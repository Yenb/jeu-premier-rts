extends RefCounted

# Mecanisme du coeur : ACCOUPLEMENT -- deuxieme phase du cycle de
# reproduction (apres stade.gd, avant le futur gestation.gd). Deux individus
# MATURS et COMPATIBLES qui se PERCOIVENT accumulent une exposition ; une
# fois un SEUIL franchi, un etat de gestation est pose sur ceux des deux que
# la donnee autorise a gester -- IRREVERSIBLE. Ce fichier reprend le patron d'accumulation de
# charge.gd (monter tant qu'une cause est percue, comparer a un seuil) mais
# JAMAIS le retrait symetrique : une fois posee, gestation ne redescend
# jamais et bloque elle-meme tout nouvel accouplement (voir GARDE GESTATION
# plus bas) -- aucune notion de "poser"/"retirer" comme charge.gd.
#
# PROCESSUS PASSIF, HORS PIPELINE DE DECISION : comme charge.gd et
# lien_personnel_croissance.gd, ce fichier n'est jamais appele par
# agir.gd -- deux individus proches et compatibles se reproduisent SANS
# decision, sur la seule base de la perception. Ce fichier ne connait AUCUN
# nom de contenu ("colon", "espece") : le vocabulaire vit en donnee
# (proprietes.espece_reproduction, jamais un type compare en dur).
#
# COMPATIBILITE PAR PROPRIETE, JAMAIS PAR TYPE (doctrine ADN, voir
# CLAUDE.md) : deux individus sont compatibles si leurs
# proprietes.espece_reproduction (String) sont EGALES -- jamais une
# comparaison de type. MATURITE par proprietes.stade (pose par
# stade.gd:avancer, JAMAIS relu ici comme un age -- ce fichier ne compare
# jamais l'age directement) contre proprietes.stades_fertiles (Array de
# String sur le type, a cote de stades_config).
#
# MODE DE REPRODUCTION : ce fichier ne s'execute QUE pour
# proprietes.mode_reproduction == "sexuee" -- "asexuee"/"parthenogenese"
# (les deux autres valeurs attendues sur un type, jamais verifiees ici,
# aucune n'est une reference de catalogue) sautent cette phase par
# construction, un futur gestation.gd les traite directement. La garde rend
# silencieusement, jamais une alarme : ce fichier est appele sur TOUT le
# monde (comme charge.gd), la plupart des choses (arbre, bloc, feu) n'ont
# simplement rien a y faire.
#
# GARDE GESTATION : une entite qui porte deja proprietes.gestation est
# ignoree d'emblee, cote ENTITE ET cote PARTENAIRE PERCU -- pas de cooldown
# separe (decision Yael) : l'etat de gestation lui-meme empeche tout nouvel
# accouplement jusqu'a ce que le futur gestation.gd le consomme et retire
# la cle.
#
# ACCUMULATION (patron charge.gd adapte) : proprietes.accouplement_accumulateur
# (Dictionary FACULTATIF partenaire_id -> float, jamais declare sur
# data/types.json -- meme statut que
# lien_personnel_croissance.gd:lien_personnel_croissance_cooldown, un
# accumulateur propre a ce fichier) monte de taux_montee * delta A CHAQUE
# appel ou le partenaire reste percu, mature et compatible -- jamais
# reinitialise tant que le seuil n'est pas franchi (contrairement a
# charge.gd, qui redescend des que la cause cesse d'etre percue : ici, une
# exposition interrompue puis reprise CONTINUE d'accumuler, jamais remise a
# zero, parce que l'evenement vise est IRREVERSIBLE, pas un etat emotionnel
# reversible). Seuil et taux vivent dans le catalogue recu en parametre
# (data/reproduction.json), resolu par proprietes.reproduction_ref (forme
# A, meme patron que profil_saillance/lien_personnel_croissance_ref).
#
# LA FECONDATION EST SYMETRIQUE, LA GESTATION NE L'EST PAS. Au
# franchissement du seuil, les deux partenaires sont traites -- l'entite ET
# le partenaire percu, en mutant DIRECTEMENT partenaire.proprietes (meme
# reference que l'objet du monde : perception.gd ne copie jamais les choses
# qu'elle rend, voir monde.gd). Mais seul celui que role_gestation autorise
# recoit l'etat (voir _peut_gester) : LEQUEL porte est une propriete du
# type, jamais une convention d'appelant. Chaque gestation posee emporte
# l'id de l'autre et une COPIE PROFONDE (duplicate(true), meme garde
# qu'objet.gd:fabriquer) de ses genes_etat/marques_epigenetiques : ce sont
# ces copies que gestation.gd lira, jamais un etat vivant qui peut evoluer
# ou disparaitre. Une seule fecondation par appel : la boucle s'arrete au
# premier franchissement.
#
# entite : Dictionary { id, position, proprietes }, mute en place --
#   proprietes.accouplement_accumulateur (ecriture directe) et
#   proprietes.gestation (posee au franchissement, jamais retiree ici).
# perceptions : Array de { chose, ... } tel que rendu par
#   perception.gd:percevoir -- seul "chose" (id + proprietes, REFERENCE
#   vivante vers le monde) est lu ; "chose" peut aussi etre MUTEE (voir
#   plus haut) si le seuil est franchi.
# catalogue : Dictionary reproduction_ref -> { seuil_accouplement,
#   taux_montee } -- data/reproduction.json, jamais charge par ce fichier.
# delta : float, secondes ecoulees ce pas -- consomme uniquement par
#   l'accumulation (pas de decroissance dans ce fichier, voir ACCUMULATION
#   ci-dessus).
# tick_actuel : int, fourni par l'appelant, jamais une horloge interne a ce
#   fichier -- meme convention que delta/annees_par_seconde dans
#   senescence.gd. Aucun concept de tick global n'existe dans ce depot
#   (voir data/senescence.json:_note) ; ce fichier se contente d'enregistrer
#   la valeur recue dans gestation.accouplement_tick, un horodatage
#   INFORMATIF, jamais relu par ce fichier lui-meme -- meme statut que
#   marques_epigenetiques.<nom>.age_marque cote epigenetique.gd.
#
# Structurel vs facultatif (voir docs/design.md, "Propriete structurelle vs
# facultative") : proprietes.mode_reproduction est FACULTATIVE (defaut "",
# meme statut que etats cote charge.gd) ; differente de "sexuee" -> rendu
# silencieux, jamais une alarme. proprietes.gestation deja presente -> rendu
# silencieux (garde, pas une alarme). DES QUE mode_reproduction == "sexuee"
# (CAS DU COUPLE, meme precedent que jugement.gd :
# gain_jugement/plafond_jugement) : proprietes.reproduction_ref,
# proprietes.espece_reproduction ET proprietes.stades_fertiles deviennent
# STRUCTURELLES -- absence de l'une ou l'autre, push_error, entite ignoree
# ce tick. proprietes.stade reste FACULTATIVE (defaut "", meme statut que
# dans stade.gd lui-meme -- une chaine vide ne matche simplement aucun
# stade fertile, jamais une alarme). Cote PARTENAIRE PERCU, aucune de ces
# verifications n'alarme (silencieuse seulement) : le partenaire aura sa
# PROPRE alarme le jour ou il sera lui-meme l'entite traitee par ce
# fichier -- alarmer deux fois pour le meme trou de donnee serait du bruit.
# proprietes.accouplement_accumulateur est FACULTATIVE (defaut {}), meme
# statut que lien_personnel_croissance_cooldown.
#
# Resumabilite JSON stricte (voir docs/cadrage_corps_interne_colon.md) :
# accouplement_accumulateur est un Dictionary a feuilles float, gestation un
# Dictionary a feuilles String/Dictionary/int -- aucun Vector3, aucun
# Callable.

static func avancer(entite: Dictionary, perceptions: Array, catalogue: Dictionary, delta: float, tick_actuel: int) -> void:
	var proprietes: Dictionary = entite.get("proprietes", {})
	if proprietes.get("mode_reproduction", "") != "sexuee":
		return
	if proprietes.has("gestation"):
		return
	if not proprietes.has("reproduction_ref"):
		push_error("accouplement.gd : propriete structurelle 'reproduction_ref' absente de proprietes (mode_reproduction sexuee)")
		return
	if not proprietes.has("espece_reproduction"):
		push_error("accouplement.gd : propriete structurelle 'espece_reproduction' absente de proprietes (mode_reproduction sexuee)")
		return
	if not proprietes.has("stades_fertiles"):
		push_error("accouplement.gd : propriete structurelle 'stades_fertiles' absente de proprietes (mode_reproduction sexuee)")
		return
	var stades_fertiles: Array = proprietes.stades_fertiles
	if not stades_fertiles.has(proprietes.get("stade", "")):
		return
	var ref: String = proprietes.reproduction_ref
	if not catalogue.has(ref):
		push_error("accouplement.gd : reproduction_ref '%s' absente du catalogue" % ref)
		return
	var regle: Dictionary = catalogue[ref]
	var seuil: float = regle.get("seuil_accouplement", 0.0)
	var taux: float = regle.get("taux_montee", 0.0)
	var espece: String = proprietes.espece_reproduction

	var accumulateur: Dictionary = proprietes.get("accouplement_accumulateur", {})
	for entree in perceptions:
		var partenaire: Dictionary = entree.chose
		var p_proprietes: Dictionary = partenaire.get("proprietes", {})
		if p_proprietes.get("mode_reproduction", "") != "sexuee":
			continue
		if p_proprietes.has("gestation"):
			continue
		if p_proprietes.get("espece_reproduction", "") != espece:
			continue
		var p_stades_fertiles: Array = p_proprietes.get("stades_fertiles", [])
		if not p_stades_fertiles.has(p_proprietes.get("stade", "")):
			continue
		var valeur: float = accumulateur.get(partenaire.id, 0.0) + taux * delta
		accumulateur[partenaire.id] = valeur
		if valeur >= seuil:
			proprietes["accouplement_accumulateur"] = accumulateur
			_poser_gestation(proprietes, partenaire.id, p_proprietes, tick_actuel)
			_poser_gestation(p_proprietes, entite.id, proprietes, tick_actuel)
			return
	proprietes["accouplement_accumulateur"] = accumulateur

# DECISION LOCALE : chaque entite ne regarde que son propre role, jamais celui
# de l'autre -- aucun arbitrage cache entre les deux. "porteur" et "les_deux"
# gestent ; toute autre valeur, defaut compris, ne geste pas. Deux
# hermaphrodites gestent donc tous les deux : deux pontes, pas un doublon.
static func _peut_gester(proprietes: Dictionary) -> bool:
	var role: String = proprietes.get("role_gestation", "")
	return role == "porteur" or role == "les_deux"

static func _poser_gestation(proprietes: Dictionary, partenaire_id, partenaire_proprietes: Dictionary, tick_actuel: int) -> void:
	if not _peut_gester(proprietes):
		return
	proprietes["gestation"] = {
		"partenaire_id": partenaire_id,
		"partenaire_genes_etat": partenaire_proprietes.get("genes_etat", {}).duplicate(true),
		"partenaire_marques_epigenetiques": partenaire_proprietes.get("marques_epigenetiques", {}).duplicate(true),
		"accouplement_tick": tick_actuel,
	}
