# Etape 6b : DVWA + agent Wazuh sur SRV-WEB, puis bascule sur le VLAN Serveurs (10.10.20.20)
. (Join-Path $PSScriptRoot "lib.ps1")
$VmWeb = "SOC-SRV-WEB"
$nat = @("-p", "2222")
$web = "socadmin@127.0.0.1"

# ---- Phase 0 : par la console (la commande de fin d'installation de VBoxManage n'a pas
#      depose la cle ni installe openssh-server avec le modele Ubuntu 24.04) ----
$pw = (Get-Content (Join-Path $Secrets "srv-web.pw") -Raw).Trim()
$pub = (Get-Content "$SshKey.pub" -Raw).Trim()
Send-Key $VmWeb Enter; Start-Sleep 2
Send-Line $VmWeb "socadmin"; Start-Sleep 3; Send-Line $VmWeb $pw; Start-Sleep 6
Send-Line $VmWeb "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$pub' > ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"; Start-Sleep 4
Send-Line $VmWeb "echo '$pw' | sudo -S sh -c 'echo ""socadmin ALL=(ALL) NOPASSWD:ALL"" > /etc/sudoers.d/90-soc-lab && chmod 440 /etc/sudoers.d/90-soc-lab'"; Start-Sleep 4
Send-Line $VmWeb "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q openssh-server && sudo systemctl enable --now ssh && exit"
Start-Sleep 120
# La cle d'hote de l'environnement d'installation differe de celle du systeme installe
ssh-keygen -q -R "[127.0.0.1]:2222" -f "$Secrets\known_hosts" 2>&1 | Out-Null

# ---- Phase 1 : sur la carte NAT (Internet), SSH par 127.0.0.1:2222 ----
$mac = ((& $VBox showvminfo $VmWeb --machinereadable | Select-String '^macaddress1=') -replace '.*="(.*)"', '$1')
$mac = ($mac -split '(..)' -ne '' -join ':').ToLower()

Invoke-SshScript $web @"
set -e
export DEBIAN_FRONTEND=noninteractive
sudo -E apt-get update -q
sudo -E apt-get install -y -q apache2 mariadb-server php php-mysqli php-gd libapache2-mod-php git curl gnupg

# DVWA (application volontairement vulnerable, niveau de securite 'low' pour les tests)
[ -d /var/www/html/dvwa ] || sudo git clone -q https://github.com/digininja/DVWA.git /var/www/html/dvwa
cd /var/www/html/dvwa
sudo cp -n config/config.inc.php.dist config/config.inc.php
sudo sed -i "s/'default_security_level' \] *= *'[a-z]*'/'default_security_level' ] = 'low'/" config/config.inc.php
sudo mysql -e "CREATE DATABASE IF NOT EXISTS dvwa; CREATE USER IF NOT EXISTS 'dvwa'@'localhost' IDENTIFIED BY 'p@ssw0rd'; GRANT ALL ON dvwa.* TO 'dvwa'@'localhost'; FLUSH PRIVILEGES;"
sudo chown -R www-data:www-data /var/www/html/dvwa/hackable/uploads /var/www/html/dvwa/config
sudo systemctl restart apache2

# Agent Wazuh 4.14.9 (meme version que le manager), enregistre sous le nom srv-web
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | sudo gpg --dearmor --yes -o /usr/share/keyrings/wazuh.gpg
echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" | sudo tee /etc/apt/sources.list.d/wazuh.list >/dev/null
sudo apt-get update -q
sudo WAZUH_MANAGER='$($Ip.Wazuh)' WAZUH_AGENT_NAME='srv-web' -E apt-get install -y -q wazuh-agent=4.14.9-1
sudo apt-mark hold wazuh-agent
# FIM en temps reel sur le site web et /tmp
sudo sed -i 's|<directories>/etc,/usr/bin,/usr/sbin</directories>|<directories>/etc,/usr/bin,/usr/sbin</directories>\n    <directories realtime="yes" check_all="yes">/var/www/html</directories>\n    <directories realtime="yes" check_all="yes">/tmp</directories>|' /var/ossec/etc/ossec.conf
sudo systemctl enable wazuh-agent

# Adresse de production, appliquee au prochain demarrage (sur le VLAN Serveurs)
sudo tee /etc/netplan/60-soc-srv.yaml >/dev/null <<'EOF'
network:
  version: 2
  ethernets:
    soc-srv:
      match: {macaddress: "$mac"}
      dhcp4: false
      addresses: [$($Ip.SrvWeb)/24]
      routes: [{to: default, via: $($Ip.OpnSrv)}]
      nameservers: {addresses: [$($Ip.OpnSrv)]}
EOF
sudo chmod 600 /etc/netplan/60-soc-srv.yaml
sudo rm -f /etc/netplan/50-cloud-init.yaml
echo 'network: {config: disabled}' | sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg >/dev/null
echo PHASE1_OK
"@ $nat

# Base DVWA : page setup.php (jeton anti-CSRF)
Invoke-SshScript $web @'
cd /tmp && rm -f c.txt
tok=$(curl -s -c c.txt http://127.0.0.1/dvwa/setup.php | grep -o "user_token' value='[a-f0-9]*" | cut -d"'" -f3)
curl -s -b c.txt -d "create_db=Create+%2F+Reset+Database&user_token=$tok" http://127.0.0.1/dvwa/setup.php | grep -o 'Setup successful[^<]*' | head -n 1
'@ $nat

# ---- Phase 2 : bascule sur le VLAN Serveurs ----
Invoke-SshScript $web "sudo poweroff" $nat
while (Test-VmRunning $VmWeb) { Start-Sleep 5 }
VBox modifyvm $VmWeb --natpf1 delete ssh
VBox modifyvm $VmWeb --nic1 intnet --intnet1 $NetSrv
VBox startvm $VmWeb --type headless
Start-Sleep 120
Invoke-SshScript "socadmin@$($Ip.SrvWeb)" "ip -4 -br a; systemctl is-active apache2 wazuh-agent; curl -s -o /dev/null -w 'DVWA local : HTTP %{http_code}\n' http://127.0.0.1/dvwa/login.php" (Get-JumpOpts)
