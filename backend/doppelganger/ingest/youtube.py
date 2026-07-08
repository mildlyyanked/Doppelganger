"""YouTube connector — STUB.

Plan: use the official YouTube Data API v3 (friendly, public) to list a
channel's uploads, then pull captions/transcripts as MemoryItems. Requires
DG_ env additions for an API key; left unimplemented so the PoC runs keyless.

config: {"channel_id": "UC...", "api_key": "..."}
"""
from __future__ import annotations

from datetime import datetime
from typing import Optional

from .base import Connector, ConnectorResult


class YouTubeConnector(Connector):
    source_name = "youtube"

    async def fetch(
        self, since: Optional[datetime] = None, cursor: Optional[str] = None
    ) -> ConnectorResult:
        # TODO: GET youtube/v3/search?channelId=... (uploads), then
        # captions.download or a transcript lib -> MemoryItem(kind=video).
        return ConnectorResult(
            ok=False,
            error="youtube connector not implemented yet (stub) — wire the Data API v3",
        )
