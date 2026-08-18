extends RefCounted

# BOÎTE À OUTILS -- pas un banc. Un banc est jetable : il éprouve une
# mécanique neuve puis meurt quand elle est prouvée (voir CARTE.md §3,
# docs/prototypes.md, « À quoi sert un banc »). Cette boîte ne meurt pas
# au même rythme : elle ACCUMULE l'éprouvé. Les bancs la TRAVERSENT --
# ils la préchargent (`const BancCommun = preload(...)`) et appellent ses
# fonctions -- ils ne la DUPLIQUENT plus. Ce fichier est le POINT DE VÉRITÉ
# UNIQUE de ce câblage : chaque outil ci-dessous a été recopié à l'identique
# dans plusieurs bancs avant d'y descendre, et n'y a plus qu'une seule
# version. AUCUNE règle de jeu ne vit ici, seulement du câblage.
#
# EXCEPTION, décidée par Yael (chantier « combustible propagé ») :
# `propagation.gd` (cœur) précharge cette boîte et appelle
# `resoudre_chantier` -- avant, il portait sa PROPRE copie du même geste
# (`for cle in patron: if not chose.proprietes.has(cle): ...`), jamais
# reliée à celle-ci. Les deux copies partageaient le même bug d'aliasing
# (voir `resoudre_chantier` plus bas) ; plutôt que corriger le bug deux
# fois, `propagation.gd` appelle désormais l'unique version corrigée --
# un mécanisme du cœur qui dépend de cette boîte est donc voulu ici,
# pas un oubli, la seule exception à « jamais lu par le cœur ».
#
# CRITÈRE D'ENTRÉE -- n'existait écrit nulle part avant ce fichier,
# formulé ici pour la première fois (voir CARTE.md §6, « Dette
# extinction/cendre »). Une mécanique n'entre dans cette boîte que si
# elle est :
#   - STATIQUE : aucun état retenu entre deux appels, tout est reçu en
#     paramètre, rien n'est lu ni écrit sur `self`.
#   - AUTONOME : précharge au besoin des mécanismes du cœur (Monde, Objet,
#     et désormais Agir pour choses_a_fuir -- même statut, ce ne sont pas
#     des bancs) -- jamais un banc, jamais un autre outil de cette boîte.
#   - PARAMÉTRÉE PAR DONNÉE : aucun nom de propriété, de type ou de
#     réserve en dur -- ces noms arrivent toujours en paramètre
#     (Dictionary de règles, clé de catalogue...), jamais écrits dans le
#     code.
# Ces trois conditions sont ce qui rend une mécanique COMPOSABLE : un
# banc neuf se monte en assemblant des briques de cette boîte plus un
# fichier de données, presque sans code neuf. `extinction.gd`, `flux.gd`,
# `depense.gd` ont déjà cette forme (RefCounted, uniquement du static,
# aucun preload d'un banc, aucun nom de contenu en dur) -- elles restent
# dans scripts/, elles ne descendent PAS ici : cette boîte porte le
# CÂBLAGE composable (comment un banc les invoque), jamais les mécaniques
# du cœur elles-mêmes (CARTE.md §2).
#
# NOTICE D'EXTENSION -- marche à suivre pour ajouter un outil ici, une
# prochaine session :
#   (a) écrire la static func en respectant le critère d'entrée ci-dessus ;
#   (b) ajouter sa ligne au REGISTRE ci-dessous ;
#   (c) ajouter son verrou dans test_banc_commun.gd ;
#   (d) l'inscrire là où la doc l'attend (CARTE.md, une fois ce fichier
#       référencé depuis les bancs -- pas fait ce tour-ci).
# Une fonction posée sans ces quatre n'est pas « ajoutée » -- elle est une
# dette de plus, exactement le défaut que cette boîte existe pour fermer.
#
# REGISTRE -- un outil par ligne (format exact : "# - nom : rôle.", une
# seule ligne physique par outil pour rester grep-able), verrouillé par
# test_registre_banc_commun.gd (modèle : test_docs.gd) : toute static
# func publique de ce fichier doit avoir sa ligne ici, et réciproquement.
# - objets_de : aplatit un Monde (Dictionary id -> {chose,type}) en Array nu de choses brutes, memes references, jamais des copies.
# - resoudre_chantier : pose les cles absentes d'un patron AU GRAIN DE LA SOUS-CLE (Dictionary traverses), dupliquees jamais par reference, sans rien ecraser.
# - agents_rythme : derive d'un Array nu la liste des agents d'extinction (choses portant "rythme"), aplatit position/rythme.
# - marquer_eteints : pose couleur et log sur chaque chose fraichement eteinte, garde structurelle sur noeuds/monde.par_id.
# - fabriquer_colon : construit le dictionnaire colon (position, attaches/forme/poids_verbes depuis decl, action_en_cours/action_precedente) sans dessiner ni enregistrer, type recu en parametre.
# - bouger_vers : deplacement borne VERS une cible-position, jamais de depassement.
# - bouger_selon : deplacement SELON une direction deja donnee, aucune cible a atteindre ni a depasser.
# - choses_a_fuir : filtre, parmi ce qui reste visible, les entrees d'origine proximite/jugement dont le verbe RESOLU pour cette seule entree est oriente "fuite" ; monde et catalogue_attaches_par_trait relayes a Agir.choisir, jamais deref ici.
# - verbe_action : resout "eteint"/"va vers" depuis travail_restant/transformation/portee_travail de la chose ciblee, jamais un rayon en dur.
# - monde_depuis : construit un Monde NEUF depuis des groupes de choses (type fixe, ou lu par chose) ou d'entrees deja typees (pour filtrer un monde existant) -- la seule facon pour un banc d'obtenir un Monde.

const Objet = preload("res://scripts/objet.gd")
const Agir = preload("res://scripts/agir.gd")
const Monde = preload("res://scripts/monde.gd")

static func objets_de(monde) -> Array:
	var objets: Array = []
	for entree in monde.choses.values():
		objets.append(entree.chose)
	return objets

# LE GRAIN DE COMPARAISON EST LA SOUS-CLE, JAMAIS LA CLE RACINE : deux
# Dictionary se traversent recursivement. Une chose qui porte deja un
# CONTENEUR (`reserves`, cinq canaux physiologiques sur tout type qui
# compose data/types.json:dynamique) recoit le canal que le patron lui
# ajoute SANS perdre les siens ; une chose qui porte deja CE canal precis
# le garde tel quel, sa calibration l'emporte (data/types.json:feu). A la
# racine, les deux cas sont indistinguables : le conteneur present fait
# sauter la cle entiere, la chose devient un chantier sans jamais recevoir
# de quoi se consumer, et rien n'alarme.
# Un ARRAY ne se fusionne JAMAIS element par element (voir
# data/types.json:colon._note, stades_config) : present il est laisse tel
# quel, absent il est pose duplique. Une valeur presente d'un autre type
# que celle du patron est laissee telle quelle SANS alarme -- ce fichier
# pose du cablage, il ne valide aucune forme (c'est test_lint_donnees.gd).
# Toute feuille reellement posee est COPIEE, jamais assignee telle quelle
# (CARTE.md §6, doctrine du meme nom).
static func resoudre_chantier(proprietes: Dictionary, patron: Dictionary) -> void:
	for cle in patron:
		var valeur = patron[cle]
		if proprietes.has(cle):
			if valeur is Dictionary and proprietes[cle] is Dictionary:
				resoudre_chantier(proprietes[cle], valeur)
			continue
		if valeur is Dictionary or valeur is Array:
			valeur = valeur.duplicate(true)
		proprietes[cle] = valeur

static func agents_rythme(monde: Array) -> Array:
	var agents: Array = []
	for chose in monde:
		if chose.proprietes.has("rythme"):
			agents.append({"position": chose.position, "rythme": chose.proprietes.rythme})
	return agents

static func marquer_eteints(
	eteints: Array,
	noeuds: Dictionary,
	monde,
	couleur: Color,
	temps_ecoule: float,
) -> void:
	for id in eteints:
		if not noeuds.has(id) or monde.par_id(id) == null:
			push_error("marquer_eteints: id '%s' absent de noeuds ou du monde" % id)
			continue
		noeuds[id].color = couleur
		print("t=%.1f %s eteint par les colons" % [temps_ecoule, id])

# type recu en parametre -- jamais "colon" en dur ici (ce fichier n'est pas
# un banc, l'exception "banc jetable peut nommer une categorie" de
# CLAUDE.md ne s'y applique pas) : chaque banc appelant passe la sienne
# ("colon" pour banc_p1.gd/banc_feu.gd aujourd'hui).
static func fabriquer_colon(nom: String, type: String, decl: Dictionary, catalogue_types: Dictionary) -> Dictionary:
	var pos: Array = decl.get("position", [0.0, 0.0, 0.0])
	var position3 := Vector3(pos[0], pos[1], pos[2])
	var colon := Objet.fabriquer(nom, type, position3, catalogue_types)
	colon.proprietes["attaches"] = decl.get("attaches", [])
	colon.proprietes["forme"] = decl.get("forme", {})
	colon.proprietes["poids_verbes"] = decl.get("poids_verbes", {})
	colon["action_en_cours"] = {}
	colon["action_precedente"] = "__jamais__"
	return colon

static func bouger_vers(position: Vector3, cible: Vector3, vitesse: float, delta: float) -> Vector3:
	var vers: Vector3 = cible - position
	var dist: float = vers.length()
	if dist < 1.0:
		return position
	var pas: float = min(dist, vitesse * delta)
	return position + vers.normalized() * pas

# Soeur de bouger_vers, PAS une variante : bouger_vers avance VERS une
# cible-position (borne le pas a la distance restante, ne depasse jamais) ;
# bouger_selon avance SELON une direction deja donnee (Fuite.direction) --
# aucune cible a atteindre ni a depasser, un pas plein tant qu'une
# direction existe.
static func bouger_selon(position: Vector3, direction: Vector3, vitesse: float, delta: float) -> Vector3:
	if direction == Vector3.ZERO:
		return position
	return position + direction.normalized() * vitesse * delta

# Cablage du verbe s_eloigner (chantier "fuite") : parmi ce qui reste
# VISIBLE (Dominance.visibles, ce que le colon ecrase deja vers le bas),
# ne retient que les entrees d'origine PROXIMITE (cle "chose" -- une
# chose reelle et sa position, jamais une saillance d'attache qui n'en
# porte aucune) dont le verbe RESOLU POUR CETTE SEULE ENTREE est oriente
# "fuite" dans orientations (data/orientations.json). Resout par entree
# via Agir.choisir([entree], ...) -- jamais une reimplementation du
# pesage poids_verbes (agir.gd) : sur une liste a un seul element,
# choisir() delegue directement a sa resolution de propriete, sans
# inertie. Rend l'Array { position, saillance } que Fuite.direction
# attend -- aucun nom de verbe ("s_eloigner") n'apparait ici, seulement
# la table orientations. Entrees d'origine JUGEMENT (banc_feu.gd) portent
# aussi "chose" (meme forme que proximite) : ce filtre ne distingue pas
# les deux origines, aucun cas particulier a ajouter. monde : transmis
# tel quel a Agir.choisir (parametre desormais obligatoire, voir agir.gd),
# jamais dereference ici -- seul agir.gd sait s'en servir (reinjection de
# cible engagee), ce fichier ne fait que le relayer.
# catalogue_attaches_par_trait (PHASE 5 etape 4/4 piece 2/3, defaut {}) :
# relaye tel quel a Agir.choisir, meme statut que monde ci-dessus -- un
# catalogue vide laisse AttacheParTrait inerte (voir agir.gd, "ATTACHE PAR
# TRAIT"), aucun risque pour un appelant qui ne le passe pas.
static func choses_a_fuir(
	visibles: Array,
	colon: Dictionary,
	catalogue_actions: Dictionary,
	orientations: Dictionary,
	monde,
	catalogue_attaches_par_trait: Dictionary = {},
) -> Array:
	var choses: Array = []
	for entree in visibles:
		if not entree.has("chose"):
			continue
		var resolue: Dictionary = Agir.choisir([entree], colon, catalogue_actions, monde, {}, catalogue_attaches_par_trait)
		if orientations.get(resolue.get("action", ""), "declencheur") != "fuite":
			continue
		choses.append({"position": entree.position, "saillance": entree.saillance})
	return choses

# Resout le meme couple transformation/portee_travail que
# extinction.gd:avancer -- jamais rayon_extinction (donnee morte, purgee).
# chose peut etre null (decision sans "chose" et sans menace active, voir
# scripts/ciblage.gd:viser) ; une chose sans travail_restant > 0.0 n'est
# simplement pas (ou plus) un chantier -- legitime, aucune alerte. En
# revanche une chose EN chantier (travail_restant > 0.0) sans
# "transformation" resolue, ou dont l'entree resolue ne porte pas
# "portee_travail", est structurellement anormale : push_error, jamais un
# 0.0 silencieux qui se confondrait avec "hors de portee".
static func verbe_action(colon: Dictionary, cible: Vector3, chose, transformations: Dictionary) -> String:
	var dist: float = colon.position.distance_to(cible)
	if chose == null:
		return "va vers"
	var proprietes: Dictionary = chose.proprietes
	var restant: float = proprietes.get("travail_restant", 0.0)
	if restant <= 0.0:
		return "va vers"
	if not proprietes.has("transformation"):
		push_error("verbe_action : chose '%s' porte travail_restant sans 'transformation'" % chose.id)
		return "va vers"
	var cle: String = proprietes.transformation
	if not transformations.has(cle):
		push_error("verbe_action : transformation '%s' absente du catalogue (chose '%s')" % [cle, chose.id])
		return "va vers"
	var transfo: Dictionary = transformations[cle]
	if not transfo.has("portee_travail"):
		push_error("verbe_action : entree '%s' sans 'portee_travail' (chose '%s')" % [cle, chose.id])
		return "va vers"
	var portee: float = transfo.portee_travail
	return "eteint" if dist <= portee else "va vers"

# LE MONDE EST UNE VUE, JAMAIS UN STOCK -- et c'est ce qui rend inutile
# toute fonction de retrait sur monde.gd (voir son en-tete). Un banc tient
# deja ses propres listes (colons, animaux, cases...) ; ce qui DOIT
# disparaitre n'est simplement plus dans la liste au moment ou le Monde est
# construit. Rien n'est jamais retire : ce qui reste est RE-AJOUTE PAR
# REFERENCE, donc positions, reserves et etats survivent intacts.
#
# CE QUE CET OUTIL FERME : ces trois lignes etaient recopiees dans vingt-sept
# endroits, chacun avec sa propre boucle. Un banc n'a plus a fabriquer un
# Monde lui-meme -- scripts/test_banc_commun.gd refuse tout `Monde.new()`
# ecrit dans le corps d'une fonction de banc.
#
# groupes : Array de { choses: Array, type: String, type_depuis: String }.
#   "type" est le type FIXE de tout le groupe. "type_depuis" nomme, a la
#   place, la cle qui porte le type SUR CHAQUE CHOSE -- cherchee d'abord
#   dans `proprietes`, sinon a la racine de la chose (meme ordre que
#   couplage.gd:satisfait_par), defaut "" si absente des deux. Les deux
#   ensemble : "type_depuis" gagne, il est plus precis. Aucun nom de
#   contenu n'est ecrit ici, ils arrivent tous en parametre.
# SECONDE FORME, pour FILTRER un monde existant : un groupe peut porter
#   "entrees" au lieu de "choses" -- un Array de { chose, type } a la forme
#   exacte de monde.choses.values(), chaque entree portant deja son type.
#   L'appelant construit la liste de ce qui RESTE ; rien n'est jamais retire.
# Un groupe sans "choses" ni "entrees" alarme et est saute -- jamais un Monde
# silencieusement incomplet.
static func monde_depuis(groupes: Array) -> Variant:
	var monde = Monde.new()
	for groupe in groupes:
		if not (groupe is Dictionary) or not (groupe.has("choses") or groupe.has("entrees")):
			push_error("monde_depuis : groupe sans 'choses' ni 'entrees' -- %s" % str(groupe))
			continue
		if groupe.has("entrees"):
			for entree in groupe.entrees:
				monde.ajouter(entree.chose, String(entree.type), entree.chose.position)
			continue
		var fixe: String = String(groupe.get("type", ""))
		var depuis: String = String(groupe.get("type_depuis", ""))
		for chose in groupe.choses:
			var type := fixe
			if depuis != "":
				var proprietes: Dictionary = chose.get("proprietes", {})
				if proprietes.has(depuis):
					type = String(proprietes[depuis])
				else:
					type = String(chose.get(depuis, ""))
			monde.ajouter(chose, type, chose.position)
	return monde
