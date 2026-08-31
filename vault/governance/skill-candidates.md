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
