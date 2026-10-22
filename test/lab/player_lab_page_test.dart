import 'dart:async';

import 'package:appmusica/lab/player_lab_page.dart';
import 'package:appmusica/player/local_player.dart';
import 'package:appmusica/player/track.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeLocalPlayer implements LocalPlayer {
  final calls = <String>[];
  final _status = StreamController<PlayerStatus>.broadcast();
  final _track = StreamController<Track?>.broadcast();
  List<Track> _queue = const [];
  int _index = 0;

  @override
  PlayerStatus status = PlayerStatus.idle;

  void emitStatus(PlayerStatus s) {
    status = s;
    _status.add(s);
  }

  @override
  Future<void> setQueue(List<Track> tracks, {int startIndex = 0}) async {
    calls.add('setQueue:${tracks.length}');
    _queue = tracks;
    _index = startIndex;
    _track.add(currentTrack);
  }

  @override
  Future<void> play() async => calls.add('play');
  @override
  Future<void> pause() async => calls.add('pause');
  @override
  Future<void> next() async => calls.add('next');
  @override
  Future<void> previous() async => calls.add('previous');
  @override
  Future<void> seek(Duration p) async => calls.add('seek:${p.inSeconds}');
  @override
  Future<void> setSpeed(double s) async => calls.add('speed:$s');

  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<PlayerStatus> get statusStream => _status.stream;
  @override
  Stream<Track?> get currentTrackStream => _track.stream;
  @override
  Duration get position => Duration.zero;
  @override
  Track? get currentTrack => _queue.isEmpty ? null : _queue[_index];
  @override
  List<Track> get queue => _queue;
  @override
  Future<void> dispose() async => calls.add('dispose');
}

void main() {
  late FakeLocalPlayer player;

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: PlayerLabPage(
        player: player,
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
