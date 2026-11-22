

1. Update the system: sudo apt update && sudo apt upgrade -y
2. Install web server,database and required PHP extensions:
  sudo apt install -y mariadb-server php8.3-fpm php8.3-mysql php8.3-curl php8.3-gd php8.3-intl php8.3-mbstring php8.3-xml php8.3-zip php8.3-bz2 php8.3-ldap php8.3-apcu php8.3-redis php8.3-bcmath php8.3-cli wget tar
3. Enable the services: sudo systemctl enable --now nginx mariadb php8.3-fpm
4. Configure PHP settings with the following parameters (/etc/php/8.3/fpm/php.ini): \
  memory_limit = 512M \
  upload_max_filesize = 32M \
  post_max_size = 32M \
  max_execution_time = 600 \
  session.cookie_httponly = On \
  date.timezone = America/Argentina/Cordoba
5. Restart: sudo systemctl restart php8.3-fpm
6. Create MariaDB database:
  sudo mysql_secure_installation \
  sudo mysql -u root -p
7. Run the following SQL commands, replacing the password:
  CREATE DATABASE glpidb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci; \
  CREATE USER 'glpiuser'@'localhost' IDENTIFIED BY 'YourStrongPassword'; \
  GRANT ALL PRIVILEGES ON glpidb.* TO 'glpiuser'@'localhost'; \
  FLUSH PRIVILEGES; \
  EXIT;
8. Download GLPI: \
  cd /tmp && rm -f index.html \
  HOST="github.com" \
  PATH_URL="glpi-project/glpi/releases/download/11.0.8/glpi-11.0.8.tgz" \
  wget "https://${HOST}/${PATH_URL}" \
  sudo tar -xvzf glpi-11.0.8.tgz -C /var/www/
9. Set the right permissions: \ 
  sudo chown -R www-data:www-data /var/www/glpi \
  sudo chmod -R 755 /var/www/glpi
10. Add GLPI to our existing nginx adding the following lines to "/etc/nginx/sites-enabled/northstar" : \
  location ^~ /glpi { \
      alias /var/www/glpi/public; \
      index index.php; \
  
      try_files $uri $uri/ @glpi_rewrite;
  
      location ~ ^/glpi/index\.php(/|$) { \
          fastcgi_pass unix:/run/php/php8.3-fpm.sock; \
          fastcgi_split_path_info ^/glpi(/index\.php)(/.*)$; \
          include fastcgi_params; \
          fastcgi_param SCRIPT_FILENAME /var/www/glpi/public/index.php; \
          fastcgi_param SCRIPT_NAME /glpi/index.php; \
      } \
  } \
  
  location @glpi_rewrite { \
      rewrite ^/glpi/(.*)$ /glpi/index.php/$1 last; \
  }

11. Enter http://192.168.50.20/glpi and complete the web installation. Once that's done, we have GLPI enabled and we just need to enter our assets and configure the system. It's reccommended to delete the installation script and change all default user's passwords.
