#!/usr/bin/env python3
"""Generate the built-in multilingual LanRead demo EPUB."""

from __future__ import annotations

from pathlib import Path
from zipfile import ZIP_DEFLATED, ZIP_STORED, ZipFile

BOOK_ID = "urn:uuid:8f36f0e4-cc8e-4dad-9621-c64dc8ad0101"
BOOK_TITLE = "LanRead Quick Start (Multilingual)"
BOOK_AUTHOR = "LanRead Team"
OUTPUT_PATH = Path("Isla Reader/SampleBooks/LanRead_Getting_Started_Multilingual.epub")

LANG_SECTIONS = [
    {
        "code": "en",
        "nav": "English",
        "title": "English Quick Start",
        "intro": "This demo book helps new users and app reviewers verify LanRead features quickly.",
        "steps_title": "3-minute walkthrough",
        "steps": [
            "Open this book from the Library and check chapter navigation in the table of contents.",
            "Enter AI Summary and generate an overview from the first section.",
            "Tap Start Reading, create one highlight, and add one bookmark.",
            "Try Skimming Mode and return to your previous position.",
        ],
        "features_title": "Feature map",
        "features": [
            "Import & metadata parsing for EPUB files",
            "Reader typography settings and progress tracking",
            "AI reading guide, chapter summary, and key insight extraction",
            "Highlights, bookmarks, and status management in Library",
            "Language switch support in app-level localized UI",
        ],
        "review_title": "Review checklist",
        "review_note": "For App Review: this single EPUB is enough to test import, reading, AI summary trigger, and navigation.",
        "closing": "Continue to other language chapters from the table of contents.",
    },
    {
        "code": "ja",
        "nav": "日本語",
        "title": "日本語クイックスタート",
        "intro": "このデモ書籍は、LanRead の主要機能を短時間で確認するための案内です。",
        "steps_title": "3分で確認する手順",
        "steps": [
            "ライブラリで本書を開き、目次ジャンプと章移動を確認します。",
            "AI要約画面に入り、最初の章から要約を生成します。",
            "「読み始める」でリーダーを開き、ハイライト1件とブックマーク1件を追加します。",
            "略読モードを試し、元の読書位置へ戻ることを確認します。",
        ],
        "features_title": "機能マップ",
        "features": [
            "EPUB のインポートとメタデータ解析",
            "文字組み設定と読書進捗の管理",
            "AI導読、章要約、重要ポイント抽出",
            "ハイライト・ブックマーク・読書状態管理",
            "アプリUIの多言語切替対応",
        ],
        "review_title": "審査チェック",
        "review_note": "審査担当者向け: この1冊で、導入・読書・AI要約・ナビゲーションを確認できます。",
        "closing": "目次から他言語の章も確認できます。",
    },
    {
        "code": "zh",
        "nav": "中文",
        "title": "中文快速上手",
        "intro": "这本示例书用于帮助新用户和审核人员快速验证 LanRead 的核心能力。",
        "steps_title": "3 分钟体验路径",
        "steps": [
            "在书架打开本书，测试目录跳转与章节切换。",
            "进入 AI 导读摘要，对第一章生成一次摘要。",
            "点击“开始阅读”，添加 1 条高亮和 1 个书签。",
            "进入略读模式并返回，确认阅读位置保持正确。",
        ],
        "features_title": "功能地图",
        "features": [
            "EPUB 导入与元数据解析",
            "阅读排版设置与进度追踪",
            "AI 导读、章节摘要、关键洞察",
            "高亮、书签、阅读状态管理",
            "应用界面多语言切换",
        ],
        "review_title": "审核检查点",
        "review_note": "给审核人员：仅用这一本书即可验证导入、阅读、AI 摘要触发和导航流程。",
        "closing": "你可以从目录继续切换到其他语言章节。",
    },
    {
        "code": "ko",
        "nav": "한국어",
        "title": "한국어 빠른 시작",
        "intro": "이 샘플 도서는 신규 사용자와 심사자가 LanRead 기능을 빠르게 확인하도록 돕습니다.",
        "steps_title": "3분 점검 순서",
        "steps": [
            "라이브러리에서 이 책을 열고 목차 이동과 장 전환을 확인합니다.",
            "AI 요약 화면에서 첫 장 기준으로 요약을 생성합니다.",
            "읽기 시작 후 하이라이트 1개와 북마크 1개를 추가합니다.",
            "훑어보기 모드를 사용한 뒤 이전 읽기 위치로 돌아옵니다.",
        ],
        "features_title": "기능 맵",
        "features": [
            "EPUB 가져오기 및 메타데이터 파싱",
            "타이포그래피 설정과 읽기 진행률 추적",
            "AI 읽기 가이드, 장 요약, 핵심 인사이트",
            "하이라이트, 북마크, 라이브러리 상태 관리",
            "앱 UI 다국어 전환 지원",
        ],
        "review_title": "심사 체크",
        "review_note": "앱 심사용: 이 EPUB 한 권만으로 가져오기, 읽기, AI 요약, 탐색을 확인할 수 있습니다.",
        "closing": "목차에서 다른 언어 장도 확인해 보세요.",
    },
    {
        "code": "es",
        "nav": "Español",
        "title": "Inicio rápido en Español",
        "intro": "Este libro de muestra permite validar rápidamente las funciones principales de LanRead.",
        "steps_title": "Recorrido de 3 minutos",
        "steps": [
            "Abre este libro en la Biblioteca y verifica la navegación por capítulos.",
            "Entra en Resumen con IA y genera un resumen de la primera sección.",
            "Pulsa Empezar a leer, crea un subrayado y añade un marcador.",
            "Prueba el modo de lectura rápida y vuelve a tu posición anterior.",
        ],
        "features_title": "Mapa de funciones",
        "features": [
            "Importación EPUB y análisis de metadatos",
            "Ajustes tipográficos y seguimiento del progreso",
            "Guía de lectura con IA, resumen por capítulo y puntos clave",
            "Subrayados, marcadores y estado de lectura en Biblioteca",
            "Cambio de idioma en la interfaz de la app",
        ],
        "review_title": "Checklist de revisión",
        "review_note": "Para App Review: este único EPUB cubre importación, lectura, IA y navegación.",
        "closing": "Usa la tabla de contenidos para cambiar a otros idiomas.",
    },
    {
        "code": "de",
        "nav": "Deutsch",
        "title": "Deutsch Schnellstart",
        "intro": "Dieses Demo-Buch hilft dabei, die wichtigsten LanRead-Funktionen schnell zu prüfen.",
        "steps_title": "3-Minuten-Ablauf",
        "steps": [
            "Öffne dieses Buch in der Bibliothek und teste die Kapitelnavigation.",
            "Wechsle zur KI-Zusammenfassung und erzeuge eine Zusammenfassung des ersten Abschnitts.",
            "Starte das Lesen, erstelle eine Markierung und ein Lesezeichen.",
            "Teste den Skimming-Modus und kehre zur vorherigen Position zurück.",
        ],
        "features_title": "Funktionsübersicht",
        "features": [
            "EPUB-Import und Metadaten-Parsing",
            "Typografie-Einstellungen und Fortschrittstracking",
            "KI-Leseleitfaden, Kapitelzusammenfassung und Kernaussagen",
            "Markierungen, Lesezeichen und Lesestatus in der Bibliothek",
            "Mehrsprachige App-Oberfläche",
        ],
        "review_title": "Review-Checkliste",
        "review_note": "Für App Review: Diese eine EPUB-Datei reicht für Import, Lesen, KI-Auslösung und Navigation.",
        "closing": "Über das Inhaltsverzeichnis kannst du andere Sprachen öffnen.",
    },
    {
        "code": "fr",
        "nav": "Français",
        "title": "Démarrage rapide en Français",
        "intro": "Ce livre de démonstration permet de vérifier rapidement les fonctions clés de LanRead.",
        "steps_title": "Parcours en 3 minutes",
        "steps": [
            "Ouvrez ce livre dans la Bibliothèque et vérifiez la navigation par chapitres.",
            "Accédez au Résumé IA et générez un résumé de la première section.",
            "Appuyez sur Commencer la lecture, ajoutez un surlignage et un signet.",
            "Essayez le mode lecture rapide puis revenez à votre position.",
        ],
        "features_title": "Carte des fonctions",
        "features": [
            "Import EPUB et analyse des métadonnées",
            "Réglages typographiques et suivi de progression",
            "Guide de lecture IA, résumé de chapitre et points clés",
            "Surlignages, signets et état de lecture dans la Bibliothèque",
            "Changement de langue de l'interface",
        ],
        "review_title": "Checklist de revue",
        "review_note": "Pour App Review : ce seul EPUB couvre l'import, la lecture, l'IA et la navigation.",
        "closing": "Utilisez la table des matières pour passer à d'autres langues.",
    },
    {
        "code": "it",
        "nav": "Italiano",
        "title": "Avvio rapido in Italiano",
        "intro": "Questo libro demo aiuta utenti e revisori a verificare rapidamente le funzioni di LanRead.",
        "steps_title": "Percorso da 3 minuti",
        "steps": [
            "Apri questo libro in Libreria e controlla la navigazione dei capitoli.",
            "Entra nel riepilogo AI e genera un riassunto della prima sezione.",
            "Tocca Inizia lettura, crea un'evidenziazione e un segnalibro.",
            "Prova la modalità Skimming e torna alla posizione precedente.",
        ],
        "features_title": "Mappa funzionalità",
        "features": [
            "Import EPUB e parsing dei metadati",
            "Impostazioni tipografiche e tracciamento avanzamento",
            "Guida di lettura AI, riassunti capitolo e insight chiave",
            "Evidenziazioni, segnalibri e stato lettura in Libreria",
            "Supporto cambio lingua nell'interfaccia app",
        ],
        "review_title": "Checklist revisione",
        "review_note": "Per App Review: questo unico EPUB è sufficiente per testare import, lettura, AI e navigazione.",
        "closing": "Dalla tabella dei contenuti puoi passare alle altre lingue.",
    },
]

STYLE_CSS = """body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  margin: 1.2em;
  line-height: 1.6;
  color: #222;
}
h1 { font-size: 1.7em; margin-bottom: 0.2em; }
h2 {
  margin-top: 1.2em;
  border-left: 4px solid #2f6bff;
  padding-left: 0.5em;
  font-size: 1.15em;
}
ol, ul { padding-left: 1.2em; }
li { margin: 0.35em 0; }
.note {
  margin-top: 1.2em;
  padding: 0.8em;
  border-radius: 10px;
  background: #f3f7ff;
}
"""


def xhtml_doc(lang_code: str, title: str, body: str) -> str:
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="{lang_code}" lang="{lang_code}">
  <head>
    <meta charset="utf-8"/>
    <title>{title}</title>
    <link rel="stylesheet" type="text/css" href="../styles/style.css"/>
  </head>
  <body>
{body}
  </body>
</html>
"""


def chapter_body(section: dict[str, object]) -> str:
    steps = "\n".join(f"    <li>{step}</li>" for step in section["steps"])
    features = "\n".join(f"    <li>{item}</li>" for item in section["features"])
    return f"""    <h1>{section["title"]}</h1>
    <p>{section["intro"]}</p>

    <h2>{section["steps_title"]}</h2>
    <ol>
{steps}
    </ol>

    <h2>{section["features_title"]}</h2>
    <ul>
{features}
    </ul>

    <h2>{section["review_title"]}</h2>
    <p class="note">{section["review_note"]}</p>
    <p>{section["closing"]}</p>
"""


def nav_xhtml() -> str:
    nav_items = "\n".join(
        f'          <li><a href="text/{section["code"]}.xhtml">{section["nav"]} - {section["title"]}</a></li>'
        for section in LANG_SECTIONS
    )
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="en" lang="en">
  <head>
    <meta charset="UTF-8"/>
    <title>Table of Contents</title>
  </head>
  <body>
    <nav epub:type="toc" id="toc">
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
        f"""    <navPoint id="navPoint-{idx}" playOrder="{idx}">
      <navLabel><text>{section["nav"]} - {section["title"]}</text></navLabel>
      <content src="text/{section["code"]}.xhtml"/>
    </navPoint>"""
        for idx, section in enumerate(LANG_SECTIONS, start=1)
    )
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE ncx PUBLIC "-//NISO//DTD ncx 2005-1//EN"
  "http://www.daisy.org/z3986/2005/ncx-2005-1.dtd">
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head>
    <meta name="dtb:uid" content="{BOOK_ID}"/>
    <meta name="dtb:depth" content="1"/>
    <meta name="dtb:totalPageCount" content="0"/>
    <meta name="dtb:maxPageNumber" content="0"/>
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
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="bookid">{BOOK_ID}</dc:identifier>
    <dc:title>{BOOK_TITLE}</dc:title>
    <dc:creator>{BOOK_AUTHOR}</dc:creator>
    <dc:language>en</dc:language>
  </metadata>
  <manifest>
    {manifest}
  </manifest>
  <spine toc="ncx">
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
