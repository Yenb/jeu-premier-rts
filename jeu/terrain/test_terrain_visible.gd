extends SceneTree

# Test manuel :
# godot --headless --script jeu/terrain/test_terrain_visible.gd
#
# Verrouille res://jeu/terrain/terrain_visible.gd, le dessinateur de la carte :
# - le disque pose ce qui est a `rayon` et rien au-dela ;
# - le seuil de rafraichissement ne declenche pas sous le pas, declenche au pas,
#   et declenche TOUJOURS a l'amorce ;
# - LE COMPTE DE CELLULES NE SUIT PAS LA CARTE : traverser dix kilometres sur
#   une carte de 100 km² laisse le GridMap au meme nombre de cellules qu'au
#   premier pas. C'est la seule chose qui rend l'echelle tenable, et c'est ce
#   que ce test existe pour tenir ;
# - AUCUNE CELLULE NE TRAINE derriere l'observateur : apres la traversee, les
#   colonnes du GridMap sont EXACTEMENT celles du disque final. Une cellule
#   oubliee ne se voit pas a l'ecran, elle ne se voit que dans ce compte ;
# - le bord d'emprise coupe le disque au lieu de poser dans le vide ;
# - une colonne sculptee pose la hauteur que la carte lui donne, pas le defaut.
#
# Entree : la bibliotheque res://jeu/terrain/bloc.tres et un GridMap construit
# ici, jamais enregistre dans une scene. Sortie : une ligne « OK: » et le code 0
# si tout tient, « ECHEC: » et le code 1 sinon.
#
# LE NOEUD N'EST PAS INSTANCIE, ET C'EST VOLONTAIRE : tout ce qui decide de ce
# qui est pose est statique, et _process ne fait que declencher. Ce test appelle
# donc les memes fonctions que la boucle d'images, sans boucle d'images.
#
# Regles tenues : positions en Vector3, jamais Vector2 -- une colonne est un
# Vector2i. Aucun hasard. Les prints sont des traces de mise au point, pas du
# texte joueur. Rien de scripts/, data/ ni documents/ n'est ecrit.

const Verif = preload("res://scripts/verif.gd")
const CarteTerrain = preload("res://jeu/terrain/carte_terrain.gd")
const TerrainVisible = preload("res://jeu/terrain/terrain_visible.gd")
const Commun = preload("res://jeu/terrain/terrain_commun.gd")

const CHEMIN_BIBLIOTHEQUE := "res://jeu/terrain/bloc.tres"
const CHEMIN_CARTE := "res://jeu/terrain/carte_100km2.tres"

# Le rayon d'essai, plus court que celui de jeu : ce qui est verrouille est
# l'invariance du compte, pas une valeur de reglage.
const RAYON := 30
const PAS := 4

# La traversee : la carte livree d'un bord a l'autre, moins la marge qui garde
# le disque ENTIER du depart a l'arrivee. Sans cette marge le disque est coupe
# par le bord aux deux extremites, et le compte de cellules varie pour une
# raison qui n'a rien a voir avec ce que ce test verrouille.
const MARGE_DU_BORD := 100
const CELLULES_TRAVERSEES := 4800

# Le rayon reellement pose en jeu, mesure a part : ce que coute un
# rafraichissement decide s'il tient dans une image ou s'il doit s'etaler.
const RAYON_DE_JEU := 50

var _v
var _grille: GridMap

func _init() -> void:
	_v = Verif.new()
	_grille = _construire_grille()
	if _grille == null:
		_conclure()
		return
	_disque()
	_seuil()
	_traversee()
	_bord_emprise()
	_colonne_sculptee()
	# DIFFERE : un noeud ajoute ici n'entrerait pas encore dans l'arbre, et son
	# _ready ne partirait jamais. Meme raison que test_maquette.gd.
	_etalement.call_deferred()

func _construire_grille() -> GridMap:
	var bibliotheque := load(CHEMIN_BIBLIOTHEQUE) as MeshLibrary
	if bibliotheque == null:
		_v.v(false, "%s ne se charge pas" % CHEMIN_BIBLIOTHEQUE)
		return null
	var grille := GridMap.new()
	grille.cell_size = Vector3(2.0, 2.0, 2.0)
	grille.mesh_library = bibliotheque
	get_root().add_child(grille)
	return grille

func _carte_livree() -> Resource:
	var carte: Resource = load(CHEMIN_CARTE)
	if carte == null:
		_v.v(false, "%s ne se charge pas" % CHEMIN_CARTE)
	return carte

func _disque() -> void:
	var disque := TerrainVisible.colonnes_du_disque(Vector2i.ZERO, RAYON)
	_v.v(disque.has(Vector2i(RAYON, 0)), "la colonne a distance exacte du rayon n'est pas posee")
	_v.v(disque.has(Vector2i(0, -RAYON)), "le disque n'est pas symetrique sur l'axe z")
	_v.v(not disque.has(Vector2i(RAYON + 1, 0)), "une colonne au-dela du rayon est posee")
	_v.v(not disque.has(Vector2i(RAYON, RAYON)),
		"le coin du carre circonscrit est pose : le disque est en fait un carre")

	# Le compte doit approcher π·r² ; large tolerance, ce qui se refuse ici est
	# un carre (4r²) ou un demi-disque, jamais quelques cellules de bord.
	var attendu := PI * float(RAYON * RAYON)
	_v.v(absf(float(disque.size()) - attendu) < attendu * 0.1,
		"le disque compte %d colonnes, environ %.0f attendues" % [disque.size(), attendu])

	# Le disque se DEPLACE avec son centre sans changer de taille.
	var ailleurs := TerrainVisible.colonnes_du_disque(Vector2i(1000, -2000), RAYON)
	_v.v(ailleurs.size() == disque.size(), "le disque change de taille selon son centre")
	_v.v(ailleurs.has(Vector2i(1000, -2000)), "le disque ne contient pas son propre centre")

func _seuil() -> void:
	_v.v(TerrainVisible.doit_rafraichir(Vector2i.ZERO, Vector2i.ZERO, PAS, false),
		"le premier passage ne declenche pas : le terrain resterait vide")
	_v.v(not TerrainVisible.doit_rafraichir(Vector2i.ZERO, Vector2i(PAS - 1, 0), PAS, true),
		"un ecart sous le pas declenche un rafraichissement")
	_v.v(TerrainVisible.doit_rafraichir(Vector2i.ZERO, Vector2i(PAS, 0), PAS, true),
		"un ecart egal au pas ne declenche pas")
	_v.v(TerrainVisible.doit_rafraichir(Vector2i.ZERO, Vector2i(0, -PAS), PAS, true),
		"le seuil ne regarde pas l'axe z")

func _traversee() -> void:
	var carte := _carte_livree()
	if carte == null:
		return
	var bloc := Commun.premier_bloc(_grille)
	if bloc == GridMap.INVALID_CELL_ITEM:
		_v.v(false, "aucun bloc dans la bibliotheque")
		return

	# On part a MARGE_DU_BORD cellules du bord pour que le disque reste entier
	# tout du long : ce qui est mesure ici est l'invariance du compte, pas la
	# coupe au bord, qui se verrouille a part.
	var depart := Vector2i(-carte.demi_cote + MARGE_DU_BORD, 0)
	_v.v(depart.x + CELLULES_TRAVERSEES + RAYON <= carte.demi_cote,
		"la traversee sort de l'emprise : le disque serait coupe a l'arrivee")
	var pose: Dictionary = {}
	var bilan := TerrainVisible.rafraichir(_grille, carte, pose, depart, RAYON, bloc)
	pose = bilan.pose
	var cellules_initiales := _grille.get_used_cells().size()
	var colonnes_initiales: int = pose.size()
	_v.v(cellules_initiales == colonnes_initiales * carte.couches_pleines,
		"%d cellules posees pour %d colonnes de %d couches" % [
			cellules_initiales, colonnes_initiales, carte.couches_pleines])

	var debut := Time.get_ticks_usec()
	var rafraichissements := 0
	var maximum := cellules_initiales
	var centre := depart
	while centre.x < depart.x + CELLULES_TRAVERSEES:
		centre.x += PAS
		if not TerrainVisible.doit_rafraichir(pose_centre(centre, PAS), centre, PAS, true):
			continue
		bilan = TerrainVisible.rafraichir(_grille, carte, pose, centre, RAYON, bloc)
		pose = bilan.pose
		rafraichissements += 1
		maximum = maxi(maximum, _grille.get_used_cells().size())
	var duree := (Time.get_ticks_usec() - debut) / 1000.0

	var cellules_finales := _grille.get_used_cells().size()
	_v.v(cellules_finales == cellules_initiales,
		"apres %d cellules traversees, %d cellules posees contre %d au depart" % [
			CELLULES_TRAVERSEES, cellules_finales, cellules_initiales])
	_v.v(maximum == cellules_initiales,
		"le compte de cellules a culmine a %d, %d au depart" % [maximum, cellules_initiales])

	# AUCUNE CELLULE NE TRAINE : les colonnes du GridMap sont exactement celles
	# du disque final. Un oubli laisserait des cellules derriere l'observateur
	# sans changer aucun autre compte.
	var colonnes_grille: Dictionary = {}
	for cellule in _grille.get_used_cells():
		colonnes_grille[Vector2i(cellule.x, cellule.z)] = true
	_v.v(colonnes_grille.size() == pose.size(),
		"%d colonnes dans le GridMap, %d dans l'ensemble pose" % [
			colonnes_grille.size(), pose.size()])
	var etrangeres := 0
	for colonne in colonnes_grille:
		if not pose.has(colonne):
			etrangeres += 1
	_v.v(etrangeres == 0, "%d colonnes posees hors du disque final" % etrangeres)

	print("traversee : %d cellules parcourues, %d rafraichissements en %.0f ms, %d cellules posees en permanence (%.1f Mo de memoire de grille)" % [
		CELLULES_TRAVERSEES, rafraichissements, duree, cellules_finales,
		float(cellules_finales) * 86.0 / 1048576.0])
	print("            la carte declare %d colonnes ; la grille en porte %d" % [
		carte.colonnes(), pose.size()])
	_cout_au_rayon_de_jeu(carte, bloc)

# CE QUE COUTE UN RAFRAICHISSEMENT AU RAYON DE JEU, mesure separement : la
# traversee tourne a rayon reduit pour rester courte, et le cout suit r². Le
# chiffre qui compte pour l'image est celui-ci.
func _cout_au_rayon_de_jeu(carte: Resource, bloc: int) -> void:
	var grille := GridMap.new()
	grille.cell_size = Vector3(2.0, 2.0, 2.0)
	grille.mesh_library = _grille.mesh_library
	get_root().add_child(grille)

	var centre := Vector2i(0, 0)
	var debut := Time.get_ticks_usec()
	var bilan := TerrainVisible.rafraichir(grille, carte, {}, centre, RAYON_DE_JEU, bloc)
	var premier := (Time.get_ticks_usec() - debut) / 1000.0

	debut = Time.get_ticks_usec()
	var suivant := TerrainVisible.rafraichir(grille, carte, bilan.pose,
		Vector2i(centre.x + PAS, centre.y), RAYON_DE_JEU, bloc)
	var apres_un_pas := (Time.get_ticks_usec() - debut) / 1000.0

	print("cout au rayon de jeu (%d cellules) : premier pose %.1f ms pour %d cellules, puis %.1f ms par pas de %d (%d colonnes entrent, %d sortent)" % [
		RAYON_DE_JEU, premier, bilan.cellules_posees, apres_un_pas, PAS,
		suivant.entrantes, suivant.sortantes])
	grille.queue_free()

# Le centre pose implicite pendant la traversee : le pas est franchi a chaque
# tour, donc le centre precedent est toujours a `pas` en arriere.
func pose_centre(centre: Vector2i, pas: int) -> Vector2i:
	return Vector2i(centre.x - pas, centre.y)

func _bord_emprise() -> void:
	var carte: Resource = CarteTerrain.new()
	carte.demi_cote = 40
	var grille := GridMap.new()
	grille.cell_size = Vector3(2.0, 2.0, 2.0)
	grille.mesh_library = _grille.mesh_library
	get_root().add_child(grille)
	var bloc := Commun.premier_bloc(grille)

	# Centre pose sur le coin de l'emprise : trois quarts du disque tombent
	# dehors.
	var bilan := TerrainVisible.rafraichir(grille, carte, {}, Vector2i(39, 39), RAYON, bloc)
	var pose: Dictionary = bilan.pose
	var entier := TerrainVisible.colonnes_du_disque(Vector2i(39, 39), RAYON)
	_v.v(pose.size() < entier.size(),
		"le disque au coin de l'emprise pose autant qu'au centre : le bord ne coupe rien")
	var dehors := 0
	for colonne in pose:
		if not carte.dans_emprise(colonne):
			dehors += 1
	_v.v(dehors == 0, "%d colonnes posees hors emprise" % dehors)
	for cellule in grille.get_used_cells():
		if not carte.dans_emprise(Vector2i(cellule.x, cellule.z)):
			_v.v(false, "cellule %v posee hors emprise" % cellule)
			break
	grille.queue_free()

func _colonne_sculptee() -> void:
	var carte: Resource = CarteTerrain.new()
	carte.demi_cote = 100
	var creusee := Vector2i(3, 3)
	var montee := Vector2i(-3, -3)
	carte.sculpter(creusee, carte.couche_base)
	carte.sculpter(montee, carte.sommet_de_base() + 4)

	var grille := GridMap.new()
	grille.cell_size = Vector3(2.0, 2.0, 2.0)
	grille.mesh_library = _grille.mesh_library
	get_root().add_child(grille)
	var bloc := Commun.premier_bloc(grille)
	TerrainVisible.rafraichir(grille, carte, {}, Vector2i.ZERO, 10, bloc)

	var hauteurs: Dictionary = {}
	for cellule in grille.get_used_cells():
		var colonne := Vector2i(cellule.x, cellule.z)
		if not hauteurs.has(colonne) or cellule.y > int(hauteurs[colonne]):
			hauteurs[colonne] = cellule.y
	_v.v(int(hauteurs.get(creusee, -99)) == carte.couche_base,
		"la colonne creusee monte a %s, couche %d attendue" % [
			hauteurs.get(creusee, null), carte.couche_base])
	_v.v(int(hauteurs.get(montee, -99)) == carte.sommet_de_base() + 4,
		"la colonne montee s'arrete a %s, couche %d attendue" % [
			hauteurs.get(montee, null), carte.sommet_de_base() + 4])
	_v.v(int(hauteurs.get(Vector2i(5, 5), -99)) == carte.sommet_de_base(),
		"une colonne non sculptee ne monte pas au sommet par defaut")
	grille.queue_free()

# VERROUILLE LE RAFRAICHISSEMENT ETALE (_retargeter / _avancer_file), le
# chemin qu'emprunte le jeu -- rafraichir() reste le chemin des sections
# ci-dessus, tout d'un coup.
func _etalement() -> void:
	var carte: Resource = CarteTerrain.new()
	carte.demi_cote = 100

	var bibliotheque := load(CHEMIN_BIBLIOTHEQUE) as MeshLibrary
	var terrain: GridMap = TerrainVisible.new()
	terrain.mesh_library = bibliotheque
	terrain.cell_size = Vector3(2.0, 2.0, 2.0)
	terrain.carte = carte
	terrain.rayon_cellules = 10
	terrain.pas_de_rafraichissement = 2
	terrain.colonnes_par_image = 7
	get_root().add_child(terrain)

	var complet: Dictionary = terrain._pose.duplicate()
	var attendu := TerrainVisible.colonnes_du_disque(Vector2i.ZERO, 10)
	_v.v(complet.size() == attendu.size(),
		"le premier affichage n'est pas complet : %d colonnes, %d attendues" % [
			complet.size(), attendu.size()])
	_v.v(terrain._a_poser.is_empty() and terrain._a_effacer.is_empty(),
		"le premier affichage laisse des files non vides")

	# UN DEMI-TOUR AVANT LE MOINDRE DRAINAGE N'A RIEN A FAIRE : les deux files
	# reviennent exactement a vide, l'etat reste celui du premier affichage.
	terrain._retargeter(Vector2i(4, 0))
	_v.v(not terrain._a_poser.is_empty() or not terrain._a_effacer.is_empty(),
		"viser une nouvelle cible ne remplit aucune file : le test ne prouve rien")
	terrain._retargeter(Vector2i.ZERO)
	_v.v(terrain._a_poser.is_empty() and terrain._a_effacer.is_empty(),
		"revenir a la cible de depart avant tout drainage laisse du travail en file")
	_v.v(terrain._pose.size() == complet.size(),
		"un aller-retour sans drainage a quand meme change ce qui est pose")

	# UNE VRAIE CIBLE : chaque image ne draine que le budget, jusqu'a vider
	# les files et rejoindre exactement le disque vise.
	terrain._retargeter(Vector2i(4, 0))
	var vise := TerrainVisible.colonnes_du_disque(Vector2i(4, 0), 10)
	for colonne in vise.keys():
		if not carte.dans_emprise(colonne):
			vise.erase(colonne)
	var total_en_file: int = terrain._a_poser.size() + terrain._a_effacer.size()
	_v.v(total_en_file > terrain.colonnes_par_image,
		"le deplacement d'essai ne met pas plus d'une image de travail en file : le test ne prouve rien")

	terrain._avancer_file()
	_v.v(terrain._a_poser.size() + terrain._a_effacer.size()
			== total_en_file - terrain.colonnes_par_image,
		"une image ne draine pas exactement le budget alors qu'il en reste plus que ca")

	var images := 1
	while (not terrain._a_poser.is_empty() or not terrain._a_effacer.is_empty()) and images < 1000:
		terrain._avancer_file()
		images += 1
	_v.v(images > 1, "une seule image a suffi a tout drainer : le test ne prouve pas l'etalement")
	_v.v(terrain._a_poser.is_empty() and terrain._a_effacer.is_empty(),
		"les files ne se vident jamais apres %d images" % images)
	_v.v(terrain._pose.size() == vise.size(),
		"apres etalement complet, %d colonnes posees, %d visees" % [terrain._pose.size(), vise.size()])

	var colonnes_grille: Dictionary = {}
	for cellule in terrain.get_used_cells():
		colonnes_grille[Vector2i(cellule.x, cellule.z)] = true
	_v.v(colonnes_grille.size() == vise.size(),
		"%d colonnes dans le GridMap apres etalement, %d visees" % [colonnes_grille.size(), vise.size()])

	terrain.queue_free()
	_conclure()

func _conclure() -> void:
	if _grille != null:
		_grille.queue_free()
	if _v.echecs() > 0:
		print("ECHEC: le dessinateur de terrain ne tient pas (%d)" % _v.echecs())
		quit(1)
		return
	print("OK: terrain visible -- disque borne par le rayon, compte de cellules invariant sur dix kilometres, rien ne traine, bord d'emprise coupe, relief suivi, rafraichissement etale sur plusieurs images en jeu")
	quit(0)
