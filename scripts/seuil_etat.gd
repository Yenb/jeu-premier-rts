extends RefCounted

# Mecanisme du coeur : SEUIL D'ETAT REVERSIBLE sur une propriete continue
# DEJA CALCULEE par un autre mecanisme (chantier "colonne thermique",
# brique commune aux cases 3/4/7/8 du tableau Thermique -- voir
# docs/orion-matrice-elements.md). MEME BASCULE que charge.gd:_avancer_canal
# (franchissement montant pose un etat, franchissement descendant le
# retire -- reversible, symetrique, jamais un evenement unique) mais un
# POINT D'ENTREE DIFFERENT : charge.gd ACCUMULE sa propre valeur depuis des
# causes a portee (monte/descend en interne, delta requis). Ce fichier ne
# possede ni ne calcule AUCUNE valeur d'entree, n'a besoin d'aucun delta --
# il COMPARE une propriete deja presente sur l'objet (ex. proprietes.
# temperature, ecrite par temperature.gd, jamais recalculee ici) a un
# seuil, LUI-MEME potentiellement deja present sur l'objet (ex. proprietes.
# point_fusion, fusionne a la fabrication par objet.gd depuis
# data/materiaux.json -- voir data/proprietes_immuables_composition.json).
# Une comparaison pure a chaque appel, plus la memoire de son propre cote
# precedent (voir MEMOIRE PAR ENTREE plus bas).
#
# GENERIQUE : ce fichier ne connait ni "temperature", ni "point_fusion", ni
# "point_ebullition", ni "chaud", ni "liquide"/"gaz", ni aucun nom de
# contenu. Chaque nom de propriete comparee ET chaque nom d'etat pose/
# retire viennent d'un catalogue recu en parametre (data/seuils_etat.json,
# jamais charge ici).
#
# UNE ENTREE, UN SEUL ETAT -- CHAQUE ENTREE EST TOTALEMENT INDEPENDANTE DES
# AUTRES (decision explicite, prise apres un bug constate a l'ecriture --
# voir CHOIX DE CONCEPTION plus bas) : contrairement a un premier jet qui
# faisait poser un etat ET en retirer un AUTRE sur le meme franchissement
# (ex. "point_fusion" pose "liquide" ET retire "solide" a la fois), une
# entree ne touche jamais qu'UN SEUL nom d'etat -- exactement le patron de
# charge.gd (une "poser" Dictionary appliquee symetriquement au-dessus/
# en-dessous), generalise a un nom d'etat plutot qu'a un Dictionary de
# proprietes arbitraires. Plusieurs entrees peuvent donc laisser PLUSIEURS
# etats actifs EN MEME TEMPS sur le meme objet a haute temperature (ex. au-
# dela de point_ebullition, "liquide" ET "gaz" sont TOUS LES DEUX actifs --
# physiquement correct, un objet au-dela de son point d'ebullition est
# aussi, necessairement, au-dela de son point de fusion) : c'est a
# l'APPELANT (un banc, jamais ce fichier) de choisir comment AFFICHER un
# ensemble d'etats qui se chevauchent (ex. prioriser "gaz" sur "liquide"
# pour la couleur d'un carre) -- ce fichier ne hierarchise jamais les
# etats entre eux.
#
# CHOIX DE CONCEPTION (bug constate, corrige avant d'etre laisse en
# l'etat) : une premiere version faisait porter a chaque entree un
# `etat_au_dessus` ET un `etat_en_dessous` (le second retire par le
# premier au franchissement montant, et inversement) pour enchainer
# solide -> liquide -> gaz sans jamais nommer "solide" comme un troisieme
# etat reel. Avec deux entrees CHAINEES (point_fusion/point_ebullition
# partageant le nom "liquide"), un grand saut de temperature en un seul
# appel (ex. une source qui disparait d'un coup, l'objet retombe vers
# l'ambiante par un ecart enorme au pas suivant) pouvait laisser l'etat
# INTERMEDIAIRE ("liquide") actif alors que l'objet avait deja retraverse
# LES DEUX seuils. Corrige en simplifiant a UN SEUL ETAT PAR ENTREE,
# totalement independante.
#
# DEUXIEME BUG CONSTATE, PLUS TARD (chantier "transitions directes
# solide<->gaz") : le premier jet de ce fichier lisait `etait_dessus`
# directement depuis `proprietes.etats_actifs.has(etat)` -- l'etat PARTAGE
# ETAIT sa propre memoire. Tant qu'une SEULE entree ciblait un nom d'etat
# donne, c'etait exact. Des qu'une DEUXIEME entree cible le MEME nom (ex.
# "sublimation" et "point_ebullition" posent toutes deux "gaz"), cette
# lecture partagee casse : une entree dont la condition est FAUSSE relit
# "etat precedent = VRAI" (pose par l'AUTRE entree, pas par elle-meme) et
# EFFACE ce que l'autre entree vient de poser, DANS LE MEME APPEL (ordre
# d'iteration du Dictionary), A CHAQUE APPEL -- constate concretement sur
# du fer reel (test_banc_changement_etat.gd) qui restait bloque "gazeux"
# ou perdait son "gaz" a tort des qu'une entree "sublimation" existait dans
# le meme catalogue partage, meme sans qu'aucun materiau ne declare les
# deux seuils a la fois.
#
# MEMOIRE PAR ENTREE (correction) : chaque entree porte desormais SA
# PROPRE memoire de franchissement, `proprietes.seuils_etat_memoire`
# (Dictionary, reference de catalogue -> bool, forme A). Elle ne lit
# JAMAIS ce qu'une AUTRE entree a pose ou retire dans `etats_actifs` --
# uniquement SON PROPRE dernier cote observe, sous SA PROPRE reference.
# BOOTSTRAP (memoire absente pour cette reference, ex. objet jamais encore
# traite par ce mecanisme) : replie UNE SEULE FOIS sur
# `etats_actifs.has(etat)` -- preserve le comportement historique "un objet
# fabrique DEJA au-dessus d'un seuil, sans que `etat` n'ait jamais ete pose
# a la main, bascule au premier appel qui le constate". A partir de ce
# premier appel, la memoire est ECRITE A CHAQUE PASSAGE (meme sans
# bascule) : c'est ce qui la rend IMMUNISEE a toute mutation de
# `etats_actifs` par une AUTRE entree entre deux appels -- une entree dont
# la condition ne change jamais (ex. `seuil_sublimation` absent, repli
# INF, jamais franchi) ne relit plus JAMAIS `etats_actifs` apres son
# premier appel, elle ne peut donc plus jamais desinterpreter un etat pose
# par quelqu'un d'autre comme le sien.
#
# RISQUE RESIDUEL, ACCEPTE, PAS CORRIGE (meme famille que point_ignition en
# composition mixte, voir data/proprietes_immuables_composition.json) : si
# DEUX entrees ciblant le MEME nom d'etat sont TOUTES LES DEUX reellement
# applicables sur le MEME objet (ni l'une ni l'autre en repli INF) ET que
# leurs franchissements DIVERGENT dans le temps (l'une active, l'autre pas,
# a un instant donne), l'entree qui redescend efface le nom MEME SI
# l'autre entree le veut encore actif -- chaque entree agit SANS REGARDER
# les autres, par construction (voir MEMOIRE PAR ENTREE ci-dessus), aucune
# des deux ne sait que l'autre existe. Non corrige : aucun materiau reel de
# ce depot ne declare aujourd'hui deux seuils differents visant le meme nom
# d'etat sur le meme objet (ex. point_ebullition ET seuil_sublimation a la
# fois) -- si un jour un tel contenu existait, ce risque redeviendrait
# actif.
#
# Recoit (avancer()) : `monde` (Array de { id, position, proprietes }, MUTE
# EN PLACE -- proprietes.etats_actifs gagne ou perd des noms, meme forme A
# que etat_duree.gd/etat_effectif.gd ; proprietes.seuils_etat_memoire
# (Dictionary ref -> bool) porte la memoire PRIVEE de ce mecanisme, jamais
# lue ni ecrite par aucun autre fichier), `catalogue` (Dictionary ref -> {
# propriete_continue, seuil_propriete?, seuil?, etat } -- voir champ par
# champ ci-dessous).
# Rend : Array des id des choses ayant vu au moins un etat basculer ce
# passage (meme contrat que charge.gd:avancer).
#
# CHAMPS D'UNE ENTREE :
# - propriete_continue (String, STRUCTURELLE) : nom de la propriete a
#   comparer sur CHAQUE objet (ex. "temperature"). Entree sans ce champ :
#   push_error, entree ignoree. Objet qui ne porte pas cette propriete :
#   chemin mort silencieux pour CET objet sur CETTE entree (pas une
#   alarme -- ex. un objet non physique n'a jamais de "temperature", c'est
#   legitime, pas une donnee cassee).
# - seuil_propriete (String, FACULTATIF) : si presente, le seuil est LU
#   PAR OBJET sur proprietes[seuil_propriete] -- permet un seuil qui varie
#   par materiau (ex. "point_fusion", fusionne a la fabrication, different
#   pour bois/pierre/fer). Objet sans cette propriete : repli sur INF,
#   cette entree ne se declenche JAMAIS pour CET objet -- meme idiome que
#   propagation.gd:delai_ignition avec point_ignition absent (gate
#   desactive PAR LA SEULE ARITHMETIQUE, jamais une branche separee) :
#   UN OBJET SANS point_fusion NE FOND JAMAIS.
# - seuil (float, FACULTATIF, ignore si seuil_propriete est fourni) :
#   seuil UNIVERSEL, pas par materiau (ex. "chaud", le meme seuil pour
#   n'importe quel objet). Ni seuil_propriete ni seuil fournis :
#   push_error, repli sur INF -- jamais un seuil invente.
# - etat (String, STRUCTURELLE) : pose au franchissement montant, retire
#   au franchissement descendant. Entree sans ce champ : push_error,
#   entree ignoree.
#
# DIRECTION DE LA COMPARAISON, meme convention que charge.gd : strictement
# AU-DESSUS (`valeur > seuil`), jamais >=.
#
# DEUX CONTRAINTES STRUCTURELLES QUI FACONNENT TOUS SES APPELANTS, a lire
# AVANT de cabler quoi que ce soit dessus :
# (1) il ne lit qu'une cle PLATE de `proprietes` -- une reserve, qui vit
#     sous proprietes.reserves.<nom>.reserve, lui est INVISIBLE ;
# (2) il ne compare que VERS LE HAUT (voir ci-dessus). « Descendre sous un
#     seuil » n'est donc PAS exprimable directement.
# D'ou le geste que tous les cablages ecrivent : un MIROIR PLAT, parfois
# INVERSE (poser proprietes.manque_energie = capacite - reserve, puis
# comparer CE miroir a un seuil montant). Et une consequence a ne pas
# decouvrir apres coup : un miroir RECALCULE A NEUF chaque tick rend l'etat
# REVERSIBLE ; un miroir ACCUMULE le rend DEFINITIF -- c'est le cablage,
# jamais ce fichier, qui choisit lequel des deux.
#
# UNE ENTREE NON CONCERNEE EST UN CHEMIN MORT SILENCIEUX (objet sans la
# propriete comparee, ou seuil en repli INF) : un MEME catalogue partage
# peut donc etre passe TEL QUEL a un banc qui n'exerce qu'une seule de ses
# entrees, sans le filtrer et sans une alarme.
#
# COEXISTENCE : plusieurs entrees du catalogue s'appliquent INDEPENDAMMENT
# au meme objet, sur la MEME propriete continue ou des proprietes
# differentes, MEME quand elles ciblent le meme nom d'etat (voir MEMOIRE
# PAR ENTREE ci-dessus, et le RISQUE RESIDUEL documente) -- chaque entree
# pose/retire son propre nom depuis SA PROPRE memoire, sans collision tant
# qu'aucune paire d'entrees reellement applicables sur le meme objet ne
# diverge dans le temps.

static func avancer(monde: Array, catalogue: Dictionary) -> Array:
	var bascules: Array = []
	for chose in monde:
		var proprietes: Dictionary = chose.proprietes
		# INSTANTANE pris AVANT que quelque entree que ce soit ne mute
		# etats_actifs ce passage -- sert UNIQUEMENT au bootstrap (voir
		# MEMOIRE PAR ENTREE ci-dessous) ; sans lui, une entree traitee
		# APRES une autre dans ce meme appel bootstrapperait sur un
		# etats_actifs DEJA mute par cette autre entree, pas sur l'etat
		# d'AVANT cet appel -- reintroduirait exactement le bug que la
		# memoire par entree est censee corriger, uniquement pour le tout
		# premier appel de deux entrees partageant un nom d'etat.
		var actifs_avant: Array = proprietes.get("etats_actifs", []).duplicate()
		var a_bascule := false
		for ref in catalogue:
			var ref_str := String(ref)
			# "_note" (String) est un texte descriptif, pas une entree --
			# meme convention que test_lint_donnees.gd:_parcourir, jamais
			# descendu ni traite comme une regle.
			if ref_str.begins_with("_"):
				continue
			if _avancer_seuil(ref_str, catalogue[ref], proprietes, actifs_avant):
				a_bascule = true
		if a_bascule:
			bascules.append(chose.id)
	return bascules

static func _avancer_seuil(ref: String, entree: Dictionary, proprietes: Dictionary, actifs_avant: Array) -> bool:
	if not entree.has("propriete_continue"):
		push_error("seuil_etat.gd : entree sans 'propriete_continue', ignoree")
		return false
	var propriete_continue: String = entree.propriete_continue
	if not proprietes.has(propriete_continue):
		return false
	var valeur: float = float(proprietes[propriete_continue])

	var seuil := INF
	if entree.has("seuil_propriete"):
		seuil = float(proprietes.get(entree.seuil_propriete, INF))
	elif entree.has("seuil"):
		seuil = float(entree.seuil)
	else:
		push_error("seuil_etat.gd : entree sans 'seuil' ni 'seuil_propriete', repli sur INF (jamais franchi)")

	if not entree.has("etat"):
		push_error("seuil_etat.gd : entree sans 'etat', ignoree")
		return false
	var etat: String = entree.etat

	var actifs: Array = proprietes.get("etats_actifs", [])
	var memoire: Dictionary = proprietes.get("seuils_etat_memoire", {})
	# BOOTSTRAP (voir MEMOIRE PAR ENTREE en tete de fichier) : seule la
	# PREMIERE lecture de CETTE reference replie sur l'INSTANTANE
	# actifs_avant (jamais le "actifs" local, deja potentiellement mute par
	# une entree precedente CE MEME appel). A partir d'ici, "memoire" est
	# ECRITE INCONDITIONNELLEMENT ci-dessous -- meme sans bascule -- pour
	# que les appels suivants ne retombent plus JAMAIS sur ce repli, quoi
	# qu'une AUTRE entree fasse au
	# meme nom d'etat entre deux appels.
	var etait_dessus: bool = memoire.get(ref, actifs_avant.has(etat))
	var est_dessus: bool = valeur > seuil
	memoire[ref] = est_dessus
	proprietes["seuils_etat_memoire"] = memoire
	if etait_dessus == est_dessus:
		return false

	if est_dessus:
		if not actifs.has(etat):
			actifs.append(etat)
	else:
		actifs.erase(etat)
	proprietes["etats_actifs"] = actifs
	return true
