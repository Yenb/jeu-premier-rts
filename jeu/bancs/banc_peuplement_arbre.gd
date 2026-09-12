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
# COUCHE LOGIQUE (coeur) : franchissement de frontiere en LOT une fois
# par tick. `Senescence.avancer_lot` mute `_ages` en place ;
# `Stade.avancer_lot` mute `_slot_stade` (index int, aucun passage par
# String). La boucle par arbre qui restait pour la detection de
# transition et le tirage RNG lit directement `_slot_stade_avant` /
# `_slot_stade` sans jamais reconstruire un Dictionary par entite.
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
# CHAMP DE COUVERT : delegue au mecanisme framework
# `scripts/champ_saturation.gd` (depot signe a decroissance Chebyshev
# lineaire, retrait symetrique, nettoyage sous epsilon). Le banc detient
# une instance `_couvert`, y ecrit a la naissance/mort/changement de
# stade (`_deposer_ombrage`), la graine y LIT en O(1) (`_lire_couvert`).
# Le rayon d'ombre est lu en METRES depuis `ombrage_par_stade`, converti
# en cases par le mecanisme via `_taille_case` : portee physique
# independante de la finesse du quadrillage.
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
const ChampSaturation = preload("res://scripts/champ_saturation.gd")

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
# et la garde de _semer_lot derivent tous deux de cette valeur.
var _demi_carte: float = 300.0
# Gate : true = le joueur (CharacterBody3D, exception CLAUDE.md) est
# instancie et sa camera est current ; false = pas de joueur, la camera
# plongeante de la scene devient current.
var _joueur_actif: bool = true
var _graine_rng: int = 20260910
# NOMBRE MOYEN DE GRAINES PRODUITES PAR ARBRE SUR TOUTE SA VIE FERTILE.
# Reglage stable de la pression de reproduction : contrairement a un
# intervalle en secondes, ce nombre NE change PAS quand on modifie les
# durees des stades ou la variance de croissance. Un arbre lent, fertile
# plus longtemps, ESPACE ses graines ; un arbre rapide les RESSERRE ;
# le total moyen par arbre reste `_graines_par_vie` pour tous.
# L'intervalle effectif par arbre est deduit a la naissance et stocke
# dans `_intervalle_reprod[i]`.
var _graines_par_vie: float = 24.0
# Duree en secondes de sim (age) de la fenetre fertile commune, calculee
# une fois apres le chargement : `_fin_fertilite - _debut_fertilite`. Sert
# a deriver l'intervalle effectif de chaque arbre.
var _fenetre_fertile_age: float = 0.0
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
# d'ombrage (max des `rayon_ombre_m` du JSON, deja en unites monde --
# la portee physique de l'ombre est independante de `taille_case`). Sur-estimation OK : le reveil est
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
# Cache du dernier stade dont la couleur a ete ecrite pour le slot.
# Sentinelle -1 = "jamais ecrit" -> premier ecrit force la couleur.
# La couleur ne depend que du stade : on ne re-ecrit que si le stade
# change. Invalide au liberer/agrandir (buffer GPU efface par
# `instance_count`).
var _derniere_couleur_stade: PackedInt32Array = PackedInt32Array()

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
# COULEURS PAR STADE (patron `_ombrage_par_stade` : tableau indexe par
# stade, lu, jamais mute). Une entree Color par stade, meme taille que
# `_stades`. Repli sur les couleurs actuelles (tronc marron, feuillage
# vert) si les cles JSON sont absentes : ne casse pas.
var _couleur_tronc_par_stade: PackedColorArray = PackedColorArray()
var _couleur_feuillage_par_stade: PackedColorArray = PackedColorArray()
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
# Intervalle effectif de reproduction (secondes reelles) par slot,
# calcule a la naissance : `_fenetre_fertile_age /
# (_annees_par_seconde * _facteur_croissance[i] * _graines_par_vie)`.
# Un arbre lent (facteur bas) recoit un intervalle plus grand -- ses
# graines s'espacent d'autant qu'il est fertile plus longtemps, total
# constant. INF pour un slot invalide (fenetre nulle ou graines_par_vie
# nul) -> proba nulle, aucune reproduction.
var _intervalle_reprod: PackedFloat32Array = PackedFloat32Array()

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
var _chrono_us_expiration: int = 0
var _chrono_us_total: int = 0
var _chrono_n_setup: int = 0
var _chrono_n_query: int = 0
var _chrono_n_gate: int = 0
var _chrono_n_naissance: int = 0
var _chrono_n_expiration: int = 0
var _chrono_n_ticks: int = 0

# Champ scalaire d'ombrage par case, delegue au mecanisme framework
# scripts/champ_saturation.gd (depot signe a decroissance Chebyshev
# lineaire, retrait symetrique, nettoyage sous epsilon). Instancie au
# _ready.
var _couvert: RefCounted = null

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

# LOT DE GRAINES A SEMER, cumule pendant la boucle des arbres de _process
# et draine par `_semer_lot` apres la boucle. Deux PackedFloat32Array
# paralleles (position XZ) reutilisees tick apres tick : resize(0) au
# debut du tick garde la capacite deja allouee, aucune allocation neuve
# en regime. Une passe de traitement par tick au lieu d'un appel par
# arbre.
var _graines_lot_x: PackedFloat32Array = PackedFloat32Array()
var _graines_lot_z: PackedFloat32Array = PackedFloat32Array()

# NOUVEAU-NES DU LOT COURANT : positions XZ des graines qui ont naitre
# depuis le debut du drainage de `_semer_lot`. Reutilises tick apres
# tick. Utile parce que la requete GROUPEE `_monde.choses_dans_rayons`
# est prise UNE fois avant toute naissance du lot -- elle ne voit que
# les arbres deja inscrits. Les nouveau-nes de la meme rafale doivent
# etre visibles par les graines suivantes pour que le gate de trouee
# morde comme avant. Scanne lineairement au traitement de chaque
# candidat suivant.
var _naissances_lot_x: PackedFloat32Array = PackedFloat32Array()
var _naissances_lot_z: PackedFloat32Array = PackedFloat32Array()

# LOT DE TRANSITIONS DE STADE, cumule pendant la boucle des arbres et
# draine par UN seul appel a `_couvert.redeposer_lot` apres la boucle.
# Six PackedFloat32Array paralleles reutilises tick apres tick
# (`resize(0)` au debut du tick, aucune allocation en regime) : position
# XZ + rayon ancien/nouveau (metres) + magnitude ancienne/nouvelle. Les
# cas signe seul (naissance / mort) restent en appel direct a
# `_deposer_ombrage` -- seule la transition ancien->nouveau (les deux
# stades existent) passe par le lot.
var _transitions_x: PackedFloat32Array = PackedFloat32Array()
var _transitions_z: PackedFloat32Array = PackedFloat32Array()
var _transitions_rayon_a: PackedFloat32Array = PackedFloat32Array()
var _transitions_rayon_n: PackedFloat32Array = PackedFloat32Array()
var _transitions_mag_a: PackedFloat32Array = PackedFloat32Array()
var _transitions_mag_n: PackedFloat32Array = PackedFloat32Array()

# LOT DE COMPETITION : reutilise appel apres appel de `_avancer_competition`.
# Deux colonnes paralleles collectees en une passe de l'anneau (positions
# Vector3 + indices de slot) puis draines par UN appel a
# `_monde.choses_dans_rayons`. Reutilises tick apres tick (resize/clear
# au debut de chaque appel a `_avancer_competition`).
var _competition_positions: Array = []
var _competition_slots: PackedInt32Array = PackedInt32Array()

# POSITIONS DE REVEIL DES DORMANTES, collectees pendant la passe de
# transition et drainees par UN appel a `_reveiller_dormantes_autour_lot`
# apres la boucle. Reutilisees tick apres tick (`resize(0)` en debut de
# tick, aucune allocation en regime). Le reveil est un SET par
# `_reveils` (Dictionary utilise comme Set d'ids), l'ordre de traitement
# n'affecte pas le contenu final -- batching sur.
var _reveils_positions_x: PackedFloat32Array = PackedFloat32Array()
var _reveils_positions_z: PackedFloat32Array = PackedFloat32Array()

# LOT DE MORTS DE VIEILLESSE, collectees pendant la boucle des arbres et
# drainees par UN appel a `_liberer_morts_vieillesse_lot` apres la
# boucle. Reutilisee tick apres tick. Le comportement de `_liberer_slot`
# est reproduit inline dans le drainage (retrait monde, retrait ombrage,
# append reveil pos, reset colonnes, libre + slot_libres + _ecrire_slot_vide,
# decrement _population).
var _morts_vieillesse_lot: PackedInt32Array = PackedInt32Array()

# GRILLE SPATIALE PROPRE A LA BANQUE (patron LOCALITE SPATIALE du
# CLAUDE.md, variante monde-indexe adaptee aux ids stables). Cle =
# Vector2i (case du plan XZ, cote `_taille_case_dormantes`), valeur =
# Array<int> des ids de prospects dormants dans cette case. Insertion a
# `_semer_lot`, retrait quand une graine leve (`_tick_banque`).
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

# DUREE DE VIE DES GRAINES DORMANTES : sans mortalite, la banque
# n'aurait aucun plafond -- toute graine tombee en zone dense y
# entrerait et n'en sortirait qu'a une levee. Or beaucoup ne levent
# JAMAIS (place jamais liberee, couvert jamais bas), et chacune reste
# alors reveillable a l'infini : chaque evenement voisin la reveille,
# elle refait une requete spatiale, echoue, replonge. La banque
# devient un reservoir qui alourdit les reveils sans jamais donner
# une plante. Une graine dormante finit donc par MOURIR apres
# `_duree_vie_graine` secondes de temps monde sans lever -- comme
# dans la nature. Reglable en JSON.
var _duree_vie_graine: float = 300.0

# TEMPS MONDE DE LA BANQUE (secondes cumulees). Reintroduit
# uniquement pour dater les echeances de mort des dormantes.
# Avance a chaque `_tick_banque` de `pas` (le meme delta accumule
# passe a la sim). Aucun autre role : la reveil des dormantes reste
# evenementiel, la germination reste sans horloge.
var _temps_banque: float = 0.0

# FILE FIFO DES ECHEANCES DE MORT : Array de [echeance:float, id:int]
# range par ORDRE D'INSERTION -- comme `_duree_vie_graine` est fixe,
# l'ordre d'insertion = l'ordre chronologique d'expiration, aucun tri
# n'est requis. Curseur `_expirations_head` avance sur les entrees
# drainees. Trim (`slice(head)`) declenche quand head > 1024 ET
# head > size/2 pour ne pas laisser l'Array croitre sans borne. Insert
# O(1) (append), drain O(k) ou k = expirations du tick (typiquement
# 0-10). Lazy discard : une entree dont l'id n'est plus dans
# `_banque_graines.prospects()` (graine levee entre-temps) est
# skippee au drain, aucun retrait synchronise a la levee.
var _expirations: Array = []
var _expirations_head: int = 0

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


func _ready() -> void:
	_charger_reglages_locaux()
	_calculer_rayon_reveil()
	_rng.seed = _graine_rng
	_couvert = ChampSaturation.new()
	_monde = Monde.new()
	_monde.structure_simple = true
	_monter_scene()
	if _joueur_actif:
		_monter_joueur()
	_monter_population()
	_construire_catalogue()
	_banque_graines = AttenteSeuil.new()
	if _stades.size() == 9:
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
		push_warning("banc_peuplement_arbre : cle JSON `intervalle_graine_moyen` obsolete, remplacee par `graines_par_vie` (nombre moyen de graines produites par arbre sur sa vie fertile)")
	if donnees.has("graines_par_vie"):
		_graines_par_vie = float(donnees.graines_par_vie)
	if donnees.has("rayon_graine"):
		_rayon_graine = float(donnees.rayon_graine)
	if donnees.has("stade_fertile_debut"):
		_stade_fertile_debut = int(donnees.stade_fertile_debut)
	if donnees.has("stade_fertile_fin"):
		_stade_fertile_fin = int(donnees.stade_fertile_fin)
	_stade_fertile_debut = clampi(_stade_fertile_debut, 1, 9)
	_stade_fertile_fin = clampi(_stade_fertile_fin, _stade_fertile_debut, 9)
	if donnees.has("taille_case"):
		_taille_case = float(donnees.taille_case)
	if donnees.has("seuil_couvert"):
		_seuil_couvert = float(donnees.seuil_couvert)
	if donnees.has("duree_vie_graine"):
		_duree_vie_graine = float(donnees.duree_vie_graine)
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
	# COULEURS PAR STADE : chaque entree JSON est [r, g, b] (floats 0-1),
	# convertie en Color. Repli sur (marron, vert) pour tous les stades
	# si la cle est absente -- comportement pre-fix.
	_couleur_tronc_par_stade = PackedColorArray()
	if donnees.has("couleur_tronc_par_stade"):
		for e in donnees.couleur_tronc_par_stade:
			var arr: Array = e
			_couleur_tronc_par_stade.append(Color(float(arr[0]), float(arr[1]), float(arr[2])))
	_couleur_feuillage_par_stade = PackedColorArray()
	if donnees.has("couleur_feuillage_par_stade"):
		for e in donnees.couleur_feuillage_par_stade:
			var arr: Array = e
			_couleur_feuillage_par_stade.append(Color(float(arr[0]), float(arr[1]), float(arr[2])))
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
	if _stades.size() != 9:
		push_error("banc_peuplement_arbre : `stades` doit contenir 9 entrees (recu %d)" % _stades.size())
	if _durees.size() != 8:
		push_error("banc_peuplement_arbre : `durees_stades` doit contenir 8 entrees (recu %d)" % _durees.size())
	if _ombrage_par_stade.size() != 9:
		push_error("banc_peuplement_arbre : `ombrage_par_stade` doit contenir 9 entrees (recu %d)" % _ombrage_par_stade.size())
	_duree_croissance_totale = 0.0
	for d in _durees:
		_duree_croissance_totale += float(d)
	# Bornes de fertilite lues du JSON (stade_fertile_debut/fin, 1..9, inclus).
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
	# Duree en secondes de sim (age) de la fenetre fertile commune.
	# L'intervalle effectif de chaque arbre s'en deduit a la naissance
	# via `_facteur_croissance[i]` -- voir _naitre.
	_fenetre_fertile_age = maxf(0.0, _fin_fertilite - _debut_fertilite)

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
	for i in range(_stades.size()):
		stades_config.append({"nom": "s%d" % (i + 1), "age_seuil": cumul})
		if i < _durees.size():
			cumul += float(_durees[i])
	_catalogue[TYPE_ARBRE] = {
		"herite": ["dynamique"],
		"stades_config": stades_config,
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
	# Couleur d'instance -> albedo (paire OBLIGATOIRE avec
	# `_mm_tronc.use_colors = true` : sans les deux, `set_instance_color`
	# est ignore silencieusement).
	mat_tronc.vertex_color_use_as_albedo = true
	tronc_mesh.material = mat_tronc
	_mm_tronc = MultiMesh.new()
	_mm_tronc.transform_format = MultiMesh.TRANSFORM_3D
	_mm_tronc.use_colors = true
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
	# Couleur d'instance -> albedo (paire OBLIGATOIRE avec use_colors,
	# meme raison que pour le tronc).
	mat_feuillage.vertex_color_use_as_albedo = true
	cone.material = mat_feuillage
	_mm_feuillage = MultiMesh.new()
	_mm_feuillage.transform_format = MultiMesh.TRANSFORM_3D
	_mm_feuillage.use_colors = true
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
	_intervalle_reprod.resize(_capacite)
	_choses_arbre.resize(_capacite)
	_derniere_params.resize(_capacite)
	_derniere_couleur_stade.resize(_capacite)
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
		_intervalle_reprod[i] = INF
		_choses_arbre[i] = null
		_derniere_params[i] = Vector4(INF, INF, INF, INF)
		_derniere_couleur_stade[i] = -1
		_slots_libres.append(i)
		_ecrire_slot_vide(i)
		i -= 1

func _process(delta: float) -> void:
	if _stades.size() != 9 or _durees.size() != 8 or _stades_config_partagee.is_empty():
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
	# LOT DE GRAINES A SEMER : vide en debut de tick. resize(0) garde la
	# capacite deja allouee (aucune allocation neuve tick apres tick une
	# fois le regime atteint).
	_graines_lot_x.resize(0)
	_graines_lot_z.resize(0)
	# LOT DE TRANSITIONS DE STADE : meme discipline, videe en debut de
	# tick. Draine par UN appel a `_couvert.redeposer_lot` apres la
	# boucle des arbres, avant `_semer_lot` (les graines candidates
	# lisent alors le couvert a jour).
	_transitions_x.resize(0)
	_transitions_z.resize(0)
	_transitions_rayon_a.resize(0)
	_transitions_rayon_n.resize(0)
	_transitions_mag_a.resize(0)
	_transitions_mag_n.resize(0)
	# LOT DE POSITIONS DE REVEIL des dormantes : meme discipline. Draine
	# par UN appel a `_reveiller_dormantes_autour_lot` apres la boucle.
	_reveils_positions_x.resize(0)
	_reveils_positions_z.resize(0)
	# LOT DE MORTS DE VIEILLESSE : meme discipline. Draine par UN appel
	# a `_liberer_morts_vieillesse_lot` apres la boucle, avant le reveil
	# groupe (les morts appendent des positions de reveil a leur tour).
	_morts_vieillesse_lot.resize(0)
	# SENESCENCE EN LOT : un seul franchissement de frontiere pour tout le
	# tick. Mute `_ages` en place, saute les slots libres. Ordre des
	# multiplications preserve dans le mecanisme (`delta * (aps * facteur)`).
	Senescence.avancer_lot(_ages, _libres, pas, _annees_par_seconde, _facteur_croissance)
	# STADE EN LOT : mute `_slot_stade` en place, sans passage par String.
	# `_slot_stade_avant` capture l'index PRE-tick pour que la detection de
	# transition et `_liberer_slot` (seuil_mort) lisent bien l'index ANCIEN.
	# JAMAIS UN RECUL : la mecanique `avancer_lot` respecte l'invariant du
	# port unitaire (aucun retour arriere), le duplicate ne sert que pour
	# la comparaison.
	var _slot_stade_avant: PackedInt32Array = _slot_stade.duplicate()
	Stade.avancer_lot(_ages, _libres, _slot_stade, _stades_config_partagee)
	# Capacite figee en debut de boucle.
	var cap: int = _capacite
	var i: int = 0
	while i < cap:
		if _libres[i] == 1:
			i += 1
			continue
		# Age reel compare au seuil de mort MODULE par la longevite individuelle.
		var seuil_mort: float = (_duree_croissance_totale + _duree_mort) * _facteur_longevite[i]
		var age_i: float = _ages[i]
		if age_i >= seuil_mort:
			# L'arbre meurt AVANT que sa transition de stade prenne effet
			# (comportement de la version unitaire). On restaure l'index
			# ancien pour que le drainage groupe depose bien -1 sur
			# l'empreinte du stade ancien, jamais du stade nouvellement
			# franchi. La liberation reelle (retrait monde, ombrage,
			# reveil) est differee au drainage `_liberer_morts_vieillesse_lot`
			# apres la boucle.
			_slot_stade[i] = _slot_stade_avant[i]
			_morts_vieillesse_lot.append(i)
			i += 1
			continue
		# Detection de changement de stade -> maj du champ de couvert.
		var ancien: int = _slot_stade_avant[i]
		var nouveau_index: int = _slot_stade[i]
		if nouveau_index != ancien:
			# TRANSITION EN UNE PASSE : empilement INLINE (aucun appel de
			# fonction par arbre). Cas ancien >= 0 ET nouveau >= 0 : empile
			# une transition qui sera fusionnee par `_couvert.redeposer_lot`.
			# Cas naissance/mort (un seul stade existe) : `_deposer_ombrage`
			# simple (rare, chemin degrade).
			if ancien >= 0 and nouveau_index >= 0:
				var stade_a: int = ancien + 1
				var stade_n: int = nouveau_index + 1
				var n_conf: int = _ombrage_par_stade.size()
				if stade_a >= 1 and stade_a <= n_conf and stade_n >= 1 and stade_n <= n_conf:
					var conf_a: Dictionary = _ombrage_par_stade[stade_a - 1]
					var conf_n: Dictionary = _ombrage_par_stade[stade_n - 1]
					_transitions_x.append(_positions_x[i])
					_transitions_z.append(_positions_z[i])
					_transitions_rayon_a.append(float(conf_a.get("rayon_ombre_m", 0.0)))
					_transitions_rayon_n.append(float(conf_n.get("rayon_ombre_m", 0.0)))
					_transitions_mag_a.append(float(conf_a.get("magnitude", 0.0)))
					_transitions_mag_n.append(float(conf_n.get("magnitude", 0.0)))
			elif ancien >= 0:
				_deposer_ombrage(_positions_x[i], _positions_z[i], ancien + 1, -1)
			elif nouveau_index >= 0:
				_deposer_ombrage(_positions_x[i], _positions_z[i], nouveau_index + 1, 1)
			# `_slot_stade[i]` deja mute par `Stade.avancer_lot`.
			# REVEIL SEULEMENT SI DEGAGEMENT (predicat INLINE) : perte du
			# statut adulte OU baisse de magnitude OU baisse de rayon. Toute
			# autre transition ne peut que fermer davantage un gate deja
			# coince, jamais l'ouvrir. Position empilee dans le lot de
			# reveils ; le traitement se fait en UNE passe apres la boucle
			# dans `_reveiller_dormantes_autour_lot`.
			var degageant: bool = false
			if ancien >= 0 and nouveau_index >= 0:
				var ancien_adulte: bool = (ancien + 1) >= _stade_gros_min and (ancien + 1) <= _stade_gros_max
				var nouveau_adulte: bool = (nouveau_index + 1) >= _stade_gros_min and (nouveau_index + 1) <= _stade_gros_max
				if ancien_adulte and not nouveau_adulte:
					degageant = true
				else:
					var n_conf2: int = _ombrage_par_stade.size()
					if n_conf2 > ancien and n_conf2 > nouveau_index:
						var conf_a2: Dictionary = _ombrage_par_stade[ancien]
						var conf_n2: Dictionary = _ombrage_par_stade[nouveau_index]
						if float(conf_n2.get("magnitude", 0.0)) < float(conf_a2.get("magnitude", 0.0)):
							degageant = true
						elif float(conf_n2.get("rayon_ombre_m", 0.0)) < float(conf_a2.get("rayon_ombre_m", 0.0)):
							degageant = true
			if degageant:
				_reveils_positions_x.append(_positions_x[i])
				_reveils_positions_z.append(_positions_z[i])
		# REPRODUCTION extraite du tree loop -> `_reproduire_lot(pas)`
		# apres les lots de mort/reveil/couvert (place avant `_semer_lot`
		# qui draine `_graines_lot_*`).
		i += 1
	# MORTS DE VIEILLESSE EN LOT : draine les slots dont l'age a franchi
	# le seuil de mort ce tick. Un seul appel pour tous, meme resultat
	# que N appels a `_liberer_slot` dans la boucle des arbres. Chaque
	# mort append sa position aux `_reveils_positions_*` pour que le
	# reveil groupe qui suit couvre AUSSI les morts (patron unifie).
	_liberer_morts_vieillesse_lot()
	# REVEIL EN LOT : un seul appel pour toutes les transitions degageantes
	# du tick ET les morts de vieillesse, meme resultat que N appels a
	# `_reveiller_dormantes_autour` (le contenu de `_reveils` est un Set
	# d'ids, invariant a l'ordre).
	_reveiller_dormantes_autour_lot(_reveils_positions_x, _reveils_positions_z)
	# LOT DE TRANSITIONS applique en UNE passe : un seul appel au champ
	# pour toutes les transitions de stade du tick, au lieu de N appels.
	# Doit tourner AVANT `_semer_lot` (qui lit `_lire_couvert` sur chaque
	# candidat) et AVANT `_tick_banque` (idem sur les prospects
	# reveilles) pour que le couvert reflete l'etat post-tick.
	if _transitions_x.size() > 0:
		_couvert.redeposer_lot(_transitions_x, _transitions_z, _transitions_rayon_a, _transitions_rayon_n, _taille_case, _transitions_mag_a, _transitions_mag_n)
	# REPRODUCTION EN LOT : passe unique sur les vivants (post-mort_lot,
	# donc les morts du tick sont deja marques `_libres[i] == 1`). Ordre
	# RNG strictement identique a la version tree-loop : meme sequence
	# de `_rng.randf()` sur les memes slots dans le meme ordre d'indice.
	# Empile dans `_graines_lot_*`, draine par `_semer_lot` juste apres.
	_reproduire_lot(pas)
	_semer_lot()
	_tick_banque(pas)
	# NAISSANCES EN LOT : draine `_naissances_lot_x/_z` empile par
	# `_semer_lot` et `_tick_banque`. Un seul appel groupe pour toutes
	# les naissances du tick (alloc slots, tirer variance en paires
	# interleaved, `monde.ajouter_lot`, `champ.deposer_lot`). Ordre
	# RNG variance = ordre des naissances dans la queue = ordre naturel
	# (semer d'abord, puis tick_banque). Objet.fabriquer skippe.
	_naitre_lot()
	_avancer_competition(pas)
	# RENDU EN LOT : un seul appel groupe pour tous les slots vivants. Le
	# corps de `_ecrire_slot` + `_calc_params` + `_appliquer_couleur_slot`
	# est reproduit inline dans la boucle interne unique -- zero appel
	# de fonction par arbre au chemin chaud. `_naitre` et
	# `_agrandir_capacite` gardent `_ecrire_slot` pour leurs points de
	# naissance / repose du buffer GPU (chemins rares).
	_ecrire_slots_lot()
	_frames_depuis_releve += 1
	if _frames_depuis_releve >= CADENCE_RELEVE_POPULATION_FRAMES:
		_frames_depuis_releve = 0
		var dormantes: int = 0 if _banque_graines == null else _banque_graines.nombre()
		print("[arbre] population = %d, dormantes = %d, cases_couvertes = %d" % [_population, dormantes, _couvert.nombre_cases()])
		# CHRONOS TEMPORAIRES : releve puis reset. A retirer une fois le
		# poste dominant identifie.
		print("[arbre.tick_banque] ticks=%d total=%d us | setup=%d us / n=%d | query=%d us / n=%d | gate=%d us / n=%d | naissance=%d us / n=%d | expiration=%d us / n=%d" % [
			_chrono_n_ticks, _chrono_us_total,
			_chrono_us_setup, _chrono_n_setup,
			_chrono_us_query, _chrono_n_query,
			_chrono_us_gate, _chrono_n_gate,
			_chrono_us_naissance, _chrono_n_naissance,
			_chrono_us_expiration, _chrono_n_expiration])
		_chrono_us_setup = 0
		_chrono_us_query = 0
		_chrono_us_gate = 0
		_chrono_us_naissance = 0
		_chrono_us_expiration = 0
		_chrono_us_total = 0
		_chrono_n_setup = 0
		_chrono_n_query = 0
		_chrono_n_gate = 0
		_chrono_n_naissance = 0
		_chrono_n_expiration = 0
		_chrono_n_ticks = 0

# Interpolation de taille entre deux entrees consecutives du catalogue
# `stades` local (rendu, aucun rapport avec stade.gd qui ne pose que le
# nom). Rend un Vector4 (h_tronc, l_tronc, h_feuillage, l_feuillage).
# RENDU EN LOT : ecrit les transforms et couleurs de TOUS les slots
# vivants dans les deux MultiMesh en UNE boucle interne. Corps de
# `_ecrire_slot` + `_calc_params` + `_appliquer_couleur_slot` inline,
# zero appel de fonction par arbre. Les skips existants sont preserves :
# EPS_TAILLE sur `_derniere_params` (arbre au dernier stade fige,
# croissance imperceptible entre deux passes) et cache `_derniere_couleur_stade`
# par stade (couleur re-ecrite seulement quand le stade change). Duplication
# assumee avec `_ecrire_slot` -- meme discipline que `redeposer_lot`/
# `redeposer` : les chemins rares (`_naitre`, `_agrandir_capacite`) gardent
# la version unitaire.
func _ecrire_slots_lot() -> void:
	var cap: int = _capacite
	if cap == 0:
		return
	var n_stades: int = _durees.size()
	var n_stades_full: int = _stades.size()
	var i: int = 0
	while i < cap:
		if _libres[i] == 1:
			i += 1
			continue
		var age: float = _ages[i]
		# INLINE _calc_params : interpolation lineaire entre deux stades
		# consecutifs selon l'age accumule dans les durees.
		var p: Vector4
		var trouve: bool = false
		var duree_cumulee: float = 0.0
		var j: int = 0
		while j < n_stades:
			var duree_segment: float = _durees[j]
			if age <= duree_cumulee + duree_segment:
				var t: float = 0.0
				if duree_segment > 0.0:
					t = (age - duree_cumulee) / duree_segment
				if t < 0.0:
					t = 0.0
				elif t > 1.0:
					t = 1.0
				var a: Dictionary = _stades[j]
				var b: Dictionary = _stades[j + 1]
				p = Vector4(
					lerp(float(a.tronc.hauteur), float(b.tronc.hauteur), t),
					lerp(float(a.tronc.largeur), float(b.tronc.largeur), t),
					lerp(float(a.feuillage.hauteur), float(b.feuillage.hauteur), t),
					lerp(float(a.feuillage.largeur), float(b.feuillage.largeur), t))
				trouve = true
				break
			duree_cumulee += duree_segment
			j += 1
		if not trouve:
			var s: Dictionary = _stades[n_stades_full - 1]
			p = Vector4(
				float(s.tronc.hauteur), float(s.tronc.largeur),
				float(s.feuillage.hauteur), float(s.feuillage.largeur))
		# INLINE _appliquer_couleur_slot : traitee AVANT le skip GPU des
		# tailles (le stade peut bouger sans que les tailles bougent).
		var stade_actuel: int = _slot_stade[i]
		if _derniere_couleur_stade[i] != stade_actuel:
			var col_tronc: Color = COULEUR_REPLI_TRONC
			var col_feuillage: Color = COULEUR_REPLI_FEUILLAGE
			if stade_actuel >= 0 and stade_actuel < _couleur_tronc_par_stade.size():
				col_tronc = _couleur_tronc_par_stade[stade_actuel]
			if stade_actuel >= 0 and stade_actuel < _couleur_feuillage_par_stade.size():
				col_feuillage = _couleur_feuillage_par_stade[stade_actuel]
			_mm_tronc.set_instance_color(i, col_tronc)
			_mm_feuillage.set_instance_color(i, col_feuillage)
			_derniere_couleur_stade[i] = stade_actuel
		# SKIP EPS_TAILLE : arbre fige, aucun transform a repousser.
		var ancien: Vector4 = _derniere_params[i]
		if absf(p.x - ancien.x) < EPS_TAILLE \
				and absf(p.y - ancien.y) < EPS_TAILLE \
				and absf(p.z - ancien.z) < EPS_TAILLE \
				and absf(p.w - ancien.w) < EPS_TAILLE:
			i += 1
			continue
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
		i += 1

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
	# Fallback = dernier stade (mort). Lu dynamiquement pour ne pas
	# presumer le nombre de stades.
	var s: Dictionary = _stades[_stades.size() - 1]
	return Vector4(
		float(s.tronc.hauteur), float(s.tronc.largeur),
		float(s.feuillage.hauteur), float(s.feuillage.largeur))

# Ecrit les deux transforms du slot depuis les quatre parametres interpoles.
# Meshes sources UNITAIRES. Empilement : base du tronc a y=Y_SOL, base du
# feuillage au sommet du tronc. Feuillage a hauteur/largeur nulle : Basis
# a echelle nulle -> instance invisible.
func _ecrire_slot(i: int, age: float) -> void:
	var p: Vector4 = _calc_params(age)
	# COULEUR : ecrite si le stade a change depuis la derniere pose du
	# slot. Traitee AVANT le skip GPU des tailles -- le stade peut
	# bouger sans que les tailles bougent significativement (transition
	# adulte -> senescent, tronc identique). Sentinelle -1 = "jamais
	# ecrit" -> premier appel apres naissance/agrandissement force la
	# pose. Un arbre fige a son stade final ne re-ecrit sa couleur qu'a
	# la premiere passe apres avoir atteint ce stade, jamais ensuite.
	var stade_actuel: int = _slot_stade[i]
	if _derniere_couleur_stade[i] != stade_actuel:
		_appliquer_couleur_slot(i, stade_actuel)
		_derniere_couleur_stade[i] = stade_actuel
	# SKIP GPU si les 4 params sont inchanges au-dela d'EPS_TAILLE
	# (arbre au dernier stade fige, croissance imperceptible entre
	# deux passes). La sentinelle Vector4(INF,...) posee au liberer/vide
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
# Le cache couleur du slot est reset : le prochain _ecrire_slot force
# la pose de couleur.
func _ecrire_slot_vide(i: int) -> void:
	var t := Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3(0.0, Y_SOL, 0.0))
	_mm_tronc.set_instance_transform(i, t)
	_mm_feuillage.set_instance_transform(i, t)
	if i < _derniere_couleur_stade.size():
		_derniere_couleur_stade[i] = -1

# Pose la couleur d'instance du slot pour le stade donne (index 0-based
# dans `_couleur_*_par_stade`). Repli sur les couleurs marron/vert
# actuelles si l'index est hors table (JSON absent ou entrees
# insuffisantes) -- ne casse pas.
const COULEUR_REPLI_TRONC := Color(0.35, 0.22, 0.12)
const COULEUR_REPLI_FEUILLAGE := Color(0.15, 0.45, 0.2)
func _appliquer_couleur_slot(i: int, stade_index: int) -> void:
	var col_tronc: Color = COULEUR_REPLI_TRONC
	var col_feuillage: Color = COULEUR_REPLI_FEUILLAGE
	if stade_index >= 0 and stade_index < _couleur_tronc_par_stade.size():
		col_tronc = _couleur_tronc_par_stade[stade_index]
	if stade_index >= 0 and stade_index < _couleur_feuillage_par_stade.size():
		col_feuillage = _couleur_feuillage_par_stade[stade_index]
	_mm_tronc.set_instance_color(i, col_tronc)
	_mm_feuillage.set_instance_color(i, col_feuillage)

# DEPOT D'OMBRAGE VIA champ_saturation.gd -- signe -1 = retrait strictement
# symetrique. `stade` = numero de stade (1..N, index+1) pour lire
# `_ombrage_par_stade[stade-1]` : rayon_ombre_m (metres) + magnitude. Le
# mecanisme framework porte la loi (decroissance Chebyshev lineaire,
# nettoyage sous epsilon, conversion metres->cases par ceil).
func _deposer_ombrage(pos_x: float, pos_z: float, stade: int, signe: int) -> void:
	if stade < 1 or stade > _ombrage_par_stade.size():
		return
	var conf: Dictionary = _ombrage_par_stade[stade - 1]
	# Portee lue en METRES, convertie en rayon de cases par le mecanisme
	# framework `champ_saturation.gd` au moment de la pose : la portee
	# physique reste stable quand `_taille_case` change. La seule source
	# de verite est le JSON en metres.
	var rayon_m: float = float(conf.get("rayon_ombre_m", 0.0))
	var mag: float = float(conf.get("magnitude", 0.0))
	_couvert.deposer(pos_x, pos_z, rayon_m, _taille_case, mag, signe)

func _lire_couvert(pos_x: float, pos_z: float) -> float:
	return _couvert.lire(pos_x, pos_z, _taille_case)

# DRAINAGE DES MORTS DE VIEILLESSE en UNE passe. Reproduit `_liberer_slot`
# inline pour chaque slot du lot, sans appel de fonction par mort. Le
# reveil des dormantes est UNIFIE avec celui des transitions : chaque
# mort append sa position dans `_reveils_positions_x/_z`, le reveil
# groupe qui suit les traite tous. `_liberer_slot` reste utilise par
# `_avancer_competition` (chemin de mort par competition).
# REPRODUCTION EN LOT : passe unique sur les vivants apres liberation
# des morts du tick. RNG STOCHASTIQUE (processus de Poisson par
# individu) CALEE SUR UN TOTAL DE GRAINES PAR VIE : `_intervalle_reprod[i]`
# est deduit a la naissance de la fenetre fertile ET du facteur de
# croissance individuel -- un arbre lent recoit un intervalle plus
# grand, ses graines s'espacent, TOTAL constant a `_graines_par_vie`
# pour tous. Cadence moyenne inchangee, instants desynchronises entre
# individus (fin des vagues de cohortes). Au plus une graine par pas
# et par arbre. Ordre RNG STRICTEMENT PRESERVE : meme sequence de
# `randf()` sur les memes slots dans le meme ordre d'indice qu'une
# boucle unitaire par arbre -- foret identique a seed egal.
func _reproduire_lot(pas: float) -> void:
	var cap: int = _capacite
	if cap == 0:
		return
	var i: int = 0
	while i < cap:
		if _libres[i] == 1:
			i += 1
			continue
		var age_i: float = _ages[i]
		if age_i >= _debut_fertilite and age_i < _fin_fertilite:
			var intervalle_i: float = _intervalle_reprod[i]
			if intervalle_i > 0.0 and not is_inf(intervalle_i):
				if _rng.randf() < pas / intervalle_i:
					# Tirage disque UNIFORME : angle uniforme + rayon = sqrt(u) * R.
					var angle: float = _rng.randf() * TAU
					var rayon: float = sqrt(_rng.randf()) * _rayon_graine
					_graines_lot_x.append(_positions_x[i] + cos(angle) * rayon)
					_graines_lot_z.append(_positions_z[i] + sin(angle) * rayon)
		i += 1

func _liberer_morts_vieillesse_lot() -> void:
	var n: int = _morts_vieillesse_lot.size()
	if n == 0:
		return
	var k: int = 0
	while k < n:
		var i: int = _morts_vieillesse_lot[k]
		k += 1
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
		# EVENEMENT DE VOISINAGE : la mort a retire densite et ombrage.
		# Empile la position pour le reveil groupe (identique a l'appel
		# `_reveiller_dormantes_autour` de la version unitaire, meme Set
		# `_reveils`, invariant a l'ordre).
		_reveils_positions_x.append(pos_x)
		_reveils_positions_z.append(pos_z)

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

# NAISSANCES EN LOT : draine `_naissances_lot_x/_z` (positions empilees
# par `_semer_lot` et `_tick_banque` -- les deux chemins deferent
# `_naitre` a cette passe unique). Cinq franchissements de frontiere
# par tick au total, quel que soit le nombre de naissances : alloc
# slots (banc) + `FacteurVariance.tirer_paires_entre_lot` +
# `_monde.ajouter_lot` + `_couvert.deposer_lot`. `Objet.fabriquer`
# est SKIPPE : `_stades_config_partagee` est cache au premier
# `_naitre` du `_ready`, initial age = 0.0 par contrat du banc.
# `_ecrire_slot` est SKIPPE : `_ecrire_slots_lot` en fin de tick
# ecrira les newborns depuis leurs colonnes (sentinelle INF au
# `_derniere_params` force le premier ecrit).
# ORDRE RNG STRICTEMENT PRESERVE : `tirer_paires_entre_lot` produit
# la meme sequence interleaved (croissance, longevite) que N appels
# unitaires alternes -- test hors domaine dans
# `scripts/test_facteur_variance.gd`.
func _naitre_lot() -> void:
	var n: int = _naissances_lot_x.size()
	if n == 0:
		return
	# Alloue N slots -- agrandit si necessaire.
	while _slots_libres.size() < n:
		_agrandir_capacite()
	var slots: PackedInt32Array = PackedInt32Array()
	slots.resize(n)
	var k: int = 0
	while k < n:
		slots[k] = _slots_libres.pop_back()
		k += 1
	# TIRAGE DE VARIANCE en UN appel interleaved (ordre RNG identique
	# a N appels unitaires alternes).
	var facteurs: Array = FacteurVariance.tirer_paires_entre_lot(
		_rng, n, _croissance_min, _croissance_max, _longevite_min, _longevite_max)
	var croissance_col: PackedFloat32Array = facteurs[0]
	var longevite_col: PackedFloat32Array = facteurs[1]
	# Prepare les entrees pour `_monde.ajouter_lot` et les colonnes de
	# depot d'ombrage. Age initial : 0.0 (contrat du banc). Stade
	# initial : `_index_pour_age(0.0)`, en general 0 (premier stade
	# franchi des la naissance).
	var stade_initial: int = _index_pour_age(0.0)
	var entries_monde: Array = []
	entries_monde.resize(n)
	var dep_x: PackedFloat32Array = PackedFloat32Array()
	var dep_z: PackedFloat32Array = PackedFloat32Array()
	var dep_r: PackedFloat32Array = PackedFloat32Array()
	var dep_m: PackedFloat32Array = PackedFloat32Array()
	var dep_s: PackedByteArray = PackedByteArray()
	# Reserves de conf_ombrage lues une seule fois si stade initial
	# valide et dans les bornes du catalogue.
	var stade_num: int = stade_initial + 1
	var conf_ombrage_ok: bool = stade_num >= 1 and stade_num <= _ombrage_par_stade.size()
	var rayon_naissance: float = 0.0
	var mag_naissance: float = 0.0
	if conf_ombrage_ok:
		var conf: Dictionary = _ombrage_par_stade[stade_num - 1]
		rayon_naissance = float(conf.get("rayon_ombre_m", 0.0))
		mag_naissance = float(conf.get("magnitude", 0.0))
	var denom_prefixe: float = _annees_par_seconde * _graines_par_vie
	k = 0
	while k < n:
		var slot: int = slots[k]
		var pos_x: float = _naissances_lot_x[k]
		var pos_z: float = _naissances_lot_z[k]
		_libres[slot] = 0
		_ages[slot] = 0.0
		_positions_x[slot] = pos_x
		_positions_z[slot] = pos_z
		_slot_stade[slot] = stade_initial
		_facteur_croissance[slot] = croissance_col[k]
		_facteur_longevite[slot] = longevite_col[k]
		# Intervalle effectif de reproduction : meme formule que
		# `_naitre` unitaire.
		var denom: float = denom_prefixe * croissance_col[k]
		if _fenetre_fertile_age > 0.0 and denom > 0.0:
			_intervalle_reprod[slot] = _fenetre_fertile_age / denom
		else:
			_intervalle_reprod[slot] = INF
		var position := Vector3(pos_x, Y_SOL, pos_z)
		var chose := {"id": "arbre_%d" % slot, "position": position, "slot": slot}
		_choses_arbre[slot] = chose
		entries_monde[k] = {"chose": chose, "type": "arbre"}
		if conf_ombrage_ok and mag_naissance != 0.0:
			dep_x.append(pos_x)
			dep_z.append(pos_z)
			dep_r.append(rayon_naissance)
			dep_m.append(mag_naissance)
			dep_s.append(1)  # signe +1
		_population += 1
		k += 1
	# UN appel groupe au monde.
	_monde.ajouter_lot(entries_monde)
	# UN appel groupe au champ pour tous les depots d'ombrage naissance.
	if dep_x.size() > 0:
		_couvert.deposer_lot(dep_x, dep_z, dep_r, _taille_case, dep_m, dep_s)

# Naissance UNITAIRE : conserve pour le `_naitre` initial de `_ready`
# (avant que `_stades_config_partagee` soit cache, obligatoire pour
# initialiser le cache) et pour tout autre chemin qui exigerait la
# fabrication complete via `Objet.fabriquer`.
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
	# Intervalle effectif de reproduction, deduit de la fenetre fertile
	# et du facteur de croissance individuel : un arbre lent
	# (facteur bas) est fertile plus longtemps EN TEMPS REEL, son
	# intervalle est proportionnellement plus grand -- total de
	# graines par vie = `_graines_par_vie` pour tous. INF si l'un des
	# denominateurs est nul (pas de reproduction).
	var denom: float = _annees_par_seconde * _facteur_croissance[i] * _graines_par_vie
	if _fenetre_fertile_age > 0.0 and denom > 0.0:
		_intervalle_reprod[i] = _fenetre_fertile_age / denom
	else:
		_intervalle_reprod[i] = INF
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

# GATE DE TROUEE PAR REQUETE PONCTUELLE (patron
# vegetation.gd:trouee_suffisante). Appele par `_tick_banque` (une
# graine reveillee = une requete ciblee a SA position avec `rayon_gros`).
# La germination directe (semis d'un lot depuis `_process`) passe par
# `_trouee_saturee_lot` sur une requete GROUPEE, avec le meme predicat
# -- les deux chemins gardent des resultats identiques. Les nouveau-nes
# eventuels de la rafale sont deja dans `_monde` au moment ou
# `_tick_banque` s'execute (le lot est draine avant), la lecture reste
# coherente.
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

# GATE DE TROUEE VERSION LOT : les voisins existants sont pre-calcules
# par la requete groupee `_monde.choses_dans_rayons` (UNE frontiere
# franchie pour tout le lot), les nouveau-nes de la rafale sont scannes
# lineairement dans `_naissances_lot_x/_z` (petite liste, filtre AABB
# implicite via `carre_normal`). Meme predicat que `_trouee_saturee`,
# meme resultat -- l'union des deux listes reproduit la vue de
# `_monde.choses_dans_rayon` prise apres les naissances precedentes.
func _trouee_saturee_lot(pos_x: float, pos_z: float, voisins: Array, carre_normal: float) -> bool:
	var arrivee := Vector3(pos_x, Y_SOL, pos_z)
	var compte_normal: int = 0
	for entree in voisins:
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
	# Nouveau-nes du meme lot : tous au stade 0 (jamais adultes), ne
	# peuvent qu'incrementer `compte_normal`.
	var m: int = _naissances_lot_x.size()
	var j: int = 0
	while j < m:
		var dx: float = _naissances_lot_x[j] - pos_x
		var dz: float = _naissances_lot_z[j] - pos_z
		if dx * dx + dz * dz <= carre_normal:
			compte_normal += 1
		j += 1
	return compte_normal > _trouee_max_voisins

# TRAITEMENT DU LOT DE GRAINES en UNE passe par tick. Appele une fois
# depuis `_process` apres la boucle des arbres. Draine
# `_graines_lot_x/_z` (position XZ empilee inline dans la boucle des
# arbres, ordre RNG preserve). UN SEUL appel a
# `_monde.choses_dans_rayons` pour tout le lot au lieu d'une requete par
# graine. Les nouveau-nes de la rafale sont tenus dans
# `_naissances_lot_x/_z` et scannes lineairement au traitement de chaque
# candidat suivant, pour que le gate de trouee morde comme avant (patron
# `nouvelles` de `vegetation.gd`, sans dict temporaire).
func _semer_lot() -> void:
	var n: int = _graines_lot_x.size()
	if n == 0:
		return
	var rayon_gros: float = _rayon_trouee * _facteur_trouee_gros
	var carre_normal: float = _rayon_trouee * _rayon_trouee
	# Positions Vector3 pour la requete groupee. Reconstruit chaque tick
	# (contenu de longueur variable, aucun regime stable a maintenir).
	var positions_vec3: Array = []
	positions_vec3.resize(n)
	var k: int = 0
	while k < n:
		positions_vec3[k] = Vector3(_graines_lot_x[k], Y_SOL, _graines_lot_z[k])
		k += 1
	var voisins_par_graine: Array = _monde.choses_dans_rayons(positions_vec3, rayon_gros)
	_naissances_lot_x.resize(0)
	_naissances_lot_z.resize(0)
	k = 0
	while k < n:
		var pos_x: float = _graines_lot_x[k]
		var pos_z: float = _graines_lot_z[k]
		var voisins: Array = voisins_par_graine[k]
		k += 1
		# Graine hors carte : perdue. Ne germe pas, n'entre pas en banque.
		if absf(pos_x) > _demi_carte or absf(pos_z) > _demi_carte:
			continue
		# Rejet trouee sur germination directe = graine perdue (pas de banque :
		# la banque attend que le COUVERT baisse, pas que la densite physique
		# se degage).
		if _trouee_saturee_lot(pos_x, pos_z, voisins, carre_normal):
			continue
		if _lire_couvert(pos_x, pos_z) < _seuil_couvert:
			# NAISSANCE DEFEREE au `_naitre_lot` de fin de tick : append
			# la position au meme lot que la scan du gate suivant lit
			# (`_trouee_saturee_lot` scanne `_naissances_lot_x/_z` en
			# plus du batch monde), pour que les graines suivantes
			# comptent ce nouveau-ne dans leur voisinage.
			_naissances_lot_x.append(pos_x)
			_naissances_lot_z.append(pos_z)
			continue
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
			# Echeance de mort : temps banque courant + duree de vie.
			# Duree fixe -> ordre d'insertion = ordre d'expiration,
			# append en queue suffit (aucun tri).
			_expirations.append([_temps_banque + _duree_vie_graine, id_prospect])

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
func _tick_banque(pas: float) -> void:
	# CHRONOS TEMPORAIRES : voir declaration des _chrono_us_* / _chrono_n_*.
	# La logique du gate est INLINE ici (dupliquee de `_trouee_saturee`)
	# pour isoler QUERY et GATE en postes distincts. A retirer une fois
	# le poste dominant identifie -- rebranchement sur `_trouee_saturee`.
	var t_total: int = Time.get_ticks_usec()
	# POSTE 5 : EXPIRATION (mort des dormantes de vieillesse). Avance
	# _temps_banque puis draine les entrees dont l'echeance est atteinte.
	# Independant de _reveils.is_empty() -- une graine peut expirer meme
	# si aucun evenement de reveil ne survient ce tick.
	_temps_banque += pas
	var t_exp: int = Time.get_ticks_usec()
	_drainer_expirations()
	_chrono_us_expiration += Time.get_ticks_usec() - t_exp
	_chrono_n_expiration += 1
	if _reveils.is_empty():
		_chrono_us_total += Time.get_ticks_usec() - t_total
		_chrono_n_ticks += 1
		return
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
		# POSTE 3 : GATE (delegue a `_trouee_saturee_lot` qui scanne
		# aussi les pending `_naissances_lot_x/_z` -- les prospects
		# germines plus tot dans le meme tick comptent dans le gate).
		var t2: int = Time.get_ticks_usec()
		var trouee_ko: bool = _trouee_saturee_lot(pos.x, pos.z, voisins, carre_normal)
		var couvert_ko: bool = false
		if not trouee_ko:
			couvert_ko = _lire_couvert(pos.x, pos.z) >= _seuil_couvert
		_chrono_us_gate += Time.get_ticks_usec() - t2
		_chrono_n_gate += 1
		if trouee_ko or couvert_ko:
			continue
		# POSTE 4 : NAISSANCE DEFEREE au `_naitre_lot` de fin de tick.
		# La sortie de banque (banque_graines.retirer + retirer_dormante)
		# reste immediate -- une graine qui passe le gate n'est plus
		# dormante des maintenant, meme si sa naissance materielle est
		# groupee.
		var t3: int = Time.get_ticks_usec()
		_banque_graines.retirer(id)
		_retirer_dormante(id)
		_naissances_lot_x.append(pos.x)
		_naissances_lot_z.append(pos.z)
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

# REVEIL EN LOT : boucle interne unique sur les positions collectees
# pendant la passe de transition. `_reveils` etant un Set d'ids, l'ordre
# de traitement des positions n'affecte pas le contenu final. Meme
# resultat qu'un appel a `_reveiller_dormantes_autour` par position, un
# seul appel de fonction du banc au lieu de N. Les invariants de la
# version unitaire (gates sur `_banque_graines == null`, `_rayon_reveil`,
# `_dormantes_par_case` vide) sont evalues UNE fois avant la boucle.
func _reveiller_dormantes_autour_lot(positions_x: PackedFloat32Array, positions_z: PackedFloat32Array) -> void:
	var n: int = positions_x.size()
	if n == 0:
		return
	if _banque_graines == null or _rayon_reveil <= 0.0 or _taille_case_dormantes <= 0.0:
		return
	if _dormantes_par_case.is_empty():
		return
	var inv_case: float = 1.0 / _taille_case_dormantes
	var carre: float = _rayon_reveil * _rayon_reveil
	var prospects: Dictionary = _banque_graines.prospects()
	var k: int = 0
	while k < n:
		var pos_x: float = positions_x[k]
		var pos_z: float = positions_z[k]
		k += 1
		var cx_min: int = floori((pos_x - _rayon_reveil) * inv_case)
		var cx_max: int = floori((pos_x + _rayon_reveil) * inv_case)
		var cz_min: int = floori((pos_z - _rayon_reveil) * inv_case)
		var cz_max: int = floori((pos_z + _rayon_reveil) * inv_case)
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

# Inscrit une graine dormante dans la grille spatiale (a `_semer_lot`
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

# DRAIN DE LA FILE D'ECHEANCES DE MORT : depuis la tete
# (`_expirations_head`), depile tant que l'echeance est atteinte
# (echeance <= _temps_banque). Pour chaque id depile, si la graine
# est encore prospect (pas encore levee), la retire de la banque et
# de la grille sans naitre. Une graine levee entre-temps n'est plus
# prospect -> discard silencieux (lazy). Rebuild (`slice`) declenche
# rarement quand le head grossit trop, pour ne pas laisser l'Array
# croitre indefiniment.
func _drainer_expirations() -> void:
	if _banque_graines == null:
		return
	var prospects: Dictionary = _banque_graines.prospects()
	while _expirations_head < _expirations.size():
		var entry: Array = _expirations[_expirations_head]
		if float(entry[0]) > _temps_banque:
			break
		_expirations_head += 1
		var id: int = int(entry[1])
		if prospects.has(id):
			_banque_graines.retirer(id)
			_retirer_dormante(id)
	# Trim rare pour eviter que l'Array grossisse sans borne. Slice
	# alloue une copie mais le cout est amorti sur >1024 drains.
	if _expirations_head > 1024 and _expirations_head > (_expirations.size() >> 1):
		_expirations = _expirations.slice(_expirations_head)
		_expirations_head = 0

# Rayon d'influence d'un evenement (mort, changement de stade) sur les
# graines dormantes : max du rayon trouee elargi (voisin adulte)
# et de la portee maximale d'ombrage. Une graine plus loin que ce rayon
# ne peut voir NI son gate trouee ni son gate couvert change par
# l'evenement. Sur-estimation OK (surface d'ombrage est en cases
# Chebyshev, convertie en unites monde avec un pas de securite).
func _calculer_rayon_reveil() -> void:
	var rayon_gros: float = _rayon_trouee * _facteur_trouee_gros
	# Portee d'ombrage lue directement en METRES depuis `ombrage_par_stade`
	# -- independante de `_taille_case`.
	var max_rayon_ombre_m: float = 0.0
	for entree in _ombrage_par_stade:
		if entree is Dictionary:
			max_rayon_ombre_m = maxf(max_rayon_ombre_m, float(entree.get("rayon_ombre_m", 0.0)))
	# Une case de securite (Chebyshev) pour couvrir un seed a l'oppose de
	# son centre de case et un arbre a l'oppose du sien ; diagonale plane
	# sqrt(2). La case de securite reste indexee sur `_taille_case` (elle
	# borne le decalage sub-case, pas la portee physique).
	var portee_ombrage: float = (max_rayon_ombre_m + _taille_case) * sqrt(2.0)
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
	_intervalle_reprod.resize(nouvelle)
	_choses_arbre.resize(nouvelle)
	_derniere_params.resize(nouvelle)
	_derniere_couleur_stade.resize(nouvelle)
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
		_intervalle_reprod[i] = INF
		_choses_arbre[i] = null
		_derniere_params[i] = Vector4(INF, INF, INF, INF)
		_derniere_couleur_stade[i] = -1
		_slots_libres.append(i)
		_ecrire_slot_vide(i)
		i -= 1
	# Reecriture des slots preexistants dont le buffer GPU vient d'etre
	# reinitialise par le changement d'instance_count ci-dessus. Les caches
	# `_derniere_params` ET `_derniere_couleur_stade` doivent etre INVALIDES
	# pour chaque slot vivant, sinon `_ecrire_slot` skippe l'ecrit croyant
	# que rien n'a bouge -- alors que le buffer GPU (transforms ET couleurs)
	# vient d'etre efface.
	var j: int = 0
	while j < ancienne:
		if _libres[j] == 1:
			_ecrire_slot_vide(j)
		else:
			_derniere_params[j] = Vector4(INF, INF, INF, INF)
			_derniere_couleur_stade[j] = -1
			_ecrire_slot(j, _ages[j])
		j += 1

# Passe rare d'auto-eclaircie. Ne tourne QU'a la cadence lente
# `_cadence_competition` (pas dans la boucle 60 fps). PASSE ETALEE EN
# ANNEAU : au lieu d'un balayage complet toutes les
# `_cadence_competition` secondes (pic de ~13 ms mesure), chaque passe
# de sim visite `n_slots = ceil(capacite * pas / _cadence_competition)`
# slots depuis `_curseur_competition`. Sur une periode de
# `_cadence_competition` cumulee, la somme visite `_capacite` slots =
# chaque slot exactement une fois en moyenne, sans jamais concentrer
# le cout sur une frame.
#
# Seuls les vulnerables (stade + 1 <= _stade_competition_max) sont
# testes -- les adultes dominent.
#
# REQUETE GROUPEE : la mesure du voisinage passe par UN SEUL appel a
# `_monde.choses_dans_rayons` sur toutes les positions eligibles, au
# lieu d'un `choses_dans_rayon` par slot. L'ordre des tirages de
# mortalite RNG reste celui de l'anneau (foret identique a seed egal).
# EFFET DE BORD PRESERVE : la version unitaire retirait la mort au fil,
# donc un slot teste plus tard voyait un voisin de moins si son voisin
# venait de mourir. Ici la requete groupee est prise AVANT toute mort
# du tick ; on reproduit le meme compte NET en soustrayant, pour chaque
# slot testé, les morts precedentes du meme tick presentes dans son
# batch de voisins (`_competition_morts_du_tick` : Set d'`id` de choses
# retirees ce tick). Coherent avec le rayon petit (_rayon_competition ~
# 3 m) qui rend l'effet rare mais preserve.
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
	# Premiere passe : collecte des eligibles en ordre d'anneau.
	_competition_positions.clear()
	_competition_slots.resize(0)
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
		_competition_positions.append(Vector3(_positions_x[i], Y_SOL, _positions_z[i]))
		_competition_slots.append(i)
	if _competition_positions.is_empty():
		return
	# Requete groupee : UN seul franchissement de frontiere.
	var voisins_par_slot: Array = _monde.choses_dans_rayons(_competition_positions, _rayon_competition)
	# Deuxieme passe : mortalite en ordre d'anneau. Soustraction des morts
	# precedentes du tick pour reproduire l'effet de bord de la version
	# unitaire (une mort retire son id de `_monde` au fil, un slot teste
	# plus tard voit un voisin de moins).
	var morts_du_tick: Dictionary = {}
	var k: int = 0
	var m: int = _competition_slots.size()
	while k < m:
		var slot: int = _competition_slots[k]
		var voisins_list: Array = voisins_par_slot[k]
		var voisins: int = voisins_list.size()
		if not morts_du_tick.is_empty():
			for entree in voisins_list:
				if morts_du_tick.has(entree.chose.id):
					voisins -= 1
		k += 1
		if voisins > _competition_max_voisins:
			var exces: int = voisins - _competition_max_voisins
			var proba: float = clampf(
				float(exces) / float(maxi(1, _competition_max_voisins)), 0.0, 1.0)
			if _rng.randf() < proba:
				var chose = _choses_arbre[slot]
				if chose != null:
					morts_du_tick[chose.id] = true
				_liberer_slot(slot)
