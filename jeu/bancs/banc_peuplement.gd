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
# INTENTION. Deux chemins pour poser desiree = direction * vitesse :
#   separation_active=true : UN appel C++ separation_lot(cols.position,
#     rayon_separation) lit l'index (deja tenu par deplacer_lot) et rend une
#     direction unitaire de repulsion par unite -- les voisins dans rayon
#     poussent, sinon direction=0. desiree entierement ecrase. Premiere brique
#     d'IA de masse : perception + intention en une passe native, aucune
#     requete par unite. Exige deplacer_cpp=true et brancher_monde=true.
#   separation_active=false : ERRANCE. Pour chaque individu :
# 1. cap_horloge -= delta ; a <= 0, tirer une nouvelle direction et nouvelle
#    horloge dans [3, 8] s.
# 2. Poser desiree = direction * vitesse (vitesse vient du type mobile_test).
#
# ERRANCE (chemin separation_active=false). Chaque tick physique, pour chaque
# individu du pool (for-in sur individus, aucun index construit) :
# 1. cap_horloge -= delta ; a <= 0, tirer une nouvelle direction et nouvelle
#    horloge dans [3, 8] s.
# 2. Poser velocite_desiree_horizontale = direction * proprietes.vitesse
#    (vitesse vient du type mobile_test, lue via proprietes).
# 3. Physique + buffer fusionnes (physique_et_buffer GDScript, ou
#    PhysiqueSimpleLot C++ derriere @export utilise_cpp) mutent les colonnes
#    paralleles (cols.position, cols.velocite, cols.au_sol) et le buffer
#    MultiMesh (3 floats/slot).
# 4. mm.set_instance_transform(slot, ...) INLINE : slot lu directement dans
#    individu.proprietes._slot, plus d'appel a Peuplement.ecrire_transform*.
#
# MONDE (index spatial) BRANCHE derriere @export brancher_monde (defaut true) :
# les spawns inscrivent chaque unite dans _monde via `Peuplement.spawn(...,
# _monde, ...)`, et une passe supplementaire par frame recopie cols.position[i]
# vers individu.position puis appelle _monde.deplacer(individu). Cette
# duplication TRANSITOIRE tient une frame : les colonnes restent la verite
# tenue par la physique (aucun autre code ne lit individu.position pendant que
# la physique tourne), individu.position est un miroir ecrit juste avant chaque
# deplacer. Sans cette recopie, monde.gd verrait la position d'avant la
# physique -- l'index divergerait de la position vivante et une requete
# spatiale echouerait. brancher_monde=false : aucun spawn n'inscrit dans le
# monde, aucun deplacer par frame, comportement de l'ancien banc.
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
# RELEVE DE CHRONOS -- instrumentation seule, aucune optimisation (chantier
# "mesurer avant portage C++"). true : accumule trois postes du hot path
# (errance, physique+buffer, multimesh_set_buffer) en microsecondes et imprime
# UNE ligne par seconde ; false : aucune mesure, aucune impression, banc
# strictement identique. Reprend le patron des compteurs de monde.gd
# (requetes/cases_lues/candidats_mesures + remise a zero), instances a la place
# de static.
@export var actif_releve: bool = true
# CHEMIN C++ pour la boucle physique + buffer (chantier "portage C++ du poste
# physique du peuplement"). true : appel a PhysiqueSimpleLot depuis
# extension_terrain, GDScript rejoue seulement les indices renvoyes dans
# `indices_a_repasser` (miss table de sol -> repli sommet_sous cote GDScript).
# false : ancien chemin, physique_et_buffer GDScript entiere. Le chemin
# GDScript reste l'ORACLE de parite et le rollback ; scripts/test_physique_simple_lot_cpp.gd
# verrouille la parite bit a bit.
@export var utilise_cpp: bool = false
# BRANCHER MONDE (chantier "rebrancher l'index spatial + mesurer monde.deplacer").
# true : les spawns inscrivent chaque unite dans _monde, et une passe par frame
# recopie cols.position -> individu.position puis appelle _monde.deplacer.
# false : _monde = null, aucun spawn n'inscrit dans l'index, aucun deplacer par
# frame. Le poste `deplacer` du releve reste imprime a 0 sous false.
@export var brancher_monde: bool = true
# INDEX SPATIAL EN C++ (chantier "portage C++ deplacer_lot"). true : la boucle
# for j: _monde.deplacer_simple(individu) est remplacee par UN appel
# _index_cpp.deplacer_lot(cols.position) -- UNE traversee de frontiere par
# frame au lieu de 100 000. false : chemin GDScript (deplacer_simple), garde
# comme oracle et rollback. Verrouille par test_index_spatial_cpp.gd (parite
# bit a bit des cases entre index C++ et index GDScript).
@export var deplacer_cpp: bool = false
# SEPARATION (premiere brique d'IA de masse). true : la passe errance est
# remplacee par UN appel _index_cpp.separation_lot(cols.position, rayon_separation)
# qui rend UNE direction unitaire par unite (repulsion des voisins dans le rayon,
# lue depuis l'index C++ deja tenu par deplacer_lot). Le resultat ecrase
# cols.desiree : direction * vitesse. false : passe errance historique (cap
# horloge + tirage direction), separation ignoree. Exige deplacer_cpp=true et
# brancher_monde=true (sinon _index_cpp est null, repli automatique sur errance
# avec push_error). Verrouille par test_separation_cpp.gd (parite du calcul C++
# vs un oracle GDScript naif O(N^2)).
@export var separation_active: bool = false
# Rayon de perception pour la separation, en unites du monde. Le banc ouvre en
# plus du niveau deplacer (arete 16) un SECOND niveau dedie a la separation,
# d'exposant `ceil(log2(rayon_separation))` -- la case du niveau separation
# couvre le rayon sur chaque axe, la boucle interne de separation_lot ne voit
# qu'une poignee de voisins par case. Sans ce second niveau, la separation
# lisait le niveau du deplacer (arete 16 pour un rayon 2 : chaque case
# ramassait des milliers de candidats hors rayon, degeneration quasi-N^2
# local -- releve en jeu ~1 020 000 us / frame a N=100 000, 1 fps). Voir
# en-tete de extension_terrain/src/index_spatial.h::separation_lot.
@export var rayon_separation: float = 2.0
# PAQUETS PARTAGES (chantier "partage COW du paquet par defaut", 2026-09-08).
# true : Peuplement.spawn passe paquets_partages=true a Objet.fabriquer -- les
# sous-Dict/Array de premier niveau des paquets herites (objet_physique +
# dynamique pour mobile_test : reserves 5 canaux, deformation_etat, etats,
# engagement, canaux_config sur les types qui composent percevant...) sont
# PARTAGES PAR REFERENCE entre toutes les instances au lieu d'etre dupliques.
# A N=100 000, ce chantier vise la chute nette de la memoire statique (auparavant
# ~1 Go, plafond 1 Gio). Les ecritures que ce banc pose sur proprietes
# (profil/cadence_tick/velocite/velocite_desiree_horizontale/au_sol/gravite/
# errance_direction/errance_cap_horloge/_slot) sont TOUTES top-level : elles
# creent/remplacent des cles du Dict top-level neuf, elles ne mutent jamais un
# sous-Dict partage. Isolation verrouillee par scripts/test_objet_isolation.gd.
# false : comportement historique (deep copy complete a chaque fabrication).
@export var paquets_partages: bool = true

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
# VT = |Mouvement.VITESSE_TERMINALE| = 55.0 -- passe au C++ pour que la
# constante ne vive qu'a UN endroit dans le chemin GDScript (mouvement_kinematic.gd)
# et soit reflet ee cote natif. Si la constante change la, la passer via cette
# ligne fait suivre le C++ sans recompilation.
const VITESSE_TERMINALE_ABS := 55.0
# Instance C++ paresseuse, cree au premier appel utilise_cpp=true. null si le
# chemin C++ n'est jamais active OU si la classe n'est pas disponible (extension
# non chargee -- push_error, repli automatique sur GDScript).
var _physique_cpp: RefCounted = null
# INDEX SPATIAL C++ (chantier deplacer_cpp). Instance unique creee au
# _monter_pool si deplacer_cpp=true et brancher_monde=true. Un seul niveau
# ouvert a EXPOSANT_INDEX_CPP (arete 2^n) -- correspond au rayon de perception
# typique du peuplement (choses_dans_rayon eventuel restera GDScript pour ce
# chantier, cf. en-tete de scripts/index_spatial.h).
const EXPOSANT_INDEX_CPP := 4  # arete = 2^4 = 16
var _index_cpp: RefCounted = null

# ACCUMULATEURS DE CHRONOS -- lus par _imprimer_releve_si_seconde_ecoulee et
# remis a zero apres chaque impression. `_us_*` = microsecondes cumulees sur la
# seconde en cours, `_frames_accumulees` = nombre de _physics_process compris
# dans cette meme seconde (pour rendre la moyenne PAR FRAME). `_temps_prochain`
# = timestamp secondes de la prochaine impression (Time.get_ticks_msec / 1000).
var _us_errance: int = 0
var _us_separation: int = 0
var _us_physique_buffer: int = 0
var _us_multimesh: int = 0
# Poste `deplacer` : passe individu.position <- cols.position + N appels
# monde.deplacer(individu). Sous brancher_monde=false, reste a 0.
var _us_deplacer: int = 0
var _frames_accumulees: int = 0
var _temps_prochain_ms: int = 0

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
	if donnees.has("actif_releve"):
		actif_releve = bool(donnees.actif_releve)
	if donnees.has("utilise_cpp"):
		utilise_cpp = bool(donnees.utilise_cpp)
	if donnees.has("brancher_monde"):
		brancher_monde = bool(donnees.brancher_monde)
	if donnees.has("deplacer_cpp"):
		deplacer_cpp = bool(donnees.deplacer_cpp)
	if donnees.has("separation_active"):
		separation_active = bool(donnees.separation_active)
	if donnees.has("rayon_separation"):
		rayon_separation = float(donnees.rayon_separation)
	if donnees.has("paquets_partages"):
		paquets_partages = bool(donnees.paquets_partages)

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
	# brancher_monde=false : aucun Monde n'est cree, `null` circule aux spawns,
	# `_monde.deplacer` n'est jamais appele (voir en-tete du banc, section MONDE).
	# structure_simple=true : la subdivision adaptative est court-circuitee dans
	# ce Monde. Le peuplement est une population dont TOUS les individus bougent
	# CHAQUE frame -- la subdivision, prevue pour des tas denses statiques, coute
	# ~1.8 us par deplacer a N=100 000 (mesure) parce qu'elle re-remanie l'index
	# chaque appel. Sous structure_simple, deplacer devient un swap-remove +
	# append. Le comportement de choses_dans_rayon reste identique
	# (test_monde_structure_simple).
	if brancher_monde:
		_monde = Monde.new()
		_monde.structure_simple = true
	else:
		_monde = null
	# INDEX SPATIAL EN C++ (chantier "portage C++ deplacer_lot"). Instancie
	# UNE fois, configure a la taille pool. Deux niveaux ouverts sous
	# separation_active :
	#   - EXPOSANT_INDEX_CPP (arete 16) : niveau du deplacer, grand pour
	#     amortir le nombre de re-affectations de case par frame.
	#   - exposant_separation = ceil(log2(rayon_separation)) : niveau lu par
	#     separation_lot, arete du meme ordre que le rayon pour que la case
	#     couvre le voisinage sur chaque axe (regle arete <= rayon rejetee,
	#     c'est le piege documente). Sans ce second niveau, la separation
	#     lisait le niveau du deplacer et degenerait en quasi-N^2 local a
	#     N=100 000.
	# deplacer_lot met a jour TOUS les niveaux ouverts (patron IndexSpatial).
	# L'appelant garde le Ref vivant tant qu'il en a besoin (RefCounted, pas Node).
	if deplacer_cpp and brancher_monde:
		if not ClassDB.class_exists("IndexSpatial"):
			push_error("banc_peuplement : classe C++ 'IndexSpatial' introuvable -- extension_terrain non chargee ? Repli GDScript pour ce banc.")
			deplacer_cpp = false
		else:
			_index_cpp = ClassDB.instantiate("IndexSpatial")
			_index_cpp.configurer(nombre_individus * 2)
			_index_cpp.ouvrir_niveau(EXPOSANT_INDEX_CPP)
			if separation_active:
				# exposant tel que 2^exposant >= rayon_separation, minimal. Pour
				# rayon 2.0 : ceil(log2(2)) = 1 -> arete 2. Pour rayon 3.0 :
				# ceil(log2(3)) = 2 -> arete 4. Le C++ auto-selectionne ce
				# niveau via separation_lot (plus petit exposant tel que arete
				# >= rayon).
				var exposant_sep: int = int(ceil(log(maxf(rayon_separation, 1.0e-3)) / log(2.0)))
				_index_cpp.ouvrir_niveau(exposant_sep)
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
	# CHRONO DE CREATION : entoure la boucle entiere. En N=100 000, l'ancien
	# comportement (push RS par spawn) rendait ce poste dominant du chargement.
	# Un seul push final via `Peuplement.pousser_buffer` en fin de fonction ; ce
	# chrono prouvera le gain a l'ecran. Actif seulement sous actif_releve, meme
	# gate que les chronos par frame.
	var chrono_creation_debut: int = Time.get_ticks_usec() if actif_releve else 0
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
		# pousser=false : le push RS unique se fait apres la boucle, jamais par
		# unite (sinon O(N^2) sur le buffer entier).
		var id: String = Peuplement.spawn(_pool, _catalogue, type_id, position, _monde, false, paquets_partages)
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
	# PUSH RS UNIQUE : le buffer contient les 12 floats de chaque slot pose ci-dessus
	# (spawn(..., false) les ecrit sans pousser). Un seul envoi au serveur de rendu
	# pour tout le lot -- N=100 000, coup unique au lieu de N.
	Peuplement.pousser_buffer(_pool)
	# SEED DE L'INDEX C++ : sous separation_active, la separation lit l'index a la
	# frame N pour ecrire desiree, AVANT que la physique ne bouge et que deplacer_lot
	# ne soit rappele en queue. Sans ce seed, la frame 0 lirait un index vide et
	# rendrait direction=0 partout. Une passe de C++ ici, une fois pour toute la vie
	# du banc -- cout amorti a zero.
	if _index_cpp != null:
		var cols_seed: Dictionary = _pool.colonnes
		_index_cpp.deplacer_lot(cols_seed.position)
	if actif_releve:
		var duree_us: int = Time.get_ticks_usec() - chrono_creation_debut
		print("[peuplement] creation N=%d en %d us (push RS unique final)" % [poses, duree_us])


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
		directions[i] = p.get("errance_direction", Vector3.ZERO)
		cap_horloges[i] = float(p.get("errance_cap_horloge", 0.0))
		vitesses[i] = float(p.get("vitesse", 1.0))
		# desiree = direction * vitesse au spawn : la passe errance revisee du
		# round 11 ne reecrit desiree qu'a l'expiration de l'horloge ; sans
		# cette init, frame 1 partirait de Vector3.ZERO au lieu de la direction
		# tiree au spawn.
		desirees[i] = directions[i] * vitesses[i]
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
	var count: int = (_pool.individus as Array).size()
	if count == 0:
		return
	# CHRONOS -- trois postes du hot path, en microsecondes. Sous actif_releve
	# false, les trois `Time.get_ticks_usec()` sont EVITES au maximum (une
	# branche par poste plutot que trois inconditionnels) : instrumenter n'est
	# pas biaiser la mesure.
	var chrono_intention_debut: int = Time.get_ticks_usec() if actif_releve else 0
	# ROUND 11 (revise) : deux passes au lieu de trois.
	# PASSE 1 -- intention. Deux chemins :
	#   separation_active=true : UN appel C++ separation_lot(cols.position, rayon)
	#     rend une direction unitaire de repulsion par unite (voisinage lu dans
	#     l'index deja tenu). desiree[i] = direction * vitesse[i], ecrase
	#     entierement l'errance. Exige _index_cpp != null (deplacer_cpp + brancher_monde) ;
	#     sinon push_error et repli sur l'errance (le poste separation reste a 0).
	#   separation_active=false : errance historique. desiree[i] n'est reecrit QUE
	#     quand l'horloge expire (direction change) -- les autres frames, desiree
	#     conserve sa valeur.
	var cols: Dictionary = _pool.colonnes
	var vitesses: PackedFloat32Array = cols.vitesse
	var desirees: PackedVector3Array = cols.desiree
	var chrono_intention_fin: int = 0
	if separation_active and _index_cpp != null:
		# UN appel, tout le lot. Le C++ tient son index natif (unordered_map) et
		# lit les cases voisines touchees par rayon_separation. Sortie : direction
		# horizontale unitaire (Y=0) ou Vector3.ZERO si aucun voisin dans rayon.
		var directions_sep: PackedVector3Array = _index_cpp.separation_lot(cols.position, rayon_separation)
		var k: int = 0
		while k < count:
			desirees[k] = directions_sep[k] * vitesses[k]
			k += 1
		cols.desiree = desirees
		if actif_releve:
			chrono_intention_fin = Time.get_ticks_usec()
			_us_separation += chrono_intention_fin - chrono_intention_debut
	else:
		if separation_active and _index_cpp == null:
			push_error("banc_peuplement : separation_active=true mais _index_cpp null (deplacer_cpp=%s, brancher_monde=%s) -- repli sur errance." % [str(deplacer_cpp), str(brancher_monde)])
		var directions: PackedVector3Array = cols.direction
		var cap_horloges: PackedFloat32Array = cols.cap_horloge
		var repack_desiree: bool = false
		var repack_direction: bool = false
		var i: int = 0
		while i < count:
			var horloge: float = cap_horloges[i] - delta
			if horloge <= 0.0:
				var angle: float = _rng.randf() * TAU
				var direction := Vector3(cos(angle), 0.0, sin(angle))
				directions[i] = direction
				repack_direction = true
				horloge = _rng.randf_range(3.0, 8.0)
				desirees[i] = direction * vitesses[i]
				repack_desiree = true
			cap_horloges[i] = horloge
			i += 1
		cols.cap_horloge = cap_horloges
		if repack_direction:
			cols.direction = directions
		if repack_desiree:
			cols.desiree = desirees
		if actif_releve:
			chrono_intention_fin = Time.get_ticks_usec()
			_us_errance += chrono_intention_fin - chrono_intention_debut
	var chrono_physique_debut: int = chrono_intention_fin
	# PASSE 2 -- physique + buffer fusionnes. Deux chemins : C++ (chantier
	# "portage C++ du poste physique") derriere @export utilise_cpp, GDScript
	# sinon (chemin oracle, verrouille par test_tick_fusionne + test de parite
	# C++ vs GDScript). Le C++ traite tout ce qui est un HIT sur la table plate
	# de sol ; les indices ratant au moins un des trois tests sol repartent
	# GDScript sur physique_et_buffer_indices (repli sommet_sous). En regime
	# chaud, la liste est presque toujours vide.
	var buffer: PackedFloat32Array
	if utilise_cpp:
		buffer = _physique_et_buffer_cpp(cols, _pool.buffer, count, GRAVITE_LOT, delta, _carte)
	else:
		buffer = physique_et_buffer(cols, _pool.buffer, count, GRAVITE_LOT, delta, _carte)
	var chrono_deplacer_debut: int = 0
	if actif_releve:
		chrono_deplacer_debut = Time.get_ticks_usec()
		_us_physique_buffer += chrono_deplacer_debut - chrono_physique_debut
	# PASSE DEPLACER (chantier "rebrancher l'index spatial") : la physique a
	# mute cols.position (verite tenue par la boucle physique) mais PAS
	# individu.position (les Dictionary du pool). monde.gd:deplacer lit
	# chose.position, donc on RECOPIE colonne -> individu juste avant l'appel.
	# Duplication transitoire, une frame, aucun autre code ne lit
	# individu.position entre-temps. Sous brancher_monde=false, cette passe est
	# integralement sautee (aucune recopie, aucun deplacer, poste = 0).
	if brancher_monde:
		if deplacer_cpp and _index_cpp != null:
			# UN appel, tout le lot. Le C++ tient son index natif (unordered_map)
			# et met a jour les 100 000 unites en une passe (aucun franchissement
			# de frontiere par unite). L'index GDScript de _monde n'est plus tenu
			# a jour sous ce chemin -- voir en-tete scripts/index_spatial.h.
			_index_cpp.deplacer_lot(cols.position)
		elif _monde != null:
			var positions_apres: PackedVector3Array = cols.position
			var individus: Array = _pool.individus
			var j: int = 0
			while j < count:
				var individu: Dictionary = individus[j]
				individu.position = positions_apres[j]
				_monde.deplacer_simple(individu)
				j += 1
	var chrono_multimesh_debut: int = 0
	if actif_releve:
		chrono_multimesh_debut = Time.get_ticks_usec()
		_us_deplacer += chrono_multimesh_debut - chrono_deplacer_debut
	RenderingServer.multimesh_set_buffer((_pool.mm as MultiMesh).get_rid(), buffer)
	_pool["buffer"] = buffer
	if actif_releve:
		_us_multimesh += Time.get_ticks_usec() - chrono_multimesh_debut
		_frames_accumulees += 1
		_imprimer_releve_si_seconde_ecoulee(count)

# UNE LIGNE PAR SECONDE, jamais par frame -- format stable, prefixe "[peuplement]",
# valeurs en microsecondes moyennes PAR FRAME (accumule / frames de la seconde
# ecoulee). Remet les accumulateurs a zero apres chaque impression (patron
# monde.gd:remettre_les_compteurs). La toute premiere impression tombe apres la
# premiere seconde de jeu, jamais a t=0.
func _imprimer_releve_si_seconde_ecoulee(count: int) -> void:
	var maintenant_ms: int = Time.get_ticks_msec()
	if _temps_prochain_ms == 0:
		_temps_prochain_ms = maintenant_ms + 1000
		return
	if maintenant_ms < _temps_prochain_ms:
		return
	var frames: int = maxi(_frames_accumulees, 1)
	# Divisions promues en float pour eviter le warning GDScript "Integer division.
	# Decimal part will be discarded." au reload -- le format reste %d, arrondi au us.
	var inv_frames: float = 1.0 / float(frames)
	print("[peuplement] N=%d fps=%d errance=%dus separation=%dus phys+buffer=%dus deplacer=%dus mm_set=%dus" % [
		count,
		int(Engine.get_frames_per_second()),
		int(float(_us_errance) * inv_frames),
		int(float(_us_separation) * inv_frames),
		int(float(_us_physique_buffer) * inv_frames),
		int(float(_us_deplacer) * inv_frames),
		int(float(_us_multimesh) * inv_frames),
	])
	_us_errance = 0
	_us_separation = 0
	_us_physique_buffer = 0
	_us_deplacer = 0
	_us_multimesh = 0
	_frames_accumulees = 0
	_temps_prochain_ms = maintenant_ms + 1000


# PHYSIQUE + BUFFER FUSIONNES (round 11 revise) : une seule boucle sur count qui
# applique le corps physique de pas_simple_lot puis ecrit les trois floats
# d'origine du buffer MultiMesh du slot depuis la nouvelle position. Depack
# desiree/position/velocite/au_sol/slot + buffer en tete, repack en queue.
#
# MIROIR : le corps physique (S.2 a S.10) est une COPIE de
# scripts/mouvement_kinematic.gd::pas_simple_lot. Si l'un change, l'autre
# DOIT changer aussi. Commentaire croise pose la-bas.
# Le verrou de parite (meme resultat que pas_simple_lot + ecriture buffer
# separee) est scripts/test_tick_fusionne.gd.
#
# REGLAGES ROUND 11 REVISE :
# - floori(x) au lieu de int(floor(x)) dans les calculs d'index de sol.
# - inv_cote = 1.0 / cote et trois_sur_cote = 3.0 / cote precalcules,
#   les divisions par cote deviennent des multiplications.
#
# Static : la helper prend tout en parametre pour etre testable hors du banc.
static func physique_et_buffer(cols: Dictionary, buffer: PackedFloat32Array, count: int, gravite: float, delta: float, carte) -> PackedFloat32Array:
	if delta <= 0.0 or count <= 0 or carte == null:
		return buffer
	var desirees: PackedVector3Array = cols.desiree
	var positions: PackedVector3Array = cols.position
	var velocites: PackedVector3Array = cols.velocite
	var au_sols: PackedByteArray = cols.au_sol
	var slots: PackedInt32Array = cols.slot
	var cote: float = 2.0
	if "cote" in carte:
		cote = float(carte.cote)
	var inv_cote: float = 1.0 / cote
	var trois_sur_cote: float = 3.0 * inv_cote
	var table: PackedFloat32Array = carte.table_sommet()
	var demi_cote: int = int(carte.demi_cote)
	var cote_lin: int = 2 * demi_cote
	var g_dt: float = gravite * delta
	# VITESSE_TERMINALE = 55.0 (IDENTIQUE a Mouvement.VITESSE_TERMINALE dans
	# scripts/mouvement_kinematic.gd -- valeur constante du profil simple).
	var vt: float = -55.0
	var i: int = 0
	while i < count:
		# ---- PHYSIQUE (copie EXACTE de pas_simple_lot, S.2 a S.10) ----
		var ve: Vector3 = velocites[i]
		ve.y -= g_dt
		if ve.y < vt:
			ve.y = vt
		var vdh: Vector3 = desirees[i]
		ve.x = vdh.x
		ve.z = vdh.z
		var dep_x: float = ve.x * delta
		var dep_y: float = ve.y * delta
		var dep_z: float = ve.z * delta
		var pos: Vector3 = positions[i]
		# --- sol sous les pieds ---
		var x1: float = pos.x
		var z1: float = pos.z
		var ymax1: float = pos.y + cote
		var cx1: int = floori(x1 * inv_cote)
		var cz1: int = floori(z1 * inv_cote)
		var sol_ici_val: float = 0.0
		var sol_ici_present: bool = false
		if cx1 >= -demi_cote and cx1 < demi_cote and cz1 >= -demi_cote and cz1 < demi_cote:
			var xl1: float = x1 - float(cx1) * cote
			var zl1: float = z1 - float(cz1) * cote
			var ix1: int = clampi(floori(xl1 * trois_sur_cote), 0, 2)
			var iz1: int = clampi(floori(zl1 * trois_sur_cote), 0, 2)
			var idx1: int = ((cx1 + demi_cote) + (cz1 + demi_cote) * cote_lin) * 9 + ix1 + iz1 * 3
			var cache1: float = table[idx1]
			if not is_nan(cache1) and cache1 <= ymax1:
				sol_ici_val = cache1
				sol_ici_present = true
		if not sol_ici_present:
			var r1 = carte.sommet_sous(x1, z1, ymax1)
			if r1 != null:
				sol_ici_val = float(r1)
				sol_ici_present = true
		# --- sol devant ---
		var x2: float = pos.x + dep_x
		var z2: float = pos.z + dep_z
		var ymax2: float = pos.y + cote
		var cx2: int = floori(x2 * inv_cote)
		var cz2: int = floori(z2 * inv_cote)
		var sol_dv_val: float = 0.0
		var sol_dv_present: bool = false
		if cx2 >= -demi_cote and cx2 < demi_cote and cz2 >= -demi_cote and cz2 < demi_cote:
			var xl2: float = x2 - float(cx2) * cote
			var zl2: float = z2 - float(cz2) * cote
			var ix2: int = clampi(floori(xl2 * trois_sur_cote), 0, 2)
			var iz2: int = clampi(floori(zl2 * trois_sur_cote), 0, 2)
			var idx2: int = ((cx2 + demi_cote) + (cz2 + demi_cote) * cote_lin) * 9 + ix2 + iz2 * 3
			var cache2: float = table[idx2]
			if not is_nan(cache2) and cache2 <= ymax2:
				sol_dv_val = cache2
				sol_dv_present = true
		if not sol_dv_present:
			var r2 = carte.sommet_sous(x2, z2, ymax2)
			if r2 != null:
				sol_dv_val = float(r2)
				sol_dv_present = true
		if not sol_ici_present or not sol_dv_present:
			dep_x = 0.0
			dep_z = 0.0
			ve.x = 0.0
			ve.z = 0.0
		elif sol_dv_val - sol_ici_val > cote:
			dep_x = 0.0
			dep_z = 0.0
			ve.x = 0.0
			ve.z = 0.0
		pos.x += dep_x
		pos.z += dep_z
		pos.y += dep_y
		# --- snap sol ---
		var x3: float = pos.x
		var z3: float = pos.z
		var ymax3: float = pos.y + cote
		var cx3: int = floori(x3 * inv_cote)
		var cz3: int = floori(z3 * inv_cote)
		var sol_val: float = 0.0
		var sol_present: bool = false
		if cx3 >= -demi_cote and cx3 < demi_cote and cz3 >= -demi_cote and cz3 < demi_cote:
			var xl3: float = x3 - float(cx3) * cote
			var zl3: float = z3 - float(cz3) * cote
			var ix3: int = clampi(floori(xl3 * trois_sur_cote), 0, 2)
			var iz3: int = clampi(floori(zl3 * trois_sur_cote), 0, 2)
			var idx3: int = ((cx3 + demi_cote) + (cz3 + demi_cote) * cote_lin) * 9 + ix3 + iz3 * 3
			var cache3: float = table[idx3]
			if not is_nan(cache3) and cache3 <= ymax3:
				sol_val = cache3
				sol_present = true
		if not sol_present:
			var r3 = carte.sommet_sous(x3, z3, ymax3)
			if r3 != null:
				sol_val = float(r3)
				sol_present = true
		var contact: bool = false
		if sol_present and pos.y <= sol_val:
			pos.y = sol_val
			contact = true
		var au_sol_final: bool = contact and ve.y <= 0.0
		au_sols[i] = 1 if au_sol_final else 0
		if au_sol_final:
			ve.y = 0.0
		velocites[i] = ve
		positions[i] = pos
		# ---- BUFFER (round 7, layout TRANSFORM_3D 12 floats/slot) ----
		var slot: int = slots[i]
		if slot >= 0:
			var base: int = slot * 12
			buffer[base + 3] = pos.x
			buffer[base + 7] = pos.y
			buffer[base + 11] = pos.z
		i += 1
	cols.position = positions
	cols.velocite = velocites
	cols.au_sol = au_sols
	return buffer

# CHEMIN C++ (chantier "portage C++ du poste physique"). Prepare le Dictionary
# d'entree, appelle PhysiqueSimpleLot.pas_simple_lot (extension_terrain),
# reassigne les colonnes mutees, et rejoue GDScript sur les indices renvoyes
# dans indices_a_repasser (miss table de sol -> repli sommet_sous cote GDScript,
# hors perimetre C++). Aucune divergence de comportement possible : les indices
# non traites par le C++ n'ont AUCUNE mutation faite par lui, le rejeu part de
# l'etat exact d'entree pour ces unites. Verrouille par test_physique_simple_lot_cpp.gd.
func _physique_et_buffer_cpp(cols: Dictionary, buffer: PackedFloat32Array, count: int, gravite: float, delta: float, carte) -> PackedFloat32Array:
	if delta <= 0.0 or count <= 0 or carte == null:
		return buffer
	var cpp := _instance_physique_cpp()
	if cpp == null:
		return physique_et_buffer(cols, buffer, count, gravite, delta, carte)
	var cote: float = 2.0
	if "cote" in carte:
		cote = float(carte.cote)
	var demi_cote: int = int(carte.demi_cote)
	var entree := {
		"position": cols.position,
		"velocite": cols.velocite,
		"desiree": cols.desiree,
		"au_sol": cols.au_sol,
		"slot": cols.slot,
		"buffer": buffer,
		"count": count,
		"gravite": gravite,
		"delta": delta,
		"vitesse_terminale": VITESSE_TERMINALE_ABS,
		"table": carte.table_sommet(),
		"demi_cote": demi_cote,
		"cote": cote,
	}
	var sortie: Dictionary = cpp.pas_simple_lot(entree)
	cols.position = sortie.position
	cols.velocite = sortie.velocite
	cols.au_sol = sortie.au_sol
	var buffer_out: PackedFloat32Array = sortie.buffer
	var indices: PackedInt32Array = sortie.indices_a_repasser
	if not indices.is_empty():
		buffer_out = physique_et_buffer_indices(cols, buffer_out, indices, gravite, delta, carte)
	return buffer_out

# Instance paresseuse de la classe C++. push_error + null si l'extension
# `extension_terrain` n'est pas chargee (developpeur qui roule l'editeur sans
# la .dll) -- l'appelant retombe alors sur physique_et_buffer GDScript.
func _instance_physique_cpp() -> RefCounted:
	if _physique_cpp != null:
		return _physique_cpp
	if not ClassDB.class_exists("PhysiqueSimpleLot"):
		push_error("banc_peuplement : classe C++ 'PhysiqueSimpleLot' introuvable -- extension_terrain non chargee ? Repli GDScript force pour cette frame.")
		return null
	_physique_cpp = ClassDB.instantiate("PhysiqueSimpleLot")
	return _physique_cpp

# MIROIR de physique_et_buffer sur un SOUS-ENSEMBLE d'indices. Corps identique
# (memes copies de calcul S.2 a S.10, meme ecriture buffer), seule la boucle
# change (indices au lieu de range(count)). Duplication acceptee : refactoriser
# physique_et_buffer en helper interne casserait test_tick_fusionne (verrouille
# la fonction bout-en-bout) ; ce fichier assume deja d'etre un MIROIR de
# pas_simple_lot, une duplication de plus reste dans la meme discipline. La
# parite est verrouillee par test_physique_simple_lot_cpp.gd, qui exerce ce
# chemin ET la boucle complete.
static func physique_et_buffer_indices(cols: Dictionary, buffer: PackedFloat32Array, indices: PackedInt32Array, gravite: float, delta: float, carte) -> PackedFloat32Array:
	if delta <= 0.0 or indices.is_empty() or carte == null:
		return buffer
	var desirees: PackedVector3Array = cols.desiree
	var positions: PackedVector3Array = cols.position
	var velocites: PackedVector3Array = cols.velocite
	var au_sols: PackedByteArray = cols.au_sol
	var slots: PackedInt32Array = cols.slot
	var cote: float = 2.0
	if "cote" in carte:
		cote = float(carte.cote)
	var inv_cote: float = 1.0 / cote
	var trois_sur_cote: float = 3.0 * inv_cote
	var table: PackedFloat32Array = carte.table_sommet()
	var demi_cote: int = int(carte.demi_cote)
	var cote_lin: int = 2 * demi_cote
	var g_dt: float = gravite * delta
	var vt: float = -VITESSE_TERMINALE_ABS
	var k: int = 0
	var m: int = indices.size()
	while k < m:
		var i: int = indices[k]
		var ve: Vector3 = velocites[i]
		ve.y -= g_dt
		if ve.y < vt:
			ve.y = vt
		var vdh: Vector3 = desirees[i]
		ve.x = vdh.x
		ve.z = vdh.z
		var dep_x: float = ve.x * delta
		var dep_y: float = ve.y * delta
		var dep_z: float = ve.z * delta
		var pos: Vector3 = positions[i]
		# --- sol sous les pieds (table + repli sommet_sous) ---
		var x1: float = pos.x
		var z1: float = pos.z
		var ymax1: float = pos.y + cote
		var cx1: int = floori(x1 * inv_cote)
		var cz1: int = floori(z1 * inv_cote)
		var sol_ici_val: float = 0.0
		var sol_ici_present: bool = false
		if cx1 >= -demi_cote and cx1 < demi_cote and cz1 >= -demi_cote and cz1 < demi_cote:
			var xl1: float = x1 - float(cx1) * cote
			var zl1: float = z1 - float(cz1) * cote
			var ix1: int = clampi(floori(xl1 * trois_sur_cote), 0, 2)
			var iz1: int = clampi(floori(zl1 * trois_sur_cote), 0, 2)
			var idx1: int = ((cx1 + demi_cote) + (cz1 + demi_cote) * cote_lin) * 9 + ix1 + iz1 * 3
			var cache1: float = table[idx1]
			if not is_nan(cache1) and cache1 <= ymax1:
				sol_ici_val = cache1
				sol_ici_present = true
		if not sol_ici_present:
			var r1 = carte.sommet_sous(x1, z1, ymax1)
			if r1 != null:
				sol_ici_val = float(r1)
				sol_ici_present = true
		# --- sol devant ---
		var x2: float = pos.x + dep_x
		var z2: float = pos.z + dep_z
		var ymax2: float = pos.y + cote
		var cx2: int = floori(x2 * inv_cote)
		var cz2: int = floori(z2 * inv_cote)
		var sol_dv_val: float = 0.0
		var sol_dv_present: bool = false
		if cx2 >= -demi_cote and cx2 < demi_cote and cz2 >= -demi_cote and cz2 < demi_cote:
			var xl2: float = x2 - float(cx2) * cote
			var zl2: float = z2 - float(cz2) * cote
			var ix2: int = clampi(floori(xl2 * trois_sur_cote), 0, 2)
			var iz2: int = clampi(floori(zl2 * trois_sur_cote), 0, 2)
			var idx2: int = ((cx2 + demi_cote) + (cz2 + demi_cote) * cote_lin) * 9 + ix2 + iz2 * 3
			var cache2: float = table[idx2]
			if not is_nan(cache2) and cache2 <= ymax2:
				sol_dv_val = cache2
				sol_dv_present = true
		if not sol_dv_present:
			var r2 = carte.sommet_sous(x2, z2, ymax2)
			if r2 != null:
				sol_dv_val = float(r2)
				sol_dv_present = true
		if not sol_ici_present or not sol_dv_present:
			dep_x = 0.0
			dep_z = 0.0
			ve.x = 0.0
			ve.z = 0.0
		elif sol_dv_val - sol_ici_val > cote:
			dep_x = 0.0
			dep_z = 0.0
			ve.x = 0.0
			ve.z = 0.0
		pos.x += dep_x
		pos.z += dep_z
		pos.y += dep_y
		# --- snap sol ---
		var x3: float = pos.x
		var z3: float = pos.z
		var ymax3: float = pos.y + cote
		var cx3: int = floori(x3 * inv_cote)
		var cz3: int = floori(z3 * inv_cote)
		var sol_val: float = 0.0
		var sol_present: bool = false
		if cx3 >= -demi_cote and cx3 < demi_cote and cz3 >= -demi_cote and cz3 < demi_cote:
			var xl3: float = x3 - float(cx3) * cote
			var zl3: float = z3 - float(cz3) * cote
			var ix3: int = clampi(floori(xl3 * trois_sur_cote), 0, 2)
			var iz3: int = clampi(floori(zl3 * trois_sur_cote), 0, 2)
			var idx3: int = ((cx3 + demi_cote) + (cz3 + demi_cote) * cote_lin) * 9 + ix3 + iz3 * 3
			var cache3: float = table[idx3]
			if not is_nan(cache3) and cache3 <= ymax3:
				sol_val = cache3
				sol_present = true
		if not sol_present:
			var r3 = carte.sommet_sous(x3, z3, ymax3)
			if r3 != null:
				sol_val = float(r3)
				sol_present = true
		var contact: bool = false
		if sol_present and pos.y <= sol_val:
			pos.y = sol_val
			contact = true
		var au_sol_final: bool = contact and ve.y <= 0.0
		au_sols[i] = 1 if au_sol_final else 0
		if au_sol_final:
			ve.y = 0.0
		velocites[i] = ve
		positions[i] = pos
		var slot: int = slots[i]
		if slot >= 0:
			var base: int = slot * 12
			buffer[base + 3] = pos.x
			buffer[base + 7] = pos.y
			buffer[base + 11] = pos.z
		k += 1
	cols.position = positions
	cols.velocite = velocites
	cols.au_sol = au_sols
	return buffer

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
