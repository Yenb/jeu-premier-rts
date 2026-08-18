extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_elasticite.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1, coexiste avec les autres
# bancs). Chantier « elasticite -- deformation reversible » : "elasticite"
# (data/materiaux.json, bois 0.3/pierre 0.05/fer 0.2, DORMANTE depuis la
# creation du catalogue, voir audit_colonne_mecanique_prealable.md
# propriete #6 -- aucun mecanisme candidat avant ce chantier) rejoint enfin
# data/proprietes_immuables_composition.json (voir CARTE.md §4) -- avant ce
# chantier, aucun objet fabrique par composition ne portait jamais
# proprietes.elasticite. Reutilise "rigidite" (DEJA fusionnee par le
# chantier concurrent « rigidite -- resistance a la flexion »,
# scripts/banc_rigidite.gd) pour la deformation SOUS force -- meme formule
# deformation = force / rigidite_effective que fleche() de
# banc_rigidite.gd, jamais reimplementee differemment ; ce que la force
# LAISSE une fois retiree est ce que ce banc-ci ajoute, jamais couvert
# avant.
#
# AUCUN MECANISME DU CŒUR TOUCHE : etat_effectif.gd/seuil_etat.gd/objet.gd/
# banc_commun.gd restent inchanges. Une seule ligne de donnee au-dela de ce
# fichier et de data/banc_elasticite.json (jetable, propre au banc) :
# "elasticite" rejoint data/proprietes_immuables_composition.json (voir
# §4) -- "rigidite" y est deja, ajoutee par le chantier concurrent
# « rigidite ».
#
# "elasticite" n'est MODULEE PAR AUCUN etat de data/etats.json (meme statut
# que "restitution") -- lue en base seule, jamais via etat_effectif.gd.
# "rigidite", elle, EST lue via EtatEffectif.valeur (meme convention que
# banc_rigidite.gd sur LA MEME propriete, meme si aucun etat ne la module
# encore aujourd'hui -- coherence entre les deux bancs qui la consomment).
#
# MECANIQUE (deux temps, jamais confondus) :
# - SOUS FORCE : deformation_actuelle = force / rigidite_effective
#   (EXACTEMENT fleche() de banc_rigidite.gd) -- recalculee chaque tick,
#   jamais un accumulateur temporel. deformation_maximale_atteinte grimpe
#   en suivant (jamais redescendue tant que la force reste active), meme
#   principe que fleche_maximale_atteinte de banc_rigidite.gd -- c'est
#   elle, PAS la deformation instantanee, qui sert de "deformation
#   initiale" au calcul de retour ci-dessous.
# - FORCE RETIREE : la partie ELASTIQUE de la deformation revient
#   (deformation_maximale_atteinte * elasticite disparait), la partie
#   PERMANENTE reste -- ENONCE EXACT du chantier :
#     deformation_permanente = deformation_maximale_atteinte * (1.0 - elasticite)
#   deformation_actuelle devient alors EGALE a deformation_permanente,
#   stable tant que la force ne revient pas, recalculee chaque tick depuis
#   la derniere deformation_maximale_atteinte (jamais un evenement one-shot
#   fragile). elasticite 1.0 : permanente = 0.0 (retour total, jamais un
#   cas particulier code -- simple consequence de la formule). elasticite
#   0.0 : permanente = deformation_maximale_atteinte (aucun retour,
#   jamais).
#
# CE QU'ON DOIT VOIR : trois objets fabriques (bois/pierre/fer, un materiau
# reel chacun, Objet.fabriquer/composition/materiaux.json -- jamais
# construits a la main), cote a cote, hauteur pleine au repos. Un clic
# gauche BASCULE une force de compression identique sur LES TROIS A LA FOIS
# (meme geste que banc_friction.gd:basculer_mouille/banc_rigidite.gd:
# basculer_charge) : sous force, les trois s'ecrasent -- le bois (rigidite
# 11.0) le plus, le fer (200.0) a peine, la pierre (50.0) au milieu (MEME
# ordre que banc_rigidite.gd, meme grandeur physique). Un second clic
# retire la force : le bois (elasticite 0.3) remonte le plus (30% de sa
# deformation maximale recuperee), la pierre (0.05) reste quasi ecrasee
# (95% de deformation permanente), le fer (0.2) remonte partiellement (20%
# recupere, 80% permanent). Un troisieme clic reapplique la force -- la
# deformation maximale continue d'accumuler si la nouvelle compression
# depasse l'ancienne, rien ne redemarre a zero. Label par objet :
# elasticite, deformation actuelle, deformation permanente, force (posee
# ou non). Trace console : une ligne a chaque bascule de force, un
# recapitulatif periodique (meme patron que banc_friction.gd:
# doit_imprimer_recap/ligne_recap).
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge les donnees et fabrique les trois objets
#   (Objet.fabriquer, composition fusionnee -- meme patron que
#   banc_friction.gd/banc_rigidite.gd). _unhandled_input bascule la force
#   sur les trois au clic gauche. _process appelle UNIQUEMENT avancer()
#   (fonction statique, ci-dessous) puis lit ses resultats pour
#   l'affichage/la console -- jamais un calcul refait ici.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_elasticite.gd) : deformation_sous_force/
#   deformation_permanente/avancer/basculer_force/fabriquer_objets/
#   diagnostiquer/doit_imprimer_recap, plus le texte d'affichage et de log.

const Objet = preload("res://scripts/objet.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")

const PROPRIETE_ELASTICITE := "elasticite"
const PROPRIETE_RIGIDITE := "rigidite"
const LARGEUR := 60.0
const HAUTEUR_BASE := 140.0
const HAUTEUR_MIN := 10.0

var _config: Dictionary = {}
var _etats: Dictionary = {}
var _materiaux: Dictionary = {}
var _objets: Array = []
var _couleurs: Dictionary = {}
var _force_valeur := 1000.0
var _force_active := false
var _intervalle_log := 2.0
var _noeuds: Dictionary = {}
var _labels: Dictionary = {}
var _temps := 0.0
var _dernier_log := 0.0

func _ready() -> void:
	_config = _charger_json("res://data/banc_elasticite.json")
	_etats = _charger_json("res://data/etats.json")
	_materiaux = _charger_json("res://data/materiaux.json")
	var proprietes_immuables: Array = _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", [])

	_force_valeur = _config.get("force_valeur", 1000.0)
	_intervalle_log = _config.get("intervalle_log", 2.0)

	_objets = fabriquer_objets(_config.get("objets", []), _materiaux, proprietes_immuables)
	var decl_couleurs: Dictionary = _config.get("couleurs", {})
	for objet in _objets:
		_couleurs[objet.id] = _couleur_depuis_array(decl_couleurs.get(objet.id, [0.6, 0.6, 0.6]))
		_creer_rendu_objet(objet)
		print(ligne_pose_initiale(objet.id, diagnostiquer(objet, _etats)))

	_rafraichir_tout()
	_poser_camera()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_force_active = basculer_force(_force_active)
		print(ligne_force(_temps, _force_active))
		_rafraichir_tout()

func _process(delta: float) -> void:
	_temps += delta
	avancer(_objets, _force_valeur, _force_active, _etats)

	if doit_imprimer_recap(_temps, _dernier_log, _intervalle_log):
		print(ligne_recap(_temps, _objets, _etats))
		_dernier_log = _temps

	_rafraichir_tout()

func _rafraichir_tout() -> void:
	for objet in _objets:
		var id: String = objet.id
		var diag := diagnostiquer(objet, _etats)
		var hauteur: float = max(HAUTEUR_MIN, HAUTEUR_BASE - float(diag.deformation_actuelle))
		var centre := Vector2(objet.position.x, objet.position.y)
		_noeuds[id].size = Vector2(LARGEUR, hauteur)
		_noeuds[id].position = centre - Vector2(LARGEUR / 2.0, hauteur)
		_noeuds[id].color = _couleurs.get(id, Color(0.8, 0.8, 0.8))
		_labels[id].position = centre - Vector2(LARGEUR / 2.0 + 20.0, hauteur + 90.0)
		_labels[id].text = texte_objet(id, diag, _force_active)

# ---- Fonctions PURES, testables headless (voir test_banc_elasticite.gd) ----

# force / rigidite_effective -- EXACTEMENT fleche() de banc_rigidite.gd,
# jamais reimplementee differemment (meme grandeur physique, meme
# formule). rigidite_effective nulle ou negative (donnee incoherente,
# jamais produite par les materiaux reels de ce depot) : garde defensive,
# INF plutot qu'une division par zero silencieuse.
static func deformation_sous_force(force: float, rigidite_effective: float) -> float:
	if rigidite_effective <= 0.0:
		return INF
	return force / rigidite_effective

# ENONCE EXACT du chantier : ce qui reste une fois la force retiree.
# elasticite 1.0 -- tout revient, permanente = 0.0 exactement. elasticite
# 0.0 -- rien ne revient, permanente = deformation_maximale_atteinte
# exactement.
static func deformation_permanente(deformation_maximale_atteinte: float, elasticite: float) -> float:
	return deformation_maximale_atteinte * (1.0 - elasticite)

# UN PAS de simulation complet : pour chaque objet, sous force, recalcule
# deformation_actuelle (deformation_sous_force, rigidite LUE VIA
# EtatEffectif -- voir en-tete) et fait grimper deformation_maximale_
# atteinte (jamais redescendue tant que la force reste active, meme
# principe que fleche_maximale_atteinte de banc_rigidite.gd) ; force
# retiree, fige deformation_actuelle sur deformation_permanente
# (recalculee depuis la derniere deformation_maximale_atteinte, stable
# tant que la force ne revient pas). MUTE les objets recus, comme
# Charge.avancer/Deformation.avancer.
static func avancer(objets: Array, force_valeur: float, force_active: bool, etats: Dictionary) -> void:
	for objet in objets:
		var rigidite_eff: float = EtatEffectif.valeur(objet, PROPRIETE_RIGIDITE, etats)
		if force_active:
			var d := deformation_sous_force(force_valeur, rigidite_eff)
			objet.proprietes["deformation_actuelle"] = d
			var maximale: float = objet.proprietes.get("deformation_maximale_atteinte", 0.0)
			objet.proprietes["deformation_maximale_atteinte"] = max(maximale, d)
		else:
			var maximale: float = objet.proprietes.get("deformation_maximale_atteinte", 0.0)
			var elasticite: float = objet.proprietes.get(PROPRIETE_ELASTICITE, 0.0)
			var permanente := deformation_permanente(maximale, elasticite)
			objet.proprietes["deformation_permanente"] = permanente
			objet.proprietes["deformation_actuelle"] = permanente

static func basculer_force(actif: bool) -> bool:
	return not actif

# Construit les trois objets via Objet.fabriquer (composition fusionnee --
# meme patron que banc_friction.gd/banc_rigidite.gd, catalogue LOCAL a une
# entree par id).
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
		objet.proprietes["deformation_actuelle"] = 0.0
		objet.proprietes["deformation_maximale_atteinte"] = 0.0
		objet.proprietes["deformation_permanente"] = 0.0
		objets.append(objet)
	return objets

# Diagnostic d'affichage, PUR : lit uniquement des valeurs deja calculees,
# ne reimplemente jamais une loi (meme doctrine que banc_friction.gd/
# banc_rigidite.gd:diagnostiquer). Rend { elasticite, rigidite_effective,
# deformation_actuelle, deformation_permanente }.
static func diagnostiquer(objet: Dictionary, etats: Dictionary) -> Dictionary:
	return {
		"elasticite": objet.proprietes.get(PROPRIETE_ELASTICITE, 0.0),
		"rigidite_effective": EtatEffectif.valeur(objet, PROPRIETE_RIGIDITE, etats),
		"deformation_actuelle": objet.proprietes.get("deformation_actuelle", 0.0),
		"deformation_permanente": objet.proprietes.get("deformation_permanente", 0.0),
	}

static func texte_objet(id: String, diag: Dictionary, force_active: bool) -> String:
	return "%s\nelasticite = %.2f\ndeformation actuelle = %.2f\ndeformation permanente = %.2f\nforce = %s" % [
		id, diag.elasticite, diag.deformation_actuelle, diag.deformation_permanente, "posee" if force_active else "retiree"
	]

static func ligne_pose_initiale(id: String, diag: Dictionary) -> String:
	return "t=0.0s %s : elasticite=%.2f rigidite_effective=%.2f (sans force)" % [id, diag.elasticite, diag.rigidite_effective]

static func ligne_force(t: float, actif: bool) -> String:
	return "t=%.1fs force : %s (les trois objets)" % [t, "POSEE" if actif else "RETIREE"]

# "changement significatif" version temps, meme role que
# banc_friction.gd:doit_imprimer_recap.
static func doit_imprimer_recap(temps: float, dernier_log: float, intervalle: float) -> bool:
	if intervalle <= 0.0:
		return true
	return temps - dernier_log >= intervalle

static func ligne_recap(t: float, objets: Array, etats: Dictionary) -> String:
	var morceaux: Array = []
	for objet in objets:
		var diag := diagnostiquer(objet, etats)
		morceaux.append("%s=%.2f" % [objet.id, diag.deformation_actuelle])
	var texte := ""
	for i in range(morceaux.size()):
		if i > 0:
			texte += ", "
		texte += morceaux[i]
	return "t=%.1fs deformation actuelle : %s" % [t, texte]

# ---- Rendu (impur, Node) -- aucune decision, seulement la construction
# des noeuds et la camera.

func _creer_rendu_objet(objet: Dictionary) -> void:
	var id: String = objet.id

	var noeud := ColorRect.new()
	noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noeud.size = Vector2(LARGEUR, HAUTEUR_BASE)
	add_child(noeud)
	_noeuds[id] = noeud

	var label := Label.new()
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
