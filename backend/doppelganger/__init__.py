"""Doppelganger — build a conversational twin of a person from their
public footprint + supplemental uploads.

The package is organized as a small, swappable pipeline:

    ingest  ->  MemoryItem[]  ->  embed + store  ->  PersonaCard
                                       |                  |
                                       +----- RAG chat ---+ -> guardrails -> reply

Every stage is behind an interface so the fragile bits (public crawlers)
can fail or be replaced without touching the rest of the engine.
"""

__version__ = "0.1.0"
