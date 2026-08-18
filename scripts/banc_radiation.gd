extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_radiation.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1). Chantier « sensibilite_radiation
# -- irradiation et blindage » (audit prealable
# audit_colonnes_chimique_nucleaire_magie_prealable.md, colonne nucleaire
# #1/#2). BLOQUE une session entiere en attente de la generalisation de
# 'propriete_emission' dans scripts/perception.gd (chantier separe, livre par
# une autre session -- voir docs/ETAT.md) : la geometrie propagation_obstacles
# ne pouvait pas bloquer une source de radiation avant, elle ne lisait que
# "son_emis" en dur.
#
# TROIS MECANISMES DU COEUR COMPOSES, AUCUN TOUCHE :
# - scripts/perception.gd (canal "radiation", data/canaux.json -- geometrie
#   propagation_obstacles, propriete_obstacle "densite", propriete_emission
#   "force_radiation") decide, PAR OBJET CIBLE, si la source radioactive lui
#   est visible (mur absent ou hors de son segment) ou occluse (mur present ET
#   sur son segment, densite clampee a 1.0 -- blocage total).
# - scripts/charge.gd accumule un canal "radiation" PAR OBJET CIBLE, pondere
#   par (force_radiation de la source * sensibilite_radiation EFFECTIVE de
#   l'objet, scripts/etat_effectif.gd:valeur, jamais reimplementee) --
#   MEME idiome que scripts/banc_toxicite.gd/scripts/banc_corrosion.gd (un
#   appel a Charge.avancer par objet cible, charge.gd n'ayant aucun
#   coefficient par receveur). Au seuil, un marqueur booleen (expose_radiation)
#   est pose -- jamais etats_actifs directement (charge.gd est symetrique,
#   pose/retire instantanes, incompatible avec une guerison PROGRESSIVE) --
#   c'est CE FICHIER qui, tant que le marqueur reste vrai, repose lui-meme
#   scripts/etat_duree.gd:poser("irradie") CHAQUE tick (remise a 1.0, jamais
#   un cumul, meme idiome que toxicite/corrosion).
# - scripts/depense.gd consomme la reserve "integrite" a "degat_par_s" SEULEMENT
#   tant que "irradie" est dans etats_actifs, gelee (0.0) sinon -- meme gate
#   exact que "sante" dans banc_toxicite.gd / "integrite" dans banc_conduction.gd.
#
# AUCUN MECANISME DU COEUR TOUCHE : perception.gd/charge.gd/etat_duree.gd/
# etat_effectif.gd/depense.gd/produit.gd/objet.gd/monde.gd restent EXACTEMENT
# ceux deja verrouilles par leurs propres tests. Donnees neuves au-dela de ce
# fichier et de data/banc_radiation.json (jetable, propre au banc) :
# "sensibilite_radiation" rejoint data/proprietes_immuables_composition.json
# (dormante avant ce chantier) ; "force_radiation" (NOUVELLE, data/
# materiaux.json, bois/pierre/fer -- PAS fusionnee dans proprietes_immuables_
# composition.json, seule la SOURCE hand-built de ce banc la porte, voir
# fabriquer_source) ; "irradie" rejoint data/etats.json (catalogue PARTAGE,
# meme famille reversible que electrocute/empoisonne -- duree, aucun effet
# module, marqueur de gate pour depense.gd seul) ; le canal "radiation" rejoint
# data/canaux.json (catalogue PARTAGE, geometrie propagation_obstacles deja
# prouvee par le canal ouie/chantier occlusion).
#
# POURQUOI LA SOURCE EST HAND-BUILT, PAS FABRIQUEE PAR COMPOSITION : un point
# d'emission de radiation n'a besoin d'aucune matiere physique (densite,
# masse) -- meme patron que data/banc_corrosion.json:source (hand-built,
# {source_humidite: true} seul) et data/banc_croissance.json:source_lumiere/
# source_eau (hand-built, aucune composition). "force_radiation" est donc pose
# directement sur proprietes, jamais fusionne via un materiau.
#
# GEOMETRIE (voir data/banc_radiation.json._note pour le detail chiffre) :
# trois objets a EGALE distance (200.0) de la source, disposes
# PERPENDICULAIREMENT ((200,0,0)/(0,200,0)/(0,-200,0)) pour qu'aucun ne tombe
# jamais sur le segment source->fer_radiation -- seule la sensibilite_radiation
# de chacun explique la difference de vitesse d'irradiation, jamais la
# distance. Le mur (fer, TRES dense) est place EXACTEMENT au milieu de ce
# segment : actif, SEUL fer_radiation cesse d'etre percu ; bois_radiation et
# pierre_radiation restent TOUJOURS visibles, mur actif ou non.
#
# CE QU'ON DOIT VOIR : une source radioactive fixe au centre, trois objets
# alignes perpendiculairement (bois/pierre/fer) affichant chacun sa
# sensibilite_radiation, sa charge de radiation et son integrite. Sans mur
# (etat initial), le bois (sensibilite 0.3) s'irradie le plus vite, le fer
# (0.2) ensuite, la pierre (0.1) le plus lentement -- les trois finissent par
# passer "irradie" et voir leur integrite decroitre en continu tant qu'ils le
# restent. Un clic gauche fait apparaitre le mur (fer) entre la source et
# fer_radiation : celui-ci cesse aussitot d'accumuler de la radiation (sa
# charge redescend vers 0.0 par taux_decroissance, comme mouille/pourri qui
# perdent leur cause), bois/pierre continuent inchanges. Un second clic retire
# le mur, fer_radiation redevient expose comme avant.
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge les donnees et fabrique source/mur/objets.
#   _unhandled_input bascule le mur au clic gauche. _process appelle
#   UNIQUEMENT avancer() (fonction statique, ci-dessous) puis lit ses
#   resultats pour l'affichage/la console.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_radiation.gd) : perceoit_source/monde_pour_objet/avancer/
#   fabriquer_source/fabriquer_mur/fabriquer_objets/diagnostiquer, plus le
#   texte d'affichage et de log.

const Objet = preload("res://scripts/objet.gd")
const Monde = preload("res://scripts/monde.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")
const Perception = preload("res://scripts/perception.gd")
const Charge = preload("res://scripts/charge.gd")
const EtatDuree = preload("res://scripts/etat_duree.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")
const Depense = preload("res://scripts/depense.gd")

const TAILLE := 70.0
const TAILLE_SOURCE := 34.0
const TAILLE_MUR := 40.0
const HAUTEUR_BARRE := 10.0
const PROPRIETE_SENSIBILITE := "sensibilite_radiation"
const PROPRIETE_FORCE := "force_radiation"
const NOM_CANAL_RADIATION := "radiation"

var _config: Dictionary = {}
var _etats: Dictionary = {}
var _catalogue_canaux: Dictionary = {}

var _source: Dictionary = {}
var _mur: Dictionary = {}
var _objets: Array = []
var _mur_actif: bool = false

var _noeuds: Dictionary = {}
var _barres_fond: Dictionary = {}
var _barres_remplies: Dictionary = {}
var _labels: Dictionary = {}
var _noeud_mur: ColorRect
var _label_mur: Label
var _expose_avant: Dictionary = {}
var _irradie_avant: Dictionary = {}
var _temps: float = 0.0

func _ready() -> void:
	_config = _charger_json("res://data/banc_radiation.json")
	_etats = _charger_json("res://data/etats.json")
	var materiaux: Dictionary = _charger_json("res://data/materiaux.json")
	var proprietes_immuables: Array = _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", [])
	_catalogue_canaux = _charger_json("res://data/canaux.json")

	_source = fabriquer_source(_config.source)
	_mur = fabriquer_mur(_config.mur, materiaux, proprietes_immuables)
	_objets = fabriquer_objets(_config.objets, materiaux, proprietes_immuables, _config)

	for objet in _objets:
		_expose_avant[objet.id] = false
		_irradie_avant[objet.id] = false
		_creer_rendu_objet(objet)
	_creer_rendu_source()
	_creer_rendu_mur()
	_poser_camera()

	for objet in _objets:
		print(_ligne_pose_initiale(objet.id, diagnostiquer(objet, _etats, _config)))
	_rafraichir_tout()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_mur_actif = not _mur_actif
		print(_ligne_toggle(_temps, _mur_actif))
		_rafraichir_tout()

func _process(delta: float) -> void:
	_temps += delta
	avancer(_objets, _source, _mur, _mur_actif, delta, _config, _etats, _catalogue_canaux)

	for objet in _objets:
		var id: String = objet.id
		var expose: bool = objet.proprietes.get(_config.declencheur_expose_radiation, false)
		if expose != _expose_avant.get(id, false):
			var canal: Dictionary = objet.proprietes.get("etats", {}).get(_config.nom_canal_radiation, {})
			print(_ligne_expose(_temps, id, expose, canal.get("charge", 0.0), canal.get("seuil", 0.0)))
			_expose_avant[id] = expose

		var irradie: bool = objet.proprietes.get("etats_actifs", []).has(_config.nom_etat_irradie)
		if irradie != _irradie_avant.get(id, false):
			var reserve: float = objet.proprietes.get("reserves", {}).get(_config.nom_reserve_integrite, {}).get("reserve", 0.0)
			print(_ligne_irradie(_temps, id, irradie, reserve))
			_irradie_avant[id] = irradie

	_rafraichir_tout()

func _rafraichir_tout() -> void:
	for objet in _objets:
		var id: String = objet.id
		var diag := diagnostiquer(objet, _etats, _config)
		_noeuds[id].color = Color(0.75, 0.2, 0.2) if diag.irradie else Color(0.5, 0.5, 0.55)
		var ratio: float = clamp(diag.charge / diag.seuil, 0.0, 1.0) if diag.seuil > 0.0 else 0.0
		_barres_remplies[id].size.x = _barres_fond[id].size.x * ratio
		_labels[id].text = _texte_label(id, diag)

	_noeud_mur.visible = _mur_actif
	_label_mur.visible = _mur_actif
	_label_mur.text = _texte_label_mur(_mur)

func _charger_json(chemin: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))

# ---- Fonctions PURES, testables headless (voir test_banc_radiation.gd) ----

# Le mur n'entre dans le Monde du tick QUE si mur_actif est vrai --
# RECONSTRUIT du neant a chaque appel, jamais une mutation en place (meme
# idiome que banc_occlusion.gd:monde_du_tick).
static func monde_pour_objet(source: Dictionary, mur: Dictionary, mur_actif: bool) -> Monde:
	var murs: Array = [mur] if mur_actif else []
	return BancCommun.monde_depuis([
		{"choses": [source], "type": "source_radioactive"},
		{"choses": murs, "type": "mur"},
	])

# La source radioactive est-elle visible pour CET objet ? Construit une
# entite de perception MINIMALE (canal "radiation" seul, portee/seuil du
# banc) et delegue entierement a Perception.percevoir -- jamais un test de
# distance/obstacle reimplemente ici.
static func perceoit_source(objet: Dictionary, source: Dictionary, mur: Dictionary, mur_actif: bool, portee: float, seuil: float, catalogue_canaux: Dictionary) -> bool:
	var monde := monde_pour_objet(source, mur, mur_actif)
	var entite := {
		"id": objet.id,
		"position": objet.position,
		"proprietes": {
			"canaux": [NOM_CANAL_RADIATION],
			"canaux_config": { NOM_CANAL_RADIATION: { "portee": portee, "seuil": seuil } },
		},
	}
	var perceptions: Array = Perception.percevoir(entite, monde, catalogue_canaux)
	for entree in perceptions:
		if entree.chose.id == source.id and NOM_CANAL_RADIATION in entree.canaux:
			return true
	return false

# UN PAS de simulation complet, PAR OBJET CIBLE : (1) perception decide si la
# source est visible, (2) si oui et que la sensibilite effective de l'objet
# est strictement positive, une cause ponderee (force_radiation source *
# sensibilite_radiation effective) alimente Charge.avancer -- sinon aucune
# cause, la charge redescend comme n'importe quelle cause disparue ; le
# marqueur d'exposition, tant qu'il reste vrai, repose EtatDuree.poser("irradie")
# CHAQUE tick (remise a 1.0, jamais un cumul). (3) EtatDuree.avancer une
# seule fois pour l'ensemble. (4) gate du cout_base de la reserve "integrite" :
# actif SEULEMENT tant que "irradie" est actif sur CET objet. (5) Depense.avancer.
# Rend { bascules, expirees, franchis_integrite } -- memes formes que celles
# deja rendues par Charge.avancer/EtatDuree.avancer/Depense.avancer, jamais
# recalculees ici.
static func avancer(objets: Array, source: Dictionary, mur: Dictionary, mur_actif: bool, delta: float, config: Dictionary, etats: Dictionary, catalogue_canaux: Dictionary) -> Dictionary:
	var force_source: float = source.proprietes.get(PROPRIETE_FORCE, 0.0)
	var portee: float = config.portee_perception_radiation
	var seuil_perception: float = config.seuil_perception_radiation
	var bascules: Array = []
	for objet in objets:
		var causes: Array = []
		if perceoit_source(objet, source, mur, mur_actif, portee, seuil_perception, catalogue_canaux):
			var sensibilite: float = EtatEffectif.valeur(objet, PROPRIETE_SENSIBILITE, etats)
			if sensibilite > 0.0:
				causes.append({"position": source.position, "poids": force_source * sensibilite})
		var b := Charge.avancer([objet], causes, delta)
		if not b.is_empty():
			bascules.append(objet.id)
		if objet.proprietes.get(config.declencheur_expose_radiation, false):
			EtatDuree.poser(objet, config.nom_etat_irradie, etats)
	var expirees := EtatDuree.avancer(objets, delta, etats)

	for objet in objets:
		var reserves: Dictionary = objet.proprietes.get("reserves", {})
		if not reserves.has(config.nom_reserve_integrite):
			continue
		var actif: bool = objet.proprietes.get("etats_actifs", []).has(config.nom_etat_irradie)
		reserves[config.nom_reserve_integrite]["cout_base"] = config.degat_par_s if actif else 0.0
	var franchis_integrite := Depense.avancer(objets, delta)

	return {"bascules": bascules, "expirees": expirees, "franchis_integrite": franchis_integrite}

# Hand-built, AUCUNE composition -- un point d'emission n'a besoin d'aucune
# matiere physique, voir en-tete du fichier.
static func fabriquer_source(decl: Dictionary) -> Dictionary:
	var pos: Array = decl.position
	return {
		"id": decl.id,
		"position": Vector3(pos[0], pos[1], pos[2]),
		"proprietes": { PROPRIETE_FORCE: decl.get("force_radiation", 0.0) },
	}

# Fabrique via Objet.fabriquer (composition fusionnee -- "densite" structurelle
# necessaire pour jouer le role de propriete_obstacle du canal "radiation").
static func fabriquer_mur(decl: Dictionary, materiaux: Dictionary, proprietes_immuables: Array) -> Dictionary:
	var catalogue: Dictionary = { decl.id: {"composition": decl.composition} }
	var pos: Array = decl.position
	return Objet.fabriquer(decl.id, decl.id, Vector3(pos[0], pos[1], pos[2]), catalogue, materiaux, proprietes_immuables)

# Construit les objets cibles via Objet.fabriquer (composition fusionnee --
# "sensibilite_radiation" rejoint data/proprietes_immuables_composition.json,
# voir en-tete). Chaque objet recoit ENSUITE son propre canal de charge
# (duplique), sa propre reserve d'integrite (dupliquee) -- meme patron que
# banc_toxicite.gd:fabriquer_agent/banc_corrosion.gd:fabriquer_objets.
static func fabriquer_objets(declarations: Array, materiaux: Dictionary, proprietes_immuables: Array, config: Dictionary) -> Array:
	var catalogue: Dictionary = {}
	for decl in declarations:
		catalogue[decl.id] = {"composition": decl.composition}
	var objets: Array = []
	for decl in declarations:
		var pos: Array = decl.position
		var objet := Objet.fabriquer(decl.id, decl.id, Vector3(pos[0], pos[1], pos[2]), catalogue, materiaux, proprietes_immuables)
		if objet.is_empty():
			continue
		objet.proprietes["etats"] = {config.nom_canal_radiation: config.canal_radiation_defaut.duplicate(true)}
		objet.proprietes["etats_actifs"] = []
		objet.proprietes["reserves"] = {config.nom_reserve_integrite: config.reserve_integrite_defaut.duplicate(true)}
		objets.append(objet)
	return objets

# Diagnostic d'affichage, PUR : lit uniquement des valeurs deja calculees par
# charge.gd/etat_effectif.gd/depense.gd, ne reimplemente jamais leur loi.
static func diagnostiquer(objet: Dictionary, etats: Dictionary, config: Dictionary) -> Dictionary:
	var canal: Dictionary = objet.proprietes.get("etats", {}).get(config.nom_canal_radiation, {})
	var reserves: Dictionary = objet.proprietes.get("reserves", {})
	return {
		"sensibilite": EtatEffectif.valeur(objet, PROPRIETE_SENSIBILITE, etats),
		"charge": canal.get("charge", 0.0),
		"seuil": canal.get("seuil", 0.0),
		"irradie": objet.proprietes.get("etats_actifs", []).has(config.nom_etat_irradie),
		"integrite": reserves.get(config.nom_reserve_integrite, {}).get("reserve", 0.0),
	}

static func _texte_label(id: String, diag: Dictionary) -> String:
	return "%s\nsensibilite_radiation=%.2f\ncharge=%.2f/%.2f\nirradie=%s\nintegrite=%.2f" % [
		id, diag.sensibilite, diag.charge, diag.seuil, diag.irradie, diag.integrite
	]

static func _texte_label_mur(mur: Dictionary) -> String:
	return "mur (fer)\ndensite=%.2f" % mur.proprietes.get("densite", 0.0)

static func _ligne_pose_initiale(id: String, diag: Dictionary) -> String:
	return "t=0.0s %s : sensibilite_radiation=%.2f seuil=%.2f" % [id, diag.sensibilite, diag.seuil]

static func _ligne_toggle(t: float, mur_actif: bool) -> String:
	return "t=%.1fs MUR (fer, tres dense) : %s" % [t, "present" if mur_actif else "absent"]

static func _ligne_expose(t: float, id: String, actif: bool, charge: float, seuil: float) -> String:
	return "t=%.1fs %s : expose_radiation %s (charge=%.2f, seuil=%.2f)" % [
		t, id, "POSE" if actif else "RETIRE", charge, seuil
	]

static func _ligne_irradie(t: float, id: String, irradie: bool, reserve: float) -> String:
	if irradie:
		return "t=%.1fs %s : irradie (integrite=%.2f)" % [t, id, reserve]
	return "t=%.1fs %s : irradiation terminee, guerison progressive (integrite=%.2f)" % [t, id, reserve]

# ---- Rendu (impur, Node) -- aucune decision, seulement la construction des
# noeuds et de la camera.

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
	rempli.color = Color(0.8, 0.7, 0.15)
	rempli.size = Vector2(0.0, HAUTEUR_BARRE)
	rempli.position = fond.position
	add_child(rempli)
	_barres_remplies[id] = rempli

	var label := Label.new()
	label.position = centre - Vector2(TAILLE / 2.0, TAILLE / 2.0 + 100.0)
	add_child(label)
	_labels[id] = label

func _creer_rendu_source() -> void:
	var centre := Vector2(_source.position.x, _source.position.y)
	var noeud := ColorRect.new()
	noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noeud.color = Color(0.95, 0.6, 0.1)
	noeud.size = Vector2(TAILLE_SOURCE, TAILLE_SOURCE)
	noeud.position = centre - noeud.size / 2.0
	add_child(noeud)

	var label := Label.new()
	label.position = noeud.position - Vector2(20.0, 24.0)
	label.text = "source_radioactive\nforce_radiation=%.2f" % _source.proprietes.get(PROPRIETE_FORCE, 0.0)
	add_child(label)

func _creer_rendu_mur() -> void:
	var centre := Vector2(_mur.position.x, _mur.position.y)
	_noeud_mur = ColorRect.new()
	_noeud_mur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_noeud_mur.color = Color(0.35, 0.35, 0.4)
	_noeud_mur.size = Vector2(TAILLE_MUR, TAILLE_MUR)
	_noeud_mur.position = centre - _noeud_mur.size / 2.0
	add_child(_noeud_mur)

	_label_mur = Label.new()
	_label_mur.position = _noeud_mur.position - Vector2(20.0, 24.0)
	add_child(_label_mur)

func _poser_camera() -> void:
	var camera := Camera2D.new()
	camera.position = Vector2(_source.position.x, _source.position.y)
	camera.zoom = Vector2(0.55, 0.55)
	camera.enabled = true
	add_child(camera)
