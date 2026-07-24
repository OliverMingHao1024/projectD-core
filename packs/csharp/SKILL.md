---
name: csharp
description: C# stack conventions for PG — ASP.NET Core Web API/backend services and console/background tools.
---

# C# Pack

適用專案類型：ASP.NET Core Web API / 後端服務、Console / 背景服務工具。
混用 .NET 8（新專案）與 .NET Framework 4.x（既有專案）— 動手前先確認目標專案
實際 target framework，不要假設一律是 .NET 8。

## 專案結構慣例

- **ASP.NET Core Web API**：Controllers/Endpoints、Services、Repositories 分層；
  依賴注入透過內建 DI 容器（`Program.cs` 的 `builder.Services`），不手動 new 服務。
- **Console/背景服務**：用 `IHostedService`/`BackgroundService`（.NET 8 專案）；
  .NET Framework 專案若沒有 Generic Host，維持既有結構，不強行升級架構。
- 一個方案（.sln）對應一個邏輯專案；共用邏輯抽成獨立 class library 專案，
  不要在多個可執行專案間複製貼上。

## 命名規則

- 類別/方法/屬性：PascalCase；區域變數/參數：camelCase；介面前綴 `I`。
- 非同步方法名稱以 `Async` 結尾，且回傳 `Task`/`Task<T>`，不要用 `async void`
  （除了事件處理器）。
- 檔名與類別名一致，一個檔案一個公開類別。

## Code Review Checklist

- [ ] 是否有 `async void`（事件處理器除外）？
- [ ] 例外處理是否只在邊界（controller/最外層）捕捉，內部邏輯不要吞例外？
- [ ] 資料庫查詢是否有 N+1 問題（EF Core 的 `Include`/投影是否正確）？
- [ ] DI 註冊的生命週期（Singleton/Scoped/Transient）是否符合實際用途？
- [ ] Web API 的輸入是否有做基本驗證（不信任前端傳來的資料）？
- [ ] Console/背景服務的長跑迴圈是否正確處理 `CancellationToken`？

## 測試慣例

- 既有專案沿用現有測試框架；新測試專案沒有既定選擇時使用 xUnit。
- 測試專案命名：`{ProjectName}.Tests`，鏡射被測專案的資料夾結構。
- 單元測試不連真實資料庫/外部服務；需要時用 mock（Moq）或 in-memory provider。
- 測試方法命名：`MethodName_Scenario_ExpectedResult`。
- 新增行為或修復 bug 時，先寫能描述期望行為或重現問題的失敗測試（Red），
  再做最小實作（Green），最後在測試保護下整理結構（Refactor）。
- 執行 Red 時要確認失敗原因正確；不是因專案無法編譯、DI 未配置或測試本身寫錯而紅。
- .NET Framework 專案若沒有測試基礎設施，不擅自導入新框架；先做可重現驗證，
  再向使用者提案是否建立最小測試專案。

## Build / Test 指令

```bash
# .NET 8 專案
dotnet build
dotnet test

# .NET Framework 專案（若無 dotnet CLI 支援，改用 MSBuild）
msbuild YourSolution.sln /t:Build
```

<!-- 以下項目待真正遇到具體專案時再補：NuGet 套件慣例、CI/CD pipeline、
     Entity Framework migration 流程、日誌/監控慣例。不預先假設內容。 -->
