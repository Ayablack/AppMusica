import 'package:appmusica/player/just_audio_local_player.dart';
import 'package:appmusica/player/local_player.dart';
import 'package:appmusica/player/track.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_audio_engine.dart';

List<Track> tracks(int n) => List.generate(
  n,
  (i) => Track(id: 't$i', uri: 'file:///m$i.mp3', title: 'Faixa $i'),
);

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  late FakeAudioEngine engine;
  late JustAudioLocalPlayer player;

  setUp(() {
    engine = FakeAudioEngine();
    player = JustAudioLocalPlayer(engine: engine);
  });

  tearDown(() => player.dispose());

  test('setQueue carrega a faixa inicial e fica pronto', () async {
    await player.setQueue(tracks(3), startIndex: 1);
    await settle();

    expect(engine.calls, ['load:file:///m1.mp3']);
    expect(player.currentTrack!.id, 't1');
    expect(player.status, PlayerStatus.ready);
    expect(player.queue, hasLength(3));
  });

  test('play e pause refletem no status', () async {
    await player.setQueue(tracks(2));
    await player.play();
    await settle();
    expect(player.status, PlayerStatus.playing);

    await player.pause();
    await settle();
    expect(player.status, PlayerStatus.paused);
  });

  test('next carrega a próxima e continua tocando se estava tocando', () async {
    await player.setQueue(tracks(3));
    await player.play();
    await player.next();
    await settle();

    expect(player.currentTrack!.id, 't1');
    expect(engine.calls, containsAllInOrder(['load:file:///m1.mp3', 'play']));
    expect(player.status, PlayerStatus.playing);
  });

  test('next pausado carrega a próxima sem tocar', () async {
    await player.setQueue(tracks(3));
    await player.next();
    await settle();

    expect(player.currentTrack!.id, 't1');
    expect(engine.calls.where((c) => c == 'play'), isEmpty);
  });

  test(
    'fim da faixa avança automaticamente; na última fica completed',
    () async {
      await player.setQueue(tracks(2));
      await player.play();

      engine.complete();
      await settle();
      expect(player.currentTrack!.id, 't1');
      expect(player.status, PlayerStatus.playing);

      engine.complete();
      await settle();
      expect(player.currentTrack!.id, 't1');
      expect(player.status, PlayerStatus.completed);
    },
  );

  test('previous depois de 3 s reinicia a faixa atual', () async {
    await player.setQueue(tracks(3), startIndex: 1);
    engine.position = const Duration(seconds: 10);

    await player.previous();

    expect(player.currentTrack!.id, 't1');
    expect(engine.calls.last, 'seek:0');
  });

  test('previous até 3 s volta para a faixa anterior', () async {
    await player.setQueue(tracks(3), startIndex: 1);
    engine.position = const Duration(seconds: 1);

    await player.previous();

    expect(player.currentTrack!.id, 't0');
    expect(engine.calls.last, 'load:file:///m0.mp3');
  });

  test('setSpeed repassa o valor e limita a 0,5–2,0', () async {
    await player.setSpeed(1.02);
    expect(engine.speed, 1.02);
    await player.setSpeed(5);
    expect(engine.speed, 2.0);
    await player.setSpeed(0.1);
    expect(engine.speed, 0.5);
  });

  test(
    'arquivo ilegível vira error, não lança e pula para a próxima',
    () async {
      engine.failing.add('file:///m0.mp3');
      final statuses = <PlayerStatus>[];
      player.statusStream.listen(statuses.add);

      await player.setQueue(tracks(2));
      await settle();

      expect(statuses, contains(PlayerStatus.error));
      expect(player.currentTrack!.id, 't1');
      expect(player.status, PlayerStatus.ready);
    },
  );

  test(
    'erro durante a reprodução pula para a próxima e continua tocando',
    () async {
      await player.setQueue(tracks(2));
      await player.play();

      engine.failWhilePlaying();
      await settle();

      expect(player.currentTrack!.id, 't1');
      expect(player.status, PlayerStatus.playing);
    },
  );

  test(
    'todas as faixas ilegíveis terminam em error sem laço infinito',
    () async {
      engine.failing.addAll(['file:///m0.mp3', 'file:///m1.mp3']);

      await player.setQueue(tracks(2));
      await settle();

      expect(player.status, PlayerStatus.error);
      expect(engine.calls.where((c) => c.startsWith('load')), hasLength(2));
    },
  );

  test('next rápido duas vezes: vale a última faixa pedida', () async {
    await player.setQueue(tracks(4));
    engine.loadDelay = const Duration(milliseconds: 30);

    final a = player.next();
    final b = player.next();
    await Future.wait([a, b]);
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(player.currentTrack!.id, 't2');
    expect(engine.calls.last, 'load:file:///m2.mp3');
  });

  test('currentTrackStream emite a faixa nova ao avançar', () async {
    final emitted = <String?>[];
    player.currentTrackStream.listen((t) => emitted.add(t?.id));

    await player.setQueue(tracks(2));
    await player.next();
    await settle();

    expect(emitted, ['t0', 't1']);
  });

  test('positionStream emite a posição do motor periodicamente', () async {
    await player.setQueue(tracks(1));
    engine.position = const Duration(seconds: 7);

    final p = await player.positionStream.first.timeout(
      const Duration(seconds: 1),
    );

    expect(p, const Duration(seconds: 7));
  });

  test('duration vem do motor ao carregar a faixa', () async {
    await player.setQueue(tracks(1));

    expect(player.duration, const Duration(minutes: 3));
  });

  test('dispose libera o motor', () async {
    await player.dispose();
    expect(engine.calls, contains('dispose'));
    player = JustAudioLocalPlayer(engine: FakeAudioEngine());
  });
}
