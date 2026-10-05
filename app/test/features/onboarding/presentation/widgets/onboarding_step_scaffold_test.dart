import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forma/features/onboarding/presentation/widgets/onboarding_step_scaffold.dart';

Widget _step({bool scrollable = true, VoidCallback? onContinue}) => MaterialApp(
  home: OnboardingStepScaffold(
    stepNumber: 3,
    totalSteps: 9,
    title: 'Numbers',
    scrollable: scrollable,
    footer: FilledButton(onPressed: onContinue ?? () {}, child: const Text('CONTINUE')),
    child: Column(
      children: [
        const TextField(key: Key('height')),
        // Tall enough that the body scrolls on a test-sized screen.
        const SizedBox(height: 1200),
      ],
    ),
  ),
);

bool _keyboardOpen(WidgetTester tester) => FocusManager.instance.primaryFocus?.context != null && tester.testTextInput.isVisible;

void main() {
  testWidgets('tapping empty space closes the keyboard', (tester) async {
    await tester.pumpWidget(_step());
    await tester.tap(find.byKey(const Key('height')));
    await tester.pump();
    expect(_keyboardOpen(tester), isTrue, reason: 'focusing the field opens the keyboard');

    // The title sits in plain, non-interactive space.
    await tester.tap(find.text('Numbers'));
    await tester.pump();
    expect(_keyboardOpen(tester), isFalse);
  });

  testWidgets('dragging the screen closes the keyboard', (tester) async {
    await tester.pumpWidget(_step());
    await tester.tap(find.byKey(const Key('height')));
    await tester.pump();
    expect(_keyboardOpen(tester), isTrue);

    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -150));
    await tester.pump();
    expect(_keyboardOpen(tester), isFalse);
  });

  testWidgets('tapping a button still works while the keyboard is open', (tester) async {
    var continued = 0;
    await tester.pumpWidget(_step(onContinue: () => continued++));
    await tester.tap(find.byKey(const Key('height')));
    await tester.pump();

    await tester.tap(find.text('CONTINUE'));
    await tester.pump();
    expect(continued, 1, reason: 'the dismiss-on-tap handler must not swallow taps meant for controls');
  });

  testWidgets('a non-scrollable step also closes the keyboard on tap', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingStepScaffold(
          stepNumber: 7,
          totalSteps: 9,
          title: 'Injuries',
          scrollable: false,
          child: const TextField(key: Key('notes')),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('notes')));
    await tester.pump();
    expect(_keyboardOpen(tester), isTrue);

    await tester.tap(find.text('Injuries'));
    await tester.pump();
    expect(_keyboardOpen(tester), isFalse);
  });
}
