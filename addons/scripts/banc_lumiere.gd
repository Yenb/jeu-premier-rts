extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_lumiere.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1, coexiste avec les autres
# bancs). Existe pour VOIR scripts/lumiere.gd (ferme et prouve hors
# domaine par test_lumiere.gd, lint vert) tourner sur une scene
# observable -- PREMIERE DEMONSTRATION REELLE. JETABLE PAR DEFINITION.
# Recopie le patron de scripts/banc_temperature.gd (Node impur + fonctions
# statiques pures testables, CanvasLayer pour le HUD, Camera2D fixe).
#
# CE QU'IL DOIT MONTRER (voir en-tete du chantier) :
# 1. LE CYCLE JOUR/NUIT -- l'heure simulee avance (mappee sur des
#    secondes reelles, voir data/banc_lumiere.json:cycle_reel), l'ambiante
#    (Lumiere.soleil) monte/descend en intensite ET change de couleur
#    (orange aube -> blanc-jaune midi -> orange crepuscule -> bleu nuit).
#    Le lecteur `temoin_ambiant`, loin de toute source, montre le cycle
#    PUR. Le fond de l'ecran (grand ColorRect derriere tout le reste) suit
#    la meme ambiante.
# 2. UNE TORCHE FIXE (source locale, orange chaud) -- le lecteur
#    `pres_torche`, dans son rayon, doit rester orange et lumineux la
#    nuit (la torche domine une ambiante nulle) et se fondre dans le
#    blanc-jaune ambiant le jour (l'ambiante ecrase la contribution
#    relative de la torche au fur et a mesure qu'elle grandit).
# 3. UNE LANTERNE MOBILE -- source dont la position change chaque tick
#    (mouvement sinusoidal, fonction pure du temps, meme discipline que
#    banc_temperature.gd -- CE BANC deplace la source, lumiere.gd ne
#    possede ni ne deplace jamais rien lui-meme). Deux lecteurs la
#    suivent : `porteur_lanterne` (RECALCULE a la position de la lanterne
#    chaque tick -- toujours au centre exact de sa lumiere) et
#    `passage_lanterne` (fixe sur sa trajectoire, capte le passage puis le
#    perd).
# 4. DEUX SOURCES DE COULEURS DIFFERENTES -- torche (orange, 0.15) et
#    cristal (bleu, 0.85), placees pour que leurs rayons se RECOUVRENT.
#    Le lecteur `zone_melange`, dans le recouvrement, doit afficher une
#    couleur INTERMEDIAIRE (ni franchement orange ni franchement bleue) --
#    preuve visuelle que la couleur est une MOYENNE PONDEREE, jamais un
#    ecrasement de l'une par l'autre.
# 5. Un Label PAR LECTEUR (CanvasLayer, patron banc_champ.gd/
#    banc_temperature.gd) affiche EN PERMANENCE intensite_lumiere/
#    couleur_lumiere.
# 6. Trace console : un rapport PERIODIQUE (heure, intensite ambiante,
#    couleur ambiante, valeurs de chaque lecteur -- intervalle_print en
#    donnee, meme discipline que banc_temperature.gd/banc_vent.gd) PLUS
#    une ligne a chaque CHANGEMENT DE ZONE (jour/penombre/nuit, seuils en
#    donnee) d'un lecteur -- jamais l'epsilon fin du retour de
#    Lumiere.avancer() (trop bavard pour une trace console, verifie a
#    l'ecriture : l'ambiante derive en continu pendant tout le cycle,
#    loggerait sinon a quasiment chaque frame).
#
# PORTEE VOLONTAIREMENT LIMITEE : ce banc ne route rien par
# attaches.gd/proximite.gd/jugement.gd/dominance.gd/agir.gd -- aucune
# decision, seulement des sources construites/deplacees par ce fichier et
# l'appel du mecanisme de lumiere. Les lecteurs sont des Dictionary bruts
# { id, position, proprietes } CONSTRUITS PAR CE BANC -- pas via
# Objet.fabriquer/data/types.json (decision de perimetre du chantier,
# voir lumiere.gd en-tete : intensite_lumiere/couleur_lumiere ne sont pas
# structurelles sur objet_physique).
#
# COULEUR A L'ECRAN, JAMAIS DANS LE MECANISME : `couleur_lumiere` (0.0
# orange, 1.0 bleu) est un SCALAIRE de temperature de couleur, pas un RGB
# -- la traduction en Color affichable (couleur_affichage, INTERPOLATION
# EN DEUX MORCEAUX orange -> blanc-jaune -> bleu, meme idiome que
# vent.gd:facteur_directionnel pour la meme raison : un point milieu
# NOMME -- 0.5, "blanc-jaune" -- qu'une seule droite entre les deux
# extremes ne produirait jamais) vit ENTIEREMENT dans ce fichier, jamais
# dans lumiere.gd. La LUMINOSITE affichee d'un lecteur mele en plus
# `intensite_lumiere` (lerp vers le noir a intensite nulle, meme
# principe que temperature.gd:couleur_pour_temperature) -- deux
# lectures, deux roles distincts, jamais confondues.
#
# Deux moities, meme decoupage que banc_temperature.gd :
# - Node (impur) : _ready charge data/banc_lumiere.json (jetable, propre
#   a ce banc) et data/lumiere.json (catalogue PARTAGE, reel, jamais
#   surcharge ni mute ici -- une COPIE profonde recoit chaque tick
#   l'ambiante fraiche calculee par Lumiere.soleil, voir lumiere.gd
#   en-tete). _process avance l'heure, deplace la lanterne, appelle
#   Lumiere.soleil/avancer, redessine fond+sources+lecteurs+Label,
#   imprime le rapport periodique et les changements de zone.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_lumiere.gd) : heure_courante, position_lanterne,
#   fabriquer_lecteur, sources_du_tick, couleur_affichage,
#   couleur_lecteur, zone_pour_intensite, texte_lecteur, ligne_rapport,
#   ligne_changement_zone.

const Lumiere = preload("res://scripts/lumiere.gd")

const TAILLE_LECTEUR := 50.0
const TAILLE_SOURCE := 24.0

var _donnees: Dictionary = {}
var _catalogue_lumiere: Dictionary = {}
var _duree_jour_secondes := 40.0
var _heure_depart := 0.0
var _torche: Dictionary = {}
var _cristal: Dictionary = {}
var _lanterne_config: Dictionary = {}
var _lecteurs: Array = []
var _seuil_jour := 0.5
var _seuil_penombre := 0.1
var _couleur_orange := Color(1.0, 0.55, 0.1)
var _couleur_blanc_jaune := Color(1.0, 0.95, 0.8)
var _couleur_bleu := Color(0.25, 0.45, 0.9)
var _intervalle_print := 3.0

var _fond: ColorRect
var _noeud_torche: ColorRect
var _noeud_cristal: ColorRect
var _noeud_lanterne: ColorRect
var _noeuds_lecteurs: Dictionary = {}  # id -> ColorRect
var _labels: Dictionary = {}  # id -> Label
var _label_ambiant: Label
var _zones_precedentes: Dictionary = {}  # id -> String

var _temps_ecoule := 0.0
var _prochain_print := 0.0

func _ready() -> void:
	_donnees = _charger_json("res://data/banc_lumiere.json")
	_catalogue_lumiere = _charger_json("res://data/lumiere.json")

	var cycle: Dictionary = _donnees.get("cycle_reel", {})
	_duree_jour_secondes = cycle.get("duree_jour_secondes", 40.0)
	_heure_depart = cycle.get("heure_depart", 0.0)

	_torche = _source_depuis_declaration(_donnees.get("torche", {}))
	_cristal = _source_depuis_declaration(_donnees.get("cristal", {}))
	_lanterne_config = _donnees.get("lanterne", {})

	for decl_lecteur in _donnees.get("lecteurs", []):
		var pos: Array = decl_lecteur.position
		_lecteurs.append(fabriquer_lecteur(decl_lecteur.id, Vector3(pos[0], pos[1], pos[2])))
		_zones_precedentes[decl_lecteur.id] = ""

	var zones: Dictionary = _donnees.get("zones", {})
	_seuil_jour = zones.get("seuil_jour", 0.5)
	_seuil_penombre = zones.get("seuil_penombre", 0.1)

	var couleurs: Dictionary = _donnees.get("couleurs_affichage", {})
	_couleur_orange = _couleur_depuis_array(couleurs.get("orange", [1.0, 0.55, 0.1]))
	_couleur_blanc_jaune = _couleur_depuis_array(couleurs.get("blanc_jaune", [1.0, 0.95, 0.8]))
	_couleur_bleu = _couleur_depuis_array(couleurs.get("bleu", [0.25, 0.45, 0.9]))

	_intervalle_print = _donnees.get("intervalle_print", 3.0)

	_fond = ColorRect.new()
	_fond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fond.size = Vector2(4000.0, 3000.0)
	_fond.position = Vector2(-2000.0, -1500.0)
	add_child(_fond)
	move_child(_fond, 0)

	_noeud_torche = _dessiner_source(_torche.position, couleur_affichage(_torche.temperature_couleur, _couleur_orange, _couleur_blanc_jaune, _couleur_bleu))
	_noeud_cristal = _dessiner_source(_cristal.position, couleur_affichage(_cristal.temperature_couleur, _couleur_orange, _couleur_blanc_jaune, _couleur_bleu))
	var pos_lanterne_initiale := position_lanterne(_vecteur_depuis_array(_lanterne_config.get("centre", [0.0, 0.0, 0.0])), _lanterne_config.get("amplitude", 0.0), _lanterne_config.get("periode", 1.0), 0.0)
	_noeud_lanterne = _dessiner_source(pos_lanterne_initiale, couleur_affichage(_lanterne_config.get("temperature_couleur", 0.5), _couleur_orange, _couleur_blanc_jaune, _couleur_bleu))

	for lecteur in _lecteurs:
		var carre := ColorRect.new()
		carre.mouse_filter = Control.MOUSE_FILTER_IGNORE
		carre.size = Vector2(TAILLE_LECTEUR, TAILLE_LECTEUR)
		carre.color = Color.BLACK
		carre.position = Vector2(lecteur.position.x, lecteur.position.y) - carre.size / 2.0
		add_child(carre)
		_noeuds_lecteurs[lecteur.id] = carre

	var couche_ui := CanvasLayer.new()
	add_child(couche_ui)
	_label_ambiant = Label.new()
	_label_ambiant.position = Vector2(10.0, 10.0)
	couche_ui.add_child(_label_ambiant)

	var decalage_y := 40.0
	for lecteur in _lecteurs:
		var label := Label.new()
		label.position = Vector2(10.0, decalage_y)
		couche_ui.add_child(label)
		_labels[lecteur.id] = label
		decalage_y += 34.0

	var decl_camera: Dictionary = _donnees.get("camera", {})
	var pos_camera: Array = decl_camera.get("position", [0.0, 0.0, 0.0])
	var camera := Camera2D.new()
	camera.position = Vector2(pos_camera[0], pos_camera[1])
	camera.zoom = Vector2(decl_camera.get("zoom", 0.55), decl_camera.get("zoom", 0.55))
	camera.enabled = true
	add_child(camera)

func _process(delta: float) -> void:
	_temps_ecoule += delta

	var heures_par_jour: float = _catalogue_lumiere.get("defaut", {}).get("cycle", {}).get("heures_par_jour", 24.0)
	var heure := heure_courante(_temps_ecoule, _duree_jour_secondes, heures_par_jour, _heure_depart)
	var latitude: float = _catalogue_lumiere.get("defaut", {}).get("latitude_demonstration", 45.0)

	var ambiante: Dictionary = Lumiere.soleil(heure, latitude, _catalogue_lumiere)
	var catalogue_tick: Dictionary = _catalogue_lumiere.duplicate(true)
	catalogue_tick["defaut"]["ambiante"] = ambiante

	var pos_lanterne := position_lanterne(_vecteur_depuis_array(_lanterne_config.get("centre", [0.0, 0.0, 0.0])), _lanterne_config.get("amplitude", 0.0), _lanterne_config.get("periode", 1.0), _temps_ecoule)
	var lanterne := _source_a_position(_lanterne_config, pos_lanterne)
	var sources := sources_du_tick(_torche, _cristal, lanterne)

	# Le lecteur porteur_lanterne colle a la position courante de la lanterne.
	for lecteur in _lecteurs:
		if lecteur.id == "porteur_lanterne":
			lecteur.position = pos_lanterne

	Lumiere.avancer(_lecteurs, sources, delta, catalogue_tick)

	_fond.color = couleur_lecteur(ambiante.intensite, ambiante.couleur, _couleur_orange, _couleur_blanc_jaune, _couleur_bleu)
	_noeud_torche.position = Vector2(_torche.position.x, _torche.position.y) - _noeud_torche.size / 2.0
	_noeud_cristal.position = Vector2(_cristal.position.x, _cristal.position.y) - _noeud_cristal.size / 2.0
	_noeud_lanterne.position = Vector2(pos_lanterne.x, pos_lanterne.y) - _noeud_lanterne.size / 2.0

	_label_ambiant.text = "heure = %.2f\nintensite ambiante = %.2f\ncouleur ambiante = %.2f" % [heure, ambiante.intensite, ambiante.couleur]

	for lecteur in _lecteurs:
		var intensite: float = lecteur.proprietes.intensite_lumiere
		var couleur: float = lecteur.proprietes.couleur_lumiere
		var noeud: ColorRect = _noeuds_lecteurs[lecteur.id]
		noeud.position = Vector2(lecteur.position.x, lecteur.position.y) - noeud.size / 2.0
		noeud.color = couleur_lecteur(intensite, couleur, _couleur_orange, _couleur_blanc_jaune, _couleur_bleu)
		_labels[lecteur.id].text = texte_lecteur(lecteur.id, intensite, couleur)

		var zone := zone_pour_intensite(intensite, _seuil_jour, _seuil_penombre)
		var zone_avant: String = _zones_precedentes[lecteur.id]
		if zone != zone_avant:
			if zone_avant != "":
				print(ligne_changement_zone(lecteur.id, heure, zone_avant, zone))
			_zones_precedentes[lecteur.id] = zone

	if _temps_ecoule >= _prochain_print:
		_prochain_print = _temps_ecoule + _intervalle_print
		print(ligne_rapport(heure, ambiante, _lecteurs))

# ---- Fonctions statiques, pures, testables ----

# Heure simulee au temps ecoule (secondes reelles) : mappe lineairement
# `duree_jour_secondes` (secondes reelles pour un cycle complet) sur
# `heures_par_jour` (issu de data/lumiere.json, jamais 24.0 en dur ici),
# boucle sans fin (fmod), part de `heure_depart` -- fonction PURE du
# temps, meme discipline que vent.gd/banc_temperature.gd. duree_jour_secondes
# <= 0.0 : reste bloque sur heure_depart, jamais une division par zero.
static func heure_courante(temps_ecoule: float, duree_jour_secondes: float, heures_par_jour: float, heure_depart: float) -> float:
	if duree_jour_secondes <= 0.0:
		return heure_depart
	var heures_ecoulees: float = (temps_ecoule / duree_jour_secondes) * heures_par_jour
	return fmod(heure_depart + heures_ecoulees, heures_par_jour)

# Position de la lanterne a l'instant `temps` : un aller-retour
# sinusoidal autour de `centre`, fonction PURE du temps -- meme patron que
# banc_temperature.gd:position_source_mobile, recopie jamais partage.
# `periode` <= 0.0 : la source reste immobile au centre.
static func position_lanterne(centre: Vector3, amplitude: float, periode: float, temps: float) -> Vector3:
	if periode <= 0.0:
		return centre
	var decalage: float = amplitude * sin(TAU * temps / periode)
	return centre + Vector3(decalage, 0.0, 0.0)

static func fabriquer_lecteur(id: String, position: Vector3) -> Dictionary:
	return {"id": id, "position": position, "proprietes": {}}

# Les trois sources de ce tick, dans la forme attendue par
# lumiere.gd:locale/avancer -- construites ICI, jamais par le mecanisme.
static func sources_du_tick(torche: Dictionary, cristal: Dictionary, lanterne: Dictionary) -> Array:
	return [torche, cristal, lanterne]

# INTERPOLATION EN DEUX MORCEAUX (orange -> blanc-jaune sur [0.0, 0.5],
# blanc-jaune -> bleu sur [0.5, 1.0]) -- meme idiome que
# vent.gd:facteur_directionnel, pour la meme raison : un point milieu NOMME
# (0.5 = blanc-jaune) qu'une seule droite entre les deux extremes ne
# produirait jamais (une seule droite orange->bleu rendrait un gris-mauve
# terne a 0.5, pas un blanc-jaune de plein midi). Couleur brute, PAS
# ponderee par l'intensite -- voir couleur_lecteur pour la luminosite.
static func couleur_affichage(couleur: float, orange: Color = Color(1.0, 0.55, 0.1), blanc_jaune: Color = Color(1.0, 0.95, 0.8), bleu: Color = Color(0.25, 0.45, 0.9)) -> Color:
	var c: float = clamp(couleur, 0.0, 1.0)
	if c <= 0.5:
		return orange.lerp(blanc_jaune, c / 0.5)
	return blanc_jaune.lerp(bleu, (c - 0.5) / 0.5)

# Couleur AFFICHEE d'un lecteur : la teinte (couleur_affichage) ternie vers
# le noir a mesure que l'intensite baisse -- 0.0 = noir total (quelle que
# soit la couleur, invisible), 1.0 = teinte pleine. Deux roles distincts,
# jamais confondus : intensite pilote la LUMINOSITE, couleur pilote la
# TEINTE.
static func couleur_lecteur(intensite: float, couleur: float, orange: Color, blanc_jaune: Color, bleu: Color) -> Color:
	var teinte := couleur_affichage(couleur, orange, blanc_jaune, bleu)
	return Color.BLACK.lerp(teinte, clamp(intensite, 0.0, 1.0))

# Zone DISCRETE pour le log de changement significatif -- jamais l'epsilon
# fin d'avancer(), qui derive en continu pendant tout le cycle et
# loggerait a quasiment chaque frame (verifie a l'ecriture, voir en-tete).
static func zone_pour_intensite(intensite: float, seuil_jour: float, seuil_penombre: float) -> String:
	if intensite >= seuil_jour:
		return "jour"
	if intensite >= seuil_penombre:
		return "penombre"
	return "nuit"

static func texte_lecteur(id: String, intensite: float, couleur: float) -> String:
	return "%s : intensite=%.2f couleur=%.2f" % [id, intensite, couleur]

static func ligne_rapport(heure: float, ambiante: Dictionary, lecteurs: Array) -> String:
	var texte := "t(heure)=%.2f ambiante(intensite=%.2f couleur=%.2f)" % [heure, ambiante.intensite, ambiante.couleur]
	for lecteur in lecteurs:
		texte += " | %s" % texte_lecteur(lecteur.id, lecteur.proprietes.get("intensite_lumiere", 0.0), lecteur.proprietes.get("couleur_lumiere", 0.0))
	return texte

static func ligne_changement_zone(id: String, heure: float, zone_avant: String, zone_apres: String) -> String:
	return "t(heure)=%.2f %s : %s -> %s" % [heure, id, zone_avant, zone_apres]

# ---- Rendu/chargement, jetable ----

func _source_depuis_declaration(decl: Dictionary) -> Dictionary:
	var pos: Array = decl.get("position", [0.0, 0.0, 0.0])
	return {
		"position": Vector3(pos[0], pos[1], pos[2]),
		"rayon": decl.get("rayon", 50.0),
		"intensite": decl.get("intensite", 0.5),
		"temperature_couleur": decl.get("temperature_couleur", 0.5),
		"force": decl.get("force", 1.0),
	}

func _source_a_position(decl: Dictionary, position: Vector3) -> Dictionary:
	return {
		"position": position,
		"rayon": decl.get("rayon", 50.0),
		"intensite": decl.get("intensite", 0.5),
		"temperature_couleur": decl.get("temperature_couleur", 0.5),
		"force": decl.get("force", 1.0),
	}

func _dessiner_source(position3: Vector3, couleur: Color) -> ColorRect:
	var marqueur := ColorRect.new()
	marqueur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marqueur.size = Vector2(TAILLE_SOURCE, TAILLE_SOURCE)
	marqueur.color = couleur
	marqueur.position = Vector2(position3.x, position3.y) - marqueur.size / 2.0
	add_child(marqueur)
	return marqueur

func _vecteur_depuis_array(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])

func _couleur_depuis_array(rgb: Array) -> Color:
	return Color(rgb[0], rgb[1], rgb[2])

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
