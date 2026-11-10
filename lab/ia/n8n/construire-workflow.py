"""Assemble lab/ia/workflow-soc-ia.json a partir du code JavaScript des noeuds (lab/ia/n8n/*.js).
Usage : python construire-workflow.py   (depuis n'importe quel dossier)
"""
import json, pathlib

ici = pathlib.Path(__file__).resolve().parent
js = lambda nom: (ici / nom).read_text(encoding="utf-8")
THEHIVE = "https://thehive.local/thehive/api/v1"
cred_thehive = {"httpHeaderAuth": {"id": "", "name": "TheHive API (Authorization: Bearer ...)"}}
cred_groq = {"httpHeaderAuth": {"id": "", "name": "Groq API (Authorization: Bearer ...)"}}

def code(nom, fichier, x):
    return {"parameters": {"jsCode": js(fichier)}, "name": nom, "type": "n8n-nodes-base.code",
            "typeVersion": 2, "position": [x, 0]}

def http(nom, methode, url, corps, cred, x, y=0, **extra):
    n = {"parameters": {"method": methode, "url": url, "authentication": "genericCredentialType",
                        "genericAuthType": "httpHeaderAuth", "sendBody": True, "specifyBody": "json",
                        "jsonBody": corps, "options": {"allowUnauthorizedCerts": True}},
         "name": nom, "type": "n8n-nodes-base.httpRequest", "typeVersion": 4.2,
         "position": [x, y], "credentials": cred}
    n.update(extra)
    return n

noeuds = [
    {"parameters": {"httpMethod": "POST", "path": "wazuh-alerte", "responseMode": "onReceived", "options": {}},
     "name": "Webhook Wazuh", "type": "n8n-nodes-base.webhook", "typeVersion": 2, "position": [0, 0],
     "webhookId": "wazuh-alerte"},
    http("TheHive - historique IP", "POST", THEHIVE + "/query",
         # Filtre sur l'etiquette seule : le filtre _gt sur _createdAt de TheHive ecartait des alertes
         # recentes (constate le 10/11). La fenetre de 24 h est appliquee dans "Score et contexte".
         "={{ JSON.stringify({ query: [{ _name: 'listAlert' }, "
         "{ _name: 'filter', _eq: { _field: 'tags', _value: 'src:' + ($json.body.reseau.src_ip || 'aucune') } }, "
         "{ _name: 'sort', _fields: [{ _createdAt: 'desc' }] }, { _name: 'page', from: 0, to: 200 }] }) }}",
         cred_thehive, 110, alwaysOutputData=True),
    code("Score et contexte", "1-score-et-contexte.js", 220),
    http("TheHive - creer alerte", "POST", THEHIVE + "/alert",
         "={{ JSON.stringify($json.thehive) }}", cred_thehive, 440),
    {"parameters": {"conditions": {
        "options": {"caseSensitive": True, "leftValue": "", "typeValidation": "strict"},
        "conditions": [{"id": "doublon", "leftValue": "={{ $('Score et contexte').first().json.doublon }}",
                        "rightValue": True,
                        "operator": {"type": "boolean", "operation": "true", "singleValue": True}}],
        "combinator": "and"}, "options": {}},
     "name": "Doublon ?", "type": "n8n-nodes-base.if", "typeVersion": 2, "position": [660, 0]},
    code("Marquer le doublon", "2-doublon.js", 880) | {"position": [880, -160]},
    http("IA - analyser (Groq)", "POST", "https://api.groq.com/openai/v1/chat/completions",
         "={{ JSON.stringify($('Score et contexte').first().json.request) }}", cred_groq, 880, 120,
         onError="continueRegularOutput", retryOnFail=True, maxTries=3, waitBetweenTries=5000),
    {"parameters": {"conditions": {
        "options": {"caseSensitive": True, "leftValue": "", "typeValidation": "loose"},
        "conditions": [{"id": "debit", "leftValue": "={{ /429|too many requests|rate.?limit/i.test(JSON.stringify($json.error || '')) && $runIndex < 4 }}",
                        "rightValue": True,
                        "operator": {"type": "boolean", "operation": "true", "singleValue": True}}],
        "combinator": "and"}, "options": {}},
     "name": "Limite de debit ?", "type": "n8n-nodes-base.if", "typeVersion": 2, "position": [1100, 120]},
    {"parameters": {"amount": 35, "unit": "seconds"}, "name": "Attendre 35 s", "type": "n8n-nodes-base.wait",
     "typeVersion": 1.1, "position": [1100, 300], "webhookId": "attente-debit-groq"},
    code("Lire la reponse IA", "3-lire-reponse-ia.js", 1320) | {"position": [1320, 120]},
    http("TheHive - mettre a jour", "PATCH", "=" + THEHIVE + "/alert/{{ $json.id }}",
         "={{ JSON.stringify($json.patch) }}", cred_thehive, 1540),
]
ia = next(n for n in noeuds if n["name"] == "IA - analyser (Groq)")
ia["parameters"]["options"]["timeout"] = 300000
del ia["parameters"]["options"]["allowUnauthorizedCerts"]

lien = lambda cible: {"main": [[{"node": cible, "type": "main", "index": 0}]]}
connexions = {
    "Webhook Wazuh": lien("TheHive - historique IP"),
    "TheHive - historique IP": lien("Score et contexte"),
    "Score et contexte": lien("TheHive - creer alerte"),
    "TheHive - creer alerte": lien("Doublon ?"),
    "Doublon ?": {"main": [[{"node": "Marquer le doublon", "type": "main", "index": 0}],
                           [{"node": "IA - analyser (Groq)", "type": "main", "index": 0}]]},
    "Marquer le doublon": lien("TheHive - mettre a jour"),
    "IA - analyser (Groq)": lien("Limite de debit ?"),
    # Limite de debit de l'offre gratuite Groq : attendre 35 s puis reessayer (4 fois au plus)
    "Limite de debit ?": {"main": [[{"node": "Attendre 35 s", "type": "main", "index": 0}],
                                   [{"node": "Lire la reponse IA", "type": "main", "index": 0}]]},
    "Attendre 35 s": lien("IA - analyser (Groq)"),
    "Lire la reponse IA": lien("TheHive - mettre a jour"),
}
for i, n in enumerate(noeuds, 1):
    n["id"] = f"a1b2c3d4-{i:04d}-4000-8000-{i:012d}"

wf = {"name": "SOC - copilote IA (Groq)", "nodes": noeuds, "connections": connexions,
      "settings": {"executionOrder": "v1"}}
sortie = ici.parent / "workflow-soc-ia.json"
sortie.write_text(json.dumps(wf, ensure_ascii=False, indent=2), encoding="utf-8", newline="\n")
print("ecrit :", sortie)
