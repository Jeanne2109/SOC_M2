#!/bin/bash
# Reponse active Wazuh : isole un serveur Linux compromis (corrélation critique 100150/100151).
# A placer sur l'agent (SRV-WEB) dans /var/ossec/active-response/bin/isoler-hote.sh (chmod 750, root:wazuh).
# L'hote ne parle plus qu'au manager Wazuh (10.10.30.10). Levee par la commande "delete" (fin de
# temporisation de la reponse active) ou manuellement : sudo /var/ossec/active-response/bin/isoler-hote.sh --lever
#
# Securite labo : a l'isolement, une tache planifiee leve l'isolement au bout de 15 min meme sans
# ordre du manager, pour ne jamais verrouiller definitivement la VM.
MANAGER="10.10.30.10"
MARQUEUR="/var/ossec/active-response/.isole"
LOG="/var/ossec/logs/active-responses.log"
journal() { echo "$(date '+%Y/%m/%d %H:%M:%S') isoler-hote: $1" >> "$LOG"; }

lever() {
    iptables -P INPUT ACCEPT; iptables -P OUTPUT ACCEPT; iptables -P FORWARD ACCEPT
    iptables -F
    atrm $(cat "$MARQUEUR" 2>/dev/null) 2>/dev/null
    rm -f "$MARQUEUR"
    journal "isolement leve"
}

isoler() {
    [ -f "$MARQUEUR" ] && { journal "deja isole"; return; }
    iptables -F
    iptables -I INPUT  -i lo -j ACCEPT
    iptables -I OUTPUT -o lo -j ACCEPT
    iptables -I INPUT  -s "$MANAGER" -j ACCEPT
    iptables -I OUTPUT -d "$MANAGER" -p tcp --dport 1514:1515 -j ACCEPT
    iptables -P INPUT DROP; iptables -P OUTPUT DROP; iptables -P FORWARD DROP
    # Securite : levee automatique dans 15 min si le manager ne l'ordonne pas avant
    command -v at >/dev/null 2>&1 && echo "$0 --lever" | at now + 15 minutes 2>/dev/null | grep -o '[0-9]\+' | head -n1 > "$MARQUEUR" || touch "$MARQUEUR"
    journal "hote isole (seul $MANAGER reste joignable)"
}

# Appel manuel
[ "$1" = "--lever" ] && { lever; exit 0; }
[ "$1" = "--isoler" ] && { isoler; exit 0; }

# Appel par Wazuh active-response (protocole stdin)
read -r INPUT
cmd=$(echo "$INPUT" | sed -n 's/.*"command":"\([a-z]*\)".*/\1/p')
if [ "$cmd" = "add" ]; then
    echo '{"version":1,"origin":{"name":"isoler-hote","module":"active-response"},"command":"check_keys","parameters":{"keys":["isolation"]}}'
    read -r REP
    echo "$REP" | grep -q '"continue"' || { journal "deja isole (manager)"; exit 0; }
    isoler
elif [ "$cmd" = "delete" ]; then
    lever
fi
