from pathlib import Path

from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse, HTMLResponse

router = APIRouter(tags=["public"])

_STATIC_DIR = Path(__file__).resolve().parent.parent / "static"
_LANDING_DIR = _STATIC_DIR / "landing"
_LANDING_CONTENT_DIR = _LANDING_DIR / "content"
_ALLOWED_LANDING_CONTENT_IMAGE_EXTS = {".svg", ".png", ".jpg", ".jpeg", ".webp", ".gif", ".avif"}

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
      flex-wrap: wrap;
    }
    .logo {
      display: flex; align-items: center; gap: 10px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.16em;
      font-family: "Newsreader", "Epilogue", serif;
    }
    .logo .dot { width: 12px; height: 12px; border: 2px solid var(--accent); border-radius: 50%; box-shadow: 0 0 0 6px rgba(0,0,0,0.05); }
    .nav-links { display: flex; gap: 10px; align-items: center; flex-wrap: wrap; }
    .lang-switch { display: flex; align-items: center; gap: 8px; color: var(--muted); font-size: 12px; text-transform: uppercase; letter-spacing: 0.08em; }
    .lang-switch select {
      padding: 7px 10px; border-radius: 12px; border: 1px solid var(--line);
      background: var(--panel); color: var(--text); font-size: 13px;
    }
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
      nav { padding: 12px 18px; }
      .lang-switch { width: 100%; justify-content: flex-end; }
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
        <a class="pill" id="nav-home" href="/">Home</a>
        <a class="pill" id="nav-changelog" href="changelog.html">Changelog</a>
        <a class="pill" id="nav-support" href="support.html">Support</a>
        <span class="pill active" id="nav-privacy" style="background:rgba(0,0,0,0.02);">Privacy</span>
      </div>
      <div class="lang-switch">
        <label for="language" id="nav-language">Language</label>
        <select id="language" aria-label="Language selector">
          <option value="en">English</option>
          <option value="zh">中文</option>
          <option value="ja">日本語</option>
          <option value="ko">한국어</option>
        </select>
      </div>
    </nav>
  </header>

  <section class="section" style="margin-top:64px;">
    <div class="paper-sheet ruled">
      <div class="note-tab" aria-hidden="true"></div>
      <div class="paper-label" id="privacy-label">Privacy</div>
      <h1 id="privacy-title">Privacy &amp; Data Use</h1>
      <p class="lead" id="privacy-lead">We collect only the minimum data needed to provide reading and AI features. Books and reading content stay on your device by default, and required network traffic is encrypted. This policy applies to the Lan Read iOS app and its companion backend (isla-reader.top).</p>
      <div class="meta-line"><span class="dot"></span><span id="privacy-updated">Updated: 2026-02-05</span></div>

      <div class="privacy-stack" style="margin-top: 18px;">
        <div class="privacy-card">
          <h3 id="principles-title">Our Principles</h3>
          <ul class="privacy-list" id="principles-list"></ul>
        </div>

        <div class="privacy-card" id="admob">
          <h3 id="admob-title">AdMob Data Use</h3>
          <ul class="privacy-list" id="admob-list"></ul>
        </div>

        <div class="privacy-card" id="ai">
          <h3 id="ai-title">AI Feature Uploads</h3>
          <ul class="privacy-list" id="ai-list"></ul>
        </div>

        <div class="privacy-card" id="notion">
          <h3 id="notion-title">Notion Sync (Optional)</h3>
          <ul class="privacy-list" id="notion-list"></ul>
        </div>

        <div class="privacy-card">
          <h3 id="rights-title">Your Rights &amp; Contact</h3>
          <ul class="privacy-list" id="rights-list"></ul>
        </div>
      </div>

      <div class="paper-edge" aria-hidden="true"></div>
    </div>
  </section>

  <footer>
    <div style="max-width:1180px; margin:0 auto; display:flex; justify-content:space-between; gap:10px; flex-wrap:wrap;">
      <span id="footer-note">© 2026 Lan Read · 澜悦 — Privacy &amp; data use.</span>
      <span style="display:flex; gap:12px; flex-wrap:wrap;">
        <a class="pill" id="footer-home" href="/">Home</a>
        <a class="pill" id="footer-changelog" href="changelog.html">Changelog</a>
        <a class="pill" id="footer-support" href="support.html">Support</a>
      </span>
    </div>
  </footer>

  <script>
    const languageSelect = document.getElementById('language');

    const setText = (id, value) => {
      const node = document.getElementById(id);
      if (node && value) node.textContent = value;
    };

    const setList = (id, items) => {
      const node = document.getElementById(id);
      if (!node) return;
      node.innerHTML = (items || []).map(item => `<li>${item}</li>`).join('');
    };

    const copy = {
      en: {
        meta: {
          title: 'Lan Read · Privacy',
          description: 'Lan Read privacy & data use. Local-first by default with optional iCloud sync and secure AI key exchange.'
        },
        nav: {
          home: 'Home',
          changelog: 'Changelog',
          support: 'Support',
          privacy: 'Privacy',
          language: 'Language'
        },
        header: {
          label: 'Privacy',
          title: 'Privacy & Data Use',
          lead: 'We collect only the minimum data needed to provide reading and AI features. Books and reading content stay on your device by default, and required network traffic is encrypted. This policy applies to the Lan Read iOS app and its companion backend (isla-reader.top).',
          updated: 'Updated: 2026-02-05'
        },
        sections: {
          principles: {
            title: 'Our Principles',
            items: [
              'No account is required; data remains local to your device.',
              'Book content is not uploaded unless you trigger AI features (summaries, translation, etc.).',
              'You can export, import, or erase local data anytime in "Settings > Data Management."'
            ]
          },
          admob: {
            title: 'AdMob Data Use',
            items: [
              'We use Google AdMob to show banner and rewarded ads that keep the app free.',
              'AdMob may collect device info such as IDFA (if permitted), IP address, device model, OS version, coarse location (IP-based), and ad performance/fraud signals.',
              'We do not send your imported books, notes, or account data to AdMob; ad requests include only the SDK’s necessary device signals.',
              'You can limit ad personalization via iOS "Allow Apps to Request to Track" and "Personalized Ads." See the <a href="https://policies.google.com/privacy">Google Privacy Policy</a>.'
            ]
          },
          ai: {
            title: 'AI Feature Uploads',
            items: [
              'When you use translation, explanation, AI summary, or skimming, we send the relevant text over HTTPS to your configured OpenAI-compatible endpoint (DashScope by default) to generate results.',
              'Uploaded content is limited to the book passages you request to process plus necessary prompt context; it excludes account identifiers and ad identifiers.',
              'API keys can be issued by the secure server (isla-reader.top/v1/keys/ai); this server does not store your book content and only signs and forwards credentials.',
              'We do not persist uploaded text on the server; generated summaries/key points remain on your device.',
              'Third-party model providers (e.g., DashScope or your custom OpenAI-compatible service) may handle data under their own privacy policies.'
            ]
          },
          notion: {
            title: 'Notion Sync (Optional)',
            items: [
              'If you opt into syncing highlights or notes to Notion, we perform only the OAuth code exchange on the server to keep the Notion client secret off your device.',
              'Data we receive: the authorization code, redirect URI, client_id, nonce, timestamp, and HMAC signature used to validate the request. These are sent to Notion over HTTPS to obtain the access token.',
              'The Notion access token is returned directly to your device with <code>Cache-Control: no-store</code>; the server does not store or log the token.',
              'Logs keep minimal metadata (status, workspace_id/name, bot_id) for troubleshooting and omit the authorization code and access token.',
              'Book content and notes are not proxied through our server for Notion sync; your device uses the token to call Notion’s API directly.',
              'You may revoke the integration anytime in Notion (“Settings & Members → My connections”) or disconnect in the app; no server-side deletion is required because tokens are never persisted server-side.'
            ]
          },
          rights: {
            title: 'Your Rights & Contact',
            items: [
              'You can export or erase local data anytime via "Data Management." All data stays on-device.',
              'For questions about this policy or data handling, contact <a href="mailto:guoliang88925@icloud.com">guoliang88925@icloud.com</a>.'
            ]
          }
        },
        footer: {
          note: '© 2026 Lan Read · 澜悦 — Privacy & data use.',
          home: 'Home',
          changelog: 'Changelog',
          support: 'Support'
        }
      },
      zh: {
        meta: {
          title: 'Lan Read · 隐私',
          description: 'Lan Read 隐私与数据使用。默认本地优先，可选 iCloud 同步与安全 AI 密钥交换。'
        },
        nav: {
          home: '主页',
          changelog: '更新日志',
          support: '支持',
          privacy: '隐私',
          language: '语言'
        },
        header: {
          label: '隐私 · Privacy',
          title: '隐私与数据使用',
          lead: '我们仅收集提供阅读与 AI 功能所需的最少数据。默认情况下书籍与阅读内容保留在你的设备上，必要的网络传输会加密。本政策适用于 Lan Read iOS 应用及其配套后端（isla-reader.top）。',
          updated: '更新日期：2026-02-05'
        },
        sections: {
          principles: {
            title: '我们的原则',
            items: [
              '无需账号；数据保留在设备本地。',
              '除非你触发 AI 功能（摘要、翻译等），书籍内容不会上传。',
              '你可以随时在“设置 > 数据管理”导出、导入或清除本地数据。'
            ]
          },
          admob: {
            title: 'AdMob 数据使用',
            items: [
              '我们使用 Google AdMob 展示横幅与激励广告以保持应用免费。',
              'AdMob 可能收集设备信息，如 IDFA（若允许）、IP 地址、设备型号、系统版本、粗略位置（基于 IP）及广告表现/反欺诈信号。',
              '我们不会向 AdMob 发送你导入的书籍、笔记或账号数据；广告请求仅包含 SDK 必需的设备信号。',
              '你可在 iOS“允许 App 请求跟踪”和“个性化广告”中限制个性化广告。详见 <a href="https://policies.google.com/privacy">Google 隐私政策</a>。'
            ]
          },
          ai: {
            title: 'AI 功能上传',
            items: [
              '当你使用翻译、解释、AI 摘要或略读功能时，我们会通过 HTTPS 将相关文本发送到你配置的 OpenAI 兼容端点（默认 DashScope）生成结果。',
              '上传内容仅限你请求处理的书籍片段及必要的提示上下文；不包含账号标识或广告标识。',
              'API 密钥可由安全服务器（isla-reader.top/v1/keys/ai）签发；该服务器不存储你的书籍内容，只负责签名与转发凭证。',
              '我们不会在服务器持久化上传文本；生成的摘要/要点保留在你的设备上。',
              '第三方模型提供方可能在其隐私政策下处理数据，请在使用前查阅。'
            ]
          },
          notion: {
            title: 'Notion 同步（可选）',
            items: [
              '若你选择同步高亮或笔记至 Notion，我们仅在服务器完成 OAuth code 交换，以避免 Notion 客户端密钥出现在设备上。',
              '我们接收的数据：授权码、redirect URI、client_id、nonce、时间戳与 HMAC 签名；这些会通过 HTTPS 发送至 Notion 以换取访问令牌。',
              'Notion 访问令牌会直接返回你的设备并设置 <code>Cache-Control: no-store</code>；服务器不存储也不记录令牌。',
              '日志仅保留最小元数据（status、workspace_id/name、bot_id）用于排障，不含授权码和访问令牌。',
              'Notion 同步的书籍内容与笔记不会经过服务器代理；设备使用令牌直接调用 Notion API。',
              '你可以在 Notion（“Settings & Members → My connections”）或应用内随时撤销；由于令牌从不持久化，无需服务器端删除。'
            ]
          },
          rights: {
            title: '你的权利与联系',
            items: [
              '你可以随时在“数据管理”导出或清除本地数据；所有数据保留在设备上。',
              '如对本政策或数据处理有疑问，请联系 <a href="mailto:guoliang88925@icloud.com">guoliang88925@icloud.com</a>。'
            ]
          }
        },
        footer: {
          note: '© 2026 Lan Read · 澜悦 — 隐私与数据使用。',
          home: '主页',
          changelog: '更新日志',
          support: '支持'
        }
      },
      ja: {
        meta: {
          title: 'Lan Read · プライバシー',
          description: 'Lan Read のプライバシーとデータ利用。ローカル優先、必要に応じて iCloud 同期と安全な AI キー交換。'
        },
        nav: {
          home: 'ホーム',
          changelog: '更新履歴',
          support: 'サポート',
          privacy: 'プライバシー',
          language: '言語'
        },
        header: {
          label: 'プライバシー · Privacy',
          title: 'プライバシーとデータ利用',
          lead: '本アプリは読書とAI機能に必要な最小限のデータのみを収集します。書籍と読書内容は原則として端末内に保存され、必要な通信は暗号化されます。本ポリシーは Lan Read iOS アプリとそのバックエンド（isla-reader.top）に適用されます。',
          updated: '更新日：2026-02-05'
        },
        sections: {
          principles: {
            title: '基本方針',
            items: [
              'アカウント不要。データは端末内に保持されます。',
              'AI機能（要約・翻訳など）を使わない限り、書籍内容は送信されません。',
              '「設定 > データ管理」からいつでもエクスポート／インポート／消去できます。'
            ]
          },
          admob: {
            title: 'AdMob のデータ利用',
            items: [
              '無料提供のため Google AdMob のバナー／リワード広告を使用します。',
              'AdMob は IDFA（許可時）、IP、端末モデル、OS バージョン、概算位置（IPベース）、広告パフォーマンス／不正対策シグナル等を収集する可能性があります。',
              '書籍・ノート・アカウント情報は AdMob に送信しません。広告リクエストは SDK の必要な端末シグナルのみを含みます。',
              'iOS の「Appにトラッキングを許可」「パーソナライズド広告」で制限できます。詳しくは <a href="https://policies.google.com/privacy">Google プライバシーポリシー</a> を参照してください。'
            ]
          },
          ai: {
            title: 'AI 機能の送信',
            items: [
              '翻訳／解説／AI要約／スキミングを使う際、関連テキストを HTTPS で OpenAI 互換エンドポイント（既定は DashScope）へ送信します。',
              '送信内容は必要な書籍の抜粋とプロンプト文脈のみで、アカウントIDや広告IDは含みません。',
              'API キーは安全なサーバー（isla-reader.top/v1/keys/ai）から発行可能で、書籍内容は保存せず署名と転送のみを行います。',
              'サーバーに送信テキストを永続保存しません。生成結果は端末に保存されます。',
              '外部のモデル提供者は各社のプライバシーポリシーに従ってデータを扱う場合があります。'
            ]
          },
          notion: {
            title: 'Notion 同期（任意）',
            items: [
              'Notion 同期を選択した場合、サーバーで OAuth のコード交換のみを行い、クライアントシークレットを端末外に保持します。',
              '受信するデータ：認可コード、redirect URI、client_id、nonce、タイムスタンプ、HMAC 署名。これらを HTTPS で Notion に送信しアクセストークンを取得します。',
              'アクセストークンは <code>Cache-Control: no-store</code> で端末に直接返却され、サーバーは保存・記録しません。',
              'ログは最小メタデータ（status、workspace_id/name、bot_id）のみで、認可コードとトークンは含みません。',
              '書籍内容とノートはサーバーを経由せず、端末がトークンで Notion API を直接呼び出します。',
              'Notion 側またはアプリでいつでも解除可能。トークンは保存しないためサーバー側の削除は不要です。'
            ]
          },
          rights: {
            title: '権利と連絡先',
            items: [
              '「データ管理」からいつでもエクスポート／消去できます。データは端末内に保持されます。',
              '本ポリシーやデータ取り扱いについては <a href="mailto:guoliang88925@icloud.com">guoliang88925@icloud.com</a> までお問い合わせください。'
            ]
          }
        },
        footer: {
          note: '© 2026 Lan Read · 澜悦 — プライバシーとデータ利用。',
          home: 'ホーム',
          changelog: '更新履歴',
          support: 'サポート'
        }
      },
      ko: {
        meta: {
          title: 'Lan Read · 개인정보',
          description: 'Lan Read 개인정보 및 데이터 사용. 기본 로컬 우선, 선택적 iCloud 동기화와 안전한 AI 키 교환.'
        },
        nav: {
          home: '홈',
          changelog: '변경 로그',
          support: '지원',
          privacy: '개인정보',
          language: '언어'
        },
        header: {
          label: '개인정보 · Privacy',
          title: '개인정보 및 데이터 사용',
          lead: '독서 및 AI 기능에 필요한 최소한의 데이터만 수집합니다. 기본적으로 책과 독서 내용은 기기 내에 보관되며 필요한 네트워크 통신은 암호화됩니다. 이 정책은 Lan Read iOS 앱과 동반 백엔드(isla-reader.top)에 적용됩니다.',
          updated: '업데이트: 2026-02-05'
        },
        sections: {
          principles: {
            title: '핵심 원칙',
            items: [
              '계정이 필요 없으며 데이터는 기기에 로컬로 보관됩니다.',
              'AI 기능(요약, 번역 등)을 사용하지 않는 한 책 내용은 업로드되지 않습니다.',
              '“설정 > 데이터 관리”에서 언제든 내보내기/가져오기/삭제할 수 있습니다.'
            ]
          },
          admob: {
            title: 'AdMob 데이터 사용',
            items: [
              '앱을 무료로 제공하기 위해 Google AdMob 배너 및 보상형 광고를 사용합니다.',
              'AdMob은 IDFA(허용 시), IP 주소, 기기 모델, OS 버전, 대략적 위치(IP 기반), 광고 성과/부정 신호 등을 수집할 수 있습니다.',
              '책/노트/계정 데이터는 AdMob에 전송하지 않으며, 광고 요청에는 SDK에 필요한 기기 신호만 포함됩니다.',
              'iOS의 “앱 추적 요청 허용” 및 “맞춤형 광고”에서 개인화 광고를 제한할 수 있습니다. 자세한 내용은 <a href="https://policies.google.com/privacy">Google 개인정보처리방침</a>을 참고하세요.'
            ]
          },
          ai: {
            title: 'AI 기능 업로드',
            items: [
              '번역/설명/AI 요약/스키밍을 사용할 때 관련 텍스트를 HTTPS로 OpenAI 호환 엔드포인트(기본 DashScope)에 전송합니다.',
              '전송 내용은 요청한 책 구간과 필요한 프롬프트 컨텍스트만 포함하며, 계정/광고 식별자는 제외됩니다.',
              'API 키는 보안 서버(isla-reader.top/v1/keys/ai)에서 발급될 수 있으며, 서버는 책 내용을 저장하지 않고 서명과 전달만 수행합니다.',
              '업로드된 텍스트를 서버에 영구 저장하지 않으며, 생성 결과는 기기에 보관됩니다.',
              '제3자 모델 제공자가 자체 개인정보처리방침에 따라 데이터를 처리할 수 있습니다.'
            ]
          },
          notion: {
            title: 'Notion 동기화(선택)',
            items: [
              'Notion 동기화를 선택하면 OAuth 코드 교환만 서버에서 수행하여 클라이언트 시크릿을 기기에 두지 않습니다.',
              '수신 데이터: 인증 코드, redirect URI, client_id, nonce, 타임스탬프, HMAC 서명. 이를 HTTPS로 Notion에 전송해 액세스 토큰을 획득합니다.',
              '액세스 토큰은 <code>Cache-Control: no-store</code>로 기기에 직접 반환되며, 서버는 저장하거나 로그하지 않습니다.',
              '로그는 최소 메타데이터(status, workspace_id/name, bot_id)만 유지하고 인증 코드와 토큰은 포함하지 않습니다.',
              '책 내용과 노트는 서버를 거치지 않으며, 기기가 토큰으로 Notion API를 직접 호출합니다.',
              'Notion 또는 앱에서 언제든지 연결을 해제할 수 있으며, 토큰을 저장하지 않으므로 서버 측 삭제가 필요하지 않습니다.'
            ]
          },
          rights: {
            title: '권리 및 문의',
            items: [
              '“데이터 관리”에서 언제든 내보내기/삭제할 수 있으며 모든 데이터는 기기에 남습니다.',
              '정책 또는 데이터 처리 관련 문의는 <a href="mailto:guoliang88925@icloud.com">guoliang88925@icloud.com</a>으로 연락하세요.'
            ]
          }
        },
        footer: {
          note: '© 2026 Lan Read · 澜悦 — 개인정보 및 데이터 사용.',
          home: '홈',
          changelog: '변경 로그',
          support: '지원'
        }
      }
    };

    const applyLanguage = (lang) => {
      const chosen = copy[lang] ? lang : 'en';
      const t = copy[chosen];

      if (document.documentElement) {
        document.documentElement.lang = chosen === 'zh' ? 'zh-Hans' : chosen;
      }
      if (languageSelect) languageSelect.value = chosen;

      document.title = t.meta.title;
      const metaDesc = document.querySelector('meta[name="description"]');
      if (metaDesc) metaDesc.setAttribute('content', t.meta.description);

      setText('nav-home', t.nav.home);
      setText('nav-changelog', t.nav.changelog);
      setText('nav-support', t.nav.support);
      setText('nav-privacy', t.nav.privacy);
      setText('nav-language', t.nav.language);

      setText('privacy-label', t.header.label);
      setText('privacy-title', t.header.title);
      setText('privacy-lead', t.header.lead);
      setText('privacy-updated', t.header.updated);

      setText('principles-title', t.sections.principles.title);
      setList('principles-list', t.sections.principles.items);

      setText('admob-title', t.sections.admob.title);
      setList('admob-list', t.sections.admob.items);

      setText('ai-title', t.sections.ai.title);
      setList('ai-list', t.sections.ai.items);

      setText('notion-title', t.sections.notion.title);
      setList('notion-list', t.sections.notion.items);

      setText('rights-title', t.sections.rights.title);
      setList('rights-list', t.sections.rights.items);

      setText('footer-note', t.footer.note);
      setText('footer-home', t.footer.home);
      setText('footer-changelog', t.footer.changelog);
      setText('footer-support', t.footer.support);

      localStorage.setItem('lanread-privacy-lang', chosen);
    };

    const storedLang = localStorage.getItem('lanread-privacy-lang');
    applyLanguage(copy[storedLang] ? storedLang : 'en');

    if (languageSelect) {
      languageSelect.addEventListener('change', (e) => applyLanguage(e.target.value));
    }
  </script>
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


@router.get("/content/{filename}", include_in_schema=False)
async def marketing_content_asset(filename: str):
    """Serve static landing content assets (images only)."""
    if not filename or "/" in filename or "\\" in filename:
        raise HTTPException(status_code=404, detail="asset not found")

    ext = Path(filename).suffix.lower()
    if ext not in _ALLOWED_LANDING_CONTENT_IMAGE_EXTS:
        raise HTTPException(status_code=404, detail="asset not found")

    base = _LANDING_CONTENT_DIR.resolve()
    path = (_LANDING_CONTENT_DIR / filename).resolve()
    if base not in path.parents:
        raise HTTPException(status_code=404, detail="asset not found")
    if not path.exists() or not path.is_file():
        raise HTTPException(status_code=404, detail="asset not found")

    return FileResponse(path, headers={"Cache-Control": "public, max-age=900"})


def _landing_file(filename: str) -> FileResponse:
    path = _LANDING_DIR / filename
    if not path.exists():
        raise HTTPException(status_code=404, detail="page not found")
    return FileResponse(path, media_type="text/html", headers={"Cache-Control": "public, max-age=900"})


@router.get("/changelog.html", include_in_schema=False)
async def landing_changelog_html():
    return _landing_file("changelog.html")


@router.get("/support.html", include_in_schema=False)
async def landing_support_html():
    return _landing_file("support.html")


@router.get("/privacy", response_class=HTMLResponse, include_in_schema=False)
async def privacy_policy() -> HTMLResponse:
    return HTMLResponse(PRIVACY_POLICY_HTML, headers={"Cache-Control": "public, max-age=3600"})
