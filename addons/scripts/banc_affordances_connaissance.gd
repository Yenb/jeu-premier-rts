extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_affordances_connaissance.tscn, PAS
# la scene principale -- run/main_scene reste banc_p1). Chantier
# « connaissance » : lignes 13, 14, 15, 16 et 17 du tableau Affordances
# (audit_affordances_prealable.md, les cinq au verdict CABLABLE).
#
# COMPOSE HUIT MECANISMES DEJA FERMES, TOUS RIGOUREUSEMENT INCHANGES :
# perception.gd, croyance.gd, proximite.gd, dominance.gd, agir.gd, objet.gd,
# monde.gd, depense.gd, etat_duree.gd, lien_personnel.gd (+ banc_commun.gd).
# AUCUN .gd du coeur n'est ecrit ni modifie par ce chantier, et AUCUNE
# mecanique neuve n'est ecrite : un gameplay est une COMPOSITION, jamais une
# piece (CLAUDE.md, « Forme des prompts de tache »).
#
# ---------------------------------------------------------------------------
# CE QU'IL DOIT MONTRER -- une ligne de l'audit par point
# ---------------------------------------------------------------------------
# 13. SEUL LE MEDECIN SAIT. Le medecin SE SERT des choses a portee_usage, a SA
#     cadence, et le cablage appelle Croyance.corriger avec credibilite 1.0 --
#     l'experience directe. Il apprend que le fruit amer est toxique. L'apprenti
#     est trop loin pour s'en servir : il ne sait rien de lui-meme, et son
#     registre de croyances le dit (il croit encore le fruit comestible).
#     LA PROBABILITE DE L'AUDIT EST DEVENUE UNE CADENCE, jamais un tirage : il
#     n'existe AUCUN RNG dans le depot (CLAUDE.md, docs/design.md REGLE
#     ANTI-BRUIT), et croyance.gd n'a AUCUNE notion de temps propre -- observer()
#     n'a pas de delta. La cadence DOIT donc vivre au cablage (piege deja paye
#     par banc_graisse_accoutumance.gd sur Epigenetique.poser).
# 14. ON PEUT L'APPRENDRE A QUELQU'UN. Touche T : l'auteur verse TOUTES ses
#     croyances aux colons a portee_transmission, avec
#     credibilite = LienPersonnel.force(receveur, auteur) * fidelite_parole.
#     La certitude du receveur vaut gain_par_echec * credibilite, donc
#     STRICTEMENT SOUS celle de l'emetteur (qui tient la sienne d'une
#     credibilite 1.0). LA FIDELITE DEGRADE LA CERTITUDE, JAMAIS LA VALEUR --
#     corriger() recopie la valeur transmise telle quelle ; une transmission qui
#     DEFORMERAIT ce qui est dit n'existe pas dans le depot et serait un
#     mecanisme neuf (audit, ligne 14, limite dite). Le dogmatique ecoute et
#     refuse : resistance_par_certitude, dans le MECANISME, jamais ici.
#     CE BANC NE PASSE PAS PAR charge.gd : la contagion de maladie
#     (banc_maladie.gd) monte un canal par presence a portee ; la transmission
#     de savoir passe par Croyance.corriger, directement (audit, ligne 14).
# 15. IL CROIT QUE CA SOIGNE, CA EMPOISONNE. Le fruit devient toxique et PERD
#     la cle « comestible » -- il ne la met pas a false. Structurel, pas
#     cosmetique : observer() n'itere que les proprietes PRESENTES, une cle
#     retiree n'est donc jamais reobservee et la croyance perimee SURVIT.
#     Croyance.filtrer REMPLACE les proprietes que voient les quatre couches :
#     agir.gd resout « manger » exactement comme avant, sur une croyance fausse,
#     sans UNE ligne de mecanisme. Le colon mange, et il s'empoisonne.
# 16. UN COLON CURIEUX EXPERIMENTE. « experimenter » est un VERBE
#     (data/types_choses.json + poids_verbes), jamais un mecanisme. Le gate
#     composite (curiosite ET temps libre ET materiau) est ARITHMETIQUE :
#     poids_verbes.experimenter vaut 0.0 des qu'une condition manque, et
#     agir.gd:_verbe_par_poids exige p > 0.0 -- le verbe devient inchoisissable
#     sans qu'aucune branche ne soit ecrite (precedent ecrit noir sur blanc dans
#     data/deformations.json:competence_forge, « ce n'est pas un cas particulier
#     code, c'est la meme arithmetique lue a zero »). Le resultat de
#     l'experimentation est un Croyance.corriger a credibilite 1.0.
# 17. UN COLON ECRIT CE QU'IL SAIT. L'auteur fabrique un LIVRE en cours de
#     partie (Objet.fabriquer + Monde.ajouter, patron
#     banc_elimination_salete.gd:fabriquer_dechet) qui PORTE ses croyances
#     figees (proprietes.contenu_croyance = duplicate(true)). Un lecteur appelle
#     Croyance.corriger avec la fidelite du livre comme credibilite. Le livre se
#     degrade sur une reserve d'integrite (depense.gd, patron banc_corrosion.gd
#     Phase 3) et devient « illisible » au seuil. LE CONTENU N'EST PAS DU TEXTE :
#     data/textes.json ne porte que le LABEL affiche (titre, « illisible »).
#
# ---------------------------------------------------------------------------
# CINQ DECISIONS DE CE CABLAGE, dites plutot que masquees
# ---------------------------------------------------------------------------
# (a) PERSONNE NE SE DEPLACE -- reprise telle quelle de banc_croyance.gd, et
#     pour la meme raison exacte : faire marcher les colons vers le fruit les
#     mettrait tous au contact, donc tous corriges par l'experience directe, et
#     il n'y aurait plus ni ignorance, ni transmission, ni livre a montrer. Ce
#     que la geometrie separe ici, c'est QUI PEUT SE SERVIR DE QUOI, et ca ne
#     bouge pas de la partie. Aucune vitesse, aucun bouger_vers, aucun
#     ciblage.gd.
# (b) L'USAGE EST UN SEUL GESTE A DEUX EFFETS, jamais deux gestes jumeaux. A sa
#     cadence, pour chaque chose a portee_usage dont le VERBE RESOLU POUR CETTE
#     SEULE ENTREE appartient a verbes_d_usage : (1) il s'en sert -- si la chose
#     porte REELLEMENT la propriete toxique, EtatDuree.poser ; (2) l'usage
#     CORRIGE ses croyances a credibilite 1.0. « On ne goute que ce qu'on croit
#     comestible » est donc une consequence de la croyance, pas un test de
#     realite : c'est le meme geste qui fait la decouverte de la ligne 13 et le
#     repas empoisonne de la ligne 15. Resolution par entree via
#     Agir.choisir([entree], ...) -- jamais une reimplementation du pesage
#     poids_verbes, patron exact de banc_commun.gd:choses_a_fuir.
# (c) LE GATE D'EXPERIMENTATION LIT DEUX MIROIRS PLATS, ecrits chaque tick par
#     UN SEUL ECRIVAIN (audit, cinq pieges, « UN SEUL ECRIVAIN par propriete » --
#     deux morceaux de cablage qui ecriraient la meme cle se detruiraient EN
#     SILENCE, aucun test ne rougirait). « temps_libre » n'existe nulle part
#     dans le depot (grep : zero) et le materiau vit sous
#     proprietes.reserves.<nom>.reserve, imbrique : les deux doivent etre
#     miroites a plat, idiome le plus employe du depot (manque_energie,
#     urgence_elimination, population_locale). UN TICK DE RETARD INHERENT, dit
#     plutot que masque : le gate est ecrit AVANT la decision (poids_verbes doit
#     exister quand agir.gd le lit) et le surcout APRES (seul instant ou l'on
#     sait s'il a experimente) -- l'ordre inverse serait circulaire.
# (d) LE MATERIAU FERME LE GATE DE LUI-MEME. Experimenter ecrit un
#     surcout_action sur la reserve, depense.gd la vide, le miroir tombe sous
#     seuil_materiau et le verbe s'eteint. AUCUNE ligne ne dit « il s'arrete » :
#     c'est la meme arithmetique lue a zero.
# (e) LE CLIC DROIT ACCELERE LA DEGRADATION DU LIVRE, il ne le RETIRE pas du
#     monde -- ecart a la consigne, signale et non masque. monde.gd n'a AUCUNE
#     fonction de retrait (CARTE.md §6) : retirer le livre obligerait a
#     RECONSTRUIRE le Monde du neant, idiome deja employe six fois mais qui
#     detruirait ici la seule chose que la ligne 17 demande de montrer -- l'etat
#     terminal du livre. L'etat atteint est LE MEME (« illisible », plus aucune
#     lecture possible), atteint six fois plus vite, et l'objet reste a l'ecran
#     pour qu'on le VOIE mourir.
#
# ---------------------------------------------------------------------------
# CE QUE CE BANC NE MONTRE PAS
# ---------------------------------------------------------------------------
# - AUCUN COLON SOURD. Les deux receveurs ont un lien assez fort pour que le
#   cablage appelle corriger() : le refus qu'on montre ici est le DOGME (le
#   MECANISME refuse), jamais le refus par credibilite (le CABLAGE renonce sous
#   data/croyances.json:seuil_bornes_transmission) -- celui-la est deja
#   demontre par banc_croyance.gd, le redemontrer n'apprendrait rien.
# - AUCUNE MEMOIRE SPATIALE. La position rendue par Croyance.filtrer est
#   toujours la position VIVANTE ; ce qu'une chose EST et OU elle etait sont
#   deux questions separees (memoire_spatiale.gd, banc_memoire_navigation.gd).
# - AUCUNE DEFORMATION, AUCUN ENGAGEMENT, AUCUN CHANTIER. deformation.gd,
#   couplage.gd, extinction.gd ne sont pas appeles : rien ici ne dispute une
#   cible ni ne consomme un travail.
#
# ---------------------------------------------------------------------------
# UNE CONSEQUENCE A ATTENDRE, PAS UN BUG : le dogme porte PAR PROPRIETE, jamais
# par chose. corriger() compare la certitude de LA propriete visee a
# resistance_par_certitude. Le novice, dogmatique sur « comestible » (il l'a
# regardee sept fois), n'a AUCUNE croyance sur « toxique » : la premiere source
# qui la lui donne passe. Il finit donc par croire, en meme temps, que le fruit
# est comestible ET qu'il est toxique -- et il continue de le manger, parce que
# c'est « comestible » qui porte le verbe. C'est la mecanique exacte de
# croyance.gd, jamais un raccourci de ce banc.
#
# LE DOGME CEDE A L'OUBLI, mesure et non voulu au depart : la certitude du
# novice plafonne a 1.0, le fruit perd sa cle « comestible » a t=5 s donc
# observer() ne la rafraichit plus, et l'oubli (taux_decroissance 0.01/s) la
# ramene sous 0.9 vers t=15 s. Son usage suivant le corrige alors, et il cesse
# de s'empoisonner. Un dogme n'est pas eternel : il l'est tant qu'on continue
# de le nourrir.
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge les catalogues et construit ; _unhandled_input
#   bascule le fruit (clic gauche), la degradation du livre (clic droit), la
#   transmission (T) et le colon selectionne (C) ; _process appelle UNIQUEMENT
#   avancer() puis redessine.
# - Fonctions statiques (pures, testables headless, voir
#   scripts/test_banc_affordances_connaissance.gd) : tout le reste.

const Perception = preload("res://scripts/perception.gd")
const Croyance = preload("res://scripts/croyance.gd")
const Proximite = preload("res://scripts/proximite.gd")
const Dominance = preload("res://scripts/dominance.gd")
const Agir = preload("res://scripts/agir.gd")
const LienPersonnel = preload("res://scripts/lien_personnel.gd")
const Monde = preload("res://scripts/monde.gd")
const Objet = preload("res://scripts/objet.gd")
const Depense = preload("res://scripts/depense.gd")
const EtatDuree = preload("res://scripts/etat_duree.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")

const TAILLE_COLON := 40.0
const TAILLE_OBJET := 46.0
const TAILLE_LIVRE := 30.0
const TAILLE_POLICE_LABEL := 13
const TAILLE_POLICE_COMPTEUR := 16
const LARGEUR_LIGNE := 2.0

var _config: Dictionary = {}
var _catalogues: Dictionary = {}
var _textes: Dictionary = {}

var _etat: Dictionary = {}
var _temps := 0.0
var _prochaine_trace := 0.0

var _couche_ui: CanvasLayer
var _noeuds: Dictionary = {}
var _labels: Dictionary = {}
var _lignes: Dictionary = {}
var _noeud_livre: ColorRect
var _label_livre: Label
var _label_compteur: Label

# Le rendu relit l'etat du DERNIER pas, jamais une valeur recalculee a cote --
# le label ne peut donc pas mentir sur ce que le colon croit (meme discipline
# que banc_croyance.gd/banc_menace_combat.gd).
var _dernier_resultat: Dictionary = {}

func _ready() -> void:
	_config = _charger_json("res://data/banc_affordances_connaissance.json")
	_textes = _charger_json("res://data/textes.json")
	_catalogues = {
		"canaux": _charger_json("res://data/canaux.json"),
		"croyances": _charger_json("res://data/croyances.json"),
		"etats": _charger_json("res://data/etats.json"),
		"seuils": _charger_json("res://data/seuils_combustible.json"),
		"profils": _charger_json("res://data/profils_saillance.json"),
		"actions": _charger_json("res://data/types_choses.json"),
		"types": _charger_json("res://data/types.json"),
		"materiaux": _charger_json("res://data/materiaux.json"),
		"liens": _charger_json("res://data/liens_personnels.json"),
	}

	_etat = etat_initial(_config, _catalogues)

	_couche_ui = CanvasLayer.new()
	add_child(_couche_ui)
	_creer_rendu()
	_poser_camera()
	print(ligne_bascule(0.0, String(_config.fruit_bascule), "sain"))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_etat.fruit_toxique = not bool(_etat.fruit_toxique)
			poser_etat_fruit(_etat.objets, _config, bool(_etat.fruit_toxique))
			print(ligne_bascule(_temps, String(_config.fruit_bascule),
				"toxique" if bool(_etat.fruit_toxique) else "sain"))
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_etat.degradation_acceleree = not bool(_etat.degradation_acceleree)
			print(ligne_degradation(_temps, bool(_etat.degradation_acceleree)))
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_T:
			for evenement in transmettre(_etat.colons, _config, _catalogues.croyances, _catalogues.liens):
				print(ligne_evenement(_temps, evenement))
		elif event.keycode == KEY_C:
			_etat.selection = (int(_etat.selection) + 1) % _etat.colons.size()
			print(ligne_selection(_temps, String(_etat.colons[int(_etat.selection)].id)))

func _process(delta: float) -> void:
	_temps += delta
	var resultat := avancer(_etat, _config, _catalogues, delta, _temps)
	_dernier_resultat = resultat
	for evenement in resultat.evenements:
		print(ligne_evenement(_temps, evenement))
	if _temps >= _prochaine_trace:
		_prochaine_trace = _temps + float(_config.periode_trace_s)
		for etat_colon in resultat.colons:
			print(ligne_etat(_temps, etat_colon))
	_rafraichir_tout()

# ---------------------------------------------------------------------------
# Construction (pures)
# ---------------------------------------------------------------------------

# Les colons sont FABRIQUES depuis data/types.json:colon (Objet.fabriquer via
# BancCommun.fabriquer_colon) et non construits a la main comme dans
# banc_croyance.gd -- ecart VOULU : c'est la seule facon que « curiosite »
# (posee sur le type par ce chantier) soit REELLEMENT lue plutot que dormante.
# Deux des trois colons ne la declarent pas dans data/banc_affordances_
# connaissance.json et heritent donc la valeur du type ; seul l'auteur la
# surcharge.
#
# CE QUE LE CABLAGE ECRASE APRES LA FABRICATION, et pourquoi :
# - canaux/canaux_config : une seule vue, angle 360.0 (voir _note_angle en
#   donnee -- un cone de 180.0 ne percoit RIEN dans un monde plan, et les cinq
#   autres canaux du type introduiraient des portees qui brouilleraient les
#   distances calibrees).
# - croyances : {} -- STRUCTURELLE pour croyance.gd, absente de data/types.json
#   (aucun type ne la porte), posee ici comme dans banc_croyance.gd. AUCUNE
#   croyance n'est posee en dur : elles naissent toutes de la perception vecue.
# - etats_actifs/etats_intensite : le couple qu'etat_duree.gd mute.
# - la reserve de materiau et les deux miroirs plats du gate.
#
# Les trois echeances de cadence vivent HORS de proprietes, au meme niveau
# qu'action_en_cours : elles changent a chaque pas, ce n'est pas un fait stable
# de l'objet (docs/design.md, « action_en_cours vit hors de proprietes »).
static func fabriquer_colons(config: Dictionary, catalogue_types: Dictionary) -> Array:
	var colons: Array = []
	var auteur := String(config.get("auteur", ""))
	for nom in config.get("colons", {}):
		var decl: Dictionary = config.colons[nom]
		var decl_commune: Dictionary = {
			"position": decl.position,
			"attaches": [],
			"forme": config.forme_commune.duplicate(true),
			"poids_verbes": config.poids_verbes_commun.duplicate(true),
		}
		var colon: Dictionary = BancCommun.fabriquer_colon(
			String(nom), String(config.type_colon), decl_commune, catalogue_types)
		if colon.is_empty():
			push_error("banc_affordances_connaissance : fabrication du colon '%s' refusee" % nom)
			continue
		var proprietes: Dictionary = colon.proprietes
		proprietes["canaux"] = [String(config.nom_canal_vue)]
		proprietes["canaux_config"] = {String(config.nom_canal_vue): config.canal_vue.duplicate(true)}
		proprietes["croyances"] = {}
		proprietes["etats_actifs"] = []
		proprietes["etats_intensite"] = {}
		var reserves: Dictionary = proprietes.get("reserves", {})
		reserves[String(config.nom_reserve_materiau)] = config.canal_materiau.duplicate(true)
		proprietes["reserves"] = reserves
		proprietes[String(config.nom_miroir_temps_libre)] = 0.0
		proprietes[String(config.nom_miroir_materiau)] = float(config.canal_materiau.reserve)
		if decl.has("curiosite"):
			proprietes["curiosite"] = float(decl.curiosite)
		colon["cadence_observation"] = float(decl.cadence_observation)
		colon["cadence_usage"] = float(decl.cadence_usage)
		colon["cadence_lecture"] = float(config.cadence_lecture)
		colon["prochaine_observation"] = 0.0
		colon["prochain_usage"] = 0.0
		colon["prochaine_lecture"] = 0.0
		var force: float = float(decl.get("lien_vers_auteur", 0.0))
		if force > 0.0 and String(nom) != auteur:
			LienPersonnel.poser(colon, auteur, force)
		colons.append(colon)
	return colons

# Les objets, CONSTRUITS A LA MAIN. L'id EST la cle de configuration. Les
# proprietes sont DUPLIQUEES : sans quoi la bascule du fruit muterait le
# Dictionary du disque, deja partage avec toute autre lecture de ce fichier.
static func fabriquer_objets(config: Dictionary) -> Array:
	var objets: Array = []
	for cle in config.get("objets", {}):
		var decl: Dictionary = config.objets[cle]
		var pos: Array = decl.position
		objets.append({
			"id": String(cle),
			"position": Vector3(pos[0], pos[1], pos[2]),
			"proprietes": decl.get("proprietes", {}).duplicate(true),
		})
	return objets

static func objet_par_id(objets: Array, id: String) -> Dictionary:
	for objet in objets:
		if String(objet.id) == id:
			return objet
	return {}

# L'ETAT COMPLET du banc, en un seul Dictionary -- c'est lui, et non un champ de
# Node, que avancer() mute (patron banc_predation.gd:etat_initial). Le livre y
# entre {} et devient un vrai objet quand l'auteur l'ecrit.
static func etat_initial(config: Dictionary, catalogues: Dictionary) -> Dictionary:
	var objets := fabriquer_objets(config)
	var colons := fabriquer_colons(config, catalogues.types)
	var monde = BancCommun.monde_depuis([
		{"choses": objets, "type": "objet"},
		{"choses": colons, "type": "colon"},
	])
	return {
		"colons": colons,
		"objets": objets,
		"monde": monde,
		"livre": {},
		"fruit_toxique": false,
		"toxicite_declenchee": false,
		"degradation_acceleree": false,
		"selection": 0,
	}

# REMPLACE le Dictionary de proprietes EN ENTIER plutot que d'ecrire une cle :
# le fruit toxique n'a PAS « comestible » a false, il ne l'a PLUS DU TOUT (voir
# en-tete, ligne 15). UN SEUL ECRIVAIN de l'etat du fruit -- la bascule du
# joueur et l'echeance automatique passent toutes deux par ici.
static func poser_etat_fruit(objets: Array, config: Dictionary, toxique: bool) -> void:
	var id := String(config.fruit_bascule)
	var fruit := objet_par_id(objets, id)
	if fruit.is_empty():
		return
	var decl: Dictionary = config.get("objets", {}).get(id, {})
	var cle := "proprietes_toxiques" if toxique else "proprietes"
	fruit["proprietes"] = decl.get(cle, {}).duplicate(true)

# ---------------------------------------------------------------------------
# Lectures pures d'une croyance (jamais une regle recopiee)
# ---------------------------------------------------------------------------

static func valeur_crue(colon: Dictionary, chose_id: String, propriete: String) -> Variant:
	return colon.proprietes.croyances.get(chose_id, {}).get(propriete, {}).get("valeur", null)

static func certitude_crue(colon: Dictionary, chose_id: String, propriete: String) -> float:
	return colon.proprietes.croyances.get(chose_id, {}).get(propriete, {}).get("certitude", 0.0)

static func instantane(colon: Dictionary) -> Dictionary:
	var plat: Dictionary = {}
	var croyances: Dictionary = colon.proprietes.croyances
	for chose_id in croyances:
		for propriete in croyances[chose_id]:
			plat["%s/%s" % [chose_id, propriete]] = croyances[chose_id][propriete].valeur
	return plat

# ---------------------------------------------------------------------------
# Le gate composite (ligne 16) -- ARITHMETIQUE, jamais une branche de decision
# ---------------------------------------------------------------------------

# UNIQUE ECRIVAIN du miroir plat de materiau (voir decision (c) en tete).
# seuil_etat.gd et conditions.gd ne savent lire qu'une cle PLATE, jamais
# proprietes.reserves.<nom>.reserve -- recopie, jamais un calcul.
static func refleter_materiau(colon: Dictionary, config: Dictionary) -> void:
	var reserves: Dictionary = colon.proprietes.get("reserves", {})
	var canal: Dictionary = reserves.get(String(config.nom_reserve_materiau), {})
	colon.proprietes[String(config.nom_miroir_materiau)] = float(canal.get("reserve", 0.0))

# UNIQUE ECRIVAIN du miroir plat de temps libre. S'accumule tant que le colon ne
# se sert de rien, RETOMBE A ZERO des qu'il s'en sert -- un accumulateur
# d'evenements, patron duree_maladie_cumulee/cycles_vecus, jamais un mecanisme.
static func accumuler_temps_libre(colon: Dictionary, a_utilise: bool, config: Dictionary, delta: float) -> void:
	var cle := String(config.nom_miroir_temps_libre)
	if a_utilise:
		colon.proprietes[cle] = 0.0
		return
	colon.proprietes[cle] = float(colon.proprietes.get(cle, 0.0)) + delta

# LE GATE. Trois comparaisons, un seul nombre en sortie. Une condition qui
# manque rend 0.0 -- agir.gd:_verbe_par_poids exige p > 0.0, le verbe devient
# donc inchoisissable par la seule arithmetique, sans qu'aucune branche
# « ce colon n'experimente pas » n'existe nulle part.
static func poids_experimenter(colon: Dictionary, config: Dictionary) -> float:
	var proprietes: Dictionary = colon.proprietes
	if float(proprietes.get("curiosite", 0.0)) < float(config.seuil_curiosite):
		return 0.0
	if float(proprietes.get(String(config.nom_miroir_temps_libre), 0.0)) < float(config.seuil_temps_libre):
		return 0.0
	if float(proprietes.get(String(config.nom_miroir_materiau), 0.0)) < float(config.seuil_materiau):
		return 0.0
	return float(config.poids_experimenter)

# UNIQUE ECRIVAIN de poids_verbes (audit, cinq pieges). Ecrit la table EN ENTIER
# depuis la donnee, jamais un increment sur la precedente -- idempotent, rappele
# a chaque tick : deux tables successives ne peuvent pas se melanger.
static func poser_poids_verbes(colon: Dictionary, config: Dictionary) -> void:
	var table: Dictionary = config.poids_verbes_commun.duplicate(true)
	table[String(config.verbe_experimenter)] = poids_experimenter(colon, config)
	colon.proprietes["poids_verbes"] = table

# UNIQUE ECRIVAIN du surcout de la reserve de materiau. Voir decision (d) :
# c'est lui qui, par depense.gd, finit par fermer le gate ci-dessus.
static func poser_surcout_experimentation(colon: Dictionary, a_experimente: bool, config: Dictionary) -> void:
	var reserves: Dictionary = colon.proprietes.get("reserves", {})
	var canal: Dictionary = reserves.get(String(config.nom_reserve_materiau), {})
	if canal.is_empty():
		return
	canal["surcout_action"] = float(config.cout_experimentation) if a_experimente else 0.0

# ---------------------------------------------------------------------------
# Les gestes du cablage
# ---------------------------------------------------------------------------

static func observer_si_cadence(
	colon: Dictionary,
	perceptions: Array,
	catalogue: Dictionary,
	temps: float,
) -> Array:
	if temps < float(colon.prochaine_observation):
		return []
	colon["prochaine_observation"] = temps + float(colon.cadence_observation)
	var avant := instantane(colon)
	Croyance.observer(colon, perceptions, catalogue)
	var evenements: Array = []
	for cle in instantane(colon):
		if avant.has(cle):
			continue
		var morceaux: PackedStringArray = cle.split("/")
		evenements.append(_evenement(colon, "observe", morceaux[0], morceaux[1], 1.0))
	return evenements

# LES QUATRE COUCHES, sur la COPIE et jamais sur le monde. Croyance.filtrer
# s'intercale entre la couche 1 et la couche 2 ; les quatre suivantes ne savent
# pas qu'elles lisent une copie et n'ont pas une ligne de changee.
static func decider(
	colon: Dictionary,
	perceptions: Array,
	monde,
	catalogue_croyances: Dictionary,
	profils_saillance: Dictionary,
	catalogue_actions: Dictionary,
) -> Dictionary:
	var crues := Croyance.filtrer(colon, perceptions, catalogue_croyances)
	var resultats := Proximite.evaluer(crues, colon, profils_saillance)
	var visibles := Dominance.visibles(resultats, colon)
	var decision = Agir.choisir(visibles, colon, catalogue_actions, monde)
	colon.action_en_cours = Agir.etat_courant(decision)
	return {"crues": crues, "resultats": resultats, "visibles": visibles, "decision": decision}

# LE VERBE RESOLU POUR UNE SEULE ENTREE -- jamais une reimplementation du pesage
# poids_verbes (agir.gd). Sur une liste a un seul element, choisir() delegue
# directement a sa resolution de propriete, sans inertie. Patron exact de
# banc_commun.gd:choses_a_fuir. L'entree doit venir de Proximite.evaluer (elle
# porte « saillance », qu'agir.gd lit dans _score).
static func verbe_pour(colon: Dictionary, entree: Dictionary, monde, catalogue_actions: Dictionary) -> String:
	var resolue = Agir.choisir([entree], colon, catalogue_actions, monde)
	if resolue == null:
		return ""
	return String(resolue.get("action", ""))

# L'USAGE : UN SEUL GESTE, DEUX EFFETS (voir decision (b) en tete). Rend
# { evenements, a_utilise }.
#
# Une propriete ABSENTE de la chose reelle vaut false -- c'est la valeur
# VERIFIEE, pas un defaut silencieux : « je m'en suis servi, ce n'est pas
# comestible » (meme convention que banc_croyance.gd:verifier_si_cadence).
static func utiliser_si_cadence(
	colon: Dictionary,
	resultats: Array,
	monde,
	config: Dictionary,
	catalogue_croyances: Dictionary,
	catalogue_actions: Dictionary,
	catalogue_etats: Dictionary,
	temps: float,
) -> Dictionary:
	if temps < float(colon.prochain_usage):
		return {"evenements": [], "a_utilise": false}
	colon["prochain_usage"] = temps + float(colon.cadence_usage)
	var portee: float = float(config.portee_usage)
	var verbes: Array = config.verbes_d_usage
	var evenements: Array = []
	var a_utilise := false
	for entree in resultats:
		if colon.position.distance_to(entree.position) > portee:
			continue
		if not verbes.has(verbe_pour(colon, entree, monde, catalogue_actions)):
			continue
		var chose_id := String(entree.chose.id)
		var wrapper = monde.par_id(chose_id)
		if wrapper == null:
			continue
		a_utilise = true
		var reelles: Dictionary = wrapper.chose.proprietes
		if bool(reelles.get(String(config.propriete_toxique), false)):
			EtatDuree.poser(colon, String(config.etat_empoisonne), catalogue_etats)
			evenements.append(_evenement(colon, "empoisonne", chose_id, String(config.propriete_toxique), 1.0))
		evenements.append_array(_corriger_et_tracer(
			colon, chose_id, config.proprietes_apprises_par_usage, reelles, 1.0,
			catalogue_croyances, "apprend"))
	return {"evenements": evenements, "a_utilise": a_utilise}

# L'EXPERIMENTATION (ligne 16). Suit la DECISION, jamais une liste : ce que le
# colon experimente est ce qu'il a CHOISI, et le verbe resolu est la seule
# preuve que le gate est ouvert. Rend { evenements, a_experimente }.
static func experimenter_si_decide(
	colon: Dictionary,
	decision,
	monde,
	config: Dictionary,
	catalogue_croyances: Dictionary,
) -> Dictionary:
	if decision == null or not decision.has("chose"):
		return {"evenements": [], "a_experimente": false}
	if String(decision.get("action", "")) != String(config.verbe_experimenter):
		return {"evenements": [], "a_experimente": false}
	if colon.position.distance_to(decision.position) > float(config.portee_usage):
		return {"evenements": [], "a_experimente": false}
	var chose_id := String(decision.chose.id)
	var wrapper = monde.par_id(chose_id)
	if wrapper == null:
		return {"evenements": [], "a_experimente": false}
	var evenements := _corriger_et_tracer(
		colon, chose_id, config.proprietes_apprises_par_experimentation,
		wrapper.chose.proprietes, 1.0, catalogue_croyances, "experimente")
	return {"evenements": evenements, "a_experimente": true}

# LA TRANSMISSION (ligne 14). L'auteur verse TOUTES ses croyances aux colons a
# portee_transmission. La credibilite n'est pas inventee : c'est la force du
# LIEN PERSONNEL du RECEVEUR vers l'auteur (un autre colon est une chose comme
# une autre, il a deja sa place dans liens_personnels), MULTIPLIEE par la
# fidelite de la parole. La fidelite degrade la CERTITUDE, jamais la VALEUR.
#
# DEUX REFUS DISTINCTS, a ne jamais confondre : sous
# data/croyances.json:seuil_bornes_transmission le CABLAGE renonce et n'appelle
# meme pas ; au-dela il appelle, et c'est le MECANISME qui refuse si la
# certitude du receveur a franchi resistance_par_certitude. Ce banc ne montre
# que le SECOND (voir en-tete). Detecte par DIFFERENCE d'etat -- la valeur crue
# apres correction est la valeur transmise si, et seulement si, la correction
# est passee ; aucun seuil n'est recopie ici.
static func transmettre(
	colons: Array,
	config: Dictionary,
	catalogue_croyances: Dictionary,
	catalogue_liens: Dictionary,
) -> Array:
	var nom_auteur := String(config.get("auteur", ""))
	var auteur: Dictionary = {}
	for colon in colons:
		if String(colon.id) == nom_auteur:
			auteur = colon
	if auteur.is_empty():
		return []
	var seuil: float = float(catalogue_croyances.get("seuil_bornes_transmission", 0.0))
	var portee: float = float(config.portee_transmission)
	var fidelite: float = float(config.fidelite_parole)
	var evenements: Array = []
	for colon in colons:
		if String(colon.id) == nom_auteur:
			continue
		if auteur.position.distance_to(colon.position) > portee:
			continue
		var credibilite: float = LienPersonnel.force(colon, nom_auteur, catalogue_liens) * fidelite
		if credibilite < seuil:
			evenements.append(_evenement(colon, "sourd", nom_auteur, "", credibilite))
			continue
		evenements.append_array(_verser(
			colon, auteur.proprietes.croyances, credibilite, catalogue_croyances, "recoit", true))
	return evenements

# L'ECRITURE (ligne 17). Vrai quand l'auteur CROIT qu'une chose porte la
# propriete declenchante, avec une certitude suffisante -- « on ecrit ce qu'on
# juge important », en donnee et jamais un instant code.
static func doit_ecrire(auteur: Dictionary, config: Dictionary) -> bool:
	var nom := String(config.propriete_declenchant_ecriture)
	var seuil: float = float(config.certitude_minimale_ecriture)
	var croyances: Dictionary = auteur.proprietes.croyances
	for chose_id in croyances:
		var champ: Dictionary = croyances[chose_id].get(nom, {})
		if champ.is_empty():
			continue
		if bool(champ.get("valeur", false)) and float(champ.get("certitude", 0.0)) >= seuil:
			return true
	return false

# UN VRAI OBJET FABRIQUE EN COURS DE PARTIE (patron
# banc_elimination_salete.gd:fabriquer_dechet) -- le type vient d'un catalogue
# LOCAL au banc (patron banc_corrosion.gd:fabriquer_objets), data/types.json
# n'a pas a connaitre un objet que seul ce banc fabrique. Les quatre proprietes
# posees APRES la fabrication suivent le constat systemique deja ecrit
# (banc_produit_nucleaire.gd) : Objet.fabriquer ne relaie aucune propriete qui
# ne vienne pas du type ou de la composition.
#
# LE FIGEAGE EST UNE COPIE PROFONDE : sans duplicate(true), le livre et son
# auteur partageraient le MEME registre, et « ce que le medecin savait ce
# jour-la » suivrait ce qu'il apprend ensuite -- le livre ne figerait rien.
# Rend {} si objet.gd REFUSE la fabrication (contrat explicite d'objet.gd).
static func fabriquer_livre(
	auteur: Dictionary,
	position: Vector3,
	config: Dictionary,
	materiaux: Dictionary,
) -> Dictionary:
	var decl: Dictionary = config.livre
	var livre := Objet.fabriquer(
		String(decl.id), String(decl.type), position, config.types_locaux, materiaux)
	if livre.is_empty():
		return {}
	livre.proprietes["auteur"] = String(auteur.id)
	livre.proprietes["contenu_croyance"] = auteur.proprietes.croyances.duplicate(true)
	livre.proprietes["fidelite"] = float(config.fidelite_livre)
	livre.proprietes["reserves"] = {
		String(config.nom_reserve_integrite): {
			"capacite": float(decl.integrite),
			"reserve": float(decl.integrite),
			"cout_base": float(decl.cout_lisibilite),
			"surcout_action": 0.0,
			"seuils_ref": String(decl.seuils_ref),
			"seuils_franchis": [],
		},
	}
	return livre

static func est_illisible(livre: Dictionary, config: Dictionary) -> bool:
	if livre.is_empty():
		return false
	return bool(livre.proprietes.get(String(config.livre.propriete_illisible), false))

static func integrite_livre(livre: Dictionary, config: Dictionary) -> float:
	if livre.is_empty():
		return 0.0
	return float(livre.proprietes.get("reserves", {})
		.get(String(config.nom_reserve_integrite), {}).get("reserve", 0.0))

# UNIQUE ECRIVAIN du cout de la reserve d'integrite -- gate de cablage sur la
# bascule joueur, meme idiome que banc_corrosion.gd (cout_base ecrit selon un
# etat, depense.gd ne consulte JAMAIS etat_effectif.gd).
static func poser_cout_livre(livre: Dictionary, config: Dictionary, acceleree: bool) -> void:
	if livre.is_empty():
		return
	var canal: Dictionary = livre.proprietes.get("reserves", {}).get(String(config.nom_reserve_integrite), {})
	if canal.is_empty():
		return
	var facteur: float = float(config.livre.facteur_degradation_acceleree) if acceleree else 1.0
	canal["cout_base"] = float(config.livre.cout_lisibilite) * facteur

# LA LECTURE (ligne 17). MEME GESTE que la transmission, avec un livre au lieu
# d'un colon comme source : le contenu figee est verse par Croyance.corriger,
# credibilite = fidelite du livre. L'AUTEUR NE SE RELIT PAS -- sans ce gate il
# rabaisserait sa propre certitude (0.80 vecue contre 0.60 lue) en relisant ce
# qu'il vient d'ecrire.
static func lire_si_cadence(
	colon: Dictionary,
	livre: Dictionary,
	config: Dictionary,
	catalogue_croyances: Dictionary,
	temps: float,
) -> Array:
	if livre.is_empty() or est_illisible(livre, config):
		return []
	if String(livre.proprietes.get("auteur", "")) == String(colon.id):
		return []
	if colon.position.distance_to(livre.position) > float(config.portee_lecture):
		return []
	if temps < float(colon.prochaine_lecture):
		return []
	colon["prochaine_lecture"] = temps + float(colon.cadence_lecture)
	return _verser(
		colon, livre.proprietes.get("contenu_croyance", {}),
		float(livre.proprietes.get("fidelite", 0.0)), catalogue_croyances, "lit", false)

# ---------------------------------------------------------------------------
# Deux gestes partages, pour ne pas ecrire trois fois la meme boucle
# ---------------------------------------------------------------------------

# Verse un REGISTRE ENTIER (celui d'un emetteur, ou celui d'un livre) dans les
# croyances d'un receveur. Le refus par dogme est detecte par DIFFERENCE : apres
# corriger(), la valeur crue vaut la valeur versee si et seulement si la
# correction est passee. Aucun seuil recopie.
#
# DEUX REGIMES DE TRACE, et c'est une decision de LISIBILITE, jamais de
# mecanique : la TRANSMISSION est un geste du joueur (touche T), on veut voir
# TOUT ce qu'elle produit d'un coup, y compris ce qu'elle confirme
# (tout_tracer) ; la LECTURE tourne a la cadence, tracer chaque confirmation
# toutes les deux secondes noierait la console -- on n'y garde que ce qui
# CHANGE. Le refus par dogme, lui, est trace dans les deux cas : il n'arrive
# jamais sans raison.
static func _verser(
	colon: Dictionary,
	registre: Dictionary,
	credibilite: float,
	catalogue_croyances: Dictionary,
	genre_succes: String,
	tout_tracer: bool,
) -> Array:
	var evenements: Array = []
	for chose_id in registre:
		for propriete in registre[chose_id]:
			var nom_chose := String(chose_id)
			var nom := String(propriete)
			var versee: Variant = registre[nom_chose][nom].valeur
			var avant: Variant = valeur_crue(colon, nom_chose, nom)
			Croyance.corriger(colon, nom_chose, nom, versee, credibilite, catalogue_croyances)
			var apres: Variant = valeur_crue(colon, nom_chose, nom)
			if apres != versee:
				evenements.append(_evenement(colon, "dogme", nom_chose, nom, credibilite))
			elif tout_tracer or avant != versee:
				evenements.append(_evenement(colon, genre_succes, nom_chose, nom, credibilite))
	return evenements

# Confronte les croyances d'un colon aux valeurs REELLES d'une chose, sur une
# liste de proprietes recue en donnee. Meme detection de dogme que _verser.
static func _corriger_et_tracer(
	colon: Dictionary,
	chose_id: String,
	proprietes: Array,
	reelles: Dictionary,
	credibilite: float,
	catalogue_croyances: Dictionary,
	genre_succes: String,
) -> Array:
	var evenements: Array = []
	for propriete in proprietes:
		var nom := String(propriete)
		var reelle: Variant = reelles.get(nom, false)
		var avant: Variant = valeur_crue(colon, chose_id, nom)
		Croyance.corriger(colon, chose_id, nom, reelle, credibilite, catalogue_croyances)
		var apres: Variant = valeur_crue(colon, chose_id, nom)
		if apres != reelle:
			evenements.append(_evenement(colon, "dogme", chose_id, nom, credibilite))
		elif avant != reelle:
			evenements.append(_evenement(colon, genre_succes, chose_id, nom, credibilite))
	return evenements

static func _evenement(colon: Dictionary, genre: String, chose_id: String, propriete: String, credibilite: float) -> Dictionary:
	return {
		"colon": String(colon.id),
		"genre": genre,
		"chose_id": chose_id,
		"propriete": propriete,
		"valeur": valeur_crue(colon, chose_id, propriete),
		"certitude": certitude_crue(colon, chose_id, propriete),
		"credibilite": credibilite,
	}

# ---------------------------------------------------------------------------
# UN PAS COMPLET
# ---------------------------------------------------------------------------

# ORDRE FIXE ET ASSUME, chaque etape depend de la precedente :
#  1. l'echeance de toxicite du fruit (un evenement du MONDE, avant toute
#     perception -- sinon un colon percevrait l'etat d'avant et deciderait sur
#     un monde qui n'existe plus) ;
#  2. les deux miroirs plats, puis le GATE (poids_verbes doit exister quand
#     agir.gd le lit -- voir decision (c)) ;
#  3. par colon : percevoir -> observer a la cadence -> decider sur la copie ;
#  4. l'usage a la cadence (repas + decouverte), puis l'experimentation selon la
#     decision, puis le surcout et l'accumulation de temps libre ;
#  5. l'ecriture du livre, puis la lecture -- dans cet ordre, un livre ecrit ce
#     tick est lisible ce tick, l'ordre inverse decalerait tout d'un pas ;
#  6. la degradation du livre (depense.gd) et l'usure des etats (etat_duree.gd),
#     puis la depense des reserves des colons ;
#  7. l'OUBLI EN DERNIER : une croyance formee ce pas-ci ne doit pas perdre sa
#     certitude avant d'avoir servi une seule fois a decider.
static func avancer(
	etat: Dictionary,
	config: Dictionary,
	catalogues: Dictionary,
	delta: float,
	temps: float,
) -> Dictionary:
	var evenements: Array = []

	if not bool(etat.toxicite_declenchee) and temps >= float(config.instant_toxicite_s):
		etat["toxicite_declenchee"] = true
		etat["fruit_toxique"] = true
		poser_etat_fruit(etat.objets, config, true)
		evenements.append({
			"colon": "", "genre": "bascule_fruit", "chose_id": String(config.fruit_bascule),
			"propriete": String(config.propriete_toxique), "valeur": true,
			"certitude": 0.0, "credibilite": 0.0,
		})

	for colon in etat.colons:
		refleter_materiau(colon, config)
		poser_poids_verbes(colon, config)

	var etats_colons: Array = []
	for colon in etat.colons:
		var perceptions: Array = Perception.percevoir(colon, etat.monde, catalogues.canaux)
		evenements.append_array(observer_si_cadence(colon, perceptions, catalogues.croyances, temps))
		var r := decider(colon, perceptions, etat.monde, catalogues.croyances,
			catalogues.profils, catalogues.actions)

		var usage := utiliser_si_cadence(colon, r.resultats, etat.monde, config,
			catalogues.croyances, catalogues.actions, catalogues.etats, temps)
		evenements.append_array(usage.evenements)

		var experience := experimenter_si_decide(colon, r.decision, etat.monde, config, catalogues.croyances)
		evenements.append_array(experience.evenements)

		poser_surcout_experimentation(colon, bool(experience.a_experimente), config)
		accumuler_temps_libre(colon, bool(usage.a_utilise), config, delta)

		etats_colons.append(_etat_colon(colon, r.decision, config))

	if etat.livre.is_empty():
		var auteur := colon_par_id(etat.colons, String(config.auteur))
		var pupitre := objet_par_id(etat.objets, String(config.pupitre_id))
		if not auteur.is_empty() and not pupitre.is_empty() \
			and auteur.position.distance_to(pupitre.position) <= float(config.portee_ecriture) \
			and doit_ecrire(auteur, config):
			var livre := fabriquer_livre(auteur, pupitre.position, config, catalogues.materiaux)
			if not livre.is_empty():
				etat["livre"] = livre
				etat.monde.ajouter(livre, "livre", livre.position)
				evenements.append({
					"colon": String(auteur.id), "genre": "ecrit",
					"chose_id": String(livre.id), "propriete": "",
					"valeur": livre.proprietes.contenu_croyance.size(),
					"certitude": 0.0, "credibilite": float(livre.proprietes.fidelite),
				})

	for colon in etat.colons:
		evenements.append_array(lire_si_cadence(colon, etat.livre, config, catalogues.croyances, temps))

	if not etat.livre.is_empty():
		var illisible_avant := est_illisible(etat.livre, config)
		poser_cout_livre(etat.livre, config, bool(etat.degradation_acceleree))
		Depense.avancer([etat.livre], delta, catalogues.seuils)
		if not illisible_avant and est_illisible(etat.livre, config):
			evenements.append({
				"colon": "", "genre": "illisible", "chose_id": String(etat.livre.id),
				"propriete": String(config.livre.propriete_illisible), "valeur": true,
				"certitude": 0.0, "credibilite": 0.0,
			})

	for entree in EtatDuree.avancer(etat.colons, delta, catalogues.etats):
		evenements.append({
			"colon": String(entree.id), "genre": "gueri", "chose_id": "",
			"propriete": String(entree.nom_etat), "valeur": null,
			"certitude": 0.0, "credibilite": 0.0,
		})
	Depense.avancer(etat.colons, delta)

	for i in range(etat.colons.size()):
		var colon: Dictionary = etat.colons[i]
		var avant := instantane(colon)
		Croyance.avancer(colon, delta, catalogues.croyances)
		var apres := instantane(colon)
		for cle in avant:
			if apres.has(cle):
				continue
			var morceaux: PackedStringArray = cle.split("/")
			evenements.append(_evenement(colon, "oublie", morceaux[0], morceaux[1], 0.0))
		etats_colons[i]["nb_croyances"] = apres.size()

	return {"colons": etats_colons, "evenements": evenements}

static func colon_par_id(colons: Array, id: String) -> Dictionary:
	for colon in colons:
		if String(colon.id) == id:
			return colon
	return {}

static func _etat_colon(colon: Dictionary, decision, config: Dictionary) -> Dictionary:
	return {
		"id": String(colon.id),
		"curiosite": float(colon.proprietes.get("curiosite", 0.0)),
		"temps_libre": float(colon.proprietes.get(String(config.nom_miroir_temps_libre), 0.0)),
		"materiau": float(colon.proprietes.get(String(config.nom_miroir_materiau), 0.0)),
		"poids_experimenter": float(colon.proprietes.poids_verbes.get(String(config.verbe_experimenter), 0.0)),
		"empoisonne": colon.proprietes.get("etats_actifs", []).has(String(config.etat_empoisonne)),
		"verbe": String(decision.get("action", "")) if decision != null else "",
		"cible_id": String(decision.chose.id) if decision != null and decision.has("chose") else "",
		"nb_croyances": 0,
		"croyances": colon.proprietes.croyances,
	}

# ---------------------------------------------------------------------------
# Textes. DEUX REGIMES A NE PAS CONFONDRE (voir data/textes.json) : les LABELS
# a l'ecran passent par le catalogue i18n, les traces console (print) non --
# ce sont des sorties de mise au point, la regle d'INTERNATIONALISATION ne les
# vise pas. Une cle absente ressort TELLE QUELLE, jamais remplacee par un texte
# de repli ecrit ici : le trou doit etre visible pour etre corrige.
# ---------------------------------------------------------------------------

static func texte(cle: String, config: Dictionary, textes: Dictionary) -> String:
	if cle == "":
		return ""
	return String(textes.get(String(config.langue), {}).get(cle, cle))

static func cle_label_livre(livre: Dictionary, config: Dictionary) -> String:
	if livre.is_empty():
		return ""
	return String(config.livre.cle_illisible) if est_illisible(livre, config) \
		else String(config.livre.cle_titre)

static func _mot(valeur: Variant) -> String:
	if valeur is bool:
		return "oui" if valeur else "non"
	if valeur == null:
		return "-"
	return str(valeur)

static func ligne_bascule(t: float, id: String, etat: String) -> String:
	return "t=%.1fs BASCULE : %s -> %s" % [t, id, etat]

static func ligne_degradation(t: float, acceleree: bool) -> String:
	return "t=%.1fs LIVRE : degradation %s" % [t, "ACCELEREE" if acceleree else "normale"]

static func ligne_selection(t: float, id: String) -> String:
	return "t=%.1fs SELECTION : les fruits sont colores par ce que croit %s" % [t, id]

static func ligne_evenement(t: float, ev: Dictionary) -> String:
	match String(ev.genre):
		"observe":
			return "t=%.1fs %s OBSERVE %s.%s = %s (certitude %.2f)" % [
				t, ev.colon, ev.chose_id, ev.propriete, _mot(ev.valeur), ev.certitude]
		"apprend":
			return "t=%.1fs %s DECOUVRE PAR L'USAGE %s.%s = %s (certitude %.2f)" % [
				t, ev.colon, ev.chose_id, ev.propriete, _mot(ev.valeur), ev.certitude]
		"experimente":
			return "t=%.1fs %s EXPERIMENTE %s -> %s = %s (certitude %.2f)" % [
				t, ev.colon, ev.chose_id, ev.propriete, _mot(ev.valeur), ev.certitude]
		"empoisonne":
			return "t=%.1fs %s MANGE %s ET S'EMPOISONNE (il le croyait comestible)" % [
				t, ev.colon, ev.chose_id]
		"gueri":
			return "t=%.1fs %s : etat '%s' expire" % [t, ev.colon, ev.propriete]
		"recoit":
			return "t=%.1fs %s RECOIT DE VIVE VOIX %s.%s = %s (credibilite %.2f, certitude %.2f)" % [
				t, ev.colon, ev.chose_id, ev.propriete, _mot(ev.valeur), ev.credibilite, ev.certitude]
		"lit":
			return "t=%.1fs %s LIT %s.%s = %s (credibilite %.2f, certitude %.2f)" % [
				t, ev.colon, ev.chose_id, ev.propriete, _mot(ev.valeur), ev.credibilite, ev.certitude]
		"dogme":
			return "t=%.1fs %s DOGME : refuse une correction sur %s.%s (certitude %.2f inchangee)" % [
				t, ev.colon, ev.chose_id, ev.propriete, ev.certitude]
		"sourd":
			return "t=%.1fs %s N'ECOUTE PAS %s (credibilite %.2f sous le seuil)" % [
				t, ev.colon, ev.chose_id, ev.credibilite]
		"oublie":
			return "t=%.1fs %s OUBLIE %s.%s" % [t, ev.colon, ev.chose_id, ev.propriete]
		"bascule_fruit":
			return "t=%.1fs LE MONDE CHANGE : %s devient toxique et PERD sa cle comestible" % [
				t, ev.chose_id]
		"ecrit":
			return "t=%.1fs %s ECRIT %s -- %s chose(s) figee(s), fidelite %.2f" % [
				t, ev.colon, ev.chose_id, _mot(ev.valeur), ev.credibilite]
		"illisible":
			return "t=%.1fs %s : reserve d'integrite epuisee -- ILLISIBLE" % [t, ev.chose_id]
	return "t=%.1fs %s ?" % [t, ev.colon]

static func ligne_etat(t: float, etat_colon: Dictionary) -> String:
	return "t=%.1fs %s | curiosite %.2f | libre %.1fs | materiau %.1f | experimenter %.2f | %d croyance(s) | verbe=%s -> %s%s" % [
		t, etat_colon.id, etat_colon.curiosite, etat_colon.temps_libre, etat_colon.materiau,
		etat_colon.poids_experimenter, etat_colon.nb_croyances,
		String(etat_colon.verbe) if String(etat_colon.verbe) != "" else "(rien)",
		String(etat_colon.cible_id) if String(etat_colon.cible_id) != "" else "(rien)",
		"  [EMPOISONNE]" if bool(etat_colon.empoisonne) else "",
	]

static func texte_colon(etat_colon: Dictionary) -> String:
	var lignes: Array = ["%s%s" % [etat_colon.id, "  [EMPOISONNE]" if bool(etat_colon.empoisonne) else ""]]
	lignes.append("curiosite %.2f  libre %.1fs  materiau %.1f" % [
		etat_colon.curiosite, etat_colon.temps_libre, etat_colon.materiau])
	lignes.append("poids experimenter : %.2f" % etat_colon.poids_experimenter)
	var croyances: Dictionary = etat_colon.croyances
	if croyances.is_empty():
		lignes.append("(aucune croyance)")
	for chose_id in croyances:
		for propriete in croyances[chose_id]:
			lignes.append("%s.%s = %s (%.2f)" % [
				chose_id, propriete, _mot(croyances[chose_id][propriete].valeur),
				float(croyances[chose_id][propriete].certitude)])
	lignes.append("verbe : %s -> %s" % [
		String(etat_colon.verbe) if String(etat_colon.verbe) != "" else "(rien)",
		String(etat_colon.cible_id) if String(etat_colon.cible_id) != "" else "(rien)"])
	return "\n".join(lignes)

# L'etiquette d'un objet : ce qu'il EST vraiment, puis ce que le colon
# SELECTIONNE en croit -- cote a cote, pour que l'ecart se lise sans calcul.
static func texte_objet(objet: Dictionary, colon: Dictionary) -> String:
	var lignes: Array = [String(objet.id) + "  (reel)"]
	var vide := true
	for propriete in objet.proprietes:
		if String(propriete) == "profil_saillance":
			continue
		vide = false
		lignes.append("  %s = %s" % [propriete, _mot(objet.proprietes[propriete])])
	if vide:
		lignes.append("  (aucune propriete)")
	if colon.is_empty():
		return "\n".join(lignes)
	lignes.append("cru par %s" % String(colon.id))
	var crues: Dictionary = colon.proprietes.croyances.get(String(objet.id), {})
	if crues.is_empty():
		lignes.append("  (il ne sait rien)")
	for propriete in crues:
		lignes.append("  %s = %s (%.2f)" % [
			propriete, _mot(crues[propriete].valeur), float(crues[propriete].certitude)])
	return "\n".join(lignes)

static func texte_livre(livre: Dictionary, config: Dictionary, textes: Dictionary) -> String:
	if livre.is_empty():
		return ""
	var lignes: Array = [texte(cle_label_livre(livre, config), config, textes)]
	lignes.append("integrite %.1f" % integrite_livre(livre, config))
	lignes.append("fidelite %.2f" % float(livre.proprietes.get("fidelite", 0.0)))
	var contenu: Dictionary = livre.proprietes.get("contenu_croyance", {})
	for chose_id in contenu:
		for propriete in contenu[chose_id]:
			lignes.append("  %s.%s = %s" % [
				chose_id, propriete, _mot(contenu[chose_id][propriete].valeur)])
	return "\n".join(lignes)

static func texte_compteur(resultat: Dictionary, livre: Dictionary, config: Dictionary, textes: Dictionary, selection: String) -> String:
	var empoisonnes := 0
	var experimentateurs := 0
	for etat_colon in resultat.get("colons", []):
		if bool(etat_colon.empoisonne):
			empoisonnes += 1
		if float(etat_colon.poids_experimenter) > 0.0:
			experimentateurs += 1
	var etat_livre := "(aucun livre)"
	if not livre.is_empty():
		etat_livre = "%s %.1f" % [texte(cle_label_livre(livre, config), config, textes),
			integrite_livre(livre, config)]
	return ("%d empoisonne(s) | %d peut/peuvent experimenter | livre : %s | fruits colores selon %s\n" +
		"clic gauche : fruit sain/toxique   clic droit : degradation du livre   T : transmission   C : colon suivant") % [
		empoisonnes, experimentateurs, etat_livre, selection]

# ---------------------------------------------------------------------------
# Rendu (impur, Node) -- aucune decision, seulement couleurs et positions.
# ---------------------------------------------------------------------------

func _couleur(cle: String, defaut: Array) -> Color:
	var rgb: Array = _config.get("couleurs", {}).get(cle, defaut)
	return Color(rgb[0], rgb[1], rgb[2])

func _colon_selectionne() -> Dictionary:
	if _etat.colons.is_empty():
		return {}
	return _etat.colons[int(_etat.selection) % _etat.colons.size()]

# La couleur d'un objet dit ce que le colon selectionne EN CROIT, jamais ce
# qu'il est : vert = comestible cru, rouge = toxique cru, gris = inconnu.
func _couleur_croyance(objet: Dictionary, colon: Dictionary) -> Color:
	if colon.is_empty():
		return _couleur("cru_inconnu", [0.55, 0.55, 0.55])
	var crues: Dictionary = colon.proprietes.croyances.get(String(objet.id), {})
	if bool(crues.get(String(_config.propriete_toxique), {}).get("valeur", false)):
		return _couleur("cru_toxique", [0.85, 0.2, 0.2])
	if bool(crues.get(String(_config.propriete_comestible), {}).get("valeur", false)):
		return _couleur("cru_comestible", [0.3, 0.75, 0.35])
	return _couleur("cru_inconnu", [0.55, 0.55, 0.55])

func _creer_rendu() -> void:
	for objet in _etat.objets:
		_noeuds[objet.id] = _creer_carre(objet.position, TAILLE_OBJET,
			_couleur(String(objet.id), [0.5, 0.5, 0.5]))
		_labels[objet.id] = _creer_label()
	for colon in _etat.colons:
		_noeuds[colon.id] = _creer_carre(colon.position, TAILLE_COLON,
			_couleur("colon", [0.35, 0.55, 0.8]))
		_labels[colon.id] = _creer_label()
		var ligne := Line2D.new()
		ligne.width = LARGEUR_LIGNE
		ligne.default_color = _couleur("cible", [0.7, 0.7, 0.7])
		add_child(ligne)
		_lignes[colon.id] = ligne
	_label_compteur = Label.new()
	_label_compteur.add_theme_font_size_override("font_size", TAILLE_POLICE_COMPTEUR)
	_label_compteur.position = Vector2(10.0, 10.0)
	_couche_ui.add_child(_label_compteur)

func _creer_label() -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", TAILLE_POLICE_LABEL)
	add_child(label)
	return label

func _creer_carre(position: Vector3, taille: float, couleur: Color) -> ColorRect:
	var carre := ColorRect.new()
	carre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	carre.size = Vector2(taille, taille)
	carre.color = couleur
	carre.position = Vector2(position.x, position.y) - carre.size / 2.0
	add_child(carre)
	return carre

func _rafraichir_tout() -> void:
	var selectionne := _colon_selectionne()
	for objet in _etat.objets:
		var noeud: ColorRect = _noeuds[objet.id]
		if String(objet.id) == String(_config.pupitre_id):
			noeud.color = _couleur("pupitre", [0.45, 0.4, 0.35])
		elif objet.proprietes.has(String(_config.propriete_experimentable)):
			noeud.color = _couleur("objet_inconnu", [0.6, 0.45, 0.85])
		else:
			noeud.color = _couleur_croyance(objet, selectionne)
		_labels[objet.id].position = noeud.position + Vector2(TAILLE_OBJET + 8.0, 0.0)
		_labels[objet.id].text = texte_objet(objet, selectionne)

	if not _etat.livre.is_empty() and _noeud_livre == null:
		_noeud_livre = _creer_carre(_etat.livre.position + Vector3(0.0, 44.0, 0.0),
			TAILLE_LIVRE, _couleur("livre", [0.9, 0.8, 0.55]))
		_label_livre = _creer_label()
	if _noeud_livre != null:
		_noeud_livre.color = _couleur("livre_illisible", [0.4, 0.38, 0.35]) \
			if est_illisible(_etat.livre, _config) else _couleur("livre", [0.9, 0.8, 0.55])
		_label_livre.position = _noeud_livre.position + Vector2(TAILLE_LIVRE + 8.0, 0.0)
		_label_livre.text = texte_livre(_etat.livre, _config, _textes)

	if _dernier_resultat.is_empty():
		return
	for etat_colon in _dernier_resultat.colons:
		var colon := colon_par_id(_etat.colons, String(etat_colon.id))
		if colon.is_empty():
			continue
		var noeud: ColorRect = _noeuds[colon.id]
		if bool(etat_colon.empoisonne):
			noeud.color = _couleur("colon_empoisonne", [0.55, 0.2, 0.6])
		elif String(colon.id) == String(selectionne.get("id", "")):
			noeud.color = _couleur("colon_selectionne", [0.95, 0.85, 0.3])
		else:
			noeud.color = _couleur("colon", [0.35, 0.55, 0.8])
		_labels[colon.id].position = noeud.position + Vector2(-TAILLE_COLON, TAILLE_COLON + 6.0)
		_labels[colon.id].text = texte_colon(etat_colon)
		_tracer_ligne(colon, etat_colon)
	_label_compteur.text = texte_compteur(_dernier_resultat, _etat.livre, _config, _textes,
		String(selectionne.get("id", "")))

# UNE ligne par colon, vers la chose que sa DECISION vise -- donc vers ce qu'il
# CROIT saillant, jamais vers ce que le monde dit.
func _tracer_ligne(colon: Dictionary, etat_colon: Dictionary) -> void:
	var ligne: Line2D = _lignes[colon.id]
	var cible_id := String(etat_colon.cible_id)
	if cible_id == "" or String(etat_colon.verbe) == "":
		ligne.points = PackedVector2Array()
		return
	var wrapper = _etat.monde.par_id(cible_id)
	if wrapper == null:
		ligne.points = PackedVector2Array()
		return
	var pos: Vector3 = wrapper.chose.position
	ligne.points = PackedVector2Array([
		Vector2(colon.position.x, colon.position.y), Vector2(pos.x, pos.y)])

func _poser_camera() -> void:
	var decl: Dictionary = _config.get("camera", {})
	var pos: Array = decl.get("position", [0.0, 0.0, 0.0])
	var camera := Camera2D.new()
	camera.position = Vector2(pos[0], pos[1])
	camera.zoom = Vector2(decl.get("zoom", 1.0), decl.get("zoom", 1.0))
	camera.enabled = true
	add_child(camera)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
