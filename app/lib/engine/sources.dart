import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import 'models.dart';

/// Client-side connectors. Live ones (reddit, web) fetch directly; the hostile
/// platforms (x/instagram/facebook/linkedin) come in via import of the user's
/// data export — higher fidelity and no ToS/anti-scraping breakage.
class Sources {
  // Reddit blocklists generic/bot User-Agents on its public .json endpoints
  // (403). A realistic browser UA gets through from a normal (phone) IP.
  static const _ua =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36';
  static const _headers = {
    'User-Agent': _ua,
    'Accept': 'application/json,text/html;q=0.9,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9',
  };

  /// The bundled fake person, so the PoC works with zero setup.
  static Future<List<MemoryItem>> loadSample() async {
    final raw = await rootBundle.loadString('assets/sample_person.json');
    return importJson(raw, Platform.upload);
  }

  /// Reddit public comments + submissions (rate-limited, no login).
  static Future<List<MemoryItem>> reddit(String username) async {
    final handle = username.replaceFirst(RegExp(r'^/?u/'), '').trim();
    final items = <MemoryItem>[];
    for (final kind in ['comments', 'submitted']) {
      final r = await _redditGet(handle, kind);
      if (r.statusCode == 403) {
        throw Exception(
            'Reddit blocked the request (403). Their public API is heavily '
            'rate-limited — wait a minute and retry, or use Reddit\'s data '
            'export and import it. (u/$handle)');
      }
      if (r.statusCode == 404) {
        throw Exception('Reddit user "u/$handle" not found (404).');
      }
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
          authorHandle: handle,
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

  /// GET a user's .json, trying www then old.reddit.com (different edge that
  /// sometimes answers when www 403s). Returns the first non-403 response.
  static Future<http.Response> _redditGet(String handle, String kind) async {
    http.Response? last;
    for (final host in ['www.reddit.com', 'old.reddit.com']) {
      final r = await http.get(
        Uri.parse('https://$host/user/$handle/$kind.json?limit=100&raw_json=1'),
        headers: _headers,
      );
      if (r.statusCode != 403) return r;
      last = r;
    }
    return last!;
  }

  /// Fetch a public article/blog/profile page and strip it to text.
  static Future<List<MemoryItem>> web(String url) async {
    final r = await http.get(Uri.parse(url), headers: _headers);
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
