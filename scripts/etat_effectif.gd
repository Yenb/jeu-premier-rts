extends RefCounted

# Mecanisme du coeur : ETAT EFFECTIF -- rend la valeur EFFECTIVE d'une
# propriete numerique quelconque portee par un objet, en partant de sa
# valeur de BASE (proprietes) et en y appliquant les ETATS actuellement
# actifs sur cet objet (proprietes.etats_actifs). Chantier prealable au
# chantier feu -- inflammabilite effective (voir docs/prototypes.md) :
# ce fichier ne connait ni "mouille", ni "huile", ni "inflammabilite" --
# uniquement des noms recus en parametre ou lus sur l'objet.
#
# NE MUTE JAMAIS : deux fonctions PURES, calcul seul -- aucun noeud,
# testables headless (scripts/test_etat_effectif.gd). Rien n'est ecrit sur
# l'objet ; l'appelant relit la valeur effective a chaque fois qu'il en a
# besoin (meme discipline que champ.gd:force_paire -- jamais une valeur
# mise en cache qui pourrait perimer si un etat change).
#
# proprietes.etats_actifs : Array de String -- FACULTATIVE. Cle absente,
# vide, ou de type autre qu'Array : la valeur de base est rendue telle
# quelle, CHEMIN MORT, aucune allocation (voir "Un objet sans aucun etat"
# plus bas). Meme patron "forme A" que canaux/deformation_sources
# (docs/design.md, "Propriete du monde vs champ de configuration
# technique") : chaque element EST une reference String vers
# data/etats.json, jamais une cle de Dictionary -- verifie par
# scripts/test_lint_donnees.gd, entree "etats_actifs".
#
# etats (parametre, data/etats.json) : Dictionary nom_etat -> { effets:
# Array de { propriete: String, mode: "ecraser" | "moduler", valeur:
# float (mode ecraser) | facteur: float (mode moduler) } }. Catalogue
# recu en parametre, jamais charge par ce fichier (meme convention que
# tout le reste du coeur -- extinction.gd/depense.gd/charge.gd/
# couplage.gd/champ.gd). Un nom present dans etats_actifs mais absent du
# catalogue est une reference cassee -- push_error nommant l'etat, cet
# etat est ignore, jamais un defaut invente.
#
# DEUX GESTES, JAMAIS CONFONDUS :
# - ECRASER : l'etat IMPOSE une valeur, quelle que soit la base. Absolu --
#   des qu'un ecrasement est actif sur une propriete, aucun modulateur sur
#   la meme propriete n'a plus d'effet (l'ecrasement n'est pas une couche
#   de plus au-dessus de la base, c'est un remplacement).
# - MODULER : l'etat MULTIPLIE la valeur de base par un facteur. Plusieurs
#   modulateurs actifs sur la meme propriete se composent tous ensemble,
#   MULTIPLICATIVEMENT -- meme doctrine que "Lecture des calques :
#   composition multiplicative, pas additive" (docs/design.md).
#
# ORDRE DE RESOLUTION, deterministe, JAMAIS l'ordre naturel d'iteration
# d'un Dictionary ou d'un Array (explicitement exige par le chantier) :
# 1. Tous les etats actifs dont le catalogue declare un effet visant LA
#    PROPRIETE demandee sont retenus.
# 2. S'il en existe au moins un en mode "ecraser" : le resultat est la
#    valeur de celui dont le NOM D'ETAT est alphabetiquement le plus petit
#    parmi eux -- tri explicite sur le nom (String), jamais sur l'ordre
#    d'iteration d'un Dictionary ou d'un Array. Tout modulateur present
#    sur la meme propriete est alors IGNORE (voir ECRASER ci-dessus).
# 3. Sinon, s'il existe au moins un modulateur : chacun multiplie la
#    valeur de base, apres tri alphabetique de son nom d'etat -- la
#    multiplication etant commutative, l'ordre ne change jamais le
#    resultat ; le tri est un choix de discipline (determinisme visible,
#    reproductible), pas une necessite mathematique.
# 4. Aucun etat actif ne vise cette propriete (ou etats_actifs absent/
#    vide) : la valeur de base est rendue telle quelle.
#
# Recoit (les deux fonctions) : chose ({ id, position, proprietes }),
# propriete (String, nom de la propriete numerique dont on veut la valeur
# effective -- jamais connu de ce fichier a l'avance, jamais compare a un
# nom en dur), etats (Dictionary, data/etats.json).
#
# valeur(...) -> float : le resultat numerique seul -- API historique,
# suffisante partout ou seul le nombre importe.
#
# resoudre(...) -> Dictionary { valeur: float, mode: "ecraser" | "moduler"
# | "aucun", gagnants: Array de String (noms d'etat dont l'effet est
# retenu -- un seul en mode ecraser, un ou plusieurs en mode moduler, vide
# en mode aucun), ignores: Array de String (noms d'etat actifs sur cette
# propriete mais dont l'effet a ete ecarte -- les ecraseurs perdants d'un
# conflit, ou tout modulateur sous un ecraseur gagnant) } : le detail de
# la resolution, pour un appelant qui doit EXPLIQUER pourquoi une valeur
# est ce qu'elle est (ex. une trace console d'observation) sans jamais
# reimplementer la loi ci-dessus -- valeur() est un raccourci strict de
# resoudre(...).valeur, jamais deux calculs paralleles.
#
# TRI ALPHABETIQUE : reproductible, mais c'est un arbitrage PAR
# ORTHOGRAPHE -- une donnee qui compte dessus pour choisir un gagnant est
# fragile, deux etats concurrents sur la meme propriete sont a eviter en
# donnee plutot qu'a departager par leur nom.
#
# DEUX PIEGES STRUCTURELS, a connaitre avant de declarer un effet :
# (1) CE FICHIER NE S'APPLIQUE QUE SI QUELQU'UN L'APPELLE. Aucune couche de
#     decision ne passe par lui, depense.gd ne le consulte jamais, et les
#     mecanismes qui lisent une propriete la lisent BRUTE. Declarer un effet
#     dans data/etats.json ne produit donc RIEN tant qu'un cablage ne compose
#     pas lui-meme la valeur par ce fichier -- silence total, aucune alarme.
# (2) IL REND `base * facteur`. Un objet qui ne porte PAS la propriete EN
#     BASE rend donc 0.0 -- inoffensif pour une grandeur inerte, MORTEL pour
#     une grandeur utilisee ensuite comme DIVISEUR par l'appelant.
#
# NE POSE JAMAIS AUCUN ETAT : lecture pure, dans les deux sens -- il ne
# retire rien non plus (voir etat_duree.gd pour l'epuisement).
#
# Regle clee : aucun nom d'etat ni de propriete de jeu n'apparait jamais
# ici -- "mouille", "huile", "inflammabilite" ne vivent que dans le
# catalogue recu en parametre et dans les tests (hors domaine pour le
# mecanisme, dans le domaine pour le banc d'observation, voir
# docs/prototypes.md).

static func valeur(chose: Dictionary, propriete: String, etats: Dictionary) -> float:
	return resoudre(chose, propriete, etats).valeur

static func resoudre(chose: Dictionary, propriete: String, etats: Dictionary) -> Dictionary:
	var proprietes: Dictionary = chose.get("proprietes", {})
	var base: float = float(proprietes.get(propriete, 0.0))
	var bruts: Variant = proprietes.get("etats_actifs", [])
	if not (bruts is Array) or bruts.is_empty():
		return {"valeur": base, "mode": "aucun", "gagnants": [], "ignores": []}

	var ecraseurs: Array = []
	var modulateurs: Array = []
	for nom_variant in bruts:
		var nom_etat: String = String(nom_variant)
		if not etats.has(nom_etat):
			push_error("etat_effectif.gd : etat '%s' absent de data/etats.json" % nom_etat)
			continue
		var entree: Dictionary = etats[nom_etat]
		for effet in entree.get("effets", []):
			if effet.get("propriete", "") != propriete:
				continue
			var mode: String = effet.get("mode", "")
			if mode == "ecraser":
				ecraseurs.append({"nom": nom_etat, "valeur": float(effet.get("valeur", 0.0))})
			elif mode == "moduler":
				modulateurs.append({"nom": nom_etat, "facteur": float(effet.get("facteur", 1.0))})
			else:
				push_error("etat_effectif.gd : etat '%s', effet sur '%s' -- mode '%s' non reconnu (attendu 'ecraser' ou 'moduler')" % [nom_etat, propriete, mode])

	if not ecraseurs.is_empty():
		ecraseurs.sort_custom(func(a, b): return a.nom < b.nom)
		var gagnant: Dictionary = ecraseurs[0]
		var ignores: Array = []
		for i in range(1, ecraseurs.size()):
			ignores.append(ecraseurs[i].nom)
		for modulateur in modulateurs:
			ignores.append(modulateur.nom)
		return {"valeur": gagnant.valeur, "mode": "ecraser", "gagnants": [gagnant.nom], "ignores": ignores}

	if modulateurs.is_empty():
		return {"valeur": base, "mode": "aucun", "gagnants": [], "ignores": []}

	modulateurs.sort_custom(func(a, b): return a.nom < b.nom)
	var resultat := base
	var gagnants: Array = []
	for modulateur in modulateurs:
		resultat *= modulateur.facteur
		gagnants.append(modulateur.nom)
	return {"valeur": resultat, "mode": "moduler", "gagnants": gagnants, "ignores": []}
