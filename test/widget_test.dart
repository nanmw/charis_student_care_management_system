// Basic Flutter widget test for Charis Student Care app.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:charis_student_care/app.dart';

void main() {
  testWidgets('App shows login screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: CharisStudentCareApp()),
    );
    expect(find.text('Charis Student Care'), findsOneWidget);
    expect(find.text('Sign in with Microsoft'), findsOneWidget);
  });
}
