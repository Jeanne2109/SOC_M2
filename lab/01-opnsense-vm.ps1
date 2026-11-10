# Etape 1 : cree la VM OPNsense (3 cartes : WAN, SERVEURS, OUTILS) et la demarre sur l'ISO
. (Join-Path $PSScriptRoot "lib.ps1")

if (Test-Vm $VmOpn) { Write-Host "$VmOpn existe deja"; return }

VBox createvm --name $VmOpn --ostype FreeBSD_64 --basefolder $VmDir --register
VBox modifyvm $VmOpn --memory 4096 --cpus 2 --firmware bios --rtcuseutc on `
    --graphicscontroller vmsvga --vram 16 --audio-enabled off --usb off `
    --boot1 dvd --boot2 disk --boot3 none --boot4 none `
    --nic1 hostonly --hostonlyadapter1 $HostOnly --nictype1 82540EM `
    --nic2 intnet --intnet2 $NetSrv --nictype2 82540EM --nicpromisc2 deny `
    --nic3 intnet --intnet3 $NetOutils --nictype3 82540EM

$disk = Join-Path $VmDir "$VmOpn\$VmOpn.vdi"
VBox createmedium disk --filename $disk --size 30720 --format VDI
VBox storagectl $VmOpn --name SATA --add sata --controller IntelAhci --portcount 2
VBox storageattach $VmOpn --storagectl SATA --port 0 --device 0 --type hdd --medium $disk
VBox storageattach $VmOpn --storagectl SATA --port 1 --device 0 --type dvddrive --medium $OpnIso

VBox startvm $VmOpn --type headless
Write-Host "$VmOpn demarre sur l'ISO. Suite : installation depuis la console (02-opnsense-install.ps1)."
