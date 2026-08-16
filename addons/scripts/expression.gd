extends RefCounted

# Mecanisme du coeur : EXPRESSION -- traduit genes_etat + marques
# epigenetiques + senescence en valeurs effectives sur les proprietes d'un
# colon, via un chemin en points (meme patron que couplage.gd:_lire_chemin,
# DUPLIQUE ici, jamais preloade -- decision tranchee par Yael : expression.gd
# reste autonome comme les seize autres mecanismes du coeur ; aucun mecanisme
# du coeur ne preloade un autre mecanisme, a la seule exception documentee de
# propagation.gd/banc_commun.gd). Chantier "fondation genetique dormante",
# voir docs/design.md "L'entite comme agent complet".
#
# DEUX FONCTIONS, meme repartition que deformation.gd (une fonction PURE de
# lecture separee d'une fonction qui MUTE, dans le meme fichier) :
# - exprimer(colon, catalogue_genes, catalogue_epigenetique,
#   catalogue_senescence) -> Dictionary { chemin: valeur_effective } : PURE,
#   ne mute jamais colon. Lit la valeur de BASE deja presente au chemin
#   (_lire_chemin, absente -> 0.0, point neutre legitime -- meme convention
#   que couplage.gd:_valeur_satisfaction) puis y ADDITIONNE les contributions
#   de gene(s) + marque(s) epigenetique(s) + senescence qui ciblent ce meme
#   chemin.
# - appliquer(colon, valeurs: Dictionary) -> void : MUTE colon.proprietes,
#   ecrit chaque { chemin: valeur } du Dictionary rendu par exprimer(). C'est
#   le pendant en ECRITURE de couplage.gd:_lire_chemin -- aucun equivalent
#   n'existait avant ce fichier dans le depot.
#
# COMPOSITION ADDITIVE, jamais multiplicative (decision tranchee par Yael) :
# gene(s), marque(s) epigenetique(s) et courbe(s) de senescence qui ciblent
# le meme chemin s'additionnent tous a la valeur de base, sans ordre de
# priorite entre les trois couches -- meme precedent que depense.gd
# (reserve -= (cout_base + surcout_action) * delta, deux modulateurs
# INDEPENDANTS qui s'additionnent sur le meme canal), PAS le precedent de
# deformation.gd (qui pondere rapide/lent en UN SEUL biais puis l'applique
# MULTIPLICATIVEMENT a une saillance deja calculee -- un cas different :
# deformation.gd module un nombre deja resulte, expression.gd construit la
# valeur BRUTE d'une propriete a partir de causes independantes, voir
# docs/design.md "Cause, jamais resultat" : "deux transformations qui posent
# chacune leur propre cause ne s'ecrasent jamais : elles s'accumulent").
#
# STRUCTUREL vs FACULTATIF, deux statuts differents et volontairement
# distincts (voir docs/design.md "Propriete structurelle vs facultative") :
# - proprietes.genes_actifs ET proprietes.genes_etat : STRUCTURELLES (cle
#   absente -> push_error, rend {}) -- meme convention que
#   deformation_sources/deformation_etat (couplage.gd/deformation.gd),
#   parce que ces deux cles existent DEJA, meme vides, sur tout type qui
#   compose le paquet 'dynamique' (data/types.json, chantier "fondation
#   genetique dormante", session precedente). Leur absence dit "ceci n'est
#   pas une entite equipee pour porter des genes", jamais "genes neutres".
# - proprietes.marques_epigenetiques ET proprietes.age : FACULTATIVES (cle
#   absente -> cette couche est simplement ignoree, aucune alarme) --
#   PARCE QUE ni l'une ni l'autre n'existe encore sur AUCUN type reel de
#   data/types.json (ce chantier ne touche pas ce fichier). Les rendre
#   STRUCTURELLES aujourd'hui ferait alarmer exprimer() sur TOUT colon reel
#   du depot, y compris ceux qui n'ont et n'auront jamais d'epigenetique ou
#   de senescence -- l'absence est ici un fait legitime du monde, pas une
#   anomalie. Le jour ou marques_epigenetiques/age rejoignent data/
#   types.json:dynamique en donnee reelle, ce statut peut etre reconsidere,
#   pas avant.
#
# QUATRE MODES D'EXPRESSION (codominant RETIRE de cette V1 -- non
# traduisible en une seule valeur scalaire par cible, un mode qui
# demanderait deux sorties distinctes par allele plutot qu'une fusion ;
# question laissee ouverte pour une V2, jamais devinee ici) :
# - dominant  : le maximum des alleles (un seul allele fort suffit).
# - recessif  : le minimum des alleles (l'allele le plus faible plafonne).
# - additif   : la somme des alleles (les copies s'accumulent).
# - incomplet : la moyenne des alleles (melange, valeur intermediaire).
# Un mode_expression absent du catalogue ou non reconnu (y compris
# "codominant", laisse en donnee dormante sur data/genes.json:
# resonance_gravitique depuis la session precedente -- catalogue NON touche
# par ce chantier) alarme (push_error nommant le gene et le mode) et rend
# une contribution nulle pour ce gene, jamais un defaut silencieux ni un
# crash.
#
# SENESCENCE, UN SEUL MODE IMPLEMENTE ("lineaire") : "exponentiel" et
# "plafonne" restent des noms de mode DECLARES par data/senescence.json
# mais NON IMPLEMENTES ici -- leur formule exacte demanderait un champ
# supplementaire (taux d'acceleration, valeur de plafond) absent du
# catalogue tel que pose (chantier precedent, non retouche ici). Un mode
# autre que "lineaire" alarme (push_error nommant la courbe et le mode) et
# rend une contribution nulle -- signale explicitement, jamais une formule
# devinee. proprietes.age est un float en ANNEES ; chaque courbe du
# catalogue s'applique des que age >= age_debut, quel que soit le type
# (aucune liste "senescence_actifs" -- une courbe de senescence n'est pas
# une reference choisie par l'entite, contrairement a un gene ou une marque,
# elle s'applique universellement des que l'age la franchit).
#
# _lire_chemin : chemin en points ("a.b.c"), descend un Dictionary morceau
# par morceau, rend null (jamais une alarme) des qu'un morceau manque --
# COPIE EXACTE de couplage.gd:_lire_chemin (voir decision de duplication
# ci-dessus), utilisee pour LIRE la base ; jamais utilisee pour verifier une
# ecriture (voir _ecrire_chemin plus bas, qui EST stricte).
#
# _ecrire_chemin : MEME chemin en points, mais en ECRITURE -- ASYMETRIE
# VOULUE avec la lecture (decision tranchee par Yael) : un segment
# intermediaire absent ou non-Dictionary alarme (push_error nommant le
# chemin, l'entite -- via l'appelant, voir appliquer() -- et le segment
# fautif) et N'ECRIT RIEN, jamais de creation silencieuse de structure
# imbriquee. Raison de l'asymetrie : lire une base absente est un point
# neutre legitime (le calcul repart de zero, comme couplage.gd:
# _valeur_satisfaction) ; ecrire a un endroit qui n'existe pas est une
# donnee de catalogue mal ciblee (un chemin invente ou mal orthographie
# dans genes.json/epigenetique.json/senescence.json) -- meme doctrine que
# "jamais un defaut silencieux" deja tenue par deformation.gd/couplage.gd
# sur leurs propres cles structurelles. Un chemin a un seul segment (sans
# point, ex. "masse") s'ecrit directement sur proprietes, aucun segment
# intermediaire a verifier.
#
# Recoit (exprimer) : colon ({ id, position, proprietes }), catalogue_genes
# (data/genes.json : nom_gene -> { cibles: Array de { chemin, poids },
# mode_expression }), catalogue_epigenetique (data/epigenetique.json :
# nom_marque -> { cible, modulateur_pose, taux_decroissance,
# taux_transmission_enfant, source_environnementale }, "modulateur_pose"
# n'est PAS lu ici -- c'est le futur epigenetique.gd qui pose/decroit la
# valeur COURANTE deja stockee sur l'entite, exprimer() ne fait QUE la
# lire), catalogue_senescence (data/senescence.json : nom_courbe -> {
# cible, age_debut, modulateur_par_annee, mode }). Les trois catalogues
# recus en parametre, jamais charges par ce fichier (meme convention que
# extinction.gd/depense.gd/charge.gd/couplage.gd/deformation.gd).
#
# Rend (exprimer) : Dictionary { chemin: valeur_effective } -- jamais une
# mutation. Rend (appliquer) : rien, mute colon.proprietes en place.
#
# Regle clee : ne connait aucun nom de gene, de marque ni de propriete de
# jeu -- "resonance_gravitique", "champ_gravitique", "peur" n'apparaissent
# jamais ici, seulement dans les catalogues recus en parametre et dans le
# test hors domaine.

static func exprimer(
	colon: Dictionary,
	catalogue_genes: Dictionary,
	catalogue_epigenetique: Dictionary,
	catalogue_senescence: Dictionary,
) -> Dictionary:
	var proprietes: Dictionary = colon.get("proprietes", {})
	if not proprietes.has("genes_actifs"):
		push_error("expression.gd : propriete structurelle 'genes_actifs' absente de proprietes")
		return {}
	if not proprietes.has("genes_etat"):
		push_error("expression.gd : propriete structurelle 'genes_etat' absente de proprietes")
		return {}

	var deltas: Dictionary = {}

	for nom_gene in proprietes.genes_actifs:
		if not catalogue_genes.has(nom_gene):
			push_error("expression.gd : gene '%s' absent du catalogue" % nom_gene)
			continue
		var entree: Dictionary = catalogue_genes[nom_gene]
		var etat_gene: Dictionary = proprietes.genes_etat.get(nom_gene, {})
		var alleles: Array = etat_gene.get("alleles", [])
		if alleles.is_empty():
			continue
		var expression_brute := _combiner_alleles(alleles, entree.get("mode_expression", ""), nom_gene)
		for cible_entry in entree.get("cibles", []):
			var chemin: String = cible_entry.get("chemin", "")
			if chemin == "":
				continue
			var poids: float = cible_entry.get("poids", 0.0)
			deltas[chemin] = deltas.get(chemin, 0.0) + expression_brute * poids

	if proprietes.has("marques_epigenetiques"):
		for nom_marque in proprietes.marques_epigenetiques:
			if not catalogue_epigenetique.has(nom_marque):
				push_error("expression.gd : marque epigenetique '%s' absente du catalogue" % nom_marque)
				continue
			var entree_marque: Dictionary = catalogue_epigenetique[nom_marque]
			var chemin_marque: String = entree_marque.get("cible", "")
			if chemin_marque == "":
				continue
			var canal_marque: Dictionary = proprietes.marques_epigenetiques[nom_marque]
			var modulateur: float = canal_marque.get("modulateur", 0.0)
			deltas[chemin_marque] = deltas.get(chemin_marque, 0.0) + modulateur

	if proprietes.has("age"):
		var age: float = proprietes.age
		for nom_courbe in catalogue_senescence:
			var entree_senescence: Dictionary = catalogue_senescence[nom_courbe]
			var age_debut: float = entree_senescence.get("age_debut", 0.0)
			if age < age_debut:
				continue
			var chemin_senescence: String = entree_senescence.get("cible", "")
			if chemin_senescence == "":
				continue
			var annees: float = age - age_debut
			var modulateur_par_annee: float = entree_senescence.get("modulateur_par_annee", 0.0)
			var mode_senescence: String = entree_senescence.get("mode", "lineaire")
			var valeur := _valeur_senescence(annees, modulateur_par_annee, mode_senescence, nom_courbe)
			deltas[chemin_senescence] = deltas.get(chemin_senescence, 0.0) + valeur

	var resultat: Dictionary = {}
	for chemin in deltas:
		var base_variant: Variant = _lire_chemin(proprietes, chemin)
		var base: float = float(base_variant) if base_variant != null else 0.0
		resultat[chemin] = base + deltas[chemin]
	return resultat

static func appliquer(colon: Dictionary, valeurs: Dictionary) -> void:
	var proprietes: Dictionary = colon.get("proprietes", {})
	for chemin in valeurs:
		_ecrire_chemin(proprietes, chemin, valeurs[chemin])

static func _combiner_alleles(alleles: Array, mode: String, nom_gene: String) -> float:
	match mode:
		"dominant":
			var maximum: float = alleles[0]
			for a in alleles:
				if a > maximum:
					maximum = a
			return maximum
		"recessif":
			var minimum: float = alleles[0]
			for a in alleles:
				if a < minimum:
					minimum = a
			return minimum
		"additif":
			var somme := 0.0
			for a in alleles:
				somme += a
			return somme
		"incomplet":
			var somme_incomplet := 0.0
			for a in alleles:
				somme_incomplet += a
			return somme_incomplet / alleles.size()
		_:
			push_error("expression.gd : mode d'expression '%s' non reconnu pour le gene '%s'" % [mode, nom_gene])
			return 0.0

static func _valeur_senescence(annees: float, modulateur_par_annee: float, mode: String, nom_courbe: String) -> float:
	match mode:
		"lineaire":
			return modulateur_par_annee * annees
		_:
			push_error("expression.gd : mode de senescence '%s' non implemente pour la courbe '%s' (seul 'lineaire' est ecrit en V1)" % [mode, nom_courbe])
			return 0.0

static func _lire_chemin(proprietes: Dictionary, chemin: String) -> Variant:
	if chemin == "":
		return null
	var courant: Variant = proprietes
	for morceau in chemin.split("."):
		if courant is Dictionary and courant.has(morceau):
			courant = courant[morceau]
		else:
			return null
	return courant

static func _ecrire_chemin(proprietes: Dictionary, chemin: String, valeur: float) -> void:
	var morceaux: Array = chemin.split(".")
	var courant: Dictionary = proprietes
	for i in range(morceaux.size() - 1):
		var morceau: String = morceaux[i]
		if not (courant.has(morceau) and courant[morceau] is Dictionary):
			push_error("expression.gd : chemin '%s' invalide -- segment '%s' absent ou non-Dictionary sur l'entite" % [chemin, morceau])
			return
		courant = courant[morceau]
	courant[morceaux[-1]] = valeur
