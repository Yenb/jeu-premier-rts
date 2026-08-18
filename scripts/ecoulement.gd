extends RefCounted

# ecoulement.gd -- mecanisme du coeur neuf (chantier "ecoulement gravitaire --
# eau par pente", audit prealable audit_ecoulement_gravitaire_prealable.md).
# HUITIEME nature de mecanisme (docs/design.md, "Direction majeure") :
# TRANSFERT CONSERVE PAIR-A-PAIRE CONDITIONNE PAR COMPARAISON RELATIVE --
# ne correspond a aucune des sept deja nommees (lecture pure, ecriture
# differee irreversible, transfert continu non conserve [flux.gd], seuil
# reversible [charge.gd], evenement ponctuel par selection [frappe.gd],
# derivation passive [velocite.gd], transfert destructif entre DEUX objets
# DEJA identifies par l'appelant [consommer.gd]) : ici c'est le mecanisme
# LUI-MEME qui identifie la paire source/receveur, par comparaison mutuelle
# de deux voisins du meme ensemble -- aucun des sept precedents ne compare
# jamais deux instances entre elles pour decider un sens de transfert.
#
# Recoit :
# - cases (Array de { id, position, proprietes }) : generique, aucun nom de
#   contenu en dur. Boucle NUE sur "cases" (index contre index, jamais
#   monde.gd:choses_dans_rayon -- couteux en O(n) par case sur TOUT le
#   monde ; ici "cases" est deja la liste ciblee par l'appelant, voir
#   audit_ecoulement_gravitaire_prealable.md §2).
# - rayon_voisinage (float) : portee de voisinage, comparee via
#   position.distance_to -- "position" reste un FAIT SPATIAL PUR ici :
#   AUCUNE case ne pose jamais d'altitude sur son propre position.z
#   (decision Yael, question posee avant d'ecrire : position.z reste a
#   0.0 partout, meme convention que le reste du depot -- docs/design.md,
#   "Verticalite", "Z reste a zero aujourd'hui" -- jamais lue comme
#   altitude ici). CONTRADICTION CONCRETE qui impose ce decouplage, posee
#   avant d'ecrire : si l'altitude vivait dans position.z, l'ecart de
#   hauteur entre deux cases ADJACENTES d'un relief depasserait a lui seul
#   le rayon de voisinage -- plus aucune case ne serait voisine d'aucune
#   autre, et l'ecoulement ne se declencherait jamais.
# - nom_reserve (String) : nom de la reserve transferee
#   (proprietes.reserves.<nom_reserve>.reserve, meme forme que
#   consommer.gd/depense.gd). Jamais un nom de domaine en dur ici.
# - nom_altitude (String) : nom de la PROPRIETE d'altitude
#   (proprietes.<nom_altitude>, un float simple, jamais position.z).
# - taux (float) : facteur qui module l'ecart d'altitude en debit --
#   deja resolu par l'appelant, aucun nom de propriete de domaine lu ici.
# - delta (float) : temps ecoule ce pas, en secondes.
#
# Pour CHAQUE PAIRE ORDONNEE (case, voisin) a distance <= rayon_voisinage :
# hauteur = proprietes.get(nom_altitude, 0.0) + reserve courante (l'eau
# elle-meme modifie la hauteur effective -- une case qui se vide peut
# cesser d'etre "la plus haute" et s'arreter de transferer en cours de
# tick). Si hauteur_case > hauteur_voisin : la demande vaut taux * ecart *
# delta, passee telle quelle avec delta=1.0 (le produit y vaut alors
# exactement la demande) ; la trace porte ce que le mecanisme dit avoir
# retire. Ce fichier ne borne rien -- voir l'en-tete de consommer.gd. Si
# hauteur_case <= hauteur_voisin : rien -- l'eau ne remonte jamais.
#
# SEQUENCE : UNE SEULE PASSE, mutation immediate a chaque transfert
# (contrairement a reaction.gd, jamais deux passes detection/application)
# -- une case qui distribue vers PLUSIEURS voisins dans le meme tick voit
# sa reserve courante decroitre a chaque transfert, ce qui borne
# naturellement la somme distribuee sans code de bornage supplementaire.
# EFFET ASSUME, PAS EMPECHE STRUCTURELLEMENT : l'ordre d'iteration des
# cases peut faire "voyager" de l'eau sur plus d'un saut dans un seul tick
# de grande taille (une case tres haute peut alimenter une voisine avant
# que celle-ci ne soit a son tour comparee a une troisieme, dans la MEME
# passe) -- accepte par calibration (delta petit, taux module), a
# reouvrir si un besoin de jeu l'exige (voir reaction.gd pour le patron a
# deux passes).
#
# Rend l'Array des transferts effectues ce tick, chacun
# { source_id, receveur_id, quantite } -- pour affichage/trace, jamais
# recalcule par l'appelant.

const Consommer = preload("res://scripts/consommer.gd")

static func avancer(cases: Array, rayon_voisinage: float, nom_reserve: String, nom_altitude: String, taux: float, delta: float) -> Array:
	var transferts: Array = []
	for i in range(cases.size()):
		var case: Dictionary = cases[i]
		for j in range(cases.size()):
			if i == j:
				continue
			var voisin: Dictionary = cases[j]
			if case.position.distance_to(voisin.position) > rayon_voisinage:
				continue
			var hauteur_case: float = _hauteur(case, nom_altitude, nom_reserve)
			var hauteur_voisin: float = _hauteur(voisin, nom_altitude, nom_reserve)
			if hauteur_case <= hauteur_voisin:
				continue
			var ecart: float = hauteur_case - hauteur_voisin
			var reserve_avant: float = _reserve(case, nom_reserve)
			if reserve_avant <= 0.0:
				continue
			var demande: float = taux * ecart * delta
			if demande <= 0.0:
				continue
			var resultat: Dictionary = Consommer.transferer(case, voisin, nom_reserve, nom_reserve, demande, 1.0)
			var quantite: float = float(resultat.quantite)
			if quantite <= 0.0:
				continue
			transferts.append({"source_id": case.id, "receveur_id": voisin.id, "quantite": quantite})
	return transferts

static func _hauteur(case: Dictionary, nom_altitude: String, nom_reserve: String) -> float:
	return float(case.proprietes.get(nom_altitude, 0.0)) + _reserve(case, nom_reserve)

static func _reserve(case: Dictionary, nom_reserve: String) -> float:
	return float(case.proprietes.get("reserves", {}).get(nom_reserve, {}).get("reserve", 0.0))
