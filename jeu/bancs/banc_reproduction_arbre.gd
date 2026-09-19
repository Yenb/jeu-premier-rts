# BANC D'ISOLATION REPRODUCTION ARBRE — CHIFFRES SEULS, AUCUN RENDU.
#
# But : observer UNIQUEMENT les evenements de reproduction (naissances,
# morts) de la simulation d'arbres. Aucune couche rendu : pas de camera
# poussee (donc `_camera_active` reste false cote wrapper, aucun filtre ne
# tourne), pas de MultiMeshInstance3D dans la scene, pas d'occlusion, pas de
# frustum, pas de shader. Deux `MultiMesh.new()` vides sont passes a
# `_sim.attacher(...)` pour respecter la signature, mais ne sont jamais
# ajoutes a l'arbre de scene ni rafraichis.
#
# La sim tourne a la cadence JSON (`cadence_simulation_hz`) via
# `_sim.avancer(pas)`. Chaque frame, la variation de `_sim.population()`
# donne les naissances (hausse) et morts (baisse) ; un log par seconde.
#
# Reutilise le catalogue JSON du grand banc
# (res://data/banc_peuplement_arbre.json). Aucune ecriture dans data/. Le
# grand banc (banc_peuplement_arbre.gd) reste intact.
#
# ECART FRAMEWORK : ce banc + son catalogue local sont neufs, voir
# CLAUDE.md § Frontiere.

extends Node3D

const Monde = preload("res://scripts/monde.gd")
const ChampSaturationPlatGd = preload("res://scripts/champ_saturation_plat.gd")
const AttenteSeuil = preload("res://scripts/attente_seuil.gd")
const SimulationArbreGd = preload("res://jeu/bancs/simulation_arbre.gd")

const CHEMIN_CATALOGUE_LOCAL := "res://data/banc_peuplement_arbre.json"
const CHEMIN_TYPES := "res://data/types.json"

# Capacite initiale des deux MultiMesh, doit correspondre a
# `SimulationArbreGd.CAPACITE_INITIALE` -- l'init des colonnes de la sim
# repose sur cette taille de buffer.
const CAPACITE_INITIALE := 8

# Cadence de simulation (Hz) lue du JSON. Le delta accumule est passe en
# `pas` a `_sim.avancer(pas)`.
var _cadence_simulation_hz: float = 4.0
var _mode_test_rapide: bool = false
var _temps_depuis_maj: float = 0.0

# MultiMesh vides : passes a attacher pour la signature, jamais ajoutes a la
# scene ni rafraichis. La sim y ecrit ses transforms/couleurs (init des
# colonnes), sans consequence puisque rien ne les rend.
var _mm_tronc: MultiMesh = null
var _mm_feuillage: MultiMesh = null

var _sim: RefCounted = null

# Instrumentation reproduction.
var _pop_prec: int = 0          # population de la frame precedente.
var _pop_prec_sec: int = 0      # population au dernier log (pour le delta/s).
var _naissances_sec: int = 0    # naissances depuis le dernier log.
var _morts_sec: int = 0         # morts depuis le dernier log.
var _naissances_total: int = 0  # cumul session.
var _morts_total: int = 0       # cumul session.
var _instr_temps: float = 0.0
const INSTR_INTERVALLE_S: float = 1.0


func _ready() -> void:
	var donnees: Dictionary = _charger_json_local()
	if donnees.is_empty():
		return
	if donnees.has("cadence_simulation_hz"):
		_cadence_simulation_hz = float(donnees.cadence_simulation_hz)
	if donnees.has("mode_test_rapide"):
		_mode_test_rapide = bool(donnees.mode_test_rapide)
	# ChampSaturationPlatGd : bornes derivees de `demi_carte / taille_case` +
	# marge = ceil(max_rayon_ombre_m / taille_case), pour couvrir les depots
	# pres du bord (meme calcul que le grand banc).
	var demi_carte_couvert: float = float(donnees.get("demi_carte", 300.0))
	var taille_case: float = float(donnees.get("taille_case", 20.0))
	var ombrage: Array = donnees.get("ombrage_par_stade", [])
	var max_rayon_ombre_m: float = 0.0
	for entree in ombrage:
		if entree is Dictionary:
			max_rayon_ombre_m = maxf(max_rayon_ombre_m, float(entree.get("rayon_ombre_m", 0.0)))
	var demi_cases: int = int(ceil(demi_carte_couvert / taille_case))
	var marge_cases: int = int(ceil(max_rayon_ombre_m / taille_case))
	var borne_cases: int = demi_cases + marge_cases
	var couvert = ChampSaturationPlatGd.new()
	couvert.activer_cpp()
	couvert.configurer(-borne_cases, -borne_cases, borne_cases, borne_cases)
	var monde = Monde.new()
	monde.structure_simple = true
	var banque = AttenteSeuil.new()
	var types_dynamique = _lire_types_dynamique()
	if types_dynamique == null:
		return
	# MultiMesh vides configures comme ceux du grand banc (transform_format,
	# use_colors, instance_count) pour que l'init des colonnes de la sim
	# (set_instance_transform / set_instance_color) ne soit pas hors-bornes.
	# Aucun mesh, aucun noeud : rien n'est rendu.
	_mm_tronc = MultiMesh.new()
	_mm_tronc.transform_format = MultiMesh.TRANSFORM_3D
	_mm_tronc.use_colors = true
	_mm_tronc.instance_count = CAPACITE_INITIALE
	_mm_feuillage = MultiMesh.new()
	_mm_feuillage.transform_format = MultiMesh.TRANSFORM_3D
	_mm_feuillage.use_colors = true
	_mm_feuillage.instance_count = CAPACITE_INITIALE
	# Sim : mode isole (pas d'hote, pas de carte_terrain externe).
	_sim = SimulationArbreGd.new()
	_sim.configurer(donnees)
	_sim.attacher(_mm_tronc, _mm_feuillage, monde, couvert, banque, false, null, types_dynamique)
	_sim.configurer_cpp(true)
	# Arbre initial en (0, Y_SOL, 0) : le tscn n'a pas de transform.
	_sim.naitre_initial(global_position.x, global_position.z)
	_pop_prec = _sim.population()
	_pop_prec_sec = _pop_prec


func _process(delta: float) -> void:
	if _sim == null:
		return
	# CADENCE DE SIMULATION DECOUPLEE DU FRAMERATE. La reproduction, la mort
	# vieillesse et la competition dependent de `pas` ; aucune camera n'est
	# poussee, donc aucun filtre rendu ne tourne cote C++.
	_temps_depuis_maj += delta
	var intervalle_maj: float = 1.0 / _cadence_simulation_hz if _cadence_simulation_hz > 0.0 else 0.0
	if _temps_depuis_maj >= intervalle_maj:
		var pas: float = _temps_depuis_maj
		_temps_depuis_maj = 0.0
		if _mode_test_rapide:
			pas *= 4.0
		_sim.avancer(pas)
	# Evenements de reproduction : variation de population frame a frame.
	# Hausse = naissances, baisse = morts (net par intervalle entre lectures).
	var pop: int = _sim.population()
	if pop > _pop_prec:
		var n: int = pop - _pop_prec
		_naissances_sec += n
		_naissances_total += n
	elif pop < _pop_prec:
		var m: int = _pop_prec - pop
		_morts_sec += m
		_morts_total += m
	_pop_prec = pop
	# Log une ligne par seconde.
	_instr_temps += delta
	if _instr_temps >= INSTR_INTERVALLE_S:
		_instr_temps = 0.0
		print("pop=", pop,
			" naissances=", _naissances_sec,
			" morts=", _morts_sec,
			" delta=", pop - _pop_prec_sec,
			" | total_naissances=", _naissances_total,
			" total_morts=", _morts_total)
		_naissances_sec = 0
		_morts_sec = 0
		_pop_prec_sec = pop


# Charge le JSON du banc (donnees + config). Rend un Dictionary vide en
# cas d'echec -- l'appelant (`_ready`) court-circuite le montage.
func _charger_json_local() -> Dictionary:
	if not FileAccess.file_exists(CHEMIN_CATALOGUE_LOCAL):
		push_error("banc_reproduction_arbre : catalogue local absent (%s)" % CHEMIN_CATALOGUE_LOCAL)
		return {}
	var texte := FileAccess.get_file_as_string(CHEMIN_CATALOGUE_LOCAL)
	if texte.is_empty():
		push_error("banc_reproduction_arbre : catalogue local vide (%s)" % CHEMIN_CATALOGUE_LOCAL)
		return {}
	var donnees = JSON.parse_string(texte)
	if not (donnees is Dictionary):
		push_error("banc_reproduction_arbre : catalogue local invalide (pas un objet)")
		return {}
	return donnees


# Lit `data/types.json` et rend le paquet `dynamique`. Passe a la sim pour
# construire le catalogue combine.
func _lire_types_dynamique() -> Variant:
	if not FileAccess.file_exists(CHEMIN_TYPES):
		push_error("banc_reproduction_arbre : %s absent" % CHEMIN_TYPES)
		return null
	var texte_types := FileAccess.get_file_as_string(CHEMIN_TYPES)
	var types = JSON.parse_string(texte_types)
	if not (types is Dictionary):
		push_error("banc_reproduction_arbre : %s invalide" % CHEMIN_TYPES)
		return null
	if not types.has("dynamique"):
		push_error("banc_reproduction_arbre : paquet `dynamique` absent de %s" % CHEMIN_TYPES)
		return null
	return types.dynamique
