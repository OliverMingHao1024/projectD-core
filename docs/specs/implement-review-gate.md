# Implementation Review Gate

- 狀態：approved／active
- 決策依據：[Targeted Skill intake ADR](../adr/0016-targeted-skill-intake.md)
- 導入前完整規格：[Git history](https://github.com/OliverMingHao1024/projectD-core/blob/ef0f62c3e4bffbfc3a5cb4ed35c0c49bb90007eb/docs/specs/implement-review-gate.md)

## 現行交付流程

`to-spec → to-tickets → implement → code-review`

`implement` 只能依 approved specification、ticket 或同等明確的 settled scope 執行。
TDD 由專案證據決定，不是強制流程；相關 validation 與 tests 始終必須執行。

## Completion gate

- Source code 與會改變行為的 configuration 必須通過 `code-review`。
- Documentation-only 工作可明示 `code-review: not applicable`。
- Review 分開回報 Standards 與 Specification findings。
- Review 可檢查 uncommitted working tree，或固定 branch／tag／commit 比較。
- Material fix 最多接受一次 focused re-review，避免無界循環。
- Review 不要求 sub-agent；目前 Agent 可完成兩個審查軸。
- `implement` 與 `code-review` 都不得在未取得使用者明確授權時 commit、push 或開 PR。

## Skill governance

- Canonical Skills：`core/skills/implement/`、`core/skills/code-review/`。
- 共通規則引用 glossary、ADR、repository standards、PG guidance 與 stack packs，不在 Skills 重複。
- 外部來源以 pinned commit 與 digest 記錄於 `vault/governance/skill-registry.json`。
- Upstream drift 只產生報告，不得自動覆寫 CanonicalSkill。
- Claude-specific metadata、mandatory sub-agent dispatch、mandatory TDD、automatic commit 與 upstream
  setup dependency 不屬於 projectD 契約。

## 驗證

- 兩個 Skill 必須通過官方 Skill validator。
- Catalog、registry、contract 與 GovernanceWiring checks 必須通過。
- Contract fixtures 必須涵蓋 working-tree review、fixed-point review、無 specification review、
  non-TDD implementation，以及 material fix 後單次 focused re-review。

```powershell
pwsh -NoProfile -File scripts/projectd-check.ps1
```

## 非目標

本閘門不採用 upstream TDD Skill、不自動修正所有 findings，也不自動 commit、push、開 PR
或合併未來 upstream 變更。
