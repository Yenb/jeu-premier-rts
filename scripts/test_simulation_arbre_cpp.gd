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
const ChampSaturationPlat = preload("res://scripts/champ_saturation_plat.gd")
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

	var sim_a: RefCounted = SimulationArbreGd.new()
	var sim_b: RefCounted = SimulationArbreGd.new()

	_configurer_sim(sim_a, donnees.duplicate(true), types.dynamique)
	_configurer_sim(sim_b, donnees.duplicate(true), types.dynamique)

	sim_b.configurer_cpp(true)

	sim_a.naitre_initial(0.0, 0.0)
	sim_b.naitre_initial(0.0, 0.0)

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

	print("OK: parite passe 1 + rendu GDScript vs C++ apres %d ticks (population=%d, capacite=%d, buffers=%d floats)" % [TICKS, pop_a, n, m])
	quit(0)


func _lire_json(chemin: String) -> Variant:
	if not FileAccess.file_exists(chemin):
		return {}
	var texte := FileAccess.get_file_as_string(chemin)
	if texte.is_empty():
		return {}
	return JSON.parse_string(texte)


func _configurer_sim(sim: RefCounted, donnees: Dictionary, types_dyn: Variant) -> void:
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
	var couvert = ChampSaturationPlat.new()
	couvert.configurer(-100, -100, 100, 100)
	var banque = AttenteSeuil.new()
	sim.attacher(mm_t, mm_f, monde, couvert, banque, false, null, types_dyn)
