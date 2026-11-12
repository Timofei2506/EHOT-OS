#!/usr/bin/env python3
"""
EHOT OS Control — Independent Telegram Bot Integration Module.
Uses Python stdlib (urllib) so memory footprint stays minimal on 4 GB RAM.
"""

from __future__ import annotations

import json
import urllib.error
import urllib.request
from dataclasses import dataclass
from typing import Any, Dict, Optional


@dataclass(frozen=True)
class TelegramResult:
    ok: bool
    status_code: int
    error: Optional[str] = None


class TelegramClient:
    """Client for sending EHOT OS event notifications to an existing Telegram bot."""

    API_BASE = "https://api.telegram.org"

    def __init__(self, bot_token: str, chat_id: str, timeout: float = 8.0) -> None:
        self.bot_token = bot_token.strip()
        self.chat_id = str(chat_id).strip()
        self.timeout = timeout

    def is_configured(self) -> bool:
        return bool(self.bot_token and self.chat_id)

    def send_message(self, text: str, disable_web_page_preview: bool = True) -> TelegramResult:
        if not self.is_configured():
            return TelegramResult(ok=False, status_code=0, error="Telegram token or chat_id not configured")

        url = f"{self.API_BASE}/bot{self.bot_token}/sendMessage"
        payload: Dict[str, Any] = {
            "chat_id": self.chat_id,
            "text": text,
            "disable_web_page_preview": disable_web_page_preview,
        }
        data = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(
            url,
            data=data,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                code = getattr(resp, "status", 200)
                body = json.loads(resp.read().decode("utf-8", errors="replace"))
                if body.get("ok"):
                    return TelegramResult(ok=True, status_code=code)
                return TelegramResult(ok=False, status_code=code, error=str(body.get("description", "API error")))
        except urllib.error.HTTPError as exc:
            return TelegramResult(ok=False, status_code=exc.code, error=f"HTTP {exc.code}")
        except (urllib.error.URLError, TimeoutError, OSError, ValueError) as exc:
            return TelegramResult(ok=False, status_code=0, error=str(exc))
