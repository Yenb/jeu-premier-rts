extends SceneTree

# ETAPE 2 -- Parite bit-a-bit passe 1 (senescence + stade + detection + mort
# vieillesse) portee en C++ vs oracle GDScript.
#
# Deux instances de `simulation_arbre.gd` (le module GDScript) sont montees a
# l'identique : memes reglages JSON, meme seed, memes MultiMesh/Monde/Couvert/
# Banque separes. La seule difference : SIM A tourne le chemin oracle
# (utilise_cpp = false), SIM B tourne la bascule cote C++ (utilise_cpp = true).
# Apres N ticks, on exige l'egalite EXACTE de `_ages` et `_slot_stade` --
# ce sont les colonnes que la passe 1 mute. La reproduction stochastique
# reste GDScript dans les DEUX chemins (portage RNG a l'etape 3), donc
# l'ordre des tirages est identique par construction.
#
# ROLLBACK / IMPACT : test isole, aucun autre fichier. Si rouge, la bascule
# `utilise_cpp = false` remet l'oracle sans effet de bord ; le portage C++
# se corrige seul.

const SimulationArbreGd = preload("res://jeu/bancs/simulation_arbre.gd")
const Monde = preload("res://scripts/monde.gd")
const ChampSaturationPlatGd = preload("res://scripts/champ_saturation_plat.gd")
const AttenteSeuil = preload("res://scripts/attente_seuil.gd")

const CHEMIN_JSON := "res://data/banc_peuplement_arbre.json"
const CHEMIN_TYPES := "res://data/types.json"
const TICKS := 100
const PAS := 0.25


func _init() -> void:
	if not ClassDB.class_exists("SimulationArbre"):
		printerr("ECHEC: classe C++ 'SimulationArbre' absente -- extension_terrain non chargee ?")
		quit(1)
		return

	var donnees: Dictionary = _lire_json(CHEMIN_JSON)
	if donnees.is_empty():
		printerr("ECHEC: catalogue local absent ou invalide (%s)" % CHEMIN_JSON)
		quit(1)
		return
	var types = _lire_json(CHEMIN_TYPES)
	if not (types is Dictionary) or not types.has("dynamique"):
		printerr("ECHEC: %s invalide ou paquet `dynamique` absent" % CHEMIN_TYPES)
		quit(1)
		return

	# ETAPE 6 : configurer pour exercer REPRODUCTION (parite RNG portee)
	# + morts vieillesse (reset colonnes plates de l'etape 4). Fertile a
	# tous les stades -> l'arbre initial pond des graines rapidement,
	# les tirages randf() du C++ vs GDScript doivent matcher. Longevite
	# a 0.3 -> les arbres meurent en quelques dizaines de secondes de sim
	# (100 ticks a pas 0.25s = 25s), le drainage morts vieillesse est
	# aussi exerce.
	var donnees_a: Dictionary = donnees.duplicate(true)
	var donnees_b: Dictionary = donnees.duplicate(true)
	donnees_a["stade_fertile_debut"] = 1
	donnees_a["stade_fertile_fin"] = 9
	donnees_a["graines_par_vie"] = 100.0
	donnees_a["longevite_min"] = 0.3
	donnees_a["longevite_max"] = 0.3
	donnees_b["stade_fertile_debut"] = 1
	donnees_b["stade_fertile_fin"] = 9
	donnees_b["graines_par_vie"] = 100.0
	donnees_b["longevite_min"] = 0.3
	donnees_b["longevite_max"] = 0.3

	var sim_a: RefCounted = SimulationArbreGd.new()
	var sim_b: RefCounted = SimulationArbreGd.new()

	_configurer_sim(sim_a, donnees_a, types.dynamique, false)
	_configurer_sim(sim_b, donnees_b, types.dynamique, true)

	sim_b.configurer_cpp(true)

	sim_a.naitre_initial(0.0, 0.0)
	sim_b.naitre_initial(0.0, 0.0)

	# ETAPE : verifie que le shadow C++ est synchro avec _monde APRES
	# naitre_initial. Le bug corrige : _naitre unitaire n'appelait pas
	# arbre_ajouter_lot, donc le shadow ratait l'arbre initial. Ce test
	# doit ECHOUER sans le fix, PASSER avec.
	var _rayon_comp_test: float = float(sim_b.get("_rayon_competition"))
	var _monde_sim_b: RefCounted = sim_b.get("_monde")
	var _voisins_monde_init: Array = _monde_sim_b.choses_dans_rayons_brut_xz(
		[Vector3(0.0, 12.0, 0.0)], _rayon_comp_test
	)
	var _simu_cpp_b_early: RefCounted = sim_b.get("_simu_cpp")
	var _px_probe: PackedFloat32Array = PackedFloat32Array()
	_px_probe.append(0.0)
	var _pz_probe: PackedFloat32Array = PackedFloat32Array()
	_pz_probe.append(0.0)
	var _voisins_shadow_init: Dictionary = _simu_cpp_b_early.arbre_choses_dans_rayons_brut_xz(
		_px_probe, _pz_probe, 12.0, _rayon_comp_test
	)
	var _monde_count_init: int = _voisins_monde_init[0].size()
	var _shadow_offsets_init: PackedInt32Array = _voisins_shadow_init.offsets
	var _shadow_count_init: int = _shadow_offsets_init[1]
	if _monde_count_init != _shadow_count_init:
		printerr("ECHEC: shadow C++ desynchro de _monde apres naitre_initial -- monde=%d voisins, shadow=%d (rayon=%.1f)" % [_monde_count_init, _shadow_count_init, _rayon_comp_test])
		quit(1)
		return

	var t: int = 0
	while t < TICKS:
		sim_a.avancer(PAS)
		sim_b.avancer(PAS)
		t += 1

	var ages_a: PackedFloat32Array = sim_a.get("_ages")
	var ages_b: PackedFloat32Array = sim_b.get("_ages")
	var stade_a: PackedInt32Array = sim_a.get("_slot_stade")
	var stade_b: PackedInt32Array = sim_b.get("_slot_stade")
	var libres_a: PackedByteArray = sim_a.get("_libres")
	var libres_b: PackedByteArray = sim_b.get("_libres")
	var pop_a: int = int(sim_a.population())
	var pop_b: int = int(sim_b.population())

	if pop_a != pop_b:
		printerr("ECHEC: population divergente apres %d ticks -- A=%d, B=%d" % [TICKS, pop_a, pop_b])
		quit(1)
		return
	if ages_a.size() != ages_b.size():
		printerr("ECHEC: capacite divergente -- A=%d, B=%d" % [ages_a.size(), ages_b.size()])
		quit(1)
		return

	var i: int = 0
	var n: int = ages_a.size()
	while i < n:
		if libres_a[i] != libres_b[i]:
			printerr("ECHEC: _libres[%d] divergent A=%d B=%d" % [i, libres_a[i], libres_b[i]])
			quit(1)
			return
		if libres_a[i] == 0:
			if ages_a[i] != ages_b[i]:
				printerr("ECHEC: _ages[%d] divergent A=%.9f B=%.9f (delta=%.9f)" % [i, ages_a[i], ages_b[i], ages_b[i] - ages_a[i]])
				quit(1)
				return
			if stade_a[i] != stade_b[i]:
				printerr("ECHEC: _slot_stade[%d] divergent A=%d B=%d" % [i, stade_a[i], stade_b[i]])
				quit(1)
				return
		i += 1

	# ETAPE 3 : PARITE BUFFERS RENDU. Sur les colonnes de SIM A (oracle
	# GDScript), appeler le helper GDScript et le C++, comparer bit-a-bit
	# les deux PackedFloat32Array (16 floats par slot : 12 transform + 4
	# color). Le SimulationArbre C++ de SIM B a deja recu initialiser_stable_rendu
	# via `_pousser_stables_cpp` -- on l'utilise pour le calcul.
	var pos_x_a: PackedFloat32Array = sim_a.get("_positions_x")
	var pos_y_a: PackedFloat32Array = sim_a.get("_positions_y")
	var pos_z_a: PackedFloat32Array = sim_a.get("_positions_z")
	var buf_gd: Dictionary = sim_a._construire_buffers_rendu_gd(n)
	var simu_cpp_b: RefCounted = sim_b.get("_simu_cpp")
	if simu_cpp_b == null:
		printerr("ECHEC: sim_b n'a pas d'instance _simu_cpp (bascule non montee ?)")
		quit(1)
		return
	var buf_cpp: Dictionary = simu_cpp_b.construire_buffers_rendu(
		n, libres_a, ages_a, stade_a, pos_x_a, pos_y_a, pos_z_a
	)
	var bt_gd: PackedFloat32Array = buf_gd.buffer_tronc
	var bt_cpp: PackedFloat32Array = buf_cpp.buffer_tronc
	var bf_gd: PackedFloat32Array = buf_gd.buffer_feuillage
	var bf_cpp: PackedFloat32Array = buf_cpp.buffer_feuillage
	if bt_gd.size() != bt_cpp.size() or bf_gd.size() != bf_cpp.size():
		printerr("ECHEC: taille buffers divergente -- tronc gd=%d cpp=%d, feuillage gd=%d cpp=%d" % [bt_gd.size(), bt_cpp.size(), bf_gd.size(), bf_cpp.size()])
		quit(1)
		return
	var m: int = bt_gd.size()
	var k: int = 0
	while k < m:
		if bt_gd[k] != bt_cpp[k]:
			printerr("ECHEC: buffer_tronc[%d] divergent gd=%.9f cpp=%.9f" % [k, bt_gd[k], bt_cpp[k]])
			quit(1)
			return
		if bf_gd[k] != bf_cpp[k]:
			printerr("ECHEC: buffer_feuillage[%d] divergent gd=%.9f cpp=%.9f" % [k, bf_gd[k], bf_cpp[k]])
			quit(1)
			return
		k += 1

	# PARITE RENDU COMPACT (prompt 2026-09-14). mettre_a_jour_buffers_rendu
	# doit produire un buffer compact (pop*16) contenant les slots vivants
	# ranges 0..pop-1 dans l'ordre croissant des slots data, plus la table
	# slot_data -> index_rendu (-1 si libre). Pour chaque slot vivant, la
	# tranche de 16 floats dans le buffer compact doit egaler la tranche du
	# meme slot dans le buffer de reference (construit sans cache). On
	# invalide le cache C++ pour forcer un recompute complet -> parite
	# bit-a-bit identique a construire_buffers_rendu.
	simu_cpp_b.invalider_cache_rendu()
	var res_maj: Dictionary = simu_cpp_b.mettre_a_jour_buffers_rendu(
		n, libres_a, ages_a, stade_a, pos_x_a, pos_y_a, pos_z_a,
		false, 0.0, 0.0, 0.0,
		false, 0.0, 0.0, -1.0,
		0.0, 0.0
	)
	var pop_compact: int = int(res_maj.get("pop", -1))
	var bt_compact: PackedFloat32Array = res_maj.buffer_tronc
	var bf_compact: PackedFloat32Array = res_maj.buffer_feuillage
	var srpd: PackedInt32Array = res_maj.slot_rendu_pour_data
	if pop_compact != pop_a:
		printerr("ECHEC: pop compact divergent -- attendu=%d, obtenu=%d" % [pop_a, pop_compact])
		quit(1)
		return
	if bt_compact.size() != pop_compact * 16 or bf_compact.size() != pop_compact * 16:
		printerr("ECHEC: taille buffer compact -- attendu=%d, tronc=%d, feuillage=%d" % [pop_compact * 16, bt_compact.size(), bf_compact.size()])
		quit(1)
		return
	if srpd.size() != n:
		printerr("ECHEC: slot_rendu_pour_data taille -- attendu=%d, obtenu=%d" % [n, srpd.size()])
		quit(1)
		return
	var rank_attendu: int = 0
	var ii: int = 0
	while ii < n:
		if libres_a[ii] == 1:
			if srpd[ii] != -1:
				printerr("ECHEC: srpd[%d] libre devrait etre -1, obtenu=%d" % [ii, srpd[ii]])
				quit(1)
				return
		else:
			if srpd[ii] != rank_attendu:
				printerr("ECHEC: srpd[%d] rank attendu=%d, obtenu=%d" % [ii, rank_attendu, srpd[ii]])
				quit(1)
				return
			var src_slot: int = ii * 16
			var dst_rank: int = rank_attendu * 16
			var kk: int = 0
			while kk < 16:
				if bt_compact[dst_rank + kk] != bt_gd[src_slot + kk]:
					printerr("ECHEC: buffer_tronc compact[slot=%d, rank=%d, k=%d] compact=%.9f ref=%.9f" % [ii, rank_attendu, kk, bt_compact[dst_rank + kk], bt_gd[src_slot + kk]])
					quit(1)
					return
				if bf_compact[dst_rank + kk] != bf_gd[src_slot + kk]:
					printerr("ECHEC: buffer_feuillage compact[slot=%d, rank=%d, k=%d] compact=%.9f ref=%.9f" % [ii, rank_attendu, kk, bf_compact[dst_rank + kk], bf_gd[src_slot + kk]])
					quit(1)
					return
				kk += 1
			rank_attendu += 1
		ii += 1

	# PARITE RENDU COMPACT AVEC CONE ACTIF (prompt 2026-09-15). Ferme le trou
	# ou une regression sur le chemin cone_actif=true resterait VERTE. On
	# invalide le cache C++, on appelle mettre_a_jour_buffers_rendu avec un
	# observateur en (0,0) et un cone regardant +X, demi-angle 90° (cos=0.0).
	# Rayon carre TRES GRAND -> le cercle n'exclut rien, seul le cone filtre.
	# On verifie : (a) au moins un slot vivant est exclu (filtre reellement
	# exerce, sinon equivalent a cone eteint), (b) au moins un slot vivant
	# est inclus, (c) srpd est -1 pour libres ET pour exclus, ranks croissants
	# pour inclus, (d) tranche 16 floats du buffer compact au rank egale
	# tranche 16 floats du buffer de reference (buf_gd) au slot data. Meme
	# patron d'assertion bit-a-bit que le cas cone_actif=false ci-dessus.
	simu_cpp_b.invalider_cache_rendu()
	var res_cone: Dictionary = simu_cpp_b.mettre_a_jour_buffers_rendu(
		n, libres_a, ages_a, stade_a, pos_x_a, pos_y_a, pos_z_a,
		true, 0.0, 0.0, 1.0e12,
		true, 1.0, 0.0, 0.0,
		0.0, 0.0
	)
	var pop_cone: int = int(res_cone.get("pop", -1))
	var bt_cone: PackedFloat32Array = res_cone.buffer_tronc
	var bf_cone: PackedFloat32Array = res_cone.buffer_feuillage
	var srpd_cone: PackedInt32Array = res_cone.slot_rendu_pour_data
	if srpd_cone.size() != n:
		printerr("ECHEC cone: srpd taille attendu=%d obtenu=%d" % [n, srpd_cone.size()])
		quit(1)
		return
	if bt_cone.size() != pop_cone * 16 or bf_cone.size() != pop_cone * 16:
		printerr("ECHEC cone: taille buffer compact -- attendu=%d, tronc=%d, feuillage=%d" % [pop_cone * 16, bt_cone.size(), bf_cone.size()])
		quit(1)
		return
	if pop_cone <= 0:
		printerr("ECHEC cone: aucun slot inclus (pop_cone=%d) -- cone trop restrictif pour cette pop" % pop_cone)
		quit(1)
		return
	if pop_cone >= pop_a:
		printerr("ECHEC cone: aucun slot exclu (pop_cone=%d, pop_a=%d) -- filtre non exerce, cas equivalent a cone eteint" % [pop_cone, pop_a])
		quit(1)
		return
	var rank_cone: int = 0
	var iic: int = 0
	while iic < n:
		if libres_a[iic] == 1:
			if srpd_cone[iic] != -1:
				printerr("ECHEC cone: srpd[%d] libre devrait etre -1, obtenu=%d" % [iic, srpd_cone[iic]])
				quit(1)
				return
		else:
			var rid: int = srpd_cone[iic]
			if rid == -1:
				iic += 1
				continue
			if rid != rank_cone:
				printerr("ECHEC cone: srpd[%d] rank attendu=%d, obtenu=%d" % [iic, rank_cone, rid])
				quit(1)
				return
			var src_slot_c: int = iic * 16
			var dst_rank_c: int = rank_cone * 16
			var kkc: int = 0
			while kkc < 16:
				if bt_cone[dst_rank_c + kkc] != bt_gd[src_slot_c + kkc]:
					printerr("ECHEC cone: buffer_tronc compact[slot=%d, rank=%d, k=%d] compact=%.9f ref=%.9f" % [iic, rank_cone, kkc, bt_cone[dst_rank_c + kkc], bt_gd[src_slot_c + kkc]])
					quit(1)
					return
				if bf_cone[dst_rank_c + kkc] != bf_gd[src_slot_c + kkc]:
					printerr("ECHEC cone: buffer_feuillage compact[slot=%d, rank=%d, k=%d] compact=%.9f ref=%.9f" % [iic, rank_cone, kkc, bf_cone[dst_rank_c + kkc], bf_gd[src_slot_c + kkc]])
					quit(1)
					return
				kkc += 1
			rank_cone += 1
		iic += 1
	if rank_cone != pop_cone:
		printerr("ECHEC cone: rank final=%d != pop_cone=%d" % [rank_cone, pop_cone])
		quit(1)
		return

	# ETAPE 5 : PARITE RNG. Le C++ instancie un RandomNumberGenerator du
	# moteur (meme classe que GDScript, meme PCG32). A seed egal, la suite
	# des randf() doit etre bit-a-bit identique. On tire N=1000 des deux
	# cotes et on compare.
	var seed_test: int = 20260910
	var rng_gd := RandomNumberGenerator.new()
	rng_gd.seed = seed_test
	var suite_gd: PackedFloat32Array = PackedFloat32Array()
	suite_gd.resize(1000)
	for k2 in range(1000):
		suite_gd[k2] = rng_gd.randf()
	simu_cpp_b.poser_seed_rng(seed_test)
	var suite_cpp: PackedFloat32Array = simu_cpp_b.tirer_randf_lot(1000)
	if suite_cpp.size() != 1000:
		printerr("ECHEC: tirer_randf_lot(1000) rend %d valeurs" % suite_cpp.size())
		quit(1)
		return
	for k3 in range(1000):
		if suite_gd[k3] != suite_cpp[k3]:
			printerr("ECHEC: randf[%d] divergent gd=%.9f cpp=%.9f" % [k3, suite_gd[k3], suite_cpp[k3]])
			quit(1)
			return
	# Verifier reproductibilite : re-seed et re-tirer, meme suite.
	simu_cpp_b.poser_seed_rng(seed_test)
	var suite_cpp_bis: PackedFloat32Array = simu_cpp_b.tirer_randf_lot(1000)
	for k4 in range(1000):
		if suite_cpp[k4] != suite_cpp_bis[k4]:
			printerr("ECHEC: re-seed non reproductible index=%d cpp=%.9f cpp_bis=%.9f" % [k4, suite_cpp[k4], suite_cpp_bis[k4]])
			quit(1)
			return

	print("OK: parite passe 1 + rendu + rng (1000 randf) GDScript vs C++ apres %d ticks (population=%d, capacite=%d, buffers=%d floats)" % [TICKS, pop_a, n, m])
	quit(0)


func _lire_json(chemin: String) -> Variant:
	if not FileAccess.file_exists(chemin):
		return {}
	var texte := FileAccess.get_file_as_string(chemin)
	if texte.is_empty():
		return {}
	return JSON.parse_string(texte)


func _configurer_sim(sim: RefCounted, donnees: Dictionary, types_dyn: Variant, activer_couvert_cpp: bool) -> void:
	sim.configurer(donnees)
	var mm_t := MultiMesh.new()
	mm_t.transform_format = MultiMesh.TRANSFORM_3D
	mm_t.use_colors = true
	mm_t.instance_count = 8
	var mm_f := MultiMesh.new()
	mm_f.transform_format = MultiMesh.TRANSFORM_3D
	mm_f.use_colors = true
	mm_f.instance_count = 8
	var monde = Monde.new()
	monde.structure_simple = true
	var couvert = ChampSaturationPlatGd.new()
	# ETAPE 9 : sim_b active la bascule couvert C++ ; sim_a garde oracle GDScript.
	if activer_couvert_cpp:
		couvert.activer_cpp()
	couvert.configurer(-100, -100, 100, 100)
	var banque = AttenteSeuil.new()
	sim.attacher(mm_t, mm_f, monde, couvert, banque, false, null, types_dyn)
