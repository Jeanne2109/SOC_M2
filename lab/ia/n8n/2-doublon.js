// Noeud n8n "Marquer le doublon" : meme regle et meme IP source deja analysees il y a moins de 10 min.
// On garde le ticket (tracabilite) mais sans nouvel appel a l'IA : moins de bruit et quota gratuit preserve.
const alerte = $('TheHive - creer alerte').first().json;
const ctx = $('Score et contexte').first().json;
return [{ json: { id: alerte._id, patch: {
  tags: (alerte.tags || []).concat(['ia:doublon']),
  description: alerte.description + '\n\n**Doublon** : meme regle et meme IP source deja analysees par l IA a ' + ctx.precedent +
    ' (moins de 10 min). Voir l alerte precedente pour l analyse.'
} } }];
