/// Funções de formatação usadas em toda a interface (pt-BR).
library;

String formatBytes(int? bytes, {int decimals = 1}) {
  if (bytes == null || bytes <= 0) return '—';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = unit == 0 ? 0 : decimals;
  return '${value.toStringAsFixed(digits).replaceAll('.', ',')} ${units[unit]}';
}

String formatSpeed(double bytesPerSecond) {
  if (bytesPerSecond <= 0) return '—';
  return '${formatBytes(bytesPerSecond.round())}/s';
}

String formatRamMb(int? mb) {
  if (mb == null || mb <= 0) return '—';
  if (mb < 1024) return '$mb MB';
  final gb = mb / 1024;
  return '${gb.toStringAsFixed(gb >= 10 ? 0 : 1).replaceAll('.', ',')} GB';
}

String formatEta(Duration? eta) {
  if (eta == null) return '—';
  final s = eta.inSeconds;
  if (s < 60) return '${s}s';
  if (s < 3600) return '${eta.inMinutes}min ${s % 60}s';
  return '${eta.inHours}h ${eta.inMinutes % 60}min';
}

String formatDate(DateTime? d) {
  if (d == null) return '—';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year}';
}

String formatPlayTime(int seconds) {
  if (seconds <= 0) return 'Nunca jogado';
  if (seconds < 3600) return '${(seconds / 60).ceil()} min jogados';
  final h = seconds / 3600;
  return '${h.toStringAsFixed(1).replaceAll('.', ',')} h jogadas';
}

String timeAgo(DateTime? d) {
  if (d == null) return '—';
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'agora';
  if (diff.inHours < 1) return 'há ${diff.inMinutes} min';
  if (diff.inDays < 1) return 'há ${diff.inHours} h';
  if (diff.inDays < 30) return 'há ${diff.inDays} dia${diff.inDays == 1 ? '' : 's'}';
  if (diff.inDays < 365) {
    final m = diff.inDays ~/ 30;
    return 'há $m ${m == 1 ? 'mês' : 'meses'}';
  }
  final y = diff.inDays ~/ 365;
  return 'há $y ano${y == 1 ? '' : 's'}';
}
