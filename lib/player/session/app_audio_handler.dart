import 'dart:async';

import 'package:audio_service/audio_service.dart';

import '../local_player.dart';
import '../track.dart';

/// Ponte entre a sessão de mídia do sistema (`audio_service`: notificação,
/// tela bloqueada, botões do fone, Android Auto) e o [LocalPlayer].
///
/// Comandos do sistema viram chamadas ao player; o estado publicado vem
/// sempre do player, para o sistema nunca mostrar algo diferente do app.
class AppAudioHandler extends BaseAudioHandler with QueueHandler {
  AppAudioHandler(this._player) {
    _subs = [
      _player.statusStream.listen((_) => _publish()),
      _player.currentTrackStream.listen((_) => _publish()),
    ];
    _publish();
  }

  /// Pasta única do Android Auto, abaixo da raiz.
  static const queueFolderId = 'queue';

  final LocalPlayer _player;
  late final List<StreamSubscription<Object?>> _subs;

  static MediaItem _item(Track t, {Duration? duration}) => MediaItem(
    id: t.id,
    title: t.title,
    artist: t.artist,
    duration: duration ?? t.duration,
    playable: true,
  );

  void _publish() {
    final tracks = _player.queue;
    final current = _player.currentTrack;
    if (!_sameQueue(tracks)) queue.add([for (final t in tracks) _item(t)]);
    if (current != null) {
      final item = _item(current, duration: _player.duration);
      final old = mediaItem.value;
      final changed =
          old == null ||
          old.id != item.id ||
          old.title != item.title ||
          old.artist != item.artist ||
          old.duration != item.duration;
      if (changed) mediaItem.add(item);
    }
    final playing = _player.status == PlayerStatus.playing;
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: switch (_player.status) {
          PlayerStatus.idle => AudioProcessingState.idle,
          PlayerStatus.loading => AudioProcessingState.loading,
          PlayerStatus.ready ||
          PlayerStatus.playing ||
          PlayerStatus.paused => AudioProcessingState.ready,
          PlayerStatus.completed => AudioProcessingState.completed,
          PlayerStatus.error => AudioProcessingState.error,
        },
        playing: playing,
        updatePosition: _player.position,
        queueIndex: current == null ? null : tracks.indexOf(current),
      ),
    );
  }

  bool _sameQueue(List<Track> tracks) {
    final q = queue.value;
    if (q.length != tracks.length) return false;
    for (var i = 0; i < q.length; i++) {
      if (q[i].id != tracks[i].id) return false;
    }
    return true;
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    _publish();
  }

  @override
  Future<void> skipToNext() => _player.next();

  @override
  Future<void> skipToPrevious() => _player.previous();

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> skipToQueueItem(int index) async {
    final tracks = _player.queue;
    if (index < 0 || index >= tracks.length) return;
    await _player.setQueue(tracks, startIndex: index);
    await _player.play();
  }

  @override
  Future<void> playFromMediaId(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) async {
    final index = _player.queue.indexWhere((t) => t.id == mediaId);
    if (index >= 0) await skipToQueueItem(index);
  }

  @override
  Future<List<MediaItem>> getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) async => switch (parentMediaId) {
    AudioService.browsableRootId => const [
      MediaItem(id: queueFolderId, title: 'Fila', playable: false),
    ],
    queueFolderId => [for (final t in _player.queue) _item(t)],
    _ => const [],
  };

  /// "Parar" vindo do sistema (ex.: descartar a notificação): pausa a música
  /// e libera o serviço em primeiro plano.
  @override
  Future<void> stop() async {
    await _player.pause();
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
    await super.stop();
  }

  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
  }
}
