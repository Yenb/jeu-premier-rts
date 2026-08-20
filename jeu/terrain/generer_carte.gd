extends SceneTree

# Lancement :
# godot --headless --script jeu/terrain/generer_carte.gd
# godot --headless --script jeu/terrain/generer_carte.gd -- forcer
# godot --headless --script jeu/terrain/generer_carte.gd -- vers=res://jeu/terrain/autre.tscn
#
# OUTIL D'ECHAFAUDAGE, lance a la main. Il ECRIT deux fichiers et rend la
# main ; le jeu ne l'appelle jamais, rien ne le charge au demarrage. Son seul
# role : poser le terrain de depart que Yael sculpte ensuite A LA SOURIS dans
# l'editeur. Une fois la carte sculptee, ce script n'a plus rien a faire --
# c'est l'editeur qui devient l'outil, pas lui.
#
# Entree : aucune donnee, tout est dans les constantes ci-dessous. Deux
# arguments utilisateur reconnus, « forcer » et « vers=<chemin> ».
# Sortie : res://jeu/terrain/bloc.tres (la bibliotheque de blocs, ECRITE
# SEULEMENT SI ELLE MANQUE) et la scene demandee. Code de sortie 0 sur VERT, 1
# sur ROUGE.
#
# GARDE-FOU : sans « forcer », le script REFUSE d'ecrire si la scene existe
# deja. La ecrire, c'est effacer tout le relief sculpte a la main -- un travail
# qui ne vit que la, dans les cellules du GridMap, et qu'aucun autre fichier ne
# porte.
#
# « vers= » EST CE QUI PERMET UNE SECONDE CARTE. Sans lui, une carte de taille
# differente ne s'obtient qu'en ecrasant celle qui existe : le garde-fou
# ci-dessus n'a alors que deux reponses, refuser ou detruire.
#
# UNE BIBLIOTHEQUE DEJA SUR LE DISQUE N'EST JAMAIS REECRITE, elle est RELUE. Ce
# fichier ne sait construire qu'un item, le cube plein ; celle du depot en porte
# d'autres, ajoutes par des chantiers qui ne passent pas par ici -- une limite
# solide sans maillage, une rampe. Les reecrire les effacerait, et TOUTE cellule
# qui les porte deviendrait vide, dans cette scene comme dans les autres.
#
# CE QU'IL PRODUIT, et ce qu'il ne produit pas : un bloc PLEIN de sept
# couches. Sa face du dessus est la surface ; ce qu'il y a dessous est la
# matiere dans laquelle on creuse en jeu, et le relief se sculpte AU-DESSUS,
# sur les couches vides. Aucune forme de collision sur le bloc (le sculptage
# dans l'editeur n'en demande pas), aucune logique de jeu, aucun script
# accroche a la scene.
#
# LA VIGNETTE DE PALETTE EST UN APLAT DE COULEUR, jamais un rendu du cube :
# --headless n'a pas de rendu, rien ici ne peut photographier une geometrie.
# Sans vignette du tout, la palette du GridMap affiche des cases muettes ; avec
# cet aplat, l'item se voit et se clique. L'editeur regenere une vraie vignette
# si la bibliotheque est reexportee depuis une scene.
#
# Regles tenues : toutes les positions sont des Vector3, jamais des Vector2.
# Aucun hasard. Aucun texte visible par le joueur -- les prints sont des traces
# de mise au point, pas de l'interface. Rien de scripts/, data/ ni addons/
# n'est lu ni ecrit.

const Commun = preload("res://jeu/terrain/terrain_commun.gd")

const CHEMIN_BIBLIOTHEQUE := "res://jeu/terrain/bloc.tres"
const CHEMIN_SCENE := "res://jeu/terrain/carte.tscn"

# Ce qui, dans les arguments utilisateur, designe une autre destination.
const PREFIXE_VERS := "vers="

# Ce qui, dans les arguments utilisateur, designe une autre emprise. Voir
# DEMI_COTE : sans ce prefixe, une carte plus petite ou plus grande que celle
# de reference ne s'obtient qu'en changeant la constante, ce qui deplace
# l'emprise de TOUT -- outils de sculpture et ceinture compris -- pour toutes
# les cartes generees ici, pas seulement la nouvelle.
const PREFIXE_DEMI_COTE := "demi_cote="

# Arete du cube ET pas de la grille : les deux valent le meme nombre, sinon les
# blocs se chevauchent ou laissent des joints.
const COTE := 2.0

# 150 cellules de part et d'autre de l'origine = 300 de cote, soit 600 m. La
# carte est CENTREE sur l'origine du monde : le milieu du terrain est (0, 0, 0),
# pas un coin.
#
# CE NOMBRE EST LA SEULE DECLARATION DE L'EMPRISE. outil_sculpture.gd y ecrete sa
# boite, outil_remplissage.gd y borne sa couche, generer_murs.gd y pose sa
# ceinture : le monter ouvre le terrain pour les trois d'un coup, et le baisser
# laisserait hors emprise des cellules deja posees, que plus aucun outil
# n'atteindrait.
const DEMI_COTE := 150

# Le bloc plein occupe les couches COUCHE_BASE a COUCHE_BASE + COUCHES_PLEINES
# - 1. La derniere est la surface visible ; tout ce qui est au-dessus reste
# vide, c'est la que se sculpte le relief. GridMap n'impose AUCUNE borne en
# hauteur : la profondeur du bloc est une decision de jeu, ecrite ici, que rien
# dans le moteur ne fait respecter -- poser un cube dix couches plus haut
# marchera toujours.
const COUCHE_BASE := 0
const COUCHES_PLEINES := 7

const NOM_BLOC := "bloc"
const COULEUR_BLOC := Color(0.45, 0.36, 0.27)
# La vignette est un APLAT : 16 pixels de cote suffisent, la palette l'etire
# sans rien perdre. Chaque pixel s'ecrit en clair dans le .tres -- a 64 de
# cote, l'aplat pesait dix fois le reste du fichier.
const COTE_VIGNETTE := 16

const HAUTEUR_CAMERA := 200.0
const PORTEE_OMBRE := 400.0

# La destination lue dans les arguments utilisateur, ou le defaut. Statique et
# pure : elle ne lit ni la ligne de commande ni le disque, on la lui passe.
static func chemin_demande(arguments: PackedStringArray, defaut: String) -> String:
	for argument in arguments:
		if argument.begins_with(PREFIXE_VERS):
			var demande := argument.substr(PREFIXE_VERS.length()).strip_edges()
			if not demande.is_empty():
				return demande
	return defaut

# Meme geste que chemin_demande, pour un entier. Un argument illisible ou
# nul ou negatif est ignore plutot que de produire une carte vide ou
# retournee -- silencieusement se tromper de taille ne se voit qu'a l'ecran.
static func entier_demande(arguments: PackedStringArray, prefixe: String, defaut: int) -> int:
	for argument in arguments:
		if argument.begins_with(prefixe):
			var texte := argument.substr(prefixe.length()).strip_edges()
			if texte.is_valid_int() and texte.to_int() > 0:
				return texte.to_int()
	return defaut

func _init() -> void:
	var arguments := OS.get_cmdline_user_args()
	var chemin_scene := chemin_demande(arguments, CHEMIN_SCENE)
	var demi_cote := entier_demande(arguments, PREFIXE_DEMI_COTE, DEMI_COTE)

	if FileAccess.file_exists(chemin_scene) and not arguments.has("forcer"):
		print("ROUGE: %s existe deja. La regenerer EFFACERAIT le relief sculpte." % chemin_scene)
		print("       Relancer avec « -- forcer » si c'est bien ce qui est voulu.")
		quit(1)
		return

	var bibliotheque := _bibliotheque()
	if bibliotheque == null:
		quit(1)
		return

	var racine := _construire_scene(bibliotheque, demi_cote)
	var paquet := PackedScene.new()
	var erreur := paquet.pack(racine)
	if erreur != OK:
		print("ROUGE: mise en paquet de la scene impossible (erreur %d)" % erreur)
		quit(1)
		return
	erreur = ResourceSaver.save(paquet, chemin_scene)
	if erreur != OK:
		print("ROUGE: ecriture de %s impossible (erreur %d)" % [chemin_scene, erreur])
		quit(1)
		return

	var grille: GridMap = racine.get_node("Terrain")
	print("Ecrit : %s (%d cellules, %d x %d, couches %d a %d, cellule de %.1f m)" % [
		chemin_scene, grille.get_used_cells().size(),
		demi_cote * 2, demi_cote * 2,
		COUCHE_BASE, COUCHE_BASE + COUCHES_PLEINES - 1, COTE])
	# Les noeuds construits hors arbre ne sont liberes par personne : sans ce
	# free, Godot annonce des centaines de RID fuites a la sortie et le vrai
	# resultat se perd dedans.
	racine.free()
	print("VERT: terrain genere. Le sculptage se fait dans l'editeur, plus ici.")
	quit(0)

# CELLE DU DISQUE D'ABORD, la neuve seulement si elle manque. Voir l'en-tete :
# ce fichier ne sait construire qu'un item, celle du depot en porte d'autres, et
# les ecraser viderait toute cellule qui les porte, dans n'importe quelle scene.
func _bibliotheque() -> MeshLibrary:
	if FileAccess.file_exists(CHEMIN_BIBLIOTHEQUE):
		var existante := load(CHEMIN_BIBLIOTHEQUE) as MeshLibrary
		if existante == null:
			print("ROUGE: %s existe mais n'est pas une MeshLibrary" % CHEMIN_BIBLIOTHEQUE)
			return null
		print("Relu : %s (%d item(s), inchangee)" % [
			CHEMIN_BIBLIOTHEQUE, existante.get_item_list().size()])
		return existante

	var neuve := _construire_bibliotheque()
	var erreur := ResourceSaver.save(neuve, CHEMIN_BIBLIOTHEQUE)
	if erreur != OK:
		print("ROUGE: ecriture de %s impossible (erreur %d)" % [CHEMIN_BIBLIOTHEQUE, erreur])
		return null
	# Sans ce take_over_path, la bibliotheque n'a pas de chemin sur disque et la
	# scene l'embarquerait EN ENTIER au lieu de la referencer : deux copies, une
	# seule editable.
	neuve.take_over_path(CHEMIN_BIBLIOTHEQUE)
	print("Ecrit : %s (%d item)" % [CHEMIN_BIBLIOTHEQUE, neuve.get_item_list().size()])
	return neuve

# Un seul item : le cube plein. L'identifiant vaut 0 -- c'est lui que le
# GridMap pose dans chaque cellule.
func _construire_bibliotheque() -> MeshLibrary:
	var matiere := StandardMaterial3D.new()
	matiere.albedo_color = COULEUR_BLOC

	var cube := BoxMesh.new()
	cube.size = Vector3(COTE, COTE, COTE)
	cube.material = matiere

	var bibliotheque := MeshLibrary.new()
	var identifiant := bibliotheque.get_last_unused_item_id()
	bibliotheque.create_item(identifiant)
	bibliotheque.set_item_name(identifiant, NOM_BLOC)
	bibliotheque.set_item_mesh(identifiant, cube)
	bibliotheque.set_item_preview(identifiant, _vignette(COULEUR_BLOC))
	return bibliotheque

func _vignette(couleur: Color) -> ImageTexture:
	var image := Image.create(COTE_VIGNETTE, COTE_VIGNETTE, false, Image.FORMAT_RGBA8)
	image.fill(couleur)
	return ImageTexture.create_from_image(image)

func _construire_scene(bibliotheque: MeshLibrary, demi_cote: int) -> Node3D:
	var racine := Node3D.new()
	racine.name = "Carte"

	var grille := GridMap.new()
	grille.name = "Terrain"
	grille.cell_size = Vector3(COTE, COTE, COTE)
	grille.mesh_library = bibliotheque
	# LE PREMIER ITEM, jamais l'identifiant 0 en dur : les identifiants d'une
	# MeshLibrary ne sont tenus ni de commencer a zero ni de se suivre, et depuis
	# que la bibliotheque est RELUE ce fichier ne les choisit plus.
	var bloc := Commun.premier_bloc(grille)
	for y in range(COUCHE_BASE, COUCHE_BASE + COUCHES_PLEINES):
		for x in range(-demi_cote, demi_cote):
			for z in range(-demi_cote, demi_cote):
				grille.set_cell_item(Vector3i(x, y, z), bloc)
	racine.add_child(grille)

	# Plein axe vertical, regard vers le bas. A cette hauteur, les 128 cellules
	# de cote (256 m) tiennent dans le champ.
	var camera := Camera3D.new()
	camera.name = "Camera"
	camera.position = Vector3(0.0, HAUTEUR_CAMERA, 0.0)
	camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	camera.current = true
	racine.add_child(camera)

	# Lumiere RASANTE, pas verticale : vue du dessus, une lumiere d'aplomb
	# rendrait toutes les faces identiques et le relief illisible.
	var soleil := DirectionalLight3D.new()
	soleil.name = "Soleil"
	soleil.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	soleil.shadow_enabled = true
	soleil.directional_shadow_max_distance = PORTEE_OMBRE
	racine.add_child(soleil)

	# Sans lumiere ambiante, tout ce que le soleil ne touche pas est NOIR, pas
	# sombre : le ciel procedural sert de source ambiante, pas de decor.
	var ciel := Sky.new()
	ciel.sky_material = ProceduralSkyMaterial.new()
	var ambiance := Environment.new()
	ambiance.background_mode = Environment.BG_SKY
	ambiance.sky = ciel
	ambiance.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	var monde := WorldEnvironment.new()
	monde.name = "Ambiance"
	monde.environment = ambiance
	racine.add_child(monde)

	# Un noeud sans owner n'est PAS ecrit dans la scene : il disparait au pack,
	# sans erreur ni avertissement.
	for enfant in racine.get_children():
		enfant.owner = racine

	return racine
