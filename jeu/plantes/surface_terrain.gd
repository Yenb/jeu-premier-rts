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
# Entree : un GridMap deja peuple, ou une CARTE de terrain. Sortie : un releve,
# Dictionary { origine, pas, sommets, couche_reference, carte }, ou `sommets`
# associe chaque colonne (Vector2i x/z) a la couche de sa cellule pleine la plus
# haute. LE PLAFOND N'EN FAIT PAS PARTIE : il depend de l'espece, et se demande a
# plafond_pour(). Tout le reste du fichier est constitue de lectures PURES sur ce
# releve, qui ne rouvrent jamais la grille.
#
# ---- DEUX SOURCES POSSIBLES, UNE SEULE A LA FOIS ----
# UN GRIDMAP PLEIN SE RELEVE CELLULE PAR CELLULE ; UNE CARTE SE LIT A LA DEMANDE.
# Les deux rendent le meme releve et repondent aux memes questions ; ce qui
# change est OU la hauteur est prise, et c'est tout ce que l'appelant a a
# choisir.
#
# LA CARTE EST LA SOURCE DES QUE LE TERRAIN EST RENDU PAR MORCEAUX. Un GridMap
# qui ne porte qu'un disque autour du joueur (voir jeu/terrain/
# terrain_visible.gd) ne dit rien du terrain ailleurs -- et il ne porte encore
# AUCUNE cellule au moment ou ses enfants s'eveillent, l'ordre des _ready allant
# des enfants vers le parent. Relever un tel GridMap rend un terrain vide : rien
# a planter, partout, definitivement.
#
# RIEN N'EST ENUMERE QUAND LA SOURCE EST UNE CARTE. `sommets` reste vide et
# chaque colonne se demande a la carte en temps constant : une emprise de vingt
# cinq millions de colonnes ne coute donc pas plus qu'une de dix mille. Seul le
# plancher du relief est cherche a l'avance, et il ne relit que les colonnes
# SCULPTEES -- la carte ne stocke que celles-la.
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
# un oubli. monde.gd range par case et son cout suit le RAYON, plus la
# population : y verser le terrain ne rendrait donc pas une requete
# proportionnelle a la carte entiere. Ce qu'elle paierait est autre chose et
# reste vrai -- une case-objet PAR COLONNE dans chacune des cases que le rayon
# touche, la ou une plante n'y cherche que des plantes et ou le terrain les
# depasse de plusieurs ordres. Le releve, lui, est un Dictionary indexe par
# colonne, lu en temps constant, sans aucun rayon a parcourir. Seules les
# plantes vivent dans le Monde.
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

	@warning_ignore("shadowed_variable_base_class")
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
		"carte": null,
	}

# Le releve d'une CARTE de terrain, pour un GridMap qui n'en porte qu'un morceau
# -- ou rien du tout.
#
# LA GRILLE EST ENCORE DEMANDEE, ET SEULEMENT POUR SON REPERE : l'origine et le
# pas sont des reglages du noeud (cell_size, cell_center_x/y/z) que rien ici ne
# recalcule ni ne suppose. Ce qui vient de la carte est la HAUTEUR, et rien
# d'autre. Une grille vide convient : map_to_local repond sans aucune cellule.
#
# L'ARETE DE LA CELLULE RESTE CELLE DE LA GRILLE, et la carte declare la sienne
# de son cote. jeu/terrain/terrain_visible.gd impose deja celle de la carte a la
# grille au demarrage : les deux s'accordent parce qu'une seule commande, pas
# parce qu'on les recopie ici.
#
# LE PLANCHER DU RELIEF NE RELIT QUE LES COLONNES SCULPTEES, plus le sommet par
# defaut -- que porte toute colonne non sculptee. Une colonne creusee jusqu'au
# vide ne compte pas : elle n'a aucun sommet, et l'inclure ferait plonger le
# plafond de toutes les especes a cause d'un seul trou.
static func relever_depuis_carte(grille: GridMap, carte: Resource) -> Dictionary:
	return {
		"origine": grille.map_to_local(Vector3i.ZERO),
		"pas": grille.cell_size,
		"sommets": {},
		"couche_reference": plancher_de_carte(carte),
		"carte": carte,
	}

# La couche la plus basse qu'un sommet atteint sur une carte.
#
# LE SOMMET SE DEMANDE A LA CARTE, jamais deduit de ce qu'elle stocke : depuis
# qu'une colonne porte le MASQUE de ses couches pleines et non sa hauteur, la
# valeur rangee n'est plus une couche. La lire comme telle donnerait des
# planchers absurdes -- un masque de sept couches vaut 127.
static func plancher_de_carte(carte: Resource) -> int:
	var volumes: Dictionary = carte.volumes
	# LE DEFAUT NE COMPTE QUE S'IL RESTE UNE COLONNE POUR LE PORTER : sur une
	# carte entierement sculptee, il ne decrit plus aucun endroit du terrain.
	@warning_ignore("shadowed_variable_base_class")
	var reference: int = carte.sommet_de_base()
	var premier: bool = volumes.size() < carte.colonnes()
	for colonne in volumes:
		var haut: Variant = carte.sommet(colonne)
		if haut == null:
			continue
		var couche: int = int(haut)
		if premier or couche < reference:
			reference = couche
			premier = false
	return reference

# Le releve porte-t-il du terrain ? Sans quoi rien ne peut y pousser, et
# l'appelant a mieux a faire que de deviner laquelle des deux sources il tient.
static func porte_du_terrain(releve: Dictionary) -> bool:
	if releve.get("carte") != null:
		return (releve.carte as Resource).colonnes() > 0
	return not (releve.sommets as Dictionary).is_empty()

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
#
# C'EST LE SEUL ENDROIT QUI SAIT D'OU VIENT LA HAUTEUR. Tout le reste du fichier
# passe par ici, et la carte rend deja null pour une colonne hors emprise comme
# pour une colonne creusee jusqu'au vide -- exactement les deux cas ou un GridMap
# n'a aucune cellule a montrer.
static func couche_de(colonne: Vector2i, releve: Dictionary) -> Variant:
	var carte = releve.get("carte")
	if carte != null:
		return carte.sommet(colonne)
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
