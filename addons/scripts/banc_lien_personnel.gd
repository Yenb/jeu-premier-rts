extends Node2D

# Cablage de banc VISUEL, scene separee (Scene/banc_lien_personnel.tscn, PAS
# la scene principale -- run/main_scene reste banc_p1.tscn). JETABLE PAR
# DEFINITION. Existe pour VOIR scripts/lien_personnel.gd recevoir un evenement
# reel : la defense d'un ouvrage en feu.
#
# CE QUE LE BANC MONTRE : quatre colons identiques a la naissance (meme forme
# vide, meme poids_verbes {"eteindre": 1.0}, meme liens_personnels vide) --
# seules leur POSITION et leur sensibilite_generalisation different, ce sont
# les deux variables experimentales. Les trois pompiers restent a portee de vue
# ET de travail d'une batisse en feu ; le spectateur est hors de portee de tout,
# sa decision ne resout donc jamais "eteindre" et son registre reste vide. Une
# barre au-dessus de chaque colon (largeur = grandeur visuelle, convention de
# banc_deformation.gd) reflete LienPersonnel.force vers la batisse. Un carre
# dore apparait des que l'attache par trait se forme, et y reste pour toujours
# -- une attache formee est IMMUABLE.
#
# TROIS RYTHMES DE CRISTALLISATION, sous exposition identique : les seuils sont
# lus colon-d'abord, catalogue en repli (voir attache_par_trait.gd). Le rapide
# surcharge seuil_nombre a 2, le moyen ne surcharge rien (seuils partages de
# data/attaches_par_trait.json), le lent surcharge seuil_nombre a 5 ET
# seuil_force a 0.5.
#
# PIPELINE A QUATRE COUCHES, comme banc_p1.gd:decider -- jamais jugement.gd
# (aucun abri, aucune fuite ici). C'EST LE PASSAGE PAR agir.gd QUI EST LE POINT
# de ce banc : lien_personnel.gd ne peut recevoir son evenement que par l'effet
# de bord ACTES LIANTS de Agir.choisir (voir agir.gd). Ce fichier ne pose jamais
# un lien lui-meme ; il appelle le pipeline et fait avancer la decroissance
# chaque tick, pour les quatre colons. Consequence observable : l'accumulation
# suit la DECISION resolue tick apres tick tant que le feu brule, et s'arrete
# quand il est eteint -- les liens deja formes, eux, restent.
#
# COMPOSE, tous INCHANGES : les quatre couches, lien_personnel.gd, son bonus de
# saillance, son attraction, attache_par_trait.gd, couplage.gd, propagation.gd,
# extinction.gd, depense.gd.
#
# QUATRE DECISIONS PROPRES A CE BANC :
# - catalogue_local "brule" -> ["eteindre"], et il EST _catalogue_actions dans
#   son entier -- rien a fusionner. Le data/types_choses.json partage garde
#   "brule" -> "approcher", inchange.
# - chaque feu allume au clic porte notre_ouvrage : il devient candidat a SON
#   PROPRE acte liant, par le meme mecanisme generique, sans qu'une ligne de ce
#   fichier ne le sache. Plusieurs clics produisent plusieurs liens simultanes.
# - la batisse ne porte PAS de vulnerabilite : elle demarre en feu et doit
#   RESTER eteinte une fois sauvee, sinon un feu voisin la rallume
#   cycliquement jusqu'a consumption.
# - "bois_0", objet local inflammable pose a portee de la batisse, existe pour
#   rendre Propagation.avancer OBSERVABLE : sans lui rien n'est vulnerable dans
#   cette scene et le cablage resterait inerte. Il se consume seul, faute de
#   defenseur.
#
# LIMITE DITE PLUTOT QUE MASQUEE : lien_personnel_attraction.gd est cable ici
# mais SANS EFFET OBSERVABLE -- batisse et feux cliques portent deja un
# profil_saillance, le candidat qu'il ajoute double donc une cible deja
# gagnante au lieu d'en creer une. La preuve du trou qu'il comble (une chose
# aimee SANS saillance propre devient une cible atteignable) vit dans
# test_lien_personnel_attraction.gd, pas dans ce banc.
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge les donnees et fabrique le monde,
#   _unhandled_input allume au clic (il DECLENCHE, il ne calcule jamais),
#   _process fait avancer propagation/extinction/depense puis, par colon,
#   agir_et_deplacer et la decroissance du lien, et redessine.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_lien_personnel.gd) : decider (les quatre etapes, plus le bonus de
#   lien applique additivement a chaque entree identifiee et le candidat
#   d'attraction ajoute avant lui) ; decider_et_memoriser (enveloppe qui ecrit
#   action_en_cours) ; agir_et_deplacer (le geste complet decision -> mouvement,
#   appele aussi par le test : un seul chemin de code pour le jeu et pour le
#   test) ; cible_pour_decision/_selection_par_menace/feu_le_plus_proche,
#   recopiees de banc_p1.gd -- deux bancs jetables ne se referencent jamais.

const Objet = preload("res://scripts/objet.gd")
const Monde = preload("res://scripts/monde.gd")
const Perception = preload("res://scripts/perception.gd")
const Attaches = preload("res://scripts/attaches.gd")
const Proximite = preload("res://scripts/proximite.gd")
const Dominance = preload("res://scripts/dominance.gd")
const Agir = preload("res://scripts/agir.gd")
const Ciblage = preload("res://scripts/ciblage.gd")
const Propagation = preload("res://scripts/propagation.gd")
const Extinction = preload("res://scripts/extinction.gd")
const Depense = preload("res://scripts/depense.gd")
const Couplage = preload("res://scripts/couplage.gd")
const LienPersonnel = preload("res://scripts/lien_personnel.gd")
const LienPersonnelSaillance = preload("res://scripts/lien_personnel_saillance.gd")
const LienPersonnelAttraction = preload("res://scripts/lien_personnel_attraction.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")

const LARGEUR_BARRE := 40.0
const HAUTEUR_BARRE := 5.0
const ID_BATISSE := "batisse_0"
const ID_FEU_PROCHE := "feu_proche_0"
const ID_BOIS := "bois_0"
const ID_PREFIXE_FEU := "feu_"

var _couleurs_types: Dictionary = {}
var _catalogue_types: Dictionary = {}
var _catalogue_actions: Dictionary = {}
var _catalogue_canaux: Dictionary = {}
var _profils_saillance: Dictionary = {}
var _catalogue_deformations: Dictionary = {}
var _catalogue_actes_liants: Dictionary = {}
var _catalogue_liens: Dictionary = {}
var _catalogue_attaches_par_trait: Dictionary = {}
var _menaces: Dictionary = {}
var _orientations: Dictionary = {}
var _jugements: Dictionary = {}
var _engagements: Dictionary = {}
var _seuils_combustible: Dictionary = {}
var _transformations: Dictionary = {}
var _patron: Dictionary = {}
var _exposition: Dictionary = {}
var _biais_max := 1.0
var _monde := Monde.new()
var _colons: Array = []
var _noeuds: Dictionary = {}
var _barres: Dictionary = {}
var _marqueurs_attache: Dictionary = {}
var _comptes_attaches: Dictionary = {}
var _temps_ecoule := 0.0
var _compteur_feu := 0

func _ready() -> void:
	var donnees := _charger_json("res://data/banc_lien_personnel.json")
	_couleurs_types = donnees.get("couleurs_types", {})
	# "batisse" reste local (vocabulaire propre a ce banc, voir CLAUDE.md) ;
	# objet_physique/dynamique/percevant/agent (et "colon") viennent du catalogue PARTAGE
	# (data/types.json), meme geste que banc_deformation.gd/banc_charge.gd:_ready.
	_catalogue_types = donnees.get("types", {}).duplicate(true)
	var types_partages := _charger_json("res://data/types.json")
	_catalogue_types["objet_physique"] = types_partages.get("objet_physique", {})
	_catalogue_types["dynamique"] = types_partages.get("dynamique", {})
	_catalogue_types["percevant"] = types_partages.get("percevant", {})
	_catalogue_types["agent"] = types_partages.get("agent", {})
	_catalogue_types["colon"] = types_partages.get("colon", {})
	# catalogue_local EST _catalogue_actions dans son entier -- "brule" ->
	# "eteindre" ici, jamais "approcher" (data/types_choses.json partage
	# n'est meme pas charge, ce banc n'en a pas besoin).
	_catalogue_actions = donnees.get("catalogue_local", {})
	_catalogue_canaux = _charger_json("res://data/canaux.json")
	_profils_saillance = _charger_json("res://data/profils_saillance.json")
	_catalogue_deformations = _charger_json("res://data/deformations.json")
	_catalogue_actes_liants = _charger_json("res://data/actes_liants.json")
	_catalogue_liens = _charger_json("res://data/liens_personnels.json")
	_catalogue_attaches_par_trait = _charger_json("res://data/attaches_par_trait.json")
	_menaces = _charger_json("res://data/menaces.json")
	_orientations = _charger_json("res://data/orientations.json")
	_jugements = _charger_json("res://data/jugements.json")
	_engagements = _charger_json("res://data/engagements.json")
	_seuils_combustible = _charger_json("res://data/seuils_combustible.json")
	var donnees_transformations := _charger_json("res://data/transformations.json")
	_patron = donnees_transformations.get("patron", {})
	_transformations = donnees_transformations.get("transformations", {})
	_biais_max = donnees.get("biais_max", 1.0)

	var batisse_decl: Dictionary = donnees.get("batisse", {})
	_ajouter_chose(ID_BATISSE, "batisse", batisse_decl.get("position", [0.0, 0.0, 0.0]))

	var feu_proche_decl: Dictionary = donnees.get("feu_proche", {})
	_ajouter_chose(ID_FEU_PROCHE, "feu_proche", feu_proche_decl.get("position", [0.0, 20.0, 0.0]))

	var bois_decl: Dictionary = donnees.get("bois", {})
	_ajouter_chose(ID_BOIS, "bois", bois_decl.get("position", [0.0, 0.0, 0.0]))

	var declarations: Dictionary = donnees.get("colons", {})
	for nom in declarations:
		_ajouter_colon(nom, declarations[nom])

func _ajouter_chose(id: String, type: String, pos: Array) -> void:
	var position3 := Vector3(pos[0], pos[1], pos[2])
	var objet := Objet.fabriquer(id, type, position3, _catalogue_types)
	_monde.ajouter(objet, type, position3)
	_noeuds[id] = _dessiner_carre(type, pos)

func _ajouter_colon(nom: String, decl: Dictionary) -> void:
	var colon := BancCommun.fabriquer_colon(nom, "colon", decl, _catalogue_types)
	# COLON SAILLANT, RETIRE LOCALEMENT (chantier "colon saillant") :
	# data/types.json:colon porte desormais profil_saillance: "colon"
	# (heritage partage avec banc_p1.gd/banc_feu.gd/banc_charge.gd, qui le
	# gardent). Ce banc, lui, demontre la formation CIBLEE d'un lien
	# personnel sur UNE chose precise (batisse_0/feu_ouvrage) -- les quatre
	# colons sont regroupes a courte distance les uns des autres (voir
	# data/banc_lien_personnel.json, pompier_rapide/moyen/lent a 150
	# unites d'ecart), largement a portee de vue mutuelle : les laisser
	# saillants les uns pour les autres detournerait la decision vers
	# "aller vers un autre pompier" (action vide, aucun verbe ne resout
	# sur un colon) au lieu du chantier observe, perturbant le
	# comportement deja verrouille par test_banc_lien_personnel.gd. Retire
	# la reference ICI, en LOCAL, jamais dans data/types.json ni dans
	# BancCommun.fabriquer_colon (partage avec les bancs qui, eux,
	# gardent la saillance inter-colon) -- proximite.gd traite une cle
	# absente comme une chose non saillante, point neutre legitime (voir
	# proximite.gd:evaluer, ref == "" -> continue), jamais une alarme.
	colon.proprietes.erase("profil_saillance")
	# sensibilite_generalisation (PHASE 5 etape 4/4 piece 2/3) : surcharge
	# PAR COLON des seuils d'attache_par_trait.gd -- pas un champ que
	# BancCommun.fabriquer_colon connait (outil partage avec banc_p1.gd/
	# banc_feu.gd/banc_charge.gd, qui n'en ont pas besoin), pose ici en
	# LOCAL, meme geste que banc_charge.gd:_fabriquer_colon_charge pour
	# etats.peur.seuil. Facultative sur l'entite (voir attache_par_trait.gd) :
	# {} par defaut pour un colon qui ne surcharge rien, jamais absente de
	# proprietes (evite un .get(cle, {}) en cascade cote lecteur).
	colon.proprietes["sensibilite_generalisation"] = decl.get("sensibilite_generalisation", {})
	_monde.ajouter(colon, "colon", colon.position)
	_colons.append(colon)
	var pos: Array = decl.get("position", [0.0, 0.0, 0.0])
	_noeuds[colon.id] = _dessiner_carre(nom, pos)
	_barres[colon.id] = _dessiner_barre(Color(1.0, 0.6, 0.2))
	_marqueurs_attache[colon.id] = _dessiner_marqueur_attache()
	_comptes_attaches[colon.id] = colon.proprietes.attaches.size()

# Ne fait que DECLENCHER (CLAUDE.md, Regle d'etat) -- _ajouter_chose et
# BancCommun.resoudre_chantier sont deja des fonctions testees ailleurs,
# rien de neuf a calculer ici. Calque sur banc_feu.gd:_unhandled_input.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_compteur_feu += 1
		var pos := get_global_mouse_position()
		var id := "%s%d" % [ID_PREFIXE_FEU, _compteur_feu]
		_ajouter_chose(id, "feu_ouvrage", [pos.x, pos.y, 0.0])
		# OPTION B (tranchee par Yael) : "feu_ouvrage" porte deja
		# notre_ouvrage: true en donnee (data/banc_lien_personnel.json:types)
		# -- voie 1, nouveau type LOCAL a ce banc, jamais une mutation
		# post-fabrication. Consequence voulue : le premier colon qui resout
		# "eteindre" sur ce feu declenche Agir.choisir/
		# _appliquer_actes_liants (voir agir.gd, "ACTES LIANTS"), qui pose
		# LUI-MEME un lien personnel colon -> feu_N, exactement comme pour
		# batisse_0 -- N sources d'evenements liants simultanees, pas une
		# seule.
		# _monde.par_id(id) est structurellement sur cet id : _ajouter_chose,
		# juste au-dessus, vient de l'enregistrer dans _monde (compteur_feu
		# monotone, jamais de collision avec feu_proche_0/batisse_0) -- si
		# cette garantie tombait un jour, par_id alarme deja lui-meme
		# (push_error) avant de rendre null, jamais un defaut silencieux.
		BancCommun.resoudre_chantier(_monde.par_id(id).chose.proprietes, _patron)

func _process(delta: float) -> void:
	_temps_ecoule += delta
	var objets := BancCommun.objets_de(_monde)
	var enflammees := Propagation.avancer(objets, _menaces, _exposition, delta, _patron)
	for id in enflammees:
		_noeuds[id].color = _couleur_de("feu_ouvrage")
	var agents := BancCommun.agents_rythme(objets)
	var eteints := Extinction.avancer(objets, agents, delta, _transformations)
	BancCommun.marquer_eteints(eteints, _noeuds, _monde, _couleur_de("cendre"), _temps_ecoule)
	var consumes := Depense.avancer(objets, delta, _seuils_combustible)
	for id in consumes:
		# Pas de teinte "cendre_consumee" dediee dans data/banc_lien_personnel.json
		# (portee volontairement limitee, voir en-tete) -- reutilise "cendre",
		# meme resultat visuel pour le joueur, juste sans la nuance de banc_p1.
		_noeuds[id].color = _couleur_de("cendre")
		print("t=%.1f %s consume (plus de combustible)" % [_temps_ecoule, id])
	for colon in _colons:
		var g := agir_et_deplacer(
			colon, _monde, _catalogue_canaux, _menaces, _profils_saillance,
			_catalogue_deformations, _catalogue_actions, _catalogue_actes_liants, _catalogue_liens,
			_jugements, _orientations, _transformations, _engagements, delta, _catalogue_attaches_par_trait,
		)
		LienPersonnel.avancer(colon, delta, _catalogue_liens)
		_logger_decision(colon, g)
		if g.decision != null:
			var noeud: ColorRect = _noeuds[colon.id]
			noeud.position = Vector2(colon.position.x, colon.position.y) - noeud.size / 2.0
		var force := LienPersonnel.force(colon, ID_BATISSE, _catalogue_liens)
		_redessiner_barre(colon.id, force)
		_mettre_a_jour_marqueur_attache(colon)

# Log console a CHAQUE CHANGEMENT de decision (jamais a chaque tick) --
# meme patron que banc_p1.gd:_faire_agir_colon/banc_charge.gd:_process
# (action_actuelle compare a colon.action_precedente, deja pose par
# BancCommun.fabriquer_colon). Ce banc n'a pas de branche fuite
# (catalogue_actions local ne propose jamais de verbe oriente fuite, voir
# en-tete de fichier) : deux issues seulement, contrairement a banc_p1.gd/
# banc_charge.gd qui en ont trois.
func _logger_decision(colon: Dictionary, g: Dictionary) -> void:
	var decision = g.decision
	var action_actuelle: String
	if decision == null:
		action_actuelle = "RIEN"
	else:
		action_actuelle = "%s|%s" % [
			_etiquette_decision(decision),
			BancCommun.verbe_action({"position": g.position_avant}, g.cible, g.chose, _transformations),
		]
	if action_actuelle == colon.action_precedente:
		return
	colon.action_precedente = action_actuelle
	if decision == null:
		print("t=%.1f %s : 0 saillance -> RIEN" % [_temps_ecoule, colon.id])
	else:
		var dist: float = g.position_avant.distance_to(g.cible)
		print("t=%.1f %s : %d saillance(s) -> %s (dist %.0f) -> %s" % [
			_temps_ecoule, colon.id, g.resultats.size(), _etiquette_decision(decision), dist,
			BancCommun.verbe_action({"position": g.position_avant}, g.cible, g.chose, _transformations),
		])

# Duplique banc_p1.gd:_etiquette_decision/banc_charge.gd:_etiquette_decision.
func _etiquette_decision(decision: Dictionary) -> String:
	var chose = decision.get("chose", null)
	if chose is Dictionary:
		return String(chose.get("id", decision.type))
	if chose != null:
		return String(chose)
	return String(decision.type)

# PIPELINE A QUATRE ETAPES, comme banc_p1.gd:decider -- Perception -> Attaches
# + Proximite -> Dominance -> Agir, jamais de jugement.gd ici (aucun abri,
# aucune fuite a demontrer). SEULE difference avec banc_p1.gd:decider :
# catalogue_actes_liants transite jusqu'a Agir.choisir, qui pose lui-meme le
# lien personnel quand le verbe resolu et la propriete de la chose visee
# matchent une entree du catalogue (voir agir.gd, "ACTES LIANTS").
static func decider(
	colon: Dictionary,
	monde,
	catalogue_canaux: Dictionary,
	menaces: Dictionary,
	profils_saillance: Dictionary,
	catalogue_deformations: Dictionary,
	catalogue_actions: Dictionary,
	catalogue_actes_liants: Dictionary,
	catalogue_liens: Dictionary,
	catalogue_attaches_par_trait: Dictionary = {},
) -> Dictionary:
	var perceptions := Perception.percevoir(colon, monde, catalogue_canaux)
	var att := Attaches.evaluer(perceptions, colon, menaces, catalogue_deformations)
	var prox := Proximite.evaluer(perceptions, colon, profils_saillance, catalogue_deformations)
	var attraction := LienPersonnelAttraction.evaluer(colon, monde, catalogue_liens)
	var resultats: Array = att + prox + attraction
	_appliquer_bonus_lien_personnel(resultats, colon, monde, catalogue_liens)
	var visibles := Dominance.visibles(resultats, colon)
	var decision = Agir.choisir(visibles, colon, catalogue_actions, monde, catalogue_actes_liants, catalogue_attaches_par_trait)
	return {"decision": decision, "resultats": resultats, "perceptions": perceptions, "visibles": visibles}

# PHASE 5 etape 3/4 : ajoute, EN PLACE, le bonus de lien personnel a la
# saillance NUE deja calculee par attaches.gd/proximite.gd -- une entree
# sans cle "chose" (origine attache) n'a pas d'identite distincte, rien a
# comparer a une chose liee, donc ignoree (meme garde que
# proximite.gd/attaches.gd:_appliquer_deformation face a une source sans
# correspondance). Composition ADDITIVE, jamais multiplicative -- deux
# SOURCES DE SAILLANCE distinctes (docs/design.md, "DEUX SOURCES DE
# SAILLANCE"), pas un facteur de deformation de l'existant.
static func _appliquer_bonus_lien_personnel(
	resultats: Array,
	colon: Dictionary,
	monde,
	catalogue_liens: Dictionary,
) -> void:
	for entree in resultats:
		if not entree.has("chose"):
			continue
		entree.saillance += LienPersonnelSaillance.bonus(colon, entree.chose, monde, catalogue_liens)

# Enveloppe decider() + la memorisation pour le tick suivant
# (agir.gd:etat_courant) -- meme geste que banc_p1.gd:decider_et_memoriser.
# Ce banc ne demontre pas l'inertie, mais le cablage reste coherent avec les
# autres : _faire_agir_colon-equivalent (_process) appelle CETTE fonction,
# jamais decider() seule.
static func decider_et_memoriser(
	colon: Dictionary,
	monde,
	catalogue_canaux: Dictionary,
	menaces: Dictionary,
	profils_saillance: Dictionary,
	catalogue_deformations: Dictionary,
	catalogue_actions: Dictionary,
	catalogue_actes_liants: Dictionary,
	catalogue_liens: Dictionary,
	catalogue_attaches_par_trait: Dictionary = {},
) -> Dictionary:
	var r := decider(colon, monde, catalogue_canaux, menaces, profils_saillance, catalogue_deformations, catalogue_actions, catalogue_actes_liants, catalogue_liens, catalogue_attaches_par_trait)
	colon.action_en_cours = Agir.etat_courant(r.decision)
	return r

# GESTE COMPLET decision -> mouvement, calque sur banc_p1.gd:agir_et_deplacer --
# meme role : decider_et_memoriser (INCHANGE, signature deja existante,
# exercee telle quelle par test_banc_lien_personnel.gd) + engagement
# (Couplage, avant et apres la decision) + deplacement (BancCommun.bouger_vers),
# mute colon.position EN PLACE. PAS de branche fuite ici (contrairement a
# banc_p1.gd) : ce banc ne propose aucun verbe oriente fuite dans son
# catalogue_actions local (seul "brule" -> ["eteindre"] existe), donc
# orientations/Fuite.direction ne serviraient jamais -- omis plutot que
# cable mort. cible_pour_decision/_selection_par_menace/feu_le_plus_proche
# sont DUPLIQUEES ici (pas descendues dans banc_commun.gd, decision de
# perimetre pour cette correction) : ce banc n'a en pratique aucun colon
# avec attaches (voir data/banc_lien_personnel.json, attaches: [] pour les
# deux), la branche "menace" de cible_pour_decision ne se declenche donc
# jamais aujourd'hui, mais la dupliquer garde ce fichier autonome et pret
# si un futur colon de ce banc portait une attache.
#
# ENGAGEMENT (couplage.gd, meme mecanisme que banc_p1.gd) : ferme la meme
# classe de bug d'oscillation que dans banc_p1 (voir docs/design.md,
# corps interne, entree "engagement") -- utile ici des
# que plusieurs feux (batisse, feu_proche, bois, feu_ouvrage clique) sont
# perceptibles a la fois :
# _avancer_engagement_colon AVANT decider_et_memoriser (etat a jour avant
# que agir.gd:choisir ne lise l'engagement) ; _mettre_a_jour_engagement_colon
# APRES le calcul de "chose" (retire l'engagement si la decision a change
# de cible, pose un nouvel engagement "colon_chantier" des que le colon
# arrive physiquement a portee_travail d'un chantier).
static func agir_et_deplacer(
	colon: Dictionary,
	monde,
	catalogue_canaux: Dictionary,
	menaces: Dictionary,
	profils_saillance: Dictionary,
	catalogue_deformations: Dictionary,
	catalogue_actions: Dictionary,
	catalogue_actes_liants: Dictionary,
	catalogue_liens: Dictionary,
	jugements: Dictionary,
	orientations: Dictionary,
	transformations: Dictionary,
	engagements: Dictionary,
	delta: float,
	catalogue_attaches_par_trait: Dictionary = {},
) -> Dictionary:
	_avancer_engagement_colon(colon, monde, delta, engagements)
	var r := decider_et_memoriser(colon, monde, catalogue_canaux, menaces, profils_saillance, catalogue_deformations, catalogue_actions, catalogue_actes_liants, catalogue_liens, catalogue_attaches_par_trait)
	var decision = r.decision
	var position_avant: Vector3 = colon.position
	var cible: Vector3 = colon.position
	var chose = null
	if decision != null:
		cible = cible_pour_decision(decision, r.perceptions, menaces, colon.position)
		chose = Ciblage.viser(decision, r.perceptions, menaces, jugements, orientations)
		colon.position = BancCommun.bouger_vers(colon.position, cible, colon.proprietes.vitesse, delta)
	_mettre_a_jour_engagement_colon(colon, chose, position_avant, transformations, engagements)
	return {
		"decision": decision, "resultats": r.resultats, "fuite": false,
		"cible": cible, "chose": chose, "position_avant": position_avant,
	}

# Duplique banc_p1.gd:_avancer_engagement_colon (voir la-bas pour le
# rationale complet) -- entite.proprietes.engagement lu FACULTATIVEMENT ici,
# jamais .has()+alarme : un colon de ce banc porte toujours cette cle
# (herite de "entite" via Objet.fabriquer, voir data/types.json), mais
# l'absence resterait un usage legitime.
static func _avancer_engagement_colon(colon: Dictionary, monde, delta: float, engagements: Dictionary) -> void:
	var engagement: Variant = colon.proprietes.get("engagement", null)
	if engagement == null:
		return
	var trouve: Variant = monde.par_id(engagement.get("cible_id", null))
	var cible_actuelle: Variant = trouve.chose if trouve != null else null
	Couplage.avancer(colon, cible_actuelle, delta, engagements)

# Duplique banc_p1.gd:_mettre_a_jour_engagement_colon.
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

# Duplique banc_p1.gd:cible_pour_decision -- attaches.gd ne rend qu'un
# nombre (menace), jamais une position : retrouve OU aller depuis les
# memes perceptions brutes. Voir en-tete de agir_et_deplacer : la branche
# "menace" ne se declenche jamais avec les donnees actuelles de ce banc
# (aucun colon avec attaches), conservee pour autonomie du fichier.
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

# Duplique banc_p1.gd:_selection_par_menace.
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

# Duplique banc_p1.gd:feu_le_plus_proche.
static func feu_le_plus_proche(
	perceptions: Array,
	propriete_attache: String,
	menaces: Dictionary,
	defaut: Vector3,
) -> Vector3:
	return _selection_par_menace(perceptions, propriete_attache, menaces, defaut).position

func _dessiner_carre(type: String, pos: Array) -> ColorRect:
	var carre := ColorRect.new()
	carre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	carre.size = Vector2(24.0, 24.0)
	carre.color = _couleur_de(type)
	carre.position = Vector2(pos[0], pos[1]) - carre.size / 2.0
	add_child(carre)
	return carre

# Marqueur visuel de l'ATTACHE PAR TRAIT (PHASE 5 etape 4/4 piece 2/3,
# scripts/attache_par_trait.gd) -- un petit carre dore, cache par defaut,
# distinct de la barre de LIEN (couleur/forme differentes, meme convention
# que banc_charge.gd -- une deuxieme couleur pour un deuxieme mecanisme,
# jamais reutilisee). Reste visible pour toujours une fois affiche : une
# attache par trait, une fois formee, est IMMUABLE (voir attache_par_trait.gd),
# rien ne doit jamais la faire disparaitre.
const _COULEUR_MARQUEUR_ATTACHE := Color(1.0, 0.85, 0.1)
const _TAILLE_MARQUEUR := 10.0

func _dessiner_marqueur_attache() -> ColorRect:
	var marqueur := ColorRect.new()
	marqueur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marqueur.color = _COULEUR_MARQUEUR_ATTACHE
	marqueur.size = Vector2(_TAILLE_MARQUEUR, _TAILLE_MARQUEUR)
	marqueur.visible = false
	add_child(marqueur)
	return marqueur

# Detecte une attache NOUVELLEMENT formee en observant la mutation de
# colon.proprietes.attaches tick apres tick (le retour d'AttacheParTrait.avancer
# n'est pas expose par Agir.choisir, voir agir.gd "ATTACHE PAR TRAIT" --
# seule la mutation en place est observable depuis ce banc). _comptes_attaches
# retient la TAILLE precedente par colon (jamais son contenu -- seule la
# croissance importe ici) : une croissance affiche le marqueur et repositionne
# la barre de lien pour lui faire de la place ; le marqueur reste ensuite
# repositionne a chaque tick pour suivre le colon qui bouge, jamais recache.
func _mettre_a_jour_marqueur_attache(colon: Dictionary) -> void:
	var nb_attaches: int = colon.proprietes.attaches.size()
	if nb_attaches > _comptes_attaches.get(colon.id, 0):
		_comptes_attaches[colon.id] = nb_attaches
		_marqueurs_attache[colon.id].visible = true
		print("t=%.1f %s : attache par trait formee -> %s" % [
			_temps_ecoule, colon.id, colon.proprietes.attaches[-1].get("propriete", ""),
		])
	if _marqueurs_attache[colon.id].visible:
		var noeud: ColorRect = _noeuds[colon.id]
		_marqueurs_attache[colon.id].position = noeud.position + Vector2(12.0, -12.0 - _TAILLE_MARQUEUR)

func _dessiner_barre(couleur: Color) -> ColorRect:
	var barre := ColorRect.new()
	barre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	barre.color = couleur
	add_child(barre)
	return barre

func _redessiner_barre(id: String, force: float) -> void:
	var noeud: ColorRect = _noeuds[id]
	var barre: ColorRect = _barres[id]
	var fraction: float = clamp(force / _biais_max, 0.0, 1.0) if _biais_max > 0.0 else 0.0
	barre.size = Vector2(LARGEUR_BARRE * fraction, HAUTEUR_BARRE)
	barre.position = noeud.position + Vector2(-LARGEUR_BARRE / 2.0 + 12.0, -12.0)

func _couleur_de(type: String) -> Color:
	var rgb: Array = _couleurs_types.get(type, [1.0, 1.0, 1.0])
	return Color(rgb[0], rgb[1], rgb[2])

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
