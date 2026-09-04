extends Node

# A ajouter a CARTE.md dans le prochain chantier d'inventaire -- banc non
# encore documente dans la carte.
#
# BANC DE PEUPLEMENT (chantier "peuplement + rendu MultiMesh", etape 2 M1a).
# Monte une scene d'observation minimale et depose 100 individus qui errent
# aleatoirement sur le terrain, via scripts/peuplement.gd (mecanisme static)
# comme orchestrateur et scripts/tick.gd + mouvement_kinematic.gd (profil
# "simple") pour le pas physique.
#
# CE BANC TIENT L'ETAT DU POOL. Peuplement.gd est static et n'a pas de var
# membre : c'est le banc qui detient le Dictionary _pool retourne par
# Peuplement.creer_pool, l'itere dans _physics_process, et le detruit en
# _exit_tree. Cette repartition est doctrinale : le mecanisme est un
# orchestrateur, le banc est le seul depositaire de la vie du pool.
#
# UN BANC PEUT NOMMER UNE CATEGORIE (CLAUDE.md § ADN, exception documentee
# pour un banc jetable) : "mobile_test" et "boite_simple" apparaissent dans
# data/banc_peuplement.json (catalogue local du banc) et sont lus ici -- ni
# dans peuplement.gd, ni dans mesh_catalogue.gd, ni dans aucun mecanisme du
# coeur.
#
# CATALOGUE LOCAL data/banc_peuplement.json : chaque banc jetable porte son
# propre fichier de reglages (patron docs/design.md). Un nombre_individus,
# un type_id, un mesh_ref -- rien d'autre. Le banc lit ce fichier au _ready
# pour surcharger ses defauts @export.
#
# ERRANCE. Chaque tick physique, pour chaque individu du pool :
# 1. cap_horloge -= delta ; a <= 0, tirer une nouvelle direction et nouvelle
#    horloge dans [3, 8] s.
# 2. Poser velocite_desiree_horizontale = direction * proprietes.vitesse
#    (vitesse vient du type mobile_test, lue via proprietes).
# 3. Tick.tick_entite(individu, politique_intrinseque, delta, monde, carte) --
#    delegue au pas partage (gravite, snap sol, blocage marche).
# 4. Peuplement.ecrire_transform(_pool, id) -- reflete la nouvelle position sur
#    l'instance RS du slot.
#
# Camera plongeante, lumiere directionnelle sans ombre, sol visuel decoratif.
# Groupe "observateur" pose sur la camera par convention du framework.
#
# ECART FRAMEWORK : ce banc + son catalogue local sont neufs, voir CLAUDE.md
# § Frontiere.

const CarteTerrain = preload("res://jeu/terrain/carte_terrain.gd")
const Monde = preload("res://scripts/monde.gd")
const Peuplement = preload("res://scripts/peuplement.gd")
const MeshCatalogue = preload("res://scripts/mesh_catalogue.gd")
const Tick = preload("res://scripts/tick.gd")

const CHEMIN_CATALOGUE_LOCAL := "res://data/banc_peuplement.json"

# Defauts surcharges par data/banc_peuplement.json si present.
@export var nombre_individus: int = 100
@export var type_id: String = "mobile_test"
@export var mesh_ref: String = "boite_simple"
@export var demi_zone_spawn: float = 40.0
@export var graine_rng: int = 20260904

var _pool: Dictionary = {}
var _monde = null
var _carte: Resource = null
var _catalogue: Dictionary = {}
var _rng := RandomNumberGenerator.new()
# Etat d'errance par individu, index par id (le pool ne le porte pas -- c'est
# du comportement, pas de la structure). direction est horizontale (y = 0),
# cap_horloge est en secondes.
var _errance: Dictionary = {}
var _politique: Callable

func _ready() -> void:
	_charger_reglages_locaux()
	_rng.seed = graine_rng
	_politique = Callable(Tick, "politique_intrinseque")
	_monter_scene()
	_monter_pool()
	_fabriquer_lot()

func _charger_reglages_locaux() -> void:
	if not FileAccess.file_exists(CHEMIN_CATALOGUE_LOCAL):
		return
	var texte := FileAccess.get_file_as_string(CHEMIN_CATALOGUE_LOCAL)
	if texte.is_empty():
		push_warning("banc_peuplement : catalogue local vide (%s)" % CHEMIN_CATALOGUE_LOCAL)
		return
	var donnees = JSON.parse_string(texte)
	if not (donnees is Dictionary):
		push_warning("banc_peuplement : catalogue local invalide (pas un objet)")
		return
	# Surcharge des @export si les cles sont presentes ; sinon defauts.
	if donnees.has("nombre_individus"):
		nombre_individus = int(donnees.nombre_individus)
	if donnees.has("type_id"):
		type_id = String(donnees.type_id)
	if donnees.has("mesh_ref"):
		mesh_ref = String(donnees.mesh_ref)
	if donnees.has("demi_zone_spawn"):
		demi_zone_spawn = float(donnees.demi_zone_spawn)
	if donnees.has("graine_rng"):
		graine_rng = int(donnees.graine_rng)

func _monter_scene() -> void:
	# CarteTerrain plate au defaut neutre : demi_cote=150 (300x300 cellules),
	# couches_pleines=7 -> sommet = couche 6 -> y=12.
	_carte = CarteTerrain.new()
	# Sol visuel decoratif : un PlaneMesh pour voir un sol. Aucun impact sur la
	# logique -- carte.sommet reste la seule autorite.
	var sol := MeshInstance3D.new()
	var plan := PlaneMesh.new()
	plan.size = Vector2(600.0, 600.0)
	var mat_sol := StandardMaterial3D.new()
	mat_sol.albedo_color = Color(0.3, 0.3, 0.3)
	plan.material = mat_sol
	sol.mesh = plan
	sol.position = Vector3(0.0, 12.0, 0.0)
	add_child(sol)
	var lumiere := DirectionalLight3D.new()
	lumiere.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(30.0), 0.0)
	lumiere.light_energy = 1.0
	lumiere.shadow_enabled = false
	add_child(lumiere)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 55.0, 55.0)
	camera.current = true
	camera.add_to_group(&"observateur")
	add_child(camera)
	# look_at exige que le Node soit dans l'arbre.
	camera.look_at(Vector3(0.0, 12.0, 0.0), Vector3.UP)

func _monter_pool() -> void:
	_monde = Monde.new()
	# Le banc charge le catalogue types.json et le passe au mecanisme --
	# Peuplement lui-meme n'ouvre jamais un fichier.
	_catalogue = _charger_types()
	# Le banc resout le Mesh depuis le catalogue mesh -- meme raison.
	var catalogue_mesh: Dictionary = MeshCatalogue.charger()
	if not catalogue_mesh.has(mesh_ref):
		push_error("banc_peuplement : mesh_ref '%s' absent de data/mesh.json, aucun rendu possible" % mesh_ref)
		return
	var mesh: Mesh = MeshCatalogue.fabriquer_mesh(catalogue_mesh[mesh_ref])
	if mesh == null:
		push_error("banc_peuplement : MeshCatalogue.fabriquer_mesh('%s') a rendu null" % mesh_ref)
		return
	# Taille du pool = capacite avec un peu de marge -- des chantiers ulterieurs
	# pourront spawn/kill dynamiquement sans re-allouer.
	# Node (pas Node3D) : pas de get_world_3d() direct. Passer par le Viewport.
	_pool = Peuplement.creer_pool(nombre_individus * 2, mesh, get_viewport().get_world_3d().scenario)

func _fabriquer_lot() -> void:
	if _pool.is_empty():
		return
	var poses := 0
	var tentatives := 0
	while poses < nombre_individus and tentatives < nombre_individus * 10:
		tentatives += 1
		var x: float = _rng.randf_range(-demi_zone_spawn, demi_zone_spawn)
		var z: float = _rng.randf_range(-demi_zone_spawn, demi_zone_spawn)
		var y_sol_v: Variant = _carte.sommet(x, z)
		if y_sol_v == null:
			continue
		# +0.4 = demi-hauteur d'une boite_simple (0.8), reglage porte ici et pas
		# dans peuplement.gd (agnostique du mesh).
		var position := Vector3(x, float(y_sol_v) + 0.4, z)
		var id: String = Peuplement.spawn(_pool, _catalogue, type_id, position, _monde)
		if id.is_empty():
			push_error("banc_peuplement : Peuplement.spawn a echoue a la tentative %d" % tentatives)
			return
		# Contrat Mouvement + Tick pose apres spawn (le banc decide du profil et
		# de la politique -- Peuplement les ignore par doctrine).
		var individu: Dictionary = _pool.individus[_pool.id_to_index[id]]
		var p: Dictionary = individu.proprietes
		p["profil"] = "simple"
		p["cadence_tick"] = 1
		p["velocite"] = Vector3.ZERO
		p["velocite_desiree_horizontale"] = Vector3.ZERO
		p["au_sol"] = false
		p["gravite"] = 18.0
		# Etat d'errance : direction horizontale + horloge de cap.
		_errance[id] = {
			"direction": _nouvelle_direction(),
			"cap_horloge": _rng.randf_range(3.0, 8.0),
		}
		poses += 1
	if poses < nombre_individus:
		push_error("banc_peuplement : seulement %d/%d individus poses (%d tentatives)" % [poses, nombre_individus, tentatives])

func _physics_process(delta: float) -> void:
	if _pool.is_empty():
		return
	for individu in _pool.individus:
		var id: String = String(individu.id)
		if not _errance.has(id):
			continue
		var etat: Dictionary = _errance[id]
		etat["cap_horloge"] = float(etat.cap_horloge) - delta
		if float(etat.cap_horloge) <= 0.0:
			etat["direction"] = _nouvelle_direction()
			etat["cap_horloge"] = _rng.randf_range(3.0, 8.0)
		var p: Dictionary = individu.proprietes
		var vitesse: float = float(p.get("vitesse", 1.0))
		p["velocite_desiree_horizontale"] = (etat.direction as Vector3) * vitesse
		Tick.tick_entite(individu, _politique, delta, _monde, _carte)
		Peuplement.ecrire_transform(_pool, id)

func _nouvelle_direction() -> Vector3:
	var angle: float = _rng.randf() * TAU
	return Vector3(cos(angle), 0.0, sin(angle))

func _charger_types() -> Dictionary:
	if not FileAccess.file_exists("res://data/types.json"):
		push_error("banc_peuplement : data/types.json introuvable")
		return {}
	var texte := FileAccess.get_file_as_string("res://data/types.json")
	var donnees = JSON.parse_string(texte)
	if not (donnees is Dictionary):
		push_error("banc_peuplement : data/types.json invalide")
		return {}
	return donnees

func _exit_tree() -> void:
	Peuplement.detruire_pool(_pool)
