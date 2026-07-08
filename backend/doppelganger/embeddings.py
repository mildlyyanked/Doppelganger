"""Pluggable embeddings.

- LocalHashEmbedding: zero-dependency, deterministic. Good enough to prove
  the retrieval loop with no keys. NOT semantically strong — swap for prod.
- OpenAICompatEmbedding: any OpenAI-compatible /embeddings endpoint.
"""
from __future__ import annotations

import hashlib
import math
import re
from abc import ABC, abstractmethod

import httpx

from .config import settings

_TOKEN = re.compile(r"[a-z0-9']+")


class EmbeddingProvider(ABC):
    dim: int

    @abstractmethod
    async def embed(self, texts: list[str]) -> list[list[float]]: ...


class LocalHashEmbedding(EmbeddingProvider):
    """Hashing bag-of-words -> L2-normalized vector. Deterministic, offline."""

    def __init__(self, dim: int | None = None) -> None:
        self.dim = dim or settings.embedding_dim

    def _one(self, text: str) -> list[float]:
        vec = [0.0] * self.dim
        for tok in _TOKEN.findall(text.lower()):
            h = int(hashlib.md5(tok.encode()).hexdigest(), 16)
            vec[h % self.dim] += 1.0
        norm = math.sqrt(sum(v * v for v in vec)) or 1.0
        return [v / norm for v in vec]

    async def embed(self, texts: list[str]) -> list[list[float]]:
        return [self._one(t) for t in texts]


class OpenAICompatEmbedding(EmbeddingProvider):
    def __init__(self) -> None:
        self.dim = 0  # discovered from first response

    async def embed(self, texts: list[str]) -> list[list[float]]:
        headers = {"Authorization": f"Bearer {settings.embedding_api_key}"}
        async with httpx.AsyncClient(timeout=settings.request_timeout_seconds) as client:
            resp = await client.post(
                f"{settings.embedding_base_url}/embeddings",
                headers=headers,
                json={"model": settings.embedding_model, "input": texts},
            )
            resp.raise_for_status()
            vecs = [d["embedding"] for d in resp.json()["data"]]
            if vecs:
                self.dim = len(vecs[0])
            return vecs


def get_embedding_provider() -> EmbeddingProvider:
    if settings.embedding_provider == "openai":
        return OpenAICompatEmbedding()
    return LocalHashEmbedding()


def cosine(a: list[float], b: list[float]) -> float:
    dot = sum(x * y for x, y in zip(a, b))
    na = math.sqrt(sum(x * x for x in a)) or 1.0
    nb = math.sqrt(sum(y * y for y in b)) or 1.0
    return dot / (na * nb)
