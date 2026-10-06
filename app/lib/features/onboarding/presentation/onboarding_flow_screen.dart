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
  static const _reviewPage = 8;
  static const _locationPage = 3;

  int _currentPage = 0;

  /// True while the user is fixing one answer from the review screen. Continue
  /// and Back then return straight to the review instead of walking the steps
  /// in between again.
  bool _editingFromReview = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    // Steps with a text field (height/weight on step 3) leave the keyboard
    // focused when "Continue" is tapped — without this, it stays open and
    // covers the next step's content even when that step has no text field
    // at all (e.g. step 4's location picker cards get pushed up behind the
    // still-open numeric keypad).
    FocusScope.of(context).unfocus();
    _pageController.animateToPage(
      page.clamp(0, _lastPage),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  /// From the review's pencil: jump to [page] and remember to come back.
  void _editFromReview(int page) {
    _editingFromReview = true;
    _goTo(page);
  }

  /// The page after [page] when Continue is tapped.
  int _next(int page) {
    if (!_editingFromReview) return page + 1;
    // Changing where they train resets the equipment preset, which is the very
    // next screen — let them see it once before returning.
    if (page == _locationPage) return page + 1;
    _editingFromReview = false;
    return _reviewPage;
  }

  /// The page before [page] when Back is tapped.
  int _previous(int page) {
    if (!_editingFromReview) return page - 1;
    _editingFromReview = false;
    return _reviewPage;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _currentPage == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _currentPage > 0) _goTo(_previous(_currentPage));
      },
      child: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        onPageChanged: (page) {
          // Belt and braces with `_goTo`: whatever moved the page (Continue,
          // Back, the system back gesture), the next step must not inherit an
          // open keyboard from the one before it.
          FocusManager.instance.primaryFocus?.unfocus();
          setState(() => _currentPage = page);
        },
        children: [
          Step1Goal(onContinue: () => _goTo(_next(0))),
          Step2Experience(onBack: () => _goTo(_previous(1)), onContinue: () => _goTo(_next(1))),
          Step3Numbers(onBack: () => _goTo(_previous(2)), onContinue: () => _goTo(_next(2))),
          Step4Location(onBack: () => _goTo(_previous(3)), onContinue: () => _goTo(_next(3))),
          Step4Equipment(onBack: () => _goTo(_previous(4)), onContinue: () => _goTo(_next(4))),
          Step5Frequency(onBack: () => _goTo(_previous(5)), onContinue: () => _goTo(_next(5))),
          Step6Split(onBack: () => _goTo(_previous(6)), onContinue: () => _goTo(_next(6))),
          Step7Injuries(onBack: () => _goTo(_previous(7)), onContinue: () => _goTo(_next(7))),
          Step8Review(onBack: () => _goTo(7), onEditStep: _editFromReview, onBuildPlan: () => _goTo(9)),
          Step9Building(onCancel: () => _goTo(8)),
        ],
      ),
    );
  }
}
