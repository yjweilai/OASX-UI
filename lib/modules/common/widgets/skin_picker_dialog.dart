import 'dart:io';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:oasx/service/theme_service.dart';

/// Opens the frosted-glass skin selector dialog with preset colors,
/// custom images (auto-backed up to `skins/`), custom text color,
/// light/dark UI style toggle, card transparency, and background position controls.
Future<void> showSkinPickerDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (_) => const _SkinPickerDialog(),
  );
}

class _SkinPickerDialog extends StatelessWidget {
  const _SkinPickerDialog();

  ThemeService get _themeService => Get.find<ThemeService>();

  Future<void> _pickCustomImage(BuildContext context) async {
    if (kIsWeb) {
      Get.snackbar('提示', 'Web 端暂不支持读取本地图片路径，请在桌面端使用。');
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      dialogTitle: '选择自定义背景图片',
    );
    final path = result?.files.single.path;
    if (path == null || path.trim().isEmpty) {
      return;
    }
    await _themeService.addCustomImageSkin(path);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final panelColor =
        isDark ? const Color(0xE61A2028) : const Color(0xF2FFFFFF);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.14)
        : const Color(0xFFE2E6EE);
    final textColor = isDark ? Colors.white : const Color(0xFF111827);
    final mutedColor = isDark ? Colors.white70 : const Color(0xFF6B7280);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            width: 420,
            constraints: const BoxConstraints(maxHeight: 680),
            decoration: BoxDecoration(
              color: panelColor,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: borderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 10, 10),
                  child: Row(
                    children: [
                      Text(
                        '选择皮肤',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: textColor,
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: textColor,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                        ),
                        onPressed: () => _pickCustomImage(context),
                        icon: const Icon(
                          Icons.add_photo_alternate_outlined,
                          size: 18,
                        ),
                        label: const Text('添加'),
                      ),
                      IconButton(
                        tooltip: '关闭',
                        visualDensity: VisualDensity.compact,
                        color: mutedColor,
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded, size: 20),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: borderColor),
                Flexible(
                  child: Obx(() {
                    final activeId = _themeService.activeSkinId.value;
                    final skins = _themeService.allSkins;
                    return ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(12),
                      itemCount: skins.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final skin = skins[index];
                        final isSelected = skin.id == activeId;
                        return _SkinOptionTile(
                          skin: skin,
                          isSelected: isSelected,
                          isDarkDialog: isDark,
                          onTap: () => _themeService.selectSkin(skin.id),
                          onDelete: skin.isCustomImage
                              ? () =>
                                  _themeService.removeCustomImageSkin(skin.id)
                              : null,
                        );
                      },
                    );
                  }),
                ),
                Obx(() {
                  final active = _themeService.activeSkin;
                  final cardOpacity = _themeService.skinCardOpacity.value;
                  final overlayOpacity = _themeService.skinOverlayOpacity.value;
                  final customDark = _themeService.customSkinDarkMode.value;
                  final textColorId = _themeService.skinTextColorId.value;
                  final alignX = _themeService.skinImageAlignX.value;
                  final alignY = _themeService.skinImageAlignY.value;

                  return Container(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: borderColor)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Font color picker (Auto + Black, White, Blue, Green, Red, Yellow)
                        Row(
                          children: [
                            SizedBox(
                              width: 76,
                              child: Text(
                                '字体颜色',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: mutedColor,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: ThemeService.textColorOptions
                                    .map((option) {
                                  final selected = option.id == textColorId;
                                  if (option.color == null) {
                                    return ChoiceChip(
                                      label: Text(
                                        option.label,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      selected: selected,
                                      visualDensity: VisualDensity.compact,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      onSelected: (_) => _themeService
                                          .setSkinTextColor(option.id),
                                    );
                                  }
                                  return _TextColorDot(
                                    label: option.label,
                                    color: option.color!,
                                    selected: selected,
                                    isDarkDialog: isDark,
                                    onTap: () => _themeService
                                        .setSkinTextColor(option.id),
                                  );
                                }).toList(),
                              ),
                            ),
                          ],
                        ),
                        if (active.supportsTranslucentCards) ...[
                          const SizedBox(height: 8),
                          if (active.isCustomImage) ...[
                            Row(
                              children: [
                                SizedBox(
                                  width: 76,
                                  child: Text(
                                    '界面风格',
                                    style:
                                        theme.textTheme.labelMedium?.copyWith(
                                      color: mutedColor,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Row(
                                    children: [
                                      ChoiceChip(
                                        label: const Text('浅色文字框'),
                                        selected: !customDark,
                                        visualDensity: VisualDensity.compact,
                                        onSelected: (_) => _themeService
                                            .setCustomSkinDarkMode(false),
                                      ),
                                      const SizedBox(width: 8),
                                      ChoiceChip(
                                        label: const Text('深色文字框'),
                                        selected: customDark,
                                        visualDensity: VisualDensity.compact,
                                        onSelected: (_) => _themeService
                                            .setCustomSkinDarkMode(true),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                          ],
                          _SliderRow(
                            label: 'UI 框透明度',
                            value: cardOpacity,
                            min: 0.05,
                            max: 0.98,
                            mutedColor: mutedColor,
                            onChanged: _themeService.setSkinCardOpacity,
                          ),
                          if (active.isCustomImage) ...[
                            _SliderRow(
                              label: '背景暗度',
                              value: overlayOpacity,
                              min: 0.0,
                              max: 0.85,
                              mutedColor: mutedColor,
                              onChanged: _themeService.setSkinOverlayOpacity,
                            ),
                            const SizedBox(height: 6),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 76,
                                  child: Text(
                                    '图片位置',
                                    style:
                                        theme.textTheme.labelMedium?.copyWith(
                                      color: mutedColor,
                                    ),
                                  ),
                                ),
                                _AlignmentNineGrid(
                                  alignX: alignX,
                                  alignY: alignY,
                                  isDark: isDark,
                                  onSelect: _themeService.setSkinImageAlignment,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _CompactAxisSlider(
                                        label: '左右',
                                        value: alignX,
                                        mutedColor: mutedColor,
                                        onChanged: (v) => _themeService
                                            .setSkinImageAlignment(v, alignY),
                                      ),
                                      _CompactAxisSlider(
                                        label: '上下',
                                        value: alignY,
                                        mutedColor: mutedColor,
                                        onChanged: (v) => _themeService
                                            .setSkinImageAlignment(alignX, v),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TextColorDot extends StatelessWidget {
  const _TextColorDot({
    required this.label,
    required this.color,
    required this.selected,
    required this.isDarkDialog,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool selected;
  final bool isDarkDialog;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final checkColor =
        color.computeLuminance() > 0.55 ? Colors.black87 : Colors.white;
    return Tooltip(
      message: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? scheme.primary
                  : (isDarkDialog ? Colors.white38 : Colors.black26),
              width: selected ? 2.4 : 1.2,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.45),
                      blurRadius: 6,
                    ),
                  ]
                : const [],
          ),
          child: selected
              ? Icon(Icons.check_rounded, size: 14, color: checkColor)
              : null,
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.mutedColor,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final Color mutedColor;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(color: mutedColor),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 6.5),
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                min: min,
                max: max,
                value: value.clamp(min, max),
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 38,
            child: Text(
              '${(value * 100).round()}%',
              textAlign: TextAlign.end,
              style: theme.textTheme.labelSmall?.copyWith(color: mutedColor),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactAxisSlider extends StatelessWidget {
  const _CompactAxisSlider({
    required this.label,
    required this.value,
    required this.mutedColor,
    required this.onChanged,
  });

  final String label;
  final double value;
  final Color mutedColor;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 26,
      child: Row(
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: mutedColor),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2.5,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 5.5),
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 10),
              ),
              child: Slider(
                min: -1.0,
                max: 1.0,
                value: value.clamp(-1.0, 1.0),
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AlignmentNineGrid extends StatelessWidget {
  const _AlignmentNineGrid({
    required this.alignX,
    required this.alignY,
    required this.isDark,
    required this.onSelect,
  });

  final double alignX;
  final double alignY;
  final bool isDark;
  final void Function(double x, double y) onSelect;

  static const List<double> _stops = [-1.0, 0.0, 1.0];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.14)
              : Colors.black.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final y in _stops)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final x in _stops) _buildCell(x, y, scheme),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildCell(double x, double y, ColorScheme scheme) {
    final active = (alignX - x).abs() < 0.2 && (alignY - y).abs() < 0.2;
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () => onSelect(x, y),
      child: Container(
        width: 18,
        height: 18,
        margin: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          color: active
              ? scheme.primary
              : (isDark
                  ? Colors.white.withValues(alpha: 0.14)
                  : Colors.black.withValues(alpha: 0.12)),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}

class _SkinOptionTile extends StatelessWidget {
  const _SkinOptionTile({
    required this.skin,
    required this.isSelected,
    required this.isDarkDialog,
    required this.onTap,
    this.onDelete,
  });

  final AppSkinPreset skin;
  final bool isSelected;
  final bool isDarkDialog;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedBg = isDarkDialog
        ? Colors.white.withValues(alpha: 0.08)
        : theme.colorScheme.primary.withValues(alpha: 0.08);
    final selectedBorder = isDarkDialog
        ? Colors.white.withValues(alpha: 0.24)
        : theme.colorScheme.primary.withValues(alpha: 0.45);
    final labelColor = isDarkDialog ? Colors.white : const Color(0xFF111827);

    return Material(
      color: isSelected ? selectedBg : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? selectedBorder : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              _SkinSwatch(skin: skin),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  skin.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: labelColor,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (onDelete != null)
                SizedBox(
                  width: 30,
                  height: 30,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 17,
                    tooltip: '移除自定义背景',
                    color: isDarkDialog ? Colors.white54 : Colors.black45,
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ),
              if (isSelected) ...[
                const SizedBox(width: 4),
                const Icon(
                  Icons.check_rounded,
                  size: 18,
                  color: Color(0xFF86EFAC),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SkinSwatch extends StatelessWidget {
  const _SkinSwatch({required this.skin});

  final AppSkinPreset skin;

  @override
  Widget build(BuildContext context) {
    final border = Border.all(
      color: Colors.white.withValues(alpha: 0.35),
      width: 1,
    );
    if (skin.isCustomImage && !kIsWeb) {
      final file = File(skin.imagePath!);
      if (file.existsSync()) {
        return Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: border,
            image: DecorationImage(
              image: FileImage(file),
              fit: BoxFit.cover,
            ),
          ),
        );
      }
    }
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: border,
        color: skin.gradientColors == null ? skin.previewColor : null,
        gradient: skin.gradientColors != null
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: skin.gradientColors!,
              )
            : null,
      ),
    );
  }
}
