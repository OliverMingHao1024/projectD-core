# Skill 候選治理清單

> 現行機器可讀的 source、candidate ID、commit、digest、lifecycle 與 canonical target，
> 以 [`skill-registry.json`](skill-registry.json) 為準。
> 完整人工採用／拒絕理由已封存於
> [projectD-knowledge](https://github.com/OliverMingHao1024/projectD-knowledge/blob/4049cdc1dfccaed8910092d499806b2e33c4ab14/archive/projectd-core/history/skill-intake/skill-candidates-full-history.md)。

**維護契約**

- 本檔保留三個固定 lifecycle H2 區塊，以及 registry 引用的精確 H3 decision-record headings。
- 已完成 decision 的 metadata、理由與歷史 star／日期只保存在 archive，不在 core 重複。
- 評估中的候選保留完整人工判斷資料；狀態完成後更新 registry，再把理由追加至 archive。
- 新候選 ID 使用 `<owner>-<repo>--<完整-skill-路徑>`，與 registry 及 staging 目錄一致。
- 候選固定欄位為 `id`、來源、授權、評估證據、結論、理由、目標與發現管道。
- `packs/_staging/` 只放正在有界審查的候選，不保存已採用或已拒絕的完整副本。

## 已收錄

下列 headings 僅為 `skill-registry.json` 的 referential-integrity keys；完整理由見 archive。

### ali/tfs-code

### ch-chang/tfs

### dreamwing/angular-developer

### mattpocock/skills（implement / code-review review gate）

### mattpocock/skills（to-spec / to-tickets）

### mattpocock/skills（grill-with-docs）

### mattpocock/skills（codebase-design / domain-modeling / improve-codebase-architecture / writing-great-skills）

### mattpocock/skills（第二批：to-questionnaire / resolving-merge-conflicts / diagnosing-bugs / research / prototype / wayfinder）

### tt-a1i/archify
- id：tt-a1i-archify--archify
- 來源連結：https://github.com/tt-a1i/archify
- 授權條款：MIT
- 評估日期：2026-09-06 ／ 採用日期：2026-09-06
- Pin commit：d8e4daf2610d512821365f41b139d874b29efe81（採用時的預設分支 HEAD）
- upstream digest：sha256:5bb6f5535d0e4501ac51ecb8b6d2112fab58810ce18477eff1b1af71746f7f45
  （方法：對 `archify/` 子目錄以 `tar --sort=name --mtime='UTC 2020-01-01' --owner=0 --group=0 --numeric-owner` 打包後取 sha256；為本次採用自訂的確定性雜湊法）
- 結論：已收錄，落地至 `core/skills/archify`；已於 2026-09-06 由使用者實機執行
  `node bin/archify.mjs doctor`，全數檢查（Node.js 版本、核心樣板、五種圖表 renderer／schema／example、
  即時預覽與視覺檢查 runtime 等）皆為 `[ok]`，輸出「Archify is ready.」
- 理由：涵蓋架構／流程／循序／資料流／生命週期五種圖表的 Agent Skill，產出具型別 JSON IR，經 schema／layout／HTML-SVG／路由驗證後才交付自包含 HTML；訴求「不瞎掰拓樸、驗證後才交付」。archify 本體是 Node.js 執行期程式（bin/archify.mjs），本次只複製原始碼快照，未實際執行任何 `.mjs` 腳本或安裝流程，執行期驗證留待之後實際使用時再做。archify 預設每約 72 小時對外 GET 一次固定的穩定版本清單以顯示更新提醒（不自動下載或安裝），可用環境變數 `ARCHIFY_UPDATE_CHECK_DISABLED=1` 關閉——已告知使用者並取得知情同意後才採用。
- 目標 pack：core/skills/archify（跨技術棧通用，不綁定特定語言／框架）
- 發現管道：使用者直接提供 GitHub 連結
- 備註（治理缺口，待人工處理）：依維護契約，本條目理由應搬到
  [projectD-knowledge 的 archive](https://github.com/OliverMingHao1024/projectD-knowledge/blob/4049cdc1dfccaed8910092d499806b2e33c4ab14/archive/projectd-core/history/skill-intake/skill-candidates-full-history.md)，
  本檔只留標題。目前沒有該外部 repo 的寫入權限，完整理由暫留本檔，尚未搬遷。

### emilkowalski/skills

### humanlayer/skills — plugins/show-me/skills/show-me

### freestylefly/awesome-gpt-image-2 — agents/skills/gpt-image-2-style-library

## 評估中

<!-- 已進 packs/_staging/、等 pg 乾跑或使用者判斷者。 -->

### xiaopu-ai/web-design
- id：xiaopu-ai-web-design
- 來源連結：https://github.com/xiaopu-ai/web-design
- 授權條款：MIT
- star 數（評估時）：596
- 最近更新：2026-06-24
- 評估日期：2026-07-24
- 結論：（待使用者判斷，尚未落 staging）
- 理由：主題「美化 Web 頁面」關鍵字掃描，專門設計美化網頁的 skill（spec first, code second），規模適中、聚焦度高，star 成長曲線合理。
- 目標 pack：（待定，可能 frontend-core）
- 發現管道：gh search code --filename SKILL.md "web design"

### superdesigndev/superdesign-skill
- id：superdesigndev-superdesign-skill
- 來源連結：https://github.com/superdesigndev/superdesign-skill
- 授權條款：MIT
- star 數（評估時）：362
- 最近更新：2026-07-24
- 評估日期：2026-07-24
- 結論：（待使用者判斷，尚未落 staging）
- 理由：主題「美化 Web 頁面」關鍵字掃描，訴求「Stop shipping AI-slop UI」，superdesign.dev 產品方維護，持續更新中。
- 目標 pack：（待定，可能 frontend-core）
- 發現管道：gh search --topic claude-code（先前廣掃已見）

### tryopendata/skills — plugins/opendesign/skills/svg-design
- id：tryopendata-skills-svg-design
- 來源連結：https://github.com/tryopendata/skills/tree/main/plugins/opendesign/skills/svg-design
- 授權條款：MIT
- star 數（評估時）：106
- 最近更新：2026-07-25
- 評估日期：2026-07-26
- 結論：（待使用者判斷，尚未落 staging）
- 理由：本輪 Logo 設計首選。原生產出可編輯 SVG，涵蓋設計方向訪談、跨類型概念探索、字標與負空間、深淺色版本、瀏覽器預覽、最佳化及無障礙；內容完整且不綁付費影像 API。
- 目標 pack：（待定，可能 core/skills 或新 design pack）
- 發現管道：gh code search + WebSearch（OpenData 作者文章與社群討論交叉命中）

## 已拒絕・暫緩

下列 headings 僅為 `skill-registry.json` 的 referential-integrity keys；完整理由見 archive。

### mattpocock/skills（tdd / code-review 兩個 skill，此為舊評估範圍）

### addyosmani/agent-skills

### agentskills/agentskills

### K-Dense-AI/scientific-agent-skills

### sickn33/agentic-awesome-skills

### alirezarezvani/claude-skills

### Jeffallan/claude-skills

### KKKKhazix/khazix-skills

### majiayu000/claude-skill-registry

### yusufkaraaslan/Skill_Seekers

### VoltAgent/awesome-agent-skills

### JimLiu/baoyu-skills

### Orchestra-Research/AI-Research-SKILLs

### anthropics/skills（授權未明，不可收錄）

### ComposioHQ/awesome-claude-skills（授權未明，不可收錄）

### travisvn/awesome-claude-skills（授權未明，不可收錄）

### hesreallyhim/awesome-claude-code（授權未明，不可收錄）

### dominikmartn/hue

### wondelai/skills

### nexu-io/html-anything（僅留痕，偏工具型）

### anthropics/skills — skills/frontend-design（授權未明，不可收錄）

### vercel-labs/agent-skills（授權未明，不可收錄）

### nextlevelbuilder/ui-ux-pro-max-skill（存疑，疑似洗星）

### SamurAIGPT/Generative-Media-Skills — logo-branding

### fucha1122/minimalist-bw-logo-skill
