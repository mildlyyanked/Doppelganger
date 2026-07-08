"""Reddit public connector — pulls a user's public comments + submissions via
the unauthenticated JSON endpoints. Real, and works with no key, but heavily
rate-limited; for volume, move to the official OAuth API (PRAW) behind this
same interface.

config: {"username": "spez", "kinds": ["comments", "submitted"]}
"""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Optional

import httpx

from ..config import settings
from ..models import MediaKind, MemoryItem, SourceType
from .base import Connector, ConnectorResult


class RedditConnector(Connector):
    source_name = "reddit"

    async def fetch(
        self, since: Optional[datetime] = None, cursor: Optional[str] = None
    ) -> ConnectorResult:
        username = self.config.get("username")
        if not username:
            return ConnectorResult(ok=False, error="reddit: missing 'username'")
        kinds = self.config.get("kinds", ["comments", "submitted"])
        items: list[MemoryItem] = []
        try:
            async with httpx.AsyncClient(
                timeout=settings.request_timeout_seconds,
                headers={"User-Agent": settings.user_agent},
            ) as client:
                for kind in kinds:
                    url = f"https://www.reddit.com/user/{username}/{kind}.json?limit=100"
                    resp = await client.get(url)
                    if resp.status_code != 200:
                        return ConnectorResult(
                            ok=False,
                            error=f"reddit {kind}: HTTP {resp.status_code}",
                        )
                    for child in resp.json().get("data", {}).get("children", []):
                        it = self._to_item(username, kind, child.get("data", {}))
                        if it and (since is None or (it.created_at or datetime.min.replace(tzinfo=timezone.utc)) > since):
                            items.append(it)
        except httpx.HTTPError as e:
            return ConnectorResult(ok=False, error=f"reddit: {e}")
        return ConnectorResult(items=items, ok=True)

    def _to_item(self, username: str, kind: str, d: dict[str, Any]) -> Optional[MemoryItem]:
        name = d.get("name")
        if not name:
            return None
        created = d.get("created_utc")
        text = d.get("body") or ""  # comment
        if kind == "submitted":
            title = d.get("title", "")
            selftext = d.get("selftext", "")
            text = f"{title}\n{selftext}".strip()
        if not text:
            return None
        permalink = d.get("permalink")
        return MemoryItem(
            id=f"reddit:{name}",
            subject_id=self.subject_id,
            source=SourceType.reddit,
            kind=MediaKind.text,
            text=text,
            author_handle=username,
            permalink=f"https://reddit.com{permalink}" if permalink else None,
            created_at=datetime.fromtimestamp(created, tz=timezone.utc) if created else None,
            meta={"subreddit": d.get("subreddit"), "score": d.get("score"), "kind": kind},
        )
