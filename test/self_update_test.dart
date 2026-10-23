import 'package:flutter_test/flutter_test.dart';
import 'package:porthub/services/self_update_service.dart';

void main() {
  test('número do build vem do fim da tag publicada pelo GitHub Actions', () {
    expect(SelfUpdateService.buildFromTag('v1.0.42'), 42);
    expect(SelfUpdateService.buildFromTag('build-7'), 7);
    expect(SelfUpdateService.buildFromTag('nightly'), 0);
  });
}
