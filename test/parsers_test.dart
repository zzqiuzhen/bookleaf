import 'dart:convert';
import 'dart:typed_data';

import 'package:bookleaf/models.dart';
import 'package:bookleaf/services/paginator.dart';
import 'package:bookleaf/services/parsers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TXT 切章：识别「第X章」并且不把标题留在正文里', () {
    const text = '''
序

这是序言部分，讲述故事的开始。

第一章 启程

他推开门，风灌了进来。

第二章 归途

天亮了。
''';
    final parsed =
        TxtParser.parse(Uint8List.fromList(utf8.encode(text)), '测试书.txt');
    expect(parsed.chapters.length, greaterThanOrEqualTo(3));
    final ch1 = parsed.chapters.firstWhere((c) => c.title.contains('第一章'));
    expect(ch1.text.contains('他推开门'), true);
    expect(ch1.text.contains('第一章'), false);
  });

  test('HTML 转文本保留段落', () {
    final out = htmlToText(
        '<html><body><h1>标题</h1><p>第一段内容。</p><p>第二段<br/>换行</p></body></html>');
    expect(out.contains('第一段内容'), true);
    expect(out.contains('换行'), true);
  });

  test('UTF-8 编码的 TXT 能解码', () {
    final bytes = utf8.encode('第一章 测试\n\n内容在这里。');
    final parsed = TxtParser.parse(Uint8List.fromList(bytes), '编码测试.txt');
    expect(parsed.chapters.first.text.contains('内容在这里'), true);
  });

  testWidgets('分页：页码连续且每页非空', (tester) async {
    final body = '　　' + ('一二三四五六七八九十' * 300);
    final chapters = [Chapter('第一章', body)];
    await tester.pumpWidget(const SizedBox());
    final layout = await Paginator.build(
      chapters: chapters,
      style: const TextStyle(fontSize: 18, height: 1.6),
      maxWidth: 320,
      maxHeight: 560,
    );
    expect(layout.totalPages, greaterThan(1));
    expect(layout.pages.first.start, 0);
    expect(layout.pages.last.end, body.length);
    for (final page in layout.pages) {
      expect(page.end, greaterThan(page.start));
    }
    for (var i = 1; i < layout.pages.length; i++) {
      expect(layout.pages[i].start, layout.pages[i - 1].end);
    }
  });

  test('缩进工具：去掉空行并加两个全角空格', () {
    final out = applyIndent('第一段\n\n第二段');
    expect(out, '　　第一段\n　　第二段');
  });
}
