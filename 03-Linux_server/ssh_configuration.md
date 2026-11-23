It was pretty easy.

1. SSH was installed during the Ubuntu installation (there's a pop-up that asks you about it during the installation, i said yes).
2. I generated a SSH key in my Windows machine with: ssh-keygen -t ed25519 -C "mymail@example.com"
3. I imported it to my Ubuntu Server VM using: \
   Get-Content $env:USERPROFILE\.ssh\id_ed25519.pub | ssh sysadmin@192.168.50.20 "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys" \
   I had to retort to this because PowerShell doesn't have the convenient "ssh-copy-id" command.
5. I inputed the sysadmin's password when prompted.
6. Done. I logged in correctly using: ssh sysadmin@192.168.50.20
7. I tested that SSH is using the key to login, without using password:
   ssh -o PubkeyAuthentication=yes -o PasswordAuthentication=no -i $env:USERPROFILE\.ssh\id_ed25519 sysadmin@192.168.50.20
8. The login was successful. I see no reason to disable password authentication. So SSH setup ends here.
