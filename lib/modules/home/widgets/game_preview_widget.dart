import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:oasx/service/game_preview_service.dart';

/// Compact embedded game screen preview placed on the left side of the top-right card.
class GamePreviewThumbnail extends StatefulWidget {
  const GamePreviewThumbnail({
    super.key,
    required this.scriptName,
  });

  final String scriptName;

  @override
  State<GamePreviewThumbnail> createState() => _GamePreviewThumbnailState();
}

class _GamePreviewThumbnailState extends State<GamePreviewThumbnail> {
  bool _hovered = false;

  GamePreviewService get _service => Get.find<GamePreviewService>();

  @override
  void initState() {
    super.initState();
    unawaited(_service.bindScript(widget.scriptName));
  }

  @override
  void didUpdateWidget(covariant GamePreviewThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scriptName != widget.scriptName) {
      unawaited(_service.bindScript(widget.scriptName));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Obx(() {
        final bytes = _service.frameBytes.value;
        final isStreaming = _service.isStreaming.value;
        final isCapturing = _service.isCapturing.value;
        final errorText = _service.lastError.value;

        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.32)
                  : Colors.black.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.55),
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (bytes != null)
                  GestureDetector(
                    onTap: () => _openPreviewModal(context),
                    child: Image.memory(
                      bytes,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.medium,
                    ),
                  )
                else
                  InkWell(
                    onTap: () {
                      if (!isStreaming) {
                        _service.startPolling(widget.scriptName);
                      } else {
                        _openPreviewModal(context);
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            isCapturing
                                ? Icons.hourglass_top_rounded
                                : Icons.monitor_rounded,
                            size: 24,
                            color: errorText.isNotEmpty
                                ? scheme.error
                                : scheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            errorText.isNotEmpty
                                ? errorText
                                : (isStreaming ? '正在获取游戏画面...' : '点击开启画面预览'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: errorText.isNotEmpty
                                  ? scheme.error
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                // Top-right quick controls on hover or when idle/error
                Positioned(
                  top: 5,
                  right: 5,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 140),
                    opacity: (_hovered || bytes == null) ? 1.0 : 0.0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.56),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _MiniOverlayButton(
                            icon: isStreaming
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            tooltip: isStreaming ? '暂停预览' : '开始预览',
                            onTap: () =>
                                _service.togglePolling(widget.scriptName),
                          ),
                          _MiniOverlayButton(
                            icon: Icons.refresh_rounded,
                            tooltip: '立即刷新',
                            onTap: () =>
                                _service.captureOnce(widget.scriptName),
                          ),
                          _MiniOverlayButton(
                            icon: Icons.open_in_full_rounded,
                            tooltip: '放大与设置',
                            onTap: () => _openPreviewModal(context),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Subtle LIVE badge when streaming
                if (isStreaming && bytes != null)
                  Positioned(
                    left: 6,
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.52),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF22C55E),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _service.mode.value == GamePreviewMode.adb
                                ? 'ADB'
                                : '窗口',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Future<void> _openPreviewModal(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => _GamePreviewModalDialog(scriptName: widget.scriptName),
    );
  }
}

class _MiniOverlayButton extends StatelessWidget {
  const _MiniOverlayButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(icon, size: 14, color: Colors.white),
        ),
      ),
    );
  }
}

class _GamePreviewModalDialog extends StatefulWidget {
  const _GamePreviewModalDialog({required this.scriptName});

  final String scriptName;

  @override
  State<_GamePreviewModalDialog> createState() =>
      _GamePreviewModalDialogState();
}

class _GamePreviewModalDialogState extends State<_GamePreviewModalDialog> {
  late final TextEditingController _serialCtrl;
  late final TextEditingController _windowCtrl;

  GamePreviewService get _service => Get.find<GamePreviewService>();

  @override
  void initState() {
    super.initState();
    _serialCtrl = TextEditingController(text: _service.serial.value);
    _windowCtrl = TextEditingController(text: _service.windowTitle.value);
    if (_service.mode.value == GamePreviewMode.windowsWindow) {
      unawaited(_service.scanWindows());
    }
  }

  @override
  void dispose() {
    _serialCtrl.dispose();
    _windowCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAdbExe() async {
    if (kIsWeb) return;
    final res = await FilePicker.platform.pickFiles(
      dialogTitle: '选择 adb.exe',
      type: FileType.custom,
      allowedExtensions: const ['exe'],
    );
    final path = res?.files.single.path;
    if (path != null && path.trim().isNotEmpty) {
      _service.setAdbPath(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 820,
        height: 600,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.monitor_rounded, size: 20, color: scheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    '游戏画面预览 · ${widget.scriptName}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Obx(() {
                    final streaming = _service.isStreaming.value;
                    return FilledButton.tonalIcon(
                      onPressed: () =>
                          _service.togglePolling(widget.scriptName),
                      icon: Icon(
                        streaming
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 18,
                      ),
                      label: Text(streaming ? '暂停' : '开始预览'),
                    );
                  }),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => _service.captureOnce(widget.scriptName),
                    icon: const Icon(Icons.refresh_rounded, size: 17),
                    label: const Text('刷新'),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Obx(() {
                final currentMode = _service.mode.value;
                final interval = _service.intervalSeconds.value;
                return Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ChoiceChip(
                      label: const Text('模拟器 (ADB)'),
                      selected: currentMode == GamePreviewMode.adb,
                      onSelected: (_) => _service.setMode(GamePreviewMode.adb),
                    ),
                    if (!kIsWeb && Platform.isWindows)
                      ChoiceChip(
                        label: const Text('桌面版窗口'),
                        selected: currentMode == GamePreviewMode.windowsWindow,
                        onSelected: (_) =>
                            _service.setMode(GamePreviewMode.windowsWindow),
                      ),
                    const SizedBox(width: 8),
                    Text(
                      '刷新频率:',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    for (final sec in const [1, 2, 3, 5])
                      ChoiceChip(
                        label: Text('${sec}s'),
                        selected: interval == sec,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => _service.setIntervalSeconds(sec),
                      ),
                  ],
                );
              }),
              const SizedBox(height: 10),
              Obx(() {
                final currentMode = _service.mode.value;
                if (currentMode == GamePreviewMode.adb) {
                  return Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _serialCtrl,
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: '模拟器串口 (如 127.0.0.1:16384)',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (v) => _service.setSerial(
                            v,
                            scriptName: widget.scriptName,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () async {
                          final resolved = await _service
                              .resolveSerialForScript(widget.scriptName);
                          if (mounted && resolved.isNotEmpty) {
                            _serialCtrl.text = resolved;
                          }
                        },
                        child: const Text('读取配置串口'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _pickAdbExe,
                        icon: const Icon(Icons.folder_open_rounded, size: 16),
                        label: Text(
                          _service.adbPath.value.isEmpty
                              ? '指定 adb.exe'
                              : '已选 adb',
                        ),
                      ),
                    ],
                  );
                }
                final windows = _service.availableWindows;
                return Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _windowCtrl,
                        decoration: const InputDecoration(
                          isDense: true,
                          labelText: '游戏窗口标题关键词 (默认 阴阳师)',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) => _service.setWindowTitle(v, scriptName: widget.scriptName),
                      ),
                    ),
                    const SizedBox(width: 8),
                    PopupMenuButton<String>(
                      tooltip: '从当前窗口选择',
                      onSelected: (title) {
                        _windowCtrl.text = title;
                        _service.setWindowTitle(title, scriptName: widget.scriptName);
                        unawaited(_service.captureOnce(widget.scriptName));
                      },
                      itemBuilder: (_) => windows
                          .map(
                            (title) => PopupMenuItem<String>(
                              value: title,
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      child: OutlinedButton.icon(
                        onPressed: null,
                        icon: const Icon(Icons.window_rounded, size: 16),
                        label: Text('选择窗口 (${windows.length})'),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: '重新扫描窗口',
                      onPressed: _service.scanWindows,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                    ),
                  ],
                );
              }),
              const SizedBox(height: 12),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.85),
                    child: Obx(() {
                      final bytes = _service.frameBytes.value;
                      final err = _service.lastError.value;
                      if (bytes == null) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              err.isNotEmpty
                                  ? err
                                  : '点击右上角「开始预览」或「刷新」获取当前游戏画面',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ),
                        );
                      }
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          InteractiveViewer(
                            minScale: 0.5,
                            maxScale: 4.0,
                            child: Center(
                              child: Image.memory(
                                bytes,
                                fit: BoxFit.contain,
                                gaplessPlayback: true,
                              ),
                            ),
                          ),
                          if (err.isNotEmpty)
                            Positioned(
                              left: 12,
                              right: 12,
                              bottom: 12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.82),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  err,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    }),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
