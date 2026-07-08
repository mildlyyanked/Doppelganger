import 'dart:convert';
import 'package:http/http.dart' as http;

/// Direct OpenRouter client — called straight from the device. The key goes
/// only to OpenRouter (no backend hop). Native Android has no CORS constraint.
class OpenRouterClient {
  OpenRouterClient(this.apiKey);
  final String apiKey;

  static const _base = 'https://openrouter.ai/api/v1';
  Map<String, String> get _headers => {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
        'HTTP-Referer': 'https://github.com/mildlyyanked/Doppelganger',
        'X-Title': 'Doppelganger',
      };

  void _requireKey() {
    if (apiKey.trim().isEmpty) {
      throw Exception('No OpenRouter API key — add one in the Setup tab.');
    }
  }

  Future<String> complete(List<Map<String, String>> messages,
      {required String model, double temperature = 0.8}) async {
    _requireKey();
    final r = await http.post(
      Uri.parse('$_base/chat/completions'),
      headers: _headers,
      body: jsonEncode(
          {'model': model, 'messages': messages, 'temperature': temperature}),
    );
    if (r.statusCode >= 400) {
      throw Exception('OpenRouter ${r.statusCode}: ${r.body}');
    }
    return jsonDecode(r.body)['choices'][0]['message']['content'] as String;
  }

  Stream<String> streamChat(List<Map<String, String>> messages,
      {required String model, double temperature = 0.8}) async* {
    _requireKey();
    final req = http.Request('POST', Uri.parse('$_base/chat/completions'))
      ..headers.addAll(_headers)
      ..body = jsonEncode({
        'model': model,
        'messages': messages,
        'temperature': temperature,
        'stream': true,
      });
    final resp = await http.Client().send(req);
    if (resp.statusCode >= 400) {
      final body = await resp.stream.bytesToString();
      throw Exception('OpenRouter ${resp.statusCode}: $body');
    }
    final lines =
        resp.stream.transform(utf8.decoder).transform(const LineSplitter());
    await for (final line in lines) {
      if (!line.startsWith('data:')) continue;
      final payload = line.substring(5).trim();
      if (payload == '[DONE]') break;
      try {
        final delta = jsonDecode(payload)['choices'][0]['delta']['content'];
        if (delta != null) yield delta as String;
      } catch (_) {/* keep-alive / partial frame */}
    }
  }
}
