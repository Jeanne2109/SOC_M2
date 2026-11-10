# Parametres communs de la maquette Projet 1 (charge par tous les scripts)

$Lab     = $PSScriptRoot
$VBox    = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
$Images  = Join-Path $Lab "images"     # ISO / OVA telecharges
$VmDir   = Join-Path $Lab "vms"        # disques et fichiers des VMs
$Secrets = Join-Path $Lab "secrets"    # cle SSH et mots de passe du labo (ne pas partager)
$Shots   = Join-Path $Lab "captures"   # captures d'ecran des consoles

# Reseaux VirtualBox
$HostOnly  = "VirtualBox Host-Only Ethernet Adapter"   # WAN simule, PC hote = 192.168.56.1
$NetSrv    = "soc-srv"                                 # VLAN Serveurs 10.10.20.0/24
$NetOutils = "soc-outils"                              # VLAN Outils 10.10.30.0/24

# Adresses
$Ip = @{
    HostWan     = "192.168.56.1"
    OpnWan      = "192.168.56.2"
    OpnSrv      = "10.10.20.1"
    OpnOutils   = "10.10.30.1"
    Wazuh       = "10.10.30.10"
    WazuhAdmin  = "192.168.56.10"     # carte d'administration host-only (reservation DHCP)
    Kali        = "192.168.56.66"
    SrvWeb      = "10.10.20.20"
    SrvWin      = "10.10.20.10"
    Ia          = "10.10.30.20"
    IaAdmin     = "192.168.56.20"
}

# Versions
$OpnVersion   = "26.7"
$OpnIso       = Join-Path $Images "OPNsense-$OpnVersion-dvd-amd64.iso"
$WazuhVersion = "4.14.9"
$WazuhOva     = Join-Path $Images "wazuh-$WazuhVersion.ova"

# Noms des VMs
$VmOpn   = "SOC-OPNsense"
$VmWazuh = "SOC-Wazuh"

$SshKey = Join-Path $Secrets "id_lab"
