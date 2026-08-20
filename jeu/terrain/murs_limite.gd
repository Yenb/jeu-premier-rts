extends GridMap

# LA CEINTURE DE LA CARTE : un mur d'une cellule d'epaisseur, UNE CELLULE
# AU-DELA de l'emprise, sur les quatre bords. Il n'existe que pour qu'aucun
# corps physique ne quitte le plateau ; il ne porte aucun relief et ne se
# sculpte pas.
#
# Entree : la carte, qui declare son emprise, sa couche de base et l'arete de sa
# cellule ; une hauteur en couches. Sortie : ses propres cellules, posees une
# fois a l'entree dans l'arbre.
#
# LES MURS SONT INVISIBLES ET SOLIDES : ils portent l'item de la bibliotheque
# qui a une forme de collision et AUCUN maillage. Rien a rendre, donc rien a
# voir -- une limite de carte, pas un decor. L'item se reconnait a ses
# proprietes, jamais a son nom.
#
# IL A SON PROPRE GRIDMAP, SEPARE DU TERRAIN, et ce n'est pas un rangement : le
# terrain rendu se VIDE au demarrage puis ne pose qu'un disque autour de
# l'observateur (voir terrain_visible.gd). Une ceinture posee dans ces
# cellules-la disparaitrait au lancement, puis a chaque fois que le joueur
# s'eloignerait. La ceinture ne bouge jamais : elle vit ailleurs.
#
# CE GRIDMAP N'EST PAS FRERE DES OUTILS D'EDITION. Les outils cherchent le
# terrain par TYPE parmi leurs freres et refusent de choisir entre deux GridMap
# (voir terrain_commun.terrain_frere) : la ceinture se range donc sous un noeud
# a part.
#
# LA SCENE NE PORTE AUCUNE DE SES CELLULES : elles se deduisent entierement de
# l'emprise de la carte, et deux emprises -- celle de la carte, celle des
# cellules enregistrees -- finiraient par diverger sans que rien ne rougisse.
# Meme regle que la fenetre de sculpture et la maquette.
#
# LA GEOMETRIE DE L'ANNEAU EST CELLE DE generer_murs.gd, empruntee et jamais
# recopiee : deux facons de placer une meme ceinture donneraient deux bords a un
# demi-cote d'ecart.
#
# IL NE TOURNE PAS DANS L'EDITEUR : la ceinture ne se voit pas, et des cellules
# posees a l'ouverture d'une scene finissent par etre enregistrees dedans.
#
# Regles tenues : positions en Vector3i (grille), jamais Vector2 -- une COLONNE
# est un Vector2i, un index et pas une position. Aucun hasard. Aucun texte
# visible par le joueur. Aucun nom de contenu. Rien de scripts/, data/ ni
# documents/ n'est lu ni ecrit.

const Commun = preload("res://jeu/terrain/terrain_commun.gd")
const Ceinture = preload("res://jeu/terrain/generer_murs.gd")

# La carte dont on ceinture l'emprise. Sans elle, rien n'est pose et le dit.
@export var carte: Resource

# Hauteur du mur, en couches, depuis la base du terrain. C'est une decision de
# jeu : assez haut pour qu'aucune unite ne franchisse le bord.
@export var couches: int = 22

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if carte == null:
		push_error("murs_limite sans carte : aucune emprise a ceinturer")
		return
	cell_size = Vector3(carte.cote, carte.cote, carte.cote)
	var bilan := poser(self, carte, couches)
	if bilan["cellules"] == 0:
		return
	print("murs_limite : %d cellules de ceinture posees autour de l'emprise %d" % [
		bilan["cellules"], carte.demi_cote])

# Pose la ceinture d'une carte dans une grille, et rend { cellules, item } :
# combien de cellules ont REELLEMENT change, et l'item pose.
#
# LA GRILLE EST VIDEE D'ABORD : appelee deux fois sur deux emprises differentes,
# elle laisserait sinon la premiere ceinture en place, a l'interieur de la
# seconde.
static func poser(grille: GridMap, source: Resource, hauteur: int) -> Dictionary:
	var item := Ceinture.bloc_solide_sans_maillage(grille)
	if item == GridMap.INVALID_CELL_ITEM:
		return { "cellules": 0, "item": item }
	grille.clear()
	var cellules := Ceinture.cellules_de_ceinture(
		source.demi_cote, source.couche_base, maxi(hauteur, 1))
	var ecriture := Commun.ecrire_cellules(grille, cellules, item, 0, cellules.size())
	return { "cellules": ecriture["changees"], "item": item }
