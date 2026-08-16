extends RefCounted

# Mecanisme du coeur : SOMME -- DEUXIEME BRIQUE de la couche LECTEUR, a
# cote de comptage.gd (voir docs/design.md, "Les collectifs n'existent
# pas -- un resume lu, pas un objet pose"). comptage.gd rend COMBIEN
# D'ENTITES satisfont une regle (un int) ; ce fichier rend COMBIEN AU
# TOTAL une liste d'entites porte d'une grandeur (un float). Deux
# questions differentes, deux fichiers -- jamais un cinquieme mode de
# comptage.gd, qui changerait son TYPE DE RETOUR (int -> float) donc sa
# signature, pour tous ses appelants existants.
#
# EXTRACTION, PAS UNE INVENTION : le meme geste etait recopie a
# l'identique dans QUATRE bancs (banc_ecoulement.gd, banc_erosion.gd,
# banc_cratere.gd, banc_simulation_acceleree.gd). MEME PATRON que
# portee.gd, quantite_matiere.gd, occlusion.gd, horloge.gd : extraction
# ETROITE, appelee par plusieurs fichiers, qui n'unifie rien d'autre
# autour d'elle. LES QUATRE COPIES RESTENT EN PLACE, inchangees -- dette
# COSMETIQUE recensee dans CARTE.md, section 6.
#
# DEUX USAGES, ET C'EST LA MEME FONCTION : mesurer une OFFRE (un total
# qui DOIT bouger) et verifier un INVARIANT (un total dont le moindre
# ecart est un bug). Les deux ont un appelant reel dans le depot.
#
# MEME PATRON DE PORTEE que comptage.gd (le troisieme du depot) : la
# liste est DEJA CONSTRUITE par l'appelant. Ce fichier ne connait ni
# l'espace (position, rayon, region), ni le monde, ni aucun nom de
# contenu -- il recoit un Array et un NOM de grandeur, jamais ecrit en
# dur ici.
#
# Deux fonctions, deux profondeurs de lecture -- jamais une seule
# generalisee par un chemin passe en parametre : le geste recopie quatre
# fois est celui des reserves, le second existe parce que la meme
# question se pose sur une propriete PLATE (ex. mesurer la conservation
# d'une grandeur qui ne vit pas sous "reserves").
#
# reserves(entites, nom_reserve) -> float
#   Somme entites[i].proprietes.reserves[nom_reserve].reserve.
#
# propriete(entites, nom_propriete) -> float
#   Somme entites[i].proprietes[nom_propriete].
#
# Contrats communs aux deux, identiques a ceux de comptage.gd :
# - Array VIDE : 0.0. Un total nul et un total sur rien se disent du meme
#   nombre -- l'appelant qui doit les distinguer compte les entites
#   lui-meme (comptage.gd).
# - Un element qui n'est pas un Dictionary, ou dont "proprietes" est
#   absente ou n'est pas un Dictionary, est ignore SILENCIEUSEMENT (Array
#   sale legitime, meme garde que comptage.gd:compter -- l'appelant
#   filtre s'il veut).
# - Une entite qui ne porte pas la reserve (ou la propriete) demandee
#   contribue 0.0 SANS alarme : une propriete facultative absente est un
#   fait legitime (voir docs/design.md, "Propriete structurelle vs
#   facultative", .has() avant .get()). Vaut aussi pour un canal de
#   reserve present mais sans la cle "reserve".
# - Une valeur presente mais NON NUMERIQUE (String, bool, Vector3...) :
#   push_error nommant l'entite et la grandeur, cette entite seule
#   contribue 0.0, la somme continue sur les autres -- meme contrat que
#   comptage.gd, mode superieur_a. Les quatre copies de banc font
#   float(valeur) A L'AVEUGLE : 0.0 silencieux sur une String, PLANTAGE
#   sur un Vector3. Ce fichier ne reprend pas ce geste.
#
# Ne fait pas : ne mute jamais `entites` (calcul PUR) ; ne borne rien, ni
# en haut ni en bas -- une reserve negative se SOUSTRAIT, c'est la somme
# vraie qui est rendue (rien dans le coeur ne borne le haut d'une
# reserve, voir CARTE.md §2 depense.gd) ; ne rend jamais la liste des
# contributions, seulement leur total ; ne charge aucun fichier ; ne
# cable aucun banc.

static func reserves(entites: Array, nom_reserve: String) -> float:
	var total := 0.0
	for entite in entites:
		var proprietes = _proprietes(entite)
		if proprietes == null:
			continue
		var table = proprietes.get("reserves")
		if not (table is Dictionary) or not table.has(nom_reserve):
			continue
		var canal = table[nom_reserve]
		if not (canal is Dictionary) or not canal.has("reserve"):
			continue
		total += _numerique(entite, nom_reserve, canal["reserve"])
	return total

static func propriete(entites: Array, nom_propriete: String) -> float:
	var total := 0.0
	for entite in entites:
		var proprietes = _proprietes(entite)
		if proprietes == null:
			continue
		if not proprietes.has(nom_propriete):
			continue
		total += _numerique(entite, nom_propriete, proprietes[nom_propriete])
	return total

# Rend le Dictionary "proprietes" d'une entite, ou null si l'element est
# mal forme (pas un Dictionary, "proprietes" absente ou d'un autre type)
# -- une seule garde pour les deux fonctions, silencieuse par contrat.
static func _proprietes(entite):
	if not (entite is Dictionary):
		return null
	var proprietes = entite.get("proprietes")
	if not (proprietes is Dictionary):
		return null
	return proprietes

# `entite` n'est lue ici que pour NOMMER la source d'une alarme (meme
# usage que comptage.gd:_satisfait) -- aucune autre lecture.
static func _numerique(entite: Dictionary, nom: String, valeur) -> float:
	if not (valeur is float or valeur is int):
		push_error("somme.gd : entite '%s' porte '%s' = %s (non numerique), cette entite contribue 0.0" %
			[entite.get("id", "?"), nom, str(valeur)])
		return 0.0
	return float(valeur)
