/// Comparação tolerante de versões vindas de tags do GitHub
/// (`v1.2.3`, `1.4`, `r146`, `2024-05-01`, `continuous`...).
library;

List<int> _numbers(String v) =>
    RegExp(r'\d+').allMatches(v).map((m) => int.tryParse(m.group(0)!) ?? 0).toList();

/// Retorna >0 se [a] for mais nova que [b], <0 se mais antiga e 0 se iguais.
int compareVersions(String a, String b) {
  final na = _numbers(a);
  final nb = _numbers(b);
  if (na.isEmpty || nb.isEmpty) return a == b ? 0 : (a.compareTo(b));
  final len = na.length > nb.length ? na.length : nb.length;
  for (var i = 0; i < len; i++) {
    final x = i < na.length ? na[i] : 0;
    final y = i < nb.length ? nb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

/// Verdadeiro quando [latest] representa uma release mais nova que [installed].
///
/// Tags sem números (ex.: `continuous`, `nightly`) só são consideradas novas
/// quando a data de publicação for posterior à instalação ([publishedAt] / [installedAt]).
bool isNewerVersion(String? latest, String? installed,
    {DateTime? publishedAt, DateTime? installedAt}) {
  if (latest == null || installed == null) return false;
  final l = latest.trim();
  final i = installed.trim();
  if (l == i) {
    if (publishedAt != null && installedAt != null) {
      // Builds "rolling" reaproveitam a mesma tag.
      return publishedAt.isAfter(installedAt.add(const Duration(minutes: 5)));
    }
    return false;
  }
  if (_numbers(l).isEmpty || _numbers(i).isEmpty) {
    if (publishedAt != null && installedAt != null) return publishedAt.isAfter(installedAt);
    return true;
  }
  return compareVersions(l, i) > 0;
}
