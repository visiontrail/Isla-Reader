## Prompt Strategy (English)

- Scope: Covers book summary flow and skimming mode prompt construction.
- Sources: Chapters prefer EPUB TOC assembly; fallback to stored `Book.metadata` JSON.
- Skimming prompt role: LanRead inspectional reading coach (Adler skimming mindset), includes book title, chapter title/order, reading goal.
- Knowledge-first strategy: Run a YES/NO chapter knowledge probe first. If the model knows the chapter, generate directly from prior knowledge.
- Unknown fallback: If probe returns NO (or unrecognized), include the full assembled chapter content.
- Token compression and cleanup: Chapter content is locally cleaned before sending (whitespace compression, blank-line collapse, page number/header/footer/noise-line removal).
- TOC-aware assembly: Top-level TOC nodes include all descendant chapters up to the next same-level entry to avoid empty parent chapters.
- Output contract: Model must return JSON with `chapterTitle`, `readingGoal`, 3–5 `structure` items, 3 `keySentences`, 5 `keywords`, 2–3 `inspectionQuestions`, `aiNarrative` (<220 words), and `estimatedMinutes` (2–6).
- Language: Prompt language switches by the resolved app language from `AppSettings.shared.language` (`Follow System` respects the active bundle localization; supported outputs: English, Simplified Chinese, Japanese, Korean).
- Caching: Skimming summaries cached per book + chapter order + resolved language key.
- AISummary: Whole-book summaries parse chapters from `Book.metadata`; chapter mappings can be extended similarly.

## 提示词策略（中文）

- 范围：涵盖全书摘要流程与略读模式提示词构建。
- 数据来源：优先使用 EPUB 目录重组章节，若失败则回退到 `Book.metadata` 中的章节 JSON。
- 略读角色：以“检视阅读教练”身份（Adler 略读心智模型），注入书名、章节名/序号和阅读目标。
- 知识优先策略：先执行章节级 YES/NO 知识探测；若模型已知该章节，直接基于已有知识生成结果。
- 未知回退：若探测返回 NO（或无法识别），再注入完整拼接后的章节内容。
- Token 压缩与清洗：发送前对章节内容做本地清洗（压缩空白、折叠空行、移除页码/页眉页脚/噪声行）。
- 目录感知：一级目录节点包含直到下一个同级前的所有子章节，避免父级节点内容为空。
- 输出契约：要求模型返回 JSON，包含 `chapterTitle`、`readingGoal`、3–5 条 `structure`、3 条 `keySentences`、5 个 `keywords`、2–3 个 `inspectionQuestions`、`aiNarrative`（<220 词）、`estimatedMinutes`（2–6）。
- 语言：提示语言随 `AppSettings.shared.language` 的实际生效语言切换；`跟随系统` 会跟随 App 当前命中的本地化（支持英文、简体中文、日语、韩语）。
- 缓存：按书籍 + 章节序号 + 生效语言缓存略读摘要结果。
- 全书摘要：AISummary 从 `Book.metadata` 解析章节生成全书摘要；章节映射可按同样方式扩展。
