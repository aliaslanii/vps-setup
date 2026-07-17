#!/usr/bin/env bash

# VPS Auto-Setup Script for Laravel (PHP) & Next.js (Node.js) Fullstack Projects
# Author: Antigravity
# Designed for: Ubuntu 20.04 / 22.04 / 24.04 LTS

# Exit immediately if a command exits with a non-zero status
set -e

# Color variables for outputs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}===================================================================${NC}"
echo -e "${BLUE}    VPS Auto-Setup for Laravel (PHP) & Next.js (Node.js) Web Apps  ${NC}"
echo -e "${BLUE}===================================================================${NC}"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Error: Please run this script as root (sudo bash setup.sh).${NC}"
  exit 1
fi

# Ask for preferences
read -p "Enter PHP version to install [default: 8.3]: " PHP_VERSION
PHP_VERSION=${PHP_VERSION:-8.3}

read -p "Enter Node.js major version to install (e.g., 20, 22) [default: 20]: " NODE_VERSION
NODE_VERSION=${NODE_VERSION:-20}

# Update System packages
echo -e "${YELLOW}---> Updating system package lists and upgrading...${NC}"
apt-get update -y
apt-get upgrade -y

# Install common utilities
echo -e "${YELLOW}---> Installing common utilities (git, curl, zip, ufw, certbot, etc.)...${NC}"
apt-get install -y software-properties-common curl git zip unzip build-essential ufw certbot python3-certbot-nginx libpng-dev libjpeg-dev libwebp-dev

# Add Ondrej PHP PPA
echo -e "${YELLOW}---> Adding ondrej/php PPA...${NC}"
add-apt-repository -y ppa:ondrej/php
apt-get update -y

# Install PHP and extensions
echo -e "${YELLOW}---> Installing PHP ${PHP_VERSION} & extensions...${NC}"
apt-get install -y \
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

# Install Composer
echo -e "${YELLOW}---> Installing Composer...${NC}"
curl -sS https://getcomposer.org/installer | php
mv composer.phar /usr/local/bin/composer
chmod +x /usr/local/bin/composer

# Install Node.js (Modern & Stable NodeSource repository)
echo -e "${YELLOW}---> Installing Node.js v${NODE_VERSION} (Stable)...${NC}"
apt-get install -y ca-certificates gnupg
mkdir -p /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_VERSION}.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list
apt-get update -y
apt-get install -y nodejs

# Install PM2 globally
echo -e "${YELLOW}---> Installing PM2 globally...${NC}"
npm install -g pm2
pm2 startup || true

# Install MySQL
echo -e "${YELLOW}---> Installing MySQL Server...${NC}"
apt-get install -y mysql-server

# Generate a random password for MySQL root user
MYSQL_ROOT_PASSWORD=$(openssl rand -base64 12)

echo -e "${YELLOW}---> Configuring MySQL...${NC}"
# Configure password authentication for root
mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASSWORD}';"
mysql -e "FLUSH PRIVILEGES;"

# Create a sample template database and developer user
DB_NAME="app_db"
DB_USER="app_user"
DB_PASS=$(openssl rand -base64 12)

mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';"
mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "FLUSH PRIVILEGES;"

# Install Nginx
echo -e "${YELLOW}---> Installing Nginx...${NC}"
apt-get install -y nginx

# Setup UFW Firewall
echo -e "${YELLOW}---> Configuring Firewall (UFW)...${NC}"
ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw --force enable

# Create Nginx Templates
echo -e "${YELLOW}---> Creating Nginx Server Block Templates...${NC}"

# Laravel Template
cat <<EOF > /etc/nginx/sites-available/laravel.template
server {
    listen 80;
    server_name example.com; # Change to your domain
    root /var/www/laravel/public; # Change to your Laravel project path

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

# Next.js Template (Reverse proxy to PM2 port 3000)
cat <<EOF > /etc/nginx/sites-available/nextjs.template
server {
    listen 80;
    server_name example.com; # Change to your domain

    location / {
        proxy_pass http://127.0.0.1:3000; # Port where PM2 / Next.js is running
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

# Create standard directories
mkdir -p /var/www/laravel
mkdir -p /var/www/nextjs

# Fix initial permissions
chown -R www-data:www-data /var/www
chmod -R 775 /var/www

# Interactive Git SSH & Project Cloning Flow
echo -e "\n${BLUE}===================================================================${NC}"
echo -e "${BLUE}          Project Deployment & Repository Cloning                  ${NC}"
echo -e "${BLUE}===================================================================${NC}"

# SSH Key Setup Helper
setup_ssh_key() {
  if [ ! -f ~/.ssh/id_ed25519 ]; then
    echo -e "${YELLOW}---> Generating new SSH Key (ED25519) for VPS...${NC}"
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    ssh-keygen -t ed25519 -C "vps-deploy-key" -N "" -f ~/.ssh/id_ed25519
  fi

  echo -e "\n${GREEN}Here is your VPS SSH Public Key:${NC}"
  echo -e "${CYAN}"
  cat ~/.ssh/id_ed25519.pub
  echo -e "${NC}"
  echo -e "${YELLOW}IMPORTANT: Copy the key above and add it as a Deploy Key on GitHub/GitLab.${NC}"
  read -p "Once you have added the key to your repository, press [ENTER] to continue..." ready_confirm
  
  # Add hosts to prevent interactive prompt during clone
  ssh-keyscan -H github.com >> ~/.ssh/known_hosts 2>/dev/null || true
  ssh-keyscan -H gitlab.com >> ~/.ssh/known_hosts 2>/dev/null || true
}

# 1. Laravel Deployment
read -p "Do you want to clone your Laravel project now? (y/n) [default: n]: " CLONE_LARAVEL
CLONE_LARAVEL=${CLONE_LARAVEL:-n}

if [ "$CLONE_LARAVEL" = "y" ] || [ "$CLONE_LARAVEL" = "Y" ]; then
  setup_ssh_key
  read -p "Enter Laravel Git SSH URL (e.g., git@github.com:user/repo.git): " LARAVEL_REPO
  if [ ! -z "$LARAVEL_REPO" ]; then
    echo -e "${YELLOW}---> Cloning Laravel repository...${NC}"
    rm -rf /var/www/laravel
    git clone "$LARAVEL_REPO" /var/www/laravel
    
    if [ -f "/var/www/laravel/composer.json" ]; then
      echo -e "${YELLOW}---> Laravel project detected. Installing dependencies...${NC}"
      cd /var/www/laravel
      composer install --no-interaction --prefer-dist --optimize-autoloader
      
      if [ ! -f ".env" ] && [ -f ".env.example" ]; then
        echo -e "${YELLOW}---> Copying .env.example to .env...${NC}"
        cp .env.example .env
      fi

      if [ -f ".env" ]; then
        echo -e "${YELLOW}---> Configuring database credentials in .env...${NC}"
        sed -i 's/^DB_CONNECTION=.*/DB_CONNECTION=mysql/g' .env
        sed -i 's/^DB_HOST=.*/DB_HOST=127.0.0.1/g' .env
        sed -i 's/^DB_PORT=.*/DB_PORT=3306/g' .env
        sed -i "s/^DB_DATABASE=.*/DB_DATABASE=${DB_NAME}/g" .env
        sed -i "s/^DB_USERNAME=.*/DB_USERNAME=${DB_USER}/g" .env
        # Use | delimiter in sed to prevent issues if password contains special characters
        sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=${DB_PASS}|g" .env
        # Set Session Driver to file
        sed -i 's/^SESSION_DRIVER=.*/SESSION_DRIVER=file/g' .env
        
        echo -e "${YELLOW}---> Generating application key...${NC}"
        php artisan key:generate
      fi
      
      # Set permissions for storage & bootstrap cache
      chown -R www-data:www-data /var/www/laravel
      chmod -R 775 /var/www/laravel
      chmod -R 775 /var/www/laravel/storage /var/www/laravel/bootstrap/cache
      
      # Run migrations if database is ready
      read -p "Do you want to run database migrations? (y/n) [default: y]: " RUN_MIGRATIONS
      RUN_MIGRATIONS=${RUN_MIGRATIONS:-y}
      if [ "$RUN_MIGRATIONS" = "y" ] || [ "$RUN_MIGRATIONS" = "Y" ]; then
         echo -e "${YELLOW}---> Running migrations...${NC}"
         php artisan migrate --force
      fi
      
      # Nginx Domain Configuration for Laravel
      read -p "Enter Domain Name for Laravel (e.g., api.domain.com) [leave empty to skip Nginx configuration]: " LARAVEL_DOMAIN
      if [ ! -z "$LARAVEL_DOMAIN" ]; then
         echo -e "${YELLOW}---> Configuring Nginx site for $LARAVEL_DOMAIN...${NC}"
         cat <<EOF > /etc/nginx/sites-available/$LARAVEL_DOMAIN
server {
    listen 80;
    server_name $LARAVEL_DOMAIN;
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
         ln -sf /etc/nginx/sites-available/$LARAVEL_DOMAIN /etc/nginx/sites-enabled/
         if nginx -t; then
            systemctl reload nginx
            echo -e "${GREEN}---> Nginx configuration for Laravel successfully reloaded!${NC}"
            
            # Certbot SSL
            read -p "Do you want to configure SSL (HTTPS) for $LARAVEL_DOMAIN? (y/n) [default: y]: " LARAVEL_SSL
            LARAVEL_SSL=${LARAVEL_SSL:-y}
            if [ "$LARAVEL_SSL" = "y" ] || [ "$LARAVEL_SSL" = "Y" ]; then
               certbot --nginx -d $LARAVEL_DOMAIN
            fi
         else
            echo -e "${RED}---> Nginx configuration test failed. Reverting link.${NC}"
            rm -f /etc/nginx/sites-enabled/$LARAVEL_DOMAIN
         fi
      fi
    fi
  else
    echo -e "${RED}Skipped cloning Laravel because repo URL was empty.${NC}"
  fi
fi

# 2. Next.js Deployment
read -p "Do you want to clone your Next.js project now? (y/n) [default: n]: " CLONE_NEXTJS
CLONE_NEXTJS=${CLONE_NEXTJS:-n}

if [ "$CLONE_NEXTJS" = "y" ] || [ "$CLONE_NEXTJS" = "Y" ]; then
  setup_ssh_key
  read -p "Enter Next.js Git SSH URL (e.g., git@github.com:user/repo.git): " NEXTJS_REPO
  if [ ! -z "$NEXTJS_REPO" ]; then
    echo -e "${YELLOW}---> Cloning Next.js repository...${NC}"
    rm -rf /var/www/nextjs
    git clone "$NEXTJS_REPO" /var/www/nextjs
    
    if [ -f "/var/www/nextjs/package.json" ]; then
      echo -e "${YELLOW}---> Next.js project detected. Installing node modules...${NC}"
      cd /var/www/nextjs
      npm install
      chown -R www-data:www-data /var/www/nextjs
      
      # Build & PM2 setup
      read -p "Do you want to build and start the Next.js project using PM2? (y/n) [default: y]: " START_PM2
      START_PM2=${START_PM2:-y}
      if [ "$START_PM2" = "y" ] || [ "$START_PM2" = "Y" ]; then
         echo -e "${YELLOW}---> Building Next.js project...${NC}"
         npm run build
         
         echo -e "${YELLOW}---> Starting Next.js project with PM2...${NC}"
         pm2 start npm --name "nextjs-app" -- start || pm2 restart nextjs-app
         pm2 save
         echo -e "${GREEN}---> Next.js is now running under PM2 control!${NC}"
      fi
       
       # Nginx Domain Configuration for Next.js
       read -p "Enter Domain Name for Next.js (e.g., app.domain.com) [leave empty to skip Nginx configuration]: " NEXTJS_DOMAIN
       if [ ! -z "$NEXTJS_DOMAIN" ]; then
          read -p "Enter Local Port where Next.js runs [default: 3000]: " NEXTJS_PORT
          NEXTJS_PORT=${NEXTJS_PORT:-3000}
          
          echo -e "${YELLOW}---> Configuring Nginx site for $NEXTJS_DOMAIN proxying to port $NEXTJS_PORT...${NC}"
          cat <<EOF > /etc/nginx/sites-available/$NEXTJS_DOMAIN
server {
    listen 80;
    server_name $NEXTJS_DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:$NEXTJS_PORT;
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
          ln -sf /etc/nginx/sites-available/$NEXTJS_DOMAIN /etc/nginx/sites-enabled/
          if nginx -t; then
             systemctl reload nginx
             echo -e "${GREEN}---> Nginx configuration for Next.js successfully reloaded!${NC}"
             
             # Certbot SSL
             read -p "Do you want to configure SSL (HTTPS) for $NEXTJS_DOMAIN? (y/n) [default: y]: " NEXTJS_SSL
             NEXTJS_SSL=${NEXTJS_SSL:-y}
             if [ "$NEXTJS_SSL" = "y" ] || [ "$NEXTJS_SSL" = "Y" ]; then
                certbot --nginx -d $NEXTJS_DOMAIN
             fi
          else
             echo -e "${RED}---> Nginx configuration test failed. Reverting link.${NC}"
             rm -f /etc/nginx/sites-enabled/$NEXTJS_DOMAIN
          fi
       fi
    fi
  else
    echo -e "${RED}Skipped cloning Next.js because repo URL was empty.${NC}"
  fi
fi


# Create Custom MOTD (Login Banner)
echo -e "${YELLOW}---> Configuring Custom SSH Login Banner (MOTD)...${NC}"
mkdir -p /etc/update-motd.d
cat <<'EOF' > /etc/update-motd.d/99-aliaslani
#!/bin/sh
# Cyan (آبی فیروزه‌ای) color code
printf "\033[1;36m"
printf "    ___    ___                  __               _   \n"
printf "   /   |  / (_)  ____ _ _____  / / ____ _  ____ (_)  \n"
printf "  / /| | / / /  / __ \`// ___/ / / / __ \`/ / __ \/ /   \n"
printf " / ___ |/ / /  / /_/ /(__  ) / / / /_/ / / / / / /    \n"
printf "/_/  |_/_/_/   \__,_//____/ /_/  \__,_/ /_/ /_/_/     \n"
printf "                                                     \n"
printf "  Welcome back, Ali Aslani!\n"
printf "  VPS Auto-Setup for Laravel (PHP) & Next.js (Node.js) Web Apps\n"
printf "  Launching My Project...\n"
printf "\033[0m\n"
EOF
chmod +x /etc/update-motd.d/99-aliaslani

# Restart Services
echo -e "${YELLOW}---> Restarting services...${NC}"
systemctl restart php${PHP_VERSION}-fpm
systemctl restart mysql
systemctl restart nginx

# Finish message
echo -e "${GREEN}===================================================================${NC}"
echo -e "${GREEN}             VPS Setup Completed Successfully!                      ${NC}"
echo -e "${GREEN}===================================================================${NC}"
echo -e "${BLUE}Installed software:${NC}"
echo -e " - Git: \$(git --version)"
echo -e " - PHP: \$(php -v | head -n 1)"
echo -e " - Composer: \$(composer --version | head -n 1)"
echo -e " - Node.js: \$(node -v)"
echo -e " - npm: \$(npm -v)"
echo -e " - PM2: \$(pm2 -v)"
echo -e " - MySQL: Server installed & running"
echo -e " - Nginx: \$(nginx -v 2>&1)"
echo -e " - UFW Firewall: Enabled (SSH & Nginx Full allowed)"
echo -e ""
echo -e "${BLUE}MySQL Credentials:${NC}"
echo -e " - root password: ${YELLOW}${MYSQL_ROOT_PASSWORD}${NC}"
echo -e " - Database name: ${YELLOW}${DB_NAME}${NC}"
echo -e " - Database user: ${YELLOW}${DB_USER}${NC}"
echo -e " - Database pass: ${YELLOW}${DB_PASS}${NC}"
echo -e ""
echo -e "${BLUE}Nginx Templates created at:${NC}"
echo -e " - Laravel: ${YELLOW}/etc/nginx/sites-available/laravel.template${NC}"
echo -e " - Next.js: ${YELLOW}/etc/nginx/sites-available/nextjs.template${NC}"
echo -e ""
echo -e "${YELLOW}Note: Store these credentials safely. Use 'sudo certbot --nginx' to configure SSL.${NC}"
echo -e "${GREEN}===================================================================${NC}"
