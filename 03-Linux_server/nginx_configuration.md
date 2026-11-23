It was pretty simple. Now i'm going to work on the Website. To get nginx working, i: \

1. Like before: sudo apt update && sudo apt upgrade
2. Then, i installed nginx: sudo apt install nginx -y
3. I ran nginx: sudo systemctl status nginx
4. The Default page is running. I cheked at http//192.168.50.20
5. I created the setup for when i have the page done, creating a folder for it, and making nginx launch THAT page instead of the default one:
  sudo nano /etc/nginx/sites-available/northstar
  That file contains: \
  server {
      listen 80;
      listen [::]:80;
  
      server_name 192.168.50.20;
      root /var/www/northstar/html;
      index index.html;
  
      location / {
          try_files $uri $uri/ =404;
      }
  }
6. Now, the setup is done. I'm going to work on the page.
