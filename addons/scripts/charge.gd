extends RefCounted

const Portee = preload("res://scripts/portee.gd")

# Modele generique de charge a seuil : une chose porte un ENSEMBLE NOMME
# de charges (canaux), chacune MONTE tant qu'une cause est percue a portee
# (somme des contributions a portee -- le test "a portee" delegue a
# scripts/portee.gd:en_portee, seule part partagee avec attaches.gd/
# propagation.gd/flux.gd/extinction.gd ; voir docs/design.md, "Direction
# majeure" -- la fusion des cinq mecanismes eux-memes est ABANDONNEE, ce
# fichier reste le SEUL des cinq dont le seuil est REVERSIBLE, une
# quatrieme nature d'effet que design.md ne nommait pas avant ce
# chantier),
# FRANCHIT un seuil vers le HAUT qui pose une cause en donnee sur
# proprietes, puis REDESCEND d'elle-meme quand la cause disparait
# (taux_decroissance en donnee, applique seulement quand la somme a portee
# est nulle ce pas) et RETIRE la meme cause quand la charge repasse sous le
# seuil -- reversible, jamais un evenement unique comme les seuils de
# depense.gd. Contrairement a a_zero (extinction.gd) ou aux seuils de
# depense.gd, qui distinguent retirer/poser pour une transformation
# asymetrique et definitive, une seule table "poser" suffit ici : le
# franchissement montant l'ajoute a proprietes, le franchissement
# descendant retire exactement les memes cles -- symetrie voulue par la
# reversibilite (le calque se retire, rien n'atteint l'immuable, voir
# docs/design.md, "Piste ouverte -- transformations qui atteignent
# l'immuable"). Ce fichier ne connait aucun nom de contenu ("peur",
# "colere", "controleur") : tout le vocabulaire vit en donnee.
#
# Frontiere avec depense.gd : depense DECROIT en interne, sans portee, et
# applique ses seuils UNE SEULE FOIS (vers le bas, retire de la liste,
# jamais reappliques). Frontiere avec extinction.gd : extinction decroit
# par AGENTS A PORTEE mais ne remonte jamais et ne connait pas de seuil. Ce
# fichier est le seul a monter sous portee, basculer, puis redescendre
# seul -- verbe distinct des deux, d'ou un script separe (voir CARTE.md,
# "deux verbes distincts a ne jamais fusionner").
#
# UN SEUL SEUIL PAR CANAL, PAS D'HYSTERESIS (V1) : une charge qui oscille
# pile autour du seuil (presence intermittente d'un pas a l'autre vers la
# frontiere exacte) pose et retire la cause a chaque pas. Non corrige ici --
# une hysteresis a deux seuils (comme banc_animal.gd:cible_besoin,
# seuil_bascule/seuil_satisfait) est un raffinement de cablage a ajouter en
# donnee plus tard si le besoin se presente, pas une garde du mecanisme pur.
#
# monde : Array de Dictionary { "id", "position", "proprietes" }, mute en
#         place : chaque charge monte ou descend independamment des autres,
#         chaque bascule pose/retire sa cause sur proprietes (pas sur le
#         canal).
# causes : Array de Dictionary avec au moins "position" (Vector3) ; "poids"
#          facultatif (defaut 1.0), la force de cette cause -- meme
#          convention que "rythme" dans extinction.gd.
# delta : temps ecoule ce pas, en secondes.
#
# proprietes lues sur la chose :
#   - etats (Dictionary facultatif) : nom de charge -> canal. Absence de
#     cette cle, ou Dictionary vide -> la chose est ignoree.
#   - un canal est un Dictionary { "charge": float (plancher 0.0, jamais
#     negatif -- contrairement a depense.gd ou la reserve n'est pas bornee
#     par choix, une charge sous zero n'a pas de sens ici), "seuil": float,
#     "portee_charge": float (defaut 0.0 -- convention de prefixe par
#     mecanisme, voir docs/design.md ; un canal sans portee ne detecte
#     jamais rien a distance non nulle, legitime, pas alarme, meme
#     convention que cout_base dans depense.gd), "taux_decroissance": float
#     (defaut 0.0), "poser": Dictionary cle -> valeur }.
#
# Rend l'Array des id des choses ayant franchi un seuil (dans un sens ou
# l'autre) sur au moins une charge, ce pas de temps.
static func avancer(monde: Array, causes: Array, delta: float) -> Array:
	var bascules: Array = []
	for chose in monde:
		var proprietes: Dictionary = chose.proprietes
		var etats: Dictionary = proprietes.get("etats", {})
		if etats.is_empty():
			continue
		var a_bascule := false
		for nom in etats:
			if _avancer_canal(etats[nom], proprietes, chose.position, causes, delta):
				a_bascule = true
		if a_bascule:
			bascules.append(chose.id)
	return bascules

static func _avancer_canal(canal: Dictionary, proprietes: Dictionary, position: Vector3, causes: Array, delta: float) -> bool:
	var seuil: float = canal.get("seuil", 0.0)
	var avant: float = canal.get("charge", 0.0)
	var portee: float = canal.get("portee_charge", 0.0)
	var somme := 0.0
	for cause in causes:
		if Portee.en_portee(position, cause.position, portee):
			somme += cause.get("poids", 1.0)
	var charge := avant
	if somme > 0.0:
		charge += somme * delta
	else:
		var taux: float = canal.get("taux_decroissance", 0.0)
		charge = max(0.0, charge - taux * delta)
	canal["charge"] = charge
	var etait_dessus := avant > seuil
	var est_dessus := charge > seuil
	if etait_dessus == est_dessus:
		return false
	# Ce qu'un canal pose est COPIE, jamais assigne tel quel (CARTE.md §6,
	# doctrine du meme nom).
	var poser: Dictionary = canal.get("poser", {})
	if est_dessus:
		for cle in poser:
			var valeur = poser[cle]
			if valeur is Dictionary or valeur is Array:
				valeur = valeur.duplicate(true)
			proprietes[cle] = valeur
	else:
		for cle in poser:
			proprietes.erase(cle)
	return true
