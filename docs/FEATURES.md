# 功能与配置说明

[← 返回首页](../README.md) · [English](FEATURES.en.md) · [故障排查](TROUBLESHOOTING.md)

## 功能明细

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

### 单一中心订阅架构（v2026.10.16.4 起）

**普通 VPS** 仅使用「10. Clash/Mihomo 配置与订阅 → 1. 生成/刷新 YAML → 2. 开启/刷新远程订阅」。它会自动发布两个使用**同一单机 Token** 的文件：

- /sub/<single-token>/clash.yaml：包含节点与分流策略的独立 Mihomo 订阅；
- /sub/<single-token>/proxies.yaml：纯节点 Provider，供唯一的中心引用。

普通 VPS **不需要**启用中心、多机模式，也不需要记住其他 VPS 的信息、生成新的 Provider Token、安装第二个守护进程。更新 Xray 凭据后，已有订阅仍按照原有流程重新生成。新增单机 Provider 路由生效前，老机器需在菜单中执行「2. 开启/刷新远程订阅」，使 Nginx 配置或 Python 订阅服务加载新版代码。

**唯一中心 VPS** 也先开启单机订阅，再选择「10 → 6. 中心聚合订阅管理 → 1. 将本机设为中心」。中心保存原来的 multi-server.json（仅中心有 enabled=true），添加其他 VPS 独立 Provider 地址，例如 http://VPS-B:PORT/sub/<single-token-B>/proxies.yaml。中心聚合依然使用自己现有的多机 Token：

- /sub/<center-token>/multi_clash.yaml：Mihomo/Clash Verge Rev（Proxy Providers、Auto/Failover/Balance）。
- /sub/<center-token>/multi_nodes.txt：Shadowrocket 的 Base64 VLESS 节点订阅。

中心菜单「10 → 6 → 8」可以查看已经添加的所有子节点名称及完整 Provider URL（包括 Token），便于核对地址及重新复制；未添加节点时会显示空列表。普通「查看订阅信息」不泄露子节点完整地址。

中心仍包含本机节点，远端不可用时 Shadowrocket 最多回退 12 小时内的上次有效缓存；Mihomo 的远端 Provider 由客户端更新。任何 VPS 的独立订阅与中心无关。中心故障时，现有已导入节点一般仍可继续使用，但中心订阅无法更新，需要手工恢复中心。**没有自动主副切换。**

**从旧的对等版本迁移**：先升级全部 VPS 到 v2026.10.16.4，分别运行「生成/刷新 YAML」和「开启/刷新远程订阅」以发布新的 /proxies.yaml。选择一台作为唯一中心，在该机添加/更新其他机器的新 Provider URL。其他 VPS 进入「10 → 6 → 6. 关闭中心」，独立订阅仍然可用。新版本**不会自动关闭**旧机器的 enabled=true 配置，也不偷偷修改远端配置。现有中心 Token 和服务器列表不会在升级时被重置；旧 Provider Token URL 仍临时受支持，但新架构不再生成或提供旧的 Provider Token 轮换菜单。中心确认全部切换到单机 Token 后，可自行计划安全地停用旧凭据。不要公开任何完整订阅 URL，其中含节点信息或凭据。

**操作诊断**：中心菜单「10 → 6 → 7」检查远端 Provider 可达性及中心本机参数。遇到节点聚合后连接失败时，先用普通 VPS 自己的 clash.yaml 对比，再检查中心订阅；无需再从每台机器相互添加 peer。


## Xray-core 版本更新

主菜单选择 **2. 安装 / 更新 Xray** 后，有三种版本选择：

- **最新版**：包含预发布版（Pre-release），例如安全紧急修复版本。通过 GitHub Releases 列表解析最新发布时间的有效标签。
- **稳定版**：使用 GitHub Latest Stable API，**不会**自动选择预发布版。紧急安全版仍是 Pre-release 时，稳定版可能更旧。
- **自选版**：输入 `v26.10.21` 或 `26.10.21` 形式的完整版本号；不依赖 GitHub API 预先确认该版本是否存在，而是通过实际的 Release 文件下载与校验确认。

更新流程会下载所选版本对应架构的 ZIP 和 `.dgst` 文件，校验 SHA-256，再通过 Xray 官方安装器的本地文件模式安装。安装后核对实际 `xray version`；下载、校验或安装失败时保留原配置版本及之前的可执行文件，并尽可能恢复原服务。不会重新生成 REALITY 密钥、UUID 或订阅 Token。

升级之后可在 VPS 上运行：

```bash
/usr/local/bin/xray version
sudo systemctl is-active xray
sudo journalctl -u xray -n 30 --no-pager
```

建议仍然测试 VLESS REALITY 和 XHTTP 节点连通性。遇到 GitHub 下载失败，应检查 VPS 到 `github.com`、`raw.githubusercontent.com` 的网络，不要忽略错误继续重启服务。

## Xray 配置自动备份

脚本在覆盖正式 Xray 配置前会自动保存当前版本：

- 正式配置：`/usr/local/etc/xray/config.json`
- 备份目录：`~/.xray-script/backups/xray/`
- 默认保留：最近 10 份
- 首次安装时如果正式配置尚不存在，则不会创建空备份
- 当前版本还提供「运维与诊断 → 备份恢复」菜单

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
- **TCP BBR 网络优化**：可选状态查看、开启 BBR + fq、恢复原参数。采用专属 `sysctl.d` 文件持久化；不自动开启、不升级内核、不修改 Xray 配置。

### TCP BBR（可选）

从主菜单进入 **11. 运维与诊断 → 9. TCP BBR 网络优化**，可选择检查状态、开启或恢复原有设置。默认保持系统原样，不会在 Xray 安装或更新时自动开启。

开启前会先读取 `net.ipv4.tcp_available_congestion_control`，必要时尝试 `modprobe tcp_bbr`，不安装新内核。支持时立即应用 `net.ipv4.tcp_congestion_control=bbr` 与 `net.core.default_qdisc=fq`，并创建 **仅由脚本管理** 的 `/etc/sysctl.d/99-xray-script-bbr.conf`；原值保存在 `~/.xray-script/network/bbr-original.conf`。重新开启不会覆盖原始备份，恢复操作会撤销这个文件并尽量恢复启用前的运行时值。

可选 CLI：`bash core/handler.sh --bbr status|enable|restore`（需在已安装的项目根目录执行，启用/恢复需要 root）。如果目标 sysctl 文件已存在但不是脚本创建的，或者备份缺失，脚本会拒绝覆盖。BBR 仅作用于 Linux TCP 拥塞控制，**不保证加速，也不解决线路绕路或高丢包问题**。注意系统其他独立的 sysctl 配置仍可能在启动时覆盖这些参数。

### 安全写入与自动回滚

所有 Xray 配置修改统一经过 `apply_xray_config`：

```text
候选配置 → xray -test → 自动备份 → 同目录原子替换 → 重启检查
                                                ↓ 失败
                                      自动恢复旧配置与脚本状态
```

Routing、协议重生成、WARP 开关/重置、备份恢复、导入和 Direct/WARP fallback 均复用这条路径。协议重配跨多个脚本进程时会保存 pending script-state，只有新 Xray 配置成功应用后才清除，避免 Xray 已回滚但脚本元数据仍停留在新配置。

### Oracle Ubuntu 主机运维（v2026.10.16.2）

主菜单选「11. 运维与诊断」→「10. 防火墙 / 11. conntrack_max / 12. Swap」。

防火墙：启动新的 Xray、Nginx 或 Python 订阅监听端口前检查本机 IPv4 规则；如未明确放行，终端主动询问。确认前不修改任何规则，拒绝后原规则保留。启用 UFW 时使用 UFW，否则使用 iptables，并将脚本新增的 ACCEPT 规则记录在 /etc/xray-script/firewall-ports.conf，通过 xray-script-firewall.service 在重启时恢复，不清空 INPUT、也不改变 SSH 端口。独立的 Oracle Cloud Security List / NSG 入站规则仍需自己在 OCI 控制台添加；「本机规则允许」不等于公网可达。未知 nftables 管理环境只显示警告，不自动变更。

conntrack：菜单可查看 nf_conntrack_count/max，默认建议 16384（输入时可改，范围 1024–1048576），先检查是否低于当前 count，再执行 sysctl -w 并读取内核验证，然后保存到 /etc/sysctl.d/99-z-xray-script-conntrack.conf；还将 nf_conntrack 加入独立 modules-load.d 文件以处理开机模块加载时序。保留原始值以备恢复，不编辑其他 sysctl 文件。重启后仍应验证 sysctl net.netfilter.nf_conntrack_max 是否符合预期。

Swap：默认仅创建 /var/lib/xray-script/swapfile，输入整数 1–32 GiB；验证磁盘剩余空间、文件系统、文件权限、mkswap 和 swapon，成功后写入带标识的 /etc/fstab 条目。删除仅针对该文件，不改已有 /swapfile 或其他 Swap 分区；swapoff 失败则拒绝删除。Btrfs 需特别处理，本功能明确拒绝自动创建。Oracle E2.1.Micro 可以从 1 GiB 开始，避免耗尽可用磁盘。

命令示例：bash core/handler.sh --host firewall status 443 tcp；bash core/handler.sh --host conntrack set 16384；bash core/handler.sh --host swap add 1。

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
