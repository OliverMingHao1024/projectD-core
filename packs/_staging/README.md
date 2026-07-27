# packs/_staging — Skill 候選暫存區（未畢業，不可信任）

> 這裡的內容**不是正式規範**。任何 agent／工具都不得把 `_staging/` 底下的內容當作
> 可信 pack 載入或遵循。底線前綴 `_` 即代表「隔離、未畢業」。

## 用途

暫存經 `skill-scout` 定向找到、且由使用者選定要審查的 GitHub Skill。搜尋本身唯讀；
只有使用者另外確認 staging 後才能建立候選目錄。

## 目錄命名慣例

一候選一子目錄：

    packs/_staging/<owner>-<repo>--<完整-skill-路徑>/
      upstream/
      adapted/
      SOURCE.md

- id 規則為 `<owner>-<repo>--<完整相對路徑>`，所有非英數字元轉成 `-`。
- 此名稱必須與 `vault/governance/skill-registry.json` 的 candidate `id` 完全一致。

每個子目錄至少包含：
- `upstream/`：鎖定 commit 的原始快照；不得就地修改。
- `adapted/`：projectD 跨 Agent 候選版本。
- `SOURCE.md`：來源 URL、授權（SPDX）、擷取日期、原始 commit hash、star 快照。

## 隔離聲明

- `_staging/` **不會**、也**不應**被連結到 `~/.claude/skills/`（`setup.ps1` 只連結不以 `_`
  開頭的正式 pack 目錄）。
- 內容可能過時、格式未驗、授權未定，未經畢業一律視為不可信。

## 畢業（graduation）條件

一個候選要離開 `_staging/` 進正式 pack，必須同時滿足：
1. 靜態審查通過（格式正確、無明顯過時、與現有規範無矛盾）；不得自動執行候選 scripts。
2. 授權明確（MIT / Apache-2.0 / BSD 等；授權未明者一律不得畢業）。
3. 使用者主觀確認「好用、要收」。

## 畢業後的動作

- **收錄**：只把 `adapted/` 的跨 Agent 版本畢業為 CanonicalSkill。跨技術棧通用能力移入
  `core/skills/`；特定技術棧能力移入 `packs/<stack>/`。
- **拒絕/暫緩**：清空該子目錄，並在 `skill-candidates.md` 的 `## 已拒絕・暫緩` 留痕（含理由）。

機器狀態更新於 `vault/governance/skill-registry.json`；人工理由留痕於
`vault/governance/skill-candidates.md`。

## SOURCE.md 欄位範本

每個候選子目錄內的 `SOURCE.md` 建議格式：

```markdown
# SOURCE — <owner>/<repo>/<skill-path>

- id：<owner>-<repo>--<完整-skill-路徑>
- 來源連結：https://github.com/<owner>/<repo>/tree/<commit>/<skill-path>
- 授權條款（SPDX）：MIT
- 授權二次確認：gh api repos/<owner>/<repo>/license -> spdx_id = MIT（已核）
- 擷取日期：2026-07-24
- 原始 commit hash：<40 碼 sha>
- star 數（擷取時）：1.2k
- 最近更新（擷取時）：2026-06-30
- 發現管道：gh search / gh code search / WebSearch(awesome-list 名稱)
- 擷取內容：SKILL.md（+ 若有輔助檔，逐一列出）
- upstream digest：sha256:<digest>
- 對應 registry：vault/governance/skill-registry.json
- 對應決策紀錄：vault/governance/skill-candidates.md#<heading>
- 備註：（可選，例如 code search 命中的檔案路徑、rate limit 情況）
```
