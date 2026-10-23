import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/logger.dart';
import '../../core/models/hardware_profile.dart';
import '../../core/platform_info.dart';
import '../../database/hardware_dao.dart';
import 'android_hardware_probe.dart';
import 'linux_hardware_probe.dart';
import 'windows_hardware_probe.dart';

/// Avaliação automática de hardware. Executada na primeira abertura do app e
/// sob demanda (Configurações → Reanalisar). O resultado fica em `hardware_cache`.
class HardwareService extends ChangeNotifier {
  HardwareService(this._dao);
  final HardwareDao _dao;

  HardwareProfile? _profile;
  bool _scanning = false;

  HardwareProfile? get profile => _profile;
  bool get scanning => _scanning;

  Future<void> loadCached() async {
    _profile = await _dao.latest();
    notifyListeners();
  }

  Future<HardwareProfile> scan() async {
    _scanning = true;
    notifyListeners();
    try {
      final display = PlatformDispatcher.instance.displays.firstOrNull;
      final w = display?.size.width.round();
      final h = display?.size.height.round();
      final hz = display?.refreshRate;
      final storage = (await getApplicationSupportDirectory()).path;

      final HardwareProfile hw = switch (hostPlatform) {
        HostPlatform.android => await AndroidHardwareProbe.probe(),
        HostPlatform.linux => await LinuxHardwareProbe.probe(storagePath: storage, screenW: w, screenH: h, refresh: hz),
        HostPlatform.windows => await WindowsHardwareProbe.probe(storagePath: storage, screenW: w, screenH: h, refresh: hz),
        HostPlatform.other => HardwareProfile(
            platform: Platform.operatingSystem,
            abis: [currentProcessArch()],
            screenWidth: w,
            screenHeight: h,
            refreshRate: hz,
          ),
      };
      _profile = hw;
      await _dao.save(hw);
      appLog.i('HW', 'Análise concluída: ${hw.deviceLabel} | CPU ${hw.cpuName ?? hw.socModel} | GPU ${hw.gpuName} | '
          'RAM ${hw.ramMb} MB | ABIs ${hw.abis.join(',')} | Vulkan ${hw.vulkan}');
      return hw;
    } catch (e, s) {
      appLog.e('HW', 'Falha na análise de hardware', e, s);
      final fallback = HardwareProfile(platform: Platform.operatingSystem, abis: [currentProcessArch()]);
      _profile ??= fallback;
      return _profile!;
    } finally {
      _scanning = false;
      notifyListeners();
    }
  }
}
