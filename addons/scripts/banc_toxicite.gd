extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_toxicite.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1). Chantier « toxicite --
# empoisonnement par contact » (audit prealable
# audit_colonnes_chimique_nucleaire_magie_prealable.md, colonne chimique #3 :
# "meme idiome que banc_conduction.gd -- un agent en contact avec un objet
# toxique prend des degats continus"). MEME PATRON que banc_conduction.gd,
# SANS le volet propagation/flux (pas de reseau conducteur ici -- un seul
# objet compte a la fois, celui dont le colon est proche) : charge.gd ->
# etat_duree.gd -> depense.gd, patron « accumulation -> etat -> degat » deja
# ferme quatre fois (pourriture/corrosion/solubilite/conduction), applique
# ici a une exposition toxique plutot qu'a l'humidite/l'electricite.
#
# AUCUN MECANISME DU COEUR TOUCHE : charge.gd/etat_duree.gd/etat_effectif.gd/
# depense.gd/objet.gd restent inchanges. Une ligne de donnee au-dela de ce
# fichier et de data/banc_toxicite.json (jetable, propre au banc) :
# "toxicite" rejoint data/proprietes_immuables_composition.json (dormante
# avant ce chantier, comme conductivite_electrique avant banc_conduction.gd) ;
# "empoisonne" rejoint data/etats.json (catalogue PARTAGE, meme famille
# reversible que mouille/pourri/corrode/electrocute -- duree, aucun effet
# module, marqueur de gate pour depense.gd seul, MEME ROLE que "electrocute").
# "poison_demo" (data/materiaux.json) est un materiau de demonstration
# (toxicite 0.9, densite realiste), meme patron que sel_demo/verre_demo.
#
# POURQUOI UN SEUL OBJET COMPTE A LA FOIS (design du banc, pas une limite du
# mecanisme) : les trois objets (poison_demo/fer_toxicite/pierre_toxicite)
# sont espaces de 300 unites, largement au-dela de "portee_charge" (60.0) --
# causes_toxicite() rend une cause par objet a toxicite EFFECTIVE non nulle
# (EtatEffectif.valeur, jamais reimplementee), et c'est charge.gd lui-meme
# (Portee.en_portee, deja partage) qui filtre celles a portee du colon. Le
# colon se deplace entre trois positions fixes (data/banc_toxicite.json:
# positions_colon, offset de 40 unites -- a l'interieur de portee_charge --
# sur chaque objet) : au clic gauche, deplacer_colon() fait avancer un index
# circulaire, jamais une position calculee ailleurs.
#
# POURQUOI PIERRE (toxicite 0.0) NE FAIT RIEN : causes_toxicite() saute tout
# objet a toxicite effective <= 0.0 (meme garde defensive que
# banc_conduction.gd:causes_de_tension sur une conductivite <= 0.0) -- aucune
# cause n'est jamais produite pres de la pierre, la charge du colon decroit
# vers 0.0 au lieu de monter, jamais de franchissement de seuil.
#
# LES DEGATS (charge.gd -> etat_duree.gd -> depense.gd) : le colon
# (colon_toxicite, construit A LA MAIN comme l'agent de banc_conduction.gd --
# aucun pipeline de decision necessaire) accumule une charge "empoisonnement"
# dont l'unique cause possible est l'objet dont il est proche, pondere par SA
# toxicite effective. Au franchissement, charge.gd pose un simple marqueur
# booleen (expose_empoisonnement, jamais etats_actifs directement -- charge.gd
# est symetrique, incompatible avec un retrait PROGRESSIF) ; CE FICHIER, tant
# que le marqueur reste vrai, repose lui-meme EtatDuree.poser("empoisonne")
# CHAQUE tick (remise a 1.0, jamais un cumul, meme idiome que
# banc_conduction.gd/banc_humidite.gd). depense.gd n'a de coefficient par
# receveur : le cout_base du canal "sante" du colon est donc GELE a
# "degat_par_s" (donnee) SEULEMENT tant que "empoisonne" est dans
# etats_actifs, 0.0 sinon -- meme gate exact que "integrite" dans
# banc_conduction.gd.
#
# CE QU'ON DOIT VOIR : trois objets fixes alignes (poison_demo/fer/pierre),
# chacun affichant sa toxicite. Le colon demarre a cote de poison_demo (index
# 0 de positions_colon) ; un clic gauche le deplace vers l'objet suivant,
# cycle circulaire sur les trois. Pres de poison_demo (toxicite 0.9), le
# colon s'empoisonne vite (~1.1s) et sa reserve de sante decroit en continu
# tant qu'il reste expose ; pres du fer (0.1), beaucoup plus lentement
# (~10s) ; pres de la pierre (0.0), jamais -- sa charge d'empoisonnement
# redescend au lieu de monter. S'eloigner (ou passer a un objet moins
# toxique) laisse "empoisonne" s'estomper progressivement (etat_duree.gd,
# duree 3.0s), jamais un retrait instantane ; la reserve de sante cesse alors
# de decroitre.
#
# LIMITE STRICTE (rappel explicite du chantier) : ce fichier, ses donnees et
# ses tests sont le SEUL perimetre au-dela des trois lignes de donnee citees
# plus haut -- charge.gd/etat_effectif.gd/etat_duree.gd/depense.gd/objet.gd
# restent EXACTEMENT ceux deja verrouilles par leurs propres tests, aucun
# n'est touche par ce chantier.
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge les donnees et fabrique objets/agent
#   (Objet.fabriquer pour les objets composes, construction a la main pour
#   l'agent -- meme patron que banc_conduction.gd). _unhandled_input deplace
#   le colon au clic gauche. _process appelle UNIQUEMENT avancer() (fonction
#   statique, ci-dessous) puis lit ses resultats pour l'affichage/la console.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_toxicite.gd) : causes_toxicite/avancer/deplacer_colon/
#   fabriquer_objets/fabriquer_agent/diagnostiquer/diagnostiquer_agent, plus
#   le texte d'affichage et de log.

const Objet = preload("res://scripts/objet.gd")
const Charge = preload("res://scripts/charge.gd")
const EtatDuree = preload("res://scripts/etat_duree.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")
const Depense = preload("res://scripts/depense.gd")

const TAILLE := 70.0
const TAILLE_COLON := 40.0
const HAUTEUR_BARRE := 10.0
const PROPRIETE_TOXICITE := "toxicite"
const SANTE_BARRE_MAX := 10.0

var _config: Dictionary = {}
var _etats: Dictionary = {}
var _materiaux: Dictionary = {}
var _objets: Array = []
var _agent: Dictionary = {}
var _index_colon: int = 0
var _noeuds: Dictionary = {}
var _labels: Dictionary = {}
var _noeud_colon: ColorRect
var _barre_fond_colon: ColorRect
var _barre_remplie_colon: ColorRect
var _label_colon: Label
var _expose_avant: bool = false
var _empoisonne_avant: bool = false
var _temps: float = 0.0

func _ready() -> void:
	_config = _charger_json("res://data/banc_toxicite.json")
	_etats = _charger_json("res://data/etats.json")
	_materiaux = _charger_json("res://data/materiaux.json")
	var proprietes_immuables: Array = _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", [])

	_objets = fabriquer_objets(_config.get("objets", []), _materiaux, proprietes_immuables)
	var pos_depart: Array = _config.positions_colon[0]
	_agent = fabriquer_agent(_config.agent, _config, Vector3(pos_depart[0], pos_depart[1], pos_depart[2]))

	for objet in _objets:
		_creer_rendu_objet(objet)
	_creer_rendu_colon()
	_poser_camera()

	_rafraichir_tout()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_index_colon = deplacer_colon(_agent, _config.positions_colon, _index_colon)
		print(_ligne_deplacement(_temps, _config.objets[_index_colon].id))
		_rafraichir_tout()

func _process(delta: float) -> void:
	_temps += delta
	var resultat := avancer(_objets, _agent, delta, _config, _etats)

	var expose: bool = _agent.proprietes.get(_config.declencheur_expose_empoisonnement, false)
	if expose != _expose_avant:
		var canal: Dictionary = _agent.proprietes.get("etats", {}).get(_config.nom_canal_empoisonnement, {})
		print(_ligne_expose(_temps, expose, canal.get("charge", 0.0), canal.get("seuil", 0.0)))
		_expose_avant = expose

	var empoisonne: bool = _agent.proprietes.get("etats_actifs", []).has(_config.nom_etat_empoisonne)
	if empoisonne != _empoisonne_avant:
		var reserve: float = _agent.proprietes.get("reserves", {}).get(_config.nom_reserve_sante, {}).get("reserve", 0.0)
		print(_ligne_empoisonne(_temps, empoisonne, reserve))
		_empoisonne_avant = empoisonne

	_rafraichir_tout()

func _rafraichir_tout() -> void:
	for objet in _objets:
		_labels[objet.id].text = _texte_label_objet(objet, diagnostiquer(objet, _etats))

	var diag_agent := diagnostiquer_agent(_agent, _config)
	_noeud_colon.color = Color(0.55, 0.15, 0.75) if diag_agent.empoisonne else Color(0.5, 0.5, 0.55)
	_noeud_colon.position = Vector2(_agent.position.x, _agent.position.y) - _noeud_colon.size / 2.0
	var ratio: float = clamp(diag_agent.reserve_sante / SANTE_BARRE_MAX, 0.0, 1.0)
	_barre_fond_colon.position = _noeud_colon.position + Vector2(-5.0, TAILLE_COLON / 2.0 + 6.0)
	_barre_remplie_colon.position = _barre_fond_colon.position
	_barre_remplie_colon.size.x = _barre_fond_colon.size.x * ratio
	_label_colon.position = _noeud_colon.position - Vector2(10.0, 90.0)
	_label_colon.text = _texte_label_colon(diag_agent)

# ---- Fonctions PURES, testables headless (voir test_banc_toxicite.gd) ----

# Une cause par objet a toxicite EFFECTIVE strictement positive (EtatEffectif.
# valeur, jamais reimplementee) -- un objet non toxique (toxicite 0.0, ex.
# pierre) ne produit jamais de cause, meme garde defensive que
# banc_conduction.gd:causes_de_tension. Le filtrage par PORTEE (qui est assez
# proche pour compter) reste entierement delegue a charge.gd (Portee.
# en_portee, deja partage) -- ce fichier ne compare jamais lui-meme des
# positions.
static func causes_toxicite(objets: Array, etats: Dictionary) -> Array:
	var causes: Array = []
	for objet in objets:
		var effective: float = EtatEffectif.valeur(objet, PROPRIETE_TOXICITE, etats)
		if effective <= 0.0:
			continue
		causes.append({"position": objet.position, "poids": effective})
	return causes

# UN PAS de simulation complet, sur l'agent uniquement (les trois objets sont
# immobiles, aucun etat ne les affecte) : (1) charge.gd -> etat_duree.gd sur
# le canal "empoisonnement", meme patron ferme quatre fois (pourriture/
# corrosion/solubilite/conduction) ; (2) depense.gd sur la reserve "sante",
# gelee a "degat_par_s" seulement tant que "empoisonne" est actif. Rend
# { bascules, expirees, franchis_sante } -- memes formes que celles deja
# rendues par Charge.avancer/EtatDuree.avancer/Depense.avancer, jamais
# recalculees ici.
static func avancer(objets: Array, agent: Dictionary, delta: float, config: Dictionary, etats: Dictionary) -> Dictionary:
	var causes := causes_toxicite(objets, etats)
	var bascules := Charge.avancer([agent], causes, delta)
	if agent.proprietes.get(config.declencheur_expose_empoisonnement, false):
		EtatDuree.poser(agent, config.nom_etat_empoisonne, etats)
	var expirees := EtatDuree.avancer([agent], delta, etats)

	var reserves: Dictionary = agent.proprietes.get("reserves", {})
	if reserves.has(config.nom_reserve_sante):
		var actif_empoisonne: bool = agent.proprietes.get("etats_actifs", []).has(config.nom_etat_empoisonne)
		reserves[config.nom_reserve_sante]["cout_base"] = config.degat_par_s if actif_empoisonne else 0.0
	var franchis_sante := Depense.avancer([agent], delta)

	return {
		"bascules": bascules,
		"expirees": expirees,
		"franchis_sante": franchis_sante,
	}

# Avance l'agent a la position suivante de "positions" (Array de [x,y,z]),
# cycle circulaire -- MUTE agent.position en place (Dictionary, reference).
# Rend le nouvel index, pour que l'appelant sache quel objet est desormais
# le plus proche sans le recalculer.
static func deplacer_colon(agent: Dictionary, positions: Array, index: int) -> int:
	var nouvel_index := (index + 1) % positions.size()
	var pos: Array = positions[nouvel_index]
	agent.position = Vector3(pos[0], pos[1], pos[2])
	return nouvel_index

# Construit les objets via Objet.fabriquer (composition fusionnee -- meme
# patron que banc_conduction.gd), catalogue LOCAL a une entree par id.
static func fabriquer_objets(declarations: Array, materiaux: Dictionary, proprietes_immuables: Array) -> Array:
	var catalogue: Dictionary = {}
	for decl in declarations:
		catalogue[decl.id] = {"composition": decl.composition}
	var objets: Array = []
	for decl in declarations:
		var pos: Array = decl.position
		var objet := Objet.fabriquer(decl.id, decl.id, Vector3(pos[0], pos[1], pos[2]), catalogue, materiaux, proprietes_immuables)
		if objet.is_empty():
			continue
		objets.append(objet)
	return objets

# Construit l'agent A LA MAIN (meme patron que banc_conduction.gd) : aucun
# pipeline de decision necessaire, seulement l'exposition (canal
# "empoisonnement", charge.gd) et la reserve consommee ("sante", depense.gd).
static func fabriquer_agent(decl: Dictionary, config: Dictionary, position: Vector3) -> Dictionary:
	return {
		"id": decl.get("id", "agent"),
		"position": position,
		"proprietes": {
			"etats": {config.nom_canal_empoisonnement: config.canal_empoisonnement_defaut.duplicate(true)},
			"etats_actifs": [],
			"reserves": {config.nom_reserve_sante: config.reserve_sante_defaut.duplicate(true)},
		},
	}

# Diagnostic d'affichage, PUR : lit uniquement la toxicite EFFECTIVE d'un
# objet (etat_effectif.gd, jamais reimplementee). Rend { toxicite_effective }.
static func diagnostiquer(objet: Dictionary, etats: Dictionary) -> Dictionary:
	return {"toxicite_effective": EtatEffectif.valeur(objet, PROPRIETE_TOXICITE, etats)}

# Diagnostic d'affichage de l'agent, PUR. Rend { empoisonne, charge, seuil,
# reserve_sante }.
static func diagnostiquer_agent(agent: Dictionary, config: Dictionary) -> Dictionary:
	var canal: Dictionary = agent.proprietes.get("etats", {}).get(config.nom_canal_empoisonnement, {})
	var reserves: Dictionary = agent.proprietes.get("reserves", {})
	return {
		"empoisonne": agent.proprietes.get("etats_actifs", []).has(config.nom_etat_empoisonne),
		"charge": canal.get("charge", 0.0),
		"seuil": canal.get("seuil", 0.0),
		"reserve_sante": reserves.get(config.nom_reserve_sante, {}).get("reserve", 0.0),
	}

static func _texte_label_objet(objet: Dictionary, diag: Dictionary) -> String:
	return "%s\ntoxicite=%.2f" % [objet.id, diag.toxicite_effective]

static func _texte_label_colon(diag: Dictionary) -> String:
	return "colon_toxicite\nempoisonne=%s\ncharge=%.2f/%.2f\nsante=%.2f" % [
		diag.empoisonne, diag.charge, diag.seuil, diag.reserve_sante
	]

static func _ligne_deplacement(t: float, id_objet: String) -> String:
	return "t=%.1fs colon_toxicite : deplace pres de %s" % [t, id_objet]

static func _ligne_expose(t: float, actif: bool, charge: float, seuil: float) -> String:
	return "t=%.1fs colon_toxicite : expose_empoisonnement %s (charge=%.2f, seuil=%.2f)" % [
		t, "POSE" if actif else "RETIRE", charge, seuil
	]

static func _ligne_empoisonne(t: float, empoisonne: bool, reserve: float) -> String:
	if empoisonne:
		return "t=%.1fs colon_toxicite : empoisonne (sante=%.2f)" % [t, reserve]
	return "t=%.1fs colon_toxicite : empoisonnement termine, guerison progressive (sante=%.2f)" % [t, reserve]

# ---- Rendu (impur, Node) -- aucune decision, seulement la construction
# des noeuds et la camera.

func _creer_rendu_objet(objet: Dictionary) -> void:
	var id: String = objet.id
	var centre := Vector2(objet.position.x, objet.position.y)

	var noeud := ColorRect.new()
	noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noeud.color = Color(0.65, 0.2, 0.55)
	noeud.size = Vector2(TAILLE, TAILLE)
	noeud.position = centre - noeud.size / 2.0
	add_child(noeud)
	_noeuds[id] = noeud

	var label := Label.new()
	label.position = centre - Vector2(TAILLE / 2.0, TAILLE / 2.0 + 40.0)
	add_child(label)
	_labels[id] = label

func _creer_rendu_colon() -> void:
	_noeud_colon = ColorRect.new()
	_noeud_colon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_noeud_colon.size = Vector2(TAILLE_COLON, TAILLE_COLON)
	add_child(_noeud_colon)

	_barre_fond_colon = ColorRect.new()
	_barre_fond_colon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_barre_fond_colon.color = Color(0.2, 0.2, 0.2)
	_barre_fond_colon.size = Vector2(TAILLE_COLON + 10.0, HAUTEUR_BARRE)
	add_child(_barre_fond_colon)

	_barre_remplie_colon = ColorRect.new()
	_barre_remplie_colon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_barre_remplie_colon.color = Color(0.2, 0.75, 0.3)
	_barre_remplie_colon.size = Vector2(0.0, HAUTEUR_BARRE)
	add_child(_barre_remplie_colon)

	_label_colon = Label.new()
	add_child(_label_colon)

func _poser_camera() -> void:
	var centre_x := 0.0
	for objet in _objets:
		centre_x += objet.position.x
	centre_x /= float(_objets.size())
	var camera := Camera2D.new()
	camera.position = Vector2(centre_x, 100.0)
	camera.zoom = Vector2(0.75, 0.75)
	camera.enabled = true
	add_child(camera)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
