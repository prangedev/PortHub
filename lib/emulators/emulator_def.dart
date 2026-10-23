import 'package:flutter/material.dart';

/// Um console suportado pela aba Emuladores e o emulador que roda seus jogos.
///
/// O emulador em si vem do catálogo ([catalogId]) e é instalado/atualizado
/// como qualquer port; aqui fica o que é específico dele: como abrir um jogo
/// e quais arquivos ele aceita.
class EmulatorDef {
  const EmulatorDef({
    required this.system,
    required this.systemName,
    required this.name,
    required this.catalogId,
    required this.androidPackage,
    required this.androidActivity,
    required this.extensions,
    required this.description,
    required this.icon,
    required this.accent,
    this.launchAction = 'android.intent.action.VIEW',
    this.coverAspect = 0.71,
  });

  /// Chave do console nas ROMs importadas (ex.: `x360`).
  final String system;
  final String systemName;
  final String name;

  /// Id do emulador no catálogo (`gh:owner/repo`).
  final String catalogId;
  final String androidPackage;

  /// Activity que recebe o jogo pela `data` da intent.
  final String androidActivity;
  final String launchAction;

  /// Extensões aceitas na importação (minúsculas, com ponto).
  final List<String> extensions;
  final String description;
  final IconData icon;
  final Color accent;

  /// Proporção largura/altura da frente da capa (estojo de Xbox 360 ≈ 0,71).
  final double coverAspect;

  bool accepts(String fileName) => extensions.any((e) => fileName.toLowerCase().endsWith(e));
}

/// Xbox 360 → XenDroid (Xenia Edge para Android, github.com/rfandango/XenDroid).
const xbox360 = EmulatorDef(
  system: 'x360',
  systemName: 'Xbox 360',
  name: 'XenDroid',
  catalogId: 'gh:rfandango/xendroid',
  androidPackage: 'xendroid.compose',
  androidActivity: 'xendroid.compose.EmulatorHostActivity',
  extensions: ['.iso', '.zar'],
  description: 'Emulador de Xbox 360 para Android baseado no Xenia Edge (Vulkan). '
      'Importe seus ISOs: o PortHub lê o Title ID do disco e busca a capa no XboxUnity, como o Aurora.',
  icon: Icons.sports_esports_rounded,
  accent: Color(0xFF6CC24A),
);

const emulators = [xbox360];

EmulatorDef? emulatorForSystem(String system) {
  for (final e in emulators) {
    if (e.system == system) return e;
  }
  return null;
}
