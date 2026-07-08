#!/usr/bin/env python3
"""End-to-end PoC: ingest -> store -> persona -> talk to the doppelganger.

Runs entirely offline for ingest/embed/retrieval (local hash embeddings).
The persona-build and chat steps call OpenRouter, so set DG_OPENROUTER_API_KEY
to exercise those. Without a key it still proves ingest + retrieval and prints
what WOULD be sent.

Usage:
    cd backend
    pip install -r requirements.txt
    export DG_OPENROUTER_API_KEY=sk-or-...        # optional but recommended
    python scripts/poc.py                          # interactive chat
    python scripts/poc.py "what's your carbonara secret?"   # one-shot
"""
from __future__ import annotations

import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from doppelganger.chat import DoppelgangerChat            # noqa: E402
from doppelganger.config import settings                  # noqa: E402
from doppelganger.llm import LLMError                      # noqa: E402
from doppelganger.twin import Twin                         # noqa: E402

SAMPLE = Path(__file__).resolve().parents[1] / "sample_data" / "sample_person.json"


async def main() -> None:
    twin = Twin(subject_id="sample_dad")
    twin.add_source("upload", {"path": str(SAMPLE)})

    print("→ polling sources...")
    report = await twin.poll_once()
    print(f"  {report}")
    print(f"  memory items: {twin.store.count()}")

    # Show retrieval works with zero LLM keys.
    hits = await twin.store.search("cooking pasta", settings.top_k)
    print("\n→ retrieval sanity check (query='cooking pasta'):")
    for item, score in hits[:3]:
        print(f"  [{score:.3f}] {item.embedding_text()[:80]}")

    if not settings.openrouter_api_key:
        print(
            "\n⚠  DG_OPENROUTER_API_KEY not set — skipping persona build + chat.\n"
            "   Set it and re-run to talk to the doppelganger."
        )
        return

    print("\n→ building persona card (this calls OpenRouter)...")
    card = await twin.rebuild_persona()
    print(f"  name: {card.display_name}")
    print(f"  summary: {card.summary[:200]}")
    print(f"  speech style: {card.speech_style[:3]}")

    chat = DoppelgangerChat(card, twin.store, twin.guardrails)
    one_shot = " ".join(sys.argv[1:]).strip()

    async def turn(text: str) -> None:
        print(f"\nyou: {text}\n{card.display_name or 'twin'}: ", end="", flush=True)
        async for delta in chat.stream([], text):
            print(delta, end="", flush=True)
        print()

    if one_shot:
        await turn(one_shot)
        return

    print("\n→ chatting. Ctrl-C to exit.")
    while True:
        try:
            text = input("\nyou: ").strip()
        except (EOFError, KeyboardInterrupt):
            print("\nbye.")
            return
        if text:
            print(f"{card.display_name or 'twin'}: ", end="", flush=True)
            async for delta in chat.stream([], text):
                print(delta, end="", flush=True)
            print()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except LLMError as e:
        print(f"\nLLM error: {e}")
