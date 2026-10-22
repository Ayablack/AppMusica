enum SignalType {
  hello,
  welcome,
  reject,
  peerJoined,
  peerLeft,
  offer,
  answer,
  candidate,
  bye,
}

/// Mensagem de sinalização. Não carrega áudio nem arquivos: só a
/// negociação da conexão entre aparelhos.
class SignalMessage {
  SignalMessage({
    required this.type,
    required this.from,
    this.to,
    this.payload = const {},
  });

  final SignalType type;
  final String from;
  final String? to;
  final Map<String, Object?> payload;

  Map<String, Object?> toJson() => {
    'type': type.name,
    'from': from,
    if (to != null) 'to': to,
    'payload': payload,
  };

  factory SignalMessage.fromJson(Map<String, Object?> json) {
    final typeName = json['type'];
    final type = SignalType.values.where((t) => t.name == typeName).firstOrNull;
    final from = json['from'];
    final to = json['to'];
    final payload = json['payload'] ?? const <String, Object?>{};
    if (type == null)
      throw FormatException('tipo de sinalização inválido: $typeName');
    if (from is! String || (to != null && to is! String) || payload is! Map) {
      throw const FormatException('mensagem de sinalização malformada');
    }
    return SignalMessage(
      type: type,
      from: from,
      to: to as String?,
      payload: Map<String, Object?>.from(payload),
    );
  }
}
