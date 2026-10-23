import '../core/models/game_requirements.dart';

/// Extração "inteligente" de informações do README: imagens (galeria),
/// descrição curta, requisitos, engine, categorias e tags.
class ReadmeParser {
  static final _mdImage = RegExp(r'!\[[^\]]*\]\(\s*<?([^)\s>]+)>?(?:\s+"[^"]*")?\s*\)');
  static final _htmlImage = RegExp(r'''<img[^>]+src\s*=\s*["']([^"']+)["']''', caseSensitive: false);

  static const _badgeHints = [
    'shields.io', 'badge', 'badgen', 'travis-ci', 'circleci', 'appveyor', 'codecov', 'coveralls',
    '/workflows/', '/actions/', 'liberapay', 'ko-fi', 'patreon', 'paypal', 'discordapp.com/api',
    'discord.com/api', 'opencollective', 'repology', 'f-droid.org/badge', 'play.google.com/intl',
    'buymeacoffee', 'sonarcloud', 'codefactor', 'weblate', 'hosted.weblate', 'flathub.org/assets/badges',
    'get-it-on', 'snapcraft.io/static', 'translate', 'stars.svg', 'gitter',
  ];

  /// Imagens do README (sem badges/SVG), com URLs relativas resolvidas.
  static List<String> images(String markdown, String rawBase) {
    final urls = <String>[];
    for (final m in [..._mdImage.allMatches(markdown), ..._htmlImage.allMatches(markdown)]) {
      var url = m.group(1)!.trim();
      final lower = url.toLowerCase();
      if (_badgeHints.any(lower.contains)) continue;
      if (lower.endsWith('.svg') || lower.contains('.svg?')) continue;
      if (!url.startsWith('http')) {
        if (rawBase.isEmpty) continue;
        url = Uri.parse(rawBase).resolve(url.replaceFirst(RegExp(r'^\./'), '')).toString();
      }
      // Links "blob" do GitHub não são imagens diretas.
      url = url.replaceFirstMapped(
        RegExp(r'^https://github\.com/([^/]+)/([^/]+)/blob/(.+)$'),
        (m) => 'https://raw.githubusercontent.com/${m[1]}/${m[2]}/${m[3]}',
      );
      if (!urls.contains(url)) urls.add(url);
    }
    return urls;
  }

  /// Remove marcação para obter texto puro.
  static String plainText(String markdown) {
    var s = markdown;
    s = s.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
    s = s.replaceAll(RegExp(r'```[\s\S]*?```'), '');
    s = s.replaceAll(RegExp(r'<[^>]+>'), ' ');
    s = s.replaceAll(_mdImage, '');
    s = s.replaceAllMapped(RegExp(r'\[([^\]]*)\]\([^)]*\)'), (m) => m[1] ?? '');
    s = s.replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '');
    s = s.replaceAll(RegExp(r'[*_`>|]'), '');
    s = s.replaceAll(RegExp(r'&nbsp;'), ' ');
    s = s.replaceAll(RegExp(r'[ \t]+'), ' ');
    return s.trim();
  }

  /// Primeiro parágrafo significativo do README (descrição curta).
  static String shortDescription(String markdown, {int maxLen = 320}) {
    final paragraphs = plainText(markdown)
        .split(RegExp(r'\n\s*\n'))
        .map((p) => p.replaceAll('\n', ' ').trim())
        .where((p) => p.length > 40 && !p.startsWith('-') && !RegExp(r'^(table of contents|índice|contents)', caseSensitive: false).hasMatch(p));
    final first = paragraphs.isEmpty ? '' : paragraphs.first;
    if (first.length <= maxLen) return first;
    final cut = first.substring(0, maxLen);
    final dot = cut.lastIndexOf('. ');
    return dot > 120 ? cut.substring(0, dot + 1) : '$cut…';
  }

  /// Heurísticas de requisitos no texto do README (prioridade mais baixa).
  static GameRequirements requirements(String markdown) {
    final t = plainText(markdown);
    final lower = t.toLowerCase();

    int? ram;
    final ramM = RegExp(r'(\d+(?:[.,]\d+)?)\s*(gb|gib|mb|mib)\s*(?:of\s+)?(?:ram|memory|de ram|memória)', caseSensitive: false)
        .firstMatch(t);
    if (ramM != null) ram = GameRequirements.parseSizeMb('${ramM[1]}${ramM[2]}');

    double? android;
    final andM = RegExp(
      r'android\s*(\d+(?:\.\d+)?)\s*(?:\+|or\s+(?:higher|newer|later|above)|and\s+(?:up|above|newer)|ou\s+superior)',
      caseSensitive: false,
    ).firstMatch(t);
    final andM2 = RegExp(r'(?:requires|minimum|min\.?|requer|mínimo)\s*(?:is\s*)?android\s*(\d+(?:\.\d+)?)', caseSensitive: false)
        .firstMatch(t);
    android = double.tryParse((andM ?? andM2)?.group(1) ?? '');

    bool? vulkan;
    if (RegExp(r'(requires?|need(?:s|ed)?|requer|necessita|mandatory)[^.\n]{0,40}vulkan', caseSensitive: false).hasMatch(t) ||
        RegExp(r'vulkan[^.\n]{0,20}(required|is needed|obrigatório)', caseSensitive: false).hasMatch(t)) {
      vulkan = true;
    }

    final gles = RegExp(r'opengl\s*es\s*(\d\.\d)', caseSensitive: false).firstMatch(t);
    final gl = RegExp(r'opengl\s*(?!es)(\d\.\d)', caseSensitive: false).firstMatch(t);
    final dx = RegExp(r'directx\s*(\d{1,2})', caseSensitive: false).firstMatch(t);

    final archs = <String>[];
    if (RegExp(r'(arm64|aarch64|64-bit)\s*(only|devices only|apenas)', caseSensitive: false).hasMatch(lower)) {
      archs.add('arm64');
    }

    final r = GameRequirements(
      minRamMb: ram,
      minAndroid: android,
      vulkan: vulkan,
      minGlEs: double.tryParse(gles?.group(1) ?? ''),
      minOpenGl: double.tryParse(gl?.group(1) ?? ''),
      minDirectX: int.tryParse(dx?.group(1) ?? ''),
      architectures: archs,
      sources: const ['README'],
    );
    return r.isEmpty ? const GameRequirements() : r;
  }

  static const _engines = <String, String>{
    'godot': 'Godot',
    'unity': 'Unity',
    'unreal': 'Unreal Engine',
    'libgdx': 'libGDX',
    'love2d': 'LÖVE',
    'löve': 'LÖVE',
    'raylib': 'raylib',
    'monogame': 'MonoGame',
    'fna': 'FNA',
    'defold': 'Defold',
    'cocos2d': 'Cocos2d',
    'bevy': 'Bevy',
    'irrlicht': 'Irrlicht',
    'xash3d': 'Xash3D (GoldSrc)',
    'gzdoom': 'GZDoom',
    'id tech': 'id Tech',
    'quake engine': 'Quake Engine',
    'sfml': 'SFML',
    'sdl2': 'SDL2',
    'sdl3': 'SDL3',
    'ogre': 'OGRE',
    'panda3d': 'Panda3D',
    'pygame': 'Pygame',
    'renpy': "Ren'Py",
    "ren'py": "Ren'Py",
    'gamemaker': 'GameMaker',
    'openra': 'OpenRA',
  };

  /// Detecta a engine pelos tópicos e pelo texto do README.
  static String? engine(List<String> topics, String markdown, String? language) {
    final lowerTopics = topics.map((t) => t.toLowerCase()).toList();
    for (final e in _engines.entries) {
      if (lowerTopics.any((t) => t.replaceAll('-', ' ').contains(e.key))) return e.value;
    }
    final lower = markdown.toLowerCase();
    for (final e in _engines.entries) {
      if (RegExp('(built|made|written|powered|developed|uses|using|feito|construído)[^.\\n]{0,40}${RegExp.escape(e.key)}')
          .hasMatch(lower)) {
        return e.value;
      }
    }
    if (lower.contains('sdl2') || lower.contains('libsdl')) return 'SDL2';
    return null;
  }

  static const _categoryHints = <String, List<String>>{
    'RPG': ['rpg', 'roguelike', 'roguelite', 'dungeon', 'jrpg', 'arpg', 'role-playing'],
    'Ação': ['action', 'hack-and-slash', 'beat-em-up', 'fighting', 'sandbox', 'adventure'],
    'FPS': ['fps', 'first-person-shooter', 'shooter', 'quake', 'doom'],
    'Corrida': ['racing', 'kart', 'racer', 'driving'],
    'Plataforma': ['platformer', 'platform-game', 'metroidvania', 'jump-and-run'],
    'Estratégia': ['strategy', 'rts', 'turn-based', '4x', 'tower-defense', 'city-builder', 'tactics'],
    'Terror': ['horror', 'survival-horror', 'zombie', 'survival'],
    'Puzzle': ['puzzle', 'sudoku', 'minesweeper', 'tetris', 'match-3', 'sokoban'],
  };

  static List<String> categories(List<String> topics, String text) {
    final lowerTopics = topics.map((t) => t.toLowerCase()).toSet();
    final lowerText = text.toLowerCase();
    final result = <String>[];
    for (final e in _categoryHints.entries) {
      if (e.value.any(lowerTopics.contains) || e.value.any((h) => RegExp('\\b${RegExp.escape(h)}\\b').hasMatch(lowerText))) {
        result.add(e.key);
      }
    }
    return result;
  }

  /// Tags especiais: Offline / Multiplayer / Open Source.
  static List<String> tags(List<String> topics, String text, {required bool openSource}) {
    final lower = '${topics.join(' ')} ${text.toLowerCase()}';
    final tags = <String>[];
    if (RegExp(r'\b(multiplayer|multi-player|online|co-?op|netplay|lan)\b').hasMatch(lower)) tags.add('Multiplayer');
    if (RegExp(r'\b(single[- ]?player|offline|campaign)\b').hasMatch(lower)) tags.add('Offline');
    if (openSource) tags.add('Open Source');
    return tags;
  }
}
