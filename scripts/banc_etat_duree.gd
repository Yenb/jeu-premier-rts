extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_etat_duree.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1). PREMIERE demonstration
# reelle du chantier "un etat a une intensite qui decroit" (evolution en
# place du chantier "un etat peut cesser") : scripts/etat_duree.gd
# (poser/avancer/etats_ponderes) jouant en jeu pour la premiere fois avec
# une intensite continue. Noms de domaine reels (inflammabilite/mouille/
# huile, deja utilises par banc_etat_effectif/banc_inflammabilite) --
# exception documentee (CLAUDE.md : "un banc jetable peut nommer une
# categorie pour poser une scene d'observation").
#
# JETABLE PAR DEFINITION : aucune regle de jeu ne doit vivre ici, seulement
# du cablage et de la lecture. Tout calcul d'affichage est en fonctions
# STATIQUES testables (_intensite_texte/_ratio_intensite/_teinte_pour_valeur/
# _texte_label/_ligne_pose/_ligne_rapport/_ligne_retrait) -- _process ne
# fait qu'appeler EtatDuree.avancer/etats_ponderes (deja le mecanisme reel)
# et EtatEffectif.valeur (deja le mecanisme reel, jamais modifie), jamais
# recalculer une loi ecrite ailleurs.
#
# CE QU'ON DOIT VOIR : deux objets, meme propriete de base
# (inflammabilite=0.9). `objet_expire` porte l'etat REEL "mouille"
# (data/etats.json, duree 6.0s -- temps pour aller de 1.0 a 0.0) : une
# BARRE qui se vide EN PERMANENCE (largeur = intensite courante) juste a
# cote de sa valeur effective, qui REMONTE progressivement au meme rythme
# (0.0 -> 0.9 lineairement sur 6s, jamais un saut) -- le carre suit du
# gris vers l'orange en continu. A intensite epuisee (t=6s), EtatDuree.
# avancer retire "mouille" de lui-meme, et la BARRE COMME LE LABEL
# "etat"/"intensite" DISPARAISSENT de l'ecran (indicateur retire, pas
# juste une barre vide) -- seule la valeur effective (revenue a 0.9,
# EtatEffectif.valeur jamais modifie) reste affichee. `objet_permanent`
# porte l'etat REEL "huile" (aucune "duree" declaree) : sa barre reste
# PLEINE et son carre reste orange sature (0.9 -> 1.8, modulateur) pour
# toujours -- contraste avec objet_expire visible sans lire la console.
# La console imprime, une phrase par ligne : une ligne de POSE au
# demarrage (objet, etat, intensite initiale ou "permanent"), un RAPPORT
# PERIODIQUE pour l'objet qui decroit (objet, etat, intensite courante,
# valeur effective), et la ligne de RETRAIT au moment de l'expiration
# (objet, etat, valeur AVANT -> valeur APRES).
#
# LIMITE STRICTE (rappel explicite du chantier) : ce fichier cable
# UNIQUEMENT ce banc -- aucun mecanisme neuf, aucune extension du coeur.
# etat_duree.gd/etat_effectif.gd sont deja ecrits et verts ; ce fichier ne
# fait que les appeler et lire leurs resultats publics. etat_effectif.gd
# n'est jamais modifie : c'est etats_ponderes() (etat_duree.gd) qui
# construit, a chaque lecture, un catalogue equivalent deja ajuste par
# l'intensite courante -- voir etat_duree.gd pour la doctrine complete.

const EtatDuree = preload("res://scripts/etat_duree.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")

const TAILLE := 70.0
const HAUTEUR_BARRE := 10.0
const INTERVALLE_RAPPORT := 1.5

var _monde: Array = []
var _objets: Array = []
var _etat_pose: Dictionary = {}
var _etats: Dictionary = {}
var _propriete_observee: String = ""
var _noeuds: Dictionary = {}
var _labels: Dictionary = {}
var _barres_fond: Dictionary = {}
var _barres_remplies: Dictionary = {}
var _prochain_rapport: Dictionary = {}
var _temps: float = 0.0

func _ready() -> void:
	var donnees := _charger_json("res://data/banc_etat_duree.json")
	_etats = _charger_json("res://data/etats.json")
	_propriete_observee = donnees.get("propriete_observee", "")

	for decl in donnees.get("objets", []):
		var pos: Array = decl.position
		var objet := {
			"id": decl.id,
			"position": Vector3(pos[0], pos[1], pos[2]),
			"proprietes": {
				_propriete_observee: decl.get("valeur_base", 0.0),
				"etats_actifs": [],
			},
		}
		EtatDuree.poser(objet, decl.nom_etat, _etats)
		_monde.append(objet)
		_objets.append(objet)
		_etat_pose[decl.id] = decl.nom_etat
		_creer_rendu_objet(objet)
		if objet.proprietes.has("etats_intensite"):
			_prochain_rapport[decl.id] = INTERVALLE_RAPPORT

	_poser_camera()

	for objet in _objets:
		var id: String = objet.id
		var nom_etat: String = _etat_pose[id]
		var intensite: float = objet.proprietes.get("etats_intensite", {}).get(nom_etat, -1.0)
		print(_ligne_pose(0.0, id, nom_etat, intensite))

	_rafraichir_tout()

func _process(delta: float) -> void:
	_temps += delta

	var avant: Dictionary = {}
	for objet in _objets:
		avant[objet.id] = EtatEffectif.valeur(objet, _propriete_observee, EtatDuree.etats_ponderes(objet, _etats))

	var expirees: Array = EtatDuree.avancer(_monde, delta, _etats)
	for expiration in expirees:
		var id: String = expiration.id
		var objet: Dictionary = _par_id(id)
		var apres: float = EtatEffectif.valeur(objet, _propriete_observee, EtatDuree.etats_ponderes(objet, _etats))
		print(_ligne_retrait(_temps, id, expiration.nom_etat, avant.get(id, 0.0), apres))
		_prochain_rapport.erase(id)

	for objet in _objets:
		var id: String = objet.id
		if _prochain_rapport.has(id) and _temps >= _prochain_rapport[id]:
			var nom_etat: String = _etat_pose[id]
			var intensite: float = objet.proprietes.get("etats_intensite", {}).get(nom_etat, -1.0)
			var effective: float = EtatEffectif.valeur(objet, _propriete_observee, EtatDuree.etats_ponderes(objet, _etats))
			print(_ligne_rapport(_temps, id, nom_etat, intensite, effective))
			_prochain_rapport[id] += INTERVALLE_RAPPORT

	_rafraichir_tout()

func _par_id(id: String) -> Dictionary:
	for objet in _objets:
		if objet.id == id:
			return objet
	return {}

func _rafraichir_tout() -> void:
	for objet in _objets:
		var id: String = objet.id
		var nom_etat: String = _etat_pose[id]
		var pondere := EtatDuree.etats_ponderes(objet, _etats)
		var effective := EtatEffectif.valeur(objet, _propriete_observee, pondere)
		_noeuds[id].color = _teinte_pour_valeur(effective)

		var actif: bool = objet.proprietes.get("etats_actifs", []).has(nom_etat)
		_barres_fond[id].visible = actif
		_barres_remplies[id].visible = actif
		if actif:
			var ratio := _ratio_intensite(objet.proprietes, nom_etat)
			_barres_remplies[id].size.x = _barres_fond[id].size.x * ratio

		_labels[id].text = _texte_label(id, nom_etat, objet.proprietes, effective)

# ---- Fonctions PURES, testables -- lisent un etat deja calcule par
# etat_duree.gd/etat_effectif.gd, ne reimplementent jamais leur loi.

# Rend "X.XX" si l'etat est encore actif ET suivi en intensite,
# "permanent" s'il est actif SANS intensite suivie (jamais dans
# etats_intensite -- voir etat_duree.gd, absence legitime), "expire" s'il
# n'est plus dans etats_actifs du tout.
static func _intensite_texte(proprietes: Dictionary, nom_etat: String) -> String:
	var intensites: Dictionary = proprietes.get("etats_intensite", {})
	if intensites.has(nom_etat):
		return "%.2f" % intensites[nom_etat]
	var actifs: Array = proprietes.get("etats_actifs", [])
	if actifs.has(nom_etat):
		return "permanent"
	return "expire"

# Rend le ratio de remplissage de la barre : l'intensite suivie si l'etat
# en a une, 1.0 si l'etat est actif SANS intensite suivie (permanent,
# barre pleine par definition), 0.0 sinon (etat absent, barre masquee de
# toute facon par _rafraichir_tout).
static func _ratio_intensite(proprietes: Dictionary, nom_etat: String) -> float:
	var intensites: Dictionary = proprietes.get("etats_intensite", {})
	if intensites.has(nom_etat):
		return clamp(intensites[nom_etat], 0.0, 1.0)
	var actifs: Array = proprietes.get("etats_actifs", [])
	return 1.0 if actifs.has(nom_etat) else 0.0

static func _teinte_pour_valeur(effective: float) -> Color:
	if effective <= 0.0:
		return Color(0.4, 0.4, 0.4)
	var t: float = clamp(effective, 0.0, 1.0)
	return Color(t, t * 0.5, 0.0)

static func _texte_label(id: String, nom_etat: String, proprietes: Dictionary, effective: float) -> String:
	return "%s\netat=%s\nintensite=%s\nvaleur_effective=%.2f" % [
		id, nom_etat, _intensite_texte(proprietes, nom_etat), effective
	]

static func _ligne_pose(t: float, id: String, nom_etat: String, intensite: float) -> String:
	var texte: String = ("%.2f" % intensite) if intensite >= 0.0 else "permanent, aucune duree declaree"
	return "t=%.1fs %s : etat '%s' pose, intensite=%s" % [t, id, nom_etat, texte]

static func _ligne_rapport(t: float, id: String, nom_etat: String, intensite: float, effective: float) -> String:
	return "t=%.1fs %s : etat '%s' intensite=%.2f valeur_effective=%.2f" % [t, id, nom_etat, intensite, effective]

static func _ligne_retrait(t: float, id: String, nom_etat: String, avant: float, apres: float) -> String:
	return "t=%.1fs %s : etat '%s' expire -- valeur %.2f -> %.2f" % [t, id, nom_etat, avant, apres]

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
	rempli.color = Color(0.3, 0.6, 0.9)
	rempli.size = Vector2(TAILLE, HAUTEUR_BARRE)
	rempli.position = fond.position
	add_child(rempli)
	_barres_remplies[id] = rempli

	var label := Label.new()
	label.position = centre - Vector2(TAILLE / 2.0, TAILLE / 2.0 + 90.0)
	add_child(label)
	_labels[id] = label

func _poser_camera() -> void:
	var centre_x := 0.0
	for objet in _objets:
		centre_x += objet.position.x
	if not _objets.is_empty():
		centre_x /= _objets.size()
	var camera := Camera2D.new()
	camera.position = Vector2(centre_x, 320.0)
	camera.zoom = Vector2(0.9, 0.9)
	camera.enabled = true
	add_child(camera)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
