import 'package:appmusica/jam/signaling/signal_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SignalMessage ida e volta JSON preserva todos os campos', () {
    final m = SignalMessage(
      type: SignalType.candidate,
      from: 'g1',
      to: 'host',
      payload: {'candidate': 'x', 'sdpMLineIndex': 0},
    );

    final back = SignalMessage.fromJson(m.toJson());

    expect(back.type, SignalType.candidate);
    expect(back.from, 'g1');
    expect(back.to, 'host');
    expect(back.payload, {'candidate': 'x', 'sdpMLineIndex': 0});
  });

  test('to nulo e payload vazio sobrevivem à ida e volta', () {
    final back = SignalMessage.fromJson(
      SignalMessage(type: SignalType.hello, from: '').toJson(),
    );

    expect(back.to, isNull);
    expect(back.payload, isEmpty);
  });

  test('tipo desconhecido gera FormatException', () {
    expect(
      () => SignalMessage.fromJson({'type': 'xpto', 'from': 'a'}),
      throwsFormatException,
    );
  });

  test('campos com tipo errado geram FormatException', () {
    expect(
      () => SignalMessage.fromJson({'type': 'offer', 'from': 1}),
      throwsFormatException,
    );
    expect(
      () => SignalMessage.fromJson({
        'type': 'offer',
        'from': 'a',
        'payload': 'texto',
      }),
      throwsFormatException,
    );
  });
}
