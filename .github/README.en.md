<!-- Translated by AI -->
[中文](/README.md) | English

# Xray Management Script :sparkles:

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

## FAQ

1. If installation succeeds but service is unusable, check whether the server ports are open. You can verify using `https://tcp.ping.pe/ip:port`.
2. Before using SNI configuration, ensure VPS HTTP (80) and HTTPS (443) ports are open.
3. Before using SNI configuration, do not enable CDN protection, otherwise SSL issuance may fail.
4. For upstream/downstream separation details, see [XHTTP: Beyond REALITY][XHTTP] and [xhttp 五合一配置][xhttp 五合一配置].
5. If you encounter 【Could not get nonce, let's try again】 while issuing certificates with SNI, check the [ZeroSSL status page](https://status.zerossl.com/). Most likely ZeroSSL 【Free ACME Service】 is in 【Service disruption】 or 【Service outage】.

## Changelog

13. v2026.09.23.9 completes the Xray config lifecycle with health checks, automatic rollback, restore UI, and config export/import.
   1. `apply_xray_config` can restart and verify Xray; restart failure prints systemd/journal diagnostics and restores the pre-apply backup automatically.
   2. Routing add/delete/clear, full config regeneration, and WARP toggle/reset all use the unified safe apply path.
   3. Default routing rules are now built in memory during full config generation and applied once, avoiding intermediate live-config writes.
   4. Configuration Management adds backup listing and manual restore; restore creates another backup of the current config and health-checks Xray afterward.
   5. Add tar.gz config export/import containing Xray config, script config, and a manifest; imports validate JSON and Xray config before applying.
   6. WARP reset refreshes the rebuilt container IP in the Xray `warp` outbound so Xray does not keep a stale Docker address.
12. v2026.09.23.8 introduces the unified `apply_xray_config` safe-write entry point and migrates routing changes first.
   1. Stage the candidate config in the same directory as the live file and validate it with `xray run -test -format=json`.
   2. After validation, back up the current config and preserve the live file's permissions and owner/group.
   3. Replace the live config with a same-filesystem atomic `mv`, avoiding partial writes from `cat > config.json` style updates.
   4. Routing add, single-entry delete, and group clear now call `apply_xray_config` directly with operation context.
   5. Keep `persist_xray_config` temporarily as a compatibility wrapper; full config regeneration and WARP call sites can migrate incrementally later.
11. v2026.09.23.7 adds automatic Xray config backups and shorter Clash/Mihomo subscription tokens.
   1. Before overwriting `/usr/local/etc/xray/config.json`, save the current config under `~/.xray-script/backups/xray/`.
   2. Backups use timestamp + random-suffix names, mode `600`, with the backup directory set to `700`.
   3. Keep only the latest 10 backups by default; failure to prune older backups warns but does not block the current config update.
   4. If backup creation or permission hardening fails, abort the config change instead of overwriting the live config without a backup.
   5. New Clash/Mihomo subscription tokens use 128-bit URL-safe Base64 and are about 22 characters long; existing long tokens are kept until the user rotates the subscription token.
10. v2026.09.23.6 upgrades the Clash Verge Rev / Mihomo config generator to v2.
   1. Enable HTTP/TLS/QUIC sniffing by default with common skip domains.
   2. Add a manual `Proxy` group and an `Auto` URL-test group with 300s interval, lazy testing, 50ms tolerance, and HTTP 204 validation.
   3. Enable `profile.store-selected`, `unified-delay`, and `tcp-concurrent`; disable IPv6 by default.
   4. Enable automatic Mihomo GEO updates with the `memconservative` loader and MetaCubeX GeoIP/GeoSite data.
   5. Add default rules for ad rejection, LAN direct, Steam/Microsoft China direct, CN domains/IPs direct, and send everything else to `Proxy`.
   6. Do not force TUN/DNS into the subscription so local Clash Verge networking preferences remain client-managed.
9. v2026.09.23.5 improves startup diagnostics and self-test reliability for the lightweight Clash/Mihomo HTTP subscription backend.
   1. Local subscription checks now force `curl --noproxy '*'` so `127.0.0.1` health checks cannot be redirected through `http_proxy/HTTP_PROXY`.
   2. Startup performs several short retries to avoid false failures while the systemd service is still becoming ready.
   3. On systemd startup or local self-test failure, the script prints `systemctl status` and recent `journalctl` output before rollback.
   4. Self-test failures also display listeners on the selected port to distinguish a service-start problem from a request-path problem.
8. v2026.09.23.4 fixes the incorrect coupling between Clash/Mihomo remote subscriptions and Xray SNI mode.
   1. Compatible Vision, XHTTP, Fallback, and SNI configs can all publish remote subscriptions; `.xray.tag == SNI` is no longer required.
   2. Subscription hosting is independent from the Xray data path: reuse an existing Nginx HTTPS site when available, otherwise optionally start a lightweight HTTP static subscription service on port 80 by default or a user-selected port.
   3. The lightweight HTTP backend serves only the random-token `clash.yaml` path, has no directory listing or web UI, and is managed by systemd.
   4. The HTTP backend self-tests the local subscription URL after startup; port conflicts or startup failures do not produce an enabled subscription state.
   5. Plain HTTP is unencrypted and the subscription contains proxy credentials, so the script displays an explicit warning before enabling it.
7. v2026.09.23.3 adds Clash Verge Rev / Mihomo config and subscription support.
   1. Generates an importable Mihomo YAML from the current Xray config.
   2. Supports Vision+Reality, VLESS+XHTTP+Reality, Fallback, and compatible Reality/XHTTP/TLS-CDN nodes in SNI mode.
   3. SNI + Nginx can publish a random-token HTTPS subscription without adding a resident service.
   4. Supports viewing, refreshing, rotating the subscription token, and disabling remote delivery; Nginx changes are backed up and rolled back when validation fails.
   5. Mihomo currently does not support VLESS+mKCP or Trojan+XHTTP, so the script explicitly refuses to generate invalid configs for those combinations.
6. v2026.09.23.2 aligns the fork's maintainer and repository branding.
   1. README and terminal banners now display `miauyle/Xray-script`.
   2. Script repository/maintainer metadata now points to the current fork.
   3. Original MIT copyright notices remain preserved in LICENSE and required copyright notices.
5. v2026.09.23.1 adds management for existing custom routing rules.
   1. Lists `block-ip`, `block-domain`, `warp-ip`, and `warp-domain` custom rules.
   2. Deletes individual entries by index and removes an empty rule group automatically.
   3. Clears an entire custom rule group with confirmation.
   4. Delete/clear changes are validated by Xray before the live config is replaced and the service is restarted.
4. v2026.09.23 fixes custom routing rule writes and hardens Xray config updates.
   1. Fixes WARP/block routing input being read from `XRAY_CONFIG` instead of `CONFIG_DATA`, which could turn a valid domain into an empty string entry.
   2. Routing input now trims whitespace, drops empty values, and deduplicates entries; empty rules are rejected.
   3. Candidate Xray configs are validated before replacing the live config; validation failure keeps the existing config unchanged.
   4. Installation, update, and config download URLs now stay on `miauyle/Xray-script`.
1. v2025.11.19 resolves the issue where WARP was enabled without log limits, causing container logs to keep growing and eventually fill up disk space.
   1. Users who already enabled WARP routing can select 【Reset WARP Proxy】 in 【Manage Configuration】 -> 【Routing Management】 to clear container logs and reset WARP Proxy.
   2. Log limits have been added; just enable WARP directly when needed.
2. v2026.03.01 adds CA vendor switching. When switching CA vendor, the script force re-issues certificates for existing domains (`domain`, `cdn`, and `custom_sites[].domain`). It writes the new CA only after all re-issues succeed; if any step fails, it automatically rolls back to the original CA and restores related settings, preventing acme auto-renew from breaking.
   1. Force re-issue bypasses the "Domains not changed" check (acme.sh skip scenario).
   2. Watch out for CA issuance rate limits (for example, Let's Encrypt limits).
3. v2026.03.17 adds SNI custom domain and reverse proxy app management, allowing multiple extra HTTPS reverse proxy sites without affecting the existing `Reality(domain)` and `CDN(cdn)` sites.
   1. Menu path: `Manage Configuration -> SNI Configuration -> Manage custom domains and reverse proxy apps`
   2. Supports list / add / edit / delete, with an independent certificate, `sites-available/<domain>.conf`, stream mapping, and UDS for each custom site.
   3. `stream.conf` is rebuilt from `domain`, `cdn`, and `custom_sites`; UDS names use the first `12` hex chars of `SHA-256(domain)` plus the port.
   4. Proxy targets support port-only input or full `http(s)://host:port` URLs; port-only input is normalized to `http://127.0.0.1:<port>`; URLs containing `path`, `query`, or `fragment` are rejected.
   5. Editing only the upstream target skips certificate re-issuance; changing the domain issues the new certificate first and then switches over with rollback on failure; deleting a site also removes the site config, symlink, renew record, and certificate directory.
   6. A custom site domain must not duplicate `domain`, `cdn`, or another custom site domain; CA switching and "force renew all certificates" also cover custom site domains.
   7. Custom sites are "pure reverse proxy sites". They do not include Xray `xhttp/grpc` paths and are not managed by the Cloudreve integration; the proxy layer does not inject an extra `Content-Security-Policy`, so CSP should be controlled by the upstream application.

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
- This version adds the backup mechanism only; there is no restore menu yet

A backup creation or permission failure aborts the config change. Failure to prune an older backup only emits a warning.

### Recovery and config migration

Under `Configuration Management -> Config Backup & Recovery` you can:

- List recent automatic Xray backups.
- Restore a selected backup; the current config is backed up again first, then Xray is restarted and verified.
- Export a bundle under `~/.xray-script/exports/` containing `xray-config.json`, `script-config.json`, and a manifest.
- Import a bundle created by the script; JSON and Xray configuration are validated before any apply.

When an apply that requires restart makes Xray fail to start, the script automatically attempts to restore the pre-apply backup and starts Xray again.

## How to Use

* Download

  ```sh
  wget --no-check-certificate -O ${HOME}/Xray-script.sh https://raw.githubusercontent.com/miauyle/Xray-script/main/install.sh
  ```

* Usage
  * Launch UI

    ```sh
    bash ${HOME}/Xray-script.sh
    ```

  * Quick install Vision

    ```sh
    bash ${HOME}/Xray-script.sh --vision
    ```

  * Quick install XHTTP

    ```sh
    bash ${HOME}/Xray-script.sh --xhttp
    ```

  * Quick install Fallback

    ```sh
    bash ${HOME}/Xray-script.sh --fallback
    ```

* Quick start (UI)

  ```sh
  wget --no-check-certificate -O ${HOME}/Xray-script.sh https://raw.githubusercontent.com/miauyle/Xray-script/main/install.sh && bash ${HOME}/Xray-script.sh
  ```

## Script UI

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
WARP Proxy : Running
-------------------------------------------

--------------- Xray-script ---------------
 Version      : v2025-07-25
 Description  : Xray Management Script
----------------- Install -----------------
1. Full installation
2. Install/Update only
3. Uninstall
----------------- Operation ----------------
4. Start
5. Stop
6. Restart
---------------- Configuration -------------
7. Share links and QR codes
8. Statistics
9. Manage configuration
-------------------------------------------
0. Exit
```

## Tested Systems

| Platform | Version    |
| -------- | ---------- |
| Debian   | 10, 11, 12 |
| Ubuntu   | 20, 22, 24 |
| CentOS   | 7, 8, 9    |
| Rocky    | 8, 9       |

The distributions above were tested on Vultr.

Other Debian-based and Red Hat-based systems may work, but are untested and may have issues.

## Installation Time Notes

SNI configuration is intended for long-term use after one setup, and is not suitable for repeated reinstall/reset, which consumes significant time. If you need to change configuration or domain, use the options in the management UI.

After switching to a non-SNI config, Nginx will be stopped but kept on the machine. Re-enabling SNI will not reinstall Nginx.

### Installation Time Reference

Installation flow:

Update package index -> install dependencies -> [install Docker] -> [install Cloudreve] -> [install Cloudflare-warp] -> install Xray -> install Nginx -> issue certificate -> apply configuration

**Average install time on a 1-core 1GB server (for reference only):**

| Item                | Duration  |
| ------------------- | --------- |
| Update package index| 0-10 min  |
| Install dependencies| 0-5 min   |
| Install Docker      | 1-2 min   |
| Install Cloudreve   | 3-5 min   |
| Install Cloudflare-warp | 3-5 min |
| Install Xray        | < 0.5 min |
| Install Nginx       | 13-15 min |
| Issue certificate   | 1-2 min   |
| Apply configuration | < 0.5 min |

### Why does SNI installation take so long?

Nginx in this script is managed by source compilation.

Compared with installing prebuilt binaries, compilation advantages are:

1. Better runtime performance (compiled with -O3 optimization)
2. Newer software versions

The downside is long compilation time.

## Install Paths

**Xray-script:** `/usr/local/xray-script`

**Nginx:** `/usr/local/nginx`

**Cloudreve:** `$HOME/.xray-script/docker/cloudreve`

**Cloudflare-warp:** `$HOME/.xray-script/docker/warp`

**Xray:** See **[Xray-install](https://github.com/XTLS/Xray-install)**

## Dependency List

When using SNI configuration, the script may install the following dependencies:

| Purpose                            | Debian-based                         | Red Hat-based        |
| ---------------------------------- | ------------------------------------ | -------------------- |
| yumdb set (mark package manually installed) |                              | yum-utils            |
| dnf config-manager                 |                                      | dnf-plugins-core     |
| IP retrieval                       | iproute2                             | iproute              |
| DNS resolution                     | dnsutils                             | bind-utils           |
| wget                               | wget                                 | wget                 |
| curl                               | curl                                 | curl                 |
| wget/curl https                    | ca-certificates                      | ca-certificates      |
| kill/pkill/ps/sysctl/free          | procps                               | procps-ng            |
| epel repository                    |                                      | epel-release         |
| epel repository                    |                                      | epel-next-release    |
| remi repository                    |                                      | remi-release         |
| Firewall                           | ufw                                  | firewalld            |
| **Build basics:**                  |                                      |                      |
| Download source files              | wget                                 | wget                 |
| Extract tar source files           | tar                                  | tar                  |
| Extract tar.gz source files        | gzip                                 | gzip                 |
| gcc                                | gcc                                  | gcc                  |
| g++                                | g++                                  | gcc-c++              |
| make                               | make                                 | make                 |
| **acme.sh dependencies:**          |                                      |                      |
|                                    | curl                                 | curl                 |
|                                    | openssl                              | openssl              |
|                                    | cron                                 | crontabs             |
| **Build openssl:**                 |                                      |                      |
|                                    | perl-base (included in libperl-dev) | perl-IPC-Cmd         |
|                                    | perl-modules-5.32 (included in libperl-dev) | perl-Getopt-Long |
|                                    | libperl5.32 (included in libperl-dev) | perl-Data-Dumper   |
|                                    |                                      | perl-FindBin         |
| **Build Brotli:**                  |                                      |                      |
|                                    | git                                  | git                  |
|                                    | libbrotli-dev                        | brotli-devel         |
| **Build Nginx:**                   |                                      |                      |
|                                    | libpcre2-dev                         | pcre2-devel          |
|                                    | zlib1g-dev                           | zlib-devel           |
| --with-http_xslt_module            | libxml2-dev                          | libxml2-devel        |
| --with-http_xslt_module            | libxslt1-dev                         | libxslt-devel        |
| --with-http_image_filter_module    | libgd-dev                            | gd-devel             |
| --with-google_perftools_module     | libgoogle-perftools-dev              | gperftools-devel     |
| --with-http_geoip_module           | libgeoip-dev                         | geoip-devel          |
| --with-http_perl_module            |                                      | perl-ExtUtils-Embed  |
|                                    | libperl-dev                          | perl-devel           |

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
