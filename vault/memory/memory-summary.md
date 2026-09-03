---
type: memory-summary
readAt: session-start
lastUpdated: 2026-09-03
---

# projectD-core 工作記憶

本頁只保存跨 session 仍會影響決策的短索引；完整推導與時間線在
`docs/history/`、`docs/adr/`、`vault/governance/` 與 Git history，命中任務時才回讀。

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
- Governance Evals Phase 1–2 已完成；Phase 3 只有 deterministic contracts、manual-import
  adapters、operation log、hooks 與 upgrade/run-plan gate。Live runner、observers、pilot、
  paired evidence、Copilot/cross-host matrix 尚未完成，不得宣稱已 live interception。
- Runtime Governance v2：host permission 不等於 task authorization；read 為 advisory，effectful／unclassified 無 envelope 時 pre-effect deny，issuance 要真人互動確認。2026-09-03 Codex CLI 0.152.1（gpt-5.6-luna／medium）已驗證 current-policy bootstrap、workspace allow、shell deny；其他模型／工具、Claude、recovery、observer／cross-host 未驗證。Pi runtime 仍是 optional experiment。

## 瘦身護欄

- Session init 總量上限 10 KiB；本頁只留活躍決策與回讀路徑。
- 全域 Skill discovery metadata 上限 6,000 characters；description 要短且保留觸發語意。
- `_staging` 只保存仍在審查或暫留的候選；adopted/rejected 工作副本必須清出。
- CI 不得同時個別與 aggregate 重跑同一批重型 governance contracts。
- 刪除個別 Skill 前需有使用或品質證據；先合併可證明的薄 wrapper。

## 回讀入口

- 制度與路由：`vault/governance/INDEX.md`
- Skill 來源與生命週期：`vault/governance/skill-registry.json`、
  `vault/governance/skill-candidates.md`
- Governance Evals：`docs/specs/governance-evals-v2.md`、
  `docs/specs/governance-evals-v2-phase-3.md`
- 決策與實作歷程：`docs/history/`、`docs/adr/`
- 可重複踩坑：`vault/after-action/`

