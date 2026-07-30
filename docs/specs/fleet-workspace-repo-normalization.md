# Fleet Workspace／Repo 雙層正規化計畫

## 狀態

- 建立日期：2026-07-27
- 狀態：部分完成；Phase 1 已完成，Phase 2–5 尚未授權實作
- 已確認決策：work 專案需要跨 repo 協作，因此保留父層 Workspace
- 待確認決策：是否在 Fleet schema 增加 `scope: workspace | repo`

## 目標

將 projectD-core Fleet 正規化為「Workspace＋Repo」雙層模型：

- Workspace 負責跨 repo 分析、規劃、整合與共用 packs。
- Repo 負責單一 Git repository 的實作、精確 packs 與本地規則。
- 合法的父子項目可以同時存在，不視為重複。
- 不刪除或重新 init 既有 `AGENTS.md`、`CLAUDE.md`、`GEMINI.md`；
  只維護 projectD-core 擁有的 managed block。

## 現況

本機 `fleet/fleet.json` 目前有 21 筆：

- 9 個 work Workspace。
- 10 個已納管的下層 Repo。
- 2 個 side Repo（projectD-knowledge、Tools）。

既有 21 筆已通過：

```text
[PASS] Fleet governance: 21 project(s), 84 managed file(s), 0 changed.
```

先前盤點另發現 23 個尚未納管的下層 Git repo。若全部確認啟用，最終 Fleet
會有 44 筆。

### 已納管 Workspace

- `D:\workspaces\CTCB`
- `D:\workspaces\FEIB`
- `D:\workspaces\HN`
- `D:\workspaces\KGIB`
- `D:\workspaces\LBIB`
- `D:\workspaces\TACB`
- `D:\workspaces\TBB`
- `D:\workspaces\TCB`
- `D:\workspaces\TS`

### 已納管 Repo／Side Project

- `D:\workspaces\KGIB\KGIB_MI`
- `D:\workspaces\KGIB\KGIB_MI_Trade`
- `D:\workspaces\KGIB\KGIB_MI_Web`
- `D:\workspaces\KGIB\KGIB_PlatformDll`
- `D:\workspaces\LBIB\lbib_PlatformDll_New`
- `D:\workspaces\LBIB\lbib_Trade_New`
- `D:\workspaces\LBIB\lbib_Web`
- `D:\workspaces\TCB\TCB_PlatformDll`
- `D:\workspaces\TCB\TCB_Trade`
- `D:\workspaces\TCB\TCB_Web`
- `D:\workspaces\projectD-knowledge`（side）
- `D:\workspaces\Tools`（side）

## 候選 Repo 清單

### CTCB

- `D:\workspaces\CTCB\BATCH`
- `D:\workspaces\CTCB\microfront_trade`
- `D:\workspaces\CTCB\microservice`
- `D:\workspaces\CTCB\New_CTCB_PlatformDll`
- `D:\workspaces\CTCB\New_CTCB_Trade`
- `D:\workspaces\CTCB\New_CTCB_Web`

### FEIB

- `D:\workspaces\FEIB\FEIB_Evo`
- `D:\workspaces\FEIB\FEIB_MI`
- `D:\workspaces\FEIB\FEIB_PlatformDll`
- `D:\workspaces\FEIB\FEIB_Trade`

### HN

- `D:\workspaces\HN\HN_MI`
- `D:\workspaces\HN\HN_MI_Trade`
- `D:\workspaces\HN\HN_MI_Web`
- `D:\workspaces\HN\HN_PlatformDll`

### TACB

- `D:\workspaces\TACB\TACB_MI`
- `D:\workspaces\TACB\TACB_MI_Trade`
- `D:\workspaces\TACB\TACB_PlatformDll`

### TBB

- `D:\workspaces\TBB\TBB_MI`
- `D:\workspaces\TBB\TBB_PlatformDll`
- `D:\workspaces\TBB\TBB_Trade`
- `D:\workspaces\TBB\TBB_Web`

### TS

- `D:\workspaces\TS\ts_MI`
- `D:\workspaces\TS\ts_MI_Web`

## 實作階段

### Phase 1 — 修正 projectD quality gate（已完成）

已由 commit `e28a974` 修正 `projectd-check.ps1` 的 `Child` 包裝：native child
process 的非零 exit code 會讓對應 check 失敗，不再發生子檢查輸出錯誤、JSON 卻仍
回報 `passed: true` 且主程序 exit code 為 0 的假綠燈。

完成項目：

- 子程序非零 exit code 必須讓對應 check 失敗。
- `-Json` 的 `passed`、各 check 狀態與主程序 exit code 必須一致。
- 保留可診斷的子程序錯誤摘要。
- 增加 contract test，覆蓋成功與失敗兩條路徑。

### Phase 2 — 明確化 Workspace／Repo 模型

待確認是否在 Fleet 項目增加：

```json
{
  "scope": "workspace"
}
```

或：

```json
{
  "scope": "repo"
}
```

若採用 `scope`：

- work 父層使用 `workspace`。
- 下層 Git repo 與 Tools 使用 `repo`。
- 相同 path 禁止重複。
- 只有 `workspace` 包含 `repo` 屬合法父子關係。
- Repo packs 原則上應包含於父 Workspace packs；不符合時必須以實際技術棧證據說明。
- 更新 `fleet.json.example`、`fleet/README.md`、catalog validation 與 contract tests。

### Phase 3 — 盤點候選 Repo

每個候選需確認：

- 是否仍在使用；封存或停用 repo 不納入。
- 是否為真正 Git root。
- 是否已有本地 agent Markdown。
- 是否存在尚未提交的變更。
- 從 `.sln`、`.csproj`、`package.json`、框架設定等專案證據判定 packs，
  不直接照抄父 Workspace。

盤點只讀，不修改候選 repo。

### Phase 4 — 分批導入

建議順序：

1. TBB、TACB
2. FEIB、HN
3. CTCB
4. TS

每批執行：

1. `fleet-governance.ps1 -Mode Check`，確認預期缺口。
2. `fleet-governance.ps1 -Mode Apply`。
3. 重新執行 Check，必須為 0 漂移。
4. 確認每個入口檔只有一組 `PROJECTD_CORE_START/END`。
5. 比對原文、BOM、換行與 Git diff，確保沒有刪除專案規則。

### Phase 5 — Git 交付

- 先完成並推送 projectD-core 的工具、測試與文件變更。
- `fleet/fleet.json` 含本機路徑，維持不進 Git。
- 各專案只 stage 三個治理入口 MD，以及有變更時的 `.gitignore`；
  不混入既有功能變更。
- 每個 repo 分開 commit。
- push 前另行確認精確遠端與目標分支；不得把治理 commit 靜默混入功能分支。

## 驗收條件

- [x] Quality gate 子檢查失敗時不再假綠燈。
- [ ] Workspace／Repo schema 決策已確認並反映於文件與測試。
- [ ] 23 個候選均完成 active／inactive 與 packs 判定。
- [ ] 所有 active repo 都納入 Fleet。
- [ ] 合法父子關係可通過；重複 path、無效 packs 與 malformed block 會失敗。
- [ ] 每個納管項目三個入口檔各有且只有一個 managed block，且 `.gitignore`
      有一個 root-only agent-entry managed block。
- [ ] 原有專案規則、編碼與無關工作目錄變更均保留。
- [x] `projectd-check.ps1 -Json` 的 JSON、訊息與 exit code 一致且通過。
- [ ] projectD-core 與各專案 commit 保持分離。

## 不在本次範圍

- 刪除專案或 Git repository。
- 刪除既有專案治理規則。
- 將本機 `fleet.json` 納入版本控制。
- 未確認目標分支前自動 commit 或 push 各工作專案。
