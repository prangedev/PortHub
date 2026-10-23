import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:porthub/emulators/xbox/xiso_reader.dart';

/// Arquivo "esparso": só os trechos escritos existem, o resto é zero. Permite
/// simular ISOs de vários GB sem alocar a memória.
class SparseReader extends RandomReader {
  SparseReader(this.size);
  final int size;
  final _chunks = <int, Uint8List>{};

  void write(int offset, List<int> bytes) => _chunks[offset] = Uint8List.fromList(bytes);

  @override
  Future<int> length() async => size;

  @override
  Future<Uint8List> read(int offset, int count) async {
    final out = Uint8List(count.clamp(0, size - offset));
    _chunks.forEach((start, data) {
      for (var i = 0; i < data.length; i++) {
        final pos = start + i - offset;
        if (pos >= 0 && pos < out.length) out[pos] = data[i];
      }
    });
    return out;
  }
}

/// Monta um XISO mínimo: volume, diretório raiz com dois arquivos e um
/// default.xex com o bloco de execução.
SparseReader buildIso({required int partition, String titleId = '4D5307E6', int disc = 1, int discs = 2}) {
  const sector = XisoReader.sector;
  final r = SparseReader(partition + 400 * sector);

  final volume = BytesBuilder()
    ..add(ascii.encode('MICROSOFT*XBOX*MEDIA'))
    ..add(_le32(40)) // setor do diretório raiz
    ..add(_le32(sector)); // tamanho do diretório
  r.write(partition + 32 * sector, volume.toBytes());

  // Diretório: "media" na raiz, "default.xex" à direita (offset em dwords).
  Uint8List entry(int left, int right, int start, int size, String name) {
    final b = BytesBuilder()
      ..add(_le16(left))
      ..add(_le16(right))
      ..add(_le32(start))
      ..add(_le32(size))
      ..addByte(0x10)
      ..addByte(name.length)
      ..add(latin1.encode(name));
    while (b.length % 4 != 0) {
      b.addByte(0xFF);
    }
    return b.toBytes();
  }

  final first = entry(0, 0, 50, sector, 'media');
  final second = entry(0, 0, 60, 4096, 'Default.XEX');
  final firstWithRight = entry(0, first.length ~/ 4, 50, sector, 'media');
  r.write(partition + 40 * sector, [...firstWithRight, ...second]);

  // XEX2: 1 cabeçalho opcional apontando para as informações de execução.
  final xex = BytesBuilder()
    ..add(ascii.encode('XEX2'))
    ..add(_be32(0))
    ..add(_be32(0x3000))
    ..add(_be32(0))
    ..add(_be32(0x100))
    ..add(_be32(1))
    ..add(_be32(0x00040006))
    ..add(_be32(0x200));
  r.write(partition + 60 * sector, xex.toBytes());
  final exec = BytesBuilder()
    ..add(_be32(0xA1B2C3D4)) // media id
    ..add(_be32(0x00010002))
    ..add(_be32(0))
    ..add(_be32(int.parse(titleId, radix: 16)))
    ..addByte(0)
    ..addByte(0)
    ..addByte(disc)
    ..addByte(discs)
    ..add(_be32(0));
  r.write(partition + 60 * sector + 0x200, exec.toBytes());
  return r;
}

List<int> _le16(int v) => [v & 0xFF, (v >> 8) & 0xFF];
List<int> _le32(int v) => [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];
List<int> _be32(int v) => [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];

void main() {
  test('lê Title ID de ISO reconstruído (partição no início)', () async {
    final info = await XisoReader.readTitleInfo(buildIso(partition: 0));
    expect(info.titleId, '4D5307E6');
    expect(info.mediaId, 'A1B2C3D4');
    expect(info.discNumber, 1);
    expect(info.discCount, 2);
    expect(info.publisherCode, 'MS');
    expect(info.isValid, isTrue);
  });

  test('acha a partição de jogo de uma cópia XGD2 completa', () async {
    final info = await XisoReader.readTitleInfo(buildIso(partition: 0xFD90000, titleId: '454107D9'));
    expect(info.titleId, '454107D9');
    expect(info.publisherCode, 'EA');
  });

  test('rejeita arquivo que não é XISO', () async {
    final r = MemoryRandomReader(Uint8List(200 * 1024));
    expect(() => XisoReader.readTitleInfo(r), throwsA(isA<XisoException>()));
  });

  test('Title ID zerado não é válido', () {
    expect(const XboxTitleInfo(titleId: '00000000').isValid, isFalse);
  });
}
