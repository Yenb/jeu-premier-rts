# BANC DE PEUPLEMENT ARBRE.
#
# Population d'arbres statiques qui pousse librement : chaque arbre fertile
# (age dans les stades 5 a 7) seme une graine invisible toutes les
# `intervalle_graine` secondes, ce qui fait naitre un nouvel arbre au stade
# 1 pres du parent (rayon horizontal `rayon_graine`). Deux MultiMesh (tronc
# + feuillage), UN slot par arbre au MEME index dans les deux. Un slot mort
# est reutilise en priorite (patron FREE-LIST, jeu/PROTOCOLE_MULTIMESH.md
# § 1) ; sans slot libre, la capacite des deux MultiMesh est doublee et
# les colonnes redimensionnees. Aucun plafond de population.
#
# COLONNES PARALLELES indexees par slot : `_ages`, `_horloges`, `_libres`,
# `_positions_x`, `_positions_z`. Le hot path est UNE boucle par frame sur
# les slots vivants : lecture/mutation des colonnes, ecriture directe des
# deux transforms (`set_instance_transform`) par arbre. Aucune allocation
# heap dans la boucle : `_calc_params` renvoie un Vector4 (type valeur),
# Transform3D et Basis sont aussi des types valeur. L'agrandissement de
# capacite est un evenement rare (cout amorti O(1) par naissance) qui vit
# hors boucle par frame.
#
# POURQUOI DEUX MultiMesh. Une MultiMesh porte UN mesh applique par UNE
# Transform3D par instance : une Basis n'encode qu'UN triplet d'echelles.
# Un slot ne peut donc pas scaler independamment tronc et feuillage. Deux
# MultiMesh a plusieurs slots (une par forme) levent la contrainte -- le
# meme index dans chaque MultiMesh appartient au meme arbre.
#
# CE BANC NE TOUCHE AUCUN MECANISME DU COEUR. Pas d'appel a
# scripts/peuplement.gd, scripts/stade.gd, scripts/mesh_catalogue.gd. Pas
# de fichier partage lu (types.json, mesh.json). Tout vit dans le banc et
# son JSON local.
#
# VERSION GROSSIERE, assumee par le prompt : pas de collision entre arbres,
# base des troncs au sol fixe Y_SOL, pas de double gate seuil_mere /
# seuil_cible du canevas `jeu/plantes/vegetation.gd`, pas de champ scalaire
# de saturation. Reproduction sans limite : la population peut croitre
# indefiniment.
#
# ECART FRAMEWORK : ce banc + son catalogue local sont neufs, voir
# CLAUDE.md § Frontiere.

extends Node

const CHEMIN_CATALOGUE_LOCAL := "res://data/banc_peuplement_arbre.json"

# Hauteur du sol visuel monte par _monter_scene. La base des troncs y est posee.
const Y_SOL := 12.0

# Capacite initiale des deux MultiMesh (petite ; doublee par _agrandir_capacite
# quand aucun slot libre).
const CAPACITE_INITIALE := 8

# Position horizontale du premier arbre (l'arbre initial).
const POS_INITIALE := Vector2(0.0, 0.0)

var _durees: PackedFloat32Array = PackedFloat32Array()
var _stades: Array = []
var _duree_mort: float = 180.0
var _duree_croissance_totale: float = 0.0
var _debut_fertilite: float = 0.0
var _fin_fertilite: float = 0.0
var _mode_test_rapide: bool = false
var _graine_rng: int = 20260910
var _intervalle_graine: float = 10.0
var _rayon_graine: float = 6.0

var _mm_tronc: MultiMesh = null
var _mm_feuillage: MultiMesh = null
var _noeud_tronc: MultiMeshInstance3D = null
var _noeud_feuillage: MultiMeshInstance3D = null

var _capacite: int = 0
var _ages: PackedFloat32Array = PackedFloat32Array()
var _horloges: PackedFloat32Array = PackedFloat32Array()
var _libres: PackedByteArray = PackedByteArray()
var _positions_x: PackedFloat32Array = PackedFloat32Array()
var _positions_z: PackedFloat32Array = PackedFloat32Array()
var _slots_libres: Array = []

var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_charger_reglages_locaux()
	_rng.seed = _graine_rng
	_monter_scene()
	_monter_population()
	if _stades.size() == 8:
		_naitre(POS_INITIALE.x, POS_INITIALE.y)

func _charger_reglages_locaux() -> void:
	if not FileAccess.file_exists(CHEMIN_CATALOGUE_LOCAL):
		push_error("banc_peuplement_arbre : catalogue local absent (%s)" % CHEMIN_CATALOGUE_LOCAL)
		return
	var texte := FileAccess.get_file_as_string(CHEMIN_CATALOGUE_LOCAL)
	if texte.is_empty():
		push_error("banc_peuplement_arbre : catalogue local vide (%s)" % CHEMIN_CATALOGUE_LOCAL)
		return
	var donnees = JSON.parse_string(texte)
	if not (donnees is Dictionary):
		push_error("banc_peuplement_arbre : catalogue local invalide (pas un objet)")
		return
	if donnees.has("durees_stades"):
		var brut_durees: Array = donnees.durees_stades
		_durees = PackedFloat32Array()
		for v in brut_durees:
			_durees.append(float(v))
	if donnees.has("stades"):
		_stades = donnees.stades
	if donnees.has("duree_mort"):
		_duree_mort = float(donnees.duree_mort)
	if donnees.has("mode_test_rapide"):
		_mode_test_rapide = bool(donnees.mode_test_rapide)
	if donnees.has("graine_rng"):
		_graine_rng = int(donnees.graine_rng)
	if donnees.has("intervalle_graine"):
		_intervalle_graine = float(donnees.intervalle_graine)
	if donnees.has("rayon_graine"):
		_rayon_graine = float(donnees.rayon_graine)
	if _stades.size() != 8:
		push_error("banc_peuplement_arbre : `stades` doit contenir 8 entrees (recu %d)" % _stades.size())
	if _durees.size() != 7:
		push_error("banc_peuplement_arbre : `durees_stades` doit contenir 7 entrees (recu %d)" % _durees.size())
	_duree_croissance_totale = 0.0
	for d in _durees:
		_duree_croissance_totale += float(d)
	# Fertilite = stades 5 a 7 : debut = fin de la transition 4->5 (somme des
	# quatre premieres durees), fin = fin de la transition 7->8 (= somme totale).
	_debut_fertilite = 0.0
	var k: int = 0
	while k < 4 and k < _durees.size():
		_debut_fertilite += float(_durees[k])
		k += 1
	_fin_fertilite = _duree_croissance_totale

func _monter_scene() -> void:
	var sol := MeshInstance3D.new()
	var plan := PlaneMesh.new()
	plan.size = Vector2(600.0, 600.0)
	var mat_sol := StandardMaterial3D.new()
	mat_sol.albedo_color = Color(0.3, 0.3, 0.3)
	plan.material = mat_sol
	sol.mesh = plan
	sol.position = Vector3(0.0, Y_SOL, 0.0)
	add_child(sol)
	var lumiere := DirectionalLight3D.new()
	lumiere.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(30.0), 0.0)
	lumiere.light_energy = 1.0
	lumiere.shadow_enabled = false
	add_child(lumiere)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 55.0, 55.0)
	camera.current = true
	camera.add_to_group(&"observateur")
	add_child(camera)
	camera.look_at(Vector3(0.0, Y_SOL, 0.0), Vector3.UP)

# Meshes UNITAIRES : BoxMesh 1x1x1 (tronc), CylinderMesh hauteur 1 rayon-bas
# 0.5 rayon-haut 0 (cone feuillage). MultiMesh instance_count =
# CAPACITE_INITIALE ; tous slots partent libres, transforms a echelle nulle.
func _monter_population() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 1.0, 1.0)
	var mat_tronc := StandardMaterial3D.new()
	mat_tronc.albedo_color = Color(0.35, 0.22, 0.12)
	box.material = mat_tronc
	_mm_tronc = MultiMesh.new()
	_mm_tronc.transform_format = MultiMesh.TRANSFORM_3D
	_mm_tronc.mesh = box
	_mm_tronc.instance_count = CAPACITE_INITIALE
	_noeud_tronc = MultiMeshInstance3D.new()
	_noeud_tronc.multimesh = _mm_tronc
	add_child(_noeud_tronc)

	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.5
	cone.height = 1.0
	var mat_feuillage := StandardMaterial3D.new()
	mat_feuillage.albedo_color = Color(0.15, 0.45, 0.2)
	cone.material = mat_feuillage
	_mm_feuillage = MultiMesh.new()
	_mm_feuillage.transform_format = MultiMesh.TRANSFORM_3D
	_mm_feuillage.mesh = cone
	_mm_feuillage.instance_count = CAPACITE_INITIALE
	_noeud_feuillage = MultiMeshInstance3D.new()
	_noeud_feuillage.multimesh = _mm_feuillage
	add_child(_noeud_feuillage)

	_capacite = CAPACITE_INITIALE
	_ages.resize(_capacite)
	_horloges.resize(_capacite)
	_libres.resize(_capacite)
	_positions_x.resize(_capacite)
	_positions_z.resize(_capacite)
	_slots_libres.clear()
	# Ordre inverse : pop_back rendra les slots dans l'ordre croissant.
	var i: int = _capacite - 1
	while i >= 0:
		_libres[i] = 1
		_ages[i] = 0.0
		_horloges[i] = 0.0
		_positions_x[i] = 0.0
		_positions_z[i] = 0.0
		_slots_libres.append(i)
		_ecrire_slot_vide(i)
		i -= 1

func _process(delta: float) -> void:
	if _stades.size() != 8 or _durees.size() != 7:
		return
	var pas: float = delta
	if _mode_test_rapide:
		pas *= 4.0
	# Capacite figee en debut de boucle : les naissances declenchees pendant
	# la frame peuvent agrandir la capacite ; les nouveaux slots seront tickes
	# a la frame suivante.
	var cap: int = _capacite
	var i: int = 0
	while i < cap:
		if _libres[i] == 1:
			i += 1
			continue
		var age_i: float = _ages[i] + pas
		_ages[i] = age_i
		if age_i >= _duree_croissance_totale + _duree_mort:
			_liberer_slot(i)
			i += 1
			continue
		if age_i >= _debut_fertilite and age_i < _fin_fertilite:
			var h: float = _horloges[i] + pas
			while h >= _intervalle_graine:
				h -= _intervalle_graine
				_naitre_pres_de(i)
			_horloges[i] = h
		_ecrire_slot(i, age_i)
		i += 1

# Trouve le segment de stade contenant `age` et rend un Vector4 (h_tronc,
# l_tronc, h_feuillage, l_feuillage) interpole lineairement entre le stade
# courant et le suivant. Age au-dela du dernier segment : fige sur stade 8.
# Vector4 = type valeur, aucune allocation heap.
func _calc_params(age: float) -> Vector4:
	var duree_cumulee: float = 0.0
	var n: int = _durees.size()
	var i: int = 0
	while i < n:
		var duree_segment: float = _durees[i]
		if age <= duree_cumulee + duree_segment:
			var t: float = 0.0
			if duree_segment > 0.0:
				t = (age - duree_cumulee) / duree_segment
			if t < 0.0:
				t = 0.0
			elif t > 1.0:
				t = 1.0
			var a: Dictionary = _stades[i]
			var b: Dictionary = _stades[i + 1]
			var ht: float = lerp(float(a.tronc.hauteur), float(b.tronc.hauteur), t)
			var lt: float = lerp(float(a.tronc.largeur), float(b.tronc.largeur), t)
			var hf: float = lerp(float(a.feuillage.hauteur), float(b.feuillage.hauteur), t)
			var lf: float = lerp(float(a.feuillage.largeur), float(b.feuillage.largeur), t)
			return Vector4(ht, lt, hf, lf)
		duree_cumulee += duree_segment
		i += 1
	var s: Dictionary = _stades[7]
	return Vector4(
		float(s.tronc.hauteur), float(s.tronc.largeur),
		float(s.feuillage.hauteur), float(s.feuillage.largeur))

# Ecrit les deux transforms du slot depuis les quatre parametres interpoles.
# Meshes sources UNITAIRES (hauteur 1, largeur 1). Empilement : base du
# tronc a y=Y_SOL (centre = Y_SOL + ht/2), base du feuillage au sommet du
# tronc (centre = Y_SOL + ht + hf/2). Feuillage a hauteur ou largeur nulle
# (stade 8) : Basis a echelle nulle -> instance invisible.
func _ecrire_slot(i: int, age: float) -> void:
	var p: Vector4 = _calc_params(age)
	var ht: float = p.x
	var lt: float = p.y
	var hf: float = p.z
	var lf: float = p.w
	var pos_x: float = _positions_x[i]
	var pos_z: float = _positions_z[i]
	var t_tronc := Transform3D(
		Basis.IDENTITY.scaled(Vector3(lt, ht, lt)),
		Vector3(pos_x, Y_SOL + ht * 0.5, pos_z))
	_mm_tronc.set_instance_transform(i, t_tronc)
	var t_feuillage: Transform3D
	if hf <= 0.0 or lf <= 0.0:
		t_feuillage = Transform3D(
			Basis.IDENTITY.scaled(Vector3.ZERO),
			Vector3(pos_x, Y_SOL + ht, pos_z))
	else:
		t_feuillage = Transform3D(
			Basis.IDENTITY.scaled(Vector3(lf, hf, lf)),
			Vector3(pos_x, Y_SOL + ht + hf * 0.5, pos_z))
	_mm_feuillage.set_instance_transform(i, t_feuillage)

# Slot libre : les deux instances a echelle nulle (invisibles). Piege du
# PROTOCOLE_MULTIMESH.md § 1 : sans ca, l'instance apparait a l'origine
# avec la geometrie du mesh a echelle 1.
func _ecrire_slot_vide(i: int) -> void:
	var t := Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3(0.0, Y_SOL, 0.0))
	_mm_tronc.set_instance_transform(i, t)
	_mm_feuillage.set_instance_transform(i, t)

func _liberer_slot(i: int) -> void:
	_libres[i] = 1
	_ages[i] = 0.0
	_horloges[i] = 0.0
	_ecrire_slot_vide(i)
	_slots_libres.append(i)

# Naissance a une position horizontale donnee. Prend un slot libre en
# priorite ; agrandit la capacite s'il n'y en a plus.
func _naitre(pos_x: float, pos_z: float) -> void:
	if _slots_libres.is_empty():
		_agrandir_capacite()
	var i: int = _slots_libres.pop_back()
	_libres[i] = 0
	_ages[i] = 0.0
	_horloges[i] = 0.0
	_positions_x[i] = pos_x
	_positions_z[i] = pos_z
	_ecrire_slot(i, 0.0)

func _naitre_pres_de(parent_index: int) -> void:
	var angle: float = _rng.randf() * TAU
	var rayon: float = _rng.randf() * _rayon_graine
	var pos_x: float = _positions_x[parent_index] + cos(angle) * rayon
	var pos_z: float = _positions_z[parent_index] + sin(angle) * rayon
	_naitre(pos_x, pos_z)

# Double la capacite des deux MultiMesh et des colonnes. Les nouveaux slots
# sont poses libres, transforms a echelle nulle. Godot conserve les
# transforms existantes lors d'une augmentation de instance_count. Cout
# amorti O(1) par naissance grace au doublement.
func _agrandir_capacite() -> void:
	var ancienne: int = _capacite
	var nouvelle: int = ancienne * 2
	if nouvelle < ancienne + 1:
		nouvelle = ancienne + 1
	_ages.resize(nouvelle)
	_horloges.resize(nouvelle)
	_libres.resize(nouvelle)
	_positions_x.resize(nouvelle)
	_positions_z.resize(nouvelle)
	_mm_tronc.instance_count = nouvelle
	_mm_feuillage.instance_count = nouvelle
	_capacite = nouvelle
	var i: int = nouvelle - 1
	while i >= ancienne:
		_libres[i] = 1
		_ages[i] = 0.0
		_horloges[i] = 0.0
		_positions_x[i] = 0.0
		_positions_z[i] = 0.0
		_slots_libres.append(i)
		_ecrire_slot_vide(i)
		i -= 1
