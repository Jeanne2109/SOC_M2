# Etape 6 : VM SRV-WEB (Ubuntu Server 24.04 + DVWA + agent Wazuh), cible 10.10.20.20
# Installation automatique avec une carte NAT temporaire (Internet + SSH sur 127.0.0.1:2222),
# puis bascule sur le VLAN Serveurs (06b-srvweb-config.ps1).
. (Join-Path $PSScriptRoot "lib.ps1")

$VmWeb = "SOC-SRV-WEB"
$iso = Get-ChildItem $Images -Filter "ubuntu-24.04*-live-server-amd64.iso" | Select-Object -First 1
if (-not $iso) { throw "ISO Ubuntu absente de $Images" }
if (Test-Vm $VmWeb) { Write-Host "$VmWeb existe deja"; return }

# Empreinte publiee par Ubuntu
$expected = ((Get-Content (Join-Path $Images "ubuntu-SHA256SUMS")) -match [regex]::Escape($iso.Name) -split '\s+')[0]
if ((Get-FileHash $iso.FullName -Algorithm SHA256).Hash -ne $expected.ToUpper()) { throw "Empreinte Ubuntu invalide" }
Write-Host "Ubuntu : empreinte SHA256 OK"

# Mot de passe du compte d'administration, genere une fois
$pwFile = Join-Path $Secrets "srv-web.pw"
if (-not (Test-Path $pwFile)) {
    $chars = [char[]]'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'
    -join (1..16 | ForEach-Object { $chars | Get-Random }) | Set-Content -NoNewline $pwFile
    Add-Content (Join-Path $Secrets "lab-credentials.txt") "srv_web_user=socadmin (mot de passe dans secrets\srv-web.pw)"
}
$pub = (Get-Content "$SshKey.pub" -Raw).Trim()

VBox createvm --name $VmWeb --ostype Ubuntu_64 --basefolder $VmDir --register
# 1 vCPU : avec 2 vCPU, Ubuntu part en soft lockup au demarrage sous Hyper-V
VBox modifyvm $VmWeb --memory 2048 --cpus 1 --rtcuseutc on --graphicscontroller vmsvga --audio-enabled off --usb off `
    --nic1 nat --nictype1 82540EM --natpf1 "ssh,tcp,127.0.0.1,2222,,22"
$disk = Join-Path $VmDir "$VmWeb\$VmWeb.vdi"
VBox createmedium disk --filename $disk --size 20480 --format VDI
VBox storagectl $VmWeb --name SATA --add sata --controller IntelAhci --portcount 2
VBox storageattach $VmWeb --storagectl SATA --port 0 --device 0 --type hdd --medium $disk

# Fin d'installation : cle SSH du labo, serveur SSH, sudo sans mot de passe
# (constate le 30/10 : sans effet avec le modele Ubuntu 24.04 de VirtualBox 7.2 ; 06b le refait par la console)
# Sous Hyper-V, le demarrage sur l'ISO prend environ 30 min (lecture du CD par le BIOS), l'installation 15 min.
$post = "mkdir -p /target/home/socadmin/.ssh && echo '$pub' > /target/home/socadmin/.ssh/authorized_keys && " +
        "echo 'socadmin ALL=(ALL) NOPASSWD:ALL' > /target/etc/sudoers.d/90-soc-lab && " +
        "curtin in-target -- apt-get install -y openssh-server && " +
        "curtin in-target -- chown -R socadmin:socadmin /home/socadmin/.ssh"
VBox unattended install $VmWeb --iso $iso.FullName --user socadmin --password-file $pwFile `
    --full-user-name "Admin SOC" --hostname "srv-web.lab.local" --locale en_US --time-zone Europe/Paris `
    --post-install-command $post --start-vm headless
Write-Host "Installation d'Ubuntu en cours (20 a 40 min sous Hyper-V). Suivi : ssh -p 2222 socadmin@127.0.0.1"
