# BANC DE PEUPLEMENT ARBRE.
#
# Population d'arbres statiques qui pousse et se reproduit librement. Le
# banc est un CABLAGE : la logique passe par les mecanismes du coeur
# (`scripts/objet.gd:fabriquer`, `scripts/senescence.gd:avancer`,
# `scripts/stade.gd:avancer`), le banc n'invente ni age, ni seuil de stade,
# ni construction d'arbre. Le stockage de masse reste en colonnes
# paralleles (PackedArrays), le rendu reste sur deux MultiMesh. Trois
# couches, jamais confondues.
#
# COUCHE STOCKAGE DE MASSE (banc) : `_ages`, `_libres`,
# `_positions_x/z`, `_slot_stade`, `_facteur_croissance`,
# `_facteur_longevite`, `_slots_libres`. La population entiere y vit --
# aucun Dictionary par arbre.
#
# COUCHE LOGIQUE (coeur) : un SEUL Dictionary TAMPON reutilise arbre par
# arbre pour franchir la frontiere vers les mecanismes du coeur. Le banc
# remplit le tampon depuis les colonnes de l'arbre i, appelle
# `Senescence.avancer` (age) puis `Stade.avancer` (stade), relit les deux
# valeurs mutees vers les colonnes. Zero allocation par arbre dans la
# boucle : le tampon est alloue UNE fois, ses cles reecrites.
#
# COUCHE RENDU (banc) : deux MultiMesh partagees (tronc + feuillage), un
# slot par arbre au meme index. Le MultiMesh LIT le stade pose par le
# coeur et en derive la taille (interpolation entre les entrees
# `stades[i]` du catalogue local). Le coeur ne touche jamais le rendu.
#
# FABRICATION VIA `Objet.fabriquer` : catalogue combine construit une fois
# au `_ready` (paquet `dynamique` extrait de `data/types.json` + type
# local `arbre_pousse` qui herite de `dynamique` et pose `stades_config`).
# Chaque naissance appelle `Objet.fabriquer("arbre_<slot>", "arbre_pousse",
# position, catalogue, {}, [], {}, [], true)` -- resultat NON stocke
# (couche stockage tient tout), on extrait `age` initial et on cache
# `stades_config` la premiere fois. Le type `arbre_pousse` est LOCAL
# (data/banc_peuplement_arbre.json) -- pas de modification de
# data/types.json (lecture seule framework). Le type framework `arbre`
# herite de `objet_physique` seul, sans `dynamique` (donc sans `age` ni
# `stades_config`) ; c'est ce manque qui justifie le type local.
#
# BANQUE DE GRAINES DORMANTES : registre delegue au mecanisme framework
# `scripts/attente_seuil.gd` (ajouter/retirer/prospects). Le tick de
# banque itere `prospects()` directement -- chaque graine porte sa
# propre `prochaine_echeance` (cle libre, `attente_seuil` ne la lit
# jamais), tiree seedee dans [0, _intervalle_retest[ a l'ajout et
# repoussee de `_intervalle_retest` a chaque re-test rate. `avancer`
# n'est plus appele (il compare a un seuil unique, il ne connait pas
# l'echeance par graine). Les levees s'etalent au lieu de pulser.
#
# MECANIQUES ENCORE INLINE (manque framework a signaler, ne PAS bricoler
# davantage) :
# - CHAMP DE COUVERT (`_couvert`, Dictionary Vector2i -> float) : chaque
#   arbre y ecrit son ombrage a la naissance, retire a la mort, redepose
#   au changement de stade ; la graine y LIT en O(1). `scripts/champ.gd`
#   est une force qui deplace, pas un champ scalaire lisible ;
#   `jeu/Outil de jeu/champ_spatial.gd` est un compte entier +1/-1
#   uniforme. Un mecanisme cadre `champ_saturation.gd` (float, depot
#   signe sur carre de cases) manque au coeur.
#
# VARIANCES INDIVIDUELLES : `scripts/facteur_variance.gd` (mecanisme cadre
# neuf, teste hors domaine) deja en place. `_facteur_croissance[i]`
# multiplie le `annees_par_seconde` passe a `Senescence.avancer`
# (rythme individuel) ; `_facteur_longevite[i]` multiplie le seuil de
# mort (compare a l'age reel).
#
# ECART FRAMEWORK : ce banc + son catalogue local sont neufs, voir
# CLAUDE.md § Frontiere.

extends Node

const Objet = preload("res://scripts/objet.gd")
const Senescence = preload("res://scripts/senescence.gd")
const Stade = preload("res://scripts/stade.gd")
const FacteurVariance = preload("res://scripts/facteur_variance.gd")
const AttenteSeuil = preload("res://scripts/attente_seuil.gd")
const Monde = preload("res://scripts/monde.gd")
const JoueurBanc = preload("res://jeu/bancs/joueur_banc.gd")

const CHEMIN_CATALOGUE_LOCAL := "res://data/banc_peuplement_arbre.json"
const CHEMIN_TYPES := "res://data/types.json"

# Hauteur du sol visuel monte par _monter_scene. La base des troncs y est posee.
const Y_SOL := 12.0

# Capacite initiale des deux MultiMesh (petite ; doublee par _agrandir_capacite
# quand aucun slot libre).
const CAPACITE_INITIALE := 8

# Position horizontale du premier arbre (l'arbre initial).
const POS_INITIALE := Vector2(0.0, 0.0)

# Cadence du releve population imprime dans la console (~1/s a 60 fps).
const CADENCE_RELEVE_POPULATION_FRAMES := 60

# Seuil de nettoyage d'une case du champ dont le cumul retombe sous cette
# valeur absolue (evite les zeros residuels de float qui polluent le Dict).
const EPS_COUVERT := 1.0e-6

# Nom du type local declare dans le catalogue combine et resolu par
# `Objet.fabriquer`.
const TYPE_ARBRE := "arbre_pousse"

var _durees: PackedFloat32Array = PackedFloat32Array()
var _stades: Array = []
var _duree_mort: float = 180.0
var _duree_croissance_totale: float = 0.0
var _debut_fertilite: float = 0.0
var _fin_fertilite: float = 0.0
var _mode_test_rapide: bool = false
# Demi-etendue de la carte en unites monde. Le sol est un carre de cote
# `2 * _demi_carte` centre a l'origine ; toute graine dont la position
# tombe hors [-_demi_carte, +_demi_carte] en x ou z est rejetee (perdue,
# ne germe pas). UNE seule source de verite -- le sol de _monter_scene
# et la garde de _deposer_graine derivent tous deux de cette valeur.
var _demi_carte: float = 300.0
# Gate : true = le joueur (CharacterBody3D, exception CLAUDE.md) est
# instancie et sa camera est current ; false = pas de joueur, la camera
# plongeante de la scene devient current.
var _joueur_actif: bool = true
var _graine_rng: int = 20260910
var _intervalle_graine_moyen: float = 10.0
var _rayon_graine: float = 6.0
var _stade_fertile_debut: int = 5
var _stade_fertile_fin: int = 7
var _taille_case: float = 20.0
var _seuil_couvert: float = 0.5
var _intervalle_retest: float = 5.0
# Gate d'etablissement au point de chute (patron vegetation.gd:trouee_suffisante) :
# rayon en unites monde, seuil en nombre d'arbres. La graine tombee compte
# les arbres deja inscrits dans _monde autour de son point d'arrivee ;
# au-dela du seuil, elle est perdue.
var _rayon_trouee: float = 4.0
var _trouee_max_voisins: int = 1

# MORT PAR COMPETITION (auto-eclaircie). Passe rare pilotee par
# `_cadence_competition` (secondes). Seuls les stades <= `_stade_competition_max`
# (1..8) sont vulnerables -- les adultes dominent et survivent. Un arbre
# eligible compte ses voisins dans `_rayon_competition` via monde ; l'exces
# au-dela de `_competition_max_voisins` fixe la probabilite de mort ce pas
# (exces / _competition_max_voisins, borne 1). Le compte inclut soi-meme
# (distance 0), meme convention que vegetation.gd:peut_pousser -- le seuil
# en tient compte.
var _cadence_competition: float = 5.0
var _stade_competition_max: int = 4
var _rayon_competition: float = 3.0
var _competition_max_voisins: int = 3
var _temps_competition: float = 0.0
var _ombrage_par_stade: Array = []
# Bornes independantes pour les deux facteurs individuels (tires seedes
# a la naissance via facteur_variance.gd:tirer_entre). Asymetriques
# possibles : ex. longevite [0.5, 2.0] rend l'arbre du double au moitie
# de la duree moyenne, hors de portee d'un tirage symetrique.
var _croissance_min: float = 0.6
var _croissance_max: float = 1.6
var _longevite_min: float = 0.5
var _longevite_max: float = 2.0
# Facteur d'echelle senescence : delta * annees_par_seconde ajoute a age.
# Fixe a 1.0 par defaut (unites de temps du banc = "annees" par convention),
# pour que les seuils de `durees_stades` (secondes ecoulees ici) se lisent
# tels quels dans stades_config.
var _annees_par_seconde: float = 1.0

var _mm_tronc: MultiMesh = null
var _mm_feuillage: MultiMesh = null
var _noeud_tronc: MultiMeshInstance3D = null
var _noeud_feuillage: MultiMeshInstance3D = null

var _capacite: int = 0
var _ages: PackedFloat32Array = PackedFloat32Array()
var _libres: PackedByteArray = PackedByteArray()
var _positions_x: PackedFloat32Array = PackedFloat32Array()
var _positions_z: PackedFloat32Array = PackedFloat32Array()
var _slots_libres: Array = []
# Index dans _stades_config_partagee du stade courant de chaque slot
# (0..stades_config.size()-1 pour un vivant, -1 pour un slot libre ou un
# vivant avant tout franchissement -- meme convention que
# `stade.gd:_index_du_stade`).
var _slot_stade: PackedInt32Array = PackedInt32Array()
var _facteur_croissance: PackedFloat32Array = PackedFloat32Array()
var _facteur_longevite: PackedFloat32Array = PackedFloat32Array()

# Population vivante courante, tenue en O(1) : incrementee dans _naitre,
# decrementee dans _liberer_slot. Aucun scan par frame.
var _population: int = 0
var _frames_depuis_releve: int = 0

# Champ scalaire d'ombrage par case (Vector2i -> float). Une entree est
# supprimee quand son cumul retombe sous EPS_COUVERT.
var _couvert: Dictionary = {}

# Banque de graines dormantes deleguee au mecanisme framework
# scripts/attente_seuil.gd : le banc enregistre chaque graine comme
# prospect avec `position` ET `prochaine_echeance` (temps monde cumule
# de son prochain re-test). La phase initiale est tiree seedee dans
# [0, _intervalle_retest[ a l'ajout, puis avance de `_intervalle_retest`
# a chaque re-test rate. Consequence : les graines ne se reveillent
# plus toutes au meme tic, les levees s'etalent au lieu de pulser.
# `attente_seuil.gd` accepte les cles libres par entree, il ne les lit
# jamais (voir en-tete de attente_seuil.gd) -- `prochaine_echeance`
# voyage telle quelle, ce banc la mute en place via `prospects()`.
var _banque_graines: RefCounted = null
# Temps monde cumule dedie a la banque : chaque _tick_banque avance ce
# compteur et compare a la `prochaine_echeance` de chaque prospect.
var _temps_banque: float = 0.0

# INDEX SPATIAL DU COEUR. Chaque arbre est inscrit a la naissance et retire
# a la mort ; aucun lecteur du monde dans ce banc aujourd'hui, l'inscription
# prepare les mecaniques qui interrogeront le voisinage. `structure_simple`
# = true : les arbres ne bougent pas, chaque case reste un Array<id> a plat.
# Patron : banc_peuplement.gd:318-322.
var _monde: RefCounted = null
# Interface avec _monde : monde.gd:ajouter exige un Dictionary avec `id` et
# `position`. Une entree par slot vivant ({id, position}), null pour un slot
# libre. Les colonnes restent la source de verite pour age/stade/geometrie ;
# ce dict ne sert QU'A ajouter/retirer dans monde. Sans retrait, la mort
# resterait un fantome compte a sa place dans toute requete de densite.
var _choses_arbre: Array = []

var _rng := RandomNumberGenerator.new()

# Table combinee passee a Objet.fabriquer : paquet `dynamique` (extrait de
# data/types.json) + type local `arbre_pousse`. Construite une fois au
# _ready, jamais rechargee.
var _catalogue: Dictionary = {}
# Reference vers l'Array stades_config produit par Objet.fabriquer,
# partagee entre tous les arbres (paquets_partages=true garantit la meme
# reference pour toutes les instances). Assignee au premier _naitre.
var _stades_config_partagee: Array = []

# Dictionary TAMPON reutilise arbre par arbre pour franchir la frontiere
# vers Senescence.avancer / Stade.avancer. Alloue UNE fois au _ready, ses
# cles sont reecrites a chaque iteration.
var _tampon: Dictionary = {}

func _ready() -> void:
	_charger_reglages_locaux()
	_rng.seed = _graine_rng
	_monde = Monde.new()
	_monde.structure_simple = true
	_monter_scene()
	if _joueur_actif:
		_monter_joueur()
	_monter_population()
	_construire_catalogue()
	_init_tampon()
	_banque_graines = AttenteSeuil.new()
	if _stades.size() == 8:
		_naitre(POS_INITIALE.x, POS_INITIALE.y)

func _charger_reglages_locaux() -> void:
	if not FileAccess.file_exists(CHEMIN_CATALOGUE_LOCAL):
		push_error("banc_peuplement_arbre : catalogue local absent (%s)" % CHEMIN_CATALOGUE_LOCAL)
		return
	var texte := FileAccess.get_file_as_string(CHEMIN_CATALOGUE_LOCAL)
	if texte.is_empty():
		push_error("banc_peuplement_arbre : catalogue local vide (%s)" % CHEMIN_CATALOGUE_LOCAL)
		return
	var donnees = JSON.parse_string(texte)
	if not (donnees is Dictionary):
		push_error("banc_peuplement_arbre : catalogue local invalide (pas un objet)")
		return
	if donnees.has("durees_stades"):
		var brut_durees: Array = donnees.durees_stades
		_durees = PackedFloat32Array()
		for v in brut_durees:
			_durees.append(float(v))
	if donnees.has("stades"):
		_stades = donnees.stades
	if donnees.has("duree_mort"):
		_duree_mort = float(donnees.duree_mort)
	if donnees.has("mode_test_rapide"):
		_mode_test_rapide = bool(donnees.mode_test_rapide)
	if donnees.has("demi_carte"):
		_demi_carte = float(donnees.demi_carte)
	if donnees.has("joueur_actif"):
		_joueur_actif = bool(donnees.joueur_actif)
	if donnees.has("graine_rng"):
		_graine_rng = int(donnees.graine_rng)
	if donnees.has("intervalle_graine_moyen"):
		_intervalle_graine_moyen = float(donnees.intervalle_graine_moyen)
	if donnees.has("rayon_graine"):
		_rayon_graine = float(donnees.rayon_graine)
	if donnees.has("stade_fertile_debut"):
		_stade_fertile_debut = int(donnees.stade_fertile_debut)
	if donnees.has("stade_fertile_fin"):
		_stade_fertile_fin = int(donnees.stade_fertile_fin)
	_stade_fertile_debut = clampi(_stade_fertile_debut, 1, 8)
	_stade_fertile_fin = clampi(_stade_fertile_fin, _stade_fertile_debut, 8)
	if donnees.has("taille_case"):
		_taille_case = float(donnees.taille_case)
	if donnees.has("seuil_couvert"):
		_seuil_couvert = float(donnees.seuil_couvert)
	if donnees.has("intervalle_retest"):
		_intervalle_retest = float(donnees.intervalle_retest)
	if donnees.has("rayon_trouee"):
		_rayon_trouee = float(donnees.rayon_trouee)
	if donnees.has("trouee_max_voisins"):
		_trouee_max_voisins = int(donnees.trouee_max_voisins)
	if donnees.has("cadence_competition"):
		_cadence_competition = float(donnees.cadence_competition)
	if donnees.has("stade_competition_max"):
		_stade_competition_max = int(donnees.stade_competition_max)
	if donnees.has("rayon_competition"):
		_rayon_competition = float(donnees.rayon_competition)
	if donnees.has("competition_max_voisins"):
		_competition_max_voisins = int(donnees.competition_max_voisins)
	if donnees.has("ombrage_par_stade"):
		_ombrage_par_stade = donnees.ombrage_par_stade
	if donnees.has("croissance_min"):
		_croissance_min = float(donnees.croissance_min)
	if donnees.has("croissance_max"):
		_croissance_max = float(donnees.croissance_max)
	if donnees.has("longevite_min"):
		_longevite_min = float(donnees.longevite_min)
	if donnees.has("longevite_max"):
		_longevite_max = float(donnees.longevite_max)
	if donnees.has("annees_par_seconde"):
		_annees_par_seconde = float(donnees.annees_par_seconde)
	if _stades.size() != 8:
		push_error("banc_peuplement_arbre : `stades` doit contenir 8 entrees (recu %d)" % _stades.size())
	if _durees.size() != 7:
		push_error("banc_peuplement_arbre : `durees_stades` doit contenir 7 entrees (recu %d)" % _durees.size())
	if _ombrage_par_stade.size() != 8:
		push_error("banc_peuplement_arbre : `ombrage_par_stade` doit contenir 8 entrees (recu %d)" % _ombrage_par_stade.size())
	_duree_croissance_totale = 0.0
	for d in _durees:
		_duree_croissance_totale += float(d)
	# Bornes de fertilite lues du JSON (stade_fertile_debut/fin, 1..8, inclus).
	_debut_fertilite = 0.0
	var k: int = 0
	while k < _stade_fertile_debut - 1 and k < _durees.size():
		_debut_fertilite += float(_durees[k])
		k += 1
	_fin_fertilite = 0.0
	k = 0
	while k < _stade_fertile_fin and k < _durees.size():
		_fin_fertilite += float(_durees[k])
		k += 1

# Construit la table passee a Objet.fabriquer : paquet `dynamique` du
# framework (lu depuis data/types.json) + type local `arbre_pousse`. Aucune
# modification de data/types.json.
func _construire_catalogue() -> void:
	if not FileAccess.file_exists(CHEMIN_TYPES):
		push_error("banc_peuplement_arbre : %s absent" % CHEMIN_TYPES)
		return
	var texte_types := FileAccess.get_file_as_string(CHEMIN_TYPES)
	var types = JSON.parse_string(texte_types)
	if not (types is Dictionary):
		push_error("banc_peuplement_arbre : %s invalide" % CHEMIN_TYPES)
		return
	if not types.has("dynamique"):
		push_error("banc_peuplement_arbre : paquet `dynamique` absent de %s" % CHEMIN_TYPES)
		return
	_catalogue = {}
	_catalogue["dynamique"] = types.dynamique
	# stades_config du type local = suite des seuils cumules a partir de
	# durees_stades. Les noms "s1".."s8" sont arbitraires (stade.gd ne
	# connait aucun nom, il ne fait que comparer des index).
	var stades_config: Array = []
	var cumul: float = 0.0
	for i in range(8):
		stades_config.append({"nom": "s%d" % (i + 1), "age_seuil": cumul})
		if i < _durees.size():
			cumul += float(_durees[i])
	_catalogue[TYPE_ARBRE] = {
		"herite": ["dynamique"],
		"stades_config": stades_config,
	}

func _init_tampon() -> void:
	_tampon = {
		"id": "",
		"position": Vector3.ZERO,
		"proprietes": {
			"age": 0.0,
			"stades_config": [],
			"stade": "",
		},
	}

func _monter_scene() -> void:
	var sol := MeshInstance3D.new()
	var plan := PlaneMesh.new()
	plan.size = Vector2(_demi_carte * 2.0, _demi_carte * 2.0)
	var mat_sol := StandardMaterial3D.new()
	mat_sol.albedo_color = Color(0.3, 0.3, 0.3)
	plan.material = mat_sol
	sol.mesh = plan
	sol.position = Vector3(0.0, Y_SOL, 0.0)
	add_child(sol)
	# Collision statique du sol : sans elle, le CharacterBody3D du joueur
	# tomberait indefiniment. Une box tres plate (0.2 m) suffit et evite le
	# cas limite d'un plan infini a epaisseur nulle.
	var sol_corps := StaticBody3D.new()
	sol_corps.position = Vector3(0.0, Y_SOL - 0.1, 0.0)
	var sol_collision := CollisionShape3D.new()
	var sol_forme := BoxShape3D.new()
	sol_forme.size = Vector3(_demi_carte * 2.0, 0.2, _demi_carte * 2.0)
	sol_collision.shape = sol_forme
	sol_corps.add_child(sol_collision)
	add_child(sol_corps)
	var lumiere := DirectionalLight3D.new()
	lumiere.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(30.0), 0.0)
	lumiere.light_energy = 1.0
	lumiere.shadow_enabled = false
	add_child(lumiere)
	# Camera plongeante conservee mais NON-current : le joueur reprend le
	# point de vue avec sa propre camera. Le groupe "observateur" reste sur
	# elle -- aucun consommateur du groupe dans ce banc, verifie au grep.
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 55.0, 55.0)
	# current = true si le joueur est desactive (JSON `joueur_actif`=false),
	# sinon false : le joueur mettra sa propre camera current au _ready.
	camera.current = not _joueur_actif
	camera.add_to_group(&"observateur")
	add_child(camera)
	camera.look_at(Vector3(0.0, Y_SOL, 0.0), Vector3.UP)

# Instancie le joueur jetable (CharacterBody3D + capsule + Camera3D). Pose
# a 8 m de l'arbre initial pour ne pas naitre coince dans le tronc, un
# metre au-dessus du sol pour retomber proprement au premier tick de
# gravite. Exception joueur du CLAUDE.md : seul pont autorise entre le
# monde data et le rendu Godot.
func _monter_joueur() -> void:
	var joueur := JoueurBanc.new()
	joueur.position = Vector3(8.0, Y_SOL + 1.0, 8.0)
	add_child(joueur)

# Meshes UNITAIRES : CylinderMesh hauteur 1 rayon 0.5 (tronc droit,
# diametre 1 -- equivalent a l'ancienne BoxMesh de largeur 1, le scale
# par la largeur dans `_ecrire_slot` donne le meme diametre). CylinderMesh
# hauteur 1 rayon-bas 0.5 rayon-haut 0 (cone feuillage).
func _monter_population() -> void:
	var tronc_mesh := CylinderMesh.new()
	tronc_mesh.top_radius = 0.5
	tronc_mesh.bottom_radius = 0.5
	tronc_mesh.height = 1.0
	var mat_tronc := StandardMaterial3D.new()
	mat_tronc.albedo_color = Color(0.35, 0.22, 0.12)
	tronc_mesh.material = mat_tronc
	_mm_tronc = MultiMesh.new()
	_mm_tronc.transform_format = MultiMesh.TRANSFORM_3D
	_mm_tronc.mesh = tronc_mesh
	_mm_tronc.instance_count = CAPACITE_INITIALE
	_noeud_tronc = MultiMeshInstance3D.new()
	_noeud_tronc.multimesh = _mm_tronc
	# `_ecrire_slot` mute les transforms depuis `_process` (rendu par frame),
	# pas `_physics_process` : desactiver l'interpolation physique evite le
	# warning "MultiMesh interpolation triggered from outside physics process"
	# de Godot 4.5+, sans effet sur le rendu (arbres statiques par nature).
	_noeud_tronc.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_noeud_tronc)

	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.5
	cone.height = 1.0
	var mat_feuillage := StandardMaterial3D.new()
	mat_feuillage.albedo_color = Color(0.15, 0.45, 0.2)
	cone.material = mat_feuillage
	_mm_feuillage = MultiMesh.new()
	_mm_feuillage.transform_format = MultiMesh.TRANSFORM_3D
	_mm_feuillage.mesh = cone
	_mm_feuillage.instance_count = CAPACITE_INITIALE
	_noeud_feuillage = MultiMeshInstance3D.new()
	_noeud_feuillage.multimesh = _mm_feuillage
	_noeud_feuillage.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_noeud_feuillage)

	_capacite = CAPACITE_INITIALE
	_ages.resize(_capacite)
	_libres.resize(_capacite)
	_positions_x.resize(_capacite)
	_positions_z.resize(_capacite)
	_slot_stade.resize(_capacite)
	_facteur_croissance.resize(_capacite)
	_facteur_longevite.resize(_capacite)
	_choses_arbre.resize(_capacite)
	_slots_libres.clear()
	# Ordre inverse : pop_back rendra les slots dans l'ordre croissant.
	var i: int = _capacite - 1
	while i >= 0:
		_libres[i] = 1
		_ages[i] = 0.0
		_positions_x[i] = 0.0
		_positions_z[i] = 0.0
		_slot_stade[i] = -1
		_facteur_croissance[i] = 1.0
		_facteur_longevite[i] = 1.0
		_choses_arbre[i] = null
		_slots_libres.append(i)
		_ecrire_slot_vide(i)
		i -= 1

func _process(delta: float) -> void:
	if _stades.size() != 8 or _durees.size() != 7 or _stades_config_partagee.is_empty():
		return
	var pas: float = delta
	if _mode_test_rapide:
		pas *= 4.0
	# Capacite figee en debut de boucle.
	var cap: int = _capacite
	var i: int = 0
	while i < cap:
		if _libres[i] == 1:
			i += 1
			continue
		# Age reel compare au seuil de mort MODULE par la longevite individuelle.
		var seuil_mort: float = (_duree_croissance_totale + _duree_mort) * _facteur_longevite[i]
		# FRONTIERE COEUR : remplir le tampon depuis les colonnes de l'arbre i,
		# appeler Senescence + Stade, relire. Un seul Dictionary vivant, ses
		# cles reecrites -- aucune allocation par arbre.
		var tampon_props: Dictionary = _tampon.proprietes
		tampon_props.age = _ages[i]
		tampon_props.stades_config = _stades_config_partagee
		tampon_props.stade = _nom_du_stade(_slot_stade[i])
		Senescence.avancer(_tampon, pas, _annees_par_seconde * _facteur_croissance[i])
		Stade.avancer(_tampon)
		var age_i: float = tampon_props.age
		_ages[i] = age_i
		if age_i >= seuil_mort:
			_liberer_slot(i)
			i += 1
			continue
		# Detection de changement de stade -> maj du champ de couvert.
		var nouveau_index: int = _index_du_stade_nom(tampon_props.stade)
		var ancien: int = _slot_stade[i]
		if nouveau_index != ancien:
			if ancien >= 0:
				_deposer_ombrage(_positions_x[i], _positions_z[i], ancien + 1, -1)
			if nouveau_index >= 0:
				_deposer_ombrage(_positions_x[i], _positions_z[i], nouveau_index + 1, 1)
			_slot_stade[i] = nouveau_index
		# REPRODUCTION STOCHASTIQUE (processus de Poisson par individu) :
		# a chaque pas, un arbre fertile a une probabilite `pas /
		# _intervalle_graine_moyen` de semer UNE graine. La cadence
		# MOYENNE par arbre reste inchangee, mais les instants sont
		# desynchronises entre individus -- fin des vagues de cohortes
		# qui semaient au meme tic. Au plus une graine par pas et par
		# arbre (jamais de rafale). RNG seede : a seed egal, meme foret.
		if age_i >= _debut_fertilite and age_i < _fin_fertilite:
			if _rng.randf() < pas / _intervalle_graine_moyen:
				_semer_pres_de(i)
		_ecrire_slot(i, age_i)
		i += 1
	_tick_banque(pas)
	_temps_competition += pas
	if _temps_competition >= _cadence_competition:
		_temps_competition = 0.0
		_passe_competition()
	_frames_depuis_releve += 1
	if _frames_depuis_releve >= CADENCE_RELEVE_POPULATION_FRAMES:
		_frames_depuis_releve = 0
		var dormantes: int = 0 if _banque_graines == null else _banque_graines.nombre()
		print("[arbre] population = %d, dormantes = %d, cases_couvertes = %d" % [_population, dormantes, _couvert.size()])

# Nom du stade a l'index dans _stades_config_partagee. Index -1 -> "" :
# aucun stade encore atteint.
func _nom_du_stade(index: int) -> String:
	if index < 0 or index >= _stades_config_partagee.size():
		return ""
	return _stades_config_partagee[index].get("nom", "")

# Retrouve l'index d'un nom dans _stades_config_partagee (-1 pour ""
# ou nom absent).
func _index_du_stade_nom(nom: String) -> int:
	if nom == "":
		return -1
	for i in range(_stades_config_partagee.size()):
		if _stades_config_partagee[i].get("nom", "") == nom:
			return i
	return -1

# Interpolation de taille entre deux entrees consecutives du catalogue
# `stades` local (rendu, aucun rapport avec stade.gd qui ne pose que le
# nom). Rend un Vector4 (h_tronc, l_tronc, h_feuillage, l_feuillage).
func _calc_params(age: float) -> Vector4:
	var duree_cumulee: float = 0.0
	var n: int = _durees.size()
	var i: int = 0
	while i < n:
		var duree_segment: float = _durees[i]
		if age <= duree_cumulee + duree_segment:
			var t: float = 0.0
			if duree_segment > 0.0:
				t = (age - duree_cumulee) / duree_segment
			if t < 0.0:
				t = 0.0
			elif t > 1.0:
				t = 1.0
			var a: Dictionary = _stades[i]
			var b: Dictionary = _stades[i + 1]
			var ht: float = lerp(float(a.tronc.hauteur), float(b.tronc.hauteur), t)
			var lt: float = lerp(float(a.tronc.largeur), float(b.tronc.largeur), t)
			var hf: float = lerp(float(a.feuillage.hauteur), float(b.feuillage.hauteur), t)
			var lf: float = lerp(float(a.feuillage.largeur), float(b.feuillage.largeur), t)
			return Vector4(ht, lt, hf, lf)
		duree_cumulee += duree_segment
		i += 1
	var s: Dictionary = _stades[7]
	return Vector4(
		float(s.tronc.hauteur), float(s.tronc.largeur),
		float(s.feuillage.hauteur), float(s.feuillage.largeur))

# Ecrit les deux transforms du slot depuis les quatre parametres interpoles.
# Meshes sources UNITAIRES. Empilement : base du tronc a y=Y_SOL, base du
# feuillage au sommet du tronc. Feuillage a hauteur/largeur nulle : Basis
# a echelle nulle -> instance invisible.
func _ecrire_slot(i: int, age: float) -> void:
	var p: Vector4 = _calc_params(age)
	var ht: float = p.x
	var lt: float = p.y
	var hf: float = p.z
	var lf: float = p.w
	var pos_x: float = _positions_x[i]
	var pos_z: float = _positions_z[i]
	var t_tronc := Transform3D(
		Basis.IDENTITY.scaled(Vector3(lt, ht, lt)),
		Vector3(pos_x, Y_SOL + ht * 0.5, pos_z))
	_mm_tronc.set_instance_transform(i, t_tronc)
	var t_feuillage: Transform3D
	if hf <= 0.0 or lf <= 0.0:
		t_feuillage = Transform3D(
			Basis.IDENTITY.scaled(Vector3.ZERO),
			Vector3(pos_x, Y_SOL + ht, pos_z))
	else:
		t_feuillage = Transform3D(
			Basis.IDENTITY.scaled(Vector3(lf, hf, lf)),
			Vector3(pos_x, Y_SOL + ht + hf * 0.5, pos_z))
	_mm_feuillage.set_instance_transform(i, t_feuillage)

# Slot libre : les deux instances a echelle nulle (invisibles).
func _ecrire_slot_vide(i: int) -> void:
	var t := Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3(0.0, Y_SOL, 0.0))
	_mm_tronc.set_instance_transform(i, t)
	_mm_feuillage.set_instance_transform(i, t)

# CHAMP DE COUVERT -- depot/retrait strictement symetrique (signe -1 =
# retrait). `stade` = numero de stade (1..8, index+1) pour lire
# `_ombrage_par_stade[stade-1]`. La magnitude est le PIC CENTRAL ; a
# distance d de la case centrale (d = max(|dcx|, |dcz|), norme Chebyshev),
# l'apport est mag * (1 - d/rayon) -- decroissance lineaire, plein au
# centre, zero au bord (case skippee). Rayon 0 : seule la case centrale
# recoit mag. Le retrait rejoue exactement la meme formule (deterministe
# pour (pos, stade) fixes) : invariant strict, aucune derive du champ.
# Case dont le cumul retombe sous EPS_COUVERT est retiree du Dict.
func _deposer_ombrage(pos_x: float, pos_z: float, stade: int, signe: int) -> void:
	if stade < 1 or stade > 8:
		return
	if _ombrage_par_stade.size() < stade:
		return
	var conf: Dictionary = _ombrage_par_stade[stade - 1]
	var rayon: int = int(conf.get("rayon_cases", 0))
	var mag: float = float(conf.get("magnitude", 0.0)) * float(signe)
	if mag == 0.0:
		return
	var cx0: int = floori(pos_x / _taille_case)
	var cz0: int = floori(pos_z / _taille_case)
	var dcx: int = -rayon
	while dcx <= rayon:
		var dcz: int = -rayon
		while dcz <= rayon:
			var d: int = maxi(absi(dcx), absi(dcz))
			var poids: float = 1.0
			if rayon > 0:
				poids = 1.0 - float(d) / float(rayon)
			if poids <= 0.0:
				dcz += 1
				continue
			var apport: float = mag * poids
			var cle: Vector2i = Vector2i(cx0 + dcx, cz0 + dcz)
			var v: float = float(_couvert.get(cle, 0.0)) + apport
			if absf(v) < EPS_COUVERT:
				_couvert.erase(cle)
			else:
				_couvert[cle] = v
			dcz += 1
		dcx += 1

func _lire_couvert(pos_x: float, pos_z: float) -> float:
	var cle: Vector2i = Vector2i(floori(pos_x / _taille_case), floori(pos_z / _taille_case))
	return float(_couvert.get(cle, 0.0))

func _liberer_slot(i: int) -> void:
	# Retrait structurel du monde (consequence: sans lui, la mort resterait
	# un fantome compte a sa place dans toute requete de densite ; risque:
	# gates de densite futurs trop stricts ; plan B: aucun -- monde.gd:retirer
	# alarme sur id absent, defaut impossible ici).
	var chose = _choses_arbre[i]
	if chose != null:
		_monde.retirer(chose.id)
		_choses_arbre[i] = null
	var index: int = _slot_stade[i]
	if index >= 0:
		_deposer_ombrage(_positions_x[i], _positions_z[i], index + 1, -1)
	_slot_stade[i] = -1
	_libres[i] = 1
	_ages[i] = 0.0
	_ecrire_slot_vide(i)
	_slots_libres.append(i)
	_population -= 1

# Naissance : prend un slot libre en priorite ; agrandit la capacite s'il
# n'y en a plus. Fabrique un objet via Objet.fabriquer, extrait
# `stades_config` la premiere fois pour le cache partage. Le Dictionary
# de l'objet n'est PAS stocke -- seules les colonnes tiennent la population.
func _naitre(pos_x: float, pos_z: float) -> void:
	if _slots_libres.is_empty():
		_agrandir_capacite()
	var i: int = _slots_libres.pop_back()
	var position := Vector3(pos_x, Y_SOL, pos_z)
	var objet: Dictionary = Objet.fabriquer(
		"arbre_%d" % i, TYPE_ARBRE, position, _catalogue, {}, [], {}, [], true)
	if objet.is_empty():
		push_error("banc_peuplement_arbre : Objet.fabriquer a rendu {} pour slot %d" % i)
		_slots_libres.append(i)
		return
	if _stades_config_partagee.is_empty():
		_stades_config_partagee = objet.proprietes.get("stades_config", [])
	_libres[i] = 0
	_ages[i] = float(objet.proprietes.get("age", 0.0))
	_positions_x[i] = pos_x
	_positions_z[i] = pos_z
	# Index du stade initial (age 0 tombe sur le premier stade dont
	# age_seuil <= 0, en general "s1").
	_slot_stade[i] = _index_pour_age(_ages[i])
	if _slot_stade[i] >= 0:
		_deposer_ombrage(pos_x, pos_z, _slot_stade[i] + 1, 1)
	_facteur_croissance[i] = FacteurVariance.tirer_entre(_rng, _croissance_min, _croissance_max)
	_facteur_longevite[i] = FacteurVariance.tirer_entre(_rng, _longevite_min, _longevite_max)
	# Inscription dans monde (consequence: monde.gd:ajouter exige un
	# Dictionary avec `id` et `position` structurels ; plan B: aucun --
	# rollback = ne pas ajouter le champ, mais le retirer de _liberer_slot
	# echouerait alors sur push_error id absent).
	var chose := {"id": "arbre_%d" % i, "position": position}
	_choses_arbre[i] = chose
	_monde.ajouter(chose, "arbre", position)
	_ecrire_slot(i, _ages[i])
	_population += 1

# Index du stade dont age_seuil <= age est le plus grand. Meme geste que
# `stade.gd:avancer` en interne, mais rendu ici pour poser le stade INITIAL
# au moment de la naissance (avant tout appel a Stade.avancer).
func _index_pour_age(age: float) -> int:
	var trouve: int = -1
	for i in range(_stades_config_partagee.size()):
		var seuil: float = float(_stades_config_partagee[i].get("age_seuil", 0.0))
		if age >= seuil:
			trouve = i
	return trouve

func _semer_pres_de(parent_index: int) -> void:
	# Tirage UNIFORME dans le disque : angle uniforme + rayon = sqrt(u) * R.
	var angle: float = _rng.randf() * TAU
	var rayon: float = sqrt(_rng.randf()) * _rayon_graine
	var pos_x: float = _positions_x[parent_index] + cos(angle) * rayon
	var pos_z: float = _positions_z[parent_index] + sin(angle) * rayon
	_deposer_graine(pos_x, pos_z)

# UNIQUE definition du gate de trouee (patron vegetation.gd:trouee_suffisante).
# Appele par _deposer_graine ET _tick_banque -- si les deux chemins
# divergent, la banque contourne le gate et les salves synchronisees
# reviennent par la banque. Les rejets nes plus tot dans la meme frame ou
# la meme rafale de banque sont deja dans _monde (ajout live a chaque
# _naitre) et comptes ici -- meme effet que le dict `nouvelles` de
# vegetation.gd sans dict temporaire.
func _trouee_saturee(pos_x: float, pos_z: float) -> bool:
	var arrivee := Vector3(pos_x, Y_SOL, pos_z)
	return _monde.choses_dans_rayon(arrivee, _rayon_trouee).size() > _trouee_max_voisins

func _deposer_graine(pos_x: float, pos_z: float) -> void:
	# Graine hors carte : perdue. Ne germe pas, n'entre pas en banque.
	if absf(pos_x) > _demi_carte or absf(pos_z) > _demi_carte:
		return
	# Rejet trouee sur germination directe = graine perdue (pas de banque :
	# la banque attend que le COUVERT baisse, pas que la densite physique
	# se degage).
	if _trouee_saturee(pos_x, pos_z):
		return
	if _lire_couvert(pos_x, pos_z) < _seuil_couvert:
		_naitre(pos_x, pos_z)
		return
	# Phase de re-test tiree seedee dans [0, _intervalle_retest[ : chaque
	# graine a son propre reveil, la banque ne pulse plus au meme tic.
	var phase: float = _rng.randf() * _intervalle_retest
	_banque_graines.ajouter({
		"position": Vector3(pos_x, Y_SOL, pos_z),
		"prochaine_echeance": _temps_banque + phase,
	})

# Re-test DESYNCHRONISE : chaque graine a sa propre `prochaine_echeance`
# (temps monde cumule dans `_temps_banque`). Ce tick, on incremente
# `_temps_banque` puis on ne teste QUE les prospects dont l'echeance est
# atteinte. Les autres attendent leur tour -- fin des pulses.
#
# `attente_seuil.avancer` n'est plus appele : il compare une valeur lue a
# un seuil unique, il ne connait pas les cles libres du prospect
# (`prochaine_echeance`). On itere `prospects()` directement (documente
# comme lecture ; on ne mute pas la structure -- on mute seulement le
# champ `prochaine_echeance` de chaque entree, et on retire par id apres
# la boucle pour ne pas iterer un Dictionary en mutation).
#
# Gate applique aux levees comme pour _deposer_graine : trouee saturee
# -> re-echeance repoussee, graine reste en banque. Couvert encore
# ombrage -> meme geste. Le gate mord pendant la rafale grace a l'ajout
# live dans _monde a chaque _naitre.
func _tick_banque(pas: float) -> void:
	if _banque_graines == null or _banque_graines.nombre() == 0:
		return
	_temps_banque += pas
	var a_retirer: Array = []
	var prospects: Dictionary = _banque_graines.prospects()
	for id in prospects:
		var entree: Dictionary = prospects[id]
		if float(entree.get("prochaine_echeance", 0.0)) > _temps_banque:
			continue
		var pos: Vector3 = entree.position
		if _trouee_saturee(pos.x, pos.z) or _lire_couvert(pos.x, pos.z) >= _seuil_couvert:
			entree["prochaine_echeance"] = float(entree.prochaine_echeance) + _intervalle_retest
			continue
		a_retirer.append({"id": int(id), "pos": pos})
	for r in a_retirer:
		_banque_graines.retirer(int(r.id))
		_naitre(r.pos.x, r.pos.z)

# Double la capacite des deux MultiMesh et des colonnes. Reallouer
# `instance_count` REINITIALISE le tampon GPU des deux MultiMesh : toute
# transform ecrite avant est perdue. Il faut donc reecrire, dans le meme
# appel, TOUS les slots (vivants avec leur vraie transform, libres a
# echelle nulle) avant qu'une frame ne passe -- sinon les arbres
# existants clignotent par vagues au doublement (8, 16, 32...).
# Cout amorti O(1) par naissance grace au doublement.
func _agrandir_capacite() -> void:
	var ancienne: int = _capacite
	var nouvelle: int = ancienne * 2
	if nouvelle < ancienne + 1:
		nouvelle = ancienne + 1
	_ages.resize(nouvelle)
	_libres.resize(nouvelle)
	_positions_x.resize(nouvelle)
	_positions_z.resize(nouvelle)
	_slot_stade.resize(nouvelle)
	_facteur_croissance.resize(nouvelle)
	_facteur_longevite.resize(nouvelle)
	_choses_arbre.resize(nouvelle)
	_mm_tronc.instance_count = nouvelle
	_mm_feuillage.instance_count = nouvelle
	_capacite = nouvelle
	var i: int = nouvelle - 1
	while i >= ancienne:
		_libres[i] = 1
		_ages[i] = 0.0
		_positions_x[i] = 0.0
		_positions_z[i] = 0.0
		_slot_stade[i] = -1
		_facteur_croissance[i] = 1.0
		_facteur_longevite[i] = 1.0
		_choses_arbre[i] = null
		_slots_libres.append(i)
		_ecrire_slot_vide(i)
		i -= 1
	# Reecriture des slots preexistants dont le buffer GPU vient d'etre
	# reinitialise par le changement d'instance_count ci-dessus.
	var j: int = 0
	while j < ancienne:
		if _libres[j] == 1:
			_ecrire_slot_vide(j)
		else:
			_ecrire_slot(j, _ages[j])
		j += 1

# Passe rare d'auto-eclaircie. Ne tourne QU'a la cadence lente
# `_cadence_competition` (pas dans la boucle 60 fps). Seuls les arbres
# vulnerables (stade + 1 <= _stade_competition_max) sont testes -- les
# adultes dominent et survivent. Collecte les morts a retirer APRES
# l'iteration : _liberer_slot mute _libres et pourrait perturber le
# balayage en cours. Chaque mort passe par _liberer_slot (retrait de
# monde, retrait ombrage, slot recycle) -- meme geste que la mort de
# vieillesse.
func _passe_competition() -> void:
	var cap: int = _capacite
	var a_liberer: Array = []
	var i: int = 0
	while i < cap:
		if _libres[i] == 1:
			i += 1
			continue
		var index: int = _slot_stade[i]
		if index < 0 or index + 1 > _stade_competition_max:
			i += 1
			continue
		var pos := Vector3(_positions_x[i], Y_SOL, _positions_z[i])
		var voisins: int = _monde.choses_dans_rayon(pos, _rayon_competition).size()
		if voisins > _competition_max_voisins:
			var exces: int = voisins - _competition_max_voisins
			var proba: float = clampf(
				float(exces) / float(maxi(1, _competition_max_voisins)), 0.0, 1.0)
			if _rng.randf() < proba:
				a_liberer.append(i)
		i += 1
	for slot in a_liberer:
		_liberer_slot(int(slot))
