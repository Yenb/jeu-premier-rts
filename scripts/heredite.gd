extends RefCounted

# Mecanisme du coeur : HEREDITE -- derniere phase du cycle de reproduction
# (apres stade.gd, apres accouplement.gd, apres gestation.gd). Prend les
# genes/marques epigenetiques des parents deja poses par le cycle
# (proprietes.genes_etat/marques_epigenetiques cote porteuse,
# proprietes.gestation.partenaire_genes_etat/partenaire_marques_epigenetiques
# cote partenaire) et produit le KIT GENETIQUE de l'enfant -- jamais
# l'enfant lui-meme. Chantier « L'entite comme agent complet », voir
# docs/design.md.
#
# NE FABRIQUE JAMAIS L'ENFANT : meme discipline que gestation.gd -- ce
# fichier ne connait ni Objet.fabriquer, ni monde.gd, ni aucun generateur
# d'id (voir data/heredite.json:_note, « aucun concept de fabrication d'un
# enfant/naissance n'existe dans le depot »). C'est A L'APPELANT de lire
# proprietes.gestation.naissance_prete (pose par gestation.gd), d'appeler
# fabriquer_genes_enfant() ICI, de fabriquer la coquille de l'enfant par
# Objet.fabriquer, d'ECRASER genes_etat/marques_epigenetiques de cette
# coquille par le Dictionary rendu ici, PUIS de retirer proprietes.gestation
# de la porteuse lui-meme -- ce fichier ne mute rien, ne retire rien, il ne
# fait QUE lire et rendre un resultat.
#
# FONCTION PURE, contrairement a accouplement.gd/gestation.gd (qui mutent
# l'entite en place) : fabriquer_genes_enfant() ne mute NI entite NI le
# rng au-dela de la consommation normale de ses tirages -- meme statut que
# expression.gd:exprimer.
#
# UNE SEULE FONCTION :
#
# fabriquer_genes_enfant(entite, catalogue_heredite, catalogue_epigenetique,
# rng) -> Dictionary { genes_etat, marques_epigenetiques } :
#
# MODE lu sur proprietes.mode_reproduction (jamais un parametre separe --
# meme convention que accouplement.gd, qui lit ce champ lui-meme). Trois
# valeurs traitees, chacune une combinaison differente des allees de
# CHAQUE GENE ACTIF (proprietes.genes_actifs, meme liste que lit
# expression.gd -- les deux parents partagent forcement le meme
# genes_actifs, garanti par la compatibilite espece_reproduction deja
# verifiee par accouplement.gd avant que gestation n'existe) :
#   - "sexuee" : UN allele tire au hasard (rng.randi_range) dans le
#     tableau de la porteuse, UN allele tire au hasard dans le tableau du
#     partenaire (gestation.partenaire_genes_etat) -- le resultat porte
#     TOUJOURS exactement deux allees, quelle que soit la taille des
#     tableaux parents (diploidie : moitie de chaque parent).
#   - "asexuee" : COPIE du tableau complet d'allees de la porteuse (meme
#     taille, meme ordre) -- un seul parent, rien a tirer.
#   - "parthenogenese" : REARRANGEMENT du tableau de la porteuse -- pour
#     CHAQUE POSITION du tableau d'origine (meme taille en sortie qu'en
#     entree, generalise a N alleles, pas seulement 2), un allele tire au
#     hasard AVEC REMISE dans ce meme tableau (donc pour [a,b], quatre
#     resultats possibles : [a,a]/[a,b]/[b,a]/[b,b] -- generalise a N
#     positions pour un gene a N alleles).
#   Un mode_reproduction autre que ces trois valeurs alarme (push_error) et
#   rend un Dictionary VIDE -- ce fichier n'est appele qu'une fois
#   gestation/naissance_prete etablis par le reste du cycle, un mode
#   inattendu a ce point est une donnee mal posee en amont, jamais une
#   valeur neutre a deviner.
#   Un gene de proprietes.genes_actifs dont proprietes.genes_etat (ou, en
#   sexuee, gestation.partenaire_genes_etat) ne porte aucun allele est
#   IGNORE silencieusement (meme contrat que expression.gd:exprimer face a
#   un genes_etat[nom_gene] vide -- point neutre legitime, jamais une
#   alarme) : ce gene n'apparait simplement pas dans le kit rendu.
#
# MUTATION (decision Yael) : APRES construction du tableau d'allees
# (quel que soit le mode), CHAQUE position est independamment soumise a un
# tirage rng.randf() ; sous taux_mutation (taux_mutation_base pour
# "sexuee"/"parthenogenese", taux_mutation_asexuee -- plus faible -- pour
# "asexuee", tous deux lus dans catalogue_heredite:defaut), l'allele recoit
# un bruit gaussien ADDITIF, rng.randfn(0.0, ecart_type_mutation) (meme
# catalogue) -- AUCUN BORNAGE (allele reste un float libre, doctrine deja
# en place pour data/genes.json:resonance_gravitique, des poids positifs et
# negatifs coexistent deja sans plage fixe). modulateurs_environnementaux/
# modulateurs_age_parent (data/heredite.json:defaut) restent DORMANTS --
# NON LUS ICI : ce chantier ne recoit ni un parametre "environnement" ni
# l'age des parents, aucun des deux modulateurs n'a de lecteur avant qu'un
# de ces deux concepts soit cadre (meme statut que "codominant" pour
# expression.gd -- une donnee qui precede son lecteur complet, jamais
# devinee).
#
# CATALOGUE HEREDITE : UNE SEULE ENTREE « defaut » (meme convention
# sentinelle que data/liens_personnels.json:defaut -- JAMAIS une reference
# choisie par proprietes, contrairement a data/reproduction.json), catalogue
# ENTIER passe en parametre, jamais charge par ce fichier. Une entree
# "defaut" absente, ou un champ requis pour le MODE COURANT
# (taux_mutation_base/taux_mutation_asexuee/ecart_type_mutation) absent de
# cette entree, alarme et rend un Dictionary VIDE -- jamais un defaut
# silencieux de 0.0 qui ferait taire une mutation sans que personne ne
# l'ait voulu (meme doctrine que gestation.gd face a duree_gestation absent).
#
# MARQUES EPIGENETIQUES (decision Yael) : pour chaque marque presente CHEZ
# L'UN OU L'AUTRE parent (union des cles de proprietes.marques_epigenetiques
# et de gestation.partenaire_marques_epigenetiques), le modulateur transmis
# est max(modulateur_porteuse, modulateur_partenaire) -- LE PLUS FORT des
# deux, jamais une moyenne ni une somme -- multiplie par
# taux_transmission_enfant (resolu PAR NOM DE MARQUE dans
# catalogue_epigenetique, data/epigenetique.json, meme catalogue que
# epigenetique.gd/expression.gd lisent deja, jamais charge ici). Si le
# resultat descend SOUS plancher_suppression (meme catalogue, meme champ
# que epigenetique.gd:avancer verifie pour la decroissance), la marque
# N'EST PAS transmise -- absente du Dictionary rendu, jamais une entree a
# modulateur quasi nul. Une marque transmise demarre a age_marque: 0.0
# (horodatage frais, meme convention que epigenetique.gd:poser sur une
# marque neuve). Une marque absente de catalogue_epigenetique alarme
# (push_error nommant la marque) et n'est jamais transmise.
#
# RNG (decision Yael, patron banc_comptage.gd -- SEUL precedent du depot,
# voir CLAUDE.md « Aucun hasard non-seede ») : rng: RandomNumberGenerator
# RECU en parametre, JAMAIS instancie dans ce fichier -- le seed vit chez
# l'appelant, jamais ici. A seed egal, deux appels produisent le meme
# resultat -- reproductibilite totale, meme garantie que
# banc_comptage.gd:_appliquer_bascules.
#
# GENES_ACTIFS NON PRODUIT ICI (decision Yael) : ce fichier ne pose jamais
# proprietes.genes_actifs sur le kit rendu -- c'est le TYPE (data/
# types.json, via Objet.fabriquer) qui le porte pour l'enfant, exactement
# comme pour tout autre colon fabrique. Le kit rendu ne porte que
# genes_etat/marques_epigenetiques, jamais genes_actifs.
#
# Structurel vs facultatif (voir docs/design.md, "Propriete structurelle vs
# facultative") : proprietes.gestation, proprietes.genes_actifs et
# proprietes.genes_etat sont STRUCTURELLES ici -- ce fichier n'est appele
# qu'une fois le cycle (stade -> accouplement/poser -> gestation) deja
# passe par ces cles, leur absence est une erreur d'appel, jamais un point
# neutre. Meme statut STRUCTUREL pour proprietes.marques_epigenetiques
# (contrairement a expression.gd, qui la lit encore en FACULTATIVE --
# ecrit avant que cette cle rejoigne data/types.json:dynamique, jamais
# retouche depuis ; heredite.gd, ecrit APRES, suit la convention actuelle
# du fichier, meme bascule que epigenetique.gd/senescence.gd/stade.gd
# avant lui). gestation.partenaire_genes_etat/partenaire_marques_
# epigenetiques ne sont JAMAIS verifies separement : accouplement.gd ET
# gestation.gd:poser les posent INCONDITIONNELLEMENT (duplicate(true) d'un
# Dictionary, {} au pire), leur absence a l'interieur d'un gestation deja
# present ne peut survenir que par construction d'un Dictionary invalide a
# la main -- hors contrat de ce fichier, aucune garde dediee.
#
# entite : Dictionary { id, position, proprietes }, jamais mute par cette
#          fonction.
# catalogue_heredite : Dictionary "defaut" -> { taux_mutation_base,
#          taux_mutation_asexuee, ecart_type_mutation,
#          modulateurs_environnementaux, modulateurs_age_parent } --
#          data/heredite.json, jamais charge par ce fichier. Les deux
#          derniers champs cites restent DORMANTS (voir MUTATION ci-dessus).
# catalogue_epigenetique : Dictionary nom_marque -> { cible,
#          modulateur_pose, taux_decroissance, plancher_suppression,
#          taux_transmission_enfant, source_environnementale } --
#          data/epigenetique.json, meme catalogue que epigenetique.gd/
#          expression.gd, jamais charge par ce fichier.
# rng : RandomNumberGenerator, recu en parametre -- voir RNG ci-dessus.
#
# Rend : Dictionary { genes_etat: Dictionary, marques_epigenetiques:
#         Dictionary } -- forme prete a ecraser directement les cles de
#         meme nom sur l'enfant fabrique par l'appelant. Dictionary VIDE
#         ({genes_etat: {}, marques_epigenetiques: {}}) si une propriete
#         structurelle ou un champ de catalogue requis manque (voir
#         alarmes ci-dessus) -- jamais null, pour que l'appelant puisse
#         toujours ecrire ses deux cles sans verification supplementaire.
#
# Resumabilite JSON stricte (voir docs/cadrage_corps_interne_colon.md) :
# le Dictionary rendu ne porte que des feuilles float/Array<float> --
# aucun Vector3, aucun Callable, meme contrat que genes_etat/
# marques_epigenetiques ailleurs dans le depot.

static func fabriquer_genes_enfant(entite: Dictionary, catalogue_heredite: Dictionary, catalogue_epigenetique: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var vide := {"genes_etat": {}, "marques_epigenetiques": {}}
	var proprietes: Dictionary = entite.get("proprietes", {})
	if not proprietes.has("gestation"):
		push_error("heredite.gd : propriete structurelle 'gestation' absente de proprietes")
		return vide
	if not proprietes.has("genes_actifs"):
		push_error("heredite.gd : propriete structurelle 'genes_actifs' absente de proprietes")
		return vide
	if not proprietes.has("genes_etat"):
		push_error("heredite.gd : propriete structurelle 'genes_etat' absente de proprietes")
		return vide
	if not proprietes.has("marques_epigenetiques"):
		push_error("heredite.gd : propriete structurelle 'marques_epigenetiques' absente de proprietes")
		return vide
	if not catalogue_heredite.has("defaut"):
		push_error("heredite.gd : catalogue heredite sans entree 'defaut'")
		return vide

	var regle: Dictionary = catalogue_heredite.defaut
	var mode: String = proprietes.get("mode_reproduction", "")
	var cle_taux: String
	match mode:
		"sexuee", "parthenogenese":
			cle_taux = "taux_mutation_base"
		"asexuee":
			cle_taux = "taux_mutation_asexuee"
		_:
			push_error("heredite.gd : mode_reproduction '%s' non reconnu (attendu sexuee/asexuee/parthenogenese)" % mode)
			return vide
	if not regle.has(cle_taux):
		push_error("heredite.gd : catalogue heredite:defaut sans champ '%s'" % cle_taux)
		return vide
	if not regle.has("ecart_type_mutation"):
		push_error("heredite.gd : catalogue heredite:defaut sans champ 'ecart_type_mutation'")
		return vide
	var taux_mutation: float = regle[cle_taux]
	var ecart_type_mutation: float = regle.ecart_type_mutation

	var gestation: Dictionary = proprietes.gestation
	var genes_porteuse: Dictionary = proprietes.genes_etat
	var genes_partenaire: Dictionary = gestation.get("partenaire_genes_etat", {})
	var genes_etat_enfant: Dictionary = {}

	for nom_gene in proprietes.genes_actifs:
		var alleles_porteuse: Array = genes_porteuse.get(nom_gene, {}).get("alleles", [])
		if alleles_porteuse.is_empty():
			continue
		var nouveaux_alleles: Array = []
		match mode:
			"sexuee":
				var alleles_partenaire: Array = genes_partenaire.get(nom_gene, {}).get("alleles", [])
				if alleles_partenaire.is_empty():
					continue
				nouveaux_alleles.append(alleles_porteuse[rng.randi_range(0, alleles_porteuse.size() - 1)])
				nouveaux_alleles.append(alleles_partenaire[rng.randi_range(0, alleles_partenaire.size() - 1)])
			"asexuee":
				nouveaux_alleles = alleles_porteuse.duplicate()
			"parthenogenese":
				for _i in range(alleles_porteuse.size()):
					nouveaux_alleles.append(alleles_porteuse[rng.randi_range(0, alleles_porteuse.size() - 1)])
		for i in range(nouveaux_alleles.size()):
			if rng.randf() < taux_mutation:
				nouveaux_alleles[i] = float(nouveaux_alleles[i]) + rng.randfn(0.0, ecart_type_mutation)
		genes_etat_enfant[nom_gene] = {"alleles": nouveaux_alleles}

	var marques_porteuse: Dictionary = proprietes.marques_epigenetiques
	var marques_partenaire: Dictionary = gestation.get("partenaire_marques_epigenetiques", {})
	var noms_marques: Array = []
	for nom_marque in marques_porteuse:
		if not noms_marques.has(nom_marque):
			noms_marques.append(nom_marque)
	for nom_marque in marques_partenaire:
		if not noms_marques.has(nom_marque):
			noms_marques.append(nom_marque)

	var marques_enfant: Dictionary = {}
	for nom_marque in noms_marques:
		if not catalogue_epigenetique.has(nom_marque):
			push_error("heredite.gd : marque epigenetique '%s' absente du catalogue" % nom_marque)
			continue
		var regle_marque: Dictionary = catalogue_epigenetique[nom_marque]
		var modulateur_porteuse: float = marques_porteuse.get(nom_marque, {}).get("modulateur", 0.0)
		var modulateur_partenaire: float = marques_partenaire.get(nom_marque, {}).get("modulateur", 0.0)
		var modulateur_le_plus_fort: float = max(modulateur_porteuse, modulateur_partenaire)
		var taux_transmission: float = regle_marque.get("taux_transmission_enfant", 0.0)
		var modulateur_transmis: float = modulateur_le_plus_fort * taux_transmission
		var plancher: float = regle_marque.get("plancher_suppression", 0.0)
		if modulateur_transmis < plancher:
			continue
		marques_enfant[nom_marque] = {"modulateur": modulateur_transmis, "age_marque": 0.0}

	return {"genes_etat": genes_etat_enfant, "marques_epigenetiques": marques_enfant}
