import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Leitura aleatória de um arquivo grande (ISO de vários GB) sem carregá-lo
/// na memória. No Android a implementação lê um `content://` pelo canal nativo.
abstract class RandomReader {
  Future<int> length();
  Future<Uint8List> read(int offset, int count);
  Future<void> close() async {}
}

class FileRandomReader extends RandomReader {
  FileRandomReader(String path) : _raf = File(path).openSync();
  final RandomAccessFile _raf;

  @override
  Future<int> length() => _raf.length();

  @override
  Future<Uint8List> read(int offset, int count) async {
    await _raf.setPosition(offset);
    return _raf.read(count);
  }

  @override
  Future<void> close() => _raf.close();
}

class MemoryRandomReader extends RandomReader {
  MemoryRandomReader(this.bytes);
  final Uint8List bytes;

  @override
  Future<int> length() async => bytes.length;

  @override
  Future<Uint8List> read(int offset, int count) async {
    if (offset >= bytes.length) return Uint8List(0);
    final end = (offset + count).clamp(0, bytes.length);
    return Uint8List.sublistView(bytes, offset, end);
  }
}

/// Dados de identificação de um jogo de Xbox 360, lidos do `default.xex`.
class XboxTitleInfo {
  const XboxTitleInfo({
    required this.titleId,
    this.mediaId,
    this.version,
    this.discNumber = 0,
    this.discCount = 0,
  });

  /// 8 dígitos hexadecimais em maiúsculas (ex.: `4D5307E6` = Halo 3).
  final String titleId;
  final String? mediaId;
  final int? version;
  final int discNumber;
  final int discCount;

  /// IDs zerados ou de homebrew genérico não identificam o jogo.
  bool get isValid => titleId != '00000000' && titleId != 'FFFFFFFF';

  /// Editora codificada nos 2 primeiros bytes (ex.: `4D53` = "MS", `4541` = "EA").
  String get publisherCode {
    final a = int.parse(titleId.substring(0, 2), radix: 16);
    final b = int.parse(titleId.substring(2, 4), radix: 16);
    bool printable(int c) => c >= 0x20 && c < 0x7F;
    return printable(a) && printable(b) ? String.fromCharCodes([a, b]) : titleId.substring(0, 4);
  }
}

class XisoException implements Exception {
  XisoException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Leitor do sistema de arquivos XDVDFS (discos de Xbox/Xbox 360) e do
/// cabeçalho XEX2. Só lê o mínimo necessário para achar o Title ID — o mesmo
/// que o Aurora usa para buscar capas.
class XisoReader {
  static const sector = 2048;
  static const _magic = 'MICROSOFT*XBOX*MEDIA';

  /// Onde a partição de jogo pode começar: ISO reconstruído (0), XGD3, XGD2 e
  /// XGD1 (cópias completas do disco incluem a partição de vídeo antes).
  static const partitionOffsets = [0, 0x2080000, 0xFD90000, 0x18300000];

  static const _xexExecutionInfo = 0x00040006;

  static Future<XboxTitleInfo> readTitleInfo(RandomReader r) async {
    final total = await r.length();
    for (final base in partitionOffsets) {
      final volume = base + 32 * sector;
      if (volume + sector > total) continue;
      final head = await r.read(volume, 28);
      if (head.length < 28 || ascii.decode(head.sublist(0, 20), allowInvalid: true) != _magic) continue;
      final bd = ByteData.sublistView(head);
      final rootSector = bd.getUint32(20, Endian.little);
      final rootSize = bd.getUint32(24, Endian.little);
      final xex = await _findFile(r, base, rootSector, rootSize, 'default.xex');
      if (xex == null) throw XisoException('O disco não tem default.xex (não é um jogo de Xbox 360).');
      return _parseXex(r, base + xex.$1 * sector, xex.$2);
    }
    throw XisoException('Não é uma imagem de disco de Xbox 360 (XISO).');
  }

  /// Procura [name] na árvore binária do diretório. Retorna (setor, tamanho).
  static Future<(int, int)?> _findFile(RandomReader r, int base, int dirSector, int dirSize, String name) async {
    if (dirSize <= 0 || dirSize > 16 * 1024 * 1024) return null;
    final table = await r.read(base + dirSector * sector, dirSize);
    final bd = ByteData.sublistView(table);
    final wanted = name.toLowerCase();
    final pending = <int>[0];
    final seen = <int>{};
    while (pending.isNotEmpty) {
      final off = pending.removeLast();
      if (!seen.add(off) || off + 14 > table.length) continue;
      final left = bd.getUint16(off, Endian.little);
      final right = bd.getUint16(off + 2, Endian.little);
      if (left == 0xFFFF && right == 0xFFFF && bd.getUint32(off + 4, Endian.little) == 0xFFFFFFFF) continue;
      final start = bd.getUint32(off + 4, Endian.little);
      final size = bd.getUint32(off + 8, Endian.little);
      final nameLen = table[off + 13];
      if (off + 14 + nameLen > table.length) continue;
      final entryName = latin1.decode(table.sublist(off + 14, off + 14 + nameLen));
      if (entryName.toLowerCase() == wanted) return (start, size);
      if (left != 0 && left != 0xFFFF) pending.add(left * 4);
      if (right != 0 && right != 0xFFFF) pending.add(right * 4);
    }
    return null;
  }

  static Future<XboxTitleInfo> _parseXex(RandomReader r, int xexOffset, int xexSize) async {
    final header = await r.read(xexOffset, 24);
    if (header.length < 24 || ascii.decode(header.sublist(0, 4), allowInvalid: true) != 'XEX2') {
      throw XisoException('default.xex inválido (sem assinatura XEX2).');
    }
    final hd = ByteData.sublistView(header);
    final count = hd.getUint32(20, Endian.big);
    if (count > 256) throw XisoException('Cabeçalho XEX corrompido.');
    final table = await r.read(xexOffset + 24, count * 8);
    final td = ByteData.sublistView(table);
    for (var i = 0; i + 8 <= table.length; i += 8) {
      if (td.getUint32(i, Endian.big) != _xexExecutionInfo) continue;
      final at = td.getUint32(i + 4, Endian.big);
      if (at + 24 > xexSize) break;
      final info = ByteData.sublistView(await r.read(xexOffset + at, 24));
      String hex(int v) => v.toRadixString(16).toUpperCase().padLeft(8, '0');
      return XboxTitleInfo(
        mediaId: hex(info.getUint32(0, Endian.big)),
        version: info.getUint32(4, Endian.big),
        titleId: hex(info.getUint32(12, Endian.big)),
        discNumber: info.getUint8(18),
        discCount: info.getUint8(19),
      );
    }
    throw XisoException('default.xex sem informações de execução (Title ID).');
  }
}
