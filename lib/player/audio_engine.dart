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

  /// Prazo máximo para abrir um arquivo local.
  static const loadTimeout = Duration(seconds: 10);

  /// O `just_audio_media_kit` 2.1.0 espera um evento de duração para
  /// concluir o `load`; quando o libmpv recusa o arquivo, esse evento nunca
  /// vem e o `load` não termina. Por isso a carga também falha se o estado
  /// cair para `idle` depois de `loading`, se chegar um erro, ou no prazo.
  @override
  Future<Duration?> load(String uri) async {
    final failed = Completer<Duration?>();
    void fail(Object reason) {
      if (!failed.isCompleted) failed.completeError(reason);
    }

    var sawLoading = false;
    final stateSub = _player.processingStateStream.listen((s) {
      if (s == ProcessingState.loading) sawLoading = true;
      if (s == ProcessingState.idle && sawLoading) {
        fail(StateError('o decodificador recusou o arquivo'));
      }
    });
    final errorSub = _errors.stream.listen(fail);
    try {
      return await Future.any([
        _player.setAudioSource(AudioSource.uri(Uri.parse(uri))),
        failed.future,
      ]).timeout(loadTimeout);
    } finally {
      await stateSub.cancel();
      await errorSub.cancel();
    }
  }

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
