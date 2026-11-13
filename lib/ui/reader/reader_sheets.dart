import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/settings_store.dart';
import '../theme.dart';

Future<void> showTocSheet({
  required BuildContext context,
  required List<Chapter> chapters,
  required int currentChapter,
  required ReaderPalette palette,
  required void Function(int chapter) onSelect,
}) {
  final controller = ScrollController(
    initialScrollOffset: (currentChapter * 52.0 - 120).clamp(0.0, 1e9),
  );
  return showCupertinoModalPopup<void>(
    context: context,
    builder: (ctx) => Container(
      height: MediaQuery.sizeOf(ctx).height * 0.62,
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 4),
            width: 36,
            height: 4.5,
            decoration: BoxDecoration(
              color: palette.secondary.withOpacity(0.4),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
            child: Row(
              children: [
                Text('目录',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: palette.text)),
                const Spacer(),
                Text('${chapters.length} 章',
                    style: TextStyle(fontSize: 13, color: palette.secondary)),
                CupertinoButton(
                  padding: const EdgeInsets.only(left: 14),
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text('完成',
                      style: TextStyle(fontSize: 16, color: palette.accent)),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: palette.secondary.withOpacity(0.18)),
          Expanded(
            child: ListView.builder(
              controller: controller,
              itemCount: chapters.length,
              itemBuilder: (_, i) {
                final selected = i == currentChapter;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    onSelect(i);
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: palette.secondary.withOpacity(0.10),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            chapters[i].title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              color: selected ? palette.accent : palette.text,
                              fontWeight:
                                  selected ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ),
                        Text('${(i + 1)}',
                            style: TextStyle(
                                fontSize: 12, color: palette.secondary)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

Future<void> showStyleSheet({
  required BuildContext context,
  required SettingsStore store,
  required ReaderPalette palette,
}) {
  return showCupertinoModalPopup<void>(
    context: context,
    builder: (ctx) => AnimatedBuilder(
      animation: store,
      builder: (ctx, _) {
        final s = store.reader;
        final p = paletteFor(s.theme);
        return Container(
          decoration: BoxDecoration(
            color: p.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(ctx).bottom + 12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 4),
                width: 36,
                height: 4.5,
                decoration: BoxDecoration(
                  color: p.secondary.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              _row(
                p,
                label: '字号',
                child: Row(
                  children: [
                    _smallA(p, 13),
                    Expanded(
                      child: CupertinoSlider(
                        value: s.fontSize,
                        min: 14,
                        max: 30,
                        divisions: 16,
                        activeColor: p.accent,
                        onChanged: (v) =>
                            store.update((x) => x.fontSize = v.roundToDouble()),
                      ),
                    ),
                    _smallA(p, 22),
                  ],
                ),
              ),
              _row(
                p,
                label: '行距',
                child: Row(
                  children: [
                    Expanded(
                      child: CupertinoSlider(
                        value: s.lineHeight,
                        min: 1.2,
                        max: 2.3,
                        divisions: 11,
                        activeColor: p.accent,
                        onChanged: (v) => store.update(
                            (x) => x.lineHeight = (v * 10).round() / 10),
                      ),
                    ),
                  ],
                ),
              ),
              _row(
                p,
                label: '字体',
                child: CupertinoSlidingSegmentedControl<String>(
                  groupValue: s.fontKey,
                  backgroundColor: p.secondary.withOpacity(0.12),
                  thumbColor: p.background,
                  children: const {
                    'system': Padding(
                        padding: EdgeInsets.symmetric(vertical: 5),
                        child: Text('系统')),
                    'song': Padding(
                        padding: EdgeInsets.symmetric(vertical: 5),
                        child: Text('宋体', style: TextStyle(fontFamily: 'Songti SC'))),
                    'hei': Padding(
                        padding: EdgeInsets.symmetric(vertical: 5),
                        child: Text('黑体', style: TextStyle(fontFamily: 'PingFang SC'))),
                    'kai': Padding(
                        padding: EdgeInsets.symmetric(vertical: 5),
                        child: Text('楷体', style: TextStyle(fontFamily: 'Kaiti SC'))),
                  },
                  onValueChanged: (v) {
                    if (v != null) store.update((x) => x.fontKey = v);
                  },
                ),
              ),
              _row(
                p,
                label: '主题',
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: ReaderThemeKind.values.map((kind) {
                    final pp = paletteFor(kind);
                    final selected = kind == s.theme;
                    return GestureDetector(
                      onTap: () => store.update((x) => x.theme = kind),
                      child: Container(
                        width: 52,
                        height: 38,
                        decoration: BoxDecoration(
                          color: pp.background,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: selected
                                ? pp.accent
                                : pp.secondary.withOpacity(0.45),
                            width: selected ? 2 : 1,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            _themeLabel(kind),
                            style: TextStyle(
                              fontSize: 12,
                              color: pp.text,
                              fontWeight:
                                  selected ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              _row(
                p,
                label: '翻页',
                child: CupertinoSlidingSegmentedControl<PageTurnStyle>(
                  groupValue: s.turn,
                  backgroundColor: p.secondary.withOpacity(0.12),
                  thumbColor: p.background,
                  children: const {
                    PageTurnStyle.curl:
                        Padding(padding: EdgeInsets.symmetric(vertical: 5), child: Text('仿真')),
                    PageTurnStyle.slide:
                        Padding(padding: EdgeInsets.symmetric(vertical: 5), child: Text('滑动')),
                    PageTurnStyle.none:
                        Padding(padding: EdgeInsets.symmetric(vertical: 5), child: Text('无')),
                  },
                  onValueChanged: (v) {
                    if (v != null) store.update((x) => x.turn = v);
                  },
                ),
              ),
              _row(
                p,
                label: '两端对齐',
                child: Row(
                  children: [
                    CupertinoSwitch(
                      value: s.justify,
                      activeColor: p.accent,
                      onChanged: (v) => store.update((x) => x.justify = v),
                    ),
                  ],
                ),
              ),
              _row(
                p,
                label: '首行缩进',
                child: Row(
                  children: [
                    CupertinoSwitch(
                      value: s.indent,
                      activeColor: p.accent,
                      onChanged: (v) => store.update((x) => x.indent = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
            ],
          ),
        );
      },
    ),
  );
}

String _themeLabel(ReaderThemeKind kind) {
  switch (kind) {
    case ReaderThemeKind.white:
      return '白';
    case ReaderThemeKind.sepia:
      return '米黄';
    case ReaderThemeKind.gray:
      return '灰';
    case ReaderThemeKind.night:
      return '夜';
  }
}

Widget _row(ReaderPalette p, {required String label, required Widget child}) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 62,
          child: Text(label,
              style: TextStyle(fontSize: 13, color: p.secondary)),
        ),
        Expanded(child: child),
      ],
    ),
  );
}

Widget _smallA(ReaderPalette p, double size) => SizedBox(
      width: 22,
      child: Text('A',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: size, color: p.text)),
    );
