"""Instagram connector (server-side, optional).

Wraps the Node CLI `drawrowfly/instagram-scraper`
(https://github.com/drawrowfly/instagram-scraper) in ANONYMOUS mode to pull a
public user's posts + captions + media URLs into MemoryItems.

Reality check (why this lives in the backend, isolated, and fails soft):
  - It's Node.js, so it can't run on-device — server mode only.
  - Instagram actively breaks these scrapers; treat breakage as normal.
  - Use anonymous mode only. Do NOT wire in your own session cookie here — the
    richer endpoints that need one risk getting your account banned.
  - Rate-limited / IP-blocked is expected; run behind a proxy for volume.

Because the tool's exact flags/output shape drift between versions, the command
is fully configurable. Default assumes the CLI writes a JSON file we then read.

Prereq:  npm i -g instagram-scraper
config:  {
    "username": "somepublicuser",
    # optional overrides:
    "command": ["instagram-scraper", "{username}", "-t", "user",
                "-o", "{outdir}", "--type", "json"],
    "output_glob": "*.json"   # file(s) the tool drops in outdir
}
"""
from __future__ import annotations

import asyncio
import json
import shutil
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

from ..models import MediaKind, MemoryItem, SourceType
from .base import Connector, ConnectorResult

_DEFAULT_CMD = ["instagram-scraper", "{username}", "-o", "{outdir}", "--type", "json"]


class InstagramConnector(Connector):
    source_name = "instagram"

    async def fetch(
        self, since: Optional[datetime] = None, cursor: Optional[str] = None
    ) -> ConnectorResult:
        username = self.config.get("username")
        if not username:
            return ConnectorResult(ok=False, error="instagram: missing 'username'")
        exe = (self.config.get("command") or _DEFAULT_CMD)[0]
        if shutil.which(exe) is None:
            return ConnectorResult(
                ok=False,
                error=f"instagram: '{exe}' not installed "
                "(npm i -g instagram-scraper). On-device path: import the export.",
            )

        with tempfile.TemporaryDirectory() as outdir:
            cmd = [
                part.format(username=username, outdir=outdir)
                for part in (self.config.get("command") or _DEFAULT_CMD)
            ]
            try:
                proc = await asyncio.create_subprocess_exec(
                    *cmd,
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE,
                )
                stdout, stderr = await proc.communicate()
            except OSError as e:
                return ConnectorResult(ok=False, error=f"instagram: launch failed: {e}")
            if proc.returncode != 0:
                return ConnectorResult(
                    ok=False,
                    error=f"instagram: scraper exited {proc.returncode}: "
                    f"{stderr.decode(errors='ignore')[:300]}",
                )

            records = self._collect(outdir, stdout)

        items = [
            it
            for rec in records
            if (it := self._to_item(username, rec))
            and (since is None or (it.created_at or datetime.min.replace(tzinfo=timezone.utc)) > since)
        ]
        return ConnectorResult(items=items, ok=True)

    def _collect(self, outdir: str, stdout: bytes) -> list[dict[str, Any]]:
        """Prefer JSON files the tool wrote; fall back to stdout JSON."""
        records: list[dict[str, Any]] = []
        for f in sorted(Path(outdir).glob(self.config.get("output_glob", "*.json"))):
            try:
                data = json.loads(f.read_text())
            except (json.JSONDecodeError, OSError):
                continue
            records.extend(self._unwrap(data))
        if not records and stdout.strip():
            try:
                records = self._unwrap(json.loads(stdout))
            except json.JSONDecodeError:
                pass
        return records

    @staticmethod
    def _unwrap(data: Any) -> list[dict[str, Any]]:
        if isinstance(data, list):
            return [d for d in data if isinstance(d, dict)]
        if isinstance(data, dict):
            # common wrappers: {"posts": [...]}, {"edges": [...]}, {"GraphImages": [...]}
            for key in ("posts", "edges", "GraphImages", "items", "data"):
                if isinstance(data.get(key), list):
                    return [d for d in data[key] if isinstance(d, dict)]
            return [data]
        return []

    def _to_item(self, username: str, d: dict[str, Any]) -> Optional[MemoryItem]:
        caption = (
            d.get("caption")
            or d.get("edge_media_to_caption")  # raw graphql shape
            or d.get("description")
            or d.get("text")
            or ""
        )
        if isinstance(caption, dict):  # dig graphql edges->node->text
            try:
                caption = caption["edges"][0]["node"]["text"]
            except (KeyError, IndexError, TypeError):
                caption = ""
        caption = str(caption).strip()
        shortcode = d.get("shortcode") or d.get("code") or d.get("id")
        media = d.get("display_url") or d.get("display_src") or d.get("thumbnail_src")
        if not caption and not media:
            return None
        ts = d.get("taken_at_timestamp") or d.get("taken_at") or d.get("date")
        created = None
        if isinstance(ts, (int, float)):
            created = datetime.fromtimestamp(ts, tz=timezone.utc)
        elif isinstance(ts, str):
            try:
                created = datetime.fromisoformat(ts)
            except ValueError:
                created = None
        return MemoryItem(
            id=f"instagram:{shortcode or caption[:24]}",
            subject_id=self.subject_id,
            source=SourceType.instagram,
            kind=MediaKind.image if media else MediaKind.text,
            text=caption,
            media_url=str(media) if media else None,
            permalink=f"https://instagram.com/p/{shortcode}/" if shortcode else None,
            author_handle=username,
            created_at=created,
            meta={"likes": d.get("edge_liked_by", {}).get("count") if isinstance(d.get("edge_liked_by"), dict) else d.get("likes")},
        )
