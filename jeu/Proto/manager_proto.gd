# PROTO -- manager qui separe simulation (donnee) et rendu.
#
# SIMULATION (independante du rendu) :
#   - Producteurs : extraction sur reserves internes (Dict cellule->float),
#     initialisees a `capacite_case` a la premiere visite. Regen locale.
#     Autonome, sans dependance au catalogue `ressources_terrain` limite
#     au disque initial du terrain streame.
#   - Deplacement : couche sommet via `carte_terrain.sommet(colonne)`,
#     conversion cellule -> monde via `_grille.to_global(_grille.map_to_local(c))`.
#   - Carres rouges pondus en DONNEE (dict {position, age, noeud}).
#     Age incremente chaque frame, retire quand `age >= duree_pourriture_carre`.
#
# RENDU (bascule selon distance a observateur) :
#   - Producteurs : nœud producteur.tscn (mode passif).
#   - Carres rouges : nœud carre_rouge_visuel.tscn (peau simple, aucun Timer).

extends Node

const ProducteurScene = preload("res://jeu/Proto/producteur.tscn")
const CarreVisuelScene = preload("res://jeu/Outil de jeu/carre_rouge.tscn")

@export var rayon_rendu: float = 40.0
@export var groupe_observateur: StringName = &"observateur"

@export var intervalle_extraction: float = 1.0
@export var quantite_par_tick: float = 1.0
@export var seuil_ponte: float = 5.0
@export var capacite_stock: float = 50.0

@export var capacite_case: float = 50.0
@export var quantite_regen_par_tick: float = 0.033

@export var duree_pourriture_carre: float = 3600.0
@export var pas_angle_ponte: float = 0.7
@export var rayon_ponte: float = 1.5

@export var rayon_detection: float = 30.0
@export var vitesse_sol: float = 3.0
@export var cote_cellule: float = 2.0

const TICKS_ROUGE_AVANT_DEPART := 2
const DISTANCE_MIN_CIBLE := 4.0
const ECART_VERTICAL_MAX_CIBLE := 5.0

var _observateur: Node3D = null
var _carte: Resource = null
var _grille: GridMap = null
var _reserves: Dictionary = {}
var _producteurs: Array = []
var _carres: Array = []
var _horloge: float = 0.0

func _ready() -> void:
	_observateur = get_tree().get_first_node_in_group(groupe_observateur)
	var parent := get_parent()
	if parent != null:
		var terrain := parent.get_node_or_null("Terrain")
		if terrain != null:
			_carte = terrain.get("carte") as Resource
			_grille = terrain as GridMap
	if _carte == null:
		push_warning("manager_proto : carte introuvable")
	if _grille == null:
		push_warning("manager_proto : GridMap introuvable")
	call_deferred("_convertir_producteurs_initiaux")

func _convertir_producteurs_initiaux() -> void:
	var parent := get_parent()
	if parent == null:
		return
	for enfant in parent.get_children():
		if not (enfant is Node3D):
			continue
		if not enfant.is_in_group("producteur"):
			continue
		if enfant.has_method("set_passif"):
			enfant.call("set_passif", true)
		_producteurs.append({
			"position": (enfant as Node3D).global_position,
			"stock": 0.0,
			"ticks_vides": 0,
			"cible": null,
			"cellule_courante": null,
			"angle_ponte": 0.0,
			"noeud": enfant as Node3D,
		})

func _process(delta: float) -> void:
	_horloge += delta
	if _horloge >= intervalle_extraction:
		_horloge = 0.0
		_tick_extraction()
		_tick_regen()
	_avancer_donnees(delta)
	_ticker_carres(delta)
	_bascule_rendu_producteurs()
	_bascule_rendu_carres()

func _avancer_donnees(delta: float) -> void:
	for prod in _producteurs:
		if prod.cible == null:
			continue
		var vers: Vector3 = (prod.cible as Vector3) - prod.position
		vers.y = 0.0
		if vers.length() <= 1.0:
			prod.cible = null
			continue
		var direction := vers.normalized()
		prod.position += direction * vitesse_sol * delta

func _tick_extraction() -> void:
	if _carte == null:
		return
	for prod in _producteurs:
		if prod.cible != null:
			continue
		var pos: Vector3 = prod.position
		var x := int(floor(pos.x / cote_cellule))
		var z := int(floor(pos.z / cote_cellule))
		var sommet: Variant = _carte.sommet(Vector2i(x, z))
		if sommet == null:
			prod.ticks_vides += 1
			if prod.ticks_vides >= TICKS_ROUGE_AVANT_DEPART:
				prod.ticks_vides = 0
				_choisir_cible(prod)
			continue
		var cellule := Vector3i(x, int(sommet), z)
		prod.cellule_courante = cellule
		var pris := _preleve(cellule, quantite_par_tick)
		if pris > 0.0:
			prod.stock = minf(prod.stock + pris, capacite_stock)
			while prod.stock >= seuil_ponte:
				prod.stock -= seuil_ponte
				_pondre(prod)
		# TICKS VIDES : la regen (0.033/s) laisse pris > 0 meme quand la
		# case est essentiellement vide. Un tick vide = "n'a pas satisfait
		# la demande" (pris < quantite_par_tick), pas "pris nul". Sans ca,
		# regen empeche _choisir_cible de se declencher.
		if pris >= quantite_par_tick:
			prod.ticks_vides = 0
		else:
			prod.ticks_vides += 1
			if prod.ticks_vides >= TICKS_ROUGE_AVANT_DEPART:
				prod.ticks_vides = 0
				_choisir_cible(prod)

func _preleve(cellule: Vector3i, quantite: float) -> float:
	var stock: float = _reserves.get(cellule, capacite_case)
	var pris: float = minf(quantite, stock)
	_reserves[cellule] = stock - pris
	return pris

func _tick_regen() -> void:
	for cellule in _reserves.keys():
		var s: float = _reserves[cellule]
		if s < capacite_case:
			_reserves[cellule] = minf(s + quantite_regen_par_tick, capacite_case)

func _choisir_cible(prod: Dictionary) -> void:
	if _carte == null or _grille == null:
		return
	var pos_ici: Vector3 = prod.position
	var cx := int(floor(pos_ici.x / cote_cellule))
	var cz := int(floor(pos_ici.z / cote_cellule))
	var rayon_cases := int(ceil(rayon_detection / cote_cellule))
	var meilleure: Variant = null
	var meilleure_d2: float = INF
	for dx in range(-rayon_cases, rayon_cases + 1):
		for dz in range(-rayon_cases, rayon_cases + 1):
			var col := Vector2i(cx + dx, cz + dz)
			var som: Variant = _carte.sommet(col)
			if som == null:
				continue
			var cellule := Vector3i(col.x, int(som), col.y)
			if prod.cellule_courante != null and cellule == (prod.cellule_courante as Vector3i):
				continue
			var reserve: float = _reserves.get(cellule, capacite_case)
			if reserve <= 0.0:
				continue
			var pos_c := _grille.to_global(_grille.map_to_local(cellule))
			if absf(pos_c.y - pos_ici.y) > ECART_VERTICAL_MAX_CIBLE:
				continue
			var ex := pos_c.x - pos_ici.x
			var ez := pos_c.z - pos_ici.z
			var dh2 := ex * ex + ez * ez
			if sqrt(dh2) < DISTANCE_MIN_CIBLE:
				continue
			if dh2 < meilleure_d2:
				meilleure_d2 = dh2
				meilleure = Vector3(pos_c.x, pos_ici.y, pos_c.z)
	if meilleure != null:
		prod.cible = meilleure

func _pondre(prod: Dictionary) -> void:
	prod.angle_ponte += pas_angle_ponte
	var offset := Vector3(cos(prod.angle_ponte), 0.0, sin(prod.angle_ponte)) * rayon_ponte
	_carres.append({
		"position": prod.position + offset,
		"age": 0.0,
		"noeud": null,
		# EST_DETRUIT : bascule a true via le signal `detruit` emis par
		# carre_rouge.gd:_mourir. C'est le SEUL moyen fiable de detecter
		# la destruction externe : en Godot 4, cr.noeud freed compare
		# `== null` a true dans un Dictionary, is_instance_valid pas
		# suffisant seul (voir issue godotengine/godot#35534).
		"est_detruit": false,
	})

func _ticker_carres(delta: float) -> void:
	var i := 0
	while i < _carres.size():
		var cr = _carres[i]
		# PURGE si le carre a emis son signal `detruit` (frappe balle ou
		# pourriture cote framework). Le flag est fiable, contrairement au
		# test `cr.noeud == null OR !is_instance_valid` qui echoue en
		# Godot 4 sur les refs freed dans un Dictionary.
		if cr.est_detruit:
			_carres.remove_at(i)
			continue
		cr.age += delta
		if cr.age >= duree_pourriture_carre:
			if cr.noeud != null and is_instance_valid(cr.noeud):
				cr.noeud.queue_free()
			_carres.remove_at(i)
			continue
		i += 1

func _bascule_rendu_producteurs() -> void:
	if _observateur == null:
		return
	var pos_obs: Vector3 = _observateur.global_position
	var parent := get_parent()
	if parent == null:
		return
	var r2 := rayon_rendu * rayon_rendu
	for prod in _producteurs:
		var d2: float = (prod.position - pos_obs).length_squared()
		if d2 < r2:
			if prod.noeud == null or not is_instance_valid(prod.noeud):
				var n := ProducteurScene.instantiate() as Node3D
				if n.has_method("set_passif"):
					n.set_passif(true)
				parent.add_child(n)
				n.global_position = prod.position
				prod.noeud = n
			else:
				prod.noeud.global_position = prod.position
			if prod.noeud.has_method("set_stock_visuel"):
				prod.noeud.set_stock_visuel(prod.stock)
		else:
			if prod.noeud != null and is_instance_valid(prod.noeud):
				prod.noeud.queue_free()
				prod.noeud = null

func _bascule_rendu_carres() -> void:
	if _observateur == null:
		return
	var pos_obs: Vector3 = _observateur.global_position
	var parent := get_parent()
	if parent == null:
		return
	var r2 := rayon_rendu * rayon_rendu
	for cr in _carres:
		var d2: float = ((cr.position as Vector3) - pos_obs).length_squared()
		if d2 < r2:
			# CREATE si pas de nœud (nouvellement pondu, ou revient dans
			# rayon apres sortie). Le flag est_detruit filtrera plus haut
			# les cr deja detruits externement.
			if cr.noeud == null or not is_instance_valid(cr.noeud):
				var n := CarreVisuelScene.instantiate() as Node3D
				if "passif" in n:
					n.set("passif", true)
				parent.add_child(n)
				n.global_position = cr.position
				# Signal `detruit` du framework carre_rouge : le manager
				# marque est_detruit=true quand le carre meurt (frappe
				# balle, pourriture, autre). _ticker_carres purgera.
				# capture cr dans une closure pour reference stable.
				var cr_ref: Dictionary = cr
				if n.has_signal("detruit"):
					n.detruit.connect(func(): cr_ref["est_detruit"] = true)
				# EXCEPTION COLLISION avec producteurs : sans ca les carres
				# pondus tout autour du producteur RigidBody3D le ceinturent
				# et le bloquent physiquement (constate a l'ecran par Yael).
				# Meme geste que jeu/Outil de jeu/generateur_energie.gd:_ready
				# pour l'exclusion geniteur/generateur.
				if n is CollisionObject3D:
					for prod in _producteurs:
						if prod.noeud != null and is_instance_valid(prod.noeud) and prod.noeud is CollisionObject3D:
							(prod.noeud as CollisionObject3D).add_collision_exception_with(n)
				cr.noeud = n
				cr.avait_noeud = true
			elif cr.noeud != null and is_instance_valid(cr.noeud):
				cr.position = cr.noeud.global_position
		else:
			# HORS RAYON : detruit le nœud et met noeud=null. On garde
			# avait_noeud=true, donc si le joueur s'eloigne puis les carres
			# meurent naturellement (age), _ticker_carres purgera.
			# ATTENTION : si le joueur revient dans le rayon, la condition
			# `not cr.avait_noeud` empeche la recreation. C'est un choix :
			# une fois qu'un carre est passe par le rendu, il ne reprend
			# pas de peau -- sinon on peut retirer le && not avait_noeud
			# et accepter la recreation propre.
			if cr.noeud != null and is_instance_valid(cr.noeud):
				cr.noeud.queue_free()
				cr.noeud = null
