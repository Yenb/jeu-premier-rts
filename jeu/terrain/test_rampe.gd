extends SceneTree

# Test manuel :
# godot --headless --script jeu/terrain/test_rampe.gd
#
# Verrouille l'item RAMPE de la bibliotheque res://jeu/terrain/bloc.tres :
# - il porte un maillage, une teinte plus sombre que le bloc plein, et une forme
#   de collision qui n'est PAS une boite ;
# - la forme epouse le maillage sommet pour sommet -- une boite passerait toutes
#   les verifications visuelles et laisserait un objet flotter au-dessus de la
#   pente sans que rien a l'ecran ne le montre ;
# - la pente reelle se mesure au rayon lance vers le bas sur une rampe POSEE dans
#   un GridMap, jamais sur la ressource seule : entre les deux il y a le centrage
#   des cellules et l'orientation, et c'est la que ca casse ;
# - une rampe tournee d'un demi-tour monte dans la direction OPPOSEE.
#
# Entree : res://jeu/terrain/bloc.tres, plus un GridMap construit ici (jamais
# enregistre dans une scene) portant deux rampes, l'une droite l'autre tournee.
# Sortie : une ligne « OK: » et le code 0 si tout tient, « ECHEC: » et le code 1
# sinon, chaque manquement pousse en erreur par verif.gd.
#
# RIEN N'EST SUPPOSE DE LA GEOMETRIE DE LA CELLULE : les cotes se demandent au
# GridMap (map_to_local, cell_size) au lieu d'etre recalculees ici. Le centrage
# des cellules est un reglage du noeud, pas une constante de ce fichier.
#
# LE SENS DE LA MONTEE N'EST PAS ECRIT EN DUR. Il est LU sur la rampe droite,
# puis la rampe tournee doit rendre l'inverse : le test survit a une rampe
# retournee dans la bibliotheque, et ne tient que ce qui compte -- que le
# demi-tour du GridMap inverse la pente.
#
# Regles tenues : positions en Vector3, jamais Vector2. Aucun hasard. Les prints
# sont des traces de mise au point, pas du texte joueur. Rien de scripts/, data/
# ni addons/ n'est ecrit.

const Verif = preload("res://scripts/verif.gd")

const CHEMIN_BIBLIOTHEQUE := "res://jeu/terrain/bloc.tres"

const ITEM_BLOC := 0
const ITEM_RAMPE := 2

# Les deux cellules d'essai, assez loin l'une de l'autre pour qu'aucun rayon ne
# puisse toucher la voisine.
const CELLULE_DROITE := Vector3i(0, 0, 0)
const CELLULE_TOURNEE := Vector3i(6, 0, 0)

# Ou sonder la pente, en fraction de demi-cellule depuis le centre, sur l'axe x.
# Ni 0 (les deux sondes se confondraient au milieu de la pente) ni 1 (l'arete,
# ou le rayon glisse au bord de la forme).
const SONDE := 0.6

# D'ou part le rayon au-dessus de la cellule, en cellules.
const HAUTEUR_DE_TIR := 3.0

# Tolerance sur une cote lue au rayon. Une intersection est exacte a la
# precision flottante pres ; le reste vient de la marge des formes convexes.
const TOLERANCE := 0.05

var _v
var _racine: Node3D
var _grille: GridMap
var _pas := 0

func _init() -> void:
	_v = Verif.new()

	var bibliotheque := load(CHEMIN_BIBLIOTHEQUE) as MeshLibrary
	_v.v(bibliotheque != null, "%s introuvable ou illisible" % CHEMIN_BIBLIOTHEQUE)
	if bibliotheque == null:
		_conclure()
		return

	if not _ressource_de_la_rampe(bibliotheque):
		_conclure()
		return

	_racine = Node3D.new()
	_racine.name = "EssaiRampe"
	root.add_child(_racine)

	_grille = GridMap.new()
	_grille.name = "Terrain"
	_grille.mesh_library = bibliotheque
	_racine.add_child(_grille)

	_grille.set_cell_item(CELLULE_DROITE, ITEM_RAMPE)
	_grille.set_cell_item(CELLULE_TOURNEE, ITEM_RAMPE,
		_grille.get_orthogonal_index_from_basis(Basis(Vector3.UP, PI)))

	# Le rayon a besoin d'un espace physique deja pas : les corps du GridMap sont
	# construits a l'entree dans l'arbre, l'espace ne les connait qu'au pas
	# suivant.
	physics_frame.connect(_sur_pas_physique)

# Ce que la RESSOURCE doit porter, avant toute mise en scene. Le verifier ici
# nomme le fichier a rouvrir quand une pente s'aplatit, au lieu de laisser
# chercher entre la bibliotheque, la scene et le moteur physique.
func _ressource_de_la_rampe(bibliotheque: MeshLibrary) -> bool:
	var items := bibliotheque.get_item_list()
	_v.v(items.has(ITEM_RAMPE), "la bibliotheque n'a aucun item %d : la rampe manque" % ITEM_RAMPE)
	if not items.has(ITEM_RAMPE):
		return false

	var maillage := bibliotheque.get_item_mesh(ITEM_RAMPE)
	_v.v(maillage != null, "l'item %d n'a aucun maillage : rien ne s'affichera" % ITEM_RAMPE)
	if maillage == null:
		return false

	# Meme encombrement que le bloc plein : une rampe qui deborde de sa cellule
	# se pose de travers partout sur la carte, sans erreur.
	var bloc := bibliotheque.get_item_mesh(ITEM_BLOC)
	if bloc != null:
		var attendu := bloc.get_aabb()
		var mesure := maillage.get_aabb()
		_v.v(mesure.position.is_equal_approx(attendu.position)
			and mesure.size.is_equal_approx(attendu.size),
			"la rampe n'occupe pas la meme cellule que le bloc : %s au lieu de %s" % [
				mesure, attendu])

	_v.v(_teinte(maillage) < _teinte(bloc),
		"la rampe n'est pas plus sombre que le bloc : rien ne l'en distingue dans la palette")

	var formes := bibliotheque.get_item_shapes(ITEM_RAMPE)
	_v.v(formes.size() >= 2, "l'item %d n'a aucune forme de collision : il se traverse" % ITEM_RAMPE)
	if formes.size() < 2:
		return false

	var forme: Shape3D = formes[0]
	_v.v(not (forme is BoxShape3D),
		"la collision de la rampe est une boite : un objet flotterait au-dessus de la pente")
	_v.v(forme is ConvexPolygonShape3D,
		"la collision de la rampe n'est pas un ConvexPolygonShape3D mais un %s" % forme.get_class())
	if not (forme is ConvexPolygonShape3D):
		return false

	# La forme et le maillage, sommet pour sommet. Deux listes qui divergent
	# donnent une pente vue et une pente touchee qui ne sont pas la meme.
	var vus := _sommets(maillage.get_faces())
	var touches := _sommets((forme as ConvexPolygonShape3D).points)
	_v.v(vus == touches,
		"la collision ne suit pas le maillage : touche %s, affiche %s" % [touches, vus])
	print("rampe : %d sommets, collision %s" % [vus.size(), forme.get_class()])
	return true

# La clarte d'un maillage, par la couleur de son materiau. Rend 1.0 quand il n'y
# a pas de materiau : sans couleur lisible, la comparaison doit rater, jamais
# passer par defaut.
func _teinte(maillage: Mesh) -> float:
	if maillage == null:
		return 1.0
	var materiau := maillage.surface_get_material(0) as StandardMaterial3D
	if materiau == null:
		return 1.0
	var c := materiau.albedo_color
	return c.r + c.v + c.b

# Les sommets d'une soupe de triangles, dedoublonnes et ranges, en texte : deux
# geometries identiques listees dans un ordre different doivent se comparer
# egales.
func _sommets(points: PackedVector3Array) -> PackedStringArray:
	var vus := {}
	for p in points:
		vus["%.3f %.3f %.3f" % [p.x, p.y, p.z]] = true
	var liste := PackedStringArray(vus.keys())
	liste.sort()
	return liste

func _sur_pas_physique() -> void:
	_pas += 1
	if _pas < 2:
		return
	physics_frame.disconnect(_sur_pas_physique)
	_mesurer_la_pente()
	_conclure()

func _mesurer_la_pente() -> void:
	var bas_droite: Variant = _cote_touchee(CELLULE_DROITE, -SONDE)
	var haut_droite: Variant = _cote_touchee(CELLULE_DROITE, SONDE)
	if bas_droite == null or haut_droite == null:
		_v.v(false, "un rayon n'a rien touche sur la rampe droite : pas de collision posee")
		return

	var pente := (haut_droite as float) - (bas_droite as float)
	var demi := _grille.cell_size.y * 0.5

	# La pente monte vraiment : d'un bord a l'autre, la cote change de toute la
	# denivellation attendue entre les deux sondes. Une boite rendrait zero.
	var attendue := _grille.cell_size.y * SONDE
	_v.v(absf(absf(pente) - attendue) < TOLERANCE,
		"la denivellation entre les deux sondes est %.3f, attendue %.3f : la pente est fausse" % [
			absf(pente), attendue])

	# Et elle reste DANS la cellule : une cote au-dela d'une demi-cellule du
	# centre veut dire que la forme deborde en hauteur.
	var centre := _grille.map_to_local(CELLULE_DROITE)
	for cote in [bas_droite as float, haut_droite as float]:
		_v.v(absf(cote - centre.y) <= demi + TOLERANCE,
			"une cote touchee (%.3f) sort de la cellule centree en %.3f" % [cote, centre.y])

	var bas_tournee: Variant = _cote_touchee(CELLULE_TOURNEE, -SONDE)
	var haut_tournee: Variant = _cote_touchee(CELLULE_TOURNEE, SONDE)
	if bas_tournee == null or haut_tournee == null:
		_v.v(false, "un rayon n'a rien touche sur la rampe tournee : le demi-tour l'a fait disparaitre")
		return

	var pente_tournee := (haut_tournee as float) - (bas_tournee as float)
	print("pente droite = %+.3f, pente apres demi-tour = %+.3f (sondes a x %+.1f et %+.1f)" % [
		pente, pente_tournee, -SONDE, SONDE])

	# Le coeur du test : meme denivellation, sens inverse. Les deux ensemble,
	# jamais le signe seul -- une rampe ecrasee par la rotation inverserait bien
	# son sens en perdant sa hauteur.
	_v.v(absf(pente_tournee + pente) < TOLERANCE,
		"le demi-tour n'inverse pas la pente : %+.3f d'un cote, %+.3f de l'autre" % [
			pente, pente_tournee])

# La cote du premier point touche par un rayon lance vers le bas au-dessus d'une
# cellule, decale de `decalage` demi-cellules sur x depuis son centre. Rend null
# quand le rayon ne touche rien : il n'existe pas de cote sentinelle qu'un
# appelant prendrait pour une surface.
func _cote_touchee(cellule: Vector3i, decalage: float) -> Variant:
	var centre := _grille.map_to_local(cellule)
	var x := centre.x + decalage * _grille.cell_size.x * 0.5
	var depart := Vector3(x, centre.y + HAUTEUR_DE_TIR * _grille.cell_size.y, centre.z)
	var arrivee := Vector3(x, centre.y - _grille.cell_size.y, centre.z)

	var requete := PhysicsRayQueryParameters3D.create(
		_grille.to_global(depart), _grille.to_global(arrivee))
	var touche := _grille.get_world_3d().direct_space_state.intersect_ray(requete)
	if touche.is_empty():
		return null
	return (_grille.to_local(touche["position"]) as Vector3).y

func _conclure() -> void:
	if _racine != null:
		_racine.queue_free()
	if _v.echecs() > 0:
		print("ECHEC: l'item rampe de la bibliotheque ne tient pas (%d)" % _v.echecs())
		quit(1)
		return
	print("OK: rampe -- pente pleine hauteur, collision qui epouse le maillage, demi-tour qui inverse la montee")
	quit(0)
