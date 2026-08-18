extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_combustible.tscn, PAS la
# scene principale -- run/main_scene reste banc_p1). PREMIERE
# demonstration reelle du chantier "feu -- la reserve de combustible suit
# la matiere" : objet.gd:_fabriquer_reserve_combustible (capacite calculee
# a la fabrication depuis la composition) et scripts/combustible.gd
# (lecture du rendement) jouant en jeu pour la premiere fois, avec
# depense.gd (deja ecrit, non touche) qui consomme la reserve exactement
# comme il consommait le forfait avant ce chantier. Noms de domaine reels
# (bois/fer/paille/combustible) -- exception documentee (CLAUDE.md : "un
# banc jetable peut nommer une categorie pour poser une scene
# d'observation").
#
# JETABLE PAR DEFINITION : aucune regle de jeu ne doit vivre ici, seulement
# du cablage et de la lecture. Tout calcul d'affichage est en fonctions
# STATIQUES testables (_texte_composition/_teinte_pour_proportion/
# _texte_label/_ligne_pose/_ligne_rapport/_ligne_extinction) -- _process
# ne fait qu'appeler Depense.avancer (deja le mecanisme reel) et
# Combustible.restant (deja le mecanisme reel), jamais recalculer une loi
# ecrite ailleurs.
#
# CE QU'ON DOIT VOIR : cinq objets DEJA EN FEU des le demarrage (aucune
# propagation, aucun colon -- ce banc observe la CONSUMATION, pas
# l'allumage). `bois_petit`/`bois_moyen`/`bois_grand` (meme materiau,
# volumes 3/8/15) s'eteignent dans cet ordre, precisement parce que leur
# CAPACITE (calculee UNE FOIS a la fabrication, jamais ecrite a la main)
# suit leur volume. `fer_meme_volume` (volume 8.0, IDENTIQUE a bois_moyen)
# s'eteint presque instantanement -- meme volume, matiere differente,
# capacite tres differente : "pouvoir_calorifique" du fer (materiaux.json,
# chantier correctif "une grandeur dediee au contenu energetique") tres
# inferieur a celui du bois -- PROPRIETE DEDIEE, INDEPENDANTE
# d'"inflammabilite" (jamais recalculee depuis elle). `paille_vive`
# (volume 5.0) le prouve dans l'AUTRE sens : la paille est PLUS
# inflammable que le bois (s'enflammerait plus vite) mais a un pouvoir
# calorifique NETTEMENT plus bas -- elle s'eteint presque aussi vite que
# le fer, malgre une inflammabilite superieure a celle du bois. Chaque
# objet affiche EN PERMANENCE son nom, sa composition, sa capacite
# (immuable) et ce qu'il lui reste (absolu ET proportion, scripts/
# combustible.gd:restant), plus une BARRE dont le remplissage suit la
# proportion restante. La TEINTE fonce a mesure que la reserve s'epuise,
# puis se fige en cendre a l'extinction. La console imprime, une phrase
# par ligne : une ligne de POSE par objet au demarrage (capacite
# initiale), un RAPPORT PERIODIQUE (ce qu'il reste, absolu et proportion)
# pour chaque objet encore allume, et la ligne d'EXTINCTION au moment ou
# Depense.avancer retire "brule" (combustible epuise).
#
# LIMITE STRICTE (rappel explicite du chantier) : ce fichier cable
# UNIQUEMENT ce banc -- aucun mecanisme neuf, aucune extension du coeur au
# -dela de ce qu'objet.gd/combustible.gd/quantite_matiere.gd portent deja.
# depense.gd/extinction.gd/propagation.gd/champ.gd/materiaux.json non
# touches.

const Objet = preload("res://scripts/objet.gd")
const Combustible = preload("res://scripts/combustible.gd")
const Depense = preload("res://scripts/depense.gd")

const TAILLE := 70.0
const HAUTEUR_BARRE := 10.0
const INTERVALLE_RAPPORT := 2.0
const NOM_RESERVE := "combustible"

var _monde: Array = []
var _objets: Array = []
var _noeuds: Dictionary = {}
var _labels: Dictionary = {}
var _barres_fond: Dictionary = {}
var _barres_remplies: Dictionary = {}
var _prochain_rapport: Dictionary = {}
var _eteints: Dictionary = {}
var _seuils_combustible: Dictionary = {}
var _temps: float = 0.0

func _ready() -> void:
	var donnees := _charger_json("res://data/banc_combustible.json")
	var materiaux := _charger_json("res://data/materiaux.json")
	var reserve_combustible := _charger_json("res://data/reserve_combustible_composition.json")
	var seuils_combustible := _charger_json("res://data/seuils_combustible.json")
	_seuils_combustible = seuils_combustible

	var declarations: Array = donnees.get("objets", [])
	var catalogue_types: Dictionary = {}
	for decl in declarations:
		catalogue_types[decl.id] = {"composition": decl.composition}

	for decl in declarations:
		var pos: Array = decl.position
		var objet := Objet.fabriquer(decl.id, decl.id, Vector3(pos[0], pos[1], pos[2]), catalogue_types, materiaux, [], reserve_combustible)
		if objet.is_empty():
			push_error("banc_combustible.gd : fabrication refusee pour '%s'" % decl.id)
			continue
		objet.proprietes["brule"] = true
		_monde.append(objet)
		_objets.append(objet)
		_prochain_rapport[decl.id] = INTERVALLE_RAPPORT
		_creer_rendu_objet(objet)

	_poser_camera()

	for objet in _objets:
		var capacite: float = objet.proprietes.reserves[NOM_RESERVE].capacite
		print(_ligne_pose(0.0, objet.id, capacite))

	_rafraichir_tout()

func _process(delta: float) -> void:
	_temps += delta

	var franchis: Array = Depense.avancer(_monde, delta, _seuils_combustible)
	for id in franchis:
		var objet: Dictionary = _par_id(id)
		if objet.is_empty() or _eteints.has(id):
			continue
		if not objet.proprietes.get("brule", false):
			var restant := Combustible.restant(objet, NOM_RESERVE)
			print(_ligne_extinction(_temps, id, restant.absolu))
			_eteints[id] = true
			_prochain_rapport.erase(id)

	for objet in _objets:
		var id: String = objet.id
		if _prochain_rapport.has(id) and _temps >= _prochain_rapport[id]:
			var restant := Combustible.restant(objet, NOM_RESERVE)
			print(_ligne_rapport(_temps, id, restant.absolu, restant.proportion))
			_prochain_rapport[id] += INTERVALLE_RAPPORT

	_rafraichir_tout()

func _par_id(id: String) -> Dictionary:
	for objet in _objets:
		if objet.id == id:
			return objet
	return {}

func _rafraichir_tout() -> void:
	for objet in _objets:
		var id: String = objet.id
		var restant := Combustible.restant(objet, NOM_RESERVE)
		_noeuds[id].color = _teinte_pour_proportion(restant.proportion)
		_barres_remplies[id].size.x = _barres_fond[id].size.x * restant.proportion
		var capacite: float = objet.proprietes.reserves[NOM_RESERVE].capacite
		_labels[id].text = _texte_label(id, capacite, restant)

# ---- Fonctions PURES, testables -- lisent un rendement deja calcule par
# combustible.gd/depense.gd, ne reimplementent jamais leur loi.

static func _texte_composition(composition: Array) -> String:
	var morceaux: Array = []
	for element in composition:
		morceaux.append("%.1f %s" % [float(element.get("volume", 0.0)), String(element.get("materiau", "?"))])
	return " + ".join(morceaux)

static func _teinte_pour_proportion(proportion: float) -> Color:
	var p: float = clamp(proportion, 0.0, 1.0)
	return Color(0.3 + 0.6 * p, 0.15 + 0.25 * p, 0.05)

static func _texte_label(id: String, capacite: float, restant: Dictionary) -> String:
	return "%s\ncapacite=%.2f\nreste=%.2f (%.0f%%)" % [id, capacite, restant.absolu, restant.proportion * 100.0]

static func _ligne_pose(t: float, id: String, capacite: float) -> String:
	return "t=%.1fs %s : reserve initiale = %.2f" % [t, id, capacite]

static func _ligne_rapport(t: float, id: String, absolu: float, proportion: float) -> String:
	return "t=%.1fs %s : reste %.2f (%.0f%%)" % [t, id, absolu, proportion * 100.0]

static func _ligne_extinction(t: float, id: String, absolu: float) -> String:
	return "t=%.1fs %s : eteint (combustible epuise), reste %.2f" % [t, id, absolu]

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
	rempli.color = Color(0.9, 0.5, 0.1)
	rempli.size = Vector2(TAILLE, HAUTEUR_BARRE)
	rempli.position = fond.position
	add_child(rempli)
	_barres_remplies[id] = rempli

	var label := Label.new()
	label.position = centre - Vector2(TAILLE / 2.0, TAILLE / 2.0 + 90.0)
	add_child(label)
	_labels[id] = label

func _poser_camera() -> void:
	var centre_x := 0.0
	for objet in _objets:
		centre_x += objet.position.x
	if not _objets.is_empty():
		centre_x /= _objets.size()
	var camera := Camera2D.new()
	camera.position = Vector2(centre_x, 320.0)
	camera.zoom = Vector2(0.75, 0.75)
	camera.enabled = true
	add_child(camera)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
