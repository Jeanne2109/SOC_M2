# Etape 7b : cle SSH + Docker/TheHive/n8n sur SOC-IA, puis bascule sur le VLAN Outils (10.10.30.20)
# La partie Claude (n8n) attend la cle d'API Anthropic de l'utilisateur.
. (Join-Path $PSScriptRoot "lib.ps1")
$VmIa = "SOC-IA"; $nat = @("-p", "2223"); $ia = "socadmin@127.0.0.1"

# Phase 0 : cle SSH + openssh-server par la console (le modele Ubuntu 24.04 ne depose pas la cle)
# Option -SansConsole : sauter cette phase si la cle est deja en place
if (-not ($args -contains '-SansConsole')) {
$pw = (Get-Content (Join-Path $Secrets "soc-ia.pw") -Raw).Trim()
$pub = (Get-Content "$SshKey.pub" -Raw).Trim()
Send-Key $VmIa Enter; Start-Sleep 2
Send-Line $VmIa "socadmin"; Start-Sleep 3; Send-Line $VmIa $pw; Start-Sleep 6
Send-Line $VmIa "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$pub' > ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"; Start-Sleep 4
Send-Line $VmIa "echo '$pw' | sudo -S sh -c 'echo ""socadmin ALL=(ALL) NOPASSWD:ALL"" > /etc/sudoers.d/90-soc-lab && chmod 440 /etc/sudoers.d/90-soc-lab'"; Start-Sleep 4
Send-Line $VmIa "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q openssh-server && sudo systemctl enable --now ssh && exit"
Start-Sleep 90
ssh-keygen -q -R "[127.0.0.1]:2223" -f "$Secrets\known_hosts" 2>&1 | Out-Null
}

# Phase 1 : Docker + TheHive (profil testing) + n8n via setup-soc-ia.sh
$mac = ((& $VBox showvminfo $VmIa --machinereadable | Select-String '^macaddress1=') -replace '.*="(.*)"', '$1')
$mac = ($mac -split '(..)' -ne '' -join ':').ToLower()
& scp -q -i $SshKey -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o "UserKnownHostsFile=`"$Secrets\known_hosts`"" -P 2223 `
    (Join-Path $Lab "ia\setup-soc-ia.sh") (Join-Path $Lab "ia\docker-compose-n8n.yml") "${ia}:/tmp/"
if ($LASTEXITCODE -ne 0) { throw "Copie vers SOC-IA impossible : arret avant la bascule sur le VLAN" }
# N8N_VERSION : derniere version stable au moment de l'execution
$r = Invoke-SshScript $ia "sudo N8N_VERSION='2.46.6' bash /tmp/setup-soc-ia.sh && echo SETUP_OK" $nat
$r
if (($r -join "`n") -notmatch 'SETUP_OK') { throw "Installation de TheHive/n8n en echec : la VM reste sur la carte NAT" }

# Phase 2 : bascule sur le VLAN Outils + carte d'administration 192.168.56.20 (acces depuis le PC, comme Wazuh)
$admin = "network:`n  version: 2`n  ethernets:`n    soc-admin:`n      match: {macaddress: `"08:00:27:a1:a0:20`"}`n      dhcp4: false`n      addresses: [192.168.56.20/24]`n"
Invoke-SshScript $ia "printf '%s' '$admin' | sudo tee /etc/netplan/61-soc-admin.yaml >/dev/null && sudo chmod 600 /etc/netplan/61-soc-admin.yaml" $nat
Invoke-SshScript $ia "sudo poweroff" $nat
while (Test-VmRunning $VmIa) { Start-Sleep 5 }
VBox modifyvm $VmIa --natpf1 delete ssh
VBox modifyvm $VmIa --nic1 intnet --intnet1 $NetOutils --nic2 hostonly --hostonlyadapter2 $HostOnly --macaddress2 080027A1A020
VBox startvm $VmIa --type headless
Write-Host "SOC-IA bascule sur 10.10.30.20 (admin 192.168.56.20). TheHive https://192.168.56.20/thehive | n8n http://192.168.56.20:5678"
Write-Host "Reste : licence Community TheHive (portail StrangeBee) + cle API Anthropic dans n8n + import du workflow."
