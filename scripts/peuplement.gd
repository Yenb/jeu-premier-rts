extends RefCounted

# A ajouter a CARTE.md dans le prochain chantier d'inventaire -- mecanisme
# non encore documente dans la carte.
#
# PEUPLEMENT : orchestrateur generique d'une population homogene d'individus.
# Alloue un pool de N slots portes par UN MultiMesh unique + UNE instance
# RenderingServer directe qui pointe vers ce MultiMesh (patron
# rendu_terrain_multimesh.gd:853-870 § S6, chemin "instances RS directes").
# Consequence : UN seul draw call pour toute la population, quelle que soit
# N. Le consommateur (banc, systeme de jeu) tient le pool en donnee
# (Dictionary), lit et ecrit ses champs, decide du comportement de chaque
# individu.
#
# CE MODULE NE CONNAIT AUCUN NOM DE CONTENU. Il ne parle d'aucune categorie
# du monde. Aucun type_id, aucun mesh_ref n'est cite en dur ici. Ce sont
# toujours des Strings opaques recues en parametre, resolues via un catalogue
# passe par le consommateur. Test permanent : si une String qui nomme une
# chose du jeu apparait ici, une categorie s'est glissee.
#
# CE MODULE N'EMBARQUE AUCUN COMPORTEMENT. Errance, chasse, ordre, cadence
# de tick, choix de politique -- rien de tout cela n'est ici. Le consommateur
# itere pool.individus, pose velocite_desiree_horizontale, appelle
# Tick.tick_entite lui-meme, puis appelle Peuplement.ecrire_transform pour
# refleter la nouvelle position sur le rendu. Peuplement est un orchestrateur
# de population, pas un moteur d'IA.
#
# CE MODULE N'A AUCUN ETAT. Fonctions static, pas de var membre, aucun cache
# entre appels. Toute donnee de vie du pool est dans le Dictionary retourne
# par creer_pool -- le consommateur en est le seul depositaire.
#
# Aucun nom de classe global declare (doctrine CLAUDE.md) : preload("res://scripts/peuplement.gd").
#
# ---- STRUCTURE DU POOL (Dictionary retourne par creer_pool) ----
# {
#   individus       : Array de Dictionary (chacun est un objet Objet.fabriquer),
#   id_to_index     : Dictionary id:String -> int (index dans individus),
#   slots_libres    : Array[int] (LIFO des slots dispo dans le MultiMesh),
#   mm              : MultiMesh (reference forte, N slots -- issue #80479 :
#                     sans ref forte GDScript, GC -> RID invalide, instance
#                     disparait silencieusement),
#   buffer          : PackedFloat32Array de taille_max * 12, layout
#                     TRANSFORM_3D. Ecrit par spawn/retirer et par tout
#                     consommateur qui bouge des transforms ; envoye au mm en
#                     UN appel par frame via pousser_buffer(pool). CoW :
#                     toujours reassigner pool.buffer apres mutation locale.
#   rid             : RID (UNE seule instance RS, base = mm.get_rid()),
#   scenario        : RID (World3D scenario -- garde pour trace),
#   taille_max      : int,
#   _counter        : int (compteur d'id, seul champ prefixe _ dans le pool),
# }
#
# ---- API PUBLIQUE ----
# static creer_pool(taille_max, mesh, scenario, colonnes = {}) -> Dictionary
#   colonnes : Dictionary { nom -> valeur par defaut } declare les colonnes
#   PARALLELES au pool tenues par peuplement. Le TYPE est deduit du defaut :
#   Vector3 -> PackedVector3Array, bool -> PackedByteArray, int ->
#   PackedInt32Array, float -> PackedFloat32Array. peuplement ne connait
#   aucun nom : c'est le consommateur qui declare. Une colonne est append
#   au spawn (defaut) et swap-remove au retrait, en meme temps que
#   individus, pour rester alignee ; peuplement ne LIT JAMAIS le contenu et
#   n'en NOMME AUCUNE.
#   Alloue le MultiMesh (N slots, mm.mesh = mesh, TRANSFORM_3D), puis UNE
#   instance RS pointant vers lui. scenario pose (obligatoire, issue
#   godotengine/godot#77113). custom_aabb TRES LARGE (Godot ne cull pas par
#   instance de MultiMesh, godot-proposals#10669 : le culling se decide sur
#   l'AABB du MultiMesh entier, jamais par slot). Tous les slots demarrent
#   avec une transform d'echelle NULLE (invisibles). slots_libres initialise
#   [0..N-1] LIFO. Rend le Dictionary complet, ou {} sur echec (taille_max
#   <= 0, mesh null, scenario invalide).
#
# static spawn(pool, catalogue, type_id, position, monde) -> String
#   Alloue un slot libre, appelle Objet.fabriquer pour construire l'individu,
#   l'inscrit dans pool.individus / pool.id_to_index, pose la transform du
#   slot dans le MultiMesh a la position demandee, inscrit dans le monde si
#   non null. Ecrit individu.proprietes._slot = slot (champ technique prefixe
#   _). Rend "" et remet le slot dans slots_libres si Objet.fabriquer refuse
#   (composition invalide, materiau absent). Rend "" sans allouer si
#   pool.slots_libres est vide (pool sature) -- _counter n'incremente pas.
#
# static retirer(pool, id, monde) -> void
#   Remet le slot du MultiMesh a la transform "invisible" (echelle nulle),
#   libere le slot dans slots_libres, retire l'individu du pool par
#   swap-remove (O(1)), retire du monde si non null. Silencieux sur id
#   absent. Le parametre monde est facultatif par symetrie avec spawn --
#   l'ajout est justifie par le choix Yael d'utiliser monde.retirer (ecart
#   framework documente en tete de monde.gd, CARTE.md §4781 amende par le
#   meme chantier).
#
# static ecrire_transform(pool, id) -> void
#   Depuis individu.position courante, pose mm.set_instance_transform sur le
#   slot de l'individu. Silencieux sur id absent.
#
# static ecrire_transform_index(pool, index) -> void
#   Meme geste que ecrire_transform, mais recoit l'INDEX de l'individu dans
#   pool.individus au lieu de son id String -- saute le lookup id_to_index.
#   Utile a un consommateur qui itere deja pool.individus par index (banc de
#   population homogene ou la boucle _physics_process n'a pas besoin du hash).
#   Silencieux sur index hors bornes.
#
# static detruire_pool(pool) -> void
#   Free la RID (sinon fuite : le SceneTree ne nettoie pas les instances RS
#   directes), vide toutes les structures. mm et sa ref forte tombent
#   naturellement quand le Dictionary est libere.
#
# ---- POURQUOI MULTIMESH + N SLOTS PLUTOT QUE N INSTANCES RS + MESH ----
# Un livrable intermediaire avait choisi N instances RS + base=Mesh partage
# (perte du batching : N draw calls a 10 000 individus, incompatible avec
# l'objectif M1). Retour au patron MultiMesh unique : UN draw call, quelle
# que soit N. Prix : les slots libres restent "presents mais invisibles" dans
# le buffer MultiMesh (pas de compaction) -- la transform d'echelle nulle sur
# un slot libre reste rendue par le GPU mais ne produit aucun pixel visible,
# cout marginal versus le gain d'un draw call unique. Voir
# rendu_terrain_multimesh.gd:853-870 pour le patron RS direct.
#
# ---- INVALIDATION DU MONDE ----
# Le monde.gd de ce depot porte un retirer(id) en ECART FRAMEWORK (voir
# monde.gd:224 § "ECART AVEC LE DEPOT FRAMEWORK"). Le depot Orion n'a pas ce
# geste, et CARTE.md §4781 le classait "ECARTE, a ne pas reproposer" ; l'ecart
# est desormais assume (validation Yael, chantier "peuplement + rendu"),
# CARTE.md est amendee en consequence dans le meme commit. Peuplement.retirer
# l'utilise donc sans reserve.
#
# ---- REGIME DE MASSE : PAQUET DYNAMIQUE FABRIQUE A LA DEMANDE ----
# Chantier 2026-09-08. Le partage COW du paquet par defaut (voir objet.gd
# § PAQUETS PARTAGES) a fait tomber la memoire de ~1 Go a 569 Mo a
# N=100 000. Reste un poids mort : chaque unite portait quand meme un
# Dictionary `individu` complet (proprietes fusionnees, id String,
# position Vector3) alors que le hot path (physique_et_buffer,
# separation_lot, deplacer_lot C++) ne lit RIEN de ce Dictionary --
# tout passe par les colonnes paralleles. Une unite de foule qui ne
# decremente pas ses reserves n'a besoin que de ses colonnes.
#
# DOCTRINE (docs/design.md, deux regimes presence complete / activation
# variable) appliquee ICI a la MEMOIRE, pas seulement a la simulation :
# une barre faim/soif/sommeil EXISTE et compte quand elle est active,
# mais une barre qui dort n'a pas a etre materialisee 100 000 fois en
# RAM. L'information n'est jamais perdue -- elle est DIFFEREE, fabriquee
# a la demande quand l'unite s'active.
#
# DEUX REGIMES DU PEUPLEMENT :
# (1) MASSE (spawn_masse) : ne cree QUE la ligne de colonnes (position,
#     velocite, desiree, direction, cap_horloge, au_sol, vitesse, slot).
#     Aucun Dictionary `individu`, aucune fabrication d'objet, aucune
#     inscription au monde. `pool.individus` reste vide, la population
#     n'existe que dans les colonnes.
# (2) ACTIVATION (activer) : fabrique le Dictionary complet a la demande
#     -- Objet.fabriquer avec `paquets_partages=true` produit un individu
#     comme si on avait spawn en regime normal, positionne a la ligne de
#     colonnes deja posee. L'individu rejoint `pool.individus`, `_slot`
#     pointe sur le slot MultiMesh preexistant (colonne slot[index]).
#     Le paquet dynamique arrive intact -- reserves.faim.reserve=100.0
#     par defaut, tout ce qu'un colon normal aurait.
#
# INVARIANT ROMPU EXPRES SOUS MASSE : `individus.size() == cols.size()`
# ne tient PLUS. Les activations ne sont pas alignees avec les colonnes,
# elles sont un tableau clairseme (peut etre vide, ou porter quelques
# unites activees pendant que les 99 990 autres restent en colonnes).
# `pool.taille_max - pool.slots_libres.size()` remplace `individus.size()`
# comme "compte d'unites vivantes dans les colonnes" -- valable dans les
# deux regimes. Le banc lit `cols.position.size()` (equivalent, plus
# direct) pour la borne d'iteration du hot path.
#
# CONTRAINTE : le regime masse EXIGE `deplacer_cpp=true` cote banc, car
# la passe deplacer GDScript oracle (`_monde.deplacer_simple(individu)`)
# lit `individus[j].position` -- vide sous masse. L'index C++
# `deplacer_lot(cols.position)` reste seule voie.
#
# ACTIVATION ALLER SIMPLE (choix documente pour ce chantier) : desactiver
# une unite (retirer son individu tout en gardant sa ligne de colonnes)
# n'est pas implemente ici -- la question "quand une unite peut-elle
# redormir" est un chantier de gameplay a part. Ce qui est implemente :
# spawn_masse (dormant) -> activer (reveil) est un aller simple. `retirer`
# fonctionne pour les unites ACTIVEES et retire aussi leur ligne de
# colonnes ; retirer une unite MASSE sans activation prealable n'est pas
# expose ici, l'appelant peut compacter les colonnes lui-meme si besoin.
#
# ---- ECART AVEC LE DEPOT FRAMEWORK ----
# Ce fichier est NEUF dans cette copie de scripts/ ; le depot orion ne le
# porte pas encore. Divergence assumee par Yael faute d'un mecanisme partage
# cote framework (voir CLAUDE.md § Frontiere).

const Objet = preload("res://scripts/objet.gd")

# Transform "invisible" pour un slot libre : echelle NULLE + position (0,0,0).
# Transform3D() par defaut est IDENTITE : un slot libre y rendrait le mesh a
# l'origine, empilement de cubes visibles a (0,0,0). Une echelle nulle rend
# strictement invisible sans retirer le slot du buffer -- alternative propre a
# la compaction / swap qui couterait un memmove par retrait.
const TRANSFORM_SLOT_LIBRE := Transform3D(
	Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO),
	Vector3.ZERO)

# AABB monde large englobant toute la population attendue. Godot ne cull pas
# par instance de MultiMesh (godot-proposals#10669), le culler decide "visible
# ou pas" pour le MultiMesh entier. -1e6 a +1e6 est au-dela de toute carte
# concevable, donc le MultiMesh est TOUJOURS considere visible tant qu'un
# individu est dans le champ de la camera.
const AABB_TRES_LARGE := AABB(Vector3(-1e6, -1e6, -1e6), Vector3(2e6, 2e6, 2e6))

static func creer_pool(taille_max: int, mesh: Mesh, scenario: RID, colonnes: Dictionary = {}) -> Dictionary:
	if taille_max <= 0:
		push_error("peuplement.gd : creer_pool(taille_max = %d) -- taille non positive, pool inutilisable" % taille_max)
		return {}
	if mesh == null:
		push_error("peuplement.gd : creer_pool -- mesh null, aucun rendu possible")
		return {}
	if not scenario.is_valid():
		push_error("peuplement.gd : creer_pool -- scenario RID invalide, instance RS ne serait jamais rendue (issue godotengine/godot#77113)")
		return {}
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = taille_max
	mm.visible_instance_count = taille_max
	# TAMPON UNIQUE. Un PackedFloat32Array de 12 floats par slot -- layout
	# TRANSFORM_3D : [xx, xy, xz, ox, yx, yy, yz, oy, zx, zy, zz, oz]. Rempli
	# de 0.0 par resize : base nulle + origine nulle = slot invisible (equivalent
	# a l'ancien TRANSFORM_SLOT_LIBRE d'echelle nulle). spawn/retirer et le
	# consommateur ecrivent dans ce tampon puis appellent pousser_buffer pour
	# faire monter le tout au RenderingServer en UN envoi par frame, au lieu
	# de N set_instance_transform.
	var buffer := PackedFloat32Array()
	buffer.resize(taille_max * 12)
	RenderingServer.multimesh_set_buffer(mm.get_rid(), buffer)
	var slots_libres: Array = []
	slots_libres.resize(taille_max)
	var i: int = taille_max - 1
	var j: int = 0
	while i >= 0:
		slots_libres[j] = i
		i -= 1
		j += 1
	var rid: RID = RenderingServer.instance_create()
	RenderingServer.instance_set_base(rid, mm.get_rid())
	RenderingServer.instance_set_scenario(rid, scenario)
	RenderingServer.instance_set_custom_aabb(rid, AABB_TRES_LARGE)
	# Colonnes paralleles au pool : nom -> PackedArray vide du bon type. Le
	# consommateur les remplira via `pool.colonnes[nom][index]` a chaque spawn
	# (index = id_to_index[id]). peuplement les tient alignees en append/swap.
	var cols: Dictionary = {}
	for nom in colonnes.keys():
		cols[String(nom)] = _colonne_vide_pour_defaut(colonnes[nom])
	return {
		"individus": [] as Array,
		"id_to_index": {} as Dictionary,
		"slots_libres": slots_libres,
		"mm": mm,
		"buffer": buffer,
		"rid": rid,
		"scenario": scenario,
		"taille_max": taille_max,
		"_counter": 0,
		"colonnes": cols,
		"_defauts_colonnes": colonnes.duplicate(),
	}


# COLONNE VIDE, TYPE DEDUIT DU DEFAUT. Sans jamais nommer la nature de la
# colonne (peuplement n'en connait aucun nom).
static func _colonne_vide_pour_defaut(defaut) -> Variant:
	match typeof(defaut):
		TYPE_VECTOR3:
			return PackedVector3Array()
		TYPE_BOOL:
			return PackedByteArray()
		TYPE_INT:
			return PackedInt32Array()
		TYPE_FLOAT:
			return PackedFloat32Array()
		_:
			push_error("peuplement.gd : type de defaut de colonne non supporte (%d) -- utiliser Vector3, bool, int ou float" % typeof(defaut))
			return null

## Contrat : ecrit toujours les 12 floats du slot dans pool.buffer (position +
## base identite). Le PUSH au RenderingServer (`multimesh_set_buffer`) est
## conditionnel : `pousser=true` (defaut) l'envoie -- comportement historique,
## necessaire pour un spawn ISOLE en jeu (l'unite doit apparaitre immediatement).
## `pousser=false` ecrit le slot sans push : reserve au REMPLISSAGE EN LOT
## (jeu/bancs/banc_peuplement.gd::_fabriquer_lot), qui appelle
## `pousser_buffer(pool)` UNE fois a la fin. Sans ce parametre, N spawns
## poussent N fois le buffer entier au RS, cout O(N^2) mesure a l'ecran :
## 100 000 unites x 1,2 M floats = interminable.
##
## `paquets_partages` (defaut false, comportement historique) : propage a
## Objet.fabriquer -- voir objet.gd:PAQUETS PARTAGES pour le contrat complet.
## A activer pour les populations massives (mobile_test) dont les sous-Dict
## par defaut (reserves, deformation_etat, etats...) sont inertes en regime.
## Sous true, TOUTES les instances du meme type partagent les sous-Dict/Array
## du paquet par reference -- ecritures top-level sur `proprietes` sures,
## mutations d'un sous-Dict interdites sans Objet.detacher au prealable.
static func spawn(pool: Dictionary, catalogue: Dictionary, type_id: String, position: Vector3, monde = null, pousser: bool = true, paquets_partages: bool = false) -> String:
	if pool.is_empty():
		push_error("peuplement.gd : spawn -- pool vide (non initialise)")
		return ""
	if (pool.slots_libres as Array).is_empty():
		push_error("peuplement.gd : spawn -- pool sature (%d slots occupes), refuse" % int(pool.taille_max))
		return ""
	var slot: int = int((pool.slots_libres as Array).pop_back())
	pool["_counter"] = int(pool._counter) + 1
	var id: String = "%s_%d" % [type_id, int(pool._counter)]
	# Objet.fabriquer contrat : (id, type, position, table, materiaux, proprietes_immuables, reserve_combustible, catalogue_emergences).
	# Les quatre catalogues facultatifs restent au defaut vide -- un objet mobile
	# generique n'utilise ni composition, ni combustible, ni emergences.
	var individu: Dictionary = Objet.fabriquer(id, type_id, position, catalogue, {}, [], {}, [], paquets_partages)
	if individu.is_empty():
		push_error("peuplement.gd : spawn -- Objet.fabriquer('%s', '%s') a echoue (voir push_error precedent)" % [id, type_id])
		(pool.slots_libres as Array).push_back(slot)
		return ""
	(individu.proprietes as Dictionary)["_slot"] = slot
	(pool.individus as Array).append(individu)
	(pool.id_to_index as Dictionary)[id] = (pool.individus as Array).size() - 1
	# COLONNES PARALLELES : append la valeur par defaut de chaque colonne,
	# alignement garanti sur individus. Le consommateur ecrit ensuite la vraie
	# valeur a l'index rendu.
	var cols: Dictionary = pool.colonnes
	var defauts: Dictionary = pool._defauts_colonnes
	for nom in cols.keys():
		var defaut = defauts[nom]
		var col = cols[nom]
		col.push_back(defaut)
		cols[nom] = col
	if monde != null:
		monde.ajouter(individu, type_id, position)
	# TAMPON UNIQUE : pose la base identite + position dans les 12 floats du
	# slot. Le push au RS est CONDITIONNEL (voir contrat de spawn). CoW : buffer
	# local, muter, reassigner a pool.
	var buffer: PackedFloat32Array = pool.buffer
	var base: int = slot * 12
	buffer[base + 0] = 1.0
	buffer[base + 1] = 0.0
	buffer[base + 2] = 0.0
	buffer[base + 3] = position.x
	buffer[base + 4] = 0.0
	buffer[base + 5] = 1.0
	buffer[base + 6] = 0.0
	buffer[base + 7] = position.y
	buffer[base + 8] = 0.0
	buffer[base + 9] = 0.0
	buffer[base + 10] = 1.0
	buffer[base + 11] = position.z
	pool["buffer"] = buffer
	if pousser:
		RenderingServer.multimesh_set_buffer((pool.mm as MultiMesh).get_rid(), buffer)
	return id

static func retirer(pool: Dictionary, id: String, monde = null) -> void:
	if pool.is_empty():
		return
	var id_to_index: Dictionary = pool.id_to_index
	if not id_to_index.has(id):
		return
	var index: int = int(id_to_index[id])
	var individus: Array = pool.individus
	var individu: Dictionary = individus[index]
	var slot: int = int((individu.proprietes as Dictionary).get("_slot", -1))
	if slot >= 0:
		# TAMPON UNIQUE : remet les 12 floats du slot a 0.0 (slot invisible,
		# equivalent a l'ancien TRANSFORM_SLOT_LIBRE), puis pousse. CoW.
		var buffer: PackedFloat32Array = pool.buffer
		var base: int = slot * 12
		for k in range(12):
			buffer[base + k] = 0.0
		RenderingServer.multimesh_set_buffer((pool.mm as MultiMesh).get_rid(), buffer)
		pool["buffer"] = buffer
		(pool.slots_libres as Array).push_back(slot)
	# Swap-remove : deplace le dernier a la place du retire, evite le O(N) d'un
	# remove_at + rebuild complet de id_to_index.
	var dernier: int = individus.size() - 1
	if index != dernier:
		var swap: Dictionary = individus[dernier]
		individus[index] = swap
		id_to_index[String(swap.id)] = index
	individus.pop_back()
	id_to_index.erase(id)
	# COLONNES PARALLELES : appliquer LE MEME swap-remove que sur individus,
	# depack/mute/repack pour le CoW. Alignement colonne <-> individus tenu.
	var cols: Dictionary = pool.colonnes
	for nom in cols.keys():
		var col = cols[nom]
		if index != dernier:
			col[index] = col[dernier]
		col.resize(col.size() - 1)
		cols[nom] = col
	if monde != null and (monde.choses as Dictionary).has(id):
		monde.retirer(id)

static func ecrire_transform(pool: Dictionary, id: String) -> void:
	if pool.is_empty():
		return
	var id_to_index: Dictionary = pool.id_to_index
	if not id_to_index.has(id):
		return
	var individu: Dictionary = (pool.individus as Array)[int(id_to_index[id])]
	var slot: int = int((individu.proprietes as Dictionary).get("_slot", -1))
	if slot < 0:
		return
	(pool.mm as MultiMesh).set_instance_transform(slot, Transform3D(Basis.IDENTITY, individu.position))

static func ecrire_transform_index(pool: Dictionary, index: int) -> void:
	if pool.is_empty():
		return
	var individus: Array = pool.individus
	if index < 0 or index >= individus.size():
		return
	var individu: Dictionary = individus[index]
	var slot: int = int((individu.proprietes as Dictionary).get("_slot", -1))
	if slot < 0:
		return
	(pool.mm as MultiMesh).set_instance_transform(slot, Transform3D(Basis.IDENTITY, individu.position))

static func pousser_buffer(pool: Dictionary) -> void:
	# Envoi UNIQUE du tampon complet au serveur de rendu. A appeler apres avoir
	# ecrit les nouvelles transforms de la frame dans pool.buffer (le
	# consommateur qui itere ses individus lui-meme). Alternative aux N
	# set_instance_transform en boucle.
	if pool.is_empty():
		return
	RenderingServer.multimesh_set_buffer((pool.mm as MultiMesh).get_rid(), pool.buffer)

static func detruire_pool(pool: Dictionary) -> void:
	if pool.is_empty():
		return
	var rid: RID = pool.get("rid", RID())
	if rid.is_valid():
		RenderingServer.free_rid(rid)
	(pool.individus as Array).clear()
	(pool.id_to_index as Dictionary).clear()
	(pool.slots_libres as Array).clear()
	(pool.colonnes as Dictionary).clear()

# ============================================================================
# REGIME MASSE -- voir en-tete § "REGIME DE MASSE" pour la doctrine complete.
# ============================================================================

## spawn_masse : cree UNE ligne de colonnes (position + vitesse + init errance),
## ecrit le buffer du slot, ne fabrique AUCUN Dictionary individu et n'inscrit
## rien dans le monde. `individus` / `id_to_index` restent vides. Rend l'INDEX
## dans les colonnes (= slot MultiMesh sous regime sequentiel sans retrait
## anterieur ; l'appelant peut lire `cols.slot[index]` s'il a besoin du slot
## explicitement). Le buffer n'est PAS pousse au RS -- l'appelant appelle
## pousser_buffer(pool) UNE fois en fin de lot (meme patron que spawn(..., false)).
##
## Chaque colonne connue est initialisee ici : position au parametre, velocite/
## desiree/au_sol/cap_horloge/direction au defaut neutre (Vector3.ZERO / 0.0 /
## false), vitesse au parametre, slot au slot alloue. Colonne inconnue au module
## (nom que le consommateur a passe a creer_pool mais que peuplement ne
## connait pas nominalement) : append la valeur par defaut declaree au colonnes[nom]
## de creer_pool -- meme geste que spawn.
##
## Rend -1 si le pool est vide ou sature (jamais un slot invalide).
static func spawn_masse(pool: Dictionary, position: Vector3, vitesse: float, direction_errance: Vector3 = Vector3.ZERO, cap_horloge: float = 0.0) -> int:
	if pool.is_empty():
		push_error("peuplement.gd : spawn_masse -- pool vide (non initialise)")
		return -1
	if (pool.slots_libres as Array).is_empty():
		push_error("peuplement.gd : spawn_masse -- pool sature (%d slots occupes), refuse" % int(pool.taille_max))
		return -1
	var slot: int = int((pool.slots_libres as Array).pop_back())
	# TAMPON : pose la base identite + position dans les 12 floats du slot. CoW.
	var buffer: PackedFloat32Array = pool.buffer
	var base: int = slot * 12
	buffer[base + 0] = 1.0
	buffer[base + 1] = 0.0
	buffer[base + 2] = 0.0
	buffer[base + 3] = position.x
	buffer[base + 4] = 0.0
	buffer[base + 5] = 1.0
	buffer[base + 6] = 0.0
	buffer[base + 7] = position.y
	buffer[base + 8] = 0.0
	buffer[base + 9] = 0.0
	buffer[base + 10] = 1.0
	buffer[base + 11] = position.z
	pool["buffer"] = buffer
	# COLONNES : peuplement connait nominalement position/velocite/desiree/
	# direction/au_sol/cap_horloge/vitesse/slot (les colonnes que le banc
	# declare). Toute autre colonne recoit son defaut de creer_pool.
	var cols: Dictionary = pool.colonnes
	var defauts: Dictionary = pool._defauts_colonnes
	for nom in cols.keys():
		var col = cols[nom]
		var valeur = _valeur_masse_pour_colonne(String(nom), position, vitesse, direction_errance, cap_horloge, slot, defauts.get(nom, null))
		col.push_back(valeur)
		cols[nom] = col
	return slot

# Extraction du switch de defauts par nom de colonne, pour ne pas dupliquer entre
# spawn_masse et un futur activer_par_lots. `defaut` (declare a creer_pool) est
# la voie de repli sur toute colonne dont le nom n'est pas connu ici -- meme
# principe que _colonne_vide_pour_defaut : peuplement ne nomme aucune categorie,
# la liste ci-dessous est un raccourci pratique du CABLAGE que fait deja
# banc_peuplement (les huit colonnes universelles au peuplement mobile).
static func _valeur_masse_pour_colonne(nom: String, position: Vector3, vitesse: float, direction: Vector3, cap_horloge: float, slot: int, defaut) -> Variant:
	match nom:
		"position":
			return position
		"velocite":
			return Vector3.ZERO
		"desiree":
			return direction * vitesse
		"direction":
			return direction
		"au_sol":
			return false
		"cap_horloge":
			return cap_horloge
		"vitesse":
			return vitesse
		"slot":
			return slot
		_:
			return defaut

## activer : fabrique le Dictionary `individu` complet (Objet.fabriquer avec
## `paquets_partages=true`) pour la ligne de colonnes `index`, l'inscrit dans
## `pool.individus` / `pool.id_to_index`, pose `_slot` a `cols.slot[index]`,
## inscrit dans le monde si non null. Le Dictionary porte le paquet dynamique
## complet -- reserves.faim.reserve=100.0 par defaut, tout ce qu'un colon normal
## aurait recu au spawn. La ligne de colonnes reste EN PLACE : la position lue
## est `cols.position[index]` (pas le parametre), pour que activer n'introduise
## pas de discordance entre la position du Dictionary et la position tenue par
## la physique.
##
## Rend l'id String de l'unite activee, ou "" en cas d'echec (index hors bornes,
## fabrication refusee par Objet.fabriquer, pool vide).
##
## L'INVARIANT `individus.size() == cols.size()` est ROMPU expres apres cet appel
## sous regime masse (voir en-tete). Le hot path lit `cols.position.size()` pour
## la borne d'iteration, pas `individus.size()`.
static func activer(pool: Dictionary, catalogue: Dictionary, type_id: String, index: int, monde = null) -> String:
	if pool.is_empty():
		push_error("peuplement.gd : activer -- pool vide (non initialise)")
		return ""
	var cols: Dictionary = pool.colonnes
	var positions: PackedVector3Array = cols.position
	if index < 0 or index >= positions.size():
		push_error("peuplement.gd : activer(index=%d) hors bornes (0..%d)" % [index, positions.size() - 1])
		return ""
	var slots_col: PackedInt32Array = cols.slot
	var slot: int = int(slots_col[index])
	var position: Vector3 = positions[index]
	pool["_counter"] = int(pool._counter) + 1
	var id: String = "%s_%d" % [type_id, int(pool._counter)]
	# paquets_partages=true : les sous-Dict/Array de premier niveau (reserves,
	# deformation_etat, canaux_config si le type compose percevant, etc.) sont
	# partages avec les autres activations du meme type -- meme contrat que
	# spawn(..., paquets_partages=true) : ecritures top-level sures, mutations
	# de sous-Dict a proteger avec Objet.detacher.
	var individu: Dictionary = Objet.fabriquer(id, type_id, position, catalogue, {}, [], {}, [], true)
	if individu.is_empty():
		push_error("peuplement.gd : activer -- Objet.fabriquer('%s', '%s') a echoue (voir push_error precedent)" % [id, type_id])
		pool["_counter"] = int(pool._counter) - 1
		return ""
	(individu.proprietes as Dictionary)["_slot"] = slot
	# PRESENCE COMPLETE (activation = materialisation reelle) : une unite activee a
	# SON PROPRE etat interne mutable. Sans ce detacher, muter reserves.sommeil.reserve
	# sur l'unite A muterait AUSSI l'unite B qui pointait vers la meme reference via
	# le cache canonique du chantier COW (objet.gd:PAQUETS PARTAGES). Detacher
	# `reserves` UNIQUEMENT : c'est le seul sous-Dict que ce depot mute couramment
	# sur une entite vivante (depense.gd:avancer / flux.gd). Les autres sous-Dict
	# (deformation_etat, etats de charge, canaux_config...) restent partages ; un
	# banc qui veut les muter appellera Objet.detacher lui-meme sur la cle voulue
	# (contrat CARTE.md §objet.gd).
	Objet.detacher(individu.proprietes as Dictionary, "reserves")
	(pool.individus as Array).append(individu)
	(pool.id_to_index as Dictionary)[id] = (pool.individus as Array).size() - 1
	if monde != null:
		monde.ajouter(individu, type_id, position)
	return id
