import 'dart:async';

import 'package:appmusica/player/local_player.dart';
import 'package:appmusica/player/track.dart';

/// Player falso para testes de telas e da sessão de mídia.
class FakeLocalPlayer implements LocalPlayer {
  final calls = <String>[];
  final _status = StreamController<PlayerStatus>.broadcast();
  final _track = StreamController<Track?>.broadcast();
  List<Track> _queue = const [];
  int _index = 0;
  Duration fakePosition = Duration.zero;
  Duration? fakeDuration;

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

  /// Muda a faixa atual e avisa quem escuta, como o motor faria.
  void moveTo(int index) {
    _index = index;
    _track.add(currentTrack);
  }

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
  Duration get position => fakePosition;
  @override
  Duration? get duration => fakeDuration ?? currentTrack?.duration;
  @override
  Track? get currentTrack => _queue.isEmpty ? null : _queue[_index];
  @override
  List<Track> get queue => _queue;
  @override
  Future<void> dispose() async => calls.add('dispose');
}
