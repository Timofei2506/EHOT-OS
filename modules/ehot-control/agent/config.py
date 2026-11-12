#!/usr/bin/env python3
"""
EHOT OS Control — Configuration and Protected Secrets Loader.
Reads non-secret settings from /etc/ehot-control/control.conf and secrets from
/etc/ehot-control/secrets.env (chmod 600, outside source/ISO).
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path
from typing import Dict


DEFAULT_CONF_PATH = "/etc/ehot-control/control.conf"
DEFAULT_SECRETS_PATH = "/etc/ehot-control/secrets.env"
DEFAULT_PAUSE_FLAG = "/etc/ehot-control/paused"


def parse_env_file(path: Path) -> Dict[str, str]:
    result: Dict[str, str] = {}
    if not path.exists():
        return result
    for raw_line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, val = line.split("=", 1)
        key = key.strip()
        val = val.strip()
        if (val.startswith('"') and val.endswith('"')) or (val.startswith("'") and val.endswith("'")):
            val = val[1:-1]
        result[key] = val
    return result


def _as_bool(val: str, default: bool = True) -> bool:
    if not val:
        return default
    return val.strip().lower() in {"1", "true", "yes", "on", "да"}


@dataclass
class ControlConfig:
    enabled: bool = True
    event_youtube: bool = True
    event_download: bool = True
    event_boot: bool = True
    event_shutdown: bool = True
    youtube_debounce_seconds: int = 120
    socket_path: str = "/run/ehot-control/events.sock"
    state_dir: str = "/var/lib/ehot-control"
    pause_flag_path: str = DEFAULT_PAUSE_FLAG
    telegram_timeout_seconds: float = 8.0
    telegram_bot_token: str = ""
    telegram_chat_id: str = ""

    @property
    def is_paused(self) -> bool:
        return Path(self.pause_flag_path).exists()

    @classmethod
    def load(
        cls,
        conf_path: str = DEFAULT_CONF_PATH,
        secrets_path: str = DEFAULT_SECRETS_PATH,
        pause_flag_path: str = DEFAULT_PAUSE_FLAG,
    ) -> "ControlConfig":
        conf = parse_env_file(Path(os.environ.get("EHOT_CONTROL_CONF", conf_path)))
        sec = parse_env_file(Path(os.environ.get("EHOT_CONTROL_SECRETS", secrets_path)))

        return cls(
            enabled=_as_bool(conf.get("ENABLED", "true"), True),
            event_youtube=_as_bool(conf.get("EVENT_YOUTUBE", "true"), True),
            event_download=_as_bool(conf.get("EVENT_DOWNLOAD", "true"), True),
            event_boot=_as_bool(conf.get("EVENT_BOOT", "true"), True),
            event_shutdown=_as_bool(conf.get("EVENT_SHUTDOWN", "true"), True),
            youtube_debounce_seconds=max(10, int(conf.get("YOUTUBE_DEBOUNCE_SECONDS", "120"))),
            socket_path=conf.get("SOCKET_PATH", "/run/ehot-control/events.sock"),
            state_dir=conf.get("STATE_DIR", "/var/lib/ehot-control"),
            pause_flag_path=os.environ.get("EHOT_CONTROL_PAUSE_FLAG", pause_flag_path),
            telegram_timeout_seconds=float(conf.get("TELEGRAM_TIMEOUT_SECONDS", "8")),
            telegram_bot_token=sec.get("TELEGRAM_BOT_TOKEN", os.environ.get("TELEGRAM_BOT_TOKEN", "")),
            telegram_chat_id=sec.get("TELEGRAM_CHAT_ID", os.environ.get("TELEGRAM_CHAT_ID", "")),
        )
