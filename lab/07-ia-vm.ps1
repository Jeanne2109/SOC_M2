# Etape 7 (bonus IA) : VM SOC-IA (Ubuntu 24.04 + Docker + TheHive + n8n), 10.10.30.20
# Meme methode que SRV-WEB : carte NAT temporaire pour l'installation (SSH sur 127.0.0.1:2223),
# puis bascule sur le VLAN Outils. La partie Claude attend la cle d'API de l'utilisateur.
# Prerequis : au moins 6 Go disponibles. Pendant l'installation, mettre Wazuh en veille
# (VBoxManage controlvm SOC-Wazuh savestate) : l'installation n'a pas besoin de lui.
# 5 Go de RAM : TheHive, Cassandra et Elasticsearch sont reduits a 768 Mo de tas Java (setup-soc-ia.sh).
. (Join-Path $PSScriptRoot "lib.ps1")

$VmIa = "SOC-IA"
$iso = Get-ChildItem $Images -Filter "ubuntu-24.04*-live-server-amd64.iso" | Select-Object -First 1
if (-not $iso) { throw "ISO Ubuntu absente de $Images" }
if (Test-Vm $VmIa) { Write-Host "$VmIa existe deja"; return }

$free = (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB
if ($free -lt 6) { Write-Warning ("Seulement {0:N1} Go libres. Mettre Wazuh en veille avant : VBoxManage controlvm SOC-Wazuh savestate" -f $free) }

$pwFile = Join-Path $Secrets "soc-ia.pw"
if (-not (Test-Path $pwFile)) {
    $chars = [char[]]'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'
    -join (1..16 | ForEach-Object { $chars | Get-Random }) | Set-Content -NoNewline $pwFile
    Add-Content (Join-Path $Secrets "lab-credentials.txt") "soc_ia_user=socadmin (mot de passe dans secrets\soc-ia.pw)"
}

VBox createvm --name $VmIa --ostype Ubuntu_64 --basefolder $VmDir --register
# 2 vCPU : TheHive (Cassandra + Elasticsearch + JVM) a besoin de coeurs ; surveiller un eventuel soft lockup
VBox modifyvm $VmIa --memory 5120 --cpus 2 --rtcuseutc on --graphicscontroller vmsvga --audio-enabled off --usb off `
    --nic1 nat --nictype1 82540EM --natpf1 "ssh,tcp,127.0.0.1,2223,,22"
$disk = Join-Path $VmDir "$VmIa\$VmIa.vdi"
VBox createmedium disk --filename $disk --size 61440 --format VDI
VBox storagectl $VmIa --name SATA --add sata --controller IntelAhci --portcount 2
VBox storageattach $VmIa --storagectl SATA --port 0 --device 0 --type hdd --medium $disk

VBox unattended install $VmIa --iso $iso.FullName --user socadmin --password-file $pwFile `
    --full-user-name "Admin SOC" --hostname "soc-ia.lab.local" --locale en_US --time-zone Europe/Paris --start-vm headless
Write-Host "Installation d'Ubuntu en cours (demarrage lent sous Hyper-V). Ensuite : 07b-ia-config.ps1"
