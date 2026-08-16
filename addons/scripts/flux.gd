extends RefCounted

const Portee = preload("res://scripts/portee.gd")

# Modele generique de flux : une chose portant une propriete SOURCE recharge,
# a son propre taux et dans sa propre portee (taux_flux, portee_flux, poses a
# la fabrication -- jamais dans la table, meme raisonnement que
# portee_travail sur extinction.gd ou portee_saillance sur proximite.gd), la
# reserve <cible> de toute chose a portee portant la propriete RECEPTRICE
# correspondante. Neutre par construction : un taux_flux negatif decroit la
# reserve au lieu de la recharger -- ce fichier ne "donne" rien, il transfere
# selon un nombre, dans un sens ou dans l'autre.
#
# Meme forme de canal que depense.gd (proprietes.reserves.<nom>.reserve) et
# volontairement : ce que ce fichier recharge, depense.gd peut le ponctionner
# ensuite, sans structure concurrente.
#
# monde : Array de Dictionary { "id", "position", "proprietes" }, mute en
#         place -- proprietes.reserves.<cible> est cree (canal minimal
#         { "reserve": 0.0 }) s'il n'existe pas encore sur la chose
#         receptrice, puis sa reserve est incrementee du total transfere.
# table_flux : Array de Dictionary { "source": <propriete>, "receptrice":
#         <propriete>, "cible": <nom de reserve> } -- table de regles,
#         analogue a menaces.json (data/menaces.json). Ni la source, ni la
#         receptrice, ni le nom de reserve ne sont nommes en dur ici.
# delta : temps ecoule ce pas, en secondes.
#
# Le test "a portee" delegue a scripts/portee.gd:en_portee -- seule part
# partagee avec attaches.gd/propagation.gd/extinction.gd/charge.gd (voir
# docs/design.md "Direction majeure" : la fusion des cinq mecanismes est
# ABANDONNEE, ce fichier garde sa propre boucle regles-d'abord).
#
# Rend l'Array des id des choses receptrices dont une reserve a ete modifiee
# ce pas de temps (dedoublonne).
static func avancer(monde: Array, table_flux: Array, delta: float) -> Array:
	var modifiees: Array = []
	for ligne in table_flux:
		var sources: Array = []
		for chose in monde:
			if chose.proprietes.get(ligne.source, false):
				sources.append(chose)
		if sources.is_empty():
			continue
		for chose in monde:
			if not chose.proprietes.get(ligne.receptrice, false):
				continue
			var total := 0.0
			for source in sources:
				var portee: float = source.proprietes.get("portee_flux", 0.0)
				if Portee.en_portee(chose.position, source.position, portee):
					total += source.proprietes.get("taux_flux", 0.0)
			if total == 0.0:
				continue
			_recharger(chose.proprietes, ligne.cible, total * delta)
			if not modifiees.has(chose.id):
				modifiees.append(chose.id)
	return modifiees

static func _recharger(proprietes: Dictionary, cible: String, quantite: float) -> void:
	if not proprietes.has("reserves"):
		proprietes["reserves"] = {}
	var reserves: Dictionary = proprietes["reserves"]
	if not reserves.has(cible):
		reserves[cible] = {"reserve": 0.0}
	var canal: Dictionary = reserves[cible]
	canal["reserve"] = canal.get("reserve", 0.0) + quantite
