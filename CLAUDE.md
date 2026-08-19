# projectD-core — Session 啟動協議

每次 session 開始時，依序讀取：

1. `core/constitution/rules.md` — L0 規則
2. `vault/README.md` → 依其 init 序列讀取 identity/memory/governance
3. 依 `vault/governance/INDEX.md` 的 L1–L6 摘要做語意路由；只在命中時讀取
   `vault/governance/operating-model.md` 的相關規則
4. 需要技術棧規範時，才讀取對應的 `packs/*/SKILL.md`
   （C# → `packs/csharp`；通用瀏覽器 → `packs/frontend-core`；React → `packs/frontend-react`；Angular → `packs/frontend-angular`；TypeScript/Node → `packs/typescript、node-runtime`；
   Python → `packs/python`）

## 外部工具參考（core/skills/）

- `core/skills/codegraph.md` — 若專案根目錄有 `.codegraph/`，理解/定位程式碼優先用它
- `core/skills/grilling.md` — 動手前想壓力測試計畫/決策時使用 `/grill-me`

這些是外部工具/技能庫的參考文件，不是自己重寫的內容；是否已安裝以實際環境為準。

## 角色 Agent

六個角色是按任務需要選用的能力，不是每次都要跑完的固定流水線：

- `pm` — 需求釐清、PRD、範圍界定
- `sa` — 技術分析、決定要用哪些 packs，並判斷是否需要 UX 或 SD
- `ux` — 使用者互動流程、介面狀態、易用性取捨
- `sd` — 架構/資料模型/介面設計
- `pg` — 實作、審查、測試，並判斷是否需要 QA 做獨立驗證
- `qa` — 獨立於實作者的測試涵蓋率與驗收驗證

需求明確的低風險小任務可直接由主 agent 或 PG 處理。只有角色選擇會實質影響成果且
無法從需求判定時，才詢問使用者。
