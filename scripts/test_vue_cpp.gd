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
		print("OK: IndexSpatial C++ vue_lot -- 6 cas passes : cas 1-5 comportement, cas 6 partage voisinage co-case (unites B et C au bord de leurs cases voient bien la case adjacente via le 3x3 partage)")
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

	# ---- CAS 5 : OCCULTEUR PLUS PROCHE QUE LA CIBLE + traverse le segment ----
	# Modele : OCCLUSION VISUELLE CORPS TRAVERSE. Un voisin J est cache si
	# le segment percepteur -> J traverse le VOLUME (disque rayon = largeur/2)
	# d'un corps K PLUS PROCHE que J. Un corps plus loin ne peut jamais
	# cacher un corps plus proche (physiquement impossible) -- l'ancienne
	# config (K a 0.652 > d_J=0.6) etait incoherente et acceptee a tort par
	# le modele "couloir lateral <= largeur" (tolerance r_cible + r_occ). Elle
	# est retiree ; le nouveau cas encode le modele corps traverse.
	#
	# Configuration (cone etroit 45 deg pour que K sorte du cone) :
	#   A percepteur a (0, 12, 0), regarde +X. cone_5 = 45 deg total.
	#   J cible a (1.5, 12, 0), d=1.5, angle 0 -> DANS le cone.
	#   K occulteur a (0.3, 12, 0.2), d=sqrt(0.13)~=0.361 < d_J=1.5 -> PLUS PROCHE.
	#     angle = atan(0.2/0.3) = 33.7 deg > 22.5 -> HORS cone (pas cible).
	# Segment A->J = axe X (v = (1.5, 0), |v|^2 = 2.25).
	# Projection de K sur A->J : t = (0.3 * 1.5)/2.25 = 0.2 dans ]0,1[.
	# Point du segment = (0.3, 12, 0). Distance laterale de K = 0.2 <= r_corps
	# = largeur/2 = 0.25 -> K TRAVERSE le segment. K bloque J.
	#
	# ATTENDU : J cache par K (corps traverse). K hors cone -> ne pousse pas.
	# Aucun voisin vu ne contribue a la separation. dirs_5[0] = (0, 0, 0).
	var cos_moitie_5: float = cos(deg_to_rad(22.5))  # cone 45 deg total
	var positions_5 := PackedVector3Array([
		Vector3(0.0, 12.0, 0.0),     # 0 -- A percepteur
		Vector3(1.5, 12.0, 0.0),     # 1 -- J cible plus loin, dans le cone
		Vector3(0.3, 12.0, 0.2),     # 2 -- K occulteur PLUS PROCHE, hors cone, traverse segment
	])
	var orient_5 := PackedVector3Array([
		Vector3(1.0, 0.0, 0.0),
		Vector3(1.0, 0.0, 0.0),
		Vector3(1.0, 0.0, 0.0),
	])
	var opac_5 := PackedFloat32Array([1.0, 1.0, 1.0])
	var index5: RefCounted = ClassDB.instantiate("IndexSpatial")
	index5.configurer(positions_5.size())
	index5.ouvrir_niveau_planaire(1)
	index5.deplacer_lot(positions_5)
	var dirs_5: PackedVector3Array = index5.vue_lot(positions_5, orient_5, opac_5, rayon, cos_moitie_5, largeur, seuil)
	# Prealable : K est bien PLUS PROCHE que J.
	_v.v((positions_5[2] - positions_5[0]).length() < (positions_5[1] - positions_5[0]).length(),
		"cas 5 : prealable geometrique -- K doit etre plus proche que J pour occulter")
	# Prealable : distance laterale de K au segment A->J <= r_corps = largeur/2.
	var v_aj := positions_5[1] - positions_5[0]
	var ok := positions_5[2] - positions_5[0]
	var t_proj: float = ok.dot(v_aj) / v_aj.length_squared()
	var lat := ok - t_proj * v_aj
	_v.v(t_proj > 0.0 and t_proj < 1.0 and lat.length() <= 0.5 * largeur,
		"cas 5 : prealable geometrique -- segment A->J doit traverser le disque de K (t=%f, lat=%f, r_corps=%f)" % [t_proj, lat.length(), 0.5 * largeur])
	# CIBLE : direction nulle (J cache par K corps traverse, K hors cone).
	_v.v(dirs_5[0].length() < 1.0e-4,
		"cas 5 : direction attendue nulle (J cache par K corps traverse, K hors cone) -- obtenu %s" % str(dirs_5[0]))

	# ---- CAS 6 : PARTAGE DU VOISINAGE ENTRE UNITES CO-CASE ----
	# Chantier "collecte voisinage par case" : le voisinage 3x3 est collecte UNE
	# fois par case et partage par toutes les unites de la case. Chaque unite
	# obtient le meme resultat qu'avant (collecte par unite). Ce cas pose 4
	# unites reparties sur 2 cases (arete 2 : case (0,0,0) couvre [0,2[ x [0,2[
	# en X-Z, case (1,0,0) couvre [2,4[).
	#
	# Positions (Y=12 constant, ecart Z=0.5 pour cases (0,0,0) et (1,0,0)) :
	#   A a (0.5, 12, 0.5) -- case (0,0,0), orient +X.
	#   B a (1.5, 12, 0.5) -- case (0,0,0) MEME que A, orient +X.
	#   C a (2.5, 12, 0.5) -- case (1,0,0), orient +X.
	#   D a (3.5, 12, 0.5) -- case (1,0,0) MEME que C, orient +X.
	# Distances : A-B = 1, B-C = 1, C-D = 1, A-C = 2 (strict > rayon 2 exclu),
	# B-D = 2 (exclu), A-D = 3 (exclu).
	#
	# ATTENDU :
	#   A voit B (d=1, devant, dans cone). Aucun obstacle. Pousse -X. dir ~= (-1,0,0).
	#   B voit A (d=1, derriere B qui regarde +X -> HORS cone) et C (d=1, devant,
	#     dans cone). Seule C compte. Pousse -X. dir ~= (-1,0,0).
	#   C voit B (d=1, derriere -> HORS cone) et D (d=1, devant, dans cone).
	#     Pousse -X. dir ~= (-1,0,0).
	#   D voit C (d=1, derriere -> HORS cone). Aucun voisin devant. dir = zero.
	# Le fait que A et B (case commune) aient des dir differentes prouve que le
	# voisinage PARTAGE est correctement filtre PAR UNITE (chaque orient, chaque
	# position appliquent leurs propres filtres). B au bord de sa case (x=1.5)
	# voit bien C (case adjacente x=2.5) via le voisinage 3x3.
	var positions_6 := PackedVector3Array([
		Vector3(0.5, 12.0, 0.5),  # 0 -- A
		Vector3(1.5, 12.0, 0.5),  # 1 -- B (meme case que A)
		Vector3(2.5, 12.0, 0.5),  # 2 -- C
		Vector3(3.5, 12.0, 0.5),  # 3 -- D (meme case que C)
	])
	var orient_6 := PackedVector3Array([
		Vector3(1.0, 0.0, 0.0),
		Vector3(1.0, 0.0, 0.0),
		Vector3(1.0, 0.0, 0.0),
		Vector3(1.0, 0.0, 0.0),
	])
	var opac_6 := PackedFloat32Array([1.0, 1.0, 1.0, 1.0])
	var index6: RefCounted = ClassDB.instantiate("IndexSpatial")
	index6.configurer(positions_6.size())
	index6.ouvrir_niveau_planaire(1)
	index6.deplacer_lot(positions_6)
	var dirs_6: PackedVector3Array = index6.vue_lot(positions_6, orient_6, opac_6, rayon, cos_moitie, largeur, seuil)
	_v.v(dirs_6[0].distance_to(Vector3(-1.0, 0.0, 0.0)) < 1.0e-4,
		"cas 6 : dir_A attendue (-1,0,0), obtenu %s" % str(dirs_6[0]))
	_v.v(dirs_6[1].distance_to(Vector3(-1.0, 0.0, 0.0)) < 1.0e-4,
		"cas 6 : dir_B attendue (-1,0,0) (B au bord de sa case voit C dans case adjacente), obtenu %s" % str(dirs_6[1]))
	_v.v(dirs_6[2].distance_to(Vector3(-1.0, 0.0, 0.0)) < 1.0e-4,
		"cas 6 : dir_C attendue (-1,0,0), obtenu %s" % str(dirs_6[2]))
	_v.v(dirs_6[3].length() < 1.0e-4,
		"cas 6 : dir_D attendue nulle (aucun voisin dans le cone devant D), obtenu %s" % str(dirs_6[3]))
