---
lastUpdated: 2026-07-26
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
- 初始 pack：csharp、frontend-react-angular、python（骨架，內容待實際使用累積）。
- 建立輕量 L1–L6 運作模型：L0 常駐、其他層按語意載入；四角色依任務規模選用，
  不強制完整流水線，也不引入固定思維框架、自動 recap 或跨專案固定覆蓋率。
- 開發流程以 TDD 精神為優先：有既有測試基礎設施的行為變更／bug 修復採
  Red → Green → Refactor；無測試框架時改做最小回歸驗證，不擅自加依賴。
- Fleet 專案以 `AGENTS.md`／`CLAUDE.md`／`GEMINI.md` 受管區塊連回單一 core，
  並用 `scripts/fleet-governance.ps1` 的 Apply／Check 模式防止入口漂移或靜默失聯。
- 軟體變更使用 `grill-me`／`grilling` 完成共識並確認執行後，預設銜接精簡工程流程：
  spec → tracer-bullet TDD → typecheck/build → Standards/Spec 雙軸 review → commit。
  此流程是下位、可組合的工作流；projectD-core L0、較近專案規則與使用者當次明確指令
  永遠優先，且非程式議題不強制套用開發流程。

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
