from pathlib import Path

from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse, HTMLResponse

router = APIRouter(tags=["public"])

_STATIC_DIR = Path(__file__).resolve().parent.parent / "static"
_LANDING_DIR = _STATIC_DIR / "landing"
_LANDING_CONTENT_DIR = _LANDING_DIR / "content"

LANDING_HTML = (_LANDING_DIR / "index.html").read_text(encoding="utf-8")

PRIVACY_POLICY_HTML = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Lan Read · Privacy</title>
  <meta name="description" content="Lan Read privacy & data use. Local-first by default with optional iCloud sync and secure AI key exchange." />
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link href="https://fonts.googleapis.com/css2?family=Epilogue:wght@400;500;700&family=DM+Mono:wght@400;500&family=Newsreader:opsz,wght@6..72,500;6..72,700&display=swap" rel="stylesheet">
  <style>
    :root {
      --bg: #f3f1eb;
      --panel: #fffdf8;
      --paper-edge: #e8e1d5;
      --line: rgba(20,20,20,0.12);
      --text: #14110f;
      --muted: #5a5d61;
      --accent: #14110f;
      --radius: 18px;
      --grid: 120px;
      --paper-shadow: 0 20px 60px rgba(0,0,0,0.08);
    }
    * { box-sizing: border-box; }
    body {
      margin: 0; color: var(--text);
      background:
        radial-gradient(circle at 18% 16%, rgba(0,0,0,0.025), transparent 32%),
        radial-gradient(circle at 78% 8%, rgba(0,0,0,0.018), transparent 30%),
        var(--bg);
      font-family: "Epilogue", "DM Mono", system-ui, -apple-system, sans-serif;
      min-height: 100vh; overflow-x: hidden;
    }
    .grain {
      position: fixed; inset: 0; pointer-events: none; opacity: 0.12;
      background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='120' height='120' viewBox='0 0 120 120'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='2' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='120' height='120' filter='url(%23n)' opacity='0.4'/%3E%3C/svg%3E");
      mix-blend-mode: multiply; z-index: 5;
    }
    .grid {
      position: fixed; inset: 0; pointer-events: none; z-index: 1;
      background-image:
        linear-gradient(var(--line) 1px, transparent 1px),
        linear-gradient(90deg, var(--line) 1px, transparent 1px);
      background-size: var(--grid) var(--grid);
      mask-image: radial-gradient(circle at center, rgba(0,0,0,1) 42%, rgba(0,0,0,0) 70%);
    }
    header {
      position: sticky; top: 0; z-index: 10;
      backdrop-filter: blur(14px);
      background: rgba(255,253,248,0.90);
      border-bottom: 1px solid var(--line);
    }
    nav {
      max-width: 1180px; margin: 0 auto; padding: 14px 28px;
      display: flex; align-items: center; justify-content: space-between; gap: 18px;
      font-size: 14px; letter-spacing: 0.03em;
    }
    .logo {
      display: flex; align-items: center; gap: 10px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.16em;
      font-family: "Newsreader", "Epilogue", serif;
    }
    .logo .dot { width: 12px; height: 12px; border: 2px solid var(--accent); border-radius: 50%; box-shadow: 0 0 0 6px rgba(0,0,0,0.05); }
    .nav-links { display: flex; gap: 10px; align-items: center; flex-wrap: wrap; }
    .pill {
      padding: 8px 14px; border: 1px solid var(--line); border-radius: 999px; color: var(--text); text-decoration: none; transition: border .3s, color .3s, background .3s;
    }
    .pill:hover { border-color: var(--accent); color: var(--accent); background: rgba(0,0,0,0.03); }
    .pill.active { background: rgba(0,0,0,0.04); }
    .section { max-width: 1180px; margin: 0 auto 120px; padding: 0 28px; position: relative; z-index: 2; }
    h1 {
      font-size: clamp(32px, 4vw, 48px); line-height: 1.1; margin: 0 0 12px;
      letter-spacing: -0.02em;
      font-family: "Newsreader", "Epilogue", serif;
    }
    .lead { color: var(--muted); max-width: 820px; font-size: 17px; line-height: 1.7; margin: 0 0 18px; }
    .meta-line { color: var(--muted); font-size: 13px; letter-spacing: 0.06em; text-transform: uppercase; display: inline-flex; align-items: center; gap: 10px; }
    .meta-line .dot { width: 7px; height: 7px; background: var(--accent); border-radius: 50%; display: inline-block; }
    .paper-sheet {
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 18px;
      padding: 28px 26px 30px;
      box-shadow: var(--paper-shadow);
      position: relative;
      overflow: hidden;
    }
    .paper-sheet::after {
      content: ""; position: absolute; inset: 12px; border-radius: 14px; border: 1px dashed rgba(20,20,20,0.06);
      pointer-events: none;
    }
    .paper-sheet.ruled {
      background-image: linear-gradient(rgba(20,20,20,0.04) 1px, transparent 1px);
      background-size: 100% 46px;
    }
    .paper-sheet .note-tab {
      position: absolute; left: -12px; top: 22px; width: 22px; height: 82px;
      background: linear-gradient(180deg, #d5c9b1, #e7dbc5);
      border: 1px solid rgba(20,20,20,0.15);
      border-radius: 10px 6px 6px 10px;
      box-shadow: 6px 12px 20px rgba(0,0,0,0.10);
    }
    .paper-sheet .paper-label {
      display: inline-flex; align-items: center; gap: 8px;
      font-size: 12px; letter-spacing: 0.08em; text-transform: uppercase;
      color: var(--muted); margin-bottom: 14px; padding: 6px 10px;
      border: 1px solid var(--line); border-radius: 999px; background: rgba(0,0,0,0.02);
    }
    .paper-sheet .paper-label::before {
      content: "§"; font-family: "DM Mono", monospace; color: var(--accent); font-size: 12px;
    }
    .paper-edge {
      position: absolute; inset: 18px -18px auto auto; height: 20px; background:
        linear-gradient(90deg, rgba(20,20,20,0.10) 32%, transparent 32%),
        var(--paper-edge);
      border-radius: 999px; opacity: 0.65;
    }
    .badge { display: inline-flex; align-items: center; gap: 6px; padding: 4px 10px; border-radius: 999px; background: rgba(20,20,20,0.06); border: 1px solid var(--line); color: var(--muted); font-size: 12px; letter-spacing: 0.02em; }
    .privacy-list { list-style: none; padding: 0; margin: 0; display: grid; gap: 10px; color: var(--muted); line-height: 1.65; }
    .privacy-card {
      border: 1px solid var(--line); border-radius: var(--radius);
      padding: 18px 18px 20px; background: linear-gradient(120deg, rgba(0,0,0,0.02), rgba(0,0,0,0));
      box-shadow: 0 16px 40px rgba(0,0,0,0.06);
      position: relative;
    }
    .privacy-card::after {
      content: ""; position: absolute; inset: 12px; border: 1px dashed var(--line); border-radius: var(--radius);
      opacity: 0.6;
    }
    .privacy-card h3 { margin: 0 0 10px; font-size: 18px; letter-spacing: 0.01em; display: inline-flex; align-items: center; gap: 10px; }
    .privacy-stack { display: grid; gap: 16px; }
    footer {
      border-top: 1px solid var(--line); padding: 30px 28px 60px; color: var(--muted); background: rgba(247,248,250,0.8);
      position: relative; z-index: 2;
    }
    @media (max-width: 900px) {
      nav { padding: 12px 18px; flex-wrap: wrap; }
    }
  </style>
</head>
<body>
  <div class="grid"></div>
  <div class="grain"></div>

  <header>
    <nav>
      <div class="logo"><div class="dot"></div><span>Lan Read · 澜悦</span></div>
      <div class="nav-links">
        <a class="pill" href="index.html">Home</a>
        <a class="pill" href="changelog.html">Changelog</a>
        <a class="pill" href="support.html">Support</a>
      </div>
      <span class="pill active" style="background:rgba(0,0,0,0.02);">Privacy</span>
    </nav>
  </header>

  <section class="section" style="margin-top:64px;">
    <div class="paper-sheet ruled">
      <div class="note-tab" aria-hidden="true"></div>
      <div class="paper-label">Privacy · 隐私</div>
      <h1>Privacy &amp; Data Use</h1>
      <p class="lead">We collect only the minimum data needed to provide reading and AI features. Books and reading content stay on your device by default, and required network traffic is encrypted. This policy applies to the Lan Read iOS app and its companion backend (isla-reader.top).</p>
      <div class="meta-line"><span class="dot"></span><span>Updated: 2026-02-05</span></div>

      <div class="privacy-stack" style="margin-top: 18px;">
        <div class="privacy-card">
          <h3>Our Principles</h3>
          <ul class="privacy-list">
            <li>No account is required; data remains local to your device.</li>
            <li>Book content is not uploaded unless you trigger AI features (summaries, translation, etc.).</li>
            <li>You can export, import, or erase local data anytime in "Settings &gt; Data Management."</li>
          </ul>
        </div>

        <div class="privacy-card" id="admob">
          <h3>AdMob Data Use</h3>
          <ul class="privacy-list">
            <li>We use Google AdMob to show banner and rewarded ads that keep the app free.</li>
            <li>AdMob may collect device info such as IDFA (if permitted), IP address, device model, OS version, coarse location (IP-based), and ad performance/fraud signals.</li>
            <li>We do not send your imported books, notes, or account data to AdMob; ad requests include only the SDK’s necessary device signals.</li>
            <li>You can limit ad personalization via iOS "Allow Apps to Request to Track" and "Personalized Ads." See the Google Privacy Policy.</li>
          </ul>
        </div>

        <div class="privacy-card" id="ai">
          <h3>AI Feature Uploads</h3>
          <ul class="privacy-list">
            <li>When you use translation, explanation, AI summary, or skimming, we send the relevant text over HTTPS to your configured OpenAI-compatible endpoint (DashScope by default) to generate results.</li>
            <li>Uploaded content is limited to the book passages you request to process plus necessary prompt context; it excludes account identifiers and ad identifiers.</li>
            <li>API keys can be issued by the secure server (isla-reader.top/v1/keys/ai); this server does not store your book content and only signs and forwards credentials.</li>
            <li>We do not persist uploaded text on the server; generated summaries/key points remain on your device.</li>
            <li>Third-party model providers (e.g., DashScope or your custom OpenAI-compatible service) may handle data under their own privacy policies.</li>
          </ul>
        </div>

        <div class="privacy-card" id="notion">
          <h3>Notion Sync (Optional)</h3>
          <ul class="privacy-list">
            <li>If you opt into syncing highlights or notes to Notion, we perform only the OAuth code exchange on the server to keep the Notion client secret off your device.</li>
            <li>Data we receive: the authorization code, redirect URI, client_id, nonce, timestamp, and HMAC signature used to validate the request. These are sent to Notion over HTTPS to obtain the access token.</li>
            <li>The Notion access token is returned directly to your device with Cache-Control: no-store; the server does not store or log the token.</li>
            <li>Logs keep minimal metadata (status, workspace_id/name, bot_id) for troubleshooting and omit the authorization code and access token.</li>
            <li>Book content and notes are not proxied through our server for Notion sync; your device uses the token to call Notion’s API directly.</li>
            <li>You may revoke the integration anytime in Notion (“Settings &amp; Members → My connections”) or disconnect in the app; no server-side deletion is required because tokens are never persisted server-side.</li>
          </ul>
        </div>

        <div class="privacy-card">
          <h3>Your Rights &amp; Contact</h3>
          <ul class="privacy-list">
            <li>You can export or erase local data anytime via "Data Management." All data stays on-device.</li>
            <li>For questions about this policy or data handling, contact <a href="mailto:guoliang88925@icloud.com">guoliang88925@icloud.com</a>.</li>
          </ul>
        </div>
      </div>

      <div class="paper-edge" aria-hidden="true"></div>
    </div>
  </section>

  <footer>
    <div style="max-width:1180px; margin:0 auto; display:flex; justify-content:space-between; gap:10px; flex-wrap:wrap;">
      <span>© 2026 Lan Read · 澜悦 — Privacy &amp; data use.</span>
      <span style="display:flex; gap:12px; flex-wrap:wrap;">
        <a class="pill" href="index.html">Home</a>
        <a class="pill" href="changelog.html">Changelog</a>
        <a class="pill" href="support.html">Support</a>
      </span>
    </div>
  </footer>
</body>
</html>
"""


@router.get("/", response_class=HTMLResponse, include_in_schema=False)
async def marketing_home() -> HTMLResponse:
    return HTMLResponse(LANDING_HTML, headers={"Cache-Control": "public, max-age=600"})


@router.get("/content/{lang}.json", include_in_schema=False)
async def marketing_copy(lang: str):
    """Serve localized landing copy used by the front-end language switcher."""
    normalized = lang.lower()
    if normalized not in {"en", "zh"}:
        normalized = "en"

    path = _LANDING_CONTENT_DIR / f"{normalized}.json"
    if not path.exists():
        raise HTTPException(status_code=404, detail="copy not found")

    return FileResponse(path, media_type="application/json", headers={"Cache-Control": "public, max-age=900"})


def _landing_file(filename: str) -> FileResponse:
    path = _LANDING_DIR / filename
    if not path.exists():
        raise HTTPException(status_code=404, detail="page not found")
    return FileResponse(path, media_type="text/html", headers={"Cache-Control": "public, max-age=900"})


@router.get("/privacy.html", include_in_schema=False)
async def landing_privacy_html():
    return _landing_file("privacy.html")


@router.get("/changelog.html", include_in_schema=False)
async def landing_changelog_html():
    return _landing_file("changelog.html")


@router.get("/support.html", include_in_schema=False)
async def landing_support_html():
    return _landing_file("support.html")


@router.get("/privacy", response_class=HTMLResponse, include_in_schema=False)
async def privacy_policy() -> HTMLResponse:
    return HTMLResponse(PRIVACY_POLICY_HTML, headers={"Cache-Control": "public, max-age=3600"})
