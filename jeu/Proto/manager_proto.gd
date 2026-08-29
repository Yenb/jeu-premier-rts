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

@tool
extends Node

const ProducteurScene = preload("res://jeu/Proto/producteur.tscn")
const Monde = preload("res://scripts/monde.gd")
const CarreVisuelScene = preload("res://jeu/Outil de jeu/carre_rouge.tscn")
const BalleScene = preload("res://jeu/Proto/balle_violette.tscn")
const BarreVieShader = preload("res://jeu/Outil de jeu/barre_de_vie.gdshader")

@export_group("Rendu")
@export var rayon_rendu: float = 60.0
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
# Zone de spawn : nœud enfant "ZoneSpawn" (MeshInstance3D avec BoxMesh)
# glissé à la souris dans l'éditeur. Sa position 3D est le centre du carré,
# sa taille visuelle est ajustée au _ready selon spawn_demi_cote.
@export var spawn_demi_cote: float = 10.0 : set = _set_spawn_demi_cote
@export var intervalle_spawn_ennemi: float = 1.0
@export var max_ennemis: int = 2500
# Nombre d'ennemis crees a chaque intervalle de spawn (avant plafond max).
@export var ennemis_par_cycle: int = 5
@export var vitesse_ennemi: float = 2.0
@export var vie_ennemi: int = 3


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
# BARRE DE VIE DU JOUEUR (200 PV). HUD 2D pour visibilite pendant le proto,
# a cacher/deplacer plus tard. Le contact avec un carre rouge coute 1 PV/s.
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
var _ennemis: Array = []
# TAS DE MATIERE AU SOL. Chaque sous-cube casse spawn 1 unite au point
# d'impact. La matiere tombe par gravite data jusqu'au sol effectif
# (`sommet(x, z)`). Vit en donnees pures partout dans le monde ; rendu
# streame par rayon. Cap total pour eviter accumulation.
# Indexe dans `Monde` (framework) : requete `choses_dans_rayon(pos_obs, r)`
# gratuite pour le rendu et le ramassage a l'etape 2.
var _monde_tas: Monde
var _prochain_id_tas: int = 0
const MAX_TAS := 2000
const GRAVITE_TAS := 18.0
const TAILLE_MESH_TAS := 0.35
var _mesh_tas: BoxMesh
var _mat_tas_terre: StandardMaterial3D
# Colonne (Vector2i) -> int, impacts accumules sur la colonne. Vide apres retrait.
# Repulsion inter-ennemis en data pure : bucket spatial reconstruit chaque
# frame dans _repousser_ennemis, aucun etat persistant a maintenir.
var _horloge_spawn: float = 0.0
var _zone_spawn: Node3D = null
var _mesh_ennemi: BoxMesh
var _mesh_barre: PlaneMesh
var _rng_ennemis := RandomNumberGenerator.new()

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
const RAYON_HIT_ENNEMI := 0.5
# NOURRITURE ENNEMI : reserve max, consomme 1 par metre parcouru. A zero, la
# famine draine 1 PV toutes les 5 s.
const NOURRITURE_MAX_ENNEMI := 500.0
const COUT_NOURRITURE_PAR_M := 1.0
const INTERVALLE_FAMINE := 5.0
# COLLISION INTER-CARRES EN DONNEES : push-apart si distance < seuil.
# Sans push, les carres empilent verticalement (deux pontes proches +
# gravite = pile). Cote cellule spatial hash = RAYON_REPOUSSE_CARRES
# pour que le voisinage 3x3 couvre exactement la portee de repousse.
const RAYON_REPOUSSE_CARRES := 0.6
const FORCE_REPOUSSE := 2.0
# REPULSION ENNEMIS via PhysicsServer3D direct (RID sans Node). Une RID area
# par ennemi, callback central pour les paires signalees par le BVH physique.
# Repulsion data en boucle sur les paires. Zero Node par ennemi. Layer 16 (bit
# 5) : couche exclusive ennemi-ennemi.
# REPULSION ENNEMIS EN DATA PURE (doctrine data-verite). Bucket spatial X/Z,
# push horizontal en donnees. Aucune Area RID, aucun signal Godot -- marche
# partout dans le monde, indépendant du streaming.
const RAYON_REPOUSSE_ENNEMI := 0.9
const FORCE_REPOUSSE_ENNEMI := 15.0
# Gravite data appliquee par ennemi hors du sol. Meme regle que le joueur
# (`personnage.gravite = 18`) -- coherent visuellement.
const GRAVITE_ENNEMI := 18.0
# PARTICULES IMPACT : bref eclat visuel au hit. Duree courte pour ne pas
# accumuler des noeuds dans la scene meme sous feu nourri.
const DUREE_IMPACT := 0.35

func _ready() -> void:
	if Engine.is_editor_hint():
		_rafraichir_zone_spawn()
		return
	# GROUPE "manager_proto" : permet a arme_tir.gd de retrouver le manager
	# pour lui pousser les balles (spawn_balle). Sans groupe, arme_tir
	# devrait connaitre le chemin de scene -- fragile.
	add_to_group("manager_proto")
	# GROUPE "ressources_terrain" RETIRE : depuis qu'un vrai RessourcesTerrain
	# est dans la scene (avec profils de blocs et regeneration par cellule),
	# le manager ne doit plus prendre ce role -- deux membres du groupe et
	# get_first_node_in_group renverrait le premier ajoute, imprevisible.
	# add_to_group("ressources_terrain")
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
	_rng_ennemis.seed = 20260827
	_preparer_meshes_ennemis()
	_preparer_hud_pv()
	_monde_tas = Monde.new()
	_mesh_tas = BoxMesh.new()
	_mesh_tas.size = Vector3(TAILLE_MESH_TAS, TAILLE_MESH_TAS, TAILLE_MESH_TAS)
	_mat_tas_terre = StandardMaterial3D.new()
	_mat_tas_terre.albedo_color = Color(0.35, 0.22, 0.12, 1.0)
	_mat_tas_terre.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mesh_tas.material = _mat_tas_terre
	_zone_spawn = get_node_or_null("ZoneSpawn") as Node3D
	if _zone_spawn == null:
		push_warning("manager_proto : nœud enfant 'ZoneSpawn' introuvable — aucun spawn d'ennemi")
	else:
		_rafraichir_zone_spawn()

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
	if Engine.is_editor_hint():
		return
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
	_tick_spawn_ennemis(delta)
	_tick_ia_ennemis(delta)
	_repousser_ennemis(delta)
	_bascule_rendu_ennemis()
	_ticker_tas(delta)
	_bascule_rendu_tas()
	_tick_pv_joueur(delta)

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

# API RESSOURCES pour inspecteur_bloc.gd -- meme contrat que
# ressources_terrain.gd. LECTURE SEULE, O(1) : `_reserves.get` avec defaut
# n'ecrit rien et ne cree aucune entree. Le defaut `capacite_case` rend une
# cellule jamais entamee comme pleine, sans la stocker.
func quantite_a(cellule: Vector3i) -> int:
	return int(floor(_reserves.get(cellule, capacite_case)))

# PRELEVEMENT, O(1) : delegue au meme geste que l'extraction des producteurs.
# La cellule entamee entre dans _tick_regen (regen locale) -- exactement le
# comportement d'une case minee par un producteur, aucun cout par frame ajoute.
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
	# Y sol via la NOUVELLE `sommet(x, z)` : precis au sous-cube pres.
	# Retourne directement la Y monde du sommet effectif sous cette position.
	var y_haut: Variant = _carte.sommet(cr.position.x, cr.position.z)
	if y_haut == null:
		return  # hors emprise, pas de sol logique
	# Y sol = face haute + mi-hauteur carre (0.2).
	var y_sol: float = float(y_haut) + 0.2
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
			var som: Variant = _carte.sommet_max_colonne(col)
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
			if not touche:
				var rayon2_en := RAYON_HIT_ENNEMI * RAYON_HIT_ENNEMI
				for e in _ennemis:
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
						_rafraichir_barre_ennemi(e)
						touche = true
						pos_hit = e.position
						break
			if not touche and _carte != null:
				# HIT SOL via la doctrine data : la balle percute quand elle
				# passe SOUS le sol effectif a (x, z). `sommet(x, z)` rend la
				# Y monde precise au sous-cube. Robuste : indep. de la cellule
				# pleine, prend en compte les sous-cubes deja cassés.
				var y_sol: Variant = _carte.sommet(b.position.x, b.position.z)
				if y_sol != null and b.position.y <= float(y_sol):
					var sol_y: float = float(y_sol)
					# La cellule qui porte le sous-cube touche : celle dont
					# la face haute est sol_y. cy = floor((sol_y - epsilon) / cote).
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
						# iy depuis sol_y : le sous-cube dont la face haute
						# vaut sol_y a iy tel que (iy+1)*cote/3 = sol_y - cy*cote.
						var iy: int = clampi(int(round(
							((sol_y - float(cy) * cote_cellule) * 3.0 / cote_cellule) - 1.0)), 0, 2)
						var idx: int = ix + iy * 3 + iz * 9
						# La carte gere le compteur PV (data), retourne true si
						# le sous-cube a ete casse par cet appel.
						var casse: bool = _carte.ajouter_pv_sous_cube(cellule, idx, 1)
						if casse:
							# CONSERVATION MASSE : la matiere du sous-cube casse
							# tombe au sol comme un tas ramassable.
							_spawn_tas(Vector3(b.position.x, sol_y, b.position.z), "terre")
					touche = true
					pos_hit = Vector3(b.position.x, sol_y, b.position.z)
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

# REPOUSSE INTER-ENNEMIS EN DATA PURE. Meme patron que _repousser_carres :
# bucket spatial reconstruit par frame (O(N) construction, O(N*k) tests avec
# k ~ densite locale). Push horizontal seul (Y suit la chute data). Marche
# partout dans le monde, independant du streaming.
func _repousser_ennemis(delta: float) -> void:
	if _ennemis.is_empty():
		return
	var cote := RAYON_REPOUSSE_ENNEMI
	var buckets: Dictionary = {}
	for idx in range(_ennemis.size()):
		var e = _ennemis[idx]
		if e.est_mort:
			continue
		var cx := int(floor((e.position as Vector3).x / cote))
		var cz := int(floor((e.position as Vector3).z / cote))
		var cle := Vector2i(cx, cz)
		if not buckets.has(cle):
			buckets[cle] = []
		(buckets[cle] as Array).append(idx)
	var voisins_offset := [Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]
	for cle in buckets.keys():
		var ici: Array = buckets[cle]
		for i_a in range(ici.size()):
			var a = _ennemis[ici[i_a]]
			for j in range(i_a + 1, ici.size()):
				_appliquer_repousse_ennemis(a, _ennemis[ici[j]])
		for off in voisins_offset:
			var voisin_cle := Vector2i(cle.x + off.x, cle.y + off.y)
			if not buckets.has(voisin_cle):
				continue
			var la: Array = buckets[voisin_cle]
			for idx_a in ici:
				var a2 = _ennemis[idx_a]
				for idx_b in la:
					_appliquer_repousse_ennemis(a2, _ennemis[idx_b])

func _appliquer_repousse_ennemis(a: Dictionary, b: Dictionary) -> void:
	if a.est_mort or b.est_mort:
		return
	var seuil := RAYON_REPOUSSE_ENNEMI
	var seuil2 := seuil * seuil
	var vers: Vector3 = (b.position as Vector3) - (a.position as Vector3)
	vers.y = 0.0
	var d2: float = vers.length_squared()
	if d2 >= seuil2:
		return
	var dir: Vector3
	var chevauchement: float
	if d2 <= 0.0001:
		# Empilement exact : brise la symetrie par un push cardinal fixe.
		dir = Vector3(1.0, 0.0, 0.0)
		chevauchement = seuil
	else:
		var d: float = sqrt(d2)
		chevauchement = seuil - d
		dir = vers / d
	# Separation instantanee : moitie du chevauchement, sans delta.
	var push: Vector3 = dir * chevauchement * 0.5
	var pos_a_apres: Vector3 = (a.position as Vector3) - push
	var pos_b_apres: Vector3 = (b.position as Vector3) + push
	if not _mouvement_bloque_par_terrain(a.position, pos_a_apres):
		a.position = pos_a_apres
	if not _mouvement_bloque_par_terrain(b.position, pos_b_apres):
		b.position = pos_b_apres

# TEST DATA PUR entre pos_a et pos_b. `carte.sommet(colonne)` marche partout
# dans le monde -- aucun raycast, aucune dependance au streaming physique.
# Blocage si le sommet de la colonne candidate depasse celui de la colonne
# actuelle de >= 2 cases (meme regle que le saut du joueur : 1 case max).
# Meme case = pas de blocage, meme si on est deja sur un mur haut.
func _mouvement_bloque_par_terrain(pos_a: Vector3, pos_b: Vector3) -> bool:
	if _carte == null:
		return false
	# Y monde precise au sous-cube via la nouvelle `sommet(x, z)`.
	var y_a: Variant = _carte.sommet(pos_a.x, pos_a.z)
	var y_b: Variant = _carte.sommet(pos_b.x, pos_b.z)
	if y_a == null or y_b == null:
		return false
	# Blocage si la marche fait plus d'1 case (2 m) de haut -- meme regle que
	# le saut du joueur. Une petite marche <= cote_cellule est franchissable.
	return float(y_b) - float(y_a) > cote_cellule

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
# TAS DE MATIERE : spawn au point de casse, indexe dans `_monde_tas` (framework
# `scripts/monde.gd`), tombe par gravite data jusqu'au sol effectif, y reste
# jusqu'a ramassage (etape 2).
func _spawn_tas(pos: Vector3, matiere: String) -> void:
	# Cap : quand on depasse MAX_TAS, retire le plus ancien via _rang de monde.
	if _monde_tas.choses.size() >= MAX_TAS:
		var id_vieux = _monde_tas.choses.keys()[0]
		var wrap = _monde_tas.par_id(id_vieux)
		if wrap != null:
			var vc = wrap.chose
			if vc.noeud != null and is_instance_valid(vc.noeud):
				vc.noeud.queue_free()
		_monde_tas.retirer(id_vieux)
	var id_neuf: String = "tas_%d" % _prochain_id_tas
	_prochain_id_tas += 1
	var tas := {
		"id": id_neuf,
		"position": pos,
		"vitesse_y": 0.0,
		"noeud": null,
		"matiere": matiere,
	}
	_monde_tas.ajouter(tas, "tas", pos)

func _ticker_tas(delta: float) -> void:
	if _monde_tas.choses.is_empty():
		return
	for wrap in _monde_tas.choses.values():
		var t: Dictionary = wrap.chose
		var pos: Vector3 = t.position
		if _carte == null:
			continue
		var y_sol: Variant = _carte.sommet(pos.x, pos.z)
		if y_sol == null:
			continue
		var sol_y: float = float(y_sol) + TAILLE_MESH_TAS * 0.5
		var change := false
		if pos.y > sol_y:
			t.vitesse_y -= GRAVITE_TAS * delta
			pos.y += t.vitesse_y * delta
			if pos.y < sol_y:
				pos.y = sol_y
				t.vitesse_y = 0.0
			change = true
		elif pos.y < sol_y:
			# Le sol est monte SOUS le tas (rare mais possible via placement).
			pos.y = sol_y
			t.vitesse_y = 0.0
			change = true
		if change:
			t.position = pos
			_monde_tas.deplacer(t)

func _bascule_rendu_tas() -> void:
	if _observateur == null:
		return
	var pos_obs: Vector3 = _observateur.global_position
	var parent := get_parent()
	if parent == null:
		return
	# Requete locale : seuls les tas dans le rayon rendu sont candidats a
	# recevoir un noeud visuel. Cout O(rayon), pas O(N).
	var proches: Array = _monde_tas.choses_dans_rayon(pos_obs, rayon_rendu)
	var ids_proches: Dictionary = {}
	for entree in proches:
		var t: Dictionary = entree.chose
		ids_proches[t.id] = true
		if t.noeud == null or not is_instance_valid(t.noeud):
			var n := MeshInstance3D.new()
			n.mesh = _mesh_tas
			n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(n)
			n.global_position = t.position
			t.noeud = n
		else:
			(t.noeud as Node3D).global_position = t.position
	# Ceux hors rayon : queue_free du noeud, null.
	for wrap in _monde_tas.choses.values():
		var tas: Dictionary = wrap.chose
		if ids_proches.has(tas.id):
			continue
		if tas.noeud != null and is_instance_valid(tas.noeud):
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

# --- ENNEMIS ---

func _preparer_meshes_ennemis() -> void:
	_mesh_ennemi = BoxMesh.new()
	_mesh_ennemi.size = Vector3(0.8, 0.8, 0.8)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.15, 0.15)
	_mesh_ennemi.material = mat
	_mesh_barre = PlaneMesh.new()
	_mesh_barre.size = Vector2(0.6, 0.08)

func _set_spawn_demi_cote(v: float) -> void:
	spawn_demi_cote = v
	_rafraichir_zone_spawn()

func _rafraichir_zone_spawn() -> void:
	# Recherchée à chaque appel : le setter peut tirer avant _ready, et le nœud
	# ZoneSpawn peut être renommé/supprimé dans l'éditeur pendant l'édition.
	var noeud := get_node_or_null("ZoneSpawn")
	if noeud == null:
		return
	var mi := noeud as MeshInstance3D
	if mi == null or not (mi.mesh is BoxMesh):
		return
	# Y fixé à 0.4 : dalle plate au sol, pas un cube qui masque la vue.
	(mi.mesh as BoxMesh).size = Vector3(spawn_demi_cote * 2.0, 0.4, spawn_demi_cote * 2.0)

func _tick_spawn_ennemis(delta: float) -> void:
	if _zone_spawn == null:
		return
	_horloge_spawn += delta
	if _horloge_spawn < intervalle_spawn_ennemi:
		return
	_horloge_spawn = 0.0
	# ennemis_par_cycle tentatives par intervalle. Chaque tentative fait son
	# reject sampling propre. Le plafond max_ennemis est teste avant chaque.
	for _n in range(ennemis_par_cycle):
		if _ennemis.size() >= max_ennemis:
			return
		_spawner_un_ennemi()

func _spawner_un_ennemi() -> void:
	var centre: Vector3 = _zone_spawn.global_position
	# Reject sampling : la colonne tiree ne doit pas etre un mur (sommet
	# strictement au-dessus du sommet_de_base) -- sinon l'ennemi apparait EN
	# HAUT du mur. 12 essais max avant d'abandonner cette tentative.
	var x := 0.0
	var z := 0.0
	var y := centre.y
	var trouve := false
	for essai in range(12):
		x = centre.x + _rng_ennemis.randf_range(-spawn_demi_cote, spawn_demi_cote)
		z = centre.z + _rng_ennemis.randf_range(-spawn_demi_cote, spawn_demi_cote)
		if _carte == null:
			trouve = true
			break
		var cx := int(floor(x / cote_cellule))
		var cz := int(floor(z / cote_cellule))
		var som: Variant = _carte.sommet_max_colonne(Vector2i(cx, cz))
		if som == null:
			continue
		if int(som) > _carte.sommet_de_base():
			continue
		y = (float(int(som)) + 1.0) * cote_cellule + 0.4
		trouve = true
		break
	if not trouve:
		return
	var e := {
		"position": Vector3(x, y, z),
		"vitesse_y": 0.0,
		"vie": vie_ennemi,
		"noeud": null,
		"est_mort": false,
		"nourriture": NOURRITURE_MAX_ENNEMI,
		"famine": 0.0,
	}
	_ennemis.append(e)

func _tick_ia_ennemis(delta: float) -> void:
	if _observateur == null:
		return
	var pos_obs: Vector3 = _observateur.global_position
	var i := 0
	while i < _ennemis.size():
		var e = _ennemis[i]
		if e.est_mort:
			if e.noeud != null and is_instance_valid(e.noeud):
				e.noeud.queue_free()
			_ennemis.remove_at(i)
			continue
		var pos: Vector3 = e.position
		var vers: Vector3 = pos_obs - pos
		vers.y = 0.0
		if vers.length() > 0.5:
			var direction := vers.normalized()
			var candidat: Vector3 = pos + direction * vitesse_ennemi * delta
			# Un seul test : raycast physique entre pos et candidat, a hauteur
			# pos.y + cote_cellule (torse d'ennemi au-dessus des pieds). Le
			# rayon touche un mur de >= 2 cases (sa face verticale coupe le
			# rayon), un mur d'exactement 1 case est SOUS le rayon donc
			# franchissable. Zero test data, zero snapshot -- la geometrie
			# reelle de la GridMap tranche.
			if not _mouvement_bloque_par_terrain(pos, candidat):
				pos = candidat
		# CHUTE ET GRAVITE EN DATA (doctrine). Sommet precis au sous-cube via
		# `sommet(x, z)` : rend directement la Y monde du plus haut sous-cube
		# plein sous ce point. L'ennemi tombe dans un trou d'un sous-cube.
		if _carte != null:
			var y_haut: Variant = _carte.sommet(pos.x, pos.z)
			if y_haut != null:
				var sol_y: float = float(y_haut) + 0.4
				if pos.y > sol_y:
					e.vitesse_y -= GRAVITE_ENNEMI * delta
					pos.y += e.vitesse_y * delta
					if pos.y < sol_y:
						pos.y = sol_y
						e.vitesse_y = 0.0
				else:
					pos.y = sol_y
					e.vitesse_y = 0.0
		# NOURRITURE : 1 point par metre parcouru (composante X/Z seule).
		var deplacement := Vector3(pos.x - (e.position as Vector3).x, 0.0, pos.z - (e.position as Vector3).z)
		var dist := deplacement.length()
		if dist > 0.0 and e.nourriture > 0.0:
			e.nourriture = max(0.0, e.nourriture - COUT_NOURRITURE_PAR_M * dist)
			_rafraichir_barre_nourriture_ennemi(e)
		# FAMINE : nourriture epuisee -> compteur monte, -1 PV tous les 5 s.
		if e.nourriture <= 0.0:
			e.famine += delta
			if e.famine >= INTERVALLE_FAMINE:
				e.famine -= INTERVALLE_FAMINE
				e.vie -= 1
				if e.vie <= 0:
					e.est_mort = true
				_rafraichir_barre_ennemi(e)
		else:
			e.famine = 0.0
		e.position = pos
		i += 1

func _pas_permis(actuel: Vector3, candidat: Vector3) -> bool:
	if _carte == null:
		return true
	# Y monde precise au sous-cube. Permis si la marche est <= cote_cellule.
	var y_actuel: Variant = _carte.sommet(actuel.x, actuel.z)
	var y_candidat: Variant = _carte.sommet(candidat.x, candidat.z)
	if y_actuel == null or y_candidat == null:
		return true
	return float(y_candidat) - float(y_actuel) <= cote_cellule

func _bascule_rendu_ennemis() -> void:
	if _observateur == null:
		return
	var pos_obs: Vector3 = _observateur.global_position
	var parent := get_parent()
	if parent == null:
		return
	var r2 := rayon_rendu * rayon_rendu
	for e in _ennemis:
		if e.est_mort:
			continue
		var d2: float = ((e.position as Vector3) - pos_obs).length_squared()
		if d2 < r2:
			if e.noeud == null or not is_instance_valid(e.noeud):
				var n := _creer_visuel_ennemi(
					float(e.vie) / float(vie_ennemi),
					float(e.nourriture) / NOURRITURE_MAX_ENNEMI)
				parent.add_child(n)
				n.global_position = e.position
				e.noeud = n
			else:
				(e.noeud as Node3D).global_position = e.position
		else:
			if e.noeud != null and is_instance_valid(e.noeud):
				e.noeud.queue_free()
				e.noeud = null

func _creer_visuel_ennemi(fraction_vie: float, fraction_nourriture: float) -> StaticBody3D:
	var racine := StaticBody3D.new()
	# child(0) : cube
	var cube := MeshInstance3D.new()
	cube.mesh = _mesh_ennemi
	cube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	racine.add_child(cube)
	# child(1) : barre de vie (rouge/vert par defaut du shader)
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

# CORPS-A-CORPS : direction 3D, suit la vision comme l'arme de tir (le tangage
# yeux est deja recopie sur l'arme dans arme_tir.gd). Segment
# [origine, origine + dir * portee], distance point-segment 3D vs chaque
# ennemi vivant, hit celui le plus proche (distance tireur-ennemi) dont la
# distance au segment est <= RAYON_HIT_ENNEMI. Rend true si touche. Ni carres
# ni sol.
func frapper_melee(origine: Vector3, direction: Vector3, portee: float, degat: int) -> bool:
	if direction.length_squared() <= 0.0:
		return false
	var seg: Vector3 = direction.normalized() * portee
	var long2: float = seg.length_squared()
	var rayon2 := RAYON_HIT_ENNEMI * RAYON_HIT_ENNEMI
	var cible = null
	var dist2_meilleur := INF
	for e in _ennemis:
		if e.est_mort:
			continue
		var vers: Vector3 = (e.position as Vector3) - origine
		var t: float = clampf(vers.dot(seg) / long2, 0.0, 1.0)
		var proche: Vector3 = seg * t
		var d2: float = (vers - proche).length_squared()
		if d2 > rayon2:
			continue
		var d2_origine: float = vers.length_squared()
		if d2_origine < dist2_meilleur:
			dist2_meilleur = d2_origine
			cible = e
	if cible == null:
		return false
	cible.vie -= degat
	if cible.vie <= 0:
		cible.est_mort = true
	_rafraichir_barre_ennemi(cible)
	return true

func _rafraichir_barre_ennemi(e: Dictionary) -> void:
	if e.noeud == null or not is_instance_valid(e.noeud):
		return
	var barre := (e.noeud as Node3D).get_child(1) as MeshInstance3D
	if barre == null:
		return
	var mat := barre.get_surface_override_material(0) as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("fraction", float(e.vie) / float(vie_ennemi))

# Barre bleue (child 3) : rafraichit la fraction depuis e.nourriture.
func _rafraichir_barre_nourriture_ennemi(e: Dictionary) -> void:
	if e.noeud == null or not is_instance_valid(e.noeud):
		return
	if (e.noeud as Node3D).get_child_count() < 4:
		return
	var barre := (e.noeud as Node3D).get_child(3) as MeshInstance3D
	if barre == null:
		return
	var mat := barre.get_surface_override_material(0) as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("fraction", float(e.nourriture) / NOURRITURE_MAX_ENNEMI)

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
	for e in _ennemis:
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
