import 'dart:io';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:oasx/service/theme_service.dart';

/// Opens the frosted-glass skin selector dialog with preset colors and custom images.
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
    _themeService.addCustomImageSkin(path);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final panelColor = isDark
        ? const Color(0xE61A2028)
        : const Color(0xF2FFFFFF);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.14)
        : const Color(0xFFE2E6EE);
    final textColor = isDark ? Colors.white : const Color(0xFF111827);
    final mutedColor =
        isDark ? Colors.white70 : const Color(0xFF6B7280);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            width: 380,
            constraints: const BoxConstraints(maxHeight: 540),
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
                              ? () => _themeService.removeCustomImageSkin(skin.id)
                              : null,
                        );
                      },
                    );
                  }),
                ),
                Obx(() {
                  final active = _themeService.activeSkin;
                  if (!active.isCustomImage) {
                    return const SizedBox.shrink();
                  }
                  final opacity = _themeService.skinOverlayOpacity.value;
                  return Container(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: borderColor)),
                    ),
                    child: Row(
                      children: [
                        Text(
                          '背景遮罩',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: mutedColor,
                          ),
                        ),
                        Expanded(
                          child: Slider(
                            min: 0.15,
                            max: 0.85,
                            value: opacity,
                            onChanged: _themeService.setSkinOverlayOpacity,
                          ),
                        ),
                        SizedBox(
                          width: 36,
                          child: Text(
                            '${(opacity * 100).round()}%',
                            textAlign: TextAlign.end,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: mutedColor,
                            ),
                          ),
                        ),
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
