extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_friction.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1, coexiste avec les autres
# bancs). Chantier « friction -- fusionner et cabler » : "friction"
# (data/materiaux.json, bois 0.4/pierre 0.65/fer 0.5, DORMANTE depuis la
# creation du catalogue) rejoint enfin data/proprietes_immuables_
# composition.json (voir §4) -- avant ce chantier, un objet fabrique par
# composition ne portait JAMAIS proprietes.friction, ce qui rendait INERTE
# la fondation dormante data/etats.json:mouille (module friction x0.4,
# posee au chantier humidite, verrouillee par test_fondations_humidite.gd
# -- son propre en-tete le dit explicitement : « personne ne les fusionne
# sur proprietes a la fabrication, personne ne les lit encore »). Ce banc
# est la PREMIERE lecture reelle de "friction" -- sur un objet FABRIQUE
# (Objet.fabriquer/composition/materiaux.json, jamais construit a la main,
# contrairement a banc_dilatation.gd/banc_temperature.gd) ET la PREMIERE
# consommation reelle de la modulation "mouille" sur friction (meme statut
# que "mouille x10.0 sur conductivite_electrique" avant banc_conduction.gd).
#
# AUCUN MECANISME DU COEUR TOUCHE : etat_effectif.gd/objet.gd/banc_commun.gd
# restent inchanges. Une seule ligne de donnee au-dela de ce fichier et de
# data/banc_friction.json (jetable, propre au banc) : "friction" rejoint
# data/proprietes_immuables_composition.json (voir §4).
#
# CE QU'ON DOIT VOIR : trois objets fabriques (bois/pierre/fer, un materiau
# reel chacun) glissent depuis t=0 sous une force identique -- AUCUN bouton
# de poussee, la poussee est permanente, seul le clic gauche bascule
# "mouille" sur LES TROIS A LA FOIS (meme geste que banc_humidite.gd/
# banc_conduction.gd appliques a un objet unique). La VITESSE EFFECTIVE de
# chaque objet est vitesse_base * (1.0 - friction_effective) --
# friction_effective vient de EtatEffectif.valeur(objet, "friction", etats),
# JAMAIS reimplementee. A sec : bois (friction 0.4) glisse le plus vite
# (vitesse effective 0.6*base), fer (0.5) au milieu (0.5*base), pierre
# (0.65) le moins vite (0.35*base) -- la distance parcourue, qui s'accumule
# sans jamais redescendre, reflete cet ordre a tout instant t>0. Mouille,
# la friction effective de chacun tombe a x0.4 de sa base (0.16/0.2/0.26) :
# les trois glissent alors visiblement plus vite qu'a sec, et l'ecart
# bois/pierre (vitesse effective 0.84*base contre 0.74*base) reste net.
# Un objet a friction_effective 1.0 ne bougerait jamais (vitesse_effective
# rendrait 0.0) ; un objet a friction_effective 0.0 glisserait a vitesse_base
# exacte, sans aucune resistance -- aucun des trois materiaux reels de ce
# banc n'atteint ces deux bornes, verifiees separement par
# test_banc_friction.gd sur la fonction pure seule.
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge les donnees et fabrique les trois objets
#   (Objet.fabriquer, composition fusionnee -- meme patron que
#   banc_humidite.gd/banc_conduction.gd). _unhandled_input bascule "mouille"
#   sur les trois au clic gauche. _process appelle UNIQUEMENT avancer()
#   (fonction statique, ci-dessous) puis lit ses resultats pour
#   l'affichage/la console -- jamais un calcul refait ici.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_friction.gd) : vitesse_effective/avancer/basculer_mouille/
#   est_mouille/fabriquer_objets/diagnostiquer/doit_imprimer_recap, plus le
#   texte d'affichage et de log.

const Objet = preload("res://scripts/objet.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")

const PROPRIETE_FRICTION := "friction"
const TAILLE := 60.0
const HAUTEUR_BARRE := 8.0

var _config: Dictionary = {}
var _etats: Dictionary = {}
var _materiaux: Dictionary = {}
var _objets: Array = []
var _direction := Vector3.RIGHT
var _vitesse_base := 120.0
var _intervalle_log := 2.0
var _couleur_sec := Color(0.55, 0.42, 0.28)
var _couleur_mouille := Color(0.15, 0.35, 0.85)
var _noeuds: Dictionary = {}
var _labels: Dictionary = {}
var _temps := 0.0
var _dernier_log := 0.0
var _mouille_avant := false

func _ready() -> void:
	_config = _charger_json("res://data/banc_friction.json")
	_etats = _charger_json("res://data/etats.json")
	_materiaux = _charger_json("res://data/materiaux.json")
	var proprietes_immuables: Array = _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", [])

	var dir: Array = _config.get("direction", [1.0, 0.0, 0.0])
	_direction = Vector3(dir[0], dir[1], dir[2])
	_vitesse_base = _config.get("vitesse_base", 120.0)
	_intervalle_log = _config.get("intervalle_log", 2.0)
	_couleur_sec = _couleur_depuis_array(_config.get("couleur_sec", [0.55, 0.42, 0.28]))
	_couleur_mouille = _couleur_depuis_array(_config.get("couleur_mouille", [0.15, 0.35, 0.85]))

	_objets = fabriquer_objets(_config.get("objets", []), _materiaux, proprietes_immuables)
	for objet in _objets:
		_creer_rendu_objet(objet)
		print(ligne_pose_initiale(objet.id, diagnostiquer(objet, _etats)))

	_rafraichir_tout()
	_poser_camera()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		basculer_mouille(_objets)
		var actif := est_mouille(_objets[0]) if not _objets.is_empty() else false
		print(ligne_mouille(_temps, actif))
		_mouille_avant = actif
		_rafraichir_tout()

func _process(delta: float) -> void:
	_temps += delta
	avancer(_objets, _vitesse_base, _direction, delta, _etats)

	if doit_imprimer_recap(_temps, _dernier_log, _intervalle_log):
		print(ligne_recap(_temps, _objets, _etats))
		_dernier_log = _temps

	_rafraichir_tout()

func _rafraichir_tout() -> void:
	for objet in _objets:
		var id: String = objet.id
		var diag := diagnostiquer(objet, _etats)
		_noeuds[id].color = _couleur_mouille if diag.mouille else _couleur_sec
		_noeuds[id].position = Vector2(objet.position.x, objet.position.y) - _noeuds[id].size / 2.0
		_labels[id].text = texte_objet(id, diag)

# ---- Fonctions PURES, testables headless (voir test_banc_friction.gd) ----

# vitesse_base * (1.0 - friction_effective) -- voir en-tete. max(0.0, ...) :
# garde defensive, aucune donnee reelle du depot ne porte une friction
# effective au-dela de 1.0 aujourd'hui (mouille MODULE vers le bas, jamais
# vers le haut), mais une vitesse negative n'aurait aucun sens physique ici
# (l'objet reculerait au lieu de simplement s'arreter).
static func vitesse_effective(vitesse_base: float, friction_effective: float) -> float:
	return vitesse_base * max(0.0, 1.0 - friction_effective)

# UN PAS de simulation complet : pour chaque objet, lit sa friction
# EFFECTIVE (EtatEffectif.valeur, jamais reimplementee -- applique deja
# data/etats.json:mouille x0.4 si l'etat est present), en deduit sa vitesse
# effective, avance sa position SELON _direction (BancCommun.bouger_selon,
# jamais reimplemente) et accumule la distance parcourue sur
# proprietes.distance_parcourue -- MUTE les objets recus, comme
# Temperature.avancer/Charge.avancer.
static func avancer(objets: Array, vitesse_base: float, direction: Vector3, delta: float, etats: Dictionary) -> void:
	for objet in objets:
		var friction_eff: float = EtatEffectif.valeur(objet, PROPRIETE_FRICTION, etats)
		var v := vitesse_effective(vitesse_base, friction_eff)
		objet.position = BancCommun.bouger_selon(objet.position, direction, v, delta)
		objet.proprietes["distance_parcourue"] = objet.proprietes.get("distance_parcourue", 0.0) + v * delta

static func est_mouille(objet: Dictionary) -> bool:
	return objet.proprietes.get("etats_actifs", []).has("mouille")

# Bascule "mouille" sur TOUS les objets recus A LA FOIS (meme geste que
# banc_humidite.gd/banc_conduction.gd, applique ici a trois objets plutot
# qu'a une seule source) -- le nouvel etat (pose ou retire) est decide une
# seule fois depuis le premier objet, jamais par objet.
static func basculer_mouille(objets: Array) -> void:
	if objets.is_empty():
		return
	var actif := not est_mouille(objets[0])
	for objet in objets:
		var etats_actifs: Array = objet.proprietes.get("etats_actifs", [])
		if actif:
			if not etats_actifs.has("mouille"):
				etats_actifs.append("mouille")
		else:
			etats_actifs.erase("mouille")
		objet.proprietes["etats_actifs"] = etats_actifs

# Construit les trois objets via Objet.fabriquer (composition fusionnee --
# meme patron que banc_humidite.gd/banc_conduction.gd, catalogue LOCAL a une
# entree par id). "distance_parcourue" initialisee a 0.0 pour que le premier
# affichage (avant tout tick) montre 0.0 plutot qu'une absence.
static func fabriquer_objets(declarations: Array, materiaux: Dictionary, proprietes_immuables: Array) -> Array:
	var catalogue: Dictionary = {}
	for decl in declarations:
		catalogue[decl.id] = {"composition": decl.composition}
	var objets: Array = []
	for decl in declarations:
		var pos: Array = decl.position
		var objet := Objet.fabriquer(decl.id, decl.id, Vector3(pos[0], pos[1], pos[2]), catalogue, materiaux, proprietes_immuables)
		if objet.is_empty():
			continue
		objet.proprietes["etats_actifs"] = []
		objet.proprietes["distance_parcourue"] = 0.0
		objets.append(objet)
	return objets

# Diagnostic d'affichage, PUR : lit uniquement des valeurs deja calculees
# par etat_effectif.gd, ne reimplemente jamais sa loi (meme doctrine que
# banc_humidite.gd/banc_conduction.gd:diagnostiquer). Rend { friction_base,
# friction_effective, mouille, distance_parcourue }.
static func diagnostiquer(objet: Dictionary, etats: Dictionary) -> Dictionary:
	return {
		"friction_base": objet.proprietes.get(PROPRIETE_FRICTION, 0.0),
		"friction_effective": EtatEffectif.valeur(objet, PROPRIETE_FRICTION, etats),
		"mouille": est_mouille(objet),
		"distance_parcourue": objet.proprietes.get("distance_parcourue", 0.0),
	}

# "changement significatif" version temps, meme role que
# banc_dilatation.gd:doit_imprimer mais sur un intervalle fixe plutot qu'un
# seuil de variation -- intervalle <= 0.0 : imprime a chaque appel (garde
# degeneree, ne doit jamais arriver avec la donnee reelle).
static func doit_imprimer_recap(temps: float, dernier_log: float, intervalle: float) -> bool:
	if intervalle <= 0.0:
		return true
	return temps - dernier_log >= intervalle

static func texte_objet(id: String, diag: Dictionary) -> String:
	return "%s\nfriction (base) = %.2f\nfriction (effective) = %.3f\netat = %s\ndistance parcourue = %.1f" % [
		id, diag.friction_base, diag.friction_effective, "mouille" if diag.mouille else "sec", diag.distance_parcourue
	]

static func ligne_pose_initiale(id: String, diag: Dictionary) -> String:
	return "t=0.0s %s : friction_base=%.2f friction_effective=%.3f (sec)" % [id, diag.friction_base, diag.friction_effective]

static func ligne_mouille(t: float, actif: bool) -> String:
	return "t=%.1fs mouille : %s (les trois objets)" % [t, "POSE" if actif else "RETIRE"]

static func ligne_recap(t: float, objets: Array, etats: Dictionary) -> String:
	var morceaux: Array = []
	for objet in objets:
		var diag := diagnostiquer(objet, etats)
		morceaux.append("%s=%.1f" % [objet.id, diag.distance_parcourue])
	var texte := ""
	for i in range(morceaux.size()):
		if i > 0:
			texte += ", "
		texte += morceaux[i]
	return "t=%.1fs distance parcourue : %s" % [t, texte]

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

	var label := Label.new()
	label.position = centre - Vector2(TAILLE / 2.0, TAILLE / 2.0 + 90.0)
	add_child(label)
	_labels[id] = label

func _poser_camera() -> void:
	var decl_camera: Dictionary = _config.get("camera", {})
	var pos: Array = decl_camera.get("position", [0.0, 0.0, 0.0])
	var camera := Camera2D.new()
	camera.position = Vector2(pos[0], pos[1])
	camera.zoom = Vector2(decl_camera.get("zoom", 1.0), decl_camera.get("zoom", 1.0))
	camera.enabled = true
	add_child(camera)

func _couleur_depuis_array(rgb: Array) -> Color:
	return Color(rgb[0], rgb[1], rgb[2])

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
