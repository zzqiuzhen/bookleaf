import 'package:flutter/material.dart';

import '../models.dart';

class PageRef {
  final int chapter;
  final int start;
  final int end;
  const PageRef(this.chapter, this.start, this.end);
}

/// Pagination result for a whole book.
class BookLayout {
  final List<PageRef> pages;
  final List<int> chapterFirstPage;
  final int totalChars;
  const BookLayout(this.pages, this.chapterFirstPage, this.totalChars);

  int get totalPages => pages.length;

  int pageForPosition(int chapter, int offset) {
    if (pages.isEmpty) return 0;
    final first = chapterFirstPage[chapter.clamp(0, chapterFirstPage.length - 1)];
    final nextChapter =
        chapter + 1 < chapterFirstPage.length ? chapterFirstPage[chapter + 1] : pages.length;
    for (var i = first; i < nextChapter; i++) {
      final p = pages[i];
      if (offset >= p.start && offset < p.end) return i;
    }
    return first.clamp(0, pages.length - 1);
  }
}

class Paginator {
  /// Splits every chapter into pages that fit [maxWidth] x [maxHeight].
  static Future<BookLayout> build({
    required List<Chapter> chapters,
    required TextStyle style,
    required double maxWidth,
    required double maxHeight,
    TextAlign align = TextAlign.justify,
    double firstPageReduction = 0,
    void Function(double progress)? onProgress,
  }) async {
    final pages = <PageRef>[];
    final firstPage = <int>[];
    var total = 0;
    for (var ci = 0; ci < chapters.length; ci++) {
      firstPage.add(pages.length);
      final text = chapters[ci].text;
      total += text.length;
      if (text.trim().isEmpty) {
        continue;
      }
      final ranges = _paginateChapter(
          text, style, maxWidth, maxHeight, align, firstPageReduction);
      for (final r in ranges) {
        pages.add(PageRef(ci, r[0], r[1]));
      }
      if (ci % 8 == 7) {
        onProgress?.call((ci + 1) / chapters.length);
        await Future<void>.delayed(Duration.zero);
      }
    }
    if (pages.isEmpty) {
      pages.add(const PageRef(0, 0, 0));
      if (firstPage.isEmpty) firstPage.add(0);
    }
    return BookLayout(pages, firstPage, total);
  }

  static List<List<int>> _paginateChapter(
    String text,
    TextStyle style,
    double width,
    double height,
    TextAlign align,
    double firstPageReduction,
  ) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textAlign: align,
      textScaler: TextScaler.noScaling,
    )..layout(maxWidth: width);

    final out = <List<int>>[];
    var start = 0;
    var y = 0.0;
    final fullHeight = tp.height;
    var guard = 0;

    while (start < text.length && guard++ < 100000) {
      // Skip leading newlines so pages don't open with blank lines.
      while (start < text.length && text[start] == '\n') {
        start++;
      }
      if (start >= text.length) break;

      final pageHeight =
          (out.isEmpty ? height - firstPageReduction : height).clamp(80.0, height);
      final probe = y + pageHeight;
      int end;
      double nextY;
      if (probe >= fullHeight - 0.5) {
        end = text.length;
        nextY = fullHeight;
      } else {
        end = tp.getPositionForOffset(Offset(0, probe)).offset;
        if (end <= start) {
          // Extremely defensive: force progress by one line.
          end = text.length;
          nextY = fullHeight;
        } else {
          final caret = tp.getOffsetForCaret(TextPosition(offset: end), Rect.zero);
          nextY = caret.dy;
          if (nextY <= y + 1) nextY = y + height;
        }
      }
      if (end > text.length) end = text.length;
      out.add([start, end]);
      start = end;
      y = nextY;
      if (out.length > 20000) break;
    }
    if (out.isEmpty) out.add([0, text.length]);
    return out;
  }
}
