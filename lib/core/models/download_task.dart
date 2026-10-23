import 'release_info.dart';

enum DownloadState { queued, downloading, paused, verifying, completed, installing, installed, failed, canceled }

extension DownloadStateLabel on DownloadState {
  String get label => switch (this) {
        DownloadState.queued => 'Na fila',
        DownloadState.downloading => 'Baixando',
        DownloadState.paused => 'Pausado',
        DownloadState.verifying => 'Verificando integridade',
        DownloadState.completed => 'Concluído',
        DownloadState.installing => 'Instalando',
        DownloadState.installed => 'Instalado',
        DownloadState.failed => 'Falhou',
        DownloadState.canceled => 'Cancelado',
      };

  bool get isActive => this == DownloadState.downloading || this == DownloadState.verifying;
  bool get isFinished =>
      this == DownloadState.installed || this == DownloadState.canceled || this == DownloadState.completed;
}

/// Uma tarefa do Download Manager (persistida na tabela `downloads`).
class DownloadTask {
  DownloadTask({
    this.id,
    required this.gameId,
    required this.gameName,
    required this.url,
    required this.fileName,
    required this.filePath,
    required this.version,
    required this.kind,
    this.totalBytes = 0,
    this.receivedBytes = 0,
    this.state = DownloadState.queued,
    this.checksum,
    this.error,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  int? id;
  final String gameId;
  final String gameName;
  final String url;
  final String fileName;

  /// Caminho final do arquivo (o download parcial usa `<filePath>.part`).
  final String filePath;
  final String version;
  final AssetKind kind;
  int totalBytes;
  int receivedBytes;
  DownloadState state;

  /// `sha256:<hex>` ou `md5:<hex>`.
  String? checksum;
  String? error;
  final DateTime createdAt;

  // Métricas em tempo real (não persistidas).
  double speedBps = 0;
  Duration? eta;
  bool checksumVerified = false;

  double get progress => totalBytes > 0 ? (receivedBytes / totalBytes).clamp(0.0, 1.0) : 0;
  String get partPath => '$filePath.part';
}
