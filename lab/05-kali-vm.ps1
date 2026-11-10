# Etape 5 : VM Kali (attaquant, Red Team) sur le WAN simule, 192.168.56.66
# Image officielle : https://cdimage.kali.org/current/ (archive .7z VirtualBox, verifiee par SHA256)
. (Join-Path $PSScriptRoot "lib.ps1")

$VmKali = "SOC-Kali"
$archive = Get-ChildItem $Images -Filter "kali-linux-*-virtualbox-amd64.7z" | Select-Object -First 1
if (-not $archive) { throw "Image Kali absente de $Images" }
if (Test-Vm $VmKali) { Write-Host "$VmKali existe deja"; return }

# 1. Empreinte publiee par Kali
$expected = ((Get-Content (Join-Path $Images "kali-SHA256SUMS")) -match [regex]::Escape($archive.Name) -split '\s+')[0]
if ((Get-FileHash $archive.FullName -Algorithm SHA256).Hash -ne $expected.ToUpper()) { throw "Empreinte Kali invalide" }
Write-Host "Kali : empreinte SHA256 OK"

# 2. Extraction (bsdtar de Windows : lit le 7z) dans le dossier des VMs, puis enregistrement
$dest = Join-Path $VmDir "kali"
New-Item -ItemType Directory -Force $dest | Out-Null
& "$env:SystemRoot\System32\tar.exe" -xf $archive.FullName -C $dest
# Attention : PowerShell ignore la casse, une variable $vbox ecraserait $VBox (chemin de VBoxManage)
$vboxFile = Get-ChildItem $dest -Recurse -Filter *.vbox | Select-Object -First 1
VBox registervm $vboxFile.FullName
$name = ((& $VBox showvminfo $vboxFile.FullName --machinereadable | Select-String '^name=') -replace 'name="(.*)"', '$1')
VBox modifyvm $name --name $VmKali
VBox modifyvm $VmKali --memory 2048 --cpus 2 --graphicscontroller vmsvga --audio-enabled off --usb off `
    --nic1 hostonly --hostonlyadapter1 $HostOnly --nictype1 82540EM --nic2 none
VBox startvm $VmKali --type headless
Write-Host "$VmKali demarre. Suite : 05b-kali-config.ps1 (apres 2 a 3 min de demarrage)"
