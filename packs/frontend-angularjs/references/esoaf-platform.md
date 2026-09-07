# ESOAF Platform Conventions

Read this reference when the AngularJS 1.x application is built on Systex's ESOAF
platform (`eSoafApp`, `BaseController`, `$scope.tioa`, `e-smart-*` directives — seen
across multiple bank client codebases, e.g. CTCB `New_CTCB_Web` / legacy `WMIAS/web/eSoafWeb`).
This is a proprietary framework layered on top of AngularJS 1.x plus a legacy `ngGrid`
(not `ui-grid`), not covered by generic AngularJS knowledge, and it is easy to misread as
following ordinary directive/CSS/DI conventions when it doesn't. Every transaction
controller starts with `$controller('BaseController', { $scope: $scope })` — this mixes
~150 `$scope.xxx` properties directly onto the caller's own scope object; it is not
scope-inheritance and not class inheritance, just a shared-object mixin applied first, so
anything the transaction controller assigns after that line silently overrides same-named
BaseController properties.

Findings below are marked **(confirmed)** when traced through actual framework source, or
**(unconfirmed)** when inferred from usage patterns without being able to verify the
underlying implementation — treat unconfirmed items as a strong lead, not a fact.

## Module registration and lazy loading (confirmed)

`eSoafApp.controller` / `.service` / `.factory` / `.directive` are **not** the standard
chainable `angular.module()` methods — `app.js`'s `.config()` block reassigns them to call
`$controllerProvider.register` / `$provide.service` / `$provide.factory` /
`$compileProvider.directive` directly, using references captured in closure at config time.
Because those references never go away, `eSoafApp.controller('X', fn)` still works **after**
the app has bootstrapped — this is what makes per-transaction lazy-loading possible at all
(each transaction's `.js`+`.html` pair loads on demand via `withLazyModule`/RequireJS, and
the HTML's contents get stuffed into `$templateCache`). In standard Angular, registering a
controller after bootstrap throws. If you ever see `eSoafApp._controller` etc. (underscore
prefix), that's the original unmodified module method kept as an escape hatch.

The grid library is the old, abandoned **`ngGrid`**, not `ui-grid` (explicitly commented out
elsewhere as "doesn't support IE8"). Expect `row.entity`, `row.getProperty('field')`,
`COL_FIELD`, `col.colIndex()`, `$gridScope`/`$gridServices` — not `ui-grid`'s `gridApi`/`field`
conventions.

## `showDialog` opens a scope **three levels down**, not the same scope (confirmed)

`$scope.showDialog(sTxn, scope, oCallback)` calls `ngDialog.openConfirm({ scope, ... })`.
Reading `ngDialog`'s own source: `openConfirm` does `options.scope.$new()` once, then the
`open()` it delegates to does **another** `.$new()` on that result, and finally the dialog's
own root `ng-controller="XxxController"` (present in every dialog's HTML) creates a **third**
child scope via Angular's native `ngController` directive. So the dialog controller's `$scope`
is `callerScope.$new().$new().$new()` — three prototypal hops below the screen that opened it,
not a shared object.

This is why the established convention (`$scope.args = angular.copy(oRow); $scope.args.Type =
"edit";` right before `showDialog`, then `$scope.tioa = angular.copy($scope.args)` inside the
dialog controller) works at all: reading `$scope.args`/`$scope.cbData` from the dialog is
ordinary prototypal **read-through**, not identity. It also means:

- If a dialog ever writes `$scope.args.someField = x` **without** copying first, that mutates
  the same object the parent screen still holds — silent cross-contamination. The codebase
  avoids this only by convention (`angular.copy`), not by anything structural.
- `$scope.confirm(value)` and `$scope.closeThisDialog()` are injected by **`ngDialog` itself**
  (not BaseController) onto the dialog's scope — visible via the same prototypal read-through.
  `confirm(value)` **resolves** the `showDialog` promise (`oCallback(true, value)`);
  closing without confirming **rejects** it (`oCallback(false, reason)`). The established
  success pattern is to call **both, in this order**: `$scope.exitDialog(); $scope.confirm(true);`
  (close first, then resolve).
- `showDialog` uses `openConfirm`, so `closeByEscape`/`closeByDocument` default to **false** —
  every ESOAF dialog can only be dismissed by an explicit button, never Escape or overlay-click.
- `preCloseCallback: 'preCloseCallbackOnScope'` is passed on every dialog open but is a
  **no-op unless you define `$scope.preCloseCallbackOnScope`** yourself — nothing in the
  platform defines it by default, so don't assume dialog-close interception exists already.
- The internal supervisor/host-credential dialogs (`bSupvVerify`/`bRequireHost` on `sendRecv`)
  open **without** forwarding any scope at all — they always descend from `$rootScope`, so
  they cannot see transaction-local data. This is asymmetric with `showDialog`'s explicit
  scope-forwarding.

## `e-smart-tag`: the load-bearing input-masking directive

```html
<input class="eControl eField" e-smart-tag editMask="D1" data-ng-model="tioa.date_beg"
    lower-than-or-equal="{{tioa.date_end}}" />
```

Five attributes drive its behavior — `editMask` (defaults to `dataformat` if unset) wins over
everything else once set:

| `editMask` | Meaning |
|---|---|
| `D1` | 西元日期八位 `yyyyMMdd` |
| `D2` | 西元日期六位 `yyyyMM` — use for year-month range filters instead of native `<input type="month">`, whose model is a JS `Date` needing manual `.getFullYear()`/`.getMonth()` conversion and manual invalid-range highlighting; `D2` manages the string format and highlight itself |
| `C1` | ROC-era 7-digit date |
| `T1`/`T2` | Time `HH:mm` / `HH:mm:ss` |
| `N1`–`N4` | Money; `N2`/`N4` add thousands separators (paired with `dataext`/`datafrac` for case/decimals) |
| `A1`/`A2`/`A3` | Delegates to `validateService.validateData_PID`/`CID`/`FID` (Taiwan national ID / business unified ID / foreign resident ID) |
| `I1` | Custom validation — calls the directive's own `check` expression with `{oValue}` |

Other attributes: `dataformat` (keystroke-level character filter: `N`=digits, `$`=money
chars), `edittype` (2-char pad spec, e.g. `L0`/`RS` — first char = pad direction, second =
pad character), `dataext` (`U`/`L` case transform).

Gotchas:

- Range constraints go through `lower-than-or-equal`/`lower-than`/`greater-than-or-equal`/
  `greater-than` attributes (separate directives, `eCompare.js`), which do a **plain string
  comparison** after stripping `/` — only numerically correct for equal-length, zero-padded
  values (exactly `yyyyMMdd`/`yyyyMM`). Don't reuse on unpadded numeric fields.
- On blur it force-calls `ngModelCtrl.$setDirty()` specifically so
  `.eField.ng-dirty.ng-invalid { background: red }` can ever fire — a field that's invalid but
  never focused stays visually clean (see `dataIsValid` below).
- Depends on several bare global functions (`getToday`, `padLeft`, `padRight`) — see "Global
  bare functions" below.
- Write the attribute as `editMask` (no dash). Angular normalizes `edit-mask` to
  `attrs.editMask` (capital M), but the directive reads `attrs.editmask` (all-lowercase, as
  the browser lowercases plain HTML attribute names) — using the dashed form silently means
  the mask is never picked up, no error, just wrong formatting behavior.
- Prefer this over `e-date-picker` for plain date/year-month inputs; reserve `e-date-picker`
  for when a calendar-dropdown UI is actually wanted.

## `e-date-picker` width is an HTML attribute, not a CSS class

The directive uses `replace: true` and builds its own template, splicing `attrs.width`
directly into an inline style on the real `<input>`:

```js
// eDatePicker.js
style="width: ' + attrs.width + '; display: inline-block;"
```

A CSS class on the wrapping element (`<div e-date-picker class="myWidth">`) never reaches
that inner input — it silently falls back to the shared `[editMask="D1"]{width:90px}` rule
instead (inline style beats stylesheet specificity, but only when the inline value is
*valid*; omitting `width` produces `style="width: undefined;"`, which the browser ignores,
falling through to that same 90px default). Set width as a literal attribute instead:
`<div e-date-picker width="140px" ng-model="..." />`. It also force-clears
`ng-invalid-required` on blur unconditionally (a manual class removal, not an actual
validity change) — a required-but-empty date field can look valid right after blur even
though the model still isn't.

## Server communication (`$scope.sendRecv` / `BaseController`)

`$scope.sendRecv(sTxnCode, sFuncType, sFuncCode, oTIA, oCallbackFunc, oUploader, bSupvVerify,
oSupvInfo, bRequireHost)` is the core RPC call. Wire request shape:

```
{ Header: { TxnCode, FuncType, FuncCode, UserID, UserRole, OrganizationID, LangType },
  Body:   { Info: {...}, Before: {}, After: {}, Data: oJSON } }
```

POSTed to `MsgService.svc/rest/SendRecv`; the response's `.d` field is itself a JSON string
requiring a second `JSON.parse`. `RetLevel === "Error"` is the `isError` your callback gets.

- **(confirmed)** Before sending, `TransTIOA` replaces every **top-level Array property** of
  your payload with a `[headerRow, ...valueRows]` shape (`GRID2JSON`). If that array's
  elements aren't plain objects, the "value row" loop only pushes rows where
  `typeof item === "object"` — an array of primitives becomes a header row with **zero data
  rows**. Don't pass primitive arrays in a `sendRecv` payload; wrap them as `{value: x}`
  objects first if they need to survive the trip.
- **(confirmed)** If the session times out (`sysInfoService.isTxnTimeout`), your callback
  **never fires** — there's an early return with just a "session expired" popup, so a
  callback that "randomly" doesn't run is often not a bug in your code.
- `$scope.requestComboBox(oJSON, cb)` — each key of `oJSON` becomes a combo-set name; each
  value is a 3-element convention array, e.g. `["985", "*", "Asc"]`
  **(unconfirmed exact meaning of positions 2/3** — every transaction uses this shape
  uniformly, but the precise semantics weren't traceable from front-end code alone).
- `$scope.JSON2GRID`/`JSON2COMBO`/`OBJ2COMBO` convert the `[headerRow, ...rows]` wire shape
  to/from `[{col:val}]`/`[{code_id,code_desc}]` — both **skip the first row as a header**.
- `$scope.exportFile(...)` does **not** stream the file over the same `$http` call — on
  success it opens a second, separate GET to `ExportFile.aspx?GetFile=1` relying on
  server-side session/temp-file state from the first POST. Anything that clears session state
  between the two calls breaks downloads with no visible client-side error.
- `$scope.getMicroFrontToken`/`getMicroFrontCredential` return a **native `Promise`**, not
  `$q` — `.then()` callbacks run outside the digest cycle; touch scope-bound data inside one
  and nothing updates until an unrelated digest fires, unless you force `$apply`/`$timeout`.

## Validation: `dataIsValid` is a jQuery DOM scan, not a form-object check

`$scope.dataIsValid(sBlock, ...)` does **not** check `$scope.form.$valid`. It jQuery-selects
`.ngdialog <sBlock>` then `div.txn-pane>div.tab-content>div.tab-pane.active <sBlock>`
(hardcoded DOM structure) and looks for Angular's own `.ng-invalid-required` /
`.ng-invalid-lower-than-or-equal` (etc.) / generic `.ng-invalid` classes, in that priority
order — checking `.ng-invalid` alone, **without** requiring `.ng-dirty`.

This creates a real trap: the CSS that visually reddens a field requires **both**
`.ng-dirty.ng-invalid`, but `dataIsValid` only checks `.ng-invalid`. A required field the user
never clicked into can fail `dataIsValid()` and pop an error message while **no field on
screen looks invalid** — nothing is dirty yet. `e-smart-tag`'s forced `$setDirty()` on blur
(above) exists specifically to narrow this gap for fields the user did interact with; it does
nothing for fields never focused at all.

**The `ng-required="v.xxx"` pattern is not a BaseController feature** — it's a per-transaction,
copy-pasted convention (`$scope.v = {}`, reset before validating, individual transactions set
`v.fieldName = true` for whichever fields are currently mandatory). Also note:
`.eField[ng-required="true"]` in the shared CSS is a literal attribute-value selector — it
only matches a hardcoded `ng-required="true"` in markup, **never** the dynamic
`ng-required="v.xxx"` form, so the "required field" blue-border visual cue is effectively dead
for the majority of conditionally-required fields using this convention.

## Paging and auth gotchas

- `$scope.pageMaxRow` is a **hardcoded client-side `50`**, not derived from any server
  response — if a transaction's backend actually pages at a different size,
  `hasLastPage()`/`hasNextPage()` will misjudge silently.
- `$scope.lastPageQuery`/`nextPageQuery` default their callback to `$scope.queryTxn`, which
  **does not exist in BaseController** — it's a bare naming convention. Transactions that name
  their query function anything else (very common, e.g. `Query_Data`) will throw
  `$scope.queryTxn is not a function` if you call paging without passing the callback
  explicitly.
- `$scope.hasAuth(sBtnAuthName)` does `$scope.btnAuth.indexOf(sBtnAuthName) >= 0` — `btnAuth`
  is one string, checked with substring match, not an array/bitmask/object of booleans.
- `$scope.pageCheck` requires each grid row to carry a `rank` field (absolute row number
  across the whole result set) and throws silently (caught, no message shown at all — not even
  "0 rows") if the result set is empty.

## Global bare functions — not injected, not mockable via DI

Defined as plain top-level `function name(){}` in `eSoafWebPlatform.js`/`datetimeUtil.js`
(no IIFE), so they attach to `window` and are callable unqualified anywhere, including inside
directive closures, with **no dependency-injection footprint** — skimming a function's
injector-argument list will not reveal that it depends on these:

`getToday()`, `getTimeNow(n)`, `padLeft`/`padRight`, `endsWith`, `S2M` (money formatter — a
**second, independently-maintained copy** of this exact name also exists as a private closure
inside `eSmartTag.js`), `dataMaskFormat`, `detectBrowser`, `QueryString`, `getCookie`
(duplicates what the already-loaded `ngCookies` module would provide), `closeMe`, `logout`,
`beep`, `debugAngular`, and a monkey-patched `Date.prototype.Format(fmt)`. A unit-test harness
that only mocks Angular services will miss all of these.

## Known dead/orphaned files — don't copy patterns from these

Confirmed absent from `MainPage.html`'s script includes and unreferenced anywhere else in the
tree (verify the same way in a new ESOAF project before trusting this list — it was confirmed
for one specific CTCB checkout, not guaranteed identical elsewhere):

- `eSmartSelect2.js` — old native-`<select>` implementation, superseded by `eSmartSelect.js`.
  **Registers the same directive name** (`eSmartSelect`) — would collide if ever loaded
  alongside the live one.
- `ngJqGrid.js` — superseded by `ngGrid` itself (author's own comment says so).
- `scheduler.js` (`dhxScheduler`/`dhxTemplate`) — dhtmlxScheduler wrapper, no remaining usage.
- `imgFileUploadService.js` (+ co-located `fileModel` directive) — superseded by
  `eFileUpload.js`/`FileUploader`; explicitly marked "不再使用" (no longer used) and was an
  IE8-only fallback.
- `enterAsTab.js`: the **registered** directive `enterAsTab` is an intentional no-op
  (`return {}`) — disabled platform-wide because it broke multi-tab-pane transactions. The
  real implementation sits under the unreferenced name `enterAsTab1`. Every transaction's
  `<form enter-as-tab>` attribute is therefore vestigial markup that does nothing; don't
  assume it provides Tab/Enter focus-advance behavior.

## Naming conventions

- `assets/txn/<TXNCODE>/<TXNCODE>.html`+`.js` is the main screen (`<TXNCODE>Controller`).
  `<TXNCODE>Sxx.html`/`.js` are secondary dialogs, numbered **sequentially starting at `S02`**
  (the unsuffixed main screen is implicitly "S01" — there is never a bare `S01` file). The
  number carries **no fixed meaning** — `S02` isn't always "edit," `S03` isn't always
  "confirm"; different transactions use the same numbers for different purposes.
- A mail-template `functionID` string can coincidentally match an unrelated screen's filename
  (seen: a notification `functionID` of `"PS41016S03"` matching a screen also named
  `PS41016S03.html` that has nothing to do with that email) — these are different namespaces;
  don't infer one from the other.

## Label alignment: `eTitle` + a per-column fixed-width class, never hand-padded spaces

`.eControl` only sets `display: inline-block` — no width, no text alignment. Alignment
comes from adding `.eTitle` (`text-align: right`) plus a page-scoped fixed-width class keyed
to the field's *column position* (not to that label's own text length):

```html
<style>
  .PS41016 .eLbl1 { width: 170px; }
</style>
<p class="eControl eTitle eLbl1">AO/經攬人所屬單位：</p>
<p class="eControl eTitle eLbl1">比對類型：</p>
```

Legacy screens in this codebase sometimes hand-pad the label text with full-width spaces
instead (`比對年月　　　：`). That approach breaks as soon as a longer label appears in the same
column — without `eTitle`, `eControl` neither right-aligns nor forces `white-space: nowrap`,
so the box wraps mid-label instead of aligning, and the next field on the row shifts out of
column with the row above it. Size the shared width class for the longest label at that
column position, add `white-space: nowrap` as a safety margin against estimation error, and
never fake alignment with spaces baked into the text.

Whether a start/end pair renders as two independently-labeled fields
(`XX（起）：[field] XX（迄）：[field]`) or one label with a combined range
(`XX：[field] ~ [field]`) is a spec/product decision, not a technical constraint — both are
established patterns in this codebase; check what the transaction's spec actually calls for.
