import 'package:flutter/material.dart';

import 'steps/step1_goal.dart';
import 'steps/step2_experience.dart';
import 'steps/step3_numbers.dart';
import 'steps/step4_equipment.dart';
import 'steps/step4_location.dart';
import 'steps/step5_frequency.dart';
import 'steps/step6_split.dart';
import 'steps/step7_injuries.dart';
import 'steps/step8_review.dart';
import 'steps/step9_building.dart';

/// The 9-step onboarding quiz. Ten pages in total — "Where do you train?"
/// and "What can you train with?" are two separate screens that both read
/// as "STEP 4 OF 9" in the progress header, since picking a gym location
/// just sets the starting preset for the equipment picker right after it.
///
/// Navigation is button-driven (Continue / back arrow / review pencils)
/// rather than swipe, so the PageView itself just follows a controller;
/// each step widget owns its own validity and its own "STEP N OF 9" chrome.
class OnboardingFlowScreen extends StatefulWidget {
  const OnboardingFlowScreen({super.key});

  @override
  State<OnboardingFlowScreen> createState() => _OnboardingFlowScreenState();
}

class _OnboardingFlowScreenState extends State<OnboardingFlowScreen> {
  static const _lastPage = 9;

  final _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    _pageController.animateToPage(
      page.clamp(0, _lastPage),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _currentPage == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _currentPage > 0) _goTo(_currentPage - 1);
      },
      child: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        onPageChanged: (page) => setState(() => _currentPage = page),
        children: [
          Step1Goal(onContinue: () => _goTo(1)),
          Step2Experience(onBack: () => _goTo(0), onContinue: () => _goTo(2)),
          Step3Numbers(onBack: () => _goTo(1), onContinue: () => _goTo(3)),
          Step4Location(onBack: () => _goTo(2), onContinue: () => _goTo(4)),
          Step4Equipment(onBack: () => _goTo(3), onContinue: () => _goTo(5)),
          Step5Frequency(onBack: () => _goTo(4), onContinue: () => _goTo(6)),
          Step6Split(onBack: () => _goTo(5), onContinue: () => _goTo(7)),
          Step7Injuries(onBack: () => _goTo(6), onContinue: () => _goTo(8)),
          Step8Review(onBack: () => _goTo(7), onEditStep: _goTo, onBuildPlan: () => _goTo(9)),
          Step9Building(onCancel: () => _goTo(8)),
        ],
      ),
    );
  }
}
