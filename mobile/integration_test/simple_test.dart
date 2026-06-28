import 'package:flutter_test/flutter_test.dart';
import 'package:kinetic/main.dart';
import 'package:kinetic/src/rust/frb_generated.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => await RustLib.init());
  testWidgets('App launches successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const KineticApp());
    // Verify the Browser tab is shown by default
    expect(find.textContaining('Kinetic'), findsWidgets);
  });
}
