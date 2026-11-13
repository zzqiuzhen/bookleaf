import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:xml/xml.dart';

import '../models.dart';

class ParsedBook {
  final String title;
  final String author;
  final List<Chapter> chapters;
  final Uint8List? cover;
  ParsedBook({
    required this.title,
    required this.author,
    required this.chapters,
    this.cover,
  });
}

String _cleanText(String s) {
  var t = s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  t = t.replaceAll('\u00a0', ' ');
  // Collapse runs of spaces inside lines but keep paragraph breaks.
  final lines = t.split('\n').map((l) {
    var x = l.replaceAll(RegExp(r'[ \t\u3000]{2,}'), ' ');
    return x.trimRight();
  });
  t = lines.join('\n');
  t = t.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return t.trim();
}

/// Decode bytes that may be UTF-8 or GBK/GB18030.
String decodeTextBytes(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3), allowMalformed: true);
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    try {
      return gbk.decode(bytes);
    } catch (_) {
      return utf8.decode(bytes, allowMalformed: true);
    }
  }
}

const _blockTags = {
  'p', 'div', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'li', 'ul', 'ol', //
  'blockquote', 'pre', 'section', 'article', 'tr', 'table', 'figure',
  'figcaption', 'body', 'header', 'footer', 'aside', 'nav', 'hr', 'dd', 'dt',
};

const _skipTags = {'script', 'style', 'head', 'title', 'meta', 'link', 'svg'};

/// Serialise HTML into readable plain text (paragraphs separated by blank lines).
String htmlToText(String source) {
  final doc = html_parser.parse(source);
  final body = doc.body;
  if (body == null) return _cleanText(doc.text ?? '');
  final sb = StringBuffer();
  var lastWrite = '';

  void newline() {
    if (!sb.toString().endsWith('\n')) sb.write('\n');
  }

  void walk(dom.Node node) {
    if (node is dom.Text) {
      var text = node.data.replaceAll(RegExp(r'[ \t\n\r\u00a0]+'), ' ');
      if (text.trim().isEmpty) {
        text = ' ';
      }
      if (text == ' ' && (sb.isEmpty || lastWrite.endsWith(' '))) return;
      sb.write(text);
      lastWrite = text;
      return;
    }
    if (node is! dom.Element) return;
    final tag = node.localName?.toLowerCase() ?? '';
    if (_skipTags.contains(tag)) return;
    if (tag == 'br') {
      sb.write('\n');
      return;
    }
    if (tag == 'img') {
      sb.write('\n');
      return;
    }
    final isBlock = _blockTags.contains(tag);
    if (isBlock) {
      if (sb.isNotEmpty && !sb.toString().endsWith('\n\n')) newline();
    }
    for (final child in node.nodes) {
      walk(child);
    }
    if (isBlock) {
      newline();
      if (tag == 'p' || tag.startsWith('h') || tag == 'div') newline();
      lastWrite = '\n';
    }
  }

  walk(body);
  return _cleanText(sb.toString());
}

String _firstHeadingText(String source) {
  final doc = html_parser.parse(source);
  for (final tag in ['h1', 'h2', 'h3', 'title']) {
    final el = doc.querySelector(tag);
    final text = el?.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text != null && text.isNotEmpty && text.length <= 80) return text;
  }
  return '';
}

class EpubParser {
  static ParsedBook parse(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes, verify: false);
    final Map<String, ArchiveFile> byName = {};
    for (final f in archive.files) {
      if (f.isFile) byName[_norm(f.name)] = f;
    }

    ArchiveFile? find(String path) => byName[_norm(path)];

    String readText(String path) {
      final f = find(path);
      if (f == null) return '';
      return decodeTextBytes(Uint8List.fromList(f.content as List<int>));
    }

    // 1. container.xml -> OPF path
    var opfPath = '';
    final container = readText('META-INF/container.xml');
    if (container.isNotEmpty) {
      try {
        final doc = XmlDocument.parse(container);
        final root = doc.findAllElements('rootfile').firstOrNull;
        opfPath = root?.getAttribute('full-path') ?? '';
      } catch (_) {}
    }
    if (opfPath.isEmpty) {
      opfPath = byName.keys.firstWhere(
        (k) => k.endsWith('.opf'),
        orElse: () => '',
      );
    }

    var title = '';
    var author = '';
    final chapters = <Chapter>[];
    Uint8List? cover;

    if (opfPath.isEmpty) {
      // Not a valid epub container: treat every xhtml as a chapter.
      for (final entry in byName.entries) {
        if (entry.key.endsWith('.xhtml') || entry.key.endsWith('.html')) {
          final src = readText(entry.key);
          final text = htmlToText(src);
          if (text.length > 40) {
            chapters.add(Chapter(_firstHeadingText(src).ifEmpty('正文'), text));
          }
        }
      }
      return ParsedBook(
        title: title.ifEmpty('未命名'),
        author: author,
        chapters: chapters,
        cover: cover,
      );
    }

    final opfSource = readText(opfPath);
    final opfDir = _dirOf(opfPath);
    XmlDocument? opf;
    try {
      opf = XmlDocument.parse(opfSource);
    } catch (_) {}

    final manifest = <String, _ManifestItem>{};
    final spine = <String>[];
    final tocTitles = <String, String>{};

    if (opf != null) {
      for (final el in opf.findAllElements('title')) {
        if (el.name.namespaceUri?.contains('purl.org/dc') ?? true) {
          final t = el.innerText.trim();
          if (t.isNotEmpty) {
            title = t;
            break;
          }
        }
      }
      for (final el in opf.findAllElements('creator')) {
        final t = el.innerText.trim();
        if (t.isNotEmpty) {
          author = t;
          break;
        }
      }

      String? coverId;
      for (final el in opf.findAllElements('meta')) {
        if (el.getAttribute('name') == 'cover') coverId = el.getAttribute('content');
      }

      for (final el in opf.findAllElements('item')) {
        final id = el.getAttribute('id') ?? '';
        final href = el.getAttribute('href') ?? '';
        if (id.isEmpty || href.isEmpty) continue;
        manifest[id] = _ManifestItem(
          id: id,
          href: _resolve(opfDir, href),
          mediaType: el.getAttribute('media-type') ?? '',
          properties: el.getAttribute('properties') ?? '',
        );
      }

      for (final el in opf.findAllElements('itemref')) {
        final idref = el.getAttribute('idref');
        if (idref != null && manifest.containsKey(idref)) spine.add(idref);
      }

      // Cover image
      String? coverPath;
      for (final item in manifest.values) {
        if (item.properties.contains('cover-image')) {
          coverPath = item.href;
          break;
        }
      }
      coverPath ??= coverId != null ? manifest[coverId]?.href : null;
      if (coverPath == null) {
        for (final item in manifest.values) {
          if (item.mediaType.startsWith('image/') &&
              item.href.toLowerCase().contains('cover')) {
            coverPath = item.href;
            break;
          }
        }
      }
      if (coverPath != null) {
        final f = find(coverPath);
        if (f != null) cover = Uint8List.fromList(f.content as List<int>);
      }

      // TOC (nav.xhtml / toc.ncx)
      for (final item in manifest.values) {
        if (item.properties.contains('nav') && item.href.endsWith('.xhtml')) {
          final src = readText(item.href);
          if (src.isNotEmpty) {
            final doc = html_parser.parse(src);
            for (final a in doc.querySelectorAll('nav a, a')) {
              final href = a.attributes['href'];
              final label = a.text.replaceAll(RegExp(r'\s+'), ' ').trim();
              if (href == null || label.isEmpty) continue;
              final path = _resolve(_dirOf(item.href), href.split('#').first);
              tocTitles.putIfAbsent(path, () => label);
            }
          }
        } else if (item.href.endsWith('.ncx')) {
          final src = readText(item.href);
          if (src.isNotEmpty) {
            try {
              final doc = XmlDocument.parse(src);
              for (final nav in doc.findAllElements('navPoint')) {
                final label = nav
                    .findAllElements('text')
                    .firstOrNull
                    ?.innerText
                    .trim();
                final srcAttr = nav
                    .findAllElements('content')
                    .firstOrNull
                    ?.getAttribute('src')
                    ?.split('#')
                    .first;
                if (label == null || label.isEmpty || srcAttr == null) continue;
                final path = _resolve(_dirOf(item.href), srcAttr);
                tocTitles.putIfAbsent(path, () => label);
              }
            } catch (_) {}
          }
        }
      }
    }

    // 2. Walk spine
    final sources = <String, String>{}; // path -> raw source
    final order = <String>[];
    for (final id in spine) {
      final item = manifest[id]!;
      if (!(item.mediaType.contains('html') ||
          item.href.endsWith('.xhtml') ||
          item.href.endsWith('.html') ||
          item.href.endsWith('.htm'))) {
        continue;
      }
      if (find(item.href) == null) continue;
      sources[item.href] = readText(item.href);
      order.add(item.href);
    }

    // 3. Build chapters, merging tiny fragments into the following chapter
    final pending = StringBuffer();
    for (final path in order) {
      final src = sources[path]!;
      final text = htmlToText(src);
      final heading = tocTitles[path] ?? _firstHeadingText(src);
      if (text.length < 240) {
        if (pending.isNotEmpty) pending.write('\n\n');
        pending.write(text);
        continue;
      }
      var body = text;
      if (heading.isNotEmpty && body.startsWith(heading)) {
        body = body.substring(heading.length).trim();
      }
      if (pending.isNotEmpty) {
        body = '${pending.toString().trim()}\n\n$body';
        pending.clear();
      }
      final chTitle = heading.isNotEmpty
          ? heading
          : (chapters.isEmpty ? '开篇' : '第${chapters.length + 1}节');
      chapters.add(Chapter(chTitle, body));
    }
    if (pending.isNotEmpty) {
      final tail = pending.toString().trim();
      if (tail.isNotEmpty) {
        if (chapters.isEmpty) {
          chapters.add(Chapter('开篇', tail));
        } else {
          chapters.last = Chapter(
            chapters.last.title,
            '${chapters.last.text}\n\n$tail',
          );
        }
      }
    }

    if (chapters.isEmpty) {
      for (final path in order) {
        final ch = htmlToText(sources[path]!);
        if (ch.isNotEmpty) chapters.add(Chapter('正文', ch));
      }
    }

    return ParsedBook(
      title: title.ifEmpty('未命名'),
      author: author,
      chapters: _capChapters(chapters),
      cover: cover,
    );
  }

  static List<Chapter> _capChapters(List<Chapter> input) {
    const maxChars = 18000;
    final out = <Chapter>[];
    for (final ch in input) {
      if (ch.text.length <= maxChars) {
        out.add(ch);
        continue;
      }
      final parts = _splitBySize(ch.text, maxChars);
      for (var i = 0; i < parts.length; i++) {
        out.add(Chapter('${ch.title}（${i + 1}）', parts[i]));
      }
    }
    return out;
  }
}

class _ManifestItem {
  final String id;
  final String href;
  final String mediaType;
  final String properties;
  _ManifestItem({
    required this.id,
    required this.href,
    required this.mediaType,
    required this.properties,
  });
}

String _norm(String p) => p.replaceAll('\\', '/').replaceAll(RegExp(r'^\./'), '');

String _dirOf(String path) {
  final i = path.lastIndexOf('/');
  return i < 0 ? '' : path.substring(0, i + 1);
}

String _resolve(String dir, String href) {
  final clean = Uri.decodeFull(href.split('#').first);
  if (clean.startsWith('/')) return clean.substring(1);
  final parts = ('$dir$clean').split('/');
  final stack = <String>[];
  for (final p in parts) {
    if (p == '..') {
      if (stack.isNotEmpty) stack.removeLast();
    } else if (p != '.' && p.isNotEmpty) {
      stack.add(p);
    }
  }
  return stack.join('/');
}

List<String> _splitBySize(String text, int maxChars) {
  final out = <String>[];
  var offset = 0;
  while (offset < text.length) {
    var end = (offset + maxChars).clamp(0, text.length);
    if (end < text.length) {
      final nl = text.lastIndexOf('\n', end);
      if (nl > offset + maxChars ~/ 2) end = nl;
    }
    out.add(text.substring(offset, end).trim());
    offset = end;
  }
  return out.where((s) => s.isNotEmpty).toList();
}

final _chapterRegex = RegExp(
  r'^[ \t\u3000]*('
  r'第[0-9零一二三四五六七八九十百千万〇两]{1,12}[章节回卷部集篇话]([ \t\u3000:：、.\-—]*[^\n]{0,30})?'
  r'|(序|楔子|引子|前言|后记|尾声|终章|番外)[^\n]{0,24}'
  r'|Chapter[ \t]+[0-9IVXLCivxlc]+[^\n]{0,40}'
  r')[ \t\u3000]*$',
  multiLine: true,
);

class TxtParser {
  static ParsedBook parse(Uint8List bytes, String fileName) {
    final raw = decodeTextBytes(bytes);
    final meta = _metaFromFileName(fileName);
    var body = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    body = body.replaceAll('\u3000', '  ');

    final matches = _chapterRegex.allMatches(body).toList();
    final chapters = <Chapter>[];
    if (matches.length >= 2) {
      final firstStart = matches.first.start;
      final preface = body.substring(0, firstStart).trim();
      for (var i = 0; i < matches.length; i++) {
        final start = matches[i].start;
        final end = i + 1 < matches.length ? matches[i + 1].start : body.length;
        final title = matches[i].group(0)!.trim();
        // The heading line itself is rendered separately: drop it from the body.
        final bodyStart = matches[i].end.clamp(start, end);
        final text = _cleanText(body.substring(bodyStart, end));
        if (text.isEmpty) continue;
        chapters.add(Chapter(title.isEmpty ? '第${i + 1}章' : title, text));
      }
      if (preface.isNotEmpty && preface.length > 20) {
        chapters.insert(0, Chapter('序', _cleanText(preface)));
      }
    }

    if (chapters.isEmpty) {
      final split = _splitBySize(_cleanText(body), 14000);
      for (var i = 0; i < split.length; i++) {
        chapters.add(Chapter('第${i + 1}节', split[i]));
      }
    }

    return ParsedBook(
      title: meta.title,
      author: meta.author,
      chapters: EpubParser._capChapters(chapters),
      cover: null,
    );
  }

  static ({String title, String author}) _metaFromFileName(String name) {
    var base = name.replaceAll(RegExp(r'\.(txt|TXT|text)$'), '');
    String title = base;
    String author = '';
    // 《书名》作者：某某
    final bracket = RegExp(r'《(.+?)》').firstMatch(base);
    if (bracket != null) {
      title = bracket.group(1)!.trim();
      final rest = base.substring(bracket.end).trim();
      final a = RegExp(r'(作者|著|by)[:：\s]*([^\s,，]+)').firstMatch(rest);
      if (a != null) author = a.group(2)!.trim();
    } else {
      final by = RegExp(r'[-_ ](?:作者[-_ :：]*)?([^\s\-_]{2,10})$').firstMatch(base);
      if (by != null && base.contains('作者')) {
        title = base.substring(0, by.start).trim();
        author = by.group(1)!.trim();
      }
    }
    title = title.replaceAll(RegExp(r'[_\s]+$'), '').trim();
    if (title.isEmpty) title = '未命名';
    return (title: title, author: author);
  }
}

extension _EmptyString on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
