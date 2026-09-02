extends RefCounted

# sandpile.gd -- mecanisme du coeur neuf. Verbe : TRANSFERT DISCRET
# CONDITIONNE PAR PENTE CRITIQUE. Une paire (source, receveur) declenche
# le transfert d'UN grain (unite entiere) SI ET SEULEMENT SI l'ecart de
# hauteur depasse un seuil de pente. Sous le seuil, la paire est stable,
# aucun mouvement. La quantite transferee est TOUJOURS 1, jamais
# fractionnaire.
#
# NEUVIEME nature de mecanisme (voir taxonomie de ecoulement.gd) --
# proche du "transfert conserve pair-a-paire par comparaison relative"
# de ecoulement.gd, mais distinct sur DEUX axes non-composables dans un
# meme fichier :
#   - GRANULARITE : 1 grain entier par declenchement, jamais une fraction
#     (ecoulement.gd = fluide continu, quantite = taux * ecart * delta).
#   - SEUIL : rien ne bouge sous le seuil (ecoulement.gd transfere au
#     moindre ecart, meme 0.01).
# Deux physiques differentes -- fluide vs granulaire (sable, terre, neige,
# gravats, tout ce qui a un angle de repos). Standard academique : modele
# Bak-Tang-Wiesenfeld (1987), automates cellulaires en physique
# granulaire.
#
# Recoit :
#   - cases : Array de { id, position, proprietes } -- generique, aucun
#     nom de contenu en dur (patron ecoulement.gd). Boucle NUE sur
#     "cases", jamais monde.gd:choses_dans_rayon -- couteux en O(n) par
#     case sur TOUT le monde. L'appelant fournit deja la liste ciblee
#     (colonnes actives + leurs voisines).
#   - rayon_voisinage : distance max entre position.source et
#     position.receveur pour qu'une paire soit consideree. 1.0 pour von
#     Neumann sur grille pas 1.0 (4 cardinaux), 1.5 pour Moore (8
#     voisins). Une valeur negative rend [] (desactivation temporaire par
#     l'appelant, jamais alarmee -- meme patron que taux=0.0 ailleurs).
#   - nom_reserve : cle dans proprietes.reserves ou vit le compte de
#     grains sur la case.
#   - nom_altitude : cle dans proprietes ou vit l'altitude fixe du sol
#     sous les grains. Le decouplage position (fait spatial pur) /
#     altitude (propriete) est le meme que ecoulement.gd -- position.z
#     reste a 0.0 partout (voir CLAUDE.md, "Verticalite"), altitude vit
#     dans une propriete nommee.
#   - seuil_pente : ecart de hauteur MINIMUM (strict) pour declencher un
#     transfert. Sous ce seuil, la paire est stable. Seuil = 0.0 autorise
#     (comportement degenere : tout ecart declenche).
#
# HAUTEUR d'une case : altitude + reserve. Les grains poses modifient la
# hauteur effective -- une pile qui se vide peut cesser d'etre la plus
# haute et s'arreter en cours de tick. Formule identique a ecoulement.gd.
#
# QUANTITE TRANSFEREE : toujours EXACTEMENT 1 grain par paire declenchante
# par tick. Le seuil "reserve source >= 1.0" est verifie AVANT l'appel a
# Consommer.transferer -- sandpile ne cree ni ne fractionne la matiere.
# Une source avec reserve < 1.0 (fraction residuelle laissee par un autre
# mecanisme) est skippee : sandpile ne connait que des grains entiers.
#
# SEQUENCE : UNE seule passe, mutation immediate. Chaque paire NON
# ORDONNEE (i, j) avec i < j est evaluee EXACTEMENT UNE FOIS par tick.
# Le sens du transfert est decide au moment de l'evaluation par
# comparaison des hauteurs : la plus haute est source, l'autre receveur.
# Ne PAS reparcourir (j, i) apres (i, j) -- sinon un transfert discret
# d'un grain (i -> j) inverserait immediatement la relation et un second
# grain retournerait (j -> i), oscillation infinie a chaque tick.
# Contraste avec ecoulement.gd qui boucle plein (i, j) et (j, i) : la
# nature continue de son transfert (taux * ecart * delta) amortit le
# risque d'oscillation, la nature discrete de sandpile ne l'amortit pas.
#
# Une source qui a plusieurs voisines declenchantes distribue a chacune
# dans le meme tick, sa reserve decroissant a chaque transfert -- une
# source a 10 grains avec 4 voisines a 0 (seuil 2) distribue 1 grain a
# chaque voisine dans le meme tick, finit a 6, voisines a 1 chacune.
# Effet assume : cascade rapide, comportement observe dans le
# height-model classique.
#
# CAS D'EGALITE entre voisines (deux voisines a hauteur identique sous
# la meme source) : la premiere rencontree dans l'ordre d'iteration de
# `cases` capte le grain. Biais directionnel accepte, cosmetique --
# l'appelant peut randomiser l'ordre de sa liste (RNG seede) s'il veut
# eliminer le biais, JAMAIS ici (le mecanisme reste deterministe).
#
# Rend : Array de transferts effectues ce tick, chacun
# { source_id: String, receveur_id: String, quantite: 1 } -- pour
# affichage/trace, jamais recalcule par l'appelant. quantite est TOUJOURS
# 1 (le mecanisme ne coalesce pas plusieurs transferts en un seul).

const Consommer = preload("res://scripts/consommer.gd")

static func avancer(cases: Array, rayon_voisinage: float, nom_reserve: String,
		nom_altitude: String, seuil_pente: float) -> Array:
	var transferts: Array = []
	if rayon_voisinage < 0.0:
		return transferts
	for i in range(cases.size()):
		for j in range(i + 1, cases.size()):
			var a: Dictionary = cases[i]
			var b: Dictionary = cases[j]
			if a.position.distance_to(b.position) > rayon_voisinage:
				continue
			# Sens decide MAINTENANT : la plus haute est source, l'autre receveur.
			# Chaque paire {i, j} est evaluee UNE FOIS par tick -- pas de
			# reparcours (j, i) qui provoquerait l'oscillation d'un grain
			# discret.
			var h_a: float = _hauteur(a, nom_altitude, nom_reserve)
			var h_b: float = _hauteur(b, nom_altitude, nom_reserve)
			var source: Dictionary
			var receveur: Dictionary
			var ecart: float
			if h_a > h_b:
				source = a
				receveur = b
				ecart = h_a - h_b
			else:
				source = b
				receveur = a
				ecart = h_b - h_a
			if ecart <= seuil_pente:
				continue
			var reserve_source: float = _reserve(source, nom_reserve)
			if reserve_source < 1.0:
				continue
			# Transfert d'exactement 1 grain (taux=1.0 * delta=1.0 = demande 1.0,
			# bornee par la reserve source qu'on sait >= 1.0). Consommer.transferer
			# garantit la conservation (credit egal au retrait reel).
			var resultat: Dictionary = Consommer.transferer(
				source, receveur, nom_reserve, nom_reserve, 1.0, 1.0)
			var quantite: float = float(resultat.quantite)
			if quantite <= 0.0:
				continue
			transferts.append({
				"source_id": source.id,
				"receveur_id": receveur.id,
				"quantite": 1,
			})
	return transferts

static func _hauteur(case: Dictionary, nom_altitude: String, nom_reserve: String) -> float:
	return float(case.proprietes.get(nom_altitude, 0.0)) + _reserve(case, nom_reserve)

static func _reserve(case: Dictionary, nom_reserve: String) -> float:
	return float(case.proprietes.get("reserves", {}).get(nom_reserve, {}).get("reserve", 0.0))
