# projectD 治理接線與驗證手冊

本頁保存安裝、Fleet、治理檢查與 Phase 3 離線工具的操作細節。Repository 首頁只保留
導覽與最常用命令。

## 全域接線

```powershell
# 套用或更新 desired state
pwsh -File scripts/setup.ps1

# 唯讀檢查
pwsh -File scripts/setup.ps1 -Mode Check

# 移除 owned resources；先做唯讀 preflight
pwsh -File scripts/uninstall.ps1 -Mode Check
pwsh -File scripts/uninstall.ps1
```

全域接線包含：

- `PROJECTD_CORE` 環境變數；
- Claude agents 與相容 commands；
- `core/skills/*` 到 `~/.claude/skills/` 與 `~/.agents/skills/` 的 junction；
- Claude/Codex 全域入口中的 projectD managed block。

技術棧 `packs/*` 不進全域 Skill catalog。`setup.ps1` 會依 ownership state 清除舊版建立的
全域 pack junction；不屬於 projectD 的檔案或 junction 會視為 conflict，不會覆寫。

## Fleet 專案接線

`fleet/fleet.json` 為每個專案指定 `path`、`category` 與 `packs`。執行：

```powershell
pwsh -File scripts/fleet-governance.ps1 -Mode Check
pwsh -File scripts/fleet-governance.ps1 -Mode Apply
```

Fleet 會管理專案根目錄的 `AGENTS.md`、`CLAUDE.md`、`GEMINI.md` 區塊，並只將指定 packs
接到該專案的 `.agents/skills/` 與 `.claude/skills/`。Managed junction 會以精確路徑加入
該專案 `.gitignore`，不會忽略其他 project-owned Skills。

## Unified projectD check

```powershell
pwsh -File scripts/projectd-check.ps1
pwsh -File scripts/projectd-check.ps1 -Json
pwsh -File scripts/projectd-check.ps1 -GovernanceEvals
```

一般檢查包含 Skill catalog/registry、session-init 與 Skill discovery budgets、staging lifecycle、
CI 去重、Fleet catalog、文字掃描與 wiring。`-GovernanceEvals` 再執行：

1. structural eval；
2. behavior catalog；
3. asset inventory；
4. security trace replay；
5. Claude paired-pilot run-plan contract；
6. Codex／Claude host hook contract；
7. host trial contract；
8. paired upgrade gate；
9. durable operation-log contract。

所有檢查均為 deterministic/offline；contract 通過不代表真實模型、live hook 或完整 host
coverage 已驗證。詳細限制見 [`governance-evals-v2-phase-3.md`](../specs/governance-evals-v2-phase-3.md)。

## Repository-local pre-push hook

```powershell
pwsh -File scripts/governance-hooks.ps1 -Mode Install
pwsh -File scripts/governance-hooks.ps1 -Mode Check
pwsh -File scripts/governance-hooks.ps1 -Mode Uninstall
```

Hook 只提供本機提早回饋，不取代 CI、branch protection、L0 授權或人工 review。

## Host evidence tools

這些入口只處理已授權、metadata-only、位於 repository 內的 evidence；不啟動模型，也不讀取
prompt、reasoning 或 credential。

```powershell
# 驗證 operation log 與 recovery composite gate
pwsh -File scripts/governance-operation-log-eval.ps1 `
  -OperationLogPath .local/governance/operation-log.json `
  -HostManifestPath .local/governance/host-trial.json `
  -CurrentSafeEffectKinds checkpoint-write,smoke-test,final-state-observation `
  -VerifyCurrentWorkspace

# 驗證 Claude paired-pilot 計畫；不執行 live trial
pwsh -File scripts/claude-governance-run-plan.ps1 `
  -PlanPath .local/governance/claude-paired-pilot.json

# 比較兩份已驗證 host trial evidence
pwsh -File scripts/governance-host-upgrade-gate.ps1 `
  -BaselineManifestPath .local/governance/baseline.json `
  -CandidateManifestPath .local/governance/candidate.json
```

Codex／Claude manual-import 參數、schema 與 evidence 語意以
[`governance-evals-v2-phase-3.md`](../specs/governance-evals-v2-phase-3.md) 為準。

## 可選本機專案歷程

```powershell
pwsh -File scripts/setup-project-history.ps1
```

此 runtime 不由一般 setup 安裝。模型、allowlist 與 index 都在 `.local/project-history/`；
完整移機與受限網路說明見
[`portable-setup.md`](../../core/skills/query-project-history/references/portable-setup.md)。
