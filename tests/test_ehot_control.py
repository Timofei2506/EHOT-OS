import io
import json
import socket
import sys
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "modules" / "ehot-control" / "agent"))
sys.path.insert(0, str(REPO_ROOT / "modules" / "ehot-control" / "native-host"))

from config import ControlConfig  # noqa: E402
from ehot_control_agent import ALLOWED_EVENTS, EventProcessor, format_event_message  # noqa: E402
from ehot_native_host import forward_to_daemon, read_native_message, write_native_message  # noqa: E402
from telegram_client import TelegramClient  # noqa: E402


class DummyNotifier:
    def __init__(self, should_succeed: bool = True) -> None:
        self.should_succeed = should_succeed
        self.messages: list[str] = []

    def is_configured(self) -> bool:
        return True

    def send_message(self, text: str):
        from telegram_client import TelegramResult

        if self.should_succeed:
            self.messages.append(text)
            return TelegramResult(ok=True, status_code=200)
        return TelegramResult(ok=False, status_code=0, error="offline")


def test_only_four_events_are_allowed(tmp_path):
    assert ALLOWED_EVENTS == {"youtube_start", "download_start", "system_boot", "system_shutdown"}
    cfg = ControlConfig(state_dir=str(tmp_path), pause_flag_path=str(tmp_path / "paused"))
    notifier = DummyNotifier()
    proc = EventProcessor(cfg, notifier, hostname="lenovo-test")

    assert proc.process_event({"event": "keystroke"}) is False
    assert proc.process_event({"event": "screenshot"}) is False
    assert proc.process_event({"event": "arbitrary_url", "url": "https://example.com"}) is False
    assert notifier.messages == []


def test_youtube_debounce_and_download_sanitization(tmp_path):
    cfg = ControlConfig(state_dir=str(tmp_path), pause_flag_path=str(tmp_path / "paused"))
    notifier = DummyNotifier()
    proc = EventProcessor(cfg, notifier, hostname="lenovo-test")

    assert proc.process_event({"event": "youtube_start", "video_id": "dQw4w9WgXcQ", "title": "Test Video"}) is True
    # Immediate duplicate navigation event for same video is debounced
    assert proc.process_event({"event": "youtube_start", "video_id": "dQw4w9WgXcQ", "title": "Test Video"}) is True
    assert len(notifier.messages) == 1

    # Download passes ONLY basename, stripping local path
    assert proc.process_event({
        "event": "download_start",
        "filename": "/home/Regzen/Downloads/archive.zip",
        "source_domain": "example.org",
    }) is True
    assert len(notifier.messages) == 2
    assert "archive.zip" in notifier.messages[1]
    assert "/home/Regzen" not in notifier.messages[1]


def test_pause_flag_stops_notifications(tmp_path):
    pause_file = tmp_path / "paused"
    pause_file.touch()
    cfg = ControlConfig(state_dir=str(tmp_path), pause_flag_path=str(pause_file))
    notifier = DummyNotifier()
    proc = EventProcessor(cfg, notifier, hostname="lenovo-test")

    assert proc.process_event({"event": "system_boot"}) is False
    assert notifier.messages == []


def test_offline_shutdown_queues_and_flushes_on_next_boot(tmp_path):
    cfg = ControlConfig(state_dir=str(tmp_path), pause_flag_path=str(tmp_path / "paused"))
    offline_notifier = DummyNotifier(should_succeed=False)
    proc = EventProcessor(cfg, offline_notifier, hostname="lenovo-test")

    assert proc.process_event({"event": "system_shutdown"}) is False
    assert (tmp_path / "pending_events.json").exists()

    online_notifier = DummyNotifier(should_succeed=True)
    proc2 = EventProcessor(cfg, online_notifier, hostname="lenovo-test")
    assert proc2.process_event({"event": "system_boot"}) is True
    assert len(online_notifier.messages) == 2
    assert any("Выключается" in m or "выключается" in m for m in online_notifier.messages)
    assert any("включён" in m for m in online_notifier.messages)


def test_native_messaging_framing_and_socket_strip(tmp_path):
    buf = io.BytesIO()
    sample = {"event": "youtube_start", "video_id": "abc123", "title": "Cool Video", "secret_cookie": "drop_me"}
    write_native_message(buf, sample)
    buf.seek(0)
    decoded = read_native_message(buf)
    assert decoded == sample

    sock_path = str(tmp_path / "events.sock")
    received = []

    srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    srv.bind(sock_path)
    srv.listen(1)

    def accept_one():
        conn, _ = srv.accept()
        with conn:
            received.append(json.loads(conn.recv(4096).decode("utf-8")))

    t = threading.Thread(target=accept_one, daemon=True)
    t.start()
    assert forward_to_daemon(sample, socket_path=sock_path) is True
    assert forward_to_daemon({"event": "forbidden_history"}, socket_path=sock_path) is False
    t.join(timeout=2)
    srv.close()

    assert len(received) == 1
    assert "secret_cookie" not in received[0]
    assert received[0]["video_id"] == "abc123"


def test_telegram_client_posts_expected_json():
    captured = {}

    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            length = int(self.headers.get("Content-Length", "0"))
            captured["path"] = self.path
            captured["body"] = json.loads(self.rfile.read(length).decode("utf-8"))
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"ok": true, "result": {"message_id": 1}}')

        def log_message(self, *_args):
            pass

    server = HTTPServer(("127.0.0.1", 0), Handler)
    t = threading.Thread(target=server.serve_forever, daemon=True)
    t.start()
    try:
        client = TelegramClient("dummy_token", "999999")
        client.API_BASE = f"http://127.0.0.1:{server.server_address[1]}"
        res = client.send_message("Привет от EHOT OS")
        assert res.ok is True
        assert captured["path"] == "/botdummy_token/sendMessage"
        assert captured["body"]["chat_id"] == "999999"
        assert captured["body"]["text"] == "Привет от EHOT OS"
    finally:
        server.shutdown()


def test_format_event_rejects_unknown():
    assert format_event_message({"event": "unknown"}, "host") is None
