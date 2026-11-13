import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Realistic page-curl renderer (corner peel rolled around a cylinder).
///
/// Geometry, in page space: [n] is the unit normal of the crease pointing from
/// the lifted corner into the page, [tt] runs along the crease. A sheet point is
/// described by `u` = distance from the corner along [n].
///
/// The sheet stays flat while `u > c` (crease position). For `u < c` the paper
/// is wound around a cylinder of radius [radius]: at arc length `a = c - u` it
/// has wrapped `phi = a / radius`, so it projects to `u' = c - radius*sin(phi)`
/// and rises `radius*(1-cos(phi))` off the page. Each strip is drawn as a
/// clipped, anisotropically scaled copy of the page image and then shaded by the
/// cosine of its wrap angle — that is what makes the print compress and bend
/// instead of sliding under a gradient.
///
/// The reverse direction is *not* drawn by mirroring the canvas: mirroring would
/// flip the page bitmap and print the text backwards. Instead the corner and the
/// crease normal are mirrored and the images are drawn in their true
/// orientation.
class CurlPainter extends CustomPainter {
  CurlPainter({
    required this.current,
    required this.next,
    required this.forward,
    required this.paperColor,
    required this.progress,
    this.radiusFactor = 0.030,
    this.tilt = 0.0,
    this.strips = 24,
  }) : super(repaint: progress);

  final ui.Image current;
  final ui.Image next;
  final bool forward;
  final Color paperColor;

  /// Driven from the gesture: repaints without rebuilding the widget tree.
  final ValueListenable<double> progress;

  final double radiusFactor;
  final double tilt;
  final int strips;

  static const _phiMax = 2.25;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    final double t = progress.value.clamp(0.0, 1.0);
    final fullRect = Offset.zero & size;
    final srcRect = Rect.fromLTWH(
      0,
      0,
      current.width.toDouble(),
      current.height.toDouble(),
    );

    // ---- geometry ------------------------------------------------------
    // The crease always runs the same diagonal; only the side the sheet ends up
    // on changes. Mirroring the canvas instead would flip the page bitmap and
    // print the text backwards, which is exactly the reversed-page bug.
    final ang = math.pi / 4 + tilt;
    final n = Offset(-math.sin(ang), -math.cos(ang));
    final tt = Offset(-n.dy, n.dx);
    final corner = Offset(w, h);

    var uMax = 0.0;
    for (final p in [
      Offset.zero,
      Offset(w, 0),
      Offset(0, h),
      Offset(w, h),
    ]) {
      final u = (p - corner).dx * n.dx + (p - corner).dy * n.dy;
      if (u > uMax) uMax = u;
    }

    // Forward: the sheet leaves, so the crease sweeps into the page and the
    // revealed page grows. Backward: the sheet arrives, so the crease starts at
    // the far corner and sweeps back out while the sheet covers the page.
    final c = (forward ? uMax * t * 1.04 : uMax * (1.0 - t * 1.04))
        .clamp(0.0, uMax);
    final radius = math.max(h * radiusFactor, 6.0);
    final rollLen = radius * _phiMax;
    final phiLimit = c <= rollLen ? c / radius : _phiMax;

    double projU(double a) => c - radius * math.sin(math.min(a, rollLen) / radius);

    final huge = w + h;
    Path band(double u0, double u1) {
      final p0 = corner + n * u0;
      final p1 = corner + n * u1;
      return Path()
        ..moveTo(p0.dx + tt.dx * -huge, p0.dy + tt.dy * -huge)
        ..lineTo(p0.dx + tt.dx * huge, p0.dy + tt.dy * huge)
        ..lineTo(p1.dx + tt.dx * huge, p1.dy + tt.dy * huge)
        ..lineTo(p1.dx + tt.dx * -huge, p1.dy + tt.dy * -huge)
        ..close();
    }

    final pagePaint = Paint()
      ..filterQuality = FilterQuality.low
      ..isAntiAlias = false;

    // ---- 1. the page underneath ---------------------------------------
    canvas.drawImageRect(next, srcRect, fullRect, pagePaint);
    if (c <= 0.5) return;

    // ---- 2. shadow the lifted sheet throws on the revealed page --------
    final castStart = projU(math.min(rollLen, c));
    canvas.save();
    canvas.clipPath(band(castStart - h * 0.10, c));
    canvas.drawRect(
      fullRect,
      Paint()
        ..shader = ui.Gradient.linear(
          corner + n * (castStart - h * 0.10),
          corner + n * c,
          [const Color(0x00000000), const Color(0x70000000)],
        ),
    );
    canvas.restore();

    // ---- 3. the part of the sheet still lying flat ---------------------
    canvas.save();
    canvas.clipPath(band(c, huge));
    canvas.drawImageRect(current, srcRect, fullRect, pagePaint);
    canvas.restore();

    // dark seam exactly at the crease
    canvas.save();
    canvas.clipPath(band(c - 1.5, c + 1.5));
    canvas.drawRect(fullRect, Paint()..color = const Color(0x59000000));
    canvas.restore();

    // contact shadow where the sheet leaves the page
    canvas.save();
    canvas.clipPath(band(c, c + h * 0.07));
    canvas.drawRect(
      fullRect,
      Paint()
        ..shader = ui.Gradient.linear(
          corner + n * c,
          corner + n * (c + h * 0.07),
          [const Color(0x66000000), const Color(0x00000000)],
        ),
    );
    canvas.restore();

    // ---- 4. roll + flap ------------------------------------------------
    final rolled = math.min(c, rollLen);
    final start = 0.0;
    final frame = Matrix4.identity()
      ..translate(corner.dx, corner.dy)
      ..rotateZ(math.atan2(n.dy, n.dx));
    final inv = Matrix4.inverted(frame);
    final black = Paint();

    for (var i = 0; i < strips; i++) {
      final a0 = start + (rolled - start) * i / strips;
      final a1 = start + (rolled - start) * (i + 1) / strips;
      final u0 = projU(a0);
      final u1 = projU(a1);
      if ((u0 - u1).abs() < 0.05) continue;

      final midA = (a0 + a1) / 2;
      final phi = math.min(midA / radius, phiLimit);
      final back = phi > math.pi / 2;

      final quad = band(u0, u1);
      canvas.save();
      canvas.clipPath(quad);

      final dA = a1 - a0;
      final dX = u1 - u0;
      final k = dA.abs() < 0.001 ? 1.0 : -dX / dA;
      final srcMid = c - midA;
      final dstMid = (u0 + u1) / 2;
      canvas.transform((frame *
              (Matrix4.identity()
                ..translate(dstMid - k * srcMid, 0)
                ..scale(k, 1)) *
              inv)
          .storage);

      pagePaint.colorFilter = ColorFilter.mode(
        paperColor.withValues(
          alpha: back ? 0.985 : (0.10 + 0.80 * (phi / 1.25).clamp(0.0, 1.0)),
        ),
        BlendMode.srcOver,
      );
      canvas.drawImage(current, Offset.zero, pagePaint);
      canvas.restore();

      // Shading: cosine falloff of the curved surface, plus the ridge of
      // light on the outside of the roll. Painted as one clipped fill.
      final shade = back
          ? (1.0 -
                  (0.70 +
                          0.30 *
                              math.cos(
                                math.min(phi - math.pi / 2, math.pi / 2),
                              ))
                      .clamp(0.35, 1.0))
              .clamp(0.0, 1.0)
          : (1.0 - (0.22 + 0.78 * math.cos(phi)).clamp(0.06, 1.0))
              .clamp(0.0, 1.0);
      final ridge = (!back && phi > 0.15 && phi < 1.4)
          ? 0.055 * (1 - (phi - 0.75).abs() / 0.65)
          : 0.0;
      if (shade > 0.02 || ridge > 0.01) {
        canvas.save();
        canvas.clipPath(quad);
        if (shade > 0.02) {
          black.color = Colors.black.withValues(alpha: shade * 0.85);
          canvas.drawRect(fullRect, black);
        }
        if (ridge > 0.01) {
          black.color = Colors.white.withValues(alpha: ridge);
          canvas.drawRect(fullRect, black);
        }
        canvas.restore();
      }
    }
    pagePaint.colorFilter = null;
  }

  @override
  bool shouldRepaint(covariant CurlPainter old) =>
      old.current != current ||
      old.next != next ||
      old.forward != forward ||
      old.paperColor != paperColor ||
      old.radiusFactor != radiusFactor ||
      old.tilt != tilt ||
      old.strips != strips;
}
