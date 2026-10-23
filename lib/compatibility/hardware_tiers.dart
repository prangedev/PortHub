import '../core/models/hardware_profile.dart';

/// Estimativa de desempenho (0–100) de CPU e GPU a partir do nome do chip.
///
/// É uma tabela heurística, não um benchmark: serve para comparar com o nível
/// mínimo que um jogo declara (`cpu: mid`, `gpu: high`...). Contribuições com
/// novos chips são bem-vindas.
class HardwareTiers {
  /// Retorna (pontuação, foiReconhecido).
  static (int, bool) cpuTier(HardwareProfile hw) {
    final name = '${hw.socModel ?? ''} ${hw.cpuName ?? ''}'.toLowerCase();

    // ---- Android SoCs --------------------------------------------------------
    final snap = RegExp(r'snapdragon\s*(\d)\s*(?:\+\s*)?gen\s*(\d)|snapdragon\s*(\d{3})').firstMatch(name);
    if (name.contains('8 elite') || name.contains('8elite')) return (98, true);
    if (snap != null) {
      if (snap[2] != null) {
        final series = int.parse(snap[1]!);
        final gen = int.parse(snap[2]!);
        return (switch (series) { 8 => 86 + gen * 3, 7 => 66 + gen * 4, 6 => 48 + gen * 4, _ => 30 + gen * 3 }.clamp(0, 100), true);
      }
      final n = int.parse(snap[3] ?? '0');
      return (_snapdragonNumber(n), true);
    }
    final sm = RegExp(r'\bsm(\d)(\d{3})').firstMatch(name); // Build.SOC_MODEL: SM7325, SM8550...
    if (sm != null) {
      final series = int.parse(sm[1]!);
      final rev = int.parse(sm[2]!);
      final base = switch (series) { 8 => 80, 7 => 62, 6 => 45, 4 => 28, _ => 35 };
      return ((base + (rev ~/ 100) * 3).clamp(0, 100), true);
    }
    final dim = RegExp(r'dimensity\s*(\d{3,4})').firstMatch(name);
    if (dim != null) {
      final n = int.parse(dim[1]!);
      return (n >= 9000 ? 92 : n >= 8000 ? 80 : n >= 7000 ? 64 : n >= 1000 ? 72 : 55, true);
    }
    final helio = RegExp(r'helio\s*([gpax])\s*(\d{2,3})').firstMatch(name);
    if (helio != null) {
      final n = int.parse(helio[2]!);
      return (helio[1] == 'g' ? (n >= 90 ? 50 : n >= 80 ? 44 : 35) : 30, true);
    }
    final mt = RegExp(r'\bmt(\d{4})').firstMatch(name);
    if (mt != null) {
      final n = int.parse(mt[1]!);
      return (n >= 6983 ? 85 : n >= 6877 ? 68 : n >= 6785 ? 50 : 32, true);
    }
    final exy = RegExp(r'exynos\s*(\d{3,4})').firstMatch(name);
    if (exy != null) {
      final n = int.parse(exy[1]!);
      return (n >= 2100 ? 85 : n >= 1380 ? 62 : n >= 990 ? 60 : n >= 9810 ? 50 : 40, true);
    }
    if (name.contains('tensor')) return (name.contains('g4') || name.contains('g5') ? 88 : 82, true);
    if (name.contains('unisoc') || name.contains('spreadtrum') || name.contains('tiger') || name.contains(' ums')) {
      return (25, true);
    }
    if (name.contains('kirin')) return (name.contains('9') ? 70 : 45, true);

    // ---- Desktop -------------------------------------------------------------
    if (name.contains('ryzen')) {
      final g = RegExp(r'ryzen\s*(?:ai\s*)?(\d)\s*(?:pro\s*)?(\d)(\d{2,3})').firstMatch(name);
      if (g != null) {
        final cls = int.parse(g[1]!);
        final gen = int.parse(g[2]!);
        return ((40 + cls * 5 + gen * 4).clamp(30, 100), true);
      }
      return (70, true);
    }
    final intel = RegExp(r'\bi([3579])[- ](\d{4,5})').firstMatch(name);
    if (intel != null) {
      final cls = int.parse(intel[1]!);
      final model = intel[2]!;
      final gen = int.parse(model.length == 5 ? model.substring(0, 2) : model.substring(0, 1));
      return ((25 + cls * 4 + gen * 3).clamp(20, 100), true);
    }
    if (RegExp(r'core\s*ultra').hasMatch(name)) return (88, true);
    if (name.contains('celeron') || name.contains('pentium') || name.contains('atom')) return (22, true);
    if (name.contains('apple m')) return (92, true);

    // ---- Fallback: núcleos ---------------------------------------------------
    final threads = hw.cpuThreads ?? hw.cpuCores ?? 0;
    final fallback = threads >= 16 ? 85 : threads >= 8 ? 65 : threads >= 4 ? 45 : 25;
    return (fallback, false);
  }

  static int _snapdragonNumber(int n) {
    if (n >= 888) return 86;
    if (n >= 855) return 80;
    if (n >= 835) return 68;
    if (n >= 800) return 55;
    if (n >= 780) return 70; // 778G, 780G
    if (n >= 765) return 62;
    if (n >= 720) return 56;
    if (n >= 700) return 50;
    if (n >= 660) return 44;
    if (n >= 600) return 36;
    return 24;
  }

  static (int, bool) gpuTier(HardwareProfile hw) {
    final g = (hw.gpuName ?? '').toLowerCase();
    if (g.isEmpty) return (hw.vulkan ? 50 : 35, false);

    final adreno = RegExp(r'adreno\D*(\d{3})').firstMatch(g);
    if (adreno != null) {
      final n = int.parse(adreno[1]!);
      if (n >= 800) return (98, true);
      if (n >= 730) return (94, true);
      if (n >= 700) return (n >= 720 ? 80 : 70, true);
      if (n >= 660) return (86, true);
      if (n >= 650) return (82, true);
      if (n >= 640) return (72, true); // 642L, 643, 644
      if (n >= 618) return (56, true);
      if (n >= 610) return (44, true);
      if (n >= 540) return (60, true);
      if (n >= 500) return (36, true);
      return (20, true);
    }
    if (g.contains('immortalis') || g.contains('xclipse')) return (88, true);
    final mali = RegExp(r'mali-?\s*g(\d{2,3})').firstMatch(g);
    if (mali != null) {
      final n = int.parse(mali[1]!);
      if (n >= 710) return (n >= 715 ? 82 : 74, true);
      if (n >= 610) return (60, true);
      if (n >= 76) return (66, true); // G76, G77, G78
      if (n >= 71) return (50, true);
      if (n >= 57) return (45, true);
      if (n >= 51) return (34, true);
      return (26, true);
    }
    if (g.contains('mali-t') || g.contains('mali t') || g.contains('mali-4')) return (15, true);
    if (g.contains('powervr')) return (28, true);
    if (g.contains('maleoon')) return (70, true);

    // Desktop
    if (g.contains('llvmpipe') || g.contains('softpipe') || g.contains('microsoft basic') || g.contains('swiftshader')) {
      return (5, true);
    }
    final rtx = RegExp(r'rtx\s*(?:a)?(\d{2})(\d{2})').firstMatch(g);
    if (rtx != null) {
      final gen = int.parse(rtx[1]!);
      final cls = int.parse(rtx[2]!);
      return ((62 + (gen - 20) ~/ 10 * 10 + (cls - 50) ~/ 10 * 4).clamp(55, 100), true);
    }
    final gtx = RegExp(r'gtx\s*(\d{3,4})').firstMatch(g);
    if (gtx != null) {
      final n = int.parse(gtx[1]!);
      return (n >= 1600 ? 64 : n >= 1060 ? 58 : n >= 1050 ? 46 : n >= 950 ? 44 : 30, true);
    }
    final rx = RegExp(r'rx\s*(\d{3,4})').firstMatch(g);
    if (rx != null) {
      final n = int.parse(rx[1]!);
      if (n >= 9000) return (98, true);
      if (n >= 7000) return (90, true);
      if (n >= 6000) return (84, true);
      if (n >= 5000) return (70, true);
      if (n >= 400) return (52, true);
      return (40, true);
    }
    if (g.contains('arc')) return (70, true);
    if (g.contains('radeon') && (g.contains('780m') || g.contains('890m') || g.contains('880m'))) return (62, true);
    if (g.contains('radeon') || g.contains('vega')) return (42, true);
    if (g.contains('iris xe') || g.contains('iris(r) xe')) return (40, true);
    if (g.contains('iris')) return (30, true);
    if (g.contains('uhd') || g.contains('intel') || g.contains('hd graphics')) return (24, true);
    if (g.contains('nvidia') || g.contains('geforce')) return (55, false);
    if (g.contains('amd')) return (50, false);
    return (hw.vulkan ? 50 : 35, false);
  }
}
