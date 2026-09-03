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
# ECART AVEC LE DEPOT FRAMEWORK : SUBDIVISION ADAPTATIVE des buckets. Une case
# terminale au-dela de SEUIL_SPLIT (20) se subdivise en 8 sous-cases, jusqu'a
# PROFONDEUR_MAX (3). Une case subdivisee dont le total descend sous
# SEUIL_MERGE (5) se reaplatit. L'ecart 5/20 evite l'oscillation. Le depot
# orion ne le porte pas encore. Necessaire quand un gameplay empile des mobs au
# meme point (siege, tas de ressources, foule d'IA) : sans subdivision, une
# requete degenere en O(k^2) local sur la case saturee et bloque le manager.
# Ne peut pas attendre le depot framework : les tests de charge en phase 8
# franchissent le seuil. Meme geste doctrinal que retirer() ci-dessus.
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

# exposant -> { "cases": { Vector3i -> Array d'ids OU Dictionary de sous-cases },
#               "case_de": { id -> Array[Vector3i] (chemin globale + sub_keys) } }
#
# CASE POLYMORPHIQUE : le contenu de cases[Vector3i] est soit un Array d'ids
# (terminal), soit un Dictionary { Vector3i(0..1, 0..1, 0..1) -> contenu }
# (subdivise, recursif). `contenu is Array` distingue les deux. La subdivision
# se declenche quand une case terminale depasse SEUIL_SPLIT et fusionne quand
# une case subdivisee descend sous SEUIL_MERGE (voir ECART FRAMEWORK).
#
# CHEMIN COMPLET : case_de[id] est un Array[Vector3i] representant le chemin
# depuis la racine jusqu'a la feuille : [case_globale] pour un terminal a la
# racine, [case_globale, sub_0] pour un niveau de subdivision, jusqu'a
# [case_globale, sub_0, sub_1, sub_2] a PROFONDEUR_MAX. Longueur min 1, max
# 1 + PROFONDEUR_MAX. Necessaire pour que _deranger retrouve la feuille sans
# depender de la position vivante, qui peut avoir bouge sans que deplacer()
# ait ete appele (contrat historique du monde).
var _niveaux: Dictionary = {}

# SUBDIVISION ADAPTATIVE : voir ECART FRAMEWORK en tete de fichier.
# Une case terminale au-dela de SEUIL_SPLIT bascule en 8 sous-cases. Une case
# subdivisee dont le TOTAL descend sous SEUIL_MERGE se reaplatit. L'ecart 5/20
# evite le ping-pong split/merge d'un id qui entre et sort au seuil.
# PROFONDEUR_MAX borne la recursion : au-dela, la case reste terminale meme si
# elle depasse SEUIL_SPLIT -- c'est le cas plancher de N ids a la MEME position,
# ou la subdivision ne peut fondamentalement pas aider. Ce n'est pas un bug,
# c'est le contrat : subdivision aide quand les positions differencient, pas
# quand elles convergent au meme point.
const SEUIL_SPLIT := 20
const SEUIL_MERGE := 5
const PROFONDEUR_MAX := 3
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
		var chemin_actuel: Array = niveau.case_de.get(chose.id, [])
		# Optim conservee UNIQUEMENT quand la case globale n'a pas change ET que la
		# case n'est pas subdivisee (chemin de longueur 1). Sur une case subdivisee,
		# meme si la case globale est identique la sub_key peut avoir change, donc
		# on doit re-ranger.
		if chemin_actuel.size() == 1 and chemin_actuel[0] == visee:
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
	var arete := _arete(exposant)
	requetes += 1
	for cx in range(basse.x, haute.x + 1):
		for cy in range(basse.y, haute.y + 1):
			for cz in range(basse.z, haute.z + 1):
				cases_lues += 1
				var cle := Vector3i(cx, cy, cz)
				var contenu = cases.get(cle, null)
				if contenu == null:
					continue
				var origine := Vector3(cle) * arete
				_collecter(contenu, origine, arete, position, carre, resultat)
	if trier_par_insertion:
		resultat.sort_custom(_avant)
	if verifier_index:
		_verifier(position, rayon, resultat)
	return resultat

# COLLECTE RECURSIVE : sur une case terminale (Array), teste chaque id.
# Sur une case subdivisee (Dictionary), itere les 8 sous-cases mais ne descend
# que dans celles dont l'AABB intersecte la sphere de la query. Chaque descente
# incremente `cases_lues`, pour que le cout reste visible depuis les tests.
func _collecter(contenu, origine: Vector3, arete: float, centre: Vector3, carre_r: float, out: Array) -> void:
	if contenu is Array:
		for id in contenu:
			var entree: Dictionary = choses[id]
			var pos_vivante: Vector3 = entree.chose.position
			candidats_mesures += 1
			# LE CARRE DE LA DISTANCE, jamais la distance : meme verdict, une
			# racine de moins par candidat.
			if centre.distance_squared_to(pos_vivante) <= carre_r:
				out.append({"chose": entree.chose, "type": entree.type, "position": pos_vivante})
		return
	if contenu is Dictionary:
		var demi := arete * 0.5
		for sub_key in contenu:
			var sub_origine: Vector3 = origine + Vector3(sub_key) * demi
			if not _sphere_touche_boite(centre, carre_r, sub_origine, demi):
				continue
			cases_lues += 1
			_collecter(contenu[sub_key], sub_origine, demi, centre, carre_r, out)

# Sphere de rayon^2 = carre_r centree sur centre, contre boite AABB
# [origine, origine + taille * Vector3.ONE]. Test standard : distance carree du
# centre au point le plus proche de la boite (chaque axe clampe dans [min, max]).
func _sphere_touche_boite(centre: Vector3, carre_r: float, origine: Vector3, taille: float) -> bool:
	var proche := Vector3(
		clampf(centre.x, origine.x, origine.x + taille),
		clampf(centre.y, origine.y, origine.y + taille),
		clampf(centre.z, origine.z, origine.z + taille))
	return centre.distance_squared_to(proche) <= carre_r

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
	var cases: Dictionary = niveau.cases
	var case_globale := _case_pour(position, exposant)
	if not cases.has(case_globale):
		cases[case_globale] = []
	# Chemin initial = juste la racine. _inserer l'etend au fil de la descente
	# dans les Dictionary de subdivision, et _splitter l'etend aussi pour l'id
	# courant s'il declenche un split de la case terminale.
	niveau.case_de[id] = [case_globale]
	var origine_racine := Vector3(case_globale) * _arete(exposant)
	_inserer(cases, case_globale, id, position, origine_racine, _arete(exposant), 0, niveau)

# Descend dans le contenu de parent[cle] et insere id a la bonne place.
# - Contenu terminal (Array) : append + split si depasse SEUIL_SPLIT et
#   profondeur < MAX (au plancher, on garde le pile terminal).
# - Contenu subdivise (Dictionary) : trouve la sous-case correspondant a la
#   position, etend le chemin, recurse.
func _inserer(parent: Dictionary, cle, id, position: Vector3, origine: Vector3,
		arete: float, profondeur: int, niveau: Dictionary) -> void:
	var contenu = parent[cle]
	if contenu is Dictionary:
		var sub_key := _sous_case(position, origine, arete)
		if not contenu.has(sub_key):
			contenu[sub_key] = []
		(niveau.case_de[id] as Array).append(sub_key)
		var sub_origine: Vector3 = origine + Vector3(sub_key) * (arete * 0.5)
		_inserer(contenu, sub_key, id, position, sub_origine, arete * 0.5, profondeur + 1, niveau)
		return
	# Contenu terminal.
	(contenu as Array).append(id)
	if profondeur < PROFONDEUR_MAX and (contenu as Array).size() > SEUIL_SPLIT:
		_splitter(parent, cle, contenu, origine, arete, profondeur, niveau)

# Convertit une case terminale en 8 sous-cases. Chaque id (y compris celui
# qu'on vient d'ajouter) est reparti selon sa position vivante, et son chemin
# dans case_de est etendu de la sub_key. Recurse si une sous-case elle-meme
# depasse SEUIL_SPLIT et qu'on n'a pas atteint PROFONDEUR_MAX.
func _splitter(parent: Dictionary, cle, contenu: Array, origine: Vector3,
		arete: float, profondeur: int, niveau: Dictionary) -> void:
	var subdivise: Dictionary = {}
	for autre_id in contenu:
		var pos_autre: Vector3 = choses[autre_id].chose.position
		var sub_key := _sous_case(pos_autre, origine, arete)
		if not subdivise.has(sub_key):
			subdivise[sub_key] = []
		(subdivise[sub_key] as Array).append(autre_id)
		(niveau.case_de[autre_id] as Array).append(sub_key)
	parent[cle] = subdivise
	if profondeur + 1 < PROFONDEUR_MAX:
		var demi := arete * 0.5
		for sub_key in subdivise:
			var sub_contenu = subdivise[sub_key]
			if (sub_contenu as Array).size() > SEUIL_SPLIT:
				var sub_origine: Vector3 = origine + Vector3(sub_key) * demi
				_splitter(subdivise, sub_key, sub_contenu, sub_origine, demi, profondeur + 1, niveau)

func _deranger(niveau: Dictionary, id) -> void:
	if not niveau.case_de.has(id):
		return
	var chemin: Array = niveau.case_de[id]
	niveau.case_de.erase(id)
	if chemin.is_empty():
		return
	var cases: Dictionary = niveau.cases
	_retirer_par_chemin(cases, chemin, 0, id)
	# Merge : si la racine de cette colonne est un Dictionary dont le total est
	# passe sous SEUIL_MERGE, on la reaplatit en Array terminal. Un seul niveau
	# de merge par retrait : hysteresis 5/20 rend le merge en cascade inutile.
	var cle_globale = chemin[0]
	if cases.has(cle_globale) and cases[cle_globale] is Dictionary:
		if _totaliser(cases[cle_globale]) < SEUIL_MERGE:
			_merger(cases, cle_globale, niveau)

# Descend par le chemin, retire l'id de la feuille Array. Rend true si le
# noeud courant est devenu vide -- le parent le supprime alors de son Dictionary
# (purge en remontant, evite les containers fantomes).
func _retirer_par_chemin(parent: Dictionary, chemin: Array, profondeur: int, id) -> bool:
	var cle = chemin[profondeur]
	if not parent.has(cle):
		return false
	var contenu = parent[cle]
	if contenu is Array:
		(contenu as Array).erase(id)
		if (contenu as Array).is_empty():
			parent.erase(cle)
			return true
		return false
	# Dictionary : recurse.
	var sous_vide := _retirer_par_chemin(contenu, chemin, profondeur + 1, id)
	if sous_vide and (contenu as Dictionary).is_empty():
		parent.erase(cle)
		return true
	return false

# Aplatit un contenu subdivise (Dictionary) en Array terminal. Met a jour le
# chemin de tous les ids concernes : [globale] (longueur 1, terminal a la racine).
func _merger(cases: Dictionary, cle_globale, niveau: Dictionary) -> void:
	var contenu = cases[cle_globale]
	var aplati: Array = []
	_aplatir(contenu, aplati)
	cases[cle_globale] = aplati
	for id in aplati:
		niveau.case_de[id] = [cle_globale]

func _aplatir(contenu, out: Array) -> void:
	if contenu is Array:
		for id in contenu:
			out.append(id)
		return
	if contenu is Dictionary:
		for cle in contenu:
			_aplatir(contenu[cle], out)

func _totaliser(contenu) -> int:
	if contenu is Array:
		return (contenu as Array).size()
	if contenu is Dictionary:
		var total := 0
		for cle in contenu:
			total += _totaliser(contenu[cle])
		return total
	return 0

# Sous-cle 0/1 par axe : 0 si la position est dans la moitie basse, 1 dans la
# haute. Compatible frontiere exacte (>=), coherent avec _sphere_touche_boite.
func _sous_case(pos: Vector3, origine: Vector3, arete: float) -> Vector3i:
	var demi := arete * 0.5
	return Vector3i(
		1 if pos.x >= origine.x + demi else 0,
		1 if pos.y >= origine.y + demi else 0,
		1 if pos.z >= origine.z + demi else 0)

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
