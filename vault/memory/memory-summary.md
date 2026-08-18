---
lastUpdated: 2026-08-19
---

# 記憶快照

<!-- 每次重要決策後更新。格式：日期 + 決策 + 為什麼。 -->

## 2026-07-24

- 從零建立 projectD-core，作為個人獨立擁有、精簡且可按需演進的 AI 治理核心。
- 採用自主設計的 core + packs 架構。
- 所有自建 Skill 採開放的 `<name>/SKILL.md` 格式，canonical 內容只在 projectD-core 維護：
  `core/skills/` 放跨技術棧能力、`packs/` 放技術棧規範；`setup.ps1` 只以 junction 接到
  `~/.claude/skills/` 與 Codex/Copilot 共用的 `~/.agents/skills/`，不為不同 AI 維護副本。
- 角色 agent：PM/SA/SD/PG 四個獨立具名 agent。
- 初始 pack：csharp、frontend-core、frontend-react、frontend-angular、typescript / node-runtime、python（骨架，內容待實際使用累積）。
- 建立輕量 L1–L6 運作模型：L0 常駐、其他層按語意載入；四角色依任務規模選用，
  不強制完整流水線，也不引入固定思維框架、自動 recap 或跨專案固定覆蓋率。
- Fleet 專案以 `AGENTS.md`／`CLAUDE.md`／`GEMINI.md` 受管區塊連回單一 core，
  並用 `scripts/fleet-governance.ps1` 的 Apply／Check 模式防止入口漂移或靜默失聯。

## 2026-07-26

- 為避免外部 Skill 或單一套件清單造成跨專案生態綁定，採用「共用決策原則 → 能力需求 →
  技術棧 adapter → 專案決策」四層模型。L0 只保留技術生態中立底線；具體路由放在 L4。
  新增 `select-frontend-capability`，React／Angular 候選留在各自 adapter，且只能作為附帶
  適用條件的候選。專案既有決策與可維護依賴優先，只有需求、維護、安全、授權、相容性、
  成本或使用者要求發生變化時才重新選型。
- 從 `emilkowalski/skills` 部分收錄並改寫 `apple-design`、`animation-vocabulary`、
  `design-engineering`、`find-animation-opportunities`、`improve-animations` 與
  `review-animations`。修正來源中的絕對動效規則、spring／效能保證、跨框架與寫入授權問題；
  原版 `pick-ui-library` 不建立 active Skill，只把附帶條件的候選整合至 React adapter。

## 2026-07-27

- 為避免 Git 只留下「改了什麼」而遺失「為什麼」，建立重要決策／可重複教訓的最小留痕
  閉環：L0 要求重要理由可追溯且禁止事後捏造；L5 定義觸發條件與
  `verified`／`user-confirmed`／`inferred`／`unknown` 證據分級；L6 在任務結束時由 AI
  提出候選，使用者只需選擇保留、暫留或排除。一般修改不產生流水帳，完整對話不保存。

## 2026-07-28

- 外部 Skill 引入改為定向、受治理流程：`skill-scout` 只接受功能需求或明確 GitHub
  Skill 來源，最多三組查詢與三個合格候選，不自動擴大範圍、執行外部程式、寫 staging
  或收錄。Claude `/skill-scout` 只作薄入口；Claude、Codex、Copilot 共用 canonical Skill。
- Skill 管理採 `SkillSource`（repository）與 `SkillCandidate`（單一路徑）兩層模型；
  `skill-registry.json` 保存機器狀態，`skill-candidates.md` 保存人工理由。候選 ID 包含
  repository 與完整 Skill 路徑，staging 分離 immutable `upstream/` 與 `adapted/`。
- CanonicalSkill 的正式落點依適用範圍決定：跨技術棧放 `core/skills/`，特定技術棧放
  `packs/`；來源是否外部不再決定落點。upstream 更新由獨立 `skill-update-check` 唯讀
  比對路徑 digest，任何採用或升級仍需使用者確認。
- System Feature Wiki 第一階段收斂為 `intentype` 開發影響分析 PoC：八個 FeaturePages
  以使用者可觀察能力切頁，內容放在獨立 private `projectD-knowledge`；來源 repo 仍是
  最終權威。KnowledgeWorkspace 擁有具體 schema、validator、fixtures 與 CI，
  projectD-core 只保留 portable allowlist、生命周期／安全底線與 fail-closed adapter。
- KnowledgePromotion 只透過 GitHub PR；`reviewed` 是事件而非頁面狀態。PoC 使用
  deterministic lexical index、lint drift 與 query RuntimeStale 防呆，延後自動 ingest、
  外部技術知識、hybrid search 與正式 training view。

## 2026-07-30

- TBB／LBIB「新增交易代碼」Skill 依實際程式碼的 parameterized SQL 慣例撰寫；舊資料庫標準文件與程式碼不符，不作為權威來源。
- `rdl-report` 已成為 projectD-core 的 canonical pack，並吸收 LBIB 參數、資料集與版面線索；重疊的 `ssrs-rdl` 副本與失效 junction 已移除。
- oai-core 的重疊 `bug-fix` 與 `code-review` 已移除，避免功能重疊與 junction 覆寫風險；其餘無對應且尚無淘汰證據的 Skills 繼續保留。

## 2026-08-18

- 採用 TaskScopedProposalLoop 作為實際執行與產物任務的外層治理流程：
  `Understand → Propose → Authorize → Execute → Verify → Report → Learn`。
  此流程只處理使用者提出或既有授權範圍內發現的工作，不包含背景監控、未授權跨工具觀察或自行擴張範圍。
- 只有具實質影響的發現形成 MaterialProposal；既有範圍內必要、低風險且可回復的操作沿用原授權。未接受提案只回報、不自動持久化；軟體工程的 Spec、Tracer-bullet TDD 與雙軸 Review 分別組合於 Execute／Verify。
