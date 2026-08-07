# 制度路由

> Session 開始只讀本頁摘要。L0 常駐；L1–L6 依任務語意按需載入，不要求每個任務
> 逐層跑完。

## 常駐摘要

| 層級 | 何時關注 | 核心原則 |
|---|---|---|
| L0 憲法 | 永遠 | 授權、最小改動、證據、安全、驗證與制度邊界 |
| L1 安全 | 秘密、權限、DB、檔案、網路、部署、不可逆操作 | 先確認邊界與影響，高風險依 L0 取得授權 |
| L2 判斷 | 架構、根因、影響範圍、重大方案取捨 | 區分事實／假設，以專案證據驗證 |
| L3 流程 | 多步驟、多檔案、跨模組或行為變更 | 依規模選擇角色；可行時採 Red → Green → Refactor |
| L4 技能 | 通用工作流、能力選型、外部工具與技術棧規範 | 先辨識能力與技術棧；專案決策／既有慣例優先，候選不升格為唯一標準 |
| L5 經驗 | 歷史決策、既有調查、重複踩坑 | 重要理由留痕、證據分級；memory 是索引，回讀原文 |
| L6 校準 | 準備宣告完成或交付 | 用 read-back、測試或來源證據驗證，缺口明說 |

## 路由

- L0 規則：`../../core/constitution/rules.md`
- L1–L6 詳細判準：`operating-model.md`
- 角色分工：`../../core/agents/{pm,sa,sd,pg}.md`
- 通用 Skill：`../../core/skills/*/SKILL.md`
- 技術棧 Skill：`../../packs/*/SKILL.md`（含 F25B/ESOAF 家族 SSRS RDL 報表：`../../packs/rdl-report/SKILL.md`，
  2026-07-30 由 oai-core `shared-skills/rdl-report` 遷入）
- 前端能力選型：`../../core/skills/select-frontend-capability/SKILL.md`，再依目前 workspace
  路由至 `../../packs/frontend-react/references/react-capabilities.md` 與 `../../packs/frontend-angular/references/angular-capabilities.md`
- 可重複踩坑：`../after-action/`
- 跨專案歷程查詢 PoC：`../../core/skills/query-project-history/SKILL.md`；
  候選與基準集位於 `project-history-poc/`，候選未經人工確認不得視為歷程事實。
- System Feature Wiki（規格已核准、Phase 0 進行中）：`../../docs/specs/external-knowledge-wiki.md`；
  獨立 private KnowledgeWorkspace（`D:\workspaces\projectD-knowledge`）以能力導向
  FeaturePages 提供唯讀開發影響分析。第一階段納入 `intentype`（8 個 Initial
  FeaturePages）、`lbib`（跨 `lbib_Web`／`lbib_Trade_New`／`lbib_PlatformDll_New`
  三個 repository；Initial FeaturePages 尚未選定）及 `tbb`（先以 `TBB_Web`／
  `TBB_Trade` 的 TA23001 作為 tracer bullet）三個 source system。架構理由見
  `../../docs/adr/0004-*.md` 至 `0009-*.md`、`0013-expand-knowledge-workspace-to-lbib.md`、
  `0014-expand-knowledge-workspace-to-tbb.md`；
  `plan-external-llm-wiki.md` 僅保留為歷史研究，不是實作權威。
- Skill 引入機制（GitHub 定向搜尋、指定 registry 安裝與受治理收錄）：`../../docs/adr/0001-targeted-skill-intake.md`
  （現行架構）、`prd-skill-import.md`（歷史 PRD）、
  `sa-analysis-skill-import.md`（技術分析）、`skill-candidates.md`（決策紀錄）、
  `skill-registry.json`（機器狀態）、`../../core/skills/skill-scout/SKILL.md`
  （跨 Agent 定向搜尋）、`../../core/skills/skill-update-check/SKILL.md`
  （upstream 更新檢查）、`../../core/commands/skill-scout.md`（Claude 薄入口）、
  `../../packs/_staging/README.md`（staging 說明）

## 載入原則

- 先用本頁判斷命中層級，再讀單一必要文件；不要在 session 開始載入全部 agents 與 Skills。
- 使用者以自然語句表達意圖即可，不要求精準說出層級、角色或 pack 名稱。
- 新增治理文件時必須更新本頁；入口檔只保留路由，不複製治理正文。
