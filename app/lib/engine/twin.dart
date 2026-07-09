import 'dart:convert';

import 'models.dart';
import 'openrouter.dart';
import 'store.dart';

/// The on-device twin: holds the memory store, persona card, and the OpenRouter
/// client. Everything lives in memory for the session.
class Twin {
  Twin({
    required this.subjectId,
    required String apiKey,
    String? personaModel,
    String? chatModel,
  })  : _client = OpenRouterClient(apiKey),
        personaModel = (personaModel?.trim().isNotEmpty ?? false)
            ? personaModel!.trim()
            : defaultPersonaModel,
        chatModel = (chatModel?.trim().isNotEmpty ?? false)
            ? chatModel!.trim()
            : defaultChatModel;

  String subjectId;
  final OpenRouterClient _client;
  final store = MemoryStore();
  PersonaCard? card;

  // Configurable OpenRouter model ids (editable in the app so a renamed/retired
  // slug is a one-field fix, not a rebuild). Mutable so changing a model keeps
  // the already-ingested memories and built persona. Defaults to a known-good slug.
  String personaModel; // strong model, distills the persona
  String chatModel; //    per-turn chat
  static const defaultPersonaModel = 'anthropic/claude-sonnet-4';
  static const defaultChatModel = 'anthropic/claude-sonnet-4';
  static const topK = 8;

  int addMemories(List<MemoryItem> items) => store.add(items);

  // --- Persona distillation ---

  static const _personaInstruction =
      'You are a forensic profiler. From the SAMPLE of a single person\'s own '
      'posts/messages below, infer a structured persona. Return ONLY minified '
      'JSON with these keys (all optional, omit if unknown): display_name '
      '(string), summary (string, one rich paragraph), biography (string[]), '
      'relationships (object name->relation), values_beliefs (string[]), '
      'interests (string[]), speech_style (string[] describing cadence, '
      'punctuation, emoji, slang), catchphrases (string[]), would_never_say '
      '(string[]), recurring_stories (string[]). Infer only from evidence.';

  Future<PersonaCard> buildPersona() async {
    final items = store.all();
    final sorted = items.where((i) => i.embeddingText().isNotEmpty).toList()
      ..sort((a, b) => (b.createdAt ?? DateTime(0))
          .compareTo(a.createdAt ?? DateTime(0)));
    final corpus = sorted.take(120).map((it) {
      final stamp =
          (it.createdAt ?? DateTime.now()).toIso8601String().substring(0, 10);
      return '[${it.source.name} $stamp] ${it.embeddingText()}';
    }).join('\n');

    final raw = await _client.complete([
      {'role': 'system', 'content': _personaInstruction},
      {'role': 'user', 'content': 'PERSON: $subjectId\n\nSAMPLE:\n$corpus'},
    ], model: personaModel, temperature: 0.3);

    card = PersonaCard.fromJson(_extractJson(raw), subjectId, items.length);
    return card!;
  }

  List<String> _styleExemplars({int k = 12}) {
    final cand = store
        .all()
        .map((it) => it.text.trim())
        .where((t) => t.length >= 8 && t.length <= 240)
        .toSet()
        .toList()
      ..sort((a, b) => a.length.compareTo(b.length));
    return cand.take(k).toList();
  }

  // --- RAG chat ---

  Stream<String> chatStream(
      List<Map<String, String>> history, String userText) {
    if (card == null) {
      throw Exception('Build a persona first.');
    }
    final hits = store.search(userText, topK);
    final recalled = hits.isEmpty
        ? '(no specific memories matched — answer from general persona only)'
        : hits.map((h) {
            final it = h.key;
            final when = (it.createdAt ?? DateTime.now())
                .toIso8601String()
                .substring(0, 10);
            return '- [${it.source.name} $when] ${it.embeddingText()}';
          }).join('\n');

    final messages = <Map<String, String>>[
      {'role': 'system', 'content': card!.toSystemPrompt(_styleExemplars())},
      ...history,
      {
        'role': 'user',
        'content':
            'RECALLED MEMORIES (ground your reply in these; say you don\'t '
                'remember if they don\'t cover it):\n$recalled\n\n---\n'
                'They say: $userText'
      },
    ];
    return _client.streamChat(messages, model: chatModel);
  }

  Map<String, dynamic> _extractJson(String raw) {
    var s = raw.trim();
    if (s.startsWith('```')) {
      final parts = s.split('```');
      if (parts.length >= 2) s = parts[1].replaceFirst('json', '').trim();
    }
    final start = s.indexOf('{'), end = s.lastIndexOf('}');
    if (start != -1 && end != -1) s = s.substring(start, end + 1);
    try {
      return jsonDecode(s) as Map<String, dynamic>;
    } catch (_) {
      return {'summary': raw.length > 500 ? raw.substring(0, 500) : raw};
    }
  }
}
