import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:oasx/service/theme_service.dart';

/// Renders the active background skin (solid color, gradient, or local image)
/// and adapts child CardTheme colors for crisp contrast.
class SkinBackgroundShell extends StatelessWidget {
  const SkinBackgroundShell({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final themeService = Get.find<ThemeService>();
    return Obx(() {
      final skin = themeService.activeSkin;
      final overlayOpacity = themeService.skinOverlayOpacity.value;
      final baseTheme = Theme.of(context);

      final adaptedTheme = baseTheme.copyWith(
        cardTheme: baseTheme.cardTheme.copyWith(
          color: skin.cardColor ?? baseTheme.cardTheme.color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: skin.cardBorderColor ??
                  baseTheme.colorScheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
        ),
      );

      Widget background;
      if (skin.isCustomImage && !kIsWeb && File(skin.imagePath!).existsSync()) {
        background = Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              File(skin.imagePath!),
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
            ),
            ColoredBox(
              color: Colors.black.withValues(alpha: overlayOpacity),
            ),
          ],
        );
      } else if (skin.gradientColors != null) {
        background = DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: skin.gradientColors!,
            ),
          ),
        );
      } else {
        background = ColoredBox(
          color: skin.backgroundColor ?? baseTheme.scaffoldBackgroundColor,
        );
      }

      return Theme(
        data: adaptedTheme,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(child: background),
            Positioned.fill(child: child),
          ],
        ),
      );
    });
  }
}
