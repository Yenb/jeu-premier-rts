extends RefCounted

# Systeme de collision GENERALISTE en donnee pure (prototype Orion). Tout
# statique, AUCUN etat interne : chaque fonction recoit ce dont elle a besoin.
# AUCUNE physique Godot (PhysicsServer3D / StaticBody3D / CollisionShape3D) :
# une forme est un Dictionary, une entite est un Dictionary, la collision se
# calcule sur ces donnees, partout et tout le temps (hors rendu comme dans le
# rendu). A reutiliser pour tout futur objet interactif.
#
# SYSTEME COMPLET : SUPPORT unifiee, AABB par forme, GJK, EPA, tick (broadphase
# monde.gd + narrowphase + swept) et resoudre (separation en donnee pure).
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
static func aabb_forme(forme: Dictionary, transform_monde: Transform3D) -> AABB:
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

# --- TICK : liste des contacts pour un ensemble d'entites ---
# Broadphase par monde.gd (une requete par entite, rayon = demi-diagonale de son
# AABB + demi-diagonale MAX du voisinage + deplacement swept, ce qui garantit de
# ne rater aucune paire dont les AABB balayees se touchent). Filtre par
# masque_collision puis recouvrement d'AABB balayees. Narrowphase GJK->EPA par
# paire de formes, avec SWEPT (sous-pas si le deplacement d'une entite depasse
# la moitie de sa plus petite dimension). Rend un Array de contacts
# { a, b, normale (A->B), profondeur }.
#
# ENTITE : position (Vector3, top-level, requis par monde.gd) ; le reste dans
# proprietes : formes (Array { type, transform_locale, parametres }), velocite
# (Vector3), orientation (Basis), masque_collision (int), masque_reponse (int),
# reponse (String), aabb_cache (rafraichie ici). transform monde d'une forme =
# Transform3D(orientation, position) * transform_locale.
static func tick(monde, entites: Array, delta: float) -> Array:
	var contacts: Array = []
	var rayon_max := 0.0
	for e in entites:
		rayon_max = maxf(rayon_max, _aabb_entite(e).size.length() * 0.5)
	var vus: Dictionary = {}
	for e in entites:
		var aabb_e := _aabb_entite(e)
		e.proprietes["aabb_cache"] = aabb_e  # rafraichit le cache
		var hd_e: float = aabb_e.size.length() * 0.5
		var r: float = hd_e + rayon_max + _velocite(e).length() * delta
		for entree in monde.choses_dans_rayon(e.position, r):
			var o = entree.chose
			if o == e:
				continue
			if not (o is Dictionary and (o.get("proprietes", {}) as Dictionary).has("formes")):
				continue
			var cle: String = _cle_paire(e, o)
			if vus.has(cle):
				continue
			vus[cle] = true
			if (int(_prop(e, "masque_collision", 0)) & int(_prop(o, "masque_collision", 0))) == 0:
				continue
			if not _aabb_balayee(e, delta).intersects(_aabb_balayee(o, delta)):
				continue
			var c: Dictionary = _contact_paire(e, o, delta)
			if not c.is_empty():
				contacts.append(c)
	return contacts

# Narrowphase avec swept : echantillonne le trajet parcouru [position -
# velocite*delta, position] en N sous-pas (N grandit si le deplacement depasse
# la moitie de la plus petite dimension) et rend le PREMIER contact rencontre en
# partant de l'endpoint (k=0) vers l'arriere. {} si aucun.
static func _contact_paire(e, o, delta: float) -> Dictionary:
	var vel_e: Vector3 = _velocite(e)
	var vel_o: Vector3 = _velocite(o)
	var pos_e: Vector3 = e.position
	var pos_o: Vector3 = o.position
	var orient_e: Basis = _orientation(e)
	var orient_o: Basis = _orientation(o)
	var n := 1
	var tm_e: float = _taille_min_entite(e)
	var tm_o: float = _taille_min_entite(o)
	if tm_e > 0.0 and vel_e.length() * delta > tm_e * 0.5:
		n = maxi(n, int(ceil(vel_e.length() * delta / (tm_e * 0.5))))
	if tm_o > 0.0 and vel_o.length() * delta > tm_o * 0.5:
		n = maxi(n, int(ceil(vel_o.length() * delta / (tm_o * 0.5))))
	var formes_e: Array = e.proprietes.get("formes", [])
	var formes_o: Array = o.proprietes.get("formes", [])
	for k in range(n + 1):
		var frac: float = float(k) / float(n)
		var pe: Vector3 = pos_e - vel_e * delta * frac
		var po: Vector3 = pos_o - vel_o * delta * frac
		for fa in formes_e:
			var ta: Transform3D = Transform3D(orient_e, pe) * fa.get("transform_locale", Transform3D.IDENTITY)
			for fb in formes_o:
				var tb: Transform3D = Transform3D(orient_o, po) * fb.get("transform_locale", Transform3D.IDENTITY)
				var g: Dictionary = gjk(fa, ta, fb, tb)
				if g.intersecte:
					var ep: Dictionary = epa(g.simplexe, fa, ta, fb, tb)
					return {"a": e, "b": o, "normale": ep.normale, "profondeur": ep.profondeur}
	return {}

static func _aabb_entite(e) -> AABB:
	var formes: Array = e.get("proprietes", {}).get("formes", [])
	if formes.is_empty():
		return AABB(e.position, Vector3.ZERO)
	var orient: Basis = _orientation(e)
	var res: AABB = aabb_forme(formes[0], Transform3D(orient, e.position) * formes[0].get("transform_locale", Transform3D.IDENTITY))
	for i in range(1, formes.size()):
		res = res.merge(aabb_forme(formes[i], Transform3D(orient, e.position) * formes[i].get("transform_locale", Transform3D.IDENTITY)))
	return res

# AABB de l'entite a sa position ET a sa position d'il y a un tick (couvre le
# trajet swept) -- pour la broadphase.
static func _aabb_balayee(e, delta: float) -> AABB:
	var a := _aabb_entite(e)
	var vel: Vector3 = _velocite(e)
	if vel.length_squared() <= 0.0:
		return a
	var b := AABB(a.position - vel * delta, a.size)
	return a.merge(b)

static func _taille_min_entite(e) -> float:
	var formes: Array = e.get("proprietes", {}).get("formes", [])
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

static func _cle_paire(e, o) -> String:
	var ia: String = String(e.get("id", ""))
	var ib: String = String(o.get("id", ""))
	return ia + "|" + ib if ia < ib else ib + "|" + ia

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
		var a = c.a
		var b = c.b
		if String(_prop(a, "reponse", "")) != "bloque" or String(_prop(b, "reponse", "")) != "bloque":
			continue
		if (int(_prop(a, "masque_reponse", 0)) & int(_prop(b, "masque_reponse", 0))) == 0:
			continue
		var a_mobile: bool = _velocite(a).length_squared() > 0.0
		var b_mobile: bool = _velocite(b).length_squared() > 0.0
		var part_a := 0.5
		var part_b := 0.5
		if a_mobile and not b_mobile:
			part_a = 1.0
			part_b = 0.0
		elif b_mobile and not a_mobile:
			part_a = 0.0
			part_b = 1.0
		# normale pointe A->B : A s'ecarte en -normale, B en +normale.
		a.position -= normale * prof * part_a
		b.position += normale * prof * part_b
