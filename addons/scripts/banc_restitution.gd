extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_restitution.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1, coexiste avec les autres
# bancs). Chantier « restitution -- rebond apres impact » : "restitution"
# (data/materiaux.json, bois 0.5/pierre 0.6/fer 0.65, DORMANTE depuis la
# creation du catalogue, voir audit_colonne_mecanique_prealable.md
# propriete #8 -- aucun mecanisme candidat avant ce chantier) rejoint enfin
# data/proprietes_immuables_composition.json (voir CARTE.md §4) -- avant ce
# chantier, aucun objet fabrique par composition ne portait jamais
# proprietes.restitution.
#
# AUCUN MECANISME DU COEUR TOUCHE : frappe.gd/seuil_etat.gd/etat_effectif.gd/
# objet.gd/perception.gd/charge.gd/temperature.gd/lumiere.gd inchanges.
# "restitution" n'est modulee par AUCUN etat de data/etats.json (contrairement
# a "friction"/"mouille") -- lue en base seule, jamais via etat_effectif.gd.
#
# CONVENTION DE HAUTEUR : position.z porte la hauteur, meme convention que
# frappe.gd (critere "position_z")/banc_foudre.gd -- rendu a l'ecran par
# centre = Vector2(x, y - z), formule EXACTE de
# banc_foudre.gd:_creer_rendu_objet, ici recalculee CHAQUE FRAME (contrairement
# a la foudre, la position bouge ici a chaque tick).
#
# MECANIQUE (aucune physique Godot, aucun RigidBody -- un calcul de position
# par tick, cable a la main) : deux fonctions pures triviales --
# hauteur_apres_rebond (hauteur_precedente * restitution, EXACTEMENT
# l'enonce du chantier) et vitesse_pour_hauteur (cinematique d'un tir
# vertical sous gravite constante, v = racine(2*g*h) -- la vitesse initiale
# necessaire pour culminer a la hauteur h) -- composees par avancer(), qui
# integre position/vitesse par tick (vitesse -= gravite*delta, z +=
# vitesse*delta) et declenche un rebond des que l'objet franchit le sol en
# tombant. Chaque objet garde son propre "hauteur_pic" (hauteur de
# reference pour LE PROCHAIN rebond -- initialisee a la hauteur de chute,
# remplacee a chaque impact par la nouvelle hauteur) et "nombre_rebonds"
# (incremente SEULEMENT quand l'objet rebondit reellement, jamais au
# dernier contact qui l'arrete -- restitution 0.0 doit rendre nombre_rebonds
# EXACTEMENT 0, voir avancer()).
#
# CE QU'ON DOIT VOIR : trois objets fabriques (bois/pierre/fer, un materiau
# reel chacun), immobiles en l'air a la hauteur de chute, jusqu'au premier
# clic gauche qui les relache TOUS LES TROIS A LA FOIS (meme geste que
# banc_friction.gd:basculer_mouille, bistable -- un second clic les
# reinitialise en l'air, pret pour une nouvelle chute). Une fois relaches,
# chacun tombe, rebondit au sol a hauteur_precedente*restitution, remonte,
# retombe, de plus en plus bas -- le fer (restitution 0.65) rebondit le
# plus haut et le plus longtemps, le bois (0.5) s'arrete le plus vite, la
# pierre (0.6) entre les deux. Un objet dont le rebond calcule tomberait
# sous SEUIL_ARRET s'arrete au sol pour de bon (etat "arrete"). Label par
# objet : restitution, hauteur actuelle, nombre de rebonds. Trace console :
# une ligne par impact (rebond ou arret final).
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge les donnees et fabrique les trois objets
#   (Objet.fabriquer, composition fusionnee -- meme patron que
#   banc_friction.gd). _unhandled_input bascule la chute au clic gauche.
#   _process appelle UNIQUEMENT avancer() (fonction statique, ci-dessous)
#   puis lit ses resultats pour l'affichage/la console -- jamais un calcul
#   refait ici.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_restitution.gd) : hauteur_apres_rebond/vitesse_pour_hauteur/
#   avancer/basculer_chute/fabriquer_objets/diagnostiquer, plus le texte
#   d'affichage et de log.

const Objet = preload("res://scripts/objet.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")

const PROPRIETE_RESTITUTION := "restitution"
const TAILLE := 50.0

# Couleur de rendu par materiau -- purement cosmetique, propre a ce fichier
# (aucun mecanisme du coeur ne connait de couleur), meme role que
# _couleur_sec/_couleur_mouille de banc_friction.gd.
const COULEURS_MATERIAU := {
	"bois": Color(0.55, 0.42, 0.28),
	"pierre": Color(0.5, 0.5, 0.55),
	"fer": Color(0.65, 0.68, 0.72),
}
const FACTEUR_ASSOMBRI_ARRETE := 0.55

var _config: Dictionary = {}
var _materiaux: Dictionary = {}
var _objets: Array = []
var _couleurs: Dictionary = {}
var _gravite := 900.0
var _hauteur_initiale := 400.0
var _seuil_arret := 4.0
var _noeuds: Dictionary = {}
var _labels: Dictionary = {}
var _temps := 0.0

func _ready() -> void:
	_config = _charger_json("res://data/banc_restitution.json")
	_materiaux = _charger_json("res://data/materiaux.json")
	var proprietes_immuables: Array = _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", [])

	_gravite = _config.get("gravite", 900.0)
	_hauteur_initiale = _config.get("hauteur_initiale", 400.0)
	_seuil_arret = _config.get("seuil_arret", 4.0)

	_objets = fabriquer_objets(_config.get("objets", []), _materiaux, proprietes_immuables, _hauteur_initiale)
	for decl in _config.get("objets", []):
		var nom_materiau: String = decl.composition[0].materiau
		_couleurs[decl.id] = COULEURS_MATERIAU.get(nom_materiau, Color(0.8, 0.8, 0.8))

	for objet in _objets:
		_creer_rendu_objet(objet)
	_creer_sol()
	_rafraichir_tout()
	_poser_camera()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var relache := basculer_chute(_objets, _hauteur_initiale)
		print(ligne_bascule(_temps, relache))
		_rafraichir_tout()

func _process(delta: float) -> void:
	_temps += delta
	var impacts := avancer(_objets, _gravite, delta, _seuil_arret)
	for id in impacts:
		print(ligne_impact(_temps, _objet_par_id(id)))
	_rafraichir_tout()

func _objet_par_id(id: String) -> Dictionary:
	for objet in _objets:
		if objet.id == id:
			return objet
	return {}

func _rafraichir_tout() -> void:
	for objet in _objets:
		var id: String = objet.id
		var diag := diagnostiquer(objet)
		var centre := Vector2(objet.position.x, objet.position.y - objet.position.z)
		_noeuds[id].position = centre - _noeuds[id].size / 2.0
		var couleur: Color = _couleurs.get(id, Color(0.8, 0.8, 0.8))
		_noeuds[id].color = couleur * FACTEUR_ASSOMBRI_ARRETE if diag.arrete else couleur
		_labels[id].position = centre - Vector2(TAILLE / 2.0, TAILLE / 2.0 + 60.0)
		_labels[id].text = texte_objet(id, diag)

# ---- Fonctions PURES, testables headless (voir test_banc_restitution.gd) ----

# hauteur_precedente * restitution -- EXACTEMENT l'enonce du chantier,
# aucun autre facteur. restitution 0.0 rend toujours 0.0 (jamais de rebond) ;
# restitution 1.0 rend hauteur_precedente inchangee (conservation parfaite).
static func hauteur_apres_rebond(hauteur_precedente: float, restitution: float) -> float:
	return hauteur_precedente * restitution

# Cinematique d'un tir vertical sous gravite constante : v^2 = 2*g*h, donc
# v = racine(2*g*h) -- la vitesse ascendante initiale necessaire pour
# culminer EXACTEMENT a "hauteur" avant de retomber. hauteur <= 0.0 : rend
# 0.0 (aucune vitesse necessaire pour "culminer" a zero).
static func vitesse_pour_hauteur(hauteur: float, gravite: float) -> float:
	if hauteur <= 0.0:
		return 0.0
	return sqrt(2.0 * gravite * hauteur)

# UN PAS de simulation complet pour tous les objets EN CHUTE (proprietes.
# en_chute, jamais un objet encore tenu en l'air ni deja arrete) : integre
# vitesse/position (garde vitesse -= gravite*delta, z += vitesse*delta),
# detecte le franchissement du sol EN TOMBANT (z <= 0.0 ET vitesse < 0.0,
# jamais au depart ou en montee) et y declenche un rebond -- MUTE les
# objets recus, comme Charge.avancer/Deformation.avancer. Rend la liste des
# ids qui ont subi un impact CE TICK (rebond ou arret), pour que l'appelant
# imprime une ligne par impact, jamais par tick.
static func avancer(objets: Array, gravite: float, delta: float, seuil_arret: float) -> Array:
	var impacts: Array = []
	for objet in objets:
		if not objet.proprietes.get("en_chute", false):
			continue
		if objet.proprietes.get("arrete", false):
			continue

		var vitesse: float = objet.proprietes.get("vitesse_verticale", 0.0)
		var z: float = objet.position.z
		vitesse -= gravite * delta
		z += vitesse * delta

		if z <= 0.0 and vitesse < 0.0:
			var restitution: float = objet.proprietes.get(PROPRIETE_RESTITUTION, 0.0)
			var hauteur_pic: float = objet.proprietes.get("hauteur_pic", 0.0)
			var nouvelle_hauteur := hauteur_apres_rebond(hauteur_pic, restitution)
			z = 0.0
			if nouvelle_hauteur < seuil_arret:
				vitesse = 0.0
				objet.proprietes["arrete"] = true
				objet.proprietes["hauteur_pic"] = 0.0
			else:
				vitesse = vitesse_pour_hauteur(nouvelle_hauteur, gravite)
				objet.proprietes["hauteur_pic"] = nouvelle_hauteur
				objet.proprietes["nombre_rebonds"] = int(objet.proprietes.get("nombre_rebonds", 0)) + 1
			impacts.append(objet.id)

		objet.position.z = z
		objet.proprietes["vitesse_verticale"] = vitesse
	return impacts

# Bascule "en_chute" sur TOUS les objets recus A LA FOIS (meme geste que
# banc_friction.gd:basculer_mouille) : relachement (repos -> chute, l'etat
# de chute actuel N'EST PAS reinitialise, l'objet tombe simplement d'ou il
# etait) OU reinitialisation complete (chute -> repos, hauteur/vitesse/
# compteur/arret remis a l'etat de depart, pret pour une nouvelle chute).
# Rend "true" si le geste vient de RELACHER (pour le log), "false" s'il vient
# de reinitialiser.
static func basculer_chute(objets: Array, hauteur_initiale: float) -> bool:
	if objets.is_empty():
		return false
	var relache: bool = not objets[0].proprietes.get("en_chute", false)
	for objet in objets:
		if relache:
			objet.proprietes["en_chute"] = true
		else:
			objet.proprietes["en_chute"] = false
			objet.proprietes["arrete"] = false
			objet.proprietes["vitesse_verticale"] = 0.0
			objet.proprietes["hauteur_pic"] = hauteur_initiale
			objet.proprietes["nombre_rebonds"] = 0
			objet.position.z = hauteur_initiale
	return relache

# Construit les trois objets via Objet.fabriquer (composition fusionnee --
# meme patron que banc_friction.gd, catalogue LOCAL a une entree par id),
# puis pose l'etat de chute initial : au repos, en l'air, a hauteur_initiale.
static func fabriquer_objets(declarations: Array, materiaux: Dictionary, proprietes_immuables: Array, hauteur_initiale: float) -> Array:
	var catalogue: Dictionary = {}
	for decl in declarations:
		catalogue[decl.id] = {"composition": decl.composition}
	var objets: Array = []
	for decl in declarations:
		var pos: Array = decl.position
		var objet := Objet.fabriquer(decl.id, decl.id, Vector3(pos[0], pos[1], hauteur_initiale), catalogue, materiaux, proprietes_immuables)
		if objet.is_empty():
			continue
		objet.proprietes["en_chute"] = false
		objet.proprietes["arrete"] = false
		objet.proprietes["vitesse_verticale"] = 0.0
		objet.proprietes["hauteur_pic"] = hauteur_initiale
		objet.proprietes["nombre_rebonds"] = 0
		objets.append(objet)
	return objets

# Diagnostic d'affichage, PUR : lit uniquement des valeurs deja posees par
# fabriquer_objets/avancer/basculer_chute, ne recalcule jamais rien. Rend
# { restitution, hauteur, nombre_rebonds, arrete, en_chute }.
static func diagnostiquer(objet: Dictionary) -> Dictionary:
	return {
		"restitution": objet.proprietes.get(PROPRIETE_RESTITUTION, 0.0),
		"hauteur": objet.position.z,
		"nombre_rebonds": objet.proprietes.get("nombre_rebonds", 0),
		"arrete": objet.proprietes.get("arrete", false),
		"en_chute": objet.proprietes.get("en_chute", false),
	}

static func texte_objet(id: String, diag: Dictionary) -> String:
	return "%s\nrestitution = %.2f\nhauteur = %.1f\nrebonds = %d%s" % [
		id, diag.restitution, diag.hauteur, diag.nombre_rebonds, "\narrete" if diag.arrete else ""
	]

static func ligne_bascule(t: float, relache: bool) -> String:
	return "t=%.1fs %s (les trois objets)" % [t, "RELACHE" if relache else "REINITIALISE"]

static func ligne_impact(t: float, objet: Dictionary) -> String:
	var diag := diagnostiquer(objet)
	if diag.arrete:
		return "t=%.1fs %s : impact, s'arrete (hauteur sous seuil, %d rebond(s))" % [t, objet.id, diag.nombre_rebonds]
	return "t=%.1fs %s : impact, rebond #%d -> hauteur %.1f" % [t, objet.id, diag.nombre_rebonds, objet.proprietes.get("hauteur_pic", 0.0)]

# ---- Rendu (impur, Node) -- aucune decision, seulement la construction
# des noeuds et la camera.

func _creer_rendu_objet(objet: Dictionary) -> void:
	var id: String = objet.id

	var noeud := ColorRect.new()
	noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noeud.size = Vector2(TAILLE, TAILLE)
	add_child(noeud)
	_noeuds[id] = noeud

	var label := Label.new()
	add_child(label)
	_labels[id] = label

func _creer_sol() -> void:
	var largeur: float = _config.get("largeur_sol", 800.0)
	var sol_y: float = _config.get("sol_y", 0.0)
	var sol := ColorRect.new()
	sol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sol.color = Color(0.3, 0.3, 0.3)
	sol.size = Vector2(largeur, 4.0)
	sol.position = Vector2(-largeur / 2.0 + _config.get("centre_sol_x", 200.0), sol_y)
	add_child(sol)

func _poser_camera() -> void:
	var decl_camera: Dictionary = _config.get("camera", {})
	var pos: Array = decl_camera.get("position", [0.0, 0.0, 0.0])
	var camera := Camera2D.new()
	camera.position = Vector2(pos[0], pos[1])
	camera.zoom = Vector2(decl_camera.get("zoom", 1.0), decl_camera.get("zoom", 1.0))
	camera.enabled = true
	add_child(camera)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
