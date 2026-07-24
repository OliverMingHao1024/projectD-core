---
name: grilling
type: external-tool-reference
source: https://github.com/mattpocock/skills
---

# Grilling (/grill-me)

外部技能庫，不是重寫的內容——這裡只記錄「這是什麼、何時用」，安裝/更新以原專案為準。

## 是什麼

Matt Pocock 的 `mattpocock/skills` 提供的 `/grill-me`（一般用途）與 `/grill-with-docs`
（工程用途，多附加項）技能：讓 agent 在動手做之前，針對計畫/決策/想法對使用者
連續發問，逐一釐清依賴關係，直到雙方對齊為止。目的是解決「AI 做出來的東西不是
你要的」這個最常見的失敗模式。

## 何時使用

- 使用者觸發 grill 相關字眼，或想在動手前先壓力測試自己的想法/計畫/決策。
- 任何 PM/SA 階段（見 `core/agents/pm.md`、`core/agents/sa.md`）需要釐清模糊需求時，
  可以考慮先跑一次 grilling，而不是直接假設。

## 怎麼用

- 若已透過 `npx skills@latest add mattpocock/skills` 或 Claude Code plugin 安裝，
  直接呼叫 `/grill-me`（非程式相關）或 `/grill-with-docs`（工程相關）。
- 尚未安裝時，不要憑空模仿；先安裝或明確告知使用者尚未具備此技能。

## 安裝（依需要，不預先裝）

```bash
npx skills@latest add mattpocock/skills
# 或 Claude Code plugin
/plugin marketplace add mattpocock/skills
/plugin install mattpocock-skills@mattpocock
```

安裝方式、內容更新以原專案為準，本檔案不重複維護。
