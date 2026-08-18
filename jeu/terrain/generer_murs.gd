extends SceneTree

# Lancement :
# godot --headless --script jeu/terrain/generer_murs.gd
#
# OUTIL D'ECHAFAUDAGE, lance a la main. Il REECRIT res://jeu/terrain/carte.tscn
# et rend la main ; le jeu ne l'appelle jamais, rien ne le charge au demarrage.
# Son seul role : ceinturer le terrain d'un mur d'une cellule d'epaisseur, UNE
# CELLULE AU-DELA de l'emprise sculptable, pour qu'aucun corps physique ne
# quitte le plateau par le bord.
#
# Entree : res://jeu/terrain/carte.tscn, lue sur le disque, et l'emprise lue
# chez le generateur. Aucune donnee, aucun argument.
# Sortie : la meme scene, reecrite avec les cellules de bordure. Code de sortie
# 0 sur VERT, 1 sur ROUGE.
#
# IL NE TOUCHE AUCUNE CELLULE DE L'EMPRISE SCULPTEE. La ceinture est HORS
# emprise par construction, et le compte des cellules de l'emprise est releve
# avant puis apres pour le PROUVER, jamais seulement l'affirmer -- ce que porte
# ce fichier est un travail a la souris qu'aucun autre fichier ne double.
#
# IL SE RELIT SUR LE DISQUE AVANT DE CONCLURE. Une scene mise en paquet peut
# perdre en silence ce qui n'appartient a personne (un noeud sans owner
# disparait au pack, sans erreur) : le verdict porte sur le FICHIER RELU, jamais
# sur l'objet qui vient d'etre construit en memoire.
#
# RELANCABLE SANS DEGAT : une cellule deja dans l'etat demande n'est pas
# reecrite (voir terrain_commun.gd). Un second lancement annonce zero
# changement, il ne double ni n'efface rien -- pas de garde-fou a lever, pas de
# « forcer » a passer.
#
# LES MURS SONT INVISIBLES ET SOLIDES : ils portent l'item de la bibliotheque
# qui a une forme de collision et AUCUN maillage (bloc.tres, item/1). Rien a
# rendre, donc rien a voir -- une limite de carte, pas un decor.
#
# UN MAILLAGE A ALPHA ZERO EST ECARTE : il coute une passe de transparence sur
# chaque cellule de la ceinture, pour un resultat que l'absence de maillage
# obtient a cout nul.
#
# L'ITEM SE RECONNAIT A SES PROPRIETES, jamais a son nom : « celui qui collisionne
# sans se rendre », pas « celui qui s'appelle limite ». Renommer un item dans la
# bibliotheque ne doit casser aucun outil -- meme raison qui fait chercher le
# terrain par TYPE dans terrain_commun.gd.
#
# Regles tenues : positions en Vector3i (grille), jamais des Vector2. Aucun
# hasard. Les prints sont des traces de mise au point, pas du texte joueur. Rien
# de scripts/, data/ ni addons/ n'est lu ni ecrit.

const Generateur = preload("res://jeu/terrain/generer_carte.gd")
const Commun = preload("res://jeu/terrain/terrain_commun.gd")

const CHEMIN_SCENE := "res://jeu/terrain/carte.tscn"
const NOM_TERRAIN := "Terrain"

# Hauteur du mur, en couches, depuis la base du terrain. C'est une decision de
# jeu : assez haut pour qu'aucune unite ne franchisse le bord, et rien dans le
# moteur ne la fait respecter -- GridMap n'impose aucune borne en hauteur.
const COUCHES_MURS := 22

func _init() -> void:
	var paquet := load(CHEMIN_SCENE) as PackedScene
	if paquet == null:
		print("ROUGE: %s introuvable ou illisible" % CHEMIN_SCENE)
		quit(1)
		return

	var racine := paquet.instantiate() as Node3D
	if racine == null:
		print("ROUGE: la racine de %s n'est pas un Node3D" % CHEMIN_SCENE)
		quit(1)
		return

	var grille := racine.get_node_or_null(NOM_TERRAIN) as GridMap
	if grille == null:
		print("ROUGE: aucun GridMap nomme %s sous la racine" % NOM_TERRAIN)
		racine.free()
		quit(1)
		return

	var bloc := bloc_solide_sans_maillage(grille)
	if bloc == GridMap.INVALID_CELL_ITEM:
		print("ROUGE: aucun item solide et sans maillage dans la bibliotheque : " +
			"la ceinture serait visible, ou traversable")
		racine.free()
		quit(1)
		return

	var emprise_avant := _compter_emprise(grille)
	var noeuds_avant := _noms_des_noeuds(racine)

	var ceinture := cellules_de_ceinture(Generateur.DEMI_COTE, Generateur.COUCHE_BASE, COUCHES_MURS)
	var ecriture := Commun.ecrire_cellules(grille, ceinture, bloc, 0, ceinture.size())
	print("ceinture : %d cellules designees, %d posees (les autres l'etaient deja)" % [
		ceinture.size(), ecriture["changees"]])

	var paquet_neuf := PackedScene.new()
	var erreur := paquet_neuf.pack(racine)
	if erreur != OK:
		print("ROUGE: mise en paquet de la scene impossible (erreur %d)" % erreur)
		racine.free()
		quit(1)
		return
	erreur = ResourceSaver.save(paquet_neuf, CHEMIN_SCENE)
	if erreur != OK:
		print("ROUGE: ecriture de %s impossible (erreur %d)" % [CHEMIN_SCENE, erreur])
		racine.free()
		quit(1)
		return
	# Les noeuds construits hors arbre ne sont liberes par personne : sans ce
	# free, Godot annonce des centaines de RID fuites a la sortie et le vrai
	# resultat se perd dedans.
	racine.free()
	print("Ecrit : %s" % CHEMIN_SCENE)

	if not _relu_et_conforme(emprise_avant, noeuds_avant, ceinture, bloc):
		quit(1)
		return
	print("VERT: ceinture de %d couches posee sur les quatre bords, emprise sculptee intacte" %
		COUCHES_MURS)
	quit(0)

# L'item qui COLLISIONNE SANS SE RENDRE : une forme de collision, pas de
# maillage. C'est ce couple de proprietes qui fait une limite de carte, jamais un
# nom ni un identifiant ecrit en clair -- l'ordre des identifiants d'une
# MeshLibrary n'est garanti par rien.
#
# DEUX CANDIDATS EST UNE AMBIGUITE : on s'arrete et on le dit, on n'en choisit
# jamais un -- meme doctrine que terrain_commun.terrain_frere.
static func bloc_solide_sans_maillage(grille: GridMap) -> int:
	var bibliotheque := grille.mesh_library
	if bibliotheque == null:
		push_error("le GridMap n'a aucune bibliotheque : rien a poser")
		return GridMap.INVALID_CELL_ITEM

	var trouves: Array[int] = []
	for item in bibliotheque.get_item_list():
		if bibliotheque.get_item_mesh(item) == null \
				and not bibliotheque.get_item_shapes(item).is_empty():
			trouves.append(item)
	if trouves.is_empty():
		push_error("aucun item solide et sans maillage dans la bibliotheque")
		return GridMap.INVALID_CELL_ITEM
	if trouves.size() > 1:
		push_error("%d items solides sans maillage : l'outil ne choisit pas" % trouves.size())
		return GridMap.INVALID_CELL_ITEM
	return trouves[0]

# Les cellules du POURTOUR d'un carre qui depasse l'emprise d'une cellule sur
# les quatre cotes, repetees sur chaque couche. L'emprise occupe
# [-demi_cote, demi_cote - 1] : la ceinture est donc a -demi_cote - 1 et
# +demi_cote, jamais un nombre ecrit en clair -- l'emprise se lit chez le
# generateur, deux nombres qui doivent s'accorder finissent par diverger.
#
# UN SEUL ANNEAU CALCULE, puis recopie couche par couche : parcourir le carre
# plein a chaque couche pour n'en garder que le bord ferait 130 x 130 x 22
# essais la ou l'anneau en compte 516.
static func cellules_de_ceinture(demi_cote: int, couche_base: int, couches: int) -> Array[Vector3i]:
	var bas := -demi_cote - 1
	var haut := demi_cote
	var anneau: Array[Vector2i] = []
	# Les deux cotes en z sur toute la largeur, puis les deux cotes en x SANS
	# leurs extremites : les quatre coins appartiennent aux premiers, les
	# reprendre les poserait deux fois.
	for x in range(bas, haut + 1):
		anneau.append(Vector2i(x, bas))
		anneau.append(Vector2i(x, haut))
	for z in range(bas + 1, haut):
		anneau.append(Vector2i(bas, z))
		anneau.append(Vector2i(haut, z))

	var cellules: Array[Vector3i] = []
	for y in range(couche_base, couche_base + couches):
		for colonne in anneau:
			cellules.append(Vector3i(colonne.x, y, colonne.y))
	return cellules

# Combien de cellules pleines DANS l'emprise sculptable. Sert de temoin : ce
# nombre ne doit pas bouger d'une cellule.
static func compter_dans_emprise(grille: GridMap, demi_cote: int) -> int:
	var compte := 0
	for cellule in grille.get_used_cells():
		if cellule.x >= -demi_cote and cellule.x < demi_cote \
				and cellule.z >= -demi_cote and cellule.z < demi_cote:
			compte += 1
	return compte

func _compter_emprise(grille: GridMap) -> int:
	return compter_dans_emprise(grille, Generateur.DEMI_COTE)

func _noms_des_noeuds(racine: Node) -> Array[String]:
	var noms: Array[String] = []
	for enfant in racine.get_children():
		noms.append(String(enfant.name))
	noms.sort()
	return noms

# Le verdict, sur le fichier RELU : la sculpture est intacte, la ceinture est
# bien la, et aucun noeud de la scene n'a disparu au passage.
func _relu_et_conforme(emprise_avant: int, noeuds_avant: Array[String],
		ceinture: Array[Vector3i], bloc: int) -> bool:
	# CACHE_MODE_IGNORE, jamais load() : la scene est deja dans le cache de
	# ressources depuis le debut de ce script, et load() rendrait cette copie
	# d'AVANT l'ecriture -- une relecture qui ne relit rien conclut que rien n'a
	# ete ecrit alors que le fichier est bon.
	var paquet := ResourceLoader.load(
		CHEMIN_SCENE, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if paquet == null:
		print("ROUGE: %s illisible apres ecriture" % CHEMIN_SCENE)
		return false
	var racine := paquet.instantiate() as Node3D
	if racine == null:
		print("ROUGE: la racine de %s n'est plus un Node3D apres ecriture" % CHEMIN_SCENE)
		return false

	var conforme := true
	var grille := racine.get_node_or_null(NOM_TERRAIN) as GridMap
	if grille == null:
		print("ROUGE: le GridMap %s a disparu de la scene reecrite" % NOM_TERRAIN)
		racine.free()
		return false

	var emprise_apres := _compter_emprise(grille)
	if emprise_apres != emprise_avant:
		print("ROUGE: l'emprise sculptee porte %d cellules au lieu de %d" % [
			emprise_apres, emprise_avant])
		conforme = false

	var manquantes := 0
	for cellule in ceinture:
		if grille.get_cell_item(cellule) != bloc:
			manquantes += 1
	if manquantes > 0:
		print("ROUGE: %d cellules de ceinture sur %d absentes du fichier relu" % [
			manquantes, ceinture.size()])
		conforme = false

	var noeuds_apres := _noms_des_noeuds(racine)
	if noeuds_apres != noeuds_avant:
		print("ROUGE: les noeuds de la scene ont change : %s au lieu de %s" % [
			noeuds_apres, noeuds_avant])
		conforme = false

	print("relu : %d cellules dans l'emprise (inchangees), %d en ceinture, noeuds %s" % [
		emprise_apres, ceinture.size(), noeuds_apres])
	racine.free()
	return conforme
