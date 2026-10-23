import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:porthub/compatibility/hardware_tiers.dart';
import 'package:porthub/services/hardware/linux_hardware_probe.dart';
import 'package:porthub/services/hardware/windows_hardware_probe.dart';

/// Executa a análise real de hardware da máquina de desenvolvimento
/// (Windows ou Linux) e imprime o resultado.
void main() {
  test('análise de hardware do host', () async {
    final hw = Platform.isWindows
        ? await WindowsHardwareProbe.probe(storagePath: Directory.current.path)
        : await LinuxHardwareProbe.probe(storagePath: Directory.current.path);
    // ignore: avoid_print
    print(hw.toJson());
    // ignore: avoid_print
    print('CPU tier ${HardwareTiers.cpuTier(hw)} | GPU tier ${HardwareTiers.gpuTier(hw)}');
    expect(hw.ramMb, isNotNull);
    expect(hw.abis, isNotEmpty);
  }, skip: !(Platform.isWindows || Platform.isLinux), timeout: const Timeout(Duration(seconds: 60)));
}
