import 'dart:typed_data';

enum PeerLinkState { connecting, connected, disconnected, closed }

/// Conexão ponto a ponto com outro participante, com dois canais:
/// `ctrl` (JSON, ordenado) e `data` (binário, ordenado).
///
/// O protocolo de transferência só conhece esta interface; não sabe se por
/// baixo há WebRTC, memória (testes) ou outra coisa.
abstract class PeerLink {
  /// Acima disso, quem envia deve esperar [dataBufferedLow].
  static const bufferedLowThreshold = 256 * 1024;

  String get remoteId;
  PeerLinkState get state;
  Stream<PeerLinkState> get stateStream;

  Stream<Map<String, Object?>> get ctrlMessages;
  Stream<Uint8List> get dataMessages;

  Future<void> sendCtrl(Map<String, Object?> message);
  Future<void> sendData(Uint8List bytes);

  int get dataBufferedAmount;
  Stream<void> get dataBufferedLow;

  /// Ex.: `host/host`, `srflx/host`, `relay/srflx`; null se ainda não há par.
  Future<String?> selectedCandidatePairType();

  Future<void> close();
}
