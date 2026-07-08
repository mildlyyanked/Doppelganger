import 'embeddings.dart';
import 'models.dart';

/// In-memory vector store — one per twin, lives for the app session.
class MemoryStore {
  final _embedder = HashEmbedding();
  final _items = <String, MemoryItem>{};
  final _vectors = <String, List<double>>{};

  int get count => _items.length;
  List<MemoryItem> all() => _items.values.toList();

  /// Idempotent: re-adding the same id is a no-op (safe to re-poll).
  int add(List<MemoryItem> items) {
    var added = 0;
    for (final it in items) {
      if (_items.containsKey(it.id)) continue;
      _items[it.id] = it;
      _vectors[it.id] = _embedder.embed(it.embeddingText());
      added++;
    }
    return added;
  }

  List<MapEntry<MemoryItem, double>> search(String query, int topK) {
    if (_items.isEmpty) return [];
    final qv = _embedder.embed(query);
    final scored = _vectors.entries
        .map((e) => MapEntry(_items[e.key]!, cosine(qv, e.value)))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return scored.take(topK).toList();
  }
}
