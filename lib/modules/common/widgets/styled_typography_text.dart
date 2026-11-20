import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:oasx/service/theme_service.dart';

/// Regex splitting text into CJK characters, Latin letters, digits, or other chars.
final RegExp _kTypographyTokenPattern = RegExp(
  r'([\u4e00-\u9fff\u3000-\u303f\uff00-\uffef]+)|([A-Za-z]+)|([0-9]+)|([^\u4e00-\u9fff\u3000-\u303f\uff00-\uffefA-Za-z0-9]+)',
);

/// Builds [InlineSpan] segments applying independent scale & bold settings
/// for Chinese (汉字), English (英文), and digits (数字).
List<InlineSpan> buildTypedTextSpans(
  String text,
  TextStyle baseStyle,
  AppTypographyConfig config,
) {
  if (text.isEmpty || config.isDefault) {
    return [TextSpan(text: text, style: baseStyle)];
  }
  final baseFontSize = baseStyle.fontSize ?? 14.0;
  final spans = <InlineSpan>[];

  for (final match in _kTypographyTokenPattern.allMatches(text)) {
    final token = match.group(0)!;
    if (match.group(1) != null) {
      // CJK / Chinese
      spans.add(
        TextSpan(
          text: token,
          style: _applyRule(
            baseStyle,
            baseFontSize,
            scale: config.cjkScale,
            bold: config.cjkBold,
          ),
        ),
      );
    } else if (match.group(2) != null) {
      // Latin / English
      spans.add(
        TextSpan(
          text: token,
          style: _applyRule(
            baseStyle,
            baseFontSize,
            scale: config.latinScale,
            bold: config.latinBold,
          ),
        ),
      );
    } else if (match.group(3) != null) {
      // Digits
      spans.add(
        TextSpan(
          text: token,
          style: _applyRule(
            baseStyle,
            baseFontSize,
            scale: config.digitScale,
            bold: config.digitBold,
          ),
        ),
      );
    } else {
      spans.add(TextSpan(text: token, style: baseStyle));
    }
  }
  return spans;
}

TextStyle _applyRule(
  TextStyle baseStyle,
  double baseFontSize, {
  required double scale,
  required bool bold,
}) {
  final nextSize = (baseFontSize * scale).clamp(9.0, 40.0).toDouble();
  final nextWeight = bold ? FontWeight.w700 : baseStyle.fontWeight;
  return baseStyle.copyWith(
    fontSize: nextSize,
    fontWeight: nextWeight,
  );
}

/// Drop-in reactive text widget that applies separate size & bold settings
/// to Chinese, English, and numeric characters from [ThemeService].
class StyledTypographyText extends StatelessWidget {
  const StyledTypographyText(
    this.data, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.softWrap,
    this.textAlign,
  });

  final String data;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final themeService =
        Get.isRegistered<ThemeService>() ? Get.find<ThemeService>() : null;
    if (themeService == null) {
      return Text(
        data,
        style: style,
        maxLines: maxLines,
        overflow: overflow,
        softWrap: softWrap,
        textAlign: textAlign,
      );
    }
    return Obx(() {
      final config = themeService.typographyConfig.value;
      final effectiveStyle =
          DefaultTextStyle.of(context).style.merge(style);
      if (config.isDefault) {
        return Text(
          data,
          style: style,
          maxLines: maxLines,
          overflow: overflow,
          softWrap: softWrap,
          textAlign: textAlign,
        );
      }
      return Text.rich(
        TextSpan(
          children: buildTypedTextSpans(data, effectiveStyle, config),
        ),
        maxLines: maxLines,
        overflow: overflow,
        softWrap: softWrap,
        textAlign: textAlign,
      );
    });
  }
}
