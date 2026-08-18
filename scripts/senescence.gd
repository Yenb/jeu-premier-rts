extends RefCounted

# Mecanisme du coeur : SENESCENCE -- incremente l'age d'une entite, rien
# d'autre. Derniere couche d'expression individuelle du corps interne,
# chantier "fondation genetique dormante" (voir docs/design.md "L'entite
# comme agent complet"). scripts/expression.gd fait DEJA tout le calcul de
# senescence (lecture de data/senescence.json, application des courbes par
# chemin, ecriture via son propre appliquer()) -- ce fichier ne duplique
# rien de ca, il tient seulement l'horloge que expression.gd lit.
#
# FICHIER MINIMAL, VOULU : contrairement a deformation.gd/lien_personnel.gd/
# epigenetique.gd (qui possedent chacun leur propre calcul ET leur propre
# ecriture par chemin), la totalite du calcul de senescence a deja ete
# ecrite dans expression.gd AVANT ce fichier (il lit proprietes.age, itere
# catalogue_senescence, applique modulateur_par_annee * annees pour le mode
# "lineaire", ecrit par chemin via son appliquer()). Il ne restait donc
# rien a calculer ni a ecrire par chemin ici -- seulement a faire avancer
# l'age lui-meme, ce que rien d'autre dans le depot ne fait.
#
# DEUXIEME ROLE, AJOUTE PAR LE CHANTIER « horloge du monde » : POSER LE TEMPS
# DU MONDE SUR L'ENTITE (proprietes.heure_courante / proprietes.saison),
# calcule par scripts/horloge.gd. CORRECTION DE CE QUE CET EN-TETE AFFIRMAIT
# JUSQU'ICI : « aucun concept de temps du monde n'existe » n'est plus vrai --
# _temps_ecoule reste un accumulateur LOCAL au Node de chaque banc, mais il
# se DEVERSE desormais sur les entites par ce fichier, une fois par tick au
# lieu d'etre recopie dans chaque banc.
#
# POURQUOI ICI ET PAS DANS UN MECANISME A PART : senescence.gd est deja LE
# fichier qui fait avancer une horloge sur une entite (proprietes.age). Le
# temps du monde est la MEME nature de geste -- ecrire, sur l'entite, une
# grandeur temporelle que le cablage lui fournit -- et un troisieme fichier
# qui parcourrait les memes entites au meme tick pour poser deux cles de plus
# serait un parcours de plus sans loi de plus. horloge.gd tient le CALCUL
# (pur, sans etat, teste hors domaine), ce fichier tient l'ECRITURE : meme
# separation exacte que stade.gd (compare) face a senescence.gd (incremente).
#
# DEUX HORLOGES DISJOINTES SUR LA MEME ENTITE, jamais reliees (meme doctrine
# que age vs age_marque ci-dessous) : proprietes.age est INDIVIDUELLE et en
# ANNEES (chaque entite a la sienne, elle naissent a des instants
# differents) ; proprietes.heure_courante/saison sont MONDIALES et en
# heures/en nom (identiques pour toutes les entites du meme tick, puisque le
# cablage passe la meme horloge a tous ses appels). L'age ne se deduit jamais
# de l'heure, ni l'inverse.
#
# UNITE : proprietes.age est un float en ANNEES (contrat deja fixe par
# expression.gd, voir son en-tete : "chaque courbe du catalogue s'applique
# des que age >= age_debut"). delta, lui, est en SECONDES DE SIMULATION
# (convention du reste du depot -- deformation.gd/depense.gd/etc). Les deux
# unites ne se convertissent pas elles-memes : annees_par_seconde est le
# facteur d'echelle qui les relie, RECU EN PARAMETRE, jamais une constante
# en dur ici -- c'est au CABLAGE (banc, ou plus tard le jeu reel) de
# choisir a quelle vitesse le temps du jeu vieillit ses entites, pas a ce
# mecanisme de le deviner.
#
# Structurel vs facultatif (voir docs/design.md, "Propriete structurelle vs
# facultative") : proprietes.age est STRUCTURELLE ICI -- posee sur
# data/types.json:dynamique (0.0 par defaut), heritee par tout type qui
# compose ce paquet, meme geste que genes_actifs/genes_etat/
# marques_epigenetiques. Sa cle absente dit "ceci n'est pas une entite
# equipee pour vieillir", jamais "age neutre a 0.0" -- CONTRAIREMENT a
# expression.gd, qui la lit en FACULTATIVE (ecrite avant qu'elle rejoigne
# types.json, jamais retouche par ce chantier, meme choix deja fait pour
# marques_epigenetiques) : deux fichiers, deux contrats sur la meme cle,
# meme precedent que colon.proprietes.engagement (structurelle dans
# couplage.gd, facultative dans agir.gd:_score).
#
# NE MUTE QUE TROIS CLES PLATES : proprietes.age TOUJOURS, plus
# proprietes.heure_courante et proprietes.saison quand une horloge est
# fournie -- aucun chemin en points, aucun _lire_chemin/_ecrire_chemin a
# dupliquer ici (contrairement a expression.gd) : trois cles plates, connues
# d'avance, jamais imbriquees.
#
# INDEPENDANT de epigenetique.gd (decision tranchee par Yael) : l'age de
# l'entite (proprietes.age, ce fichier) et l'age d'une marque epigenetique
# (proprietes.marques_epigenetiques[nom].age_marque, epigenetique.gd) sont
# deux horloges disjointes, jamais reliees -- aucune modulation croisee
# (une marque ne decroit pas plus vite parce que l'entite vieillit). Meme
# doctrine que la composition ADDITIVE d'expression.gd : chaque couche
# contribue independamment, aucune ne module le taux d'une autre.
#
# entite : Dictionary { id, position, proprietes }, mute en place par
#          avancer() -- seule proprietes.age change.
# delta : float, secondes de simulation ecoulees ce pas (meme convention
#         que tout le reste du depot).
# annees_par_seconde : float, facteur d'echelle RECU du cablage, jamais
#                       une constante de ce fichier -- age += delta *
#                       annees_par_seconde.
# horloge : Dictionary, FACULTATIF, defaut {} -- le temps du MONDE, construit
#           une seule fois par tick par le cablage et passe tel quel a chaque
#           appel. VIDE (ou absent) = ce monde n'a pas d'horloge : aucune
#           ecriture, aucune alarme, comportement RIGOUREUSEMENT identique a
#           celui d'avant ce chantier -- c'est ce qui laisse les appelants
#           existants (banc_reproduction.gd, banc_succession.gd,
#           banc_simulation_acceleree.gd) inchanges.
#
# LE CAS DU COUPLE (voir docs/design.md, « Propriete structurelle vs
# facultative ») applique a `horloge` : chacune de ses cles est FACULTATIVE
# tant que le Dictionary entier est absent, et devient STRUCTURELLE des que
# le Dictionary est fourni -- fournir une horloge DECLARE qu'on en veut une,
# un defaut invente y contredirait la declaration au lieu de decrire un point
# neutre du monde.
#   temps_ecoule / duree_jour_secondes / heures_par_jour : STRUCTURELLES des
#     que `horloge` est non vide -> push_error nommant la cle, aucune des
#     deux cles d'horloge ecrite.
#   heure_depart : FACULTATIVE, defaut 0.0 -- « le monde a commence a
#     minuit » est un point reel, pas une invention.
#   saisons : FACULTATIVE, defaut [] -- un monde sans saisons est legitime :
#     proprietes.saison n'est alors JAMAIS ecrite, sans aucune alarme.
#   jours_par_saison : FACULTATIVE tant que `saisons` est vide, STRUCTURELLE
#     des que `saisons` est peuplee (meme couple, un cran plus bas).
#
# L'AGE AVANCE TOUJOURS EN PREMIER, et son avancement ne depend JAMAIS de
# l'horloge : une horloge cassee alarme et ne pose rien, mais ne prive pas
# l'entite de son propre vieillissement. Deux roles disjoints dans un seul
# fichier, jamais un seul chemin ou l'un peut faire tomber l'autre.
#
# Resumabilite JSON stricte (voir docs/cadrage_corps_interne_colon.md) :
# proprietes.age et proprietes.heure_courante sont des floats nus,
# proprietes.saison une String nue -- aucun Vector3, aucun Callable.

const Horloge = preload("res://scripts/horloge.gd")

const CLES_HORLOGE_STRUCTURELLES := ["temps_ecoule", "duree_jour_secondes", "heures_par_jour"]

static func avancer(entite: Dictionary, delta: float, annees_par_seconde: float, horloge: Dictionary = {}) -> void:
	var proprietes: Dictionary = entite.get("proprietes", {})
	if not proprietes.has("age"):
		push_error("senescence.gd : propriete structurelle 'age' absente de proprietes")
		return
	proprietes["age"] = proprietes.age + delta * annees_par_seconde
	_poser_temps_du_monde(proprietes, horloge)

# Deverse le temps du MONDE sur l'entite. Ne calcule rien lui-meme : la loi
# vit entierement dans horloge.gd (pure, sans etat, prouvee hors domaine par
# test_horloge.gd), ce fichier ne fait qu'ecrire ce qu'elle rend -- meme
# separation que stade.gd (compare) face a senescence.gd (incremente).
static func _poser_temps_du_monde(proprietes: Dictionary, horloge: Dictionary) -> void:
	if horloge.is_empty():
		return
	for cle in CLES_HORLOGE_STRUCTURELLES:
		if not horloge.has(cle):
			push_error("senescence.gd : horloge fournie sans sa cle structurelle '%s'" % cle)
			return
	var temps_ecoule: float = float(horloge.temps_ecoule)
	var duree_jour_secondes: float = float(horloge.duree_jour_secondes)
	var heures_par_jour: float = float(horloge.heures_par_jour)
	proprietes["heure_courante"] = Horloge.heure(
		temps_ecoule, duree_jour_secondes, heures_par_jour, float(horloge.get("heure_depart", 0.0)))
	var saisons: Array = horloge.get("saisons", [])
	if saisons.is_empty():
		return
	if not horloge.has("jours_par_saison"):
		push_error("senescence.gd : horloge porte 'saisons' sans 'jours_par_saison' (le cas du couple)")
		return
	proprietes["saison"] = Horloge.saison(
		temps_ecoule, duree_jour_secondes, float(horloge.jours_par_saison), saisons)
