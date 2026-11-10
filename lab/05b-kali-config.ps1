# Etape 5b : configuration de Kali par la console texte (tty2), compte par defaut kali/kali
#  - adresse fixe 192.168.56.66, route vers les VLAN internes via OPNsense (192.168.56.2)
#  - SSH par cle du labo, sudo sans mot de passe, demarrage sans interface graphique
. (Join-Path $PSScriptRoot "lib.ps1")
$VmKali = "SOC-Kali"
$pub = (Get-Content "$SshKey.pub" -Raw).Trim()

# Ctrl+Alt+F2 : console texte (l'ecran de connexion graphique est sur tty7)
VBox controlvm $VmKali keyboardputscancode 1d 38 3c bc b8 9d
Start-Sleep 4
Send-Line $VmKali "kali"; Start-Sleep 3
Send-Line $VmKali "kali"; Start-Sleep 6   # mot de passe par defaut publie par Kali, a changer

$cmds = @(
    "echo kali | sudo -S sh -c 'echo ""kali ALL=(ALL) NOPASSWD:ALL"" > /etc/sudoers.d/90-soc-lab && chmod 440 /etc/sudoers.d/90-soc-lab'",
    "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$pub' > ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys",
    "C=`$(nmcli -t -f NAME,DEVICE con show | grep eth0 | cut -d: -f1); sudo nmcli con mod ""`$C"" ipv4.method manual ipv4.addresses $($Ip.Kali)/24 ipv4.routes '10.10.0.0/16 $($Ip.OpnWan)' ipv6.method disabled && sudo nmcli con up ""`$C""",
    "sudo systemctl enable --now ssh",
    "sudo systemctl set-default multi-user.target",
    "ip -4 -br a; ip route"
)
foreach ($c in $cmds) { Send-Line $VmKali $c; Start-Sleep 6 }
Save-Screen $VmKali "config" | Out-Null

Invoke-Ssh "kali@$($Ip.Kali)" "echo CONNECTE_KALI; which nmap hping3 msfconsole curl"
