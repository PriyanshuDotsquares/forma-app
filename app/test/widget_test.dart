import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:forma/features/auth/presentation/auth_controller.dart';
import 'package:forma/features/auth/domain/user.dart';
import 'package:forma/main.dart';

class _SignedOutAuthController extends AuthController {
  @override
  Future<User?> build() async => null;
}

void main() {
  testWidgets('Signed-out app renders the login screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authControllerProvider.overrideWith(_SignedOutAuthController.new)],
        child: const FormaApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
  });
}
