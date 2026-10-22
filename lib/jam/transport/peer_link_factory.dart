import 'dart:async';

import '../signaling/signal_message.dart';
import '../signaling/signaling_channel.dart';
import 'peer_link.dart';

/// Negociação de uma conexão (oferta, resposta, candidatos ICE), separada
/// da sinalização. A implementação real é `WebRtcSession`.
abstract class RtcSession {
  PeerLink get link;

  /// Candidatos locais; devem ficar guardados até alguém escutar.
  Stream<Map<String, Object?>> get localCandidates;

  Future<Map<String, Object?>> createOffer();
  Future<Map<String, Object?>> acceptOffer(Map<String, Object?> offer);
  Future<void> acceptAnswer(Map<String, Object?> answer);
  Future<void> addCandidate(Map<String, Object?> candidate);
  Future<void> dispose();
}

typedef RtcSessionBuilder = Future<RtcSession> Function(
  String remoteId, {
  required bool initiator,
});

/// Cria [PeerLink]s usando qualquer [SignalingChannel].
///
/// O anfitrião inicia (oferta) para cada convidado; o convidado responde.
/// Candidatos ICE que chegam antes da descrição remota ficam na fila.
class PeerLinkFactory {
  PeerLinkFactory(
    this.signaling, {
    required this.sessionBuilder,
    this.autoConnect = false,
  }) {
    _sub = signaling.messages.listen(_onSignal);
  }

  final SignalingChannel signaling;
  final RtcSessionBuilder sessionBuilder;

  /// Anfitrião: conecta sozinho a cada `peerJoined`.
  final bool autoConnect;

  // Guarda links criados antes de alguém escutar.
  final _links = BufferedBroadcast<PeerLink>();
  final _peers = <String, _Peer>{};
  late final StreamSubscription<SignalMessage> _sub;

  Stream<PeerLink> get links => _links.controller.stream;

  Future<void> connectTo(String remoteId) async {
    final peer = await _create(remoteId, initiator: true);
    final offer = await peer.session.createOffer();
    await _send(SignalType.offer, remoteId, offer);
    _forwardCandidates(remoteId, peer);
  }

  Future<_Peer> _create(String remoteId, {required bool initiator}) async {
    await _drop(remoteId);
    final peer = _Peer(await sessionBuilder(remoteId, initiator: initiator));
    final orphan = _orphans.remove(remoteId);
    if (orphan != null) peer.adopt(orphan);
    _peers[remoteId] = peer;
    _links.add(peer.session.link);
    return peer;
  }

  void _forwardCandidates(String remoteId, _Peer peer) {
    peer.candidateSub = peer.session.localCandidates.listen(
      (c) => _send(SignalType.candidate, remoteId, c),
    );
  }

  Future<void> _onSignal(SignalMessage m) async {
    switch (m.type) {
      case SignalType.peerJoined when autoConnect:
        await connectTo(m.from);
      case SignalType.peerLeft:
        await _drop(m.from);
      case SignalType.offer:
        final peer = await _create(m.from, initiator: false);
        final answer = await peer.session.acceptOffer(m.payload);
        await peer.remoteReady();
        await _send(SignalType.answer, m.from, answer);
        _forwardCandidates(m.from, peer);
      case SignalType.answer:
        final peer = _peers[m.from];
        if (peer == null) return;
        await peer.session.acceptAnswer(m.payload);
        await peer.remoteReady();
      case SignalType.candidate:
        await (_peers[m.from] ?? _orphanQueue(m.from)).addRemote(m.payload);
      default:
        break;
    }
  }

  /// Candidato chegou antes da oferta: guarda num par provisório.
  _Peer _orphanQueue(String remoteId) =>
      _orphans.putIfAbsent(remoteId, _Peer.pending);
  final _orphans = <String, _Peer>{};

  Future<void> _send(
    SignalType type,
    String to,
    Map<String, Object?> payload,
  ) => signaling.send(
    SignalMessage(type: type, from: signaling.selfId, to: to, payload: payload),
  );

  Future<void> _drop(String remoteId) async {
    final peer = _peers.remove(remoteId);
    if (peer == null) return;
    await peer.candidateSub?.cancel();
    await peer.session.link.close();
    await peer.session.dispose();
  }

  Future<void> dispose() async {
    await _sub.cancel();
    for (final id in _peers.keys.toList()) {
      await _drop(id);
    }
    await _links.close();
  }
}

class _Peer {
  _Peer(RtcSession session) : _session = session;
  _Peer.pending() : _session = null;

  final RtcSession? _session;
  RtcSession get session => _session!;
  StreamSubscription<Map<String, Object?>>? candidateSub;
  bool _remoteSet = false;
  final _queued = <Map<String, Object?>>[];

  Future<void> addRemote(Map<String, Object?> c) async {
    if (_remoteSet && _session != null) {
      await session.addCandidate(c);
    } else {
      _queued.add(c);
    }
  }

  Future<void> remoteReady() async {
    _remoteSet = true;
    for (final c in _queued) {
      await session.addCandidate(c);
    }
    _queued.clear();
  }

  void adopt(_Peer orphan) => _queued.addAll(orphan._queued);
}
