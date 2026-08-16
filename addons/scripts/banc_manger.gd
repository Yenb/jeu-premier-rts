extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_manger.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1). Chantier « consommer.gd --
# transfert destructif + banc_manger » : PREMIERE demonstration reelle de
# scripts/consommer.gd (SIXIEME mecanisme du coeur neuf de la session,
# transfert destructif) et du verbe "manger" (data/types_choses.json,
# donnee pure, zero ligne dans agir.gd -- voir audit_manger_prealable.md).
#
# AUCUN MECANISME DU COEUR TOUCHE : perception.gd/proximite.gd/dominance.gd/
# agir.gd/ciblage.gd/consommer.gd/produit.gd/etat_effectif.gd/objet.gd
# restent inchanges. Ce fichier compose des patrons deja fermes :
# - PIPELINE DE DECISION A TROIS COUCHES (perception -> proximite ->
#   dominance -> agir), meme patron que banc_p1.gd/banc_feu.gd MAIS SANS
#   attaches.gd ni jugement.gd -- ce banc n'a besoin d'aucune menace, d'aucun
#   trait auquel tenir : la SEULE source de saillance est la proximite
#   intrinseque (data/profils_saillance.json:nourriture, catalogue PARTAGE --
#   "nourriture" y a ete AJOUTEE par ce chantier : test_lint_donnees.gd
#   verifie tout champ "profil_saillance" de data/*.json contre CE fichier,
#   quel que soit le fichier source -- une table locale a banc_manger.json
#   n'aurait jamais ete validee, meme collision fermee que leger_golem/
#   aimant_metal dans data/materiaux.json, chantier champ.gd/banc_champ).
#   Omettre attaches.gd est sans consequence : BancCommun.fabriquer_colon
#   pose deja "attaches": [] par defaut, Attaches.evaluer sur une liste vide
#   ne produirait jamais rien de plus -- l'appel est simplement sans objet
#   ici (meme raisonnement que banc_animal.gd, qui ne l'appelle pas non plus).
# - LE VERBE "manger" EST DE LA DONNEE PURE (voir audit_manger_prealable.md
#   §3) : data/types_choses.json:comestible -> ["manger"] (catalogue
#   PARTAGE) resout "decision.action == 'manger'" des que "nourriture"
#   (type LOCAL a ce banc, jamais data/types.json) porte "comestible": true
#   ET que colon.proprietes.poids_verbes["manger"] est strictement positif.
#   "bois_manger"/"pierre_manger" ne portent NI "comestible" NI
#   "profil_saillance" : ils ne sont jamais percus comme saillants, jamais
#   candidats de decision -- le colon les ignore entierement, pas seulement
#   "ne les mange pas".
# - L'EXECUTION (perte de contenu + gain d'energie) N'EST PAS FAITE PAR
#   agir.gd (voir audit_manger_prealable.md §3/§4, "agir.gd ne produit
#   qu'une String") -- avancer_repas() (CE FICHIER) verifie
#   decision.action == "manger" ET la portee physique (portee_manger,
#   donnee), calcule taux = taux_base * comestibilite_EFFECTIVE *
#   valeur_nutritive_energie_EFFECTIVE (EtatEffectif.valeur, JAMAIS
#   reimplementee -- une ration "pourrie" ecraserait comestibilite a 0.0,
#   taux tombe a 0.0, Consommer.transferer(taux=0.0) ne fait deja rien, voir
#   test_consommer.gd -- AUCUN cas particulier code ici pour "pourri"), puis
#   appelle Consommer.transferer (INCHANGE) une fois par tick tant que la
#   nourriture est a portee et que le verbe resolu reste "manger". Quand la
#   reserve "contenu" atteint zero, avancer_transformation_repas() (CE
#   FICHIER) appelle Produit.transformer (INCHANGE, meme geste
#   proprietes.clear()+merge() que banc_coupe.gd) vers "reste_nourriture" --
#   type PARTAGE (data/types.json, meme raison que "nourriture" sur
#   data/profils_saillance.json : "type_produit" est verifie par le meme
#   linter contre CE catalogue, quel que soit le fichier source) -- jamais
#   fait par consommer.gd lui-meme (meme discipline que frappe.gd, qui ne
#   transforme jamais).
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge les donnees/catalogues partagees
#   (data/types.json pour les paquets du colon + "reste_nourriture" ;
#   data/types_choses.json pour la resolution du verbe ; data/
#   profils_saillance.json pour la saillance) et un catalogue LOCAL pour
#   nourriture/bois_manger/pierre_manger seuls (jamais data/types.json).
#   _process appelle
#   UNIQUEMENT agir_et_deplacer() puis avancer_repas()/
#   avancer_transformation_repas() (fonctions statiques, ci-dessous) avant
#   de lire leurs resultats pour l'affichage/la console.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_manger.gd) : decider/decider_et_memoriser/agir_et_deplacer
#   (pipeline de decision), avancer_repas/avancer_transformation_repas
#   (execution), fabriquer_objets, plus le texte d'affichage et de log.

const Objet = preload("res://scripts/objet.gd")
const Perception = preload("res://scripts/perception.gd")
const Proximite = preload("res://scripts/proximite.gd")
const Dominance = preload("res://scripts/dominance.gd")
const Agir = preload("res://scripts/agir.gd")
const Ciblage = preload("res://scripts/ciblage.gd")
const Consommer = preload("res://scripts/consommer.gd")
const Produit = preload("res://scripts/produit.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")
const Monde = preload("res://scripts/monde.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")

const PROPRIETE_COMESTIBILITE := "comestibilite"
const PROPRIETE_VALEUR_NUTRITIVE := "valeur_nutritive_energie"
const VERBE_MANGER := "manger"

const TAILLE := 60.0
const TAILLE_COLON := 36.0

var _config: Dictionary = {}
var _catalogue_types: Dictionary = {}
var _catalogue_actions: Dictionary = {}
var _profils_saillance: Dictionary = {}
var _catalogue_canaux: Dictionary = {}
var _materiaux: Dictionary = {}
var _proprietes_immuables: Array = []
var _etats: Dictionary = {}
var _monde := Monde.new()
var _objets: Array = []
var _colon: Dictionary = {}
var _noeuds: Dictionary = {}
var _labels: Dictionary = {}
var _label_colon: Label
var _noeud_colon: ColorRect
var _transforme_avant: bool = false
var _temps: float = 0.0

func _ready() -> void:
	_config = _charger_json("res://data/banc_manger.json")
	_materiaux = _charger_json("res://data/materiaux.json")
	_proprietes_immuables = _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", [])
	_etats = _charger_json("res://data/etats.json")
	_catalogue_canaux = _charger_json("res://data/canaux.json")
	_catalogue_actions = _charger_json("res://data/types_choses.json")
	_profils_saillance = _charger_json("res://data/profils_saillance.json")

	_catalogue_types = _config.get("types", {}).duplicate(true)
	var types_partages := _charger_json("res://data/types.json")
	_catalogue_types["objet_physique"] = types_partages.get("objet_physique", {})
	_catalogue_types["dynamique"] = types_partages.get("dynamique", {})
	_catalogue_types["percevant"] = types_partages.get("percevant", {})
	_catalogue_types["agent"] = types_partages.get("agent", {})
	_catalogue_types["colon"] = types_partages.get("colon", {})
	_catalogue_types["reste_nourriture"] = types_partages.get("reste_nourriture", {})

	_objets = fabriquer_objets(_config.get("objets", []), _catalogue_types, _materiaux, _proprietes_immuables)
	for objet in _objets:
		_monde.ajouter(objet, objet.get("proprietes_type", ""), objet.position)
		_creer_rendu_objet(objet)

	_colon = BancCommun.fabriquer_colon(_config.colon.id, "colon", _config.colon, _catalogue_types)
	_monde.ajouter(_colon, "colon", _colon.position)
	_creer_rendu_colon()

	_poser_camera()
	_rafraichir_tout()

func _process(delta: float) -> void:
	_temps += delta
	var g := agir_et_deplacer(_colon, _monde, _catalogue_canaux, _profils_saillance, _catalogue_actions, delta)

	var nourriture := _nourriture()
	if not nourriture.is_empty():
		var repas := avancer_repas(g.decision, _colon, _config, _etats, delta)
		if repas.mange:
			print(_ligne_mange(_temps, nourriture.id, nourriture.proprietes.reserves.contenu.reserve, _colon.proprietes.reserves.energie.reserve))
		if repas.source_epuisee and not _transforme_avant:
			var transforme := avancer_transformation_repas(nourriture, _config, _catalogue_types, _materiaux)
			if transforme:
				_transforme_avant = true
				print(_ligne_transforme(_temps, nourriture.id))

	_rafraichir_tout()

func _nourriture() -> Dictionary:
	for objet in _objets:
		if objet.proprietes.has("reserves") and objet.proprietes.reserves.has(_config.nom_reserve_contenu):
			return objet
	return {}

func _rafraichir_tout() -> void:
	for objet in _objets:
		_noeuds[objet.id].color = _couleur_objet(objet)
		_labels[objet.id].text = _texte_objet(objet, _config, _etats)
	_noeud_colon.position = Vector2(_colon.position.x, _colon.position.y) - _noeud_colon.size / 2.0
	_label_colon.text = _texte_colon(_colon, _config)

# ---- Fonctions PURES, testables headless (voir test_banc_manger.gd) ----

# Construit nourriture/bois/pierre via Objet.fabriquer (composition
# fusionnee -- meme patron que banc_coupe.gd/banc_toxicite.gd), catalogue
# LOCAL (jamais data/types.json). Chaque objet garde son type d'origine
# sous "proprietes_type" (String, propre a CE banc, jamais lue par le coeur)
# -- seul moyen pour ce fichier de savoir, apres transformation, qu'un objet
# est devenu "reste_nourriture" sans comparer un nom en dur ailleurs.
static func fabriquer_objets(declarations: Array, table_types: Dictionary, materiaux: Dictionary, proprietes_immuables: Array) -> Array:
	var objets: Array = []
	for decl in declarations:
		var pos: Array = decl.position
		var objet := Objet.fabriquer(decl.id, decl.type, Vector3(pos[0], pos[1], pos[2]), table_types, materiaux, proprietes_immuables)
		if objet.is_empty():
			continue
		objet["proprietes_type"] = decl.type
		objets.append(objet)
	return objets

# TROIS COUCHES (perception -> proximite -> dominance -> agir), jamais
# attaches.gd ni jugement.gd -- voir en-tete du fichier. Rend { decision,
# resultats, perceptions, visibles }, meme forme que banc_p1.gd/banc_feu.gd.
static func decider(
	colon: Dictionary,
	monde,
	catalogue_canaux: Dictionary,
	profils_saillance: Dictionary,
	catalogue_actions: Dictionary,
) -> Dictionary:
	var perceptions := Perception.percevoir(colon, monde, catalogue_canaux)
	var resultats := Proximite.evaluer(perceptions, colon, profils_saillance)
	var visibles := Dominance.visibles(resultats, colon)
	var decision = Agir.choisir(visibles, colon, catalogue_actions, monde)
	return {"decision": decision, "resultats": resultats, "perceptions": perceptions, "visibles": visibles}

static func decider_et_memoriser(
	colon: Dictionary,
	monde,
	catalogue_canaux: Dictionary,
	profils_saillance: Dictionary,
	catalogue_actions: Dictionary,
) -> Dictionary:
	var r := decider(colon, monde, catalogue_canaux, profils_saillance, catalogue_actions)
	colon.action_en_cours = Agir.etat_courant(r.decision)
	return r

# GESTE COMPLET decision -> mouvement, meme role qu'en banc_p1.gd/
# banc_feu.gd, adapte a l'absence de fuite ici (aucun verbe de ce banc n'est
# oriente "fuite" -- data/orientations.json n'est meme pas charge). MUTE
# colon.position EN PLACE.
static func agir_et_deplacer(
	colon: Dictionary,
	monde,
	catalogue_canaux: Dictionary,
	profils_saillance: Dictionary,
	catalogue_actions: Dictionary,
	delta: float,
) -> Dictionary:
	var r := decider_et_memoriser(colon, monde, catalogue_canaux, profils_saillance, catalogue_actions)
	var decision = r.decision
	var position_avant: Vector3 = colon.position
	var cible: Vector3 = colon.position
	var chose = null
	if decision != null:
		chose = Ciblage.viser(decision, r.perceptions, {}, {}, {})
		if chose != null:
			cible = chose.position
		colon.position = BancCommun.bouger_vers(colon.position, cible, colon.proprietes.vitesse, delta)
	return {"decision": decision, "resultats": r.resultats, "cible": cible, "chose": chose, "position_avant": position_avant}

# UN PAS de consommation : ne fait rien si le verbe resolu n'est pas
# "manger" (bois/pierre ne le resolvent jamais, voir en-tete) ou si le
# colon n'est pas encore a "portee_manger" de la chose visee. taux compose
# comestibilite et valeur_nutritive_energie EFFECTIVES (EtatEffectif.valeur,
# jamais reimplementee) -- une ration a comestibilite effective nulle
# (ecrasee par un etat, ex. "pourri") donne taux=0.0, Consommer.transferer
# ne fait alors deja rien (voir test_consommer.gd), aucun cas particulier
# code ici. Rend { mange: bool, source_epuisee: bool }.
static func avancer_repas(
	decision: Variant,
	colon: Dictionary,
	config: Dictionary,
	etats: Dictionary,
	delta: float,
) -> Dictionary:
	if decision == null or decision.get("action", "") != VERBE_MANGER or not decision.has("chose"):
		return {"mange": false, "source_epuisee": false}
	var nourriture: Dictionary = decision.chose
	if colon.position.distance_to(nourriture.position) > float(config.portee_manger):
		return {"mange": false, "source_epuisee": false}
	var comestibilite_eff: float = EtatEffectif.valeur(nourriture, PROPRIETE_COMESTIBILITE, etats)
	var valeur_eff: float = EtatEffectif.valeur(nourriture, PROPRIETE_VALEUR_NUTRITIVE, etats)
	var taux: float = float(config.taux_base) * comestibilite_eff * valeur_eff
	var resultat := Consommer.transferer(nourriture, colon, config.nom_reserve_contenu, config.nom_reserve_energie, taux, delta)
	return {"mange": taux > 0.0, "source_epuisee": resultat.source_epuisee}

# Transforme la nourriture en "reste_nourriture" une fois "contenu" epuise
# (Produit.transformer, INCHANGE, meme geste proprietes.clear()+merge() que
# banc_coupe.gd:avancer_transformation). IDEMPOTENT SANS MARQUEUR
# SUPPLEMENTAIRE : le garde est la PRESENCE de la reserve elle-meme -- une
# fois transformee, "reserves" disparait entierement (proprietes.clear()),
# le second appel ne retrouve donc plus jamais "contenu" et rend faux sans
# retenter. Rend vrai seulement si une transformation a reellement eu lieu.
static func avancer_transformation_repas(
	nourriture: Dictionary,
	config: Dictionary,
	table_types: Dictionary,
	materiaux: Dictionary,
) -> bool:
	var reserves: Dictionary = nourriture.proprietes.get("reserves", {})
	if not reserves.has(config.nom_reserve_contenu):
		return false
	if reserves[config.nom_reserve_contenu].get("reserve", 0.0) > 0.0:
		return false
	var nouvelles_proprietes: Dictionary = Produit.transformer(nourriture.proprietes, config.transformation_reste, table_types, materiaux)
	if nouvelles_proprietes.is_empty():
		return false
	nourriture.proprietes.clear()
	nourriture.proprietes.merge(nouvelles_proprietes, true)
	nourriture["proprietes_type"] = config.transformation_reste.type_produit
	return true

static func _texte_objet(objet: Dictionary, config: Dictionary, etats: Dictionary) -> String:
	var proprietes: Dictionary = objet.proprietes
	var reserves: Dictionary = proprietes.get("reserves", {})
	if reserves.has(config.nom_reserve_contenu):
		var contenu: float = reserves[config.nom_reserve_contenu].get("reserve", 0.0)
		var comestibilite_eff: float = EtatEffectif.valeur(objet, PROPRIETE_COMESTIBILITE, etats)
		var valeur_eff: float = EtatEffectif.valeur(objet, PROPRIETE_VALEUR_NUTRITIVE, etats)
		return "%s\ncontenu=%.2f\ncomestibilite=%.2f\nvaleur_nutritive_energie=%.2f" % [objet.id, contenu, comestibilite_eff, valeur_eff]
	return "%s\ncomestibilite=%.2f" % [objet.id, proprietes.get(PROPRIETE_COMESTIBILITE, 0.0)]

static func _texte_colon(colon: Dictionary, config: Dictionary) -> String:
	var energie: float = colon.proprietes.get("reserves", {}).get(config.nom_reserve_energie, {}).get("reserve", 0.0)
	var action: Dictionary = colon.get("action_en_cours", {})
	var action_texte: String = String(action.get("id", action.get("type", "aucune")))
	return "%s\nenergie=%.2f\naction=%s" % [colon.id, energie, action_texte]

static func _ligne_mange(t: float, id_nourriture: String, contenu_restant: float, energie: float) -> String:
	return "t=%.1fs colon_manger : mange %s (contenu restant=%.2f, energie=%.2f)" % [t, id_nourriture, contenu_restant, energie]

static func _ligne_transforme(t: float, id_nourriture: String) -> String:
	return "t=%.1fs %s : contenu epuise, transforme en reste_nourriture" % [t, id_nourriture]

# ---- Rendu (impur, Node) -- aucune decision, seulement la construction
# des noeuds et la camera.

func _couleur_objet(objet: Dictionary) -> Color:
	var type: String = objet.get("proprietes_type", "")
	var rgb: Array = _config.get("couleurs", {}).get(type, [1.0, 1.0, 1.0])
	return Color(rgb[0], rgb[1], rgb[2])

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
	label.position = centre - Vector2(TAILLE / 2.0, TAILLE / 2.0 + 60.0)
	add_child(label)
	_labels[id] = label

func _creer_rendu_colon() -> void:
	_noeud_colon = ColorRect.new()
	_noeud_colon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_noeud_colon.size = Vector2(TAILLE_COLON, TAILLE_COLON)
	var rgb: Array = _config.get("couleurs", {}).get("colon", [1.0, 1.0, 1.0])
	_noeud_colon.color = Color(rgb[0], rgb[1], rgb[2])
	add_child(_noeud_colon)

	_label_colon = Label.new()
	_label_colon.position = Vector2(_colon.position.x, _colon.position.y) - Vector2(20.0, 90.0)
	add_child(_label_colon)

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
