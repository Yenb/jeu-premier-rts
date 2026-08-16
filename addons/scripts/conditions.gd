extends RefCounted

# Mecanisme du coeur : EVALUATEUR MULTI-CONDITIONS REJOUABLE. Extrait de
# scripts/objet.gd (_evaluer_emergences / _conditions_remplies, chantier
# "proprietes emergentes -- capacites conditionnelles a la fabrication"), ou
# la logique etait PRIVEE et enfermee dans le dernier pas de fabriquer() --
# donc appelable UNE SEULE FOIS par objet, a sa naissance. Ce fichier la rend
# appelable A CHAQUE TICK sur n'importe quelle chose deja construite (chantier
# "biomes -- conditions multiples -> type de terrain",
# audit_terrain_et_monde_prealable.md §2).
#
# CE QUE CE FICHIER AJOUTE A L'EXTRACTION : la REVERSIBILITE (retirer_si_faux
# ci-dessous). objet.gd ne faisait que MERGE -- une emergence posee a la
# fabrication ne pouvait plus jamais disparaitre, ce qui est correct pour une
# capacite issue de la matiere (un objet ne change jamais de composition, voir
# objet.gd "DENSITE EFFECTIVE") mais faux pour une condition d'ENVIRONNEMENT
# qui change en cours de partie (le climat se refroidit, la foret redevient
# toundra). Meme famille de bascule que charge.gd/seuil_etat.gd (pose ET
# retire selon le sens), mais un POINT D'ENTREE DIFFERENT : ni accumulation
# interne (charge.gd), ni comparaison d'UNE propriete a UN seuil
# (seuil_etat.gd, dont l'en-tete dit "UNE ENTREE, UN SEUL ETAT") -- ici N
# conditions en ET logique sur N proprietes differentes, aboutissant a un
# Dictionary de proprietes arbitraires plutot qu'a un nom d'etat.
#
# GENERIQUE : ce fichier ne connait aucun nom de contenu -- ni "biome", ni
# "desert", ni "humidite", ni "temperature", ni "canalise_mana". Chaque nom de
# propriete, chaque operateur, chaque seuil et chaque resultat vient du
# catalogue recu en parametre (data/emergences.json, data/biomes.json --
# jamais charges ici). Deux fonctions STATIQUES, sans etat, sans noeud,
# testables headless (scripts/test_conditions.gd).
#
# FORME D'UNE ENTREE DE CATALOGUE, inchangee depuis data/emergences.json :
#   { conditions: Array de { propriete, operateur, seuil }, resultat: Dictionary }
# "id" facultatif (nom lisible pour logs/tests, jamais lu par la logique).
# Operateurs supportes : ">=", "<=", ">", "<", "==".
#
# ---- remplies(proprietes, conditions) -> bool ----
# Rend true UNIQUEMENT si TOUTES les conditions sont vraies (ET logique,
# court-circuit). Array vide : vrai par vacuite -- jamais atteint via
# evaluer(), qui EXIGE la cle "conditions" (voir plus bas), mais contrat
# assume pour un appel direct.
# Une propriete absente de "proprietes" fait echouer SA condition (repli
# false, aucune alarme -- absence legitime), jamais un defaut 0.0 qui la
# ferait passer a tort : "densite <= seuil" sur un objet sans densite ne doit
# jamais reussir par accident. Meme philosophie que seuil_etat.gd:
# seuil_propriete absent, repli INF jamais franchi.
# Condition sans propriete/operateur/seuil, ou operateur inconnu :
# push_error nommant le defaut, la condition ECHOUE (jamais un defaut
# permissif).
#
# ---- evaluer(proprietes, catalogue, retirer_si_faux) -> Dictionary ----
# MUTE "proprietes" EN PLACE (decision Yael, question posee avant d'ecrire) :
# la reversibilite n'a de sens que sur l'etat PERSISTANT de la chose -- un
# Dictionary de retour fraichement construit n'a rien a retirer. Le retour est
# une TRACE, jamais l'etat : { poses: Dictionary (union des "resultat" des
# entrees vraies, telle qu'elle a ete fusionnee), retires: Array de String
# (cles REELLEMENT effacees) }. Un appelant qui ignore le retour obtient
# exactement le comportement historique d'objet.gd.
#
# retirer_si_faux (bool, FACULTATIF, defaut false) : DEFAUT NEUTRE, choisi
# pour que objet.gd:_evaluer_emergences garde son comportement EXACT apres
# extraction (merge seul, jamais de retrait). Sans ce drapeau, une emergence
# non declenchee EFFACERAIT une cle homonyme posee par le type ou un paquet
# (data/types.json) -- aucun contenu actuel n'est concerne, mais le contrat
# aurait change silencieusement pour tout contenu futur. Le cablage qui veut
# la reversibilite (un terrain reevalue chaque tick) passe true explicitement.
#
# DEUX PASSES DISJOINTES, jamais un parcours unique (decision Yael, bug reel
# trouve en preparant le chantier) : plusieurs entrees d'un meme catalogue
# posent souvent LA MEME CLE (quatre biomes posent tous "biome"). En une seule
# passe, une entree FAUSSE rencontree APRES une entree VRAIE retirerait ce que
# la vraie vient de poser -- une case remplissant les conditions de la foret se
# retrouverait sans aucun biome. Donc :
#   passe 1 -- lire seul : accumuler "poses" (entrees vraies) et les cles
#              candidates au retrait (entrees fausses), sans rien muter ;
#   passe 2 -- ecrire : effacer les candidates SAUF celles que "poses"
#              reclame, puis fusionner "poses".
# UNE ENTREE VRAIE GAGNE TOUJOURS SUR UNE ENTREE FAUSSE, quel que soit leur
# ordre dans le catalogue. Entre DEUX entrees vraies posant la meme cle, la
# DERNIERE du catalogue gagne (merge, ecrase les cles communes) -- ordre
# DECLARE EN DONNEE, deterministe, jamais l'ordre d'iteration d'un Dictionary.
# Ce fichier ne hierarchise jamais les entrees entre elles, exactement comme
# seuil_etat.gd laisse coexister "liquide" et "gaz" et laisse l'AFFICHAGE
# trancher.
#
# ASYMETRIE ASSUMEE DE LA TRACE : "retires" ne liste que les cles qui
# ETAIENT REELLEMENT PRESENTES sur "proprietes" avant ce passage -- effacer
# une cle absente est un non-evenement, et l'inscrire ferait clignoter une
# trace de banc a chaque tick. "poses" liste au contraire tout ce qui a ete
# fusionne, que la valeur ait change ou non : detecter un CHANGEMENT (pour
# une trace console "la case est devenue une toundra") est le travail de
# l'appelant, qui seul connait l'etat precedent -- ce fichier ne memorise
# rien d'un appel a l'autre (contrairement a seuil_etat.gd et sa
# "seuils_etat_memoire").
#
# NE MULTIPLIE RIEN, ET C'EST UNE FRONTIERE, PAS UN MANQUE : ce fichier POSE
# un Dictionary de proprietes, il ne module aucune grandeur existante. Une
# sensibilite GRADUEE (une valeur qui varie continument avec la condition
# plutot qu'un tout-ou-rien) n'est pas de son ressort et ne s'y ajoute pas --
# c'est le travail d'etat_effectif.gd (module une propriete) ou du cablage.
#
# Entree de catalogue sans cle "conditions" : push_error, entree IGNOREE --
# ni posee, ni comptee comme fausse, donc elle ne retire jamais rien. Jamais
# un repli sur [] qui se declencherait ALORS SANS AUCUNE CONDITION (verite par
# vacuite). "resultat" absent se replie legitimement sur {} (rien a fusionner,
# rien a retirer, chemin mort silencieux).
# Catalogue vide : chemin mort, "proprietes" inchangee, trace vide.

static func remplies(proprietes: Dictionary, conditions: Array) -> bool:
	for condition in conditions:
		if not (condition.has("propriete") and condition.has("operateur") and condition.has("seuil")):
			push_error("conditions.gd : condition incomplete (propriete/operateur/seuil requis), condition echouee")
			return false
		var nom_propriete: String = condition.propriete
		if not proprietes.has(nom_propriete):
			return false
		var valeur: float = float(proprietes[nom_propriete])
		var seuil: float = float(condition.seuil)
		match String(condition.operateur):
			">=":
				if not (valeur >= seuil):
					return false
			"<=":
				if not (valeur <= seuil):
					return false
			">":
				if not (valeur > seuil):
					return false
			"<":
				if not (valeur < seuil):
					return false
			"==":
				if not is_equal_approx(valeur, seuil):
					return false
			_:
				push_error("conditions.gd : operateur inconnu '%s', condition echouee" % condition.operateur)
				return false
	return true

static func evaluer(proprietes: Dictionary, catalogue: Array, retirer_si_faux: bool = false) -> Dictionary:
	# ---- Passe 1 : LIRE SEUL, ne rien muter (voir DEUX PASSES en tete) ----
	var poses: Dictionary = {}
	var candidats_retrait: Array = []
	for entree in catalogue:
		if not entree.has("conditions"):
			push_error("conditions.gd : entree sans 'conditions', ignoree")
			continue
		var resultat: Dictionary = entree.get("resultat", {})
		if remplies(proprietes, entree.conditions):
			poses.merge(resultat, true)
		elif retirer_si_faux:
			for cle in resultat:
				if not candidats_retrait.has(cle):
					candidats_retrait.append(cle)

	# ---- Passe 2 : ECRIRE. Une cle reclamee par une entree VRAIE n'est
	# jamais effacee par une entree FAUSSE, quel que soit l'ordre. ----
	var retires: Array = []
	for cle in candidats_retrait:
		if poses.has(cle):
			continue
		if not proprietes.has(cle):
			continue
		proprietes.erase(cle)
		retires.append(cle)
	proprietes.merge(poses, true)

	return {"poses": poses, "retires": retires}
