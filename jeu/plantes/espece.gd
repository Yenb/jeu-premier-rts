@tool
extends Node

# UNE ESPECE DE PLANTE : un noeud pose sous le Couvert, qui ne porte QUE les
# reglages de cette espece-la.
#
# UN NOEUD PLUTOT QU'UN FICHIER, et c'est le point : le game designer voit ses
# especes dans l'arbre de scene, les nomme, en clique une, et n'a sous les yeux
# que ce qui la concerne. Deux especes ne se melangent jamais dans le meme
# inspecteur. En ajouter une : dupliquer un noeud, changer les valeurs et le nom.
#
# CE FICHIER NE SIMULE RIEN et ne connait aucune espece. Il decrit ce qu'EST une
# espece, jamais laquelle -- aucun nom de contenu n'entre dans le code
# (CLAUDE.md, ADN). Il est LU par jeu/plantes/couvert.gd au lancement, jamais
# appele.
#
# AUCUNE VALEUR DERIVEE ICI. La duree de vie, les seuils cumules et le catalogue
# de reproduction se calculent dans vegetation.gd:preparer_depuis_champs -- un
# calcul range dans la donnee finirait par contredire la donnee qui le nourrit.
#
# TROIS STADES, ET C'EST DELIBERE. Des stades en nombre libre demanderaient une
# ressource imbriquee par stade, donc deux clics de plus pour lire une duree. Le
# jour ou une espece en reclame un quatrieme, c'est un champ de plus ici -- pas
# une refonte.
#
# Regles tenues : aucun texte joueur. Rien de scripts/, data/ ni addons/ n'est
# ecrit.

# Le nom sous lequel un semis reclame cette espece : c'est ce qu'on ecrit dans le
# champ `Type` d'un noeud Plante. Vide, l'espece est ignoree -- aucun semis ne
# pourrait la demander.
@export var nom: String = ""

@export_group("Stades")

# `duree` en secondes : LEUR SOMME EST LA DUREE DE VIE, il n'y a pas de champ
# separe qui pourrait la contredire. `stature` en metres : c'est ELLE que l'ombre
# compare, jamais le numero du stade -- entre deux especes un numero ne veut rien
# dire. `modele` vide = touffe fabriquee a l'execution, haute comme la stature.
@export var nom_stade_1: String = "pousse"
@export var duree_stade_1: float = 180.0
@export var stature_stade_1: float = 2.0
@export_file("*.glb", "*.tscn", "*.scn") var modele_stade_1: String = ""

@export var nom_stade_2: String = "mature"
@export var duree_stade_2: float = 240.0
@export var stature_stade_2: float = 7.5
@export_file("*.glb", "*.tscn", "*.scn") var modele_stade_2: String = ""

@export var nom_stade_3: String = "epuise"
@export var duree_stade_3: float = 180.0
@export var stature_stade_3: float = 5.0
@export_file("*.glb", "*.tscn", "*.scn") var modele_stade_3: String = ""

@export_group("Terrain")

# Combien de couches au-dessus du sol le plus bas de la carte cette espece
# supporte. C'est ce seul chiffre qui fait que le relief produit deux paysages.
@export var marge_couches: int = 2

# Combien de voisines un rejet supporte LA OU IL TOMBE. Bas, l'espece exige une
# vraie trouee et ne s'installe pas dans un tapis continu. Haut, elle s'etend dans
# le sien.
@export var trouee_max_voisins: int = 1

@export_group("Peuplement")

# OU TOMBENT LES REJETS, en cellules autour de la mere. C'est la CAPACITE DE
# DISPERSION, et elle appartient a l'espece : un arbre confie ses graines au vent
# ou aux animaux et essaime loin ; une herbe s'etend par ses stolons, donc juste a
# cote. Un anneau serre fait un tapis continu, un anneau large fait un semis
# clairseme -- deux paysages avec la meme mecanique.
@export var rayon_dispersion_min: int = 3
@export var rayon_dispersion_max: int = 5

# Combien de plantes vivantes, TOUTES ESPECES CONFONDUES, cette espece supporte
# autour d'elle avant de cesser de se reproduire. Haut, elle se serre et forme un
# tapis ; bas, elle s'espace. C'est ce qui borne la population : sans plafond,
# elle croit a chaque generation et ne se stabilise jamais.
#
# LE RAYON SUR LEQUEL ON COMPTE RESTE COMMUN (rayon_voisinage_cellules, sur le
# Couvert) : c'est l'echelle a laquelle le couvert regarde, pas un trait
# d'espece. Seul le SEUIL varie ici.
@export var max_voisins: int = 6

@export_group("Reproduction")

# Les deux bornes du stade fertile, comptees a partir de 1. DEUX BORNES ET NON
# UNE : un minimum seul laisserait une plante epuisee semer encore.
@export var stade_reproduction_min: int = 2
@export var stade_reproduction_max: int = 2

# Secondes entre deux pousses. IL DOIT TENIR PLUSIEURS FOIS DANS LA FENETRE
# FERTILE : une plante fertile a 25 s et morte a 100 s n'a que 75 s pour semer --
# un intervalle de 80 la rendrait sterile, verte a tous les tests de cycle.
@export var intervalle_reproduction: float = 240.0

@export_group("Production")

# Le premier stade qui produit, compte a partir de 1. AU-DELA DU DERNIER STADE,
# l'espece ne produit JAMAIS -- par la seule arithmetique, sans une branche dans
# le code. C'est ainsi qu'une espece de couvert pur se declare.
@export var stade_production_min: int = 2
@export var intervalle_production: float = 120.0

# Combien de produits peuvent attendre au sol en meme temps. Un ENCOMBREMENT, pas
# un quota de vie : ramasser libere une place et la production repart.
@export var max_produits_par_plante: int = 3

# De combien l'intervalle s'allonge au dernier stade.
@export var ralentissement_dernier_stade: float = 2.0

# Combien de temps un produit non ramasse reste au sol.
@export var duree_vie_produit: float = 300.0

# La CLE de ressource rendue au colon -- jamais un texte joueur (CLAUDE.md,
# INTERNATIONALISATION).
@export var ressource: String = ""

@export_file("*.glb", "*.tscn", "*.scn") var modele_produit: String = ""

@export_group("Apparence")

# La couleur des touffes fabriquees pour les stades qui ne declarent aucun modele.
@export var couleur: Color = Color(0.38, 0.68, 0.28)

# Les reglages, ramasses en un Dictionary. C'est la SEULE chose que ce noeud rend,
# et la seule que couvert.gd lui demande.
func champs() -> Dictionary:
	return {
		"noms_stades": [nom_stade_1, nom_stade_2, nom_stade_3],
		"durees_stades": [duree_stade_1, duree_stade_2, duree_stade_3],
		"statures_stades": [stature_stade_1, stature_stade_2, stature_stade_3],
		"modeles_stades": [modele_stade_1, modele_stade_2, modele_stade_3],
		"marge_couches": marge_couches,
		"trouee_max_voisins": trouee_max_voisins,
		"rayon_dispersion_min": rayon_dispersion_min,
		"rayon_dispersion_max": rayon_dispersion_max,
		"max_voisins": max_voisins,
		"stade_reproduction_min": stade_reproduction_min,
		"stade_reproduction_max": stade_reproduction_max,
		"intervalle_reproduction": intervalle_reproduction,
		"stade_production_min": stade_production_min,
		"intervalle_production": intervalle_production,
		"max_produits_par_plante": max_produits_par_plante,
		"ralentissement_dernier_stade": ralentissement_dernier_stade,
		"duree_vie_produit": duree_vie_produit,
		"ressource": ressource,
		"modele_produit": modele_produit,
		"couleur": couleur,
	}

# AVERTISSEMENT D'EDITEUR : une espece sans nom ne peut etre reclamee par aucun
# semis, et une duree nulle fige la plante a son premier stade pour toujours.
func _get_configuration_warnings() -> PackedStringArray:
	var alertes := PackedStringArray()
	if nom == "":
		alertes.append("Cette espece n'a pas de nom : aucun semis ne peut la reclamer.")
	if duree_stade_1 <= 0.0 or duree_stade_2 <= 0.0 or duree_stade_3 <= 0.0:
		alertes.append("Un stade a une duree nulle ou negative : la plante s'y figerait.")
	return alertes
