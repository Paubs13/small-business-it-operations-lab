It was pretty easy.

1. SSH was installed during the Ubuntu installation (there's a pop-up that asks you about it during the installation, i said yes).
2. I generated a SSH key in my Windows machine with: ssh-keygen -t ed25519 -C "mymail@example.com"
3. I imported it to my Ubuntu Server VM using: Get-Content $env:USERPROFILE\.ssh\id_ed25519.pub | ssh sysadmin@192.168.50.20 "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
4. I inputed the sysadmin's password when prompted.
5. Done. I logged in correctly using: ssh sysadmin@192.168.50.20
