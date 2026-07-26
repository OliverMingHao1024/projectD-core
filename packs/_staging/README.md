# packs/_staging — Skill 候選暫存區（未畢業，不可信任）

> 這裡的內容**不是正式規範**。任何 agent／工具都不得把 `_staging/` 底下的內容當作
> 可信 pack 載入或遵循。底線前綴 `_` 即代表「隔離、未畢業」。

## 用途

暫存透過 `/skill-scout` 從 GitHub 發現、使用者選定要試用的 Skill 候選。每個候選在此有
一個獨立子目錄，供 `pg` 乾跑把關與使用者主觀評估，尚未進入正式 `packs/`。

## 目錄命名慣例

一候選一子目錄：

    packs/_staging/<owner>-<repo>/

- `<owner>-<repo>` 全小寫，`/` 換成 `-`（例：GitHub `example/skill-repo` → `example-skill-repo`）。
- 此名稱必須與 `vault/governance/skill-candidates.md` 中該筆的 `- id：` 完全一致，
  三者（候選紀錄 ↔ staging 目錄 ↔ 目標 pack）用同一把 key 串起。

每個子目錄至少包含：
- 候選原始的 `SKILL.md`（及必要輔助檔）。
- `SOURCE.md`：來源 URL、授權（SPDX）、擷取日期、原始 commit hash、star 快照。

## 隔離聲明

- `_staging/` **不會**、也**不應**被連結到 `~/.claude/skills/`（`setup.ps1` 只連結不以 `_`
  開頭的正式 pack 目錄）。
- 內容可能過時、格式未驗、授權未定，未經畢業一律視為不可信。

## 畢業（graduation）條件

一個候選要離開 `_staging/` 進正式 pack，必須同時滿足：
1. `pg` 乾跑把關通過（格式正確、無明顯過時、與現有規範無矛盾）。
2. 授權明確（MIT / Apache-2.0 / BSD 等；授權未明者一律不得畢業）。
3. 使用者主觀確認「好用、要收」。

## 畢業後的動作

- **收錄**：改寫成跨工具通用表述、標注來源+授權，移入 `packs/<stack>/`（技術棧規範型）
  或 `core/skills/`（外部工具參考型）。移入後從 `_staging/` 清空該子目錄。
- **拒絕/暫緩**：清空該子目錄，並在 `skill-candidates.md` 的 `## 已拒絕・暫緩` 留痕（含理由）。

無論收錄與否，決策都必須留痕於 `vault/governance/skill-candidates.md`。

## SOURCE.md 欄位範本

每個候選子目錄內的 `SOURCE.md` 建議格式：

```markdown
# SOURCE — <owner>/<repo>

- id：<owner>-<repo>
- 來源連結：https://github.com/<owner>/<repo>
- 授權條款（SPDX）：MIT
- 授權二次確認：gh api repos/<owner>/<repo>/license -> spdx_id = MIT（已核）
- 擷取日期：2026-07-24
- 原始 commit hash：<40 碼 sha>
- star 數（擷取時）：1.2k
- 最近更新（擷取時）：2026-06-30
- 發現管道：gh search / gh code search / WebSearch(awesome-list 名稱)
- 擷取內容：SKILL.md（+ 若有輔助檔，逐一列出）
- 對應候選紀錄：vault/governance/skill-candidates.md#<owner>-<repo>
- 備註：（可選，例如 code search 命中的檔案路徑、rate limit 情況）
```
