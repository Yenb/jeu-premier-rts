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
		print("OK: IndexSpatial C++ vue_lot -- 5 cas passes : voisin devant vu et pousse, voisin derriere ignore, voisin cache retire, parite du facteur d'occlusion avec occlusion.gd::facteur, occulteur lateral plus lointain que sa cible reste occulteur legitime (couverture boucle occlusion = tous les corps, pas seulement les plus proches)")
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

	# ---- CAS 5 : OCCULTEUR LATERAL avec distance(i,k) > distance(i,j) ----
	# Contre-exemple geometrique documente dans index_spatial.cpp : un occulteur
	# k plus loin de i que sa cible j peut quand meme couper le segment i->j.
	# distance(i,k)^2 = (t*d_j)^2 + L^2, si L est non negligeable devant d_j
	# alors distance(i,k) > d_j.
	#
	# Configuration (avec CONE ETROIT 45 deg pour ce cas, pour que K SORTE du
	# cone et ne soit pas lui-meme cible -- sinon auto-occlusion mutuelle
	# donnerait direction nulle, la comparaison serait indistinguable) :
	#   A percepteur a (0, 12, 0), regarde +X. cone_5 = 45 deg total.
	#   J cible a (0.6, 12, 0), distance = 0.6, angle 0 -> DANS le cone.
	#   K occulteur a (0.55, 12, 0.35), distance ~= 0.652 > 0.6, angle atan(0.35/0.55)
	#     = 32.5 deg > 22.5 deg (moitie de 45) -> HORS du cone (pas candidat cible).
	# Segment A->J : v = (0.6, 0, 0), longueur_carre = 0.36.
	# Projection de K sur AJ : t = (0.55 * 0.6 + 0.35 * 0) / 0.36 = 0.917 dans ]0,1[.
	# Point sur segment : (0.55, 12, 0). Distance laterale : 0.35 <= largeur 0.5.
	# K est donc un occulteur LEGITIME de J (t dans ]0,1[ et L <= largeur), MEME
	# si distance(i,k) > distance(i,j). Un tri par distance croissante placerait K
	# APRES J -- une boucle occulteurs limitee a `b < a` raterait K et considererait
	# J comme non-occulte a tort. La boucle actuelle (b != a) doit prendre K.
	#
	# COMPORTEMENT ATTENDU :
	#   - Sans le patch (bug b < a) : J vu (non occlus), pousse A vers -X.
	#     dirs_5[0] proche de (-1, 0, 0).
	#   - Avec le patch (b != a) : J occlus par K (opaque, dans le couloir), retire.
	#     K est hors cone donc pas candidat. Aucune poussee. dirs_5[0] = (0, 0, 0).
	var cos_moitie_5: float = cos(deg_to_rad(22.5))  # cone 45 deg total
	var positions_5 := PackedVector3Array([
		Vector3(0.0, 12.0, 0.0),     # 0 -- A percepteur
		Vector3(0.6, 12.0, 0.0),     # 1 -- J cible plus proche, dans le cone
		Vector3(0.55, 12.0, 0.35),   # 2 -- K occulteur plus loin, HORS cone
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
	# Prealable : distance(A, K) > distance(A, J).
	_v.v((positions_5[2] - positions_5[0]).length() > (positions_5[1] - positions_5[0]).length(),
		"cas 5 : prealable geometrique casse (distance(A,K) devrait > distance(A,J))")
	# Prealable : parite avec Occlusion.facteur -- K doit occulter le segment A->J.
	var obstacles_5 := [
		{ "position": Vector3(0.55, 12.0, 0.35), "proprietes": { "opacite": 1.0 } },
	]
	var facteur_5: float = Occlusion.facteur(positions_5[0], positions_5[1], obstacles_5, "opacite", largeur, [])
	_v.v(facteur_5 <= seuil,
		"cas 5 : Occlusion.facteur(A, J, [K], opacite=1) attendu <= seuil pour prouver K occulteur legitime, obtenu %f" % facteur_5)
	# CIBLE : direction nulle (J occlus par K, K pas cible car hors cone).
	# Un bug `b < a` donnerait dirs_5[0] proche de (-1, 0, 0) car J serait retenu.
	_v.v(dirs_5[0].length() < 1.0e-4,
		"cas 5 : direction attendue nulle (J occlus par K plus lointain, K hors cone) -- si dir ~= (-1,0,0) c'est le bug b < a qui a rate K comme occulteur ; obtenu %s" % str(dirs_5[0]))
