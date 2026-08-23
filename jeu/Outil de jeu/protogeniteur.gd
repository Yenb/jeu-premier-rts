extends RigidBody3D

# BANC "test_ennemi2 Mother box" -- LE PROTOGENITEUR, pondu par le geniteur
# v2 quand son stock privee atteint 120 (80% de capacite_privee=150). Vit
# 20 min (duree_vie_secondes = 1200). Role : produit auto de l'ENERGIE
# (stock_public), les generateurs peuvent venir puiser dessus comme sur le
# geniteur (perception via stock_puisable > 0). Suit le geniteur a
# distance_suivi_geniteur = 60 m.
#
# NE COMPOSE PAS LA GESTATION : il vit et meurt seul, s'inscrit dans
# "protogeniteur" a son _ready. Meme patron que stockeur.gd pour le suivi
# et generateur_energie.gd pour la mort/inscription.
#
# NE REINVENTE PAS L'EXTRACTION TERRAIN : Yael a specifie "produit de
# l'energie" -- production auto par tick (production_par_seconde), pas de
# raycast sur GridMap. C'est ce qui distingue le protogeniteur du geniteur
# lui-meme, qui, lui, extrait des cellules marrons.

const Frappe = preload("res://scripts/frappe.gd")

@export var vie_max: float = 5.0
@export var duree_vie_secondes: float = 1200.0
@export var capacite_public: int = 100
@export var production_par_seconde: float = 2.0
@export var distance_suivi_geniteur: float = 60.0
@export var vitesse_suivi_geniteur: float = 4.0

var _stock_public: float = 0.0
var entite: Dictionary
var _monde_partage: Node = null
var _est_mort: bool = false
var _barre_vie: MeshInstance3D
var _materiau_vie: ShaderMaterial
var _barre_stock: MeshInstance3D = null
var _materiau_stock: ShaderMaterial

func _ready() -> void:
	add_to_group("protogeniteur")
	for grp in ["geniteur", "generateur_energie", "stockeur", "ressource", "protogeniteur"]:
		for autre in get_tree().get_nodes_in_group(grp):
			if autre is CollisionObject3D and autre != self:
				(autre as CollisionObject3D).add_collision_exception_with(self)
	var timer_mort := Timer.new()
	timer_mort.wait_time = duree_vie_secondes
	timer_mort.one_shot = true
	timer_mort.autostart = true
	timer_mort.timeout.connect(_mourir)
	add_child(timer_mort)
	var timer_prod := Timer.new()
	timer_prod.wait_time = 1.0
	timer_prod.one_shot = false
	timer_prod.autostart = true
	timer_prod.timeout.connect(_tick_production)
	add_child(timer_prod)
	entite = {
		"id": str(get_instance_id()),
		"position": global_position,
		"proprietes": {
			"reserves": {"vie": {"reserve": vie_max, "capacite": vie_max}},
			"stock_puisable": _stock_public,
		},
		"noeud": self,
	}
	_monde_partage = get_tree().get_first_node_in_group("monde_partage")
	if _monde_partage != null:
		_monde_partage.monde.ajouter(entite, "protogeniteur", global_position)
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
	_suivre_geniteur(delta)

func _tick_production() -> void:
	if _est_mort:
		return
	_stock_public = minf(_stock_public + production_par_seconde, float(capacite_public))
	if _materiau_stock != null:
		_materiau_stock.set_shader_parameter("fraction", _stock_public / float(capacite_public))
	if not entite.is_empty():
		entite.proprietes["stock_puisable"] = _stock_public

func _suivre_geniteur(_delta: float) -> void:
	var geniteur = get_tree().get_first_node_in_group("geniteur")
	if geniteur == null or not is_instance_valid(geniteur) or not (geniteur is Node3D):
		linear_velocity = Vector3(0.0, linear_velocity.y, 0.0)
		return
	var vers: Vector3 = (geniteur as Node3D).global_position - global_position
	vers.y = 0.0
	var d: float = vers.length()
	if d > distance_suivi_geniteur + 2.0:
		var direction := vers.normalized()
		linear_velocity = Vector3(direction.x * vitesse_suivi_geniteur, linear_velocity.y, direction.z * vitesse_suivi_geniteur)
	elif d < distance_suivi_geniteur - 2.0:
		var direction := (-vers).normalized()
		linear_velocity = Vector3(direction.x * vitesse_suivi_geniteur, linear_velocity.y, direction.z * vitesse_suivi_geniteur)
	else:
		linear_velocity = Vector3(0.0, linear_velocity.y, 0.0)

func preleve_stock_puisable(quantite: float) -> float:
	return preleve_stock_public(quantite)

func preleve_stock_public(quantite: float) -> float:
	var pris: float = minf(quantite, _stock_public)
	_stock_public = _stock_public - pris
	if _materiau_stock != null:
		_materiau_stock.set_shader_parameter("fraction", _stock_public / float(capacite_public))
	if not entite.is_empty():
		entite.proprietes["stock_puisable"] = _stock_public
	return pris

func stock_public_courant() -> float:
	return _stock_public

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
