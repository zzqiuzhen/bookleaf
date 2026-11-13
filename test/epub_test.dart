import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:bookleaf/models.dart';
import 'package:bookleaf/services/paginator.dart';
import 'package:bookleaf/services/parsers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _buildEpub() {
  final archive = Archive();

  void add(String name, String text) {
    final bytes = utf8.encode(text);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  add('mimetype', 'application/epub+zip');
  add('META-INF/container.xml', '''
<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
''');
  add('OEBPS/content.opf', '''
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>测试之书</dc:title>
    <dc:creator>某作者</dc:creator>
    <meta name="cover" content="cover-img"/>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="c1" href="text/ch1.xhtml" media-type="application/xhtml+xml"/>
    <item id="c2" href="text/ch2.xhtml" media-type="application/xhtml+xml"/>
    <item id="cover-img" href="images/cover.jpg" media-type="image/jpeg" properties="cover-image"/>
  </manifest>
  <spine>
    <itemref idref="c1"/>
    <itemref idref="c2"/>
  </spine>
</package>
''');
  add('OEBPS/nav.xhtml', '''
<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><body>
<nav epub:type="toc" xmlns:epub="http://www.idpf.org/2007/ops">
  <ol>
    <li><a href="text/ch1.xhtml">第一章 山门</a></li>
    <li><a href="text/ch2.xhtml">第二章 下山</a></li>
  </ol>
</nav>
</body></html>
''');
  add('OEBPS/text/ch1.xhtml', '''
<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>第一章 山门</title>
<style>p{color:#000}</style></head>
<body>
<h1>第一章 山门</h1>
<p>清晨的雾还没有散，山门外的石阶上落了一层薄霜。他站在阶下，仰头看了很久。</p>
<p>守门的道人认得他，什么也没问，只是把门推开了一半，让他自己走进去。</p>
</body></html>
''');
  add('OEBPS/text/ch2.xhtml', '''
<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><body>
<h2>第二章 下山</h2>
<p>下山的路比上山好走。三年时间，石阶被踩得更滑了，两侧的松树也高了许多。</p>
<p>他背着一个旧布包，包里只有两本书和一件换洗的道袍。</p>
</body></html>
''');
  add('OEBPS/images/cover.jpg', 'JPEGDATA');

  final bytes = ZipEncoder().encode(archive);
  return Uint8List.fromList(bytes);
}

void main() {
  test('EPUB：解析元数据、目录标题、正文与封面', () {
    final parsed = EpubParser.parse(_buildEpub());
    expect(parsed.title, '测试之书');
    expect(parsed.author, '某作者');
    expect(parsed.chapters.length, 2);
    expect(parsed.chapters[0].title, '第一章 山门');
    expect(parsed.chapters[1].title, '第二章 下山');
    expect(parsed.chapters[0].text.contains('清晨的雾还没有散'), true);
    // the heading must not leak into the body (it is rendered separately)
    expect(parsed.chapters[0].text.startsWith('第一章'), false);
    // style/head content must be stripped
    expect(parsed.chapters[0].text.contains('color'), false);
    expect(parsed.cover, isNotNull);
    expect(parsed.cover!.isNotEmpty, true);
  });

  testWidgets('分页：每一页的文本都不超过可用高度', (tester) async {
    final body = '　　' + ('山中四季，晨昏各异，雨雪风霜皆可入文。' * 120);
    final chapters = [Chapter('第一章', body)];
    await tester.pumpWidget(const SizedBox());
    const style = TextStyle(fontSize: 19, height: 1.62, letterSpacing: 0.2);
    const width = 330.0;
    const height = 560.0;
    final layout = await Paginator.build(
      chapters: chapters,
      style: style,
      maxWidth: width,
      maxHeight: height,
      align: TextAlign.justify,
      firstPageReduction: 58,
    );
    expect(layout.totalPages, greaterThan(3));
    for (final page in layout.pages) {
      final text = body.substring(page.start, page.end);
      final tp = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.justify,
        textScaler: TextScaler.noScaling,
      )..layout(maxWidth: width);
      expect(tp.height, lessThanOrEqualTo(height + 1.0),
          reason: 'page ${page.start}-${page.end} overflowed (${tp.height})');
      tp.dispose();
    }
  });
}
