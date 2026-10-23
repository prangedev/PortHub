import '../../core/models/game.dart';
import '../../core/models/game_requirements.dart';
import '../../core/models/release_info.dart';
import '../../github/github_client.dart';

/// Entrada bruta de um provedor, antes do enriquecimento com dados do GitHub.
class CatalogEntry {
  CatalogEntry({
    required this.id,
    required this.provider,
    this.name,
    this.owner,
    this.repo,
    this.description,
    this.author,
    this.categories = const [],
    this.tags = const [],
    this.engine,
    this.requirements,
    this.cover,
    this.banner,
    this.icon,
    this.gallery = const [],
    this.androidPackage,
    this.directRelease,
    this.homepage,
    this.prereleases = false,
    this.prefetchedRepo,
    this.origin,
    this.gameDataNote,
  });

  /// Jogo original (para capa e capturas quando o repositório não tem imagens).
  final GameOrigin? origin;

  /// Aviso de que o port exige os arquivos do jogo original.
  final String? gameDataNote;

  /// Metadados já obtidos (ex.: resultado de busca), evitando uma requisição extra.
  final GitHubRepo? prefetchedRepo;

  /// Inclui prereleases (projetos que só publicam builds "continuous").
  final bool prereleases;

  /// Identificador estável: `<provedor>:<owner>/<repo>` ou `<provedor>:<slug>`.
  final String id;
  final String provider;
  final String? name;
  final String? owner;
  final String? repo;
  final String? description;
  final String? author;
  final List<String> categories;
  final List<String> tags;
  final String? engine;
  final GameRequirements? requirements;
  final String? cover;
  final String? banner;
  final String? icon;
  final List<String> gallery;
  final String? androidPackage;

  /// Para provedores sem GitHub Releases (ex.: PortMaster): release já pronta.
  final ReleaseInfo? directRelease;
  final String? homepage;

  bool get hasGitHub => owner != null && repo != null;
  String? get repoKey => hasGitHub ? '${owner!.toLowerCase()}/${repo!.toLowerCase()}' : null;
}

/// Contrato de um provedor de jogos. Cada fonte (GitHub, PortMaster, lista
/// JSON...) implementa seu próprio adaptador.
abstract class GameSourceProvider {
  String get id;
  String get displayName;
  String get description;

  /// Habilitado por padrão nesta plataforma?
  bool get enabledByDefault;

  Future<List<CatalogEntry>> fetch();
}
