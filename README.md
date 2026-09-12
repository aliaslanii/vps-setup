# VPS Auto-Setup: Full Stack & Dependencies

A clean, robust bash script to configure a fresh Ubuntu VPS with all essential dependencies for Laravel (PHP), MySQL, phpMyAdmin, Redis, and Node.js (Next.js/PM2) web environments — without cloning or deploying user projects.

## Quick Installation

Login to your fresh VPS as root and run:

```bash
curl -sSL https://raw.githubusercontent.com/<YOUR_GITHUB_USERNAME>/<YOUR_REPO_NAME>/main/setup.sh | sudo bash
```

## Features & Installed Software

- **System Updates & Utilities**: Upgrades system packages and installs `curl`, `git`, `zip`, `unzip`, `build-essential`, `ufw`, `certbot`, etc.
- **PHP & Extensions**: Installs chosen PHP version (default: `8.3`) via `ondrej/php` with all required extensions (`fpm`, `mysql`, `xml`, `curl`, `zip`, `gd`, `mbstring`, `bcmath`, `sqlite3`, `intl`, `redis`, `soap`, `imagick`).
- **Composer**: Installs the latest stable Composer globally.
- **Node.js & PM2**: Installs Node.js LTS (default: `20`) via NodeSource repo, with `npm` and `pm2` process manager configured.
- **MySQL Server**: Installs and secures MySQL, generates credentials, and creates a ready-to-use database (`app_db`) and user (`app_user`).
- **phpMyAdmin**: Installs latest stable phpMyAdmin with blowfish encryption and dedicated Nginx server block (default port: `8080`).
- **Redis Server**: Installs and starts Redis cache & queue server.
- **Nginx & Ready Templates**: Installs Nginx with ready-to-use virtual host templates for Laravel (`laravel.template`) and Next.js (`nextjs.template`).
- **Security & Firewall**: Configures UFW firewall (SSH, Nginx Full, and phpMyAdmin port enabled).
- **Custom MOTD**: Cyan ASCII welcome banner on SSH login.

