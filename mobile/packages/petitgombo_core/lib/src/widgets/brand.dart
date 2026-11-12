import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/spacing.dart';
import '../app/theme.dart';

/// A five-pointed star with softened points, centred in [size].
Path starPath(Size size, {double inset = 0}) {
  final centre = Offset(size.width / 2, size.height / 2);
  final outer = size.shortestSide / 2 - inset;
  final inner = outer * 0.5;
  final path = Path();
  for (var i = 0; i < 10; i++) {
    final radius = i.isEven ? outer : inner;
    final angle = -math.pi / 2 + i * math.pi / 5;
    final point = centre + Offset(math.cos(angle), math.sin(angle)) * radius;
    if (i == 0) {
      path.moveTo(point.dx, point.dy);
    } else {
      path.lineTo(point.dx, point.dy);
    }
  }
  return path..close();
}

/// The petitGombo mark: a tilted white star on a green tile, with an orange spark.
/// The star stands for the trust two people earn from each other.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'petitGombo',
      image: true,
      child: CustomPaint(size: Size.square(size), painter: _BrandPainter()),
    );
  }
}

class _BrandPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    final tile = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(side * 0.28));
    canvas.drawRRect(tile, Paint()..color = AppColors.primary);

    canvas.save();
    canvas.translate(side * 0.47, side * 0.54);
    canvas.rotate(-0.21);
    canvas.translate(-side * 0.5, -side * 0.5);
    final star = starPath(size, inset: side * 0.2);
    final white = Paint()..color = Colors.white;
    canvas.drawPath(star, white);
    // A round stroke of the same colour softens the points.
    canvas.drawPath(
      star,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = side * 0.09
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();

    canvas.drawCircle(
      Offset(side * 0.79, side * 0.22),
      side * 0.085,
      Paint()..color = AppColors.spark,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// One star, filled by [fill] from 0 to 1.
class _StarPainter extends CustomPainter {
  const _StarPainter(this.fill);

  final double fill;

  @override
  void paint(Canvas canvas, Size size) {
    final star = starPath(size, inset: size.shortestSide * 0.06);
    canvas.drawPath(star, Paint()..color = AppColors.border);
    if (fill <= 0) return;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width * fill, size.height));
    canvas.drawPath(star, Paint()..color = AppColors.spark);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _StarPainter oldDelegate) => oldDelegate.fill != fill;
}

/// Five stars for an average rating, with the figure and the number of reviews
/// in words, so the rating never depends on colour alone. With no review yet it
/// says so instead of showing an empty score.
class StarRating extends StatelessWidget {
  const StarRating({super.key, required this.average, required this.count, this.size = 18});

  /// Between 0 and 5; ignored while [count] is 0.
  final double average;
  final int count;
  final double size;

  static String label(double average, int count) {
    if (count == 0) return "Pas encore d'avis";
    final figure = average.toStringAsFixed(1).replaceAll('.', ',');
    return '$figure sur 5 · $count avis';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = label(average, count);
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: Gaps.sm,
        runSpacing: Gaps.xs,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 5; i++)
                CustomPaint(
                  size: Size.square(size),
                  painter: _StarPainter(count == 0 ? 0 : (average - i).clamp(0, 1).toDouble()),
                ),
            ],
          ),
          Text(text, style: theme.textTheme.bodyMedium!.copyWith(color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

/// One review: who (first name only), the stars, when, and the words.
class ReviewCard extends StatelessWidget {
  const ReviewCard({
    super.key,
    required this.author,
    required this.stars,
    required this.when,
    required this.text,
  });

  final String author;
  final int stars;
  final String when;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: Gaps.md),
      padding: const EdgeInsets.all(Gaps.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.primarySoft,
                child: Text(
                  author.isEmpty ? '?' : author.characters.first.toUpperCase(),
                  style: theme.textTheme.bodyLarge!.copyWith(color: AppColors.primary),
                ),
              ),
              const SizedBox(width: Gaps.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(author, style: theme.textTheme.bodyLarge),
                    Text(when, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Gaps.sm),
          Semantics(
            label: '$stars sur 5',
            excludeSemantics: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 5; i++)
                  CustomPaint(
                    size: const Size.square(16),
                    painter: _StarPainter(i < stars ? 1 : 0),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Gaps.sm),
          Text(text, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
