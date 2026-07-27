# Skill 候選決策紀錄

> 保存人工審查理由。機器可讀的來源、單一 Skill ID、commit、digest、生命週期狀態與
> canonical 目標以 `skill-registry.json` 為準。
> 格式契約：三個固定 H2 區塊 + 每筆用 `### <owner>/<repo>` H3 標題 + 固定 key 條列。
> 回填策略：區塊定位搬移，不整檔重寫（避免破壞手改內容）。
> 本檔既有 repo 級 `id` 是歷史欄位；新候選使用
> `<owner>-<repo>--<完整-skill-路徑>`，與 registry 及 staging 目錄一致。

固定欄位 key（每筆）：
`id`、`來源連結`、`授權條款`、`star 數（評估時）`、`最近更新`、`評估日期`、`結論`、
`理由`、`目標 pack`（收錄／部分收錄時填）、`發現管道`。
`結論` 用固定 enum：`收錄` / `部分收錄` / `暫緩` / `拒絕`。
`部分收錄`：只吸收來源中可用的片段，其餘捨棄；`理由` 必須寫清楚抽了什麼、捨了什麼、為何捨。

## 已收錄

<!-- 畢業並移入正式 pack 者。每筆務必補「目標 pack」。 -->

### mattpocock/skills（grill-with-docs）
- id：mattpocock-skills
- 來源連結：https://github.com/mattpocock/skills/tree/ed37663cc5fbef691ddfecd080dff42f7e7e350d/skills/engineering/grill-with-docs
- 授權條款：MIT
- star 數（評估時）：191111
- 最近更新：2026-07-27
- 評估日期：2026-07-28
- 結論：收錄
- 理由：使用者指名收錄。此 Skill 是既有 grilling 與 domain-modeling 的小型組合工作流；相依能力已存在。引入時移除 Claude 專屬 `/skill` 語法與 `disable-model-invocation` metadata，補上跨 Agent 觸發、相依 Skill 缺少時的降級行為，以及逐筆確認後才寫入 CONTEXT.md／ADR 的界線。
- 目標 pack：core/skills/grill-with-docs
- 發現管道：使用者指定 + gh repo/API 實檔審查

### mattpocock/skills（codebase-design / domain-modeling / improve-codebase-architecture / writing-great-skills）
- id：mattpocock-skills
- 來源連結：https://github.com/mattpocock/skills
- 授權條款：MIT
- star 數（評估時）：189187
- 最近更新：2026-07-23
- 評估日期：2026-07-26
- 結論：部分收錄
- 理由：使用者指名要收 improve-codebase-architecture 與 writing-great-skills。improve-codebase-architecture 依賴 codebase-design（詞彙）與 domain-modeling（CONTEXT.md/ADR 收斂），兩者皆未收錄；使用者確認四者一起收錄才能保持功能完整（同一 id 下已有 grill-me/grilling 先前收錄，未留痕於本檔，屬歷史缺口）。PG 乾跑找出並已修正：(1) codebase-design/DEEPENING.md 內建「刪除舊測試」指令，改為需明確使用者核准才刪；(2) domain-modeling 原版就地寫入 CONTEXT.md/ADR，改為提案後才寫（與 emilkowalski 收錄時同一類寫入授權問題）；(3) improve-codebase-architecture 的 `subagent_type=Explore`、`/skill` 斜線語法、Windows `start`/`%TEMP%` 均為 Claude Code 專屬寫法，已改寫為工具中立表述並修正 Git Bash/PowerShell 相容性；(4) 為 codebase-design 加入「使用者指示 > 專案既有慣例 > 本 skill 詞彙」優先序前言，避免強加 DDD/命名體系覆蓋既有專案慣例；(5) 四者皆補上 LICENSE 與 `## Source` 溯源段（比照既有 grill-me/grilling 格式）。此結論不涵蓋同來源的 tdd/code-review（見上方「已拒絕・暫緩」同一 id 的舊評估，範圍不同、未重新檢視）。
- 目標 pack：core/skills/{codebase-design,domain-modeling,improve-codebase-architecture,writing-great-skills}
- 發現管道：使用者指定（本機已安裝 plugin marketplace `~/.claude/plugins/marketplaces/mattpocock`）+ PG dry-run

### mattpocock/skills（第二批：to-questionnaire / resolving-merge-conflicts / diagnosing-bugs / research / prototype / wayfinder）
- id：mattpocock-skills
- 來源連結：https://github.com/mattpocock/skills
- 授權條款：MIT
- star 數（評估時）：189187
- 最近更新：2026-07-23
- 評估日期：2026-07-26
- 結論：部分收錄
- 理由：使用者從 README 概覽中選定這六個（排除 git-guardrails-claude-code，留待之後單獨評估）。wayfinder 依賴 research 與 prototype（Research/Prototype 票種）；使用者確認三者一起收，但明確不收 setup-matt-pocock-skills（per-repo 一次性 issue tracker 設定流程）。PG 乾跑找出並已修正：(1) resolving-merge-conflicts 原版「stage everything and commit」「never --abort」直接違反 L0 不可逆操作需授權，改為只 stage 衝突相關檔案、commit 前出示 diff 並取得同意、abort 改為使用者的選擇而非 agent 自行排除的選項；(2) research 的 background-agent 派工與 findings 寫檔皆改為條件式/需確認；(3) prototype 的 SKILL.md/UI.md 把「commit 到 throwaway branch」「刪除落選 variant」「改 package.json/Makefile」全部改為提案後才動手，且不再假設一定有 issue tracker；(4) diagnosing-bugs 修正 CONTEXT.md/ADR 存在假設與 `/improve-codebase-architecture`、`scripts/hitl-loop.template.sh` 的死引用；(5) wayfinder 改動最大：移除對未收錄 setup-matt-pocock-skills 的依賴，改為就地定義 local-markdown tracker fallback（claim/blocking/frontier 皆給出 markdown 慣例的對應寫法）；所有 `/skill` 斜線引用改寫成工具中立的 Skill 名稱＋降級語；「update or delete tickets」改為「一律 close 並記錄原因，不刪除」；不確定 assignee 時改為詢問而非猜測；每一次 tracker 寫入（建 issue、指派、留言、關閉、開分支）都要求先出示批次內容再取得使用者確認。六者皆補上 LICENSE 與 `## Source` 溯源段。
- 目標 pack：core/skills/{to-questionnaire,resolving-merge-conflicts,diagnosing-bugs,research,prototype,wayfinder}
- 發現管道：使用者指定（本機已安裝 plugin marketplace）+ PG dry-run

### emilkowalski/skills
- id：emilkowalski-skills
- 來源連結：https://github.com/emilkowalski/skills
- 授權條款：MIT
- star 數（評估時）：20922
- 最近更新：2026-07-23
- 評估日期：2026-07-26
- 結論：部分收錄
- 理由：部分收錄並全面改寫 apple-design、animation-vocabulary、emil-design-eng、find-animation-opportunities、improve-animations、review-animations。保留設計／動效核心方法，修正 duration-based spring、效能保證、絕對 duration、Pointer Events、無障礙、跨框架與寫入授權問題。原版 pick-ui-library 的封閉清單違反 L0 生態中立，不建立 active Skill；僅把經驗證且附條件的 React 候選整合至既有能力 adapter。
- 目標 pack：core/skills/{apple-design,animation-vocabulary,design-engineering,find-animation-opportunities,improve-animations,review-animations} + packs/frontend-react/references/react-capabilities.md
- 發現管道：使用者指定 + gh repo/API 實檔審查 + PG dry-run

## 評估中

<!-- 已進 packs/_staging/、等 pg 乾跑或使用者判斷者。 -->

### addyosmani/agent-skills
- id：addyosmani-agent-skills
- 來源連結：https://github.com/addyosmani/agent-skills
- 授權條款：MIT
- star 數（評估時）：80128
- 最近更新：2026-07-24
- 評估日期：2026-07-24
- 結論：（待使用者判斷，尚未落 staging）
- 理由：Addy Osmani 署名，「production-grade engineering skills」，信度較高。使用者選擇先留存查詢結果，後續再看。
- 目標 pack：（待定）
- 發現管道：gh search --topic claude-code

### agentskills/agentskills
- id：agentskills-agentskills
- 來源連結：https://github.com/agentskills/agentskills
- 授權條款：Apache-2.0
- star 數（評估時）：23413
- 最近更新：2026-07-10
- 評估日期：2026-07-24
- 結論：（待使用者判斷，尚未落 staging）
- 理由：Agent Skills 開放標準的規格/文件庫本身（非技能包），對治理判準有參考價值。
- 目標 pack：（待定，可能屬 core/skills 外部工具參考型）
- 發現管道：gh search --topic ai-agent-skills

### K-Dense-AI/scientific-agent-skills
- id：k-dense-ai-scientific-agent-skills
- 來源連結：https://github.com/K-Dense-AI/scientific-agent-skills
- 授權條款：MIT
- star 數（評估時）：31631
- 最近更新：2026-07-23
- 評估日期：2026-07-24
- 結論：（待使用者判斷，尚未落 staging）
- 理由：148 個科學領域技能，較利基，與目前技術棧（csharp/frontend/python）關聯度待評估。
- 目標 pack：（待定）
- 發現管道：gh search --topic claude-code

### sickn33/agentic-awesome-skills
- id：sickn33-agentic-awesome-skills
- 來源連結：https://github.com/sickn33/agentic-awesome-skills
- 授權條款：MIT
- star 數（評估時）：43791
- 最近更新：2026-07-22
- 評估日期：2026-07-24
- 結論：（待使用者判斷，尚未落 staging）
- 理由：聲稱 1,987+ 技能的目錄型工具，規模存疑，僅有 star 數未見 WebSearch 質化背書。
- 目標 pack：（待定）
- 發現管道：gh search --topic claude-code / ai-agent-skills（重複命中）

### alirezarezvani/claude-skills
- id：alirezarezvani-claude-skills
- 來源連結：https://github.com/alirezarezvani/claude-skills
- 授權條款：MIT
- star 數（評估時）：23107
- 最近更新：2026-07-17
- 評估日期：2026-07-24
- 結論：（待使用者判斷，尚未落 staging）
- 理由：345 個技能/agent/command，跨工程/行銷/法遵等多角色，範疇廣但需檢視品質一致性。
- 目標 pack：（待定）
- 發現管道：gh search --topic claude-skills

### Jeffallan/claude-skills
- id：jeffallan-claude-skills
- 來源連結：https://github.com/Jeffallan/claude-skills
- 授權條款：MIT
- star 數（評估時）：10710
- 最近更新：2026-05-20
- 評估日期：2026-07-24
- 結論：（待使用者判斷，尚未落 staging）
- 理由：66 個全端開發技能，規模適中、聚焦度較高，與 frontend-core pack 可能有重疊價值。
- 目標 pack：（待定，可能 frontend-core）
- 發現管道：gh search --topic claude-skills

### KKKKhazix/khazix-skills
- id：kkkkhazix-khazix-skills
- 來源連結：https://github.com/KKKKhazix/khazix-skills
- 授權條款：MIT
- star 數（評估時）：17833
- 最近更新：2026-07-24
- 評估日期：2026-07-24
- 結論：（待使用者判斷，尚未落 staging）
- 理由：中文作者技能合集，含 docs/memory closeout 等，與現有治理習慣（繁中回覆、記憶系統）可能有共鳴。
- 目標 pack：（待定）
- 發現管道：gh search --topic claude-skills

### majiayu000/claude-skill-registry
- id：majiayu000-claude-skill-registry
- 來源連結：https://github.com/majiayu000/claude-skill-registry
- 授權條款：MIT
- star 數（評估時）：未取得（code search 意外命中，未走 repo search）
- 最近更新：（未查）
- 評估日期：2026-07-24
- 結論：（待使用者判斷，尚未落 staging）
- 理由：按分類組織的技能登記庫（monday/documents/data 等），code search 意外命中，值得後續細看。
- 目標 pack：（待定）
- 發現管道：gh search code --filename SKILL.md（意外命中）

### yusufkaraaslan/Skill_Seekers
- id：yusufkaraaslan-skill_seekers
- 來源連結：https://github.com/yusufkaraaslan/Skill_Seekers
- 授權條款：MIT
- star 數（評估時）：14544
- 最近更新：2026-07-20
- 評估日期：2026-07-24
- 結論：（待使用者判斷，尚未落 staging）
- 理由：非技能包本身，是「把文件/repo/PDF 轉成技能」的工具型 repo，屬性較接近 external-tool-reference。
- 目標 pack：（待定，可能屬 core/skills）
- 發現管道：gh search --topic claude-skills

### VoltAgent/awesome-agent-skills
- id：voltagent-awesome-agent-skills
- 來源連結：https://github.com/VoltAgent/awesome-agent-skills
- 授權條款：MIT
- star 數（評估時）：28817
- 最近更新：2026-07-10
- 評估日期：2026-07-24
- 結論：（待使用者判斷，尚未落 staging）
- 理由：1000+ 技能策展清單，跨工具，WebSearch 與 gh 雙軌交叉確認。
- 目標 pack：（待定）
- 發現管道：gh search --topic claude-skills + ai-agent-skills（重複命中）+ WebSearch

### JimLiu/baoyu-skills
- id：jimliu-baoyu-skills
- 來源連結：https://github.com/JimLiu/baoyu-skills
- 授權條款：MIT
- star 數（評估時）：24104
- 最近更新：2026-07-04
- 評估日期：2026-07-24
- 結論：（待使用者判斷，尚未落 staging）
- 理由：無 repo 描述，需實際檢視內容才知範疇。
- 目標 pack：（待定）
- 發現管道：gh search --topic claude-skills

### Orchestra-Research/AI-Research-SKILLs
- id：orchestra-research-ai-research-skills
- 來源連結：https://github.com/Orchestra-Research/AI-Research-SKILLs
- 授權條款：MIT
- star 數（評估時）：11047
- 最近更新：2026-06-16
- 評估日期：2026-07-24
- 結論：（待使用者判斷，尚未落 staging）
- 理由：AI 研究/工程技能庫，Maintained by Orchestra Research。
- 目標 pack：（待定）
- 發現管道：gh search --topic claude-skills

### anthropics/skills（授權未明，不可收錄）
- id：anthropics-skills
- 來源連結：https://github.com/anthropics/skills
- 授權條款：未偵測到（gh api 回 404，GitHub license API 未識別出 license 檔案）
- star 數（評估時）：163853
- 最近更新：2026-07-22
- 評估日期：2026-07-24
- 結論：（授權未明，依規則不可進 staging，僅留痕供使用者知情）
- 理由：官方 Anthropic 倉庫，但自動授權偵測未過關；建議使用者親自確認 repo 內是否有 LICENSE 檔（有可能是偵測誤判)。
- 目標 pack：（不適用）
- 發現管道：gh search --topic agent-skills

### ComposioHQ/awesome-claude-skills（授權未明，不可收錄）
- id：composiohq-awesome-claude-skills
- 來源連結：https://github.com/ComposioHQ/awesome-claude-skills
- 授權條款：未偵測到（gh api 回 404）
- star 數（評估時）：69714
- 最近更新：2026-07-24
- 評估日期：2026-07-24
- 結論：（授權未明，依規則不可進 staging，僅留痕供使用者知情）
- 理由：策展清單，WebSearch 交叉確認為社群最大策展清單之一，但授權未明。
- 目標 pack：（不適用）
- 發現管道：gh search --topic claude-code + WebSearch

### travisvn/awesome-claude-skills（授權未明，不可收錄）
- id：travisvn-awesome-claude-skills
- 來源連結：https://github.com/travisvn/awesome-claude-skills
- 授權條款：未偵測到（gh api 回 404）
- star 數（評估時）：14270
- 最近更新：2026-04-28
- 評估日期：2026-07-24
- 結論：（授權未明，依規則不可進 staging，僅留痕供使用者知情）
- 理由：策展清單，WebSearch 交叉確認。
- 目標 pack：（不適用）
- 發現管道：gh search --topic claude-skills + WebSearch

### hesreallyhim/awesome-claude-code（授權未明，不可收錄）
- id：hesreallyhim-awesome-claude-code
- 來源連結：https://github.com/hesreallyhim/awesome-claude-code
- 授權條款：NOASSERTION
- star 數（評估時）：50815
- 最近更新：2026-07-24
- 評估日期：2026-07-24
- 結論：（授權未明，依規則不可進 staging，僅留痕供使用者知情）
- 理由：策展清單，含 skills/agents/status lines，授權標示為 NOASSERTION（等同未明）。
- 目標 pack：（不適用）
- 發現管道：gh search --topic claude-code + ai-agent-skills

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

### dominikmartn/hue
- id：dominikmartn-hue
- 來源連結：https://github.com/dominikmartn/hue
- 授權條款：MIT
- star 數（評估時）：765
- 最近更新：2026-06-11
- 評估日期：2026-07-24
- 結論：（待使用者判斷，尚未落 staging）
- 理由：主題「美化 Web 頁面」關鍵字掃描，從品牌素材學習後生成完整 design system，偏向品牌一致性而非單純美化，需檢視是否與 xiaopu-ai/web-design 重疊。
- 目標 pack：（待定）
- 發現管道：gh search --topic claude-code（先前廣掃已見）

### wondelai/skills
- id：wondelai-skills
- 來源連結：https://github.com/wondelai/skills
- 授權條款：MIT
- star 數（評估時）：1718
- 最近更新：2026-07-22
- 評估日期：2026-07-24
- 結論：（待使用者判斷，尚未落 staging）
- 理由：50 個技能合集（含 top-design 子技能），非專一美化 skill，若收錄應只抽 top-design 子目錄，不整包收（見部分收錄原則）。
- 目標 pack：（待定）
- 發現管道：gh search code --filename SKILL.md "web design"

### nexu-io/html-anything（僅留痕，偏工具型）
- id：nexu-io-html-anything
- 來源連結：https://github.com/nexu-io/html-anything
- 授權條款：Apache-2.0
- star 數（評估時）：7935
- 最近更新：2026-07-14
- 評估日期：2026-07-24
- 結論：（待使用者判斷，尚未落 staging）
- 理由：75 Skills 的 HTML 產出工具型產品，規模大但偏工具而非單一 skill，若收錄可能屬 core/skills 外部工具參考型而非 pack。
- 目標 pack：（待定，可能 core/skills）
- 發現管道：gh search repos "claude code frontend design skill"

### anthropics/skills — skills/frontend-design（授權未明，不可收錄）
- id：anthropics-skills-frontend-design
- 來源連結：https://github.com/anthropics/skills/tree/main/skills/frontend-design
- 授權條款：未偵測到（repo 根目錄無 LICENSE 檔，gh api 回 404）
- star 數（評估時）：163853（整包 repo）
- 最近更新：2026-07-22
- 評估日期：2026-07-24
- 結論：（授權未明，依規則不可進 staging，僅留痕供使用者知情）
- 理由：官方 frontend-design 子技能，多篇 WebSearch 部落格推為第一名，但整包 repo 無 LICENSE 檔，授權未明；且部落格引用的 star 數（65,847）與實際整包 star 數（163,853）對不上，顯示這類排行網站數字不可盡信。
- 目標 pack：（不適用）
- 發現管道：WebSearch + gh api 驗證

### vercel-labs/agent-skills（授權未明，不可收錄）
- id：vercel-labs-agent-skills
- 來源連結：https://github.com/vercel-labs/agent-skills
- 授權條款：未偵測到（gh api 回 404）
- star 數（評估時）：29430
- 最近更新：2026-07-24
- 評估日期：2026-07-24
- 結論：（授權未明，依規則不可進 staging，僅留痕供使用者知情）
- 理由：Vercel 官方技能集，WebSearch 稱「133k 週安裝量」，但無 LICENSE 檔，授權未明。
- 目標 pack：（不適用）
- 發現管道：gh search code --filename SKILL.md "web design"（awesomething repo 提及）+ WebSearch

### nextlevelbuilder/ui-ux-pro-max-skill（存疑，疑似洗星）
- id：nextlevelbuilder-ui-ux-pro-max-skill
- 來源連結：https://github.com/nextlevelbuilder/ui-ux-pro-max-skill
- 授權條款：MIT
- star 數（評估時）：109612
- 最近更新：2026-07-21
- 評估日期：2026-07-24
- 結論：（存疑，不建議採信 star 數，待使用者自行判斷）
- 理由：WebSearch 部落格封為「#1 首選」，但短期內（單一貢獻者、近期推送）star 數異常暴增至 10 萬+，與先前掃描中發現的多筆洗星模式相符，不建議僅憑星數採信；授權雖為 MIT，仍建議先實測內容品質再決定是否落地。
- 目標 pack：（不適用，需先驗證真實性）
- 發現管道：WebSearch

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

### SamurAIGPT/Generative-Media-Skills — logo-branding
- id：samuraigpt-generative-media-skills-logo-branding
- 來源連結：https://github.com/SamurAIGPT/Generative-Media-Skills/tree/main/library/visual/logo-branding
- 授權條款：MIT
- star 數（評估時）：3910
- 最近更新：2026-07-24
- 評估日期：2026-07-26
- 結論：（待使用者判斷，尚未落 staging）
- 理由：可產出三款 Logo 概念、品牌套件與情境 mockup，但流程綁定 muapi.ai、API Key 與多個指定影像模型；較適合作為外部工具參考，不宜整包直接納入通用 Skill。
- 目標 pack：（待定，可能 core/skills 外部工具參考型）
- 發現管道：gh code search

### fucha1122/minimalist-bw-logo-skill
- id：fucha1122-minimalist-bw-logo-skill
- 來源連結：https://github.com/fucha1122/minimalist-bw-logo-skill
- 授權條款：MIT
- star 數（評估時）：19
- 最近更新：2026-06-16
- 評估日期：2026-07-26
- 結論：（待使用者判斷，尚未落 staging）
- 理由：聚焦一次生成 24 款黑白極簡 Logo 探索板，概念發散方法完整且支援中英文；但高度依賴點陣影像生成，文字與幾何精度不如原生 SVG，適合前期發想而非最終交付。
- 目標 pack：（待定，可能 design pack）
- 發現管道：gh code search

## 已拒絕・暫緩

<!-- 拒絕或暫緩者。理由必填；是否重新審查由使用者決定，不由 scout 自動展開。 -->

### mattpocock/skills（tdd / code-review 兩個 skill，此為舊評估範圍）
- id：mattpocock-skills
- 來源連結：https://github.com/mattpocock/skills
- 授權條款：MIT
- star 數（評估時）：185684
- 最近更新：2026-07-23
- 評估日期：2026-07-24
- 結論：暫緩
- 理由：PG 乾跑發現三項阻擋：強制每次測試前由使用者確認 seam、將 Refactor 排除在 TDD loop 外、依賴未擷取的 code-review skill。折衷方案是只吸收公開介面測試、系統邊界 mock 與 Red→Green→Refactor 原則；將 seam 確認改為需求／風險不明時才詢問，移除未擷取依賴，並修正 Jest／Fetch 範例後再試用。此結論僅涵蓋 tdd/code-review 兩個 skill；同一來源其他 skill 分別評估，見「評估中」區塊同一 id 的另一筆。
- 目標 pack：（待定，僅 tdd/code-review 範圍）
- 發現管道：gh search + gh code search + WebSearch
