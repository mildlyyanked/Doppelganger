"""Configurable guardrail layer.

Per the current product decision: this is WIRED IN but intentionally EMPTY /
pass-through. No rules are enabled by default. Everything is toggled via
`GuardrailConfig`, so grief-safety features (no 'I'm alive' claims, crisis
routing, session pacing) can be switched on later without touching call sites.
"""
from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class GuardrailConfig:
    # All OFF by default — deferred, as decided. Flip these on to activate.
    block_alive_claims: bool = False
    crisis_routing: bool = False
    session_pacing: bool = False
    custom_blocklist: list[str] = field(default_factory=list)


@dataclass
class GuardrailResult:
    allowed: bool = True
    text: str = ""
    notes: list[str] = field(default_factory=list)


class Guardrails:
    """Hooks around the model. Default config makes every method a no-op."""

    def __init__(self, config: GuardrailConfig | None = None) -> None:
        self.config = config or GuardrailConfig()

    def check_input(self, user_text: str) -> GuardrailResult:
        # Placeholder: crisis_routing etc. would inspect input here.
        return GuardrailResult(allowed=True, text=user_text)

    def filter_output(self, reply: str) -> GuardrailResult:
        # Placeholder: block_alive_claims / custom_blocklist would run here.
        return GuardrailResult(allowed=True, text=reply)

    def extra_system_rules(self) -> str:
        """Additional system-prompt text when safety features are enabled.
        Empty by default so the twin's voice isn't constrained yet."""
        return ""
