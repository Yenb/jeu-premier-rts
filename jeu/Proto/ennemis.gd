extends RefCounted

# Module ENNEMIS : la population hostile du proto -- spawn, IA (chasse /
# creuse / ramasse / pose de marches), faim, repousse mutuelle, corps-a-corps.
# Extrait de manager_proto.gd -- aucune logique nouvelle, un deplacement.
#
# Recoit a la construction :
# - carte (Resource) : la carte terrain, source de verite du sol.
# - cote_cellule (float) : arete d'une cellule.
# - tas (jeu/Proto/tas.gd) : le module matiere. Les ennemis creusent, ramassent
#   et posent des sous-cubes via lui (sommet_effectif, spawn_sous_cube_libre,
#   monde(), index_ajouter, index_retirer).
# - percepteur_position (Callable) : () -> Variant. Rend la position du joueur
#   (Vector3), ou null s'il n'y a pas de joueur -- reproduit le gate
#   "if _observateur == null: return" sans qu'ennemis connaisse l'observateur.
# - effondrer (Callable) : (cellule:Vector3i, idx:int, pos_impact:Vector3) ->
#   void. Delegue l'effondrement d'un bloc creuse au manager, qui seul connait
#   RessourcesTerrain (materiau, type d'effondrement) via get_tree().
# - spawn_actif (bool), spawn_demi_cote, intervalle_spawn_ennemi, max_ennemis,
#   ennemis_par_cycle, vitesse_ennemi, vie_ennemi : les reglages, copies des
#   exports du manager.
#
# Detient : _ennemis (Array de dicts), _horloge_spawn, _rng_ennemis (seede),
# _zone_spawn (node ou spawner, pose par le manager).
#
# Expose : tick(delta), ennemis() (l'Array, itere par le manager au rendu et au
# degat de contact), zone_spawn_set(node), frapper_melee(...),
# rafraichir_barre_ennemi(e) (le tick des balles, cote manager, l'appelle apres
# un hit).
#
# Regles : mouvement, gravite, collision terrain calcules sur carte.sommet et
# tas.sommet_effectif -- jamais de physique Godot. Ne cree aucun visuel : le
# rendu des ennemis (noeud, barres) reste au manager ; ennemis ne fait que lire
# e.noeud pour rafraichir les barres, jamais le fabriquer.

const CADENCE_ENNEMI_CREUSAGE := 0.5
const RAYON_ENNEMI_CHERCHE_BLOC := 3
const RAYON_ENNEMI_RAMASSE := 2.0
const PV_ENNEMI_CREUSAGE_PAR_COUP := 20
const NOURRITURE_MAX_ENNEMI := 500.0
const COUT_NOURRITURE_PAR_M := 1.0
const COUT_NOURRITURE_PAR_M_MONTEE := 5.0
const COUT_NOURRITURE_CREUSAGE_PAR_COUP := 3.0
const INTERVALLE_FAMINE := 5.0
const RAYON_REPOUSSE_ENNEMI := 0.9
const FORCE_REPOUSSE_ENNEMI := 15.0
const GRAVITE_ENNEMI := 18.0
const RAYON_HIT_ENNEMI := 0.5

var _carte: Resource = null
var _cote_cellule: float = 2.0
var _tas
var _percepteur: Callable
var _effondrer: Callable
var _spawn_actif: bool = true
var _spawn_demi_cote: float = 10.0
var _intervalle_spawn: float = 1.0
var _max_ennemis: int = 2500
var _ennemis_par_cycle: int = 5
var _vitesse_ennemi: float = 2.0
var _vie_ennemi: int = 3

var _ennemis: Array = []
var _horloge_spawn: float = 0.0
var _rng_ennemis := RandomNumberGenerator.new()
var _zone_spawn: Node3D = null

func _init(carte: Resource, cote_cellule: float, tas, percepteur_position: Callable,
		effondrer: Callable, spawn_actif: bool, spawn_demi_cote: float,
		intervalle_spawn_ennemi: float, max_ennemis: int, ennemis_par_cycle: int,
		vitesse_ennemi: float, vie_ennemi: int) -> void:
	_carte = carte
	_cote_cellule = cote_cellule
	_tas = tas
	_percepteur = percepteur_position
	_effondrer = effondrer
	_spawn_actif = spawn_actif
	_spawn_demi_cote = spawn_demi_cote
	_intervalle_spawn = intervalle_spawn_ennemi
	_max_ennemis = max_ennemis
	_ennemis_par_cycle = ennemis_par_cycle
	_vitesse_ennemi = vitesse_ennemi
	_vie_ennemi = vie_ennemi
	_rng_ennemis.seed = 20260827

func ennemis() -> Array:
	return _ennemis

func zone_spawn_set(node: Node3D) -> void:
	_zone_spawn = node

func tick(delta: float) -> void:
	_tick_spawn_ennemis(delta)
	_tick_ia_ennemis(delta)
	_repousser_ennemis(delta)

func _tick_spawn_ennemis(delta: float) -> void:
	if not _spawn_actif:
		return
	if _zone_spawn == null:
		return
	_horloge_spawn += delta
	if _horloge_spawn < _intervalle_spawn:
		return
	_horloge_spawn = 0.0
	for _n in range(_ennemis_par_cycle):
		if _ennemis.size() >= _max_ennemis:
			return
		_spawner_un_ennemi()

func _spawner_un_ennemi() -> void:
	var centre: Vector3 = _zone_spawn.global_position
	# Reject sampling : refuser une colonne mur (sommet > sommet_de_base) --
	# sinon l'ennemi apparait en haut du mur.
	var x := 0.0
	var z := 0.0
	var y := centre.y
	var trouve := false
	for essai in range(12):
		x = centre.x + _rng_ennemis.randf_range(-_spawn_demi_cote, _spawn_demi_cote)
		z = centre.z + _rng_ennemis.randf_range(-_spawn_demi_cote, _spawn_demi_cote)
		if _carte == null:
			trouve = true
			break
		var cx := int(floor(x / _cote_cellule))
		var cz := int(floor(z / _cote_cellule))
		var som: Variant = _carte.sommet_max_colonne(Vector2i(cx, cz))
		if som == null:
			continue
		if int(som) > _carte.sommet_de_base():
			continue
		y = (float(int(som)) + 1.0) * _cote_cellule + 0.4
		trouve = true
		break
	if not trouve:
		return
	var e := {
		"position": Vector3(x, y, z),
		"vitesse_y": 0.0,
		"vie": _vie_ennemi,
		"noeud": null,
		"est_mort": false,
		"nourriture": NOURRITURE_MAX_ENNEMI,
		"famine": 0.0,
		"etat": "chasse",
		"cible_cellule": null,
		"derniere_cible_creusee": null,
		"sc_porte": null,
		"cooldown_creusage": 0.0,
		"cooldown_grimpe": 0.0,
		"derniere_direction_chasse": Vector3(1.0, 0.0, 0.0),
	}
	_ennemis.append(e)

func _tick_ia_ennemis(delta: float) -> void:
	if not _percepteur.is_valid():
		return
	var p_obs: Variant = _percepteur.call()
	if p_obs == null:
		return
	var pos_obs: Vector3 = p_obs
	var i := 0
	while i < _ennemis.size():
		var e = _ennemis[i]
		if e.est_mort:
			# Snap XZ pour que deux cadavres proches tombent dans la MEME
			# colonne SC et s'empilent au lieu d'atterrir cote a cote.
			var cote_sous: float = _cote_cellule / 3.0
			var x_snap: float = floor(e.position.x / cote_sous) * cote_sous + cote_sous * 0.5
			var z_snap: float = floor(e.position.z / cote_sous) * cote_sous + cote_sous * 0.5
			var pos_cadavre := Vector3(x_snap, e.position.y, z_snap)
			_tas.spawn_sous_cube_libre(pos_cadavre, "cadavre", false)
			if e.noeud != null and is_instance_valid(e.noeud):
				e.noeud.queue_free()
			_ennemis.remove_at(i)
			continue
		var pos: Vector3 = e.position
		if float(e.get("cooldown_creusage", 0.0)) > 0.0:
			e.cooldown_creusage = max(0.0, float(e.cooldown_creusage) - delta)
		if float(e.get("cooldown_grimpe", 0.0)) > 0.0:
			e.cooldown_grimpe = max(0.0, float(e.cooldown_grimpe) - delta)
		var etat: String = String(e.get("etat", "chasse"))
		var vers: Vector3 = pos_obs - pos
		vers.y = 0.0
		if vers.length() > 0.1:
			e.derniere_direction_chasse = vers.normalized()
		match etat:
			"chasse":
				if vers.length() > 0.5:
					var direction := vers.normalized()
					var candidat: Vector3 = pos + direction * _vitesse_ennemi * delta
					if e.get("sc_porte", null) != null:
						# Poser DEVANT l'ennemi (1 sous-cube dans la direction
						# chasse). Le snap up gravite au tick suivant le fait
						# monter sur son cube. Escalier progressif vers le mur.
						var cote_sous: float = _cote_cellule / 3.0
						var dir_plate: Vector3 = e.derniere_direction_chasse
						var pos_devant: Vector3 = pos + dir_plate.normalized() * cote_sous
						var x_snap: float = floor(pos_devant.x / cote_sous) * cote_sous + cote_sous * 0.5
						var z_snap: float = floor(pos_devant.z / cote_sous) * cote_sous + cote_sous * 0.5
						var y_sol_v: Variant = _tas.sommet_effectif(x_snap, z_snap, pos.y + cote_sous) if dir_plate.length_squared() >= 0.0001 else null
						if y_sol_v != null:
							var y_pose: float = float(y_sol_v) + cote_sous * 0.5
							var sc: Dictionary = e.sc_porte
							sc.position = Vector3(x_snap, y_pose, z_snap)
							sc.vitesse_y = 0.0
							sc.noeud = null
							_tas.monde().ajouter(sc, "sous_cube", sc.position)
							_tas.index_ajouter(sc)
							e.sc_porte = null
					if _mouvement_bloque_par_terrain(pos, candidat):
						# Cooldown obligatoire sinon boucle chasse/cherche_sc
						# contre un mur infranchissable.
						if float(e.cooldown_grimpe) <= 0.0:
							var cellule: Variant = _ennemi_bloc_creusable_proche(pos, RAYON_ENNEMI_CHERCHE_BLOC)
							if cellule != null:
								e.etat = "creuse"
								e.cible_cellule = cellule
							else:
								e.cooldown_grimpe = 3.0
					else:
						pos = candidat
			"creuse":
				if e.get("cible_cellule", null) == null:
					e.etat = "chasse"
				elif float(e.cooldown_creusage) <= 0.0:
					var casse: bool = _ennemi_creuser(e.cible_cellule as Vector3i)
					e.cooldown_creusage = CADENCE_ENNEMI_CREUSAGE
					if e.nourriture > 0.0:
						e.nourriture = max(0.0, float(e.nourriture) - COUT_NOURRITURE_CREUSAGE_PAR_COUP)
						_rafraichir_barre_nourriture_ennemi(e)
					if casse:
						e.derniere_cible_creusee = e.cible_cellule
						e.cible_cellule = null
						e.etat = "cherche_sc"
			"cherche_sc":
				var sc: Variant = _ennemi_ramasser_sc_proche(pos, RAYON_ENNEMI_RAMASSE)
				if sc != null:
					e.sc_porte = sc
					e.etat = "pose"
				else:
					e.cooldown_grimpe = 3.0
					e.etat = "chasse"
			"pose":
				# Pose vers la cellule creusee, pas vers le joueur -- sinon la
				# marche atterrit a cote au lieu de servir a monter.
				if e.get("sc_porte", null) != null:
					var dir_pose: Vector3 = e.derniere_direction_chasse
					if e.get("derniere_cible_creusee", null) != null:
						var cible: Vector3i = e.derniere_cible_creusee
						var centre_cellule := Vector3(
							float(cible.x) * _cote_cellule + _cote_cellule * 0.5,
							pos.y,
							float(cible.z) * _cote_cellule + _cote_cellule * 0.5)
						var vers_cellule: Vector3 = centre_cellule - pos
						vers_cellule.y = 0.0
						if vers_cellule.length() > 0.001:
							dir_pose = vers_cellule.normalized()
					var pose_ok: bool = _ennemi_poser_sc_devant(pos, dir_pose, e.sc_porte)
					if pose_ok:
						e.sc_porte = null
				e.etat = "chasse"
		if _carte != null:
			var y_haut: Variant = _tas.sommet_effectif(pos.x, pos.z, pos.y + _cote_cellule / 3.0 * 0.5)
			if y_haut != null:
				var sol_y: float = float(y_haut) + 0.4
				if pos.y > sol_y:
					e.vitesse_y -= GRAVITE_ENNEMI * delta
					pos.y += e.vitesse_y * delta
					if pos.y < sol_y:
						pos.y = sol_y
						e.vitesse_y = 0.0
				else:
					pos.y = sol_y
					e.vitesse_y = 0.0
		var pos_avant: Vector3 = e.position
		var deplacement := Vector3(pos.x - pos_avant.x, 0.0, pos.z - pos_avant.z)
		var dist := deplacement.length()
		var dy: float = pos.y - pos_avant.y
		var cout: float = COUT_NOURRITURE_PAR_M * dist
		if dy > 0.0:
			cout += COUT_NOURRITURE_PAR_M_MONTEE * dy
		if cout > 0.0 and e.nourriture > 0.0:
			e.nourriture = max(0.0, e.nourriture - cout)
			_rafraichir_barre_nourriture_ennemi(e)
		if e.nourriture <= 0.0:
			e.famine += delta
			if e.famine >= INTERVALLE_FAMINE:
				e.famine -= INTERVALLE_FAMINE
				e.vie -= 1
				if e.vie <= 0:
					e.est_mort = true
				_rafraichir_barre_ennemi(e)
		else:
			e.famine = 0.0
		e.position = pos
		i += 1

func _repousser_ennemis(_delta: float) -> void:
	if _ennemis.is_empty():
		return
	var cote := RAYON_REPOUSSE_ENNEMI
	var buckets: Dictionary = {}
	for idx in range(_ennemis.size()):
		var e = _ennemis[idx]
		if e.est_mort:
			continue
		var cx := int(floor((e.position as Vector3).x / cote))
		var cz := int(floor((e.position as Vector3).z / cote))
		var cle := Vector2i(cx, cz)
		if not buckets.has(cle):
			buckets[cle] = []
		(buckets[cle] as Array).append(idx)
	var voisins_offset := [Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]
	for cle in buckets.keys():
		var ici: Array = buckets[cle]
		for i_a in range(ici.size()):
			var a = _ennemis[ici[i_a]]
			for j in range(i_a + 1, ici.size()):
				_appliquer_repousse_ennemis(a, _ennemis[ici[j]])
		for off in voisins_offset:
			var voisin_cle := Vector2i(cle.x + off.x, cle.y + off.y)
			if not buckets.has(voisin_cle):
				continue
			var la: Array = buckets[voisin_cle]
			for idx_a in ici:
				var a2 = _ennemis[idx_a]
				for idx_b in la:
					_appliquer_repousse_ennemis(a2, _ennemis[idx_b])

func _appliquer_repousse_ennemis(a: Dictionary, b: Dictionary) -> void:
	if a.est_mort or b.est_mort:
		return
	var seuil := RAYON_REPOUSSE_ENNEMI
	var seuil2 := seuil * seuil
	var vers: Vector3 = (b.position as Vector3) - (a.position as Vector3)
	vers.y = 0.0
	var d2: float = vers.length_squared()
	if d2 >= seuil2:
		return
	var dir: Vector3
	var chevauchement: float
	if d2 <= 0.0001:
		# Empilement exact : brise la symetrie par un push cardinal fixe.
		dir = Vector3(1.0, 0.0, 0.0)
		chevauchement = seuil
	else:
		var d: float = sqrt(d2)
		chevauchement = seuil - d
		dir = vers / d
	# Separation instantanee : moitie du chevauchement, sans delta.
	var push: Vector3 = dir * chevauchement * 0.5
	var pos_a_apres: Vector3 = (a.position as Vector3) - push
	var pos_b_apres: Vector3 = (b.position as Vector3) + push
	if not _mouvement_bloque_par_terrain(a.position, pos_a_apres):
		a.position = pos_a_apres
	if not _mouvement_bloque_par_terrain(b.position, pos_b_apres):
		b.position = pos_b_apres

func _mouvement_bloque_par_terrain(pos_a: Vector3, pos_b: Vector3) -> bool:
	if _carte == null:
		return false
	var y_a_v: Variant = _tas.sommet_effectif(pos_a.x, pos_a.z, pos_a.y)
	var y_b_v: Variant = _tas.sommet_effectif(pos_b.x, pos_b.z, pos_a.y)
	if y_a_v == null or y_b_v == null:
		return false
	return float(y_b_v) - float(y_a_v) > _cote_cellule

func _ennemi_poser_sc_devant(pos_ennemi: Vector3, direction: Vector3, sc_a_poser: Variant) -> bool:
	if sc_a_poser == null:
		return false
	if _tas.monde() == null:
		return false
	var dir_plate := Vector3(direction.x, 0.0, direction.z)
	if dir_plate.length_squared() < 0.0001:
		return false
	var cote_sous: float = _cote_cellule / 3.0
	var pos_devant: Vector3 = pos_ennemi + dir_plate.normalized() * _cote_cellule
	var x_snap: float = floor(pos_devant.x / cote_sous) * cote_sous + cote_sous * 0.5
	var z_snap: float = floor(pos_devant.z / cote_sous) * cote_sous + cote_sous * 0.5
	var y_sol_v: Variant = _tas.sommet_effectif(x_snap, z_snap, pos_ennemi.y + cote_sous)
	if y_sol_v == null:
		return false
	var y_pose: float = float(y_sol_v) + cote_sous * 0.5
	var sc: Dictionary = sc_a_poser
	sc.position = Vector3(x_snap, y_pose, z_snap)
	sc.vitesse_y = 0.0
	sc.noeud = null  # sera recree au prochain _bascule_rendu_tas
	_tas.monde().ajouter(sc, "sous_cube", sc.position)
	_tas.index_ajouter(sc)
	return true

func _ennemi_ramasser_sc_proche(pos_ennemi: Vector3, rayon_metres: float) -> Variant:
	if _tas.monde() == null:
		return null
	var proches: Array = _tas.monde().choses_dans_rayon(pos_ennemi, rayon_metres)
	if proches.is_empty():
		return null
	var meilleur = null
	var meilleur_d2: float = INF
	for e in proches:
		var sc: Dictionary = e.chose
		if sc.get("matiere", "") == "pelle" or sc.get("matiere", "") == "beche":
			continue
		var d2: float = (sc.position as Vector3).distance_squared_to(pos_ennemi)
		if d2 < meilleur_d2:
			meilleur_d2 = d2
			meilleur = sc
	if meilleur == null:
		return null
	if meilleur.get("noeud", null) != null and is_instance_valid(meilleur.noeud):
		(meilleur.noeud as Node3D).queue_free()
		meilleur.noeud = null
	_tas.index_retirer(meilleur)
	_tas.monde().retirer(meilleur.id)
	return meilleur

func _ennemi_creuser(cellule: Vector3i) -> bool:
	if _carte == null:
		return false
	if cellule.y <= _carte.couche_base:
		return false
	if _carte.item_de(cellule) != _carte.ITEM_DEFAUT:
		return false
	# Iterer du HAUT vers le bas pour prendre le premier sous-cube plein --
	# viser idx 16 en dur bloquait au 2e cycle (idx 16 casse -> false a vie).
	var idx: int = -1
	for iy in range(2, -1, -1):
		for iz in range(3):
			for ix in range(3):
				var candidat: int = ix + iy * 3 + iz * 9
				if _carte.est_sous_cube_plein(cellule, candidat):
					idx = candidat
					break
			if idx >= 0:
				break
		if idx >= 0:
			break
	if idx < 0:
		return false  # cellule entierement videe
	var casse: bool = _carte.ajouter_pv_sous_cube(cellule, idx, PV_ENNEMI_CREUSAGE_PAR_COUP)
	if casse:
		var cote_sous: float = _cote_cellule / 3.0
		var pos_impact := Vector3(
			float(cellule.x) * _cote_cellule + _cote_cellule * 0.5,
			float(cellule.y) * _cote_cellule + (2.0 + 0.5) * cote_sous,
			float(cellule.z) * _cote_cellule + _cote_cellule * 0.5)
		_effondrer.call(cellule, idx, pos_impact)
	return casse

func _ennemi_bloc_creusable_proche(pos_ennemi: Vector3, rayon_cases: int) -> Variant:
	if _carte == null:
		return null
	var cote_sous: float = _cote_cellule / 3.0
	var y_som_ennemi_v: Variant = _tas.sommet_effectif(pos_ennemi.x, pos_ennemi.z, pos_ennemi.y + cote_sous * 0.5)
	if y_som_ennemi_v == null:
		return null
	var couche_ennemi: int = int(floor(float(y_som_ennemi_v) / _cote_cellule))
	var col_e := Vector2i(int(floor(pos_ennemi.x / _cote_cellule)), int(floor(pos_ennemi.z / _cote_cellule)))
	var meilleur: Variant = null
	var meilleur_d2: int = 1 << 30
	for dx in range(-rayon_cases, rayon_cases + 1):
		for dz in range(-rayon_cases, rayon_cases + 1):
			if dx == 0 and dz == 0:
				continue
			var col := Vector2i(col_e.x + dx, col_e.y + dz)
			var x_centre: float = float(col.x) * _cote_cellule + _cote_cellule * 0.5
			var z_centre: float = float(col.y) * _cote_cellule + _cote_cellule * 0.5
			var y_som_cible_v: Variant = _tas.sommet_effectif(x_centre, z_centre, INF)
			if y_som_cible_v == null:
				continue
			var couche_cible: int = int(floor(float(y_som_cible_v) / _cote_cellule))
			if abs(couche_cible - couche_ennemi) > 1:
				continue
			# Sommet TERRAIN pour cibler un bloc reel, pas un sc libre au-dessus.
			var som_terrain_v: Variant = _carte.sommet_max_colonne(col)
			if som_terrain_v == null:
				continue
			var cellule := Vector3i(col.x, int(som_terrain_v), col.y)
			if _carte.item_de(cellule) != _carte.ITEM_DEFAUT:
				continue
			if cellule.y <= _carte.couche_base:
				continue
			# Rejette les colonnes dont le bloc terrain est enterre sous une
			# pile de sc libres (l'ennemi ne peut pas atteindre le bloc).
			if couche_cible > cellule.y + 1:
				continue
			var d2: int = dx * dx + dz * dz
			if d2 < meilleur_d2:
				meilleur_d2 = d2
				meilleur = cellule
	return meilleur

func _ennemi_a_obstacle_devant(pos_ennemi: Vector3, direction: Vector3, distance: float = 0.0) -> bool:
	var d: float = distance if distance > 0.0 else _cote_cellule
	var dir_plate: Vector3 = Vector3(direction.x, 0.0, direction.z)
	if dir_plate.length_squared() < 0.0001:
		return false
	var pos_devant: Vector3 = pos_ennemi + dir_plate.normalized() * d
	return _mouvement_bloque_par_terrain(pos_ennemi, pos_devant)

# CORPS-A-CORPS : direction 3D, suit la vision comme l'arme de tir (le tangage
# yeux est deja recopie sur l'arme dans arme_tir.gd). Segment
# [origine, origine + dir * portee], distance point-segment 3D vs chaque
# ennemi vivant, hit celui le plus proche (distance tireur-ennemi) dont la
# distance au segment est <= RAYON_HIT_ENNEMI. Rend true si touche. Ni carres
# ni sol.
func frapper_melee(origine: Vector3, direction: Vector3, portee: float, degat: int) -> bool:
	if direction.length_squared() <= 0.0:
		return false
	var seg: Vector3 = direction.normalized() * portee
	var long2: float = seg.length_squared()
	var rayon2 := RAYON_HIT_ENNEMI * RAYON_HIT_ENNEMI
	var cible = null
	var dist2_meilleur := INF
	for e in _ennemis:
		if e.est_mort:
			continue
		var vers: Vector3 = (e.position as Vector3) - origine
		var t: float = clampf(vers.dot(seg) / long2, 0.0, 1.0)
		var proche: Vector3 = seg * t
		var d2: float = (vers - proche).length_squared()
		if d2 > rayon2:
			continue
		var d2_origine: float = vers.length_squared()
		if d2_origine < dist2_meilleur:
			dist2_meilleur = d2_origine
			cible = e
	if cible == null:
		return false
	cible.vie -= degat
	if cible.vie <= 0:
		cible.est_mort = true
	rafraichir_barre_ennemi(cible)
	return true

func rafraichir_barre_ennemi(e: Dictionary) -> void:
	_rafraichir_barre_ennemi(e)

func _rafraichir_barre_ennemi(e: Dictionary) -> void:
	if e.noeud == null or not is_instance_valid(e.noeud):
		return
	var barre := (e.noeud as Node3D).get_child(1) as MeshInstance3D
	if barre == null:
		return
	var mat := barre.get_surface_override_material(0) as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("fraction", float(e.vie) / float(_vie_ennemi))

# Barre bleue (child 3) : rafraichit la fraction depuis e.nourriture.
func _rafraichir_barre_nourriture_ennemi(e: Dictionary) -> void:
	if e.noeud == null or not is_instance_valid(e.noeud):
		return
	if (e.noeud as Node3D).get_child_count() < 4:
		return
	var barre := (e.noeud as Node3D).get_child(3) as MeshInstance3D
	if barre == null:
		return
	var mat := barre.get_surface_override_material(0) as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("fraction", float(e.nourriture) / NOURRITURE_MAX_ENNEMI)
