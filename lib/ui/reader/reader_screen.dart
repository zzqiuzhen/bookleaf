import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../models.dart';
import '../../services/library_store.dart';
import '../../services/paginator.dart';
import '../../services/settings_store.dart';
import '../theme.dart';
import 'curl.dart';
import 'reader_sheets.dart';

enum _TurnDir { none, forward, backward }

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.book,
    required this.store,
    this.startPage,
  });

  final BookMeta book;
  final LibraryStore store;
  final int? startPage;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen>
    with TickerProviderStateMixin {
  final SettingsStore _settingsStore = SettingsStore.instance;
  ReaderSettings get _s => _settingsStore.reader;

  List<Chapter> _rawChapters = const [];
  List<Chapter> _chapters = const [];
  BookLayout? _layout;
  bool _loading = true;
  double _layoutProgress = 0;

  int _page = 0;
  bool _chrome = false;

  final GlobalKey _curKey = GlobalKey();
  final GlobalKey _prevKey = GlobalKey();
  final GlobalKey _nextKey = GlobalKey();

  ui.Image? _curImg;
  ui.Image? _prevImg;
  ui.Image? _nextImg;

  _TurnDir _dir = _TurnDir.none;
  final ValueNotifier<double> _turn = ValueNotifier<double>(0);
  double _dragAccum = 0;
  double _dragVelocity = 0;
  Offset? _downPos;
  DateTime? _downAt;
  Offset? _lastMovePos;
  DateTime? _lastMoveAt;
  AnimationController? _turnCtrl;

  /// Painted while a turn is in flight; the pages underneath stay untouched.
  CurlPainter? _painter;

  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onPause: _saveProgress);
    _settingsStore.addListener(_onSettingsChanged);
    _load();
  }

  @override
  void dispose() {
    _saveProgress();
    _settingsStore.removeListener(_onSettingsChanged);
    _lifecycle.dispose();
    _turnCtrl?.dispose();
    _turn.dispose();
    _curImg?.dispose();
    _prevImg?.dispose();
    _nextImg?.dispose();
    super.dispose();
  }

  bool _needsRelayout = false;

  void _onSettingsChanged() {
    if (!mounted) return;
    setState(() {});
    _needsRelayout = true;
    _scheduleRelayout();
  }

  Timer? _relayoutTimer;
  void _scheduleRelayout() {
    _relayoutTimer?.cancel();
    _relayoutTimer = Timer(const Duration(milliseconds: 180), () async {
      if (!mounted || !_needsRelayout) return;
      _needsRelayout = false;
      final currentPos = _layout == null || _layout!.pages.isEmpty
          ? (chapter: widget.book.chapterIndex, offset: widget.book.charOffset)
          : () {
              final p = _layout!.pages[_page];
              return (chapter: p.chapter, offset: p.start);
            }();
      await _buildLayout();
      if (!mounted || _layout == null) return;
      final target = _layout!.pageForPosition(currentPos.chapter, currentPos.offset);
      setState(() => _page = target);
      _scheduleCapture();
    });
  }

  Future<void> _load() async {
    final chapters = await widget.store.chaptersOf(widget.book);
    if (!mounted) return;
    if (chapters.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    _rawChapters = chapters;
    await _buildLayout();
    if (!mounted || _layout == null) return;
    final start = widget.startPage ??
        _layout!.pageForPosition(widget.book.chapterIndex, widget.book.charOffset);
    setState(() {
      _page = start.clamp(0, _layout!.totalPages - 1);
      _loading = false;
    });
    widget.store.markOpened(widget.book);
    _scheduleCapture();
  }

  Future<void> _buildLayout() async {
    if (_rawChapters.isEmpty) return;
    _chapters = _s.indent
        ? _rawChapters
            .map((c) => Chapter(c.title, applyIndent(c.text)))
            .toList()
        : _rawChapters;
    final size = MediaQuery.sizeOf(context);
    final safe = MediaQuery.paddingOf(context);
    final metrics = PageGeometry.of(size, safe);
    final palette = paletteFor(_s.theme);
    final style = readerBodyStyle(_s, palette);
    final layout = await Paginator.build(
      chapters: _chapters,
      style: style,
      maxWidth: metrics.textWidth,
      maxHeight: metrics.textHeight,
      align: _s.justify ? TextAlign.justify : TextAlign.start,
      firstPageReduction: metrics.chapterTitleSpace,
      onProgress: (p) {
        if (mounted) setState(() => _layoutProgress = p);
      },
    );
    if (!mounted) return;
    setState(() => _layout = layout);
  }

  // ---------------------------------------------------------------- capture
  Future<ui.Image?> _cap(GlobalKey key, double ratio) async {
    final obj = key.currentContext?.findRenderObject();
    if (obj is! RenderRepaintBoundary) return null;
    try {
      return await obj.toImage(pixelRatio: ratio);
    } catch (e) {
      debugPrint('capture failed: $e');
      return null;
    }
  }

  void _scheduleCapture() {
    Future<void>.delayed(const Duration(milliseconds: 90), () async {
      if (!mounted || _dir != _TurnDir.none) return;
      final ratio = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 2.0);
      final cur = await _cap(_curKey, ratio);
      final next = _hasNext ? await _cap(_nextKey, ratio) : null;
      final prev = _hasPrev ? await _cap(_prevKey, ratio) : null;
      if (!mounted) return;
      _curImg?.dispose();
      _prevImg?.dispose();
      _nextImg?.dispose();
      setState(() {
        _curImg = cur;
        _nextImg = next;
        _prevImg = prev;
      });
    });
  }

  bool get _hasNext => _layout != null && _page < _layout!.totalPages - 1;
  bool get _hasPrev => _page > 0;

  /// Snapshots are taken from the rendered pages; without them (e.g. on the
  /// web preview, where toImage is unsupported) we fall back to a slide.
  bool get _canCurlForward => _curImg != null && _nextImg != null;
  bool get _canCurlBackward => _curImg != null && _prevImg != null;

  // ---------------------------------------------------------------- turning
  void _beginTurn(_TurnDir dir) {
    if (_dir == dir) return;
    _turnCtrl?.stop();
    _turn.value = 0;
    setState(() {
      _dir = dir;
      _painter = null;
    });
    _ensurePainter();
  }

  /// Builds the curl painter for the current direction (once per turn).
  void _ensurePainter() {
    if (_dir == _TurnDir.none) return;
    final cur = _curImg;
    if (cur == null) return;
    final forward = _dir == _TurnDir.forward;
    final top = forward ? _nextImg : _prevImg;
    if (top == null) return;
    if (_painter != null && _painter!.forward == forward) return;
    setState(() {
      _painter = CurlPainter(
        // "current" is the sheet being turned, "next" is what it reveals.
        current: cur,
        next: top,
        forward: forward,
        paperColor: paletteFor(_s.theme).paperBack,
        progress: _turn,
      );
    });
  }

  void _startProgrammaticTurn(_TurnDir dir) {
    if (_dir != _TurnDir.none) return;
    if (dir == _TurnDir.forward && !_hasNext) return;
    if (dir == _TurnDir.backward && !_hasPrev) return;
    _beginTurn(dir);
    _animateTurn(toComplete: true, fling: true);
  }

  void _animateTurn({required bool toComplete, bool fling = false}) {
    final target = toComplete ? 1.0 : 0.0;
    final distance = (target - _turn.value).abs();
    // Long enough to read as paper: a full turn takes ~520 ms, a flick ~300 ms.
    final ms = fling
        ? (300 + 220 * distance).round()
        : (200 + 380 * distance).round();
    _turnCtrl?.dispose();
    final ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: ms.clamp(160, 620)),
    );
    final anim = Tween<double>(begin: _turn.value, end: target).animate(
      CurvedAnimation(
        parent: ctrl,
        curve: toComplete ? Curves.easeOutCubic : Curves.easeOutQuart,
      ),
    );
    anim.addListener(() => _turn.value = anim.value);
    ctrl.addStatusListener((status) {
      if (!mounted || status != AnimationStatus.completed) return;
      if (target >= 1.0) {
        _commitTurn();
      } else {
        setState(() {
          _turn.value = 0;
          _dir = _TurnDir.none;
          _painter = null;
        });
      }
    });
    _turnCtrl = ctrl;
    ctrl.forward();
  }

  void _commitTurn() {
    final delta = _dir == _TurnDir.forward ? 1 : -1;
    setState(() {
      _page = (_page + delta).clamp(0, (_layout?.totalPages ?? 1) - 1);
      _turn.value = 0;
      _dir = _TurnDir.none;
      _painter = null;
    });
    _saveProgress();
    _scheduleCapture();
  }

  void _goNext() {
    if (_s.turn == PageTurnStyle.curl && _canCurlForward) {
      _startProgrammaticTurn(_TurnDir.forward);
    } else if (_hasNext) {
      setState(() => _page++);
      _saveProgress();
      _scheduleCapture();
    }
  }

  void _goPrev() {
    if (_s.turn == PageTurnStyle.curl && _canCurlBackward) {
      _startProgrammaticTurn(_TurnDir.backward);
    } else if (_hasPrev) {
      setState(() => _page--);
      _saveProgress();
      _scheduleCapture();
    }
  }

  void _saveProgress() {
    final layout = _layout;
    if (layout == null || layout.pages.isEmpty) return;
    final ref = layout.pages[_page.clamp(0, layout.totalPages - 1)];
    widget.store.saveProgress(
      widget.book,
      chapterIndex: ref.chapter,
      charOffset: ref.start,
      finished: _page >= layout.totalPages - 1,
    );
  }

  // ---------------------------------------------------------------- gesture
  bool get _curlGestureAvailable =>
      _s.turn == PageTurnStyle.curl && (_canCurlForward || _canCurlBackward);

  void _onPointerDown(PointerDownEvent e) {
    if (_loading || _layout == null) return;
    _downPos = e.localPosition;
    _downAt = DateTime.now();
    _lastMovePos = e.localPosition;
    _lastMoveAt = _downAt;
    _dragAccum = 0;
    _dragVelocity = 0;
    _turnCtrl?.stop();
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (_downPos == null || !_curlGestureAvailable) return;
    final width = MediaQuery.sizeOf(context).width;
    _dragAccum += e.delta.dx;

    final now = DateTime.now();
    if (_lastMovePos != null && _lastMoveAt != null) {
      final dt = now.difference(_lastMoveAt!).inMicroseconds;
      if (dt > 0) {
        _dragVelocity = 0.7 * _dragVelocity +
            0.3 * (e.delta.dx / (dt / 1000000));
      }
    }
    _lastMovePos = e.localPosition;
    _lastMoveAt = now;

    if (_dir == _TurnDir.none) {
      final wantForward = _dragAccum < 0;
      if (wantForward && _canCurlForward) {
        _beginTurn(_TurnDir.forward);
      } else if (!wantForward && _canCurlBackward) {
        _beginTurn(_TurnDir.backward);
      }
      if (_dir == _TurnDir.none) return;
    }

    // Fire the curl as soon as the finger moves: no dead zone, and the sheet
    // tracks the finger 1:1 across ~92% of the page width.
    final mag = (_dragAccum.abs() / (width * 0.92)).clamp(0.0, 1.0);
    _turn.value = mag;
    if (mag >= 0.999) _commitTurn();
  }

  void _onPointerUp(PointerUpEvent e) {
    final down = _downPos;
    final at = _downAt;
    _downPos = null;
    _downAt = null;
    if (down == null || at == null) return;

    final moved = (e.localPosition - down).distance;
    final elapsed = DateTime.now().difference(at);
    if (_dir == _TurnDir.none) {
      if (moved < 12 && elapsed < Duration(milliseconds: 400)) {
        _handleTapAt(e.localPosition);
      }
      return;
    }
    if (moved < 12) {
      // a tap that happened to start a turn: undo it quietly
      _animateTurn(toComplete: false);
      return;
    }
    final velocity = _dragVelocity.abs() > 1 ? _dragVelocity : 0.0;
    final flick = velocity.abs() > 650;
    final sameDirection =
        (_dir == _TurnDir.forward && velocity < 0) ||
            (_dir == _TurnDir.backward && velocity > 0);
    final complete = (flick && sameDirection) || _turn.value > 0.32;
    _animateTurn(toComplete: complete);
  }

  void _handleTapAt(Offset local) {
    final width = MediaQuery.sizeOf(context).width;
    final x = local.dx;
    if (_chrome) {
      setState(() => _chrome = false);
      return;
    }
    if (x < width * 0.28) {
      _goPrev();
    } else if (x > width * 0.72) {
      _goNext();
    } else {
      setState(() => _chrome = true);
    }
  }

  // ---------------------------------------------------------------- build
  @override
  Widget build(BuildContext context) {
    final palette = paletteFor(_s.theme);
    final safe = MediaQuery.paddingOf(context);
    return Scaffold(
      backgroundColor: palette.background,
      body: _loading
          ? _buildLoading(palette)
          : Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerUp,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_s.turn == PageTurnStyle.curl)
                    _buildCurlStack(palette)
                  else
                    AnimatedSwitcher(
                      duration: _s.turn == PageTurnStyle.none
                          ? Duration.zero
                          : const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOut,
                      transitionBuilder: (child, anim) => SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0.04, 0),
                          end: Offset.zero,
                        ).animate(anim),
                        child: FadeTransition(opacity: anim, child: child),
                      ),
                      child: KeyedSubtree(
                        key: ValueKey<int>(_page),
                        child: _pageWidget(_page),
                      ),
                    ),
                  if (_chrome) ..._chromeOverlay(palette, safe),
                ],
              ),
            ),
    );
  }

  Widget _buildCurlStack(ReaderPalette palette) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_hasPrev)
          RepaintBoundary(key: _prevKey, child: _pageWidget(_page - 1)),
        if (_hasNext)
          RepaintBoundary(key: _nextKey, child: _pageWidget(_page + 1)),
        RepaintBoundary(key: _curKey, child: _pageWidget(_page)),
        if (_painter != null)
          IgnorePointer(
            child: RepaintBoundary(child: CustomPaint(painter: _painter)),
          ),
      ],
    );
  }

  Widget _buildLoading(ReaderPalette palette) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CupertinoActivityIndicator(radius: 14, color: palette.secondary),
          const SizedBox(height: 16),
          Text(
            _layoutProgress > 0
                ? '正在排版 ${(_layoutProgress * 100).round()}%'
                : '正在打开',
            style: TextStyle(fontSize: 13, color: palette.secondary),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- page
  Widget _pageWidget(int index) {
    final layout = _layout;
    final palette = paletteFor(_s.theme);
    final safe = MediaQuery.paddingOf(context);
    final metrics = PageGeometry.of(MediaQuery.sizeOf(context), safe);
    if (layout == null || layout.pages.isEmpty) {
      return Container(color: palette.background);
    }
    final pageIndex = index.clamp(0, layout.totalPages - 1);
    final ref = layout.pages[pageIndex];
    final chapter = ref.chapter >= 0 && ref.chapter < _chapters.length
        ? _chapters[ref.chapter]
        : const Chapter('', '');
    final end = ref.end.clamp(0, chapter.text.length);
    final start = ref.start.clamp(0, end);
    final text = chapter.text.substring(start, end);
    final isChapterStart =
        ref.chapter < layout.chapterFirstPage.length &&
            layout.chapterFirstPage[ref.chapter] == pageIndex;
    final style = readerBodyStyle(_s, palette);
    final align = _s.justify ? TextAlign.justify : TextAlign.start;

    return Container(
      color: palette.background,
      padding: EdgeInsets.only(top: safe.top, bottom: safe.bottom),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: metrics.horizontalPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: metrics.headerHeight,
              child: Center(
                child: Text(
                  widget.book.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    letterSpacing: 0.8,
                    color: palette.secondary,
                  ),
                ),
              ),
            ),
            Expanded(
              child: isChapterStart
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: metrics.chapterTitleSpace,
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                chapter.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 21,
                                  height: 1.3,
                                  fontWeight: FontWeight.w600,
                                  color: palette.text,
                                  fontFamily: fontFamilyFor(_s.fontKey),
                                  fontFamilyFallback: const [
                                    'Songti SC',
                                    'PingFang SC',
                                    'serif',
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            text,
                            style: style,
                            textAlign: align,
                            textScaler: TextScaler.noScaling,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      text,
                      style: style,
                      textAlign: align,
                      textScaler: TextScaler.noScaling,
                    ),
            ),
            SizedBox(
              height: metrics.footerHeight,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '${pageIndex + 1}',
                    style: TextStyle(
                      fontSize: 10.5,
                      letterSpacing: 0.6,
                      color: palette.secondary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- chrome
  List<Widget> _chromeOverlay(ReaderPalette palette, EdgeInsets safe) {
    final layout = _layout;
    final total = layout?.totalPages ?? 1;
    final ref = layout != null && layout.pages.isNotEmpty
        ? layout.pages[_page.clamp(0, layout.pages.length - 1)]
        : null;
    final chapterTitle = ref != null && ref.chapter < _chapters.length
        ? _chapters[ref.chapter].title
        : widget.book.title;
    final chromeColor = palette.chromeScrim.withOpacity(0.97);

    return [
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: Container(
          color: chromeColor,
          padding: EdgeInsets.only(top: safe.top + 2, bottom: 6),
          child: Row(
            children: [
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: Size.zero,
                onPressed: () => Navigator.of(context).maybePop(),
                child: Icon(CupertinoIcons.chevron_back,
                    size: 22, color: palette.text),
              ),
              Expanded(
                child: Text(
                  chapterTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: palette.text,
                  ),
                ),
              ),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: Size.zero,
                onPressed: _openToc,
                child:
                    Icon(CupertinoIcons.list_bullet, size: 22, color: palette.text),
              ),
            ],
          ),
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Container(
          color: chromeColor,
          padding: EdgeInsets.only(
            top: 10,
            bottom: safe.bottom + 4,
            left: 18,
            right: 18,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text('${_page + 1}',
                      style: TextStyle(fontSize: 11, color: palette.secondary)),
                  Expanded(
                    child: CupertinoSlider(
                      value: (_page / (total - 1 <= 0 ? 1 : total - 1))
                          .clamp(0.0, 1.0),
                      activeColor: palette.accent,
                      onChanged: (v) {
                        final target = (v * (total - 1)).round();
                        setState(() => _page = target.clamp(0, total - 1));
                        _saveProgress();
                      },
                      onChangeEnd: (_) => _scheduleCapture(),
                    ),
                  ),
                  Text('$total',
                      style: TextStyle(fontSize: 11, color: palette.secondary)),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _bottomAction(palette, CupertinoIcons.list_bullet, '目录', _openToc),
                  _bottomAction(
                      palette, CupertinoIcons.textformat, '样式', _openStyle),
                  _bottomAction(palette, CupertinoIcons.chevron_left_slash_chevron_right,
                      '跳转', _jumpDialog),
                ],
              ),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _bottomAction(
    ReaderPalette palette,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 14),
      minimumSize: Size.zero,
      onPressed: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 21, color: palette.text),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 10.5, color: palette.secondary)),
        ],
      ),
    );
  }

  void _openToc() {
    final layout = _layout;
    if (layout == null || layout.pages.isEmpty) return;
    final current = layout.pages[_page].chapter;
    showTocSheet(
      context: context,
      chapters: _chapters,
      currentChapter: current,
      palette: paletteFor(_s.theme),
      onSelect: (chapter) {
        final target = layout.chapterFirstPage[chapter];
        setState(() => _page = target.clamp(0, layout.totalPages - 1));
        _saveProgress();
        _scheduleCapture();
      },
    );
  }

  void _openStyle() {
    showStyleSheet(
      context: context,
      store: _settingsStore,
      palette: paletteFor(_s.theme),
    );
  }

  Future<void> _jumpDialog() async {
    final layout = _layout;
    if (layout == null) return;
    final controller =
        TextEditingController(text: '${(_page + 1)}');
    final palette = paletteFor(_s.theme);
    await showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('跳转到页'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CupertinoTextField(
                controller: controller,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                placeholder: '1 - ${layout.totalPages}',
              ),
              const SizedBox(height: 8),
              Text('共 ${layout.totalPages} 页',
                  style: TextStyle(fontSize: 12, color: palette.secondary)),
            ],
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              final n = int.tryParse(controller.text.trim());
              Navigator.of(ctx).pop();
              if (n == null) return;
              setState(() => _page = (n - 1).clamp(0, layout.totalPages - 1));
              _saveProgress();
              _scheduleCapture();
            },
            child: const Text('跳转'),
          ),
        ],
      ),
    );
  }
}

