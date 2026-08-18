extends RefCounted

# Mecanisme du coeur : LECTURE DU RENDEMENT D'UNE RESERVE (chantier
# "feu -- la reserve de combustible suit la matiere"). CAPACITE
# (immuable, calculee UNE FOIS a la fabrication -- voir objet.gd,
# _fabriquer_reserve_combustible) et RESERVE (ce qui reste a bruler,
# decroit -- depense.gd, jamais touche par ce fichier) sont deux champs
# DISTINCTS du meme canal (proprietes.reserves.<nom>). Ce fichier ne fait
# QUE LIRE les deux et en deriver un rendement lisible -- calcul PUR,
# aucune mutation, aucun noeud, testable headless.
#
# POURQUOI CAPACITE EST CALCULEE A LA FABRICATION, PAS A LA DEMANDE
# (decision assumee) : la composition d'un objet est IMMUABLE (se casser
# DETRUIT l'objet et en CREE d'autres, voir objet.gd, DENSITE EFFECTIVE)
# -- la capacite qui en decoule (une SOMME ponderee par volume, voir
# scripts/quantite_matiere.gd) l'est donc AUSSI, et se calcule UNE SEULE
# FOIS, exactement comme densite/inflammabilite (memes decisions,
# objet.gd). CE QUI RESTE A BRULER, en revanche, N'EST PAS immuable : il
# decroit a chaque tick (depense.gd:avancer, deja ecrit, non touche) --
# les DEUX vivent donc sur la MEME instance mais avec des CONTRATS
# OPPOSES : "capacite" n'est JAMAIS reecrite apres la fabrication (aucun
# mecanisme de ce depot n'ecrit ce champ hors objet.gd:fabriquer),
# "reserve" est reecrite a chaque pas (depense.gd, canal deja
# generique, ce fichier ne le duplique jamais).
#
# restant(chose, nom_reserve) -> Dictionary { absolu: float, proportion:
# float } : lit proprietes.reserves[nom_reserve] -- canal ABSENT ou SANS
# "capacite" positive : { absolu: 0.0, proportion: 0.0 }, point neutre
# legitime (un objet sans cette reserve n'a rien a rendre, jamais une
# alarme -- meme discipline que etat_effectif.gd sur une propriete
# absente). "absolu" est "reserve" TEL QUEL -- depense.gd borne
# "reserve" a 0.0 a la soustraction (voir depense.gd, et docs/design.md
# "Depense : reserve bornee a zero") : "absolu" ne peut
# donc pas etre negatif, ce fichier ne fait que relire ce que depense.gd
# a deja borne, jamais une seconde borne ici. "proportion" est
# "reserve / capacite", BORNEE a [0.0, 1.0] (une capacite depassee reste
# lisible en absolu, mais une PROPORTION hors de cet intervalle n'aurait
# aucun sens pour une barre affichee).
#
# DECOUPAGE -- LA VITESSE DE CONSUMATION SELON LA MATIERE, POSSIBLE PLUS
# TARD SANS REECRITURE : ce chantier fixe deliberement "cout_base" a une
# constante EN DONNEE (data/reserve_combustible_composition.json),
# IDENTIQUE pour toute composition -- jamais materiau-dependante ici.
# Rendre "cout_base" materiau-dependant plus tard n'exige AUCUN
# changement de ce fichier ni de depense.gd : il suffirait de calculer
# "cout_base" par la MEME formule que "capacite" (une quantite ponderee
# par volume, scripts/quantite_matiere.gd, sur une AUTRE propriete
# materiau nommee en donnee -- ex. "vitesse_combustion") au lieu d'une
# constante, dans objet.gd:_fabriquer_reserve_combustible SEUL. Le canal
# reste un Dictionary { capacite, reserve, cout_base, surcout_action,
# seuils_ref } identique dans les deux cas -- depense.gd ne voit jamais
# la difference, ce fichier non plus.
#
# Recoit : chose ({ id, position, proprietes }), nom_reserve (String,
# jamais en dur ici -- le nom du canal a lire vient toujours de
# l'appelant). Ne connait ni "combustible", ni "bois", ni aucun nom de
# jeu.

static func restant(chose: Dictionary, nom_reserve: String) -> Dictionary:
	var canal: Dictionary = chose.get("proprietes", {}).get("reserves", {}).get(nom_reserve, {})
	var capacite: float = canal.get("capacite", 0.0)
	if capacite <= 0.0:
		return {"absolu": 0.0, "proportion": 0.0}
	var reserve: float = canal.get("reserve", 0.0)
	return {"absolu": reserve, "proportion": clamp(reserve / capacite, 0.0, 1.0)}
