"""RAG chat: retrieve real memories, assemble the prompt from the persona
card + exemplars + recalled memories, stream the twin's reply."""
from __future__ import annotations

from typing import AsyncIterator

from . import llm, persona
from .config import settings
from .guardrails import Guardrails
from .models import MemoryItem, PersonaCard
from .store import MemoryStore


def _format_memories(hits: list[tuple[MemoryItem, float]]) -> str:
    if not hits:
        return "(no specific memories matched — answer from general persona only)"
    lines = []
    for item, score in hits:
        when = (item.created_at or item.ingested_at).date().isoformat()
        lines.append(f"- [{item.source.value} {when}] {item.embedding_text()}")
    return "\n".join(lines)


class DoppelgangerChat:
    def __init__(
        self,
        card: PersonaCard,
        store: MemoryStore,
        guardrails: Guardrails | None = None,
        api_key: str | None = None,
    ) -> None:
        self.card = card
        self.store = store
        self.guardrails = guardrails or Guardrails()
        self.api_key = api_key
        self._exemplars = persona.style_exemplars(store.all())

    async def _build_messages(self, history: list[dict], user_text: str) -> list[dict]:
        hits = await self.store.search(user_text, settings.top_k)
        system = self.card.to_system_prompt(self._exemplars)
        extra = self.guardrails.extra_system_rules()
        if extra:
            system += "\n\nSAFETY\n" + extra
        recalled = (
            "RECALLED MEMORIES (ground your reply in these; say you don't "
            f"remember if they don't cover it):\n{_format_memories(hits)}"
        )
        return [
            {"role": "system", "content": system},
            *history,
            {"role": "user", "content": f"{recalled}\n\n---\nThey say: {user_text}"},
        ]

    async def reply(self, history: list[dict], user_text: str) -> str:
        gi = self.guardrails.check_input(user_text)
        if not gi.allowed:
            return gi.text
        messages = await self._build_messages(history, gi.text)
        raw = await llm.complete(messages, model=settings.chat_model, api_key=self.api_key)
        return self.guardrails.filter_output(raw).text

    async def stream(self, history: list[dict], user_text: str) -> AsyncIterator[str]:
        gi = self.guardrails.check_input(user_text)
        if not gi.allowed:
            yield gi.text
            return
        messages = await self._build_messages(history, gi.text)
        # NOTE: output guardrails run post-hoc on streamed text at the API layer.
        async for delta in llm.stream(messages, model=settings.chat_model, api_key=self.api_key):
            yield delta
