// Noeud n8n "Lire la reponse IA" : met en forme l'analyse pour TheHive (ou signale l'indisponibilite).
const rep = $input.first().json;
const alerte = $('TheHive - creer alerte').first().json;
const ctx = $('Score et contexte').first().json;
const niveaux = { faible: 1, moyenne: 2, haute: 3, critique: 4 };

// Reponse au format OpenAI (Groq) : choices[0].message.content contient le JSON impose par le schema
const choix = (rep.choices || [])[0] || {};
const message = choix.message || {};
const texte = message.content || '';

let patch;
if (!texte || message.refusal || choix.finish_reason === 'length') {
  // Pas d'invention : le ticket garde la gravite du script de score
  const err = rep.error || {};
  const raison = message.refusal || [err.httpCode, err.message, err.description].filter(Boolean).join(' - ') || choix.finish_reason || 'erreur';
  patch = { tags: (alerte.tags || []).concat(['ia:indisponible']),
            description: alerte.description + '\n\n**Analyse IA indisponible** (' + String(raison).slice(0, 300) + '). Gravite retenue : score du script.' };
} else {
  const ia = JSON.parse(texte);
  const liste = (t) => (t || []).map((e, i) => (i + 1) + '. ' + e).join('\n');
  const puces = (t) => (t || []).length ? t.map(e => '- `' + e + '`').join('\n') : '- aucun';
  patch = {
    severity: niveaux[ia.gravite],
    tags: (alerte.tags || []).concat(['ia:analyse', 'ia:' + ia.evenement_redoute, 'score-ia:' + ia.score_ia,
      ia.faux_positif_probable ? 'ia:faux-positif-probable' : 'ia:vrai-positif-probable']),
    description: alerte.description +
      '\n\n---\n## Analyse IA (' + (rep.model || 'groq') + ')\n' +
      '| Gravite | Score IA | Score script | Evenement | MITRE | Faux positif |\n|---|---|---|---|---|---|\n' +
      '| **' + ia.gravite + '** | ' + ia.score_ia + '/100 | ' + ctx.score + '/100 | ' + ia.evenement_redoute + ' | ' + ia.technique_mitre + ' | ' + (ia.faux_positif_probable ? 'probable' : 'peu probable') + ' |\n\n' +
      '**Comparaison avec le score du script** : ' + ia.accord_avec_score_script + '\n\n' +
      '### Resume\n' + ia.resume + '\n\n' +
      '### Analyse technique\n' + ia.analyse_technique + '\n\n' +
      '### Impact potentiel\n' + ia.impact_potentiel + '\n\n' +
      '### Faux positif ?\n' + ia.justification_faux_positif + '\n\n' +
      '### Indicateurs de compromission\n' + puces(ia.ioc) + '\n\n' +
      '### Prochaines etapes proposees\n' + liste(ia.etapes) + '\n\n' +
      '_Recommandations a valider par l analyste avant toute action._'
  };
}

return [{ json: { id: alerte._id, patch } }];
