extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_temps_vieillissement.tscn, PAS la
# scene principale). Assemble DIX mecanismes deja fermes, tous appeles tels
# quels et AUCUN TOUCHE : senescence.gd, stade.gd, seuil_etat.gd,
# etat_effectif.gd, depense.gd, epigenetique.gd, accouplement.gd, gestation.gd,
# heredite.gd, consommer.gd (plus lien_personnel.gd, perception.gd, monde.gd,
# et expression.gd a la seule fabrication).
#
# CE QU'ON DOIT VOIR, trois observations sur une seule horloge.
#   1. UN EFFET POSE AUJOURD'HUI QUI FRAPPE DANS DEUX ANS. Deux colons ont
#      decide au premier tick. Rien ne les distingue des autres pendant 730
#      jours simules -- puis leur reserve de vie se vide six fois plus vite,
#      d'un coup. Clic gauche : le temps accelere, l'attente raccourcit, la loi
#      ne bouge pas.
#   2. ON VIEILLIT ET CA SE VOIT. Quatre ages cote a cote. Le jeune est faible
#      et ignorant ; l'adulte touche son pic sous vos yeux puis redescend ; le
#      veteran perd en force et gagne en savoir ; le vieux est le plus faible
#      et le plus competent. Une courbe, aucune categorie.
#   3. LES ENFANTS HERITENT. Deux couples, deux lignees. Chaque enfant recoit
#      un allele de chacun de ses parents, une part de la marque d'annees de sa
#      mere, et la moitie de son patrimoine. Les LIENS suivent deux voies
#      opposees : lignee A les transmet, lignee B laisse l'enfant neutre.
#
# LA COURBE D'AGE EST UN CHAMP DERIVE, reecrit par-dessus sa propre valeur a
# chaque tick depuis l'age et une force de BASE que plus rien ne retouche --
# jamais un '+='. C'est la parade au blocage connu du mecanisme de generation :
# sa lecture par chemin relit ce qu'il vient d'ecrire, donc rappele en boucle
# il part sans borne (resultat negatif inscrit cinq fois en donnee, voir
# data/epigenetique.json). Ce mecanisme n'intervient qu'UNE FOIS, a la
# fabrication, pour traduire les alleles en force de base. Verrouille
# NEGATIVEMENT par un test qui relit avancer_tick sur le disque.
#
# QUATRE ECRIVAINS UNIQUES, un par grandeur : poser_force_effective,
# poser_accumulateur_differe, poser_cout_vie et avancer_competence. Deux
# morceaux de cablage poses sur la meme cle se recouvriraient sans bruit, et
# aucun test ne le dirait.
#
# QUI PORTE EST UNE DONNEE, jamais une convention de ce fichier : chaque colon
# declare son role_gestation, et accouplement.gd n'ecrit l'etat que sur celui
# qui peut gester. Gestation.avancer est donc appele sur TOUT colon qui porte
# une gestation -- une fecondation n'en produit qu'une, ce fichier n'a personne
# a departager.
#
# TROIS GARDES VIENNENT DE LA DONNEE, jamais d'un cas particulier du code. Les
# temoins d'age ne declarent aucun mode de reproduction, et accouplement.gd
# rend la main de lui-meme. Les deux couples declarent deux especes distinctes,
# et l'egalite stricte suffit a les separer meme s'ils se voient tous. Un
# enfant nait sans espece, donc sterile dans cette scene.
#
# COLONS FABRIQUES PAR Objet.fabriquer sur le type reel 'colon' : de la
# viennent l'age, la table de stades, les genes, les marques et la reference de
# reproduction. Leur bloc de reserves est ENSUITE remplace par le seul canal de
# vie de ce banc -- les cinq canaux physiologiques du paquet partage
# brouilleraient la lecture sans rien prouver. data/types.json reste intact,
# rien a inscrire au linter.
#
# Deux moities : le Node charge, dessine et imprime ; les fonctions statiques
# calculent, et le test rejoue exactement les memes. Aucun nom de propriete
# n'est ecrit en dur, ils arrivent tous de
# data/banc_temps_vieillissement.json.

const Monde = preload("res://scripts/monde.gd")
const Perception = preload("res://scripts/perception.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")
const Senescence = preload("res://scripts/senescence.gd")
const Stade = preload("res://scripts/stade.gd")
const Accouplement = preload("res://scripts/accouplement.gd")
const Gestation = preload("res://scripts/gestation.gd")
const Heredite = preload("res://scripts/heredite.gd")
const ExpressionGenetique = preload("res://scripts/expression.gd")
const Epigenetique = preload("res://scripts/epigenetique.gd")
const SeuilEtat = preload("res://scripts/seuil_etat.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")
const Depense = preload("res://scripts/depense.gd")
const Consommer = preload("res://scripts/consommer.gd")
const LienPersonnel = preload("res://scripts/lien_personnel.gd")

# Cle PLATE posee par ce cablage sur ses propres colons -- jamais sur
# data/types.json, donc rien a inscrire dans scripts/test_lint_donnees.gd.
const CLE_VOIE_LIENS := "voie_heritage_liens"

var _config: Dictionary = {}
var _catalogue_types: Dictionary = {}
var _catalogue_canaux: Dictionary = {}
var _catalogue_etats: Dictionary = {}
var _catalogue_seuils: Dictionary = {}
var _catalogue_epigenetique: Dictionary = {}
var _catalogue_heredite: Dictionary = {}
var _catalogue_reproduction: Dictionary = {}
var _catalogue_genes: Dictionary = {}

var _colons: Array = []
var _monde
var _rng := RandomNumberGenerator.new()

var _horloges: Dictionary = {}
var _infos: Dictionary = {}
var _etats_avant: Dictionary = {}
var _heritages: Dictionary = {}
var _naissance_faite: Dictionary = {}
var _couleurs: Dictionary = {}
var _tailles: Dictionary = {}
var _labels: Dictionary = {}

var _facteur: int = 0
var _temps: float = 0.0
var _temps_simule: float = 0.0
var _horloge_trace: float = 0.0
var _compteur_enfant: int = 0

var _label_compteur: Label
var _label_aide: Label

func _ready() -> void:
	_config = _charger_json("res://data/banc_temps_vieillissement.json")
	_catalogue_canaux = _charger_json("res://data/canaux.json")
	_catalogue_etats = _charger_json("res://data/etats.json")
	_catalogue_epigenetique = _charger_json("res://data/epigenetique.json")
	_catalogue_heredite = _charger_json("res://data/heredite.json")
	_catalogue_genes = _config.get("catalogue_genes", {})
	_catalogue_reproduction = _config.get("catalogue_reproduction_local", {})
	_rng.seed = int(_config.get("seed", 0))

	_catalogue_types = types_du_banc(_charger_json("res://data/types.json"))
	_catalogue_seuils = catalogue_seuils_effectif(
		_charger_json("res://data/seuils_etat.json"), _config)

	for decl in _config.get("colons", []):
		var colon := construire_colon(decl, _config, _catalogue_types, _catalogue_genes, _catalogue_epigenetique)
		_colons.append(colon)
		_couleurs[colon.id] = _couleur(decl.get("couleur", [1.0, 1.0, 1.0]))
		_tailles[colon.id] = float(_config.taille_colon)
		_horloges[colon.id] = 0.0
	_catalogue_epigenetique = catalogue_epigenetique_effectif(_config, _colons, _catalogue_epigenetique)

	_monde = BancCommun.monde_depuis([{"choses": _colons, "type": "colon"}])

	_construire_rendu()
	print(ligne_pose(_config, _colons))

func _unhandled_input(evenement: InputEvent) -> void:
	if evenement is InputEventMouseButton and evenement.pressed \
			and evenement.button_index == MOUSE_BUTTON_LEFT:
		_facteur = facteur_suivant(_facteur, _config.get("facteurs_temps", [1.0]).size())
		print(ligne_facteur(_temps, _facteur_courant()))

func _process(delta: float) -> void:
	var delta_simule: float = delta * _facteur_courant()
	_temps += delta
	_temps_simule += delta_simule

	for colon in _colons:
		_etats_avant[colon.id] = colon.proprietes.get("etats_actifs", []).duplicate()

	var resultat: Dictionary = avancer_tick(
		_colons, _monde, delta_simule, int(_temps_simule * 1000.0), _config,
		_catalogue_canaux, _catalogue_reproduction, _catalogue_etats,
		_catalogue_seuils, _catalogue_epigenetique, _horloges)
	_infos = resultat.infos
	_horloges = resultat.horloges

	for colon in _colons:
		var changements: Dictionary = changements_etats(
			_etats_avant.get(colon.id, []), colon.proprietes.get("etats_actifs", []))
		for ligne in lignes_changement(_temps_simule, String(colon.id), changements):
			print(ligne)

	_verifier_naissances()

	_horloge_trace += delta
	if _horloge_trace >= float(_config.intervalle_trace_s):
		_horloge_trace = 0.0
		for colon in _colons:
			print(ligne_trace(_temps_simule, colon, _infos.get(colon.id, {}), _config))

	_rafraichir()
	queue_redraw()

func _facteur_courant() -> float:
	var facteurs: Array = _config.get("facteurs_temps", [1.0])
	if _facteur < 0 or _facteur >= facteurs.size():
		return 1.0
	return float(facteurs[_facteur])

# Une naissance par porteur, et une seule : le compteur de ce banc gate la
# fabrication, jamais un mecanisme. Sans lui, la gestation retiree serait
# reposee au tick suivant (accouplement.gd n'efface JAMAIS son accumulateur,
# son accumulation est irreversible par construction) et la scene se
# remplirait d'enfants.
func _verifier_naissances() -> void:
	for colon in _colons.duplicate():
		if not naissance_prete(colon) or bool(_naissance_faite.get(colon.id, false)):
			continue
		_naissance_faite[colon.id] = true
		_compteur_enfant += 1
		_accoucher(colon, "enfant_%d" % _compteur_enfant)

func _accoucher(porteur: Dictionary, id: String) -> void:
	var off: Array = _config.get("offset_enfant", [0.0, 0.0, 0.0])
	var position: Vector3 = porteur.position + Vector3(float(off[0]), float(off[1]), float(off[2]))
	var enfant := fabriquer_enfant(id, porteur, position, _config, _catalogue_types,
		_catalogue_genes, _catalogue_heredite, _catalogue_epigenetique, _rng)
	var heritage := transmettre_heritage(porteur, enfant, _config, _catalogue_epigenetique)

	_colons.append(enfant)
	_monde.ajouter(enfant, "colon", enfant.position)
	_couleurs[enfant.id] = _couleur(_config.get("couleur_enfant", [1.0, 1.0, 1.0]))
	_tailles[enfant.id] = float(_config.taille_colon_enfant)
	_horloges[enfant.id] = 0.0
	_heritages[enfant.id] = heritage
	_labels[enfant.id] = _creer_label_colon(enfant)

	# La trace lit gestation.partenaire_genes_etat (la copie figee des genes de
	# l'autre parent) : elle passe donc AVANT le retrait, jamais apres.
	print(ligne_naissance(_temps_simule, porteur, enfant, _config))
	print(ligne_heritage(_temps_simule, enfant, heritage, _config))
	porteur.proprietes.erase("gestation")

# ---------------------------------------------------------------------------
# Chargement (pur : ne lit aucun fichier, recoit les catalogues deja parses)
# ---------------------------------------------------------------------------

# Les cinq entrees de data/types.json dont Objet.fabriquer a besoin pour
# composer un colon reel -- jamais le catalogue entier, meme geste que
# banc_reproduction.gd/banc_genetique.gd.
static func types_du_banc(types_partages: Dictionary) -> Dictionary:
	var catalogue: Dictionary = {}
	for nom in ["objet_physique", "dynamique", "percevant", "agent", "colon"]:
		catalogue[nom] = types_partages.get(nom, {})
	return catalogue

# Le catalogue PARTAGE de seuils, plus les entrees LOCALES du banc, en un seul
# Dictionary : seuil_etat.gd n'en recoit qu'un par appel, et deux appels
# separes couteraient deux parcours du monde pour la meme loi. Les references
# ne peuvent pas se telescoper -- une cle locale qui existerait deja dans le
# catalogue partage alarme ici plutot que d'ecraser en silence.
static func catalogue_seuils_effectif(partage: Dictionary, config: Dictionary) -> Dictionary:
	var effectif: Dictionary = partage.duplicate(true)
	for ref in config.get("seuils_locaux", {}):
		if effectif.has(ref):
			push_error("banc_temps_vieillissement : entree de seuil locale '%s' deja presente dans le catalogue partage" % ref)
			continue
		effectif[ref] = config.seuils_locaux[ref]
	return effectif

# Derive, d'UN SEUL patron de donnee, une entree de catalogue par cible
# possible -- la loi (montee, decroissance, plancher) vit une fois, jamais N
# fois. epigenetique.gd ne voit que des noms opaques et ignore totalement
# qu'ils encodent une paire. Meme geste que banc_social_paire.gd:catalogue_paires.
static func catalogue_epigenetique_effectif(config: Dictionary, colons: Array, partage: Dictionary) -> Dictionary:
	var effectif: Dictionary = partage.duplicate(true)
	var patron: Dictionary = config.get("patron_marque_lien_herite", {})
	for colon in colons:
		effectif[nom_marque_lien_herite(config, String(colon.id))] = patron.duplicate(true)
	return effectif

static func nom_marque_lien_herite(config: Dictionary, cible: String) -> String:
	return "%s:%s" % [String(config.get("prefixe_lien_herite", "lien_herite")), cible]

# ---------------------------------------------------------------------------
# Construction d'un colon (pure : ni Monde, ni rendu)
# ---------------------------------------------------------------------------

# Ordre impose : composition de paquets -> age et reglages de courbe ->
# remplacement du canal de reserves -> surcharge des genes -> expression UNE
# SEULE FOIS -> stade -> competence de depart -> premiere courbe. L'expression
# doit passer APRES la surcharge des genes (sinon elle n'aurait rien a
# exprimer) et AVANT la premiere lecture de la force de base.
static func construire_colon(
	decl: Dictionary,
	config: Dictionary,
	catalogue_types: Dictionary,
	catalogue_genes: Dictionary,
	catalogue_epigenetique: Dictionary,
) -> Dictionary:
	var brut := {
		"position": decl.get("position", [0.0, 0.0, 0.0]),
		"attaches": [], "forme": {}, "poids_verbes": {},
	}
	var colon := BancCommun.fabriquer_colon(String(decl.id), "colon", brut, catalogue_types)
	var proprietes: Dictionary = colon.proprietes

	proprietes["age"] = float(decl.get("age_initial", 0.0))
	proprietes[String(config.nom_pic_force)] = float(config.pic_force_ans)
	proprietes[String(config.nom_declin_force)] = float(config.declin_par_an_apres)
	proprietes[String(config.nom_cout_vie)] = float(config.cout_vie_base)

	# REMPLACEMENT EN BLOC des cinq canaux du paquet 'dynamique' : ce banc
	# n'observe qu'une seule reserve, et depense.gd ponctionne TOUS les canaux
	# presents. Les laisser rendrait la lecture illisible sans rien prouver.
	var reserves: Dictionary = {}
	reserves[String(config.nom_reserve_vie)] = {
		"reserve": float(config.capacite_vie),
		"cout_base": float(config.cout_vie_base),
		"surcout_action": 0.0,
	}
	if decl.has("patrimoine"):
		reserves[String(config.nom_reserve_patrimoine)] = {
			"reserve": float(decl.patrimoine), "cout_base": 0.0, "surcout_action": 0.0,
		}
	proprietes["reserves"] = reserves

	# La cle n'existe QUE chez les colons qui ont pris la decision : les autres
	# sont un chemin mort silencieux pour l'entree partagee de seuil.
	if bool(decl.get("decision_differee", false)):
		proprietes[String(config.nom_accumulateur_differe)] = 0.0

	# L'espece DECLAREE decide du mode : sans espece, mode_reproduction vide,
	# et accouplement.gd rend la main par sa propre garde.
	if decl.has("espece"):
		proprietes["mode_reproduction"] = "sexuee"
		proprietes["espece_reproduction"] = String(decl.espece)
	else:
		proprietes["mode_reproduction"] = ""
	proprietes["role_gestation"] = String(decl.get("role_gestation", ""))
	proprietes[CLE_VOIE_LIENS] = String(decl.get("voie_heritage_liens", ""))

	proprietes["genes_actifs"] = decl.get("genes_actifs", []).duplicate()
	proprietes["genes_etat"] = decl.get("genes_etat", {}).duplicate(true)
	for cible in decl.get("liens_initiaux", {}):
		LienPersonnel.poser(colon, String(cible), float(decl.liens_initiaux[cible]))

	var valeurs := ExpressionGenetique.exprimer(colon, catalogue_genes, {}, {})
	ExpressionGenetique.appliquer(colon, valeurs)

	Stade.avancer(colon)
	poser_competence_initiale(colon, config, catalogue_epigenetique)
	poser_force_effective(colon, config)
	return colon

# Une entite deja agee ne repart pas de zero : elle porte les annees qu'elle a
# vecues. La valeur vient du catalogue (modulateur_pose x age), jamais d'un
# second nombre recopie en donnee de banc qui pourrait diverger du premier.
static func poser_competence_initiale(colon: Dictionary, config: Dictionary, catalogue_epigenetique: Dictionary) -> float:
	var nom := String(config.nom_marque_competence)
	if not catalogue_epigenetique.has(nom):
		push_error("banc_temps_vieillissement : marque '%s' absente du catalogue epigenetique" % nom)
		return 0.0
	var gain: float = float(catalogue_epigenetique[nom].get("modulateur_pose", 0.0))
	var depart: float = gain * float(colon.proprietes.get("age", 0.0))
	if depart <= 0.0:
		return 0.0
	colon.proprietes.marques_epigenetiques[nom] = {"modulateur": depart, "age_marque": 0.0}
	return depart

# ---------------------------------------------------------------------------
# LIGNE 3 : la courbe d'age, recalculee a neuf
# ---------------------------------------------------------------------------

# LECTURE PURE, aucune ecriture. Deux branches et une seule borne : sous le
# pic la force monte proportionnellement a l'age, au-dela elle descend d'un
# taux fixe par annee. Le plancher n'est pas une regle de jeu, c'est la borne
# qui empeche la droite descendante de passer sous zero -- une force negative
# n'a aucun sens et rendrait la barre absurde. pic <= 0.0 : la courbe n'a plus
# de sens, la base est rendue telle quelle plutot qu'une division par zero.
static func force_effective(age: float, base: float, pic: float, declin: float, plancher: float) -> float:
	if pic <= 0.0:
		return base
	var brute: float = base * (age / pic) if age <= pic else base * (1.0 - declin * (age - pic))
	return max(plancher, brute)

# UNIQUE ECRIVAIN de la force effective. RECALCULEE A NEUF depuis l'age et la
# force de BASE (que rien ne reecrit jamais apres la fabrication), puis ECRITE
# PAR-DESSUS la valeur du tick precedent -- JAMAIS un '+='. C'est la parade
# etablie du depot au blocage d'expression.gd. MUTE le colon ; rend la valeur
# posee pour que l'affichage relise sans recalculer.
static func poser_force_effective(colon: Dictionary, config: Dictionary) -> float:
	var proprietes: Dictionary = colon.proprietes
	var valeur := force_effective(
		float(proprietes.get("age", 0.0)),
		float(proprietes.get(String(config.nom_force_base), 0.0)),
		float(proprietes.get(String(config.nom_pic_force), 0.0)),
		float(proprietes.get(String(config.nom_declin_force), 0.0)),
		float(config.plancher_force))
	proprietes[String(config.nom_force_effective)] = valeur
	return valeur

# ---------------------------------------------------------------------------
# LIGNE 3 : la competence, une marque posee par annee vecue
# ---------------------------------------------------------------------------

static func modulateur_competence(colon: Dictionary, config: Dictionary) -> float:
	var marques: Dictionary = colon.proprietes.get("marques_epigenetiques", {})
	return float(marques.get(String(config.nom_marque_competence), {}).get("modulateur", 0.0))

# CLAMP A LA LECTURE, jamais une borne dans le mecanisme : epigenetique.gd
# n'a AUCUN plafond, poser() ajoute sans fin.
static func competence_effective(colon: Dictionary, config: Dictionary) -> float:
	return clamp(modulateur_competence(colon, config), 0.0, float(config.plafond_competence))

# L'intervalle de pose, en SECONDES DE SIMULATION : une pose par ANNEE vecue,
# jamais un appel par image (poser() n'a pas de delta, appele par image la
# marque monterait a une vitesse qui depend de la machine). Il doit rester
# sous la survie d'une marque fraiche sans renouvellement : au-dela, le
# catalogue la supprime avant la pose suivante et le compteur ne demarre
# jamais -- verrouille par test contre les nombres reels du disque.
static func intervalle_pose_s(config: Dictionary) -> float:
	var annees_par_seconde: float = float(config.annees_par_seconde)
	if annees_par_seconde <= 0.0:
		return 0.0
	return 1.0 / annees_par_seconde

# Accumulateur d'intervalle. INCONDITIONNEL, contrairement au patron de la
# forge : personne ne peut cesser de vieillir, il n'y a aucune exposition a
# couper. PURE.
static func avancer_horloge(horloge: float, delta: float, intervalle: float) -> Dictionary:
	if intervalle <= 0.0:
		return {"horloge": 0.0, "poser": true}
	var suivant: float = horloge + delta
	if suivant < intervalle:
		return {"horloge": suivant, "poser": false}
	return {"horloge": suivant - intervalle, "poser": true}

# POSER AVANT AVANCER : l'annee de CE tick doit compter avant la decroissance
# de CE tick, sinon la marque fraiche est rabotee avant d'avoir servi. Le
# plafond gate la POSE en plus de la lecture -- sans lui, le modulateur
# monterait tres au-dessus du plafond affiche et la redescente prendrait dix
# fois plus longtemps que la montee.
static func avancer_competence(
	colon: Dictionary,
	horloge: float,
	delta: float,
	config: Dictionary,
	catalogue_epigenetique: Dictionary,
) -> Dictionary:
	var suivant := avancer_horloge(horloge, delta, intervalle_pose_s(config))
	var pose := false
	if bool(suivant.poser) and modulateur_competence(colon, config) < float(config.plafond_competence):
		Epigenetique.poser(colon, String(config.nom_marque_competence), catalogue_epigenetique)
		pose = true
	Epigenetique.avancer(colon, delta, catalogue_epigenetique)
	return {"horloge": float(suivant.horloge), "pose": pose}

# ---------------------------------------------------------------------------
# LIGNE 2 : l'accumulateur plat, et le cout que l'etat module
# ---------------------------------------------------------------------------

# UNIQUE ECRIVAIN du compteur de jours. La cle ABSENTE est un point neutre
# legitime : ce colon n'a rien decide, il n'accumule rien et l'entree de seuil
# ne le voit jamais. MONOTONE par construction -- rien ici ne la fait
# redescendre, le franchissement ne peut donc pas s'inverser.
static func poser_accumulateur_differe(colon: Dictionary, delta: float, config: Dictionary) -> float:
	var nom := String(config.nom_accumulateur_differe)
	if not colon.proprietes.has(nom):
		return 0.0
	var valeur: float = float(colon.proprietes[nom]) + delta * float(config.jours_par_seconde)
	colon.proprietes[nom] = valeur
	return valeur

# UNIQUE ECRIVAIN du cout_base du canal de vie. Compose par etat_effectif.gd,
# jamais reimplemente ici : une copie locale de sa loi (ecraser gagne sur
# moduler, tri alphabetique) deriverait du mecanisme sans que rien ne rougisse.
# C'est cette fonction, et elle seule, qui rend le x6.0 de l'etat observable :
# la ponction de reserve ignore totalement la resolution d'etats, elle ne lit
# qu'un nombre deja pose sur le canal.
static func poser_cout_vie(colon: Dictionary, config: Dictionary, catalogue_etats: Dictionary) -> float:
	var effectif: float = EtatEffectif.valeur(colon, String(config.nom_cout_vie), catalogue_etats)
	var canal: Dictionary = colon.proprietes.get("reserves", {}).get(String(config.nom_reserve_vie), {})
	if canal.is_empty():
		push_error("banc_temps_vieillissement : canal de reserve '%s' absent du colon '%s'"
			% [String(config.nom_reserve_vie), colon.get("id", "?")])
		return 0.0
	canal["cout_base"] = effectif
	return effectif

static func reserve_vie(colon: Dictionary, config: Dictionary) -> float:
	return float(colon.proprietes.get("reserves", {}).get(String(config.nom_reserve_vie), {}).get("reserve", 0.0))

static func reserve_patrimoine(colon: Dictionary, config: Dictionary) -> float:
	return float(colon.proprietes.get("reserves", {}).get(String(config.nom_reserve_patrimoine), {}).get("reserve", 0.0))

# ---------------------------------------------------------------------------
# LE TICK
# ---------------------------------------------------------------------------

# UN TICK COMPLET, l'ordre compris. Statique et sans noeud : le test rejoue
# EXACTEMENT ce que la scene execute, jamais une reconstitution parallele.
# MUTE les colons en place ; rend { infos, horloges, bascules }.
#
# L'ORDRE N'EST PAS LIBRE, cinq contraintes le fixent :
#   (1) l'age AVANT tout -- la courbe, la marque et le stade en dependent tous
#       les trois, ils doivent lire le MEME age.
#   (2) la courbe recalculee AVANT la marque, pour que la trace montre l'etat
#       du meme instant des deux cotes.
#   (3) poser AVANT avancer pour la marque (voir avancer_competence).
#   (4) le seuil APRES l'accumulateur -- comparer la valeur de CE tick, jamais
#       celle du precedent.
#   (5) le cout de vie APRES le seuil et AVANT la depense -- sinon la depense
#       de ce tick appliquerait le cout d'avant le franchissement, et le
#       basculement aurait un tick de retard, invisible mais faux.
static func avancer_tick(
	colons: Array,
	monde,
	delta: float,
	tick_actuel: int,
	config: Dictionary,
	catalogue_canaux: Dictionary,
	catalogue_reproduction: Dictionary,
	catalogue_etats: Dictionary,
	catalogue_seuils: Dictionary,
	catalogue_epigenetique: Dictionary,
	horloges: Dictionary,
) -> Dictionary:
	var infos: Dictionary = {}
	var horloges_apres: Dictionary = {}

	for colon in colons:
		Senescence.avancer(colon, delta, float(config.annees_par_seconde))
		Stade.avancer(colon)
		infos[colon.id] = {"age": float(colon.proprietes.age), "stade": String(colon.proprietes.get("stade", ""))}

	for colon in colons:
		infos[colon.id]["force_effective"] = poser_force_effective(colon, config)

	for colon in colons:
		var marque := avancer_competence(
			colon, float(horloges.get(colon.id, 0.0)), delta, config, catalogue_epigenetique)
		horloges_apres[colon.id] = float(marque.horloge)
		infos[colon.id]["competence"] = competence_effective(colon, config)

	for colon in colons:
		infos[colon.id]["differe"] = poser_accumulateur_differe(colon, delta, config)

	var bascules: Array = SeuilEtat.avancer(colons, catalogue_seuils)

	for colon in colons:
		infos[colon.id]["cout_vie"] = poser_cout_vie(colon, config, catalogue_etats)
	Depense.avancer(colons, delta)

	# Le cycle de reproduction, appele sur TOUT le monde : les gardes de
	# accouplement.gd et le mode lu en donnee suffisent a tenir les temoins
	# dehors, aucun cas particulier ici.
	for colon in colons:
		var perceptions := Perception.percevoir(colon, monde, catalogue_canaux)
		Accouplement.avancer(colon, perceptions, catalogue_reproduction, delta, tick_actuel)
	for colon in colons:
		if colon.proprietes.has("gestation"):
			Gestation.avancer(colon, catalogue_reproduction, delta)

	for colon in colons:
		infos[colon.id]["reserve"] = reserve_vie(colon, config)
		infos[colon.id]["patrimoine"] = reserve_patrimoine(colon, config)

	return {"infos": infos, "horloges": horloges_apres, "bascules": bascules}

static func naissance_prete(colon: Dictionary) -> bool:
	return colon.proprietes.has("gestation") \
		and bool(colon.proprietes.gestation.get("naissance_prete", false))

# ---------------------------------------------------------------------------
# LIGNE 4 : l'heritage
# ---------------------------------------------------------------------------

# heredite.gd produit le kit (genes + marques), ce fichier ne fait que le poser
# sur une coquille construite par le MEME chemin que n'importe quel colon
# declare. genes_actifs vient du PORTEUR : heredite.gd ne le produit jamais.
# Les marques sont ecrasees APRES construire_colon -- a l'age zero, la
# competence de depart ne pose rien, il n'y a donc rien a ecraser en retour.
static func fabriquer_enfant(
	id: String,
	porteur: Dictionary,
	position: Vector3,
	config: Dictionary,
	catalogue_types: Dictionary,
	catalogue_genes: Dictionary,
	catalogue_heredite: Dictionary,
	catalogue_epigenetique: Dictionary,
	rng: RandomNumberGenerator,
) -> Dictionary:
	var kit := Heredite.fabriquer_genes_enfant(porteur, catalogue_heredite, catalogue_epigenetique, rng)
	var decl := {
		"id": id,
		"position": [position.x, position.y, position.z],
		"age_initial": 0.0,
		"genes_actifs": porteur.proprietes.get("genes_actifs", []),
		"genes_etat": kit.genes_etat,
	}
	var enfant := construire_colon(decl, config, catalogue_types, catalogue_genes, catalogue_epigenetique)
	enfant.proprietes["marques_epigenetiques"] = kit.marques_epigenetiques
	return enfant

# LES DEUX TRANSMISSIONS QUE heredite.gd NE FAIT PAS, et la question ouverte.
#
# OBJETS : consommer.gd, transfert DESTRUCTIF qui ne cree aucune matiere -- le
# receveur gagne ce que la source a perdu, pas ce qu'on avait demande. La somme
# parent + enfant est donc invariante, quelle que soit la part reclamee ;
# verrouille par test. delta vaut 1.0, la quantite etant deja resolue par
# l'appelant (meme geste que banc_fertilite.gd:avancer_cadavres).
#
# LIENS : DEUX VOIES OPPOSEES, toutes deux cablees, la decision doctrinale
# laissee ouverte. La voie A pose sur l'enfant une marque a nom compose par
# cible heritee, sous un GATE lu sur le PARENT (lien_personnel.gd:force) : un
# lien faible ne passe pas. La voie B ne pose rien -- l'enfant part neutre.
# CE QUE LA VOIE A COUTE, dit plutot que masque : le registre de lien tire sa
# legitimite d'un evenement VECU, et un enfant qui nait avec les liens de sa
# mere herite d'un vecu qu'il n'a pas eu. La voie B respecte cette regle et
# perd la continuite des lignees. Les deux tournent cote a cote.
static func transmettre_heritage(
	porteur: Dictionary,
	enfant: Dictionary,
	config: Dictionary,
	catalogue_epigenetique: Dictionary,
) -> Dictionary:
	var nom_patrimoine := String(config.nom_reserve_patrimoine)
	var quantite: float = reserve_patrimoine(porteur, config) * float(config.part_heritage_objets)
	var transfere: float = float(Consommer.transferer(
		porteur, enfant, nom_patrimoine, nom_patrimoine, quantite, 1.0).quantite)

	var voie := String(porteur.proprietes.get(CLE_VOIE_LIENS, ""))
	var liens: Array = []
	if voie == "A":
		for cible in porteur.proprietes.get("liens_personnels", {}).keys():
			if LienPersonnel.force(porteur, String(cible), {}) < float(config.seuil_heritage_lien):
				continue
			Epigenetique.poser(enfant, nom_marque_lien_herite(config, String(cible)), catalogue_epigenetique)
			liens.append(String(cible))
	return {"voie": voie, "objets": transfere, "liens": liens}

# Les cibles dont l'enfant porte une marque de lien herite. LECTURE PURE, sur
# l'enfant seul -- jamais sur le journal de la transmission, qui n'existe que
# le temps du tick de la naissance.
static func liens_herites(enfant: Dictionary, config: Dictionary) -> Array:
	var prefixe: String = "%s:" % String(config.get("prefixe_lien_herite", "lien_herite"))
	var cibles: Array = []
	for nom in enfant.proprietes.get("marques_epigenetiques", {}):
		var texte := String(nom)
		if texte.begins_with(prefixe):
			cibles.append(texte.substr(prefixe.length()))
	cibles.sort()
	return cibles

# ---------------------------------------------------------------------------
# Bascules et lectures d'affichage (pures)
# ---------------------------------------------------------------------------

static func facteur_suivant(selection: int, nb_facteurs: int) -> int:
	if nb_facteurs <= 0:
		return 0
	return (selection + 1) % nb_facteurs

# seuil_etat.gd rend les ids ayant bascule, jamais QUELS etats -- d'ou cette
# comparaison de deux instantanes cote cablage. PURE.
static func changements_etats(avant: Array, apres: Array) -> Dictionary:
	var gagnes: Array = []
	var perdus: Array = []
	for etat in apres:
		if not avant.has(etat):
			gagnes.append(String(etat))
	for etat in avant:
		if not apres.has(etat):
			perdus.append(String(etat))
	return {"gagnes": gagnes, "perdus": perdus}

static func texte_etats(colon: Dictionary) -> String:
	var noms: Array = []
	for etat in colon.proprietes.get("etats_actifs", []):
		noms.append(String(etat))
	noms.sort()
	return " + ".join(noms) if not noms.is_empty() else "-"

static func texte_heritage(enfant: Dictionary, heritage: Dictionary, config: Dictionary) -> String:
	var cibles := liens_herites(enfant, config)
	return "voie %s | objets %.1f | liens %s" % [
		String(heritage.get("voie", "?")),
		float(heritage.get("objets", 0.0)),
		", ".join(cibles) if not cibles.is_empty() else "aucun",
	]

static func ligne_pose(config: Dictionary, colons: Array) -> String:
	var morceaux: Array = []
	for colon in colons:
		morceaux.append("%s (age %.0f)" % [String(colon.id), float(colon.proprietes.age)])
	return "t=0.0 %d colons poses -- %s\npic de force %.0f ans, declin %.3f par an, gain de competence par annee lu au catalogue partage -- seuil de l'effet differe : %.0f jours" % [
		colons.size(), " | ".join(morceaux),
		float(config.pic_force_ans), float(config.declin_par_an_apres), 730.0,
	]

static func ligne_facteur(temps: float, facteur: float) -> String:
	return "t=%.1f TEMPS x%.0f" % [temps, facteur]

static func lignes_changement(t: float, id: String, changements: Dictionary) -> Array:
	var lignes: Array = []
	for etat in changements.get("gagnes", []):
		lignes.append("t=%.1f %s etat POSE : %s" % [t, id, String(etat)])
	for etat in changements.get("perdus", []):
		lignes.append("t=%.1f %s etat RETIRE : %s" % [t, id, String(etat)])
	return lignes

static func ligne_naissance(t: float, porteur: Dictionary, enfant: Dictionary, config: Dictionary) -> String:
	var morceaux: Array = []
	for nom_gene in enfant.proprietes.get("genes_actifs", []):
		morceaux.append("%s %s <- %s + %s" % [
			String(nom_gene),
			enfant.proprietes.genes_etat.get(nom_gene, {}).get("alleles", []),
			porteur.proprietes.genes_etat.get(nom_gene, {}).get("alleles", []),
			porteur.proprietes.get("gestation", {}).get("partenaire_genes_etat", {}).get(nom_gene, {}).get("alleles", []),
		])
	return "t=%.1f NAISSANCE %s de %s -- %s | force de base %.3f" % [
		t, String(enfant.id), String(porteur.id),
		" ; ".join(morceaux) if not morceaux.is_empty() else "aucun gene",
		float(enfant.proprietes.get(String(config.nom_force_base), 0.0)),
	]

static func ligne_heritage(t: float, enfant: Dictionary, heritage: Dictionary, config: Dictionary) -> String:
	return "t=%.1f HERITAGE %s -- %s | marque d'annees recue %.4f" % [
		t, String(enfant.id), texte_heritage(enfant, heritage, config),
		modulateur_competence(enfant, config),
	]

static func ligne_trace(t: float, colon: Dictionary, infos: Dictionary, config: Dictionary) -> String:
	return "t=%.1f %s | age %.1f (%s) | force %.3f | competence %.3f | differe %.0f j | cout %.2f | reserve %.1f | %s" % [
		t, String(colon.id),
		float(infos.get("age", 0.0)), String(infos.get("stade", "")),
		float(infos.get("force_effective", 0.0)), float(infos.get("competence", 0.0)),
		float(infos.get("differe", 0.0)), float(infos.get("cout_vie", 0.0)),
		float(infos.get("reserve", 0.0)), texte_etats(colon),
	]

static func texte_label_colon(colon: Dictionary, infos: Dictionary, heritage: Dictionary, config: Dictionary) -> String:
	var ligne_heritee := ""
	if not heritage.is_empty():
		ligne_heritee = "\nherite : %s" % texte_heritage(colon, heritage, config)
	return "%s\nage %.1f  %s\nforce %.3f   competence %.3f\ndiffere %.0f j   cout %.2f\netats : %s%s" % [
		String(colon.id),
		float(infos.get("age", 0.0)), String(infos.get("stade", "")),
		float(infos.get("force_effective", 0.0)), float(infos.get("competence", 0.0)),
		float(infos.get("differe", 0.0)), float(infos.get("cout_vie", 0.0)),
		texte_etats(colon), ligne_heritee,
	]

static func texte_compteur(temps: float, temps_simule: float, facteur: float, colons: Array, config: Dictionary) -> String:
	var differes := 0
	var veterans := 0
	for colon in colons:
		var actifs: Array = colon.proprietes.get("etats_actifs", [])
		if actifs.has(String(config.etat_effet_differe)):
			differes += 1
		if actifs.has(String(config.etat_veteran)):
			veterans += 1
	return "t=%.1f s reelles -- %.1f s simulees (x%.0f) -- %d colons | %s %d | %s %d" % [
		temps, temps_simule, facteur, colons.size(),
		String(config.etat_veteran), veterans,
		String(config.etat_effet_differe), differes,
	]

static func texte_aide() -> String:
	return "clic gauche : accelere le temps (x1 / x4 / x16) -- rien d'autre n'est pilotable, la scene se deroule seule"

# ---------------------------------------------------------------------------
# Rendu (impur, Node) -- aucune decision, seulement des couleurs, des
# rectangles et des longueurs de barre.
# ---------------------------------------------------------------------------

func _couleur(rgb: Array) -> Color:
	return Color(float(rgb[0]), float(rgb[1]), float(rgb[2]))

# La teinte dit l'age SANS qu'on ait a lire le nombre : vert quand on commence,
# gris quand on finit. PURE au sens du calcul (aucun etat du Node lu).
static func teinte_age(age: float, config: Dictionary) -> Color:
	var jeunesse := Color(float(config.couleur_jeunesse[0]), float(config.couleur_jeunesse[1]), float(config.couleur_jeunesse[2]))
	var vieillesse := Color(float(config.couleur_vieillesse[0]), float(config.couleur_vieillesse[1]), float(config.couleur_vieillesse[2]))
	var age_gris: float = float(config.age_gris)
	var fraction: float = clamp(age / age_gris, 0.0, 1.0) if age_gris > 0.0 else 1.0
	return jeunesse.lerp(vieillesse, fraction)

func _construire_rendu() -> void:
	for colon in _colons:
		_labels[colon.id] = _creer_label_colon(colon)

	var couche := CanvasLayer.new()
	add_child(couche)
	_label_compteur = _creer_label(int(_config.taille_police_compteur))
	_label_compteur.position = Vector2(10.0, 10.0)
	couche.add_child(_label_compteur)
	_label_aide = _creer_label(int(_config.taille_police_aide))
	_label_aide.position = Vector2(10.0, 36.0)
	_label_aide.text = texte_aide()
	couche.add_child(_label_aide)

	_poser_camera()

func _creer_label_colon(colon: Dictionary) -> Label:
	var label := _creer_label(int(_config.taille_police_label))
	label.position = Vector2(colon.position.x, colon.position.y) \
		+ Vector2(-float(_config.largeur_barre) / 2.0, float(_config.taille_colon))
	add_child(label)
	return label

func _creer_label(taille: int) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", taille)
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	label.add_theme_constant_override("outline_size", 4)
	return label

func _draw() -> void:
	var largeur: float = float(_config.terrain_largeur)
	var hauteur: float = float(_config.terrain_hauteur)
	draw_rect(Rect2(Vector2(-largeur / 2.0, -hauteur / 2.0), Vector2(largeur, hauteur)),
		_couleur(_config.couleur_fond))

	for colon in _colons:
		var centre := Vector2(colon.position.x, colon.position.y)
		var cote: float = float(_tailles.get(colon.id, float(_config.taille_colon)))
		# Le carre porte la teinte de l'AGE ; le lisere porte la couleur
		# DECLAREE du colon, pour qu'on le retrouve d'un tick a l'autre alors
		# meme que sa teinte vire du vert au gris.
		draw_rect(Rect2(centre - Vector2(cote, cote) / 2.0 - Vector2(3.0, 3.0),
			Vector2(cote + 6.0, cote + 6.0)), _couleurs.get(colon.id, Color.WHITE))
		draw_rect(Rect2(centre - Vector2(cote, cote) / 2.0, Vector2(cote, cote)),
			teinte_age(float(colon.proprietes.get("age", 0.0)), _config))
		_dessiner_barres(colon, centre, cote)

# Trois barres par colon, empilees AU-DESSUS de lui : force effective,
# competence, reserve de vie. La barre de reserve passe au rouge quand l'effet
# differe est actif -- sans ce signal, l'effondrement serait un nombre dans la
# console et rien a l'ecran.
func _dessiner_barres(colon: Dictionary, centre: Vector2, cote: float) -> void:
	var infos: Dictionary = _infos.get(colon.id, {})
	var largeur: float = float(_config.largeur_barre)
	var hauteur: float = float(_config.hauteur_barre)
	var espacement: float = float(_config.espacement_barre)
	var x: float = centre.x - largeur / 2.0
	var y: float = centre.y - cote / 2.0 - float(_config.marge_bloc) - 3.0 * espacement

	var force_max: float = max(0.0001, float(colon.proprietes.get(String(_config.nom_force_base), 1.0)))
	_barre(Vector2(x, y), largeur, hauteur, _couleur(_config.couleur_fond_barre), 1.0)
	_barre(Vector2(x, y), largeur, hauteur, _couleur(_config.couleur_barre_force),
		clamp(float(infos.get("force_effective", 0.0)) / force_max, 0.0, 1.0))

	var plafond: float = max(0.0001, float(_config.plafond_competence))
	_barre(Vector2(x, y + espacement), largeur, hauteur, _couleur(_config.couleur_fond_barre), 1.0)
	_barre(Vector2(x, y + espacement), largeur, hauteur, _couleur(_config.couleur_barre_competence),
		clamp(float(infos.get("competence", 0.0)) / plafond, 0.0, 1.0))

	var capacite: float = max(0.0001, float(_config.capacite_vie))
	var actifs: Array = colon.proprietes.get("etats_actifs", [])
	var couleur_reserve := _couleur(_config.couleur_effet_differe) \
		if actifs.has(String(_config.etat_effet_differe)) else _couleur(_config.couleur_barre_reserve)
	_barre(Vector2(x, y + 2.0 * espacement), largeur, hauteur, _couleur(_config.couleur_fond_barre), 1.0)
	_barre(Vector2(x, y + 2.0 * espacement), largeur, hauteur, couleur_reserve,
		clamp(float(infos.get("reserve", 0.0)) / capacite, 0.0, 1.0))

func _barre(origine: Vector2, largeur: float, hauteur: float, couleur: Color, ratio: float) -> void:
	draw_rect(Rect2(origine, Vector2(largeur * ratio, hauteur)), couleur)

func _rafraichir() -> void:
	for colon in _colons:
		if not _labels.has(colon.id):
			continue
		_labels[colon.id].text = texte_label_colon(
			colon, _infos.get(colon.id, {}), _heritages.get(colon.id, {}), _config)
	_label_compteur.text = texte_compteur(_temps, _temps_simule, _facteur_courant(), _colons, _config)

func _poser_camera() -> void:
	var pos: Array = _config.get("camera_position", [0.0, 0.0])
	var camera := Camera2D.new()
	camera.position = Vector2(float(pos[0]), float(pos[1]))
	camera.zoom = Vector2(float(_config.camera_zoom), float(_config.camera_zoom))
	camera.enabled = true
	add_child(camera)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
