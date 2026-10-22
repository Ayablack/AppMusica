/// Saneamento de textos que vão para logs exportáveis: remove IPs, caminhos
/// de arquivo e e-mails. Prefere remover demais a vazar dado pessoal.
String sanitizeForLog(String text) {
  var s = text;
  s = s.replaceAll(RegExp(r'file:///\S+'), '<caminho>');
  s = s.replaceAll(RegExp(r'[A-Za-z]:[\\/][^\s,;)]*'), '<caminho>');
  s = s.replaceAll(
    RegExp(r'/(?:storage|sdcard|data|Users|home|mnt|private|var)/[^\n,;)]*'),
    '<caminho>',
  );
  s = s.replaceAll(RegExp(r'[\w.+-]+@[\w-]+\.[\w.]+'), '<email>');
  s = s.replaceAll(
    RegExp(r'(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])'),
    '<ip>',
  );
  // IPv6: exige "::" ou 5+ grupos, para não confundir com horários (00:01:23).
  s = s.replaceAllMapped(
    RegExp(
      r'(?<![\w:.])[0-9a-fA-F]{1,4}(?::[0-9a-fA-F]{0,4}){2,7}(?:%[\w.]+)?',
    ),
    (m) {
      final v = m[0]!;
      return v.contains('::') || ':'.allMatches(v).length >= 5 ? '<ip>' : v;
    },
  );
  return s;
}

/// Tipo, mensagem saneada e até 3 frames do próprio app.
String describeError(Object error, [StackTrace? stack]) {
  final message = sanitizeForLog(error.toString().split('\n').first);
  final frames = (stack?.toString().split('\n') ?? const <String>[])
      .where((l) => l.contains('package:appmusica/'))
      .take(3)
      .map((l) => '  em ${sanitizeForLog(l.trim())}');
  return ['${error.runtimeType}: $message', ...frames].join('\n');
}
