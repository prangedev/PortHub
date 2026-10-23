import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../achievements/achievement_service.dart';
import '../achievements/ra_models.dart';
import '../core/formatters.dart';
import '../ui/theme.dart';
import '../widgets/badges.dart';
import '../widgets/focusable.dart';
import '../widgets/ph_button.dart';

/// Aba Conquistas: conta do RetroAchievements, desbloqueios em tempo real e
/// progresso por jogo.
class AchievementsPage extends StatelessWidget {
  const AchievementsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ra = context.watch<AchievementService>();
    return ra.loggedIn ? const _Dashboard() : const _Login();
  }
}

// ---------------------------------------------------------------------------
// Login
// ---------------------------------------------------------------------------

class _Login extends StatefulWidget {
  const _Login();

  @override
  State<_Login> createState() => _LoginState();
}

class _LoginState extends State<_Login> {
  final _user = TextEditingController();
  final _key = TextEditingController();
  bool _showKey = false;
  String? _error;

  @override
  void dispose() {
    _user.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final err = await context.read<AchievementService>().login(_user.text, _key.text);
    if (mounted) setState(() => _error = err);
  }

  InputDecoration _field(String label, IconData icon, {Widget? suffix}) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        suffixIcon: suffix,
        filled: true,
        fillColor: PH.surfaceHi,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(PH.radius), borderSide: BorderSide.none),
      );

  @override
  Widget build(BuildContext context) {
    final ra = context.watch<AchievementService>();
    final pad = PH.compact(context) ? 16.0 : 48.0;
    return ListView(padding: EdgeInsets.fromLTRB(pad, 24, pad, 40), children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(PH.radiusLg),
              gradient: const LinearGradient(colors: [Color(0xFF2A2310), PH.surface]),
              border: Border.all(color: PH.stroke),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.emoji_events_rounded, color: PH.yellow, size: 40),
                SizedBox(width: 14),
                Expanded(
                  child: Text('Conquistas com RetroAchievements',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                ),
              ]),
              const SizedBox(height: 10),
              const Text(
                'Conecte sua conta para ver pontos, conquistas e o progresso de cada jogo. Com o app aberto, '
                'cada conquista que você desbloquear no emulador aparece aqui em tempo real.',
                style: TextStyle(color: PH.textDim, height: 1.4),
              ),
              const SizedBox(height: 22),
              TextField(
                controller: _user,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                decoration: _field('Usuário do RetroAchievements', Icons.person_rounded),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _key,
                obscureText: !_showKey,
                autocorrect: false,
                enableSuggestions: false,
                onSubmitted: (_) => _submit(),
                decoration: _field(
                  'Chave da Web API',
                  Icons.key_rounded,
                  suffix: IconButton(
                    tooltip: _showKey ? 'Ocultar' : 'Mostrar',
                    icon: Icon(_showKey ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                    onPressed: () => setState(() => _showKey = !_showKey),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: PH.red, fontWeight: FontWeight.w700)),
              ],
              const SizedBox(height: 18),
              Wrap(spacing: 12, runSpacing: 12, children: [
                // Foco inicial no botão: focar o campo abriria o teclado e cobriria a tela.
                PHButton(
                  label: ra.loading ? 'Conectando…' : 'Entrar',
                  icon: Icons.login_rounded,
                  gradient: PH.installGradient,
                  autofocus: true,
                  onPressed: ra.loading ? null : _submit,
                ),
                PHButton(
                  label: 'Onde encontro a chave?',
                  icon: Icons.open_in_new_rounded,
                  onPressed: () => launchUrl(Uri.parse('$raSite/settings'), mode: LaunchMode.externalApplication),
                ),
              ]),
              const SizedBox(height: 16),
              const Text(
                'A chave fica em retroachievements.org › Settings › Keys (Web API Key). Ela é salva só neste '
                'aparelho e serve apenas para ler seus dados — não permite alterar sua conta.',
                style: TextStyle(color: PH.textFaint, fontSize: 12.5, height: 1.4),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Painel
// ---------------------------------------------------------------------------

class _Dashboard extends StatelessWidget {
  const _Dashboard();

  @override
  Widget build(BuildContext context) {
    final ra = context.watch<AchievementService>();
    final pad = PH.compact(context) ? 16.0 : 48.0;
    final p = ra.profile;
    if (p == null) {
      return Center(
        child: ra.error != null
            ? Column(mainAxisSize: MainAxisSize.min, children: [
                Text(ra.error!, style: const TextStyle(color: PH.red)),
                const SizedBox(height: 12),
                PHButton(label: 'Tentar de novo', icon: Icons.refresh_rounded, autofocus: true, onPressed: ra.refresh),
              ])
            : const CircularProgressIndicator(),
      );
    }
    return RefreshIndicator(
      onRefresh: ra.refresh,
      child: ListView(padding: EdgeInsets.fromLTRB(pad, 20, pad, 40), children: [
        _ProfileHeader(profile: p),
        const SizedBox(height: 26),
        _SectionTitle(Icons.bolt_rounded, 'Desbloqueadas recentemente', '${ra.recent.length} nos últimos 30 dias'),
        const SizedBox(height: 12),
        if (ra.recent.isEmpty)
          const _Empty('Nenhuma conquista nos últimos 30 dias. Jogue com o RetroAchievements ativo no emulador.')
        else
          SizedBox(
            height: 132,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: ra.recent.length.clamp(0, 30),
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, i) => _UnlockCard(unlock: ra.recent[i]),
            ),
          ),
        const SizedBox(height: 26),
        _SectionTitle(Icons.sports_esports_rounded, 'Jogos recentes', null),
        const SizedBox(height: 12),
        if (ra.recentGames.isEmpty)
          const _Empty('Nenhum jogo recente.')
        else
          SizedBox(
            height: 270,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: ra.recentGames.length,
              separatorBuilder: (_, _) => const SizedBox(width: 16),
              itemBuilder: (context, i) => _RecentGameCard(game: ra.recentGames[i]),
            ),
          ),
        if (ra.achievementOfWeek != null && ra.achievementOfWeek!.title.isNotEmpty) ...[
          const SizedBox(height: 26),
          _SectionTitle(Icons.calendar_month_rounded, 'Conquista da semana', null),
          const SizedBox(height: 12),
          _WeekCard(aotw: ra.achievementOfWeek!, user: ra.user),
        ],
      ]),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.profile});
  final RaProfile profile;

  @override
  Widget build(BuildContext context) {
    final ra = context.watch<AchievementService>();
    final p = profile;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(PH.radiusLg),
        gradient: const LinearGradient(colors: [Color(0xFF2A2310), PH.surface]),
        border: Border.all(color: PH.stroke),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: CachedNetworkImage(
              imageUrl: p.userPic,
              width: 76,
              height: 76,
              fit: BoxFit.cover,
              errorWidget: (_, _, _) => const ColoredBox(color: PH.surfaceHi, child: Icon(Icons.person_rounded, size: 40)),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 10, runSpacing: 6, children: [
                Text(p.user, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                if (p.rank != null) TagPill('#${p.rank} no ranking', icon: Icons.leaderboard_rounded, color: PH.yellow),
                _LiveChip(ra: ra),
              ]),
              if (p.motto.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('“${p.motto}”', style: const TextStyle(color: PH.textDim, fontStyle: FontStyle.italic)),
              ],
              if (p.richPresence.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.play_circle_fill_rounded, size: 16, color: PH.green),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(p.richPresence,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: PH.textDim, fontSize: 13)),
                  ),
                ]),
              ],
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        Wrap(spacing: 12, runSpacing: 12, children: [
          _Stat('Pontos (hardcore)', p.points, PH.yellow),
          _Stat('Pontos softcore', p.softcorePoints, PH.textDim),
          _Stat('RetroPoints', p.truePoints, PH.accentSoft),
        ]),
        const SizedBox(height: 16),
        Wrap(spacing: 12, runSpacing: 12, children: [
          PHButton(
            label: ra.loading ? 'Atualizando…' : 'Atualizar',
            icon: Icons.refresh_rounded,
            autofocus: true,
            onPressed: ra.loading ? null : ra.refresh,
          ),
          PHButton(
            label: ra.live ? 'Tempo real: ligado' : 'Tempo real: desligado',
            icon: ra.live ? Icons.sensors_rounded : Icons.sensors_off_rounded,
            onPressed: () => ra.setLive(!ra.settings.raLive),
          ),
          PHButton(
            label: 'Perfil no site',
            icon: Icons.open_in_new_rounded,
            onPressed: () => launchUrl(Uri.parse('$raSite/user/${p.user}'), mode: LaunchMode.externalApplication),
          ),
          PHButton(label: 'Sair', icon: Icons.logout_rounded, onPressed: ra.logout),
        ]),
        if (ra.error != null) ...[
          const SizedBox(height: 10),
          Text(ra.error!, style: const TextStyle(color: PH.red)),
        ],
      ]),
    );
  }
}

/// Indicador "ao vivo": pisca enquanto acompanha os desbloqueios.
class _LiveChip extends StatefulWidget {
  const _LiveChip({required this.ra});
  final AchievementService ra;

  @override
  State<_LiveChip> createState() => _LiveChipState();
}

class _LiveChipState extends State<_LiveChip> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ra = widget.ra;
    final synced = ra.lastSync == null ? '' : ' · ${timeAgo(ra.lastSync!)}';
    if (!ra.live) return TagPill('Tempo real desligado$synced', icon: Icons.sensors_off_rounded);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: PH.red.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        FadeTransition(
          opacity: Tween(begin: 0.35, end: 1.0).animate(_pulse),
          child: const Icon(Icons.circle, size: 9, color: PH.red),
        ),
        const SizedBox(width: 6),
        Text('AO VIVO$synced', style: const TextStyle(color: PH.red, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.color);
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(color: PH.surfaceHi, borderRadius: BorderRadius.circular(PH.radius)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(_thousands(value), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color)),
          Text(label, style: const TextStyle(color: PH.textDim, fontSize: 12)),
        ]),
      );
}

String _thousands(int v) => v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.icon, this.title, this.subtitle);
  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 20, color: PH.yellow),
        const SizedBox(width: 10),
        Text(title.toUpperCase(), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 1.6)),
        if (subtitle != null) ...[
          const SizedBox(width: 12),
          Flexible(child: Text(subtitle!, overflow: TextOverflow.ellipsis, style: const TextStyle(color: PH.textDim, fontSize: 13))),
        ],
      ]);
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text, style: const TextStyle(color: PH.textFaint));
}

class _Badge extends StatelessWidget {
  const _Badge(this.url, {this.size = 64});
  final String url;
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: (_, _) => Container(width: size, height: size, color: PH.surfaceHi),
          errorWidget: (_, _, _) => Container(
            width: size,
            height: size,
            color: PH.surfaceHi,
            child: const Icon(Icons.emoji_events_rounded, color: PH.textFaint),
          ),
        ),
      );
}

class _UnlockCard extends StatelessWidget {
  const _UnlockCard({required this.unlock});
  final RaUnlock unlock;

  @override
  Widget build(BuildContext context) {
    final u = unlock;
    return Focusable(
      onActivate: () => openRaGame(context, u.gameId, u.gameTitle),
      builder: (context, focused) => Container(
        width: 320,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: PH.surface, borderRadius: BorderRadius.circular(PH.radius)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _Badge(u.badgeUrl),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(u.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(u.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: PH.textDim, fontSize: 12)),
              const Spacer(),
              Row(children: [
                Text('${u.points} pts', style: const TextStyle(color: PH.yellow, fontWeight: FontWeight.w800, fontSize: 12)),
                if (u.hardcore) ...[
                  const SizedBox(width: 6),
                  const Text('HC', style: TextStyle(color: PH.red, fontWeight: FontWeight.w900, fontSize: 11)),
                ],
                const SizedBox(width: 8),
                Expanded(
                  child: Text('${u.gameTitle} · ${u.date == null ? '' : timeAgo(u.date!)}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: PH.textFaint, fontSize: 11.5)),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _RecentGameCard extends StatelessWidget {
  const _RecentGameCard({required this.game});
  final RaRecentGame game;

  @override
  Widget build(BuildContext context) {
    final g = game;
    const w = 150.0;
    return SizedBox(
      width: w,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Focusable(
          onActivate: () => openRaGame(context, g.id, g.title),
          builder: (context, focused) => ClipRRect(
            borderRadius: BorderRadius.circular(PH.radius),
            child: SizedBox(
              width: w,
              height: 180,
              child: Stack(fit: StackFit.expand, children: [
                CachedNetworkImage(
                  imageUrl: g.boxArt ?? g.icon ?? '',
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => const ColoredBox(color: PH.surfaceHi, child: Icon(Icons.sports_esports_rounded)),
                ),
                if (g.total > 0)
                  Positioned(left: 8, right: 8, bottom: 8, child: PHProgress(value: g.completion, height: 5, color: PH.yellow)),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(g.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
        Text(
          g.total == 0 ? g.consoleName : '${g.earned}/${g.total} · ${(g.completion * 100).round()}% · ${g.consoleName}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: PH.textDim, fontSize: 12),
        ),
      ]),
    );
  }
}

class _WeekCard extends StatelessWidget {
  const _WeekCard({required this.aotw, required this.user});
  final RaAchievementOfWeek aotw;
  final String user;

  @override
  Widget build(BuildContext context) {
    final mine = aotw.unlockedBy.contains(user.toLowerCase());
    return Focusable(
      onActivate: () => openRaGame(context, aotw.gameId, aotw.gameTitle),
      builder: (context, focused) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: PH.surface, borderRadius: BorderRadius.circular(PH.radius)),
        child: Row(children: [
          _Badge(aotw.badgeUrl, size: 80),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(aotw.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                TagPill('${aotw.points} pts', color: PH.yellow),
                if (mine) const TagPill('Você já tem', color: PH.green, icon: Icons.check_circle_rounded),
              ]),
              const SizedBox(height: 4),
              Text(aotw.description, style: const TextStyle(color: PH.textDim)),
              const SizedBox(height: 6),
              Text(
                '${aotw.gameTitle} · ${aotw.consoleName} · ${aotw.unlocks} de ${aotw.totalPlayers} jogadores desbloquearam',
                style: const TextStyle(color: PH.textFaint, fontSize: 12.5),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Página do jogo
// ---------------------------------------------------------------------------

Future<void> openRaGame(BuildContext context, int gameId, String title) => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RaGamePage(gameId: gameId, title: title)),
    );

class RaGamePage extends StatefulWidget {
  const RaGamePage({super.key, required this.gameId, required this.title});
  final int gameId;
  final String title;

  @override
  State<RaGamePage> createState() => _RaGamePageState();
}

class _RaGamePageState extends State<RaGamePage> {
  late Future<RaGameProgress> _future = context.read<AchievementService>().gameProgress(widget.gameId);

  void _reload() =>
      setState(() => _future = context.read<AchievementService>().gameProgress(widget.gameId, force: true));

  @override
  Widget build(BuildContext context) {
    final pad = PH.compact(context) ? 16.0 : 48.0;
    return Scaffold(
      backgroundColor: PH.bg,
      body: FutureBuilder<RaGameProgress>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${snap.error}', style: const TextStyle(color: PH.red)),
                const SizedBox(height: 12),
                PHButton(label: 'Tentar de novo', icon: Icons.refresh_rounded, autofocus: true, onPressed: _reload),
              ]),
            );
          }
          final g = snap.data;
          if (g == null) return const Center(child: CircularProgressIndicator());
          return ListView(padding: EdgeInsets.fromLTRB(pad, 20, pad, 40), children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              PHIconButton(icon: Icons.arrow_back_rounded, tooltip: 'Voltar', onPressed: () => Navigator.of(context).maybePop()),
              const SizedBox(width: 16),
              if (g.boxArt != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(PH.radius),
                  child: CachedNetworkImage(imageUrl: g.boxArt!, width: 110, height: 150, fit: BoxFit.cover),
                ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(g.title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text([g.consoleName, ?g.developer, ?g.genre].join(' · '), style: const TextStyle(color: PH.textDim)),
                  const SizedBox(height: 14),
                  Text(
                    '${g.earned} de ${g.achievements.length} conquistas · ${g.earnedPoints} de ${g.totalPoints} pontos'
                    '${g.earnedHardcore > 0 ? ' · ${g.earnedHardcore} hardcore' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: PHProgress(value: g.completion, height: 8, color: PH.yellow),
                  ),
                  const SizedBox(height: 12),
                  PHButton(label: 'Atualizar', icon: Icons.refresh_rounded, dense: true, autofocus: true, onPressed: _reload),
                ]),
              ),
            ]),
            const SizedBox(height: 24),
            if (g.achievements.isEmpty)
              const _Empty('Este jogo ainda não tem conquistas.')
            else
              for (final a in g.achievements) _AchievementRow(a: a, players: g.players),
          ]);
        },
      ),
    );
  }
}

class _AchievementRow extends StatelessWidget {
  const _AchievementRow({required this.a, required this.players});
  final RaGameAchievement a;
  final int players;

  @override
  Widget build(BuildContext context) {
    final when = a.earnedHardcore ?? a.earned;
    final rarity = players == 0 ? null : (a.numAwarded * 100 / players);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Focusable(
        glow: false,
        focusScale: 1.0,
        builder: (context, focused) => Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: focused ? PH.surfaceHi : PH.surface,
            borderRadius: BorderRadius.circular(PH.radius),
          ),
          child: Opacity(
            opacity: a.unlocked ? 1 : 0.6,
            child: Row(children: [
              _Badge(a.badgeUrl(), size: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(a.description, style: const TextStyle(color: PH.textDim, fontSize: 13)),
                ]),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${a.points} pts', style: const TextStyle(color: PH.yellow, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(
                  when != null
                      ? '${a.earnedHardcore != null ? 'Hardcore · ' : ''}${formatDate(when)}'
                      : rarity == null
                          ? 'Bloqueada'
                          : '${rarity.toStringAsFixed(rarity < 10 ? 1 : 0)}% dos jogadores',
                  style: TextStyle(color: when != null ? PH.green : PH.textFaint, fontSize: 12),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
