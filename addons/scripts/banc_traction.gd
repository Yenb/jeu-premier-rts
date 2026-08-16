extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_traction.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1, coexiste avec les autres
# bancs). Chantier « resistance_traction -- rupture par traction », audit
# prealable audit_colonne_mecanique_prealable.md (propriete #4 du tableau
# des quatorze mecaniques : DORMANTE, aucun mecanisme candidat avant ce
# chantier). "resistance_traction" (data/materiaux.json, bois 90.0/pierre
# 5.0/fer 250.0, presente depuis la creation du catalogue) rejoint enfin
# data/proprietes_immuables_composition.json (voir CARTE.md §4) -- avant ce
# chantier, aucun objet fabrique par composition ne portait jamais
# proprietes.resistance_traction.
#
# AUCUN MECANISME DU COEUR TOUCHE : seuil_etat.gd/frappe.gd/etat_effectif.gd/
# charge.gd/objet.gd restent inchanges. Ce fichier COMPOSE deux patrons deja
# fermes, jamais reecrits :
# - ACCUMULATION CONTINUE tant qu'une force reste active, MEME IDIOME que
#   banc_fracture_sonore.gd:avancer_exposition -- "force_traction_cumulee"
#   monte de config.force_valeur * delta a CHAQUE tick ou la force est
#   active, ECRITE PAR CE FICHIER DIRECTEMENT (aucun mecanisme du coeur ne
#   connait cette propriete, elle n'existe QUE parce que ce cablage
#   l'ecrit lui-meme, meme statut que degats_impact_cumules/
#   intensite_sonore_cumulee). GATE STRICTE sur force_active (chemin mort
#   strict, meme garde que banc_fracture_sonore.gd:avancer_exposition) :
#   force coupee, force_traction_cumulee ne bouge JAMAIS -- c'est ce qui
#   garantit "sans force rien ne casse".
# - SeuilEtat.avancer (INCHANGE) -- compare force_traction_cumulee a
#   resistance_traction (seuil_propriete, fusionnee a la fabrication) via
#   une NOUVELLE entree PARTAGEE de data/seuils_etat.json ("traction"),
#   pose l'etat "rompu" (data/etats.json, NEUF, ecrase resistance_traction
#   a 0.0, IRREVERSIBLE -- meme famille que "fracture", voir data/
#   etats.json). Catalogue PARTAGE passe TEL QUEL (les entrees thermiques/
#   fracture y cohabitent, jamais declenchees ici -- aucune source de
#   temperature ni de choc dans ce banc).
#
# CHUTE APRES RUPTURE (aucune physique Godot, aucun RigidBody -- un calcul
# de position par tick, cable a la main, MEME CONVENTION DE HAUTEUR que
# banc_restitution.gd : position.z porte la hauteur, rendu a l'ecran par
# centre = Vector2(x, y - z)) : l'etat "rompu" LUI-MEME est le declencheur,
# aucun flag separe -- un objet qui porte "rompu" dans etats_actifs et n'a
# pas encore "tombe" integre une gravite constante (v -= gravite*delta,
# z += v*delta, MEME formule que banc_restitution.gd:avancer, mais SANS
# rebond -- un lien rompu tombe et reste au sol, jamais de rebond) jusqu'a
# toucher le sol (z <= 0.0), ou il s'arrete pour de bon ("tombe": true).
#
# CE QU'ON DOIT VOIR : trois objets fabriques (bois/pierre/fer, un materiau
# reel chacun, Objet.fabriquer/composition/materiaux.json -- jamais
# construits a la main), suspendus a un point fixe dessine au-dessus de
# chacun (ancrage, purement visuel, meme patron que les ancrages de
# banc_rigidite.gd). AUCUNE force au demarrage ; un clic gauche BASCULE une
# force de traction identique sur LES TROIS A LA FOIS (meme geste que
# banc_friction.gd:basculer_mouille/banc_rigidite.gd:basculer_charge). La
# pierre (resistance_traction 5.0) rompt tres vite, le bois (90.0) resiste
# bien plus longtemps, le fer (250.0) resiste le plus -- avec les valeurs
# de demonstration (force_valeur 8.0), la pierre rompt en ~0.6s, le bois
# en ~11s, le fer resiste au-dela de la duree d'observation habituelle
# (>30s). Des qu'un objet rompt, son lien avec l'ancrage disparait (rendu
# seul) et il tombe -- une fois au sol, il y reste, "rompu" ne se retire
# jamais. Label par objet : resistance_traction, force_traction_cumulee,
# etat rompu ou non. Trace console : une ligne a chaque bascule de force, a
# chaque rupture, a chaque atterrissage.
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge les donnees/catalogues et fabrique les
#   trois objets (Objet.fabriquer, INCHANGE). _unhandled_input bascule la
#   force au clic gauche. _process appelle UNIQUEMENT avancer_force/
#   avancer_rupture/avancer_chute (fonctions statiques, ci-dessous) puis
#   lit leurs resultats pour l'affichage/la console -- jamais un calcul
#   refait ici.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_traction.gd) : fabriquer_objets/basculer_force/avancer_force/
#   avancer_rupture/est_rompu/avancer_chute/diagnostiquer, plus le texte
#   d'affichage et de log.

const Objet = preload("res://scripts/objet.gd")
const SeuilEtat = preload("res://scripts/seuil_etat.gd")

const PROPRIETE_RESISTANCE := "resistance_traction"
const TAILLE := 50.0
const TAILLE_ANCRAGE := 16.0

const COULEURS_MATERIAU := {
	"bois": Color(0.55, 0.42, 0.28),
	"pierre": Color(0.5, 0.5, 0.55),
	"fer": Color(0.65, 0.68, 0.72),
}
const COULEUR_ROMPU := Color(0.7, 0.2, 0.15)
const COULEUR_ANCRAGE := Color(0.35, 0.35, 0.38)

var _config: Dictionary = {}
var _materiaux: Dictionary = {}
var _catalogue_seuils_etat: Dictionary = {}
var _hauteur_suspension := 0.0
var _force_valeur := 0.0
var _gravite := 900.0
var _force_active := false
var _objets: Array = []
var _couleurs: Dictionary = {}
var _noeuds: Dictionary = {}
var _ancrages: Dictionary = {}
var _labels: Dictionary = {}
var _rompu_avant: Dictionary = {}
var _temps := 0.0

func _ready() -> void:
	_config = _charger_json("res://data/banc_traction.json")
	_materiaux = _charger_json("res://data/materiaux.json")
	var proprietes_immuables: Array = _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", [])
	_catalogue_seuils_etat = _charger_json("res://data/seuils_etat.json")

	_hauteur_suspension = _config.get("hauteur_suspension", 250.0)
	_force_valeur = _config.get("force_valeur", 0.0)
	_gravite = _config.get("gravite", 900.0)

	_objets = fabriquer_objets(_config.get("objets", []), _materiaux, proprietes_immuables, _hauteur_suspension)
	for decl in _config.get("objets", []):
		var nom_materiau: String = decl.composition[0].materiau
		_couleurs[decl.id] = COULEURS_MATERIAU.get(nom_materiau, Color(0.8, 0.8, 0.8))

	for objet in _objets:
		_rompu_avant[objet.id] = false
		_creer_rendu_objet(objet)
	_rafraichir_tout()
	_poser_camera()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_force_active = basculer_force(_force_active)
		print(ligne_force(_temps, _force_active))
		_rafraichir_tout()

func _process(delta: float) -> void:
	_temps += delta
	avancer_force(_objets, _force_active, _force_valeur, delta)
	var bascules := avancer_rupture(_objets, _catalogue_seuils_etat)
	for id in bascules:
		if not est_rompu(_objet_par_id(id)) or _rompu_avant.get(id, false):
			continue
		_rompu_avant[id] = true
		print(ligne_rupture(_temps, id, diagnostiquer(_objet_par_id(id))))
	var atterris := avancer_chute(_objets, _gravite, delta)
	for id in atterris:
		print(ligne_atterrissage(_temps, id))
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
		var centre := Vector2(objet.position.x, objet.position.y - objet.position.z)
		_noeuds[id].position = centre - _noeuds[id].size / 2.0
		_noeuds[id].color = COULEUR_ROMPU if diag.rompu else _couleurs.get(id, Color(0.8, 0.8, 0.8))
		_ancrages[id].visible = not diag.rompu
		_labels[id].position = centre - Vector2(TAILLE / 2.0, TAILLE / 2.0 + 60.0)
		_labels[id].text = texte_objet(id, diag)

# ---- Fonctions PURES, testables headless (voir test_banc_traction.gd) ----

# Construit les trois objets via Objet.fabriquer (composition fusionnee --
# meme patron que banc_rigidite.gd/banc_restitution.gd, catalogue LOCAL a
# une entree par id), suspendus a hauteur_suspension. Ajoute A LA MAIN
# (Objet.fabriquer ne les connait pas) : "force_traction_cumulee" (0.0, la
# grandeur que scripts/seuil_etat.gd va comparer -- SANS elle,
# proprietes.has() rendrait faux et l'entree "traction" ne se
# declencherait jamais), "etats_actifs" (Array vide, structurelle),
# "tombe" (faux, marque l'atterrissage definitif), "vitesse_chute" (0.0).
static func fabriquer_objets(declarations: Array, materiaux: Dictionary, proprietes_immuables: Array, hauteur_suspension: float) -> Array:
	var catalogue: Dictionary = {}
	for decl in declarations:
		catalogue[decl.id] = {"composition": decl.composition}
	var objets: Array = []
	for decl in declarations:
		var pos: Array = decl.position
		var objet := Objet.fabriquer(decl.id, decl.id, Vector3(pos[0], pos[1], hauteur_suspension), catalogue, materiaux, proprietes_immuables)
		if objet.is_empty():
			continue
		objet.proprietes["force_traction_cumulee"] = 0.0
		objet.proprietes["etats_actifs"] = []
		objet.proprietes["tombe"] = false
		objet.proprietes["vitesse_chute"] = 0.0
		objets.append(objet)
	return objets

static func basculer_force(actif: bool) -> bool:
	return not actif

# ACCUMULATION AVEC DELTA, MEME IDIOME que banc_fracture_sonore.gd:
# avancer_exposition -- force_traction_cumulee monte de force_valeur*delta
# a CHAQUE tick ou la force est active, jamais un montant fixe par tick
# (independant du framerate). GATE STRICTE sur force_active : force coupee,
# CHEMIN MORT STRICT, force_traction_cumulee ne bouge JAMAIS quel que soit
# force_valeur -- garantit "sans force rien ne casse". MUTE EN PLACE.
static func avancer_force(objets: Array, force_active: bool, force_valeur: float, delta: float) -> void:
	if not force_active:
		return
	for objet in objets:
		var cumul: float = objet.proprietes.get("force_traction_cumulee", 0.0)
		objet.proprietes["force_traction_cumulee"] = cumul + force_valeur * delta

# SeuilEtat.avancer (INCHANGE) sur le catalogue PARTAGE, TEL QUEL -- rend
# l'Array des id ayant vu un etat basculer ce passage (meme contrat que
# SeuilEtat.avancer).
static func avancer_rupture(objets: Array, catalogue_seuils_etat: Dictionary) -> Array:
	return SeuilEtat.avancer(objets, catalogue_seuils_etat)

static func est_rompu(objet: Dictionary) -> bool:
	return objet.get("proprietes", {}).get("etats_actifs", []).has("rompu")

# UN PAS de chute pour tout objet ROMPU pas encore au sol -- "rompu" LUI-
# MEME est le declencheur (aucun flag "en_chute" separe, contrairement a
# banc_restitution.gd : ici la chute est IRREVERSIBLE, jamais relachee/
# reinitialisee par un clic). Meme integration que banc_restitution.gd:
# avancer (v -= gravite*delta, z += v*delta) mais SANS rebond -- un lien
# rompu ne rebondit jamais, il touche le sol et y reste ("tombe": true).
# Rend les ids qui ont touche le sol CE TICK (pour une ligne de log par
# atterrissage, jamais par tick). MUTE EN PLACE.
static func avancer_chute(objets: Array, gravite: float, delta: float) -> Array:
	var atterris: Array = []
	for objet in objets:
		if not est_rompu(objet):
			continue
		if objet.proprietes.get("tombe", false):
			continue
		var vitesse: float = objet.proprietes.get("vitesse_chute", 0.0)
		var z: float = objet.position.z
		vitesse -= gravite * delta
		z += vitesse * delta
		if z <= 0.0:
			z = 0.0
			vitesse = 0.0
			objet.proprietes["tombe"] = true
			atterris.append(objet.id)
		objet.position.z = z
		objet.proprietes["vitesse_chute"] = vitesse
	return atterris

# Diagnostic d'affichage, PUR : lit uniquement des valeurs deja posees,
# jamais recalculees. Rend { resistance_traction, force_traction_cumulee,
# rompu, hauteur, tombe }.
static func diagnostiquer(objet: Dictionary) -> Dictionary:
	var proprietes: Dictionary = objet.get("proprietes", {})
	return {
		"resistance_traction": proprietes.get(PROPRIETE_RESISTANCE, 0.0),
		"force_traction_cumulee": proprietes.get("force_traction_cumulee", 0.0),
		"rompu": est_rompu(objet),
		"hauteur": objet.get("position", Vector3.ZERO).z,
		"tombe": proprietes.get("tombe", false),
	}

static func texte_objet(id: String, diag: Dictionary) -> String:
	return "%s\nresistance_traction = %.1f\nforce_cumulee = %.2f\netat = %s" % [
		id, diag.resistance_traction, diag.force_traction_cumulee,
		"rompu" if diag.rompu else "intact"
	]

static func ligne_force(t: float, actif: bool) -> String:
	return "t=%.1fs force de traction : %s (les trois objets)" % [t, "POSEE" if actif else "RETIREE"]

static func ligne_rupture(t: float, id: String, diag: Dictionary) -> String:
	return "t=%.1fs %s : ROMPU (force cumulee = %.2f, resistance_traction = %.1f)" % [t, id, diag.force_traction_cumulee, diag.resistance_traction]

static func ligne_atterrissage(t: float, id: String) -> String:
	return "t=%.1fs %s : touche le sol" % [t, id]

# ---- Rendu (impur, Node) -- aucune decision, seulement la construction
# des noeuds et la camera.

func _creer_rendu_objet(objet: Dictionary) -> void:
	var id: String = objet.id

	var ancrage := ColorRect.new()
	ancrage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ancrage.size = Vector2(TAILLE_ANCRAGE, TAILLE_ANCRAGE)
	ancrage.color = COULEUR_ANCRAGE
	ancrage.position = Vector2(objet.position.x - TAILLE_ANCRAGE / 2.0, objet.position.y - _hauteur_suspension - TAILLE_ANCRAGE)
	add_child(ancrage)
	_ancrages[id] = ancrage

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
