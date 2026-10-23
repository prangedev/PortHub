import 'package:flutter_test/flutter_test.dart';
import 'package:porthub/services/artwork_service.dart';

void main() {
  test('normaliza nomes do acervo libretro e de catálogos', () {
    expect(ArtworkService.normalize('Need for Speed - Underground 2 (USA)'), 'need for speed underground 2');
    expect(ArtworkService.normalize('Need for Speed™: Underground 2'), 'need for speed underground 2');
    expect(ArtworkService.normalize("Knuckles' Chaotix (Japan, USA)"), 'knuckles chaotix');
    expect(ArtworkService.normalize('Black Stone - Magic & Steel (USA)'), 'black stone magic and steel');
  });

  test('escolhe a região certa e ignora protótipos e demos', () {
    const files = [
      'Black (Europe).png',
      'Black (USA) (Beta).png',
      'Black (USA).png',
      'Black Stone - Magic & Steel (USA).png',
      'Ninja Gaiden Black (USA).png',
    ];
    expect(ArtworkService.bestMatch(files, 'Black'), 'Black (USA).png');
    expect(ArtworkService.bestMatch(['Black (USA) (Beta).png'], 'Black'), isNull);
    expect(ArtworkService.bestMatch(files, 'Blacksite'), isNull);
  });

  test('extrai arquivos de uma listagem do servidor', () {
    const html = '<a href="?C=N;O=D">Name</a><a href="/">Parent</a>'
        '<a href="Black%20(USA).png">Black (USA).png</a>'
        '<a href="Black%20Stone%20-%20Magic%20&amp;%20Steel%20(USA).png">x</a>';
    final idx = ArtworkService.parseIndex(html);
    expect(idx.keys, containsAll(['Black (USA).png', 'Black Stone - Magic & Steel (USA).png']));
    expect(idx['Black (USA).png'], 'Black%20(USA).png');
  });

  test('deriva o nome do jogo a partir do repositório do port', () {
    expect(ArtworkService.titleFromRepoName('Black-Android'), 'Black');
    expect(ArtworkService.titleFromRepoName('ShaolinMonks-Android'), 'Shaolin Monks');
    expect(ArtworkService.titleFromRepoName('NFS-CARBON-360-ANDROID-RECOMP'), 'NFS CARBON');
  });
}
