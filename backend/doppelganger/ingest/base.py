"""Connector interface + polling contract."""
from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any, Optional

from ..models import MemoryItem


@dataclass
class ConnectorResult:
    items: list[MemoryItem] = field(default_factory=list)
    # Opaque cursor a connector hands back so the next poll is incremental
    # ("since last time"). Persist alongside the source config.
    cursor: Optional[str] = None
    ok: bool = True
    error: Optional[str] = None


class Connector(ABC):
    """One configured source for one subject.

    `fetch` must be:
      - incremental: honor `since` / the returned cursor so polling is cheap
      - resilient: catch its own failures and return ok=False rather than
        raising, so a dead crawler can't take down the poll loop
    """

    source_name: str = "base"

    def __init__(self, subject_id: str, config: dict[str, Any]) -> None:
        self.subject_id = subject_id
        self.config = config

    @abstractmethod
    async def fetch(
        self, since: Optional[datetime] = None, cursor: Optional[str] = None
    ) -> ConnectorResult: ...
