import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import 'models.dart';

/// Client-side connectors. Live ones (reddit, web) fetch directly; the hostile
/// platforms (x/instagram/facebook/linkedin) come in via import of the user's
/// data export — higher fidelity and no ToS/anti-scraping breakage.
class Sources {
  static const _ua = 'DoppelgangerApp/0.1';

  /// The bundled fake person, so the PoC works with zero setup.
  static Future<List<MemoryItem>> loadSample() async {
    final raw = await rootBundle.loadString('assets/sample_person.json');
    return importJson(raw, Platform.upload);
  }

  /// Reddit public comments + submissions (rate-limited, no login).
  static Future<List<MemoryItem>> reddit(String username) async {
    final items = <MemoryItem>[];
    for (final kind in ['comments', 'submitted']) {
      final r = await http.get(
        Uri.parse('https://www.reddit.com/user/$username/$kind.json?limit=100'),
        headers: {'User-Agent': _ua},
      );
      if (r.statusCode != 200) {
        throw Exception('Reddit $kind: HTTP ${r.statusCode}');
      }
      final children =
          (jsonDecode(r.body)['data']?['children'] as List?) ?? const [];
      for (final child in children) {
        final d = child['data'] as Map<String, dynamic>;
        final name = d['name']?.toString();
        if (name == null) continue;
        var text = (d['body'] ?? '').toString();
        if (kind == 'submitted') {
          text = '${d['title'] ?? ''}\n${d['selftext'] ?? ''}'.trim();
        }
        if (text.isEmpty) continue;
        final created = d['created_utc'];
        items.add(MemoryItem(
          id: 'reddit:$name',
          source: Platform.reddit,
          text: text,
          authorHandle: username,
          permalink: d['permalink'] != null
              ? 'https://reddit.com${d['permalink']}'
              : null,
          createdAt: created is num
              ? DateTime.fromMillisecondsSinceEpoch((created * 1000).round(),
                  isUtc: true)
              : null,
        ));
      }
    }
    return items;
  }

  /// Fetch a public article/blog/profile page and strip it to text.
  static Future<List<MemoryItem>> web(String url) async {
    final r = await http.get(Uri.parse(url), headers: {'User-Agent': _ua});
    if (r.statusCode != 200) throw Exception('Web: HTTP ${r.statusCode}');
    var html = r.body
        .replaceAll(RegExp(r'<script.*?</script>', dotAll: true), ' ')
        .replaceAll(RegExp(r'<style.*?</style>', dotAll: true), ' ')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (html.isEmpty) return [];
    return [
      MemoryItem(
        id: 'web:$url',
        source: Platform.web,
        text: html.length > 8000 ? html.substring(0, 8000) : html,
        permalink: url,
        createdAt: DateTime.now().toUtc(),
      )
    ];
  }

  /// Import a JSON array of post records (a data-export dump or hand-made list),
  /// tagging them with the chosen platform. This is the path for X/IG/FB/LinkedIn.
  static List<MemoryItem> importJson(String raw, Platform platform) {
    final decoded = jsonDecode(raw);
    final records = decoded is List ? decoded : [decoded];
    final out = <MemoryItem>[];
    for (var i = 0; i < records.length; i++) {
      final item =
          MemoryItem.fromRecord(records[i] as Map<String, dynamic>, platform, i);
      if (item != null) out.add(item);
    }
    return out;
  }
}
