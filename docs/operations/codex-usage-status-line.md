# Codex CLI 用量狀態列

- 狀態：active，2026-09-23
- 適用範圍：受信任的 `projectD-core` 專案
- 實測版本：Codex CLI `0.145.0`

## 目的

在 Codex CLI 的 TUI footer 顯示：

1. 目前模型與 reasoning level；
2. 本 session 累計 token；
3. context window 已用百分比；
4. 5-hour 額度剩餘量；
5. weekly 額度剩餘量。

刻意不顯示 session cost 或金額。

## 與 Claude Code `statusLine` 的差異

Codex 原生使用 `config.toml` 的 `tui.status_line`，不會將 JSON payload 傳給任意外部指令。
因此不需要 PowerShell／Bash statusline 腳本、UTF-8 BOM、`jq` 或 `settings.json`。

Codex 目前提供的原生欄位也與 Claude Code 不完全相同：

- `context-used` 顯示 context window 的已用百分比；`used-tokens` 顯示 session 累計 token，
  footer 沒有可組合成「context 已用 token／總 token」的自訂 formatter。
- `five-hour-limit` 與 `weekly-limit` 顯示**剩餘**額度，而不是已用額度；無法在
  `tui.status_line` 中套用 `100 - remaining` 的轉換。
- 額度與 reset 資訊只有在 Codex 從目前帳號取得 rate-limit snapshot 時才會顯示；
  欄位不可用時會自動省略。

需要完整 token 與最新額度資訊時，在進行中的 Codex CLI session 執行 `/status`。

## projectD-core 設定

專案設定位於 [`.codex/config.toml`](../../.codex/config.toml)：

```toml
[tui]
status_line = [
  "model-with-reasoning",
  "used-tokens",
  "context-used",
  "five-hour-limit",
  "weekly-limit",
]
```

Codex 只會為受信任的專案載入 `.codex/config.toml`。設定依序顯示可用欄位；額度欄位尚未
取得資料時不會留下空白 placeholder。

## 生效與驗證

1. 關閉目前的 Codex CLI session。
2. 從 `projectD-core` 目錄重新啟動 `codex`。
3. 確認 footer 出現模型、token/context 與可用的額度欄位。
4. 執行 `/status`，交叉確認目前模型、token usage 與 rate limits。
5. 如需互動調整 footer，可執行 `/statusline`；若要保留 repository 的一致設定，將選擇結果
   同步回 `.codex/config.toml`。

這是 project-level 設定，不會修改使用者層級的 `~/.codex/config.toml`，也不會影響其他
repository。
