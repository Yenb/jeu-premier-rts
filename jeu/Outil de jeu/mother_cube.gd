extends RigidBody3D

# BANC "test_ennemi2 Mother box" -- LA MOTHER CUBE, pondue par le geniteur
# apres 4 generateurs d'energie vivants + stock >= 100 (voir
# gestation_mother_cube.gd). Petit cube 0.30 m avec 3 vies par defaut.
# Recoit des frappes via Frappe.frapper (framework), affiche sa vie en
# barre 3D via barre_de_vie.gdshader (patron generateur_energie.gd /
# vie_ennemi.gd).
#
# EXTENSIBLE : Yael prevoit d'ajouter des parametres plus tard (croissance
# progressive, production, comportements). Le fichier est structure comme
# les autres bancs (entite Dictionary, reserves nommees, @export
# parametres) pour recevoir de nouveaux champs sans refonte.
#
# NE COMPOSE PAS LA GESTATION : ce fichier ne connait pas son producteur.
# Il vit et meurt seul, s'inscrit dans le groupe "mother_cube" pour que
# le banc de gestation du geniteur puisse compter les vivantes (max 1
# par defaut).
#
# NE REINVENTE PAS LE CALCUL DE DEGATS : Frappe.frapper() (framework)
# soustrait la reserve, bornee a zero.

const Frappe = preload("res://scripts/frappe.gd")
const Perception = preload("res://scripts/perception.gd")

# CATALOGUE LOCAL des canaux perceptifs. Patron transporteur.gd:47-49 --
# on n'ecrit rien dans data/canaux.json (framework), on passe un catalogue
# local a Perception.percevoir. Une seule vue en cone_oriente ; angle >= 360
# (implicite absent) => sphere pure (voir perception.gd:198-200).
const CATALOGUE_CANAUX := {
	"vue": {"geometrie": "cone_oriente"},
}

@export var vie_max: float = 3.0
# PORTEE VUE : 30 m specifie par Yael pour la mother cube. Elle ne voit
# rien au-dela, meme dans l'ecosysteme ennemi. Regle par l'inspecteur.
@export var portee_vision: float = 30.0

var entite: Dictionary
var _barre_vie: MeshInstance3D
var _materiau_vie: ShaderMaterial
# LE MONDE PARTAGE : resolu au _ready via le groupe -- sans lui, la
# perception ne peut rien voir. Une mother cube qui n'en trouve pas se
# rabat sur "je ne percois rien" (percevoir_nourriture rend []), plutot
# que planter.
var _monde_partage: Node = null

# Idempotent : queue_free peut declencher plusieurs chemins, on ne retire
# du monde qu'une fois.
var _est_mort: bool = false

func _mourir() -> void:
	if _est_mort:
		return
	_est_mort = true
	# SORT DU MONDE AVANT queue_free (patron carre_rouge.gd / gisement_fer.gd).
	# Sans ce retrait, un percevant continuerait a la voir comme un fantome.
	if _monde_partage != null:
		_monde_partage.monde.retirer(entite.id)
	queue_free()

func _ready() -> void:
	add_to_group("mother_cube")
	entite = {
		"id": str(get_instance_id()),
		"position": global_position,
		"proprietes": {
			"reserves": {
				"vie": {"reserve": vie_max, "capacite": vie_max},
			},
			# CANAUX PERCEPTIFS -- structurels pour perception.gd (cf.
			# perception.gd:118 : cle absente = push_error). Une seule vue,
			# angle absent = sphere pure a portee_vision metres.
			"canaux": ["vue"],
			"canaux_config": {
				"vue": {"portee": portee_vision, "sensibilite": 1.0, "seuil": 0.0},
			},
		},
		"noeud": self,
	}
	# INSCRIT AU MONDE PARTAGE : sans ca, la mother cube ne serait pas
	# elle-meme percue par d'autres entites (a cabler plus tard : joueur).
	# Meme patron carre_rouge.gd / gisement_fer.gd.
	_monde_partage = get_tree().get_first_node_in_group("monde_partage")
	if _monde_partage != null:
		_monde_partage.monde.ajouter(entite, "mother_cube", global_position)

	_barre_vie = get_node("BarreDeVie/Barre") as MeshInstance3D
	# DUPLIQUE le materiau pour ne pas partager la fraction entre plusieurs
	# instances futures. Meme patron que generateur_energie.gd:_ready.
	_materiau_vie = _barre_vie.mesh.surface_get_material(0).duplicate() as ShaderMaterial
	_barre_vie.set_surface_override_material(0, _materiau_vie)
	_rafraichir_barre()

func _process(_delta: float) -> void:
	# SYNCHRONISATION POSITION MONDE : la mother cube bouge (physique
	# RigidBody + mouvement volontaire au morceau 3). entite.position doit
	# refleter la position vivante pour que Perception.percevoir mesure
	# les distances correctement. Patron transporteur.gd:156.
	if not _est_mort:
		entite["position"] = global_position

# API publique -- appelee par ce qui frappe (arme, projectile, etc.).
func subir_frappe(degats: float) -> void:
	Frappe.frapper(entite, degats, "vie")
	_rafraichir_barre()
	if entite.proprietes.reserves.vie.reserve <= 0.0:
		_mourir()

# API publique -- rend la liste des percepts qui portent une propriete
# "nourriture" > 0 sur leur entite du monde. La couche perception
# (framework) est aveugle et rend TOUT dans le cone de vue ; la saillance
# ici est faite en local par filtrage sur propriete NOMMEE, PAS sur type
# (respect CLAUDE.md § ADN -- aucun test type == "carre_rouge").
#
# Rend un Array de percepts {chose, type, position, distance, canaux} tries
# du plus proche au plus loin. Vide si aucune nourriture percue ou si le
# monde partage est absent.
func percevoir_nourriture() -> Array:
	if _monde_partage == null:
		return []
	var percues := Perception.percevoir(entite, _monde_partage.monde, CATALOGUE_CANAUX)
	var nourritures: Array = []
	for p in percues:
		var props: Dictionary = p.chose.get("proprietes", {})
		if float(props.get("nourriture", 0.0)) > 0.0:
			nourritures.append(p)
	nourritures.sort_custom(func(a, b): return a.distance < b.distance)
	return nourritures

func _rafraichir_barre() -> void:
	var f := clampf(entite.proprietes.reserves.vie.reserve / vie_max, 0.0, 1.0)
	_materiau_vie.set_shader_parameter("fraction", f)
