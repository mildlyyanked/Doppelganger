"""Central configuration. Everything is env-overridable so the same code
runs against a local no-key setup or a full OpenRouter deployment."""
from __future__ import annotations

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_prefix="DG_", extra="ignore")

    # --- LLM (OpenRouter, OpenAI-compatible) ---
    openrouter_api_key: str = ""
    openrouter_base_url: str = "https://openrouter.ai/api/v1"
    # A strong model for the one-off persona-distillation pass...
    persona_model: str = "anthropic/claude-sonnet-4"
    # ...and a fast/cheap model for per-turn chat.
    chat_model: str = "anthropic/claude-3.5-haiku"

    # --- Embeddings ---
    # "local"  -> zero-dependency deterministic hash embedding (PoC default,
    #             good enough to prove the retrieval loop, swap for prod).
    # "openai" -> any OpenAI-compatible /embeddings endpoint.
    embedding_provider: str = "local"
    embedding_model: str = "text-embedding-3-small"
    embedding_base_url: str = "https://api.openai.com/v1"
    embedding_api_key: str = ""
    embedding_dim: int = 256  # only used by the local provider

    # --- Retrieval ---
    top_k: int = 8

    # --- Ingestion polling ---
    poll_interval_seconds: int = 900  # 15 min; the "update loop" cadence

    # --- HTTP ---
    request_timeout_seconds: float = 60.0
    user_agent: str = "DoppelgangerBot/0.1 (+https://github.com/mildlyyanked/Doppelganger)"


settings = Settings()
