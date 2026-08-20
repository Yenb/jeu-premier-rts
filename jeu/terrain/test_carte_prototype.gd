extends SceneTree

# Test manuel :
# godot --headless --script jeu/terrain/test_carte_prototype.gd
#
# Verrouille le CABLAGE de res://jeu/terrain/carte_prototype.tscn -- pas la
# mecanique, qui a ses propres tests, mais ce qu'un fichier de scene perd en
# silence, et ce que la ceinture de murs ajoute ici :
# - le terrain porte la carte de 100 x 100 colonnes, et la scene ne porte aucun
#   relief : la carte est la seule verite ;
# - le personnage est dans le GROUPE que le terrain interroge. Sans ce lien le
#   disque se pose autour de l'origine et n'en bouge plus, ce qui ressemble a un
#   terrain qui marche ;
# - APRES UNE IMAGE, le terrain porte exactement le disque attendu. Une scene
#   qui se charge sans rien poser est le faux vert de ce chantier ;
# - LA CEINTURE EST POSEE, INVISIBLE ET SOLIDE : son item a une forme de
#   collision et aucun maillage. Un mur qui se verrait, ou qu'on traverse, passe
#   sans broncher tout jugement qui se contente de compter des cellules ;
# - ELLE EST HORS DE L'EMPRISE, sur les quatre bords, et son compte est celui de
#   l'anneau -- pas une cellule de plus, sinon elle deborderait sur ce qui se
#   sculpte ;
# - ELLE VIT DANS SON PROPRE GRIDMAP, QUI N'EST PAS FRERE DU TERRAIN. Deux
#   GridMap freres et les outils d'edition refusent de choisir (voir
#   terrain_commun.terrain_frere) : la scene ne se sculpterait plus ;
# - UN CORPS POUSSE VERS LE BORD EST ARRETE. C'est le seul jugement qui prouve
#   la ceinture par ce qu'elle FAIT, et pas par ce qu'elle contient ;
# - LES OUTILS DE SCULPTURE VISENT CETTE CARTE-CI : chacun retrouve le terrain
#   parmi ses freres et lit l'emprise sur la carte, la fenetre couvre toute
#   l'emprise d'un seul chargement, et la vue d'ensemble est branchee. Leur
#   presence dans la scene ne prouve aucun de ces liens ;
# - LE COUVERT VEGETAL POUSSE, et il releve la CARTE : un terrain rendu par
#   morceaux ne porte aucune cellule quand le couvert s'eveille.
#
# Entree : la scene sur le disque, instanciee et poussee dans l'arbre. Sortie :
# une ligne « OK: » et le code 0 si tout tient, « ECHEC: » et le code 1 sinon.
#
# LA SCENE EST RELUE SUR LE DISQUE, jamais construite ici : ce qui est verrouille
# est le FICHIER, y compris ce qu'il perd au chargement.
#
# Regles tenues : positions en Vector3, jamais Vector2 -- une COLONNE est un
# Vector2i, un index et pas une position. Aucun hasard. Les prints sont des
# traces de mise au point, pas du texte joueur. Rien de scripts/, data/ ni
# documents/ n'est ecrit.

const Verif = preload("res://scripts/verif.gd")
const TerrainVisible = preload("res://jeu/terrain/terrain_visible.gd")
const Commun = preload("res://jeu/terrain/terrain_commun.gd")
const Vegetation = preload("res://jeu/plantes/vegetation.gd")

const CHEMIN_SCENE := "res://jeu/terrain/carte_prototype.tscn"

# Ce que la carte prototype declare.
const DEMI_COTE_ATTENDU := 50
const COLONNES_ATTENDUES := 10000

# Combien d'images de physique laisser au corps d'essai pour atteindre le bord,
# et a quelle vitesse on le pousse.
const IMAGES_DE_POUSSEE := 240
const VITESSE_DE_POUSSEE := 20.0

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
	if terrain.carte == null:
		_v.v(false, "le terrain ne porte aucune carte")
		_conclure(racine)
		return
	var carte: Resource = terrain.carte
	_v.v(carte.demi_cote == DEMI_COTE_ATTENDU,
		"la carte declare un demi-cote de %d, %d attendu" % [
			carte.demi_cote, DEMI_COTE_ATTENDU])
	_v.v(carte.colonnes() == COLONNES_ATTENDUES,
		"la carte porte %d colonnes, %d attendues" % [
			carte.colonnes(), COLONNES_ATTENDUES])

	# LES OUTILS D'EDITION NE DOIVENT PAS TROUVER DEUX GRIDMAP FRERES.
	var freres := 0
	for enfant in racine.get_children():
		if enfant is GridMap:
			freres += 1
	_v.v(freres == 1,
		"%d GridMap freres sous la racine : les outils d'edition refuseraient de choisir" % freres)

	var personnage := racine.get_node_or_null("Personnage") as Node3D
	if personnage == null:
		_v.v(false, "aucun Personnage sous la racine")
		_conclure(racine)
		return
	_v.v(personnage.is_in_group(terrain.groupe_observateur),
		"le personnage n'est pas dans le groupe « %s » : le terrain ne le suivra pas" % terrain.groupe_observateur)

	var murs := racine.get_node_or_null("Limites/Murs") as GridMap
	if murs == null:
		_v.v(false, "aucun GridMap nomme Limites/Murs : la carte n'a aucun bord")
		_conclure(racine)
		return

	_les_outils_sculptent_cette_carte(racine, terrain, carte)

	await process_frame

	# CE QUE LA CARTE DECRIT DANS LE DISQUE, jamais un terrain suppose plat : la
	# carte se sculpte, et un compte calcule sur le defaut finirait par mesurer
	# le travail du sculpteur au lieu du rendu.
	var posees := terrain.get_used_cells().size()
	var attendu := TerrainVisible.colonnes_du_disque(Vector2i.ZERO, terrain.rayon_cellules)
	var cellules_dues := 0
	for colonne in attendu:
		if carte.dans_emprise(colonne):
			cellules_dues += (carte.cellules_de(colonne) as Array).size()
	_v.v(posees == cellules_dues,
		"%d cellules posees par le terrain, %d decrites par la carte sur les %d colonnes du disque" % [
			posees, cellules_dues, attendu.size()])

	# LA CEINTURE, CELLULE PAR CELLULE.
	var cellules_murs := murs.get_used_cells()
	_v.v(not cellules_murs.is_empty(),
		"la ceinture n'a pose aucune cellule : rien n'arrete au bord")
	if cellules_murs.is_empty():
		_conclure(racine)
		return

	# L'anneau depasse l'emprise d'une cellule sur les quatre cotes : son cote
	# vaut 2 x demi_cote + 2 colonnes, et les quatre coins ne se comptent
	# qu'une fois.
	var anneau: int = 4 * (2 * carte.demi_cote + 2) - 4
	_v.v(cellules_murs.size() == anneau * murs.couches,
		"la ceinture porte %d cellules, %d attendues (%d colonnes de %d couches)" % [
			cellules_murs.size(), anneau * murs.couches, anneau, murs.couches])

	var dedans := 0
	var sur_le_bord := 0
	for cellule in cellules_murs:
		if carte.dans_emprise(Vector2i(cellule.x, cellule.z)):
			dedans += 1
		if cellule.x == -carte.demi_cote - 1 or cellule.x == carte.demi_cote \
				or cellule.z == -carte.demi_cote - 1 or cellule.z == carte.demi_cote:
			sur_le_bord += 1
	_v.v(dedans == 0,
		"%d cellules de ceinture tombent DANS l'emprise sculptable" % dedans)
	_v.v(sur_le_bord == cellules_murs.size(),
		"%d cellules de ceinture ne sont sur aucun des quatre bords" % (
			cellules_murs.size() - sur_le_bord))

	# INVISIBLE ET SOLIDE : les deux ensemble, jamais l'une puis l'autre.
	var item := murs.get_cell_item(cellules_murs[0])
	var bibliotheque := murs.mesh_library
	_v.v(bibliotheque != null and bibliotheque.get_item_mesh(item) == null,
		"l'item de la ceinture porte un maillage : les murs se verraient")
	_v.v(bibliotheque != null and not bibliotheque.get_item_shapes(item).is_empty(),
		"l'item de la ceinture n'a aucune forme de collision : on traverserait le bord")

	var arete: float = carte.cote
	_v.v(murs.cell_size.is_equal_approx(Vector3(arete, arete, arete)),
		"la ceinture a des cellules de %v alors que la carte declare %.3f" % [
			murs.cell_size, arete])

	await _les_objets_basculent(racine, personnage)
	_le_couvert_pousse(racine)

	await physics_frame
	await _le_bord_arrete(racine, carte)

	print("prototype : carte de %d x %d colonnes (%.0f m de cote, %.3f km²), %d cellules posees autour du personnage" % [
		carte.demi_cote * 2, carte.demi_cote * 2, carte.metres(),
		carte.superficie_km2(), posees])
	print("            ceinture de %d cellules sur %d couches, hors emprise sur les quatre bords" % [
		cellules_murs.size(), murs.couches])
	_conclure(racine)

# LE COUVERT POUSSE SUR UN TERRAIN QUI N'EST RENDU QUE PAR MORCEAUX. Ce qui le
# rend possible est la SOURCE de son releve : la carte, jamais les cellules --
# elles n'existent pas encore quand il s'eveille, et n'existeront jamais partout.
# Le jugement porte sur les deux ensemble : la source choisie, et des plantes
# reellement vivantes. La source seule ne dit pas qu'il pousse ; les plantes
# seules ne diraient pas pourquoi.
func _le_couvert_pousse(racine: Node3D) -> void:
	var couvert := racine.get_node_or_null("Terrain/Couvert")
	if couvert == null:
		_v.v(false, "aucun Terrain/Couvert : rien ne pousse sur la carte prototype")
		return
	var releve: Dictionary = couvert.get("_releve")
	_v.v(releve.get("carte") != null,
		"le couvert a releve les cellules du terrain, qui n'en porte qu'un disque")

	var etat: Dictionary = couvert.get("_etat")
	if etat.is_empty():
		_v.v(false, "le couvert n'a aucun etat : aucun semis n'a ete releve")
		return
	var config: Dictionary = couvert.get("_config")
	var vivantes: Array = Vegetation.vivantes(etat.plantes, config)
	_v.v(vivantes.size() > 0, "aucune plante vivante sur la carte prototype")
	_v.v((etat.refus as Array).is_empty(),
		"des semis ont ete refuses : %s" % [etat.refus])

	# LE COUVERT NE DESSINE PLUS UNE PLANTE A LA FOIS. Trois choses ensemble :
	# aucune plante ne porte de maillage a elle, les lots portent exactement une
	# ligne par plante et par produit, et le compte de nœuds qui dessinent est
	# celui des LOTS -- pas celui de la population.
	var lots: Dictionary = couvert.lots()
	var lignes := 0
	for cle in lots:
		lignes += couvert.lignes_du_lot(String(cle))
	var produits: int = (etat.graines as Array).size()
	_v.v(lignes == vivantes.size() + produits,
		"%d lignes de lot pour %d plantes et %d produits" % [
			lignes, vivantes.size(), produits])

	var dessinateurs := 0
	var maillages_isoles := 0
	var a_visiter: Array = [couvert]
	while not a_visiter.is_empty():
		var noeud: Node = a_visiter.pop_back()
		if noeud is MultiMeshInstance3D:
			dessinateurs += 1
		elif noeud is MeshInstance3D:
			maillages_isoles += 1
		for enfant in noeud.get_children():
			a_visiter.append(enfant)
	_v.v(maillages_isoles == 0,
		"%d plantes portent encore leur propre maillage" % maillages_isoles)
	_v.v(dessinateurs < vivantes.size(),
		"%d nœuds dessinent pour %d plantes : le regroupement ne sert a rien" % [
			dessinateurs, vivantes.size()])
	print("            couvert : %d plante(s) vivante(s) + %d produit(s), dessines par %d nœud(s) en %d lot(s)" % [
		vivantes.size(), produits, dessinateurs, lots.size()])

# CE QUI EST SEME EN DONNEES BASCULE EN NŒUDS PRES DE L'OBSERVATEUR, et pas
# ailleurs. Trois choses ensemble, dont aucune ne se voit sans les deux autres :
# le semis a peuple un Monde, le montreur en a pose une PARTIE seulement, et
# tout ce qu'il a pose est dans son rayon. Un montreur qui poserait tout
# passerait les deux premiers jugements.
func _les_objets_basculent(racine: Node3D, personnage: Node3D) -> void:
	var semeur := racine.get_node_or_null("Semeur")
	var montreur := racine.get_node_or_null("Objets") as Node3D
	if semeur == null or montreur == null:
		_v.v(false, "la scene n'a pas de Semeur et de montreur d'Objets : rien a poser dessus")
		return
	if semeur.monde == null:
		_v.v(false, "le semis n'a donne aucun Monde au montreur : rien ne basculera jamais")
		return
	var semes: int = (semeur.monde.choses as Dictionary).size()
	_v.v(semes > 0, "aucun objet seme en donnees")

	# Le montreur travaille dans _process : il lui faut une image pour voir
	# l'observateur et poser ce qui l'entoure.
	await process_frame

	var montres: int = montreur.montres()
	_v.v(montres > 0, "%d objets semes, aucun n'a bascule en nœud" % semes)
	_v.v(montres < semes,
		"les %d objets semes sont TOUS poses : le rayon ne borne rien" % semes)

	var rayon: float = montreur.rayon_metres
	var trop_loin := 0
	for noeud in montreur.get_children():
		if noeud is Node3D:
			if noeud.global_position.distance_to(personnage.global_position) > rayon * 2.0:
				trop_loin += 1
	_v.v(trop_loin == 0,
		"%d objets poses sont a plus du double du rayon de l'observateur" % trop_loin)
	print("            %d objets semes en donnees, %d nœuds vivants dans un rayon de %.0f m" % [
		semes, montres, rayon])

# LES OUTILS DE SCULPTURE VISENT CETTE CARTE-CI, et c'est le seul jugement qui
# le dit : leur presence dans la scene ne prouve rien. Chacun cherche le terrain
# parmi ses freres et l'emprise sur la carte qu'un frere porte -- une scene ou
# l'un des deux liens manque laisse des outils d'allure normale qui sculptent a
# cote, ou qui ecretent a l'emprise par defaut.
#
# LA FENETRE COUVRE TOUTE L'EMPRISE. C'est ce qui distingue une carte
# prototype : elle se charge d'un seul geste, la ou une grande carte se sculpte
# fenetre par fenetre.
func _les_outils_sculptent_cette_carte(racine: Node3D, terrain: GridMap, carte: Resource) -> void:
	for nom in ["Fenetre", "Sculpteur", "Remplisseur"]:
		var outil := racine.get_node_or_null(nom) as Node3D
		if outil == null:
			_v.v(false, "aucun outil « %s » sous la racine : la carte ne se sculpte pas" % nom)
			continue
		_v.v(Commun.terrain_frere(outil) == terrain,
			"l'outil « %s » ne retrouve pas le terrain parmi ses freres" % nom)
		_v.v(Commun.emprise_fraternelle(outil, 0) == carte.demi_cote,
			"l'outil « %s » lit une emprise de %d, la carte en declare %d" % [
				nom, Commun.emprise_fraternelle(outil, 0), carte.demi_cote])

	var fenetre := racine.get_node_or_null("Fenetre") as Node3D
	if fenetre != null:
		_v.v(fenetre.carte == carte,
			"la fenetre de sculpture ne porte pas la carte du terrain : elle sculpterait ailleurs")
		_v.v(fenetre.demi_fenetre >= carte.demi_cote,
			"la fenetre couvre %d colonnes de demi-largeur, l'emprise en fait %d : la carte ne se charge pas d'un geste" % [
				fenetre.demi_fenetre, carte.demi_cote])

	var maquette := racine.get_node_or_null("Apercu/Maquette") as Node3D
	if maquette == null:
		_v.v(false, "aucune Apercu/Maquette : le sculpteur n'a aucune vue d'ensemble")
	else:
		_v.v(maquette.carte == carte,
			"la vue d'ensemble ne porte pas la carte du terrain")
	var repere := racine.get_node_or_null("Apercu/Repere") as MeshInstance3D
	if repere == null:
		_v.v(false, "aucun Apercu/Repere : rien ne montre ou la fenetre travaille")
	else:
		_v.v(repere.get_node_or_null(repere.outil_fenetre) == fenetre,
			"le repere ne pointe pas la fenetre de sculpture")
		_v.v(repere.get_node_or_null(repere.maquette) == maquette,
			"le repere ne pointe pas la vue d'ensemble")

# LE JUGEMENT QUI PROUVE LA CEINTURE PAR CE QU'ELLE FAIT : un corps pousse vers
# le bord ne le franchit pas. Compter des cellules ne dit rien de ce qui arrive
# a ce qui leur rentre dedans.
#
# LE CORPS EST NEUF, jamais le personnage de la scene : le deplacer le sortirait
# du disque pose, le terrain se rafraichirait sous lui, et deux mecaniques se
# melangeraient dans un seul jugement.
func _le_bord_arrete(racine: Node3D, carte: Resource) -> void:
	var corps := CharacterBody3D.new()
	var forme := CollisionShape3D.new()
	var boite := BoxShape3D.new()
	boite.size = Vector3(1.0, 1.0, 1.0)
	forme.shape = boite
	corps.add_child(forme)
	racine.add_child(corps)
	# Au-dessus du terrain plein, a une hauteur que la ceinture couvre.
	var bord: float = carte.metres() * 0.5
	corps.global_position = Vector3(
		bord - 10.0, float(carte.sommet_de_base() + 2) * carte.cote, 0.0)

	for i in range(IMAGES_DE_POUSSEE):
		corps.velocity = Vector3(VITESSE_DE_POUSSEE, 0.0, 0.0)
		corps.move_and_slide()
		await physics_frame

	var arrive := corps.global_position.x
	_v.v(arrive < bord,
		"pousse vers le bord, un corps est sorti a x = %.2f m (l'emprise s'arrete a %.2f m)" % [
			arrive, bord])
	corps.queue_free()

func _conclure(racine: Node) -> void:
	if racine != null:
		racine.queue_free()
	if _v.echecs() > 0:
		print("ECHEC: le cablage de la carte prototype ne tient pas (%d)" % _v.echecs())
		quit(1)
		return
	print("OK: carte prototype -- 100 x 100 colonnes en donnee, disque pose autour du personnage, ceinture invisible et solide hors emprise")
	quit(0)
