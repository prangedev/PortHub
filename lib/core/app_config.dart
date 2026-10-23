/// Constantes globais do PortHub.
class AppConfig {
  static const appName = 'PortHub';
  static const appVersion = '1.0.0';

  /// Catálogo comunitário remoto. Se falhar (ou estiver offline), o app usa a
  /// cópia embarcada em `assets/catalog/community.json`.
  /// Troque para o raw do seu fork: `https://raw.githubusercontent.com/<usuario>/porthub/main/assets/catalog/community.json`
  static const defaultCommunityCatalogUrl = '';

  static const bundledCatalogAsset = 'assets/catalog/community.json';

  static const githubApi = 'https://api.github.com';
  static const githubGraphQL = 'https://api.github.com/graphql';

  static const portMasterPortsJson =
      'https://github.com/PortsMaster/PortMaster-New/releases/latest/download/ports.json';
  static const portMasterRaw = 'https://raw.githubusercontent.com/PortsMaster/PortMaster-New/main/ports';

  /// Tempo máximo para considerar uma resposta do GitHub "fresca" sem revalidar.
  static const repoCacheTtl = Duration(hours: 6);
  static const readmeCacheTtl = Duration(hours: 24);

  /// Requisições simultâneas ao GitHub durante a atualização da biblioteca.
  static const githubConcurrency = 4;

  static const userAgent = 'PortHub/$appVersion (+https://github.com)';

  /// Repositório (owner/repo) de onde o próprio PortHub se atualiza. Definido no
  /// build automático (`--dart-define=PORTHUB_UPDATE_REPO=...`); vazio em builds
  /// locais, o que desliga a atualização automática.
  static const updateRepo = String.fromEnvironment('PORTHUB_UPDATE_REPO');

  /// Número do build (run do GitHub Actions). 0 = build local.
  static const buildNumber = int.fromEnvironment('PORTHUB_BUILD');
}
