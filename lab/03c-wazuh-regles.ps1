# Etape 3c : regles SOC dans Wazuh, journaux du pare-feu, blocage automatique sur OPNsense
# Prerequis : 02c fait (agent "opnsense" actif, ID 001)
. (Join-Path $PSScriptRoot "lib.ps1")
$w = "wazuh-user@$($Ip.WazuhAdmin)"
$o = "root@$($Ip.OpnWan)"
function Copy-To([string]$Local, [string]$Remote) {
    & scp -q -i $SshKey -o BatchMode=yes -o "UserKnownHostsFile=`"$Secrets\known_hosts`"" $Local $Remote
}

# 1. Manager : regles SOC (wazuh\local_rules.xml) et reponse active (wazuh\ossec-soc.conf)
Copy-To (Join-Path $Lab "wazuh\local_rules.xml") "${w}:/tmp/"
Copy-To (Join-Path $Lab "wazuh\ossec-soc.conf") "${w}:/tmp/"
Invoke-SshScript $w @'
set -e
sudo -n cp -n /var/ossec/etc/rules/local_rules.xml /var/ossec/etc/rules/local_rules.xml.ova
sudo -n install -m 660 -o wazuh -g wazuh /tmp/local_rules.xml /var/ossec/etc/rules/local_rules.xml
sudo -n grep -q 'SOC-LAB' /var/ossec/etc/ossec.conf || { sudo -n cp /var/ossec/etc/ossec.conf /var/ossec/etc/ossec.conf.ova; sudo -n sh -c 'cat /tmp/ossec-soc.conf >> /var/ossec/etc/ossec.conf'; }
sudo -n /var/ossec/bin/wazuh-analysisd -t
sudo -n systemctl restart wazuh-manager
'@

# 2. OPNsense : script de blocage soc-drop (table pf __wazuh_agent_drop du plugin)
#    et envoi des journaux du pare-feu (filterlog) par l'agent
Copy-To (Join-Path $Lab "opnsense\soc-drop") "${o}:/tmp/soc-drop"
Copy-To (Join-Path $Lab "opnsense\soc-wazuh-syslog.php") "${o}:/root/"
Invoke-SshScript $o @'
tr -d '\r' < /tmp/soc-drop > /var/ossec/active-response/bin/soc-drop
chown root:wazuh /var/ossec/active-response/bin/soc-drop
chmod 750 /var/ossec/active-response/bin/soc-drop
php /root/soc-wazuh-syslog.php
configctl template reload OPNsense/WazuhAgent
configctl template reload OPNsense/Syslog
configctl syslog restart
configctl wazuh_agent restart
'@

# 3. Controle de bout en bout : alerte ER4 injectee (adresse de documentation 203.0.113.46)
#    -> regle 100104 -> soc-drop -> table pf
Start-Sleep 40
Invoke-SshScript $o @'
ts=$(date -u +%Y-%m-%dT%H:%M:%S.000000+0000)
echo "{\"timestamp\":\"$ts\",\"event_type\":\"alert\",\"src_ip\":\"203.0.113.46\",\"src_port\":40000,\"dest_ip\":\"10.10.20.20\",\"dest_port\":80,\"proto\":\"TCP\",\"alert\":{\"action\":\"allowed\",\"gid\":1,\"signature_id\":1000040,\"rev\":1,\"signature\":\"SOC ER4 scan de ports (test injecte)\",\"severity\":2}}" >> /var/log/suricata/eve.json
sleep 30
pfctl -t __wazuh_agent_drop -T show
tail -n 1 /var/ossec/logs/active-responses.log
pfctl -t __wazuh_agent_drop -T delete 203.0.113.46
'@
