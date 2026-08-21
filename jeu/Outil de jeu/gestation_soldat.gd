extends Node3D

# BANC "test_ennemi" -- le cube violet en mode combat convertit son stock
# en soldats. Meme patron que gestation_stock.gd (compose gestation.gd du
# framework), avec deux differences :
# - Actif SEULEMENT quand parent_cube.mode_combat -- sinon dormant total.
# - Cout et duree differents : 50 metal, 30 s de gestation.
#
# TROIS COMPOSANTS SOEURS sous chaque cube violet, tous silencieux tant
# que leur gate n'est pas vrai :
#   GardeTransporteurs  -- toujours actif (maintient les 2 transporteurs)
#   GestationStock      -- gele en mode combat
#   GestationSoldat     -- actif seulement en mode combat
#
# Rien n'est en conflit : les deux gestations partagent la meme reserve
# stock_metal mais le meme cube ne fait jamais les deux en meme temps
# (l'un est gele quand l'autre travaille). Le stock qui reste sous 50
# quand le mode combat expire n'est PAS perdu -- gestation_stock reprend
# la main et l'utilisera pour un cube violet des qu'il atteint 30.

const Gestation = preload("res://scripts/gestation.gd")
const SoldatScene := preload("res://jeu/Outil de jeu/soldat.tscn")

@export var seuil_soldat: float = 50.0
@export var duree_gestation: float = 30.0
@export var cout_soldat: float = 50.0

@export var rayon_pose_min: float = 1.5
@export var rayon_pose_max: float = 2.5

const REF_REPRODUCTION := "soldat"

static var _prochaine_graine := 20261001
var _rng := RandomNumberGenerator.new()
var _catalogue: Dictionary
var _mere: Dictionary

func _ready() -> void:
	_rng.seed = _prochaine_graine
	_prochaine_graine += 1
	_catalogue = {REF_REPRODUCTION: {"duree_gestation": duree_gestation}}
	_mere = {
		"id": str(get_instance_id()),
		"proprietes": {"reproduction_ref": REF_REPRODUCTION},
	}

	var minuteur := Timer.new()
	minuteur.wait_time = 1.0
	minuteur.autostart = true
	minuteur.timeout.connect(_tick)
	add_child(minuteur)

func _tick() -> void:
	var parent_cube := get_parent()
	if parent_cube == null or not is_instance_valid(parent_cube):
		return
	if not "entite" in parent_cube:
		return
	# GATE PRINCIPAL : ce composant ne travaille QUE en mode combat, qui
	# reste vrai jusqu'a la naissance du soldat (voir vie_ennemi.gd :
	# sortir_du_mode_combat est appelee ci-dessous, apres la ponte).
	if not ("mode_combat" in parent_cube and parent_cube.mode_combat):
		return

	var stock: float = parent_cube.entite.proprietes.reserves.stock_metal.reserve

	if stock < seuil_soldat and not _mere.proprietes.has("gestation"):
		return

	if not _mere.proprietes.has("gestation"):
		Gestation.poser(_mere, null, _catalogue)

	Gestation.avancer(_mere, _catalogue, 1.0)

	var gestation: Dictionary = _mere.proprietes.get("gestation", {})
	if gestation.get("naissance_prete", false):
		_mere.proprietes.erase("gestation")
		_pondre_un_soldat(parent_cube)
		var canal: Dictionary = parent_cube.entite.proprietes.reserves.stock_metal
		canal["reserve"] = maxf(0.0, canal.reserve - cout_soldat)
		if parent_cube.has_method("_rafraichir_barres"):
			parent_cube._rafraichir_barres()
		# LE SOLDAT EST NE : le cube sort du mode combat, reprend la
		# reproduction normale. Une nouvelle frappe le remettra en combat.
		if parent_cube.has_method("sortir_du_mode_combat"):
			parent_cube.sortir_du_mode_combat()

func _pondre_un_soldat(parent_cube: Node3D) -> void:
	var accueil := parent_cube.get_parent()
	if accueil == null:
		push_error("gestation_soldat.gd : aucun contenant pour poser le soldat")
		return
	var angle := _rng.randf_range(0.0, TAU)
	var rayon := _rng.randf_range(rayon_pose_min, rayon_pose_max)
	var pose: Vector3 = parent_cube.global_position + Vector3(cos(angle) * rayon, 0.0, sin(angle) * rayon)
	var soldat := SoldatScene.instantiate() as Node3D
	accueil.add_child(soldat)
	soldat.global_position = pose
	# LIEN AU CUBE PARENT : le soldat en a besoin pour son rayon de
	# defense (voir soldat.gd). Passe explicitement, jamais devine.
	if "cube_parent" in soldat:
		soldat.cube_parent = parent_cube
