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
const BalleScene = preload("res://jeu/Proto/balle_violette.tscn")

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
# GRAVITE POUR SIMULATION DONNEE. Applique quand la physique est
# inactive (nœud absent hors rayon, ou nœud freeze en zone buffer).
# Assure que la data suit la gravite naturelle, meme quand le joueur
# n'est pas la. Sans ca, les carres restent suspendus a la hauteur du
# producteur pour l'eternite en donnees.
const GRAVITE_DATA := 9.8
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
var _balles: Array = []
var _impacts: Array = []
var _horloge: float = 0.0

# BALLES SIMULEES EN DONNEES. La collision se fait en donnee (test point-
# segment contre chaque carre pour eviter tunneling), la peau visuelle
# (Area3D balle_violette) est instanciee dans rayon rendu et suit la
# position data. Aucune logique metier (mort, purge) ne depend du noeud.
# Anti-tunneling : a 20 m/s et delta 1/60 = 0.33 m par tick, sup au rayon
# hit 0.3 m -> test distance point-point manque des collisions rapides.
# Solution : distance du point cible au segment [ancienne, nouvelle] pos.
const VITESSE_BALLE := 20.0
const DUREE_BALLE := 5.0
const RAYON_HIT_CARRE := 0.35
# EXCLUSION TIREUR : la balle nait 0.15 m devant le cube de l'arme ; si
# un carre est colle a la bouche (joueur qui se colle a un carre puis
# tire), on aurait un hit immediat. Tant que la balle n'a pas parcouru
# RAYON_EXCLUSION_TIREUR depuis son point de depart, on ignore les
# collisions. 1 m couvre la capsule joueur + cube arme + marge.
const RAYON_EXCLUSION_TIREUR := 1.0
const RAYON_EXCLUSION_TIREUR2 := RAYON_EXCLUSION_TIREUR * RAYON_EXCLUSION_TIREUR
# COLLISION INTER-CARRES EN DONNEES : push-apart si distance < seuil.
# Sans push, les carres empilent verticalement (deux pontes proches +
# gravite = pile). Cote cellule spatial hash = RAYON_REPOUSSE_CARRES
# pour que le voisinage 3x3 couvre exactement la portee de repousse.
const RAYON_REPOUSSE_CARRES := 0.6
const FORCE_REPOUSSE := 2.0
# PARTICULES IMPACT : bref eclat visuel au hit. Duree courte pour ne pas
# accumuler des noeuds dans la scene meme sous feu nourri.
const DUREE_IMPACT := 0.35

func _ready() -> void:
	# GROUPE "manager_proto" : permet a arme_tir.gd de retrouver le manager
	# pour lui pousser les balles (spawn_balle). Sans groupe, arme_tir
	# devrait connaitre le chemin de scene -- fragile.
	add_to_group("manager_proto")
	# INSTRUMENTATION PERF : sonde mesure_perf.gd active UNIQUEMENT si env
	# var MESURE_PERF=1 ou TAILLE_TUILE=<n>. Sans var, sonde ABSENTE --
	# la scene tourne normalement, aucun quit automatique.
	# Anti-piege : sans cette garde, chaque lancement quittait a 10s.
	if OS.get_environment("MESURE_PERF") == "1" or OS.get_environment("TAILLE_TUILE") != "":
		var script_mesure: GDScript = load("res://jeu/Proto/mesure_perf.gd")
		var mesure: Node = script_mesure.new()
		add_child(mesure)
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
	_repousser_carres(delta)
	_tick_balles(delta)
	_ticker_impacts(delta)
	_bascule_rendu_producteurs()
	_bascule_rendu_carres()
	_bascule_rendu_balles()

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
	# Le carre nait a hauteur du producteur avec vy=0. La gravite data
	# le fait tomber tick apres tick dans _ticker_carres jusqu'au sol
	# logique (via carte). SIMULATION DE PHYSIQUE EN DONNEES : ce qui
	# se passe dans le monde ne depend pas de la presence du joueur.
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
		# SIMULATION GRAVITE EN DONNEES : uniquement si physique inactive
		# (nœud absent ou nœud freeze). En zone safe unfreeze, la physique
		# pilote et sync data <- noeud.global_position (voir bascule
		# rendu). Ici on couvre le cas "loin du joueur" et "zone buffer".
		var physique_active := cr.noeud != null and is_instance_valid(cr.noeud) \
			and cr.noeud is RigidBody3D and not (cr.noeud as RigidBody3D).freeze
		if not physique_active:
			_appliquer_gravite_data(cr, delta)
		i += 1

# GRAVITE DATA : chute simulee jusqu'au sol logique (via carte).
# Clamp au sol quand touche. Sans clamp, le carre s'enfonce.
func _appliquer_gravite_data(cr: Dictionary, delta: float) -> void:
	if _carte == null:
		return
	var col_x: int = int(floor(cr.position.x / cote_cellule))
	var col_z: int = int(floor(cr.position.z / cote_cellule))
	var som: Variant = _carte.sommet(Vector2i(col_x, col_z))
	if som == null:
		return  # hors emprise, pas de sol logique
	# Y sol = face haute cellule + mi-hauteur carre (0.2).
	var y_sol: float = (float(int(som)) + 1.0) * cote_cellule + 0.2
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

# SPAWN BALLE EN DONNEES. Appele par arme_tir.gd. Aucun noeud instancie
# ici -- la peau viendra au prochain _bascule_rendu_balles si le tireur
# est dans le rayon. Consequence : la simulation tourne meme si le rendu
# rate. Risque : si arme_tir tire hors rayon (impossible en pratique
# puisque le tireur = observateur), pas de peau visible. Plan B : ok.
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

# TICK BALLES DATA : avance chaque balle, teste collision segment vs
# carres en donnee, purge sur hit ou expiration. Independant du rendu.
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
		# Collision segment vs carres. Distance point-segment : projeter
		# cr.position sur [ancienne, nouvelle], clamp t dans [0,1], mesurer.
		var seg: Vector3 = b.position - b.ancienne
		var long2: float = seg.length_squared()
		if long2 <= 0.0:
			i += 1
			continue
		# EXCLUSION TIREUR : tant que la balle est proche du point de
		# depart, on ignore les collisions carres (evite hit immediat
		# quand le joueur tire colle a une cible).
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
			if touche:
				b.morte = true
				_spawn_impact(pos_hit)
				continue
		i += 1

# REPOUSSE INTER-CARRES EN DONNEES : evite empilement. Spatial hash
# reconstruit par frame (cout O(N)). Chaque carre inspecte sa cellule +
# 8 voisines, push-apart si voisin plus proche que RAYON_REPOUSSE.
# Ne touche PAS les carres physique-active (zone safe unfreeze) : la
# physique du RigidBody gere deja les collisions inter-carres reelles ;
# un push data serait ecrase par la sync data <- noeud.
# Scale N=1000 : O(N * k) avec k ~ 3 (densite locale typique) = trivial.
func _repousser_carres(delta: float) -> void:
	# Bucket par cellule spatiale. Cle Vector2i sur le plan X/Z.
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
	# Pour chaque bucket, tester paires internes + voisines droite/bas
	# pour eviter double comptage. On applique le push aux deux carres.
	# Pour chaque bucket : paires internes + paires avec voisins droite/bas
	# (evite double-comptage). Offsets voisins : (1,-1) (1,0) (1,1) (0,1).
	var voisins_offset := [Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]
	for cle in buckets.keys():
		var ici: Array = buckets[cle]
		# Paires internes.
		for i_a in range(ici.size()):
			var a = _carres[ici[i_a]]
			for j in range(i_a + 1, ici.size()):
				_appliquer_repousse(a, _carres[ici[j]], seuil2, delta)
		# Paires avec buckets voisins direction droite/bas.
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

# IMPACTS VISUELS. Petit eclair violet spawn au point de hit, dure
# DUREE_IMPACT puis queue_free. Pas de son (aucun asset audio dispo).
# Sans MeshInstance dedie : cree un OmniLight3D + petit MeshInstance
# sphere en code pour eviter un nouveau tscn.
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

# RENDU BALLES : instancie peau visuelle (balle_violette.tscn) dans rayon,
# la retire hors rayon. La peau n'a AUCUN script actif (set_script null
# supprime la logique projectile.gd embarquee dans le tscn). Position
# poussee chaque frame depuis b.position.
func _bascule_rendu_balles() -> void:
	if _observateur == null:
		return
	var pos_obs: Vector3 = _observateur.global_position
	var parent := get_parent()
	if parent == null:
		return
	var r2 := rayon_rendu * rayon_rendu
	for b in _balles:
		var d2: float = ((b.position as Vector3) - pos_obs).length_squared()
		if d2 < r2:
			if b.noeud == null or not is_instance_valid(b.noeud):
				var n := BalleScene.instantiate() as Node3D
				# NEUTRALISE le script projectile.gd (mouvement + timer 5s
				# autonomes). La balle devient une simple coque visuelle
				# pilotee par le manager. set_script(null) laisse l'Area3D
				# et ses enfants (Mesh, CollisionShape) intacts.
				n.set_script(null)
				parent.add_child(n)
				b.noeud = n
			b.noeud.global_position = b.position
		else:
			if b.noeud != null and is_instance_valid(b.noeud):
				b.noeud.queue_free()
				b.noeud = null
