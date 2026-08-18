extends Node2D

# Cablage de banc VISUEL, separe de banc_p1 (Scene/banc_feu.tscn, PAS la
# scene principale -- run/main_scene reste banc_p1). Existe pour VOIR la
# BASCULE INDIVIDUELLE : trois colons, memes couches, seuls gain_jugement
# et poids_verbes different -- a mesure que le nombre de feux monte (clic
# = un feu de plus, comme banc_p1), chacun quitte l'extinction pour l'abri
# (jugement.gd) a un seuil de pression qui lui est propre : prudent (gain
# 0.2) reste sur l'extinction dans la plage observable ; peureux (gain 0.8)
# bascule vers s_eloigner des ~3 feux ; mesure (gain 0.24, poids_verbes
# se_proteger 1.0/s_eloigner 0.5) bascule vers se_proteger vers ~5-6 feux,
# seul des trois a rejoindre physiquement l'abri (eau ou pierre) plutot que
# de s'en eloigner. JETABLE PAR DEFINITION : aucune regle de jeu ne doit
# vivre ici, seulement du cablage.
#
# PREMIER cablage reel qui fait entrer jugement.gd dans decider() (banc_p1
# ne le fait pas encore) : perception -> attaches + proximite -> JUGEMENT
# -> dominance -> agir. jugement.gd lit "resultats" (att+prox, AVANT
# jugement) pour la PRESSION, puis son propre resultat rejoint resultats
# avant dominance -- meme ordre que docs/design.md, "Jugement : troisieme
# source de saillance".
#
# Aucun colon ici ne porte d'attache (attaches: [] pour les deux) : la
# CHOSE ciblee (Ciblage.viser) porte donc TOUJOURS "chose" (origine
# proximite OU jugement, jamais attache) -- cible_pour_decision/
# feu_le_plus_proche/_selection_par_menace (banc_p1.gd) sont donc INUTILES
# ici et ne sont PAS dupliquees : chose.position suffit comme cible-
# mouvement. "menaces" reste {} (jamais charge, jamais consulte).
#
# Deux moities, meme decoupage que banc_p1.gd/banc_animal.gd :
# - Node (impur) : _ready charge data/banc_feu.json (types, catalogue de
#   verbes LOCAL -- "abrite" n'existe dans aucun fichier data/ partage,
#   voir plus bas) et data/jugements.json/data/orientations.json
#   (partages, INCHANGES : abrite->brule et se_proteger->jugee/
#   s_eloigner->fuite y sont deja). _unhandled_input allume un feu au
#   clic (identique a banc_p1.gd). _process fait avancer Extinction.avancer
#   (PAS Propagation.avancer : rien d'inflammable ici en dehors du feu
#   lui-meme, aucun voisin a contaminer) + chaque colon.
# - Fonctions statiques PROPRES a ce banc (pures, testables headless, voir
#   test_banc_feu.gd) :
#   decider(colon, monde, catalogue_canaux, menaces, profils_saillance,
#     catalogue_deformations, jugements, catalogue_actions) -- le pipeline
#     complet CINQ COUCHES decrit plus haut. Rend { decision, resultats,
#     perceptions, visibles }. profils_saillance (data/profils_saillance.json)
#     resout la reference "profil_saillance" que porte une chose saillante --
#     voir scripts/proximite.gd, dont la saillance est ponderee par
#     l'avancement du chantier (travail_restant/travail_initial) quand la
#     chose en porte un -- proprietes de la chose, rien a transmettre
#     depuis ce banc. PHASE 4 piece 3 (chantier "L'entite comme agent
#     complet") : catalogue_deformations (data/deformations.json) est
#     transmis tel quel a Proximite.evaluer, qui module la saillance nue
#     par la deformation du COLON lui-meme.
#   agir_et_deplacer(colon, monde, catalogue_canaux, menaces, profils_saillance,
#     catalogue_deformations, jugements, catalogue_actions, orientations,
#     delta) -- LE GESTE COMPLET decision -> mouvement
#     (chantier "boucle.gd", CARTE.md §6) : decider_et_memoriser + branche
#     fuite/non-fuite (via BancCommun.choses_a_fuir) + deplacement, mute
#     colon.position EN PLACE. _faire_agir_colon l'appelle puis fait
#     UNIQUEMENT le rendu (print, noeud) ; scripts/boucle.gd:tracer()
#     l'appelle aussi (liee par l'appelant), jamais une reimplementation.
# - Outils PARTAGES avec les autres bancs (scripts/banc_commun.gd, precharge
#   ci-dessous sous BancCommun -- voir sa boite a outils, CARTE.md §6,
#   "Dette extinction/cendre") : objets_de, resoudre_chantier,
#   agents_rythme, marquer_eteints, fabriquer_colon, bouger_vers,
#   bouger_selon, choses_a_fuir, verbe_action. Ne vivent plus dans ce
#   fichier -- leur rationale complete vit desormais dans banc_commun.gd,
#   pas ici. _ajouter_colon (impur) appelle BancCommun.fabriquer_colon
#   ("colon", ...) puis fait l'enregistrement, inchange.
#
# LA PROPRIETE "abrite" ET SA TABLE DE VERBES SONT PROPRES A CE BANC :
# data/banc_feu.json porte "types" (eau/pierre/feu/colon, un catalogue de
# FABRICATION local -- ce banc ne touche PAS data/types.json) et
# "catalogue_local" ({ "abrite": { "verbes": [...] } }), fusionne dans
# _catalogue_actions par-dessus data/types_choses.json (partage, donne
# "brule" -> approcher, inchange). Aucun nom de propriete n'est ecrit en
# dur dans ce fichier : "abrite"/"brule"/"approcher"/"se_proteger"/
# "s_eloigner" ne vivent que dans data/banc_feu.json et les tables deja
# partagees (jugements.json, orientations.json) -- voir CLAUDE.md, "Ne
# code pas ce que tu n'as pas compris" et le test hors domaine de
# test_banc_feu.gd, qui verrouille cette absence.
#
# MARQUEUR VISUEL "abrite" (_dessiner_marqueur_abri) : toute chose ajoutee
# par _ajouter_chose qui porte "abrite" (eau ET pierre aujourd'hui, sans
# qu'aucun des deux ne soit nomme ici) affiche un Label "abrite: <id>"
# au-dessus de son carre -- lecture de PROPRIETE, jamais un nom de type en
# dur, pour montrer a l'oeil que ce sont deux instances independantes de la
# meme propriete plutot qu'une seule chose. Jamais lu par le coeur.
#
# POURQUOI L'ESCALADE NE VIENT JAMAIS D'UN SECOND VERBE SUR "brule" :
# poids_verbes est un choix STATIQUE par colon, indifferent a l'intensite
# de la scene -- un colon qui prefererait s_eloigner a approcher fuirait
# le tout premier feu, jamais seulement "au bout d'un moment". La bascule
# vient exclusivement du basculement de LA SAILLANCE DOMINANTE entre
# "brule" (proximite, bornee ~3.0 par feu) et "abrite" (jugement, pression
# * gain_jugement, croit avec le nombre de feux) : "abrite" ne propose
# QUE des verbes de raction a la peur (se_proteger, s_eloigner), jamais
# approcher -- une fois qu'elle domine, l'extinction s'arrete d'elle-meme.
#
# PROFIL_SAILLANCE RETIRE LOCALEMENT SUR LE COLON (audit 2026-08-06, defaut
# "les colons s'empilent au repos") : data/types.json:colon porte
# profil_saillance: "colon" depuis le chantier "colon saillant" -- herite
# ici via la fusion du catalogue PARTAGE (_ready, plus haut), comme
# banc_p1.gd/banc_charge.gd. CHOIX (different de banc_p1.gd) : ce banc
# retire la reference EN LOCAL sur son colon (_ajouter_colon), meme patron
# que banc_lien_personnel.gd -- pas le patron DISTANCE_ARRET_COLON de
# banc_p1.gd. RAISON : le sujet de CE banc est la bascule INDIVIDUELLE de
# trois colons (prudent/peureux/mesure) sous la MEME exposition (nombre de
# feux identique pour les trois) -- une convergence colon-vers-colon
# introduirait une saillance et une distance qui n'ont rien a voir avec ce
# qui est mesure, et pourrait faire router un colon vers un AUTRE colon au
# lieu du feu/de l'abri. banc_p1.gd, lui, DEMONTRE la convergence
# elle-meme (voir prototypes.md) -- ce n'est pas le sujet ici, donc rien a
# demontrer en la gardant. proximite.gd traite une cle "profil_saillance"
# absente comme une chose non saillante, point neutre deja legitime
# (ref == "" -> continue) : aucune alarme, aucun effet sur "brule"/"abrite"
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
const Objet = preload("res://scripts/objet.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")

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
var _compteur_feu := 0

var _colons: Array = []
var _temps_ecoule := 0.0

func _ready() -> void:
	var donnees := _charger_json("res://data/banc_feu.json")
	_couleurs_types = donnees.get("couleurs_types", {})
	_catalogue_types = donnees.get("types", {})
	# objet_physique/dynamique/percevant/agent (et "colon") viennent
	# desormais du catalogue PARTAGE (data/types.json), meme geste que
	# banc_charge.gd:_ready (PHASE 3 piece 2) -- necessaire depuis PHASE 5
	# etape 4 piece 2 : AttacheParTrait.avancer (agir.gd) traite
	# liens_personnels comme STRUCTURELLE, et seul dynamique le porte
	# (refonte "eclatement du corps interne" -- auparavant seul "entite" le
	# portait). Colon local restait numeriquement identique (rythme 1.5,
	# vitesse 150.0, vue.portee 1600.0/angle 180.0) -- la fusion n'ajoute
	# que ce qui manquait (liens_personnels/attaches/reserves/engagement/
	# deformation/orientation), tout inerte ici (aucun mecanisme de ce banc
	# ne les lit hors deformation, deja cablee). objet_physique AJOUTE
	# (correction, session ulterieure) : data/types.json:colon.herite le
	# liste (masse/volume/densite/temperature, dormant, voir design.md
	# "objet_physique comme paquet fondateur"), mais ce banc l'oubliait --
	# objet.gd:fabriquer alarmait donc (push_error) a CHAQUE fabrication de
	# colon, sans consequence observable (paquet dormant, aucun mecanisme de
	# ce banc ne le lit) mais bruyant en console. banc_charge.gd le
	# fusionnait deja correctement, seul ce fichier avait la dette.
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

	var i := 0
	for instance in donnees.get("instances", []):
		var id := "%s_%d" % [instance["type"], i]
		i += 1
		_ajouter_chose(id, instance["type"], instance["position"])

	var declarations: Dictionary = donnees.get("colons", {})
	for nom in declarations:
		_ajouter_colon(nom, declarations[nom])

func _ajouter_colon(nom: String, decl: Dictionary) -> void:
	var colon := BancCommun.fabriquer_colon(nom, "colon", decl, _catalogue_types)
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
		# _monde.par_id(id) est structurellement sur cet id : _ajouter_chose,
		# juste au-dessus, vient de l'enregistrer dans _monde (compteur_feu
		# monotone, jamais de collision) -- si cette garantie tombait un
		# jour, par_id alarme deja lui-meme (push_error) avant de rendre
		# null, jamais un defaut silencieux.
		BancCommun.resoudre_chantier(_monde.par_id(id).chose.proprietes, _patron)

func _process(delta: float) -> void:
	_temps_ecoule += delta
	var objets := BancCommun.objets_de(_monde)
	var agents := BancCommun.agents_rythme(objets)
	var eteints := Extinction.avancer(objets, agents, delta, _transformations)
	BancCommun.marquer_eteints(eteints, _noeuds, _monde, _couleur_de("cendre"), _temps_ecoule)
	for colon in _colons:
		_faire_agir_colon(colon, delta)

func _faire_agir_colon(colon: Dictionary, delta: float) -> void:
	var g := agir_et_deplacer(colon, _monde, _catalogue_canaux, _menaces, _profils_saillance, _catalogue_deformations, _jugements, _catalogue_actions, _orientations, delta, _catalogue_attaches_par_trait)
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

# CINQ COUCHES (premier cablage reel a inclure jugement.gd) : perception ->
# attaches + proximite -> JUGEMENT -> dominance -> agir. jugement.gd lit
# "resultats" (att+prox, AVANT jugement -- sa PRESSION ne doit jamais lire
# sa propre sortie) ; son resultat rejoint resultats ENSUITE, avant
# dominance -- att + prox + jugement, dominance ne sait pas d'ou vient un
# nombre (voir docs/design.md, "Jugement : troisieme source de
# saillance"). Rend { decision, resultats, perceptions, visibles }.
static func decider(
	colon: Dictionary,
	monde,
	catalogue_canaux: Dictionary,
	menaces: Dictionary,
	profils_saillance: Dictionary,
	catalogue_deformations: Dictionary,
	jugements: Dictionary,
	catalogue_actions: Dictionary,
	catalogue_attaches_par_trait: Dictionary = {},
) -> Dictionary:
	var perceptions := Perception.percevoir(colon, monde, catalogue_canaux)
	var att := Attaches.evaluer(perceptions, colon, menaces, catalogue_deformations)
	var prox := Proximite.evaluer(perceptions, colon, profils_saillance, catalogue_deformations)
	var resultats: Array = att + prox
	var jug := Jugement.evaluer(perceptions, colon, resultats, jugements, catalogue_deformations)
	var tous: Array = resultats + jug
	var visibles := Dominance.visibles(tous, colon)
	var decision = Agir.choisir(visibles, colon, catalogue_actions, monde, {}, catalogue_attaches_par_trait)
	return {"decision": decision, "resultats": tous, "perceptions": perceptions, "visibles": visibles}

# Enveloppe decider() + la memorisation pour le tick suivant
# (agir.gd:etat_courant) -- c'est le fil complet que _faire_agir_colon doit
# executer, extrait en statique pour etre teste sur deux ticks sans
# instancier le Node (voir test_banc_feu.gd). _faire_agir_colon appelle
# CETTE fonction, jamais decider() seule suivie d'une ecriture a cote --
# sinon rien ne verrouille que le cablage reel memorise vraiment.
static func decider_et_memoriser(
	colon: Dictionary,
	monde,
	catalogue_canaux: Dictionary,
	menaces: Dictionary,
	profils_saillance: Dictionary,
	catalogue_deformations: Dictionary,
	jugements: Dictionary,
	catalogue_actions: Dictionary,
	catalogue_attaches_par_trait: Dictionary = {},
) -> Dictionary:
	var r := decider(colon, monde, catalogue_canaux, menaces, profils_saillance, catalogue_deformations, jugements, catalogue_actions, catalogue_attaches_par_trait)
	colon.action_en_cours = Agir.etat_courant(r.decision)
	return r

# GESTE COMPLET decision -> mouvement (chantier "boucle.gd", voir
# scripts/boucle.gd et CARTE.md §6) -- meme role qu'en banc_p1.gd, adapte a
# la signature CINQ COUCHES de ce banc (jugements) et a l'absence de
# cible_pour_decision ici (aucun colon du banc ne porte d'attache, voir
# l'en-tete de ce fichier -- chose.position suffit toujours comme cible).
# Appelle decider_et_memoriser, resout la branche fuite/non-fuite, deplace
# le colon -- MUTE colon.position EN PLACE. _faire_agir_colon (impur)
# l'appelle puis fait UNIQUEMENT le rendu ; boucle.gd:tracer() l'appelle
# aussi (liee par l'appelant), plus de 3e copie de cet agencement.
#
# Rend, pour le RENDU (jamais ecrit ici) : "decision"/"resultats" (sortie
# de decider_et_memoriser) ; "fuite" (bool) ; "cible"/"chose" (position/
# chose visee) ; "position_avant" (colon.position AVANT ce tick, pour que
# _faire_agir_colon calcule la meme distance/le meme "eteint" vs "va vers"
# qu'avant ce chantier -- colon.position a deja bouge quand cette fonction
# rend la main).
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
	delta: float,
	catalogue_attaches_par_trait: Dictionary = {},
) -> Dictionary:
	var r := decider_et_memoriser(colon, monde, catalogue_canaux, menaces, profils_saillance, catalogue_deformations, jugements, catalogue_actions, catalogue_attaches_par_trait)
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
	if objet.proprietes.get("abrite", false):
		_dessiner_marqueur_abri(id, pos)

# Marqueur textuel jetable (lecture de propriete, jamais un nom de type en
# dur) : toute chose qui porte "abrite" -- eau ET pierre aujourd'hui, sans
# que ce fichier ne les nomme -- affiche son id au-dessus de son carre,
# pour montrer a l'oeil que ce sont deux instances INDEPENDANTES de la
# meme propriete (memes verbes proposes par catalogue_local, memes
# couleurs propres) plutot qu'une seule chose dupliquee. Jamais lu par le
# coeur -- meme statut que les barres de reserve de banc_p1.gd.
func _dessiner_marqueur_abri(id: String, pos: Array) -> void:
	var label := Label.new()
	label.text = "abrite: %s" % id
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.position = Vector2(pos[0], pos[1]) - Vector2(30.0, 40.0)
	add_child(label)

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
