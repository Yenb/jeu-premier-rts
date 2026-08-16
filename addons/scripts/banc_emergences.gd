extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_emergences.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1). Demonstration du chantier
# "proprietes emergentes -- capacites conditionnelles a la fabrication"
# (scripts/objet.gd:_evaluer_emergences, voir son en-tete pour la doctrine
# complete) : un objet compose peut acquerir une propriete qu'AUCUN de ses
# composants ne porte individuellement, si la combinaison remplit des
# conditions lues depuis data/emergences.json.
#
# CE QU'ON DOIT VOIR : AVANT/APRES, bistable au clic gauche (meme geste que
# banc_restitution.gd -- un premier clic fabrique, un second reinitialise) :
# - AVANT : trois silhouettes grises, composition seule affichee, aucune
#   propriete fusionnee, aucune emergence.
# - APRES (clic) : chaque objet est FABRIQUE (Objet.fabriquer, composition
#   fusionnee + emergences evaluees). Le label detaille, PAR EMERGENCE DU
#   CATALOGUE, chaque condition (propriete=valeur operateur seuil, colore
#   OK/RATE) et le verdict final (ACQUISE/non) -- le verdict vient TOUJOURS
#   de proprietes.get(id, false), jamais recalcule : la coloration OK/RATE
#   par condition est un AFFICHAGE de nombres deja connus (aucune loi
#   reimplementee), le carre ne change de couleur que sur le verdict reel.
#   - "fer_cristal" (fer + cristal_demo, volumes egaux) : combine un bon
#     conducteur (fer, conductivite_electrique) et une matiere sensible a
#     la magie (cristal_demo, sensibilite_magique) -- ni l'un ni l'autre
#     seul ne suffit (fer, sensibilite_magique 0.2, sous le seuil de
#     data/emergences.json:canalise_mana), la COMBINAISON declenche
#     "canalise_mana": true.
#   - "balsa" (balsa_demo seul) : densite basse ET resistance_impact assez
#     haute declenchent "flotte": true, sans aucune composition necessaire.
#   - "fer_seul" (fer seul) : conductivite_electrique haute REMPLIT sa
#     condition, mais sensibilite_magique (0.2) rate l'autre -- ET logique,
#     ni "canalise_mana" ni "flotte" (densite trop haute).
# Trace console a chaque bascule (fabrication ou reinitialisation).
#
# DECISION (constat pose avant d'ecrire, voir CLAUDE.md "Ne code pas ce que
# tu n'as pas compris") : "sensibilite_magique" est presente sur chaque
# fiche de data/materiaux.json (fer 0.2/pierre 0.3/bois 0.5/cristal_demo
# 0.5) mais N'EST PAS dans data/proprietes_immuables_composition.json --
# DORMANTE partout dans le depot par decision explicite d'un chantier
# anterieur (banc_magie_perception, role RECEPTEUR jamais lu). Sans
# fusion, un objet fabrique par composition ne porterait jamais cette
# propriete, et "canalise_mana" ne pourrait jamais se declencher. Ce banc
# etend donc SA PROPRE liste proprietes_immuables (construite a _ready :
# catalogue partage + "sensibilite_magique") plutot que de toucher au
# catalogue partage -- objet.gd et data/proprietes_immuables_
# composition.json restent intouches, aucun autre banc n'est affecte, la
# dormance deja actee ailleurs est preservee.
#
# LIMITE STRICTE : ce fichier et ses donnees (data/banc_emergences.json)
# sont le SEUL perimetre -- objet.gd est MODIFIE par ce chantier (voir son
# en-tete, _evaluer_emergences), mais aucun AUTRE mecanisme du coeur
# (charge.gd/depense.gd/produit.gd/seuil_etat.gd/perception.gd) n'est
# touche. data/emergences.json (catalogue NEUF, generique, aucun nom de
# contenu propre a ce banc) et cristal_demo/balsa_demo (data/
# materiaux.json, NOUVEAUX materiaux de demonstration) sont les seules
# donnees NEUVES au-dela de ce fichier et de ses propres donnees jetables.
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready pose le rendu en etat AVANT. _unhandled_input
#   bascule _fabrique au clic gauche (fonction pure basculer_fabrique,
#   ci-dessous) puis rappelle _rafraichir_tout -- jamais de calcul refait
#   dans le Node lui-meme (regle CLAUDE.md).
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_emergences.gd) : objets_bruts/fabriquer_objets/
#   texte_composition/emergences_actives/diagnostic_conditions/
#   texte_label_avant/texte_label_apres/ligne_console.

const Objet = preload("res://scripts/objet.gd")

const TAILLE := 90.0
const _COULEUR_AVANT := Color(0.4, 0.4, 0.45)
const _COULEUR_NEUTRE := Color(0.55, 0.55, 0.6)
const _COULEUR_EMERGENCE := Color(0.85, 0.55, 0.2)

var _config: Dictionary = {}
var _declarations: Array = []
var _materiaux: Dictionary = {}
var _proprietes_immuables_locales: Array = []
var _catalogue_emergences: Array = []
var _objets: Array = []
var _fabrique := false
var _temps: float = 0.0
var _noeuds: Dictionary = {}
var _labels: Dictionary = {}

func _ready() -> void:
	_config = _charger_json("res://data/banc_emergences.json")
	_declarations = _config.get("objets", [])
	_materiaux = _charger_json("res://data/materiaux.json")
	_proprietes_immuables_locales = _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", []) + ["sensibilite_magique"]
	_catalogue_emergences = _charger_json("res://data/emergences.json").get("emergences", [])

	_objets = objets_bruts(_declarations)
	for objet in _objets:
		_creer_rendu_objet(objet)
	_poser_camera()
	_rafraichir_tout()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_fabrique = basculer_fabrique(_fabrique)
		_objets = fabriquer_objets(_declarations, _materiaux, _proprietes_immuables_locales, _catalogue_emergences) if _fabrique else objets_bruts(_declarations)
		print(_ligne_bascule(_temps, _fabrique))
		if _fabrique:
			for objet in _objets:
				print(ligne_console(objet, _config.emergences_a_afficher))
		_rafraichir_tout()

func _process(delta: float) -> void:
	_temps += delta

func _rafraichir_tout() -> void:
	for objet in _objets:
		var id: String = objet.id
		_noeuds[id].color = _couleur_objet(objet)
		_labels[id].text = texte_label_apres(objet, _config.proprietes_a_afficher, _catalogue_emergences) if _fabrique else texte_label_avant(objet)

func _couleur_objet(objet: Dictionary) -> Color:
	if not _fabrique:
		return _COULEUR_AVANT
	return _COULEUR_EMERGENCE if not emergences_actives(objet, _config.emergences_a_afficher).is_empty() else _COULEUR_NEUTRE

# ---- Fonctions PURES, testables headless (voir test_banc_emergences.gd) ----

static func basculer_fabrique(fabrique: bool) -> bool:
	return not fabrique

# Etat AVANT : composition seule, AUCUNE fusion -- jamais Objet.fabriquer,
# pour que le label AVANT ne montre litteralement rien de plus que ce que
# le joueur a declare (aucune propriete inventee).
static func objets_bruts(declarations: Array) -> Array:
	var objets: Array = []
	for decl in declarations:
		var pos: Array = decl.position
		objets.append({
			"id": decl.id,
			"position": Vector3(pos[0], pos[1], pos[2]),
			"proprietes": {"composition": decl.composition},
		})
	return objets

# Etat APRES : fabrique chaque objet declare via Objet.fabriquer -- meme
# patron que banc_reactivite.gd:fabriquer_cibles, un catalogue de types
# local construit depuis les declarations (id -> {composition}), aucune
# donnee dupliquee.
static func fabriquer_objets(declarations: Array, materiaux: Dictionary, proprietes_immuables: Array, catalogue_emergences: Array) -> Array:
	var catalogue: Dictionary = {}
	for decl in declarations:
		catalogue[decl.id] = {"composition": decl.composition}
	var objets: Array = []
	for decl in declarations:
		var pos: Array = decl.position
		var objet := Objet.fabriquer(decl.id, decl.id, Vector3(pos[0], pos[1], pos[2]), catalogue, materiaux, proprietes_immuables, {}, catalogue_emergences)
		objets.append(objet)
	return objets

static func texte_composition(objet: Dictionary) -> String:
	var composition: Array = objet.get("proprietes", {}).get("composition", [])
	var noms: Array = []
	for element in composition:
		noms.append(String(element.get("materiau", "")))
	return "+".join(noms)

static func emergences_actives(objet: Dictionary, emergences_a_afficher: Array) -> Array:
	var actives: Array = []
	for nom in emergences_a_afficher:
		if objet.proprietes.get(nom, false) == true:
			actives.append(String(nom))
	return actives

static func texte_emergences(objet: Dictionary, emergences_a_afficher: Array) -> String:
	var actives := emergences_actives(objet, emergences_a_afficher)
	return ", ".join(actives) if not actives.is_empty() else "aucune"

# DIAGNOSTIC PAR CONDITION, pour affichage seul (jamais pour decider) :
# pour chaque entree du catalogue, rend { id, acquise (LUE sur
# proprietes.get(id, false), la VERITE reelle deja posee par objet.gd),
# conditions: Array de { texte, ok } } -- "ok" est un simple `valeur op
# seuil` litteral, MEME operateur/seuil que ceux du catalogue, jamais une
# loi differente : sert a MONTRER pourquoi une condition passe ou rate,
# jamais a re-decider l'emergence elle-meme (le carre ne change de couleur
# que sur "acquise", pas sur ce diagnostic).
static func diagnostic_conditions(objet: Dictionary, catalogue_emergences: Array) -> Array:
	var diagnostics: Array = []
	for entree in catalogue_emergences:
		var id: String = String(entree.get("id", "?"))
		var conditions: Array = []
		for condition in entree.get("conditions", []):
			var nom: String = String(condition.get("propriete", ""))
			var operateur: String = String(condition.get("operateur", ""))
			var seuil: float = float(condition.get("seuil", 0.0))
			var valeur: float = float(objet.proprietes.get(nom, 0.0))
			var ok: bool
			match operateur:
				">=": ok = valeur >= seuil
				"<=": ok = valeur <= seuil
				">": ok = valeur > seuil
				"<": ok = valeur < seuil
				"==": ok = is_equal_approx(valeur, seuil)
				_: ok = false
			conditions.append({"texte": "%s=%s %s %s" % [nom, str(valeur), operateur, str(seuil)], "ok": ok})
		diagnostics.append({"id": id, "acquise": objet.proprietes.get(id, false) == true, "conditions": conditions})
	return diagnostics

static func texte_label_avant(objet: Dictionary) -> String:
	return "[b]%s[/b]\ncomposition=%s\n[i](clic pour fabriquer)[/i]" % [objet.id, texte_composition(objet)]

static func texte_label_apres(objet: Dictionary, proprietes_a_afficher: Array, catalogue_emergences: Array) -> String:
	var lignes: Array = ["[b]%s[/b]" % objet.id, "composition=%s" % texte_composition(objet)]
	for nom in proprietes_a_afficher:
		lignes.append("%s=%s" % [nom, str(objet.proprietes.get(nom, 0.0))])
	for diag in diagnostic_conditions(objet, catalogue_emergences):
		lignes.append("")
		lignes.append("[u]%s[/u] %s" % [diag.id, "[color=lime]ACQUISE[/color]" if diag.acquise else "[color=gray]non[/color]"])
		for condition in diag.conditions:
			lignes.append("  %s %s" % [condition.texte, "[color=lime]OK[/color]" if condition.ok else "[color=orange_red]RATE[/color]"])
	return "\n".join(lignes)

static func ligne_console(objet: Dictionary, emergences_a_afficher: Array) -> String:
	return "%s : fabrique -- composition=%s emergences=%s" % [
		objet.id, texte_composition(objet), texte_emergences(objet, emergences_a_afficher),
	]

static func _ligne_bascule(t: float, fabrique: bool) -> String:
	return "t=%.1fs : %s" % [t, "FABRICATION" if fabrique else "RESET (retour a l'etat avant)"]

# ---- Rendu (impur, Node) -- aucune decision, seulement la construction des
# noeuds et la camera.

func _creer_rendu_objet(objet: Dictionary) -> void:
	var id: String = objet.id
	var centre := Vector2(objet.position.x, objet.position.y)

	var noeud := ColorRect.new()
	noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noeud.color = _COULEUR_AVANT
	noeud.size = Vector2(TAILLE, TAILLE)
	noeud.position = centre - noeud.size / 2.0
	add_child(noeud)
	_noeuds[id] = noeud

	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.custom_minimum_size = Vector2(260.0, 0.0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.position = centre - Vector2(TAILLE / 2.0, TAILLE / 2.0 + 250.0)
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
