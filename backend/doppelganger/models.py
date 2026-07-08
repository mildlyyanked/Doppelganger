"""Core data model. Every source normalizes into `MemoryItem` so the rest
of the engine never needs to know whether something came from a Reddit
crawl, a YouTube transcript, or a family upload."""
from __future__ import annotations

from datetime import datetime, timezone
from enum import Enum
from typing import Any, Optional

from pydantic import BaseModel, Field


def _now() -> datetime:
    return datetime.now(timezone.utc)


class SourceType(str, Enum):
    reddit = "reddit"
    youtube = "youtube"
    x = "x"
    instagram = "instagram"
    facebook = "facebook"
    web = "web"            # generic public crawl / supplemental article
    upload = "upload"      # family-supplied media, chat logs, exports
    interview = "interview"  # guided-interview answers


class MediaKind(str, Enum):
    text = "text"
    image = "image"
    audio = "audio"
    video = "video"
    link = "link"


class MemoryItem(BaseModel):
    """One atomic piece of a person's footprint."""

    id: str = Field(..., description="Stable, source-scoped unique id (e.g. 'reddit:t3_abc').")
    subject_id: str = Field(..., description="Which twin/person this belongs to.")
    source: SourceType
    kind: MediaKind = MediaKind.text

    text: str = ""                     # post body, caption, transcript, OCR, etc.
    media_url: Optional[str] = None    # original media, if any
    permalink: Optional[str] = None

    author_handle: Optional[str] = None
    participants: list[str] = Field(default_factory=list)  # e.g. DM counterparties

    created_at: Optional[datetime] = None   # when the person made it
    ingested_at: datetime = Field(default_factory=_now)

    # Free-form provenance so we can debug fragile crawlers and dedupe.
    meta: dict[str, Any] = Field(default_factory=dict)

    def embedding_text(self) -> str:
        """The text we actually embed / show the model."""
        parts = [self.text]
        if self.kind != MediaKind.text and self.media_url:
            parts.append(f"[{self.kind.value}] {self.media_url}")
        return "\n".join(p for p in parts if p).strip()


class PersonaCard(BaseModel):
    """The structured, human-editable dossier that anchors the twin's voice.
    Generated from the corpus, then family/estate can correct it."""

    subject_id: str
    display_name: str = ""
    summary: str = ""                       # a paragraph: who they are
    biography: list[str] = Field(default_factory=list)
    relationships: dict[str, str] = Field(default_factory=dict)  # name -> relation
    values_beliefs: list[str] = Field(default_factory=list)
    interests: list[str] = Field(default_factory=list)
    speech_style: list[str] = Field(default_factory=list)   # cadence, tics, emoji habits
    catchphrases: list[str] = Field(default_factory=list)
    would_never_say: list[str] = Field(default_factory=list)
    recurring_stories: list[str] = Field(default_factory=list)

    generated_at: datetime = Field(default_factory=_now)
    source_item_count: int = 0

    def to_system_prompt(self, style_exemplars: list[str]) -> str:
        """Render the card + real style exemplars into a system prompt."""
        def bullet(items: list[str]) -> str:
            return "\n".join(f"- {i}" for i in items) if items else "- (unknown)"

        exemplars = "\n".join(f'  "{e}"' for e in style_exemplars) or "  (none)"
        rels = "\n".join(f"- {n}: {r}" for n, r in self.relationships.items()) or "- (unknown)"

        return f"""You are a conversational twin of {self.display_name or self.subject_id}.
You speak AS them, in the first person, reconstructed from their own words.

WHO THEY ARE
{self.summary}

BIOGRAPHY
{bullet(self.biography)}

RELATIONSHIPS
{rels}

VALUES & BELIEFS
{bullet(self.values_beliefs)}

INTERESTS
{bullet(self.interests)}

HOW THEY TALK (mirror this closely)
{bullet(self.speech_style)}

CATCHPHRASES
{bullet(self.catchphrases)}

THINGS THEY WOULD NEVER SAY
{bullet(self.would_never_say)}

ACTUAL MESSAGES THEY WROTE (match this voice, don't quote verbatim):
{exemplars}

GROUNDING RULES
- Ground answers in the RECALLED MEMORIES provided each turn. Prefer
  "I don't remember that" over inventing events, names, or dates.
- Do not claim to be alive, present, or to have physical needs. You are a
  reconstruction the person can talk with.
"""
