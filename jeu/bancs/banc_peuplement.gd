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
const Depense = preload("res://scripts/depense.gd")
const SeuilEtat = preload("res://scripts/seuil_etat.gd")

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
# REGIME MASSE (chantier "regime de masse en colonnes", 2026-09-08). true :
# `_fabriquer_lot` appelle Peuplement.spawn_masse (colonnes seules, aucun Dict
# `individu` fabrique). Les paquets par defaut (reserves 5 canaux,
# deformation_etat, etats...) ne sont MEME PLUS FABRIQUES pour les unites
# dormantes -- ils naitront a l'activation via `Peuplement.activer(pool, ..., index)`
# quand un mecanisme reveillera une unite (aller simple pour ce chantier).
# Le hot path continue de lire les colonnes uniquement -- rien ne bouge a l'ecran.
# EXIGE deplacer_cpp=true : la passe deplacer GDScript oracle (`_monde.deplacer_simple(individu)`)
# lit `individus[j]` qui reste vide sous masse ; le C++ (`deplacer_lot(cols.position)`)
# est la seule voie viable. false : comportement du chantier COW precedent
# (spawn regulier, un Dict individu par unite, paquets_partages=true partage
# les sous-Dict).
@export var regime_masse: bool = false
# ---- DEMO FATIGUE (chantier "fatigue en cadence lente sur charge/seuil", 2026-09-08).
# Une passe cadencee decremente le canal `sommeil` (herite de `dynamique`), pose un
# miroir plat `manque_sommeil = capacite - reserve`, et delegue a scripts/seuil_etat.gd
# qui compare a l'entree "epuisement" de data/seuils_etat.json (seuil=70, etat='epuise').
# Au FRANCHISSEMENT (pas par frame), le banc ajuste cols.vitesse -- entre deux bascules,
# rien n'est recalcule (contrat evenementiel).
# `nombre_actives` : combien d'unites reoivent leur paquet dynamique via Peuplement.activer.
# Les autres restent en regime masse (colonnes seules, aucune fatigue materialisee).
@export var nombre_actives: int = 100
# Cadence UNIFORME de la passe fatigue, en frames. 30 a 60 fps = 0.5 s -- un mecanisme
# lent, jamais chaque frame. Reglable, jamais fonction de la distance au joueur (LOD
# par distance INTERDIT par le prompt : temps du monde uniforme).
@export var cadence_fatigue_frames: int = 30
# DEMO : cout_base pose sur le canal sommeil des unites activees, plus grand que le
# defaut de `dynamique` (0.3/s), pour que le franchissement du seuil "epuise" soit
# visible sur une echelle de secondes en jeu. Reste un cablage de banc, jamais une
# valeur en dur dans le moteur.
@export var cout_base_sommeil_demo: float = 20.0
# DEMO : facteur multiplicatif applique a cols.vitesse quand une unite bascule sur
# 'epuise'. 0.4 = ralentit a 40% de sa vitesse nominale, visible a l'oeil. Retour a
# 1.0 quand 'epuise' est retire (franchissement descendant).
@export var vitesse_epuise_facteur: float = 0.4
# ---- VUE (cone_oriente) + OCCLUSION en C++ (chantier "vue avec occlusion en
# C++", 2026-09-08). vue_lot(positions, orientations, opacites, rayon,
# cos_moitie_angle, largeur, seuil) fait TOUT en un seul parcours du voisinage
# planaire : (1) voisins dans le rayon, (2) filtres par le cone d'angle
# autour de l'orientation de chaque unite (patron perception.gd::_percevoir_cone_oriente),
# (3) test d'occlusion contre les autres corps du meme voisinage 3x3 (jamais
# une requete spatiale par paire, contrat prompt), (4) accumulation de la
# separation dans le MEME parcours -- les voisins vus sont deja la. Sortie :
# direction unitaire horizontale (Y=0) par unite. Un seul poste de chrono,
# une seule frontiere.
# La geometrie d'occlusion (t dans ]0,1[, distance laterale <= largeur, cumul
# multiplicatif) est portee mot pour mot depuis scripts/occlusion.gd::facteur.
# largeur_occlusion : DERIVEE de la taille du corps (chantier "occlusion a
# hauteur de la taille reelle", 2026-09-08). Un corps de rayon r occulte au
# maximum a distance laterale r+r = taille horizontale du corps (peuplement
# homogene : occulteur et cible font la meme taille). Calculee au _monter_pool
# depuis data/mesh.json[mesh_ref].taille -- aucun nombre en dur, aucun
# @export. Un premier jet avait pose 0.5 pour un corps de 0.8 : le couloir
# etait plus etroit que les corps, un occulteur latteralement decale de 0.6
# n'etait pas compte alors que geometriquement il bouche encore la ligne de
# vue -> ~64 cibles/unite au releve BORNE au lieu de la poignee attendue.
var _largeur_occlusion: float = 0.0
# Seuil du facteur d'occlusion sous lequel un voisin est retire du percu.
# Convention historique du depot (test_banc_p1 : 0.001) : un facteur nul serait
# trivialement rejete, 0.001 laisse passer un obstacle transparent tout en
# refusant un obstacle opaque (facteur == 0.0).
@export var seuil_facteur_occlusion: float = 0.001
# Opacite uniforme des unites du peuplement : chaque unite est ce
# corps-obstacle pour les autres. 1.0 = totalement opaque (blocage total).
# Cablage local du banc, jamais un nom en dur en C++ (le C++ recoit un
# PackedFloat32Array indexe par id, aveugle au nom de propriete).
@export var opacite_unite: float = 1.0
# Angle TOTAL du cone de vue en degres (patron scripts/perception.gd:
# _percevoir_cone_oriente qui prend l'angle total puis divise par deux pour
# comparer au cosinus de la moitie). 120.0 par defaut = un cone de vision
# large. >= 360.0 degenere en sphere pure -- l'angle ne peut plus exclure
# aucun voisin, comportement identique a un canal sans reglage d'angle. Le
# C++ recoit le COSINUS de la moitie (calcule une fois cote banc), aucun acos
# en boucle sur la masse.
@export var angle_vue_deg: float = 120.0

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
# Exposant du niveau PLANAIRE ouvert par _monter_pool sous separation_active
# (arete = 2^exposant, choisi pour couvrir rayon_separation sur chaque axe).
# -1 = aucun niveau planaire ouvert (separation_active=false ou brancher_monde=false).
# Lu par la passe candidats pour choisir le niveau a interroger.
var _exposant_planaire: int = -1

# CHRONO -- lus par _imprimer_releve_si_seconde_ecoulee. UN SEUL POSTE : vue
# (le seul qui pese en foule dense a N=100 000, ~600 000 us contre <10 000 us
# pour tous les autres postes cumules). Les autres postes historiques
# (errance/phys+buffer/deplacer/fatigue/mm_set) ont ete retires du releve
# comme inutilises pour l'optimisation en cours (chantier "concentre le
# releve sur la vue", 2026-09-08). Chronos internes de leurs branches
# supprimes aussi -- ils ne sont plus calcules.
var _us_vue: int = 0
# Catalogue seuils_etat.json charge une fois au _ready. Passe la sur SeuilEtat.avancer.
var _catalogue_seuils: Dictionary = {}
# CAPACITE du canal `sommeil` sur mobile_test : lue une fois au _fabriquer_lot depuis
# le paquet dynamique deja fabrique (paquet.reserves.sommeil.reserve initial). Sert
# a poser le miroir plat `manque_sommeil = capacite - reserve.sommeil.reserve`. Pas
# une constante en dur -- si dynamique.reserves.sommeil.reserve change dans
# data/types.json, la capacite suit.
var _capacite_sommeil: float = 100.0
# Compteur de frames depuis la derniere passe fatigue. La passe se declenche quand
# ce compteur atteint `cadence_fatigue_frames`, puis se remet a zero.
var _frames_depuis_fatigue: int = 0
var _frames_accumulees: int = 0
var _temps_prochain_ms: int = 0

func _ready() -> void:
	_charger_reglages_locaux()
	_rng.seed = graine_rng
	_monter_scene()
	_monter_pool()
	_catalogue_seuils = _charger_seuils_etat()
	_fabriquer_lot()
	_activer_lot()

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
	if donnees.has("regime_masse"):
		regime_masse = bool(donnees.regime_masse)
	if donnees.has("nombre_actives"):
		nombre_actives = int(donnees.nombre_actives)
	if donnees.has("cadence_fatigue_frames"):
		cadence_fatigue_frames = int(donnees.cadence_fatigue_frames)
	if donnees.has("cout_base_sommeil_demo"):
		cout_base_sommeil_demo = float(donnees.cout_base_sommeil_demo)
	if donnees.has("vitesse_epuise_facteur"):
		vitesse_epuise_facteur = float(donnees.vitesse_epuise_facteur)
	if donnees.has("seuil_facteur_occlusion"):
		seuil_facteur_occlusion = float(donnees.seuil_facteur_occlusion)
	if donnees.has("opacite_unite"):
		opacite_unite = float(donnees.opacite_unite)
	if donnees.has("angle_vue_deg"):
		angle_vue_deg = float(donnees.angle_vue_deg)

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
	# GARDE : regime_masse EXIGE deplacer_cpp=true. La passe deplacer GDScript
	# oracle (`_monde.deplacer_simple(individu)`) lit `individus[j].position` --
	# `individus` est vide sous masse, la passe deplacer historique ne verrait
	# aucune unite. L'index C++ (`deplacer_lot(cols.position)`) est la seule voie
	# qui lit uniquement les colonnes. Push_error + repli sur regime_masse=false
	# pour ne pas casser la simulation silencieusement.
	if regime_masse and not deplacer_cpp:
		push_error("banc_peuplement : regime_masse=true exige deplacer_cpp=true -- repli sur regime_masse=false.")
		regime_masse = false
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
				# PLANAIRE (chantier "degraissage separation_lot", 2026-09-08) :
				# separation_lot lit ce niveau sans jamais balayer l'axe Y.
				# deplacer_lot y insere avec y=0 dans la clef -- toutes les unites
				# d'une meme colonne (fx, fz) dans la meme entree unordered_map,
				# quelle que soit leur altitude. Le niveau du deplacer (arete 16)
				# reste 3D. Voir extension_terrain/src/index_spatial.h §
				# Niveau::planaire et separation_lot.
				_index_cpp.ouvrir_niveau_planaire(exposant_sep)
				_exposant_planaire = exposant_sep
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
	# LARGEUR D'OCCLUSION DERIVEE DE LA TAILLE DU CORPS (chantier "occlusion a
	# hauteur de la taille reelle"). En peuplement homogene (occulteur et cible
	# de meme taille), la distance laterale maximale d'un occulteur pour boucher
	# entierement le corps derriere = r_occulteur + r_cible = 2 * (taille/2) =
	# taille. La geometrie horizontale se lit sur max(taille.x, taille.z). Aucun
	# nombre en dur : la valeur vient de data/mesh.json[mesh_ref].taille.
	var fiche_mesh: Dictionary = catalogue_mesh[mesh_ref]
	var t_mesh: Dictionary = fiche_mesh.get("taille", {})
	_largeur_occlusion = maxf(float(t_mesh.get("x", 0.0)), float(t_mesh.get("z", 0.0)))
	if _largeur_occlusion <= 0.0:
		push_error("banc_peuplement : taille horizontale du mesh '%s' introuvable ou nulle (%s) -- occlusion inerte" % [mesh_ref, str(t_mesh)])
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
		# Opacite de chaque unite pour le test d'occlusion de perception_lot.
		# Uniforme sur ce peuplement (opacite_unite comme defaut) -- l'appelant
		# du C++ (perception_lot) lit cette colonne indexee par id, aveugle au
		# nom de propriete. Le nom "opacite" est un choix local du banc (patron
		# CLAUDE.md § ADN : un banc peut nommer une categorie).
		"opacite": opacite_unite,
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
	# La vitesse du type (types.json:mobile_test.vitesse) est lue UNE fois : sous
	# regime masse, aucun Dict individu ne porte cette valeur (colonne vitesse
	# alimentee directement au spawn_masse) ; sous regime normal, l'ancien chemin
	# la posait dans proprietes puis _remplir_colonnes_depuis_individus la lisait.
	# UN seul emplacement source dans les deux regimes -- le catalogue.
	var proprietes_type: Dictionary = _catalogue.get(type_id, {})
	var vitesse_type: float = float(proprietes_type.get("vitesse", 1.0))
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
		# ORDRE DE TIRAGE RNG identique dans les deux regimes (direction puis
		# horloge) -- le determinisme de la graine est preserve tel qu'avant le
		# chantier "regime de masse".
		var direction_init: Vector3 = _nouvelle_direction()
		var cap_horloge_init: float = _rng.randf_range(3.0, 8.0)
		if regime_masse:
			# Colonnes seules -- aucun Dict individu ne naitra tant qu'un mecanisme
			# n'active pas cette unite (Peuplement.activer(pool, ..., index)).
			# spawn_masse ecrit les 8 colonnes du peuplement en un push_back par
			# colonne, sans allocation Dict individu ni fabrication Objet.
			var slot: int = Peuplement.spawn_masse(_pool, position, vitesse_type, direction_init, cap_horloge_init)
			if slot < 0:
				push_error("banc_peuplement : Peuplement.spawn_masse a echoue a la tentative %d" % tentatives)
				return
		else:
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
			p["errance_direction"] = direction_init
			p["errance_cap_horloge"] = cap_horloge_init
		poses += 1
	if poses < nombre_individus:
		push_error("banc_peuplement : seulement %d/%d individus poses (%d tentatives)" % [poses, nombre_individus, tentatives])
	if not regime_masse:
		# Remplir les colonnes du pool en batch (peuplement les a appendees vides
		# a chaque spawn ; le banc y ecrit les vraies valeurs). Depack / mute /
		# repack par colonne (CoW). Ordre = ordre de _pool.individus.
		# Sous regime_masse : deja rempli directement au spawn_masse, cette passe
		# est integralement sautee.
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
	# count = nombre d'unites VIVANTES dans les colonnes, valable dans les deux
	# regimes. Sous regime normal, individus.size() == cols.position.size() (les
	# colonnes sont maintenues alignees avec individus par le swap-remove). Sous
	# regime masse, individus reste vide et cols.position porte toute la
	# population -- lire cols.position.size() traite les deux uniformement.
	var cols_positions_ref: PackedVector3Array = _pool.colonnes.position
	var count: int = cols_positions_ref.size()
	if count == 0:
		return
	# CHRONOS -- trois postes du hot path, en microsecondes. Sous actif_releve
	# false, les trois `Time.get_ticks_usec()` sont EVITES au maximum (une
	# branche par poste plutot que trois inconditionnels) : instrumenter n'est
	# pas biaiser la mesure.
	var chrono_intention_debut: int = Time.get_ticks_usec() if actif_releve else 0
	# INTENTION. Deux chemins :
	#   separation_active=true : UN SEUL APPEL C++ -- vue_lot(positions,
	#     orientations, opacites, rayon, cos_moitie_angle, largeur, seuil).
	#     UN SEUL PARCOURS DU VOISINAGE PAR FRAME. Pour chaque unite : voisins
	#     dans le rayon ET dans le cone d'angle autour de son orientation, PUIS
	#     filtrage occlusion (obstacles = les autres corps du meme voisinage
	#     3x3 planaire, jamais une requete spatiale par paire), PUIS accumulation
	#     de la separation dans le MEME parcours (les voisins vus sont deja la).
	#     Sortie : direction unitaire horizontale (Y=0) de repulsion par unite.
	#     Un seul poste `vue`, une seule frontiere.
	#   separation_active=false : errance historique. desiree[i] n'est reecrit
	#     QUE quand l'horloge expire.
	var cols: Dictionary = _pool.colonnes
	var vitesses: PackedFloat32Array = cols.vitesse
	var desirees: PackedVector3Array = cols.desiree
	var chrono_intention_fin: int = 0
	if separation_active and _index_cpp != null:
		# Cos de la moitie de l'angle total, calcule UNE fois. Cone_oriente
		# (perception.gd) compare orientation.dot(direction_vers_voisin) a ce
		# cos ; angle >= 360 -> cos_moitie = -1.0 (sphere pure, accepte tout).
		var demi_angle_rad: float = deg_to_rad(angle_vue_deg * 0.5)
		var cos_moitie_angle: float = -1.0 if angle_vue_deg >= 360.0 else cos(demi_angle_rad)
		var directions_sep: PackedVector3Array = _index_cpp.vue_lot(
			cols.position,
			cols.direction,
			cols.opacite,
			rayon_separation,
			cos_moitie_angle,
			_largeur_occlusion,
			seuil_facteur_occlusion)
		var k: int = 0
		while k < count:
			desirees[k] = directions_sep[k] * vitesses[k]
			k += 1
		cols.desiree = desirees
		if actif_releve:
			chrono_intention_fin = Time.get_ticks_usec()
			_us_vue += chrono_intention_fin - chrono_intention_debut
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
	# PASSE FATIGUE, cadence lente : n'agit QUE toutes les cadence_fatigue_frames
	# images. Uniforme pour toutes les unites, jamais fonction de la distance au
	# joueur (LOD par distance INTERDIT dans ce depot). Delta effectif = cadence *
	# delta_frame (la duree du monde reellement ecoulee depuis la derniere passe).
	_frames_depuis_fatigue += 1
	if _frames_depuis_fatigue >= cadence_fatigue_frames:
		var delta_cadence: float = float(cadence_fatigue_frames) * delta
		var vitesse_type: float = float((_catalogue.get(type_id, {}) as Dictionary).get("vitesse", 1.0))
		_passe_fatigue(delta_cadence, vitesse_type)
		_frames_depuis_fatigue = 0
	RenderingServer.multimesh_set_buffer((_pool.mm as MultiMesh).get_rid(), buffer)
	_pool["buffer"] = buffer
	if actif_releve:
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
	print("[peuplement] N=%d fps=%d vue=%dus" % [
		count,
		int(Engine.get_frames_per_second()),
		int(float(_us_vue) * inv_frames),
	])
	_us_vue = 0
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

func _charger_seuils_etat() -> Dictionary:
	if not FileAccess.file_exists("res://data/seuils_etat.json"):
		push_error("banc_peuplement : data/seuils_etat.json introuvable -- passe fatigue inerte")
		return {}
	var texte := FileAccess.get_file_as_string("res://data/seuils_etat.json")
	var donnees = JSON.parse_string(texte)
	if not (donnees is Dictionary):
		push_error("banc_peuplement : data/seuils_etat.json invalide")
		return {}
	return donnees

# ACTIVATION DU LOT DE DEMO. Active `nombre_actives` unites via Peuplement.activer :
# chacune recoit son paquet dynamique complet (reserves 5 canaux, deformation_etat,
# etats, canaux_config si le type compose percevant, etc.). Les autres unites du
# pool restent en regime masse -- colonnes seules, aucune materialisation, aucune
# fatigue -- coherent avec la doctrine "presence complete / activation variable"
# appliquee a la memoire (chantier 2026-09-08 precedent). Puis surcharge le cout_base
# du canal sommeil (`cout_base_sommeil_demo`) pour que le franchissement du seuil
# "epuise" (seuil=70 sur manque_sommeil, entree "epuisement" de data/seuils_etat.json)
# se produise sur une echelle de secondes VISIBLE en jeu.
func _activer_lot() -> void:
	if _pool.is_empty():
		return
	if not regime_masse:
		# En regime normal, toutes les unites ont deja un Dictionary individu depuis
		# _fabriquer_lot ; l'activation supplementaire ne sert a rien, la passe
		# fatigue tournera sur pool.individus telles quelles.
		# On ecrit quand meme cout_base_sommeil_demo pour que la demo soit visible.
		var individus_normaux: Array = _pool.individus
		for individu in individus_normaux:
			_appliquer_cout_base_sommeil_demo(individu)
		return
	var nb_a_activer: int = mini(nombre_actives, (_pool.colonnes.position as PackedVector3Array).size())
	var i: int = 0
	while i < nb_a_activer:
		var id: String = Peuplement.activer(_pool, _catalogue, type_id, i, _monde)
		if id.is_empty():
			push_error("banc_peuplement : Peuplement.activer a echoue a l'index %d" % i)
			return
		var individu: Dictionary = (_pool.individus as Array)[(_pool.id_to_index as Dictionary)[id]]
		_appliquer_cout_base_sommeil_demo(individu)
		i += 1
	# Lire la capacite du canal sommeil sur la premiere unite activee : c'est la
	# valeur qui servira de reference au miroir plat `manque_sommeil = capacite -
	# reserve` (voir _passe_fatigue). Toutes les unites activees partagent la MEME
	# capacite (le cache canonique de `dynamique` avant detache).
	if (_pool.individus as Array).size() > 0:
		var premier: Dictionary = (_pool.individus as Array)[0]
		var p: Dictionary = premier.proprietes
		if p.has("reserves") and p.reserves.has("sommeil"):
			_capacite_sommeil = float(p.reserves.sommeil.reserve)

# Le canal `reserves` a ete detache par Peuplement.activer -- muter sommeil.cout_base
# est isole a cette instance. Sur regime normal (spawn), le canal etait deja unique
# a l'instance (paquets_partages=true fait le detacher a la fabrication -- non, il
# ne le fait PAS : c'est le partage COW qui laisse reserves partage. Ici on force
# le detacher au cas ou l'unite provient du chemin regime normal ou l'activation
# n'a pas eu lieu et le paquet peut etre partage.
func _appliquer_cout_base_sommeil_demo(individu: Dictionary) -> void:
	var Objet = load("res://scripts/objet.gd")
	Objet.detacher(individu.proprietes, "reserves")
	individu.proprietes.reserves.sommeil.cout_base = cout_base_sommeil_demo

# PASSE FATIGUE, cadence lente uniforme (voir @export cadence_fatigue_frames en tete
# de fichier). Ne s'execute PAS a chaque frame : compte les frames et ne declenche
# qu'a l'expiration de la cadence. Delta effectif = cadence * delta_frame (la vraie
# duree du monde ecoulee depuis la derniere passe). Trois etapes strictement
# lineaires :
#   1. Depense.avancer(individus, delta_cadence, {}) : decrement du canal sommeil
#      (cout_base ecrit par _appliquer_cout_base_sommeil_demo). Chaque unite a son
#      propre reserves (detache par Peuplement.activer), aucune contamination.
#   2. Miroir plat : proprietes.manque_sommeil = capacite - reserves.sommeil.reserve.
#      Necessaire car seuil_etat.gd ne lit que des cles PLATES (contrainte structurelle
#      documentee dans son en-tete).
#   3. SeuilEtat.avancer(individus, catalogue_seuils) : compare `manque_sommeil > 70`
#      et pose/retire l'etat 'epuise' au franchissement (memoire par entree, jamais
#      un recalcul). Rend les ids qui ont bascule.
#   4. Comportement DEMO : pour chaque id bascule, lire etats_actifs.has('epuise') UNE
#      fois et ecrire cols.vitesse a `vitesse_nominale * facteur` ou `vitesse_nominale`.
#      La colonne vitesse alimente desiree = direction * vitesse dans la passe errance,
#      et separation_lot la lit aussi. La vitesse s'applique au tick suivant sans jamais
#      re-tester la jauge.
func _passe_fatigue(delta_cadence: float, vitesse_type: float) -> void:
	var individus: Array = _pool.individus
	if individus.is_empty() or _catalogue_seuils.is_empty():
		return
	Depense.avancer(individus, delta_cadence, {})
	# Miroir plat sur chaque unite : c'est ce miroir qui permet a seuil_etat.gd
	# (aveugle aux sous-Dict) de lire la reserve.
	for individu in individus:
		var p: Dictionary = individu.proprietes
		var reserve_sommeil: float = float(p.reserves.sommeil.reserve)
		p["manque_sommeil"] = _capacite_sommeil - reserve_sommeil
	var bascules: Array = SeuilEtat.avancer(individus, _catalogue_seuils)
	if bascules.is_empty():
		return
	# COMPORTEMENT DEMO A LA BASCULE. Pour chaque id bascule, ajuster cols.vitesse.
	# Lire etats_actifs UNE fois pour savoir dans quel sens on va -- la memoire par
	# entree de seuil_etat.gd garantit que ce fut un VRAI franchissement.
	var cols: Dictionary = _pool.colonnes
	var vitesses: PackedFloat32Array = cols.vitesse
	var id_to_index: Dictionary = _pool.id_to_index
	for id in bascules:
		if not id_to_index.has(id):
			continue
		var individu: Dictionary = individus[int(id_to_index[id])]
		var slot: int = int(individu.proprietes.get("_slot", -1))
		if slot < 0 or slot >= vitesses.size():
			continue
		var etats: Array = individu.proprietes.get("etats_actifs", [])
		if etats.has("epuise"):
			vitesses[slot] = vitesse_type * vitesse_epuise_facteur
		else:
			vitesses[slot] = vitesse_type
	cols.vitesse = vitesses

func _exit_tree() -> void:
	Peuplement.detruire_pool(_pool)
