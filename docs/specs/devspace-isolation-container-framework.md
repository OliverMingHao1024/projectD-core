# DevSpace Isolation Container Framework

## Problem

`docs/adr/0015-isolate-ai-agent-mcp-server-execution.md` 要求任何有檔案讀寫/shell
執行能力的 AI-agent MCP server（例如 DevSpace）必須先跑在 rootless container、單一
明確 repo bind-mount、不掛 Docker socket、egress 強制走網域白名單 proxy——這是重新
啟用 DevSpace 的硬性前提，源自 2026/07/01 Offense 335495 事件（`devtunnel
--allow-anonymous` 把 DevSpace 高權限能力暴露到公開網路）。目前這個前提完全沒有
落地，DevSpace 因此一直被擋在門外。

## Outcome

一套跟具體 DevSpace 軟體無關的通用隔離骨架——Dockerfile、docker-compose 網路拓樸、
squid egress 白名單、驗證腳本——先把「容器能不能真的擋住 host 憑證外洩」這件事做
出來並證明，之後才把實際 DevSpace 實作接進來。

## User stories

1. As a projectD-core 維護者，I want 一個跟 DevSpace 具體實作解耦的隔離骨架，so
   that 之後不管選哪套實作，都能直接套用，不必重做隔離設計。
2. As a projectD-core 維護者，I want 有一支腳本能實際證明「容器裡的 shell 碰不到
   host 的 SSH/雲端憑證」，so that ADR 0015 的驗收標準不是空話，是可重複執行的
   證據。
3. As a projectD-core 維護者，I want 誠實知道 Windows Docker Desktop 上「rootless」
   實際做到什麼程度，so that 我不會誤以為滿足了 Linux 原生 rootless daemon 才有的
   保證。

## Acceptance criteria

- [ ] `docker compose up` 能啟動兩個服務：`devspace`（佔位容器）與
      `egress-proxy`（squid）。
- [ ] `devspace` 服務容器內程序以非 root user 執行（Dockerfile `USER` 指令，UID
      10001，非 0）。
- [ ] `devspace` 服務套用 `no-new-privileges:true`，`cap_drop: [ALL]`，不加回任何
      capability。
- [ ] `devspace` 服務只 bind-mount 一個明確指定的 host 路徑（`.env` 的
      `DEVSPACE_REPO_PATH` 指定），沒有第二個 volume。
- [ ] `devspace` 服務不掛載 Docker socket。
- [ ] `devspace` 所在 Docker network 標記 `internal: true`（無路由到外網）；
      `egress-proxy` 另接一個有出網能力的 network，是 `devspace` 唯一可能出網的
      路徑。
- [ ] squid 白名單預設只含一筆**驗證專用**的測試網域（`example.com`），並在檔案與
      README 顯著標記「這是驗證用 placeholder，選定實際 DevSpace 軟體後要替換成
      真正需要的網域」。
- [ ] 驗證腳本執行後回報五項證據，任一失敗即整體判定失敗：
      1. 容器內找不到常見 host 憑證路徑（`.ssh`、`.aws`、`.kube`）
      2. 容器內找不到 Docker socket
      3. 容器對外部主機的直接連線（不經 proxy）失敗——證明 internal network 真的
         沒有出網路由
      4. 透過 `egress-proxy` 對白名單外網域的請求被 squid 拒絕（403 或等效拒絕）
      5. 透過 `egress-proxy` 對白名單內網域（`example.com`）的請求成功
- [ ] 驗證腳本可重複執行、無需人工判讀輸出，exit code 0 = 全過，非 0 = 指出是哪
      一項失敗。
- [ ] README 明確寫清楚：這是 Docker Desktop for Windows（WSL2 backend）上的隔離，
      不是 Linux 原生 rootless dockerd；這裡做到的「rootless」是容器內程序以非
      root 執行、no-new-privileges、capability drop 的組合，不是「容器逃逸也不
      影響 host」等級的保證。

## Implementation decisions

- 目錄位置：新增頂層目錄 `containers/devspace-isolation/`。
- 內容物：
  - `Dockerfile`——`debian:bookworm-slim` 基底（之後接實際 DevSpace 軟體時相容性
    風險較低），`USER` 非 root（UID 10001），佔位程序只 `sleep infinity`，不含任何
    shell-execution 服務對外暴露。
  - `docker-compose.yml`——`devspace` + `egress-proxy` 兩服務；`devspace` 的
    network 標記 `internal: true`；`egress-proxy` 同時接 internal network 與一個
    有出網能力的 bridge network，是唯一出口。
  - `squid/squid.conf` + `squid/allowed-domains.txt`——白名單機制，預設只有
    `example.com` 這筆驗證用項目。
  - `scripts/verify-isolation.ps1`——跑在 host，透過 `docker compose exec` 進容器
    執行實際檢查指令，單一腳本完成全部五項驗證，不另外寫容器內版本。
  - `.env.example`（`DEVSPACE_REPO_PATH` 佔位值）；`.env` 本身不進版控。
  - `README.md`——說明用途、Windows rootless 的實際範圍、如何之後接入具體
    DevSpace 軟體、如何替換 squid 白名單。
- 跟今天稍早完成的 `scripts/governance-command-policy-hook.ps1`（擋下工作機器/
  工作 repo 呼叫 DevSpace 工具）是互補、不同層的防護：command-policy-hook 決定
  「誰能連進來」，這個容器框架決定「連進來的人能拿到什麼」，兩者都要，不互相
  取代。

## Testing decisions

- 驗證腳本本身就是測試，不另外包一層 pytest/contract 測試——它需要真的啟動 Docker
  容器，是需要 Docker daemon 存在才能跑的整合測試，不放進一般 `pytest tests/` 的
  預設執行路徑（避免沒裝 Docker 的環境測試失敗）。
- 手動驗收流程：`docker compose up -d` → 執行驗證腳本 → 確認五項全過 →
  `docker compose down`。
- 之後若要接進 `pytest`，比照既有 `shutil.which("pwsh")` 的 skip 模式，用
  `shutil.which("docker")` 判斷可用性。

## Out of scope

- 不在本次選定或安裝實際的 DevSpace 軟體本身。
- 不修改 `docs/adr/0015-isolate-ai-agent-mcp-server-execution.md`——本次是落地
  實作其要求，不是修訂決策；先前討論過的「放寬到 OAuth+allowlist」ADR 0017 草稿
  是另一條路徑，本次選擇照 ADR 0015 原文落實，兩者不同時進行。
- 不處理 Microsoft Dev Tunnel / OAuth 相關設定。
- 不做 Linux 原生 rootless dockerd 遷移或 Hyper-V VM 隔離（ADR 0015 已評估並
  排除）。
- squid 白名單的實際生產網域清單不在本次填入。

## Assumptions and open questions

- 「host 憑證讀取被拒絕」是透過刻意不 bind-mount 這些路徑來驗證「容器本來就看
  不到」，不是「掛了但用權限擋住」；驗證腳本用來確認這個設計沒有被意外破壞
  （例如未來有人手滑加了一個掛載）。
- squid 白名單預設放 `example.com` 這筆驗證用項目，而非完全空白——理由是驗收
  條件第 5 項需要至少一個「允許成功」的案例可測，完全空白名單無法驗證允許路徑
  本身有沒有正確運作。

## Addendum: 接入真實 DevSpace 軟體（post-implementation）

骨架驗證通過後，接續把 [Waishnav/devspace](https://github.com/Waishnav/devspace)
（`@waishnav/devspace`，npm、MIT）接進 `devspace` 服務，取代原本的佔位程序。過程中
實測發現三個跟原始骨架假設不符的地方，都已修正並重新驗證：

1. **版本落差**：npm 上實際安裝的是 `1.0.8`，這個版本走**舊式環境變數設定**
   （`HOST`、`PORT`、`DEVSPACE_ALLOWED_ROOTS`、`DEVSPACE_OAUTH_OWNER_TOKEN`、
   `DEVSPACE_PUBLIC_BASE_URL`），完全不讀取 GitHub main branch 文件描述的
   `config.jsonc`/`DEVSPACE_CONFIG_DIR` 系統（那是尚未發布到 npm 的較新設計）。
   `docker-entrypoint.sh` 因此改成直接 `export` 這些環境變數，不寫設定檔。
2. **`DEVSPACE_PUBLIC_BASE_URL` 空字串會讓 1.0.8 直接崩潰**（丟出 `Invalid URL`，
   即使 schema 文件說這個值可以是 `null`）。修法：compose 對外的變數名稱改叫
   `DEVSPACE_ISOLATION_PUBLIC_BASE_URL`（我們自己的中介變數），只有在使用者真的
   填了 `.env` 的 `DEVSPACE_PUBLIC_BASE_URL` 時，entrypoint 才會把它匯出成
   devspace 認得的確切變數名稱；否則容器環境裡完全不存在這個變數名稱。
3. **`internal: true` 的網路不支援 Docker port publish**（不只是連得到被擋，是
   `docker port` 直接回傳空、host 完全無法建立連線），這跟容器內部服務綁定
   哪個位址無關。修法：新增一個獨立的 `port-forward` 服務（`socat`，非 root、
   capability 全 drop、read-only），同時掛在 `devspace-internal` 與
   `devspace-egress` 兩個網路，只做 `host:7676 → devspace-isolated:7676` 的
   單一轉發，不具備 `devspace` 容器擁有的任何能力（無檔案存取、無 shell），
   因此它跨到非 internal 網路不會削弱 `devspace` 本身的隔離。

修正後，`verify-isolation.ps1` 六項全過，第六項（`devspace-mcp-endpoint-responds`）
回報 `http_status=401`——這是 MCP endpoint 要求 OAuth 核准的正確行為，不是失敗。

若未來把安裝版本升級到支援 `config.jsonc` 的版本，`docker-entrypoint.sh` 需要
重新檢視，可能要改回寫設定檔而非純環境變數。

## Addendum: 對外曝露與 ChatGPT 連線完成（post-implementation）

Tunnel 選用 Microsoft Dev Tunnel（放棄 Cloudflare Tunnel——named tunnel 需要帳號
底下已有網域/zone，這個帳號沒有；quick tunnel 可用但網址不固定）。對應新增
[ADR 0017](../adr/0017-allow-anonymous-devtunnel-for-isolated-devspace-on-personal-registrations.md)：
`devtunnel --allow-anonymous` 在「repo/機器登記為 personal」時例外放行，其餘情境
維持絕對禁止。

`devspace`（`internal: true` 網路）本身無法直接 port publish，這在骨架驗證階段
已知（README 的 port-forward 說明）；接上真實 tunnel 後又踩到兩個新坑：

1. `devtunnel port create` 的 `--protocol` 設錯成 `https` 會讓 relay 對明文 HTTP
   後端講 TLS，回報 502 且無明確錯誤訊息。
2. ChatGPT 連接器核准頁的 Owner password 若透過 `cut -d= -f2` 之類指令萃取，
   token 尾端剛好是 base64 padding `=` 時會被誤砍，核准會顯示「password was not
   accepted」卻查不出原因——要直接讀檔案原文，不要用會在 `=` 切字串的指令處理。

完整設定步驟（含 ChatGPT Developer Mode 開啟路徑、連接器建立流程）已寫進
`containers/devspace-isolation/README.md`，不在此重複。

驗證：ChatGPT 連接器頁面顯示「已使用授權：OAuth」與連線日期，代表端到端可用。

## Addendum: `egress-proxy` 最小權限強化與已知限制（post-implementation）

資安複查指出 `egress-proxy`（squid）是唯一同時橋接 `devspace-internal` 與
`devspace-egress` 兩個網路的元件，卻沒有比照 `devspace`/`port-forward` 做
`cap_drop`/`read_only`/非 root 強化。實測結果：

- `no-new-privileges: true`、`read_only: true` + 三個必要目錄改 tmpfs
  （`mode=1777`，因為 squid 自己降權後需要能寫）——**可行，已套用**。
- `cap_drop: [ALL]` 當時判定**不可行**：`ubuntu/squid` 官方 image 的 entrypoint 會先以
  root 啟動，內部用 `setuid`/`setgid` 降到 `proxy` 使用者，需要
  `CAP_SETUID`/`CAP_SETGID`；就算補回這兩個 capability，squid 內建的 ICMP
  pinger 子程序在降權後一樣拿不到 `CAP_NET_RAW`（Linux 預設 `setuid()` 會清空
  capability，這個 image 的 pinger binary 沒有設定 file capability 讓它繞過這個
  限制），導致 pinger FATAL、squid 整個中止。要真正解決需要客製化 image
  （對 pinger binary 做 `setcap`，或直接移除 pinger），這次不做，留為已知限制
  記錄，不是默默跳過不提。（註：上述「pinger 子程序拿不到 `CAP_NET_RAW` 導致
  FATAL、squid 整個中止」的判斷，經下方 post-implementation 補測後發現不完全
  準確——實際擋住 `cap_drop: [ALL]` 的是 squid.conf 預設
  `cache_effective_user proxy` 讓 squid 主行程自己呼叫
  `setgid`/`initgroups` 需要 `CAP_SETGID`；pinger 拿不到 `CAP_NET_RAW`
  確實會 FATAL，但那只是 pinger 自己的子行程失敗、登出雜訊，不會拖垮主行程。）

  **已於 post-implementation 補測解決**：`docker-compose.yml` 的
  `egress-proxy` 服務加上 `user: "13:13"`（Debian/Ubuntu 內建 `proxy`
  使用者的 uid/gid，也是 squid.conf `cache_effective_user` 解析到的目標），
  讓容器一開始就以該身份啟動，squid 已經是自己要降到的目標使用者，完全不需要
  再呼叫 `setgid`/`initgroups`。實測驗證：`docker exec ... cat
  /proc/1/status` 顯示 `CapInh`/`CapPrm`/`CapEff`/`CapBnd`/`CapAmb` 全部是
  `0000000000000000`；`cap_drop: [ALL]` 生效下，允許清單網域 200、非允許
  網域 403、loopback/RFC1918 403 皆與修改前一致，功能無迴歸。另外在
  `squid.conf` 加上 `pinger_enable off`——這個代理沒有任何 parent
  cache/ICP peer，ICMP pinger 本來就用不到，拿掉它讓每次啟動的 log 不再被
  一段獨立、無害但吵雜的 pinger FATAL 訊息洗版，與 `cap_drop` 能否生效無關，
  純粹是 log 衛生。

## References

## Addendum: git `safe.directory` required for the bind-mounted repo（post-implementation）

實際接上 ChatGPT 後,第一個真實 `bash` 工具呼叫就在 `/workspace` 裡執行 git 指令
失敗:`fatal: detected dubious ownership in repository at '/workspace'`——這是
Docker Desktop 在 Windows/WSL2 上做 bind-mount 路徑轉換時,回報的目錄擁有者跟
容器內執行的 UID 10001 對不上,觸發 git 自己的安全機制。修法：
`docker-entrypoint.sh` 每次啟動時執行
`git config --global --add safe.directory /workspace`——只信任這一個容器本來就
被明確授權的路徑,不放寬到其他任何目錄，不影響隔離態勢本身。已用真實 ChatGPT
連線重現問題、驗證修法有效（`git status` 恢復正常）。

- `docs/adr/0015-isolate-ai-agent-mcp-server-execution.md`
- `docs/adr/0017-allow-anonymous-devtunnel-for-isolated-devspace-on-personal-registrations.md`
- `scripts/governance-command-policy-hook.ps1`、
  `vault/governance/project-classification.json`
- `pop15106/pixiu-core` 的 `scripts/devspace-portable`（先前研究過的參考實作，
  本次不採用其隔離模型）
- [Waishnav/devspace](https://github.com/Waishnav/devspace)（實際接入的 DevSpace
  上游來源，MIT 授權）

## Addendum: squid 允許清單補上內網位址阻擋（post-implementation）

資安複查追加發現：`squid.conf` 的允許清單（`allowed-domains.txt` + `dstdomain`
ACL）只管網域名稱，沒有限制**解析後的目的位址**——未來若允許清單加入的某個
網域，此刻或之後透過 DNS rebinding 解析到內網位址（`egress-proxy` 同時掛在
`devspace-internal` 與 `devspace-egress` 兩個網路，本來就連得到內網其他服務），
就能繞過「只能連白名單網域」的設計意圖，直接打到內網。

修法：在 `Safe_ports`/`CONNECT` 檢查之前，新增一條 `dst` ACL 直接擋掉私有/
loopback/link-local 位址範圍（`10.0.0.0/8`、`172.16.0.0/12`、`192.168.0.0/16`、
`127.0.0.0/8`、`169.254.0.0/16`、`0.0.0.0/8`、`::1/128`、`fc00::/7`、
`fe80::/10`），不論來源是哪個網域名稱。squid 的 `dst` ACL 是對「DNS 解析後的
實際目的位址」判斷，不是對主機名稱字串判斷，所以這條規則會擋住網域重新解析
到內網的情況，不只是擋直接打 IP。

已在正式運行中的 `devspace-egress-proxy` 容器上實測驗證（`docker compose up
-d --force-recreate egress-proxy` 套用設定變更；bind-mount 的設定檔變更不會
自動觸發重建，需要 `--force-recreate`）：

- `curl -x http://egress-proxy:3128 http://example.com/` → `200`（允許清單內，
  仍然放行）
- `curl -x http://egress-proxy:3128 http://denied-test.invalid.example/` →
  `403`（不在允許清單，原本就會擋，確認沒有因為新規則而誤放）
- `curl -x http://egress-proxy:3128 http://127.0.0.1/` → `403`（新規則生效）
- `curl -x http://egress-proxy:3128 http://10.1.2.3/` → `403`（新規則生效）

這條規則之後加入真實網域時不需要額外維護——它擋的是目的位址範圍，跟允許清單
裡有哪些網域無關。

## Addendum: 多專案並存——`containers/chouten-court-isolation/`（post-implementation）

ADR 0015 的「單一 bind-mount」邊界是**每個容器實例**的邊界，不是「整台機器只能
跑一個 DevSpace 實例」；要同時開放第二個 repo（`D:/workspaces/chouten-court`）
給 DevSpace，且不能讓兩個專案互相看到彼此，做法是整組隔離骨架**複製一份獨立
實例**（`containers/chouten-court-isolation/`），而不是讓單一容器實例切換
`DEVSPACE_REPO_PATH`（那樣同時間只能有一個專案可連）。

兩個實例之間唯一必須不同的地方：

- `container_name`（Docker daemon 全域唯一，不像 compose network 名稱會自動加
  專案前綴）：`chouten-court-*` 系列。
- `port-forward` 對外發布的 host port：`127.0.0.1:7677`，projectD-core 那組
  维持 `127.0.0.1:7676`。
- 各自獨立的 `.env`（獨立的 `DEVSPACE_REPO_PATH`、獨立產生的
  `DEVSPACE_OAUTH_OWNER_TOKEN`——兩個實例絕不共用同一組 token）。

其餘安全設定（非 root、`cap_drop: [ALL]`——含 egress-proxy 的 `user: "13:13"`
修法、`read_only`、`no-new-privileges`、squid deny-by-default 允許清單、
`private_destinations` 內網阻擋、`pinger_enable off`）完全比照 projectD-core
那組複製，不因為是第二個實例就降低標準。

已用真實同時執行驗證：兩組堆疊 `docker compose up -d --build` 同時跑，
`docker inspect` 確認各自的 network 是 `devspace-isolation_devspace-internal`
與 `chouten-court-isolation_devspace-internal`（compose 依目錄名自動加前綴，
未特意改名也不會撞名）；`chouten-court-isolated` 容器內對
`devspace-egress-proxy`（另一組的內部 hostname）發出請求得到 DNS 解析失敗
（`curl` exit code 6），確認兩個 `devspace-internal` 網路彼此不通;兩邊
`/workspace` 內容分別對應各自的 repo，沒有互相看到對方的檔案。`.gitignore`
的 `.env` 規則已從單一路徑改成 `containers/*/.env`，涵蓋所有未來新增的實例。

對外曝露沿用同一個 `devspace-projectd` devtunnel、多加一個 port（7677）轉發，
不另外開一條 tunnel、也不用多維護一個排程工作；細節見
`containers/chouten-court-isolation/README.md`。

## Addendum: 上述「多實例」設計被取代——改成單一容器多 repo 掛載（post-implementation）

上面這個「一個 repo 一組獨立容器」的決定，實際運作後發現每加一個 repo 就要
重來一整套（容器、port、devtunnel port、token、ChatGPT 連接器），維運成本
跟效益不成比例；同時發現已安裝的 `@waishnav/devspace@1.0.8` 原生就支援
`DEVSPACE_ALLOWED_ROOTS` 吃逗號分隔的多個路徑（依 v1.0.8 標籤版本的上游文件
確認），根本不需要靠多容器來服務多個 repo。詳細取捨理由記在
`docs/adr/0015-isolate-ai-agent-mcp-server-execution.md` 的對應 addendum。

`containers/chouten-court-isolation/` 已整個移除，`chouten-court` 改成掛進
`containers/devspace-isolation/` 這唯一一個容器（`/repos/chouten-court`）；
devtunnel 的 7677 port 也已刪除，只剩 7676 一個 port 服務所有 repo。上面這段
「多實例」的內容保留作為歷史紀錄與設計思路對照，不代表目前的實際架構——目前
架構、加 repo 的步驟、`docker-entrypoint.sh` 如何動態組出
`DEVSPACE_ALLOWED_ROOTS`，都記在 `containers/devspace-isolation/README.md`
的「Multi-repo support」段落。

已用真實測試驗證：`verify-isolation.ps1` 新增兩項檢查（多 repo 掛載不互相
混淆、`DEVSPACE_ALLOWED_ROOTS` 正確列出所有 repo），9 項全過;實際掛
`projectD-core`、`chouten-court`、`projectD-knowledge` 三個 repo 到同一個
執行中容器，`docker exec` 確認 `/repos/` 下三個資料夾內容互不混淆;只重建
`devspace` 容器（不動 `devspace-config` volume）不會讓既有 ChatGPT 連接器的
OAuth 授權失效——只有整個 volume 被清掉才會。
