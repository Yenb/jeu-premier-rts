extends Node2D

# Cablage de banc VISUEL, separe des autres bancs (Scene/banc_vecu_inter_colon.tscn,
# PAS la scene principale -- run/main_scene reste banc_p1). Existe pour VOIR
# scripts/lien_personnel_croissance.gd (nouveau mecanisme du coeur, voir
# CARTE.md §2) recevoir son PREMIER CABLAGE REEL SUR DES COLONS ORION :
# la CONTAGION CULTURELLE PAR VECU INTER-COLON -- deux colons qui se
# percoivent mutuellement, en continu, cristallisent chacun une attache au
# trait que l'autre porte ; un troisieme colon d'identite opposee, arrive
# plus tard, se laisse a son tour absorber SANS jamais perdre son identite
# d'origine (les attaches se cumulent, ne s'effacent jamais -- voir
# docs/design.md, "Les collectifs n'existent pas"). JETABLE PAR DEFINITION.
#
# CE QUE CE BANC MONTRE, en trois phases :
# - PHASE 1 (t=0 a ~18s) : deux colons ("colon_vert_1"/"colon_vert_2"),
#   places a 150 unites l'un de l'autre, portent chacun DEPUIS LA NAISSANCE
#   la propriete PLATE "venere_arbres_verts" (trait percu par l'autre, PAS
#   une attache). Chaque tick, chacun percoit l'autre
#   (Perception.percevoir), LienPersonnelCroissance.avancer pose un lien
#   personnel vers lui PAR INTERVALLE (ref catalogue
#   "venere_arbres_verts_croissance", montant_par_pose 0.05 toutes les
#   intervalle_pose 1.0s -- CONVENTION CORRIGEE, voir scripts/
#   lien_personnel_croissance.gd, chantier correction "banc invisible" :
#   un montant FIXE par pose, jamais un debit multiplie par delta, espace
#   par un cooldown pour rester observable), LienPersonnel.avancer le fait
#   decroitre tres lentement en parallele (taux_decroissance 0.001/s,
#   negligeable face a la croissance). Une fois la force au-dela du seuil
#   (0.9, catalogue local "generalisation_verts" -- voir
#   data/banc_vecu_inter_colon.json:catalogue_attaches_par_trait, seuil_nombre
#   SURCHARGE a 1 par colon, chacun n'ayant qu'UN seul partenaire possible en
#   phase 1 -- voir "sensibilite_generalisation" pose a la fabrication),
#   AttacheParTrait.avancer cristallise l'attache generale "venere_arbres_verts"
#   sur chacun. Bascule visuelle : carre gris uni -> carre vert uni. Pendant
#   l'attente, _imprimer_progression (toutes les INTERVALLE_PRINT secondes,
#   PAS a chaque frame) imprime pour chaque colon la force du lien le plus
#   fort et le seuil a atteindre -- sans ce print, rien ne distingue "en
#   cours" de "casse" pendant les ~18s d'attente (voir en-tete, correction
#   "banc invisible", PROBLEME 2).
# - PHASE 2 (a t=60s, data/banc_vecu_inter_colon.json:delai_apparition_troisieme) :
#   un troisieme colon ("colon_rouge_3") est instancie HORS DE TOUTE PORTEE
#   de perception des deux premiers ET hors du champ de la Camera2D
#   (position_apparition_troisieme, distance au colon_vert_2 le plus proche
#   1700 -- strictement au-dela du plus grand rayon possible, vue 1600, marge
#   100 unites deterministe -- CORRECTION session ulterieure "banc invisible" :
#   l'ancienne valeur (4000/4000) etait hors de tout ecran possible ET
#   donnait un trajet interminable a 150 u/s, voir data/
#   banc_vecu_inter_colon.json et _poser_camera ci-dessous), portant DEPUIS
#   LA NAISSANCE "venere_arbres_rouges" (trait plat) ET l'ATTACHE deja
#   cristallisee { propriete: "venere_arbres_rouges", force: 1.0 } (posee
#   directement, JAMAIS par attache_par_trait.gd -- une identite d'origine,
#   pas un vecu). Couleur initiale : carre rouge uni, INVISIBLE a l'ecran (le
#   transit n'est jamais cadre par la Camera2D, par design -- voir
#   _poser_camera). Il se deplace ensuite (BancCommun.bouger_vers, ~12s de
#   trajet) vers position_arret_troisieme, un point PRECALCULE en donnee
#   (milieu geometrique entre les deux colons verts, decale en Y) qui
#   respecte a la fois DISTANCE_ARRET_COLON (>= 30, repliquee depuis
#   banc_p1.gd -- aucun chevauchement visuel) et portee_ecoute (< 400) --
#   aucun calcul de ralentissement a l'execution, le point d'arret encode
#   deja la bonne distance.
# - PHASE 3 (des l'arrivee du troisieme a portee d'ecoute des deux autres) :
#   colon_rouge_3 percoit desormais les deux verts (sa reference de
#   croissance, "venere_arbres_verts_et_rouges_croissance", cherche les DEUX
#   traits "venere_arbres_verts" ET "venere_arbres_rouges" -- mais aucun des
#   deux verts ne porte le trait plat rouge, seul le trait vert matche) :
#   deux liens personnels montent en parallele. Une fois les DEUX au-dela du
#   seuil (catalogue "generalisation_verts", seuil_nombre 2 -- valeur PAR
#   DEFAUT du catalogue, aucune surcharge pour ce colon, contrairement aux
#   deux verts), AttacheParTrait.avancer cristallise "venere_arbres_verts" EN
#   PLUS de son "venere_arbres_rouges" d'origine, jamais a la place. Rendu
#   BICOLORE : bordure rouge, interieur vert -- deux ColorRect superposes
#   (voir _dessiner_colon), jamais un etat visuel separe : le rendu lit
#   TOUJOURS colon.proprietes.attaches (voir _rendu_colon), jamais une
#   variable locale au banc.
#
# CE QUE CE BANC NE FAIT PAS (portee volontairement limitee, meme discipline
# que banc_convergence_attache.gd) : aucun agir.gd, aucune dominance.gd,
# aucune proximite.gd/attaches.gd, aucun verbe resolu -- les attaches
# formees ne sont JAMAIS consommees par une decision ici. Convertir ce fait
# en decision (jugement.gd lit les attaches acquises) est un chantier
# SEPARE, non commence. La DECRISTALLISATION n'existe pas dans le depot :
# les attaches se cumulent, ne s'effacent jamais -- comportement voulu, pas
# une limite a lever ici (voir docs/design.md).
#
# CABLAGE DIRECT, PAS LE PIPELINE A QUATRE COUCHES : comme
# banc_convergence_attache.gd, la ligne generatrice ("un lien monte quand un
# colon percoit un autre colon de maniere repetee, filtre par trait") ne
# passe par AUCUNE decision -- LienPersonnelCroissance.avancer est appele
# directement sur la perception brute, jamais via agir.gd. Seuls
# perception.gd, lien_personnel.gd, lien_personnel_croissance.gd et
# attache_par_trait.gd sont exerces.
#
# CATALOGUE D'ATTACHE PAR TRAIT STRICTEMENT LOCAL (meme discipline que
# data/banc_convergence_attache.json) : "generalisation_verts" ne vit JAMAIS
# dans data/attaches_par_trait.json (partage) -- scopee a
# data/banc_vecu_inter_colon.json:catalogue_attaches_par_trait.
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge data/banc_vecu_inter_colon.json,
#   data/types.json (paquets partages), data/canaux.json,
#   data/liens_personnels.json, data/lien_personnel_croissance.json ;
#   fabrique les deux colons verts (_ajouter_colon_vert) et, a l'heure dite,
#   le troisieme (_ajouter_troisieme) -- ces deux fonctions ne font que
#   cabler _monde/le rendu autour d'une fabrication PURE (voir plus bas) ;
#   pose aussi la Camera2D (_poser_camera, PREMIERE de tout le depot -- voir
#   ce bloc pour le pourquoi). _process avance le pipeline, verifie le delai
#   d'apparition du troisieme, le deplace une fois instancie
#   (BancCommun.bouger_vers), puis rafraichit le rendu de tous les colons.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_vecu_inter_colon.gd) : _fabriquer_colon_vert/_fabriquer_troisieme
#   (fabrication + proprietes locales au banc, sans _monde ni rendu) ;
#   _avancer_tick_pour_colons (UN tick pour une LISTE de colons -- perception
#   -> croissance -> decroissance -> cristallisation) ; _rendu_colon(colon) --
#   lit proprietes.attaches, rend { bordure: Color, interieur: Color },
#   jamais un etat visuel independant ; _force_maximale(colon)/_seuil_force_pour
#   (colon, catalogue_attaches_par_trait) -- lecture pure pour
#   _imprimer_progression (voir plus bas, PROBLEME 2).

const Objet = preload("res://scripts/objet.gd")
const Monde = preload("res://scripts/monde.gd")
const Perception = preload("res://scripts/perception.gd")
const LienPersonnel = preload("res://scripts/lien_personnel.gd")
const LienPersonnelCroissance = preload("res://scripts/lien_personnel_croissance.gd")
const AttacheParTrait = preload("res://scripts/attache_par_trait.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")

const TAILLE_CARRE := 24.0
const TAILLE_INTERIEUR := 14.0

# Zoom fixe de la Camera2D (voir _ready) -- resserre la vue par rapport au
# viewport de base (aucune dimension custom dans project.godot, defaut
# 1152x648) autour du petit groupe de colons (~250x200 unites une fois le
# troisieme arrive) : a zoom 1.0, ce groupe tiendrait noye au centre d'un
# viewport bien plus grand que necessaire -- 2.5 rend les carres 24x24 plus
# lisibles sans jamais couper la zone d'arrivee (demi-largeur visible
# 1152/2/2.5 = 230, demi-hauteur 648/2/2.5 = 130, largement au-dela du point
# d'arret le plus excentre, voir data/banc_vecu_inter_colon.json).
const ZOOM_CAMERA := 2.5

# Repliquee depuis banc_p1.gd (DISTANCE_ARRET_COLON) -- ici jamais consommee
# en calcul a l'execution : position_arret_troisieme (donnee) est
# PRECALCULEE pour deja la respecter (voir en-tete). Conservee comme
# constante nommee pour que le lien avec banc_p1.gd reste explicite et
# verifiable (voir test_banc_vecu_inter_colon.gd).
const DISTANCE_ARRET_COLON := 30.0

const TRAIT_VERT := "venere_arbres_verts"
const TRAIT_ROUGE := "venere_arbres_rouges"

const ID_COLON_1 := "colon_vert_1"
const ID_COLON_2 := "colon_vert_2"
const ID_TROISIEME := "colon_rouge_3"

# PROBLEME 2 (audit "banc ne produit rien") : sans trace intermediaire,
# ~18s d'attente silencieuse (voir lien_personnel_croissance.gd) sont
# indistinguables d'un banc casse. Periodique, PAS a chaque frame (voir
# _imprimer_progression) -- meme discipline que banc_convergence_attache.gd,
# qui imprime a chaque formation d'attache, mais ici rien ne "survient" a
# observer avant la cristallisation : un resume regulier de la PROGRESSION
# (force du lien le plus fort / seuil) comble ce vide.
const INTERVALLE_PRINT := 2.5

# Nom de regle en dur (catalogue_attaches_par_trait n'a qu'UNE entree dans ce
# banc) -- acceptable pour du cablage de banc jetable, meme exception
# CLAUDE.md que "brule"/"combustible" ailleurs dans le depot.
const REGLE_ATTACHE_VERTE := "generalisation_verts"

# Palette FIXE, hors donnee -- _rendu_colon doit rester une fonction statique
# pure (testable sans Node ni disque, voir en-tete) ; purement cosmetique,
# aucune valeur de gameplay, contrairement aux couleurs chargees depuis le
# JSON dans les autres bancs (banc_convergence_attache.gd/banc_contagion.gd),
# qui n'exposent pas de fonction statique de rendu a tester isolement.
const COULEUR_GRIS := Color(0.5, 0.5, 0.5)
const COULEUR_VERT := Color(0.2, 0.8, 0.2)
const COULEUR_ROUGE := Color(0.8, 0.2, 0.2)

var _donnees: Dictionary = {}
var _catalogue_types: Dictionary = {}
var _catalogue_canaux: Dictionary = {}
var _catalogue_liens: Dictionary = {}
var _catalogue_croissance: Dictionary = {}
var _catalogue_attaches_par_trait: Dictionary = {}
var _monde := Monde.new()
var _colons: Array = []
var _noeuds: Dictionary = {}
var _position_arret_troisieme := Vector3.ZERO
var _troisieme_instancie := false
var _temps_ecoule := 0.0
var _temps_depuis_dernier_print := 0.0

func _ready() -> void:
	_donnees = _charger_json("res://data/banc_vecu_inter_colon.json")
	_catalogue_croissance = _charger_json("res://data/lien_personnel_croissance.json")
	_catalogue_liens = _charger_json("res://data/liens_personnels.json")
	_catalogue_canaux = _charger_json("res://data/canaux.json")
	_catalogue_attaches_par_trait = _donnees.get("catalogue_attaches_par_trait", {})

	var types_partages := _charger_json("res://data/types.json")
	_catalogue_types = {
		"objet_physique": types_partages.get("objet_physique", {}),
		"dynamique": types_partages.get("dynamique", {}),
		"percevant": types_partages.get("percevant", {}),
		"agent": types_partages.get("agent", {}),
		"colon": types_partages.get("colon", {}),
	}

	var pos_arret: Array = _donnees.get("position_arret_troisieme", [0.0, 0.0, 0.0])
	_position_arret_troisieme = Vector3(pos_arret[0], pos_arret[1], pos_arret[2])

	var positions: Array = _donnees.get("positions_colons_initiaux", [])
	_ajouter_colon_vert(ID_COLON_1, positions[0])
	_ajouter_colon_vert(ID_COLON_2, positions[1])

	_poser_camera(positions)
	_rafraichir_affichage()

# Camera2D centree sur le MILIEU des deux positions initiales (calcule
# depuis la donnee, jamais une constante dupliquee) -- cadre la zone
# d'arrivee (les deux verts, position_arret_troisieme) en permanence.
# Correction "banc invisible" (session ulterieure a la construction du
# banc) : sans camera, un Node2D s'affiche dans le referentiel monde brut
# (origine en haut a gauche du viewport) -- colon_vert_1 (0,0) y etait deja
# rogne par le bord de l'ecran. Aucun autre banc du depot ne pose de
# Camera2D (patron absent, verifie avant d'ecrire) : celui-ci est le
# PREMIER, motive par le seul besoin reel a ce jour (le troisieme colon
# apparaissait hors de tout ecran possible). Ne cadre JAMAIS le transit du
# troisieme (voir data/banc_vecu_inter_colon.json, position_apparition_troisieme) --
# seulement la zone d'arrivee, par design (voir en-tete du fichier).
func _poser_camera(positions: Array) -> void:
	var pos_1 := Vector3(positions[0][0], positions[0][1], positions[0][2])
	var pos_2 := Vector3(positions[1][0], positions[1][1], positions[1][2])
	var milieu := (pos_1 + pos_2) / 2.0
	var camera := Camera2D.new()
	camera.position = Vector2(milieu.x, milieu.y)
	camera.zoom = Vector2(ZOOM_CAMERA, ZOOM_CAMERA)
	camera.enabled = true
	add_child(camera)

func _ajouter_colon_vert(nom: String, pos: Array) -> void:
	var colon := _fabriquer_colon_vert(nom, pos, _donnees, _catalogue_types)
	_monde.ajouter(colon, "colon", colon.position)
	_colons.append(colon)
	_noeuds[colon.id] = _dessiner_colon(colon.position)

func _ajouter_troisieme() -> void:
	var pos: Array = _donnees.get("position_apparition_troisieme", [0.0, 0.0, 0.0])
	var colon := _fabriquer_troisieme(pos, _donnees, _catalogue_types)
	_monde.ajouter(colon, "colon", colon.position)
	_colons.append(colon)
	_noeuds[colon.id] = _dessiner_colon(colon.position)
	_troisieme_instancie = true

# Fabrication PURE (testable headless, voir test_banc_vecu_inter_colon.gd) --
# ne touche ni _monde ni le rendu, jamais appelee en dehors de
# _ajouter_colon_vert/_ajouter_troisieme et des tests.
static func _fabriquer_colon_vert(nom: String, pos: Array, donnees: Dictionary, catalogue_types: Dictionary) -> Dictionary:
	var position3 := Vector3(pos[0], pos[1], pos[2])
	var colon := Objet.fabriquer(nom, "colon", position3, catalogue_types)
	colon.proprietes[TRAIT_VERT] = true
	colon.proprietes["lien_personnel_croissance_ref"] = donnees.get("ref_croissance_verts", "")
	colon.proprietes["sensibilite_generalisation"] = {
		TRAIT_VERT: {"seuil_nombre": int(donnees.get("seuil_nombre_colon_vert", 1))},
	}
	_appliquer_portee_ecoute(colon, donnees)
	return colon

static func _fabriquer_troisieme(pos: Array, donnees: Dictionary, catalogue_types: Dictionary) -> Dictionary:
	var position3 := Vector3(pos[0], pos[1], pos[2])
	var colon := Objet.fabriquer(ID_TROISIEME, "colon", position3, catalogue_types)
	colon.proprietes[TRAIT_ROUGE] = true
	colon.proprietes["lien_personnel_croissance_ref"] = donnees.get("ref_croissance_troisieme", "")
	colon.proprietes.attaches.append({
		"propriete": TRAIT_ROUGE,
		"force": donnees.get("force_attache_rouge_initiale", 1.0),
	})
	_appliquer_portee_ecoute(colon, donnees)
	return colon

# "Portee d'ecoute" individuelle (decision Yael : sur le colon, pas dans un
# catalogue partage -- meme convention que portee_charge/portee_menace) :
# surcharge ciblee de canaux_config.ouie.portee, DEJA integralement peuple
# par Objet.fabriquer (colon herite "percevant" + redeclare canaux_config en
# entier -- voir data/types.json:colon, "_note") -- mutation d'UNE seule
# sous-cle, jamais un remplacement du Dictionary canaux_config entier (qui
# effacerait silencieusement les cinq autres canaux, voir CARTE.md §6).
static func _appliquer_portee_ecoute(colon: Dictionary, donnees: Dictionary) -> void:
	var portee: float = donnees.get("portee_ecoute", 0.0)
	colon.proprietes.canaux_config.ouie["portee"] = portee

# UN TICK pour une LISTE de colons : pour chacun, percoit (Perception.percevoir,
# reel) -> LienPersonnelCroissance.avancer (croissance filtree par trait) ->
# LienPersonnel.avancer (decroissance) -> AttacheParTrait.avancer
# (cristallisation) -- meme patron que
# banc_convergence_attache.gd:_avancer_tick_pour_colons, jamais de decision
# (voir en-tete). Testable headless (voir test_banc_vecu_inter_colon.gd).
static func _avancer_tick_pour_colons(
	colons: Array,
	monde,
	catalogue_canaux: Dictionary,
	catalogue_croissance: Dictionary,
	catalogue_liens: Dictionary,
	catalogue_attaches_par_trait: Dictionary,
	delta: float,
) -> void:
	for colon in colons:
		var perceptions := Perception.percevoir(colon, monde, catalogue_canaux)
		LienPersonnelCroissance.avancer(colon, perceptions, catalogue_croissance, catalogue_liens, delta)
		LienPersonnel.avancer(colon, delta, catalogue_liens)
		AttacheParTrait.avancer(colon, monde, catalogue_attaches_par_trait)

# Condition d'apparition du troisieme, extraite pour rester testable seule
# (voir test_banc_vecu_inter_colon.gd) : IDEMPOTENTE -- une fois
# troisieme_instancie a true, rend toujours false, jamais une seconde
# instanciation meme longtemps apres le delai.
static func _doit_faire_apparaitre_troisieme(troisieme_instancie: bool, temps_ecoule: float, delai: float) -> bool:
	return not troisieme_instancie and temps_ecoule >= delai

func _process(delta: float) -> void:
	_temps_ecoule += delta
	_avancer_tick_pour_colons(
		_colons, _monde, _catalogue_canaux, _catalogue_croissance, _catalogue_liens,
		_catalogue_attaches_par_trait, delta,
	)

	if _doit_faire_apparaitre_troisieme(_troisieme_instancie, _temps_ecoule, float(_donnees.get("delai_apparition_troisieme", 60.0))):
		_ajouter_troisieme()

	if _troisieme_instancie:
		var troisieme := _colon_par_id(ID_TROISIEME)
		var vitesse: float = troisieme.proprietes.get("vitesse", 150.0)
		troisieme.position = BancCommun.bouger_vers(troisieme.position, _position_arret_troisieme, vitesse, delta)

	_temps_depuis_dernier_print += delta
	if _temps_depuis_dernier_print >= INTERVALLE_PRINT:
		_temps_depuis_dernier_print -= INTERVALLE_PRINT
		_imprimer_progression()

	_rafraichir_affichage()

# Force la plus haute portee par ce colon sur UN lien personnel quelconque --
# 0.0 si liens_personnels est vide (aucun lien encore forme, point neutre
# legitime, jamais une alarme -- meme lecture que LienPersonnel.force sur une
# chose absente). Pure, testable headless.
static func _force_maximale(colon: Dictionary) -> float:
	var maximum := 0.0
	for chose_id in colon.proprietes.liens_personnels:
		maximum = max(maximum, colon.proprietes.liens_personnels[chose_id])
	return maximum

# Seuil a atteindre pour CE colon (regle REGLE_ATTACHE_VERTE, surcharge par
# colon via sensibilite_generalisation deja lue par attache_par_trait.gd --
# meme resolution COLON D'ABORD, CATALOGUE EN REPLI, dupliquee ici en
# LECTURE SEULE pour l'affichage, jamais pour decider). Pure, testable
# headless.
static func _seuil_force_pour(colon: Dictionary, catalogue_attaches_par_trait: Dictionary) -> float:
	var regle: Dictionary = catalogue_attaches_par_trait.get(REGLE_ATTACHE_VERTE, {})
	var trait_vise: String = regle.get("propriete", "")
	var sensibilite: Dictionary = colon.proprietes.get("sensibilite_generalisation", {})
	var surcharge: Dictionary = sensibilite.get(trait_vise, {})
	return surcharge.get("seuil_force", regle.get("seuil_force", 0.0))

# PROBLEME 2 (voir en-tete) : une ligne par colon, toutes les
# INTERVALLE_PRINT secondes -- assez pour suivre la progression sans noyer
# la console (jamais a chaque frame).
func _imprimer_progression() -> void:
	for colon in _colons:
		var force := _force_maximale(colon)
		var seuil := _seuil_force_pour(colon, _catalogue_attaches_par_trait)
		print("t=%.1f %s : lien personnel le plus fort = %.3f / seuil = %.2f" % [_temps_ecoule, colon.id, force, seuil])

func _colon_par_id(id: String) -> Dictionary:
	for colon in _colons:
		if colon.id == id:
			return colon
	return {}

# Lit UNIQUEMENT colon.proprietes.attaches -- jamais un etat visuel separe,
# jamais les traits plats (venere_arbres_verts/rouges, qui ne servent qu'a
# etre PERCUS par autrui, pas a se peindre soi-meme). Aucune attache : gris.
# Une seule : couleur pleine (bordure == interieur). Les deux : bordure
# rouge, interieur vert (l'ordre reflete l'IDENTITE D'ORIGINE en bordure,
# l'IDENTITE ACQUISE au centre -- lecture volontaire, pas neutre, voir
# en-tete).
static func _rendu_colon(colon: Dictionary) -> Dictionary:
	var a_vert := false
	var a_rouge := false
	for attache in colon.get("proprietes", {}).get("attaches", []):
		var propriete: String = attache.get("propriete", "")
		if propriete == TRAIT_VERT:
			a_vert = true
		elif propriete == TRAIT_ROUGE:
			a_rouge = true
	if a_vert and a_rouge:
		return {"bordure": COULEUR_ROUGE, "interieur": COULEUR_VERT}
	elif a_vert:
		return {"bordure": COULEUR_VERT, "interieur": COULEUR_VERT}
	elif a_rouge:
		return {"bordure": COULEUR_ROUGE, "interieur": COULEUR_ROUGE}
	return {"bordure": COULEUR_GRIS, "interieur": COULEUR_GRIS}

func _rafraichir_affichage() -> void:
	for colon in _colons:
		var rendu := _rendu_colon(colon)
		var noeud: Dictionary = _noeuds[colon.id]
		var bordure: ColorRect = noeud.bordure
		var interieur: ColorRect = noeud.interieur
		bordure.color = rendu.bordure
		interieur.color = rendu.interieur
		bordure.position = Vector2(colon.position.x, colon.position.y) - bordure.size / 2.0

# Deux ColorRect superposes : "bordure" (24x24, dessine en premier, occupe
# tout le carre) et "interieur" (14x14, ENFANT de "bordure", centre en
# coordonnees locales) -- quand les deux couleurs sont identiques (gris/vert/
# rouge uni), le carre parait plein ; quand elles divergent (colon hybride),
# l'exterieur reste visible comme un anneau autour de l'interieur. Choix
# retenu plutot qu'un ShaderMaterial (patron ColorRect deja partout dans le
# depot -- banc_p1/banc_feu/banc_charge/banc_convergence_attache/
# banc_contagion --, aucun shader nulle part : voie la moins invasive).
func _dessiner_colon(position3: Vector3) -> Dictionary:
	var bordure := ColorRect.new()
	bordure.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bordure.size = Vector2(TAILLE_CARRE, TAILLE_CARRE)
	bordure.position = Vector2(position3.x, position3.y) - bordure.size / 2.0
	add_child(bordure)

	var interieur := ColorRect.new()
	interieur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	interieur.size = Vector2(TAILLE_INTERIEUR, TAILLE_INTERIEUR)
	interieur.position = (bordure.size - interieur.size) / 2.0
	bordure.add_child(interieur)

	return {"bordure": bordure, "interieur": interieur}

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
