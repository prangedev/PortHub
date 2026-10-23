import 'package:flutter_test/flutter_test.dart';
import 'package:porthub/github/github_client.dart';
import 'package:porthub/services/providers/github_topic_provider.dart';

GitHubRepo repo(String fullName, String description, {int stars = 0}) => GitHubRepo({
      'full_name': fullName,
      'owner': {'login': fullName.split('/').first},
      'name': fullName.split('/').last,
      'description': description,
      'html_url': 'https://github.com/$fullName',
      'stargazers_count': stars,
    });

void main() {
  test('barra repositórios-isca encontrados em buscas reais', () {
    final bait = [
      repo('mowdrdulitl1996/Need-For-Speed-Underground-2-Full-Version',
          'Need for Speed Underground 2 is a free full-version racing game for Windows that lets you'),
      repo('nikanetred5/Need-For-Speed-Underground-2', 'Download Need for Speed Underground 2 — a racing game for Windows with free download.'),
      repo('nighthuntercomb/Need-For-Speed-Most-Wanted',
          'Experience Need for Speed Most Wanted — an exhilarating racing game for Windows with free download'),
      repo('x/gta-mod-apk', 'GTA mod apk unlimited money'),
    ];
    for (final r in bait) {
      expect(GitHubTopicProvider.looksLikeBait(r), isTrue, reason: r.fullName);
    }
  });

  test('não barra ports e ferramentas legítimas', () {
    final legit = [
      repo('Wannamingo/NFSU-Android', 'Native Android ARM64 port of NFS Underground: Vulkan, touch controls, gamepads and portable', stars: 1),
      repo('codepdbh/nfsu2-recompiled', 'Static recompilation of Need for Speed Underground 2 (SPEED2.EXE x86-32 -> C) with pcrecomp', stars: 170),
      repo('lukasduben030-commits/NFSU2-Widescreen-Fix', 'Widescreen fix package for Need for Speed: Underground 2 (PC), with installation instructions'),
      repo('RanggaCasper/Black-Android', 'An unofficial native Android port of the original Xbox version of Black', stars: 166),
      repo('nlgxzef/NFSU2Unlimiter', 'Need for Speed Underground 2 Unlimiter', stars: 66),
    ];
    for (final r in legit) {
      expect(GitHubTopicProvider.looksLikeBait(r), isFalse, reason: r.fullName);
    }
  });
}
