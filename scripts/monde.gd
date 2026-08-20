extends RefCounted

# Le contenant de monde du banc : fournit la requete spatiale
# choses_dans_rayon() dont perception.gd a besoin. _monde (banc_p1.gd) EST une
# instance de cette classe (CARTE.md §6, FERME) -- pas un echafaudage a cote du
# vrai monde. Sert aussi de fixture legere dans les tests (test_perception.gd,
# test_monde.gd, test_banc_p1.gd).
#
# Regles : test de DISTANCE seul -- aucune occlusion, aucune ligne de vue. Elle
# depend du CANAL interroge (un mur arrete la vue, pas le son), notion qu'un
# contenant spatial n'a aucune raison de connaitre : elle vit dans occlusion.gd.
#
# UNE REQUETE NE LIT QUE LES CASES QUE SON RAYON TOUCHE. Sans index, savoir qui
# est dans le cercle exige de demander a TOUT LE MONDE : le rayon ne reduit plus
# le travail, il ne filtre plus que la reponse, et 2 m coute autant que 200. Les
# choses sont donc rangees par case cubique ; le cout suit le rayon, jamais la
# population.
#
# A PLUSIEURS RESOLUTIONS A LA FOIS, parce que tout le monde ne percoit pas a la
# meme echelle : une plante teste ses voisines immediates, un guetteur balaie
# l'horizon. Une arete unique dessert l'un ou l'autre -- trop grande, la petite
# requete ramasse une case pleine de candidats hors rayon ; trop petite, la
# grande parcourt des milliers de cases vides. Les aretes sont des puissances de
# deux ; une requete lit la premiere au-dessus de son rayon, ce qui borne la
# lecture a deux cases par axe quel que soit le rayon. Chaque resolution NAIT
# quand un rayon inedit la demande, jamais avant : rien a declarer, rien a
# regler.
#
# L'ALTERNATIVE ECARTEE : une grille par FAMILLE d'interrogeant (une pour les
# plantes, une pour les colons) inscrirait des categories du monde dans le
# moteur, ce que l'ADN interdit -- ajouter une creature qui percoit plus loin
# rouvrirait ce fichier. Ici le moteur ne connait qu'un NOMBRE.
#
# CE QUE L'INDEX COUTE, A SAVOIR AVANT D'ECRIRE UN MOBILE : la position est
# desormais RANGEE en plus d'etre lue. Une chose qui bouge sans le dire reste a
# son ancienne case et devient introuvable la ou elle est. Les distances restent
# calculees sur la position VIVANTE, donc exactes : c'est l'appartenance a une
# case qui vieillit. deplacer() la remet a jour, resynchroniser() le fait pour
# tout le monde d'un coup.
#
# verifier_index rejoue la recherche exhaustive et alarme sur tout ecart -- le
# filet du paragraphe precedent, pour les tests, jamais pour la boucle de jeu.
#
# retirer(id) SORT UNE CHOSE DU MONDE, DE PARTOUT A LA FOIS : `choses`,
# `_rang`, et chaque niveau ouvert de l'index spatial. Sans elle, une chose
# detruite reste un fantome compte par toute requete de densite a sa place,
# pour toujours -- symptome paye sur une population qui se reproduit ET se
# detruit (jeu/Ennemie/population_ennemie.gd). Id absent : push_error, rien
# ne bouge -- jamais un silence sur un retrait qui n'a pas eu lieu.
#
# ECART AVEC LE DEPOT FRAMEWORK : sa version n'a pas ce geste (voir
# CLAUDE.md § Frontiere pour la raison d'etre de l'ecart et sa portee).
#
# choses : Dictionary indexe PAR ID (id -> { chose, type }), pas un Array --
# permet par_id() ci-dessous. L'ordre d'insertion est preserve ; un appelant qui
# veut les choses nues itere `choses.values()`.
#
# ajouter(chose, type, position) : enregistre `{ chose, type }` sous `chose.id`,
# mute `choses` en place, range la chose a chaque resolution ouverte.
# `position` n'est PAS stocke -- elle est relue depuis `chose.position` a chaque
# requete, jamais figee a l'ajout. CONSEQUENCE POUR TOUT MECANISME QUI VISE : il
# vise la chose LA OU ELLE EST MAINTENANT ; viser un SOUVENIR exige un registre
# separe (memoire_spatiale.gd). L'argument existe pour ne pas changer la
# signature. `position` est STRUCTURELLE sur `chose` : absente, push_error et la
# chose n'est PAS enregistree. Meme doctrine sur un id deja present : jamais un
# ecrasement silencieux.
#
# deplacer(chose) -> range la chose a sa position courante, a chaque resolution.
# A appeler apres toute reassignation de `chose.position`. Sans effet si elle
# n'a change de case nulle part. Id absent : push_error.
#
# resynchroniser() -> range tout le monde a neuf. Pour les deplacements EN LOT,
# ou personne n'a declare son mouvement. Cout proportionnel a la population.
#
# par_id(id) -> le wrapper { chose, type } sous cet id. Absent : push_error et
# null -- jamais un defaut silencieux.
#
# choses_dans_rayon(position, rayon) -> Array des entrees { chose, type,
# position } a distance <= rayon, `position` relue sur `entree.chose.position`.
#
# Ne fait pas : ne fabrique aucun objet (voir objet.gd), ne connait aucune
# propriete.

var choses: Dictionary = {}

# LES BORNES DES RESOLUTIONS, en exposants de deux : de 2^-2 (0,25 m) a 2^12
# (4096 m). Elles n'existent que pour qu'un rayon aberrant -- zero, negatif,
# infini -- ne fabrique pas une resolution absurde ; entre les deux, chaque
# ordre de grandeur a la sienne des qu'on la demande. Aucun contenu du jeu
# n'entre dans ces deux nombres : ce sont des garde-fous d'arithmetique.
const EXPOSANT_MINIMAL := -2
const EXPOSANT_MAXIMAL := 12

# L'ORDRE D'INSERTION COUTE UN TRI PAR REQUETE. Il n'est rendu que sur
# demande : aucun mecanisme du depot n'en depend -- les appelants comptent,
# cherchent un maximum, ou s'arretent au premier trouve.
var trier_par_insertion: bool = false

# Sous ce drapeau, chaque requete est rejouee en balayage exhaustif et tout
# ecart alarme. Pour les tests -- il coute exactement ce que l'index economise.
var verifier_index: bool = false

# CE QU'UNE REQUETE A REELLEMENT COUTE, lisible du dehors : nombre de
# requetes, cases lues, candidats dont la distance a ete calculee, et
# resolutions ouvertes. Sans ce compteur, une requete locale et un balayage
# integral sont INDISCERNABLES pour l'appelant -- il obtient la meme reponse
# et ne voit pas le prix. C'est ce qui permet a un test de poser un plafond de
# COUT au lieu de verifier seulement que le resultat est juste, seule espece
# de test qui puisse voir venir un balayage cache.
var requetes: int = 0
var cases_lues: int = 0
var candidats_mesures: int = 0

func remettre_les_compteurs() -> void:
	requetes = 0
	cases_lues = 0
	candidats_mesures = 0

# Rend les aretes des resolutions actuellement ouvertes, croissantes. Sert aux
# tests et a la mise au point : c'est la seule fenetre sur ce que l'index a
# decide tout seul.
func resolutions_ouvertes() -> Array:
	var aretes: Array = []
	for exposant in _niveaux:
		aretes.append(_arete(int(exposant)))
	aretes.sort()
	return aretes

# exposant -> { "cases": { Vector3i -> Array d'ids }, "case_de": { id -> Vector3i } }
var _niveaux: Dictionary = {}
# id -> rang d'insertion, pour rendre les resultats dans l'ordre d'ajout.
var _rang: Dictionary = {}
var _prochain_rang: int = 0

func ajouter(chose, type: String, position: Vector3) -> void:
	if not (chose is Dictionary and chose.has("position")):
		push_error("monde.gd : ajouter() -- 'chose' sans champ 'position' structurel, non enregistree")
		return
	if choses.has(chose.id):
		push_error("monde.gd : ajouter() -- id '%s' deja enregistre, non ecrase" % chose.id)
		return
	choses[chose.id] = {"chose": chose, "type": type}
	_rang[chose.id] = _prochain_rang
	_prochain_rang += 1
	for exposant in _niveaux:
		_ranger(_niveaux[exposant], int(exposant), chose.id, chose.position)

# Remet une chose a sa place courante, a chaque resolution ouverte. A appeler
# apres toute reassignation de `chose.position` -- sans quoi elle reste
# trouvable a son ANCIENNE place et introuvable a la nouvelle.
func deplacer(chose) -> void:
	if not (chose is Dictionary and chose.has("id")):
		push_error("monde.gd : deplacer() -- 'chose' sans champ 'id'")
		return
	if not choses.has(chose.id):
		push_error("monde.gd : deplacer() -- id '%s' absent" % chose.id)
		return
	for exposant in _niveaux:
		var niveau: Dictionary = _niveaux[exposant]
		var visee := _case_pour(chose.position, int(exposant))
		if niveau.case_de.get(chose.id, null) == visee:
			continue
		_deranger(niveau, chose.id)
		_ranger(niveau, int(exposant), chose.id, chose.position)

# Range tout le monde a neuf, a chaque resolution ouverte -- la reponse aux
# deplacements EN LOT, quand personne n'a declare son mouvement.
func resynchroniser() -> void:
	for exposant in _niveaux:
		_niveaux[exposant] = _batir(int(exposant))

func par_id(id) -> Variant:
	if not choses.has(id):
		push_error("monde.gd : par_id() -- id '%s' absent" % id)
		return null
	return choses[id]

# Sort une chose du monde : de `choses`, de `_rang`, et de chaque niveau
# ouvert de l'index spatial. Voir l'en-tete -- un id absent alarme et ne
# fait rien, jamais un silence.
func retirer(id) -> void:
	if not choses.has(id):
		push_error("monde.gd : retirer() -- id '%s' absent" % id)
		return
	for exposant in _niveaux:
		_deranger(_niveaux[exposant], id)
	choses.erase(id)
	_rang.erase(id)

func choses_dans_rayon(position: Vector3, rayon: float) -> Array:
	var resultat: Array = []
	var exposant := _exposant_pour(rayon)
	var niveau := _niveau(exposant)
	var cases: Dictionary = niveau.cases
	var basse := _case_pour(position - Vector3(rayon, rayon, rayon), exposant)
	var haute := _case_pour(position + Vector3(rayon, rayon, rayon), exposant)
	var carre := rayon * rayon
	requetes += 1
	for cx in range(basse.x, haute.x + 1):
		for cy in range(basse.y, haute.y + 1):
			for cz in range(basse.z, haute.z + 1):
				cases_lues += 1
				var occupants = cases.get(Vector3i(cx, cy, cz), null)
				if occupants == null:
					continue
				for id in occupants:
					var entree: Dictionary = choses[id]
					var pos_vivante: Vector3 = entree.chose.position
					candidats_mesures += 1
					# LE CARRE DE LA DISTANCE, jamais la distance : meme verdict,
					# une racine de moins par candidat. Seul endroit du fichier ou
					# la geometrie n'est pas ecrite naivement, et il ne change
					# aucun resultat.
					if position.distance_squared_to(pos_vivante) <= carre:
						resultat.append({"chose": entree.chose, "type": entree.type, "position": pos_vivante})
	if trier_par_insertion:
		resultat.sort_custom(_avant)
	if verifier_index:
		_verifier(position, rayon, resultat)
	return resultat

func _avant(a: Dictionary, b: Dictionary) -> bool:
	return int(_rang[a.chose.id]) < int(_rang[b.chose.id])

# ---- Les resolutions ----

# L'EXPOSANT DONT L'ARETE COUVRE LE RAYON. Une arete au moins egale au rayon
# borne la lecture a DEUX cases par axe : la sphere fait 2 rayons de large,
# donc jamais plus de deux aretes, quel que soit l'alignement. C'est ce qui
# rend le cout independant du rayon comme du nombre de choses.
func _exposant_pour(rayon: float) -> int:
	if not (rayon > 0.0) or is_inf(rayon):
		return EXPOSANT_MAXIMAL if is_inf(rayon) else EXPOSANT_MINIMAL
	return clampi(ceili(log(rayon) / log(2.0)), EXPOSANT_MINIMAL, EXPOSANT_MAXIMAL)

func _arete(exposant: int) -> float:
	return pow(2.0, float(exposant))

func _case_pour(position: Vector3, exposant: int) -> Vector3i:
	var arete := _arete(exposant)
	return Vector3i(
		floori(position.x / arete),
		floori(position.y / arete),
		floori(position.z / arete))

# La resolution demandee, batie a la volee si elle n'existe pas encore. Ce
# premier passage coute une passe sur toute la population -- une fois, pour
# tout un ordre de grandeur de rayon.
func _niveau(exposant: int) -> Dictionary:
	if not _niveaux.has(exposant):
		_niveaux[exposant] = _batir(exposant)
	return _niveaux[exposant]

func _batir(exposant: int) -> Dictionary:
	var niveau := {"cases": {}, "case_de": {}}
	for id in choses:
		_ranger(niveau, exposant, id, choses[id].chose.position)
	return niveau

func _ranger(niveau: Dictionary, exposant: int, id, position: Vector3) -> void:
	var case := _case_pour(position, exposant)
	var cases: Dictionary = niveau.cases
	if not cases.has(case):
		cases[case] = []
	(cases[case] as Array).append(id)
	niveau.case_de[id] = case

func _deranger(niveau: Dictionary, id) -> void:
	if not niveau.case_de.has(id):
		return
	var case: Vector3i = niveau.case_de[id]
	var occupants: Array = niveau.cases.get(case, [])
	occupants.erase(id)
	if occupants.is_empty():
		niveau.cases.erase(case)
	niveau.case_de.erase(id)

# Rejoue la recherche exhaustive et alarme sur tout ecart. La cause en
# pratique est toujours la meme : une chose a bouge sans que deplacer() ni
# resynchroniser() n'aient ete appeles.
func _verifier(position: Vector3, rayon: float, obtenu: Array) -> void:
	var attendus: Dictionary = {}
	for entree in choses.values():
		if position.distance_to(entree.chose.position) <= rayon:
			attendus[entree.chose.id] = true
	for entree in obtenu:
		attendus.erase(entree.chose.id)
	if not attendus.is_empty():
		push_error("monde.gd : index incomplet -- %s hors de leur case, deplacer() n'a pas ete appele" % str(attendus.keys()))
