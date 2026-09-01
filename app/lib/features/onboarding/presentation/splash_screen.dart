import 'package:flutter/material.dart';

import '../../../core/design_system/design_system.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.surfaceLowest,
      body: Center(child: FormaWordmark(size: 40)),
    );
  }
}
