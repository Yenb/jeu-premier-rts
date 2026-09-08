extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_vue_cpp.gd
#
# Verrouille IndexSpatial::vue_lot (chantier "vue avec occlusion en C++",
# 2026-09-08) : UN parcours du voisinage par frame, filtre par (rayon + cone
# d'angle autour de l'orientation) puis par occlusion, accumule la separation
# dans le MEME parcours. Sortie : direction unitaire horizontale (Y=0) par unite.
#
# QUATRE cas :
#  1) Voisin DEVANT dans le cone, aucun obstacle -> VU, l'unite est poussee
#     dans le sens oppose (repulsion). Direction unitaire non nulle.
#  2) Voisin DERRIERE (hors cone) -> IGNORE, aucune contribution.
#  3) Voisin dans le cone mais CACHE par un obstacle opaque -> RETIRE.
#  4) PARITE FACTEUR : le facteur d'occlusion calcule par occlusion.gd::facteur
#     sur les memes points est celui que vue_lot applique (test symbolique).

const Verif = preload("res://scripts/verif.gd")
const Occlusion = preload("res://scripts/occlusion.gd")

var _v := Verif.new()

func _init() -> void:
	if not ClassDB.class_exists("IndexSpatial"):
		printerr("ECHEC: classe C++ 'IndexSpatial' absente -- extension_terrain non chargee ?")
		quit(1)
		return
	_executer()
	if _v.echecs() == 0:
		print("OK: IndexSpatial C++ vue_lot -- voisin devant vu et pousse, voisin derriere ignore, voisin cache retire, parite du facteur d'occlusion avec occlusion.gd::facteur")
		quit(0)
	else:
		printerr("ECHEC: %d assertion(s) fausse(s)" % _v.echecs())
		quit(1)

func _executer() -> void:
	var rayon: float = 2.0
	var cos_moitie: float = cos(deg_to_rad(60.0))  # cone 120 total
	var largeur: float = 0.5
	var seuil: float = 0.001

	# ---- CAS 1 : voisin DEVANT, cone, aucun obstacle ----
	var positions_1 := PackedVector3Array([
		Vector3(0.0, 12.0, 0.0),
		Vector3(1.0, 12.0, 0.0),
	])
	var orient_x := PackedVector3Array([
		Vector3(1.0, 0.0, 0.0),
		Vector3(1.0, 0.0, 0.0),
	])
	var opac_pleines := PackedFloat32Array([1.0, 1.0])
	var index: RefCounted = ClassDB.instantiate("IndexSpatial")
	index.configurer(positions_1.size())
	index.ouvrir_niveau_planaire(1)
	index.deplacer_lot(positions_1)
	var dirs_1: PackedVector3Array = index.vue_lot(positions_1, orient_x, opac_pleines, rayon, cos_moitie, largeur, seuil)
	_v.v(dirs_1[0].distance_to(Vector3(-1.0, 0.0, 0.0)) < 1.0e-4,
		"cas 1 : A pas pousse loin de B devant, dir=%s (attendu ~(-1,0,0))" % str(dirs_1[0]))

	# ---- CAS 2 : voisin DERRIERE (hors cone) -> ignore ----
	var positions_2 := PackedVector3Array([
		Vector3(0.0, 12.0, 0.0),
		Vector3(-1.0, 12.0, 0.0),
	])
	var index2: RefCounted = ClassDB.instantiate("IndexSpatial")
	index2.configurer(positions_2.size())
	index2.ouvrir_niveau_planaire(1)
	index2.deplacer_lot(positions_2)
	var dirs_2: PackedVector3Array = index2.vue_lot(positions_2, orient_x, opac_pleines, rayon, cos_moitie, largeur, seuil)
	_v.v(dirs_2[0].length() < 1.0e-4,
		"cas 2 : A pousse alors que B est derriere (hors cone), dir=%s (attendu ~zero)" % str(dirs_2[0]))

	# ---- CAS 3 : voisin dans cone mais CACHE par obstacle opaque ----
	# A a (0,12,0), B obstacle a (0.5, 12, 0) opaque, C source a (1.5, 12, 0).
	# B est entre A et C, dans le couloir, opacite 1 -> C retire. Seul B pousse A.
	var positions_3 := PackedVector3Array([
		Vector3(0.0, 12.0, 0.0),
		Vector3(0.5, 12.0, 0.0),
		Vector3(1.5, 12.0, 0.0),
	])
	var orient_3 := PackedVector3Array([
		Vector3(1.0, 0.0, 0.0),
		Vector3(1.0, 0.0, 0.0),
		Vector3(1.0, 0.0, 0.0),
	])
	var opac_3 := PackedFloat32Array([1.0, 1.0, 1.0])
	var index3: RefCounted = ClassDB.instantiate("IndexSpatial")
	index3.configurer(positions_3.size())
	index3.ouvrir_niveau_planaire(1)
	index3.deplacer_lot(positions_3)
	var dirs_3: PackedVector3Array = index3.vue_lot(positions_3, orient_3, opac_3, rayon, cos_moitie, largeur, seuil)
	_v.v(dirs_3[0].distance_to(Vector3(-1.0, 0.0, 0.0)) < 1.0e-4,
		"cas 3 : direction A avec C cachee derriere B = %s (attendu ~(-1,0,0))" % str(dirs_3[0]))

	# ---- CAS 4 : parite du facteur d'occlusion ----
	# occlusion.gd::facteur sur A->C avec B obstacle opacite 0.5 doit rendre 0.5.
	# vue_lot avec meme geometrie et opacite 0.5 doit RETENIR C (facteur 0.5 > seuil).
	var depuis := Vector3(0.0, 12.0, 0.0)
	var vers := Vector3(1.5, 12.0, 0.0)
	var obstacles := [
		{ "position": Vector3(0.5, 12.0, 0.0), "proprietes": { "opacite": 0.5 } },
	]
	var facteur_ref: float = Occlusion.facteur(depuis, vers, obstacles, "opacite", largeur, [])
	_v.v(is_equal_approx(facteur_ref, 0.5),
		"cas 4 : occlusion.gd::facteur attendu 0.5 pour opacite=0.5, obtenu %f" % facteur_ref)
	var opac_4 := PackedFloat32Array([1.0, 0.5, 1.0])
	var index4: RefCounted = ClassDB.instantiate("IndexSpatial")
	index4.configurer(positions_3.size())
	index4.ouvrir_niveau_planaire(1)
	index4.deplacer_lot(positions_3)
	var dirs_4: PackedVector3Array = index4.vue_lot(positions_3, orient_3, opac_4, rayon, cos_moitie, largeur, seuil)
	# Facteur d'occlusion 0.5 > seuil 0.001 -> C RETENU. Direction non nulle,
	# unitaire, Y=0 (le tri-alignement A/B/C rend le vecteur strictement le
	# long de -X).
	_v.v(dirs_4[0].length() > 0.9 and is_equal_approx(dirs_4[0].y, 0.0),
		"cas 4 : direction avec obstacle attenue attendue unitaire Y=0, obtenu %s" % str(dirs_4[0]))
	_v.v(dirs_4[0].distance_to(Vector3(-1.0, 0.0, 0.0)) < 1.0e-4,
		"cas 4 : direction A/B/C alignes attendue (-1,0,0), obtenu %s" % str(dirs_4[0]))
