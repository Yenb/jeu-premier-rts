extends Node3D

# BANC "test_ennemi" -- le cube violet observe SON PROPRE stock de metal.
# Des qu'il atteint `seuil_reproduction`, une gestation de
# `duree_gestation` secondes s'entame ; a la naissance, un nouveau cube
# violet est pose autour, et le stock est diminue du COUT exact.
#
# COMPOSE gestation.gd DU FRAMEWORK -- meme patron que
# garde_transporteurs.gd. La difference est la CONDITION D'ENTREE : ici
# c'est un seuil de stock, la-bas un manque d'individus. Meme mecanisme,
# meme framework, deux gates. Rien de neuf ecrit sur "compter le temps"
# ou "declencher au seuil".
#
# LE COUT SE PAIE A LA NAISSANCE, pas a la conception -- si le cube meurt
# pendant sa gestation, le stock n'a pas ete gaspille. C'est LA logique
# derriere le mecanisme : ce que Consommer.transferer garantit sur la
# conservation (aucune matiere creee, aucune perdue en trop), on l'a
# aussi ici -- 30 metal payes, 1 cube ne, jamais deux ni zero.
#
# LE NOUVEAU CUBE EST POSE COMME FRERE du cube parent, pas enfant : un
# enfant meurt avec son parent (queue_free). Un enfant de la genese ne
# doit pas s'evanouir quand son producteur meurt.

const Gestation = preload("res://scripts/gestation.gd")
const CubeEnnemiScene := preload("res://jeu/Ennemie/cube_ennemi.tscn")

@export var seuil_reproduction: float = 30.0
@export var duree_gestation: float = 20.0
@export var cout_reproduction: float = 30.0

@export var rayon_pose_min: float = 3.0
@export var rayon_pose_max: float = 5.0

const REF_REPRODUCTION := "cube_violet"

static var _prochaine_graine := 20260930
var _rng := RandomNumberGenerator.new()
var _catalogue: Dictionary
var _mere: Dictionary

func _ready() -> void:
	_rng.seed = _prochaine_graine
	_prochaine_graine += 1
	_catalogue = {REF_REPRODUCTION: {"duree_gestation": duree_gestation}}
	# LE CUBE VIOLET AGIT COMME "MERE" au sens de reproduction. Aucune
	# gestation n'est posee ici tant que le stock ne franchit pas le seuil.
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
	var stock: float = parent_cube.entite.proprietes.reserves.stock_metal.reserve

	# 1. STOCK INSUFFISANT : rien a faire. Une gestation deja entamee
	# reste en place (elle a demarre quand le stock etait la ; le stock
	# a pu redescendre entre-temps si personne ne pond -- rare mais on
	# ne casse pas ce qui a demarre).
	if stock < seuil_reproduction and not _mere.proprietes.has("gestation"):
		return

	# 2. ENTAMER LA GESTATION AU FRANCHISSEMENT, pas avant.
	if not _mere.proprietes.has("gestation"):
		Gestation.poser(_mere, null, _catalogue)

	# 3. AVANCER D'UNE SECONDE, meme rythme que le Timer.
	Gestation.avancer(_mere, _catalogue, 1.0)

	# 4. NAISSANCE PRETE : pondre, retirer la gestation, payer le cout.
	var gestation: Dictionary = _mere.proprietes.get("gestation", {})
	if gestation.get("naissance_prete", false):
		_mere.proprietes.erase("gestation")
		_pondre_un_cube_violet(parent_cube)
		# LE COUT SE PAIE ICI, jamais avant : voir en-tete.
		var canal: Dictionary = parent_cube.entite.proprietes.reserves.stock_metal
		canal["reserve"] = maxf(0.0, canal.reserve - cout_reproduction)
		if parent_cube.has_method("_rafraichir_barres"):
			parent_cube._rafraichir_barres()

func _pondre_un_cube_violet(parent_cube: Node3D) -> void:
	var accueil := parent_cube.get_parent()
	if accueil == null:
		push_error("gestation_stock.gd : aucun contenant pour poser le nouveau cube violet")
		return
	var angle := _rng.randf_range(0.0, TAU)
	var rayon := _rng.randf_range(rayon_pose_min, rayon_pose_max)
	var pose: Vector3 = parent_cube.global_position + Vector3(cos(angle) * rayon, 0.0, sin(angle) * rayon)
	var nouveau := CubeEnnemiScene.instantiate() as Node3D
	accueil.add_child(nouveau)
	nouveau.global_position = pose
