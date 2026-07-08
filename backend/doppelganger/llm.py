"""Thin OpenRouter (OpenAI-compatible) client with streaming support."""
from __future__ import annotations

import json
from typing import AsyncIterator

import httpx

from .config import settings


class LLMError(RuntimeError):
    pass


def _headers() -> dict[str, str]:
    if not settings.openrouter_api_key:
        raise LLMError(
            "DG_OPENROUTER_API_KEY is not set. Export it (see backend/.env.example) "
            "or the persona/chat calls cannot run."
        )
    return {
        "Authorization": f"Bearer {settings.openrouter_api_key}",
        "HTTP-Referer": "https://github.com/mildlyyanked/Doppelganger",
        "X-Title": "Doppelganger",
        "Content-Type": "application/json",
    }


async def complete(messages: list[dict], *, model: str, temperature: float = 0.8) -> str:
    """Non-streaming completion; returns the full text."""
    async with httpx.AsyncClient(timeout=settings.request_timeout_seconds) as client:
        resp = await client.post(
            f"{settings.openrouter_base_url}/chat/completions",
            headers=_headers(),
            json={"model": model, "messages": messages, "temperature": temperature},
        )
        if resp.status_code >= 400:
            raise LLMError(f"OpenRouter {resp.status_code}: {resp.text[:500]}")
        data = resp.json()
        return data["choices"][0]["message"]["content"]


async def stream(
    messages: list[dict], *, model: str, temperature: float = 0.8
) -> AsyncIterator[str]:
    """Yield text deltas as they arrive (SSE)."""
    async with httpx.AsyncClient(timeout=settings.request_timeout_seconds) as client:
        async with client.stream(
            "POST",
            f"{settings.openrouter_base_url}/chat/completions",
            headers=_headers(),
            json={
                "model": model,
                "messages": messages,
                "temperature": temperature,
                "stream": True,
            },
        ) as resp:
            if resp.status_code >= 400:
                body = await resp.aread()
                raise LLMError(f"OpenRouter {resp.status_code}: {body[:500]!r}")
            async for line in resp.aiter_lines():
                if not line or not line.startswith("data:"):
                    continue
                payload = line[len("data:"):].strip()
                if payload == "[DONE]":
                    break
                try:
                    delta = json.loads(payload)["choices"][0]["delta"].get("content")
                except (json.JSONDecodeError, KeyError, IndexError):
                    continue
                if delta:
                    yield delta
