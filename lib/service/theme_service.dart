import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:oasx/config/theme.dart';
import 'package:oasx/modules/common/models/storage_key.dart';

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
  final skinOverlayOpacity = 0.25.obs;
  final skinCardOpacity = 0.52.obs;
  final skinImageAlignX = 0.0.obs;
  final skinImageAlignY = 0.0.obs;

  bool get isDarkMode => _dark.value;
  Color get color => _color.value;

  ThemeMode get themeMode => isDarkMode ? ThemeMode.dark : ThemeMode.light;

  List<AppSkinPreset> get allSkins => [...builtInSkins, ...customSkins];

  AppSkinPreset get activeSkin {
    final id = activeSkinId.value;
    for (final skin in allSkins) {
      if (skin.id == id) {
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
    final savedAlignX = _storage.read(StorageKey.skinImageAlignX.name);
    if (savedAlignX is num) {
      skinImageAlignX.value = savedAlignX.toDouble().clamp(-1.0, 1.0);
    }
    final savedAlignY = _storage.read(StorageKey.skinImageAlignY.name);
    if (savedAlignY is num) {
      skinImageAlignY.value = savedAlignY.toDouble().clamp(-1.0, 1.0);
    }

    final savedDark = _storage.read(StorageKey.dark.name) ?? false;
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
    }
    Get.changeThemeMode(themeMode);
  }

  void selectSkin(String skinId) {
    final matches = allSkins.where((s) => s.id == skinId);
    if (matches.isEmpty) {
      return;
    }
    final target = matches.first;
    activeSkinId.value = target.id;
    _storage.write(StorageKey.skinPresetId.name, target.id);
    _dark.value = target.isDark;
    _storage.write(StorageKey.dark.name, _dark.value);
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

  AppSkinPreset? addCustomImageSkin(String path, {String? name}) {
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
    final fileName = normalizedPath
        .split(RegExp(r'[/\\]'))
        .last
        .replaceAll(RegExp(r'\.[^.]+$'), '');
    final displayName = (name != null && name.trim().isNotEmpty)
        ? name.trim()
        : (fileName.isEmpty ? '自定义图片' : fileName);
    final preset = AppSkinPreset(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      label: displayName,
      isDark: true,
      previewColor: const Color(0xFF1F242D),
      cardColor: const Color(0xFF141820),
      cardBorderColor: const Color(0x40FFFFFF),
      imagePath: normalizedPath,
    );
    customSkins.add(preset);
    _saveCustomSkins();
    selectSkin(preset.id);
    return preset;
  }

  void removeCustomImageSkin(String id) {
    customSkins.removeWhere((s) => s.id == id);
    _saveCustomSkins();
    if (activeSkinId.value == id) {
      selectSkin(kPureWhiteId);
    }
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
