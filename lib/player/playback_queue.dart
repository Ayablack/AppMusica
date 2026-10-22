import 'track.dart';

/// Lógica pura de navegação na fila, sem reprodução.
class PlaybackQueue {
  PlaybackQueue(List<Track> tracks, {int startIndex = 0})
    : tracks = List.unmodifiable(tracks),
      _index = startIndex {
    if (tracks.isNotEmpty) RangeError.checkValidIndex(startIndex, tracks);
  }

  /// Acima disso, "anterior" volta ao início da faixa atual.
  static const restartThreshold = Duration(seconds: 3);

  final List<Track> tracks;
  int _index;

  int get index => _index;
  Track? get current => tracks.isEmpty ? null : tracks[_index];

  bool moveNext() {
    if (_index + 1 >= tracks.length) return false;
    _index++;
    return true;
  }

  /// Retorna `true` se mudou de faixa; `false` se deve reiniciar a atual.
  bool movePrevious({required Duration position}) {
    if (position > restartThreshold || _index == 0) return false;
    _index--;
    return true;
  }
}
