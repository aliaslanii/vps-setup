# VPS Auto-Setup for Laravel & Next.js

A comprehensive, interactive bash script to configure a fresh Ubuntu VPS for full-stack Laravel (PHP 8.2/8.3) and Next.js (Node.js/PM2) applications, utilizing Nginx as a reverse proxy, MySQL database, UFW firewall, and Certbot for SSL.

## Quick Installation

Login to your fresh VPS as root and run the following command:

```bash
curl -sSL https://raw.githubusercontent.com/<YOUR_GITHUB_USERNAME>/<YOUR_REPO_NAME>/main/setup.sh | sudo bash
```

## Features

- **System Updates**: Automatically updates package lists and upgrades.
- **PHP & Extensions**: Installs PHP (8.3 default) with Laravel required extensions.
- **Composer**: Installs the latest stable version globally.
- **Node.js & PM2**: Installs Node.js LTS (v20 default) using modern NodeSource repo, and installs PM2 globally.
- **MySQL**: Automatically installs MySQL, generates secure credentials, and sets up a database (`app_db`) and user (`app_user`).
- **Nginx Configuration**: Installs Nginx, creates easy configuration templates, and prompts to configure custom domains for your deployed apps.
- **Security**: Sets up UFW firewall (SSH, HTTP, HTTPS allowed).
- **Interactive Deployments**: 
  - Generates SSH keys.
  - Automatically clones Laravel / Next.js projects via SSH.
  - Installs vendors (`composer install` / `npm install`).
  - Sets Laravel `.env` variables and runs migrations.
  - Builds Next.js projects and runs them under PM2.
  - Installs Let's Encrypt SSL (HTTPS) automatically using Certbot.
- **Custom MOTD**: Renders a beautiful cyan ASCII welcome banner when logging into SSH.
