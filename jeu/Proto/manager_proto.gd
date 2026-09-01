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
const Sandpile = preload("res://scripts/sandpile.gd")
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
# SOUS-CUBES LIBRES AU SOL. Chaque sous-cube casse conserve son IDENTITE
# GEOMETRIQUE : taille cote_cellule/3, meme couleur que le materiau
# d'origine. Il tombe par gravite data jusqu'au sol effectif. Vit en
# donnees pures partout dans le monde ; rendu streame par rayon.
# Indexe dans `Monde` (framework) : requete `choses_dans_rayon(pos_obs, r)`
# gratuite pour le rendu et le ramassage.
var _monde_tas: Monde
var _prochain_id_tas: int = 0
# INDEX SC LIBRES PAR COLONNE SOUS-CUBE. Cle : Vector2i col_sc = (floor(x/cote_sous),
# floor(z/cote_sous)). Valeur : Array de dicts sc. Ne contient QUE les sc de matiere
# != "pelle" -- la pelle n'est jamais indexee. Sert a `_sommet_effectif` pour eviter
# le scan O(N) de `_monde_tas.choses` a chaque appel. Maintenu par `_index_ajouter`
# et `_index_retirer`, appeles a chaque site d'ajout/retrait de sc dans `_monde_tas`.
var _index_sc_par_colonne: Dictionary = {}
const MAX_TAS := 2000
const GRAVITE_TAS := 18.0
# CUBE PORTE PAR LE JOUEUR. Un seul a la fois (fatigue de portage). Reference
# directe au Dictionary du sous-cube (meme structure que dans _monde_tas),
# retire du monde quand pris, re-ajoute au monde quand pose.
var _cube_porte: Dictionary = {}
const RAYON_PRENDRE_METRES := 2.0
const OFFSET_PORTAGE := Vector3(0.5, -0.5, -1.0)  # bas droite (FPS), pour ne pas masquer le halo de pose
# Pelle : outil qui casse 10 PV/coup -> 5 coups pour un sous-cube (MAX_PV=50).
const PV_PELLE_PAR_COUP := 10
# Portee pelle : pattern Minecraft (survival 4.5m, creative 5m). Une SEULE
# regle -- si le raycast camera touche un sous-cube dans ces N metres, la
# pelle peut le creuser. Pas de double filtre distance-au-joueur qui creait
# des refus incoherents visuellement (bloc atteint par le raycast, rejete
# par sphere euclidienne).
const PORTEE_PELLE_METRES := 5.0
# Portee beche : meme regle que la pelle. La beche ne casse pas un sous-cube,
# elle compte les coups sur la cellule de terre (10 coups -> transformation).
const PORTEE_BECHE_METRES := 5.0
# LAYER de collision dedie aux OBJETS RAMASSABLES (outils au sol : pelle,
# beche, tout futur outil portable). Valeur 4 (bit 2) -- libre dans le projet
# (seul le layer 1 sert : terrain, murs, plantes, joueur). Le StaticBody3D
# pose sur le visuel d'un outil est sur ce layer, mask 0 (detecte, ne bloque
# personne). Le raycast de `_objet_ramassable_sous_viseur` filtre sur ce layer,
# donc ne touche QUE des outils -- jamais le terrain ni un cube libre (layer 1).
const LAYER_RAMASSABLE := 4
# SANDPILE : tick 1 Hz qui fait couler les sous-cubes libres empiles
# quand l'ecart de hauteur entre colonnes voisines depasse l'angle de repos.
const INTERVALLE_SANDPILE := 1.0
const SANDPILE_ANGLE_REPOS := 3.0  # TODO proto : lire depuis profil par matiere.
var _horloge_sandpile: float = 0.0
# Cout de faim par coup de pelle REUSSI (raycast touche un sous-cube plein).
# 5 coups pour casser un sous-cube -> 50 faim / cellule cassee complete = 27 %
# d'une barre neuve (2500). Adressable de la meme facon pour tout autre outil
# de travail : hache, marteau, etc. -- chacun appelle `depenser_pour_travail`
# avec sa propre valeur.
const COUT_CREUSER_PAR_COUP := 10.0
# Cout de faim par coup de beche REUSSI (raycast touche une cellule de terre
# plein). Meme flux generique que la pelle : `depenser_pour_travail`.
const COUT_BECHER_PAR_COUP := 10.0
# Ennemi creuseur : PV appliques par coup au sous-cube cible. Plus rapide
# que la pelle joueur (10 PV) pour que la menace tienne dans le proto.
# Cadence (secondes entre 2 coups) geree par la boucle IA au morceau 7.
const PV_ENNEMI_CREUSAGE_PAR_COUP := 20
# Cadence entre deux coups de creusage (secondes).
const CADENCE_ENNEMI_CREUSAGE := 0.5
# Rayon en cases pour chercher un bloc creusable.
const RAYON_ENNEMI_CHERCHE_BLOC := 3
# Rayon en metres pour ramasser un sc libre.
const RAYON_ENNEMI_RAMASSE := 2.0
# Halo de visee pour la pelle : cube filaire jaune emissif de taille sous-cube,
# positionne chaque frame sur le sous-cube que le raycast va frapper. Visible
# uniquement quand la pelle est portee. Sans ca, le joueur creuse a l'aveugle.
var _halo_pelle: MeshInstance3D = null
# Halo de visee pour la beche : meme role que le halo pelle, visible seulement
# quand la beche est portee.
var _halo_beche: MeshInstance3D = null
# Index de l'item "bloc_beche" dans le MeshLibrary, resolu une fois au _ready
# (le manager ne connait pas les noms d'items). -1 tant que non resolu.
var _index_bloc_beche: int = -1
# Halo de POSE : cube filaire vert positionne sur la cellule adjacente a la
# face visee, visible SEULEMENT quand un sous-cube libre (non pelle) est
# porte. Distinct du halo pelle : la pelle CREUSE (jaune), la pose EMPILE
# (vert).
var _halo_pose: MeshInstance3D = null
# Mesh partage par matiere (matiere String -> BoxMesh cote/3 avec materiau
# de la couleur du bloc d'origine).
var _mesh_sous_cube_par_matiere: Dictionary = {}
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
# Monter (dy positif entre deux ticks) coute plus cher que marcher a plat --
# effort physique. Multiplicateur 5x sur le deplacement vertical positif.
const COUT_NOURRITURE_PAR_M_MONTEE := 5.0
# Chaque coup de creusage retire un forfait de nourriture, quel que soit le
# succes de la casse. Effort du geste.
const COUT_NOURRITURE_CREUSAGE_PAR_COUP := 3.0
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
	_creer_halo_pelle()
	_creer_halo_beche()
	_creer_halo_pose()
	# Resoudre l'index de l'item "bloc_beche" une fois -- le manager ne
	# hardcode pas le nombre, il lit le nom dans le MeshLibrary du terrain.
	if _grille != null and _grille.mesh_library != null:
		var meshlib: MeshLibrary = _grille.mesh_library
		for id in meshlib.get_item_list():
			if meshlib.get_item_name(id) == "bloc_beche":
				_index_bloc_beche = id
				break
		if _index_bloc_beche < 0:
			push_warning("manager_proto : item 'bloc_beche' introuvable dans le MeshLibrary")
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
	# SCAN INITIAL : `_monde_tas` neuf est vide, donc scan a cout nul en pratique.
	# Presence defensive : si un jour `_monde_tas` est injecte pre-rempli, l'index
	# reste coherent sans avoir a se rappeler d'ajouter cette ligne.
	for w in _monde_tas.choses.values():
		_index_ajouter(w.chose as Dictionary)
	call_deferred("_spawn_pelle_initiale")
	call_deferred("_spawn_beche_initiale")
	# Mesh sous-cube libre "terre" par defaut. D'autres materiaux ajoutes a la
	# volee via _mesh_pour_matiere() -- couleur = albedo du bloc d'origine.
	_mesh_sous_cube_par_matiere["terre"] = _fabriquer_mesh_sous_cube(Color(0.35, 0.22, 0.12, 1.0))
	# Mesh sous-cube "cadavre" -- rouge fonce, distinct des materiaux terrain.
	_mesh_sous_cube_par_matiere["cadavre"] = _fabriquer_mesh_sous_cube(Color(0.35, 0.05, 0.05, 1.0))
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
	_tick_spawn_ennemis(delta)
	_tick_ia_ennemis(delta)
	_repousser_ennemis(delta)
	_bascule_rendu_ennemis()
	_ticker_tas(delta)
	# Sandpile : ecoulement granulaire des sous-cubes libres empiles.
	_horloge_sandpile += delta
	if _horloge_sandpile >= INTERVALLE_SANDPILE:
		_horloge_sandpile = 0.0
		_tick_sandpile()
	_bascule_rendu_tas()
	_sync_cube_porte()
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

# GRAVITE DATA : chute simulee jusqu'au sol EFFECTIF (via carte + sous-cubes
# libres empiles). Clamp au sol quand touche. Sans clamp, le carre s'enfonce.
# Marche PARTOUT dans le monde, pas seulement dans le rayon de rendu :
# aucun gate distance, aucune dependance streaming/physique Godot.
func _appliquer_gravite_data(cr: Dictionary, delta: float) -> void:
	if _carte == null:
		return
	var cote_sous: float = cote_cellule / 3.0
	var y_ref: float = cr.position.y + cote_sous * 0.5
	var y_haut_v: Variant = _sommet_effectif(cr.position.x, cr.position.z, y_ref)
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
							# tombe au sol comme un sous-cube libre.
							_effondrer_selon_materiau(cellule, idx, Vector3(b.position.x, sol_y, b.position.z))
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
	# Sommet EFFECTIF (terrain + sc libres empiles) evalue a la MEME hauteur
	# de reference (pos_a.y) pour comparaison symetrique. Sans ca, une pile
	# de sc libres serait invisible au blocage horizontal et l'ennemi
	# marcherait dedans, puis la gravite le teleporterait au sommet.
	var y_a_v: Variant = _sommet_effectif(pos_a.x, pos_a.z, pos_a.y)
	var y_b_v: Variant = _sommet_effectif(pos_b.x, pos_b.z, pos_a.y)
	if y_a_v == null or y_b_v == null:
		return false
	return float(y_b_v) - float(y_a_v) > cote_cellule

# API publique -- ennemi POSE un sc libre 1 case devant lui (au pied du mur
# ou de la cible). Snap sur grille SC (cote_sous), Y = sommet effectif de la
# colonne cible + demi sc (empilement naturel via _ticker_tas ensuite). Le sc
# passe en parametre garde son id : reinjection dans _monde_tas, pas
# duplication. Pas de flag immobile -- si le support disparait, la gravite
# le fait tomber (patron pose Minecraft-like + physique apres). Rend true si
# pose reussie. Data pur, aucun gate distance.
func _ennemi_poser_sc_devant(pos_ennemi: Vector3, direction: Vector3, sc_a_poser: Variant) -> bool:
	if sc_a_poser == null:
		return false
	if _monde_tas == null:
		return false
	var dir_plate := Vector3(direction.x, 0.0, direction.z)
	if dir_plate.length_squared() < 0.0001:
		return false
	var cote_sous: float = cote_cellule / 3.0
	var pos_devant: Vector3 = pos_ennemi + dir_plate.normalized() * cote_cellule
	var x_snap: float = floor(pos_devant.x / cote_sous) * cote_sous + cote_sous * 0.5
	var z_snap: float = floor(pos_devant.z / cote_sous) * cote_sous + cote_sous * 0.5
	var y_sol_v: Variant = _sommet_effectif(x_snap, z_snap, INF)
	if y_sol_v == null:
		return false
	var y_pose: float = float(y_sol_v) + cote_sous * 0.5
	var sc: Dictionary = sc_a_poser
	sc.position = Vector3(x_snap, y_pose, z_snap)
	sc.vitesse_y = 0.0
	sc.noeud = null  # sera recree au prochain _bascule_rendu_tas
	_monde_tas.ajouter(sc, "sous_cube", sc.position)
	_index_ajouter(sc)
	return true

# API publique -- ennemi RAMASSE le sous-cube libre le plus proche (non-pelle)
# dans un rayon donne. Retire du _monde_tas + libere le visuel, rend le dict
# du sc ramasse (le caller le portera). Rend null si aucun candidat.
# Data pur, aucun gate distance globale (le rayon est local a l'action).
func _ennemi_ramasser_sc_proche(pos_ennemi: Vector3, rayon_metres: float) -> Variant:
	if _monde_tas == null:
		return null
	var proches: Array = _monde_tas.choses_dans_rayon(pos_ennemi, rayon_metres)
	if proches.is_empty():
		return null
	var meilleur = null
	var meilleur_d2: float = INF
	for e in proches:
		var sc: Dictionary = e.chose
		if sc.get("matiere", "") == "pelle" or sc.get("matiere", "") == "beche":
			continue
		var d2: float = (sc.position as Vector3).distance_squared_to(pos_ennemi)
		if d2 < meilleur_d2:
			meilleur_d2 = d2
			meilleur = sc
	if meilleur == null:
		return null
	if meilleur.get("noeud", null) != null and is_instance_valid(meilleur.noeud):
		(meilleur.noeud as Node3D).queue_free()
		meilleur.noeud = null
	_index_retirer(meilleur)
	_monde_tas.retirer(meilleur.id)
	return meilleur

# API publique -- ennemi CREUSE un sous-cube de la cellule cible. Cible fixe :
# sous-cube (ix=1, iy=2, iz=1) = centre haut de la cellule, idx 16 -- visible
# depuis n'importe quelle face laterale. Reutilise _effondrer_selon_materiau
# (helper existant, propage la casse selon type_effondrement du profil).
# Rend true si le sous-cube a casse ce coup, false sinon (PV partiels ou hors
# emprise). Data pur, aucun gate distance.
func _ennemi_creuser(cellule: Vector3i) -> bool:
	if _carte == null:
		return false
	if cellule.y <= _carte.couche_base:
		return false
	if _carte.item_de(cellule) != _carte.ITEM_DEFAUT:
		return false
	# Cible = sous-cube PLEIN le plus haut de la cellule (parmi 27). Sans ca,
	# frapper idx 16 en dur bloque au 2e cycle : idx 16 deja casse -> false
	# indefiniment. On itere du haut (iy=2) vers le bas et prend le premier
	# plein rencontre.
	var idx: int = -1
	for iy in range(2, -1, -1):
		for iz in range(3):
			for ix in range(3):
				var candidat: int = ix + iy * 3 + iz * 9
				if _carte.est_sous_cube_plein(cellule, candidat):
					idx = candidat
					break
			if idx >= 0:
				break
		if idx >= 0:
			break
	if idx < 0:
		return false  # cellule entierement videe
	var casse: bool = _carte.ajouter_pv_sous_cube(cellule, idx, PV_ENNEMI_CREUSAGE_PAR_COUP)
	if casse:
		var cote_sous: float = cote_cellule / 3.0
		var pos_impact := Vector3(
			float(cellule.x) * cote_cellule + cote_cellule * 0.5,
			float(cellule.y) * cote_cellule + (2.0 + 0.5) * cote_sous,
			float(cellule.z) * cote_cellule + cote_cellule * 0.5)
		_effondrer_selon_materiau(cellule, idx, pos_impact)
	return casse

# API publique -- trouve la CELLULE creusable la plus proche de l'ennemi.
# Retourne Vector3i (cellule) ou null. Rayon en NOMBRE DE CASES (pas metres),
# filtre : sommet cellule a +/- 1 case du niveau ennemi (accessible sans
# pathfinding), item par defaut (les blocs profiles -- bloc_bleu -- sont
# reserves, TODO SUIVI : ajouter `creusable_par_ennemi: bool` sur profil).
# Data pur, aucun gate distance, marche PARTOUT dans le monde.
func _ennemi_bloc_creusable_proche(pos_ennemi: Vector3, rayon_cases: int) -> Variant:
	if _carte == null:
		return null
	# Cohérence morceau 1 : partout où on raisonne sur "la hauteur ou est
	# l'entite" ou "la hauteur d'une colonne", utiliser _sommet_effectif
	# (terrain + sc libres empiles), jamais _carte.sommet seul. Sinon un
	# ennemi sur une pile ne detecte plus les blocs voisins, et un bloc
	# terrain enterre sous une pile est detecte comme accessible.
	var cote_sous: float = cote_cellule / 3.0
	var y_som_ennemi_v: Variant = _sommet_effectif(pos_ennemi.x, pos_ennemi.z, pos_ennemi.y + cote_sous * 0.5)
	if y_som_ennemi_v == null:
		return null
	var couche_ennemi: int = int(floor(float(y_som_ennemi_v) / cote_cellule))
	var col_e := Vector2i(int(floor(pos_ennemi.x / cote_cellule)), int(floor(pos_ennemi.z / cote_cellule)))
	var meilleur: Variant = null
	var meilleur_d2: int = 1 << 30
	for dx in range(-rayon_cases, rayon_cases + 1):
		for dz in range(-rayon_cases, rayon_cases + 1):
			if dx == 0 and dz == 0:
				continue
			var col := Vector2i(col_e.x + dx, col_e.y + dz)
			# Centre monde de la colonne pour l'appel _sommet_effectif.
			var x_centre: float = float(col.x) * cote_cellule + cote_cellule * 0.5
			var z_centre: float = float(col.y) * cote_cellule + cote_cellule * 0.5
			# Sommet effectif TOTAL de la colonne cible (y_ref = INF pour
			# inclure TOUS les sc libres empiles) -- couche visible depuis
			# le dessus, incluant les grains poses ou tombes.
			var y_som_cible_v: Variant = _sommet_effectif(x_centre, z_centre, INF)
			if y_som_cible_v == null:
				continue
			var couche_cible: int = int(floor(float(y_som_cible_v) / cote_cellule))
			if abs(couche_cible - couche_ennemi) > 1:
				continue
			# La couche cible = ce que l'ennemi voit comme "haut de la pile",
			# mais on veut CREUSER un bloc terrain, pas un sc libre. On lit
			# donc le sommet TERRAIN (sommet_max_colonne) pour cibler le
			# bloc reel, pas le sc libre au-dessus.
			var som_terrain_v: Variant = _carte.sommet_max_colonne(col)
			if som_terrain_v == null:
				continue
			var cellule := Vector3i(col.x, int(som_terrain_v), col.y)
			if _carte.item_de(cellule) != _carte.ITEM_DEFAUT:
				continue
			if cellule.y <= _carte.couche_base:
				continue
			# Rejeter les colonnes ou le bloc terrain est ENTERRE sous des sc
			# libres empiles (couche cible effective > couche terrain + 1) :
			# l'ennemi ne peut pas atteindre le bloc, il devrait d'abord
			# creuser la pile.
			if couche_cible > cellule.y + 1:
				continue
			var d2: int = dx * dx + dz * dz
			if d2 < meilleur_d2:
				meilleur_d2 = d2
				meilleur = cellule
	return meilleur

# API publique -- l'ennemi a-t-il un obstacle horizontal directement devant
# lui ? Sémantique explicite pour la boucle grimpe : "ma prochaine case est
# elle plus haute qu'un saut permis ?" Réutilise _mouvement_bloque_par_terrain
# qui compare deux sommets effectifs (terrain + sc libres empilés) à même
# hauteur de référence. Data pur, marche PARTOUT (aucun gate distance).
# distance = combien de mètres devant considérer (défaut : 1 case = cote_cellule).
func _ennemi_a_obstacle_devant(pos_ennemi: Vector3, direction: Vector3, distance: float = 0.0) -> bool:
	var d: float = distance if distance > 0.0 else cote_cellule
	var dir_plate: Vector3 = Vector3(direction.x, 0.0, direction.z)
	if dir_plate.length_squared() < 0.0001:
		return false
	var pos_devant: Vector3 = pos_ennemi + dir_plate.normalized() * d
	return _mouvement_bloque_par_terrain(pos_ennemi, pos_devant)

# INDEX SC : ajoute un sc a `_index_sc_par_colonne` a sa colonne SC courante.
# Skip si matiere == "pelle" -- la pelle n'est jamais indexee. A appeler APRES
# `_monde_tas.ajouter(sc, ...)`, quand `sc.position` est la position definitive.
func _index_ajouter(sc: Dictionary) -> void:
	if String(sc.get("matiere", "")) == "pelle" or String(sc.get("matiere", "")) == "beche":
		return
	var cote_sous: float = cote_cellule / 3.0
	var pos: Vector3 = sc.position
	var col := Vector2i(int(floor(pos.x / cote_sous)), int(floor(pos.z / cote_sous)))
	if not _index_sc_par_colonne.has(col):
		_index_sc_par_colonne[col] = []
	(_index_sc_par_colonne[col] as Array).append(sc)

# INDEX SC : retire un sc de `_index_sc_par_colonne`. Skip si matiere == "pelle"
# (jamais indexee). A appeler AVANT `_monde_tas.retirer(sc.id)` -- apres retrait,
# le sc peut etre invalide. Supprime la cle si la colonne devient vide, pour ne
# pas laisser des Array vides polluer le dictionnaire.
func _index_retirer(sc: Dictionary) -> void:
	if String(sc.get("matiere", "")) == "pelle" or String(sc.get("matiere", "")) == "beche":
		return
	var cote_sous: float = cote_cellule / 3.0
	var pos: Vector3 = sc.position
	var col := Vector2i(int(floor(pos.x / cote_sous)), int(floor(pos.z / cote_sous)))
	if not _index_sc_par_colonne.has(col):
		return
	var arr: Array = _index_sc_par_colonne[col]
	arr.erase(sc)
	if arr.is_empty():
		_index_sc_par_colonne.erase(col)

# Sommet effectif = max(sommet_terrain, top des sc libres sur la colonne SC
# de (x, z) sous y_ref). Colonne SC = grille SOUS-CUBE (cote_cellule/3),
# JAMAIS colonne cellule (cote_cellule) -- un sc libre a 0.5m lateral d'un
# ennemi ne doit pas etre considere sous lui. Rend null si hors emprise.
func _sommet_effectif(x: float, z: float, y_ref: float) -> Variant:
	if _carte == null:
		return null
	var y_terrain: Variant = _carte.sommet(x, z)
	if y_terrain == null:
		return null
	var y_max: float = float(y_terrain)
	var cote_sous: float = cote_cellule / 3.0
	var col_sc := Vector2i(int(floor(x / cote_sous)), int(floor(z / cote_sous)))
	# Lecture O(k) via l'index : k = nombre de sc dans cette colonne (typ. 2-5).
	# Invariants garantis par `_index_ajouter`/`_index_retirer` : aucun sc "pelle"
	# n'est present, et tous les sc listes ont une col_sc egale a la cle.
	var sc_colonne: Array = _index_sc_par_colonne.get(col_sc, [])
	for sc in sc_colonne:
		var pos_sc: Vector3 = sc.position
		if pos_sc.y > y_ref:
			continue
		var y_top_sc: float = pos_sc.y + cote_sous * 0.5
		if y_top_sc > y_max:
			y_max = y_top_sc
	return y_max

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
# SOUS-CUBE LIBRE : spawn au point de casse, indexe dans `_monde_tas` (framework
# `scripts/monde.gd`), tombe par gravite data jusqu'au sol effectif. Identite
# geometrique preservee : taille cote_cellule/3, meme couleur que le materiau.
func _spawn_sous_cube_libre(pos: Vector3, matiere: String, immobile: bool = false) -> void:
	# Cap : quand on depasse MAX_TAS, retire le plus ancien via _rang de monde.
	if _monde_tas.choses.size() >= MAX_TAS:
		var id_vieux = _monde_tas.choses.keys()[0]
		var w = _monde_tas.par_id(id_vieux)
		if w != null:
			var vc: Dictionary = w.chose
			if vc.noeud != null and is_instance_valid(vc.noeud):
				vc.noeud.queue_free()
			_index_retirer(vc)
		_monde_tas.retirer(id_vieux)
	var id_neuf: String = "sc_%d" % _prochain_id_tas
	_prochain_id_tas += 1
	var sc := {
		"id": id_neuf,
		"position": pos,
		"vitesse_y": 0.0,
		"noeud": null,
		"matiere": matiere,
		"immobile": immobile,
	}
	_monde_tas.ajouter(sc, "sous_cube", pos)
	_index_ajouter(sc)

# SANDPILE : ecoulement granulaire (angle de repos) sur les colonnes SOUS-CUBE
# du _monde_tas. Ne touche PAS le terrain data (carte.sommet) -- ecoule
# uniquement les sous-cubes LIBRES au-dessus.
# Ligne de vue OCCULTEE PAR LE TERRAIN. Data pur, marche partout (independant
# du streaming). Ray-marching en pas de sous-cube (cote_cellule/3) sur le
# segment pos_a -> pos_b. Si une cellule pleine touche le chemin, retour false.
# Sert a la perception ennemie : un ennemi voit le joueur si (a) Perception
# cone_oriente le rend + (b) cette fonction rend true pour la ligne
# ennemi->joueur.
func _ligne_de_vue_libre(pos_a: Vector3, pos_b: Vector3) -> bool:
	return ligne_de_vue_libre_statique(_carte, cote_cellule, pos_a, pos_b)

# Version statique pour testabilite headless. Prend carte + cote explicites.
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
	# On ne teste PAS le premier ni le dernier point (positions des entites
	# elles-memes, jamais des obstacles) : range(1, nb_pas).
	for i in range(1, nb_pas):
		var p: Vector3 = pos_a + direction * (float(i) * pas)
		var col := Vector2i(int(floor(p.x / cote)), int(floor(p.z / cote)))
		var cy: int = int(floor(p.y / cote))
		if carte.est_pleine(col, cy):
			return false
	return true

func _tick_sandpile() -> void:
	if _carte == null:
		return
	var cases: Array = _cases_pour_sandpile()
	if cases.is_empty():
		return
	var transferts: Array = Sandpile.avancer(cases, 1.0, "tas", "altitude_sol", SANDPILE_ANGLE_REPOS)
	if not transferts.is_empty():
		_appliquer_transferts_sandpile(transferts)

# Rend Array de cases au format Sandpile. Une case = une COLONNE SC (grille
# sous-cube, pas cellule) contenant au moins un sous-cube libre, PLUS ses 4
# voisines cardinales (pour que le mecanisme puisse comparer avec le vide
# alentour). Hauteur en UNITES SOUS-CUBE : altitude_sol = sommet(x,z) /
# cote_sous, reserve = compte des sc libres dans cette colonne.
func _cases_pour_sandpile() -> Array:
	var cote_sous: float = cote_cellule / 3.0
	var par_colonne: Dictionary = {}  # Vector2i -> Array de sc
	for w in _monde_tas.choses.values():
		var sc: Dictionary = w.chose
		if sc.get("matiere", "") == "pelle" or sc.get("matiere", "") == "beche":
			continue
		var pos: Vector3 = sc.position
		var col := Vector2i(int(floor(pos.x / cote_sous)), int(floor(pos.z / cote_sous)))
		if not par_colonne.has(col):
			par_colonne[col] = []
		(par_colonne[col] as Array).append(sc)
	if par_colonne.is_empty():
		return []
	var cols_a_inclure: Dictionary = {}
	for col in par_colonne.keys():
		cols_a_inclure[col] = true
		cols_a_inclure[Vector2i(col.x + 1, col.y)] = true
		cols_a_inclure[Vector2i(col.x - 1, col.y)] = true
		cols_a_inclure[Vector2i(col.x, col.y + 1)] = true
		cols_a_inclure[Vector2i(col.x, col.y - 1)] = true
	var cases: Array = []
	for col in cols_a_inclure.keys():
		var x_monde: float = float(col.x) * cote_sous + cote_sous * 0.5
		var z_monde: float = float(col.y) * cote_sous + cote_sous * 0.5
		var y_sol_val: Variant = _carte.sommet(x_monde, z_monde)
		if y_sol_val == null:
			continue
		var altitude_sc: float = float(y_sol_val) / cote_sous
		var reserve: float = float((par_colonne.get(col, []) as Array).size())
		cases.append({
			"id": "col_%d_%d" % [col.x, col.y],
			"position": Vector3(float(col.x), float(col.y), 0.0),
			"proprietes": {
				"altitude_sol": altitude_sc,
				"reserves": {"tas": {"reserve": reserve}},
			},
		})
	return cases

func _appliquer_transferts_sandpile(transferts: Array) -> void:
	var cote_sous: float = cote_cellule / 3.0
	# Snapshot des sc reels par colonne SC : ne contient QUE des sc valides
	# du _monde_tas (avec id). Jamais de faux dict pousse ici.
	var par_colonne: Dictionary = {}
	for w in _monde_tas.choses.values():
		var sc: Dictionary = w.chose
		if sc.get("matiere", "") == "pelle" or sc.get("matiere", "") == "beche":
			continue
		var pos: Vector3 = sc.position
		var col := Vector2i(int(floor(pos.x / cote_sous)), int(floor(pos.z / cote_sous)))
		if not par_colonne.has(col):
			par_colonne[col] = []
		(par_colonne[col] as Array).append(sc)
	# Compteur separe des sc ajoutes ce tick par colonne. Sert a poser le
	# prochain sc au-dessus du precedent sans polluer par_colonne avec des
	# entrees sans id qui casseraient _monde_tas.retirer plus tard.
	var ajouts_par_col: Dictionary = {}
	for t in transferts:
		var col_s := _col_de_id(String(t.source_id))
		var col_r := _col_de_id(String(t.receveur_id))
		if not par_colonne.has(col_s) or (par_colonne[col_s] as Array).is_empty():
			continue
		# Refus de transfert si la colonne receveur atteint la hauteur MAX pour
		# cette matiere (donnee du profil .tres, PAS regle framework). On
		# compte les sc DE MEME MATIERE deja sur la colonne + ceux ajoutes
		# ce tick. Si limite > 0 et atteinte -> le sc source reste en place.
		var sc_source_head: Dictionary = (par_colonne[col_s] as Array).back()
		# Sc marque immobile : jamais deplace lateralement par sandpile. Regle
		# generale (pas specifique cadavre) -- un sc fixe reste sur place.
		if bool(sc_source_head.get("immobile", false)):
			continue
		var matiere_src: String = String(sc_source_head.get("matiere", "terre"))
		var limite: int = _limite_hauteur_matiere(matiere_src)
		if limite > 0:
			var hauteur_meme_matiere: int = 0
			for sc_r in (par_colonne.get(col_r, []) as Array):
				if String((sc_r as Dictionary).get("matiere", "")) == matiere_src:
					hauteur_meme_matiere += 1
			hauteur_meme_matiere += int(ajouts_par_col.get(col_r, 0))
			if hauteur_meme_matiere >= limite:
				continue
		var sc_ret: Dictionary = (par_colonne[col_s] as Array).pop_back()
		if sc_ret.get("noeud", null) != null and is_instance_valid(sc_ret.noeud):
			(sc_ret.noeud as Node3D).queue_free()
		_index_retirer(sc_ret)
		_monde_tas.retirer(sc_ret.id)
		var x_rec: float = float(col_r.x) * cote_sous + cote_sous * 0.5
		var z_rec: float = float(col_r.y) * cote_sous + cote_sous * 0.5
		var y_sol_val: Variant = _carte.sommet(x_rec, z_rec)
		if y_sol_val == null:
			continue
		var reserve_rec: int = (par_colonne.get(col_r, []) as Array).size() + int(ajouts_par_col.get(col_r, 0))
		var y_pose: float = float(y_sol_val) + (float(reserve_rec) + 0.5) * cote_sous
		var pos_neuve := Vector3(x_rec, y_pose, z_rec)
		_spawn_sous_cube_libre(pos_neuve, String(sc_ret.get("matiere", "terre")))
		ajouts_par_col[col_r] = int(ajouts_par_col.get(col_r, 0)) + 1

# Limite de hauteur (sous-cubes) pour une matiere donnee, lue dans son profil
# .tres via ressources_terrain. 0 = aucune limite (matiere sans plafond
# explicite). Marche pour toute matiere qui a un profil correspondant a son
# nom via nom_item (ex: "bloc" -> bloc_terre.tres). Cache non necessaire :
# ~2 lookups par tick sandpile en pic.
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

func _col_de_id(id: String) -> Vector2i:
	# "col_X_Z" -> Vector2i(X, Z). X et Z peuvent etre negatifs.
	if not id.begins_with("col_"):
		return Vector2i.ZERO
	var reste: String = id.substr(4)
	var sep: int = reste.rfind("_")
	if sep < 0:
		return Vector2i.ZERO
	return Vector2i(int(reste.substr(0, sep)), int(reste.substr(sep + 1)))

# Fabrique un BoxMesh cote/3 avec un StandardMaterial3D unlit de la couleur
# fournie. Sert au preparer et a la creation a la volee pour un materiau neuf.
func _fabriquer_mesh_sous_cube(couleur: Color) -> BoxMesh:
	var box := BoxMesh.new()
	var mini_cote := cote_cellule / 3.0
	box.size = Vector3(mini_cote, mini_cote, mini_cote)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = couleur
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	box.material = mat
	return box

# Rend le BoxMesh pour cette matiere, en le fabriquant a la volee si nouveau.
func _mesh_pour_matiere(matiere: String) -> BoxMesh:
	if not _mesh_sous_cube_par_matiere.has(matiere):
		# Defaut : gris moyen si materiau inconnu.
		_mesh_sous_cube_par_matiere[matiere] = _fabriquer_mesh_sous_cube(Color(0.5, 0.5, 0.5, 1.0))
	return _mesh_sous_cube_par_matiere[matiere]

# EFFONDREMENT SELON LE MATERIAU. Spawn 1 sous-cube libre a `pos_impact` pour
# la cassure locale. Si le profil du bloc dit "meuble", CASCADE : casser
# aussi TOUS les autres sous-cubes de la cellule, chacun spawn un sous-cube
# libre a sa position monde propre. Note : cette cascade est brutale (27
# mini-cubes d'un coup). Version progressive au prochain chantier si besoin.
func _effondrer_selon_materiau(cellule: Vector3i, idx_touche: int, pos_impact: Vector3) -> void:
	var matiere := _matiere_de_cellule(cellule)
	_spawn_sous_cube_libre(pos_impact, matiere)
	var type_eff := _type_effondrement_de_cellule(cellule)
	if type_eff != "meuble":
		return
	# Cascade : les autres sous-cubes du bloc se detachent aussi.
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
		# Casse sans passer par le compteur PV (effondrement instantane).
		_carte.casser_sous_cube(cellule, i)
		_spawn_sous_cube_libre(pos_i, matiere)

# PELLE : outil dans le monde. Composite Node3D (manche + lame). Se ramasse
# et se pose avec la touche E (indep. du clic gauche). Quand portee, le
# clic gauche CREUSE : +10 PV sur le sous-cube pointe (5 coups pour casser).
func _fabriquer_visuel_pelle() -> Node3D:
	var racine := Node3D.new()
	# Manche : BoxMesh vertical, bois marron.
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
	# Lame : BoxMesh en bas, fer gris.
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

# COLLIDER RAMASSABLE : StaticBody3D sur le LAYER_RAMASSABLE (mask 0), pose sur
# le visuel composite d'un outil pour que le raycast de ramassage le detecte.
# Nomme "StaticBody3D" pour que `_basculer_collision_cube_porte` le desactive
# pendant le portage -- sans ca, le raycast de creusage/bechage toucherait
# l'outil porte (1 m devant les yeux) au lieu du terrain.
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
	# Graines : parse `jeu/Proto/pelles_initiales.json` (patron
	# `data/banc_affordances_portage.json`, liste locale au banc). N=1000
	# pelles ne passent JAMAIS ici : population = mecanique de jeu qui
	# appelle `_spawn_pelle(pos)` (fabrication, drop, spawn). Ce fichier
	# n'est que la graine de proto. Aucun noeud d'editeur, aucune Node par
	# entite. Y du JSON ignoree : snap au sol via `carte.sommet(x, z)`.
	var chemin := "res://jeu/Proto/pelles_initiales.json"
	var fichier := FileAccess.open(chemin, FileAccess.READ)
	if fichier == null:
		return
	var texte := fichier.get_as_text()
	fichier.close()
	var parse: Variant = JSON.parse_string(texte)
	if not (parse is Dictionary):
		push_warning("pelles_initiales.json : racine attendue Dictionary")
		return
	var liste: Variant = (parse as Dictionary).get("pelles", [])
	if not (liste is Array):
		return
	for entree in (liste as Array):
		if not (entree is Dictionary):
			continue
		var arr: Variant = (entree as Dictionary).get("position", null)
		if not (arr is Array) or (arr as Array).size() < 3:
			continue
		var pos := Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
		if _carte != null:
			var y_sol: Variant = _carte.sommet(pos.x, pos.z)
			if y_sol != null:
				pos.y = float(y_sol) + 0.5
		_spawn_pelle(pos)

func _spawn_pelle(pos: Vector3) -> void:
	var id_neuf: String = "pelle_%d" % _prochain_id_tas
	_prochain_id_tas += 1
	var p := {
		"id": id_neuf,
		"position": pos,
		"vitesse_y": 0.0,
		"noeud": null,
		"matiere": "pelle",
	}
	_monde_tas.ajouter(p, "pelle", pos)

# RAYCAST RAMASSABLE : depuis la camera, centre ecran, filtre sur
# LAYER_RAMASSABLE -- ne touche donc QUE des outils au sol (jamais terrain ni
# cube libre, layer 1). Retrouve l'entree du `_monde_tas` dont le noeud est le
# visuel composite touche (le collider est enfant de ce visuel). Rend le dict
# du sous-cube, ou {} si rien. Calque de `_sous_cube_sous_viseur` pour
# l'origine, la direction et l'exclusion du joueur.
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
	# stocke dans l'entree du _monde_tas. Remonte au parent pour le comparer.
	var racine := (collider as Node).get_parent()
	if racine == null:
		return {}
	if _observateur == null:
		return {}
	var proches: Array = _monde_tas.choses_dans_rayon(_observateur.global_position, RAYON_PRENDRE_METRES * 2.0)
	for e in proches:
		var sc: Dictionary = e.chose
		if sc.get("noeud", null) == racine:
			return sc
	return {}

# Toggle E GENERIQUE : un seul geste, un seul raycast, pour tous les outils
# portables (pelle, beche, futurs). Cas 1 : porte deja un OUTIL -> pose devant
# le joueur (matiere lue sur _cube_porte, jamais hardcodee). Cas 2 : ne porte
# rien -> raycast ramassable, prend l'outil vise. Rend true si l'action a eu
# lieu.
#
# CHOIX : le cas pose ne concerne QUE les outils (pelle/beche). Un cube libre
# porte garde son chemin dedie au clic gauche (avec _index_ajouter) -- E ne le
# pose pas, exactement comme avant. Sans ca, l'index des cubes libres divergerait.
func toggle_prendre_poser_e(origine: Vector3, direction: Vector3) -> bool:
	# Cas 1 : porte deja un outil -> pose devant le joueur.
	var mat_portee: String = String(_cube_porte.get("matiere", "")) if not _cube_porte.is_empty() else ""
	if mat_portee == "pelle" or mat_portee == "beche":
		if _observateur == null:
			return false
		var pos_pose: Vector3 = origine + direction.normalized() * 1.5
		if _carte != null:
			var y_sol: Variant = _carte.sommet(pos_pose.x, pos_pose.z)
			if y_sol != null:
				pos_pose.y = float(y_sol) + 0.5
		# Reactive le collider ramassable avant de reposer au sol (il etait
		# desactive pendant le portage pour ne pas polluer le raycast creuser).
		_basculer_collision_cube_porte(true)
		_cube_porte.position = pos_pose
		_monde_tas.ajouter(_cube_porte, mat_portee, pos_pose)
		if _cube_porte.noeud != null and is_instance_valid(_cube_porte.noeud):
			(_cube_porte.noeud as Node3D).global_position = pos_pose
		_cube_porte = {}
		return true
	# On porte autre chose (cube libre) : E ne fait rien.
	if not _cube_porte.is_empty():
		return false
	# Cas 2 : ne porte rien -> raycast ramassable.
	var cible := _objet_ramassable_sous_viseur(RAYON_PRENDRE_METRES)
	if cible.is_empty():
		return false
	_monde_tas.retirer(cible.id)
	_cube_porte = cible
	# Le noeud existe deja (c'est son collider qu'on vient de toucher). Desactive
	# son collider pendant le portage.
	_basculer_collision_cube_porte(false)
	return true

# Creuser avec la pelle : 10 PV sur le sous-cube pointe. 5 coups pour casser.
# Raycast physique depuis la camera, centre ecran, contre la GridMap streamee.
# Rend {cellule: Vector3i, idx: int, point: Vector3} ou {}. SPECIFIQUE JOUEUR :
# depend de terrain_visible autour de l'observateur -- inutilisable pour un
# acteur hors streaming (ennemi qui creuserait a 5 km). Le jour ou un autre
# acteur doit creuser : version data pure, ray-marching sur carte_terrain.
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
	# Exclure le corps du joueur : sans ca, le raycast plonge dans sa propre
	# capsule quand on regarde vers le bas, touche ce collider (qui n'est pas
	# un GridMap), le test is GridMap echoue -> le halo ne s'affiche jamais
	# pour un sol pourtant clairement visible.
	if _observateur != null and _observateur is CollisionObject3D:
		requete.exclude = [(_observateur as CollisionObject3D).get_rid()]
	var frappe := espace.intersect_ray(requete)
	if frappe.is_empty():
		return {}
	# NE PAS filtrer sur `frappe.collider is GridMap` : les cellules ENTAMEES
	# ont leur collision refaite par terrain_visible en StaticBody3D+BoxShape3D
	# (voir _poser_bodies_sous_cubes) -- filtrer sur GridMap rejetait toute
	# cellule deja creusee. Le point d'impact suffit a identifier cellule+idx
	# par arithmetique ; les gates aval (est_pleine, couche_base) filtrent
	# les cas non-terrain (ennemi, arme).
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
	# Visible SEULEMENT quand un sous-cube libre (non pelle) est porte.
	if not porteur_a_cube() or porte_pelle():
		if _halo_pose.visible:
			_halo_pose.visible = false
		return
	var cible := _sous_cube_sous_viseur(PORTEE_PELLE_METRES)
	if cible.is_empty():
		if _halo_pose.visible:
			_halo_pose.visible = false
		return
	# Cellule cible = point d'impact decale d'un demi sous-cube dans la
	# direction de la normale = centre du sous-cube adjacent a la face touchee.
	# Puis OFFSET dans la direction du regard pour eloigner du joueur -- sinon
	# viser tes pieds fait apparaitre le halo pile sur toi. Camera -> point.
	var point: Vector3 = cible["point"]
	var normale: Vector3 = cible["normal"]
	var cote_sous: float = cote_cellule / 3.0
	var centre_pose := point + normale * (cote_sous * 0.5)
	# Offset regard : 1 cellule (2m) vers la direction pointee.
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

# Halo de visee pour la pelle. Cube filaire (BoxMesh en wireframe via NEXT_PASS
# transparent) de taille sous-cube, jaune emissif, top-level pour ignorer la
# transform du parent Node.
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
	# Cout de faim au coup REUSSI (raycast touche un sous-cube plein),
	# jamais au clic dans le vide. Flux generique -- meme verbe pour tout
	# outil de travail futur (hache, marteau, etc.).
	if _observateur != null and _observateur.has_method("depenser_pour_travail"):
		_observateur.call("depenser_pour_travail", COUT_CREUSER_PAR_COUP)
	return true

# PORTAGE D'UN SOUS-CUBE LIBRE (etape 1 : porter/poser sans reformation).
# API publique appelee par arme_tir au clic gauche pour prioriser sur mêlée.

func porteur_a_cube() -> bool:
	return not _cube_porte.is_empty()

# Vrai si l'objet porte est la pelle (par opposition a un sous-cube libre).
# Sert a arme_tir pour verrouiller le clic gauche sur "creuser" quand la
# pelle est en main -- sans ca, un raycast rate ferait tomber la pelle.
func porte_pelle() -> bool:
	return not _cube_porte.is_empty() and _cube_porte.get("matiere", "") == "pelle"

# ================= BECHE (calque du bloc pelle) =================
# Meme organisation, meme emplacement, memes signatures que la pelle. La
# logique interne differe : la beche ne casse pas un sous-cube coup par coup,
# elle compte les coups sur la cellule de terre (carte_terrain.ajouter_coups_
# beche). Au dixieme coup, la cellule devient "bloc_beche" (terre fertile) et
# sa couche superieure de sous-cubes est retiree pour la rendre plus basse.

# BECHE : outil dans le monde. Composite Node3D (manche + lame large). Se
# ramasse et se pose avec la touche dediee. Quand portee, le geste BECHE :
# compte un coup sur la cellule de terre pointee (10 coups pour transformer).
func _fabriquer_visuel_beche() -> Node3D:
	var racine := Node3D.new()
	# Manche : BoxMesh vertical, bois marron (identique a la pelle).
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
	# Lame : BoxMesh en bas, plus LARGE en X et plus ETROITE en Z que la pelle,
	# fer gris plus sombre (distingue la beche de la pelle en main).
	var lame := MeshInstance3D.new()
	var mesh_lame := BoxMesh.new()
	mesh_lame.size = Vector3(0.35, 0.05, 0.10)
	var mat_lame := StandardMaterial3D.new()
	mat_lame.albedo_color = Color(0.4, 0.4, 0.45, 1.0)
	mat_lame.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_lame.material = mat_lame
	lame.mesh = mesh_lame
	lame.position = Vector3(0.0, -0.35, -0.08)
	lame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	racine.add_child(lame)
	_ajouter_collision_ramassable(racine)
	return racine

func _spawn_beche_initiale() -> void:
	# Graines : parse `jeu/Proto/beches_initiales.json` (meme organisation que
	# `pelles_initiales.json`). N=1000 beches ne passent JAMAIS ici :
	# population = mecanique de jeu qui appelle `_spawn_beche(pos)`. Ce fichier
	# n'est que la graine de proto. Y du JSON ignoree : snap au sol.
	var chemin := "res://jeu/Proto/beches_initiales.json"
	var fichier := FileAccess.open(chemin, FileAccess.READ)
	if fichier == null:
		return
	var texte := fichier.get_as_text()
	fichier.close()
	var parse: Variant = JSON.parse_string(texte)
	if not (parse is Dictionary):
		push_warning("beches_initiales.json : racine attendue Dictionary")
		return
	var liste: Variant = (parse as Dictionary).get("beches", [])
	if not (liste is Array):
		return
	for entree in (liste as Array):
		if not (entree is Dictionary):
			continue
		var arr: Variant = (entree as Dictionary).get("position", null)
		if not (arr is Array) or (arr as Array).size() < 3:
			continue
		var pos := Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
		if _carte != null:
			var y_sol: Variant = _carte.sommet(pos.x, pos.z)
			if y_sol != null:
				pos.y = float(y_sol) + 0.5
		_spawn_beche(pos)

func _spawn_beche(pos: Vector3) -> void:
	var id_neuf: String = "beche_%d" % _prochain_id_tas
	_prochain_id_tas += 1
	var b := {
		"id": id_neuf,
		"position": pos,
		"vitesse_y": 0.0,
		"noeud": null,
		"matiere": "beche",
	}
	_monde_tas.ajouter(b, "beche", pos)

# Becher : compte un coup sur la cellule de terre pointee. Gates identiques a
# creuser_avec_pelle. Au coup qui atteint le seuil (ajouter_coups_beche rend
# true) : transforme la cellule en bloc_beche et retire les 9 sous-cubes de la
# couche superieure (iy=2) pour la rendre plus basse que ses voisines.
#
# ORDRE poser_cellule PUIS casser_sous_cube : poser_cellule ecrit l'item dans
# particularites et remet la couche pleine (poser_masque), sans toucher
# _masques_sous_cube -- les 9 casser_sous_cube qui suivent operent donc sur le
# masque sous-cube courant de la cellule. CELLULE PRE-ENTAMEE : si un tir avait
# deja casse un sous-cube du haut, casser_sous_cube rend false en silence sur
# celui-la (deja absent) ; la representation "plus basse" est alors partielle.
# Tolere en proto.
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
	if seuil_atteint:
		# Transformation : la cellule devient marqueur "bloc_beche" (fertile).
		if _index_bloc_beche >= 0:
			_carte.poser_cellule(cellule, _index_bloc_beche, 0)
		# Retire la couche superieure de sous-cubes (iy=2) : la cellule
		# descend d'un tiers, legerement plus basse que ses voisines.
		for ix in range(3):
			for iz in range(3):
				_carte.casser_sous_cube(cellule, ix + 2 * 3 + iz * 9)
	# Cout de faim au coup REUSSI (cellule de terre plein touchee), jamais au
	# clic dans le vide. Meme flux generique que la pelle.
	if _observateur != null and _observateur.has_method("depenser_pour_travail"):
		_observateur.call("depenser_pour_travail", COUT_BECHER_PAR_COUP)
	return true

# Halo de visee pour la beche. Cube filaire de taille sous-cube, marron
# emissif (distinct du jaune pelle et du vert pose), top-level.
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

# Vrai si l'objet porte est la beche (par opposition a la pelle ou un sc libre).
func porte_beche() -> bool:
	return not _cube_porte.is_empty() and _cube_porte.get("matiere", "") == "beche"

# Cherche le sous-cube libre le plus proche du joueur devant lui, dans un cone
# etroit et un rayon court. Si trouve : retire du monde (mais garde son noeud
# visuel) et le met en portage. Rend true si un cube a ete pris.
func porteur_prendre_si_proche(_origine: Vector3, _direction: Vector3) -> bool:
	if not _cube_porte.is_empty():
		return false
	# Selection par RAYCAST (meme regle que la pelle) : on prend uniquement
	# le sc pile pointe par le viseur, pas les sc au hasard dans un rayon
	# spherique aveugle qui attrapait des cubes hors camera.
	var cible := _sous_cube_sous_viseur(PORTEE_PELLE_METRES)
	if cible.is_empty():
		return false
	var point: Vector3 = cible["point"]
	var cote_sous: float = cote_cellule / 3.0
	var tolerance2: float = cote_sous * cote_sous
	var meilleur = null
	var meilleur_d2: float = tolerance2
	for w in _monde_tas.choses.values():
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
	_index_retirer(meilleur)
	_monde_tas.retirer(meilleur.id)
	_cube_porte = meilleur
	# S'il n'a pas de noeud (etait hors rayon rendu), on en fabrique un.
	if _cube_porte.noeud == null or not is_instance_valid(_cube_porte.noeud):
		var parent := get_parent()
		if parent != null:
			var n := MeshInstance3D.new()
			n.mesh = _mesh_pour_matiere(_cube_porte.get("matiere", "terre"))
			n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_ajouter_collision_cube_libre(n)
			parent.add_child(n)
			_cube_porte.noeud = n
	# Cube en main : collision desactivee pour ne pas bloquer le joueur.
	_basculer_collision_cube_porte(false)
	return true

# Pose le cube porte a la position pointee par le viseur, snappe a la grille
# 3x3x3. Etape 1 : reste sous-cube libre (pas de reformation). Le cube est
# reinjecte dans _monde_tas a sa nouvelle position.
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
	_monde_tas.ajouter(_cube_porte, "sous_cube", cible)
	_index_ajouter(_cube_porte)
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

func _ticker_tas(delta: float) -> void:
	if _monde_tas.choses.is_empty() or _carte == null:
		return
	var cote_sous: float = cote_cellule / 3.0
	# Grouper les sc mobiles par COLONNE sous-cube (x_sc, z_sc). Un sc voit
	# uniquement les autres sc de sa propre colonne pour calculer son sol
	# effectif : sol_terrain + n_sc_stables_en_dessous * cote_sous.
	var par_colonne: Dictionary = {}  # Vector2i -> Array de sc (mobiles)
	for w in _monde_tas.choses.values():
		var t: Dictionary = w.chose
		if t.get("matiere", "") == "pelle" or t.get("matiere", "") == "beche":
			continue
		var pos: Vector3 = t.position
		var col := Vector2i(int(floor(pos.x / cote_sous)), int(floor(pos.z / cote_sous)))
		if not par_colonne.has(col):
			par_colonne[col] = []
		(par_colonne[col] as Array).append(t)
	# Pour chaque colonne : tri par Y croissant, empilement du bas vers le haut.
	for col in par_colonne.keys():
		var sc_liste: Array = par_colonne[col]
		sc_liste.sort_custom(func(a, b): return a.position.y < b.position.y)
		var x_centre: float = float(col.x) * cote_sous + cote_sous * 0.5
		var z_centre: float = float(col.y) * cote_sous + cote_sous * 0.5
		var y_sol_terrain_v: Variant = _carte.sommet(x_centre, z_centre)
		if y_sol_terrain_v == null:
			continue
		var y_sol_terrain: float = float(y_sol_terrain_v)
		# Hauteur du sommet de la pile DEJA stable (croit au fur et a mesure).
		var y_pile_stable: float = y_sol_terrain
		for t in sc_liste:
			var pos: Vector3 = t.position
			var sol_y: float = y_pile_stable + cote_sous * 0.5
			var change := false
			if pos.y > sol_y:
				t.vitesse_y -= GRAVITE_TAS * delta
				pos.y += t.vitesse_y * delta
				if pos.y < sol_y:
					pos.y = sol_y
					t.vitesse_y = 0.0
				change = true
			elif pos.y < sol_y:
				pos.y = sol_y
				t.vitesse_y = 0.0
				change = true
			if change:
				t.position = pos
				_monde_tas.deplacer(t)
			# Ce sc est maintenant considere comme faisant partie de la pile
			# (meme s'il est encore en chute) -> son sommet ajoute cote_sous
			# au sol effectif du suivant.
			y_pile_stable = pos.y + cote_sous * 0.5

# Conservation de la masse : un cube libre pose au sol doit bloquer le corps
# du joueur (empilable comme un vrai bloc). Un StaticBody3D+BoxShape3D est
# ajoute au MeshInstance3D visuel du cube -- streame avec lui.
func _ajouter_collision_cube_libre(visuel: Node3D) -> void:
	if visuel == null:
		return
	if visuel.get_node_or_null("StaticBody3D") != null:
		return
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var cote_sous: float = cote_cellule / 3.0
	box.size = Vector3(cote_sous, cote_sous, cote_sous)
	shape.shape = box
	body.add_child(shape)
	visuel.add_child(body)

# Pendant le portage, la collision du cube porte bloquerait le corps du
# joueur (le cube est devant les yeux). Desactivee au portage, reactivee
# a la pose.
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
	# Requete locale : seuls les tas dans le rayon rendu sont candidats a
	# recevoir un noeud visuel. Cout O(rayon), pas O(N).
	var proches: Array = _monde_tas.choses_dans_rayon(pos_obs, rayon_rendu)
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
				mi.mesh = _mesh_pour_matiere(t.get("matiere", "terre"))
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				_ajouter_collision_cube_libre(mi)
				n = mi
			parent.add_child(n)
			n.global_position = t.position
			t.noeud = n
		else:
			(t.noeud as Node3D).global_position = t.position
	# Ceux hors rayon : queue_free du noeud, null.
	for w in _monde_tas.choses.values():
		var tas: Dictionary = w.chose
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
	if not spawn_ennemis_actif:
		return
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
		# Machine a etats grimpe (morceau 7). Defaut = chasse.
		"etat": "chasse",
		"cible_cellule": null,
		"derniere_cible_creusee": null,  # pour poser en direction du bloc
		"sc_porte": null,
		"cooldown_creusage": 0.0,
		"cooldown_grimpe": 0.0,  # anti-boucle chasse/cherche apres echec
		"derniere_direction_chasse": Vector3(1.0, 0.0, 0.0),
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
			# Cadavre : sc immobile a la position de mort, tombe par gravite data
			# puis reste (sandpile skip via `immobile: true`). Collision StaticBody
			# du sc bloque le joueur : on peut marcher dessus. Persiste jusqu'au
			# cap MAX_TAS, pas de degradation timee.
			_spawn_sous_cube_libre(e.position, "cadavre", true)
			if e.noeud != null and is_instance_valid(e.noeud):
				e.noeud.queue_free()
			_ennemis.remove_at(i)
			continue
		var pos: Vector3 = e.position
		# Cooldowns tick partout (meme etats non-creuse) : ainsi apres un cycle
		# grimpe complet, le prochain coup n'est pas instantane.
		if float(e.get("cooldown_creusage", 0.0)) > 0.0:
			e.cooldown_creusage = max(0.0, float(e.cooldown_creusage) - delta)
		if float(e.get("cooldown_grimpe", 0.0)) > 0.0:
			e.cooldown_grimpe = max(0.0, float(e.cooldown_grimpe) - delta)
		var etat: String = String(e.get("etat", "chasse"))
		var vers: Vector3 = pos_obs - pos
		vers.y = 0.0
		# Memoriser la derniere direction chasse (utile pour pose meme si
		# stationnaire pendant creuse).
		if vers.length() > 0.1:
			e.derniere_direction_chasse = vers.normalized()
		# DISPATCH machine a etats grimpe.
		match etat:
			"chasse":
				# Comportement de base : poursuite du joueur.
				if vers.length() > 0.5:
					var direction := vers.normalized()
					var candidat: Vector3 = pos + direction * vitesse_ennemi * delta
					if _mouvement_bloque_par_terrain(pos, candidat):
						# Obstacle detecte -> tenter grimpe SEULEMENT si pas
						# en cooldown apres un echec recent (evite boucle
						# infinie chasse/cherche_sc contre mur infranchissable).
						if float(e.cooldown_grimpe) <= 0.0:
							var cellule: Variant = _ennemi_bloc_creusable_proche(pos, RAYON_ENNEMI_CHERCHE_BLOC)
							if cellule != null:
								e.etat = "creuse"
								e.cible_cellule = cellule
							else:
								# Aucun bloc creusable -> abandon temporaire.
								e.cooldown_grimpe = 3.0
					else:
						pos = candidat
			"creuse":
				# Stationnaire. Applique PV sur cible avec cadence. Detection
				# de casse = sc individuel (pas cellule entiere) : un seul sc
				# suffit pour ramasser et poser (marche 1 sc de haut).
				if e.get("cible_cellule", null) == null:
					e.etat = "chasse"
				elif float(e.cooldown_creusage) <= 0.0:
					var casse: bool = _ennemi_creuser(e.cible_cellule as Vector3i)
					e.cooldown_creusage = CADENCE_ENNEMI_CREUSAGE
					# Cout nourriture par coup de creusage (effort du geste),
					# applique meme si la casse n'a pas encore lieu.
					if e.nourriture > 0.0:
						e.nourriture = max(0.0, float(e.nourriture) - COUT_NOURRITURE_CREUSAGE_PAR_COUP)
						_rafraichir_barre_nourriture_ennemi(e)
					if casse:
						# Memorise la cellule pour orienter la pose vers elle.
						e.derniere_cible_creusee = e.cible_cellule
						e.cible_cellule = null
						e.etat = "cherche_sc"
			"cherche_sc":
				# Ramasser sc libre proche (nouvellement genere par le creusage).
				var sc: Variant = _ennemi_ramasser_sc_proche(pos, RAYON_ENNEMI_RAMASSE)
				if sc != null:
					e.sc_porte = sc
					e.etat = "pose"
				else:
					# Aucun sc a portee (peut etre tombe hors de vue) -> retour
					# chasse avec cooldown pour eviter la boucle chasse/cherche.
					e.cooldown_grimpe = 3.0
					e.etat = "chasse"
			"pose":
				# Pose en direction de la cellule qu'on a creusee (pied du mur
				# a escalader), pas vers le joueur -- sinon la marche atterrit
				# a cote au lieu de servir a monter.
				if e.get("sc_porte", null) != null:
					var dir_pose: Vector3 = e.derniere_direction_chasse
					if e.get("derniere_cible_creusee", null) != null:
						var cible: Vector3i = e.derniere_cible_creusee
						var centre_cellule := Vector3(
							float(cible.x) * cote_cellule + cote_cellule * 0.5,
							pos.y,
							float(cible.z) * cote_cellule + cote_cellule * 0.5)
						var vers_cellule: Vector3 = centre_cellule - pos
						vers_cellule.y = 0.0
						if vers_cellule.length() > 0.001:
							dir_pose = vers_cellule.normalized()
					var pose_ok: bool = _ennemi_poser_sc_devant(pos, dir_pose, e.sc_porte)
					if pose_ok:
						e.sc_porte = null
				e.etat = "chasse"
		# CHUTE ET GRAVITE EN DATA (doctrine). Sommet EFFECTIF (terrain + sc
		# libres empiles sur la colonne SC de l'ennemi) via `_sommet_effectif`
		# -- sans ca, un ennemi qui marche sur une pile de sc libres passe au
		# travers. Marche PARTOUT, aucun gate distance.
		if _carte != null:
			var y_haut: Variant = _sommet_effectif(pos.x, pos.z, pos.y + cote_cellule / 3.0 * 0.5)
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
		# NOURRITURE : cout horizontal (X/Z) + cout MONTEE (dy positif seul,
		# tomber ne coute rien). Monter est un effort physique 5x plus cher
		# que marcher a plat.
		var pos_avant: Vector3 = e.position
		var deplacement := Vector3(pos.x - pos_avant.x, 0.0, pos.z - pos_avant.z)
		var dist := deplacement.length()
		var dy: float = pos.y - pos_avant.y
		var cout: float = COUT_NOURRITURE_PAR_M * dist
		if dy > 0.0:
			cout += COUT_NOURRITURE_PAR_M_MONTEE * dy
		if cout > 0.0 and e.nourriture > 0.0:
			e.nourriture = max(0.0, e.nourriture - cout)
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
