import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models.dart';

const _coverPalettes = <List<Color>>[
  [Color(0xFF2F4858), Color(0xFF1B2C36)],
  [Color(0xFF7A4E3A), Color(0xFF4A2C20)],
  [Color(0xFF3E5C50), Color(0xFF22352D)],
  [Color(0xFF5A4B6E), Color(0xFF32273F)],
  [Color(0xFF8A4340), Color(0xFF55211F)],
  [Color(0xFF2C4A6E), Color(0xFF182B41)],
  [Color(0xFF6B5A2E), Color(0xFF3F3418)],
  [Color(0xFF3C3F4A), Color(0xFF21232A)],
];

class BookCover extends StatelessWidget {
  const BookCover({
    super.key,
    required this.book,
    this.imagePath,
    this.radius = 4,
    this.width,
  });

  final BookMeta book;
  final String? imagePath;
  final double radius;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final content = AspectRatio(
      aspectRatio: 2 / 3,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1F000000),
              blurRadius: 5,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: imagePath != null
              ? Image.file(
                  File(imagePath!),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _generated(context),
                )
              : _generated(context),
        ),
      ),
    );
    return width == null ? content : SizedBox(width: width, child: content);
  }

  Widget _generated(BuildContext context) {
    final palette =
        _coverPalettes[book.title.hashCode.abs() % _coverPalettes.length];
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth.isFinite ? box.maxWidth : 160;
      final titleSize = math.max(13.0, w * 0.115);
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: palette,
          ),
        ),
        child: Stack(
          children: [
            // spine
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: math.max(3, w * 0.035),
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0x33FFFFFF), Color(0x11000000)],
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(w * 0.14, w * 0.12, w * 0.1, w * 0.1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: const Color(0xFFF3F1EA),
                      fontSize: titleSize,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Songti SC',
                      fontFamilyFallback: const ['Noto Serif CJK SC', 'serif'],
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: w * 0.24,
                    height: 1,
                    color: const Color(0x66FFFFFF),
                  ),
                  if (book.author.isNotEmpty) ...[
                    SizedBox(height: w * 0.05),
                    Text(
                      book.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: const Color(0xCCFFFFFF),
                        fontSize: titleSize * 0.62,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    });
  }
}

/// Thin reading progress indicator used under covers.
class ProgressLine extends StatelessWidget {
  const ProgressLine({super.key, required this.value, this.width = 44});
  final double value;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 3,
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: value.clamp(0.0, 1.0),
                minHeight: 3,
                backgroundColor: CupertinoColors.systemGrey4
                    .resolveFrom(context)
                    .withOpacity(0.45),
                valueColor: const AlwaysStoppedAnimation(Color(0xFFFA5C2E)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String formatProgress(double v) => '${(v * 100).round()}%';
