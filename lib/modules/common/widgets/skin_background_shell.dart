import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:oasx/service/theme_service.dart';

/// Renders the active background skin (solid color, gradient, or local image)
/// and adapts child CardTheme & cardColor opacity dynamically.
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
      final cardOpacity = themeService.skinCardOpacity.value;
      final alignX = themeService.skinImageAlignX.value;
      final alignY = themeService.skinImageAlignY.value;
      final baseTheme = Theme.of(context);

      final baseCardColor = skin.cardColor ??
          baseTheme.cardTheme.color ??
          baseTheme.colorScheme.surface;
      final resolvedCardColor = skin.supportsTranslucentCards
          ? baseCardColor.withValues(alpha: cardOpacity)
          : baseCardColor;

      final innerAlpha = (cardOpacity * 0.70).clamp(0.06, 0.85).toDouble();
      final adaptedColorScheme = skin.supportsTranslucentCards
          ? baseTheme.colorScheme.copyWith(
              surfaceContainerHighest: baseTheme
                  .colorScheme.surfaceContainerHighest
                  .withValues(alpha: innerAlpha),
              surfaceContainerHigh: baseTheme.colorScheme.surfaceContainerHigh
                  .withValues(alpha: innerAlpha),
              surfaceContainer: baseTheme.colorScheme.surfaceContainer
                  .withValues(alpha: innerAlpha),
              surfaceContainerLow: baseTheme.colorScheme.surfaceContainerLow
                  .withValues(alpha: innerAlpha),
            )
          : baseTheme.colorScheme;

      final adaptedTheme = baseTheme.copyWith(
        colorScheme: adaptedColorScheme,
        cardColor: resolvedCardColor,
        cardTheme: baseTheme.cardTheme.copyWith(
          color: resolvedCardColor,
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
              alignment: Alignment(alignX, alignY),
              filterQuality: FilterQuality.medium,
            ),
            if (overlayOpacity > 0.005)
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
