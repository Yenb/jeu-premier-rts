extends SceneTree

# Test manuel :
# godot --headless --script jeu/terrain/test_carte_terrain.gd
#
# Verrouille res://jeu/terrain/carte_terrain.gd et la carte livree
# res://jeu/terrain/carte_100km2.tres :
# - la carte livree couvre bien 100 km2 et porte son emprise elle-meme ;
# - SON POIDS SUIT CE QUI EST SCULPTE, jamais son emprise. Exiger qu'elle reste
#   vierge mesurerait le travail de Yael au lieu du code : elle se remplit, et
#   c'est justement ce qu'on veut. Ce qui est verrouille est le cout PAR COLONNE
#   sculptee ;
# - une carte vierge ne stocke AUCUNE colonne et tient sous un plafond d'octets,
#   quelle que soit son emprise -- c'est la seule chose qui rend l'echelle
#   tenable, et un stockage par colonne la ferait sauter sans qu'aucun autre
#   test ne rougisse ;
# - UNE CARTE EST UN VOLUME, PAS UN RELIEF : deux niveaux separes par du vide
#   restent deux niveaux, une grotte creusee au milieu d'une colonne reste une
#   grotte, un pont garde le vide dessous. Une hauteur unique par colonne les
#   remplissait tous du fond au sommet, et TOUT le terrain destructible de
#   GAME_DESIGN.md en depend ;
# - le sommet vaut le defaut partout dans l'emprise, null au-dela, et null sur
#   une colonne creusee jusqu'au vide ;
# - une colonne remise au defaut SORT du stockage : sculpter puis defaire ne
#   laisse rien derriere ;
# - une carte sculptee relue sur le disque rend le meme relief ;
# - LE COUT D'UNE LECTURE NE SUIT PAS CE QUI EST SCULPTE : le meme tirage de
#   colonnes se lit dans le meme ordre de temps sur une carte vierge et sur une
#   carte a cent mille colonnes sculptees. Sans ce plafond, le jour ou l'acces
#   deviendrait lineaire, tous les tests de correction resteraient verts.
#
# Entree : la carte livree sur le disque, plus des cartes construites ici et
# ecrites sous user:// (jamais dans le depot). Sortie : une ligne « OK: » et le
# code 0 si tout tient, « ECHEC: » et le code 1 sinon.
#
# Regles tenues : aucun hasard non seede -- le tirage de colonnes passe par un
# RandomNumberGenerator de graine fixe. Les prints sont des traces de mise au
# point, pas du texte joueur. Rien de scripts/, data/ ni documents/ n'est ecrit.

const Verif = preload("res://scripts/verif.gd")
const CarteTerrain = preload("res://jeu/terrain/carte_terrain.gd")

const CHEMIN_LIVREE := "res://jeu/terrain/carte_100km2.tres"

# L'emprise de la carte livree, et la superficie qu'elle doit couvrir.
const EMPRISE_LIVREE := 2500
const KM2_LIVRES := 100.0
const TOLERANCE_KM2 := 0.001

# Ce qu'une carte VIERGE a le droit de peser, quelle que soit son emprise. Le
# repere qui donne son sens a ce plafond : un GridMap plein a la meme emprise
# pese 16,5 octets par cellule, soit pres de trois milliards pour 100 km2.
const PLAFOND_OCTETS_VIERGE := 4096

# Ce qu'une colonne SCULPTEE a le droit de peser sur le disque. C'est le bon
# invariant pour la carte livree : elle se remplit au fil du travail, et exiger
# qu'elle reste vierge reviendrait a mesurer ce que Yael a sculpte au lieu de
# mesurer le code.
const PLAFOND_OCTETS_PAR_COLONNE := 60.0

# Le tirage de cout : combien de colonnes lues, et combien sculptees sur la
# carte chargee a laquelle on compare.
const GRAINE := 20260819
const LECTURES := 100000
const COLONNES_SCULPTEES := 100000

# Ce que le temps de lecture a le droit de faire quand la carte est chargee.
# Genereux : ce qu'on refuse ici est un cout qui SUIT le stockage, pas quelques
# pourcents de bruit machine.
const RAPPORT_MAXIMAL := 4.0

var _v

func _init() -> void:
	_v = Verif.new()
	_carte_livree()
	_volume()
	_emprise_et_sommet()
	_sculpture()
	_serialisation()
	_cout_de_lecture()
	_conclure()

func _carte_livree() -> void:
	if not FileAccess.file_exists(CHEMIN_LIVREE):
		_v.v(false, "%s n'existe pas : la carte livree n'a pas ete ecrite" % CHEMIN_LIVREE)
		return
	var carte: Resource = load(CHEMIN_LIVREE)
	# Une ressource qui ne se charge pas ROUGIT, elle ne se saute jamais.
	if carte == null:
		_v.v(false, "%s ne se charge pas" % CHEMIN_LIVREE)
		return
	_v.v(carte.demi_cote == EMPRISE_LIVREE,
		"la carte livree porte une emprise de %d, %d attendu" % [carte.demi_cote, EMPRISE_LIVREE])
	_v.v(absf(carte.superficie_km2() - KM2_LIVRES) < TOLERANCE_KM2,
		"la carte livree couvre %.4f km2, %.1f attendu" % [carte.superficie_km2(), KM2_LIVRES])
	_v.v(carte.colonnes() == EMPRISE_LIVREE * EMPRISE_LIVREE * 4,
		"la carte livree declare %d colonnes" % carte.colonnes())
	var octets := FileAccess.open(CHEMIN_LIVREE, FileAccess.READ).get_length()
	var sculptees: int = carte.colonnes_sculptees()

	# SON POIDS SUIT LE TRAVAIL, JAMAIS L'EMPRISE. C'est ce qui rend une carte
	# de cent kilometres carres tenable : vierge elle ne pese rien, et ce
	# qu'elle porte est ce qui a ete sculpte. Un GridMap plein a la meme emprise
	# pese pres de trois milliards d'octets.
	if sculptees == 0:
		_v.v(octets <= PLAFOND_OCTETS_VIERGE,
			"la carte livree est vierge et pese %d octets, plafond %d" % [
				octets, PLAFOND_OCTETS_VIERGE])
	else:
		var par_colonne := float(octets) / float(sculptees)
		_v.v(par_colonne <= PLAFOND_OCTETS_PAR_COLONNE,
			"la carte livree pese %.1f octets par colonne sculptee, plafond %.1f" % [
				par_colonne, PLAFOND_OCTETS_PAR_COLONNE])
	print("carte livree : %.2f km2, %d colonnes dont %d sculptees, %d octets (%.1f par colonne sculptee)" % [
		carte.superficie_km2(), carte.colonnes(), sculptees, octets,
		float(octets) / float(maxi(sculptees, 1))])

# CE QUE LE RELIEF NE SAVAIT PAS FAIRE. Chaque jugement ici serait faux avec une
# hauteur unique par colonne.
func _volume() -> void:
	var carte: Resource = CarteTerrain.new()
	carte.demi_cote = 100
	var base: int = carte.couche_base

	# DEUX NIVEAUX SEPARES PAR DU VIDE : le sol, puis une plateforme au-dessus.
	var plateforme := Vector2i(5, 5)
	var bits: int = CarteTerrain.masque_depuis([base, base + 1, base + 6, base + 7], base)
	_v.v(carte.poser_masque(plateforme, bits), "poser un masque dans l'emprise a echoue")

	var cellules: Array[Vector3i] = carte.cellules_de(plateforme)
	_v.v(cellules.size() == 4,
		"la colonne a deux niveaux rend %d cellules, 4 attendues : le vide a ete comble" % [
			cellules.size()])
	_v.v(carte.est_pleine(plateforme, base + 1), "le niveau du bas a disparu")
	_v.v(not carte.est_pleine(plateforme, base + 2),
		"le vide entre les deux niveaux a ete rempli : la carte reste un relief")
	_v.v(not carte.est_pleine(plateforme, base + 5), "le vide n'est pas complet")
	_v.v(carte.est_pleine(plateforme, base + 7), "le niveau du haut a disparu")
	_v.v(carte.sommet_max_colonne(plateforme) == base + 7,
		"le sommet ne designe pas la couche la plus haute : %s" % [carte.sommet_max_colonne(plateforme)])

	# UNE GROTTE : la colonne est pleine, sauf en son milieu.
	var grotte := Vector2i(-7, 3)
	var pleine: int = carte.masque_de_base()
	var creuse := pleine & ~(1 << 3)
	carte.poser_masque(grotte, creuse)
	_v.v(not carte.est_pleine(grotte, base + 3), "la grotte a ete rebouchee")
	_v.v(carte.est_pleine(grotte, base + 2) and carte.est_pleine(grotte, base + 4),
		"la grotte a emporte ses voisines")
	_v.v(carte.sommet_max_colonne(grotte) == carte.sommet_de_base(),
		"creuser au milieu a change le sommet")
	_v.v(carte.cellules_de(grotte).size() == carte.couches_pleines - 1,
		"la colonne creusee rend %d cellules, %d attendues" % [
			carte.cellules_de(grotte).size(), carte.couches_pleines - 1])

	# LE POIDS SUIT LE VOLUME, PAS SA COMPLEXITE : une colonne = une entree,
	# qu'elle porte deux niveaux ou dix.
	_v.v(carte.colonnes_sculptees() == 2,
		"%d colonnes stockees pour deux colonnes sculptees" % carte.colonnes_sculptees())

	# ET LE DEFAUT RESTE GRATUIT : reposer le masque du defaut sort du stockage.
	carte.poser_masque(grotte, carte.masque_de_base())
	_v.v(carte.colonnes_sculptees() == 1,
		"une colonne remise au defaut reste stockee")

func _emprise_et_sommet() -> void:
	var carte: Resource = CarteTerrain.new()
	if carte == null:
		_v.v(false, "carte_terrain.gd ne s'instancie pas")
		return
	carte.demi_cote = EMPRISE_LIVREE

	var base: int = carte.sommet_de_base()
	_v.v(base == carte.couche_base + carte.couches_pleines - 1,
		"le sommet par defaut ne vaut pas la derniere couche pleine")

	# Les quatre coins DEDANS, et leurs voisins immediats DEHORS : c'est la
	# frontiere qui casse, jamais le milieu.
	var dedans: Array[Vector2i] = [
		Vector2i(-EMPRISE_LIVREE, -EMPRISE_LIVREE),
		Vector2i(EMPRISE_LIVREE - 1, EMPRISE_LIVREE - 1),
		Vector2i(-EMPRISE_LIVREE, EMPRISE_LIVREE - 1),
		Vector2i(0, 0),
	]
	for colonne in dedans:
		_v.v(carte.dans_emprise(colonne), "colonne %v rejetee de l'emprise" % colonne)
		_v.v(carte.sommet_max_colonne(colonne) == base,
			"colonne %v : sommet %s, %d attendu" % [colonne, carte.sommet_max_colonne(colonne), base])

	var dehors: Array[Vector2i] = [
		Vector2i(-EMPRISE_LIVREE - 1, 0),
		Vector2i(EMPRISE_LIVREE, 0),
		Vector2i(0, -EMPRISE_LIVREE - 1),
		Vector2i(0, EMPRISE_LIVREE),
	]
	for colonne in dehors:
		_v.v(not carte.dans_emprise(colonne), "colonne %v acceptee hors emprise" % colonne)
		_v.v(carte.sommet_max_colonne(colonne) == null,
			"colonne %v hors emprise rend un sommet au lieu de null" % colonne)

	var cellules: Array[Vector3i] = carte.cellules_de(Vector2i.ZERO)
	_v.v(cellules.size() == carte.couches_pleines,
		"une colonne vierge rend %d cellules, %d attendu" % [cellules.size(), carte.couches_pleines])
	if not cellules.is_empty():
		_v.v(cellules[cellules.size() - 1] == Vector3i(0, base, 0),
			"la derniere cellule d'une colonne vierge n'est pas son sommet")
	_v.v(carte.cellules_de(Vector2i(EMPRISE_LIVREE, 0)).is_empty(),
		"une colonne hors emprise rend des cellules")

func _sculpture() -> void:
	var carte: Resource = CarteTerrain.new()
	carte.demi_cote = 150
	var base: int = carte.sommet_de_base()
	var colonne := Vector2i(12, -34)

	_v.v(carte.sculpter(colonne, base + 3), "sculpter dans l'emprise a echoue")
	_v.v(carte.sommet_max_colonne(colonne) == base + 3, "le sommet sculpte n'est pas relu")
	_v.v(carte.colonnes_sculptees() == 1,
		"%d colonnes stockees apres une sculpture" % carte.colonnes_sculptees())
	_v.v(carte.cellules_de(colonne).size() == carte.couches_pleines + 3,
		"une colonne montee de 3 ne rend pas 3 cellules de plus")

	# Remise au defaut : le stockage doit se VIDER, pas garder une entree egale
	# au defaut.
	_v.v(carte.sculpter(colonne, base), "remettre une colonne au defaut a echoue")
	_v.v(carte.colonnes_sculptees() == 0,
		"une colonne remise au defaut reste stockee (%d)" % carte.colonnes_sculptees())
	_v.v(carte.sommet_max_colonne(colonne) == base, "une colonne remise au defaut ne rend plus le defaut")

	# Creusee jusqu'au vide : plus de sommet, plus de cellules.
	_v.v(carte.sculpter(colonne, carte.couche_base - 1), "creuser jusqu'au vide a echoue")
	_v.v(carte.sommet_max_colonne(colonne) == null,
		"une colonne creusee jusqu'au vide rend %s au lieu de null" % carte.sommet_max_colonne(colonne))
	_v.v(carte.cellules_de(colonne).is_empty(), "une colonne vide rend des cellules")

	_v.v(not carte.sculpter(Vector2i(999, 0), base + 1), "sculpter hors emprise a ete accepte")

func _serialisation() -> void:
	var carte: Resource = CarteTerrain.new()
	carte.demi_cote = EMPRISE_LIVREE
	var base: int = carte.sommet_de_base()
	var tirage := RandomNumberGenerator.new()
	tirage.seed = GRAINE
	var attendus: Dictionary = {}
	for i in range(200):
		var colonne := Vector2i(
			tirage.randi_range(-EMPRISE_LIVREE, EMPRISE_LIVREE - 1),
			tirage.randi_range(-EMPRISE_LIVREE, EMPRISE_LIVREE - 1))
		var couche := base + tirage.randi_range(1, 9)
		carte.sculpter(colonne, couche)
		attendus[colonne] = couche

	var chemin := "user://test_carte_terrain.tres"
	var erreur := ResourceSaver.save(carte, chemin)
	_v.v(erreur == OK, "ecriture de la carte d'essai impossible (erreur %d)" % erreur)
	if erreur != OK:
		return
	var relue: Resource = load(chemin)
	if relue == null:
		_v.v(false, "la carte d'essai ecrite ne se relit pas")
		return
	_v.v(relue.demi_cote == EMPRISE_LIVREE, "l'emprise ne survit pas a la relecture")
	_v.v(relue.colonnes_sculptees() == attendus.size(),
		"%d colonnes relues, %d ecrites" % [relue.colonnes_sculptees(), attendus.size()])
	var divergentes := 0
	for colonne in attendus:
		if relue.sommet_max_colonne(colonne) != attendus[colonne]:
			divergentes += 1
	_v.v(divergentes == 0, "%d colonnes ont un sommet different apres relecture" % divergentes)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(chemin))

func _cout_de_lecture() -> void:
	var vierge: Resource = CarteTerrain.new()
	vierge.demi_cote = EMPRISE_LIVREE
	var chargee: Resource = CarteTerrain.new()
	chargee.demi_cote = EMPRISE_LIVREE
	var base: int = chargee.sommet_de_base()

	var semeur := RandomNumberGenerator.new()
	semeur.seed = GRAINE
	for i in range(COLONNES_SCULPTEES):
		chargee.sculpter(Vector2i(
			semeur.randi_range(-EMPRISE_LIVREE, EMPRISE_LIVREE - 1),
			semeur.randi_range(-EMPRISE_LIVREE, EMPRISE_LIVREE - 1)), base + 2)

	# LE MEME TIRAGE POUR LES DEUX : deux tirages differents compareraient aussi
	# deux suites de colonnes, et le rapport ne voudrait plus rien dire.
	var colonnes: Array[Vector2i] = []
	var tireur := RandomNumberGenerator.new()
	tireur.seed = GRAINE + 1
	for i in range(LECTURES):
		colonnes.append(Vector2i(
			tireur.randi_range(-EMPRISE_LIVREE, EMPRISE_LIVREE - 1),
			tireur.randi_range(-EMPRISE_LIVREE, EMPRISE_LIVREE - 1)))

	var temps_vierge := _lire(vierge, colonnes)
	var temps_chargee := _lire(chargee, colonnes)
	var rapport := float(temps_chargee) / maxf(float(temps_vierge), 1.0)
	print("cout : %d lectures en %.1f ms sur carte vierge, %.1f ms sur %d colonnes sculptees (x%.2f)" % [
		LECTURES, temps_vierge / 1000.0, temps_chargee / 1000.0, COLONNES_SCULPTEES, rapport])
	_v.v(rapport <= RAPPORT_MAXIMAL,
		"lire coute %.2f fois plus cher sur une carte chargee : l'acces suit le stockage" % rapport)
	_v.v(chargee.colonnes_sculptees() <= COLONNES_SCULPTEES,
		"plus de colonnes stockees que de sculptures demandees")

func _lire(carte: Resource, colonnes: Array[Vector2i]) -> int:
	var debut := Time.get_ticks_usec()
	var somme := 0
	for colonne in colonnes:
		var haut: Variant = carte.sommet_max_colonne(colonne)
		if haut != null:
			somme += int(haut)
	# La somme est CONSOMMEE : sans usage, rien ne garantit que la boucle mesuree
	# ne soit pas allegee.
	if somme < 0:
		print("somme negative impossible : %d" % somme)
	return Time.get_ticks_usec() - debut

func _conclure() -> void:
	if _v.echecs() > 0:
		print("ECHEC: la donnee de terrain ne tient pas (%d)" % _v.echecs())
		quit(1)
		return
	print("OK: carte de terrain -- volume et non relief (grottes, ponts, niveaux separes), 100 km2 declares, carte vierge a poids nul, sculpture reversible, lecture a cout constant")
	quit(0)
