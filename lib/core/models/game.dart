import 'compatibility_result.dart';
import 'game_requirements.dart';
import 'release_info.dart';

enum InstallStatus { notInstalled, installed, updateAvailable }

/// O jogo original de que o port deriva — usado para achar capa e capturas
/// de tela quando o repositório não tem imagens.
class GameOrigin {
  const GameOrigin({required this.title, this.systems = const [], this.wikipedia, this.steamAppId});

  /// Nome do jogo original (ex.: "Need for Speed: Underground 2").
  final String title;

  /// Consoles de origem no acervo libretro (ex.: "Sony - PlayStation 2").
  final List<String> systems;
  final String? wikipedia;
  final int? steamAppId;

  Map<String, dynamic> toJson() => {
        'title': title,
        if (systems.isNotEmpty) 'systems': systems,
        'wikipedia': ?wikipedia,
        'steam_appid': ?steamAppId,
      };

  static GameOrigin? fromJson(Object? raw) {
    if (raw is! Map || raw['title'] == null) return null;
    final sys = raw['systems'] ?? raw['system'];
    return GameOrigin(
      title: '${raw['title']}',
      systems: sys is List ? sys.map((e) => '$e').toList() : (sys is String ? [sys] : const []),
      wikipedia: raw['wikipedia'] as String?,
      steamAppId: (raw['steam_appid'] as num?)?.toInt(),
    );
  }
}

extension InstallStatusLabel on InstallStatus {
  String get label => switch (this) {
        InstallStatus.notInstalled => 'Não instalado',
        InstallStatus.installed => 'Instalado',
        InstallStatus.updateAvailable => 'Atualização disponível',
      };
}

/// Um jogo/port da biblioteca. Mistura metadados vindos do provedor/GitHub
/// (atualizados a cada sincronização) e estado do usuário (instalação,
/// favoritos, tempo de jogo), que é preservado entre sincronizações.
class Game {
  Game({
    required this.id,
    required this.name,
    required this.provider,
    this.description = '',
    this.readme,
    this.author = '',
    this.githubUrl = '',
    this.owner,
    this.repo,
    this.version,
    this.size,
    this.categories = const [],
    this.engine,
    this.coverUrl,
    this.bannerUrl,
    this.iconUrl,
    this.gallery = const [],
    this.tags = const [],
    this.language,
    this.license,
    this.stars = 0,
    this.lastUpdate,
    this.requirements = const GameRequirements(),
    this.releases = const [],
    this.pinnedIssues = const [],
    this.androidPackage,
    this.aiSummary,
    this.origin,
    this.gameDataNote,
    this.artSource,
    // estado do usuário
    this.installed = false,
    this.installedVersion,
    this.installedAt,
    this.installPath,
    this.executablePath,
    this.compatibility = CompatibilityResult.unknown,
    this.favorite = false,
    this.wishlist = false,
    this.lastPlayed,
    this.playTimeSeconds = 0,
    this.sessions = 0,
    DateTime? syncedAt,
  }) : syncedAt = syncedAt ?? DateTime.now();

  /// `<provedor>:<owner>/<repo>` ou `<provedor>:<slug>`.
  final String id;
  String name;
  final String provider;
  String description;
  String? readme;
  String author;
  String githubUrl;
  String? owner;
  String? repo;
  String? version;
  int? size;
  List<String> categories;
  String? engine;
  String? coverUrl;
  String? bannerUrl;
  String? iconUrl;
  List<String> gallery;
  List<String> tags;
  String? language;
  String? license;
  int stars;
  DateTime? lastUpdate;
  GameRequirements requirements;
  List<ReleaseInfo> releases;
  List<PinnedIssue> pinnedIssues;
  String? androidPackage;
  String? aiSummary;

  bool installed;
  String? installedVersion;
  DateTime? installedAt;
  String? installPath;
  String? executablePath;
  CompatibilityResult compatibility;
  bool favorite;
  bool wishlist;
  DateTime? lastPlayed;
  int playTimeSeconds;
  int sessions;
  DateTime syncedAt;

  String get category => categories.isEmpty ? 'Outros' : categories.first;

  /// Emuladores vêm do mesmo catálogo (instalação e atualização iguais às de um
  /// port), mas aparecem na aba Emuladores, não entre os jogos.
  bool get isEmulator => categories.contains('Emulador');
  ReleaseInfo? get latestRelease => releases.isEmpty ? null : releases.first;
  String? get repoFullName => owner != null && repo != null ? '$owner/$repo' : null;

  GameOrigin? origin;

  /// Aviso exibido na página do jogo quando o port exige os arquivos do jogo
  /// original (ex.: "Copie o ISO do Xbox (USA) para /Black").
  String? gameDataNote;

  /// De onde veio a capa encontrada automaticamente (libretro, Wikipédia...).
  String? artSource;

  /// Asset escolhido para esta plataforma (definido pelo LibraryService).
  ReleaseAsset? bestAsset;

  bool updateAvailable = false;

  InstallStatus get status {
    if (!installed) return InstallStatus.notInstalled;
    return updateAvailable ? InstallStatus.updateAvailable : InstallStatus.installed;
  }

  /// Copia o estado do usuário de [old] para este objeto (usado na sincronização).
  void adoptUserState(Game old) {
    installed = old.installed;
    installedVersion = old.installedVersion;
    installedAt = old.installedAt;
    installPath = old.installPath;
    executablePath = old.executablePath;
    androidPackage ??= old.androidPackage;
    favorite = old.favorite;
    wishlist = old.wishlist;
    lastPlayed = old.lastPlayed;
    playTimeSeconds = old.playTimeSeconds;
    sessions = old.sessions;
    aiSummary ??= old.aiSummary;
    compatibility = old.compatibility;
  }

  /// Texto usado na pesquisa.
  late final String searchBlob = [
    name,
    author,
    engine ?? '',
    ...categories,
    ...tags,
    repoFullName ?? '',
  ].join(' ').toLowerCase();
}
