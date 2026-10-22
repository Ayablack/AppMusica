import 'dart:async';

import 'package:appmusica/jam/signaling/signaling_channel.dart';
import 'package:appmusica/jam/transport/memory_peer_link.dart';
import 'package:appmusica/jam/transport/peer_link.dart';
import 'package:appmusica/jam/transport/peer_link_factory.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sessão falsa: registra a negociação e devolve um MemoryPeerLink.
class FakeSession implements RtcSession {
  FakeSession(this.remoteId, this.initiator, this.link);

  final String remoteId;
  final bool initiator;
  @override
  final PeerLink link;
  final log = <String>[];
  final candidates = StreamController<Map<String, Object?>>();

  @override
  Stream<Map<String, Object?>> get localCandidates => candidates.stream;

  @override
  Future<Map<String, Object?>> createOffer() async {
    log.add('createOffer');
    candidates.add({'candidate': 'c-$remoteId-offerer'});
    return {'type': 'offer', 'sdp': 'OFFER'};
  }

  @override
  Future<Map<String, Object?>> acceptOffer(Map<String, Object?> offer) async {
    log.add('acceptOffer:${offer['sdp']}');
    candidates.add({'candidate': 'c-answerer'});
    return {'type': 'answer', 'sdp': 'ANSWER'};
  }

  @override
  Future<void> acceptAnswer(Map<String, Object?> answer) async =>
      log.add('acceptAnswer:${answer['sdp']}');

  @override
  Future<void> addCandidate(Map<String, Object?> c) async =>
      log.add('addCandidate:${c['candidate']}');

  @override
  Future<void> dispose() async => candidates.close();
}

void main() {
  test('fábrica troca offer, answer e candidatos e entrega os links dos dois lados', () async {
    final hub = LoopbackSignalingHub();
    final hostSignal = hub.join('host');
    final (hostLink, guestLink) = MemoryPeerLink.pair(idA: 'host', idB: 'g1');
    final sessions = <String, FakeSession>{};

    RtcSessionBuilder builderFor(String side, PeerLink link) =>
        (remoteId, {required initiator}) async =>
            sessions[side] = FakeSession(remoteId, initiator, link);

    final host = PeerLinkFactory(
      hostSignal,
      sessionBuilder: builderFor('host', hostLink),
    );
    final hostLinks = host.links.first;

    final guestSignal = hub.join('g1');
    final guest = PeerLinkFactory(
      guestSignal,
      sessionBuilder: builderFor('guest', guestLink),
    );
    final guestLinks = guest.links.first;

    await host.connectTo('g1');

    expect(await hostLinks.timeout(const Duration(seconds: 1)), same(hostLink));
    expect(
      await guestLinks.timeout(const Duration(seconds: 1)),
      same(guestLink),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(sessions['host']!.initiator, isTrue);
    expect(sessions['guest']!.initiator, isFalse);
    expect(sessions['host']!.log, [
      'createOffer',
      'acceptAnswer:ANSWER',
      'addCandidate:c-answerer',
    ]);
    expect(sessions['guest']!.log, [
      'acceptOffer:OFFER',
      'addCandidate:c-g1-offerer',
    ]);

    await host.dispose();
    await guest.dispose();
  });

  test(
    'anfitrião conecta automaticamente quem entra quando autoConnect',
    () async {
      final hub = LoopbackSignalingHub();
      final hostSignal = hub.join('host');
      final created = <String>[];
      final host = PeerLinkFactory(
        hostSignal,
        autoConnect: true,
        sessionBuilder: (remoteId, {required initiator}) async {
          created.add(remoteId);
          final (l, _) = MemoryPeerLink.pair();
          return FakeSession(remoteId, initiator, l);
        },
      );

      hub.join('g1');
      hub.join('g2');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(created, ['g1', 'g2']);
      await host.dispose();
    },
  );

  test('link criado antes de alguém escutar não se perde', () async {
    final hub = LoopbackSignalingHub();
    final host = PeerLinkFactory(
      hub.join('host'),
      sessionBuilder: (remoteId, {required initiator}) async {
        final (l, _) = MemoryPeerLink.pair();
        return FakeSession(remoteId, initiator, l);
      },
    );

    await host.connectTo('g1');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final link = await host.links.first.timeout(const Duration(seconds: 1));
    expect(link.state, PeerLinkState.connected);
    await host.dispose();
  });

  test('peerLeft descarta a sessão daquele convidado', () async {
    final hub = LoopbackSignalingHub();
    final hostSignal = hub.join('host');
    FakeSession? session;
    final host = PeerLinkFactory(
      hostSignal,
      autoConnect: true,
      sessionBuilder: (remoteId, {required initiator}) async {
        final (l, _) = MemoryPeerLink.pair();
        return session = FakeSession(remoteId, initiator, l);
      },
    );
    final g1 = hub.join('g1');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    await g1.close();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(session!.candidates.isClosed, isTrue);
    expect(session!.link.state, PeerLinkState.closed);
    await host.dispose();
  });
}
