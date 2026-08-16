extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_foudre.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1, coexiste avec les autres
# bancs). Existe pour VOIR scripts/frappe.gd (ferme et prouve hors domaine
# par test_frappe.gd) tourner sur une scene observable -- PREMIERE
# DEMONSTRATION REELLE. Chantier « foudre -- evenement ponctuel »,
# audit_foudre_prealable.md.
#
# AUCUN MECANISME DU COEUR TOUCHE : frappe.gd/quantite_matiere.gd/
# portee.gd/temperature.gd/objet.gd restent inchanges. Ce fichier COMPOSE
# trois patrons deja fermes, jamais reecrits :
# - Frappe.selectionner/frapper (neuf, voir frappe.gd) -- QUI est frappe et
#   QUEL degat instantane s'applique.
# - Objet.fabriquer (INCHANGE) -- les quatre objets sont de VRAIS fer/bois
#   du catalogue PARTAGE data/materiaux.json (fer conductivite_electrique=
#   1e7 S/m, bois 1e-15 S/m -- deja reels, aucun materiau de demonstration a
#   inventer), composant "objet_physique" (data/types.json, partage) pour
#   porter "temperature" -- meme patron que arbre/bloc.
# - Temperature.avancer (INCHANGE) -- APPELE CHAQUE TICK avec une liste de
#   sources VIDE (refroidissement continu vers l'ambiante, loi de Newton
#   deja prouvee par test_temperature.gd) ; au tick d'une frappe SEULEMENT,
#   UN SEUL appel supplementaire recoit une source de chaleur extreme
#   CONSTRUITE ICI a la position de l'impact -- patron deja demontre par
#   banc_temperature.gd pour une source MOBILE (source reconstruite chaque
#   tick a une position differente) : une source qui n'existe qu'UN SEUL
#   tick est un cas particulier de la meme mecanique, jamais un geste
#   nouveau cote temperature.gd (voir audit_foudre_prealable.md §6).
#
# LA RESERVE "integrite" (par objet, {reserve, cout_base: 0.0,
# surcout_action: 0.0}) N'EST JAMAIS AVANCEE PAR depense.gd -- ce chantier
# ne consomme rien en continu, Frappe.frapper ecrit dessus une seule fois,
# directement, au moment de la frappe.
#
# QUI EST FRAPPABLE (fonction PROPRE a ce fichier, frappe.gd ne le sait
# pas -- son contrat ne porte aucune notion de reserve nommee) :
# objets_frappables(objets, nom_reserve) filtre les objets DEJA DETRUITS
# (reserve <= 0.0) AVANT l'appel a Frappe.selectionner -- meme esprit que
# banc_soudure.gd:_monde_vivant() filtrant les fantomes avant
# Temperature.avancer, mais applique ICI a l'ELIGIBILITE d'une cible,
# jamais dans frappe.gd lui-meme.
#
# CE QU'ON DOIT VOIR : quatre objets fixes -- fer_haut (conducteur, en
# hauteur), bois_bas (ni l'un ni l'autre), fer_bas (conducteur, bas),
# bois_haut (haut, isolant -- prouve que la hauteur SEULE ne
# suffit jamais face a un objet conducteur, voir CRITERES plus bas). Un
# clic gauche declenche UN SEUL eclair : Frappe.selectionner choisit la
# cible au score le plus haut parmi les objets FRAPPABLES a portee de
# "position_source": Frappe.frapper applique le degat instantane ; une
# source de chaleur extreme est appliquee UN SEUL tick a la position de
# l'impact. Le carre frappe vire visiblement vers le rouge (degats) et sa
# temperature bondit (visible au Label, redescend ensuite tick apres tick
# vers l'ambiante). Un second clic declenche un second eclair independant
# -- la foudre ne se repete jamais automatiquement, aucun code dans
# _process ne rappelle Frappe.selectionner/frapper.
#
# CRITERES (data/banc_foudre.json:criteres) : conductivite_electrique
# (source "materiau", QuantiteMatiere.quantite -- EXTENSIVE, pondere par
# volume -- CORRECTION FACTUELLE : la foudre est guidee par le champ
# electrique/la conductivite, jamais par le magnetisme) domine tres
# largement position_z (source "position_z", brute) -- calibre pour que
# bois_haut (hauteur seule) perde TOUJOURS face a fer_bas (conductivite
# seule, hauteur nulle) : la hauteur ne fait que DEPARTAGER entre deux
# objets deja conducteurs, jamais gagner seule contre un objet conducteur.
# Detail des poids : voir _note de data/banc_foudre.json.
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge les donnees/catalogues partages et
#   fabrique les quatre objets (Objet.fabriquer, INCHANGE). _unhandled_input
#   declenche UNE frappe au clic gauche. _process appelle UNIQUEMENT
#   Temperature.avancer (refroidissement continu, sources vides) puis
#   redessine.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_foudre.gd) : fabriquer_objets/objets_frappables/
#   avancer_frappe/detail_score, plus le texte d'affichage et de log.

const Objet = preload("res://scripts/objet.gd")
const Frappe = preload("res://scripts/frappe.gd")
const Temperature = preload("res://scripts/temperature.gd")
const QuantiteMatiere = preload("res://scripts/quantite_matiere.gd")

const TAILLE := 60.0
const HAUTEUR_BARRE := 8.0
const TAILLE_POLICE_LABEL := 13

var _config: Dictionary = {}
var _materiaux: Dictionary = {}
var _proprietes_immuables: Array = []
var _catalogue_temperature: Dictionary = {}
var _objet_physique: Dictionary = {}
var _objets: Array = []
var _noeuds: Dictionary = {}
var _labels: Dictionary = {}
var _temps: float = 0.0

func _ready() -> void:
	_config = _charger_json("res://data/banc_foudre.json")
	_materiaux = _charger_json("res://data/materiaux.json")
	_proprietes_immuables = _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", [])
	_catalogue_temperature = _charger_json("res://data/temperature.json")
	_objet_physique = _charger_json("res://data/types.json").get("objet_physique", {})

	_objets = fabriquer_objets(_config.get("objets", []), _objet_physique, _materiaux, _proprietes_immuables, _config.nom_reserve_integrite, _config.reserve_integrite_defaut)

	for objet in _objets:
		_creer_rendu_objet(objet)
	_poser_camera()
	_rafraichir_tout()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var diag := avancer_frappe(_objets, _config, _materiaux, _catalogue_temperature)
		if diag.is_empty():
			print(_ligne_aucune_cible(_temps))
		else:
			print(_ligne_frappe(_temps, diag))
			for detail in diag.details_score:
				print(_ligne_detail(detail))
		_rafraichir_tout()

func _process(delta: float) -> void:
	_temps += delta
	Temperature.avancer(_objets, [], delta, _catalogue_temperature)
	_rafraichir_tout()

func _rafraichir_tout() -> void:
	for objet in _objets:
		var id: String = objet.id
		var reserve_max: float = _config.reserve_integrite_defaut.get("reserve", 1.0)
		var reserve: float = objet.proprietes.reserves[_config.nom_reserve_integrite].reserve
		_noeuds[id].color = _teinte_pour_degats(reserve, reserve_max)
		_labels[id].text = _texte_label(objet, _config.nom_reserve_integrite)

# ---- Fonctions PURES, testables headless (voir test_banc_foudre.gd) ----

# Construit les quatre (ou N) objets via Objet.fabriquer (composition
# fusionnee -- meme patron que arbre/bloc, "objet_physique" fusionne pour
# porter "temperature", structurelle pour Temperature.avancer) puis ajoute
# la reserve "integrite" A LA MAIN (Objet.fabriquer ne la connait pas --
# aucune reserve n'est declaree pour ce chantier dans data/
# reserve_combustible_composition.json, seul mecanisme de reserve que
# fabriquer() sait construire).
static func fabriquer_objets(declarations: Array, objet_physique: Dictionary, materiaux: Dictionary, proprietes_immuables: Array, nom_reserve_integrite: String, reserve_integrite_defaut: Dictionary) -> Array:
	var table: Dictionary = {"objet_physique": objet_physique}
	for decl in declarations:
		table[decl.id] = {"herite": ["objet_physique"], "composition": decl.composition}
	var objets: Array = []
	for decl in declarations:
		var pos: Array = decl.position
		var objet := Objet.fabriquer(decl.id, decl.id, Vector3(pos[0], pos[1], pos[2]), table, materiaux, proprietes_immuables)
		if objet.is_empty():
			continue
		objet.proprietes["reserves"] = {nom_reserve_integrite: reserve_integrite_defaut.duplicate(true)}
		objets.append(objet)
	return objets

# Un objet DEJA DETRUIT (reserve <= 0.0 sur le canal nomme) n'est plus
# jamais candidat -- filtre PROPRE a ce fichier, frappe.gd ne connait
# aucune reserve nommee dans son contrat (selectionner() ne recoit qu'une
# liste d'"objets", jamais un nom de reserve). Un objet sans la reserve du
# tout (ne devrait pas arriver, fabriquer_objets() la pose toujours) est
# traite comme deja detruit -- meme convention defensive que ci-dessus.
static func objets_frappables(objets: Array, nom_reserve: String) -> Array:
	var vivants: Array = []
	for objet in objets:
		var canal: Dictionary = objet.proprietes.get("reserves", {}).get(nom_reserve, {})
		if canal.get("reserve", 0.0) > 0.0:
			vivants.append(objet)
	return vivants

# UN SEUL eclair : selectionne parmi les objets FRAPPABLES a portee de
# "position_source" (Frappe.selectionner, INCHANGE), applique le degat
# instantane (Frappe.frapper, INCHANGE) puis UN SEUL appel a
# Temperature.avancer avec une source de chaleur extreme construite a la
# position de l'impact (patron banc_temperature.gd, source qui n'existe
# que pour CET appel, jamais reconstruite au tick suivant -- voir en-tete
# de ce fichier). Rend {} si aucune cible frappable a portee (rien ne se
# passe, meme convention que Frappe.selectionner). Rend sinon { cible,
# degats, temperature_avant, temperature_apres, details_score } --
# details_score vient de detail_score(), jamais recalcule deux fois.
static func avancer_frappe(objets: Array, config: Dictionary, materiaux: Dictionary, catalogue_temperature: Dictionary) -> Dictionary:
	var frappables := objets_frappables(objets, config.nom_reserve_integrite)
	var pos: Array = config.position_source
	var cible := Frappe.selectionner(frappables, Vector3(pos[0], pos[1], pos[2]), config.rayon, config.criteres, materiaux)
	if cible.is_empty():
		return {}

	var temperature_avant: float = cible.proprietes.temperature
	Frappe.frapper(cible, config.degats, config.nom_reserve_integrite)

	var decl_chaleur: Dictionary = config.source_chaleur
	var source_chaleur := {
		"position": cible.position,
		"rayon": decl_chaleur.rayon,
		"temperature": decl_chaleur.temperature,
		"force": decl_chaleur.force,
	}
	Temperature.avancer(objets, [source_chaleur], config.delta_impact, catalogue_temperature)

	return {
		"cible": cible,
		"degats": config.degats,
		"temperature_avant": temperature_avant,
		"temperature_apres": cible.proprietes.temperature,
		"details_score": detail_score(cible, config.criteres, materiaux),
	}

# Recalcule, POUR L'AFFICHAGE SEUL, la contribution de chaque critere sur
# UN objet -- meme primitives que frappe.gd:_score (QuantiteMatiere.quantite/
# position.z), jamais la decision elle-meme (deja prise par
# Frappe.selectionner avant que cette fonction ne soit appelee). Rend un
# Array de { propriete, source, poids, valeur, contribution }.
static func detail_score(objet: Dictionary, criteres: Array, materiaux: Dictionary) -> Array:
	var details: Array = []
	for critere in criteres:
		var source: String = critere.get("source", "")
		var poids: float = critere.get("poids", 0.0)
		var propriete: String = critere.get("propriete", "")
		var valeur := 0.0
		if source == "materiau":
			valeur = QuantiteMatiere.quantite(objet.proprietes, propriete, materiaux)
		elif source == "position_z":
			valeur = objet.position.z
		details.append({
			"propriete": propriete,
			"source": source,
			"poids": poids,
			"valeur": valeur,
			"contribution": valeur * poids,
		})
	return details

static func _teinte_pour_degats(reserve: float, reserve_max: float) -> Color:
	if reserve_max <= 0.0:
		return Color(0.85, 0.15, 0.1)
	var ratio: float = clamp(1.0 - reserve / reserve_max, 0.0, 1.0)
	return Color(0.55, 0.55, 0.6).lerp(Color(0.85, 0.15, 0.1), ratio)

static func _texte_label(objet: Dictionary, nom_reserve: String) -> String:
	var reserve: float = objet.proprietes.reserves[nom_reserve].reserve
	return "%s\ntemperature=%.1f\nintegrite=%.2f" % [objet.id, objet.proprietes.temperature, reserve]

static func _ligne_frappe(t: float, diag: Dictionary) -> String:
	return "t=%.1fs FOUDRE : %s frappe (degats=%.2f, temperature %.1f -> %.1f)" % [
		t, diag.cible.id, diag.degats, diag.temperature_avant, diag.temperature_apres
	]

static func _ligne_detail(detail: Dictionary) -> String:
	return "  critere source=%s propriete='%s' valeur=%.3f poids=%.3f contribution=%.3f" % [
		detail.source, detail.propriete, detail.valeur, detail.poids, detail.contribution
	]

static func _ligne_aucune_cible(t: float) -> String:
	return "t=%.1fs FOUDRE : aucune cible frappable a portee" % t

# ---- Rendu (impur, Node) -- aucune decision, seulement la construction
# des noeuds et la camera.

func _creer_rendu_objet(objet: Dictionary) -> void:
	var id: String = objet.id
	var centre := Vector2(objet.position.x, objet.position.y - objet.position.z)

	var noeud := ColorRect.new()
	noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noeud.size = Vector2(TAILLE, TAILLE)
	noeud.position = centre - noeud.size / 2.0
	add_child(noeud)
	_noeuds[id] = noeud

	var label := Label.new()
	label.position = centre - Vector2(TAILLE / 2.0, TAILLE / 2.0 + 50.0)
	label.add_theme_font_size_override("font_size", TAILLE_POLICE_LABEL)
	add_child(label)
	_labels[id] = label

func _poser_camera() -> void:
	var decl_camera: Dictionary = _config.get("camera", {})
	var pos: Array = decl_camera.get("position", [0.0, 0.0, 0.0])
	var camera := Camera2D.new()
	camera.position = Vector2(pos[0], pos[1])
	camera.zoom = Vector2(decl_camera.get("zoom", 0.5), decl_camera.get("zoom", 0.5))
	camera.enabled = true
	add_child(camera)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
