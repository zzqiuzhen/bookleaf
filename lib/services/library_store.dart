import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models.dart';
import 'parsers.dart';

class LibraryStore extends ChangeNotifier {
  LibraryStore._(this.root, {this.memoryOnly = false});

  final Directory root;
  final bool memoryOnly; // web preview: no file system available
  final List<BookMeta> books = [];
  final Map<String, List<Chapter>> _chapterCache = {};
  bool ready = false;

  static Future<LibraryStore> open() async {
    if (kIsWeb) {
      final store = LibraryStore._(Directory(''), memoryOnly: true);
      await store._loadIndex();
      return store;
    }
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/BookLeaf');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final store = LibraryStore._(dir);
    await store._loadIndex();
    return store;
  }

  File get _indexFile => File('${root.path}/library.json');

  Directory _bookDir(BookMeta b) => Directory('${root.path}/books/${b.dirName}');

  Future<void> _loadIndex() async {
    if (memoryOnly) {
      ready = true;
      notifyListeners();
      return;
    }
    try {
      if (_indexFile.existsSync()) {
        books.addAll(BookMeta.decodeList(await _indexFile.readAsString()));
      }
    } catch (_) {}
    books.sort(_sort);
    ready = true;
    notifyListeners();
  }

  static int _sort(BookMeta a, BookMeta b) {
    final ao = a.openedAt, bo = b.openedAt;
    if (ao == null && bo == null) return b.addedAt.compareTo(a.addedAt);
    if (ao == null) return 1;
    if (bo == null) return -1;
    return bo.compareTo(ao);
  }

  Future<void> _saveIndex() async {
    if (memoryOnly) return;
    await _indexFile.writeAsString(BookMeta.encodeList(books));
  }

  List<BookMeta> get inProgress =>
      books.where((b) => (b.chapterIndex > 0 || b.charOffset > 0) && !b.finished).toList();

  BookMeta? get lastRead {
    final withOpen = books.where((b) => b.openedAt != null).toList()
      ..sort((a, b) => b.openedAt!.compareTo(a.openedAt!));
    return withOpen.isEmpty ? null : withOpen.first;
  }

  Future<String?> coverPathOf(BookMeta b) async {
    if (memoryOnly || b.coverFile == null) return null;
    final f = File('${_bookDir(b).path}/${b.coverFile}');
    return f.existsSync() ? f.path : null;
  }

  Future<List<Chapter>> chaptersOf(BookMeta b) async {
    final cached = _chapterCache[b.id];
    if (cached != null) return cached;
    if (memoryOnly) return [];
    final f = File('${_bookDir(b).path}/chapters.json');
    if (!f.existsSync()) return [];
    final raw = await f.readAsString();
    final list = (jsonDecode(raw) as List)
        .whereType<Map<String, dynamic>>()
        .map(Chapter.fromJson)
        .toList();
    _chapterCache[b.id] = list;
    return list;
  }

  /// Import a local file (epub / txt). Throws [ImportException] on failure.
  Future<BookMeta> importFile(String path, String displayName) async {
    final ext = displayName.toLowerCase().split('.').last;
    if (ext != 'epub' && ext != 'txt') {
      throw ImportException('仅支持 EPUB 与 TXT 格式');
    }
    final bytes = await File(path).readAsBytes();
    return importBytes(bytes, displayName);
  }

  Future<BookMeta> importBytes(Uint8List bytes, String displayName) async {
    final ext = displayName.toLowerCase().split('.').last;
    ParsedBook parsed;
    try {
      parsed = ext == 'epub'
          ? EpubParser.parse(bytes)
          : TxtParser.parse(bytes, displayName);
    } catch (e) {
      throw ImportException('解析失败：$e');
    }
    if (parsed.chapters.isEmpty) {
      throw ImportException('这本书没有可读内容，可能是加密或有问题的文件');
    }

    final id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    String? coverName;
    if (!memoryOnly) {
      final dir = Directory('${root.path}/books/$id');
      dir.createSync(recursive: true);

      final bookFile = File('${dir.path}/book.$ext');
      await bookFile.writeAsBytes(bytes);

      await File('${dir.path}/chapters.json').writeAsString(jsonEncode(
        parsed.chapters.map((c) => c.toJson()).toList(),
      ));

      if (parsed.cover != null && parsed.cover!.isNotEmpty) {
        final lower = displayName.toLowerCase();
        final isPng = parsed.cover![0] == 0x89 || lower.endsWith('png');
        coverName = isPng ? 'cover.png' : 'cover.jpg';
        await File('${dir.path}/$coverName').writeAsBytes(parsed.cover!);
      }
    }

    final meta = BookMeta(
      id: id,
      title: parsed.title.isEmpty ? displayName : parsed.title,
      author: parsed.author,
      format: ext,
      dirName: id,
      coverFile: coverName,
      chapterCount: parsed.chapters.length,
      totalChars: parsed.chapters.fold(0, (s, c) => s + c.text.length),
      addedAt: DateTime.now(),
    );
    books.insert(0, meta);
    _chapterCache[id] = parsed.chapters;
    await _saveIndex();
    notifyListeners();
    return meta;
  }

  Future<void> markOpened(BookMeta b) async {
    b.openedAt = DateTime.now();
    books.sort(_sort);
    await _saveIndex();
    notifyListeners();
  }

  Future<void> saveProgress(
    BookMeta b, {
    required int chapterIndex,
    required int charOffset,
    required bool finished,
  }) async {
    b.chapterIndex = chapterIndex;
    b.charOffset = charOffset;
    b.finished = finished;
    b.openedAt = DateTime.now();
    await _saveIndex();
    notifyListeners();
  }

  Future<void> setFinished(BookMeta b, bool value) async {
    b.finished = value;
    if (value) {
      b.chapterIndex = (b.chapterCount.clamp(1, 1 << 30)) - 1;
    } else {
      b.chapterIndex = 0;
      b.charOffset = 0;
    }
    await _saveIndex();
    notifyListeners();
  }

  Future<void> remove(BookMeta b) async {
    books.removeWhere((x) => x.id == b.id);
    _chapterCache.remove(b.id);
    try {
      final dir = _bookDir(b);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (_) {}
    await _saveIndex();
    notifyListeners();
  }
}

class ImportException implements Exception {
  final String message;
  ImportException(this.message);
  @override
  String toString() => message;
}
