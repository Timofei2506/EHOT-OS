#!/usr/bin/env python3
"""
EHOT OS Control — Lightweight Background Monitoring Daemon.
Accepts ONLY 4 strictly whitelisted event types:
  1. youtube_start
  2. download_start
  3. system_boot
  4. system_shutdown
Never logs passwords, keystrokes, screenshots, file contents, or other browsing history.
"""

from __future__ import annotations

import json
import logging
import os
import signal
import socket
import sys
import threading
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional

AGENT_DIR = Path(__file__).resolve().parent
if str(AGENT_DIR) not in sys.path:
    sys.path.insert(0, str(AGENT_DIR))

from config import ControlConfig  # noqa: E402
from telegram_client import TelegramClient  # noqa: E402

ALLOWED_EVENTS = frozenset({"youtube_start", "download_start", "system_boot", "system_shutdown"})
MAX_PENDING_EVENTS = 50
MAX_SOCKET_PAYLOAD_BYTES = 8192

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [ehot-control] %(levelname)s: %(message)s",
)
logger = logging.getLogger("ehot-control")


def sanitize_text(value: Any, max_len: int = 160) -> str:
    text = str(value or "").replace("\r", " ").replace("\n", " ").strip()
    if len(text) > max_len:
        return text[: max_len - 1] + "…"
    return text


def format_event_message(event: Dict[str, Any], hostname: str, delayed: bool = False) -> Optional[str]:
    etype = event.get("event")
    if etype not in ALLOWED_EVENTS:
        return None

    ts = sanitize_text(event.get("timestamp") or datetime.now(timezone.utc).astimezone().strftime("%Y-%m-%d %H:%M:%S"), 40)
    prefix = "⏳ [Отложенное уведомление]\n" if delayed else ""

    if etype == "youtube_start":
        title = sanitize_text(event.get("title") or "Без названия", 140)
        video_id = sanitize_text(event.get("video_id") or "", 32)
        url = f"https://www.youtube.com/watch?v={video_id}" if video_id else sanitize_text(event.get("url") or "https://www.youtube.com", 160)
        return (
            f"{prefix}▶️ EHOT OS [{hostname}]: Начат просмотр YouTube\n"
            f"Видео: {title}\n"
            f"Ссылка: {url}\n"
            f"Время: {ts}"
        )

    if etype == "download_start":
        filename = Path(sanitize_text(event.get("filename") or "unknown", 180)).name or "unknown"
        domain = sanitize_text(event.get("source_domain") or "неизвестный источник", 100)
        return (
            f"{prefix}⬇️ EHOT OS [{hostname}]: Начата загрузка файла\n"
            f"Файл: {filename}\n"
            f"Источник: {domain}\n"
            f"Время: {ts}"
        )

    if etype == "system_boot":
        return f"{prefix}🟢 EHOT OS [{hostname}]: Ноутбук включён\nВремя: {ts}"

    if etype == "system_shutdown":
        return f"{prefix}🔴 EHOT OS [{hostname}]: Ноутбук выключается / перезагружается\nВремя: {ts}"

    return None


class EventProcessor:
    def __init__(self, cfg: ControlConfig, notifier: TelegramClient, hostname: Optional[str] = None) -> None:
        self.cfg = cfg
        self.notifier = notifier
        self.hostname = hostname or socket.gethostname()
        self._lock = threading.Lock()
        self._recent_youtube: Dict[str, float] = {}
        self.state_dir = Path(cfg.state_dir)
        self.pending_file = self.state_dir / "pending_events.json"

    def is_event_allowed_by_config(self, etype: str) -> bool:
        if not self.cfg.enabled or self.cfg.is_paused:
            return False
        mapping = {
            "youtube_start": self.cfg.event_youtube,
            "download_start": self.cfg.event_download,
            "system_boot": self.cfg.event_boot,
            "system_shutdown": self.cfg.event_shutdown,
        }
        return mapping.get(etype, False)

    def _is_youtube_duplicate(self, video_id: str, now: float) -> bool:
        if not video_id:
            return False
        # Clean expired entries
        cutoff = now - self.cfg.youtube_debounce_seconds
        self._recent_youtube = {k: v for k, v in self._recent_youtube.items() if v >= cutoff}
        last_seen = self._recent_youtube.get(video_id)
        if last_seen is not None and (now - last_seen) < self.cfg.youtube_debounce_seconds:
            return True
        self._recent_youtube[video_id] = now
        return False

    def _load_pending(self) -> List[Dict[str, Any]]:
        if not self.pending_file.exists():
            return []
        try:
            data = json.loads(self.pending_file.read_text(encoding="utf-8"))
            return data if isinstance(data, list) else []
        except (OSError, ValueError):
            return []

    def _save_pending(self, items: List[Dict[str, Any]]) -> None:
        try:
            self.state_dir.mkdir(parents=True, exist_ok=True)
            trimmed = items[-MAX_PENDING_EVENTS:]
            self.pending_file.write_text(json.dumps(trimmed, ensure_ascii=False), encoding="utf-8")
        except OSError as exc:
            logger.warning("Failed saving pending events: %s", exc)

    def queue_event(self, event: Dict[str, Any]) -> None:
        with self._lock:
            items = self._load_pending()
            items.append(event)
            self._save_pending(items)

    def flush_pending(self) -> int:
        if not self.cfg.enabled or self.cfg.is_paused or not self.notifier.is_configured():
            return 0
        with self._lock:
            items = self._load_pending()
            if not items:
                return 0
            remaining: List[Dict[str, Any]] = []
            sent = 0
            for idx, ev in enumerate(items):
                msg = format_event_message(ev, self.hostname, delayed=True)
                if not msg:
                    continue
                res = self.notifier.send_message(msg)
                if res.ok:
                    sent += 1
                else:
                    remaining = items[idx:]
                    break
            self._save_pending(remaining)
            return sent

    def process_event(self, raw_event: Dict[str, Any], queue_on_fail: bool = True) -> bool:
        etype = raw_event.get("event")
        if etype not in ALLOWED_EVENTS:
            logger.warning("Rejected unsupported event type: %r", etype)
            return False

        if not self.is_event_allowed_by_config(etype):
            logger.info("Ignored event %s (monitoring disabled or paused).", etype)
            return False

        now = time.monotonic()
        with self._lock:
            if etype == "youtube_start":
                vid = sanitize_text(raw_event.get("video_id") or "", 32)
                if self._is_youtube_duplicate(vid, now):
                    logger.debug("Debounced duplicate YouTube event for video %s", vid)
                    return True

        event = dict(raw_event)
        event.setdefault("timestamp", datetime.now(timezone.utc).astimezone().strftime("%Y-%m-%d %H:%M:%S"))
        msg = format_event_message(event, self.hostname, delayed=False)
        if not msg:
            return False

        if not self.notifier.is_configured():
            logger.warning("Telegram bot token/chat_id not configured yet; skipping delivery.")
            return False

        res = self.notifier.send_message(msg)
        if res.ok:
            if etype != "system_shutdown":
                self.flush_pending()
            return True

        logger.warning("Telegram send failed for %s: %s", etype, res.error)
        if queue_on_fail:
            self.queue_event(event)
        return False


def serve_daemon() -> int:
    cfg = ControlConfig.load()
    notifier = TelegramClient(cfg.telegram_bot_token, cfg.telegram_chat_id, cfg.telegram_timeout_seconds)
    processor = EventProcessor(cfg, notifier)

    sock_path = Path(cfg.socket_path)
    sock_path.parent.mkdir(parents=True, exist_ok=True)
    if sock_path.exists():
        sock_path.unlink()

    srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    srv.bind(str(sock_path))
    # Allow local user native messaging host to write events while secrets stay root/ehotcontrol 0600
    os.chmod(sock_path, 0o666)
    srv.listen(16)
    srv.settimeout(2.0)

    stop_event = threading.Event()

    def _handle_sig(_signum: int, _frame: Any) -> None:
        stop_event.set()

    signal.signal(signal.SIGTERM, _handle_sig)
    signal.signal(signal.SIGINT, _handle_sig)

    logger.info("EHOT OS Control agent listening on %s", sock_path)
    last_flush = 0.0

    try:
        while not stop_event.is_set():
            now = time.monotonic()
            if now - last_flush > 30.0:
                processor.flush_pending()
                last_flush = now
            try:
                conn, _ = srv.accept()
            except socket.timeout:
                continue
            with conn:
                conn.settimeout(2.0)
                data = conn.recv(MAX_SOCKET_PAYLOAD_BYTES)
                if not data:
                    continue
                try:
                    payload = json.loads(data.decode("utf-8"))
                except ValueError:
                    logger.warning("Invalid JSON received on socket")
                    continue
                if isinstance(payload, dict):
                    # Reload config dynamically so pause toggle takes effect immediately
                    processor.cfg = ControlConfig.load()
                    processor.notifier = TelegramClient(
                        processor.cfg.telegram_bot_token,
                        processor.cfg.telegram_chat_id,
                        processor.cfg.telegram_timeout_seconds,
                    )
                    processor.process_event(payload)
    finally:
        srv.close()
        if sock_path.exists():
            sock_path.unlink()
    return 0


if __name__ == "__main__":
    raise SystemExit(serve_daemon())
