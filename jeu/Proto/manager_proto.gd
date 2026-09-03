@tool
extends Node

const ProducteurScene = preload("res://jeu/Proto/producteur.tscn")
const CarreVisuelScene = preload("res://jeu/Outil de jeu/carre_rouge.tscn")
const BalleScene = preload("res://jeu/Proto/balle_violette.tscn")
const BarreVieShader = preload("res://jeu/Outil de jeu/barre_de_vie.gdshader")
const Tas = preload("res://jeu/Proto/tas.gd")
const Ennemis = preload("res://jeu/Proto/ennemis.gd")
# Framework de tick + mouvement partage : les producteurs delèguent leur pas
# horizontal + gravite + snap sol a Mouvement (profil "simple") via Tick.
const Mouvement = preload("res://scripts/mouvement_kinematic.gd")
const Tick = preload("res://scripts/tick.gd")

@export_group("Rendu")
# Hysteresis : instancier sous *_entrer, liberer au-dela de *_sortir. L'ecart
# evite le flip-flop au bord. Producteurs / carres / ennemis / tas partagent le
# meme couple. Balles ont le leur, plus serre (projectiles rapides, on ne veut
# pas les garder visibles apres leur sortie effective).
@export var rayon_rendu_entrer: float = 60.0
@export var rayon_rendu_sortir: float = 65.0
@export var rayon_rendu_balles_entrer: float = 60.0
@export var rayon_rendu_balles_sortir: float = 61.0
@export var groupe_observateur: StringName = &"observateur"

@export_group("Producteurs")
@export var intervalle_extraction: float = 1.0
@export var quantite_par_tick: float = 1.0
@export var seuil_ponte: float = 5.0
@export var capacite_stock: float = 50.0
@export var rayon_detection: float = 30.0
@export var vitesse_sol: float = 3.0

@export_group("Ressources sol")
@export var capacite_case: float = 50.0
@export var quantite_regen_par_tick: float = 0.033
@export var cote_cellule: float = 2.0

@export_group("Carres rouges")
@export var duree_pourriture_carre: float = 3600.0
@export var pas_angle_ponte: float = 0.7
@export var rayon_ponte: float = 1.5

@export_group("Ennemis")
@export var spawn_demi_cote: float = 10.0 : set = _set_spawn_demi_cote
@export var spawn_ennemis_actif: bool = true
@export var intervalle_spawn_ennemi: float = 1.0
@export var max_ennemis: int = 2500
# Nombre d'ennemis crees a chaque intervalle de spawn (avant plafond max).
@export var ennemis_par_cycle: int = 5
@export var vitesse_ennemi: float = 2.0
@export var vie_ennemi: int = 3


const TICKS_ROUGE_AVANT_DEPART := 2
const DISTANCE_MIN_CIBLE := 4.0
const ECART_VERTICAL_MAX_CIBLE := 5.0
const FRAMES_SANS_SOL_MAX := 14
const GRAVITE_DATA := 9.8
const MARGE_SAFE := 4.0
var _rayon_safe: float = 20.0
var _rayon_safe2: float = 400.0

var _observateur: Node3D = null
const PV_JOUEUR_MAX := 200.0
const RAYON_CONTACT_CARRE_JOUEUR := 0.8
const DEGAT_CARRE_PAR_S := 1.0
var _pv_joueur: float = PV_JOUEUR_MAX
var _hud_barre_pv: ColorRect = null
var _hud_barre_fond: ColorRect = null
var _carte: Resource = null
var _grille: GridMap = null
var _reserves: Dictionary = {}
var _producteurs: Array = []
var _carres: Array = []
var _balles: Array = []
var _impacts: Array = []
var _horloge: float = 0.0
var _tas
var _ennemis
# Compteur d'id des OUTILS (pelle/beche), qui vivent dans le monde des tas mais
# ne sont pas geres par tas.gd (exclus de l'index). Le prefixe "pelle_"/"beche_"
# les rend uniques independamment du compteur "sc_" de tas.gd.
var _prochain_id_outil: int = 0
var _cube_porte: Dictionary = {}
const RAYON_PRENDRE_METRES := 2.0
const OFFSET_PORTAGE := Vector3(0.5, -0.5, -1.0)
const PV_PELLE_PAR_COUP := 10
const PORTEE_PELLE_METRES := 5.0
const PORTEE_BECHE_METRES := 5.0
const LAYER_RAMASSABLE := 4
const COUT_CREUSER_PAR_COUP := 10.0
const COUT_BECHER_PAR_COUP := 10.0
var _halo_pelle: MeshInstance3D = null
var _halo_beche: MeshInstance3D = null
var _index_bloc_beche: int = -1
var _halo_pose: MeshInstance3D = null
var _mesh_ennemi: BoxMesh
var _mesh_barre: PlaneMesh

const VITESSE_BALLE := 20.0
const DUREE_BALLE := 5.0
const RAYON_HIT_CARRE := 0.35
const RAYON_EXCLUSION_TIREUR := 1.0
const RAYON_EXCLUSION_TIREUR2 := RAYON_EXCLUSION_TIREUR * RAYON_EXCLUSION_TIREUR
const RAYON_REPOUSSE_CARRES := 0.6
const FORCE_REPOUSSE := 2.0
const DUREE_IMPACT := 0.35

func _ready() -> void:
	if Engine.is_editor_hint():
		_rafraichir_zone_spawn()
		return
	# GROUPE "manager_proto" : permet a arme_tir.gd de retrouver le manager
	# pour lui pousser les balles (spawn_balle). Sans groupe, arme_tir
	# devrait connaitre le chemin de scene -- fragile.
	add_to_group("manager_proto")
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
	_creer_halo_pelle()
	_creer_halo_beche()
	_creer_halo_pose()
	if _grille != null and _grille.mesh_library != null:
		var meshlib: MeshLibrary = _grille.mesh_library
		for id in meshlib.get_item_list():
			if meshlib.get_item_name(id) == "bloc_beche":
				_index_bloc_beche = id
				break
		if _index_bloc_beche < 0:
			push_warning("manager_proto : item 'bloc_beche' introuvable dans le MeshLibrary")
	if _grille != null and _carte != null:
		var rayon_cellules_terrain: int = _grille.get("rayon_cellules") if "rayon_cellules" in _grille else 15
		var pas: int = _grille.get("pas_de_rafraichissement") if "pas_de_rafraichissement" in _grille else 4
		var cote: float = _carte.get("cote") if "cote" in _carte else 2.0
		_rayon_safe = max(0.0, float(rayon_cellules_terrain - pas) * cote - MARGE_SAFE)
		_rayon_safe2 = _rayon_safe * _rayon_safe
	call_deferred("_convertir_producteurs_initiaux")
	_preparer_meshes_ennemis()
	_preparer_hud_pv()
	_tas = Tas.new(_carte, cote_cellule, Callable(self, "_limite_hauteur_matiere"))
	_ennemis = Ennemis.new(_carte, cote_cellule, _tas,
		Callable(self, "_position_observateur"),
		Callable(self, "_effondrer_selon_materiau"),
		spawn_ennemis_actif, spawn_demi_cote, intervalle_spawn_ennemi,
		max_ennemis, ennemis_par_cycle, vitesse_ennemi, vie_ennemi)
	call_deferred("_spawn_pelle_initiale")
	call_deferred("_spawn_beche_initiale")
	var zone := get_node_or_null("ZoneSpawn") as Node3D
	if zone == null:
		push_warning("manager_proto : nœud enfant 'ZoneSpawn' introuvable — aucun spawn d'ennemi")
	else:
		_ennemis.zone_spawn_set(zone)
		_rafraichir_zone_spawn()
	# Capture des marqueurs "ennemi_test_statique" de la scene (patron A) : chaque
	# noeud du groupe cree un ennemi immobile a sa position, puis le noeud marqueur
	# est retire (il ne sert qu'a porter la position). Deferre : le groupe se
	# remplit au _ready des noeuds, apres celui-ci.
	call_deferred("_capturer_ennemis_statiques_test")

func _capturer_ennemis_statiques_test() -> void:
	if _ennemis == null:
		return
	for marqueur in get_tree().get_nodes_in_group(&"ennemi_test_statique"):
		if not (marqueur is Node3D):
			continue
		_ennemis.ajouter_statique((marqueur as Node3D).global_position)
		marqueur.queue_free()

# Percepteur passe au module ennemis (Callable) : rend la position du joueur,
# ou null s'il n'y a pas de joueur -- le module ne connait pas _observateur.
func _position_observateur() -> Variant:
	if _observateur == null:
		return null
	return _observateur.global_position

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
		# Harmonisation avec l'instantiation runtime de _bascule_rendu_producteurs :
		# tout producteur passe en FREEZE KINEMATIC des la capture, sinon un
		# producteur pre-place dans la scene tourne en physique active
		# (freeze=false), _avancer_donnees fait continue sur lui (branche
		# physique_active), Tick n'est jamais appele -- il echappe au pipeline
		# data-pure + streaming. Doctrine 5c : producteurs toujours frozen.
		if enfant is RigidBody3D:
			var rb: RigidBody3D = enfant
			rb.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			rb.freeze = true
		_producteurs.append({
			"position": (enfant as Node3D).global_position,
			"stock": 0.0,
			"ticks_vides": 0,
			"cible": null,
			"cellule_courante": null,
			"angle_ponte": 0.0,
			"noeud": enfant as Node3D,
			"frames_sans_sol": 0,
			# Contrat Mouvement + Tick (profil "simple"). L'IA n'ecrit PAS ce sous-dict
			# a part velocite_desiree_horizontale, posee chaque tour par _avancer_donnees.
			"proprietes": {
				"profil": "simple",
				"cadence_tick": 1,
				"velocite": Vector3.ZERO,
				"velocite_desiree_horizontale": Vector3.ZERO,
				"saut_demande": false,
				"vitesse_saut": 0.0,
				"rayon_capsule": 0.4,
				"hauteur_capsule": 0.8,
				"gravite": 18.0,
				"au_sol": false,
				"y_appui_entite": -INF,
			},
		})

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_maj_halo_pelle()
	_maj_halo_beche()
	_maj_halo_pose()
	_horloge += delta
	if _horloge >= intervalle_extraction:
		_horloge = 0.0
		_tick_extraction()
		_tick_regen()
	_avancer_donnees(delta)
	_ticker_carres(delta)
	_repousser_carres(delta)
	_tick_balles(delta)
	_ticker_impacts(delta)
	_bascule_rendu_producteurs()
	_bascule_rendu_carres()
	_bascule_rendu_balles()
	_ennemis.tick(delta)
	_bascule_rendu_ennemis()
	_tas.tick(delta)
	_bascule_rendu_tas()
	_sync_cube_porte()
	_tick_pv_joueur(delta)

func _avancer_donnees(delta: float) -> void:
	for prod in _producteurs:
		if prod.cible == null:
			continue
		var physique_active := prod.noeud != null and is_instance_valid(prod.noeud) \
			and prod.noeud is RigidBody3D and not (prod.noeud as RigidBody3D).freeze
		if physique_active:
			continue  # velocity pilote via _bascule_rendu_producteurs
		var vers: Vector3 = (prod.cible as Vector3) - prod.position
		vers.y = 0.0
		if vers.length() <= 1.0:
			prod.cible = null
			prod.proprietes["velocite_desiree_horizontale"] = Vector3.ZERO
			continue
		var direction := vers.normalized()
		prod.proprietes["velocite_desiree_horizontale"] = direction * vitesse_sol
		Tick.tick_entite(prod, Callable(Tick, "politique_intrinseque"), delta, null, _carte)

func _tick_extraction() -> void:
	if _carte == null:
		return
	for prod in _producteurs:
		if prod.cible != null:
			continue
		var pos: Vector3 = prod.position
		var x := int(floor(pos.x / cote_cellule))
		var z := int(floor(pos.z / cote_cellule))
		var sommet: Variant = _carte.sommet_max_colonne(Vector2i(x, z))
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

func quantite_a(cellule: Vector3i) -> int:
	return int(floor(_reserves.get(cellule, capacite_case)))

func preleve(cellule: Vector3i, quantite: float) -> float:
	return _preleve(cellule, quantite)

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
			var som: Variant = _carte.sommet_max_colonne(col)
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
		"vy": 0.0,
		"age": 0.0,
		"noeud": null,
		"est_detruit": false,
		"frames_sans_sol": 0,
	})

func _ticker_carres(delta: float) -> void:
	var i := 0
	while i < _carres.size():
		var cr = _carres[i]
		if cr.est_detruit:
			_carres.remove_at(i)
			continue
		cr.age += delta
		if cr.age >= duree_pourriture_carre:
			if cr.noeud != null and is_instance_valid(cr.noeud):
				cr.noeud.queue_free()
			_carres.remove_at(i)
			continue
		var physique_active := cr.noeud != null and is_instance_valid(cr.noeud) \
			and cr.noeud is RigidBody3D and not (cr.noeud as RigidBody3D).freeze
		if not physique_active:
			_appliquer_gravite_data(cr, delta)
		i += 1

func _appliquer_gravite_data(cr: Dictionary, delta: float) -> void:
	if _carte == null:
		return
	var cote_sous: float = cote_cellule / 3.0
	var y_ref: float = cr.position.y + cote_sous * 0.5
	var y_haut_v: Variant = _tas.sommet_effectif(cr.position.x, cr.position.z, y_ref)
	if y_haut_v == null:
		return
	var y_sol: float = float(y_haut_v) + 0.2
	if cr.position.y > y_sol:
		cr.vy -= GRAVITE_DATA * delta
		cr.position.y += cr.vy * delta
		if cr.position.y <= y_sol:
			cr.position.y = y_sol
			cr.vy = 0.0
	else:
		cr.vy = 0.0

func _bascule_rendu_producteurs() -> void:
	if _observateur == null:
		return
	var pos_obs: Vector3 = _observateur.global_position
	var parent := get_parent()
	if parent == null:
		return
	var r2_entrer := rayon_rendu_entrer * rayon_rendu_entrer
	var r2_sortir := rayon_rendu_sortir * rayon_rendu_sortir
	for prod in _producteurs:
		var d2: float = (prod.position - pos_obs).length_squared()
		var a_noeud: bool = prod.noeud != null and is_instance_valid(prod.noeud)
		if a_noeud and d2 > r2_sortir:
			prod.noeud.queue_free()
			prod.noeud = null
		elif not a_noeud and d2 < r2_entrer:
			var n := ProducteurScene.instantiate() as Node3D
			if n.has_method("set_passif"):
				n.set_passif(true)
			if n is RigidBody3D:
				var rb_new: RigidBody3D = n
				rb_new.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
				rb_new.freeze = true
			parent.add_child(n)
			n.global_position = prod.position
			prod.noeud = n
			if prod.noeud.has_method("set_stock_visuel"):
				prod.noeud.set_stock_visuel(prod.stock)
		elif a_noeud:
			# Producteurs bascules sur Tick + Mouvement (profil "simple") : le
			# vertical est desormais exclusivement Mouvement.pas, jamais un snap
			# legacy. On n'appelle plus _gerer_freeze_kinematic ici -- le RB reste
			# frozen tel qu'a la creation (kinematic pur), la branche unfrozen
			# ci-dessous devient morte pour prod (surface de diff minimale).
			if prod.noeud is RigidBody3D:
				var rb: RigidBody3D = prod.noeud
				if not rb.freeze:
					# Velocity vers cible, sinon 0.
					var vel := Vector3.ZERO
					if prod.cible != null:
						var vers: Vector3 = (prod.cible as Vector3) - rb.global_position
						vers.y = 0.0
						if vers.length() <= 1.0:
							prod.cible = null
						else:
							vel = vers.normalized() * vitesse_sol
					rb.linear_velocity = Vector3(vel.x, rb.linear_velocity.y, vel.z)
					prod.position = rb.global_position
				else:
					rb.global_position = prod.position
			if prod.noeud.has_method("set_stock_visuel"):
				prod.noeud.set_stock_visuel(prod.stock)

func _bascule_rendu_carres() -> void:
	if _observateur == null:
		return
	var pos_obs: Vector3 = _observateur.global_position
	var parent := get_parent()
	if parent == null:
		return
	var r2_entrer := rayon_rendu_entrer * rayon_rendu_entrer
	var r2_sortir := rayon_rendu_sortir * rayon_rendu_sortir
	for cr in _carres:
		var d2: float = ((cr.position as Vector3) - pos_obs).length_squared()
		var a_noeud: bool = cr.noeud != null and is_instance_valid(cr.noeud)
		if a_noeud and d2 > r2_sortir:
			cr.noeud.queue_free()
			cr.noeud = null
		elif not a_noeud and d2 < r2_entrer:
			var n := CarreVisuelScene.instantiate() as Node3D
			if "passif" in n:
				n.set("passif", true)
			parent.add_child(n)
			n.global_position = cr.position
			var cr_ref: Dictionary = cr
			if n.has_signal("detruit"):
				n.detruit.connect(func(): cr_ref["est_detruit"] = true)
			# Sans exception collision avec producteurs, les carres pondus
			# tout autour du producteur RigidBody3D le ceinturent et le
			# bloquent physiquement (constate a l'ecran).
			if n is CollisionObject3D:
				for prod in _producteurs:
					if prod.noeud != null and is_instance_valid(prod.noeud) and prod.noeud is CollisionObject3D:
						(prod.noeud as CollisionObject3D).add_collision_exception_with(n)
			# FREEZE_MODE_KINEMATIC (pas STATIC) : sans quoi Area3D ne
			# detecte pas les collisions -- forum.godotengine.org thread
			# 79351. Les balles violettes (Area3D) doivent pouvoir toucher.
			if n is RigidBody3D:
				var rb_new: RigidBody3D = n
				rb_new.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
				rb_new.freeze = true
			cr.noeud = n
			if cr.noeud is RigidBody3D:
				_gerer_freeze_kinematic(cr.noeud, cr, d2 < _rayon_safe2)
		elif a_noeud:
			if cr.noeud is RigidBody3D:
				_gerer_freeze_kinematic(cr.noeud, cr, d2 < _rayon_safe2)
			if cr.noeud is RigidBody3D and not (cr.noeud as RigidBody3D).freeze:
				cr.position = cr.noeud.global_position

# Au degel : reset velocity obligatoire -- issue godotengine/godot#92891.
func _gerer_freeze_kinematic(rb: RigidBody3D, data: Dictionary, en_zone_safe: bool) -> void:
	var doit_freeze := true
	if en_zone_safe:
		if _sol_present_sous(rb.global_position):
			doit_freeze = false
			data.frames_sans_sol = 0
		else:
			data.frames_sans_sol += 1
			if data.frames_sans_sol >= FRAMES_SANS_SOL_MAX and _carte != null:
				if _snap_sol_via_carte(data):
					rb.global_position = data.position
					data.frames_sans_sol = 0
	else:
		data.frames_sans_sol = 0
	if rb.freeze != doit_freeze:
		if not doit_freeze:
			rb.linear_velocity = Vector3.ZERO
			rb.angular_velocity = Vector3.ZERO
		rb.freeze = doit_freeze

func _snap_sol_via_carte(cr: Dictionary) -> bool:
	var col_x: int = int(floor(cr.position.x / cote_cellule))
	var col_z: int = int(floor(cr.position.z / cote_cellule))
	for dx in [0, 1, -1]:
		for dz in [0, 1, -1]:
			var col := Vector2i(col_x + dx, col_z + dz)
			var som: Variant = _carte.sommet_max_colonne(col)
			if som == null:
				continue
			# Snap X/Z au centre de la case si on n'y est pas -- evite
			# d'etre imbrique dans un mur X/Z.
			if dx != 0 or dz != 0:
				cr.position.x = float(col.x) * cote_cellule + cote_cellule * 0.5
				cr.position.z = float(col.y) * cote_cellule + cote_cellule * 0.5
			cr.position.y = (float(int(som)) + 1.0) * cote_cellule + 0.2
			return true
	return false

func _sol_present_sous(pos: Vector3) -> bool:
	# Le manager est un Node (pas Node3D), get_world_3d n'existe pas ici.
	# Passer par _grille (Node3D) qui partage la meme World3D.
	var monde: World3D = null
	if _grille != null:
		monde = _grille.get_world_3d()
	elif get_viewport() != null:
		monde = get_viewport().find_world_3d()
	if monde == null:
		return false
	var espace := monde.direct_space_state
	if espace == null:
		return false
	var depart := pos + Vector3(0, 0.5, 0)
	var arrivee := pos + Vector3(0, -3.0, 0)
	var requete := PhysicsRayQueryParameters3D.create(depart, arrivee)
	var frappe: Dictionary = espace.intersect_ray(requete)
	return not frappe.is_empty()

func spawn_balle(pos: Vector3, direction: Vector3) -> void:
	_balles.append({
		"position": pos,
		"ancienne": pos,
		"depart": pos,
		"direction": direction.normalized(),
		"age": 0.0,
		"noeud": null,
		"morte": false,
	})

func _tick_balles(delta: float) -> void:
	var i := 0
	while i < _balles.size():
		var b = _balles[i]
		if b.morte:
			if b.noeud != null and is_instance_valid(b.noeud):
				b.noeud.queue_free()
			_balles.remove_at(i)
			continue
		b.age += delta
		if b.age >= DUREE_BALLE:
			b.morte = true
			continue
		b.ancienne = b.position
		b.position += b.direction * VITESSE_BALLE * delta
		var seg: Vector3 = b.position - b.ancienne
		var long2: float = seg.length_squared()
		if long2 <= 0.0:
			i += 1
			continue
		var loin_du_tireur: bool = ((b.position as Vector3) - (b.depart as Vector3)).length_squared() >= RAYON_EXCLUSION_TIREUR2
		if loin_du_tireur:
			var rayon2 := RAYON_HIT_CARRE * RAYON_HIT_CARRE
			var touche := false
			var pos_hit: Vector3 = b.position
			for cr in _carres:
				if cr.est_detruit:
					continue
				var vers_cr: Vector3 = (cr.position as Vector3) - b.ancienne
				var t: float = clampf(vers_cr.dot(seg) / long2, 0.0, 1.0)
				var proche: Vector3 = b.ancienne + seg * t
				var d2: float = ((cr.position as Vector3) - proche).length_squared()
				if d2 <= rayon2:
					cr.est_detruit = true
					touche = true
					pos_hit = cr.position
					break
			if not touche:
				var rayon2_en := Ennemis.RAYON_HIT_ENNEMI * Ennemis.RAYON_HIT_ENNEMI
				for e in _ennemis.ennemis():
					if e.est_mort:
						continue
					var vers_e: Vector3 = (e.position as Vector3) - b.ancienne
					var t_e: float = clampf(vers_e.dot(seg) / long2, 0.0, 1.0)
					var proche_e: Vector3 = b.ancienne + seg * t_e
					var d2_e: float = ((e.position as Vector3) - proche_e).length_squared()
					if d2_e <= rayon2_en:
						e.vie -= 1
						if e.vie <= 0:
							e.est_mort = true
						_ennemis.rafraichir_barre_ennemi(e)
						touche = true
						pos_hit = e.position
						break
			if not touche and _carte != null:
				var y_sol: Variant = _carte.sommet(b.position.x, b.position.z)
				if y_sol != null and b.position.y <= float(y_sol):
					var sol_y: float = float(y_sol)
					var cy: int = int(floor((sol_y - 0.001) / cote_cellule))
					var col := Vector2i(
						int(floor(b.position.x / cote_cellule)),
						int(floor(b.position.z / cote_cellule)))
					var cellule := Vector3i(col.x, cy, col.y)
					if _carte.item_de(cellule) == _carte.ITEM_DEFAUT and cy > _carte.couche_base:
						var x_local: float = b.position.x - float(col.x) * cote_cellule
						var z_local: float = b.position.z - float(col.y) * cote_cellule
						var ix: int = clampi(int(floor(x_local * 3.0 / cote_cellule)), 0, 2)
						var iz: int = clampi(int(floor(z_local * 3.0 / cote_cellule)), 0, 2)
						var iy: int = clampi(int(round(
							((sol_y - float(cy) * cote_cellule) * 3.0 / cote_cellule) - 1.0)), 0, 2)
						var idx: int = ix + iy * 3 + iz * 9
						var casse: bool = _carte.ajouter_pv_sous_cube(cellule, idx, 1)
						if casse:
							_effondrer_selon_materiau(cellule, idx, Vector3(b.position.x, sol_y, b.position.z))
					touche = true
					pos_hit = Vector3(b.position.x, sol_y, b.position.z)
			if touche:
				b.morte = true
				_spawn_impact(pos_hit)
				continue
		i += 1

func _repousser_carres(delta: float) -> void:
	var cote := RAYON_REPOUSSE_CARRES
	var buckets: Dictionary = {}
	for idx in range(_carres.size()):
		var cr = _carres[idx]
		if cr.est_detruit:
			continue
		var physique_active := cr.noeud != null and is_instance_valid(cr.noeud) \
			and cr.noeud is RigidBody3D and not (cr.noeud as RigidBody3D).freeze
		if physique_active:
			continue
		var cx := int(floor((cr.position as Vector3).x / cote))
		var cz := int(floor((cr.position as Vector3).z / cote))
		var cle := Vector2i(cx, cz)
		if not buckets.has(cle):
			buckets[cle] = []
		(buckets[cle] as Array).append(idx)
	var seuil2 := RAYON_REPOUSSE_CARRES * RAYON_REPOUSSE_CARRES
	var voisins_offset := [Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]
	for cle in buckets.keys():
		var ici: Array = buckets[cle]
		for i_a in range(ici.size()):
			var a = _carres[ici[i_a]]
			for j in range(i_a + 1, ici.size()):
				_appliquer_repousse(a, _carres[ici[j]], seuil2, delta)
		for off in voisins_offset:
			var voisin_cle := Vector2i(cle.x + off.x, cle.y + off.y)
			if not buckets.has(voisin_cle):
				continue
			var la: Array = buckets[voisin_cle]
			for idx_a in ici:
				var a2 = _carres[idx_a]
				for idx_b in la:
					_appliquer_repousse(a2, _carres[idx_b], seuil2, delta)

func _appliquer_repousse(a: Dictionary, b: Dictionary, seuil2: float, delta: float) -> void:
	if a.est_detruit or b.est_detruit:
		return
	var vers: Vector3 = (b.position as Vector3) - (a.position as Vector3)
	vers.y = 0.0  # push horizontal seul, gravite gere Y
	var d2: float = vers.length_squared()
	if d2 >= seuil2 or d2 <= 0.0001:
		return
	var d: float = sqrt(d2)
	var chevauchement: float = RAYON_REPOUSSE_CARRES - d
	var dir: Vector3 = vers / d
	var push: Vector3 = dir * chevauchement * FORCE_REPOUSSE * delta * 0.5
	a.position -= push
	b.position += push

func _ligne_de_vue_libre(pos_a: Vector3, pos_b: Vector3) -> bool:
	return ligne_de_vue_libre_statique(_carte, cote_cellule, pos_a, pos_b)

static func ligne_de_vue_libre_statique(carte, cote: float, pos_a: Vector3, pos_b: Vector3) -> bool:
	if carte == null:
		return true
	var pas: float = cote / 3.0
	var vect: Vector3 = pos_b - pos_a
	var dist: float = vect.length()
	if dist < 0.0001:
		return true
	var direction: Vector3 = vect / dist
	var nb_pas: int = int(ceil(dist / pas))
	# Ne teste PAS les extremites (positions des entites, pas des obstacles).
	for i in range(1, nb_pas):
		var p: Vector3 = pos_a + direction * (float(i) * pas)
		var col := Vector2i(int(floor(p.x / cote)), int(floor(p.z / cote)))
		var cy: int = int(floor(p.y / cote))
		if carte.est_pleine(col, cy):
			return false
	return true

# 0 = aucune limite (matiere sans plafond explicite dans son profil .tres).
# Reste au manager (Node) : seul lui a get_tree() pour interroger
# RessourcesTerrain. Injecte a tas.gd comme Callable fournisseur.
func _limite_hauteur_matiere(matiere: String) -> int:
	var ressources := get_tree().get_first_node_in_group(&"ressources_terrain")
	if ressources == null:
		return 0
	var profils_arr: Variant = ressources.get("profils")
	if not (profils_arr is Array):
		return 0
	for p in (profils_arr as Array):
		if p == null:
			continue
		if String(p.get("nom_item")) == matiere:
			return int(p.get("hauteur_max_sous_cubes"))
	return 0

func _effondrer_selon_materiau(cellule: Vector3i, idx_touche: int, pos_impact: Vector3) -> void:
	var matiere := _matiere_de_cellule(cellule)
	_tas.spawn_sous_cube_libre(pos_impact, matiere)
	var type_eff := _type_effondrement_de_cellule(cellule)
	if type_eff != "meuble":
		return
	var masque_restant: int = _carte.sous_cubes(cellule)
	for i in range(27):
		if i == idx_touche:
			continue
		if (masque_restant & (1 << i)) == 0:
			continue
		var ix := i % 3
		@warning_ignore("integer_division")
		var iy := (i / 3) % 3
		@warning_ignore("integer_division")
		var iz := i / 9
		var pos_i := Vector3(
			(float(cellule.x) + 0.5 + float(ix - 1) / 3.0) * cote_cellule,
			(float(cellule.y) + 0.5 + float(iy - 1) / 3.0) * cote_cellule,
			(float(cellule.z) + 0.5 + float(iz - 1) / 3.0) * cote_cellule)
		_carte.casser_sous_cube(cellule, i)
		_tas.spawn_sous_cube_libre(pos_i, matiere)

func _fabriquer_visuel_pelle() -> Node3D:
	var racine := Node3D.new()
	var manche := MeshInstance3D.new()
	var mesh_manche := BoxMesh.new()
	mesh_manche.size = Vector3(0.05, 0.7, 0.05)
	var mat_manche := StandardMaterial3D.new()
	mat_manche.albedo_color = Color(0.4, 0.25, 0.12, 1.0)
	mat_manche.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_manche.material = mat_manche
	manche.mesh = mesh_manche
	manche.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	racine.add_child(manche)
	var lame := MeshInstance3D.new()
	var mesh_lame := BoxMesh.new()
	mesh_lame.size = Vector3(0.25, 0.05, 0.15)
	var mat_lame := StandardMaterial3D.new()
	mat_lame.albedo_color = Color(0.6, 0.6, 0.65, 1.0)
	mat_lame.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_lame.material = mat_lame
	lame.mesh = mesh_lame
	lame.position = Vector3(0.0, -0.35, -0.08)
	lame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	racine.add_child(lame)
	_ajouter_collision_ramassable(racine)
	return racine

# Nomme "StaticBody3D" (nom exact) pour que _basculer_collision_cube_porte
# le desactive pendant le portage -- sans ca, le raycast creusage toucherait
# l'outil porte au lieu du terrain.
func _ajouter_collision_ramassable(visuel: Node3D) -> void:
	if visuel == null:
		return
	if visuel.get_node_or_null("StaticBody3D") != null:
		return
	var body := StaticBody3D.new()
	body.collision_layer = LAYER_RAMASSABLE
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.3, 0.8, 0.3)
	shape.shape = box
	shape.position = Vector3(0.0, -0.1, 0.0)
	body.add_child(shape)
	visuel.add_child(body)

func _spawn_pelle_initiale() -> void:
	for marqueur in get_tree().get_nodes_in_group(&"spawn_pelle"):
		if not (marqueur is Node3D):
			continue
		var pos: Vector3 = (marqueur as Node3D).global_position
		if _carte != null:
			var y_sol: Variant = _carte.sommet(pos.x, pos.z)
			if y_sol != null:
				pos.y = float(y_sol) + 0.5
		_spawn_pelle(pos)

func _spawn_pelle(pos: Vector3) -> void:
	var id_neuf: String = "pelle_%d" % _prochain_id_outil
	_prochain_id_outil += 1
	var p := {
		"id": id_neuf,
		"position": pos,
		"vitesse_y": 0.0,
		"noeud": null,
		"matiere": "pelle",
	}
	_tas.monde().ajouter(p, "pelle", pos)

func _objet_ramassable_sous_viseur(portee: float) -> Dictionary:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return {}
	var taille := get_viewport().get_visible_rect().size
	var centre := taille * 0.5
	var origine := camera.project_ray_origin(centre)
	var direction := camera.project_ray_normal(centre)
	var espace := get_viewport().get_world_3d().direct_space_state
	var requete := PhysicsRayQueryParameters3D.create(origine, origine + direction * portee)
	requete.collision_mask = LAYER_RAMASSABLE
	if _observateur != null and _observateur is CollisionObject3D:
		requete.exclude = [(_observateur as CollisionObject3D).get_rid()]
	var frappe := espace.intersect_ray(requete)
	if frappe.is_empty():
		return {}
	var collider = frappe.get("collider")
	if collider == null or not (collider is Node):
		return {}
	# Le collider (StaticBody3D) est enfant du visuel composite = le noeud
	# stocke dans l'entree du monde des tas. Remonte au parent pour le comparer.
	var racine := (collider as Node).get_parent()
	if racine == null:
		return {}
	if _observateur == null:
		return {}
	# Le collider (StaticBody3D) est enfant du visuel composite = le noeud
	# stocke dans l'entree du monde des tas. Remonte au parent pour le comparer.
	var proches: Array = _tas.monde().choses_dans_rayon(_observateur.global_position, RAYON_PRENDRE_METRES * 2.0)
	for e in proches:
		var sc: Dictionary = e.chose
		if sc.get("noeud", null) == racine:
			return sc
	return {}

# Pose ne concerne que les outils (pelle/beche) : un cube libre porte garde son
# chemin dedie au clic gauche pour ne pas casser tas.index_ajouter.
func toggle_prendre_poser_e(origine: Vector3, direction: Vector3) -> bool:
	var mat_portee: String = String(_cube_porte.get("matiere", "")) if not _cube_porte.is_empty() else ""
	if mat_portee == "pelle" or mat_portee == "beche":
		if _observateur == null:
			return false
		var pos_pose: Vector3 = origine + direction.normalized() * 1.5
		if _carte != null:
			var y_sol: Variant = _carte.sommet(pos_pose.x, pos_pose.z)
			if y_sol != null:
				pos_pose.y = float(y_sol) + 0.5
		_basculer_collision_cube_porte(true)
		_cube_porte.position = pos_pose
		_tas.monde().ajouter(_cube_porte, mat_portee, pos_pose)
		if _cube_porte.noeud != null and is_instance_valid(_cube_porte.noeud):
			(_cube_porte.noeud as Node3D).global_position = pos_pose
		_cube_porte = {}
		return true
	if not _cube_porte.is_empty():
		return false
	var cible := _objet_ramassable_sous_viseur(RAYON_PRENDRE_METRES)
	if cible.is_empty():
		return false
	_tas.monde().retirer(cible.id)
	_cube_porte = cible
	_basculer_collision_cube_porte(false)
	return true

# SPECIFIQUE JOUEUR : depend de terrain_visible autour de l'observateur --
# inutilisable pour un acteur hors streaming.
func _sous_cube_sous_viseur(portee: float) -> Dictionary:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return {}
	var taille := get_viewport().get_visible_rect().size
	var centre := taille * 0.5
	var origine := camera.project_ray_origin(centre)
	var direction := camera.project_ray_normal(centre)
	var espace := get_viewport().get_world_3d().direct_space_state
	var requete := PhysicsRayQueryParameters3D.create(origine, origine + direction * portee)
	# Exclure la capsule du joueur : sans exclusion, le raycast plonge dedans
	# quand on regarde vers le bas et rate le sol.
	if _observateur != null and _observateur is CollisionObject3D:
		requete.exclude = [(_observateur as CollisionObject3D).get_rid()]
	var frappe := espace.intersect_ray(requete)
	if frappe.is_empty():
		return {}
	# NE PAS filtrer sur `frappe.collider is GridMap` : les cellules entamees
	# ont leur collision refaite en StaticBody3D+BoxShape3D par terrain_visible.
	var point: Vector3 = (frappe.position as Vector3) - (frappe.normal as Vector3) * 0.01
	var cy: int = int(floor(point.y / cote_cellule))
	var col := Vector2i(
		int(floor(point.x / cote_cellule)),
		int(floor(point.z / cote_cellule)))
	var cellule := Vector3i(col.x, cy, col.y)
	var x_local: float = point.x - float(col.x) * cote_cellule
	var y_local: float = point.y - float(cy) * cote_cellule
	var z_local: float = point.z - float(col.y) * cote_cellule
	var ix: int = clampi(int(floor(x_local * 3.0 / cote_cellule)), 0, 2)
	var iy: int = clampi(int(floor(y_local * 3.0 / cote_cellule)), 0, 2)
	var iz: int = clampi(int(floor(z_local * 3.0 / cote_cellule)), 0, 2)
	var idx: int = ix + iy * 3 + iz * 9
	return {"cellule": cellule, "idx": idx, "point": point, "normal": frappe.normal}

func _creer_halo_pose() -> void:
	if _halo_pose != null:
		return
	var cote_sous: float = cote_cellule / 3.0
	var box := BoxMesh.new()
	box.size = Vector3(cote_sous, cote_sous, cote_sous) * 1.02
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.2, 1.0, 0.3, 0.35)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	box.material = mat
	_halo_pose = MeshInstance3D.new()
	_halo_pose.mesh = box
	_halo_pose.top_level = true
	_halo_pose.visible = false
	_halo_pose.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_halo_pose)

func _maj_halo_pose() -> void:
	if _halo_pose == null:
		return
	if not porteur_a_cube() or porte_pelle():
		if _halo_pose.visible:
			_halo_pose.visible = false
		return
	var cible := _sous_cube_sous_viseur(PORTEE_PELLE_METRES)
	if cible.is_empty():
		if _halo_pose.visible:
			_halo_pose.visible = false
		return
	# Offset regard pour eloigner du joueur -- sinon viser les pieds fait
	# apparaitre le halo pile sur soi.
	var point: Vector3 = cible["point"]
	var normale: Vector3 = cible["normal"]
	var cote_sous: float = cote_cellule / 3.0
	var centre_pose := point + normale * (cote_sous * 0.5)
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		var dir_regard: Vector3 = -camera.global_transform.basis.z
		centre_pose += dir_regard.normalized() * (cote_cellule * 0.5)
	centre_pose.x = floor(centre_pose.x / cote_sous) * cote_sous + cote_sous * 0.5
	centre_pose.y = floor(centre_pose.y / cote_sous) * cote_sous + cote_sous * 0.5
	centre_pose.z = floor(centre_pose.z / cote_sous) * cote_sous + cote_sous * 0.5
	_halo_pose.global_position = centre_pose
	if not _halo_pose.visible:
		_halo_pose.visible = true

func _creer_halo_pelle() -> void:
	if _halo_pelle != null:
		return
	var cote_sous: float = cote_cellule / 3.0
	var box := BoxMesh.new()
	box.size = Vector3(cote_sous, cote_sous, cote_sous) * 1.02
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.9, 0.15, 0.35)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	box.material = mat
	_halo_pelle = MeshInstance3D.new()
	_halo_pelle.mesh = box
	_halo_pelle.top_level = true
	_halo_pelle.visible = false
	_halo_pelle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_halo_pelle)

func _maj_halo_pelle() -> void:
	if _halo_pelle == null:
		return
	if not porte_pelle():
		if _halo_pelle.visible:
			_halo_pelle.visible = false
		return
	var cible := _sous_cube_sous_viseur(PORTEE_PELLE_METRES)
	if cible.is_empty():
		if _halo_pelle.visible:
			_halo_pelle.visible = false
		return
	var cellule: Vector3i = cible["cellule"]
	var idx: int = cible["idx"]
	var ix: int = idx % 3
	@warning_ignore("integer_division")
	var iy: int = (idx / 3) % 3
	@warning_ignore("integer_division")
	var iz: int = idx / 9
	var cote_sous: float = cote_cellule / 3.0
	var centre := Vector3(
		float(cellule.x) * cote_cellule + (float(ix) + 0.5) * cote_sous,
		float(cellule.y) * cote_cellule + (float(iy) + 0.5) * cote_sous,
		float(cellule.z) * cote_cellule + (float(iz) + 0.5) * cote_sous)
	_halo_pelle.global_position = centre
	if not _halo_pelle.visible:
		_halo_pelle.visible = true

func creuser_avec_pelle(_origine: Vector3, _direction: Vector3) -> bool:
	if _cube_porte.is_empty() or _cube_porte.get("matiere", "") != "pelle":
		return false
	if _carte == null:
		return false
	var cible := _sous_cube_sous_viseur(PORTEE_PELLE_METRES)
	if cible.is_empty():
		return false
	var cellule: Vector3i = cible["cellule"]
	var idx: int = cible["idx"]
	if not _carte.est_pleine(Vector2i(cellule.x, cellule.z), cellule.y):
		return false
	if _carte.item_de(cellule) != _carte.ITEM_DEFAUT:
		return false
	if cellule.y <= _carte.couche_base:
		return false
	var casse: bool = _carte.ajouter_pv_sous_cube(cellule, idx, PV_PELLE_PAR_COUP)
	if casse:
		_effondrer_selon_materiau(cellule, idx, cible["point"])
	if _observateur != null and _observateur.has_method("depenser_pour_travail"):
		_observateur.call("depenser_pour_travail", COUT_CREUSER_PAR_COUP)
	return true

func porteur_a_cube() -> bool:
	return not _cube_porte.is_empty()

func porte_pelle() -> bool:
	return not _cube_porte.is_empty() and _cube_porte.get("matiere", "") == "pelle"

func _fabriquer_visuel_beche() -> Node3D:
	var racine := Node3D.new()
	var mat_bois := StandardMaterial3D.new()
	mat_bois.albedo_color = Color(0.4, 0.25, 0.12, 1.0)
	mat_bois.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mat_fer := StandardMaterial3D.new()
	mat_fer.albedo_color = Color(0.55, 0.55, 0.6, 1.0)
	mat_fer.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var manche := MeshInstance3D.new()
	var mesh_manche := BoxMesh.new()
	mesh_manche.size = Vector3(0.04, 0.6, 0.04)
	mesh_manche.material = mat_bois
	manche.mesh = mesh_manche
	manche.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	racine.add_child(manche)
	var poignee := MeshInstance3D.new()
	var mesh_poignee := BoxMesh.new()
	mesh_poignee.size = Vector3(0.20, 0.04, 0.04)
	mesh_poignee.material = mat_bois
	poignee.mesh = mesh_poignee
	poignee.position = Vector3(0.0, 0.31, 0.0)
	poignee.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	racine.add_child(poignee)
	var lame := MeshInstance3D.new()
	var mesh_lame := BoxMesh.new()
	mesh_lame.size = Vector3(0.20, 0.28, 0.02)
	mesh_lame.material = mat_fer
	lame.mesh = mesh_lame
	lame.position = Vector3(0.0, -0.44, 0.0)
	lame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	racine.add_child(lame)
	_ajouter_collision_ramassable(racine)
	return racine

func _spawn_beche_initiale() -> void:
	for marqueur in get_tree().get_nodes_in_group(&"spawn_beche"):
		if not (marqueur is Node3D):
			continue
		var pos: Vector3 = (marqueur as Node3D).global_position
		if _carte != null:
			var y_sol: Variant = _carte.sommet(pos.x, pos.z)
			if y_sol != null:
				pos.y = float(y_sol) + 0.5
		_spawn_beche(pos)

func _spawn_beche(pos: Vector3) -> void:
	var id_neuf: String = "beche_%d" % _prochain_id_outil
	_prochain_id_outil += 1
	var b := {
		"id": id_neuf,
		"position": pos,
		"vitesse_y": 0.0,
		"noeud": null,
		"matiere": "beche",
	}
	_tas.monde().ajouter(b, "beche", pos)

func becher_avec_beche(_origine: Vector3, _direction: Vector3) -> bool:
	if _cube_porte.is_empty() or _cube_porte.get("matiere", "") != "beche":
		return false
	if _carte == null:
		return false
	var cible := _sous_cube_sous_viseur(PORTEE_BECHE_METRES)
	if cible.is_empty():
		return false
	var cellule: Vector3i = cible["cellule"]
	if not _carte.est_pleine(Vector2i(cellule.x, cellule.z), cellule.y):
		return false
	if _carte.item_de(cellule) != _carte.ITEM_DEFAUT:
		return false
	if cellule.y <= _carte.couche_base:
		return false
	var seuil_atteint: bool = _carte.ajouter_coups_beche(cellule, 1)
	if seuil_atteint and _index_bloc_beche >= 0:
		_carte.poser_cellule(cellule, _index_bloc_beche, 0)
		# Une cellule creee en jeu doit etre inscrite explicitement -- la table
		# des ressources ne scanne qu'au _ready.
		var ressources := get_tree().get_first_node_in_group(&"ressources_terrain")
		if ressources != null and ressources.has_method("inscrire_cellule"):
			ressources.call("inscrire_cellule", cellule)
	if _observateur != null and _observateur.has_method("depenser_pour_travail"):
		_observateur.call("depenser_pour_travail", COUT_BECHER_PAR_COUP)
	return true

func _creer_halo_beche() -> void:
	if _halo_beche != null:
		return
	var cote_sous: float = cote_cellule / 3.0
	var box := BoxMesh.new()
	box.size = Vector3(cote_sous, cote_sous, cote_sous) * 1.02
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.6, 0.4, 0.15, 0.35)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	box.material = mat
	_halo_beche = MeshInstance3D.new()
	_halo_beche.mesh = box
	_halo_beche.top_level = true
	_halo_beche.visible = false
	_halo_beche.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_halo_beche)

func _maj_halo_beche() -> void:
	if _halo_beche == null:
		return
	if not porte_beche():
		if _halo_beche.visible:
			_halo_beche.visible = false
		return
	var cible := _sous_cube_sous_viseur(PORTEE_BECHE_METRES)
	if cible.is_empty():
		if _halo_beche.visible:
			_halo_beche.visible = false
		return
	var cellule: Vector3i = cible["cellule"]
	var idx: int = cible["idx"]
	var ix: int = idx % 3
	@warning_ignore("integer_division")
	var iy: int = (idx / 3) % 3
	@warning_ignore("integer_division")
	var iz: int = idx / 9
	var cote_sous: float = cote_cellule / 3.0
	var centre := Vector3(
		float(cellule.x) * cote_cellule + (float(ix) + 0.5) * cote_sous,
		float(cellule.y) * cote_cellule + (float(iy) + 0.5) * cote_sous,
		float(cellule.z) * cote_cellule + (float(iz) + 0.5) * cote_sous)
	_halo_beche.global_position = centre
	if not _halo_beche.visible:
		_halo_beche.visible = true

func porte_beche() -> bool:
	return not _cube_porte.is_empty() and _cube_porte.get("matiere", "") == "beche"

func porteur_prendre_si_proche(_origine: Vector3, _direction: Vector3) -> bool:
	if not _cube_porte.is_empty():
		return false
	var cible := _sous_cube_sous_viseur(PORTEE_PELLE_METRES)
	if cible.is_empty():
		return false
	var point: Vector3 = cible["point"]
	var cote_sous: float = cote_cellule / 3.0
	var tolerance2: float = cote_sous * cote_sous
	var meilleur = null
	var meilleur_d2: float = tolerance2
	for w in _tas.monde().choses.values():
		var sc: Dictionary = w.chose
		if sc.get("matiere", "") == "pelle" or sc.get("matiere", "") == "beche":
			continue
		var d2: float = (sc.position as Vector3).distance_squared_to(point)
		if d2 < meilleur_d2:
			meilleur_d2 = d2
			meilleur = sc
	if meilleur == null:
		return false
	# Retire du monde (indice spatial) mais GARDE le noeud pour le portage.
	_tas.index_retirer(meilleur)
	_tas.monde().retirer(meilleur.id)
	_cube_porte = meilleur
	# S'il n'a pas de noeud (etait hors rayon rendu), on en fabrique un.
	if _cube_porte.noeud == null or not is_instance_valid(_cube_porte.noeud):
		var parent := get_parent()
		if parent != null:
			var n := MeshInstance3D.new()
			n.mesh = _tas.mesh_pour_matiere(_cube_porte.get("matiere", "terre"))
			n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_tas.ajouter_collision_cube_libre(n)
			parent.add_child(n)
			_cube_porte.noeud = n
	# Cube en main : collision desactivee pour ne pas bloquer le joueur.
	_basculer_collision_cube_porte(false)
	return true

# Pose le cube porte a la position pointee par le viseur, snappe a la grille
# 3x3x3. Etape 1 : reste sous-cube libre (pas de reformation). Le cube est
# reinjecte dans le monde des tas a sa nouvelle position.
func porteur_poser() -> bool:
	if _cube_porte.is_empty():
		return false
	if _observateur == null:
		return false
	# PATRON MINECRAFT : le sous-cube apparait dans la CELLULE ADJACENTE a la
	# face visee par le raycast. Aucune gravite, aucune recherche de sol --
	# le sous-cube reste IMMOBILE la ou on l'a pose. Distinct de creuser
	# (ou le sous-cube tombe par gravite data).
	var cible_ray := _sous_cube_sous_viseur(PORTEE_PELLE_METRES)
	var pas: float = cote_cellule / 3.0
	var cible: Vector3
	if cible_ray.is_empty():
		# Rien vise -> repli : devant le joueur, au sol (comportement de
		# secours, pas ideal mais evite la perte du cube porte).
		var pos_obs: Vector3 = _observateur.global_position
		var yeux := _observateur.get_node_or_null("Yeux")
		var dir: Vector3 = Vector3(0.0, 0.0, -1.0)
		if yeux != null:
			dir = -(yeux as Node3D).global_transform.basis.z
		cible = pos_obs + dir.normalized() * 2.0
		if _carte != null:
			var y_sol_fallback: Variant = _carte.sommet(cible.x, cible.z)
			if y_sol_fallback != null:
				cible.y = float(y_sol_fallback) + pas * 0.5
		cible.x = floor(cible.x / pas) * pas + pas * 0.5
		cible.z = floor(cible.z / pas) * pas + pas * 0.5
	else:
		# Cible = point d'impact decale d'un DEMI sous-cube dans la direction
		# de la normale = centre du sous-cube adjacent a la face touchee.
		# Puis OFFSET regard (1 cellule) -- doit matcher _maj_halo_pose.
		var point: Vector3 = cible_ray["point"]
		var normale: Vector3 = cible_ray["normal"]
		cible = point + normale * (pas * 0.5)
		var camera := get_viewport().get_camera_3d()
		if camera != null:
			var dir_regard: Vector3 = -camera.global_transform.basis.z
			cible += dir_regard.normalized() * (cote_cellule * 0.5)
		# Snap sur grille sous-cube (centre de case).
		cible.x = floor(cible.x / pas) * pas + pas * 0.5
		cible.y = floor(cible.y / pas) * pas + pas * 0.5
		cible.z = floor(cible.z / pas) * pas + pas * 0.5
	# PAS de flag immobile : contrairement a Minecraft, un sous-cube pose sans
	# support tombe. La physique s'applique APRES la pose. Le geste de pose est
	# juste rendu previsible (raycast + face), la stabilite se decide ensuite.
	_cube_porte.position = cible
	_tas.monde().ajouter(_cube_porte, "sous_cube", cible)
	_tas.index_ajouter(_cube_porte)
	if _cube_porte.noeud != null and is_instance_valid(_cube_porte.noeud):
		(_cube_porte.noeud as Node3D).global_position = cible
	_basculer_collision_cube_porte(true)
	_cube_porte = {}
	return true

# Chaque frame : si un cube est porte, son noeud suit le joueur (devant les
# yeux, position OFFSET_PORTAGE dans le repere du perso).
func _sync_cube_porte() -> void:
	if _cube_porte.is_empty() or _observateur == null:
		return
	if _cube_porte.noeud == null or not is_instance_valid(_cube_porte.noeud):
		return
	var yeux := _observateur.get_node_or_null("Yeux") as Node3D
	var origine: Vector3 = yeux.global_position if yeux != null else _observateur.global_position
	# Basis des YEUX (inclut le tangage) pour suivre la vue : haut/bas
	# aussi, pas seulement le lacet du corps.
	var base: Basis = yeux.global_transform.basis if yeux != null else _observateur.global_transform.basis
	var pos_portage: Vector3 = origine + base * OFFSET_PORTAGE
	(_cube_porte.noeud as Node3D).global_position = pos_portage
	_cube_porte.position = pos_portage

# MANGER un bloc bleu directement au clic gauche (sans passer par
# l'inspecteur). Test data : cellule pile devant le joueur a courte distance
# (2 m). Si l'item est un bloc_bleu profile -> preleve 1 unite + nourrit 1.5.
# Rend true si le repas a eu lieu.
func manger_si_bloc_bleu_proche(origine: Vector3, direction: Vector3) -> bool:
	if _carte == null:
		return false
	var pos_cible: Vector3 = origine + direction.normalized() * 2.0
	var cx: int = int(floor(pos_cible.x / cote_cellule))
	var cy: int = int(floor(pos_cible.y / cote_cellule))
	var cz: int = int(floor(pos_cible.z / cote_cellule))
	var col := Vector2i(cx, cz)
	if not _carte.est_pleine(col, cy):
		return false
	var cellule := Vector3i(cx, cy, cz)
	var ressources := get_tree().get_first_node_in_group(&"ressources_terrain")
	if ressources == null or not ressources.has_method("profil_de_cellule"):
		return false
	var profil = ressources.call("profil_de_cellule", cellule)
	if profil == null or String(profil.nom_item) != "bloc_bleu":
		return false
	var pris: float = float(ressources.call("preleve", cellule, 1.0))
	if pris <= 0.0:
		return false
	if _observateur != null and _observateur.has_method("nourrir"):
		_observateur.call("nourrir", 15.0)
	return true

# HELPERS PROFIL. Interrogent RessourcesTerrain (framework) pour connaitre
# le materiau et le type d'effondrement du bloc de cette cellule.
func _matiere_de_cellule(cellule: Vector3i) -> String:
	var ressources := get_tree().get_first_node_in_group(&"ressources_terrain")
	if ressources == null or not ressources.has_method("profil_de_cellule"):
		return "terre"
	var profil = ressources.call("profil_de_cellule", cellule)
	if profil == null:
		return "terre"
	return String(profil.nom_item)

func _type_effondrement_de_cellule(cellule: Vector3i) -> String:
	var ressources := get_tree().get_first_node_in_group(&"ressources_terrain")
	if ressources == null or not ressources.has_method("profil_de_cellule"):
		return "structurel"
	var profil = ressources.call("profil_de_cellule", cellule)
	if profil == null:
		return "structurel"
	return String(profil.get("type_effondrement"))

func _basculer_collision_cube_porte(active: bool) -> void:
	if _cube_porte.is_empty() or _cube_porte.get("noeud", null) == null:
		return
	var visuel: Node3D = _cube_porte.noeud
	if not is_instance_valid(visuel):
		return
	var body := visuel.get_node_or_null("StaticBody3D") as StaticBody3D
	if body == null:
		return
	var shape := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape != null:
		shape.disabled = not active

func _bascule_rendu_tas() -> void:
	if _observateur == null:
		return
	var pos_obs: Vector3 = _observateur.global_position
	var parent := get_parent()
	if parent == null:
		return
	# Hysteresis : premiere passe sur rayon_rendu_entrer -> creer et mettre a jour
	# les proches ; deuxieme passe sur toutes les choses -> liberer ce qui a un
	# noeud mais distance carree > r2_sortir. L'ecart evite le flip-flop.
	var r2_sortir := rayon_rendu_sortir * rayon_rendu_sortir
	var proches: Array = _tas.monde().choses_dans_rayon(pos_obs, rayon_rendu_entrer)
	var ids_proches: Dictionary = {}
	for entree in proches:
		var t: Dictionary = entree.chose
		ids_proches[t.id] = true
		if t.noeud == null or not is_instance_valid(t.noeud):
			var n: Node3D
			if t.get("matiere", "") == "pelle":
				n = _fabriquer_visuel_pelle()
			elif t.get("matiere", "") == "beche":
				n = _fabriquer_visuel_beche()
			else:
				var mi := MeshInstance3D.new()
				mi.mesh = _tas.mesh_pour_matiere(t.get("matiere", "terre"))
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				_tas.ajouter_collision_cube_libre(mi)
				n = mi
			parent.add_child(n)
			n.global_position = t.position
			t.noeud = n
		else:
			(t.noeud as Node3D).global_position = t.position
	for w in _tas.monde().choses.values():
		var tas: Dictionary = w.chose
		if ids_proches.has(tas.id):
			continue
		if tas.noeud == null or not is_instance_valid(tas.noeud):
			continue
		# Deja hors du rayon_entrer (sinon serait dans ids_proches) : ne liberer que
		# si aussi au-dela du rayon_sortir. Sinon on garde le noeud (bande morte).
		var d2: float = ((tas.position as Vector3) - pos_obs).length_squared()
		if d2 > r2_sortir:
			tas.noeud.queue_free()
			tas.noeud = null

func _spawn_impact(pos: Vector3) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var n := Node3D.new()
	n.name = "ImpactBalle"
	parent.add_child(n)
	n.global_position = pos
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.25
	sphere.height = 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.4, 1.0, 0.7)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.4, 1.0)
	mat.emission_energy_multiplier = 2.0
	sphere.material = mat
	mesh.mesh = sphere
	n.add_child(mesh)
	_impacts.append({"noeud": n, "age": 0.0})

func _ticker_impacts(delta: float) -> void:
	var i := 0
	while i < _impacts.size():
		var imp = _impacts[i]
		imp.age += delta
		if imp.age >= DUREE_IMPACT:
			if imp.noeud != null and is_instance_valid(imp.noeud):
				imp.noeud.queue_free()
			_impacts.remove_at(i)
			continue
		# Fade + shrink lineaire.
		if imp.noeud != null and is_instance_valid(imp.noeud):
			var t: float = 1.0 - (imp.age / DUREE_IMPACT)
			imp.noeud.scale = Vector3.ONE * (0.5 + t)
		i += 1

func _bascule_rendu_balles() -> void:
	if _observateur == null:
		return
	var pos_obs: Vector3 = _observateur.global_position
	var parent := get_parent()
	if parent == null:
		return
	# Balles : hysteresis serree (1m) -- projectiles rapides, on ne veut pas garder
	# le visuel apres leur sortie effective.
	var r2_entrer := rayon_rendu_balles_entrer * rayon_rendu_balles_entrer
	var r2_sortir := rayon_rendu_balles_sortir * rayon_rendu_balles_sortir
	for b in _balles:
		var d2: float = ((b.position as Vector3) - pos_obs).length_squared()
		var a_noeud: bool = b.noeud != null and is_instance_valid(b.noeud)
		if a_noeud and d2 > r2_sortir:
			b.noeud.queue_free()
			b.noeud = null
		elif not a_noeud and d2 < r2_entrer:
			var n := BalleScene.instantiate() as Node3D
			# Neutralise le script projectile.gd embarque dans le tscn --
			# la balle devient une coque visuelle pilotee par le manager.
			n.set_script(null)
			parent.add_child(n)
			b.noeud = n
			b.noeud.global_position = b.position
		elif a_noeud:
			b.noeud.global_position = b.position

# --- ENNEMIS ---

func _preparer_meshes_ennemis() -> void:
	_mesh_ennemi = BoxMesh.new()
	_mesh_ennemi.size = Vector3(0.8, 0.8, 0.8)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.15, 0.15)
	_mesh_ennemi.material = mat
	_mesh_barre = PlaneMesh.new()
	_mesh_barre.size = Vector2(0.6, 0.08)
	# Orientation FACE_Z : vertices dans le plan XY (normal +Z), pas XZ (defaut
	# FACE_Y). Le shader BarreVieShader billboarde en remplacant MODELVIEW par
	# VIEW * (right, up, back, pos). Un PlaneMesh horizontal (FACE_Y) donne apres
	# billboarding un plan (right, back) qui contient l'axe camera_back --> vu en
	# tranche, 0 pixel, shimmer et AABB degenere. FACE_Z donne un plan (right, up)
	# perpendiculaire a la camera, face a face.
	_mesh_barre.orientation = PlaneMesh.FACE_Z

func _set_spawn_demi_cote(v: float) -> void:
	spawn_demi_cote = v
	_rafraichir_zone_spawn()

func _rafraichir_zone_spawn() -> void:
	# Re-recherchee a chaque appel : le setter peut tirer avant _ready.
	var noeud := get_node_or_null("ZoneSpawn")
	if noeud == null:
		return
	var mi := noeud as MeshInstance3D
	if mi == null or not (mi.mesh is BoxMesh):
		return
	(mi.mesh as BoxMesh).size = Vector3(spawn_demi_cote * 2.0, 0.4, spawn_demi_cote * 2.0)

func _bascule_rendu_ennemis() -> void:
	if _observateur == null:
		return
	var pos_obs: Vector3 = _observateur.global_position
	var parent := get_parent()
	if parent == null:
		return
	var r2_entrer := rayon_rendu_entrer * rayon_rendu_entrer
	var r2_sortir := rayon_rendu_sortir * rayon_rendu_sortir
	for e in _ennemis.ennemis():
		if e.est_mort:
			if e.noeud != null and is_instance_valid(e.noeud):
				(e.noeud as Node3D).global_position = e.position
			continue
		var d2: float = ((e.position as Vector3) - pos_obs).length_squared()
		var a_noeud: bool = e.noeud != null and is_instance_valid(e.noeud)
		if a_noeud and d2 > r2_sortir:
			print("[ENNEMI SORT] id=%s d=%.2f entrer=%.2f sortir=%.2f pos_e=%s pos_obs=%s" % [
				e.get("id", "?"), sqrt(d2), rayon_rendu_entrer, rayon_rendu_sortir,
				e.position, pos_obs])
			e.noeud.queue_free()
			e.noeud = null
		elif not a_noeud and d2 < r2_entrer:
			var n := _creer_visuel_ennemi(
				float(e.vie) / float(vie_ennemi),
				float(e.nourriture) / Ennemis.NOURRITURE_MAX_ENNEMI)
			print("[ENNEMI ENTRE] id=%s d=%.2f entrer=%.2f sortir=%.2f pos_e=%s pos_obs=%s" % [
				e.get("id", "?"), sqrt(d2), rayon_rendu_entrer, rayon_rendu_sortir,
				e.position, pos_obs])
			parent.add_child(n)
			n.global_position = e.position
			e.noeud = n
		elif a_noeud:
			(e.noeud as Node3D).global_position = e.position

func _creer_visuel_ennemi(fraction_vie: float, fraction_nourriture: float) -> StaticBody3D:
	var racine := StaticBody3D.new()
	var cube := MeshInstance3D.new()
	cube.mesh = _mesh_ennemi
	cube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	racine.add_child(cube)
	var barre := MeshInstance3D.new()
	barre.mesh = _mesh_barre
	barre.position = Vector3(0.0, 1.0, 0.0)
	barre.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var smat := ShaderMaterial.new()
	smat.shader = BarreVieShader
	smat.set_shader_parameter("fraction", fraction_vie)
	barre.set_surface_override_material(0, smat)
	racine.add_child(barre)
	# child(2) : collision
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 0.8, 0.8)
	shape.shape = box
	racine.add_child(shape)
	# child(3) : barre de nourriture (bleue, empilee au-dessus)
	var barre_n := MeshInstance3D.new()
	barre_n.mesh = _mesh_barre
	barre_n.position = Vector3(0.0, 1.15, 0.0)
	barre_n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var smat_n := ShaderMaterial.new()
	smat_n.shader = BarreVieShader
	smat_n.set_shader_parameter("fraction", fraction_nourriture)
	smat_n.set_shader_parameter("couleur_pleine", Color(0.2, 0.5, 0.95, 1.0))
	barre_n.set_surface_override_material(0, smat_n)
	racine.add_child(barre_n)
	return racine

# CORPS-A-CORPS : delegue au module ennemis, ou vit la logique de hit.
func frapper_melee(origine: Vector3, direction: Vector3, portee: float, degat: int) -> bool:
	return _ennemis.frapper_melee(origine, direction, portee, degat)

# BARRE DE VIE JOUEUR (HUD 2D). Fabrique par code -- pas de TSCN. Ancree en bas
# au centre. Deux ColorRect : un fond sombre, un "remplissage" rouge dont la
# taille suit le ratio pv/max.
func _preparer_hud_pv() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)
	_hud_barre_fond = ColorRect.new()
	_hud_barre_fond.color = Color(0.1, 0.03, 0.03, 0.85)
	_hud_barre_fond.anchor_left = 0.5
	_hud_barre_fond.anchor_right = 0.5
	_hud_barre_fond.anchor_top = 1.0
	_hud_barre_fond.anchor_bottom = 1.0
	_hud_barre_fond.offset_left = -200
	_hud_barre_fond.offset_right = 200
	_hud_barre_fond.offset_top = -50
	_hud_barre_fond.offset_bottom = -20
	canvas.add_child(_hud_barre_fond)
	_hud_barre_pv = ColorRect.new()
	_hud_barre_pv.color = Color(0.85, 0.15, 0.15, 1.0)
	_hud_barre_pv.anchor_left = 0.0
	_hud_barre_pv.anchor_top = 0.0
	_hud_barre_pv.anchor_right = 1.0
	_hud_barre_pv.anchor_bottom = 1.0
	_hud_barre_pv.offset_left = 3
	_hud_barre_pv.offset_top = 3
	_hud_barre_pv.offset_right = -3
	_hud_barre_pv.offset_bottom = -3
	_hud_barre_fond.add_child(_hud_barre_pv)
	_rafraichir_hud_pv()

func _rafraichir_hud_pv() -> void:
	if _hud_barre_pv == null:
		return
	var ratio: float = clampf(_pv_joueur / PV_JOUEUR_MAX, 0.0, 1.0)
	# La largeur suit le ratio via anchor_right : 1.0 = pleine, 0.0 = vide.
	_hud_barre_pv.anchor_right = ratio

# Tick des degats de contact carre rouge -- joueur. Rayon fixe autour du
# joueur, chaque carre en contact draine des PV/s. Au passage a 0, la sim
# est mise en pause (get_tree().paused = true). Ne modifie plus rien apres.
func _tick_pv_joueur(delta: float) -> void:
	if _observateur == null:
		return
	if _pv_joueur <= 0.0:
		return
	var pos_j: Vector3 = _observateur.global_position
	var r2 := RAYON_CONTACT_CARRE_JOUEUR * RAYON_CONTACT_CARRE_JOUEUR
	var subit := 0.0
	for e in _ennemis.ennemis():
		if e.est_mort:
			continue
		# Test CYLINDRIQUE : horizontal 0.8m ET vertical < 1.5m. Un joueur
		# perche 3m plus haut est immunise.
		var pos_e: Vector3 = e.position
		var dh: Vector3 = pos_e - pos_j
		dh.y = 0.0
		if dh.length_squared() >= r2:
			continue
		if absf(pos_e.y - pos_j.y) >= 1.5:
			continue
		subit += DEGAT_CARRE_PAR_S * delta
	if subit <= 0.0:
		return
	_pv_joueur = max(0.0, _pv_joueur - subit)
	_rafraichir_hud_pv()
	if _pv_joueur <= 0.0:
		get_tree().paused = true

# API PUBLIQUE : retirer des PV au joueur (appelee par le personnage sous
# inanition). Meme traitement que le contact ennemi : baisse, rafraichit
# la barre, pause a zero.
func retirer_pv_joueur(quantite: float) -> void:
	if _pv_joueur <= 0.0:
		return
	_pv_joueur = max(0.0, _pv_joueur - quantite)
	_rafraichir_hud_pv()
	if _pv_joueur <= 0.0:
		get_tree().paused = true
