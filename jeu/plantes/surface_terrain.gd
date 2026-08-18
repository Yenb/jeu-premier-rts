extends RefCounted

# LE PONT entre le terrain AFFICHE et le terrain SIMULE, et rien d'autre.
#
# `SUIVI.md` tranche que le GridMap est un objet d'affichage et d'edition que la
# simulation ne lit pas, et que tout terrain lu par un mecanisme se modelise en
# cases. Ce fichier EST cette traduction : il ouvre le GridMap UNE FOIS, en tire
# un releve de cases, et le rend. Apres quoi plus personne ne touche au GridMap
# -- ni la reproduction, ni la mort, ni la recolte. Un seul fichier du jeu
# connait GridMap, c'est celui-ci.
#
# Entree : un GridMap deja peuple. Sortie : un releve, Dictionary { origine, pas,
# sommets, couche_reference }, ou `sommets` associe chaque colonne (Vector2i x/z)
# a la couche de sa cellule pleine la plus haute. LE PLAFOND N'EN FAIT PAS PARTIE :
# il depend de l'espece, et se demande a plafond_pour(). Tout le reste du fichier est
# constitue de lectures PURES sur ce releve, qui ne rouvrent jamais la grille.
#
# LE RELEVE EST AFFINE, ET C'EST CE QUI LE REND AUTONOME : map_to_local est une
# application affine de la cellule vers la position, l'origine et le pas
# suffisent donc a la rejouer entierement. Le CENTRAGE des cellules est un
# reglage du noeud (cell_center_x/y/z) et se retrouve tout entier dans
# l'origine relevee -- il n'est jamais recalcule ici, jamais suppose.
#
# TOUT VIT DANS LE REPERE LOCAL DU GRIDMAP, positions de plantes comprises.
# to_global est ECARTE : appele sur un noeud qui n'est pas encore dans l'arbre,
# il rend une matrice vide en poussant une erreur. Un porteur de plantes se pose
# donc en ENFANT du GridMap, et ses positions locales sont directement celles du
# releve.
#
# LES CASES N'ENTRENT PAS DANS LE MONDE, et c'est une decision de cout, jamais
# un oubli : monde.gd:choses_dans_rayon est un balayage LINEAIRE de toutes les
# choses enregistrees. Une carte de cette taille compte des dizaines de milliers
# de colonnes ; les y verser rendrait chaque requete de voisinage proportionnelle
# au terrain entier alors qu'elle ne cherche que des plantes. Le releve est un
# Dictionary indexe par colonne, lu en temps constant. Seules les plantes vivent
# dans le Monde.
#
# Regles tenues : positions en Vector3, jamais Vector2 -- une COLONNE est un
# Vector2i (x/z de la grille), ce qui n'est pas une position mais un index, et le
# releve rend toujours des Vector3 pour les positions. Aucun hasard. Aucun nom de
# contenu : ce fichier ne sait pas ce qui pousse sur les cases qu'il rend. Rien
# de scripts/, data/ ni addons/ n'est ecrit.

# Le releve d'un GridMap peuple.
#
# LE SOL LE PLUS BAS EST MESURE, JAMAIS SUPPOSE : c'est le minimum des sommets
# releves, donc une carte resculptee deplace le plafond d'elle-meme. Une colonne
# vide n'a aucun sommet et ne figure pas dans la table -- une plante n'y a rien
# sur quoi se poser, ce qui est un cas neutre et non une donnee cassee.
#
# LA CEINTURE DE LA CARTE MONTE HAUT et se releve comme tout le reste : ses
# colonnes se retrouvent tres au-dessus du plafond, donc non plantables, sans
# qu'une seule ligne n'ait a la connaitre.
static func relever(grille: GridMap) -> Dictionary:
	var sommets: Dictionary = {}
	for cellule in grille.get_used_cells():
		var colonne := Vector2i(cellule.x, cellule.z)
		if not sommets.has(colonne) or cellule.y > int(sommets[colonne]):
			sommets[colonne] = cellule.y

	var reference := 0
	var premier := true
	for colonne in sommets:
		var couche: int = int(sommets[colonne])
		if premier or couche < reference:
			reference = couche
			premier = false

	return {
		"origine": grille.map_to_local(Vector3i.ZERO),
		"pas": grille.cell_size,
		"sommets": sommets,
		"couche_reference": reference,
	}

# LE PLAFOND N'EST PLUS DANS LE RELEVE, ET C'EST CE QUI PERMET LE MULTI-ESPECE :
# chaque espece declare sa propre marge, l'arbre bas et l'herbe haut, sur le MEME
# terrain releve une seule fois. Un plafond range dans le releve n'en autoriserait
# qu'un pour toute la carte.
static func plafond_pour(releve: Dictionary, marge_couches: int) -> int:
	return int(releve.couche_reference) + marge_couches

# La colonne sous une position. Arrondi au plus proche : l'origine relevee est
# le CENTRE de la colonne (0,0), une position pile sur une frontiere retombe
# donc du cote de la colonne dont elle est le plus proche, jamais dans le vide.
static func colonne_de(position: Vector3, releve: Dictionary) -> Vector2i:
	var origine: Vector3 = releve.origine
	var pas: Vector3 = releve.pas
	return Vector2i(
		int(round((position.x - origine.x) / pas.x)),
		int(round((position.z - origine.z) / pas.z)))

# La couche du sommet d'une colonne, ou null quand la colonne est vide. Vector3i
# n'a pas de valeur « aucune » et un entier sentinelle serait pris pour une
# couche reelle par n'importe quel appelant : le retour est donc une Variant.
static func couche_de(colonne: Vector2i, releve: Dictionary) -> Variant:
	var sommets: Dictionary = releve.sommets
	if not sommets.has(colonne):
		return null
	return int(sommets[colonne])

# Une colonne est plantable si elle porte du terrain ET si ce terrain reste sous
# le plafond. Les deux conditions ensemble, jamais l'une puis l'autre : une
# colonne vide et une colonne trop haute sont deux refus differents, mais les
# deux sont des refus, et aucun appelant n'a besoin de les distinguer pour poser
# une plante. Ce qui les distingue sert ailleurs -- voir raison_de_refus.
static func est_plantable(colonne: Vector2i, releve: Dictionary, plafond: int) -> bool:
	var couche: Variant = couche_de(colonne, releve)
	return couche != null and int(couche) <= plafond

# Pourquoi une colonne n'est pas plantable, en une CLE -- jamais une phrase :
# l'appelant qui alarme compose son texte depuis des donnees (CLAUDE.md,
# INTERNATIONALISATION). Rend "" quand la colonne est plantable.
static func raison_de_refus(colonne: Vector2i, releve: Dictionary, plafond: int) -> String:
	var couche: Variant = couche_de(colonne, releve)
	if couche == null:
		return "colonne_vide"
	if int(couche) > plafond:
		return "couche_trop_haute"
	return ""

# La position ou se pose une plante sur une colonne : le DESSUS de la cellule
# sommet, pas son centre -- c'est la face sur laquelle une chose repose. Rend
# null quand la colonne est vide, pour la meme raison que couche_de.
static func position_posee(colonne: Vector2i, releve: Dictionary) -> Variant:
	var couche: Variant = couche_de(colonne, releve)
	if couche == null:
		return null
	var origine: Vector3 = releve.origine
	var pas: Vector3 = releve.pas
	return Vector3(
		origine.x + float(colonne.x) * pas.x,
		origine.y + float(couche) * pas.y + pas.y * 0.5,
		origine.z + float(colonne.y) * pas.z)

# Convertit une distance exprimee en CELLULES vers des metres. Le pas de la
# grille est un reglage du noeud, releve une fois : aucune taille de cellule
# n'apparait dans le code qui appelle.
static func metres_par_cellules(cellules: float, releve: Dictionary) -> float:
	return cellules * float((releve.pas as Vector3).x)
