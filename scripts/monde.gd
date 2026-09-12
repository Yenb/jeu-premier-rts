extends RefCounted

const NiveauMonde = preload("res://scripts/niveau_monde.gd")

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
# ECART AVEC LE DEPOT FRAMEWORK : choses_dans_rayon lit `niveau.inv_arete`
# precalcule au lieu de rappeler `_arete(exposant)` (pow) a chaque requete, et
# calcule `origine = Vector3(cle) * arete` UNIQUEMENT au dispatch Dictionary --
# sous structure_simple chaque case est un Array a plat, la branche Dictionary
# de _collecter est morte et l'origine n'a jamais a etre allouee. La branche
# Array est aussi inlinee dans choses_dans_rayon (economie de l'appel _collecter
# + du dispatch `contenu is Array`). Les trois floori de multiplications qui
# donnent les cases min/max de la boite englobante d'une requete sont eux aussi
# INLINE dans choses_dans_rayon et choses_dans_rayons -- zero appel de fonction
# par point de requete. Compteurs requetes/cases_lues/candidats_mesures
# identiques a l'ancien chemin (verrouille par test_monde_structure_simple.gd
# et test_monde_subdivision.gd). Le depot orion ne porte pas ces retraits.
#
# ECART AVEC LE DEPOT FRAMEWORK : `structure_simple` (bool, defaut false --
# comportement historique intact). Sous true, la subdivision adaptative est
# COURT-CIRCUITEE : ajouter/deplacer/retirer prennent une branche courte
# (Array<id> par case, swap-remove pour retirer/deplacer, aucun chemin,
# aucun test SPLIT/MERGE, aucune recursion). deplacer devient O(1) reel
# (2 acces Dict + 1 comparaison Vector3i + swap-remove + append). Prevu pour
# une population dont TOUS les individus bougent CHAQUE frame (peuplement
# generique du jeu, N=100 000 dans les projections). La subdivision existante
# reste la doctrine par defaut ; verrouillee par test_monde_subdivision qui
# tourne toujours a structure_simple=false. Test dedie : structure_simple=true
# rend les MEMES resultats de requete que la subdivision, prouve sur ajouter/
# deplacer/retirer/choses_dans_rayon.
#
# DEUX FONCTIONS DEUX REGIMES : `deplacer` (mode subdivision, defaut) et
# `deplacer_simple` (mode structure_simple, hot path du peuplement). Aucun
# `if structure_simple` par appel -- le choix se fait CHEZ L'APPELANT une
# seule fois. Optimisations residuelles sous structure_simple : `_inv_arete`
# precalcule dans le niveau (`_batir`), `case_de[id] = Vector3i` direct,
# `_niveaux_liste` (Array plat) itere plutot que Dictionary. Le chiffre reel
# du poste `deplacer` a N=100 000 se releve en jeu sur `[peuplement]
# deplacer=`, pas via un test headless.
#
# PIEGE : deux chemins dans une meme fonction hot-path appelee par frame,
# avec un `if` en tete pour choisir, alourdit le bytecode et ralentit le
# chemin PRIS -- pas seulement le chemin non pris. Un regime = une fonction,
# choix une seule fois chez l'appelant. Piege paye une session entiere sur
# `deplacer` avant separation en `deplacer` / `deplacer_simple`.
#
# PIEGE : un test de profil headless ne prédit pas le jeu. `test_profil_deplacer.gd`
# (supprime cette session) mesurait 99,5% de fast-path avec des unites qui
# bougent de 0,05/frame ; en jeu les unites bougent a leur vraie vitesse et
# passent l'essentiel du temps sur le miss path -- le test headless ne le
# touchait jamais. Verdict : le seul juge de perf est le chrono `[peuplement]
# deplacer=` en jeu, pas un headless.
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
# choses_dans_couloir(depuis, vers, demi_largeur) -> Array des entrees dont la
# position tombe dans le couloir (segment `depuis`->`vers`, tolerance laterale
# `demi_largeur`). Meme forme rendue que choses_dans_rayon. NE LIT QUE LES
# CASES QUE LE SEGMENT TRAVERSE : parcours de la bbox du segment epaissi, a la
# resolution _exposant_pour(2 * demi_largeur), chaque case testee par capsule
# vs AABB (surestime -- jamais un faux negatif), chaque candidat teste par
# distance point-segment <= demi_largeur. Meme discipline de compteurs
# (requetes, cases_lues, candidats_mesures) que choses_dans_rayon, pour qu'un
# test puisse poser un plafond de COUT et voir un balayage cache.
#
# ECART AVEC LE DEPOT FRAMEWORK : sa version n'a pas ce geste (voir CLAUDE.md
# § Frontiere). L'appelant qui en a besoin sans cette requete paie O(sources *
# n_sphere) : chaque source teste TOUS les candidats de la sphere comme
# obstacles potentiels, jamais bornes au couloir source->percepteur. C'est ce
# que perception.gd:_percevoir_propagation_obstacles payait avant cette
# requete.
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

# STRUCTURE SIMPLE (voir ECART FRAMEWORK en tete de fichier). Defaut : false --
# la subdivision adaptative reste le comportement historique. true : chaque
# case reste un Array<id> a plat, aucun _inserer recursif, aucun SPLIT/MERGE,
# deplacer O(1). A activer par une population qui bouge tout le temps
# (peuplement du jeu). Le comportement OBSERVABLE de choses_dans_rayon et
# choses_dans_couloir est identique dans les deux modes -- verrouille par
# scripts/test_monde_structure_simple.gd.
var structure_simple: bool = false

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
# Cache LISTE plate des niveaux ouverts, alimente en synchronisation avec
# `_niveaux` (une entree par exposant ouvert, dans l'ordre d'ouverture).
# Permet au hot path de deplacer d'iterer un Array plutot que Dictionary --
# gain mesure : un lookup `_niveaux[exposant]` de moins par appel.
var _niveaux_liste: Array = []

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

# LOT D'AJOUTS en UNE passe : applique N appels `ajouter` sur un Array
# d'entrees {chose, type}. La position lue est `chose.position`. Meme
# resultat exact que N appels a `ajouter` dans le meme ordre. `ajouter`
# (unitaire) reste utilise ailleurs (chemins uniques d'inscription).
#
# ECART FRAMEWORK : cette signature lot n'existe pas dans le depot Orion,
# ajoutee ici sous l'exception CLAUDE.md § Frontiere pour retirer les
# franchissements de frontiere par naissance du banc `jeu/bancs/
# banc_peuplement_arbre.gd`. Meme geste doctrinal que `retirer()` et que
# `choses_dans_rayons`.
func ajouter_lot(entries: Array) -> void:
	var n: int = entries.size()
	if n == 0:
		return
	var k: int = 0
	while k < n:
		var entree: Dictionary = entries[k]
		k += 1
		var chose = entree.chose
		var type: String = entree.type
		if not (chose is Dictionary and chose.has("position")):
			push_error("monde.gd : ajouter_lot() -- 'chose' sans champ 'position' structurel, non enregistree")
			continue
		if choses.has(chose.id):
			push_error("monde.gd : ajouter_lot() -- id '%s' deja enregistre, non ecrase" % chose.id)
			continue
		choses[chose.id] = {"chose": chose, "type": type}
		_rang[chose.id] = _prochain_rang
		_prochain_rang += 1
		var position: Vector3 = chose.position
		for exposant in _niveaux:
			_ranger(_niveaux[exposant], int(exposant), chose.id, position)

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
#
# DEUX FONCTIONS DEUX REGIMES -- le choix se fait CHEZ L'APPELANT, jamais par
# `if structure_simple` a chaque appel. Un tel test 100 000 fois par frame
# alourdit le bytecode de la fonction et ralentit le chemin pris (piege paye
# une session entiere). `deplacer` = chemin subdivision pur (mode par defaut,
# structure_simple=false). `deplacer_simple` = chemin simple pur, a appeler
# quand `structure_simple=true` (banc_peuplement du jeu, populations qui
# bougent toute chaque frame).
#
# CONTRAT DE L'APPELANT : si le monde tourne en structure_simple, appeler
# `deplacer_simple` -- appeler `deplacer` a la place n'alarmera pas mais
# corrompra silencieusement l'index (ancien Array chemin vs nouveau Vector3i).
# Idem dans l'autre sens.
func deplacer(chose) -> void:
	if not (chose is Dictionary and chose.has("id")):
		push_error("monde.gd : deplacer() -- 'chose' sans champ 'id'")
		return
	if not choses.has(chose.id):
		push_error("monde.gd : deplacer() -- id '%s' absent" % chose.id)
		return
	for exposant in _niveaux:
		var niveau = _niveaux[exposant]
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

# CHEMIN SIMPLE PUR, a appeler quand `structure_simple = true`. Aucun `if
# structure_simple`, aucun code subdivision dans cette fonction -- elle ne fait
# que ce dont le mode simple a besoin. Contrat : l'appelant a inscrit `chose`
# via `ajouter()`, `chose.id` existe, `chose.position` est a jour.
# Sur miss : appels `_deranger` + `_ranger` (versions rapides testees dans
# cette session ; leur variante `if structure_simple` a l'interieur ne pese
# qu'a l'ouverture d'une case, pas par appel).
func deplacer_simple(chose) -> void:
	var pos: Vector3 = chose.position
	var chose_id = chose.id
	for niveau_s in _niveaux_liste:
		var inv_a: float = niveau_s.inv_arete
		var visee_s := Vector3i(
			floori(pos.x * inv_a),
			floori(pos.y * inv_a),
			floori(pos.z * inv_a))
		var actuelle_v = niveau_s.case_de.get(chose_id)
		if actuelle_v != null and actuelle_v == visee_s:
			continue
		_deranger(niveau_s, chose_id)
		_ranger(niveau_s, int(niveau_s.exposant), chose_id, pos)

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
# LOT DE RETRAITS en UNE passe : applique N appels `retirer` sur un Array
# d'ids. Meme resultat exact que N appels a `retirer` dans le meme ordre.
# Ids inconnus : alarme + skip (comportement identique a la version
# unitaire, meme id-par-id).
#
# ECART FRAMEWORK : cette signature lot n'existe pas dans le depot Orion,
# ajoutee ici sous l'exception CLAUDE.md § Frontiere pour retirer les
# franchissements de frontiere par mort du banc `jeu/bancs/
# banc_peuplement_arbre.gd`. Meme geste doctrinal que `retirer()` et
# `ajouter_lot`.
func retirer_lot(ids: Array) -> void:
	var n: int = ids.size()
	if n == 0:
		return
	var k: int = 0
	while k < n:
		var id = ids[k]
		k += 1
		if not choses.has(id):
			push_error("monde.gd : retirer_lot() -- id '%s' absent" % id)
			continue
		for exposant in _niveaux:
			_deranger(_niveaux[exposant], id)
		choses.erase(id)
		_rang.erase(id)

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
	# inv_arete precalcule dans le niveau (voir _batir) : evite pow(2, exposant)
	# par requete et transforme les 3 divisions de _case_pour en 3
	# multiplications. Voir ECART FRAMEWORK en tete de fichier.
	var inv_a: float = niveau.inv_arete
	# _case_pour_inv inline (3 floori de multiplications, meme resultat).
	# ECART FRAMEWORK : voir bloc en tete de fichier.
	var pos_bas: Vector3 = position - Vector3(rayon, rayon, rayon)
	var pos_haut: Vector3 = position + Vector3(rayon, rayon, rayon)
	var basse := Vector3i(
		floori(pos_bas.x * inv_a),
		floori(pos_bas.y * inv_a),
		floori(pos_bas.z * inv_a))
	var haute := Vector3i(
		floori(pos_haut.x * inv_a),
		floori(pos_haut.y * inv_a),
		floori(pos_haut.z * inv_a))
	var carre := rayon * rayon
	requetes += 1
	for cx in range(basse.x, haute.x + 1):
		for cy in range(basse.y, haute.y + 1):
			for cz in range(basse.z, haute.z + 1):
				cases_lues += 1
				var cle := Vector3i(cx, cy, cz)
				var contenu = cases.get(cle, null)
				if contenu == null:
					continue
				# BRANCHE ARRAY INLINE : cas dominant sous structure_simple (chaque
				# case reste Array a plat, jamais Dictionary). Economise l'appel a
				# _collecter et son dispatch `is Array`, et surtout n'alloue pas
				# `origine` qui ne servirait a rien ici.
				if contenu is Array:
					for id in contenu:
						var entree: Dictionary = choses[id]
						var pos_vivante: Vector3 = entree.chose.position
						candidats_mesures += 1
						if position.distance_squared_to(pos_vivante) <= carre:
							resultat.append({"chose": entree.chose, "type": entree.type, "position": pos_vivante})
				else:
					# BRANCHE DICTIONARY : subdivision. Origine et arete calcules
					# PARESSEUSEMENT, uniquement quand on descend.
					var arete: float = 1.0 / inv_a
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
# REQUETE GROUPEE : pour chaque point de `positions`, meme calcul que
# `choses_dans_rayon(pos, rayon)`, mais UN seul acces au niveau /
# `inv_arete` / `cases` pour tout le lot -- economise le hashmap lookup
# du niveau et les bornes de boucle a chaque point. Rend un Array de
# meme longueur que `positions`, entree k = liste des voisins autour de
# `positions[k]`. `rayon` commun a tous les points.
# ECART FRAMEWORK : ce point d'entree n'existe pas dans le depot Orion,
# ajoute ici sous l'exception CLAUDE.md § Frontiere pour reduire les
# franchissements de frontiere lors du semis de lot du banc arbre
# (voir jeu/bancs/banc_peuplement_arbre.gd:_semer_lot). Meme geste
# doctrinal que retirer() ci-dessus.
func choses_dans_rayons(positions: Array, rayon: float) -> Array:
	var resultat: Array = []
	resultat.resize(positions.size())
	if positions.is_empty():
		return resultat
	var exposant := _exposant_pour(rayon)
	var niveau := _niveau(exposant)
	var cases: Dictionary = niveau.cases
	var inv_a: float = niveau.inv_arete
	var carre: float = rayon * rayon
	var offset := Vector3(rayon, rayon, rayon)
	var k: int = 0
	var n: int = positions.size()
	while k < n:
		var position: Vector3 = positions[k]
		var liste: Array = []
		# _case_pour_inv inline (voir bloc ECART FRAMEWORK en tete).
		var pos_bas: Vector3 = position - offset
		var pos_haut: Vector3 = position + offset
		var basse := Vector3i(
			floori(pos_bas.x * inv_a),
			floori(pos_bas.y * inv_a),
			floori(pos_bas.z * inv_a))
		var haute := Vector3i(
			floori(pos_haut.x * inv_a),
			floori(pos_haut.y * inv_a),
			floori(pos_haut.z * inv_a))
		requetes += 1
		for cx in range(basse.x, haute.x + 1):
			for cy in range(basse.y, haute.y + 1):
				for cz in range(basse.z, haute.z + 1):
					cases_lues += 1
					var cle := Vector3i(cx, cy, cz)
					var contenu = cases.get(cle, null)
					if contenu == null:
						continue
					if contenu is Array:
						for id in contenu:
							var entree: Dictionary = choses[id]
							var pos_vivante: Vector3 = entree.chose.position
							candidats_mesures += 1
							if position.distance_squared_to(pos_vivante) <= carre:
								liste.append({"chose": entree.chose, "type": entree.type, "position": pos_vivante})
					else:
						var arete: float = 1.0 / inv_a
						var origine := Vector3(cle) * arete
						_collecter(contenu, origine, arete, position, carre, liste)
		if trier_par_insertion:
			liste.sort_custom(_avant)
		resultat[k] = liste
		k += 1
	return resultat

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

# Segment [a, b] contre AABB [origine, origine + taille] etendu de demi_largeur
# sur chaque axe. Slab test standard sur l'AABB dilate : conservateur (les coins
# de l'AABB dilate depassent la capsule vraie), jamais un faux negatif -- une
# case qui contient un point du couloir renvoie toujours true. Faux positifs
# possibles aux coins (< 5%), rattrapes par le test distance point-segment sur
# chaque candidat de la case retenue.
func _segment_touche_boite(a: Vector3, b: Vector3, demi_largeur: float, origine: Vector3, taille: float) -> bool:
	var minimum := Vector3(origine.x - demi_largeur, origine.y - demi_largeur, origine.z - demi_largeur)
	var maximum := Vector3(origine.x + taille + demi_largeur, origine.y + taille + demi_largeur, origine.z + taille + demi_largeur)
	var direction := b - a
	var tmin := 0.0
	var tmax := 1.0
	for axe in range(3):
		var d: float = direction[axe]
		var origine_axe: float = a[axe]
		var min_axe: float = minimum[axe]
		var max_axe: float = maximum[axe]
		if absf(d) < 0.000001:
			if origine_axe < min_axe or origine_axe > max_axe:
				return false
			continue
		var t1: float = (min_axe - origine_axe) / d
		var t2: float = (max_axe - origine_axe) / d
		if t1 > t2:
			var tmp := t1
			t1 = t2
			t2 = tmp
		if t1 > tmin:
			tmin = t1
		if t2 < tmax:
			tmax = t2
		if tmin > tmax:
			return false
	return true

# Distance CARREE d'un point au segment [a, b], jamais la distance : meme
# verdict qu'un test avec racine, une racine de moins par candidat.
func _distance_carree_point_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
	var vecteur := b - a
	var longueur_carre := vecteur.length_squared()
	if longueur_carre <= 0.000001:
		return p.distance_squared_to(a)
	var t := clampf((p - a).dot(vecteur) / longueur_carre, 0.0, 1.0)
	var projection := a + vecteur * t
	return p.distance_squared_to(projection)

func choses_dans_couloir(depuis: Vector3, vers: Vector3, demi_largeur: float) -> Array:
	var resultat: Array = []
	if demi_largeur <= 0.0:
		return resultat
	var exposant := _exposant_pour(2.0 * demi_largeur)
	var niveau := _niveau(exposant)
	var cases: Dictionary = niveau.cases
	var arete := _arete(exposant)
	# BBOX du segment dilate de demi_largeur : borne les cases a visiter au
	# TUBE seul, jamais toute la sphere de rayon max(distances aux bouts).
	var minimum := Vector3(
		minf(depuis.x, vers.x) - demi_largeur,
		minf(depuis.y, vers.y) - demi_largeur,
		minf(depuis.z, vers.z) - demi_largeur)
	var maximum := Vector3(
		maxf(depuis.x, vers.x) + demi_largeur,
		maxf(depuis.y, vers.y) + demi_largeur,
		maxf(depuis.z, vers.z) + demi_largeur)
	var basse := _case_pour(minimum, exposant)
	var haute := _case_pour(maximum, exposant)
	var carre_largeur := demi_largeur * demi_largeur
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
				if not _segment_touche_boite(depuis, vers, demi_largeur, origine, arete):
					continue
				_collecter_couloir(contenu, origine, arete, depuis, vers, demi_largeur, carre_largeur, resultat)
	if trier_par_insertion:
		resultat.sort_custom(_avant)
	return resultat

# Meme discipline que _collecter, mais teste distance point-segment au lieu de
# distance point-centre. Descend dans les sous-cases dont l'AABB touche encore
# le segment epaissi (jamais dans les autres).
func _collecter_couloir(contenu, origine: Vector3, arete: float, depuis: Vector3, vers: Vector3, demi_largeur: float, carre_largeur: float, out: Array) -> void:
	if contenu is Array:
		for id in contenu:
			var entree: Dictionary = choses[id]
			var pos_vivante: Vector3 = entree.chose.position
			candidats_mesures += 1
			if _distance_carree_point_segment(pos_vivante, depuis, vers) <= carre_largeur:
				out.append({"chose": entree.chose, "type": entree.type, "position": pos_vivante})
		return
	if contenu is Dictionary:
		var demi := arete * 0.5
		for sub_key in contenu:
			var sub_origine: Vector3 = origine + Vector3(sub_key) * demi
			if not _segment_touche_boite(depuis, vers, demi_largeur, sub_origine, demi):
				continue
			cases_lues += 1
			_collecter_couloir(contenu[sub_key], sub_origine, demi, depuis, vers, demi_largeur, carre_largeur, out)

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
func _niveau(exposant: int) -> Object:
	if not _niveaux.has(exposant):
		var n := _batir(exposant)
		_niveaux[exposant] = n
		_niveaux_liste.append(n)
	return _niveaux[exposant]

func _batir(exposant: int) -> Object:
	# `_idx_dans_case` sert UNIQUEMENT au mode structure_simple : id -> index
	# dans l'Array de sa case, pour un swap-remove O(1) au deranger (au lieu
	# d'un find O(k)). Le dict est cree ici dans tous les cas -- cout memoire
	# nul quand structure_simple=false (jamais peuple).
	# `_inv_arete` : precalcul de 1/arete pour eliminer les 3 divisions par
	# case + le pow(2, exposant) dans le hot path de deplacer (mesure : 0.77
	# us/appel pour _case_pour, 30% du budget total du deplacer a N=100 000).
	# Stocke a la CREATION du niveau -- l'arete d'un niveau ne bouge plus
	# apres, la valeur reste valide pour toute la vie du Monde.
	var arete := _arete(exposant)
	var niveau := NiveauMonde.new()
	niveau.arete = arete
	niveau.inv_arete = 1.0 / arete
	niveau.exposant = exposant
	for id in choses:
		_ranger(niveau, exposant, id, choses[id].chose.position)
	return niveau

func _ranger(niveau, exposant: int, id, position: Vector3) -> void:
	var cases: Dictionary = niveau.cases
	var case_globale := _case_pour(position, exposant)
	if not cases.has(case_globale):
		cases[case_globale] = []
	# BRANCHE STRUCTURE SIMPLE : append id + index inverse, jamais _inserer
	# recursif, jamais SPLIT. Le contenu de cases[case_globale] reste TOUJOURS
	# un Array<id> a plat -- _collecter (choses_dans_rayon / _couloir) gere ce
	# cas nativement (test `contenu is Array`).
	# case_de[id] stocke Vector3i DIRECT (pas Array de taille 1) : evite
	# l'alloc d'un Array par appel de deplacer.get(id, []) -- mesure : 0.91 us
	# gagnees par appel a N=100 000.
	if structure_simple:
		var arr: Array = cases[case_globale]
		niveau.idx_dans_case[id] = arr.size()
		arr.append(id)
		niveau.case_de[id] = case_globale
		return
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
		arete: float, profondeur: int, niveau) -> void:
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
		arete: float, profondeur: int, niveau) -> void:
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

func _deranger(niveau, id) -> void:
	if not niveau.case_de.has(id):
		return
	# BRANCHE STRUCTURE SIMPLE : case_de[id] = Vector3i direct, pas Array de
	# chemin. Swap-remove O(1). Le voisin qui prend la place liberee voit son
	# idx mis a jour dans _idx_dans_case. Aucune purge remontante, aucun test
	# MERGE.
	if structure_simple:
		var cle_globale: Vector3i = niveau.case_de[id]
		niveau.case_de.erase(id)
		var cases_simple: Dictionary = niveau.cases
		if not cases_simple.has(cle_globale):
			return
		var contenu: Array = cases_simple[cle_globale]
		var idx: int = int(niveau.idx_dans_case.get(id, -1))
		niveau.idx_dans_case.erase(id)
		if idx < 0 or idx >= contenu.size():
			return
		var dernier: int = contenu.size() - 1
		if idx != dernier:
			var autre_id = contenu[dernier]
			contenu[idx] = autre_id
			niveau.idx_dans_case[autre_id] = idx
		contenu.resize(dernier)
		if contenu.is_empty():
			cases_simple.erase(cle_globale)
		return
	# ---- Chemin subdivision (structure_simple = false) ----
	var chemin: Array = niveau.case_de[id]
	niveau.case_de.erase(id)
	if chemin.is_empty():
		return
	var cases: Dictionary = niveau.cases
	_retirer_par_chemin(cases, chemin, 0, id)
	# Merge : si la racine de cette colonne est un Dictionary dont le total est
	# passe sous SEUIL_MERGE, on la reaplatit en Array terminal. Un seul niveau
	# de merge par retrait : hysteresis 5/20 rend le merge en cascade inutile.
	var cle_globale_sd = chemin[0]
	if cases.has(cle_globale_sd) and cases[cle_globale_sd] is Dictionary:
		if _totaliser(cases[cle_globale_sd]) < SEUIL_MERGE:
			_merger(cases, cle_globale_sd, niveau)

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
func _merger(cases: Dictionary, cle_globale, niveau) -> void:
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
