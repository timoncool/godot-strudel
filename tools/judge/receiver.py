"""Приёмник эталона: страница Булки шлёт сюда JSON, он ложится на диск.

Нужен только на время снятия эталона. В поставку плагина не входит.
Запуск:  python receiver.py [порт]
"""

import sys
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

HERE = Path(__file__).resolve().parent
GOLDEN = HERE / "golden"


class Handler(BaseHTTPRequestHandler):
    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "*")
        self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")

    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.end_headers()

    # Файлы, которые страница вправе забрать сама (чтобы не слать их врезкой в код).
    SERVED = {
        "corpus": HERE / "corpus.json",
        "track": HERE.parent.parent / "examples" / "full_track" / "kuvshinka.js",
        "effects": HERE / "effects.json",
    }

    def do_GET(self):
        name = self.path.strip("/") or "corpus"
        src = self.SERVED.get(name)
        if src is None:
            src = HERE / f"{name}.json"
        if not src.is_file():
            self.send_response(404)
            self._cors()
            self.end_headers()
            return
        body = src.read_bytes()
        self.send_response(200)
        self._cors()
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length)
        name = self.path.strip("/") or "dump"
        name = "".join(c for c in name if c.isalnum() or c in "-_.")
        GOLDEN.mkdir(parents=True, exist_ok=True)
        out = GOLDEN / f"{name}.json"
        try:
            parsed = json.loads(raw.decode("utf-8"))
            out.write_text(json.dumps(parsed, ensure_ascii=False, indent=1), encoding="utf-8")
            msg = f"ok {out.name} {out.stat().st_size} bytes"
        except Exception as exc:  # noqa: BLE001
            out = GOLDEN / f"{name}.raw"
            out.write_bytes(raw)
            msg = f"raw {out.name}: {exc}"
        print(msg, flush=True)
        self.send_response(200)
        self._cors()
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.end_headers()
        self.wfile.write(msg.encode("utf-8"))

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 4199
    print(f"receiver on http://127.0.0.1:{port} -> {GOLDEN}", flush=True)
    HTTPServer(("127.0.0.1", port), Handler).serve_forever()
