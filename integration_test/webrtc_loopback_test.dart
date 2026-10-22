// Task 8 — WebRTC real (flutter_webrtc nativo) entre dois pares no mesmo PC,
// com sinalização pelo servidor LAN de verdade em 127.0.0.1.
//
// flutter test integration_test/webrtc_loopback_test.dart -d windows
//
// Prova a pilha completa sem aparelhos. Não substitui o teste entre aparelhos.
import 'dart:math';
import 'dart:typed_data';

import 'package:appmusica/jam/signaling/lan/lan_signaling_client.dart';
import 'package:appmusica/jam/signaling/lan/lan_signaling_server.dart';
import 'package:appmusica/jam/transport/peer_link.dart';
import 'package:appmusica/jam/transport/peer_link_factory.dart';
import 'package:appmusica/jam/transport/webrtc_peer_link.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Nenhum teste de integração pode travar a máquina: limite total por teste.
const testLimit = Timeout(Duration(minutes: 2));

final _clock = Stopwatch()..start();

/// Registro com tempo, para achar onde trava.
void step(String s) {
  // ignore: avoid_print
  print('PASSO ${_clock.elapsedMilliseconds} ms: $s');
}

Future<T> limit<T>(Future<T> f, String what, [int seconds = 15]) => f.timeout(
  Duration(seconds: seconds),
  onTimeout: () {
    throw StateError('travou em: $what');
  },
);

RtcSessionBuilder webrtc(String side) =>
    (remoteId, {required initiator}) async {
      step('$side: criando sessão (initiator=$initiator)');
      final s = await limit(
        WebRtcSession.create(remoteId, initiator: initiator),
        '$side createPeerConnection/createDataChannel',
      );
      step('$side: sessão criada');
      s.link.stateStream.listen((st) => step('$side: estado $st'));
      return s;
    };

Future<PeerLink> connected(Stream<PeerLink> links) async {
  final link = await limit(links.first, 'primeiro link');
  if (link.state != PeerLinkState.connected) {
    await link.stateStream
        .firstWhere((s) => s == PeerLinkState.connected)
        .timeout(const Duration(seconds: 15));
  }
  return link;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('WebRTC real: conecta, troca ctrl e 1 MiB binário íntegro', (
    tester,
  ) async {
    final server = await LanSignalingServer.start(port: 0);
    final host = PeerLinkFactory(
      server.hostChannel,
      sessionBuilder: webrtc('anfitrião'),
      autoConnect: true,
    );
    final hostLink = connected(host.links);

    final guestSignal = await LanSignalingClient.connect(
      host: '127.0.0.1',
      port: server.port,
      roomCode: server.roomCode,
    );
    final guest = PeerLinkFactory(
      guestSignal,
      sessionBuilder: webrtc('convidado'),
    );
    step('convidado entrou na sala');
    final a = await hostLink;
    final b = await connected(guest.links);

    step('os dois lados conectados');
    final pairType = await limit(a.selectedCandidatePairType(), 'getStats');
    // ignore: avoid_print
    print('RESULTADO parICE=$pairType');
    // prflx: o outro lado foi descoberto pela checagem de conectividade antes
    // do candidato chegar pela sinalização. Continua direto na rede local.
    expect(pairType, anyOf('host/host', 'host/prflx', 'prflx/host'));

    final ctrl = b.ctrlMessages.first;
    await limit(a.sendCtrl({'t': 'ping', 'n': 1}), 'sendCtrl');
    expect(await ctrl.timeout(const Duration(seconds: 5)), {
      't': 'ping',
      'n': 1,
    });

    // 1 MiB em blocos de 16 KiB, conferido por SHA-256.
    final rng = Random(7);
    final payload = Uint8List.fromList(
      List.generate(1 << 20, (_) => rng.nextInt(256)),
    );
    final received = BytesBuilder(copy: false);
    final done = b.dataMessages
        .map((d) {
          received.add(d);
          return received.length;
        })
        .firstWhere((n) => n >= payload.length);
    final sw = Stopwatch()..start();
    for (var o = 0; o < payload.length; o += 16384) {
      await limit(
        a.sendData(Uint8List.sublistView(payload, o, o + 16384)),
        'sendData',
      );
    }
    await done.timeout(const Duration(seconds: 30));
    sw.stop();

    expect(sha256.convert(received.toBytes()), sha256.convert(payload));
    // ignore: avoid_print
    print('RESULTADO 1MiB em ${sw.elapsedMilliseconds} ms');

    step('encerrando');
    await limit(guest.dispose(), 'dispose convidado');
    await guestSignal.close();
    await limit(host.dispose(), 'dispose anfitrião');
    await server.stop();
    step('fim');
  }, timeout: testLimit);
}
