# Projet 1 – SOC Ambassade : protection des serveurs contre les attaques réseau

Projet du cours SOC (M2 Efrei). Une ambassade héberge des serveurs Windows Server 2016 avec SMBv1, impossibles à corriger : on les protège **par le réseau** (détection, blocage, réponse automatique) et on organise le traitement des incidents par une équipe SOC.

Ce dépôt contient les **livrables** et une **maquette complète et automatisée** sous VirtualBox : chaque VM est créée, installée et configurée par des scripts PowerShell, puis un script rejoue toutes les attaques.

## Contenu

| Élément | Où |
|---|---|
| Note technique (stratégie, solutions, organisation de l'équipe) | `Note technique - Projet 1.docx` |
| HLD / LLD (architecture, flux, règles, playbook, IA) | `HLD-LLD - Projet 1.docx` |
| Scripts de construction de la maquette | `lab/*.ps1` (mode d'emploi détaillé : [`lab/README.md`](lab/README.md)) |
| Règles et configuration Suricata / OPNsense | `lab/opnsense/` |
| Règles Wazuh, réponses actives (blocage, isolement) | `lab/wazuh/` |
| Bonus IA : TheHive + n8n + Claude | `lab/ia/` |
| Dossier de test rejouable et résultats | `lab/tests/` |

## Architecture

| VM | Adresse | Rôle |
|---|---|---|
| **OPNsense** 26.7 | 192.168.56.2 (WAN), 10.10.20.1, 10.10.30.1 | Pare-feu, **Suricata** (IDS) intégré, blocage GeoIP, agent Wazuh qui exécute les blocages |
| **Wazuh** 4.14.9 | 10.10.30.10 (admin 192.168.56.10) | SIEM : règles SOC, corrélation, réponse active |
| **SRV-WEB** Ubuntu 24.04 | 10.10.20.20 | Serveur protégé (DVWA), surveillance des fichiers, isolement automatique |
| **Kali** | 192.168.56.66 | Attaquant pour les tests |
| **SOC-IA** Ubuntu 24.04 (bonus) | 10.10.30.20 (admin 192.168.56.20) | TheHive (gestion des incidents), n8n (automatisation), Claude (analyse) |

Réseaux : WAN simulé = réseau host-only VirtualBox 192.168.56.0/24 ; VLAN Serveurs `soc-srv` 10.10.20.0/24 ; VLAN Outils `soc-outils` 10.10.30.0/24.

Chaîne de traitement : **Kali attaque → Suricata détecte → Wazuh alerte (règles 100101–100152) → OPNsense bloque l'IP 1 h / SRV-WEB s'isole 15 min → n8n crée l'alerte TheHive → Claude l'analyse.**

| Événement redouté | Détection | Réponse |
|---|---|---|
| ER1 IP malveillante | Listes ET CINS/DROP/COMPROMISED + IOC du SOC (règle 100101) | Blocage de l'IP |
| ER2 pays à risque | Alias GeoIP MaxMind (Chine, Corée du Nord, Roumanie), règle 100108 | Bloqué par le pare-feu |
| ER3 malware | Signature EICAR / ET MALWARE (100103) | Blocage |
| ER4 scan | ET SCAN / règle SOC (100104) | Blocage |
| ER5 déni de service | SYN flood (100105) | Blocage |
| Attaque web | ET WEB_SERVER (100107) | Blocage |
| Corrélation critique | Alerte réseau puis webshell dans `/var/www` en moins de 5 min (100152, niveau 15) | **Isolement de SRV-WEB** |

## Démarrage rapide

### Prérequis

- Windows 10/11, **VirtualBox 7.2**, PowerShell 7, OpenSSH client (inclus dans Windows), Python 3 (décompression de l'ISO OPNsense).
- **RAM** : 16 Go minimum. OPNsense 4 Go + Wazuh 6 Go + Kali 2 Go + SRV-WEB 2 Go ; SOC-IA (5 Go) se lance quand Kali et SRV-WEB sont en pause.
- **Disque** : environ 100 Go libres.
- Si Hyper-V / VBS est actif sous Windows, VirtualBox est plus lent : garder 1 vCPU pour les VM Ubuntu (déjà le cas dans les scripts).

### 1. Télécharger les images officielles dans `lab/images/`

| Fichier attendu | Source officielle |
|---|---|
| `OPNsense-26.7-dvd-amd64.iso.bz2` + `OPNsense-26.7-checksums-amd64.sha256` | https://opnsense.org/download/ |
| `wazuh-4.14.9.ova` (+ `.sha512`) | https://documentation.wazuh.com/current/deployment-options/virtual-machine/virtual-machine.html |
| `kali-linux-2026.3-virtualbox-amd64.7z` + `kali-SHA256SUMS` | https://www.kali.org/get-kali/#kali-virtual-machines |
| `ubuntu-24.04.5-live-server-amd64.iso` + `ubuntu-SHA256SUMS` | https://releases.ubuntu.com/24.04/ |

Les scripts vérifient les empreintes avant d'utiliser chaque image. Si les versions ont changé, adapter `lab/config.ps1`.

### 2. Construire la maquette

Depuis `lab/`, dans PowerShell, lancer les scripts dans l'ordre (chacun attend la fin de l'étape précédente) :

```
00 → 01 → 02 → 02b → 03 → 03b → 02c → 03c → 05 → 05b → 06 → 06b → 06c → 06d → (bonus IA : 07 → 07b → 07c)
```

`00-preparation.ps1` crée `lab/secrets/` : clé SSH et mots de passe propres à **votre** maquette (jamais versionnés).

**ER2 (GeoIP)** : créer un compte gratuit MaxMind GeoLite2, générer une clé de licence, la saisir dans OPNsense (*Firewall › Aliases › GeoIP settings*), puis lancer `lab/opnsense/soc-geoip.php` (voir `lab/README.md`).

### 3. Rejouer les attaques

```powershell
.\tests\attaques.ps1              # ER1, ER2, ER3, ER4, ER5, web
.\tests\attaques.ps1 er4 garder   # une seule attaque, en laissant Kali bloquée pour la montrer
.\tests\attaques.ps1 isolement    # corrélation + isolement de SRV-WEB (coupé 15 min)
```

Où regarder : OPNsense https://192.168.56.2 (*Services › Intrusion Detection › Alerts*, *Firewall › Diagnostics › Aliases › `__wazuh_agent_drop`*, *Firewall › Log Files › Live View*) ; Wazuh https://192.168.56.10 (*Threat Hunting*, recherche `rule.groups:soc`) ; TheHive https://192.168.56.20/thehive.

## Bonus IA

- TheHive 6 (profil *testing* StrangeBee, licence d'essai puis licence Community gratuite à activer), n8n 2.46.6.
- Le workflow `lab/ia/workflow-soc-ia.json` crée l'alerte TheHive puis demande à un LLM une analyse structurée (gravité, événement redouté, faux positif probable, résumé, 3 actions), au format JSON imposé par un schéma.
- **LLM gratuit par défaut : Groq** (`openai/gpt-oss-120b`, API compatible OpenAI, offre gratuite : 30 requêtes/min, 1 000/jour). Créer une clé sur https://console.groq.com/keys, puis dans n8n › *Credentials* › « Groq API (Authorization: Bearer ...) », compléter la valeur `Bearer ` avec la clé (`Bearer gsk_...`). **Garder le mot `Bearer` et l'espace devant la clé**, sinon Groq répond « Invalid API Key ».
- Variante payante : `lab/ia/workflow-soc-ia-claude.json` (Claude, `claude-opus-5-5`, clé Anthropic).
- Aucune clé n'est fournie. Sans clé, la chaîne fonctionne en mode dégradé : le ticket TheHive est créé avec l'étiquette `ia:indisponible`.
- Offre gratuite : le fournisseur peut réutiliser les données envoyées ; le workflow n'envoie que les champs techniques de l'alerte (IP, signature, règle), jamais de journaux ni de fichiers.

## Sécurité

- Maquette **pédagogique**, isolée sur des réseaux VirtualBox : DVWA et Kali ne doivent jamais être exposés sur un vrai réseau.
- Aucun secret dans ce dépôt (`lab/secrets/`, VM et images exclus par `.gitignore`). Les identifiants par défaut cités (`wazuh`, `kali`, `admin@thehive.local` / `secret`) sont ceux des éditeurs : à changer après installation.
