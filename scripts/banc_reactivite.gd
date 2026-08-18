extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_reactivite.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1). SEUL banc ou DEUX objets reels
# reagissent l'un avec l'autre, chacun apportant sa propre reactivite au score
# et produisant un objet neuf : patron reactif A + reactif B -> produit C. Les
# autres bancs d'accumulation (corrosion, pourriture, solubilite) n'ont qu'UN
# objet actif face a une CAUSE AMBIANTE PASSIVE.
#
# DECISION DE DESIGN (clarifiee en conversation avant d'ecrire, voir
# CLAUDE.md "Ne code pas ce que tu n'as pas compris") : produit.gd ne
# transforme JAMAIS deux objets en un seul (sa signature ne porte qu'un seul
# "proprietes_ancien", verifie sur le code reel), et monde.gd n'a aucune
# fonction de retrait d'objet. Les DEUX reactifs sont donc transformes
# SEPAREMENT, par deux appels distincts a produit.gd:transformer :
# - la CIBLE (fer/pierre/bois) devient son produit (sel_metallique/
#   residu_calcaire/residu_organique) quand SON PROPRE canal charge.gd
#   franchit son seuil ;
# - l'ACIDE devient residu_acide quand SA PROPRE reserve depense.gd
#   ("acide") atteint zero.
# Les deux processus sont COUPLES par la MEME grandeur (reactivite, fusionnee
# depuis data/materiaux.json) mais restent deux mecanismes independants,
# chacun deja ferme, jamais reecrit.
#
# PHASE 1 -- ACCUMULATION PAR CIBLE (charge.gd, DEJA FERME) : chaque cible
# porte SON PROPRE canal charge.gd nomme "reaction". Tant que l'acide est a
# portee (canal.portee_charge) ET qu'une entree data/reactions.json existe
# pour (materiau de l'acide, materiau de la cible), la cause qui alimente ce
# canal a pour poids score_reaction = reactivite(acide) * reactivite(cible)
# (score_reaction ci-dessous) -- calcule A CHAQUE TICK depuis les proprietes
# COURANTES des deux objets, jamais mis en cache : un score plus haut (fer,
# 0.6*0.95=0.57) remplit le MEME seuil (canal.seuil, initialise depuis
# data/reactions.json:seuil_reactivite a la fabrication) plus vite qu'un
# score plus bas (pierre, 0.1*0.95=0.095) -- "le fer reagit vite, la pierre
# lentement" emerge de la ponderation, aucun seuil distinct par paire n'est
# necessaire (les trois entrees de data/reactions.json partagent le meme
# seuil_reactivite). Une paire SANS entree dans data/reactions.json ne
# produit jamais de cause (causes reste vide) : ce canal n'accumule alors
# jamais, quelle que soit la distance -- "deux objets non reactifs ne
# reagissent jamais".
#
# PHASE 2 -- TRANSFORMATION DE LA CIBLE (produit.gd, DEJA FERME) : des que le
# canal "reaction" d'une cible franchit son seuil (poser: { marqueur_pret:
# true }, meme idiome que expose_corrosion/expose_humidite dans banc_corrosion.gd/
# banc_solubilite.gd), CE FICHIER appelle LUI-MEME scripts/produit.gd:transformer
# (charge.gd n'a pas de branche "produire") avec le type_produit/rendement de
# l'entree data/reactions.json correspondante, PUIS proprietes.clear() +
# proprietes.merge(...) -- meme geste que extinction.gd:_appliquer_a_zero,
# rejoue au niveau du cablage. Une cible deja transformee ne porte plus
# "etats" (chemin mort deja garanti par charge.gd sur un Dictionary absent)
# ET son materiau (sel_metallique/residu_calcaire/residu_organique) n'a plus
# d'entree dans data/reactions.json -- elle sort donc naturellement du calcul
# de score_reaction ET de la consommation de l'acide (Phase 3) sans aucune
# garde "deja transforme" supplementaire, meme discipline que banc_corrosion.gd/
# banc_solubilite.gd.
#
# PHASE 3 -- CONSOMMATION DE L'ACIDE (depense.gd, DEJA FERME) : l'acide porte
# UNE reserve nommee "acide". Son cout_base est recalcule CHAQUE TICK (meme
# idiome que le gate de cout_base dans banc_corrosion.gd/banc_solubilite.gd) =
# facteur_consommation_acide * SOMME(reactivite de chaque cible encore
# reactive -- une entree data/reactions.json existe toujours pour elle -- ET
# actuellement a portee_contact de l'acide) : "plus il y a de cibles
# reactives a portee, plus l'acide s'epuise vite" (consigne explicite),
# jamais pondere par la reactivite de l'acide lui-meme (deja comptee dans le
# score_reaction de la Phase 1). FERMETURE EXPLICITE, PAS UNE SIMPLE DECROISSANCE
# ORGANIQUE : si PLUS AUCUNE cible ne porte d'entree data/reactions.json (les
# trois ont fini de reagir), la reserve est forcee a 0.0 CE TICK -- sans cette
# regle, une consommation strictement proportionnelle aux cibles ENCORE actives
# se fige a une valeur residuelle des que la derniere cible a fini de reagir
# (plus aucune cible active = cout_base retombe a 0.0 = la reserve ne bouge
# plus jamais), et l'acide ne deviendrait JAMAIS residu_acide. Les CONSTANTES
# de demonstration (facteur_consommation_acide=0.4, reserve initiale 3.0) sont
# choisies pour que la decroissance ORGANIQUE (avant cette fermeture) ne
# descende JAMAIS a zero tant que la pierre (la plus lente) n'a pas fini de
# reagir -- verifie par calcul (aire sous la courbe de consommation avant
# t_pierre ~= 1.26, tres en dessous de la reserve 3.0) puis par test
# (_toutes_les_cibles_reagissent_avant_que_lacide_ne_sepuise ci-dessous) : la
# fermeture n'intervient donc jamais EN COURS DE REACTION, seulement une fois
# qu'il n'y a plus rien a consommer.
#
# PHASE 4 -- TRANSFORMATION DE L'ACIDE (produit.gd, DEJA FERME) : au meme
# geste que la Phase 2, des que depense.gd pose le marqueur terminal
# (data/seuils_combustible.json:epuisement_reactivite_acide, "acide_epuise"),
# CE FICHIER appelle produit.gd:transformer sur LES PROPRIETES DE L'ACIDE
# (jamais celles d'une cible) vers data/transformations.json:
# reactivite_acide_epuise (residu_acide).
#
# CE QU'ON DOIT VOIR : un acide_demo et trois cibles (fer/pierre/bois,
# materiaux REELS de data/materiaux.json) fabriquees par composition. Un clic
# gauche BASCULE la position de l'acide entre "proche" (a portee de contact
# des trois cibles a la fois) et "loin" (hors de toute portee) -- meme geste
# bistable que banc_corrosion.gd/banc_solubilite.gd, applique a une POSITION
# plutot qu'a un booleen. Proche : le fer (reactivite 0.6) devient
# sel_metallique en premier, le bois (0.2) ensuite, la pierre (0.1) en
# dernier -- l'acide se vide proportionnellement, plus vite au debut (les
# trois cibles reactives a la fois) qu'a la fin (une seule, la pierre,
# encore active). Une fois les trois cibles transformees, l'acide devient
# residu_acide. Loin : rien ne bouge, aucune charge n'accumule, la reserve
# d'acide reste figee. Label par objet : reactivite, charge de reaction
# (cible) ou reserve (acide), produit attendu (cible) ou statut (acide).
# Trace console : une ligne par bascule de position, par cible transformee,
# et quand l'acide devient residu_acide.
#
# AUCUN MECANISME DU COEUR TOUCHE : charge.gd, depense.gd, produit.gd,
# portee.gd et objet.gd sont ceux que verrouillent leurs propres tests.
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready fabrique l'acide et les trois cibles (Objet.fabriquer,
#   composition fusionnee). _unhandled_input bascule la position de l'acide
#   au clic gauche. _process appelle UNIQUEMENT avancer() (fonction statique,
#   ci-dessous) puis lit ses resultats pour l'affichage/la console -- jamais
#   un calcul refait ici (regle CLAUDE.md).
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_reactivite.gd) : trouver_reaction/materiau_de/score_reaction/
#   fabriquer_acide/fabriquer_cibles/basculer_position_acide/avancer/
#   diagnostiquer_cible/diagnostiquer_acide, plus le texte d'affichage et de
#   log.

const Objet = preload("res://scripts/objet.gd")
const Charge = preload("res://scripts/charge.gd")
const Depense = preload("res://scripts/depense.gd")
const Produit = preload("res://scripts/produit.gd")
const Portee = preload("res://scripts/portee.gd")

const TAILLE := 70.0
const HAUTEUR_BARRE := 10.0
const TAILLE_ACIDE := 40.0

var _config: Dictionary = {}
var _reactions: Array = []
var _catalogue_types: Dictionary = {}
var _materiaux: Dictionary = {}
var _config_produire_acide: Dictionary = {}
var _catalogue_seuils_acide: Dictionary = {}
var _acide: Dictionary = {}
var _acide_proche := false
var _cibles: Array = []
var _noeuds: Dictionary = {}
var _barres_fond: Dictionary = {}
var _barres_remplies: Dictionary = {}
var _labels: Dictionary = {}
var _noeud_acide: ColorRect
var _label_acide: Label
var _pret_avant: Dictionary = {}
var _transforme_avant: Dictionary = {}
var _acide_transforme_avant := false
var _temps: float = 0.0

func _ready() -> void:
	_config = _charger_json("res://data/banc_reactivite.json")
	_reactions = _charger_json("res://data/reactions.json").get("reactions", [])
	_materiaux = _charger_json("res://data/materiaux.json")
	var proprietes_immuables: Array = _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", [])
	_catalogue_types = _charger_json("res://data/types.json")
	var transformations: Dictionary = _charger_json("res://data/transformations.json").get("transformations", {})
	_config_produire_acide = transformations.get(_config.transformation_acide, {}).get("a_zero", {}).get("produire", {})
	_catalogue_seuils_acide = _charger_json("res://data/seuils_combustible.json")

	_acide = fabriquer_acide(_config.acide, false, _materiaux, proprietes_immuables, _config)
	_acide_proche = false
	_cibles = fabriquer_cibles(_config.get("cibles", []), _materiaux, proprietes_immuables, _config, _reactions)

	for cible in _cibles:
		_pret_avant[cible.id] = false
		_transforme_avant[cible.id] = false
		_creer_rendu_objet(cible)
	_creer_rendu_acide()
	_poser_camera()

	for cible in _cibles:
		var diag := diagnostiquer_cible(cible, _config, _reactions)
		print(_ligne_pose_initiale(cible.id, diag))
	_rafraichir_tout()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_acide_proche = basculer_position_acide(_acide, _acide_proche, _config.acide.position_proche, _config.acide.position_loin)
		print(_ligne_position(_temps, _acide_proche))
		_rafraichir_tout()

func _process(delta: float) -> void:
	_temps += delta
	var resultat := avancer(_acide, _cibles, delta, _config, _reactions, _catalogue_seuils_acide, _config_produire_acide, _catalogue_types, _materiaux)

	for cible in _cibles:
		var id: String = cible.id
		if _transforme_avant.get(id, false):
			continue

		var pret: bool = cible.proprietes.get(_config.marqueur_pret, false)
		if pret != _pret_avant.get(id, false):
			var canal: Dictionary = cible.proprietes.get("etats", {}).get(_config.nom_canal_reaction, {})
			print(_ligne_pret(_temps, id, pret, canal.get("charge", 0.0), canal.get("seuil", 0.0)))
			_pret_avant[id] = pret

		if id in resultat.transformes_cibles:
			print(_ligne_transforme_cible(_temps, id, cible.proprietes.get("masse", 0.0)))
			_transforme_avant[id] = true

	if resultat.acide_transforme and not _acide_transforme_avant:
		print(_ligne_transforme_acide(_temps, _acide.proprietes.get("masse", 0.0)))
		_acide_transforme_avant = true

	_rafraichir_tout()

func _rafraichir_tout() -> void:
	for cible in _cibles:
		var id: String = cible.id
		if _transforme_avant.get(id, false):
			_noeuds[id].color = _COULEUR_PRODUIT
			_labels[id].text = _texte_label_produit(id, cible.proprietes)
			_barres_remplies[id].size.x = 0.0
			continue
		var diag := diagnostiquer_cible(cible, _config, _reactions)
		_noeuds[id].color = _teinte_pour_statut(diag.statut)
		var ratio: float = clamp(diag.charge / diag.seuil, 0.0, 1.0) if diag.seuil > 0.0 else 0.0
		_barres_remplies[id].size.x = _barres_fond[id].size.x * ratio
		_labels[id].text = _texte_label_cible(id, diag)

	if _acide_transforme_avant:
		_noeud_acide.color = _COULEUR_ACIDE_EPUISE
		_label_acide.text = _texte_label_acide_epuise(_acide.proprietes)
	else:
		var diag_acide := diagnostiquer_acide(_acide, _config)
		_noeud_acide.color = _COULEUR_ACIDE
		_label_acide.text = _texte_label_acide(diag_acide, _acide_proche)
	var centre_acide := Vector2(_acide.position.x, _acide.position.y)
	_noeud_acide.position = centre_acide - _noeud_acide.size / 2.0
	_label_acide.position = centre_acide - Vector2(TAILLE_ACIDE / 2.0, TAILLE_ACIDE / 2.0 + 90.0)

# ---- Fonctions PURES, testables headless (voir test_banc_reactivite.gd) ----

# Trouve l'entree data/reactions.json pour la paire (materiau_a, materiau_b),
# ou {} si aucune n'existe -- SEULE source de verite sur quelles paires
# reagissent, aucun nom de materiau en dur ailleurs dans ce fichier.
static func trouver_reaction(reactions: Array, materiau_a: String, materiau_b: String) -> Dictionary:
	for entree in reactions:
		if entree.get("materiau_a", "") == materiau_a and entree.get("materiau_b", "") == materiau_b:
			return entree
	return {}

# Lit le materiau d'un objet fabrique par composition (mono-materiau, meme
# lecture que banc_corrosion.gd:_texte_label_rouille) -- "" si absent.
static func materiau_de(objet: Dictionary) -> String:
	var composition: Array = objet.get("proprietes", {}).get("composition", [])
	if composition.is_empty():
		return ""
	return String(composition[0].get("materiau", ""))

# Poids de la Phase 1 -- calcule A CHAQUE APPEL depuis les proprietes
# COURANTES des deux objets, jamais mis en cache (voir en-tete).
static func score_reaction(proprietes_acide: Dictionary, proprietes_cible: Dictionary) -> float:
	return float(proprietes_acide.get("reactivite", 0.0)) * float(proprietes_cible.get("reactivite", 0.0))

static func basculer_position_acide(acide: Dictionary, proche: bool, position_proche: Array, position_loin: Array) -> bool:
	var nouveau_proche := not proche
	var p: Array = position_proche if nouveau_proche else position_loin
	acide.position = Vector3(p[0], p[1], p[2])
	return nouveau_proche

static func fabriquer_acide(decl: Dictionary, proche: bool, materiaux: Dictionary, proprietes_immuables: Array, config: Dictionary) -> Dictionary:
	var catalogue: Dictionary = {decl.id: {"composition": decl.composition}}
	var p: Array = decl.position_proche if proche else decl.position_loin
	var objet := Objet.fabriquer(decl.id, decl.id, Vector3(p[0], p[1], p[2]), catalogue, materiaux, proprietes_immuables)
	objet.proprietes["reserves"] = {config.nom_reserve_acide: config.reserve_acide_defaut.duplicate(true)}
	return objet

# Construit les trois cibles via Objet.fabriquer (composition fusionnee --
# meme patron que banc_corrosion.gd/banc_solubilite.gd). Chaque cible recoit
# SON PROPRE canal "reaction" (duplique, jamais partage) dont le seuil est
# initialise DEPUIS data/reactions.json:seuil_reactivite (l'entree
# correspondant a son materiau) -- si aucune entree n'existe pour cette
# cible, le canal garde le seuil par defaut de la config (jamais atteint en
# pratique puisque Phase 1 ne lui fournit alors jamais de cause).
static func fabriquer_cibles(declarations: Array, materiaux: Dictionary, proprietes_immuables: Array, config: Dictionary, reactions: Array) -> Array:
	var catalogue: Dictionary = {}
	for decl in declarations:
		catalogue[decl.id] = {"composition": decl.composition}
	var objets: Array = []
	for decl in declarations:
		var pos: Array = decl.position
		var objet := Objet.fabriquer(decl.id, decl.id, Vector3(pos[0], pos[1], pos[2]), catalogue, materiaux, proprietes_immuables)
		var materiau_cible: String = decl.composition[0].materiau
		var entree := trouver_reaction(reactions, config.materiau_acide, materiau_cible)
		var canal: Dictionary = config.canal_reaction_defaut.duplicate(true)
		if not entree.is_empty():
			canal["seuil"] = entree.seuil_reactivite
		objet.proprietes["etats"] = {config.nom_canal_reaction: canal}
		objets.append(objet)
	return objets

# UN PAS de simulation complet, les quatre phases dans l'ordre (voir en-tete
# pour le detail de chacune). Rend { bascules: Array d'id de cible ayant
# franchi le seuil de "reaction" ce pas, transformes_cibles: Array d'id de
# cible devenues leur produit ce pas, franchis_acide: Array (contrat
# Depense.avancer, ici toujours [] ou [acide.id]), acide_transforme: bool }.
static func avancer(acide: Dictionary, cibles: Array, delta: float, config: Dictionary, reactions: Array, catalogue_seuils_acide: Dictionary, config_produire_acide: Dictionary, table: Dictionary, materiaux: Dictionary) -> Dictionary:
	# Phase 1 -- accumulation par cible.
	var bascules: Array = []
	for cible in cibles:
		var materiau_cible: String = materiau_de(cible)
		var entree := trouver_reaction(reactions, config.materiau_acide, materiau_cible)
		var causes: Array = []
		if not entree.is_empty():
			causes = [{"position": acide.position, "poids": score_reaction(acide.proprietes, cible.proprietes)}]
		var b := Charge.avancer([cible], causes, delta)
		if not b.is_empty():
			bascules.append(cible.id)

	# Phase 2 -- transformation de chaque cible fraichement prete.
	var transformes_cibles: Array = []
	for cible in cibles:
		if not cible.proprietes.get(config.marqueur_pret, false):
			continue
		var materiau_cible2: String = materiau_de(cible)
		var entree2 := trouver_reaction(reactions, config.materiau_acide, materiau_cible2)
		if entree2.is_empty():
			continue
		var nouvelles: Dictionary = Produit.transformer(cible.proprietes, {"type_produit": entree2.type_produit, "rendement": entree2.rendement}, table, materiaux)
		if nouvelles.is_empty():
			continue
		cible.proprietes.clear()
		cible.proprietes.merge(nouvelles, true)
		transformes_cibles.append(cible.id)

	# Phase 3 -- consommation de l'acide, proportionnelle aux cibles encore
	# reactives ET a portee de contact -- fermeture explicite si plus aucune
	# cible ne reste reactive (voir en-tete).
	var reserves: Dictionary = acide.proprietes.get("reserves", {})
	var nom_reserve: String = config.nom_reserve_acide
	if reserves.has(nom_reserve):
		var reste_actif := false
		var somme := 0.0
		for cible in cibles:
			var materiau_cible3: String = materiau_de(cible)
			var entree3 := trouver_reaction(reactions, config.materiau_acide, materiau_cible3)
			if entree3.is_empty():
				continue
			reste_actif = true
			if not Portee.en_portee(acide.position, cible.position, config.portee_contact):
				continue
			somme += float(cible.proprietes.get("reactivite", 0.0))
		if reste_actif:
			reserves[nom_reserve]["cout_base"] = config.facteur_consommation_acide * somme
		else:
			reserves[nom_reserve]["cout_base"] = 0.0
			reserves[nom_reserve]["reserve"] = 0.0

	var franchis_acide := Depense.avancer([acide], delta, catalogue_seuils_acide)

	# Phase 4 -- transformation de l'acide, une fois epuise.
	var acide_transforme := false
	if acide.proprietes.get(config.marqueur_acide_epuise, false):
		var nouvelles_acide: Dictionary = Produit.transformer(acide.proprietes, config_produire_acide, table, materiaux)
		if not nouvelles_acide.is_empty():
			acide.proprietes.clear()
			acide.proprietes.merge(nouvelles_acide, true)
			acide_transforme = true

	return {"bascules": bascules, "transformes_cibles": transformes_cibles, "franchis_acide": franchis_acide, "acide_transforme": acide_transforme}

# Diagnostic d'affichage, PUR : lit uniquement des valeurs deja calculees par
# charge.gd, ne reimplemente jamais sa loi (meme doctrine que
# banc_corrosion.gd/banc_solubilite.gd:diagnostiquer). Rend { statut,
# materiau, reactivite, charge, seuil, produit_attendu }.
static func diagnostiquer_cible(cible: Dictionary, config: Dictionary, reactions: Array) -> Dictionary:
	var materiau_cible: String = materiau_de(cible)
	var entree := trouver_reaction(reactions, config.materiau_acide, materiau_cible)
	var canal: Dictionary = cible.proprietes.get("etats", {}).get(config.nom_canal_reaction, {})
	var pret: bool = cible.proprietes.get(config.marqueur_pret, false)
	var statut: String = "pret" if pret else ("reactif" if not entree.is_empty() else "inerte")
	return {
		"statut": statut,
		"materiau": materiau_cible,
		"reactivite": cible.proprietes.get("reactivite", 0.0),
		"charge": canal.get("charge", 0.0),
		"seuil": canal.get("seuil", 0.0),
		"produit_attendu": entree.get("type_produit", ""),
	}

# Meme doctrine, pour l'acide -- rend { reactivite, reserve, reserve_initiale }.
static func diagnostiquer_acide(acide: Dictionary, config: Dictionary) -> Dictionary:
	var canal_reserve: Dictionary = acide.proprietes.get("reserves", {}).get(config.nom_reserve_acide, {})
	return {
		"reactivite": acide.proprietes.get("reactivite", 0.0),
		"reserve": canal_reserve.get("reserve", 0.0),
		"reserve_initiale": config.reserve_acide_defaut.get("reserve", 0.0),
	}

const _COULEUR_PRODUIT := Color(0.55, 0.5, 0.35)
const _COULEUR_ACIDE := Color(0.3, 0.75, 0.35)
const _COULEUR_ACIDE_EPUISE := Color(0.6, 0.65, 0.5)

static func _teinte_pour_statut(statut: String) -> Color:
	match statut:
		"pret":
			return Color(0.85, 0.55, 0.2)
		"reactif":
			return Color(0.6, 0.55, 0.5)
		_:
			return Color(0.55, 0.55, 0.6)

static func _texte_label_cible(id: String, diag: Dictionary) -> String:
	return "%s\nmateriau=%s\nreactivite=%.2f\ncharge_reaction=%.2f/%.2f\nproduit_attendu=%s\netat=%s" % [
		id, diag.materiau, diag.reactivite, diag.charge, diag.seuil, diag.produit_attendu, diag.statut,
	]

static func _texte_label_produit(id: String, proprietes: Dictionary) -> String:
	var materiau: String = ""
	var composition: Array = proprietes.get("composition", [])
	if not composition.is_empty():
		materiau = String(composition[0].get("materiau", ""))
	return "%s\nTRANSFORME\nmateriau=%s\nmasse=%.2f" % [id, materiau, proprietes.get("masse", 0.0)]

static func _texte_label_acide(diag: Dictionary, proche: bool) -> String:
	return "acide_demo\nreactivite=%.2f\nreserve=%.2f/%.2f\nposition=%s" % [
		diag.reactivite, diag.reserve, diag.reserve_initiale, "PROCHE" if proche else "LOIN",
	]

static func _texte_label_acide_epuise(proprietes: Dictionary) -> String:
	var materiau: String = ""
	var composition: Array = proprietes.get("composition", [])
	if not composition.is_empty():
		materiau = String(composition[0].get("materiau", ""))
	return "acide_demo\nEPUISE\nmateriau=%s\nmasse=%.2f" % [materiau, proprietes.get("masse", 0.0)]

static func _ligne_pose_initiale(id: String, diag: Dictionary) -> String:
	return "t=0.0s %s : materiau=%s reactivite=%.2f seuil=%.2f produit_attendu=%s" % [
		id, diag.materiau, diag.reactivite, diag.seuil, diag.produit_attendu,
	]

static func _ligne_position(t: float, proche: bool) -> String:
	return "t=%.1fs acide_demo : %s" % [t, "RAPPROCHE" if proche else "ELOIGNE"]

static func _ligne_pret(t: float, id: String, pret: bool, charge: float, seuil: float) -> String:
	if pret:
		return "t=%.1fs %s : seuil de reaction franchi (charge=%.2f, seuil=%.2f)" % [t, id, charge, seuil]
	return "t=%.1fs %s : charge de reaction redescend sous le seuil (charge=%.2f, seuil=%.2f)" % [t, id, charge, seuil]

static func _ligne_transforme_cible(t: float, id: String, masse: float) -> String:
	return "t=%.1fs %s : reaction terminee -- transforme en produit (masse=%.2f)" % [t, id, masse]

static func _ligne_transforme_acide(t: float, masse: float) -> String:
	return "t=%.1fs acide_demo : reserve epuisee -- transforme en residu_acide (masse=%.2f)" % [t, masse]

# ---- Rendu (impur, Node) -- aucune decision, seulement la construction des
# noeuds et la camera.

func _creer_rendu_objet(cible: Dictionary) -> void:
	var id: String = cible.id
	var centre := Vector2(cible.position.x, cible.position.y)

	var noeud := ColorRect.new()
	noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noeud.size = Vector2(TAILLE, TAILLE)
	noeud.position = centre - noeud.size / 2.0
	add_child(noeud)
	_noeuds[id] = noeud

	var fond := ColorRect.new()
	fond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fond.color = Color(0.2, 0.2, 0.2)
	fond.size = Vector2(TAILLE, HAUTEUR_BARRE)
	fond.position = centre + Vector2(-TAILLE / 2.0, TAILLE / 2.0 + 6.0)
	add_child(fond)
	_barres_fond[id] = fond

	var rempli := ColorRect.new()
	rempli.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rempli.color = Color(0.85, 0.55, 0.2)
	rempli.size = Vector2(0.0, HAUTEUR_BARRE)
	rempli.position = fond.position
	add_child(rempli)
	_barres_remplies[id] = rempli

	var label := Label.new()
	label.position = centre - Vector2(TAILLE / 2.0, TAILLE / 2.0 + 130.0)
	add_child(label)
	_labels[id] = label

func _creer_rendu_acide() -> void:
	var noeud := ColorRect.new()
	noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noeud.size = Vector2(TAILLE_ACIDE, TAILLE_ACIDE)
	add_child(noeud)
	_noeud_acide = noeud

	var label := Label.new()
	add_child(label)
	_label_acide = label

func _poser_camera() -> void:
	var decl_camera: Dictionary = _config.get("camera", {})
	var pos: Array = decl_camera.get("position", [0.0, 0.0, 0.0])
	var camera := Camera2D.new()
	camera.position = Vector2(pos[0], pos[1])
	camera.zoom = Vector2(decl_camera.get("zoom", 1.0), decl_camera.get("zoom", 1.0))
	camera.enabled = true
	add_child(camera)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
