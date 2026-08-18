extends SceneTree

# Test manuel :
# godot --headless --script jeu/terrain/test_carte.gd
#
# Verrouille ce que la scene de terrain DOIT porter pour rester sculptable :
# une bibliotheque de blocs attachee, un pas de grille egal a l'arete du cube,
# un bloc plein SANS TROU sur toutes ses couches, et rien au-dessus de sa
# surface. Aucun de ces faits n'est visible a l'oeil sans ouvrir l'editeur --
# vu du dessus, un bloc creux et un bloc plein sont la meme image ; tous se
# perdent en silence si la scene est reecrite de travers.
#
# Entree : res://jeu/terrain/carte.tscn, lu sur le disque -- jamais l'objet
# qu'un generateur vient de construire en memoire, sinon le test ne prouve
# rien sur le fichier.
# Sortie : une ligne « OK: » et le code 0 si tout tient, « ECHEC: » et le code
# 1 sinon, chaque manquement pousse en erreur par verif.gd.
#
# CE QUE CE TEST NE PEUT PAS PROUVER : que la palette de blocs s'affiche et
# qu'un clic pose un cube. Ca demande un editeur, un ecran et une souris --
# ca se verifie a la main, pas ici.

const Verif = preload("res://scripts/verif.gd")

const CHEMIN_SCENE := "res://jeu/terrain/carte.tscn"
const COTE_ATTENDU := 2.0
const DEMI_COTE_ATTENDU := 64
const COUCHE_BASE_ATTENDUE := 0
const COUCHES_PLEINES_ATTENDUES := 7

func _init() -> void:
	var v := Verif.new()
	var racine := _instancier(v)
	if racine != null:
		_bloc_plein_sans_trou(v, racine)
		_bibliotheque_a_un_bloc_de_deux_metres(v, racine)
		_regard_et_lumiere_en_place(v, racine)
		racine.free()

	if v.echecs() > 0:
		print("ECHEC: la scene de terrain ne tient pas ses garanties (%d)" % v.echecs())
		quit(1)
		return
	print("OK: carte -- bloc plein de %d x %d x %d cellules de %.1f m, couches %d a %d " % [
			DEMI_COTE_ATTENDU * 2, DEMI_COTE_ATTENDU * 2, COUCHES_PLEINES_ATTENDUES,
			COTE_ATTENDU, COUCHE_BASE_ATTENDUE,
			COUCHE_BASE_ATTENDUE + COUCHES_PLEINES_ATTENDUES - 1] +
		"pleines sans trou, rien au-dessus, bibliotheque attachee, camera et lumiere posees")
	quit(0)

func _instancier(v) -> Node3D:
	var paquet := load(CHEMIN_SCENE) as PackedScene
	v.v(paquet != null, "%s introuvable ou illisible" % CHEMIN_SCENE)
	if paquet == null:
		return null
	var racine := paquet.instantiate() as Node3D
	v.v(racine != null, "la racine de %s n'est pas un Node3D" % CHEMIN_SCENE)
	return racine

func _bloc_plein_sans_trou(v, racine: Node3D) -> void:
	var grille := racine.get_node_or_null("Terrain") as GridMap
	v.v(grille != null, "aucun GridMap nomme Terrain sous la racine")
	if grille == null:
		return

	var couche_haute := COUCHE_BASE_ATTENDUE + COUCHES_PLEINES_ATTENDUES - 1
	var par_couche := DEMI_COTE_ATTENDU * DEMI_COTE_ATTENDU * 4
	var cellules := grille.get_used_cells()
	v.v(cellules.size() == par_couche * COUCHES_PLEINES_ATTENDUES,
		"le bloc porte %d cellules au lieu de %d" % [
			cellules.size(), par_couche * COUCHES_PLEINES_ATTENDUES])

	# Une seule passe : hors couche, hors emprise et bloc inconnu se comptent
	# ensemble, sinon un bloc decale rendrait trois fois la meme alarme.
	var comptes := {}
	var hors_couches := 0
	var hors_emprise := 0
	var bloc_inconnu := 0
	for cellule in cellules:
		if cellule.y < COUCHE_BASE_ATTENDUE or cellule.y > couche_haute:
			hors_couches += 1
		else:
			comptes[cellule.y] = comptes.get(cellule.y, 0) + 1
		if cellule.x < -DEMI_COTE_ATTENDU or cellule.x >= DEMI_COTE_ATTENDU \
				or cellule.z < -DEMI_COTE_ATTENDU or cellule.z >= DEMI_COTE_ATTENDU:
			hors_emprise += 1
		if grille.get_cell_item(cellule) != 0:
			bloc_inconnu += 1
	v.v(hors_couches == 0, "%d cellules hors des couches %d a %d" % [
		hors_couches, COUCHE_BASE_ATTENDUE, couche_haute])
	v.v(hors_emprise == 0, "%d cellules hors de l'emprise attendue" % hors_emprise)
	v.v(bloc_inconnu == 0, "%d cellules portent un bloc autre que l'item 0" % bloc_inconnu)

	# Le total seul ne prouve rien : il tient encore si une couche est trouee
	# et qu'une autre deborde d'autant.
	for y in range(COUCHE_BASE_ATTENDUE, couche_haute + 1):
		v.v(comptes.get(y, 0) == par_couche, "la couche %d porte %d cellules au lieu de %d" % [
			y, comptes.get(y, 0), par_couche])

	v.v(grille.cell_size == Vector3(COTE_ATTENDU, COTE_ATTENDU, COTE_ATTENDU),
		"le pas de grille vaut %s au lieu de %s" % [
			grille.cell_size, Vector3(COTE_ATTENDU, COTE_ATTENDU, COTE_ATTENDU)])

func _bibliotheque_a_un_bloc_de_deux_metres(v, racine: Node3D) -> void:
	var grille := racine.get_node_or_null("Terrain") as GridMap
	if grille == null:
		return
	var bibliotheque := grille.mesh_library
	v.v(bibliotheque != null, "le GridMap n'a aucune bibliotheque : palette vide, rien a poser")
	if bibliotheque == null:
		return

	var items := bibliotheque.get_item_list()
	v.v(items.size() == 1, "la bibliotheque porte %d items au lieu d'un seul" % items.size())
	if items.size() == 0:
		return

	var maillage := bibliotheque.get_item_mesh(items[0]) as BoxMesh
	v.v(maillage != null, "l'item de la bibliotheque ne porte pas de BoxMesh")
	if maillage == null:
		return
	v.v(maillage.size == Vector3(COTE_ATTENDU, COTE_ATTENDU, COTE_ATTENDU),
		"le cube mesure %s au lieu de %s -- il ne remplit plus sa cellule" % [
			maillage.size, Vector3(COTE_ATTENDU, COTE_ATTENDU, COTE_ATTENDU)])
	v.v(maillage.material != null, "le cube n'a aucun materiau : invisible au rendu")

func _regard_et_lumiere_en_place(v, racine: Node3D) -> void:
	var camera := racine.get_node_or_null("Camera") as Camera3D
	v.v(camera != null, "aucune Camera3D nommee Camera sous la racine")
	if camera != null:
		v.v(camera.current, "la camera n'est pas active : le lancement rendrait un ecran vide")
		v.v(camera.position.y > 0.0, "la camera est sous le sol (y = %.1f)" % camera.position.y)
		# La troisieme colonne de la base est l'axe -regard : regarder vers le
		# bas veut dire que sa composante y est positive. La transformation
		# LOCALE, jamais la globale : hors de l'arbre de scene, global_transform
		# rend une matrice vide et l'alarme porterait a faux.
		v.v(camera.transform.basis.z.y > 0.9, "la camera ne regarde pas vers le bas")

	var soleil := racine.get_node_or_null("Soleil") as DirectionalLight3D
	v.v(soleil != null, "aucune DirectionalLight3D nommee Soleil sous la racine")
