import 'package:flutter/material.dart';

import '../models.dart';

class ReaderPalette {
  final Color background;
  final Color text;
  final Color secondary;
  final Color accent;
  final Brightness brightness;
  const ReaderPalette(this.background, this.text, this.secondary, this.accent,
      this.brightness);

  Color get chromeScrim =>
      brightness == Brightness.dark ? Colors.black : Colors.white;

  /// Colour of the back of the paper, seen while a page is being turned.
  Color get paperBack {
    switch (background) {
      case const Color(0xFFFFFFFF):
        return const Color(0xFFFBF7EF);
      case const Color(0xFFF6EFE0):
        return const Color(0xFFEFE6D3);
      case const Color(0xFF3A3A3C):
        return const Color(0xFF4A4A4D);
      default:
        return const Color(0xFF1B1B1D);
    }
  }
}

const _fallbackFonts = <String>[
  'Songti SC',
  'PingFang SC',
  'Heiti SC',
  'STSong',
  'Noto Serif CJK SC',
  'serif',
];

String? fontFamilyFor(String key) {
  switch (key) {
    case 'song':
      return 'Songti SC';
    case 'hei':
      return 'PingFang SC';
    case 'kai':
      return 'Kaiti SC';
    default:
      return null;
  }
}

String fontLabelFor(String key) {
  switch (key) {
    case 'song':
      return '宋体';
    case 'hei':
      return '黑体';
    case 'kai':
      return '楷体';
    default:
      return '系统';
  }
}

ReaderPalette paletteFor(ReaderThemeKind kind) {
  switch (kind) {
    case ReaderThemeKind.white:
      return const ReaderPalette(
          Color(0xFFFFFFFF), Color(0xFF1A1A1A), Color(0xFF8A8A8E), Color(0xFFFA5C2E), Brightness.light);
    case ReaderThemeKind.sepia:
      return const ReaderPalette(
          Color(0xFFF6EFE0), Color(0xFF4A3B2A), Color(0xFF9A8B74), Color(0xFFB0652A), Brightness.light);
    case ReaderThemeKind.gray:
      return const ReaderPalette(
          Color(0xFF3A3A3C), Color(0xFFD8D8DA), Color(0xFF8E8E93), Color(0xFFFA5C2E), Brightness.dark);
    case ReaderThemeKind.night:
      return const ReaderPalette(
          Color(0xFF000000), Color(0xFFB9B9BE), Color(0xFF6E6E73), Color(0xFFFA5C2E), Brightness.dark);
  }
}

TextStyle readerBodyStyle(ReaderSettings s, ReaderPalette palette) {
  return TextStyle(
    fontSize: s.fontSize,
    height: s.lineHeight,
    color: palette.text,
    fontFamily: fontFamilyFor(s.fontKey),
    fontFamilyFallback: _fallbackFonts,
    letterSpacing: 0.2,
    leadingDistribution: TextLeadingDistribution.even,
    decoration: TextDecoration.none,
  );
}

/// Tunable page geometry, shared by the paginator and the renderer.
class PageGeometry {
  final double width;
  final double height;
  final double horizontalPadding;
  final double headerHeight;
  final double footerHeight;
  final double chapterTitleSpace;

  const PageGeometry({
    required this.width,
    required this.height,
    this.horizontalPadding = 23,
    this.headerHeight = 30,
    this.footerHeight = 34,
    this.chapterTitleSpace = 58,
  });

  double get textWidth => width - horizontalPadding * 2;
  double get textHeight => height - headerHeight - footerHeight;

  factory PageGeometry.of(Size size, EdgeInsets safe) {
    final w = size.width;
    final h = size.height - safe.top - safe.bottom;
    return PageGeometry(width: w, height: h);
  }
}
