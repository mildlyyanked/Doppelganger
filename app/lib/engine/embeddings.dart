import 'dart:math';

/// Deterministic, dependency-free hash embedding — the on-device equivalent of
/// the backend's LocalHashEmbedding. Good enough to prove retrieval; swap for a
/// real embeddings API for quality.
class HashEmbedding {
  HashEmbedding({this.dim = 256});
  final int dim;

  static final RegExp _token = RegExp(r"[a-z0-9']+");

  // FNV-1a 32-bit: stable across runs, no crypto dependency.
  int _fnv1a(String s) {
    int hash = 0x811c9dc5;
    for (final c in s.codeUnits) {
      hash ^= c;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  List<double> embed(String text) {
    final vec = List<double>.filled(dim, 0.0);
    for (final m in _token.allMatches(text.toLowerCase())) {
      vec[_fnv1a(m.group(0)!) % dim] += 1.0;
    }
    final norm = sqrt(vec.fold<double>(0.0, (a, v) => a + v * v));
    if (norm == 0) return vec;
    return vec.map((v) => v / norm).toList();
  }
}

double cosine(List<double> a, List<double> b) {
  double dot = 0, na = 0, nb = 0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  if (na == 0 || nb == 0) return 0;
  return dot / (sqrt(na) * sqrt(nb));
}
