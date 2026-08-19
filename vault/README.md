---
type: vault-init
alwaysApply: true
readAt: session-start
priority: highest
---

# projectD-core Vault — 跨 session 記憶

> 本 vault 為 projectD-core 專用，跨專案、跨 AI 工具共用。內容只從本系統的
> 實際使用、決策與教訓中累積。

## Init 讀取序列（每次 session 開始）

```
1. vault/README.md                  ← 你現在在這裡
2. vault/identity/profile.md        ← 了解你在服務誰
3. vault/memory/memory-summary.md   ← 載入最新記憶快照（先看 lastUpdated）
4. vault/governance/INDEX.md        ← 制度路由
```

## 資料夾用途

| 資料夾 | 用途 | 更新頻率 |
|--------|------|---------|
| `identity/` | 使用者檔案、AI 角色設定 | 低 |
| `memory/` | 決策紀錄、跨 session 記憶快照 | 高（每次重要決策後）|
| `governance/` | L1–L6 制度路由、判準 | 低 |
| `after-action/` | 事後回顧、踩坑紀錄 | 事件驅動 |

## 維護責任

- 使用者：填寫 `identity/` 待補欄位、更新 `memory/memory-summary.md`
- AI：只有產生可長期重用的決策或教訓時，才提醒使用者更新 memory
