extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_humidite.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1). PREMIERE demonstration reelle
# du chantier "humidite -- pose automatique de mouille" : charge.gd (deja
# ferme, deja cable sur banc_charge.gd/banc_contagion.gd) fait monter une
# charge d'humidite tant qu'une SOURCE (un objet portant une propriete
# d'emission, comme un feu porte "brule") est a portee, franchit un seuil,
# et ce franchissement declenche EtatDuree.poser("mouille") -- le meme
# mecanisme de decroissance progressive deja demontre par banc_etat_duree/
# banc_inflammabilite, jamais reecrit. Noms de domaine reels (bois/pierre/
# fer/mouille), exception documentee CLAUDE.md ("un banc jetable peut nommer
# une categorie pour poser une scene d'observation").
#
# AUCUN MECANISME DU COEUR TOUCHE : charge.gd/etat_duree.gd/etat_effectif.gd/
# objet.gd restent inchanges. Ce fichier est un CABLAGE seul (plus une ligne
# de donnee : "absorption_humidite" ajoutee a data/proprietes_immuables_
# composition.json, meme patron que inflammabilite/point_ignition).
#
# POURQUOI CHARGE.GD NE POSE PAS "MOUILLE" DIRECTEMENT (decision Yael,
# constat pose avant d'ecrire ce fichier) : le "poser" de charge.gd est une
# ecriture/effacement SYMETRIQUE de cles au franchissement -- poser
# etats_actifs/etats_intensite directement dedans ferait secher l'objet
# INSTANTANEMENT au franchissement descendant, jamais PROGRESSIVEMENT.
# Ce fichier fait donc poser a charge.gd un simple marqueur booleen
# (proprietes.expose_humidite, meme patron que "effraye" dans banc_charge.gd),
# et c'est LE CABLAGE, ici, qui appelle EtatDuree.poser("mouille") tant que
# ce marqueur est vrai -- CHAQUE TICK d'exposition, pas seulement au
# franchissement (EtatDuree.poser remet l'intensite a 1.0, jamais un cumul,
# voir sa doctrine REPOSE : rearroser un objet deja mouille le laisse a
# pleine humidite, exactement l'effet voulu tant que la source reste a
# portee). Des que le marqueur retombe (source eloignee/coupee), plus aucun
# repos n'est appele : EtatDuree.avancer(), deja tourne CHAQUE tick dans ce
# banc, seche alors l'objet PROGRESSIVEMENT sur data/etats.json:mouille.duree
# (6.0s) -- exactement le mecanisme deja demontre par banc_etat_duree, jamais
# reecrit ici.
#
# POURQUOI UN APPEL A Charge.avancer() PAR OBJET (decision Yael) :
# absorption_humidite doit moduler la VITESSE DE MONTEE, mais charge.gd
# n'a aucun coefficient par objet RECEVEUR -- un seul appel a
# Charge.avancer(monde, causes, delta) applique la MEME somme de poids de
# causes a tous les objets du monde. avancer() ci-dessous appelle donc
# Charge.avancer([objet], causes_ponderees, delta) UNE FOIS PAR OBJET CIBLE,
# avec un tableau de causes propre a cet objet ou le poids de la source est
# PRE-MULTIPLIE par l'absorption_humidite de CET objet -- zero ligne de
# charge.gd changee, un usage different de banc_charge.gd/banc_contagion.gd
# (qui l'appellent une seule fois pour tout le monde, poids uniforme).
#
# CE QU'ON DOIT VOIR : une source d'humidite fixe (clic gauche : bascule
# active/inactive, marqueur au sol) expose en permanence cinq objets
# alignes (data/banc_humidite.json). Chacun affiche sa charge d'humidite
# courante, son absorption, sa porosite, son etat (sec/expose/mouille),
# l'intensite de mouille et l'inflammabilite EFFECTIVE (EtatEffectif.valeur,
# jamais reimplementee). Le bois mouille vite (absorption haute), la pierre
# lentement, le fer quasiment jamais en pratique (absorption 0.01,
# materiaux.json) -- trois vitesses qui isolent l'effet d'absorption_humidite
# seule. dense_mixte/poreux_mixte isolent l'effet de la POROSITE seule :
# memes deux objets a absorption_humidite RIGOUREUSEMENT IDENTIQUE (0.05,
# composition mixte dosee, voir data/banc_humidite.json._note), seule leur
# porosite diverge (0.0536 contre 0.525) -- poreux_mixte doit monter
# visiblement plus vite que dense_mixte malgre une absorption egale. Couper la
# source (clic) fait redescendre la charge de chaque objet expose ; une fois
# le marqueur retire, l'objet deja mouille seche PROGRESSIVEMENT sur 6s
# (EtatDuree.avancer, deja demontre) -- jamais un retrait instantane.
#
# LIMITE CONNUE, ASSUMEE (consequence directe de reutiliser EtatDuree.poser
# tel quel, jamais modifie) : si la source reste active en continu, ce
# cablage RE-POSE "mouille" a chaque tick tant que le marqueur est vrai --
# c'est CE geste, pas un defaut, qui evite qu'un objet immobile pres d'une
# source permanente ne seche au bout de 6s malgre une exposition continue.
#
# POROSITE COMME FACTEUR DE VITESSE D'ABSORPTION (chantier "porosite -- la
# porosite comme facteur de vitesse d'absorption") : absorption_humidite
# reste le SEUL coefficient que charge.gd connaisse par receveur (voir
# ci-dessus) ; la porosite s'ajoute PAR-DESSUS, jamais a la place --
# poids_receveur = absorption_humidite * (1.0 + facteur_porosite *
# porosite_effective), meme patron multiplicatif que objet.gd:
# _fabriquer_reserve_combustible (cout_base_effectif module par la
# porosite au numerateur). "facteur_porosite" vit en donnee
# (data/banc_humidite.json), jamais en dur ici -- valeur reprise de
# docs/orion-matrice-elements.md, colonne Humidite. La porosite EST LUE A
# LA DEMANDE depuis materiaux.json (jamais fusionnee sur proprietes,
# jamais ecrite dessus) -- exactement le patron d'objet.gd:
# _moyenne_ponderee_volume, mais RECOPIE LOCALEMENT (fonction
# porosite_ponderee ci-dessous) plutot que d'appeler la fonction privee
# d'objet.gd : meme discipline que causes_de/causes_ponderees, deja
# recopiees localement plutot que descendues dans un fichier partage. Un
# objet SANS "composition" (donc porosite non calculable) rend une
# porosite de 0.0 -- poids_receveur retombe alors exactement sur
# "absorption_humidite" seul, comportement RIGOUREUSEMENT IDENTIQUE a
# avant ce chantier (non-regression, verrouillee par test_banc_humidite.gd).
#
# LIMITE STRICTE (rappel explicite du chantier) : ce fichier cable
# UNIQUEMENT ce banc -- aucun mecanisme neuf, aucune extension du coeur.
# charge.gd/etat_duree.gd/etat_effectif.gd/objet.gd sont deja ecrits et
# verts ; ce fichier ne fait que les appeler et lire leurs resultats publics.
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready construit la source et les trois objets
#   (Objet.fabriquer, composition fusionnee -- meme patron que
#   banc_inflammabilite.gd). _unhandled_input bascule la source au clic
#   gauche. _process appelle UNIQUEMENT avancer() (fonction statique,
#   ci-dessous) puis lit ses resultats pour l'affichage/la console --
#   jamais un calcul refait ici (regle CLAUDE.md : la logique enfermee dans
#   _process doit en sortir en fonction statique testable).
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_humidite.gd) : causes_de/causes_ponderees/porosite_ponderee/
#   poids_receveur_humidite/avancer/basculer_source/fabriquer_objets/
#   diagnostiquer, plus le texte d'affichage et de log.

const Objet = preload("res://scripts/objet.gd")
const Charge = preload("res://scripts/charge.gd")
const EtatDuree = preload("res://scripts/etat_duree.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")

const TAILLE := 70.0
const HAUTEUR_BARRE := 10.0
const TAILLE_SOURCE := 30.0
const PROPRIETE_INFLAMMABILITE := "inflammabilite"

var _config: Dictionary = {}
var _etats: Dictionary = {}
var _materiaux: Dictionary = {}
var _source: Dictionary = {}
var _objets: Array = []
var _noeuds: Dictionary = {}
var _barres_fond: Dictionary = {}
var _barres_remplies: Dictionary = {}
var _labels: Dictionary = {}
var _noeud_source: ColorRect
var _label_source: Label
var _mouille_avant: Dictionary = {}
var _expose_avant: Dictionary = {}
var _temps: float = 0.0

func _ready() -> void:
	_config = _charger_json("res://data/banc_humidite.json")
	_etats = _charger_json("res://data/etats.json")
	_materiaux = _charger_json("res://data/materiaux.json")
	var materiaux := _materiaux
	var proprietes_immuables: Array = _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", [])

	var decl_source: Dictionary = _config.get("source", {})
	var pos_source: Array = decl_source.get("position", [0.0, 0.0, 0.0])
	_source = {
		"id": decl_source.get("id", "source"),
		"position": Vector3(pos_source[0], pos_source[1], pos_source[2]),
		"proprietes": {_config.propriete_cause: true},
	}

	_objets = fabriquer_objets(_config.get("objets", []), materiaux, proprietes_immuables, _config)
	for objet in _objets:
		_mouille_avant[objet.id] = false
		_expose_avant[objet.id] = false
		_creer_rendu_objet(objet)

	_creer_rendu_source()
	_poser_camera()

	for objet in _objets:
		var diag := diagnostiquer(objet, _config, _etats, _materiaux)
		print(_ligne_pose_initiale(objet.id, diag))
	_rafraichir_tout()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		basculer_source(_source, _config.propriete_cause)
		var actif: bool = _source.proprietes.get(_config.propriete_cause, false)
		print(_ligne_source(_temps, actif))
		_rafraichir_tout()

func _process(delta: float) -> void:
	_temps += delta
	var resultat := avancer(_objets, _source, delta, _config, _etats, _materiaux)

	for objet in _objets:
		var id: String = objet.id
		var porosite: float = porosite_ponderee(objet, _materiaux, _config.get("propriete_porosite", ""))
		var expose: bool = objet.proprietes.get(_config.declencheur_expose, false)
		if expose != _expose_avant.get(id, false):
			var canal: Dictionary = objet.proprietes.get("etats", {}).get(_config.nom_canal, {})
			print(_ligne_expose(_temps, id, expose, canal.get("charge", 0.0), canal.get("seuil", 0.0), porosite))
			_expose_avant[id] = expose

		var mouille: bool = objet.proprietes.get("etats_actifs", []).has(_config.nom_etat)
		if mouille != _mouille_avant.get(id, false):
			var effective: float = EtatEffectif.valeur(objet, PROPRIETE_INFLAMMABILITE, EtatDuree.etats_ponderes(objet, _etats))
			print(_ligne_mouille(_temps, id, mouille, effective, porosite))
			_mouille_avant[id] = mouille

	_rafraichir_tout()

func _rafraichir_tout() -> void:
	for objet in _objets:
		var id: String = objet.id
		var diag := diagnostiquer(objet, _config, _etats, _materiaux)
		_noeuds[id].color = _teinte_pour_statut(diag.statut)
		var ratio: float = clamp(diag.charge / diag.seuil, 0.0, 1.0) if diag.seuil > 0.0 else 0.0
		_barres_remplies[id].size.x = _barres_fond[id].size.x * ratio
		_labels[id].text = _texte_label(id, diag)
	var actif: bool = _source.proprietes.get(_config.propriete_cause, false)
	_noeud_source.color = Color(0.15, 0.55, 0.95) if actif else Color(0.4, 0.4, 0.4)
	_label_source.text = "source : %s (clic pour basculer)" % ("ACTIVE" if actif else "INACTIVE")

# ---- Fonctions PURES, testables headless (voir test_banc_humidite.gd) ----

# Meme geste que banc_charge.gd:causes_de -- filtre les objets portant
# "propriete_cause" a vrai, rend { position }, poids implicite 1.0 laisse a
# la charge de charge.gd. Local a ce fichier, meme choix que banc_charge.gd
# (pas descendu dans banc_commun.gd).
static func causes_de(objets: Array, propriete_cause: String) -> Array:
	var causes: Array = []
	for chose in objets:
		if chose.proprietes.get(propriete_cause, false):
			causes.append({"position": chose.position})
	return causes

# Pre-multiplie le poids de chaque cause par "poids" (le poids RECEVEUR --
# absorption_humidite du receveur module par sa porosite, voir
# poids_receveur_humidite ci-dessous ; jamais un poids de la source). Une
# cause sans "poids" explicite est traitee comme poids 1.0 (meme defaut que
# charge.gd).
static func causes_ponderees(causes: Array, poids: float) -> Array:
	var resultat: Array = []
	for cause in causes:
		resultat.append({"position": cause.position, "poids": cause.get("poids", 1.0) * poids})
	return resultat

# Voir en-tete, "POROSITE COMME FACTEUR DE VITESSE D'ABSORPTION". Meme
# patron que objet.gd:_moyenne_ponderee_volume -- moyenne ponderee par
# volume d'une propriete nommee sur la composition de l'objet, RECOPIE
# LOCALEMENT (jamais un appel a la fonction privee d'objet.gd, meme
# discipline que causes_de/causes_ponderees ci-dessus) plutot que reecrit
# dans objet.gd (aucun mecanisme du coeur touche). "propriete_porosite"
# vide, objet sans "composition", ou catalogue "materiaux" vide : rend 0.0,
# CHEMIN MORT -- meme contrat que la propriete elle-meme quand elle est
# absente d'une fiche materiau (aucune alarme, absence legitime).
static func porosite_ponderee(objet: Dictionary, materiaux: Dictionary, propriete_porosite: String) -> float:
	if propriete_porosite.is_empty() or materiaux.is_empty():
		return 0.0
	var composition: Array = objet.proprietes.get("composition", [])
	if composition.is_empty():
		return 0.0
	var somme_ponderee := 0.0
	var somme_volume := 0.0
	for element in composition:
		var nom_materiau: String = element.get("materiau", "")
		var volume: float = float(element.get("volume", 0.0))
		var fiche: Dictionary = materiaux.get(nom_materiau, {})
		somme_ponderee += float(fiche.get(propriete_porosite, 0.0)) * volume
		somme_volume += volume
	if somme_volume <= 0.0:
		return 0.0
	return somme_ponderee / somme_volume

# poids_receveur = absorption_humidite * (1.0 + facteur_porosite *
# porosite_effective) -- voir en-tete. "facteur_porosite"/"propriete_porosite"
# absents de "config" : retombent sur 0.0/"" (FACULTATIFS, contrairement aux
# champs requis d'objet.gd:_fabriquer_reserve_combustible) pour que tout
# appel existant sans ces deux cles (tests/config hors domaine anterieurs a
# ce chantier) continue de rendre exactement "absorption_humidite" seul --
# non-regression, verrouillee par test_banc_humidite.gd.
static func poids_receveur_humidite(objet: Dictionary, materiaux: Dictionary, config: Dictionary) -> float:
	var absorption: float = objet.proprietes.get(config.propriete_absorption, 0.0)
	var facteur_porosite: float = config.get("facteur_porosite", 0.0)
	var porosite: float = porosite_ponderee(objet, materiaux, config.get("propriete_porosite", ""))
	return absorption * (1.0 + facteur_porosite * porosite)

# UN PAS de simulation complet : pour chaque objet, fait avancer SON PROPRE
# canal de charge (portee/seuil/decroissance lus sur son canal, vitesse de
# montee ponderee par SON absorption_humidite ET SA porosite -- voir
# poids_receveur_humidite ci-dessus), pose "mouille" (EtatDuree.
# poser, remise a 1.0) tant que le marqueur d'exposition reste vrai CE tick,
# puis fait avancer la decroissance/le retrait progressif de TOUS les etats
# suivis (EtatDuree.avancer, une seule fois pour l'ensemble). Rend
# { bascules: Array d'id ayant franchi le seuil d'exposition ce pas,
# expirees: Array de { id, nom_etat } retires par decroissance ce pas } --
# meme forme que les valeurs deja rendues par Charge.avancer/EtatDuree.avancer,
# jamais recalculee ici. "materiaux" (FACULTATIF, defaut {}) : catalogue
# data/materiaux.json, necessaire uniquement a la lecture de la porosite --
# absent ou objet sans "composition", poids_receveur_humidite retombe sur
# l'absorption seule (non-regression, voir en-tete).
static func avancer(objets: Array, source: Dictionary, delta: float, config: Dictionary, etats: Dictionary, materiaux: Dictionary = {}) -> Dictionary:
	var causes_base := causes_de([source], config.propriete_cause)
	var bascules: Array = []
	for objet in objets:
		var poids_receveur := poids_receveur_humidite(objet, materiaux, config)
		var causes := causes_ponderees(causes_base, poids_receveur)
		var b := Charge.avancer([objet], causes, delta)
		if not b.is_empty():
			bascules.append(objet.id)
		if objet.proprietes.get(config.declencheur_expose, false):
			EtatDuree.poser(objet, config.nom_etat, etats)
	var expirees := EtatDuree.avancer(objets, delta, etats)
	return {"bascules": bascules, "expirees": expirees}

static func basculer_source(source: Dictionary, propriete_cause: String) -> void:
	source.proprietes[propriete_cause] = not source.proprietes.get(propriete_cause, false)

# Construit les objets cibles via Objet.fabriquer (composition fusionnee --
# meme patron que banc_inflammabilite.gd : un catalogue LOCAL, une entree
# par id, la cle "composition" seule). Chaque objet recoit ENSUITE son
# propre canal de charge (duplique, jamais partage entre objets -- meme
# garde que banc_charge.gd:_fabriquer_colon_charge) et etats_actifs vide.
static func fabriquer_objets(declarations: Array, materiaux: Dictionary, proprietes_immuables: Array, config: Dictionary) -> Array:
	var catalogue: Dictionary = {}
	for decl in declarations:
		catalogue[decl.id] = {"composition": decl.composition}
	var objets: Array = []
	for decl in declarations:
		var pos: Array = decl.position
		var objet := Objet.fabriquer(decl.id, decl.id, Vector3(pos[0], pos[1], pos[2]), catalogue, materiaux, proprietes_immuables)
		objet.proprietes["etats"] = {config.nom_canal: config.canal_defaut.duplicate(true)}
		objet.proprietes["etats_actifs"] = []
		objets.append(objet)
	return objets

# Diagnostic d'affichage, PUR : lit uniquement des valeurs deja calculees
# par charge.gd/etat_duree.gd/etat_effectif.gd, ne reimplemente jamais leur
# loi (meme doctrine que banc_inflammabilite.gd:diagnostiquer). "materiaux"
# (FACULTATIF, defaut {}) sert uniquement a resoudre "porosite" via
# porosite_ponderee -- absent, porosite rend 0.0, comportement inchange
# pour tout appelant anterieur a ce chantier. Rend
# { statut: "sec" | "expose" | "mouille", charge, seuil, absorption,
# porosite, intensite (-1.0 si non suivie), effective (inflammabilite
# effective) }.
static func diagnostiquer(objet: Dictionary, config: Dictionary, etats: Dictionary, materiaux: Dictionary = {}) -> Dictionary:
	var canal: Dictionary = objet.proprietes.get("etats", {}).get(config.nom_canal, {})
	var expose: bool = objet.proprietes.get(config.declencheur_expose, false)
	var mouille: bool = objet.proprietes.get("etats_actifs", []).has(config.nom_etat)
	var intensite: float = objet.proprietes.get("etats_intensite", {}).get(config.nom_etat, -1.0)
	var pondere := EtatDuree.etats_ponderes(objet, etats)
	var effective: float = EtatEffectif.valeur(objet, PROPRIETE_INFLAMMABILITE, pondere)
	var statut: String = "mouille" if mouille else ("expose" if expose else "sec")
	return {
		"statut": statut,
		"charge": canal.get("charge", 0.0),
		"seuil": canal.get("seuil", 0.0),
		"absorption": objet.proprietes.get(config.propriete_absorption, 0.0),
		"porosite": porosite_ponderee(objet, materiaux, config.get("propriete_porosite", "")),
		"intensite": intensite,
		"effective": effective,
	}

static func _teinte_pour_statut(statut: String) -> Color:
	match statut:
		"mouille":
			return Color(0.15, 0.35, 0.85)
		"expose":
			return Color(0.55, 0.6, 0.7)
		_:
			return Color(0.55, 0.42, 0.28)

static func _texte_label(id: String, diag: Dictionary) -> String:
	var intensite_texte: String = ("%.2f" % diag.intensite) if diag.intensite >= 0.0 else "-"
	return "%s\nabsorption=%.2f\nporosite=%.2f\ncharge=%.2f/%.2f\netat=%s\nintensite=%s\ninflammabilite_eff=%.2f" % [
		id, diag.absorption, diag.porosite, diag.charge, diag.seuil, diag.statut, intensite_texte, diag.effective
	]

static func _ligne_pose_initiale(id: String, diag: Dictionary) -> String:
	return "t=0.0s %s : absorption=%.2f porosite=%.2f seuil=%.2f inflammabilite_eff=%.2f (%s)" % [
		id, diag.absorption, diag.porosite, diag.seuil, diag.effective, diag.statut
	]

static func _ligne_expose(t: float, id: String, actif: bool, charge: float, seuil: float, porosite: float) -> String:
	return "t=%.1fs %s : expose_humidite %s (charge=%.2f, seuil=%.2f, porosite=%.2f)" % [
		t, id, "POSE" if actif else "RETIRE", charge, seuil, porosite
	]

static func _ligne_mouille(t: float, id: String, pose: bool, effective: float, porosite: float) -> String:
	if pose:
		return "t=%.1fs %s : etat 'mouille' pose (porosite=%.2f) -- inflammabilite effective -> %.2f" % [t, id, porosite, effective]
	return "t=%.1fs %s : etat 'mouille' expire (sechage progressif termine, porosite=%.2f) -- inflammabilite effective -> %.2f" % [t, id, porosite, effective]

static func _ligne_source(t: float, actif: bool) -> String:
	return "t=%.1fs source : %s" % [t, "ACTIVE" if actif else "INACTIVE"]

# ---- Rendu (impur, Node) -- aucune decision, seulement la construction
# des noeuds et la camera.

func _creer_rendu_objet(objet: Dictionary) -> void:
	var id: String = objet.id
	var centre := Vector2(objet.position.x, objet.position.y)

	var noeud := ColorRect.new()
	noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noeud.size = Vector2(TAILLE, TAILLE)
	noeud.position = centre - noeud.size / 2.0
	add_child(noeud)
	_noeuds[id] = noeud

	var fond := ColorRect.new()
	fond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fond.color = Color(0.2, 0.2, 0.2)
	fond.size = Vector2(TAILLE, HAUTEUR_BARRE)
	fond.position = centre + Vector2(-TAILLE / 2.0, TAILLE / 2.0 + 6.0)
	add_child(fond)
	_barres_fond[id] = fond

	var rempli := ColorRect.new()
	rempli.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rempli.color = Color(0.2, 0.55, 0.9)
	rempli.size = Vector2(0.0, HAUTEUR_BARRE)
	rempli.position = fond.position
	add_child(rempli)
	_barres_remplies[id] = rempli

	var label := Label.new()
	label.position = centre - Vector2(TAILLE / 2.0, TAILLE / 2.0 + 120.0)
	add_child(label)
	_labels[id] = label

func _creer_rendu_source() -> void:
	var centre := Vector2(_source.position.x, _source.position.y)
	var noeud := ColorRect.new()
	noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noeud.size = Vector2(TAILLE_SOURCE, TAILLE_SOURCE)
	noeud.position = centre - noeud.size / 2.0
	add_child(noeud)
	_noeud_source = noeud

	var label := Label.new()
	label.position = noeud.position - Vector2(20.0, 24.0)
	add_child(label)
	_label_source = label

func _poser_camera() -> void:
	var position_source: Vector3 = _source.position
	var centre_x: float = position_source.x
	for objet in _objets:
		centre_x += objet.position.x
	centre_x /= float(_objets.size() + 1)
	var camera := Camera2D.new()
	camera.position = Vector2(centre_x, 250.0)
	camera.zoom = Vector2(0.8, 0.8)
	camera.enabled = true
	add_child(camera)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
