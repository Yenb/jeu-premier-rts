extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_corrosion.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1). PREMIERE demonstration reelle
# du chantier "corrosion" : un objet en fer expose a une source d'humidite se
# corrode progressivement (proprietes degradees), puis au terme est
# transforme en un objet neuf (rouille) -- meme patron que le chantier
# pourriture (accumulation -> etat -> degradation -> transformation), en
# TROIS phases qui composent uniquement des mecanismes deja fermes.
#
# CORRECTION DE DOMAINE (retour Yael, verifie en ligne, session ulterieure a
# l'ecriture initiale) : le bois ne rouille PAS -- rouiller est un phenomene
# specifique au fer/acier (oxyde de fer), le bois se degrade par un tout
# autre processus deja modelise separement (pourriture, banc_pourriture.gd).
# Ce fichier a donc ete GENERALISE : chaque objet du banc porte desormais
# SON PROPRE etat cible (proprietes.etat_corrosion) et SA PROPRE propriete
# visee (proprietes.propriete_corrosion), plutot qu'un seul etat/une seule
# propriete partages par tout le banc -- necessaire car l'oxydation produit
# des effets CHIMIQUEMENT DIFFERENTS selon le metal :
# - FER -> ROUILLE : destructive, ronge le metal. Seul le fer porte
#   `reserve_integrite: true` (voir Phase 3 plus bas) et suit le pipeline
#   complet jusqu'a la transformation en objet neuf.
# - CUIVRE/BRONZE -> VERT-DE-GRIS (patine_verte, catalogue PARTAGE) :
#   COSMETIQUE. La patine est une couche PROTECTRICE (passivante) qui ne
#   ronge PAS le metal -- ce chantier s'arrete donc a la Phase 2 pour ces
#   deux-la, aucune reserve d'integrite, jamais transformes.
# - ARGENT -> TERNISSURE (catalogue PARTAGE) : COSMETIQUE, meme raison que
#   la patine -- une simple couche de surface (sulfure d'argent), jamais
#   destructive.
# Le mecanisme reste generique (aucun nom de metal en dur dans les fonctions
# statiques ci-dessous) : c'est la DONNEE (`data/banc_corrosion.json:objets`)
# qui decide, par objet, quel etat viser et si la Phase 3 s'applique.
#
# PHASE 1 -- ACCUMULATION (charge.gd, deja ferme, deja cable sur
# banc_charge.gd/banc_contagion.gd/banc_humidite.gd/banc_pourriture.gd) : une
# charge d'humidite monte tant que la source est a portee, ponderee PAR OBJET
# par corrodable (data/materiaux.json) -- exactement le meme cablage que
# banc_humidite.gd/banc_pourriture.gd (un appel a Charge.avancer PAR OBJET
# CIBLE, charge.gd n'ayant aucun coefficient par receveur). Le franchissement
# du seuil pose un simple marqueur booleen (proprietes.expose_corrosion),
# jamais etats_actifs directement (charge.gd est symetrique, poser/retirer
# instantanes, incompatibles avec une corrosion PROGRESSIVE) -- c'est CE
# fichier qui, tant que le marqueur reste vrai, appelle EtatDuree.poser SUR
# L'ETAT PROPRE A CET OBJET (proprietes.etat_corrosion) CHAQUE tick (remise
# a 1.0, jamais un cumul).
#
# PHASE 2 -- DEGRADATION (etat_effectif.gd + etat_duree.gd, deja fermes,
# deja demontres par banc_etat_duree.gd/banc_inflammabilite.gd) : l'etat
# cible de chaque objet (data/etats.json:corrode/patine_verte/ternissure,
# toutes trois NOUVELLES entrees partagees -- duree 10-12s, meme famille que
# "mouille"/"pourri") module UNIQUEMENT la propriete visee de cet objet
# (durete pour le fer, reflectivite pour cuivre/bronze/argent) -- comme
# "mouille"/"pourri", REVERSIBLE : si la source est coupee avant le terme,
# l'etat guerit progressivement, jamais un retrait instantane.
#
# PHASE 3 -- TRANSFORMATION (depense.gd + produit.gd, deja fermes, deja
# combines une premiere fois par le chantier "pourriture") -- SEUL LE FER :
# une DEUXIEME reserve nommee, "integrite" (proprietes.reserves.integrite,
# forme generique de depense.gd), decroit UNIQUEMENT tant que l'etat du fer
# ("corrode") est actif -- son cout_base est gele a 0.0 sinon (meme idiome
# que banc_p1.gd:geler_combustible_apres_sauvetage, INVERSE ici). Au seuil
# 0.0 (data/seuils_combustible.json:epuisement_corrosion -- catalogue
# PARTAGE), depense.gd pose un simple marqueur booleen (corrosion_totale) --
# IL NE PRODUIT RIEN LUI-MEME, depense.gd n'a pas de branche "produire"
# (contrairement a extinction.gd:_appliquer_a_zero). C'EST CE FICHIER, des
# qu'il voit ce marqueur fraichement pose, qui appelle LUI-MEME
# scripts/produit.gd:transformer puis proprietes.clear() +
# proprietes.merge(...). Cuivre/bronze/argent ne portent JAMAIS de cle
# "reserves" -- la boucle de Phase 3 les ignore donc naturellement (chemin
# mort deja garanti par depense.gd sur un Dictionary "reserves" absent),
# aucune garde supplementaire necessaire ici.
#
# CE QU'ON DOIT VOIR : une source d'humidite fixe (clic gauche : bascule
# active/inactive) expose en permanence quatre objets alignes -- fer,
# cuivre, bronze, argent. Le fer se corrode vite (corrodable 0.8) : charge,
# puis "expose", puis "corrode" (teinte qui rouille, durete effective qui
# chute), puis sa reserve d'integrite s'epuise et il devient de la ROUILLE
# (teinte brique sombre, composition qui change, masse = 0.85 * masse du
# fer). Cuivre (corrodable 0.5) et bronze (0.45) verdissent progressivement
# (reflectivite effective qui chute) et RESTENT VERTS POUR TOUJOURS une fois
# la patine formee tant que la source reste active -- jamais detruits,
# jamais transformes. Argent (corrodable 0.55) ternit (reflectivite
# effective qui chute plus fort que la patine) -- meme statut cosmetique.
# Couper la source AVANT le terme fait guerir chaque etat progressivement
# (comme "mouille"/"pourri") -- pour le fer, la reserve d'integrite cesse
# alors de descendre (cout_base regele a 0.0), l'objet est SAUVE.
#
# LIMITE STRICTE (rappel explicite du chantier) : ce fichier, ses donnees et
# ses tests sont le SEUL perimetre -- charge.gd/etat_duree.gd/
# etat_effectif.gd/depense.gd/produit.gd/extinction.gd/objet.gd restent
# EXACTEMENT ceux deja verrouilles par leurs propres tests, aucun n'est
# touche par ce chantier. "corrode"/"patine_verte"/"ternissure"
# (data/etats.json), "corrosion_fer" (data/transformations.json),
# "epuisement_corrosion" (data/seuils_combustible.json), les types/materiaux
# "rouille"/"cuivre"/"bronze"/"argent" (data/types.json/data/materiaux.json)
# et "corrodable"/"durete"/"reflectivite" (data/
# proprietes_immuables_composition.json) sont les seules donnees NEUVES
# au-dela de ce fichier et de ses propres donnees jetables
# (data/banc_corrosion.json).
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready construit la source et les quatre objets
#   (Objet.fabriquer, composition fusionnee -- meme patron que
#   banc_humidite.gd/banc_pourriture.gd). _unhandled_input bascule la source
#   au clic gauche. _process appelle UNIQUEMENT avancer() (fonction
#   statique, ci-dessous) puis lit ses resultats pour l'affichage/la
#   console -- jamais un calcul refait ici (regle CLAUDE.md : la logique
#   enfermee dans _process doit en sortir en fonction statique testable).
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_corrosion.gd) : causes_de/causes_ponderees/avancer/
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
var _actif_avant: Dictionary = {}
var _expose_avant: Dictionary = {}
var _transforme_avant: Dictionary = {}
var _temps: float = 0.0

func _ready() -> void:
	_config = _charger_json("res://data/banc_corrosion.json")
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
		_actif_avant[objet.id] = false
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

		var nom_etat: String = objet.proprietes.get("etat_corrosion", "")
		var actif: bool = objet.proprietes.get("etats_actifs", []).has(nom_etat)
		if actif != _actif_avant.get(id, false):
			var pondere := EtatDuree.etats_ponderes(objet, _etats)
			var propriete_visee: String = objet.proprietes.get("propriete_corrosion", "")
			var eff: float = EtatEffectif.valeur(objet, propriete_visee, pondere)
			print(_ligne_etat(_temps, id, nom_etat, propriete_visee, actif, eff))
			_actif_avant[id] = actif

		if id in resultat.transformes:
			var masse: float = objet.proprietes.get("masse", 0.0)
			print(_ligne_transforme(_temps, id, masse))
			_transforme_avant[id] = true

	_rafraichir_tout()

func _rafraichir_tout() -> void:
	for objet in _objets:
		var id: String = objet.id
		if _transforme_avant.get(id, false):
			_noeuds[id].color = _COULEUR_ROUILLE
			_labels[id].text = _texte_label_rouille(id, objet.proprietes)
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

# ---- Fonctions PURES, testables headless (voir test_banc_corrosion.gd) ----

# Meme geste que banc_humidite.gd/banc_pourriture.gd:causes_de -- filtre les
# objets portant "propriete_cause" a vrai, rend { position }, poids implicite
# 1.0 laisse a la charge de charge.gd.
static func causes_de(objets: Array, propriete_cause: String) -> Array:
	var causes: Array = []
	for chose in objets:
		if chose.proprietes.get(propriete_cause, false):
			causes.append({"position": chose.position})
	return causes

# Pre-multiplie le poids de chaque cause par "poids" (le corrodable du
# RECEVEUR, jamais de la source) -- meme geste que banc_humidite.gd/
# banc_pourriture.gd.
static func causes_ponderees(causes: Array, poids: float) -> Array:
	var resultat: Array = []
	for cause in causes:
		resultat.append({"position": cause.position, "poids": cause.get("poids", 1.0) * poids})
	return resultat

# UN PAS de simulation complet, les trois phases dans l'ordre. DIFFERENCE
# avec banc_pourriture.gd : l'etat cible n'est plus un nom UNIQUE partage par
# tout le banc (config.nom_etat) mais lu SUR CHAQUE OBJET
# (proprietes.etat_corrosion, pose par fabriquer_objets depuis la donnee) --
# necessaire pour que fer/cuivre/bronze/argent visent chacun leur propre
# etat (corrode/patine_verte/ternissure) avec le meme code generique.
# 1. accumulation (Charge.avancer, un appel par objet, pondere par
#    corrodable) + repose de l'etat PROPRE A CET OBJET tant que le marqueur
#    d'exposition reste vrai ce tick, puis EtatDuree.avancer une seule fois
#    pour l'ensemble (degradation/guerison progressives, generique quel que
#    soit le nombre d'etats distincts suivis).
# 2. gate du cout_base de la reserve "integrite" : actif SEULEMENT tant que
#    l'etat de CET OBJET est dans etats_actifs -- SEUL le fer porte une cle
#    "reserves" (voir fabriquer_objets), la boucle est donc un CHEMIN MORT
#    pour cuivre/bronze/argent (reserves.has(nom_reserve) rend faux).
# 3. Depense.avancer sur la reserve "integrite" -- pose "corrosion_totale"
#    au seuil 0.0 UNIQUEMENT sur les objets qui portent cette reserve (donc
#    le fer seul) ; pour chaque id fraichement franchi, appelle
#    Produit.transformer PUIS proprietes.clear()+merge(...) -- exactement le
#    geste d'extinction.gd:_appliquer_a_zero pour "a_zero.produire", rejoue
#    ici puisque depense.gd n'a pas cette branche.
# Rend { bascules, expirees, franchis_integrite, transformes } -- memes
# formes que celles deja rendues par Charge.avancer/EtatDuree.avancer/
# Depense.avancer, jamais recalculees ici.
static func avancer(objets: Array, source: Dictionary, delta: float, config: Dictionary, etats: Dictionary, catalogue_seuils_integrite: Dictionary, config_produire: Dictionary, table: Dictionary, materiaux: Dictionary) -> Dictionary:
	var causes_base := causes_de([source], config.propriete_cause)
	var bascules: Array = []
	for objet in objets:
		var corrodable: float = objet.proprietes.get(config.propriete_corrodable, 0.0)
		var causes := causes_ponderees(causes_base, corrodable)
		var b := Charge.avancer([objet], causes, delta)
		if not b.is_empty():
			bascules.append(objet.id)
		if objet.proprietes.get(config.declencheur_expose, false):
			EtatDuree.poser(objet, objet.proprietes.etat_corrosion, etats)
	var expirees := EtatDuree.avancer(objets, delta, etats)

	var nom_reserve: String = config.nom_reserve_integrite
	var cout_actif: float = config.cout_integrite_actif
	for objet in objets:
		var reserves: Dictionary = objet.proprietes.get("reserves", {})
		if not reserves.has(nom_reserve):
			continue
		var actif: bool = objet.proprietes.get("etats_actifs", []).has(objet.proprietes.etat_corrosion)
		reserves[nom_reserve]["cout_base"] = cout_actif if actif else 0.0

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
# meme patron que banc_humidite.gd/banc_pourriture.gd). Chaque objet recoit
# ENSUITE son propre canal de charge (duplique, jamais partage), SON PROPRE
# etat cible (decl.nom_etat -- fer "corrode", cuivre/bronze "patine_verte",
# argent "ternissure") et SA PROPRE propriete visee (decl.propriete_visee),
# poses directement sur proprietes -- meme statut qu'une reference de
# catalogue ("transformation" sur un chantier extinction.gd). SEUL un objet
# dont la declaration porte `reserve_integrite: true` recoit en plus la
# reserve "integrite" (dupliquee) -- c'est cette seule difference qui separe
# le fer (Phase 3 destructive) de cuivre/bronze/argent (cosmetique, jamais
# de "reserves" du tout).
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
		objet.proprietes["etat_corrosion"] = decl.nom_etat
		objet.proprietes["propriete_corrosion"] = decl.propriete_visee
		if decl.get("reserve_integrite", false):
			objet.proprietes["reserves"] = {config.nom_reserve_integrite: config.reserve_integrite_defaut.duplicate(true)}
		objets.append(objet)
	return objets

# Diagnostic d'affichage, PUR : lit uniquement des valeurs deja calculees
# par charge.gd/etat_duree.gd/etat_effectif.gd/depense.gd, ne reimplemente
# jamais leur loi (meme doctrine que banc_humidite.gd/banc_pourriture.gd:
# diagnostiquer). "statut" vaut desormais le NOM DE L'ETAT lui-meme
# ("corrode"/"patine_verte"/"ternissure") une fois actif, plutot qu'un mot
# fixe -- necessaire pour que l'affichage distingue les trois destins sans
# qu'aucun nom ne soit en dur dans ce fichier (statut lu depuis
# proprietes.etat_corrosion). Rend { statut, nom_etat, charge, seuil,
# corrodable, intensite (-1.0 si non suivie), propriete_visee,
# valeur_effective, a_reserve, reserve_integrite }.
static func diagnostiquer(objet: Dictionary, config: Dictionary, etats: Dictionary) -> Dictionary:
	var canal: Dictionary = objet.proprietes.get("etats", {}).get(config.nom_canal, {})
	var expose: bool = objet.proprietes.get(config.declencheur_expose, false)
	var nom_etat: String = objet.proprietes.get("etat_corrosion", "")
	var actif: bool = objet.proprietes.get("etats_actifs", []).has(nom_etat)
	var intensite: float = objet.proprietes.get("etats_intensite", {}).get(nom_etat, -1.0)
	var pondere := EtatDuree.etats_ponderes(objet, etats)
	var propriete_visee: String = objet.proprietes.get("propriete_corrosion", "")
	var valeur_effective: float = EtatEffectif.valeur(objet, propriete_visee, pondere)
	var reserves: Dictionary = objet.proprietes.get("reserves", {})
	var a_reserve: bool = reserves.has(config.nom_reserve_integrite)
	var canal_integrite: Dictionary = reserves.get(config.nom_reserve_integrite, {})
	var statut: String = nom_etat if actif else ("expose" if expose else "sain")
	return {
		"statut": statut,
		"nom_etat": nom_etat,
		"charge": canal.get("charge", 0.0),
		"seuil": canal.get("seuil", 0.0),
		"corrodable": objet.proprietes.get(config.propriete_corrodable, 0.0),
		"intensite": intensite,
		"propriete_visee": propriete_visee,
		"valeur_effective": valeur_effective,
		"a_reserve": a_reserve,
		"reserve_integrite": canal_integrite.get("reserve", 0.0),
	}

const _COULEUR_ROUILLE := Color(0.32, 0.14, 0.06)

static func _teinte_pour_statut(statut: String) -> Color:
	match statut:
		"corrode":
			return Color(0.6, 0.32, 0.1)
		"patine_verte":
			return Color(0.2, 0.5, 0.35)
		"ternissure":
			return Color(0.18, 0.18, 0.2)
		"expose":
			return Color(0.6, 0.55, 0.5)
		_:
			return Color(0.55, 0.55, 0.6)

static func _texte_label(id: String, diag: Dictionary) -> String:
	var intensite_texte: String = ("%.2f" % diag.intensite) if diag.intensite >= 0.0 else "-"
	var texte := "%s\ncorrodable=%.2f\ncharge=%.2f/%.2f\netat=%s\nintensite=%s\n%s_eff=%.2f" % [
		id, diag.corrodable, diag.charge, diag.seuil, diag.statut, intensite_texte,
		diag.propriete_visee, diag.valeur_effective,
	]
	if diag.a_reserve:
		texte += "\nintegrite=%.2f" % diag.reserve_integrite
	return texte

static func _texte_label_rouille(id: String, proprietes: Dictionary) -> String:
	var materiau: String = ""
	var composition: Array = proprietes.get("composition", [])
	if not composition.is_empty():
		materiau = String(composition[0].get("materiau", ""))
	return "%s\nROUILLE\nmateriau=%s\nmasse=%.2f" % [id, materiau, proprietes.get("masse", 0.0)]

static func _ligne_pose_initiale(id: String, diag: Dictionary) -> String:
	return "t=0.0s %s : corrodable=%.2f seuil=%.2f %s_eff=%.2f (%s)" % [
		id, diag.corrodable, diag.seuil, diag.propriete_visee, diag.valeur_effective, diag.statut
	]

static func _ligne_expose(t: float, id: String, actif: bool, charge: float, seuil: float) -> String:
	return "t=%.1fs %s : expose_corrosion %s (charge=%.2f, seuil=%.2f)" % [
		t, id, "POSE" if actif else "RETIRE", charge, seuil
	]

static func _ligne_etat(t: float, id: String, nom_etat: String, propriete_visee: String, pose: bool, eff: float) -> String:
	if pose:
		return "t=%.1fs %s : etat '%s' pose -- %s effective -> %.2f" % [t, id, nom_etat, propriete_visee, eff]
	return "t=%.1fs %s : etat '%s' expire (guerison progressive terminee) -- %s effective -> %.2f" % [t, id, nom_etat, propriete_visee, eff]

static func _ligne_transforme(t: float, id: String, masse: float) -> String:
	return "t=%.1fs %s : reserve d'integrite epuisee -- transforme en rouille (masse=%.2f)" % [t, id, masse]

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
	rempli.color = Color(0.75, 0.4, 0.15)
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
	camera.zoom = Vector2(0.55, 0.55)
	camera.enabled = true
	add_child(camera)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
