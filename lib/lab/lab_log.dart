import '../metrics/sanitize.dart';

/// Log das telas de laboratório: carimbo de tempo, saneamento e cópia no
/// logcat (prefixo APPMUSICA_LAB), para ler resultados por `adb logcat`.
class LabLog {
  final _clock = Stopwatch()..start();
  final lines = <String>[];

  /// Adiciona a linha (já saneada) no topo e devolve o texto registrado.
  String add(String line) {
    final t = _clock.elapsed;
    final stamp =
        '${t.inMinutes.toString().padLeft(2, '0')}:'
        '${(t.inSeconds % 60).toString().padLeft(2, '0')}.'
        '${(t.inMilliseconds % 1000).toString().padLeft(3, '0')}';
    final entry = '$stamp  ${sanitizeForLog(line)}';
    toLogcat(entry);
    lines.insert(0, entry);
    return entry;
  }

  static void toLogcat(String text) {
    for (final l in text.split('\n')) {
      // ignore: avoid_print
      print('APPMUSICA_LAB $l');
    }
  }
}
