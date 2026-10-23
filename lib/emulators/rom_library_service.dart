import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../core/logger.dart';
import '../database/rom_dao.dart';
import '../services/artwork_service.dart';
import '../services/native_bridge.dart';
import 'emulator_def.dart';
import 'rom_game.dart';
import 'xbox/xbox_unity.dart';
import 'xbox/xiso_reader.dart';

/// Lê um `content://` (Android) aos pedaços pelo canal nativo.
class ContentUriReader extends RandomReader {
  ContentUriReader(this.uri);
  final String uri;
  int? _length;

  @override
  Future<int> length() async => _length ??= await NativeBridge.uriSize(uri) ?? 0;

  @override
  Future<Uint8List> read(int offset, int count) => NativeBridge.readUri(uri, offset, count);
}

class ImportReport {
  int added = 0;
  int duplicates = 0;
  final failures = <String>[];

  String get summary {
    final parts = [
      if (added > 0) '$added ${added == 1 ? 'jogo importado' : 'jogos importados'}',
      if (duplicates > 0) '$duplicates já estava${duplicates == 1 ? '' : 'm'} na biblioteca',
      if (failures.isNotEmpty) '${failures.length} com erro',
    ];
    return parts.isEmpty ? 'Nenhum arquivo compatível encontrado.' : parts.join(' · ');
  }
}

/// Biblioteca de jogos dos emuladores: importação de ISOs, identificação pelo
/// Title ID, capas do XboxUnity (como o Aurora) e abertura no emulador.
class RomLibraryService extends ChangeNotifier {
  RomLibraryService(this._dao, this._unity);
  final RomDao _dao;
  final XboxUnity _unity;

  final _roms = <String, RomGame>{};
  bool importing = false;
  String importStatus = '';
  double importProgress = 0;

  Future<void> load() async {
    for (final r in await _dao.all()) {
      _roms[r.id] = r;
    }
    notifyListeners();
  }

  List<RomGame> bySystem(String system) {
    final list = _roms.values.where((r) => r.system == system).toList()
      ..sort((a, b) {
        final la = a.lastPlayed?.millisecondsSinceEpoch ?? 0;
        final lb = b.lastPlayed?.millisecondsSinceEpoch ?? 0;
        if (la != lb) return lb.compareTo(la);
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return list;
  }

  static bool get canImport => Platform.isAndroid;

  // --- Importação ----------------------------------------------------------------

  Future<ImportReport> pickAndImport(EmulatorDef emu, {bool folder = false}) async {
    final picked = folder ? await NativeBridge.pickRomFolder(emu.extensions) : await NativeBridge.pickRomFiles();
    return importPicked(emu, picked);
  }

  /// [picked]: `[{uri, name, size}]` vindos do seletor do sistema.
  Future<ImportReport> importPicked(EmulatorDef emu, List<Map<String, dynamic>> picked) async {
    final report = ImportReport();
    final files = <Map<String, dynamic>>[];
    for (final f in picked) {
      final name = '${f['name']}';
      if (emu.accepts(name)) {
        files.add(f);
      } else {
        report.failures.add('$name: formato não suportado (${emu.extensions.join(', ')})');
      }
    }
    if (files.isEmpty) return report;

    importing = true;
    importProgress = 0;
    notifyListeners();
    try {
      for (var i = 0; i < files.length; i++) {
        final f = files[i];
        final uri = '${f['uri']}';
        final name = '${f['name']}';
        importStatus = 'Lendo $name (${i + 1}/${files.length})';
        importProgress = i / files.length;
        notifyListeners();

        final id = '${emu.system}:${sha1.convert(utf8.encode(uri)).toString().substring(0, 16)}';
        if (_roms.containsKey(id)) {
          report.duplicates++;
          continue;
        }
        final rom = RomGame(
          id: id,
          system: emu.system,
          name: cleanFileName(name),
          uri: uri,
          fileName: name,
          size: (f['size'] as num?)?.toInt(),
        );
        try {
          await identify(rom);
        } catch (e) {
          // Sem Title ID o jogo ainda abre no emulador; só fica sem capa.
          appLog.w('ROMs', 'Não foi possível identificar $name', e);
        }
        _roms[id] = rom;
        await _dao.upsert(rom);
        report.added++;
        notifyListeners();
      }
    } finally {
      importing = false;
      importStatus = '';
      importProgress = 1;
      notifyListeners();
    }
    appLog.i('ROMs', 'Importação: ${report.summary}');
    return report;
  }

  /// "Halo 3 (USA) (En,Fr).iso" → "Halo 3".
  static String cleanFileName(String name) => name
      .replaceAll(RegExp(r'\.[A-Za-z0-9]{2,4}$'), '')
      .replaceAll(RegExp(r'\s*[\(\[][^\)\]]*[\)\]]'), '')
      .replaceAll('_', ' ')
      .trim();

  RandomReader _reader(String uri) => uri.startsWith('content://') ? ContentUriReader(uri) : FileRandomReader(uri);

  /// Title ID → nome oficial → capa. ISOs comprimidos (.zar) não têm o XEX
  /// legível, então buscam pelo nome do arquivo.
  Future<void> identify(RomGame rom) async {
    if (rom.fileName.toLowerCase().endsWith('.iso')) {
      final reader = _reader(rom.uri);
      try {
        final info = await XisoReader.readTitleInfo(reader);
        if (info.isValid) {
          rom
            ..titleId = info.titleId
            ..mediaId = info.mediaId
            ..discNumber = info.discNumber
            ..discCount = info.discCount;
        }
      } finally {
        await reader.close();
      }
    }

    if (rom.titleId != null) {
      final official = await _unity.titleName(rom.titleId!);
      if (official != null && official.isNotEmpty) rom.name = official;
    } else {
      final want = ArtworkService.normalize(rom.name);
      for (final t in await _unity.search(rom.name)) {
        if (ArtworkService.normalize(t.name) == want) {
          rom
            ..titleId = t.titleId
            ..name = t.name;
          break;
        }
      }
    }
    await _pickDefaultCover(rom);
  }

  Future<void> _pickDefaultCover(RomGame rom) async {
    final tid = rom.titleId;
    if (tid == null) return;
    final covers = await _unity.covers(tid);
    if (covers.isNotEmpty) {
      rom
        ..coverUrl = covers.first.largeUrl
        ..coverId = covers.first.id;
    } else {
      rom
        ..coverUrl = XboxUnity.marketplaceBoxart(tid)
        ..coverId = null;
    }
  }

  // --- Capas (seletor estilo Aurora) ------------------------------------------------

  Future<List<XboxCover>> coverOptions(RomGame rom) async =>
      rom.titleId == null ? const [] : _unity.covers(rom.titleId!);

  Future<void> setCover(RomGame rom, XboxCover cover) async {
    rom
      ..coverUrl = cover.largeUrl
      ..coverId = cover.id;
    await _dao.upsert(rom);
    notifyListeners();
  }

  Future<void> useMarketplaceCover(RomGame rom) async {
    if (rom.titleId == null) return;
    rom
      ..coverUrl = XboxUnity.marketplaceBoxart(rom.titleId!)
      ..coverId = null;
    await _dao.upsert(rom);
    notifyListeners();
  }

  /// Refaz a identificação (ex.: estava sem internet ao importar).
  Future<void> reidentify(RomGame rom) async {
    await identify(rom);
    await _dao.upsert(rom);
    notifyListeners();
  }

  Future<void> remove(RomGame rom) async {
    _roms.remove(rom.id);
    await _dao.delete(rom.id);
    if (rom.uri.startsWith('content://') && !_roms.values.any((r) => r.uri == rom.uri)) {
      try {
        await NativeBridge.releaseUri(rom.uri);
      } catch (_) {}
    }
    notifyListeners();
  }

  // --- Jogar ----------------------------------------------------------------------------

  /// Abre o jogo no emulador. Retorna `null` ou o motivo da falha.
  Future<String?> launch(EmulatorDef emu, RomGame rom) async {
    if (!Platform.isAndroid) return '${emu.name} roda apenas no Android.';
    final installed = await NativeBridge.installedVersion(emu.androidPackage);
    if (installed == null) return 'Instale o ${emu.name} primeiro.';
    if (!await NativeBridge.canReadUri(rom.uri)) {
      return 'O arquivo não está mais acessível (movido ou apagado). Remova e importe de novo.';
    }
    final err = await NativeBridge.launchEmulatorGame(
      package: emu.androidPackage,
      activity: emu.androidActivity,
      uri: rom.uri,
      action: emu.launchAction,
    );
    if (err != null) return err;
    rom
      ..lastPlayed = DateTime.now()
      ..sessions += 1;
    await _dao.upsert(rom);
    notifyListeners();
    appLog.i('ROMs', 'Abrindo ${rom.name} (${rom.titleId ?? 'sem Title ID'}) no ${emu.name}');
    return null;
  }
}
