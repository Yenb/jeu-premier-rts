# SIMULATION ARBRE (module RefCounted).
#
# ORCHESTRATEUR de la population d'arbres. Un SEUL appel public par tick :
# `avancer(pas)`. Vu de l'exterieur : un appel, une boucle, tout ce dont
# l'arbre a besoin. La coquille `jeu/bancs/banc_peuplement_arbre.gd` tient
# la scene (sol, MultiMesh, joueur, camera) et la cadence -- elle instancie
# ce module au `_ready`, lui INJECTE toutes les refs (MultiMesh, monde,
# couvert, banque, carte de terrain) et toute la config figee, puis
# delegue chaque tick a `avancer(pas)`.
#
# Ce module tient : les colonnes de la population, les structures de
# travail par-tick, la config figee, le RNG, les refs coeur (`_monde`,
# `_couvert`, `_banque_graines`, `_mm_tronc`, `_mm_feuillage`,
# `carte_terrain_ref`). Il est le SEUL a appeler `monde.gd` et
# `champ_saturation_plat.gd` pour l'arbre. Aucune ligne de logique de sim
# ne vit dans la coquille. Aucune ligne de scene ne vit ici (RefCounted,
# jamais dans la scene tree, aucun `get_node`).
#
# Population d'arbres statiques qui pousse et se reproduit librement. Le
# module est un CABLAGE : la logique passe par les mecanismes du coeur
# (`scripts/objet.gd:fabriquer`, `scripts/senescence.gd:avancer`,
# `scripts/stade.gd:avancer`), le module n'invente ni age, ni seuil de
# stade, ni construction d'arbre. Le stockage de masse reste en colonnes
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
# CATALOGUE `stades_config` LOCAL : `_stades_config_partagee` est
# construit une fois au `_ready` (`_construire_stades_config`) comme
# suite de seuils cumules a partir de `_durees`. Reference unique
# partagee entre toutes les instances : chaque `_naitre_lot` en
# reutilise la meme ref (contrat "paquets_partages" applique sans
# passer par une machinerie de composition). Le framework ne porte
# aucun `stades_config` sur son type `arbre`, ce banc porte le sien.
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
# l'entree en banque ; `_reveiller_dormantes_autour_lot` la passe a true
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
# stade (`_deposer_ombrage`), les graines y LISENT EN LOT via `_couvert.lire_lot`.
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

extends RefCounted

const Objet = preload("res://scripts/objet.gd")
const FacteurVariance = preload("res://scripts/facteur_variance.gd")

# Hauteur du sol visuel monte par _monter_scene. La base des troncs y est posee.
const Y_SOL := 12.0

# MODE HOTE : le banc tourne dans une scene qui apporte deja son sol, sa
# lumiere, sa camera, son joueur (par exemple `jeu/Proto/verification.tscn`).
# `hote_actif = true` : `_ready` SAUTE `_monter_scene` et `_monter_joueur`,
# derive `_demi_carte` de `carte_terrain_ref.metres()` (surcharge le JSON),
# lit la hauteur du sol reel via `carte_terrain_ref.sommet(x, z)` a la
# naissance de chaque arbre (colonne `_positions_y`, morceau 2 -- pas
# encore branche a ce commit). Le monde data (`_monde`) continue de
# stocker `y = Y_SOL` constant : distance XZ preservee, gate/banque/
# reveils bit-a-bit identiques au mode isole. Seul le RENDU change.
# Doctrine CLAUDE.md « Les donnees sont la verite, la physique est un
# rendu » : le monde ne connait pas le relief, le rendu si.
# `hote_actif = false` (defaut) : mode banc isole, sol plat a Y_SOL,
# _monter_scene et _monter_joueur montent leur propre decor -- comportement
# STRICTEMENT inchange du banc historique.
# INJECTES par la coquille via `installer(...)`. `hote_actif = true`
# : la coquille est montee dans une scene hote (ex. verification.tscn)
# qui fournit sol/lumiere/camera/joueur ; la sim lit alors la hauteur du
# sol reel via `carte_terrain_ref.sommet(x, z)` a chaque naissance.
# `hote_actif = false` (defaut) : mode banc isole, `_positions_y[i] = Y_SOL`
# constant.
var hote_actif: bool = false
# Ressource carte_terrain injectee par la scene hote en mode hote (par
# exemple `res://jeu/Proto/proto_carte.tres`). Doit exposer `sommet(x, z)`
# (Y du sol en unites monde) et `metres()` (etendue en unites monde).
# `null` en mode isole (jamais lu).
var carte_terrain_ref: Resource = null

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
# EXCLUSION STRICTE DE SUPERPOSITION : toute naissance dont un voisin
# (monde OU `_naissances_lot`) est a distance XZ strictement inferieure
# a `_rayon_exclusion` est rejetee d'office, quel que soit le compte
# `_trouee_max_voisins`. Empeche deux graines tombees au meme point
# (ou tres proches) de passer toutes deux le gate. Sans ca, avec
# `_trouee_max_voisins=1`, deux graines coincidentes donnent compte=1
# > 1 faux -> les deux naissent superposees.
var _rayon_exclusion: float = 1.5

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

var _capacite: int = 0
var _ages: PackedFloat32Array = PackedFloat32Array()
var _libres: PackedByteArray = PackedByteArray()
var _positions_x: PackedFloat32Array = PackedFloat32Array()
var _positions_z: PackedFloat32Array = PackedFloat32Array()
# Hauteur Y du sol pour le rendu de chaque slot. Colonne par slot,
# posee a la naissance. Mode isole (`hote_actif = false`) : toujours
# Y_SOL, meme rendu qu'avant. Mode hote : `carte_terrain_ref.sommet(x,z)`
# lu a la naissance, jamais recalcule au rendu (les arbres ne bougent
# pas ; la hauteur du sol sous un arbre reste stable dans la vie du
# slot). Le monde data (`_monde`) continue de stocker `y = Y_SOL` --
# distance XZ preservee, gate/banque/reveils bit-a-bit identiques dans
# les deux modes. Doctrine CLAUDE.md « Les donnees sont la verite, la
# physique est un rendu ».
var _positions_y: PackedFloat32Array = PackedFloat32Array()
var _slots_libres: Array = []

# ---- SEPARATION SLOT DATA / SLOT RENDU (streaming, morceau 1/3) ----
#
# Slot DATA (index dans les colonnes ci-dessus, borne par la population
# totale) vs slot RENDU (index MultiMesh, borne par la fenetre autour de
# l'observateur en mode hote streame). Aujourd'hui (morceau 1), IDENTITY
# mapping : chaque naissance alloue en parallele un slot data et un slot
# rendu au meme index -- comportement bit-a-bit inchange. Les morceaux
# 2/3 romperont l'identity : mapping dynamique quand un arbre entre/sort
# du cercle autour de l'observateur, capacite MultiMesh bornee par le
# cercle et non par la population totale. Le rendu ecrit deja avec un
# index qui pourra alors etre lu depuis `_slot_rendu_pour_data[i]` sans
# toucher aux fonctions d'ecriture (transparence de l'indirection).
#
# Mode isole (`hote_actif = false`) : identity mapping toujours,
# `_capacite_rendu = _capacite`, ordre d'allocation identique aux
# `_slots_libres` -> `_slot_rendu_pour_data[i] = i`.
var _capacite_rendu: int = 0
# Slot data i -> slot rendu (index MultiMesh), -1 si l'arbre data n'est
# pas rendu (sortie du cercle en mode hote streame). En morceau 1,
# identity : posee a `i` a la naissance, -1 a la mort.
var _slot_rendu_pour_data: PackedInt32Array = PackedInt32Array()
# Inverse : slot rendu j -> slot data, -1 si le slot rendu est libre.
# Sert au morceau 2 pour effacer visuellement un arbre sorti du cercle.
var _data_pour_slot_rendu: PackedInt32Array = PackedInt32Array()
# Pile des slots rendu libres, memes conventions que `_slots_libres`
# (init ordre inverse, pop_back rend le plus petit index d'abord). En
# morceau 1, allocation en parallele des slots data -> identity.
var _slots_rendu_libres: Array = []

# ZONES D'EXCLUSION (patron `jeu/plantes/zone_exclusion_arbre.gd`) :
# des noeuds cercle/carre poses en editeur dans la scene hote, ajoutes
# au groupe `&"exclusion_arbre"`. Lus UNE fois au `_ready` en mode
# hote, copies en data legere ici -- aucune reference vivante au noeud
# dans le hot path, aucun test tree pendant le tick. Chaque entree :
# { forme: int (0=cercle, 1=carre), cx: float, cz: float, rayon: float,
# demi_x: float, demi_z: float }. Mode isole : liste vide, aucun effet.
# Cout par graine = O(N_zones) lineaire ; adapte a une poignee de zones
# (< 10). Pour beaucoup de zones, prevoir une indexation spatiale.
var _zones_exclusion: Array = []
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

# Population vivante courante, tenue en O(1) : incrementee dans
# _naitre_lot, decrementee dans _liberer_slots_lot. Aucun scan par frame.
var _population: int = 0
var _frames_depuis_releve: int = 0

# CHRONO TEMPORAIRE du dernier tick en microsecondes. Rempli en fin de
# `avancer(pas)` (Time.get_ticks_usec() aux bornes de la fonction, jamais
# par arbre -- un now() par arbre fausserait la mesure), imprime sous le
# meme gate que le releve population. Un seul poste « tick » a cette
# etape ; le decoupage en sous-postes (senescence/stade/repro/banque/
# couvert/competition/rendu) est une etape suivante. A RETIRER une fois
# la mesure prise et le portage C++ verifie. Patron collision_lot.h
# « CHRONOS TEMPORAIRES par appel ».
var _chrono_dernier_tick_us: int = 0

# SOUS-CHRONOS TEMPORAIRES par POSTE, cumules sur la fenetre de releve
# (remis a 0 apres chaque print). Ecart : cumul plutot que « dernier tick »
# pour lisser le bruit inter-tick et voir OU le tick passe son temps.
# Postes disjoints qui couvrent tout le corps de avancer(pas) sans trou :
#   us_boucle    : boucle unique (senescence + stade + detection + mort +
#                  reproduction inline) OU passe_1_cpp + passe_reproduction
#                  quand utilise_cpp = true.
#   us_morts_v   : drainage `_liberer_morts_vieillesse_lot` inline.
#   us_reveils   : reveil des dormantes en lot inline.
#   us_transitions : redepot des transitions dans _couvert (deposer_lot elargi).
#   us_semis     : `_semer_lot` inline.
#   us_banque    : `_tick_banque` inline (drain expirations + reveils).
#   us_naitre    : `_naitre_lot` inline.
#   us_competition : `_avancer_competition` inline.
#   us_rendu     : `_ecrire_slots_lot` inline.
#   us_deverse   : monde.retirer_lot + couvert.deposer_lot finaux.
# Total attendu : somme des 10 ~= _chrono_dernier_tick_us cumule sur la
# fenetre (aux 10-20 us de now() eux-memes pres). Patron chronos
# collision_lot.h -- TEMPORAIRE, a retirer une fois le poste dominant
# identifie et porte C++.
var _us_boucle: int = 0
var _us_morts_v: int = 0
var _us_reveils: int = 0
var _us_semis: int = 0
var _us_banque: int = 0
var _us_naitre: int = 0
var _us_competition: int = 0
var _us_rendu: int = 0
var _us_deverse: int = 0
var _us_tick_cumul: int = 0
# Poste `transitions` : le drainage W1 fusionne reveils + transitions
# dans un unique bloc de code, sans separation nette. Comptabilise en
# entier dans `_us_reveils` (voir bornage). Membre absent volontairement.

# BASCULE C++ (etape 2 du portage). `utilise_cpp = true` remplace la boucle
# unique (senescence + stade + detection + mort vieillesse) par un appel a
# `extension_terrain::SimulationArbre::avancer_passe_1(...)`. La
# reproduction stochastique (RNG) reste GDScript. Instancie a la demande
# via `configurer_cpp()` : si l'extension n'est pas chargee, le drapeau
# reste false et l'oracle GDScript est utilise sans interruption. Aucun
# etat entre appels : la classe C++ ne stocke que les STABLES (poussees
# une fois par `_pousser_stables_cpp`), les colonnes mutables voyagent
# par frontiere a chaque tick.
var utilise_cpp: bool = false
var _simu_cpp: RefCounted = null
# Drapeau : true = les colonnes stables (aps, durees, seuils, ombrage, bornes
# adulte) ont deja ete poussees au C++ pour ce banc. Remis a false a chaque
# `configurer_cpp(true)` (nouvelle instance).
var _cpp_stable_pousse: bool = false

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
# testent qu'une fois). Rempli par `_reveiller_dormantes_autour_lot`
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
# boucle. Reutilisee tick apres tick. Le comportement de liberation est
# reproduit inline dans `_liberer_slots_lot` : retrait monde (groupe),
# retrait ombrage (groupe), reveil (groupe), reset colonnes, libre +
# slot_libres + `_ecrire_slot_vide`, decrement `_population`.
var _morts_vieillesse_lot: PackedInt32Array = PackedInt32Array()

# GRILLE SPATIALE PROPRE A LA BANQUE (patron LOCALITE SPATIALE du
# CLAUDE.md, variante monde-indexe adaptee aux ids stables). Cle =
# Vector2i (case du plan XZ, cote `_taille_case_dormantes`), valeur =
# Array<int> des ids de prospects dormants dans cette case. Insertion a
# `_semer_lot`, retrait quand une graine leve (`_tick_banque`).
# `_reveiller_dormantes_autour_lot` ne lit QUE les cases dans le rectangle
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


# API PUBLIQUE, appelee par la coquille au `_ready` :
# `configurer(donnees)` reçoit le Dictionary du JSON du banc, remplit
# TOUTES les vars de config figee, calcule `_rayon_reveil`, seede le RNG.
func configurer(donnees: Dictionary) -> void:
	_charger_reglages_locaux(donnees)
	_calculer_rayon_reveil()
	_rng.seed = _graine_rng

# API PUBLIQUE. `attacher(...)` injecte les refs coeur + MultiMesh puis
# initialise les colonnes (`_monter_population_init`). Le catalogue combine
# ({dynamique + type local arbre_pousse}) est construit ici pour que
# `_naitre` (initial) trouve `_catalogue`.
func attacher(mm_tronc: MultiMesh, mm_feuillage: MultiMesh, monde: RefCounted, couvert: RefCounted, banque: RefCounted, hote_actif_val: bool, carte_ref: Resource, types_dynamique: Variant) -> void:
	_mm_tronc = mm_tronc
	_mm_feuillage = mm_feuillage
	_monde = monde
	_couvert = couvert
	_banque_graines = banque
	hote_actif = hote_actif_val
	carte_terrain_ref = carte_ref
	_construire_catalogue(types_dynamique)
	_monter_population_init()

# API PUBLIQUE. Passe des zones d'exclusion collectees par la coquille
# (deferre dans son `_ready` en mode hote). Aucune reference vivante aux
# noeuds retenue -- data legere.
func definir_zones_exclusion(zones: Array) -> void:
	_zones_exclusion = zones

# API PUBLIQUE. Plante l'arbre initial (equivalent de l'ancien
# `_naitre(global_position.x, global_position.z)` au `_ready`).
func naitre_initial(pos_x: float, pos_z: float) -> void:
	if _stades.size() == 9:
		_naitre(pos_x, pos_z)

# Getters exposes a la coquille (cadence, scene, decision de montage).
func demi_carte() -> float: return _demi_carte
func joueur_actif() -> bool: return _joueur_actif
func cadence_simulation_hz() -> float: return _cadence_simulation_hz
func mode_test_rapide() -> bool: return _mode_test_rapide
func graine_rng() -> int: return _graine_rng
func stades_ok() -> bool: return _stades.size() == 9 and _durees.size() == 8

# Population vivante courante (nombre d'arbres non-libres). Sert au
# releve imprime et aux instruments de mesure externes (banc de mesure,
# test de parite futur C++).
func population() -> int: return _population

# CHRONO TEMPORAIRE : cout du dernier tick en microsecondes, expose au
# meme titre que `collision_lot.h::derniers_chronos()`. Un seul poste
# « tick » a cette etape. A RETIRER avec le reste de l'instrumentation.
func derniers_chronos() -> Dictionary:
	return {"tick": _chrono_dernier_tick_us}

# BASCULE C++ (etape 2 du portage). Active/desactive la voie C++ pour la
# passe 1 (senescence + stade + detection + mort vieillesse). `actif=true`
# instancie SimulationArbre C++ via ClassDB si l'extension est chargee ;
# sinon un push_warning est emis et le drapeau reste false (l'appelant
# n'a pas a s'inquieter du chargement). `actif=false` remet le chemin
# oracle sans liberer l'instance (le RefCounted C++ vit jusqu'a la
# prochaine bascule ou la mort de la sim). Patron `deplacer_cpp` de
# banc_peuplement.gd.
func configurer_cpp(actif: bool) -> void:
	if actif and _simu_cpp == null:
		if not ClassDB.class_exists("SimulationArbre"):
			push_warning("simulation_arbre : SimulationArbre C++ absente, bascule ignoree")
			utilise_cpp = false
			return
		_simu_cpp = ClassDB.instantiate("SimulationArbre")
		_cpp_stable_pousse = false
	utilise_cpp = actif
	# ETAPE 6 : partager le RNG. Sous bascule, `_rng` GDScript pointe le
	# _simu_cpp._rng -- TOUS les tirages (repro C++ + variance naissance
	# GDScript + competition GDScript) passent par LE MEME PCG32. Sans ce
	# partage, la reproduction C++ desynchroniserait la suite de tirages
	# GDScript restants et casserait la parite.
	if actif and _simu_cpp != null:
		_rng = _simu_cpp.obtenir_rng()
		_rng.seed = _graine_rng

func _charger_reglages_locaux(donnees: Dictionary) -> void:
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
	if donnees.has("rayon_exclusion"):
		_rayon_exclusion = float(donnees.rayon_exclusion)
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
	# via `_facteur_croissance[i]` -- voir `_naitre_lot`.
	_fenetre_fertile_age = maxf(0.0, _fin_fertilite - _debut_fertilite)

# Construit la table passee a Objet.fabriquer : paquet `dynamique` du
# framework (fourni par la coquille) + type local `arbre_pousse`. La
# coquille a lu `data/types.json` et extrait le paquet `dynamique` ;
# ce module ne relit pas le disque.
func _construire_catalogue(types_dynamique: Variant) -> void:
	if types_dynamique == null:
		push_error("simulation_arbre : paquet `dynamique` non fourni par la coquille")
		return
	_catalogue = {}
	_catalogue["dynamique"] = types_dynamique
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

# INIT DES COLONNES A LA CAPACITE INITIALE. Appelee par `attacher(...)` :
# les MultiMesh sont deja crees, dimensionnes et attaches par la coquille ;
# ce module ne monte aucun noeud. Ordre d'insertion des slots libres et
# ordre des `_ecrire_slot_vide` STRICTEMENT identiques a l'ancien
# `_monter_population` -- migration bit-a-bit.
func _monter_population_init() -> void:
	_capacite = CAPACITE_INITIALE
	_capacite_rendu = CAPACITE_INITIALE
	_ages.resize(_capacite)
	_libres.resize(_capacite)
	_positions_x.resize(_capacite)
	_positions_z.resize(_capacite)
	_positions_y.resize(_capacite)
	_slot_rendu_pour_data.resize(_capacite)
	_data_pour_slot_rendu.resize(_capacite_rendu)
	_slot_stade.resize(_capacite)
	_facteur_croissance.resize(_capacite)
	_facteur_longevite.resize(_capacite)
	_intervalle_reprod.resize(_capacite)
	_choses_arbre.resize(_capacite)
	_derniere_params.resize(_capacite)
	_derniere_couleur_stade.resize(_capacite)
	_slots_libres.clear()
	_slots_rendu_libres.clear()
	# Ordre inverse : pop_back rendra les slots dans l'ordre croissant.
	var i: int = _capacite - 1
	while i >= 0:
		_libres[i] = 1
		_ages[i] = 0.0
		_positions_x[i] = 0.0
		_positions_z[i] = 0.0
		_positions_y[i] = Y_SOL
		_slot_stade[i] = -1
		_facteur_croissance[i] = 1.0
		_facteur_longevite[i] = 1.0
		_intervalle_reprod[i] = INF
		_choses_arbre[i] = null
		_derniere_params[i] = Vector4(INF, INF, INF, INF)
		_derniere_couleur_stade[i] = -1
		_slot_rendu_pour_data[i] = -1
		_data_pour_slot_rendu[i] = -1
		_slots_libres.append(i)
		_slots_rendu_libres.append(i)
		_ecrire_slot_vide(i)
		i -= 1

# API PUBLIQUE. Fait avancer la foret d'UN pas de simulation. UNIQUE
# point d'entree du tick, appele par la coquille depuis `_process` apres
# la gate de cadence. `avancer(pas)` enferme TOUTE la sequence : vidage
# des lots, boucle unique par slot vivant (senescence + stade + detection
# transition + mort-vieillesse + reproduction), puis la chaine d'effets
# groupes dans son ordre actuel (mort vieillesse -> reveil -> redepot
# transition -> semis -> banque -> naissances -> competition -> rendu).
# L'ordre des effets n'est PAS modifie : chaque effet reste un seul
# appel groupe, une seule fois par tick. Les seuls franchissements de
# frontiere (vers `_monde` et `_couvert`) subsistent en interne, jamais
# vus par la coquille.
func avancer(pas: float) -> void:
	if _stades.size() != 9 or _durees.size() != 8 or _stades_config_partagee.is_empty():
		return
	# CHRONO TEMPORAIRE du tick complet. Borne haute : dernier appel avant
	# la sortie de la fonction. Voir `_chrono_dernier_tick_us`. A RETIRER
	# avec le reste de l'instrumentation.
	var _debut_tick_us: int = Time.get_ticks_usec()
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
	# BASCULE C++ (etape 2 du portage). `utilise_cpp = true` remplace la
	# boucle unique GDScript (senescence + stade + detection + mort
	# vieillesse + reproduction inline) par (a) un appel a
	# `SimulationArbre.avancer_passe_1(...)` en C++ natif pour la partie
	# non-RNG et (b) une boucle GDScript locale pour la reproduction seule
	# (le RNG reste GDScript a cette etape pour que l'ordre des tirages
	# reste evident et testable ; portage RNG a l'etape 3). Defaut false :
	# chemin oracle inchange, boucle unique historique (extraction pure en
	# `_boucle_unique_gd` -- aucun changement de logique dans le chemin
	# oracle).
	var utiliser_cpp_ce_tick: bool = utilise_cpp and _simu_cpp != null
	var _us_bornage_debut: int = Time.get_ticks_usec()
	if utiliser_cpp_ce_tick:
		_passe_1_cpp(pas)
		_passe_reproduction(pas)
	else:
		_boucle_unique_gd(pas)
	_us_boucle += Time.get_ticks_usec() - _us_bornage_debut
	_us_bornage_debut = Time.get_ticks_usec()
	# INLINE _liberer_morts_vieillesse_lot -> _liberer_slots_lot(
	# _morts_vieillesse_lot) -- morceau 2/N. Vars suffixees `_lsl`
	# (liberer slots lot). Le reveil recursif utilise suffix `_lslrev`,
	# le vidage rendu suffix `_lslev`. La fonction originale
	# `_liberer_slots_lot` reste appelee depuis `_avancer_competition`
	# (sera inlinee au morceau suivant, duplication assumee).
	#
	# WRITES cœur morts_v HOISTES au scope avancer : `_monde.retirer_lot`
	# et le depot d'ombrage morts_v (signe -1) sont DEFERES apres les
	# reveils pour etre fusionnes dans la fenetre W1 en UN seul
	# `_couvert.deposer_lot` elargi (morts_v -1 + chaque transition
	# decomposee ancien -1 / nouveau +1). Les reveils inline ne lisent
	# ni monde ni couvert -> defere bit-a-bit equivalent.
	var _ids_a_retirer_lsl: Array = []
	var _dep_x_lsl: PackedFloat32Array = PackedFloat32Array()
	var _dep_z_lsl: PackedFloat32Array = PackedFloat32Array()
	var _dep_r_lsl: PackedFloat32Array = PackedFloat32Array()
	var _dep_m_lsl: PackedFloat32Array = PackedFloat32Array()
	var _dep_s_lsl: PackedByteArray = PackedByteArray()
	# DOUBLE BUFFER PARTIEL : accumule les writes que AUCUNE lecture du
	# tick ne consomme (prouve par audit dependances) -- W2 couvert
	# (naissances +1) et W3 monde+couvert (morts_c). Deverses en UN
	# appel monde et UN appel couvert a la toute fin de `avancer`, avant
	# le print releve (qui lit `nombre_cases()`). W1 monde+couvert et
	# W2 monde restent synchrones (lus par gates semis/banque/competition).
	var _ids_finaux_m: Array = []
	var _dep_x_finaux: PackedFloat32Array = PackedFloat32Array()
	var _dep_z_finaux: PackedFloat32Array = PackedFloat32Array()
	var _dep_r_finaux: PackedFloat32Array = PackedFloat32Array()
	var _dep_m_finaux: PackedFloat32Array = PackedFloat32Array()
	var _dep_s_finaux: PackedByteArray = PackedByteArray()
	var _slots_lsl: PackedInt32Array = _morts_vieillesse_lot
	var _n_lsl: int = _slots_lsl.size()
	if _n_lsl > 0:
		var _rev_x_lsl: PackedFloat32Array = PackedFloat32Array()
		var _rev_z_lsl: PackedFloat32Array = PackedFloat32Array()
		var _n_conf_lsl: int = _ombrage_par_stade.size()
		var _k_lsl: int = 0
		while _k_lsl < _n_lsl:
			var _i_lsl: int = _slots_lsl[_k_lsl]
			_k_lsl += 1
			var _pos_x_lsl: float = _positions_x[_i_lsl]
			var _pos_z_lsl: float = _positions_z[_i_lsl]
			var _chose_lsl = _choses_arbre[_i_lsl]
			if _chose_lsl != null:
				_ids_a_retirer_lsl.append(_chose_lsl.id)
				_choses_arbre[_i_lsl] = null
			_derniere_params[_i_lsl] = Vector4(INF, INF, INF, INF)
			var _index_lsl: int = _slot_stade[_i_lsl]
			if _index_lsl >= 0:
				var _stade_num_lsl: int = _index_lsl + 1
				if _stade_num_lsl >= 1 and _stade_num_lsl <= _n_conf_lsl:
					var _conf_lsl: Dictionary = _ombrage_par_stade[_stade_num_lsl - 1]
					var _mag_lsl: float = float(_conf_lsl.get("magnitude", 0.0))
					if _mag_lsl != 0.0:
						_dep_x_lsl.append(_pos_x_lsl)
						_dep_z_lsl.append(_pos_z_lsl)
						_dep_r_lsl.append(float(_conf_lsl.get("rayon_ombre_m", 0.0)))
						_dep_m_lsl.append(_mag_lsl)
						_dep_s_lsl.append(0)
			# ETAPE 4 : reset colonnes plates (slot_stade/libres/ages) DEFERRE
			# au batch C++ sous bascule. Le chemin oracle garde le reset
			# inline. Le reste du drainage (_slots_libres, _slot_rendu_pour_data,
			# _population, _dep_lsl, _rev_lsl, _choses_arbre, _derniere_params)
			# n'est PAS porte a cette etape.
			if not utiliser_cpp_ce_tick:
				_slot_stade[_i_lsl] = -1
				_libres[_i_lsl] = 1
				_ages[_i_lsl] = 0.0
			_slots_libres.append(_i_lsl)
			var _slot_r_libere_lsl: int = _slot_rendu_pour_data[_i_lsl]
			_slot_rendu_pour_data[_i_lsl] = -1
			if _slot_r_libere_lsl >= 0:
				_data_pour_slot_rendu[_slot_r_libere_lsl] = -1
				_slots_rendu_libres.append(_slot_r_libere_lsl)
			_population -= 1
			_rev_x_lsl.append(_pos_x_lsl)
			_rev_z_lsl.append(_pos_z_lsl)
		# ETAPE 4 : batch C++ du reset colonnes plates apres la boucle.
		# Sous bascule utilise_cpp, remplace les 3 lignes inline
		# (slot_stade[i]=-1, libres[i]=1, ages[i]=0) qui ont ete skippees
		# dans la boucle. Le reste du drainage GDScript est intact.
		if utiliser_cpp_ce_tick:
			var res_reset: Dictionary = _simu_cpp.appliquer_reset_morts(_slots_lsl, _libres, _slot_stade, _ages)
			_libres = res_reset.libres
			_slot_stade = res_reset.slot_stade
			_ages = res_reset.ages
		# WRITES monde+couvert morts_v DEFERES a la fenetre W1 groupee
		# apres les reveils (voir plus bas). Reveils inline n'accedent ni
		# monde ni couvert, defere OK bit-a-bit.
		# INLINE _ecrire_slots_vides_lot(_slots_lsl) -- suffix _lslev.
		var _t_lslev := Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3(0.0, Y_SOL, 0.0))
		var _taille_couleur_lslev: int = _derniere_couleur_stade.size()
		var _k_lslev: int = 0
		while _k_lslev < _n_lsl:
			var _i_lslev: int = _slots_lsl[_k_lslev]
			_k_lslev += 1
			_mm_tronc.set_instance_transform(_i_lslev, _t_lslev)
			_mm_feuillage.set_instance_transform(_i_lslev, _t_lslev)
			if _i_lslev < _taille_couleur_lslev:
				_derniere_couleur_stade[_i_lslev] = -1
		# INLINE _reveiller_dormantes_autour_lot(_rev_x_lsl, _rev_z_lsl)
		# -- suffix _lslrev. Reveils locaux au lot des morts.
		var _n_lslrev: int = _rev_x_lsl.size()
		if _n_lslrev > 0 and _banque_graines != null and _rayon_reveil > 0.0 and _taille_case_dormantes > 0.0 and not _dormantes_par_case.is_empty():
			var _inv_case_lslrev: float = 1.0 / _taille_case_dormantes
			var _carre_lslrev: float = _rayon_reveil * _rayon_reveil
			var _prospects_lslrev: Dictionary = _banque_graines.prospects()
			var _kk_lslrev: int = 0
			while _kk_lslrev < _n_lslrev:
				var _pos_x_lslrev: float = _rev_x_lsl[_kk_lslrev]
				var _pos_z_lslrev: float = _rev_z_lsl[_kk_lslrev]
				_kk_lslrev += 1
				var _cx_min_lslrev: int = floori((_pos_x_lslrev - _rayon_reveil) * _inv_case_lslrev)
				var _cx_max_lslrev: int = floori((_pos_x_lslrev + _rayon_reveil) * _inv_case_lslrev)
				var _cz_min_lslrev: int = floori((_pos_z_lslrev - _rayon_reveil) * _inv_case_lslrev)
				var _cz_max_lslrev: int = floori((_pos_z_lslrev + _rayon_reveil) * _inv_case_lslrev)
				for _cx_lslrev in range(_cx_min_lslrev, _cx_max_lslrev + 1):
					for _cz_lslrev in range(_cz_min_lslrev, _cz_max_lslrev + 1):
						var _cle_lslrev: Vector2i = Vector2i(_cx_lslrev, _cz_lslrev)
						var _ids_lslrev = _dormantes_par_case.get(_cle_lslrev, null)
						if _ids_lslrev == null:
							continue
						for _id_variant_lslrev in _ids_lslrev:
							var _id_lslrev: int = int(_id_variant_lslrev)
							if _reveils.has(_id_lslrev):
								continue
							if not _prospects_lslrev.has(_id_lslrev):
								continue
							var _entree_lslrev: Dictionary = _prospects_lslrev[_id_lslrev]
							var _pos_lslrev: Vector3 = _entree_lslrev.position
							var _dx_lslrev: float = _pos_lslrev.x - _pos_x_lslrev
							var _dz_lslrev: float = _pos_lslrev.z - _pos_z_lslrev
							if _dx_lslrev * _dx_lslrev + _dz_lslrev * _dz_lslrev <= _carre_lslrev:
								_reveils[_id_lslrev] = true
	_us_morts_v += Time.get_ticks_usec() - _us_bornage_debut
	_us_bornage_debut = Time.get_ticks_usec()
	# REVEIL EN LOT INLINE (corps de `_reveiller_dormantes_autour_lot`
	# recopie ici -- morceau 1/N de l'inlining des fonctions banc dans
	# tick). Fonction originale conservee : appelee depuis
	# `_liberer_slots_lot` (mort vieillesse + competition), sera inlinee
	# aux morceaux suivants. Vars suffixees `_rev` pour eviter collisions
	# GDScript function-scope avec les autres inlines du tick.
	var _n_rev: int = _reveils_positions_x.size()
	if _n_rev > 0 and _banque_graines != null and _rayon_reveil > 0.0 and _taille_case_dormantes > 0.0 and not _dormantes_par_case.is_empty():
		var _inv_case_rev: float = 1.0 / _taille_case_dormantes
		var _carre_rev: float = _rayon_reveil * _rayon_reveil
		var _prospects_rev: Dictionary = _banque_graines.prospects()
		var _k_rev: int = 0
		while _k_rev < _n_rev:
			var _pos_x_rev: float = _reveils_positions_x[_k_rev]
			var _pos_z_rev: float = _reveils_positions_z[_k_rev]
			_k_rev += 1
			var _cx_min_rev: int = floori((_pos_x_rev - _rayon_reveil) * _inv_case_rev)
			var _cx_max_rev: int = floori((_pos_x_rev + _rayon_reveil) * _inv_case_rev)
			var _cz_min_rev: int = floori((_pos_z_rev - _rayon_reveil) * _inv_case_rev)
			var _cz_max_rev: int = floori((_pos_z_rev + _rayon_reveil) * _inv_case_rev)
			for _cx_rev in range(_cx_min_rev, _cx_max_rev + 1):
				for _cz_rev in range(_cz_min_rev, _cz_max_rev + 1):
					var _cle_rev: Vector2i = Vector2i(_cx_rev, _cz_rev)
					var _ids_rev = _dormantes_par_case.get(_cle_rev, null)
					if _ids_rev == null:
						continue
					for _id_variant_rev in _ids_rev:
						var _id_rev: int = int(_id_variant_rev)
						if _reveils.has(_id_rev):
							continue
						if not _prospects_rev.has(_id_rev):
							continue
						var _entree_rev: Dictionary = _prospects_rev[_id_rev]
						var _pos_rev: Vector3 = _entree_rev.position
						var _dx_rev: float = _pos_rev.x - _pos_x_rev
						var _dz_rev: float = _pos_rev.z - _pos_z_rev
						if _dx_rev * _dx_rev + _dz_rev * _dz_rev <= _carre_rev:
							_reveils[_id_rev] = true
	# FENETRE W1 : ecritures monde + couvert groupees. Cote monde : UN
	# `_monde.retirer_lot` (morts_v). Cote couvert : UN `_couvert.deposer_lot`
	# ELARGI qui contient morts_v (signe -1) PLUS chaque transition
	# decomposee en 2 depots (ancien signe -1, nouveau signe +1). Fusion
	# C1+C2 en UN franchissement de frontiere couvert au lieu de deux.
	# Doit tourner AVANT `_semer_lot` (qui lit `_couvert.lire_lot` sur
	# toutes les positions du lot) et AVANT le drain banque inline (idem
	# sur les prospects reveilles) pour que monde et couvert refletent
	# l'etat post-W1.
	if _ids_a_retirer_lsl.size() > 0:
		_monde.retirer_lot(_ids_a_retirer_lsl)
	var _n_trans_w1: int = _transitions_x.size()
	var _n_morts_w1: int = _dep_x_lsl.size()
	if _n_morts_w1 > 0 or _n_trans_w1 > 0:
		var _dep_x_w1: PackedFloat32Array = PackedFloat32Array()
		var _dep_z_w1: PackedFloat32Array = PackedFloat32Array()
		var _dep_r_w1: PackedFloat32Array = PackedFloat32Array()
		var _dep_m_w1: PackedFloat32Array = PackedFloat32Array()
		var _dep_s_w1: PackedByteArray = PackedByteArray()
		if _n_morts_w1 > 0:
			_dep_x_w1.append_array(_dep_x_lsl)
			_dep_z_w1.append_array(_dep_z_lsl)
			_dep_r_w1.append_array(_dep_r_lsl)
			_dep_m_w1.append_array(_dep_m_lsl)
			_dep_s_w1.append_array(_dep_s_lsl)
		# TRANSITIONS DECOMPOSEES : chaque redeposer_lot(ancien -> nouveau)
		# devient deux entrees deposer_lot (ancien signe -1, nouveau signe +1).
		# Arithmetique float : redeposer_lot cumule `apport = -ma*pa + mn*pn`
		# puis ajoute a la case en UN add ; deposer_lot 2 entrees fait
		# `case += -ma*pa` puis `case += mn*pn`. Non strictement associatif
		# en float (jusqu'a 1 ULP d'ecart possible) et le compteur
		# `_n_non_nulles` peut basculer intermediaire. Bit-a-bit verifie
		# jeune ET mure sur diff vide -- si dans un futur reglage le diff
		# revele une divergence, revenir a C2 en appel separe (garder C1
		# dans le meme deposer_lot elargi).
		var _kt_w1: int = 0
		while _kt_w1 < _n_trans_w1:
			var _px_w1: float = _transitions_x[_kt_w1]
			var _pz_w1: float = _transitions_z[_kt_w1]
			# entree "ancien" (signe -1)
			_dep_x_w1.append(_px_w1)
			_dep_z_w1.append(_pz_w1)
			_dep_r_w1.append(_transitions_rayon_a[_kt_w1])
			_dep_m_w1.append(_transitions_mag_a[_kt_w1])
			_dep_s_w1.append(0)
			# entree "nouveau" (signe +1)
			_dep_x_w1.append(_px_w1)
			_dep_z_w1.append(_pz_w1)
			_dep_r_w1.append(_transitions_rayon_n[_kt_w1])
			_dep_m_w1.append(_transitions_mag_n[_kt_w1])
			_dep_s_w1.append(1)
			_kt_w1 += 1
		if _dep_x_w1.size() > 0:
			_couvert.deposer_lot(_dep_x_w1, _dep_z_w1, _dep_r_w1, _taille_case, _dep_m_w1, _dep_s_w1)
	_us_reveils += Time.get_ticks_usec() - _us_bornage_debut
	_us_bornage_debut = Time.get_ticks_usec()
	# INLINE _semer_lot -- morceau 3/N. Vars suffixees `_sml`. Inclut
	# l'inline recursif de `_inscrire_dormante` (suffix `_smlind`).
	var _n_sml: int = _graines_lot_x.size()
	if _n_sml > 0:
		var _rayon_gros_sml: float = _rayon_trouee * _facteur_trouee_gros
		var _carre_normal_sml: float = _rayon_trouee * _rayon_trouee
		var _indices_valides_sml: PackedInt32Array = PackedInt32Array()
		var _positions_valides_sml: Array = []
		var _n_zones_pre_sml: int = _zones_exclusion.size()
		var _k_sml: int = 0
		while _k_sml < _n_sml:
			var _pxp_sml: float = _graines_lot_x[_k_sml]
			var _pzp_sml: float = _graines_lot_z[_k_sml]
			if absf(_pxp_sml) > _demi_carte or absf(_pzp_sml) > _demi_carte:
				_k_sml += 1
				continue
			var _dans_zone_pre_sml: bool = false
			if _n_zones_pre_sml > 0:
				var _zi_p_sml: int = 0
				while _zi_p_sml < _n_zones_pre_sml:
					var _zone_p_sml: Dictionary = _zones_exclusion[_zi_p_sml]
					_zi_p_sml += 1
					if int(_zone_p_sml.forme) == 0:
						var _zdx_p_sml: float = _pxp_sml - float(_zone_p_sml.cx)
						var _zdz_p_sml: float = _pzp_sml - float(_zone_p_sml.cz)
						var _r_p_sml: float = float(_zone_p_sml.rayon)
						if _zdx_p_sml * _zdx_p_sml + _zdz_p_sml * _zdz_p_sml <= _r_p_sml * _r_p_sml:
							_dans_zone_pre_sml = true
							break
					else:
						if absf(_pxp_sml - float(_zone_p_sml.cx)) <= float(_zone_p_sml.demi_x) and absf(_pzp_sml - float(_zone_p_sml.cz)) <= float(_zone_p_sml.demi_z):
							_dans_zone_pre_sml = true
							break
			if _dans_zone_pre_sml:
				_k_sml += 1
				continue
			_indices_valides_sml.append(_k_sml)
			_positions_valides_sml.append(Vector3(_pxp_sml, Y_SOL, _pzp_sml))
			_k_sml += 1
		if not _positions_valides_sml.is_empty():
			var _voisins_par_graine_sml: Array = _monde.choses_dans_rayons_brut_xz(_positions_valides_sml, _rayon_gros_sml)
			var _couverts_sml: PackedFloat32Array = _couvert.lire_lot(_graines_lot_x, _graines_lot_z, _taille_case)
			var _carre_min_sml: float = _rayon_exclusion * _rayon_exclusion
			var _stade_gros_min_sml: int = _stade_gros_min
			var _stade_gros_max_sml: int = _stade_gros_max
			var _trouee_max_sml: int = _trouee_max_voisins
			var _taille_slot_stade_sml: int = _slot_stade.size()
			var _j_lot_sml: int = 0
			var _nv_sml: int = _indices_valides_sml.size()
			while _j_lot_sml < _nv_sml:
				var _kk_sml: int = _indices_valides_sml[_j_lot_sml]
				var _pos_x_sml: float = _graines_lot_x[_kk_sml]
				var _pos_z_sml: float = _graines_lot_z[_kk_sml]
				var _voisins_sml: Array = _voisins_par_graine_sml[_j_lot_sml]
				_j_lot_sml += 1
				var _arrivee_sml := Vector3(_pos_x_sml, Y_SOL, _pos_z_sml)
				var _compte_normal_sml: int = 0
				var _passe_sml: bool = true
				for _voisin_sml in _voisins_sml:
					var _slot_v_sml: int = int(_voisin_sml.get("slot", -1))
					var _stade_num_sml: int = 0
					if _slot_v_sml >= 0 and _slot_v_sml < _taille_slot_stade_sml:
						_stade_num_sml = _slot_stade[_slot_v_sml] + 1
					if _stade_num_sml >= _stade_gros_min_sml and _stade_num_sml <= _stade_gros_max_sml:
						_passe_sml = false
						break
					var _pos_voisin_sml: Vector3 = _voisin_sml.position
					var _d2_sml: float = _arrivee_sml.distance_squared_to(_pos_voisin_sml)
					if _d2_sml < _carre_min_sml:
						_passe_sml = false
						break
					if _d2_sml <= _carre_normal_sml:
						_compte_normal_sml += 1
				if _passe_sml:
					var _m_sml: int = _naissances_lot_x.size()
					var _j_s_sml: int = 0
					while _j_s_sml < _m_sml:
						var _dx_sml: float = _naissances_lot_x[_j_s_sml] - _pos_x_sml
						var _dz_sml: float = _naissances_lot_z[_j_s_sml] - _pos_z_sml
						var _d2n_sml: float = _dx_sml * _dx_sml + _dz_sml * _dz_sml
						if _d2n_sml < _carre_min_sml:
							_passe_sml = false
							break
						if _d2n_sml <= _carre_normal_sml:
							_compte_normal_sml += 1
						_j_s_sml += 1
				if _passe_sml and _compte_normal_sml > _trouee_max_sml:
					_passe_sml = false
				if not _passe_sml:
					continue
				if _couverts_sml[_kk_sml] < _seuil_couvert:
					_naissances_lot_x.append(_pos_x_sml)
					_naissances_lot_z.append(_pos_z_sml)
					continue
				var _id_prospect_sml: int = _banque_graines.ajouter({
					"position": Vector3(_pos_x_sml, Y_SOL, _pos_z_sml),
				})
				if _id_prospect_sml >= 0:
					# INLINE _inscrire_dormante(id, pos_x, pos_z) -- suffix _smlind
					if _taille_case_dormantes > 0.0:
						var _inv_case_smlind: float = 1.0 / _taille_case_dormantes
						var _cle_smlind: Vector2i = Vector2i(floori(_pos_x_sml * _inv_case_smlind), floori(_pos_z_sml * _inv_case_smlind))
						var _arr_smlind = _dormantes_par_case.get(_cle_smlind, null)
						if _arr_smlind == null:
							_arr_smlind = []
							_dormantes_par_case[_cle_smlind] = _arr_smlind
						(_arr_smlind as Array).append(_id_prospect_sml)
						_case_de_dormante[_id_prospect_sml] = _cle_smlind
					_expirations.append([_temps_banque + _duree_vie_graine, _id_prospect_sml])
	_us_semis += Time.get_ticks_usec() - _us_bornage_debut
	_us_bornage_debut = Time.get_ticks_usec()
	# INLINE _tick_banque -- morceau 4/N. Vars suffixees `_tbq`.
	# Helpers profonds inlines : _drainer_expirations (suffix _tbqde),
	# _retirer_dormante (suffix _tbqrd).
	_temps_banque += pas
	# INLINE _drainer_expirations() -- suffix _tbqde
	if _banque_graines != null:
		var _prospects_tbqde: Dictionary = _banque_graines.prospects()
		while _expirations_head < _expirations.size():
			var _entry_tbqde: Array = _expirations[_expirations_head]
			if float(_entry_tbqde[0]) > _temps_banque:
				break
			_expirations_head += 1
			var _id_tbqde: int = int(_entry_tbqde[1])
			if _prospects_tbqde.has(_id_tbqde):
				_banque_graines.retirer(_id_tbqde)
				# INLINE _retirer_dormante(_id_tbqde) -- suffix _tbqdrd
				var _cle_v_tbqdrd = _case_de_dormante.get(_id_tbqde, null)
				if _cle_v_tbqdrd != null:
					var _cle_tbqdrd: Vector2i = _cle_v_tbqdrd
					_case_de_dormante.erase(_id_tbqde)
					var _arr_tbqdrd = _dormantes_par_case.get(_cle_tbqdrd, null)
					if _arr_tbqdrd != null:
						(_arr_tbqdrd as Array).erase(_id_tbqde)
						if (_arr_tbqdrd as Array).is_empty():
							_dormantes_par_case.erase(_cle_tbqdrd)
		if _expirations_head > 1024 and _expirations_head > (_expirations.size() >> 1):
			_expirations = _expirations.slice(_expirations_head)
			_expirations_head = 0
	if not _reveils.is_empty():
		var _prospects_tbq: Dictionary = _banque_graines.prospects()
		var _ids_tbq: Array = _reveils.keys()
		_reveils.clear()
		var _rayon_gros_tbq: float = _rayon_trouee * _facteur_trouee_gros
		var _carre_normal_tbq: float = _rayon_trouee * _rayon_trouee
		var _carre_min_tbq: float = _rayon_exclusion * _rayon_exclusion
		var _stade_gros_min_tbq: int = _stade_gros_min
		var _stade_gros_max_tbq: int = _stade_gros_max
		var _trouee_max_tbq: int = _trouee_max_voisins
		var _taille_slot_stade_tbq: int = _slot_stade.size()
		var _pros_x_tbq: PackedFloat32Array = PackedFloat32Array()
		var _pros_z_tbq: PackedFloat32Array = PackedFloat32Array()
		var _pros_ids_tbq: Array = []
		for _id_variant_tbq in _ids_tbq:
			var _id_pre_tbq: int = int(_id_variant_tbq)
			if not _prospects_tbq.has(_id_pre_tbq):
				continue
			var _entree_pre_tbq: Dictionary = _prospects_tbq[_id_pre_tbq]
			var _pos_pre_tbq: Vector3 = _entree_pre_tbq.position
			_pros_x_tbq.append(_pos_pre_tbq.x)
			_pros_z_tbq.append(_pos_pre_tbq.z)
			_pros_ids_tbq.append(_id_pre_tbq)
		var _couverts_tbq: PackedFloat32Array = _couvert.lire_lot(_pros_x_tbq, _pros_z_tbq, _taille_case)
		# M3 GROUPE : UNE requete groupee `choses_dans_rayons_brut_xz` sur
		# TOUTES les positions de prospects reveilles, memes patron que le
		# semis (`_voisins_par_graine_sml`). Aucun tirage RNG dans la
		# boucle prospect -> ordre RNG inchange. Ordre des voisins par
		# prospect strictement identique (tous les arbres a y=Y_SOL, seule
		# la tranche cy=Y_SOL/arete contient des ids ; l'ordre effectif
		# cx externe / cz interne est le meme entre `choses_dans_rayon` et
		# `choses_dans_rayons_brut_xz` sur cette tranche unique).
		var _nn_tbq: int = _pros_ids_tbq.size()
		var _pros_positions_tbq: Array = []
		_pros_positions_tbq.resize(_nn_tbq)
		var _kk_pre_tbq: int = 0
		while _kk_pre_tbq < _nn_tbq:
			_pros_positions_tbq[_kk_pre_tbq] = Vector3(_pros_x_tbq[_kk_pre_tbq], Y_SOL, _pros_z_tbq[_kk_pre_tbq])
			_kk_pre_tbq += 1
		var _voisins_par_prospect_tbq: Array = _monde.choses_dans_rayons_brut_xz(_pros_positions_tbq, _rayon_gros_tbq)
		var _kk_tbq: int = 0
		while _kk_tbq < _nn_tbq:
			var _idx_tbq: int = _kk_tbq
			var _id_tbq: int = int(_pros_ids_tbq[_kk_tbq])
			var _pos_tbq: Vector3 = Vector3(_pros_x_tbq[_kk_tbq], Y_SOL, _pros_z_tbq[_kk_tbq])
			var _couvert_b_tbq: float = _couverts_tbq[_kk_tbq]
			_kk_tbq += 1
			var _arrivee_tbq := _pos_tbq
			var _n_zones_tbq: int = _zones_exclusion.size()
			if _n_zones_tbq > 0:
				var _dans_zone_tbq: bool = false
				var _zi_tbq: int = 0
				while _zi_tbq < _n_zones_tbq:
					var _zone_tbq: Dictionary = _zones_exclusion[_zi_tbq]
					_zi_tbq += 1
					if int(_zone_tbq.forme) == 0:
						var _zdx_tbq: float = _pos_tbq.x - float(_zone_tbq.cx)
						var _zdz_tbq: float = _pos_tbq.z - float(_zone_tbq.cz)
						var _r_tbq: float = float(_zone_tbq.rayon)
						if _zdx_tbq * _zdx_tbq + _zdz_tbq * _zdz_tbq <= _r_tbq * _r_tbq:
							_dans_zone_tbq = true
							break
					else:
						if absf(_pos_tbq.x - float(_zone_tbq.cx)) <= float(_zone_tbq.demi_x) and absf(_pos_tbq.z - float(_zone_tbq.cz)) <= float(_zone_tbq.demi_z):
							_dans_zone_tbq = true
							break
				if _dans_zone_tbq:
					continue
			# M3 GROUPE : lecture indexee du batch pre-calcule (meme patron
			# que le semis `_voisins_par_graine_sml`). Format brut : chaque
			# entree est la `chose` direct, pas un wrap `{chose,type,position}`.
			# Meme reference dict cote monde : `wrap.chose == brut`, valeurs
			# lues par le gate (`get("slot",-1)`, `.position`) identiques.
			var _voisins_tbq: Array = _voisins_par_prospect_tbq[_idx_tbq]
			var _compte_normal_tbq: int = 0
			var _passe_tbq: bool = true
			for _entree_b_tbq in _voisins_tbq:
				var _slot_b_tbq: int = int(_entree_b_tbq.get("slot", -1))
				var _stade_num_b_tbq: int = 0
				if _slot_b_tbq >= 0 and _slot_b_tbq < _taille_slot_stade_tbq:
					_stade_num_b_tbq = _slot_stade[_slot_b_tbq] + 1
				if _stade_num_b_tbq >= _stade_gros_min_tbq and _stade_num_b_tbq <= _stade_gros_max_tbq:
					_passe_tbq = false
					break
				var _pos_voisin_b_tbq: Vector3 = _entree_b_tbq.position
				var _d2_b_tbq: float = _arrivee_tbq.distance_squared_to(_pos_voisin_b_tbq)
				if _d2_b_tbq < _carre_min_tbq:
					_passe_tbq = false
					break
				if _d2_b_tbq <= _carre_normal_tbq:
					_compte_normal_tbq += 1
			if _passe_tbq:
				var _m_b_tbq: int = _naissances_lot_x.size()
				var _j_b_tbq: int = 0
				while _j_b_tbq < _m_b_tbq:
					var _dx_b_tbq: float = _naissances_lot_x[_j_b_tbq] - _pos_tbq.x
					var _dz_b_tbq: float = _naissances_lot_z[_j_b_tbq] - _pos_tbq.z
					var _d2n_b_tbq: float = _dx_b_tbq * _dx_b_tbq + _dz_b_tbq * _dz_b_tbq
					if _d2n_b_tbq < _carre_min_tbq:
						_passe_tbq = false
						break
					if _d2n_b_tbq <= _carre_normal_tbq:
						_compte_normal_tbq += 1
					_j_b_tbq += 1
			if _passe_tbq and _compte_normal_tbq > _trouee_max_tbq:
				_passe_tbq = false
			if not _passe_tbq:
				continue
			if _couvert_b_tbq >= _seuil_couvert:
				continue
			_banque_graines.retirer(_id_tbq)
			# INLINE _retirer_dormante(_id_tbq) -- suffix _tbqrd
			var _cle_v_tbqrd = _case_de_dormante.get(_id_tbq, null)
			if _cle_v_tbqrd != null:
				var _cle_tbqrd: Vector2i = _cle_v_tbqrd
				_case_de_dormante.erase(_id_tbq)
				var _arr_tbqrd = _dormantes_par_case.get(_cle_tbqrd, null)
				if _arr_tbqrd != null:
					(_arr_tbqrd as Array).erase(_id_tbq)
					if (_arr_tbqrd as Array).is_empty():
						_dormantes_par_case.erase(_cle_tbqrd)
			_naissances_lot_x.append(_pos_tbq.x)
			_naissances_lot_z.append(_pos_tbq.z)
	# NAISSANCES EN LOT : draine `_naissances_lot_x/_z` empile par
	# `_semer_lot` et `_tick_banque`. Un seul appel groupe pour toutes
	# les naissances du tick (alloc slots, tirer variance en paires
	# interleaved, `monde.ajouter_lot`, `champ.deposer_lot`). Ordre
	# RNG variance = ordre des naissances dans la queue = ordre naturel
	# (semer d'abord, puis tick_banque). `stades_config` deja partage.
	_us_banque += Time.get_ticks_usec() - _us_bornage_debut
	_us_bornage_debut = Time.get_ticks_usec()
	# INLINE _naitre_lot -- morceau 5/N. Vars suffixees `_ntl`. Helpers
	# inlines : _index_pour_age (suffix _ntlia), _y_pour_naissance
	# (suffix _ntlyn). `_agrandir_capacite` reste appel (chemin rare).
	var _n_ntl: int = _naissances_lot_x.size()
	if _n_ntl == 0:
		_naissances_lot_x.resize(0)
		_naissances_lot_z.resize(0)
	else:
		while _slots_libres.size() < _n_ntl:
			_agrandir_capacite()
		var _slots_ntl: PackedInt32Array = PackedInt32Array()
		_slots_ntl.resize(_n_ntl)
		var _slots_r_ntl: PackedInt32Array = PackedInt32Array()
		_slots_r_ntl.resize(_n_ntl)
		var _k_ntl: int = 0
		while _k_ntl < _n_ntl:
			_slots_ntl[_k_ntl] = _slots_libres.pop_back()
			if _slots_rendu_libres.size() > 0:
				_slots_r_ntl[_k_ntl] = _slots_rendu_libres.pop_back()
			else:
				_slots_r_ntl[_k_ntl] = -1
			_k_ntl += 1
		var _facteurs_ntl: Array = FacteurVariance.tirer_paires_entre_lot(
			_rng, _n_ntl, _croissance_min, _croissance_max, _longevite_min, _longevite_max)
		var _croissance_col_ntl: PackedFloat32Array = _facteurs_ntl[0]
		var _longevite_col_ntl: PackedFloat32Array = _facteurs_ntl[1]
		# INLINE _index_pour_age(0.0) -- suffix _ntlia
		var _stade_initial_ntl: int = -1
		for _ii_ntlia in range(_stades_config_partagee.size()):
			var _seuil_ntlia: float = float(_stades_config_partagee[_ii_ntlia].get("age_seuil", 0.0))
			if 0.0 >= _seuil_ntlia:
				_stade_initial_ntl = _ii_ntlia
		var _entries_monde_ntl: Array = []
		_entries_monde_ntl.resize(_n_ntl)
		var _dep_x_ntl: PackedFloat32Array = PackedFloat32Array()
		var _dep_z_ntl: PackedFloat32Array = PackedFloat32Array()
		var _dep_r_ntl: PackedFloat32Array = PackedFloat32Array()
		var _dep_m_ntl: PackedFloat32Array = PackedFloat32Array()
		var _dep_s_ntl: PackedByteArray = PackedByteArray()
		var _stade_num_ntl: int = _stade_initial_ntl + 1
		var _conf_ombrage_ok_ntl: bool = _stade_num_ntl >= 1 and _stade_num_ntl <= _ombrage_par_stade.size()
		var _rayon_naissance_ntl: float = 0.0
		var _mag_naissance_ntl: float = 0.0
		if _conf_ombrage_ok_ntl:
			var _conf_ntl: Dictionary = _ombrage_par_stade[_stade_num_ntl - 1]
			_rayon_naissance_ntl = float(_conf_ntl.get("rayon_ombre_m", 0.0))
			_mag_naissance_ntl = float(_conf_ntl.get("magnitude", 0.0))
		var _denom_prefixe_ntl: float = _annees_par_seconde * _graines_par_vie
		_k_ntl = 0
		while _k_ntl < _n_ntl:
			var _slot_ntl: int = _slots_ntl[_k_ntl]
			var _pos_x_ntl: float = _naissances_lot_x[_k_ntl]
			var _pos_z_ntl: float = _naissances_lot_z[_k_ntl]
			_libres[_slot_ntl] = 0
			_ages[_slot_ntl] = 0.0
			_positions_x[_slot_ntl] = _pos_x_ntl
			_positions_z[_slot_ntl] = _pos_z_ntl
			# INLINE _y_pour_naissance(_pos_x_ntl, _pos_z_ntl) -- suffix _ntlyn
			var _y_ntlyn: float = Y_SOL
			if hote_actif and carte_terrain_ref != null:
				var _y_variant_ntlyn = carte_terrain_ref.sommet(_pos_x_ntl, _pos_z_ntl)
				if _y_variant_ntlyn != null:
					_y_ntlyn = float(_y_variant_ntlyn)
			_positions_y[_slot_ntl] = _y_ntlyn
			var _slot_r_naissance_ntl: int = _slots_r_ntl[_k_ntl]
			_slot_rendu_pour_data[_slot_ntl] = _slot_r_naissance_ntl
			if _slot_r_naissance_ntl >= 0:
				_data_pour_slot_rendu[_slot_r_naissance_ntl] = _slot_ntl
			_slot_stade[_slot_ntl] = _stade_initial_ntl
			_facteur_croissance[_slot_ntl] = _croissance_col_ntl[_k_ntl]
			_facteur_longevite[_slot_ntl] = _longevite_col_ntl[_k_ntl]
			_derniere_params[_slot_ntl] = Vector4(INF, INF, INF, INF)
			_derniere_couleur_stade[_slot_ntl] = -1
			var _denom_ntl: float = _denom_prefixe_ntl * _croissance_col_ntl[_k_ntl]
			if _fenetre_fertile_age > 0.0 and _denom_ntl > 0.0:
				_intervalle_reprod[_slot_ntl] = _fenetre_fertile_age / _denom_ntl
			else:
				_intervalle_reprod[_slot_ntl] = INF
			var _position_arbre_ntl := Vector3(_pos_x_ntl, Y_SOL, _pos_z_ntl)
			var _chose_ntl := {"id": "arbre_%d" % _slot_ntl, "position": _position_arbre_ntl, "slot": _slot_ntl}
			_choses_arbre[_slot_ntl] = _chose_ntl
			_entries_monde_ntl[_k_ntl] = {"chose": _chose_ntl, "type": "arbre"}
			if _conf_ombrage_ok_ntl and _mag_naissance_ntl != 0.0:
				_dep_x_ntl.append(_pos_x_ntl)
				_dep_z_ntl.append(_pos_z_ntl)
				_dep_r_ntl.append(_rayon_naissance_ntl)
				_dep_m_ntl.append(_mag_naissance_ntl)
				_dep_s_ntl.append(1)
			_population += 1
			_k_ntl += 1
		# W2 monde SYNCHRONE (competition lit monde et compte naissances).
		_monde.ajouter_lot(_entries_monde_ntl)
		# W2 couvert BUFFERISE (aucune lecture couvert apres W2 dans ce
		# tick -- competition ne lit que monde).
		if _dep_x_ntl.size() > 0:
			_dep_x_finaux.append_array(_dep_x_ntl)
			_dep_z_finaux.append_array(_dep_z_ntl)
			_dep_r_finaux.append_array(_dep_r_ntl)
			_dep_m_finaux.append_array(_dep_m_ntl)
			_dep_s_finaux.append_array(_dep_s_ntl)
		_naissances_lot_x.resize(0)
		_naissances_lot_z.resize(0)
	_us_naitre += Time.get_ticks_usec() - _us_bornage_debut
	_us_bornage_debut = Time.get_ticks_usec()
	# INLINE _avancer_competition -- morceau 6/N. Vars suffixees `_avc`.
	# Inline recursif de _liberer_slots_lot (suffix _avclsl), avec ses
	# propres inlines _ecrire_slots_vides_lot (_avcev) et
	# _reveiller_dormantes_autour_lot (_avcrev). Duplication assumee.
	var _cap_avc: int = _capacite
	if _cap_avc > 0 and _cadence_competition > 0.0:
		var _n_slots_avc: int = int(ceil(float(_cap_avc) * pas / _cadence_competition))
		if _n_slots_avc < 1:
			_n_slots_avc = 1
		if _n_slots_avc > _cap_avc:
			_n_slots_avc = _cap_avc
		_competition_positions.clear()
		_competition_slots.resize(0)
		var _count_avc: int = 0
		while _count_avc < _n_slots_avc:
			var _i_avc: int = _curseur_competition
			_curseur_competition = (_curseur_competition + 1) % _cap_avc
			_count_avc += 1
			if _libres[_i_avc] == 1:
				continue
			var _index_avc: int = _slot_stade[_i_avc]
			if _index_avc < 0 or _index_avc + 1 > _stade_competition_max:
				continue
			_competition_positions.append(Vector3(_positions_x[_i_avc], Y_SOL, _positions_z[_i_avc]))
			_competition_slots.append(_i_avc)
		if not _competition_positions.is_empty():
			var _voisins_par_slot_avc: Array = _monde.choses_dans_rayons_brut_xz(_competition_positions, _rayon_competition)
			var _morts_du_tick_avc: Dictionary = {}
			var _morts_slots_avc: PackedInt32Array = PackedInt32Array()
			var _k_avc: int = 0
			var _m_avc: int = _competition_slots.size()
			while _k_avc < _m_avc:
				var _slot_avc: int = _competition_slots[_k_avc]
				var _voisins_list_avc: Array = _voisins_par_slot_avc[_k_avc]
				var _voisins_n_avc: int = _voisins_list_avc.size()
				if not _morts_du_tick_avc.is_empty():
					for _voisin_avc in _voisins_list_avc:
						if _morts_du_tick_avc.has(_voisin_avc.id):
							_voisins_n_avc -= 1
				_k_avc += 1
				if _voisins_n_avc > _competition_max_voisins:
					var _exces_avc: int = _voisins_n_avc - _competition_max_voisins
					var _proba_avc: float = clampf(
						float(_exces_avc) / float(maxi(1, _competition_max_voisins)), 0.0, 1.0)
					if _rng.randf() < _proba_avc:
						var _chose_avc = _choses_arbre[_slot_avc]
						if _chose_avc != null:
							_morts_du_tick_avc[_chose_avc.id] = true
						_morts_slots_avc.append(_slot_avc)
			# INLINE _liberer_slots_lot(_morts_slots_avc) -- suffix _avclsl
			var _n_avclsl: int = _morts_slots_avc.size()
			if _n_avclsl > 0:
				var _ids_a_retirer_avclsl: Array = []
				var _dep_x_avclsl: PackedFloat32Array = PackedFloat32Array()
				var _dep_z_avclsl: PackedFloat32Array = PackedFloat32Array()
				var _dep_r_avclsl: PackedFloat32Array = PackedFloat32Array()
				var _dep_m_avclsl: PackedFloat32Array = PackedFloat32Array()
				var _dep_s_avclsl: PackedByteArray = PackedByteArray()
				var _rev_x_avclsl: PackedFloat32Array = PackedFloat32Array()
				var _rev_z_avclsl: PackedFloat32Array = PackedFloat32Array()
				var _n_conf_avclsl: int = _ombrage_par_stade.size()
				var _k_avclsl: int = 0
				while _k_avclsl < _n_avclsl:
					var _i_avclsl: int = _morts_slots_avc[_k_avclsl]
					_k_avclsl += 1
					var _pos_x_avclsl: float = _positions_x[_i_avclsl]
					var _pos_z_avclsl: float = _positions_z[_i_avclsl]
					var _chose_avclsl = _choses_arbre[_i_avclsl]
					if _chose_avclsl != null:
						_ids_a_retirer_avclsl.append(_chose_avclsl.id)
						_choses_arbre[_i_avclsl] = null
					_derniere_params[_i_avclsl] = Vector4(INF, INF, INF, INF)
					var _index_avclsl: int = _slot_stade[_i_avclsl]
					if _index_avclsl >= 0:
						var _stade_num_avclsl: int = _index_avclsl + 1
						if _stade_num_avclsl >= 1 and _stade_num_avclsl <= _n_conf_avclsl:
							var _conf_avclsl: Dictionary = _ombrage_par_stade[_stade_num_avclsl - 1]
							var _mag_avclsl: float = float(_conf_avclsl.get("magnitude", 0.0))
							if _mag_avclsl != 0.0:
								_dep_x_avclsl.append(_pos_x_avclsl)
								_dep_z_avclsl.append(_pos_z_avclsl)
								_dep_r_avclsl.append(float(_conf_avclsl.get("rayon_ombre_m", 0.0)))
								_dep_m_avclsl.append(_mag_avclsl)
								_dep_s_avclsl.append(0)
					_slot_stade[_i_avclsl] = -1
					_libres[_i_avclsl] = 1
					_ages[_i_avclsl] = 0.0
					_slots_libres.append(_i_avclsl)
					var _slot_r_libere_avclsl: int = _slot_rendu_pour_data[_i_avclsl]
					_slot_rendu_pour_data[_i_avclsl] = -1
					if _slot_r_libere_avclsl >= 0:
						_data_pour_slot_rendu[_slot_r_libere_avclsl] = -1
						_slots_rendu_libres.append(_slot_r_libere_avclsl)
					_population -= 1
					_rev_x_avclsl.append(_pos_x_avclsl)
					_rev_z_avclsl.append(_pos_z_avclsl)
				# W3 monde+couvert BUFFERISES (aucune lecture apres W3 dans
				# ce tick -- morts_c ne sont plus jamais interrogees).
				if _ids_a_retirer_avclsl.size() > 0:
					_ids_finaux_m.append_array(_ids_a_retirer_avclsl)
				if _dep_x_avclsl.size() > 0:
					_dep_x_finaux.append_array(_dep_x_avclsl)
					_dep_z_finaux.append_array(_dep_z_avclsl)
					_dep_r_finaux.append_array(_dep_r_avclsl)
					_dep_m_finaux.append_array(_dep_m_avclsl)
					_dep_s_finaux.append_array(_dep_s_avclsl)
				# INLINE _ecrire_slots_vides_lot(_morts_slots_avc) -- suffix _avcev
				var _t_avcev := Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3(0.0, Y_SOL, 0.0))
				var _taille_couleur_avcev: int = _derniere_couleur_stade.size()
				var _k_avcev: int = 0
				while _k_avcev < _n_avclsl:
					var _i_avcev: int = _morts_slots_avc[_k_avcev]
					_k_avcev += 1
					_mm_tronc.set_instance_transform(_i_avcev, _t_avcev)
					_mm_feuillage.set_instance_transform(_i_avcev, _t_avcev)
					if _i_avcev < _taille_couleur_avcev:
						_derniere_couleur_stade[_i_avcev] = -1
				# INLINE _reveiller_dormantes_autour_lot(_rev_x_avclsl, _rev_z_avclsl) -- suffix _avcrev
				var _n_avcrev: int = _rev_x_avclsl.size()
				if _n_avcrev > 0 and _banque_graines != null and _rayon_reveil > 0.0 and _taille_case_dormantes > 0.0 and not _dormantes_par_case.is_empty():
					var _inv_case_avcrev: float = 1.0 / _taille_case_dormantes
					var _carre_avcrev: float = _rayon_reveil * _rayon_reveil
					var _prospects_avcrev: Dictionary = _banque_graines.prospects()
					var _kk_avcrev: int = 0
					while _kk_avcrev < _n_avcrev:
						var _pos_x_avcrev: float = _rev_x_avclsl[_kk_avcrev]
						var _pos_z_avcrev: float = _rev_z_avclsl[_kk_avcrev]
						_kk_avcrev += 1
						var _cx_min_avcrev: int = floori((_pos_x_avcrev - _rayon_reveil) * _inv_case_avcrev)
						var _cx_max_avcrev: int = floori((_pos_x_avcrev + _rayon_reveil) * _inv_case_avcrev)
						var _cz_min_avcrev: int = floori((_pos_z_avcrev - _rayon_reveil) * _inv_case_avcrev)
						var _cz_max_avcrev: int = floori((_pos_z_avcrev + _rayon_reveil) * _inv_case_avcrev)
						for _cx_avcrev in range(_cx_min_avcrev, _cx_max_avcrev + 1):
							for _cz_avcrev in range(_cz_min_avcrev, _cz_max_avcrev + 1):
								var _cle_avcrev: Vector2i = Vector2i(_cx_avcrev, _cz_avcrev)
								var _ids_avcrev = _dormantes_par_case.get(_cle_avcrev, null)
								if _ids_avcrev == null:
									continue
								for _id_variant_avcrev in _ids_avcrev:
									var _id_avcrev: int = int(_id_variant_avcrev)
									if _reveils.has(_id_avcrev):
										continue
									if not _prospects_avcrev.has(_id_avcrev):
										continue
									var _entree_avcrev: Dictionary = _prospects_avcrev[_id_avcrev]
									var _pos_avcrev: Vector3 = _entree_avcrev.position
									var _dx_avcrev: float = _pos_avcrev.x - _pos_x_avcrev
									var _dz_avcrev: float = _pos_avcrev.z - _pos_z_avcrev
									if _dx_avcrev * _dx_avcrev + _dz_avcrev * _dz_avcrev <= _carre_avcrev:
										_reveils[_id_avcrev] = true
	# RENDU EN LOT : un seul appel groupe pour tous les slots vivants. Le
	# corps de `_ecrire_slot` + `_calc_params` + `_appliquer_couleur_slot`
	# est reproduit inline dans la boucle interne unique -- zero appel
	# de fonction par arbre au chemin chaud. `_agrandir_capacite` garde
	# `_ecrire_slot` pour reposer le buffer GPU quand la capacite double
	# (chemin rare). Corps de `_ecrire_slots_lot` inline ci-dessous
	# (morceau 7, suffixe `_esl`).
	_us_competition += Time.get_ticks_usec() - _us_bornage_debut
	_us_bornage_debut = Time.get_ticks_usec()
	var _cap_esl: int = _capacite
	if utilise_cpp and _simu_cpp != null:
		_ecrire_slots_lot_cpp(_cap_esl)
	elif _cap_esl > 0:
		var _n_stades_esl: int = _durees.size()
		var _n_stades_full_esl: int = _stades.size()
		var _i_esl: int = 0
		while _i_esl < _cap_esl:
			if _libres[_i_esl] == 1:
				_i_esl += 1
				continue
			var _age_esl: float = _ages[_i_esl]
			var _p_esl: Vector4
			var _trouve_esl: bool = false
			var _duree_cumulee_esl: float = 0.0
			var _j_esl: int = 0
			while _j_esl < _n_stades_esl:
				var _duree_segment_esl: float = _durees[_j_esl]
				if _age_esl <= _duree_cumulee_esl + _duree_segment_esl:
					var _t_esl: float = 0.0
					if _duree_segment_esl > 0.0:
						_t_esl = (_age_esl - _duree_cumulee_esl) / _duree_segment_esl
					if _t_esl < 0.0:
						_t_esl = 0.0
					elif _t_esl > 1.0:
						_t_esl = 1.0
					var _a_esl: Dictionary = _stades[_j_esl]
					var _b_esl: Dictionary = _stades[_j_esl + 1]
					_p_esl = Vector4(
						lerp(float(_a_esl.tronc.hauteur), float(_b_esl.tronc.hauteur), _t_esl),
						lerp(float(_a_esl.tronc.largeur), float(_b_esl.tronc.largeur), _t_esl),
						lerp(float(_a_esl.feuillage.hauteur), float(_b_esl.feuillage.hauteur), _t_esl),
						lerp(float(_a_esl.feuillage.largeur), float(_b_esl.feuillage.largeur), _t_esl))
					_trouve_esl = true
					break
				_duree_cumulee_esl += _duree_segment_esl
				_j_esl += 1
			if not _trouve_esl:
				var _s_esl: Dictionary = _stades[_n_stades_full_esl - 1]
				_p_esl = Vector4(
					float(_s_esl.tronc.hauteur), float(_s_esl.tronc.largeur),
					float(_s_esl.feuillage.hauteur), float(_s_esl.feuillage.largeur))
			var _stade_actuel_esl: int = _slot_stade[_i_esl]
			if _derniere_couleur_stade[_i_esl] != _stade_actuel_esl:
				var _col_tronc_esl: Color = COULEUR_REPLI_TRONC
				var _col_feuillage_esl: Color = COULEUR_REPLI_FEUILLAGE
				if _stade_actuel_esl >= 0 and _stade_actuel_esl < _couleur_tronc_par_stade.size():
					_col_tronc_esl = _couleur_tronc_par_stade[_stade_actuel_esl]
				if _stade_actuel_esl >= 0 and _stade_actuel_esl < _couleur_feuillage_par_stade.size():
					_col_feuillage_esl = _couleur_feuillage_par_stade[_stade_actuel_esl]
				_mm_tronc.set_instance_color(_i_esl, _col_tronc_esl)
				_mm_feuillage.set_instance_color(_i_esl, _col_feuillage_esl)
				_derniere_couleur_stade[_i_esl] = _stade_actuel_esl
			var _ancien_esl: Vector4 = _derniere_params[_i_esl]
			if absf(_p_esl.x - _ancien_esl.x) < EPS_TAILLE \
					and absf(_p_esl.y - _ancien_esl.y) < EPS_TAILLE \
					and absf(_p_esl.z - _ancien_esl.z) < EPS_TAILLE \
					and absf(_p_esl.w - _ancien_esl.w) < EPS_TAILLE:
				_i_esl += 1
				continue
			_derniere_params[_i_esl] = _p_esl
			var _ht_esl: float = _p_esl.x
			var _lt_esl: float = _p_esl.y
			var _hf_esl: float = _p_esl.z
			var _lf_esl: float = _p_esl.w
			var _pos_x_esl: float = _positions_x[_i_esl]
			var _pos_z_esl: float = _positions_z[_i_esl]
			var _y_sol_esl: float = _positions_y[_i_esl]
			var _t_tronc_esl := Transform3D(
				Basis.IDENTITY.scaled(Vector3(_lt_esl, _ht_esl, _lt_esl)),
				Vector3(_pos_x_esl, _y_sol_esl + _ht_esl * 0.5, _pos_z_esl))
			_mm_tronc.set_instance_transform(_i_esl, _t_tronc_esl)
			var _t_feuillage_esl: Transform3D
			if _hf_esl <= 0.0 or _lf_esl <= 0.0:
				_t_feuillage_esl = Transform3D(
					Basis.IDENTITY.scaled(Vector3.ZERO),
					Vector3(_pos_x_esl, _y_sol_esl + _ht_esl, _pos_z_esl))
			else:
				_t_feuillage_esl = Transform3D(
					Basis.IDENTITY.scaled(Vector3(_lf_esl, _hf_esl, _lf_esl)),
					Vector3(_pos_x_esl, _y_sol_esl + _ht_esl + _hf_esl * 0.5, _pos_z_esl))
			_mm_feuillage.set_instance_transform(_i_esl, _t_feuillage_esl)
			_i_esl += 1
	_us_rendu += Time.get_ticks_usec() - _us_bornage_debut
	_us_bornage_debut = Time.get_ticks_usec()
	# DEVERSEMENT DES BUFFERS FINAUX : UN appel monde (morts_c) et UN
	# appel couvert (naissances +1 concatenees avec morts_c -1). Ordre des
	# entrees couvert dans le deposer_lot final = ordre chronologique des
	# accumulations : naissances (W2) d'abord, puis morts_c (W3) --
	# strictement identique a la sequence de 2 appels separes couvert
	# (naissances puis morts_c) qui existait avant le buffer. Aucune
	# reordonnance, aucune fusion arithmetique intra-case : bit-a-bit
	# strict.
	if _ids_finaux_m.size() > 0:
		_monde.retirer_lot(_ids_finaux_m)
	if _dep_x_finaux.size() > 0:
		_couvert.deposer_lot(_dep_x_finaux, _dep_z_finaux, _dep_r_finaux, _taille_case, _dep_m_finaux, _dep_s_finaux)
	_us_deverse += Time.get_ticks_usec() - _us_bornage_debut
	# CHRONO TEMPORAIRE : borne basse. La mesure couvre tout le corps de
	# `avancer(pas)` hors la garde d'entree. A RETIRER avec le reste de
	# l'instrumentation.
	_chrono_dernier_tick_us = Time.get_ticks_usec() - _debut_tick_us
	_us_tick_cumul += _chrono_dernier_tick_us
	_frames_depuis_releve += 1
	if _frames_depuis_releve >= CADENCE_RELEVE_POPULATION_FRAMES:
		var n_frames: int = _frames_depuis_releve
		_frames_depuis_releve = 0
		var dormantes: int = 0 if _banque_graines == null else _banque_graines.nombre()
		# Sous-chronos : MOYENNE par tick sur la fenetre du releve. Un poste
		# a 0 us moyen = jamais actif sur la fenetre (ou ecrase sous 1 us).
		@warning_ignore("integer_division")
		print("[arbre] tick=%d us | boucle=%d morts_v=%d reveils=%d semis=%d banque=%d naitre=%d compet=%d rendu=%d deverse=%d | pop=%d dorm=%d cases=%d" % [
			_us_tick_cumul / n_frames,
			_us_boucle / n_frames,
			_us_morts_v / n_frames,
			_us_reveils / n_frames,
			_us_semis / n_frames,
			_us_banque / n_frames,
			_us_naitre / n_frames,
			_us_competition / n_frames,
			_us_rendu / n_frames,
			_us_deverse / n_frames,
			_population, dormantes, _couvert.nombre_cases()
		])
		# Remise a zero de la fenetre.
		_us_tick_cumul = 0
		_us_boucle = 0
		_us_morts_v = 0
		_us_reveils = 0
		_us_semis = 0
		_us_banque = 0
		_us_naitre = 0
		_us_competition = 0
		_us_rendu = 0
		_us_deverse = 0

# ============================================================================
# BOUCLE UNIQUE (chemin oracle GDScript, utilise_cpp = false).
# ============================================================================
# EXTRAITE MOT POUR MOT du corps de `avancer(pas)` : senescence inline +
# stade inline + detection de transition + mort vieillesse + reproduction
# stochastique inline. Aucun changement de logique ni d'ordre par rapport a
# la version pre-extraction -- juste un contenant. Le chemin oracle reste
# la seule verite tant que la parite C++ n'est pas prouvee. Voir en-tete
# du fichier « COUCHE LOGIQUE (coeur) » et « ECART FRAMEWORK ».
func _boucle_unique_gd(pas: float) -> void:
	var cap: int = _capacite
	var n_stades_config: int = _stades_config_partagee.size()
	var i: int = 0
	while i < cap:
		if _libres[i] == 1:
			i += 1
			continue
		_ages[i] = _ages[i] + pas * (_annees_par_seconde * _facteur_croissance[i])
		var age_i: float = _ages[i]
		var ancien: int = _slot_stade[i]
		if n_stades_config > 0:
			var index_trouve: int = -1
			var k: int = 0
			while k < n_stades_config:
				var age_seuil: float = _stades_config_partagee[k].get("age_seuil", 0.0)
				if age_i >= age_seuil:
					index_trouve = k
				k += 1
			if index_trouve > ancien:
				_slot_stade[i] = index_trouve
		var seuil_mort: float = (_duree_croissance_totale + _duree_mort) * _facteur_longevite[i]
		if age_i >= seuil_mort:
			_slot_stade[i] = ancien
			_morts_vieillesse_lot.append(i)
			i += 1
			continue
		var nouveau_index: int = _slot_stade[i]
		if nouveau_index != ancien:
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
		if age_i >= _debut_fertilite and age_i < _fin_fertilite:
			var intervalle_i: float = _intervalle_reprod[i]
			if intervalle_i > 0.0 and not is_inf(intervalle_i):
				if _rng.randf() < pas / intervalle_i:
					var angle_r: float = _rng.randf() * TAU
					var rayon_r: float = sqrt(_rng.randf()) * _rayon_graine
					_graines_lot_x.append(_positions_x[i] + cos(angle_r) * rayon_r)
					_graines_lot_z.append(_positions_z[i] + sin(angle_r) * rayon_r)
		i += 1

# ============================================================================
# PASSE 1 en C++ (chemin bascule, utilise_cpp = true).
# ============================================================================
# Appelle `SimulationArbre.avancer_passe_1(...)` (extension_terrain) et
# INTEGRE ses sorties dans l'etat GDScript : reassigne _ages et _slot_stade
# (patron Copy-on-Write), append aux lots (transitions, reveils, morts
# vieillesse), depose les cas rares « simple » (naissance/mort dans boucle)
# directement dans _couvert via _deposer_ombrage. La reproduction n'est PAS
# faite ici -- elle est appelee separement (`_passe_reproduction`) pour
# garder le RNG cote GDScript a cette etape.
func _passe_1_cpp(pas: float) -> void:
	if not _cpp_stable_pousse:
		_pousser_stables_cpp()
		_cpp_stable_pousse = true
	# APPEL TYPE (ptrcall) : 9 arguments nommes, aucun Dictionary d'entree.
	# Voir simulation_arbre.h -- signature alignee sur index_spatial.h::
	# perception_lot. La sortie reste Dictionary (aligne sur les 4 soeurs).
	var res: Dictionary = _simu_cpp.avancer_passe_1(
		pas, _capacite, _libres, _ages, _slot_stade,
		_facteur_croissance, _facteur_longevite, _positions_x, _positions_z
	)
	_ages = res.ages
	_slot_stade = res.slot_stade
	_morts_vieillesse_lot.append_array(res.morts_vieillesse)
	_transitions_x.append_array(res.transitions_x)
	_transitions_z.append_array(res.transitions_z)
	_transitions_rayon_a.append_array(res.transitions_rayon_a)
	_transitions_rayon_n.append_array(res.transitions_rayon_n)
	_transitions_mag_a.append_array(res.transitions_mag_a)
	_transitions_mag_n.append_array(res.transitions_mag_n)
	_reveils_positions_x.append_array(res.reveils_x)
	_reveils_positions_z.append_array(res.reveils_z)
	var n_simple: int = res.simple_stade.size()
	var k: int = 0
	while k < n_simple:
		_deposer_ombrage(res.simple_x[k], res.simple_z[k], res.simple_stade[k], res.simple_signe[k])
		k += 1

# Extrait les stables du banc et les pousse une seule fois au C++ via
# `SimulationArbre.initialiser_stable(...)`. Le paquet couvre :
# annees_par_seconde, duree_croissance_totale, duree_mort, stade_gros_min/max,
# les age_seuil du catalogue de stades, les rayon_ombre_m et magnitude de
# l'ombrage par stade. Idempotent : peut etre rappele sans effet observable.
func _pousser_stables_cpp() -> void:
	var seuils: PackedFloat32Array = PackedFloat32Array()
	for entry in _stades_config_partagee:
		seuils.append(float(entry.get("age_seuil", 0.0)))
	var omb_r: PackedFloat32Array = PackedFloat32Array()
	var omb_m: PackedFloat32Array = PackedFloat32Array()
	for entry in _ombrage_par_stade:
		omb_r.append(float(entry.get("rayon_ombre_m", 0.0)))
		omb_m.append(float(entry.get("magnitude", 0.0)))
	# APPEL TYPE (ptrcall) : 8 arguments nommes.
	_simu_cpp.initialiser_stable(
		_annees_par_seconde,
		_duree_croissance_totale,
		_duree_mort,
		_stade_gros_min,
		_stade_gros_max,
		seuils,
		omb_r,
		omb_m
	)
	# Tables du RENDU (durees_stades, tronc/feuillage hauteur/largeur par
	# stade, couleurs par stade, couleurs de repli, Y_SOL). Extraction des
	# Dictionary imbriques _stades[k].tronc.hauteur etc. en PackedFloat32Array
	# plates -- puis appel typé.
	var n_stades_full: int = _stades.size()
	var tr_h: PackedFloat32Array = PackedFloat32Array()
	var tr_l: PackedFloat32Array = PackedFloat32Array()
	var fe_h: PackedFloat32Array = PackedFloat32Array()
	var fe_l: PackedFloat32Array = PackedFloat32Array()
	tr_h.resize(n_stades_full)
	tr_l.resize(n_stades_full)
	fe_h.resize(n_stades_full)
	fe_l.resize(n_stades_full)
	for k in range(n_stades_full):
		var e: Dictionary = _stades[k]
		tr_h[k] = float(e.tronc.hauteur)
		tr_l[k] = float(e.tronc.largeur)
		fe_h[k] = float(e.feuillage.hauteur)
		fe_l[k] = float(e.feuillage.largeur)
	_simu_cpp.initialiser_stable_rendu(
		_durees,
		tr_h,
		tr_l,
		fe_h,
		fe_l,
		_couleur_tronc_par_stade,
		_couleur_feuillage_par_stade,
		COULEUR_REPLI_TRONC,
		COULEUR_REPLI_FEUILLAGE,
		Y_SOL
	)
	# ETAPE 6 : pousser les stables de reproduction.
	_simu_cpp.initialiser_stable_reproduction(
		_debut_fertilite,
		_fin_fertilite,
		_rayon_graine
	)

# ============================================================================
# RENDU par PUSH BUFFER (chemin bascule utilise_cpp = true).
# ============================================================================
# Remplace la boucle GDScript de rendu (2xN appels set_instance_transform)
# par UN appel C++ qui construit deux PackedFloat32Array + DEUX push moteur
# (`_mm_tronc.buffer = ...`, `_mm_feuillage.buffer = ...`). Voir
# simulation_arbre.h::construire_buffers_rendu pour le layout (16 floats
# par slot : 12 transform TRANSFORM_3D + 4 color RGBA).
func _ecrire_slots_lot_cpp(cap: int) -> void:
	if cap <= 0:
		return
	var res: Dictionary = _simu_cpp.construire_buffers_rendu(
		cap,
		_libres,
		_ages,
		_slot_stade,
		_positions_x,
		_positions_y,
		_positions_z
	)
	# Synchro instance_count : le buffer C++ fait 16*cap floats, le
	# MultiMesh doit avoir instance_count = cap avant `buffer = ...`.
	if _mm_tronc.instance_count != cap:
		_mm_tronc.instance_count = cap
	if _mm_feuillage.instance_count != cap:
		_mm_feuillage.instance_count = cap
	_mm_tronc.buffer = res.buffer_tronc
	_mm_feuillage.buffer = res.buffer_feuillage

# ============================================================================
# CONSTRUIRE BUFFERS RENDU en GDScript (helper de test parite).
# ============================================================================
# Miroir GDScript de construire_buffers_rendu C++. Reproduit la MEME logique
# (lerp, cas feuillage nul, couleurs, formules Y), sans skip cache -- pour
# comparer bit-a-bit contre le buffer C++. NE PAS l'utiliser au chemin
# oracle (il ne cache pas) : c'est un helper de TEST uniquement.
func _construire_buffers_rendu_gd(cap: int) -> Dictionary:
	var buf_t: PackedFloat32Array = PackedFloat32Array()
	var buf_f: PackedFloat32Array = PackedFloat32Array()
	buf_t.resize(cap * 16)
	buf_f.resize(cap * 16)
	var n_durees: int = _durees.size()
	var n_stades_full: int = _stades.size()
	var n_col_t: int = _couleur_tronc_par_stade.size()
	var n_col_f: int = _couleur_feuillage_par_stade.size()
	# BUFFERIZE les tables de stade en PackedFloat32Array : le C++ lit
	# depuis des std::vector<float> (float32), il faut que le helper GD
	# fasse le meme calcul depuis les memes valeurs float32 (les doubles
	# JSON ont ete casts en float32 lors du push aux stables C++). Sans
	# ca, le helper GD lit les doubles JSON directement -> divergence 1 ULP.
	var tr_h_f: PackedFloat32Array = PackedFloat32Array()
	var tr_l_f: PackedFloat32Array = PackedFloat32Array()
	var fe_h_f: PackedFloat32Array = PackedFloat32Array()
	var fe_l_f: PackedFloat32Array = PackedFloat32Array()
	tr_h_f.resize(n_stades_full)
	tr_l_f.resize(n_stades_full)
	fe_h_f.resize(n_stades_full)
	fe_l_f.resize(n_stades_full)
	for k in range(n_stades_full):
		var e: Dictionary = _stades[k]
		tr_h_f[k] = float(e.tronc.hauteur)
		tr_l_f[k] = float(e.tronc.largeur)
		fe_h_f[k] = float(e.feuillage.hauteur)
		fe_l_f[k] = float(e.feuillage.largeur)
	var i: int = 0
	while i < cap:
		var base: int = i * 16
		if _libres[i] == 1:
			buf_t[base + 7] = Y_SOL
			buf_t[base + 15] = 1.0
			buf_f[base + 7] = Y_SOL
			buf_f[base + 15] = 1.0
			i += 1
			continue
		var age: float = _ages[i]
		var ht: float = 0.0
		var lt: float = 0.0
		var hf: float = 0.0
		var lf: float = 0.0
		var duree_cumulee: float = 0.0
		var trouve: bool = false
		var j: int = 0
		while j < n_durees:
			var duree_segment: float = _durees[j]
			if age <= duree_cumulee + duree_segment:
				var t: float = 0.0
				if duree_segment > 0.0:
					t = (age - duree_cumulee) / duree_segment
				if t < 0.0:
					t = 0.0
				elif t > 1.0:
					t = 1.0
				# Lire depuis les PackedFloat32Array bufferizes (float32) --
				# meme precision que le C++ (std::vector<float>).
				ht = tr_h_f[j] + t * (tr_h_f[j + 1] - tr_h_f[j])
				lt = tr_l_f[j] + t * (tr_l_f[j + 1] - tr_l_f[j])
				hf = fe_h_f[j] + t * (fe_h_f[j + 1] - fe_h_f[j])
				lf = fe_l_f[j] + t * (fe_l_f[j + 1] - fe_l_f[j])
				trouve = true
				break
			duree_cumulee += duree_segment
			j += 1
		if not trouve:
			var idx: int = n_stades_full - 1
			ht = tr_h_f[idx]
			lt = tr_l_f[idx]
			hf = fe_h_f[idx]
			lf = fe_l_f[idx]
		var stade_actuel: int = _slot_stade[i]
		var ct: Color = COULEUR_REPLI_TRONC
		var cf: Color = COULEUR_REPLI_FEUILLAGE
		if stade_actuel >= 0 and stade_actuel < n_col_t:
			ct = _couleur_tronc_par_stade[stade_actuel]
		if stade_actuel >= 0 and stade_actuel < n_col_f:
			cf = _couleur_feuillage_par_stade[stade_actuel]
		var pos_x: float = _positions_x[i]
		var pos_y_sol: float = _positions_y[i]
		var pos_z: float = _positions_z[i]
		buf_t[base + 0] = lt
		buf_t[base + 3] = pos_x
		buf_t[base + 5] = ht
		buf_t[base + 7] = pos_y_sol + ht * 0.5
		buf_t[base + 10] = lt
		buf_t[base + 11] = pos_z
		buf_t[base + 12] = ct.r
		buf_t[base + 13] = ct.g
		buf_t[base + 14] = ct.b
		buf_t[base + 15] = ct.a
		if hf <= 0.0 or lf <= 0.0:
			buf_f[base + 3] = pos_x
			buf_f[base + 7] = pos_y_sol + ht
			buf_f[base + 11] = pos_z
		else:
			buf_f[base + 0] = lf
			buf_f[base + 3] = pos_x
			buf_f[base + 5] = hf
			buf_f[base + 7] = pos_y_sol + ht + hf * 0.5
			buf_f[base + 10] = lf
			buf_f[base + 11] = pos_z
		buf_f[base + 12] = cf.r
		buf_f[base + 13] = cf.g
		buf_f[base + 14] = cf.b
		buf_f[base + 15] = cf.a
		i += 1
	return {"buffer_tronc": buf_t, "buffer_feuillage": buf_f}

# ============================================================================
# REPRODUCTION SEULE (chemin bascule, apres `_passe_1_cpp`).
# ============================================================================
# Boucle par arbre, meme ordre 0..cap-1 que la boucle unique GDScript --
# ordre des tirages `_rng.randf()` STRICTEMENT identique a l'oracle,
# condition pour que le seed produise la meme foret sous les deux chemins
# (parite prouvee a l'etape 3 quand le RNG sera lui aussi porte C++).
# Skip _libres[i]==1 et skip les slots fraichement morts dans la passe 1
# (via un PackedByteArray temporaire construit une fois par tick). Un
# slot mort de vieillesse ne se reproduit pas -- meme resultat que le
# `continue` sur mort de la boucle unique originale.
func _passe_reproduction(pas: float) -> void:
	var cap: int = _capacite
	# ETAPE 6 : sous bascule, appel batch C++ (meme ordre, meme RNG partage,
	# parite bit-a-bit). Chemin oracle GDScript inchange sinon.
	if utilise_cpp and _simu_cpp != null:
		var res_repro: Dictionary = _simu_cpp.passe_reproduction(
			pas,
			cap,
			_libres,
			_ages,
			_intervalle_reprod,
			_positions_x,
			_positions_z,
			_morts_vieillesse_lot
		)
		_graines_lot_x.append_array(res_repro.graines_x)
		_graines_lot_z.append_array(res_repro.graines_z)
		return
	var morts_set: PackedByteArray = PackedByteArray()
	morts_set.resize(cap)
	var nm: int = _morts_vieillesse_lot.size()
	var kk: int = 0
	while kk < nm:
		var mi: int = _morts_vieillesse_lot[kk]
		if mi >= 0 and mi < cap:
			morts_set[mi] = 1
		kk += 1
	var i: int = 0
	while i < cap:
		if _libres[i] == 1 or morts_set[i] == 1:
			i += 1
			continue
		var age_i: float = _ages[i]
		if age_i >= _debut_fertilite and age_i < _fin_fertilite:
			var intervalle_i: float = _intervalle_reprod[i]
			if intervalle_i > 0.0 and not is_inf(intervalle_i):
				if _rng.randf() < pas / intervalle_i:
					var angle_r: float = _rng.randf() * TAU
					var rayon_r: float = sqrt(_rng.randf()) * _rayon_graine
					_graines_lot_x.append(_positions_x[i] + cos(angle_r) * rayon_r)
					_graines_lot_z.append(_positions_z[i] + sin(angle_r) * rayon_r)
		i += 1


# Hauteur Y du sol pour une naissance. Mode isole (`hote_actif = false`)
# : Y_SOL constant, comportement bit-a-bit inchange du banc historique.
# Mode hote : lit `carte_terrain_ref.sommet(pos_x, pos_z)` -- si null
# (hors emprise du terrain, cas de bord flottant), fallback Y_SOL. Lue
# UNE fois par naissance, jamais recalculee au rendu.
func _y_pour_naissance(pos_x: float, pos_z: float) -> float:
	if not hote_actif:
		return Y_SOL
	if carte_terrain_ref == null:
		return Y_SOL
	var y_variant = carte_terrain_ref.sommet(pos_x, pos_z)
	if y_variant == null:
		return Y_SOL
	return float(y_variant)

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
# `redeposer` : le chemin rare (`_agrandir_capacite`) garde
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
		# Y du sol lue en colonne (voir `_positions_y`). Mode isole :
		# Y_SOL constant, bit-a-bit inchange. Mode hote : sommet(x,z) du
		# terrain reel, pose une fois a la naissance.
		var y_sol: float = _positions_y[i]
		var t_tronc := Transform3D(
			Basis.IDENTITY.scaled(Vector3(lt, ht, lt)),
			Vector3(pos_x, y_sol + ht * 0.5, pos_z))
		_mm_tronc.set_instance_transform(i, t_tronc)
		var t_feuillage: Transform3D
		if hf <= 0.0 or lf <= 0.0:
			t_feuillage = Transform3D(
				Basis.IDENTITY.scaled(Vector3.ZERO),
				Vector3(pos_x, y_sol + ht, pos_z))
		else:
			t_feuillage = Transform3D(
				Basis.IDENTITY.scaled(Vector3(lf, hf, lf)),
				Vector3(pos_x, y_sol + ht + hf * 0.5, pos_z))
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
	# Y du sol lue en colonne (voir `_positions_y`).
	var y_sol: float = _positions_y[i]
	var t_tronc := Transform3D(
		Basis.IDENTITY.scaled(Vector3(lt, ht, lt)),
		Vector3(pos_x, y_sol + ht * 0.5, pos_z))
	_mm_tronc.set_instance_transform(i, t_tronc)
	var t_feuillage: Transform3D
	if hf <= 0.0 or lf <= 0.0:
		t_feuillage = Transform3D(
			Basis.IDENTITY.scaled(Vector3.ZERO),
			Vector3(pos_x, y_sol + ht, pos_z))
	else:
		t_feuillage = Transform3D(
			Basis.IDENTITY.scaled(Vector3(lf, hf, lf)),
			Vector3(pos_x, y_sol + ht + hf * 0.5, pos_z))
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

# LOT DE VIDAGES DE SLOTS en UNE passe : applique le corps de
# `_ecrire_slot_vide` inline dans une boucle interne, zero appel de
# fonction par slot. Meme transform t (identity scaled zero a Y_SOL),
# meme reset cache couleur. Appele par `_liberer_slots_lot` pour tous
# les slots liberes du tick en un seul geste. `_ecrire_slot_vide`
# (unitaire) reste utilise ailleurs (`_monter_population` init,
# `_agrandir_capacite`).
func _ecrire_slots_vides_lot(slots: PackedInt32Array) -> void:
	var n: int = slots.size()
	if n == 0:
		return
	var t := Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3(0.0, Y_SOL, 0.0))
	var taille_couleur: int = _derniere_couleur_stade.size()
	var k: int = 0
	while k < n:
		var i: int = slots[k]
		k += 1
		_mm_tronc.set_instance_transform(i, t)
		_mm_feuillage.set_instance_transform(i, t)
		if i < taille_couleur:
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

func _naitre(pos_x: float, pos_z: float) -> void:
	if _slots_libres.is_empty():
		_agrandir_capacite()
	var i: int = _slots_libres.pop_back()
	var position_arbre := Vector3(pos_x, Y_SOL, pos_z)
	var objet: Dictionary = Objet.fabriquer(
		"arbre_%d" % i, TYPE_ARBRE, position_arbre, _catalogue, {}, [], {}, [], true)
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
	# Hauteur Y du sol pour le rendu de ce slot (voir doc de `_positions_y`).
	_positions_y[i] = _y_pour_naissance(pos_x, pos_z)
	# Mapping slot data -> slot rendu (voir bloc SEPARATION en tete). En
	# morceau 1 identity, morceaux 2/3 casseront cette equivalence.
	var slot_r_ini: int = -1
	if _slots_rendu_libres.size() > 0:
		slot_r_ini = _slots_rendu_libres.pop_back()
	_slot_rendu_pour_data[i] = slot_r_ini
	if slot_r_ini >= 0:
		_data_pour_slot_rendu[slot_r_ini] = i
	_slot_stade[i] = _index_pour_age(_ages[i])
	if _slot_stade[i] >= 0:
		_deposer_ombrage(pos_x, pos_z, _slot_stade[i] + 1, 1)
	_facteur_croissance[i] = FacteurVariance.tirer_entre(_rng, _croissance_min, _croissance_max)
	_facteur_longevite[i] = FacteurVariance.tirer_entre(_rng, _longevite_min, _longevite_max)
	var denom: float = _annees_par_seconde * _facteur_croissance[i] * _graines_par_vie
	if _fenetre_fertile_age > 0.0 and denom > 0.0:
		_intervalle_reprod[i] = _fenetre_fertile_age / denom
	else:
		_intervalle_reprod[i] = INF
	var chose := {"id": "arbre_%d" % i, "position": position_arbre, "slot": i}
	_choses_arbre[i] = chose
	_monde.ajouter(chose, "arbre", position_arbre)
	# INVALIDATION CACHE RENDU par coherence avec `_naitre_lot` : force
	# `_ecrire_slot` a repousser transform+couleur sans risquer un skip
	# EPS sur un cache herite d'un slot precedent.
	_derniere_params[i] = Vector4(INF, INF, INF, INF)
	_derniere_couleur_stade[i] = -1
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
	_positions_y.resize(nouvelle)
	_slot_rendu_pour_data.resize(nouvelle)
	_data_pour_slot_rendu.resize(nouvelle)
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
	# En morceau 1 (identity), capacite rendu suit capacite data.
	_capacite_rendu = nouvelle
	# INIT NEW SLOTS : par defaut libres, sentinelle INF pour cache
	# rendu, `_ecrire_slot_vide` push zero-scale sur le buffer neuf.
	var i: int = nouvelle - 1
	while i >= ancienne:
		_libres[i] = 1
		_ages[i] = 0.0
		_positions_x[i] = 0.0
		_positions_z[i] = 0.0
		_positions_y[i] = Y_SOL
		_slot_stade[i] = -1
		_facteur_croissance[i] = 1.0
		_facteur_longevite[i] = 1.0
		_intervalle_reprod[i] = INF
		_choses_arbre[i] = null
		_derniere_params[i] = Vector4(INF, INF, INF, INF)
		_derniere_couleur_stade[i] = -1
		_slot_rendu_pour_data[i] = -1
		_data_pour_slot_rendu[i] = -1
		_slots_libres.append(i)
		_slots_rendu_libres.append(i)
		_ecrire_slot_vide(i)
		i -= 1
	# REPOSE DES SLOTS PREEXISTANTS : `instance_count` a REINITIALISE le
	# buffer GPU des deux MultiMesh. Tout transform et couleur ecrits avant
	# sont perdus. Il faut INVALIDER `_derniere_params` ET
	# `_derniere_couleur_stade` de CHAQUE slot preexistant (vivant comme
	# libre), sinon `_ecrire_slots_lot` en fin de tick verrait un cache
	# valide et SKIPPERAIT la reecriture -- laissant le slot a la
	# transform par defaut du buffer neuf. `_ecrire_slot_vide` immediat
	# pour les libres, `_ecrire_slot` immediat pour les vivants
	# (garantit un buffer coherent avant meme le prochain
	# `_ecrire_slots_lot`).
	var j: int = 0
	while j < ancienne:
		_derniere_params[j] = Vector4(INF, INF, INF, INF)
		_derniere_couleur_stade[j] = -1
		if _libres[j] == 1:
			_ecrire_slot_vide(j)
		else:
			_ecrire_slot(j, _ages[j])
		j += 1

