# Etape 3 : importe l'OVA Wazuh et la branche sur le VLAN Outils
# Carte 1 : intnet soc-outils (10.10.30.10, adresse de production)
# Carte 2 : host-only, carte d'administration temporaire (DHCP VirtualBox) pour piloter la VM depuis le PC
. (Join-Path $PSScriptRoot "lib.ps1")

if (Test-Vm $VmWazuh) { Write-Host "$VmWazuh existe deja"; return }

# 2 vCPU : sous Hyper-V, 4 vCPU provoquaient des blocages du noyau (soft lockup) sur l'indexer
VBox import $WazuhOva --vsys 0 --vmname $VmWazuh --basefolder $VmDir --cpus 2 --memory 6144
# 6 Go et non 8 : avec SOC-IA (5 Go) et OPNsense, le PC du labo ne peut pas donner plus (constate le 09/11)
VBox modifyvm $VmWazuh --graphicscontroller vmsvga --rtcuseutc on --audio-enabled off `
    --nic1 intnet --intnet1 $NetOutils --nictype1 82540EM `
    --nic2 hostonly --hostonlyadapter2 $HostOnly --nictype2 82540EM

# Adresse d'administration fixe (reservation DHCP VirtualBox) : 192.168.56.10
VBox dhcpserver modify "--network=HostInterfaceNetworking-$HostOnly" --vm=$VmWazuh --nic=2 --fixed-address=$($Ip.WazuhAdmin)

VBox startvm $VmWazuh --type headless
# Ensuite (console, compte wazuh-user) : cle SSH du labo, sudo sans mot de passe, IP 10.10.30.10 sur eth0
# -> voir 03b-wazuh-config.ps1
Write-Host "$VmWazuh demarre. Le dashboard met quelques minutes a s'initialiser."
