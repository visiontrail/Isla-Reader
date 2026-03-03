from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.responses import HTMLResponse
from pydantic import BaseModel, Field

from ..config import Settings, get_settings
from ..logging_utils import get_logger
from ..update_policy_store import UpdatePolicy, get_update_policy_store
from .metrics import require_dashboard_user

router = APIRouter(tags=["update-policy"])
logger = get_logger("update_policy")

_SUPPORTED_PLATFORMS = {"ios", "ipados"}


class UpdatePolicyResponse(BaseModel):
    enabled: bool
    mode: str
    latest_version: str
    minimum_supported_version: str
    title: str
    message: str
    app_store_url: str
    remind_interval_hours: int
    updated_at: datetime


class UpdatePolicyUpdateRequest(BaseModel):
    enabled: bool = False
    mode: str = Field(default="soft", pattern="^(soft|hard)$")
    latest_version: str = ""
    minimum_supported_version: str = ""
    title: str = ""
    message: str = ""
    app_store_url: str = ""
    remind_interval_hours: int = Field(default=24, ge=1, le=24 * 30)


def _store(settings: Settings):
    return get_update_policy_store(settings.update_policy_file)


@router.get("/v1/app/update-policy", response_model=UpdatePolicyResponse, summary="Fetch app update policy")
async def get_public_update_policy(
    platform: str = Query(default="ios"),
    current_version: Optional[str] = Query(default=None),
    current_build: Optional[str] = Query(default=None),
    settings: Settings = Depends(get_settings),
) -> UpdatePolicyResponse:
    lowered_platform = platform.strip().lower()
    if lowered_platform not in _SUPPORTED_PLATFORMS:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Unsupported platform")

    policy = _store(settings).get()
    logger.debug(
        "Update policy fetched platform=%s current_version=%s current_build=%s enabled=%s mode=%s latest=%s minimum=%s",
        lowered_platform,
        (current_version or "").strip() or "unknown",
        (current_build or "").strip() or "unknown",
        policy.enabled,
        policy.mode,
        policy.latest_version or "none",
        policy.minimum_supported_version or "none",
    )
    return UpdatePolicyResponse(**policy.model_dump())


@router.get("/admin/update-policy/config", response_model=UpdatePolicyResponse)
async def get_admin_update_policy(
    user: str = Depends(require_dashboard_user),
    settings: Settings = Depends(get_settings),
) -> UpdatePolicyResponse:
    policy = _store(settings).get()
    logger.debug("Update policy viewed by %s", user)
    return UpdatePolicyResponse(**policy.model_dump())


@router.put("/admin/update-policy/config", response_model=UpdatePolicyResponse)
async def update_admin_update_policy(
    payload: UpdatePolicyUpdateRequest,
    user: str = Depends(require_dashboard_user),
    settings: Settings = Depends(get_settings),
) -> UpdatePolicyResponse:
    current = _store(settings).get()
    updated = UpdatePolicy(
        enabled=payload.enabled,
        mode=payload.mode,
        latest_version=payload.latest_version,
        minimum_supported_version=payload.minimum_supported_version,
        title=payload.title,
        message=payload.message,
        app_store_url=payload.app_store_url,
        remind_interval_hours=payload.remind_interval_hours,
        updated_at=current.updated_at,
    )
    saved = _store(settings).set(updated)
    logger.info(
        "Update policy updated by %s enabled=%s mode=%s latest=%s minimum=%s",
        user,
        saved.enabled,
        saved.mode,
        saved.latest_version or "none",
        saved.minimum_supported_version or "none",
    )
    return UpdatePolicyResponse(**saved.model_dump())


ADMIN_PAGE_HTML = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>LanRead Update Policy</title>
  <style>
    :root {
      --bg: #0b1021;
      --card: rgba(18, 24, 46, 0.82);
      --line: rgba(255,255,255,0.14);
      --text: #e9f0ff;
      --muted: #9fb0d8;
      --accent: #79f6d2;
      --warn: #ffce6f;
      --danger: #ff6b7c;
      --ok: #7cf29c;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      background: radial-gradient(circle at 20% 10%, rgba(121,246,210,0.12), transparent 35%),
                  radial-gradient(circle at 80% 0%, rgba(255,206,111,0.10), transparent 40%),
                  var(--bg);
      color: var(--text);
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
      padding: 20px;
      min-height: 100vh;
    }
    .container {
      max-width: 860px;
      margin: 0 auto;
      display: grid;
      gap: 14px;
    }
    .card {
      background: var(--card);
      border: 1px solid var(--line);
      border-radius: 14px;
      padding: 16px;
      backdrop-filter: blur(8px);
    }
    h1 { margin: 0; font-size: 22px; }
    p { margin: 8px 0 0; color: var(--muted); }
    .hidden { display: none; }
    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
      gap: 12px;
    }
    label {
      display: grid;
      gap: 6px;
      font-size: 13px;
      color: var(--muted);
    }
    input, select, textarea, button {
      width: 100%;
      border-radius: 10px;
      border: 1px solid var(--line);
      background: rgba(255,255,255,0.04);
      color: var(--text);
      padding: 10px 12px;
      font-size: 14px;
    }
    textarea { min-height: 96px; resize: vertical; }
    .checkbox {
      display: flex;
      align-items: center;
      gap: 8px;
      color: var(--text);
    }
    .checkbox input {
      width: auto;
      accent-color: var(--accent);
    }
    .actions {
      display: flex;
      gap: 10px;
      flex-wrap: wrap;
    }
    .actions button {
      width: auto;
      min-width: 120px;
      cursor: pointer;
    }
    .btn-primary {
      background: rgba(121,246,210,0.16);
      border-color: rgba(121,246,210,0.7);
    }
    .btn-secondary {
      background: rgba(255,255,255,0.08);
    }
    .status {
      font-size: 13px;
      min-height: 18px;
      color: var(--muted);
    }
    .status.ok { color: var(--ok); }
    .status.error { color: var(--danger); }
    .status.warn { color: var(--warn); }
  </style>
</head>
<body>
  <main class="container">
    <section class="card">
      <h1>App Update Policy</h1>
      <p>Configure soft/hard update prompts for iOS clients and publish without redeploying the app.</p>
    </section>

    <section id="login-card" class="card">
      <h2 style="margin:0 0 10px; font-size:18px;">Dashboard Login</h2>
      <form id="login-form" class="grid">
        <label>
          Username
          <input id="username" name="username" required autocomplete="username" />
        </label>
        <label>
          Password
          <input id="password" name="password" type="password" required autocomplete="current-password" />
        </label>
        <div class="actions">
          <button class="btn-primary" type="submit">Sign In</button>
        </div>
      </form>
      <div id="login-status" class="status"></div>
    </section>

    <section id="editor-card" class="card hidden">
      <form id="policy-form">
        <div class="checkbox" style="margin-bottom: 12px;">
          <input id="enabled" type="checkbox" />
          <label for="enabled" style="display:inline; color:var(--text);">Enable update prompts</label>
        </div>

        <div class="grid">
          <label>
            Mode
            <select id="mode">
              <option value="soft">soft</option>
              <option value="hard">hard</option>
            </select>
          </label>
          <label>
            Remind Interval Hours
            <input id="remind_interval_hours" type="number" min="1" max="720" step="1" />
          </label>
          <label>
            Latest Version
            <input id="latest_version" placeholder="e.g. 1.1.0" />
          </label>
          <label>
            Minimum Supported Version
            <input id="minimum_supported_version" placeholder="e.g. 1.0.0" />
          </label>
        </div>

        <div class="grid" style="margin-top: 12px;">
          <label>
            App Store URL
            <input id="app_store_url" placeholder="itms-apps://itunes.apple.com/app/id1234567890" />
          </label>
          <label>
            Prompt Title
            <input id="title" placeholder="Optional override title" />
          </label>
        </div>

        <label style="margin-top: 12px;">
          Prompt Message
          <textarea id="message" placeholder="Optional override message"></textarea>
        </label>

        <div class="actions" style="margin-top: 14px;">
          <button class="btn-primary" type="submit">Save Policy</button>
          <button class="btn-secondary" id="reload-button" type="button">Reload</button>
        </div>
      </form>

      <div id="policy-status" class="status"></div>
      <p id="policy-updated-at" style="margin-top:10px; font-size:12px; color:var(--muted);"></p>
    </section>
  </main>

  <script>
    const loginCard = document.getElementById('login-card');
    const editorCard = document.getElementById('editor-card');
    const loginStatus = document.getElementById('login-status');
    const policyStatus = document.getElementById('policy-status');
    const updatedAt = document.getElementById('policy-updated-at');

    const fields = {
      enabled: document.getElementById('enabled'),
      mode: document.getElementById('mode'),
      latest_version: document.getElementById('latest_version'),
      minimum_supported_version: document.getElementById('minimum_supported_version'),
      title: document.getElementById('title'),
      message: document.getElementById('message'),
      app_store_url: document.getElementById('app_store_url'),
      remind_interval_hours: document.getElementById('remind_interval_hours'),
    };

    const setStatus = (node, text, cls = '') => {
      node.className = `status ${cls}`.trim();
      node.textContent = text || '';
    };

    const setEditorVisible = (visible) => {
      editorCard.classList.toggle('hidden', !visible);
      loginCard.classList.toggle('hidden', visible);
    };

    const fillForm = (policy) => {
      fields.enabled.checked = !!policy.enabled;
      fields.mode.value = policy.mode || 'soft';
      fields.latest_version.value = policy.latest_version || '';
      fields.minimum_supported_version.value = policy.minimum_supported_version || '';
      fields.title.value = policy.title || '';
      fields.message.value = policy.message || '';
      fields.app_store_url.value = policy.app_store_url || '';
      fields.remind_interval_hours.value = policy.remind_interval_hours ?? 24;
      updatedAt.textContent = policy.updated_at ? `Last updated: ${new Date(policy.updated_at).toLocaleString()}` : '';
    };

    const collectPayload = () => ({
      enabled: fields.enabled.checked,
      mode: fields.mode.value,
      latest_version: fields.latest_version.value.trim(),
      minimum_supported_version: fields.minimum_supported_version.value.trim(),
      title: fields.title.value.trim(),
      message: fields.message.value.trim(),
      app_store_url: fields.app_store_url.value.trim(),
      remind_interval_hours: Number(fields.remind_interval_hours.value || '24'),
    });

    async function login(username, password) {
      const res = await fetch('/admin/metrics/login', {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ username, password }),
      });
      return res.ok;
    }

    async function loadPolicy() {
      const res = await fetch('/admin/update-policy/config', { credentials: 'include' });
      if (res.status === 401) return { unauthorized: true };
      if (!res.ok) throw new Error('Failed to load policy');
      return { data: await res.json() };
    }

    async function savePolicy(payload) {
      const res = await fetch('/admin/update-policy/config', {
        method: 'PUT',
        credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
      });
      if (res.status === 401) return { unauthorized: true };
      if (!res.ok) {
        let detail = 'Failed to save policy';
        try {
          const parsed = await res.json();
          if (parsed.detail) detail = typeof parsed.detail === 'string' ? parsed.detail : JSON.stringify(parsed.detail);
        } catch {}
        throw new Error(detail);
      }
      return { data: await res.json() };
    }

    async function bootstrap() {
      try {
        const me = await fetch('/admin/metrics/me', { credentials: 'include' });
        if (!me.ok) {
          setEditorVisible(false);
          return;
        }

        const loaded = await loadPolicy();
        if (loaded.unauthorized) {
          setEditorVisible(false);
          return;
        }
        fillForm(loaded.data);
        setEditorVisible(true);
        setStatus(policyStatus, 'Policy loaded.', 'ok');
      } catch (error) {
        setEditorVisible(false);
        setStatus(loginStatus, error.message || 'Initialization failed.', 'error');
      }
    }

    document.getElementById('login-form').addEventListener('submit', async (event) => {
      event.preventDefault();
      setStatus(loginStatus, 'Signing in...', 'warn');
      const username = document.getElementById('username').value.trim();
      const password = document.getElementById('password').value;
      const ok = await login(username, password);
      if (!ok) {
        setStatus(loginStatus, 'Login failed. Check credentials.', 'error');
        return;
      }
      setStatus(loginStatus, '');
      await bootstrap();
    });

    document.getElementById('reload-button').addEventListener('click', async () => {
      setStatus(policyStatus, 'Reloading...', 'warn');
      try {
        const loaded = await loadPolicy();
        if (loaded.unauthorized) {
          setEditorVisible(false);
          setStatus(loginStatus, 'Session expired. Please sign in again.', 'warn');
          return;
        }
        fillForm(loaded.data);
        setStatus(policyStatus, 'Policy reloaded.', 'ok');
      } catch (error) {
        setStatus(policyStatus, error.message || 'Reload failed.', 'error');
      }
    });

    document.getElementById('policy-form').addEventListener('submit', async (event) => {
      event.preventDefault();
      setStatus(policyStatus, 'Saving...', 'warn');
      try {
        const saved = await savePolicy(collectPayload());
        if (saved.unauthorized) {
          setEditorVisible(false);
          setStatus(loginStatus, 'Session expired. Please sign in again.', 'warn');
          return;
        }
        fillForm(saved.data);
        setStatus(policyStatus, 'Policy saved.', 'ok');
      } catch (error) {
        setStatus(policyStatus, error.message || 'Save failed.', 'error');
      }
    });

    bootstrap();
  </script>
</body>
</html>
"""


@router.get("/admin/update-policy", response_class=HTMLResponse, include_in_schema=False)
async def update_policy_admin_page() -> HTMLResponse:
    return HTMLResponse(ADMIN_PAGE_HTML)
