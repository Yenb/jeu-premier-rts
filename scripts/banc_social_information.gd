extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_social_information.tscn, PAS la
# scene principale -- run/main_scene reste banc_p1). Chantier « circulation de
# l'information » (Social et relations, lignes 4 et 6). Compose CINQ mecanismes
# deja fermes, TOUS APPELES TELS QUELS : perception.gd, croyance.gd,
# lien_personnel.gd, epigenetique.gd, portee.gd (+ monde.gd). AUCUN MECANISME DU
# COEUR TOUCHE, AUCUN MECANISME NEUF ECRIT -- verrouille NEGATIVEMENT par
# scripts/test_banc_social_information.gd, qui relit les cinq fichiers sur le
# disque et exige qu'aucun nom de contenu de ce banc n'y apparaisse.
#
# DEUX LIGNES, UN SEUL BANC, parce qu'elles sont LA MEME QUESTION (CLAUDE.md,
# « UN GAMEPLAY EST UNE COMPOSITION, JAMAIS UNE PIECE ») : qu'est-ce qui circule
# d'un colon a un autre quand ils se voient. La ligne 4 fait circuler un FAIT
# (une reputation -- Croyance.corriger, attenue par la credibilite d'un lien
# personnel) ; la ligne 6 fait circuler un SAVOIR-FAIRE (une marque
# epigenetique -- Epigenetique.poser, borne par la fidelite). Deux mecanismes,
# deux temporalites, UN SEUL geste de cablage : percevoir quelqu'un a portee,
# puis ecrire chez lui.
#
# CE QU'ON DOIT VOIR. Cinq colons posés. En haut a gauche un VOLEUR (rouge) et
# le TEMOIN (bleu) qui le voit ; a droite le LOINTAIN (gris), hors du cercle de
# propagation. En bas le MAITRE forgeron (or) et le NOVICE (vert).
#   1. LA REPUTATION SE PROPAGE. Le voleur porte 'reputation_voleur' ; le temoin
#      le PERCOIT, donc l'observe (Croyance.observer) et sa certitude monte. A la
#      cadence de propagation, il verse cette croyance a tout colon A PORTEE
#      (Portee.en_portee) -- maitre et novice la recoivent, le lointain jamais.
#   2. LA PAROLE AFFAIBLIT CE QU'ELLE PORTE. Le temoin a vu ; les autres ont
#      entendu. Leur certitude vaut gain_par_echec x credibilite, ou credibilite
#      = force du lien x propagation_par_temoin -- toujours SOUS celle du temoin,
#      et differente pour chacun parce que les liens different. Personne n'a
#      ecrit cette regle ici : c'est croyance.gd qui ecrase la certitude.
#   3. CLIC DROIT : le lointain se rapproche. Il entre dans le cercle, il recoit.
#      Il repart, il n'est plus alimente et oublie a la saison suivante.
#   4. CLIC GAUCHE : le vol cesse. La cle disparait du voleur, plus personne ne
#      la reobserve, et A CHAQUE SAISON la certitude perd 0.20 D'UN COUP, chez
#      le temoin comme chez ceux qu'il a informes -- jusqu'a ce que croyance.gd
#      RETIRE l'entree sous son plancher. La reputation ne s'efface pas en
#      continu : elle tombe par marches.
#   5. LE NOVICE IMITE. Il percoit le maitre a portee d'imitation, l'ecart de
#      competence depasse le seuil, sa barre orange monte -- et s'arrete net a
#      fidelite x competence du maitre. Celle du maitre ne bouge pas.
#
# ---------------------------------------------------------------------------
# LES QUATRE CONSTATS QUI DECIDENT CE CABLAGE, relus dans le code avant d'ecrire.
#
# (A) LA REPUTATION PASSE PAR LE MEME GESTE QUE LA TRANSMISSION DE SAVOIR, et
#     PAS par charge.gd. Une contagion par canal accumule (charge.gd) somme des
#     causes a portee et bascule un marqueur : elle ne porte NI valeur NI
#     certitude, et ne sait pas de QUI vient l'information. Ici la propagation
#     est PAR PAIRE -- un emetteur nomme, un destinataire nomme, une credibilite
#     propre au couple. C'est exactement Croyance.corriger, deja cable par
#     banc_croyance.gd:transmettre. Ce banc en est le second appelant, et n'en
#     recopie pas la loi : ni le plancher, ni le gain, ni la resistance
#     n'apparaissent dans ce fichier.
# (B) epigenetique.gd:lire N'EXISTE PAS -- verifie dans le fichier avant
#     d'ecrire. La lecture d'un modulateur est un GESTE DE CABLAGE : ce fichier
#     lit lui-meme proprietes.marques_epigenetiques[marque].modulateur, sur
#     l'observe comme sur l'observant, et compare. Patron litteral
#     banc_marche_competence.gd:modulateur_competence.
# (C) epigenetique.gd:poser N'ACCEPTE AUCUNE MAGNITUDE -- le montant vient de
#     catalogue[marque].modulateur_pose et de nulle part ailleurs. « poser avec
#     fidelite x modulateur du maitre » est donc IMPOSSIBLE sans toucher le
#     coeur. La fidelite est cablee en PLAFOND DE POSE : on pose tant que le
#     modulateur de l'imitant reste sous fidelite x modulateur du modele. Patron
#     litteral banc_marche_competence.gd:_poser_une_marque, qui borne deja la
#     POSE et non la seule lecture.
# (D) UNE CADENCE « PAR HEURE » N'EST PAS UNE CADENCE. Le moteur ne connait que
#     des secondes ; secondes_par_heure_simulee est le SEUL facteur de
#     conversion du banc, et les quatre cadences (observation, propagation,
#     imitation, saison) en derivent toutes. Verrouille par test.
# ---------------------------------------------------------------------------
#
# LA SAISON EST UNE CADENCE DE CABLAGE, jamais un taux de plus. croyance.gd:
# avancer n'a aucune notion de saison -- il retire taux_decroissance x delta. Ce
# fichier ne l'appelle donc PAS a chaque image : il accumule une horloge et
# l'appelle UNE FOIS par saison, avec la duree de la saison entiere comme delta.
# Meme geste que les intervalles de pose de banc_marche_competence.gd et
# banc_graisse_accoutumance.gd, applique cette fois a l'oubli. Consequence
# voulue : la certitude tombe PAR MARCHES de 0.20, jamais en pente douce -- c'est
# ce que « la reputation decroit par saison » veut dire, et une decroissance par
# image ne le montrerait pas.
#
# LA COMPETENCE DU MAITRE NE BAISSE PAS, ET CE N'EST PAS UN CAS PARTICULIER.
# Epigenetique.avancer decroit TOUTES les marques de TOUS les colons, chaque
# tick, inconditionnellement (aucune exception n'est cablee ici) : un maitre qui
# ne ferait rien perdrait sa competence en 17.6 s, et « le maitre ne perd rien »
# serait faux tous tests verts. Il l'ENTRETIENT donc -- il exerce son metier,
# voila tout : le cablage repose la marque tant qu'elle est sous son
# plafond_competence declare. Le novice, lui, n'entretient rien ; il n'a que ce
# que l'imitation lui donne.
#
# DEUX BORNES SUR L'IMITATION, ET ELLES NE DISENT PAS LA MEME CHOSE.
# seuil_ecart est un GATE D'ENTREE (« sous cet ecart il n'y a plus rien a
# apprendre de ce modele ») ; fidelite_imitation est un PLAFOND (« on n'apprend
# jamais au-dela de fidelite x le modele »). Sous la calibration reelle du banc
# le plafond mord bien avant le gate, c'est donc lui qu'on voit a l'ecran ; le
# gate d'ecart est exerce par le test sur un cas dedie plutot que laisse a la
# souris.
#
# LE MODELE N'EST PAS NOMME. imiter() ne cherche pas « le maitre » : il prend,
# parmi les colons PERCUS et a portee d'imitation, celui dont le modulateur est
# le plus haut. Un troisieme forgeron plus competent volerait le role sans une
# ligne de code -- et le maitre, qui percoit le novice, ne l'imite jamais parce
# que son ecart est negatif, pas parce qu'un cas particulier l'exclut.
#
# LES COLONS NE SE DEPLACENT PAS et ne decident rien : ce banc monte la couche 1
# (perception.gd) et rien au-dela -- NI proximite.gd, NI dominance.gd, NI
# agir.gd. Choix assume, meme decoupage que banc_marche_competence.gd et
# banc_temps_anticipation.gd : le sujet est ce qui CIRCULE entre deux colons,
# jamais ou ils vont. Croyance.filtrer n'est donc pas appele non plus -- il sert
# a alimenter les couches de decision, qui ne tournent pas ici ; ce que chacun
# SAIT est lu directement sur son registre de croyances et affiche.
#
# COLONS CONSTRUITS A LA MAIN (pas Objet.fabriquer, meme statut que
# banc_croyance.gd/banc_marche_competence.gd/banc_menace_combat.gd) : ni
# composition ni materiau, donc data/types.json n'est pas touche et rien n'est a
# enregistrer dans scripts/test_lint_donnees.gd.
#
# AUCUN NOM DE PROPRIETE, DE MARQUE NI D'IDENTITE EN DUR :
# nom_propriete_reputation et nom_marque_competence arrivent de
# data/banc_social_information.json, et les cinq colons sont trouves PAR ROLE
# DECLARE (sujet_reputation / temoin / imite / entretient_competence), jamais
# par leur id -- c'est ce qui permet au test de faire traverser le meme code par
# un domaine entierement invente.
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge les quatre fichiers de donnees et construit la
#   scene ; _unhandled_input porte les deux bascules et ne calcule jamais rien ;
#   _process appelle avancer(...) et ne fait que lire son resultat ; _draw
#   dessine.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_social_information.gd) : avancer(...) et tout ce qu'elle enchaine.
#   LE TICK N'EST JAMAIS RECONSTITUE DANS LE TEST : il appelle avancer(), la
#   MEME fonction que _process (regle d'etat de CLAUDE.md).

const Perception = preload("res://scripts/perception.gd")
const Croyance = preload("res://scripts/croyance.gd")
const LienPersonnel = preload("res://scripts/lien_personnel.gd")
const Epigenetique = preload("res://scripts/epigenetique.gd")
const Portee = preload("res://scripts/portee.gd")
const Monde = preload("res://scripts/monde.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")

var _config: Dictionary = {}
var _catalogue_canaux: Dictionary = {}
var _catalogue_croyances: Dictionary = {}
var _catalogue_liens: Dictionary = {}
var _catalogue_epigenetique: Dictionary = {}

var _colons: Array = []
var _monde
var _horloges: Dictionary = {}
var _temps := 0.0
var _horloge_trace := 0.0
var _vol := false
var _lointain_eloigne := true

# Ce que le dernier tick a produit -- relu tel quel par l'affichage, jamais
# recalcule a cote (meme discipline que banc_marche_competence.gd:_infos).
var _infos: Dictionary = {}

var _labels: Dictionary = {}
var _label_compteur: Label
var _label_aide: Label

func _ready() -> void:
	_config = _charger_json("res://data/banc_social_information.json")
	_catalogue_canaux = _charger_json("res://data/canaux.json")
	_catalogue_croyances = _charger_json("res://data/croyances.json")
	_catalogue_liens = _charger_json("res://data/liens_personnels.json")
	_catalogue_epigenetique = _charger_json("res://data/epigenetique.json")

	var scene := fabriquer_scene(_config)
	_colons = scene.colons
	_monde = scene.monde
	_horloges = scene.horloges
	_vol = bool(scene.vol)
	_lointain_eloigne = bool(scene.eloigne)

	_construire_rendu()
	print(ligne_pose(_config))

func _unhandled_input(evenement: InputEvent) -> void:
	# Le clic ne fait que basculer un drapeau : aucune decision, aucun calcul.
	if not (evenement is InputEventMouseButton and evenement.pressed):
		return
	if evenement.button_index == MOUSE_BUTTON_LEFT:
		_vol = not _vol
		poser_vol(_colons, _config, _vol)
		print(ligne_bascule_vol(_temps, _vol))
	elif evenement.button_index == MOUSE_BUTTON_RIGHT:
		_lointain_eloigne = basculer_eloigne(_colons, _config, _lointain_eloigne)
		_monde.resynchroniser()
		print(ligne_bascule_eloigne(_temps, _lointain_eloigne))

func _process(delta: float) -> void:
	_temps += delta
	var resultat: Dictionary = avancer(
		_colons, _monde, _config, _catalogue_canaux, _catalogue_croyances,
		_catalogue_liens, _catalogue_epigenetique, delta, _temps, _horloges)
	_infos = resultat.infos
	for evenement in resultat.evenements:
		print(ligne_evenement(_temps, evenement))

	_horloge_trace += delta
	if _horloge_trace >= float(_config.intervalle_trace_s):
		_horloge_trace = 0.0
		for colon in _colons:
			print(ligne_trace(_temps, colon, _infos.get(colon.id, {})))

	_rafraichir()
	queue_redraw()

# ---- Fonctions PURES, testables headless ----

# Les cinq colons. « croyances », « liens_personnels » et
# « marques_epigenetiques » sont STRUCTURELLES pour croyance.gd/
# lien_personnel.gd/epigenetique.gd (leur absence est une alarme, jamais « rien
# de pose ») : posees ici, comme data/types.json:dynamique le fait pour les
# types reels. AUCUNE croyance n'est posee en dur -- elles naissent toutes de la
# perception vecue (meme precedent que banc_croyance.gd, docs/design.md).
#
# Les liens personnels, eux, sont poses par LienPersonnel.poser et jamais par un
# Dictionary recopie : etat INITIAL de la scene, au meme titre qu'une position.
# Leur naissance par evenement vecu est deja prouvee par banc_lien_personnel.gd.
#
# Les quatre echeances de cadence vivent HORS de proprietes, au meme rang
# qu'action_en_cours ailleurs : elles changent a chaque pas, ce n'est pas un fait
# stable de l'objet (docs/design.md, « action_en_cours vit hors de proprietes »).
static func fabriquer_colons(config: Dictionary) -> Array:
	var colons: Array = []
	for decl in config.get("colons", []):
		var pos: Array = decl.position
		var canaux_config: Dictionary = {}
		for nom_canal in config.get("canaux", []):
			canaux_config[String(nom_canal)] = {
				"portee": float(decl.portee_vue), "angle": 360.0,
			}
		var marques: Dictionary = {}
		var depart: float = float(decl.get("modulateur_competence_depart", 0.0))
		if depart > 0.0:
			marques[String(config.nom_marque_competence)] = {
				"modulateur": depart, "age_marque": 0.0,
			}
		var colon: Dictionary = {
			"id": String(decl.id),
			"position": Vector3(float(pos[0]), float(pos[1]), float(pos[2])),
			"prochaine_observation": 0.0,
			"prochaine_propagation": 0.0,
			"prochaine_imitation": 0.0,
			"prochaine_entretien": 0.0,
			"proprietes": {
				"canaux": config.canaux.duplicate(true),
				"canaux_config": canaux_config,
				"croyances": {},
				"liens_personnels": {},
				"marques_epigenetiques": marques,
			},
		}
		for cle in decl.get("liens", {}):
			LienPersonnel.poser(colon, String(cle), float(decl.liens[cle]))
		colons.append(colon)
	return colons

static func horloges_neuves() -> Dictionary:
	return {"horloge_saison": 0.0, "saison": 0}

# LA SCENE ENTIERE, en une fonction STATIQUE -- _ready et le test appellent la
# MEME (regle d'etat de CLAUDE.md) : un test qui reconstruirait la scene a cote
# pourrait deriver de ce que la fenetre montre sans que rien ne rougisse. Rend
# { colons, monde, horloges, vol, eloigne } ; le drapeau de vol de depart vient
# de la donnee, jamais d'une constante de ce fichier.
static func fabriquer_scene(config: Dictionary) -> Dictionary:
	var colons := fabriquer_colons(config)
	var monde = BancCommun.monde_depuis([{"choses": colons, "type": "colon"}])
	var vol := bool(config.get("vol_au_depart", false))
	poser_vol(colons, config, vol)
	return {
		"colons": colons,
		"monde": monde,
		"horloges": horloges_neuves(),
		"vol": vol,
		"eloigne": true,
	}

static func colon_par_id(colons: Array, id: String) -> Dictionary:
	for colon in colons:
		if String(colon.id) == id:
			return colon
	return {}

# LES COLONS SONT TROUVES PAR ROLE DECLARE, jamais par leur id -- c'est ce qui
# rend ce cablage traversable par un domaine invente. Un role absent rend un
# Dictionary vide : point neutre legitime (une scene sans temoin ne propage
# rien), jamais une alarme.
static func colon_par_role(colons: Array, config: Dictionary, role: String) -> Dictionary:
	for decl in config.get("colons", []):
		if bool(decl.get(role, false)):
			return colon_par_id(colons, String(decl.id))
	return {}

static func declaration_de(config: Dictionary, id: String) -> Dictionary:
	for decl in config.get("colons", []):
		if String(decl.id) == id:
			return decl
	return {}

# ---- LES QUATRE CADENCES, toutes derivees de la MEME echelle (constat D) ----

static func secondes_par_heure(config: Dictionary) -> float:
	return float(config.secondes_par_heure_simulee)

static func intervalle_observation_s(config: Dictionary) -> float:
	return float(config.cadence_observation_h) * secondes_par_heure(config)

static func intervalle_propagation_s(config: Dictionary) -> float:
	return float(config.heures_par_propagation) * secondes_par_heure(config)

# « prob_par_observation_h » est un NOMBRE D'OCCASIONS PAR HEURE : l'intervalle
# en secondes en est l'INVERSE, mis a l'echelle. Une valeur nulle ou negative
# rendrait un intervalle infini -- rendu 0.0, c'est-a-dire « a chaque tick »,
# point neutre legitime plutot qu'une division par zero.
static func intervalle_imitation_s(config: Dictionary) -> float:
	var par_heure: float = float(config.prob_par_observation_h)
	if par_heure <= 0.0:
		return 0.0
	return secondes_par_heure(config) / par_heure

static func duree_saison_s(config: Dictionary) -> float:
	return float(config.heures_par_saison) * secondes_par_heure(config)

# ---- Les deux portees, en CASES converties en unites ----

static func portee_propagation(config: Dictionary) -> float:
	return float(config.portee_propagation_cases) * float(config.unites_par_case)

static func portee_imitation(config: Dictionary) -> float:
	return float(config.portee_imitation_cases) * float(config.unites_par_case)

# ---- Bascules (pures) ----

# LE VOL POSE ET RETIRE LA CLE, il ne la met jamais a false -- structurel, pas
# cosmetique (patron banc_croyance.gd:basculer_fruit) : croyance.gd:observer
# n'itere que les proprietes PRESENTES sur la chose percue, une cle retiree
# n'est donc jamais reobservee et la reputation SURVIT a la fin du vol, le temps
# que les saisons l'effacent. Une cle a false serait reobservee au premier coup
# d'oeil et la reputation s'effacerait instantanement.
static func poser_vol(colons: Array, config: Dictionary, actif: bool) -> void:
	var sujet := colon_par_role(colons, config, "sujet_reputation")
	if sujet.is_empty():
		return
	var nom := String(config.nom_propriete_reputation)
	if actif:
		sujet.proprietes[nom] = true
	else:
		sujet.proprietes.erase(nom)

# Deplace le colon qui declare une position alternee, entre sa position declaree
# et celle-la. MUTE chose.position en place : monde.gd relit toujours la
# position vivante, il n'y a rien a re-enregistrer (patron
# banc_croyance.gd:basculer_feu). Rend le nouvel etat (true = eloigne).
#
# LE SENS EST L'INVERSE DE banc_croyance.gd:basculer_feu, et c'est voulu : ici
# la position DECLAREE est celle du depart, donc l'ELOIGNEE (le banc lance doit
# montrer d'abord qu'on ne recoit rien hors de portee), et « position_alternee »
# est la position rapprochee. Recopier la condition du patron sans regarder quel
# etat est le depart inverse la bascule -- defaut trouve au test, pas a l'ecran.
static func basculer_eloigne(colons: Array, config: Dictionary, eloigne_avant: bool) -> bool:
	for decl in config.get("colons", []):
		if not decl.has("position_alternee"):
			continue
		var colon := colon_par_id(colons, String(decl.id))
		if colon.is_empty():
			continue
		var pos: Array = decl.position_alternee if eloigne_avant else decl.position
		colon["position"] = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
		return not eloigne_avant
	return eloigne_avant

# ---- Lectures pures (jamais une regle recopiee) ----

static func valeur_crue(colon: Dictionary, chose_id: String, propriete: String) -> Variant:
	return colon.proprietes.croyances.get(chose_id, {}).get(propriete, {}).get("valeur", null)

static func certitude_crue(colon: Dictionary, chose_id: String, propriete: String) -> float:
	return float(colon.proprietes.croyances.get(chose_id, {}).get(propriete, {}).get("certitude", 0.0))

# LE GESTE DE CABLAGE DU CONSTAT (B) : epigenetique.gd:lire n'existe pas, la
# lecture d'un modulateur se fait ici. Marque absente -- jamais posee, ou RETIREE
# par epigenetique.gd sous son plancher_suppression -- : 0.0, point neutre
# legitime, jamais une alarme.
static func modulateur(colon: Dictionary, nom_marque: String) -> float:
	return float(colon.proprietes.get("marques_epigenetiques", {}).get(nom_marque, {}).get("modulateur", 0.0))

# Aplatit le registre de croyances en cles « chose/propriete », pour DIFFERENCE
# avant/apres -- c'est ainsi que ce fichier detecte un oubli, en comparant deux
# etats, JAMAIS en recopiant la loi de croyance.gd (le plancher, le gain et la
# resistance ne sont ecrits nulle part ici). Patron banc_croyance.gd:instantane.
static func instantane(colon: Dictionary) -> Dictionary:
	var plat: Dictionary = {}
	var croyances: Dictionary = colon.proprietes.croyances
	for chose_id in croyances:
		for propriete in croyances[chose_id]:
			plat["%s/%s" % [chose_id, propriete]] = croyances[chose_id][propriete].valeur
	return plat

# ---- LIGNE 4 : la reputation ----

# CE QUE LE TEMOIN A VU DE SES YEUX. Croyance.observer recopie toute propriete
# a la fois PRESENTE sur la chose percue et listee dans
# data/croyances.json:proprietes_observables -- ce fichier ne filtre rien
# lui-meme et ne nomme aucune propriete ici. Rend les croyances NEUVES de ce
# passage (difference d'instantanes), jamais un recalcul de la loi.
static func observer_si_cadence(
	colon: Dictionary,
	perceptions: Array,
	config: Dictionary,
	catalogue_croyances: Dictionary,
	temps: float,
) -> Array:
	if temps < float(colon.prochaine_observation):
		return []
	colon["prochaine_observation"] = temps + intervalle_observation_s(config)
	var avant := instantane(colon)
	Croyance.observer(colon, perceptions, catalogue_croyances)
	var evenements: Array = []
	for cle in instantane(colon):
		if avant.has(cle):
			continue
		var morceaux: PackedStringArray = cle.split("/")
		evenements.append({
			"colon": String(colon.id),
			"genre": "observe",
			"chose_id": morceaux[0],
			"propriete": morceaux[1],
			"certitude": certitude_crue(colon, morceaux[0], morceaux[1]),
			"credibilite": 1.0,
		})
	return evenements
# LA PROPAGATION AUX TEMOINS. L'emetteur verse TOUTES ses croyances a tout colon
# A PORTEE (Portee.en_portee, mecanisme partage -- jamais une comparaison de
# distance recopiee ici). Trois refus, a ne jamais confondre :
# - HORS PORTEE : le cablage ne parle meme pas. C'est le lointain.
# - SOUS data/croyances.json:seuil_bornes_transmission : le cablage renonce, il
#   n'appelle pas corriger(). Contrat du catalogue partage (« c'est a l'appelant
#   de le lire »), tenu ici comme banc_croyance.gd le tient ; aucun destinataire
#   de cette scene n'y tombe, le test seul exerce la branche.
# - AU-DELA : il appelle, et c'est le MECANISME qui tranche si la certitude du
#   receveur a franchi resistance_par_certitude.
#
# LE SUJET DE LA CROYANCE EST EXCLU DES DESTINATAIRES : on ne raconte pas a
# quelqu'un sa propre reputation. Decision de cablage, dite plutot que masquee --
# la retirer ne casserait rien, elle garde seulement le banc lisible.
#
# CREDIBILITE = LienPersonnel.force(RECEVEUR, emetteur) x
# propagation_par_temoin -- « a quel point JE TE crois ». Le lien est porte par
# CELUI QUI ECOUTE, jamais par celui qui parle : c'est le sens deja cable par
# banc_croyance.gd:transmettre, le seul du depot qui tourne, et celui que
# l'audit prealable nomme explicitement (ligne 4). La consigne d'origine ecrivait
# l'ordre inverse ; ECART ASSUME ET DIT, parce qu'une credibilite portee par
# l'emetteur ferait dependre ma confiance de ce que L'AUTRE ressent pour moi.
static func propager_si_cadence(
	emetteur: Dictionary,
	colons: Array,
	config: Dictionary,
	catalogue_croyances: Dictionary,
	catalogue_liens: Dictionary,
	temps: float,
) -> Array:
	if emetteur.is_empty() or temps < float(emetteur.prochaine_propagation):
		return []
	emetteur["prochaine_propagation"] = temps + intervalle_propagation_s(config)
	var seuil: float = float(catalogue_croyances.get("seuil_bornes_transmission", 0.0))
	var portee: float = portee_propagation(config)
	var fidelite: float = float(config.propagation_par_temoin)
	var evenements: Array = []
	for destinataire in colons:
		if String(destinataire.id) == String(emetteur.id):
			continue
		if not Portee.en_portee(emetteur.position, destinataire.position, portee):
			continue
		# CE QU'IL Y A A DIRE A CELUI-CI, resolu AVANT le gate de credibilite :
		# un destinataire a qui il n'y a rien a dire n'est pas « sourd », il n'y a
		# simplement pas de conversation. Sans ce tri, le SUJET de la reputation
		# (dont on retire la seule croyance qui le concerne, voir plus bas)
		# produirait un refus par credibilite a chaque passage -- defaut trouve EN
		# LANCANT LA SCENE, invisible au test.
		var a_dire: Array = []
		var croyances_emetteur: Dictionary = emetteur.proprietes.croyances
		for chose_id in croyances_emetteur:
			if String(chose_id) == String(destinataire.id):
				continue
			for propriete in croyances_emetteur[chose_id]:
				a_dire.append([String(chose_id), String(propriete),
					croyances_emetteur[chose_id][propriete].valeur])
		if a_dire.is_empty():
			continue
		var credibilite: float = LienPersonnel.force(
			destinataire, String(emetteur.id), catalogue_liens) * fidelite
		if credibilite < seuil:
			evenements.append({
				"colon": String(destinataire.id),
				"genre": "sourd",
				"chose_id": String(emetteur.id),
				"propriete": "",
				"certitude": 0.0,
				"credibilite": credibilite,
			})
			continue
		for entree in a_dire:
			var avant_valeur: Variant = valeur_crue(destinataire, entree[0], entree[1])
			var avant: float = certitude_crue(destinataire, entree[0], entree[1])
			Croyance.corriger(destinataire, entree[0], entree[1],
				entree[2], credibilite, catalogue_croyances)
			var apres: float = certitude_crue(destinataire, entree[0], entree[1])
			# NE TRACE QUE LES CHANGEMENTS (patron banc_croyance.gd:
			# verifier_si_cadence). La propagation est PERIODIQUE ici, pas
			# manuelle : sans ce filtre, chaque passage rejouerait la meme ligne
			# a l'identique. Un refus par dogme serait donc silencieux -- limite
			# DITE, et sans consequence ici : le dogme ne naît que de
			# l'accumulation d'observations (croyance.gd), or personne dans cette
			# scene n'observe le sujet sauf le temoin, qui n'ecoute personne.
			# C'est banc_croyance.gd qui montre le dogme, pas ce banc.
			if apres == avant and valeur_crue(destinataire, entree[0], entree[1]) == avant_valeur:
				continue
			evenements.append({
				"colon": String(destinataire.id),
				"genre": "recoit",
				"chose_id": entree[0],
				"propriete": entree[1],
				"certitude": apres,
				"credibilite": credibilite,
			})
	return evenements

# ---- LIGNE 6 : l'imitation ----

# LE MODELE N'EST PAS NOMME : parmi les colons PERCUS et a portee d'imitation,
# celui dont le modulateur est le plus haut. Rend {} si personne. Les entrees de
# perception qui ne sont pas des colons du banc sont ignorees sans alarme -- une
# chose percue qui ne porte pas de marque rend simplement 0.0.
static func modele_pour(
	colon: Dictionary,
	perceptions: Array,
	colons: Array,
	config: Dictionary,
) -> Dictionary:
	var portee: float = portee_imitation(config)
	var nom_marque := String(config.nom_marque_competence)
	var meilleur: Dictionary = {}
	var meilleur_modulateur: float = 0.0
	for entree in perceptions:
		var candidat := colon_par_id(colons, String(entree.chose.id))
		if candidat.is_empty():
			continue
		if not Portee.en_portee(colon.position, candidat.position, portee):
			continue
		var m: float = modulateur(candidat, nom_marque)
		if m > meilleur_modulateur:
			meilleur_modulateur = m
			meilleur = candidat
	return meilleur

# L'IMITATION, avec ses DEUX BORNES (voir en-tete). Le gate d'ecart decide s'il
# y a encore quelque chose a apprendre ; le plafond decide jusqu'ou. Le montant,
# lui, n'est PAS decide ici -- Epigenetique.poser le lit dans son catalogue
# (constat C). Rend l'evenement d'imitation, ou [] si rien n'a ete pose : un
# modele absent, un ecart trop faible ou un plafond atteint sont trois points
# neutres legitimes, jamais des alarmes.
static func imiter_si_cadence(
	colon: Dictionary,
	modele: Dictionary,
	config: Dictionary,
	catalogue_epigenetique: Dictionary,
	temps: float,
) -> Array:
	if temps < float(colon.prochaine_imitation):
		return []
	colon["prochaine_imitation"] = temps + intervalle_imitation_s(config)
	if modele.is_empty():
		return []
	var nom_marque := String(config.nom_marque_competence)
	var chez_le_modele: float = modulateur(modele, nom_marque)
	var chez_soi: float = modulateur(colon, nom_marque)
	if chez_le_modele - chez_soi <= float(config.seuil_ecart):
		return []
	var plafond: float = float(config.fidelite_imitation) * chez_le_modele
	if chez_soi >= plafond:
		return []
	Epigenetique.poser(colon, nom_marque, catalogue_epigenetique)
	return [{
		"colon": String(colon.id),
		"genre": "imite",
		"chose_id": String(modele.id),
		"propriete": nom_marque,
		"certitude": modulateur(colon, nom_marque),
		"credibilite": plafond,
	}]

# L'ENTRETIEN DU METIER : le maitre repose sa propre marque tant qu'elle est
# sous son plafond declare. Sans lui, Epigenetique.avancer la ferait fondre et
# « le maitre ne perd rien » serait faux (voir en-tete). Meme gate exact que
# banc_marche_competence.gd:_poser_une_marque.
#
# A LA MEME CADENCE QUE L'IMITATION, et jamais a chaque image : Epigenetique.
# poser n'a AUCUN parametre de temps (constat F de l'audit prealable), l'appeler
# par image ferait monter la marque a une vitesse dependant de la machine. Son
# echeance est SEPAREE de celle de l'imitation (un colon peut faire les deux)
# meme si l'intervalle est le meme -- coupler les deux echeances ferait qu'un
# geste consomme le tour de l'autre.
static func entretenir_si_cadence(
	colon: Dictionary,
	config: Dictionary,
	catalogue_epigenetique: Dictionary,
	decl: Dictionary,
	temps: float,
) -> bool:
	if not bool(decl.get("entretient_competence", false)):
		return false
	if temps < float(colon.prochaine_entretien):
		return false
	colon["prochaine_entretien"] = temps + intervalle_imitation_s(config)
	var nom_marque := String(config.nom_marque_competence)
	if modulateur(colon, nom_marque) >= float(decl.get("plafond_competence", 0.0)):
		return false
	Epigenetique.poser(colon, nom_marque, catalogue_epigenetique)
	return true

# ---- UN TICK COMPLET ----

# Statique et sans noeud : le test rejoue EXACTEMENT ce que la scene execute,
# jamais une reconstitution parallele qui pourrait deriver. MUTE colons et
# horloges en place ; rend { infos, evenements, saison }.
#
# L'ORDRE N'EST PAS LIBRE, quatre contraintes le fixent :
#   (1) percevoir AVANT tout -- observation, imitation et choix du modele lisent
#       la MEME perception de ce tick.
#   (2) observer AVANT propager : ce que le temoin vient de voir doit pouvoir
#       partir dans la meme image, sinon la propagation traine d'un tick.
#   (3) POSER AVANT AVANCER pour les marques (patron banc_psycho_social.gd) :
#       une imitation de CE tick doit compter avant la decroissance de CE tick,
#       sinon la marque fraiche est rabotee avant d'avoir servi.
#   (4) L'OUBLI EN DERNIER, et SEULEMENT a l'echeance de saison : une croyance
#       formee ou recue ce pas-ci ne doit pas perdre sa certitude avant d'avoir
#       ete lue une seule fois.
static func avancer(
	colons: Array,
	monde,
	config: Dictionary,
	catalogue_canaux: Dictionary,
	catalogue_croyances: Dictionary,
	catalogue_liens: Dictionary,
	catalogue_epigenetique: Dictionary,
	delta: float,
	temps: float,
	horloges: Dictionary,
) -> Dictionary:
	var evenements: Array = []
	var infos: Dictionary = {}
	var perceptions_par_colon: Dictionary = {}

	# (1) La couche 1, pour tout le monde.
	for colon in colons:
		perceptions_par_colon[colon.id] = Perception.percevoir(colon, monde, catalogue_canaux)

	# (2) Ce que chacun voit de ses yeux, puis ce que le temoin en dit.
	for colon in colons:
		evenements.append_array(observer_si_cadence(
			colon, perceptions_par_colon[colon.id], config, catalogue_croyances, temps))
	evenements.append_array(propager_si_cadence(
		colon_par_role(colons, config, "temoin"), colons, config,
		catalogue_croyances, catalogue_liens, temps))

	# (3) Les marques : poser (imitation et entretien) AVANT avancer.
	var nom_marque := String(config.nom_marque_competence)
	for colon in colons:
		var decl := declaration_de(config, String(colon.id))
		var modele: Dictionary = {}
		if bool(decl.get("imite", false)):
			modele = modele_pour(colon, perceptions_par_colon[colon.id], colons, config)
			evenements.append_array(imiter_si_cadence(
				colon, modele, config, catalogue_epigenetique, temps))
		entretenir_si_cadence(colon, config, catalogue_epigenetique, decl, temps)
		infos[colon.id] = {"modele_id": String(modele.get("id", ""))}
	for colon in colons:
		Epigenetique.avancer(colon, delta, catalogue_epigenetique)

	# (4) L'oubli, PAR SAISON et jamais par image (voir en-tete).
	var saison_echue := false
	horloges["horloge_saison"] = float(horloges.get("horloge_saison", 0.0)) + delta
	var duree_saison: float = duree_saison_s(config)
	if duree_saison > 0.0 and float(horloges.horloge_saison) >= duree_saison:
		horloges["horloge_saison"] = float(horloges.horloge_saison) - duree_saison
		horloges["saison"] = int(horloges.get("saison", 0)) + 1
		saison_echue = true
		evenements.append({
			"colon": "", "genre": "saison", "chose_id": "", "propriete": "",
			"certitude": float(horloges.saison), "credibilite": duree_saison,
		})
		for colon in colons:
			var avant := instantane(colon)
			Croyance.avancer(colon, duree_saison, catalogue_croyances)
			var apres := instantane(colon)
			for cle in avant:
				if apres.has(cle):
					continue
				var morceaux: PackedStringArray = cle.split("/")
				evenements.append({
					"colon": String(colon.id), "genre": "oublie",
					"chose_id": morceaux[0], "propriete": morceaux[1],
					"certitude": 0.0, "credibilite": 0.0,
				})

	# Les lectures, EN DERNIER : elles ne calculent aucun etat, elles le racontent.
	var sujet := colon_par_role(colons, config, "sujet_reputation")
	var nom_propriete := String(config.nom_propriete_reputation)
	for colon in colons:
		infos[colon.id]["modulateur"] = modulateur(colon, nom_marque)
		infos[colon.id]["reputation_valeur"] = valeur_crue(
			colon, String(sujet.get("id", "")), nom_propriete)
		infos[colon.id]["reputation_certitude"] = certitude_crue(
			colon, String(sujet.get("id", "")), nom_propriete)
	return {
		"infos": infos,
		"evenements": evenements,
		"saison": int(horloges.get("saison", 0)),
		"saison_echue": saison_echue,
	}

# ---- Textes (purs -- aucun nombre n'y est recalcule) ----

static func _mot(valeur: Variant) -> String:
	if valeur == null:
		return "(rien)"
	if valeur is bool:
		return "oui" if valeur else "non"
	return str(valeur)

static func ligne_pose(config: Dictionary) -> String:
	return ("t=0.0 %d colons poses -- echelle : 1 h = %.2f s\n" +
		"cadences (s) : observation %.2f | propagation %.2f | imitation %.3f | saison %.1f\n" +
		"portees (unites) : propagation %.0f | imitation %.0f -- fidelite %.2f, seuil d'ecart %.2f") % [
		config.get("colons", []).size(),
		secondes_par_heure(config),
		intervalle_observation_s(config),
		intervalle_propagation_s(config),
		intervalle_imitation_s(config),
		duree_saison_s(config),
		portee_propagation(config),
		portee_imitation(config),
		float(config.fidelite_imitation),
		float(config.seuil_ecart),
	]

static func ligne_bascule_vol(t: float, actif: bool) -> String:
	return "t=%.1fs VOL : %s" % [t, "en cours" if actif else "termine (plus rien a reobserver)"]

static func ligne_bascule_eloigne(t: float, eloigne: bool) -> String:
	return "t=%.1fs LOINTAIN : %s" % [t, "hors de portee" if eloigne else "a portee"]

static func ligne_evenement(t: float, ev: Dictionary) -> String:
	match String(ev.genre):
		"observe":
			return "t=%.1fs %s OBSERVE %s.%s (certitude %.2f) -- il l'a vu de ses yeux" % [
				t, ev.colon, ev.chose_id, ev.propriete, ev.certitude]
		"recoit":
			return "t=%.1fs %s RECOIT %s.%s (credibilite %.2f, certitude %.2f)" % [
				t, ev.colon, ev.chose_id, ev.propriete, ev.credibilite, ev.certitude]
		"sourd":
			return "t=%.1fs %s N'ECOUTE PAS %s (credibilite %.2f sous le seuil)" % [
				t, ev.colon, ev.chose_id, ev.credibilite]
		"imite":
			return "t=%.1fs %s IMITE %s sur '%s' -- modulateur %.3f (plafond %.3f)" % [
				t, ev.colon, ev.chose_id, ev.propriete, ev.certitude, ev.credibilite]
		"saison":
			return "t=%.1fs SAISON %d (%.1f s) -- oubli applique a tous" % [
				t, int(ev.certitude), ev.credibilite]
		"oublie":
			return "t=%.1fs %s OUBLIE %s.%s" % [t, ev.colon, ev.chose_id, ev.propriete]
	return "t=%.1fs %s ?" % [t, ev.colon]

static func ligne_trace(t: float, colon: Dictionary, infos: Dictionary) -> String:
	return "t=%.1fs %s | reputation crue %s (certitude %.3f) | competence %.3f | modele %s" % [
		t, String(colon.id),
		_mot(infos.get("reputation_valeur", null)),
		float(infos.get("reputation_certitude", 0.0)),
		float(infos.get("modulateur", 0.0)),
		String(infos.get("modele_id", "")) if String(infos.get("modele_id", "")) != "" else "(aucun)",
	]

static func texte_label_colon(colon: Dictionary, infos: Dictionary) -> String:
	var modele_id := String(infos.get("modele_id", ""))
	var suite := ""
	if modele_id != "":
		suite = "\nimite : %s" % modele_id
	return "%s\nreputation crue : %s (%.2f)\ncompetence : %.3f%s" % [
		String(colon.id),
		_mot(infos.get("reputation_valeur", null)),
		float(infos.get("reputation_certitude", 0.0)),
		float(infos.get("modulateur", 0.0)),
		suite,
	]

static func texte_compteur(temps: float, saison: int, vol: bool, eloigne: bool) -> String:
	return "t=%.1f s -- saison %d -- vol : %s -- lointain : %s" % [
		temps, saison,
		"EN COURS" if vol else "termine",
		"hors de portee" if eloigne else "a portee",
	]

static func texte_aide() -> String:
	return ("clic gauche : le vol commence / cesse -- clic droit : le lointain se " +
		"rapproche / s'eloigne")

# ---- Rendu (impur, Node) -- aucune decision, seulement des couleurs, des
# rectangles et des longueurs de barre.

func _couleur(rgb: Array) -> Color:
	return Color(float(rgb[0]), float(rgb[1]), float(rgb[2]))

func _construire_rendu() -> void:
	for colon in _colons:
		var label := _creer_label(int(_config.taille_police_label))
		label.position = Vector2(colon.position.x, colon.position.y) + Vector2(
			float(_config.taille_colon), float(_config.taille_colon))
		add_child(label)
		_labels[colon.id] = label

	var couche := CanvasLayer.new()
	add_child(couche)
	_label_compteur = _creer_label(int(_config.taille_police_compteur))
	_label_compteur.position = Vector2(10.0, 10.0)
	couche.add_child(_label_compteur)
	_label_aide = _creer_label(int(_config.taille_police_aide))
	_label_aide.position = Vector2(10.0, 34.0)
	_label_aide.text = texte_aide()
	couche.add_child(_label_aide)

	_poser_camera()

func _creer_label(taille: int) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", taille)
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	label.add_theme_constant_override("outline_size", 4)
	return label

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(float(_config.terrain_largeur), float(_config.terrain_hauteur))),
		_couleur(_config.couleur_fond))

	# Les DEUX cercles de portee sont les portees REELLES, jamais des disques
	# decoratifs : ce sont elles qui decident qui recoit et qui imite.
	var temoin := colon_par_role(_colons, _config, "temoin")
	if not temoin.is_empty():
		draw_arc(Vector2(temoin.position.x, temoin.position.y), portee_propagation(_config),
			0.0, TAU, 128, _couleur(_config.couleur_portee_propagation), 2.0)
	for decl in _config.get("colons", []):
		if not bool(decl.get("imite", false)):
			continue
		var imitant := colon_par_id(_colons, String(decl.id))
		if imitant.is_empty():
			continue
		draw_arc(Vector2(imitant.position.x, imitant.position.y), portee_imitation(_config),
			0.0, TAU, 96, _couleur(_config.couleur_portee_imitation), 2.0)

	_tracer_liens_de_savoir(temoin)
	_tracer_liens_d_imitation()

	for colon in _colons:
		var centre := Vector2(colon.position.x, colon.position.y)
		var cote: float = float(_config.taille_colon)
		draw_rect(Rect2(centre - Vector2(cote, cote) / 2.0, Vector2(cote, cote)),
			_couleur(_couleur_declaree(String(colon.id))))
		_dessiner_barre_competence(colon, centre)

# QUI SAIT QUOI : une ligne du temoin vers chaque colon qui PORTE la croyance de
# reputation, d'opacite proportionnelle a sa certitude. Dessinee sur l'ETAT (qui
# la porte), jamais sur l'EVENEMENT du tick -- sinon la ligne battrait au rythme
# de la cadence de propagation au lieu de dire ce que chacun sait.
func _tracer_liens_de_savoir(temoin: Dictionary) -> void:
	if temoin.is_empty():
		return
	var sujet := colon_par_role(_colons, _config, "sujet_reputation")
	if sujet.is_empty():
		return
	var nom := String(_config.nom_propriete_reputation)
	var base := _couleur(_config.couleur_propagation)
	for colon in _colons:
		if String(colon.id) == String(temoin.id):
			continue
		var certitude := certitude_crue(colon, String(sujet.id), nom)
		if certitude <= 0.0:
			continue
		var couleur := Color(base.r, base.g, base.b, clamp(certitude, 0.1, 1.0))
		draw_line(Vector2(temoin.position.x, temoin.position.y),
			Vector2(colon.position.x, colon.position.y), couleur, 1.0 + 4.0 * certitude)

func _tracer_liens_d_imitation() -> void:
	for colon in _colons:
		var modele_id := String(_infos.get(colon.id, {}).get("modele_id", ""))
		if modele_id == "":
			continue
		var modele := colon_par_id(_colons, modele_id)
		if modele.is_empty():
			continue
		draw_line(Vector2(colon.position.x, colon.position.y),
			Vector2(modele.position.x, modele.position.y),
			_couleur(_config.couleur_imitation), 3.0)

# La barre est graduee sur le modulateur du MODELE le plus competent de la
# scene -- un seul nombre, jamais un maximum d'affichage recopie a cote.
func _dessiner_barre_competence(colon: Dictionary, centre: Vector2) -> void:
	var maximum := 0.0
	for autre in _colons:
		maximum = max(maximum, modulateur(autre, String(_config.nom_marque_competence)))
	if maximum <= 0.0:
		return
	var largeur: float = float(_config.largeur_barre)
	var hauteur: float = float(_config.hauteur_barre)
	var origine := Vector2(centre.x - largeur / 2.0,
		centre.y - float(_config.taille_colon) / 2.0 - hauteur - 6.0)
	draw_rect(Rect2(origine, Vector2(largeur, hauteur)), _couleur(_config.couleur_fond_barre))
	var ratio: float = clamp(float(_infos.get(colon.id, {}).get("modulateur", 0.0)) / maximum, 0.0, 1.0)
	draw_rect(Rect2(origine, Vector2(largeur * ratio, hauteur)),
		_couleur(_config.couleur_barre_competence))

func _couleur_declaree(id: String) -> Array:
	return declaration_de(_config, id).get("couleur", [1.0, 1.0, 1.0])

func _rafraichir() -> void:
	for colon in _colons:
		_labels[colon.id].position = Vector2(colon.position.x, colon.position.y) + Vector2(
			float(_config.taille_colon), float(_config.taille_colon))
		_labels[colon.id].text = texte_label_colon(colon, _infos.get(colon.id, {}))
	_label_compteur.text = texte_compteur(
		_temps, int(_horloges.get("saison", 0)), _vol, _lointain_eloigne)

func _poser_camera() -> void:
	var camera := Camera2D.new()
	camera.position = Vector2(float(_config.terrain_largeur), float(_config.terrain_hauteur)) / 2.0
	camera.zoom = Vector2(0.95, 0.95)
	camera.enabled = true
	add_child(camera)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
