## Prompt Strategy (English)

- Scope: Covers book summary flow and skimming mode prompt construction.
- Sources: Chapters prefer EPUB TOC assembly; fallback to stored `Book.metadata` JSON.
- Skimming prompt role: IslaBooks inspectional reading coach (Adler skimming mindset), includes book title, chapter title/order, reading goal.
- Content inclusion: Full assembled chapter content is embedded (previous 4,000-character clamp removed).
- TOC-aware assembly: Top-level TOC nodes include all descendant chapters up to the next same-level entry to avoid empty parent chapters.
- Output contract: Model must return JSON with `chapterTitle`, `readingGoal`, 3–5 `structure` items, 3 `keySentences`, 5 `keywords`, 2–3 `inspectionQuestions`, `aiNarrative` (<220 words), and `estimatedMinutes` (2–6).
- Language: Prompt language switches by `AppSettings.shared.language` (English or Simplified Chinese).
- Caching: Skimming summaries cached per book + chapter order key.
- AISummary: Whole-book summaries parse chapters from `Book.metadata`; chapter mappings can be extended similarly.

## 提示词策略（中文）

- 范围：涵盖全书摘要流程与略读模式提示词构建。
- 数据来源：优先使用 EPUB 目录重组章节，若失败则回退到 `Book.metadata` 中的章节 JSON。
- 略读角色：以“检视阅读教练”身份（Adler 略读心智模型），注入书名、章节名/序号和阅读目标。
- 内容注入：嵌入完整拼接后的章节内容（已移除 4000 字符截断）。
- 目录感知：一级目录节点包含直到下一个同级前的所有子章节，避免父级节点内容为空。
- 输出契约：要求模型返回 JSON，包含 `chapterTitle`、`readingGoal`、3–5 条 `structure`、3 条 `keySentences`、5 个 `keywords`、2–3 个 `inspectionQuestions`、`aiNarrative`（<220 词）、`estimatedMinutes`（2–6）。
- 语言：提示语言随 `AppSettings.shared.language` 切换英文或简体中文。
- 缓存：按书籍 + 章节序号缓存略读摘要结果。
- 全书摘要：AISummary 从 `Book.metadata` 解析章节生成全书摘要；章节映射可按同样方式扩展。
