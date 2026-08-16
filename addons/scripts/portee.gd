extends RefCounted

# Utilitaire minimal -- MEME PATRON que quantite_matiere.gd (extraction
# ETROITE, appelee par plusieurs fichiers, qui n'unifie rien d'autre autour
# d'elle). Seule part reellement commune, mesuree, entre attaches.gd,
# propagation.gd, flux.gd, extinction.gd et charge.gd.
# ECARTE : la FUSION de ces cinq mecanismes en un seul (voir docs/design.md,
# "Direction majeure") -- part commune mesuree a ~5-10% du code de detection
# de chacun, quatre axes de variation independants avant meme d'atteindre
# l'effet. Seule cette ligne survit, extraite une fois ; chaque mecanisme
# garde sa boucle, sa portee, son agregation et son effet.
#
# Ce fichier ne connait NI la liste a parcourir, NI l'agregation (max,
# somme, presence), NI la nature de l'effet -- ces trois axes restent
# proprement dans chaque appelant, aucun n'est accessoire.
#
# Recoit : deux positions (Vector3) et une portee (float).
# Rend : true si les deux positions sont a portee, false sinon. Rien d'autre --
# pas de distance rendue, pas de poids, pas de liste. Un appelant qui a aussi
# besoin de la distance elle-meme la recalcule de son cote : ce fichier ne rend
# qu'une reponse binaire, par construction.
#
# TROIS PROPRIETES DU CONTRAT : la frontiere est INCLUSE (<=, jamais <) ; une
# portee NEGATIVE laisse toujours hors de portee ; la comparaison est
# SYMETRIQUE, l'ordre des deux positions ne change rien.

static func en_portee(position_a: Vector3, position_b: Vector3, portee: float) -> bool:
	return position_a.distance_to(position_b) <= portee
