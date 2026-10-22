import 'package:appmusica/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tela inicial abre o laboratório de conexão', (tester) async {
    await tester.pumpWidget(const AppMusica());

    await tester.tap(find.text('Laboratório: conexão'));
    await tester.pumpAndSettle();

    expect(find.text('Ser anfitrião'), findsOneWidget);
    expect(find.text('Entrar'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Código da sala'), findsOneWidget);
  });
}
