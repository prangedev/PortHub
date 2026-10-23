import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../core/app_config.dart';
import '../core/formatters.dart';
import '../database/cache_dao.dart';
import '../github/github_client.dart';
import '../services/game_actions.dart';
import '../services/hardware/hardware_service.dart';
import '../services/install_service.dart';
import '../services/library_service.dart';
import '../services/providers/game_source_provider.dart';
import '../services/self_update_service.dart';
import '../services/settings_service.dart';
import '../ui/theme.dart';
import '../widgets/focusable.dart';
import 'logs_page.dart';
import 'navigation.dart';

/// Configurações avançadas.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsService>();
    final lib = context.watch<LibraryService>();
    final gh = context.read<GitHubClient>();
    final providers = context.read<List<GameSourceProvider>>();
    final pad = PH.compact(context) ? 16.0 : 48.0;

    return ListView(padding: EdgeInsets.fromLTRB(pad, 24, pad, 40), children: [
      Text('Configurações', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 20),
      const _SelfUpdateGroup(),
      _Group('GitHub', [
        _TextTile(
          autofocus: true,
          icon: Icons.key_rounded,
          title: 'Token pessoal do GitHub',
          subtitle: s.githubToken.isEmpty
              ? 'Opcional. Sem token: 60 req/h. Com token: 5000 req/h e issues fixadas.'
              : 'Configurado (${s.githubToken.substring(0, s.githubToken.length.clamp(0, 6))}…)',
          value: s.githubToken,
          obscure: true,
          onSave: (v) => s.githubToken = v,
        ),
        _InfoTile(
          icon: Icons.speed_rounded,
          title: 'Rate limit',
          value: gh.rateRemaining == null ? 'Ainda não consultado' : '${gh.rateRemaining} restantes · renova ${timeAgoFuture(gh.rateReset)}',
        ),
        _TextTile(
          icon: Icons.dns_rounded,
          title: 'Backend de cache (opcional)',
          subtitle: s.cacheProxyUrl.isEmpty ? 'Acesso direto à API do GitHub' : s.cacheProxyUrl,
          value: s.cacheProxyUrl,
          hint: 'http://192.168.0.10:8787',
          onSave: (v) => s.cacheProxyUrl = v,
        ),
        _SwitchTile(icon: Icons.science_rounded, title: 'Incluir pré-lançamentos', value: s.includePrereleases, onChanged: (v) => s.includePrereleases = v),
      ]),
      _Group('Biblioteca', [
        _ActionTile(
          icon: Icons.sync_rounded,
          title: lib.refreshing ? 'Sincronizando… ${(lib.refreshProgress * 100).round()}%' : 'Sincronizar agora',
          subtitle: 'Última: ${s.lastLibraryRefresh == null ? 'nunca' : timeAgo(s.lastLibraryRefresh)}',
          onTap: lib.refreshing ? null : lib.refresh,
        ),
        _SwitchTile(icon: Icons.update_rounded, title: 'Atualização automática da biblioteca', value: s.autoRefresh, onChanged: (v) => s.autoRefresh = v),
        _ChoiceTile(
          icon: Icons.schedule_rounded,
          title: 'Intervalo de atualização',
          value: s.refreshIntervalHours,
          options: const [1, 3, 6, 12, 24, 72],
          label: (v) => v < 24 ? '$v h' : '${v ~/ 24} dia(s)',
          onChanged: (v) => s.refreshIntervalHours = v,
        ),
        _SwitchTile(icon: Icons.cloud_off_rounded, title: 'Modo offline', subtitle: 'Usa apenas dados em cache', value: s.offlineMode, onChanged: (v) => s.offlineMode = v),
        _SwitchTile(icon: Icons.block_rounded, title: 'Mostrar jogos incompatíveis', value: s.showIncompatible, onChanged: (v) => s.showIncompatible = v),
        _SwitchTile(icon: Icons.notifications_active_rounded, title: 'Notificar atualizações', value: s.notifyUpdates, onChanged: (v) => s.notifyUpdates = v),
        _ActionTile(
          icon: Icons.playlist_add_check_rounded,
          title: 'Importar jogos já instalados',
          subtitle: Platform.isAndroid ? 'Procura apps instalados que estão no catálogo' : 'Lê a pasta de jogos do PortHub',
          onTap: () async {
            final n = await context.read<GameActions>().importInstalled();
            if (context.mounted) showMessage(context, '$n jogo(s) importado(s)');
          },
        ),
      ]),
      _Group('Provedores', [
        for (final p in providers)
          _SwitchTile(
            icon: Icons.extension_rounded,
            title: p.displayName,
            subtitle: p.description,
            value: lib.isProviderEnabled(p),
            onChanged: (v) => s.setProviderEnabled(p.id, v),
          ),
        _TextTile(
          icon: Icons.link_rounded,
          title: 'URL da lista JSON comunitária',
          subtitle: s.communityCatalogUrl.isEmpty ? 'Usando o catálogo embarcado' : s.communityCatalogUrl,
          value: s.communityCatalogUrl,
          hint: 'https://raw.githubusercontent.com/<usuario>/porthub/main/assets/catalog/community.json',
          onSave: (v) => s.communityCatalogUrl = v,
        ),
      ]),
      _Group('Downloads e instalação', [
        _ChoiceTile(
          icon: Icons.layers_rounded,
          title: 'Downloads simultâneos',
          value: s.maxConcurrentDownloads,
          options: const [1, 2, 3, 4, 6],
          label: (v) => '$v',
          onChanged: (v) => s.maxConcurrentDownloads = v,
        ),
        _SwitchTile(icon: Icons.verified_user_rounded, title: 'Verificar integridade (SHA256/MD5)', value: s.verifyChecksums, onChanged: (v) => s.verifyChecksums = v),
        _SwitchTile(icon: Icons.install_desktop_rounded, title: 'Instalar automaticamente após baixar', value: s.autoInstall, onChanged: (v) => s.autoInstall = v),
        _SwitchTile(icon: Icons.cleaning_services_rounded, title: 'Apagar arquivo baixado após instalar', value: s.deleteAfterInstall, onChanged: (v) => s.deleteAfterInstall = v),
        if (!Platform.isAndroid)
          _TextTile(
            icon: Icons.folder_rounded,
            title: 'Pasta de jogos',
            subtitle: s.installDir.isEmpty ? 'Padrão (dados do aplicativo)' : s.installDir,
            value: s.installDir,
            onSave: (v) => s.installDir = v,
          ),
      ]),
      _Group('Comunidade', [
        _TextTile(
          icon: Icons.groups_rounded,
          title: 'PortHub Compatibility Database',
          subtitle: s.communityDbUrl.isEmpty ? 'Desativada — informe a URL do servidor (ver /backend)' : s.communityDbUrl,
          value: s.communityDbUrl,
          hint: 'http://localhost:8787',
          onSave: (v) => s.communityDbUrl = v,
        ),
      ]),
      _Group('IA local (opcional)', [
        _SwitchTile(
          icon: Icons.auto_awesome_rounded,
          title: 'Resumir READMEs longos com IA local',
          subtitle: 'Servidor compatível com a API do Ollama',
          value: s.aiSummaries,
          onChanged: (v) => s.aiSummaries = v,
        ),
        _TextTile(icon: Icons.computer_rounded, title: 'URL do servidor', subtitle: s.ollamaUrl, value: s.ollamaUrl, onSave: (v) => s.ollamaUrl = v),
        _TextTile(icon: Icons.psychology_rounded, title: 'Modelo', subtitle: s.ollamaModel, value: s.ollamaModel, onSave: (v) => s.ollamaModel = v),
      ]),
      _Group('Interface', [
        _SwitchTile(
          icon: Icons.fullscreen_rounded,
          title: 'Tela cheia',
          subtitle: Platform.isAndroid ? 'Modo imersivo' : 'F11 alterna a qualquer momento',
          value: s.fullscreen,
          onChanged: (v) async {
            s.fullscreen = v;
            if (Platform.isAndroid) {
              await SystemChrome.setEnabledSystemUIMode(v ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
            } else {
              await windowManager.setFullScreen(v);
            }
          },
        ),
      ]),
      _Group('Manutenção', [
        _ActionTile(icon: Icons.memory_rounded, title: 'Reanalisar hardware', onTap: () => context.read<HardwareService>().scan()),
        _ActionTile(
          icon: Icons.delete_sweep_rounded,
          title: 'Limpar cache (GitHub e imagens)',
          onTap: () async {
            final n = await context.read<CacheDao>().clear();
            await DefaultCacheManagerHolder.clear();
            if (context.mounted) showMessage(context, '$n respostas removidas do cache');
          },
        ),
        _ActionTile(
          icon: Icons.folder_open_rounded,
          title: 'Pasta de jogos',
          subtitle: 'Mostra o caminho atual',
          onTap: () async {
            final dir = await context.read<InstallService>().gamesDir();
            if (context.mounted) showMessage(context, dir.path);
          },
        ),
        _ActionTile(
          icon: Icons.receipt_long_rounded,
          title: 'Logs do sistema',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LogsPage())),
        ),
        const _InfoTile(icon: Icons.info_outline_rounded, title: AppConfig.appName, value: 'Versão ${AppConfig.appVersion} · open source (MIT)'),
      ]),
    ]);
  }

  static String timeAgoFuture(DateTime? d) {
    if (d == null) return '—';
    final m = d.difference(DateTime.now()).inMinutes;
    return m <= 0 ? 'agora' : 'em $m min';
  }
}

/// Acesso ao cache de imagens do cached_network_image.
class DefaultCacheManagerHolder {
  static Future<void> clear() async {
    try {
      await CachedNetworkImageProvider.defaultCacheManager.emptyCache();
    } catch (_) {}
  }
}

class _Group extends StatelessWidget {
  const _Group(this.title, this.children);
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 22),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(title.toUpperCase(), style: const TextStyle(color: PH.textFaint, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
            ),
            Container(
              decoration: BoxDecoration(color: PH.surface, borderRadius: BorderRadius.circular(PH.radius)),
              child: Column(children: children),
            ),
          ]),
        ),
      );
}

class _TileFrame extends StatelessWidget {
  const _TileFrame({required this.icon, required this.title, this.subtitle, this.trailing, this.onTap, this.autofocus = false});
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Focusable(
        autofocus: autofocus,
        glow: false,
        focusScale: 1.0,
        borderRadius: PH.radius,
        onActivate: onTap,
        builder: (context, focused) => Container(
          color: focused ? PH.surfaceHi : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(children: [
            Icon(icon, color: focused ? PH.accent : PH.textDim),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: PH.textDim, fontSize: 13)),
                  ),
              ]),
            ),
            ?trailing,
          ]),
        ),
      );
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({required this.icon, required this.title, required this.value, required this.onChanged, this.subtitle});
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => _TileFrame(
        icon: icon,
        title: title,
        subtitle: subtitle,
        onTap: () => onChanged(!value),
        trailing: ExcludeFocus(child: Switch(value: value, onChanged: onChanged)),
      );
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.title, this.subtitle, this.onTap});
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => _TileFrame(
        icon: icon,
        title: title,
        subtitle: subtitle,
        onTap: onTap,
        trailing: const Icon(Icons.chevron_right_rounded, color: PH.textFaint),
      );
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.icon, required this.title, required this.value});
  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) => _TileFrame(icon: icon, title: title, subtitle: value);
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({required this.icon, required this.title, required this.value, required this.options, required this.label, required this.onChanged});
  final IconData icon;
  final String title;
  final int value;
  final List<int> options;
  final String Function(int) label;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => _TileFrame(
        icon: icon,
        title: title,
        subtitle: 'Atual: ${label(value)} — pressione para alternar',
        onTap: () {
          final i = options.indexOf(value);
          onChanged(options[(i + 1) % options.length]);
        },
        trailing: Text(label(value), style: const TextStyle(fontWeight: FontWeight.w800, color: PH.accentSoft)),
      );
}

class _TextTile extends StatelessWidget {
  const _TextTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onSave,
    this.subtitle,
    this.hint,
    this.obscure = false,
    this.autofocus = false,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final String value;
  final String? hint;
  final bool obscure;
  final bool autofocus;
  final ValueChanged<String> onSave;

  @override
  Widget build(BuildContext context) => _TileFrame(
        icon: icon,
        title: title,
        subtitle: subtitle,
        autofocus: autofocus,
        trailing: const Icon(Icons.edit_rounded, color: PH.textFaint, size: 20),
        onTap: () async {
          final ctrl = TextEditingController(text: value);
          final r = await showDialog<String>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(title),
              content: SizedBox(
                width: 520,
                child: TextField(
                  controller: ctrl,
                  autofocus: true,
                  obscureText: obscure,
                  decoration: InputDecoration(hintText: hint),
                  onSubmitted: (v) => Navigator.pop(ctx, v),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
                TextButton(onPressed: () => Navigator.pop(ctx, ''), child: const Text('Limpar')),
                FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Salvar')),
              ],
            ),
          );
          ctrl.dispose();
          if (r != null) onSave(r);
        },
      );
}

/// Atualizações do próprio PortHub (releases do repositório do app).
class _SelfUpdateGroup extends StatelessWidget {
  const _SelfUpdateGroup();

  @override
  Widget build(BuildContext context) {
    final up = context.watch<SelfUpdateService>();
    final s = context.watch<SettingsService>();
    if (!up.enabled) {
      return _Group('Atualizações do PortHub', [
        _InfoTile(
          icon: Icons.system_update_rounded,
          title: 'Versão ${up.currentLabel}',
          value: AppConfig.updateRepo.isEmpty
              ? 'Build local: a atualização automática vale para os APKs gerados pelo GitHub Actions.'
              : 'Atualização automática disponível no Android.',
        ),
      ]);
    }
    final rel = up.latest;
    final busy = up.status == SelfUpdateState.downloading || up.status == SelfUpdateState.installing;
    final subtitle = switch (up.status) {
      SelfUpdateState.checking => 'Verificando…',
      SelfUpdateState.upToDate => 'Você está na versão mais recente (${rel?.tag}).',
      SelfUpdateState.available => '${rel!.tag} disponível · ${formatBytes(rel.size)}${rel.publishedAt != null ? ' · ${timeAgo(rel.publishedAt!)}' : ''}',
      SelfUpdateState.downloading => 'Baixando ${(up.progress * 100).round()}%…',
      SelfUpdateState.installing => 'Abrindo o instalador…',
      SelfUpdateState.error => up.error ?? 'Erro',
      _ => up.lastCheck == null ? 'Ainda não verificado' : 'Verificado ${timeAgo(up.lastCheck!)}',
    };
    return _Group('Atualizações do PortHub', [
      _TileFrame(
        icon: up.updateAvailable ? Icons.system_update_rounded : Icons.verified_rounded,
        title: up.updateAvailable ? 'Atualizar para ${rel!.tag}' : 'Versão ${up.currentLabel}',
        subtitle: subtitle,
        onTap: busy
            ? null
            : () async {
                if (!up.updateAvailable) return up.check(manual: true);
                final err = await up.downloadAndInstall();
                if (err != null && context.mounted) showMessage(context, err, error: true);
              },
        trailing: busy
            ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, value: up.status == SelfUpdateState.downloading ? up.progress : null))
            : Text(up.updateAvailable ? 'Atualizar' : 'Verificar', style: const TextStyle(color: PH.accent, fontWeight: FontWeight.w800)),
      ),
      _SwitchTile(
        icon: Icons.schedule_rounded,
        title: 'Verificar automaticamente',
        subtitle: 'Ao abrir o app e a cada 6 horas · ${AppConfig.updateRepo}',
        value: s.selfUpdateCheck,
        onChanged: (v) => s.selfUpdateCheck = v,
      ),
    ]);
  }
}
