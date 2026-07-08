"""Persona Card builder: distill a corpus of MemoryItems into a structured,
editable dossier via one strong-model pass."""
from __future__ import annotations

import json

from . import llm
from .config import settings
from .models import MemoryItem, PersonaCard

_INSTRUCTION = """You are a forensic profiler. From the SAMPLE of a single \
person's own posts/messages below, infer a structured persona. Return ONLY \
minified JSON with these keys (all optional, omit if unknown):
display_name (string), summary (string, one rich paragraph), biography \
(string[]), relationships (object name->relation), values_beliefs (string[]), \
interests (string[]), speech_style (string[] describing cadence, punctuation, \
emoji, slang), catchphrases (string[]), would_never_say (string[]), \
recurring_stories (string[]).
Infer only from evidence. Do not invent facts that aren't supported."""


def _sample_corpus(items: list[MemoryItem], limit: int = 120) -> str:
    # Prefer text-bearing, most-recent items; keep the prompt bounded.
    texts = [it for it in items if it.embedding_text()]
    texts.sort(key=lambda it: it.created_at or it.ingested_at, reverse=True)
    lines = []
    for it in texts[:limit]:
        stamp = (it.created_at or it.ingested_at).date().isoformat()
        lines.append(f"[{it.source.value} {stamp}] {it.embedding_text()}")
    return "\n".join(lines)


async def build_persona_card(
    subject_id: str, items: list[MemoryItem], api_key: str | None = None
) -> PersonaCard:
    corpus = _sample_corpus(items)
    messages = [
        {"role": "system", "content": _INSTRUCTION},
        {"role": "user", "content": f"PERSON: {subject_id}\n\nSAMPLE:\n{corpus}"},
    ]
    raw = await llm.complete(
        messages, model=settings.persona_model, temperature=0.3, api_key=api_key
    )
    data = _extract_json(raw)
    data["subject_id"] = subject_id
    data["source_item_count"] = len(items)
    return PersonaCard.model_validate(data)


def style_exemplars(items: list[MemoryItem], k: int = 12) -> list[str]:
    """A handful of the person's actual short messages, for few-shot voice."""
    cand = [
        it.text.strip()
        for it in items
        if it.text and 8 <= len(it.text.strip()) <= 240
    ]
    cand.sort(key=len)  # shorter, punchier lines mirror voice better
    seen, out = set(), []
    for c in cand:
        if c not in seen:
            seen.add(c)
            out.append(c)
        if len(out) >= k:
            break
    return out


def _extract_json(raw: str) -> dict:
    raw = raw.strip()
    if raw.startswith("```"):
        raw = raw.split("```", 2)[1].removeprefix("json").strip()
    start, end = raw.find("{"), raw.rfind("}")
    if start != -1 and end != -1:
        raw = raw[start : end + 1]
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return {"summary": raw[:500]}
