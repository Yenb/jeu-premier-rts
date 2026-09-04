extends SceneTree

# Test de PROFIL SCALING du pipeline de banc_peuplement.gd. But : identifier
# quel poste du _physics_process domine le cout par individu quand N croit,
# pour brancher l'optimisation sur une mesure et non une intuition.
#
# Ce test recopie la BOUCLE du _physics_process de jeu/bancs/banc_peuplement.gd
# (il n'appelle pas le banc lui-meme -- pas de rendu, pas de bruit de scene),
# et chronometre TROIS phases avec Time.get_ticks_usec() pour chaque individu :
#   Phase A : gestion cap_horloge + retirage direction + pose de
#             velocite_desiree_horizontale.
#   Phase B : Tick.tick_entite (donc Mouvement._pas_simple, snap sol, blocage
#             terrain, monde.deplacer).
#   Phase C : Peuplement.ecrire_transform (donc mm.set_instance_transform).
#
# Cinq tailles : N in {100, 500, 1000, 2000, 5000}, 100 ticks a delta=1/60 par
# taille, apres 3 ticks de warm-up (le premier tick apres spawn touche des
# branches froides -- au_sol=false qui bascule a true, gravite accumulee sur
# velocite.y=0). Sortie CSV lisible + une ligne d'analyse.
#
# La cadence est CONSTANTE (cadence_tick=1) : chaque tick calcule tout pour
# tous les individus, pas de LOD. C'est le pire cas -- si un poste s'ecroule
# ici, il s'ecroulera aussi en production.
#
# Le chronometrage lui-meme consomme du temps (six appels Time.get_ticks_usec
# par individu). C'est CONSTANT par individu : il ne fausse pas la comparaison
# entre phases ni la lecture d'un ratio par-individu de N=100 a N=5000.
#
# Godot 4 headless :
#   godot --headless --script scripts/test_profil_peuplement.gd

const Verif = preload("res://scripts/verif.gd")
const Peuplement = preload("res://scripts/peuplement.gd")
const Monde = preload("res://scripts/monde.gd")
const MeshCatalogue = preload("res://scripts/mesh_catalogue.gd")
const Tick = preload("res://scripts/tick.gd")
const CarteTerrain = preload("res://jeu/terrain/carte_terrain.gd")

const TAILLES: Array = [100, 500, 1000, 2000, 5000]
const TICKS_MESURES: int = 100
const TICKS_WARMUP: int = 3
const DELTA: float = 1.0 / 60.0
const GRAINE: int = 20260904

var _v := Verif.new()

func _init() -> void:
	_lancer.call_deferred()

func _lancer() -> void:
	await _executer()
	if _v.echecs() == 0:
		print("OK: scripts/test_profil_peuplement.gd -- profil scaling mesure sur %d tailles" % TAILLES.size())
		quit(0)
	else:
		printerr("ECHEC: %d assertion(s) fausse(s) -- voir push_error ci-dessus" % _v.echecs())
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
	print("N,total_ms_par_tick,A_us_total,A_us_par_ind,B_us_total,B_us_par_ind,C_us_total,C_us_par_ind")

	var par_ind_par_N: Array = []

	for N in TAILLES:
		var carte := CarteTerrain.new()
		var monde = Monde.new()
		var pool: Dictionary = Peuplement.creer_pool(N, mesh, scenario)
		_v.v(not pool.is_empty(), "N=%d : pool vide apres creer_pool" % N)
		if pool.is_empty():
			continue
		var errance: Dictionary = {}
		var rng := RandomNumberGenerator.new()
		rng.seed = GRAINE
		# Zone qui s'ouvre avec N pour ne pas empiler 5000 individus sur 80m ;
		# reste dans la carte plate par defaut (demi_cote=150, cote=2 -> +-300).
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
				push_error("N=%d : spawn a echoue tentative %d (poses=%d)" % [N, tentatives, poses])
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

		# Warm-up : purge des effets de premier tick (bascule au_sol, gravite
		# accumulee sur velocite.y=0, allocations paresseuses du Monde).
		for _w in range(TICKS_WARMUP):
			_tick_boucle_sans_mesure(pool, errance, rng, monde, carte, politique)

		var acc_a: int = 0
		var acc_b: int = 0
		var acc_c: int = 0
		var t_debut: int = Time.get_ticks_usec()
		for _tick_i in range(TICKS_MESURES):
			var abc: Array = _tick_boucle_avec_mesure(pool, errance, rng, monde, carte, politique)
			acc_a += abc[0]
			acc_b += abc[1]
			acc_c += abc[2]
		var t_total_us: int = Time.get_ticks_usec() - t_debut

		var total_ms_par_tick: float = float(t_total_us) / float(TICKS_MESURES) / 1000.0
		var a_par_ind: float = float(acc_a) / float(N) / float(TICKS_MESURES)
		var b_par_ind: float = float(acc_b) / float(N) / float(TICKS_MESURES)
		var c_par_ind: float = float(acc_c) / float(N) / float(TICKS_MESURES)

		print("%d,%.3f,%d,%.3f,%d,%.3f,%d,%.3f" % [
			N,
			total_ms_par_tick,
			acc_a, a_par_ind,
			acc_b, b_par_ind,
			acc_c, c_par_ind,
		])

		par_ind_par_N.append({
			"N": N,
			"a": a_par_ind,
			"b": b_par_ind,
			"c": c_par_ind,
		})

		Peuplement.detruire_pool(pool)

	if par_ind_par_N.size() >= 2:
		var premier: Dictionary = par_ind_par_N[0]
		var dernier: Dictionary = par_ind_par_N[par_ind_par_N.size() - 1]
		var nom_dominant: String = "A"
		var val_dominant: float = dernier.a
		if dernier.b > val_dominant:
			nom_dominant = "B"
			val_dominant = dernier.b
		if dernier.c > val_dominant:
			nom_dominant = "C"
			val_dominant = dernier.c
		var val_debut: float = premier.a
		if nom_dominant == "B":
			val_debut = premier.b
		elif nom_dominant == "C":
			val_debut = premier.c
		var ratio: float = 0.0
		if val_debut > 0.0:
			ratio = val_dominant / val_debut
		var verdict: String = "O(N) sain (ratio proche de 1)"
		if ratio > 1.5:
			verdict = "SUPER-LINEAIRE (cout par individu qui monte avec N)"
		elif ratio < 0.66:
			verdict = "SOUS-LINEAIRE (mesure suspecte : warm-up insuffisant ou bruit)"
		print("")
		print("ANALYSE : phase %s domine a N=%d (%.3f us/ind). Ratio par-individu N=%d/N=%d = %.2f -- %s" % [
			nom_dominant,
			int(dernier.N),
			val_dominant,
			int(dernier.N),
			int(premier.N),
			ratio,
			verdict,
		])

func _nouvelle_direction(rng: RandomNumberGenerator) -> Vector3:
	var angle: float = rng.randf() * TAU
	return Vector3(cos(angle), 0.0, sin(angle))

func _tick_boucle_sans_mesure(pool: Dictionary, errance: Dictionary, rng: RandomNumberGenerator, monde, carte, politique: Callable) -> void:
	for individu in pool.individus:
		var id: String = String(individu.id)
		if not errance.has(id):
			continue
		var etat: Dictionary = errance[id]
		etat["cap_horloge"] = float(etat.cap_horloge) - DELTA
		if float(etat.cap_horloge) <= 0.0:
			etat["direction"] = _nouvelle_direction(rng)
			etat["cap_horloge"] = rng.randf_range(3.0, 8.0)
		var p: Dictionary = individu.proprietes
		var vitesse: float = float(p.get("vitesse", 1.0))
		p["velocite_desiree_horizontale"] = (etat.direction as Vector3) * vitesse
		Tick.tick_entite(individu, politique, DELTA, monde, carte)
		Peuplement.ecrire_transform(pool, id)

func _tick_boucle_avec_mesure(pool: Dictionary, errance: Dictionary, rng: RandomNumberGenerator, monde, carte, politique: Callable) -> Array:
	var us_a: int = 0
	var us_b: int = 0
	var us_c: int = 0
	for individu in pool.individus:
		var id: String = String(individu.id)
		if not errance.has(id):
			continue
		var t_a: int = Time.get_ticks_usec()
		var etat: Dictionary = errance[id]
		etat["cap_horloge"] = float(etat.cap_horloge) - DELTA
		if float(etat.cap_horloge) <= 0.0:
			etat["direction"] = _nouvelle_direction(rng)
			etat["cap_horloge"] = rng.randf_range(3.0, 8.0)
		var p: Dictionary = individu.proprietes
		var vitesse: float = float(p.get("vitesse", 1.0))
		p["velocite_desiree_horizontale"] = (etat.direction as Vector3) * vitesse
		us_a += Time.get_ticks_usec() - t_a
		var t_b: int = Time.get_ticks_usec()
		Tick.tick_entite(individu, politique, DELTA, monde, carte)
		us_b += Time.get_ticks_usec() - t_b
		var t_c: int = Time.get_ticks_usec()
		Peuplement.ecrire_transform(pool, id)
		us_c += Time.get_ticks_usec() - t_c
	return [us_a, us_b, us_c]

func _charger_types() -> Dictionary:
	if not FileAccess.file_exists("res://data/types.json"):
		return {}
	var texte := FileAccess.get_file_as_string("res://data/types.json")
	var donnees = JSON.parse_string(texte)
	if donnees is Dictionary:
		return donnees
	return {}
