extends Node2D

# Cablage de banc VISUEL, separe de banc_p1/banc_feu/banc_animal
# (Scene/banc_charge.tscn, PAS la scene principale -- run/main_scene reste
# banc_p1). Existe pour VOIR scripts/charge.gd (le mecanisme
# "charge") JOUER EN JEU -- il tournait deja, ferme et teste, mais aucun
# banc ne l'invoquait avant celui-ci (voir CARTE.md §2, charge.gd
# "Non cable a ce jour"). JETABLE PAR DEFINITION : aucune regle de jeu ne
# doit vivre ici, seulement du cablage.
#
# CE QUE CE BANC MONTRE : deux colons, memes couches, seul le SEUIL de
# charge differe (prudent haut, peureux bas -- data/banc_charge.json).
# Chacun porte un canal proprietes.etats.peur qui MONTE tant qu'un feu
# (proprietes.brule) est a portee, FRANCHIT son seuil et pose "effraye" --
# le peureux bascule apres une exposition courte, le prudent apres une
# exposition longue, tous deux par le MEME code (charge.gd ignore
# lequel des deux colons il traite). Quand les feux disparaissent, la
# charge redescend et "effraye" se retire -- le colon revient eteindre.
#
# LE PROBLEME QUE CE CABLAGE RESOUT (constat avant code, voir CLAUDE.md) :
# jugement.gd calcule sa PRESSION en sommant les saillances de "resultats"
# (att+prox) portees par des choses PERCUES qui ont le declencheur. Pour
# qu'"effraye" (pose sur le colon LUI-MEME) alimente cette pression, il
# faudrait que le colon apparaisse dans "resultats" avec une saillance --
# donc qu'il se PERCOIVE lui-meme (profil_saillance sur lui-meme). C'est
# exactement le cas fragile signale par CARTE.md §6, "Auto-exclusion du
# colon" : "le jour ou un colon devient perceptible... il faudra reposer
# la question de l'auto-perception, pas supposer qu'elle reste vraie". En
# plus, si le colon entrait dans "resultats", il entrerait aussi dans
# "tous" -> Dominance -> Agir : s'il y domine, agir.gd tente d'agir SUR LUI-
# MEME (aucune propriete actionnable dessus) -> action vide -> LE COLON SE
# FIGE, au lieu de fuir ou se proteger.
#
# SOLUTION (validee avec Yael avant d'ecrire ce fichier) : decider(),
# ci-dessous, separe les DEUX usages de "resultats" -- "resultats"
# (att+prox) alimente Dominance normalement, SANS jamais porter d'entree
# pour le colon lui-meme (aucun risque de gel) ; un array SEPARE,
# "source_pression" = resultats + une entree synthetique { chose: colon,
# saillance: intensite_interne } AJOUTEE SEULEMENT SI le colon porte deja
# la propriete declencheur_interne ("effraye"), sert UNIQUEMENT de 3e
# argument a Jugement.evaluer -- jamais melange a "tous"/dominance.
# jugement.gd (coeur) n'est pas touche : il recoit juste un array construit
# differemment par ce cablage.
#
# DONNEE AJOUTEE (jugements.json, PARTAGE) : une seule cle, "refuge":
# "effraye" -- AJOUTEE a cote de "abrite": "brule" (jamais ecrasee),
# inerte pour banc_feu.gd (rien la-bas ne porte "refuge" ni "effraye").
# eau/pierre portent ici "refuge" (PAS "abrite" -- aucun canal brule/abrite
# dans ce banc, uniquement charge/effraye).
#
# declencheur_charge ("brule"), declencheur_interne ("effraye") et
# intensite_interne (magnitude de l'entree synthetique) arrivent en
# PARAMETRE depuis data/banc_charge.json -- jamais ecrits en dur dans ce
# fichier : meme discipline que banc_feu.gd ("Aucun nom de propriete n'est
# ecrit en dur dans ce fichier").
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge data/banc_charge.json + les tables
#   partagees (types_choses.json, jugements.json, orientations.json,
#   profils_saillance.json, transformations.json, et depuis PHASE 3 piece 2
#   les entrees entite/colon de types.json, fusionnees par-dessus le
#   catalogue local -- voir plus bas). _unhandled_input allume
#   un feu au clic (identique aux autres bancs). _process fait avancer,
#   DANS CET ORDRE : causes_de (derive les feux-causes du monde brut) ->
#   Charge.avancer (les colons portent les canaux de charge) ->
#   Extinction.avancer -> chaque colon (agir_et_deplacer, pipeline CINQ
#   COUCHES avec jugement, comme banc_feu.gd).
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_charge.gd) : decider/decider_et_memoriser/agir_et_deplacer
#   (memes roles qu'en banc_feu.gd, signature augmentee de
#   declencheur_interne/intensite_interne, et depuis PHASE 4 piece 3
#   catalogue_deformations -- data/deformations.json, transmis tel quel a
#   Proximite.evaluer) ; causes_de et
#   _fabriquer_colon_charge, LOCAUX A CE FICHIER (pas descendus dans
#   banc_commun.gd -- causes_de prend son nom de propriete en parametre
#   donc respecterait le critere d'entree de la boite a outils partagee,
#   mais cette session n'a pas touche banc_commun.gd, seulement CREE des
#   fichiers ; a reconsiderer une prochaine session si un second banc en a
#   besoin).
#
# LA PROPRIETE "refuge" ET SA TABLE DE VERBES SONT PROPRES A CE BANC (meme
# exception banc-jetable que banc_feu.gd) : data/banc_charge.json porte
# "types" (eau/pierre/feu, catalogue de FABRICATION local pour ce
# vocabulaire propre au banc) et "catalogue_local" ({ "refuge": {
# "verbes": [...] } }), fusionne dans _catalogue_actions par-dessus
# data/types_choses.json (partage, donne "brule" -> approcher, inchange).
# "colon" N'EST PLUS local depuis PHASE 3 piece 2 (chantier "L'entite comme
# agent complet") : _ready fusionne entite/colon depuis data/types.json
# par-dessus ce catalogue, colon.etats.peur y est herite -- voir
# _fabriquer_colon_charge pour la surcharge par colon du seuil.
#
# PROFIL_SAILLANCE RETIRE LOCALEMENT SUR LE COLON (audit 2026-08-06, defaut
# "les colons s'empilent au repos") : data/types.json:colon porte
# profil_saillance: "colon" depuis le chantier "colon saillant", herite ici
# par la meme fusion. CHOIX (different de banc_p1.gd) : ce banc retire la
# reference EN LOCAL sur son colon (_ajouter_colon), meme patron que
# banc_lien_personnel.gd -- pas DISTANCE_ARRET_COLON. RAISON : le sujet de
# CE banc est la bascule prudent/peureux selon la DUREE d'exposition a un
# feu, sous exposition identique (memes feux, memes distances au feu) -- la
# convergence colon-vers-colon deplacerait les colons l'un vers l'autre
# independamment de l'exposition mesuree, brouillant la comparaison des deux
# rythmes de charge. banc_p1.gd, lui, DEMONTRE la convergence elle-meme
# (voir prototypes.md) -- pas le sujet ici. proximite.gd traite une cle
# absente comme une chose non saillante, point neutre deja legitime
# (ref == "" -> continue) : aucune alarme, aucun effet sur "brule"/"refuge"
# (ni feu ni eau/pierre ne sont des colons).

const Perception = preload("res://scripts/perception.gd")
const Attaches = preload("res://scripts/attaches.gd")
const Proximite = preload("res://scripts/proximite.gd")
const Jugement = preload("res://scripts/jugement.gd")
const Dominance = preload("res://scripts/dominance.gd")
const Agir = preload("res://scripts/agir.gd")
const Ciblage = preload("res://scripts/ciblage.gd")
const Fuite = preload("res://scripts/fuite.gd")
const Monde = preload("res://scripts/monde.gd")
const Extinction = preload("res://scripts/extinction.gd")
const Charge = preload("res://scripts/charge.gd")
const Objet = preload("res://scripts/objet.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")

# Convention de RENDU, jetable, jamais lue par le coeur : le carre d'un
# colon passe a cette couleur quand declencheur_interne ("effraye") est
# pose sur ses proprietes, revient a sa couleur d'origine (_couleurs_types)
# quand il se retire -- lu directement sur bascules (Charge.avancer),
# jamais un etat suivi a la main a cote.
const _COULEUR_EFFRAYE := Color(1.0, 0.2, 0.2)

var _couleurs_types: Dictionary = {}
var _catalogue_types: Dictionary = {}
var _catalogue_actions: Dictionary = {}
var _jugements: Dictionary = {}
var _orientations: Dictionary = {}
var _menaces: Dictionary = {}
var _profils_saillance: Dictionary = {}
var _catalogue_deformations: Dictionary = {}
var _catalogue_canaux: Dictionary = {}
var _catalogue_attaches_par_trait: Dictionary = {}
var _monde := Monde.new()
var _noeuds: Dictionary = {}
var _patron: Dictionary = {}
var _transformations: Dictionary = {}
var _declencheur_charge := ""
var _declencheur_interne := ""
var _intensite_interne := 0.0
var _compteur_feu := 0

var _colons: Array = []
var _temps_ecoule := 0.0

func _ready() -> void:
	var donnees := _charger_json("res://data/banc_charge.json")
	_couleurs_types = donnees.get("couleurs_types", {})
	_catalogue_types = donnees.get("types", {})
	# "colon" (et objet_physique/dynamique/percevant/agent, requis par sa fusion herite a
	# plat -- refonte "eclatement du corps interne") viennent du catalogue
	# PARTAGE (data/types.json), pas du catalogue local -- colon y porte
	# etats.peur depuis PHASE 3 piece 2 (voir _fabriquer_colon_charge pour
	# la surcharge par colon du seuil). eau/pierre/feu restent locaux
	# (vocabulaire propre a ce banc, voir data/banc_charge.json:_note).
	var types_partages := _charger_json("res://data/types.json")
	_catalogue_types["objet_physique"] = types_partages.get("objet_physique", {})
	_catalogue_types["dynamique"] = types_partages.get("dynamique", {})
	_catalogue_types["percevant"] = types_partages.get("percevant", {})
	_catalogue_types["agent"] = types_partages.get("agent", {})
	_catalogue_types["colon"] = types_partages.get("colon", {})
	_catalogue_actions = _charger_json("res://data/types_choses.json")
	var local: Dictionary = donnees.get("catalogue_local", {})
	for cle in local:
		_catalogue_actions[cle] = local[cle]
	_jugements = _charger_json("res://data/jugements.json")
	_orientations = _charger_json("res://data/orientations.json")
	_profils_saillance = _charger_json("res://data/profils_saillance.json")
	_catalogue_deformations = _charger_json("res://data/deformations.json")
	_catalogue_canaux = _charger_json("res://data/canaux.json")
	_catalogue_attaches_par_trait = _charger_json("res://data/attaches_par_trait.json")
	var donnees_transformations := _charger_json("res://data/transformations.json")
	_patron = donnees_transformations.get("patron", {})
	_transformations = donnees_transformations.get("transformations", {})
	_declencheur_charge = donnees.get("declencheur_charge", "")
	_declencheur_interne = donnees.get("declencheur_interne", "")
	_intensite_interne = donnees.get("intensite_interne", 0.0)

	var i := 0
	for instance in donnees.get("instances", []):
		var id := "%s_%d" % [instance["type"], i]
		i += 1
		_ajouter_chose(id, instance["type"], instance["position"])

	var declarations: Dictionary = donnees.get("colons", {})
	for nom in declarations:
		_ajouter_colon(nom, declarations[nom])

func _ajouter_colon(nom: String, decl: Dictionary) -> void:
	var colon := _fabriquer_colon_charge(nom, "colon", decl, _catalogue_types)
	# COLON SAILLANT, RETIRE LOCALEMENT -- voir en-tete du fichier
	# ("PROFIL_SAILLANCE RETIRE LOCALEMENT SUR LE COLON"). proximite.gd
	# traite une cle absente comme une chose non saillante (ref == "" ->
	# continue), jamais une alarme.
	colon.proprietes.erase("profil_saillance")
	var pos: Array = decl.get("position", [0.0, 0.0, 0.0])
	_monde.ajouter(colon, "colon", colon.position)
	_colons.append(colon)
	_noeuds[colon.id] = _dessiner_carre(nom, pos)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_compteur_feu += 1
		var pos := get_global_mouse_position()
		var id := "feu_%d" % _compteur_feu
		_ajouter_chose(id, "feu", [pos.x, pos.y, 0.0])
		BancCommun.resoudre_chantier(_monde.par_id(id).chose.proprietes, _patron)

func _process(delta: float) -> void:
	_temps_ecoule += delta
	var objets := BancCommun.objets_de(_monde)
	var causes := causes_de(objets, _declencheur_charge)
	var bascules := Charge.avancer(objets, causes, delta)
	for colon in _colons:
		if not bascules.has(colon.id):
			continue
		var effraye: bool = colon.proprietes.get(_declencheur_interne, false)
		var noeud: ColorRect = _noeuds[colon.id]
		noeud.color = _COULEUR_EFFRAYE if effraye else _couleur_de(colon.id)
		print("%s : %s %s" % [colon.id, _declencheur_interne, "POSÉ" if effraye else "RETIRÉ"])
	var agents := BancCommun.agents_rythme(objets)
	var eteints := Extinction.avancer(objets, agents, delta, _transformations)
	BancCommun.marquer_eteints(eteints, _noeuds, _monde, _couleur_de("cendre"), _temps_ecoule)
	for colon in _colons:
		_faire_agir_colon(colon, delta)

func _faire_agir_colon(colon: Dictionary, delta: float) -> void:
	var g := agir_et_deplacer(
		colon, _monde, _catalogue_canaux, _menaces, _profils_saillance, _catalogue_deformations, _jugements, _catalogue_actions,
		_orientations, _declencheur_interne, _intensite_interne, delta, _catalogue_attaches_par_trait,
	)
	var decision = g.decision
	var action_actuelle: String
	if decision == null:
		action_actuelle = "RIEN"
	elif g.fuite:
		action_actuelle = "%s|fuit" % _etiquette_decision(decision)
	else:
		action_actuelle = "%s|%s" % [
			_etiquette_decision(decision),
			BancCommun.verbe_action({"position": g.position_avant}, g.cible, g.chose, _transformations),
		]
	if action_actuelle != colon.action_precedente:
		colon.action_precedente = action_actuelle
		if decision == null:
			print("t=%.1f %s : 0 saillance -> RIEN (aucun feu)" % [_temps_ecoule, colon.id])
		elif g.fuite:
			print("t=%.1f %s : %d saillance(s) -> fuit %s" % [
				_temps_ecoule, colon.id, g.resultats.size(), _etiquette_decision(decision),
			])
		else:
			var dist: float = g.position_avant.distance_to(g.cible)
			print("t=%.1f %s : %d saillance(s) -> %s (dist %.0f) -> %s" % [
				_temps_ecoule, colon.id, g.resultats.size(), _etiquette_decision(decision), dist,
				BancCommun.verbe_action({"position": g.position_avant}, g.cible, g.chose, _transformations),
			])
	if decision != null:
		var noeud: ColorRect = _noeuds[colon.id]
		noeud.position = Vector2(colon.position.x, colon.position.y) - noeud.size / 2.0

func _etiquette_decision(decision: Dictionary) -> String:
	var chose = decision.get("chose", null)
	if chose is Dictionary:
		return String(chose.get("id", decision.type))
	return String(decision.type)

# Derive du monde BRUT (Array nu, voir BancCommun.objets_de) les CAUSES
# de charge : toute chose portant la propriete "propriete_cause" a
# vrai, aplatie en { position } (poids par defaut 1.0, voir
# charge.gd). Nom de propriete arrive en PARAMETRE -- aucun nom de
# contenu ecrit en dur ici, meme critere que les outils de banc_commun.gd
# (voir en-tete de ce fichier).
static func causes_de(objets: Array, propriete_cause: String) -> Array:
	var causes: Array = []
	for chose in objets:
		if chose.proprietes.get(propriete_cause, false):
			causes.append({"position": chose.position})
	return causes

# BancCommun.fabriquer_colon (via Objet.fabriquer) a deja pose
# proprietes.etats depuis data/types.json:colon (herite_entite, PHASE 3
# piece 2) -- portee_charge/taux_decroissance/poser/charge, communs aux
# deux colons du banc, y sont complets. Seul "seuil" diverge par colon
# (prudent 8.0, peureux 3.0) : ce wrapper SURCHARGE, canal par canal, les
# cles que decl.etats porte (aujourd'hui seulement "peur.seuil") par-dessus
# le canal herite, sans jamais l'ecraser en entier -- contrairement a
# forme/attaches/poids_verbes ci-dessus (BancCommun.fabriquer_colon),
# remplaces integralement par decl car rien n'y est partage entre colons.
static func _fabriquer_colon_charge(nom: String, type: String, decl: Dictionary, catalogue_types: Dictionary) -> Dictionary:
	var colon := BancCommun.fabriquer_colon(nom, type, decl, catalogue_types)
	var surcharge: Dictionary = decl.get("etats", {})
	for nom_etat in surcharge:
		var canal: Dictionary = colon.proprietes["etats"].get(nom_etat, {})
		for cle in surcharge[nom_etat]:
			canal[cle] = surcharge[nom_etat][cle]
		colon.proprietes["etats"][nom_etat] = canal
	return colon

# CINQ COUCHES (comme banc_feu.gd) : perception -> attaches + proximite ->
# JUGEMENT -> dominance -> agir. Difference avec banc_feu.gd : le 3e
# argument passe a Jugement.evaluer n'est PAS "resultats" lui-meme mais
# "source_pression" -- resultats DUPLIQUE puis, SEULEMENT SI le colon
# porte deja declencheur_interne ("effraye"), complete d'une entree
# synthetique portant sa PROPRE reference ({ chose: colon, saillance:
# intensite_interne }). Cette entree alimente la PRESSION de jugement.gd
# (declencheur_interne compte parmi ses cles) sans jamais entrer dans
# "resultats"/"tous" -- jamais un candidat pour Dominance/Agir, jamais un
# risque que le colon tente d'agir sur lui-meme (voir constat en-tete).
# Rend { decision, resultats, perceptions, visibles }, meme forme que
# banc_feu.gd:decider.
static func decider(
	colon: Dictionary,
	monde,
	catalogue_canaux: Dictionary,
	menaces: Dictionary,
	profils_saillance: Dictionary,
	catalogue_deformations: Dictionary,
	jugements: Dictionary,
	catalogue_actions: Dictionary,
	declencheur_interne: String,
	intensite_interne: float,
	catalogue_attaches_par_trait: Dictionary = {},
) -> Dictionary:
	var perceptions := Perception.percevoir(colon, monde, catalogue_canaux)
	var att := Attaches.evaluer(perceptions, colon, menaces, catalogue_deformations)
	var prox := Proximite.evaluer(perceptions, colon, profils_saillance, catalogue_deformations)
	var resultats: Array = att + prox
	var source_pression: Array = resultats.duplicate()
	if colon.proprietes.get(declencheur_interne, false):
		source_pression.append({
			"chose": colon, "type": "colon", "position": colon.position, "saillance": intensite_interne,
		})
	var jug := Jugement.evaluer(perceptions, colon, source_pression, jugements, catalogue_deformations)
	var tous: Array = resultats + jug
	var visibles := Dominance.visibles(tous, colon)
	var decision = Agir.choisir(visibles, colon, catalogue_actions, monde, {}, catalogue_attaches_par_trait)
	return {"decision": decision, "resultats": tous, "perceptions": perceptions, "visibles": visibles}

# Enveloppe decider() + la memorisation pour le tick suivant
# (agir.gd:etat_courant) -- meme role qu'en banc_p1.gd/banc_feu.gd.
static func decider_et_memoriser(
	colon: Dictionary,
	monde,
	catalogue_canaux: Dictionary,
	menaces: Dictionary,
	profils_saillance: Dictionary,
	catalogue_deformations: Dictionary,
	jugements: Dictionary,
	catalogue_actions: Dictionary,
	declencheur_interne: String,
	intensite_interne: float,
	catalogue_attaches_par_trait: Dictionary = {},
) -> Dictionary:
	var r := decider(colon, monde, catalogue_canaux, menaces, profils_saillance, catalogue_deformations, jugements, catalogue_actions, declencheur_interne, intensite_interne, catalogue_attaches_par_trait)
	colon.action_en_cours = Agir.etat_courant(r.decision)
	return r

# GESTE COMPLET decision -> mouvement (meme role qu'en banc_p1.gd/
# banc_feu.gd, chantier "boucle.gd") -- appelle decider_et_memoriser,
# resout la branche fuite/non-fuite, deplace le colon -- MUTE
# colon.position EN PLACE. _faire_agir_colon (impur) l'appelle puis fait
# UNIQUEMENT le rendu ; scripts/boucle.gd:tracer() l'appelle aussi (liee
# par l'appelant), un seul chemin de code.
static func agir_et_deplacer(
	colon: Dictionary,
	monde,
	catalogue_canaux: Dictionary,
	menaces: Dictionary,
	profils_saillance: Dictionary,
	catalogue_deformations: Dictionary,
	jugements: Dictionary,
	catalogue_actions: Dictionary,
	orientations: Dictionary,
	declencheur_interne: String,
	intensite_interne: float,
	delta: float,
	catalogue_attaches_par_trait: Dictionary = {},
) -> Dictionary:
	var r := decider_et_memoriser(colon, monde, catalogue_canaux, menaces, profils_saillance, catalogue_deformations, jugements, catalogue_actions, declencheur_interne, intensite_interne, catalogue_attaches_par_trait)
	var decision = r.decision
	var position_avant: Vector3 = colon.position
	var cible: Vector3 = colon.position
	var chose = null
	var fuite := false
	if decision != null:
		if orientations.get(decision.get("action", ""), "declencheur") == "fuite":
			fuite = true
			var direction := Fuite.direction(
				colon.position, BancCommun.choses_a_fuir(r.visibles, colon, catalogue_actions, orientations, monde, catalogue_attaches_par_trait)
			)
			colon.position = BancCommun.bouger_selon(colon.position, direction, colon.proprietes.vitesse, delta)
		else:
			chose = Ciblage.viser(decision, r.perceptions, menaces, jugements, orientations)
			if chose != null:
				cible = chose.position
			colon.position = BancCommun.bouger_vers(colon.position, cible, colon.proprietes.vitesse, delta)
	return {
		"decision": decision, "resultats": r.resultats, "fuite": fuite,
		"cible": cible, "chose": chose, "position_avant": position_avant,
	}

func _ajouter_chose(id: String, type: String, pos: Array) -> void:
	var position3 := Vector3(pos[0], pos[1], pos[2])
	var objet := Objet.fabriquer(id, type, position3, _catalogue_types)
	_monde.ajouter(objet, type, position3)
	_noeuds[id] = _dessiner_carre(type, pos)

func _dessiner_carre(type: String, pos: Array) -> ColorRect:
	var carre := ColorRect.new()
	carre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	carre.size = Vector2(24.0, 24.0)
	carre.color = _couleur_de(type)
	carre.position = Vector2(pos[0], pos[1]) - carre.size / 2.0
	add_child(carre)
	return carre

func _couleur_de(type: String) -> Color:
	var rgb: Array = _couleurs_types.get(type, [1.0, 1.0, 1.0])
	return Color(rgb[0], rgb[1], rgb[2])

func _charger_json(chemin: String) -> Dictionary:
	var texte := FileAccess.get_file_as_string(chemin)
	return JSON.parse_string(texte)
