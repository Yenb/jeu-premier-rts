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

@export var rayon_rendu: float = 60.0
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
# FRAMES SANS SOL AVANT SNAP LOGIQUE : le terrain_visible cook les
# cellules sur ~7 frames (voir terrain_visible.gd:67-77). 14 frames
# (~0.23s a 60fps) = deux cycles de chargement complets. Au-dela, on
# snap au sol via carte_terrain (donnee), independant de la physique.
const FRAMES_SANS_SOL_MAX := 14
# MARGE SOUS LE RAYON TERRAIN GARANTI : le terrain streame a un rayon
# reel garanti = rayon_cellules - pas_de_rafraichissement (voir
# terrain_visible.gd:62-65). MARGE_SAFE ajoute une marge supplementaire
# contre le chargement etale sur plusieurs frames (terrain_visible.gd:67).
const MARGE_SAFE := 4.0
# Fallback si _grille absent au _ready. Recalcule au _ready si _grille
# present : _rayon_safe = (rayon_cellules - pas_de_rafraichissement) * cote - MARGE_SAFE
var _rayon_safe: float = 20.0
var _rayon_safe2: float = 400.0  # au carre (pour comparaison distance2)

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
	# RAYON SAFE DYNAMIQUE : lu depuis _grille.rayon_cellules pour eviter
	# dependance a une constante figee. Si rayon_cellules du terrain change
	# un jour (config, biome), _rayon_safe s'ajuste automatiquement.
	if _grille != null and _carte != null:
		var rayon_cellules_terrain: int = _grille.get("rayon_cellules") if "rayon_cellules" in _grille else 15
		var pas: int = _grille.get("pas_de_rafraichissement") if "pas_de_rafraichissement" in _grille else 4
		var cote: float = _carte.get("cote") if "cote" in _carte else 2.0
		_rayon_safe = max(0.0, float(rayon_cellules_terrain - pas) * cote - MARGE_SAFE)
		_rayon_safe2 = _rayon_safe * _rayon_safe
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
			# FRAMES_SANS_SOL : compte les frames zone-safe sans sol
			# detecte, pour timeout snap logique (voir helper
			# _gerer_freeze_kinematic).
			"frames_sans_sol": 0,
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
	# La donnee ne bouge par calcul math QUE si la physique est inactive
	# (nœud absent = hors rayon rendu, OU nœud freeze = zone buffer). En
	# zone safe (nœud unfrozen), la physique pilote et sync donnee<-noeud.
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
		# FRAMES_SANS_SOL : compte les frames consecutives ou le carre est
		# en zone safe mais raycast sol echoue (terrain pas encore cook).
		# Au-dela de FRAMES_SANS_SOL_MAX, snap au sol logique via carte
		# (donnee) pour eviter le carre coince freeze eternellement.
		"frames_sans_sol": 0,
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
			# CREATE si pas de nœud (nouveau ou revient dans rayon).
			# Freeze KINEMATIC par defaut, degel par le helper si zone safe.
			if prod.noeud == null or not is_instance_valid(prod.noeud):
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
			# BASCULE FREEZE (helper generique).
			if prod.noeud is RigidBody3D:
				_gerer_freeze_kinematic(prod.noeud, prod, d2 < _rayon_safe2)
			# ZONE SAFE (freeze=false, physique active) : velocity pilote
			# vers cible (patron scalable, evite teleport chaque frame).
			# Sync donnee <- noeud (position portee par physique).
			# ZONE BUFFER (freeze=true KINEMATIC) : donnee bouge via
			# _avancer_donnees, push noeud <- donnee (freeze KINEMATIC
			# autorise set global_position).
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
					# Freeze KINEMATIC : donnee bouge, noeud suit par teleport
					# (physique inactive donc set_global_position ok).
					rb.global_position = prod.position
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
				# FREEZE PAR DEFAUT AU SPAWN : evite chute si sol physique
				# pas encore cook (terrain_visible etale le chargement sur
				# plusieurs frames). Sera degele par le check ci-dessous
				# si sol confirme.
				# FREEZE_MODE_KINEMATIC (pas STATIC) : sans quoi Area3D ne
				# detecte pas les collisions (voir forum.godotengine.org
				# thread 79351). Les balles violettes (Area3D) doivent
				# pouvoir toucher les carres frozen.
				if n is RigidBody3D:
					var rb_new: RigidBody3D = n
					rb_new.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
					rb_new.freeze = true
				cr.noeud = n
			# BASCULE FREEZE DYNAMIQUE (patron Minecraft simulation vs render
			# distance) : sous _rayon_safe ET sol confirme -> unfreeze
			# (physique active, cognable). Au-dela ou sol absent -> freeze
			# (visible mais immobile, evite chute dans zone terrain non
			# streamed). Set freeze SEULEMENT si l'etat change (evite
			# spam physics).
			if cr.noeud is RigidBody3D:
				_gerer_freeze_kinematic(cr.noeud, cr, d2 < _rayon_safe2)
			# SYNC POSITION UNIQUEMENT quand unfreeze : le carre etait
			# physique, son deplacement (cognement par joueur) est legitime.
			# Si freeze, cr.position reste stable a la ponte.
			if cr.noeud is RigidBody3D and not (cr.noeud as RigidBody3D).freeze:
				cr.position = cr.noeud.global_position
		else:
			# HORS RAYON : queue_free du nœud, remise a null explicite.
			# Le cr reste dans _carres, sera recree au retour du joueur.
			if cr.noeud != null and is_instance_valid(cr.noeud):
				cr.noeud.queue_free()
				cr.noeud = null

# CONFIRME SOL PHYSIQUE PRESENT SOUS `pos` via raycast vertical court.
# Utilise pour decider si un carre peut etre degele sans tomber
# (terrain_visible cook les cellules sur plusieurs frames -- distance <
# rayon_safe ne garantit PAS que le sol est cook). Raycast de 0.5m
# au-dessus de pos vers 3m dessous : tolere une petite hauteur au-dessus
# du sol (repos naturel). Rend false si get_world_3d absent (ex. hors
# arbre).
# HELPER GENERIQUE : gere la bascule freeze KINEMATIC d'un RigidBody3D
# selon zone safe + presence de sol physique + timeout snap logique.
# Reutilisable pour toute entite physique du proto (carre rouge, futurs
# ennemis mobiles, autres objets). Le `data` doit contenir un champ
# `frames_sans_sol: int` et un champ `position: Vector3` (mise a jour
# si snap logique declenche).
#
# Trois zones :
#   - Hors zone safe -> freeze (pas de chute possible hors terrain streamed)
#   - Zone safe + sol raycast OK -> unfreeze (physique active, cognable)
#   - Zone safe + sol absent > FRAMES_SANS_SOL_MAX -> snap au sol logique
#     via carte, reset compteur
#
# Au degel : reset velocity (issue godotengine/godot#92891). Set freeze
# seulement si l'etat change (evite spam physics chaque frame).
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

# SNAP AU SOL LOGIQUE via carte_terrain (donnee, indep de physique cook).
# Cherche cellule courante d'abord ; si sommet null, scan les 8 voisines
# spirale. Modifie cr.position en place. Rend true si sommet trouve.
# Utile quand raycast physique rate en permanence -- la carte reste
# source de verite pour "sol logique".
func _snap_sol_via_carte(cr: Dictionary) -> bool:
	var col_x: int = int(floor(cr.position.x / cote_cellule))
	var col_z: int = int(floor(cr.position.z / cote_cellule))
	# Scan cellule courante + 8 voisines (rayon 1). Chaque cellule
	# valide donne un Y = (sommet+1)*cote + mi-hauteur carre.
	for dx in [0, 1, -1]:
		for dz in [0, 1, -1]:
			var col := Vector2i(col_x + dx, col_z + dz)
			var som: Variant = _carte.sommet(col)
			if som == null:
				continue
			# Trouve. Snap Y + optionnellement X/Z au centre de la cellule
			# si on n'est pas dans la case courante (evite d'etre imbrique
			# dans un mur X/Z).
			if dx != 0 or dz != 0:
				cr.position.x = float(col.x) * cote_cellule + cote_cellule * 0.5
				cr.position.z = float(col.y) * cote_cellule + cote_cellule * 0.5
			cr.position.y = (float(int(som)) + 1.0) * cote_cellule + 0.2
			return true
	return false

func _sol_present_sous(pos: Vector3) -> bool:
	# Le manager est un Node (pas Node3D), get_world_3d n'existe pas ici.
	# On passe par _grille (GridMap, descendant Node3D) qui a la meme
	# World3D. Fallback : get_viewport().find_world_3d() si _grille absent.
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
