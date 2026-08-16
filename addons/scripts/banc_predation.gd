extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_predation.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1). AUCUN MECANISME DU COEUR TOUCHE,
# AUCUN .gd neuf.
#
# CE QUE CE BANC EST, ET IL FAUT LE DIRE D'ENTREE : un ORCHESTRATEUR. Les
# mecanismes existent tous ; ce qui n'existait pas, c'est l'ORDRE FIXE qui les
# fait tenir ensemble tick apres tick, plus la naissance et le retrait. Ce
# fichier ne contient donc AUCUNE mecanique neuve : il compose dix-sept appels,
# dans un ordre ecrit et assume, a des mecanismes tous deja fermes.
#
# ---- L'ORDRE FIXE ET ASSUME (avancer(), une fonction, tout le tick) ----
#  1. senescence.gd  -- l'age monte (annees_par_seconde recu du cablage)
#  2. stade.gd       -- le stade suit l'age, jamais en arriere
#  3. depense.gd     -- l'energie descend (predateur) ou remonte (proie,
#                       cout_base NEGATIF)
#  4. perception.gd  -- qui voit quoi (UNE SEULE FOIS par tick, reutilisee
#                       au pas 12 ET au pas 14)
#  5. comptage.gd    -- combien de proies, combien de predateurs (jamais un
#                       objet-agregat : docs/design.md, « Les collectifs
#                       n'existent pas »)
#  6. hierarchie     -- score = poids_masse x masse + poids_force x force,
#                       RECALCULE A NEUF
#  7. consommer.gd   -- le dominant mange, conservatif
# 7b. seuil_etat.gd  -- miroir plat de manque puis la mort (UNE entree locale
#                       pour DEUX causes : proie videe, predateur affame)
#  8. produit.gd     -- un mort devient un reste
#  9. charge.gd      -- l'agression monte sous trois causes SYNTHETISEES
# 10. bifurcation.gd -- laquelle des trois domine (biais COMPOSE)
# 11. deformation.gd -- la cible de la sortie gagnante monte en saillance
# 12. agir.gd        -- proximite -> dominance -> agir
# 13. mouvement      -- bouger_vers / bouger_selon, puis surcout_action
# 14. accouplement.gd -- sous GATE DE CABLAGE (reserves hautes)
# 15. gestation.gd   -- le compteur, sur LE PORTEUR SEUL
# 16. heredite.gd    -- le kit genetique, puis Objet.fabriquer : la naissance
# 17. retrait        -- les morts quittent le Monde, RECONSTRUIT DU NEANT
#
# TROIS INVERSIONS SERAIENT FAUSSES, et c'est pour elles que l'ordre est ecrit :
# 7b avant 8 (on ne produit pas le reste d'un mort qu'on n'a pas encore declare
# mort) ; 9/10 avant 11 (la deformation vise la cible de la sortie GAGNANTE, la
# resoudre apres coup la ferait viser celle du tick precedent) ; 11 avant 12 (la
# deformation doit etre posee AVANT que la saillance ne soit evaluee, sinon un
# predateur qui bascule ne voit sa proie amplifiee qu'au tick suivant --
# invisible a l'oeil, mesurable au test).
#
# ---- CE QUE CE BANC MONTRE, ET QU'AUCUN AUTRE NE MONTRE ----
#
# 1) UNE POPULATION QUI NAIT ET MEURT EN CONTINU. Les autres bancs ont un
#    casting FIXE ; banc_reproduction.gd fait naitre UN enfant, une fois, d'UN
#    couple. Ici la naissance et le retrait sont le geste CENTRAL du tick, pas
#    un evenement. Le retrait passe par la RECONSTRUCTION du Monde -- monde.gd
#    n'a aucune fonction de retrait.
#
# 2) UNE HIERARCHIE QUI DECIDE QUI MANGE, ET ELLE EST HEREDITAIRE. Le score est
#    du CABLAGE PUR, et les deux mecanismes qu'on croirait candidats ne savent
#    pas le faire : dominance.gd ECRASE, il n'elit pas ; frappe.gd ne connait
#    que deux sources de critere, aucune « propriete plate », en ajouter une
#    serait modifier le coeur. Somme ponderee recalculee a neuf, tri, le premier
#    mange et les autres attendent, push_error sur egalite stricte -- on ne
#    tranche pas, on refuse le silence. Et comme la force est la cible d'un
#    gene, un petit de dominant nait plus fort : la hierarchie se transmet sans
#    une ligne de code pour le dire.
#
# 3) TROIS CAUSES D'AGRESSION, UNE SEULE CHARGE, UNE SEULE SORTIE. charge.gd
#    SOMME les trois contributions -- il repond a « attaque-t-il ? » -- mais la
#    somme EFFACE L'ORIGINE ; bifurcation.gd prend l'argmax des MEMES trois
#    produits, il repond a « pourquoi ? ». Il faut les deux. Le biais est
#    COMPOSE par le cablage, et c'est OBLIGATOIRE : bifurcation.gd multiplie
#    chaque biais par UNE grandeur commune, qui ne peut donc JAMAIS departager
#    deux biais.
#
# 4) LES CYCLES PROIE-PREDATEUR EMERGENT DU COUPLAGE, ils ne sont ecrits nulle
#    part. Proies nombreuses -> les predateurs mangent -> leurs reserves montent
#    -> le gate de reproduction s'ouvre -> plus de predateurs -> les proies
#    diminuent -> les predateurs meurent de faim -> les proies remontent. LE
#    DELAI vient de la gestation ET des stades juveniles (un nouveau-ne n'est
#    pas fertile) : sans lui la reponse serait instantanee et il n'y aurait pas
#    d'oscillation, seulement un equilibre.
#
# ---- AUCUN HASARD, SAUF UN, SEEDE ET RECU EN PARAMETRE ----
# Le seul RNG du fichier est celui passe a heredite.gd (mutation gaussienne),
# seede depuis la donnee. Ni errance aleatoire, ni tirage de predation, ni
# tirage de mort : un animal qui ne decide rien reste IMMOBILE, il n'erre pas au
# hasard. La REGLE ANTI-BRUIT de docs/design.md vaut pour tout DECIDEUR, pas
# seulement pour les colons.
#
# ---- DEUX ECRIVAINS UNIQUES ----
# poser_surcout_action et poser_poids_verbes sont les SEULS endroits du fichier
# qui ecrivent ces deux cles, et chacun les ecrit EN ENTIER depuis la donnee,
# jamais par increment. Deux morceaux de cablage qui y auraient touche chacun de
# leur cote se seraient ecrases EN SILENCE : aucun test n'aurait rougi, le
# nombre aurait seulement ete faux.
# UN TICK DE RETARD INHERENT : le surcout est ecrit au pas 13, seul instant ou
# l'on sait si l'animal a bouge, et consomme par depense.gd au pas 3 du tick
# SUIVANT. L'ordre inverse serait circulaire.
#
# ---- QUATRE DECISIONS DE CE BANC, prises et dites ----
# (a) LE GATE DE MOUVEMENT. Les deux proprietes en jeu proposent LES MEMES deux
#     verbes et un animal n'a QU'UN poids_verbes : une proie dont la fuite
#     domine la resout AUSSI sur une congenere, et le troupeau se disperserait
#     jusqu'aux bords sans jamais s'accoupler. Le cablage n'applique donc un
#     mouvement que si la propriete portee par la CIBLE figure dans la liste
#     "poursuit" ou "fuit" de l'espece. Toute autre decision laisse l'animal
#     immobile.
# (b) UN SEUL DES DEUX GESTE, ET L'AUTRE EST LIBERE AU MEME TICK. Especes
#     sans sexes : role_gestation vaut "les_deux", la gestation tombe donc des
#     deux cotes. Les laisser avancer ferait naitre DEUX petits d'un seul
#     accouplement. Le departage est UNE CONVENTION DE CE FICHIER -- porte
#     celui dont l'id est le plus petit alphabetiquement, l'autre est libere
#     au meme tick, sans quoi il resterait indisponible pour toujours.
# (c) L'ACCUMULATEUR D'ACCOUPLEMENT EST VIDE A LA NAISSANCE, sur les DEUX
#     parents. accouplement.gd ne le fait jamais -- son accumulation est
#     IRREVERSIBLE par construction. Sans ce geste, une gestation retiree serait
#     reposee AU TICK SUIVANT, l'exposition passee restant creditee pour
#     toujours, et le gate sur la reserve d'energie ne retiendrait plus rien.
# (d) LES RESTES NE SONT PAS AJOUTES AU MONDE -- decision de COUT, pas un
#     oubli : monde.gd:choses_dans_rayon est un balayage LINEAIRE et
#     perception.gd demande de signaler tout depassement d'une cinquantaine de
#     candidats par requete. Ils sont fabriques REELLEMENT par produit.gd et
#     affiches, mais percus par personne.
#
# ---- LIMITES DITES, PAS MASQUEES ----
# - Aucun combat n'a lieu entre predateurs : l'agression territoriale les fait
#   se CHARGER (la saillance de l'intrus monte, le verbe resout l'approche),
#   jamais s'infliger des degats. frappe.gd n'est pas cable ici.
# - Un mort reste dans la liste jusqu'au pas 17 du meme tick ; les pas 9 a 16
#   sont donc gates par est_mort. Sans ce gate un cadavre deciderait, se
#   deplacerait (sa vitesse est ecrasee a zero, mais son surcout serait ecrit)
#   et pourrait meme s'accoupler.
# - Les perceptions du pas 4 sont reutilisees au pas 14, donc APRES le mouvement
#   du pas 13 : l'accouplement lit une perception vieille d'un demi-tick. Sans
#   consequence puisque c'est une accumulation continue, dit pour qu'on ne le
#   redecouvre pas.
# - Le cout des requetes spatiales grandit avec la population : chaque animal
#   vivant fait sa propre requete chaque tick sur un balayage lineaire. Ce n'est
#   pas un blocage pour un banc d'observation ; c'en serait un pour le jeu.
#   Signale, jamais optimise en silence.
# - EGALITE STRICTE TRANSITOIRE, et c'est un fait du mecanisme, pas un defaut du
#   cablage. bifurcation.gd ALARME des que deux sorties sont a egalite stricte
#   au sommet, et sa convention est la bonne. Mais ses appelants precedents lui
#   passaient des grandeurs DISCRETES, ou l'egalite ne survient que sur une
#   donnee mal posee. Ici les trois contributions sont CONTINUES et varient avec
#   les distances : elles se croisent donc NECESSAIREMENT, et a chaque
#   croisement une alarme part. Elle est juste -- a cet instant precis rien ne
#   departage vraiment les deux causes -- et sans consequence, la premiere
#   sortie declaree etant conservee. CE QU'UN FUTUR APPELANT DOIT EN RETENIR :
#   passer des grandeurs continues a bifurcation.gd est legitime, mais la
#   console en portera la trace a chaque croisement, et ce n'est PAS le signe
#   d'une donnee cassee. La meme egalite cote hierarchie est evitee par
#   CALIBRATION, la masse et la force ne variant pas continument.
#
# Deux moities, meme decoupage que les autres bancs : le Node charge, construit
# et affiche ; tout le reste est en fonctions statiques pures, testables
# headless.

const Objet = preload("res://scripts/objet.gd")
const Monde = preload("res://scripts/monde.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")
const Perception = preload("res://scripts/perception.gd")
const Proximite = preload("res://scripts/proximite.gd")
const Dominance = preload("res://scripts/dominance.gd")
const Agir = preload("res://scripts/agir.gd")
const Fuite = preload("res://scripts/fuite.gd")
const Charge = preload("res://scripts/charge.gd")
const Comptage = preload("res://scripts/comptage.gd")
const Bifurcation = preload("res://scripts/bifurcation.gd")
const Deformation = preload("res://scripts/deformation.gd")
const EtatDuree = preload("res://scripts/etat_duree.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")
const SeuilEtat = preload("res://scripts/seuil_etat.gd")
const Depense = preload("res://scripts/depense.gd")
const Consommer = preload("res://scripts/consommer.gd")
const Produit = preload("res://scripts/produit.gd")
const Senescence = preload("res://scripts/senescence.gd")
const Stade = preload("res://scripts/stade.gd")
const Accouplement = preload("res://scripts/accouplement.gd")
const Gestation = preload("res://scripts/gestation.gd")
const Heredite = preload("res://scripts/heredite.gd")
const ExpressionGenetique = preload("res://scripts/expression.gd")

const SORTIE_AUCUNE := ""

var _config: Dictionary = {}
var _etats: Dictionary = {}
var _catalogue_canaux: Dictionary = {}
var _catalogue_deformations: Dictionary = {}
var _catalogue_actions: Dictionary = {}
var _orientations: Dictionary = {}
var _profils_saillance: Dictionary = {}
var _catalogue_reproduction: Dictionary = {}
var _catalogue_heredite: Dictionary = {}
var _catalogue_types: Dictionary = {}
var _materiaux: Dictionary = {}

var _etat: Dictionary = {}
var _palier_temps := 0
var _prochaine_trace := 0.0
# Memoire des traces deja imprimees -- voir lignes_evenements : une ligne par
# TRANSITION, jamais une par tick.
var _precedents: Dictionary = {"repas": {}, "sorties": {}}

var _couche_ui: CanvasLayer
var _noeuds: Dictionary = {}
var _labels: Dictionary = {}
var _noeuds_restes: Dictionary = {}
var _label_compteur: Label
var _barre_proies: ColorRect
var _barre_predateurs: ColorRect
var _fond_proies: ColorRect
var _fond_predateurs: ColorRect
var _label_courbe: Label

# Le rendu relit le rapport du DERNIER pas, jamais une valeur recalculee a cote
# -- le label ne peut donc pas mentir sur ce que l'animal subit (meme discipline
# que banc_menace_combat.gd/banc_fatigue_circadien.gd).
var _dernier_rapport: Dictionary = {}

func _ready() -> void:
	_config = _charger_json("res://data/banc_predation.json")
	_etats = _charger_json("res://data/etats.json")
	_catalogue_canaux = _charger_json("res://data/canaux.json")
	_catalogue_deformations = _charger_json("res://data/deformations.json")
	_catalogue_actions = _charger_json("res://data/types_choses.json")
	_orientations = _charger_json("res://data/orientations.json")
	_profils_saillance = _charger_json("res://data/profils_saillance.json")
	_catalogue_reproduction = _charger_json("res://data/reproduction.json")
	_catalogue_heredite = _charger_json("res://data/heredite.json")
	_materiaux = _charger_json("res://data/materiaux.json")
	_catalogue_types = catalogue_types(_config, _charger_json("res://data/types.json"))

	_etat = etat_initial(_config, _catalogue_types)

	_couche_ui = CanvasLayer.new()
	add_child(_couche_ui)
	_creer_rendu_fixe()
	_poser_camera()
	print(_ligne_ouverture(_config, _etat))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_palier_temps = palier_suivant(_palier_temps, _config)
		print(_ligne_palier(_etat.temps, facteur_du_palier(_config, _palier_temps)))

func _process(delta: float) -> void:
	var rapport := avancer(
		_etat, _config, _etats, _catalogue_canaux, _catalogue_deformations,
		_profils_saillance, _catalogue_actions, _orientations,
		_catalogue_reproduction, _catalogue_heredite, _catalogue_types,
		_materiaux, delta * facteur_du_palier(_config, _palier_temps),
	)
	_dernier_rapport = rapport

	for ligne in lignes_evenements(_etat.temps, rapport, _precedents):
		print(ligne)
	if _etat.temps >= _prochaine_trace:
		_prochaine_trace = _etat.temps + float(_config.periode_trace_s)
		print(ligne_population(_etat.temps, rapport, facteur_du_palier(_config, _palier_temps)))

	_rafraichir_tout()

# =====================================================================
# ---- Fonctions PURES, testables headless (test_banc_predation.gd) ----
# =====================================================================

# ---- Construction ----

# Le catalogue de fabrication : les types LOCAUX du banc, PLUS la seule entree
# de data/types.json dont produit.gd a besoin pour resoudre son type_produit --
# ET LES PAQUETS DONT CETTE ENTREE HERITE, sans quoi Objet.fabriquer alarme
# (« type 'reste_nourriture' declare heriter du paquet 'objet_physique', absent
# de la table ») et fabrique un objet sans masse. DEFAUT REEL TROUVE AU
# PREMIER LANCEMENT DU TEST, pas raisonne a l'avance : la resolution de
# « herite » n'est PAS recursive (objet.gd le documente), mais elle exige que
# chaque paquet NOMME soit present dans la table qu'on lui passe. Piocher une
# entree de data/types.json sans ses paquets est donc toujours faux.
# types_partages est passe ENTIER par l'appelant ; rien d'autre que cette
# entree et ses paquets n'entre dans ce banc.
static func catalogue_types(config: Dictionary, types_partages: Dictionary) -> Dictionary:
	var table: Dictionary = config.get("types_locaux", {}).duplicate(true)
	table.erase("_note")
	var type_reste: String = String(config.get("produit_reste", {}).get("type_produit", ""))
	if type_reste == "" or not types_partages.has(type_reste):
		return table
	table[type_reste] = types_partages[type_reste].duplicate(true)
	for nom_paquet in table[type_reste].get("herite", []):
		if types_partages.has(nom_paquet):
			table[String(nom_paquet)] = types_partages[nom_paquet].duplicate(true)
		else:
			push_error("banc_predation : le type de reste '%s' herite du paquet '%s', absent de data/types.json" % [type_reste, nom_paquet])
	return table

# Un animal, fabrique par Objet.fabriquer (via BancCommun.fabriquer_colon, qui
# pose en plus attaches/forme/poids_verbes depuis la declaration et les deux
# champs d'inertie action_en_cours/action_precedente qu'agir.gd relit).
# L'expression genetique tourne UNE FOIS ICI et jamais plus (voir
# data/banc_predation.json:_note_genes -- expression.gd rappele chaque tick
# relit la valeur qu'il vient d'ecrire et diverge sans borne, mesure deux fois
# dans le depot).
static func fabriquer_animal(
	id: String,
	nom_type: String,
	position: Vector3,
	biais_agression: Dictionary,
	config: Dictionary,
	catalogue_types: Dictionary,
	genes_etat: Dictionary,
) -> Dictionary:
	var est_pred: bool = catalogue_types.get(nom_type, {}).has(String(config.propriete_predateur))
	var decl := {
		"position": [position.x, position.y, position.z],
		"attaches": [],
		"forme": (config.forme_predateur if est_pred else config.forme_proie).duplicate(true),
		"poids_verbes": (config.poids_verbes_predateur if est_pred else config.poids_verbes_proie).duplicate(true),
	}
	var animal := BancCommun.fabriquer_colon(id, nom_type, decl, catalogue_types)
	if animal.is_empty():
		return {}
	animal.proprietes["age"] = float(config.get("age_depart", 0.0))
	if not biais_agression.is_empty():
		animal.proprietes["biais_agression"] = biais_agression.duplicate(true)
	if not genes_etat.is_empty():
		animal.proprietes["genes_etat"] = genes_etat.duplicate(true)
	ExpressionGenetique.appliquer(
		animal, ExpressionGenetique.exprimer(animal, config.get("catalogue_genes", {}), {}, {}))
	return animal

# L'etat COMPLET du banc, en un seul Dictionary -- c'est lui, et non un champ
# de Node, que avancer() mute : le Monde y est REMPLACE a chaque retrait (pas 17),
# ce qu'aucune signature « monde recu en parametre » ne permettrait (monde.gd
# n'a aucune fonction de retrait, audit constat E).
static func etat_initial(config: Dictionary, catalogue_types: Dictionary) -> Dictionary:
	# AUCUN NOM D'ESPECE EN DUR, pas meme ici : un banc jetable aurait le droit
	# d'en nommer une (CLAUDE.md, l'exception), mais `populations_initiales`
	# (espece -> nom de la liste de declarations) suffit a l'eviter, et le
	# lecteur n'a plus a se demander si le code est couple aux deux especes de
	# CE banc. Meme table `type_par_espece` que la naissance, meme resolution.
	var animaux: Array = []
	var table_espece: Dictionary = config.get("type_par_espece", {})
	for espece in config.get("populations_initiales", {}):
		var nom_type := String(table_espece.get(espece, ""))
		for decl in config.get(String(config.populations_initiales[espece]), []):
			var pos: Array = decl.position
			animaux.append(fabriquer_animal(
				String(decl.id), nom_type, Vector3(pos[0], pos[1], pos[2]),
				decl.get("biais_agression", {}), config, catalogue_types,
				decl.get("genes_etat", {})))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(config.get("seed", 0))
	var etat := {
		"animaux": animaux,
		"restes": [],
		"monde": null,
		"rng": rng,
		"temps": 0.0,
		"tick": 0,
		"naissances": 0,
		"morts": 0,
		"compteur_enfant": 0,
	}
	etat["monde"] = monde_reconstruit(animaux)
	return etat

# Le Monde RECONSTRUIT DU NEANT, les vivants ré-ajoutés PAR REFERENCE (leurs
# positions, charges et deformations survivent donc au retrait). monde.gd n'a
# aucune fonction de retrait -- dette deja recensee, contournee de la meme
# facon par banc_menace_combat.gd:_reconstruire_monde et
# banc_elimination_salete.gd ; ici le geste est joue A CHAQUE TICK et non a un
# clic, c'est ce que l'audit appelle « le geste central du cablage ».
static func monde_reconstruit(animaux: Array) -> Variant:
	return BancCommun.monde_depuis([{"choses": animaux, "type_depuis": "espece_reproduction"}])

# ---- Lectures pures sur un animal ----

static func espece_de(animal: Dictionary) -> String:
	return String(animal.proprietes.get("espece_reproduction", ""))

static func est_predateur(animal: Dictionary, config: Dictionary) -> bool:
	return animal.proprietes.get(String(config.propriete_predateur), false)

static func est_proie(animal: Dictionary, config: Dictionary) -> bool:
	return animal.proprietes.get(String(config.propriete_proie), false)

static func est_mort(animal: Dictionary, config: Dictionary) -> bool:
	return animal.proprietes.get("etats_actifs", []).has(String(config.etat_mort))

static func est_juvenile(animal: Dictionary) -> bool:
	return animal.proprietes.get("stades_juveniles", []).has(animal.proprietes.get("stade", ""))

static func vivants(animaux: Array, config: Dictionary) -> Array:
	var resultat: Array = []
	for animal in animaux:
		if not est_mort(animal, config):
			resultat.append(animal)
	return resultat

static func energie(animal: Dictionary, config: Dictionary) -> float:
	return float(animal.proprietes.get("reserves", {})
		.get(String(config.nom_reserve_energie), {}).get("reserve", 0.0))

# LE SCORE DE HIERARCHIE (audit ligne 7). SOMME PONDEREE DE PROPRIETES,
# RECALCULEE A NEUF a chaque appel -- jamais un '+=', jamais une valeur
# stockee : c'est ce recalcul, et lui seul, qui empeche un champ derive de
# deriver (resultat negatif mesure deux fois dans le depot, voir
# banc_bonheur.gd:calculer_bonheur, dont ceci est la copie exacte du geste).
# LECTURE PURE : n'ecrit rien, ne mute rien.
static func score_hierarchie(animal: Dictionary, config: Dictionary) -> float:
	var regle: Dictionary = config.get("hierarchie", {})
	var proprietes: Dictionary = animal.proprietes
	return float(regle.get("poids_masse", 0.0)) * float(proprietes.get(String(config.nom_masse), 0.0)) \
		+ float(regle.get("poids_force", 0.0)) * float(proprietes.get(String(config.nom_force), 0.0))

# ---- Ecrivains uniques ----

# UNIQUE ECRIVAIN de la reserve d'energie hors consommer.gd/depense.gd : rien
# dans le coeur ne borne le HAUT d'une reserve (constat repaye par
# banc_fertilite.gd:plafonner_fertilite). Sans lui, une proie qui regagne
# 2.5/s monterait sans fin et son gate de reproduction ne redescendrait jamais.
static func plafonner_energie(animal: Dictionary, config: Dictionary) -> void:
	var canal: Dictionary = animal.proprietes.get("reserves", {}).get(String(config.nom_reserve_energie), {})
	if canal.is_empty():
		return
	canal["reserve"] = min(float(canal.get("reserve", 0.0)), float(config.capacite_energie))

# UNIQUE ECRIVAIN du miroir plat 'manque_energie' (audit, constat B) :
# seuil_etat.gd ne sait lire qu'une cle PLATE (jamais
# proprietes.reserves.<nom>.reserve) et ne compare que VERS LE HAUT, donc
# « l'energie descend sous un seuil » s'ecrit « le manque monte au-dessus d'un
# seuil ». RECALCULE A NEUF chaque tick, JAMAIS accumule par '+=' -- c'est ce
# recalcul, et lui seul, qui rend l'etat reversible (patron
# banc_faim_thermo.gd). Rend la valeur posee pour que l'appelant la relise sans
# rien recalculer.
static func poser_manque_energie(animal: Dictionary, config: Dictionary) -> float:
	var manque: float = max(0.0, float(config.capacite_energie) - energie(animal, config))
	animal.proprietes[String(config.nom_manque_energie)] = manque
	return manque

# UNIQUE ECRIVAIN de poids_verbes (audit, constat C). Ecrit la table EN ENTIER
# depuis la donnee, jamais un increment sur la precedente. Idempotent, rappele
# a chaque tick : deux tables successives ne peuvent donc pas se melanger.
static func poser_poids_verbes(animal: Dictionary, config: Dictionary) -> void:
	var table: Dictionary = config.poids_verbes_predateur if est_predateur(animal, config) \
		else config.poids_verbes_proie
	animal.proprietes["poids_verbes"] = table.duplicate(true)

# UNIQUE ECRIVAIN de surcout_action (audit, constat C -- meme piege ferme par
# banc_faim_thermo.gd:poser_surcout_action). Les DEUX contributions sont
# sommees puis ecrites d'un seul geste ; la decomposition est rendue pour que
# le label la relise sans jamais rien recalculer.
static func poser_surcout_action(animal: Dictionary, a_bouge: bool, agressif: bool, config: Dictionary) -> Dictionary:
	var mouvement: float = float(config.surcout_mouvement) if a_bouge else 0.0
	var agression: float = float(config.surcout_agression) if agressif else 0.0
	var canal: Dictionary = animal.proprietes.get("reserves", {}).get(String(config.nom_reserve_energie), {})
	if not canal.is_empty():
		canal["surcout_action"] = mouvement + agression
	return {"mouvement": mouvement, "agression": agression, "total": mouvement + agression}

# ---- Pas 5 : le comptage ----

# Deux appels a comptage.gd sur la liste des VIVANTS, zero ligne de mecanisme.
# Le catalogue de regles est LOCAL au banc (format exact de data/comptages.json,
# passe tel quel -- comptage.gd recoit toujours son catalogue en parametre),
# meme geste que banc_menace_combat.gd:ratio_effectifs. AUCUN objet-agregat
# n'est pose : la population est un CALCUL refait a chaque tick
# (docs/design.md, « Les collectifs n'existent pas -- un resume lu, pas un
# objet pose » ; precedent banc_comptage.gd).
static func effectifs(animaux: Array, config: Dictionary) -> Dictionary:
	var comptages: Dictionary = config.get("comptages", {})
	var liste := vivants(animaux, config)
	return {
		"proies": Comptage.compter(liste, String(config.regle_proie), comptages),
		"predateurs": Comptage.compter(liste, String(config.regle_predateur), comptages),
	}

# ---- Pas 7 : le repas, sous hierarchie ----

# LE CŒUR DE LA LIGNE 7. Pour chaque proie vivante, les predateurs vivants a
# portee_morsure sont TRIES par score de hierarchie decroissant : le premier
# mange, les autres ATTENDENT. Egalite stricte au sommet : push_error nommant
# les ex aequo, premier trouve conserve, aucun departage -- convention unique
# et constante du depot (frappe.gd:selectionner, agir.gd:_verbe_par_poids,
# bifurcation.gd:resoudre : on ne tranche pas, on refuse le silence).
#
# UN PREDATEUR NE MANGE QU'UNE PROIE PAR TICK (deja_servis) : sans cette garde
# un dominant a portee de deux proies les viderait toutes les deux au meme
# pas -- consommer.gd est conservatif, rien ne serait cree, mais la hierarchie
# ne se verrait plus (le second n'attendrait jamais). L'ordre de parcours des
# proies est celui de la liste, donc DETERMINISTE.
#
# Rend un Array de { proie_id, mangeur_id, score_mangeur, attendants } -- ne
# MUTE RIEN, le transfert lui-meme est fait par l'appelant (avancer), pour que
# le tri reste lisible et testable sans effet de bord.
static func repas_du_tick(animaux: Array, config: Dictionary) -> Array:
	var portee: float = float(config.portee_morsure)
	var proies: Array = []
	var predateurs: Array = []
	for animal in vivants(animaux, config):
		if est_proie(animal, config):
			proies.append(animal)
		elif est_predateur(animal, config):
			predateurs.append(animal)

	var deja_servis: Dictionary = {}
	var repas: Array = []
	for proie in proies:
		var pretendants: Array = []
		for predateur in predateurs:
			if deja_servis.has(predateur.id):
				continue
			if proie.position.distance_to(predateur.position) <= portee:
				pretendants.append(predateur)
		if pretendants.is_empty():
			continue
		pretendants.sort_custom(func(a, b): return score_hierarchie(a, config) > score_hierarchie(b, config))
		var mangeur: Dictionary = pretendants[0]
		var meilleur: float = score_hierarchie(mangeur, config)
		var a_egalite: Array = []
		for pretendant in pretendants:
			if is_equal_approx(score_hierarchie(pretendant, config), meilleur):
				a_egalite.append(String(pretendant.id))
		if a_egalite.size() > 1:
			push_error("banc_predation : predateurs a egalite stricte de hierarchie (%s) sur '%s' : %s -- '%s' conserve (premier trie), aucun departage" %
				[meilleur, proie.id, a_egalite, mangeur.id])
		deja_servis[mangeur.id] = true
		var attendants: Array = []
		for i in range(1, pretendants.size()):
			attendants.append(String(pretendants[i].id))
		repas.append({
			"proie_id": String(proie.id),
			"proie": proie,
			"mangeur_id": String(mangeur.id),
			"mangeur": mangeur,
			"score_mangeur": meilleur,
			"attendants": attendants,
		})
	return repas

# ---- Pas 9/10 : les trois causes d'agression ----

static func urgence_faim(animal: Dictionary, config: Dictionary) -> float:
	return clamp(float(animal.proprietes.get(String(config.nom_manque_energie), 0.0))
		/ float(config.capacite_energie), 0.0, 1.0)

# GARDE reprise de banc_menace_combat.gd:ratio_effectifs : une reference nulle
# rendrait INF et ferait exploser la charge EN SILENCE.
static func densite_intrus(animal: Dictionary, animaux: Array, config: Dictionary) -> float:
	var reference: float = float(config.densite_intrus_reference)
	if reference <= 0.0:
		return 0.0
	var portee: float = float(config.portee_territoire)
	var compte := 0
	for autre in vivants(animaux, config):
		if autre.id == animal.id or not est_predateur(autre, config):
			continue
		if animal.position.distance_to(autre.position) <= portee:
			compte += 1
	return min(1.0, float(compte) / reference)

# Vaut 0.0 EXACTEMENT tant qu'aucun juvenile de la MEME espece n'est a portee
# -- ce qui est le cas au premier tick (toute la population demarre adulte) :
# cette cause ne peut donc gagner qu'apres une naissance, et c'est le sujet.
static func proximite_menace_petits(animal: Dictionary, animaux: Array, config: Dictionary) -> float:
	var espece := espece_de(animal)
	var a_des_petits := false
	for autre in vivants(animaux, config):
		if autre.id == animal.id or espece_de(autre) != espece or not est_juvenile(autre):
			continue
		if animal.position.distance_to(autre.position) <= float(config.portee_petits):
			a_des_petits = true
			break
	if not a_des_petits:
		return 0.0
	var portee: float = float(config.portee_menace_petits)
	if portee <= 0.0:
		return 0.0
	var plus_proche := INF
	for autre in vivants(animaux, config):
		if autre.id == animal.id or not est_predateur(autre, config):
			continue
		plus_proche = min(plus_proche, animal.position.distance_to(autre.position))
	if plus_proche == INF:
		return 0.0
	return max(0.0, 1.0 - plus_proche / portee)

# LES MEMES TROIS PRODUITS SERVENT DEUX FOIS, et c'est la decision centrale de
# ce cablage : poids de cause pour charge.gd (qui les SOMME -- « attaque-t-il ? »)
# ET biais compose pour bifurcation.gd (qui en prend l'ARGMAX -- « pourquoi ? »).
# Un seul calcul, deux lectures : impossible qu'ils divergent.
#
# LE BIAIS DOIT ETRE COMPOSE, ce n'est pas un contournement mais la seule voie
# que le mecanisme laisse, et il le dit lui-meme (bifurcation.gd, « LIMITE
# REELLE DE CETTE LOI ») : la grandeur passee est UN SEUL SCALAIRE commun a
# toutes les sorties, elle multiplie donc tous les scores par le meme nombre et
# NE CHANGE JAMAIS QUI GAGNE. Faire dependre le choix de la SITUATION exige de
# composer le biais cote cablage. Le biais PERSONNEL (proprietes.biais_agression)
# n'est jamais reecrit : ceci est une LECTURE, refaite a neuf chaque tick.
static func contributions_agression(animal: Dictionary, animaux: Array, config: Dictionary) -> Dictionary:
	var biais: Dictionary = animal.proprietes.get("biais_agression", {})
	var sorties: Array = config.get("sorties_agression", [])
	var grandeurs := [
		urgence_faim(animal, config),
		densite_intrus(animal, animaux, config),
		proximite_menace_petits(animal, animaux, config),
	]
	var contributions: Dictionary = {}
	for i in range(sorties.size()):
		var sortie := String(sorties[i])
		var grandeur: float = grandeurs[i] if i < grandeurs.size() else 0.0
		contributions[sortie] = float(biais.get(sortie, 0.0)) * grandeur
	return contributions

# LES CAUSES SYNTHETISEES de charge.gd (troisieme famille du depot, apres
# banc_nutrition.gd/banc_fatigue_circadien.gd/banc_menace_combat.gd) :
# { position: celle de l'animal, poids } a portee_charge 0.0 -- l'animal est sa
# PROPRE cause, charge.gd ne scanne jamais le monde. Une contribution nulle
# n'entre PAS dans la liste : c'est l'Array VIDE, jamais un poids a 0.0, qui
# declenche la redescente autonome de charge.gd (taux_decroissance n'est
# applique que si la somme des poids a portee est nulle ce pas).
static func causes_agression(animal: Dictionary, contributions: Dictionary) -> Array:
	var causes: Array = []
	for sortie in contributions:
		if float(contributions[sortie]) > 0.0:
			causes.append({"position": animal.position, "poids": float(contributions[sortie])})
	return causes

static func charge_agression(animal: Dictionary, config: Dictionary) -> float:
	return float(animal.proprietes.get("etats", {})
		.get(String(config.nom_canal_agression), {}).get("charge", 0.0))

static func agression_franchie(animal: Dictionary, config: Dictionary) -> bool:
	return animal.proprietes.get(String(config.nom_marqueur_agression), false)

# La sortie ACTIVE, lue sur etats_actifs -- jamais une variable tenue a cote.
static func sortie_active(animal: Dictionary, config: Dictionary) -> String:
	var actifs: Array = animal.proprietes.get("etats_actifs", [])
	for sortie in config.get("sorties_agression", []):
		if actifs.has(String(sortie)):
			return String(sortie)
	return SORTIE_AUCUNE

# BIFURQUER PUIS POSER (patron exact banc_menace_combat.gd:relayer_bifurcation).
# Tant que le marqueur de charge.gd est absent, AUCUNE sortie n'est active : le
# cablage les efface toutes les trois (miroir exact du marqueur reversible --
# aucune des trois ne porte de 'duree', etat_duree.gd ne les retirerait donc
# JAMAIS tout seul). Marqueur present : Bifurcation.resoudre tranche et
# EtatDuree.poser (idempotent) pose la gagnante ; les deux perdantes sont
# effacees au meme instant. UNE SEULE sortie active a la fois est une garantie
# du CABLAGE, jamais du catalogue.
static func relayer_bifurcation(animal: Dictionary, contributions: Dictionary, config: Dictionary, etats: Dictionary) -> String:
	var sorties: Array = config.get("sorties_agression", [])
	var retenue := SORTIE_AUCUNE
	if agression_franchie(animal, config):
		retenue = String(Bifurcation.resoudre(charge_agression(animal, config), contributions, sorties).sortie)
	var actifs: Array = animal.proprietes.get("etats_actifs", [])
	for sortie in sorties:
		var nom := String(sortie)
		if nom == retenue:
			EtatDuree.poser(animal, nom, etats)
		else:
			actifs.erase(nom)
	return retenue

# ---- Pas 11 : la deformation ----

# DEUX CONTRAINTES QUE deformation.gd IMPOSE, aucune contournable en donnee, et
# toutes deux payees ici :
# (1) poser() n'a AUCUN parametre de temps -- une magnitude fixe par image
#     ferait monter le biais a une vitesse dependant de la machine. La
#     magnitude posee est donc un DEBIT PAR SECONDE multiplie par delta.
# (2) IL N'EXISTE AUCUN EQUILIBRE NATUREL : avancer() decroit par SOUSTRACTION
#     FIXE (max(0, registre - taux*delta)), jamais par une fraction du registre
#     courant -- tant que le debit de pose depasse le taux, le registre monte
#     LINEAIREMENT ET SANS BORNE. LE PLAFOND EST DONC AU CABLAGE. Resultat
#     negatif deja paye trois fois (data/deformations.json:faim_critique, peur,
#     data/epigenetique.json:accoutumance_froid) : ne pas le repayer.
# avancer() est appele DANS TOUS LES CAS, y compris sans sortie active et y
# compris au plafond : c'est lui, et lui seul, qui fait redescendre le biais.
static func avancer_deformation(
	animal: Dictionary,
	sortie: String,
	config: Dictionary,
	catalogue_deformations: Dictionary,
	delta: float,
) -> void:
	if not animal.proprietes.has("deformation_etat"):
		return
	if sortie != SORTIE_AUCUNE:
		var source := String(config.get("deformation_par_sortie", {}).get(sortie, ""))
		var cible := String(config.get("cible_par_sortie", {}).get(sortie, ""))
		if source != "" and cible != "" \
				and Deformation.biais(animal, source, cible, catalogue_deformations) < float(config.plafond_biais_agression):
			Deformation.poser(animal, source, cible, float(config.magnitude_deformation_par_s) * delta)
	Deformation.avancer(animal, delta, catalogue_deformations)

# LA VIGILANCE DE LA PROIE -- posee INCONDITIONNELLEMENT, jamais sous condition
# d'etat : ce n'est pas une emotion, c'est un TRAIT PERMANENT (une proie regarde
# toujours ce qui la mange plus qu'elle ne regarde ses congeneres).
#
# POURQUOI ELLE EXISTE, et c'est un RESULTAT NEGATIF MESURE et non un choix de
# style : proximite.gd lit 'saillance_intrinseque' DANS le catalogue, jamais sur
# l'objet, et n'appelle jamais etat_effectif.gd (audit, constat A) -- une chose
# n'a donc QU'UNE saillance, la meme pour tous ceux qui la regardent. Ce banc a
# besoin des DEUX sens a la fois, et un profil unique ne peut pas les rendre
# tous les deux. La DEFORMATION, elle, est PAR PERCEVANT : c'est la seule voie
# du depot qui laisse deux especes lire le meme monde differemment. La premiere
# calibration l'ignorait et produisait ZERO repas sur 60 s de config reelle,
# tous les cas de mecanique isoles restant verts -- voir
# data/profils_saillance.json:predateur_predation.
#
# Memes deux contraintes que avancer_deformation ci-dessus : debit PAR SECONDE
# multiplie par delta, plafond AU CABLAGE. avancer() est appele la, pas ici :
# une proie n'a qu'une source, la faire decroitre deux fois par tick doublerait
# son taux en silence.
static func poser_vigilance(
	animal: Dictionary,
	config: Dictionary,
	catalogue_deformations: Dictionary,
	delta: float,
) -> void:
	var regle: Dictionary = config.get("deformation_vigilance", {})
	var source := String(regle.get("source", ""))
	var cible := String(regle.get("cible", ""))
	if source == "" or cible == "" or not animal.proprietes.get("deformation_sources", []).has(source):
		return
	if Deformation.biais(animal, source, cible, catalogue_deformations) < float(config.plafond_biais_vigilance):
		Deformation.poser(animal, source, cible, float(config.magnitude_deformation_par_s) * delta)

static func biais_de_sortie(animal: Dictionary, sortie: String, config: Dictionary, catalogue_deformations: Dictionary) -> float:
	if sortie == SORTIE_AUCUNE:
		return 0.0
	var source := String(config.get("deformation_par_sortie", {}).get(sortie, ""))
	var cible := String(config.get("cible_par_sortie", {}).get(sortie, ""))
	if source == "" or cible == "":
		return 0.0
	return Deformation.biais(animal, source, cible, catalogue_deformations)

# ---- Pas 12/13 : decider et se deplacer ----

# TROIS COUCHES seulement -- proximite -> dominance -> agir. La perception a
# deja eu lieu au pas 4 et ses resultats sont PASSES EN PARAMETRE : une seule
# requete spatiale par animal et par tick, jamais deux (voir LIMITES en tete,
# le cout des requetes). Ni attaches.gd (ces animaux ne tiennent a rien --
# attaches: []), ni jugement.gd (aucun declencheur juge ici).
static func decider(
	animal: Dictionary,
	perceptions: Array,
	monde,
	profils_saillance: Dictionary,
	catalogue_deformations: Dictionary,
	catalogue_actions: Dictionary,
) -> Dictionary:
	var resultats := Proximite.evaluer(perceptions, animal, profils_saillance, catalogue_deformations)
	var visibles := Dominance.visibles(resultats, animal)
	var decision = Agir.choisir(visibles, animal, catalogue_actions, monde)
	animal.action_en_cours = Agir.etat_courant(decision)
	return {"decision": decision, "resultats": resultats, "visibles": visibles}

# LE GATE DE MOUVEMENT (decision (a) de ce banc, voir en-tete). Le mouvement
# n'est applique QUE si la propriete portee par la CIBLE figure dans la liste
# 'poursuit' (verbe oriente declencheur) ou 'fuit' (verbe oriente fuite) de
# l'espece. Toute autre decision laisse l'animal IMMOBILE -- sans ce gate, une
# proie resoudrait 's_eloigner' sur une congenere ('proie' et 'hostile'
# proposent les MEMES deux verbes, et un animal n'a QU'UN poids_verbes) et le
# troupeau se disperserait jusqu'aux bords sans jamais s'accoupler.
#
# MUTE animal.position EN PLACE, bornee a la zone. Rend le detail du geste,
# jamais recalcule ailleurs.
static func agir_et_deplacer(
	animal: Dictionary,
	perceptions: Array,
	monde,
	profils_saillance: Dictionary,
	catalogue_deformations: Dictionary,
	catalogue_actions: Dictionary,
	orientations: Dictionary,
	etats: Dictionary,
	config: Dictionary,
	delta: float,
) -> Dictionary:
	var r := decider(animal, perceptions, monde, profils_saillance, catalogue_deformations, catalogue_actions)
	var decision = r.decision
	var position_avant: Vector3 = animal.position
	var geste := ""
	var cible_id := ""
	if decision != null and decision.has("chose"):
		cible_id = String(decision.chose.get("id", ""))
		var comportement: Dictionary = config.get("comportements", {}).get(espece_de(animal), {})
		var action := String(decision.get("action", ""))
		var orientation := String(orientations.get(action, "declencheur"))
		var vitesse: float = EtatEffectif.valeur(animal, String(config.nom_vitesse), etats)
		if orientation == "fuite" and _cible_porte_une_de(decision.chose, comportement.get("fuit", [])):
			geste = "fuit"
			var direction := Fuite.direction(
				animal.position,
				BancCommun.choses_a_fuir(r.visibles, animal, catalogue_actions, orientations, monde))
			animal.position = BancCommun.bouger_selon(animal.position, direction, vitesse, delta)
		elif orientation != "fuite" and _cible_porte_une_de(decision.chose, comportement.get("poursuit", [])):
			geste = "poursuit"
			animal.position = BancCommun.bouger_vers(animal.position, decision.position, vitesse, delta)
	animal.position = _borner(animal.position, config)
	return {
		"decision": decision,
		"visibles": r.visibles,
		"geste": geste,
		"cible_id": cible_id,
		"a_bouge": animal.position != position_avant,
	}

static func _cible_porte_une_de(chose: Dictionary, proprietes: Array) -> bool:
	for propriete in proprietes:
		if chose.proprietes.get(String(propriete), false):
			return true
	return false

static func _borner(position: Vector3, config: Dictionary) -> Vector3:
	var zone: Dictionary = config.get("zone", {})
	if zone.is_empty():
		return position
	var mini: Array = zone["min"]
	var maxi: Array = zone["max"]
	return Vector3(
		clamp(position.x, float(mini[0]), float(maxi[0])),
		clamp(position.y, float(mini[1]), float(maxi[1])),
		position.z)

# ---- Pas 14/15/16 : le cycle de reproduction ----

# LE GATE DE CABLAGE (audit ligne 5) : accouplement.gd ne lit AUCUNE reserve --
# seulement mode_reproduction, espece_reproduction, stades_fertiles, stade et
# les perceptions (voir son en-tete). « La proie se reproduit quand ses
# reserves sont hautes » ne peut donc etre qu'un refus d'appeler.
#
# DEUXIEME CONDITION DU MEME GATE, ajoutee APRES avoir lance la scene et non
# raisonnee a l'avance : un PLAFOND DE POPULATION PAR ESPECE. Sans lui, une
# fois les predateurs eteints, les proies croissent EXPONENTIELLEMENT (mesure :
# 8 -> 32 en une trentaine de secondes, et le nombre de ticks par seconde
# s'effondre avec le carre de la population) -- le banc cesse d'etre
# observable, ce qui est un defaut reel du CABLAGE, pas du monde qu'il montre.
#
# CE N'EST PAS UNE CAPACITE DE CHARGE, et il ne faut pas le lire comme telle :
# la vraie est la LIGNE 3 de l'audit (un milieu nourrit un nombre fini), elle
# est SPATIALE (par case de biome, seuil_propriete 'capacite_charge', etat
# 'surpeuplement' pose par seuil_etat.gd sur un comptage local) et elle vit
# dans un autre chantier -- scripts/banc_ecosysteme_terrain.gd, session
# concurrente. Ici c'est un plafond GLOBAL et brut, une borne d'observabilite
# assumee, de la meme famille que restes_max : il empeche le banc de se noyer,
# il ne modelise rien.
static func reproduction_autorisee(animal: Dictionary, config: Dictionary, comptes: Dictionary = {}) -> bool:
	var espece := espece_de(animal)
	var seuil: float = float(config.get("seuil_reproduction", {}).get(espece, INF))
	if energie(animal, config) < seuil:
		return false
	var plafond: float = float(config.get("population_max", {}).get(espece, INF))
	return float(comptes.get(espece, 0)) < plafond

# DECISION (b) de ce banc, voir en-tete : deux especes sans sexes declarent
# role_gestation "les_deux", donc accouplement.gd pose 'gestation' des deux
# cotes. Convention deterministe et symetrique de CE fichier -- porte celui
# dont l'id est le plus PETIT alphabetiquement ; l'autre est libere AU MEME
# TICK, sans quoi il resterait
# definitivement indisponible pour tout accouplement futur (garde de
# accouplement.gd : un partenaire percu qui porte deja 'gestation' est ignore).
static func est_porteur(animal: Dictionary) -> bool:
	var gestation: Dictionary = animal.proprietes.get("gestation", {})
	if gestation.is_empty():
		return false
	return String(animal.id) <= String(gestation.get("partenaire_id", ""))

static func liberer_non_porteurs(animaux: Array) -> Array:
	var liberes: Array = []
	for animal in animaux:
		if animal.proprietes.has("gestation") and not est_porteur(animal):
			animal.proprietes.erase("gestation")
			liberes.append(String(animal.id))
	return liberes

# DECISION (c) de ce banc : accouplement.gd ne vide JAMAIS son accumulateur
# (son accumulation est IRREVERSIBLE par construction). Sans ce geste, une
# gestation retiree serait REPOSEE AU TICK SUIVANT, l'exposition passee restant
# creditee pour toujours, et le gate de reproduction ne retiendrait plus rien.
static func vider_accumulateur(animal: Dictionary) -> void:
	if animal.proprietes.has("accouplement_accumulateur"):
		animal.proprietes["accouplement_accumulateur"] = {}

# LA NAISSANCE. heredite.gd produit le KIT genetique (fonction PURE, rng recu
# en parametre) ; Objet.fabriquer construit la coquille depuis le type local
# resolu par l'ESPECE de la porteuse (config.type_par_espece -- aucun nom de
# type dans ce code) ; le cablage ecrase genes_etat/marques_epigenetiques par
# le kit, PUIS retire 'gestation' de la porteuse -- gestation.gd et heredite.gd
# ne le font jamais eux-memes, c'est ecrit dans leurs deux en-tetes.
static func fabriquer_enfant(
	id: String,
	porteuse: Dictionary,
	config: Dictionary,
	catalogue_types: Dictionary,
	catalogue_heredite: Dictionary,
	rng: RandomNumberGenerator,
) -> Dictionary:
	var kit := Heredite.fabriquer_genes_enfant(porteuse, catalogue_heredite, {}, rng)
	var offset: Array = config.get("offset_naissance", [0.0, 0.0, 0.0])
	var position: Vector3 = _borner(
		porteuse.position + Vector3(offset[0], offset[1], offset[2]), config)
	var nom_type := String(config.get("type_par_espece", {}).get(espece_de(porteuse), ""))
	var enfant := fabriquer_animal(
		id, nom_type, position, porteuse.proprietes.get("biais_agression", {}),
		config, catalogue_types, {})
	if enfant.is_empty():
		return {}
	# age 0.0 EXPLICITE : fabriquer_animal pose age_depart (les fondateurs
	# naissent adultes pour que le banc demarre) -- un enfant, lui, doit
	# traverser ses stades juveniles, et c'est ce delai qui dephase le cycle.
	enfant.proprietes["age"] = 0.0
	enfant.proprietes["stade"] = ""
	# ET SON STADE EST RESOLU TOUT DE SUITE, jamais laisse a "" jusqu'au tick
	# suivant. DEFAUT REEL TROUVE AU PREMIER LANCEMENT DU TEST : une chaine vide
	# ne matche AUCUN stades_juveniles, donc pendant un tick entier un
	# nouveau-ne n'etait ni juvenile (invisible a la cause « petits », qui
	# existe pour lui) ni colore en jaune a l'ecran. stade.gd est PUR et
	# idempotent, l'appeler ici ne coute rien et ne double aucun calcul.
	Stade.avancer(enfant)
	enfant.proprietes["genes_actifs"] = porteuse.proprietes.get("genes_actifs", []).duplicate()
	enfant.proprietes["genes_etat"] = kit.genes_etat
	enfant.proprietes["marques_epigenetiques"] = kit.marques_epigenetiques
	ExpressionGenetique.appliquer(
		enfant, ExpressionGenetique.exprimer(enfant, config.get("catalogue_genes", {}), {}, {}))
	return enfant

# ---- Pas 8 : le reste ----

# produit.gd:transformer, patron banc_fertilite.gd:avancer_transformations
# (cadavre -> humus). Rend { id, position, proprietes } ou {} si la
# transformation echoue -- produit.gd rend un Dictionary de PROPRIETES seul,
# id et position restent la responsabilite de l'appelant, il ne les connait pas.
static func fabriquer_reste(
	id: String,
	mort: Dictionary,
	config: Dictionary,
	catalogue_types: Dictionary,
	materiaux: Dictionary,
) -> Dictionary:
	var proprietes := Produit.transformer(
		mort.proprietes, config.get("produit_reste", {}), catalogue_types, materiaux)
	if proprietes.is_empty():
		return {}
	return {"id": id, "position": mort.position, "proprietes": proprietes}

# ---- LE TICK COMPLET ----

# ORDRE FIXE ET ASSUME -- voir l'en-tete du fichier pour les dix-sept pas et
# les trois inversions qui seraient fausses. MUTE `etat` en place, y compris
# etat.monde (REMPLACE au pas 17). Rend le rapport que le rendu et les traces
# relisent, jamais recalcule ailleurs.
static func avancer(
	etat: Dictionary,
	config: Dictionary,
	etats: Dictionary,
	catalogue_canaux: Dictionary,
	catalogue_deformations: Dictionary,
	profils_saillance: Dictionary,
	catalogue_actions: Dictionary,
	orientations: Dictionary,
	catalogue_reproduction: Dictionary,
	catalogue_heredite: Dictionary,
	catalogue_types: Dictionary,
	materiaux: Dictionary,
	delta: float,
) -> Dictionary:
	etat["temps"] = float(etat.temps) + delta
	etat["tick"] = int(etat.tick) + 1
	var animaux: Array = etat.animaux
	var monde = etat.monde
	var annees_par_seconde: float = float(config.annees_par_seconde)

	# 1/2. l'age monte, le stade suit.
	for animal in animaux:
		Senescence.avancer(animal, delta, annees_par_seconde)
		Stade.avancer(animal)

	# 3. l'energie descend (predateur) ou remonte (proie, cout_base NEGATIF).
	Depense.avancer(animaux, delta)

	# 4. qui voit quoi -- UNE SEULE requete spatiale par animal et par tick.
	var perceptions: Dictionary = {}
	for animal in vivants(animaux, config):
		perceptions[animal.id] = Perception.percevoir(animal, monde, catalogue_canaux)

	# 5. combien de proies, combien de predateurs (un CALCUL, jamais un objet).
	var comptes := effectifs(animaux, config)

	# 6/7. la hierarchie trie, le dominant mange (consommer.gd, conservatif).
	var repas := repas_du_tick(animaux, config)
	for r in repas:
		Consommer.transferer(
			r.proie, r.mangeur, String(config.nom_reserve_energie),
			String(config.nom_reserve_energie), float(config.taux_predation), delta)

	# 7b. le plafond, le miroir plat, puis la mort -- dans cet ordre, chacun un
	# seul ecrivain.
	for animal in animaux:
		plafonner_energie(animal, config)
		poser_manque_energie(animal, config)
	var etaient_morts: Dictionary = {}
	for animal in animaux:
		etaient_morts[animal.id] = est_mort(animal, config)
	SeuilEtat.avancer(animaux, config.get("seuils_locaux", {}))

	# 8. un mort devient un reste (patron cadavre).
	var morts: Array = []
	for animal in animaux:
		if est_mort(animal, config) and not etaient_morts[animal.id]:
			morts.append(String(animal.id))
			var reste := fabriquer_reste(
				"reste_%s" % String(animal.id), animal, config, catalogue_types, materiaux)
			if not reste.is_empty():
				etat.restes.append(reste)
	while etat.restes.size() > int(config.restes_max):
		etat.restes.pop_front()

	# 9 a 16 -- gates par est_mort : un cadavre ne decide pas, ne bouge pas,
	# ne s'accouple pas (voir LIMITES en tete).
	var rapports: Array = []
	var naissances: Array = []
	for animal in vivants(animaux, config):
		# 9. l'agression monte sous trois causes synthetisees.
		var contributions: Dictionary = {}
		if animal.proprietes.get("etats", {}).has(String(config.nom_canal_agression)):
			contributions = contributions_agression(animal, animaux, config)
			Charge.avancer([animal], causes_agression(animal, contributions), delta)
		# 10. laquelle des trois domine.
		var sortie := relayer_bifurcation(animal, contributions, config, etats) \
			if not contributions.is_empty() else SORTIE_AUCUNE
		# 11. la cible de la sortie gagnante monte en saillance -- et, cote
		# proie, la vigilance permanente monte celle du predateur (poser AVANT
		# avancer_deformation, qui porte l'unique appel a Deformation.avancer :
		# deux appels par tick doubleraient le taux de decroissance en silence).
		poser_vigilance(animal, config, catalogue_deformations, delta)
		avancer_deformation(animal, sortie, config, catalogue_deformations, delta)
		# 12/13. decider, se deplacer, puis le surcout (UN SEUL ecrivain).
		poser_poids_verbes(animal, config)
		var geste := agir_et_deplacer(
			animal, perceptions.get(animal.id, []), monde, profils_saillance,
			catalogue_deformations, catalogue_actions, orientations, etats, config, delta)
		var surcout := poser_surcout_action(animal, geste.a_bouge, sortie != SORTIE_AUCUNE, config)
		rapports.append({
			"id": String(animal.id),
			"espece": espece_de(animal),
			"predateur": est_predateur(animal, config),
			"juvenile": est_juvenile(animal),
			"stade": String(animal.proprietes.get("stade", "")),
			"age": float(animal.proprietes.get("age", 0.0)),
			"energie": energie(animal, config),
			"charge": charge_agression(animal, config),
			"sortie": sortie,
			"biais_deformation": biais_de_sortie(animal, sortie, config, catalogue_deformations),
			"score": score_hierarchie(animal, config),
			"masse": float(animal.proprietes.get(String(config.nom_masse), 0.0)),
			"force": float(animal.proprietes.get(String(config.nom_force), 0.0)),
			"surcout": surcout.total,
			"geste": String(geste.geste),
			"cible_id": String(geste.cible_id),
			"gestation": animal.proprietes.has("gestation"),
			"position": animal.position,
		})

	# 14. l'accouplement, sous gate de cablage ; puis on libere le non-porteur.
	# Les effectifs PAR ESPECE sont comptes UNE FOIS pour tout le pas -- jamais
	# par animal : ils ne changent pas pendant la boucle (aucune naissance
	# n'a lieu avant le pas 16), et un comptage par animal serait O(n^2) pour
	# rien.
	var effectifs_par_espece: Dictionary = {}
	for animal in vivants(animaux, config):
		var espece := espece_de(animal)
		effectifs_par_espece[espece] = int(effectifs_par_espece.get(espece, 0)) + 1
	for animal in vivants(animaux, config):
		if reproduction_autorisee(animal, config, effectifs_par_espece):
			Accouplement.avancer(
				animal, perceptions.get(animal.id, []), catalogue_reproduction, delta, int(etat.tick))
	liberer_non_porteurs(vivants(animaux, config))

	# 15. le compteur, sur LE PORTEUR SEUL.
	for animal in vivants(animaux, config):
		if animal.proprietes.has("gestation"):
			Gestation.avancer(animal, catalogue_reproduction, delta)

	# 16. le kit genetique puis Objet.fabriquer : la naissance.
	for animal in vivants(animaux, config):
		var gestation: Dictionary = animal.proprietes.get("gestation", {})
		if gestation.is_empty() or not gestation.get("naissance_prete", false):
			continue
		etat["compteur_enfant"] = int(etat.compteur_enfant) + 1
		var enfant := fabriquer_enfant(
			"ne_%d" % int(etat.compteur_enfant), animal, config, catalogue_types,
			catalogue_heredite, etat.rng)
		var partenaire := _animal_par_id(animaux, String(gestation.get("partenaire_id", "")))
		animal.proprietes.erase("gestation")
		vider_accumulateur(animal)
		if not partenaire.is_empty():
			vider_accumulateur(partenaire)
		var cout: float = float(config.get("cout_reproduction", {}).get(espece_de(animal), 0.0))
		var canal: Dictionary = animal.proprietes.get("reserves", {}).get(String(config.nom_reserve_energie), {})
		if not canal.is_empty():
			canal["reserve"] = max(0.0, float(canal.get("reserve", 0.0)) - cout)
		if enfant.is_empty():
			continue
		animaux.append(enfant)
		naissances.append({"id": String(enfant.id), "parent_id": String(animal.id), "espece": espece_de(enfant)})
		etat["naissances"] = int(etat.naissances) + 1

	# 17. les morts quittent le Monde, RECONSTRUIT DU NEANT.
	etat["morts"] = int(etat.morts) + morts.size()
	if not morts.is_empty() or not naissances.is_empty():
		var survivants := vivants(animaux, config)
		etat["animaux"] = survivants
		etat["monde"] = monde_reconstruit(survivants)

	return {
		"proies": comptes.proies,
		"predateurs": comptes.predateurs,
		"repas": repas,
		"morts": morts,
		"naissances": naissances,
		"animaux": rapports,
		"total_naissances": int(etat.naissances),
		"total_morts": int(etat.morts),
		"tick": int(etat.tick),
		"restes": etat.restes.size(),
	}

static func _animal_par_id(animaux: Array, id: String) -> Dictionary:
	for animal in animaux:
		if String(animal.id) == id:
			return animal
	return {}

# ---- Toggle du temps ----

static func palier_suivant(palier: int, config: Dictionary) -> int:
	var paliers: Array = config.get("paliers_facteur_temps", [])
	if paliers.is_empty():
		return 0
	return (palier + 1) % paliers.size()

static func facteur_du_palier(config: Dictionary, palier: int) -> float:
	var paliers: Array = config.get("paliers_facteur_temps", [])
	if paliers.is_empty():
		return 1.0
	return float(paliers[palier % paliers.size()])

# ---- Textes (purs -- aucun nombre n'y est recalcule) ----

static func _ligne_ouverture(config: Dictionary, etat: Dictionary) -> String:
	var comptes := effectifs(etat.animaux, config)
	return "t=0.0s POSE : %d proies, %d predateurs -- clic gauche : facteur de temps suivant" % [
		comptes.proies, comptes.predateurs]

static func _ligne_palier(t: float, facteur: float) -> String:
	return "t=%.1fs TEMPS x%.1f" % [t, facteur]

# UNE LIGNE PAR TRANSITION, jamais une par tick. DEFAUT REEL TROUVE EN LANCANT
# LA SCENE, invisible au test (qui ne lit pas la console) : un repas dure
# plusieurs secondes et une sortie d'agression reste active tant que sa cause
# dure -- tracer l'ETAT a chaque image noyait les naissances et les morts sous
# des centaines de lignes identiques. `precedents` (Dictionary { repas, sorties }
# tenu par l'appelant) porte la memoire de ce qui a deja ete dit ; il est MUTE
# ici. Meme discipline exacte que banc_menace_combat.gd:_sorties_precedentes et
# que tous les autres bancs (« imprime UNE FOIS par changement, jamais par
# tick »).
static func lignes_evenements(t: float, rapport: Dictionary, precedents: Dictionary) -> Array:
	var lignes: Array = []
	var repas_en_cours: Dictionary = {}
	for r in rapport.repas:
		repas_en_cours[String(r.mangeur_id)] = String(r.proie_id)
		if String(precedents.get("repas", {}).get(String(r.mangeur_id), "")) == String(r.proie_id):
			continue
		var suffixe := ""
		if not r.attendants.is_empty():
			suffixe = " (attendent : %s)" % ", ".join(r.attendants)
		lignes.append("t=%.1fs REPAS : %s mange %s (score %.2f)%s" % [
			t, r.mangeur_id, r.proie_id, r.score_mangeur, suffixe])
	precedents["repas"] = repas_en_cours

	for id in rapport.morts:
		lignes.append("t=%.1fs MORT : %s" % [t, id])
	for n in rapport.naissances:
		lignes.append("t=%.1fs NAISSANCE : %s (%s), parent %s" % [t, n.id, n.espece, n.parent_id])

	var sorties: Dictionary = precedents.get("sorties", {})
	for a in rapport.animaux:
		var id := String(a.id)
		if String(sorties.get(id, SORTIE_AUCUNE)) == String(a.sortie):
			continue
		sorties[id] = String(a.sortie)
		if String(a.sortie) == SORTIE_AUCUNE:
			lignes.append("t=%.1fs AGRESSION : %s retombe (charge %.2f)" % [t, id, a.charge])
		else:
			lignes.append("t=%.1fs AGRESSION : %s -> %s (charge %.2f, biais %.2f)" % [
				t, id, a.sortie, a.charge, a.biais_deformation])
	precedents["sorties"] = sorties
	return lignes

static func ligne_population(t: float, rapport: Dictionary, facteur: float) -> String:
	return "t=%.1fs (x%.1f) | proies %d | predateurs %d | naissances %d | morts %d | restes %d | tick %d" % [
		t, facteur, rapport.proies, rapport.predateurs, rapport.total_naissances,
		rapport.total_morts, rapport.restes, rapport.tick]

static func texte_animal(a: Dictionary) -> String:
	return "%s\nenergie %.0f\n%s\n%s\nscore %.2f" % [
		a.id, a.energie, a.stade,
		String(a.sortie) if String(a.sortie) != SORTIE_AUCUNE else "calme",
		a.score]

static func texte_compteur(rapport: Dictionary, facteur: float) -> String:
	return "proies %d | predateurs %d | naissances %d | morts %d | tick %d | temps x%.1f  (clic gauche : accelerer)" % [
		rapport.proies, rapport.predateurs, rapport.total_naissances,
		rapport.total_morts, rapport.tick, facteur]

# Taille proportionnelle a la masse, bornee -- un nouveau-ne est visiblement
# plus petit qu'un adulte sans jamais disparaitre ni deborder.
static func taille_pour_masse(masse: float, config: Dictionary) -> float:
	var reference: float = float(config.masse_reference_taille)
	if reference <= 0.0:
		return float(config.taille_base)
	return clamp(float(config.taille_base) * masse / reference,
		float(config.taille_min), float(config.taille_max))

# ---- Rendu (impur, Node) -- aucune decision, seulement couleurs, tailles
# et positions.

func _couleur(cle: String) -> Color:
	var rgb: Array = _config.get("couleurs", {}).get(cle, [1.0, 1.0, 1.0])
	return Color(rgb[0], rgb[1], rgb[2])

func _couleur_animal(a: Dictionary) -> Color:
	if a.juvenile:
		return _couleur("juvenile")
	return _couleur("predateur") if a.predateur else _couleur("proie")

func _creer_rendu_fixe() -> void:
	_label_compteur = Label.new()
	_label_compteur.add_theme_font_size_override("font_size", int(_config.taille_police_compteur))
	_label_compteur.position = Vector2(10.0, 10.0)
	_couche_ui.add_child(_label_compteur)

	var origine: Array = _config.origine_courbe
	var largeur: float = float(_config.largeur_barre_population)
	var hauteur: float = float(_config.hauteur_barre_population_max)
	var base := Vector2(float(origine[0]), float(origine[1]))
	_fond_proies = _creer_barre(_couleur("fond_barre"), base - Vector2(0.0, hauteur), largeur, hauteur)
	_barre_proies = _creer_barre(_couleur("proie"), base, largeur, 0.0)
	_fond_predateurs = _creer_barre(_couleur("fond_barre"),
		base + Vector2(largeur + 10.0, -hauteur), largeur, hauteur)
	_barre_predateurs = _creer_barre(_couleur("predateur"), base + Vector2(largeur + 10.0, 0.0), largeur, 0.0)
	_label_courbe = Label.new()
	_label_courbe.add_theme_font_size_override("font_size", int(_config.taille_police_label))
	_label_courbe.position = base + Vector2(0.0, 6.0)
	add_child(_label_courbe)

func _creer_barre(couleur: Color, origine: Vector2, largeur: float, hauteur: float) -> ColorRect:
	var barre := ColorRect.new()
	barre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	barre.color = couleur
	barre.position = origine
	barre.size = Vector2(largeur, hauteur)
	add_child(barre)
	return barre

# Les noeuds NAISSENT et MEURENT avec les animaux -- un banc a casting fixe
# n'avait jamais eu a le faire.
func _rafraichir_tout() -> void:
	if _dernier_rapport.is_empty():
		return
	var vus: Dictionary = {}
	for a in _dernier_rapport.animaux:
		var id := String(a.id)
		vus[id] = true
		if not _noeuds.has(id):
			var carre := ColorRect.new()
			carre.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(carre)
			_noeuds[id] = carre
			var label := Label.new()
			label.add_theme_font_size_override("font_size", int(_config.taille_police_label))
			add_child(label)
			_labels[id] = label
		var taille: float = taille_pour_masse(float(a.masse), _config)
		var noeud: ColorRect = _noeuds[id]
		noeud.size = Vector2(taille, taille)
		noeud.color = _couleur_animal(a)
		noeud.position = Vector2(a.position.x, a.position.y) - noeud.size / 2.0
		_labels[id].position = noeud.position + Vector2(taille + 4.0, -6.0)
		_labels[id].text = texte_animal(a)
	for id in _noeuds.keys():
		if not vus.has(id):
			_noeuds[id].queue_free()
			_noeuds.erase(id)
			_labels[id].queue_free()
			_labels.erase(id)

	for reste in _etat.restes:
		var id_reste := String(reste.id)
		if _noeuds_restes.has(id_reste):
			continue
		var taille_reste: float = float(_config.taille_reste)
		var carre_reste := ColorRect.new()
		carre_reste.mouse_filter = Control.MOUSE_FILTER_IGNORE
		carre_reste.size = Vector2(taille_reste, taille_reste)
		carre_reste.color = _couleur("reste")
		carre_reste.position = Vector2(reste.position.x, reste.position.y) - carre_reste.size / 2.0
		add_child(carre_reste)
		_noeuds_restes[id_reste] = carre_reste
	var restes_vivants: Dictionary = {}
	for reste in _etat.restes:
		restes_vivants[String(reste.id)] = true
	for id in _noeuds_restes.keys():
		if not restes_vivants.has(id):
			_noeuds_restes[id].queue_free()
			_noeuds_restes.erase(id)

	var maxi: float = float(_config.population_affichee_max)
	var hauteur: float = float(_config.hauteur_barre_population_max)
	var largeur: float = float(_config.largeur_barre_population)
	var h_proies: float = hauteur * clamp(float(_dernier_rapport.proies) / maxi, 0.0, 1.0)
	var h_pred: float = hauteur * clamp(float(_dernier_rapport.predateurs) / maxi, 0.0, 1.0)
	_barre_proies.size = Vector2(largeur, h_proies)
	_barre_proies.position = _fond_proies.position + Vector2(0.0, hauteur - h_proies)
	_barre_predateurs.size = Vector2(largeur, h_pred)
	_barre_predateurs.position = _fond_predateurs.position + Vector2(0.0, hauteur - h_pred)
	_label_courbe.text = "proies %d / predateurs %d" % [_dernier_rapport.proies, _dernier_rapport.predateurs]

	_label_compteur.text = texte_compteur(_dernier_rapport, facteur_du_palier(_config, _palier_temps))

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
