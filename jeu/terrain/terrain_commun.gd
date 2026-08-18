extends RefCounted

# GESTES PARTAGES PAR LES OUTILS D'EDITEUR du terrain. Aucun etat, aucune
# propriete, rien a accrocher a un noeud : uniquement des fonctions statiques
# que chaque outil appelle. Il n'y a rien de specifique a un outil ici -- ce
# qui distingue le remplissage de la sculpture, c'est QUELLES cellules il
# designe, jamais la facon de les ecrire ni de retrouver le terrain.
#
# Entree : un noeud, une grille, une liste de cellules -- tout est passe en
# parametre, rien n'est devine. Sortie : le GridMap frere, l'identifiant du
# bloc, ou un compte d'ecriture.
#
# Regles tenues : positions en Vector3i (grille), jamais des Vector2. Les
# alarmes passent par push_error, visible dans le panneau de l'editeur, jamais
# un retour muet sur lequel l'appelant tomberait sans le savoir.

# Le terrain se cherche par TYPE parmi les freres du noeud, jamais par nom :
# renommer un noeud dans l'editeur ne doit casser aucun outil. Deux GridMap
# freres est une ambiguite -- on s'arrete et on le dit, on n'en choisit jamais
# un.
static func terrain_frere(noeud: Node) -> GridMap:
	var parent := noeud.get_parent()
	if parent == null:
		push_error("outil sans parent : le terrain se cherche parmi les freres")
		return null

	var trouves: Array[GridMap] = []
	for frere in parent.get_children():
		if frere is GridMap:
			trouves.append(frere)
	if trouves.is_empty():
		push_error("aucun GridMap parmi les freres de %s" % noeud.name)
		return null
	if trouves.size() > 1:
		push_error("%d GridMap parmi les freres de %s : l'outil ne choisit pas" % [
			trouves.size(), noeud.name])
		return null
	return trouves[0]

# Le PREMIER item de la bibliotheque, jamais l'identifiant 0 en dur : les
# identifiants d'une MeshLibrary ne sont tenus ni de commencer a zero ni de se
# suivre.
static func premier_bloc(grille: GridMap) -> int:
	var bibliotheque := grille.mesh_library
	if bibliotheque == null:
		push_error("le GridMap n'a aucune bibliotheque : rien a poser")
		return GridMap.INVALID_CELL_ITEM
	var items := bibliotheque.get_item_list()
	if items.is_empty():
		push_error("la bibliotheque du GridMap est vide : rien a poser")
		return GridMap.INVALID_CELL_ITEM
	return items[0]

# Ecrit les cellules d'indice [depuis, depuis + combien) d'une LISTE deja
# constituee, et rend { index, changees } : l'indice atteint, et le nombre de
# cellules dont l'etat a REELLEMENT change.
#
# UNE CELLULE DEJA DANS L'ETAT DEMANDE N'EST PAS REECRITE : le nombre de
# cellules parcourues ne dit rien de ce qui a bouge a l'ecran, et un rapport
# qui ne compte que le parcours fait chercher une panne la ou il n'y en a pas.
# Accessoirement, une cellule non reecrite ne salit pas son octant, donc ne le
# fait pas reconstruire.
static func ecrire_cellules(grille: GridMap, cellules: Array[Vector3i], bloc: int,
		depuis: int, combien: int) -> Dictionary:
	# Une tranche AVANCE toujours d'au moins une cellule : rendre l'indice recu
	# tel quel ferait tourner sans fin la boucle qui appelle.
	var index := clampi(depuis, 0, cellules.size())
	var fin := mini(index + maxi(combien, 1), cellules.size())
	var changees := 0
	while index < fin:
		var cellule := cellules[index]
		if grille.get_cell_item(cellule) != bloc:
			grille.set_cell_item(cellule, bloc)
			changees += 1
		index += 1
	return { "index": fin, "changees": changees }
