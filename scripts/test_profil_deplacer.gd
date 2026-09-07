extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_profil_deplacer.gd
#
# PROFIL du corps de monde.gd::deplacer sous structure_simple = true, N=100 000
# appels par run. Nomme la ligne coupable par un chiffre (temps moyen par appel
# en microsecondes), sous-etape par sous-etape. Le test REPRODUIT chaque
# sous-etape isolement pour ne PAS biaiser la mesure par le dispatch de
# fonction : la boucle mesuree ne fait QUE la sous-etape ciblee. Les refs
# d'individus sont pre-cachees pour ne pas mesurer par_id("p%d" % i).
#
# Ce fichier reste dans le depot : outil de diagnostic reproductible pour tout
# futur soupcon de regression sur ce hot path (banc peuplement en jeu = ~1,8
# us/appel a N=100 000 = 90% de la frame).

const Monde = preload("res://scripts/monde.gd")
const Objet = preload("res://scripts/objet.gd")

const N := 100_000
const RAYON_OUVERTURE := 10.0

func _init() -> void:
	var monde := Monde.new()
	monde.structure_simple = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260908
	var individus: Array = []
	individus.resize(N)
	for i in range(N):
		var pos := Vector3(rng.randf_range(-100.0, 100.0), 0.0, rng.randf_range(-100.0, 100.0))
		var o := Objet.fabriquer("p%d" % i, "t", pos, {})
		monde.ajouter(o, "t", pos)
		individus[i] = o
	# Ouvre une resolution (deplacer boucle sur _niveaux ; sans resolution
	# ouverte, la boucle est vide et le profil ne mesure que le dispatch de
	# fonction).
	var _r := monde.choses_dans_rayon(Vector3.ZERO, RAYON_OUVERTURE)

	# ---- MESURE 1 : deplacer complet, chaque unite bouge ----
	var t0: int = Time.get_ticks_usec()
	for i in range(N):
		var o = individus[i]
		o.position += Vector3(0.05, 0.0, 0.03)
		monde.deplacer(o)
	var t1: int = Time.get_ticks_usec()
	print("[profil] deplacer complet (mouvement) : %d us total, %.3f us/appel (N=%d)" % [t1 - t0, float(t1 - t0) / float(N), N])

	# ---- MESURE 2 : deplacer sans mouvement (fast-path : compare cle actuelle a visee, continue) ----
	var t2: int = Time.get_ticks_usec()
	for i in range(N):
		monde.deplacer(individus[i])
	var t3: int = Time.get_ticks_usec()
	print("[profil] deplacer sans mouvement (fast-path) : %d us total, %.3f us/appel" % [t3 - t2, float(t3 - t2) / float(N)])

	# ---- MESURE 3 : _case_pour(position, exposant) isole (contient _arete = pow + 3 divisions + 3 floori) ----
	var exposant: int = monde._exposant_pour(RAYON_OUVERTURE)
	var t4: int = Time.get_ticks_usec()
	for i in range(N):
		var _v := monde._case_pour(individus[i].position, exposant)
	var t5: int = Time.get_ticks_usec()
	print("[profil] _case_pour(position, exposant) : %d us total, %.3f us/appel" % [t5 - t4, float(t5 - t4) / float(N)])

	# ---- MESURE 4 : _arete(exposant) isole (juste pow) ----
	var t6: int = Time.get_ticks_usec()
	for i in range(N):
		var _a := monde._arete(exposant)
	var t7: int = Time.get_ticks_usec()
	print("[profil] _arete(exposant) (pow) : %d us total, %.3f us/appel" % [t7 - t6, float(t7 - t6) / float(N)])

	# ---- MESURE 5 : case_de.get(id, []) isole (alloc d'un Array vide par defaut a chaque appel) ----
	var niveau: Dictionary = monde._niveaux[exposant]
	var t8: int = Time.get_ticks_usec()
	for i in range(N):
		var _c = niveau.case_de.get(individus[i].id, [])
	var t9: int = Time.get_ticks_usec()
	print("[profil] niveau.case_de.get(id, []) : %d us total, %.3f us/appel" % [t9 - t8, float(t9 - t8) / float(N)])

	# ---- MESURE 6 : case_de[id] direct (sans alloc du default) ----
	var t10: int = Time.get_ticks_usec()
	for i in range(N):
		var _c = niveau.case_de[individus[i].id]
	var t11: int = Time.get_ticks_usec()
	print("[profil] niveau.case_de[id] direct : %d us total, %.3f us/appel" % [t11 - t10, float(t11 - t10) / float(N)])

	print("[profil] N=%d, structure_simple=true, une resolution ouverte (rayon %.1f -> exposant %d)" % [N, RAYON_OUVERTURE, exposant])
	quit(0)
