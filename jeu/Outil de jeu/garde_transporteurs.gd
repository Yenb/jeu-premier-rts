extends Node3D

# BANC "test_ennemi" -- le cube violet maintient TOUJOURS `combien`
# transporteurs vivants (2 par defaut). Quand l'un meurt, une gestation
# demarre : `duree_gestation` secondes plus tard, un nouveau transporteur
# est pondu autour du cube. Une seule gestation a la fois -- si deux
# transporteurs meurent, le second est refait apres le premier, en
# sequence. C'est ce que l'utilisateur a demande ("trente secondes pour
# produire UN transporteur des qu'il a perdu", singulier).
#
# COMPOSE gestation.gd DU FRAMEWORK -- pas de compte a rebours refait a la
# main. Le cube violet devient une "mere" au sens de reproduction : une
# proprietes.gestation qui monte, un `naissance_prete` au seuil, pond puis
# retire. Meme patron que population_ennemie.gd:_avancer_dune_seconde,
# meme fichier framework, applique a un contexte different -- c'est ce
# que le motif "moteur de population organique generique" (voir SUIVI.md)
# permet, sans jamais rouvrir un mecanisme.
#
# LES TRANSPORTEURS SONT DES FRERES du cube parent (voir la version
# precedente pour la raison) -- ils survivent au cube violet.
#
# LA POSE EST DIFFEREE D'UNE FRAME : add_child() est refuse pendant que
# le grand-parent monte encore (Godot 4.7). Le tick de suivi est un
# Timer d'une seconde, meme rythme que population_ennemie.gd.

const Gestation = preload("res://scripts/gestation.gd")
const TransporteurScene := preload("res://jeu/Outil de jeu/transporteur.tscn")

@export var combien: int = 2
@export var duree_gestation: float = 30.0

@export var rayon_pose_min: float = 1.5
@export var rayon_pose_max: float = 2.5

const REF_REPRODUCTION := "transporteur"

static var _prochaine_graine := 20260901
var _rng := RandomNumberGenerator.new()
var _catalogue: Dictionary
# LE CUBE VIOLET COMME "MERE" : un Dictionary a la meme forme que ce
# qu'attend gestation.gd, mais qui vit UNIQUEMENT dans ce fichier -- il
# n'est jamais enregistre dans _monde de population_ennemie.gd (le cube
# y a deja son entree, distincte). Deux poches de donnees separees pour
# deux mecaniques separees ; c'est plus simple que d'ajouter une
# structure partagee.
var _mere: Dictionary
var _vivants: Array[Node3D] = []

func _ready() -> void:
	_rng.seed = _prochaine_graine
	_prochaine_graine += 1
	_catalogue = {REF_REPRODUCTION: {"duree_gestation": duree_gestation}}
	_mere = {
		"id": str(get_instance_id()),
		"proprietes": {"reproduction_ref": REF_REPRODUCTION},
	}

	_pondre_les_transporteurs.call_deferred()

	var minuteur := Timer.new()
	minuteur.wait_time = 1.0
	minuteur.autostart = true
	minuteur.timeout.connect(_tick)
	add_child(minuteur)

func _pondre_les_transporteurs() -> void:
	for _i in range(combien):
		var enfant := _pondre_un_transporteur()
		if enfant != null:
			_vivants.append(enfant)

# UN SEUL TRANSPORTEUR, autour du cube parent. Rend le noeud pose, ou null
# si le contenant a disparu (cube detruit).
func _pondre_un_transporteur() -> Node3D:
	var parent_cube := get_parent()
	if parent_cube == null:
		return null
	var accueil := parent_cube.get_parent()
	if accueil == null:
		push_error("garde_transporteurs.gd : aucun contenant pour poser un transporteur")
		return null
	var angle := _rng.randf_range(0.0, TAU)
	var rayon := _rng.randf_range(rayon_pose_min, rayon_pose_max)
	var pose: Vector3 = parent_cube.global_position + Vector3(cos(angle) * rayon, 0.0, sin(angle) * rayon)
	var transporteur := TransporteurScene.instantiate() as Node3D
	accueil.add_child(transporteur)
	transporteur.global_position = pose
	# LE LIEN EXCLUSIF A LA MERE, DONNE ICI ET NULLE PART AILLEURS : sans
	# lui, le transporteur ne saurait pas a qui deposer sa charge, et
	# devinerait sur "cube violet le plus proche" -- ce qui casserait
	# l'exigence de Yael que le lien soit specifique. La mere est le CUBE
	# violet parent du garde (le grand-parent est le contenant).
	if transporteur.has_method("subir_frappe"):
		transporteur.mere = parent_cube
	return transporteur

# UN TICK DE SUIVI : oublie les morts, entame ou avance une gestation,
# pond quand elle est prete. Une seule gestation a la fois, jamais en
# parallele -- voir l'en-tete.
func _tick() -> void:
	# 1. OUBLIER LES MORTS : is_instance_valid, jamais un autre test --
	# une queue_free() invalide au prochain idle, c'est ce qu'on voit ici.
	var restants: Array[Node3D] = []
	for enfant in _vivants:
		if is_instance_valid(enfant):
			restants.append(enfant)
	_vivants = restants

	# 2. RIEN A REMPLACER : tout est plein, on efface toute gestation qui
	# aurait ete entamee juste avant qu'un revenu apparaisse (impossible
	# aujourd'hui, mais l'invariant se garde).
	if _vivants.size() >= combien:
		if _mere.proprietes.has("gestation"):
			_mere.proprietes.erase("gestation")
		return

	# 3. ENTAMER LA GESTATION SI ELLE N'EST PAS DEJA EN COURS. Aucun
	# parametre a passer -- Gestation.poser gere le mode "asexuee".
	if not _mere.proprietes.has("gestation"):
		Gestation.poser(_mere, null, _catalogue)

	# 4. AVANCER D'UNE SECONDE, meme rythme que le Timer.
	Gestation.avancer(_mere, _catalogue, 1.0)

	# 5. NAISSANCE PRETE : pondre, retirer la gestation. Le tick suivant
	# entamera la gestation du prochain s'il en manque encore.
	var gestation: Dictionary = _mere.proprietes.get("gestation", {})
	if gestation.get("naissance_prete", false):
		_mere.proprietes.erase("gestation")
		var enfant := _pondre_un_transporteur()
		if enfant != null:
			_vivants.append(enfant)
