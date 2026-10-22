# Installation and Usage

[← Home](../.github/README.en.md) · [中文](INSTALLATION.md) · [Features](FEATURES.en.md)

## How to Use

* Download

  ```sh
  wget -O ${HOME}/Xray-script.sh https://raw.githubusercontent.com/miauyle/Xray-script/main/install.sh
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
  wget -O ${HOME}/Xray-script.sh https://raw.githubusercontent.com/miauyle/Xray-script/main/install.sh && bash ${HOME}/Xray-script.sh
  ```

## Current main-menu overview

| Menu | Purpose |
| --- | --- |
| 1–3 Installation | Full install, update, uninstall |
| 4–6 Operations | Start, stop, restart Xray |
| 7–9 Configuration | Share links, traffic statistics, configuration and routing |
| 10 Clash/Mihomo | Standalone subscriptions and centralized multi-VPS providers |
| 11 Operations & Diagnostics | Logs, Doctor, backups, WARP, BBR and host tuning |

Use the live menu as the authoritative source; the old screenshot showed an obsolete version.

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
