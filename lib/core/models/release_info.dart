/// Tipo de arquivo de uma release, detectado pelo nome.
enum AssetKind { apk, splitApk, zip, tarball, appImage, exe, msi, deb, checksum, other }

/// Plataforma alvo deduzida do nome/extensão do asset.
enum AssetPlatform { android, linux, windows, macos, unknown }

extension AssetKindLabel on AssetKind {
  String get label => switch (this) {
        AssetKind.apk => 'APK',
        AssetKind.splitApk => 'APK dividido',
        AssetKind.zip => 'ZIP',
        AssetKind.tarball => 'TAR',
        AssetKind.appImage => 'AppImage',
        AssetKind.exe => 'EXE',
        AssetKind.msi => 'MSI',
        AssetKind.deb => 'DEB',
        AssetKind.checksum => 'Checksum',
        AssetKind.other => 'Arquivo',
      };
}

class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.url,
    required this.size,
    required this.kind,
    required this.platform,
    this.arch,
    this.checksum,
    this.downloadCount = 0,
  });

  final String name;
  final String url;
  final int size;
  final AssetKind kind;
  final AssetPlatform platform;

  /// Arquitetura normalizada (`arm64`, `armv7`, `x86_64`, `x86`) ou null = universal.
  final String? arch;

  /// `"sha256:<hex>"` ou `"md5:<hex>"` quando disponível.
  final String? checksum;
  final int downloadCount;

  bool get installable => kind != AssetKind.checksum && kind != AssetKind.other;

  ReleaseAsset copyWith({String? checksum}) => ReleaseAsset(
        name: name,
        url: url,
        size: size,
        kind: kind,
        platform: platform,
        arch: arch,
        checksum: checksum ?? this.checksum,
        downloadCount: downloadCount,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'url': url,
        'size': size,
        'kind': kind.name,
        'platform': platform.name,
        'arch': arch,
        'checksum': checksum,
        'downloads': downloadCount,
      };

  factory ReleaseAsset.fromJson(Map<String, dynamic> j) => ReleaseAsset(
        name: j['name'] as String,
        url: j['url'] as String,
        size: (j['size'] as num?)?.toInt() ?? 0,
        kind: AssetKind.values.asNameMap()[j['kind']] ?? AssetKind.other,
        platform: AssetPlatform.values.asNameMap()[j['platform']] ?? AssetPlatform.unknown,
        arch: j['arch'] as String?,
        checksum: j['checksum'] as String?,
        downloadCount: (j['downloads'] as num?)?.toInt() ?? 0,
      );
}

class ReleaseInfo {
  const ReleaseInfo({
    required this.tag,
    required this.name,
    required this.body,
    required this.publishedAt,
    required this.assets,
    this.prerelease = false,
    this.htmlUrl,
  });

  final String tag;
  final String name;

  /// Changelog (markdown).
  final String body;
  final DateTime? publishedAt;
  final List<ReleaseAsset> assets;
  final bool prerelease;
  final String? htmlUrl;

  Iterable<ReleaseAsset> get checksumAssets => assets.where((a) => a.kind == AssetKind.checksum);

  Map<String, dynamic> toJson() => {
        'tag': tag,
        'name': name,
        'body': body,
        'published_at': publishedAt?.toIso8601String(),
        'assets': assets.map((a) => a.toJson()).toList(),
        'prerelease': prerelease,
        'html_url': htmlUrl,
      };

  factory ReleaseInfo.fromJson(Map<String, dynamic> j) => ReleaseInfo(
        tag: j['tag'] as String? ?? '',
        name: j['name'] as String? ?? '',
        body: j['body'] as String? ?? '',
        publishedAt: DateTime.tryParse(j['published_at'] as String? ?? ''),
        assets: ((j['assets'] as List?) ?? const [])
            .map((e) => ReleaseAsset.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        prerelease: j['prerelease'] as bool? ?? false,
        htmlUrl: j['html_url'] as String?,
      );
}

/// Issue fixada no repositório (obtida via GraphQL quando há token).
class PinnedIssue {
  const PinnedIssue({required this.title, required this.url, this.body = ''});
  final String title;
  final String url;
  final String body;

  Map<String, dynamic> toJson() => {'title': title, 'url': url, 'body': body};
  factory PinnedIssue.fromJson(Map<String, dynamic> j) =>
      PinnedIssue(title: j['title'] as String? ?? '', url: j['url'] as String? ?? '', body: j['body'] as String? ?? '');
}
