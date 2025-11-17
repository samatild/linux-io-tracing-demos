#!/usr/bin/env python3
"""
Lab 2 web server: simple "news" page that writes to disk on each request.

This is intentionally similar to the Lab 1 server, but here the slowdown
comes from an external I/O delay mechanism (e.g. kprobes on VFS calls)
that you can enable/disable outside of this lab.
"""

import os
import sys
import time
from http.server import HTTPServer, BaseHTTPRequestHandler

PORT = 8000
WORKDIR = "/opt/iolab2"
PAGE_IO_FILE = os.path.join(WORKDIR, "page_render.tmp")
UPLOAD_DIR = os.path.join(WORKDIR, "uploads")

# Amount of data (in MB) written per request to make the page meaningfully
# dependent on disk performance. You can override with IOLAB2_PAGE_WRITE_MB.
PAGE_WRITE_MB = int(os.environ.get("IOLAB2_PAGE_WRITE_MB", "32"))

os.makedirs(WORKDIR, exist_ok=True)
os.makedirs(UPLOAD_DIR, exist_ok=True)


def simulate_page_disk_io():
    """Write PAGE_WRITE_MB to disk to make each page view do real I/O."""
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

    try:
        os.sync()
    except Exception:
        pass

    try:
        os.remove(PAGE_IO_FILE)
    except OSError:
        pass


class Lab2Handler(BaseHTTPRequestHandler):
    def _render_homepage(self):
        return """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Lab 2 - Hidden I/O Delay</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    :root {
      --bg: #020617;
      --bg-elevated: #020617;
      --accent: #38bdf8;
      --border-subtle: rgba(148,163,184,0.35);
      --text-main: #e5e7eb;
      --text-muted: #9ca3af;
      --danger: #fb7185;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: system-ui, -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
      font-size: 16px;
      background: radial-gradient(circle at top, #1f2937 0, #020617 45%, #020617 100%);
      color: var(--text-main);
      min-height: 100vh;
      display: flex;
      flex-direction: column;
    }
    header {
      border-bottom: 1px solid var(--border-subtle);
      background: rgba(15,23,42,0.98);
      position: sticky;
      top: 0;
      z-index: 10;
    }
    .nav {
      max-width: 960px;
      margin: 0 auto;
      padding: 14px 20px;
      display: flex;
      align-items: center;
      justify-content: space-between;
    }
    .logo {
      display: flex;
      align-items: center;
      gap: 10px;
      font-weight: 600;
      letter-spacing: 0.04em;
    }
    .logo-mark {
      width: 26px;
      height: 26px;
      border-radius: 999px;
      background: radial-gradient(circle at 30% 20%, #e5e7eb 0, #38bdf8 30%, #0ea5e9 60%, #0f172a 100%);
      box-shadow: 0 0 20px rgba(56,189,248,0.7);
    }
    .logo span {
      font-size: 13px;
      color: var(--text-muted);
    }
    .nav-pill {
      border-radius: 999px;
      border: 1px solid var(--border-subtle);
      padding: 4px 10px;
      font-size: 11px;
      color: var(--text-muted);
    }
    main {
      flex: 1;
    }
    .shell {
      max-width: 960px;
      margin: 0 auto;
      padding: 24px 20px 40px;
    }
    .hero {
      display: grid;
      grid-template-columns: minmax(0, 3fr) minmax(0, 2.4fr);
      gap: 24px;
      align-items: stretch;
    }
    @media (max-width: 820px) {
      .hero {
        grid-template-columns: minmax(0, 1fr);
      }
    }
    .eyebrow {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      font-size: 12px;
      padding: 4px 10px;
      border-radius: 999px;
      background: rgba(15,23,42,0.9);
      border: 1px solid var(--border-subtle);
      margin-bottom: 10px;
    }
    .eyebrow span {
      padding: 1px 7px;
      border-radius: 999px;
      background: rgba(56,189,248,0.18);
      color: var(--accent);
    }
    h1 {
      font-size: clamp(24px, 2.6vw, 30px);
      line-height: 1.2;
      margin: 6px 0 10px;
    }
    .hero-sub {
      font-size: 15px;
      color: var(--text-muted);
      line-height: 1.6;
    }
    .hero-actions {
      margin-top: 18px;
      display: flex;
      flex-wrap: wrap;
      gap: 12px;
      align-items: center;
    }
    .btn-primary {
      border-radius: 999px;
      border: none;
      padding: 9px 16px;
      font-size: 14px;
      font-weight: 500;
      color: #0f172a;
      background: linear-gradient(135deg, #38bdf8, #22c55e);
      cursor: pointer;
      display: inline-flex;
      align-items: center;
      gap: 6px;
      box-shadow: 0 8px 24px rgba(15,23,42,0.8);
    }
    .btn-primary:hover {
      filter: brightness(1.03);
    }
    .hero-note {
      margin-top: 10px;
      font-size: 11px;
      color: var(--text-muted);
    }
    .panel {
      border-radius: 16px;
      padding: 14px 16px 14px;
      border: 1px solid var(--border-subtle);
      background: radial-gradient(circle at top left, rgba(56,189,248,0.16), rgba(15,23,42,0.98));
      box-shadow: 0 18px 45px rgba(15,23,42,0.9);
      font-size: 14px;
    }
    .panel-title {
      font-size: 12px;
      text-transform: uppercase;
      letter-spacing: 0.12em;
      color: var(--text-muted);
      margin-bottom: 6px;
    }
    .status-row {
      display: flex;
      align-items: center;
      justify-content: space-between;
      margin-bottom: 8px;
    }
    .status-label {
      display: flex;
      flex-direction: column;
      gap: 2px;
      font-size: 12px;
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
    .status-meter {
      margin-top: 8px;
      height: 6px;
      border-radius: 999px;
      background: rgba(15,23,42,0.9);
      position: relative;
      overflow: hidden;
    }
    .status-meter-fill {
      position: absolute;
      left: 0;
      top: 0;
      bottom: 0;
      width: 5%;
      border-radius: inherit;
      background: linear-gradient(90deg, #22c55e, #38bdf8, #f97316);
      transition: width 260ms ease-out;
    }
    .status-footer {
      margin-top: 8px;
      font-size: 11px;
      color: var(--text-muted);
    }
    .cards {
      margin-top: 26px;
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 16px;
    }
    @media (max-width: 820px) {
      .cards {
        grid-template-columns: minmax(0, 1fr);
      }
    }
    .card {
      border-radius: 14px;
      border: 1px solid var(--border-subtle);
      background: linear-gradient(145deg, rgba(15,23,42,0.98), rgba(15,23,42,0.96));
      padding: 12px 14px 14px;
      font-size: 13px;
      color: var(--text-muted);
    }
    .card-tag {
      font-size: 11px;
      text-transform: uppercase;
      letter-spacing: 0.14em;
      color: var(--text-muted);
      margin-bottom: 4px;
    }
    .card-title {
      font-size: 13px;
      font-weight: 500;
      color: var(--text-main);
      margin-bottom: 4px;
    }
    .upload-box {
      margin-top: 26px;
      border-radius: 16px;
      border: 1px dashed rgba(148,163,184,0.6);
      background: rgba(15,23,42,0.9);
      padding: 16px 16px 14px;
      font-size: 14px;
    }
    .upload-header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 8px;
      margin-bottom: 10px;
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
      margin-bottom: 8px;
    }
    .upload-row input[type=file] {
      font-size: 13px;
      max-width: 260px;
    }
    .upload-row button {
      border-radius: 999px;
      border: 1px solid rgba(148,163,184,0.6);
      background: rgba(15,23,42,0.9);
      color: var(--text-main);
      padding: 7px 12px;
      font-size: 13px;
      cursor: pointer;
    }
    .upload-row button:hover {
      border-color: var(--accent);
    }
    #upload-status {
      margin-top: 4px;
      font-size: 12px;
    }
    .success { color: #4ade80; }
    .error { color: #fb7185; }
    #upload-progress {
      width: 100%;
      height: 8px;
      margin-top: 6px;
      border-radius: 999px;
      overflow: hidden;
      background: rgba(15,23,42,0.95);
    }
    #upload-progress::-webkit-progress-bar {
      background: transparent;
    }
    #upload-progress::-webkit-progress-value {
      background: linear-gradient(90deg, #22c55e, #38bdf8);
    }
    #upload-progress::-moz-progress-bar {
      background: linear-gradient(90deg, #22c55e, #38bdf8);
    }
    footer {
      border-top: 1px solid var(--border-subtle);
      padding: 10px 20px 16px;
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
        I/O LAB<span>lab 2</span>
      </div>
      <div class="nav-pill">Hidden latency experiment</div>
    </div>
  </header>
  <main>
    <div class="shell">
      <section class="hero">
        <div class="hero-copy">
          <div class="eyebrow">
            Lab 2
            <span>Kernel-induced delay</span>
          </div>
          <h1>Sometimes this page is fast. Sometimes it feels stuck. Nothing changed in the code.</h1>
          <p class="hero-sub">
            This lab is focused on observation, not configuration. A low-level mechanism is
            occasionally slowing down filesystem operations on this host. Your goal is to
            use standard tools to prove where the time is spent and how it affects this
            otherwise simple web application.
          </p>
          <div class="hero-actions">
            <button class="btn-primary" onclick="location.reload()">
              Refresh page
            </button>
          </div>
          <p class="hero-note">
            Approach this like a production incident: correlate what you see in the browser
            with metrics from the operating system and explain the chain from click to disk.
          </p>
        </div>
        <aside class="panel" aria-label="Server status">
          <div class="panel-title">Server-side timing</div>
          <div class="status-row">
            <div class="status-label">
              <div>Last page view</div>
              <small>End-to-end server work</small>
            </div>
            <div class="status-chip">
              <span class="status-dot" id="status-dot"></span>
              <span id="status-chip-text">Measuring…</span>
            </div>
          </div>
          <div class="status-row">
            <div class="status-label">
              <div>Render time</div>
              <small>Measured on the server</small>
            </div>
            <div class="status-value" id="status-latency">–</div>
          </div>
          <div class="status-meter">
            <div id="status-meter-fill" class="status-meter-fill"></div>
          </div>
          <div class="status-footer">
            When this metric spikes, dig deeper: is the CPU busy, the network congested,
            or are system calls blocked on something slower underneath?
          </div>
        </aside>
      </section>

      <section class="cards" aria-label="Lab 2 prompts">
        <article class="card">
          <div class="card-tag">Question</div>
          <div class="card-title">Where is the bottleneck?</div>
          <p class="card-body">
            Use tools like <code>iostat</code>, <code>pidstat</code>, and <code>strace</code>
            to decide whether latency is coming from CPU, memory, disk, or something else
            in the kernel path. Support your answer with concrete measurements.
          </p>
        </article>
        <article class="card">
          <div class="card-tag">Question</div>
          <div class="card-title">What changed between fast and slow phases?</div>
          <p class="card-body">
            Capture a "fast" sample and a "slow" sample of system metrics. Compare process
            states, run queue length, and I/O wait to explain what is different.
          </p>
        </article>
        <article class="card">
          <div class="card-tag">Question</div>
          <div class="card-title">How would you detect this in production?</div>
          <p class="card-body">
            Sketch a minimal set of dashboards or alerts that would help you notice that a
            kernel-level delay had been introduced into filesystem operations.
          </p>
        </article>
      </section>
      <section class="upload-box" aria-label="Upload probe">
        <div class="upload-header">
          <div>
            <strong>Upload probe (disk write test)</strong><br>
            <span>Optional: send a file and watch how long the server takes to persist it.</span>
          </div>
          <span style="font-size:11px;color:var(--text-muted);">Uses a simple /upload endpoint on this server.</span>
        </div>
        <form id="uploadForm" method="post" enctype="multipart/form-data">
          <div class="upload-row">
            <input type="file" name="file" id="fileInput" required>
            <button type="submit">Upload file</button>
          </div>
          <progress id="upload-progress" value="0" max="100" style="display:none;"></progress>
          <div id="upload-status"></div>
        </form>
      </section>
    </div>
  </main>
  <footer>
    Lab 2 · I/O delay experiment · Browse over time and explain why this simple page sometimes stalls.
  </footer>
  <script>
    window.SERVER_RENDER_MS = {SERVER_RENDER_MS};

    window.addEventListener('load', () => {
      let t = typeof window.SERVER_RENDER_MS === 'number'
        ? Math.round(window.SERVER_RENDER_MS)
        : 0;

      const statusLatency = document.getElementById('status-latency');
      const statusMeterFill = document.getElementById('status-meter-fill');
      const statusDot = document.getElementById('status-dot');
      const statusChipText = document.getElementById('status-chip-text');

      if (!Number.isFinite(t) || t < 0) {
        t = 0;
      }

      statusLatency.textContent = t + ' ms';

      const clamped = Math.max(0, Math.min(5000, t));
      const pct = 5 + (clamped / 5000) * 95;
      statusMeterFill.style.width = pct + '%';

      if (t > 1500) {
        statusDot.classList.add('busy');
        statusChipText.textContent = 'Slow phase';
      } else if (t > 700) {
        statusDot.classList.add('busy');
        statusChipText.textContent = 'Moderate delay';
      } else {
        statusDot.classList.remove('busy');
        statusChipText.textContent = 'Fast phase';
      }
    });
    // Upload probe logic
    const uploadForm = document.getElementById('uploadForm');
    const uploadStatus = document.getElementById('upload-status');
    const uploadProgress = document.getElementById('upload-progress');

    if (uploadForm) {
      uploadForm.addEventListener('submit', (e) => {
        e.preventDefault();
        const fileInput = document.getElementById('fileInput');
        const file = fileInput.files[0];

        if (!file) {
          uploadStatus.innerHTML = '<span class="error">Please select a file.</span>';
          return;
        }

        const startTime = Date.now();
        let lastLoaded = 0;
        let lastTime = startTime;

        uploadProgress.style.display = 'block';
        uploadProgress.value = 0;

        const formData = new FormData();
        formData.append('file', file);

        const xhr = new XMLHttpRequest();

        xhr.upload.addEventListener('progress', (ev) => {
          if (ev.lengthComputable) {
            const percentComplete = (ev.loaded / ev.total) * 100;
            uploadProgress.value = percentComplete;

            const currentTime = Date.now();
            const timeDiff = (currentTime - lastTime) / 1000;
            const loadedDiff = ev.loaded - lastLoaded;

            lastLoaded = ev.loaded;
            lastTime = currentTime;

            const currentSpeedMBps = timeDiff > 0 ? (loadedDiff / 1024 / 1024 / timeDiff).toFixed(2) : 0;
            const avgSpeedMBps = ((ev.loaded / 1024 / 1024) / ((currentTime - startTime) / 1000)).toFixed(2);
            const uploadedMB = (ev.loaded / 1024 / 1024).toFixed(2);
            const totalMB = (ev.total / 1024 / 1024).toFixed(2);

            uploadStatus.innerHTML = `
              <strong>Uploading ${file.name}</strong><br>
              Progress: ${uploadedMB} / ${totalMB} MB (${percentComplete.toFixed(1)}%)<br>
              <span style="color:#38bdf8;"><strong>Current speed: ${currentSpeedMBps} MB/s</strong></span><br>
              Average speed: ${avgSpeedMBps} MB/s
            `;
          }
        });

        xhr.addEventListener('load', () => {
          const duration = ((Date.now() - startTime) / 1000).toFixed(2);
          const avgSpeedMBps = (file.size / 1024 / 1024 / duration).toFixed(2);
          const fileSizeMB = (file.size / 1024 / 1024).toFixed(2);

          if (xhr.status === 200) {
            uploadStatus.innerHTML = `
              <span class="success">
                <strong>Upload complete</strong><br>
                File: ${file.name} (${fileSizeMB} MB)<br>
                Time: ${duration}s<br>
                Average speed: ${avgSpeedMBps} MB/s
              </span>
            `;
          } else {
            uploadStatus.innerHTML = '<span class="error">Upload failed: ' + xhr.statusText + '</span>';
          }
          uploadProgress.style.display = 'none';
        });

        xhr.addEventListener('error', () => {
          uploadStatus.innerHTML = '<span class="error">Upload failed - network error.</span>';
          uploadProgress.style.display = 'none';
        });

        xhr.open('POST', '/upload');
        xhr.send(formData);
      });
    }
  </script>
</body>
</html>"""

    def do_GET(self):
        if self.path == "/" or self.path.startswith("/index"):
            start = time.time()
            simulate_page_disk_io()
            duration_ms = int((time.time() - start) * 1000)

            self.send_response(200)
            self.send_header("Content-type", "text/html")
            self.send_header("X-Page-Render-Time-ms", str(duration_ms))
            self.end_headers()

            html = self._render_homepage()
            html = html.replace("{SERVER_RENDER_MS}", str(duration_ms))
            self.wfile.write(html.encode("utf-8"))
        else:
            self.send_error(404, "File not found")

    def do_POST(self):
        """Handle file uploads for the Lab 2 upload probe."""
        if self.path != "/upload":
            self.send_error(404, "Not found")
            return

        try:
            content_length = int(self.headers.get("Content-Length", "0"))
            if content_length <= 0:
                self.send_error(400, "Missing or invalid Content-Length")
                return

            content_type = self.headers.get("Content-Type", "")
            if "multipart/form-data" not in content_type:
                self.send_error(400, "Expected multipart/form-data")
                return

            # Extract boundary from header
            if "boundary=" not in content_type:
                self.send_error(400, "Missing multipart boundary")
                return
            boundary = content_type.split("boundary=")[1].encode()

            # Read the full body
            data = self.rfile.read(content_length)

            file_path = os.path.join(UPLOAD_DIR, f"upload_{os.getpid()}.tmp")
            fd = os.open(
                file_path,
                os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_SYNC,
                0o644,
            )

            try:
                # Split on boundary and search for the part containing file data
                parts = data.split(boundary)
                for part in parts:
                    if b"filename=" in part:
                        header_end = part.find(b"\r\n\r\n")
                        if header_end != -1:
                            file_data = part[header_end + 4 :]
                            # Trim trailing CRLF/boundary markers
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

            except Exception:
                try:
                    os.close(fd)
                    os.remove(file_path)
                except Exception:
                    pass
                raise

        except Exception as e:
            print(f"Upload error: {e}", file=sys.stderr)
            self.send_error(500, "Upload failed")

    def log_message(self, format, *args):
        sys.stdout.write("%s - - [%s] %s\n" %
                         (self.address_string(),
                          self.log_date_time_string(),
                          format % args))
        sys.stdout.flush()


def run_server():
    server_address = ("", PORT)
    httpd = HTTPServer(server_address, Lab2Handler)
    print(f"Lab 2 server running on http://0.0.0.0:{PORT}")
    print(f"Working directory: {WORKDIR}")
    sys.stdout.flush()
    httpd.serve_forever()


if __name__ == "__main__":
    run_server()


