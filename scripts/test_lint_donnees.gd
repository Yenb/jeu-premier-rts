extends SceneTree

# Filet de securite au chargement : verrouille que toute reference String
# vers un catalogue (forme A -- une chose porte un CHAMP dont la valeur est
# une cle d'un autre fichier data/*.json, voir proximite.gd/extinction.gd/
# depense.gd) resout bien a une entree existante. Sans ce test, une
# reference orpheline (typo dans data/types.json:colon.profil_saillance
# pointant vers "fue" au lieu de "feu") n'est detectee qu'a l'execution du
# mecanisme qui la resout -- donc potentiellement jamais si aucun banc
# n'exerce ce chemin precis.
#
# DEUXIEME SCAN, INDEPENDANT DU PREMIER : "propriete orpheline"
# (tolerance_proprietes_orphelines = 0, audit prealable CLAUDE.md). Une
# reference orpheline (ci-dessus) est une VALEUR qui ne pointe nulle part ;
# une propriete orpheline est une CLE posee sur un paquet ou un type de
# data/types.json qu'aucun lecteur connu ne consulte jamais. L'exemple reel
# est data/types.json:feu.action : une cle copiee sur chaque instance de feu par
# Objet.fabriquer, jamais lue par aucun mecanisme, trouvee seulement a
# l'oeil. `_verifier_proprietes_orphelines` (plus bas) classe chaque
# propriete de data/types.json dans un de trois sorts : REGISTRE_PROPRIETES_LUES
# (un mecanisme du coeur la lit), PROPRIETES_CABLAGE_SEUL (un banc la lit,
# aucun mecanisme du coeur encore), PROPRIETES_DORMANTES_ACCEPTEES (personne
# ne la lit, fondation posee pour plus tard, nommee explicitement). Absente
# des trois : ECHEC.
#
# TROISIEME SCAN, INDEPENDANT DES DEUX AUTRES : "surcharge partielle d'un
# conteneur herite" -- contrat, registre et raison d'etre au-dessus de
# SURCHARGES_EN_BLOC_ACCEPTEES, plus bas.
#
# Entree : aucune -- decouvre tous les data/*.json sur le disque (DirAccess,
# motif *.json, aucun nom de fichier en dur), les parcourt recursivement, et
# resout chaque champ declare dans REFERENCES contre son catalogue cible.
# Sortie : "OK:" / exit 0 si toutes les references resolvent ; "ECHEC:" /
# exit 1 en nommant chaque reference fautive (fichier source, chemin du
# champ, valeur trouvee, catalogue cible) sinon. Ce test SIGNALE une
# reference orpheline, il ne la corrige jamais -- meme contrat que
# test_docs.gd, dont il reprend le patron.
#
# REFERENCES est la SEULE connaissance de contenu que porte ce fichier.
# Ajouter une reference forme A de plus au depot = une entree de plus ici,
# zero ligne de code de parcours a toucher. "racine" vaut "" quand les
# entrees vivent a la racine du catalogue (profils_saillance.json,
# seuils_combustible.json, materiaux.json, canaux.json, deformations.json)
# et un nom de cle quand elles vivent en dessous (transformations.json : les
# references reelles vivent sous "transformations", a cote de "patron"/
# "patron_bloc" qui sont des GABARITS, pas des entrees resolues par cette
# reference).
#
# DEUX FORMES DE CHAMP, meme patron de reference derriere les deux :
# - "scalaire" (defaut, cle "forme" absente) : la valeur est une String
#   unique, verifiee telle quelle (profil_saillance, transformation,
#   seuils_ref, materiau).
# - "liste" (cle "forme" valant "liste") : la valeur est un Array de
#   String, CHAQUE element verifie individuellement contre le meme
#   catalogue/racine (canaux, deformation_sources). Un seul patron de
#   REFERENCE DE CATALOGUE dans tout le depot (voir docs/design.md,
#   "Propriete du monde vs champ de configuration technique") -- la forme
#   scalaire/liste est un detail de CARDINALITE (une seule reference vs
#   plusieurs), jamais un second patron.
#
# PORTEE, volontairement limitee (voir CLAUDE.md, audit prealable) :
# - Niveau 2 seulement (l'entree referencee existe) -- jamais niveau 3 (la
#   structure interne de l'entree resolue, ex. profils_saillance.json:<ref>
#   doit porter saillance_intrinseque ET portee_saillance). Chaque mecanisme
#   du coeur continue d'alarmer lui-meme sur ce qu'il sait lire -- dupliquer
#   ce savoir ici couplerait ce fichier au contrat de chaque mecanisme, un
#   cout qui grandit a chaque nouveau lecteur d'un catalogue existant.
# - Une valeur vide ("") est verifiee comme n'importe quelle autre chaine,
#   jamais presumee neutre : omettre la cle (ou, en forme liste, omettre
#   l'element) est la facon canonique d'exprimer "aucune reference" (voir
#   proximite.gd/depense.gd), pas d'y mettre une chaine vide. Aujourd'hui
#   aucune donnee du depot ne porte de chaine vide sur ces six champs.
# - Toute cle commencant par "_" est ignoree a la lecture recursive (jamais
#   descendue, jamais testee comme champ) -- un "_note" est un texte
#   descriptif, pas une donnee (voir data/materiaux.json:_note).
# - "deformation_etat" (l'ETAT interne mutable, { source: { cible: {
#   rapide, lent } } }) et "canaux_config" (les REGLAGES, { nom: { portee,
#   angle, sensibilite, seuil } }) ne sont JAMAIS verifies -- ce sont des
#   donnees, pas des references. Seules les LISTES qui les accompagnent
#   (deformation_sources, canaux) portent une reference de catalogue.
#
# Cas particulier : un catalogue cible absent du disque alarme
# distinctement ("catalogue introuvable") plutot que de faire planter le
# parcours sur un FileAccess.get_file_as_string() vide.

const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

const DOSSIER_DONNEES := "res://data"

const REFERENCES := [
	{ "champ": "profil_saillance", "catalogue": "res://data/profils_saillance.json", "racine": "" },
	{ "champ": "transformation", "catalogue": "res://data/transformations.json", "racine": "transformations" },
	{ "champ": "seuils_ref", "catalogue": "res://data/seuils_combustible.json", "racine": "" },
	{ "champ": "materiau", "catalogue": "res://data/materiaux.json", "racine": "" },
	{ "champ": "canaux", "catalogue": "res://data/canaux.json", "racine": "", "forme": "liste" },
	{ "champ": "deformation_sources", "catalogue": "res://data/deformations.json", "racine": "", "forme": "liste" },
	{ "champ": "comptage_ref", "catalogue": "res://data/comptages.json", "racine": "" },
	{ "champ": "lien_personnel_croissance_ref", "catalogue": "res://data/lien_personnel_croissance.json", "racine": "" },
	{ "champ": "etats_actifs", "catalogue": "res://data/etats.json", "racine": "", "forme": "liste" },
	{ "champ": "type_produit", "catalogue": "res://data/types.json", "racine": "" },
	{ "champ": "reproduction_ref", "catalogue": "res://data/reproduction.json", "racine": "" },
]

# REGISTRE DU SCAN "PROPRIETE ORPHELINE" -- source de verite du deuxieme
# scan (voir en-tete). Cle = nom de propriete tel qu'il apparait sur un
# paquet/type de data/types.json ; valeur = un lecteur reel qui prouve que
# la propriete n'est pas orpheline. DETTE ACCEPTEE (decision explicite de
# Yael) : ce registre n'est pas derive automatiquement du code, il se perime
# des qu'un mecanisme neuf lit une propriete sans qu'on l'y ajoute -- le
# cout de la detection, assume.
#
# Plusieurs entrees pointent vers un mecanisme qui ne contient JAMAIS le nom
# litteral de la propriete dans son code (ex. "brule" -> attaches.gd) : ce
# sont des PROPRIETES DU MONDE (docs/design.md, "Propriete du monde vs champ
# de configuration technique") lues generiquement via une table de donnees
# (menaces.json/jugements.json/types_choses.json/attaches_par_trait.json/
# actes_liants.json) -- le mecanisme cite est celui qui consulte cette table
# et regarde donc, a l'execution, si l'objet porte la propriete qu'elle nomme.
# Verifie par grep sur scripts/*.gd (hors banc_*.gd/test_*.gd) avant d'ecrire
# ce registre, pas suppose depuis la doc seule.
const REGISTRE_PROPRIETES_LUES := {
	"engagement": "couplage.gd",
	"reserves": "depense.gd",
	"liens_personnels": "lien_personnel.gd",
	"deformation_sources": "deformation.gd",
	"deformation_etat": "deformation.gd",
	"etats": "charge.gd",
	"genes_actifs": "expression.gd",
	"genes_etat": "expression.gd",
	"marques_epigenetiques": "epigenetique.gd",
	"age": "senescence.gd",
	"stade": "stade.gd",
	"stades_config": "stade.gd",
	"mode_reproduction": "accouplement.gd",
	"espece_reproduction": "accouplement.gd",
	"stades_fertiles": "accouplement.gd",
	"reproduction_ref": "accouplement.gd",
	"role_gestation": "accouplement.gd",
	"canaux": "perception.gd",
	"canaux_config": "perception.gd",
	"orientation": "perception.gd",
	"attaches": "attaches.gd",
	"rythme": "extinction.gd",
	"profil_saillance": "proximite.gd",
	"portee_propagation": "propagation.gd",
	"delai_propagation": "propagation.gd",
	"inflammable": "propagation.gd",
	"irremplacable": "attaches.gd",
	"notre_ouvrage": "attaches.gd",
	"brule": "attaches.gd",
	"cassable": "agir.gd",
	"dangereux": "agir.gd",
	"composition": "objet.gd",
	"masse": "objet.gd",
	"volume": "objet.gd",
	"densite": "objet.gd",
	"temperature": "temperature.gd",
}

# Lu par du CABLAGE DE BANC (jetable, §3 de CARTE.md), jamais par un
# mecanisme du coeur (§2) -- ni verrouille comme une fondation dormante
# (aucun mecanisme ne s'en approche), ni un vrai lecteur du moteur permanent.
# A PROMOUVOIR dans REGISTRE_PROPRIETES_LUES le jour ou un mecanisme du coeur
# (ex. un futur mouvement.gd) la consomme ; a REDESCENDRE en orpheline vraie
# si le dernier banc qui la lit disparait sans remplacant.
const PROPRIETES_CABLAGE_SEUL := [
	"vitesse", # BancCommun.bouger_vers/bouger_selon la recoit en simple
	           # parametre float -- c'est CHAQUE banc (banc_p1.gd,
	           # banc_feu.gd, banc_charge.gd, banc_animal.gd,
	           # banc_lien_personnel.gd, banc_vecu_inter_colon.gd,
	           # banc_genetique.gd) qui lit proprietes.vitesse pour la leur
	           # passer ; verifie par grep, aucun script hors banc_*.gd/
	           # test_*.gd ne la reference.
	"controlable", # chantier "controle direct du joueur" (2026-08-03,
	               # decision Yael) -- lu par scripts/banc_controle.gd
	               # (cablage seul) avant d'appeler ou non le pipeline de
	               # decision ; aucun mecanisme du coeur ne la lit.
	"ordre_joueur", # meme chantier -- pose/lu par scripts/banc_controle.gd
	                # seul, jamais par un mecanisme du coeur.
	"lie_au_joueur", # meme chantier -- pose par scripts/banc_controle.gd
	                 # seul, jamais lu par un mecanisme du coeur a ce jour.
	"force", # chantier "portage + force + stabilisation" (audit_affordances_
	         # prealable.md ligne 7) -- lue par scripts/banc_affordances_
	         # portage.gd seul, qui la somme via scripts/somme.gd:propriete et
	         # compare le total a une force_requise LOCALE au banc ; aucun
	         # mecanisme du coeur ne la lit (extinction.gd ne connait que
	         # "rythme"). A PROMOUVOIR le jour ou un mecanisme du coeur la
	         # consomme.
	"fournit_stabilisation", # meme chantier (ligne 9) -- lue par
	                         # scripts/banc_affordances_portage.gd seul, sommee
	                         # par scripts/somme.gd:propriete sur les choses a
	                         # portee sans jamais demander si le contributeur
	                         # est vivant (un etau et un colon la portent tous
	                         # deux). Aucun mecanisme du coeur ne la lit.
	"curiosite", # chantier "connaissance" (audit_affordances_prealable.md
	             # ligne 16) -- lue par scripts/banc_affordances_connaissance.gd
	             # seul, dans le gate arithmetique qui ecrit
	             # poids_verbes.experimenter. Aucun mecanisme du coeur ne la
	             # lit : agir.gd ne connait que poids_verbes, jamais la cause
	             # qui l'a ecrit.
]

# Personne ne la lit aujourd'hui, ni le coeur ni un banc -- fondation posee
# pour un mecanisme futur (voir docs/design.md, "objet_physique comme paquet
# fondateur"), verifiee dormante par grep sur tout scripts/*.gd. Nommee ici
# plutot que silencieusement toleree. "masse"/"volume"/"densite" (memes
# paquet) et "materiau" (data/materiaux.json) EN SONT SORTIES (chantier
# "densite effective calculee a la fabrication") : masse/volume/densite
# sont desormais lues ET ecrites par objet.gd:fabriquer (voir
# REGISTRE_PROPRIETES_LUES ci-dessus) ; "materiau" a disparu comme champ de
# data/types.json, remplace par "composition" (Array de { materiau,
# volume } -- "materiau" y survit comme cle IMBRIQUEE, toujours verifiee
# par la meme entree REFERENCES ci-dessus : _parcourir descend deja dans
# les Array/Dictionary, aucune ligne de scan a ajouter pour la retrouver
# nichee dans composition).
const PROPRIETES_DORMANTES_ACCEPTEES := [
]

# Contrat et sorties : CARTE.md section 6, entree objet.gd:fabriquer.
#
# CE REGISTRE DOIT RESTER VIDE -- la doctrine des compartiments
# (docs/design.md) ne laisse aucun effacement legitime. Une entree ici se
# retire en corrigeant la donnee, jamais en allongeant la liste.
const SURCHARGES_EN_BLOC_ACCEPTEES := {
}

# Cle "chemin_catalogue::racine" -> Dictionary d'entrees deja descendu sous
# "racine", ou null si le catalogue est introuvable/invalide -- calcule une
# seule fois par catalogue quel que soit le nombre de references qui le visent.
var _cache_catalogues: Dictionary = {}

func _init() -> void:
	var fichiers := _decouvrir_donnees()
	fichiers.sort()

	for chemin_fichier in fichiers:
		var texte := FileAccess.get_file_as_string(chemin_fichier)
		var contenu: Variant = JSON.parse_string(texte)
		if not (contenu is Dictionary or contenu is Array):
			verif.v(false, "test_lint_donnees.gd : %s -- JSON invalide (ni Dictionary ni Array a la racine)" % chemin_fichier)
			continue
		_parcourir(chemin_fichier, contenu, "")

	_verifier_proprietes_orphelines()
	_verifier_surcharges_partielles(fichiers)

	if verif.echecs() > 0:
		print("ECHEC: %d probleme(s) (reference(s) de catalogue fautive(s) et/ou propriete(s) orpheline(s))" % verif.echecs())
		quit(1)
		return
	var champs: Array = []
	for reference in REFERENCES:
		champs.append(reference.champ)
	print("OK: toutes les references de catalogue (%s) dans data/*.json resolvent a une entree existante, " % ", ".join(champs) +
		"aucune propriete de data/types.json n'est orpheline (tolerance_proprietes_orphelines = 0), " +
		"et aucun type n'efface en silence une sous-cle d'un conteneur herite")
	quit(0)

# Scan "propriete orpheline" (voir en-tete) : chaque propriete d'un
# paquet/type de data/types.json doit apparaitre dans REGISTRE_PROPRIETES_LUES,
# PROPRIETES_CABLAGE_SEUL ou PROPRIETES_DORMANTES_ACCEPTEES. Une seule
# profondeur descendue par entree -- "reserves"/"etats"/"canaux_config"/
# "deformation_etat"/"genes_etat"/"marques_epigenetiques" SONT la propriete
# (un conteneur generique lu sans nom de canal en dur, voir depense.gd/
# charge.gd/perception.gd/deformation.gd) : leur contenu interne n'est
# jamais descendu par ce scan, tout comme "canaux_config"/"deformation_etat"
# ne sont jamais descendus par le scan de references ci-dessus.
func _verifier_proprietes_orphelines() -> void:
	var chemin := "res://data/types.json"
	var contenu: Variant = JSON.parse_string(FileAccess.get_file_as_string(chemin))
	if not (contenu is Dictionary):
		verif.v(false, "test_lint_donnees.gd : %s -- JSON invalide, scan proprietes orphelines saute" % chemin)
		return

	var proprietes_vues: Dictionary = {}
	for nom_entree in contenu:
		if String(nom_entree).begins_with("_"):
			continue
		var entree: Variant = contenu[nom_entree]
		if not (entree is Dictionary):
			continue
		for cle in entree:
			var cle_str := String(cle)
			# "_note" est un texte descriptif (voir _parcourir ci-dessus) ;
			# "herite" est un champ de configuration CONSOMME ET RETIRE par
			# objet.gd:fabriquer avant que "proprietes" existe -- il ne
			# survit jamais sur un objet fabrique, rien a chercher comme
			# lecteur en aval.
			if cle_str.begins_with("_") or cle_str == "herite":
				continue
			proprietes_vues[cle_str] = true

	for propriete in proprietes_vues:
		if REGISTRE_PROPRIETES_LUES.has(propriete) or PROPRIETES_CABLAGE_SEUL.has(propriete) \
				or PROPRIETES_DORMANTES_ACCEPTEES.has(propriete):
			continue
		verif.v(false, "test_lint_donnees.gd : data/types.json > %s -- propriete orpheline, absente de REGISTRE_PROPRIETES_LUES/PROPRIETES_CABLAGE_SEUL/PROPRIETES_DORMANTES_ACCEPTEES" % propriete)

# Scan "surcharge partielle" (voir en-tete du registre). Les PAQUETS vivent
# tous dans data/types.json ; les TYPES qui les composent peuvent vivre dans
# n'importe quel data/*.json (un banc declare ses types localement). Le
# parcours descend donc partout et traite tout Dictionary portant "herite".
func _verifier_surcharges_partielles(fichiers: Array) -> void:
	var paquets: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/types.json"))
	if not (paquets is Dictionary):
		verif.v(false, "test_lint_donnees.gd : data/types.json illisible, scan surcharges saute")
		return
	for chemin_fichier in fichiers:
		var contenu: Variant = JSON.parse_string(FileAccess.get_file_as_string(chemin_fichier))
		_chercher_types(chemin_fichier, contenu, paquets, "")

func _chercher_types(fichier: String, noeud: Variant, paquets: Dictionary, nom: String) -> void:
	if noeud is Array:
		for element in noeud:
			_chercher_types(fichier, element, paquets, nom)
		return
	if not (noeud is Dictionary):
		return
	if noeud.get("herite", null) is Array:
		_verifier_un_type(fichier, nom, noeud, paquets)
	for cle in noeud:
		if String(cle).begins_with("_"):
			continue
		_chercher_types(fichier, noeud[cle], paquets, String(cle))

func _verifier_un_type(fichier: String, nom_type: String, type: Dictionary, paquets: Dictionary) -> void:
	for nom_paquet in type.herite:
		var paquet: Variant = paquets.get(nom_paquet, null)
		if not (paquet is Dictionary):
			continue
		for cle in paquet:
			var cle_str := String(cle)
			if cle_str.begins_with("_"):
				continue
			var herite_valeur: Variant = paquet[cle]
			# Seul un conteneur NON VIDE peut perdre quelque chose. Un
			# Dictionary vide n'a rien a effacer, un Array est remplace en
			# bloc par convention (voir data/types.json:colon, stades_config).
			if not (herite_valeur is Dictionary) or herite_valeur.is_empty():
				continue
			var surcharge: Variant = type.get(cle_str, null)
			if not (surcharge is Dictionary):
				continue
			var manquantes: Array = []
			for sous_cle in herite_valeur:
				if not surcharge.has(sous_cle):
					manquantes.append(String(sous_cle))
			if manquantes.is_empty():
				continue
			var adresse := "%s > %s > %s" % [fichier, nom_type, cle_str]
			if SURCHARGES_EN_BLOC_ACCEPTEES.has(adresse):
				continue
			manquantes.sort()
			verif.v(false, "test_lint_donnees.gd : %s -- surcharge partielle d'un conteneur herite de '%s' : %s EFFACEE(S) en silence. Redeclarer le conteneur entier, ou inscrire cette adresse dans SURCHARGES_EN_BLOC_ACCEPTEES en disant pourquoi." %
				[adresse, nom_paquet, str(manquantes)])

func _decouvrir_donnees() -> Array:
	var fichiers: Array = []
	var dir := DirAccess.open(DOSSIER_DONNEES)
	if dir == null:
		push_error("test_lint_donnees.gd : impossible d'ouvrir %s" % DOSSIER_DONNEES)
		return fichiers
	dir.list_dir_begin()
	var nom := dir.get_next()
	while nom != "":
		if not dir.current_is_dir() and nom.ends_with(".json"):
			fichiers.append("%s/%s" % [DOSSIER_DONNEES, nom])
		nom = dir.get_next()
	dir.list_dir_end()
	return fichiers

# Descend recursivement dans un Dictionary/Array JSON deja parse. Pour
# chaque couple (cle, valeur) d'un Dictionary dont la valeur est une String
# OU un Array, verifie si "cle" matche un champ declare dans REFERENCES.
# "chemin" est le fil d'Ariane affiche dans un message d'echec, jamais relu
# par ce fichier.
func _parcourir(fichier_source: String, noeud: Variant, chemin: String) -> void:
	if noeud is Dictionary:
		for cle in noeud:
			if String(cle).begins_with("_"):
				continue
			var valeur: Variant = noeud[cle]
			var sous_chemin: String = "%s > %s" % [chemin, cle] if chemin != "" else String(cle)
			if valeur is String or valeur is Array:
				_verifier_si_reference(fichier_source, sous_chemin, cle, valeur)
			_parcourir(fichier_source, valeur, sous_chemin)
	elif noeud is Array:
		for i in range(noeud.size()):
			_parcourir(fichier_source, noeud[i], "%s[%d]" % [chemin, i])
	# String/float/int/bool/null : rien de plus a descendre.

# "valeur" est soit une String (forme scalaire), soit un Array (forme
# liste) -- le type effectivement rencontre doit matcher la "forme"
# declaree dans REFERENCES pour ce champ, sinon ce n'est pas la reference
# attendue et rien n'est verifie (pas d'alarme sur un homonyme mal forme,
# ce fichier ne devine jamais une intention).
func _verifier_si_reference(fichier_source: String, chemin: String, cle: String, valeur: Variant) -> void:
	for reference in REFERENCES:
		if reference.champ != cle:
			continue
		var forme: String = reference.get("forme", "scalaire")
		if forme == "liste":
			if valeur is Array:
				for i in range(valeur.size()):
					var element: Variant = valeur[i]
					if element is String:
						_verifier_contre_catalogue(fichier_source, "%s[%d]" % [chemin, i], element, reference)
		elif valeur is String:
			_verifier_contre_catalogue(fichier_source, chemin, valeur, reference)
		return

func _verifier_contre_catalogue(fichier_source: String, chemin: String, valeur: String, reference: Dictionary) -> void:
	var entrees: Variant = _resoudre_catalogue(reference.catalogue, reference.racine)
	if entrees == null:
		verif.v(false, "test_lint_donnees.gd : %s (%s = \"%s\") -- catalogue introuvable : %s" %
			[fichier_source, chemin, valeur, reference.catalogue])
		return
	verif.v(entrees.has(valeur), "test_lint_donnees.gd : %s (%s = \"%s\") -- reference absente de %s%s" %
		[fichier_source, chemin, valeur, reference.catalogue,
			(" > %s" % reference.racine) if reference.racine != "" else ""])

# Charge et met en cache un catalogue, deja descendu sous "racine". Rend
# null si le fichier est absent, si son JSON est invalide, ou si "racine"
# (non vide) n'y designe pas un Dictionary -- les trois cas remontent comme
# "catalogue introuvable" par l'appelant, jamais un plantage.
func _resoudre_catalogue(chemin_catalogue: String, racine: String) -> Variant:
	var cle_cache: String = "%s::%s" % [chemin_catalogue, racine]
	if _cache_catalogues.has(cle_cache):
		return _cache_catalogues[cle_cache]

	var resultat: Variant = null
	if FileAccess.file_exists(chemin_catalogue):
		var contenu: Variant = JSON.parse_string(FileAccess.get_file_as_string(chemin_catalogue))
		if contenu is Dictionary:
			if racine == "":
				resultat = contenu
			elif contenu.get(racine, null) is Dictionary:
				resultat = contenu[racine]

	_cache_catalogues[cle_cache] = resultat
	return resultat
