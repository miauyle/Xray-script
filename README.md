中文 | [English](/.github/README.en.md)

# Xray 管理脚本 :sparkles:

* 一个纯 Shell 编写的 Xray 管理脚本
* 可选配置:
  * mKCP (VLESS-mKCP-seed)
  * Vision (VLESS-Vision-REALITY)
  * XHTTP (VLESS-XHTTP-REALITY)
  * trojan (Trojan-XHTTP-REALITY)
  * Fallback (包含 VLESS-Vision-REALITY、VLESS-XHTTP-REALITY)
  * SNI (包含 Vision_REALITY、XHTTP_REALITY、XHTTP_TLS)
* SNI 配置由 Nginx 实现 SNI 分流，适合过 CDN、上下行分离、多网站共存等需求
* SNI 分享链接实现了上下行分离(上行 xhttp+TLS+CDN | 下行 xhttp+Reality、上行 xhttp+Reality | 下行 xhttp+TLS+CDN)
* SNI 配置支持管理自定义域名与反代应用，每个站点拥有独立证书、独立站点配置、独立 stream 映射与 UDS
* 规则配置与自填:
  * 禁止 bittorrent 流量(可选)
  * 禁止回国 ip 流量(可选)
  * 屏蔽广告(可选)
  * 添加自定义 WARP Proxy 分流
  * 添加自定义屏蔽分流
* 开关 Cloudflare WARP Proxy( :whale: Docker 部署)
* 开关 geodata 自动更新功能
* xray 端口默认与自填:
  * VLESS-mKCP: 随机生成
  * ALL-REALITY: 443
* UUID 默认与自填:
  * 随机生成
  * 自定义输入标准 UUID
  * 非标准 UUID 映射转化为 UUID
* kcp(seed) 和 trojan(password) 默认与自填:
  * 随机生成(格式: cw-GEMDYgwIV3_g#)
  * 自定义输入
* target 默认与自填:
  * 随机在 serverNames.json 中获取
  * 实现自填 target 的 TLSv1.3 与 H2 验证
  * 实现自填 target 的 serverNames 自动获取
* shortId 默认与自填:
  * 随机生成(默认两个 shortId 例如: 01234567, 0123456789abcdef)
  * 实现自填 shortId
  * 实现输入值为 0 到 8, 则自动生成对 0-16 长度的 shortId
  * 支持逗号分隔的多个值
* path 默认与自填:
  * 随机生成(格式: /8ugSUeNJ.9OEnTErb.dVZMUAFu)
  * 自定义输入(格式: /8ugSUeNJ, 加不加 `/` 都可以)

## 问题

1. 如果安装成功，但无法使用，请检查服务器是否开启对应端口，可通过 `https://tcp.ping.pe/ip:port` 验证服务器端口是否开放。
2. 使用 SNI 配置前，请确保 VPS 的 HTTP(80) 与 HTTPS(443) 端口开放。
3. 使用 SNI 配置前，请不要开启 CDN 保护，不然无法正常申请 SSL 证书。
4. 上下行分离详情请看 [XHTTP: Beyond REALITY][XHTTP] 与 [xhttp 五合一配置][xhttp 五合一配置] 了解。
5. 使用 SNI 获取证书时遇到 【Could not get nonce, let's try again】 请查看 [ZeroSSL 状态页](https://status.zerossl.com/)，大概率是 ZeroSSL 的【Free ACME Service】处于 【Service disruption】或【Service outage】状态。

## 更新日志

14. v2026.09.23.10 吸收旧 PR #11 中仍有价值的 Xray 重启可靠性改进。
   1. Xray restart/start 后最多进行 5 次短间隔 active 检查，降低 systemd 服务启动瞬间造成的误判。
   2. apply 后重启失败时，在自动 rollback 前打印 `systemctl status xray` 和最近 40 行 journal，便于直接看到真实失败原因。
   3. 手工重启 Xray 同样复用 checked restart；失败不再静默继续，并输出相同诊断信息。
   4. restart/start 成功后确保 Xray systemd unit 已启用。
13. v2026.09.23.9 补全运维与安全管理功能。
   1. `apply_xray_config` 完成迁移：校验、自动备份、原子替换，并支持重启失败自动回滚。
   2. 新增备份列表/恢复、配置导出/导入、Doctor 与 Xray/WARP/Clash 日志查看。
   3. WARP 新增容器/SOCKS/出口 IP/国家检测，并支持基于 Xray observatory + balancer 的 Direct fallback。
   4. Routing 扩展为 Direct/WARP/Block 统一管理，新增 Direct IP/Domain，并同步持久化规则状态。
   5. Direct 出站支持 Auto/IPv4/IPv6；重新生成协议配置时保留 Direct family 与 WARP fallback。
   6. 主菜单新增“运维与诊断”，集中提供上述能力；自动备份同时保存脚本状态，协议重配失败可成对回滚。
   7. 新增轻量 CI，对核心 Shell、JSON 与 Clash HTTP Python 服务做语法校验。
12. v2026.09.23.8 引入统一 `apply_xray_config` 安全写入入口，并首先迁移 routing 配置修改。
   1. 候选配置先写入与正式配置同目录的临时文件，再由 `xray run -test -format=json` 校验。
   2. 校验通过后自动备份当前配置，并保留正式配置原有的权限和 owner/group。
   3. 使用同文件系统 `mv` 原子替换正式配置，避免 `cat > config.json` 等方式产生部分写入。
   4. routing 的新增、单项删除、整组清空已直接调用 `apply_xray_config`，并附带具体操作 context。
   5. `persist_xray_config` 暂时保留为兼容 wrapper，完整配置重生成与 WARP 等调用点后续逐步迁移。
11. v2026.09.23.7 新增 Xray 配置自动备份，并缩短 Clash/Mihomo 订阅 Token。
   1. 覆盖 `/usr/local/etc/xray/config.json` 前自动备份当前配置到 `~/.xray-script/backups/xray/`。
   2. 备份使用时间戳 + 随机后缀命名，权限为 `600`，备份目录权限为 `700`。
   3. 默认仅保留最近 10 份备份；清理更旧备份失败只警告，不阻止当前配置更新。
   4. 备份创建或权限设置失败时立即终止本次修改，避免在没有备份的情况下覆盖正式配置。
   5. Clash/Mihomo 新订阅 Token 改为 128-bit URL-safe Base64，长度约 22 字符；已有旧 Token 不会被静默替换，可通过“更换订阅 URL Token”生成短 Token。
10. v2026.09.23.6 升级 Clash Verge Rev / Mihomo 配置生成器到 v2。
   1. 默认开启 Sniffer，覆盖 HTTP、TLS 与 QUIC，并保留常见跳过域名。
   2. 新增 `Proxy` 手动策略组与 `Auto` 延迟测试组；Auto 每 300 秒测试节点，支持 lazy、50ms tolerance 与 HTTP 204 校验。
   3. 默认启用 `profile.store-selected`、`unified-delay` 与 `tcp-concurrent`，并将 IPv6 默认关闭。
   4. 启用 Mihomo GEO 数据自动更新，使用 `memconservative` loader 与 MetaCubeX GeoIP/GeoSite 数据。
   5. 默认规则增加广告拒绝、LAN 直连、Steam/Microsoft 中国区直连、CN 域名/IP 直连，其余流量进入 `Proxy`。
   6. 不在订阅中强制写入 TUN/DNS，避免覆盖 Clash Verge 客户端本地网络设置。
9. v2026.09.23.5 增强 Clash/Mihomo 轻量 HTTP 订阅启动诊断与自检可靠性。
   1. 本机订阅自检强制绕过 `http_proxy/HTTP_PROXY`，避免 `127.0.0.1` 健康检查误走代理。
   2. 启动后进行多次短间隔自检，减少 systemd 服务刚启动时的瞬时误判。
   3. systemd 启动失败或本机自检失败时，直接输出 `systemctl status` 与最近的 `journalctl` 日志，再执行回滚。
   4. 自检失败时同时显示目标端口的监听 socket，便于区分服务未启动与请求链路异常。
8. v2026.09.23.4 修正 Clash/Mihomo 远程订阅与 Xray SNI 模式错误耦合的问题。
   1. Vision、XHTTP、Fallback、SNI 等兼容协议都可生成远程订阅，不再要求 `.xray.tag == SNI`。
   2. 远程订阅托管与 Xray 数据链路解耦：已有 Nginx HTTPS 时优先复用；否则可选择启动轻量 HTTP 静态订阅服务，默认端口为 80，用户可自行输入其他端口。
   3. 轻量 HTTP 后端仅响应随机 Token 对应的 `clash.yaml`，无目录浏览和 Web 管理界面，并由 systemd 管理。
   4. HTTP 后端启动后会本机自检订阅 URL；端口冲突或服务启动失败时不会写入有效订阅状态。
   5. HTTP 订阅链路不加密，订阅包含节点凭据，脚本会在启用前明确提示风险。
7. v2026.09.23.3 新增 Clash Verge Rev / Mihomo 配置与订阅功能。
   1. 支持从当前 Xray 配置生成可直接导入的 Mihomo YAML。
   2. 支持 Vision+Reality、VLESS+XHTTP+Reality、Fallback，以及 SNI 下的 Reality/XHTTP/TLS-CDN 节点。
   3. SNI + Nginx 模式可发布带随机 Token 的 HTTPS 远程订阅，不新增常驻服务。
   4. 支持查看、刷新、旋转订阅 Token 和关闭远程订阅；Nginx 修改前备份并在校验失败时回滚。
   5. Mihomo 当前不支持 VLESS+mKCP 与 Trojan+XHTTP，脚本会明确拒绝生成无效配置。
6. v2026.09.23.2 统一 fork 的维护者与仓库展示信息。
   1. README 与终端 Banner 改为显示 `miauyle/Xray-script`。
   2. 脚本头部的仓库/维护者元数据改为当前 fork。
   3. 原始 MIT 版权声明继续保留在 LICENSE 与必要的版权声明中。
5. v2026.09.23.1 新增现有分流规则管理。
   1. 支持查看 `block-ip`、`block-domain`、`warp-ip`、`warp-domain` 四类自定义规则。
   2. 支持按编号删除单条规则，规则组为空时自动移除对应 ruleTag。
   3. 支持清空整组自定义规则，并提供确认提示。
   4. 删除和清空仍会先执行 Xray 配置校验，通过后才写入并重启服务。
4. v2026.09.23 修复自定义 routing 规则写入问题，并增强配置更新安全性。
   1. 修复 WARP/屏蔽分流误用 `XRAY_CONFIG` 读取输入，导致有效域名可能被写成空字符串 `""` 的问题。
   2. 分流输入会自动去除空白、过滤空项并去重，禁止空规则写入。
   3. 写入正式 Xray 配置前先执行配置校验；校验失败时保留原配置，避免重启后 Xray 无法启动。
   4. 安装、更新和配置下载地址切换为 `miauyle/Xray-script`，后续更新保持在当前 fork。
1. v2025.11.19 版本解决【开启 WARP 时没有设置日志限制，导致容器日志会一直叠加，最终占满硬盘空间】问题。
   1. 已启动 WARP 分流的用户可以在【管理配置】->【分流管理】中选择【重置 WARP Proxy】选项，该选项实现清空容器日志与重置 WARP Proxy。
   2. 已添加日志限制，如需使用 WARP 功能直接启用即可。
2. v2026.03.01 版本添加切换 CA 厂商功能，切换 CA 厂商时，脚本会对现有域名证书执行强制重签（`domain`、`cdn` 与 `custom_sites[].domain`），全部成功后才写入新 CA；若中途失败会自动回滚到原 CA，并恢复对应配置，避免影响后续 acme 自动续期任务。
   1. 强制重签会绕过「域名未变化」检查（acme.sh 的 `Domains not changed` 提示场景）。
   2. 请留意 CA 侧签发频率限制（例如 Let's Encrypt 的速率限制）。
3. v2026.03.17 版本添加 SNI 自定义域名与反代应用管理功能，用于在不影响现有 `Reality(domain)` 与 `CDN(cdn)` 站点的前提下，额外挂载多个 HTTPS 反代站点。
   1. 菜单路径：`管理配置 -> SNI 配置管理 -> 管理自定义域名与反代应用`
   2. 支持列表 / 新增 / 编辑 / 删除，自定义站点拥有独立证书、独立 `sites-available/<domain>.conf`、独立 stream 映射与 UDS。
   3. `stream.conf` 会按 `domain`、`cdn`、`custom_sites` 全量重建；UDS 名称规则为 `SHA-256(域名)` 前 `12` 位 + 端口号。
   4. 反代目标支持仅输入端口或完整 `http(s)://host:port` 地址；仅输入端口时自动规范化为 `http://127.0.0.1:<port>`；不接受带 `path`、`query`、`fragment` 的地址。
   5. 编辑时仅修改上游地址不会重复签发证书；修改域名时会先申请新证书，再切换配置，失败自动回滚；删除时会同时清理站点配置、软链、续签记录与证书目录。
   6. 自定义域名不能与 `domain`、`cdn` 或其他自定义站点域名重复；切换 CA 厂商与“强制续签所有证书”都会覆盖自定义站点域名。
   7. 自定义站点为“纯反代站点”，不包含 Xray 的 `xhttp/grpc` 路径，也不接入 Cloudreve 管理逻辑；代理层不会额外注入 `Content-Security-Policy`，由上游应用自行控制 CSP。

## 分享链接

基于[VMessAEAD / VLESS 分享链接标准提案](https://github.com/XTLS/Xray-core/discussions/716)与[v2rayN](https://github.com/2dust/v2rayN)实现，如果其他客户端无法正常使用，请自行根据分享链接进行修改。

SNI 配置中，CDN 的分享链接 Alpn 默认为 H2，如有 H3 需求，请自行在客户端修改。

### Clash Verge Rev / Mihomo

**配置生成器 v2 默认策略：**

- Sniffer：HTTP / TLS / QUIC。
- 策略组：`Proxy`（手动）+ `Auto`（URL Test）。
- GEO：自动更新 GeoIP / GeoSite 数据。
- 分流：广告拒绝、LAN 直连、Steam/Microsoft 中国区直连、CN 域名/IP 直连，其余走 `Proxy`。
- IPv6 默认关闭；开启 `unified-delay`、`tcp-concurrent`、`profile.store-selected`。
- 不写入 TUN / DNS；继续由 Clash Verge 客户端本地配置管理。

主菜单新增 `Clash/Mihomo 配置与订阅`：

- `生成/刷新本地 YAML`：输出到 `~/.xray-script/clash/clash.yaml`。
- `开启/刷新远程订阅`：与 Xray 协议类型无关；已有 Nginx HTTPS 站点时优先复用，否则可选择启动轻量 HTTP 静态订阅服务。
- `查看订阅信息`：显示本地 YAML 路径和当前订阅 URL。
- `更换订阅 URL Token`：立即使旧 URL 失效。
- `关闭远程订阅`：关闭当前订阅后端，但保留本地 YAML。

远程订阅与 Xray 的 Vision/Reality/XHTTP 数据链路完全独立。已有 Nginx HTTPS 时 URL 形如 `https://domain/sub/<random-token>/clash.yaml`；没有可复用 HTTPS 站点时，可选择轻量 HTTP 后端。端口直接回车默认使用 `80`，也可手动输入 `1-65535` 的其他端口。80 端口时 URL 形如 `http://server-ip/sub/<random-token>/clash.yaml`；自定义端口时形如 `http://server-ip:<port>/sub/<random-token>/clash.yaml`。脚本不会自动替用户切换端口；所选端口被占用时会直接报错。HTTP 不加密，订阅内容又包含节点凭据，因此只应在你接受这一风险时使用；如果怀疑 URL 泄露，请立即旋转 Token。

当前生成器支持 Vision+Reality、VLESS+XHTTP+Reality、Fallback 与 SNI 中的兼容 VLESS 节点。Mihomo 当前不支持 VLESS+mKCP 和 Trojan+XHTTP，脚本不会为这两类组合生成伪兼容配置。

## Xray 配置自动备份

脚本在覆盖正式 Xray 配置前会自动保存当前版本：

- 正式配置：`/usr/local/etc/xray/config.json`
- 备份目录：`~/.xray-script/backups/xray/`
- 默认保留：最近 10 份
- 首次安装时如果正式配置尚不存在，则不会创建空备份
- 当前版本只提供自动备份机制，暂不提供恢复菜单

备份失败会直接终止本次配置修改；旧备份清理失败只会输出警告，不影响已经创建的新备份。


## 运维与诊断

主菜单 **11. 运维与诊断** 集中提供日常维护能力：

- **Doctor**：检查 Xray JSON/核心校验、systemd 状态、监听端口、自动备份、WARP 容器与 SOCKS 出口、WARP fallback 结构、Clash HTTP 订阅服务。
- **日志**：显示 Xray systemd/error.log、WARP Docker 日志和 Clash 订阅服务日志。
- **WARP 状态与出口**：通过 WARP SOCKS 请求 Cloudflare trace，显示容器状态、出口 IP、国家/地区和 WARP 状态。
- **WARP Direct fallback**：使用 Xray `observatory + balancer.fallbackTag=direct`，WARP 被观测为不可用时回退 Direct；只影响明确配置为 WARP 的规则。
- **备份恢复**：Xray 正式配置修改前自动备份，默认保留 10 份。新备份同时保存脚本状态；旧版仅 Xray 的备份仍可恢复。
- **导出/导入**：将脚本配置和 Xray 配置打包为权限 `600` 的 `tar.gz`，用于手工迁移或额外留档。WARP 容器网络属于机器本地状态，迁移到其他 VPS 后建议运行 Doctor/WARP reset 重新确认。
- **Direct 出口 family**：可选 Auto / IPv4 / IPv6，对 Freedom outbound 使用 Xray `sockopt.domainStrategy`。

### 安全写入与自动回滚

所有 Xray 配置修改统一经过 `apply_xray_config`：

```text
候选配置 → xray -test → 自动备份 → 同目录原子替换 → 重启检查
                                                ↓ 失败
                                      自动恢复旧配置与脚本状态
```

Routing、协议重生成、WARP 开关/重置、备份恢复、导入和 Direct/WARP fallback 均复用这条路径。协议重配跨多个脚本进程时会保存 pending script-state，只有新 Xray 配置成功应用后才清除，避免 Xray 已回滚但脚本元数据仍停留在新配置。


## 如何使用

* 获取

  ```sh
  wget --no-check-certificate -O ${HOME}/Xray-script.sh https://raw.githubusercontent.com/miauyle/Xray-script/main/install.sh
  ```

* 使用
  * 启动界面

    ```sh
    bash ${HOME}/Xray-script.sh
    ```

  * 快速安装 Vision

    ```sh
    bash ${HOME}/Xray-script.sh --vision
    ```

  * 快速安装 XHTTP

    ```sh
    bash ${HOME}/Xray-script.sh --xhttp
    ```

  * 快速安装 Fallback

    ```sh
    bash ${HOME}/Xray-script.sh --fallback
    ```

* 快速启动(界面)

  ```sh
  wget --no-check-certificate -O ${HOME}/Xray-script.sh https://raw.githubusercontent.com/miauyle/Xray-script/main/install.sh && bash ${HOME}/Xray-script.sh
  ```

## 脚本界面

```sh
 __   __  _    _   _______   _______   _____  
 \ \ / / | |  | | |__   __| |__   __| |  __ \ 
  \ V /  | |__| |    | |       | |    | |__) |
   > <   |  __  |    | |       | |    |  ___/ 
  / . \  | |  | |    | |       | |    | |     
 /_/ \_\ |_|  |_|    |_|       |_|    |_|     

Maintained by miauyle | https://github.com/miauyle/Xray-script

-------------------------------------------
Xray       : v25.7.26
CONFIG     : VLESS-Vision-REALITY
WARP Proxy : 已启动
-------------------------------------------

--------------- Xray-script ---------------
 Version      : v2025-07-25
 Description  : Xray 管理脚本
----------------- 装载管理 ----------------
1. 完整安装
2. 仅安装/更新
3. 卸载
----------------- 操作管理 ----------------
4. 启动
5. 停止
6. 重启
----------------- 配置管理 ----------------
7. 分享链接与二维码
8. 信息统计
9. 管理配置
-------------------------------------------
0. 退出
```

## 已测试系统

| Platform | Version    |
| -------- | ---------- |
| Debian   | 10, 11, 12 |
| Ubuntu   | 20, 22, 24 |
| CentOS   | 7, 8, 9    |
| Rocky    | 8, 9       |

以上发行版均通过 Vultr 测试安装。

其他 Debian 基系统与 Red Hat 基系统可能能用，但未测试过，可能存在问题。

## 安装时长说明

SNI 配置适合安装一次后长期使用，不适合反复重置系统安装，这会消耗您的大量时间。如果需要更换配置和域名等，在管理界面都有相应的选项。

更换为非 SNI 配置后，Nginx 将停止服务，但会继续保留在本机，再启用 SNI 配置时不会进行重新安装。

### 安装时长参考

安装流程：

更新系统管理包->安装依赖->[安装Docker]->[安装Cloudreve]->[安装Cloudflare-warp]->安装Xray->安装Nginx->申请证书->配置文件

**这是一台单核1G的服务器的平均安装时长，仅供参考：**

| 项目                | 时长      |
| ------------------- | --------- |
| 更新系统管理包      | 0-10分钟  |
| 安装依赖            | 0-5分钟   |
| 安装Docker          | 1-2分钟   |
| 安装Cloudreve       | 3-5分钟   |
| 安装Cloudflare-warp | 3-5分钟   |
| 安装Xray            | <半分钟   |
| 安装Nginx           | 13-15分钟 |
| 申请证书            | 1-2分钟   |
| 配置文件            | <半分钟  |

### 为什么 SNI 配置安装时间那么长？

脚本的 Nginx 是采用源码编译的形式进行管理安装。

编译相比直接安装二进制文件的优点有：

1. 运行效率高 (编译时采用了-O3优化)
2. 软件版本新

缺点就是编译耗时长。

## 安装位置

**Xray-script:** `/usr/local/xray-script`

**Nginx:** `/usr/local/nginx`

**Cloudreve:** `$HOME/.xray-script/docker/cloudreve`

**Cloudflare-warp:** `$HOME/.xray-script/docker/warp`

**Xray:** 见 **[Xray-install](https://github.com/XTLS/Xray-install)**

## 依赖列表

使用 SNI 配置时，脚本可能自动安装以下依赖：
| 用途                            | Debian基系统                         | Red Hat基系统       |
| ------------------------------- | ------------------------------------ | ------------------- |
| yumdb set(标记包手动安装)       |                                      | yum-utils           |
| dnf config-manager              |                                      | dnf-plugins-core    |
| IP 获取                         | iproute2                             | iproute             |
| DNS 解析                        | dnsutils                             | bind-utils          |
| wget                            | wget                                 | wget                |
| curl                            | curl                                 | curl                |
| wget/curl https                 | ca-certificates                      | ca-certificates     |
| kill/pkill/ps/sysctl/free       | procps                               | procps-ng           |
| epel源                          |                                      | epel-release        |
| epel源                          |                                      | epel-next-release   |
| remi源                          |                                      | remi-release        |
| 防火墙                          | ufw                                  | firewalld           |
| **编译基础：**                  |                                      |                     |
| 下载源码文件                    | wget                                 | wget                |
| 解压tar源码文件                 | tar                                  | tar                 |
| 解压tar.gz源码文件              | gzip                                 | gzip                |
| gcc                             | gcc                                  | gcc                 |
| g++                             | g++                                  | gcc-c++             |
| make                            | make                                 | make                |
| **acme.sh依赖：**               |                                      |                     |
|                                 | curl                                 | curl                |
|                                 | openssl                              | openssl             |
|                                 | cron                                 | crontabs            |
| **编译openssl：**               |                                      |                     |
|                                 | perl-base(包含于libperl-dev)         | perl-IPC-Cmd        |
|                                 | perl-modules-5.32(包含于libperl-dev) | perl-Getopt-Long    |
|                                 | libperl5.32(包含于libperl-dev)       | perl-Data-Dumper    |
|                                 |                                      | perl-FindBin        |
| **编译Brotli：**                |                                      |                     |
|                                 | git                                  | git                 |
|                                 | libbrotli-dev                        | brotli-devel        |
| **编译Nginx：**                 |                                      |                     |
|                                 | libpcre2-dev                         | pcre2-devel         |
|                                 | zlib1g-dev                           | zlib-devel          |
| --with-http_xslt_module         | libxml2-dev                          | libxml2-devel       |
| --with-http_xslt_module         | libxslt1-dev                         | libxslt-devel       |
| --with-http_image_filter_module | libgd-dev                            | gd-devel            |
| --with-google_perftools_module  | libgoogle-perftools-dev              | gperftools-devel    |
| --with-http_geoip_module        | libgeoip-dev                         | geoip-devel         |
| --with-http_perl_module         |                                      | perl-ExtUtils-Embed |
|                                 | libperl-dev                          | perl-devel          |

## 致谢

[Xray-core][Xray-core]

[REALITY][REALITY]

[XHTTP: Beyond REALITY][XHTTP]

[integrated-examples][lxhao61/integrated-examples]

[xhttp 五合一配置][xhttp 五合一配置]

[部署 Cloudflare WARP Proxy][haoel]

[cloudflare-warp 镜像][e7h4n]

[V2Ray 路由规则文件加强版][v2ray-rules-dat]

[kirin10000/Xray-script][kirin10000/Xray-script]

[Cloudreve][cloudreve]

**此脚本仅供交流学习使用，请勿使用此脚本行违法之事。网络非法外之地，行非法之事，必将接受法律制裁。**

[Xray-core]: https://github.com/XTLS/Xray-core (THE NEXT FUTURE)
[REALITY]: https://github.com/XTLS/REALITY (THE NEXT FUTURE)
[XHTTP]: https://github.com/XTLS/Xray-core/discussions/4113 (XHTTP: Beyond REALITY)
[lxhao61/integrated-examples]: https://github.com/lxhao61/integrated-examples (以 V2Ray（v4 版） 或 Xray、Nginx 或 Caddy（v2 版）、Hysteria 等打造常用科学上网的优化配置及最优组合示例，且提供集成特定插件的 Caddy（v2 版） 文件，分享给大家食用及自己备份。)
[xhttp 五合一配置]: https://github.com/XTLS/Xray-core/discussions/4118 (xhttp 五合一配置 \( reality 直连与过 CDN 共存, 附小白可抄的配置\))
[haoel]: https://github.com/haoel/haoel.github.io#943-docker-%E4%BB%A3%E7%90%86 (使用 Docker 快速部署 Cloudflare WARP Proxy)
[e7h4n]: https://github.com/e7h4n/cloudflare-warp (cloudflare-warp 镜像)
[v2ray-rules-dat]: https://github.com/Loyalsoldier/v2ray-rules-dat (V2Ray 路由规则文件加强版)
[kirin10000/Xray-script]: https://github.com/kirin10000/Xray-script (kirin10000/Xray-script)
[cloudreve]: https://github.com/cloudreve/cloudreve (cloudreve)
