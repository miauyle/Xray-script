<!-- Translated by AI -->
[中文](../README.md) | English

# Xray-script

A Shell-based installer and manager for Xray-core, including REALITY / XHTTP configurations, subscriptions, routing, and diagnostics.

**Current script version: `v2026.10.22.6`** · [Full changelog](../CHANGELOG.en.md)

## Quick start

Run on a Linux VPS with appropriate administrative privileges. Check SSH access and cloud firewall rules, and back up existing configurations before installation.

```bash
wget -O "$HOME/Xray-script.sh" https://raw.githubusercontent.com/miauyle/Xray-script/main/install.sh
bash "$HOME/Xray-script.sh"
```

Optional direct setup:

```bash
bash "$HOME/Xray-script.sh" --vision   # VLESS Vision REALITY
bash "$HOME/Xray-script.sh" --xhttp    # VLESS XHTTP REALITY
bash "$HOME/Xray-script.sh" --fallback # Vision + XHTTP
```

See [Installation and Usage](../docs/INSTALLATION.en.md) for supported systems, SNI setup, commands, and requirements.

## Main features

| Area | Capabilities |
| --- | --- |
| Xray modes | Vision, XHTTP, Fallback, SNI, mKCP and Trojan options |
| Subscriptions | VLESS links / QR codes, Mihomo YAML, Shadowrocket node subscriptions |
| Multi-VPS | One aggregation center with independently published VPS Providers |
| Routing | Direct / Block / WARP rules, optional WARP egress and Direct fallback |
| Operations | Config validation and rollback, backups, Doctor, logs, BBR, Swap, conntrack and firewall checks |
| Nginx / SNI | TLS/CDN routing, custom domains and reverse proxy sites |

For the details, read [Features and Configuration](../docs/FEATURES.en.md).

## Subscription notes

- **Single VPS:** use menu 10 to generate Mihomo YAML and optionally publish a remote subscription.
- **Multiple VPSs:** each VPS publishes a Provider; only one VPS manages the central `multi_clash.yaml` and Shadowrocket aggregation.
- **Security:** subscription URLs carry access tokens; publishing over HTTP does not encrypt credentials.
- **Compatibility:** newer Xray REALITY versions may require X25519MLKEM768 on Mihomo. The generator sets this based on the server core version; Shadowrocket must be tested separately.

## Documentation

| Guide | Scope |
| --- | --- |
| [Installation and Usage](../docs/INSTALLATION.en.md) | Commands, menu, tested systems, duration, dependencies |
| [Features and Configuration](../docs/FEATURES.en.md) | Protocols, SNI, subscriptions, multi-VPS, backups and operations |
| [Troubleshooting](../docs/TROUBLESHOOTING.en.md) | Connectivity, REALITY, Shadowrocket, WARP and subscriptions |
| [Changelog](../CHANGELOG.en.md) | Historical versions and migration notes |

## Safety

This script manages network services and configuration files. Back up existing state; cloud Security Lists / NSGs must be configured separately. Updating the script does not automatically regenerate running Xray configuration or subscriptions.

Built around [Xray-core](https://github.com/XTLS/Xray-core), [REALITY](https://github.com/XTLS/REALITY) and [XHTTP](https://github.com/XTLS/Xray-core/discussions/4113). See the [full acknowledgements](../docs/FEATURES.en.md).

For lawful study, communication and network administration only.
