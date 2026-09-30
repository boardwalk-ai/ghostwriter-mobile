import 'package:flutter_test/flutter_test.dart';
import 'package:ghostwriter/main.dart';
import 'package:ghostwriter/ghostwriter_page.dart';

void main() {
  testWidgets('app boots into GhostWriter', (tester) async {
    await tester.pumpWidget(const GhostWriterApp());
    expect(find.byType(GhostWriterPage), findsOneWidget);
  });
}
