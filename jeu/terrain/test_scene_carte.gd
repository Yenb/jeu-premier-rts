extends SceneTree

# Test manuel :
# godot --headless --script jeu/terrain/test_scene_carte.gd
#
# Verrouille le CABLAGE de res://jeu/terrain/carte_100km2.tscn -- pas la
# mecanique, qui a ses propres tests, mais les branchements qu'un fichier de
# scene peut perdre en silence :
# - le terrain porte bien la carte de 100 km² et une bibliotheque de blocs ;
# - le personnage est dans le GROUPE que le terrain interroge. Ce lien-la ne se
#   voit nulle part ailleurs : sans lui le terrain se pose autour de l'origine
#   et n'en bouge plus, ce qui ressemble a un terrain qui marche ;
# - le soleil garde son inclinaison. Une propriete qu'un fichier de scene
#   n'accepterait pas retomberait au defaut sans erreur ;
# - APRES UNE IMAGE, le terrain S'EST PEUPLE, et il porte exactement le disque
#   attendu autour du personnage. Une scene qui se charge sans rien poser est le
#   faux vert de ce chantier ;
# - LE SOL RESTE SOLIDE MEME SI LA SCENE PORTE UNE BIBLIOTHEQUE D'EDITION. La
#   meme scene sert a sculpter, et l'outil de fenetre y pose alors une
#   bibliotheque sans formes de collision -- six cent mille corps physiques
#   coutent vingt-huit secondes. Enregistree ainsi, la scene rend un sol que le
#   personnage TRAVERSE, sans qu'aucune erreur ne sorte ;
# - le personnage est pose SUR le sol au demarrage, ni enfonce dedans ni
#   suspendu au-dessus, et le terrain pose le RATTRAPE quand on le laisse
#   tomber de plus haut : c'est ce qui prouve que les cellules posees a
#   l'execution portent bien leur collision.
#
# Entree : la scene sur le disque, instanciee et poussee dans l'arbre. Sortie :
# une ligne « OK: » et le code 0 si tout tient, « ECHEC: » et le code 1 sinon.
#
# LA SCENE EST RELUE SUR LE DISQUE, jamais construite ici : ce qui est verrouille
# est le FICHIER, y compris ce qu'il perd au chargement.
#
# Regles tenues : positions en Vector3, jamais Vector2. Aucun hasard. Les prints
# sont des traces de mise au point, pas du texte joueur. Rien de scripts/, data/
# ni documents/ n'est ecrit.

const Verif = preload("res://scripts/verif.gd")
const TerrainVisible = preload("res://jeu/terrain/terrain_visible.gd")

const CHEMIN_SCENE := "res://jeu/terrain/carte_100km2.tscn"
const KM2_ATTENDUS := 100.0
const TOLERANCE_KM2 := 0.001

# L'inclinaison du soleil telle que la scene l'ecrit.
const SOLEIL_DEGRES := Vector3(-50.0, -35.0, 0.0)
const TOLERANCE_DEGRES := 0.5

# Combien d'images de physique laisser passer pour que le personnage se pose,
# de combien sa hauteur a le droit de s'ecarter du sol, et de combien on le
# souleve avant de le lacher.
const IMAGES_DE_CHUTE := 120
const TOLERANCE_POSE := 0.1
const HAUTEUR_DE_LACHER := 3.0

# De combien la scene a le droit de lacher le personnage au-dessus du sol. Ce
# qu'on refuse est une partie qui commence par une chute, pas quelques metres
# laisses par un reglage a la souris.
const CHUTE_TOLEREE := 20.0

# D'ou part le rayon qui MESURE le sol, au-dessus de l'origine.
const HAUTEUR_DE_TIR := 40.0

var _v

func _init() -> void:
	_v = Verif.new()
	_verifier.call_deferred()

func _verifier() -> void:
	var paquet := load(CHEMIN_SCENE) as PackedScene
	if paquet == null:
		_v.v(false, "%s introuvable ou illisible" % CHEMIN_SCENE)
		_conclure(null)
		return
	var racine := paquet.instantiate() as Node3D
	if racine == null:
		_v.v(false, "la racine de %s n'est pas un Node3D" % CHEMIN_SCENE)
		_conclure(null)
		return
	get_root().add_child(racine)

	var terrain := racine.get_node_or_null("Terrain") as GridMap
	if terrain == null:
		_v.v(false, "aucun GridMap nomme Terrain sous la racine")
		_conclure(racine)
		return
	_v.v(terrain.mesh_library != null, "le terrain n'a aucune bibliotheque de blocs")
	if terrain.carte == null:
		_v.v(false, "le terrain ne porte aucune carte")
		_conclure(racine)
		return
	_v.v(absf(terrain.carte.superficie_km2() - KM2_ATTENDUS) < TOLERANCE_KM2,
		"le terrain porte une carte de %.2f km², %.0f attendus" % [
			terrain.carte.superficie_km2(), KM2_ATTENDUS])

	var personnage := racine.get_node_or_null("Personnage") as Node3D
	if personnage == null:
		_v.v(false, "aucun Personnage sous la racine")
		_conclure(racine)
		return
	# LE LIEN QUI NE SE VOIT NULLE PART AILLEURS.
	_v.v(personnage.is_in_group(terrain.groupe_observateur),
		"le personnage n'est pas dans le groupe « %s » : le terrain ne le suivra pas" % terrain.groupe_observateur)

	var soleil := racine.get_node_or_null("Soleil") as DirectionalLight3D
	if soleil == null:
		_v.v(false, "aucun Soleil sous la racine")
	else:
		_v.v(soleil.rotation_degrees.distance_to(SOLEIL_DEGRES) < TOLERANCE_DEGRES,
			"le soleil est incline a %v, %v attendu : la propriete n'a pas ete relue" % [
				soleil.rotation_degrees, SOLEIL_DEGRES])
		_v.v(soleil.shadow_enabled, "le soleil ne projette pas d'ombre")

	_v.v(racine.get_node_or_null("Ambiance") != null,
		"aucune Ambiance : ce que le soleil ne touche pas serait noir")

	await process_frame

	var posees := terrain.get_used_cells().size()
	_v.v(posees > 0, "le terrain n'a pose aucune cellule apres une image")

	# LA CARTE DIT LA TAILLE DE SA CELLULE, la scene ne la redit pas. Une arete
	# reglee dans la scene et une autre declaree par la carte, c'est un terrain
	# dessine a la mauvaise echelle sans qu'aucune erreur ne sorte.
	var arete: float = terrain.carte.cote
	_v.v(terrain.cell_size.is_equal_approx(Vector3(arete, arete, arete)),
		"le terrain a des cellules de %v alors que la carte declare %.3f" % [
			terrain.cell_size, arete])
	# LE JEU NE PAIE PAS LES OUTILS D'EDITION. La meme scene sert a sculpter :
	# maquette et repere doivent s'effacer au lancement, sinon le joueur trouve
	# soixante-deux mille cellules colorees au-dessus de sa tete.
	var maquette := racine.get_node_or_null("Apercu/Maquette") as Node3D
	if maquette != null:
		_v.v(maquette.grille().get_used_cells().is_empty(),
			"la vue d'ensemble pose %d cellules en jeu" % maquette.grille().get_used_cells().size())
	var repere := racine.get_node_or_null("Apercu/Repere") as MeshInstance3D
	if repere != null:
		_v.v(repere.mesh == null, "le repere de fenetre se voit en jeu")

	await _arete_imposee(terrain)
	await _collision_reprise(terrain)
	await _scene_reprise(terrain)

	var carte: Resource = terrain.carte

	# LE CENTRE SE LIT SOUS LE PERSONNAGE, jamais suppose a l'origine : le
	# disque suit l'observateur, et sa position se regle a la souris. Un centre
	# ecrit en dur fait rougir le test des que le personnage est deplace.
	var sous_le_joueur := terrain.local_to_map(
		terrain.to_local(personnage.global_position))
	var centre := Vector2i(sous_le_joueur.x, sous_le_joueur.z)
	var attendu := TerrainVisible.colonnes_du_disque(centre, terrain.rayon_cellules)

	# L'ATTENDU SE DEMANDE A LA CARTE, colonne par colonne. Le deduire du nombre
	# de colonnes fois les couches par defaut suppose un terrain PLAT : le jour
	# ou la carte porte du relief, le test rougit sans qu'aucun code n'ait
	# change, et il mesure alors le travail du sculpteur au lieu du code.
	var cellules_attendues := 0
	for colonne in attendu:
		cellules_attendues += carte.cellules_de(colonne).size()
	_v.v(posees == cellules_attendues,
		"%d cellules posees, %d attendues sur les %d colonnes du disque" % [
			posees, cellules_attendues, attendu.size()])

	# La physique a besoin d'une image pour donner un corps aux cellules qui
	# viennent d'etre posees.
	await physics_frame

	# LE SOL SE MESURE AU RAYON, JAMAIS CALCULE ICI. Entre la couche d'une
	# cellule et la cote de sa face du dessus il y a le centrage des cellules,
	# qui est un reglage du noeud -- le recalculer serait supposer ce reglage.
	# LE RAYON SE TIRE SOUS LE PERSONNAGE, jamais a l'origine : la carte se
	# sculpte, et rien ne garantit que la colonne (0,0) porte encore du terrain.
	# Un test qui vise un point fixe finit par mesurer le travail du sculpteur.
	var sous_lui := terrain.to_local(personnage.global_position)
	var sol: Variant = _cote_du_sol(terrain, Vector3(sous_lui.x, 0.0, sous_lui.z),
		[personnage.get_rid()])
	if sol == null:
		_v.v(false, "aucun sol sous le personnage (%v) : les cellules posees ne collisionnent pas" % [
			personnage.global_position])
		_conclure(racine)
		return
	var cote_du_sol := float(sol)

	# LA SCENE NE LE POSE NI DANS LA ROCHE NI EN ORBITE. Exiger le centimetre
	# serait trop strict : la position se regle a la souris et une chute d'un
	# metre ou deux au demarrage ne casse rien. Ce qui casse, c'est un
	# personnage ENFONCE dans le terrain -- il y reste coince -- ou lache de si
	# haut que la partie commence par une chute.
	var depart := personnage.global_position.y
	_v.v(depart >= cote_du_sol - TOLERANCE_POSE,
		"la scene enfonce le personnage a %.2f m alors que le sol est a %.2f m" % [
			depart, cote_du_sol])
	_v.v(depart <= cote_du_sol + CHUTE_TOLEREE,
		"la scene lache le personnage a %.2f m, soit %.1f m au-dessus du sol" % [
			depart, depart - cote_du_sol])

	# LE TERRAIN LE RATTRAPE. Sans ce lacher, un personnage deja pose passerait
	# le jugement sans qu'aucune collision n'ait jamais ete eprouvee -- c'est le
	# faux vert exact que ce morceau existe pour attraper.
	personnage.global_position = Vector3(
		personnage.global_position.x,
		cote_du_sol + HAUTEUR_DE_LACHER,
		personnage.global_position.z)
	for i in range(IMAGES_DE_CHUTE):
		await physics_frame
	var apres_chute := personnage.global_position.y
	_v.v(absf(apres_chute - cote_du_sol) < TOLERANCE_POSE,
		"lache %.1f m au-dessus du sol, le personnage est a %.2f m, sol a %.2f m" % [
			HAUTEUR_DE_LACHER, apres_chute, cote_du_sol])

	print("scene : %d cellules posees autour du personnage, carte de %.0f km² (%d colonnes)" % [
		posees, carte.superficie_km2(), carte.colonnes()])
	print("        sol mesure au rayon a %.2f m, personnage pose a %.2f m au depart, %.2f m apres une chute de %.1f m" % [
		cote_du_sol, depart, apres_chute, HAUTEUR_DE_LACHER])
	_conclure(racine)

# La cote du premier point touche par un rayon lance vers le bas. Rend null
# quand le rayon ne touche rien : il n'existe pas de cote sentinelle qu'un
# appelant prendrait pour une surface. Meme geste que test_rampe.gd.
#
# LE PERSONNAGE S'EXCLUT, sans quoi le rayon lui touche le crane et rend une
# cote qui n'est celle d'aucun sol.
func _cote_du_sol(terrain: GridMap, ou: Vector3, exclus: Array[RID]) -> Variant:
	var depart := Vector3(ou.x, ou.y + HAUTEUR_DE_TIR, ou.z)
	var arrivee := Vector3(ou.x, ou.y - HAUTEUR_DE_TIR, ou.z)
	var requete := PhysicsRayQueryParameters3D.create(
		terrain.to_global(depart), terrain.to_global(arrivee))
	requete.exclude = exclus
	var touche := terrain.get_world_3d().direct_space_state.intersect_ray(requete)
	if touche.is_empty():
		return null
	return (touche["position"] as Vector3).y

# LE JUGEMENT PRECEDENT SERAIT TAUTOLOGIQUE SEUL : la scene regle deja des
# cellules de deux metres et la carte livree en declare deux, si bien qu'il
# passerait meme si plus rien n'imposait l'une a l'autre. On monte donc un
# terrain dont la scene et la carte SE CONTREDISENT, et c'est la carte qui doit
# gagner.
func _arete_imposee(modele: GridMap) -> void:
	var CarteTerrain := load("res://jeu/terrain/carte_terrain.gd")
	var carte: Resource = CarteTerrain.new()
	carte.demi_cote = 20
	carte.cote = 3.0

	var terrain: GridMap = load("res://jeu/terrain/terrain_visible.gd").new()
	terrain.mesh_library = modele.mesh_library
	# Une arete VOLONTAIREMENT fausse, comme une scene qui l'aurait figee.
	terrain.cell_size = Vector3(5.0, 5.0, 5.0)
	terrain.carte = carte
	terrain.rayon_cellules = 3
	get_root().add_child(terrain)
	await process_frame

	_v.v(terrain.cell_size.is_equal_approx(Vector3(3.0, 3.0, 3.0)),
		"la scene a impose des cellules de %v : la carte declare 3.0 et ne gagne pas" % [
			terrain.cell_size])
	terrain.queue_free()

# LE FILET : un terrain dont la scene porte une bibliotheque SANS COLLISION doit
# reprendre celle du jeu avant de dessiner. Sans ce jugement, rien ne distingue
# un sol solide d'un sol traversable -- les cellules sont posees dans les deux
# cas, elles se voient dans les deux cas, et seul le personnage tombe.
func _collision_reprise(_modele: GridMap) -> void:
	# ON PART DE bloc.tres, jamais de la bibliotheque du terrain de la scene :
	# celle-la a pu etre reprise par le filet qu'on veut justement eprouver.
	var de_jeu := load("res://jeu/terrain/bloc.tres") as MeshLibrary
	if de_jeu == null or de_jeu.get_item_list().is_empty():
		_v.v(false, "bloc.tres ne se charge pas : le test ne prouverait rien")
		return
	var premier: int = de_jeu.get_item_list()[0]
	if de_jeu.get_item_shapes(premier).is_empty():
		_v.v(false, "bloc.tres n'a aucune forme de collision : le test ne prouverait rien")
		return

	# La bibliotheque allegee, exactement celle que l'outil de fenetre pose.
	var Outil := load("res://jeu/terrain/outil_fenetre.gd")
	var allegee: MeshLibrary = Outil.sans_collision(de_jeu)

	var racine := Node3D.new()
	get_root().add_child(racine)

	# L'outil de fenetre, qui a mis la vraie de cote -- c'est chez lui que le
	# terrain va la rechercher.
	var outil: Node3D = Outil.new()
	outil.bibliotheque_de_jeu = de_jeu
	racine.add_child(outil)

	var CarteTerrain := load("res://jeu/terrain/carte_terrain.gd")
	var carte: Resource = CarteTerrain.new()
	carte.demi_cote = 20

	var terrain: GridMap = load("res://jeu/terrain/terrain_visible.gd").new()
	# LA SCENE PORTE L'ALLEGEE, comme apres une sauvegarde en cours de sculpture.
	terrain.mesh_library = allegee
	terrain.carte = carte
	terrain.rayon_cellules = 3
	racine.add_child(terrain)
	await process_frame

	_v.v(terrain.mesh_library == de_jeu,
		"le terrain a garde la bibliotheque d'edition : le sol du jeu serait traversable")

	# CE QUE CE JUGEMENT NE COUVRE PAS : que le terrain pose des cellules. Le
	# compte depend ici de l'observateur, que la scene deja instanciee fournit,
	# et le mesurer reviendrait a tester le placement du personnage. La pose est
	# verrouillee par test_terrain_visible.gd, sur un terrain isole.

	# La collision existe vraiment, pas seulement la reference.
	var reprise := terrain.mesh_library
	_v.v(not reprise.get_item_shapes(reprise.get_item_list()[0]).is_empty(),
		"la bibliotheque reprise n'a aucune forme de collision")

	racine.queue_free()

# CE QUE LA SCENE PORTE EST DU TRAVAIL, pas un residu. Un terrain sculpte dans
# l'editeur et enregistre avec la scene doit arriver dans le jeu SANS avoir
# transite par quoi que ce soit d'autre : ce transit dependait d'un _process
# d'editeur, d'un script recharge et d'une fenetre chargee -- quatre conditions
# dont aucune ne se signale quand elle manque, et le travail etait efface.
func _scene_reprise(modele: GridMap) -> void:
	var CarteTerrain := load("res://jeu/terrain/carte_terrain.gd")
	var carte: Resource = CarteTerrain.new()
	carte.demi_cote = 50
	var base: int = carte.sommet_de_base()

	var racine := Node3D.new()
	get_root().add_child(racine)
	var terrain: GridMap = load("res://jeu/terrain/terrain_visible.gd").new()
	terrain.mesh_library = modele.mesh_library
	terrain.carte = carte
	terrain.rayon_cellules = 20
	# AUCUN OBSERVATEUR pour ce terrain : la scene deja instanciee en fournit
	# un, et le disque se centrerait sous LUI au lieu de l'origine. Le test
	# mesurerait alors le placement du personnage.
	terrain.groupe_observateur = &"aucun_observateur_pour_ce_test"

	# Les cellules sont posees AVANT l'entree dans l'arbre : c'est exactement ce
	# que porte une scene sculptee puis enregistree.
	var bloc := terrain.mesh_library.get_item_list()[0]
	var colonne := Vector2i(4, -3)
	for y in range(carte.couche_base, base + 1):
		terrain.set_cell_item(Vector3i(colonne.x, y, colonne.y), bloc)
	terrain.set_cell_item(Vector3i(colonne.x, base + 3, colonne.y), bloc)
	_v.v(carte.colonnes_sculptees() == 0, "la carte n'est pas vierge : le test ne prouverait rien")

	racine.add_child(terrain)
	await process_frame

	_v.v(carte.sommet_max_colonne(colonne) == base + 3,
		"le relief de la scene n'est pas passe dans la carte : sommet %s" % [
			carte.sommet_max_colonne(colonne)])
	_v.v(not carte.est_pleine(colonne, base + 1),
		"le vide entre les deux niveaux a ete comble en reprenant la scene")
	_v.v(carte.est_sale(), "la carte n'est pas marquee : la reprise ne serait jamais ecrite")

	var haut := -1
	for cellule in terrain.get_used_cells():
		if cellule.x == colonne.x and cellule.z == colonne.y:
			haut = maxi(haut, cellule.y)
	_v.v(haut == base + 3,
		"le terrain rendu monte a la couche %d, %d attendu : la reprise n'est pas redessinee" % [
			haut, base + 3])

	racine.queue_free()

func _conclure(racine: Node) -> void:
	if racine != null:
		racine.queue_free()
	if _v.echecs() > 0:
		print("ECHEC: le cablage de la scene ne tient pas (%d)" % _v.echecs())
		quit(1)
		return
	print("OK: scene de la carte -- ce que la scene porte est repris dans la carte, carte de 100 km² branchee, personnage dans le groupe observateur, terrain pose autour de lui, sol solide")
	quit(0)
