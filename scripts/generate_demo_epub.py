#!/usr/bin/env python3
"""Generate the built-in multilingual LanRead demo EPUB."""

from __future__ import annotations

from pathlib import Path
from textwrap import dedent
from zipfile import ZIP_DEFLATED, ZIP_STORED, ZipFile

BOOK_ID = "urn:uuid:8f36f0e4-cc8e-4dad-9621-c64dc8ad0101"
BOOK_TITLE = "LanRead Quick Start (Multilingual)"
BOOK_AUTHOR = "LanRead Team"
OUTPUT_PATH = Path("Isla Reader/SampleBooks/LanRead_Getting_Started_Multilingual.epub")


LANG_SECTIONS = [
    {
        "code": "en",
        "nav": "English",
        "title": "LanRead User Guide (English)",
        "quick_start_title": "3-minute start",
        "quick_start_flow": "Import one book -> AI overview -> Skimming -> Highlight & Note -> Sync to Notion -> Share",
        "tip": "Tip: This sample is interactive. You can highlight text, add notes, or select a sentence and ask AI to explain/translate it.",
        "toc_title": "Contents",
        "toc": [
            "1. Welcome to LanRead",
            "2. Step One: Import your local EPUB from Library",
            "3. First stop after import: AI Summarize",
            "4. Skimming Mode",
            "5. Reading basics: Bookmark / Highlight / Note",
            "6. Select text and ask AI to explain or translate",
            "7. Highlights & Notes: polished recap and sharing",
            "8. Connect Notion for automatic sync",
            "9. Theme and appearance settings",
            "10. Closing: build your reading knowledge base",
        ],
        "content": dedent(
            """
            <h2>1. Welcome to LanRead</h2>
            <p>LanRead is more than an EPUB page-turner. It is an AI-assisted reading and knowledge-capture workflow.</p>
            <ul>
              <li>After import, AI gives you a structural map of the book.</li>
              <li>Skimming Mode summarizes each chapter so you can grasp the full outline quickly.</li>
              <li>During reading, you can highlight, write notes, and ask AI to explain or translate selected text.</li>
              <li>Highlights and notes can be shared and synced to Notion.</li>
            </ul>
            <p class="quote">This demo includes action-ready paragraphs. Try selecting one sentence and ask AI to explain it.</p>

            <h2>2. Step One: Import your local EPUB from Library</h2>
            <p>Your reading journey starts in <strong>Library</strong>.</p>
            <ol>
              <li>Open <strong>Library</strong> on the home screen.</li>
              <li>Tap <strong>Import</strong>.</li>
              <li>Select a local <strong>EPUB</strong> from Files.</li>
            </ol>
            <ul>
              <li>After import, the book appears in Library immediately.</li>
              <li>You can search, favorite, and update reading status.</li>
            </ul>

            <h2>3. First stop after import: AI Summarize</h2>
            <p>Summarize gives a fast preview of what the book is about and how it is organized.</p>
            <ul>
              <li>Use it as a pre-reading trailer.</li>
              <li>Use it again as a post-reading review.</li>
            </ul>

            <h2>4. Skimming Mode</h2>
            <p>If Summarize is the trailer, Skimming Mode is the chapter-by-chapter scanline.</p>
            <ul>
              <li>Enter from Summarize by button or gesture.</li>
              <li>Review structure points, key sentences, keywords, and guiding questions.</li>
              <li>Jump back to full text when a chapter deserves deep reading.</li>
            </ul>
            <p class="quote">"Reading does not start from page one. It starts from structure."</p>

            <h2>5. Reading basics: Bookmark / Highlight / Note</h2>
            <ul>
              <li><strong>Bookmark</strong>: mark places you want to revisit.</li>
              <li><strong>Highlight</strong>: keep key lines and definitions.</li>
              <li><strong>Note</strong>: capture your own interpretation and action items.</li>
            </ul>

            <h2>6. Select text and ask AI to explain or translate</h2>
            <ol>
              <li>Long-press and select a sentence.</li>
              <li>Choose AI action: <strong>Explain</strong> or <strong>Translate</strong>.</li>
            </ol>
            <ul>
              <li>When a concept is unclear, ask AI for a simpler explanation.</li>
              <li>When reading foreign text, translate instantly.</li>
              <li>When writing notes, ask AI to rewrite in another language.</li>
            </ul>

            <h2>7. Highlights &amp; Notes: polished recap and sharing</h2>
            <p>LanRead collects your highlights and notes in one clean page.</p>
            <ul>
              <li>Browse quickly and jump back to source passages.</li>
              <li>Share curated cards with one tap.</li>
            </ul>

            <h2>8. Connect Notion for automatic sync</h2>
            <p>Turn reading output into a searchable long-term knowledge base.</p>
            <ol>
              <li>Open <strong>Settings</strong>.</li>
              <li>Find the <strong>Notion</strong> entry.</li>
              <li>Authorize and choose a destination page/database.</li>
            </ol>
            <ul>
              <li>Synced fields can include title, author, date, highlights, notes, and tags.</li>
            </ul>

            <h2>9. Theme and appearance settings</h2>
            <p>Different contexts need different reading styles.</p>
            <ul>
              <li>Night reading: dark theme.</li>
              <li>Day reading: light theme.</li>
              <li>Adjust typography and spacing to reduce fatigue.</li>
            </ul>

            <h2>10. Closing: build your reading knowledge base</h2>
            <p>LanRead helps you complete a practical reading loop:</p>
            <ol>
              <li>Import a book in Library.</li>
              <li>Build the map with Summarize.</li>
              <li>Skim for structure in Skimming Mode.</li>
              <li>Annotate deeply with bookmark/highlight/note.</li>
              <li>Ask AI on selected text.</li>
              <li>Review in Highlights &amp; Notes.</li>
              <li>Sync to Notion for long-term reuse.</li>
            </ol>
            """
        ).strip(),
        "next_steps_title": "Next steps you can do now",
        "next_steps": [
            "Import your first EPUB right now.",
            "Or use this sample to practice one full loop once.",
        ],
        "closing": "Happy reading!",
    },
    {
        "code": "ja",
        "nav": "日本語",
        "title": "LanRead 利用ガイド（日本語）",
        "quick_start_title": "3分で開始",
        "quick_start_flow": "1冊を取り込み -> AI概要 -> 速読 -> ハイライト/メモ -> Notion同期 -> 共有",
        "tip": "ヒント: このサンプルは操作デモです。文章を選択して、ハイライト・メモ・AI解説/翻訳をすぐ試せます。",
        "toc_title": "目次",
        "toc": [
            "1. LanReadへようこそ",
            "2. Step 1: LibraryからEPUBを取り込む",
            "3. 取り込み後の第一ステップ: AI Summarize",
            "4. Skimming Mode（速読モード）",
            "5. 基本操作: ブックマーク / ハイライト / メモ",
            "6. テキスト選択でAI解説・翻訳",
            "7. Highlights & Notes（一覧と共有）",
            "8. Notion連携で自動同期",
            "9. テーマと表示設定",
            "10. まとめ: 読書成果を知識として残す",
        ],
        "content": dedent(
            """
            <h2>1. LanReadへようこそ</h2>
            <p>LanRead は EPUB リーダーであり、同時に AI を使った読書理解と知識化のワークフローです。</p>
            <ul>
              <li>取り込み後、AIが本全体の構造を先に整理します。</li>
              <li>Skimming Modeで章ごとの要点を短時間で把握できます。</li>
              <li>読書中にハイライト、メモ、選択テキストのAI解説/翻訳が可能です。</li>
              <li>成果は Highlights &amp; Notes と Notion 同期で蓄積できます。</li>
            </ul>
            <p class="quote">このサンプルはそのまま練習用です。1文を選択してAI解説を試してください。</p>

            <h2>2. Step 1: LibraryからEPUBを取り込む</h2>
            <ol>
              <li>ホームの <strong>Library</strong> を開く。</li>
              <li><strong>取り込み</strong> をタップ。</li>
              <li>Files からローカル <strong>EPUB</strong> を選択。</li>
            </ol>
            <ul>
              <li>取り込み後すぐに本がLibraryへ追加されます。</li>
              <li>検索、お気に入り、読書ステータス管理ができます。</li>
            </ul>

            <h2>3. 取り込み後の第一ステップ: AI Summarize</h2>
            <p>Summarize は「読む前の予告編」です。内容と構造を短時間で把握できます。</p>
            <ul>
              <li>初見の本で全体像を掴む。</li>
              <li>読了後の振り返りにも使う。</li>
            </ul>

            <h2>4. Skimming Mode（速読モード）</h2>
            <p>Skimming Mode は章単位のAI要約で本全体を素早く走査します。</p>
            <ul>
              <li>Summarize 画面からボタンまたはジェスチャーで入る。</li>
              <li>章要点、重要文、キーワード、ガイド質問を確認する。</li>
              <li>必要な章だけ本文へ戻って精読する。</li>
            </ul>
            <p class="quote">「読書は1ページ目からではなく、構造から始まる。」</p>

            <h2>5. 基本操作: ブックマーク / ハイライト / メモ</h2>
            <ul>
              <li><strong>ブックマーク</strong>: 後で戻りたい位置を保存。</li>
              <li><strong>ハイライト</strong>: 重要な文をマーキング。</li>
              <li><strong>メモ</strong>: 自分の解釈やTODOを記録。</li>
            </ul>

            <h2>6. テキスト選択でAI解説・翻訳</h2>
            <ol>
              <li>本文を長押ししてテキストを選択。</li>
              <li>AI操作から <strong>解説</strong> または <strong>翻訳</strong> を選ぶ。</li>
            </ol>
            <ul>
              <li>難しい概念をやさしい表現に言い換える。</li>
              <li>多言語テキストを即時翻訳する。</li>
            </ul>

            <h2>7. Highlights &amp; Notes（一覧と共有）</h2>
            <p>読書中のハイライトとメモは1ページに整理されます。</p>
            <ul>
              <li>素早く一覧し、元の位置へジャンプ可能。</li>
              <li>カード形式で共有しやすい。</li>
            </ul>

            <h2>8. Notion連携で自動同期</h2>
            <ol>
              <li><strong>Settings</strong> を開く。</li>
              <li><strong>Notion</strong> 連携を選択。</li>
              <li>認証後、同期先ページ/DBを指定。</li>
            </ol>
            <p>書名、著者、抜粋、メモ、タグを長期的に検索できる形で保存できます。</p>

            <h2>9. テーマと表示設定</h2>
            <ul>
              <li>夜はダークテーマ。</li>
              <li>日中はライトテーマ。</li>
              <li>フォントや余白を調整して疲れを減らす。</li>
            </ul>

            <h2>10. まとめ: 読書成果を知識として残す</h2>
            <ol>
              <li>Libraryで取り込み。</li>
              <li>Summarizeで全体地図を作る。</li>
              <li>Skimmingで構造を把握。</li>
              <li>注釈で理解を深める。</li>
              <li>AI質問で理解を補強。</li>
              <li>Highlights &amp; Notesで整理。</li>
              <li>Notionへ同期して再利用する。</li>
            </ol>
            """
        ).strip(),
        "next_steps_title": "今すぐできる次のアクション",
        "next_steps": [
            "最初のEPUBを取り込んでみる。",
            "このサンプルで1回フルフローを練習する。",
        ],
        "closing": "よい読書を。",
    },
    {
        "code": "zh",
        "nav": "中文",
        "title": "LanRead 使用指南（中文）",
        "quick_start_title": "3 分钟上手",
        "quick_start_flow": "导入一本书 -> AI 梳理 -> 速读 -> 高亮与笔记 -> 同步到 Notion -> 分享",
        "tip": "小提示：这本书本身就是可操作演示。你可以随时高亮、写笔记，或选中文字让 AI 解释和翻译。",
        "toc_title": "目录",
        "toc": [
            "1. 欢迎来到 LanRead",
            "2. 第一步：从 Library 导入你的本地 EPUB",
            "3. 导入后第一站：AI Summarize（全书概要）",
            "4. Skimming Mode（速读模式）",
            "5. 阅读的基础能力：书签 / 高亮 / 笔记",
            "6. 选中文字让 AI 解释与翻译",
            "7. Highlights & Notes（精美汇总与分享）",
            "8. 连接 Notion，自动同步高亮与笔记",
            "9. 主题与外观：在设置中切换阅读主题",
            "10. 结束语：把阅读成果沉淀成你的知识库",
        ],
        "content": dedent(
            """
            <h2>1. 欢迎来到 LanRead</h2>
            <p>LanRead 不只是一款 EPUB 阅读器，它是一个基于 AI 的读书理解与知识沉淀工具。</p>
            <ul>
              <li>导入一本书后，AI 会先帮你梳理全书结构与重点。</li>
              <li>通过 Skimming Mode，用章节级摘要快速抓住脉络。</li>
              <li>阅读中可随时高亮、记笔记，并对选中文字发起 AI 解释/翻译。</li>
              <li>最后在 Highlights &amp; Notes 汇总成果，并可同步到 Notion。</li>
            </ul>
            <p class="quote">这本示例书包含可操作段落。你可以立刻选中一句话，试试 AI 解释功能。</p>

            <h2>2. 第一步：从 Library 导入你的本地 EPUB</h2>
            <p>LanRead 的阅读从 <strong>Library（书库）</strong> 开始。</p>
            <ol>
              <li>打开首页 <strong>Library</strong>。</li>
              <li>点击 <strong>导入</strong>。</li>
              <li>从系统 Files 里选择本地 <strong>EPUB</strong>。</li>
            </ol>
            <ul>
              <li>导入成功后，书会立刻出现在 Library 中。</li>
              <li>你可以搜索、收藏、并更新阅读状态（想读/在读/暂停/已读）。</li>
            </ul>

            <h2>3. 导入后第一站：AI Summarize（全书概要）</h2>
            <p>Summarize 的目标是让你在最短时间知道这本书讲什么、结构如何组织。</p>
            <ul>
              <li>第一次读陌生书：先看 Summarize，决定是否深入。</li>
              <li>读完回顾：再看 Summarize，快速复盘主线。</li>
            </ul>

            <h2>4. Skimming Mode（速读模式）</h2>
            <p>如果 Summarize 是全书预告片，Skimming Mode 就是章节级快速扫描。</p>
            <ul>
              <li>在 Summarize 页面通过按钮或手势进入。</li>
              <li>查看章节要点、关键句、关键词和引导问题。</li>
              <li>先扫全书结构，再跳回正文精读重点章节。</li>
            </ul>
            <p class="quote">“读书不是从第一页开始，而是从结构开始。”</p>

            <h2>5. 阅读的基础能力：书签 / 高亮 / 笔记</h2>
            <ul>
              <li><strong>书签（Bookmark）</strong>：标记你要回来的位置。</li>
              <li><strong>高亮（Highlight）</strong>：标记定义、结论、金句和关键例子。</li>
              <li><strong>笔记（Note）</strong>：记录理解、疑问和行动项（TODO）。</li>
            </ul>
            <p class="note">建议你在本书里先做 2~3 条高亮和 1 条笔记，后面可在 Highlights &amp; Notes 看到汇总效果。</p>

            <h2>6. 选中文字让 AI 解释与翻译</h2>
            <p>LanRead 的 AI 像阅读助教，不只是写摘要。</p>
            <ol>
              <li>长按并选中一段文字。</li>
              <li>选择 AI 操作：<strong>解释</strong> 或 <strong>翻译</strong>。</li>
            </ol>
            <ul>
              <li>概念看不懂时，让 AI 用更简单的话解释。</li>
              <li>读英文原文时，直接翻译成中文。</li>
              <li>写英文笔记时，让 AI 帮你润色成自然表达。</li>
            </ul>

            <h2>7. Highlights &amp; Notes（精美汇总与分享）</h2>
            <p>你在阅读中的高亮与笔记会被集中整理在同一个页面。</p>
            <ul>
              <li>清晰排版，支持快速浏览和回跳原文。</li>
              <li>可直接分享成读书卡片或社交内容。</li>
            </ul>

            <h2>8. 连接 Notion，自动同步高亮与笔记</h2>
            <p>如果你想把阅读成果长期沉淀，LanRead 提供 Notion 自动同步。</p>
            <ol>
              <li>打开 <strong>Settings（设置）</strong>。</li>
              <li>进入 <strong>Notion</strong> 相关入口。</li>
              <li>按引导完成授权。</li>
              <li>选择或创建用于存放读书笔记的页面/数据库。</li>
            </ol>
            <p>同步后你可以在 Notion 按关键词、标签和主题进行检索与复盘。</p>

            <h2>9. 主题与外观：在设置中切换阅读主题</h2>
            <p>每个人的阅读习惯不同，你可以按场景调整主题与排版。</p>
            <ul>
              <li>夜间阅读：使用深色主题。</li>
              <li>白天阅读：使用浅色主题。</li>
              <li>按需调整字体和行距，降低阅读疲劳。</li>
            </ul>

            <h2>10. 结束语：把阅读成果沉淀成你的知识库</h2>
            <p>LanRead 希望帮助你完成完整读书闭环：</p>
            <ol>
              <li>导入一本书（Library）。</li>
              <li>AI 先帮你建立地图（Summarize）。</li>
              <li>速读抓结构（Skimming Mode）。</li>
              <li>精读做标注（书签/高亮/笔记）。</li>
              <li>选中即问（AI 解释/翻译）。</li>
              <li>汇总沉淀（Highlights &amp; Notes）。</li>
              <li>同步外部知识库（Notion）。</li>
            </ol>
            """
        ).strip(),
        "next_steps_title": "下一步你可以做",
        "next_steps": [
            "现在就导入你的第一本 EPUB。",
            "或者先用这本示例书完整练习一遍流程。",
        ],
        "closing": "祝你阅读愉快！",
    },
    {
        "code": "ko",
        "nav": "한국어",
        "title": "LanRead 사용 가이드 (한국어)",
        "quick_start_title": "3분 시작",
        "quick_start_flow": "책 가져오기 -> AI 개요 -> 훑어보기 -> 하이라이트/노트 -> Notion 동기화 -> 공유",
        "tip": "팁: 이 샘플은 바로 실습할 수 있습니다. 문장을 선택해 하이라이트, 메모, AI 설명/번역을 시험해 보세요.",
        "toc_title": "목차",
        "toc": [
            "1. LanRead에 오신 것을 환영합니다",
            "2. 1단계: Library에서 EPUB 가져오기",
            "3. 가져온 뒤 첫 화면: AI Summarize",
            "4. Skimming Mode",
            "5. 기본 읽기 기능: 북마크 / 하이라이트 / 노트",
            "6. 텍스트 선택 후 AI 설명/번역",
            "7. Highlights & Notes 요약과 공유",
            "8. Notion 연결 및 자동 동기화",
            "9. 테마와 화면 설정",
            "10. 마무리: 읽기 결과를 지식으로 축적",
        ],
        "content": dedent(
            """
            <h2>1. LanRead에 오신 것을 환영합니다</h2>
            <p>LanRead는 단순 EPUB 뷰어가 아니라 AI 기반 독서 이해와 지식 정리를 위한 도구입니다.</p>
            <ul>
              <li>가져오기 직후 AI가 책의 구조와 핵심을 먼저 정리합니다.</li>
              <li>Skimming Mode로 장 단위 요약을 빠르게 확인할 수 있습니다.</li>
              <li>읽는 중 하이라이트/노트, 선택 텍스트 설명/번역을 바로 실행할 수 있습니다.</li>
              <li>결과는 Highlights &amp; Notes와 Notion 동기화로 누적됩니다.</li>
            </ul>

            <h2>2. 1단계: Library에서 EPUB 가져오기</h2>
            <ol>
              <li>홈에서 <strong>Library</strong>를 엽니다.</li>
              <li><strong>가져오기</strong>를 누릅니다.</li>
              <li>Files에서 로컬 <strong>EPUB</strong>를 선택합니다.</li>
            </ol>
            <p>가져오기 후 책이 Library에 표시되고 검색/즐겨찾기/상태 관리가 가능합니다.</p>

            <h2>3. 가져온 뒤 첫 화면: AI Summarize</h2>
            <p>Summarize는 책의 핵심 주제와 구조를 짧은 시간에 파악하게 해줍니다.</p>
            <ul>
              <li>처음 읽는 책의 사전 지도.</li>
              <li>완독 후 빠른 복습 도구.</li>
            </ul>

            <h2>4. Skimming Mode</h2>
            <p>Skimming Mode는 장 단위 AI 요약으로 전체 흐름을 빠르게 훑어보는 기능입니다.</p>
            <ul>
              <li>Summarize 화면에서 버튼/제스처로 진입.</li>
              <li>핵심 포인트, 핵심 문장, 키워드, 가이드 질문 확인.</li>
              <li>중요 장은 원문으로 즉시 점프해 정독.</li>
            </ul>
            <p class="quote">"독서는 첫 페이지가 아니라 구조에서 시작됩니다."</p>

            <h2>5. 기본 읽기 기능: 북마크 / 하이라이트 / 노트</h2>
            <ul>
              <li><strong>북마크</strong>: 다시 돌아올 위치를 저장.</li>
              <li><strong>하이라이트</strong>: 중요한 문장 표시.</li>
              <li><strong>노트</strong>: 내 해석, 질문, 실행 항목 기록.</li>
            </ul>

            <h2>6. 텍스트 선택 후 AI 설명/번역</h2>
            <ol>
              <li>문장을 길게 눌러 선택.</li>
              <li>AI 작업에서 <strong>설명</strong> 또는 <strong>번역</strong> 선택.</li>
            </ol>
            <ul>
              <li>어려운 개념을 쉬운 말로 재설명.</li>
              <li>다국어 원문을 즉시 번역.</li>
            </ul>

            <h2>7. Highlights &amp; Notes 요약과 공유</h2>
            <p>하이라이트와 노트를 한 화면에 정리해 확인할 수 있습니다.</p>
            <ul>
              <li>빠르게 훑고 원문 위치로 돌아가기.</li>
              <li>정리된 카드 형태로 공유하기.</li>
            </ul>

            <h2>8. Notion 연결 및 자동 동기화</h2>
            <ol>
              <li><strong>Settings</strong> 열기.</li>
              <li><strong>Notion</strong> 항목 선택.</li>
              <li>권한 승인 후 대상 페이지/DB 지정.</li>
            </ol>
            <p>책 제목, 저자, 하이라이트, 노트, 태그를 장기적으로 검색 가능한 형태로 보관합니다.</p>

            <h2>9. 테마와 화면 설정</h2>
            <ul>
              <li>야간: 다크 테마.</li>
              <li>주간: 라이트 테마.</li>
              <li>글꼴/줄간격 조정으로 피로도 감소.</li>
            </ul>

            <h2>10. 마무리: 읽기 결과를 지식으로 축적</h2>
            <ol>
              <li>Library에서 책 가져오기.</li>
              <li>Summarize로 전체 지도 만들기.</li>
              <li>Skimming Mode로 구조 파악.</li>
              <li>북마크/하이라이트/노트로 정독.</li>
              <li>선택 텍스트에 AI 질의.</li>
              <li>Highlights &amp; Notes로 정리.</li>
              <li>Notion으로 동기화하여 재사용.</li>
            </ol>
            """
        ).strip(),
        "next_steps_title": "지금 바로 할 수 있는 다음 단계",
        "next_steps": [
            "첫 EPUB를 지금 가져오기.",
            "이 샘플로 전체 흐름을 한 번 실습하기.",
        ],
        "closing": "즐거운 독서 되세요!",
    },
    {
        "code": "es",
        "nav": "Español",
        "title": "Guía de uso de LanRead (Español)",
        "quick_start_title": "Inicio en 3 minutos",
        "quick_start_flow": "Importar un libro -> Resumen IA -> Skimming -> Subrayados y notas -> Sincronizar con Notion -> Compartir",
        "tip": "Consejo: Este libro es interactivo. Puedes subrayar, escribir notas o seleccionar una frase para pedir explicación/traducción con IA.",
        "toc_title": "Contenido",
        "toc": [
            "1. Bienvenido a LanRead",
            "2. Paso 1: importar EPUB desde Library",
            "3. Primera parada: AI Summarize",
            "4. Skimming Mode",
            "5. Funciones base: marcador / subrayado / nota",
            "6. Seleccionar texto para explicar o traducir",
            "7. Highlights & Notes: resumen y compartir",
            "8. Conectar Notion para sincronización automática",
            "9. Tema y apariencia",
            "10. Cierre: convertir lectura en base de conocimiento",
        ],
        "content": dedent(
            """
            <h2>1. Bienvenido a LanRead</h2>
            <p>LanRead no es solo un lector EPUB; es un flujo de lectura asistido por IA para entender y conservar conocimiento.</p>
            <ul>
              <li>Tras importar, IA organiza estructura y puntos clave del libro.</li>
              <li>Skimming Mode resume cada capítulo para ver el panorama completo.</li>
              <li>Durante la lectura puedes subrayar, anotar y usar IA sobre texto seleccionado.</li>
              <li>Tus resultados se recopilan y se pueden sincronizar con Notion.</li>
            </ul>

            <h2>2. Paso 1: importar EPUB desde Library</h2>
            <ol>
              <li>Abre <strong>Library</strong>.</li>
              <li>Pulsa <strong>Importar</strong>.</li>
              <li>Elige un <strong>EPUB</strong> local en Files.</li>
            </ol>
            <p>El libro aparecerá en Library con búsqueda, favoritos y estado de lectura.</p>

            <h2>3. Primera parada: AI Summarize</h2>
            <p>Summarize te da una vista rápida del contenido y de la estructura del libro.</p>
            <ul>
              <li>Úsalo antes de leer para decidir profundidad.</li>
              <li>Úsalo después para repasar.</li>
            </ul>

            <h2>4. Skimming Mode</h2>
            <p>Escaneo rápido por capítulos con resumen IA.</p>
            <ul>
              <li>Entrada desde Summarize por botón o gesto.</li>
              <li>Muestra ideas clave, frases clave, palabras clave y preguntas guía.</li>
              <li>Vuelve al texto completo cuando encuentres una sección importante.</li>
            </ul>

            <h2>5. Funciones base: marcador / subrayado / nota</h2>
            <ul>
              <li><strong>Marcador</strong>: guardar posición para volver.</li>
              <li><strong>Subrayado</strong>: marcar líneas importantes.</li>
              <li><strong>Nota</strong>: registrar interpretación personal y tareas.</li>
            </ul>

            <h2>6. Seleccionar texto para explicar o traducir</h2>
            <ol>
              <li>Mantén pulsado y selecciona una frase.</li>
              <li>Elige acción IA: <strong>Explicar</strong> o <strong>Traducir</strong>.</li>
            </ol>
            <p>Ideal para conceptos difíciles, lectura multilingüe y notas bilingües.</p>

            <h2>7. Highlights &amp; Notes: resumen y compartir</h2>
            <ul>
              <li>Vista ordenada de subrayados y notas.</li>
              <li>Navegación rápida y retorno al texto original.</li>
              <li>Compartir como tarjetas de lectura.</li>
            </ul>

            <h2>8. Conectar Notion para sincronización automática</h2>
            <ol>
              <li>Abre <strong>Settings</strong>.</li>
              <li>Entra en <strong>Notion</strong>.</li>
              <li>Autoriza y selecciona la base de destino.</li>
            </ol>
            <p>Así tu lectura queda en un repositorio consultable a largo plazo.</p>

            <h2>9. Tema y apariencia</h2>
            <ul>
              <li>Noche: tema oscuro.</li>
              <li>Día: tema claro.</li>
              <li>Ajusta tipografía y espaciado según tu hábito.</li>
            </ul>

            <h2>10. Cierre: convertir lectura en base de conocimiento</h2>
            <ol>
              <li>Importar en Library.</li>
              <li>Crear mapa con Summarize.</li>
              <li>Escanear estructura con Skimming.</li>
              <li>Anotar con marcador/subrayado/nota.</li>
              <li>Preguntar a IA sobre texto seleccionado.</li>
              <li>Revisar en Highlights &amp; Notes.</li>
              <li>Sincronizar con Notion.</li>
            </ol>
            """
        ).strip(),
        "next_steps_title": "Próximos pasos",
        "next_steps": [
            "Importa ahora tu primer EPUB.",
            "O practica el flujo completo con este libro de ejemplo.",
        ],
        "closing": "¡Feliz lectura!",
    },
    {
        "code": "de",
        "nav": "Deutsch",
        "title": "LanRead Leitfaden (Deutsch)",
        "quick_start_title": "Start in 3 Minuten",
        "quick_start_flow": "Buch importieren -> KI-Überblick -> Skimming -> Markieren & Notieren -> Notion-Sync -> Teilen",
        "tip": "Hinweis: Dieses Buch ist interaktiv. Du kannst Text markieren, Notizen schreiben oder KI-Erklärung/Übersetzung testen.",
        "toc_title": "Inhalt",
        "toc": [
            "1. Willkommen bei LanRead",
            "2. Schritt 1: EPUB in der Library importieren",
            "3. Erster Schritt danach: AI Summarize",
            "4. Skimming Mode",
            "5. Basisfunktionen: Lesezeichen / Markierung / Notiz",
            "6. Text auswählen und KI nutzen",
            "7. Highlights & Notes: Übersicht und Teilen",
            "8. Notion verbinden und automatisch synchronisieren",
            "9. Thema und Darstellung",
            "10. Abschluss: Lesewissen nachhaltig sichern",
        ],
        "content": dedent(
            """
            <h2>1. Willkommen bei LanRead</h2>
            <p>LanRead ist nicht nur ein EPUB-Reader, sondern ein KI-gestützter Leseworkflow zur Wissenssicherung.</p>
            <ul>
              <li>Nach dem Import erstellt KI eine Strukturkarte des Buchs.</li>
              <li>Skimming Mode liefert Kapitelzusammenfassungen im Schnelllauf.</li>
              <li>Beim Lesen kannst du markieren, notieren und ausgewählten Text mit KI erklären/übersetzen.</li>
              <li>Ergebnisse werden in Highlights &amp; Notes gesammelt und optional nach Notion synchronisiert.</li>
            </ul>

            <h2>2. Schritt 1: EPUB in der Library importieren</h2>
            <ol>
              <li><strong>Library</strong> öffnen.</li>
              <li><strong>Importieren</strong> antippen.</li>
              <li>Lokale <strong>EPUB</strong>-Datei in Files wählen.</li>
            </ol>
            <p>Danach ist das Buch in der Library sichtbar, inklusive Suche, Favoriten und Lesestatus.</p>

            <h2>3. Erster Schritt danach: AI Summarize</h2>
            <p>Summarize zeigt dir Thema, Struktur und Kernpunkte in kurzer Zeit.</p>
            <ul>
              <li>Vor dem Lesen zur Orientierung.</li>
              <li>Nach dem Lesen zur Wiederholung.</li>
            </ul>

            <h2>4. Skimming Mode</h2>
            <p>Kapitelweiser KI-Scan für den schnellen Gesamtüberblick.</p>
            <ul>
              <li>Einstieg über Summarize (Button oder Geste).</li>
              <li>Zeigt Kernideen, Schlüsselsätze, Keywords und Leitfragen.</li>
              <li>Direkter Sprung zurück in den Volltext.</li>
            </ul>

            <h2>5. Basisfunktionen: Lesezeichen / Markierung / Notiz</h2>
            <ul>
              <li><strong>Lesezeichen</strong>: Position für später sichern.</li>
              <li><strong>Markierung</strong>: wichtige Sätze hervorheben.</li>
              <li><strong>Notiz</strong>: eigene Gedanken und To-dos festhalten.</li>
            </ul>

            <h2>6. Text auswählen und KI nutzen</h2>
            <ol>
              <li>Textstelle lang drücken und auswählen.</li>
              <li>KI-Aktion wählen: <strong>Erklären</strong> oder <strong>Übersetzen</strong>.</li>
            </ol>
            <p>Hilfreich bei schwierigen Begriffen und mehrsprachigen Inhalten.</p>

            <h2>7. Highlights &amp; Notes: Übersicht und Teilen</h2>
            <ul>
              <li>Alle Markierungen und Notizen sauber gesammelt.</li>
              <li>Schnellansicht und Rücksprung zur Originalstelle.</li>
              <li>Einfaches Teilen als Lesekarten.</li>
            </ul>

            <h2>8. Notion verbinden und automatisch synchronisieren</h2>
            <ol>
              <li><strong>Settings</strong> öffnen.</li>
              <li><strong>Notion</strong> auswählen.</li>
              <li>Autorisieren und Zielseite/DB festlegen.</li>
            </ol>
            <p>So entsteht eine langfristig durchsuchbare Wissensdatenbank.</p>

            <h2>9. Thema und Darstellung</h2>
            <ul>
              <li>Nacht: dunkles Theme.</li>
              <li>Tag: helles Theme.</li>
              <li>Schriftbild und Abstände individuell anpassen.</li>
            </ul>

            <h2>10. Abschluss: Lesewissen nachhaltig sichern</h2>
            <ol>
              <li>Import in der Library.</li>
              <li>Überblick per Summarize.</li>
              <li>Struktur-Scan mit Skimming.</li>
              <li>Markieren und Notieren im Volltext.</li>
              <li>KI-Fragen auf ausgewählten Text.</li>
              <li>Review in Highlights &amp; Notes.</li>
              <li>Sync nach Notion.</li>
            </ol>
            """
        ).strip(),
        "next_steps_title": "Nächste Schritte",
        "next_steps": [
            "Importiere jetzt dein erstes EPUB.",
            "Oder übe den gesamten Ablauf mit diesem Demo-Buch.",
        ],
        "closing": "Viel Freude beim Lesen!",
    },
    {
        "code": "fr",
        "nav": "Français",
        "title": "Guide d'utilisation LanRead (Français)",
        "quick_start_title": "Démarrage en 3 minutes",
        "quick_start_flow": "Importer un livre -> Résumé IA -> Skimming -> Surlignages et notes -> Sync Notion -> Partage",
        "tip": "Astuce : ce livre est interactif. Vous pouvez surligner, annoter, ou demander à l'IA d'expliquer/traduire un passage.",
        "toc_title": "Sommaire",
        "toc": [
            "1. Bienvenue sur LanRead",
            "2. Étape 1 : importer un EPUB depuis Library",
            "3. Première étape après import : AI Summarize",
            "4. Skimming Mode",
            "5. Fonctions de base : signet / surlignage / note",
            "6. Sélection de texte avec IA",
            "7. Highlights & Notes : synthèse et partage",
            "8. Connecter Notion et synchroniser automatiquement",
            "9. Thème et apparence",
            "10. Conclusion : transformer la lecture en base de connaissances",
        ],
        "content": dedent(
            """
            <h2>1. Bienvenue sur LanRead</h2>
            <p>LanRead est plus qu'un lecteur EPUB : c'est un flux de lecture assisté par IA pour comprendre et capitaliser.</p>
            <ul>
              <li>Après import, l'IA construit la carte de structure du livre.</li>
              <li>Skimming Mode résume chaque chapitre pour un survol rapide.</li>
              <li>Pendant la lecture : surlignage, notes, explication/traduction IA du texte sélectionné.</li>
              <li>Les résultats sont centralisés et synchronisables vers Notion.</li>
            </ul>

            <h2>2. Étape 1 : importer un EPUB depuis Library</h2>
            <ol>
              <li>Ouvrir <strong>Library</strong>.</li>
              <li>Appuyer sur <strong>Importer</strong>.</li>
              <li>Choisir un <strong>EPUB</strong> local dans Files.</li>
            </ol>
            <p>Le livre apparaît ensuite dans Library avec recherche, favoris et statut de lecture.</p>

            <h2>3. Première étape après import : AI Summarize</h2>
            <p>Summarize donne rapidement les thèmes, la structure et les points clés.</p>
            <ul>
              <li>Avant lecture : décider du niveau d'approfondissement.</li>
              <li>Après lecture : révision rapide.</li>
            </ul>

            <h2>4. Skimming Mode</h2>
            <p>Balayage rapide du livre par résumés IA chapitre par chapitre.</p>
            <ul>
              <li>Entrée depuis Summarize via bouton ou geste.</li>
              <li>Affiche points structurants, phrases clés, mots-clés et questions guides.</li>
              <li>Retour direct au texte intégral pour approfondir.</li>
            </ul>

            <h2>5. Fonctions de base : signet / surlignage / note</h2>
            <ul>
              <li><strong>Signet</strong> : marquer une position à retrouver.</li>
              <li><strong>Surlignage</strong> : conserver les passages importants.</li>
              <li><strong>Note</strong> : capturer votre compréhension et vos actions.</li>
            </ul>

            <h2>6. Sélection de texte avec IA</h2>
            <ol>
              <li>Appui long pour sélectionner un passage.</li>
              <li>Choisir <strong>Expliquer</strong> ou <strong>Traduire</strong>.</li>
            </ol>
            <p>Très utile pour les concepts complexes et la lecture multilingue.</p>

            <h2>7. Highlights &amp; Notes : synthèse et partage</h2>
            <ul>
              <li>Vue propre de tous les surlignages et notes.</li>
              <li>Navigation rapide et retour vers le texte source.</li>
              <li>Partage simplifié sous forme de cartes de lecture.</li>
            </ul>

            <h2>8. Connecter Notion et synchroniser automatiquement</h2>
            <ol>
              <li>Ouvrir <strong>Settings</strong>.</li>
              <li>Entrer dans <strong>Notion</strong>.</li>
              <li>Autoriser puis choisir la destination.</li>
            </ol>
            <p>Vous construisez ainsi une base de connaissances durable et interrogeable.</p>

            <h2>9. Thème et apparence</h2>
            <ul>
              <li>Nuit : thème sombre.</li>
              <li>Jour : thème clair.</li>
              <li>Ajuster police et espacement selon vos habitudes.</li>
            </ul>

            <h2>10. Conclusion : transformer la lecture en base de connaissances</h2>
            <ol>
              <li>Importer dans Library.</li>
              <li>Créer la carte avec Summarize.</li>
              <li>Parcourir la structure avec Skimming.</li>
              <li>Annoter avec signet/surlignage/note.</li>
              <li>Interroger l'IA sur texte sélectionné.</li>
              <li>Réviser dans Highlights &amp; Notes.</li>
              <li>Synchroniser vers Notion.</li>
            </ol>
            """
        ).strip(),
        "next_steps_title": "Prochaines actions",
        "next_steps": [
            "Importez maintenant votre premier EPUB.",
            "Ou entraînez-vous avec ce livre de démonstration.",
        ],
        "closing": "Bonne lecture !",
    },
    {
        "code": "it",
        "nav": "Italiano",
        "title": "Guida LanRead (Italiano)",
        "quick_start_title": "Avvio in 3 minuti",
        "quick_start_flow": "Importa un libro -> Riepilogo AI -> Skimming -> Evidenziazioni e note -> Sync Notion -> Condividi",
        "tip": "Suggerimento: questo libro è interattivo. Puoi evidenziare, annotare o chiedere all'AI spiegazione/traduzione.",
        "toc_title": "Indice",
        "toc": [
            "1. Benvenuto in LanRead",
            "2. Passo 1: importa EPUB dalla Library",
            "3. Primo step dopo import: AI Summarize",
            "4. Skimming Mode",
            "5. Funzioni base: segnalibro / evidenziazione / nota",
            "6. Seleziona testo e usa AI",
            "7. Highlights & Notes: riepilogo e condivisione",
            "8. Collega Notion e sincronizza automaticamente",
            "9. Tema e aspetto",
            "10. Conclusione: trasforma la lettura in conoscenza",
        ],
        "content": dedent(
            """
            <h2>1. Benvenuto in LanRead</h2>
            <p>LanRead non è solo un lettore EPUB: è un flusso di lettura assistito da AI per comprendere e conservare conoscenza.</p>
            <ul>
              <li>Dopo l'importazione, l'AI crea una mappa della struttura del libro.</li>
              <li>Skimming Mode offre riepiloghi per capitolo in modo rapido.</li>
              <li>Durante la lettura puoi evidenziare, scrivere note e usare AI sul testo selezionato.</li>
              <li>I risultati finiscono in Highlights &amp; Notes e possono sincronizzarsi con Notion.</li>
            </ul>

            <h2>2. Passo 1: importa EPUB dalla Library</h2>
            <ol>
              <li>Apri <strong>Library</strong>.</li>
              <li>Tocca <strong>Importa</strong>.</li>
              <li>Scegli un file <strong>EPUB</strong> locale da Files.</li>
            </ol>
            <p>Il libro appare subito in Library con ricerca, preferiti e stato di lettura.</p>

            <h2>3. Primo step dopo import: AI Summarize</h2>
            <p>Summarize mostra in poco tempo temi, struttura e punti chiave del libro.</p>
            <ul>
              <li>Prima di leggere: orientamento veloce.</li>
              <li>Dopo la lettura: ripasso rapido.</li>
            </ul>

            <h2>4. Skimming Mode</h2>
            <p>Scansione rapida del libro con sintesi AI per capitolo.</p>
            <ul>
              <li>Accesso da Summarize tramite pulsante o gesto.</li>
              <li>Mostra punti strutturali, frasi chiave, keyword e domande guida.</li>
              <li>Salto diretto al testo completo per approfondire.</li>
            </ul>

            <h2>5. Funzioni base: segnalibro / evidenziazione / nota</h2>
            <ul>
              <li><strong>Segnalibro</strong>: salva una posizione da rivedere.</li>
              <li><strong>Evidenziazione</strong>: marca frasi importanti.</li>
              <li><strong>Nota</strong>: registra interpretazioni personali e TODO.</li>
            </ul>

            <h2>6. Seleziona testo e usa AI</h2>
            <ol>
              <li>Tieni premuto e seleziona un passaggio.</li>
              <li>Scegli <strong>Spiega</strong> o <strong>Traduci</strong>.</li>
            </ol>
            <p>Utile per concetti complessi e contenuti multilingue.</p>

            <h2>7. Highlights &amp; Notes: riepilogo e condivisione</h2>
            <ul>
              <li>Raccoglie in modo ordinato evidenziazioni e note.</li>
              <li>Navigazione veloce e ritorno al testo originale.</li>
              <li>Condivisione semplice in formato card.</li>
            </ul>

            <h2>8. Collega Notion e sincronizza automaticamente</h2>
            <ol>
              <li>Apri <strong>Settings</strong>.</li>
              <li>Entra nella sezione <strong>Notion</strong>.</li>
              <li>Autorizza e scegli pagina/database di destinazione.</li>
            </ol>
            <p>Così ottieni una base conoscenza ricercabile nel tempo.</p>

            <h2>9. Tema e aspetto</h2>
            <ul>
              <li>Notte: tema scuro.</li>
              <li>Giorno: tema chiaro.</li>
              <li>Regola font e spaziatura in base alle abitudini.</li>
            </ul>

            <h2>10. Conclusione: trasforma la lettura in conoscenza</h2>
            <ol>
              <li>Importa da Library.</li>
              <li>Costruisci la mappa con Summarize.</li>
              <li>Scansiona la struttura con Skimming.</li>
              <li>Annota con segnalibro/evidenziazione/nota.</li>
              <li>Interroga AI sul testo selezionato.</li>
              <li>Rivedi in Highlights &amp; Notes.</li>
              <li>Sincronizza su Notion.</li>
            </ol>
            """
        ).strip(),
        "next_steps_title": "Prossime azioni",
        "next_steps": [
            "Importa ora il tuo primo EPUB.",
            "Oppure prova un ciclo completo con questo libro demo.",
        ],
        "closing": "Buona lettura!",
    },
]

STYLE_CSS = """body {
  font-family: -apple-system, BlinkMacSystemFont, \"Segoe UI\", sans-serif;
  margin: 1.2em;
  line-height: 1.68;
  color: #1f2937;
}
h1 {
  font-size: 1.7em;
  margin-bottom: 0.4em;
}
h2 {
  margin-top: 1.35em;
  border-left: 4px solid #2f6bff;
  padding-left: 0.5em;
  font-size: 1.16em;
}
p {
  margin: 0.58em 0;
}
ol, ul {
  padding-left: 1.25em;
  margin: 0.48em 0;
}
li {
  margin: 0.3em 0;
}
.note {
  margin-top: 0.85em;
  padding: 0.8em;
  border-radius: 10px;
  background: #f3f7ff;
}
.quote {
  margin-top: 0.8em;
  padding: 0.75em 0.85em;
  border-left: 4px solid #7aa2ff;
  background: #f7f9ff;
  border-radius: 8px;
}
.kicker {
  margin-top: 0.2em;
  color: #0f5bd8;
}
.flow {
  font-weight: 600;
}
"""


def xhtml_doc(lang_code: str, title: str, body: str) -> str:
    return f"""<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE html>
<html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:epub=\"http://www.idpf.org/2007/ops\" xml:lang=\"{lang_code}\" lang=\"{lang_code}\">
  <head>
    <meta charset=\"utf-8\"/>
    <title>{title}</title>
    <link rel=\"stylesheet\" type=\"text/css\" href=\"../styles/style.css\"/>
  </head>
  <body>
{body}
  </body>
</html>
"""


def chapter_body(section: dict[str, object]) -> str:
    toc_items = "\n".join(f"      <li>{item}</li>" for item in section["toc"])
    next_steps = "\n".join(f"      <li>{item}</li>" for item in section["next_steps"])
    return f"""    <h1>{section["title"]}</h1>
    <p class=\"kicker\"><strong>{section["quick_start_title"]}</strong></p>
    <p class=\"flow\">{section["quick_start_flow"]}</p>
    <p class=\"note\">{section["tip"]}</p>

    <h2>{section["toc_title"]}</h2>
    <ol>
{toc_items}
    </ol>

    {section["content"]}

    <h2>{section["next_steps_title"]}</h2>
    <ul>
{next_steps}
    </ul>
    <p><strong>{section["closing"]}</strong></p>
"""


def nav_xhtml() -> str:
    nav_items = "\n".join(
        f'          <li><a href="text/{section["code"]}.xhtml">{section["nav"]} - {section["title"]}</a></li>'
        for section in LANG_SECTIONS
    )
    return f"""<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE html>
<html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:epub=\"http://www.idpf.org/2007/ops\" xml:lang=\"en\" lang=\"en\">
  <head>
    <meta charset=\"UTF-8\"/>
    <title>Table of Contents</title>
  </head>
  <body>
    <nav epub:type=\"toc\" id=\"toc\">
      <h1>Table of Contents</h1>
      <ol>
{nav_items}
      </ol>
    </nav>
  </body>
</html>
"""


def toc_ncx() -> str:
    nav_points = "\n".join(
        f"""    <navPoint id=\"navPoint-{idx}\" playOrder=\"{idx}\">
      <navLabel><text>{section["nav"]} - {section["title"]}</text></navLabel>
      <content src=\"text/{section["code"]}.xhtml\"/>
    </navPoint>"""
        for idx, section in enumerate(LANG_SECTIONS, start=1)
    )
    return f"""<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE ncx PUBLIC "-//NISO//DTD ncx 2005-1//EN"
  "http://www.daisy.org/z3986/2005/ncx-2005-1.dtd">
<ncx xmlns=\"http://www.daisy.org/z3986/2005/ncx/\" version=\"2005-1\">
  <head>
    <meta name=\"dtb:uid\" content=\"{BOOK_ID}\"/>
    <meta name=\"dtb:depth\" content=\"1\"/>
    <meta name=\"dtb:totalPageCount\" content=\"0\"/>
    <meta name=\"dtb:maxPageNumber\" content=\"0\"/>
  </head>
  <docTitle><text>{BOOK_TITLE}</text></docTitle>
  <navMap>
{nav_points}
  </navMap>
</ncx>
"""


def content_opf() -> str:
    manifest_items = [
        '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>',
        '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>',
        '<item id="style" href="styles/style.css" media-type="text/css"/>',
    ]
    manifest_items.extend(
        f'<item id="ch-{section["code"]}" href="text/{section["code"]}.xhtml" media-type="application/xhtml+xml"/>'
        for section in LANG_SECTIONS
    )

    spine_items = "\n".join(f'    <itemref idref="ch-{section["code"]}"/>' for section in LANG_SECTIONS)
    manifest = "\n    ".join(manifest_items)
    return f"""<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<package xmlns=\"http://www.idpf.org/2007/opf\" version=\"3.0\" unique-identifier=\"bookid\">
  <metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\">
    <dc:identifier id=\"bookid\">{BOOK_ID}</dc:identifier>
    <dc:title>{BOOK_TITLE}</dc:title>
    <dc:creator>{BOOK_AUTHOR}</dc:creator>
    <dc:language>en</dc:language>
  </metadata>
  <manifest>
    {manifest}
  </manifest>
  <spine toc=\"ncx\">
{spine_items}
  </spine>
</package>
"""


def container_xml() -> str:
    return """<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
"""


def build_epub(output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(output_path, "w") as archive:
        archive.writestr("mimetype", "application/epub+zip", compress_type=ZIP_STORED)
        archive.writestr("META-INF/container.xml", container_xml(), compress_type=ZIP_DEFLATED)
        archive.writestr("OEBPS/content.opf", content_opf(), compress_type=ZIP_DEFLATED)
        archive.writestr("OEBPS/nav.xhtml", nav_xhtml(), compress_type=ZIP_DEFLATED)
        archive.writestr("OEBPS/toc.ncx", toc_ncx(), compress_type=ZIP_DEFLATED)
        archive.writestr("OEBPS/styles/style.css", STYLE_CSS, compress_type=ZIP_DEFLATED)

        for section in LANG_SECTIONS:
            chapter = xhtml_doc(str(section["code"]), str(section["title"]), chapter_body(section))
            archive.writestr(
                f'OEBPS/text/{section["code"]}.xhtml',
                chapter,
                compress_type=ZIP_DEFLATED,
            )


def main() -> None:
    build_epub(OUTPUT_PATH)
    print(f"Generated: {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
