extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_etat_effectif.tscn, PAS la
# scene principale -- run/main_scene reste banc_p1). Existe pour VOIR
# scripts/etat_effectif.gd jouer en jeu : quatre objets cote a cote,
# chacun portant une propriete "inflammabilite" de base identique (0.9,
# valeur illustrative -- meme ordre de grandeur que le bois de
# data/materiaux.json, AUCUN lien reel avec le chantier feu, ce banc ne
# fabrique rien via Objet.fabriquer, ne porte aucune composition) --
# nommage d'un domaine dans un banc jetable, exception documentee
# (CLAUDE.md : "un banc jetable peut nommer une categorie pour poser une
# scene d'observation").
#
# JETABLE PAR DEFINITION : aucune regle de jeu ne doit vivre ici, seulement
# du cablage. Toute logique de decision est en fonctions STATIQUES
# testables (voir _est_actif/_teinte_pour_valeur/_texte_label/
# _explication/_ligne_log) -- _process ne fait que DECLENCHER et LIRE,
# jamais calculer la loi de resolution (CLAUDE.md, Regle d'etat).
#
# CE QU'ON DOIT VOIR : quatre carres cote a cote (data/
# banc_etat_effectif.json:objets), chacun affichant EN PERMANENCE sa
# valeur effective (teinte du carre + Label texte -- base/etats actifs/
# valeur effective, EtatEffectif.valeur, jamais reimplementee) --
# "sans_etat" (temoin, jamais touche, reste a la base 0.9 tout du long),
# "ecrase" (mouille seul -- ECRASEMENT, chute a 0.0), "module" (huile seul
# -- MODULATION, double a 1.8), "ecrase_et_module" (les DEUX a la fois --
# rend a 0.0, IDENTIQUE a "ecrase" : l'ecran prouve que l'ecraseur gagne
# toujours sur le modulateur, pas seulement l'en-tete de etat_effectif.gd).
# Une MINUTERIE (periode_bascule, data/banc_etat_effectif.json) pose les
# etats de chaque objet (sauf le temoin) puis les retire, en boucle -- la
# valeur de chacun bouge loin de sa base puis y revient, jamais figee au
# demarrage. La console imprime une ligne A CHAQUE changement d'etat d'un
# objet (voir _ligne_log) : quel objet, pose ou retire, les etats avant et
# apres, la valeur avant et apres, et quel etat a gagne la resolution
# (ou pourquoi aucun n'a d'effet) -- l'ecran montre QUE la valeur a change,
# la console montre POURQUOI.

const EtatEffectif = preload("res://scripts/etat_effectif.gd")

const TAILLE := 60.0
const PROPRIETE_OBSERVEE := "inflammabilite"

var _objets: Array = []
var _etats: Dictionary = {}
var _noeuds: Dictionary = {}
var _labels: Dictionary = {}
var _periode: float = 4.0
var _temps: float = 0.0
var _actif_precedent: bool = false

func _ready() -> void:
	var donnees := _charger_json("res://data/banc_etat_effectif.json")
	_etats = _charger_json("res://data/etats.json")
	_periode = donnees.get("periode_bascule", 4.0)
	var base: float = donnees.get("inflammabilite_base", 0.0)

	for decl in donnees.get("objets", []):
		var pos: Array = decl.get("position", [0.0, 0.0, 0.0])
		var objet := {
			"id": decl.get("id", ""),
			"position": Vector3(pos[0], pos[1], pos[2]),
			"proprietes": {
				PROPRIETE_OBSERVEE: base,
				"etats_actifs": [],
			},
			"etats_role": decl.get("etats_role", []),
		}
		_objets.append(objet)

		var noeud := ColorRect.new()
		noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
		noeud.size = Vector2(TAILLE, TAILLE)
		noeud.position = Vector2(objet.position.x, objet.position.y) - noeud.size / 2.0
		add_child(noeud)
		_noeuds[objet.id] = noeud

		var label := Label.new()
		label.position = Vector2(objet.position.x, objet.position.y) - Vector2(TAILLE / 2.0, TAILLE / 2.0 + 70.0)
		add_child(label)
		_labels[objet.id] = label

	var centre_x := 0.0
	for objet in _objets:
		centre_x += objet.position.x
	if not _objets.is_empty():
		centre_x /= _objets.size()
	var camera := Camera2D.new()
	camera.position = Vector2(centre_x, 300.0)
	camera.enabled = true
	add_child(camera)

	_actif_precedent = _est_actif(0.0, _periode)
	_appliquer_roles(_actif_precedent, 0.0)
	_rafraichir_tout()

func _process(delta: float) -> void:
	_temps += delta
	var actif_actuel := _est_actif(_temps, _periode)
	if actif_actuel != _actif_precedent:
		_appliquer_roles(actif_actuel, _temps)
		_actif_precedent = actif_actuel
	_rafraichir_tout()

# PURE, testable -- alterne actif/inactif toutes les periode/2 secondes,
# jamais un seul etat fige. periode <= 0.0 : toujours actif (garde
# degeneree, ne doit jamais arriver avec la donnee reelle).
static func _est_actif(t: float, periode: float) -> bool:
	if periode <= 0.0:
		return true
	return fmod(t, periode) < periode * 0.5

func _appliquer_roles(actif: bool, t: float) -> void:
	for objet in _objets:
		var avant: Array = objet.proprietes.etats_actifs.duplicate()
		var apres: Array = objet.etats_role.duplicate() if actif else []
		if apres == avant:
			continue
		var valeur_avant := EtatEffectif.valeur(objet, PROPRIETE_OBSERVEE, _etats)
		objet.proprietes.etats_actifs = apres
		var resolution: Dictionary = EtatEffectif.resoudre(objet, PROPRIETE_OBSERVEE, _etats)
		print(_ligne_log(objet.id, t, avant, apres, valeur_avant, resolution))

func _rafraichir_tout() -> void:
	for objet in _objets:
		var effective := EtatEffectif.valeur(objet, PROPRIETE_OBSERVEE, _etats)
		_noeuds[objet.id].color = _teinte_pour_valeur(effective)
		_labels[objet.id].text = _texte_label(objet.id, objet.proprietes[PROPRIETE_OBSERVEE], objet.proprietes.etats_actifs, effective)

# PURE, testable -- gris (aucun effet) a orange sature (effet plein ou
# au-dela), jamais une reimplementation de la loi d'etat_effectif.gd,
# seulement une lecture de son resultat.
static func _teinte_pour_valeur(effective: float) -> Color:
	if effective <= 0.0:
		return Color(0.4, 0.4, 0.4)
	var t: float = clamp(effective, 0.0, 1.0)
	return Color(t, t * 0.5, 0.0)

# PURE, testable -- texte du Label d'un objet, separe de tout Node pour
# rester verrouillable headless.
static func _texte_label(id: String, base: float, etats_actifs: Array, effective: float) -> String:
	return "%s\nbase=%.2f etats=%s\neffective=%.2f" % [id, base, str(etats_actifs), effective]

# PURE, testable -- explique en une phrase QUI a gagne la resolution,
# depuis le Dictionary rendu par EtatEffectif.resoudre -- ne relit jamais
# la loi elle-meme, seulement son verdict deja calcule.
static func _explication(resolution: Dictionary) -> String:
	match resolution.mode:
		"aucun":
			return "aucun etat actif sur cette propriete"
		"ecraser":
			var texte: String = "'%s' ecrase" % resolution.gagnants[0]
			if not resolution.ignores.is_empty():
				texte += " (ignore : %s)" % ", ".join(resolution.ignores)
			return texte
		"moduler":
			return "module : %s" % ", ".join(resolution.gagnants)
		_:
			return "?"

# PURE, testable -- une ligne humaine par changement d'etat : quel objet,
# pose ou retire, etats avant/apres, valeur avant/apres, et pourquoi
# (_explication). L'ecran montre QUE la valeur a change, cette ligne
# montre POURQUOI.
static func _ligne_log(id: String, t: float, etats_avant: Array, etats_apres: Array, valeur_avant: float, resolution: Dictionary) -> String:
	var action: String = "pose" if etats_apres.size() > etats_avant.size() else "retire"
	return "t=%.1fs %s : %s %s -> %s | valeur %.2f -> %.2f | %s" % [
		t, id, action, str(etats_avant), str(etats_apres),
		valeur_avant, resolution.valeur, _explication(resolution)
	]

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
