extends Node

# Deuxieme manager (prototype IA n2), reparti de zero. NE reprend AUCUN import
# de manager_proto : il en RECOPIE le patron (spawn en donnee, streaming du
# rendu par distance a l'observateur, Array de Dictionary, separation
# data/rendu). Il pose des cubes verts dans la ZoneSpawnIAPrototype2 : un lot
# toutes les `intervalle_spawn` secondes, jusqu'a `max_cubes`, chacun a une
# position aleatoire (RNG seede) dans le demi-cote de la zone, snappe au sol par
# carte.sommet(x, z). ERRANCE : faute de besoin, chaque cube marche (le
# comportement PAR DEFAUT, qu'un futur besoin preemptera) -- direction au hasard,
# changee par intervalle ou au blocage (pente trop raide, bord de carte). Aucun
# degat. Mouvement DATA-PUR (pos += dir*vitesse*delta, sol lu dans carte.sommet,
# blocage par comparaison de sommets), jamais de physique Godot.
#
# LE JOUEUR EST UNE ENTITE DATA COMME LES CUBES. Il n'y a plus de CharacterBody3D
# ni de fantome qui recopie une position Godot : le nœud Personnage (Node3D) rend
# une INTENTION de mouvement, et c'est CE MANAGER qui deplace l'entite joueur, en
# donnee pure. Chaque frame, _pas_joueur : demande l'intention au Personnage
# (appel direct, sans course d'ordre), compose la velocite (horizontale + saut si
# au sol + gravite), avance la position, et resout le TERRAIN par le MEME chemin
# que les cubes (_deplacement_horizontal_valide + snap carte.sommet). La collision
# JOUEUR-CONTRE-CUBES passe par collision.gd (GJK/EPA). En fin de _physics_process,
# la position data est recopiee dans le nœud (le rendu suit la donnee, seule
# autorite). Symetrie totale entite/joueur, comme le veut CLAUDE.md § Liste
# exhaustive des interactions physiques a coder en data pure.
#
# COLLISION GENERALISTE EN DONNEE PURE (modele Orion, a reutiliser pour tout
# futur objet interactif) : la collision inter-entites ne passe PAS par des nœuds
# Godot (StaticBody3D / CollisionShape3D / PhysicsServer3D) mais par
# jeu/Proto/collision.gd applique sur des Dictionary d'entites portant leurs
# `formes`. Collision.tick(_monde, entites, dt) puis Collision.resoudre(...).
#
# ECHAFAUDAGE PERCEPTION (pose, PAS ENCORE BRANCHE) : chaque cube est une entite
# conforme au contrat de scripts/perception.gd (proprietes.canaux +
# canaux_config) ; le joueur porte un profil de saillance ; les deux vivent dans
# un Monde (scripts/monde.gd) tenu a jour chaque frame. Une horloge de perception
# (INTERVALLE_PERCEPTION) appelle _tick_perception, VIDE pour l'instant.
#
# Recoit (au _ready) : l'observateur par le groupe "observateur", la carte par
# le nœud frere "Terrain" du parent. Catalogues charges en direct.
#
# Regles reprises du patron : la VERITE est la donnee ; le nœud de rendu n'existe
# que dans le rayon. Aleatoire TOUJOURS seede (RNG reproductible).

const Monde = preload("res://scripts/monde.gd")
const Collision = preload("res://jeu/Proto/collision.gd")

const INTERVALLE_PERCEPTION := 0.1
# Trace de debug : une ligne par seconde (pos / vel / au_sol du joueur).
const INTERVALLE_TRACE := 1.0
# BLOCAGE DU JOUEUR PAR LA PENTE, jamais par une marche absolue. Un MUR (pente
# raide) arrete, une PENTE douce (rampe) se monte a pied. La pente se lit sur une
# DISTANCE DE SONDE FIXE devant les pieds, independante de la vitesse (sans quoi
# un meme obstacle bloquerait ou non selon qu'on marche ou qu'on sprinte).
#   MARCHE_JOUEUR : le sol devant doit depasser les pieds de plus que ca pour
#     compter comme obstacle (tolerance de niveau contre le bruit du snap).
#   SONDE_PENTE   : distance fixe devant les pieds ou l'on lit le sol.
#   PENTE_MAX     : au-dela, c'est un mur (bloque, il faut sauter). Une rampe a
#     45° vaut 1 ; 1.5 laisse monter jusqu'a ~56° et arrete tout mur vertical.
const MARCHE_JOUEUR := 0.05
const SONDE_PENTE := 0.2
const PENTE_MAX := 1.5

@export_group("Rendu")
@export var rayon_rendu: float = 60.0

@export_group("Spawn")
@export var spawn_actif: bool = true
@export var intervalle_spawn: float = 1.0
@export var max_cubes: int = 10
@export var cubes_par_cycle: int = 1
@export var spawn_demi_cote: float = 10.0 : set = _set_spawn_demi_cote

@export_group("Errance")
@export var vitesse_errance: float = 1.5

var _carte: Resource = null
var _cote_cellule: float = 2.0
var _observateur: Node3D = null
var _ennemis: Array = []
var _mesh_ennemi: BoxMesh
var _horloge_spawn: float = 0.0
var _rng := RandomNumberGenerator.new()
var _prochain_id_cube: int = 0

# Echafaudage perception + entite joueur.
var _monde
var _entite_joueur: Dictionary = {}
var _catalogue_canaux: Dictionary = {}
var _catalogue_profils_saillance: Dictionary = {}
var _horloge_perception: float = 0.0
var _horloge_trace: float = 0.0

func _ready() -> void:
	_observateur = get_tree().get_first_node_in_group(&"observateur")
	var parent := get_parent()
	if parent != null:
		var terrain := parent.get_node_or_null("Terrain")
		if terrain != null:
			_carte = terrain.get("carte") as Resource
	if _carte == null:
		push_warning("manager_proto_2 : carte introuvable")
	elif "cote" in _carte:
		_cote_cellule = float(_carte.get("cote"))
	_rng.seed = 20260902
	_preparer_mesh()
	_rafraichir_zone_spawn()

	# Catalogues (chargement direct, faute de chargeur centralise).
	_catalogue_canaux = _charger_json("res://data/canaux.json")
	_catalogue_profils_saillance = _charger_json("res://data/profils_saillance.json")

	# Monde de perception/collision + entite joueur.
	_monde = Monde.new()
	if _observateur != null:
		var hauteur_capsule := 1.8
		var rayon_capsule := 0.4
		_entite_joueur = {
			"id": "joueur",
			"position": _observateur.global_position,
			"proprietes": {
				"profil_saillance": "menace_3",
				# Capsule DECALEE de +hauteur/2 : l'origine du nœud Personnage est
				# aux PIEDS ; sans ce transform_locale la capsule serait centree sur
				# les pieds, donc a moitie enterree, et cognerait les cubes par le
				# sol. Les cubes n'en ont pas besoin (leur position spawn est deja
				# leur centre).
				"formes": [{
					"type": "capsule",
					"transform_locale": Transform3D(Basis.IDENTITY, Vector3(0.0, hauteur_capsule * 0.5, 0.0)),
					"parametres": {"rayon": rayon_capsule, "hauteur": hauteur_capsule},
				}],
				"masque_collision": 1,
				"masque_reponse": 1,
				"reponse": "bloque",
				"velocite": Vector3.ZERO,
				"orientation": Basis.IDENTITY,
				# Dimensions et vitesses, lues par personnage.gd (injectees plus bas).
				"rayon_capsule": rayon_capsule,
				"hauteur_capsule": hauteur_capsule,
				"hauteur_yeux": 1.7,
				"vitesse_marche": 4.0,
				"vitesse_saut": 8.5,
				"gravite": 18.0,
				"au_sol": false,
				# Visibilites du rendu du joueur (corps + marqueur de debug).
				"corps_visible": true,
				"marqueur_debug_visible": true,
			},
		}
		_entite_joueur.proprietes["aabb_cache"] = Collision.aabb_forme(
			_entite_joueur.proprietes.formes[0],
			Transform3D(Basis.IDENTITY, _entite_joueur.position))
		_monde.ajouter(_entite_joueur, "joueur", _entite_joueur.position)
		# Injection directe des donnees dans le nœud (dimensions, camera,
		# visibilites) -- appel, pas de course d'ordre au _ready.
		if _observateur.has_method("configurer_depuis_donnees"):
			_observateur.configurer_depuis_donnees(_entite_joueur)

# TICK EN _physics_process : l'interpolation physique est active (project.godot),
# donc tout transform (position joueur, nœuds cubes) doit etre pose dans le pas
# physique -- sinon Godot interpole depuis une source idle et avertit. Le rendu
# est alors LISSE entre deux pas physiques, gratuitement.
func _physics_process(delta: float) -> void:
	_tick_spawn(delta)
	_tick_errance(delta)
	_pas_joueur(delta)
	_bascule_rendu()
	# Collision inter-entites (joueur vs cubes) CHAQUE frame : a ~11 entites le
	# cout GJK/EPA est negligeable et le contact ne tremble pas. A re-mesurer si
	# la population d'entites en collision explose (remettre une horloge).
	_tick_collision(delta)
	_horloge_perception += delta
	if _horloge_perception >= INTERVALLE_PERCEPTION:
		_horloge_perception = 0.0
		_tick_perception(delta)
	# Le rendu suit la donnee : le manager (seule autorite de position) recopie la
	# position data du joueur dans son nœud. Le Personnage ne touche que sa
	# rotation et sa camera.
	if not _entite_joueur.is_empty() and _observateur != null:
		_observateur.global_position = _entite_joueur.position
	_tracer_joueur(delta)

func _preparer_mesh() -> void:
	_mesh_ennemi = BoxMesh.new()
	_mesh_ennemi.size = Vector3(0.8, 0.8, 0.8)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.8, 0.15)
	_mesh_ennemi.material = mat

# La taille de la boite de la zone suit spawn_demi_cote (WYSIWYG). Le setter peut
# tirer avant _ready -- get_node_or_null garde le cas.
func _set_spawn_demi_cote(v: float) -> void:
	spawn_demi_cote = v
	_rafraichir_zone_spawn()

func _rafraichir_zone_spawn() -> void:
	var noeud := get_node_or_null("ZoneSpawnIAPrototype2")
	if noeud == null:
		return
	var mi := noeud as MeshInstance3D
	if mi == null or not (mi.mesh is BoxMesh):
		return
	(mi.mesh as BoxMesh).size = Vector3(spawn_demi_cote * 2.0, 0.4, spawn_demi_cote * 2.0)

# Un lot de cubes par intervalle, jusqu'au plafond.
func _tick_spawn(delta: float) -> void:
	if not spawn_actif:
		return
	_horloge_spawn += delta
	if _horloge_spawn < intervalle_spawn:
		return
	_horloge_spawn = 0.0
	var zone := get_node_or_null("ZoneSpawnIAPrototype2") as Node3D
	if zone == null:
		return
	var centre: Vector3 = zone.global_position
	for _n in range(cubes_par_cycle):
		if _ennemis.size() >= max_cubes:
			return
		_spawner_un_cube(centre)

# Position aleatoire seedee dans le demi-cote, snappee au sol par carte.sommet.
# Le cube est une ENTITE conforme au contrat de perception.gd, inscrite au Monde.
func _spawner_un_cube(centre: Vector3) -> void:
	var x := centre.x + _rng.randf_range(-spawn_demi_cote, spawn_demi_cote)
	var z := centre.z + _rng.randf_range(-spawn_demi_cote, spawn_demi_cote)
	var y := centre.y
	if _carte != null:
		var y_sol: Variant = _carte.sommet(x, z)
		if y_sol == null:
			return  # colonne hors carte -- pas de cube ici
		# +0.4 = demi-hauteur du cube (0.8), pour qu'il repose sur le sol.
		y = float(y_sol) + 0.4
	var cube := {
		"id": "cube_vert_%d" % _prochain_id_cube,
		"position": Vector3(x, y, z),
		"proprietes": {
			"canaux": ["vue"],
			"canaux_config": {
				"vue": {"portee": 30.0, "angle": 120.0, "sensibilite": 1.0},
			},
			"formes": [{"type": "boite", "transform_locale": Transform3D.IDENTITY, "parametres": {"demi_taille": Vector3(0.4, 0.4, 0.4)}}],
			"masque_collision": 1,
			"masque_reponse": 1,
			"reponse": "bloque",
			# Velocite gardee a ZERO : cote collision le cube est l'ANCRE immobile
			# (le joueur encaisse la separation). Son errance deplace sa position
			# de ~0.075/tick, bien sous le seuil swept -- rien a tenir cote swept.
			"velocite": Vector3.ZERO,
			"orientation": Basis.IDENTITY,
		},
		"noeud": null,
		"direction": Vector3.ZERO,
		"cap_horloge": 0.0,
	}
	cube.proprietes["aabb_cache"] = Collision.aabb_forme(
		cube.proprietes.formes[0],
		Transform3D(Basis.IDENTITY, cube.position))
	_prochain_id_cube += 1
	_nouveau_cap(cube)
	_ennemis.append(cube)
	if _monde != null:
		_monde.ajouter(cube, "cube_vert", cube.position)

# ERRANCE (comportement par defaut) : chaque cube avance sur son cap, snappe au
# sol, jusqu'a buter (pente > cote_cellule, ou bord de carte) ou a ce que son
# horloge de cap expire -- alors il retire un cap au hasard. Mouvement data-pur ;
# le TERRAIN est resolu par _deplacement_horizontal_valide, commun au joueur.
func _tick_errance(delta: float) -> void:
	if _carte == null:
		return
	for cube in _ennemis:
		cube.cap_horloge -= delta
		if cube.cap_horloge <= 0.0:
			_nouveau_cap(cube)
		var pos: Vector3 = cube.position
		var dep: Vector3 = (cube.direction as Vector3) * vitesse_errance * delta
		# hauteur_ref = sommet actuel du cube (il colle au sol) ; marche d'une cellule.
		var sol_a_v: Variant = _carte.sommet(pos.x, pos.z)
		var sol_a: float = float(sol_a_v) if sol_a_v != null else pos.y
		var r: Dictionary = _deplacement_horizontal_valide(pos, dep, sol_a, _cote_cellule)
		if r.bloque:
			_nouveau_cap(cube)  # bord de carte ou pente trop raide
			continue
		# Le cube colle au sol (pas de gravite) : snap direct au sommet + demi-cube.
		cube.position = Vector3(r.xz.x, float(r.sol) + 0.4, r.xz.z)
		if _monde != null:
			_monde.deplacer(cube)

# TERRAIN COMMUN CUBES + JOUEUR. Etant donne une position et un deplacement
# horizontal candidat, dit si le pas est bloque et rend la position horizontale
# retenue et le sommet du sol a cet endroit. Bloque si bord de carte, ou si le
# sol devant depasse `hauteur_ref` de plus que `marche_max` :
#   - cube : hauteur_ref = son sommet actuel (il colle au sol), marche_max =
#     cote_cellule (il franchit une marche d'une cellule, garde son errance) ;
#   - joueur : hauteur_ref = ses PIEDS (pos.y), marche_max = MARCHE_JOUEUR (~0) --
#     tout obstacle qui depasse les pieds arrete, et en l'air au-dessus d'un cube
#     les pieds sont hauts, donc il passe et retombe dessus.
# AUCUNE verticale ici (chute/snap) : l'appelant en decide (le cube colle, le
# joueur tombe). Rend { bloque: bool, xz: Vector3, sol: float }.
func _deplacement_horizontal_valide(pos: Vector3, dep_horizontal: Vector3, hauteur_ref: float, marche_max: float) -> Dictionary:
	var candidat: Vector3 = pos + Vector3(dep_horizontal.x, 0.0, dep_horizontal.z)
	var y_sol_c: Variant = _carte.sommet(candidat.x, candidat.z)
	if y_sol_c == null:
		return {"bloque": true, "xz": pos, "sol": pos.y}  # bord de carte
	if float(y_sol_c) - hauteur_ref > marche_max:
		return {"bloque": true, "xz": pos, "sol": hauteur_ref}  # obstacle trop haut
	return {"bloque": false, "xz": candidat, "sol": float(y_sol_c)}

# Cap horizontal au hasard (RNG seede) + horloge avant le prochain changement.
func _nouveau_cap(cube: Dictionary) -> void:
	var a: float = _rng.randf() * TAU
	cube.direction = Vector3(cos(a), 0.0, sin(a))
	cube.cap_horloge = _rng.randf_range(2.0, 4.0)

# UN PAS DE JOUEUR, EN DONNEE PURE, CHAQUE FRAME. Demande l'intention au nœud
# Personnage (appel direct), compose la velocite (horizontale pilotee + saut si
# au sol + gravite cumulee), resout le terrain par le meme chemin que les cubes,
# snappe au sol via carte.sommet et en derive au_sol. La collision contre les
# cubes est faite ensuite par _tick_collision.
func _pas_joueur(delta: float) -> void:
	if _entite_joueur.is_empty() or _observateur == null or _carte == null:
		return
	var p: Dictionary = _entite_joueur.proprietes
	var intent: Dictionary = {}
	if _observateur.has_method("intention_mouvement"):
		intent = _observateur.intention_mouvement(delta)
	var horiz: Vector3 = intent.get("horizontale", Vector3.ZERO)
	var ve: Vector3 = p.get("velocite", Vector3.ZERO)

	# HORIZONTALE : bloque par un MUR (pente raide devant), jamais par une pente
	# douce -- c'est ce qui laisse monter une rampe sans sauter et arrete un cube.
	# La pente se lit sur SONDE_PENTE (distance fixe), pas sur le pas.
	var pos: Vector3 = _entite_joueur.position
	var dep := Vector3(horiz.x, 0.0, horiz.z) * delta
	var dir_h := Vector3(horiz.x, 0.0, horiz.z)
	if dir_h.length() > 0.0001:
		var dir_n := dir_h.normalized()
		var sonde: Vector3 = pos + dir_n * SONDE_PENTE
		var sol_sonde: Variant = _carte.sommet(sonde.x, sonde.z)
		var passe := true
		if sol_sonde == null:
			passe = false  # bord de carte
		elif float(sol_sonde) > pos.y + MARCHE_JOUEUR:
			# obstacle devant : montable seulement si la pente est douce.
			var sol_pieds: Variant = _carte.sommet(pos.x, pos.z)
			var ref: float = float(sol_pieds) if sol_pieds != null else pos.y
			var pente: float = (float(sol_sonde) - ref) / SONDE_PENTE
			if pente > PENTE_MAX:
				passe = false  # mur : il faut sauter
		if passe:
			pos.x += dep.x
			pos.z += dep.z

	# VERTICALE : saut (si au sol au tick precedent) puis gravite cumulee.
	var gravite: float = float(p.get("gravite", 18.0))
	if bool(intent.get("saut", false)) and bool(p.get("au_sol", false)):
		ve.y = float(intent.get("vitesse_saut", 8.5))
	ve.y -= gravite * delta
	pos.y += ve.y * delta

	# SOL sous la position finale : snap et au_sol (comme les cubes lisent le sol).
	var y_sol: Variant = _carte.sommet(pos.x, pos.z)
	var au_sol := false
	if y_sol != null and pos.y <= float(y_sol):
		pos.y = float(y_sol)
		ve.y = 0.0
		au_sol = true

	# La velocite horizontale est enregistree (swept collision + resume d'etat).
	ve.x = horiz.x
	ve.z = horiz.z
	p["velocite"] = ve
	p["au_sol"] = au_sol
	_entite_joueur.position = pos
	if _monde != null:
		_monde.deplacer(_entite_joueur)

# Getter de l'entite joueur (lue par personnage.gd a l'injection, et par de
# futurs tests). Rend le Dictionary vivant, pas une copie.
func entite_joueur() -> Dictionary:
	return _entite_joueur

# Horloge de perception POSEE, corps VIDE : la perception n'est pas branchee.
func _tick_perception(_delta: float) -> void:
	pass

# COLLISION generaliste joueur-vs-cubes en donnee pure. Liste des entites (joueur
# + cubes), Collision.tick puis Collision.resoudre (qui mute les positions des
# entites en contact), puis re-sync du Monde pour ce qui a bouge. Le joueur est
# le seul mobile (velocite != 0) : il encaisse la separation, les cubes-ancres ne
# bougent pas.
func _tick_collision(delta: float) -> void:
	if _monde == null or delta <= 0.0:
		return
	var entites: Array = []
	if not _entite_joueur.is_empty():
		entites.append(_entite_joueur)
	for cube in _ennemis:
		entites.append(cube)
	if entites.size() < 2:
		return
	var contacts: Array = Collision.tick(_monde, entites, delta)
	Collision.resoudre(contacts, entites)
	if not _entite_joueur.is_empty():
		_monde.deplacer(_entite_joueur)
	for cube in _ennemis:
		_monde.deplacer(cube)

# Trace de debug : une ligne par seconde prouvant que la position vient bien de la
# donnee (pos/vel/au_sol de l'entite joueur).
func _tracer_joueur(delta: float) -> void:
	if _entite_joueur.is_empty():
		return
	_horloge_trace += delta
	if _horloge_trace < INTERVALLE_TRACE:
		return
	_horloge_trace = 0.0
	var p: Dictionary = _entite_joueur.proprietes
	print("joueur pos=%s vel=%s au_sol=%s" % [
		_entite_joueur.position, p.get("velocite", Vector3.ZERO), p.get("au_sol", false)])

# Chargement direct d'un catalogue JSON. push_warning + Dictionary vide sur toute
# erreur (fichier absent, illisible, JSON non-objet).
func _charger_json(chemin: String) -> Dictionary:
	if not FileAccess.file_exists(chemin):
		push_warning("manager_proto_2 : catalogue introuvable : %s" % chemin)
		return {}
	var texte := FileAccess.get_file_as_string(chemin)
	if texte.is_empty():
		push_warning("manager_proto_2 : catalogue vide ou illisible : %s" % chemin)
		return {}
	var donnees = JSON.parse_string(texte)
	if not (donnees is Dictionary):
		push_warning("manager_proto_2 : JSON invalide (pas un objet) : %s" % chemin)
		return {}
	return donnees

# Streaming du rendu par distance -- dans le rayon on instancie, au-dela on libere
# et on remet la reference a null. La donnee, elle, reste.
func _bascule_rendu() -> void:
	if _observateur == null:
		return
	var pos_obs: Vector3 = _observateur.global_position
	var parent := get_parent()
	if parent == null:
		return
	var r2 := rayon_rendu * rayon_rendu
	for e in _ennemis:
		var d2: float = ((e.position as Vector3) - pos_obs).length_squared()
		if d2 < r2:
			if e.noeud == null or not is_instance_valid(e.noeud):
				var n := _creer_visuel()
				parent.add_child(n)
				n.global_position = e.position
				e.noeud = n
			else:
				(e.noeud as Node3D).global_position = e.position
		else:
			if e.noeud != null and is_instance_valid(e.noeud):
				e.noeud.queue_free()
				e.noeud = null

func _creer_visuel() -> MeshInstance3D:
	var cube := MeshInstance3D.new()
	cube.mesh = _mesh_ennemi
	cube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return cube
