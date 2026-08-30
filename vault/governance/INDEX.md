# 制度路由

> Session 開始只讀本頁。L0 常駐；L1–L6 依任務語意按需載入，不逐層預載。

| 層級 | 命中情境 | 最小原則 |
|---|---|---|
| L0 憲法 | 永遠 | 授權、最小改動、證據、安全、驗證、制度邊界 |
| L1 安全 | 秘密、權限、檔案、網路、外部整合、部署、不可逆操作 | 分清 Source／Action；高風險先授權 |
| L2 判斷 | 架構、根因、影響、重大取捨 | 分開事實與假設，以專案證據驗證 |
| L3 流程 | 多步驟、多檔案、跨模組、行為變更 | TaskScopedProposalLoop；測試與雙軸 Review |
| L4 技能 | 工作流、工具、技術棧 | 既有專案決策優先；Skills／packs 按需 |
| L5 經驗 | 歷史決策、重複踩坑 | 摘要只作索引，回讀原始證據 |
| L6 校準 | 準備交付 | read-back、測試或來源驗證；缺口明說 |

## 路由入口

- L0：`../../core/constitution/rules.md`
- L1–L6、外部整合、MCP 與 repository hosting：`operating-model.md`
- 需求驅動開發路由（需求書開發／功能維護／debug 與常見例外）：
  `requirement-driven-routing.md`
- 角色：`../../core/agents/{pm,sa,ux,sd,pg,qa}.md`
- 通用 Skills：`../../core/skills/*/SKILL.md`
- 技術棧 packs：`../../packs/*/SKILL.md`
- 安全審查：`../../core/skills/security-review/SKILL.md`
- 前端選型：`../../core/skills/select-frontend-capability/SKILL.md`
- Skill 引入：`../../docs/adr/0016-targeted-skill-intake.md`、`skill-registry.json`、
  `skill-candidates.md`
- System Feature Wiki 核心邊界：`../../docs/specs/knowledge-workspace-boundary.md`；正式規格與專屬 ADR 位於 `projectD-knowledge`
- Governance Evals：`../../docs/specs/governance-evals-v2.md`、
  `../../docs/specs/governance-evals-v2-phase-3.md`、`../../evals/`
- 跨專案歷程：`../../core/skills/query-project-history/SKILL.md`
- 決策與踩坑：`../../docs/history/`、`../after-action/`

## 載入規則

- 先用上表選一個主要層級，再讀單一必要入口；不要預載全部 agents、Skills 或歷史。
- 使用者用自然語句表達意圖即可；較近的專案規則與當次明確指令仍須符合 L0。
- 新增治理文件必須更新本頁，但入口只放路由與狀態，不複製正文。
- Governance Evals 的 catalog／synthetic/contract 通過不代表真實模型或 live hooks 已通過；
  必須有具 provenance 的 host evidence 才能升級宣稱。
