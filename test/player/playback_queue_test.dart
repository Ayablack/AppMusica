import 'package:appmusica/player/playback_queue.dart';
import 'package:appmusica/player/track.dart';
import 'package:flutter_test/flutter_test.dart';

List<Track> _tracks(int n) => List.generate(
      n,
      (i) => Track(id: 't$i', uri: 'file:///musica$i.mp3', title: 'Faixa $i'),
    );

void main() {
  test('moveNext avança e retorna false no fim', () {
    final queue = PlaybackQueue(_tracks(3), startIndex: 1);

    expect(queue.moveNext(), isTrue);
    expect(queue.index, 2);
    expect(queue.moveNext(), isFalse);
    expect(queue.index, 2);
    expect(queue.current!.id, 't2');
  });

  test('movePrevious volta ao início se passou de 3 s', () {
    final queue = PlaybackQueue(_tracks(3), startIndex: 1);

    expect(queue.movePrevious(position: const Duration(seconds: 4)), isFalse);
    expect(queue.index, 1);
  });

  test('movePrevious vai para a anterior até 3 s', () {
    final queue = PlaybackQueue(_tracks(3), startIndex: 1);

    expect(queue.movePrevious(position: const Duration(seconds: 2)), isTrue);
    expect(queue.index, 0);
  });

  test('movePrevious na primeira faixa não sai da fila', () {
    final queue = PlaybackQueue(_tracks(3));

    expect(queue.movePrevious(position: Duration.zero), isFalse);
    expect(queue.index, 0);
  });

  test('fila vazia tem current nulo', () {
    final queue = PlaybackQueue(const []);

    expect(queue.current, isNull);
    expect(queue.moveNext(), isFalse);
    expect(queue.movePrevious(position: Duration.zero), isFalse);
  });

  test('startIndex fora da fila lança RangeError', () {
    expect(() => PlaybackQueue(_tracks(2), startIndex: 2), throwsRangeError);
  });
}
