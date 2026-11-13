import 'dart:convert';

class Chapter {
  final String title;
  final String text;
  const Chapter(this.title, this.text);

  Map<String, dynamic> toJson() => {'t': title, 'x': text};
  factory Chapter.fromJson(Map<String, dynamic> j) =>
      Chapter(j['t'] as String? ?? '', j['x'] as String? ?? '');
}

/// Metadata kept in the library index (chapters live in the book folder).
class BookMeta {
  final String id;
  String title;
  String author;
  String format; // epub | txt
  String dirName;
  String? coverFile; // file name inside the book folder
  int chapterCount;
  int totalChars;
  int chapterIndex; // resume position
  int charOffset;
  bool finished;
  DateTime addedAt;
  DateTime? openedAt;

  BookMeta({
    required this.id,
    required this.title,
    required this.author,
    required this.format,
    required this.dirName,
    this.coverFile,
    this.chapterCount = 0,
    this.totalChars = 0,
    this.chapterIndex = 0,
    this.charOffset = 0,
    this.finished = false,
    required this.addedAt,
    this.openedAt,
  });

  /// Coarse progress (0..1) computed from the resume position and book size.
  double get progress {
    if (totalChars <= 0) return 0;
    final approx = chapterIndex == 0 && charOffset == 0
        ? 0.0
        : ((chapterIndex + 0.0) / (chapterCount <= 0 ? 1 : chapterCount));
    if (finished) return 1;
    return approx.clamp(0.0, 1.0);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'author': author,
        'format': format,
        'dirName': dirName,
        'coverFile': coverFile,
        'chapterCount': chapterCount,
        'totalChars': totalChars,
        'chapterIndex': chapterIndex,
        'charOffset': charOffset,
        'finished': finished,
        'addedAt': addedAt.toIso8601String(),
        'openedAt': openedAt?.toIso8601String(),
      };

  factory BookMeta.fromJson(Map<String, dynamic> j) => BookMeta(
        id: j['id'] as String,
        title: j['title'] as String? ?? '未命名',
        author: j['author'] as String? ?? '',
        format: j['format'] as String? ?? 'txt',
        dirName: j['dirName'] as String? ?? '',
        coverFile: j['coverFile'] as String?,
        chapterCount: (j['chapterCount'] as num?)?.toInt() ?? 0,
        totalChars: (j['totalChars'] as num?)?.toInt() ?? 0,
        chapterIndex: (j['chapterIndex'] as num?)?.toInt() ?? 0,
        charOffset: (j['charOffset'] as num?)?.toInt() ?? 0,
        finished: j['finished'] as bool? ?? false,
        addedAt:
            DateTime.tryParse(j['addedAt'] as String? ?? '') ?? DateTime.now(),
        openedAt: j['openedAt'] == null
            ? null
            : DateTime.tryParse(j['openedAt'] as String),
      );

  static String encodeList(List<BookMeta> books) =>
      jsonEncode(books.map((b) => b.toJson()).toList());

  static List<BookMeta> decodeList(String raw) {
    final data = jsonDecode(raw);
    if (data is! List) return [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(BookMeta.fromJson)
        .toList();
  }
}

enum PageTurnStyle { curl, slide, none }

enum ReaderThemeKind { white, sepia, night, gray }

class ReaderSettings {
  double fontSize; // pt
  double lineHeight;
  String fontKey; // system / song / hei / kai
  ReaderThemeKind theme;
  PageTurnStyle turn;
  bool justify;
  bool indent;

  ReaderSettings({
    this.fontSize = 19,
    this.lineHeight = 1.62,
    this.fontKey = 'song',
    this.theme = ReaderThemeKind.white,
    this.turn = PageTurnStyle.curl,
    this.justify = true,
    this.indent = true,
  });

  Map<String, dynamic> toJson() => {
        'fontSize': fontSize,
        'lineHeight': lineHeight,
        'fontKey': fontKey,
        'theme': theme.name,
        'turn': turn.name,
        'justify': justify,
        'indent': indent,
      };

  void applyJson(Map<String, dynamic> j) {
    fontSize = (j['fontSize'] as num?)?.toDouble() ?? fontSize;
    lineHeight = (j['lineHeight'] as num?)?.toDouble() ?? lineHeight;
    fontKey = j['fontKey'] as String? ?? fontKey;
    theme = ReaderThemeKind.values.firstWhere(
      (e) => e.name == j['theme'],
      orElse: () => theme,
    );
    turn = PageTurnStyle.values.firstWhere(
      (e) => e.name == j['turn'],
      orElse: () => turn,
    );
    justify = j['justify'] as bool? ?? justify;
    indent = j['indent'] as bool? ?? indent;
  }
}

/// Chinese book typography: two-character first-line indent, no blank lines.
String applyIndent(String text) {
  final out = <String>[];
  for (final line in text.split('\n')) {
    final t = line.trim();
    if (t.isEmpty) continue;
    out.add('\u3000\u3000$t');
  }
  return out.join('\n');
}
