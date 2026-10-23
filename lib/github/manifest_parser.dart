import 'package:yaml/yaml.dart';

import '../core/logger.dart';
import '../core/models/game_requirements.dart';

/// Arquivo opcional `porthub.yaml` na raiz do repositório. É a forma "oficial"
/// de um porter declarar requisitos e metadados para o PortHub:
///
/// ```yaml
/// name: Meu Port
/// category: [RPG, Ação]
/// engine: SDL2
/// android_package: org.exemplo.meuport
/// tags: [Offline]
/// cover: https://.../capa.png
/// banner: https://.../banner.jpg
/// requirements:
///   ram: 4GB
///   architecture: arm64-v8a
///   android: 10+
///   vulkan: true
///   gles: 3.2
///   gpu: mid
/// ```
class PortHubManifest {
  const PortHubManifest({
    this.name,
    this.requirements,
    this.categories = const [],
    this.tags = const [],
    this.engine,
    this.androidPackage,
    this.cover,
    this.banner,
    this.icon,
    this.description,
  });

  final String? name;
  final GameRequirements? requirements;
  final List<String> categories;
  final List<String> tags;
  final String? engine;
  final String? androidPackage;
  final String? cover;
  final String? banner;
  final String? icon;
  final String? description;

  static const fileNames = ['porthub.yaml', 'porthub.yml', '.porthub.yaml', '.porthub.yml'];

  static PortHubManifest? parse(String text) {
    try {
      final doc = loadYaml(text);
      if (doc is! Map) return null;
      final m = _plain(doc) as Map<String, dynamic>;
      List<String> list(dynamic v) => v == null ? const [] : (v is List ? v.map((e) => '$e').toList() : ['$v']);
      final req = m['requirements'];
      return PortHubManifest(
        name: m['name'] as String?,
        requirements: req is Map ? GameRequirements.fromMap(req, source: 'porthub.yaml') : null,
        categories: list(m['category'] ?? m['categories']),
        tags: list(m['tags']),
        engine: m['engine']?.toString(),
        androidPackage: m['android_package']?.toString(),
        cover: m['cover']?.toString(),
        banner: m['banner']?.toString(),
        icon: m['icon']?.toString(),
        description: m['description']?.toString(),
      );
    } catch (e) {
      appLog.w('Manifest', 'porthub.yaml inválido', e);
      return null;
    }
  }

  static dynamic _plain(dynamic v) {
    if (v is Map) return v.map((k, val) => MapEntry('$k', _plain(val)));
    if (v is List) return v.map(_plain).toList();
    return v;
  }
}
