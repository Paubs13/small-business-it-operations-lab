Again, pretty easy. The process was: 
1. Good practice in Linux, specially in stable releases, to: sudo apt update && sudo apt upgrade
2. Then, just to be certain: sudo apt update && sudo apt install ufw -y
3. Finally, the following steps are the setup itself of the rules: sudo ufw default deny incoming
4. sudo ufw default allow outgoing
5. sudo ufw allow 22/tcp
6. sudo ufw allow 80/tcp
7. We enable the rules we just setuped: sudo ufw enable
8. We check that they're enabled. See screenshot: sudo ufw status verbose
