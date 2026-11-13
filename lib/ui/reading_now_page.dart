import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../services/library_store.dart';
import 'import_flow.dart';
import 'reader/reader_screen.dart';
import 'widgets.dart';

class ReadingNowPage extends StatefulWidget {
  const ReadingNowPage({super.key, required this.store});
  final LibraryStore store;

  @override
  State<ReadingNowPage> createState() => _ReadingNowPageState();
}

class _ReadingNowPageState extends State<ReadingNowPage> {
  final Map<String, String?> _covers = {};

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

  void _open(BookMeta b) {
    Navigator.of(context, rootNavigator: true).push(
      CupertinoPageRoute<void>(
        builder: (_) => ReaderScreen(book: b, store: widget.store),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final last = widget.store.lastRead;
    final reading = widget.store.inProgress;
    final others = widget.store.books
        .where((b) => b.id != last?.id && !reading.contains(b))
        .toList();

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemBackground,
      child: CustomScrollView(
        slivers: [
          const CupertinoSliverNavigationBar(
            largeTitle: Text('阅读中'),
            border: null,
          ),
          if (last == null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 60),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(CupertinoIcons.book,
                        size: 52,
                        color: CupertinoColors.systemGrey3.resolveFrom(context)),
                    const SizedBox(height: 16),
                    const Text('还没有在读的书',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    const Text('从书库选一本开始阅读',
                        style: TextStyle(
                            fontSize: 13,
                            color: CupertinoColors.secondaryLabel)),
                    const SizedBox(height: 20),
                    CupertinoButton.filled(
                      onPressed: () => importWithFeedback(context, widget.store),
                      child: const Text('导入图书'),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                child: _ContinueCard(
                  book: last,
                  coverPath: _covers[last.id],
                  onTap: () => _open(last),
                ),
              ),
            ),
            if (reading.isNotEmpty) ...[
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 26, 20, 10),
                  child: Text('正在阅读',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700)),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 196,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: reading.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 16),
                    itemBuilder: (_, i) {
                      final b = reading[i];
                      return SizedBox(
                        width: 96,
                        child: GestureDetector(
                          onTap: () => _open(b),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              BookCover(
                                  book: b,
                                  imagePath: _covers[b.id],
                                  width: 96),
                              const SizedBox(height: 6),
                              Text(b.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 12, height: 1.2)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
            if (others.isNotEmpty) ...[
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 22, 20, 10),
                  child: Text('书库精选',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700)),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 196,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: others.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 16),
                    itemBuilder: (_, i) {
                      final b = others[i];
                      return SizedBox(
                        width: 96,
                        child: GestureDetector(
                          onTap: () => _open(b),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              BookCover(
                                  book: b,
                                  imagePath: _covers[b.id],
                                  width: 96),
                              const SizedBox(height: 6),
                              Text(b.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 12, height: 1.2)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 30)),
          ],
        ],
      ),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({
    required this.book,
    required this.coverPath,
    required this.onTap,
  });

  final BookMeta book;
  final String? coverPath;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: CupertinoDynamicColor.resolve(
              CupertinoColors.secondarySystemGroupedBackground, context),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BookCover(book: book, imagePath: coverPath, width: 92),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('继续阅读',
                      style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 0.6,
                          color: CupertinoColors.secondaryLabel)),
                  const SizedBox(height: 5),
                  Text(book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w600)),
                  if (book.author.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(book.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12.5,
                            color: CupertinoColors.secondaryLabel)),
                  ],
                  const SizedBox(height: 12),
                  ProgressLine(value: book.progress),
                  const SizedBox(height: 6),
                  Text(
                    book.finished
                        ? '已读完'
                        : '已读 ${formatProgress(book.progress)} · 第 ${book.chapterIndex + 1} 章',
                    style: const TextStyle(
                        fontSize: 11.5, color: CupertinoColors.secondaryLabel),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 7),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFA5C2E).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Text('继续',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFFA5C2E))),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
