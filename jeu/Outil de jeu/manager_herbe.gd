extends Node

# BANC "test_ennemi2 Mother box" -- LE MANAGER D'HERBE. UN SEUL noeud pour
# TOUS les brins d'herbe. Aucun Node3D par brin, aucun Timer par brin. Un
# tableau plat de dicts, un _process central qui les avance tous.
#
# POURQUOI CE PATRON : voir CLAUDE.md § « Canevas de base des populations
# massives ». Un Node3D en Godot 4 pese 1320 octets et coûte un dispatch
# d'engine par frame. A 20 000 brins avec l'ancien pattern (Node3D + 2
# Timer par cube), l'engine faisait 60 000 dispatches par frame, soit
# 3.6 millions par seconde -- avant meme que la logique tourne. Le
# manager central ramene tout ca a UN dispatch par frame.
#
# COMPOSITION : le manager UTILISE (n'en a pas la responsabilite) trois
# choses qui vivent ailleurs :
#  - ChampHerbe (champ_herbe.gd) -- le compteur de densite par case.
#  - VisuelHerbe (visuel_herbe.gd) -- le MultiMesh du rendu.
#  - Un semis initial N graines aleatoires dans un disque autour de la
#    position du manager -- absorbe du semeur.gd, plus besoin de noeud
#    separe.
#
# UN BRIN = Dictionary { pos: Vector3, age: float, ecoule: float,
#                        index_visuel: int, densite_case: Vector2i }
# `densite_case` est la case OU le brin est INSCRIT DANS LE CHAMP -- garde
# ici pour eviter de la recalculer a chaque naissance/mort.

const ChampSpatialScript = preload("res://jeu/Outil de jeu/champ_spatial.gd")

@export var duree_gestation: float = 10.0
@export var duree_vie: float = 60.0
# DEUX SEUILS DISTINCTS (patron vegetation.gd) :
#  - seuil_mere : au-dessus, la mere ne pond meme pas (densite locale
#    trop haute autour d'elle -- elle ecoute la pression environnante).
#  - seuil_cible : au-dessus, le bebe ne peut pas s'installer la
#    (etablissement bloque par trouee insuffisante).
# Le premier gate LA VOLONTE de pondre, le second GATE LE LIEU de pose.
# Sans le premier, une mere en bordure d'un tapis satur pond meme si
# aucune place libre n'existe autour -- meme apres la contrainte cible,
# elle depense un tic de gestation pour rien.
@export var seuil_mere: int = 30
@export var seuil_cible: int = 33
@export var rayon_cases: int = 1
@export var rayon_pose: float = 0.10
@export var y_min: float = 0.0
@export var y_max: float = 30.0

# SEMIS INITIAL au demarrage : N positions aleatoires dans un disque autour
# de la position de CE noeud (parent doit etre Node3D). 0 = pas de semis
# automatique.
@export var nombre_initial: int = 500
@export var rayon_dispersion: float = 100.0
@export var seed_rng: int = 20261126

var _brins: Array = []
var _rng := RandomNumberGenerator.new()
var _champ: RefCounted = null
var _visuel: Node = null

func _ready() -> void:
	_rng.seed = seed_rng
	# S'ENREGISTRE DANS LE GROUPE pour que le prechauffeur puisse
	# alimenter le tableau directement (voir prechauffeur_herbe.gd).
	add_to_group("manager_herbe")
	# Attendre 5 physics_frame comme les autres pour que le GridMap
	# ait enregistre ses shapes (raycast d'altitude).
	for _i in range(5):
		await get_tree().physics_frame
	_champ = _resoudre_champ()
	_visuel = _resoudre_visuel()
	_semis_initial()

func _resoudre_champ() -> RefCounted:
	var noeud := get_tree().get_first_node_in_group("champ_herbe")
	if noeud == null:
		push_warning("manager_herbe.gd : ChampHerbe absent, saturation locale desactivee")
		return null
	return noeud.champ

func _resoudre_visuel() -> Node:
	var noeud := get_tree().get_first_node_in_group("visuel_herbe")
	if noeud == null:
		push_warning("manager_herbe.gd : VisuelHerbe absent, brins invisibles")
	return noeud

func _semis_initial() -> void:
	if nombre_initial <= 0 or rayon_dispersion <= 0.0:
		return
	var origine := Vector3.ZERO
	var parent := get_parent()
	if parent is Node3D:
		origine = (parent as Node3D).global_position
	for _i in range(nombre_initial):
		var angle := _rng.randf_range(0.0, TAU)
		var rayon := sqrt(_rng.randf()) * rayon_dispersion
		var candidate := origine + Vector3(cos(angle) * rayon, 0.0, sin(angle) * rayon)
		_tenter_ajouter(candidate)

# TICK GLOBAL : appele une fois par frame, avance TOUS les brins. Ordre :
# vieillissement, mort des trop vieux, cycle de ponte. Simple boucle plate.
func _process(delta: float) -> void:
	if _brins.is_empty():
		return
	# Ordre inverse pour pouvoir remove_at sans decaler les index restants.
	for i in range(_brins.size() - 1, -1, -1):
		var brin: Dictionary = _brins[i]
		brin["age"] = float(brin.age) + delta
		if float(brin.age) >= duree_vie:
			_retirer(i)
			continue
		brin["ecoule"] = float(brin.ecoule) + delta
		if float(brin.ecoule) >= duree_gestation:
			brin["ecoule"] = 0.0
			# DOUBLE GATE : la mere elle-meme doit etre sous le seuil
			# pour meme TENTER de pondre. Sans ce gate, une mere en
			# bordure d'un tapis dense pond a chaque cycle vers
			# l'interieur -- meme si la cible est saturee et refuse,
			# elle depense son cycle pour rien et retentera.
			if _champ != null and _champ.voisins_dans(brin.pos, rayon_cases) >= seuil_mere:
				continue
			_pondre_depuis(brin)

func _pondre_depuis(mere: Dictionary) -> void:
	var angle := _rng.randf_range(0.0, TAU)
	var candidate := (mere.pos as Vector3) + Vector3(cos(angle) * rayon_pose, 0.0, sin(angle) * rayon_pose)
	_tenter_ajouter(candidate)

# TENTE UN AJOUT a la position candidate. Trois gates :
#  1. le sol doit exister (raycast vertical GridMap uniquement)
#  2. la hauteur du sol doit tomber dans la bande y_min/y_max
#  3. la densite locale a la CIBLE doit etre sous seuil
func _tenter_ajouter(candidate: Vector3) -> void:
	var y_sol: Variant = _hauteur_sol_sous(candidate)
	if y_sol == null:
		return
	if float(y_sol) < y_min or float(y_sol) > y_max:
		return
	var pos := Vector3(candidate.x, float(y_sol), candidate.z)
	if _champ != null and _champ.voisins_dans(pos, rayon_cases) >= seuil_cible:
		return
	_ajouter(pos)

func _ajouter(pos: Vector3) -> void:
	var index_v := -1
	if _visuel != null:
		index_v = _visuel.inscrire(pos)
	if _champ != null:
		_champ.inscrire(pos)
	_brins.append({
		"pos": pos,
		"age": 0.0,
		"ecoule": 0.0,
		"index_visuel": index_v,
	})

func _retirer(index: int) -> void:
	var brin: Dictionary = _brins[index]
	if _champ != null:
		_champ.retirer(brin.pos)
	if _visuel != null and int(brin.index_visuel) >= 0:
		_visuel.retirer(int(brin.index_visuel))
	_brins.remove_at(index)

func _hauteur_sol_sous(point: Vector3) -> Variant:
	var espace := get_tree().root.get_world_3d().direct_space_state
	if espace == null:
		return null
	var depart := point + Vector3(0.0, 1000.0, 0.0)
	var arrivee := point + Vector3(0.0, -1000.0, 0.0)
	var requete := PhysicsRayQueryParameters3D.create(depart, arrivee)
	var frappe := espace.intersect_ray(requete)
	if frappe.is_empty():
		return null
	if not (frappe.collider is GridMap):
		return null
	return (frappe.position as Vector3).y

# API PUBLIQUE : compte des brins vivants (pour tests et affichage).
func compte() -> int:
	return _brins.size()

# API PUBLIQUE : injecte un brin AVEC un age deja avance. Utilise par
# `prechauffeur_herbe.gd` qui simule N secondes en pur data puis pousse
# les survivants ici. Le brin vivra `duree_vie - age_initial` de plus,
# donc les brins prechauffes meurent naturellement echelonnes au lieu
# de tous mourir en bloc a t+duree_vie.
func ajouter_avec_age(pos: Vector3, age_initial: float) -> void:
	var age := clampf(age_initial, 0.0, duree_vie - 0.1)
	var index_v := -1
	if _visuel != null:
		index_v = _visuel.inscrire(pos)
	if _champ != null:
		_champ.inscrire(pos)
	_brins.append({
		"pos": pos,
		"age": age,
		"ecoule": 0.0,
		"index_visuel": index_v,
	})
