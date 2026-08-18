extends SceneTree

# Test manuel :
# godot --headless --script jeu/terrain/test_outil_remplissage.gd
#
# Verrouille la reconnaissance des zones encloses de
# jeu/terrain/outil_remplissage.gd, et le chemin que la souris emprunte dans
# l'inspecteur : la case cochee, le GridMap retrouve parmi les freres,
# l'ecriture decoupee par frame.
#
# LES CAS SONT DESSINES, pas construits case par case : « # » est un cube,
# « . » du vide. Une figure de remplissage se lit d'un coup d'oeil et se
# corrige de meme -- une liste de coordonnees, non.
#
# Entree : aucune, tout est construit ici -- des grilles fabriquees en memoire,
# jamais la scene du jeu, qui porte le travail de sculpture et n'a pas a servir
# de cobaye.
# Sortie : une ligne « OK: » et le code 0, ou « ECHEC: » et le code 1.
#
# CE TEST ATTEND DES FRAMES : les noeuds sont accroches sous `root`, qui
# n'existe qu'une fois la boucle lancee, d'ou le premier `await process_frame`.
#
# CE QU'IL NE COUVRE PAS : l'affichage des controles dans l'inspecteur.

const Verif = preload("res://scripts/verif.gd")
const Outil = preload("res://jeu/terrain/outil_remplissage.gd")

# Emprise reduite : les figures se dessinent a la main, et la regle testee ne
# depend pas de la taille de la carte. La seule qui en depende -- le bord
# n'est jamais un mur -- se teste justement en collant une figure au bord.
const DEMI := 8
const COUCHE := 7
const FRAMES_MAX := 5000

func _init() -> void:
	await process_frame

	var v := Verif.new()
	_un_contour_ferme_donne_une_zone(v)
	_un_contour_ouvert_ne_donne_rien(v)
	_deux_contours_font_deux_zones(v)
	_un_contour_appuye_sur_le_bord_ne_ferme_rien(v)
	_une_diagonale_ferme_son_contour(v)
	_creuser_cherche_les_ilots_pleins(v)
	_l_occupation_lit_la_bonne_couche(v)
	await _la_case_declenche_et_remplit(v)

	if v.echecs() > 0:
		print("ECHEC: outil_remplissage -- %d verifications rouges" % v.echecs())
		quit(1)
		return
	print("OK: outil_remplissage -- un contour ferme donne une zone, un contour " +
		"ouvert ou appuye sur le bord n'en donne aucune, deux contours font deux " +
		"zones, une diagonale est etanche, creuser trouve les ilots pleins, " +
		"l'occupation ne lit que sa couche, la case declenche et remplit")
	quit(0)

func _un_contour_ferme_donne_une_zone(v) -> void:
	var trouve := _zones([
		"#####",
		"#...#",
		"#...#",
		"#...#",
		"#####",
	], true)
	v.v(trouve["zones"] == 1, "un carre ferme donne %d zone(s) au lieu d'une" % trouve["zones"])
	v.v(trouve["cellules"].size() == 9,
		"l'interieur du carre porte %d cellules au lieu de 9" % trouve["cellules"].size())

	var hors_couche := 0
	for cellule in trouve["cellules"]:
		if cellule.y != COUCHE:
			hors_couche += 1
	v.v(hors_couche == 0, "%d cellules rendues hors de la couche lue" % hors_couche)

func _un_contour_ouvert_ne_donne_rien(v) -> void:
	# Le meme carre, une cellule de contour en moins : la poche fuit par la.
	var trouve := _zones([
		"#####",
		"#...#",
		"#....",
		"#...#",
		"#####",
	], true)
	v.v(trouve["zones"] == 0,
		"un contour perce donne %d zone(s) : la fuite n'est pas vue" % trouve["zones"])
	v.v(trouve["cellules"].is_empty(),
		"%d cellules rendues pour un contour ouvert" % trouve["cellules"].size())

func _deux_contours_font_deux_zones(v) -> void:
	var trouve := _zones([
		"###.###",
		"#.#.#.#",
		"###.###",
	], true)
	v.v(trouve["zones"] == 2,
		"deux carres separes donnent %d zone(s) au lieu de deux" % trouve["zones"])
	v.v(trouve["cellules"].size() == 2,
		"les deux interieurs portent %d cellules au lieu de 2" % trouve["cellules"].size())

func _un_contour_appuye_sur_le_bord_ne_ferme_rien(v) -> void:
	# Un U ouvert vers le haut, colle au bord de l'emprise : le bord fermerait
	# la poche s'il comptait comme un mur. Il ne compte pas.
	var trouve := _zones_placees([
		"#.#",
		"#.#",
		"###",
	], true, Vector2i(0, 0))
	v.v(trouve["zones"] == 0,
		"une poche ouverte sur le bord donne %d zone(s) : le bord fait mur" % trouve["zones"])

func _une_diagonale_ferme_son_contour(v) -> void:
	# Losange trace en biais : aucune de ses cellules ne touche la suivante par
	# une face, seulement par un coin. Un voisinage a huit ferait fuir
	# l'exterieur au travers ; a quatre, la figure tient.
	var trouve := _zones([
		"..#..",
		".#.#.",
		"#...#",
		".#.#.",
		"..#..",
	], true)
	v.v(trouve["zones"] == 1,
		"un losange en diagonale donne %d zone(s) : le contour fuit" % trouve["zones"])
	v.v(trouve["cellules"].size() == 5,
		"l'interieur du losange porte %d cellules au lieu de 5" % trouve["cellules"].size())

func _creuser_cherche_les_ilots_pleins(v) -> void:
	# Meme dessin, nature inverse : ce sont les CUBES qui n'atteignent pas le
	# bord qu'on cherche, contour compris.
	var trouve := _zones([
		"###",
		"###",
		"###",
	], false)
	v.v(trouve["zones"] == 1, "un ilot plein donne %d zone(s) au lieu d'une" % trouve["zones"])
	v.v(trouve["cellules"].size() == 9,
		"l'ilot porte %d cellules au lieu de 9 -- le contour doit partir aussi" % trouve["cellules"].size())

	# Colle au bord, la meme masse n'est plus un ilot.
	var au_bord := _zones_placees(["###", "###"], false, Vector2i(0, 0))
	v.v(au_bord["zones"] == 0,
		"une masse qui touche le bord compte comme %d ilot(s)" % au_bord["zones"])

func _l_occupation_lit_la_bonne_couche(v) -> void:
	var grille := GridMap.new()
	grille.mesh_library = _bibliotheque_a_un_bloc()
	grille.set_cell_item(Vector3i(0, COUCHE, 0), 0)
	grille.set_cell_item(Vector3i(1, COUCHE + 1, 1), 0)

	var carte := Outil.occupation(grille, COUCHE, DEMI)
	var pleines := 0
	for case in carte:
		pleines += case
	v.v(carte.size() == DEMI * DEMI * 4,
		"l'occupation porte %d cases au lieu de %d" % [carte.size(), DEMI * DEMI * 4])
	v.v(pleines == 1, "%d cellules lues au lieu d'une : une autre couche a deteint" % pleines)
	v.v(carte[(0 + DEMI) * DEMI * 2 + (0 + DEMI)] == 1, "la cellule posee n'est pas lue pleine")

	grille.free()

# Le chemin complet, celui que la souris emprunte dans l'inspecteur.
func _la_case_declenche_et_remplit(v) -> void:
	var parent := Node3D.new()
	root.add_child(parent)
	var grille := GridMap.new()
	grille.mesh_library = _bibliotheque_a_un_bloc()
	parent.add_child(grille)
	var outil := Outil.new()
	parent.add_child(outil)

	# Un anneau de 5 x 5 pose autour de l'origine : neuf cellules a combler.
	for i in range(-2, 3):
		for j in range(-2, 3):
			if absi(i) == 2 or absi(j) == 2:
				grille.set_cell_item(Vector3i(i, COUCHE, j), 0)
	var contour := grille.get_used_cells().size()

	outil.couche = COUCHE
	outil.mode = Outil.Mode.REMPLIR
	outil.appliquer = true
	v.v(not outil.appliquer, "la case reste cochee apres l'action")
	await _attendre_la_fin(v, outil)
	v.v(grille.get_used_cells().size() == contour + 9,
		"le remplissage a pose %d cellules au lieu de 9" % [
			grille.get_used_cells().size() - contour])

	# Repasser sur un interieur deja comble ne trouve plus aucune poche : la
	# zone n'existe plus, elle est devenue de la matiere.
	outil.appliquer = true
	await _attendre_la_fin(v, outil)
	v.v(grille.get_used_cells().size() == contour + 9,
		"une seconde passe a modifie %d cellules de plus" % [
			grille.get_used_cells().size() - contour - 9])

	# Creuser reprend tout : le carre plein est desormais un ilot, contour
	# compris, et rien ne le relie au bord.
	outil.mode = Outil.Mode.CREUSER
	outil.appliquer = true
	await _attendre_la_fin(v, outil)
	v.v(grille.get_used_cells().is_empty(),
		"creuser laisse %d cellules derriere lui" % grille.get_used_cells().size())

	# Sans GridMap frere, l'outil alarme et ne pose rien. L'erreur qui suit est
	# PROVOQUEE par le test : une sortie muette ici serait le vrai echec.
	print("(l'erreur « aucun GridMap parmi les freres » ci-dessous est attendue)")
	var orphelin := Outil.new()
	Node3D.new().add_child(orphelin)
	orphelin.appliquer = true
	v.v(not orphelin.remplissage_en_cours(), "un remplissage reste ouvert sans terrain")

	orphelin.get_parent().free()
	parent.free()

func _attendre_la_fin(v, outil) -> int:
	var frames := 0
	while outil.remplissage_en_cours() and frames < FRAMES_MAX:
		await process_frame
		frames += 1
	v.v(not outil.remplissage_en_cours(),
		"le remplissage ne se termine pas apres %d frames" % FRAMES_MAX)
	return frames

func _zones(motif: Array, cherche_vide: bool) -> Dictionary:
	return _zones_placees(motif, cherche_vide, Vector2i(DEMI - motif.size() / 2, DEMI - 2))

# Place le motif dans l'emprise a partir du coin donne (en indices de carte, pas
# en coordonnees de grille) et rend les zones encloses qu'il produit.
func _zones_placees(motif: Array, cherche_vide: bool, coin: Vector2i) -> Dictionary:
	var cote := DEMI * 2
	var carte := PackedByteArray()
	carte.resize(cote * cote)
	for ligne in range(motif.size()):
		var texte: String = motif[ligne]
		for colonne in range(texte.length()):
			if texte[colonne] == "#":
				carte[(coin.x + ligne) * cote + (coin.y + colonne)] = 1
	return Outil.zones_encloses(carte, DEMI, COUCHE, cherche_vide)

func _bibliotheque_a_un_bloc() -> MeshLibrary:
	var bibliotheque := MeshLibrary.new()
	bibliotheque.create_item(0)
	bibliotheque.set_item_mesh(0, BoxMesh.new())
	return bibliotheque
