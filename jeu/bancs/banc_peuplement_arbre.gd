# BANC DE PEUPLEMENT ARBRE.
#
# Population d'arbres statiques qui pousse et se reproduit librement.
# Chaque arbre fertile (age dans [stade_fertile_debut, stade_fertile_fin])
# depose une graine toutes les `intervalle_graine` secondes dans un disque
# uniforme `rayon_graine` autour de lui. La graine LIT un CHAMP DE COUVERT
# pour decider si elle leve : couvert local strictement inferieur a
# `seuil_couvert` -> `_naitre` immediat ; sinon la graine entre dans une
# banque dormante et relit son couvert toutes les `intervalle_retest`
# secondes jusqu'a ce que l'ombrage local retombe (mort d'un voisin).
#
# CHAMP DE COUVERT (`_couvert`, Dictionary Vector2i -> float) : indexe par
# case, cote de case = `_taille_case`. Chaque arbre y ECRIT son ombrage
# (depot signe +1 a la naissance, retrait signe -1 a la mort, redepot au
# changement de stade). L'ombrage d'un arbre au stade N couvre les cases
# dans un carre de `_ombrage_par_stade[N-1].rayon_cases` autour de sa
# case, chacune recevant `magnitude`. Le retrait a la mort utilise la
# MEME formule avec signe inverse -- champ strictement symetrique, pas de
# derive. La graine LIT en O(1) (une clef du Dictionary) ; l'arbre ne LIT
# PAS le champ a cette etape (la mort par competition sera un chantier
# ulterieur).
#
# LIGNEE : meme esprit que jeu/Outil de jeu/champ_spatial.gd (case ->
# scalaire, aucun balayage global, canevas CLAUDE.md § LOCALITE SPATIALE),
# mais champ inline ici car le partage `champ_spatial` gere un COMPTE
# entier +1/-1 uniforme, alors qu'ici la magnitude est FLOAT et VARIABLE
# selon le stade (depot signe couvrant un carre de cases). Une extraction
# partagee sera envisageable si un autre banc en a besoin.
#
# COLONNES PARALLELES indexees par slot : `_ages`, `_horloges`, `_libres`,
# `_positions_x`, `_positions_z`, `_slot_stade`. Le hot path est UNE
# boucle par frame sur les slots vivants qui met a jour age, detecte les
# changements de stade (retrait+depot d'ombrage), fait tirer les graines
# des fertiles, ecrit les deux transforms. Aucune allocation heap dans la
# boucle : `_calc_params` renvoie un Vector4 (type valeur), Transform3D
# et Basis sont aussi des types valeur.
#
# DEUX MultiMesh partagees (tronc + feuillage) : un slot par arbre au MEME
# index dans les deux. Un slot mort est reutilise en priorite (patron
# FREE-LIST, jeu/PROTOCOLE_MULTIMESH.md § 1) ; sans slot libre, la
# capacite est doublee et les colonnes redimensionnees.
#
# CE BANC NE TOUCHE AUCUN MECANISME DU COEUR. Pas d'appel a
# scripts/peuplement.gd, scripts/stade.gd, scripts/mesh_catalogue.gd. Pas
# de fichier partage lu. Tout vit dans le banc et son JSON local.
#
# ECART FRAMEWORK : ce banc + son catalogue local sont neufs, voir
# CLAUDE.md § Frontiere.

extends Node

const FacteurVariance = preload("res://scripts/facteur_variance.gd")

const CHEMIN_CATALOGUE_LOCAL := "res://data/banc_peuplement_arbre.json"

# Hauteur du sol visuel monte par _monter_scene. La base des troncs y est posee.
const Y_SOL := 12.0

# Capacite initiale des deux MultiMesh (petite ; doublee par _agrandir_capacite
# quand aucun slot libre).
const CAPACITE_INITIALE := 8

# Position horizontale du premier arbre (l'arbre initial).
const POS_INITIALE := Vector2(0.0, 0.0)

# Cadence du releve population imprime dans la console (~1/s a 60 fps).
const CADENCE_RELEVE_POPULATION_FRAMES := 60

# Seuil de nettoyage d'une case du champ dont le cumul retombe sous cette
# valeur absolue (evite les zeros residuels de float qui polluent le Dict).
const EPS_COUVERT := 1.0e-6

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
var _stade_fertile_debut: int = 5
var _stade_fertile_fin: int = 7
var _taille_case: float = 20.0
var _seuil_couvert: float = 0.5
var _intervalle_retest: float = 5.0
var _ombrage_par_stade: Array = []
# Amplitudes de variance individuelle (JSON). Chaque arbre tire A LA NAISSANCE
# un facteur dans [1-amplitude, 1+amplitude] via scripts/facteur_variance.gd,
# lu ensuite sans re-tirage. Casse la synchronisation des cohortes.
var _variance_croissance: float = 0.3
var _variance_longevite: float = 0.3

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
# Stade courant de chaque slot (1..8 vivant, 0 = slot libre). Compare a
# _calculer_stade(age) chaque frame pour redeposer l'ombrage au franchissement.
var _slot_stade: PackedInt32Array = PackedInt32Array()
# Facteurs individuels tires a la naissance (FacteurVariance.tirer). Le
# facteur de croissance multiplie l'age reel pour donner l'age effectif qui
# pilote stade + fertilite + geometrie. Le facteur de longevite multiplie le
# seuil de mort (compare a l'age reel). Deux arbres nes ensemble n'atteignent
# pas les memes stades en meme temps et ne meurent pas au meme age.
var _facteur_croissance: PackedFloat32Array = PackedFloat32Array()
var _facteur_longevite: PackedFloat32Array = PackedFloat32Array()

# Population vivante courante, tenue en O(1) : incrementee dans _naitre,
# decrementee dans _liberer_slot. Aucun scan par frame.
var _population: int = 0
var _frames_depuis_releve: int = 0

# Champ scalaire d'ombrage par case (Vector2i -> float). Une entree est
# supprimee quand son cumul retombe sous EPS_COUVERT.
var _couvert: Dictionary = {}

# Banque de graines dormantes -- colonnes distinctes des arbres, sans rendu.
# Une graine porte une position (x,z) et une horloge de re-test. Retrait par
# swap-remove quand elle leve (couvert local descendu sous le seuil).
var _graines_x: PackedFloat32Array = PackedFloat32Array()
var _graines_z: PackedFloat32Array = PackedFloat32Array()
var _graines_horloge: PackedFloat32Array = PackedFloat32Array()

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
	if donnees.has("stade_fertile_debut"):
		_stade_fertile_debut = int(donnees.stade_fertile_debut)
	if donnees.has("stade_fertile_fin"):
		_stade_fertile_fin = int(donnees.stade_fertile_fin)
	_stade_fertile_debut = clampi(_stade_fertile_debut, 1, 8)
	_stade_fertile_fin = clampi(_stade_fertile_fin, _stade_fertile_debut, 8)
	if donnees.has("taille_case"):
		_taille_case = float(donnees.taille_case)
	if donnees.has("seuil_couvert"):
		_seuil_couvert = float(donnees.seuil_couvert)
	if donnees.has("intervalle_retest"):
		_intervalle_retest = float(donnees.intervalle_retest)
	if donnees.has("ombrage_par_stade"):
		_ombrage_par_stade = donnees.ombrage_par_stade
	if donnees.has("variance_croissance"):
		_variance_croissance = float(donnees.variance_croissance)
	if donnees.has("variance_longevite"):
		_variance_longevite = float(donnees.variance_longevite)
	if _stades.size() != 8:
		push_error("banc_peuplement_arbre : `stades` doit contenir 8 entrees (recu %d)" % _stades.size())
	if _durees.size() != 7:
		push_error("banc_peuplement_arbre : `durees_stades` doit contenir 7 entrees (recu %d)" % _durees.size())
	if _ombrage_par_stade.size() != 8:
		push_error("banc_peuplement_arbre : `ombrage_par_stade` doit contenir 8 entrees (recu %d)" % _ombrage_par_stade.size())
	_duree_croissance_totale = 0.0
	for d in _durees:
		_duree_croissance_totale += float(d)
	# Bornes de fertilite lues du JSON (stade_fertile_debut/fin, 1..8, inclus).
	_debut_fertilite = 0.0
	var k: int = 0
	while k < _stade_fertile_debut - 1 and k < _durees.size():
		_debut_fertilite += float(_durees[k])
		k += 1
	_fin_fertilite = 0.0
	k = 0
	while k < _stade_fertile_fin and k < _durees.size():
		_fin_fertilite += float(_durees[k])
		k += 1

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
	_slot_stade.resize(_capacite)
	_facteur_croissance.resize(_capacite)
	_facteur_longevite.resize(_capacite)
	_slots_libres.clear()
	# Ordre inverse : pop_back rendra les slots dans l'ordre croissant.
	var i: int = _capacite - 1
	while i >= 0:
		_libres[i] = 1
		_ages[i] = 0.0
		_horloges[i] = 0.0
		_positions_x[i] = 0.0
		_positions_z[i] = 0.0
		_slot_stade[i] = 0
		_facteur_croissance[i] = 1.0
		_facteur_longevite[i] = 1.0
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
		# Age reel compare au seuil de mort MODULE par la longevite individuelle.
		var seuil_mort: float = (_duree_croissance_totale + _duree_mort) * _facteur_longevite[i]
		if age_i >= seuil_mort:
			_liberer_slot(i)
			i += 1
			continue
		# Age effectif = age reel * facteur de croissance. Pilote stade,
		# fertilite et geometrie -- deux arbres nes ensemble n'atteignent
		# pas les memes stades en meme temps.
		var age_effectif: float = age_i * _facteur_croissance[i]
		var nouveau_stade: int = _calculer_stade(age_effectif)
		var ancien: int = _slot_stade[i]
		if nouveau_stade != ancien:
			if ancien > 0:
				_deposer_ombrage(_positions_x[i], _positions_z[i], ancien, -1)
			_deposer_ombrage(_positions_x[i], _positions_z[i], nouveau_stade, 1)
			_slot_stade[i] = nouveau_stade
		if age_effectif >= _debut_fertilite and age_effectif < _fin_fertilite:
			var h: float = _horloges[i] + pas
			while h >= _intervalle_graine:
				h -= _intervalle_graine
				_semer_pres_de(i)
			_horloges[i] = h
		_ecrire_slot(i, age_effectif)
		i += 1
	_tick_banque_graines(pas)
	_frames_depuis_releve += 1
	if _frames_depuis_releve >= CADENCE_RELEVE_POPULATION_FRAMES:
		_frames_depuis_releve = 0
		print("[arbre] population = %d, dormantes = %d, cases_couvertes = %d" % [_population, _graines_horloge.size(), _couvert.size()])

# Trouve le segment de stade contenant `age` et rend un Vector4 (h_tronc,
# l_tronc, h_feuillage, l_feuillage) interpole lineairement entre le stade
# courant et le suivant. Age au-dela du dernier segment : fige sur stade 8.
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

# Stade entier (1..8) correspondant a `age` : premier i tel que
# somme(_durees[0..i]) > age, avec fallback stade 8 quand age >= somme totale.
func _calculer_stade(age: float) -> int:
	var cumul: float = 0.0
	var n: int = _durees.size()
	var i: int = 0
	while i < n:
		cumul += float(_durees[i])
		if age < cumul:
			return i + 1
		i += 1
	return 8

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

# CHAMP DE COUVERT -- depot/retrait strictement symetrique (signe -1 =
# retrait). L'arbre au stade `stade` couvre les cases dans un carre de
# `_ombrage_par_stade[stade-1].rayon_cases` autour de sa case, chacune
# recevant `magnitude * signe`. Une case dont le cumul retombe sous
# EPS_COUVERT est retiree du Dictionary pour ne pas polluer les lectures.
func _deposer_ombrage(pos_x: float, pos_z: float, stade: int, signe: int) -> void:
	if stade < 1 or stade > 8:
		return
	if _ombrage_par_stade.size() < stade:
		return
	var conf: Dictionary = _ombrage_par_stade[stade - 1]
	var rayon: int = int(conf.get("rayon_cases", 0))
	var mag: float = float(conf.get("magnitude", 0.0)) * float(signe)
	if mag == 0.0:
		return
	var cx0: int = floori(pos_x / _taille_case)
	var cz0: int = floori(pos_z / _taille_case)
	var dcx: int = -rayon
	while dcx <= rayon:
		var dcz: int = -rayon
		while dcz <= rayon:
			var cle: Vector2i = Vector2i(cx0 + dcx, cz0 + dcz)
			var v: float = float(_couvert.get(cle, 0.0)) + mag
			if absf(v) < EPS_COUVERT:
				_couvert.erase(cle)
			else:
				_couvert[cle] = v
			dcz += 1
		dcx += 1

func _lire_couvert(pos_x: float, pos_z: float) -> float:
	var cle: Vector2i = Vector2i(floori(pos_x / _taille_case), floori(pos_z / _taille_case))
	return float(_couvert.get(cle, 0.0))

func _liberer_slot(i: int) -> void:
	var stade: int = _slot_stade[i]
	if stade > 0:
		_deposer_ombrage(_positions_x[i], _positions_z[i], stade, -1)
	_slot_stade[i] = 0
	_libres[i] = 1
	_ages[i] = 0.0
	_horloges[i] = 0.0
	_ecrire_slot_vide(i)
	_slots_libres.append(i)
	_population -= 1

# Naissance a une position horizontale donnee. Prend un slot libre en
# priorite ; agrandit la capacite s'il n'y en a plus. Depot d'ombrage stade 1.
func _naitre(pos_x: float, pos_z: float) -> void:
	if _slots_libres.is_empty():
		_agrandir_capacite()
	var i: int = _slots_libres.pop_back()
	_libres[i] = 0
	_ages[i] = 0.0
	_horloges[i] = 0.0
	_positions_x[i] = pos_x
	_positions_z[i] = pos_z
	_slot_stade[i] = 1
	_facteur_croissance[i] = FacteurVariance.tirer(_rng, _variance_croissance)
	_facteur_longevite[i] = FacteurVariance.tirer(_rng, _variance_longevite)
	_deposer_ombrage(pos_x, pos_z, 1, 1)
	_ecrire_slot(i, 0.0)
	_population += 1

func _semer_pres_de(parent_index: int) -> void:
	# Tirage UNIFORME dans le disque : angle uniforme + rayon = sqrt(u) * R.
	# `randf() * R` seul concentrerait la densite au centre (piege classique
	# de sampling : la surface annulaire croit lineairement avec r).
	var angle: float = _rng.randf() * TAU
	var rayon: float = sqrt(_rng.randf()) * _rayon_graine
	var pos_x: float = _positions_x[parent_index] + cos(angle) * rayon
	var pos_z: float = _positions_z[parent_index] + sin(angle) * rayon
	_deposer_graine(pos_x, pos_z)

# Depot d'une graine : couvert local sous le seuil -> leve immediate ;
# sinon entree dans la banque dormante (horloge = 0).
func _deposer_graine(pos_x: float, pos_z: float) -> void:
	if _lire_couvert(pos_x, pos_z) < _seuil_couvert:
		_naitre(pos_x, pos_z)
		return
	_graines_x.append(pos_x)
	_graines_z.append(pos_z)
	_graines_horloge.append(0.0)

# Boucle banque : chaque graine dormante voit son horloge avancer ; AU PLUS
# UN test par graine et par frame quand l'horloge atteint _intervalle_retest
# (horloge remise a zero apres un test rate, aucun rattrapage). Levee =
# swap-remove sur les trois colonnes + _naitre.
func _tick_banque_graines(pas: float) -> void:
	var i: int = 0
	while i < _graines_horloge.size():
		var h: float = _graines_horloge[i] + pas
		var doit_lever: bool = false
		if h >= _intervalle_retest:
			h = 0.0
			if _lire_couvert(_graines_x[i], _graines_z[i]) < _seuil_couvert:
				doit_lever = true
		if doit_lever:
			var px: float = _graines_x[i]
			var pz: float = _graines_z[i]
			var dernier: int = _graines_horloge.size() - 1
			if i != dernier:
				_graines_x[i] = _graines_x[dernier]
				_graines_z[i] = _graines_z[dernier]
				_graines_horloge[i] = _graines_horloge[dernier]
			_graines_x.resize(dernier)
			_graines_z.resize(dernier)
			_graines_horloge.resize(dernier)
			_naitre(px, pz)
			# i ne s'incremente pas : le slot i porte maintenant l'ancien dernier,
			# a re-examiner cette meme frame.
		else:
			_graines_horloge[i] = h
			i += 1

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
	_slot_stade.resize(nouvelle)
	_facteur_croissance.resize(nouvelle)
	_facteur_longevite.resize(nouvelle)
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
		_slot_stade[i] = 0
		_facteur_croissance[i] = 1.0
		_facteur_longevite[i] = 1.0
		_slots_libres.append(i)
		_ecrire_slot_vide(i)
		i -= 1
