---
type: memory-summary
readAt: session-start
lastUpdated: 2026-11-09
---

# projectD-core 工作記憶

本頁只保存跨 session 仍會影響決策的短索引；完整推導與時間線在
`docs/adr/`、`vault/governance/` 與 Git history，命中任務時才回讀。

## 穩定事實

- projectD-core 是個人擁有、provider-neutral 的 AI 治理核心；L0 永遠優先。
- Canonical Skills 只在 `core/skills/` 與 `packs/` 維護；外部候選必須經來源、授權、
  digest、staging 與人工採納流程。
- 通用 core Skills 可全域發現；技術棧 packs 只由 Fleet 接到匹配專案，不進全域 catalog。
- projectD repositories 使用 Git/GitHub；F25B 專案才依證據路由 TFS。
- 跨專案知識內容屬於獨立 `projectD-knowledge`；core 只保留 portable contract、adapter
  與治理決策。

## 現行決策

- 執行採 TaskScopedProposalLoop：Understand → Propose → Authorize → Execute → Verify →
  Report → Learn；不包含背景監控或未授權擴張。
- memory 只作索引，不以摘要取代原始證據。
- Runtime v2：host permission 不等於 task authorization；read 為 advisory，
  effectful／unclassified 無 envelope 時 pre-effect deny。

## 瘦身護欄

- `scripts/projectd-check.ps1` 強制：session init ≤ 10 KiB、Skill discovery ≤ 6,000
  字、`_staging` 只留審查中候選、CI 不重跑重型 contracts。
- 刪除個別 Skill 前需有使用或品質證據；先合併可證明的薄 wrapper。

## 回讀入口

- 所有 specs、ADR、Skill registry 與踩坑紀錄的入口都在 `vault/governance/INDEX.md`；
  實作歷程看 Git history。
