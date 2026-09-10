extends RefCounted

# Systeme de collision GENERALISTE en donnee pure (prototype Orion). Tout
# statique, AUCUN etat interne : chaque fonction recoit ce dont elle a besoin.
# AUCUNE physique Godot (PhysicsServer3D / StaticBody3D / CollisionShape3D) :
# une forme est un Dictionary, une entite est un Dictionary, la collision se
# calcule sur ces donnees, partout et tout le temps (hors rendu comme dans le
# rendu). A reutiliser pour tout futur objet interactif.
#
# SYSTEME COMPLET : SUPPORT unifiee, AABB par forme, GJK, EPA, detecter
# (broadphase grille locale + narrowphase + swept) et resoudre (separation en
# donnee pure). Une seule voie de collision : detecter + resoudre. L'appelant
# fournit la liste COMPLETE des entites a tester ; detecter ne va jamais
# chercher un voisin dans un index externe -- la collecte est de son ressort.
#
# CONTRAT DE FORME : { type: String, transform_locale: Transform3D,
# parametres: Dictionary }. Quatre types :
#   sphere  : parametres { rayon: float }
#   boite   : parametres { demi_taille: Vector3 }
#   capsule : parametres { rayon: float, hauteur: float } -- axe Y, segment
#             central de longueur (hauteur - 2*rayon), capuchons spheriques.
#   hull    : parametres { points: Array[Vector3] } -- sommets LOCAUX.
# Le DISPATCH par type vit UNIQUEMENT dans _support_local : un cinquieme type =
# un case de plus, rien d'autre ailleurs.
#
# transform_monde passe a support/aabb_forme est le transform COMPLET de la
# forme dans le monde (l'appelant compose Transform3D(orientation, position) *
# transform_locale) : ces deux fonctions n'appliquent PAS transform_locale
# elles-memes, il est deja dans transform_monde.

# Point de la forme le plus loin dans direction_monde. Ramene la direction en
# repere local (basis inverse), cherche le support local par type, remet le
# point en monde.
static func support(forme: Dictionary, transform_monde: Transform3D, direction_monde: Vector3) -> Vector3:
	var dir_local: Vector3 = transform_monde.basis.inverse() * direction_monde
	var p_local: Vector3 = _support_local(String(forme.get("type", "")), forme.get("parametres", {}), dir_local)
	return transform_monde * p_local

static func _support_local(type: String, p: Dictionary, d: Vector3) -> Vector3:
	match type:
		"sphere":
			var r: float = float(p.get("rayon", 0.0))
			var dn: Vector3 = d.normalized() if d.length_squared() > 0.0 else Vector3.RIGHT
			return dn * r
		"boite":
			var h: Vector3 = p.get("demi_taille", Vector3.ZERO)
			return Vector3(
				h.x if d.x >= 0.0 else -h.x,
				h.y if d.y >= 0.0 else -h.y,
				h.z if d.z >= 0.0 else -h.z)
		"capsule":
			var r: float = float(p.get("rayon", 0.0))
			var ht: float = float(p.get("hauteur", 0.0))
			var demi_seg: float = max(0.0, ht * 0.5 - r)
			var base: Vector3 = Vector3(0.0, demi_seg if d.y >= 0.0 else -demi_seg, 0.0)
			var dn: Vector3 = d.normalized() if d.length_squared() > 0.0 else Vector3.UP
			return base + dn * r
		"hull":
			var pts: Array = p.get("points", [])
			if pts.is_empty():
				push_error("collision.gd : hull sans points")
				return Vector3.ZERO
			var meilleur: Vector3 = pts[0]
			var meilleur_d: float = meilleur.dot(d)
			for q in pts:
				var qd: float = (q as Vector3).dot(d)
				if qd > meilleur_d:
					meilleur_d = qd
					meilleur = q
			return meilleur
		_:
			push_error("collision.gd : type de forme inconnu : %s" % type)
			return Vector3.ZERO

# AABB monde d'une forme, par 6 supports (±X ±Y ±Z). Generique : aucune formule
# analytique par type, donc un nouveau type n'a rien a ajouter ici.
#
# RACCOURCI boite-alignee : quand la forme est "boite" ET que le transform monde
# n'a pas de rotation (basis == IDENTITY), l'AABB est directe -- centre =
# transform.origin, demi-taille = demi_taille -- sans passer par les 6 supports
# (chaque support = 1 basis.inverse + 1 _support_local + 1 transform). Une boite
# tournee ou tout autre type retombe sur la boucle generique inchangee.
static func aabb_forme(forme: Dictionary, transform_monde: Transform3D) -> AABB:
	if String(forme.get("type", "")) == "boite" and transform_monde.basis == Basis.IDENTITY:
		var h: Vector3 = forme.get("parametres", {}).get("demi_taille", Vector3.ZERO)
		return AABB(transform_monde.origin - h, h * 2.0)
	var axes: Array = [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
	var premier: Vector3 = support(forme, transform_monde, axes[0])
	var mn: Vector3 = premier
	var mx: Vector3 = premier
	for i in range(1, axes.size()):
		var s: Vector3 = support(forme, transform_monde, axes[i])
		mn = Vector3(minf(mn.x, s.x), minf(mn.y, s.y), minf(mn.z, s.z))
		mx = Vector3(maxf(mx.x, s.x), maxf(mx.y, s.y), maxf(mx.z, s.z))
	return AABB(mn, mx - mn)

# --- GJK : deux convexes s'intersectent-ils ? ---
# Rend { intersecte: bool, simplexe: Array[Vector3] }. Sur intersection, le
# simplexe est un TETRAEDRE de points de Minkowski contenant l'origine -- c'est
# lui que EPA prendra ensuite. Point de Minkowski dans une direction :
# support(A, d) - support(B, -d). Le simplexe grandit (ligne -> triangle ->
# tetraedre) en encadrant l'origine ; a chaque tour le point le plus recent est
# en tete (index 0).

const _EPS := 1e-8

static func _support_minkowski(fa: Dictionary, ta: Transform3D, fb: Dictionary, tb: Transform3D, dir: Vector3) -> Vector3:
	return support(fa, ta, dir) - support(fb, tb, -dir)

static func gjk(forme_a: Dictionary, tf_a: Transform3D, forme_b: Dictionary, tf_b: Transform3D) -> Dictionary:
	var s0 := _support_minkowski(forme_a, tf_a, forme_b, tf_b, Vector3.RIGHT)
	var simplexe: Array = [s0]
	var dir := -s0
	for _i in range(32):
		if dir.length_squared() < _EPS:
			# Origine deja sur le simplexe : contact frontalier, on traite comme
			# une intersection (EPA prendra le relais).
			return {"intersecte": true, "simplexe": simplexe}
		var a := _support_minkowski(forme_a, tf_a, forme_b, tf_b, dir)
		if a.dot(dir) < 0.0:
			return {"intersecte": false, "simplexe": simplexe}  # ne passe pas l'origine
		simplexe.push_front(a)
		var res := _do_simplexe(simplexe)
		if res.contient:
			return {"intersecte": true, "simplexe": simplexe}
		dir = res.dir
	return {"intersecte": false, "simplexe": simplexe}

# Met a jour le simplexe (en place) et rend { contient: bool, dir: Vector3 }.
static func _do_simplexe(s: Array) -> Dictionary:
	match s.size():
		2: return _ligne(s)
		3: return _triangle(s)
		4: return _tetra(s)
	return {"contient": false, "dir": Vector3.ZERO}

static func _ligne(s: Array) -> Dictionary:
	var a: Vector3 = s[0]
	var b: Vector3 = s[1]
	var ab := b - a
	var ao := -a
	if ab.dot(ao) > 0.0:
		var dir := ab.cross(ao).cross(ab)  # perpendiculaire a ab, vers l'origine
		if dir.length_squared() < _EPS:
			dir = _perpendiculaire(ab)  # origine sur la droite ab
		return {"contient": false, "dir": dir}
	s.assign([a])
	return {"contient": false, "dir": ao}

static func _triangle(s: Array) -> Dictionary:
	var a: Vector3 = s[0]
	var b: Vector3 = s[1]
	var c: Vector3 = s[2]
	var ab := b - a
	var ac := c - a
	var ao := -a
	var abc := ab.cross(ac)  # normale du triangle
	if abc.cross(ac).dot(ao) > 0.0:
		if ac.dot(ao) > 0.0:
			s.assign([a, c])
			return {"contient": false, "dir": ac.cross(ao).cross(ac)}
		s.assign([a, b])
		return _ligne(s)
	if ab.cross(abc).dot(ao) > 0.0:
		s.assign([a, b])
		return _ligne(s)
	if abc.dot(ao) > 0.0:
		return {"contient": false, "dir": abc}  # origine au-dessus
	s.assign([a, c, b])
	return {"contient": false, "dir": -abc}  # origine en-dessous

static func _tetra(s: Array) -> Dictionary:
	var a: Vector3 = s[0]
	var b: Vector3 = s[1]
	var c: Vector3 = s[2]
	var d: Vector3 = s[3]
	var ao := -a
	var ab := b - a
	var ac := c - a
	var ad := d - a
	if ab.cross(ac).dot(ao) > 0.0:
		s.assign([a, b, c])
		return _triangle(s)
	if ac.cross(ad).dot(ao) > 0.0:
		s.assign([a, c, d])
		return _triangle(s)
	if ad.cross(ab).dot(ao) > 0.0:
		s.assign([a, d, b])
		return _triangle(s)
	return {"contient": true, "dir": Vector3.ZERO}  # origine dans le tetraedre

static func _perpendiculaire(v: Vector3) -> Vector3:
	var c := v.cross(Vector3.RIGHT)
	if c.length_squared() < _EPS:
		c = v.cross(Vector3.UP)
	return c

# --- EPA : profondeur et normale de penetration ---
# Recoit le TETRAEDRE de Minkowski rendu par gjk (4 points contenant l'origine)
# et fait grossir le polytope : a chaque tour, la face la PLUS PROCHE de
# l'origine donne un candidat de normale ; on cherche un point de support plus
# loin dans cette normale ; s'il n'apporte presque rien (< 1e-4) on a la face
# finale. Rend { normale, profondeur } -- normale unitaire (sens : la direction
# de separation minimale ; le signe A->B est fixe par la phase de resolution).
const _TOL_EPA := 1e-4

static func epa(simplexe: Array, forme_a: Dictionary, tf_a: Transform3D, forme_b: Dictionary, tf_b: Transform3D) -> Dictionary:
	var verts: Array = simplexe.duplicate()
	if verts.size() < 4:
		# Simplexe degenere (contact frontalier) : pas de volume a etendre.
		return {"normale": Vector3.UP, "profondeur": 0.0}
	var faces: Array = [
		_face(verts, 0, 1, 2),
		_face(verts, 0, 2, 3),
		_face(verts, 0, 3, 1),
		_face(verts, 1, 3, 2),
	]
	for _iter in range(32):
		var idx: int = _face_plus_proche(faces)
		var f: Dictionary = faces[idx]
		var p: Vector3 = _support_minkowski(forme_a, tf_a, forme_b, tf_b, f.normale)
		var d: float = p.dot(f.normale)
		if d - float(f.distance) < _TOL_EPA:
			return {"normale": f.normale, "profondeur": float(f.distance)}
		var iv: int = verts.size()
		verts.push_back(p)
		# Retire les faces qui "voient" p, recolte les aretes de bordure.
		var aretes: Array = []
		var gardees: Array = []
		for face in faces:
			var va: Vector3 = verts[face.a]
			if (face.normale as Vector3).dot(p - va) > 0.0:
				_ajouter_bord(aretes, face.a, face.b)
				_ajouter_bord(aretes, face.b, face.c)
				_ajouter_bord(aretes, face.c, face.a)
			else:
				gardees.append(face)
		for e in aretes:
			gardees.append(_face(verts, e[0], e[1], iv))
		faces = gardees
	var idx2: int = _face_plus_proche(faces)
	return {"normale": faces[idx2].normale, "profondeur": float(faces[idx2].distance)}

# Une face du polytope, normale rendue SORTANTE (l'origine est dedans, donc la
# distance signee d'une face sortante est >= 0 ; si elle est negative on
# retourne la face -- normale ET winding -- pour garder la coherence des aretes).
static func _face(verts: Array, ia: int, ib: int, ic: int) -> Dictionary:
	var a: Vector3 = verts[ia]
	var b: Vector3 = verts[ib]
	var c: Vector3 = verts[ic]
	var n: Vector3 = (b - a).cross(c - a)
	var l: float = n.length()
	if l < _EPS:
		return {"a": ia, "b": ib, "c": ic, "normale": Vector3.ZERO, "distance": INF}
	n = n / l
	var dist: float = n.dot(a)
	if dist < 0.0:
		return {"a": ia, "b": ic, "c": ib, "normale": -n, "distance": -dist}
	return {"a": ia, "b": ib, "c": ic, "normale": n, "distance": dist}

static func _face_plus_proche(faces: Array) -> int:
	var best: int = 0
	var bd: float = float(faces[0].distance)
	for k in range(1, faces.size()):
		if float(faces[k].distance) < bd:
			bd = float(faces[k].distance)
			best = k
	return best

# Bord partage par deux faces retirees s'annule (arete interne) ; bord unique
# reste (frontiere du trou a recoudre).
static func _ajouter_bord(aretes: Array, i: int, j: int) -> void:
	for k in range(aretes.size()):
		if aretes[k][0] == j and aretes[k][1] == i:
			aretes.remove_at(k)
			return
	aretes.append([i, j])

# --- DETECTER : liste des contacts pour un ensemble d'entites ---
# BROADPHASE 100% LOCALE : detecter construit UNE grille par counting sort a
# partir du cache colonnes -- aucun appel a un index externe. Pour chaque case
# non vide, le voisinage lu est les occupants de la case + ceux des 26 cases
# adjacentes (3x3x3), directement dans la grille locale. Le filtre distance
# per-driver `dist(a, b) <= r_a` reproduit le filtre de l'ancienne broadphase
# per-entity : parite stricte du set de paires. Narrowphase GJK->EPA par paire
# de formes, avec SWEPT.
# Rend un Array de contacts { a, b, normale (A->B), profondeur, a_reponse,
# b_reponse, a_masque_r, b_masque_r, a_vel_nz, b_vel_nz }.
#
# ENTITE : position (Vector3, top-level) ; le reste dans proprietes : formes
# (Array { type, transform_locale, parametres }), velocite (Vector3),
# orientation (Basis), masque_collision (int), masque_reponse (int), reponse
# (String), aabb_cache (rafraichie ici). transform monde d'une forme =
# Transform3D(orientation, position) * transform_locale.
#
# CONTRAT : toutes les entites a tester doivent etre dans `entites` -- detecter
# ne va JAMAIS chercher dans un index externe. Un appelant qui veut tester une
# entite contre ses voisins collecte les voisins lui-meme (ex :
# monde.choses_dans_rayon) et compose la liste avant d'appeler.
static func detecter(entites: Array, delta: float) -> Array:
	var contacts: Array = []
	if entites.is_empty():
		return contacts
	# CACHE EN COLONNES TYPEES ET PRE-DIMENSIONNEES : une colonne par champ,
	# resize(N) UNE fois -- aucune reallocation progressive, aucun boxing Variant
	# sur les scalaires/vecteurs. Les PackedArray natifs (Vector3/Float32/Int32/
	# Byte) portent les scalaires ; les Array[T] typees portent Basis/AABB/
	# Dictionary/String (aucun PackedArray de ces types). col_formes reste Array
	# generique car GDScript ne supporte pas Array[Array] typee. _ecrire_cache
	# ecrit par index, plus d'append dans le chemin normal.
	# Contrat : toutes les entites collisionnables sont dans `entites` (voir
	# en-tete de detecter) -- pas de branche "entite en plus ajoutee a la volee",
	# donc pas de reallocation apres le resize initial.
	var N: int = entites.size()
	var col_ent: Array[Dictionary] = []
	col_ent.resize(N)
	var col_vel: PackedVector3Array = PackedVector3Array()
	col_vel.resize(N)
	var col_vel_len: PackedFloat32Array = PackedFloat32Array()
	col_vel_len.resize(N)
	var col_vel_nz: PackedByteArray = PackedByteArray()
	col_vel_nz.resize(N)
	var col_orient: Array[Basis] = []
	col_orient.resize(N)
	var col_aabb: Array[AABB] = []
	col_aabb.resize(N)
	var col_swept: Array[AABB] = []
	col_swept.resize(N)
	var col_masque_c: PackedInt32Array = PackedInt32Array()
	col_masque_c.resize(N)
	var col_masque_r: PackedInt32Array = PackedInt32Array()
	col_masque_r.resize(N)
	var col_reponse: PackedStringArray = PackedStringArray()
	col_reponse.resize(N)
	var col_formes: Array = []
	col_formes.resize(N)
	var col_taille_min: PackedFloat32Array = PackedFloat32Array()
	col_taille_min.resize(N)
	# CORPS INLINE (ex _ecrire_cache) : appel de fonction par entite retire, tous
	# les lookups et calculs directement dans la boucle. Chemin rapide AABB : si
	# orient IDENTITY (cas dominant peuplement), l'AABB monde d'une forme = AABB
	# locale cachee + position, sans composer Transform3D. Fallback complet
	# (Transform3D(orient, pos) * transform_locale) sur orient tournee.
	var rayon_max := 0.0
	for idx in N:
		var e: Dictionary = entites[idx]
		var pr: Dictionary = e.get("proprietes", {})
		var vel: Vector3 = pr.get("velocite", Vector3.ZERO)
		var orient: Basis = pr.get("orientation", Basis.IDENTITY)
		var formes: Array = pr.get("formes", [])
		var pos: Vector3 = e.position
		var aabb: AABB
		if formes.is_empty():
			aabb = AABB(pos, Vector3.ZERO)
		elif orient == Basis.IDENTITY:
			var f0: Dictionary = formes[0]
			var id0: int = int(f0.get("_aabb_id", -1))
			if id0 < 0:
				id0 = _cacher_forme(f0)
			var l0: AABB = _cache_aabb_locale[id0]
			aabb = AABB(l0.position + pos, l0.size)
			for i_f in range(1, formes.size()):
				var fi: Dictionary = formes[i_f]
				var idi: int = int(fi.get("_aabb_id", -1))
				if idi < 0:
					idi = _cacher_forme(fi)
				var li: AABB = _cache_aabb_locale[idi]
				aabb = aabb.merge(AABB(li.position + pos, li.size))
		else:
			aabb = _aabb_from(orient, formes, pos)
		var vel_len: float = vel.length()
		var vel_nz: bool = vel.length_squared() > 0.0
		var swept: AABB = aabb
		if vel_nz:
			swept = aabb.merge(AABB(aabb.position - vel * delta, aabb.size))
		# Taille min via cache par-forme (INLINE aussi -- evite l'appel a
		# _taille_min_formes_cache et sa boucle interne).
		var m: float = INF
		for f in formes:
			var idf: int = int((f as Dictionary).get("_aabb_id", -1))
			if idf < 0:
				idf = _cacher_forme(f)
			var t: float = _cache_taille_min_forme[idf]
			if t < m:
				m = t
		col_ent[idx] = e
		col_vel[idx] = vel
		col_vel_len[idx] = vel_len
		col_vel_nz[idx] = 1 if vel_nz else 0
		col_orient[idx] = orient
		col_aabb[idx] = aabb
		col_swept[idx] = swept
		col_masque_c[idx] = int(pr.get("masque_collision", 0))
		col_masque_r[idx] = int(pr.get("masque_reponse", 0))
		col_reponse[idx] = String(pr.get("reponse", ""))
		col_formes[idx] = formes
		col_taille_min[idx] = 0.0 if m == INF else m
		e.proprietes["aabb_cache"] = aabb
		var sz: Vector3 = aabb.size
		rayon_max = maxf(rayon_max, sz.length() * 0.5)
	# GRILLE LOCALE PAR COUNTING SORT : indice de case lineaire par entite,
	# sorted_idx tri par cell + offsets (start par cell) -- structure exacte
	# du portage C++ a venir (cell-id array + sorted index + start/end offsets).
	# ARETE : max r_i * 1.0001, avec r_i = hd_i + rayon_max + vel_len_i*delta.
	# Pour que la sphere de rayon r_i autour d'une entite tienne dans 3x3x3
	# cases, il faut arete > r_i strict (p au bord d'une case, r_i = arete,
	# case(q) peut = case(p)+2 -- prouve par decoupage entier). La marge 1.0001
	# ferme ce cas degenere sans grossir sensiblement les cases.
	var r_par_i: PackedFloat32Array = PackedFloat32Array()
	r_par_i.resize(N)
	var arete: float = 0.0
	for i in N:
		var hd: float = (col_aabb[i] as AABB).size.length() * 0.5
		var r_i: float = hd + rayon_max + float(col_vel_len[i]) * delta
		r_par_i[i] = r_i
		if r_i > arete:
			arete = r_i
	arete = maxf(arete * 1.0001, 1e-6)
	var inv_arete: float = 1.0 / arete
	# Coordonnees de case (base globale) + min/max pour linearisation.
	var cx_arr: PackedInt32Array = PackedInt32Array()
	var cy_arr: PackedInt32Array = PackedInt32Array()
	var cz_arr: PackedInt32Array = PackedInt32Array()
	cx_arr.resize(N)
	cy_arr.resize(N)
	cz_arr.resize(N)
	var cx_min: int = 0x7fffffff
	var cx_max: int = -0x7fffffff - 1
	var cy_min: int = 0x7fffffff
	var cy_max: int = -0x7fffffff - 1
	var cz_min: int = 0x7fffffff
	var cz_max: int = -0x7fffffff - 1
	for i in N:
		var pos: Vector3 = (col_ent[i] as Dictionary).position
		var cx: int = floori(pos.x * inv_arete)
		var cy: int = floori(pos.y * inv_arete)
		var cz: int = floori(pos.z * inv_arete)
		cx_arr[i] = cx
		cy_arr[i] = cy
		cz_arr[i] = cz
		if cx < cx_min: cx_min = cx
		if cx > cx_max: cx_max = cx
		if cy < cy_min: cy_min = cy
		if cy > cy_max: cy_max = cy
		if cz < cz_min: cz_min = cz
		if cz > cz_max: cz_max = cz
	var Nx: int = cx_max - cx_min + 1
	var Ny: int = cy_max - cy_min + 1
	var Nz: int = cz_max - cz_min + 1
	var NxNy: int = Nx * Ny
	var total: int = Nx * Ny * Nz
	# Garde-fou : etendue de grille bornee. Au-dela, on continue mais on avertit
	# (probablement une position aberrante, la broadphase reste correcte mais
	# les Packed*Array pesent en memoire). 1M cases = 8 Mo pour counts+offsets.
	if total > 1000000:
		push_error("collision.gd: grille locale > 1M cases (Nx=%d Ny=%d Nz=%d)" % [Nx, Ny, Nz])
	# cell_id lineaire par entite + counts par cell FUSIONNES en UNE passe : cid
	# tenu en variable locale, pas relu depuis cell_ids apres l'ecriture. counts
	# resize (PackedInt32Array initialise a 0) avant la boucle. Ordre preserve :
	# cell_ids+counts, PUIS offsets prefix-sum, PUIS sorted_idx.
	var cell_ids: PackedInt32Array = PackedInt32Array()
	cell_ids.resize(N)
	var counts: PackedInt32Array = PackedInt32Array()
	counts.resize(total)
	for i in N:
		var cid: int = (cx_arr[i] - cx_min) + (cy_arr[i] - cy_min) * Nx + (cz_arr[i] - cz_min) * NxNy
		cell_ids[i] = cid
		counts[cid] += 1
	# offsets = prefix sum. Taille total+1 pour lire offsets[c+1].
	var offsets: PackedInt32Array = PackedInt32Array()
	offsets.resize(total + 1)
	var acc: int = 0
	for c in total:
		offsets[c] = acc
		acc += counts[c]
	offsets[total] = acc
	# Bucket : sorted_idx[offsets[c]..offsets[c+1]] = les indices de la cell c.
	var sorted_idx: PackedInt32Array = PackedInt32Array()
	sorted_idx.resize(N)
	var cursor: PackedInt32Array = PackedInt32Array()
	cursor.resize(total)
	for i in N:
		var cid: int = cell_ids[i]
		sorted_idx[offsets[cid] + cursor[cid]] = i
		cursor[cid] += 1
	# ITERATION PAR CELL, VOISINAGE 3x3x3. Ordre des filtres : distance (le moins
	# cher, rejette gros), vus (dedup), masque (bitand), AABB balayee, narrowphase.
	# GARDE case saturee (implicite) : chaque paire subit masque et AABB balayee
	# AVANT gjk/epa -- meme sur une case saturee, gjk/epa ne tourne que sur les
	# paires qui ont deja passe le filtre AABB. Pas de subdivision recursive.
	var vus: Dictionary = {}
	for c in total:
		var start_c: int = offsets[c]
		var end_c: int = offsets[c + 1]
		if start_c == end_c:
			continue
		@warning_ignore("integer_division")
		var lcz: int = c / NxNy
		var reste: int = c - lcz * NxNy
		@warning_ignore("integer_division")
		var lcy: int = reste / Nx
		var lcx: int = reste - lcy * Nx
		for pi in range(start_c, end_c):
			var i: int = sorted_idx[pi]
			var a = col_ent[i]
			var pos_a: Vector3 = a.position
			var r_a: float = float(r_par_i[i])
			var r_a_sq: float = r_a * r_a
			var masque_a: int = int(col_masque_c[i])
			var swept_a: AABB = col_swept[i]
			for dx in range(-1, 2):
				var vcx: int = lcx + dx
				if vcx < 0 or vcx >= Nx:
					continue
				for dy in range(-1, 2):
					var vcy: int = lcy + dy
					if vcy < 0 or vcy >= Ny:
						continue
					for dz in range(-1, 2):
						var vcz: int = lcz + dz
						if vcz < 0 or vcz >= Nz:
							continue
						var vc: int = vcx + vcy * Nx + vcz * NxNy
						var vs: int = offsets[vc]
						var ve: int = offsets[vc + 1]
						for pj in range(vs, ve):
							var j: int = sorted_idx[pj]
							if j == i:
								continue
							var b = col_ent[j]
							if pos_a.distance_squared_to((b as Dictionary).position) > r_a_sq:
								continue
							# Dedup par clef ENTIERE (mini*N + maxi, N = entites.size()) : les
							# indices i, j du cache colonnes sont deja en main, plus besoin
							# d'allouer une String "ida|idb" ni de la hacher. Dict a clef int.
							var lo: int = i if i < j else j
							var hi: int = j if i < j else i
							var cle: int = lo * N + hi
							if vus.has(cle):
								continue
							vus[cle] = true
							if (masque_a & int(col_masque_c[j])) == 0:
								continue
							if not swept_a.intersects(col_swept[j] as AABB):
								continue
							var contact: Dictionary = _contact_paire(a, i, b, j, delta,
								col_vel, col_vel_len, col_vel_nz, col_orient, col_formes,
								col_taille_min, col_reponse, col_masque_r)
							if not contact.is_empty():
								contacts.append(contact)
	# TRI STABLE des contacts par (min(idx_a, idx_b), max(...)) -- rend
	# `resoudre` deterministe par construction (ordre de composition des
	# separations independant de l'ordre de parcours). Prepare M2 (multithread,
	# ou l'ordre de parcours n'est plus garanti). Indice = position dans le
	# tableau `entites`, MEME grandeur que le C++ (contacts_a/contacts_b sont
	# des indices int du cache colonnes, identiques a la position dans entites).
	# stable_sort obligatoire : plusieurs contacts de meme clef (multi-formes)
	# doivent garder leur ordre d'insertion, identique aux deux cotes puisque
	# le narrowphase itere les formes (fa puis fb) dans le meme ordre.
	if not contacts.is_empty():
		var id_to_idx: Dictionary = {}
		for idx in entites.size():
			id_to_idx[entites[idx].id] = idx
		# STABILISATION par index d'insertion : Array.sort_custom de Godot 4
		# n'est PAS garanti stable (introsort). Decorate-sort-undecorate avec
		# l'indice d'origine `k` en dernier critere -- deux contacts de meme
		# (lo, hi) gardent leur ordre d'insertion. Necessaire pour matcher le
		# std::stable_sort du C++.
		var decore: Array = []
		for k in contacts.size():
			var c: Dictionary = contacts[k]
			var a_i: int = int(id_to_idx[c.a.id])
			var b_i: int = int(id_to_idx[c.b.id])
			var lo: int = a_i if a_i < b_i else b_i
			var hi: int = b_i if a_i < b_i else a_i
			decore.append([lo, hi, k, c])
		decore.sort_custom(func(x, y):
			if x[0] != y[0]:
				return x[0] < y[0]
			if x[1] != y[1]:
				return x[1] < y[1]
			return x[2] < y[2])
		var trie: Array = []
		for item in decore:
			trie.append(item[3])
		contacts = trie
	return contacts

# Narrowphase avec swept : echantillonne le trajet parcouru [position -
# velocite*delta, position] en N sous-pas (N grandit si le deplacement depasse
# la moitie de la plus petite dimension) et rend le PREMIER contact rencontre en
# partant de l'endpoint (k=0) vers l'arriere. {} si aucun. Lit uniquement les
# colonnes du cache (col_*) indexees par i, j -- aucun appel a
# _velocite/_orientation/_taille_min_entite ici. Le contact rendu embarque
# reponse/masque_reponse/vel_nz pour que resoudre n'ait pas non plus a
# relire les entites.
static func _contact_paire(a, i: int, b, j: int, delta: float,
		col_vel: PackedVector3Array, col_vel_len: PackedFloat32Array,
		col_vel_nz: PackedByteArray, col_orient: Array[Basis],
		col_formes: Array, col_taille_min: PackedFloat32Array,
		col_reponse: PackedStringArray, col_masque_r: PackedInt32Array) -> Dictionary:
	var vel_a: Vector3 = col_vel[i]
	var vel_b: Vector3 = col_vel[j]
	var pos_a: Vector3 = a.position
	var pos_b: Vector3 = b.position
	var orient_a: Basis = col_orient[i]
	var orient_b: Basis = col_orient[j]
	var n := 1
	var tm_a: float = float(col_taille_min[i])
	var tm_b: float = float(col_taille_min[j])
	var vla: float = float(col_vel_len[i])
	var vlb: float = float(col_vel_len[j])
	if tm_a > 0.0 and vla * delta > tm_a * 0.5:
		n = maxi(n, int(ceil(vla * delta / (tm_a * 0.5))))
	if tm_b > 0.0 and vlb * delta > tm_b * 0.5:
		n = maxi(n, int(ceil(vlb * delta / (tm_b * 0.5))))
	var formes_a: Array = col_formes[i]
	var formes_b: Array = col_formes[j]
	for k in range(n + 1):
		var frac: float = float(k) / float(n)
		var pe: Vector3 = pos_a - vel_a * delta * frac
		var po: Vector3 = pos_b - vel_b * delta * frac
		for fa in formes_a:
			var ta: Transform3D = Transform3D(orient_a, pe) * fa.get("transform_locale", Transform3D.IDENTITY)
			for fb in formes_b:
				var tb: Transform3D = Transform3D(orient_b, po) * fb.get("transform_locale", Transform3D.IDENTITY)
				var r: Dictionary = contact_forme_paire(fa, ta, fb, tb)
				if not r.is_empty():
					return {
						"a": a, "b": b,
						"normale": r.normale, "profondeur": r.profondeur,
						"a_reponse": col_reponse[i], "b_reponse": col_reponse[j],
						"a_masque_r": int(col_masque_r[i]), "b_masque_r": int(col_masque_r[j]),
						"a_vel_nz": bool(col_vel_nz[i]), "b_vel_nz": bool(col_vel_nz[j]),
					}
	return {}

# RACCOURCI boite-boite AABB-alignee : quand les deux formes sont "boite" et
# que leurs transforms monde n'ont pas de rotation (basis == IDENTITY), le
# contact se calcule par recouvrement d'AABB direct -- normale = axe de plus
# petit recouvrement, profondeur = ce recouvrement. Meme resultat que gjk/epa
# sur ce cas (verrouille par test de parite), mais sans les 32 iterations
# bornees ni les 6 supports par AABB. Tout autre cas (une capsule, une orient
# tournee, un transform_locale rotate) retombe sur gjk/epa inchange.
static func contact_forme_paire(fa: Dictionary, ta: Transform3D, fb: Dictionary, tb: Transform3D) -> Dictionary:
	if String(fa.get("type", "")) == "boite" and String(fb.get("type", "")) == "boite" \
			and ta.basis == Basis.IDENTITY and tb.basis == Basis.IDENTITY:
		var ha: Vector3 = fa.get("parametres", {}).get("demi_taille", Vector3.ZERO)
		var hb: Vector3 = fb.get("parametres", {}).get("demi_taille", Vector3.ZERO)
		var delta_c: Vector3 = tb.origin - ta.origin
		var rx: float = ha.x + hb.x - absf(delta_c.x)
		if rx <= 0.0:
			return {}
		var ry: float = ha.y + hb.y - absf(delta_c.y)
		if ry <= 0.0:
			return {}
		var rz: float = ha.z + hb.z - absf(delta_c.z)
		if rz <= 0.0:
			return {}
		var normale: Vector3
		var profondeur: float
		if rx <= ry and rx <= rz:
			var s: float = signf(delta_c.x)
			normale = Vector3(s if s != 0.0 else 1.0, 0.0, 0.0)
			profondeur = rx
		elif ry <= rz:
			var s2: float = signf(delta_c.y)
			normale = Vector3(0.0, s2 if s2 != 0.0 else 1.0, 0.0)
			profondeur = ry
		else:
			var s3: float = signf(delta_c.z)
			normale = Vector3(0.0, 0.0, s3 if s3 != 0.0 else 1.0)
			profondeur = rz
		return {"normale": normale, "profondeur": profondeur}
	var g: Dictionary = gjk(fa, ta, fb, tb)
	if g.intersecte:
		var ep: Dictionary = epa(g.simplexe, fa, ta, fb, tb)
		return {"normale": ep.normale, "profondeur": ep.profondeur}
	return {}

static func _aabb_entite(e) -> AABB:
	return _aabb_from(_orientation(e), e.get("proprietes", {}).get("formes", []), e.position)

# CACHE D'AABB LOCALE PAR FORME : les unites d'une population partagent une
# meme instance de forme (peuplement : 1600 unites, meme boite). L'AABB LOCALE
# (forme placee a orient=IDENTITY, pos=ZERO, avec son transform_locale
# applique) ne depend PAS de la position monde ni de l'orientation de l'entite
# -- elle ne bouge pas tant que la geometrie de la forme ne bouge pas. On la
# calcule une fois via aabb_forme puis on la range.
#
# CLEF : un id INT injecte dans la forme (`forme["_aabb_id"]`) au premier
# passage. Evite de hasher le Dictionary forme a chaque acces (2 lookups sur
# String vs 1 hash de contenu de Dict) ; permet aussi un cache Array plat
# (index -> AABB) au lieu d'un Dictionary. La mutation de la forme est
# intentionnelle : plusieurs entites qui partagent la meme instance forme
# voient toutes le meme id.
#
# POINT NOIR : cache jamais invalide. Si une forme CHANGE de contenu en
# gardant la meme reference (hitbox d'animation, morph), le cache reste sur
# l'ancien AABB local -- il faudra ajouter une invalidation (bump d'id ou
# horloge de version). Formes STABLES pour l'instant, hors scope.
static var _cache_aabb_locale: Array[AABB] = []
# Cache parallele SYNCHRONISE avec _cache_aabb_locale par le meme _aabb_id :
# une entree par forme distincte, meme id que dans _cache_aabb_locale. Rempli
# par _cacher_forme -- toujours meme longueur que _cache_aabb_locale.
static var _cache_taille_min_forme: PackedFloat32Array = PackedFloat32Array()

# Alloue un id INT a une forme (mute forme["_aabb_id"]) et remplit les deux
# caches par-forme (AABB locale et taille_min). Une seule facon d'ajouter une
# entree aux caches -- garantit que _cache_aabb_locale et
# _cache_taille_min_forme restent alignes. Sans effet si l'id existe deja.
static func _cacher_forme(forme: Dictionary) -> int:
	var id: int = int(forme.get("_aabb_id", -1))
	if id >= 0:
		return id
	var a: AABB = aabb_forme(forme, forme.get("transform_locale", Transform3D.IDENTITY))
	var t: float = _taille_min_forme(forme)
	id = _cache_aabb_locale.size()
	_cache_aabb_locale.append(a)
	_cache_taille_min_forme.append(t)
	forme["_aabb_id"] = id
	return id

static func _aabb_locale_de_forme(forme: Dictionary) -> AABB:
	var id: int = int(forme.get("_aabb_id", -1))
	if id >= 0:
		return _cache_aabb_locale[id]
	return _cache_aabb_locale[_cacher_forme(forme)]

# Somme min des tailles min de chaque forme, via le cache par-forme. Retombe
# sur _taille_min_forme (calcul complet) pour une forme jamais vue -- meme
# esprit que _aabb_locale_de_forme.
static func _taille_min_formes_cache(formes: Array) -> float:
	var m: float = INF
	for f in formes:
		var id: int = int((f as Dictionary).get("_aabb_id", -1))
		if id < 0:
			id = _cacher_forme(f)
		var t: float = _cache_taille_min_forme[id]
		if t < m:
			m = t
	return 0.0 if m == INF else m

# AABB monde d'un ensemble de formes deja resolues (orient + formes + position
# passes directement). Utilise par _aabb_entite et par _ecrire_cache.
# Cas dominant (orient IDENTITY) : AABB locale cachee, translation. Cas
# tournee : recalcul complet par aabb_forme (l'AABB monde d'une AABB locale
# tournee n'est pas la translation de l'AABB locale, il faut projeter).
static func _aabb_from(orient: Basis, formes: Array, pos: Vector3) -> AABB:
	if formes.is_empty():
		return AABB(pos, Vector3.ZERO)
	var identity_orient: bool = orient == Basis.IDENTITY
	var res: AABB
	if identity_orient:
		var local0: AABB = _aabb_locale_de_forme(formes[0])
		res = AABB(local0.position + pos, local0.size)
		for i in range(1, formes.size()):
			var li: AABB = _aabb_locale_de_forme(formes[i])
			res = res.merge(AABB(li.position + pos, li.size))
	else:
		res = aabb_forme(formes[0], Transform3D(orient, pos) * formes[0].get("transform_locale", Transform3D.IDENTITY))
		for i in range(1, formes.size()):
			res = res.merge(aabb_forme(formes[i], Transform3D(orient, pos) * formes[i].get("transform_locale", Transform3D.IDENTITY)))
	return res

# AABB de l'entite a sa position ET a sa position d'il y a un tick (couvre le
# trajet swept) -- pour la broadphase. Lit proprietes.aabb_cache si present
# (ecrit par la pre-passe de detecter), sinon recalcule via _aabb_entite : la
# broadphase reste correcte (jamais un faux negatif) meme si le cache manque.
static func _aabb_balayee(e, delta: float) -> AABB:
	var a: AABB = _aabb_cachee(e)
	var vel: Vector3 = _velocite(e)
	if vel.length_squared() <= 0.0:
		return a
	var b := AABB(a.position - vel * delta, a.size)
	return a.merge(b)

# AABB de l'entite lue dans son cache proprietes.aabb_cache si present, sinon
# recalculee. Le cache est ecrit par la pre-passe de detecter, donc frais pour
# toute entite passee dans le meme appel. Une entite trouvee par la broadphase
# mais absente de la liste passee a detecter n'a pas ce cache -- fallback safe
# sur _aabb_entite.
static func _aabb_cachee(e) -> AABB:
	var pr: Dictionary = e.get("proprietes", {})
	if pr.has("aabb_cache"):
		return pr["aabb_cache"]
	return _aabb_entite(e)

static func _taille_min_entite(e) -> float:
	return _taille_min_formes(e.get("proprietes", {}).get("formes", []))

static func _taille_min_formes(formes: Array) -> float:
	var m := INF
	for f in formes:
		m = minf(m, _taille_min_forme(f))
	return 0.0 if m == INF else m

static func _taille_min_forme(forme: Dictionary) -> float:
	var p: Dictionary = forme.get("parametres", {})
	match String(forme.get("type", "")):
		"sphere":
			return float(p.get("rayon", 0.0))
		"boite":
			var h: Vector3 = p.get("demi_taille", Vector3.ZERO)
			return minf(h.x, minf(h.y, h.z))
		"capsule":
			return float(p.get("rayon", 0.0))
		"hull":
			var pts: Array = p.get("points", [])
			if pts.is_empty():
				return 0.0
			var mn: Vector3 = pts[0]
			var mx: Vector3 = pts[0]
			for q in pts:
				mn = Vector3(minf(mn.x, q.x), minf(mn.y, q.y), minf(mn.z, q.z))
				mx = Vector3(maxf(mx.x, q.x), maxf(mx.y, q.y), maxf(mx.z, q.z))
			var half: Vector3 = (mx - mn) * 0.5
			return minf(half.x, minf(half.y, half.z))
	return 0.0

static func _prop(e, cle: String, defaut):
	var pr: Dictionary = e.get("proprietes", {})
	if pr.has(cle):
		return pr[cle]
	if e.has(cle):
		return e[cle]
	return defaut

static func _velocite(e) -> Vector3:
	return _prop(e, "velocite", Vector3.ZERO)

static func _orientation(e) -> Basis:
	return _prop(e, "orientation", Basis.IDENTITY)


# --- RESOLUTION : separe les paires qui se bloquent ---
# Pour chaque contact ou les deux entites ont reponse == "bloque" ET des
# masque_reponse compatibles, ecarte le long de la normale (A->B) de la
# profondeur. Repartition : une entite immobile (velocite nulle) ne bouge pas,
# l'autre encaisse tout ; deux mobiles se partagent 50/50 ; deux immobiles
# 50/50 (evite l'interpenetration figee). Mutation DIRECTE de entite.position.
# Passe unique (pas de resolution iterative multi-contacts, voir "ne fait pas").
static func resoudre(contacts: Array, _entites: Array) -> void:
	for c in contacts:
		var prof: float = float(c.profondeur)
		var normale: Vector3 = c.normale
		if prof <= _EPS or normale.length_squared() < _EPS:
			continue
		# Champs entite MIS EN CACHE par _contact_paire dans le contact lui-meme :
		# resoudre ne rappelle plus _prop/_velocite sur a ni sur b -- tout ce
		# dont il a besoin voyage avec le contact.
		if String(c.a_reponse) != "bloque" or String(c.b_reponse) != "bloque":
			continue
		if (int(c.a_masque_r) & int(c.b_masque_r)) == 0:
			continue
		var a_mobile: bool = bool(c.a_vel_nz)
		var b_mobile: bool = bool(c.b_vel_nz)
		var part_a := 0.5
		var part_b := 0.5
		if a_mobile and not b_mobile:
			part_a = 1.0
			part_b = 0.0
		elif b_mobile and not a_mobile:
			part_a = 0.0
			part_b = 1.0
		# normale pointe A->B : A s'ecarte en -normale, B en +normale.
		var a = c.a
		var b = c.b
		a.position -= normale * prof * part_a
		b.position += normale * prof * part_b
