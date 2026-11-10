# Etape 6c : detection des attaques applicatives web
#  - OPNsense : jeu ET emerging-web_server, flux F1 (WAN -> SRV-WEB:80)
#  - Wazuh : regle 100107 (groupe soc,ids_reseau) -> reponse active soc-drop
#  - la liste d'IOC de test (regle 1000010) pointe sur 203.0.113.66, pas sur Kali,
#    pour que Kali ne soit pas bloquee des son premier paquet (ER1) pendant les tests web
. (Join-Path $PSScriptRoot "lib.ps1")
$o = "root@$($Ip.OpnWan)"
$w = "wazuh-user@$($Ip.WazuhAdmin)"
function Copy-To($l, $r) { & scp -q -i $SshKey -o BatchMode=yes -o "UserKnownHostsFile=`"$Secrets\known_hosts`"" $l $r }

# 1. OPNsense : flux F1, jeu ET web_server, regles SOC a jour
Copy-To (Join-Path $Lab "opnsense\soc-web-rule.php") "${o}:/root/"
Copy-To (Join-Path $Lab "opnsense\soc-ids-web.php") "${o}:/root/"
Copy-To (Join-Path $Lab "opnsense\soc-local.rules") "${o}:/tmp/soc-local.rules"
Invoke-SshScript $o @'
php /root/soc-web-rule.php && configctl filter reload
php /root/soc-ids-web.php
tr -d '\r' < /tmp/soc-local.rules > /root/soc-rules/soc-local.rules
configctl template reload OPNsense/IDS
cd /root/soc-rules && (python3 -m http.server 8088 --bind 127.0.0.1 >/dev/null 2>&1 &); sleep 2
configctl ids update
sleep 60
pkill -f 'http.server 8088'
configctl ids install rules
configctl ids reload
'@

# 2. Wazuh : regle 100107 (local_rules.xml) + reponse active (ossec-soc.conf deja a jour)
Copy-To (Join-Path $Lab "wazuh\local_rules.xml") "${w}:/tmp/"
Invoke-SshScript $w @'
sudo -n install -m 660 -o wazuh -g wazuh /tmp/local_rules.xml /var/ossec/etc/rules/local_rules.xml
sudo -n /var/ossec/bin/wazuh-analysisd -t && sudo -n systemctl restart wazuh-manager
'@

# 3. Controle : attaque web depuis Kali (XSS + traversee) -> detection -> blocage
Start-Sleep 30
Invoke-SshScript "kali@$($Ip.Kali)" @'
curl -s -o /dev/null "http://10.10.20.20/dvwa/vulnerabilities/xss_r/?name=%3Cscript%3Ealert(1)%3C/script%3E"
curl -s -o /dev/null "http://10.10.20.20/dvwa/vulnerabilities/fi/?page=../../../../etc/passwd"
echo "attaques web envoyees"
'@
Start-Sleep 25
Invoke-SshScript $o "echo '--- IP bloquees :'; pfctl -t __wazuh_agent_drop -T show; tail -n 2 /var/ossec/logs/active-responses.log"
