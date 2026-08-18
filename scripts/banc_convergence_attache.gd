extends Node2D

# Cablage de banc VISUEL, separe des autres bancs (Scene/banc_convergence_attache.tscn,
# PAS la scene principale -- run/main_scene reste banc_p1). Existe pour VOIR
# scripts/comptage.gd recevoir son PREMIER CABLAGE REEL SUR DES COLONS ORION
# (apres banc_comptage.gd, hors domaine) : plusieurs colons forment
# INDIVIDUELLEMENT une attache par trait au meme trait ("brule"), et un
# compteur REGIONAL affiche combien en portent une, a chaque instant --
# PRODUIT par un lecteur agrege (Comptage.compter), jamais PORTE par un
# objet-groupe. JETABLE PAR DEFINITION.
#
# CE QUE CE BANC MONTRE : trois colons percoivent trois arbres deja en feu
# (brule: true, poses au demarrage, jamais par propagation.gd). Chaque tick
# ou un colon PERCOIT un arbre en feu, LienPersonnel.poser accumule un lien
# vers CET arbre precis (meme geste que banc_deformation.gd : perception
# repetee -> accumulation, aucune decision). Une fois assez de liens
# distincts assez forts (attache_par_trait.gd, deja ferme et deja cable sur
# banc_lien_personnel.gd), un colon cristallise une attache GENERALE au
# trait "brule" -- il ne s'agit plus alors de CES arbres precis, mais de
# tout ce qui brule. Comptage.compter (regle_id "colons_attache_brule",
# mode "contient_element_avec_champ" -- cherche un element { propriete:
# "brule" } dans proprietes.attaches) rend, a chaque tick, COMBIEN des trois
# colons ont deja cristallise -- un FAIT COLLECTIF lu a la demande sur trois
# colons individuels, jamais un compteur porte par un objet-nuee. Une
# moyenne glissante (meme composition que banc_comptage.gd, calculee ICI,
# jamais dans comptage.gd) lisse ce compte sur une fenetre plus longue,
# cohaerente avec la lenteur de la cristallisation.
#
# CE QUE CE BANC NE FAIT PAS : il ne fait JAMAIS peser ce fait collectif sur
# la decision d'un colon -- aucun agir.gd, aucune dominance.gd, aucune
# proximite/attaches.gd, aucun verbe resolu ici. Le fait est PRODUIT, jamais
# CONSOMME. La croyance collective (un colon qui pese ce que d'autres
# colons portent) est le chantier SUIVANT, distinct, non commence ici.
#
# CABLAGE DIRECT, PAS LE PIPELINE A QUATRE COUCHES DE banc_lien_personnel.gd :
# la ligne generatrice ("un lien monte quand un colon percoit une chose de
# maniere repetee") ne passe par AUCUNE decision -- LienPersonnel.poser est
# appele directement des qu'un declencheur est percu, comme
# banc_deformation.gd:avancer_colon (Deformation.poser), jamais via l'effet
# de bord ACTES LIANTS de agir.gd:choisir (qui exige une decision resolue en
# "eteindre" sur une propriete comme "notre_ouvrage" -- inutile ici, aucun
# verbe n'est jamais resolu). Seuls lien_personnel.gd et attache_par_trait.gd
# sont reutilises, PAS le reste du pipeline de banc_lien_personnel.gd.
#
# CATALOGUE D'ATTACHE PAR TRAIT STRICTEMENT LOCAL (tension trouvee et
# corrigee AVANT ce fichier, voir data/banc_convergence_attache.json,
# "_note") : la regle "generalisation_brule" ne vit JAMAIS dans
# data/attaches_par_trait.json (partage) -- une premiere tentative d'y
# ajouter une regle globale sur "brule" a casse test_banc_lien_personnel.gd,
# dont les objets notre_ouvrage portent AUSSI brule:true. La regle reste
# donc scopee a ce seul banc (chargee depuis
# data/banc_convergence_attache.json:catalogue_attaches_par_trait), jamais
# fusionnee au catalogue partage.
#
# CONVERGENCE ECHELONNEE : les trois colons percoivent les TROIS memes
# arbres (memes liens, meme force a chaque tick) -- seul
# sensibilite_generalisation.brule.seuil_force differe par colon (meme
# patron de surcharge que data/banc_lien_personnel.json, pompier_rapide/
# moyen/lent), ce qui les fait cristalliser a des instants differents sans
# jamais varier leur exposition.
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge data/banc_convergence_attache.json,
#   data/types.json (paquets objet_physique/dynamique/percevant/agent/colon),
#   data/canaux.json, data/liens_personnels.json, data/comptages.json
#   (catalogues partages, jamais mutes). _process appelle
#   _avancer_tick_pour_colons(...) puis _compter_attaches_brule(...), met a
#   jour l'historique et redessine (couleur des colons, cercles des arbres,
#   texte des deux labels).
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_convergence_attache.gd) : _avancer_tick_pour_colons(...) --
#   mute une liste de colons en place (perception -> lien_personnel ->
#   attache_par_trait, un tick), rend les formations d'attache nouvelles ce
#   tick ; _compter_attaches_brule(...) -- enveloppe testable autour de
#   Comptage.compter ; _moyenne_glissante(...) -- moyenne arithmetique d'un
#   Array de comptes (duplique depuis banc_comptage.gd, meme fonction pure,
#   candidate a une promotion dans banc_commun.gd le jour ou un troisieme
#   banc en aurait besoin -- non fait ici, hors perimetre de ce chantier).

const Objet = preload("res://scripts/objet.gd")
const Monde = preload("res://scripts/monde.gd")
const Perception = preload("res://scripts/perception.gd")
const LienPersonnel = preload("res://scripts/lien_personnel.gd")
const AttacheParTrait = preload("res://scripts/attache_par_trait.gd")
const Comptage = preload("res://scripts/comptage.gd")

const TAILLE_CARRE := 24.0
const RAYON_ARBRE := 14.0
const SEGMENTS_CERCLE := 20

var _declencheur := ""
var _magnitude := 0.0
var _fenetre_moyenne := 60
var _catalogue_types: Dictionary = {}
var _catalogue_canaux: Dictionary = {}
var _catalogue_liens: Dictionary = {}
var _catalogue_attaches_par_trait: Dictionary = {}
var _catalogue_comptages: Dictionary = {}
var _couleur_arbre := Color.ORANGE
var _couleur_sans_attache := Color.GRAY
var _couleur_avec_attache := Color.RED
var _monde := Monde.new()
var _colons: Array = []
var _noeuds: Dictionary = {}
var _historique_comptes: Array = []
var _label_compte: Label
var _label_moyenne: Label

func _ready() -> void:
	var donnees := _charger_json("res://data/banc_convergence_attache.json")
	_declencheur = donnees.get("declencheur", "brule")
	_magnitude = donnees.get("magnitude_exposition", 0.0)
	_fenetre_moyenne = int(donnees.get("fenetre_moyenne", 60))
	_catalogue_attaches_par_trait = donnees.get("catalogue_attaches_par_trait", {})

	var rgb_arbre: Array = donnees.get("couleur_arbre", [1.0, 0.5, 0.0])
	var rgb_sans: Array = donnees.get("couleur_sans_attache", [0.4, 0.5, 0.7])
	var rgb_avec: Array = donnees.get("couleur_avec_attache", [0.9, 0.2, 0.2])
	_couleur_arbre = Color(rgb_arbre[0], rgb_arbre[1], rgb_arbre[2])
	_couleur_sans_attache = Color(rgb_sans[0], rgb_sans[1], rgb_sans[2])
	_couleur_avec_attache = Color(rgb_avec[0], rgb_avec[1], rgb_avec[2])

	# "arbre" reste local (vocabulaire propre a ce banc, voir CLAUDE.md) ;
	# objet_physique/dynamique/percevant/agent/colon viennent du catalogue
	# PARTAGE (data/types.json), meme geste que banc_deformation.gd/
	# banc_lien_personnel.gd:_ready.
	_catalogue_types = donnees.get("types", {}).duplicate(true)
	var types_partages := _charger_json("res://data/types.json")
	_catalogue_types["objet_physique"] = types_partages.get("objet_physique", {})
	_catalogue_types["dynamique"] = types_partages.get("dynamique", {})
	_catalogue_types["percevant"] = types_partages.get("percevant", {})
	_catalogue_types["agent"] = types_partages.get("agent", {})
	_catalogue_types["colon"] = types_partages.get("colon", {})

	_catalogue_canaux = _charger_json("res://data/canaux.json")
	_catalogue_liens = _charger_json("res://data/liens_personnels.json")
	_catalogue_comptages = _charger_json("res://data/comptages.json")

	var positions_arbres: Array = donnees.get("positions_arbres", [])
	for i in positions_arbres.size():
		_ajouter_arbre("arbre_%d" % i, positions_arbres[i])

	var declarations: Dictionary = donnees.get("colons", {})
	for nom in declarations:
		_ajouter_colon(nom, declarations[nom])

	_label_compte = _dessiner_label(Vector2(20.0, 20.0))
	_label_moyenne = _dessiner_label(Vector2(20.0, 44.0))
	_rafraichir_affichage(0, 0.0)

func _ajouter_arbre(id: String, pos: Array) -> void:
	var position3 := Vector3(pos[0], pos[1], pos[2])
	var objet := Objet.fabriquer(id, "arbre", position3, _catalogue_types)
	_monde.ajouter(objet, "arbre", position3)
	_noeuds[id] = _dessiner_cercle(position3, _couleur_arbre)

func _ajouter_colon(nom: String, decl: Dictionary) -> void:
	var pos: Array = decl.get("position", [0.0, 0.0, 0.0])
	var position3 := Vector3(pos[0], pos[1], pos[2])
	var colon := Objet.fabriquer(nom, "colon", position3, _catalogue_types)
	# sensibilite_generalisation (surcharge PAR COLON des seuils
	# d'attache_par_trait.gd, voir en-tete) : FACULTATIVE sur l'entite (voir
	# attache_par_trait.gd), pose ici en LOCAL -- meme geste que
	# banc_lien_personnel.gd:_ajouter_colon.
	colon.proprietes["sensibilite_generalisation"] = decl.get("sensibilite_generalisation", {})
	_monde.ajouter(colon, "colon", colon.position)
	_colons.append(colon)
	_noeuds[colon.id] = _dessiner_carre(position3, _couleur_sans_attache)

func _process(delta: float) -> void:
	var formations := _avancer_tick_pour_colons(
		_colons, _monde, _catalogue_canaux, _declencheur, _magnitude,
		_catalogue_liens, _catalogue_attaches_par_trait, delta,
	)
	for formation in formations:
		print("%s : attache par trait formee -> %s" % [formation.colon_id, str(formation.nouveaux)])
	var compte := _compter_attaches_brule(_colons, _catalogue_comptages)
	_historique_comptes.append(compte)
	if _historique_comptes.size() > _fenetre_moyenne:
		_historique_comptes.pop_front()
	_rafraichir_affichage(compte, _moyenne_glissante(_historique_comptes))

# UN TICK pour une LISTE de colons : pour chacun, percoit (Perception.percevoir,
# reel) -> pose un lien vers CHAQUE arbre percu portant `declencheur` (jamais
# de decision, jamais agir.gd -- voir en-tete) -> fait decroitre tous les
# liens -> verifie la cristallisation en attache par trait. Rend, pour les
# SEULS colons ayant gagne un trait CE tick, { colon_id, nouveaux } -- vide
# si rien n'a change (meme convention que AttacheParTrait.avancer).
static func _avancer_tick_pour_colons(
	colons: Array,
	monde,
	catalogue_canaux: Dictionary,
	declencheur: String,
	magnitude: float,
	catalogue_liens: Dictionary,
	catalogue_attaches_par_trait: Dictionary,
	delta: float,
) -> Array:
	var formations: Array = []
	for colon in colons:
		var perceptions := Perception.percevoir(colon, monde, catalogue_canaux)
		for entree in perceptions:
			if entree.chose.proprietes.get(declencheur, false):
				LienPersonnel.poser(colon, entree.chose.id, magnitude)
		LienPersonnel.avancer(colon, delta, catalogue_liens)
		var nouveaux := AttacheParTrait.avancer(colon, monde, catalogue_attaches_par_trait)
		if not nouveaux.is_empty():
			formations.append({"colon_id": colon.id, "nouveaux": nouveaux})
	return formations

# Enveloppe testable autour de Comptage.compter -- fixe le regle_id de ce
# banc ("colons_attache_brule", data/comptages.json), jamais un catalogue
# ou une regle devinee ailleurs.
static func _compter_attaches_brule(colons: Array, catalogue_comptages: Dictionary) -> int:
	return Comptage.compter(colons, "colons_attache_brule", catalogue_comptages)

# Moyenne arithmetique d'un Array de comptes (int/float). 0.0 sur un
# historique vide, point neutre legitime. comptage.gd ne connait ni le
# temps ni l'historique : cette composition reste dans le banc (meme
# fonction pure que banc_comptage.gd:_moyenne_glissante, dupliquee ici --
# voir en-tete).
static func _moyenne_glissante(historique: Array) -> float:
	if historique.is_empty():
		return 0.0
	var somme := 0.0
	for compte in historique:
		somme += compte
	return somme / historique.size()

func _dessiner_carre(position3: Vector3, couleur: Color) -> ColorRect:
	var carre := ColorRect.new()
	carre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	carre.size = Vector2(TAILLE_CARRE, TAILLE_CARRE)
	carre.color = couleur
	carre.position = Vector2(position3.x, position3.y) - carre.size / 2.0
	add_child(carre)
	return carre

func _dessiner_cercle(position3: Vector3, couleur: Color) -> Polygon2D:
	var cercle := Polygon2D.new()
	cercle.color = couleur
	var points := PackedVector2Array()
	for i in SEGMENTS_CERCLE:
		var angle := TAU * float(i) / float(SEGMENTS_CERCLE)
		points.append(Vector2(cos(angle), sin(angle)) * RAYON_ARBRE)
	cercle.polygon = points
	cercle.position = Vector2(position3.x, position3.y)
	add_child(cercle)
	return cercle

func _dessiner_label(position2: Vector2) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.position = position2
	add_child(label)
	return label

func _rafraichir_affichage(compte: int, moyenne: float) -> void:
	for colon in _colons:
		var carre: ColorRect = _noeuds[colon.id]
		carre.color = _couleur_avec_attache if not colon.proprietes.attaches.is_empty() else _couleur_sans_attache
	_label_compte.text = "%d / %d colons portent attache au feu" % [compte, _colons.size()]
	_label_moyenne.text = "moyenne sur les %d derniers ticks : %.1f" % [_fenetre_moyenne, moyenne]

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
