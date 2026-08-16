extends Node2D

# Cablage de banc VISUEL, separe des autres bancs (Scene/banc_controle.tscn,
# PAS la scene principale -- run/main_scene reste banc_p1). Existe pour VOIR
# la FONDATION du controle direct du joueur : un golem OBEIT (sa position
# vient d'un ordre pose par le clic, jamais d'une decision), un colon DECIDE
# SEUL (pipeline complet perception -> attaches+proximite -> dominance ->
# agir, inchange, memes couches que tous les autres bancs). JETABLE PAR
# DEFINITION : aucune regle de jeu ne doit vivre ici, seulement du cablage.
#
# LA DIFFERENCE VIT EN DONNEE, JAMAIS EN CODE MOTEUR (voir data/types.json:
# dynamique, cles "controlable"/"ordre_joueur"/"lie_au_joueur", chantier
# "controle direct du joueur") : AUCUN mecanisme du coeur n'est touche ni
# ajoute par ce chantier. Ce fichier EST le seul lecteur de ces trois cles a
# ce jour -- c'est lui qui verifie "controlable" avant d'appeler ou non le
# pipeline de decision (voir avancer_controle ci-dessous), jamais un
# mecanisme de scripts/*.gd hors bancs.
#
# CE QUE CE BANC MONTRE : un golem (carre violet, "controlable": true,
# data/banc_controle.json:types.golem) et un colon (carre rouge, herite de
# data/types.json:colon inchange, "controlable" reste a son defaut neutre
# false) partagent le meme monde. Un clic GAUCHE pose un ORDRE sur le golem
# (donner_ordre) : le golem s'y deplace, s'arrete a portee, ne bouge plus
# tant qu'aucun ordre nouveau n'arrive -- SANS ordre, il reste immobile pour
# toujours, il n'a AUCUN pipeline de repli (a la difference du golem
# ILLUSTRATIF de data/types.json:agent._note, qui lui decide via "agent" --
# CE golem-ci ne compose que "dynamique", voir data/banc_controle.json._note).
# Un clic DROIT pose un feu (patron banc_genetique.gd, local, sans
# combustible) : le colon le PERCOIT et decide seul de s'en approcher puis de
# l'eteindre (pipeline normal, "approcher" resolu par data/types_choses.json
# sur "brule") ; le golem, lui, NE REAGIT JAMAIS au feu -- il n'a ni
# "canaux" ni "attaches" (herite: ["dynamique"] seul), donc rien pour le
# CATALOGUE_ACTIONS.
#
# COUT ENERGETIQUE (decision Yael) : le golem porte reserves.energie
# SURCHARGEE EN BLOC (voir data/banc_controle.json._note -- merge superficiel
# de objet.gd:fabriquer, les quatre autres canaux de "dynamique" disparaissent
# volontairement, un golem n'a ni faim ni soif ni sommeil ni besoin de
# chaleur) avec un surcout_action PLUS HAUT que le defaut de "dynamique"
# (2.5 contre 0.7) -- AUCUN mecanisme neuf : Depense.avancer (deja generique,
# inchange) le ponctionne exactement comme il ponctionne les cinq reserves du
# colon. Valeur STATIQUE (donnee, pas un cablage conditionnel) : le cout
# s'applique tout le temps qu'un golem EST controlable, pas seulement le
# temps d'un ordre actif -- lecture la plus simple de "un golem controle
# coute plus cher", a corriger si Yael en veut une autre.
#
# max_par_joueur (data/banc_controle.json:types.golem, valeur 3) : PAS
# exerce par CE banc (un seul golem dans la scene) -- verrouille isolement
# par golems_du_joueur/peut_prendre_controle ci-dessous, sur des fixtures,
# jamais sur le cœur (voir docs/design.md, "Les collectifs n'existent pas" --
# un compte est un calcul a la demande, jamais un objet-groupe).
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge data/banc_controle.json + les paquets
#   partages (objet_physique/dynamique/percevant/agent/colon depuis
#   data/types.json, patron banc_genetique.gd:_ready), fabrique le golem
#   (fabriquer_golem) et le colon (BancCommun.fabriquer_colon), pose la
#   Camera2D. _unhandled_input : clic gauche -> donner_ordre(_golem, ...),
#   clic droit -> pose un feu (Objet.fabriquer, patron banc_genetique.gd).
#   _process fait avancer Depense.avancer (golem + colon, meme appel
#   generique) + Extinction.avancer (agents_rythme ignore le golem, qui ne
#   porte pas "rythme") + avancer_controle(_golem, delta) + agir_et_deplacer
#   (_colon, ...) + rendu (carres, barre d'energie), et imprime les
#   transitions.
# - Fonctions statiques PROPRES a ce banc (pures, testables headless, voir
#   test_banc_controle.gd) : fabriquer_golem, donner_ordre, avancer_controle
#   (LE cablage qui verifie "controlable" avant tout mouvement -- un golem
#   sans "controlable": true, ou une entite dont "ordre_joueur" a ete pose
#   malgre "controlable": false, ne bouge jamais par cette fonction) ;
#   decider/decider_et_memoriser/agir_et_deplacer pour le colon (memes roles
#   que banc_genetique.gd, quatre couches, aucun jugement, aucune fuite) ;
#   golems_du_joueur/peut_prendre_controle pour max_par_joueur (voir
#   ci-dessus) ; _percoit_declencheur/_est_arrive_sur_le_feu, memes
#   detections que banc_genetique.gd, dupliquees ici (meme discipline que
#   banc_genetique.gd applique deja a banc_deformation.gd -- pas descendues
#   dans banc_commun.gd, un deuxieme appelant ne suffit pas a justifier une
#   promotion, voir CARTE.md §6).

const Objet = preload("res://scripts/objet.gd")
const Monde = preload("res://scripts/monde.gd")
const Perception = preload("res://scripts/perception.gd")
const Attaches = preload("res://scripts/attaches.gd")
const Proximite = preload("res://scripts/proximite.gd")
const Dominance = preload("res://scripts/dominance.gd")
const Agir = preload("res://scripts/agir.gd")
const Ciblage = preload("res://scripts/ciblage.gd")
const Depense = preload("res://scripts/depense.gd")
const Extinction = preload("res://scripts/extinction.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")

const TAILLE_CARRE := 24.0
const LARGEUR_BARRE_RESERVE := 24.0
const HAUTEUR_BARRE_RESERVE := 3.0
const ZOOM_CAMERA := 1.0

# Distance sous laquelle un ordre est considere ACCOMPLI (efface
# "ordre_joueur", remis a {}) -- strictement au-dessus du seuil d'arret de
# BancCommun.bouger_vers (1.0) pour ne jamais relire un ordre deja atteint
# comme "encore en cours".
const DISTANCE_ARRIVEE := 2.0

var _donnees: Dictionary = {}
var _catalogue_types: Dictionary = {}
var _catalogue_canaux: Dictionary = {}
var _menaces: Dictionary = {}
var _profils_saillance: Dictionary = {}
var _catalogue_actions: Dictionary = {}
var _orientations: Dictionary = {}
var _transformations: Dictionary = {}
var _catalogue_deformations: Dictionary = {}
var _couleurs_types: Dictionary = {}
var _couleurs_reserves: Dictionary = {}
var _reserves_max: Dictionary = {}
var _monde := Monde.new()
var _golem: Dictionary = {}
var _colon: Dictionary = {}
var _noeuds: Dictionary = {}
var _barres_reserves: Dictionary = {}
var _temps_ecoule := 0.0
var _compteur_feu := 0
var _golem_avait_ordre := false
var _colon_action_precedente := "__jamais__"

func _ready() -> void:
	_donnees = _charger_json("res://data/banc_controle.json")
	_couleurs_types = _donnees.get("couleurs_types", {})
	_couleurs_reserves = _donnees.get("couleurs_reserves", {})
	_reserves_max = _donnees.get("reserves_max", {})

	_catalogue_types = _donnees.get("types", {}).duplicate(true)
	var types_partages := _charger_json("res://data/types.json")
	_catalogue_types["objet_physique"] = types_partages.get("objet_physique", {})
	_catalogue_types["dynamique"] = types_partages.get("dynamique", {})
	_catalogue_types["percevant"] = types_partages.get("percevant", {})
	_catalogue_types["agent"] = types_partages.get("agent", {})
	_catalogue_types["colon"] = types_partages.get("colon", {})

	_catalogue_canaux = _charger_json("res://data/canaux.json")
	_menaces = _charger_json("res://data/menaces.json")
	_profils_saillance = _charger_json("res://data/profils_saillance.json")
	_catalogue_actions = _charger_json("res://data/types_choses.json")
	_orientations = _charger_json("res://data/orientations.json")
	var donnees_transformations := _charger_json("res://data/transformations.json")
	_transformations = donnees_transformations.get("transformations", {})
	# Charge et transmis pour EVITER l'alarme de deformation.gd:biais -- colon
	# herite deformation_sources: ["habituation"] depuis data/types.json,
	# meme geste que banc_genetique.gd/banc_p1.gd.
	_catalogue_deformations = _charger_json("res://data/deformations.json")

	_golem = fabriquer_golem("golem_1", "golem", _donnees.get("golem", {}), _catalogue_types)
	_monde.ajouter(_golem, "golem", _golem.position)
	_noeuds[_golem.id] = _dessiner_carre(_golem.position, _couleur_de("golem"))
	_barres_reserves[_golem.id] = _dessiner_barres_reserves(_golem.proprietes.get("reserves", {}))

	_colon = BancCommun.fabriquer_colon("colon_1", "colon", _donnees.get("colon", {}), _catalogue_types)
	_monde.ajouter(_colon, "colon", _colon.position)
	_noeuds[_colon.id] = _dessiner_carre(_colon.position, _couleur_de("colon"))
	_barres_reserves[_colon.id] = _dessiner_barres_reserves(_colon.proprietes.get("reserves", {}))

	_poser_camera([Vector2(_golem.position.x, _golem.position.y), Vector2(_colon.position.x, _colon.position.y)])

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	var pos := get_global_mouse_position()
	if event.button_index == MOUSE_BUTTON_LEFT:
		donner_ordre(_golem, Vector3(pos.x, pos.y, 0.0))
		print("t=%.1f golem_1 : ordre -> (%.0f, %.0f)" % [_temps_ecoule, pos.x, pos.y])
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_compteur_feu += 1
		var id := "feu_%d" % _compteur_feu
		var position3 := Vector3(pos.x, pos.y, 0.0)
		var feu := Objet.fabriquer(id, "feu", position3, _catalogue_types)
		_monde.ajouter(feu, "feu", position3)
		_noeuds[id] = _dessiner_carre(position3, _couleur_de("feu"))

func _process(delta: float) -> void:
	_temps_ecoule += delta
	var objets := BancCommun.objets_de(_monde)
	Depense.avancer(objets, delta, {})
	var agents := BancCommun.agents_rythme(objets)
	var eteints := Extinction.avancer(objets, agents, delta, _transformations)
	BancCommun.marquer_eteints(eteints, _noeuds, _monde, _couleur_de("cendre"), _temps_ecoule)

	avancer_controle(_golem, delta)
	_redessiner(_golem)
	if _golem_avait_ordre and _golem.proprietes.get("ordre_joueur", {}).is_empty():
		print("t=%.1f golem_1 : arrive, ordre accompli" % _temps_ecoule)
	_golem_avait_ordre = not _golem.proprietes.get("ordre_joueur", {}).is_empty()

	var g := agir_et_deplacer(_colon, _monde, _catalogue_canaux, _menaces, _profils_saillance, _catalogue_deformations, _catalogue_actions, _orientations, delta)
	_redessiner(_colon)
	_imprimer_action_colon(g)

func _imprimer_action_colon(g: Dictionary) -> void:
	var decision = g.decision
	var action_actuelle: String
	if decision == null:
		action_actuelle = "RIEN"
	else:
		action_actuelle = "%s|%s" % [
			String(g.chose.id) if g.chose != null else decision.type,
			BancCommun.verbe_action({"position": g.position_avant}, g.cible, g.chose, _transformations),
		]
	if action_actuelle == _colon_action_precedente:
		return
	_colon_action_precedente = action_actuelle
	if decision == null:
		print("t=%.1f colon_1 : rien a faire" % _temps_ecoule)
	else:
		print("t=%.1f colon_1 : %s" % [_temps_ecoule, action_actuelle])

# Fabrication PURE (testable headless) : ne touche ni _monde ni le rendu.
# "lie_au_joueur" est surchargee depuis decl si presente -- sinon le golem
# reste au defaut neutre de data/types.json:dynamique ("", non revendique).
static func fabriquer_golem(nom: String, type: String, decl: Dictionary, catalogue_types: Dictionary) -> Dictionary:
	var pos: Array = decl.get("position", [0.0, 0.0, 0.0])
	var position3 := Vector3(pos[0], pos[1], pos[2])
	var golem := Objet.fabriquer(nom, type, position3, catalogue_types)
	if decl.has("lie_au_joueur"):
		golem.proprietes["lie_au_joueur"] = decl.lie_au_joueur
	return golem

# Pose un ordre BRUT sur l'entite -- ne verifie JAMAIS "controlable" ici :
# c'est avancer_controle (ci-dessous), au moment de LIRE l'ordre, qui
# tranche s'il doit etre obei. Separer pose/lecture est ce qui permet a
# test_banc_controle.gd de verifier qu'un ordre pose sur une entite
# "controlable": false reste bien sans effet (voir "controlable: false
# ignore ordre_joueur meme si pose" dans les decisions de Yael).
static func donner_ordre(entite: Dictionary, cible: Vector3) -> void:
	entite.proprietes["ordre_joueur"] = {
		"action": "aller",
		"cible": {"x": cible.x, "y": cible.y, "z": cible.z},
	}

# LE CABLAGE qui court-circuite le pipeline de decision (voir en-tete de ce
# fichier) : AUCUN mecanisme du coeur n'est appele ici, seulement une lecture
# de propriete et un deplacement (BancCommun.bouger_vers, deja generique).
# "controlable" absent retombe sur false (defaut neutre de data/types.json:
# dynamique) -- une entite qui ne compose pas "dynamique" du tout (donc sans
# la cle) est logiquement dans le meme cas : jamais controlable, jamais une
# alarme, cablage seul (voir scripts/test_lint_donnees.gd:PROPRIETES_CABLAGE_SEUL).
# "ordre_joueur" vide ({}) : rien a faire, l'entite reste immobile -- AUCUN
# repli sur une decision autonome, ce cablage ne connait que deux etats,
# obeir ou rester immobile.
static func avancer_controle(entite: Dictionary, delta: float) -> void:
	var proprietes: Dictionary = entite.proprietes
	if not proprietes.get("controlable", false):
		return
	var ordre: Dictionary = proprietes.get("ordre_joueur", {})
	if ordre.is_empty():
		return
	var brute: Dictionary = ordre.get("cible", {})
	var cible := Vector3(brute.get("x", 0.0), brute.get("y", 0.0), brute.get("z", 0.0))
	entite.position = BancCommun.bouger_vers(entite.position, cible, proprietes.get("vitesse", 0.0), delta)
	if entite.position.distance_to(cible) < DISTANCE_ARRIVEE:
		proprietes["ordre_joueur"] = {}

# max_par_joueur (voir en-tete) : compte, parmi une liste d'entites brutes,
# combien portent deja "lie_au_joueur" == id_joueur -- un calcul a la
# demande, jamais un objet-groupe (voir docs/design.md, "Les collectifs
# n'existent pas"). Une entite sans "lie_au_joueur" (n'importe quoi qui ne
# compose pas "dynamique") ne compte jamais.
static func golems_du_joueur(objets: Array, id_joueur: String) -> int:
	var compte := 0
	for objet in objets:
		if objet.proprietes.get("lie_au_joueur", "") == id_joueur:
			compte += 1
	return compte

# Vrai si le joueur peut encore prendre le controle d'une entite de plus --
# STRICTEMENT sous le plafond, jamais a l'egalite (3 revendiquees, plafond 3
# -> false). Verifie par le cablage, jamais par le coeur.
static func peut_prendre_controle(objets: Array, id_joueur: String, max_par_joueur: int) -> bool:
	return golems_du_joueur(objets, id_joueur) < max_par_joueur

# QUATRE COUCHES (comme banc_genetique.gd:decider) : perception -> attaches +
# proximite -> dominance -> agir. Aucun jugement (une seule chose saillante
# possible ici, le feu).
static func decider(
	colon: Dictionary,
	monde,
	catalogue_canaux: Dictionary,
	menaces: Dictionary,
	profils_saillance: Dictionary,
	catalogue_deformations: Dictionary,
	catalogue_actions: Dictionary,
) -> Dictionary:
	var perceptions := Perception.percevoir(colon, monde, catalogue_canaux)
	var att := Attaches.evaluer(perceptions, colon, menaces, catalogue_deformations)
	var prox := Proximite.evaluer(perceptions, colon, profils_saillance, catalogue_deformations)
	var resultats: Array = att + prox
	var visibles := Dominance.visibles(resultats, colon)
	var decision = Agir.choisir(visibles, colon, catalogue_actions, monde, {}, {})
	return {"decision": decision, "resultats": resultats, "perceptions": perceptions, "visibles": visibles}

static func decider_et_memoriser(
	colon: Dictionary,
	monde,
	catalogue_canaux: Dictionary,
	menaces: Dictionary,
	profils_saillance: Dictionary,
	catalogue_deformations: Dictionary,
	catalogue_actions: Dictionary,
) -> Dictionary:
	var r := decider(colon, monde, catalogue_canaux, menaces, profils_saillance, catalogue_deformations, catalogue_actions)
	colon.action_en_cours = Agir.etat_courant(r.decision)
	return r

# GESTE COMPLET decision -> mouvement -- AUCUNE branche fuite (catalogue_actions
# de ce banc, data/types_choses.json, ne propose jamais un verbe oriente
# "fuite" dans data/orientations.json).
static func agir_et_deplacer(
	colon: Dictionary,
	monde,
	catalogue_canaux: Dictionary,
	menaces: Dictionary,
	profils_saillance: Dictionary,
	catalogue_deformations: Dictionary,
	catalogue_actions: Dictionary,
	orientations: Dictionary,
	delta: float,
) -> Dictionary:
	var r := decider_et_memoriser(colon, monde, catalogue_canaux, menaces, profils_saillance, catalogue_deformations, catalogue_actions)
	var decision = r.decision
	var position_avant: Vector3 = colon.position
	var cible: Vector3 = colon.position
	var chose = null
	if decision != null:
		chose = Ciblage.viser(decision, r.perceptions, menaces, {}, orientations)
		if chose != null:
			cible = chose.position
		colon.position = BancCommun.bouger_vers(colon.position, cible, colon.proprietes.vitesse, delta)
	return {
		"decision": decision, "resultats": r.resultats, "perceptions": r.perceptions,
		"cible": cible, "chose": chose, "position_avant": position_avant,
	}

# Meme detection que banc_genetique.gd:_percoit_declencheur, dupliquee ici
# (voir en-tete).
static func _percoit_declencheur_statique(perceptions: Array, declencheur: String) -> bool:
	for entree in perceptions:
		if entree.chose.proprietes.get(declencheur, false):
			return true
	return false

func _dessiner_carre(position3: Vector3, couleur: Color) -> ColorRect:
	var carre := ColorRect.new()
	carre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	carre.size = Vector2(TAILLE_CARRE, TAILLE_CARRE)
	carre.color = couleur
	carre.position = Vector2(position3.x, position3.y) - carre.size / 2.0
	add_child(carre)
	return carre

func _couleur_de(nom: String) -> Color:
	var rgb: Array = _couleurs_types.get(nom, [1.0, 1.0, 1.0])
	return Color(rgb[0], rgb[1], rgb[2])

func _couleur_reserve(nom: String) -> Color:
	var rgb: Array = _couleurs_reserves.get(nom, [1.0, 1.0, 1.0])
	return Color(rgb[0], rgb[1], rgb[2])

# Une barre par reserve, meme convention que banc_p1.gd/banc_genetique.gd :
# generique au nombre de reserves portees par CETTE entite (le golem n'en
# porte qu'une, "energie" -- voir data/banc_controle.json._note --, le colon
# les cinq de dynamique), largeur = grandeur visuelle, aucun nombre affiche.
func _dessiner_barres_reserves(reserves: Dictionary) -> Dictionary:
	var barres: Dictionary = {}
	for nom in reserves:
		var barre := ColorRect.new()
		barre.mouse_filter = Control.MOUSE_FILTER_IGNORE
		barre.color = _couleur_reserve(nom)
		add_child(barre)
		barres[nom] = barre
	return barres

func _redessiner(entite: Dictionary) -> void:
	var noeud: ColorRect = _noeuds[entite.id]
	noeud.position = Vector2(entite.position.x, entite.position.y) - noeud.size / 2.0
	var reserves: Dictionary = entite.proprietes.get("reserves", {})
	var barres: Dictionary = _barres_reserves.get(entite.id, {})
	var pos := Vector2(entite.position.x, entite.position.y)
	var i := 0
	for nom in reserves:
		if not barres.has(nom):
			continue
		var valeur: float = reserves[nom].get("reserve", 0.0)
		var maximum: float = _reserves_max.get(nom, 1.0)
		var fraction: float = clamp(valeur / maximum, 0.0, 1.0) if maximum > 0.0 else 0.0
		var y: float = -12.0 - HAUTEUR_BARRE_RESERVE - i * (HAUTEUR_BARRE_RESERVE + 1.0)
		barres[nom].position = pos + Vector2(-LARGEUR_BARRE_RESERVE / 2.0, y)
		barres[nom].size = Vector2(LARGEUR_BARRE_RESERVE * fraction, HAUTEUR_BARRE_RESERVE)
		i += 1

# Camera2D centree sur le MILIEU golem/colon (patron banc_genetique.gd/
# banc_vecu_inter_colon.gd:_poser_camera).
func _poser_camera(positions: Array) -> void:
	var centre := Vector2.ZERO
	for p in positions:
		centre += p
	if positions.size() > 0:
		centre /= positions.size()
	var camera := Camera2D.new()
	camera.position = centre
	camera.zoom = Vector2(ZOOM_CAMERA, ZOOM_CAMERA)
	camera.enabled = true
	add_child(camera)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
