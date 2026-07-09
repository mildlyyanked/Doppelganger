# Doppelganger backend

Python engine + FastAPI. Every stage is behind an interface so pieces swap
without touching the rest.

## Layout

| Module | Role |
| --- | --- |
| `models.py` | `MemoryItem` (the one normalized unit) and `PersonaCard` (+ its system-prompt renderer). |
| `ingest/` | Source connectors. `base.Connector` is the contract; `reddit`, `web`, `upload` real; `instagram` wraps the Node scraper (server-only, fails soft); `youtube` is a stub. Registry in `ingest/__init__.py`. |
| `embeddings.py` | `LocalHashEmbedding` (keyless default) and `OpenAICompatEmbedding`. |
| `store.py` | In-memory vector store (`add`/`search`/`all`/`count`). Swap for pgvector/Qdrant behind the same surface. |
| `persona.py` | Distills a corpus into a `PersonaCard` + picks real style exemplars. |
| `chat.py` | RAG: retrieve memories, assemble prompt, stream reply. |
| `guardrails.py` | Config-driven safety hooks — **wired in, empty by default**. |
| `twin.py` | Bundles sources + store + card + the poll loop for one subject. |
| `api.py` | FastAPI surface used by the Flutter app (incl. SSE `/chat/stream`). |

## Configuration

All env vars are `DG_`-prefixed; see `.env.example`. Key ones:

- `DG_OPENROUTER_API_KEY` — required for persona-build + chat.
- `DG_PERSONA_MODEL` / `DG_CHAT_MODEL` — strong model for distillation, fast
  model for turns.
- `DG_EMBEDDING_PROVIDER` — `local` (default) or `openai`.
- `DG_POLL_INTERVAL_SECONDS` — the update-loop cadence.

## Connector contract

`fetch(since, cursor)` must be **incremental** (honor `since`/`cursor`) and
**resilient** (catch its own errors, return `ok=False` instead of raising) so a
dead crawler can't stall the poll loop. Add a source by implementing
`Connector` and registering it in `ingest/__init__.py`.

## Roadmap / known PoC shortcuts

- **Persistence**: twins + memories are in-process. Add a DB (Postgres +
  pgvector) and load twins on boot.
- **Poll loop**: `Twin.run_poll_loop` exists but the API doesn't schedule it;
  wire a background runner (APScheduler/Celery/arq) per twin.
- **Embeddings**: local hash embedding proves retrieval but isn't semantically
  strong — flip to `openai` (or a sentence-transformer) for quality.
- **Streaming guardrails**: output filtering currently runs post-hoc on
  non-streamed replies; for streamed replies, buffer + filter before flush when
  safety features are enabled.
- **Multimodal**: images/audio are stored as links only. Add a vision pass to
  caption images and a transcription pass for audio, then embed the text.
- **Voice**: add an ElevenLabs synth step on the reply for spoken twins.
