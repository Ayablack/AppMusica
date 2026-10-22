import 'dart:async';

import 'audio_engine.dart';
import 'local_player.dart';
import 'playback_queue.dart';
import 'track.dart';

/// [LocalPlayer] sobre um [AudioEngine]: fila, avanço automático, erros e
/// status. Não conhece a Jam.
class JustAudioLocalPlayer implements LocalPlayer {
  JustAudioLocalPlayer({AudioEngine? engine})
    : _engine = engine ?? JustAudioEngine() {
    _subs = [
      _engine.stateStream.listen(_onEngineState),
      _engine.playingStream.listen((playing) {
        if (playing) _started = true;
        _derive();
      }),
      _engine.errorStream.listen((_) => _onPlaybackError()),
    ];
  }

  static const minSpeed = 0.5;
  static const maxSpeed = 2.0;
  static const _positionInterval = Duration(milliseconds: 50);

  final AudioEngine _engine;
  late final List<StreamSubscription<Object?>> _subs;
  final _status = StreamController<PlayerStatus>.broadcast();
  final _track = StreamController<Track?>.broadcast();

  PlaybackQueue _queue = PlaybackQueue(const []);
  EngineState _engineState = EngineState.idle;
  PlayerStatus _current = PlayerStatus.idle;
  Track? _emittedTrack;
  Duration? _duration;

  /// Cada carga recebe um número; uma carga antiga que termina depois de
  /// outra mais nova é ignorada (vale o último pedido).
  int _generation = 0;
  bool _started = false;
  bool _failed = false;
  bool _ended = false;

  @override
  Stream<PlayerStatus> get statusStream => _status.stream;
  @override
  Stream<Track?> get currentTrackStream => _track.stream;
  @override
  Stream<Duration> get positionStream =>
      Stream.periodic(_positionInterval, (_) => _engine.position);

  @override
  PlayerStatus get status => _current;
  @override
  Track? get currentTrack => _queue.current;
  @override
  List<Track> get queue => _queue.tracks;
  @override
  Duration get position => _engine.position;
  @override
  Duration? get duration => _duration;

  @override
  Future<void> setQueue(List<Track> tracks, {int startIndex = 0}) async {
    _queue = PlaybackQueue(tracks, startIndex: startIndex);
    await _loadCurrent(autoplay: false);
  }

  @override
  Future<void> play() async {
    if (_ended) {
      _ended = false;
      await _engine.seek(Duration.zero);
    }
    await _engine.play();
  }

  @override
  Future<void> pause() => _engine.pause();

  @override
  Future<void> seek(Duration position) => _engine.seek(position);

  @override
  Future<void> next() async {
    final wasPlaying = _engine.playing;
    if (_queue.moveNext()) await _loadCurrent(autoplay: wasPlaying);
  }

  @override
  Future<void> previous() async {
    final wasPlaying = _engine.playing;
    if (_queue.movePrevious(position: _engine.position)) {
      await _loadCurrent(autoplay: wasPlaying);
    } else {
      await _engine.seek(Duration.zero);
    }
  }

  @override
  Future<void> setSpeed(double speed) =>
      _engine.setSpeed(speed.clamp(minSpeed, maxSpeed).toDouble());

  /// Carrega a faixa atual; se falhar, marca erro e tenta as seguintes.
  Future<void> _loadCurrent({required bool autoplay}) async {
    final generation = ++_generation;
    while (true) {
      final track = _queue.current;
      if (track == null) {
        _derive();
        return;
      }
      _emitTrack(track);
      _started = false;
      _ended = false;
      _duration = track.duration;
      try {
        final loaded = await _engine.load(track.uri);
        if (generation == _generation) _duration = loaded ?? track.duration;
      } on Object {
        if (generation != _generation) return;
        _failed = true;
        _derive();
        if (_queue.moveNext()) continue;
        return;
      }
      if (generation != _generation) return;
      _failed = false;
      if (autoplay) await _engine.play();
      _derive();
      return;
    }
  }

  void _onEngineState(EngineState s) {
    _engineState = s;
    if (s == EngineState.completed && !_failed) {
      if (_queue.moveNext()) {
        _loadCurrent(autoplay: true);
        return;
      }
      _ended = true;
    }
    _derive();
  }

  void _onPlaybackError() {
    _failed = true;
    _derive();
    if (_queue.moveNext()) _loadCurrent(autoplay: true);
  }

  void _emitTrack(Track t) {
    if (identical(t, _emittedTrack)) return;
    _emittedTrack = t;
    _track.add(t);
  }

  void _derive() {
    final next = _failed
        ? PlayerStatus.error
        : _ended
        ? PlayerStatus.completed
        : switch (_engineState) {
            EngineState.loading => PlayerStatus.loading,
            EngineState.ready || EngineState.completed =>
              _engine.playing
                  ? PlayerStatus.playing
                  : (_started ? PlayerStatus.paused : PlayerStatus.ready),
            EngineState.idle =>
              _queue.current == null ? PlayerStatus.idle : PlayerStatus.loading,
          };
    if (next == _current) return;
    _current = next;
    _status.add(next);
  }

  @override
  Future<void> dispose() async {
    _generation++;
    for (final s in _subs) {
      await s.cancel();
    }
    await _engine.dispose();
    await _status.close();
    await _track.close();
  }
}
