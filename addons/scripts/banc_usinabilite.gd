extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_usinabilite.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1, coexiste avec les autres
# bancs). Chantier « usinabilite -- temps de fabrication par materiau » :
# "usinabilite" (data/materiaux.json, bois 0.8/pierre 0.3/fer 0.5, DORMANTE
# depuis la creation du catalogue -- voir audit_colonne_mecanique_
# prealable.md, propriete #11, aucun mecanisme de fabrication/artisanat dans
# le depot avant ce chantier) rejoint enfin data/proprietes_immuables_
# composition.json (voir CARTE.md §4).
#
# AUCUN MECANISME DU COEUR TOUCHE : depense.gd/etat_effectif.gd/objet.gd
# restent inchanges. Ce banc REUTILISE depense.gd (scripts/depense.gd) tel
# quel -- un colon simule le GESTE de fabrication : une reserve nommee
# "travail" (dans proprietes.reserves) descend a un cout_base EFFECTIF,
# calcule UNE FOIS a la fabrication depuis l'usinabilite du materiau.
#
# CE QU'ON DOIT VOIR : trois objets fabriques (bois/pierre/fer, un materiau
# reel chacun), chacun avec un "travail_restant" identique au depart. Un
# clic gauche BASCULE la fabrication des trois A LA FOIS (rien ne descend
# avant le premier clic, contrairement a banc_friction.gd qui glisse des
# t=0) -- Depense.avancer (jamais reimplemente) consomme alors la reserve
# "travail" de chacun a son cout_effectif = cout_base_reference *
# usinabilite_effective (EtatEffectif.valeur, jamais reimplementee) : le
# bois (usinabilite 0.8, le plus facile a travailler) descend le plus vite,
# le fer (0.5) au milieu, la pierre (0.3) le plus lentement -- le bois finit
# donc en premier, le fer ensuite, la pierre en dernier. depense.gd borne
# deja "reserve" a 0.0 (jamais negative) -- un objet dont le travail est
# fini reste "fabrique" (label/couleur qui changent, ligne console) meme si
# la fabrication reste active.
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge les donnees et fabrique les trois objets
#   (Objet.fabriquer, composition fusionnee -- meme patron que
#   banc_friction.gd/banc_rigidite.gd). _unhandled_input bascule la
#   fabrication au clic gauche. _process appelle UNIQUEMENT avancer()
#   (fonction statique, ci-dessous) puis lit ses resultats pour
#   l'affichage/la console -- jamais un calcul refait ici ; il compare
#   seulement l'etat "fabrique" avant/apres pour signaler une transition en
#   console (comparaison, pas un calcul).
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_usinabilite.gd) : cout_effectif/avancer/basculer_fabrication/
#   travail_restant/est_fabrique/fabriquer_objets/diagnostiquer/
#   doit_imprimer_recap, plus le texte d'affichage et de log.

const Objet = preload("res://scripts/objet.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")
const Depense = preload("res://scripts/depense.gd")

const PROPRIETE_USINABILITE := "usinabilite"
const NOM_RESERVE := "travail"
const TAILLE := 60.0

var _config: Dictionary = {}
var _etats: Dictionary = {}
var _materiaux: Dictionary = {}
var _objets: Array = []
var _travail_initial := 10.0
var _cout_base_reference := 1.0
var _intervalle_log := 2.0
var _couleur_en_cours := Color(0.55, 0.42, 0.28)
var _couleur_fabrique := Color(0.2, 0.75, 0.3)
var _noeuds: Dictionary = {}
var _labels: Dictionary = {}
var _temps := 0.0
var _dernier_log := 0.0
var _fabrication_active := false
var _deja_fabrique: Dictionary = {}

func _ready() -> void:
	_config = _charger_json("res://data/banc_usinabilite.json")
	_etats = _charger_json("res://data/etats.json")
	_materiaux = _charger_json("res://data/materiaux.json")
	var proprietes_immuables: Array = _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", [])

	_travail_initial = _config.get("travail_initial", 10.0)
	_cout_base_reference = _config.get("cout_base_reference", 1.0)
	_intervalle_log = _config.get("intervalle_log", 2.0)
	_couleur_en_cours = _couleur_depuis_array(_config.get("couleur_en_cours", [0.55, 0.42, 0.28]))
	_couleur_fabrique = _couleur_depuis_array(_config.get("couleur_fabrique", [0.2, 0.75, 0.3]))

	_objets = fabriquer_objets(_config.get("objets", []), _materiaux, proprietes_immuables, _travail_initial, _cout_base_reference, _etats)
	for objet in _objets:
		_creer_rendu_objet(objet)
		print(ligne_pose_initiale(objet.id, diagnostiquer(objet)))

	_rafraichir_tout()
	_poser_camera()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_fabrication_active = basculer_fabrication(_fabrication_active)
		print(ligne_fabrication(_temps, _fabrication_active))
		_rafraichir_tout()

func _process(delta: float) -> void:
	_temps += delta
	avancer(_objets, delta, _fabrication_active)

	for objet in _objets:
		var id: String = objet.id
		if est_fabrique(objet) and not _deja_fabrique.has(id):
			_deja_fabrique[id] = true
			print(ligne_fabrique(_temps, id))

	if doit_imprimer_recap(_temps, _dernier_log, _intervalle_log):
		print(ligne_recap(_temps, _objets))
		_dernier_log = _temps

	_rafraichir_tout()

func _rafraichir_tout() -> void:
	for objet in _objets:
		var id: String = objet.id
		var diag := diagnostiquer(objet)
		_noeuds[id].color = _couleur_fabrique if diag.fabrique else _couleur_en_cours
		_noeuds[id].position = Vector2(objet.position.x, objet.position.y) - _noeuds[id].size / 2.0
		_labels[id].text = texte_objet(id, diag)

# ---- Fonctions PURES, testables headless (voir test_banc_usinabilite.gd) ----

# cout_base_reference * usinabilite_effective -- voir en-tete. Un materiau
# FACILE a usiner (usinabilite haute) consomme donc SA reserve de travail
# plus vite (cout_base plus haut, voir depense.gd : reserve -= cout_base *
# delta), et finit donc plus tot -- pas l'inverse.
static func cout_effectif(cout_base_reference: float, usinabilite_effective: float) -> float:
	return cout_base_reference * usinabilite_effective

# UN PAS de simulation complet : rien ne bouge tant que la fabrication n'est
# pas active (voir en-tete, contrairement a banc_friction.gd qui glisse des
# t=0) -- actif, Depense.avancer (jamais reimplemente) consomme la reserve
# "travail" de chaque objet a son cout_effectif deja pose a la fabrication.
# Aucun catalogue de seuils fourni : "travail" descend seulement, jamais de
# transformation posee par depense.gd lui-meme -- "fabrique" se lit en
# comparant la reserve a zero (est_fabrique), jamais une deuxieme cause
# posee en parallele.
static func avancer(objets: Array, delta: float, actif: bool) -> void:
	if not actif:
		return
	Depense.avancer(objets, delta, {})

static func basculer_fabrication(actif: bool) -> bool:
	return not actif

static func travail_restant(objet: Dictionary) -> float:
	return objet.proprietes.get("reserves", {}).get(NOM_RESERVE, {}).get("reserve", 0.0)

# depense.gd borne deja "reserve" a 0.0 a la soustraction (jamais negative)
# -- "fabrique" est donc exactement "reserve <= 0.0", jamais une deuxieme
# variable qui pourrait diverger de la reserve reelle.
static func est_fabrique(objet: Dictionary) -> bool:
	return travail_restant(objet) <= 0.0

# Construit les trois objets via Objet.fabriquer (composition fusionnee --
# meme patron que banc_friction.gd/banc_rigidite.gd, catalogue LOCAL a une
# entree par id). L'usinabilite EFFECTIVE (EtatEffectif.valeur, jamais
# reimplementee -- aucun etat de data/etats.json ne la module aujourd'hui,
# mais la lecture reste generique) est resolue UNE SEULE FOIS ici pour
# poser le cout_base du canal "travail" -- usinabilite est IMMUABLE sur ce
# banc (aucun clic ne la fait varier), rien ne justifie de la relire a
# chaque tick.
static func fabriquer_objets(declarations: Array, materiaux: Dictionary, proprietes_immuables: Array, travail_initial: float, cout_base_reference: float, etats: Dictionary) -> Array:
	var catalogue: Dictionary = {}
	for decl in declarations:
		catalogue[decl.id] = {"composition": decl.composition}
	var objets: Array = []
	for decl in declarations:
		var pos: Array = decl.position
		var objet := Objet.fabriquer(decl.id, decl.id, Vector3(pos[0], pos[1], pos[2]), catalogue, materiaux, proprietes_immuables)
		if objet.is_empty():
			continue
		var usinabilite_eff: float = EtatEffectif.valeur(objet, PROPRIETE_USINABILITE, etats)
		objet.proprietes["etats_actifs"] = []
		objet.proprietes["travail_initial"] = travail_initial
		objet.proprietes["reserves"] = {
			NOM_RESERVE: {
				"reserve": travail_initial,
				"cout_base": cout_effectif(cout_base_reference, usinabilite_eff),
				"surcout_action": 0.0,
			},
		}
		objets.append(objet)
	return objets

# Diagnostic d'affichage, PUR : lit uniquement des valeurs deja calculees,
# ne reimplemente jamais leur loi (meme doctrine que
# banc_friction.gd:diagnostiquer). Rend { usinabilite, travail_restant,
# travail_initial, fabrique }.
static func diagnostiquer(objet: Dictionary) -> Dictionary:
	return {
		"usinabilite": objet.proprietes.get(PROPRIETE_USINABILITE, 0.0),
		"travail_restant": travail_restant(objet),
		"travail_initial": objet.proprietes.get("travail_initial", 0.0),
		"fabrique": est_fabrique(objet),
	}

# "changement significatif" version temps, meme role que
# banc_friction.gd:doit_imprimer_recap.
static func doit_imprimer_recap(temps: float, dernier_log: float, intervalle: float) -> bool:
	if intervalle <= 0.0:
		return true
	return temps - dernier_log >= intervalle

static func texte_objet(id: String, diag: Dictionary) -> String:
	return "%s\nusinabilite = %.2f\ntravail restant = %.2f / %.2f\netat = %s" % [
		id, diag.usinabilite, diag.travail_restant, diag.travail_initial, "fabrique" if diag.fabrique else "en cours"
	]

static func ligne_pose_initiale(id: String, diag: Dictionary) -> String:
	return "t=0.0s %s : usinabilite=%.2f travail_restant=%.2f/%.2f" % [id, diag.usinabilite, diag.travail_restant, diag.travail_initial]

static func ligne_fabrication(t: float, actif: bool) -> String:
	return "t=%.1fs fabrication : %s (les trois objets)" % [t, "LANCEE" if actif else "SUSPENDUE"]

static func ligne_fabrique(t: float, id: String) -> String:
	return "t=%.1fs %s : FABRIQUE" % [t, id]

static func ligne_recap(t: float, objets: Array) -> String:
	var morceaux: Array = []
	for objet in objets:
		var diag := diagnostiquer(objet)
		morceaux.append("%s=%.2f" % [objet.id, diag.travail_restant])
	var texte := ""
	for i in range(morceaux.size()):
		if i > 0:
			texte += ", "
		texte += morceaux[i]
	return "t=%.1fs travail restant : %s" % [t, texte]

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

	var label := Label.new()
	label.position = centre - Vector2(TAILLE / 2.0, TAILLE / 2.0 + 90.0)
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

func _couleur_depuis_array(rgb: Array) -> Color:
	return Color(rgb[0], rgb[1], rgb[2])

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
