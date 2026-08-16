extends RefCounted

# Fuite : mouvement de repulsion, PAS une couche de saillance. Ne decide
# rien -- ne lit ni verbe, ni propriete, ni type : recoit une liste DEJA
# TRIEE de choses a fuir (chacune { position, saillance }) et rend une
# DIRECTION, jamais une cible-position. Separe de scripts/ciblage.gd a
# dessein : fuir ne vise aucune chose -- ciblage.gd a pour metier de
# trouver une cible, pas de produire un mouvement sans cible.
#
# LA PEUR N'EST NI SUR LA CHOSE NI DANS LA SAILLANCE (un nombre nu,
# jamais signe) : elle est dans le poids que le colon met sur le verbe
# s_eloigner (proprietes.poids_verbes, voir agir.gd), et dans le TRI qui
# selectionne quelles choses rejoignent cette liste -- fait par
# l'appelant (scripts/banc_commun.gd:choses_a_fuir), jamais ici. Ce fichier
# ne sait meme pas qu'un verbe existe.
#
# Entree : colon_position (Vector3), choses_a_fuir (Array de { position:
# Vector3, saillance: float } -- saillance un nombre nu, jamais signe).
# Rend : Vector3 -- direction normalisee, ou Vector3.ZERO si rien a fuir
# ou si les repulsions s'annulent exactement (l'appelant ne deplace pas).
#
# Calcul : pour chaque chose, le vecteur (colon_position - chose.
# position), normalise, multiplie par sa saillance -- deux sources
# ADDITIONNENT leurs repulsions ; le colon part a l'oppose de la plus
# forte et passe entre deux menaces sans cas particulier. Aucun nom de
# type, aucune table, aucune propriete lue au-dela de position/saillance.

static func direction(colon_position: Vector3, choses_a_fuir: Array) -> Vector3:
	var somme := Vector3.ZERO
	for chose in choses_a_fuir:
		var loin: Vector3 = colon_position - chose.position
		if loin.length() <= 0.0:
			continue
		somme += loin.normalized() * chose.saillance
	if somme.length() <= 0.0:
		return Vector3.ZERO
	return somme.normalized()
