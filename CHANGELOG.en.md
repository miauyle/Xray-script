# Changelog

[Home](.github/README.en.md) · [中文](CHANGELOG.md)

Detailed historical release notes are archived here. Original numbering is retained and may not be strictly chronological.

29. v2026.10.22.5 fixes fresh **Xray 26.10.21** installs failing with `unsupported config file extension`. Temporary files for live config application, rollback and mKCP compatibility probes now end in `.json`; newer Xray releases inspect the extension despite `-format=json`. Both v26.3.27 and v26.10.21 are covered by real binary apply/rollback tests. Mihomo REALITY nodes include `reality-opts.support-x25519mlkem768: true` only when the **installed** Xray core is v26.9.8 or newer; old/unknown versions are left unchanged. The flag propagates through single-server `clash.yaml`, local `proxies.yaml`, and the center's local entries in `multi_clash.yaml`; each remote provider independently emits its own compatible option. `client-fingerprint: chrome` remains in place. Raw VLESS URI and Shadowrocket subscription handling are unchanged. Regenerate your YAML subscriptions and refresh the client after updating the script.

28. v2026.10.22.4 restores `/var/log/xray/access.log` and `/var/log/xray/error.log` in all six protocol templates. Before Xray upgrade, config change, and service start, inspect the effective systemd User/Group and ensure log paths are writable. For incompatible files, preserve original contents in timestamped root-only backups before recreating mode-0640 files for the configured service identity. Already writable logs are never truncated or rotated by this routine. Symlinks, hardlinks, and unexpected ownership fail closed. The Operations log view includes both access and error files. CI exercises actual root-to-nobody migration and real Xray file-log creation.


27. v2026.10.22.3 hardens Xray-core upgrades: generated templates log to stdout/systemd journal rather than writable files, avoiding stale access.log/error.log ownership failures; validation failures now show the underlying Xray error without dumping the candidate configuration. Core upgrades verify the previously installed configuration, restart an already-running service, check that it survives two seconds, and restore the old binary on failure. Deprecated `kcpSettings.seed` is migrated to FinalMask using the same password, probing the active core to select `mkcp-legacy` or `mkcp-aes128gcm`; older share links remain available for legacy clients, while modern Xray clients must use FinalMask configuration. CI adds regression tests plus actual v26.3.27/v26.10.21 binary/template smoke checks. Existing configurations and logs are not automatically overwritten or deleted by a script update.

25. v2026.10.17.2 adds `GEOSITE,apple-cn,DIRECT` and `GEOSITE,apple,DIRECT` to generated Mihomo routing between ad blocking and China rules, covering App Store, iCloud and Apple updates even when overseas CDN IPs are used. Both standalone and central aggregate subscriptions inherit this change. Refresh YAML on the center and reload Clash Verge Rev to apply; Shadowrocket node-only subscriptions are unaffected. Some region-sensitive services may still need a targeted rule override.

24. v2026.10.17.1 improves the compact Mihomo default routing rules. Route GEOSITE private and local-domain suffixes plus GEOIP private directly, then reject known ad domains, route mainland China domains/IPs directly, and use MATCH,Proxy for everything else. Replace GEOIP,lan with GEOIP,private and allow DNS resolution for GEOIP,CN. Standalone and center configurations inherit the same rules; no DNS/TUN overrides are added. Regenerate VPS YAML and refresh the client subscription to apply.

23. v2026.10.16.5 adds center menu item 8 to list configured remote VPS labels and their full Provider URLs on demand. URL bearer tokens remain hidden from routine status output. No subscription changes.

22. v2026.10.16.4 replaces equal-peer setup with a single center. Each standalone VPS independently publishes `proxies.yaml` under its original single subscription token; only the selected center stores peers. Old Provider token paths remain available during migration, but there is no new dedicated Provider token rotation.

21. v2026.10.16.3 switches generated Clash/Mihomo `geox-url` GeoSite and GeoIP sources from the optional testingcf.jsdelivr.net mirror to official MetaCubeX GitHub Release assets. This avoids relying on a CDN mirror that may deliver non-protobuf content in some networks. The error `invalid GeoSite database file: proto: cannot parse invalid wire-format data` may also require deleting a previously corrupted client cache. This does not change Xray nodes; update the subscription before retrying. GitHub reachability varies by network.


20. v2026.10.16.2 adds consented local IPv4 firewall port checks before Xray/HTTP listeners, opt-in conntrack_max runtime + boot persistence, and separate managed swap files (1–32 GiB). Oracle Security List/NSG cloud ingress still requires separate configuration. Includes mocked integration tests.

19. v2026.10.16.1 fixes stale remote-node credentials in multi-server subscriptions. After a successful Xray regeneration, existing published single and multi subscriptions are refreshed without rolling back working Xray on refresh failure. Mihomo retries remote Providers every five minutes; Shadowrocket only falls back to cached remote nodes for up to 12 hours. Add **Multi-server subscriptions → 9. Diagnose Providers** to compare published UUID/Reality public keys with running Xray and verify remote Provider reachability without logging secrets. Clients must still refresh their subscriptions and Providers.



18. v2026.10.15.3 adds a single Shadowrocket subscription URL for all VPS peers: reuse the existing peer list and MULTI_TOKEN, export Base64 VLESS Reality/XHTTP links, retain last-known-good remote nodes, and refresh Nginx snapshots with a five-minute one-shot timer.


17. v2026.10.15.2 fixes false failures reported after successful Xray config generation.
   1. Explicitly return success from `handler_xray_config` when there is no pending script-state snapshot; the optional EXIT-trap cleanup must not cause a nonzero result.
   2. Stop printing Reality Private Keys to installation logs.
   3. Add regression tests for fresh installation and pending snapshot handling.

16. v2026.10.15.1 adds optional TCP BBR management and updates the version previously missed when multi-VPS subscriptions were introduced.
   1. Add optional BBR + fq status/enable/restore under Operations & Diagnostics.
   2. Check kernel support, avoid kernel upgrades and Xray restarts, and persist only in Xray-script's own `/etc/sysctl.d/99-xray-script-bbr.conf` drop-in.
   3. Save original congestion control and qdisc, attempt rollback on failure and safely restore the original values.
   4. Include the equal-peer `multi_clash.yaml`, Mihomo Proxy Providers, and scoped tokens delivered in PR #15 in the version notes, with BBR regression tests.


15. v2026.09.23.11 fixes WARP health checks accidentally bypassing the configured proxy.
   1. Fix `ops_warp_trace` using `--noproxy '*'`, which disabled the explicit SOCKS proxy and incorrectly reported the VPS direct egress.
   2. Use `--noproxy \"\"` plus explicit `socks5h://<container>:40001` so WARP is forced even when `NO_PROXY` exists in the environment.
   3. Add WARP client status/mode to the status view and separate `SOCKS reachable` from `WARP data path`.
   4. Doctor now requires Cloudflare trace to return `warp=on` or `warp=plus`; `warp=off` is a failure.
14. v2026.09.23.10 carries forward the remaining useful Xray restart reliability improvements from superseded PR #11.
   1. After restart/start, check the active state up to five times with short delays to avoid transient systemd readiness false negatives.
   2. When a post-apply restart fails, print `systemctl status xray` and the latest 40 journal lines before automatic rollback.
   3. Manual Xray restart now uses the same checked restart path; failures are no longer silently ignored and include the same diagnostics.
   4. Ensure the Xray systemd unit is enabled after a successful start/restart.
13. v2026.09.23.9 completes the operations and safety-management features.
   1. Finish `apply_xray_config` migration with validation, automatic backup, atomic replace, and restart-failure rollback.
   2. Add backup restore, config export/import, Doctor, and Xray/WARP/Clash log views.
   3. Add WARP container/SOCKS/egress IP/country checks and optional Direct fallback using Xray observatory + balancer.
   4. Unify Direct/WARP/Block routing management and persist custom routing state.
   5. Add Auto/IPv4/IPv6 Direct egress policy and preserve it across protocol regeneration.
   6. Add a central Operations & Diagnostics menu; automatic backups now pair script state so protocol reconfiguration can roll back consistently.
   7. Add lightweight CI syntax validation for core Shell, JSON, and the Clash HTTP Python service.
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