---
type: vault-init
alwaysApply: true
readAt: session-start
priority: highest
---

# projectD-core Vault — 跨 session 記憶

> projectD-core 專用、跨專案與 AI 工具共用；內容只來自實際使用、決策與教訓。

## Init 讀取序列（每次 session 開始）

1. `vault/README.md`（本頁）
2. `vault/identity/profile.md` — 服務對象
3. `vault/memory/memory-summary.md` — 記憶快照（先看 lastUpdated）
4. `vault/governance/INDEX.md` — 制度路由

其他資料夾：`after-action/` 放事後回顧與踩坑紀錄（事件驅動）。

## 維護責任

- 使用者：補 `identity/`、更新 `memory/memory-summary.md`
- AI：只有產生可長期重用的決策或教訓時，才提醒使用者更新 memory
