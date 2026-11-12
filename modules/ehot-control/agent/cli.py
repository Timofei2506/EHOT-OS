#!/usr/bin/env python3
"""
EHOT OS Control CLI Helper (`ehot-control-cli`).
Supports:
  - status
  - test
  - event boot|shutdown (with retry for boot)
"""

from __future__ import annotations

import argparse
import json
import socket
import sys
import time
from pathlib import Path

AGENT_DIR = Path(__file__).resolve().parent
if str(AGENT_DIR) not in sys.path:
    sys.path.insert(0, str(AGENT_DIR))

from config import ControlConfig  # noqa: E402
from ehot_control_agent import EventProcessor  # noqa: E402
from telegram_client import TelegramClient  # noqa: E402


def cmd_status() -> int:
    cfg = ControlConfig.load()
    print(f"Enabled: {cfg.enabled}")
    print(f"Paused locally: {cfg.is_paused}")
    print(f"Telegram configured: {bool(cfg.telegram_bot_token and cfg.telegram_chat_id)}")
    print(f"Socket exists: {Path(cfg.socket_path).exists()} ({cfg.socket_path})")
    return 0


def cmd_test() -> int:
    cfg = ControlConfig.load()
    client = TelegramClient(cfg.telegram_bot_token, cfg.telegram_chat_id, cfg.telegram_timeout_seconds)
    if not client.is_configured():
        print("Ошибка: не заданы TELEGRAM_BOT_TOKEN и TELEGRAM_CHAT_ID. Запустите: sudo ehot-control-setup", file=sys.stderr)
        return 1
    res = client.send_message(f"✅ EHOT OS [{socket.gethostname()}]: Тестовое сообщение — связь с Telegram настроена.")
    if res.ok:
        print("Тестовое сообщение успешно отправлено в Telegram.")
        return 0
    print(f"Ошибка отправки в Telegram: {res.error}", file=sys.stderr)
    return 1


def cmd_event(kind: str, retries: int, delay: float) -> int:
    cfg = ControlConfig.load()
    client = TelegramClient(cfg.telegram_bot_token, cfg.telegram_chat_id, cfg.telegram_timeout_seconds)
    proc = EventProcessor(cfg, client)
    event_name = "system_boot" if kind == "boot" else "system_shutdown"

    if not cfg.enabled or cfg.is_paused:
        return 0

    for attempt in range(1, max(1, retries) + 1):
        # First try sending directly via Telegram (important during boot/shutdown)
        if proc.process_event({"event": event_name}, queue_on_fail=(attempt == retries)):
            return 0
        if attempt < retries:
            time.sleep(delay)

    # Also notify running socket daemon if reachable
    sock_path = Path(cfg.socket_path)
    if sock_path.exists():
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
                s.settimeout(1.5)
                s.connect(str(sock_path))
                s.sendall(json.dumps({"event": event_name}).encode("utf-8"))
        except OSError:
            pass
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="EHOT OS Control CLI")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("status")
    sub.add_parser("test")
    ev = sub.add_parser("event")
    ev.add_argument("kind", choices=["boot", "shutdown"])
    ev.add_argument("--retries", type=int, default=1)
    ev.add_argument("--delay", type=float, default=5.0)

    args = parser.parse_args()
    if args.command == "status":
        return cmd_status()
    if args.command == "test":
        return cmd_test()
    if args.command == "event":
        return cmd_event(args.kind, args.retries, args.delay)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
