import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../app_typography.dart';

/// The "FORMA" logo wordmark — a serif display face distinct from the rest
/// of the type scale, as seen on the splash screen and every top app bar.
class FormaWordmark extends StatelessWidget {
  const FormaWordmark({super.key, this.size = 24, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text('FORMA', style: AppTypography.wordmark(size: size, color: color ?? AppColors.textPrimary));
  }
}
