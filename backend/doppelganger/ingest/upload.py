"""Upload connector — ingests family/estate-supplied material and platform
data-export dumps (the highest-fidelity source: includes private DMs and
captions a public crawl can never see).

Accepts either:
  - a list of raw records (dicts) already in memory, or
  - a path to a JSON file / directory of JSON files.

Each record is a partial MemoryItem; sensible defaults are filled in.
"""
from __future__ import annotations

import json
from datetime import datetime
from pathlib import Path
from typing import Any, Optional

from ..models import MediaKind, MemoryItem, SourceType
from .base import Connector, ConnectorResult


class UploadConnector(Connector):
    source_name = "upload"

    async def fetch(
        self, since: Optional[datetime] = None, cursor: Optional[str] = None
    ) -> ConnectorResult:
        records: list[dict[str, Any]] = list(self.config.get("records", []))
        path = self.config.get("path")
        if path:
            records.extend(self._load_path(Path(path)))
        items: list[MemoryItem] = []
        for i, rec in enumerate(records):
            it = self._to_item(i, rec)
            if it:
                items.append(it)
        return ConnectorResult(items=items, ok=True)

    def _load_path(self, path: Path) -> list[dict[str, Any]]:
        files = [path] if path.is_file() else sorted(path.glob("**/*.json"))
        out: list[dict[str, Any]] = []
        for f in files:
            data = json.loads(f.read_text())
            out.extend(data if isinstance(data, list) else [data])
        return out

    def _to_item(self, i: int, rec: dict[str, Any]) -> Optional[MemoryItem]:
        text = (rec.get("text") or "").strip()
        media = rec.get("media_url")
        if not text and not media:
            return None
        rid = rec.get("id") or f"upload:{self.subject_id}:{i}"
        created = rec.get("created_at")
        return MemoryItem(
            id=rid if str(rid).startswith("upload:") else f"upload:{rid}",
            subject_id=self.subject_id,
            source=SourceType(rec.get("source", "upload")),
            kind=MediaKind(rec.get("kind", "text")),
            text=text,
            media_url=media,
            author_handle=rec.get("author_handle"),
            participants=rec.get("participants", []),
            created_at=datetime.fromisoformat(created) if created else None,
            meta=rec.get("meta", {}),
        )
