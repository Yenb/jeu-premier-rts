extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_dilatation.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1, coexiste avec les autres
# bancs). Existe pour VOIR la dilatation thermique (chantier "colonne
# thermique", case 5, DERNIERE case du tableau Thermique --
# scripts/temperature.gd:avancer) jouer sur une scene observable --
# PREMIERE DEMONSTRATION REELLE. JETABLE PAR DEFINITION. Recopie le patron
# de scripts/banc_temperature.gd (Node impur + fonctions statiques pures
# testables, Label par objet en Node2D -- patron banc_etat_effectif.gd --
# Camera2D fixe).
#
# CE QU'IL DOIT MONTRER : deux objets, CONSTRUITS DIRECTEMENT par ce banc
# (temperature/conductivite_thermique/dilatation_thermique/volume/masse
# poses en donnee locale -- PAS via Objet.fabriquer/composition/
# materiaux.json, meme discipline que banc_temperature.gd, voir son
# en-tete) : "chauffe" part a l'ambiante pres d'une source fixe et GROSSIT
# en chauffant ; "refroidi" part deja chaud, hors de portee de toute
# source, et RETRECIT en retombant vers l'ambiante -- meme coefficient de
# dilatation, mouvement en miroir. Chaque carre change de TAILLE (aire
# proportionnelle au volume, taille_pour_volume) et de COULEUR (froid ->
# chaud, meme patron que banc_temperature.gd). Un Label AU-DESSUS de
# chaque carre (patron banc_etat_effectif.gd, Node2D positionne dans le
# monde, pas un CanvasLayer) affiche EN PERMANENCE temperature/volume/
# densite. La console imprime une ligne PAR OBJET a chaque CHANGEMENT
# SIGNIFICATIF de volume (seuil_variation_significative, donnee) --
# jamais a chaque frame.
#
# COEFFICIENT DE DEMONSTRATION, PAS LA VALEUR REELLE : dilatation_thermique
# vaut ici 0.04 (data/banc_dilatation.json), jamais 5.0/8.0/12.0
# (bois/pierre/fer, data/materiaux.json, deja fusionnes a la fabrication
# depuis ce chantier) -- la formule LITTERALE de temperature.gd (dV =
# dilatation_thermique * dT, sans mise a l'echelle) rendrait le volume d'un
# objet reel demesure sur l'ecart de temperature demande ici ("modeste",
# pour rester lisible, voir data/banc_dilatation.json, _note). Ce banc ne
# touche donc JAMAIS data/materiaux.json ni data/proprietes_immuables_
# composition.json (deja modifie par ce chantier, piece 1, pour les
# BANCS/MECANISME reels) : sa propre valeur de dilatation reste LOCALE,
# comme conductivite_thermique l'est deja dans banc_temperature.gd.
#
# PORTEE VOLONTAIREMENT LIMITEE : ce banc ne route rien par
# attaches.gd/proximite.gd/jugement.gd/dominance.gd/agir.gd -- aucune
# decision, seulement l'appel du mecanisme de temperature sur deux objets
# immobiles. Aucun allumage, aucun seuil de fusion/ebullition, aucun abri
# -- hors perimetre.
#
# Deux moities, meme decoupage que banc_temperature.gd :
# - Node (impur) : _ready charge data/banc_dilatation.json (jetable, propre
#   a ce banc) et data/temperature.json (catalogue PARTAGE, reel, jamais
#   surcharge ni mute ici). _process appelle Temperature.avancer, redessine
#   les deux carres et leurs Labels, imprime une ligne par objet au
#   franchissement du seuil de variation.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_dilatation.gd) : fabriquer_objet, taille_pour_volume,
#   couleur_pour_temperature, texte_objet, doit_imprimer, ligne_log.

const Temperature = preload("res://scripts/temperature.gd")

var _catalogue_temperature: Dictionary = {}
var _sources: Array = []
var _volume_reference := 6.0
var _taille_base := 50.0
var _couleur_froid := Color.BLUE
var _couleur_chaud := Color.RED
var _echelle_min := 0.0
var _echelle_max := 100.0
var _seuil_variation := 0.3

var _objets: Array = []
var _noeuds: Dictionary = {}
var _labels: Dictionary = {}
var _dernier_volume_imprime: Dictionary = {}
var _temps_ecoule := 0.0

func _ready() -> void:
	var donnees := _charger_json("res://data/banc_dilatation.json")
	_catalogue_temperature = _charger_json("res://data/temperature.json")

	_volume_reference = donnees.get("volume_reference", 6.0)
	_taille_base = donnees.get("taille_base", 50.0)
	_couleur_froid = _couleur_depuis_array(donnees.get("couleur_froid", [0.15, 0.35, 0.85]))
	_couleur_chaud = _couleur_depuis_array(donnees.get("couleur_chaud", [0.85, 0.15, 0.1]))
	var echelle: Dictionary = donnees.get("echelle_couleur", {})
	_echelle_min = echelle.get("min", 0.0)
	_echelle_max = echelle.get("max", 100.0)
	_seuil_variation = donnees.get("seuil_variation_significative", 0.3)

	var decl_source: Dictionary = donnees.get("source_chaude", {})
	var pos_source: Array = decl_source.get("position", [0.0, 0.0, 0.0])
	_sources = [{
		"position": Vector3(pos_source[0], pos_source[1], pos_source[2]),
		"rayon": decl_source.get("rayon", 400.0),
		"temperature": decl_source.get("temperature", 90.0),
		"force": decl_source.get("force", 1.0),
	}]

	_objets = [
		_objet_depuis_declaration("chauffe", donnees.get("chauffe", {})),
		_objet_depuis_declaration("refroidi", donnees.get("refroidi", {})),
	]

	for objet in _objets:
		_dernier_volume_imprime[objet.id] = objet.proprietes.volume
		print(ligne_log(0.0, objet.id, objet.proprietes.temperature, objet.proprietes.volume, objet.proprietes.densite))

		var noeud := ColorRect.new()
		noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(noeud)
		_noeuds[objet.id] = noeud

		var label := Label.new()
		add_child(label)
		_labels[objet.id] = label

	_rafraichir_tout()

	var decl_camera: Dictionary = donnees.get("camera", {})
	var pos_camera: Array = decl_camera.get("position", [0.0, 0.0, 0.0])
	var camera := Camera2D.new()
	camera.position = Vector2(pos_camera[0], pos_camera[1])
	camera.zoom = Vector2(decl_camera.get("zoom", 1.0), decl_camera.get("zoom", 1.0))
	camera.enabled = true
	add_child(camera)

func _process(delta: float) -> void:
	_temps_ecoule += delta
	Temperature.avancer(_objets, _sources, delta, _catalogue_temperature)
	_rafraichir_tout()

	for objet in _objets:
		var volume: float = objet.proprietes.volume
		if doit_imprimer(volume, _dernier_volume_imprime[objet.id], _seuil_variation):
			print(ligne_log(_temps_ecoule, objet.id, objet.proprietes.temperature, volume, objet.proprietes.densite))
			_dernier_volume_imprime[objet.id] = volume

func _objet_depuis_declaration(id: String, decl: Dictionary) -> Dictionary:
	var pos: Array = decl.get("position", [0.0, 0.0, 0.0])
	return fabriquer_objet(
		id,
		Vector3(pos[0], pos[1], pos[2]),
		decl.get("temperature_initiale", 20.0),
		decl.get("conductivite_thermique", 0.25),
		decl.get("dilatation_thermique", 0.0),
		decl.get("volume_initial", 6.0),
		decl.get("masse", 12.0),
	)

func _rafraichir_tout() -> void:
	for objet in _objets:
		var temperature: float = objet.proprietes.temperature
		var volume: float = objet.proprietes.volume
		var densite: float = objet.proprietes.densite
		var noeud: ColorRect = _noeuds[objet.id]
		var taille := taille_pour_volume(volume, _volume_reference, _taille_base)
		noeud.size = Vector2(taille, taille)
		noeud.position = Vector2(objet.position.x, objet.position.y) - noeud.size / 2.0
		noeud.color = couleur_pour_temperature(temperature, _echelle_min, _echelle_max, _couleur_froid, _couleur_chaud)

		var label: Label = _labels[objet.id]
		label.position = Vector2(objet.position.x, objet.position.y) - Vector2(_taille_base / 2.0, _taille_base / 2.0 + 70.0)
		label.text = texte_objet(objet.id, temperature, volume, densite)

# ---- Fonctions statiques, pures, testables ----

# L'objet construit DIRECTEMENT par ce banc (comme fabriquer_objet_test de
# banc_temperature.gd) -- porte les cinq cles que temperature.gd lit ou
# ecrit (temperature, conductivite_thermique, dilatation_thermique, volume,
# masse) plus densite, deduite ICI une seule fois (masse/volume_initial,
# meme formule que celle que temperature.gd:avancer reapplique ensuite a
# chaque pas) -- jamais recalculee autrement qu'en cet unique endroit avant
# le premier appel a Temperature.avancer. volume_initial <= 0.0 : densite
# repliee sur 0.0 (donnee incoherente, jamais une division par zero).
static func fabriquer_objet(id: String, position: Vector3, temperature_initiale: float, conductivite: float, dilatation: float, volume_initial: float, masse: float) -> Dictionary:
	var densite_initiale: float = masse / volume_initial if volume_initial > 0.0 else 0.0
	return {
		"id": id,
		"position": position,
		"proprietes": {
			"temperature": temperature_initiale,
			"conductivite_thermique": conductivite,
			"dilatation_thermique": dilatation,
			"volume": volume_initial,
			"masse": masse,
			"densite": densite_initiale,
		},
	}

# PURE, testable -- aire du carre PROPORTIONNELLE au volume (taille au
# carre proportionnelle a l'aire, donc taille proportionnelle a
# sqrt(volume)), jamais une echelle lineaire qui exagererait visuellement
# un doublement de volume en un quadruplement de taille. volume_reference
# <= 0.0 ou volume <= 0.0 : replie sur 0.0 (carre invisible plutot qu'une
# racine negative), donnee extreme jamais rencontree avec les valeurs
# reelles de ce banc.
static func taille_pour_volume(volume: float, volume_reference: float, taille_base: float) -> float:
	if volume_reference <= 0.0 or volume <= 0.0:
		return 0.0
	return taille_base * sqrt(volume / volume_reference)

# PURE, testable -- couleur FROID -> CHAUD, meme formule que
# banc_temperature.gd:couleur_pour_temperature (duplication volontaire,
# aucun etat partage entre les deux bancs -- voir docs/design.md, la
# couleur n'est jamais un geste du mecanisme).
static func couleur_pour_temperature(temperature: float, mini: float, maxi: float, couleur_froid: Color, couleur_chaud: Color) -> Color:
	if maxi <= mini:
		return couleur_froid
	var ratio: float = clamp((temperature - mini) / (maxi - mini), 0.0, 1.0)
	return couleur_froid.lerp(couleur_chaud, ratio)

# PURE, testable -- texte du Label permanent d'un objet : les trois nombres
# demandes par la tache (temperature, volume, densite), rien de plus.
static func texte_objet(id: String, temperature: float, volume: float, densite: float) -> String:
	return "%s\ntemperature = %.1f\nvolume = %.2f\ndensite = %.3f" % [id, temperature, volume, densite]

# PURE, testable -- "changement significatif" : le volume a bouge d'au
# moins `seuil` depuis la derniere impression, dans un sens ou l'autre.
# seuil <= 0.0 : imprime a chaque appel (garde degeneree, ne doit jamais
# arriver avec la donnee reelle).
static func doit_imprimer(volume_actuel: float, dernier_volume_imprime: float, seuil: float) -> bool:
	if seuil <= 0.0:
		return true
	return absf(volume_actuel - dernier_volume_imprime) >= seuil

static func ligne_log(t: float, id: String, temperature: float, volume: float, densite: float) -> String:
	return "t=%.1f %s : temperature=%.1f volume=%.2f densite=%.3f" % [t, id, temperature, volume, densite]

# ---- Rendu/IO, jetable ----

func _couleur_depuis_array(rgb: Array) -> Color:
	return Color(rgb[0], rgb[1], rgb[2])

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
