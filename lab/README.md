# Maquette Projet 1 – scripts VirtualBox

Scripts PowerShell qui construisent la maquette du HLD/LLD. À lancer dans l'ordre, depuis ce dossier.

| Script | Rôle |
| --- | --- |
| `config.ps1` | Paramètres communs : chemins, réseaux, adresses, versions |
| `lib.ps1` | Fonctions : VBoxManage, clavier de la console, captures, SSH |
| `00-preparation.ps1` | Vérifie les empreintes, décompresse l'ISO OPNsense, crée la clé SSH et les identifiants du labo |
| `01-opnsense-vm.ps1` | Crée la VM OPNsense (WAN, SERVEURS, OUTILS) et la démarre sur l'ISO |
| `02-opnsense-install.ps1` | Installation d'OPNsense sur le disque, au clavier de la console |
| `02b-opnsense-config.ps1` | Interfaces et adresses, SSH par clé, accès admin depuis le PC, redémarrage |
| `02c-opnsense-suricata-wazuh.ps1` | Carte NAT de sortie Internet, Suricata (IDS sur le WAN, ET Open + règles SOC), agent Wazuh |
| `opnsense\` | Fichiers PHP de configuration d'OPNsense et règles locales Suricata (`soc-local.rules`) |
| `03-wazuh-vm.ps1` | Importe l'OVA Wazuh sur le VLAN Outils (2 vCPU, 6 Go) |
| `03b-wazuh-config.ps1` | Clé SSH, sudo, adresses 10.10.30.10 et 192.168.56.10, délais de démarrage allongés |
| `03c-wazuh-regles.ps1` | Règles SOC (`wazuh\local_rules.xml`), réponse active (`wazuh\ossec-soc.conf` + `opnsense\soc-drop`), journaux du pare-feu par l'agent, test de blocage |
| `05-kali-vm.ps1` | VM Kali (image officielle VirtualBox, empreinte vérifiée), 2 vCPU, 2 Go, host-only |
| `05b-kali-config.ps1` | Kali : 192.168.56.66, route 10.10.0.0/16 via OPNsense, SSH par clé, sans interface graphique |
| `06-srvweb-vm.ps1` | VM SRV-WEB : Ubuntu Server 24.04.5 en installation automatique (carte NAT temporaire, SSH sur 127.0.0.1:2222) |
| `06b-srvweb-config.ps1` | SRV-WEB : clé SSH, DVWA (niveau low), agent Wazuh avec FIM sur `/var/www/html`, bascule en 10.10.20.20 sur `soc-srv` |
| `06c-web-detection.ps1` | Jeu ET web_server, flux F1, règle Wazuh 100107, test d'attaque web depuis Kali |
| `opnsense\soc-web-rule.php` | Flux F1 : WAN → 10.10.20.20:80 autorisé et journalisé |
| `opnsense\soc-ids-web.php` | Active le jeu ET emerging-web_server dans Suricata |
| `06d-srvweb-isolement.ps1` | Déploie `wazuh\isoler-hote.sh` sur SRV-WEB (agent 002) et la réponse active `wazuh\ossec-soc-isolement.conf` : isolement sur corrélation 100152 (alerte réseau puis modification de `/var/www`), levée automatique après 15 min |
| `07-ia-vm.ps1` | Bonus IA : VM SOC-IA (Ubuntu 24.04, 5 Go, 1 vCPU, installation automatique) |
| `07b-ia-config.ps1` | SOC-IA : clé SSH, Docker + TheHive + n8n, bascule en 10.10.30.20 (+ carte d'administration 192.168.56.20) |
| `07c-ia-wazuh.ps1` | Intégration Wazuh → n8n (`wazuh\ossec-soc-ia.conf`, `ia\custom-n8n`) et règles à jour |
| `ia\` | `setup-soc-ia.sh`, `docker-compose-n8n.yml`, `custom-n8n` (intégration Wazuh→n8n), `workflow-soc-ia.json` |

**Ordre** : 00 → 01 → 02 → 02b → 03 → 03b → 02c → 03c → 05 → 05b → 06 → 06b → 06c → 06d → (07 → 07b → 07c, bonus IA)

**Joindre une VM interne** (10.10.x.x) en SSH : rebond par OPNsense, fonction `Get-JumpOpts` de `lib.ps1`.

**Rejouer les attaques** (dossier de test) : `tests\attaques.ps1` lance chaque événement redouté depuis Kali et affiche la détection et le blocage. `tests\attaques.ps1 er4` pour un seul (er1 / er2 / er3 / er4 / er5 / web) ; `tests\attaques.ps1 er4 garder` laisse Kali bloquée pour la montrer ; `tests\attaques.ps1 isolement` lance la corrélation avec isolement de SRV-WEB (coupé 15 min).

**Mettre le labo en pause** avant d'éteindre le PC : `pause.ps1` (sauvegarde l'état), `reprise.ps1` (relance en quelques secondes).

**Snapshots** : `snapshot.ps1 "nom"` traite les VMs une par une (mise en veille → snapshot → reprise). Ne pas utiliser de snapshot à chaud (`--live`) sur plusieurs VMs : le 30/10, cela a saturé la RAM et figé Wazuh 2 jours (réparée le 09/11 en retirant le disque de snapshot inachevé, conservé dans `vms\SOC-Wazuh\_sauvegarde-snapshot-rate\`).

**RAM** : OPNsense (4 Go) + Wazuh (6 Go) + SOC-IA (5 Go) : garder Kali et SRV-WEB en veille pendant la démo IA, et SOC-IA en veille pendant les attaques.

**Débloquer une IP** sur OPNsense : `pfctl -t __wazuh_agent_drop -T delete <IP>` (ou `-T flush` pour tout vider). Les adresses du PC, d'OPNsense, de Wazuh et des VLAN internes ne sont jamais bloquées (liste blanche dans `soc-drop`).

**Accès depuis le PC** : OPNsense https://192.168.56.2 et `ssh root@192.168.56.2` ; Wazuh https://192.168.56.10 et `ssh wazuh-user@192.168.56.10` (clé `secrets\id_lab`).
Les clés d'API (Groq par défaut, ou Anthropic avec `ia\workflow-soc-ia-claude.json`, TheHive, AbuseIPDB) se saisissent dans les identifiants de n8n, jamais dans les fichiers.

Dossiers créés : `images\` (ISO et OVA), `vms\` (disques), `captures\` (écrans des consoles), `secrets\` (clé SSH et mots de passe du labo, à ne pas partager).

**Réseaux VirtualBox**

- WAN simulé : réseau host-only existant 192.168.56.0/24. Le PC hôte est en .1, donc le WAN d'OPNsense est en **192.168.56.2** (et non .1 comme dans la première version du plan d'adressage).
- VLAN Serveurs : réseau interne `soc-srv`, 10.10.20.0/24.
- VLAN Outils : réseau interne `soc-outils`, 10.10.30.0/24.
- Wazuh a une deuxième carte host-only (DHCP VirtualBox) pour l'administration pendant la construction. On peut la débrancher pour la soutenance : `VBoxManage controlvm SOC-Wazuh setlinkstate2 off`.
