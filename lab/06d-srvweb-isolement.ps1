# Etape 6d : isolement automatique de SRV-WEB sur correlation critique (regle 100151)
# Prerequis : 06b (agent srv-web = ID 002) et 03c (regles SOC)
. (Join-Path $PSScriptRoot "lib.ps1")
$w = "wazuh-user@$($Ip.WazuhAdmin)"; $s = "socadmin@$($Ip.SrvWeb)"; $j = Get-JumpOpts

# 1. Agent SRV-WEB : script isoler-hote.sh + "at" (levee de secours au bout de 15 min)
$script = (Get-Content (Join-Path $Lab "wazuh\isoler-hote.sh") -Raw) -replace "`r", ""
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($script))
Invoke-SshScript $s @"
set -e
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q at >/dev/null
sudo systemctl enable --now atd
echo '$b64' | base64 -d > /tmp/isoler-hote.sh
sudo install -m 750 -o root -g wazuh /tmp/isoler-hote.sh /var/ossec/active-response/bin/isoler-hote.sh
sudo ls -l /var/ossec/active-response/bin/isoler-hote.sh
"@ $j

# 2. Manager : commande + reponse active (cible l'agent 002 uniquement)
foreach ($fic in "wazuh\ossec-soc-isolement.conf", "wazuh\local_rules.xml") {
    & scp -q -i $SshKey -o BatchMode=yes -o "UserKnownHostsFile=`"$Secrets\known_hosts`"" (Join-Path $Lab $fic) "${w}:/tmp/"
    if ($LASTEXITCODE -ne 0) { throw "Copie de $fic vers Wazuh impossible" }
}
Invoke-SshScript $w @'
set -e
sudo -n grep -q 'SOC-LAB isolement' /var/ossec/etc/ossec.conf || sudo -n sh -c 'cat /tmp/ossec-soc-isolement.conf >> /var/ossec/etc/ossec.conf'
# Regles a jour (100151/100152 avec global_frequency)
sudo -n install -m 660 -o wazuh -g wazuh /tmp/local_rules.xml /var/ossec/etc/rules/local_rules.xml
sudo -n /var/ossec/bin/wazuh-analysisd -t
sudo -n systemctl restart wazuh-manager
echo ISOLEMENT_DEPLOYE
'@
