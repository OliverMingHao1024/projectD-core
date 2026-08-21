---
project: projectD-core
date: 2026-08-22
type: architecture
status: accepted
evidence_level: verified
technologies: [PowerShell, JSON Schema, Claude Code]
commits: []
supersedes: []
verified_by:
  - "user-authorized Claude Phase 3 continuation"
  - "local Claude Code CLI 2.1.229 capability check"
  - "shared host-trial contract passed for Codex and Claude"
---

# 採用 Governance Evals v2 Phase 3 Claude Adapter Contract

## Context

[verified] Codex-first envelope、checkpoint、manual import 與 paired upgrade gate 已完成，
但 host schema 與 identity validation 仍固定為 Codex，無法接收 Claude evidence。

[user-confirmed] 使用者於 2026-08-22 指示執行 Claude 支援與後續 pilot 流程。

## Decision

1. Host envelope 支援 `codex` 與 `claude`，並以 JSON Schema 綁定各自 adapter identity。
2. Shared host validator 以 envelope 的 `host.name` 驗證 trial agent，不再寫死 Codex。
3. `claude-governance-adapter.ps1` 沿用 Codex 已通過安全／隱私審查的 bounded manual-import
   engine，只改變 host、CLI 與 adapter identity；不啟動 Claude、不保存 session 或 prompt。
4. 真實 Claude runner 不以模型自述作 observable final state。開始 pilot 前，必須先固定
   baseline／candidate 完整 model ID、instruction digest、案例 observer／grader 與成本邊界。
5. 使用者要求只消耗既有訂閱額度，不產生額外費用；run plan 因此固定為
   `subscription-only`、`additional_spend_allowed=false`、USD caps 為 0，額度耗盡即停止等待。

## Resolution

[verified] 已完成：

- Provider-neutral `governance-host-trials.schema.json` host／adapter binding。
- `claude-governance-adapter.ps1`。
- `governance-host-trial-eval.ps1` shared identity validation。
- Codex／Claude 共用的 deterministic host-trial contract coverage。
- Claude adapter asset inventory 與操作文件。
- Claude paired-pilot run-plan schema／validator：完整 model identity、source digest、observer
  coverage、plan-only permission、session persistence 關閉與零額外支出皆 fail closed；不啟動模型。
- 本機 auth preflight 僅輸出非敏感欄位，確認 `claude.ai` Team subscription，且沒有
  `ANTHROPIC_API_KEY` 或 Bedrock／Vertex／Foundry provider flags；未讀取帳號、組織或憑證值。

## Verification

- PowerShell parser：Codex adapter、Claude adapter、shared host validator 均通過。
- Host-trial contract：Codex／Claude evidence、host／adapter identity binding 與負向 mutation 均通過。
- Paired upgrade gate contract：通過。
- Governance asset inventory：17 assets valid。
- `projectd-check -SkipFleet -SkipGlobal -SkipWiring -GovernanceEvals`：15 passed、0 failed。
- Implementation review gate contract：3 tests passed。
- Security review：未發現會啟動模型、越權寫入、保存 prompt／reasoning／credential，或跨 host 冒用 identity 的重大問題。
- Code review：未發現阻擋此 manual-import vertical slice 的 material finding；live runner 仍明確列為未完成邊界。

## Remaining boundary

- 尚未呼叫 Claude 模型，亦未產生 Claude API／訂閱用量。
- 本機 paired-pilot plan 已選定 baseline `claude-opus-4-8` 與 candidate `claude-opus-5`，
  但尚未執行模型。
- Instruction／fixture digest 與 observer coverage 已進入 run-plan contract；尚未建立實際
  tool-event／filesystem／smoke-test observers 與 live capture runner。
- 尚未執行六次小型 pilot、完整 paired trials 或 Codex／Claude compatibility matrix。
