# Troubleshooting

[← Home](../.github/README.en.md) · [中文](TROUBLESHOOTING.md)

## FAQ

1. If installation succeeds but service is unusable, check whether the server ports are open. You can verify using `https://tcp.ping.pe/ip:port`.
2. Before using SNI configuration, ensure VPS HTTP (80) and HTTPS (443) ports are open.
3. Before using SNI configuration, do not enable CDN protection, otherwise SSL issuance may fail.
4. For upstream/downstream separation details, see [XHTTP: Beyond REALITY][XHTTP] and [xhttp 五合一配置][xhttp 五合一配置].
5. If you encounter 【Could not get nonce, let's try again】 while issuing certificates with SNI, check the [ZeroSSL status page](https://status.zerossl.com/). Most likely ZeroSSL 【Free ACME Service】 is in 【Service disruption】 or 【Service outage】.

## Xray is active but REALITY nodes cannot proxy traffic

1. Check `systemctl status xray`, `journalctl -u xray -n 80 --no-pager` and the listening port.
2. Newer Xray servers (such as v26.10.21) may require Mihomo to send X25519MLKEM768. From Xray-script v2026.10.22.5, Mihomo YAML conditionally sets `reality-opts.support-x25519mlkem768: true` based on the actual installed Xray version. Regenerate the YAML and refresh the client subscription.
3. Shadowrocket does not use Mihomo YAML settings. If even the original QR-code share link fails, check Shadowrocket's REALITY/TLS fingerprint compatibility; rewriting the subscription cannot fix an unsupported client handshake.
4. Test actual proxied requests as well as latency checks. Never post UUIDs, private keys, short IDs or subscription tokens publicly.

## WARP reports that its container IP cannot be obtained

From v2026.10.22.6, the script returns IPs for already-running containers, retries during startup, and preserves existing registration data on failed enable. Verify SOCKS and `warp=on` in Operations & Diagnostics. If it still fails:

```bash
sudo docker ps -a --filter name=xray-script-warp
sudo docker logs --tail 100 xray-script-warp
sudo docker inspect xray-script-warp --format '{{.State.Status}} {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
```

Do not delete the WARP registration directory before collecting diagnostics.

## WARP stuck Connecting / SOCKS connection closed

A running Docker container and open TCP port 40001 do not prove WARP data-path health. Repeated `Connecting` and `curl: (97) connection to proxy closed` indicate a real outage.

Operations & Diagnostics item 3 shows client connection stage, TCP listener, proxied HTTP requests and verified `warp=on` separately, with up to two bounded attempts. Item 13 offers an explicit `yes`-confirmed `warp-cli disconnect` / `connect` without deleting registration, container, Xray settings or subscriptions. WARP-dependent traffic may be interrupted briefly.

Review `docker exec xray-script-warp warp-cli --accept-tos status`, `docker logs --tail 80 xray-script-warp`, MASQUE UDP/443 reachability and ISP path stability if still stuck. Do not automatically change tunnel protocol or delete registration. Xray traffic using Direct routes may remain unaffected.

## WARP Connecting loop: fwmark permission denied

`IPv4 fwmark rule install: Operation not permitted (os error 1)` with `FirewallRepairFailed` means WARP cannot reinstall Linux policy-routing fwmark rules inside Docker. v2026.10.22.8 grants only `--cap-add=NET_ADMIN` for newly created WARP containers, never `--privileged`.

Existing containers cannot gain capabilities through restarts or by updating the installer alone. Check:

```bash
docker inspect xray-script-warp --format '{{json .HostConfig.CapAdd}}'
```

If the result is `null` or lacks `NET_ADMIN`, update Xray-script and choose Operations & Diagnostics → 14 (Repair WARP NET_ADMIN), then explicitly enter `yes`. This applies only to known script-managed container images, default bridge networking and the expected persisted registration bind-mount. The original container is retained stopped with `restart=no`, the new container uses the same image and registration data, and Xray's WARP IP is transactionally updated if Docker changes it. Migration errors attempt restoration of the original.

WARP-routed traffic will be briefly interrupted. Then check item 3 for `NET_ADMIN: granted` and an actual `warp=on` response; repeat probes to assess stability. This does not guarantee the upstream Cloudflare MASQUE/UDP path stays stable; never start both backup and replacement containers simultaneously.

## Centralized subscriptions fail

Test each VPS's standalone node and `proxies.yaml` first, then inspect the center's Provider diagnostics. Regenerate subscriptions after changing credentials, and refresh subscriptions on clients. Subscription URLs contain bearer tokens and must stay private.

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
