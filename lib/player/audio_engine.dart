import 'dart:async';

import 'package:just_audio/just_audio.dart';

enum EngineState { idle, loading, ready, completed }

/// Camada fina sobre o decodificador de áudio. Toca **uma** faixa por vez; a
/// fila, os erros e o status ficam no [LocalPlayer] (testável com um motor
/// falso).
abstract class AudioEngine {
  /// Carrega a faixa; lança se o arquivo não puder ser aberto.
  Future<Duration?> load(String uri);

  /// Retorna logo que o pedido foi feito, sem esperar a faixa acabar.
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> setSpeed(double speed);

  bool get playing;
  Stream<bool> get playingStream;
  Stream<EngineState> get stateStream;

  /// Erros durante a reprodução (decodificação, arquivo removido).
  Stream<Object> get errorStream;
  Duration get position;

  Future<void> dispose();
}

/// Motor real: `just_audio` (ExoPlayer no Android, libmpv no Windows).
class JustAudioEngine implements AudioEngine {
  JustAudioEngine() {
    _eventSub = _player.playbackEventStream.listen(
      (_) {},
      onError: (Object e, StackTrace _) => _errors.add(e),
    );
  }

  final _player = AudioPlayer();
  final _errors = StreamController<Object>.broadcast();
  late final StreamSubscription<PlaybackEvent> _eventSub;

  @override
  Future<Duration?> load(String uri) =>
      _player.setAudioSource(AudioSource.uri(Uri.parse(uri)));

  @override
  Future<void> play() async {
    // O Future do just_audio só completa quando a reprodução para.
    unawaited(_player.play().catchError((Object e) => _errors.add(e)));
  }

  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> stop() => _player.stop();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  bool get playing => _player.playing;
  @override
  Stream<bool> get playingStream => _player.playingStream;
  @override
  Stream<EngineState> get stateStream => _player.processingStateStream.map(
    (s) => switch (s) {
      ProcessingState.idle => EngineState.idle,
      ProcessingState.loading ||
      ProcessingState.buffering => EngineState.loading,
      ProcessingState.ready => EngineState.ready,
      ProcessingState.completed => EngineState.completed,
    },
  );
  @override
  Stream<Object> get errorStream => _errors.stream;
  @override
  Duration get position => _player.position;

  @override
  Future<void> dispose() async {
    await _eventSub.cancel();
    await _errors.close();
    await _player.dispose();
  }
}
