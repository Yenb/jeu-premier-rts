extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_reflectivite.tscn, PAS la
# scene principale -- run/main_scene reste banc_p1, coexiste avec les
# autres bancs). Existe pour VOIR qu'un objet reflechissant renvoie la
# lumiere locale (compose scripts/lumiere.gd, deja ferme et prouve hors
# domaine, premiere fois qu'il sert de SOURCE SECONDAIRE plutot que de
# simple lecteur -- voir banc_lumiere.gd) et absorbe moins de chaleur
# radiante qu'un objet sombre (compose scripts/temperature.gd, deja ferme).
# JETABLE PAR DEFINITION. AUCUN MECANISME DU COEUR TOUCHE :
# lumiere.gd/temperature.gd/etat_effectif.gd/objet.gd inchanges.
#
# CE QU'IL DOIT MONTRER :
# 0. DYNAMIQUE, INTERACTIF (correction session ulterieure -- le premier jet
#    etait statique, rien ne bougeait) : la lampe fixe (ci-dessous) est
#    TOGGLABLE au clic gauche, meme geste que la source d'humidite de
#    banc_humidite.gd (_lampe_active, bool simple, jamais un Dictionary
#    mute -- il n'y a ici qu'UNE source a bascule, pas un ensemble de
#    causes ponderees). Coupee, elle sort purement et simplement du tableau
#    des sources ambiantes (sources_lumiere_ambiantes) -- lumiere_locale/
#    chaleur_absorbee retombent, la temperature de chaque objet redescend
#    vers l'ambiante par la MEME loi de Newton (temperature.gd, non
#    touche). UNE SECONDE source, MOBILE, traverse la scene en continu
#    (mouvement sinusoidal 1D, fonction PURE du temps -- meme patron que
#    banc_temperature.gd:position_source_mobile/banc_lumiere.gd:
#    position_lanterne, jamais leur code) : elle reste TOUJOURS active,
#    independante du toggle. lumiere_locale/chaleur_absorbee de chaque
#    objet varient donc en continu meme lampe coupee, selon que la source
#    mobile s'approche ou s'eloigne.
# 1. L'ARGENT COMME SOURCE SECONDAIRE -- une lampe fixe (source primaire,
#    lumiere.gd) eclaire trois objets a EGALE distance (argent/bois/
#    cuivre_patine, mêmes rayon/angle-espacement, seule leur composition
#    diverge). Chaque objet devient lui-meme une source de lumiere.gd,
#    posee A SA PROPRE POSITION, dont le PRODUIT intensite*force vaut
#    exactement (lumiere_locale recue par l'objet) * (reflectivite
#    effective de l'objet) -- pas une formule reimplementee ici, la MEME
#    multiplication que lumiere.gd:_contribution_intensite calcule deja en
#    interne (voir source_reflechie ci-dessous). Un temoin par objet, a
#    EGALE distance de son objet, hors de portee de la lampe et des DEUX
#    autres objets (separation angulaire, voir data/banc_reflectivite.json)
#    lit ce reflet seul : le temoin pres de l'argent doit recevoir
#    NETTEMENT plus de lumiere que celui pres du bois.
# 2. LA TERNISSURE (ici : PATINE_VERTE, cuivre -- voir DERIVE ci-dessous)
#    REDUIT LA REFLEXION -- cuivre_patine_0 porte etats_actifs=
#    ["patine_verte"] des la fabrication (POSE STATIQUEMENT, jamais via
#    charge.gd/etat_duree.gd -- ce banc ne fait pas progresser une
#    corrosion dans le temps, voir banc_corrosion.gd pour ca) :
#    scripts/etat_effectif.gd module sa reflectivite de base (cuivre 0.65)
#    par le facteur PARTAGE de data/etats.json:patine_verte (x0.3) --
#    reflectivite effective ~0.195, affichee EN PLUS de la base sur son
#    Label pour que la reduction se lise sans objet neuf a cote.
# 3. L'ARGENT ABSORBE MOINS DE CHALEUR -- chaleur_absorbee = absorption_
#    sombre * (1.0 - reflectivite_effective) * lumiere_locale (formule
#    PURE, voir chaleur_absorbee ci-dessous), utilisee comme FORCE d'une
#    source radiante synthetique POSEE A LA POSITION DE L'OBJET LUI-MEME
#    (rayon minuscule, ne touche jamais les deux autres -- meme idiome que
#    scripts/banc_chaleur_emise.gd:sources_chaleur, une source PAR OBJET)
#    puis Temperature.avancer (scripts/temperature.gd, NON TOUCHE) fait
#    chauffer chaque objet vers la cible que cette source implique, loi de
#    Newton inchangee. Conductivite/chaleur_specifique sont des CONSTANTES
#    LOCALES PARTAGEES par les trois objets (voir data/
#    banc_reflectivite.json._note -- argent/cuivre n'ont pas de fiche
#    thermique reelle, la lire aurait laisse l'ecart venir d'une donnee
#    manquante plutot que de la reflectivite). Le bois, plus sombre, doit
#    chauffer NETTEMENT plus vite que l'argent sous la meme lampe.
# 4. Un Label PAR OBJET (reflectivite base ET effective, lumiere_locale,
#    chaleur_absorbee, temperature) et PAR TEMOIN (intensite_lumiere/
#    couleur_lumiere) -- CanvasLayer, patron banc_lumiere.gd/banc_champ.gd.
#    Trace console : une ligne de pose par objet au demarrage, un rapport
#    PERIODIQUE (intervalle_print en donnee, patron banc_temperature.gd/
#    banc_vent.gd/banc_lumiere.gd).
#
# DERIVE SIGNALEE ET TRANCHEE PAR YAEL (avant d'ecrire) : la consigne
# d'origine demandait "fer corrode avec ternissure" -- IMPOSSIBLE tel
# quel, ternissure n'existe que sur l'argent dans tout le depot (doctrine
# du chantier "corrosion", voir scripts/banc_corrosion.gd/data/
# etats.json) ; le fer suit UNIQUEMENT "corrode" (module durete, jamais
# reflectivite). Yael a tranche : CUIVRE + patine_verte (module
# reflectivite x0.3, meme famille que ternissure) remplace "fer +
# ternissure" -- aucune donnee nouvelle, aucune regle de contenu deja
# tranchee n'est reouverte.
#
# PORTEE VOLONTAIREMENT LIMITEE : ce banc ne route rien par
# attaches.gd/proximite.gd/jugement.gd/dominance.gd/agir.gd/charge.gd/
# etat_duree.gd -- aucune decision, aucune progression temporelle d'etat
# (patine_verte reste actif pour toujours, jamais une exposition qui
# s'accumule). La reflectivite/absorption_sombre sont FUSIONNEES a la
# fabrication (Objet.fabriquer, parametre proprietes_immuables, deja en
# place) -- ce chantier ne modifie ni ne redecouvre ce mecanisme.
#
# Deux moities, meme decoupage que banc_lumiere.gd/banc_corrosion.gd :
# - Node (impur) : _ready charge data/banc_reflectivite.json +
#   data/materiaux.json + data/etats.json + data/lumiere.json +
#   data/temperature.json, fabrique lampe/source mobile/objets/temoins.
#   _unhandled_input bascule UNIQUEMENT _lampe_active (bool), rien
#   d'autre. _process calcule la position de la source mobile
#   (position_source_mobile), compose les sources ambiantes du tick
#   (sources_lumiere_ambiantes) puis appelle UNIQUEMENT avancer()
#   (fonction statique, ci-dessous) et lit son resultat pour
#   l'affichage/la console -- jamais un calcul refait ici (regle
#   CLAUDE.md).
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_reflectivite.gd) : fabriquer_objets, fabriquer_temoins,
#   position_source_mobile, sources_lumiere_ambiantes, lampe_apres_clic,
#   chaleur_absorbee, source_reflechie, source_radiante, diagnostiquer,
#   avancer, plus le texte d'affichage et de log.

const Objet = preload("res://scripts/objet.gd")
const Lumiere = preload("res://scripts/lumiere.gd")
const Temperature = preload("res://scripts/temperature.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")

const TAILLE_OBJET := 70.0
const TAILLE_TEMOIN := 40.0
const TAILLE_LAMPE := 26.0

var _config: Dictionary = {}
var _materiaux: Dictionary = {}
var _etats: Dictionary = {}
var _catalogue_lumiere: Dictionary = {}
var _catalogue_temperature: Dictionary = {}
var _lampe: Dictionary = {}
var _lampe_active := true
var _source_mobile_config: Dictionary = {}
var _source_mobile: Dictionary = {}
var _objets: Array = []
var _temoins: Array = []
var _intervalle_print := 3.0

var _noeuds_objets: Dictionary = {}  # id -> ColorRect
var _labels_objets: Dictionary = {}  # id -> Label
var _noeuds_temoins: Dictionary = {}  # id -> ColorRect
var _labels_temoins: Dictionary = {}  # id -> Label
var _noeud_lampe: ColorRect
var _noeud_source_mobile: ColorRect

var _temps: float = 0.0
var _prochain_print: float = 0.0

const _COULEUR_LAMPE_ACTIVE := Color(1.0, 0.95, 0.75)
const _COULEUR_LAMPE_INACTIVE := Color(0.35, 0.35, 0.32)
const _COULEUR_SOURCE_MOBILE := Color(0.7, 0.85, 1.0)

const _COULEURS_OBJET := {
	"argent_0": Color(0.75, 0.76, 0.8),
	"bois_0": Color(0.45, 0.3, 0.15),
	"cuivre_patine_0": Color(0.3, 0.55, 0.42),
}

func _ready() -> void:
	_config = _charger_json("res://data/banc_reflectivite.json")
	_materiaux = _charger_json("res://data/materiaux.json")
	_etats = _charger_json("res://data/etats.json")
	_catalogue_lumiere = _charger_json("res://data/lumiere.json")
	_catalogue_temperature = _charger_json("res://data/temperature.json")
	var proprietes_immuables: Array = _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", [])

	var decl_lampe: Dictionary = _config.get("lampe", {})
	var pos_lampe: Array = decl_lampe.get("position", [0.0, 0.0, 0.0])
	_lampe = {
		"position": Vector3(pos_lampe[0], pos_lampe[1], pos_lampe[2]),
		"rayon": decl_lampe.get("rayon", 200.0),
		"intensite": decl_lampe.get("intensite", 0.9),
		"temperature_couleur": decl_lampe.get("temperature_couleur", 0.5),
		"force": decl_lampe.get("force", 1.0),
	}

	_source_mobile_config = _config.get("source_mobile", {})
	_source_mobile = _source_a_position(_source_mobile_config, position_source_mobile(
		_vecteur_depuis_array(_source_mobile_config.get("centre", [0.0, 0.0, 0.0])),
		_source_mobile_config.get("amplitude", 0.0),
		_source_mobile_config.get("periode", 1.0),
		0.0
	))

	_objets = fabriquer_objets(_config.get("objets", []), _materiaux, proprietes_immuables, _config.get("config", {}))
	_temoins = fabriquer_temoins(_config.get("temoins", []))
	_intervalle_print = _config.get("intervalle_print", 3.0)

	_creer_rendu_lampe()
	_creer_rendu_source_mobile()
	for objet in _objets:
		_creer_rendu_objet(objet)
	for temoin in _temoins:
		_creer_rendu_temoin(temoin)
	_poser_camera()

	var sources_initiales := sources_lumiere_ambiantes(_lampe, _lampe_active, _source_mobile)
	var diagnostics_initiaux: Dictionary = {}
	for objet in _objets:
		var diag := diagnostiquer(objet, sources_initiales, _catalogue_lumiere, _etats)
		diagnostics_initiaux[objet.id] = diag
		print(_ligne_pose_initiale(objet.id, diag))
	_rafraichir_tout(diagnostics_initiaux)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_lampe_active = lampe_apres_clic(_lampe_active)
		print(_ligne_toggle(_temps, _lampe_active))

func _process(delta: float) -> void:
	_temps += delta

	_source_mobile.position = position_source_mobile(
		_vecteur_depuis_array(_source_mobile_config.get("centre", [0.0, 0.0, 0.0])),
		_source_mobile_config.get("amplitude", 0.0),
		_source_mobile_config.get("periode", 1.0),
		_temps
	)
	var sources_ambiantes := sources_lumiere_ambiantes(_lampe, _lampe_active, _source_mobile)

	var resultat := avancer(_objets, _temoins, sources_ambiantes, delta, _catalogue_lumiere, _catalogue_temperature, _etats, _config.get("config", {}))
	_rafraichir_tout(resultat.diagnostics)

	_noeud_lampe.color = _COULEUR_LAMPE_ACTIVE if _lampe_active else _COULEUR_LAMPE_INACTIVE
	_noeud_source_mobile.position = Vector2(_source_mobile.position.x, _source_mobile.position.y) - _noeud_source_mobile.size / 2.0

	if _temps >= _prochain_print:
		_prochain_print = _temps + _intervalle_print
		print(ligne_rapport(_temps, resultat.diagnostics, _temoins))

func _rafraichir_tout(diagnostics: Dictionary) -> void:
	for objet in _objets:
		var diag: Dictionary = diagnostics.get(objet.id, {})
		if diag.is_empty():
			continue
		_labels_objets[objet.id].text = texte_objet(objet.id, diag)
	for temoin in _temoins:
		var intensite: float = temoin.proprietes.get("intensite_lumiere", 0.0)
		var couleur: float = temoin.proprietes.get("couleur_lumiere", 0.0)
		var noeud: ColorRect = _noeuds_temoins[temoin.id]
		noeud.color = Color.BLACK.lerp(Color.WHITE, clamp(intensite, 0.0, 1.0))
		_labels_temoins[temoin.id].text = texte_temoin(temoin.id, intensite, couleur)

# ---- Fonctions statiques, pures, testables ----

# Construit les trois objets reflechissants via Objet.fabriquer (composition
# fusionnee -- meme patron que banc_corrosion.gd/banc_humidite.gd). Chaque
# objet recoit ENSUITE etats_actifs (decl.etats_actifs, POSE STATIQUEMENT,
# jamais avance par charge.gd/etat_duree.gd -- voir en-tete DERIVE) et trois
# constantes thermiques LOCALES PARTAGEES (config.temperature_depart/
# conductivite_thermique_demo/chaleur_specifique_demo, IDENTIQUES pour les
# trois -- isole chaleur_absorbee comme SEULE cause de l'ecart de
# temperature, voir en-tete point 3).
static func fabriquer_objets(declarations: Array, materiaux: Dictionary, proprietes_immuables: Array, config: Dictionary) -> Array:
	var catalogue: Dictionary = {}
	for decl in declarations:
		catalogue[decl.id] = {"composition": decl.composition}
	var objets: Array = []
	for decl in declarations:
		var pos: Array = decl.position
		var objet := Objet.fabriquer(decl.id, decl.id, Vector3(pos[0], pos[1], pos[2]), catalogue, materiaux, proprietes_immuables)
		if objet.is_empty():
			continue
		objet.proprietes["etats_actifs"] = decl.get("etats_actifs", []).duplicate()
		objet.proprietes["temperature"] = config.get("temperature_depart", 20.0)
		objet.proprietes["conductivite_thermique"] = config.get("conductivite_thermique_demo", 0.0)
		objet.proprietes["chaleur_specifique"] = config.get("chaleur_specifique_demo", 1.0)
		objets.append(objet)
	return objets

static func fabriquer_temoins(declarations: Array) -> Array:
	var temoins: Array = []
	for decl in declarations:
		var pos: Array = decl.position
		temoins.append({"id": decl.id, "position": Vector3(pos[0], pos[1], pos[2]), "proprietes": {}})
	return temoins

# Position de la source mobile a l'instant `temps` : un aller-retour
# sinusoidal 1D autour de `centre`, fonction PURE du temps -- meme patron
# que banc_temperature.gd:position_source_mobile/banc_lumiere.gd:
# position_lanterne, jamais leur code (COPIER-PATRON). `periode` <= 0.0 :
# la source reste immobile au centre, jamais une division par zero.
static func position_source_mobile(centre: Vector3, amplitude: float, periode: float, temps: float) -> Vector3:
	if periode <= 0.0:
		return centre
	var decalage: float = amplitude * sin(TAU * temps / periode)
	return centre + Vector3(decalage, 0.0, 0.0)

# Compose les sources AMBIANTES du tick (celles qui eclairent les objets
# depuis l'exterieur, jamais leurs propres reflets) : la lampe fixe
# UNIQUEMENT si active (toggle au clic -- coupee, elle sort purement du
# tableau, jamais une intensite mise a 0.0 laissee trainer), la source
# mobile TOUJOURS (independante du toggle, jamais coupee). Fonction PURE,
# extraite de _process pour rester testable (regle CLAUDE.md : la logique
# enfermee dans _process/_unhandled_input en sort en fonction statique).
static func sources_lumiere_ambiantes(lampe: Dictionary, lampe_active: bool, source_mobile: Dictionary) -> Array:
	var sources: Array = [source_mobile]
	if lampe_active:
		sources.append(lampe)
	return sources

# Bascule triviale, extraite de _unhandled_input pour rester testable --
# un clic gauche inverse l'etat, jamais un troisieme etat possible.
static func lampe_apres_clic(active: bool) -> bool:
	return not active

# FORMULE PURE, coeur du chantier : un objet sombre (absorption_sombre haut)
# et peu reflechissant absorbe presque toute la lumiere qu'il recoit ;
# un objet tres reflechissant (reflectivite proche de 1.0) n'en absorbe
# presque rien, quelle que soit sa couleur. Hors lumiere (lumiere_locale
# 0.0) ou a reflectivite totale (1.0) : chaleur_absorbee vaut exactement
# 0.0, jamais un residu.
static func chaleur_absorbee(absorption_sombre: float, reflectivite: float, lumiere_locale: float) -> float:
	return absorption_sombre * (1.0 - reflectivite) * lumiere_locale

# La source SECONDAIRE qu'un objet reflechissant devient : posee a SA
# PROPRE position, "intensite" porte ce que l'objet RECOIT (lumiere_locale),
# "force" porte SA CAPACITE A LE RENVOYER (reflectivite effective) -- le
# produit intensite*force est donc EXACTEMENT "reflectivite x lumiere_locale"
# demande, sans reimplementer la multiplication que lumiere.gd fait deja en
# interne (voir lumiere.gd:_contribution_intensite). reflectivite 0.0 :
# force nulle, la source ne contribue jamais rien, quelle que soit
# lumiere_locale -- meme raisonnement pour lumiere_locale 0.0 (hors de
# portee de toute lumiere, rien a reflechir).
static func source_reflechie(objet: Dictionary, reflectivite: float, lumiere_locale: float, config: Dictionary) -> Dictionary:
	return {
		"position": objet.position,
		"rayon": config.get("rayon_reflet", 100.0),
		"intensite": lumiere_locale,
		"temperature_couleur": config.get("temperature_couleur_reflet", 0.5),
		"force": reflectivite,
	}

# Source de chaleur radiante synthetique, POSEE A LA POSITION DE L'OBJET
# LUI-MEME avec un rayon minuscule (config.rayon_radiant) -- ne touche
# jamais les deux autres objets, meme idiome que
# banc_chaleur_emise.gd:sources_chaleur (une source PAR OBJET). "force"
# porte chaleur_absorbee -- Temperature.avancer (NON TOUCHE) l'applique
# ensuite par la loi de Newton habituelle, aucune formule reimplementee ici.
static func source_radiante(objet: Dictionary, absorbee: float, config: Dictionary) -> Dictionary:
	return {
		"position": objet.position,
		"rayon": config.get("rayon_radiant", 5.0),
		"temperature": config.get("temperature_radiante", 100.0),
		"force": absorbee,
	}

# Diagnostic complet d'un objet, PUR : lit uniquement des valeurs deja
# calculees par etat_effectif.gd/lumiere.gd, ne reimplemente jamais leur
# loi (meme doctrine que banc_corrosion.gd:diagnostiquer). `sources` porte
# TOUTES les sources ambiantes actives ce tick (lampe si active, source
# mobile toujours -- voir sources_lumiere_ambiantes), jamais les reflets
# des objets eux-memes. Rend { reflectivite_base, reflectivite_effective,
# absorption_sombre, lumiere_locale, chaleur_absorbee, temperature }.
static func diagnostiquer(objet: Dictionary, sources: Array, catalogue_lumiere: Dictionary, etats: Dictionary) -> Dictionary:
	var reflectivite_base: float = objet.proprietes.get("reflectivite", 0.0)
	var reflectivite_effective: float = EtatEffectif.valeur(objet, "reflectivite", etats)
	var absorption_sombre: float = objet.proprietes.get("absorption_sombre", 0.0)
	var lumiere_locale: float = Lumiere.locale(objet.position, sources, catalogue_lumiere).intensite
	var absorbee: float = chaleur_absorbee(absorption_sombre, reflectivite_effective, lumiere_locale)
	return {
		"reflectivite_base": reflectivite_base,
		"reflectivite_effective": reflectivite_effective,
		"absorption_sombre": absorption_sombre,
		"lumiere_locale": lumiere_locale,
		"chaleur_absorbee": absorbee,
		"temperature": objet.proprietes.get("temperature", 0.0),
	}

# UN PAS de simulation complet. 1. diagnostique chaque objet (lumiere_locale
# recue depuis les SOURCES AMBIANTES DU TICK SEULES -- lampe si active,
# source mobile toujours, jamais les reflets des autres objets, evite toute
# boucle de reflet-sur-reflet dans le meme tick) ; 2. construit une source
# reflechie PAR OBJET (source_reflechie) et fait avancer les TEMOINS via
# Lumiere.avancer (NON TOUCHE) avec les sources ambiantes + les reflets ;
# 3. construit une source radiante PAR OBJET (source_radiante, rayon
# minuscule) et fait avancer les OBJETS eux-memes via Temperature.avancer
# (NON TOUCHE, mute en place). Rend { diagnostics: Dictionary id -> diag,
# changements_lumiere: Array } -- memes formes que celles deja rendues par
# Lumiere.avancer, jamais recalculees ici.
static func avancer(objets: Array, temoins: Array, sources_ambiantes: Array, delta: float, catalogue_lumiere: Dictionary, catalogue_temperature: Dictionary, etats: Dictionary, config: Dictionary) -> Dictionary:
	var diagnostics: Dictionary = {}
	var sources_lumiere: Array = sources_ambiantes.duplicate()
	var sources_radiantes: Array = []
	for objet in objets:
		var diag := diagnostiquer(objet, sources_ambiantes, catalogue_lumiere, etats)
		diagnostics[objet.id] = diag
		sources_lumiere.append(source_reflechie(objet, diag.reflectivite_effective, diag.lumiere_locale, config))
		sources_radiantes.append(source_radiante(objet, diag.chaleur_absorbee, config))

	var changements_lumiere := Lumiere.avancer(temoins, sources_lumiere, delta, catalogue_lumiere)
	Temperature.avancer(objets, sources_radiantes, delta, catalogue_temperature)

	return {"diagnostics": diagnostics, "changements_lumiere": changements_lumiere}

static func texte_objet(id: String, diag: Dictionary) -> String:
	return "%s\nreflectivite=%.3f (base %.3f)\nlumiere_locale=%.3f\nchaleur_absorbee=%.3f\ntemperature=%.2f" % [
		id, diag.reflectivite_effective, diag.reflectivite_base, diag.lumiere_locale, diag.chaleur_absorbee, diag.temperature
	]

static func texte_temoin(id: String, intensite: float, couleur: float) -> String:
	return "%s : intensite=%.3f couleur=%.2f" % [id, intensite, couleur]

static func _ligne_pose_initiale(id: String, diag: Dictionary) -> String:
	return "t=0.0s %s : reflectivite=%.3f (base %.3f) absorption_sombre=%.3f temperature=%.2f" % [
		id, diag.reflectivite_effective, diag.reflectivite_base, diag.absorption_sombre, diag.temperature
	]

static func _ligne_toggle(t: float, active: bool) -> String:
	return "t=%.1fs lampe : %s" % [t, "ACTIVEE" if active else "COUPEE"]

static func ligne_rapport(t: float, diagnostics: Dictionary, temoins: Array) -> String:
	var texte := "t=%.1fs" % t
	for id in diagnostics:
		var diag: Dictionary = diagnostics[id]
		texte += " | %s(refl=%.3f loc=%.3f abs=%.3f T=%.2f)" % [id, diag.reflectivite_effective, diag.lumiere_locale, diag.chaleur_absorbee, diag.temperature]
	for temoin in temoins:
		texte += " | %s" % texte_temoin(temoin.id, temoin.proprietes.get("intensite_lumiere", 0.0), temoin.proprietes.get("couleur_lumiere", 0.0))
	return texte

# ---- Rendu (impur, Node) -- aucune decision, seulement la construction
# des noeuds et la camera.

func _creer_rendu_objet(objet: Dictionary) -> void:
	var id: String = objet.id
	var centre := Vector2(objet.position.x, objet.position.y)

	var noeud := ColorRect.new()
	noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noeud.size = Vector2(TAILLE_OBJET, TAILLE_OBJET)
	noeud.position = centre - noeud.size / 2.0
	noeud.color = _COULEURS_OBJET.get(id, Color(0.5, 0.5, 0.5))
	add_child(noeud)
	_noeuds_objets[id] = noeud

	var couche_ui := CanvasLayer.new()
	add_child(couche_ui)
	var label := Label.new()
	label.position = centre - Vector2(TAILLE_OBJET / 2.0, TAILLE_OBJET / 2.0 + 90.0)
	add_child(label)
	_labels_objets[id] = label

func _creer_rendu_temoin(temoin: Dictionary) -> void:
	var id: String = temoin.id
	var centre := Vector2(temoin.position.x, temoin.position.y)

	var noeud := ColorRect.new()
	noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noeud.size = Vector2(TAILLE_TEMOIN, TAILLE_TEMOIN)
	noeud.position = centre - noeud.size / 2.0
	noeud.color = Color.BLACK
	add_child(noeud)
	_noeuds_temoins[id] = noeud

	var label := Label.new()
	label.position = centre + Vector2(-TAILLE_TEMOIN / 2.0, TAILLE_TEMOIN / 2.0 + 4.0)
	add_child(label)
	_labels_temoins[id] = label

func _creer_rendu_lampe() -> void:
	var centre := Vector2(_lampe.position.x, _lampe.position.y)
	var noeud := ColorRect.new()
	noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noeud.size = Vector2(TAILLE_LAMPE, TAILLE_LAMPE)
	noeud.position = centre - noeud.size / 2.0
	noeud.color = _COULEUR_LAMPE_ACTIVE if _lampe_active else _COULEUR_LAMPE_INACTIVE
	add_child(noeud)
	_noeud_lampe = noeud

func _creer_rendu_source_mobile() -> void:
	var noeud := ColorRect.new()
	noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noeud.size = Vector2(TAILLE_LAMPE, TAILLE_LAMPE)
	noeud.color = _COULEUR_SOURCE_MOBILE
	noeud.position = Vector2(_source_mobile.position.x, _source_mobile.position.y) - noeud.size / 2.0
	add_child(noeud)
	_noeud_source_mobile = noeud

func _source_a_position(decl: Dictionary, position: Vector3) -> Dictionary:
	return {
		"position": position,
		"rayon": decl.get("rayon", 100.0),
		"intensite": decl.get("intensite", 0.5),
		"temperature_couleur": decl.get("temperature_couleur", 0.5),
		"force": decl.get("force", 1.0),
	}

func _vecteur_depuis_array(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])

func _poser_camera() -> void:
	var decl_camera: Dictionary = _config.get("camera", {})
	var pos_camera: Array = decl_camera.get("position", [0.0, 0.0, 0.0])
	var camera := Camera2D.new()
	camera.position = Vector2(pos_camera[0], pos_camera[1])
	camera.zoom = Vector2(decl_camera.get("zoom", 0.45), decl_camera.get("zoom", 0.45))
	camera.enabled = true
	add_child(camera)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
