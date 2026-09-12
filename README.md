# VPS Auto-Setup: Full Stack, Hardening & Dependencies

A clean, robust bash script to configure a fresh Ubuntu VPS with production security hardening and all essential dependencies for Laravel (PHP), MySQL, phpMyAdmin, Redis, and Node.js (Next.js/PM2) web environments — without cloning or deploying user projects.

## Quick Installation

Login to your fresh VPS as root and run:

```bash
curl -sSL https://raw.githubusercontent.com/aliaslanii/vps-setup/main/setup.sh | sudo bash
```

Or clone and run locally:

```bash
git clone https://github.com/aliaslanii/vps-setup.git
cd vps-setup
sudo bash setup.sh
```

## Security & Hardening Features

- **Personal Sudo User**: Automatically creates your personal non-root user (e.g., `ali`), configures passwordless sudo, and sets up SSH keys with strict permissions (`700` and `600`).
- **SSH Hardening**:
  - Custom SSH Port (default: `9011`).
  - `PermitRootLogin no` (root login disabled).
  - `PasswordAuthentication no` (password logins completely disabled).
  - `PubkeyAuthentication yes` (only SSH key authentication allowed).
  - Enforced security flags: `X11Forwarding no`, `MaxAuthTries 3`, keepalive timeouts.
- **Fail2ban Intrusion Prevention**: Protects SSH on the custom port (`9011`) against brute force with automatic bans.
- **Hardened Firewall (UFW)**: Default deny incoming policy. Only ports `9011` (SSH), `80/443` (Nginx), and the custom phpMyAdmin port are opened. Database ports (`3306`, `6379`) remain completely closed to the internet.
- **Localhost Service Binding**: MySQL and Redis are strictly bound to `127.0.0.1`.

## Web Stack & Dependencies

- **PHP & Extensions**: Installs chosen PHP version (default: `8.3`) via `ondrej/php` with all required extensions (`fpm`, `mysql`, `xml`, `curl`, `zip`, `gd`, `mbstring`, `bcmath`, `sqlite3`, `intl`, `redis`, `soap`, `imagick`).
- **Composer**: Latest stable Composer installed globally.
- **Node.js & PM2**: Node.js LTS (default: `20`) via NodeSource repo, with `npm` and `pm2` process manager configured.
- **MySQL Server**: Installs MySQL, secures root password, and creates a project database (`app_db`) and user (`app_user`).
- **phpMyAdmin**: Installs latest stable phpMyAdmin with blowfish encryption and dedicated Nginx server block.
- **Redis Server**: Installs and starts Redis cache & queue service.
- **Nginx & Ready Templates**: Virtual host templates for Laravel (`laravel.template`) and Next.js (`nextjs.template`).
- **Custom MOTD**: Cyan ASCII welcome banner on SSH login.


