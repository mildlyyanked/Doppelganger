/// On-device data model — mirrors the backend's MemoryItem/PersonaCard so the
/// PoC runs entirely in the app with no server.

/// Source platforms. `live` = we can poll it client-side with no login.
enum Platform {
  reddit(label: 'Reddit', live: true),
  youtube(label: 'YouTube', live: false), // needs a free Data API key
  x(label: 'X / Twitter', live: false), // login-walled -> import export
  instagram(label: 'Instagram', live: false), // anti-scraping -> import export
  facebook(label: 'Facebook', live: false), // graph api own-acct -> import export
  linkedin(label: 'LinkedIn', live: false), // hostile -> import export
  web(label: 'Web / article', live: true),
  upload(label: 'Upload / sample', live: true);

  const Platform({required this.label, required this.live});
  final String label;
  final bool live;

  static Platform fromKey(String k) =>
      Platform.values.firstWhere((p) => p.name == k, orElse: () => Platform.upload);
}

class MemoryItem {
  MemoryItem({
    required this.id,
    required this.source,
    this.kind = 'text',
    this.text = '',
    this.mediaUrl,
    this.permalink,
    this.authorHandle,
    this.createdAt,
  });

  final String id;
  final Platform source;
  final String kind;
  final String text;
  final String? mediaUrl;
  final String? permalink;
  final String? authorHandle;
  final DateTime? createdAt;

  String embeddingText() {
    final parts = <String>[text];
    if (kind != 'text' && mediaUrl != null) parts.add('[$kind] $mediaUrl');
    return parts.where((p) => p.trim().isNotEmpty).join('\n').trim();
  }

  /// Build from a loose export/JSON record. Returns null if there's nothing usable.
  static MemoryItem? fromRecord(Map<String, dynamic> r, Platform source, int i) {
    final text = (r['text'] ?? r['body'] ?? r['caption'] ?? r['title'] ?? '')
        .toString()
        .trim();
    final media = r['media_url']?.toString();
    if (text.isEmpty && (media == null || media.isEmpty)) return null;
    DateTime? created;
    final c = r['created_at'] ?? r['timestamp'] ?? r['date'];
    if (c != null) created = DateTime.tryParse(c.toString());
    final rawId = (r['id'] ?? '${source.name}:$i').toString();
    return MemoryItem(
      id: '${source.name}:$rawId',
      source: Platform.fromKey((r['source'] ?? source.name).toString()),
      kind: (r['kind'] ?? 'text').toString(),
      text: text,
      mediaUrl: media,
      permalink: r['permalink']?.toString(),
      authorHandle: r['author_handle']?.toString(),
      createdAt: created,
    );
  }
}

class PersonaCard {
  PersonaCard({
    required this.subjectId,
    this.displayName = '',
    this.summary = '',
    this.biography = const [],
    this.relationships = const {},
    this.valuesBeliefs = const [],
    this.interests = const [],
    this.speechStyle = const [],
    this.catchphrases = const [],
    this.wouldNeverSay = const [],
    this.recurringStories = const [],
    this.sourceItemCount = 0,
  });

  final String subjectId;
  final String displayName;
  final String summary;
  final List<String> biography;
  final Map<String, String> relationships;
  final List<String> valuesBeliefs;
  final List<String> interests;
  final List<String> speechStyle;
  final List<String> catchphrases;
  final List<String> wouldNeverSay;
  final List<String> recurringStories;
  final int sourceItemCount;

  static List<String> _strList(dynamic v) =>
      v is List ? v.map((e) => e.toString()).toList() : const [];

  factory PersonaCard.fromJson(
      Map<String, dynamic> j, String subjectId, int count) {
    final rel = <String, String>{};
    if (j['relationships'] is Map) {
      (j['relationships'] as Map).forEach((k, v) => rel[k.toString()] = v.toString());
    }
    return PersonaCard(
      subjectId: subjectId,
      displayName: (j['display_name'] ?? '').toString(),
      summary: (j['summary'] ?? '').toString(),
      biography: _strList(j['biography']),
      relationships: rel,
      valuesBeliefs: _strList(j['values_beliefs']),
      interests: _strList(j['interests']),
      speechStyle: _strList(j['speech_style']),
      catchphrases: _strList(j['catchphrases']),
      wouldNeverSay: _strList(j['would_never_say']),
      recurringStories: _strList(j['recurring_stories']),
      sourceItemCount: count,
    );
  }

  String toSystemPrompt(List<String> styleExemplars) {
    String bullet(List<String> items) =>
        items.isEmpty ? '- (unknown)' : items.map((i) => '- $i').join('\n');
    final rels = relationships.isEmpty
        ? '- (unknown)'
        : relationships.entries.map((e) => '- ${e.key}: ${e.value}').join('\n');
    final exemplars = styleExemplars.isEmpty
        ? '  (none)'
        : styleExemplars.map((e) => '  "$e"').join('\n');
    return '''
You are a conversational twin of ${displayName.isEmpty ? subjectId : displayName}.
You speak AS them, in the first person, reconstructed from their own words.

WHO THEY ARE
$summary

BIOGRAPHY
${bullet(biography)}

RELATIONSHIPS
$rels

VALUES & BELIEFS
${bullet(valuesBeliefs)}

INTERESTS
${bullet(interests)}

HOW THEY TALK (mirror this closely)
${bullet(speechStyle)}

CATCHPHRASES
${bullet(catchphrases)}

THINGS THEY WOULD NEVER SAY
${bullet(wouldNeverSay)}

ACTUAL MESSAGES THEY WROTE (match this voice, don't quote verbatim):
$exemplars

GROUNDING RULES
- Ground answers in the RECALLED MEMORIES provided each turn. Prefer
  "I don't remember that" over inventing events, names, or dates.
- Do not claim to be alive, present, or to have physical needs. You are a
  reconstruction the person can talk with.
''';
  }
}
