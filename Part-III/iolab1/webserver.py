#!/usr/bin/env python3
"""
Simple HTTP server with file upload capability for I/O lab.
Accepts file uploads and saves them with O_DIRECT flag to bypass cache.
"""

import os
import sys
import time
from http.server import HTTPServer, BaseHTTPRequestHandler

PORT = 8000
WORKDIR = "/opt/iolab"
UPLOAD_DIR = os.path.join(WORKDIR, "uploads")
PAGE_IO_FILE = os.path.join(WORKDIR, "page_render.tmp")

# How much disk to write (in MB) on each page view to simulate a disk-heavy web app.
# You can override with env var: IOLAB_PAGE_WRITE_MB=128
PAGE_WRITE_MB = int(os.environ.get("IOLAB_PAGE_WRITE_MB", "64"))

os.makedirs(UPLOAD_DIR, exist_ok=True)


def simulate_page_disk_io():
    """
    Simulate a disk-heavy page render by writing PAGE_WRITE_MB of data
    with O_SYNC so each write waits for disk. When BackupJob is running,
    this becomes dramatically slower and makes browsing feel sluggish.
    """
    if PAGE_WRITE_MB <= 0:
        return

    buf = b"\0" * (1024 * 1024)  # 1MB buffer

    fd = os.open(
        PAGE_IO_FILE,
        os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_SYNC,
        0o644,
    )
    try:
        for _ in range(PAGE_WRITE_MB):
            os.write(fd, buf)
    finally:
        os.close(fd)

    # Ensure data is on disk; ignore errors if sync is not supported
    try:
        os.sync()
    except Exception:
        pass

    # Clean up the temp file so we don't fill the disk
    try:
        os.remove(PAGE_IO_FILE)
    except OSError:
        pass


class UploadHandler(BaseHTTPRequestHandler):
    def _render_homepage(self):
        """Return the main HTML for the dummy website."""
        return """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <title>I/O Lab News Portal</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        :root {
            --bg: #0f172a;
            --bg-elevated: #020617;
            --accent: #38bdf8;
            --accent-soft: rgba(56,189,248,0.15);
            --border-subtle: rgba(148,163,184,0.25);
            --text-main: #e5e7eb;
            --text-muted: #9ca3af;
            --danger: #fb7185;
        }
        * { box-sizing: border-box; }
        body {
            margin: 0;
            font-family: system-ui, -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
            background: radial-gradient(circle at top, #1f2937 0, #020617 45%, #020617 100%);
            color: var(--text-main);
            min-height: 100vh;
            display: flex;
            flex-direction: column;
        }
        header {
            border-bottom: 1px solid var(--border-subtle);
            background: linear-gradient(90deg, rgba(15,23,42,0.98), rgba(15,23,42,0.98));
            backdrop-filter: blur(18px);
            position: sticky;
            top: 0;
            z-index: 10;
        }
        .nav {
            max-width: 1080px;
            margin: 0 auto;
            padding: 14px 20px;
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 16px;
        }
        .logo {
            display: flex;
            align-items: center;
            gap: 10px;
            font-weight: 600;
            letter-spacing: 0.03em;
        }
        .logo-mark {
            width: 28px;
            height: 28px;
            border-radius: 999px;
            background: radial-gradient(circle at 30% 20%, #e5e7eb 0, #38bdf8 30%, #0ea5e9 60%, #0f172a 100%);
            box-shadow: 0 0 24px rgba(56,189,248,0.7);
        }
        .logo span {
            font-size: 14px;
            color: var(--text-muted);
        }
        .nav-links {
            display: flex;
            gap: 18px;
            font-size: 14px;
        }
        .nav-links a {
            color: var(--text-muted);
            text-decoration: none;
            padding: 6px 0;
            position: relative;
        }
        .nav-links a::after {
            content: "";
            position: absolute;
            left: 0;
            bottom: -4px;
            width: 0;
            height: 2px;
            background: linear-gradient(90deg, #38bdf8, #22c55e);
            transition: width 160ms ease-out;
        }
        .nav-links a:hover {
            color: var(--text-main);
        }
        .nav-links a:hover::after {
            width: 100%;
        }
        .nav-pill {
            border-radius: 999px;
            border: 1px solid rgba(148,163,184,0.5);
            padding: 4px 12px;
            font-size: 12px;
            color: var(--text-muted);
            display: flex;
            align-items: center;
            gap: 6px;
        }
        .pill-dot {
            width: 7px;
            height: 7px;
            border-radius: 999px;
            background: var(--danger);
            box-shadow: 0 0 10px rgba(248,113,113,0.9);
        }
        main {
            flex: 1;
        }
        .shell {
            max-width: 1080px;
            margin: 0 auto;
            padding: 24px 20px 40px;
        }
        .hero {
            display: grid;
            grid-template-columns: minmax(0, 3fr) minmax(0, 2.6fr);
            gap: 28px;
            align-items: stretch;
        }
        @media (max-width: 880px) {
            .hero {
                grid-template-columns: minmax(0, 1fr);
            }
        }
        .hero-copy {
            padding-right: 10px;
        }
        .eyebrow {
            display: inline-flex;
            align-items: center;
            gap: 8px;
            font-size: 12px;
            padding: 4px 10px;
            border-radius: 999px;
            background: rgba(15,23,42,0.9);
            border: 1px solid rgba(148,163,184,0.35);
            margin-bottom: 10px;
        }
        .eyebrow span {
            padding: 1px 8px;
            border-radius: 999px;
            background: rgba(56,189,248,0.18);
            color: var(--accent);
        }
        h1 {
            font-size: clamp(26px, 3vw, 32px);
            line-height: 1.15;
            margin: 4px 0 10px;
        }
        .hero-sub {
            font-size: 14px;
            color: var(--text-muted);
            max-width: 34rem;
            line-height: 1.6;
        }
        .hero-metrics {
            display: flex;
            flex-wrap: wrap;
            gap: 18px;
            margin-top: 18px;
            font-size: 13px;
        }
        .metric {
            padding: 10px 12px;
            border-radius: 12px;
            border: 1px solid rgba(148,163,184,0.4);
            background: radial-gradient(circle at top left, rgba(56,189,248,0.16), rgba(15,23,42,0.85));
        }
        .metric strong {
            display: block;
            font-size: 20px;
        }
        .hero-actions {
            margin-top: 22px;
            display: flex;
            flex-wrap: wrap;
            gap: 12px;
            align-items: center;
        }
        .btn-primary {
            border-radius: 999px;
            border: none;
            padding: 10px 18px;
            font-size: 14px;
            font-weight: 500;
            color: #0f172a;
            background: linear-gradient(135deg, #38bdf8, #22c55e);
            cursor: pointer;
            display: inline-flex;
            align-items: center;
            gap: 8px;
            box-shadow: 0 8px 24px rgba(15,23,42,0.8);
        }
        .btn-primary:hover {
            filter: brightness(1.03);
        }
        .btn-ghost {
            border-radius: 999px;
            border: 1px solid rgba(148,163,184,0.5);
            background: transparent;
            color: var(--text-muted);
            padding: 9px 16px;
            font-size: 13px;
            cursor: pointer;
            display: inline-flex;
            align-items: center;
            gap: 6px;
        }
        .btn-ghost:hover {
            border-color: var(--accent);
            color: var(--text-main);
        }
        .hero-note {
            margin-top: 10px;
            font-size: 11px;
            color: var(--text-muted);
        }
        .panel {
            border-radius: 16px;
            padding: 16px 16px 14px;
            border: 1px solid var(--border-subtle);
            background: radial-gradient(circle at top left, rgba(56,189,248,0.16), rgba(15,23,42,0.98));
            box-shadow: 0 18px 45px rgba(15,23,42,0.9);
        }
        .panel-title {
            font-size: 13px;
            text-transform: uppercase;
            letter-spacing: 0.12em;
            color: var(--text-muted);
            margin-bottom: 6px;
        }
        .status-row {
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 10px;
            margin-bottom: 8px;
            font-size: 13px;
        }
        .status-label {
            display: flex;
            flex-direction: column;
            gap: 2px;
        }
        .status-chip {
            display: inline-flex;
            align-items: center;
            gap: 6px;
            padding: 4px 10px;
            border-radius: 999px;
            font-size: 11px;
            border: 1px solid rgba(148,163,184,0.55);
            background: rgba(15,23,42,0.95);
        }
        .status-dot {
            width: 7px;
            height: 7px;
            border-radius: 999px;
            background: #22c55e;
            box-shadow: 0 0 10px rgba(34,197,94,0.9);
        }
        .status-dot.busy {
            background: #fb7185;
            box-shadow: 0 0 12px rgba(248,113,113,0.85);
        }
        .status-value {
            font-size: 20px;
            font-weight: 600;
        }
        .status-meter {
            margin-top: 10px;
            height: 6px;
            border-radius: 999px;
            background: rgba(15,23,42,0.9);
            overflow: hidden;
            position: relative;
        }
        .status-meter-fill {
            position: absolute;
            left: 0;
            top: 0;
            bottom: 0;
            width: 5%;
            border-radius: inherit;
            background: linear-gradient(90deg, #22c55e, #38bdf8, #f97316);
            transition: width 280ms ease-out;
        }
        .status-footer {
            margin-top: 10px;
            font-size: 11px;
            color: var(--text-muted);
        }
        .cards {
            margin-top: 28px;
            display: grid;
            grid-template-columns: repeat(3, minmax(0, 1fr));
            gap: 18px;
        }
        @media (max-width: 880px) {
            .cards {
                grid-template-columns: minmax(0, 1fr);
            }
        }
        .card {
            border-radius: 16px;
            border: 1px solid var(--border-subtle);
            background: linear-gradient(145deg, rgba(15,23,42,0.98), rgba(15,23,42,0.96));
            padding: 14px 14px 16px;
            display: flex;
            flex-direction: column;
            gap: 6px;
        }
        .card-tag {
            font-size: 11px;
            text-transform: uppercase;
            letter-spacing: 0.14em;
            color: var(--text-muted);
        }
        .card-title {
            font-size: 14px;
            font-weight: 500;
        }
        .card-body {
            font-size: 12px;
            color: var(--text-muted);
            line-height: 1.6;
        }
        .card-footer {
            margin-top: 8px;
            display: flex;
            align-items: center;
            justify-content: space-between;
            font-size: 11px;
            color: var(--text-muted);
        }
        .chip {
            padding: 3px 8px;
            border-radius: 999px;
            border: 1px solid rgba(148,163,184,0.75);
        }
        .upload-box {
            margin-top: 24px;
            border-radius: 16px;
            border: 1px dashed rgba(148,163,184,0.6);
            background: rgba(15,23,42,0.9);
            padding: 16px 16px 14px;
        }
        .upload-header {
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 8px;
            margin-bottom: 10px;
            font-size: 13px;
        }
        .upload-header span {
            color: var(--text-muted);
            font-size: 12px;
        }
        .upload-row {
            display: flex;
            flex-wrap: wrap;
            gap: 10px;
            align-items: center;
        }
        .upload-row input[type=file] {
            font-size: 12px;
            max-width: 260px;
        }
        .upload-row button {
            border-radius: 999px;
            border: 1px solid rgba(148,163,184,0.6);
            background: rgba(15,23,42,0.9);
            color: var(--text-main);
            padding: 7px 12px;
            font-size: 12px;
            cursor: pointer;
        }
        .upload-row button:hover {
            border-color: var(--accent);
        }
        #status {
            margin-top: 10px;
            font-size: 12px;
        }
        .success { color: #4ade80; }
        .error { color: #fb7185; }
        #progress {
            width: 100%;
            height: 8px;
            margin-top: 8px;
            border-radius: 999px;
            overflow: hidden;
            background: rgba(15,23,42,0.95);
        }
        #progress::-webkit-progress-bar {
            background: transparent;
        }
        #progress::-webkit-progress-value {
            background: linear-gradient(90deg, #22c55e, #38bdf8);
        }
        #progress::-moz-progress-bar {
            background: linear-gradient(90deg, #22c55e, #38bdf8);
        }
        footer {
            border-top: 1px solid var(--border-subtle);
            padding: 10px 20px 18px;
            font-size: 11px;
            color: var(--text-muted);
            text-align: center;
            background: #020617;
        }
    </style>
</head>
<body>
    <header>
        <div class="nav">
            <div class="logo">
                <div class="logo-mark"></div>
                I/O LAB1 <span>Performance challenge</span>
            </div>
        </div>
    </header>
    <main>
        <div class="shell">
            <section class="hero">
                <div class="hero-copy">
                    <div class="eyebrow">
                        Live lab · <span>Performance challenge</span>
                    </div>
                    <h1>Why does this “news site” feel fast sometimes and slow others?</h1>
                    <p class="hero-sub">
                        This dummy news portal simulates a real production system under changing load.
                        Sometimes pages are snappy, sometimes they drag. Your task is to investigate
                        where the bottleneck is coming from and explain what part of the system is
                        actually slowing things down.
                    </p>
                    <div class="hero-metrics">
                        <div class="metric">
                            <strong id="metric-latency">–</strong>
                            Page render time
                        </div>
                        <div class="metric">
                            <strong id="metric-io">~{PAGE_WRITE_MB} MB</strong>
                            Disk written per view
                        </div>
                    </div>
                    <div class="hero-actions">
                        <button class="btn-primary" onclick="location.reload()">
                            Refresh page
                        </button>
                    </div>
                    <p class="hero-note">
                        First browse this site normally and get a feel for how it behaves.
                        Then, at some point during the lab, you'll be asked to explain why it
                        suddenly feels slower. Use your usual troubleshooting tools to figure out <em>where</em> the time is going.
                    </p>
                </div>
                <aside class="panel" aria-label="Server status">
                    <div class="panel-title">Server-side behaviour</div>
                    <div class="status-row">
                        <div class="status-label">
                            <div>Page generation</div>
                            <small id="status-mode">Baseline (no obvious bottleneck detected)</small>
                        </div>
                        <div class="status-chip">
                            <span class="status-dot" id="status-dot"></span>
                            <span id="status-chip-text">Responsive</span>
                        </div>
                    </div>
                    <div class="status-row">
                        <div class="status-label">
                            <div>Last page view</div>
                            <small>End-to-end server work</small>
                        </div>
                        <div class="status-value" id="status-latency">–</div>
                    </div>
                    <div class="status-meter">
                        <div id="status-meter-fill" class="status-meter-fill"></div>
                    </div>
                    <div class="status-footer">
                        Each navigation forces the server to do a significant amount of work.
                        Under certain conditions that work suddenly takes much longer.
                        Your mission: find out what the server is really waiting on and why it changes over time.
                    </div>
                </aside>
            </section>

            <section id="deep-dive" class="cards">
                <article class="card">
                    <div class="card-tag">Deep dive</div>
                    <div class="card-title">Chasing down slow requests</div>
                    <p class="card-body">
                        In real systems, slow pages are often symptoms of something else:
                        queued work, background tasks, or shared resources under pressure.
                        Your job is to connect what you see in the browser with what the
                        operating system is telling you.
                    </p>
                </article>
                <article class="card">
                    <div class="card-tag">Tutorial</div>
                    <div class="card-title">From “it’s slow” to a concrete cause</div>
                    <p class="card-body">
                        Use your normal toolbox (top, iostat, logs, tracing, etc.) to figure out
                        what this server is spending time on when you refresh the page. The
                        symptoms are in the browser; the answers live on the host.
                    </p>
                </article>
                <article class="card">
                    <div class="card-tag">Playbook</div>
                    <div class="card-title">Taming background work</div>
                    <p class="card-body">
                        Background jobs are essential, but they can quietly steal capacity from
                        interactive traffic. Think about how you would keep an environment like
                        this healthy in production when heavy maintenance tasks are running.
                    </p>
                </article>
            </section>
        </div>
    </main>
    <footer>
        I/O Lab · Performance challenge · Browse over time, observe when it slows down, and explain what changed.
    </footer>
    <script>
        // Server-measured render time (injected from Python)
        window.SERVER_RENDER_MS = {SERVER_RENDER_MS};

        // Use server-side timing primarily, fall back to client nav timing if needed
        window.addEventListener('load', () => {
            let t = typeof window.SERVER_RENDER_MS === 'number'
                ? Math.round(window.SERVER_RENDER_MS)
                : 0;

            if (!Number.isFinite(t) || t <= 0) {
                const navTiming = performance.getEntriesByType('navigation')[0];
                if (navTiming) {
                    t = Math.round(navTiming.duration);
                } else {
                    t = 0;
                }
            }

            const metricLatency = document.getElementById('metric-latency');
            const statusLatency = document.getElementById('status-latency');
            const statusMeterFill = document.getElementById('status-meter-fill');
            const statusMode = document.getElementById('status-mode');
            const statusDot = document.getElementById('status-dot');
            const statusChipText = document.getElementById('status-chip-text');

            metricLatency.textContent = t + ' ms';
            statusLatency.textContent = t + ' ms';

            const clamped = Math.max(0, Math.min(5000, t));
            const pct = 5 + (clamped / 5000) * 95;
            statusMeterFill.style.width = pct + '%';

            if (t > 1500) {
                statusMode.textContent = 'Heavy contention suspected';
                statusDot.classList.add('busy');
                statusChipText.textContent = 'Disk bound';
            } else if (t > 800) {
                statusMode.textContent = 'Moderate I/O pressure';
                statusDot.classList.add('busy');
                statusChipText.textContent = 'Under load';
            } else {
                statusMode.textContent = 'Baseline (no explicit contention detected)';
                statusDot.classList.remove('busy');
                statusChipText.textContent = 'Responsive';
            }
        });

    </script>
</body>
</html>"""

    def do_GET(self):
        """Serve the dummy website homepage, with disk I/O on each view."""
        if self.path == "/" or self.path.startswith("/index"):
            start = time.time()
            simulate_page_disk_io()
            duration_ms = int((time.time() - start) * 1000)

            self.send_response(200)
            self.send_header("Content-type", "text/html")
            self.send_header("X-Page-Render-Time-ms", str(duration_ms))
            self.end_headers()

            html = self._render_homepage()
            # Inject server-side metrics into the template
            html = html.replace("{PAGE_WRITE_MB}", str(PAGE_WRITE_MB))
            html = html.replace("{SERVER_RENDER_MS}", str(duration_ms))
            self.wfile.write(html.encode("utf-8"))
        else:
            self.send_error(404, "File not found")

    def do_POST(self):
        """Handle file upload (kept compatible with original lab)."""
        if self.path == "/upload":
            try:
                content_length = int(self.headers["Content-Length"])

                content_type = self.headers.get("Content-Type")
                if not content_type or "multipart/form-data" not in content_type:
                    self.send_error(400, "Invalid content type")
                    return

                boundary = content_type.split("boundary=")[1].encode()

                file_path = os.path.join(UPLOAD_DIR, f"upload_{os.getpid()}.tmp")

                fd = os.open(
                    file_path,
                    os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_SYNC,
                    0o644,
                )

                try:
                    data = self.rfile.read(content_length)

                    parts = data.split(boundary)
                    for part in parts:
                        if b"Content-Type:" in part or b"filename=" in part:
                            header_end = part.find(b"\r\n\r\n")
                            if header_end != -1:
                                file_data = part[header_end + 4 :]
                                if file_data.endswith(b"\r\n"):
                                    file_data = file_data[:-2]
                                os.write(fd, file_data)
                                break

                    os.close(fd)
                    try:
                        os.sync()
                    except Exception:
                        pass

                    self.send_response(200)
                    self.send_header("Content-type", "text/plain")
                    self.end_headers()
                    self.wfile.write(b"Upload successful")

                    try:
                        os.remove(file_path)
                    except OSError:
                        pass

                except Exception as e:
                    try:
                        os.close(fd)
                        os.remove(file_path)
                    except Exception:
                        pass
                    raise e

            except Exception as e:
                print(f"Upload error: {e}", file=sys.stderr)
                self.send_error(500, f"Upload failed: {str(e)}")
        else:
            self.send_error(404, "Not found")

    def log_message(self, format, *args):
        """Log requests to stdout"""
        sys.stdout.write("%s - - [%s] %s\n" %
                         (self.address_string(),
                          self.log_date_time_string(),
                          format % args))
        sys.stdout.flush()


def run_server():
    server_address = ('', PORT)
    httpd = HTTPServer(server_address, UploadHandler)
    print(f"Server running on http://0.0.0.0:{PORT}")
    print(f"Upload directory: {UPLOAD_DIR}")
    sys.stdout.flush()
    httpd.serve_forever()


if __name__ == '__main__':
    run_server()

