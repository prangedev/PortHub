import '../../github/github_client.dart';
import 'game_source_provider.dart';

/// Provedor "GitHub": descobre repositórios pelos tópicos. Qualquer porter pode
/// aparecer no PortHub adicionando o tópico `porthub` (e, opcionalmente, um
/// `porthub.yaml`) ao repositório.
class GitHubTopicProvider extends GameSourceProvider {
  GitHubTopicProvider(this._gh);
  final GitHubClient _gh;

  static const queries = [
    'topic:porthub fork:false',
    'topic:android-port fork:false',
    'topic:game-port fork:false stars:>20',
  ];

  /// Repositórios-isca: "jogo X completo, download grátis" com executável que
  /// costuma ser malware. Comuns em buscas por nomes de jogos famosos.
  static final _bait = RegExp(
    r'free[\s-]*(full[\s-]*)?(version|download|game)|full[\s-]*version|download\s+(now|free|for\s+(pc|windows))'
    r'|\bcrack(ed)?\b|\btorrent\b|keygen|\brepack\b|activation\s*key|no\s*survey|mod\s*apk|unlimited\s+(money|coins)',
    caseSensitive: false,
  );

  static bool looksLikeBait(GitHubRepo r) {
    final text = '${r.name.replaceAll(RegExp(r'[-_]'), ' ')} ${r.description}';
    if (_bait.hasMatch(text)) return true;
    // Sem estrelas e se oferecendo para "baixar o jogo" também é suspeito.
    return r.stars == 0 && RegExp(r'\bdownload\b', caseSensitive: false).hasMatch(r.description);
  }

  @override
  String get id => 'github';
  @override
  String get displayName => 'GitHub (tópicos)';
  @override
  String get description => 'Repositórios com os tópicos porthub, android-port ou game-port.';
  @override
  bool get enabledByDefault => true;

  @override
  Future<List<CatalogEntry>> fetch() async {
    final out = <CatalogEntry>[];
    for (final q in queries) {
      final repos = await _gh.searchRepos(q, perPage: 25);
      for (final r in repos) {
        if (r.archived || looksLikeBait(r)) continue;
        out.add(CatalogEntry(
          id: 'gh:${r.fullName.toLowerCase()}',
          provider: id,
          owner: r.owner,
          repo: r.name,
          prefetchedRepo: r,
        ));
      }
    }
    return out;
  }
}

/// Provedor "Repositórios Open Source": jogos open source populares no GitHub.
/// Desligado por padrão (muitos não publicam binários).
class OpenSourceProvider extends GameSourceProvider {
  OpenSourceProvider(this._gh);
  final GitHubClient _gh;

  @override
  String get id => 'opensource';
  @override
  String get displayName => 'Repositórios Open Source';
  @override
  String get description => 'Jogos open source populares (tópico open-source-game) com releases.';
  @override
  bool get enabledByDefault => false;

  @override
  Future<List<CatalogEntry>> fetch() async {
    final repos = await _gh.searchRepos('topic:open-source-game stars:>300 fork:false', perPage: 40);
    return [
      for (final r in repos)
        if (!r.archived && !GitHubTopicProvider.looksLikeBait(r))
          CatalogEntry(id: 'gh:${r.fullName.toLowerCase()}', provider: id, owner: r.owner, repo: r.name, prefetchedRepo: r),
    ];
  }
}
