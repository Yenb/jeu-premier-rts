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
# ERRANCE. Chaque tick physique, pour chaque individu du pool (for-in sur
# individus, aucun index construit) :
# 1. cap_horloge -= delta ; a <= 0, tirer une nouvelle direction et nouvelle
#    horloge dans [3, 8] s.
# 2. Poser velocite_desiree_horizontale = direction * proprietes.vitesse
#    (vitesse vient du type mobile_test, lue via proprietes).
# 3. Mouvement.pas_simple(individu, delta, null, carte) -- appel DIRECT au
#    pas partage. monde = null : ce banc n'interroge jamais l'index spatial
#    (aucun choses_dans_rayon), donc pas_simple saute monde.deplacer. Un
#    futur chantier de perception devra rebrancher _monde ici.
# 4. mm.set_instance_transform(slot, ...) INLINE : slot lu directement dans
#    individu.proprietes._slot, plus d'appel a Peuplement.ecrire_transform*.
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
const Mouvement = preload("res://scripts/mouvement_kinematic.gd")

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
# LES COLONNES PARALLELES DU POOL, tenues par peuplement.gd, remplies par le
# banc au spawn. Le hot loop n'accede plus a individu.proprietes ni n'appelle
# pas_simple par agent : il lit/mute les colonnes directement et invoque
# Mouvement.pas_simple_lot une fois. Les colonnes restent alignees quand un
# agent est retire (peuplement fait le meme swap-remove sur chaque colonne),
# ce qui prepare la population dynamique du vrai jeu.
const GRAVITE_LOT := 18.0

func _ready() -> void:
	_charger_reglages_locaux()
	_rng.seed = graine_rng
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
	# Colonnes paralleles declarees ici (peuplement les alloue vides et les tient
	# alignees) ; le banc les remplit au spawn et les mute en boucle.
	var colonnes := {
		"position": Vector3.ZERO,
		"velocite": Vector3.ZERO,
		"desiree": Vector3.ZERO,
		"direction": Vector3.ZERO,
		"au_sol": false,
		"cap_horloge": 0.0,
		"vitesse": 1.0,
		"slot": 0,
	}
	_pool = Peuplement.creer_pool(nombre_individus * 2, mesh, get_viewport().get_world_3d().scenario, colonnes)

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
		# Etat d'errance dans proprietes : direction horizontale + horloge de cap.
		# Meme ordre de tirage RNG que l'ancien code (direction puis horloge) --
		# le determinisme de la graine est preserve.
		p["errance_direction"] = _nouvelle_direction()
		p["errance_cap_horloge"] = _rng.randf_range(3.0, 8.0)
		poses += 1
	if poses < nombre_individus:
		push_error("banc_peuplement : seulement %d/%d individus poses (%d tentatives)" % [poses, nombre_individus, tentatives])
	# Remplir les colonnes du pool en batch (peuplement les a appendees vides
	# a chaque spawn ; le banc y ecrit les vraies valeurs). Depack / mute /
	# repack par colonne (CoW). Ordre = ordre de _pool.individus.
	_remplir_colonnes_depuis_individus()


func _remplir_colonnes_depuis_individus() -> void:
	var individus: Array = _pool.individus
	var n: int = individus.size()
	var cols: Dictionary = _pool.colonnes
	var positions: PackedVector3Array = cols.position
	var velocites: PackedVector3Array = cols.velocite
	var desirees: PackedVector3Array = cols.desiree
	var directions: PackedVector3Array = cols.direction
	var cap_horloges: PackedFloat32Array = cols.cap_horloge
	var vitesses: PackedFloat32Array = cols.vitesse
	var au_sols: PackedByteArray = cols.au_sol
	var slots: PackedInt32Array = cols.slot
	var i: int = 0
	while i < n:
		var individu: Dictionary = individus[i]
		var p: Dictionary = individu.proprietes
		positions[i] = individu.position
		velocites[i] = p.get("velocite", Vector3.ZERO)
		desirees[i] = p.get("velocite_desiree_horizontale", Vector3.ZERO)
		directions[i] = p.get("errance_direction", Vector3.ZERO)
		cap_horloges[i] = float(p.get("errance_cap_horloge", 0.0))
		vitesses[i] = float(p.get("vitesse", 1.0))
		au_sols[i] = 1 if bool(p.get("au_sol", false)) else 0
		slots[i] = int(p.get("_slot", -1))
		i += 1
	cols.position = positions
	cols.velocite = velocites
	cols.desiree = desirees
	cols.direction = directions
	cols.cap_horloge = cap_horloges
	cols.vitesse = vitesses
	cols.au_sol = au_sols
	cols.slot = slots

func _physics_process(delta: float) -> void:
	if _pool.is_empty():
		return
	var carte = _carte
	var cols: Dictionary = _pool.colonnes
	var count: int = (_pool.individus as Array).size()
	if count == 0:
		return
	# PASSE ERRANCE sur les colonnes. Depack CoW en tete, muter, REPACK.
	var directions: PackedVector3Array = cols.direction
	var cap_horloges: PackedFloat32Array = cols.cap_horloge
	var vitesses: PackedFloat32Array = cols.vitesse
	var desirees: PackedVector3Array = cols.desiree
	var i: int = 0
	while i < count:
		var horloge: float = cap_horloges[i] - delta
		var direction: Vector3 = directions[i]
		if horloge <= 0.0:
			direction = _nouvelle_direction()
			directions[i] = direction
			horloge = _rng.randf_range(3.0, 8.0)
		cap_horloges[i] = horloge
		desirees[i] = direction * vitesses[i]
		i += 1
	cols.direction = directions
	cols.cap_horloge = cap_horloges
	cols.desiree = desirees
	# UNE SEULE passe physique sur tout le lot. pas_simple_lot repack lui-meme
	# position / velocite / au_sol dans cols avant de rendre.
	Mouvement.pas_simple_lot(cols, count, GRAVITE_LOT, delta, carte)
	# TAMPON UNIQUE : ecrire les 3 floats d'origine par slot depuis cols.position,
	# pousser au mm et reassigner _pool.buffer (piege CoW, meme que le round 7).
	var positions: PackedVector3Array = cols.position
	var slots: PackedInt32Array = cols.slot
	var buffer: PackedFloat32Array = _pool.buffer
	i = 0
	while i < count:
		var slot: int = slots[i]
		if slot >= 0:
			var base: int = slot * 12
			var pos: Vector3 = positions[i]
			buffer[base + 3] = pos.x
			buffer[base + 7] = pos.y
			buffer[base + 11] = pos.z
		i += 1
	(_pool.mm as MultiMesh).buffer = buffer
	_pool["buffer"] = buffer

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
