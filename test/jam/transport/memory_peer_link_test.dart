import 'dart:typed_data';

import 'package:appmusica/jam/transport/memory_peer_link.dart';
import 'package:appmusica/jam/transport/peer_link.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List bytes(List<int> v) => Uint8List.fromList(v);

void main() {
  test('par em memória entrega ctrl e data na ordem', () async {
    final (a, b) = MemoryPeerLink.pair();
    final ctrl = b.ctrlMessages.take(2).toList();
    final data = b.dataMessages.take(3).toList();

    await a.sendCtrl({'n': 1});
    await a.sendData(bytes([1]));
    await a.sendCtrl({'n': 2});
    await a.sendData(bytes([2]));
    await a.sendData(bytes([3]));

    expect(await ctrl, [
      {'n': 1},
      {'n': 2},
    ]);
    expect((await data).map((d) => d.first), [1, 2, 3]);
    expect(a.remoteId, 'b');
    expect(b.remoteId, 'a');
  });

  test(
    'simulateDisconnect muda os dois lados para disconnected e descarta envios',
    () async {
      final (a, b) = MemoryPeerLink.pair();
      final received = <Uint8List>[];
      b.dataMessages.listen(received.add);

      a.simulateDisconnect();
      await a.sendData(bytes([9]));
      await Future<void>.delayed(Duration.zero);

      expect(a.state, PeerLinkState.disconnected);
      expect(b.state, PeerLinkState.disconnected);
      expect(received, isEmpty);
    },
  );

  test('simulateReconnect volta os dois lados para connected', () async {
    final (a, b) = MemoryPeerLink.pair();
    a.simulateDisconnect();
    final backOnB = b.stateStream.firstWhere(
      (s) => s == PeerLinkState.connected,
    );

    a.simulateReconnect();

    await backOnB;
    expect(a.state, PeerLinkState.connected);
  });

  test('dropAfterDataMessages: 10 desconecta após o 10º bloco', () async {
    final (a, b) = MemoryPeerLink.pair(dropAfterDataMessages: 10);
    final received = <Uint8List>[];
    b.dataMessages.listen(received.add);

    for (var i = 0; i < 15; i++) {
      await a.sendData(bytes([i]));
    }
    await Future<void>.delayed(Duration.zero);

    expect(received, hasLength(10));
    expect(a.state, PeerLinkState.disconnected);
  });

  test('corruptDataMessages altera só os blocos indicados', () async {
    final (a, b) = MemoryPeerLink.pair(corruptDataMessages: {1});
    final data = b.dataMessages.take(3).toList();

    for (var i = 0; i < 3; i++) {
      await a.sendData(bytes([7, 7, 7]));
    }

    final got = await data;
    expect(got[0], [7, 7, 7]);
    expect(got[1], isNot([7, 7, 7]));
    expect(got[2], [7, 7, 7]);
  });

  test('setBufferedAmount abaixo de 256 KiB emite dataBufferedLow', () async {
    final (a, _) = MemoryPeerLink.pair();
    final low = a.dataBufferedLow.first;

    a.setBufferedAmount(2 << 20);
    expect(a.dataBufferedAmount, 2 << 20);
    a.setBufferedAmount(100);

    await low;
    expect(a.dataBufferedAmount, 100);
  });

  test('close fecha os dois lados', () async {
    final (a, b) = MemoryPeerLink.pair();
    await a.close();
    expect(a.state, PeerLinkState.closed);
    expect(b.state, PeerLinkState.closed);
  });
}
