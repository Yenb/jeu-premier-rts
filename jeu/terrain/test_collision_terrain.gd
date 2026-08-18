extends SceneTree

# Test manuel :
# godot --headless --script jeu/terrain/test_collision_terrain.gd
#
# Verrouille les deux solidites du terrain, avec un corps TEMOIN pour chacune :
# - LE SOL arrete ce qui tombe : une bille lachee au-dessus de la surface s'y
#   pose au lieu de la traverser.
# - LA CEINTURE arrete ce qui sort : une bille lancee vers le bord s'y ecrase au
#   lieu de quitter le plateau.
# Verrouille aussi que la ceinture reste INVISIBLE : son item ne porte aucun
# maillage.
#
# La collision ne vient pas de la scene mais de la BIBLIOTHEQUE
# (res://jeu/terrain/bloc.tres) -- le GridMap l'applique a toutes ses cellules
# d'un coup. Un item sans forme laisse un terrain qui s'affiche parfaitement et a
# travers lequel tout tombe : rien a l'ecran ne distingue les deux cas.
#
# CE TEST EST LA SEULE FACON DE SAVOIR SI LA CEINTURE EXISTE. Elle n'a aucun
# maillage : ni l'editeur ni le jeu n'en montrent quoi que ce soit, et une
# ceinture effacee ne se verrait qu'au premier agent tombe dans le vide.
#
# Entree : res://jeu/terrain/carte.tscn, lue sur le disque, plus deux corps
# temoins construits ici (jamais enregistres dans la scene).
# Sortie : une ligne « OK: » et le code 0 si les deux temoins sont arretes,
# « ECHEC: » et le code 1 sinon, chaque manquement pousse en erreur par verif.gd.
#
# RIEN N'EST SUPPOSE DE LA GEOMETRIE, tout se mesure sur la grille. Le relief est
# sculpte a la main : la hauteur de la surface change d'une colonne a l'autre, et
# la couche ou lancer le second temoin doit etre CHERCHEE -- un couloir encombre
# par le relief ferait passer le test sans que la ceinture y soit pour rien. Les
# cotes se demandent au GridMap (map_to_local) au lieu d'etre recalculees : le
# centrage des cellules est un reglage du noeud, pas une constante de ce fichier.
#
# LE VERDICT ATTEND UN NOMBRE FIXE DE PAS, jamais l'immobilite d'un temoin :
# s'arreter des que la vitesse tombe a zero conclurait a la premiere frame, ou
# aucun des deux n'a encore bouge.
#
# Regles tenues : positions en Vector3, jamais Vector2. Aucun hasard. Les prints
# sont des traces de mise au point, pas du texte joueur. Rien de scripts/, data/
# ni addons/ n'est ecrit.

const Verif = preload("res://scripts/verif.gd")
const Generateur = preload("res://jeu/terrain/generer_carte.gd")

const CHEMIN_SCENE := "res://jeu/terrain/carte.tscn"
const NOM_TERRAIN := "Terrain"

# Hauteur de lacher au-dessus de la surface, et rayon des temoins. Des billes
# plutot que des boites : elles ne peuvent pas se coincer sur une arete dans une
# pose qui fausserait la cote finale.
const CHUTE := 6.0
const RAYON_TEMOIN := 0.5

# 60 Hz par defaut : trois secondes, la ou six metres de chute en demandent
# environ une.
const PAS_ATTENDUS := 180

# Tolerance sur la cote de repos. Un contact physique laisse toujours un
# enfoncement de quelques millimetres, et Jolt en autorise plus qu'il n'en faut
# ici.
const TOLERANCE := 0.25

# Colonne du lacher, en cellules. Le centre du terrain : la seule colonne dont
# l'existence ne depend d'aucun choix de sculpture.
const COLONNE := Vector2i(0, 0)

# De quelle couche part la recherche du sommet. Au-dessus, il n'y a rien a
# trouver au centre du terrain.
const COUCHE_HAUTE_CHERCHEE := 64

# Le second temoin est lance a plat, gravite coupee : ce qui est teste est la
# ceinture, pas la chute. Sa vitesse reste sous une demi-cellule par pas -- au
# dela, une bille traverserait un mur de deux metres sans le toucher.
const VITESSE_VERS_LE_BORD := 25.0
const RECUL_DU_LANCEMENT := 8.0

# Longueur du couloir vide exige devant le second temoin, en cellules. Sans lui,
# le temoin s'arreterait sur un pan de relief et le test conclurait VERT sans
# jamais avoir touche la ceinture.
const CELLULES_DE_COULOIR := 5

var _v
var _racine: Node3D
var _tombeur: RigidBody3D
var _lanceur: RigidBody3D
var _cote_surface := 0.0
var _face_interieure := 0.0
var _depart_du_lanceur := 0.0
var _pas := 0

func _init() -> void:
	_v = Verif.new()

	var paquet := load(CHEMIN_SCENE) as PackedScene
	_v.v(paquet != null, "%s introuvable ou illisible" % CHEMIN_SCENE)
	if paquet == null:
		_conclure()
		return

	_racine = paquet.instantiate() as Node3D
	_v.v(_racine != null, "la racine de %s n'est pas un Node3D" % CHEMIN_SCENE)
	if _racine == null:
		_conclure()
		return
	root.add_child(_racine)

	var grille := _racine.get_node_or_null(NOM_TERRAIN) as GridMap
	_v.v(grille != null, "aucun GridMap nomme %s sous la racine" % NOM_TERRAIN)
	if grille == null:
		_conclure()
		return

	_formes_dans_la_bibliotheque(grille)
	var pose_sol := _poser_le_tombeur(grille)
	var pose_bord := _poser_le_lanceur(grille)
	if not pose_sol or not pose_bord:
		_conclure()
		return

	physics_frame.connect(_sur_pas_physique)

# La collision vit dans la bibliotheque ou nulle part : le verifier ICI nomme le
# fichier a rouvrir quand un temoin traverse, au lieu de laisser chercher.
func _formes_dans_la_bibliotheque(grille: GridMap) -> void:
	var bibliotheque := grille.mesh_library
	_v.v(bibliotheque != null, "le GridMap n'a aucune bibliotheque : aucune collision possible")
	if bibliotheque == null:
		return
	for item in bibliotheque.get_item_list():
		_v.v(not bibliotheque.get_item_shapes(item).is_empty(),
			"l'item %d de la bibliotheque n'a aucune forme de collision : il se traverse" % item)

# Le tombeur : lache au-dessus de la surface, au centre du terrain.
func _poser_le_tombeur(grille: GridMap) -> bool:
	var sommet: Variant = _sommet_de_colonne(grille, COLONNE)
	_v.v(sommet != null, "la colonne %s est vide sur les couches 0 a %d : rien sur quoi se poser" % [
		COLONNE, COUCHE_HAUTE_CHERCHEE])
	if sommet == null:
		return false

	# Le haut de la cellule, pas son centre : c'est la face sur laquelle le
	# temoin doit s'arreter.
	var centre := _cote_de_cellule(grille, sommet as Vector3i)
	_cote_surface = centre.y + grille.cell_size.y * 0.5

	_tombeur = _construire_temoin("Tombeur", Vector3(centre.x, _cote_surface + CHUTE, centre.z))
	root.add_child(_tombeur)
	print("tombeur lache en %s, surface attendue a y = %.2f (cellule %s)" % [
		_tombeur.position, _cote_surface, sommet])
	return true

# Le lanceur : projete a plat vers le bord +x, dans un couloir dont le vide est
# verifie avant le lancement.
func _poser_le_lanceur(grille: GridMap) -> bool:
	var bord := Generateur.DEMI_COTE
	var couche: Variant = _couche_de_tir(grille, bord)
	_v.v(couche != null,
		"aucune couche du bord x = %d ne porte un mur avec %d cellules vides devant : " % [
			bord, CELLULES_DE_COULOIR] +
		"ceinture absente, ou couloir bouche par le relief -- le test ne prouverait rien")
	if couche == null:
		return false

	var cellule_du_mur := Vector3i(bord, couche as int, COLONNE.y)
	_ceinture_invisible(grille, grille.get_cell_item(cellule_du_mur))

	var centre := _cote_de_cellule(grille, cellule_du_mur)
	_face_interieure = centre.x - grille.cell_size.x * 0.5
	_depart_du_lanceur = _face_interieure - RECUL_DU_LANCEMENT

	_lanceur = _construire_temoin("Lanceur", Vector3(_depart_du_lanceur, centre.y, centre.z))
	# Gravite coupee : le temoin doit finir sa course contre le mur, pas au sol.
	_lanceur.gravity_scale = 0.0
	_lanceur.linear_velocity = Vector3(VITESSE_VERS_LE_BORD, 0.0, 0.0)
	root.add_child(_lanceur)
	print("lanceur parti de x = %.2f a %.1f m/s, face du mur a x = %.2f (couche %d)" % [
		_depart_du_lanceur, VITESSE_VERS_LE_BORD, _face_interieure, couche])
	return true

# La ceinture ne se voit pas, et c'est la garantie a tenir : son item ne porte
# AUCUN maillage. Un maillage qui reapparait remet un mur brun autour de la
# carte, ce qu'aucun autre test ne rattrape.
func _ceinture_invisible(grille: GridMap, item: int) -> void:
	var bibliotheque := grille.mesh_library
	if bibliotheque == null:
		return
	_v.v(bibliotheque.get_item_mesh(item) == null,
		"l'item %d de la ceinture porte un maillage : la limite de carte est visible" % item)

# La cote du CENTRE d'une cellule, dans le repere de la scene. Les
# transformations LOCALES enchainees, jamais to_global : appele depuis _init, le
# noeud n'est pas encore DANS l'arbre et to_global rend une matrice vide en
# poussant une erreur.
func _cote_de_cellule(grille: GridMap, cellule: Vector3i) -> Vector3:
	return _racine.transform * (grille.transform * grille.map_to_local(cellule))

# Descend la colonne et rend la premiere cellule pleine rencontree, ou null si la
# colonne est vide. Vector3i n'a pas de valeur « aucune » : le retour est donc une
# Variant, jamais un Vector3i sentinelle qu'un appelant prendrait pour une
# cellule.
func _sommet_de_colonne(grille: GridMap, colonne: Vector2i) -> Variant:
	var y := COUCHE_HAUTE_CHERCHEE
	while y >= 0:
		var cellule := Vector3i(colonne.x, y, colonne.y)
		if grille.get_cell_item(cellule) != GridMap.INVALID_CELL_ITEM:
			return cellule
		y -= 1
	return null

# La couche ou tirer : la premiere, EN DESCENDANT, qui porte un mur ET dont les
# dernieres cellules avant le bord sont toutes vides. Les deux conditions
# ensemble, jamais l'une puis l'autre -- une couche vide de mur ou un couloir
# bouche rendraient tous deux un test qui ne prouve rien, et la hauteur de la
# ceinture n'a pas a etre connue ici.
#
# EN DESCENDANT parce que le relief occupe le bas : les couches hautes se
# liberent les premieres.
func _couche_de_tir(grille: GridMap, bord: int) -> Variant:
	var y := COUCHE_HAUTE_CHERCHEE
	while y >= 0:
		if grille.get_cell_item(Vector3i(bord, y, COLONNE.y)) != GridMap.INVALID_CELL_ITEM:
			var libre := true
			for x in range(bord - CELLULES_DE_COULOIR, bord):
				if grille.get_cell_item(Vector3i(x, y, COLONNE.y)) != GridMap.INVALID_CELL_ITEM:
					libre = false
					break
			if libre:
				return y
		y -= 1
	return null

func _construire_temoin(nom: String, position: Vector3) -> RigidBody3D:
	var corps := RigidBody3D.new()
	corps.name = nom
	corps.position = position
	var forme := CollisionShape3D.new()
	var bille := SphereShape3D.new()
	bille.radius = RAYON_TEMOIN
	forme.shape = bille
	corps.add_child(forme)
	return corps

func _sur_pas_physique() -> void:
	_pas += 1
	if _pas < PAS_ATTENDUS:
		return
	_juger_le_tombeur()
	_juger_le_lanceur()
	_conclure()

func _juger_le_tombeur() -> void:
	var cote_posee := _cote_surface + RAYON_TEMOIN
	var y := _tombeur.position.y
	print("apres %d pas : tombeur a y = %.3f (pose attendue a %.3f), vitesse %.3f" % [
		_pas, y, cote_posee, _tombeur.linear_velocity.y])

	_v.v(y > cote_posee - TOLERANCE,
		"le tombeur est passe a travers le sol : y = %.3f, attendu >= %.3f" % [
			y, cote_posee - TOLERANCE])
	_v.v(y < cote_posee + TOLERANCE,
		"le tombeur n'a pas touche la surface : y = %.3f, attendu <= %.3f" % [
			y, cote_posee + TOLERANCE])
	_v.v(absf(_tombeur.linear_velocity.y) < 0.5,
		"le tombeur tombe encore (vitesse %.3f) : rien ne l'arrete" % _tombeur.linear_velocity.y)

func _juger_le_lanceur() -> void:
	var butee := _face_interieure - RAYON_TEMOIN
	var x := _lanceur.position.x
	print("apres %d pas : lanceur a x = %.3f (butee attendue a %.3f), vitesse %.3f" % [
		_pas, x, butee, _lanceur.linear_velocity.x])

	# Un temoin qui n'a pas bouge ne prouve rien : sans ce controle, un lanceur
	# coince au depart passerait pour un mur qui tient.
	_v.v(x > _depart_du_lanceur + 1.0,
		"le lanceur n'a pas avance : x = %.3f, parti de %.3f" % [x, _depart_du_lanceur])
	_v.v(x < butee + TOLERANCE,
		"le lanceur a franchi la ceinture : x = %.3f, attendu <= %.3f" % [x, butee + TOLERANCE])
	_v.v(absf(_lanceur.linear_velocity.x) < 0.5,
		"le lanceur avance encore (vitesse %.3f) : rien ne l'arrete" % _lanceur.linear_velocity.x)

func _conclure() -> void:
	if _racine != null:
		_racine.queue_free()
	if _v.echecs() > 0:
		print("ECHEC: le terrain n'arrete pas un corps physique (%d)" % _v.echecs())
		quit(1)
		return
	print("OK: collision -- le sol arrete ce qui tombe, la ceinture invisible arrete ce qui sort")
	quit(0)
