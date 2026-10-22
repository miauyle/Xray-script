# 更新日志 / Changelog

[返回主页](README.md) · [English](CHANGELOG.en.md)

这里归档历史版本细节；主页只展示最近的重要变更。旧版本编号顺序按原记录保留，不代表严格的发布时间排序。

30. v2026.10.22.6 修复 WARP 启用时 `Failed to obtain WARP container IP`：已有运行容器现在也会返回容器 IP；已经停止的容器尝试重新启动，新容器首次注册/自动重启期间最多等待 20 秒获取运行中的 IPv4 地址。失败时显示容器状态与最近日志，避免将空 IP 写入 Xray 配置。失败回滚只移除本次新建容器，保留既有 WARP 容器、镜像和注册数据（不再触发具有破坏性的 `--disable-warp` 清理）。新增独立 Docker mock 回归测试；不改变现有 Xray 配置、UUID 或 REALITY 密钥。


29. v2026.10.22.5 修复 **Xray 26.10.21 全新安装** 报 `unsupported config file extension`：配置应用、失败回滚及 mKCP 兼容性探测的临时配置现在均以 `.json` 结尾（即使显式 `-format=json`，新版内核仍检查文件扩展名）。新增真实 Xray v26.3.27/v26.10.21 的临时配置写入与回滚测试。Mihomo 订阅只在服务器实际运行 **Xray ≥ v26.9.8** 时为 VLESS REALITY 节点输出 `reality-opts.support-x25519mlkem768: true`，低版本/未知版本不启用；单机 `clash.yaml`、`proxies.yaml` 和中心本地节点 `multi_clash.yaml` 一致，远端 Provider 的参数由各自 VPS 生成并透传。保留 `client-fingerprint: chrome`；不改变原始 VLESS 分享链接及 Shadowrocket 专用逻辑。更新后重新生成订阅 YAML、客户端刷新订阅；不会自动改动已有 Xray 身份凭据或在旧节点上强制开启后量子扩展。

28. v2026.10.22.4 恢复 Xray 的文件日志记录：所有六种协议模板重新写入 `/var/log/xray/access.log` 和 `/var/log/xray/error.log`。安装/升级、配置切换和服务启动前检测 systemd 实际 User/Group 与日志文件可写性；仅当旧文件无法写入时，先按时间戳备份旧内容（限制备份权限），再创建适当用户/组的 0640 日志文件。可写日志保持原样，不会清空或重复备份。异常符号链接、硬链接和非预期目录所有者拒绝自动修复；旧配置和证书/订阅保持不变。可在「运维与诊断 → 日志」查看 access.log 和 error.log；CI 增加 root→nobody 权限与真实 Xray 文件日志测试。


27. v2026.10.22.3 修复升级导致节点不可用的回归：所有 Xray 配置模板默认输出日志到 stdout/systemd journal，避免旧 access.log/error.log 的所有权与 systemd 运行用户不一致造成启动失败；配置校验失败显示原始错误（不回显完整私钥配置）；升级 Xray-core 前保留旧程序，新程序必须通过已有配置校验，原本运行中的服务重启后需稳定存活两秒，否则回滚。修复 mKCP 旧版 `kcpSettings.seed` 被 Xray 26.3.27 废弃导致无法启动：改为 FinalMask，按当前 Xray 实测校验选择新版 `mkcp-legacy` 或旧版 `mkcp-aes128gcm`（保留原 seed 作为混淆密码）；继续生成旧格式的分享链接供兼容客户端导入，现代 Xray 客户端应按 FinalMask 配置。新增隔离回归测试及使用 v26.3.27/v26.10.21 真实二进制的 CI 配置与启动检查。**脚本更新不会主动覆盖现有 Xray 配置或自动删除日志，已有问题需按日志诊断后修复。**

26. v2026.10.22.2 修复 Xray-core 更新使用官方安装器时传入过时的 `-u root` 参数，导致“最新版”和“自选版”均报 `unknown option -- -`；升级现改为调用官方支持的 `install --local <zip>`，对已有 systemd 服务附加 `--no-update-service`，避免更换服务运行用户或覆盖自定义配置。新增严格参数与服务保留回归测试。

25. v2026.10.17.2 默认 Mihomo 分流规则增加 Apple 直连：在广告拦截之后、中国大陆规则之前加入 `GEOSITE,apple-cn,DIRECT` 和 `GEOSITE,apple,DIRECT`，覆盖 App Store、iCloud、系统更新等苹果域名及中国特定分发域名。苹果服务即使落到境外 CDN，也不再因为 `MATCH,Proxy` 默认走代理。单机 `clash.yaml` 与中心 `multi_clash.yaml` 一并生效，Shadowrocket 节点订阅不受影响。升级后需要重新生成中心 YAML，并在 Clash Verge Rev 刷新订阅；部分区域限制服务可能需要按需覆盖。

24. v2026.10.17.1 优化 Clash/Mihomo 默认路由规则：优先直连 `GEOSITE,private`、`.local`、`.lan`、`.home.arpa` 及 `GEOIP,private`（不强制解析），随后广告拦截、中国大陆域名与 IP 直连，最后 `MATCH,Proxy`。将不存在保障的 `GEOIP,lan` 改为 `GEOIP,private`，且 `GEOIP,CN,DIRECT` 允许按需 DNS 解析来识别国内 IP。**单机与中心聚合订阅共用该模板，不强行配置 DNS/TUN**。需在 VPS 重新生成 YAML 并在客户端刷新订阅后生效；如客户端出现额外 DNS 请求可视需要恢复 CN 规则的 `no-resolve`。

23. v2026.10.16.5 中心聚合订阅菜单新增「8. 查看已添加子节点名称及完整 Provider URL」。仅主动选择该项时读取中心的 `multi-server.json` 并输出全部远端节点地址（包含 Token），不改变原有订阅、连接配置、普通 `show` 脱敏行为或中心列表。请勿公开该页面的完整 URL 或截图。

22. v2026.10.16.4 将旧多机对等订阅简化为「唯一中心 + 普通 VPS 独立订阅」：普通 VPS 生成并发布 `clash.yaml`/`proxies.yaml`，共用原单机 Token；仅中心维护服务器列表和聚合订阅；删除旧 Provider Token 轮换菜单，旧 Token 暂时保持兼容。升级不自动改变任何机器的中心角色；按迁移说明手动关闭旧副中心。

21. v2026.10.16.3 改进 Clash/Mihomo GeoSite / GeoIP 下载源：生成配置中的 `geox-url` 改为 MetaCubeX 上游 GitHub Releases latest 的真实二进制文件地址，不再强制使用 testingcf.jsdelivr.net 镜像。修复镜像返回非二进制内容时可能触发的 `invalid GeoSite database file: proto: cannot parse invalid wire-format data` 问题。此改动不更改 Xray 节点配置；客户端仍须重新生成/更新订阅并在必要时清理失效的 GeoSite 缓存。注意：GitHub Releases 在部分网络中可能不可达，网络超时与解析出错需区分排查。


20. v2026.10.16.2 新增主机防火墙、conntrack_max、Swap 运维管理。Xray/TCP/UDP 或 Python 订阅端口启用前检查本机防火墙，经终端确认后才放行；Oracle VCN Security List/NSG 云端规则仍需人工配置。conntrack_max 支持内核立即写入验证与启动持久化，Swap 支持单独创建 1–32 GiB 并在 fstab 持久化，含隔离自动化测试。

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