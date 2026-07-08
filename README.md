# Doppelganger

A conversational **twin** of a person, reconstructed from their footprint —
public posts, supplemental articles, and family/estate uploads — kept fresh by
a continuous **update loop** so it works for ongoing situations (an estranged
relative) as well as grief.

> **Consent & provenance.** Highest-fidelity, lowest-risk data is material the
> owner supplies: platform *Download-Your-Data* exports and uploads (these
> include private DMs/captions a public crawl never sees). Public crawling of
> third-party profiles is the fragile, ToS-sensitive tier — it's isolated
> behind a connector so it can break without taking the engine down.

## How it fits together

```
ingest (connectors)  ->  MemoryItem[]  ->  embed + store  ->  PersonaCard
      reddit / web /            (one schema)      |                |
      youtube / upload                            +--- RAG chat ---+ -> guardrails -> reply
                                                         (streamed to the app)
        ^                                                     
        |  poll loop every DG_POLL_INTERVAL_SECONDS (the "stay updated" loop)
```

- **`backend/`** — Python engine + FastAPI. Runs the whole pipeline; ingest,
  embedding and retrieval work with **no API keys**. Persona-build and chat use
  OpenRouter.
- **`app/`** — Flutter client (Android-first). Thin: it only talks to the
  backend, never to models or source credentials.
- **`.github/workflows/android-build.yml`** — builds an installable APK on
  every push so you can iterate on your phone.

## Quick start — talk to the sample twin

```bash
cd backend
python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt

# Offline: proves ingest + retrieval (no key needed)
python scripts/poc.py

# Full: build the persona and actually chat
export DG_OPENROUTER_API_KEY=sk-or-...
python scripts/poc.py "what's your carbonara secret?"
```

## Run the backend for the app

```bash
cd backend && . .venv/bin/activate
export DG_OPENROUTER_API_KEY=sk-or-...
uvicorn doppelganger.api:app --host 0.0.0.0 --port 8000
```

Then in the app's **Setup** tab set the Backend URL:
- **Android emulator** → `http://10.0.2.2:8000`
- **Real phone (same Wi-Fi)** → `http://<your-computer-LAN-IP>:8000`
  (or expose it with `ngrok http 8000` and use the https URL)

Create twin → Poll → Build persona → switch to **Chat**.

## Phone build loop

Push to your branch → the **Android build** workflow compiles an APK → open the
run → download the `doppelganger-debug-apk` artifact → install on your phone
(enable "install unknown apps"). Upgrade to Firebase App Distribution later to
skip the manual download.

## Status

PoC. In-memory store, in-process twins, guardrails wired but intentionally
empty (see `backend/README.md` for the roadmap and design notes).
