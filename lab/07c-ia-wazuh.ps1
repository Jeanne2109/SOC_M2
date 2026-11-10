# Etape 7c : Wazuh -> n8n (copilote IA) et regles SOC a jour (dont ER2 100108)
# Prerequis : 03c fait, SOC-IA sur 10.10.30.20 avec n8n demarre (07b)
. (Join-Path $PSScriptRoot "lib.ps1")
$w = "wazuh-user@$($Ip.WazuhAdmin)"
foreach ($f in "wazuh\local_rules.xml", "wazuh\ossec-soc-ia.conf", "ia\custom-n8n") {
    & scp -q -i $SshKey -o BatchMode=yes -o "UserKnownHostsFile=`"$Secrets\known_hosts`"" (Join-Path $Lab $f) "${w}:/tmp/"
    if ($LASTEXITCODE -ne 0) { throw "Copie de $f vers Wazuh impossible" }
}
Invoke-SshScript $w @'
set -e
sudo -n install -m 660 -o wazuh -g wazuh /tmp/local_rules.xml /var/ossec/etc/rules/local_rules.xml
tr -d '\r' < /tmp/custom-n8n > /tmp/custom-n8n.lf
sudo -n install -m 750 -o root -g wazuh /tmp/custom-n8n.lf /var/ossec/integrations/custom-n8n
sudo -n grep -q 'SOC-IA' /var/ossec/etc/ossec.conf || sudo -n sh -c 'cat /tmp/ossec-soc-ia.conf >> /var/ossec/etc/ossec.conf'
sudo -n /var/ossec/bin/wazuh-analysisd -t
sudo -n systemctl restart wazuh-manager
sleep 20
sudo -n /var/ossec/bin/wazuh-control status | grep -E 'integratord|analysisd'
echo DEPLOIEMENT_OK
'@
