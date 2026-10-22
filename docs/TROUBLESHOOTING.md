# 故障排查

[← 返回首页](../README.md) · [English](TROUBLESHOOTING.en.md)

## 问题

1. 如果安装成功，但无法使用，请检查服务器是否开启对应端口，可通过 `https://tcp.ping.pe/ip:port` 验证服务器端口是否开放。
2. 使用 SNI 配置前，请确保 VPS 的 HTTP(80) 与 HTTPS(443) 端口开放。
3. 使用 SNI 配置前，请不要开启 CDN 保护，不然无法正常申请 SSL 证书。
4. 上下行分离详情请看 [XHTTP: Beyond REALITY][XHTTP] 与 [xhttp 五合一配置][xhttp 五合一配置] 了解。
5. 使用 SNI 获取证书时遇到 【Could not get nonce, let's try again】 请查看 [ZeroSSL 状态页](https://status.zerossl.com/)，大概率是 ZeroSSL 的【Free ACME Service】处于 【Service disruption】或【Service outage】状态。

## Xray 服务正常、REALITY 节点却无法代理

1. 在 VPS 检查 `systemctl status xray`、`journalctl -u xray -n 80 --no-pager`，并确认 443 端口正常监听。
2. 对较新 Xray-core（如 v26.10.21），Mihomo 客户端可能需要 `reality-opts.support-x25519mlkem768: true`。脚本从 v2026.10.22.5 起按服务端 Xray 版本有条件生成该配置，需在 VPS 重新生成 YAML 并在客户端刷新订阅。
3. Shadowrocket 无法识别 Mihomo YAML 参数；即使直接扫码导入原始 VLESS 链接也失败时，应检查 Shadowrocket 自身的 REALITY / TLS 指纹兼容性。不能通过修改 Mihomo 订阅解决客户端协议栈问题。
4. 在客户端验证实际代理请求；单纯 Ping/延迟测试失败并不等于 TCP 端口不可达。不要公开 UUID、REALITY 私钥、shortId 或订阅 Token。

## WARP 开启时报容器 IP 获取失败

从 v2026.10.22.6 起修复了已有容器运行时不返回 IP、首次启动重试及失败清理误删的问题。更新脚本后可使用「运维与诊断 → WARP 状态与出口」验证 SOCKS 与 `warp=on`。若仍失败，在 VPS 查看：

```bash
sudo docker ps -a --filter name=xray-script-warp
sudo docker logs --tail 100 xray-script-warp
sudo docker inspect xray-script-warp --format '{{.State.Status}} {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
```

**不要在排障前随意删除 Docker 容器或 WARP 注册目录。**

## WARP 长期 Connecting / SOCKS 连接被关闭

容器 `running`、`172.17.0.2:40001` 端口可达不代表实际 WARP 数据通路可用。连续出现 `Connecting` 和 `curl: (97) connection to proxy closed`，应作为真实出口故障排查。

「运维与诊断 → 3. WARP 状态与出口」现在分别显示连接阶段、SOCKS TCP 端口、代理 HTTP 请求与实际 `warp=on`；只进行两次有限探测，不修改配置。若持续失败，可使用「13. WARP 轻量重连」，手动输入 `yes` 才执行 `disconnect` / `connect`，保留原有 WARP 注册信息、Docker 容器、Xray 配置与订阅。依赖 WARP 的流量可能短暂中断。

若仍然 Connecting，需检查 Docker 日志、Cloudflare MASQUE UDP/443 可达性与稳定性；请勿自动修改隧道协议或删除注册信息。

```bash
docker exec xray-script-warp warp-cli --accept-tos status
docker exec xray-script-warp warp-cli --accept-tos settings
docker logs --tail 80 xray-script-warp
curl --noproxy '' --proxy socks5h://172.17.0.2:40001 -v --connect-timeout 5 --max-time 20 https://www.cloudflare.com/cdn-cgi/trace
```

如果 Xray 默认经 Direct 出口，只有特定规则走 WARP，那么 WARP 故障不一定意味着全部 Xray 节点不可用。

## 多机订阅节点不可用

先测试各 VPS 的单机节点和 `proxies.yaml`，再检查中心的远端 Provider。多机菜单提供 Provider 诊断；更新 Xray 凭据后应重新生成订阅并在客户端刷新。订阅 URL 自带访问 Token，勿公开完整 URL。

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
