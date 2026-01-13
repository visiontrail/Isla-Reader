import csv
import hashlib
import hmac
import io
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, Cookie, Depends, HTTPException, Request, Response, status
from fastapi.responses import HTMLResponse, JSONResponse, StreamingResponse
from pydantic import BaseModel, Field

from ..config import Settings, get_settings
from ..logging_utils import get_logger
from ..metrics_store import MetricEvent, MetricsStore, get_metrics_store

router = APIRouter(tags=["metrics"])
logger = get_logger("metrics")


class MetricIngestPayload(BaseModel):
    interface: str
    status_code: int
    latency_ms: float
    request_bytes: int
    tokens: Optional[int] = None
    retry_count: int = 0
    source: str
    request_id: Optional[str] = None
    error_reason: Optional[str] = Field(default=None, max_length=500)
    timestamp: Optional[datetime] = Field(default=None)


class LoginRequest(BaseModel):
    username: str
    password: str


def _require_metrics_token(request: Request, settings: Settings) -> None:
    token = request.headers.get("x-metrics-key")
    expected = settings.resolved_metrics_token()
    if not expected:
        logger.warning("Metrics ingest rejected: metrics ingest token is not configured")
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid metrics token")

    if token != expected:
        client_host = request.client.host if request.client else "unknown"
        logger.warning("Metrics ingest rejected from %s: invalid token", client_host)
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid metrics token")


def _make_session_token(username: str, settings: Settings) -> str:
    exp = int(datetime.now(timezone.utc).timestamp()) + settings.dashboard_session_ttl_seconds
    payload = f"{username}.{exp}"
    signature = hmac.new(
        settings.resolved_dashboard_secret().encode("utf-8"),
        payload.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()
    return f"{payload}.{signature}"


def _verify_session_token(token: str, settings: Settings) -> str:
    try:
        payload, signature = token.rsplit(".", 1)
        expected_signature = hmac.new(
            settings.resolved_dashboard_secret().encode("utf-8"),
            payload.encode("utf-8"),
            hashlib.sha256,
        ).hexdigest()
        if not hmac.compare_digest(signature, expected_signature):
            raise ValueError("signature mismatch")
        username, exp_str = payload.split(".", 1)
        exp = int(exp_str)
    except Exception as exc:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid session") from exc

    if datetime.now(timezone.utc).timestamp() > exp:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Session expired")
    return username


async def require_dashboard_user(
    session: Optional[str] = Cookie(default=None, alias="metrics_session"),
    settings: Settings = Depends(get_settings),
) -> str:
    if not session:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Not authenticated")
    return _verify_session_token(session, settings)


def _store(settings: Settings) -> MetricsStore:
    return get_metrics_store(settings.metrics_data_file, settings.metrics_max_events)


@router.post("/v1/metrics", status_code=status.HTTP_202_ACCEPTED, summary="Ingest client AI/API metrics")
async def ingest_metrics(
    payload: MetricIngestPayload,
    request: Request,
    settings: Settings = Depends(get_settings),
) -> dict:
    _require_metrics_token(request, settings)
    store = _store(settings)

    ts = payload.timestamp or datetime.now(timezone.utc)
    if ts.tzinfo is None:
        ts = ts.replace(tzinfo=timezone.utc)

    event = MetricEvent(
        interface=payload.interface,
        status_code=payload.status_code,
        latency_ms=payload.latency_ms,
        request_bytes=payload.request_bytes,
        tokens=payload.tokens,
        retry_count=payload.retry_count,
        source=payload.source,
        request_id=payload.request_id,
        error_reason=payload.error_reason,
        timestamp=ts,
    )
    try:
        store.add(event)
    except Exception as exc:
        logger.error("Failed to persist metrics to %s: %s", store.path, exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to persist metrics",
        ) from exc

    logger.info(
        "Metrics ingested interface=%s status=%s source=%s latency=%.2fms bytes=%s tokens=%s request_id=%s file=%s",
        event.interface,
        event.status_code,
        event.source,
        event.latency_ms,
        event.request_bytes,
        event.tokens,
        event.request_id,
        store.path,
    )
    return {"status": "queued"}


@router.post("/admin/metrics/login", summary="Login for metrics dashboard")
async def login(request: LoginRequest, response: Response, settings: Settings = Depends(get_settings)) -> dict:
    if request.username != settings.dashboard_username or request.password != settings.dashboard_password:
        logger.warning("Metrics dashboard login failed for user=%s", request.username)
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials")

    token = _make_session_token(request.username, settings)
    response.set_cookie(
        "metrics_session",
        token,
        httponly=True,
        secure=settings.require_https,
        samesite="lax",
        max_age=settings.dashboard_session_ttl_seconds,
        path="/",
    )
    logger.info("Metrics dashboard login success for user=%s", request.username)
    return {"ok": True}


@router.get("/admin/metrics/me")
async def me(user: str = Depends(require_dashboard_user)) -> dict:
    return {"user": user}


@router.get("/admin/metrics/data")
async def metrics_data(
    user: str = Depends(require_dashboard_user),
    settings: Settings = Depends(get_settings),
) -> JSONResponse:
    store = _store(settings)
    overview = store.overview()
    logger.debug("Dashboard metrics data requested by %s", user)
    return JSONResponse(overview.model_dump())


@router.get("/admin/metrics/events")
async def metrics_events(
    user: str = Depends(require_dashboard_user),
    settings: Settings = Depends(get_settings),
) -> dict:
    store = _store(settings)
    cutoff = datetime.now(timezone.utc) - timedelta(days=7)
    events = [event.to_public_dict() for event in reversed(store.list_since(cutoff))]
    logger.debug("Dashboard metrics events requested by %s (count=%s)", user, len(events))
    return {"events": events}


@router.get("/admin/metrics/export")
async def metrics_export(
    user: str = Depends(require_dashboard_user),
    settings: Settings = Depends(get_settings),
) -> StreamingResponse:
    store = _store(settings)
    cutoff = datetime.now(timezone.utc) - timedelta(days=7)
    events = store.list_since(cutoff)
    logger.info("Dashboard metrics export requested by %s (count=%s)", user, len(events))

    buffer = io.StringIO()
    writer = csv.writer(buffer)
    writer.writerow(
        [
            "timestamp",
            "interface",
            "status_code",
            "latency_ms",
            "request_bytes",
            "tokens",
            "retry_count",
            "source",
            "request_id",
            "error_reason",
        ]
    )
    for event in events:
        writer.writerow(
            [
                event.timestamp.isoformat(),
                event.interface,
                event.status_code,
                round(event.latency_ms, 2),
                event.request_bytes,
                event.tokens or "",
                event.retry_count,
                event.source,
                event.request_id or "",
                (event.error_reason or "").replace("\n", " "),
            ]
        )

    filename = f"metrics-last-7d-{datetime.now(timezone.utc).strftime('%Y%m%d')}.csv"
    buffer.seek(0)
    return StreamingResponse(
        iter([buffer.getvalue()]),
        media_type="text/csv",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


DASHBOARD_HTML = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>LanRead Metrics</title>
  <style>
    @import url('https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@400;500;600;700&family=Chivo+Mono:wght@400;600&display=swap');
    :root {
      --bg: radial-gradient(circle at 20% 20%, rgba(131, 238, 255, 0.08), transparent 32%),
            radial-gradient(circle at 80% 0%, rgba(255, 165, 128, 0.08), transparent 40%),
            #0b1021;
      --card: rgba(13, 18, 36, 0.72);
      --border: rgba(255, 255, 255, 0.08);
      --text: #eaf1ff;
      --muted: #97a3c0;
      --accent: #8ef6ff;
      --accent-2: #ffb26f;
      --error: #ff5f6d;
      --positive: #7cf29c;
      --shadow: 0 20px 60px rgba(0,0,0,0.35);
    }
    * { box-sizing: border-box; }
    body {
      margin: 0; padding: 32px 18px 48px;
      background: var(--bg);
      color: var(--text);
      font-family: 'Space Grotesk', 'Helvetica Neue', Arial, sans-serif;
      min-height: 100vh;
    }
    .page {
      max-width: 1180px;
      margin: 0 auto;
      position: relative;
    }
    header {
      display: flex; justify-content: space-between; align-items: center;
      margin-bottom: 18px;
    }
    .brand {
      display: flex; align-items: center; gap: 10px;
    }
    .pill {
      padding: 6px 10px;
      border-radius: 999px;
      background: rgba(255,255,255,0.06);
      color: var(--muted);
      font-size: 12px;
      border: 1px solid var(--border);
    }
    h1 { margin: 0; font-size: 24px; letter-spacing: -0.02em; }
    .glass {
      background: var(--card);
      border: 1px solid var(--border);
      border-radius: 16px;
      box-shadow: var(--shadow);
      backdrop-filter: blur(8px);
    }
    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
      gap: 12px;
    }
    .card { padding: 16px; }
    .card h3 {
      margin: 0 0 6px;
      font-size: 15px;
      color: var(--muted);
      letter-spacing: 0.01em;
      text-transform: uppercase;
    }
    .metric-value {
      font-size: 26px;
      font-weight: 600;
      margin: 6px 0;
    }
    .metric-sub {
      color: var(--muted);
      font-size: 13px;
    }
    table {
      width: 100%;
      border-collapse: collapse;
      color: var(--text);
      font-size: 13px;
    }
    th, td {
      padding: 8px;
      border-bottom: 1px solid var(--border);
      text-align: left;
    }
    th { color: var(--muted); font-weight: 600; }
    .badge {
      display: inline-flex;
      align-items: center;
      padding: 4px 8px;
      border-radius: 999px;
      background: rgba(255,255,255,0.06);
      border: 1px solid var(--border);
      color: var(--text);
      font-size: 12px;
      gap: 6px;
    }
    .status-ok { color: var(--positive); }
    .status-bad { color: var(--error); }
    .timeline {
      display: flex;
      gap: 6px;
      align-items: flex-end;
      height: 160px;
    }
    .bar {
      flex: 1;
      min-width: 12px;
      background: linear-gradient(180deg, rgba(142, 246, 255, 0.95), rgba(142, 246, 255, 0.25));
      border-radius: 8px 8px 4px 4px;
      position: relative;
      overflow: hidden;
      border: 1px solid var(--border);
    }
    .bar .fail {
      position: absolute;
      bottom: 0;
      left: 0;
      width: 100%;
      background: linear-gradient(180deg, rgba(255,95,109,0.9), rgba(255,95,109,0.4));
      border-radius: 8px 8px 4px 4px;
    }
    .bar span {
      position: absolute;
      bottom: 6px;
      left: 6px;
      font-size: 10px;
      color: #0b1021;
      font-weight: 700;
      text-shadow: 0 1px 2px rgba(255,255,255,0.4);
    }
    .section-title {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin: 16px 0 8px;
      gap: 12px;
    }
    .section-title h2 {
      margin: 0;
      font-size: 18px;
      letter-spacing: -0.01em;
    }
    .placeholder {
      border: 1px dashed var(--border);
      color: var(--muted);
      text-align: center;
      padding: 20px;
      border-radius: 14px;
    }
    .login-panel {
      max-width: 420px;
      margin: 40px auto 0;
      padding: 20px;
    }
    .login-panel h2 { margin: 0 0 8px; }
    .field {
      display: flex;
      flex-direction: column;
      gap: 6px;
      margin-bottom: 12px;
    }
    input[type="text"], input[type="password"] {
      padding: 12px;
      border-radius: 10px;
      border: 1px solid var(--border);
      background: rgba(255,255,255,0.04);
      color: var(--text);
      font-size: 15px;
    }
    button {
      cursor: pointer;
      padding: 12px 16px;
      border-radius: 10px;
      border: 1px solid var(--border);
      background: linear-gradient(120deg, #8ef6ff, #7ec3ff);
      color: #0b1021;
      font-weight: 700;
      width: 100%;
    }
    .btn {
      width: auto;
      display: inline-flex;
      align-items: center;
      gap: 8px;
      padding: 10px 14px;
      background: linear-gradient(120deg, #8ef6ff, #7ec3ff);
      color: #0b1021;
      border-radius: 12px;
      border: 1px solid var(--border);
      box-shadow: var(--shadow);
    }
    .btn.ghost {
      background: rgba(255,255,255,0.06);
      color: var(--text);
      border-color: var(--border);
      box-shadow: none;
    }
    .hidden { display: none; }
    .chips { display: flex; gap: 8px; flex-wrap: wrap; }
  </style>
</head>
<body>
  <div class="page">
    <header>
      <div class="brand">
        <div class="pill">LanRead</div>
        <div>
          <h1>Usage & Health</h1>
          <div class="metric-sub">Login to view live AI/API telemetry</div>
        </div>
      </div>
      <div class="chips">
        <div class="badge" id="session-indicator">Auth required</div>
      </div>
    </header>

    <section id="login-section" class="glass login-panel">
      <h2>Login Required</h2>
      <p class="metric-sub">Use the dashboard credentials to unlock usage analytics.</p>
      <form id="login-form">
        <div class="field">
          <label for="username">Username</label>
          <input id="username" name="username" type="text" autocomplete="username" required />
        </div>
        <div class="field">
          <label for="password">Password</label>
          <input id="password" name="password" type="password" autocomplete="current-password" required />
        </div>
        <button type="submit">Sign in</button>
        <p class="metric-sub" id="login-error" style="color: var(--error); display:none;"></p>
      </form>
    </section>

    <section id="dashboard" class="hidden">
      <div class="grid">
        <div class="glass card">
          <h3>Total Calls</h3>
          <div class="metric-value" id="total-calls">-</div>
          <div class="metric-sub">Last 24h: <span id="last-24h">-</span></div>
        </div>
        <div class="glass card">
          <h3>Success Rate</h3>
          <div class="metric-value" id="success-rate">-</div>
          <div class="metric-sub">Retries captured in payload</div>
        </div>
        <div class="glass card">
          <h3>RPS / QPS</h3>
          <div class="metric-value" id="rps">-</div>
          <div class="metric-sub">Avg over last <span id="rps-window">-</span> min</div>
        </div>
        <div class="glass card">
          <h3>Avg Latency</h3>
          <div class="metric-value" id="avg-latency">-</div>
          <div class="metric-sub">ms per call</div>
        </div>
        <div class="glass card">
          <h3>Tokens / Bytes</h3>
          <div class="metric-value" id="tokens">-</div>
          <div class="metric-sub">Total request bytes: <span id="bytes"></span></div>
        </div>
      </div>

      <div class="section-title">
        <h2>Interface Performance</h2>
        <div class="pill">Live per-endpoint</div>
      </div>
      <div class="glass card" style="overflow-x:auto;">
        <table id="interface-table">
          <thead>
            <tr>
              <th>Interface</th>
              <th>Calls</th>
              <th>Success</th>
              <th>Avg ms</th>
              <th>P95 ms</th>
              <th>Errors</th>
              <th>Sources</th>
            </tr>
          </thead>
          <tbody></tbody>
        </table>
      </div>

      <div class="section-title">
        <h2>Funnel by Source</h2>
        <div class="pill">Start Reading / Chapter Summary / Translation</div>
      </div>
      <div class="glass card" style="overflow-x:auto;">
        <table id="source-table">
          <thead>
            <tr>
              <th>Source</th>
              <th>Calls</th>
              <th>Success</th>
              <th>Avg ms</th>
            </tr>
          </thead>
          <tbody></tbody>
        </table>
      </div>

      <div class="section-title">
        <h2>Last 24h</h2>
        <div class="pill">Capacity pulse</div>
      </div>
      <div class="glass card">
        <div class="timeline" id="timeline"></div>
      </div>

      <div class="section-title">
        <h2>Recent Calls</h2>
        <div style="display:flex; gap:8px; align-items:center; flex-wrap:wrap;">
          <div class="pill">Past 7 days</div>
          <button type="button" class="btn ghost" id="export-button">Export CSV</button>
        </div>
      </div>
      <div class="glass card" style="overflow-x:auto;">
        <table id="recent-table">
          <thead>
            <tr>
              <th>When</th>
              <th>Interface</th>
              <th>Status</th>
              <th>Latency</th>
              <th>Source</th>
              <th>Error</th>
            </tr>
          </thead>
          <tbody></tbody>
        </table>
      </div>

      <div class="section-title">
        <h2>Reserved Panels</h2>
        <div class="pill">Space for future metrics</div>
      </div>
      <div class="grid">
        <div class="glass card placeholder">Coming soon: cost per model / provider</div>
        <div class="glass card placeholder">Coming soon: device breakdown & regional stability</div>
      </div>
    </section>
  </div>

  <script>
    const loginForm = document.getElementById('login-form');
    const loginSection = document.getElementById('login-section');
    const dashboard = document.getElementById('dashboard');
    const loginError = document.getElementById('login-error');
    const sessionIndicator = document.getElementById('session-indicator');
    const exportButton = document.getElementById('export-button');

    loginForm.addEventListener('submit', async (e) => {
      e.preventDefault();
      loginError.style.display = 'none';
      const username = document.getElementById('username').value.trim();
      const password = document.getElementById('password').value.trim();
      const res = await fetch('/admin/metrics/login', {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ username, password })
      });
      if (res.ok) {
        sessionIndicator.textContent = 'Authenticated';
        sessionIndicator.classList.add('status-ok');
        loginSection.classList.add('hidden');
        dashboard.classList.remove('hidden');
        loadData();
      } else {
        loginError.textContent = '登录失败，请检查账号密码。';
        loginError.style.display = 'block';
        sessionIndicator.textContent = 'Auth required';
        sessionIndicator.classList.remove('status-ok');
      }
    });

    async function checkSession() {
      const res = await fetch('/admin/metrics/me', { credentials: 'include' });
      if (res.ok) {
        sessionIndicator.textContent = 'Authenticated';
        sessionIndicator.classList.add('status-ok');
        loginSection.classList.add('hidden');
        dashboard.classList.remove('hidden');
        loadData();
      } else {
        sessionIndicator.textContent = 'Auth required';
        loginSection.classList.remove('hidden');
      }
    }

    if (exportButton) {
      exportButton.addEventListener('click', exportMetrics);
    }

    async function exportMetrics() {
      const res = await fetch('/admin/metrics/export', { credentials: 'include' });
      if (!res.ok) {
        alert('导出失败，请检查登录状态后重试');
        if (res.status === 401) {
          sessionIndicator.textContent = 'Auth required';
          dashboard.classList.add('hidden');
          loginSection.classList.remove('hidden');
        }
        return;
      }
      const blob = await res.blob();
      const url = window.URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `metrics-last-7d-${new Date().toISOString().slice(0,10)}.csv`;
      document.body.appendChild(a);
      a.click();
      a.remove();
      window.URL.revokeObjectURL(url);
    }

    function formatNumber(value) {
      return Number(value || 0).toLocaleString();
    }

    function escapeText(value) {
      return String(value ?? '')
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;');
    }

    function simplifyError(reason) {
      if (!reason) return 'Unknown error';
      const trimmed = String(reason).trim();
      const tryExtractFromObject = (value) => {
        if (!value || typeof value !== 'object') return null;
        if (value.error && typeof value.error.message === 'string') return value.error.message;
        if (typeof value.message === 'string') return value.message;
        return null;
      };

      // Try full JSON parse
      try {
        const parsed = JSON.parse(trimmed);
        const message = tryExtractFromObject(parsed);
        if (message) return message;
      } catch (_) {
        // fall through
      }

      // Try parsing JSON inside the string (e.g., suffix after colon)
      const braceIndex = trimmed.indexOf('{');
      if (braceIndex >= 0) {
        const jsonPart = trimmed.slice(braceIndex);
        try {
          const parsed = JSON.parse(jsonPart);
          const message = tryExtractFromObject(parsed);
          if (message) return message;
        } catch (_) {
          // fall through
        }
      }

      const match = trimmed.match(/"message"\\s*:\\s*"([^"]+)"/);
      if (match && match[1]) {
        return match[1];
      }

      return trimmed;
    }

    function setTotals(totals, meta = {}) {
      document.getElementById('total-calls').textContent = formatNumber(totals.count);
      document.getElementById('last-24h').textContent = formatNumber(totals.last24h);
      const success = (totals.successRate * 100).toFixed(1) + '%';
      document.getElementById('success-rate').textContent = success;
      const rpsWindowSeconds = Number(meta.rpsWindowSeconds || 300);
      const rpsWindowMinutes = Math.max(1, Math.round(rpsWindowSeconds / 60));
      const rpsValue = Number(totals.rps || 0);
      document.getElementById('rps').textContent = rpsValue >= 1 ? rpsValue.toFixed(2) : rpsValue.toFixed(3);
      document.getElementById('rps-window').textContent = rpsWindowMinutes;
      document.getElementById('avg-latency').textContent = (totals.avgLatencyMs || 0).toFixed(1) + ' ms';
      document.getElementById('tokens').textContent = formatNumber(totals.totalTokens || 0) + ' tok';
      document.getElementById('bytes').textContent = formatNumber(totals.totalBytes || 0) + ' bytes';
    }

    function renderInterfaces(interfaces) {
      const tbody = document.querySelector('#interface-table tbody');
      tbody.innerHTML = '';
      interfaces.forEach((row) => {
        const tr = document.createElement('tr');
        tr.innerHTML = `
          <td>${row.name}</td>
          <td>${formatNumber(row.count)}</td>
          <td><span class="status-${row.successRate >= 0.95 ? 'ok' : 'bad'}">${(row.successRate * 100).toFixed(1)}%</span></td>
          <td>${(row.avgLatencyMs || 0).toFixed(1)}</td>
          <td>${(row.p95LatencyMs || 0).toFixed(1)}</td>
          <td>${formatNumber(row.errors || 0)}</td>
          <td>${Object.entries(row.sources || {}).map(([s, v]) => `<span class="badge">${s}: ${v}</span>`).join(' ')}</td>
        `;
        tbody.appendChild(tr);
      });
    }

    function renderSources(sources) {
      const tbody = document.querySelector('#source-table tbody');
      tbody.innerHTML = '';
      sources.forEach((row) => {
        const tr = document.createElement('tr');
        tr.innerHTML = `
          <td>${row.name}</td>
          <td>${formatNumber(row.count)}</td>
          <td><span class="status-${row.successRate >= 0.95 ? 'ok' : 'bad'}">${(row.successRate * 100).toFixed(1)}%</span></td>
          <td>${(row.avgLatencyMs || 0).toFixed(1)}</td>
        `;
        tbody.appendChild(tr);
      });
    }

    function renderTimeline(buckets) {
      const container = document.getElementById('timeline');
      container.innerHTML = '';
      const maxCount = Math.max(...buckets.map((b) => b.count), 1);
      buckets.forEach((bucket) => {
        const bar = document.createElement('div');
        bar.className = 'bar';
        bar.style.height = (bucket.count / maxCount * 100) + '%';
        if (bucket.failures > 0) {
          const fail = document.createElement('div');
          fail.className = 'fail';
          fail.style.height = (bucket.failures / bucket.count * 100) + '%';
          bar.appendChild(fail);
        }
        const label = document.createElement('span');
        label.textContent = bucket.count;
        bar.appendChild(label);
        bar.title = `${bucket.bucket} UTC`;
        container.appendChild(bar);
      });
    }

    function renderRecent(rows) {
      const tbody = document.querySelector('#recent-table tbody');
      tbody.innerHTML = '';
      rows.forEach((row) => {
        const tr = document.createElement('tr');
        const date = new Date(row.timestamp);
        const ok = row.statusCode >= 200 && row.statusCode < 300;
        const errorText = ok ? '-' : escapeText(simplifyError(row.errorReason));
        tr.innerHTML = `
          <td>${date.toLocaleString()}</td>
          <td>${escapeText(row.interface)}</td>
          <td><span class="status-${ok ? 'ok' : 'bad'}">${row.statusCode}</span></td>
          <td>${(row.latencyMs || 0).toFixed(1)} ms</td>
          <td>${escapeText(row.source)}</td>
          <td>${errorText}</td>
        `;
        tbody.appendChild(tr);
      });
    }

    async function loadData() {
      const res = await fetch('/admin/metrics/data', { credentials: 'include' });
      if (!res.ok) {
        sessionIndicator.textContent = 'Auth required';
        dashboard.classList.add('hidden');
        loginSection.classList.remove('hidden');
        return;
      }
      const data = await res.json();
      setTotals(data.totals || {}, data.meta || {});
      renderInterfaces(data.interfaces || []);
      renderSources(data.sources || []);
      renderTimeline(data.timeline || []);
      renderRecent(data.recent || []);
    }

    checkSession();
  </script>
</body>
</html>
"""


@router.get("/admin/metrics", response_class=HTMLResponse, include_in_schema=False)
async def metrics_page() -> HTMLResponse:
    return HTMLResponse(DASHBOARD_HTML)
