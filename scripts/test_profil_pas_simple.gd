extends SceneTree

# Test de SOUS-PROFIL de Mouvement._pas_simple. Le micro-profil precedent
# (scripts/test_profil_phase_b.gd) a mesure B2 = _pas_simple a 17-18 us/ind,
# 80 % du budget d'un tick. Ce test decompose ces 17 us en QUATRE blocs
# mesures separement, pour cibler l'optimisation.
#
# APPROCHE (a) : la logique de _pas_simple est RECOPIEE localement dans le
# test, decoupee en 4 passes independantes. Aucune instrumentation dans
# scripts/mouvement_kinematic.gd -- le cœur reste intact. La recopie
# s'aligne ligne a ligne sur mouvement_kinematic.gd:516-571 (S.1 a S.10).
#
#   B2.1 : S.1-S.5 -- lecture proprietes, gravite, vitesse terminale,
#          composition horizontale, calcul du deplacement candidat.
#   B2.2 : S.6 -- les DEUX appels carte.sommet_sous (sol_ici, sol_devant)
#          qui portent le blocage terrain. Nb : _pas_simple fait en tout
#          TROIS appels sommet_sous ; le troisieme (S.8 snap) est mesure
#          dans B2.4 conformement au decoupage du prompt.
#   B2.3 : S.6 -- la comparaison (null check + rise > cote) qui annule
#          l'horizontale. Sans les lookups (deja mesures en B2.2).
#   B2.4 : S.7-S.10 -- application horizontale + verticale + snap sol
#          (avec son sommet_sous) + au_sol + ecriture velocite.
#
# La ligne S.11 (monde.deplacer) est HORS decoupage : mesuree en B3 dans
# test_profil_phase_b.gd (0.7 us/ind), pas rejouee ici.
#
# Passes independantes par sous-composant : chaque pass fait TICKS_MESURES
# ticks sur les N individus, chronometre au bloc via Time.get_ticks_usec.
# Entre passes, des champs techniques prefixes _ stockent l'etat
# intermediaire (deplacement candidat, resultats des lookups) pour que la
# pass suivante n'ait pas a le recalculer.
#
# Sanity check en analyse : B2.1 + B2.2 + B2.3 + B2.4 doit tomber pres du
# B2 mesure par test_profil_phase_b.gd (~17 us). Un ecart franc signalerait
# un decoupage biaise (surcout de setup dans une pass, ou branche omise).
#
# Godot 4 headless :
#   godot --headless --script scripts/test_profil_pas_simple.gd

const Verif = preload("res://scripts/verif.gd")
const Peuplement = preload("res://scripts/peuplement.gd")
const Monde = preload("res://scripts/monde.gd")
const MeshCatalogue = preload("res://scripts/mesh_catalogue.gd")
const Tick = preload("res://scripts/tick.gd")
const Mouvement = preload("res://scripts/mouvement_kinematic.gd")
const CarteTerrain = preload("res://jeu/terrain/carte_terrain.gd")

const TAILLES: Array = [1000, 5000]
const TICKS_MESURES: int = 30  # 4 passes * 5000 * 30 * ~5us ~= 3s a N=5000, tient sous les 30s du lanceur.
const TICKS_WARMUP: int = 3
const DELTA: float = 1.0 / 60.0
const GRAINE: int = 20260904

var _v := Verif.new()

func _init() -> void:
	_lancer.call_deferred()

func _lancer() -> void:
	await _executer()
	if _v.echecs() == 0:
		print("OK: scripts/test_profil_pas_simple.gd -- sous-profil B2 decompose")
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
	print("N,B2.1_us/ind,B2.2_us/ind,B2.3_us/ind,B2.4_us/ind,somme_us/ind,B2.1_total,B2.2_total,B2.3_total,B2.4_total")

	var mesures: Array = []

	for N in TAILLES:
		var carte := CarteTerrain.new()
		var monde = Monde.new()
		var pool: Dictionary = Peuplement.creer_pool(N, mesh, scenario)
		_v.v(not pool.is_empty(), "N=%d : pool vide" % N)
		if pool.is_empty():
			continue

		var cote: float = 2.0
		if "cote" in carte:
			cote = float(carte.cote)

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

		# Warm-up : etat stable (au_sol qui bascule au premier snap sol).
		for _w in range(TICKS_WARMUP):
			for individu in pool.individus:
				_pose_intention(individu, errance, rng)
				Tick.tick_entite(individu, politique, DELTA, monde, carte)

		var acc_1: int = 0
		var acc_2: int = 0
		var acc_3: int = 0
		var acc_4: int = 0

		# ---- Pass B2.1 : S.1-S.5 ----
		for _t in range(TICKS_MESURES):
			for individu in pool.individus:
				_pose_intention(individu, errance, rng)
				var t0: int = Time.get_ticks_usec()
				var p: Dictionary = individu.proprietes
				var ve: Vector3 = p.get("velocite", Vector3.ZERO)
				var gravite: float = float(p.get("gravite", 18.0))
				ve.y -= gravite * DELTA
				ve.y = maxf(ve.y, -Mouvement.VITESSE_TERMINALE)
				var vdh: Vector3 = p.get("velocite_desiree_horizontale", Vector3.ZERO)
				ve.x = vdh.x
				ve.z = vdh.z
				var dep: Vector3 = ve * DELTA
				p["_dep"] = dep
				p["velocite"] = ve
				acc_1 += Time.get_ticks_usec() - t0

		# ---- Pass B2.2 : S.6 -- les deux carte.sommet_sous ----
		for _t in range(TICKS_MESURES):
			for individu in pool.individus:
				var p: Dictionary = individu.proprietes
				var dep: Vector3 = p.get("_dep", Vector3.ZERO)
				var pos: Vector3 = individu.position
				var t0: int = Time.get_ticks_usec()
				var sol_ici = carte.sommet_sous(pos.x, pos.z, pos.y + cote)
				var sol_devant = carte.sommet_sous(pos.x + dep.x, pos.z + dep.z, pos.y + cote)
				acc_2 += Time.get_ticks_usec() - t0
				p["_sol_ici"] = sol_ici
				p["_sol_devant"] = sol_devant

		# ---- Pass B2.3 : S.6 -- comparaison seule ----
		for _t in range(TICKS_MESURES):
			for individu in pool.individus:
				var p: Dictionary = individu.proprietes
				var dep: Vector3 = p.get("_dep", Vector3.ZERO)
				var ve: Vector3 = p.get("velocite", Vector3.ZERO)
				var sol_ici = p.get("_sol_ici", null)
				var sol_devant = p.get("_sol_devant", null)
				var t0: int = Time.get_ticks_usec()
				if sol_ici == null or sol_devant == null:
					dep.x = 0.0
					dep.z = 0.0
					ve.x = 0.0
					ve.z = 0.0
				elif float(sol_devant) - float(sol_ici) > cote:
					dep.x = 0.0
					dep.z = 0.0
					ve.x = 0.0
					ve.z = 0.0
				acc_3 += Time.get_ticks_usec() - t0
				p["_dep"] = dep
				p["velocite"] = ve

		# ---- Pass B2.4 : S.7-S.10 -- application + snap sol + ecriture ----
		for _t in range(TICKS_MESURES):
			for individu in pool.individus:
				var p: Dictionary = individu.proprietes
				var dep: Vector3 = p.get("_dep", Vector3.ZERO)
				var ve: Vector3 = p.get("velocite", Vector3.ZERO)
				var t0: int = Time.get_ticks_usec()
				individu.position += Vector3(dep.x, 0.0, dep.z)
				individu.position.y += dep.y
				var pos: Vector3 = individu.position
				var sol = carte.sommet_sous(pos.x, pos.z, pos.y + cote)
				var contact: bool = false
				if sol != null and pos.y <= float(sol):
					individu.position.y = float(sol)
					contact = true
				var au_sol_final: bool = contact and ve.y <= 0.0
				p["au_sol"] = au_sol_final
				if au_sol_final:
					ve.y = 0.0
				p["velocite"] = ve
				acc_4 += Time.get_ticks_usec() - t0

		var b1_us: float = float(acc_1) / float(N) / float(TICKS_MESURES)
		var b2_us: float = float(acc_2) / float(N) / float(TICKS_MESURES)
		var b3_us: float = float(acc_3) / float(N) / float(TICKS_MESURES)
		var b4_us: float = float(acc_4) / float(N) / float(TICKS_MESURES)
		var somme_us: float = b1_us + b2_us + b3_us + b4_us

		print("%d,%.3f,%.3f,%.3f,%.3f,%.3f,%d,%d,%d,%d" % [
			N,
			b1_us, b2_us, b3_us, b4_us, somme_us,
			acc_1, acc_2, acc_3, acc_4,
		])

		mesures.append({
			"N": N,
			"b1": b1_us, "b2": b2_us, "b3": b3_us, "b4": b4_us,
			"somme": somme_us,
		})

		Peuplement.detruire_pool(pool)

	if mesures.size() >= 2:
		var petit: Dictionary = mesures[0]
		var grand: Dictionary = mesures[mesures.size() - 1]
		var noms := ["B2.1", "B2.2", "B2.3", "B2.4"]
		var vals_grand := [grand.b1, grand.b2, grand.b3, grand.b4]
		var vals_petit := [petit.b1, petit.b2, petit.b3, petit.b4]
		var idx_max: int = 0
		for i in range(1, 4):
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
		print("")
		print("ANALYSE : %s domine (%.3f us/ind a N=%d, %.3f a N=%d, ratio %.2f -- %s). Somme B2.1+B2.2+B2.3+B2.4 = %.3f us/ind a N=%d (attendu ~17 us par test_profil_phase_b.gd). Attaquer %s." % [
			noms[idx_max],
			vals_grand[idx_max], int(grand.N),
			vals_petit[idx_max], int(petit.N),
			ratio_dom,
			comportement,
			grand.somme, int(grand.N),
			noms[idx_max],
		])

func _nouvelle_direction(rng: RandomNumberGenerator) -> Vector3:
	var angle: float = rng.randf() * TAU
	return Vector3(cos(angle), 0.0, sin(angle))

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
