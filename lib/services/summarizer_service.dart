import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/logger.dart';
import '../github/readme_parser.dart';
import 'settings_service.dart';

/// Resumo de descrições longas. Com IA local habilitada usa um servidor
/// compatível com a API do Ollama (`/api/generate`); caso contrário (ou se
/// falhar) usa um resumo extrativo simples, 100% offline.
class SummarizerService {
  SummarizerService(this._settings, {http.Client? client}) : _http = client ?? http.Client();
  final SettingsService _settings;
  final http.Client _http;

  bool get aiEnabled => _settings.aiSummaries;

  Future<String> summarize(String markdown, {required String gameName}) async {
    final text = ReadmeParser.plainText(markdown);
    final input = text.length > 6000 ? text.substring(0, 6000) : text;
    if (_settings.aiSummaries) {
      try {
        final res = await _http
            .post(
              Uri.parse('${_settings.ollamaUrl}/api/generate'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'model': _settings.ollamaModel,
                'stream': false,
                'prompt': 'Resuma em português do Brasil, em no máximo 4 frases, o que é o jogo "$gameName", '
                    'como jogar e o que é necessário para rodar. Texto do README:\n\n$input',
              }),
            )
            .timeout(const Duration(seconds: 90));
        if (res.statusCode == 200) {
          final r = (jsonDecode(utf8.decode(res.bodyBytes)) as Map)['response'] as String?;
          if (r != null && r.trim().isNotEmpty) return r.trim();
        }
        appLog.w('AI', 'IA local respondeu ${res.statusCode}; usando resumo extrativo');
      } catch (e) {
        appLog.w('AI', 'IA local indisponível; usando resumo extrativo', e);
      }
    }
    return extractive(input);
  }

  /// Seleciona as frases mais informativas (as primeiras de cada parágrafo).
  static String extractive(String text, {int maxSentences = 4}) {
    final paragraphs = text.split(RegExp(r'\n\s*\n')).map((p) => p.replaceAll('\n', ' ').trim()).where((p) => p.length > 60);
    final sentences = <String>[];
    for (final p in paragraphs) {
      final first = RegExp(r'^.*?[.!?](\s|$)').firstMatch(p)?.group(0)?.trim() ?? p;
      if (first.length > 30 && first.length < 400) sentences.add(first);
      if (sentences.length >= maxSentences) break;
    }
    return sentences.isEmpty ? (text.length > 400 ? '${text.substring(0, 400)}…' : text) : sentences.join(' ');
  }
}
