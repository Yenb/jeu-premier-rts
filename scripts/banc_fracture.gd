extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_fracture.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1, coexiste avec les autres
# bancs). Existe pour VOIR resistance_impact/fragilite (data/materiaux.json,
# DORMANTES avant ce chantier) tourner sur une scene observable. Chantier
# « resistance_impact -- fracture par choc »,
# audit_resistance_impact_produit_prealable.md (partie A).
#
# AUCUN MECANISME DU COEUR TOUCHE : frappe.gd/seuil_etat.gd/etat_effectif.gd/
# produit.gd/objet.gd restent inchanges. Ce fichier COMPOSE quatre patrons
# deja fermes, jamais reecrits :
# - Frappe.selectionner/frapper (INCHANGE, voir banc_foudre.gd) -- QUI est
#   frappe et QUEL degat instantane s'applique. DIFFERENCE ASSUMEE avec
#   banc_foudre.gd : la POSITION SOURCE de la selection n'est pas fixe en
#   donnee, c'est le CLIC (get_global_mouse_position, meme idiome que
#   banc_p1.gd) -- un choc est PORTE PAR LE JOUEUR qui vise sa cible,
#   contrairement a la foudre qui choisit seule par score composite sur
#   toute la scene. Un "rayon_frappe" petit (voir data/banc_fracture.json)
#   fait office de visee : cliquer pres du fer ne met jamais la pierre a
#   portee, et reciproquement.
# - frappe.gd NE MONTE AUCUNE PROPRIETE (il ne fait que decrementer une
#   reserve nommee, bornee a zero) -- c'est CE FICHIER, juste apres chaque
#   Frappe.frapper, qui ecrit lui-meme
#   `proprietes.degats_impact_cumules += degats` sur la cible (voir
#   audit_resistance_impact_produit_prealable.md §2 : aucune des deux
#   ecritures possibles n'existait avant ce chantier, celle-ci est la
#   seconde, cote cablage, jamais dans frappe.gd).
# - SeuilEtat.avancer (INCHANGE) -- compare degats_impact_cumules a
#   resistance_impact (seuil_propriete, fusionnee a la fabrication) et pose
#   l'etat "fracture" (data/etats.json/data/seuils_etat.json) au
#   franchissement. Catalogue PARTAGE data/seuils_etat.json passe TEL QUEL
#   (les entrees point_fusion/point_ebullition/sublimation/chaud y
#   cohabitent, jamais declenchees ici -- aucune source de temperature dans
#   ce banc, la "temperature" des deux objets reste a l'ambiante du paquet
#   objet_physique).
# - Produit.transformer (INCHANGE, patron banc_corrosion.gd/
#   banc_pourriture.gd/banc_solubilite.gd) -- appele PAR CE FICHIER, jamais
#   par seuil_etat.gd (qui n'a aucune branche "produire", meme doctrine que
#   depense.gd), UNIQUEMENT si l'objet fraichement fracture porte une
#   fragilite superieure a config.seuil_fragilite_eclats : sinon l'etat
#   "fracture" reste seul pose (deformation sans debris), le fer (fragilite
#   0.2) ne se transforme donc JAMAIS, la pierre (fragilite 0.7) le fait
#   toujours -- fragilite tranche, jamais un nom de materiau en dur dans ce
#   fichier (le pointeur vers data/transformations.json vient de la
#   declaration DATA de chaque objet, "transformation_fracture", vide pour
#   le fer).
#
# LA RESERVE "integrite" (par objet, {reserve, cout_base: 0.0,
# surcout_action: 0.0}) N'EST JAMAIS AVANCEE PAR depense.gd -- exactement
# comme banc_foudre.gd, Frappe.frapper l'ecrit une seule fois, directement,
# au moment de la frappe ; elle ne decide jamais la fracture (seul
# degats_impact_cumules vs resistance_impact le fait), elle sert seulement a
# exclure un objet deja detruit des cibles futures (objets_frappables, meme
# fonction que banc_foudre.gd, recopiee ICI -- chaque banc porte sa propre
# copie, jamais un import croise entre bancs).
#
# CE QU'ON DOIT VOIR : un objet en fer et un objet en pierre, cote a cote.
# Un clic pres de l'un des deux declenche UN SEUL choc dessus (Frappe.
# selectionner+frapper) : un FLASH blanc bref sur le carre touche et une
# SECOUSSE de camera (retour Yael, chantier initial jugé pas assez lisible
# -- voir RETOUR VISIBILITE ci-dessous) marquent l'INSTANT du choc, avant
# de retomber sur la teinte qui reflete l'etat (degats sur la reserve
# "integrite", ou rouge sombre si fracture). Son label affiche
# resistance_impact/fragilite/degats_impact_cumules/etat. La pierre
# (resistance_impact 2.0) fracture des le premier coup et se transforme
# aussitot : son carre disparait, remplace par une GRAPPE de petits eclats
# dispersés (forme brisee, pas un simple changement de couleur) d'une
# teinte sable claire, nettement contrastee avec le gris intact et le
# rouge de fracture. Le fer (resistance_impact 8.0) encaisse deux coups
# sans rien montrer d'autre qu'une reserve qui baisse, puis fracture au
# troisieme (etat pose, durete/resistance_compression effectives
# visiblement reduites au label) mais reste fer, jamais transforme,
# jamais reduit en morceaux -- seul son carre entier vire au rouge sombre.
#
# RETOUR VISIBILITE (Yael, session ulterieure a la premiere fermeture) :
# le premier jet transformait la pierre en un simple carre a teinte terne,
# jugee pas assez visible. Trois renforts, TOUS cote RENDU (impur, Node),
# AUCUN mecanisme du coeur ni fonction de decision touchee :
# - couleur des eclats recontrastee (sable clair, jamais confondue avec le
#   gris intact ni le rouge de degats/fracture) ;
# - forme qui change : `positions_eclats()` (pure, offsets FIXES -- jamais
#   de hasard non seede, voir CLAUDE.md) rend une grappe de petits carres
#   disperses autour du centre d'origine, remplace le carre unique a la
#   transformation (`_basculer_rendu_eclats`) ;
# - flash + secousse au moment du choc (chaque frappe, pas seulement la
#   fracture) : `offset_secousse(temps_restant, duree_totale)` (pure,
#   fonction DETERMINISTE du temps ecoule -- jamais un Vector2 aleatoire)
#   deplace temporairement la camera, `_teinte(..., flash_actif)` bascule
#   sur blanc le temps du flash avant de retomber sur la teinte normale.
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge les donnees/catalogues partages et
#   fabrique les deux objets (Objet.fabriquer, INCHANGE). _unhandled_input
#   declenche UN choc au clic gauche (selection + degat + cumul + seuil +
#   transformation eventuelle, tout en un seul geste instantane -- rien de
#   continu a faire avancer tick apres tick dans ce banc, contrairement a
#   charge.gd/temperature.gd ailleurs). _process ne fait qu'avancer
#   l'horloge d'affichage et redessiner.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_fracture.gd) : fabriquer_objets/objets_frappables/
#   avancer_frappe/avancer_fracture, plus le texte d'affichage et de log.

const Objet = preload("res://scripts/objet.gd")
const Frappe = preload("res://scripts/frappe.gd")
const SeuilEtat = preload("res://scripts/seuil_etat.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")
const Produit = preload("res://scripts/produit.gd")

const TAILLE := 70.0
const TAILLE_POLICE_LABEL := 13
const TAILLE_ECLAT := TAILLE * 0.35
const COULEUR_ECLATS := Color(0.82, 0.76, 0.6)
const COULEUR_FLASH := Color(1.0, 1.0, 1.0)
const DUREE_FLASH := 0.15
const DUREE_SECOUSSE := 0.2
const AMPLITUDE_SECOUSSE := 8.0
const FREQUENCE_SECOUSSE := 60.0

# Offsets FIXES (jamais de hasard non seede, voir CLAUDE.md) formant une
# grappe irreguliere autour du centre d'origine -- lit comme des fragments
# eparpilles, pas une disposition geometrique parfaite.
const OFFSETS_ECLATS := [
	Vector2(-18.0, -10.0), Vector2(14.0, -16.0), Vector2(-8.0, 14.0),
	Vector2(20.0, 10.0), Vector2(2.0, -22.0),
]

var _config: Dictionary = {}
var _materiaux: Dictionary = {}
var _proprietes_immuables: Array = []
var _objet_physique: Dictionary = {}
var _catalogue_seuils_etat: Dictionary = {}
var _etats: Dictionary = {}
var _catalogue_types: Dictionary = {}
var _transformations: Dictionary = {}
var _objets: Array = []
var _noeuds: Dictionary = {}
var _labels: Dictionary = {}
var _eclats: Dictionary = {}
var _fracture_avant: Dictionary = {}
var _transforme_avant: Dictionary = {}
var _flash_jusqua: Dictionary = {}
var _secousse_jusqua: float = -1.0
var _camera: Camera2D
var _position_camera_base: Vector2 = Vector2.ZERO
var _temps: float = 0.0

func _ready() -> void:
	_config = _charger_json("res://data/banc_fracture.json")
	_materiaux = _charger_json("res://data/materiaux.json")
	_proprietes_immuables = _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", [])
	_objet_physique = _charger_json("res://data/types.json").get("objet_physique", {})
	_catalogue_seuils_etat = _charger_json("res://data/seuils_etat.json")
	_etats = _charger_json("res://data/etats.json")
	_catalogue_types = _charger_json("res://data/types.json")
	_transformations = _charger_json("res://data/transformations.json").get("transformations", {})

	_objets = fabriquer_objets(_config.get("objets", []), _objet_physique, _materiaux, _proprietes_immuables, _config.nom_reserve_integrite, _config.reserve_integrite_defaut)

	for objet in _objets:
		_fracture_avant[objet.id] = false
		_transforme_avant[objet.id] = false
		_creer_rendu_objet(objet)
	_poser_camera()
	_rafraichir_tout()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var pos := get_global_mouse_position()
		var diag := avancer_frappe(_objets, Vector3(pos.x, pos.y, 0.0), _config, _materiaux)
		if diag.is_empty():
			print(_ligne_aucune_cible(_temps))
			return
		print(_ligne_frappe(_temps, diag))
		_flash_jusqua[diag.cible.id] = _temps + DUREE_FLASH
		_secousse_jusqua = _temps + DUREE_SECOUSSE

		var resultat := avancer_fracture(_objets, _catalogue_seuils_etat, _transformations, _catalogue_types, _materiaux, _config.seuil_fragilite_eclats)
		for id in resultat.bascules:
			if _fracture_avant.get(id, false):
				continue
			_fracture_avant[id] = true
			print(_ligne_fracture(_temps, id, _objet_par_id(id), _etats))
		for id in resultat.transformes:
			_transforme_avant[id] = true
			print(_ligne_transforme(_temps, id, _objet_par_id(id)))
			_basculer_rendu_eclats(id)

		_rafraichir_tout()

func _process(delta: float) -> void:
	_temps += delta
	var temps_restant: float = _secousse_jusqua - _temps
	_camera.position = _position_camera_base + offset_secousse(temps_restant, DUREE_SECOUSSE)
	_rafraichir_tout()

func _objet_par_id(id: String) -> Dictionary:
	for objet in _objets:
		if objet.id == id:
			return objet
	return {}

func _rafraichir_tout() -> void:
	for objet in _objets:
		var id: String = objet.id
		var reserve_max: float = _config.reserve_integrite_defaut.get("reserve", 20.0)
		var flash_actif: bool = _temps < _flash_jusqua.get(id, -1.0)
		_noeuds[id].color = _teinte(objet, _transforme_avant.get(id, false), _fracture_avant.get(id, false), reserve_max, flash_actif)
		_labels[id].text = _texte_label(objet)

# ---- Fonctions PURES, testables headless (voir test_banc_fracture.gd) ----

# Construit les objets via Objet.fabriquer (composition fusionnee -- meme
# patron que banc_foudre.gd, "objet_physique" fusionne pour porter
# "temperature", structurelle mais jamais utilisee ici). Ajoute A LA MAIN
# (Objet.fabriquer ne les connait pas) : la reserve "integrite" (patron
# banc_foudre.gd), "degats_impact_cumules" (0.0, la grandeur que
# scripts/seuil_etat.gd va comparer -- SANS elle, proprietes.has()
# rendrait faux et l'entree "fracture" ne se declencherait jamais, voir
# audit_resistance_impact_produit_prealable.md §3), "etats_actifs" (Array
# vide, structurelle pour seuil_etat.gd/etat_effectif.gd) et
# "transformation_fracture" (pointeur DATA vers data/transformations.json,
# vide ou nomme selon la declaration -- jamais un nom de materiau en dur
# ici).
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
		objet.proprietes["degats_impact_cumules"] = 0.0
		objet.proprietes["etats_actifs"] = []
		objet.proprietes["transformation_fracture"] = decl.get("transformation_fracture", "")
		objets.append(objet)
	return objets

# Un objet DEJA DETRUIT (reserve <= 0.0) n'est plus jamais candidat -- meme
# fonction que banc_foudre.gd, recopiee (frappe.gd ne connait aucune
# reserve nommee dans son contrat).
static func objets_frappables(objets: Array, nom_reserve: String) -> Array:
	var vivants: Array = []
	for objet in objets:
		var canal: Dictionary = objet.proprietes.get("reserves", {}).get(nom_reserve, {})
		if canal.get("reserve", 0.0) > 0.0:
			vivants.append(objet)
	return vivants

# UN SEUL choc : selectionne parmi les objets FRAPPABLES a portee de
# "position_source" (le clic, voir en-tete), applique le degat instantane
# (Frappe.frapper, INCHANGE) PUIS ecrit lui-meme le cumul de degat d'impact
# -- geste que frappe.gd ne fait jamais (voir en-tete). Rend {} si aucune
# cible frappable a portee (rien ne se passe). Rend sinon
# { cible, degats, cumul_apres }.
static func avancer_frappe(objets: Array, position_source: Vector3, config: Dictionary, materiaux: Dictionary) -> Dictionary:
	var frappables := objets_frappables(objets, config.nom_reserve_integrite)
	var cible := Frappe.selectionner(frappables, position_source, config.rayon_frappe, config.criteres, materiaux)
	if cible.is_empty():
		return {}

	Frappe.frapper(cible, config.degats, config.nom_reserve_integrite)
	var cumul: float = cible.proprietes.get("degats_impact_cumules", 0.0) + config.degats
	cible.proprietes["degats_impact_cumules"] = cumul

	return {"cible": cible, "degats": config.degats, "cumul_apres": cumul}

# Verifie le franchissement de "fracture" (SeuilEtat.avancer, INCHANGE) sur
# TOUT le monde, puis, pour chaque id fraichement fracture, decide via
# "fragilite" (lue SEULE par ce fichier, aucun mecanisme du coeur ne la
# connait) si l'objet produit des eclats (Produit.transformer, INCHANGE --
# meme geste que banc_corrosion.gd:avancer, proprietes.clear()+merge()) ou
# se contente de rester fracture, deforme sans transformation. Rend
# { bascules, transformes } -- memes formes que celles deja rendues par
# SeuilEtat.avancer, jamais recalculees ici.
static func avancer_fracture(objets: Array, catalogue_seuils_etat: Dictionary, transformations: Dictionary, table_types: Dictionary, materiaux: Dictionary, seuil_fragilite_eclats: float) -> Dictionary:
	var bascules := SeuilEtat.avancer(objets, catalogue_seuils_etat)
	var transformes: Array = []
	for objet in objets:
		if not bascules.has(objet.id):
			continue
		if not objet.proprietes.get("etats_actifs", []).has("fracture"):
			continue
		var fragilite: float = objet.proprietes.get("fragilite", 0.0)
		if fragilite < seuil_fragilite_eclats:
			continue
		var nom_transformation: String = objet.proprietes.get("transformation_fracture", "")
		if nom_transformation.is_empty():
			continue
		var config_produire: Dictionary = transformations.get(nom_transformation, {}).get("a_zero", {}).get("produire", {})
		var nouvelles_proprietes: Dictionary = Produit.transformer(objet.proprietes, config_produire, table_types, materiaux)
		if nouvelles_proprietes.is_empty():
			continue
		objet.proprietes.clear()
		objet.proprietes.merge(nouvelles_proprietes, true)
		transformes.append(objet.id)
	return {"bascules": bascules, "transformes": transformes}

# "flash_actif" GAGNE TOUJOURS (verifie en premier) -- le flash marque
# l'INSTANT du choc, il doit rester visible quel que soit l'etat sous-jacent
# (degats, fracture, ou meme transforme -- un carre d'eclats deja visible
# peut lui aussi flasher au coup suivant si l'objet est encore frappable).
static func _teinte(objet: Dictionary, transforme: bool, fracture: bool, reserve_max: float, flash_actif: bool = false) -> Color:
	if flash_actif:
		return COULEUR_FLASH
	if transforme:
		return COULEUR_ECLATS
	if fracture:
		return Color(0.7, 0.2, 0.15)
	var reserve: float = objet.proprietes.get("reserves", {}).get("integrite", {}).get("reserve", reserve_max)
	var ratio: float = clamp(1.0 - reserve / reserve_max, 0.0, 1.0)
	return Color(0.55, 0.55, 0.6).lerp(Color(0.85, 0.5, 0.15), ratio)

# Grappe de petits eclats disperses -- FIXE, jamais recalculee au hasard
# (memes offsets a chaque appel, meme objet). Pure, testable headless.
static func positions_eclats() -> Array:
	return OFFSETS_ECLATS.duplicate()

# Secousse de camera DETERMINISTE : une fonction pure du temps restant,
# jamais un Vector2 tire au hasard (voir CLAUDE.md, "Aucun hasard non
# seede"). Amplitude decroissante lineairement jusqu'a zero a
# "temps_restant" <= 0.0 -- la camera revient exactement a sa position de
# base, jamais un residu de tremblement fige.
static func offset_secousse(temps_restant: float, duree_totale: float) -> Vector2:
	if temps_restant <= 0.0 or duree_totale <= 0.0:
		return Vector2.ZERO
	var ratio: float = clamp(temps_restant / duree_totale, 0.0, 1.0)
	var amplitude: float = AMPLITUDE_SECOUSSE * ratio
	return Vector2(
		amplitude * sin(temps_restant * FREQUENCE_SECOUSSE),
		amplitude * cos(temps_restant * FREQUENCE_SECOUSSE * 1.3),
	)

static func _texte_label(objet: Dictionary) -> String:
	var proprietes: Dictionary = objet.proprietes
	if not proprietes.has("resistance_impact"):
		return "%s\n(transforme)\nmasse=%.2f" % [objet.id, proprietes.get("masse", 0.0)]
	var fracture: bool = proprietes.get("etats_actifs", []).has("fracture")
	return "%s\nresistance_impact=%.1f\nfragilite=%.2f\ndegats_cumules=%.1f\netat=%s" % [
		objet.id,
		proprietes.get("resistance_impact", 0.0),
		proprietes.get("fragilite", 0.0),
		proprietes.get("degats_impact_cumules", 0.0),
		"fracture" if fracture else "intact",
	]

static func _ligne_frappe(t: float, diag: Dictionary) -> String:
	return "t=%.1fs CHOC : %s frappe (degats=%.2f, cumul=%.2f)" % [t, diag.cible.id, diag.degats, diag.cumul_apres]

static func _ligne_fracture(t: float, id: String, objet: Dictionary, etats: Dictionary) -> String:
	var durete_eff := EtatEffectif.valeur(objet, "durete", etats)
	var compression_eff := EtatEffectif.valeur(objet, "resistance_compression", etats)
	return "t=%.1fs %s : FRACTURE (durete effective -> %.2f, resistance_compression effective -> %.2f)" % [t, id, durete_eff, compression_eff]

static func _ligne_transforme(t: float, id: String, objet: Dictionary) -> String:
	return "t=%.1fs %s : reduit en eclats (masse=%.2f)" % [t, id, objet.proprietes.get("masse", 0.0)]

static func _ligne_aucune_cible(t: float) -> String:
	return "t=%.1fs CHOC : aucune cible frappable a portee du clic" % t

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
	label.add_theme_font_size_override("font_size", TAILLE_POLICE_LABEL)
	add_child(label)
	_labels[id] = label

# Remplace le carre unique de l'objet transforme par une grappe de petits
# eclats disperses (positions_eclats(), pure) -- le noeud principal est
# CACHE, jamais libere (garde son id dans _noeuds pour que _rafraichir_tout
# continue de fonctionner sans branche speciale, meme s'il ne se voit
# plus).
func _basculer_rendu_eclats(id: String) -> void:
	var noeud_principal: ColorRect = _noeuds[id]
	noeud_principal.visible = false
	var centre: Vector2 = noeud_principal.position + noeud_principal.size / 2.0
	var eclats: Array = []
	for offset in positions_eclats():
		var rect := ColorRect.new()
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.size = Vector2(TAILLE_ECLAT, TAILLE_ECLAT)
		rect.position = centre + offset - rect.size / 2.0
		rect.color = COULEUR_ECLATS
		add_child(rect)
		eclats.append(rect)
	_eclats[id] = eclats

func _poser_camera() -> void:
	var decl_camera: Dictionary = _config.get("camera", {})
	var pos: Array = decl_camera.get("position", [0.0, 0.0, 0.0])
	_position_camera_base = Vector2(pos[0], pos[1])
	_camera = Camera2D.new()
	_camera.position = _position_camera_base
	_camera.zoom = Vector2(decl_camera.get("zoom", 0.5), decl_camera.get("zoom", 0.5))
	_camera.enabled = true
	add_child(_camera)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
