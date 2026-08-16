extends RefCounted

# Mecanisme du coeur : SELECTION D'UNE SORTIE PARMI N DECLAREES EN DONNEE,
# par le produit poids individuel x grandeur de situation -- argmax, egalite
# stricte alarmee, premiere declaree conservee. Audit prealable :
# audit_mecaniques_psycho_sociales_prealable.md, §3 et lignes 2/8 (les deux
# seules au verdict CONCEPT NEUF REQUIS, et c'est le MEME mecanisme : ecrit
# une seule fois sur N sorties, jamais deux fois sur deux branches nommees).
#
# PAS UNE NEUVIEME NATURE D'EFFET (docs/design.md, « Direction majeure ») :
# c'est la CINQUIEME deja nommee -- l'evenement ponctuel par selection de
# frappe.gd -- deplacee d'une selection d'OBJET DU MONDE vers une selection
# de SORTIE DECLAREE. design.md n'a donc pas a bouger.
#
# RefCounted SANS ETAT, deux fonctions static PURES, aucun preload, aucun
# chargement de fichier, aucune mutation -- meme gabarit que
# quantite_matiere.gd/occlusion.gd/frappe.gd. N'appartient a AUCUN pipeline
# de decision (perception/saillance/dominance/agir) et n'en suppose aucun :
# il ne recoit ni monde, ni colon, ni chose -- trois valeurs nues.
#
# GENERIQUE : ce fichier ne connait ni « grief », ni « peur », ni
# « soumission », ni aucun nom de contenu. Les noms de sorties arrivent en
# parametre, opaques, et ne sont jamais compares a quoi que ce soit d'ecrit
# ici. Prouve hors domaine par scripts/test_bifurcation.gd (suffixe
# "_qwil", aucun catalogue reel lu).
#
# ---- LA LOI, en un paragraphe ----
# Chaque sortie recoit le score `biais[sortie] * grandeur` (poids absent du
# Dictionary : repli 0.0 -- un individu qui ne penche pour rien est
# legitime, jamais une alarme ; meme repli que agir.gd:_verbe_par_poids,
# `poids.get(verbe, 0.0)`). La sortie au score le plus haut gagne, A LA
# CONDITION que ce score soit STRICTEMENT POSITIF -- sinon aucune sortie
# n'est rendue. Meme exigence exacte que agir.gd:_verbe_par_poids (`p > 0.0
# and p > meilleur_poids`, rend "" sinon) : rien ne bifurque par defaut.
#
# CE QUE CETTE EXIGENCE ACHETE, et c'est la raison de la reprendre : le
# gate est desactive PAR LA SEULE ARITHMETIQUE, jamais par une branche
# separee (idiome deja pose par propagation.gd:delai_ignition sur
# point_ignition absent, et par seuil_etat.gd sur seuil_propriete absente).
# Une grandeur nulle ou negative ne produit aucun score positif, donc aucune
# sortie -- sans qu'un `if grandeur <= 0.0` n'existe nulle part. Un biais
# entierement nul non plus. Un poids negatif ne gagne jamais.
#
# LIMITE REELLE DE CETTE LOI, DITE PLUTOT QUE MASQUEE (elle n'est pas un
# defaut de l'ecriture, elle est dans la forme meme demandee par l'audit) :
# la grandeur est UN SEUL SCALAIRE, commun a toutes les sorties. Tant
# qu'elle est strictement positive, elle multiplie tous les scores par le
# meme nombre et NE CHANGE DONC JAMAIS QUI GAGNE -- l'argmax est celui des
# poids seuls. Elle joue deux roles, tous deux reels, et aucun troisieme :
# (a) un GATE (rien ne bifurque tant qu'elle n'est pas positive), (b) une
# ECHELLE lisible (resoudre() rend les scores, un appelant peut les
# afficher ou les comparer a un seuil a lui). Si un jour la grandeur devait
# reellement arbitrer, il faudrait UNE GRANDEUR PAR SORTIE -- ce serait une
# autre signature, et donc un autre chantier : ni invente ni bricole ici.
# Verrouille POSITIVEMENT par test (le gagnant est le meme a grandeur 1.0
# et a grandeur 1000.0). CE QU'UN CABLAGE FAIT A LA PLACE, en attendant :
# faire dependre le gagnant d'une situation exterieure se fait en COMPOSANT
# le `biais` lui-meme avant l'appel (un biais recalcule chaque tick a partir
# de plusieurs grandeurs), jamais en esperant que `grandeur` arbitre.
#
# EGALITE STRICTE AU SOMMET : NON TRANCHEE -- la PREMIERE sortie dans
# l'ordre de l'Array `sorties` est conservee, mais ALARMEE (push_error
# nommant les sorties a egalite et le score). Meme convention exacte que
# frappe.gd:selectionner et agir.gd:_verbe_par_poids : on ne tranche pas, on
# refuse le silence. C'est LA raison pour laquelle `sorties` est un ARRAY et
# non les cles du Dictionary `biais` : l'ordre d'iteration d'un Dictionary
# n'est pas un ordre declare, et le depot a deja paye ce genre de couplage
# (voir etat_effectif.gd, ORDRE DE RESOLUTION, qui trie explicitement plutot
# que de subir un ordre d'iteration).
# A SAVOIR AVANT D'APPELER CE FICHIER A CHAQUE TICK : sur des grandeurs
# CONTINUES (des scores qui varient avec des distances, par exemple), deux
# sorties se croisent NECESSAIREMENT, et une alarme part a chaque
# croisement. Elle est juste -- a cet instant precis rien ne departage les
# deux -- et sans consequence, la premiere declaree etant conservee : la
# console en portera la trace, ce n'est PAS le signe d'une donnee cassee.
# Un appelant a grandeurs DISCRETES ne rencontre le cas que sur une donnee
# mal posee.
#
# `sorties` porte deux fois le meme nom : les scores vivent dans un
# Dictionary sortie -> score, les doublons y fusionnent donc d'eux-memes et
# ne peuvent JAMAIS produire une fausse egalite avec soi-meme. L'ordre
# declare reste celui du premier passage.
#
# `sorties` vide, ou `biais` vide : rend "" (resoudre : sortie "", scores
# vides). CHEMIN MORT SILENCIEUX, jamais une alarme -- n'avoir rien a
# choisir n'est pas une donnee cassee (meme convention que
# frappe.gd:selectionner sans aucun objet a portee, qui rend {}).
#
# ---- selectionner(grandeur, biais, sorties) -> String ----
# La sortie gagnante seule, "" si aucune. Raccourci STRICT de
# resoudre(...).sortie -- jamais deux calculs paralleles, meme discipline
# que etat_effectif.gd:valeur face a resoudre.
#
# ---- resoudre(grandeur, biais, sorties) -> Dictionary ----
# { sortie: String ("" si aucune), score: float (0.0 si aucune),
#   scores: Dictionary sortie -> float (toutes les sorties, gagnantes ou
#   non, dans l'ordre declare), a_egalite: Array de String (les sorties a
#   egalite stricte au sommet -- vide ou de taille >= 2, jamais 1) }
# Pour un appelant qui doit EXPLIQUER pourquoi une sortie l'a emporte (une
# trace console d'observation, un label de banc) sans jamais reimplementer
# la loi ci-dessus.
#
# Recoit : grandeur (float, la valeur de situation -- jamais lue sur un
# objet, l'appelant la fournit deja calculee), biais (Dictionary sortie ->
# poids, forme A : chaque cle EST un nom de sortie, jamais un index --
# un Array indexe couplerait silencieusement l'ordre du JSON a l'ordre des
# sorties), sorties (Array de String, l'ensemble declare en donnee ET son
# ordre de depart en cas d'egalite).
# Ne mute RIEN : ni `biais`, ni `sorties`, ni aucun objet -- il n'en recoit
# aucun. C'est a l'APPELANT (un banc, jamais ce fichier) de faire quoi que
# ce soit de la sortie rendue : la poser comme etat, la journaliser, ou
# l'ignorer. Ce fichier ne connait pas etats_actifs.

static func selectionner(grandeur: float, biais: Dictionary, sorties: Array) -> String:
	return resoudre(grandeur, biais, sorties).sortie

static func resoudre(grandeur: float, biais: Dictionary, sorties: Array) -> Dictionary:
	var scores: Dictionary = {}
	# Ordre declare : l'Array est parcouru tel quel, jamais les cles de
	# `biais` (voir EGALITE STRICTE en tete). Un doublon fusionne ici.
	for sortie_variant in sorties:
		var sortie: String = String(sortie_variant)
		scores[sortie] = float(biais.get(sortie, 0.0)) * grandeur

	var retenue := ""
	var meilleur := 0.0
	for sortie in scores:
		var score: float = scores[sortie]
		if score > 0.0 and score > meilleur:
			meilleur = score
			retenue = sortie

	if retenue == "":
		return {"sortie": "", "score": 0.0, "scores": scores, "a_egalite": []}

	var a_egalite: Array = []
	for sortie in scores:
		if is_equal_approx(scores[sortie], meilleur):
			a_egalite.append(sortie)
	if a_egalite.size() > 1:
		push_error("bifurcation.gd : sorties a egalite stricte au score maximum (%s) : %s -- '%s' conservee (premiere declaree), aucun departage" % [meilleur, a_egalite, retenue])
	else:
		a_egalite = []

	return {"sortie": retenue, "score": meilleur, "scores": scores, "a_egalite": a_egalite}
