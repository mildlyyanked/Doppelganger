"""A Twin bundles one subject's sources, memory store, persona card, and chat.
Holds the update loop that makes Doppelganger work for ongoing use (an
estranged relative) and not just a one-time grief snapshot."""
from __future__ import annotations

import asyncio
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Optional

from . import persona
from .config import settings
from .embeddings import get_embedding_provider
from .guardrails import GuardrailConfig, Guardrails
from .ingest import REGISTRY
from .ingest.base import Connector
from .models import PersonaCard
from .store import MemoryStore


@dataclass
class SourceConfig:
    kind: str                 # key into ingest.REGISTRY
    config: dict[str, Any]
    cursor: Optional[str] = None
    last_polled: Optional[datetime] = None


@dataclass
class Twin:
    subject_id: str
    sources: list[SourceConfig] = field(default_factory=list)
    store: MemoryStore = field(default=None)  # type: ignore[assignment]
    card: Optional[PersonaCard] = None
    guardrails: Guardrails = field(default_factory=lambda: Guardrails(GuardrailConfig()))

    def __post_init__(self) -> None:
        if self.store is None:
            self.store = MemoryStore(embedder=get_embedding_provider())

    def add_source(self, kind: str, config: dict[str, Any]) -> None:
        if kind not in REGISTRY:
            raise ValueError(f"unknown source '{kind}'; known: {list(REGISTRY)}")
        self.sources.append(SourceConfig(kind=kind, config=config))

    def _connector(self, sc: SourceConfig) -> Connector:
        return REGISTRY[sc.kind](self.subject_id, sc.config)

    async def poll_once(self) -> dict[str, Any]:
        """Poll every source once, add new items. Returns a per-source report.
        One source failing never blocks the others."""
        report: dict[str, Any] = {}
        for sc in self.sources:
            try:
                result = await self._connector(sc).fetch(since=sc.last_polled, cursor=sc.cursor)
            except Exception as e:  # a connector should not raise, but be safe
                report[sc.kind] = {"ok": False, "error": f"unexpected: {e}"}
                continue
            added = await self.store.add(result.items) if result.items else 0
            sc.cursor = result.cursor or sc.cursor
            sc.last_polled = datetime.now(timezone.utc)
            report[sc.kind] = {
                "ok": result.ok, "error": result.error,
                "fetched": len(result.items), "added": added,
            }
        return report

    async def run_poll_loop(self, interval: Optional[int] = None) -> None:
        """The continuous update loop (Mode B). Cancel the task to stop."""
        interval = interval or settings.poll_interval_seconds
        while True:
            await self.poll_once()
            await self.rebuild_persona()
            await asyncio.sleep(interval)

    async def rebuild_persona(self) -> PersonaCard:
        items = self.store.all()
        self.card = await persona.build_persona_card(self.subject_id, items)
        return self.card
