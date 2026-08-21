# projectD Skill 總目錄

## 使用方式

projectD 目前維護 43 個 Canonical Skill：34 個跨技術棧 Skill 與 9 個技術棧
Pack。通常只要用自然語言描述工作，Agent 就會依 Skill 的 description 自動
路由；需要明確指定時可說：

```text
使用 $research 調查這個問題
使用 $code-review 審查目前修改
使用 $frontend-react 實作這個元件
```

本目錄是方便閱讀的摘要。每個連結指向該 Skill 的唯一行為規則來源
`SKILL.md`；若摘要與原始規則不同，以 `SKILL.md` 為準。

## 規劃、研究與交付

| Skill | 用途 | 適合使用時機 |
| --- | --- | --- |
| [`grill-me`](../../core/skills/grill-me/SKILL.md) | 啟動逐題追問流程。 | 明確要求「grill me」或希望行動前逐題釐清。 |
| [`grilling`](../../core/skills/grilling/SKILL.md) | 壓力測試計畫、決策或想法。 | 希望透過持續追問找出盲點。 |
| [`grill-with-docs`](../../core/skills/grill-with-docs/SKILL.md) | 追問並同步提煉術語與架構決策文件。 | 想壓力測試設計，且保留確認後的知識。 |
| [`research`](../../core/skills/research/SKILL.md) | 使用高可信來源調查並產出 Markdown 研究文件。 | 需要查資料、比較方案或留下可追溯研究。 |
| [`prototype`](../../core/skills/prototype/SKILL.md) | 建立一次性原型回答設計問題。 | 想先驗證狀態模型、邏輯或 UI 感受。 |
| [`domain-modeling`](../../core/skills/domain-modeling/SKILL.md) | 建立與精煉領域模型及共通語言。 | 需要釐清術語、邊界或記錄架構決策。 |
| [`manage-requirement-knowledge`](../../core/skills/manage-requirement-knowledge/SKILL.md) | 管理 ProjectD 的正式需求知識。 | 匯入或調整 DOC／DOCX 需求，或除錯結果改變規格。 |
| [`to-questionnaire`](../../core/skills/to-questionnaire/SKILL.md) | 把尚無法回答的決策轉為問卷。 | 需要交由利害關係人補齊答案。 |
| [`to-spec`](../../core/skills/to-spec/SKILL.md) | 把已討論內容整理成可審查規格。 | 需求已大致確定，要形成 Spec 或 PRD。 |
| [`to-tickets`](../../core/skills/to-tickets/SKILL.md) | 把核准內容拆成有依賴關係的垂直切片票券。 | 準備進入實作，需要驗收條件與阻擋關係。 |
| [`wayfinder`](../../core/skills/wayfinder/SKILL.md) | 把跨多次工作的大型目標整理成決策地圖。 | 工作規模超過單一 Agent session。 |
| [`query-project-history`](../../core/skills/query-project-history/SKILL.md) | 搜尋已驗證的歷史決策、除錯與失敗嘗試。 | 詢問以前是否遇過、為何這樣設計或過去如何修復。 |
| [`implement`](../../core/skills/implement/SKILL.md) | 依核准範圍實作、測試並完成強制審查。 | 規格或票券已確定，要求正式實作。 |
| [`code-review`](../../core/skills/code-review/SKILL.md) | 以 Standards 與 Spec 雙軸唯讀審查程式修改。 | 審查工作樹、分支、提交或 PR。 |
| [`security-review`](../../core/skills/security-review/SKILL.md) | 對安全邊界做證據導向的唯讀審查。 | 修改認證、秘密、敏感資料、檔案、外部 API 或部署權限。 |

## 程式結構、探索與除錯

| Skill | 用途 | 適合使用時機 |
| --- | --- | --- |
| [`codebase-design`](../../core/skills/codebase-design/SKILL.md) | 使用 deep module 詞彙設計或改善模組介面。 | 決定 seam、降低耦合或提升可測試性與 AI 可讀性。 |
| [`improve-codebase-architecture`](../../core/skills/improve-codebase-architecture/SKILL.md) | 掃描可深化的模組並產出視覺化報告。 | 想系統性找出架構改善機會。 |
| [`codegraph`](../../core/skills/codegraph/SKILL.md) | 透過既有 CodeGraph 查符號、呼叫者與依賴。 | Repository 已有 `.codegraph` 或明確要求使用 CodeGraph。 |
| [`diagnosing-bugs`](../../core/skills/diagnosing-bugs/SKILL.md) | 依診斷迴圈找出困難錯誤或效能退化原因。 | 發生 broken、throwing、failing、slow 或要求 debug。 |
| [`resolving-merge-conflicts`](../../core/skills/resolving-merge-conflicts/SKILL.md) | 解決進行中的 Git merge／rebase 衝突。 | Git 已處於合併或 rebase 衝突狀態。 |

## UI、視覺與動效

| Skill | 用途 | 適合使用時機 |
| --- | --- | --- |
| [`animation-vocabulary`](../../core/skills/animation-vocabulary/SKILL.md) | 辨識並區分動畫與動效術語。 | 想知道效果名稱，或需要精準描述給設計與實作者。 |
| [`apple-design`](../../core/skills/apple-design/SKILL.md) | 運用 Apple 風格的互動與流體動效原則。 | 設計手勢、sheet、拖曳、spring、材質與 reduced motion。 |
| [`design-engineering`](../../core/skills/design-engineering/SKILL.md) | 提升 Web UI 的互動、元件、排版、無障礙與感知效能。 | 介面需要更精緻、一致且有回饋。 |
| [`find-animation-opportunities`](../../core/skills/find-animation-opportunities/SKILL.md) | 唯讀找出真正值得加入動效的互動時刻。 | 想讓介面更有生命力，但尚未決定哪些地方該動。 |
| [`improve-animations`](../../core/skills/improve-animations/SKILL.md) | 稽核整個專案的動效品質並提出改善路線。 | 要降低卡頓、改善無障礙或規劃動效改造。 |
| [`review-animations`](../../core/skills/review-animations/SKILL.md) | 專門審查動效目的、連續性、中斷性、無障礙與效能。 | 已有動效 diff、元件或原型需要審查。 |
| [`select-frontend-capability`](../../core/skills/select-frontend-capability/SKILL.md) | 以需求選擇或替換前端能力與依賴。 | 選 UI primitive、表單、狀態、動效、圖表或 styling 方案。 |
| [`visual-direction`](../../core/skills/visual-direction/SKILL.md) | 在實作前建立或審查有證據的視覺方向。 | 新介面、改版或視覺過於普通且不一致。 |

## Skill 治理

| Skill | 用途 | 適合使用時機 |
| --- | --- | --- |
| [`skill-scout`](../../core/skills/skill-scout/SKILL.md) | 有界、唯讀地尋找或檢查 GitHub Agent Skill。 | 找指定能力的 Skill，或審查明確 GitHub Skill 路徑。 |
| [`skill-update-check`](../../core/skills/skill-update-check/SKILL.md) | 比對 pinned digest，檢查已採用 GitHub Skill 的上游變更。 | 想知道 CanonicalSkill 是否需要重新審查更新。 |
| [`writing-great-skills`](../../core/skills/writing-great-skills/SKILL.md) | 提供撰寫與修改 Skill 的共通詞彙與原則。 | 設計、重構或審查 Skill 內容。 |

## 帳號、內部系統與專用工具

| Skill | 用途 | 適合使用時機 |
| --- | --- | --- |
| [`claude-switch-account`](../../core/skills/claude-switch-account/SKILL.md) | 安全查看或切換 Claude Code 訂閱帳號。 | 查目前帳號、切換工作／個人帳號或確認未使用 API 計費。 |
| [`tfs`](../../core/skills/tfs/SKILL.md) | 查詢或管理 F25B TFS 的建置、部署、Pipeline 與工作項目。 | 查 build／release 狀態或執行經確認的 TFS 變更。 |
| [`tfs-code`](../../core/skills/tfs-code/SKILL.md) | 搜尋、閱讀與 clone F25B TFS 原始碼。 | 找 repository、符號、檔案或進行跨 repository 搜尋。 |

## 技術棧 Packs

Pack 在修改對應技術棧時提供語言、框架、測試與建置慣例。

| Pack | 用途 | 適合使用時機 |
| --- | --- | --- |
| [`csharp`](../../packs/csharp/SKILL.md) | C#、ASP.NET Core、服務與既有 .NET Framework 慣例。 | 修改 `.cs`、solution／project、DI、資料存取、非同步或測試。 |
| [`frontend-angular`](../../packs/frontend-angular/SKILL.md) | 現代 Angular 慣例與能力選擇。 | 修改 component、service、Signals、RxJS、routing、forms 或測試。 |
| [`frontend-angularjs`](../../packs/frontend-angularjs/SKILL.md) | AngularJS 1.x 維護、測試與漸進遷移慣例。 | 修改 module、controller、directive、`$scope` 或 digest 行為。 |
| [`frontend-core`](../../packs/frontend-core/SKILL.md) | Framework-neutral 的 HTML、CSS、無障礙與互動慣例。 | 任何瀏覽器 UI 工作，不限框架。 |
| [`frontend-react`](../../packs/frontend-react/SKILL.md) | React component、hook、state、routing 與測試慣例。 | 修改 React／TSX 或 React build 設定。 |
| [`node-runtime`](../../packs/node-runtime/SKILL.md) | Node.js 服務、CLI、非同步與 process lifecycle 慣例。 | 修改 Node entry point、Express、檔案／程序資源或 shutdown。 |
| [`python`](../../packs/python/SKILL.md) | Python automation、Web backend 與資料處理慣例。 | 修改 Python module、型別、依賴、FastAPI／Flask／Django 或測試。 |
| [`rdl-report`](../../packs/rdl-report/SKILL.md) | 建立、修改與驗證 F25B ESOAF 家族的 SSRS RDL 報表。 | 新增 RDL、調整版面、檢查資料來源或處理 `rptsp_` 報表程序。 |
| [`typescript`](../../packs/typescript/SKILL.md) | TypeScript／JavaScript、module system 與 build tool 慣例。 | 修改 `.ts`、`.tsx`、JavaScript、`tsconfig` 或 package scripts。 |

## 維護規則

- 新增、移除或重新命名 Canonical Skill 時，同步更新本目錄。
- 不在本文件複製 Skill 的完整 workflow、命令或安全規則；詳細內容直接連到
  `SKILL.md`，避免兩份行為規則分歧。
- 使用 `scripts/projectd-check.ps1` 驗證 Canonical Skill 名稱、frontmatter 與
  catalog 結構。
- 外部 Skill 的來源、版本與採用狀態由
  `vault/governance/skill-registry.json` 管理，不在本目錄重複維護。
