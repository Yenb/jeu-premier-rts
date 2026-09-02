extends RefCounted

# Module TAS : la matiere granulaire libre du proto (sous-cubes qui tombent,
# s'empilent et s'ecoulent en sable). Extrait de manager_proto.gd -- aucune
# logique nouvelle, un deplacement.
#
# Recoit a la construction :
# - carte (Resource) : la carte terrain, seule source de verite du sol
#   (carte.sommet(x, z)). Jamais de physique Godot ici.
# - cote_cellule (float) : arete d'une cellule ; le sous-cube fait cote/3.
# - fournisseur_limite (Callable) : matiere:String -> int, la hauteur max de
#   sous-cubes empiles pour cette matiere (0 = sans plafond). Injecte parce
#   qu'un RefCounted n'a pas get_tree() pour interroger RessourcesTerrain.
#
# Detient : _monde (instance de Monde, l'index spatial des sous-cubes),
# _index_sc_par_colonne (colonne sous-cube -> Array de sc, pour sommet_effectif),
# _prochain_id (compteur d'id), _mesh_sous_cube_par_matiere (cache de meshes).
#
# Expose : monde() (l'index, interroge par le rendu et les outils), tick(delta)
# (gravite d'empilement + ecoulement sandpile), sommet_effectif(x, z, y_ref)
# (sol effectif = terrain + sous-cubes stables sous y_ref), spawn_sous_cube_libre
# (cree un sc neuf), index_ajouter/index_retirer (le manager et les ennemis
# reinjectent/retirent un sc EXISTANT dans l'index de colonne),
# mesh_pour_matiere / ajouter_collision_cube_libre (fabriques du rendu, appelees
# par le manager qui garde le rendu).
#
# Regles : lit carte.sommet, jamais un raycast. Ne connait aucun type ; la
# matiere est une chaine de donnee ("terre", "cadavre", ...). Pelle et beche
# sont exclues de l'index et du sandpile (ce sont des outils, pas de la matiere
# qui coule).

const Monde = preload("res://scripts/monde.gd")
const Sandpile = preload("res://scripts/sandpile.gd")

const MAX_TAS := 2000
const GRAVITE_TAS := 18.0
const INTERVALLE_SANDPILE := 1.0
const SANDPILE_ANGLE_REPOS := 3.0

var _carte: Resource = null
var _cote_cellule: float = 2.0
var _fournisseur_limite: Callable
var _monde: Monde
var _index_sc_par_colonne: Dictionary = {}
var _prochain_id: int = 0
var _mesh_sous_cube_par_matiere: Dictionary = {}
var _horloge_sandpile: float = 0.0

func _init(carte: Resource, cote_cellule: float, fournisseur_limite: Callable) -> void:
	_carte = carte
	_cote_cellule = cote_cellule
	_fournisseur_limite = fournisseur_limite
	_monde = Monde.new()
	_mesh_sous_cube_par_matiere["terre"] = _fabriquer_mesh_sous_cube(Color(0.35, 0.22, 0.12, 1.0))
	_mesh_sous_cube_par_matiere["cadavre"] = _fabriquer_mesh_sous_cube(Color(0.35, 0.05, 0.05, 1.0))

func monde() -> Monde:
	return _monde

func tick(delta: float) -> void:
	_ticker_tas(delta)
	# Sandpile : ecoulement granulaire des sous-cubes libres empiles.
	_horloge_sandpile += delta
	if _horloge_sandpile >= INTERVALLE_SANDPILE:
		_horloge_sandpile = 0.0
		_tick_sandpile()

# A appeler APRES `_monde.ajouter(sc, ...)` quand sc.position est finale.
func index_ajouter(sc: Dictionary) -> void:
	if String(sc.get("matiere", "")) == "pelle" or String(sc.get("matiere", "")) == "beche":
		return
	var cote_sous: float = _cote_cellule / 3.0
	var pos: Vector3 = sc.position
	var col := Vector2i(int(floor(pos.x / cote_sous)), int(floor(pos.z / cote_sous)))
	if not _index_sc_par_colonne.has(col):
		_index_sc_par_colonne[col] = []
	(_index_sc_par_colonne[col] as Array).append(sc)

# A appeler AVANT `_monde.retirer(sc.id)` -- apres retrait le sc peut
# etre invalide.
func index_retirer(sc: Dictionary) -> void:
	if String(sc.get("matiere", "")) == "pelle" or String(sc.get("matiere", "")) == "beche":
		return
	var cote_sous: float = _cote_cellule / 3.0
	var pos: Vector3 = sc.position
	var col := Vector2i(int(floor(pos.x / cote_sous)), int(floor(pos.z / cote_sous)))
	if not _index_sc_par_colonne.has(col):
		return
	var arr: Array = _index_sc_par_colonne[col]
	arr.erase(sc)
	if arr.is_empty():
		_index_sc_par_colonne.erase(col)

# Colonne SC = grille SOUS-CUBE (cote_cellule/3), JAMAIS colonne cellule --
# un sc libre a 0.5m lateral d'un ennemi ne doit pas etre considere sous lui.
func sommet_effectif(x: float, z: float, y_ref: float) -> Variant:
	if _carte == null:
		return null
	var y_terrain: Variant = _carte.sommet(x, z)
	if y_terrain == null:
		return null
	var y_max: float = float(y_terrain)
	var cote_sous: float = _cote_cellule / 3.0
	var col_sc := Vector2i(int(floor(x / cote_sous)), int(floor(z / cote_sous)))
	var sc_colonne: Array = _index_sc_par_colonne.get(col_sc, [])
	for sc in sc_colonne:
		var pos_sc: Vector3 = sc.position
		if pos_sc.y > y_ref:
			continue
		var y_top_sc: float = pos_sc.y + cote_sous * 0.5
		if y_top_sc > y_max:
			y_max = y_top_sc
	return y_max

func spawn_sous_cube_libre(pos: Vector3, matiere: String, immobile: bool = false) -> void:
	if _monde.choses.size() >= MAX_TAS:
		var id_vieux = _monde.choses.keys()[0]
		var w = _monde.par_id(id_vieux)
		if w != null:
			var vc: Dictionary = w.chose
			if vc.noeud != null and is_instance_valid(vc.noeud):
				vc.noeud.queue_free()
			index_retirer(vc)
		_monde.retirer(id_vieux)
	var id_neuf: String = "sc_%d" % _prochain_id
	_prochain_id += 1
	var sc := {
		"id": id_neuf,
		"position": pos,
		"vitesse_y": 0.0,
		"noeud": null,
		"matiere": matiere,
		"immobile": immobile,
	}
	_monde.ajouter(sc, "sous_cube", pos)
	index_ajouter(sc)

func _ticker_tas(delta: float) -> void:
	if _monde.choses.is_empty() or _carte == null:
		return
	var cote_sous: float = _cote_cellule / 3.0
	# Grouper les sc mobiles par COLONNE sous-cube (x_sc, z_sc). Un sc voit
	# uniquement les autres sc de sa propre colonne pour calculer son sol
	# effectif : sol_terrain + n_sc_stables_en_dessous * cote_sous.
	var par_colonne: Dictionary = {}  # Vector2i -> Array de sc (mobiles)
	for w in _monde.choses.values():
		var t: Dictionary = w.chose
		if t.get("matiere", "") == "pelle" or t.get("matiere", "") == "beche":
			continue
		var pos: Vector3 = t.position
		var col := Vector2i(int(floor(pos.x / cote_sous)), int(floor(pos.z / cote_sous)))
		if not par_colonne.has(col):
			par_colonne[col] = []
		(par_colonne[col] as Array).append(t)
	# Pour chaque colonne : tri par Y croissant, empilement du bas vers le haut.
	for col in par_colonne.keys():
		var sc_liste: Array = par_colonne[col]
		sc_liste.sort_custom(func(a, b): return a.position.y < b.position.y)
		var x_centre: float = float(col.x) * cote_sous + cote_sous * 0.5
		var z_centre: float = float(col.y) * cote_sous + cote_sous * 0.5
		var y_sol_terrain_v: Variant = _carte.sommet(x_centre, z_centre)
		if y_sol_terrain_v == null:
			continue
		var y_sol_terrain: float = float(y_sol_terrain_v)
		# Hauteur du sommet de la pile DEJA stable (croit au fur et a mesure).
		var y_pile_stable: float = y_sol_terrain
		for t in sc_liste:
			var pos: Vector3 = t.position
			var sol_y: float = y_pile_stable + cote_sous * 0.5
			var change := false
			if pos.y > sol_y:
				t.vitesse_y -= GRAVITE_TAS * delta
				pos.y += t.vitesse_y * delta
				if pos.y < sol_y:
					pos.y = sol_y
					t.vitesse_y = 0.0
				change = true
			elif pos.y < sol_y:
				pos.y = sol_y
				t.vitesse_y = 0.0
				change = true
			if change:
				t.position = pos
				_monde.deplacer(t)
			# Inclut la position en chute -- son sommet est deja compte comme
			# faisant partie de la pile pour le sc suivant.
			y_pile_stable = pos.y + cote_sous * 0.5

func _tick_sandpile() -> void:
	if _carte == null:
		return
	var cases: Array = _cases_pour_sandpile()
	if cases.is_empty():
		return
	var transferts: Array = Sandpile.avancer(cases, 1.0, "tas", "altitude_sol", SANDPILE_ANGLE_REPOS)
	if not transferts.is_empty():
		_appliquer_transferts_sandpile(transferts)

func _cases_pour_sandpile() -> Array:
	var cote_sous: float = _cote_cellule / 3.0
	var par_colonne: Dictionary = {}  # Vector2i -> Array de sc
	for w in _monde.choses.values():
		var sc: Dictionary = w.chose
		if sc.get("matiere", "") == "pelle" or sc.get("matiere", "") == "beche":
			continue
		var pos: Vector3 = sc.position
		var col := Vector2i(int(floor(pos.x / cote_sous)), int(floor(pos.z / cote_sous)))
		if not par_colonne.has(col):
			par_colonne[col] = []
		(par_colonne[col] as Array).append(sc)
	if par_colonne.is_empty():
		return []
	var cols_a_inclure: Dictionary = {}
	for col in par_colonne.keys():
		cols_a_inclure[col] = true
		cols_a_inclure[Vector2i(col.x + 1, col.y)] = true
		cols_a_inclure[Vector2i(col.x - 1, col.y)] = true
		cols_a_inclure[Vector2i(col.x, col.y + 1)] = true
		cols_a_inclure[Vector2i(col.x, col.y - 1)] = true
	var cases: Array = []
	for col in cols_a_inclure.keys():
		var x_monde: float = float(col.x) * cote_sous + cote_sous * 0.5
		var z_monde: float = float(col.y) * cote_sous + cote_sous * 0.5
		var y_sol_val: Variant = _carte.sommet(x_monde, z_monde)
		if y_sol_val == null:
			continue
		var altitude_sc: float = float(y_sol_val) / cote_sous
		var reserve: float = float((par_colonne.get(col, []) as Array).size())
		cases.append({
			"id": "col_%d_%d" % [col.x, col.y],
			"position": Vector3(float(col.x), float(col.y), 0.0),
			"proprietes": {
				"altitude_sol": altitude_sc,
				"reserves": {"tas": {"reserve": reserve}},
			},
		})
	return cases

func _appliquer_transferts_sandpile(transferts: Array) -> void:
	var cote_sous: float = _cote_cellule / 3.0
	var par_colonne: Dictionary = {}
	for w in _monde.choses.values():
		var sc: Dictionary = w.chose
		if sc.get("matiere", "") == "pelle" or sc.get("matiere", "") == "beche":
			continue
		var pos: Vector3 = sc.position
		var col := Vector2i(int(floor(pos.x / cote_sous)), int(floor(pos.z / cote_sous)))
		if not par_colonne.has(col):
			par_colonne[col] = []
		(par_colonne[col] as Array).append(sc)
	var ajouts_par_col: Dictionary = {}
	for t in transferts:
		var col_s := _col_de_id(String(t.source_id))
		var col_r := _col_de_id(String(t.receveur_id))
		if not par_colonne.has(col_s) or (par_colonne[col_s] as Array).is_empty():
			continue
		var sc_source_head: Dictionary = (par_colonne[col_s] as Array).back()
		# Sc immobile : jamais deplace lateralement (regle generale).
		if bool(sc_source_head.get("immobile", false)):
			continue
		var matiere_src: String = String(sc_source_head.get("matiere", "terre"))
		var limite: int = _limite_hauteur_matiere(matiere_src)
		if limite > 0:
			var hauteur_meme_matiere: int = 0
			for sc_r in (par_colonne.get(col_r, []) as Array):
				if String((sc_r as Dictionary).get("matiere", "")) == matiere_src:
					hauteur_meme_matiere += 1
			hauteur_meme_matiere += int(ajouts_par_col.get(col_r, 0))
			if hauteur_meme_matiere >= limite:
				continue
		var sc_ret: Dictionary = (par_colonne[col_s] as Array).pop_back()
		if sc_ret.get("noeud", null) != null and is_instance_valid(sc_ret.noeud):
			(sc_ret.noeud as Node3D).queue_free()
		index_retirer(sc_ret)
		_monde.retirer(sc_ret.id)
		var x_rec: float = float(col_r.x) * cote_sous + cote_sous * 0.5
		var z_rec: float = float(col_r.y) * cote_sous + cote_sous * 0.5
		var y_sol_val: Variant = _carte.sommet(x_rec, z_rec)
		if y_sol_val == null:
			continue
		var reserve_rec: int = (par_colonne.get(col_r, []) as Array).size() + int(ajouts_par_col.get(col_r, 0))
		var y_pose: float = float(y_sol_val) + (float(reserve_rec) + 0.5) * cote_sous
		var pos_neuve := Vector3(x_rec, y_pose, z_rec)
		spawn_sous_cube_libre(pos_neuve, String(sc_ret.get("matiere", "terre")))
		ajouts_par_col[col_r] = int(ajouts_par_col.get(col_r, 0)) + 1

# 0 = aucune limite (matiere sans plafond explicite dans son profil .tres).
func _limite_hauteur_matiere(matiere: String) -> int:
	if not _fournisseur_limite.is_valid():
		return 0
	return int(_fournisseur_limite.call(matiere))

func _col_de_id(id: String) -> Vector2i:
	# "col_X_Z" -> Vector2i(X, Z), X et Z peuvent etre negatifs.
	if not id.begins_with("col_"):
		return Vector2i.ZERO
	var reste: String = id.substr(4)
	var sep: int = reste.rfind("_")
	if sep < 0:
		return Vector2i.ZERO
	return Vector2i(int(reste.substr(0, sep)), int(reste.substr(sep + 1)))

func _fabriquer_mesh_sous_cube(couleur: Color) -> BoxMesh:
	var box := BoxMesh.new()
	var mini_cote := _cote_cellule / 3.0
	box.size = Vector3(mini_cote, mini_cote, mini_cote)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = couleur
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	box.material = mat
	return box

func mesh_pour_matiere(matiere: String) -> BoxMesh:
	if not _mesh_sous_cube_par_matiere.has(matiere):
		_mesh_sous_cube_par_matiere[matiere] = _fabriquer_mesh_sous_cube(Color(0.5, 0.5, 0.5, 1.0))
	return _mesh_sous_cube_par_matiere[matiere]

func ajouter_collision_cube_libre(visuel: Node3D) -> void:
	if visuel == null:
		return
	if visuel.get_node_or_null("StaticBody3D") != null:
		return
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var cote_sous: float = _cote_cellule / 3.0
	box.size = Vector3(cote_sous, cote_sous, cote_sous)
	shape.shape = box
	body.add_child(shape)
	visuel.add_child(body)
