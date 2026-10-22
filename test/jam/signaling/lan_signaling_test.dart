import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appmusica/jam/signaling/lan/lan_signaling_client.dart';
import 'package:appmusica/jam/signaling/lan/lan_signaling_server.dart';
import 'package:appmusica/jam/signaling/signal_message.dart';
import 'package:appmusica/jam/signaling/signaling_channel.dart';
import 'package:flutter_test/flutter_test.dart';

const loopback = '127.0.0.1';

void main() {
  late LanSignalingServer server;

  setUp(() async {
    // Porta 0: o sistema escolhe uma livre, para os testes não colidirem.
    server = await LanSignalingServer.start(port: 0);
  });

  tearDown(() => server.stop());

  Future<SignalingChannel> join([String? code]) => LanSignalingClient.connect(
    host: loopback,
    port: server.port,
    roomCode: code ?? server.roomCode,
  );

  test('roomCode tem 8 caracteres do alfabeto permitido', () {
    final allowed = RegExp(r'^[23456789ABCDEFGHJKMNPQRSTUVWXYZ]{8}$');
    for (var i = 0; i < 1000; i++) {
      expect(LanSignalingServer.generateRoomCode(), matches(allowed));
    }
  });

  test(
    'convidado com código certo recebe welcome e o anfitrião recebe peerJoined',
    () async {
      final joined = server.hostChannel.messages.firstWhere(
        (m) => m.type == SignalType.peerJoined,
      );

      final guest = await join();
      addTearDown(guest.close);

      expect(guest.selfId, isNotEmpty);
      expect(guest.hostId, server.hostChannel.selfId);
      expect((await joined).from, guest.selfId);
    },
  );

  test('código errado recebe reject bad_code', () async {
    await expectLater(
      join('AAAAAAAA'),
      throwsA(
        isA<SignalingRejected>().having((e) => e.reason, 'reason', 'bad_code'),
      ),
    );
  });

  test('sexto participante recebe reject full', () async {
    final guests = [for (var i = 0; i < 4; i++) await join()];
    addTearDown(() async {
      for (final g in guests) {
        await g.close();
      }
    });

    await expectLater(
      join(),
      throwsA(
        isA<SignalingRejected>().having((e) => e.reason, 'reason', 'full'),
      ),
    );
  });

  test('mensagem do anfitrião com to chega só ao destinatário', () async {
    final a = await join();
    final b = await join();
    addTearDown(a.close);
    addTearDown(b.close);
    final receivedByB = <SignalMessage>[];
    final sub = b.messages.listen(receivedByB.add);
    addTearDown(sub.cancel);

    final toA = a.messages.firstWhere((m) => m.type == SignalType.offer);
    await server.hostChannel.send(
      SignalMessage(
        type: SignalType.offer,
        from: '',
        to: a.selfId,
        payload: {'sdp': 'x'},
      ),
    );

    final got = await toA.timeout(const Duration(seconds: 2));
    expect(got.from, server.hostChannel.selfId);
    expect(got.payload['sdp'], 'x');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(receivedByB.where((m) => m.type == SignalType.offer), isEmpty);
  });

  test(
    'convidado só fala com o anfitrião e não pode falsificar o remetente',
    () async {
      final a = await join();
      final b = await join();
      addTearDown(a.close);
      addTearDown(b.close);
      final receivedByB = <SignalMessage>[];
      final sub = b.messages.listen(receivedByB.add);
      addTearDown(sub.cancel);
      final atHost = server.hostChannel.messages.firstWhere(
        (m) => m.type == SignalType.answer,
      );

      await a.send(
        SignalMessage(
          type: SignalType.answer,
          from: b.selfId,
          to: b.selfId,
          payload: {},
        ),
      );

      final got = await atHost.timeout(const Duration(seconds: 2));
      expect(got.from, a.selfId, reason: 'remetente vem do servidor');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(receivedByB, isEmpty);
    },
  );

  test('convidado que cai gera peerLeft no anfitrião', () async {
    final guest = await join();
    final left = server.hostChannel.messages.firstWhere(
      (m) => m.type == SignalType.peerLeft,
    );

    await guest.close();

    expect((await left.timeout(const Duration(seconds: 2))).from, guest.selfId);
  });

  test('conexão sem hello é fechada após o prazo', () async {
    await server.stop();
    server = await LanSignalingServer.start(
      port: 0,
      helloTimeout: const Duration(milliseconds: 200),
    );
    final ws = await WebSocket.connect('ws://$loopback:${server.port}/');
    final closed = Completer<void>();
    ws.listen((_) {}, onDone: closed.complete);

    await closed.future.timeout(const Duration(seconds: 2));
    expect(ws.closeCode, isNotNull);
  });

  test('mensagem acima de 64 KiB fecha a conexão', () async {
    final ws = await WebSocket.connect('ws://$loopback:${server.port}/');
    final closed = Completer<void>();
    ws.listen((_) {}, onDone: closed.complete);

    ws.add(
      jsonEncode({
        'type': 'hello',
        'from': '',
        'payload': {'roomCode': 'x' * (65 * 1024)},
      }),
    );

    await closed.future.timeout(const Duration(seconds: 2));
  });

  test('5 códigos errados bloqueiam o endereço por 1 minuto', () async {
    var now = DateTime(2026, 10, 22, 12);
    await server.stop();
    server = await LanSignalingServer.start(port: 0, clock: () => now);

    for (var i = 0; i < 5; i++) {
      await expectLater(join('AAAAAAAA'), throwsA(isA<SignalingRejected>()));
    }
    await expectLater(
      join(),
      throwsA(
        isA<SignalingRejected>().having((e) => e.reason, 'reason', 'blocked'),
      ),
    );

    now = now.add(const Duration(minutes: 1, seconds: 1));
    final guest = await join();
    await guest.close();
  });
}
