# ESOAF Platform Conventions — Backend (C#)

Read this reference when the C# backend transaction is layered on Systex's ESOAF platform
(`SQLHelper`/`db.AddInParamater`, `JSONParser`/`oParser.JTokenString`, `FlowMessage`,
`SetErrorResponse`, `AuditingHelper` — seen across multiple bank-client backends). These are
conventions traced through actual usage across many existing transactions, not generic
ADO.NET advice.

## Match `DbType` to whether the value can ever contain non-ASCII text (confirmed)

`db.AddInParamater(name, value, dbType, cmd)` takes a `System.Data.DbType` that should match
the *content* of the value, not just "it's a string":

- **`DbType.AnsiString`** (→ `VARCHAR`) for any value that is always ASCII by construction:
  codes from a lookup/combo table (`compare_mode`, `status`, `auth_result`, `is_cust_info`),
  branch/unit numbers (`auth_unit_no`), employee numbers (`emp_no`), role IDs (`role_id`),
  policy/customer identifiers (`policy_seq`, `id_no`), year-month/date strings (`data_ym`,
  `application_date_s/e`, `pm_lastupdate_s/e`), audit stamps (`lastupdate`, `modifier`), and
  dynamically-named parameters built from these same kinds of values (e.g. `"policy_seq" + i`).
- **`DbType.String`** (→ `NVARCHAR`) only for values a user can type freely and that may
  contain Chinese text: memo/description fields (`confirm_memo`, `auth_result_desc`, a
  composed `new_memo` that embeds Chinese labels and/or those free-text values).

This is an established cross-transaction pattern (seen across many modules, not just one) —
when adding or reviewing an `AddInParamater`
call, follow the existing convention for that codebase rather than defaulting every parameter
to `DbType.String`.

**Why this matters, in both directions:**

- Leaving an ASCII-only code/ID/date parameter as `DbType.String` sends it to SQL Server as
  `NVARCHAR`. If the target column is `VARCHAR` (typical for these fields), SQL Server must
  implicitly convert one side of the comparison — this can silently turn an index seek into a
  scan on that predicate. Since the value is pure ASCII, switching it to `DbType.AnsiString`
  is safe regardless of the actual column type (no data loss either way) and removes the
  mismatch risk.
- Going the other way — assigning `DbType.AnsiString` to a value that might actually contain
  Chinese characters — risks silent data corruption: ADO.NET narrows the string to the
  connection's ANSI code page before sending it, which can replace unmappable characters with
  `?`. Never convert a memo/description/free-text parameter to `AnsiString` even if the
  current test data happens to be ASCII-only; check whether the *field*, not just today's
  value, can ever hold Chinese input.

## Combo "全選" (select-all) sentinel length depends on the code table (confirmed)

`$scope.requestComboBox`'s combo-set convention on the frontend (`["<codeType>", "*"|false,
"Asc"]`) controls whether the platform auto-inserts a "全選" entry, and if so its `code_id` is
padded to match that code table's code length (`"*"` for 1-char codes, `"**"` for 2-char codes,
etc.) — see `Systex.ESOAF.Web.Util.ComboBoxCombineHelper.CombineData`. A backend filter that
checks for "全選 selected, skip this predicate" must not hardcode an exact-length match like
`oParser.JTokenString("status") != "**"`, since that silently breaks if the code table's code
length ever changes or differs from what was assumed. Prefer a length-independent check:

```csharp
if (!String.IsNullOrEmpty(oParser.JTokenString("status")) && !oParser.JTokenString("status").Contains("*"))
```

This applies to every optional query-filter field sourced from a combo box with this
auto-insert convention (e.g. `auth_unit_no`, `compare_mode`, `compare_result`, `status`,
`auth_result` in query and export handlers) — not to sentinel checks on values the
frontend unshifts manually with a fixed single `'*'` placeholder (e.g. a dialog's own
"[請選擇]" default), which are safe as an exact match since that string is never
platform-padded.
