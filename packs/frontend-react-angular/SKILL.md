---
name: frontend-react-angular
description: React/Angular/TypeScript/HTML/CSS conventions for PG.
---

# Frontend (React / Angular / TypeScript) Pack

## 能力選型路由

- 選擇或替換 UI、狀態、表單、動效、圖表、虛擬化等能力時，先使用
  `core/skills/select-frontend-capability/SKILL.md` 定義需求與決策深度。
- React 專案按需讀 `references/react-capabilities.md`；Angular 專案按需讀
  `references/angular-capabilities.md`。
- Monorepo 依目前操作的 app／package 路由，不以 repo 根目錄推定唯一技術棧。
- adapter 內所有套件都是條件式候選；專案決策與既有可維護方案優先。

## React 專案結構慣例

- 狀態管理視資料性質選擇，兩種都會用到，不要混用同一類資料：
  - **伺服器/非同步資料**（API 回應、快取）→ React Query/TanStack Query，
    不要把伺服器資料塞進 Redux/Zustand。
  - **跨元件的用戶端全域狀態**（UI 狀態、跨頁共用的使用者操作結果）→
    Redux 或 Zustand，依專案既有選擇，不在同一專案混用兩者。
  - **單一元件或父子層級夠用的狀態** → `useState`/Context，不要為了「以防萬一」
    就升級成全域 store。
- 元件檔案：一個檔案一個元件，檔名與元件名一致（PascalCase）。
- API 呼叫集中在 hooks 或 service 層，不要在元件內直接 `fetch`。

## Angular 專案結構慣例

- 待補：目前沒有實際 Angular 專案可參考，等第一個真實 Angular 專案出現時，
  依該專案的 module/standalone component 慣例補上，不預先假設。

## TypeScript 共用規則

- `strict: true`，不關閉型別檢查來讓程式碼「先跑起來」。
- 避免 `any`；真的無法定型時，用 `unknown` 並在使用處縮小型別。
- 型別定義與使用處放在合理鄰近的地方，共用型別才抽到獨立檔案，不要一開始
  就建一個大而全的 `types.ts`。

## HTML/CSS 慣例

- 待補：依實際專案使用的方案（CSS Modules/Tailwind/SCSS 等）填入，
  目前沒有足夠使用資訊可以先寫死規則。

## Code Review Checklist

- [ ] 伺服器資料是否誤放進 Redux/Zustand，而不是用 React Query？
- [ ] 是否有不必要的全域 state（明明只有單一元件在用）？
- [ ] `useEffect` 依賴陣列是否正確，有無遺漏依賴造成的 stale closure？
- [ ] TypeScript 是否有 `any` 濫用？
- [ ] 元件是否過度肥大，該拆的邏輯有沒有抽成 hook？

## 測試慣例 / Build 指令

- 沿用專案既有測試框架與套件管理器（例如 Vitest、Jest、Karma；npm、pnpm、yarn），
  不為統一工具而替換現有設定。
- 新增可觀察行為或修復 bug 時，先寫失敗的元件／hook／service 測試重現期望（Red），
  再做最小實作（Green），最後在測試保護下重構（Refactor）。
- 優先驗證使用者可觀察行為與公開介面，避免綁死元件內部實作細節。
- 專案沒有測試基礎設施時，不擅自新增框架或依賴；先執行 build、type check、
  lint 與可重現的人工主路徑，並說明未自動化的缺口。

<!-- Angular 結構慣例、HTML/CSS 慣例與實際測試指令待真實專案出現時補上，
     不預先寫死特定工具。 -->
