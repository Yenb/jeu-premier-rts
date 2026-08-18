extends SceneTree

# Test manuel :
# godot --headless --script jeu/terrain/test_outil_sculpture.gd
#
# Verrouille les fonctions PURES de jeu/terrain/outil_sculpture.gd -- bornes de
# la boite, ecretage a l'emprise, ecriture par tranches -- et le chemin que la
# souris emprunte dans l'inspecteur : la case cochee, le GridMap retrouve parmi
# les freres, le decoupage sur plusieurs frames.
#
# Entree : aucune, tout est construit ici -- un GridMap et une bibliotheque
# fabriques en memoire, jamais la scene du jeu, qui porte le travail de
# sculpture et n'a pas a servir de cobaye.
# Sortie : une ligne « OK: » et le code 0, ou « ECHEC: » et le code 1.
#
# CE TEST ATTEND DES FRAMES. Les noeuds sont accroches sous `root`, qui
# n'existe qu'une fois la boucle lancee : d'ou le premier `await
# process_frame` avant toute chose. Sans arbre, l'outil ecrirait tout d'un
# coup et le decoupage ne serait jamais exerce.
#
# CE QUE CE TEST NE COUVRE PAS : l'affichage des controles dans l'inspecteur,
# et le fait que l'editeur reste reactif pendant l'ecriture. Ca demande un
# editeur, un ecran et une souris.

const Verif = preload("res://scripts/verif.gd")
const Outil = preload("res://jeu/terrain/outil_sculpture.gd")
const Generateur = preload("res://jeu/terrain/generer_carte.gd")

# L'emprise se LIT chez le generateur, ici comme dans l'outil -- ecrire 64 de
# plus en dur creerait un troisieme nombre a tenir accorde. Ce chemin de
# lecture n'est emprunte, hors de ce test, que par _appliquer(), qui ne tourne
# que dans l'editeur : s'il cassait, plus rien ne bornerait la boite et aucun
# test ne rougirait.
const DEMI_COTE := Generateur.DEMI_COTE
const COUCHES := 7

# Garde-fou d'attente : un test qui PEND est pire qu'un test rouge, il ne rend
# jamais la main et rien ne le signale.
const FRAMES_MAX := 5000

func _init() -> void:
	await process_frame

	var v := Verif.new()
	_les_bornes_ignorent_l_ordre_des_coins(v)
	_l_emprise_ecrete_x_et_z_jamais_la_hauteur(v)
	_les_tranches_couvrent_la_boite_sans_trou_ni_doublon(v)
	await _la_case_declenche_puis_se_decoche(v)
	await _une_boite_pleine_taille_passe_sur_plusieurs_frames(v)

	if v.echecs() > 0:
		print("ECHEC: outil_sculpture -- %d verifications rouges" % v.echecs())
		quit(1)
		return
	print("OK: outil_sculpture -- bornes independantes de l'ordre des coins, " +
		"emprise ecretee en x et z et jamais en hauteur, tranches sans trou ni " +
		"doublon, une boite deja dans l'etat demande compte zero modification, " +
		"la case declenche puis se decoche, un terrain absent alarme " +
		"sans rien poser, une boite de %d x %d x %d passe en plusieurs frames" % [
			DEMI_COTE * 2, DEMI_COTE * 2, COUCHES])
	quit(0)

func _les_bornes_ignorent_l_ordre_des_coins(v) -> void:
	var a := Vector3i(-2, 0, 3)
	var b := Vector3i(1, 2, 5)
	var endroit := Outil.bornes(a, b, DEMI_COTE)
	var envers := Outil.bornes(b, a, DEMI_COTE)
	v.v(endroit == envers, "coins inverses : la boite change alors qu'elle designe le meme volume")
	v.v(Outil.volume(endroit[0], endroit[1]) == 4 * 3 * 3,
		"la boite porte %d cellules au lieu de %d" % [
			Outil.volume(endroit[0], endroit[1]), 4 * 3 * 3])
	v.v(Outil.volume_demande(a, b) == 4 * 3 * 3,
		"le volume demande vaut %d au lieu de %d sans aucun ecretage" % [
			Outil.volume_demande(a, b), 4 * 3 * 3])

	# Deux coins confondus designent UNE cellule, jamais zero : la boite est
	# fermee aux deux bouts.
	var seule := Outil.bornes(a, a, DEMI_COTE)
	v.v(Outil.volume(seule[0], seule[1]) == 1 and seule[0] == a,
		"deux coins confondus rendent %d cellules au lieu d'une seule" % Outil.volume(
			seule[0], seule[1]))

func _l_emprise_ecrete_x_et_z_jamais_la_hauteur(v) -> void:
	var deborde := Outil.bornes(
		Vector3i(-DEMI_COTE - 10, -5, -DEMI_COTE - 10),
		Vector3i(DEMI_COTE + 10, 40, DEMI_COTE + 10),
		DEMI_COTE)
	v.v(deborde[0].x == -DEMI_COTE and deborde[1].x == DEMI_COTE - 1,
		"l'emprise en x n'est pas ecretee (%d a %d)" % [deborde[0].x, deborde[1].x])
	v.v(deborde[0].z == -DEMI_COTE and deborde[1].z == DEMI_COTE - 1,
		"l'emprise en z n'est pas ecretee (%d a %d)" % [deborde[0].z, deborde[1].z])
	v.v(deborde[0].y == -5 and deborde[1].y == 40,
		"la hauteur a ete ecretee (%d a %d au lieu de -5 a 40)" % [deborde[0].y, deborde[1].y])

	# Une boite entierement hors emprise vaut zero -- et ne doit pas alarmer :
	# ecrire zero cellule est un resultat legitime, pas une panne.
	var dehors := Outil.bornes(
		Vector3i(DEMI_COTE + 1, 0, 0), Vector3i(DEMI_COTE + 5, 0, 0), DEMI_COTE)
	v.v(Outil.volume(dehors[0], dehors[1]) == 0,
		"une boite hors emprise vaut %d cellules" % Outil.volume(dehors[0], dehors[1]))

func _les_tranches_couvrent_la_boite_sans_trou_ni_doublon(v) -> void:
	var grille := GridMap.new()
	grille.mesh_library = _bibliotheque_a_un_bloc()

	var boite := Outil.bornes(Vector3i(-3, 0, -3), Vector3i(2, 4, 2), DEMI_COTE)
	var total := Outil.volume(boite[0], boite[1])

	# Des tranches de sept, qui ne tombent pas juste sur le total : le dernier
	# morceau est toujours plus court, c'est la qu'un decoupage se casse.
	var index := 0
	var changees := 0
	var tours := 0
	while index < total:
		var tranche := Outil.ecrire_tranche(grille, boite[0], boite[1], 0, index, 7)
		index = tranche["index"]
		changees += tranche["changees"]
		tours += 1
		v.v(tours <= total, "l'ecriture par tranches n'avance pas : boucle sans fin")
		if tours > total:
			break
	v.v(index == total, "les tranches s'arretent a %d au lieu de %d" % [index, total])
	v.v(changees == total, "%d cellules comptees comme modifiees au lieu de %d sur une grille vide" % [
		changees, total])
	v.v(grille.get_used_cells().size() == total,
		"les tranches ont pose %d cellules au lieu de %d" % [
			grille.get_used_cells().size(), total])

	var hors_boite := 0
	for cellule in grille.get_used_cells():
		if cellule.x < boite[0].x or cellule.x > boite[1].x \
				or cellule.y < boite[0].y or cellule.y > boite[1].y \
				or cellule.z < boite[0].z or cellule.z > boite[1].z:
			hors_boite += 1
	v.v(hors_boite == 0, "%d cellules posees hors de la boite demandee" % hors_boite)

	# REMPLIR une boite deja pleine parcourt tout et ne change RIEN. C'est le
	# cas qui fait chercher une panne la ou il n'y en a pas : le compte des
	# cellules parcourues reste le meme, celui des modifiees tombe a zero.
	var refaite := Outil.ecrire_tranche(grille, boite[0], boite[1], 0, 0, total)
	v.v(refaite["index"] == total,
		"la seconde passe s'arrete a %d au lieu de %d" % [refaite["index"], total])
	v.v(refaite["changees"] == 0,
		"%d cellules comptees comme modifiees alors que la boite etait deja pleine" % refaite["changees"])

	# Creuser la meme boite doit tout reprendre : c'est le seul recours contre
	# une pose ratee, l'editeur n'annule pas ce que l'outil ecrit.
	var creusee := Outil.ecrire_tranche(
		grille, boite[0], boite[1], GridMap.INVALID_CELL_ITEM, 0, total)
	v.v(grille.get_used_cells().is_empty(),
		"creuser laisse %d cellules derriere lui" % grille.get_used_cells().size())
	v.v(creusee["changees"] == total,
		"creuser compte %d cellules modifiees au lieu de %d" % [creusee["changees"], total])

	grille.free()

# Le chemin complet, celui que la souris emprunte dans l'inspecteur : la case
# cochee, le GridMap retrouve parmi les freres, le bloc pris dans la
# bibliotheque.
func _la_case_declenche_puis_se_decoche(v) -> void:
	var parent := Node3D.new()
	root.add_child(parent)
	var grille := GridMap.new()
	grille.mesh_library = _bibliotheque_a_un_bloc()
	parent.add_child(grille)
	var outil := Outil.new()
	parent.add_child(outil)

	outil.coin_debut = Vector3i(0, 10, 0)
	outil.coin_fin = Vector3i(1, 11, 1)
	outil.mode = Outil.Mode.REMPLIR
	outil.appliquer = true
	v.v(not outil.appliquer, "la case reste cochee apres l'action : c'est un etat, plus un declencheur")
	await _attendre_la_fin(v, outil)
	v.v(grille.get_used_cells().size() == 8,
		"la case cochee a pose %d cellules au lieu de 8" % grille.get_used_cells().size())

	outil.mode = Outil.Mode.CREUSER
	outil.appliquer = true
	await _attendre_la_fin(v, outil)
	v.v(grille.get_used_cells().is_empty(),
		"creuser par la case laisse %d cellules" % grille.get_used_cells().size())

	# Sans GridMap frere, l'outil alarme et ne pose rien -- il ne devine aucun
	# terrain. L'erreur qui suit est PROVOQUEE par le test : une sortie muette
	# ici serait le vrai echec.
	print("(l'erreur « aucun GridMap parmi les freres » ci-dessous est attendue)")
	var orphelin := Outil.new()
	Node3D.new().add_child(orphelin)
	orphelin.appliquer = true
	v.v(not orphelin.appliquer, "la case reste cochee alors qu'aucun terrain n'a ete trouve")
	v.v(not orphelin.sculpture_en_cours(), "une sculpture reste ouverte sans terrain")

	orphelin.get_parent().free()
	parent.free()

# La taille du terrain reel, celle qui figeait l'editeur quand elle passait
# d'un seul tenant. Ce qui est verifie ici n'est pas la vitesse -- un test ne
# mesure pas la reactivite d'un editeur -- mais que l'ecriture RENDE LA MAIN en
# cours de route et pose quand meme toutes ses cellules.
func _une_boite_pleine_taille_passe_sur_plusieurs_frames(v) -> void:
	var parent := Node3D.new()
	root.add_child(parent)
	var grille := GridMap.new()
	grille.mesh_library = _bibliotheque_a_un_bloc()
	parent.add_child(grille)
	var outil := Outil.new()
	parent.add_child(outil)

	var attendu := DEMI_COTE * DEMI_COTE * 4 * COUCHES
	outil.coin_debut = Vector3i(-DEMI_COTE, 0, -DEMI_COTE)
	outil.coin_fin = Vector3i(DEMI_COTE - 1, COUCHES - 1, DEMI_COTE - 1)
	outil.mode = Outil.Mode.REMPLIR
	outil.appliquer = true

	v.v(outil.sculpture_en_cours(),
		"une boite de %d cellules s'est ecrite d'un seul tenant : rien n'a ete decoupe" % attendu)
	var frames := await _attendre_la_fin(v, outil)
	v.v(frames > 1, "la sculpture a tenu en %d frame : le decoupage ne mord pas" % frames)
	v.v(grille.get_used_cells().size() == attendu,
		"la boite pleine taille a pose %d cellules au lieu de %d" % [
			grille.get_used_cells().size(), attendu])

	parent.free()

# Rend le nombre de frames attendues. Ne pend jamais : au-dela de FRAMES_MAX,
# la verification rougit et le test continue.
func _attendre_la_fin(v, outil) -> int:
	var frames := 0
	while outil.sculpture_en_cours() and frames < FRAMES_MAX:
		await process_frame
		frames += 1
	v.v(not outil.sculpture_en_cours(),
		"la sculpture ne se termine pas apres %d frames" % FRAMES_MAX)
	return frames

func _bibliotheque_a_un_bloc() -> MeshLibrary:
	var bibliotheque := MeshLibrary.new()
	bibliotheque.create_item(0)
	bibliotheque.set_item_mesh(0, BoxMesh.new())
	return bibliotheque
