import 'package:attendiqo_connect/features/authentication/presentation/parent_registration_screen.dart';
import 'package:attendiqo_connect/services/firebase_authentication_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _ParentWorkflow implements ParentAccountWorkflowRepository {
  int registrations = 0;

  @override
  Future<void> linkStudent(String studentNumber) async {}

  @override
  Future<void> registerParent({
    required String displayName,
    required String mobileNumber,
    required String email,
    required String password,
  }) async {
    registrations++;
  }
}

void main() {
  testWidgets('parent registration validates and submits the full form', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final workflow = _ParentWorkflow();
    await tester.pumpWidget(
      MaterialApp(
        home: ParentRegistrationScreen(repository: workflow),
      ),
    );

    await tester.tap(find.byKey(const Key('createParentAccountButton')));
    await tester.pump();
    expect(find.text('Full name is required'), findsOneWidget);
    expect(workflow.registrations, 0);

    await tester.enterText(
      find.byKey(const Key('registrationName')),
      'Test Parent',
    );
    await tester.enterText(
      find.byKey(const Key('registrationMobile')),
      '0770000001',
    );
    await tester.enterText(
      find.byKey(const Key('registrationEmail')),
      'new.parent@attendiqo.test',
    );
    await tester.enterText(
      find.byKey(const Key('registrationPassword')),
      'ParentPass1!',
    );
    await tester.enterText(
      find.byKey(const Key('registrationConfirmation')),
      'ParentPass1!',
    );
    await tester.ensureVisible(
      find.byKey(const Key('createParentAccountButton')),
    );
    await tester.tap(find.byKey(const Key('createParentAccountButton')));
    await tester.pumpAndSettle();

    expect(workflow.registrations, 1);
  });
}
