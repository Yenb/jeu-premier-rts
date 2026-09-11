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
# `scripts/attente_seuil.gd` (ajouter/retirer/prospects). RE-TEST SUR
# EVENEMENT, jamais a cadence fixe (patron `jeu/plantes/vegetation.gd`
# « L'OMBRE EST UN SIGNAL, PAS UNE QUESTION »). Une graine dormante
# reste dormante jusqu'a ce qu'un evenement dans son voisinage
# (mort d'arbre ou changement de stade d'un voisin) puisse rouvrir
# son gate. Entre deux tels evenements, ses conditions (trouee,
# couvert) sont rigoureusement identiques -- re-tester serait
# retrouver le meme resultat. Cle libre `reveille=false` posee a
# l'entree en banque ; `_reveiller_dormantes_autour` la passe a true
# pour les prospects dans le rayon d'un evenement ; `_tick_banque`
# ne teste que celles dont `reveille=true` et les remet a false
# apres un rejet. Une naissance N'EST PAS un evenement de reveil :
# elle AJOUTE de la densite et de l'ombrage, elle ne peut que fermer
# davantage un gate, jamais l'ouvrir. Le declencheur ecarte
# (cadence fixe) : voir en-tete de `_tick_banque`.
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
# Rayon (unites monde) autour d'un evenement (mort ou changement de
# stade) dans lequel les graines dormantes sont reveillees pour
# re-tester leurs gates. Calcule apres chargement JSON dans
# _calculer_rayon_reveil : max du rayon trouee elargi (voisin adulte
# a `_rayon_trouee * _facteur_trouee_gros`) et de la portee maximale
# d'ombrage (max_rayon_cases * _taille_case, distance Chebyshev entre
# cases converti en unites monde). Sur-estimation OK : le reveil est
# une invitation a re-tester, pas une decision -- le gate lu par
# `_tick_banque` reste la seule autorite.
var _rayon_reveil: float = 0.0
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
# Curseur d'anneau : chaque passe de sim avance de N slots (formule
# temps : n_slots = ceil(capacite * pas / _cadence_competition)) de
# sorte que chaque slot soit visite exactement une fois par periode
# `_cadence_competition` en moyenne. Cout reparti, plus de pic
# concentre sur une frame.
var _curseur_competition: int = 0

# CADENCE DE SIMULATION DECOUPLEE DU FRAMERATE. La sim des arbres (age,
# stade, reproduction, competition, ecriture MultiMesh) tourne a
# `_cadence_simulation_hz` fois par seconde, jamais a 60 fps. Le
# joueur (physics_process) garde son framerate plein -- cette cadence
# ne s'applique qu'a la boucle du banc. Le delta accumule (`_temps_depuis_maj`)
# est passe en `pas` a la passe de sim : proba stochastique / cadence
# banque / cadence competition dependent de `pas`, donc leur cadence
# moyenne reste identique quel que soit ce reglage.
var _cadence_simulation_hz: float = 4.0
var _temps_depuis_maj: float = 0.0

# EPSILON pour skipper l'ecriture MultiMesh quand les 4 params
# interpoles n'ont pas bouge (arbre au stade 8 fige, croissance lente
# entre deux passes). Comparaison composante par composante. En unites
# monde -- 0.001 m = 1 mm, invisible a l'oeil, sur.
const EPS_TAILLE := 0.001

# Cache des derniers params ecrits par slot (Vector4). Sentinel
# Vector4(INF,...) = "jamais ecrit" -> premier ecrit force. _ecrire_slot
# compare et skippe les deux set_instance_transform si delta < EPS.
var _derniere_params: Array = []

# GATE DE TROUEE ELARGI AUTOUR DES GROS. Un voisin adulte (stade dans
# [_stade_gros_min, _stade_gros_max]) "occupe" un rayon egal a
# `_rayon_trouee * _facteur_trouee_gros` -- une graine tombee a cette
# distance d'un adulte est rejetee, meme si le compte normal n'est pas
# depasse. Les jeunes gardent le rayon normal `_rayon_trouee`. Effet :
# rien ne pousse tres pres d'un dominant.
var _stade_gros_min: int = 5
var _stade_gros_max: int = 7
var _facteur_trouee_gros: float = 2.0
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

# CHRONOS TEMPORAIRES DE _tick_banque (a retirer une fois le poste
# dominant identifie -- meme discipline que les chronos de
# collision_lot.h). Quatre postes disjoints qui couvrent le corps de
# _tick_banque : SETUP (parcours + acces prospect), QUERY
# (choses_dans_rayon seul), GATE (boucle voisins + couvert), NAISSANCE
# (retirer + naitre). Cumul en microsecondes et compte de passages,
# imprimes sous le meme gate que le releve population.
var _chrono_us_setup: int = 0
var _chrono_us_query: int = 0
var _chrono_us_gate: int = 0
var _chrono_us_naissance: int = 0
var _chrono_us_total: int = 0
var _chrono_n_setup: int = 0
var _chrono_n_query: int = 0
var _chrono_n_gate: int = 0
var _chrono_n_naissance: int = 0
var _chrono_n_ticks: int = 0

# Champ scalaire d'ombrage par case (Vector2i -> float). Une entree est
# supprimee quand son cumul retombe sous EPS_COUVERT.
var _couvert: Dictionary = {}

# Banque de graines dormantes deleguee au mecanisme framework
# scripts/attente_seuil.gd : le banc enregistre chaque graine comme
# prospect avec `position` seule. Aucune horloge par graine : le
# re-test se declenche sur EVENEMENT de voisinage (mort d'arbre,
# changement de stade), jamais a cadence fixe. `attente_seuil.gd`
# accepte les cles libres par entree -- il ne les lit jamais.
var _banque_graines: RefCounted = null

# ENSEMBLE DES PROSPECTS REVEILLES a tester au prochain `_tick_banque`.
# Cle = id du prospect (int, rendu par `AttenteSeuil.ajouter`).
# Valeur = true (Dictionary utilise comme SET, dedoublonnage naturel :
# deux evenements successifs qui reveillent le meme prospect ne le
# testent qu'une fois). Rempli par `_reveiller_dormantes_autour`
# (appelee sur mort et changement de stade), vide par `_tick_banque`
# qui teste chaque id present. Une graine qui rate son gate au reveil
# retombe dormante -- son id est retire du set, elle attend un
# nouveau signal de son voisinage pour re-tester. Une graine qui
# leve est retiree du registre `AttenteSeuil`.
var _reveils: Dictionary = {}

# GRILLE SPATIALE PROPRE A LA BANQUE (patron LOCALITE SPATIALE du
# CLAUDE.md, variante monde-indexe adaptee aux ids stables). Cle =
# Vector2i (case du plan XZ, cote `_taille_case_dormantes`), valeur =
# Array<int> des ids de prospects dormants dans cette case. Insertion a
# `_deposer_graine`, retrait quand une graine leve (`_tick_banque`).
# `_reveiller_dormantes_autour` ne lit QUE les cases dans le rectangle
# `[pos - _rayon_reveil, pos + _rayon_reveil]` -- plus de balayage
# global de toute la banque a chaque evenement. Cout d'un reveil =
# O(graines reellement proches), plus lie a la population totale
# dormante. `_case_de_dormante` (id -> Vector2i) est l'index inverse
# qui rend le retrait O(1) : pas besoin de rechercher la case en
# balayant les listes.
var _dormantes_par_case: Dictionary = {}
var _case_de_dormante: Dictionary = {}
# Cote (unites monde) des cases de `_dormantes_par_case`. Fixe a
# `_rayon_reveil` dans `_calculer_rayon_reveil` : le rectangle d'un
# reveil couvre alors 2 ou 3 cases par axe (borne stricte), aucun scan
# 3x3 forfaitaire, aucun overshoot en cases > rayon.
var _taille_case_dormantes: float = 0.0

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
	_calculer_rayon_reveil()
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
	if donnees.has("stade_gros_min"):
		_stade_gros_min = int(donnees.stade_gros_min)
	if donnees.has("stade_gros_max"):
		_stade_gros_max = int(donnees.stade_gros_max)
	if donnees.has("facteur_trouee_gros"):
		_facteur_trouee_gros = float(donnees.facteur_trouee_gros)
	if donnees.has("cadence_simulation_hz"):
		_cadence_simulation_hz = float(donnees.cadence_simulation_hz)
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
	_derniere_params.resize(_capacite)
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
		_derniere_params[i] = Vector4(INF, INF, INF, INF)
		_slots_libres.append(i)
		_ecrire_slot_vide(i)
		i -= 1

func _process(delta: float) -> void:
	if _stades.size() != 8 or _durees.size() != 7 or _stades_config_partagee.is_empty():
		return
	# CADENCE DE SIMULATION DECOUPLEE DU FRAMERATE : la sim ne tourne
	# pas 60 fois par seconde. Le delta accumule est passe en `pas` a
	# la passe -- proba stochastique / cadence banque / competition
	# dependent de `pas`, donc leur cadence moyenne reste identique.
	_temps_depuis_maj += delta
	var intervalle_maj: float = 1.0 / _cadence_simulation_hz if _cadence_simulation_hz > 0.0 else 0.0
	if _temps_depuis_maj < intervalle_maj:
		return
	var pas: float = _temps_depuis_maj
	_temps_depuis_maj = 0.0
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
			# REVEIL SEULEMENT SI DEGAGEMENT : une transition qui augmente
			# l'ombrage OU fait entrer dans le statut adulte ne peut PAS
			# ouvrir un gate coince (elle ne peut que le fermer davantage).
			# On ne reveille que sur les transitions qui BAISSENT
			# l'ombrage OU font SORTIR du statut adulte -- les seules qui
			# peuvent debloquer une dormante. Predicat generique via
			# `_stade_est_degageant` : aucun index hardcode, l'invariant
			# tient si la JSON `ombrage_par_stade` change.
			if _stade_est_degageant(ancien, nouveau_index):
				_reveiller_dormantes_autour(_positions_x[i], _positions_z[i])
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
	_avancer_competition(pas)
	_frames_depuis_releve += 1
	if _frames_depuis_releve >= CADENCE_RELEVE_POPULATION_FRAMES:
		_frames_depuis_releve = 0
		var dormantes: int = 0 if _banque_graines == null else _banque_graines.nombre()
		print("[arbre] population = %d, dormantes = %d, cases_couvertes = %d" % [_population, dormantes, _couvert.size()])
		# CHRONOS TEMPORAIRES : releve puis reset. A retirer une fois le
		# poste dominant identifie.
		print("[arbre.tick_banque] ticks=%d total=%d us | setup=%d us / n=%d | query=%d us / n=%d | gate=%d us / n=%d | naissance=%d us / n=%d" % [
			_chrono_n_ticks, _chrono_us_total,
			_chrono_us_setup, _chrono_n_setup,
			_chrono_us_query, _chrono_n_query,
			_chrono_us_gate, _chrono_n_gate,
			_chrono_us_naissance, _chrono_n_naissance])
		_chrono_us_setup = 0
		_chrono_us_query = 0
		_chrono_us_gate = 0
		_chrono_us_naissance = 0
		_chrono_us_total = 0
		_chrono_n_setup = 0
		_chrono_n_query = 0
		_chrono_n_gate = 0
		_chrono_n_naissance = 0
		_chrono_n_ticks = 0

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
	# SKIP GPU si les 4 params sont inchanges au-dela d'EPS_TAILLE
	# (arbre au stade 8 fige, croissance imperceptible entre deux
	# passes). La sentinelle Vector4(INF,...) posee au liberer/vide
	# force le premier ecrit apres naissance ou reagrandissement.
	var ancien: Vector4 = _derniere_params[i]
	if absf(p.x - ancien.x) < EPS_TAILLE \
			and absf(p.y - ancien.y) < EPS_TAILLE \
			and absf(p.z - ancien.z) < EPS_TAILLE \
			and absf(p.w - ancien.w) < EPS_TAILLE:
		return
	_derniere_params[i] = p
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
	var pos_x: float = _positions_x[i]
	var pos_z: float = _positions_z[i]
	var chose = _choses_arbre[i]
	if chose != null:
		_monde.retirer(chose.id)
		_choses_arbre[i] = null
	_derniere_params[i] = Vector4(INF, INF, INF, INF)
	var index: int = _slot_stade[i]
	if index >= 0:
		_deposer_ombrage(pos_x, pos_z, index + 1, -1)
	_slot_stade[i] = -1
	_libres[i] = 1
	_ages[i] = 0.0
	_ecrire_slot_vide(i)
	_slots_libres.append(i)
	_population -= 1
	# EVENEMENT DE VOISINAGE : la mort a retire densite et ombrage --
	# les prospects dormants a portee peuvent voir leur gate s'ouvrir.
	# Reveille les prospects concernes ; ils testeront au prochain
	# `_tick_banque`.
	_reveiller_dormantes_autour(pos_x, pos_z)

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
	# `slot` stocke dans la `chose` : le gate de trouee elargi le relit
	# via `_slot_stade[slot]` pour distinguer adulte / jeune. Pas de parse
	# d'id (fragile).
	var chose := {"id": "arbre_%d" % i, "position": position, "slot": i}
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
# Appele par _deposer_graine (germination directe) ET par _tick_banque
# (une graine reveillee = une requete ciblee a SA position avec
# rayon_gros). UN SEUL chemin, une seule fonction -- si deux chemins
# divergeaient, la banque contournerait le gate et les salves
# reviendraient par elle. Les rejets nes plus tot dans la meme rafale
# sont deja dans _monde (ajout live a chaque _naitre) : la graine
# suivante les voit naturellement via `_monde.choses_dans_rayon`, sans
# liste locale a maintenir -- meme effet que le dict `nouvelles` de
# vegetation.gd.
func _trouee_saturee(pos_x: float, pos_z: float) -> bool:
	var arrivee := Vector3(pos_x, Y_SOL, pos_z)
	var rayon_gros: float = _rayon_trouee * _facteur_trouee_gros
	var carre_normal: float = _rayon_trouee * _rayon_trouee
	var compte_normal: int = 0
	for entree in _monde.choses_dans_rayon(arrivee, rayon_gros):
		var chose = entree.chose
		var slot: int = int(chose.get("slot", -1))
		var stade_num: int = 0
		if slot >= 0 and slot < _slot_stade.size():
			stade_num = _slot_stade[slot] + 1
		if stade_num >= _stade_gros_min and stade_num <= _stade_gros_max:
			return true
		var pos_voisin: Vector3 = chose.position
		if arrivee.distance_squared_to(pos_voisin) <= carre_normal:
			compte_normal += 1
	return compte_normal > _trouee_max_voisins

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
	# Entree en banque, DORMANTE : aucune echeance posee. Elle attendra
	# qu'un evenement de voisinage (mort ou changement de stade) la
	# reveille via `_reveiller_dormantes_autour`. Le test qui vient
	# d'echouer ci-dessus a etabli qu'aucune de ses conditions ne
	# passe MAINTENANT ; sans changement autour d'elle le resultat ne
	# changera pas.
	var id_prospect: int = _banque_graines.ajouter({
		"position": Vector3(pos_x, Y_SOL, pos_z),
	})
	if id_prospect >= 0:
		_inscrire_dormante(id_prospect, pos_x, pos_z)

# RE-TEST SUR EVENEMENT (patron `vegetation.gd` « L'OMBRE EST UN SIGNAL »).
# `pas` est ignore : rien de temporise ici, seul le `_reveils` rempli
# par les evenements de voisinage decide qui teste. Pour chaque prospect
# reveille, meme gate que la germination directe (trouee + couvert). Rate
# le gate -> reste en banque, sort du set des reveils (attend le
# prochain signal). Passe le gate -> retire de la banque et naitre. Le
# gate mord pendant une rafale grace a l'ajout live dans _monde a chaque
# _naitre et au depot d'ombrage a chaque _slot_stade non nul.
#
# NOTE ORDRE : l'ordre des naissances intra-tick est celui d'insertion
# des ids dans `_reveils` (l'evenement declencheur, puis l'ordre
# d'iteration du Dictionary -- garanti insertion sous Godot 4). Ordre
# different de la version pre-optim (echeances triees) : le RNG
# consomme dans `_naitre` (facteurs variance) voit une autre suite. La
# foret reste reproductible a seed egal, elle differe seulement de la
# version pre-optim.
func _tick_banque(_pas: float) -> void:
	if _reveils.is_empty():
		return
	# CHRONOS TEMPORAIRES : voir declaration des _chrono_us_* / _chrono_n_*.
	# La logique du gate est INLINE ici (dupliquee de `_trouee_saturee`)
	# pour isoler QUERY et GATE en postes distincts. A retirer une fois
	# le poste dominant identifie -- rebranchement sur `_trouee_saturee`.
	var t_total: int = Time.get_ticks_usec()
	var prospects: Dictionary = _banque_graines.prospects()
	var ids: Array = _reveils.keys()
	_reveils.clear()
	var rayon_gros: float = _rayon_trouee * _facteur_trouee_gros
	var carre_normal: float = _rayon_trouee * _rayon_trouee
	for id_variant in ids:
		# POSTE 1 : SETUP
		var t0: int = Time.get_ticks_usec()
		var id: int = int(id_variant)
		var a_prospect: bool = prospects.has(id)
		var entree: Dictionary
		var pos: Vector3
		if a_prospect:
			entree = prospects[id]
			pos = entree.position
		_chrono_us_setup += Time.get_ticks_usec() - t0
		_chrono_n_setup += 1
		if not a_prospect:
			continue
		# POSTE 2 : QUERY (choses_dans_rayon seul)
		var arrivee := Vector3(pos.x, Y_SOL, pos.z)
		var t1: int = Time.get_ticks_usec()
		var voisins: Array = _monde.choses_dans_rayon(arrivee, rayon_gros)
		_chrono_us_query += Time.get_ticks_usec() - t1
		_chrono_n_query += 1
		# POSTE 3 : GATE (boucle voisins + couvert)
		var t2: int = Time.get_ticks_usec()
		var compte_normal: int = 0
		var trouee_ko: bool = false
		for entree_v in voisins:
			var chose = entree_v.chose
			var slot: int = int(chose.get("slot", -1))
			var stade_num: int = 0
			if slot >= 0 and slot < _slot_stade.size():
				stade_num = _slot_stade[slot] + 1
			if stade_num >= _stade_gros_min and stade_num <= _stade_gros_max:
				trouee_ko = true
				break
			var pos_voisin: Vector3 = chose.position
			if arrivee.distance_squared_to(pos_voisin) <= carre_normal:
				compte_normal += 1
		if not trouee_ko:
			trouee_ko = compte_normal > _trouee_max_voisins
		var couvert_ko: bool = false
		if not trouee_ko:
			couvert_ko = _lire_couvert(pos.x, pos.z) >= _seuil_couvert
		_chrono_us_gate += Time.get_ticks_usec() - t2
		_chrono_n_gate += 1
		if trouee_ko or couvert_ko:
			continue
		# POSTE 4 : NAISSANCE
		var t3: int = Time.get_ticks_usec()
		_banque_graines.retirer(id)
		_retirer_dormante(id)
		_naitre(pos.x, pos.z)
		_chrono_us_naissance += Time.get_ticks_usec() - t3
		_chrono_n_naissance += 1
	_chrono_us_total += Time.get_ticks_usec() - t_total
	_chrono_n_ticks += 1

# Reveille les prospects dormants a portee d'un evenement de voisinage
# (mort d'arbre ou changement de stade). LECTURE LOCALE via la grille
# `_dormantes_par_case` : le rectangle [pos - R, pos + R] borne les
# cases lues, aucun balayage global de la banque -- cout O(dormants
# reellement dans le rectangle), pas O(N_dormants). Chaque candidat
# est filtre par distance carree pour ne reveiller que les vraies
# graines a portee (les cases au bord du rectangle peuvent contenir
# des graines au dela de R). Dedup par SET `_reveils`.
#
# NOTE ORDRE : l'ordre d'insertion dans `_reveils` suit desormais
# l'ordre cx, cz, id-dans-case (grille) au lieu de l'ordre d'insertion
# dans le registre `AttenteSeuil` (ordre d'entree en banque). Le RNG
# consomme par `_naitre` (facteurs variance) voit donc une autre suite
# -- la foret reste reproductible a seed egal mais differe de la
# version pre-optim. MEMES graines reveillees (celles a distance <= R
# du point), MEMES gates passes, MEMES levees ; seul l'ordre des
# tirages change.
func _reveiller_dormantes_autour(pos_x: float, pos_z: float) -> void:
	if _banque_graines == null or _rayon_reveil <= 0.0 or _taille_case_dormantes <= 0.0:
		return
	if _dormantes_par_case.is_empty():
		return
	var inv_case: float = 1.0 / _taille_case_dormantes
	var cx_min: int = floori((pos_x - _rayon_reveil) * inv_case)
	var cx_max: int = floori((pos_x + _rayon_reveil) * inv_case)
	var cz_min: int = floori((pos_z - _rayon_reveil) * inv_case)
	var cz_max: int = floori((pos_z + _rayon_reveil) * inv_case)
	var carre: float = _rayon_reveil * _rayon_reveil
	var prospects: Dictionary = _banque_graines.prospects()
	for cx in range(cx_min, cx_max + 1):
		for cz in range(cz_min, cz_max + 1):
			var cle: Vector2i = Vector2i(cx, cz)
			var ids = _dormantes_par_case.get(cle, null)
			if ids == null:
				continue
			for id_variant in ids:
				var id: int = int(id_variant)
				if _reveils.has(id):
					continue
				if not prospects.has(id):
					continue
				var entree: Dictionary = prospects[id]
				var pos: Vector3 = entree.position
				var dx: float = pos.x - pos_x
				var dz: float = pos.z - pos_z
				if dx * dx + dz * dz <= carre:
					_reveils[id] = true

# Inscrit une graine dormante dans la grille spatiale (a `_deposer_graine`
# quand l'entree en banque a rendu un id valide). Cout O(1). `_case_de_dormante`
# tient l'index inverse id -> Vector2i pour un retrait O(1).
func _inscrire_dormante(id: int, pos_x: float, pos_z: float) -> void:
	if _taille_case_dormantes <= 0.0:
		return
	var inv_case: float = 1.0 / _taille_case_dormantes
	var cle: Vector2i = Vector2i(floori(pos_x * inv_case), floori(pos_z * inv_case))
	var arr = _dormantes_par_case.get(cle, null)
	if arr == null:
		arr = []
		_dormantes_par_case[cle] = arr
	(arr as Array).append(id)
	_case_de_dormante[id] = cle

# Retire une graine de la grille spatiale (a `_tick_banque` quand elle
# leve, apres `_banque_graines.retirer`). Cout O(k) ou k = taille de
# l'Array de la case (typiquement quelques ids). Silencieux si id
# inconnu : garde contre un double retrait.
func _retirer_dormante(id: int) -> void:
	var cle_v = _case_de_dormante.get(id, null)
	if cle_v == null:
		return
	var cle: Vector2i = cle_v
	_case_de_dormante.erase(id)
	var arr = _dormantes_par_case.get(cle, null)
	if arr == null:
		return
	(arr as Array).erase(id)
	if (arr as Array).is_empty():
		_dormantes_par_case.erase(cle)

# PREDICAT DEGAGEMENT : rend true si la transition ancien -> nouveau
# peut ouvrir un gate coince (donc merite un reveil des dormantes).
# Trois causes disjointes suffisent (une seule suffit) :
#  (a) perte du statut adulte -- l'arbre sort de [_stade_gros_min,
#      _stade_gros_max] -> la barriere trouee elargie disparait pour
#      les seeds a portee ;
#  (b) baisse de la MAGNITUDE d'ombrage -- le pic central baisse
#      -> chaque case touchee recoit moins d'ombrage ;
#  (c) baisse du RAYON d'ombrage -- l'empreinte se retrecit -> des
#      cases jusque-la couvertes ne le sont plus.
# Toute autre transition (ombrage stable ou en hausse, statut adulte
# stable ou pris) ne peut que FERMER un gate deja coince, jamais
# l'ouvrir : reveiller sur ces evenements est pur gaspillage. Aucun
# index hardcode : l'invariant tient si `ombrage_par_stade` change.
func _stade_est_degageant(ancien: int, nouveau: int) -> bool:
	# ancien < 0 = pas de stade franchi avant : rien a comparer, on
	# considere ce cas non degageant (une NAISSANCE ne degage rien
	# de toute facon -- traitee separement).
	if ancien < 0 or nouveau < 0:
		return false
	# (a) Perte du statut adulte.
	var ancien_adulte: bool = (ancien + 1) >= _stade_gros_min and (ancien + 1) <= _stade_gros_max
	var nouveau_adulte: bool = (nouveau + 1) >= _stade_gros_min and (nouveau + 1) <= _stade_gros_max
	if ancien_adulte and not nouveau_adulte:
		return true
	# (b) et (c) : baisse de magnitude OU de rayon d'ombrage.
	if _ombrage_par_stade.size() <= ancien or _ombrage_par_stade.size() <= nouveau:
		return false
	var conf_ancien: Dictionary = _ombrage_par_stade[ancien]
	var conf_nouveau: Dictionary = _ombrage_par_stade[nouveau]
	var mag_ancien: float = float(conf_ancien.get("magnitude", 0.0))
	var mag_nouveau: float = float(conf_nouveau.get("magnitude", 0.0))
	if mag_nouveau < mag_ancien:
		return true
	var rayon_ancien: int = int(conf_ancien.get("rayon_cases", 0))
	var rayon_nouveau: int = int(conf_nouveau.get("rayon_cases", 0))
	if rayon_nouveau < rayon_ancien:
		return true
	return false

# Rayon d'influence d'un evenement (mort, changement de stade) sur les
# graines dormantes : max du rayon trouee elargi (voisin adulte)
# et de la portee maximale d'ombrage. Une graine plus loin que ce rayon
# ne peut voir NI son gate trouee ni son gate couvert change par
# l'evenement. Sur-estimation OK (surface d'ombrage est en cases
# Chebyshev, convertie en unites monde avec un pas de securite).
func _calculer_rayon_reveil() -> void:
	var rayon_gros: float = _rayon_trouee * _facteur_trouee_gros
	var max_rayon_cases: int = 0
	for entree in _ombrage_par_stade:
		if entree is Dictionary:
			max_rayon_cases = maxi(max_rayon_cases, int(entree.get("rayon_cases", 0)))
	# Portee ombrage : distance Chebyshev en cases * taille_case, plus une
	# case de securite pour couvrir un seed a l'oppose de son propre
	# centre de case et un arbre a l'oppose du sien. Diagonale plane
	# sqrt(2) : les cases sont carrees dans XZ.
	var portee_ombrage: float = float(max_rayon_cases + 1) * _taille_case * sqrt(2.0)
	_rayon_reveil = maxf(rayon_gros, portee_ombrage)
	# Cote des cases de la grille des dormantes = rayon de reveil. Le
	# rectangle d'un reveil ([pos - R, pos + R]) fait alors au plus 3
	# cases par axe (2 ou 3 selon l'alignement), aucun scan forfaitaire
	# et aucune case > rayon.
	_taille_case_dormantes = maxf(1.0, _rayon_reveil)

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
	_derniere_params.resize(nouvelle)
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
		_derniere_params[i] = Vector4(INF, INF, INF, INF)
		_slots_libres.append(i)
		_ecrire_slot_vide(i)
		i -= 1
	# Reecriture des slots preexistants dont le buffer GPU vient d'etre
	# reinitialise par le changement d'instance_count ci-dessus. Le cache
	# `_derniere_params` doit etre INVALIDE pour chaque slot vivant, sinon
	# `_ecrire_slot` skippe l'ecrit croyant que rien n'a bouge -- alors que
	# le buffer GPU vient d'etre efface.
	var j: int = 0
	while j < ancienne:
		if _libres[j] == 1:
			_ecrire_slot_vide(j)
		else:
			_derniere_params[j] = Vector4(INF, INF, INF, INF)
			_ecrire_slot(j, _ages[j])
		j += 1

# Passe rare d'auto-eclaircie. Ne tourne QU'a la cadence lente
# `_cadence_competition` (pas dans la boucle 60 fps). Seuls les arbres
# PASSE ETALEE EN ANNEAU : au lieu d'un balayage complet toutes les
# `_cadence_competition` secondes (pic de ~13 ms mesure), chaque passe
# de sim visite `n_slots = ceil(capacite * pas / _cadence_competition)`
# slots depuis `_curseur_competition`. Sur une periode de
# `_cadence_competition` cumulee, la somme visite `_capacite` slots =
# chaque slot exactement une fois en moyenne, sans jamais concentrer
# le cout sur une frame.
#
# Seuls les vulnerables (stade + 1 <= _stade_competition_max) sont
# testes -- les adultes dominent. Mortalite immediate au sein de la
# boucle : `_liberer_slot` mute _libres[i] mais on prend `i =
# _curseur_competition` puis on avance ; les autres slots ne sont pas
# affectes par ce tour, aucune collecte differee necessaire.
#
# NOTE ORDRE : l'ancienne passe balayait i=0..cap dans l'ordre a
# chaque appel ; le nouveau curseur avance en anneau. L'ordre des
# tirages RNG (mortalite) change -- la foret reste reproductible a seed
# egal mais differe de la version pre-etalement.
func _avancer_competition(pas: float) -> void:
	var cap: int = _capacite
	if cap == 0 or _cadence_competition <= 0.0:
		return
	var n_slots: int = int(ceil(float(cap) * pas / _cadence_competition))
	if n_slots < 1:
		n_slots = 1
	if n_slots > cap:
		n_slots = cap
	var count: int = 0
	while count < n_slots:
		var i: int = _curseur_competition
		_curseur_competition = (_curseur_competition + 1) % cap
		count += 1
		if _libres[i] == 1:
			continue
		var index: int = _slot_stade[i]
		if index < 0 or index + 1 > _stade_competition_max:
			continue
		var pos := Vector3(_positions_x[i], Y_SOL, _positions_z[i])
		var voisins: int = _monde.choses_dans_rayon(pos, _rayon_competition).size()
		if voisins > _competition_max_voisins:
			var exces: int = voisins - _competition_max_voisins
			var proba: float = clampf(
				float(exces) / float(maxi(1, _competition_max_voisins)), 0.0, 1.0)
			if _rng.randf() < proba:
				_liberer_slot(i)
