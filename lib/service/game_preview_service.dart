import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:oasx/api/api_client.dart';
import 'package:oasx/modules/common/models/storage_key.dart';

/// Capture source mode for live game screen preview.
enum GamePreviewMode {
  adb,
  windowsWindow,
}

/// Captures quasi-realtime game frames via local ADB (for emulators)
/// or Windows native PrintWindow API (for PC desktop clients),
/// with per-script window binding and automatic sync on config switch.
class GamePreviewService extends GetxService {
  static const String _kScriptWindowMapKey = 'game_preview_window_map_v1';

  final GetStorage _storage = GetStorage();

  final mode = GamePreviewMode.adb.obs;
  final isStreaming = false.obs;
  final isCapturing = false.obs;
  final intervalSeconds = 2.obs;
  final frameBytes = Rxn<Uint8List>();
  final lastError = ''.obs;
  final adbPath = ''.obs;
  final serial = ''.obs;
  final windowTitle = '阴阳师'.obs;
  final availableWindows = <String>[].obs;

  Timer? _timer;
  bool _inFlight = false;
  int _captureGeneration = 0;
  String _activeScript = '';
  final Map<String, String> _scriptSerialCache = {};
  final Map<String, String> _scriptWindowMap = {};

  @override
  void onInit() {
    final savedMode =
        (_storage.read(StorageKey.gamePreviewMode.name) ?? '').toString();
    if (savedMode == GamePreviewMode.windowsWindow.name) {
      mode.value = GamePreviewMode.windowsWindow;
    }
    final savedAdb =
        (_storage.read(StorageKey.gamePreviewAdbPath.name) ?? '').toString();
    adbPath.value = savedAdb.trim();

    _loadScriptWindowMap();

    final savedWindow =
        (_storage.read(StorageKey.gamePreviewWindowTitle.name) ?? '')
            .toString()
            .trim();
    if (savedWindow.isNotEmpty) {
      windowTitle.value = savedWindow;
    }

    final savedInterval =
        _storage.read(StorageKey.gamePreviewIntervalSeconds.name);
    if (savedInterval is int && savedInterval >= 1 && savedInterval <= 10) {
      intervalSeconds.value = savedInterval;
    }
    super.onInit();
  }

  @override
  void onClose() {
    stopPolling();
    super.onClose();
  }

  void _loadScriptWindowMap() {
    final raw = _storage.read(_kScriptWindowMapKey);
    if (raw == null) {
      return;
    }
    try {
      final decoded = raw is String ? jsonDecode(raw) : raw;
      if (decoded is Map) {
        for (final entry in decoded.entries) {
          final k = entry.key.toString().trim();
          final v = (entry.value ?? '').toString().trim();
          if (k.isNotEmpty && v.isNotEmpty) {
            _scriptWindowMap[k] = v;
          }
        }
      }
    } catch (_) {}
  }

  void _saveScriptWindowMap() {
    _storage.write(_kScriptWindowMapKey, jsonEncode(_scriptWindowMap));
  }

  void setMode(GamePreviewMode nextMode) {
    if (mode.value == nextMode) {
      return;
    }
    mode.value = nextMode;
    _storage.write(StorageKey.gamePreviewMode.name, nextMode.name);
    lastError.value = '';
    if (nextMode == GamePreviewMode.windowsWindow) {
      if (_activeScript.isNotEmpty) {
        windowTitle.value = _resolveWindowTitleForScript(_activeScript);
      }
      unawaited(scanWindows());
    }
    if (isStreaming.value && _activeScript.isNotEmpty) {
      unawaited(captureOnce(_activeScript));
    }
  }

  void setAdbPath(String value) {
    final normalized = value.trim();
    adbPath.value = normalized;
    _storage.write(StorageKey.gamePreviewAdbPath.name, normalized);
  }

  void setSerial(String value, {String? scriptName}) {
    final normalized = value.trim();
    serial.value = normalized;
    final target = (scriptName ?? _activeScript).trim();
    if (target.isNotEmpty && normalized.isNotEmpty) {
      _scriptSerialCache[target] = normalized;
    }
  }

  void setWindowTitle(String value, {String? scriptName}) {
    final normalized = value.trim();
    final target = (scriptName ?? _activeScript).trim();
    final resolved =
        normalized.isEmpty ? (target.isNotEmpty ? target : '阴阳师') : normalized;
    windowTitle.value = resolved;
    _storage.write(StorageKey.gamePreviewWindowTitle.name, resolved);
    if (target.isNotEmpty) {
      _scriptWindowMap[target] = resolved;
      _saveScriptWindowMap();
    }
  }

  String _resolveWindowTitleForScript(String scriptName) {
    final normalized = scriptName.trim();
    if (normalized.isEmpty) {
      return windowTitle.value.trim().isEmpty ? '阴阳师' : windowTitle.value.trim();
    }
    final mapped = _scriptWindowMap[normalized];
    if (mapped != null && mapped.trim().isNotEmpty) {
      return mapped.trim();
    }
    // Default to matching the window with the same name as the active config (e.g. p1, p2, p3).
    return normalized;
  }

  void setIntervalSeconds(int seconds) {
    final clamped = seconds.clamp(1, 10);
    intervalSeconds.value = clamped;
    _storage.write(StorageKey.gamePreviewIntervalSeconds.name, clamped);
    if (isStreaming.value && _activeScript.isNotEmpty) {
      _restartTimer();
    }
  }

  /// Syncs the active script name, switches per-script serial & window title,
  /// clears the previous script's stale frame, and immediately captures a fresh frame.
  Future<void> bindScript(String scriptName) async {
    final normalized = scriptName.trim();
    if (normalized.isEmpty || normalized == _activeScript) {
      return;
    }
    _activeScript = normalized;
    _captureGeneration++;
    frameBytes.value = null;
    lastError.value = '';

    // Always sync per-script window title so switching p1 -> p2 immediately follows p2.
    windowTitle.value = _resolveWindowTitleForScript(normalized);

    final cached = _scriptSerialCache[normalized];
    if (cached != null && cached.isNotEmpty) {
      serial.value = cached;
    } else if (mode.value == GamePreviewMode.adb) {
      await resolveSerialForScript(normalized);
    }

    if (isStreaming.value) {
      unawaited(captureOnce(normalized));
    }
  }

  /// Reads `device.serial` from the active OAS script configuration.
  Future<String> resolveSerialForScript(String scriptName) async {
    final normalized = scriptName.trim();
    if (normalized.isEmpty) {
      return serial.value;
    }
    try {
      final raw = await ApiClient().getScriptTask(normalized, 'Script');
      final found = _extractSerialFromArgs(raw);
      if (found != null && found.isNotEmpty) {
        _scriptSerialCache[normalized] = found;
        serial.value = found;
        return found;
      }
    } catch (_) {}
    return serial.value;
  }

  String? _extractSerialFromArgs(Map<String, dynamic> args) {
    for (final entry in args.entries) {
      final key = entry.key.toLowerCase();
      final val = entry.value;
      if (key == 'serial') {
        if (val is Map && val['value'] != null) {
          final text = val['value'].toString().trim();
          if (text.isNotEmpty) return text;
        } else if (val is String && val.trim().isNotEmpty) {
          return val.trim();
        }
      }
      if (val is Map) {
        final nested = _extractSerialFromArgs(Map<String, dynamic>.from(val));
        if (nested != null && nested.isNotEmpty) {
          return nested;
        }
      }
    }
    return null;
  }

  void togglePolling(String scriptName) {
    if (isStreaming.value) {
      stopPolling();
    } else {
      startPolling(scriptName);
    }
  }

  void startPolling(String scriptName) {
    final normalized = scriptName.trim();
    if (normalized.isNotEmpty) {
      _activeScript = normalized;
      if (mode.value == GamePreviewMode.windowsWindow) {
        windowTitle.value = _resolveWindowTitleForScript(normalized);
      }
    }
    if (kIsWeb) {
      lastError.value = 'Web 端不支持本地游戏画面抓取，请在 Windows 桌面端使用';
      return;
    }
    isStreaming.value = true;
    lastError.value = '';
    unawaited(_bootstrapAndCapture());
    _restartTimer();
  }

  Future<void> _bootstrapAndCapture() async {
    if (mode.value == GamePreviewMode.adb &&
        serial.value.trim().isEmpty &&
        _activeScript.isNotEmpty) {
      await resolveSerialForScript(_activeScript);
    }
    await captureOnce(_activeScript);
  }

  void stopPolling() {
    _timer?.cancel();
    _timer = null;
    isStreaming.value = false;
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(
      Duration(seconds: intervalSeconds.value),
      (_) {
        if (!isStreaming.value) {
          return;
        }
        unawaited(captureOnce(_activeScript));
      },
    );
  }

  Future<void> captureOnce(String scriptName) async {
    if (kIsWeb) {
      lastError.value = 'Web 端不支持本地游戏画面抓取';
      return;
    }
    if (_inFlight) {
      return;
    }
    final generation = _captureGeneration;
    _inFlight = true;
    isCapturing.value = true;
    try {
      final bytes = switch (mode.value) {
        GamePreviewMode.adb => await _captureViaAdb(scriptName),
        GamePreviewMode.windowsWindow => await _captureViaWindowsWindow(),
      };
      if (generation != _captureGeneration) {
        return;
      }
      if (bytes != null && bytes.length > 16) {
        frameBytes.value = bytes;
        lastError.value = '';
      }
    } catch (error) {
      if (generation == _captureGeneration) {
        lastError.value = error.toString().replaceFirst('Exception: ', '');
      }
    } finally {
      _inFlight = false;
      isCapturing.value = false;
    }
  }

  /// Scans open Windows top-level window titles for desktop client selection.
  Future<void> scanWindows() async {
    if (kIsWeb || !Platform.isWindows) {
      return;
    }
    try {
      final res = await Process.run(
        'powershell',
        const [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          r"[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; Get-Process | Where-Object { $_.MainWindowTitle -ne '' } | Select-Object -ExpandProperty MainWindowTitle | Sort-Object -Unique",
        ],
        stdoutEncoding: utf8,
      );
      if (res.exitCode == 0) {
        final lines = res.stdout
            .toString()
            .split(RegExp(r'\r?\n'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        availableWindows.assignAll(lines);
      }
    } catch (_) {}
  }

  String _resolveAdbExecutable() {
    final custom = adbPath.value.trim();
    if (custom.isNotEmpty && File(custom).existsSync()) {
      return custom;
    }
    final rootPath =
        (_storage.read(StorageKey.rootPathServer.name) ?? '').toString().trim();
    if (rootPath.isNotEmpty) {
      final candidates = [
        '$rootPath\\toolkit\\Lib\\site-packages\\adbutils\\binaries\\adb.exe',
        '$rootPath\\toolkit\\adb\\adb.exe',
        '$rootPath\\bin\\adb\\adb.exe',
      ];
      for (final candidate in candidates) {
        if (File(candidate).existsSync()) {
          return candidate;
        }
      }
    }
    return 'adb';
  }

  Future<Uint8List?> _captureViaAdb(String scriptName) async {
    var targetSerial = serial.value.trim();
    if (targetSerial.isEmpty && scriptName.trim().isNotEmpty) {
      targetSerial = await resolveSerialForScript(scriptName);
    }
    final adbExe = _resolveAdbExecutable();
    final args = <String>[
      if (targetSerial.isNotEmpty) ...['-s', targetSerial],
      'exec-out',
      'screencap',
      '-p',
    ];
    final result = await Process.run(
      adbExe,
      args,
      stdoutEncoding: null,
    ).timeout(const Duration(seconds: 6));
    if (result.exitCode != 0) {
      final err = result.stderr.toString().trim();
      throw Exception(
        err.isEmpty ? 'ADB 截屏失败，请检查串口或 adb.exe 路径' : err,
      );
    }
    final raw = result.stdout;
    if (raw is! List<int> || raw.length < 8) {
      throw Exception('未收到有效画面数据，请确认模拟器已运行');
    }
    final bytes = Uint8List.fromList(raw);
    if (bytes[0] != 0x89 ||
        bytes[1] != 0x50 ||
        bytes[2] != 0x4E ||
        bytes[3] != 0x47) {
      throw Exception('ADB 返回数据格式异常，请检查模拟器串口');
    }
    return bytes;
  }

  Future<Uint8List?> _captureViaWindowsWindow() async {
    if (!Platform.isWindows) {
      throw Exception('桌面版窗口抓取仅支持 Windows 系统');
    }
    final titleKeyword = windowTitle.value.trim().isEmpty
        ? '阴阳师'
        : windowTitle.value.trim();
    final escaped = titleKeyword.replaceAll("'", "''");
    final script = '''
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinCap {
  [StructLayout(LayoutKind.Sequential)]
  public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint nFlags);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
}
"@
\$kw = '$escaped'
\$procs = Get-Process | Where-Object { \$_.MainWindowHandle -ne 0 -and \$_.MainWindowTitle -ne '' }
\$proc = \$procs | Where-Object { \$_.MainWindowTitle -eq \$kw } | Select-Object -First 1
if (-not \$proc) {
  \$proc = \$procs | Where-Object { \$_.MainWindowTitle -like "*\$kw*" } | Select-Object -First 1
}
if (-not \$proc) { Write-Error "WINDOW_NOT_FOUND"; exit 2 }
\$hwnd = \$proc.MainWindowHandle
if ([WinCap]::IsIconic(\$hwnd)) { Write-Error "WINDOW_MINIMIZED"; exit 3 }
\$rect = New-Object WinCap+RECT
[WinCap]::GetWindowRect(\$hwnd, [ref]\$rect) | Out-Null
\$w = \$rect.Right - \$rect.Left
\$h = \$rect.Bottom - \$rect.Top
if (\$w -le 0 -or \$h -le 0) { Write-Error "INVALID_SIZE"; exit 4 }
\$bmp = New-Object System.Drawing.Bitmap(\$w, \$h)
\$g = [System.Drawing.Graphics]::FromImage(\$bmp)
\$hdc = \$g.GetHdc()
\$ok = [WinCap]::PrintWindow(\$hwnd, \$hdc, 2)
if (-not \$ok) { [WinCap]::PrintWindow(\$hwnd, \$hdc, 0) | Out-Null }
\$g.ReleaseHdc(\$hdc)
\$g.Dispose()
\$ms = New-Object System.IO.MemoryStream
\$bmp.Save(\$ms, [System.Drawing.Imaging.ImageFormat]::Png)
\$bmp.Dispose()
[Convert]::ToBase64String(\$ms.ToArray())
\$ms.Dispose()
''';
    final result = await Process.run(
      'powershell',
      ['-NoProfile', '-NonInteractive', '-Command', script],
      stdoutEncoding: utf8,
    ).timeout(const Duration(seconds: 6));

    if (result.exitCode == 2) {
      throw Exception('未找到标题为「$titleKeyword」的窗口');
    }
    if (result.exitCode == 3) {
      throw Exception('游戏窗口已最小化，请还原窗口（可被遮挡但不能最小化）');
    }
    if (result.exitCode != 0) {
      throw Exception('窗口抓图失败，请确认游戏已打开');
    }
    final b64 = result.stdout.toString().trim();
    if (b64.isEmpty) {
      throw Exception('未获取到窗口画面');
    }
    return base64Decode(b64);
  }
}
