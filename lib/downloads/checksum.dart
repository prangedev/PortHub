import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

import '../core/logger.dart';
import '../core/models/release_info.dart';
import '../github/github_client.dart';

/// Verificação de integridade (SHA256 ou MD5).
class Checksum {
  /// Calcula o hash do arquivo em um isolate (não trava a interface).
  static Future<String> hashFile(String path, String algorithm) => Isolate.run(() async {
        final hash = algorithm == 'md5' ? md5 : sha256;
        final digest = await hash.bind(File(path).openRead()).first;
        return digest.toString();
      });

  /// Retorna true se o arquivo confere com [expected] (`sha256:<hex>` ou `md5:<hex>`).
  static Future<bool> verify(String path, String expected) async {
    final parts = expected.split(':');
    if (parts.length != 2) return true;
    final actual = await hashFile(path, parts[0]);
    final ok = actual.toLowerCase() == parts[1].toLowerCase();
    appLog.i('Checksum', '${parts[0]} ${ok ? 'OK' : 'DIVERGENTE'} para $path');
    return ok;
  }

  /// Procura o hash de [asset]: primeiro no próprio asset (campo `digest` da
  /// API), depois em arquivos `SHA256SUMS`, `checksums.txt` ou `<nome>.sha256`
  /// publicados na mesma release.
  static Future<String?> resolve(ReleaseInfo? release, ReleaseAsset asset, GitHubClient gh) async {
    if (asset.checksum != null) return asset.checksum;
    if (release == null) return null;
    final candidates = release.checksumAssets.where((c) {
      final n = c.name.toLowerCase();
      return n.contains('sha256') || n.contains('checksum') || n == '${asset.name.toLowerCase()}.sha256';
    });
    for (final c in candidates) {
      try {
        final text = await gh.rawText(c.url, ttl: const Duration(days: 30));
        final hex = parse(text, asset.name);
        if (hex != null) return 'sha256:$hex';
      } catch (e) {
        appLog.w('Checksum', 'Não foi possível ler ${c.name}', e);
      }
    }
    return null;
  }

  /// Lê formatos "hash  arquivo" (sha256sum) ou só "hash".
  static String? parse(String text, String fileName) {
    final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    final re = RegExp(r'^([a-fA-F0-9]{64})\s+\*?(.+)$');
    for (final l in lines) {
      final m = re.firstMatch(l);
      if (m != null && m[2]!.trim().split('/').last == fileName) return m[1]!.toLowerCase();
    }
    if (lines.length == 1 && RegExp(r'^[a-fA-F0-9]{64}').hasMatch(lines.first)) {
      return lines.first.substring(0, 64).toLowerCase();
    }
    return null;
  }
}
