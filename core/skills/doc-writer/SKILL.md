---
name: doc-writer
description: Document code, modules, features, or APIs; Traditional Chinese unless asked otherwise.
---

# Doc Writer

Write in **繁體中文** by default. Use English only when the user asks.

## 1. Read the target first

- Understand what it does, not just what it looks like.
- Find inputs, outputs, side effects, and error conditions.
- Note constraints and dependencies that are not obvious.

## 2. Pick the format

| Target | Format |
| --- | --- |
| Function or method | Doc comment above it |
| Module or class | Header block: purpose, dependencies, usage |
| Feature or transaction | Markdown document (Obsidian or README) |
| API endpoint | Table: method, path, request, response, error codes |

## 3. Write it

- Explain **why**; the code already shows what.
- Record constraints the signature hides (for example 「必須先呼叫 init() 才能使用此方法」).
- List side effects: state changes and external calls.
- List errors: which exceptions, and when.
- Keep it short. If the explanation is longer than the code, simplify the code instead.
- Use the language's own doc-comment style (`/** */` for TS/JS/Java, `///` for C#)
  and the repository's existing conventions.

Example (C#, ESOAF):

```csharp
/// <summary>
/// 處理基金申購交易。FunctionType 格式：Query:QueryFundList
/// </summary>
/// <param name="flowMessage">包含 TIA 請求資料的流程訊息</param>
```

## 4. Feature document shape

```markdown
## [功能名稱]

**用途**：一句話說明這個功能做什麼。

**涉及檔案**：主要相關檔案路徑。

**資料流**：從觸發到完成的資料流向。

**注意事項**：不明顯的限制或依賴。
```

For governed Vault notes (issues, dev-logs, specs), use `vault-doc` instead.

## Source

Moved from the retired `oai-core/shared-skills` into projectD.
