import 'dart:convert';
import 'package:http/http.dart' as http;

/// Thin client for the Doppelganger backend. Keeps all model/keys/ingest logic
/// server-side — the app never touches OpenRouter or source credentials.
class ApiClient {
  ApiClient(this.baseUrl);

  /// e.g. http://192.168.1.20:8000 (your machine's LAN IP so the phone can reach it)
  String baseUrl;

  Uri _u(String path) => Uri.parse('$baseUrl$path');

  Future<void> createTwin(String subjectId,
      {List<Map<String, dynamic>> sources = const []}) async {
    final r = await http.post(_u('/twins'),
        headers: _json,
        body: jsonEncode({'subject_id': subjectId, 'sources': sources}));
    _check(r);
  }

  Future<void> addSource(
      String subjectId, String kind, Map<String, dynamic> config) async {
    final r = await http.post(_u('/twins/$subjectId/sources'),
        headers: _json, body: jsonEncode({'kind': kind, 'config': config}));
    _check(r);
  }

  Future<Map<String, dynamic>> poll(String subjectId) async {
    final r = await http.post(_u('/twins/$subjectId/poll'));
    _check(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> buildPersona(String subjectId) async {
    final r = await http.post(_u('/twins/$subjectId/persona'));
    _check(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> stats(String subjectId) async {
    final r = await http.get(_u('/twins/$subjectId/stats'));
    _check(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  /// Streams the twin's reply token-by-token via SSE.
  Stream<String> chatStream(String subjectId, String message,
      List<Map<String, String>> history) async* {
    final req = http.Request('POST', _u('/twins/$subjectId/chat/stream'))
      ..headers.addAll(_json)
      ..body = jsonEncode({'message': message, 'history': history});
    final resp = await http.Client().send(req);
    if (resp.statusCode >= 400) {
      throw Exception('chat stream failed: HTTP ${resp.statusCode}');
    }
    final lines = resp.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final line in lines) {
      if (!line.startsWith('data:')) continue;
      final payload = line.substring(5).trim();
      if (payload == '[DONE]') break;
      try {
        yield jsonDecode(payload) as String;
      } catch (_) {/* skip keep-alives / malformed frames */}
    }
  }

  static const _json = {'Content-Type': 'application/json'};

  void _check(http.Response r) {
    if (r.statusCode >= 400) {
      throw Exception('HTTP ${r.statusCode}: ${r.body}');
    }
  }
}
