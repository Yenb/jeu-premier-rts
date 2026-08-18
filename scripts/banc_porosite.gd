extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_porosite.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1). Chantier « banc_porosite --
# un banc transversal » : montre qu'UNE SEULE propriete materiau (porosite)
# traverse DEUX mecanismes independants EN MEME TEMPS -- l'humidite
# (charge.gd, meme patron que banc_humidite.gd) et la combustion (objet.gd/
# depense.gd, meme patron que banc_combustible.gd). En plus, chaque objet EN
# FEU sert lui-meme de source de chaleur pour scripts/temperature.gd (meme
# patron de source que banc_temperature.gd), pour un troisieme label affiche
# en continu -- CE mecanisme ne differe jamais entre les deux objets
# (conductivite_thermique/densite identiques), il n'est pas la demonstration
# de ce chantier, seulement un affichage complementaire.
#
# AUCUN MECANISME DU COEUR TOUCHE : charge.gd/etat_duree.gd/etat_effectif.gd/
# depense.gd/combustible.gd/temperature.gd/propagation.gd/perception.gd/
# agir.gd/produit.gd restent inchanges, de meme que banc_humidite.gd/
# banc_combustible.gd (ni l'un ni l'autre n'est appele ni modifie -- ce
# fichier RECOPIE localement le sous-ensemble de fonctions pures dont il a
# besoin, meme discipline que banc_humidite.gd recopie deja
# objet.gd:_moyenne_ponderee_volume plutot que d'appeler la fonction privee
# d'un autre fichier).
#
# CE QU'ON DOIT VOIR : deux objets cote a cote, `porosite_basse` (porosite
# 0.05) et `porosite_haute` (porosite 0.9, data/materiaux.json --
# absorption_humidite/inflammabilite/pouvoir_calorifique/
# conductivite_thermique/densite IDENTIQUES entre les deux, seule porosite
# diverge), deja EN FEU des le demarrage (brule: true, comme
# banc_combustible -- aucune propagation, aucun colon) ET exposes en
# permanence a la MEME source d'humidite fixe, a distance IDENTIQUE des deux
# objets -- la source est ACTIVABLE/DESACTIVABLE au clic gauche, MEME GESTE
# que banc_humidite.gd (basculer_source, ligne de log a chaque bascule).
# porosite_haute doit devenir MOUILLE avant porosite_basse (poids_receveur_
# humidite plus haut, meme formule que banc_humidite.gd) ET doit EPUISER sa
# reserve de combustible avant porosite_basse (cout_base_effectif plus haut,
# meme formule que objet.gd:_fabriquer_reserve_combustible) -- LA MEME
# porosite cause les deux ecarts, observable en parallele sur les deux
# fronts. Chaque objet affiche en continu : sa porosite, son etat mouille ou
# non, sa charge d'humidite, ce qu'il reste de sa reserve de combustible
# (absolu et proportion), et sa temperature. La console imprime une phrase
# par changement significatif (exposition posee/retiree, mouille pose/
# expire, extinction), NOMMANT la porosite de l'objet a chaque fois -- pour
# lire a l'oeil, dans le log, que c'est la meme grandeur qui explique les
# deux evenements.
#
# LIMITE STRICTE (rappel explicite du chantier) : ce fichier cable
# UNIQUEMENT ce banc -- aucun mecanisme neuf, aucune extension du coeur, ni
# des bancs existants (banc_humidite.gd/banc_combustible.gd/
# banc_temperature.gd non touches).
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready construit la source, le profil de chaleur commun
#   et les deux objets (Objet.fabriquer, composition fusionnee -- meme
#   patron que banc_humidite.gd/banc_combustible.gd). _process appelle
#   UNIQUEMENT avancer() (fonction statique, ci-dessous) puis lit ses
#   resultats pour l'affichage/la console -- jamais un calcul refait ici
#   (regle CLAUDE.md : la logique enfermee dans _process doit en sortir en
#   fonction statique testable).
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_porosite.gd) : causes_de/causes_ponderees/porosite_ponderee/
#   poids_receveur_humidite/basculer_source (recopiees de banc_humidite.gd,
#   memes formules/meme geste, jamais un appel croise entre bancs)/
#   sources_chaleur/fabriquer_objets/avancer/diagnostiquer, plus le texte
#   d'affichage et de log.

const Objet = preload("res://scripts/objet.gd")
const Charge = preload("res://scripts/charge.gd")
const Depense = preload("res://scripts/depense.gd")
const Combustible = preload("res://scripts/combustible.gd")
const EtatDuree = preload("res://scripts/etat_duree.gd")
const Temperature = preload("res://scripts/temperature.gd")

const TAILLE := 90.0
const HAUTEUR_BARRE := 10.0
const TAILLE_SOURCE := 30.0
const NOM_RESERVE := "combustible"

var _config: Dictionary = {}
var _etats: Dictionary = {}
var _materiaux: Dictionary = {}
var _seuils_combustible: Dictionary = {}
var _catalogue_temperature: Dictionary = {}
var _source: Dictionary = {}
var _objets: Array = []
var _noeuds: Dictionary = {}
var _barres_fond: Dictionary = {}
var _barres_remplies: Dictionary = {}
var _labels: Dictionary = {}
var _noeud_source: ColorRect
var _label_source: Label
var _mouille_avant: Dictionary = {}
var _expose_avant: Dictionary = {}
var _eteints: Dictionary = {}
var _temps: float = 0.0

func _ready() -> void:
	_config = _charger_json("res://data/banc_porosite.json")
	_etats = _charger_json("res://data/etats.json")
	_materiaux = _charger_json("res://data/materiaux.json")
	_seuils_combustible = _charger_json("res://data/seuils_combustible.json")
	_catalogue_temperature = _charger_json("res://data/temperature.json")
	var reserve_combustible := _charger_json("res://data/reserve_combustible_composition.json")
	var proprietes_immuables: Array = _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", [])
	var ambiante: float = _catalogue_temperature.get("defaut", {}).get("ambiante", 20.0)

	var decl_source: Dictionary = _config.get("source_humidite", {})
	var pos_source: Array = decl_source.get("position", [0.0, 0.0, 0.0])
	_source = {
		"id": decl_source.get("id", "source"),
		"position": Vector3(pos_source[0], pos_source[1], pos_source[2]),
		"proprietes": {_config.propriete_cause: true},
	}

	_objets = fabriquer_objets(_config.get("objets", []), _materiaux, proprietes_immuables, reserve_combustible, _config, ambiante)
	for objet in _objets:
		_mouille_avant[objet.id] = false
		_expose_avant[objet.id] = false
		_creer_rendu_objet(objet)

	_creer_rendu_source()
	_poser_camera()

	for objet in _objets:
		var diag := diagnostiquer(objet, _config, _etats, _materiaux, NOM_RESERVE)
		print(_ligne_pose_initiale(objet.id, diag))
	_rafraichir_tout()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		basculer_source(_source, _config.propriete_cause)
		var actif: bool = _source.proprietes.get(_config.propriete_cause, false)
		print(_ligne_source(_temps, actif))
		_rafraichir_tout()

func _process(delta: float) -> void:
	_temps += delta
	var resultat := avancer(_objets, _source, delta, _config, _etats, _materiaux, _seuils_combustible, _config.feu, _catalogue_temperature)

	for id in resultat.extinctions:
		if _eteints.has(id):
			continue
		_eteints[id] = true
		var objet := _par_id(_objets, id)
		var porosite := porosite_ponderee(objet, _materiaux, _config.propriete_porosite)
		print(_ligne_extinction(_temps, id, porosite))

	for objet in _objets:
		var id: String = objet.id
		var porosite: float = porosite_ponderee(objet, _materiaux, _config.propriete_porosite)
		var expose: bool = objet.proprietes.get(_config.declencheur_expose, false)
		if expose != _expose_avant.get(id, false):
			var canal: Dictionary = objet.proprietes.get("etats", {}).get(_config.nom_canal, {})
			print(_ligne_expose(_temps, id, expose, canal.get("charge", 0.0), canal.get("seuil", 0.0), porosite))
			_expose_avant[id] = expose

		var mouille: bool = objet.proprietes.get("etats_actifs", []).has(_config.nom_etat)
		if mouille != _mouille_avant.get(id, false):
			print(_ligne_mouille(_temps, id, mouille, porosite))
			_mouille_avant[id] = mouille

	_rafraichir_tout()

func _rafraichir_tout() -> void:
	for objet in _objets:
		var id: String = objet.id
		var diag := diagnostiquer(objet, _config, _etats, _materiaux, NOM_RESERVE)
		_noeuds[id].color = _teinte_pour(diag)
		var ratio: float = diag.reserve_proportion
		_barres_remplies[id].size.x = _barres_fond[id].size.x * ratio
		_labels[id].text = _texte_label(id, diag)
	var actif: bool = _source.proprietes.get(_config.propriete_cause, false)
	_noeud_source.color = Color(0.15, 0.55, 0.95) if actif else Color(0.4, 0.4, 0.4)
	_label_source.text = "source : %s (clic pour basculer)" % ("ACTIVE" if actif else "INACTIVE")

# ---- Fonctions PURES, testables headless (voir test_banc_porosite.gd) ----

# Meme geste que banc_humidite.gd:causes_de -- filtre les objets portant
# "propriete_cause" a vrai, rend { position }. RECOPIEE localement (jamais
# un appel croise vers banc_humidite.gd) -- meme discipline que
# banc_humidite.gd recopie deja objet.gd:_moyenne_ponderee_volume.
static func causes_de(objets: Array, propriete_cause: String) -> Array:
	var causes: Array = []
	for chose in objets:
		if chose.proprietes.get(propriete_cause, false):
			causes.append({"position": chose.position})
	return causes

# Meme geste que banc_humidite.gd:causes_ponderees.
static func causes_ponderees(causes: Array, poids: float) -> Array:
	var resultat: Array = []
	for cause in causes:
		resultat.append({"position": cause.position, "poids": cause.get("poids", 1.0) * poids})
	return resultat

# Meme geste que banc_humidite.gd:porosite_ponderee (meme formule que
# objet.gd:_moyenne_ponderee_volume, recopiee localement) -- moyenne
# ponderee par volume d'une propriete nommee sur la composition de l'objet.
# "propriete_porosite" vide, objet sans "composition", ou catalogue
# "materiaux" vide : rend 0.0, chemin mort.
static func porosite_ponderee(objet: Dictionary, materiaux: Dictionary, propriete_porosite: String) -> float:
	if propriete_porosite.is_empty() or materiaux.is_empty():
		return 0.0
	var composition: Array = objet.proprietes.get("composition", [])
	if composition.is_empty():
		return 0.0
	var somme_ponderee := 0.0
	var somme_volume := 0.0
	for element in composition:
		var nom_materiau: String = element.get("materiau", "")
		var volume: float = float(element.get("volume", 0.0))
		var fiche: Dictionary = materiaux.get(nom_materiau, {})
		somme_ponderee += float(fiche.get(propriete_porosite, 0.0)) * volume
		somme_volume += volume
	if somme_volume <= 0.0:
		return 0.0
	return somme_ponderee / somme_volume

# Meme formule que banc_humidite.gd:poids_receveur_humidite -- poids_receveur
# = absorption_humidite * (1.0 + facteur_porosite * porosite_effective).
static func poids_receveur_humidite(objet: Dictionary, materiaux: Dictionary, config: Dictionary) -> float:
	var absorption: float = objet.proprietes.get(config.propriete_absorption, 0.0)
	var facteur_porosite: float = config.get("facteur_porosite", 0.0)
	var porosite: float = porosite_ponderee(objet, materiaux, config.get("propriete_porosite", ""))
	return absorption * (1.0 + facteur_porosite * porosite)

# Meme geste que banc_humidite.gd:basculer_source -- inverse la cause sur la
# source (clic gauche, voir _unhandled_input). Pure, mute seulement le
# Dictionary "source" recu, jamais un etat cache du Node.
static func basculer_source(source: Dictionary, propriete_cause: String) -> void:
	source.proprietes[propriete_cause] = not source.proprietes.get(propriete_cause, false)

# Les sources de chaleur de ce tick pour scripts/temperature.gd, dans la
# forme attendue par locale()/avancer() (voir temperature.gd, en-tete :
# "sources... construit et possede ENTIEREMENT par l'appelant") -- CHAQUE
# objet encore "brule" rayonne depuis SA PROPRE position, meme profil
# rayon/temperature/force pour les deux (config_feu, commun) ; un objet
# eteint ("brule" absent ou faux) sort du tableau, ne rayonne plus.
static func sources_chaleur(objets: Array, config_feu: Dictionary) -> Array:
	var sources: Array = []
	for objet in objets:
		if objet.proprietes.get("brule", false):
			sources.append({
				"position": objet.position,
				"rayon": config_feu.get("rayon", 0.0),
				"temperature": config_feu.get("temperature", 0.0),
				"force": config_feu.get("force", 1.0),
			})
	return sources

# UN PAS de simulation complet, les trois mecanismes en parallele sur la
# meme liste d'objets :
# 1) COMBUSTION -- Depense.avancer (mecanisme reel, non touche) ponctionne
#    la reserve de chaque objet ; un objet qui franchit le seuil
#    "epuisement" (data/seuils_combustible.json, deja charge par
#    l'appelant) perd "brule" -- ajoute a "extinctions" (Array d'id).
# 2) HUMIDITE -- meme geste que banc_humidite.gd:avancer, UN appel a
#    Charge.avancer PAR OBJET (charge.gd n'a aucun coefficient par
#    receveur), pondere par poids_receveur_humidite de CET objet ; le
#    marqueur d'exposition, s'il reste vrai ce tick, repose "mouille"
#    (EtatDuree.poser, remise a 1.0, jamais un cumul) ; EtatDuree.avancer
#    tourne UNE FOIS pour l'ensemble des objets (decroissance/retrait
#    progressifs).
# 3) TEMPERATURE -- sources_chaleur (ci-dessus) puis Temperature.avancer
#    (mecanisme reel, non touche), sur les objets ENCORE "brule" APRES
#    l'etape combustion -- un objet qui vient de s'eteindre ce tick ne
#    rayonne deja plus.
# Rend { extinctions: Array d'id ayant perdu "brule" ce pas, bascules:
# Array d'id ayant franchi le seuil d'exposition d'humidite ce pas,
# expirees: Array de { id, nom_etat } retires par decroissance ce pas }.
static func avancer(objets: Array, source: Dictionary, delta: float, config: Dictionary, etats: Dictionary, materiaux: Dictionary, seuils_combustible: Dictionary, config_feu: Dictionary, catalogue_temperature: Dictionary) -> Dictionary:
	var franchis: Array = Depense.avancer(objets, delta, seuils_combustible)
	var extinctions: Array = []
	for id in franchis:
		var objet := _par_id(objets, id)
		if not objet.is_empty() and not objet.proprietes.get("brule", false):
			extinctions.append(id)

	var causes_base := causes_de([source], config.propriete_cause)
	var bascules: Array = []
	for objet in objets:
		var poids_receveur := poids_receveur_humidite(objet, materiaux, config)
		var causes := causes_ponderees(causes_base, poids_receveur)
		var b := Charge.avancer([objet], causes, delta)
		if not b.is_empty():
			bascules.append(objet.id)
		if objet.proprietes.get(config.declencheur_expose, false):
			EtatDuree.poser(objet, config.nom_etat, etats)
	var expirees := EtatDuree.avancer(objets, delta, etats)

	var sources := sources_chaleur(objets, config_feu)
	Temperature.avancer(objets, sources, delta, catalogue_temperature)

	return {"extinctions": extinctions, "bascules": bascules, "expirees": expirees}

static func _par_id(objets: Array, id: String) -> Dictionary:
	for objet in objets:
		if objet.id == id:
			return objet
	return {}

# Construit les deux objets via Objet.fabriquer (composition fusionnee,
# meme patron que banc_humidite.gd/banc_combustible.gd : un catalogue LOCAL,
# une entree par id, la cle "composition" seule) -- "materiaux"/
# "proprietes_immuables"/"reserve_combustible" reels, jamais une table
# locale (fusionne absorption_humidite/conductivite_thermique via
# proprietes_immuables, la capacite/le cout_base effectif via
# reserve_combustible, meme geste que les deux bancs cites). Un objet dont
# la fabrication est REFUSEE (materiau absent, voir objet.gd) est ignore
# (push_error deja emis par Objet.fabriquer). Chaque objet recoit ENSUITE,
# comme banc_changement_etat.gd (catalogue local sans "herite" -- le paquet
# objet_physique n'est jamais fusionne, donc "temperature" n'existe pas
# encore) : "temperature" (a l'ambiante, requis par temperature.gd),
# "brule" (deja en feu, comme banc_combustible.gd), son propre canal
# d'humidite (duplique, jamais partage) et "etats_actifs" vide.
static func fabriquer_objets(declarations: Array, materiaux: Dictionary, proprietes_immuables: Array, reserve_combustible: Dictionary, config: Dictionary, ambiante: float) -> Array:
	var catalogue: Dictionary = {}
	for decl in declarations:
		catalogue[decl.id] = {"composition": decl.composition}
	var objets: Array = []
	for decl in declarations:
		var pos: Array = decl.position
		var objet := Objet.fabriquer(decl.id, decl.id, Vector3(pos[0], pos[1], pos[2]), catalogue, materiaux, proprietes_immuables, reserve_combustible)
		if objet.is_empty():
			push_error("banc_porosite.gd : fabrication refusee pour '%s'" % decl.id)
			continue
		objet.proprietes["temperature"] = ambiante
		objet.proprietes["brule"] = true
		objet.proprietes["etats"] = {config.nom_canal: config.canal_defaut.duplicate(true)}
		objet.proprietes["etats_actifs"] = []
		objets.append(objet)
	return objets

# Diagnostic d'affichage, PUR : lit uniquement des valeurs deja calculees
# par charge.gd/etat_duree.gd/combustible.gd, ne reimplemente jamais leur
# loi (meme doctrine que banc_humidite.gd:diagnostiquer/
# banc_combustible.gd:_rafraichir_tout). Rend { porosite, mouille (bool),
# charge, seuil, reserve_absolu, reserve_proportion, temperature, brule
# (bool) }.
static func diagnostiquer(objet: Dictionary, config: Dictionary, etats: Dictionary, materiaux: Dictionary, nom_reserve: String) -> Dictionary:
	var canal: Dictionary = objet.proprietes.get("etats", {}).get(config.nom_canal, {})
	var mouille: bool = objet.proprietes.get("etats_actifs", []).has(config.nom_etat)
	var restant := Combustible.restant(objet, nom_reserve)
	return {
		"porosite": porosite_ponderee(objet, materiaux, config.propriete_porosite),
		"mouille": mouille,
		"charge": canal.get("charge", 0.0),
		"seuil": canal.get("seuil", 0.0),
		"reserve_absolu": restant.absolu,
		"reserve_proportion": restant.proportion,
		"temperature": objet.proprietes.get("temperature", 0.0),
		"brule": objet.proprietes.get("brule", false),
	}

static func _teinte_pour(diag: Dictionary) -> Color:
	var p: float = clamp(diag.reserve_proportion, 0.0, 1.0)
	var base := Color(0.3 + 0.6 * p, 0.15 + 0.25 * p, 0.05) if diag.brule else Color(0.25, 0.15, 0.1)
	if diag.mouille:
		return base.lerp(Color(0.15, 0.35, 0.85), 0.5)
	return base

static func _texte_label(id: String, diag: Dictionary) -> String:
	return "%s\nporosite=%.2f\nmouille=%s\ncharge=%.2f/%.2f\nreserve=%.2f (%.0f%%)\ntemperature=%.1f" % [
		id, diag.porosite, "oui" if diag.mouille else "non", diag.charge, diag.seuil,
		diag.reserve_absolu, diag.reserve_proportion * 100.0, diag.temperature
	]

static func _ligne_pose_initiale(id: String, diag: Dictionary) -> String:
	return "t=0.0s %s : porosite=%.2f reserve_initiale=%.2f seuil_humidite=%.2f" % [id, diag.porosite, diag.reserve_absolu, diag.seuil]

static func _ligne_expose(t: float, id: String, actif: bool, charge: float, seuil: float, porosite: float) -> String:
	return "t=%.1fs %s (porosite=%.2f) : expose_humidite %s (charge=%.2f, seuil=%.2f)" % [
		t, id, porosite, "POSE" if actif else "RETIRE", charge, seuil
	]

static func _ligne_mouille(t: float, id: String, pose: bool, porosite: float) -> String:
	if pose:
		return "t=%.1fs %s (porosite=%.2f) : etat 'mouille' pose" % [t, id, porosite]
	return "t=%.1fs %s (porosite=%.2f) : etat 'mouille' expire (sechage progressif termine)" % [t, id, porosite]

static func _ligne_extinction(t: float, id: String, porosite: float) -> String:
	return "t=%.1fs %s (porosite=%.2f) : eteint (combustible epuise)" % [t, id, porosite]

static func _ligne_source(t: float, actif: bool) -> String:
	return "t=%.1fs source : %s" % [t, "ACTIVE" if actif else "INACTIVE"]

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
	label.position = centre - Vector2(TAILLE / 2.0, TAILLE / 2.0 + 110.0)
	add_child(label)
	_labels[id] = label

func _creer_rendu_source() -> void:
	var centre := Vector2(_source.position.x, _source.position.y)
	var noeud := ColorRect.new()
	noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noeud.size = Vector2(TAILLE_SOURCE, TAILLE_SOURCE)
	noeud.position = centre - noeud.size / 2.0
	add_child(noeud)
	_noeud_source = noeud

	var label := Label.new()
	label.position = noeud.position - Vector2(20.0, 24.0)
	add_child(label)
	_label_source = label

func _poser_camera() -> void:
	var position_source: Vector3 = _source.position
	var centre_x: float = position_source.x
	for objet in _objets:
		centre_x += objet.position.x
	centre_x /= float(_objets.size() + 1)
	var camera := Camera2D.new()
	camera.position = Vector2(centre_x, 250.0)
	camera.zoom = Vector2(0.6, 0.6)
	camera.enabled = true
	add_child(camera)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
