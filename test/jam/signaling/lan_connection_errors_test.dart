import 'dart:io';

import 'package:appmusica/jam/signaling/lan/lan_signaling_client.dart';
import 'package:appmusica/jam/signaling/lan/lan_signaling_server.dart';
import 'package:appmusica/jam/signaling/signaling_channel.dart';
import 'package:flutter_test/flutter_test.dart';

Matcher failsWith(String code) => throwsA(
  isA<SignalingConnectionFailed>().having((e) => e.code, 'code', code),
);

void main() {
  group('validação do endereço antes de conectar', () {
    for (final host in [
      '',
      '   ',
      '192,168,0,10',
      '192.168.0',
      '300.1.1.1',
      'a b',
    ]) {
      test('"$host" é recusado como invalid_address sem abrir conexão', () {
        expect(
          LanSignalingClient.connect(
            host: host,
            port: 47820,
            roomCode: 'ABCDEFGH',
          ),
          failsWith('invalid_address'),
        );
      });
    }

    test('porta fora de 1–65535 é invalid_port', () {
      expect(
        LanSignalingClient.connect(
          host: '127.0.0.1',
          port: 0,
          roomCode: 'ABCDEFGH',
        ),
        failsWith('invalid_port'),
      );
    });

    test('código com tamanho ou caracteres errados é invalid_code', () {
      expect(
        LanSignalingClient.connect(
          host: '127.0.0.1',
          port: 47820,
          roomCode: 'ABC',
        ),
        failsWith('invalid_code'),
      );
    });
  });

  test('ninguém escutando na porta vira refused', () async {
    // Reserva uma porta e libera, para ter certeza de que está fechada.
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = s.port;
    await s.close();

    await expectLater(
      LanSignalingClient.connect(
        host: '127.0.0.1',
        port: port,
        roomCode: 'ABCDEFGH',
      ),
      failsWith('refused'),
    );
  });

  test('anfitrião que não responde vira timeout', () async {
    // Servidor TCP mudo: aceita a conexão e nunca responde ao WebSocket.
    final mute = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final held = <Socket>[];
    mute.listen(held.add);
    addTearDown(() async {
      for (final s in held) {
        s.destroy();
      }
      await mute.close();
    });

    await expectLater(
      LanSignalingClient.connect(
        host: '127.0.0.1',
        port: mute.port,
        roomCode: 'ABCDEFGH',
        timeout: const Duration(milliseconds: 300),
      ),
      failsWith('timeout'),
    );
  });

  test('mensagem do erro não contém o IP', () async {
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = s.port;
    await s.close();
    try {
      await LanSignalingClient.connect(
        host: '127.0.0.1',
        port: port,
        roomCode: 'ABCDEFGH',
      );
      fail('deveria falhar');
    } on SignalingConnectionFailed catch (e) {
      expect(e.message, isNot(contains('127.0.0.1')));
      expect(e.toString(), isNot(contains('127.0.0.1')));
      expect(e.message, isNotEmpty);
    }
  });

  test('porta do servidor já em uso vira port_in_use', () async {
    final first = await LanSignalingServer.start(port: 0);
    addTearDown(first.stop);

    await expectLater(
      LanSignalingServer.start(port: first.port),
      throwsA(
        isA<SignalingServerFailed>().having(
          (e) => e.code,
          'code',
          'port_in_use',
        ),
      ),
    );
  });

  test('describeRejection explica cada motivo', () {
    for (final r in ['bad_code', 'full', 'blocked', 'protocol']) {
      expect(SignalingRejected(r).message, isNotEmpty);
    }
    expect(SignalingRejected('full').message, contains('5'));
  });
}
