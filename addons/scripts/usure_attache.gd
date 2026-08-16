extends RefCounted

# Mecanisme du coeur : USURE D'ATTACHE -- erode la force des attaches DEJA
# CRISTALLISEES (proprietes.attaches, voir attache_par_trait.gd/attaches.gd).
# Chantier « L'entite comme agent complet », voir docs/design.md.
#
# DEUX FICHIERS, DEUX RESPONSABILITES (decision Yael) : attache_par_trait.gd
# CRISTALLISE des attaches neuves depuis liens_personnels, ne retire ni ne
# modifie jamais une attache existante (voir son propre en-tete : « pas de
# mecanisme d'oubli ici »). Ce fichier fait l'INVERSE et seulement l'INVERSE :
# il ne cristallise JAMAIS rien de neuf (il ne touche jamais
# proprietes.liens_personnels, jamais proprietes.sensibilite_generalisation),
# il ne fait qu'EMOUSSER ce qui existe deja dans proprietes.attaches. Les deux
# fichiers cohabitent sur la meme cle (proprietes.attaches) sans jamais
# s'appeler l'un l'autre -- meme discipline que « aucun mecanisme du coeur ne
# precharge un autre mecanisme », voir CLAUDE.md/CARTE.md §7 (seule exception
# documentee : propagation.gd/banc_commun.gd, sans rapport ici).
#
# DOCTRINE (voir CLAUDE.md, « sedimentation, jamais effacement ») : une
# attache cristallisee ne disparait JAMAIS -- sa force peut descendre, jamais
# a zero, jamais retiree de proprietes.attaches. PATRON NEUF dans ce depot :
# tous les mecanismes de decroissance existants (epigenetique.gd/
# lien_personnel.gd/deformation.gd) RETIRENT l'entree sous un plancher. Celui-
# ci fait l'oppose -- un plancher STRICTEMENT POSITIF (force_plancher, lu au
# catalogue) que la force ne franchit JAMAIS vers le bas, l'entree elle-meme
# n'est JAMAIS retiree de proprietes.attaches, quelle que soit la duree
# ecoulee sans renouvellement.
#
# DEUX CANAUX D'EROSION, INDEPENDANTS, jamais additifs entre eux (un seul
# s'applique par attache et par tick -- voir GEL ci-dessous) :
# - USURE PASSIVE : taux_usure_passive (catalogue_usure:defaut) -- s'applique
#   par defaut, tant qu'aucun des deux canaux suivants ne prend le relais.
# - CONTRADICTION ACTIVE : taux_usure_contradiction (catalogue_usure:defaut,
#   PLUS RAPIDE que taux_usure_passive par construction) -- remplace l'usure
#   passive (ne s'ADDITIONNE PAS a elle) des que le colon percoit, EN PLUS de
#   ne pas percevoir le trait de l'attache elle-meme, une chose portant le
#   trait CONTRADICTOIRE (data/contradictions_attaches.json, resolu par
#   trait_vise -- voir CATALOGUE CONTRADICTIONS plus bas).
#
# GEL PAR RENOUVELLEMENT (decision Yael, PRIORITE ABSOLUE sur la
# contradiction) : si le colon percoit, CE TICK, une chose portant le trait
# de l'attache elle-meme (attache.propriete), AUCUNE erosion n'est appliquee
# -- ni passive ni par contradiction, meme si une chose contradictoire est
# aussi percue en meme temps. Patron de detection copie de
# lien_personnel_croissance.gd (perception FILTREE PAR TRAIT,
# entree.chose.proprietes.get(trait, false)) -- le CODE n'est pas partage
# (lien_personnel_croissance.gd cible proprietes.liens_personnels, cle par
# CHOSE precise ; celui-ci cible proprietes.attaches, cle deja generalisee
# par TRAIT), seul le PATRON de detection est repris. Le gel NE FAIT JAMAIS
# remonter la force -- il l'IMMOBILISE seulement ce tick. La force ne remonte
# QUE par une cristallisation neuve (attache_par_trait.gd), jamais par ce
# fichier, jamais par la seule exposition.
#
# CATALOGUE USURE (data/usure_attaches.json) : UNE SEULE ENTREE « defaut »
# (meme convention sentinelle que data/liens_personnels.json:defaut/
# data/heredite.json:defaut -- JAMAIS une reference choisie par
# proprietes, l'usure est UNIVERSELLE, pas une regle par trait) -> {
# taux_usure_passive, taux_usure_contradiction, force_plancher }. Catalogue
# ENTIER recu en parametre, jamais charge par ce fichier. Une entree
# « defaut » absente, ou l'un des trois champs absent, alarme et n'ECRIT
# RIEN SUR AUCUNE ATTACHE -- jamais un defaut silencieux de 0.0 qui ferait
# soit stagner l'usure (taux a 0.0 invente), soit effacer un plancher cense
# proteger la force (meme doctrine que gestation.gd/heredite.gd face a un
# champ de catalogue manquant).
#
# CATALOGUE CONTRADICTIONS (data/contradictions_attaches.json) : PAS de
# sentinelle « defaut » ici -- meme patron qu'attache_par_trait.gd (AUCUNE
# reference choisie par l'entite, ce fichier ITERE TOUTES les entrees du
# catalogue a chaque attache) : Dictionary regle_id -> { trait,
# trait_contradictoire }. Pour une attache visant trait_vise, ce fichier
# cherche TOUTE entree dont "trait" == trait_vise ; des que son
# "trait_contradictoire" est percu (meme detection filtree que le
# renouvellement, sur un trait different), la contradiction est ACTIVE pour
# cette attache CE TICK. Un catalogue VIDE ({}) est un point neutre legitime
# (aucune contradiction declaree, seule l'usure passive s'applique jamais)
# -- jamais une alarme, contrairement au catalogue usure ci-dessus (dont
# l'entree « defaut » est, elle, indispensable a tout calcul).
#
# Structurel vs facultatif (voir docs/design.md, "Propriete structurelle vs
# facultative") : proprietes.attaches est STRUCTURELLE ici, meme convention
# qu'attache_par_trait.gd/attaches.gd -- son absence dit "ceci n'est pas une
# entite equipee pour porter des attaches", jamais une alarme "rien a
# eroder". Une liste VIDE ([]) reste legitime (rien a eroder, silencieux).
# Chaque element de proprietes.attaches est traite avec CONFIANCE (meme
# contrat qu'attaches.gd:deformer/menace_attache, qui lisent directement
# attache.force/attache.propriete sans validation par element) -- ce fichier
# ne verifie jamais qu'un element individuel a la bonne forme, seulement que
# la CLE proprietes.attaches existe.
#
# entite : Dictionary { id, position, proprietes }, mute en place -- SEUL
#          le champ "force" de chaque element de proprietes.attaches change.
#          Ne touche jamais liens_personnels, sensibilite_generalisation, ni
#          aucune autre cle.
# perceptions : Array de { chose, ... } tel que rendu par
#          perception.gd:percevoir -- seul "chose" (id + proprietes) est lu,
#          meme convention que lien_personnel_croissance.gd/accouplement.gd.
# catalogue_usure : Dictionary "defaut" -> { taux_usure_passive,
#          taux_usure_contradiction, force_plancher } -- data/
#          usure_attaches.json, jamais charge par ce fichier.
# catalogue_contradictions : Dictionary regle_id -> { trait,
#          trait_contradictoire } -- data/contradictions_attaches.json,
#          jamais charge par ce fichier.
# delta : float, secondes ecoulees ce pas -- consomme uniquement par
#          l'erosion (force -= taux * delta), aucune autre unite.
#
# Resumabilite JSON stricte (voir docs/cadrage_corps_interne_colon.md) :
# seul le champ "force" (float) d'un element deja present dans
# proprietes.attaches est modifie -- aucun Vector3, aucun Callable, meme
# forme que toute attache posee a la fabrication ou par attache_par_trait.gd.

static func avancer(
	entite: Dictionary,
	perceptions: Array,
	catalogue_usure: Dictionary,
	catalogue_contradictions: Dictionary,
	delta: float,
) -> void:
	var proprietes: Dictionary = entite.get("proprietes", {})
	if not proprietes.has("attaches"):
		push_error("usure_attache.gd : propriete structurelle 'attaches' absente de proprietes")
		return
	if not catalogue_usure.has("defaut"):
		push_error("usure_attache.gd : catalogue usure sans entree 'defaut'")
		return
	var regle_usure: Dictionary = catalogue_usure.defaut
	if not regle_usure.has("taux_usure_passive"):
		push_error("usure_attache.gd : catalogue usure:defaut sans champ 'taux_usure_passive'")
		return
	if not regle_usure.has("taux_usure_contradiction"):
		push_error("usure_attache.gd : catalogue usure:defaut sans champ 'taux_usure_contradiction'")
		return
	if not regle_usure.has("force_plancher"):
		push_error("usure_attache.gd : catalogue usure:defaut sans champ 'force_plancher'")
		return
	var taux_usure_passive: float = regle_usure.taux_usure_passive
	var taux_usure_contradiction: float = regle_usure.taux_usure_contradiction
	var force_plancher: float = regle_usure.force_plancher

	for attache in proprietes.attaches:
		var trait_vise: String = attache.get("propriete", "")
		if _trait_percu(trait_vise, perceptions):
			continue
		var taux: float = taux_usure_passive
		if _contradiction_active(trait_vise, perceptions, catalogue_contradictions):
			taux = taux_usure_contradiction
		var force: float = attache.get("force", 0.0)
		attache["force"] = max(force_plancher, force - taux * delta)

static func _trait_percu(trait_vise: String, perceptions: Array) -> bool:
	for entree in perceptions:
		var chose: Dictionary = entree.chose
		if chose.proprietes.get(trait_vise, false) == true:
			return true
	return false

static func _contradiction_active(trait_vise: String, perceptions: Array, catalogue_contradictions: Dictionary) -> bool:
	for regle_id in catalogue_contradictions:
		var regle: Dictionary = catalogue_contradictions[regle_id]
		if regle.get("trait", "") != trait_vise:
			continue
		var trait_contradictoire: String = regle.get("trait_contradictoire", "")
		if trait_contradictoire == "":
			continue
		if _trait_percu(trait_contradictoire, perceptions):
			return true
	return false
