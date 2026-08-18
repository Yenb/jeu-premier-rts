extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_grief.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1). Chantier « grief + bifurcation
# grief » (audit prealable audit_mecaniques_psycho_sociales_prealable.md,
# ligne 7 « CABLABLE, mais pas par la voie decrite » et ligne 8 « CONCEPT NEUF
# REQUIS »). AUCUN MECANISME DU COEUR TOUCHE NI MODIFIE : seuil_etat.gd/
# etat_effectif.gd/dominance.gd/agir.gd/monde.gd/banc_commun.gd sont appeles
# TELS QUELS. scripts/bifurcation.gd est NEUF -- mais c'est un chantier de
# FRAMEWORK, ferme AVANT celui-ci et prouve hors domaine
# (scripts/test_bifurcation.gd), jamais une mecanique bricolee au passage.
#
# CE QU'ON DOIT VOIR. Trois colons, MEMES conditions, MEME seuil de rupture,
# et pourtant trois destins. Le monde est injuste : leur grief monte. Au seuil,
# chacun rompt -- mais le soumis baisse la tete (il travaille encore, plus
# lentement), le rebelle cesse d'obeir (le joueur perd la main sur lui), le
# nomade s'en va vers le bord et disparait. Un clic ameliore les conditions :
# le grief redescend, et sous le seuil chacun redevient ce qu'il etait. Un
# nomade rattrape avant le bord revient a son ouvrage.
#
# ---- CE QUE CE BANC ETABLIT, ET QUI N'EXISTAIT PAS ----
#
# (1) LE PREMIER CUMUL DU DEPOT QUI REDESCEND. Les grandeurs comparees par
# seuil_etat.gd sont jusqu'ici de DEUX familles : celles ACCUMULEES par `+=`
# qui ne redescendent jamais (degats_impact_cumules, duree_maladie_cumulee...)
# et les MIROIRS PLATS recalcules a neuf chaque tick depuis une reserve
# (manque_energie, manque_sommeil...). `grief` est les deux a la fois : il
# ACCUMULE (poser_grief part de la valeur du tick precedent) ET il REDESCEND
# (le terme d'amelioration est soustrait). C'est ce que l'audit ligne 7
# annoncait comme une premiere ; rien dans seuil_etat.gd ne s'y oppose, il ne
# fait que comparer.
#
# (2) LA BIFURCATION EST UN MECANISME, PAS UN CABLAGE. Une entree de
# seuil_etat.gd pose UN nom d'etat, un seul, sans arbitrage (« UNE ENTREE, UN
# SEUL ETAT », en-tete du fichier). Elle ne sait pas choisir entre trois
# sorties selon un biais individuel. D'ou DEUX ETATS DISTINCTS, jamais
# confondus : `rupture_grief`, marqueur pur pose par seuil_etat.gd, qui ne fait
# qu'OUVRIR LA PORTE ; puis `soumis`/`contestataire`/`en_depart`, dont un seul
# est pose par bifurquer() ci-dessous depuis la sortie que Bifurcation.
# selectionner a retenue.
#
# (3) LE BIAIS SEUL DECIDE. Les trois colons partagent tout -- meme seuil, meme
# grief a chaque instant, meme instant de rupture. Seul `biais_grief` differe.
# C'est litteralement « Les archetypes n'existent pas » (docs/design.md) : les
# memes sorties sont offertes a tous, seul le POIDS distingue deux colons.
#
# ---- TROIS ECARTS A LA CONSIGNE, constates sur le disque AVANT d'ecrire ----
#
# (a) « etat : pas utilise directement » n'est PAS exprimable. seuil_etat.gd
# EXIGE le champ `etat` (structurel : entree sans lui -> push_error, entree
# ignoree). Il n'a aucun moyen de signaler un franchissement sans poser un nom.
# Traduit fidelement par un MARQUEUR PUR (`rupture_grief`, effets vides) : il
# ne module rien, il ne fait qu'ouvrir la porte. Voir (2) ci-dessus.
#
# (b) `sens: "coupe"` N'EXISTE PAS, et ne pouvait pas servir. data/
# deformations.json ne connait que "monte" et "baisse", et l'unique lecteur
# reel du champ est proximite.gd:_appliquer_deformation -- ajouter un sens
# obligerait a modifier proximite.gd (et attaches.gd/jugement.gd), c'est-a-dire
# le COEUR. Surtout, meme s'il existait il n'atteindrait jamais une directive :
# une entree de directive est SYNTHETIQUE, construite par le cablage et ajoutee
# a `resultats`, elle ne traverse JAMAIS proximite.gd -- aucune deformation,
# quel que soit son sens, ne peut la moduler. (Et « baisse » a biais 1.0 donne
# deja saillance x (1.0 - 1.0) = 0.0 : la coupure ne demandait aucun sens neuf
# de toute facon.) RETENU A LA PLACE : le GATE PAR ETAT, patron deja ecrit
# trois fois dans le depot pour ce geste exact (banc_elimination_salete.gd,
# banc_conduction.gd, et surtout banc_psycho_social.gd:directive_autorisee,
# dont `etats_vitaux` est recopie ici). Aucune loi recopiee, aucun catalogue
# partage de plus.
#
# (c) `en_depart` ECRASE `vitesse` a 0.0 -- litteralement, comme la consigne le
# demande. Le colon ne travaille plus et ne suit plus aucune directive. Mais un
# colon cense partir serait cloue au sol par cet ecrasement : le mouvement de
# sortie passe donc par `vitesse_sortie` (donnee de banc, pas_de_sortie
# ci-dessous), jamais par `vitesse`. Le mouvement de sortie n'est pas du
# travail, il n'a pas a passer par la propriete que la colonie module.
#
# ---- CE QUE CE BANC NE MONTRE PAS, dit plutot que masque ----
#
# Il ne monte NI perception.gd NI proximite.gd : ses deux entrees de saillance
# (l'ouvrage du colon, la directive du joueur) sont CONSTRUITES par le cablage
# et passees directement a dominance.gd puis agir.gd. Precedents exacts :
# banc_charge.gd:decider construit une entree synthetique, agir.gd:
# _avec_cible_engagee en reinjecte une. L'arbitrage lui-meme, en revanche, est
# REEL et non simule -- Dominance.visibles et Agir.choisir, appeles tels quels :
# la directive doit DEPASSER la saillance de l'ouvrage pour etre suivie
# (agir.gd retient le MEILLEUR score, il n'additionne jamais), et un
# contestataire ne la recoit meme pas.
#
# La demonstration complete du pipeline (perception -> attaches/proximite/
# jugement -> dominance -> agir) vit dans banc_psycho_social.gd et n'a pas a
# etre refaite ici : le sujet de ce banc est le grief et la bifurcation.
#
# ---- PIEGE DE L'AUDIT, constat (D), tenu ----
#
# etat_effectif.gd ne s'applique QUE si quelqu'un l'appelle : aucune couche de
# decision ne passe par lui, banc_commun.gd:agents_rythme lit
# proprietes.rythme BRUTE et depense.gd ne le consulte jamais. Declarer que
# `soumis` module `rythme` par 0.7 dans data/etats.json ne suffit donc JAMAIS.
# rythme_effectif()/vitesse_effective() ci-dessous composent eux-memes la
# valeur avant de s'en servir -- sans ces deux lignes, la modulation de
# `rythme` serait vraie dans le catalogue et sans le moindre effet dans le jeu,
# EN SILENCE, sans qu'aucun test ne rougisse.
#
# ---- Deux moities, meme decoupage que les autres bancs ----
# - Node (impur) : _ready charge les trois fichiers de donnees et construit la
#   scene ; _unhandled_input bascule le mode du monde ; _process appelle
#   UNIQUEMENT avancer() et lit son bilan pour l'affichage et la console --
#   aucune decision dans _process.
# - Fonctions statiques (pures, testables headless, voir test_banc_grief.gd) :
#   construire_colon/construire_ouvrage/construire_monde/poser_grief/
#   bifurquer/sortie_active/directive_autorisee/entree_directive/
#   entree_ouvrage/decider/rythme_effectif/vitesse_effective/pas_de_sortie/
#   bord_le_plus_proche/hors_terrain/avancer_travail/compter_par_etat/avancer,
#   plus les textes d'affichage et de trace.
#
# AUCUN NOM DE PROPRIETE EN DUR : nom_grief/nom_seuil_rupture/nom_vitesse/
# nom_rythme/nom_travail/etat_rupture/sorties/etats_par_sortie arrivent tous de
# data/banc_grief.json -- c'est ce qui permet au test de faire traverser le
# meme code par un domaine entierement invente.

const Bifurcation = preload("res://scripts/bifurcation.gd")
const SeuilEtat = preload("res://scripts/seuil_etat.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")
const Dominance = preload("res://scripts/dominance.gd")
const Agir = preload("res://scripts/agir.gd")
const Monde = preload("res://scripts/monde.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")

const MODE_INJUSTICE := "injustice"
const MODE_AMELIORATION := "amelioration"

var _config: Dictionary = {}
var _etats: Dictionary = {}
var _catalogue_seuils: Dictionary = {}

var _colons: Array = []
var _ouvrages: Dictionary = {}        # id de colon -> chose ouvrage
var _directive: Dictionary = {}
var _monde
var _mode := MODE_INJUSTICE
var _directive_active := true
var _temps := 0.0
var _prochain_print := 0.0

var _fond: ColorRect
var _noeuds: Dictionary = {}          # id -> ColorRect
var _labels: Dictionary = {}          # id -> Label
var _barres: Dictionary = {}          # id -> { fond, remplissage, seuil }
var _noeuds_ouvrage: Dictionary = {}  # id -> ColorRect
var _noeud_directive: ColorRect
var _label_compteur: Label
var _label_aide: Label

func _ready() -> void:
	_config = _charger_json("res://data/banc_grief.json")
	_etats = _charger_json("res://data/etats.json")
	_catalogue_seuils = _charger_json("res://data/seuils_etat.json")

	_directive_active = bool(_config.directive.get("active_au_depart", true))
	_directive = construire_directive(_config)
	for decl in _config.get("colons", []):
		var colon := construire_colon(decl, _config)
		_colons.append(colon)
		_ouvrages[colon.id] = construire_ouvrage(decl, _config)
	_monde = construire_monde(_colons, _ouvrages.values(), _directive, Monde)

	_construire_rendu()
	print(ligne_pose(_colons, _config))
	_rafraichir()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		_mode = MODE_AMELIORATION if _mode == MODE_INJUSTICE else MODE_INJUSTICE
		print(ligne_mode(_temps, _mode))
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_directive_active = not _directive_active
		print(ligne_directive(_temps, _directive_active))

func _process(delta: float) -> void:
	_temps += delta
	var bilan := avancer(_colons, _ouvrages, _directive if _directive_active else null,
		_mode, _config, _etats, _catalogue_seuils, _monde, delta)

	for ligne in lignes_bilan(_temps, bilan, _config):
		print(ligne)

	# Un colon sorti du terrain quitte la colonie : il disparait de la liste que
	# le banc anime ET du Monde. monde.gd n'a AUCUNE fonction de retrait (dette
	# deja recensee) -- le Monde est donc RECONSTRUIT DU NEANT, meme idiome que
	# banc_elimination_salete.gd:monde_sans_dechets et banc_psycho_social.gd.
	if not bilan.partis.is_empty():
		for id in bilan.partis:
			_retirer_rendu(String(id))
		_monde = construire_monde(_colons, _ouvrages.values(), _directive, Monde)

	_rafraichir()
	if _temps >= _prochain_print:
		_prochain_print = _temps + float(_config.intervalle_print)
		print(ligne_trace(_temps, _colons, _mode, _config))

# ---------------------------------------------------------------------------
# Fonctions PURES, testables headless (voir test_banc_grief.gd)
# ---------------------------------------------------------------------------

# Le colon ne porte ni composition ni materiau (construit A LA MAIN, meme
# statut que banc_maladie.gd/banc_faim_thermo.gd/banc_psycho_social.gd) : c'est
# pourquoi le seuil de rupture est pose ICI en propriete plate, et non fusionne
# depuis une fiche materiau. `forme` et `poids_verbes` sont structurelles pour
# dominance.gd et agir.gd ; `etats_actifs` part vide -- aucun etat n'est jamais
# recopie a la main dedans, seuil_etat.gd et bifurquer() sont ses seuls
# ecrivains.
static func construire_colon(decl: Dictionary, config: Dictionary) -> Dictionary:
	var pos: Array = decl.position
	var proprietes: Dictionary = {
		"etats_actifs": [],
		"attaches": [],
		"forme": config.forme_colon.duplicate(true),
		"poids_verbes": config.poids_verbes_colon.duplicate(true),
		"biais_grief": decl.biais_grief.duplicate(true),
	}
	proprietes[String(config.nom_grief)] = float(config.grief_initial)
	proprietes[String(config.nom_seuil_rupture)] = float(config.seuil_rupture)
	proprietes[String(config.nom_vitesse)] = float(config.vitesse_base)
	proprietes[String(config.nom_rythme)] = float(config.rythme_base)
	return {
		"id": String(decl.id),
		"position": Vector3(float(pos[0]), float(pos[1]), float(pos[2])),
		"proprietes": proprietes,
		"action_en_cours": {},
	}

# L'ouvrage est ce a quoi le colon tient de lui-meme -- la saillance
# CONCURRENTE que la directive du joueur doit depasser pour etre suivie. Il
# porte `travail_restant`, consomme au RYTHME EFFECTIF du colon : c'est ce qui
# rend le x0.7 de `soumis` sur `rythme` visible autrement que dans un label.
static func construire_ouvrage(decl: Dictionary, config: Dictionary) -> Dictionary:
	var pos: Array = decl.ouvrage
	var proprietes: Dictionary = { "ouvrage": true }
	proprietes[String(config.nom_travail)] = float(config.travail_initial)
	return {
		"id": "ouvrage_%s" % String(decl.id),
		"position": Vector3(float(pos[0]), float(pos[1]), float(pos[2])),
		"proprietes": proprietes,
		"type_banc": "ouvrage",
	}

static func construire_directive(config: Dictionary) -> Dictionary:
	var pos: Array = config.directive.position
	return {
		"id": String(config.directive.id),
		"position": Vector3(float(pos[0]), float(pos[1]), float(pos[2])),
		"proprietes": { "point_rassemblement": true },
		"type_banc": "point_rassemblement",
	}

# `classe_monde` est recu en PARAMETRE (jamais preload ici) pour que le test
# puisse construire le meme Monde sans dependre d'un chemin ecrit deux fois.
static func construire_monde(colons: Array, ouvrages: Array, directive: Dictionary, classe_monde):
	var monde = classe_monde.new()
	for colon in colons:
		monde.ajouter(colon, "colon", colon.position)
	for ouvrage in ouvrages:
		monde.ajouter(ouvrage, "ouvrage", ouvrage.position)
	monde.ajouter(directive, "point_rassemblement", directive.position)
	return monde

# UNIQUE ECRIVAIN de proprietes.<nom_grief> dans tout ce fichier -- meme
# discipline que banc_faim_thermo.gd:poser_surcout_action (constat C de
# l'audit) : deux morceaux de cablage qui ecriraient chacun leur terme
# s'ecraseraient EN SILENCE, sans qu'aucun test ne rougisse.
#
# LES DEUX TERMES SONT TOUJOURS NON NULS, dans les deux modes (voir
# data/banc_grief.json) : le mode ne fait que dire lequel domine. BORNE A ZERO
# PAR LE BAS ICI, et nulle part ailleurs : aucun mecanisme du coeur ne borne
# une propriete plate (meme constat que « rien ne borne le HAUT d'une reserve »,
# banc_fertilite.gd). Rend le grief obtenu.
static func poser_grief(colon: Dictionary, mode: String, config: Dictionary, delta: float) -> float:
	var gain: float = float(config.gain_base_par_s)
	var perte: float = float(config.perte_base_par_s)
	if mode == MODE_INJUSTICE:
		gain = float(config.gain_injustice_par_s)
	else:
		perte = float(config.perte_amelioration_par_s)
	var nom := String(config.nom_grief)
	var valeur: float = max(0.0, float(colon.proprietes.get(nom, 0.0)) + (gain - perte) * delta)
	colon.proprietes[nom] = valeur
	return valeur

# La sortie ACTUELLEMENT posee sur ce colon, ou "" -- lue depuis etats_actifs,
# jamais memorisee a cote (une memoire parallele divergerait du jour ou un
# autre mecanisme retirerait l'etat).
static func sortie_active(colon: Dictionary, config: Dictionary) -> String:
	var actifs: Array = colon.proprietes.get("etats_actifs", [])
	var par_sortie: Dictionary = config.etats_par_sortie
	for sortie in config.sorties:
		if actifs.has(String(par_sortie.get(String(sortie), ""))):
			return String(sortie)
	return ""

# LE COEUR DU CHANTIER. Appelee APRES SeuilEtat.avancer, elle ne fait que lire
# le marqueur `rupture_grief` et en tirer les consequences :
# - marqueur present et aucune sortie encore posee -> Bifurcation.selectionner
#   choisit, l'etat correspondant est pose ;
# - marqueur absent et une sortie posee -> l'etat est retire (REVERSIBILITE :
#   ameliorer les conditions defait la rupture, un nomade rattrape avant le
#   bord revient a son ouvrage) ;
# - marqueur present ET sortie deja posee -> RIEN. La bifurcation ne se rejoue
#   pas a chaque tick : un colon ne change pas d'avis tant qu'il n'est pas
#   redescendu sous son seuil. Sans cette garde, le grief continuant de monter,
#   selectionner serait rappele chaque image et empilerait les etats.
# Une sortie rendue vide par bifurcation.gd (biais entierement nul, ou grandeur
# non positive) ne pose RIEN et n'alarme pas -- un colon qui ne penche pour
# rien est legitime, le mecanisme le dit deja dans son en-tete.
# Rend { id, sortie, sens } pour chaque colon ayant bascule, jamais l'etat.
static func bifurquer(colons: Array, config: Dictionary) -> Array:
	var bascules: Array = []
	var nom_grief := String(config.nom_grief)
	var etat_rupture := String(config.etat_rupture)
	var par_sortie: Dictionary = config.etats_par_sortie
	for colon in colons:
		var actifs: Array = colon.proprietes.get("etats_actifs", [])
		var rompu: bool = actifs.has(etat_rupture)
		var deja: String = sortie_active(colon, config)
		if rompu and deja == "":
			var grief: float = float(colon.proprietes.get(nom_grief, 0.0))
			var biais: Dictionary = colon.proprietes.get("biais_grief", {})
			var sortie: String = Bifurcation.selectionner(grief, biais, config.sorties)
			if sortie == "":
				continue
			var nom_etat := String(par_sortie.get(sortie, ""))
			if nom_etat == "":
				push_error("banc_grief : sortie '%s' sans etat dans etats_par_sortie" % sortie)
				continue
			actifs.append(nom_etat)
			colon.proprietes["etats_actifs"] = actifs
			bascules.append({"id": colon.id, "sortie": sortie, "sens": "pose"})
		elif not rompu and deja != "":
			actifs.erase(String(par_sortie.get(deja, "")))
			colon.proprietes["etats_actifs"] = actifs
			bascules.append({"id": colon.id, "sortie": deja, "sens": "retire"})
	return bascules

# GATE PAR ETAT -- patron RECOPIE de banc_psycho_social.gd:directive_autorisee
# (deux bancs jetables ne se referencent jamais entre eux). C'est ce qui donne
# son role au marqueur pur data/etats.json:contestataire : un colon qui porte
# l'un des `etats_vitaux` ne recoit tout simplement pas l'entree de directive.
# Voir l'ecart (b) en tete de fichier -- la voie `deformation.gd sens "coupe"`
# de la consigne n'existe pas et ne pouvait pas atteindre une entree
# synthetique.
static func directive_autorisee(colon: Dictionary, config: Dictionary) -> bool:
	var actifs: Array = colon.proprietes.get("etats_actifs", [])
	for etat in config.directive.get("etats_vitaux", []):
		if actifs.has(String(etat)):
			return false
	return true

# UNE SAILLANCE CONCURRENTE DE PLUS, jamais un reglage du comportement
# (docs/design.md, « Ordre et tension »). Rend null -- et l'appelant n'ajoute
# alors rien -- quand la directive est coupee par le joueur ou par le gate.
static func entree_directive(colon: Dictionary, directive, config: Dictionary):
	if directive == null:
		return null
	if not directive_autorisee(colon, config):
		return null
	return {
		"chose": directive,
		"type": String(directive.get("type_banc", "point_rassemblement")),
		"position": directive.position,
		"saillance": float(config.directive.bonus_score),
		"directive": true,
	}

# L'ouvrage cesse d'etre saillant quand il n'y a plus rien a y faire -- meme
# geste que proximite.gd:_poids_avancement, ici reduit a « fini ou pas » : ce
# banc n'a pas de perception, il n'y a aucune saillance nue a ponderer.
static func entree_ouvrage(ouvrage, config: Dictionary):
	if ouvrage == null:
		return null
	if float(ouvrage.proprietes.get(String(config.nom_travail), 0.0)) <= 0.0:
		return null
	return {
		"chose": ouvrage,
		"type": String(ouvrage.get("type_banc", "ouvrage")),
		"position": ouvrage.position,
		"saillance": float(config.saillance_ouvrage),
	}

# Deux entrees SYNTHETIQUES (voir en-tete, « CE QUE CE BANC NE MONTRE PAS »),
# puis l'arbitrage REEL : dominance.gd ecrase ce qui est trop loin du sommet,
# agir.gd retient le meilleur score et resout le verbe. Rend { decision,
# resultats, visibles }.
static func decider(colon: Dictionary, ouvrage, directive, config: Dictionary, monde) -> Dictionary:
	var resultats: Array = []
	var e_ouvrage = entree_ouvrage(ouvrage, config)
	if e_ouvrage != null:
		resultats.append(e_ouvrage)
	var e_directive = entree_directive(colon, directive, config)
	if e_directive != null:
		resultats.append(e_directive)
	if resultats.is_empty():
		return {"decision": null, "resultats": resultats, "visibles": []}
	var visibles := Dominance.visibles(resultats, colon)
	var decision = Agir.choisir(visibles, colon, config.catalogue_local, monde)
	return {"decision": decision, "resultats": resultats, "visibles": visibles}

# Voir le PIEGE DE L'AUDIT en tete : sans ces deux fonctions, les effets
# declares dans data/etats.json n'auraient AUCUN effet reel, en silence.
static func vitesse_effective(colon: Dictionary, config: Dictionary, etats: Dictionary) -> float:
	return EtatEffectif.valeur(colon, String(config.nom_vitesse), etats)

static func rythme_effectif(colon: Dictionary, config: Dictionary, etats: Dictionary) -> float:
	return EtatEffectif.valeur(colon, String(config.nom_rythme), etats)

# Le bord le plus proche, sur x ou sur y -- le colon sort par ou il est deja le
# plus pres, jamais par un bord choisi d'avance.
static func bord_le_plus_proche(position: Vector3, config: Dictionary) -> Vector3:
	var largeur: float = float(config.terrain_largeur)
	var hauteur: float = float(config.terrain_hauteur)
	var distances := [position.x, largeur - position.x, position.y, hauteur - position.y]
	var index := 0
	for i in range(1, distances.size()):
		if distances[i] < distances[index]:
			index = i
	var marge: float = float(config.marge_bord)
	match index:
		0: return Vector3(-marge, position.y, position.z)
		1: return Vector3(largeur + marge, position.y, position.z)
		2: return Vector3(position.x, -marge, position.z)
		_: return Vector3(position.x, hauteur + marge, position.z)

# Le mouvement de sortie passe par `vitesse_sortie`, JAMAIS par `vitesse` --
# que data/etats.json:en_depart ecrase a 0.0. Voir l'ecart (c) en tete.
static func pas_de_sortie(colon: Dictionary, config: Dictionary, delta: float) -> Vector3:
	var cible := bord_le_plus_proche(colon.position, config)
	return BancCommun.bouger_vers(colon.position, cible, float(config.vitesse_sortie), delta)

static func hors_terrain(position: Vector3, config: Dictionary) -> bool:
	return position.x <= 0.0 or position.y <= 0.0 \
		or position.x >= float(config.terrain_largeur) \
		or position.y >= float(config.terrain_hauteur)

# Consomme le travail au RYTHME EFFECTIF, et seulement si le colon est
# reellement sur son ouvrage. Borne a zero : un ouvrage fini ne creuse pas.
static func avancer_travail(ouvrage, colon: Dictionary, rythme: float, config: Dictionary, delta: float) -> float:
	if ouvrage == null:
		return 0.0
	var nom := String(config.nom_travail)
	var restant: float = float(ouvrage.proprietes.get(nom, 0.0))
	if restant <= 0.0:
		return 0.0
	if colon.position.distance_to(ouvrage.position) > float(config.rayon_arrivee):
		return restant
	restant = max(0.0, restant - rythme * delta)
	ouvrage.proprietes[nom] = restant
	return restant

static func compter_par_etat(colons: Array, config: Dictionary) -> Dictionary:
	var comptes: Dictionary = {"neutre": 0}
	for sortie in config.sorties:
		comptes[String(sortie)] = 0
	for colon in colons:
		var sortie := sortie_active(colon, config)
		if sortie == "":
			comptes["neutre"] += 1
		else:
			comptes[sortie] += 1
	return comptes

# LE TICK ENTIER, en une fonction pure et testable (Regle d'etat, CLAUDE.md :
# ce qui a marche une fois sort de _process pour etre verrouille). MUTE les
# colons et les ouvrages en place ; RETIRE de `colons` ceux qui ont franchi le
# bord. Ordre, et il n'est pas interchangeable :
#   1. le grief bouge      (poser_grief, unique ecrivain)
#   2. le seuil tranche    (SeuilEtat.avancer, mecanisme du coeur tel quel)
#   3. la bifurcation pose (bifurquer -> Bifurcation.selectionner)
#   4. les effets agissent (vitesse/rythme effectifs, decision, mouvement)
# Inverser 2 et 3 ferait bifurquer sur le marqueur du tick PRECEDENT ; mettre 1
# apres 2 comparerait un grief perime.
static func avancer(
	colons: Array,
	ouvrages: Dictionary,
	directive,
	mode: String,
	config: Dictionary,
	etats: Dictionary,
	catalogue_seuils: Dictionary,
	monde,
	delta: float,
) -> Dictionary:
	for colon in colons:
		poser_grief(colon, mode, config, delta)

	# Catalogue COMPLET passe tel quel : les autres entrees (point_fusion,
	# faim, hygiene...) comparent des proprietes que ces colons ne portent pas
	# -- chemins morts silencieux, aucune collision possible.
	SeuilEtat.avancer(colons, catalogue_seuils)
	var bascules := bifurquer(colons, config)

	var partis: Array = []
	var decisions: Dictionary = {}
	for colon in colons:
		var sortie := sortie_active(colon, config)
		var rythme := rythme_effectif(colon, config, etats)
		var ouvrage = ouvrages.get(colon.id, null)

		if sortie == "depart":
			colon.position = pas_de_sortie(colon, config, delta)
			decisions[colon.id] = {"decision": null, "resultats": [], "visibles": []}
			if hors_terrain(colon.position, config):
				partis.append(colon.id)
			continue

		var r := decider(colon, ouvrage, directive, config, monde)
		decisions[colon.id] = r
		if r.decision != null and r.decision.has("position"):
			var vitesse := vitesse_effective(colon, config, etats)
			colon.position = BancCommun.bouger_vers(colon.position, r.decision.position, vitesse, delta)
			colon.action_en_cours = Agir.etat_courant(r.decision)
		avancer_travail(ouvrage, colon, rythme, config, delta)

	for id in partis:
		for i in range(colons.size() - 1, -1, -1):
			if colons[i].id == id:
				colons.remove_at(i)

	return {"bascules": bascules, "partis": partis, "decisions": decisions}

# ---------------------------------------------------------------------------
# Textes (purs eux aussi : le test les verrouille sans ouvrir la scene)
# ---------------------------------------------------------------------------

static func texte_colon(colon: Dictionary, config: Dictionary, etats: Dictionary) -> String:
	var sortie := sortie_active(colon, config)
	var biais: Dictionary = colon.proprietes.get("biais_grief", {})
	var parts: Array = []
	for nom_sortie in config.sorties:
		parts.append("%s %.2f" % [String(nom_sortie), float(biais.get(String(nom_sortie), 0.0))])
	return "%s\ngrief %.1f / %.1f\nbiais : %s\nsortie : %s\nvitesse %.1f -- rythme %.2f" % [
		String(colon.id),
		float(colon.proprietes.get(String(config.nom_grief), 0.0)),
		float(colon.proprietes.get(String(config.nom_seuil_rupture), 0.0)),
		", ".join(parts),
		sortie if sortie != "" else "-",
		vitesse_effective(colon, config, etats),
		rythme_effectif(colon, config, etats),
	]

static func texte_compteur(colons: Array, config: Dictionary, mode: String, temps: float, directive_active: bool) -> String:
	var comptes := compter_par_etat(colons, config)
	var parts: Array = ["neutre %d" % int(comptes.neutre)]
	for sortie in config.sorties:
		parts.append("%s %d" % [String(sortie), int(comptes[String(sortie)])])
	return "t=%.1f s -- monde : %s -- directive : %s -- colons : %s (partis %d)" % [
		temps, mode, "posee" if directive_active else "levee",
		"  ".join(parts), int(config.colons.size()) - colons.size(),
	]

static func ligne_pose(colons: Array, config: Dictionary) -> String:
	var noms: Array = []
	for colon in colons:
		noms.append(String(colon.id))
	return "t=0.0 %d colons poses, seuil de rupture %.1f, grief initial %.1f -- %s" % [
		colons.size(), float(config.seuil_rupture), float(config.grief_initial), ", ".join(noms),
	]

static func ligne_mode(t: float, mode: String) -> String:
	return "t=%.1f MONDE : %s" % [t, mode]

static func ligne_directive(t: float, active: bool) -> String:
	return "t=%.1f DIRECTIVE : %s" % [t, "posee" if active else "levee"]

static func ligne_trace(t: float, colons: Array, mode: String, config: Dictionary) -> String:
	var parts: Array = []
	for colon in colons:
		var sortie := sortie_active(colon, config)
		parts.append("%s %.1f%s" % [
			String(colon.id),
			float(colon.proprietes.get(String(config.nom_grief), 0.0)),
			"" if sortie == "" else " [%s]" % sortie,
		])
	return "t=%.1f (%s) grief : %s" % [t, mode, "  ".join(parts)]

static func lignes_bilan(t: float, bilan: Dictionary, _config: Dictionary) -> Array:
	var lignes: Array = []
	for bascule in bilan.get("bascules", []):
		if String(bascule.sens) == "pose":
			lignes.append("t=%.1f BIFURCATION : %s -> %s" % [t, String(bascule.id), String(bascule.sortie)])
		else:
			lignes.append("t=%.1f RETOUR : %s quitte '%s' (grief redescendu)" % [t, String(bascule.id), String(bascule.sortie)])
	for id in bilan.get("partis", []):
		lignes.append("t=%.1f DEPART : %s a quitte la colonie" % [t, String(id)])
	return lignes

# ---------------------------------------------------------------------------
# Rendu (impur, Node) -- aucune decision, seulement des noeuds et une camera.
# ---------------------------------------------------------------------------

func _construire_rendu() -> void:
	_fond = ColorRect.new()
	_fond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fond.size = Vector2(4000.0, 3000.0)
	_fond.position = Vector2(-2000.0, -1500.0)
	add_child(_fond)

	for id in _ouvrages:
		_noeuds_ouvrage[id] = _creer_carre(_ouvrages[id].position, float(_config.taille_chose), _config.couleurs.ouvrage)
	_noeud_directive = _creer_carre(_directive.position, float(_config.taille_chose), _config.couleurs.directive)

	for colon in _colons:
		_creer_rendu_colon(colon)

	var couche := CanvasLayer.new()
	add_child(couche)
	_label_compteur = _creer_label(17)
	_label_compteur.position = Vector2(12.0, 10.0)
	couche.add_child(_label_compteur)
	_label_aide = _creer_label(13)
	_label_aide.position = Vector2(12.0, 36.0)
	_label_aide.text = "clic GAUCHE : injustice <-> amelioration    clic DROIT : poser / lever la directive"
	couche.add_child(_label_aide)

	_poser_camera()

func _creer_carre(position: Vector3, taille: float, rgb: Array) -> ColorRect:
	var noeud := ColorRect.new()
	noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noeud.size = Vector2(taille, taille)
	noeud.position = Vector2(position.x, position.y) - noeud.size / 2.0
	noeud.color = _couleur(rgb)
	add_child(noeud)
	return noeud

func _creer_rendu_colon(colon: Dictionary) -> void:
	var taille: float = float(_config.taille_colon)
	_noeuds[colon.id] = _creer_carre(colon.position, taille, _config.couleurs.neutre)

	var label := _creer_label(13)
	add_child(label)
	_labels[colon.id] = label

	var largeur: float = float(_config.largeur_barre)
	var hauteur: float = float(_config.hauteur_barre)
	var origine := Vector2(colon.position.x - largeur / 2.0, colon.position.y + taille)

	var fond := ColorRect.new()
	fond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fond.size = Vector2(largeur, hauteur)
	fond.position = origine
	fond.color = _couleur(_config.couleurs.barre_fond)
	add_child(fond)

	var remplissage := ColorRect.new()
	remplissage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	remplissage.size = Vector2(0.0, hauteur)
	remplissage.position = origine
	remplissage.color = _couleur(_config.couleurs.barre_grief)
	add_child(remplissage)

	# Le trait de seuil est place depuis le seuil REEL porte par le colon,
	# jamais depuis un nombre recopie : la barre ne peut pas mentir sur ce que
	# seuil_etat.gd compare.
	var marque := ColorRect.new()
	marque.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marque.size = Vector2(2.0, hauteur)
	marque.position = origine + Vector2(largeur - 2.0, 0.0)
	marque.color = _couleur(_config.couleurs.seuil)
	add_child(marque)

	_barres[colon.id] = {"fond": fond, "remplissage": remplissage, "seuil": marque}

func _retirer_rendu(id: String) -> void:
	for table in [_noeuds, _labels]:
		if table.has(id):
			table[id].queue_free()
			table.erase(id)
	if _barres.has(id):
		for cle in _barres[id]:
			_barres[id][cle].queue_free()
		_barres.erase(id)

func _rafraichir() -> void:
	_fond.color = _couleur(_config.couleurs.fond_injustice if _mode == MODE_INJUSTICE else _config.couleurs.fond_amelioration)
	_noeud_directive.visible = _directive_active
	for colon in _colons:
		var taille: float = float(_config.taille_colon)
		var centre := Vector2(colon.position.x, colon.position.y)
		var noeud: ColorRect = _noeuds[colon.id]
		noeud.position = centre - noeud.size / 2.0
		var sortie := sortie_active(colon, _config)
		var cle_couleur: String = "neutre" if sortie == "" else String(_config.etats_par_sortie[sortie])
		noeud.color = _couleur(_config.couleurs[cle_couleur])
		_labels[colon.id].position = centre + Vector2(taille, -taille)
		_labels[colon.id].text = texte_colon(colon, _config, _etats)
		_rafraichir_barre(colon)
	_label_compteur.text = texte_compteur(_colons, _config, _mode, _temps, _directive_active)

func _rafraichir_barre(colon: Dictionary) -> void:
	var barre: Dictionary = _barres[colon.id]
	var seuil: float = float(colon.proprietes.get(String(_config.nom_seuil_rupture), 0.0))
	var grief: float = float(colon.proprietes.get(String(_config.nom_grief), 0.0))
	var ratio: float = clamp(grief / seuil, 0.0, 1.0) if seuil > 0.0 else 0.0
	var largeur: float = float(_config.largeur_barre)
	var origine := Vector2(colon.position.x - largeur / 2.0, colon.position.y + float(_config.taille_colon))
	barre.fond.position = origine
	barre.remplissage.position = origine
	barre.remplissage.size = Vector2(largeur * ratio, float(_config.hauteur_barre))
	barre.seuil.position = origine + Vector2(largeur - 2.0, 0.0)

func _creer_label(taille: int) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", taille)
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	label.add_theme_constant_override("outline_size", 4)
	return label

func _couleur(rgb: Array) -> Color:
	return Color(float(rgb[0]), float(rgb[1]), float(rgb[2]))

func _poser_camera() -> void:
	var camera := Camera2D.new()
	camera.position = Vector2(float(_config.terrain_largeur), float(_config.terrain_hauteur)) / 2.0
	camera.zoom = Vector2(0.85, 0.85)
	camera.enabled = true
	add_child(camera)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
