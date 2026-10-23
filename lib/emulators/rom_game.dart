/// Um jogo importado para um emulador (ex.: ISO de Xbox 360).
///
/// O arquivo não é copiado: [uri] é um `content://` com permissão persistente
/// (Android) ou um caminho local (desktop).
class RomGame {
  RomGame({
    required this.id,
    required this.system,
    required this.name,
    required this.uri,
    required this.fileName,
    this.size,
    this.titleId,
    this.mediaId,
    this.discNumber = 0,
    this.discCount = 0,
    this.coverUrl,
    this.coverId,
    DateTime? addedAt,
    this.lastPlayed,
    this.sessions = 0,
  }) : addedAt = addedAt ?? DateTime.now();

  final String id;
  final String system;
  String name;
  final String uri;
  final String fileName;
  final int? size;
  String? titleId;
  String? mediaId;
  int discNumber;
  int discCount;

  /// URL da capa escolhida (XboxUnity: capa completa, frente à direita).
  String? coverUrl;

  /// Id da capa no XboxUnity (para destacar a escolhida no seletor).
  String? coverId;
  final DateTime addedAt;
  DateTime? lastPlayed;
  int sessions;

  /// Capas do XboxUnity são abertas (verso + lombada + frente).
  bool get wrapCover => coverUrl?.contains('xboxunity.net') ?? false;

  String get discLabel => discCount > 1 && discNumber > 0 ? 'Disco $discNumber de $discCount' : '';

  Map<String, Object?> toRow() => {
        'id': id,
        'sistema': system,
        'nome': name,
        'uri': uri,
        'arquivo': fileName,
        'tamanho': size,
        'title_id': titleId,
        'media_id': mediaId,
        'disco': discNumber,
        'discos': discCount,
        'capa': coverUrl,
        'capa_id': coverId,
        'adicionado_em': addedAt.millisecondsSinceEpoch,
        'ultimo_jogo': lastPlayed?.millisecondsSinceEpoch,
        'sessoes': sessions,
      };

  factory RomGame.fromRow(Map<String, Object?> r) {
    DateTime? date(Object? v) => v == null ? null : DateTime.fromMillisecondsSinceEpoch(v as int);
    return RomGame(
      id: r['id'] as String,
      system: r['sistema'] as String,
      name: r['nome'] as String,
      uri: r['uri'] as String,
      fileName: r['arquivo'] as String,
      size: r['tamanho'] as int?,
      titleId: r['title_id'] as String?,
      mediaId: r['media_id'] as String?,
      discNumber: r['disco'] as int? ?? 0,
      discCount: r['discos'] as int? ?? 0,
      coverUrl: r['capa'] as String?,
      coverId: r['capa_id'] as String?,
      addedAt: date(r['adicionado_em']),
      lastPlayed: date(r['ultimo_jogo']),
      sessions: r['sessoes'] as int? ?? 0,
    );
  }
}
