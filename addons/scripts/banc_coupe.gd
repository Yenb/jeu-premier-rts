extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_coupe.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1, coexiste avec les autres
# bancs). Existe pour VOIR resistance_cisaillement/tranchant_max
# (data/materiaux.json, DORMANTES avant ce chantier) tourner sur une scene
# observable. Chantier « cisaillement et tranchant -- couper un objet »,
# audit_colonne_mecanique_prealable.md (proprietes #5/#10 -- aucun
# mecanisme candidat avant ce chantier).
#
# AUCUN MECANISME DU COEUR TOUCHE : frappe.gd/produit.gd/objet.gd restent
# inchanges. seuil_etat.gd/etat_effectif.gd NE SONT PAS UTILISES ICI
# (difference assumee avec banc_fracture.gd) : ce chantier ne compare
# jamais deux grandeurs distinctes via un seuil reversible, il epuise une
# reserve puis transforme des qu'elle atteint zero -- exactement le patron
# deja etabli par banc_pourriture.gd/banc_corrosion.gd/banc_solubilite.gd
# (reserve bornee a zero, le cablage verifie lui-meme et appelle
# Produit.transformer, jamais seuil_etat.gd). Ce fichier compose deux
# patrons deja fermes, jamais reecrits :
# - Frappe.selectionner/frapper (INCHANGE, voir banc_fracture.gd) -- QUI
#   est coupe et QUEL degat instantane s'applique. Meme visee que
#   banc_fracture.gd : la POSITION SOURCE de la selection est le CLIC
#   (get_global_mouse_position), pas une position fixe en donnee -- un
#   "rayon_coupe" petit (voir data/banc_coupe.json) fait office de visee.
# - frappe.gd NE MONTE ET NE CALCULE AUCUN degat -- c'est CE FICHIER qui
#   calcule le degat de coupe (tranchant_effectif de l'outil / resistance_
#   cisaillement de la cible, voir degat_coupe()) AVANT d'appeler
#   Frappe.frapper avec cette valeur deja calculee.
# - Produit.transformer (INCHANGE, patron banc_pourriture.gd/
#   banc_corrosion.gd/banc_solubilite.gd) -- appele PAR CE FICHIER, jamais
#   par frappe.gd (qui n'a aucune branche "produire"), des que la reserve
#   d'integrite d'une cible atteint zero. Contrairement a banc_fracture.gd
#   (fragilite tranche entre deformation et transformation), TOUTE cible
#   coupee a bout produit des debris ici -- aucune branche "reste deforme".
#
# L'OUTIL PORTE SA PROPRE GRANDEUR, PROPRE A CE BANC, JAMAIS DANS
# data/materiaux.json : "tranchant_effectif", initialise a tranchant_max
# (fusionne a la fabrication) puis reduit a chaque coupe proportionnellement
# a la durete DE LA CIBLE (durete haute = l'outil s'emousse plus vite,
# voir emoussement()) -- borne a zero (max(0.0, ...), meme discipline que
# depense.gd/frappe.gd:frapper). Un tranchant_effectif a zero rend
# degat_coupe() nul PAR LA SEULE ARITHMETIQUE (0.0 / resistance = 0.0),
# jamais une branche separee "l'outil ne coupe plus".
#
# LA RESERVE "integrite" (par cible, {reserve, cout_base: 0.0,
# surcout_action: 0.0}) N'EST JAMAIS AVANCEE PAR depense.gd -- Frappe.
# frapper l'ecrit directement, bornee a zero. Une fois a zero, la
# transformation consomme "transformation_coupe" (pointeur DATA vers
# data/transformations.json) puis remplace ENTIEREMENT proprietes.clear()+
# merge() -- la cible transformee ne porte plus jamais "reserves" ni
# "transformation_coupe", ce qui rend avancer_transformation() IDEMPOTENT
# sans marqueur supplementaire (voir avancer_transformation()).
#
# CE QU'ON DOIT VOIR : un outil (par defaut en fer, tranchant_max 9.0) et
# trois cibles cote a cote (bois/pierre/fer, un materiau reel chacune). Un
# clic gauche pres d'une cible declenche UNE coupe dessus (Frappe.
# selectionner+frapper, degat = tranchant_effectif / resistance_
# cisaillement) : le bois (resistance_cisaillement 10.0) est coupe
# facilement, la pierre (20.0) resiste, le fer (170.0) resiste beaucoup.
# Chaque coupe emousse l'outil (tranchant_effectif baisse, d'autant plus
# vite que la cible coupee est dure) ; a tranchant_effectif nul, l'outil ne
# coupe plus rien. Un clic droit fait CYCLER l'outil (fer -> bois -> pierre
# -> fer...), lui redonnant un tranchant_effectif frais -- l'outil en bois
# (tranchant_max 2.0) ne coupe presque rien. Quand l'integrite d'une cible
# atteint zero, elle se transforme en debris (copeaux_bois/eclats_pierre/
# limaille_fer) -- son carre change de teinte, son label affiche "(debris)".
# Label sur l'outil : tranchant_max, tranchant_effectif. Label sur chaque
# cible intacte : resistance_cisaillement, integrite. Trace console : une
# ligne par coupe et par transformation.
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge les donnees/catalogues partages et
#   fabrique l'outil et les trois cibles (Objet.fabriquer, INCHANGE).
#   _unhandled_input declenche une coupe au clic gauche (position du clic),
#   fait cycler l'outil au clic droit. _process ne fait qu'avancer
#   l'horloge d'affichage et redessiner.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_coupe.gd) : fabriquer_cibles/fabriquer_outil/degat_coupe/
#   emoussement/cibles_coupables/avancer_coupe/avancer_transformation/
#   materiau_suivant, plus le texte d'affichage et de log.

const Objet = preload("res://scripts/objet.gd")
const Frappe = preload("res://scripts/frappe.gd")
const Produit = preload("res://scripts/produit.gd")

const PROPRIETE_TRANCHANT_MAX := "tranchant_max"
const PROPRIETE_TRANCHANT_EFFECTIF := "tranchant_effectif"
const PROPRIETE_RESISTANCE_CISAILLEMENT := "resistance_cisaillement"
const PROPRIETE_DURETE := "durete"
const ORDRE_MATERIAUX_OUTIL := ["fer", "bois", "pierre"]

const TAILLE := 70.0
const TAILLE_OUTIL := 40.0
const TAILLE_POLICE_LABEL := 13

var _config: Dictionary = {}
var _materiaux: Dictionary = {}
var _proprietes_immuables: Array = []
var _objet_physique: Dictionary = {}
var _transformations: Dictionary = {}
var _catalogue_types: Dictionary = {}
var _cibles: Array = []
var _outil: Dictionary = {}
var _noeuds: Dictionary = {}
var _labels: Dictionary = {}
var _noeud_outil: ColorRect
var _label_outil: Label
var _transforme_avant: Dictionary = {}
var _temps: float = 0.0

func _ready() -> void:
	_config = _charger_json("res://data/banc_coupe.json")
	_materiaux = _charger_json("res://data/materiaux.json")
	_proprietes_immuables = _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", [])
	_objet_physique = _charger_json("res://data/types.json").get("objet_physique", {})
	_catalogue_types = _charger_json("res://data/types.json")
	_transformations = _charger_json("res://data/transformations.json").get("transformations", {})

	_cibles = fabriquer_cibles(_config.get("cibles", []), _objet_physique, _materiaux, _proprietes_immuables, _config.nom_reserve_integrite, _config.reserve_integrite_defaut)
	for cible in _cibles:
		_transforme_avant[cible.id] = false
		_creer_rendu_cible(cible)

	var pos_outil: Array = _config.get("position_outil", [0.0, 0.0, 0.0])
	_outil = fabriquer_outil(_config.materiau_outil_defaut, Vector3(pos_outil[0], pos_outil[1], pos_outil[2]), _objet_physique, _materiaux, _proprietes_immuables)
	_creer_rendu_outil()

	_poser_camera()
	_rafraichir_tout()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var pos := get_global_mouse_position()
		var diag := avancer_coupe(_cibles, _outil, Vector3(pos.x, pos.y, 0.0), _config, _materiaux)
		if diag.is_empty():
			print(_ligne_aucune_cible(_temps))
			return
		print(_ligne_coupe(_temps, diag))

		var transformes := avancer_transformation(_cibles, _transformations, _catalogue_types, _materiaux, _config.nom_reserve_integrite)
		for id in transformes:
			if _transforme_avant.get(id, false):
				continue
			_transforme_avant[id] = true
			print(_ligne_transforme(_temps, id, _cible_par_id(id)))

		_rafraichir_tout()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var nom_suivant := materiau_suivant(_outil.proprietes.get("materiau_outil", _config.materiau_outil_defaut), ORDRE_MATERIAUX_OUTIL)
		var pos_outil: Array = _config.get("position_outil", [0.0, 0.0, 0.0])
		_outil = fabriquer_outil(nom_suivant, Vector3(pos_outil[0], pos_outil[1], pos_outil[2]), _objet_physique, _materiaux, _proprietes_immuables)
		print(_ligne_changement_outil(_temps, nom_suivant))
		_rafraichir_tout()

func _process(delta: float) -> void:
	_temps += delta
	_rafraichir_tout()

func _cible_par_id(id: String) -> Dictionary:
	for cible in _cibles:
		if cible.id == id:
			return cible
	return {}

func _rafraichir_tout() -> void:
	for cible in _cibles:
		var id: String = cible.id
		_noeuds[id].color = _teinte_cible(cible, _transforme_avant.get(id, false), _config.get("couleurs", {}).get(id, [0.6, 0.6, 0.6]), _config.get("couleur_debris", [0.35, 0.32, 0.28]))
		_labels[id].text = _texte_cible(cible)
	_label_outil.text = _texte_outil(_outil)

# ---- Fonctions PURES, testables headless (voir test_banc_coupe.gd) ----

# Construit les trois cibles via Objet.fabriquer (composition fusionnee --
# meme patron que banc_fracture.gd:fabriquer_objets). Ajoute A LA MAIN
# (Objet.fabriquer ne les connait pas) : la reserve "integrite" (meme
# patron que banc_fracture.gd), "etats_actifs" (Array vide, structurelle
# pour le reste du depot meme si non consommee ici) et
# "transformation_coupe" (pointeur DATA vers data/transformations.json,
# JAMAIS vide contrairement a banc_fracture.gd -- toute cible coupee a
# bout produit des debris dans ce chantier).
static func fabriquer_cibles(declarations: Array, objet_physique: Dictionary, materiaux: Dictionary, proprietes_immuables: Array, nom_reserve_integrite: String, reserve_integrite_defaut: Dictionary) -> Array:
	var table: Dictionary = {"objet_physique": objet_physique}
	for decl in declarations:
		table[decl.id] = {"herite": ["objet_physique"], "composition": decl.composition}
	var cibles: Array = []
	for decl in declarations:
		var pos: Array = decl.position
		var cible := Objet.fabriquer(decl.id, decl.id, Vector3(pos[0], pos[1], pos[2]), table, materiaux, proprietes_immuables)
		if cible.is_empty():
			continue
		cible.proprietes["reserves"] = {nom_reserve_integrite: reserve_integrite_defaut.duplicate(true)}
		cible.proprietes["etats_actifs"] = []
		cible.proprietes["transformation_coupe"] = decl.get("transformation_coupe", "")
		cibles.append(cible)
	return cibles

# Construit l'outil via Objet.fabriquer, a partir d'un SEUL materiau --
# "tranchant_effectif" est initialise a "tranchant_max" (fusionne a la
# fabrication) : un outil neuf coupe a son plein potentiel. Rend {} si la
# fabrication echoue (materiau inconnu -- meme severite qu'Objet.fabriquer
# partout ailleurs).
static func fabriquer_outil(nom_materiau: String, position: Vector3, objet_physique: Dictionary, materiaux: Dictionary, proprietes_immuables: Array) -> Dictionary:
	var table: Dictionary = {"objet_physique": objet_physique, "outil": {"herite": ["objet_physique"], "composition": [{"materiau": nom_materiau, "volume": 1.0}]}}
	var outil := Objet.fabriquer("outil", "outil", position, table, materiaux, proprietes_immuables)
	if outil.is_empty():
		return {}
	outil.proprietes["etats_actifs"] = []
	outil.proprietes["materiau_outil"] = nom_materiau
	outil.proprietes[PROPRIETE_TRANCHANT_EFFECTIF] = outil.proprietes.get(PROPRIETE_TRANCHANT_MAX, 0.0)
	return outil

# degat = tranchant_effectif / resistance_cisaillement -- EXACTEMENT
# l'enonce du chantier. Une resistance_cisaillement nulle ou negative
# (donnee incoherente, jamais produite par les materiaux reels de ce
# depot) rendrait 0.0 plutot que de diviser par zero silencieusement --
# garde defensive, jamais un chemin reellement atteint par une fiche
# materiau reelle. Un tranchant_effectif a zero rend deja 0.0 par la seule
# arithmetique, sans branche separee.
static func degat_coupe(tranchant_effectif: float, resistance_cisaillement: float) -> float:
	if resistance_cisaillement <= 0.0:
		return 0.0
	return tranchant_effectif / resistance_cisaillement

# emoussement = taux_emoussement_base * durete_cible -- durete haute
# emousse plus vite. Formule volontairement independante du degat inflige
# (contrairement a degat_coupe) : meme un coup qui n'entame presque rien
# (tranchant deja tres bas) use l'outil de la meme quantite qu'un coup a
# pleine puissance sur la MEME cible -- c'est la durete rencontree, pas
# l'efficacite du coup, qui use le tranchant.
static func emoussement(taux_emoussement_base: float, durete_cible: float) -> float:
	return taux_emoussement_base * durete_cible

# Une cible DEJA REDUITE A ZERO (reserve <= 0.0) n'est plus jamais
# candidate -- meme fonction que banc_fracture.gd:objets_frappables,
# recopiee (frappe.gd ne connait aucune reserve nommee dans son contrat).
static func cibles_coupables(cibles: Array, nom_reserve: String) -> Array:
	var vivantes: Array = []
	for cible in cibles:
		var canal: Dictionary = cible.proprietes.get("reserves", {}).get(nom_reserve, {})
		if canal.get("reserve", 0.0) > 0.0:
			vivantes.append(cible)
	return vivantes

# UNE SEULE coupe : selectionne parmi les cibles COUPABLES a portee de
# "position_source" (le clic), calcule le degat (degat_coupe(), CE FICHIER
# SEUL -- frappe.gd ne sait rien de "tranchant" ni de "resistance_
# cisaillement") puis l'applique via Frappe.frapper (INCHANGE). Emousse
# ensuite l'outil (emoussement(), proportionnel a la durete de LA CIBLE
# TOUCHEE), borne a zero -- meme discipline que Frappe.frapper. Rend {} si
# aucune cible coupable a portee (rien ne se passe). Rend sinon
# { cible, degats, tranchant_effectif_apres }.
static func avancer_coupe(cibles: Array, outil: Dictionary, position_source: Vector3, config: Dictionary, materiaux: Dictionary) -> Dictionary:
	var coupables := cibles_coupables(cibles, config.nom_reserve_integrite)
	var cible := Frappe.selectionner(coupables, position_source, config.rayon_coupe, config.criteres, materiaux)
	if cible.is_empty():
		return {}

	var tranchant_effectif: float = outil.proprietes.get(PROPRIETE_TRANCHANT_EFFECTIF, 0.0)
	var resistance: float = cible.proprietes.get(PROPRIETE_RESISTANCE_CISAILLEMENT, 0.0)
	var degat := degat_coupe(tranchant_effectif, resistance)
	Frappe.frapper(cible, degat, config.nom_reserve_integrite)

	var durete_cible: float = cible.proprietes.get(PROPRIETE_DURETE, 0.0)
	var usure := emoussement(config.taux_emoussement, durete_cible)
	outil.proprietes[PROPRIETE_TRANCHANT_EFFECTIF] = max(0.0, tranchant_effectif - usure)

	return {"cible": cible, "degats": degat, "tranchant_effectif_apres": outil.proprietes[PROPRIETE_TRANCHANT_EFFECTIF]}

# Verifie, pour CHAQUE cible, si sa reserve d'integrite est a zero -- si
# oui, appelle Produit.transformer (INCHANGE, meme geste que
# banc_corrosion.gd:avancer -- proprietes.clear()+merge()) via son
# "transformation_coupe". IDEMPOTENT SANS MARQUEUR SUPPLEMENTAIRE : une
# cible deja transformee ne porte plus "reserves" (canal.get("reserve",
# 0.0) retombe a 0.0 par defaut, semblerait redeclencher) MAIS ne porte
# plus non plus "transformation_coupe" (efface par proprietes.clear()) --
# le second garde (nom_transformation vide) arrete le second appel avant
# toute reecriture. Rend l'Array des id fraichement transformes.
static func avancer_transformation(cibles: Array, transformations: Dictionary, table_types: Dictionary, materiaux: Dictionary, nom_reserve: String) -> Array:
	var transformes: Array = []
	for cible in cibles:
		var canal: Dictionary = cible.proprietes.get("reserves", {}).get(nom_reserve, {})
		if canal.get("reserve", 0.0) > 0.0:
			continue
		var nom_transformation: String = cible.proprietes.get("transformation_coupe", "")
		if nom_transformation.is_empty():
			continue
		var config_produire: Dictionary = transformations.get(nom_transformation, {}).get("a_zero", {}).get("produire", {})
		var nouvelles_proprietes: Dictionary = Produit.transformer(cible.proprietes, config_produire, table_types, materiaux)
		if nouvelles_proprietes.is_empty():
			continue
		cible.proprietes.clear()
		cible.proprietes.merge(nouvelles_proprietes, true)
		transformes.append(cible.id)
	return transformes

# Materiau suivant dans l'ordre cyclique (fer -> bois -> pierre -> fer...).
# Un materiau absent de l'ordre (jamais le cas en pratique) reprend au
# debut, jamais une erreur -- garde triviale, pure.
static func materiau_suivant(nom_actuel: String, ordre: Array) -> String:
	var idx: int = ordre.find(nom_actuel)
	if idx == -1:
		return ordre[0]
	return ordre[(idx + 1) % ordre.size()]

static func _texte_cible(cible: Dictionary) -> String:
	var proprietes: Dictionary = cible.proprietes
	if not proprietes.has(PROPRIETE_RESISTANCE_CISAILLEMENT):
		return "%s\n(debris)\nmasse=%.2f" % [cible.id, proprietes.get("masse", 0.0)]
	var reserve: float = proprietes.get("reserves", {}).get("integrite", {}).get("reserve", 0.0)
	return "%s\nresistance_cisaillement=%.1f\nintegrite=%.2f" % [
		cible.id,
		proprietes.get(PROPRIETE_RESISTANCE_CISAILLEMENT, 0.0),
		reserve,
	]

static func _texte_outil(outil: Dictionary) -> String:
	var proprietes: Dictionary = outil.get("proprietes", {})
	return "outil (%s)\ntranchant_max=%.1f\ntranchant_effectif=%.2f" % [
		proprietes.get("materiau_outil", "?"),
		proprietes.get(PROPRIETE_TRANCHANT_MAX, 0.0),
		proprietes.get(PROPRIETE_TRANCHANT_EFFECTIF, 0.0),
	]

static func _ligne_coupe(t: float, diag: Dictionary) -> String:
	return "t=%.1fs COUPE : %s (degats=%.3f, tranchant_effectif->%.3f)" % [t, diag.cible.id, diag.degats, diag.tranchant_effectif_apres]

static func _ligne_transforme(t: float, id: String, cible: Dictionary) -> String:
	return "t=%.1fs %s : reduit en debris (masse=%.2f)" % [t, id, cible.proprietes.get("masse", 0.0)]

static func _ligne_aucune_cible(t: float) -> String:
	return "t=%.1fs COUPE : aucune cible coupable a portee du clic" % t

static func _ligne_changement_outil(t: float, nom_materiau: String) -> String:
	return "t=%.1fs OUTIL : change pour '%s' (tranchant frais)" % [t, nom_materiau]

# ---- Rendu (impur, Node) -- aucune decision, seulement la construction
# des noeuds et la camera.

func _teinte_cible(cible: Dictionary, transforme: bool, couleur_intacte: Array, couleur_debris: Array) -> Color:
	if transforme:
		return Color(couleur_debris[0], couleur_debris[1], couleur_debris[2])
	return Color(couleur_intacte[0], couleur_intacte[1], couleur_intacte[2])

func _creer_rendu_cible(cible: Dictionary) -> void:
	var id: String = cible.id
	var centre := Vector2(cible.position.x, cible.position.y)

	var noeud := ColorRect.new()
	noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noeud.size = Vector2(TAILLE, TAILLE)
	noeud.position = centre - noeud.size / 2.0
	add_child(noeud)
	_noeuds[id] = noeud

	var label := Label.new()
	label.position = centre - Vector2(TAILLE / 2.0, TAILLE / 2.0 + 60.0)
	label.add_theme_font_size_override("font_size", TAILLE_POLICE_LABEL)
	add_child(label)
	_labels[id] = label

func _creer_rendu_outil() -> void:
	var centre := Vector2(_outil.position.x, _outil.position.y)

	_noeud_outil = ColorRect.new()
	_noeud_outil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_noeud_outil.size = Vector2(TAILLE_OUTIL, TAILLE_OUTIL)
	_noeud_outil.position = centre - _noeud_outil.size / 2.0
	_noeud_outil.color = Color(0.75, 0.75, 0.2)
	add_child(_noeud_outil)

	_label_outil = Label.new()
	_label_outil.position = centre - Vector2(TAILLE_OUTIL / 2.0, TAILLE_OUTIL / 2.0 + 60.0)
	_label_outil.add_theme_font_size_override("font_size", TAILLE_POLICE_LABEL)
	add_child(_label_outil)

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
