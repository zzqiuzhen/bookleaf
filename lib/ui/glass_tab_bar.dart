import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Floating "liquid glass" tab bar: a translucent pill that content scrolls
/// under. Built from a backdrop blur (with a saturation boost, which is what
/// makes frosted glass look alive instead of grey), a soft white gradient, a
/// hairline rim and a wide ambient shadow.
class GlassTabBar extends StatelessWidget {
  const GlassTabBar({
    super.key,
    required this.index,
    required this.onChanged,
    required this.items,
    this.accent = const Color(0xFFFA5C2E),
  });

  final int index;
  final ValueChanged<int> onChanged;
  final List<GlassTabItem> items;
  final Color accent;

  static const double barHeight = 62;

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 0, 18, (safeBottom > 0 ? safeBottom : 12) + 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(barHeight / 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.20),
              blurRadius: 34,
              spreadRadius: 2,
              offset: const Offset(0, 14),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(barHeight / 2),
          child: BackdropFilter(
            filter: ui.ImageFilter.compose(
              outer: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              inner: ui.ColorFilter.matrix(_saturate(1.7)),
            ),
            child: Container(
              height: barHeight,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.66),
                    Colors.white.withValues(alpha: 0.40),
                    Colors.white.withValues(alpha: 0.30),
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
                borderRadius: BorderRadius.circular(barHeight / 2),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.85),
                  width: 1.0,
                ),
              ),
              child: Stack(
                children: [
                  // inner shading: darker at the bottom edge, like a lens
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(barHeight / 2),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withValues(alpha: 0.16),
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.05),
                          ],
                          stops: const [0.0, 0.45, 1.0],
                        ),
                      ),
                    ),
                  ),
                  // top rim highlight
                  Positioned(
                    left: 22,
                    right: 22,
                    top: 0,
                    child: Container(
                      height: 1.2,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0),
                            Colors.white.withValues(alpha: 1),
                            Colors.white.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // bottom edge shadow line
                  Positioned(
                    left: 18,
                    right: 18,
                    bottom: 0,
                    child: Container(
                      height: 1,
                      color: Colors.black.withValues(alpha: 0.05),
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < items.length; i++)
                        Expanded(
                          child: _GlassTabButton(
                            item: items[i],
                            selected: i == index,
                            accent: accent,
                            onTap: () {
                              if (i == index) return;
                              HapticFeedback.selectionClick();
                              onChanged(i);
                            },
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static List<double> _saturate(double s) => <double>[
        s, 0, 0, 0, 0, //
        0, s, 0, 0, 0, //
        0, 0, s, 0, 0, //
        0, 0, 0, 1, 0, //
      ];
}

class GlassTabItem {
  const GlassTabItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
  final IconData icon;
  final IconData activeIcon;
  final String label;
}

class _GlassTabButton extends StatelessWidget {
  const _GlassTabButton({
    required this.item,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final GlassTabItem item;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.symmetric(
            horizontal: selected ? 16 : 12,
            vertical: 7,
          ),
          decoration: BoxDecoration(
            color: selected
                ? Colors.white.withValues(alpha: 0.55)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: selected
                ? Border.all(
                    color: Colors.white.withValues(alpha: 0.85),
                    width: 0.8,
                  )
                : null,
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: const Color(0xFFFA5C2E).withValues(alpha: 0.10),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 6,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: Icon(
                  selected ? item.activeIcon : item.icon,
                  key: ValueKey(selected),
                  size: 20,
                  color: selected
                      ? accent
                      : CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                item.label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected
                      ? accent
                      : CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
