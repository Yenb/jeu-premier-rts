extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_transformation_produit.tscn,
# PAS la scene principale -- run/main_scene reste banc_p1). PREMIERE
# demonstration reelle du chantier "transformation produit un objet neuf" :
# scripts/produit.gd (masse derivee d'un rendement) et l'extension
# correspondante de scripts/extinction.gd (a_zero.produire) jouant en jeu
# pour la premiere fois, en chaine (bois -> charbon -> cendre, deux
# maillons d'affilee).
#
# CE QU'ON DOIT VOIR : un seul objet, deja en combustion au demarrage
# (aucun clic, aucune propagation -- ce banc observe la CHAINE DE
# PRODUITS, pas l'allumage, meme parti pris que banc_combustible.gd).
# Son carre change de couleur a chaque etape (bois -> charbon -> cendre,
# data/banc_transformation_produit.json:couleurs). Un Label affiche EN
# PERMANENCE le materiau actuel, sa masse, et le rendement qui l'a
# produit ("origine" pour le bois, jamais produit par rien). La console
# imprime une ligne a la pose initiale puis une ligne PAR TRANSITION
# (jamais par tick) : materiau avant/apres, rendement applique, masse
# avant/apres -- verifie a l'oeil que la masse decroit exactement selon
# le rendement documente dans data/transformations.json (0.30 puis
# 0.05).
#
# L'AGENT DE COMBUSTION (rythme_combustion, donnee) n'est PAS un colon --
# extinction.gd exige des agents A PORTEE (jamais l'auto-consommation,
# reservee a depense.gd, explicitement hors perimetre de ce chantier) :
# ce banc fournit un point {position, rythme} colle a l'objet, qui
# represente la combustion se mangeant elle-meme, sans dependre de
# depense.gd ni de propagation.gd. Sa position ne bouge JAMAIS -- le
# produit herite toujours la position de l'ancien objet (scripts/
# produit.gd ne touche jamais position/id), l'agent reste donc valide
# pour toute la chaine sans recalcul.
#
# LIMITE STRICTE (rappel explicite du chantier) : ce fichier cable
# UNIQUEMENT ce banc -- aucun mecanisme neuf, aucune extension du coeur
# au-dela de ce que produit.gd/extinction.gd portent deja. depense.gd/
# propagation.gd/perception.gd/champ.gd/charge.gd/vent.gd/temperature.gd
# non touches, aucun autre banc retouche.

const Objet = preload("res://scripts/objet.gd")
const Extinction = preload("res://scripts/extinction.gd")

const TAILLE := 80.0

var _monde: Array = []
var _agents: Array = []
var _transformations: Dictionary = {}
var _catalogue_types: Dictionary = {}
var _materiaux: Dictionary = {}
var _couleurs: Dictionary = {}
var _rendements: Dictionary = {}

var _noeud: ColorRect
var _label: Label
var _dernier_materiau: String = ""
var _derniere_masse: float = 0.0
var _temps: float = 0.0

func _ready() -> void:
	_catalogue_types = _charger_json("res://data/types.json")
	_materiaux = _charger_json("res://data/materiaux.json")
	_transformations = _charger_json("res://data/transformations.json").get("transformations", {})
	var donnees := _charger_json("res://data/banc_transformation_produit.json")
	_couleurs = donnees.get("couleurs", {})
	_rendements = _rendements_par_produit(_transformations)

	var decl: Dictionary = donnees.objet
	var pos_arr: Array = decl.position
	var pos := Vector3(pos_arr[0], pos_arr[1], pos_arr[2])

	# Type transitoire propre a l'objet de depart (meme patron que
	# banc_combustible.gd) -- ajoute a la MEME table que celle transmise a
	# Extinction.avancer plus bas, pour que "charbon"/"cendre" (deja dans
	# data/types.json) restent resolubles sans une seconde table.
	_catalogue_types[decl.id] = {"composition": decl.composition}

	var objet := Objet.fabriquer(decl.id, decl.id, pos, _catalogue_types, _materiaux)
	if objet.is_empty():
		push_error("banc_transformation_produit.gd : fabrication refusee pour '%s'" % decl.id)
		return
	objet.proprietes["brule"] = true
	objet.proprietes["travail_restant"] = donnees.travail_restant_initial
	objet.proprietes["travail_initial"] = donnees.travail_initial_initial
	objet.proprietes["transformation"] = donnees.transformation_initiale
	_monde = [objet]
	_agents = [{"position": pos, "rythme": donnees.rythme_combustion}]

	_dernier_materiau = _materiau_actuel(objet.proprietes)
	_derniere_masse = objet.proprietes.masse

	_creer_rendu(objet)
	_poser_camera(pos)

	print(_ligne_pose(0.0, _dernier_materiau, _derniere_masse))
	_rafraichir()

func _process(delta: float) -> void:
	if _monde.is_empty():
		return
	_temps += delta
	Extinction.avancer(_monde, _agents, delta, _transformations, _catalogue_types, _materiaux)

	var proprietes: Dictionary = _monde[0].proprietes
	var materiau: String = _materiau_actuel(proprietes)
	if materiau != _dernier_materiau:
		var masse: float = proprietes.get("masse", 0.0)
		var rendement = _rendements.get(materiau, null)
		print(_ligne_transition(_temps, _dernier_materiau, materiau, rendement, _derniere_masse, masse))
		_dernier_materiau = materiau
		_derniere_masse = masse

	_rafraichir()

# ---- Fonctions PURES, testables -- lisent proprietes deja calculees par
# objet.gd/produit.gd/extinction.gd, ne reimplementent jamais leur loi.

static func _materiau_actuel(proprietes: Dictionary) -> String:
	var composition: Array = proprietes.get("composition", [])
	if composition.is_empty():
		return ""
	return String(composition[0].get("materiau", ""))

# Scanne le catalogue de transformations et rend, pour chaque type_produit
# declare sous a_zero.produire, le rendement qui le produit -- aucun nom
# de materiau en dur, purement derive de la donnee (data/
# transformations.json). "bois" n'y figure jamais (rien ne le produit,
# c'est l'origine de la chaine).
static func _rendements_par_produit(transformations: Dictionary) -> Dictionary:
	var rendements: Dictionary = {}
	for cle in transformations:
		var produire: Dictionary = transformations[cle].get("a_zero", {}).get("produire", {})
		if produire.has("type_produit") and produire.has("rendement"):
			rendements[String(produire.type_produit)] = float(produire.rendement)
	return rendements

static func _texte_rendement(rendement) -> String:
	if rendement == null:
		return "origine"
	return "%.0f%%" % (float(rendement) * 100.0)

static func _texte_label(materiau: String, masse: float, rendement) -> String:
	return "%s\nmasse=%.2f\nrendement applique=%s" % [materiau, masse, _texte_rendement(rendement)]

static func _ligne_pose(t: float, materiau: String, masse: float) -> String:
	return "t=%.1fs : %s en combustion, masse=%.2f" % [t, materiau, masse]

static func _ligne_transition(t: float, materiau_avant: String, materiau_apres: String, rendement, masse_avant: float, masse_apres: float) -> String:
	return "t=%.1fs : %s -> %s (rendement %s, masse %.2f -> %.2f)" % [
		t, materiau_avant, materiau_apres, _texte_rendement(rendement), masse_avant, masse_apres]

static func _couleur_pour_materiau(materiau: String, couleurs: Dictionary) -> Color:
	var rgb: Array = couleurs.get(materiau, [1.0, 1.0, 1.0])
	return Color(rgb[0], rgb[1], rgb[2])

# ---- Rendu (impur, Node) -- aucune decision, seulement la construction
# des noeuds, la camera et le rafraichissement.

func _creer_rendu(objet: Dictionary) -> void:
	var centre := Vector2(objet.position.x, objet.position.y)

	_noeud = ColorRect.new()
	_noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_noeud.size = Vector2(TAILLE, TAILLE)
	_noeud.position = centre - _noeud.size / 2.0
	add_child(_noeud)

	_label = Label.new()
	_label.position = centre - Vector2(TAILLE / 2.0, TAILLE / 2.0 + 70.0)
	add_child(_label)

func _poser_camera(pos: Vector3) -> void:
	var camera := Camera2D.new()
	camera.position = Vector2(pos.x, pos.y)
	camera.zoom = Vector2(1.2, 1.2)
	camera.enabled = true
	add_child(camera)

func _rafraichir() -> void:
	var proprietes: Dictionary = _monde[0].proprietes
	var materiau: String = _materiau_actuel(proprietes)
	var masse: float = proprietes.get("masse", 0.0)
	var rendement = _rendements.get(materiau, null)
	_noeud.color = _couleur_pour_materiau(materiau, _couleurs)
	_label.text = _texte_label(materiau, masse, rendement)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
