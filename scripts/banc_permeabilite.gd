extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_permeabilite.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1). Chantier "permeabilite" :
# la permeabilite (data/materiaux.json, DORMANTE avant ce chantier) module
# desormais la RETENTION d'eau -- jamais l'absorption. La distinction avec
# banc_humidite.gd est le point entier de ce banc : la-bas, absorption_
# humidite (module la MONTEE, via un poids receveur pre-multiplie) et
# porosite (module la MONTEE aussi, par-dessus l'absorption) sont les deux
# seules variables ; ici, les deux objets recoivent la MEME cause au MEME
# poids implicite (1.0, jamais pre-multiplie) -- ils montent donc
# STRICTEMENT a la meme vitesse. Seul taux_decroissance (charge.gd, lu
# directement sur le canal de CHAQUE objet, jamais un parametre global)
# diverge, calcule UNE SEULE FOIS a la fabrication depuis permeabilite :
# taux_decroissance = taux_decroissance_plancher + facteur_permeabilite *
# permeabilite -- meme forme (base + facteur * grandeur) que banc_humidite.
# gd:poids_receveur_humidite, mais appliquee a la DEcroissance plutot qu'a
# la montee, et calculee UNE FOIS (permeabilite est immuable) plutot qu'a
# chaque tick.
#
# AUCUN MECANISME DU COEUR TOUCHE : charge.gd/objet.gd restent inchanges.
# Ce fichier est un CABLAGE seul -- aucune donnee partagee touchee non plus
# (permeabilite existe deja sur data/materiaux.json, DORMANTE avant ce
# chantier ; lue ICI A LA DEMANDE, jamais fusionnee via proprietes_
# immuables_composition.json -- meme statut que porosite pour banc_humidite.
# gd, meme raison : cette propriete ne sert qu'a CE chantier, l'ajouter au
# catalogue partage de fusion generique n'apporterait rien).
#
# POURQUOI UN SEUL APPEL A Charge.avancer() POUR TOUT LE MONDE (contrairement
# a banc_humidite.gd, qui appelle Charge.avancer UNE FOIS PAR OBJET) :
# banc_humidite.gd avait besoin d'un poids RECEVEUR different par objet
# (absorption_humidite), une grandeur que charge.gd ne sait pas lire lui-
# meme -- d'ou le contournement (pre-multiplier le poids de la cause).
# taux_decroissance, lui, EST deja une grandeur PROPRE A CHAQUE CANAL que
# charge.gd lit nativement (canal.get("taux_decroissance", 0.0), voir
# charge.gd:_avancer_canal) -- rien a contourner, un seul appel a
# Charge.avancer(objets, causes, delta) suffit, chaque objet decroit selon
# SON PROPRE taux deja ecrit sur SON PROPRE canal a la fabrication.
#
# POURQUOI LE MARQUEUR D'ETAT NE PASSE JAMAIS PAR EtatDuree.poser (contraste
# avec banc_humidite.gd, qui l'utilise pour un sechage PROGRESSIF de
# l'effet sur inflammabilite) : ce banc ne module aucune autre propriete
# (pas d'inflammabilite en jeu ici) -- le marqueur "sature_eau" n'a besoin
# que d'un booleen reversible, exactement ce que charge.gd pose/retire deja
# lui-meme au franchissement du seuil (canal.poser). Ajouter EtatDuree
# par-dessus introduirait un DEUXIEME rythme de sechage, independant de
# taux_decroissance, qui masquerait exactement l'effet que ce banc doit
# montrer -- non fait, deliberement.
#
# CE QU'ON DOIT VOIR : une source d'humidite fixe (clic gauche : bascule
# active/inactive, marqueur au sol) expose en permanence deux objets
# (data/banc_permeabilite.json) qui montent a l'IDENTIQUE tant que la
# source reste active (meme cause, meme poids). Une fois la source coupee,
# "permeable" (bois, permeabilite 0.5) voit sa charge redescendre vite et
# repasse sous le seuil en quelques secondes (sature_eau retire) ;
# "impermeable" (fer, permeabilite 0.0) redescend beaucoup plus lentement
# (taux_decroissance_plancher seul, l'eau reste "piegee") et reste marque
# sature_eau bien apres que "permeable" a seche. Chaque objet affiche sa
# permeabilite, sa charge/seuil, et son etat (sec/sature).
#
# LIMITE STRICTE (rappel explicite du chantier) : ce fichier cable
# UNIQUEMENT ce banc -- aucun mecanisme neuf, aucune extension du coeur,
# aucun banc existant touche. charge.gd/objet.gd sont deja ecrits et
# verts ; ce fichier ne fait que les appeler et lire leurs resultats publics.
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready construit la source et les deux objets
#   (Objet.fabriquer, composition fusionnee). _unhandled_input bascule la
#   source au clic gauche. _process appelle UNIQUEMENT avancer() (fonction
#   statique, ci-dessous) puis lit ses resultats pour l'affichage/la
#   console -- jamais un calcul refait ici (regle CLAUDE.md : la logique
#   enfermee dans _process doit en sortir en fonction statique testable).
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_permeabilite.gd) : causes_de/permeabilite_ponderee/
#   taux_decroissance_permeabilite/avancer/basculer_source/
#   fabriquer_objets/diagnostiquer, plus le texte d'affichage et de log.

const Objet = preload("res://scripts/objet.gd")
const Charge = preload("res://scripts/charge.gd")

const TAILLE := 70.0
const HAUTEUR_BARRE := 10.0
const TAILLE_SOURCE := 30.0

var _config: Dictionary = {}
var _materiaux: Dictionary = {}
var _source: Dictionary = {}
var _objets: Array = []
var _noeuds: Dictionary = {}
var _barres_fond: Dictionary = {}
var _barres_remplies: Dictionary = {}
var _labels: Dictionary = {}
var _noeud_source: ColorRect
var _label_source: Label
var _sature_avant: Dictionary = {}
var _temps: float = 0.0

func _ready() -> void:
	_config = _charger_json("res://data/banc_permeabilite.json")
	_materiaux = _charger_json("res://data/materiaux.json")

	var decl_source: Dictionary = _config.get("source", {})
	var pos_source: Array = decl_source.get("position", [0.0, 0.0, 0.0])
	_source = {
		"id": decl_source.get("id", "source"),
		"position": Vector3(pos_source[0], pos_source[1], pos_source[2]),
		"proprietes": {_config.propriete_cause: true},
	}

	_objets = fabriquer_objets(_config.get("objets", []), _materiaux, _config)
	for objet in _objets:
		_sature_avant[objet.id] = false
		_creer_rendu_objet(objet)

	_creer_rendu_source()
	_poser_camera()

	for objet in _objets:
		var diag := diagnostiquer(objet, _config, _materiaux)
		print(_ligne_pose_initiale(objet.id, diag))
	_rafraichir_tout()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		basculer_source(_source, _config.propriete_cause)
		var actif: bool = _source.proprietes.get(_config.propriete_cause, false)
		print(_ligne_source(_temps, actif))
		_rafraichir_tout()

func _process(delta: float) -> void:
	_temps += delta
	avancer(_objets, _source, delta, _config)

	for objet in _objets:
		var id: String = objet.id
		var sature: bool = objet.proprietes.get(_config.nom_marque, false)
		if sature != _sature_avant.get(id, false):
			var diag := diagnostiquer(objet, _config, _materiaux)
			print(_ligne_sature(_temps, id, sature, diag))
			_sature_avant[id] = sature

	_rafraichir_tout()

func _rafraichir_tout() -> void:
	for objet in _objets:
		var id: String = objet.id
		var diag := diagnostiquer(objet, _config, _materiaux)
		_noeuds[id].color = _teinte_pour_statut(diag.sature)
		var ratio: float = clamp(diag.charge / diag.seuil, 0.0, 1.0) if diag.seuil > 0.0 else 0.0
		_barres_remplies[id].size.x = _barres_fond[id].size.x * ratio
		_labels[id].text = _texte_label(id, diag)
	var actif: bool = _source.proprietes.get(_config.propriete_cause, false)
	_noeud_source.color = Color(0.15, 0.55, 0.95) if actif else Color(0.4, 0.4, 0.4)
	_label_source.text = "source : %s (clic pour basculer)" % ("ACTIVE" if actif else "INACTIVE")

# ---- Fonctions PURES, testables headless (voir test_banc_permeabilite.gd) ----

# Meme geste que banc_humidite.gd:causes_de -- filtre les objets portant
# "propriete_cause" a vrai, rend { position }, poids implicite 1.0 laisse a
# la charge de charge.gd. Local a ce fichier (meme discipline que les
# autres bancs d'humidite : recopiee, jamais partagee).
static func causes_de(objets: Array, propriete_cause: String) -> Array:
	var causes: Array = []
	for chose in objets:
		if chose.proprietes.get(propriete_cause, false):
			causes.append({"position": chose.position})
	return causes

# Voir en-tete. Meme patron que banc_humidite.gd:porosite_ponderee -- moyenne
# ponderee par volume d'une propriete nommee sur la composition de l'objet,
# RECOPIEE LOCALEMENT (jamais un appel a une fonction d'un autre fichier).
# "propriete_permeabilite" vide, objet sans "composition", ou catalogue
# "materiaux" vide : rend 0.0, CHEMIN MORT -- meme contrat que la propriete
# elle-meme quand elle est absente d'une fiche materiau (aucune alarme,
# absence legitime).
static func permeabilite_ponderee(objet: Dictionary, materiaux: Dictionary, propriete_permeabilite: String) -> float:
	if propriete_permeabilite.is_empty() or materiaux.is_empty():
		return 0.0
	var composition: Array = objet.proprietes.get("composition", [])
	if composition.is_empty():
		return 0.0
	var somme_ponderee := 0.0
	var somme_volume := 0.0
	for element in composition:
		var nom_materiau: String = element.get("materiau", "")
		var volume: float = float(element.get("volume", 0.0))
		var fiche: Dictionary = materiaux.get(nom_materiau, {})
		somme_ponderee += float(fiche.get(propriete_permeabilite, 0.0)) * volume
		somme_volume += volume
	if somme_volume <= 0.0:
		return 0.0
	return somme_ponderee / somme_volume

# taux_decroissance = taux_decroissance_plancher + facteur_permeabilite *
# permeabilite -- voir en-tete. Une permeabilite nulle ne rend JAMAIS un
# taux de zero pur : taux_decroissance_plancher (data/banc_permeabilite.
# json, strictement positif) garantit qu'un objet totalement impermeable
# seche quand meme, tres lentement, jamais a vie -- decision de ce chantier,
# voir CARTE.md 3duotrigies.
static func taux_decroissance_permeabilite(permeabilite: float, config: Dictionary) -> float:
	var plancher: float = config.get("taux_decroissance_plancher", 0.0)
	var facteur: float = config.get("facteur_permeabilite", 0.0)
	return plancher + facteur * permeabilite

# UN PAS de simulation complet : un seul appel a Charge.avancer pour tous
# les objets (voir en-tete, POURQUOI UN SEUL APPEL) -- chaque objet monte au
# meme rythme (meme cause, meme poids implicite 1.0) mais decroit selon SON
# PROPRE taux_decroissance, deja ecrit sur son canal a la fabrication. Rend
# l'Array des id ayant franchi le seuil ce pas (meme forme que Charge.
# avancer, jamais recalculee ici).
static func avancer(objets: Array, source: Dictionary, delta: float, config: Dictionary) -> Array:
	var causes := causes_de([source], config.propriete_cause)
	return Charge.avancer(objets, causes, delta)

static func basculer_source(source: Dictionary, propriete_cause: String) -> void:
	source.proprietes[propriete_cause] = not source.proprietes.get(propriete_cause, false)

# Construit les objets cibles via Objet.fabriquer (composition fusionnee --
# meme patron que banc_humidite.gd), puis pose SUR CHAQUE OBJET son propre
# canal de charge avec taux_decroissance CALCULE UNE FOIS depuis sa
# permeabilite (immuable, jamais recalcule a chaque tick -- contrairement
# au poids receveur de banc_humidite.gd, qui doit etre recalcule car il
# depend de la source, pas seulement du receveur).
static func fabriquer_objets(declarations: Array, materiaux: Dictionary, config: Dictionary) -> Array:
	var catalogue: Dictionary = {}
	for decl in declarations:
		catalogue[decl.id] = {"composition": decl.composition}
	var objets: Array = []
	for decl in declarations:
		var pos: Array = decl.position
		var objet := Objet.fabriquer(decl.id, decl.id, Vector3(pos[0], pos[1], pos[2]), catalogue, materiaux)
		var permeabilite := permeabilite_ponderee(objet, materiaux, config.get("propriete_permeabilite", ""))
		var canal: Dictionary = config.canal_defaut.duplicate(true)
		canal["taux_decroissance"] = taux_decroissance_permeabilite(permeabilite, config)
		objet.proprietes["etats"] = {config.nom_canal: canal}
		objets.append(objet)
	return objets

# Diagnostic d'affichage, PUR : lit uniquement des valeurs deja calculees
# par charge.gd/permeabilite_ponderee, ne reimplemente jamais leur loi
# (meme doctrine que banc_humidite.gd:diagnostiquer). Rend
# { permeabilite, taux_decroissance, charge, seuil, sature }.
static func diagnostiquer(objet: Dictionary, config: Dictionary, materiaux: Dictionary) -> Dictionary:
	var canal: Dictionary = objet.proprietes.get("etats", {}).get(config.nom_canal, {})
	var permeabilite := permeabilite_ponderee(objet, materiaux, config.get("propriete_permeabilite", ""))
	return {
		"permeabilite": permeabilite,
		"taux_decroissance": canal.get("taux_decroissance", 0.0),
		"charge": canal.get("charge", 0.0),
		"seuil": canal.get("seuil", 0.0),
		"sature": objet.proprietes.get(config.nom_marque, false),
	}

static func _teinte_pour_statut(sature: bool) -> Color:
	return Color(0.15, 0.35, 0.85) if sature else Color(0.55, 0.42, 0.28)

static func _texte_label(id: String, diag: Dictionary) -> String:
	return "%s\npermeabilite=%.2f\ntaux_decroissance=%.2f\ncharge=%.2f/%.2f\netat=%s" % [
		id, diag.permeabilite, diag.taux_decroissance, diag.charge, diag.seuil,
		"sature" if diag.sature else "sec"
	]

static func _ligne_pose_initiale(id: String, diag: Dictionary) -> String:
	return "t=0.0s %s : permeabilite=%.2f taux_decroissance=%.2f seuil=%.2f" % [
		id, diag.permeabilite, diag.taux_decroissance, diag.seuil
	]

static func _ligne_sature(t: float, id: String, sature: bool, diag: Dictionary) -> String:
	return "t=%.1fs %s : sature_eau %s (charge=%.2f, seuil=%.2f, permeabilite=%.2f, taux_decroissance=%.2f)" % [
		t, id, "POSE" if sature else "RETIRE", diag.charge, diag.seuil, diag.permeabilite, diag.taux_decroissance
	]

static func _ligne_source(t: float, actif: bool) -> String:
	return "t=%.1fs source : %s" % [t, "ACTIVE" if actif else "INACTIVE"]

# ---- Rendu (impur, Node) -- aucune decision, seulement la construction
# des noeuds et la camera.

func _creer_rendu_objet(objet: Dictionary) -> void:
	var id: String = objet.id
	var centre := Vector2(objet.position.x, objet.position.y)

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
	rempli.color = Color(0.2, 0.55, 0.9)
	rempli.size = Vector2(0.0, HAUTEUR_BARRE)
	rempli.position = fond.position
	add_child(rempli)
	_barres_remplies[id] = rempli

	var label := Label.new()
	label.position = centre - Vector2(TAILLE / 2.0, TAILLE / 2.0 + 100.0)
	add_child(label)
	_labels[id] = label

func _creer_rendu_source() -> void:
	var centre := Vector2(_source.position.x, _source.position.y)
	var noeud := ColorRect.new()
	noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noeud.size = Vector2(TAILLE_SOURCE, TAILLE_SOURCE)
	noeud.position = centre - noeud.size / 2.0
	add_child(noeud)
	_noeud_source = noeud

	var label := Label.new()
	label.position = noeud.position - Vector2(20.0, 24.0)
	add_child(label)
	_label_source = label

func _poser_camera() -> void:
	var position_source: Vector3 = _source.position
	var centre_x: float = position_source.x
	for objet in _objets:
		centre_x += objet.position.x
	centre_x /= float(_objets.size() + 1)
	var camera := Camera2D.new()
	camera.position = Vector2(centre_x, 250.0)
	camera.zoom = Vector2(0.8, 0.8)
	camera.enabled = true
	add_child(camera)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
