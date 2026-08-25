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
# JUSQU'A SIX STADES, dont les trois derniers optionnels. Chaque stade renseigne
# nom + duree + stature (+ modele) ; un stade au nom vide OU a duree nulle est
# ignore par champs(), l'espece ne le declare tout simplement pas. Une espece
# a trois stades reste identique a ce qu'elle etait quand la limite etait
# gravee : elle laisse les trois derniers champs a vide, et champs() rend
# trois entrees. Ajouter un septieme demandera un champ de plus ici, pas une
# refonte -- vegetation.gd itere deja sur la taille de la table.
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

# Stades 4-6 OPTIONNELS. Nom vide OU duree nulle = stade ignore, l'espece n'en
# declare pas. Les defauts ci-dessous laissent tout a vide -- une espece qui
# tenait dans trois stades n'a rien a toucher.
@export var nom_stade_4: String = ""
@export var duree_stade_4: float = 0.0
@export var stature_stade_4: float = 0.0
@export_file("*.glb", "*.tscn", "*.scn") var modele_stade_4: String = ""

@export var nom_stade_5: String = ""
@export var duree_stade_5: float = 0.0
@export var stature_stade_5: float = 0.0
@export_file("*.glb", "*.tscn", "*.scn") var modele_stade_5: String = ""

@export var nom_stade_6: String = ""
@export var duree_stade_6: float = 0.0
@export var stature_stade_6: float = 0.0
@export_file("*.glb", "*.tscn", "*.scn") var modele_stade_6: String = ""

# DE COMBIEN LA VIE D'UN INDIVIDU S'ECARTE DE CELLE DE SON ESPECE, en fraction.
# A 0.3, une plante vit entre 70 % et 130 % des durees declarees ci-dessus --
# tous ses seuils a la fois, tiree une seule fois a sa naissance. A ZERO, toutes
# les plantes de l'espece sont identiques, et c'est le defaut.
#
# CE QU'ELLE CORRIGE, ET CE N'EST PAS COSMETIQUE : sans elle, N plantes nees au
# meme tick franchissent TOUS leurs seuils au meme tick, pour toujours. Une
# population n'est alors pas un continuum mais quelques COHORTES synchronisees :
# la vegetation apparait d'un bloc, et le tick qui porte le passage doit tout
# faire ensemble. Le meme travail, ETALE, ne se voit pas.
#
# C'EST DE LA BIOLOGIE, PAS DU BRUIT. Deux graines de la meme espece ne murissent
# pas au meme rythme -- sol, eau, lumiere, graine. La variance est la chose
# reelle qui manquait, pas un pansement sur un defaut.
#
# UN SEUL FACTEUR POUR TOUTE LA VIE de la plante, jamais un par stade : les
# seuils de stade.gd sont CUMULES et doivent rester croissants. Un facteur
# unique les met tous a l'echelle sans jamais pouvoir les croiser.
@export var dispersion_duree: float = 0.0

@export_group("Ombre")

# ACTIVE LE MECANISME DE DOMINANCE PAR OMBRE. Par defaut DESACTIVE : une
# espece isolee (ou dont tous les stades ont la meme stature) n'a pas besoin
# de calculer l'ombre entre ses plantes -- le mecanisme tournerait a vide et
# couterait N requetes de voisinage a chaque rafraichissement.
#
# ACTIVER SEULEMENT QUAND UNE ESPECE DOIT ETRE DOMINEE PAR UNE AUTRE (ex :
# herbe sous arbre, ou stade jeune sous stade adulte de la meme espece si tu
# veux mesurer). Une espece qui l'active recoit les requetes de voisinage a
# chaque rafraichir_plante, et son age gele quand une voisine porte une
# stature strictement superieure. Le compte de voisins reste calcule de toute
# facon (utilise par la densite de reproduction), independamment de ce champ.
@export var utilise_ombre: bool = false

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

@export_group("Collision")

# LE RAYON DU TRONC, en metres. Une plante qui en declare un recoit un corps
# solide que rien ne traverse : un cylindre de ce rayon, haut comme la STATURE de
# son stade -- il grandit donc avec elle, sans qu'une valeur soit a saisir par
# stade.
#
# C'EST LE TRONC, PAS L'ARBRE. Bloquer l'encombrement entier ferait de chaque
# arbre mature un mur de plusieurs metres et fermerait la foret a toute unite ; on
# circule sous la canopee, on contourne le fut.
#
# A ZERO, AUCUN CORPS N'EST POSE, et c'est le defaut : une herbe ne bloque
# personne, et une scene existante ne change pas de comportement en silence. Le
# gate est arithmetique, jamais une branche qui nommerait une espece (CLAUDE.md,
# ADN) -- meme idiome qu'« un objet sans point_fusion ne fond jamais ».
@export var rayon_collision: float = 0.0

@export_group("Apparence")

# La couleur des touffes fabriquees pour les stades qui ne declarent aucun modele.
@export var couleur: Color = Color(0.38, 0.68, 0.28)

# LA DISTANCE AU-DELA DE LAQUELLE GODOT CESSE DE DESSINER CETTE ESPECE, en
# metres. A zero, aucune limite -- tout est dessine, quelle que soit la distance.
#
# ELLE EST PAR ESPECE, et c'est tout l'interet : un brin d'herbe ne se distingue
# plus a quarante metres, un arbre de sept metres se voit d'un bout a l'autre de
# la vallee. Une distance commune obligerait a prendre la plus grande des deux.
#
# CE N'EST PAS DE LA SIMULATION. La plante hors de portee vit exactement comme
# les autres -- elle vieillit, elle se reproduit, elle meurt. Seul son DESSIN
# s'arrete. Et c'est la CAMERA qui en decide, pas le joueur : rien ici n'a besoin
# de savoir ou il est.
#
# CE QU'ELLE NE FAIT PAS : elle ne libere aucun noeud ni aucune memoire, et elle
# ne touche pas au tronc solide -- un arbre qu'on ne voit plus barre toujours le
# passage.
@export var distance_rendu: float = 0.0

# Les reglages, ramasses en un Dictionary. C'est la SEULE chose que ce noeud rend,
# et la seule que couvert.gd lui demande.
# STADES FILTRES : ne sont declares que les stades dont le nom n'est pas vide ET
# la duree est strictement positive. Un stade a duree nulle figerait la plante
# a son premier stade (stade.gd:avancer) et une espece a 4 stades declares dont
# le 4e est vide passerait pour une espece a 4 stades avec un dernier stade
# instable. Filtrer ici garde couvert.gd et vegetation.gd generiques.
func champs() -> Dictionary:
	var noms_bruts: Array = [
		nom_stade_1, nom_stade_2, nom_stade_3,
		nom_stade_4, nom_stade_5, nom_stade_6,
	]
	var durees_brutes: Array = [
		duree_stade_1, duree_stade_2, duree_stade_3,
		duree_stade_4, duree_stade_5, duree_stade_6,
	]
	var statures_brutes: Array = [
		stature_stade_1, stature_stade_2, stature_stade_3,
		stature_stade_4, stature_stade_5, stature_stade_6,
	]
	var modeles_bruts: Array = [
		modele_stade_1, modele_stade_2, modele_stade_3,
		modele_stade_4, modele_stade_5, modele_stade_6,
	]
	var noms: Array = []
	var durees: Array = []
	var statures: Array = []
	var modeles: Array = []
	for i in range(noms_bruts.size()):
		if String(noms_bruts[i]) == "" or float(durees_brutes[i]) <= 0.0:
			continue
		noms.append(String(noms_bruts[i]))
		durees.append(float(durees_brutes[i]))
		statures.append(float(statures_brutes[i]))
		modeles.append(String(modeles_bruts[i]))
	return {
		"noms_stades": noms,
		"durees_stades": durees,
		"statures_stades": statures,
		"dispersion_duree": dispersion_duree,
		"modeles_stades": modeles,
		"utilise_ombre": utilise_ombre,
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
		"rayon_collision": rayon_collision,
		"distance_rendu": distance_rendu,
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
