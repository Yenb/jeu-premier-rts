extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_pourriture.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1). PREMIERE demonstration reelle
# du chantier "pourriture" : un objet organique (bois) expose a une source
# d'humidite pourrit progressivement (proprietes degradees), puis au terme
# est transforme en un objet neuf (compost) -- meme patron que le chantier
# corrosion (accumulation -> etat -> degradation -> transformation), en
# TROIS phases qui composent uniquement des mecanismes deja fermes :
#
# PHASE 1 -- ACCUMULATION (charge.gd, deja ferme, deja cable sur
# banc_charge.gd/banc_contagion.gd/banc_humidite.gd) : une charge
# d'humidite monte tant que la source est a portee, ponderee PAR OBJET par
# sensibilite_pourriture (data/materiaux.json) -- exactement le meme
# cablage que banc_humidite.gd (un appel a Charge.avancer PAR OBJET CIBLE,
# charge.gd n'ayant aucun coefficient par receveur). Le franchissement du
# seuil pose un simple marqueur booleen (proprietes.expose_pourriture),
# jamais etats_actifs directement (meme raison que banc_humidite.gd :
# charge.gd est symetrique, poser/retirer instantanes, incompatibles avec
# une pourriture PROGRESSIVE) -- c'est CE fichier qui, tant que le marqueur
# reste vrai, appelle EtatDuree.poser("pourri") CHAQUE tick (remise a 1.0,
# jamais un cumul).
#
# PHASE 2 -- DEGRADATION (etat_effectif.gd + etat_duree.gd, deja fermes,
# deja demontres par banc_etat_duree.gd/banc_inflammabilite.gd) : l'etat
# "pourri" (data/etats.json, NOUVELLE entree partagee -- duree 10.0s, meme
# famille que "mouille") ecrase comestibilite a 0.0 et module inflammabilite
# par 1.4 (matiere qui se decompose, plus seche et plus friable). Comme
# "mouille", REVERSIBLE : si la source est coupee avant le terme, "pourri"
# seche -- pardon, GUERIT -- progressivement sur ses 10.0s, jamais un
# retrait instantane (EtatDuree.avancer, deja demontre, jamais reecrit).
#
# PHASE 3 -- TRANSFORMATION (depense.gd + produit.gd, deja fermes,
# JAMAIS COMBINES AVANT CE CHANTIER) : une DEUXIEME reserve nommee,
# "integrite" (proprietes.reserves.integrite, forme generique de
# depense.gd, sans aucun rapport avec reserves.combustible), decroit
# UNIQUEMENT tant que "pourri" est actif -- son cout_base est gele a 0.0
# tant que "pourri" est absent (meme idiome que
# banc_p1.gd:geler_combustible_apres_sauvetage, qui gele reserves.
# combustible.cout_base tant que "brule" est absent, INVERSE ici : gele
# tant que "pourri" est ABSENT). Au seuil 0.0 (data/seuils_combustible.json:
# epuisement_pourriture -- catalogue PARTAGE, "seuils_ref" est verifie par
# test_lint_donnees.gd contre CE seul fichier, jamais un catalogue local),
# depense.gd pose un simple marqueur booleen (proprietes.pourriture_totale)
# -- IL NE PRODUIT RIEN LUI-MEME, depense.gd n'a pas de branche "produire"
# (contrairement a extinction.gd:_appliquer_a_zero). C'est CE FICHIER,
# des qu'il voit ce marqueur fraichement pose (Depense.avancer le rend dans
# sa liste "franchis" le tick meme ou il bascule, jamais reapplique
# ensuite -- seuils_franchis empeche toute reapplication), qui appelle
# LUI-MEME scripts/produit.gd:transformer puis proprietes.clear() +
# proprietes.merge(...) -- EXACTEMENT le geste que extinction.gd:
# _appliquer_a_zero fait deja pour "a_zero.produire", rejoue ici au niveau
# du cablage (aucune ligne d'extinction.gd/depense.gd/produit.gd changee).
# La config produite (type_produit "compost", rendement 0.35) vit en
# donnee PARTAGEE dans data/transformations.json:pourriture_bois -- MEME
# FORME que combustion_bois/combustion_charbon (a_zero.produire), mais
# jamais lue par extinction.gd (rien ne porte "travail_restant"/
# "transformation" pointant vers cette entree) : ce fichier la lit
# directement, une seule fois a _ready().
#
# CE QU'ON DOIT VOIR : une source d'humidite fixe (clic gauche : bascule
# active/inactive, marqueur au sol -- meme geste que banc_humidite.gd)
# expose en permanence un bois et une pierre alignes. Le bois pourrit vite
# (sensibilite_pourriture 0.8) : charge, puis "expose", puis "pourri"
# (teinte qui fonce, inflammabilite effective qui grimpe), puis sa reserve
# d'integrite s'epuise et il devient du COMPOST (teinte tres sombre,
# composition qui change, masse = 0.35 * masse du bois au moment de la
# transformation). La pierre (sensibilite 0.0) ne bouge JAMAIS -- sa charge
# reste a 0.0 pour toujours, elle ne devient jamais "pourri", sa reserve
# d'integrite (cout_base gele a 0.0 en permanence) ne descend jamais, elle
# ne se transforme donc jamais. Couper la source AVANT le terme fait
# secher "pourri" progressivement (comme "mouille") -- la reserve
# d'integrite cesse alors de descendre (cout_base regele a 0.0), l'objet
# est SAUVE, exactement comme un feu eteint a temps dans banc_p1.
#
# LIMITE STRICTE (rappel explicite du chantier) : ce fichier, ses donnees
# et ses tests sont le SEUL perimetre -- charge.gd/etat_duree.gd/
# etat_effectif.gd/depense.gd/produit.gd/extinction.gd/objet.gd restent
# EXACTEMENT ceux deja verrouilles par leurs propres tests, aucun n'est
# touche par ce chantier. Seule "pourri" (data/etats.json, catalogue
# PARTAGE) et "pourriture_bois" (data/transformations.json, catalogue
# PARTAGE) sont des donnees NEUVES au-dela de ce fichier et de ses propres
# donnees jetables (data/banc_pourriture.json).
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready construit la source et les deux objets
#   (Objet.fabriquer, composition fusionnee -- meme patron que
#   banc_humidite.gd). _unhandled_input bascule la source au clic gauche.
#   _process appelle UNIQUEMENT avancer() (fonction statique, ci-dessous)
#   puis lit ses resultats pour l'affichage/la console -- jamais un calcul
#   refait ici (regle CLAUDE.md : la logique enfermee dans _process doit en
#   sortir en fonction statique testable).
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_pourriture.gd) : causes_de/causes_ponderees/avancer/
#   basculer_source/fabriquer_objets/diagnostiquer, plus le texte
#   d'affichage et de log.

const Objet = preload("res://scripts/objet.gd")
const Charge = preload("res://scripts/charge.gd")
const EtatDuree = preload("res://scripts/etat_duree.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")
const Depense = preload("res://scripts/depense.gd")
const Produit = preload("res://scripts/produit.gd")

const TAILLE := 70.0
const HAUTEUR_BARRE := 10.0
const TAILLE_SOURCE := 30.0
const PROPRIETE_INFLAMMABILITE := "inflammabilite"
const PROPRIETE_COMESTIBILITE := "comestibilite"

var _config: Dictionary = {}
var _etats: Dictionary = {}
var _catalogue_types: Dictionary = {}
var _materiaux: Dictionary = {}
var _config_produire: Dictionary = {}
var _catalogue_seuils_integrite: Dictionary = {}
var _source: Dictionary = {}
var _objets: Array = []
var _noeuds: Dictionary = {}
var _barres_fond: Dictionary = {}
var _barres_remplies: Dictionary = {}
var _labels: Dictionary = {}
var _noeud_source: ColorRect
var _label_source: Label
var _pourri_avant: Dictionary = {}
var _expose_avant: Dictionary = {}
var _transforme_avant: Dictionary = {}
var _temps: float = 0.0

func _ready() -> void:
	_config = _charger_json("res://data/banc_pourriture.json")
	_etats = _charger_json("res://data/etats.json")
	_materiaux = _charger_json("res://data/materiaux.json")
	var proprietes_immuables: Array = _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", [])
	_catalogue_types = _charger_json("res://data/types.json")
	var transformations: Dictionary = _charger_json("res://data/transformations.json").get("transformations", {})
	_config_produire = transformations.get(_config.transformation_terminale, {}).get("a_zero", {}).get("produire", {})
	# "seuils_ref" est verifie par test_lint_donnees.gd contre CE catalogue
	# PARTAGE uniquement (voir data/seuils_combustible.json._note) -- jamais
	# un catalogue local a ce banc.
	_catalogue_seuils_integrite = _charger_json("res://data/seuils_combustible.json")

	var decl_source: Dictionary = _config.get("source", {})
	var pos_source: Array = decl_source.get("position", [0.0, 0.0, 0.0])
	_source = {
		"id": decl_source.get("id", "source"),
		"position": Vector3(pos_source[0], pos_source[1], pos_source[2]),
		"proprietes": {_config.propriete_cause: true},
	}

	_objets = fabriquer_objets(_config.get("objets", []), _materiaux, proprietes_immuables, _config)
	for objet in _objets:
		_pourri_avant[objet.id] = false
		_expose_avant[objet.id] = false
		_transforme_avant[objet.id] = false
		_creer_rendu_objet(objet)

	_creer_rendu_source()
	_poser_camera()

	for objet in _objets:
		var diag := diagnostiquer(objet, _config, _etats)
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
	var resultat := avancer(_objets, _source, delta, _config, _etats, _catalogue_seuils_integrite, _config_produire, _catalogue_types, _materiaux)

	for objet in _objets:
		var id: String = objet.id
		if _transforme_avant.get(id, false):
			continue

		var expose: bool = objet.proprietes.get(_config.declencheur_expose, false)
		if expose != _expose_avant.get(id, false):
			var canal: Dictionary = objet.proprietes.get("etats", {}).get(_config.nom_canal, {})
			print(_ligne_expose(_temps, id, expose, canal.get("charge", 0.0), canal.get("seuil", 0.0)))
			_expose_avant[id] = expose

		var pourri: bool = objet.proprietes.get("etats_actifs", []).has(_config.nom_etat)
		if pourri != _pourri_avant.get(id, false):
			var pondere := EtatDuree.etats_ponderes(objet, _etats)
			var eff_inflammabilite: float = EtatEffectif.valeur(objet, PROPRIETE_INFLAMMABILITE, pondere)
			var eff_comestibilite: float = EtatEffectif.valeur(objet, PROPRIETE_COMESTIBILITE, pondere)
			print(_ligne_pourri(_temps, id, pourri, eff_inflammabilite, eff_comestibilite))
			_pourri_avant[id] = pourri

		if id in resultat.transformes:
			var masse: float = objet.proprietes.get("masse", 0.0)
			print(_ligne_transforme(_temps, id, masse))
			_transforme_avant[id] = true

	_rafraichir_tout()

func _rafraichir_tout() -> void:
	for objet in _objets:
		var id: String = objet.id
		if _transforme_avant.get(id, false):
			_noeuds[id].color = _COULEUR_COMPOST
			_labels[id].text = _texte_label_compost(id, objet.proprietes)
			_barres_remplies[id].size.x = 0.0
			continue
		var diag := diagnostiquer(objet, _config, _etats)
		_noeuds[id].color = _teinte_pour_statut(diag.statut)
		var ratio: float = clamp(diag.charge / diag.seuil, 0.0, 1.0) if diag.seuil > 0.0 else 0.0
		_barres_remplies[id].size.x = _barres_fond[id].size.x * ratio
		_labels[id].text = _texte_label(id, diag)
	var actif: bool = _source.proprietes.get(_config.propriete_cause, false)
	_noeud_source.color = Color(0.15, 0.55, 0.95) if actif else Color(0.4, 0.4, 0.4)
	_label_source.text = "source : %s (clic pour basculer)" % ("ACTIVE" if actif else "INACTIVE")

# ---- Fonctions PURES, testables headless (voir test_banc_pourriture.gd) ----

# Meme geste que banc_humidite.gd:causes_de -- filtre les objets portant
# "propriete_cause" a vrai, rend { position }, poids implicite 1.0 laisse a
# la charge de charge.gd.
static func causes_de(objets: Array, propriete_cause: String) -> Array:
	var causes: Array = []
	for chose in objets:
		if chose.proprietes.get(propriete_cause, false):
			causes.append({"position": chose.position})
	return causes

# Pre-multiplie le poids de chaque cause par "poids" (la sensibilite_pourriture
# du RECEVEUR, jamais de la source) -- meme geste que banc_humidite.gd.
static func causes_ponderees(causes: Array, poids: float) -> Array:
	var resultat: Array = []
	for cause in causes:
		resultat.append({"position": cause.position, "poids": cause.get("poids", 1.0) * poids})
	return resultat

# UN PAS de simulation complet, les trois phases dans l'ordre :
# 1. accumulation (Charge.avancer, un appel par objet, pondere par
#    sensibilite_pourriture) + repose de "pourri" tant que le marqueur
#    d'exposition reste vrai ce tick, puis EtatDuree.avancer une seule fois
#    pour l'ensemble (degradation/guerison progressives).
# 2. gate du cout_base de la reserve "integrite" : actif SEULEMENT tant que
#    "pourri" est dans etats_actifs (meme idiome que banc_p1.gd:
#    geler_combustible_apres_sauvetage, inverse -- gele tant que la cause
#    est ABSENTE plutot que presente).
# 3. Depense.avancer sur la reserve "integrite" -- pose "pourriture_totale"
#    au seuil 0.0 ; pour chaque id fraichement franchi (jamais reapplique
#    ensuite par depense.gd lui-meme), appelle Produit.transformer PUIS
#    proprietes.clear()+merge(...) -- exactement le geste d'extinction.gd:
#    _appliquer_a_zero pour "a_zero.produire", rejoue ici puisque
#    depense.gd n'a pas cette branche.
# Un objet DEJA transforme (composition["materiau"] devenu le type_produit)
# n'a plus ni "etats" ni "reserves" (le compost ne compose pas "dynamique")
# -- Charge.avancer/Depense.avancer l'ignorent alors naturellement (chemin
# mort deja garanti par ces deux fichiers sur un Dictionary "etats"/
# "reserves" absent ou vide), aucune garde supplementaire necessaire ici.
# Rend { bascules: Array d'id ayant franchi le seuil d'exposition ce pas,
# expirees: Array de { id, nom_etat } retires par decroissance ce pas,
# franchis_integrite: Array d'id ayant franchi un seuil de la reserve
# d'integrite ce pas, transformes: Array d'id devenus le type_produit ce
# pas } -- memes formes que celles deja rendues par Charge.avancer/
# EtatDuree.avancer/Depense.avancer, jamais recalculees ici.
static func avancer(objets: Array, source: Dictionary, delta: float, config: Dictionary, etats: Dictionary, catalogue_seuils_integrite: Dictionary, config_produire: Dictionary, table: Dictionary, materiaux: Dictionary) -> Dictionary:
	var causes_base := causes_de([source], config.propriete_cause)
	var bascules: Array = []
	for objet in objets:
		var sensibilite: float = objet.proprietes.get(config.propriete_sensibilite, 0.0)
		var causes := causes_ponderees(causes_base, sensibilite)
		var b := Charge.avancer([objet], causes, delta)
		if not b.is_empty():
			bascules.append(objet.id)
		if objet.proprietes.get(config.declencheur_expose, false):
			EtatDuree.poser(objet, config.nom_etat, etats)
	var expirees := EtatDuree.avancer(objets, delta, etats)

	var nom_reserve: String = config.nom_reserve_integrite
	var cout_actif: float = config.cout_integrite_actif
	for objet in objets:
		var reserves: Dictionary = objet.proprietes.get("reserves", {})
		if not reserves.has(nom_reserve):
			continue
		var pourri_actif: bool = objet.proprietes.get("etats_actifs", []).has(config.nom_etat)
		reserves[nom_reserve]["cout_base"] = cout_actif if pourri_actif else 0.0

	var franchis_integrite := Depense.avancer(objets, delta, catalogue_seuils_integrite)
	var marqueur_terminal: String = config.marqueur_terminal
	var transformes: Array = []
	for objet in objets:
		if not objet.proprietes.get(marqueur_terminal, false):
			continue
		var nouvelles_proprietes: Dictionary = Produit.transformer(objet.proprietes, config_produire, table, materiaux)
		if nouvelles_proprietes.is_empty():
			continue
		objet.proprietes.clear()
		objet.proprietes.merge(nouvelles_proprietes, true)
		transformes.append(objet.id)

	return {"bascules": bascules, "expirees": expirees, "franchis_integrite": franchis_integrite, "transformes": transformes}

static func basculer_source(source: Dictionary, propriete_cause: String) -> void:
	source.proprietes[propriete_cause] = not source.proprietes.get(propriete_cause, false)

# Construit les objets cibles via Objet.fabriquer (composition fusionnee --
# meme patron que banc_humidite.gd). Chaque objet recoit ENSUITE son propre
# canal de charge et sa propre reserve d'integrite (dupliques, jamais
# partages entre objets), etats_actifs vide.
static func fabriquer_objets(declarations: Array, materiaux: Dictionary, proprietes_immuables: Array, config: Dictionary) -> Array:
	var catalogue: Dictionary = {}
	for decl in declarations:
		catalogue[decl.id] = {"composition": decl.composition}
	var objets: Array = []
	for decl in declarations:
		var pos: Array = decl.position
		var objet := Objet.fabriquer(decl.id, decl.id, Vector3(pos[0], pos[1], pos[2]), catalogue, materiaux, proprietes_immuables)
		objet.proprietes["etats"] = {config.nom_canal: config.canal_defaut.duplicate(true)}
		objet.proprietes["etats_actifs"] = []
		objet.proprietes["reserves"] = {config.nom_reserve_integrite: config.reserve_integrite_defaut.duplicate(true)}
		objets.append(objet)
	return objets

# Diagnostic d'affichage, PUR : lit uniquement des valeurs deja calculees
# par charge.gd/etat_duree.gd/etat_effectif.gd/depense.gd, ne reimplemente
# jamais leur loi (meme doctrine que banc_humidite.gd:diagnostiquer). Rend
# { statut: "sain" | "expose" | "pourri", charge, seuil, sensibilite,
# intensite (-1.0 si non suivie), inflammabilite_eff, comestibilite_eff,
# reserve_integrite, reserve_integrite_capacite }.
static func diagnostiquer(objet: Dictionary, config: Dictionary, etats: Dictionary) -> Dictionary:
	var canal: Dictionary = objet.proprietes.get("etats", {}).get(config.nom_canal, {})
	var expose: bool = objet.proprietes.get(config.declencheur_expose, false)
	var pourri: bool = objet.proprietes.get("etats_actifs", []).has(config.nom_etat)
	var intensite: float = objet.proprietes.get("etats_intensite", {}).get(config.nom_etat, -1.0)
	var pondere := EtatDuree.etats_ponderes(objet, etats)
	var eff_inflammabilite: float = EtatEffectif.valeur(objet, PROPRIETE_INFLAMMABILITE, pondere)
	var eff_comestibilite: float = EtatEffectif.valeur(objet, PROPRIETE_COMESTIBILITE, pondere)
	var canal_integrite: Dictionary = objet.proprietes.get("reserves", {}).get(config.nom_reserve_integrite, {})
	var statut: String = "pourri" if pourri else ("expose" if expose else "sain")
	return {
		"statut": statut,
		"charge": canal.get("charge", 0.0),
		"seuil": canal.get("seuil", 0.0),
		"sensibilite": objet.proprietes.get(config.propriete_sensibilite, 0.0),
		"intensite": intensite,
		"inflammabilite_eff": eff_inflammabilite,
		"comestibilite_eff": eff_comestibilite,
		"reserve_integrite": canal_integrite.get("reserve", 0.0),
	}

const _COULEUR_COMPOST := Color(0.14, 0.1, 0.06)

static func _teinte_pour_statut(statut: String) -> Color:
	match statut:
		"pourri":
			return Color(0.32, 0.28, 0.12)
		"expose":
			return Color(0.55, 0.6, 0.5)
		_:
			return Color(0.55, 0.42, 0.28)

static func _texte_label(id: String, diag: Dictionary) -> String:
	var intensite_texte: String = ("%.2f" % diag.intensite) if diag.intensite >= 0.0 else "-"
	return "%s\nsensibilite=%.2f\ncharge=%.2f/%.2f\netat=%s\nintensite=%s\ninflammabilite_eff=%.2f\ncomestibilite_eff=%.2f\nintegrite=%.2f" % [
		id, diag.sensibilite, diag.charge, diag.seuil, diag.statut, intensite_texte,
		diag.inflammabilite_eff, diag.comestibilite_eff, diag.reserve_integrite,
	]

static func _texte_label_compost(id: String, proprietes: Dictionary) -> String:
	var materiau: String = ""
	var composition: Array = proprietes.get("composition", [])
	if not composition.is_empty():
		materiau = String(composition[0].get("materiau", ""))
	return "%s\nCOMPOST\nmateriau=%s\nmasse=%.2f" % [id, materiau, proprietes.get("masse", 0.0)]

static func _ligne_pose_initiale(id: String, diag: Dictionary) -> String:
	return "t=0.0s %s : sensibilite=%.2f seuil=%.2f inflammabilite_eff=%.2f (%s)" % [
		id, diag.sensibilite, diag.seuil, diag.inflammabilite_eff, diag.statut
	]

static func _ligne_expose(t: float, id: String, actif: bool, charge: float, seuil: float) -> String:
	return "t=%.1fs %s : expose_pourriture %s (charge=%.2f, seuil=%.2f)" % [
		t, id, "POSE" if actif else "RETIRE", charge, seuil
	]

static func _ligne_pourri(t: float, id: String, pose: bool, eff_inflammabilite: float, eff_comestibilite: float) -> String:
	if pose:
		return "t=%.1fs %s : etat 'pourri' pose -- inflammabilite effective -> %.2f, comestibilite effective -> %.2f" % [t, id, eff_inflammabilite, eff_comestibilite]
	return "t=%.1fs %s : etat 'pourri' expire (guerison progressive terminee) -- inflammabilite effective -> %.2f" % [t, id, eff_inflammabilite]

static func _ligne_transforme(t: float, id: String, masse: float) -> String:
	return "t=%.1fs %s : reserve d'integrite epuisee -- transforme en compost (masse=%.2f)" % [t, id, masse]

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
	rempli.color = Color(0.45, 0.35, 0.1)
	rempli.size = Vector2(0.0, HAUTEUR_BARRE)
	rempli.position = fond.position
	add_child(rempli)
	_barres_remplies[id] = rempli

	var label := Label.new()
	label.position = centre - Vector2(TAILLE / 2.0, TAILLE / 2.0 + 140.0)
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
	camera.zoom = Vector2(0.8, 0.8)
	camera.enabled = true
	add_child(camera)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
