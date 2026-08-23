extends RigidBody3D

# BANC "test_ennemi2 Mother box" -- LE STOCKEUR, pondu par le geniteur v2
# quand son stock privee atteint 30 (20% de capacite_privee=150). Vit
# 20 min (duree_vie_secondes = 1200). Role : perceoit les carres rouges
# (nourriture pondue par les generateurs), marche vers le plus proche,
# absorbe (frappe one-shot -> carre rouge meurt -> +5 dans son stock).
# Une fois plein (capacite_stock = 100), il rejoint le geniteur et reste
# a distance_suivi_geniteur = 10 m, le suivant en permanence.
#
# NE COMPOSE PAS LA GESTATION : il vit et meurt seul, s'inscrit dans
# "stockeur" a son _ready. Meme patron que generateur_energie.gd.
# Note : distinct du "transporteur" du banc test_ennemi qui trimballe
# des ressources entre gisements et cubes violets -- role different.
#
# NE REINVENTE PAS LA PERCEPTION : Perception.percevoir + saillance sur
# propriete "nourriture > 0" -- respect ADN, aucun test type == "carre_rouge".

const Frappe = preload("res://scripts/frappe.gd")
const Perception = preload("res://scripts/perception.gd")

const CATALOGUE_CANAUX := {
	"vue": {"geometrie": "cone_oriente"},
}

@export var vie_max: float = 3.0
@export var duree_vie_secondes: float = 1200.0
@export var portee_vision: float = 30.0
@export var vitesse_marche: float = 3.5
@export var capacite_stock: float = 100.0
@export var distance_contact_nourriture: float = 1.0
@export var distance_suivi_geniteur: float = 10.0
@export var vitesse_suivi_geniteur: float = 4.0
@export var secondes_par_perception: float = 0.5
# PATROUILLE : quand aucun carre rouge n'est percu ET que le stockeur est
# loin du geniteur (au-dela de rayon_patrouille), il retourne vers le
# geniteur pour se retrouver dans la zone de production des generateurs.
# Sans ca, un stockeur qui a fini d'absorber loin et perdu de vue son
# geniteur reste plante indefiniment. 15 m garde une marge autour du
# geniteur sans coller a lui (le suivi a 10 m n'est actif que quand plein).
@export var rayon_patrouille: float = 50.0

enum {
	ETAT_CHERCHE_NOURRITURE,
	ETAT_VERS_NOURRITURE,
	ETAT_ABSORBE,
	ETAT_SUIT_GENITEUR,
}
var _etat: int = ETAT_CHERCHE_NOURRITURE
var _cible_nourriture: Node3D = null
var _stock: float = 0.0
var _secondes_depuis_perception: float = 999.0

var entite: Dictionary
var _monde_partage: Node = null
var _est_mort: bool = false
var _barre_vie: MeshInstance3D
var _materiau_vie: ShaderMaterial
var _barre_stock: MeshInstance3D = null
var _materiau_stock: ShaderMaterial

func _ready() -> void:
	add_to_group("stockeur")
	# EXCEPTIONS COLLISION avec les entites amies : sans elles, le stockeur
	# se colle bete aux generateurs / geniteur au lieu de circuler pour
	# atteindre les carres rouges. Meme patron que le _ready du generateur
	# qui pose l'exception avec le geniteur. Bidirectionnel cote Godot :
	# l'appel depuis self couvre les deux directions.
	for grp in ["geniteur", "generateur_energie", "ressource", "protogeniteur", "stockeur"]:
		for autre in get_tree().get_nodes_in_group(grp):
			if autre is CollisionObject3D and autre != self:
				(autre as CollisionObject3D).add_collision_exception_with(self)
	var timer_mort := Timer.new()
	timer_mort.wait_time = duree_vie_secondes
	timer_mort.one_shot = true
	timer_mort.autostart = true
	timer_mort.timeout.connect(_mourir)
	add_child(timer_mort)
	entite = {
		"id": str(get_instance_id()),
		"position": global_position,
		"proprietes": {
			"reserves": {"vie": {"reserve": vie_max, "capacite": vie_max}},
			"canaux": ["vue"],
			"canaux_config": {
				"vue": {"portee": portee_vision, "sensibilite": 1.0, "seuil": 0.0},
			},
		},
		"noeud": self,
	}
	_monde_partage = get_tree().get_first_node_in_group("monde_partage")
	if _monde_partage != null:
		_monde_partage.monde.ajouter(entite, "stockeur", global_position)
	_barre_vie = get_node("BarreDeVie/Barre") as MeshInstance3D
	if _barre_vie != null:
		_materiau_vie = _barre_vie.mesh.surface_get_material(0).duplicate() as ShaderMaterial
		_barre_vie.set_surface_override_material(0, _materiau_vie)
		_rafraichir_barre_vie()
	if has_node("BarreDeStock/Barre"):
		_barre_stock = $BarreDeStock/Barre as MeshInstance3D
		_materiau_stock = _barre_stock.mesh.surface_get_material(0).duplicate() as ShaderMaterial
		_barre_stock.set_surface_override_material(0, _materiau_stock)
		_materiau_stock.set_shader_parameter("fraction", 0.0)

func _mourir() -> void:
	if _est_mort:
		return
	_est_mort = true
	if _monde_partage != null and not entite.is_empty():
		_monde_partage.monde.retirer(entite.id)
	queue_free()

func _process(delta: float) -> void:
	if _est_mort:
		return
	entite["position"] = global_position
	if _monde_partage != null:
		_monde_partage.monde.deplacer(entite)
	_secondes_depuis_perception += delta
	if _stock >= capacite_stock and _etat != ETAT_SUIT_GENITEUR:
		_etat = ETAT_SUIT_GENITEUR
		_cible_nourriture = null
	match _etat:
		ETAT_CHERCHE_NOURRITURE:
			_faire_cherche_nourriture()
		ETAT_VERS_NOURRITURE:
			_faire_vers_nourriture(delta)
		ETAT_ABSORBE:
			_faire_absorbe(delta)
		ETAT_SUIT_GENITEUR:
			_faire_suit_geniteur(delta)

func _faire_cherche_nourriture() -> void:
	if _secondes_depuis_perception < secondes_par_perception:
		_appliquer_patrouille()
		return
	_secondes_depuis_perception = 0.0
	var vus: Array = percevoir_nourriture()
	if vus.is_empty():
		# Rien de percu -> patrouille vers geniteur si trop loin.
		_appliquer_patrouille()
		return
	var noeud = vus[0].chose.get("noeud", null)
	if noeud == null or not is_instance_valid(noeud) or not (noeud is Node3D):
		_appliquer_patrouille()
		return
	_cible_nourriture = noeud as Node3D
	_etat = ETAT_VERS_NOURRITURE

# Retour vers le geniteur si le stockeur est au-dela de rayon_patrouille.
# En deca, immobile (attente qu'un carre rouge apparaisse en perception).
# Different de _faire_suit_geniteur qui a une zone morte etroite (+/- 1 m)
# autour de 10 m : ici la zone morte est simplement "sous rayon_patrouille".
func _appliquer_patrouille() -> void:
	var geniteur = get_tree().get_first_node_in_group("geniteur")
	if geniteur == null or not is_instance_valid(geniteur) or not (geniteur is Node3D):
		linear_velocity = Vector3(0.0, linear_velocity.y, 0.0)
		return
	var vers: Vector3 = (geniteur as Node3D).global_position - global_position
	vers.y = 0.0
	if vers.length() > rayon_patrouille:
		var direction := vers.normalized()
		linear_velocity = Vector3(direction.x * vitesse_marche, linear_velocity.y, direction.z * vitesse_marche)
	else:
		linear_velocity = Vector3(0.0, linear_velocity.y, 0.0)

func _faire_vers_nourriture(_delta: float) -> void:
	if _cible_nourriture == null or not is_instance_valid(_cible_nourriture):
		_cible_nourriture = null
		_etat = ETAT_CHERCHE_NOURRITURE
		return
	var vers: Vector3 = _cible_nourriture.global_position - global_position
	vers.y = 0.0
	if vers.length() <= distance_contact_nourriture:
		linear_velocity = Vector3(0.0, linear_velocity.y, 0.0)
		_etat = ETAT_ABSORBE
		return
	var direction := vers.normalized()
	linear_velocity = Vector3(direction.x * vitesse_marche, linear_velocity.y, direction.z * vitesse_marche)

func _faire_absorbe(_delta: float) -> void:
	if _cible_nourriture == null or not is_instance_valid(_cible_nourriture):
		_cible_nourriture = null
		_etat = ETAT_CHERCHE_NOURRITURE
		return
	linear_velocity = Vector3(0.0, linear_velocity.y, 0.0)
	if not _cible_nourriture.has_method("subir_frappe"):
		_cible_nourriture = null
		_etat = ETAT_CHERCHE_NOURRITURE
		return
	var gain: float = 0.0
	if "entite" in _cible_nourriture:
		gain = float(_cible_nourriture.entite.proprietes.get("nourriture", 0.0))
	_cible_nourriture.subir_frappe(999.0)
	_stock = minf(_stock + gain, capacite_stock)
	if _materiau_stock != null:
		_materiau_stock.set_shader_parameter("fraction", _stock / capacite_stock)
	_cible_nourriture = null
	_etat = ETAT_CHERCHE_NOURRITURE

func _faire_suit_geniteur(_delta: float) -> void:
	var geniteur = get_tree().get_first_node_in_group("geniteur")
	if geniteur == null or not is_instance_valid(geniteur) or not (geniteur is Node3D):
		linear_velocity = Vector3(0.0, linear_velocity.y, 0.0)
		return
	var geniteur3d := geniteur as Node3D
	var vers: Vector3 = geniteur3d.global_position - global_position
	vers.y = 0.0
	var d: float = vers.length()
	if d > distance_suivi_geniteur + 1.0:
		var direction := vers.normalized()
		linear_velocity = Vector3(direction.x * vitesse_suivi_geniteur, linear_velocity.y, direction.z * vitesse_suivi_geniteur)
	elif d < distance_suivi_geniteur - 1.0:
		var direction := (-vers).normalized()
		linear_velocity = Vector3(direction.x * vitesse_suivi_geniteur, linear_velocity.y, direction.z * vitesse_suivi_geniteur)
	else:
		linear_velocity = Vector3(0.0, linear_velocity.y, 0.0)

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

func subir_frappe(degats: float) -> void:
	Frappe.frapper(entite, degats, "vie")
	_rafraichir_barre_vie()
	if entite.proprietes.reserves.vie.reserve <= 0.0:
		_mourir()

func _rafraichir_barre_vie() -> void:
	if _materiau_vie == null:
		return
	var f := clampf(entite.proprietes.reserves.vie.reserve / vie_max, 0.0, 1.0)
	_materiau_vie.set_shader_parameter("fraction", f)
