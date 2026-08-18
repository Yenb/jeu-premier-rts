extends Node2D

# Cablage de banc, scene principale du projet (Scene/banc_p1.tscn). Traduit
# une decision de colon en mouvement et en carres colores. JETABLE PAR
# DEFINITION : aucune regle de jeu ne doit vivre ici, seulement du cablage.
# Detail complet et raison d'etre : CARTE.md §3, docs/prototypes.md.
#
# Deux moities :
# - Node (impur) : _ready charge les donnees (data/banc_p1.json et les
#   catalogues) et fabrique CHAQUE colon via Objet.fabriquer (comme les
#   choses du monde) -- un colon est un objet { id, position, proprietes },
#   enregistre dans _monde (perceptible, structurellement, par les autres
#   colons et par lui-meme -- voir docs/design.md, "Tout est objet").
#   _monde est une instance de Monde, choses indexees PAR ID (voir
#   scripts/monde.gd) -- decider() percoit directement _monde, et
#   _monde.par_id(id) retrouve une chose enregistree sans index a cote.
#   propagation.gd/extinction.gd/BancCommun.agents_rythme attendent un
#   Array nu : BancCommun.objets_de(_monde) l'extrait.
#   _unhandled_input allume un feu au clic, _process fait
#   avancer propagation.avancer + extinction.avancer (agents derives du
#   monde via BancCommun.agents_rythme, plus de canal _colons tenu a la
#   main pour ca ; _transformations, charge depuis
#   data/transformations.json, resout la reference "transformation" que
#   porte une chose en chantier -- voir scripts/extinction.gd) puis
#   geler_combustible_apres_sauvetage + depense.avancer (_seuils_combustible,
#   charge depuis data/seuils_combustible.json -- voir "Chantier fin de
#   chantier differenciee" plus bas) + chaque
#   colon (_colons reste necessaire pour la decision et le mouvement),
#   gere le rendu (ColorRect) et les print() de console.
# - Fonctions statiques PROPRES a ce banc (pures, testables headless, voir
#   test_banc_p1.gd/test_fin_chantier.gd) :
#   geler_combustible_apres_sauvetage(objets, patron) -- fin de chantier
#     differenciee entre extinction.gd (agents, travail_restant) et
#     depense.gd (combustible interne, sans portee) : premier arrive a
#     zero gagne. Si l'agent gagne (chose sauvee, "brule" retire), gele le
#     canal reserves.combustible (cout_base -> 0.0) pour que le combustible
#     ne continue pas de s'epuiser en arriere-plan et ne finisse pas par
#     retirer "inflammable" plus tard, sans lien avec un nouvel incendie --
#     reserve restante conservee telle quelle, jamais remise a son plein ;
#     restaure cout_base (depuis patron) des que "brule" revient, une
#     reprise repart d'ou elle s'est arretee.
#   decider(colon, monde, catalogue_canaux, menaces, profils_saillance,
#     catalogue_deformations, catalogue_actions,
#     catalogue_attaches_par_trait = {}) -- pipeline complet
#     Perception -> Attaches+Proximite -> Dominance -> Agir. Rend
#     { decision, resultats, perceptions }. profils_saillance
#     (data/profils_saillance.json) resout la reference "profil_saillance"
#     que porte une chose saillante -- voir scripts/proximite.gd, dont la
#     saillance est ponderee par l'avancement du chantier
#     (travail_restant/travail_initial, data/transformations.json) quand la
#     chose en porte un -- rien a transmettre depuis ce banc, ce sont des
#     proprietes de la chose, pas des parametres de decider(). PHASE 4
#     piece 3 (chantier "L'entite comme agent complet", voir
#     docs/cadrage_phase4_deformation.md) : catalogue_deformations
#     (data/deformations.json) est transmis tel quel a Proximite.evaluer,
#     qui module la saillance nue par la deformation du COLON lui-meme.
#     PHASE 5 etape 4 piece 2 : catalogue_attaches_par_trait
#     (data/attaches_par_trait.json, defaut {}) transite jusqu'a
#     Agir.choisir -- INERTE ici (aucun colon de data/banc_p1.json ne
#     construit de liens_personnels distincts sur plusieurs choses
#     notre_ouvrage), propage pour rester au meme niveau que les autres
#     bancs reels, voir agir.gd "ATTACHE PAR TRAIT".
#   cible_pour_decision(...) / feu_le_plus_proche(...) -- retrouvent OU
#     aller, puisque attaches.gd ne rend qu'un nombre, jamais une position.
#   La CHOSE ciblee (Dictionary, necessaire pour lire proprietes.
#     transformation de la chose visee) ne se calcule plus ici : chantier
#     "cible generale" (voir CARTE.md), scripts/ciblage.gd (cœur) rend
#     Ciblage.viser(decision, perceptions, menaces, jugements,
#     orientations) -- decide PAR VERBE (data/orientations.json) si la
#     chose visee est le declencheur-menace ou la chose jugee (voir
#     scripts/jugement.gd), jamais par un nom en dur. cible_pour_decision/
#     feu_le_plus_proche restent inchangees (rendent une position, pas une
#     chose -- hors perimetre de ce chantier).
#   agir_et_deplacer(colon, monde, catalogue_canaux, menaces, profils_saillance,
#     catalogue_deformations, catalogue_actions, jugements, orientations,
#     transformations, engagements, delta) -- LE GESTE COMPLET decision -> mouvement
#     (chantier "boucle.gd", CARTE.md §6) : decider_et_memoriser + branche
#     fuite/non-fuite (via BancCommun.choses_a_fuir) + deplacement, mute
#     colon.position EN PLACE. _faire_agir_colon l'appelle puis fait
#     UNIQUEMENT le rendu (print, noeud) ; scripts/boucle.gd:tracer()
#     l'appelle aussi (liee par l'appelant), jamais une reimplementation --
#     un seul chemin de code pour le jeu reel et pour un test dynamique.
#     PHASE 1 (scripts/couplage.gd) : fait aussi avancer/poser/retirer
#     l'engagement du colon sur son chantier -- voir _avancer_engagement_colon/
#     _mettre_a_jour_engagement_colon, en-tete complet sur agir_et_deplacer
#     lui-meme.
# - Outils PARTAGES avec les autres bancs (scripts/banc_commun.gd, precharge
#   ci-dessous sous BancCommun -- voir sa boite a outils, CARTE.md §6,
#   "Dette extinction/cendre") : objets_de, resoudre_chantier,
#   agents_rythme, marquer_eteints, fabriquer_colon, bouger_vers,
#   bouger_selon, choses_a_fuir, verbe_action. Ne vivent plus dans ce
#   fichier -- leur rationale complete vit desormais dans banc_commun.gd,
#   pas ici. _ajouter_colon (impur) appelle BancCommun.fabriquer_colon
#   ("colon", ...) puis fait l'enregistrement, inchange.
#
# Frontiere : ne calcule AUCUNE decision -- delegue entierement aux quatre
# couches et aux transformations. DEUX INDEX, jamais trois : _monde
# (Dictionary indexe par id) retrouve une chose par son id
# (_monde.par_id(id)), et _noeuds ne porte que du rendu (ColorRect), jamais
# lu par le cœur.
#
# PHASE 2, piece 2 (chantier "L'entite comme agent complet", corps
# physiologique -- voir docs/cadrage_phase2_reserves.md) : les colons
# portent desormais proprietes.reserves (5 canaux herites de "entite" via
# la fusion conditionnelle, PHASE 2 piece 1). AUCUN nouvel appel a
# Depense.avancer n'etait necessaire -- _process appelait deja
# Depense.avancer(objets, ...) sur BancCommun.objets_de(_monde), qui
# aplatit TOUT _monde, colons compris (enregistres au meme titre que les
# choses). Tant que les colons ne portaient aucune reserve, cet appel les
# traversait sans effet ; ils sont desormais ponctionnes par le meme
# mecanisme generique, sans ligne de code ajoutee a _process. Seul ajout
# reel : les BARRES au-dessus de chaque colon (_barres_reserves,
# _dessiner_barres_reserves/_redessiner_barres_reserves), meme convention
# d'affichage que banc_animal.gd (largeur = grandeur visuelle, AUCUN
# nombre affiche, couleurs/max lus depuis data/banc_p1.json, jamais par le
# coeur). Aucune source de recharge en piece 2 (voulu) : les reserves
# descendent, jamais retenues -- geler_combustible_apres_sauvetage ne les
# concerne pas (il ne lit que reserves.combustible, propre au feu).

const Perception = preload("res://scripts/perception.gd")
const Attaches = preload("res://scripts/attaches.gd")
const Proximite = preload("res://scripts/proximite.gd")
const Dominance = preload("res://scripts/dominance.gd")
const Agir = preload("res://scripts/agir.gd")
const Ciblage = preload("res://scripts/ciblage.gd")
const Fuite = preload("res://scripts/fuite.gd")
const Monde = preload("res://scripts/monde.gd")
const Propagation = preload("res://scripts/propagation.gd")
const Extinction = preload("res://scripts/extinction.gd")
const Depense = preload("res://scripts/depense.gd")
const Objet = preload("res://scripts/objet.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")
const Couplage = preload("res://scripts/couplage.gd")

var _couleurs_types: Dictionary = {}
var _catalogue_attaches: Dictionary = {}
var _catalogue_actions: Dictionary = {}
var _catalogue_types: Dictionary = {}
var _catalogue_materiaux: Dictionary = {}
var _menaces: Dictionary = {}
var _profils_saillance: Dictionary = {}
var _catalogue_deformations: Dictionary = {}
var _catalogue_canaux: Dictionary = {}
var _jugements: Dictionary = {}
var _orientations: Dictionary = {}
var _catalogue_attaches_par_trait: Dictionary = {}
var _monde := Monde.new()
var _noeuds: Dictionary = {}
var _couleurs_reserves: Dictionary = {}
var _reserves_max: Dictionary = {}
var _barres_reserves: Dictionary = {}
var _exposition: Dictionary = {}
var _patron: Dictionary = {}
var _patron_bloc: Dictionary = {}
var _transformations: Dictionary = {}
var _seuils_combustible: Dictionary = {}
var _engagements: Dictionary = {}
var _compteur_feu := 0
var _compteur_menace := 0
var _compteur_bloc := 0
var _mode := "feu"

var _colons: Array = []
var _temps_ecoule := 0.0

const LARGEUR_BARRE_RESERVE := 24.0
const HAUTEUR_BARRE_RESERVE := 3.0

# RUSTINE -- evite l'empilement visuel des colons idle depuis le chantier
# auto-perception (colon saillant pour un autre colon, voir perception.gd/
# data/types.json:colon). Carre de rendu 24x24 (voir _dessiner_carre) :
# bouger_vers (banc_commun.gd, generique, INCHANGE) s'arrete sous 1.0
# unite de sa cible, assez pour un feu/une batisse (chantier ponctuel,
# deja separe par portee_travail) mais pas pour deux carres qui finiraient
# visuellement confondus l'un sur l'autre. Le vrai traitement (collision
# physique, espacement en simulation, ou mecanisme de repulsion courte
# dans le cœur) est un chantier separe, a ouvrir plus tard -- CARTE.md §6.
const DISTANCE_ARRET_COLON := 30.0

func _ready() -> void:
	var placement := _charger_json("res://data/banc_p1.json")
	_couleurs_types = placement.get("couleurs_types", {})
	_couleurs_reserves = placement.get("couleurs_reserves", {})
	_reserves_max = placement.get("reserves_max", {})
	var catalogue_choses := _charger_json("res://data/types_choses.json")
	_catalogue_attaches = _charger_json("res://data/types_attaches.json")
	_catalogue_types = _charger_json("res://data/types.json")
	_catalogue_materiaux = _charger_json("res://data/materiaux.json")
	_menaces = _charger_json("res://data/menaces.json")
	_profils_saillance = _charger_json("res://data/profils_saillance.json")
	_catalogue_deformations = _charger_json("res://data/deformations.json")
	_catalogue_canaux = _charger_json("res://data/canaux.json")
	_jugements = _charger_json("res://data/jugements.json")
	_orientations = _charger_json("res://data/orientations.json")
	_catalogue_attaches_par_trait = _charger_json("res://data/attaches_par_trait.json")
	var donnees_transformations := _charger_json("res://data/transformations.json")
	_patron = donnees_transformations.get("patron", {})
	_patron_bloc = donnees_transformations.get("patron_bloc", {})
	_transformations = donnees_transformations.get("transformations", {})
	_seuils_combustible = _charger_json("res://data/seuils_combustible.json")
	_engagements = _charger_json("res://data/engagements.json")
	for cle in _catalogue_attaches:
		_catalogue_actions[cle] = _catalogue_attaches[cle]
	for cle in catalogue_choses:
		_catalogue_actions[cle] = catalogue_choses[cle]

	var i := 0
	for instance in placement.get("instances", []):
		var id := "%s_%d" % [instance["type"], i]
		i += 1
		_ajouter_chose(id, instance["type"], instance["position"])

	var declarations: Dictionary = placement.get("colons", {})
	for nom in declarations:
		_ajouter_colon(nom, declarations[nom])

func _ajouter_colon(nom: String, decl: Dictionary) -> void:
	var colon := BancCommun.fabriquer_colon(nom, "colon", decl, _catalogue_types)
	var pos: Array = decl.get("position", [0.0, 0.0, 0.0])
	# Enregistre le colon dans _monde, meme chemin que _ajouter_chose : sans
	# ca, perception.gd (couche 1) ne peut voir ni les autres colons ni les
	# choses ne le voir en retour. _noeuds range desormais le ColorRect du
	# colon comme celui de toute chose (meme convention que _ajouter_chose,
	# plus d'asymetrie).
	_monde.ajouter(colon, "colon", colon.position)
	_colons.append(colon)
	_noeuds[colon.id] = _dessiner_carre(nom, pos)
	_barres_reserves[colon.id] = _dessiner_barres_reserves(colon.proprietes.get("reserves", {}))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var pos := get_global_mouse_position()
		if _mode == "feu":
			_compteur_feu += 1
			var id := "feu_%d" % _compteur_feu
			_ajouter_chose(id, "feu", [pos.x, pos.y, 0.0])
			# _monde.par_id(id) est structurellement sur cet id : _ajouter_chose,
			# juste au-dessus, vient de l'enregistrer dans _monde (compteur_feu
			# monotone, jamais de collision) -- si cette garantie tombait un
			# jour, par_id alarme deja lui-meme (push_error) avant de rendre
			# null, jamais un defaut silencieux.
			BancCommun.resoudre_chantier(_monde.par_id(id).chose.proprietes, _patron)
		elif _mode == "bloc":
			_compteur_bloc += 1
			var id := "bloc_%d" % _compteur_bloc
			_ajouter_chose(id, "bloc", [pos.x, pos.y, 0.0])
			# Meme garantie qu'en mode feu : _ajouter_chose vient d'enregistrer
			# cet id (compteur monotone), par_id ne peut pas alarmer ici.
			BancCommun.resoudre_chantier(_monde.par_id(id).chose.proprietes, _patron_bloc)
		else:
			# _mode porte directement la reference profil_saillance
			# ("menace_1"/"menace_2"/"menace_3") -- la fabrication pose deja
			# la reference par defaut ("menace_1", voir data/types.json), on
			# l'ecrase ici si le mode selectionne un autre niveau. Chaque
			# clic pose une menace NEUVE (compteur monotone, comme le feu) --
			# plusieurs menaces coexistent, aucune n'est deplacee.
			_compteur_menace += 1
			var id := "menace_%d" % _compteur_menace
			_ajouter_chose(id, "menace", [pos.x, pos.y, 0.0])
			_monde.par_id(id).chose.proprietes.profil_saillance = _mode
			# Assombrissement selon le niveau : convention d'affichage propre
			# a ce banc jetable (comme _couleur_de), jamais lue par le coeur.
			var niveau: int = _mode.split("_")[1].to_int()
			var base := _couleur_de("menace")
			var facteur := 1.0 - float(niveau - 1) * 0.25
			_noeuds[id].color = Color(base.r * facteur, base.g * facteur, base.b * facteur)
	elif event is InputEventKey and event.pressed:
		# Selectionne le MODE du prochain clic gauche -- ne pose ni ne
		# modifie rien tant qu'aucun clic ne suit.
		var nouveau_mode := ""
		if event.keycode == KEY_0:
			nouveau_mode = "feu"
		elif event.keycode == KEY_1:
			nouveau_mode = "menace_1"
		elif event.keycode == KEY_2:
			nouveau_mode = "menace_2"
		elif event.keycode == KEY_3:
			nouveau_mode = "menace_3"
		elif event.keycode == KEY_M:
			nouveau_mode = "bloc"
		if nouveau_mode != "" and nouveau_mode != _mode:
			_mode = nouveau_mode
			print("mode -> %s" % _mode)

func _process(delta: float) -> void:
	_temps_ecoule += delta
	var objets := BancCommun.objets_de(_monde)
	var enflammees := Propagation.avancer(objets, _menaces, _exposition, delta, _patron)
	for id in enflammees:
		_noeuds[id].color = _couleur_de("feu")
	var agents := BancCommun.agents_rythme(objets)
	var eteints := Extinction.avancer(objets, agents, delta, _transformations)
	BancCommun.marquer_eteints(eteints, _noeuds, _monde, _couleur_de("cendre"), _temps_ecoule)
	geler_combustible_apres_sauvetage(objets, _patron)
	var consumes := Depense.avancer(objets, delta, _seuils_combustible)
	for id in consumes:
		_noeuds[id].color = _couleur_de("cendre_consumee")
		print("t=%.1f %s consume (plus de combustible)" % [_temps_ecoule, id])
	for colon in _colons:
		_faire_agir_colon(colon, delta)
	mettre_a_jour_occupation(_monde, agents, _transformations)

func _faire_agir_colon(colon: Dictionary, delta: float) -> void:
	var g := agir_et_deplacer(colon, _monde, _catalogue_canaux, _menaces, _profils_saillance, _catalogue_deformations, _catalogue_actions, _jugements, _orientations, _transformations, _engagements, delta, _catalogue_attaches_par_trait)
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
			var raison := ("aucun feu" if not _un_feu_existe() else "aucun feu a portee")
			print("t=%.1f %s : 0 saillance -> RIEN (%s)" % [_temps_ecoule, colon.id, raison])
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
	_redessiner_barres_reserves(colon)

func _etiquette_decision(decision: Dictionary) -> String:
	var chose = decision.get("chose", null)
	if chose is Dictionary:
		return String(chose.get("id", decision.type))
	if chose != null:
		return String(chose)
	return String(decision.type)

func _un_feu_existe() -> bool:
	for chose in BancCommun.objets_de(_monde):
		for vuln in _menaces:
			if chose.proprietes.get(_menaces[vuln], false):
				return true
	return false

# Chantier "fin de chantier differenciee" : deux issues pour un meme feu,
# course entre extinction.gd (agents a portee, travail_restant) et
# depense.gd (combustible interne, reserves.combustible, sans portee).
# Premier arrive a zero gagne. Si l'agent gagne (extinction retire "brule"
# avant que le combustible ne s'epuise), la chose est SAUVEE -- mais son
# canal combustible, lui, continue de decroitre en arriere-plan tant que
# rien ne l'arrete (depense.gd ne regarde jamais "brule", il ne connait
# que des nombres). Sans ce gel, une chose sauvee finirait par perdre
# "inflammable" plus tard quand meme, sans lien avec un nouvel incendie --
# decision de Yael (voir conversation) : geler la decroissance des que la
# chose n'est plus "brule" (cout_base -> 0.0 sur le canal combustible), en
# GARDANT la reserve restante telle quelle (jamais remise a son plein) --
# une reprise ulterieure (la chose reprend "brule", voir propagation.gd)
# repart d'ou le combustible s'est arrete, jamais d'un compte neuf : des
# que "brule" revient, cout_base est restaure a sa valeur active (celle du
# patron), jamais laisse a zero pour toujours.
# Nomme "combustible"/"brule" en dur : cablage de banc, exception "banc
# jetable peut nommer une categorie" de CLAUDE.md -- depense.gd lui-meme ne
# lit toujours aucun de ces deux noms.
static func geler_combustible_apres_sauvetage(objets: Array, patron: Dictionary) -> void:
	var cout_actif: float = patron.get("reserves", {}).get("combustible", {}).get("cout_base", 0.0)
	for chose in objets:
		var reserves: Dictionary = chose.proprietes.get("reserves", {})
		if not reserves.has("combustible"):
			continue
		reserves.combustible["cout_base"] = cout_actif if chose.proprietes.has("brule") else 0.0

# Chantier "occupation" : une chose en chantier avec au moins un AGENT
# PHYSIQUEMENT a portee_travail (meme detection que extinction.gd/
# BancCommun.verbe_action, reutilisee plutot que recodee) pose "occupe" ET
# devient NON SAILLANTE (gele "profil_saillance" sous "profil_saillance_gele",
# jamais perdu) -- proximite.gd ignore deja une chose sans profil_saillance
# (ref == "" -> non saillante), donc plus aucun colon ne la voit comme
# candidate : les autres vont ailleurs sans qu'aucune ligne du coeur ne le
# sache. Decision documentee en conversation avec Yael : poser seulement
# "occupe" sans toucher au catalogue d'actions ne suffit pas (agir.gd
# resout le verbe par SCAN des cles du catalogue contre les proprietes de
# la chose -- "cassable" reste vrai et gagnerait le scan quel que soit
# "occupe" ; de toute facon dominance.gd/agir.gd ne choisissent QUE par
# saillance, jamais par verbe resolu -- un verbe vide n'aurait empeche
# personne de viser la chose).
#
# DETECTION PAR POSITION, JAMAIS PAR action_en_cours -- essaye puis
# corrige (voir conversation) : detecter via action_en_cours.id du colon
# creait une boucle qui s'auto-detruit. Une chose gelee n'est plus
# saillante pour PERSONNE, l'occupant compris -- sa propre decision devient
# null, donc son action_en_cours se vide au tick suivant (Agir.etat_courant
# reecrit action_en_cours a chaque tick depuis la decision FRAICHE, jamais
# une memoire). Detecter par action_en_cours faisait donc "liberer" la
# chose des que l'occupant ne pouvait plus la voir comme salante -- qui la
# rendait salante -- qui la faisait regeler -- CLIGNOTEMENT a chaque tick
# (verifie empiriquement, script jetable, jamais commite). En detectant par
# POSITION (comme extinction.gd, agents deja calcules pour lui, memes
# donnees, aucun calcul duplique), le gel devient stable : un colon sans
# decision ne bouge pas (agir_et_deplacer ne deplace que sur decision non
# nulle), sa position reste a portee, l'occupation se maintient d'elle-meme
# sans jamais relire ce que le colon a decide.
#
# Une chose qui n'a plus AUCUN agent a portee_travail redevient attractive :
# "occupe" retire, "profil_saillance" restaure -- SAUF si le chantier
# s'est termine entre-temps ("travail_restant" absent, deja retire par
# a_zero) : la chose reste inerte pour de bon, comme une cendre, on ne
# ressuscite jamais une saillance qu'une transformation a intentionnellement
# effacee.
#
# agents : meme Array que recoit deja Extinction.avancer (BancCommun.
# agents_rythme -- { position, rythme facultatif }), transmis tel quel par
# _process, aucun calcul en double.
static func mettre_a_jour_occupation(monde, agents: Array, transformations: Dictionary) -> void:
	for chose in BancCommun.objets_de(monde):
		var proprietes: Dictionary = chose.proprietes
		var occupee_maintenant := false
		if proprietes.has("travail_restant"):
			for agent in agents:
				if BancCommun.verbe_action({"position": agent.position}, chose.position, chose, transformations) == "eteint":
					occupee_maintenant = true
					break
		if occupee_maintenant:
			if not proprietes.has("occupe"):
				proprietes["occupe"] = true
				if proprietes.has("profil_saillance"):
					proprietes["profil_saillance_gele"] = proprietes["profil_saillance"]
					proprietes.erase("profil_saillance")
		elif proprietes.has("occupe"):
			proprietes.erase("occupe")
			if proprietes.has("profil_saillance_gele"):
				if proprietes.has("travail_restant"):
					proprietes["profil_saillance"] = proprietes["profil_saillance_gele"]
				proprietes.erase("profil_saillance_gele")

# Cablage de banc : appelle les couches (perception -> attaches + proximite
# -> dominance -> agir), inchangees, aucun cas particulier par colon --
# seules les donnees (attaches, forme) distinguent placide, fanatique et
# batisseur. Testable headless (scripts/test_banc_p1.gd).
static func decider(
	colon: Dictionary,
	monde,
	catalogue_canaux: Dictionary,
	menaces: Dictionary,
	profils_saillance: Dictionary,
	catalogue_deformations: Dictionary,
	catalogue_actions: Dictionary,
	catalogue_attaches_par_trait: Dictionary = {},
) -> Dictionary:
	var perceptions := Perception.percevoir(colon, monde, catalogue_canaux)
	var att := Attaches.evaluer(perceptions, colon, menaces, catalogue_deformations)
	var prox := Proximite.evaluer(perceptions, colon, profils_saillance, catalogue_deformations)
	var resultats: Array = att + prox
	var visibles := Dominance.visibles(resultats, colon)
	var decision = Agir.choisir(visibles, colon, catalogue_actions, monde, {}, catalogue_attaches_par_trait)
	return {"decision": decision, "resultats": resultats, "perceptions": perceptions, "visibles": visibles}

# Enveloppe decider() + la memorisation pour le tick suivant
# (agir.gd:etat_courant) -- c'est le fil complet que _faire_agir_colon doit
# executer, extrait en statique pour etre teste sur deux ticks sans
# instancier le Node (voir test_banc_p1.gd). _faire_agir_colon appelle
# CETTE fonction, jamais decider() seule suivie d'une ecriture a cote --
# sinon rien ne verrouille que le cablage reel memorise vraiment. Meme
# geste que banc_feu.gd:decider_et_memoriser, signature propre a CE banc
# (menaces seul avant catalogue_actions, jamais jugements) --
# catalogue_choses n'est PAS un parametre : decider() ne le lirait pas, et
# son contenu
# (data/types_choses.json) reste fusionne dans catalogue_actions par
# _ready avant l'appel, rien n'est perdu.
static func decider_et_memoriser(
	colon: Dictionary,
	monde,
	catalogue_canaux: Dictionary,
	menaces: Dictionary,
	profils_saillance: Dictionary,
	catalogue_deformations: Dictionary,
	catalogue_actions: Dictionary,
	catalogue_attaches_par_trait: Dictionary = {},
) -> Dictionary:
	var r := decider(colon, monde, catalogue_canaux, menaces, profils_saillance, catalogue_deformations, catalogue_actions, catalogue_attaches_par_trait)
	colon.action_en_cours = Agir.etat_courant(r.decision)
	return r

# GESTE COMPLET decision -> mouvement (chantier "boucle.gd", voir
# scripts/boucle.gd et CARTE.md §6) : appelle decider_et_memoriser, resout
# la branche fuite/non-fuite (data/orientations.json), deplace le colon
# (BancCommun.bouger_selon/bouger_vers) -- MUTE colon.position EN PLACE,
# comme decider_et_memoriser mute deja action_en_cours. _faire_agir_colon
# (impur) appelle CETTE fonction puis fait UNIQUEMENT le rendu (print,
# noeud) ; boucle.gd:tracer() l'appelle aussi (liee par l'appelant via
# Callable.bind), pour qu'un test dynamique traverse EXACTEMENT le meme
# chemin que le jeu reel -- plus de 3e copie de cet agencement.
#
# Rend un Dictionary pour le RENDU, jamais ecrit ici : "decision"/
# "resultats" (sortie de decider_et_memoriser) ; "fuite" (bool, la branche
# prise) ; "cible"/"chose" (position/chose visee, pour le libelle et
# BancCommun.verbe_action) ; "position_avant" (colon.position AVANT ce tick,
# necessaire pour que _faire_agir_colon calcule la meme distance/le meme
# "eteint" vs "va vers" qu'avant ce chantier -- colon.position a deja
# bouge quand cette fonction rend la main).
#
# ENGAGEMENT DU COLON (PHASE 1, scripts/couplage.gd) : ferme le bug
# d'oscillation d'un colon sur un chantier LENT (voir docs/design.md,
# corps interne, entree "engagement" ;
# docs/prototypes.md banc_p1). Deux appels, avant
# et apres le pipeline de decision :
# - AVANT decider_et_memoriser : _avancer_engagement_colon fait avancer
#   l'engagement en cours (s'il y en a un) contre sa cible REELLE
#   (retrouvee par id dans monde) -- garde/satisfait/arrache s'evalue
#   AVANT que agir.gd:choisir ne lise l'engagement pour cette decision,
#   jamais apres (sinon la decision de ce tick verrait un etat perime).
# - APRES le calcul de "chose" (la cible visee ce tick) :
#   _mettre_a_jour_engagement_colon retire l'engagement si la decision a
#   change de cible (arrachement par saillance, voir agir.gd -- une
#   alternative a gagne malgre le poids d'engagement, au cablage de
#   detecter le changement et d'appeler Couplage.retirer) ; sinon, si le
#   colon vient d'ARRIVER physiquement a portee_travail d'un chantier
#   (BancCommun.verbe_action == "eteint", meme detection que le reste du
#   banc) et n'est pas deja engage dessus, pose un nouvel engagement
#   "colon_chantier" (data/engagements.json). Se pose par PRESENCE,
#   jamais par decision -- un colon qui vise un chantier de loin ("va
#   vers") n'engage rien tant qu'il n'y est pas.
static func agir_et_deplacer(
	colon: Dictionary,
	monde,
	catalogue_canaux: Dictionary,
	menaces: Dictionary,
	profils_saillance: Dictionary,
	catalogue_deformations: Dictionary,
	catalogue_actions: Dictionary,
	jugements: Dictionary,
	orientations: Dictionary,
	transformations: Dictionary,
	engagements: Dictionary,
	delta: float,
	catalogue_attaches_par_trait: Dictionary = {},
) -> Dictionary:
	_avancer_engagement_colon(colon, monde, delta, engagements)
	var r := decider_et_memoriser(colon, monde, catalogue_canaux, menaces, profils_saillance, catalogue_deformations, catalogue_actions, catalogue_attaches_par_trait)
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
			cible = cible_pour_decision(decision, r.perceptions, menaces, colon.position)
			cible = _cible_ralentie_pour_colon(colon.position, cible, decision)
			chose = Ciblage.viser(decision, r.perceptions, menaces, jugements, orientations)
			colon.position = BancCommun.bouger_vers(colon.position, cible, colon.proprietes.vitesse, delta)
	# LE MONDE EST PREVENU DU DEPLACEMENT. Il range les choses par case pour que
	# la requete de rayon ne visite que le voisinage ; une chose qui bouge sans le
	# dire reste rangee a son ancienne case et devient introuvable la ou elle est.
	# Sans effet quand le colon n'a pas quitte sa case.
	monde.deplacer(colon)
	_mettre_a_jour_engagement_colon(colon, chose, position_avant, transformations, engagements)
	return {
		"decision": decision, "resultats": r.resultats, "fuite": fuite,
		"cible": cible, "chose": chose, "position_avant": position_avant,
	}

# entite.proprietes.engagement lu FACULTATIVEMENT ici (jamais .has()+alarme,
# contrairement a couplage.gd lui-meme) : un colon fabrique par
# BancCommun.fabriquer_colon depuis data/types.json porte toujours cette
# cle (colon herite de entite, voir objet.gd), mais une fixture de test qui
# construit un colon a la main sans elle reste un usage legitime de ce
# cablage -- l'absence dit juste "ne rien faire", pas "ceci n'est pas un
# colon". monde.par_id(id) rend { chose, type } (voir monde.gd) : la cible
# passee a Couplage.avancer doit etre l'objet nu, jamais le wrapper.
static func _avancer_engagement_colon(colon: Dictionary, monde, delta: float, engagements: Dictionary) -> void:
	var engagement: Variant = colon.proprietes.get("engagement", null)
	if engagement == null:
		return
	var trouve: Variant = monde.par_id(engagement.get("cible_id", null))
	var cible_actuelle: Variant = trouve.chose if trouve != null else null
	Couplage.avancer(colon, cible_actuelle, delta, engagements)

static func _mettre_a_jour_engagement_colon(
	colon: Dictionary,
	chose: Variant,
	position_avant: Vector3,
	transformations: Dictionary,
	engagements: Dictionary,
) -> void:
	if not colon.proprietes.has("engagement"):
		return
	var chose_id: Variant = chose.id if (chose != null and chose is Dictionary) else null
	var engagement: Variant = colon.proprietes.engagement
	if engagement != null and engagement.get("cible_id", null) != chose_id:
		Couplage.retirer(colon, "decision changee de cible")
		engagement = null
	if engagement != null:
		return
	if chose == null or not chose is Dictionary or not chose.proprietes.has("travail_restant"):
		return
	if BancCommun.verbe_action({"position": position_avant}, chose.position, chose, transformations) != "eteint":
		return
	Couplage.poser(colon, chose, "colon_chantier", engagements)

# attaches.gd ne rend qu'un nombre (menace), jamais une position : pour
# savoir OU aller defendre, on retrouve depuis les memes perceptions
# brutes le point vise. Ce n'est pas une decision, la decision est deja
# prise (Agir.choisir) -- ceci ne fait que la traduire en lieu.
#
# decision.type porte ici attache.propriete (ex. "irremplacable"), jamais
# un nom de type -- voir attaches.gd. feu_le_plus_proche reutilise donc
# menaces.json au lieu d'un catalogue par type : meme detection que
# attaches.gd:menace_attache (propriete rencontre propriete en portee),
# appliquee ici pour retrouver une POSITION au lieu d'un nombre.
static func cible_pour_decision(
	decision: Dictionary,
	perceptions: Array,
	menaces: Dictionary,
	defaut: Vector3,
) -> Vector3:
	if decision.has("chose"):
		return decision.position
	elif decision.get("menace", 0.0) > 0.0:
		return feu_le_plus_proche(perceptions, decision.type, menaces, defaut)
	return defaut

# RUSTINE (voir DISTANCE_ARRET_COLON ci-dessus) -- recule la cible de
# DISTANCE_ARRET_COLON le long du segment origine->cible_reelle,
# UNIQUEMENT quand decision.type == "colon" (nom de type en dur assume,
# cablage de banc jetable -- meme exception CLAUDE.md que "brule"/
# "combustible" ailleurs dans ce fichier). Toute autre cible (feu,
# batisse, bloc, menace) rend cible_reelle inchangee : bouger_vers
# (banc_commun.gd) n'est jamais touche, seule la valeur qu'il recoit
# change pour ce seul cas. Deja plus proche que la distance d'arret :
# rend origine telle quelle (aucun mouvement), meme idiome que
# bouger_vers:dist < 1.0 -> position inchangee.
static func _cible_ralentie_pour_colon(origine: Vector3, cible_reelle: Vector3, decision: Dictionary) -> Vector3:
	if decision.type != "colon":
		return cible_reelle
	var vers_cible: Vector3 = cible_reelle - origine
	var distance: float = vers_cible.length()
	if distance <= DISTANCE_ARRET_COLON:
		return origine
	return cible_reelle - vers_cible.normalized() * DISTANCE_ARRET_COLON

# Selection commune a feu_le_plus_proche et chose_le_plus_proche : meme
# detection propriete-rencontre-propriete-menace en portee (voir
# attaches.gd:menace_attache), retient la plus proche du trait qui la
# porte. Rend { position, chose } -- une seule boucle ; les deux fonctions
# publiques n'en extraient plus qu'un champ chacune. Ce geste de detection
# etait deja recode plusieurs fois ailleurs dans le moteur (voir
# docs/design.md, "Direction majeure") -- pas une raison d'en ajouter une
# occurrence ici.
static func _selection_par_menace(
	perceptions: Array,
	propriete_attache: String,
	menaces: Dictionary,
	defaut: Vector3,
) -> Dictionary:
	var meilleure_pos := defaut
	var meilleure_chose = null
	var meilleure_d := INF
	for instance in perceptions:
		if not instance.chose.proprietes.get(propriete_attache, false):
			continue
		for vuln in menaces:
			if not instance.chose.proprietes.get(vuln, false):
				continue
			var prop_menace = menaces[vuln]
			for autre in perceptions:
				if not autre.chose.proprietes.get(prop_menace, false):
					continue
				var d: float = instance.position.distance_to(autre.position)
				if d < meilleure_d:
					meilleure_d = d
					meilleure_pos = autre.position
					meilleure_chose = autre.chose
	return {"position": meilleure_pos, "chose": meilleure_chose}

static func feu_le_plus_proche(
	perceptions: Array,
	propriete_attache: String,
	menaces: Dictionary,
	defaut: Vector3,
) -> Vector3:
	return _selection_par_menace(perceptions, propriete_attache, menaces, defaut).position

func _ajouter_chose(id: String, type: String, pos: Array) -> void:
	var position3 := Vector3(pos[0], pos[1], pos[2])
	# _catalogue_materiaux : chantier "densite effective calculee a la
	# fabrication" (objet.gd:fabriquer) -- arbre/bloc portent desormais
	# "composition" (data/types.json), resolue contre data/materiaux.json.
	# Sans ce catalogue, tout materiau referme apparaitrait absent et
	# refuserait la fabrication (retour {}) -- voir objet.gd, DENSITE
	# EFFECTIVE, echec fort.
	var objet := Objet.fabriquer(id, type, position3, _catalogue_types, _catalogue_materiaux)
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

# Une barre par reserve, empilee au-dessus du carre du colon -- meme
# convention que banc_animal.gd:_dessiner_barre (largeur = grandeur
# visuelle, aucun nombre affiche, jamais lu par le coeur). Generique au
# nombre de reserves portees par CE colon (boucle sur son propre
# Dictionary reserves, aucun nom en dur) : reserve un ColorRect par nom,
# positionne/dimensionne ensuite par _redessiner_barres_reserves.
func _dessiner_barres_reserves(reserves: Dictionary) -> Dictionary:
	var barres: Dictionary = {}
	for nom in reserves:
		barres[nom] = _dessiner_barre_reserve(_couleur_reserve(nom))
	return barres

func _dessiner_barre_reserve(couleur: Color) -> ColorRect:
	var barre := ColorRect.new()
	barre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	barre.color = couleur
	add_child(barre)
	return barre

# Repositionne/redimensionne les barres d'un colon d'apres ses reserves
# VIVANTES (mutees en place par Depense.avancer, voir en-tete du fichier).
# Meme clamp que banc_animal.gd:_positionner_barre : une largeur negative
# n'atteint jamais le rendu. Garde du CABLAGE, pas un doublon du coeur --
# depense.gd borne deja la reserve a 0.0 (design.md, "Depense : reserve
# bornee a zero"), mais rien n'interdit a une autre source d'ecrire cette
# valeur, et un rectangle de largeur negative est un defaut d'affichage.
func _redessiner_barres_reserves(colon: Dictionary) -> void:
	var reserves: Dictionary = colon.proprietes.get("reserves", {})
	var barres: Dictionary = _barres_reserves.get(colon.id, {})
	var pos := Vector2(colon.position.x, colon.position.y)
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

func _couleur_reserve(nom: String) -> Color:
	var rgb: Array = _couleurs_reserves.get(nom, [1.0, 1.0, 1.0])
	return Color(rgb[0], rgb[1], rgb[2])

func _charger_json(chemin: String) -> Dictionary:
	var texte := FileAccess.get_file_as_string(chemin)
	return JSON.parse_string(texte)
