import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Realistic page-curl renderer (corner peel, cylinder roll).
///
/// Geometry, in page space: [n] is the unit normal of the crease pointing from
/// the lifted corner into the page, [tt] runs along the crease. A point of the
/// sheet is described by `u` = distance from the corner along [n].
///
/// The sheet is flat while `u > c` (crease position). For `u < c` the material
/// is rolled around a cylinder of radius [radius]: at arc length `a = c - u`
/// the surface has wrapped `phi = a / radius`, so its projection lands at
/// `u' = c - radius * sin(phi)` and it rises `radius * (1 - cos(phi))` above the
/// page. Once the wrap limit is reached the sheet continues as a straight
/// tangent (the flap that flops over the page). Each strip is drawn as a
/// clipped, anisotropically scaled copy of the page image, then shaded by the
/// cosine of its wrap angle — which is what makes the text compress and bend
/// like paper instead of sliding under a gradient.
class CurlPainter extends CustomPainter {
  CurlPainter({
    required this.current,
    required this.next,
    required this.progress,
    required this.forward,
    required this.paperColor,
    this.radiusFactor = 0.032,
    this.tilt = 0.0,
    this.strips = 40,
  });

  final ui.Image current;
  final ui.Image next;
  final double progress; // 0..1
  final bool forward;
  final Color paperColor;
  final double radiusFactor; // roll radius as a fraction of page height
  final double tilt; // crease angle offset in radians
  final int strips;

  static const _phiMax = 2.25;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    canvas.save();
    if (!forward) {
      canvas.translate(w, 0);
      canvas.scale(-1, 1);
    }

    final ang = math.pi / 4 + tilt;
    final n = Offset(-math.sin(ang), -math.cos(ang)); // corner -> page
    final tt = Offset(-n.dy, n.dx);
    final corner = Offset(w, h);
    final uMax = w * -n.dx + h * -n.dy;

    final double c = (uMax * progress * 1.04).clamp(0.0, uMax);
    final double radius = math.max(h * radiusFactor, 6.0);
    final double rollLen = radius * _phiMax;
    final double phiLimit = c <= rollLen ? c / radius : _phiMax;

    // a = arc length from the crease; a < 0 is the page side, where the sheet
    // already starts to lift, so the print foreshortens into the fold.
    final double bend = 0.0;               // no pre-bend: the fold starts at the crease
    final double r2 = math.max(bend / 0.55, 1.0);
    // The sheet ends at the roll: everything beyond stays wound up, so the
    // revealed page appears right behind the curled edge.
    double projU(double a) {
      if (a < 0) {
        final t = math.min(-a, bend) / r2;
        return c + r2 * math.sin(t);
      }
      return c - radius * math.sin(math.min(a, rollLen) / radius);
    }

    final double huge = w + h; // enough to span the page from any crease
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

    final fullRect = Offset.zero & size;
    final srcRect = Rect.fromLTWH(
      0,
      0,
      current.width.toDouble(),
      current.height.toDouble(),
    );
    final pagePaint = Paint()..filterQuality = FilterQuality.medium;

    // ---- 1. the page underneath -------------------------------------------
    canvas.drawImageRect(next, srcRect, fullRect, pagePaint);

    // ---- 2. shadow the lifted sheet throws on the revealed page -----------
    if (c > 0.5) {
      final castStart = projU(math.min(rollLen, c));
      final shader = ui.Gradient.linear(
        corner + n * (castStart - h * 0.10),
        corner + n * c,
        [const Color(0x00000000), const Color(0x73000000)],
      );
      canvas.save();
      canvas.clipPath(band(castStart - h * 0.10, c));
      canvas.drawRect(fullRect, Paint()..shader = shader);
      canvas.restore();
    }

    // ---- 3. the part of the sheet still lying flat ------------------------
    canvas.save();
    canvas.clipPath(band(c + bend + 1, huge));
    canvas.drawImageRect(current, srcRect, fullRect, pagePaint);
    canvas.restore();

    // dark seam exactly at the crease
    if (c > 0.5) {
      canvas.save();
      canvas.clipPath(band(c - 1.5, c + 1.5));
      canvas.drawRect(fullRect, Paint()..color = Colors.black.withValues(alpha: 0.35));
      canvas.restore();
    }

    // contact shadow where the sheet leaves the page
    if (c > 0.5) {
      final shader = ui.Gradient.linear(
        corner + n * c,
        corner + n * (c + h * 0.07),
        [const Color(0x66000000), const Color(0x00000000)],
      );
      canvas.save();
      canvas.clipPath(band(c, c + h * 0.07));
      canvas.drawRect(fullRect, Paint()..shader = shader);
      canvas.restore();
    }

    // ---- 4. the roll and the flap -----------------------------------------
    if (c > 0.2) {
      // Walk arc length from the crease toward the corner, so later strips
      // (which belong to the flap lying on top) paint over earlier ones.
      final count = strips;
      final rolled = math.min(c, rollLen);
      final start = -bend;
      for (var i = 0; i < count; i++) {
        final a0 = start + (rolled - start) * i / count;
        final a1 = start + (rolled - start) * (i + 1) / count;
        final u0 = projU(a0);
        final u1 = projU(a1);
        if ((u0 - u1).abs() < 0.05) continue;

        final stripMidA = (a0 + a1) / 2;
        final phi = stripMidA <= 0 ? 0.0 : math.min(stripMidA / radius, phiLimit);
        final back = phi > math.pi / 2;

        final quad = band(u0, u1);
        canvas.save();
        canvas.clipPath(quad);

        // isotropic frame: x along n, y along tt
        final frame = Matrix4.identity()
          ..translate(corner.dx, corner.dy)
          ..rotateZ(math.atan2(n.dy, n.dx));
        final inv = Matrix4.inverted(frame);
        final dA = a1 - a0;            // arc length of the strip
        final dX = u1 - u0;            // its projected width
        final k = dA.abs() < 0.001 ? 1.0 : -dX / dA;
        final srcMid = c - stripMidA;       // page coordinate of the strip centre
        final dstMid = (u0 + u1) / 2;  // where it lands on screen
        final scale = Matrix4.identity()
          ..translate(dstMid - k * srcMid, 0)
          ..scale(k, 1);
        final m = frame * scale * inv;

        // Paper is opaque: the print fades out as the surface turns away, so
        // the roll reads as an edge instead of smeared text.
        final double veil = back
            ? 0.985
            : (0.10 + 0.80 * (phi / 1.25).clamp(0.0, 1.0));
        pagePaint.colorFilter =
            ColorFilter.mode(paperColor.withValues(alpha: veil), BlendMode.srcOver);
        canvas.transform(m.storage);
        canvas.drawImage(current, Offset.zero, pagePaint);
        canvas.restore();

        // shading: cosine falloff of the curved surface
        final bright = back
            ? (0.70 + 0.30 * math.cos(math.min(phi - math.pi / 2, math.pi / 2)))
                .clamp(0.35, 1.0)
            : (0.22 + 0.78 * math.cos(phi)).clamp(0.06, 1.0);
        final shade = (1.0 - bright).clamp(0.0, 1.0);
        if (shade > 0.01) {
          canvas.save();
          canvas.clipPath(quad);
          canvas.drawRect(
            fullRect,
            Paint()..color = Colors.black.withValues(alpha: shade * 0.85),
          );
          canvas.restore();
        }
        // light catching the outside of the roll (soft, never a hard line)
        if (!back && phi > 0.15 && phi < 1.4) {
          canvas.save();
          canvas.clipPath(quad);
          canvas.drawRect(
            fullRect,
            Paint()
              ..color = Colors.white
                  .withValues(alpha: 0.055 * (1 - (phi - 0.75).abs() / 0.65)),
          );
          canvas.restore();
        }
      }
    }
    pagePaint.colorFilter = null;
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CurlPainter old) =>
      old.progress != progress ||
      old.current != current ||
      old.next != next ||
      old.forward != forward ||
      old.paperColor != paperColor ||
      old.radiusFactor != radiusFactor ||
      old.tilt != tilt;
}
