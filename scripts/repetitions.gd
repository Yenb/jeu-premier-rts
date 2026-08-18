extends RefCounted

# SONDE DE REPETITION -- instrument de diagnostic, jamais un mecanisme de
# simulation. Aucune decision du monde ne le lit et rien n'en depend : un banc
# qui ne l'instancie pas n'en paye pas une ligne. Opt-in par construction.
#
# CE QU'IL REPOND : le travail d'un tour est-il fait UNE fois, ou plusieurs ?
# L'appelant note une CLE chaque fois qu'il calcule quelque chose, avec
# l'EMPREINTE du resultat obtenu. Deux notes de la meme cle dans le meme tour
# sont un defaut, et la sonde separe les deux defauts possibles :
# - REFAIT : meme cle, meme empreinte, plusieurs fois. Le calcul est redemande
#   alors que son resultat est deja connu. Travail perdu.
# - INSTABLE : meme cle, empreintes differentes. La valeur doit etre fixe sur
#   la duree du tour et elle bouge. Defaut de correction, pas de cout.
#
# CE QU'IL NE FAIT PAS : aucune mesure de DUREE. Un compte d'occurrences ne dit
# rien du temps passe -- pour ca, le profileur de Godot, pas cette sonde. La
# stabilite d'une valeur D'UN TOUR A L'AUTRE n'est pas non plus son objet :
# deux notes dans deux tours differents sont toujours legitimes.
#
# tour(numero) : ouvre un tour. Sans aucun appel, tout tombe dans le tour 0 et
#   la detection marche quand meme -- l'usage le plus simple ne demande rien.
# noter(cle, empreinte) : `cle` est un String libre choisi par l'appelant ; il
#   nomme CE QUI est calcule, jamais la chose du monde calculee. `empreinte`
#   est un Variant quelconque, normalise par var_to_str -- Vector3, Array et
#   Dictionary compris, sans que ce fichier sache ce qu'il compare.
# rapport() : Dictionary de donnees pures, resumable en JSON --
#   { refaits, instables, notes, cles_distinctes }. `refaits` est un Array de
#   { cle, tour, fois }, `instables` un Array de { cle, tour, empreintes }.
# resume() : une ligne de texte POUR LA CONSOLE DE DEVELOPPEMENT, jamais pour
#   un ecran de joueur. La regle d'internationalisation ne porte pas sur cet
#   instrument, dont la sortie ne quitte pas le banc.
#
# Ne connait aucun mot du monde : ni proprietes, ni type, ni position. Il ne
# voit que des String et des empreintes opaques.

var _tour := 0
var _vues := {}
var _notes := 0

func tour(numero: int) -> void:
	_tour = numero

func noter(cle: String, empreinte = null) -> void:
	_notes += 1
	if not _vues.has(_tour):
		_vues[_tour] = {}
	var du_tour: Dictionary = _vues[_tour]
	if not du_tour.has(cle):
		du_tour[cle] = []
	du_tour[cle].append(var_to_str(empreinte))

func rapport() -> Dictionary:
	var refaits: Array = []
	var instables: Array = []
	var cles := {}
	var tours: Array = _vues.keys()
	tours.sort()
	for numero in tours:
		var du_tour: Dictionary = _vues[numero]
		var noms: Array = du_tour.keys()
		noms.sort()
		for cle in noms:
			cles[cle] = true
			var empreintes: Array = du_tour[cle]
			if empreintes.size() < 2:
				continue
			var distinctes := _distinctes(empreintes)
			if distinctes.size() == 1:
				refaits.append({"cle": cle, "tour": numero, "fois": empreintes.size()})
			else:
				instables.append({"cle": cle, "tour": numero, "empreintes": distinctes})
	return {
		"refaits": refaits,
		"instables": instables,
		"notes": _notes,
		"cles_distinctes": cles.size(),
	}

func resume() -> String:
	var r := rapport()
	var defauts: Array = []
	for d in r["refaits"]:
		defauts.append("REFAIT tour %d : '%s' calcule %d fois pour le meme resultat" % [d["tour"], d["cle"], d["fois"]])
	for d in r["instables"]:
		defauts.append("INSTABLE tour %d : '%s' donne %d resultats differents dans le meme tour" % [d["tour"], d["cle"], d["empreintes"].size()])
	if defauts.is_empty():
		return "SONDE: %d notes sur %d cles, aucune repetition" % [r["notes"], r["cles_distinctes"]]
	return "SONDE: %d notes sur %d cles -- %s" % [r["notes"], r["cles_distinctes"], " | ".join(defauts)]

# Dedoublonne en gardant l'ordre d'apparition : le rapport doit rester le meme
# d'un lancement a l'autre, ce qu'un Dictionary de passage ne garantit pas.
func _distinctes(empreintes: Array) -> Array:
	var vues: Array = []
	for e in empreintes:
		if not vues.has(e):
			vues.append(e)
	return vues
