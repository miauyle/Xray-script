# 安装与运行

[← 返回首页](../README.md) · [English](INSTALLATION.en.md) · [功能说明](FEATURES.md)

## 如何使用

* 获取

  ```sh
  wget -O ${HOME}/Xray-script.sh https://raw.githubusercontent.com/miauyle/Xray-script/main/install.sh
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
  wget -O ${HOME}/Xray-script.sh https://raw.githubusercontent.com/miauyle/Xray-script/main/install.sh && bash ${HOME}/Xray-script.sh
  ```

## 当前主菜单速览

| 菜单 | 用途 |
| --- | --- |
| 1–3 装载管理 | 完整安装、更新和卸载 |
| 4–6 操作管理 | 启动、停止、重启 Xray |
| 7–9 配置管理 | 分享链接、统计、修改配置与分流 |
| 10 Clash/Mihomo | 生成单机订阅、管理中心多机订阅 |
| 11 运维与诊断 | 日志、Doctor、备份、WARP、BBR、主机调优 |

菜单以运行中的实际脚本为准，不再使用过时的版本截图。

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
