---
name: rdl-report
description: 建立、修改或驗證 F25B 各專案（TBB／KGIB／CTCB／LBIB／TCB／TACB 等 ESOAF 家族）的 SSRS RDL 報表。先掃描目前專案的 `.rptproj/.rdl/.rds/.rsd`，依實際 schema、編碼、資料來源、共享資料集與鄰近報表選範本，再修改 RDL、參數化 SQL、專案登錄及 Word/Excel 樣張版面。當使用者說「做一張報表」「新增 RDL」「改報表版面」「檢查 RDL」或提到 rptsp_ 報表預存程序時使用。預存程序不存在時，若可用則先使用 db-migration skill；否則依專案既有 migration 流程提出建立方案。
---

# F25B SSRS RDL 報表製作

適用 F25B 各專案；報表伺服器在內網，**只能從 F25B 內網 / VPN 連線**。
Claude Code 或 Codex 產生/修改 RDL XML 與自檢；Report Builder 視覺編輯與上傳由使用者執行。

## 動手前：建立目前專案 profile

1. 從使用者指定路徑或目前 repo 根目錄開始；不要只靠銀行名稱猜報表目錄。
2. 執行本 skill 的 `scripts/Get-RdlProjectProfile.ps1`（路徑相對本 `SKILL.md`）：

   ```powershell
   & '<skill-folder>\scripts\Get-RdlProjectProfile.ps1' -ProjectRoot '<repo-root>' -IsSummaryOnly
   ```

3. 若找到多個 `.rptproj` 或多個報表目錄，比對 report membership、`TargetServerVersion`、`TargetServerURL`、`TargetFolder`；選擇會影響輸出時先讓使用者指定 active variant。
4. 需要挑範本或確認資料契約時，不加 `-IsSummaryOnly` 取得逐份 RDL 的 schema、參數、`dataSetContracts`、預存程序、頁面尺寸、Tablix 與子報表輪廓。預設排除 `.git/node_modules/packages/bin/obj/dist`；只有明確要檢查建置產物時才加 `-ShouldIncludeGeneratedArtifacts`。
5. 修改前回報：報表目錄、active `.rptproj`、目標 schema、範本、RDL/rptproj 編碼與 BOM、資料來源、共享資料集、預存程序慣例及未決項目。找不到報表 artifact 時停止並詢問正確專案路徑。

## 資料契約閘門

1. 依下列順序取得主資料集契約，並記錄每個 SP 參數、ReportParameter、結果欄位與型別的來源：
   1. 可查詢的預存程序 metadata 或 SQL/migration 定義。
   2. 呼叫端程式的參數 mapping、DTO 或既有執行介面。
   3. 已核准的需求、欄位規格或資料字典。
   4. 使用相同預存程序或同一交易契約的既有 RDL。
2. 鄰近報表、Excel/Word 範例值、預存程序命名與欄位中文標題只能用來提出候選，**不能證明資料契約**。不得據此發明參數名稱、結果欄位或型別。
3. 實作前列出「契約證據表」：RDL 參數、QueryParameter、來源、結果欄位、型別、驗證狀態。所有會進入 expression 或 QueryParameter 的項目都必須有來源。
4. 契約不完整時停止正式 RDL 實作並列出缺口；若使用者明確要先看版面，只能產生標示為 `draft` 的版面稿，不綁定臆測欄位、不得登錄 `.rptproj`，並回報不能進行 SSRS 資料驗證。
5. 預存程序不存在時，依 description 指定的 migration 流程建立或提案；不得只因名稱符合 `rptsp_<報表名>` 就視為存在。

## 通用實作規則

1. **以 profile 與可運作的鄰近報表共同決定 schema**。`TargetServerVersion` 只是線索；同一專案可混有 2010/2016 RDL。舊版伺服器不收 2016/01 直傳時，挑相容 schema 範本，或以 SSDT 建置降轉後交使用者上傳。
2. **複製目前專案最接近的既有 RDL 改**，不從零手寫 XML；先以同業務家族與 schema 選 XML／資料骨架，再分別比對專案框架、紙張方向、字型、邊界與 Tablix 結構。沒有單一範本同時符合時採下方分層選模，不做手工跨版轉換。
3. 分別保留範本 RDL 與 active `.rptproj` 的原始 XML encoding、BOM、namespace、換行與專案格式；除非使用者要求，不做正規化。
4. 主資料集遵循同專案既有 `CommandType` 與預存程序命名；新增的輔助 SQL 一律參數化（`@param`），禁止字串串接。
5. 資料來源與共享資料集引用必須沿用同專案鄰近報表；名稱引用與伺服器路徑引用都可能合法，不可互相猜換。
6. 固定參數組、字型、邊界跟隨同專案同型報表；紙張大小照需求或樣張指定，不得未確認就沿用範本值。
7. 新檔只登錄到 active `.rptproj` 的既有報表項目結構；先區分原本未列入的實體 RDL，不把既存差異誤報成這次修改造成。
8. 樣張（Word/Excel）為 zip+XML：解壓後解析 `word/document.xml` 或 `xl/worksheets/*`＋`sharedStrings.xml`，
   萃取欄位順序、欄寬、合併儲存格（→群組/跨欄表頭）、合計列、字型對齊，產出「樣張→Tablix 對照表」；
   樣張與文字需求衝突時**停下讓使用者裁決**。

## 分層選模與格式優先序

不要把「最接近的單一 RDL」視為所有層面的唯一答案。至少比較同業務家族、同 schema 與同版面型態的候選，再依序決定：

1. **XML／資料骨架**：同業務家族、schema、資料來源與共享資料集慣例。
2. **專案框架**：固定參數、PageHeader、標題來源、Rectangle、頁碼與列印資訊。
3. **頁面與排版**：方向、紙張、邊界、字型、字級、Tablix／Rectangle 結構。
4. **樣張局部幾何**：欄位順序、合併儲存格、欄寬比例、對齊與顯示文字。

若樣張與專案慣例衝突，保留樣張的內容語意，優先套用同專案同型報表的框架與視覺格式；把差異列出讓使用者確認，不可讓 Excel 列印設定默默覆蓋專案邊界、PageHeader 或標題規則。

## 專案別設定（動手前查齊，缺哪項問哪項，不要猜）

| 要查什麼 | 去哪查 |
|---------|--------|
| 報表專案路徑 | 該專案 repo 搜 `*.rptproj` |
| 伺服器 URL／目標資料夾／目標版本 | `.rptproj` 的 `TargetServerURL`/`TargetFolder`/`TargetServerVersion` |
| 共用資料來源／資料集名稱 | 同目錄 `.rds`/`.rsd`；既有 RDL 的 `<DataSourceReference>`/`<SharedDataSetReference>` |
| 預存程序 schema 與命名前綴 | 既有 RDL 的 `<CommandText>` |
| 固定參數組、字型、邊界 | 既有 RDL 的 `<ReportParameters>`、`<Style>` |
| rptproj 編碼 | 檔頭 XML 宣告的 `encoding` |

### 已知 TBB 線索（每次仍須由 profile 重查）

`D:\workspaces\TBB\TBB_Trade\src\RDL\TBS_LABS\依組織查詢報表\`
- 伺服器 `http://192.168.36.101/Reportserver/`、資料夾 `IBS_SA`；`IBS_SA.rptproj` 為 **Big5**
- 資料來源常見 `CTCBIBS_RS`，部分報表使用 `/資料來源/CTCBIBS_RS`；共享資料集常見 `Header|NowTime|Subject|Printer`，也有伺服器路徑形式
- 預存程序 `RPT.rptsp_{報表檔名}`；命名 `{程式代號}R{序號}.rdl`，子報表 `_1`/`_2` 後綴
- 固定四參數：`language`(=User!Language)、`reportuser`、`programno`(=Globals!ReportName)、`showheader`(True)
- 範本：清單型 `TR41005R01`、多參數 `TS12003R01`、子報表 `TR48001R01(+_1/_2)`（均 2016/01）；2010/01 骨架 `TA11003R01`
- 版面：內文新細明體 8pt、標題微軟正黑體、邊界 0.5cm、PageHeader 受 showheader 控制

### 已知 LBIB 線索（每次仍須由 profile 重查）

`D:\workspaces\LBIB\lbib_Trade_New\src\RDL\TBS_LABS\依組織查詢報表\`
- 主專案：`IBS_SA.rptproj`／`IBS_SA2019.rptproj`／`IBS_SA2022.rptproj`；抽樣約 228 個 `.rdl`，
  同目錄混用 2010/01 與 2016/01 schema；依同業務家族選骨架，不以 `.rptproj` 目標版本單獨決定
- 共用資料來源 `CTCBIBS_RS`（`.rds`，SQL Server 連線字串）；既有 RDL 常見引用路徑
  `/資料來源/CTCBIBS_RS`；未經明確要求不得變更伺服器/資料庫名稱、憑證或共用資料來源目錄
- 常見共用資料集：`Header`（在地化標籤，通常對應 `@language`）、`Subject`（報表標題/主旨，通常對應
  `@language`／`@programno`）、`NowTime`（報表產生時間）、`分行業績清單`、`分行資料集`、`區域業績清單`、
  `報表共用變數`、`報表基本資訊`；引用時 `SharedDataSetReference` 與 `QueryParameters` 對應須同時保留完整
- 固定參數通常為 `language`、`reportuser`、`programno`、`showheader`；預設值應由同型報表 read-back，不自行改寫。
  常見業務篩選參數：`branch_no`、`is_print`、`rpt_ym`、`is_mask`、`insco_no`、`rpt_ym_end`、`dataDate`、
  `chan_code`、`prod_type`、`month`、`rpt_ym_beg`、`prod_code`——新增/變更參數時，`<ReportParameters>`、
  dataset `<QueryParameters>`、`.rsd` 的 `<DataSetParameters>`、SQL `<CommandText>` 的 `@param`、
  `Parameters!name.Value` expression 五處都要同步更新
- 常見專案框架為 PageHeader＋Rectangle，標題由 `Subject.rpt_name`／`rpt_id` 提供；內文常用標楷體，標準邊界
  常見 0.5cm；常見頁面尺寸含 `29.7cm x 42cm`、`30cm x 44cm`、`21cm x 29.7cm`、`30cm x 29.7cm`、
  `42cm x 29.7cm`，多為寬版橫式、密集 Tablix 版面，改寬度前先比對 Body/ReportItems 寬度、頁寬與邊界，
  避免超出可印寬度產生空白頁
- 21xx 業務骨架可先比較 `TA21101R01`；A4 橫式與 0.5cm 邊界比較 `TA21003R01`；A4 橫式、PageHeader、標楷體
  12/16pt 比較 `TA32040R01`；其他常見報表代碼範例：`TA61001R01`、`TA32031R09_1`、`TS14105R03`、
  `TRL3003R01`——`_1`/`_2`/末位數字後綴常代表報表變體，改動前先看同系列檔案
- XML 檔宣告編碼通常為 `utf-8`；部分專案檔以錯誤主控台編碼讀取會出現亂碼中文，判斷編碼與內容前優先
  用 XML 解析或正確編碼開啟，不要單憑主控台顯示下結論
- 上述檔案只代表不同格式層的候選，不可用來臆測新報表的 SP 參數或結果欄位

（本節於 2026-07-30 併入原 `lbib_Trade_New/.agents/skills/ssrs-rdl/references/lbib-rdl-patterns.md` 的驗證內容；
該重複的 `ssrs-rdl` skill 與 `~/.codex/skills/ssrs-rdl` 副本、`oai-core/.agents/skills/ssrs-rdl` 失效
junction 已一併刪除，`lbib_Trade_New` 的 `CLAUDE.md`/`AGENTS.md`/`GEMINI.md` 已改指向本 skill。）

## 自檢（回報附證據）

- 重新執行 profile；所有 RDL XML 載入成功，修改檔 namespace 等於所選範本 schema
- 修改前後 read-back：RDL/rptproj encoding、BOM、換行與未要求的專案設定未變
- 新報表已列入 active `.rptproj`；既存 unlisted reports 只警告，不順手修改
- 參數在 SQL、QueryParameters、ReportParameters 與 expressions 間一致；Body 寬度加左右邊界不超過 PageWidth
- 契約證據表中的參數與欄位全部可追溯；`dataSetContracts` 與實際 RDL read-back 一致，沒有未標示的推測項目
- 有樣張：附逐欄對照表（欄名、順序、群組、合計、對齊）
- **本地無 SSRS 不得宣告完成**：Claude Code 或 Codex 必須標「部分完成」＋下方上傳 checklist 交使用者驗證

## Report Builder 上傳（使用者執行）

依版本選工具（≤2014：Report Builder 3.0；2016+：Microsoft Report Builder）→ 連線報表伺服器開啟 .rdl
→「另存新檔 → 報表伺服器」或 Web Portal 上傳 → 檢查資料來源/共用資料集綁定 → 入口網站預覽
（參數面板、資料、分頁與合計）。

## 紅線

- `bin\Debug` 降版產物僅可讀取並交付上傳，不直接編修或納入版控；不修改共用 `.rds`/`.rsd` 與伺服器端共用物件，除非使用者明確要求
- 不改 rptproj 編碼；上傳/覆蓋伺服器上既有報表一律由使用者執行與逐次確認
