# 制度路由

> Session 開始只讀本頁摘要。L0 常駐；L1–L6 依任務語意按需載入，不要求每個任務
> 逐層跑完。

## 常駐摘要

| 層級 | 何時關注 | 核心原則 |
|---|---|---|
| L0 憲法 | 永遠 | 授權、最小改動、證據、安全、驗證與制度邊界 |
| L1 安全 | 秘密、權限、DB、檔案、網路、外部整合、部署、不可逆操作 | 外部操作逐次分為 Source／Action；先確認邊界與影響，高風險依 L0 取得授權 |
| L2 判斷 | 架構、根因、影響範圍、重大方案取捨 | 區分事實／假設，以專案證據驗證 |
| L3 流程 | 需要工具操作或產生產物、多步驟、多檔案、跨模組或行為變更 | 使用 TaskScopedProposalLoop；依規模選擇角色，軟體變更可行時採 Spec、Red → Green → Refactor 與雙軸 Review |
| L4 技能 | 通用工作流、能力選型、外部工具與技術棧規範 | 先辨識能力與技術棧；專案決策／既有慣例優先，候選不升格為唯一標準 |
| L5 經驗 | 歷史決策、既有調查、重複踩坑 | 重要理由留痕、證據分級；memory 是索引，回讀原文 |
| L6 校準 | 準備宣告完成或交付 | 用 read-back、測試或來源證據驗證，缺口明說 |

## 路由

- L0 規則：`../../core/constitution/rules.md`
- L1–L6 詳細判準：`operating-model.md`
- 外部整合：依 `operating-model.md` 的「外部整合的 Source／Action 邊界」逐操作分類；
  Source 不擴張讀取範圍，Source 權限也不自動授權後續 Action。
- 安全相關設計或程式變更：依 L1 確認信任邊界，再使用
  `../../core/skills/security-review/SKILL.md` 做有界、唯讀且以證據為基礎的安全審查。
- Repository hosting：所有 `projectD-*` repository 一律使用 Git／GitHub，不走 F25B
  TFS；其他專案在 push／PR 前先依 remote 證據路由。詳細邊界見 `operating-model.md`
  的「Repository hosting boundary」。
- 角色分工：`../../core/agents/{pm,sa,sd,pg}.md`
- 通用 Skill：`../../core/skills/*/SKILL.md`
- 技術棧 Skill：`../../packs/*/SKILL.md`（SSRS RDL 報表見 `../../packs/rdl-report/SKILL.md`）
- 前端能力選型：`../../core/skills/select-frontend-capability/SKILL.md`，再依目前 workspace
  路由至 `../../packs/frontend-react/references/react-capabilities.md` 與 `../../packs/frontend-angular/references/angular-capabilities.md`
- 可重複踩坑：`../after-action/`
- 跨專案歷程查詢：`../../core/skills/query-project-history/SKILL.md`；候選未經人工確認不得視為歷程事實。
- System Feature Wiki：`../../docs/specs/external-knowledge-wiki.md`；相關架構決策見 `../../docs/adr/` 中的 ADR 0004–0014；原始推導脈絡見歷史文件 `plan-external-llm-wiki.md`。
- AI-agent MCP server 執行安全邊界（例如 DevSpace 等具 shell/write 能力的工具）：
  `operating-model.md` 的「AI-agent MCP server 執行邊界」（L1 安全層），決策見
  `../../docs/adr/0015-isolate-ai-agent-mcp-server-execution.md`
- Skill 引入機制：`../../docs/adr/0001-targeted-skill-intake.md`；執行入口見
  `../../core/skills/{skill-scout,skill-update-check}/SKILL.md`，機器狀態見 `skill-registry.json`；
  原始 PM/SA/SD 決策脈絡見歷史文件 `plan-skill-import.md`／`prd-skill-import.md`／
  `sa-analysis-skill-import.md`。
- Governance Evals v2：Phase 1／2 已完成；Phase 3 的 Codex／Claude adapter contracts、
  durable operation-log schema／pure reducer／manual-drive crash contract、repo-local synchronous
  PreToolUse／PostToolUse hook seam、Claude paired-pilot run-plan integrity 與 paired upgrade gate
  已完成；真實 runner／observers、授權 pilots／paired evidence、Copilot 與 cross-host matrix 尚待後續；
  Phase 4 尚未開始。主規格見
  `../../docs/specs/governance-evals-v2.md`，研究依據見
  `../../docs/research/ai-governance-gap-analysis-2026-08-21.md`，採用證據見
  `../../docs/history/2026-08-21-governance-evals-v2-phase-1.md` 與
  `../../docs/history/2026-08-21-governance-evals-v2-phase-2.md`，Phase 3 規格與歷程見
  `../../docs/specs/governance-evals-v2-phase-3.md` 與
  `../../docs/history/2026-08-22-governance-evals-v2-phase-3-codex-first.md`、
  `../../docs/history/2026-08-22-governance-evals-v2-phase-3-claude-adapter.md`。Canonical behavior cases、
  security traces、asset inventory 與 schemas 位於 `../../evals/`。Catalog／synthetic trace
  validation 不代表真實模型已通過，必須取得具 provenance 的結構化 host trial trace 後才能
  評估實際 agent behavior。

## 載入原則

- 先用本頁判斷命中層級，再讀單一必要文件；不要在 session 開始載入全部 agents 與 Skills。
- 使用者以自然語句表達意圖即可，不要求精準說出層級、角色或 pack 名稱。
- 新增治理文件時必須更新本頁；入口檔只保留路由，不複製治理正文。
