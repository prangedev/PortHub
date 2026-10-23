import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../core/logger.dart';

/// Abre o SQLite local. No Android usa o sqflite nativo; no Windows/Linux usa
/// a implementação FFI (a biblioteca sqlite3 é empacotada automaticamente).
class AppDatabase {
  static const _version = 2;

  static Future<Database> open() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final dir = await getApplicationSupportDirectory();
    final path = p.join(dir.path, 'porthub.db');
    appLog.i('DB', 'Abrindo banco em $path');
    return openDatabase(
      path,
      version: _version,
      onCreate: (db, version) => createSchema(db),
      onUpgrade: (db, from, to) async {
        if (from < 2) {
          appLog.i('DB', 'Migrando para v2: extras dos jogos + biblioteca de ROMs');
          await db.execute('ALTER TABLE jogos ADD COLUMN extras TEXT');
          await db.execute(_romsTable);
        }
      },
    );
  }

  static Future<void> createSchema(Database db) async {
    final batch = db.batch();
    for (final sql in _schema) {
      batch.execute(sql);
    }
    await batch.commit(noResult: true);
  }

  /// Esquema. Nomes das colunas principais seguem a especificação (pt-BR).
  static const _schema = [
    '''
    CREATE TABLE jogos (
      id TEXT PRIMARY KEY,
      nome TEXT NOT NULL,
      descricao TEXT,
      readme TEXT,
      autor TEXT,
      github_url TEXT,
      owner TEXT,
      repo TEXT,
      versao TEXT,
      tamanho INTEGER,
      categoria TEXT,
      categorias TEXT,
      engine TEXT,
      capa TEXT,
      banner TEXT,
      icone TEXT,
      galeria TEXT,
      tags TEXT,
      linguagem TEXT,
      licenca TEXT,
      estrelas INTEGER DEFAULT 0,
      ultima_atualizacao INTEGER,
      requisitos TEXT,
      releases TEXT,
      issues_fixadas TEXT,
      pacote_android TEXT,
      resumo_ia TEXT,
      provedor TEXT,
      instalado INTEGER DEFAULT 0,
      versao_instalada TEXT,
      instalado_em INTEGER,
      caminho TEXT,
      executavel TEXT,
      compatibilidade TEXT,
      compat_score INTEGER,
      compat_json TEXT,
      favorito INTEGER DEFAULT 0,
      desejado INTEGER DEFAULT 0,
      ultimo_jogo INTEGER,
      tempo_jogo INTEGER DEFAULT 0,
      sessoes INTEGER DEFAULT 0,
      sincronizado_em INTEGER,
      extras TEXT
    )''',
    'CREATE INDEX idx_jogos_instalado ON jogos(instalado)',
    '''
    CREATE TABLE hardware_cache (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      plataforma TEXT NOT NULL,
      dados TEXT NOT NULL,
      criado_em INTEGER NOT NULL
    )''',
    '''
    CREATE TABLE downloads (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      jogo_id TEXT NOT NULL,
      jogo_nome TEXT,
      url TEXT NOT NULL,
      arquivo TEXT NOT NULL,
      caminho TEXT NOT NULL,
      versao TEXT,
      tipo TEXT,
      total INTEGER DEFAULT 0,
      recebido INTEGER DEFAULT 0,
      estado TEXT NOT NULL,
      checksum TEXT,
      erro TEXT,
      criado_em INTEGER NOT NULL
    )''',
    '''
    CREATE TABLE http_cache (
      url TEXT PRIMARY KEY,
      etag TEXT,
      body TEXT NOT NULL,
      buscado_em INTEGER NOT NULL
    )''',
    '''
    CREATE TABLE settings (
      key TEXT PRIMARY KEY,
      value TEXT
    )''',
    _romsTable,
  ];

  /// Jogos importados para emuladores (ex.: ISOs de Xbox 360 para o XenDroid).
  static const _romsTable = '''
    CREATE TABLE roms (
      id TEXT PRIMARY KEY,
      sistema TEXT NOT NULL,
      nome TEXT NOT NULL,
      uri TEXT NOT NULL,
      arquivo TEXT NOT NULL,
      tamanho INTEGER,
      title_id TEXT,
      media_id TEXT,
      disco INTEGER DEFAULT 0,
      discos INTEGER DEFAULT 0,
      capa TEXT,
      capa_id TEXT,
      adicionado_em INTEGER NOT NULL,
      ultimo_jogo INTEGER,
      sessoes INTEGER DEFAULT 0
    )''';
}
