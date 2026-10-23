import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/formatters.dart';
import '../core/models/hardware_profile.dart';
import '../core/platform_info.dart';
import '../services/hardware/hardware_service.dart';
import '../services/library_service.dart';
import '../services/settings_service.dart';
import '../ui/app_shell.dart';
import '../ui/theme.dart';
import '../widgets/ph_button.dart';

/// Primeira execução: análise completa do dispositivo com animação de etapas
/// e resumo final antes de entrar no launcher.
class FirstRunPage extends StatefulWidget {
  const FirstRunPage({super.key});

  @override
  State<FirstRunPage> createState() => _FirstRunPageState();
}

class _FirstRunPageState extends State<FirstRunPage> {
  static const _steps = [
    'Identificando o dispositivo',
    'Lendo processador e arquitetura',
    'Detectando GPU, Vulkan e OpenGL',
    'Medindo memória e armazenamento',
    'Verificando tela e taxa de atualização',
  ];
  int _done = 0;
  HardwareProfile? _hw;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 520), (t) {
      if (_done < _steps.length - 1) setState(() => _done++);
    });
    // scan() notifica ouvintes na hora; fora do build evita setState durante build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  Future<void> _scan() async {
    final hw = await context.read<HardwareService>().scan();
    // Garante que a animação termine antes do resumo.
    await Future.delayed(const Duration(milliseconds: 600));
    _timer?.cancel();
    if (mounted) {
      setState(() {
        _done = _steps.length;
        _hw = hw;
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _continue() {
    context.read<SettingsService>().firstRunDone = true;
    context.read<LibraryService>().startAutoRefresh();
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 500),
      pageBuilder: (_, _, _) => const AppShell(),
      transitionsBuilder: (_, a, _, c) => FadeTransition(opacity: a, child: c),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final hw = _hw;
    final steps = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      const Row(children: [
        Icon(Icons.hub_rounded, color: PH.accent, size: 44),
        SizedBox(width: 14),
        Text('PORTHUB', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: 5)),
      ]),
      const SizedBox(height: 10),
      const Text('Analisando seu dispositivo para indicar quais ports rodam bem nele.',
          style: TextStyle(color: PH.textDim, fontSize: 16)),
      const SizedBox(height: 32),
      for (var i = 0; i < _steps.length; i++)
        AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          opacity: i <= _done ? 1 : 0.35,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(children: [
              SizedBox(
                width: 24,
                height: 24,
                child: i < _done
                    ? const Icon(Icons.check_circle_rounded, color: PH.green)
                    : i == _done
                        ? const CircularProgressIndicator(strokeWidth: 2.5)
                        : const Icon(Icons.radio_button_unchecked_rounded, color: PH.textFaint),
              ),
              const SizedBox(width: 14),
              Flexible(child: Text(_steps[i], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
            ]),
          ),
        ),
    ]);
    final summary = AnimatedSize(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      child: hw == null
          ? const SizedBox(height: 24, width: double.infinity)
          : Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: PH.surface, borderRadius: BorderRadius.circular(PH.radiusLg)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(hw.deviceLabel, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                _kv('CPU', hw.cpuName ?? hw.socModel ?? '—'),
                _kv('GPU', hw.gpuName ?? '—'),
                _kv('RAM', formatRamMb(hw.ramMb)),
                _kv('Arquitetura', archLabel(hw.primaryArch)),
                _kv(platformLabel(hw.platform), hw.platform == 'linux' ? (hw.distro ?? '—') : (hw.osVersion ?? '—')),
                _kv('Vulkan', hw.vulkan ? 'Suportado ${hw.vulkanVersion ?? ''}' : 'Não suportado'),
                const SizedBox(height: 20),
                PHButton(
                  label: 'Entrar no PortHub',
                  icon: Icons.arrow_forward_rounded,
                  gradient: PH.installGradient,
                  autofocus: true,
                  onPressed: _continue,
                ),
              ]),
            ),
    );
    // Telas largas (celular deitado, desktop): passos e resumo lado a lado,
    // para o botão de continuar caber sem rolar.
    final wide = MediaQuery.sizeOf(context).width >= 860;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(center: Alignment(-0.6, -0.7), radius: 1.4, colors: [Color(0xFF12324F), PH.bg]),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: wide ? 1100 : 640),
              child: wide
                  ? Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                      Expanded(child: steps),
                      const SizedBox(width: 40),
                      Expanded(child: summary),
                    ])
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      steps,
                      if (hw != null) const SizedBox(height: 28),
                      summary,
                    ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          SizedBox(width: 120, child: Text(k, style: const TextStyle(color: PH.textDim))),
          Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w700))),
        ]),
      );
}
