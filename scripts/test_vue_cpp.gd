extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_vue_cpp.gd
#
# Verrouille IndexSpatial::perception_lot : rend PAR AGENT la liste des ids
# VUS (rayon + cone oriente + occlusion visuelle corps-traverse). Sortie CSR
# { ids: PackedInt32Array, offsets: PackedInt32Array } -- vus de l'agent i =
# ids[offsets[i]..offsets[i+1]]. La separation est un CONSOMMATEUR distinct
# (separation_lot), pas testee ici : ce fichier verrouille la PERCEPTION
# (portage de scripts/perception.gd:_percevoir_cone_oriente sur la masse), pas
# la direction de repulsion qu'un consommateur en tire.
#
# CAS :
#  1) Voisin DEVANT dans le cone, aucun obstacle -> vu. ids[A]=[B].
#  2) Voisin DERRIERE (hors cone) -> non vu. ids[A]=[].
#  3) Voisin dans le cone mais CACHE par obstacle plus proche -> RETIRE.
#     ids[A]=[B] (obstacle vu), pas C (cache).
#  4) FORMAT CSR : offsets bien monotone, taille count+1, dernier == ids.size().
#  5) Occulteur K plus proche que J qui traverse le segment A->J, K hors cone.
#     ids[A]=[] (J cache par K, K hors cone donc pas vu).
#  6) Partage du voisinage entre unites co-case (4 unites sur 2 cases,
#     chacune voit selon son cone propre).

const Verif = preload("res://scripts/verif.gd")

var _v := Verif.new()

func _init() -> void:
	if not ClassDB.class_exists("IndexSpatial"):
		printerr("ECHEC: classe C++ 'IndexSpatial' absente -- extension_terrain non chargee ?")
		quit(1)
		return
	_executer()
	if _v.echecs() == 0:
		print("OK: IndexSpatial C++ perception_lot -- 6 cas de PERCEPTION passes (rayon + cone + occlusion corps-traverse, CSR ids/offsets)")
		quit(0)
	else:
		printerr("ECHEC: %d assertion(s) fausse(s)" % _v.echecs())
		quit(1)

# Extrait la liste des ids vus par l'agent i depuis le CSR.
static func _vus_de(perception: Dictionary, i: int) -> Array:
	var ids: PackedInt32Array = perception["ids"]
	var offsets: PackedInt32Array = perception["offsets"]
	var debut: int = offsets[i]
	var fin: int = offsets[i + 1]
	var out: Array = []
	var k: int = debut
	while k < fin:
		out.append(int(ids[k]))
		k += 1
	return out

func _executer() -> void:
	var rayon: float = 2.0
	var cos_moitie: float = cos(deg_to_rad(60.0))  # cone 120 deg total
	var largeur: float = 0.5
	var seuil: float = 0.001

	# ---- CAS 1 : voisin DEVANT, cone, aucun obstacle -> VU ----
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
	var p_1: Dictionary = index.perception_lot(positions_1, orient_x, opac_pleines, rayon, cos_moitie, largeur, seuil)
	var vus_A_1: Array = _vus_de(p_1, 0)
	_v.v(vus_A_1 == [1],
		"cas 1 : A doit voir B (id=1), ids[A] obtenu %s" % str(vus_A_1))
	var vus_B_1: Array = _vus_de(p_1, 1)
	_v.v(vus_B_1 == [],
		"cas 1 : B regarde +X, A derriere en -X hors cone -> ids[B] attendu [], obtenu %s" % str(vus_B_1))

	# ---- CAS 2 : voisin DERRIERE (hors cone) -> non vu ----
	var positions_2 := PackedVector3Array([
		Vector3(0.0, 12.0, 0.0),
		Vector3(-1.0, 12.0, 0.0),
	])
	var index2: RefCounted = ClassDB.instantiate("IndexSpatial")
	index2.configurer(positions_2.size())
	index2.ouvrir_niveau_planaire(1)
	index2.deplacer_lot(positions_2)
	var p_2: Dictionary = index2.perception_lot(positions_2, orient_x, opac_pleines, rayon, cos_moitie, largeur, seuil)
	var vus_A_2: Array = _vus_de(p_2, 0)
	_v.v(vus_A_2 == [],
		"cas 2 : A regarde +X, B en -X hors cone -> ids[A] attendu [], obtenu %s" % str(vus_A_2))

	# ---- CAS 3 : voisin dans cone mais CACHE par obstacle plus proche ----
	# A=(0,12,0), B obstacle=(0.5,12,0), C=(1.5,12,0). Segment A->C traverse
	# le disque de B (r_corps=largeur/2=0.25 ; distance laterale=0 <= 0.25)
	# et B plus proche -> C cache par B. A voit B (aucun obstacle plus proche).
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
	var p_3: Dictionary = index3.perception_lot(positions_3, orient_3, opac_3, rayon, cos_moitie, largeur, seuil)
	var vus_A_3: Array = _vus_de(p_3, 0)
	_v.v(vus_A_3 == [1],
		"cas 3 : A voit B (=1) mais pas C (=2) cache par B, obtenu %s" % str(vus_A_3))

	# ---- CAS 4 : FORMAT CSR bien forme (offsets/ids) ----
	var offsets_3: PackedInt32Array = p_3["offsets"]
	var ids_3: PackedInt32Array = p_3["ids"]
	_v.v(offsets_3.size() == positions_3.size() + 1,
		"cas 4 : offsets.size() attendu %d (count+1), obtenu %d" % [positions_3.size() + 1, offsets_3.size()])
	var monotone: bool = true
	var idx: int = 1
	while idx < offsets_3.size():
		if offsets_3[idx] < offsets_3[idx - 1]:
			monotone = false
			break
		idx += 1
	_v.v(monotone,
		"cas 4 : offsets doit etre monotone croissant, obtenu %s" % str(offsets_3))
	_v.v(ids_3.size() == offsets_3[offsets_3.size() - 1],
		"cas 4 : ids.size() = %d doit egaler offsets[count] = %d" % [ids_3.size(), offsets_3[offsets_3.size() - 1]])

	# ---- CAS 5 : OCCULTEUR PLUS PROCHE QUE LA CIBLE + traverse le segment ----
	# Cone etroit 45 deg pour que K sorte du cone :
	#   A=(0,12,0) regarde +X. J=(1.5,12,0) DANS le cone (angle 0).
	#   K=(0.3,12,0.2) d~=0.361 < d_J=1.5, angle 33.7 > 22.5 -> HORS cone.
	# Segment A->J traverse le disque de K (t=0.2, lat=0.2 <= r_corps=0.25).
	# ATTENDU : J cache par K, K hors cone -> ids[A] = [].
	var cos_moitie_5: float = cos(deg_to_rad(22.5))
	var positions_5 := PackedVector3Array([
		Vector3(0.0, 12.0, 0.0),
		Vector3(1.5, 12.0, 0.0),
		Vector3(0.3, 12.0, 0.2),
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
	var p_5: Dictionary = index5.perception_lot(positions_5, orient_5, opac_5, rayon, cos_moitie_5, largeur, seuil)
	var vus_A_5: Array = _vus_de(p_5, 0)
	_v.v(vus_A_5 == [],
		"cas 5 : J cache par K (corps traverse), K hors cone -> ids[A] attendu [], obtenu %s" % str(vus_A_5))

	# ---- CAS 6 : PARTAGE DU VOISINAGE ENTRE UNITES CO-CASE ----
	# 4 unites sur 2 cases (arete 2 : case (0,0) couvre [0,2[, case (1,0) [2,4[).
	# Tous regardent +X, ecart 1 en X.
	# ATTENDU (rayon=2, cone 120) :
	#   A voit B (d=1, devant). ids[A] = [B=1].
	#   B voit A (derriere hors cone) et C (devant). ids[B] = [C=2].
	#   C voit B (derriere hors cone) et D (devant). ids[C] = [D=3].
	#   D voit C (derriere hors cone). ids[D] = [].
	# Que A et B (case commune) rendent des ids differents prouve que le
	# voisinage PARTAGE est correctement filtre PAR UNITE. B au bord de sa case
	# (x=1.5) voit C dans case adjacente via le 3x3 partage.
	var positions_6 := PackedVector3Array([
		Vector3(0.5, 12.0, 0.5),
		Vector3(1.5, 12.0, 0.5),
		Vector3(2.5, 12.0, 0.5),
		Vector3(3.5, 12.0, 0.5),
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
	var p_6: Dictionary = index6.perception_lot(positions_6, orient_6, opac_6, rayon, cos_moitie, largeur, seuil)
	_v.v(_vus_de(p_6, 0) == [1],
		"cas 6 : ids[A] attendu [B=1], obtenu %s" % str(_vus_de(p_6, 0)))
	_v.v(_vus_de(p_6, 1) == [2],
		"cas 6 : ids[B] attendu [C=2] (A derriere hors cone), obtenu %s" % str(_vus_de(p_6, 1)))
	_v.v(_vus_de(p_6, 2) == [3],
		"cas 6 : ids[C] attendu [D=3] (B derriere hors cone), obtenu %s" % str(_vus_de(p_6, 2)))
	_v.v(_vus_de(p_6, 3) == [],
		"cas 6 : ids[D] attendu [] (C derriere hors cone), obtenu %s" % str(_vus_de(p_6, 3)))
