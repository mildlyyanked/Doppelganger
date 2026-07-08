"""FastAPI surface for the Flutter client.

PoC-grade: twins live in-process (a dict). For prod, back this with a DB and
a real job runner for the poll loops. Endpoints:

  POST /twins                      create a twin (+ optional sources)
  POST /twins/{id}/sources         add a source
  POST /twins/{id}/poll            poll all sources once
  POST /twins/{id}/persona         (re)build the persona card
  GET  /twins/{id}/persona         fetch the card
  GET  /twins/{id}/stats           memory counts
  POST /twins/{id}/chat            non-streaming reply
  POST /twins/{id}/chat/stream     SSE token stream (used by the app)
"""
from __future__ import annotations

import json
from typing import Any

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from .chat import DoppelgangerChat
from .twin import Twin

app = FastAPI(title="Doppelganger", version="0.1.0")
app.add_middleware(
    CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"]
)

TWINS: dict[str, Twin] = {}


def _get(twin_id: str) -> Twin:
    twin = TWINS.get(twin_id)
    if not twin:
        raise HTTPException(404, f"twin '{twin_id}' not found")
    return twin


class CreateTwin(BaseModel):
    subject_id: str
    sources: list[dict[str, Any]] = []  # [{"kind": "reddit", "config": {...}}]


class AddSource(BaseModel):
    kind: str
    config: dict[str, Any]


class ChatTurn(BaseModel):
    message: str
    history: list[dict[str, str]] = []


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/twins")
async def create_twin(body: CreateTwin) -> dict[str, Any]:
    twin = Twin(subject_id=body.subject_id)
    for s in body.sources:
        twin.add_source(s["kind"], s.get("config", {}))
    TWINS[body.subject_id] = twin
    return {"subject_id": body.subject_id, "sources": len(twin.sources)}


@app.post("/twins/{twin_id}/sources")
async def add_source(twin_id: str, body: AddSource) -> dict[str, Any]:
    twin = _get(twin_id)
    twin.add_source(body.kind, body.config)
    return {"sources": len(twin.sources)}


@app.post("/twins/{twin_id}/poll")
async def poll(twin_id: str) -> dict[str, Any]:
    twin = _get(twin_id)
    report = await twin.poll_once()
    return {"report": report, "memory_count": twin.store.count()}


@app.post("/twins/{twin_id}/persona")
async def build_persona(twin_id: str) -> dict[str, Any]:
    twin = _get(twin_id)
    if twin.store.count() == 0:
        raise HTTPException(400, "no memories yet — poll a source first")
    card = await twin.rebuild_persona()
    return card.model_dump(mode="json")


@app.get("/twins/{twin_id}/persona")
async def get_persona(twin_id: str) -> dict[str, Any]:
    twin = _get(twin_id)
    if not twin.card:
        raise HTTPException(404, "persona not built yet")
    return twin.card.model_dump(mode="json")


@app.get("/twins/{twin_id}/stats")
async def stats(twin_id: str) -> dict[str, Any]:
    twin = _get(twin_id)
    return {
        "subject_id": twin_id,
        "memory_count": twin.store.count(),
        "sources": [s.kind for s in twin.sources],
        "persona_built": twin.card is not None,
    }


def _chat(twin: Twin) -> DoppelgangerChat:
    if not twin.card:
        raise HTTPException(400, "persona not built yet — POST /persona first")
    return DoppelgangerChat(twin.card, twin.store, twin.guardrails)


@app.post("/twins/{twin_id}/chat")
async def chat(twin_id: str, body: ChatTurn) -> dict[str, str]:
    twin = _get(twin_id)
    reply = await _chat(twin).reply(body.history, body.message)
    return {"reply": reply}


@app.post("/twins/{twin_id}/chat/stream")
async def chat_stream(twin_id: str, body: ChatTurn) -> StreamingResponse:
    twin = _get(twin_id)
    chat_engine = _chat(twin)

    async def gen():
        # JSON-encode each delta so newlines/special chars survive SSE framing.
        async for delta in chat_engine.stream(body.history, body.message):
            yield f"data: {json.dumps(delta)}\n\n"
        yield "data: [DONE]\n\n"

    return StreamingResponse(gen(), media_type="text/event-stream")
