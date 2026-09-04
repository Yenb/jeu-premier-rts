extends SceneTree

# Test de MICRO-PROFIL de la Phase B du pipeline de banc_peuplement.gd. Le
# profil scaling precedent (scripts/test_profil_peuplement.gd) a identifie
# Phase B (Tick.tick_entite -> Mouvement._pas_simple + monde.deplacer) comme
# poste dominant a ~22 us/individu, quasi constant en N. Ce test decompose
# ces 22 us en TROIS sous-phases mesurees separement, pour cibler ou porter
# l'optimisation.
#
#   B2 : cout interne de Mouvement._pas_simple, mesure en appelant
#        Mouvement.pas(entite, dt, monde=null, carte, "simple") pour ISOLER
#        du B3 (le null desactive la ligne S.11 monde.deplacer).
#   B3 : cout de monde.deplacer, mesure en l'appelant seul sur chaque
#        individu (l'individu est deja dans monde.choses via Peuplement.spawn
#        qui appelle monde.ajouter).
#   B_total : Tick.tick_entite avec monde=monde, profil=simple, cadence=1
#             (le meme appel que le banc). Reference et sanity check du
#             ~22 us/individu du test precedent.
#   B1 (derive) : B_total - B2 - B3, cout d'appel Tick.tick_entite hors
#                 Mouvement.pas et hors deplacer -- dispatch Callable,
#                 lecture/ecriture frames_depuis_tick, lecture cadence, calcul
#                 delta_effectif. Derive car Tick.tick_entite N'A PAS de mode
#                 no-op : la seule facon d'isoler l'overhead d'appel est par
#                 soustraction. Une cadence "999" ferait un exit anticipe et
#                 ne mesurerait pas le chemin qui appelle Mouvement.pas.
#
# ATTENTION SUR B3. Dans le pipeline banc_peuplement actuel, personne
# n'appelle monde.choses_dans_rayon -- donc _niveaux reste vide, et
# deplacer() reduit a ses gardes + une iteration sur dict vide. B3 sera
# quasi-nul, ce qui EST la verite du pipeline actuel. Si un banc futur
# ouvrait une resolution (proximite de troupeau, foule, ciblage), B3
# monterait -- mais tant que rien ne l'ouvre, il n'y a pas de cout a payer.
#
# Deux tailles seulement (N=1000 et N=5000) : la question n'est plus si le
# cout par-individu est constant en N -- test_profil_peuplement.gd l'a
# etabli -- mais QUEL sous-poste attaquer. Deux points suffisent a verifier
# que la sous-decomposition reste O(N) sur ces deux echelles.
#
# Trois passes SEPAREES par taille : chaque pass fait 100 ticks avec la meme
# operation isolee, ce qui evite le double travail d'un chronometrage
# imbrique dans Tick.tick_entite. La derive de l'etat entre passes ne biaise
# pas les mesures : le cout par operation ne depend pas de la vitesse ou de
# la position courante des individus.
#
# Godot 4 headless :
#   godot --headless --script scripts/test_profil_phase_b.gd

const Verif = preload("res://scripts/verif.gd")
const Peuplement = preload("res://scripts/peuplement.gd")
const Monde = preload("res://scripts/monde.gd")
const MeshCatalogue = preload("res://scripts/mesh_catalogue.gd")
const Tick = preload("res://scripts/tick.gd")
const Mouvement = preload("res://scripts/mouvement_kinematic.gd")
const CarteTerrain = preload("res://jeu/terrain/carte_terrain.gd")

const TAILLES: Array = [1000, 5000]
const TICKS_MESURES: int = 30  # 30 * 5000 * 22us * 3 passes ~= 10s a N=5000, tient sous les 30s du lanceur.gd
const TICKS_WARMUP: int = 3
const DELTA: float = 1.0 / 60.0
const GRAINE: int = 20260904

var _v := Verif.new()

func _init() -> void:
	_lancer.call_deferred()

func _lancer() -> void:
	await _executer()
	if _v.echecs() == 0:
		print("OK: scripts/test_profil_phase_b.gd -- micro-profil B decompose")
		quit(0)
	else:
		printerr("ECHEC: %d assertion(s) fausse(s)" % _v.echecs())
		quit(1)

func _executer() -> void:
	var racine := Node3D.new()
	get_root().add_child(racine)
	await process_frame

	var catalogue_mesh: Dictionary = MeshCatalogue.charger()
	_v.v(not catalogue_mesh.is_empty(), "catalogue mesh vide")
	var mesh: Mesh = MeshCatalogue.fabriquer_mesh(catalogue_mesh.get("boite_simple", {}))
	_v.v(mesh != null, "mesh 'boite_simple' non resolu")
	var scenario: RID = racine.get_world_3d().scenario
	_v.v(scenario.is_valid(), "scenario invalide")
	var catalogue_types: Dictionary = _charger_types()
	_v.v(catalogue_types.has("mobile_test"), "types.json sans 'mobile_test'")

	if _v.echecs() > 0:
		return

	var politique: Callable = Callable(Tick, "politique_intrinseque")

	print("")
	print("N,B_total_us_par_ind,B2_us_par_ind,B3_us_par_ind,B1_derive_us_par_ind,B_total_us_total,B2_us_total,B3_us_total")

	var mesures: Array = []

	for N in TAILLES:
		var carte := CarteTerrain.new()
		var monde = Monde.new()
		var pool: Dictionary = Peuplement.creer_pool(N, mesh, scenario)
		_v.v(not pool.is_empty(), "N=%d : pool vide" % N)
		if pool.is_empty():
			continue
		var errance: Dictionary = {}
		var rng := RandomNumberGenerator.new()
		rng.seed = GRAINE
		var demi_zone: float = 40.0 + sqrt(float(N)) * 2.0
		var poses: int = 0
		var tentatives: int = 0
		while poses < N and tentatives < N * 10:
			tentatives += 1
			var x: float = rng.randf_range(-demi_zone, demi_zone)
			var z: float = rng.randf_range(-demi_zone, demi_zone)
			var y_sol_v: Variant = carte.sommet(x, z)
			if y_sol_v == null:
				continue
			var position := Vector3(x, float(y_sol_v) + 0.4, z)
			var id: String = Peuplement.spawn(pool, catalogue_types, "mobile_test", position, monde)
			if id.is_empty():
				push_error("N=%d : spawn echec tentative %d" % [N, tentatives])
				break
			var individu: Dictionary = pool.individus[pool.id_to_index[id]]
			var p: Dictionary = individu.proprietes
			p["profil"] = "simple"
			p["cadence_tick"] = 1
			p["velocite"] = Vector3.ZERO
			p["velocite_desiree_horizontale"] = Vector3.ZERO
			p["au_sol"] = false
			p["gravite"] = 18.0
			errance[id] = {
				"direction": _nouvelle_direction(rng),
				"cap_horloge": rng.randf_range(3.0, 8.0),
			}
			poses += 1
		_v.v(poses == N, "N=%d : seulement %d individus poses" % [N, poses])

		# Warm-up : amene les individus a un etat stable (au_sol qui bascule
		# a true au premier snap sol, gravite qui trouve son regime).
		for _w in range(TICKS_WARMUP):
			for individu in pool.individus:
				_pose_intention(individu, errance, rng)
				Tick.tick_entite(individu, politique, DELTA, monde, carte)

		# ---- Pass B_total : Tick.tick_entite complet, comme le banc ----
		var acc_total: int = 0
		for _t in range(TICKS_MESURES):
			for individu in pool.individus:
				_pose_intention(individu, errance, rng)
				var t0: int = Time.get_ticks_usec()
				Tick.tick_entite(individu, politique, DELTA, monde, carte)
				acc_total += Time.get_ticks_usec() - t0

		# ---- Pass B2 : Mouvement.pas ISOLE, monde=null ----
		# On court-circuite Tick pour ne mesurer QUE _pas_simple. Le null
		# desactive S.11 monde.deplacer -- B3 est exclu.
		var acc_b2: int = 0
		for _t in range(TICKS_MESURES):
			for individu in pool.individus:
				_pose_intention(individu, errance, rng)
				var t0: int = Time.get_ticks_usec()
				Mouvement.pas(individu, DELTA, null, carte, "simple")
				acc_b2 += Time.get_ticks_usec() - t0

		# ---- Pass B3 : monde.deplacer ISOLE ----
		# Chaque individu est deja dans monde.choses (Peuplement.spawn a
		# appele monde.ajouter). L'appel direct court-circuite Mouvement et
		# Tick. _niveaux reste vide tant que personne n'a demande
		# choses_dans_rayon -- c'est la realite du cout de deplacer dans le
		# pipeline actuel.
		var acc_b3: int = 0
		for _t in range(TICKS_MESURES):
			for individu in pool.individus:
				var t0: int = Time.get_ticks_usec()
				monde.deplacer(individu)
				acc_b3 += Time.get_ticks_usec() - t0

		var b_total_us_ind: float = float(acc_total) / float(N) / float(TICKS_MESURES)
		var b2_us_ind: float = float(acc_b2) / float(N) / float(TICKS_MESURES)
		var b3_us_ind: float = float(acc_b3) / float(N) / float(TICKS_MESURES)
		var b1_derive_us_ind: float = b_total_us_ind - b2_us_ind - b3_us_ind

		print("%d,%.3f,%.3f,%.3f,%.3f,%d,%d,%d" % [
			N,
			b_total_us_ind, b2_us_ind, b3_us_ind, b1_derive_us_ind,
			acc_total, acc_b2, acc_b3,
		])

		mesures.append({
			"N": N,
			"total": b_total_us_ind,
			"b1": b1_derive_us_ind,
			"b2": b2_us_ind,
			"b3": b3_us_ind,
		})

		Peuplement.detruire_pool(pool)

	if mesures.size() >= 2:
		var petit: Dictionary = mesures[0]
		var grand: Dictionary = mesures[mesures.size() - 1]
		var noms := ["B1", "B2", "B3"]
		var vals_grand := [grand.b1, grand.b2, grand.b3]
		var vals_petit := [petit.b1, petit.b2, petit.b3]
		var idx_max: int = 0
		for i in range(1, 3):
			if vals_grand[i] > vals_grand[idx_max]:
				idx_max = i
		var ratio_dom: float = 0.0
		if vals_petit[idx_max] > 0.0:
			ratio_dom = vals_grand[idx_max] / vals_petit[idx_max]
		var comportement: String = "O(N) sain"
		if ratio_dom > 1.5:
			comportement = "SUPER-LINEAIRE -- cout par individu qui monte avec N"
		elif ratio_dom < 0.66:
			comportement = "SOUS-LINEAIRE (mesure suspecte : warm-up ou bruit)"
		var ratio_b3: float = 0.0
		if petit.b3 > 0.0:
			ratio_b3 = grand.b3 / petit.b3
		print("")
		print("ANALYSE : %s domine (%.3f us/ind a N=%d, %.3f a N=%d, ratio %.2f -- %s). B3 (monde.deplacer) : %.3f us/ind a N=%d, ratio N=%d/N=%d = %.2f. Attaquer %s." % [
			noms[idx_max],
			vals_grand[idx_max], int(grand.N),
			vals_petit[idx_max], int(petit.N),
			ratio_dom,
			comportement,
			grand.b3, int(grand.N),
			int(grand.N), int(petit.N),
			ratio_b3,
			noms[idx_max],
		])

func _nouvelle_direction(rng: RandomNumberGenerator) -> Vector3:
	var angle: float = rng.randf() * TAU
	return Vector3(cos(angle), 0.0, sin(angle))

# Recopie de la Phase A du banc, pour que Mouvement.pas ait une intention
# horizontale non nulle a chaque tick (branche S.4 de composition).
func _pose_intention(individu: Dictionary, errance: Dictionary, rng: RandomNumberGenerator) -> void:
	var id: String = String(individu.id)
	if not errance.has(id):
		return
	var etat: Dictionary = errance[id]
	etat["cap_horloge"] = float(etat.cap_horloge) - DELTA
	if float(etat.cap_horloge) <= 0.0:
		etat["direction"] = _nouvelle_direction(rng)
		etat["cap_horloge"] = rng.randf_range(3.0, 8.0)
	var p: Dictionary = individu.proprietes
	var vitesse: float = float(p.get("vitesse", 1.0))
	p["velocite_desiree_horizontale"] = (etat.direction as Vector3) * vitesse

func _charger_types() -> Dictionary:
	if not FileAccess.file_exists("res://data/types.json"):
		return {}
	var texte := FileAccess.get_file_as_string("res://data/types.json")
	var donnees = JSON.parse_string(texte)
	if donnees is Dictionary:
		return donnees
	return {}
