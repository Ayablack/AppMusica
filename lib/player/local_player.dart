import 'track.dart';

enum PlayerStatus { idle, loading, ready, playing, paused, completed, error }

/// Player local, independente da Jam.
///
/// Implementações não podem depender de nada em `lib/jam/`.
abstract class LocalPlayer {
  Future<void> setQueue(List<Track> tracks, {int startIndex = 0});
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> next();
  Future<void> previous();
  Future<void> setSpeed(double speed);

  Stream<Duration> get positionStream;
  Stream<PlayerStatus> get statusStream;
  Stream<Track?> get currentTrackStream;

  Duration get position;

  /// Duração da faixa atual, conhecida depois de carregada.
  Duration? get duration;
  PlayerStatus get status;
  Track? get currentTrack;
  List<Track> get queue;

  Future<void> dispose();
}
