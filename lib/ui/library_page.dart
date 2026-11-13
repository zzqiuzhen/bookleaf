import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../services/library_store.dart';
import 'import_flow.dart';
import 'reader/reader_screen.dart';
import 'widgets.dart';

enum _SortMode { recent, added, title, author }

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, required this.store});
  final LibraryStore store;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final Map<String, String?> _covers = {};
  _SortMode _sort = _SortMode.recent;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStore);
    _loadCovers();
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() {
    if (!mounted) return;
    _loadCovers();
    setState(() {});
  }

  Future<void> _loadCovers() async {
    for (final b in widget.store.books) {
      if (!_covers.containsKey(b.id)) {
        _covers[b.id] = null;
        final p = await widget.store.coverPathOf(b);
        if (mounted) setState(() => _covers[b.id] = p);
      }
    }
  }

  List<BookMeta> get _sorted {
    final list = [...widget.store.books];
    switch (_sort) {
      case _SortMode.recent:
        list.sort((a, b) {
          final ao = a.openedAt ?? a.addedAt;
          final bo = b.openedAt ?? b.addedAt;
          return bo.compareTo(ao);
        });
      case _SortMode.added:
        list.sort((a, b) => b.addedAt.compareTo(a.addedAt));
      case _SortMode.title:
        list.sort((a, b) => a.title.compareTo(b.title));
      case _SortMode.author:
        list.sort((a, b) => a.author.compareTo(b.author));
    }
    return list;
  }

  void _open(BookMeta b) {
    Navigator.of(context, rootNavigator: true).push(
      CupertinoPageRoute<void>(
        builder: (_) => ReaderScreen(book: b, store: widget.store),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final books = _sorted;
    final width = MediaQuery.sizeOf(context).width;
    final columns = width > 720 ? 4 : (width > 500 ? 3 : 2);
    final tileWidth = (width - 22 * 2 - 17 * (columns - 1)) / columns;
    final tileHeight = tileWidth * 1.5 + 52;

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemBackground,
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: const Text('书库'),
            border: null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  onPressed: () => importWithFeedback(context, widget.store),
                  child: const Icon(CupertinoIcons.add, size: 22),
                ),
                const SizedBox(width: 18),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  onPressed: _showSortMenu,
                  child: const Icon(CupertinoIcons.arrow_up_arrow_down, size: 22),
                ),
              ],
            ),
          ),
          if (books.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyLibrary(
                onImport: () => importWithFeedback(context, widget.store),
              ),
            )
          else ...[
            const SliverToBoxAdapter(child: SizedBox(height: 4)),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 40),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 26,
                  crossAxisSpacing: 17,
                  mainAxisExtent: tileHeight,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final b = books[i];
                    return _BookTile(
                      book: b,
                      coverPath: _covers[b.id],
                      onTap: () => _open(b),
                      onLongPress: () => _showActions(b),
                    );
                  },
                  childCount: books.length,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showSortMenu() {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('排序方式'),
        actions: [
          for (final mode in _SortMode.values)
            CupertinoActionSheetAction(
              onPressed: () {
                setState(() => _sort = mode);
                Navigator.of(ctx).pop();
              },
              child: Text(
                _sortLabel(mode),
                style: TextStyle(
                  fontWeight:
                      mode == _sort ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('取消'),
        ),
      ),
    );
  }

  String _sortLabel(_SortMode m) {
    switch (m) {
      case _SortMode.recent:
        return '最近阅读';
      case _SortMode.added:
        return '最近添加';
      case _SortMode.title:
        return '书名';
      case _SortMode.author:
        return '作者';
    }
  }

  void _showActions(BookMeta b) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        message: Text(
          '${b.format.toUpperCase()} · ${b.chapterCount} 章'
          '${b.author.isEmpty ? '' : ' · ${b.author}'}',
          style: const TextStyle(fontSize: 12),
        ),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(ctx).pop();
              _open(b);
            },
            child: const Text('打开'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(ctx).pop();
              widget.store.setFinished(b, !b.finished);
            },
            child: Text(b.finished ? '标记为未读' : '标记为已读'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.of(ctx).pop();
              widget.store.remove(b);
            },
            child: const Text('从书库移除'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('取消'),
        ),
      ),
    );
  }
}

class _BookTile extends StatelessWidget {
  const _BookTile({
    required this.book,
    required this.coverPath,
    required this.onTap,
    required this.onLongPress,
  });

  final BookMeta book;
  final String? coverPath;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final progress = book.progress;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Hero(
            tag: 'cover-${book.id}',
            child: BookCover(book: book, imagePath: coverPath),
          ),
          const SizedBox(height: 7),
          Text(
            book.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              height: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (book.author.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              book.author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                color: CupertinoColors.secondaryLabel,
              ),
            ),
          ],
          const SizedBox(height: 5),
          if (book.finished)
            const Text(
              '已读完',
              style: TextStyle(
                fontSize: 10.5,
                color: CupertinoColors.tertiaryLabel,
              ),
            )
          else if (progress > 0.005)
            Row(
              children: [
                Expanded(child: ProgressLine(value: progress)),
                const SizedBox(width: 6),
                Text(
                  formatProgress(progress),
                  style: const TextStyle(
                    fontSize: 10,
                    color: CupertinoColors.secondaryLabel,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onImport});
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 60),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            CupertinoIcons.book,
            size: 58,
            color: CupertinoColors.systemGrey3.resolveFrom(context),
          ),
          const SizedBox(height: 18),
          const Text(
            '书库空空如也',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            '导入 EPUB 或 TXT 文件开始阅读',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              color: CupertinoColors.secondaryLabel,
            ),
          ),
          const SizedBox(height: 22),
          CupertinoButton.filled(
            borderRadius: BorderRadius.circular(22),
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 10),
            onPressed: onImport,
            child: const Text('导入图书', style: TextStyle(fontSize: 15)),
          ),
        ],
      ),
    );
  }
}

/// Utility used by other pages to display a cover thumbnail.
Future<String?> coverPathFor(LibraryStore store, BookMeta b) => store.coverPathOf(b);

bool fileExists(String? path) => path != null && File(path).existsSync();
