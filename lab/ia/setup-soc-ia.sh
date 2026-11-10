#!/bin/bash
# Installation de la VM SOC-IA (Ubuntu Server 24.04) : Docker, TheHive (profil testing StrangeBee), n8n
# A lancer en root sur la VM : sudo bash setup-soc-ia.sh
set -euo pipefail

# 1. Adresse de production sur le VLAN Outils, preparee mais NON appliquee : la VM est encore
#    sur la carte NAT (Internet) pendant l'installation. Elle s'applique au redemarrage sur soc-outils.
IFACE=$(ip -o link | awk -F': ' '$2 !~ /lo/ {print $2; exit}')
MAC=$(cat /sys/class/net/${IFACE}/address)
cat > /etc/netplan/60-soc-outils.yaml <<EOF
network:
  version: 2
  ethernets:
    soc-outils:
      match: {macaddress: "${MAC}"}
      dhcp4: false
      addresses: [10.10.30.20/24]
      routes: [{to: default, via: 10.10.30.1}]
      nameservers: {addresses: [10.10.30.1]}
EOF
chmod 600 /etc/netplan/60-soc-outils.yaml
rm -f /etc/netplan/50-cloud-init.yaml
echo 'network: {config: disabled}' > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg

# 2. Docker Engine et plugin compose (depot officiel Docker)
apt-get update
apt-get install -y ca-certificates curl git jq
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Elasticsearch demande ce reglage noyau
echo "vm.max_map_count=262144" > /etc/sysctl.d/99-elasticsearch.conf
sysctl --system

# 3. TheHive : profil testing du depot officiel, seuls les services utiles
cd /opt
[ -d strangebee ] || git clone https://github.com/StrangeBeeCorp/docker.git strangebee
cd strangebee/testing
# Memoire reduite pour le PC du labo (VM de 5 Go) : 768 Mo de tas Java par service au lieu de 1 a 1,3 Go.
# En dessous des recommandations StrangeBee (8 Go) : suffisant pour une demonstration, pas pour la production.
# Ecrit AVANT init.sh : init.sh demarre lui-meme la pile (constate le 09/11).
cat > docker-compose.override.yml <<'EOF'
services:
  cassandra:
    environment:
      - MAX_HEAP_SIZE=768M
      - HEAP_NEWSIZE=128M
    deploy: {resources: {limits: {memory: 1200M}}}
    memswap_limit: 1200M
    healthcheck: {disable: true}
  elasticsearch:
    environment:
      - ES_JAVA_OPTS=-Xms512m -Xmx512m
    deploy: {resources: {limits: {memory: 1300M}}}
    memswap_limit: 1300M
    healthcheck: {disable: true}
  thehive:
    environment:
      - JAVA_OPTS=-Xms768M -Xmx768M -XX:MaxMetaspaceSize=300m -XX:ReservedCodeCacheSize=150m
    deploy: {resources: {limits: {memory: 1300M}}}
    memswap_limit: 1300M
    healthcheck: {disable: true}
EOF
# Tests de sante Docker desactives : avec 1 vCPU, cqlsh et curl duraient plus que l'intervalle,
# s'empilaient (50 processus zombies, charge 50) et empechaient la pile de demarrer (constate le 09/11).
# Le demarrage est sequence plus bas par des controles reels.
# init.sh initialise aussi TheHive Flow (PostgreSQL, Temporal) : inutile ici et trop gourmand,
# on le supprime ensuite. init.sh peut echouer en demarrant TheHive faute de memoire : on reprend la main.
ASSUME_YES=1 SERVICE_HOSTNAME=thehive.local bash ./scripts/init.sh -y || true
docker rm -f thehive-flow-postgresql thehive-flow-temporal thehive-flow cortex thehive-flow-s3-store 2>/dev/null || true
# Lance via sudo, init.sh enregistre UID=0 : Elasticsearch refuse alors de demarrer ("can not run
# elasticsearch as root", constate le 09/11). On fait tourner la pile sous l'utilisateur d'administration.
U=${SUDO_UID:-1000}; G=${SUDO_GID:-1000}
sed -i "s/^UID=0\$/UID=${U}/; s/^GID=0\$/GID=${G}/" .env
for d in cassandra elasticsearch thehive nginx; do [ -d "$d" ] && chown -R "${U}:${G}" "$d"; done
# Demarrage pas a pas, sans dependances (--no-deps) pour ne pas relancer TheHive Flow
attendre() {  # attendre <description> <commande de controle>
  for i in $(seq 1 120); do eval "$2" >/dev/null 2>&1 && return 0; sleep 15; done
  echo "Delai depasse : $1" >&2; return 1
}
for s in cassandra elasticsearch; do docker compose up -d --force-recreate --no-deps "$s"; done
attendre "Cassandra" "docker exec cassandra cqlsh -u cassandra -p cassandra -e 'describe keyspaces'"
attendre "Elasticsearch" "docker exec elasticsearch curl -sf http://localhost:9200/_cluster/health"
docker compose up -d --force-recreate --no-deps thehive
attendre "TheHive" "curl -sf http://localhost:9000/thehive/api/status"
# Nginx : retirer les renvois vers Cortex et TheHive Flow (absents), sinon Nginx refuse de demarrer
T=nginx/templates/default.conf.template
if grep -q 'location /cortex' "$T"; then
  sed -i '/location \/cortex {/,/^    }$/d; /# TheHive Flow webhooks/,/^    }$/d' "$T"
  sed -i '$i\    location = / { return 302 /thehive/; }' "$T"
fi
docker compose up -d --force-recreate --no-deps nginx

# 4. n8n
mkdir -p /opt/n8n && cd /opt/n8n
cp /tmp/docker-compose-n8n.yml docker-compose.yml
[ -f .env ] || echo "N8N_VERSION=${N8N_VERSION:?definir N8N_VERSION, ex. N8N_VERSION=1.x.y}" > .env
docker compose up -d

echo "TheHive : https://10.10.30.20  |  n8n : http://10.10.30.20:5678"
