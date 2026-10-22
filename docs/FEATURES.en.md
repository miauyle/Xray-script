# Features and Configuration

[← Home](../.github/README.en.md) · [中文](FEATURES.md) · [Troubleshooting](TROUBLESHOOTING.en.md)

## Supported features

* A pure Shell-based Xray management script
* Optional configurations:
  * mKCP (VLESS-mKCP-seed)
  * Vision (VLESS-Vision-REALITY)
  * XHTTP (VLESS-XHTTP-REALITY)
  * Trojan (Trojan-XHTTP-REALITY)
  * Fallback (includes VLESS-Vision-REALITY and VLESS-XHTTP-REALITY)
  * SNI (includes Vision_REALITY, XHTTP_REALITY, XHTTP_TLS)
* SNI configuration uses Nginx to implement SNI traffic splitting, suitable for CDN routing, upstream/downstream separation, and multi-site coexistence
* SNI share links support upstream/downstream separation (upstream xhttp+TLS+CDN | downstream xhttp+Reality, upstream xhttp+Reality | downstream xhttp+TLS+CDN)
* SNI configuration supports managing custom domains and reverse proxy apps, with independent certificates, site configs, stream mappings, and UDS per site
* Rule configuration and custom input:
  * Block BitTorrent traffic (optional)
  * Block China-bound IP traffic (optional)
  * Ad blocking (optional)
  * Add custom WARP Proxy routing rules
  * Add custom blocking routing rules
* Toggle Cloudflare WARP Proxy ( :whale: Docker deployment)
* Toggle geodata auto-update
* Xray port defaults and custom input:
  * VLESS-mKCP: randomly generated
  * ALL-REALITY: 443
* UUID defaults and custom input:
  * Randomly generated
  * Custom standard UUID input
  * Non-standard UUID mapped to UUID
* kcp(seed) and trojan(password) defaults and custom input:
  * Randomly generated (example: cw-GEMDYgwIV3_g#)
  * Custom input
* target defaults and custom input:
  * Randomly selected from serverNames.json
  * TLSv1.3 and H2 validation for custom target
  * Automatic serverNames lookup for custom target
* shortId defaults and custom input:
  * Random generation (default two shortIds, e.g. 01234567, 0123456789abcdef)
  * Custom shortId input
  * If input is 0 to 8, shortIds with length 0-16 are auto-generated
  * Supports multiple values separated by commas
* path defaults and custom input:
  * Randomly generated (example: /8ugSUeNJ.9OEnTErb.dVZMUAFu)
  * Custom input (example: /8ugSUeNJ, with or without `/`)

## Share Links

Implemented based on [VMessAEAD / VLESS share link proposal](https://github.com/XTLS/Xray-core/discussions/716) and [v2rayN](https://github.com/2dust/v2rayN). If other clients do not work, adjust based on the generated share link manually.

In SNI configuration, CDN share links use H2 as default ALPN. If you need H3, modify it in your client.

### Clash Verge Rev / Mihomo

**Config generator v2 defaults:**

- Sniffer: HTTP / TLS / QUIC.
- Policy groups: manual `Proxy` + `Auto` URL test.
- GEO: automatic GeoIP / GeoSite updates.
- Routing: reject ads, direct LAN, direct Steam/Microsoft China services, direct CN domains/IPs, then send the rest to `Proxy`.
- IPv6 disabled by default; `unified-delay`, `tcp-concurrent`, and `profile.store-selected` enabled.
- TUN / DNS are intentionally omitted and remain managed by the local Clash Verge client.

The main menu now includes `Clash/Mihomo Config & Subscription`:

- `Generate/refresh local YAML`: writes `~/.xray-script/clash/clash.yaml`.
- `Enable/refresh remote subscription`: independent of the Xray protocol type; reuses an existing Nginx HTTPS site when available, otherwise can start a lightweight HTTP static subscription service.
- `Show subscription info`: prints the local YAML path and current remote URL.
- `Rotate subscription URL token`: invalidates the old URL immediately.
- `Disable remote subscription`: disables the active subscription backend while keeping the local YAML.

Remote subscription hosting is independent from the Vision/Reality/XHTTP data path. With an existing Nginx HTTPS site, URLs look like `https://domain/sub/<random-token>/clash.yaml`; without reusable HTTPS, the optional lightweight HTTP backend prompts for a port. Press Enter for the default port `80`, or enter another value from `1-65535`. Port 80 produces `http://server-ip/sub/<random-token>/clash.yaml`; a custom port produces `http://server-ip:<port>/sub/<random-token>/clash.yaml`. The script does not silently choose another port when the selected one is busy. Plain HTTP is unencrypted and the subscription contains proxy credentials, so use it only if you accept that risk and rotate the token if the URL may have leaked.

The generator currently supports Vision+Reality, VLESS+XHTTP+Reality, Fallback, and compatible VLESS nodes in SNI mode. Mihomo does not currently support VLESS+mKCP or Trojan+XHTTP, so those combinations are rejected instead of generating misleading configs.

## Automatic Xray config backups

Before replacing the live Xray configuration, the script automatically saves the current version:

- Live config: `/usr/local/etc/xray/config.json`
- Backup directory: `~/.xray-script/backups/xray/`
- Retention: latest 10 backups
- No empty backup is created on first install when the live config does not exist yet
- Backup restore is available under Operations & Diagnostics

A backup creation or permission failure aborts the config change. Failure to prune an older backup only emits a warning.


## One center, independent VPS Providers (v2026.10.16.4)

Each regular VPS publishes both /sub/<single-token>/clash.yaml (standalone Mihomo subscription) and /sub/<single-token>/proxies.yaml (pure Provider) using the SAME existing single token. It does not enable aggregation or track any other servers.

Enable the aggregation center on ONE VPS only after its standalone subscription is configured. Add the other standalone VPS Provider URLs in the center's menu (Clash → Central aggregator). The center keeps its existing multi-server.json and multi-token and publishes multi_clash.yaml for Mihomo and multi_nodes.txt for Shadowrocket. The center may itself be a proxy VPS. A center outage interrupts subscription updates but does not normally disconnect cached client proxy nodes. There is no automatic center failover.

For migration: upgrade all VPSs, regenerate each standalone YAML, refresh each VPS's remote subscription publication (restart the existing Python HTTP server or reload Nginx), update remote Provider URLs on the chosen center, then disable aggregation on every other VPS. The upgrade does NOT silently disable previously enabled peer configurations. Old Provider token URLs remain readable temporarily for compatibility; new standalone Providers use their ordinary single-token URL. Do not revoke legacy credentials until the center uses the new URLs. No dedicated Provider-token rotation menu remains.

The center menu item 8 (`Clash → Central aggregator → List remote Providers`) displays all stored remote VPS names and full Provider URLs, including bearer tokens, only when explicitly requested. Never share its output or screenshots. Routine center status continues hiding remote credentials.

Mihomo Proxy Providers are updated by the client and Shadowrocket subscriptions are aggregated by the center. Only the center maintains a peer list, and only the center exposes the multi-server subscription URL. Shadowrocket XHTTP compatibility still requires real client testing.


## Operations & Diagnostics

Main-menu item **11. Operations & Diagnostics** provides the maintenance tools in one place:

- **Doctor** checks Xray JSON/core validation, systemd status, listening port, backups, WARP container/SOCKS egress, WARP fallback wiring, and the Clash HTTP subscription service.
- **Logs** shows recent Xray systemd/error.log, WARP Docker logs, and Clash subscription service logs.
- **WARP status & egress** queries Cloudflare trace through the WARP SOCKS path and reports container status, egress IP, location, and WARP state.
- **WARP Direct fallback** uses Xray `observatory + balancer.fallbackTag=direct`; only rules explicitly routed to WARP participate.
- **Backup restore** keeps 10 automatic Xray backups by default. New backups also pair the script state; legacy Xray-only backups remain restorable.
- **Export/import** bundles script + Xray config into a mode-`600` `tar.gz`. WARP container networking is host-local, so after moving to another VPS run Doctor/WARP reset to reconfirm it.
- **Direct egress family** selects Auto / IPv4 / IPv6 through Xray Freedom `sockopt.domainStrategy`.
- **TCP BBR** optionally displays the current state, enables persistent BBR + fq, or restores original settings without changing Xray.

### TCP BBR (optional)

Choose **11. Operations & Diagnostics → 9. TCP BBR network tuning** to inspect, enable, or restore settings. It is **not enabled automatically** during Xray installation or updates.

The script checks kernel availability, optionally tries `modprobe tcp_bbr` (without installing a kernel), and sets TCP BBR plus the `fq` default qdisc. Only `/etc/sysctl.d/99-xray-script-bbr.conf` is written, and previous runtime values are backed up to `~/.xray-script/network/bbr-original.conf`. Other sysctl configuration files remain untouched. It refuses to overwrite an unrecognized drop-in or operate without a valid original-value backup.

CLI: `bash core/handler.sh --bbr status|enable|restore` (from the installed repository; root is required to enable or restore). BBR does not guarantee faster routes or fix physical packet loss. Other sysctl drop-ins can still override these values at boot.

### Safe apply and automatic rollback

All Xray config writes converge on `apply_xray_config`:

```text
candidate → xray -test → automatic backup → atomic replace → restart check
                                                        ↓ failure
                                      restore old Xray + script state
```

Routing, protocol regeneration, WARP operations, backup restore/import, and Direct/WARP fallback reuse this path. Protocol regeneration keeps a pending script-state snapshot across handler processes and clears it only after the new Xray config is successfully applied.

### Oracle Ubuntu host management

Operations & Diagnostics offers firewall (10), conntrack_max (11), and Swap (12). Host firewall rules are never opened without a terminal confirmation. With UFW active, UFW persists the rule; otherwise iptables rules are inserted without flushing any existing rules or modifying SSH and are persisted through a dedicated xray-script-firewall.service. Cloud VCN Security List/NSG rules remain a separate requirement; a host firewall ACCEPT rule does not prove external reachability.

conntrack_max uses sysctl -w and verifies the kernel value immediately, while dedicated sysctl.d and modules-load.d files maintain the setting after reboot. The original kernel value is backed up for restore. Swap uses /var/lib/xray-script/swapfile, verifies disk availability, permissions, mkswap/swapon, and adds only a managed fstab entry. Removal affects only managed swap and fails safely if swapoff is rejected. Btrfs automatic swap creation is unsupported.

CLI from installed repository: bash core/handler.sh --host firewall status 443 tcp ; --host conntrack set 16384 ; --host swap add 1.

## Acknowledgements

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

**This script is for study and communication only. Do not use it for illegal purposes. Illegal acts on the network are still illegal and will be punished by law.**

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
