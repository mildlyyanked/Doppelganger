"""Generic public web crawl connector — for supplemental articles, blogs,
personal sites, and (best-effort) public profile pages.

This is the FRAGILE tier by design: markup changes and anti-bot measures
break it, and platform ToS may forbid it. It's isolated here so that when it
breaks, nothing else does. Ships as a minimal, honest fetch: pull a URL,
strip tags, emit one MemoryItem. Swap in a real extractor (trafilatura /
readability) + JS rendering per-target as needed.

config: {"urls": ["https://.../post"], "handle": "optional"}
"""
from __future__ import annotations

import re
from datetime import datetime, timezone
from typing import Optional

import httpx

from ..config import settings
from ..models import MediaKind, MemoryItem, SourceType
from .base import Connector, ConnectorResult

_TAG = re.compile(r"<[^>]+>")
_WS = re.compile(r"\s+")


class WebCrawlConnector(Connector):
    source_name = "web"

    async def fetch(
        self, since: Optional[datetime] = None, cursor: Optional[str] = None
    ) -> ConnectorResult:
        urls = self.config.get("urls", [])
        if not urls:
            return ConnectorResult(ok=False, error="web: no 'urls' configured")
        items: list[MemoryItem] = []
        try:
            async with httpx.AsyncClient(
                timeout=settings.request_timeout_seconds,
                headers={"User-Agent": settings.user_agent},
                follow_redirects=True,
            ) as client:
                for url in urls:
                    resp = await client.get(url)
                    if resp.status_code != 200:
                        # Skip a bad URL rather than failing the whole batch.
                        continue
                    text = self._extract(resp.text)
                    if text:
                        items.append(
                            MemoryItem(
                                id=f"web:{url}",
                                subject_id=self.subject_id,
                                source=SourceType.web,
                                kind=MediaKind.text,
                                text=text[:8000],
                                permalink=url,
                                author_handle=self.config.get("handle"),
                                created_at=datetime.now(timezone.utc),
                                meta={"url": url},
                            )
                        )
        except httpx.HTTPError as e:
            return ConnectorResult(items=items, ok=False, error=f"web: {e}")
        return ConnectorResult(items=items, ok=True)

    def _extract(self, html: str) -> str:
        html = re.sub(r"<script.*?</script>", " ", html, flags=re.S | re.I)
        html = re.sub(r"<style.*?</style>", " ", html, flags=re.S | re.I)
        return _WS.sub(" ", _TAG.sub(" ", html)).strip()
