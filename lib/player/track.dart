/// Uma faixa que o player local sabe tocar.
class Track {
  Track({
    required this.id,
    required this.uri,
    required this.title,
    this.artist,
    this.duration,
    this.sha256,
  });

  /// Identificador estável durante a sessão (usado também como `mediaId`).
  final String id;

  /// `file://` ou `content://`.
  final String uri;
  final String title;
  final String? artist;
  final Duration? duration;

  /// Calculado sob demanda; identifica arquivos idênticos byte a byte.
  String? sha256;
}
