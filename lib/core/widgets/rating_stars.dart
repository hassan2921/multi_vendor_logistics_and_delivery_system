import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A read-only 5-star rating row supporting half stars.
class RatingStars extends StatelessWidget {
  const RatingStars(this.rating, {super.key, this.size = 16, this.color = AppColors.amber});

  final double rating;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 5; i++)
          Icon(
            rating >= i + 1
                ? Icons.star_rounded
                : rating >= i + 0.5
                    ? Icons.star_half_rounded
                    : Icons.star_outline_rounded,
            size: size,
            color: color,
          ),
      ],
    );
  }
}
