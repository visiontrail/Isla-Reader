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
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>LanRead Privacy Policy</title>
  <style>
    :root {
      --bg: #0f172a;
      --card: #111827;
      --muted: #94a3b8;
      --text: #e2e8f0;
      --accent: #38bdf8;
      --border: #1f2937;
    }
    body {
      margin: 0;
      padding: 0;
      background: radial-gradient(circle at 20% 20%, rgba(56, 189, 248, 0.08), transparent 35%),
                  radial-gradient(circle at 80% 0%, rgba(94, 234, 212, 0.06), transparent 40%),
                  var(--bg);
      color: var(--text);
      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro Display", "Helvetica Neue", Arial, sans-serif;
      line-height: 1.6;
      display: flex;
      justify-content: center;
      padding: 32px 12px 48px;
    }
    .page {
      max-width: 920px;
      width: 100%;
      background: linear-gradient(145deg, rgba(24, 24, 27, 0.96), rgba(15, 23, 42, 0.96));
      border: 1px solid var(--border);
      border-radius: 18px;
      box-shadow: 0 25px 60px rgba(0, 0, 0, 0.35);
      padding: 28px 24px;
      backdrop-filter: blur(6px);
    }
    header {
      display: flex;
      flex-direction: column;
      gap: 8px;
      padding-bottom: 12px;
      border-bottom: 1px solid var(--border);
      margin-bottom: 16px;
    }
    .eyebrow {
      text-transform: uppercase;
      letter-spacing: 0.12em;
      font-size: 12px;
      color: var(--muted);
      margin: 0;
    }
    h1 {
      margin: 0;
      font-size: 28px;
    }
    .updated {
      margin: 0;
      color: var(--muted);
      font-size: 14px;
    }
    section {
      background: rgba(17, 24, 39, 0.7);
      border: 1px solid var(--border);
      border-radius: 14px;
      padding: 18px 16px;
      margin-bottom: 14px;
    }
    section h2 {
      margin: 0 0 10px;
      font-size: 18px;
    }
    section p {
      margin: 0 0 8px;
      color: var(--muted);
    }
    ul {
      margin: 0;
      padding-left: 18px;
      color: var(--muted);
    }
    a {
      color: var(--accent);
      text-decoration: none;
    }
    a:hover {
      text-decoration: underline;
    }
  </style>
</head>
<body>
  <div class="page">
    <header>
      <p class="eyebrow">LanRead</p>
      <h1>Privacy Policy</h1>
      <p class="updated">Updated: 2026-02-05</p>
      <p class="updated">This policy applies to the LanRead iOS app and its companion backend (isla-reader.top).</p>
    </header>

    <section>
      <h2>Our Principles</h2>
      <p>We collect only the minimum data needed to provide reading and AI features. Books and reading content stay on your device by default, and required network traffic is encrypted.</p>
      <ul>
        <li>No account is required; data remains local to your device.</li>
        <li>Book content is not uploaded unless you trigger AI features (summaries, translation, etc.).</li>
        <li>You can export, import, or erase local data anytime in "Settings &gt; Data Management."</li>
      </ul>
    </section>

    <section id="admob">
      <h2>AdMob Data Use</h2>
      <p>We use Google AdMob to show banner and rewarded ads that keep the app free.</p>
      <ul>
        <li>AdMob acts as an independent data controller and may collect device info such as: advertising identifier (IDFA, if permitted), IP address, device model, OS version, coarse location (IP-based), and ad performance/fraud signals.</li>
        <li>We do not send your imported books, notes, or account data to AdMob; ad requests include only the SDK’s necessary device signals.</li>
        <li>You can limit ad personalization via iOS "Allow Apps to Request to Track" and "Personalized Ads." See the <a href="https://policies.google.com/privacy">Google Privacy Policy</a> for details.</li>
      </ul>
    </section>

    <section id="ai">
      <h2>AI Feature Uploads</h2>
      <p>When you use translation, explanation, AI summary, or skimming, we send the relevant text over HTTPS to your configured OpenAI-compatible endpoint (DashScope by default) to generate results.</p>
      <ul>
        <li>Uploaded content is limited to the book passages you request to process plus necessary prompt context; it excludes account identifiers and ad identifiers.</li>
        <li>API keys can be issued by the secure server (isla-reader.top/v1/keys/ai); this server does not store your book content and only signs and forwards credentials.</li>
        <li>We do not persist uploaded text on the server; generated summaries/key points remain on your device.</li>
        <li>Third-party model providers (e.g., DashScope or your custom OpenAI-compatible service) may handle data under their own privacy policies. Please review them before use.</li>
      </ul>
    </section>

    <section id="notion">
      <h2>Notion Sync (Optional)</h2>
      <p>If you opt into syncing highlights or notes to Notion, we perform only the OAuth code exchange on the server to keep the Notion client secret off your device.</p>
      <ul>
        <li>Data we receive: the authorization code, redirect URI, client_id, nonce, timestamp, and HMAC signature used to validate the request. These are sent to Notion over HTTPS to obtain the access token.</li>
        <li>The Notion access token is returned directly to your device with <code>Cache-Control: no-store</code>; the server does not store or log the token.</li>
        <li>Logs keep minimal metadata (status, workspace_id/name, bot_id) for troubleshooting and omit the authorization code and access token.</li>
        <li>Book content and notes are not proxied through our server for Notion sync; your device uses the token to call Notion’s API directly.</li>
        <li>You may revoke the integration anytime in Notion (“Settings & Members → My connections”) or disconnect in the app; no server-side deletion is required because tokens are never persisted server-side.</li>
      </ul>
    </section>

    <section>
      <h2>Your Rights & Contact</h2>
      <ul>
        <li>You can export or erase local data anytime via "Data Management." All data stays on-device.</li>
        <li>For questions about this policy or data handling, contact <a href="mailto:guoliang88925@icloud.com">guoliang88925@icloud.com</a>.</li>
      </ul>
    </section>
  </div>
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
