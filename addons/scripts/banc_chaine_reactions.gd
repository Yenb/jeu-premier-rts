extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_chaine_reactions.tscn, PAS la
# scene principale -- run/main_scene reste banc_p1). PREMIERE demonstration
# reelle du chantier « composition en profondeur -- chainage automatique de
# reactions » : scripts/reaction.gd (mecanisme du COEUR neuf) detecte seul
# les paires reactives et applique la chaine -- CE FICHIER ne fait plus
# QU'UN SEUL appel par tick a Reaction.detecter_et_reagir, contrairement a
# scripts/banc_reactivite.gd qui portait encore lui-meme les quatre phases
# (detection, accumulation, transformation, consommation) dans son propre
# cablage.
#
# CE QU'ON DOIT VOIR : trois objets fabriques par composition, acide_demo et
# eau_demo de part et d'autre de fer, tous trois REELS (data/materiaux.json).
# Un clic gauche RAPPROCHE les trois a la fois (meme geste bistable que
# scripts/banc_reactivite.gd) :
# - acide_demo + fer -> sel_metallique (entree EXISTANTE de
#   data/reactions.json, deja verrouillee par scripts/test_banc_reactivite.gd)
#   -- acide_demo reste acide_demo (modele ASYMETRIQUE, materiau_a jamais
#   transforme), fer devient sel_metallique.
# - sel_metallique, desormais A PORTEE d'eau_demo (positionne sur la case de
#   fer, jamais deplace par la transformation -- Reaction.detecter_et_reagir
#   ne touche jamais position/id, seulement proprietes), forme une NOUVELLE
#   paire avec l'entree sel_metallique+eau_demo -> sel_dissous (NOUVELLE
#   entree de data/reactions.json) -- detectee au tick SUIVANT celui qui a
#   produit sel_metallique, jamais dans le meme appel (voir scripts/
#   reaction.gd, "CHAINAGE PAR LE TEMPS, PAS PAR UNE BOUCLE INTERNE").
# - eau_demo reste eau_demo (materiau_a, jamais transforme).
# Un second clic ELOIGNE les trois -- hors de portee_reaction, aucune charge
# n'accumule, rien ne se transforme, meme loin apres l'avoir ete une
# premiere fois (l'etat produit est PERMANENT, aucun retour arriere).
#
# profondeur_chaine_max (data/banc_chaine_reactions.json, 4) borne la
# cascade -- ici seuls deux etages existent dans le catalogue
# (acide+fer->sel_metallique profondeur 1, sel_metallique+eau->sel_dissous
# profondeur 2), largement sous la limite : la cascade s'arrete simplement
# faute d'une TROISIEME entree, jamais parce que profondeur_chaine_max
# l'interromprait ici (voir scripts/test_reaction.gd pour la preuve dediee
# que la limite elle-meme fonctionne, hors domaine).
#
# LIMITE STRICTE : ce fichier, ses donnees et son test sont le SEUL
# perimetre -- scripts/reaction.gd/produit.gd/objet.gd restent EXACTEMENT
# ceux deja verrouilles par leurs propres tests, aucun n'est touche par ce
# banc. eau_demo/sel_dissous (data/materiaux.json/data/types.json),
# reactivite sur sel_metallique (REVISION, data/materiaux.json) et la
# quatrieme entree de data/reactions.json sont les seules donnees NEUVES
# au-dela de ce fichier et de ses propres donnees jetables
# (data/banc_chaine_reactions.json).
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready fabrique les trois objets. _unhandled_input
#   bascule leurs positions au clic gauche. _process appelle UNIQUEMENT
#   Reaction.detecter_et_reagir (jamais un calcul refait ici) puis lit son
#   resultat pour la trace console.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_chaine_reactions.gd) : materiau_de/fabriquer_objets/
#   basculer_positions/diagnostiquer, plus le texte d'affichage et de log.

const Objet = preload("res://scripts/objet.gd")
const Reaction = preload("res://scripts/reaction.gd")

const TAILLE := 70.0
const HAUTEUR_BARRE := 10.0

var _config: Dictionary = {}
var _reactions: Array = []
var _catalogue_types: Dictionary = {}
var _materiaux: Dictionary = {}
var _proprietes_immuables: Array = []
var _objets: Array = []
var _proche := false
var _noeuds: Dictionary = {}
var _barres_fond: Dictionary = {}
var _barres_remplies: Dictionary = {}
var _labels: Dictionary = {}
var _materiau_avant: Dictionary = {}
var _temps: float = 0.0

func _ready() -> void:
	_config = _charger_json("res://data/banc_chaine_reactions.json")
	_reactions = _charger_json("res://data/reactions.json").get("reactions", [])
	_catalogue_types = _charger_json("res://data/types.json")
	_materiaux = _charger_json("res://data/materiaux.json")
	_proprietes_immuables = _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", [])

	_objets = fabriquer_objets(_config.get("objets", []), false, _materiaux, _proprietes_immuables)
	for objet in _objets:
		_materiau_avant[objet.id] = materiau_de(objet)
		_creer_rendu(objet)
	_poser_camera()

	for objet in _objets:
		print(_ligne_pose_initiale(objet, _reactions))
	_rafraichir_tout()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_proche = not _proche
		basculer_positions(_objets, _config.get("objets", []), _proche)
		print(_ligne_position(_temps, _proche))
		_rafraichir_tout()

func _process(delta: float) -> void:
	_temps += delta
	var transformations: Array = Reaction.detecter_et_reagir(_objets, _reactions, delta, int(_config.profondeur_chaine_max), _catalogue_types, _materiaux)
	for transfo in transformations:
		print(_ligne_transformation(_temps, transfo))
	_rafraichir_tout()

# ---- Fonctions PURES, testables headless (voir test_banc_chaine_reactions.gd) ----

static func materiau_de(objet: Dictionary) -> String:
	var composition: Array = objet.get("proprietes", {}).get("composition", [])
	if composition.is_empty():
		return ""
	return String(composition[0].get("materiau", ""))

# Construit les objets declares (meme patron que
# banc_reactivite.gd:fabriquer_cibles/fabriquer_acide, generalise a N objets
# sans distinction de role -- reaction.gd decide seul qui est source/cible
# a la lecture du catalogue, ce fichier ne le sait jamais a l'avance).
static func fabriquer_objets(declarations: Array, proche: bool, materiaux: Dictionary, proprietes_immuables: Array) -> Array:
	var catalogue: Dictionary = {}
	for decl in declarations:
		catalogue[decl.id] = {"composition": decl.composition}
	var objets: Array = []
	for decl in declarations:
		var pos: Array = decl.position_proche if proche else decl.position_loin
		var objet := Objet.fabriquer(decl.id, decl.id, Vector3(pos[0], pos[1], pos[2]), catalogue, materiaux, proprietes_immuables)
		objets.append(objet)
	return objets

static func basculer_positions(objets: Array, declarations: Array, proche: bool) -> void:
	var par_id: Dictionary = {}
	for decl in declarations:
		par_id[decl.id] = decl
	for objet in objets:
		var decl: Dictionary = par_id.get(objet.id, {})
		if decl.is_empty():
			continue
		var p: Array = decl.position_proche if proche else decl.position_loin
		objet.position = Vector3(p[0], p[1], p[2])

# Diagnostic d'affichage, PUR : lit uniquement des valeurs deja calculees
# par reaction.gd/charge.gd, ne reimplemente jamais leur loi (meme
# discipline que banc_reactivite.gd:diagnostiquer_cible). Rend { materiau,
# reactivite, profondeur_chaine, a_un_canal, charge, seuil }.
static func diagnostiquer(objet: Dictionary) -> Dictionary:
	var canal: Dictionary = objet.proprietes.get("etats", {}).get("reaction", {})
	return {
		"materiau": materiau_de(objet),
		"reactivite": objet.proprietes.get("reactivite", 0.0),
		"profondeur_chaine": int(objet.proprietes.get("_profondeur_chaine", 0)),
		"a_un_canal": not canal.is_empty(),
		"charge": canal.get("charge", 0.0),
		"seuil": canal.get("seuil", 0.0),
	}

static func _texte_label(id: String, diag: Dictionary) -> String:
	var ligne_canal: String = "canal_reaction=%.2f/%.2f" % [diag.charge, diag.seuil] if diag.a_un_canal else "canal_reaction=—"
	return "%s\nmateriau=%s\nreactivite=%.2f\nprofondeur_chaine=%d\n%s" % [
		id, diag.materiau, diag.reactivite, diag.profondeur_chaine, ligne_canal,
	]

static func _ligne_pose_initiale(objet: Dictionary, reactions: Array) -> String:
	return "t=0.0s %s : materiau=%s reactivite=%.2f" % [objet.id, materiau_de(objet), objet.proprietes.get("reactivite", 0.0)]

static func _ligne_position(t: float, proche: bool) -> String:
	return "t=%.1fs : objets %s" % [t, "RAPPROCHES" if proche else "ELOIGNES"]

static func _ligne_transformation(t: float, transfo: Dictionary) -> String:
	return "t=%.1fs %s : reaction terminee -- devient %s (profondeur_chaine=%d)" % [
		t, transfo.id, transfo.type_produit, transfo.profondeur_chaine,
	]

# ---- Rendu (impur, Node) -- aucune decision, seulement la construction des
# noeuds, la camera et le rafraichissement visuel.

func _creer_rendu(objet: Dictionary) -> void:
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
	rempli.color = Color(0.85, 0.55, 0.2)
	rempli.size = Vector2(0.0, HAUTEUR_BARRE)
	rempli.position = fond.position
	add_child(rempli)
	_barres_remplies[id] = rempli

	var label := Label.new()
	label.position = centre - Vector2(TAILLE / 2.0, TAILLE / 2.0 + 110.0)
	add_child(label)
	_labels[id] = label

func _rafraichir_tout() -> void:
	for objet in _objets:
		var id: String = objet.id
		var diag := diagnostiquer(objet)
		var transforme: bool = diag.materiau != _materiau_avant.get(id, diag.materiau)
		_noeuds[id].position = Vector2(objet.position.x, objet.position.y) - _noeuds[id].size / 2.0
		_noeuds[id].color = _COULEUR_PRODUIT if transforme else _teinte_par_profondeur(diag.profondeur_chaine)
		_labels[id].text = _texte_label(id, diag)
		_labels[id].position = Vector2(objet.position.x, objet.position.y) - Vector2(TAILLE / 2.0, TAILLE / 2.0 + 110.0)
		var pos_barre := Vector2(objet.position.x, objet.position.y) + Vector2(-TAILLE / 2.0, TAILLE / 2.0 + 6.0)
		_barres_fond[id].position = pos_barre
		_barres_remplies[id].position = pos_barre
		var ratio: float = clamp(diag.charge / diag.seuil, 0.0, 1.0) if diag.seuil > 0.0 else 0.0
		_barres_remplies[id].size.x = _barres_fond[id].size.x * ratio

const _COULEUR_PRODUIT := Color(0.55, 0.5, 0.35)
const _COULEUR_BASE := Color(0.4, 0.6, 0.75)
const _COULEUR_ETAGE_1 := Color(0.85, 0.55, 0.2)

static func _teinte_par_profondeur(profondeur: int) -> Color:
	if profondeur <= 0:
		return _COULEUR_BASE
	return _COULEUR_ETAGE_1

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
