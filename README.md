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

26. v2026.10.22.2 修复 Xray-core 更新使用官方安装器时传入过时的 `-u root` 参数，导致“最新版”和“自选版”均报 `unknown option -- -`；升级现改为调用官方支持的 `install --local <zip>`，对已有 systemd 服务附加 `--no-update-service`，避免更换服务运行用户或覆盖自定义配置。新增严格参数与服务保留回归测试。

25. v2026.10.17.2 默认 Mihomo 分流规则增加 Apple 直连：在广告拦截之后、中国大陆规则之前加入 `GEOSITE,apple-cn,DIRECT` 和 `GEOSITE,apple,DIRECT`，覆盖 App Store、iCloud、系统更新等苹果域名及中国特定分发域名。苹果服务即使落到境外 CDN，也不再因为 `MATCH,Proxy` 默认走代理。单机 `clash.yaml` 与中心 `multi_clash.yaml` 一并生效，Shadowrocket 节点订阅不受影响。升级后需要重新生成中心 YAML，并在 Clash Verge Rev 刷新订阅；部分区域限制服务可能需要按需覆盖。

24. v2026.10.17.1 优化 Clash/Mihomo 默认路由规则：优先直连 `GEOSITE,private`、`.local`、`.lan`、`.home.arpa` 及 `GEOIP,private`（不强制解析），随后广告拦截、中国大陆域名与 IP 直连，最后 `MATCH,Proxy`。将不存在保障的 `GEOIP,lan` 改为 `GEOIP,private`，且 `GEOIP,CN,DIRECT` 允许按需 DNS 解析来识别国内 IP。**单机与中心聚合订阅共用该模板，不强行配置 DNS/TUN**。需在 VPS 重新生成 YAML 并在客户端刷新订阅后生效；如客户端出现额外 DNS 请求可视需要恢复 CN 规则的 `no-resolve`。

23. v2026.10.16.5 中心聚合订阅菜单新增「8. 查看已添加子节点名称及完整 Provider URL」。仅主动选择该项时读取中心的 `multi-server.json` 并输出全部远端节点地址（包含 Token），不改变原有订阅、连接配置、普通 `show` 脱敏行为或中心列表。请勿公开该页面的完整 URL 或截图。

22. v2026.10.16.4 将旧多机对等订阅简化为「唯一中心 + 普通 VPS 独立订阅」：普通 VPS 生成并发布 `clash.yaml`/`proxies.yaml`，共用原单机 Token；仅中心维护服务器列表和聚合订阅；删除旧 Provider Token 轮换菜单，旧 Token 暂时保持兼容。升级不自动改变任何机器的中心角色；按迁移说明手动关闭旧副中心。

21. v2026.10.16.3 改进 Clash/Mihomo GeoSite / GeoIP 下载源：生成配置中的 `geox-url` 改为 MetaCubeX 上游 GitHub Releases latest 的真实二进制文件地址，不再强制使用 testingcf.jsdelivr.net 镜像。修复镜像返回非二进制内容时可能触发的 `invalid GeoSite database file: proto: cannot parse invalid wire-format data` 问题。此改动不更改 Xray 节点配置；客户端仍须重新生成/更新订阅并在必要时清理失效的 GeoSite 缓存。注意：GitHub Releases 在部分网络中可能不可达，网络超时与解析出错需区分排查。


20. v2026.10.16.2 新增主机防火墙、conntrack_max、Swap 运维管理。Xray/TCP/UDP 或 Python 订阅端口启用前检查本机防火墙，经终端确认后才放行；Oracle VCN Security List/NSG 云端规则仍需人工配置。conntrack_max 支持内核立即写入验证与启动持久化，Swap 支持单独创建 1–32 GiB 并在 fstab 持久化，含隔离自动化测试。

### Oracle Ubuntu 主机运维（v2026.10.16.2）

主菜单选「11. 运维与诊断」→「10. 防火墙 / 11. conntrack_max / 12. Swap」。

防火墙：启动新的 Xray、Nginx 或 Python 订阅监听端口前检查本机 IPv4 规则；如未明确放行，终端主动询问。确认前不修改任何规则，拒绝后原规则保留。启用 UFW 时使用 UFW，否则使用 iptables，并将脚本新增的 ACCEPT 规则记录在 /etc/xray-script/firewall-ports.conf，通过 xray-script-firewall.service 在重启时恢复，不清空 INPUT、也不改变 SSH 端口。独立的 Oracle Cloud Security List / NSG 入站规则仍需自己在 OCI 控制台添加；「本机规则允许」不等于公网可达。未知 nftables 管理环境只显示警告，不自动变更。

conntrack：菜单可查看 nf_conntrack_count/max，默认建议 16384（输入时可改，范围 1024–1048576），先检查是否低于当前 count，再执行 sysctl -w 并读取内核验证，然后保存到 /etc/sysctl.d/99-z-xray-script-conntrack.conf；还将 nf_conntrack 加入独立 modules-load.d 文件以处理开机模块加载时序。保留原始值以备恢复，不编辑其他 sysctl 文件。重启后仍应验证 sysctl net.netfilter.nf_conntrack_max 是否符合预期。

Swap：默认仅创建 /var/lib/xray-script/swapfile，输入整数 1–32 GiB；验证磁盘剩余空间、文件系统、文件权限、mkswap 和 swapon，成功后写入带标识的 /etc/fstab 条目。删除仅针对该文件，不改已有 /swapfile 或其他 Swap 分区；swapoff 失败则拒绝删除。Btrfs 需特别处理，本功能明确拒绝自动创建。Oracle E2.1.Micro 可以从 1 GiB 开始，避免耗尽可用磁盘。

命令示例：bash core/handler.sh --host firewall status 443 tcp；bash core/handler.sh --host conntrack set 16384；bash core/handler.sh --host swap add 1。


19. v2026.10.16.1 修复多机聚合后远端节点可能使用过期凭据的问题，增加多机 Provider 诊断。
   1. Xray 配置成功更新后，如果已经生成过 Clash 订阅，自动重新生成本机的 `clash.yaml`、`proxies.yaml`、`multi_clash.yaml` 和 Shadowrocket 聚合订阅；刷新失败只警告，不回滚已成功运行的 Xray。
   2. Mihomo 远端 Provider 从每小时刷新缩短到每 5 分钟；Shadowrocket 远端 Provider 缓存仍支持临时失败回退，但超过 12 小时不再将旧节点当作有效节点输出。
   3. 新增多机菜单 **9. 诊断多机 Provider**，检查当前 VPS 的节点是否仍匹配 Xray UUID/Reality 公钥，并从本机网络访问每个远端 Provider，报告 HTTP/网络失败或缓存陈旧（不显示 Token、UUID 或密钥）。
   4. 此版本无法替代真实客户端验证：如单独订阅可用、聚合不行，首先查看诊断输出，再分别在 VPS 上重生成配置，并在 Clash/Shadowrocket 中强制刷新订阅和 Provider。



18. v2026.10.15.3 新增 Shadowrocket 单链接多 VPS 订阅：复用现有 Provider、MULTI_TOKEN，输出 `multi_nodes.txt`，自动转换 VLESS Reality/XHTTP，并通过缓存保留暂时不可用的远程节点。HTTP 动态聚合，Nginx 使用 5 分钟一次的 systemd 定时快照，无额外常驻聚合进程。


17. v2026.10.15.2 修复安装和重新生成 Xray 配置后误报“操作执行失败”的问题。
   1. 修复 `handler_xray_config` 在没有待恢复状态快照时，因最后一条条件语句返回 1 而误报失败；成功完成配置写入后明确返回 0。
   2. 不再在安装日志中打印 Reality Private Key，避免终端记录泄露服务器私钥。
   3. 新增针对首次安装和已有 pending 快照两种路径的回归测试。

16. v2026.10.15.1 增加可选 TCP BBR 网络优化，并补上此前多 VPS Mihomo 订阅功能遗漏的版本号更新。
   1. 在“运维与诊断”中新增 TCP BBR：查看状态、一键开启并持久化 BBR + fq、恢复启用前的内核参数。
   2. 自动检查当前内核是否支持 BBR；不强制升级内核，不重启 Xray，也不覆盖既有 sysctl 配置文件。脚本只管理专属的 `/etc/sysctl.d/99-xray-script-bbr.conf`。
   3. 开启前保存原来的 TCP 拥塞控制算法和默认队列调度器；失败时尝试回滚，恢复时只删除脚本创建的配置。
   4. 同时将上一轮 PR #15 的对等多 VPS `multi_clash.yaml`、Proxy Providers 和独立 Token 功能记录在当前版本中，并增加 BBR 回归测试。


15. v2026.09.23.11 修复 WARP 健康检查误绕过代理的问题。
   1. 修复 `ops_warp_trace` 使用 `--noproxy '*'` 导致 curl 完全绕过 SOCKS、错误显示 Oracle/VPS 直连出口的问题。
   2. 改为 `--noproxy \"\"` + 显式 `socks5h://<container>:40001`，确保即使系统存在 `NO_PROXY` 环境变量也强制走 WARP SOCKS。
   3. WARP 状态页新增 client status / mode，并将运行时结果拆分为 `SOCKS reachable` 与 `WARP data path`。
   4. Doctor 现在要求 Cloudflare trace 返回 `warp=on` 或 `warp=plus` 才判定 WARP 数据路径健康；`warp=off` 直接报 FAIL。
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
