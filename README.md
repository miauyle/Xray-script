中文 | [English](.github/README.en.md)

# Xray-script

基于 Shell 的 Xray-core 安装与管理脚本，支持多种 REALITY / XHTTP 配置、订阅发布、分流与运维诊断。

**脚本版本：以 [config.json](config.json) 为准** · [完整更新记录](CHANGELOG.md)

## 快速开始

适用于已具备管理权限的 Linux VPS。先确认 SSH 与云服务商防火墙规则可用，建议在全新或已备份的环境安装。

```bash
wget -O "$HOME/Xray-script.sh" https://raw.githubusercontent.com/miauyle/Xray-script/main/install.sh
bash "$HOME/Xray-script.sh"
```

直接安装指定配置（替换启动命令即可）：

```bash
bash "$HOME/Xray-script.sh" --vision   # VLESS Vision REALITY
bash "$HOME/Xray-script.sh" --xhttp    # VLESS XHTTP REALITY
bash "$HOME/Xray-script.sh" --fallback # Vision + XHTTP
```

安装、SNI、支持的系统及完整命令见 [安装与运行指南](docs/INSTALLATION.md)。

## 核心能力

| 功能 | 内容 |
| --- | --- |
| Xray 配置 | Vision、XHTTP、Fallback、SNI、mKCP、Trojan 等可选模式 |
| 订阅与客户端 | 原始 VLESS 链接 / 二维码、Clash Verge Rev / Mihomo YAML、Shadowrocket 多节点订阅 |
| 多 VPS | 单一中心聚合订阅；普通 VPS 保留独立 `clash.yaml` 和 `proxies.yaml` |
| 路由 | Direct / Block / WARP 规则、可选 WARP 出站及 Direct fallback |
| 安全运维 | Xray 配置校验、备份与回滚、Doctor、日志、BBR、Swap、conntrack、防火墙检查 |
| Nginx / SNI | TLS/CDN 分流、自定义域名及反向代理站点 |

详细规则、架构与操作说明见 [功能与配置说明](docs/FEATURES.md)。

## 订阅使用要点

- **单台 VPS**：主菜单 `10. Clash/Mihomo 配置与订阅` → 生成 YAML → 按需发布远程订阅。
- **多台 VPS**：各服务器独立发布 Provider；只选择一台作为聚合中心，发布 `multi_clash.yaml` 或 Shadowrocket 节点订阅。
- **安全提醒**：订阅链接中的 Token 相当于访问凭据；若使用 HTTP 发布订阅，内容不加密。
- **协议兼容**：新版本 Xray REALITY 可能要求 Mihomo 开启 `X25519MLKEM768`。脚本按服务器版本生成配置；Shadowrocket 的兼容性必须以实际客户端测试为准。

## 文档导航

| 文档 | 内容 |
| --- | --- |
| [安装与运行](docs/INSTALLATION.md) | 安装命令、菜单、发行版、安装耗时与依赖 |
| [功能与配置](docs/FEATURES.md) | 协议、SNI、订阅、多 VPS、备份、运维和 WARP |
| [故障排查](docs/TROUBLESHOOTING.md) | 连通性、REALITY、Shadowrocket、WARP 和订阅诊断 |
| [更新日志](CHANGELOG.md) | 历史版本变更和迁移说明 |

## 使用说明

脚本会管理系统服务、网络和配置文件。变更前请保留备份；云端 Security List / NSG 规则需在云平台独立配置。脚本更新不代表已经更新或重新生成运行中的 Xray 配置及订阅。

项目参考 [Xray-core](https://github.com/XTLS/Xray-core)、[REALITY](https://github.com/XTLS/REALITY) 及 [XHTTP](https://github.com/XTLS/Xray-core/discussions/4113)，完整致谢见[功能说明](docs/FEATURES.md)。

仅供合法的学习、交流与网络管理使用。
