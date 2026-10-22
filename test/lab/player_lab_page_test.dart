import 'package:appmusica/lab/player_lab_page.dart';
import 'package:appmusica/player/local_player.dart';
import 'package:appmusica/player/track.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../player/fake_local_player.dart';

void main() {
  late FakeLocalPlayer player;

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: PlayerLabPage(
        player: player,
        loadTestTracks: () async => [
          Track(id: 'x', uri: 'file:///x.mp3', title: 'Teste X'),
        ],
        pickTracks: () async => [
          Track(id: 'a', uri: 'file:///a.mp3', title: 'Primeira'),
          Track(id: 'b', uri: 'file:///b.mp3', title: 'Segunda'),
        ],
      ),
    ),
  );

  setUp(() => player = FakeLocalPlayer());

  testWidgets('escolher músicas monta a fila e mostra a faixa atual', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.text('Escolher músicas'));
    await tester.pumpAndSettle();

    expect(player.calls, contains('setQueue:2'));
    expect(find.text('Primeira'), findsWidgets);
  });

  testWidgets('carregar arquivos de teste monta a fila', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Carregar arquivos de teste'));
    await tester.pumpAndSettle();

    expect(player.calls, contains('setQueue:1'));
    expect(find.text('Teste X'), findsWidgets);
  });

  testWidgets('botões de transporte chamam o player', (tester) async {
    await pump(tester);

    await tester.tap(find.byTooltip('Tocar'));
    await tester.tap(find.byTooltip('Próxima'));
    await tester.tap(find.byTooltip('Anterior'));
    await tester.pump();

    expect(player.calls, containsAllInOrder(['play', 'next', 'previous']));
  });

  testWidgets('tocando, o botão principal vira Pausar', (tester) async {
    await pump(tester);

    player.emitStatus(PlayerStatus.playing);
    await tester.pump();
    await tester.tap(find.byTooltip('Pausar'));
    await tester.pump();

    expect(player.calls, contains('pause'));
    expect(find.text('status: playing'), findsOneWidget);
  });

  testWidgets('velocidade 1,02× e seek por segundos', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Velocidade 1,02×'));
    await tester.enterText(find.byType(TextField), '42');
    await tester.tap(find.text('Ir'));
    await tester.pump();

    expect(player.calls, containsAll(['speed:1.02', 'seek:42']));
  });

  testWidgets('ao sair da tela o player não é descartado', (tester) async {
    await pump(tester);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

    expect(player.calls, isNot(contains('dispose')));
  });
}
