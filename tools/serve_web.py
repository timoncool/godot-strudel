"""Отдаёт web-сборку с заголовками, которых требует Godot (COOP/COEP).

Обычный http.server не годится: без Cross-Origin-Isolation браузер не даёт
SharedArrayBuffer, и сборка с потоками не стартует.

    python tools/serve_web.py [порт] [папка]
"""
import sys
from functools import partial
from http.server import SimpleHTTPRequestHandler, HTTPServer


class Handler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 4200
    root = sys.argv[2] if len(sys.argv) > 2 else "build/web"
    print(f"web-сборка на http://127.0.0.1:{port}/index.html", flush=True)
    HTTPServer(("127.0.0.1", port), partial(Handler, directory=root)).serve_forever()
