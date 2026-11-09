# Claude Code mods

Claude Desktop（Code 分頁）與 Claude Code 的介面 mod。作者：OliverMingHao1024，授權同本 repository 的 [LICENSE](../../LICENSE)。

| Mod | 位置 | 做什麼 |
|---|---|---|
| `statusbar` | 輸入框上方 | 模型、資料夾與 git 分支（有未 commit 改動加 `*`）、上下文 %、5h / 7d 用量與重置時間、token、本次花費。用量 50% 起黃、80% 起紅。欄位對齊 `.local/statusline.ps1`。資料夾本身不是 repo（如 TFS 工作區根目錄）時，往下一層找子 repo，每個 repo 一顆膠囊顯示分支（最多 6 顆，多的合成 `+N repo`）。第二排有 `/compact`、`/grilling` 按鈕，按下只會填入輸入框。 |
| `open-todos` | 側欄面板 | 依專案列出所有 session 未完成的待辦，以及最近幾分鐘有動靜的 session。輸入 `/todos` 開啟或重新整理。每項待辦有 `Chat` 按鈕，把它填進輸入框討論。 |

## 安裝

1. `pwsh -File scripts\setup.ps1`：把 `core/mods/<name>` 以 junction 接到 `~/.claude/mods/<name>`。
2. 在 `~/.claude/settings.json` 的 `env` 加入（一次就好；setup 不改這個檔案）：

   ```json
   "env": {
     "CLAUDE_CODE_PLUGIN_DIRS": "C:/Users/<你>/.claude/mods/statusbar;C:/Users/<你>/.claude/mods/open-todos",
     "CLAUDE_CODE_PLUGIN_DIR_WATCH": "1"
   }
   ```

3. 重開 Claude Desktop。之後改 `core/mods/` 的檔案，執行中的 session 會自動重新載入。

## 需求與限制

- 支援 mod 的 Claude Code / Claude Desktop（以 2.1.317 驗證）。
- 5h / 7d 只有訂閱帳號有，且要等第一次回應後才有資料；token 從 mod 載入後開始累計。
- `open-todos` 需要 PATH 上有 `node`（12 以上）。它只讀 `~/.claude/projects` 的 session 紀錄，不連網；
  掃描結果暫存在 `~/.claude/open-todos.cache.json`。只會列出用 Claude 待辦工具（TodoWrite / TaskCreate）建立的項目。
- 想隱藏某些專案：在 `~/.claude/open-todos-ignore.txt` 一行寫一個專案名稱、資料夾路徑或 session 編號開頭，`#` 開頭是註解。

## 開發

```bash
claude plugin validate core/mods/statusbar
claude plugin test core/mods/statusbar
```

`open-todos` 同理。這版的 mod 引擎在測試環境不提供 `$.state`，載入器也不接受把 `$` 傳進 import 的函式（例如 `update($, …)`），
所以兩個 mod 都把資料放在模組變數，用 `$.ui.invalidate('ui.render')` 要求重畫。
