"""In-memory vector store for the PoC. One instance per subject/twin.

Deliberately tiny (numpy-free cosine) so the PoC runs with no infra. For
prod, swap this class for pgvector/Qdrant behind the same method surface:
`add`, `search`, `all`, `count`.
"""
from __future__ import annotations

from dataclasses import dataclass, field

from .embeddings import EmbeddingProvider, cosine
from .models import MemoryItem


@dataclass
class MemoryStore:
    embedder: EmbeddingProvider
    _items: dict[str, MemoryItem] = field(default_factory=dict)
    _vectors: dict[str, list[float]] = field(default_factory=dict)

    async def add(self, items: list[MemoryItem]) -> int:
        """Add items, skipping ids we already have (idempotent polling)."""
        fresh = [it for it in items if it.id not in self._items]
        if not fresh:
            return 0
        vecs = await self.embedder.embed([it.embedding_text() for it in fresh])
        for it, v in zip(fresh, vecs):
            self._items[it.id] = it
            self._vectors[it.id] = v
        return len(fresh)

    async def search(self, query: str, top_k: int) -> list[tuple[MemoryItem, float]]:
        if not self._items:
            return []
        qv = (await self.embedder.embed([query]))[0]
        scored = [
            (self._items[i], cosine(qv, v)) for i, v in self._vectors.items()
        ]
        scored.sort(key=lambda t: t[1], reverse=True)
        return scored[:top_k]

    def all(self) -> list[MemoryItem]:
        return list(self._items.values())

    def count(self) -> int:
        return len(self._items)
