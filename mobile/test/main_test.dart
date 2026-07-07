import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kinetic/main.dart';


void main() {
  testWidgets('KineticApp initializes and builds without crashing', (
    WidgetTester tester,
  ) async {
    // Provide a mocked or real ProviderScope.
    await tester.pumpWidget(const ProviderScope(child: KineticApp()));

    // Verify that MaterialApp is present
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
