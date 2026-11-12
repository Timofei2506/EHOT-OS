#!/usr/bin/env python3
"""
EHOT OS Control — Firefox Native Messaging Host (`com.ehotos.control`).
Reads length-prefixed JSON messages from Firefox stdin, filters strictly for
allowed event types (`youtube_start`, `download_start`), and forwards them to
the privileged `ehot-control` Unix socket without ever exposing Telegram secrets
to the browser process.
"""

from __future__ import annotations

import json
import os
import socket
import struct
import sys
from typing import Any, BinaryIO, Dict, Optional

DEFAULT_SOCKET_PATH = os.environ.get("EHOT_CONTROL_SOCKET", "/run/ehot-control/events.sock")
ALLOWED_BROWSER_EVENTS = frozenset({"youtube_start", "download_start"})
MAX_MSG_BYTES = 16384


def read_native_message(stream: BinaryIO) -> Optional[Dict[str, Any]]:
    raw_len = stream.read(4)
    if not raw_len or len(raw_len) < 4:
        return None
    msg_len = struct.unpack("<I", raw_len)[0]
    if msg_len == 0 or msg_len > MAX_MSG_BYTES:
        return None
    payload = stream.read(msg_len)
    if len(payload) < msg_len:
        return None
    obj = json.loads(payload.decode("utf-8"))
    return obj if isinstance(obj, dict) else None


def write_native_message(stream: BinaryIO, message: Dict[str, Any]) -> None:
    encoded = json.dumps(message, ensure_ascii=False).encode("utf-8")
    stream.write(struct.pack("<I", len(encoded)))
    stream.write(encoded)
    stream.flush()


def forward_to_daemon(event: Dict[str, Any], socket_path: str = DEFAULT_SOCKET_PATH) -> bool:
    etype = event.get("event")
    if etype not in ALLOWED_BROWSER_EVENTS:
        return False

    # Strip any unexpected fields for strict privacy isolation
    sanitized: Dict[str, Any] = {"event": etype}
    if etype == "youtube_start":
        sanitized["video_id"] = str(event.get("video_id", ""))[:32]
        sanitized["title"] = str(event.get("title", ""))[:160]
    elif etype == "download_start":
        sanitized["filename"] = str(event.get("filename", ""))[:180]
        sanitized["source_domain"] = str(event.get("source_domain", ""))[:100]

    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
        sock.settimeout(2.0)
        sock.connect(socket_path)
        sock.sendall(json.dumps(sanitized, ensure_ascii=False).encode("utf-8"))
    return True


def main() -> int:
    while True:
        try:
            msg = read_native_message(sys.stdin.buffer)
        except (ValueError, OSError):
            write_native_message(sys.stdout.buffer, {"ok": False, "error": "invalid_message"})
            continue

        if msg is None:
            break

        if msg.get("event") not in ALLOWED_BROWSER_EVENTS:
            write_native_message(sys.stdout.buffer, {"ok": False, "error": "unsupported_event"})
            continue

        try:
            ok = forward_to_daemon(msg)
            write_native_message(sys.stdout.buffer, {"ok": ok})
        except OSError as exc:
            write_native_message(sys.stdout.buffer, {"ok": False, "error": str(exc)})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
