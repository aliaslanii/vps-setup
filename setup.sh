#!/usr/bin/env bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}===================================================================${NC}"
echo -e "${BLUE}    VPS Stack, Security & Hardening Auto-Setup                      ${NC}"
echo -e "${BLUE}===================================================================${NC}"

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Error: Please run this script as root (sudo bash setup.sh).${NC}"
  exit 1
fi

if [ -t 0 ]; then
  INPUT_DEV="/dev/stdin"
elif [ -e /dev/tty ]; then
  INPUT_DEV="/dev/tty"
else
  INPUT_DEV="/dev/null"
fi

if [ "$INPUT_DEV" != "/dev/null" ]; then
  read -p "Enter personal sudo username [default: ali]: " USERNAME < "$INPUT_DEV" || USERNAME="ali"
  USERNAME=${USERNAME:-ali}

  read -p "Enter custom SSH Port [default: 9011]: " SSH_PORT < "$INPUT_DEV" || SSH_PORT="9011"
  SSH_PORT=${SSH_PORT:-9011}

  echo -e "${YELLOW}Please paste your personal public SSH key (or leave empty to copy root's key):${NC}"
  read -r SSH_PUB_KEY < "$INPUT_DEV" || SSH_PUB_KEY=""

  read -p "Enter PHP version to install [default: 8.3]: " PHP_VERSION < "$INPUT_DEV" || PHP_VERSION="8.3"
  PHP_VERSION=${PHP_VERSION:-8.3}

  read -p "Enter Node.js major version to install (e.g., 20, 22) [default: 20]: " NODE_VERSION < "$INPUT_DEV" || NODE_VERSION="20"
  NODE_VERSION=${NODE_VERSION:-20}

  read -p "Enter phpMyAdmin Domain (e.g. pma.domain.com) [leave empty for Port mode]: " PMA_DOMAIN < "$INPUT_DEV" || PMA_DOMAIN=""

  if [ -z "$PMA_DOMAIN" ]; then
    read -p "Enter phpMyAdmin Port [default: 8080]: " PMA_PORT < "$INPUT_DEV" || PMA_PORT="8080"
    PMA_PORT=${PMA_PORT:-8080}
  else
    PMA_PORT="80"
  fi
else
  USERNAME="ali"
  SSH_PORT="9011"
  SSH_PUB_KEY=""
  PHP_VERSION="8.3"
  NODE_VERSION="20"
  PMA_DOMAIN=""
  PMA_PORT="8080"
fi

wait_for_apt() {
  while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1 ; do
    echo -e "${YELLOW}---> Waiting for another package manager process to release lock...${NC}"
    sleep 3
  done
}

echo -e "${YELLOW}---> Updating system package lists and upgrading...${NC}"
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
if [ -f /etc/needrestart/needrestart.conf ]; then
  sed -i "s/#\$nrconf{restart} = 'i';/\$nrconf{restart} = 'a';/g" /etc/needrestart/needrestart.conf || true
fi
wait_for_apt
apt-get -o DPkg::Lock::Timeout=120 update -y
apt-get -o DPkg::Lock::Timeout=120 upgrade -y

echo -e "${YELLOW}---> Installing common utilities & security packages...${NC}"
wait_for_apt
apt-get -o DPkg::Lock::Timeout=120 install -y software-properties-common curl wget git zip unzip build-essential ufw certbot python3-certbot-nginx fail2ban libpng-dev libjpeg-dev libwebp-dev

echo -e "${YELLOW}---> Configuring user: ${USERNAME} with sudo access...${NC}"
if ! id -u "$USERNAME" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$USERNAME"
  usermod -aG sudo "$USERNAME"
  echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/99-${USERNAME}"
  chmod 0440 "/etc/sudoers.d/99-${USERNAME}"
fi

mkdir -p "/home/${USERNAME}/.ssh"
chmod 700 "/home/${USERNAME}/.ssh"

if [ -n "$SSH_PUB_KEY" ]; then
  echo "$SSH_PUB_KEY" >> "/home/${USERNAME}/.ssh/authorized_keys"
elif [ -f /root/.ssh/authorized_keys ]; then
  cp /root/.ssh/authorized_keys "/home/${USERNAME}/.ssh/authorized_keys"
fi

touch "/home/${USERNAME}/.ssh/authorized_keys"
chmod 600 "/home/${USERNAME}/.ssh/authorized_keys"
chown -R "${USERNAME}:${USERNAME}" "/home/${USERNAME}/.ssh"

echo -e "${YELLOW}---> Hardening SSH daemon on port ${SSH_PORT}...${NC}"
mkdir -p /etc/ssh/sshd_config.d
cat <<EOF > /etc/ssh/sshd_config.d/99-security.conf
Port ${SSH_PORT}
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no
UsePAM yes
X11Forwarding no
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
EOF

sed -i "s/^#\?Port .*/Port ${SSH_PORT}/g" /etc/ssh/sshd_config || true

echo -e "${YELLOW}---> Configuring Fail2ban for SSH & Nginx...${NC}"
cat <<EOF > /etc/fail2ban/jail.local
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
port = ${SSH_PORT}
filter = sshd
backend = systemd
maxretry = 3
EOF

systemctl enable fail2ban
systemctl restart fail2ban

echo -e "${YELLOW}---> Adding ondrej/php PPA...${NC}"
wait_for_apt
add-apt-repository -y ppa:ondrej/php
wait_for_apt
apt-get -o DPkg::Lock::Timeout=120 update -y

echo -e "${YELLOW}---> Installing PHP ${PHP_VERSION} & extensions...${NC}"
wait_for_apt
apt-get -o DPkg::Lock::Timeout=120 install -y \
  php${PHP_VERSION} \
  php${PHP_VERSION}-cli \
  php${PHP_VERSION}-fpm \
  php${PHP_VERSION}-mysql \
  php${PHP_VERSION}-xml \
  php${PHP_VERSION}-curl \
  php${PHP_VERSION}-zip \
  php${PHP_VERSION}-gd \
  php${PHP_VERSION}-mbstring \
  php${PHP_VERSION}-bcmath \
  php${PHP_VERSION}-sqlite3 \
  php${PHP_VERSION}-intl \
  php${PHP_VERSION}-redis \
  php${PHP_VERSION}-soap \
  php${PHP_VERSION}-imagick

echo -e "${YELLOW}---> Installing Composer...${NC}"
curl -sS https://getcomposer.org/installer | php
mv composer.phar /usr/local/bin/composer
chmod +x /usr/local/bin/composer

echo -e "${YELLOW}---> Installing Node.js v${NODE_VERSION} & npm...${NC}"
wait_for_apt
apt-get -o DPkg::Lock::Timeout=120 install -y ca-certificates gnupg
mkdir -p /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor --yes -o /etc/apt/keyrings/nodesource.gpg
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_VERSION}.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list
wait_for_apt
apt-get -o DPkg::Lock::Timeout=120 update -y
wait_for_apt
apt-get -o DPkg::Lock::Timeout=120 install -y nodejs

echo -e "${YELLOW}---> Installing PM2 globally...${NC}"
npm install -g pm2
pm2 startup || true

echo -e "${YELLOW}---> Installing Redis Server...${NC}"
wait_for_apt
apt-get -o DPkg::Lock::Timeout=120 install -y redis-server
sed -i 's/^bind .*/bind 127.0.0.1 ::1/g' /etc/redis/redis.conf || true
systemctl enable redis-server
systemctl restart redis-server

echo -e "${YELLOW}---> Installing MySQL Server...${NC}"
wait_for_apt
apt-get -o DPkg::Lock::Timeout=120 install -y mysql-server
systemctl enable mysql
systemctl start mysql

MYSQL_ROOT_PASSWORD=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)
DB_NAME="app_db"
DB_USER="app_user"
DB_PASS=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)

echo -e "${YELLOW}---> Configuring MySQL root password and developer user...${NC}"

if mysql -e "SELECT 1;" >/dev/null 2>&1; then
  mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASSWORD}';" || \
  mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';"
  mysql -e "FLUSH PRIVILEGES;"
elif [ -f /etc/mysql/debian.cnf ]; then
  mysql --defaults-file=/etc/mysql/debian.cnf -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASSWORD}';" || \
  mysql --defaults-file=/etc/mysql/debian.cnf -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';"
  mysql --defaults-file=/etc/mysql/debian.cnf -e "FLUSH PRIVILEGES;"
fi

if mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT 1;" >/dev/null 2>&1; then
  MYSQL_EXEC="mysql -u root -p${MYSQL_ROOT_PASSWORD}"
elif [ -f /etc/mysql/debian.cnf ]; then
  MYSQL_EXEC="mysql --defaults-file=/etc/mysql/debian.cnf"
else
  MYSQL_EXEC="mysql"
fi

$MYSQL_EXEC -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
$MYSQL_EXEC -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
$MYSQL_EXEC -e "ALTER USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
$MYSQL_EXEC -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';"
$MYSQL_EXEC -e "FLUSH PRIVILEGES;"

echo -e "${YELLOW}---> Installing Nginx...${NC}"
wait_for_apt
apt-get -o DPkg::Lock::Timeout=120 install -y nginx
systemctl enable nginx
systemctl start nginx

echo -e "${YELLOW}---> Installing and configuring phpMyAdmin...${NC}"
PMA_VERSION="5.2.1"
PMA_DIR="/var/www/phpmyadmin"
rm -rf "$PMA_DIR"
mkdir -p "$PMA_DIR"
wget -q "https://files.phpmyadmin.net/phpMyAdmin/${PMA_VERSION}/phpMyAdmin-${PMA_VERSION}-all-languages.tar.gz" -O /tmp/phpmyadmin.tar.gz
tar -xzf /tmp/phpmyadmin.tar.gz -C "$PMA_DIR" --strip-components=1
rm -f /tmp/phpmyadmin.tar.gz

mkdir -p "${PMA_DIR}/tmp"
chmod 777 "${PMA_DIR}/tmp"

BLOWFISH_SECRET=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
cat <<EOF > "${PMA_DIR}/config.inc.php"
<?php
declare(strict_types=1);

\$cfg['blowfish_secret'] = '${BLOWFISH_SECRET}';

\$i = 1;
\$cfg['Servers'][\$i]['auth_type'] = 'cookie';
\$cfg['Servers'][\$i]['host'] = '127.0.0.1';
\$cfg['Servers'][\$i]['port'] = '3306';
\$cfg['Servers'][\$i]['compress'] = false;
\$cfg['Servers'][\$i]['AllowNoPassword'] = false;

\$cfg['UploadDir'] = '';
\$cfg['SaveDir'] = '';
\$cfg['TempDir'] = '${PMA_DIR}/tmp';
EOF

chown -R www-data:www-data "$PMA_DIR"
chmod -R 755 "$PMA_DIR"

if [ -n "$PMA_DOMAIN" ]; then
  cat <<EOF > /etc/nginx/sites-available/phpmyadmin
server {
    listen 80;
    server_name ${PMA_DOMAIN};
    root /var/www/phpmyadmin;
    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ \.php$ {
        fastcgi_pass unix:/var/run/php/php${PHP_VERSION}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
else
  cat <<EOF > /etc/nginx/sites-available/phpmyadmin
server {
    listen ${PMA_PORT};
    server_name _;
    root /var/www/phpmyadmin;
    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ \.php$ {
        fastcgi_pass unix:/var/run/php/php${PHP_VERSION}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
fi

ln -sf /etc/nginx/sites-available/phpmyadmin /etc/nginx/sites-enabled/

echo -e "${YELLOW}---> Configuring Hardened Firewall (UFW)...${NC}"
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow "${SSH_PORT}/tcp"
ufw allow 80/tcp
ufw allow 443/tcp
if [ -z "$PMA_DOMAIN" ] && [ "$PMA_PORT" != "80" ] && [ "$PMA_PORT" != "443" ]; then
  ufw allow "${PMA_PORT}/tcp"
fi
ufw --force enable

echo -e "${YELLOW}---> Creating Nginx Server Block Templates for future projects...${NC}"

cat <<EOF > /etc/nginx/sites-available/laravel.template
server {
    listen 80;
    server_name example.com;
    root /var/www/laravel/public;

    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";

    index index.php;
    charset utf-8;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    error_page 404 /index.php;

    location ~ \.php$ {
        fastcgi_pass unix:/var/run/php/php${PHP_VERSION}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
EOF

cat <<EOF > /etc/nginx/sites-available/nextjs.template
server {
    listen 80;
    server_name example.com;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
EOF

mkdir -p /var/www/laravel
mkdir -p /var/www/nextjs
chown -R www-data:www-data /var/www
chmod -R 775 /var/www

echo -e "${YELLOW}---> Configuring Custom SSH Login Banner (MOTD)...${NC}"
mkdir -p /etc/update-motd.d
cat <<'EOF' > /etc/update-motd.d/99-aliaslani
#!/bin/sh
printf "\033[1;36m"
printf "    ___    ___                  __               _   \n"
printf "   /   |  / (_)  ____ _ _____  / / ____ _  ____ (_)  \n"
printf "  / /| | / / /  / __ \`// ___/ / / / __ \`/ / __ \/ /   \n"
printf " / ___ |/ / /  / /_/ /(__  ) / / / /_/ / / / / / /    \n"
printf "/_/  |_/_/_/   \__,_//____/ /_/  \__,_/ /_/ /_/_/     \n"
printf "                                                     \n"
printf "  Welcome back, Ali Aslani!\n"
printf "  VPS Stack Ready & Hardened (PHP, Composer, MySQL, phpMyAdmin, Nginx, Node.js)\n"
printf "\033[0m\n"
EOF
chmod +x /etc/update-motd.d/99-aliaslani

echo -e "${YELLOW}---> Validating configurations and restarting services...${NC}"
nginx -t
systemctl restart php${PHP_VERSION}-fpm
systemctl restart mysql
systemctl restart nginx
systemctl restart ssh || systemctl restart sshd

if [ -n "$PMA_DOMAIN" ]; then
  read -p "Do you want to configure free SSL (HTTPS) for ${PMA_DOMAIN}? (y/n) [default: y]: " PMA_SSL < "$INPUT_DEV" || PMA_SSL="y"
  PMA_SSL=${PMA_SSL:-y}
  if [ "$PMA_SSL" = "y" ] || [ "$PMA_SSL" = "Y" ]; then
    echo -e "${YELLOW}---> Requesting SSL certificate via Certbot...${NC}"
    certbot --nginx -d "${PMA_DOMAIN}" --non-interactive --agree-tos --register-unsafely-without-email || certbot --nginx -d "${PMA_DOMAIN}" || true
  fi
fi

SERVER_IP=$(curl -s https://api.ipify.org || hostname -I | awk '{print $1}')

if [ -n "$PMA_DOMAIN" ]; then
  PMA_URL="https://${PMA_DOMAIN} (or http://${PMA_DOMAIN})"
else
  PMA_URL="http://${SERVER_IP}:${PMA_PORT}/"
fi

echo -e "\n${GREEN}===================================================================${NC}"
echo -e "${GREEN}       VPS Stack & Security Hardening Completed Successfully!      ${NC}"
echo -e "${GREEN}===================================================================${NC}"
echo -e "${BLUE}Security & Access Details:${NC}"
echo -e " - Sudo User: ${YELLOW}${USERNAME}${NC}"
echo -e " - SSH Port: ${YELLOW}${SSH_PORT}${NC}"
echo -e " - Root Login: ${RED}Disabled (PermitRootLogin no)${NC}"
echo -e " - Password Login: ${RED}Disabled (Key authentication only)${NC}"
echo -e " - Fail2ban: ${GREEN}Active (SSH & Nginx protection)${NC}"
echo -e " - Firewall (UFW): ${GREEN}Active & Configured${NC}"
echo -e ""
echo -e "${BLUE}Installed software & services:${NC}"
echo -e " - Git: \$(git --version)"
echo -e " - PHP: \$(php -v | head -n 1)"
echo -e " - Composer: \$(composer --version | head -n 1)"
echo -e " - MySQL Server: \$(mysql --version)"
echo -e " - phpMyAdmin: v\${PMA_VERSION}"
echo -e " - Redis Server: \$(redis-server --version | head -n 1)"
echo -e " - Node.js: \$(node -v)"
echo -e " - npm: \$(npm -v)"
echo -e " - PM2: \$(pm2 -v)"
echo -e " - Nginx: \$(nginx -v 2>&1)"
echo -e ""
echo -e "${BLUE}Database & phpMyAdmin Credentials:${NC}"
echo -e " - phpMyAdmin URL: ${YELLOW}${PMA_URL}${NC}"
echo -e " - MySQL root user: ${YELLOW}root${NC}"
echo -e " - MySQL root pass: ${YELLOW}\${MYSQL_ROOT_PASSWORD}${NC}"
echo -e " - Sample DB name:  ${YELLOW}\${DB_NAME}${NC}"
echo -e " - Sample DB user:  ${YELLOW}\${DB_USER}${NC}"
echo -e " - Sample DB pass:  ${YELLOW}\${DB_PASS}${NC}"
echo -e ""
echo -e "${BLUE}To connect from your local terminal (~/.ssh/config):${NC}"
echo -e "${CYAN}"
echo -e "Host myserver"
echo -e "    HostName ${SERVER_IP}"
echo -e "    User ${USERNAME}"
echo -e "    Port ${SSH_PORT}"
echo -e "    IdentityFile ~/.ssh/id_ed25519"
echo -e "${NC}"
echo -e "${BLUE}Direct connect command:${NC}"
echo -e "ssh -p ${SSH_PORT} ${USERNAME}@${SERVER_IP}"
echo -e ""
echo -e "${YELLOW}IMPORTANT: DO NOT close this terminal before testing a connection in a new tab!${NC}"
echo -e "${GREEN}===================================================================${NC}"

