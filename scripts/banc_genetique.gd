extends Node2D

# Cablage de banc VISUEL, separe des autres bancs (Scene/banc_genetique.tscn,
# PAS la scene principale -- run/main_scene reste banc_p1). Existe pour VOIR
# scripts/expression.gd produire un TRADE-OFF observable en jeu : trois
# colons, memes couches, memes attaches/forme/poids_verbes -- SEULE la
# genetique diverge (memes convention que tous les bancs de ce chantier :
# "identiques a la naissance, seule X differe"). JETABLE PAR DEFINITION :
# aucune regle de jeu ne doit vivre ici, seulement du cablage.
#
# CE QUE CE BANC MONTRE : AUCUN feu au demarrage -- un clic gauche en pose
# un (patron banc_p1.gd:_unhandled_input, Objet.fabriquer a la position du
# clic, plusieurs clics/plusieurs feux independants). Yael choisit OU le
# poser pour explorer un trade-off different a chaque fois : loin (seul le
# colon a la plus grande portee de vue reagit, les autres restent immobiles
# -- la difference de PERCEPTION devient visible) ; pres d'un seul colon
# (seule la VITESSE differencie l'arrivee) ; entre deux colons (lequel
# reagit/arrive en premier depend des deux a la fois). Un seul gene,
# "vivacite" (data/banc_genetique.json:catalogue_genes, LOCAL -- voir
# plus bas), TROIS cibles a la fois : canaux_config.vue.portee (voit plus
# loin), vitesse (bouge plus vite), reserves.energie.cout_base (consomme
# plus d'energie par seconde -- CHAQUE seconde, pas seulement en bougeant :
# voir data/banc_genetique.json:catalogue_genes._note pour pourquoi c'est
# cout_base, pas reserve, qui porte le poids). Les trois colons portent le
# MEME gene ; seuls les alleles differencient :
# - "vif" (alleles [1,1]) : voit plus loin, bouge plus vite, ARRIVE LE
#   PREMIER sur le feu -- mais son cout_base d'energie est le plus haut,
#   sa reserve s'epuise EN PREMIER.
# - "moyen" (alleles [0,0]) : AUCUN effet du gene (0 + 0 = 0 sur les trois
#   cibles) -- reste exactement au defaut du type "colon". Ni le premier
#   ni le dernier, ni le plus resistant ni le plus fragile, PAR CONSTRUCTION
#   (voir data/banc_genetique.json:catalogue_genes._note).
# - "endurant" (alleles [-1,-1]) : voit moins loin, bouge plus lentement,
#   ARRIVE LE DERNIER -- mais son cout_base est le plus bas, sa reserve
#   dure le plus longtemps.
# AUCUNE strategie ne domine les deux autres : chacune echange une chose
# contre une autre (voir docs/design.md, meme esprit que "Les archetypes
# n'existent pas" applique a un axe physiologique plutot qu'a une attache).
#
# VOIE (b) DE L'AUDIT FONDATION GENETIQUE (confirmee) : expression.gd n'est
# JAMAIS appele par objet.gd -- ce banc appelle ExpressionGenetique.exprimer
# puis .appliquer juste apres BancCommun.fabriquer_colon, dans
# _fabriquer_colon_genetique (voir plus bas). objet.gd/expression.gd ne sont
# pas touches par ce chantier.
#
# SURCHARGE DE genes_actifs/genes_etat, PATRON DE REMPLACEMENT TOTAL (PAS
# le patron de fusion partielle de banc_vecu_inter_colon.gd:
# _appliquer_portee_ecoute) : genes_actifs/genes_etat sont des cles de
# PREMIER NIVEAU sur le paquet dynamique, vides ([]/{}) par defaut -- rien
# a perdre en les remplacant en bloc depuis la declaration du banc, meme
# geste que BancCommun.fabriquer_colon pour attaches/forme/poids_verbes
# (jamais une fusion cle-par-cle necessaire ici, contrairement a
# canaux_config qui, lui, porte deja six canaux peuples qu'une surcharge
# partielle effacerait -- voir CARTE.md §6).
#
# reserves.energie.reserve SURCHARGEE A 8.0 (au lieu du defaut 100.0 de
# data/types.json:dynamique), AVANT l'application du gene -- voir
# data/banc_genetique.json._note : au taux par defaut (cout_base 0.3/s),
# 100.0 se serait epuise en plusieurs minutes, bien au-dela d'une session
# d'observation raisonnable. reserves_max.energie (rendu, JSON) est
# surcharge a la meme valeur pour que la barre demarre PLEINE.
#
# "feu" reste LOCAL (data/banc_genetique.json:types, exception banc jetable
# de CLAUDE.md), SANS son canal reserves.combustible habituel
# (data/types.json:feu en porte un qui s'epuiserait tout seul en 1.5s au
# rythme par defaut -- bien avant qu'aucun colon n'arrive, meme au plus
# rapide) -- profil_saillance/transformation restent des REFERENCES REELLES
# (data/profils_saillance.json/data/transformations.json, jamais mutees).
# `travail_restant`/`travail_initial`/`transformation` sont deja portes par
# l'entree de type elle-meme (contrairement a banc_p1.gd, qui les ajoute a
# la volee via BancCommun.resoudre_chantier + un patron partage, parce que
# son "feu" doit aussi se propager -- inutile ici, chaque feu est pose
# directement complet par Objet.fabriquer).
#
# EXTINCTION CABLEE (correction session ulterieure) : Extinction.avancer
# tourne chaque tick sur TOUT `_monde` aplati (BancCommun.agents_rythme,
# nos trois colons portent deja `rythme` depuis data/types.json:colon,
# aucune surcharge necessaire) -- meme patron que banc_p1.gd (agents ->
# Extinction.avancer -> BancCommun.marquer_eteints). Plusieurs colons a
# portee du MEME feu contribuent tous (extinction.gd ne differencie jamais
# par gene) : la genetique differencie QUAND chacun arrive, jamais la
# vitesse d'extinction une fois sur place -- une fois eteint (a_zero
# retire brule/profil_saillance, data/transformations.json:defaut), le feu
# n'est plus salient, les colons se redirigent seuls, aucun code special.
#
# PIPELINE COMPLET, PAS UN CABLAGE DIRECT (contrairement a
# banc_convergence_attache.gd/banc_vecu_inter_colon.gd) : la difference
# genetique doit traverser une DECISION reelle pour etre une preuve de
# trade-off, pas seulement un etat pose -- perception -> attaches+proximite
# -> dominance -> agir -> bouger_vers, MEME QUATRE COUCHES que
# banc_p1.gd:decider (aucun jugement, aucune fuite : catalogue_actions ne
# propose qu'"approcher", jamais oriente fuite dans data/orientations.json).
#
# CONSTAT GEOMETRIQUE (a ne pas reperdre, NUANCE apres le clic -- avant,
# l'ancienne version fixait le feu a 400 unites, a portee des trois) : avec
# un feu STATIQUE et un colon STATIQUE tant qu'il n'a rien percu, un colon
# dont la portee de vue n'atteint pas le clic ne bougera JAMAIS de
# lui-meme -- ce n'est PLUS une limite a contourner, c'est exactement ce
# que ce chantier demande : cliquer loin (au-dela de la portee de
# l'endurant, voire du moyen) rend la difference de PERCEPTION observable,
# un ou deux colons restant immobiles pendant que le(s) autre(s) reagissent
# deja. `test_banc_genetique.gd` continue de placer son propre feu a
# portee des trois profils (chemin deterministe, ordre d'ARRIVEE/
# EPUISEMENT verrouille) -- il ne pretend toujours pas verrouiller un ordre
# de PERCEPTION distinct, qui depend maintenant d'OU Yael clique, pas d'une
# donnee fixe.
#
# RISQUE DORMANT, PAS CORRIGE ICI (audit 2026-08-06) : data/types.json:colon
# porte profil_saillance: "colon" (chantier "colon saillant") -- herite ici
# comme dans banc_feu.gd/banc_charge.gd, qui s'empilaient au repos pour
# cette raison avant correction (meme session). CE banc-ci n'a PAS ce
# defaut aujourd'hui, mais par ACCIDENT DE POSITION, pas par garde : les
# trois colons sont a ~692 unites les uns des autres (vif<->moyen/endurant),
# au-dela de la portee de saillance mutuelle (data/profils_saillance.json,
# ~350 unites) -- ils ne se percoivent donc jamais comme saillants entre
# eux. Si ces positions se rapprochent un jour (rayon du triangle reduit,
# nouveau colon ajoute plus pres), le meme empilement qu'a banc_feu/
# banc_charge reapparaitra ici sans avertissement -- aucun test ne
# l'attrape (meme angle mort, voir prototypes.md). A corriger la ou le
# meme choix se posera : soit un retrait local (comme banc_feu.gd/
# banc_charge.gd, si le sujet reste la comparaison individuelle des trois
# genotypes), soit garder la saillance (si la convergence devient un jour
# le sujet).
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge data/banc_genetique.json + les catalogues
#   partages (types.json, canaux.json, menaces.json, profils_saillance.json,
#   types_choses.json, orientations.json, transformations.json), fabrique
#   les trois colons (AUCUN feu), pose la Camera2D centree sur leur
#   CENTROIDE (meme patron que banc_vecu_inter_colon.gd:_poser_camera,
#   deuxieme reutilisation de ce patron -- calculee depuis les positions
#   reelles des colons, plus depuis celle d'un feu qui n'existe plus au
#   demarrage). _unhandled_input (patron banc_p1.gd) pose un feu a la
#   position du clic gauche, Objet.fabriquer, plusieurs clics/plusieurs
#   feux independants, chacun son propre id (_compteur_feu). _process fait
#   avancer Depense.avancer (catalogue vide -- aucun canal de ce banc ne
#   porte de seuils_ref) puis chaque colon (agir_et_deplacer), verifie les
#   trois evenements a imprimer, redessine carre + barres de reserve
#   (patron banc_p1.gd).
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_genetique.gd) : _fabriquer_colon_genetique (fabrication +
#   surcharge reserve + surcharge genes + expression, SANS _monde ni rendu) ;
#   decider/decider_et_memoriser/agir_et_deplacer (memes roles qu'en
#   banc_p1.gd, quatre couches, signature reduite -- aucun jugement, aucune
#   fuite, aucun engagement : rien de tout cela n'est jamais exerce ici) ;
#   _percoit_declencheur/_est_arrive_sur_le_feu/_reserve_energie_epuisee --
#   detections pures pour les trois evenements a imprimer. _percoit_declencheur
#   est generique par PROPRIETE ("brule", jamais un id de feu precis --
#   plusieurs feux peuvent coexister depuis le clic), meme patron que
#   banc_deformation.gd:percoit_declencheur, duplique ici (meme discipline
#   que _dessiner_barres_reserves ci-dessous).

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
const ExpressionGenetique = preload("res://scripts/expression.gd")

const TAILLE_CARRE := 24.0
const LARGEUR_BARRE_RESERVE := 24.0
const HAUTEUR_BARRE_RESERVE := 3.0

# Meme raisonnement que banc_vecu_inter_colon.gd:ZOOM_CAMERA -- aucune
# dimension custom dans project.godot (defaut 1152x648, verifie avant
# d'ecrire). Les trois colons sont a 400 unites de l'origine (le feu) ;
# 0.65 laisse une demi-hauteur visible de 648/2/0.65 = 498 unites, marge
# suffisante pour les barres de reserve au-dessus de chaque colon.
const ZOOM_CAMERA := 0.65

var _donnees: Dictionary = {}
var _catalogue_types: Dictionary = {}
var _catalogue_canaux: Dictionary = {}
var _menaces: Dictionary = {}
var _profils_saillance: Dictionary = {}
var _catalogue_actions: Dictionary = {}
var _orientations: Dictionary = {}
var _transformations: Dictionary = {}
var _catalogue_deformations: Dictionary = {}
var _catalogue_genes: Dictionary = {}
var _couleurs_colons: Dictionary = {}
var _couleurs_types_rendu: Dictionary = {}
var _reserves_max: Dictionary = {}
var _couleurs_reserves: Dictionary = {}
var _monde := Monde.new()
var _colons: Array = []
var _noeuds: Dictionary = {}
var _barres_reserves: Dictionary = {}
var _etats_impression: Dictionary = {}
var _temps_ecoule := 0.0
var _compteur_feu := 0

func _ready() -> void:
	_donnees = _charger_json("res://data/banc_genetique.json")
	_couleurs_colons = _donnees.get("couleurs_colons", {})
	_couleurs_types_rendu = _donnees.get("couleurs_types", {})
	_couleurs_reserves = _donnees.get("couleurs_reserves", {})
	_reserves_max = _donnees.get("reserves_max", {})
	_catalogue_genes = _donnees.get("catalogue_genes", {})

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
	# Chargee et transmise pour EVITER l'alarme de deformation.gd:biais --
	# colon herite deformation_sources: ["habituation"] depuis
	# data/types.json (chantier PHASE 4), inerte ici (aucun de nos trois
	# colons ne differe par sa deformation), mais un catalogue {} ferait
	# alarmer 'source habituation absente du catalogue' a chaque tick.
	# Meme geste que banc_p1.gd/banc_feu.gd/banc_charge.gd : charger et
	# transmettre reellement, jamais deviner un defaut vide.
	_catalogue_deformations = _charger_json("res://data/deformations.json")

	var reserve_initiale: float = _donnees.get("reserve_energie_initiale", 100.0)
	var declarations: Dictionary = _donnees.get("colons", {})
	var positions: Array = []
	for nom in declarations:
		positions.append(_ajouter_colon(nom, declarations[nom], reserve_initiale))

	_poser_camera(positions)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_compteur_feu += 1
		var pos := get_global_mouse_position()
		_ajouter_feu("feu_%d" % _compteur_feu, [pos.x, pos.y, 0.0])

func _ajouter_feu(id: String, pos: Array) -> void:
	var position3 := Vector3(pos[0], pos[1], pos[2])
	var feu := Objet.fabriquer(id, "feu", position3, _catalogue_types)
	_monde.ajouter(feu, "feu", position3)
	_noeuds[id] = _dessiner_carre(position3, _couleur_rendu("feu"))

# Rend la position (Vector2) du colon ajoute -- collectee par l'appelant
# pour centrer la camera (voir _poser_camera), plus simple que retrouver
# ces positions plus tard depuis _monde.
func _ajouter_colon(nom: String, decl: Dictionary, reserve_initiale: float) -> Vector2:
	var colon := _fabriquer_colon_genetique(nom, decl, _catalogue_types, _catalogue_genes, reserve_initiale)
	_monde.ajouter(colon, "colon", colon.position)
	_colons.append(colon)
	_noeuds[colon.id] = _dessiner_carre(colon.position, _couleur_colon(nom))
	_barres_reserves[colon.id] = _dessiner_barres_reserves(colon.proprietes.get("reserves", {}))
	_etats_impression[colon.id] = {"percu": false, "arrive": false, "epuise": false}
	return Vector2(colon.position.x, colon.position.y)

# Camera2D centree sur le CENTROIDE des trois colons (aucun feu n'existe
# plus au demarrage pour servir de centre, voir en-tete) -- meme patron que
# banc_vecu_inter_colon.gd:_poser_camera (motif : un Node2D sans camera
# s'affiche dans le referentiel monde brut, origine en haut a gauche du
# viewport ; ici la MOITIE des colons ont des coordonnees negatives,
# invisibles sans camera). get_global_mouse_position() (voir
# _unhandled_input) tient deja compte de cette camera automatiquement --
# un clic pose toujours un feu aux VRAIES coordonnees du monde, quel que
# soit le zoom.
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

# Fabrication PURE (testable headless, voir test_banc_genetique.gd) : ne
# touche ni _monde ni le rendu. Ordre : composition de paquets
# (BancCommun.fabriquer_colon) -> surcharge de la reserve d'energie de
# depart (AVANT le gene, pour que le gene module cout_base sur la valeur
# stable du type, jamais un residu d'un calcul precedent) -> surcharge
# TOTALE de genes_actifs/genes_etat (patron de remplacement, voir en-tete)
# -> ExpressionGenetique.exprimer + .appliquer (VOIE (b) de l'audit
# fondation genetique : jamais dans objet.gd).
static func _fabriquer_colon_genetique(
	nom: String,
	decl: Dictionary,
	catalogue_types: Dictionary,
	catalogue_genes: Dictionary,
	reserve_energie_initiale: float,
) -> Dictionary:
	var colon := BancCommun.fabriquer_colon(nom, "colon", decl, catalogue_types)
	colon.proprietes.reserves.energie["reserve"] = reserve_energie_initiale
	colon.proprietes["genes_actifs"] = decl.get("genes_actifs", [])
	colon.proprietes["genes_etat"] = decl.get("genes_etat", {})
	var valeurs := ExpressionGenetique.exprimer(colon, catalogue_genes, {}, {})
	ExpressionGenetique.appliquer(colon, valeurs)
	return colon

# QUATRE COUCHES (comme banc_p1.gd:decider) : perception -> attaches +
# proximite -> dominance -> agir. Aucun jugement (rien dans ce banc n'en a
# besoin -- une seule chose saillante possible, le feu).
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
# ne propose jamais un verbe oriente "fuite" dans data/orientations.json,
# vérifié : seule l'entrée "approcher" existe pour "brule" dans ce banc).
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

# Vrai des qu'une chose PERCUE (couche 1) porte la propriete declencheur
# (recue en parametre, jamais "brule" en dur ici) -- independant de la
# saillance/decision, et independant de l'id : plusieurs feux peuvent
# coexister depuis le clic (voir _unhandled_input), n'importe lequel
# suffit a declencher l'evenement "percoit".
static func _percoit_declencheur(perceptions: Array, declencheur: String) -> bool:
	for entree in perceptions:
		if entree.chose.proprietes.get(declencheur, false):
			return true
	return false

# Meme detection que BancCommun.verbe_action partout ailleurs dans le
# depot (distance <= portee_travail resolue depuis transformation) :
# "eteint" veut dire "a portee de travail", jamais un rayon en dur ici.
static func _est_arrive_sur_le_feu(colon_position: Vector3, feu: Dictionary, transformations: Dictionary) -> bool:
	return BancCommun.verbe_action({"position": colon_position}, feu.position, feu, transformations) == "eteint"

# depense.gd borne la reserve a 0.0 a la soustraction (docs/design.md,
# "Depense : reserve bornee a zero") -- "epuisee" est ici un evenement
# d'AFFICHAGE (ce banc), pas une regle du coeur : <= 0.0, jamais < 0.0, la
# reserve s'arretant exactement au plancher.
static func _reserve_energie_epuisee(colon: Dictionary) -> bool:
	return colon.proprietes.reserves.energie.reserve <= 0.0

func _process(delta: float) -> void:
	_temps_ecoule += delta
	var objets := BancCommun.objets_de(_monde)
	Depense.avancer(objets, delta, {})
	var agents := BancCommun.agents_rythme(objets)
	var eteints := Extinction.avancer(objets, agents, delta, _transformations)
	BancCommun.marquer_eteints(eteints, _noeuds, _monde, _couleur_rendu("cendre"), _temps_ecoule)
	for colon in _colons:
		var g := agir_et_deplacer(colon, _monde, _catalogue_canaux, _menaces, _profils_saillance, _catalogue_deformations, _catalogue_actions, _orientations, delta)
		_verifier_evenements(colon, g.perceptions, g.chose)
		_redessiner_colon(colon)

# Imprime CHAQUE evenement une seule fois, au FRANCHISSEMENT (jamais a
# chaque frame) -- meme discipline que tous les autres bancs (action_actuelle
# != action_precedente, formations d'attache, etc.). "arrive" se verifie
# contre la chose CIBLEE par la decision de ce tick (g.chose, resolue par
# Ciblage.viser dans agir_et_deplacer) -- jamais un feu fixe : depuis le
# clic, plusieurs feux peuvent exister, seul celui vise compte.
func _verifier_evenements(colon: Dictionary, perceptions: Array, chose_ciblee) -> void:
	var etat: Dictionary = _etats_impression[colon.id]
	if not etat.percu and _percoit_declencheur(perceptions, "brule"):
		etat.percu = true
		print("t=%.2f %s : percoit le feu" % [_temps_ecoule, colon.id])
	if not etat.arrive and chose_ciblee != null and _est_arrive_sur_le_feu(colon.position, chose_ciblee, _transformations):
		etat.arrive = true
		print("t=%.2f %s : arrive sur le feu" % [_temps_ecoule, colon.id])
	if not etat.epuise and _reserve_energie_epuisee(colon):
		etat.epuise = true
		print("t=%.2f %s : reserve d'energie epuisee" % [_temps_ecoule, colon.id])

func _couleur_colon(nom: String) -> Color:
	var rgb: Array = _couleurs_colons.get(nom, [1.0, 1.0, 1.0])
	return Color(rgb[0], rgb[1], rgb[2])

func _couleur_rendu(nom: String) -> Color:
	var rgb: Array = _couleurs_types_rendu.get(nom, [1.0, 1.0, 1.0])
	return Color(rgb[0], rgb[1], rgb[2])

func _dessiner_carre(position3: Vector3, couleur: Color) -> ColorRect:
	var carre := ColorRect.new()
	carre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	carre.size = Vector2(TAILLE_CARRE, TAILLE_CARRE)
	carre.color = couleur
	carre.position = Vector2(position3.x, position3.y) - carre.size / 2.0
	add_child(carre)
	return carre

# Une barre par reserve, meme convention que banc_p1.gd
# (_dessiner_barres_reserves/_redessiner_barres_reserves) : generique au
# nombre de reserves portees par CE colon, largeur = grandeur visuelle,
# aucun nombre affiche, jamais lu par le coeur. Duplique ici (fonction pure,
# meme discipline que banc_convergence_attache.gd:_moyenne_glissante
# duplique depuis banc_comptage.gd) -- pas descendu dans banc_commun.gd,
# un seul autre appelant (banc_p1.gd) ne suffit pas a justifier une
# promotion, voir CARTE.md §6.
func _dessiner_barres_reserves(reserves: Dictionary) -> Dictionary:
	var barres: Dictionary = {}
	for nom in reserves:
		var barre := ColorRect.new()
		barre.mouse_filter = Control.MOUSE_FILTER_IGNORE
		barre.color = _couleur_reserve(nom)
		add_child(barre)
		barres[nom] = barre
	return barres

func _couleur_reserve(nom: String) -> Color:
	var rgb: Array = _couleurs_reserves.get(nom, [1.0, 1.0, 1.0])
	return Color(rgb[0], rgb[1], rgb[2])

func _redessiner_colon(colon: Dictionary) -> void:
	var noeud: ColorRect = _noeuds[colon.id]
	noeud.position = Vector2(colon.position.x, colon.position.y) - noeud.size / 2.0
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

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
