extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_affordances_portage.tscn, PAS la
# scene principale -- run/main_scene reste banc_p1, coexiste avec les autres
# bancs). Chantier « portage + force + stabilisation »
# (audit_affordances_prealable.md, lignes 7, 8 et 9 -- les trois au verdict
# CABLABLE ; confirme a l'ecriture : AUCUN mecanisme du coeur touche ni cree).
#
# CE QU'ON DOIT VOIR : trois chantiers cote a cote, chacun rouge tant qu'il
# manque quelque chose, vert des que la condition est remplie, gris une fois
# accompli. A GAUCHE un TRONC qui demande de la FORCE : le colosse seul le
# souleve, un faible seul n'y arrive pas, mais les deux faibles ensemble y
# arrivent. AU MILIEU une ECHELLE qui demande DEUX MAINS : le colosse est
# largement assez fort et reste bloque, parce qu'une echelle a deux bouts --
# il faut lui amener n'importe quel second porteur, meme faible. A DROITE une
# ENCLUME qui demande d'etre TENUE : un porteur seul est refuse, et il passe
# soit en amenant un second porteur, soit en restant a cote de l'ETAU, une
# piece de fer posee au sol qui ne travaille jamais et ne porte rien. Les
# labels affichent, sous chaque cible, les trois exigences et les trois totaux
# atteints ; sous chaque colon, sa force et sa stabilisation.
#
# COMMANDES : touches 1 / 2 / 3 selectionnent un colon (le carre selectionne
# s'eclaircit) ; CLIC GAUCHE le pose au point clique. Rien d'autre. Le clic ne
# calcule jamais rien (voir CLAUDE.md, Regle d'etat) -- il ne fait que
# deplacer, tout le reste est recalcule par avancer() au tick suivant.
#
# TROIS CHOSES QUE CE BANC EST LE PREMIER A FAIRE DANS LE DEPOT :
#
# (1) IL EST LE PREMIER APPELANT DE scripts/somme.gd:propriete. somme.gd etait
#     livre, teste, et n'avait AUCUN appelant de cette fonction -- son propre
#     en-tete l'annonce (« il existe pour que le CINQUIEME consommateur
#     n'ecrive pas une cinquieme copie »). Les deux appelants existants
#     (banc_marche_competence.gd, banc_economie.gd) n'utilisent que
#     somme.gd:reserves, la lecture PROFONDE. Ici c'est la lecture PLATE :
#     force et fournit_stabilisation sont des nombres poses a cote de
#     position, jamais sous « reserves » -- et c'est obligatoire, pas un
#     confort (somme.gd:_numerique alarme et fait contribuer 0.0 pour toute
#     valeur non numerique).
#
# (2) DEUX GATES SEPARES SUR LA MEME LISTE. La meme liste de porteurs est lue
#     DEUX FOIS et de DEUX FACONS : sa SOMME (Somme.propriete, contre
#     force_requise) et sa TAILLE (len, contre points_de_prise). C'est ce qui
#     rend l'echelle possible : le colosse a 1.8 de force pour 0.9 demandes et
#     reste refuse, parce que 1 porteur pour 2 points de prise. Un seul gate
#     composite (une force effective divisee par le nombre, par exemple)
#     n'aurait jamais pu produire ce refus-la. Les deux briques de la couche
#     LECTEUR (docs/design.md, « Les collectifs n'existent pas ») repondent a
#     deux questions differentes -- ici on pose litteralement les deux sur le
#     meme tas, et comptage.gd ne peut pas rendre la seconde (sa
#     valeur_reference vit dans le catalogue, donc statique : compter les
#     agents autour de CETTE cible-ci demanderait une entree de catalogue par
#     cible -- audit ligne 8). len() sur la liste deja construite la rend
#     gratuitement.
#
# (3) UN OBJET FOURNIT UNE GRANDEUR D'AIDE, EXACTEMENT COMME UN AGENT.
#     L'etau et le colon portent la MEME propriete (fournit_stabilisation),
#     et le gate ne demande jamais si un contributeur est vivant -- il somme.
#     Precedent qui rendait ca deja possible sans une ligne :
#     banc_commun.gd:agents_rythme ramasse TOUTE chose portant « rythme »,
#     sans le moindre test de type, et extinction.gd ne lit sur ses agents que
#     position et rythme. Ce banc pousse le geste d'un cran : l'etau ne porte
#     NI rythme NI force, donc il n'est ni agent ni porteur -- seulement
#     stabilisateur. Les trois roles sont distingues par ce que la chose
#     PORTE, jamais par ce qu'elle EST.
#
# LE GATE NE MET AUCUNE BRANCHE DANS LE COEUR. Quand une des trois conditions
# manque, le cablage n'appelle pas extinction.gd avec une liste vide d'agents
# « pour qu'il ne fasse rien » -- il ne construit simplement pas la liste :
# extinction.gd:avancer somme les rythme de ses agents et sort par `somme <=
# 0.0` sans avoir rien a savoir d'un refus. Aucune ligne d'extinction.gd n'est
# touchee, et aucune ne connait le mot « force ».
#
# LE CATALOGUE DE CHANTIERS EST LOCAL, ET SA REFERENCE NE S'APPELLE PAS
# « transformation ». extinction.gd recoit son catalogue EN PARAMETRE (4e
# argument) et n'a jamais exige que ce soit data/transformations.json. Le
# banc porte donc le sien (data/banc_affordances_portage.json:chantiers) et sa
# reference se nomme « chantier_ref » cote donnee : scripts/test_lint_donnees.
# gd:REFERENCES verifie tout champ nomme exactement « transformation » de
# data/*.json contre le catalogue PARTAGE, et une reference locale y
# rougirait. La recopie sous la cle de contrat attendue par extinction.gd se
# fait EN CODE, une fois, a la fabrication (voir CLE_TRANSFORMATION plus bas).
#
# DIRECTION DES TROIS COMPARAISONS : « >= », une exigence exactement atteinte
# est atteinte -- meme convention que portee.gd:en_portee (« <= »),
# volontairement PAS celle de seuil_etat.gd/charge.gd (strictement « > »). Ces
# deux-la comparent une grandeur qui MONTE en continu, ou l'egalite stricte
# est un instant sans duree ; ici on compare une capacite POSEE en donnee a
# une exigence POSEE en donnee, ou l'egalite est un cas nominal qu'un auteur
# de contenu ecrira exprès. Raison ecrite ici parce qu'elle ne se devine pas
# du code.
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge les trois fichiers et fabrique colons, cibles
#   et objets ; _unhandled_input porte la selection et le clic, et ne calcule
#   jamais rien ; _process appelle avancer(...) puis lit ses diagnostics pour
#   l'affichage et la console.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_affordances_portage.gd) : construire_colons /
#   construire_objets_locaux / porteurs_a_portee / stabilisateurs_a_portee /
#   evaluer_gates / avancer, plus les textes d'affichage et de log.
#
# AUCUN NOM DE PROPRIETE EN DUR : type_colon / propriete_force /
# propriete_stabilisation / propriete_force_requise / propriete_points_de_prise
# / propriete_stabilisation_requise / propriete_chantier_ref arrivent tous de
# data/banc_affordances_portage.json -- c'est ce qui permet au test de faire
# traverser le meme code par un domaine entierement invente. Les deux SEULS
# noms ecrits ici sont CLE_TRANSFORMATION et CLE_TRAVAIL_RESTANT : ce sont les
# cles de CONTRAT de extinction.gd (voir son en-tete), pas des noms de contenu
# du monde.

const Objet = preload("res://scripts/objet.gd")
const Portee = preload("res://scripts/portee.gd")
const Somme = preload("res://scripts/somme.gd")
const Extinction = preload("res://scripts/extinction.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")

# Cles de CONTRAT de scripts/extinction.gd, jamais des noms de contenu du
# monde (voir son en-tete : « travail_restant » et « transformation » sont ce
# qu'il lit sur une chose en chantier, quel que soit le domaine). Ecrites ici
# et nulle part ailleurs dans ce fichier.
const CLE_TRANSFORMATION := "transformation"
const CLE_TRAVAIL_RESTANT := "travail_restant"

const TAILLE_POLICE_LABEL := 13

var _config: Dictionary = {}
var _catalogue_types: Dictionary = {}
var _materiaux: Dictionary = {}
var _chantiers: Dictionary = {}

var _colons: Array = []
var _cibles: Array = []
var _objets: Array = []
var _choses: Array = []

var _selection: int = 0
var _temps: float = 0.0
var _satisfait_avant: Dictionary = {}
var _accompli_avant: Dictionary = {}

var _noeuds: Dictionary = {}
var _labels: Dictionary = {}
var _label_aide: Label

func _ready() -> void:
	_config = _charger_json("res://data/banc_affordances_portage.json")
	_catalogue_types = _charger_json("res://data/types.json")
	_materiaux = _charger_json("res://data/materiaux.json")
	_chantiers = _config.get("chantiers", {})

	_colons = construire_colons(_config, _catalogue_types)
	_cibles = construire_objets_locaux(_config.get("cibles", []), _materiaux, _config)
	_objets = construire_objets_locaux(_config.get("objets", []), _materiaux, _config)
	_choses = _colons + _cibles + _objets

	for cible in _cibles:
		_satisfait_avant[String(cible.id)] = false
		_accompli_avant[String(cible.id)] = false

	_construire_rendu()
	print(ligne_pose(_config))
	_rafraichir({})

func _unhandled_input(evenement: InputEvent) -> void:
	# Le clic et les touches ne font que DECLENCHER : aucune decision, aucun
	# calcul ici (voir CLAUDE.md, Regle d'etat -- ce qui est enferme dans
	# _unhandled_input regresse en silence). Tout le calcul vit dans avancer().
	if evenement is InputEventKey and evenement.pressed:
		var indice := -1
		if evenement.keycode == KEY_1:
			indice = 0
		elif evenement.keycode == KEY_2:
			indice = 1
		elif evenement.keycode == KEY_3:
			indice = 2
		if indice >= 0 and indice < _colons.size() and indice != _selection:
			_selection = indice
			print(ligne_selection(_temps, _colons[_selection]))
		return
	if not (evenement is InputEventMouseButton) or not evenement.pressed:
		return
	if evenement.button_index != MOUSE_BUTTON_LEFT:
		return
	if _selection < 0 or _selection >= _colons.size():
		return
	var pos := get_global_mouse_position()
	_colons[_selection].position = Vector3(pos.x, pos.y, 0.0)
	print(ligne_deplacement(_temps, _colons[_selection]))

func _process(delta: float) -> void:
	_temps += delta

	var resultat := avancer(_cibles, _choses, delta, _config, _chantiers)

	for id in resultat.diagnostics:
		var diag: Dictionary = resultat.diagnostics[id]
		var satisfait: bool = bool(diag.satisfait)
		if satisfait != bool(_satisfait_avant.get(id, false)):
			_satisfait_avant[id] = satisfait
			print(ligne_gate(_temps, String(id), diag))
	for id in resultat.accomplis:
		if bool(_accompli_avant.get(id, false)):
			continue
		_accompli_avant[id] = true
		print(ligne_accompli(_temps, String(id)))

	_rafraichir(resultat.diagnostics)

# ---- Fonctions PURES, testables headless (voir test_banc_affordances_portage.gd) ----

# Fabrique les colons depuis le catalogue PARTAGE (data/types.json), type recu
# en donnee (config.type_colon) -- jamais « colon » en dur. Chaque cle de la
# declaration autre que id/position est recopiee PAR-DESSUS les proprietes
# fabriquees : c'est ainsi que « force » prend sa valeur par colon alors que
# data/types.json:colon n'en porte qu'un defaut. Meme geste exact que
# banc_commun.gd:fabriquer_colon, qui ecrase deja attaches/forme/poids_verbes
# par la donnee locale du banc.
#
# rythme et vitesse ne sont PAS recopies ici : ils viennent du catalogue
# partage, comme dans tous les bancs. Une fabrication REFUSEE (Objet.fabriquer
# rend {}) laisse simplement le colon absent de la scene -- contrat explicite
# d'objet.gd, verifie avant de lire .id.
static func construire_colons(config: Dictionary, catalogue_types: Dictionary) -> Array:
	var colons: Array = []
	for decl in config.get("colons", []):
		var pos: Array = decl.position
		var colon := Objet.fabriquer(
			String(decl.id), String(config.type_colon),
			Vector3(float(pos[0]), float(pos[1]), float(pos[2])),
			catalogue_types)
		if colon.is_empty():
			continue
		_recopier_declaration(decl, colon.proprietes)
		colons.append(colon)
	return colons

# Fabrique les choses LOCALES au banc (cibles et objets) sur un catalogue
# construit a la volee, une entree par id -- patron banc_economie.gd:
# construire_ressources / banc_coupe.gd:fabriquer_cibles. La masse est DERIVEE
# de la composition et de data/materiaux.json par objet.gd, jamais recopiee en
# donnee de banc.
#
# Toute cle de la declaration autre que id/position/composition est recopiee
# telle quelle sur proprietes -- AUCUN nom de propriete n'est donc ecrit ici,
# ni force_requise, ni points_de_prise, ni fournit_stabilisation. La seule
# traduction faite au passage : la reference de chantier LOCALE
# (config.propriete_chantier_ref) est AUSSI posee sous la cle de contrat que
# extinction.gd resout (CLE_TRANSFORMATION) -- voir l'en-tete du fichier pour
# la raison (le linter verifie « transformation » contre le catalogue
# PARTAGE). Les deux cles coexistent : la locale reste lisible a l'ecran, la
# seconde est celle que le mecanisme lit.
static func construire_objets_locaux(declarations: Array, materiaux: Dictionary, config: Dictionary) -> Array:
	var catalogue: Dictionary = {}
	for decl in declarations:
		catalogue[String(decl.id)] = {"composition": decl.composition}
	var objets: Array = []
	var nom_chantier_ref := String(config.propriete_chantier_ref)
	for decl in declarations:
		var pos: Array = decl.position
		var objet := Objet.fabriquer(
			String(decl.id), String(decl.id),
			Vector3(float(pos[0]), float(pos[1]), float(pos[2])),
			catalogue, materiaux)
		if objet.is_empty():
			continue
		_recopier_declaration(decl, objet.proprietes)
		if objet.proprietes.has(nom_chantier_ref):
			objet.proprietes[CLE_TRANSFORMATION] = String(objet.proprietes[nom_chantier_ref])
		objets.append(objet)
	return objets

# Recopie une declaration de donnee sur des proprietes deja fabriquees, en
# sautant les trois champs qui decrivent l'objet lui-meme plutot qu'une
# propriete du monde (id/position sont hors proprietes ; composition est deja
# consommee par objet.gd) et les cles de commentaire. Duplication profonde des
# Dictionary/Array : sans elle, deux objets issus de la meme declaration
# partageraient le meme sous-dictionnaire (bug d'aliasing deja paye une fois,
# voir banc_commun.gd:resoudre_chantier).
static func _recopier_declaration(decl: Dictionary, proprietes: Dictionary) -> void:
	for cle in decl:
		var nom := String(cle)
		if nom.begins_with("_") or nom == "id" or nom == "position" or nom == "composition":
			continue
		var valeur = decl[cle]
		if valeur is Dictionary or valeur is Array:
			valeur = valeur.duplicate(true)
		proprietes[nom] = valeur

# La liste des PORTEURS d'une cible : les choses a portee_travail qui portent
# la propriete de force. Meme boucle exacte que extinction.gd:avancer (test de
# portee delegue a portee.gd, jamais recode), a ceci pres qu'on garde la LISTE
# au lieu de sommer un rythme -- c'est elle que les deux gates lisent ensuite,
# l'un par sa somme, l'autre par sa taille.
#
# La cible s'exclut elle-meme par son id : une chose qui porterait a la fois
# une exigence de force et de la force ne se porterait pas toute seule (la
# distance d'une chose a elle-meme est nulle, elle serait donc toujours a sa
# propre portee). Meme geste que perception.gd, qui exclut l'entite percevante
# par comparaison d'id.
static func porteurs_a_portee(cible: Dictionary, choses: Array, portee_travail: float, nom_force: String) -> Array:
	return _a_portee_portant(cible, choses, portee_travail, nom_force)

# La liste des STABILISATEURS d'une cible : les choses a portee_stabilisation
# qui portent la propriete de stabilisation. Rigoureusement la meme boucle que
# porteurs_a_portee ci-dessus, avec une autre portee et un autre nom de
# propriete -- et c'est tout ce qui separe un porteur d'un stabilisateur. Une
# chose peut etre les deux (un colon), une seule des deux (l'etau, qui ne
# porte pas de force), ou aucune des deux (un tas de pierres).
static func stabilisateurs_a_portee(cible: Dictionary, choses: Array, portee_stabilisation: float, nom_stabilisation: String) -> Array:
	return _a_portee_portant(cible, choses, portee_stabilisation, nom_stabilisation)

static func _a_portee_portant(cible: Dictionary, choses: Array, portee: float, nom_propriete: String) -> Array:
	var retenues: Array = []
	var id_cible := String(cible.id)
	for chose in choses:
		if String(chose.id) == id_cible:
			continue
		if not chose.proprietes.has(nom_propriete):
			continue
		if Portee.en_portee(cible.position, chose.position, portee):
			retenues.append(chose)
	return retenues

# LES TROIS GATES, poses cote a cote et JAMAIS composes en un seul nombre.
# Rend la decomposition complete pour que l'affichage et la console la
# relisent sans jamais rien recalculer (meme discipline que
# banc_economie.gd:poser_surcout_action / banc_faim_thermo.gd).
#
# force_totale : Somme.propriete sur les porteurs -- PREMIER appel reel de
# cette fonction dans le depot (voir en-tete, point 1). Elle ignore
# silencieusement une entite qui ne porte pas la grandeur, mais la liste est
# deja filtree dessus : le total et la taille parlent donc du MEME ensemble,
# ce qui est la condition pour que les deux gates soient comparables.
#
# nombre : len(porteurs), lu directement -- jamais comptage.gd, dont la
# valeur_reference vit dans le catalogue et serait donc statique (compter les
# agents autour de CETTE cible demanderait une entree de catalogue par cible,
# audit ligne 8).
#
# Les trois exigences sont FACULTATIVES sur la cible : leur absence retombe
# sur 0 (aucune exigence), un point neutre legitime -- une chose sans
# force_requise n'est pas une chose cassee, c'est une chose que n'importe qui
# peut travailler. Jamais une alarme.
static func evaluer_gates(cible: Dictionary, choses: Array, config: Dictionary, portee_travail: float) -> Dictionary:
	var nom_force := String(config.propriete_force)
	var nom_stabilisation := String(config.propriete_stabilisation)

	var porteurs := porteurs_a_portee(cible, choses, portee_travail, nom_force)
	var stabilisateurs := stabilisateurs_a_portee(
		cible, choses, float(config.portee_stabilisation), nom_stabilisation)

	var force_totale := Somme.propriete(porteurs, nom_force)
	var stabilisation_totale := Somme.propriete(stabilisateurs, nom_stabilisation)

	var proprietes: Dictionary = cible.proprietes
	var force_requise := float(proprietes.get(String(config.propriete_force_requise), 0.0))
	var points_de_prise := int(proprietes.get(String(config.propriete_points_de_prise), 0))
	var stabilisation_requise := float(proprietes.get(String(config.propriete_stabilisation_requise), 0.0))

	var force_ok := force_totale >= force_requise
	var prise_ok := porteurs.size() >= points_de_prise
	var stabilisation_ok := stabilisation_totale >= stabilisation_requise

	return {
		"porteurs": porteurs,
		"stabilisateurs": stabilisateurs,
		"force_totale": force_totale,
		"nombre": porteurs.size(),
		"stabilisation_totale": stabilisation_totale,
		"force_requise": force_requise,
		"points_de_prise": points_de_prise,
		"stabilisation_requise": stabilisation_requise,
		"force_ok": force_ok,
		"prise_ok": prise_ok,
		"stabilisation_ok": stabilisation_ok,
		"satisfait": force_ok and prise_ok and stabilisation_ok,
	}

# UN TICK COMPLET, l'ordre compris. Statique et sans noeud : le test rejoue
# EXACTEMENT ce que la scene execute, jamais une reconstitution parallele qui
# pourrait deriver (patron banc_economie.gd:avancer / banc_grief.gd:avancer).
# MUTE les cibles en place (travail_restant, via extinction.gd) ; rend les
# diagnostics par cible et les ids accomplis ce tick.
#
# extinction.gd est appele UNE FOIS PAR CIBLE, sur un monde a un seul element,
# parce que chaque cible a SA propre liste de porteurs -- sa signature ne
# prend qu'une liste d'agents pour tout le monde qu'on lui passe. Les agents
# sont derives par banc_commun.gd:agents_rythme, jamais construits a la main :
# l'etau, qui ne porte pas « rythme », n'y entre donc jamais, meme s'il etait
# a portee -- il stabilise, il ne travaille pas.
#
# Quand un gate manque, on n'appelle simplement PAS extinction.gd pour cette
# cible. Aucune branche « refus » n'existe cote mecanisme : c'est le cablage
# qui ne construit pas la liste (voir en-tete).
static func avancer(cibles: Array, choses: Array, delta: float, config: Dictionary, chantiers: Dictionary) -> Dictionary:
	var diagnostics: Dictionary = {}
	var accomplis: Array = []
	var nom_chantier_ref := String(config.propriete_chantier_ref)

	for cible in cibles:
		var ref := String(cible.proprietes.get(nom_chantier_ref, ""))
		var entree: Dictionary = chantiers.get(ref, {})
		var portee_travail := float(entree.get("portee_travail", 0.0))

		var diag := evaluer_gates(cible, choses, config, portee_travail)
		diagnostics[String(cible.id)] = diag
		if not bool(diag.satisfait):
			continue

		var agents := BancCommun.agents_rythme(diag.porteurs)
		for id in Extinction.avancer([cible], agents, delta, chantiers):
			accomplis.append(String(id))

	return {"diagnostics": diagnostics, "accomplis": accomplis}

# ---- Textes (aucune decision, seulement de la mise en forme) ----

static func texte_cible(cible: Dictionary, diag: Dictionary) -> String:
	var restant: float = float(cible.proprietes.get(CLE_TRAVAIL_RESTANT, 0.0))
	var etat: String = "accompli" if restant <= 0.0 else ("PRET" if bool(diag.get("satisfait", false)) else "bloque")
	return "%s [%s]\nforce %.2f / %.2f %s\nprise %d / %d %s\nstabilisation %.2f / %.2f %s\ntravail restant %.1f" % [
		cible.id, etat,
		float(diag.get("force_totale", 0.0)), float(diag.get("force_requise", 0.0)),
		_coche(bool(diag.get("force_ok", false))),
		int(diag.get("nombre", 0)), int(diag.get("points_de_prise", 0)),
		_coche(bool(diag.get("prise_ok", false))),
		float(diag.get("stabilisation_totale", 0.0)), float(diag.get("stabilisation_requise", 0.0)),
		_coche(bool(diag.get("stabilisation_ok", false))),
		max(0.0, restant),
	]

static func texte_colon(colon: Dictionary, config: Dictionary, selectionne: bool) -> String:
	return "%s%s\nforce %.2f\nstabilisation %.2f" % [
		colon.id, "  <-- selectionne" if selectionne else "",
		float(colon.proprietes.get(String(config.propriete_force), 0.0)),
		float(colon.proprietes.get(String(config.propriete_stabilisation), 0.0)),
	]

static func texte_objet(objet: Dictionary, config: Dictionary) -> String:
	return "%s\nstabilisation %.2f\n(ni force ni rythme)" % [
		objet.id,
		float(objet.proprietes.get(String(config.propriete_stabilisation), 0.0)),
	]

static func _coche(ok: bool) -> String:
	return "OK" if ok else "MANQUE"

static func ligne_pose(config: Dictionary) -> String:
	return "t=0.0 pose : %d colon(s), %d chantier(s), %d objet(s) -- portee de stabilisation %.0f" % [
		config.get("colons", []).size(), config.get("cibles", []).size(),
		config.get("objets", []).size(), float(config.portee_stabilisation),
	]

static func ligne_gate(t: float, id: String, diag: Dictionary) -> String:
	if bool(diag.satisfait):
		return "t=%.1f %s : PRET -- force %.2f/%.2f, prise %d/%d, stabilisation %.2f/%.2f" % [
			t, id,
			float(diag.force_totale), float(diag.force_requise),
			int(diag.nombre), int(diag.points_de_prise),
			float(diag.stabilisation_totale), float(diag.stabilisation_requise),
		]
	var manques: Array = []
	if not bool(diag.force_ok):
		manques.append("force %.2f < %.2f" % [float(diag.force_totale), float(diag.force_requise)])
	if not bool(diag.prise_ok):
		manques.append("prise %d < %d" % [int(diag.nombre), int(diag.points_de_prise)])
	if not bool(diag.stabilisation_ok):
		manques.append("stabilisation %.2f < %.2f" % [float(diag.stabilisation_totale), float(diag.stabilisation_requise)])
	return "t=%.1f %s : BLOQUE -- %s" % [t, id, ", ".join(manques)]

static func ligne_accompli(t: float, id: String) -> String:
	return "t=%.1f %s : chantier accompli" % [t, id]

static func ligne_selection(t: float, colon: Dictionary) -> String:
	return "t=%.1f selection -> %s" % [t, colon.id]

static func ligne_deplacement(t: float, colon: Dictionary) -> String:
	return "t=%.1f %s deplace en (%.0f, %.0f)" % [t, colon.id, colon.position.x, colon.position.y]

# ---- Rendu (impur, Node) -- aucune decision, seulement des noeuds. ----

func _draw() -> void:
	var fond: Array = _config.couleur_fond
	draw_rect(
		Rect2(Vector2.ZERO, Vector2(float(_config.terrain_largeur), float(_config.terrain_hauteur))),
		Color(float(fond[0]), float(fond[1]), float(fond[2])))

func _construire_rendu() -> void:
	for cible in _cibles:
		_creer_rendu(cible, float(_config.taille_cible), _couleur(_config.couleur_manque))
	for objet in _objets:
		_creer_rendu(objet, float(_config.taille_objet), _couleur(_config.couleur_objet))
	for colon in _colons:
		_creer_rendu(colon, float(_config.taille_colon), _couleur(_config.couleur_colon))

	var couche := CanvasLayer.new()
	add_child(couche)
	_label_aide = _creer_label(14)
	_label_aide.position = Vector2(10.0, 8.0)
	_label_aide.text = "touches 1/2/3 : choisir un colon -- clic gauche : le poser la"
	couche.add_child(_label_aide)

	var camera := Camera2D.new()
	camera.position = Vector2(float(_config.terrain_largeur), float(_config.terrain_hauteur)) / 2.0
	camera.zoom = Vector2(0.72, 0.72)
	camera.enabled = true
	add_child(camera)

func _creer_rendu(chose: Dictionary, taille: float, couleur: Color) -> void:
	var carre := ColorRect.new()
	carre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	carre.size = Vector2(taille, taille)
	carre.color = couleur
	add_child(carre)
	_noeuds[String(chose.id)] = carre

	var label := _creer_label(TAILLE_POLICE_LABEL)
	add_child(label)
	_labels[String(chose.id)] = label

func _creer_label(taille: int) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", taille)
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	label.add_theme_constant_override("outline_size", 4)
	return label

func _rafraichir(diagnostics: Dictionary) -> void:
	for cible in _cibles:
		var id := String(cible.id)
		var diag: Dictionary = diagnostics.get(id, {})
		var restant: float = float(cible.proprietes.get(CLE_TRAVAIL_RESTANT, 0.0))
		var couleur := _couleur(_config.couleur_accompli)
		if restant > 0.0:
			couleur = _couleur(_config.couleur_satisfait) if bool(diag.get("satisfait", false)) else _couleur(_config.couleur_manque)
		_placer(cible, float(_config.taille_cible), couleur, texte_cible(cible, diag))
	for objet in _objets:
		_placer(objet, float(_config.taille_objet), _couleur(_config.couleur_objet), texte_objet(objet, _config))
	for i in range(_colons.size()):
		var colon: Dictionary = _colons[i]
		var couleur := _couleur(_config.couleur_colon_selectionne) if i == _selection else _couleur(_config.couleur_colon)
		_placer(colon, float(_config.taille_colon), couleur, texte_colon(colon, _config, i == _selection))

func _placer(chose: Dictionary, taille: float, couleur: Color, texte: String) -> void:
	var id := String(chose.id)
	if not _noeuds.has(id):
		return
	var carre: ColorRect = _noeuds[id]
	var centre := Vector2(chose.position.x, chose.position.y)
	carre.position = centre - Vector2(taille, taille) / 2.0
	carre.color = couleur
	var label: Label = _labels[id]
	label.position = carre.position + Vector2(0.0, taille + 2.0)
	label.text = texte

func _couleur(brut: Array) -> Color:
	return Color(float(brut[0]), float(brut[1]), float(brut[2]))

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
