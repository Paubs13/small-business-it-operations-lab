Again, pretty easy. The process was: 
1. Good practice in Linux, specially in stable releases, to: sudo apt update && sudo apt upgrade
2. Then, just to be certain: sudo apt update && sudo apt install ufw -y
3. Finally, the following steps are the setup itself of the rules: sudo ufw default deny incoming
4. sudo ufw default allow outgoing
5. sudo ufw allow 22/tcp
6. sudo ufw allow 80/tcp
7. We enable the rules we just setuped: sudo ufw enable
8. We check that they're enabled: sudo ufw status verbose

Update 1: \
I've decided to only allow SSH from my subnet. So, to make this, i did the following:
1. Create the rule: sudo ufw allow from 192.168.50.0/24 to any port 22 proto tcp
2. Check how rules are numbered: sudo ufw status numbered
3. In my case, the rules i wanted to delete were 1 and 4, So, we delete from highest number to lowest:
   sudo ufw 4 \
   sudo ufw 1 \
4. Check that the rules are ok. See screenshot: sudo ufw status verbose
