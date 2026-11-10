# Etape 2c : sortie Internet, Suricata (IDS sur le WAN, ET Open + regles SOC), agent Wazuh
# Prerequis : 02b fait (SSH root par cle), VM Wazuh demarree (10.10.30.10)
# Les fichiers PHP et les regles sont dans opnsense\
. (Join-Path $PSScriptRoot "lib.ps1")
$src = Join-Path $Lab "opnsense"
$opn = "root@$($Ip.OpnWan)"

# 1. Carte 4 en NAT VirtualBox = sortie Internet (le WAN host-only n'en donne pas)
if (((& $VBox showvminfo $VmOpn --machinereadable) -match '^nic4=') -notmatch 'nat') {
    Invoke-Ssh $opn "shutdown -p now" | Out-Null
    while (Test-VmRunning $VmOpn) { Start-Sleep 5 }
    VBox modifyvm $VmOpn --nic4 nat --nictype4 82540EM
    VBox startvm $VmOpn --type headless
    while (-not (Test-NetConnection $Ip.OpnWan -Port 22 -InformationLevel Quiet -WarningAction SilentlyContinue)) { Start-Sleep 10 }
}

function Push([string]$File, [string]$Dest) {
    & scp -q -i $SshKey -o BatchMode=yes -o "UserKnownHostsFile=`"$Secrets\known_hosts`"" (Join-Path $src $File) "${opn}:$Dest"
}
Push "soc-internet.php" "/root/"
Push "soc-ids.php" "/root/"
Push "soc-ids-local.php" "/root/"
Push "soc-wazuh-agent.php" "/root/"
Push "soc-local.xml" "/usr/local/opnsense/scripts/suricata/metadata/rules/"
Invoke-SshScript $opn "mkdir -p /root/soc-rules"
Push "soc-local.rules" "/root/soc-rules/"

# 2. Interface INTERNET (em3, DHCP) + regle de sortie du VLAN Outils
Invoke-SshScript $opn @'
php /root/soc-internet.php && configctl interface reconfigure opt2 && configctl filter reload
'@

# 3. Suricata : IDS sur le WAN, 8 jeux ET Open, regles locales SOC servies en local le temps du telechargement
#    (le Suricata d'OPNsense est compile sans GeoIP : la regle ER2 est retiree, ER2 passe par l'alias GeoIP)
Invoke-SshScript $opn @'
pkg update -q
php /root/soc-ids.php
php /root/soc-ids-local.php
configctl template reload OPNsense/IDS
configctl template reload OPNsense/Cron
cd /root/soc-rules && (python3 -m http.server 8088 --bind 127.0.0.1 >/dev/null 2>&1 &); sleep 2
configctl ids update
sleep 60
pkill -f 'http.server 8088'
configctl ids install rules
configctl ids start
'@

# 4. Agent Wazuh (plugin os-wazuh-agent) : lit /var/log/suricata/eve.json
Invoke-SshScript $opn @'
pkg install -y os-wazuh-agent
php /root/soc-wazuh-agent.php
configctl template reload OPNsense/WazuhAgent
configctl wazuh_agent restart
'@

# 5. Controle : ping du PC vers le WAN -> regle SOC TEST 1000090 -> regle Wazuh 86601
Start-Sleep 30
Test-Connection $Ip.OpnWan -Count 2 -Quiet | Out-Null
Start-Sleep 20
Invoke-SshScript "wazuh-user@$($Ip.WazuhAdmin)" "sudo -n /var/ossec/bin/agent_control -l | grep opnsense; sudo -n grep -c 'SOC TEST ping' /var/ossec/logs/alerts/alerts.json"
