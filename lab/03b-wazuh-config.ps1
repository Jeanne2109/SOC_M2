# Etape 3b : premiere configuration de la VM Wazuh
#  1. par la console (compte par defaut de l'OVA) : cle SSH du labo, sudo sans mot de passe,
#     adresse fixe de la carte d'administration
#  2. par SSH : adresse 10.10.30.10 sur eth0 (VLAN Outils), passerelle OPNsense, delais de demarrage
. (Join-Path $PSScriptRoot "lib.ps1")

$pub = (Get-Content "$SshKey.pub" -Raw).Trim()
function Mac([int]$n) {
    $m = ((& $VBox showvminfo $VmWazuh --machinereadable | Select-String "^macaddress$n=") -replace '.*="(.*)"', '$1')
    ($m -split '(..)' -ne '' -join ':').ToLower()
}

# 1. Console. Remarques : la VM est en mode FIPS (cles Ed25519 refusees, d'ou la cle ECDSA),
#    et la cle Ed25519 "vagrant" laissee dans authorized_keys est retiree.
Send-Line $VmWazuh "wazuh-user"; Start-Sleep 3
Send-Line $VmWazuh "wazuh"; Start-Sleep 6
Send-Line $VmWazuh "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$pub' > ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && restorecon -R ~/.ssh"
Start-Sleep 4
Send-Line $VmWazuh "echo wazuh | sudo -S sh -c 'echo ""wazuh-user ALL=(ALL) NOPASSWD:ALL"" > /etc/sudoers.d/90-soc-lab && chmod 440 /etc/sudoers.d/90-soc-lab'"
Start-Sleep 4
# Carte d'administration en adresse fixe (le DHCP host-only de VirtualBox n'est pas fiable).
# Prefixe 15- : sinon le fichier 20-eth0.network de l'OVA capte aussi eth1.
Send-Line $VmWazuh "printf '[Match]\nMACAddress=$(Mac 2)\n\n[Network]\nAddress=$($Ip.WazuhAdmin)/24\n' | sudo tee /etc/systemd/network/15-soc-admin.network >/dev/null && sudo networkctl reload && sudo networkctl reconfigure eth1"
Start-Sleep 10
Send-Line $VmWazuh "exit"

# 2. SSH : adresse de production sur la carte 1 (soc-outils) et delais de demarrage
#    (sous Hyper-V, l'indexer depasse le delai par defaut de systemd)
Invoke-SshScript "wazuh-user@$($Ip.WazuhAdmin)" @"
sudo -n tee /etc/systemd/network/10-soc-outils.network >/dev/null <<'EOF'
[Match]
MACAddress=$(Mac 1)

[Network]
Address=$($Ip.Wazuh)/24
Gateway=$($Ip.OpnOutils)
DNS=$($Ip.OpnOutils)
EOF
sudo -n networkctl reload
for s in wazuh-indexer wazuh-manager wazuh-dashboard; do
  sudo -n mkdir -p /etc/systemd/system/`$s.service.d
  printf '[Service]\nTimeoutStartSec=600\n' | sudo -n tee /etc/systemd/system/`$s.service.d/90-soc-lab.conf >/dev/null
done
sudo -n systemctl daemon-reload
ip -4 -br a
"@
