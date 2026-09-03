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
# une INTENTION de mouvement, et c'est CE MANAGER qui la transmet a l'entite
# joueur, en donnee pure. Le manager NE CALCULE PLUS le mouvement lui-meme :
# _pas_joueur demande l'intention au Personnage (appel direct, sans course
# d'ordre), la POSE sur l'entite (velocite_desiree_horizontale, saut_demande,
# vitesse_saut), puis DELEGUE le pas au framework partage via
# Tick.tick_entite(..., politique_intrinseque, ...). Le pas lui-meme -- gravite,
# blocage terrain au rayon de la capsule, snap-sol borne, collision joueur-cubes
# (GJK/EPA) et calcul du dessus du cube porteur -- vit UNE SEULE FOIS dans
# scripts/mouvement_kinematic.gd (profil "complet"), partage avec tout mobile.
# profil "complet" + cadence_tick 1 : la simulation ne depend pas de l'observateur
# (temps du monde uniforme). En fin de _physics_process, la position data est
# recopiee dans le nœud (le rendu suit la donnee, seule autorite).
#
# COLLISION GENERALISTE EN DONNEE PURE (modele Orion, a reutiliser pour tout
# futur objet interactif) : la collision inter-entites ne passe PAS par des nœuds
# Godot (StaticBody3D / CollisionShape3D / PhysicsServer3D) mais par
# jeu/Proto/collision.gd applique sur des Dictionary d'entites portant leurs
# `formes`. Pour le joueur, cette collision est faite DANS le pas partage
# (mouvement_kinematic.gd, profil "complet") -- le manager ne la declenche plus a
# part.
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
# Framework de tick + mouvement partage : le joueur delegue son pas (gravite,
# blocage, snap, collision) a Tick, qui appelle mouvement_kinematic.gd. Le manager
# ne calcule plus le mouvement.
const Tick = preload("res://scripts/tick.gd")

const INTERVALLE_PERCEPTION := 0.1

@export_group("Rendu")
# Hysteresis : une entite instancie son noeud quand elle passe SOUS
# rayon_rendu_entrer, et le libere quand elle passe AU-DESSUS de
# rayon_rendu_sortir. L'ecart evite le flip-flop au bord (entite qui oscille
# entre les deux etats sans parcourir la difference entre les deux rayons).
@export var rayon_rendu_entrer: float = 60.0
@export var rayon_rendu_sortir: float = 65.0

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

func _ready() -> void:
	# GROUPE "manager_proto" : le Personnage retrouve CE manager (il expose
	# entite_joueur()) pour propager sa taille a la collision data. Le groupe peut
	# contenir plusieurs managers -- le consommateur itere et teste has_method.
	add_to_group(&"manager_proto")
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
		# SOURCE UNIQUE : la taille et la gravite du joueur sont des @export du
		# Personnage. Le manager les LIT pour fabriquer la forme de collision data --
		# ainsi collision et visuel suivent le MEME reglage (voir personnage.gd).
		var hauteur_capsule := _lire_reglage("hauteur_capsule", 1.8)
		var gravite := _lire_reglage("gravite", 18.0)
		# RAYON EFFECTIF lu du Personnage (rayon = ratio * hauteur, deja borne a
		# hauteur/2). Collision et visuel partagent la meme source, donc la meme
		# taille : reduire la hauteur rapetisse les deux ensemble.
		var rayon_capsule := hauteur_capsule * 0.5
		if _observateur.has_method("rayon_effectif"):
			rayon_capsule = float(_observateur.rayon_effectif())
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
				# Copies lues du Personnage : la collision porte la taille reglee, et
				# le pas partage lit la gravite ici.
				"rayon_capsule": rayon_capsule,
				"hauteur_capsule": hauteur_capsule,
				"gravite": gravite,
				"au_sol": false,
				# Contrat Mouvement + Tick (framework partage). profil "complet" +
				# cadence 1 : tick chaque frame, simulation independante de l'observateur.
				# L'intention (horizontale, saut) est POSEE chaque frame par _pas_joueur ;
				# y_appui_entite est calcule par le pas partage (dessus du cube porteur).
				"profil": "complet",
				"cadence_tick": 1,
				"saut_demande": false,
				"vitesse_saut": 8.5,
				"velocite_desiree_horizontale": Vector3.ZERO,
				"y_appui_entite": -INF,
			},
		}
		_entite_joueur.proprietes["aabb_cache"] = Collision.aabb_forme(
			_entite_joueur.proprietes.formes[0],
			Transform3D(Basis.IDENTITY, _entite_joueur.position))
		_monde.ajouter(_entite_joueur, "joueur", _entite_joueur.position)
		# Force la propagation initiale des dimensions : _appliquer_dimensions du
		# personnage lit _entite_joueur via get_nodes_in_group. Si son propre _ready a
		# tourne AVANT ce point, _entite_joueur etait vide et la propagation a ete
		# skippee. On la redemande maintenant que le Dictionary existe -- appel
		# synchrone, sans dependre du call_deferred du personnage.
		if _observateur.has_method("_appliquer_dimensions"):
			_observateur.call("_appliquer_dimensions")

# Lit un reglage @export sur l'observateur (le Personnage), ou un defaut s'il est
# absent -- la taille et la gravite du joueur ont leur source sur ce nœud.
func _lire_reglage(cle: String, defaut: float) -> float:
	if _observateur != null and cle in _observateur:
		return float(_observateur.get(cle))
	return defaut

# TICK EN _physics_process : l'interpolation physique est active (project.godot),
# donc tout transform (position joueur, nœuds cubes) doit etre pose dans le pas
# physique -- sinon Godot interpole depuis une source idle et avertit. Le rendu
# est alors LISSE entre deux pas physiques, gratuitement.
func _physics_process(delta: float) -> void:
	_tick_spawn(delta)
	_tick_errance(delta)
	_pas_joueur(delta)
	_bascule_rendu()
	_horloge_perception += delta
	if _horloge_perception >= INTERVALLE_PERCEPTION:
		_horloge_perception = 0.0
		_tick_perception(delta)
	# Le rendu suit la donnee : le manager (seule autorite de position) recopie la
	# position data du joueur dans son nœud. Le Personnage ne touche que sa
	# rotation et sa camera.
	if not _entite_joueur.is_empty() and _observateur != null:
		_observateur.global_position = _entite_joueur.position

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

# UN PAS DE JOUEUR : POSE L'INTENTION, DELEGUE LE PAS AU FRAMEWORK. Le manager ne
# calcule plus le mouvement -- il demande l'intention au Personnage (horizontale +
# saut), la depose sur l'entite joueur, et laisse Tick + Mouvement (profil
# "complet") faire gravite, blocage, snap-sol et collision joueur-cubes. Le pas
# vit UNE SEULE FOIS dans scripts/mouvement_kinematic.gd, partage avec tout mobile.
func _pas_joueur(delta: float) -> void:
	if _entite_joueur.is_empty() or _observateur == null:
		return
	var intent: Dictionary = {}
	if _observateur.has_method("intention_mouvement"):
		intent = _observateur.intention_mouvement(delta)
	var horiz: Vector3 = intent.get("horizontale", Vector3.ZERO)
	var p: Dictionary = _entite_joueur.proprietes
	p["velocite_desiree_horizontale"] = Vector3(horiz.x, 0.0, horiz.z)
	p["saut_demande"] = bool(intent.get("saut", false))
	p["vitesse_saut"] = float(intent.get("vitesse_saut", 8.5))
	Tick.tick_entite(_entite_joueur, Callable(Tick, "politique_intrinseque"), delta, _monde, _carte)

# Getter de l'entite joueur (lue par personnage.gd a l'injection, et par de
# futurs tests). Rend le Dictionary vivant, pas une copie.
func entite_joueur() -> Dictionary:
	return _entite_joueur

# Horloge de perception POSEE, corps VIDE : la perception n'est pas branchee.
func _tick_perception(_delta: float) -> void:
	pass

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
	var r2_entrer := rayon_rendu_entrer * rayon_rendu_entrer
	var r2_sortir := rayon_rendu_sortir * rayon_rendu_sortir
	for e in _ennemis:
		var d2: float = ((e.position as Vector3) - pos_obs).length_squared()
		var a_noeud: bool = e.noeud != null and is_instance_valid(e.noeud)
		if a_noeud and d2 > r2_sortir:
			e.noeud.queue_free()
			e.noeud = null
		elif not a_noeud and d2 < r2_entrer:
			var n := _creer_visuel()
			parent.add_child(n)
			n.global_position = e.position
			e.noeud = n
		elif a_noeud:
			(e.noeud as Node3D).global_position = e.position

func _creer_visuel() -> MeshInstance3D:
	var cube := MeshInstance3D.new()
	cube.mesh = _mesh_ennemi
	cube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return cube
