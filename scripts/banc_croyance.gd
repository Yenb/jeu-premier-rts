extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_croyance.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1). Chantier « croyance +
# correction -- le colon croit au lieu de savoir » (audit prealable
# audit_perception_croyance_memoire_prealable.md, lignes 1 et 2). PREMIER
# APPELANT REEL de scripts/croyance.gd, livre par ce meme chantier.
#
# CE QUE CE BANC MONTRE, ET QU'AUCUN AUTRE NE MONTRAIT :
#
# 1) LES QUATRE COUCHES DECIDENT SUR UNE COPIE, PLUS SUR LE MONDE. La chaine
#    reelle tourne ici -- Perception.percevoir -> Croyance.filtrer ->
#    Proximite.evaluer -> Dominance.visibles -> Agir.choisir -- et les quatre
#    dernieres ne voient JAMAIS l'objet reel : elles recoivent la copie crue
#    du colon. AUCUN mecanisme du coeur n'a une ligne de changee.
#
# 2) UN COLON AGIT SUR UNE INFORMATION FAUSSE SANS AUCUNE BRANCHE SPECIALE.
#    Le fruit devient toxique ; la croyance « comestible » du colon est
#    perimee ; agir.gd resout « manger » exactement comme avant, parce qu'il
#    ne compare que des noms de propriete et des nombres recus en parametre.
#    La fausse croyance ne coute pas UNE ligne de mecanisme.
#
# 3) LE DOGME. resistance_par_certitude (data/croyances.json) refuse toute
#    correction au-dela d'un seuil de certitude -- et cette certitude ne vient
#    que d'avoir REGARDE souvent. Le colon dogmatique de ce banc ne porte
#    AUCUN etat pose en dur : il regarde dix fois plus souvent que les autres,
#    sa certitude franchit 0.9 vers t≈3 s, et plus rien ne l'atteint. Ce qui
#    le separe des trois autres est UN NOMBRE (docs/design.md, « Les
#    archetypes n'existent pas »).
#
# 4) LA CREDIBILITE DE LA SOURCE, cablee et non inventee : credibilite =
#    LienPersonnel.force(recepteur, emetteur_id, catalogue) -- un autre colon
#    EST une chose, et liens_personnels porte deja une force colon -> chose.
#    Sous data/croyances.json:seuil_bornes_transmission, le cablage ne
#    transmet MEME PAS (le colon isole n'entend rien). Au-dessus, il appelle
#    Croyance.corriger et c'est le MECANISME qui tranche s'il passe ou non.
#
# CE QUE CE BANC NE FAIT PAS, dit plutot que masque :
# - LES COLONS NE BOUGENT PAS. Aucune vitesse, aucun bouger_vers, aucune
#   fuite, aucun ciblage.gd. Le sujet est ce qu'un colon SAIT, jamais ou il
#   va -- et faire marcher les quatre colons vers le fruit les aurait tous
#   mis au contact, donc tous corriges par l'experience directe : il n'y
#   aurait plus rien a transmettre. Le VERBE RESOLU est affiche, c'est lui
#   qui prouve la decision.
# - AUCUN REPAS N'A LIEU. consommer.gd n'est pas appele, le fruit ne se vide
#   jamais : « il mange » se lit dans le verbe resolu (« manger »), pas dans
#   une reserve qui bouge. Un vrai repas est banc_manger.gd, deja ecrit.
# - AUCUNE MEMOIRE SPATIALE ICI. La position rendue par Croyance.filtrer est
#   toujours la position VIVANTE ; un objet qui bougerait serait suivi par
#   telepathie. C'est la ligne 5 de l'audit, un mecanisme DISTINCT
#   (scripts/memoire_spatiale.gd, banc_memoire_navigation.gd) que ce banc ne
#   monte pas : retenir OU etait une chose et recopier CE QU'ELLE EST sont deux
#   questions separees, et les melanger dans un seul banc rendrait illisible ce
#   que chacune apporte.
#
# DEUX CADENCES PAR COLON, et c'est le coeur de la calibration : croyance.gd
# n'a aucune notion de temps propre (observer() n'a pas de delta, meme limite
# qu'epigenetique.gd:poser), donc appeler observer() a chaque image porterait
# la certitude au plafond en sept images et rendrait tout le monde dogmatique
# avant la premiere seconde. La CADENCE vit au cablage -- cadence_observation
# (revenir regarder) et cadence_verification (revenir toucher), toutes deux en
# donnee, par colon. Meme piege deja paye par banc_graisse_accoutumance.gd sur
# Epigenetique.poser.
#
# LE FRUIT TOXIQUE PERD LA CLE « comestible », il ne la met pas a false --
# structurel, pas cosmetique : observer() n'itere que les proprietes PRESENTES
# sur la chose, une cle retiree n'est donc jamais reobservee et la croyance
# perimee SURVIT. Le fruit portant comestible: false, un coup d'oeil suffirait
# a corriger et le banc ne montrerait plus rien.
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge les catalogues et construit,
#   _unhandled_input bascule, _process appelle avancer(...) puis redessine.
# - Fonctions statiques (pures, testables headless, voir
#   scripts/test_banc_croyance.gd) : tout le reste.

const Perception = preload("res://scripts/perception.gd")
const Croyance = preload("res://scripts/croyance.gd")
const Proximite = preload("res://scripts/proximite.gd")
const Dominance = preload("res://scripts/dominance.gd")
const Agir = preload("res://scripts/agir.gd")
const LienPersonnel = preload("res://scripts/lien_personnel.gd")
const Monde = preload("res://scripts/monde.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")

const ECART_CORRECT := "correct"
const ECART_PERIME := "perime"
const ECART_FAUX := "faux"

const TAILLE_COLON := 40.0
const TAILLE_OBJET := 46.0
const TAILLE_POLICE_LABEL := 13
const TAILLE_POLICE_COMPTEUR := 16
const LARGEUR_LIGNE := 2.0

var _config: Dictionary = {}
var _catalogue_canaux: Dictionary = {}
var _catalogue_croyances: Dictionary = {}
var _catalogue_liens: Dictionary = {}
var _profils_saillance: Dictionary = {}
var _catalogue_actions: Dictionary = {}

var _monde := Monde.new()
var _colons: Array = []
var _objets: Array = []
var _temps := 0.0
var _prochaine_trace := 0.0
var _fruit_toxique := false
var _feu_eloigne := false

var _couche_ui: CanvasLayer
var _noeuds: Dictionary = {}
var _labels: Dictionary = {}
var _lignes: Dictionary = {}
var _label_compteur: Label

# Le rendu relit l'etat du DERNIER pas, jamais une valeur recalculee a cote --
# le label ne peut donc pas mentir sur ce que le colon croit (meme discipline
# que banc_menace_combat.gd).
var _dernier_resultat: Dictionary = {}

func _ready() -> void:
	_config = _charger_json("res://data/banc_croyance.json")
	_catalogue_canaux = _charger_json("res://data/canaux.json")
	_catalogue_croyances = _charger_json("res://data/croyances.json")
	_catalogue_liens = _charger_json("res://data/liens_personnels.json")
	_profils_saillance = _charger_json("res://data/profils_saillance.json")
	_catalogue_actions = _charger_json("res://data/types_choses.json")

	_objets = fabriquer_objets(_config)
	_colons = fabriquer_colons(_config)
	_reconstruire_monde()

	_couche_ui = CanvasLayer.new()
	add_child(_couche_ui)
	_creer_rendu()
	_poser_camera()
	print(ligne_bascule(0.0, "fruit", "sain"))
	print(ligne_bascule(0.0, "feu", "proche"))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_fruit_toxique = basculer_fruit(_objets, _config, _fruit_toxique)
			print(ligne_bascule(_temps, "fruit", "toxique" if _fruit_toxique else "sain"))
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_feu_eloigne = basculer_feu(_objets, _config, _feu_eloigne)
			_monde.resynchroniser()
			print(ligne_bascule(_temps, "feu", "hors de portee" if _feu_eloigne else "proche"))
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_T:
		for evenement in transmettre(_colons, _config, _catalogue_croyances, _catalogue_liens):
			print(ligne_evenement(_temps, evenement))

func _process(delta: float) -> void:
	_temps += delta
	var resultat := avancer(
		_colons, _monde, _config, _catalogue_canaux, _catalogue_croyances,
		_profils_saillance, _catalogue_actions, delta, _temps,
	)
	_dernier_resultat = resultat
	for evenement in resultat.evenements:
		print(ligne_evenement(_temps, evenement))
	if _temps >= _prochaine_trace:
		_prochaine_trace = _temps + float(_config.periode_trace_s)
		for etat_colon in resultat.colons:
			print(ligne_etat(_temps, etat_colon))
	_rafraichir_tout()

# ---- Fonctions PURES, testables headless (voir test_banc_croyance.gd) ----

# Les trois objets, CONSTRUITS A LA MAIN. L'id EST la cle de configuration --
# ce banc n'a pas de catalogue de types local (voir data/banc_croyance.json).
# Les proprietes sont DUPLIQUEES (duplicate(true)) : sans quoi la bascule du
# fruit muterait le Dictionary du disque, deja partage avec toute autre
# lecture de ce fichier.
static func fabriquer_objets(config: Dictionary) -> Array:
	var objets: Array = []
	for cle in config.get("objets", {}):
		var decl: Dictionary = config.objets[cle]
		var pos: Array = decl.position
		objets.append({
			"id": String(cle),
			"position": Vector3(pos[0], pos[1], pos[2]),
			"proprietes": decl.get("proprietes", {}).duplicate(true),
		})
	return objets

# Les quatre colons. Tout ce qui est commun vient de config.colon_commun et est
# DUPLIQUE par colon ; seuls la position, les deux cadences et la force du lien
# vers l'emetteur different. « croyances » demarre VIDE : aucune croyance n'est
# posee en dur, elles naissent toutes de la perception vecue (meme precedent
# que lien_personnel.gd, docs/design.md).
#
# Les deux echeances de cadence vivent HORS de proprietes, au meme niveau
# qu'action_en_cours : elles changent a chaque pas, ce n'est pas un fait stable
# de l'objet (docs/design.md, « action_en_cours vit hors de proprietes »).
#
# Le lien personnel est pose par LienPersonnel.poser, jamais par un Dictionary
# recopie -- etat INITIAL de la scene, au meme titre qu'une position ; sa
# naissance par evenement vecu est deja prouvee par banc_lien_personnel.gd.
static func fabriquer_colons(config: Dictionary) -> Array:
	var commun: Dictionary = config.get("colon_commun", {})
	var emetteur: String = String(config.get("emetteur", ""))
	var colons: Array = []
	for nom in config.get("colons", {}):
		var decl: Dictionary = config.colons[nom]
		var pos: Array = decl.position
		var colon: Dictionary = {
			"id": String(nom),
			"position": Vector3(pos[0], pos[1], pos[2]),
			"action_en_cours": {},
			"cadence_observation": float(decl.cadence_observation),
			"cadence_verification": float(decl.cadence_verification),
			"prochaine_observation": 0.0,
			"prochaine_verification": 0.0,
			"proprietes": {
				"forme": commun.forme.duplicate(true),
				"poids_verbes": commun.poids_verbes.duplicate(true),
				"attaches": [],
				"canaux": commun.canaux.duplicate(true),
				"canaux_config": commun.canaux_config.duplicate(true),
				"croyances": {},
				"liens_personnels": {},
			},
		}
		var force: float = float(decl.get("lien_vers_emetteur", 0.0))
		if force > 0.0 and String(nom) != emetteur:
			LienPersonnel.poser(colon, emetteur, force)
		colons.append(colon)
	return colons

static func objet_par_id(objets: Array, id: String) -> Dictionary:
	for objet in objets:
		if String(objet.id) == id:
			return objet
	return {}

# REMPLACE le Dictionary de proprietes en entier plutot que d'ecrire une cle :
# le fruit toxique n'a PAS « comestible » a false, il ne l'a PLUS DU TOUT (voir
# en-tete). Rend le nouvel etat (true = toxique).
static func basculer_fruit(objets: Array, config: Dictionary, toxique_avant: bool) -> bool:
	var fruit := objet_par_id(objets, "fruit")
	if fruit.is_empty():
		return toxique_avant
	var decl: Dictionary = config.get("objets", {}).get("fruit", {})
	var cle := "proprietes" if toxique_avant else "proprietes_alternees"
	fruit["proprietes"] = decl.get(cle, {}).duplicate(true)
	return not toxique_avant

# Deplace le feu entre sa position declaree et sa position alternee (hors de
# portee de vue). MUTE chose.position en place. monde.gd relit la position
# vivante pour la DISTANCE, mais range les choses PAR CASE : un objet deplace
# ici doit etre re-range, sans quoi il reste trouvable a son ancienne place.
# L'appelant s'en charge -- cette fonction ne voit pas le monde. Rend le nouvel
# etat (true = eloigne).
static func basculer_feu(objets: Array, config: Dictionary, eloigne_avant: bool) -> bool:
	var feu := objet_par_id(objets, "feu")
	if feu.is_empty():
		return eloigne_avant
	var decl: Dictionary = config.get("objets", {}).get("feu", {})
	var pos: Array = decl.position if eloigne_avant else decl.position_alternee
	feu["position"] = Vector3(pos[0], pos[1], pos[2])
	return not eloigne_avant

# ---- Lectures pures d'une croyance (jamais une regle recopiee) ----

static func valeur_crue(colon: Dictionary, chose_id: String, propriete: String) -> Variant:
	return colon.proprietes.croyances.get(chose_id, {}).get(propriete, {}).get("valeur", null)

static func certitude_crue(colon: Dictionary, chose_id: String, propriete: String) -> float:
	return colon.proprietes.croyances.get(chose_id, {}).get(propriete, {}).get("certitude", 0.0)

# Aplatit le registre de croyances en un ensemble de cles « chose/propriete »,
# pour DIFFERENCE avant/apres. C'est ainsi que ce fichier detecte une croyance
# neuve ou oubliee : en comparant deux etats, JAMAIS en recopiant la loi de
# croyance.gd (le plancher de suppression, le gain, la resistance ne sont
# ecrits nulle part ici).
static func instantane(colon: Dictionary) -> Dictionary:
	var plat: Dictionary = {}
	var croyances: Dictionary = colon.proprietes.croyances
	for chose_id in croyances:
		for propriete in croyances[chose_id]:
			plat["%s/%s" % [chose_id, propriete]] = croyances[chose_id][propriete].valeur
	return plat

# ---- Les trois gestes du cablage ----

static func observer_si_cadence(
	colon: Dictionary,
	perceptions: Array,
	catalogue: Dictionary,
	temps: float,
) -> Array:
	if temps < float(colon.prochaine_observation):
		return []
	colon["prochaine_observation"] = temps + float(colon.cadence_observation)
	var avant := instantane(colon)
	Croyance.observer(colon, perceptions, catalogue)
	var evenements: Array = []
	for cle in instantane(colon):
		if not avant.has(cle):
			var morceaux: PackedStringArray = cle.split("/")
			evenements.append({
				"colon": String(colon.id),
				"genre": "observe",
				"chose_id": morceaux[0],
				"propriete": morceaux[1],
				"valeur": valeur_crue(colon, morceaux[0], morceaux[1]),
				"certitude": certitude_crue(colon, morceaux[0], morceaux[1]),
			})
	return evenements

# LA VERIFICATION PAR CONTACT. credibilite 1.0 -- l'experience directe, la
# seule source qui ne passe par personne. La liste des proprietes verifiables
# est PLUS LARGE que data/croyances.json:proprietes_observables : on ne voit
# pas qu'un fruit est toxique, on l'apprend en y goutant.
#
# Une propriete ABSENTE de la chose reelle vaut false -- c'est la valeur
# verifiee, pas un defaut silencieux : « j'ai gouté, ce n'est pas comestible ».
#
# NE TRACE QUE LES CHANGEMENTS DE VALEUR. Une verification qui confirme ce que
# le colon croyait deja ne dit rien de neuf, et une verification refusee par le
# dogme se voit deja sur le compteur de certitude -- la transmission, elle,
# trace tout (voir transmettre).
static func verifier_si_cadence(
	colon: Dictionary,
	perceptions: Array,
	config: Dictionary,
	catalogue: Dictionary,
	temps: float,
) -> Array:
	if temps < float(colon.prochaine_verification):
		return []
	colon["prochaine_verification"] = temps + float(colon.cadence_verification)
	var portee: float = float(config.portee_contact)
	var evenements: Array = []
	for entree in perceptions:
		if float(entree.distance) > portee:
			continue
		var chose: Dictionary = entree.chose
		for propriete in config.get("proprietes_verifiables_au_contact", []):
			var nom := String(propriete)
			var reelle: Variant = chose.proprietes.get(nom, false)
			var avant: Variant = valeur_crue(colon, String(chose.id), nom)
			Croyance.corriger(colon, String(chose.id), nom, reelle, 1.0, catalogue)
			var apres: Variant = valeur_crue(colon, String(chose.id), nom)
			if apres == avant:
				continue
			evenements.append({
				"colon": String(colon.id),
				"genre": "verifie",
				"chose_id": String(chose.id),
				"propriete": nom,
				"valeur": apres,
				"certitude": certitude_crue(colon, String(chose.id), nom),
				"credibilite": 1.0,
			})
	return evenements

# LA TRANSMISSION. L'emetteur (config.emetteur) verse TOUTES ses croyances aux
# autres colons a portee. La credibilite n'est pas inventee : c'est la force du
# LIEN PERSONNEL du RECEVEUR vers l'emetteur (lien_personnel.gd) -- un autre
# colon est une chose comme une autre, il a donc deja une place dans
# liens_personnels.
#
# DEUX REFUS DISTINCTS, a ne jamais confondre :
# - sous data/croyances.json:seuil_bornes_transmission, le CABLAGE renonce : il
#   n'appelle meme pas corriger(). « Je ne t'ecoute pas. »
# - au-dela, il appelle, et c'est le MECANISME qui refuse si la certitude du
#   receveur a franchi resistance_par_certitude. « Je t'ecoute, mais je sais
#   mieux. » Detecte ici par DIFFERENCE d'etat (rien n'a bouge), jamais en
#   recopiant le seuil.
static func transmettre(
	colons: Array,
	config: Dictionary,
	catalogue_croyances: Dictionary,
	catalogue_liens: Dictionary,
) -> Array:
	var nom_emetteur := String(config.get("emetteur", ""))
	var emetteur: Dictionary = {}
	for colon in colons:
		if String(colon.id) == nom_emetteur:
			emetteur = colon
	if emetteur.is_empty():
		return []
	var seuil: float = float(catalogue_croyances.get("seuil_bornes_transmission", 0.0))
	var portee: float = float(config.portee_transmission)
	var evenements: Array = []
	for colon in colons:
		if String(colon.id) == nom_emetteur:
			continue
		if emetteur.position.distance_to(colon.position) > portee:
			continue
		var credibilite: float = LienPersonnel.force(colon, nom_emetteur, catalogue_liens)
		if credibilite < seuil:
			evenements.append({
				"colon": String(colon.id),
				"genre": "sourd",
				"chose_id": nom_emetteur,
				"propriete": "",
				"valeur": null,
				"certitude": 0.0,
				"credibilite": credibilite,
			})
			continue
		var croyances_emetteur: Dictionary = emetteur.proprietes.croyances
		for chose_id in croyances_emetteur:
			for propriete in croyances_emetteur[chose_id]:
				var transmise: Variant = croyances_emetteur[chose_id][propriete].valeur
				var avant_valeur: Variant = valeur_crue(colon, String(chose_id), String(propriete))
				var avant_certitude: float = certitude_crue(colon, String(chose_id), String(propriete))
				Croyance.corriger(colon, String(chose_id), String(propriete), transmise, credibilite, catalogue_croyances)
				var apres_certitude: float = certitude_crue(colon, String(chose_id), String(propriete))
				var inchange: bool = (
					apres_certitude == avant_certitude
					and valeur_crue(colon, String(chose_id), String(propriete)) == avant_valeur
				)
				evenements.append({
					"colon": String(colon.id),
					"genre": "dogme" if inchange else "recoit",
					"chose_id": String(chose_id),
					"propriete": String(propriete),
					"valeur": transmise,
					"certitude": apres_certitude,
					"credibilite": credibilite,
				})
	return evenements

# LES QUATRE COUCHES, sur la COPIE et jamais sur le monde. Croyance.filtrer
# s'intercale entre la couche 1 et la couche 2 ; les quatre suivantes ne
# savent pas qu'elles lisent une copie.
static func decider(
	colon: Dictionary,
	perceptions: Array,
	monde,
	catalogue_croyances: Dictionary,
	profils_saillance: Dictionary,
	catalogue_actions: Dictionary,
) -> Dictionary:
	var crues := Croyance.filtrer(colon, perceptions, catalogue_croyances)
	var resultats := Proximite.evaluer(crues, colon, profils_saillance)
	var visibles := Dominance.visibles(resultats, colon)
	var decision = Agir.choisir(visibles, colon, catalogue_actions, monde)
	colon.action_en_cours = Agir.etat_courant(decision)
	return {"crues": crues, "resultats": resultats, "visibles": visibles, "decision": decision}

# L'ECART entre ce que le colon croit et ce que le monde EST -- lecture pure,
# jamais une regle. Trois etats, dans cet ordre de priorite :
# - FAUX : au moins une valeur crue contredit la valeur reelle. Le colon se
#   trompe, et il agira dessus.
# - PERIME : rien ne contredit, mais au moins une croyance porte sur une chose
#   qu'il ne percoit plus. Il se souvient, il ne verifie plus.
# - CORRECT : tout ce qu'il croit est vrai et actuellement percu.
# Une propriete absente du monde vaut false, exactement comme a la
# verification -- « je crois qu'il est comestible » contre une chose qui ne
# porte plus la cle est bien une contradiction, pas une donnee manquante.
static func ecart_croyance(colon: Dictionary, monde, ids_percus: Dictionary) -> String:
	var croyances: Dictionary = colon.proprietes.croyances
	var perime := false
	for chose_id in croyances:
		var wrapper = monde.par_id(chose_id)
		if wrapper == null:
			perime = true
			continue
		if not ids_percus.has(chose_id):
			perime = true
		var reelles: Dictionary = wrapper.chose.proprietes
		for propriete in croyances[chose_id]:
			if croyances[chose_id][propriete].valeur != reelles.get(propriete, false):
				return ECART_FAUX
	return ECART_PERIME if perime else ECART_CORRECT

# UN PAS COMPLET, pour tous les colons. ORDRE FIXE ET ASSUME :
#   percevoir -> observer (a la cadence) -> verifier au contact (a la cadence)
#   -> decider sur la copie -> oublier.
# L'oubli vient EN DERNIER : une croyance formee ce pas-ci ne doit pas perdre
# sa certitude avant d'avoir servi une seule fois a decider.
#
# Rend { colons: [ { id, ecart, verbe, cible_id, croyances_lisibles,
# nb_croyances } ], evenements: [...] } -- tout ce que le rendu et les traces
# affichent, jamais recalcule ailleurs.
static func avancer(
	colons: Array,
	monde,
	config: Dictionary,
	catalogue_canaux: Dictionary,
	catalogue_croyances: Dictionary,
	profils_saillance: Dictionary,
	catalogue_actions: Dictionary,
	delta: float,
	temps: float,
) -> Dictionary:
	var evenements: Array = []
	var etats: Array = []
	for colon in colons:
		var perceptions := Perception.percevoir(colon, monde, catalogue_canaux)
		evenements.append_array(observer_si_cadence(colon, perceptions, catalogue_croyances, temps))
		evenements.append_array(verifier_si_cadence(colon, perceptions, config, catalogue_croyances, temps))
		var r := decider(colon, perceptions, monde, catalogue_croyances, profils_saillance, catalogue_actions)
		var ids_percus: Dictionary = {}
		for entree in perceptions:
			ids_percus[String(entree.chose.id)] = true
		var avant := instantane(colon)
		Croyance.avancer(colon, delta, catalogue_croyances)
		var apres := instantane(colon)
		for cle in avant:
			if not apres.has(cle):
				var morceaux: PackedStringArray = cle.split("/")
				evenements.append({
					"colon": String(colon.id),
					"genre": "oublie",
					"chose_id": morceaux[0],
					"propriete": morceaux[1],
					"valeur": avant[cle],
					"certitude": 0.0,
				})
		var decision = r.decision
		etats.append({
			"id": String(colon.id),
			"ecart": ecart_croyance(colon, monde, ids_percus),
			"verbe": String(decision.get("action", "")) if decision != null else "",
			"cible_id": String(decision.chose.id) if decision != null and decision.has("chose") else "",
			"nb_croyances": apres.size(),
			"croyances": colon.proprietes.croyances,
		})
	return {"colons": etats, "evenements": evenements}

# ---- Textes (purs) ----

static func _mot(valeur: Variant) -> String:
	if valeur is bool:
		return "oui" if valeur else "non"
	return str(valeur)

static func ligne_bascule(t: float, cible: String, etat: String) -> String:
	return "t=%.1fs BASCULE : %s -> %s" % [t, cible, etat]

static func ligne_evenement(t: float, ev: Dictionary) -> String:
	match String(ev.genre):
		"observe":
			return "t=%.1fs %s OBSERVE %s.%s = %s (certitude %.2f)" % [
				t, ev.colon, ev.chose_id, ev.propriete, _mot(ev.valeur), ev.certitude,
			]
		"verifie":
			return "t=%.1fs %s VERIFIE AU CONTACT %s.%s -> %s (credibilite 1.00, certitude %.2f)" % [
				t, ev.colon, ev.chose_id, ev.propriete, _mot(ev.valeur), ev.certitude,
			]
		"recoit":
			return "t=%.1fs %s RECOIT %s.%s = %s (credibilite %.2f, certitude %.2f)" % [
				t, ev.colon, ev.chose_id, ev.propriete, _mot(ev.valeur), ev.credibilite, ev.certitude,
			]
		"dogme":
			return "t=%.1fs %s DOGME : refuse %s.%s = %s (certitude %.2f inchangee)" % [
				t, ev.colon, ev.chose_id, ev.propriete, _mot(ev.valeur), ev.certitude,
			]
		"sourd":
			return "t=%.1fs %s N'ECOUTE PAS %s (credibilite %.2f sous le seuil de transmission)" % [
				t, ev.colon, ev.chose_id, ev.credibilite,
			]
		"oublie":
			return "t=%.1fs %s OUBLIE %s.%s (croyait : %s)" % [
				t, ev.colon, ev.chose_id, ev.propriete, _mot(ev.valeur),
			]
	return "t=%.1fs %s ?" % [t, ev.colon]

static func ligne_etat(t: float, etat_colon: Dictionary) -> String:
	return "t=%.1fs %s | ecart=%s | %d croyance(s) | verbe=%s -> %s" % [
		t, etat_colon.id, etat_colon.ecart, etat_colon.nb_croyances,
		String(etat_colon.verbe) if String(etat_colon.verbe) != "" else "(rien)",
		String(etat_colon.cible_id) if String(etat_colon.cible_id) != "" else "(rien)",
	]

static func texte_colon(etat_colon: Dictionary, colon: Dictionary) -> String:
	var lignes: Array = ["%s  [%s]" % [etat_colon.id, etat_colon.ecart]]
	lignes.append("regarde /%.1fs  touche /%.1fs" % [colon.cadence_observation, colon.cadence_verification])
	var croyances: Dictionary = etat_colon.croyances
	if croyances.is_empty():
		lignes.append("(aucune croyance)")
	for chose_id in croyances:
		for propriete in croyances[chose_id]:
			lignes.append("%s.%s = %s (%.2f)" % [
				chose_id, propriete,
				_mot(croyances[chose_id][propriete].valeur),
				float(croyances[chose_id][propriete].certitude),
			])
	lignes.append("verbe : %s -> %s" % [
		String(etat_colon.verbe) if String(etat_colon.verbe) != "" else "(rien)",
		String(etat_colon.cible_id) if String(etat_colon.cible_id) != "" else "(rien)",
	])
	return "\n".join(lignes)

static func texte_objet(objet: Dictionary) -> String:
	var lignes: Array = [String(objet.id) + "  (reel)"]
	var vide := true
	for propriete in objet.proprietes:
		if String(propriete) == "profil_saillance":
			continue
		vide = false
		lignes.append("%s = %s" % [propriete, _mot(objet.proprietes[propriete])])
	if vide:
		lignes.append("(aucune propriete)")
	return "\n".join(lignes)

static func texte_compteur(resultat: Dictionary, fruit_toxique: bool, feu_eloigne: bool) -> String:
	var faux := 0
	var perimes := 0
	for etat_colon in resultat.get("colons", []):
		if String(etat_colon.ecart) == ECART_FAUX:
			faux += 1
		elif String(etat_colon.ecart) == ECART_PERIME:
			perimes += 1
	return ("fruit %s | feu %s | %d colon(s) dans le faux, %d perime(s)\n" +
		"clic gauche : fruit sain/toxique   clic droit : feu proche/loin   T : transmission") % [
		"TOXIQUE" if fruit_toxique else "sain",
		"HORS DE PORTEE" if feu_eloigne else "proche",
		faux, perimes,
	]

# ---- Rendu (impur, Node) -- aucune decision, seulement couleurs et positions.

func _reconstruire_monde() -> void:
	_monde = BancCommun.monde_depuis([
		{"choses": _objets, "type": "objet"},
		{"choses": _colons, "type": "colon"},
	])

func _couleur(cle: String, defaut: Array) -> Color:
	var rgb: Array = _config.get("couleurs", {}).get(cle, defaut)
	return Color(rgb[0], rgb[1], rgb[2])

func _creer_rendu() -> void:
	for objet in _objets:
		_noeuds[objet.id] = _creer_carre(objet.position, TAILLE_OBJET, _couleur(String(objet.id), [0.6, 0.6, 0.6]))
		_labels[objet.id] = _creer_label()
	for colon in _colons:
		_noeuds[colon.id] = _creer_carre(colon.position, TAILLE_COLON, _couleur("colon_correct", [0.3, 0.75, 0.35]))
		_labels[colon.id] = _creer_label()
		var ligne := Line2D.new()
		ligne.width = LARGEUR_LIGNE
		ligne.default_color = _couleur("cible", [0.7, 0.7, 0.7])
		add_child(ligne)
		_lignes[colon.id] = ligne
	_label_compteur = Label.new()
	_label_compteur.add_theme_font_size_override("font_size", TAILLE_POLICE_COMPTEUR)
	_label_compteur.position = Vector2(10.0, 10.0)
	_couche_ui.add_child(_label_compteur)

func _creer_label() -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", TAILLE_POLICE_LABEL)
	add_child(label)
	return label

func _creer_carre(position: Vector3, taille: float, couleur: Color) -> ColorRect:
	var carre := ColorRect.new()
	carre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	carre.size = Vector2(taille, taille)
	carre.color = couleur
	carre.position = Vector2(position.x, position.y) - carre.size / 2.0
	add_child(carre)
	return carre

func _couleur_ecart(ecart: String) -> Color:
	if ecart == ECART_FAUX:
		return _couleur("colon_faux", [0.85, 0.2, 0.2])
	if ecart == ECART_PERIME:
		return _couleur("colon_perime", [0.9, 0.6, 0.15])
	return _couleur("colon_correct", [0.3, 0.75, 0.35])

func _rafraichir_tout() -> void:
	for objet in _objets:
		var noeud: ColorRect = _noeuds[objet.id]
		noeud.position = Vector2(objet.position.x, objet.position.y) - noeud.size / 2.0
		_labels[objet.id].position = noeud.position + Vector2(TAILLE_OBJET + 8.0, 0.0)
		_labels[objet.id].text = texte_objet(objet)
	if _dernier_resultat.is_empty():
		return
	for etat_colon in _dernier_resultat.colons:
		var colon := _colon_par_id(String(etat_colon.id))
		if colon.is_empty():
			continue
		var noeud: ColorRect = _noeuds[colon.id]
		noeud.color = _couleur_ecart(String(etat_colon.ecart))
		_labels[colon.id].position = noeud.position + Vector2(-TAILLE_COLON, TAILLE_COLON + 6.0)
		_labels[colon.id].text = texte_colon(etat_colon, colon)
		_tracer_ligne(colon, etat_colon)
	_label_compteur.text = texte_compteur(_dernier_resultat, _fruit_toxique, _feu_eloigne)

# UNE ligne par colon, vers la chose que sa DECISION vise -- donc vers ce qu'il
# CROIT saillant, jamais vers ce que le monde dit. Aucune ligne quand il ne
# decide rien.
func _tracer_ligne(colon: Dictionary, etat_colon: Dictionary) -> void:
	var ligne: Line2D = _lignes[colon.id]
	var cible_id := String(etat_colon.cible_id)
	if cible_id == "" or String(etat_colon.verbe) == "":
		ligne.points = PackedVector2Array()
		return
	var wrapper = _monde.par_id(cible_id)
	if wrapper == null:
		ligne.points = PackedVector2Array()
		return
	var pos: Vector3 = wrapper.chose.position
	ligne.default_color = _couleur_ecart(String(etat_colon.ecart))
	ligne.points = PackedVector2Array([
		Vector2(colon.position.x, colon.position.y), Vector2(pos.x, pos.y),
	])

func _colon_par_id(id: String) -> Dictionary:
	for colon in _colons:
		if String(colon.id) == id:
			return colon
	return {}

func _poser_camera() -> void:
	var decl: Dictionary = _config.get("camera", {})
	var pos: Array = decl.get("position", [0.0, 0.0, 0.0])
	var camera := Camera2D.new()
	camera.position = Vector2(pos[0], pos[1])
	camera.zoom = Vector2(decl.get("zoom", 1.0), decl.get("zoom", 1.0))
	camera.enabled = true
	add_child(camera)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
