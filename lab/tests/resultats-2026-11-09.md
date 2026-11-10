# Résultats des tests du 09/11/2026

Complète les résultats du 30/10 (ER1, ER3, ER4, ER5, attaques web, corrélation 100151 : validés).

| Test | Procédure | Attendu | Obtenu | Statut |
|---|---|---|---|---|
| ER2 pays à risque | `tests\attaques.ps1 er2` : Kali envoie des SYN dont la source est usurpée (1.0.1.1 Chine, 175.45.176.1 Corée du Nord) vers le WAN d'OPNsense | Blocage par la règle flottante GeoIP `PAYS_RISQUE`, alerte Wazuh 100108 | 6 paquets bloqués (journal pf, étiquette de la règle ER2), alertes 100108 niveau 8 « ER2 - Accès bloqué depuis un pays à risque : 175.45.176.1 vers 192.168.56.2 » | Validé |
| Isolement automatique SRV-WEB | `tests\attaques.ps1 isolement` : scan nmap depuis Kali, puis webshell déposé dans `/var/www/html` en moins de 5 min | Corrélation 100152 niveau 15, SRV-WEB isolé (seul le manager joignable), levée automatique après 15 min | Alerte 100152 à 12:39:28, SRV-WEB injoignable (ping et port 80) depuis OPNsense, levée automatique constatée (journal : « isolement levé ») | Validé |
| Chaîne IA (sans clé) | Alerte ER1 injectée dans eve.json d'OPNsense (203.0.113.66) | Wazuh → blocage OPNsense → n8n → alerte TheHive ; sans clé Claude, ticket créé quand même avec `ia:indisponible` | Alerte TheHive « ER1 - IP malveillante… » sévérité 2, étiquettes T1190, er1, ids_reseau, `ia:indisponible` ; IP bloquée dans `__wazuh_agent_drop` | Validé (analyse Claude à tester avec la clé API) |

| Non-régression ER1 à ER5 et web | `tests\attaques.ps1` (tous) | Signature Suricata + blocage de Kali pour chaque test | Toutes les signatures détectées ; ER1, ER2, ER3, web bloqués ; ER4/ER5 bloqués après correction de `soc-drop` (relance `er4`, `er5`) | Validé |
| Isolement via le script de démo | `tests\attaques.ps1 isolement` | SRV-WEB isolé, chemin du fichier dans l'alerte | « CRITIQUE - Alerte réseau puis modification de la racine web (/var/www/html/shell-test-813145990.php) : webshell probable, isolement de l'hôte », SRV-WEB injoignable | Validé |

## Corrections faites pendant les tests

- **Blocage non rétabli après vidage de la table** : quand Wazuh considère un blocage encore actif, `soc-drop` répondait « déjà bloquée » sans vérifier la table pf (vidée entre deux tests, ou après un redémarrage d'OPNsense). Il remet maintenant toujours l'IP dans la table (opération idempotente).
- **Description sans chemin** : `$(file)` au lieu de `$(syscheck.path)` dans les descriptions 100151/100152.

- **Corrélation déclenchée à tort** : le groupe `syscheck` contient aussi les messages de fin de scan rootcheck. La règle 100151 exige maintenant un chemin de fichier (`<field name="file">`).
- **Champ de règle** : dans les règles Wazuh, le chemin FIM s'appelle `file` ; `syscheck.path` n'existe que dans l'alerte JSON (vérifié par des règles de diagnostic).
- **Corrélation entre agents** : l'alerte réseau vient de l'agent OPNsense et le fichier de SRV-WEB. Sans `<global_frequency/>`, Wazuh ne corrèle que les événements d'un même agent.
- **Ciblage de l'isolement** : nouvelle règle 100152 (modification sous `/var/www/` après une alerte réseau), réponse active limitée à l'agent 002 (SRV-WEB), pour qu'une corrélation sur un autre hôte ne coupe jamais SRV-WEB ni le manager.

## Limites connues

- Supprimer ou créer un fichier dans `/var/www` dans les 5 min qui suivent une alerte réseau, même pour une opération légitime, isole SRV-WEB : en production, la levée serait décidée par l'analyste et les déploiements web passeraient par une fenêtre de maintenance.
- SRV-WIN (règle 100150, Sysmon) non déployé dans le labo.
