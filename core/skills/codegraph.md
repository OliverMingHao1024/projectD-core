---
name: codegraph
type: external-tool-reference
source: https://github.com/colbymchenry/codegraph
---

# CodeGraph

外部工具，不是重寫的內容——安裝/更新請直接參考原專案，這裡只記錄「何時用、怎麼用」。

## 是什麼

Rust 核心的本地程式碼知識圖譜索引工具。indexed 後可透過 MCP 工具或 CLI 快速回答
「這個 symbol 在哪、呼叫路徑是什麼」之類的問題，比 grep 更準（能跟到動態派發）。
支援 Claude Code、Codex、Cursor、Gemini、OpenCode 等多種 agent。

## 何時使用

- 專案根目錄存在 `.codegraph/` 時，理解/定位程式碼**優先用 codegraph**，而不是先 grep/find。
- 若不存在 `.codegraph/`，代表使用者尚未替該專案建索引 —— 跳過，不要自作主張安裝。

## 怎麼用

- MCP 工具（若已掛載）：`codegraph_explore`，帶 symbol 名稱或問題即可拿到原始碼＋呼叫路徑。
- Shell（一定可用）：`codegraph explore "<symbol 名稱或問題>"`。
- 若工具被列為 deferred，先用工具搜尋以名稱載入。

## 安裝（依專案需要，不預先裝）

```bash
# macOS / Linux
curl -fsSL https://raw.githubusercontent.com/colbymchenry/codegraph/main/install.sh | sh
# Windows (PowerShell)
irm https://raw.githubusercontent.com/colbymchenry/codegraph/main/install.ps1 | iex
# 或已有 Node
npm i -g @colbymchenry/codegraph
```

安裝與版本升級以官方 repo 為準，本檔案不重複維護指令細節。
