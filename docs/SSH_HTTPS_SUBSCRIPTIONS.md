# SSH 多节点聚合与 Dynu HTTPS 迁移

本功能不修改任何 Xray 服务端业务配置，不要求更改 SSH 默认 22，不自动关端口。仓库默认分支为 main。

## 1. 升级与子节点本地文件

各节点先升级脚本，并进入主菜单 10 → 1 重新生成本地 clash.yaml 与 proxies.yaml。原有单节点 Token 保留不变；新生成/主动旋转的单节点和中心 Token 都是 32 字节安全随机数转 URL-safe base64（43 字符），两者分别生成，互不共享。

正常以 root 运行时，节点文件位于 /root/.xray-script/clash/proxies.yaml。原配置文件不应成为 Web 根目录；不要把配置、UUID、密钥发往公网 HTTP Provider。

推荐为中心 SFTP 读取设置专用低权限账户（如 xraysync），不要简单开放 root 的私有目录。可由管理员在每次生成后将 proxies.yaml 复制到仅该账户有权读取的 /home/xraysync/subscriptions/proxies.yaml，设置 root:xraysync / mode 0640，确保父目录可遍历。复制时保护临时文件与目标原子更新；同时保留在操作台显示的“子节点本地订阅生成”流程。中心 SSH 配置中的路径应填写这个只读副本。

## 2. SSH 密钥及主机公钥指纹

中心上生成一个独立私钥：

    ssh-keygen -t ed25519 -a 64 -f ~/.ssh/id_ed25519_xray_sync
    chmod 600 ~/.ssh/id_ed25519_xray_sync

将对应的 .pub 添加到各子节点同步账户的 authorized_keys。建议针对同步账户禁止密码认证、限制只能 SFTP、限制中心源 IP，但保留独立管理用 SSH 入口。

首次保存主机公钥需要独立核对指纹，不要盲信 ssh-keyscan 内容；核对无误后保存至专用 known_hosts 文件，并通过 SFTP 测试。示例：

    ssh-keyscan -p 22 -t ed25519 PEER_IP >> ~/.ssh/known_hosts_xray
    ssh-keygen -lf ~/.ssh/known_hosts_xray
    sftp -P 22 -i ~/.ssh/id_ed25519_xray_sync -oStrictHostKeyChecking=yes -oUserKnownHostsFile=~/.ssh/known_hosts_xray xraysync@PEER_IP

22 是默认值，每台 VPS 可独立填写其他 SSH 端口。不要用 StrictHostKeyChecking=no。修改 SSH 服务监听端口属于单独高风险人工操作，本脚本只提供只读安全检查：需提前放通 Oracle NSG/Security List 与 Ubuntu 防火墙，确认新连接能登录以后才考虑关闭旧端口。

## 3. 中心添加、测试和手动同步

在中心的主菜单 10 → 6：

1. 启用中心 SSH 聚合；原有旧 Provider 配置不会自动删除。
2. 输入子节点名称、主机/IP、SSH 用户、SSH 端口（默认 22）、远端 proxies.yaml 路径、中心私钥路径、已验证的 known_hosts 文件。
11. 测试 SFTP 及节点配置有效性。
9. 手动同步所有节点；10. 同步单个节点。
8. 列出子节点与最近同步时间；3. 移除节点；5. 主动刷新中心 Token。

修改子节点 Xray 配置后，先在子节点重新生成本地 YAML 并更新同步账户只读副本；随后在中心手动同步并在客户端刷新订阅。没有定时 SSH 拉取、没有中心向子节点推送。验证通过的远端快照缓存在中心私有目录；单节点同步失败时继续使用最近有效缓存。静态输出 multi_clash.yaml 含完整节点及原有规则集，multi_nodes.txt 是 Shadowrocket base64 VLESS 链接列表。

## 4. Dynu HTTPS 与证书

在中心主菜单 10 → 6 → 12：

1. DNS-01：Dynu TXT 验证。输入自己的 Dynu 完整域名，提供 Dynu OAuth2 API Client ID/Secret，而非 Dynu 登录密码。acme.sh 内置 dns_dynu 自动申请、增加和清理 TXT。新免费域名可能暂时不允许操作 TXT，须以账户实际 API 返回结果为准。
2. HTTP-01：acme.sh standalone 使用 80 端口。签发前确认本机 80 空闲，同时确认 Oracle Cloud Security Lists/NSG 和 Ubuntu 防火墙公网 TCP 80 已放通。自动续期时也必须允许公网 TCP 80 到达。若做不到，改 DNS-01。此模式不会永久运行独立的 HTTP 订阅服务。
3. 查看 TLS 证书到期时间、HTTPS 服务和续期 Timer。
4. 手动强制续签。
5. 在没有 Xray 监听冲突的端口启动独立 HTTPS，默认 8443（不能直接抢占已运行 Xray REALITY/Fallback 的 443）。
6. 查看 SSH 与本机防火墙（只读）。

证书继续复用已有 acme.sh 二进制，但中心独立使用本地 acme-certs 目录，以免与旧 Nginx 证书更新钩子冲突。systemd xray-center-cert-renew.timer 每天调用 acme.sh --cron 检查该目录；证书实际更新后部署钩子重启中心 HTTPS 服务。使用 systemctl list-timers xray-center-cert-renew.timer 或 journalctl -u xray-center-cert-renew.service 检查续期任务及失败。DNS-01 凭据由 acme.sh 写入受保护的账户配置，不写入仓库或普通订阅。

HTTPS 由独立 xray-center-https.service 提供，旧 Xray 保持运行。启动后的本机 TLS/路径自检不代表公网可访问，还需独立从客户端确认 Dynu DNS、证书链、Oracle 网络、Mihomo 与 Shadowrocket 支持情况。地址格式示例（不是已验证的实际地址）：

    https://YOUR_DYNU_DOMAIN:8443/sub/CENTER_TOKEN/multi_clash.yaml
    https://YOUR_DYNU_DOMAIN:8443/sub/CENTER_TOKEN/multi_nodes.txt

中心菜单 10 → 6 → 4 显示本机当前配置的实际 HTTPS 链接。

## 5. 安全迁移、Token 旋转与回退

不要升级后立即关闭旧 HTTP/80，也不要批量修改 Oracle 防火墙。先确保中心能成功 SFTP 同步、成功签发证书并完成 HTTPS 端到端客户端测试，然后在每台子节点通过主菜单 10 → 7 停用脚本管理的公开 HTTP/Nginx 订阅（保留本地 Token/文件），最后人工检查 Ubuntu/Oracle 的无用订阅入站端口；永远保留 Xray 和 SSH 必要入口。

单节点 Token 主菜单 10 → 4 旋转；中心 Token 主菜单 10 → 6 → 5 旋转。刷新会使旧 Token 无法通过仍在使用此文件的发布服务访问，请同步更新客户端。旧 Provider Token 在兼容性迁移期间可能仍由旧 Nginx 或 HTTP 后端提供访问，必须手动检查并清除旧发布入口，不能将 Token 长度升级理解为旧凭据自动失效。

变更 SSH/证书失败时先保留原服务和快照；实际云安全组、Dynu TXT 权限、80 端口续期、Shadowrocket XHTTP 必须在真实 VPS/客户端上验证，代码合并不等于实机部署。
