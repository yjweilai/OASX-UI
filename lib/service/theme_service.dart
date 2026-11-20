import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:oasx/config/theme.dart';
import 'package:oasx/modules/common/models/storage_key.dart';
import 'package:path_provider/path_provider.dart';

/// Describes a selectable text color preset for transparent/custom skins.
class AppTextColorOption {
  const AppTextColorOption({
    required this.id,
    required this.label,
    required this.color,
  });

  final String id;
  final String label;
  final Color? color;
}

/// Describes a built-in color/gradient skin or a user-selected custom image skin.
class AppSkinPreset {
  const AppSkinPreset({
    required this.id,
    required this.label,
    required this.isDark,
    required this.previewColor,
    this.gradientColors,
    this.backgroundColor,
    this.cardColor,
    this.cardBorderColor,
    this.imagePath,
  });

  final String id;
  final String label;
  final bool isDark;
  final Color previewColor;
  final List<Color>? gradientColors;
  final Color? backgroundColor;
  final Color? cardColor;
  final Color? cardBorderColor;
  final String? imagePath;

  bool get isCustomImage => imagePath != null && imagePath!.trim().isNotEmpty;

  bool get supportsTranslucentCards => isCustomImage || gradientColors != null;

  AppSkinPreset copyWith({String? imagePath}) {
    return AppSkinPreset(
      id: id,
      label: label,
      isDark: isDark,
      previewColor: previewColor,
      gradientColors: gradientColors,
      backgroundColor: backgroundColor,
      cardColor: cardColor,
      cardBorderColor: cardBorderColor,
      imagePath: imagePath ?? this.imagePath,
    );
  }

  Map<String, dynamic> toCustomJson() => {
        'id': id,
        'label': label,
        'imagePath': imagePath ?? '',
      };

  static AppSkinPreset? fromCustomJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? '').toString().trim();
    final label = (json['label'] ?? '').toString().trim();
    final path = (json['imagePath'] ?? '').toString().trim();
    if (id.isEmpty || path.isEmpty) {
      return null;
    }
    return AppSkinPreset(
      id: id,
      label: label.isEmpty ? '自定义图片' : label,
      isDark: true,
      previewColor: const Color(0xFF1F242D),
      cardColor: const Color(0xFF141820),
      cardBorderColor: const Color(0x40FFFFFF),
      imagePath: path,
    );
  }
}

class ThemeService extends GetxService {
  static const String kPureBlackId = 'pure_black';
  static const String kPureWhiteId = 'pure_white';
  static const String kAuroraId = 'aurora';
  static const String kTwilightBlueId = 'twilight_blue';

  static const List<AppTextColorOption> textColorOptions = [
    AppTextColorOption(id: 'auto', label: '自动', color: null),
    AppTextColorOption(id: 'black', label: '黑', color: Color(0xFF111827)),
    AppTextColorOption(id: 'white', label: '白', color: Color(0xFFF9FAFB)),
    AppTextColorOption(id: 'blue', label: '蓝', color: Color(0xFF38BDF8)),
    AppTextColorOption(id: 'green', label: '绿', color: Color(0xFF4ADE80)),
    AppTextColorOption(id: 'red', label: '红', color: Color(0xFFF87171)),
    AppTextColorOption(id: 'yellow', label: '黄', color: Color(0xFFFACC15)),
  ];

  static const List<AppSkinPreset> builtInSkins = [
    AppSkinPreset(
      id: kPureBlackId,
      label: '纯黑',
      isDark: true,
      previewColor: Color(0xFF0A0C10),
      backgroundColor: Color(0xFF0A0C10),
      cardColor: Color(0xFF14171D),
      cardBorderColor: Color(0xFF262A34),
    ),
    AppSkinPreset(
      id: kPureWhiteId,
      label: '纯白',
      isDark: false,
      previewColor: Color(0xFFF3F4F6),
      backgroundColor: Color(0xFFF4F5F8),
      cardColor: Colors.white,
      cardBorderColor: Color(0xFFE6E8EE),
    ),
    AppSkinPreset(
      id: kAuroraId,
      label: '极光',
      isDark: true,
      previewColor: Color(0xFF0F353C),
      gradientColors: [
        Color(0xFF0A2026),
        Color(0xFF123840),
        Color(0xFF0C1C24),
      ],
      cardColor: Color(0xFF10282F),
      cardBorderColor: Color(0x3D7DD3FC),
    ),
    AppSkinPreset(
      id: kTwilightBlueId,
      label: '暮蓝',
      isDark: true,
      previewColor: Color(0xFF1D2D46),
      gradientColors: [
        Color(0xFF142034),
        Color(0xFF1E3250),
        Color(0xFF111A2B),
      ],
      cardColor: Color(0xFF18253A),
      cardBorderColor: Color(0x3D93C5FD),
    ),
  ];

  final _storage = GetStorage();
  final _dark = false.obs;
  final _color = ColorSeed.baseColor.color.obs;
  final activeSkinId = kPureWhiteId.obs;
  final customSkins = <AppSkinPreset>[].obs;
  final skinOverlayOpacity = 0.20.obs;
  final skinCardOpacity = 0.48.obs;
  final customSkinDarkMode = false.obs;
  final skinTextColorId = 'auto'.obs;
  final skinImageAlignX = 0.0.obs;
  final skinImageAlignY = 0.0.obs;

  Directory? _cachedSkinsDir;

  bool get isDarkMode => _dark.value;
  Color get color => _color.value;

  ThemeMode get themeMode => isDarkMode ? ThemeMode.dark : ThemeMode.light;

  List<AppSkinPreset> get allSkins => [...builtInSkins, ...customSkins];

  Color? get activeTextColor {
    final id = skinTextColorId.value;
    for (final opt in textColorOptions) {
      if (opt.id == id) {
        return opt.color;
      }
    }
    return null;
  }

  AppSkinPreset get activeSkin {
    final id = activeSkinId.value;
    for (final skin in allSkins) {
      if (skin.id == id) {
        if (skin.isCustomImage) {
          final useDark = customSkinDarkMode.value;
          return AppSkinPreset(
            id: skin.id,
            label: skin.label,
            isDark: useDark,
            previewColor: skin.previewColor,
            cardColor: useDark ? const Color(0xFF141820) : Colors.white,
            cardBorderColor: useDark
                ? const Color(0x40FFFFFF)
                : const Color(0x4DFFFFFF),
            imagePath: skin.imagePath,
          );
        }
        return skin;
      }
    }
    return isDarkMode ? builtInSkins.first : builtInSkins[1];
  }

  Alignment get skinImageAlignment =>
      Alignment(skinImageAlignX.value, skinImageAlignY.value);

  @override
  void onInit() {
    _loadCustomSkins();
    final savedOpacity = _storage.read(StorageKey.skinOverlayOpacity.name);
    if (savedOpacity is num) {
      skinOverlayOpacity.value = savedOpacity.toDouble().clamp(0.0, 0.85);
    }
    final savedCardOpacity = _storage.read(StorageKey.skinCardOpacity.name);
    if (savedCardOpacity is num) {
      skinCardOpacity.value = savedCardOpacity.toDouble().clamp(0.05, 0.98);
    }
    final savedTextColorId =
        (_storage.read(StorageKey.skinTextColorId.name) ?? '').toString().trim();
    if (savedTextColorId.isNotEmpty &&
        textColorOptions.any((o) => o.id == savedTextColorId)) {
      skinTextColorId.value = savedTextColorId;
    }
    final savedAlignX = _storage.read(StorageKey.skinImageAlignX.name);
    if (savedAlignX is num) {
      skinImageAlignX.value = savedAlignX.toDouble().clamp(-1.0, 1.0);
    }
    final savedAlignY = _storage.read(StorageKey.skinImageAlignY.name);
    if (savedAlignY is num) {
      skinImageAlignY.value = savedAlignY.toDouble().clamp(-1.0, 1.0);
    }

    final savedDark = _storage.read(StorageKey.dark.name) ?? false;
    final savedCustomDark = _storage.read(StorageKey.skinCustomDarkMode.name);
    customSkinDarkMode.value =
        savedCustomDark is bool ? savedCustomDark : savedDark;

    final savedSkinId =
        (_storage.read(StorageKey.skinPresetId.name) ?? '').toString().trim();
    if (savedSkinId.isNotEmpty && allSkins.any((s) => s.id == savedSkinId)) {
      activeSkinId.value = savedSkinId;
      _dark.value = activeSkin.isDark;
    } else {
      _dark.value = savedDark;
      activeSkinId.value = savedDark ? kPureBlackId : kPureWhiteId;
    }
    switchTheme(_dark.value);
    unawaited(_migrateExistingCustomSkins());
    super.onInit();
  }

  void switchTheme([bool? dark]) {
    _dark.value = dark ?? !_dark.value;
    _storage.write(StorageKey.dark.name, _dark.value);
    if (_dark.value && activeSkinId.value == kPureWhiteId) {
      activeSkinId.value = kPureBlackId;
      _storage.write(StorageKey.skinPresetId.name, activeSkinId.value);
    } else if (!_dark.value && activeSkinId.value == kPureBlackId) {
      activeSkinId.value = kPureWhiteId;
      _storage.write(StorageKey.skinPresetId.name, activeSkinId.value);
    } else if (activeSkin.isCustomImage) {
      customSkinDarkMode.value = _dark.value;
      _storage.write(StorageKey.skinCustomDarkMode.name, _dark.value);
    }
    Get.changeThemeMode(themeMode);
  }

  void setCustomSkinDarkMode(bool dark) {
    customSkinDarkMode.value = dark;
    _storage.write(StorageKey.skinCustomDarkMode.name, dark);
    if (activeSkin.isCustomImage) {
      _dark.value = dark;
      _storage.write(StorageKey.dark.name, dark);
      Get.changeThemeMode(themeMode);
    }
  }

  void setSkinTextColor(String colorId) {
    if (!textColorOptions.any((o) => o.id == colorId)) {
      return;
    }
    skinTextColorId.value = colorId;
    _storage.write(StorageKey.skinTextColorId.name, colorId);
  }

  void selectSkin(String skinId) {
    final matches = allSkins.where((s) => s.id == skinId);
    if (matches.isEmpty) {
      return;
    }
    final target = matches.first;
    activeSkinId.value = target.id;
    _storage.write(StorageKey.skinPresetId.name, target.id);
    final nextDark =
        target.isCustomImage ? customSkinDarkMode.value : target.isDark;
    _dark.value = nextDark;
    _storage.write(StorageKey.dark.name, nextDark);
    Get.changeThemeMode(themeMode);
  }

  void setSkinOverlayOpacity(double value) {
    final clamped = value.clamp(0.0, 0.85).toDouble();
    skinOverlayOpacity.value = clamped;
    _storage.write(StorageKey.skinOverlayOpacity.name, clamped);
  }

  void setSkinCardOpacity(double value) {
    final clamped = value.clamp(0.05, 0.98).toDouble();
    skinCardOpacity.value = clamped;
    _storage.write(StorageKey.skinCardOpacity.name, clamped);
  }

  void setSkinImageAlignment(double x, double y) {
    final cx = x.clamp(-1.0, 1.0).toDouble();
    final cy = y.clamp(-1.0, 1.0).toDouble();
    skinImageAlignX.value = cx;
    skinImageAlignY.value = cy;
    _storage.write(StorageKey.skinImageAlignX.name, cx);
    _storage.write(StorageKey.skinImageAlignY.name, cy);
  }

  /// Resolves the managed `skins/` directory (preferring next to oasx.exe,
  /// falling back to application support directory if not writable).
  Future<Directory?> _resolveSkinsDir() async {
    if (kIsWeb) {
      return null;
    }
    if (_cachedSkinsDir != null && _cachedSkinsDir!.existsSync()) {
      return _cachedSkinsDir;
    }
    final sep = Platform.pathSeparator;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      try {
        final exeDir = File(Platform.resolvedExecutable).parent;
        final candidate = Directory('${exeDir.path}${sep}skins');
        if (!candidate.existsSync()) {
          candidate.createSync(recursive: true);
        }
        // Verify write permission with a tiny probe file.
        final probe = File('${candidate.path}$sep.write_test');
        probe.writeAsStringSync('ok');
        probe.deleteSync();
        _cachedSkinsDir = candidate;
        return candidate;
      } catch (_) {}
    }
    try {
      final supportDir = await getApplicationSupportDirectory();
      final fallback = Directory('${supportDir.path}${sep}skins');
      if (!fallback.existsSync()) {
        fallback.createSync(recursive: true);
      }
      _cachedSkinsDir = fallback;
      return fallback;
    } catch (_) {
      return null;
    }
  }

  /// Copies a local image file into the managed `skins/` directory so deleting
  /// the original file on disk will never break the custom background.
  Future<String> _copyIntoManagedSkinsDir(String sourcePath) async {
    if (kIsWeb) {
      return sourcePath;
    }
    final sourceFile = File(sourcePath);
    if (!sourceFile.existsSync()) {
      return sourcePath;
    }
    final skinsDir = await _resolveSkinsDir();
    if (skinsDir == null) {
      return sourcePath;
    }
    final normalizedSkinsPath = skinsDir.path.toLowerCase();
    if (sourceFile.parent.path.toLowerCase() == normalizedSkinsPath) {
      return sourcePath;
    }
    final baseName = sourcePath.split(RegExp(r'[/\\]')).last;
    final dotIndex = baseName.lastIndexOf('.');
    final ext = dotIndex > 0 ? baseName.substring(dotIndex) : '.png';
    final rawStem = dotIndex > 0 ? baseName.substring(0, dotIndex) : baseName;
    final safeStem = rawStem.replaceAll(RegExp(r'[^\w\u4e00-\u9fa5-]'), '_');
    final fileName =
        'skin_${DateTime.now().millisecondsSinceEpoch}_$safeStem$ext';
    final destPath = '${skinsDir.path}${Platform.pathSeparator}$fileName';
    try {
      await sourceFile.copy(destPath);
      return destPath;
    } catch (_) {
      return sourcePath;
    }
  }

  Future<void> _migrateExistingCustomSkins() async {
    if (kIsWeb || customSkins.isEmpty) {
      return;
    }
    final skinsDir = await _resolveSkinsDir();
    if (skinsDir == null) {
      return;
    }
    final normalizedSkinsPath = skinsDir.path.toLowerCase();
    var changed = false;
    final updated = <AppSkinPreset>[];
    for (final skin in customSkins) {
      final path = skin.imagePath;
      if (path != null && path.isNotEmpty) {
        final file = File(path);
        if (file.existsSync() &&
            file.parent.path.toLowerCase() != normalizedSkinsPath) {
          final copied = await _copyIntoManagedSkinsDir(path);
          if (copied != path) {
            updated.add(skin.copyWith(imagePath: copied));
            changed = true;
            continue;
          }
        }
      }
      updated.add(skin);
    }
    if (changed) {
      customSkins.assignAll(updated);
      _saveCustomSkins();
    }
  }

  Future<AppSkinPreset?> addCustomImageSkin(String path, {String? name}) async {
    final normalizedPath = path.trim();
    if (normalizedPath.isEmpty) {
      return null;
    }
    if (!kIsWeb && !File(normalizedPath).existsSync()) {
      return null;
    }
    final existingMatches =
        customSkins.where((s) => s.imagePath == normalizedPath);
    if (existingMatches.isNotEmpty) {
      final existing = existingMatches.first;
      selectSkin(existing.id);
      return existing;
    }
    // Preserve current light/dark preference when first adding a custom image.
    customSkinDarkMode.value = _dark.value;
    _storage.write(StorageKey.skinCustomDarkMode.name, _dark.value);

    final fileName = normalizedPath
        .split(RegExp(r'[/\\]'))
        .last
        .replaceAll(RegExp(r'\.[^.]+$'), '');
    final displayName = (name != null && name.trim().isNotEmpty)
        ? name.trim()
        : (fileName.isEmpty ? '自定义图片' : fileName);

    final storedPath = await _copyIntoManagedSkinsDir(normalizedPath);

    final preset = AppSkinPreset(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      label: displayName,
      isDark: customSkinDarkMode.value,
      previewColor: const Color(0xFF1F242D),
      cardColor: customSkinDarkMode.value
          ? const Color(0xFF141820)
          : Colors.white,
      cardBorderColor: const Color(0x40FFFFFF),
      imagePath: storedPath,
    );
    customSkins.add(preset);
    _saveCustomSkins();
    selectSkin(preset.id);
    return preset;
  }

  void removeCustomImageSkin(String id) {
    final removedList = customSkins.where((s) => s.id == id).toList();
    customSkins.removeWhere((s) => s.id == id);
    _saveCustomSkins();
    if (activeSkinId.value == id) {
      selectSkin(kPureWhiteId);
    }
    if (!kIsWeb && removedList.isNotEmpty) {
      unawaited(_deleteManagedSkinFile(removedList.first.imagePath));
    }
  }

  Future<void> _deleteManagedSkinFile(String? imagePath) async {
    if (imagePath == null || imagePath.trim().isEmpty) {
      return;
    }
    final skinsDir = await _resolveSkinsDir();
    if (skinsDir == null) {
      return;
    }
    try {
      final file = File(imagePath);
      if (file.existsSync() &&
          file.parent.path.toLowerCase() == skinsDir.path.toLowerCase()) {
        await file.delete();
      }
    } catch (_) {}
  }

  void _loadCustomSkins() {
    final raw = _storage.read(StorageKey.customSkins.name);
    if (raw == null) {
      return;
    }
    try {
      final decoded = raw is String ? jsonDecode(raw) : raw;
      if (decoded is! List) {
        return;
      }
      final loaded = <AppSkinPreset>[];
      for (final item in decoded) {
        if (item is Map) {
          final parsed =
              AppSkinPreset.fromCustomJson(Map<String, dynamic>.from(item));
          if (parsed != null) {
            loaded.add(parsed);
          }
        }
      }
      customSkins.assignAll(loaded);
    } catch (_) {}
  }

  void _saveCustomSkins() {
    _storage.write(
      StorageKey.customSkins.name,
      jsonEncode(customSkins.map((s) => s.toCustomJson()).toList()),
    );
  }
}
