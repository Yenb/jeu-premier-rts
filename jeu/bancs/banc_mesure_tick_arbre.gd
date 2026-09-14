# BANC DE MESURE — coût du tick arbre (GDScript vs C++).
#
# Outil de mesure NEUF, à poser sous jeu/bancs/. Il ne porte AUCUNE logique de
# simulation : il PILOTE la coquille existante (banc_peuplement_arbre.tscn),
# laisse la population monter jusqu'à ~N arbres, puis chronomètre le coût moyen
# d'un appel `_sim.avancer(pas)` en microsecondes.
#
# Il donne le POINT DE RÉFÉRENCE GDScript. Aux étapes suivantes du port, la
# bascule C++ se mesure avec le MÊME banc, MÊME seed, MÊME population cible :
# le rapport des deux chronos EST le gain du portage. Un port qui n'améliore pas
# ce chrono n'a pas gagné, quel que soit ce que dit la théorie.
#
# LANCER (headless, adapter le chemin Godot — voir CLAUDE.md § TRAVAILLER SUR
# LE PROJET, deux machines, deux chemins) :
#   & "<chemin godot>" --headless --script jeu/bancs/banc_mesure_tick_arbre.gd
#
# CE QUE LE PORT DOIT EXPOSER pour que ce banc lise la population sans fouiller
# les privés : une méthode publique `population() -> int` sur SimulationArbre
# (GDScript ET C++), rendant `_population`. Si elle n'existe pas encore, ce banc
# le DIT et retombe sur un accès direct `_sim._population` (fragile, à retirer
# dès que `population()` existe). À l'étape 1, exposer `population()` fait partie
# du scaffolding.

extends SceneTree

const CHEMIN_SCENE := "res://jeu/bancs/banc_peuplement_arbre.tscn"

# Populations cibles à mesurer. Le banc laisse la sim tourner jusqu'à atteindre
# (au mieux) chaque palier, puis chronomètre à ce palier. Adapter selon
# l'échelle visée du peuplement.
const PALIERS := [1000, 10000]

# Nombre de ticks chronométrés par palier (moyenne sur ces ticks). Assez pour
# lisser le bruit, pas trop pour ne pas laisser la population dériver loin du
# palier pendant la mesure.
const TICKS_MESURE := 200

# Pas de sim passé à avancer() — même ordre de grandeur que la cadence réelle
# du banc (1 / cadence_simulation_hz, défaut 4 Hz → 0.25 s). Le pas influe sur
# la proba stochastique : garder ce pas FIXE entre GDScript et C++ pour que la
# comparaison soit propre.
const PAS := 0.25

# Plafond de ticks de peuplement avant d'abandonner un palier (évite une boucle
# infinie si la population plafonne sous la cible pour raison de saturation).
const TICKS_PEUPLEMENT_MAX := 200000


func _initialize() -> void:
	print("[mesure] démarrage — mesure du coût du tick arbre")
	var scene: PackedScene = load(CHEMIN_SCENE)
	if scene == null:
		push_error("[mesure] scène introuvable : %s" % CHEMIN_SCENE)
		quit(1)
		return
	var racine: Node = scene.instantiate()
	get_root().add_child(racine)
	# En `extends SceneTree` + `--headless --script`, le _ready() du child
	# n'est PAS synchrone apres add_child : il est reporte a la premiere
	# passe idle. Sans cette ligne, `racine.get("_sim")` juste apres
	# rendrait null (verifie : _sim = null avant frame, RefCounted valide
	# apres). Un `await process_frame` suffit -- pas de tick de sim, juste
	# de quoi laisser Godot lever _ready.
	await process_frame

	# _ready est appelé à l'ajout au root. La coquille monte alors _sim,
	# les MultiMesh, le monde, le couvert, la banque, et fait naître l'arbre
	# initial. On récupère _sim depuis la coquille.
	var sim = racine.get("_sim")
	if sim == null:
		push_error("[mesure] la coquille n'expose pas _sim (banc inerte) — vérifier banc_peuplement_arbre.gd:_ready")
		quit(1)
		return

	for cible in PALIERS:
		_mesurer_palier(sim, cible)

	print("[mesure] terminé")
	quit(0)


func _mesurer_palier(sim, cible: int) -> void:
	# PEUPLEMENT : faire tourner la sim jusqu'à atteindre ~cible arbres, sans
	# chronométrer (le peuplement lui-même n'est pas la mesure).
	var pop := _population_de(sim)
	var ticks_peuplement := 0
	while pop < cible and ticks_peuplement < TICKS_PEUPLEMENT_MAX:
		sim.avancer(PAS)
		ticks_peuplement += 1
		pop = _population_de(sim)

	var pop_atteinte := _population_de(sim)
	if pop_atteinte < cible:
		print("[mesure] palier %d NON atteint (population plafonnée à %d après %d ticks) — mesure quand même à cette population" % [cible, pop_atteinte, ticks_peuplement])

	# MESURE : chronométrer TICKS_MESURE appels à avancer(pas). Temps total en
	# microsecondes, divisé par le nombre de ticks → coût moyen par tick.
	var t0 := Time.get_ticks_usec()
	for _i in range(TICKS_MESURE):
		sim.avancer(PAS)
	var t1 := Time.get_ticks_usec()

	var total_us := t1 - t0
	var par_tick_us := float(total_us) / float(TICKS_MESURE)
	var pop_finale := _population_de(sim)

	print("[mesure] population ~%d (mesuré sur %d..%d) : %.1f us / tick (total %d us sur %d ticks)" % [
		cible, pop_atteinte, pop_finale, par_tick_us, total_us, TICKS_MESURE])


# Lit la population sans fouiller les privés SI la méthode publique existe.
# Sinon retombe sur l'accès direct au champ privé, en le SIGNALANT (à retirer
# dès que population() est exposée par le port).
func _population_de(sim) -> int:
	if sim.has_method("population"):
		return int(sim.population())
	# Repli fragile — SIGNALÉ une seule fois.
	if not _repli_signale:
		push_warning("[mesure] SimulationArbre n'expose pas population() — accès direct à _population (fragile). Exposer population() à l'étape 1.")
		_repli_signale = true
	return int(sim.get("_population"))

var _repli_signale := false
