import 'package:flutter_test/flutter_test.dart';

import 'package:appmusica/main.dart';

void main() {
  testWidgets('tela inicial identifica a Fase 0 como experimental',
      (WidgetTester tester) async {
    await tester.pumpWidget(const AppMusica());

    expect(find.text('AppMusica'), findsOneWidget);
    expect(find.text('Fase 0: validação técnica'), findsOneWidget);
    expect(find.textContaining('Protótipo experimental'), findsOneWidget);
  });
}
