import 'package:appmusica/player/local_player.dart';
import 'package:appmusica/player/session/app_audio_handler.dart';
import 'package:appmusica/player/track.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_local_player.dart';

List<Track> tracks() => [
  Track(
    id: 't0',
    uri: 'file:///a.mp3',
    title: 'Primeira',
    artist: 'Banda',
    duration: const Duration(minutes: 3),
  ),
  Track(id: 't1', uri: 'file:///b.mp3', title: 'Segunda'),
  Track(id: 't2', uri: 'file:///c.mp3', title: 'Terceira'),
];

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  late FakeLocalPlayer player;
  late AppAudioHandler handler;

  setUp(() async {
    player = FakeLocalPlayer();
    handler = AppAudioHandler(player);
    await player.setQueue(tracks());
    await settle();
  });

  tearDown(() => handler.dispose());

  test('comandos do sistema chegam ao player', () async {
    await handler.play();
    await handler.pause();
    await handler.seek(const Duration(seconds: 30));
    await handler.skipToNext();
    await handler.skipToPrevious();

    expect(
      player.calls,
      containsAllInOrder(['play', 'pause', 'seek:30', 'next', 'previous']),
    );
  });

  test(
    'faixa do player vira mediaItem com título, artista e duração',
    () async {
      final item = handler.mediaItem.value!;

      expect(item.id, 't0');
      expect(item.title, 'Primeira');
      expect(item.artist, 'Banda');
      expect(item.duration, const Duration(minutes: 3));
    },
  );

  test('troca de faixa no player atualiza o mediaItem e o índice', () async {
    player.moveTo(2);
    await settle();

    expect(handler.mediaItem.value!.id, 't2');
    expect(handler.playbackState.value.queueIndex, 2);
  });

  test('duração descoberta pelo motor completa o mediaItem', () async {
    player.moveTo(1);
    player.fakeDuration = const Duration(seconds: 95);
    player.emitStatus(PlayerStatus.ready);
    await settle();

    expect(handler.mediaItem.value!.duration, const Duration(seconds: 95));
  });

  test('fila do player vira a fila da sessão', () async {
    expect(handler.queue.value.map((m) => m.id), ['t0', 't1', 't2']);
  });

  test('tocando: playing true, ready e botão de pausa', () async {
    player.emitStatus(PlayerStatus.playing);
    await settle();
    final s = handler.playbackState.value;

    expect(s.playing, isTrue);
    expect(s.processingState, AudioProcessingState.ready);
    expect(s.controls, contains(MediaControl.pause));
    expect(s.controls, isNot(contains(MediaControl.play)));
  });

  test('pausado: playing false e botão de tocar', () async {
    player.emitStatus(PlayerStatus.playing);
    player.emitStatus(PlayerStatus.paused);
    await settle();
    final s = handler.playbackState.value;

    expect(s.playing, isFalse);
    expect(s.controls, contains(MediaControl.play));
  });

  test('status do player mapeia para o estado da sessão', () async {
    final expected = {
      PlayerStatus.loading: AudioProcessingState.loading,
      PlayerStatus.ready: AudioProcessingState.ready,
      PlayerStatus.completed: AudioProcessingState.completed,
      PlayerStatus.error: AudioProcessingState.error,
      PlayerStatus.idle: AudioProcessingState.idle,
    };
    for (final e in expected.entries) {
      player.emitStatus(e.key);
      await settle();
      expect(
        handler.playbackState.value.processingState,
        e.value,
        reason: '${e.key}',
      );
    }
  });

  test('posição informada vai junto com o estado', () async {
    player.fakePosition = const Duration(seconds: 42);
    player.emitStatus(PlayerStatus.playing);
    await settle();

    expect(
      handler.playbackState.value.updatePosition,
      const Duration(seconds: 42),
    );
  });

  test('seek pelo sistema aparece como ação disponível', () async {
    expect(
      handler.playbackState.value.systemActions,
      contains(MediaAction.seek),
    );
  });

  test('Android Auto: raiz tem só a pasta Fila', () async {
    final root = await handler.getChildren(AudioService.browsableRootId);

    expect(root.map((m) => m.id), [AppAudioHandler.queueFolderId]);
    expect(root.single.title, 'Fila');
    expect(root.single.playable, isFalse);
  });

  test('Android Auto: pasta Fila lista as faixas tocáveis', () async {
    final items = await handler.getChildren(AppAudioHandler.queueFolderId);

    expect(items.map((m) => m.id), ['t0', 't1', 't2']);
    expect(items.every((m) => m.playable == true), isTrue);
  });

  test('playFromMediaId toca a faixa escolhida', () async {
    await handler.playFromMediaId('t1');

    expect(player.calls, containsAllInOrder(['setQueue:3', 'play']));
    expect(player.currentTrack!.id, 't1');
  });

  test('skipToQueueItem toca a faixa pelo índice', () async {
    await handler.skipToQueueItem(2);

    expect(player.currentTrack!.id, 't2');
    expect(player.calls.last, 'play');
  });

  test('mediaId desconhecido é ignorado sem erro', () async {
    final before = player.calls.length;
    await handler.playFromMediaId('nao-existe');

    expect(player.calls.length, before);
  });

  test('stop pausa o player e encerra a sessão', () async {
    await handler.stop();

    expect(player.calls, contains('pause'));
    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.idle,
    );
  });
}
