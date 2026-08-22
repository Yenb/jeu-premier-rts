extends Node3D

# BANC "test_ennemi2 Mother box" -- l'herbe verte : une ressource qui se
# reproduit a cadence fixe, meurt de vieillesse, sature quand la densite
# locale est trop haute.
#
# COMPTAGE DES VOISINS PAR CHAMP SCALAIRE (voir champ_spatial.gd et
# CLAUDE.md § LOCALITE SPATIALE). Il n'y a AUCUNE requete de voisinage,
# AUCUNE Area3D, AUCUNE liste de voisins. Le monde tient un champ
# `case -> densite` maintenu a jour par inscription/retrait a la naissance
# et a la mort. Le cube ne fait que LIRE la densite de sa case et de ses
# adjacentes -- 9 cases, O(1) constant, jamais lie a la population.
#
# COMPOSE gestation.gd DU FRAMEWORK pour la gestation. Le Timer de ponte
# se lance a la naissance, cadence a duree_gestation. A chaque tic : lit
# le champ, sature si densite >= seuil, sinon pond.
#
# LA MORT EST NATURELLE : un Timer one_shot pose sur soi meme se declenche
# a duree_vie et appelle _mourir(), qui retire du champ puis queue_free.
# Un cube sature qui repasse sous seuil (parce qu'un voisin a decremente
# le champ en mourant) tentera de pondre au prochain tic de son Timer --
# le Timer tourne en fond, il n'a jamais ete arrete.
#
# ATTACHEE A LA CARTE, PAS INDEXEE PAR ELLE : le raycast vertical rend la
# hauteur du sol sous le point d'atterrissage. Suppose que le sol porte
# une collision -- un GridMap sans forme dans sa MeshLibrary rendra
# "aucun sol" et l'herbe ne se posera nulle part.

const Gestation = preload("res://scripts/gestation.gd")
const CHEMIN_SCENE := "res://jeu/Outil de jeu/cube_herbe.tscn"

@export var duree_gestation: float = 10.0
@export var duree_vie: float = 60.0
@export var seuil_voisins: int = 33
@export var rayon_cases: int = 1
@export var rayon_pose: float = 0.10
@export var y_min: float = -1000.0
@export var y_max: float = 1000.0
@export var age_initial: float = 0.0

const GROUPE := "herbe"

static var _prochaine_graine := 20261120
var _rng := RandomNumberGenerator.new()
var _champ: RefCounted = null
var _visuel: Node = null
var _index_visuel: int = -1
var _timer_ponte: Timer
var _timer_mort: Timer

func _ready() -> void:
	add_to_group(GROUPE)
	_rng.seed = _prochaine_graine
	_prochaine_graine += 1

	# INSCRIPTION DANS LE CHAMP. Un seul appel, O(1), aucune requete de
	# voisinage. Sans le champ (nœud absent de la scene), l'herbe pousse
	# quand meme mais sans jamais saturer -- utile pour un banc de test
	# isole, dangereux en gameplay.
	var noeud_champ := get_tree().get_first_node_in_group("champ_herbe")
	if noeud_champ != null:
		_champ = noeud_champ.champ
		_champ.inscrire(global_position)

	# INSCRIPTION DANS LE VISUEL (MultiMesh partage). Ce cube n'a plus de
	# mesh a lui -- son transform vit dans un buffer GPU. -1 si le visuel
	# absent (comportement degrade : la logique tourne, rien de visible).
	_visuel = get_tree().get_first_node_in_group("visuel_herbe")
	if _visuel != null:
		_index_visuel = _visuel.inscrire(global_position)

	# Timer de MORT NATURELLE : one_shot, tire a duree_vie. Ecourte de
	# age_initial pour un cube ne d'un prechauffage.
	_timer_mort = Timer.new()
	_timer_mort.wait_time = maxf(0.1, duree_vie - age_initial)
	_timer_mort.one_shot = true
	_timer_mort.autostart = true
	_timer_mort.timeout.connect(_mourir)
	add_child(_timer_mort)

	# Timer de PONTE : cadence a duree_gestation, jamais arrete. A chaque
	# tic, on lit le champ ; si sature, on saute ce cycle silencieusement.
	# Pas de start/stop a orchestrer, pas de reveil manuel a coder : la
	# saturation est une lecture, pas un etat a maintenir.
	_timer_ponte = Timer.new()
	_timer_ponte.wait_time = duree_gestation
	_timer_ponte.one_shot = false
	_timer_ponte.autostart = true
	_timer_ponte.timeout.connect(_tenter_ponte)
	add_child(_timer_ponte)

func _tenter_ponte() -> void:
	_pondre()

func _pondre() -> void:
	# LA CONTRAINTE EST SUR L'ENDROIT DE POSE, pas sur la mere. Une mere
	# en bordure de tapis a peu de voisins autour d'elle et pondrait
	# indefiniment vers l'interieur du tapis meme sature -- resultat :
	# le tapis s'etend jusqu'a couvrir toute la carte. La vraie logique
	# ecologique : une graine germe si l'endroit est libre, sinon rien.
	var angle := _rng.randf_range(0.0, TAU)
	var candidate := global_position + Vector3(cos(angle) * rayon_pose, 0.0, sin(angle) * rayon_pose)
	if _champ != null and _champ.voisins_dans(candidate, rayon_cases) >= seuil_voisins:
		return  # l'endroit cible est sature, on renonce
	var y_sol: Variant = _hauteur_sol_sous(candidate)
	if y_sol == null:
		return
	if float(y_sol) < y_min or float(y_sol) > y_max:
		return

	var accueil := get_parent()
	if accueil == null:
		return
	var scene: PackedScene = load(CHEMIN_SCENE)
	if scene == null:
		return
	var nouveau := scene.instantiate() as Node3D
	# POSITION POSEE AVANT add_child (voir semeur.gd, meme piege).
	nouveau.position = Vector3(candidate.x, float(y_sol), candidate.z)
	accueil.add_child(nouveau)

func _hauteur_sol_sous(point: Vector3) -> Variant:
	# Raycast restreint au GridMap (voir semeur.gd, meme piege : la Hitbox
	# du personnage pose le bebe a sa hauteur au lieu du sol -- cubes
	# flottants "dans le ciel").
	var espace := get_world_3d().direct_space_state
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

func _mourir() -> void:
	if _champ != null:
		_champ.retirer(global_position)
	if _visuel != null:
		_visuel.retirer(_index_visuel)
	queue_free()
