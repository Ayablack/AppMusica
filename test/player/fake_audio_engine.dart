import 'dart:async';

import 'package:appmusica/player/audio_engine.dart';

/// Motor falso: registra chamadas e deixa o teste controlar estado e erros.
class FakeAudioEngine implements AudioEngine {
  final calls = <String>[];

  /// URIs que falham ao carregar.
  final failing = <String>{};

  /// Atraso artificial em `load`, para testar chamadas concorrentes.
  Duration loadDelay = Duration.zero;

  final _state = StreamController<EngineState>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final _errors = StreamController<Object>.broadcast();
  bool _isPlaying = false;
  double speed = 1.0;

  @override
  Duration position = Duration.zero;

  @override
  bool get playing => _isPlaying;
  @override
  Stream<bool> get playingStream => _playing.stream;
  @override
  Stream<EngineState> get stateStream => _state.stream;
  @override
  Stream<Object> get errorStream => _errors.stream;

  @override
  Future<Duration?> load(String uri) async {
    calls.add('load:$uri');
    _state.add(EngineState.loading);
    if (loadDelay > Duration.zero) await Future<void>.delayed(loadDelay);
    if (failing.contains(uri)) throw StateError('arquivo ilegível');
    position = Duration.zero;
    _state.add(EngineState.ready);
    return const Duration(minutes: 3);
  }

  @override
  Future<void> play() async {
    calls.add('play');
    _setPlaying(true);
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    _setPlaying(false);
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    _setPlaying(false);
    _state.add(EngineState.idle);
  }

  @override
  Future<void> seek(Duration p) async {
    calls.add('seek:${p.inMilliseconds}');
    position = p;
  }

  @override
  Future<void> setSpeed(double s) async {
    calls.add('speed:$s');
    speed = s;
  }

  void _setPlaying(bool v) {
    _isPlaying = v;
    _playing.add(v);
  }

  /// Simula o fim da faixa atual.
  void complete() {
    _setPlaying(false);
    _state.add(EngineState.completed);
  }

  /// Simula erro de decodificação durante a reprodução.
  void failWhilePlaying() => _errors.add(StateError('erro de decodificação'));

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    await _state.close();
    await _playing.close();
    await _errors.close();
  }
}
