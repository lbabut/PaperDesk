from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import json, socket, time

ROOT = Path(__file__).resolve().parent
HTML = ROOT / "index.html"

def reachable(port):
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=0.35):
            return True
    except OSError:
        return False

def memory():
    values = {}
    for line in Path("/proc/meminfo").read_text().splitlines():
        if ":" in line:
            key, value = line.split(":", 1)
            values[key] = int(value.strip().split()[0])
    total = values["MemTotal"]
    avail = values.get("MemAvailable", values.get("MemFree", 0))
    swap_total = values.get("SwapTotal", 0)
    swap_free = values.get("SwapFree", 0)
    return (
        f"{(total-avail)/total*100:.0f}%",
        f"{(swap_total-swap_free)/1024/1024:.1f}/{swap_total/1024/1024:.1f}G" if swap_total else "off",
    )

def status():
    uptime_s = float(Path("/proc/uptime").read_text().split()[0])
    ram, swap = memory()
    return {
        "uptime": f"{uptime_s/3600:.1f}h",
        "load": Path("/proc/loadavg").read_text().split()[0],
        "ram": ram,
        "swap": swap,
        "services": {
            "paperdesk": reachable(8090),
            "btc": reachable(8060),
            "roadster": reachable(8071),
            "cinema": reachable(8080),
            "muminki": reachable(8765),
            "irc": reachable(6667) and reachable(6697),
            "cockpit": reachable(9090),
        },
    }

class Handler(BaseHTTPRequestHandler):
    def send_bytes(self, code, payload, content_type):
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(payload)
    def do_GET(self):
        if self.path in ("/", "/index.html"):
            self.send_bytes(200, HTML.read_bytes(), "text/html; charset=utf-8")
        elif self.path == "/api/status":
            self.send_bytes(200, json.dumps(status()).encode(), "application/json")
        elif self.path == "/health":
            self.send_bytes(200, b"ok", "text/plain")
        else:
            self.send_bytes(404, b"not found", "text/plain")
    def log_message(self, fmt, *args):
        pass

if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 80), Handler).serve_forever()
