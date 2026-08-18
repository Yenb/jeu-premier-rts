extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_acide.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1, coexiste avec les autres
# bancs). Chantier « resistance_acide -- corrosion par acide », audit
# prealable audit_colonnes_chimique_nucleaire_magie_prealable.md (colonne
# chimique, propriete #2 : DORMANTE, aucun mecanisme candidat avant ce
# chantier -- candidat identifie : meme patron que resistance_traction/
# resistance_impact, un nouveau seuil dans data/seuils_etat.json contre
# une grandeur cumulee ecrite par le banc, seuil_etat.gd inchange).
# "resistance_acide" (data/materiaux.json, bois 0.5/pierre 0.3/fer 0.1,
# presente depuis la creation du catalogue) rejoint enfin data/
# proprietes_immuables_composition.json (voir CARTE.md §4) -- avant ce
# chantier, aucun objet fabrique par composition ne portait jamais
# proprietes.resistance_acide.
#
# AUCUN MECANISME DU COEUR TOUCHE : seuil_etat.gd/etat_effectif.gd/
# objet.gd restent inchanges. Ce fichier COMPOSE deux patrons deja fermes,
# jamais reecrits :
# - ACCUMULATION CONTINUE tant qu'une source reste active, MEME IDIOME que
#   banc_fracture_sonore.gd:avancer_exposition / banc_traction.gd:
#   avancer_force -- "exposition_acide_cumulee" monte de config.
#   exposition_valeur * delta a CHAQUE tick ou la source est active,
#   ECRITE PAR CE FICHIER DIRECTEMENT (aucun mecanisme du coeur ne connait
#   cette propriete, elle n'existe QUE parce que ce cablage l'ecrit
#   lui-meme, meme statut que degats_impact_cumules/
#   intensite_sonore_cumulee/force_traction_cumulee). GATE STRICTE sur
#   source_active (chemin mort strict, meme garde que
#   banc_fracture_sonore.gd:avancer_exposition) : source coupee,
#   exposition_acide_cumulee ne bouge JAMAIS -- garantit "sans acide rien
#   ne corrode".
# - SeuilEtat.avancer (INCHANGE) -- compare exposition_acide_cumulee a
#   resistance_acide (seuil_propriete, fusionnee a la fabrication) via une
#   NOUVELLE entree de data/seuils_etat.json ("acide"), pose l'etat
#   "corrode_acide" (data/etats.json, NEUF, MODULE durete et
#   resistance_impact par 0.4 -- meme famille que "fracture"/"corrode",
#   voir data/etats.json). IRREVERSIBLE, comme "fracture"/"rompu" :
#   exposition_acide_cumulee ne redescend jamais, aucun "duree"
#   necessaire. Catalogue PARTAGE passe TEL QUEL (les entrees thermiques/
#   fracture/traction y cohabitent, jamais declenchees ici).
#
# CE QU'ON DOIT VOIR : trois objets fabriques (bois/pierre/fer, un
# materiau reel chacun, Objet.fabriquer/composition/materiaux.json --
# jamais construits a la main), cote a cote. AUCUNE exposition au
# demarrage ; un clic gauche BASCULE une source d'acide identique sur LES
# TROIS A LA FOIS (meme geste que banc_traction.gd:basculer_force). Avec
# les valeurs de demonstration (exposition_valeur 0.05), le fer
# (resistance_acide 0.1) corrode vers t=2s, la pierre (0.3) vers t=6s, le
# bois (0.5) vers t=10s -- le fer cede en premier, le bois resiste le plus
# longtemps, la pierre entre les deux. Un objet corrode change de couleur
# et le reste pour toujours (etat irreversible, jamais retire). Label par
# objet : resistance_acide, exposition_acide_cumulee, etat corrode_acide
# ou non. Trace console : une ligne a chaque bascule de source, a chaque
# corrosion.
#
# Deux moities, meme decoupage que banc_traction.gd :
# - Node (impur) : _ready charge les donnees/catalogues et fabrique les
#   trois objets (Objet.fabriquer, INCHANGE). _unhandled_input bascule la
#   source au clic gauche. _process appelle UNIQUEMENT
#   avancer_exposition/avancer_corrosion (fonctions statiques, ci-dessous)
#   puis lit leurs resultats pour l'affichage/la console -- jamais un
#   calcul refait ici.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_acide.gd) : fabriquer_objets/basculer_source/
#   avancer_exposition/avancer_corrosion/est_corrode/diagnostiquer, plus
#   le texte d'affichage et de log.

const Objet = preload("res://scripts/objet.gd")
const SeuilEtat = preload("res://scripts/seuil_etat.gd")

const PROPRIETE_RESISTANCE := "resistance_acide"
const ETAT_CORRODE := "corrode_acide"
const TAILLE := 50.0

const COULEURS_MATERIAU := {
	"bois": Color(0.55, 0.42, 0.28),
	"pierre": Color(0.5, 0.5, 0.55),
	"fer": Color(0.65, 0.68, 0.72),
}
const COULEUR_CORRODE := Color(0.55, 0.5, 0.15)

var _config: Dictionary = {}
var _materiaux: Dictionary = {}
var _catalogue_seuils_etat: Dictionary = {}
var _exposition_valeur := 0.0
var _source_active := false
var _objets: Array = []
var _couleurs: Dictionary = {}
var _noeuds: Dictionary = {}
var _labels: Dictionary = {}
var _corrode_avant: Dictionary = {}
var _temps := 0.0

func _ready() -> void:
	_config = _charger_json("res://data/banc_acide.json")
	_materiaux = _charger_json("res://data/materiaux.json")
	var proprietes_immuables: Array = _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", [])
	_catalogue_seuils_etat = _charger_json("res://data/seuils_etat.json")

	_exposition_valeur = _config.get("exposition_valeur", 0.0)

	_objets = fabriquer_objets(_config.get("objets", []), _materiaux, proprietes_immuables)
	for decl in _config.get("objets", []):
		var nom_materiau: String = decl.composition[0].materiau
		_couleurs[decl.id] = COULEURS_MATERIAU.get(nom_materiau, Color(0.8, 0.8, 0.8))

	for objet in _objets:
		_corrode_avant[objet.id] = false
		_creer_rendu_objet(objet)
	_rafraichir_tout()
	_poser_camera()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_source_active = basculer_source(_source_active)
		print(ligne_source(_temps, _source_active))
		_rafraichir_tout()

func _process(delta: float) -> void:
	_temps += delta
	avancer_exposition(_objets, _source_active, _exposition_valeur, delta)
	var bascules := avancer_corrosion(_objets, _catalogue_seuils_etat)
	for id in bascules:
		if not est_corrode(_objet_par_id(id)) or _corrode_avant.get(id, false):
			continue
		_corrode_avant[id] = true
		print(ligne_corrosion(_temps, id, diagnostiquer(_objet_par_id(id))))
	_rafraichir_tout()

func _objet_par_id(id: String) -> Dictionary:
	for objet in _objets:
		if objet.id == id:
			return objet
	return {}

func _rafraichir_tout() -> void:
	for objet in _objets:
		var id: String = objet.id
		var diag := diagnostiquer(objet)
		var centre := Vector2(objet.position.x, objet.position.y)
		_noeuds[id].position = centre - _noeuds[id].size / 2.0
		_noeuds[id].color = COULEUR_CORRODE if diag.corrode else _couleurs.get(id, Color(0.8, 0.8, 0.8))
		_labels[id].position = centre - Vector2(TAILLE / 2.0, TAILLE / 2.0 + 60.0)
		_labels[id].text = texte_objet(id, diag)

# ---- Fonctions PURES, testables headless (voir test_banc_acide.gd) ----

# Construit les trois objets via Objet.fabriquer (composition fusionnee --
# meme patron que banc_traction.gd, catalogue LOCAL a une entree par id).
# Ajoute A LA MAIN (Objet.fabriquer ne les connait pas) :
# "exposition_acide_cumulee" (0.0, la grandeur que scripts/seuil_etat.gd
# va comparer -- SANS elle, proprietes.has() rendrait faux et l'entree
# "acide" ne se declencherait jamais), "etats_actifs" (Array vide,
# structurelle).
static func fabriquer_objets(declarations: Array, materiaux: Dictionary, proprietes_immuables: Array) -> Array:
	var catalogue: Dictionary = {}
	for decl in declarations:
		catalogue[decl.id] = {"composition": decl.composition}
	var objets: Array = []
	for decl in declarations:
		var pos: Array = decl.position
		var objet := Objet.fabriquer(decl.id, decl.id, Vector3(pos[0], pos[1], 0.0), catalogue, materiaux, proprietes_immuables)
		if objet.is_empty():
			continue
		objet.proprietes["exposition_acide_cumulee"] = 0.0
		objet.proprietes["etats_actifs"] = []
		objets.append(objet)
	return objets

static func basculer_source(actif: bool) -> bool:
	return not actif

# ACCUMULATION AVEC DELTA, MEME IDIOME que banc_fracture_sonore.gd:
# avancer_exposition / banc_traction.gd:avancer_force --
# exposition_acide_cumulee monte de exposition_valeur*delta a CHAQUE tick
# ou la source est active, jamais un montant fixe par tick (independant
# du framerate). GATE STRICTE sur source_active : source coupee, CHEMIN
# MORT STRICT, exposition_acide_cumulee ne bouge JAMAIS quel que soit
# exposition_valeur -- garantit "sans acide rien ne corrode". MUTE EN
# PLACE.
static func avancer_exposition(objets: Array, source_active: bool, exposition_valeur: float, delta: float) -> void:
	if not source_active:
		return
	for objet in objets:
		var cumul: float = objet.proprietes.get("exposition_acide_cumulee", 0.0)
		objet.proprietes["exposition_acide_cumulee"] = cumul + exposition_valeur * delta

# SeuilEtat.avancer (INCHANGE) sur le catalogue PARTAGE, TEL QUEL -- rend
# l'Array des id ayant vu un etat basculer ce passage (meme contrat que
# SeuilEtat.avancer).
static func avancer_corrosion(objets: Array, catalogue_seuils_etat: Dictionary) -> Array:
	return SeuilEtat.avancer(objets, catalogue_seuils_etat)

static func est_corrode(objet: Dictionary) -> bool:
	return objet.get("proprietes", {}).get("etats_actifs", []).has(ETAT_CORRODE)

# Diagnostic d'affichage, PUR : lit uniquement des valeurs deja posees,
# jamais recalculees. Rend { resistance_acide, exposition_acide_cumulee,
# corrode }.
static func diagnostiquer(objet: Dictionary) -> Dictionary:
	var proprietes: Dictionary = objet.get("proprietes", {})
	return {
		"resistance_acide": proprietes.get(PROPRIETE_RESISTANCE, 0.0),
		"exposition_acide_cumulee": proprietes.get("exposition_acide_cumulee", 0.0),
		"corrode": est_corrode(objet),
	}

static func texte_objet(id: String, diag: Dictionary) -> String:
	return "%s\nresistance_acide = %.2f\nexposition_cumulee = %.3f\netat = %s" % [
		id, diag.resistance_acide, diag.exposition_acide_cumulee,
		"corrode_acide" if diag.corrode else "intact"
	]

static func ligne_source(t: float, actif: bool) -> String:
	return "t=%.1fs source d'acide : %s (les trois objets)" % [t, "POSEE" if actif else "RETIREE"]

static func ligne_corrosion(t: float, id: String, diag: Dictionary) -> String:
	return "t=%.1fs %s : CORRODE (exposition cumulee = %.3f, resistance_acide = %.2f)" % [t, id, diag.exposition_acide_cumulee, diag.resistance_acide]

# ---- Rendu (impur, Node) -- aucune decision, seulement la construction
# des noeuds et la camera.

func _creer_rendu_objet(objet: Dictionary) -> void:
	var id: String = objet.id

	var noeud := ColorRect.new()
	noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noeud.size = Vector2(TAILLE, TAILLE)
	add_child(noeud)
	_noeuds[id] = noeud

	var label := Label.new()
	add_child(label)
	_labels[id] = label

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
