extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_social_paire.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1). Chantier « relation par paire »
# (audit_social_relations_prealable.md, lignes 1, 2, 3, 11 et 14 -- quatre
# CABLABLES et une PARTIELLEMENT COUVERTE, la 2). Compose SIX mecanismes deja
# fermes, TOUS INCHANGES : lien_personnel.gd (le registre positif par paire),
# epigenetique.gd (les trois autres registres par paire), seuil_etat.gd (les
# trois etats poses et retires), bifurcation.gd (ceder ou resister),
# charge.gd (le grief de transgression), plus dominance.gd + agir.gd pour
# l'arbitrage reel. AUCUN MECANISME DU COEUR TOUCHE, AUCUN .gd neuf du coeur.
#
# ---- CE QU'ON DOIT VOIR ----
#
# Quatre colons : un chef, un soldat loyal, un ami proche, un ennemi. Au
# depart personne ne se bat et personne n'obeit -- la confiance est a zero.
# Elle monte par TEMPS PARTAGE, et les trois qui se frequentent franchissent
# le premier palier : ils acceptent de se battre aux cotes du chef. Le soldat
# seul franchit le second et accepte ses ordres ; l'ami plafonne entre les
# deux et n'obeira jamais. L'ennemi, que personne ne frequente, ne franchit
# rien -- et comme le chef lui rend service sans rien recevoir, sa dette
# s'alourdit jusqu'a le rendre RANCUNIER.
#
# Clic gauche : le chef ordonne de tuer l'ami. Le soldat CEDE (il aime son
# chef, et son chef est fort), l'ami et l'ennemi RESISTENT. Mais le soldat
# refuse quand meme : son lien vers l'ami depasse le seuil d'attache, et
# l'entree de l'ordre est RETIREE de resultats avant dominance.gd -- il
# retourne a son ouvrage. Second clic : l'ordre est FORCE, l'entree survit au
# gate du lien, il tue -- et son grief de transgression monte jusqu'a le
# marquer TRANSGRESSEUR.
#
# Clic droit : les interactions passent de SERVICE a AGRESSION. L'ennemi
# frappe le soldat et l'ami, leur lien_negatif monte, les lignes entre eux
# virent au rouge. Le service du chef cesse : la dette de l'ennemi remonte
# vers zero et sa rancune se retire d'elle-meme.
#
# ---- CE QUE CE BANC ETABLIT, ET QUI N'EXISTAIT PAS ----
#
# (1) LE PREMIER REGISTRE PAR PAIRE QUI NE SOIT PAS UN LIEN PERSONNEL.
# lien_personnel.gd est, l'audit le mesure, LE SEUL registre par paire du
# depot (proprietes.liens_personnels[chose_id] = float). Il est POSITIF
# SEULEMENT : avancer() ecrit max(0.0, force - taux * delta), toute valeur
# negative est ramenee a 0.0 au premier tick puis retiree sous le plancher.
# Une haine, une rancune, une dette negative n'y survivent pas -- mesure sur
# le code, pas deduit. Le rendre signe toucherait CINQ fichiers du coeur
# (lien_personnel.gd plus ses quatre lecteurs), ce que ce chantier s'interdit.
#
# TROIS REGISTRES DE PLUS vivent donc ailleurs, et tous les trois sont des
# MARQUES EPIGENETIQUES A NOM COMPOSE -- 'confiance:<cible>',
# 'lien_negatif:<cible>', 'service_rendu:<cible>'. epigenetique.gd ne voit que
# des noms opaques, il ignore totalement qu'ils encodent une paire.
#
# ECART A L'AUDIT, ASSUME ET SIGNALE. audit_social_relations_prealable.md
# ligne 1 ecrit « la confiance est-elle une marque epigenetique ? Non, et il
# ne faut pas prendre cette route », et ligne 3 renvoie la decroissance de la
# dette vers lien_personnel.gd:avancer. Son motif, unique et explicite : « une
# confiance par paire exigerait une entree de data/epigenetique.json par paire
# de colons ». CE MOTIF NE TIENT PAS, et c'est verifiable : epigenetique.gd ne
# charge JAMAIS son catalogue, il le RECOIT en parametre (c'est ecrit dans son
# en-tete, meme convention que deformation.gd/couplage.gd/lien_personnel.gd).
# catalogue_paires() ci-dessous derive donc, d'UNE SEULE entree partagee, une
# entree par cible possible -- la loi (montee, decroissance, plancher) vit une
# fois en donnee, jamais N fois. Precedent du catalogue LOCAL au format exact
# du partage, ecrit quatre fois : data/banc_psycho_social.json:seuils_locaux,
# banc_menace_combat.gd:comptages, banc_predation.gd:comptages,
# banc_affordances_choix.gd (engagement).
#
# ET LA ROUTE DE L'AUDIT ETAIT FERMEE POUR UNE AUTRE RAISON, qu'il ne voit
# pas : mettre la confiance ET la dette dans liens_personnels les melangerait
# au lien positif dans LE MEME Dictionary. Trois grandeurs distinctes, un seul
# seau, aucun moyen de les relire separement -- et les quatre lecteurs
# existants (lien_personnel_saillance.gd, _attraction.gd, _croissance.gd,
# attache_par_trait.gd) iterent ses cles et les passent a monde.par_id(), qui
# fait push_error sur un id absent. Une cle composee y serait une alarme a
# chaque image pour le prochain banc qui les cablerait.
#
# (2) LA HAINE EST UN SECOND REGISTRE POSITIF, PAS UN SIGNE. score_net(A,B) =
# lien_positif - lien_negatif est une LECTURE du cablage, refaite a neuf a
# chaque appel, jamais une valeur stockee nulle part. Les QUATRE lecteurs de
# lien_personnel.gd continuent de ne voir que le positif, sans une ligne
# changee -- c'est exactement la route (a) de l'audit ligne 2, et son cout est
# dit plutot que masque : une haine ne rend rien saillant toute seule, il
# faudrait sa propre entree de saillance synthetique.
#
# (3) LA DETTE EST UNE DIFFERENCE LUE SUR DEUX ENTITES. Un seul registre,
# toujours positif, pose sur celui qui REND : dette(A,B) = service_rendu(A,B)
# - service_rendu(B,A). Constat (E) de l'audit : aucun mecanisme du coeur ne
# compare une propriete de A a une propriete de B -- cette soustraction est
# donc du cablage, et c'est sa place (precedents
# banc_menace_combat.gd:ratio_effectifs, banc_predation.gd:score_hierarchie).
#
# (4) DEUX GATES INDEPENDANTS SUR LE MEME ORDRE, ET ILS NE SE RECOUVRENT PAS.
# 'confiant_obeir' dit ce que le colon a ACCUMULE avec son chef (du temps, une
# confiance qui monte et redescend, seuil_etat.gd). La CESSION dit ce que le
# chef PESE ici et maintenant (score net vers lui + son score de hierarchie,
# contre le cout du conflit, tranche par bifurcation.gd). Un colon peut avoir
# assez confiance pour obeir en principe et resister quand meme parce que le
# conflit lui coute moins cher que la soumission. Les deux sont exiges par la
# consigne (lignes 1 et 14), ce sont deux mecanismes differents.
#
# ---- QUATRE CONTRAINTES DU COEUR QUI DECIDENT LA FORME DE CE FICHIER ----
#
# (a) seuil_etat.gd NE LIT QUE DES CLES PLATES et NE COMPARE QUE VERS LE HAUT.
# Les quatre registres par paire sont NICHES (sous liens_personnels ou sous
# marques_epigenetiques) -- constat (D) de l'audit, il touche huit des
# quatorze lignes. D'ou DEUX MIROIRS PLATS, 'confiance' et 'dette_negative',
# ecrits par poser_miroirs() et par lui SEUL (patron
# banc_bonheur.gd:poser_bonheur). Le second est en plus INVERSE : « la dette
# descend sous -1.0 » ne s'ecrit que « son oppose monte au-dessus de 1.0 ».
#
# (b) bifurcation.gd NE PEUT PAS ARBITRER PAR SA grandeur. C'est ecrit dans
# son propre en-tete et verrouille par test : la grandeur est UN SEUL SCALAIRE
# commun a toutes les sorties, tant qu'elle est positive elle multiplie tous
# les scores par le meme nombre et NE CHANGE JAMAIS QUI GAGNE. La comparaison
# « score_cession contre cout_conflit » vit donc entierement dans le BIAIS
# ({ ceder: score_cession, resister: cout_conflit }), et la grandeur sert de
# GATE : 1.0 s'il y a un ordre, 0.0 sinon -- aucune bifurcation ne se produit
# sans ordre, PAR LA SEULE ARITHMETIQUE, sans qu'aucun `if` ne l'interdise.
# C'est l'idiome que bifurcation.gd annonce lui-meme.
#
# (c) epigenetique.gd:poser NE PREND PAS DE MAGNITUDE. Il la LIT au catalogue
# (modulateur_pose) -- a la difference de lien_personnel.gd:poser et de
# deformation.gd:poser. Le 'gain_par_service' de la consigne EST donc
# modulateur_pose, en donnee ; l'appelant ne choisit pas. Et poser() n'a AUCUN
# parametre de temps : la pose passe par une CADENCE en secondes de
# simulation, jamais un appel par image (qui ferait dependre la montee de la
# machine).
#
# (d) LA CADENCE DE POSE EST BORNEE PAR LE HAUT, resultat negatif deja paye
# TROIS fois dans le depot (data/epigenetique.json : accoutumance_froid,
# experience_combat, competence_forge -- interdit de le repayer). L'intervalle
# doit rester sous (modulateur_pose - plancher_suppression) /
# taux_decroissance, sinon la marque est effacee entre deux poses et
# n'accumule JAMAIS rien. La plus courte des trois marques de ce banc vaut
# 1.00 s (confiance) ; l'intervalle est a 0.25 s, facteur 4 de marge,
# VERROUILLE PAR TEST contre les nombres reels du disque.
#
# ---- CE QUE CE BANC NE MONTRE PAS, dit plutot que masque ----
#
# Il ne monte NI perception.gd NI proximite.gd : ses trois entrees de
# saillance (la menace, l'ordre, l'ouvrage) sont CONSTRUITES par le cablage et
# passees directement au filtre puis a dominance.gd et agir.gd -- patron
# banc_grief.gd, meme decoupage exact. « A portee » est donc une comparaison
# de distance directe (patron banc_croyance.gd:portee_transmission,
# banc_predation.gd:portee_morsure), jamais un canal de perception : le monter
# aurait exige d'ajouter des entrees a data/canaux.json et
# data/profils_saillance.json pour un gate binaire que la distance rend deja.
# L'arbitrage lui-meme, en revanche, est REEL et non simule -- Dominance.
# visibles et Agir.choisir, appeles tels quels.
#
# LES COLONS NE SE DEPLACENT PAS, meme decoupage que banc_bonheur.gd,
# banc_marche_competence.gd, banc_affordances_choix.gd : un colon qui marche
# change lui-meme les distances, donc qui est « a portee », donc quelles
# paires accumulent -- et « l'ennemi ne partage de temps avec personne »
# serait vrai une seconde puis faux. Le verbe RESOLU est affiche, c'est lui
# qui prouve la decision.
#
# LE PIEGE DU CONSTAT (D) DES AUDITS, tenu : etat_effectif.gd ne s'applique
# QUE si quelqu'un l'appelle. Ce banc ne declare AUCUN effet module sur ses
# trois etats (tous marqueurs purs) -- il n'y a donc rien a composer, et rien
# qui serait vrai en donnee et sans effet en silence. C'est un choix : ce que
# la confiance et la rancune changent (qui l'on suit, qui l'on refuse de
# tuer) ne passe par AUCUNE propriete numerique.
#
# ---- COLONS CONSTRUITS A LA MAIN ----
# (patron banc_bonheur.gd/banc_menace_combat.gd/banc_grief.gd) : ni
# composition ni materiau, donc data/types.json n'est PAS touche et rien n'est
# a enregistrer dans scripts/test_lint_donnees.gd -- l'avertissement de
# l'audit ligne 14 (« une propriete plate de hierarchie sur data/types.json:
# colon, a inscrire dans PROPRIETES_CABLAGE_SEUL sous peine de rougir le
# linter ») ne s'applique donc pas ici. Consequence utile, verrouillee
# POSITIVEMENT par test : ne portant ni 'temperature', ni 'grief', ni aucune
# reserve, ces colons sont des chemins morts silencieux pour TOUTES les autres
# entrees du catalogue PARTAGE data/seuils_etat.json -- aucun etat parasite ne
# peut se poser, y compris ceux du chantier « rupture + migration » livre en
# parallele sur le meme fichier.
#
# ---- Deux moities, meme decoupage que les autres bancs ----
# - Node (impur) : _ready charge les quatre fichiers de donnees et construit
#   la scene ; _unhandled_input fait tourner les deux toggles ; _process
#   appelle UNIQUEMENT avancer() et lit son bilan pour l'affichage et la
#   console -- aucune decision dans _process.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_social_paire.gd) : tout le reste.
#
# AUCUN NOM DE PROPRIETE EN DUR : nom_confiance/nom_dette_negative/nom_masse/
# nom_force/nom_reference/propriete_menace/propriete_cible_ordre/
# propriete_ouvrage et les trois noms de marque arrivent tous de
# data/banc_social_paire.json -- c'est ce qui permet au test de faire traverser
# le meme code par un domaine entierement invente.

const LienPersonnel = preload("res://scripts/lien_personnel.gd")
const Epigenetique = preload("res://scripts/epigenetique.gd")
const SeuilEtat = preload("res://scripts/seuil_etat.gd")
const Bifurcation = preload("res://scripts/bifurcation.gd")
const Charge = preload("res://scripts/charge.gd")
const Dominance = preload("res://scripts/dominance.gd")
const Agir = preload("res://scripts/agir.gd")
const Monde = preload("res://scripts/monde.gd")

const MODE_SERVICE := "service"
const MODE_AGRESSION := "agression"

# Trois etats de l'ordre, cycliques -- patron banc_bonheur.gd:source_suivante
# et banc_nutrition.gd:repas_suivant. AUCUN est l'etat de depart : le banc
# lance sans un clic montre deja la confiance monter et la rancune se poser.
const ORDRE_AUCUN := 0
const ORDRE_DONNE := 1
const ORDRE_FORCE := 2

# Motifs de retrait -- des CLES, jamais du texte joueur (CLAUDE.md,
# INTERNATIONALISATION). Le label et la console les traduisent a l'affichage.
const MOTIF_SANS_CONFIANCE_COMBATTRE := "sans_confiance_combattre"
const MOTIF_RESISTE := "resiste_au_chef"
const MOTIF_SANS_CONFIANCE_OBEIR := "sans_confiance_obeir"
const MOTIF_REFUS_LIEN := "refus_lien"

# La cle de l'horloge de cadence vit HORS de proprietes, au meme rang
# qu'action_en_cours : elle change a chaque pas, ce n'est pas un fait stable
# de l'objet (docs/design.md ; patron banc_croyance.gd:prochaine_observation,
# banc_psycho_social.gd:CLE_HORLOGE_MARQUE).
const CLE_HORLOGE := "horloge_interaction"

var _config: Dictionary = {}
var _catalogue_seuils: Dictionary = {}
var _catalogue_liens: Dictionary = {}
var _catalogue_epigenetique: Dictionary = {}
var _catalogue_paires: Dictionary = {}

var _colons: Array = []
var _menace: Dictionary = {}
var _ouvrages: Dictionary = {}
var _monde
var _mode := MODE_SERVICE
var _ordre := ORDRE_AUCUN
var _temps := 0.0
var _prochaine_trace := 0.0
var _dernier_bilan: Dictionary = {}

var _couche_ui: CanvasLayer
var _noeuds: Dictionary = {}
var _labels: Dictionary = {}
var _lignes: Dictionary = {}
var _labels_paires: Dictionary = {}
var _label_compteur: Label
var _label_aide: Label

func _ready() -> void:
	_config = _charger_json("res://data/banc_social_paire.json")
	_catalogue_seuils = _charger_json("res://data/seuils_etat.json")
	_catalogue_liens = _charger_json("res://data/liens_personnels.json")
	_catalogue_epigenetique = _charger_json("res://data/epigenetique.json")

	_colons = construire_colons(_config)
	_catalogue_paires = catalogue_paires(_config, _colons, _catalogue_epigenetique)
	_menace = construire_menace(_config)
	_ouvrages = construire_ouvrages(_config)
	_monde = construire_monde(_colons, _menace, _ouvrages.values(), Monde)

	_couche_ui = CanvasLayer.new()
	add_child(_couche_ui)
	_creer_rendu()
	_poser_camera()
	print(ligne_pose(_config, _colons, _catalogue_seuils))
	_rafraichir_tout()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		_ordre = ordre_suivant(_ordre)
		print(ligne_ordre(_temps, _ordre, _config))
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_mode = MODE_AGRESSION if _mode == MODE_SERVICE else MODE_SERVICE
		print(ligne_mode(_temps, _mode))

func _process(delta: float) -> void:
	_temps += delta
	var bilan := avancer(
		_colons, _menace, _ouvrages, _mode, _ordre, _config,
		_catalogue_seuils, _catalogue_liens, _catalogue_paires, _monde, delta,
	)
	_dernier_bilan = bilan

	for ligne in lignes_bilan(_temps, bilan):
		print(ligne)
	if _temps >= _prochaine_trace:
		_prochaine_trace = _temps + float(_config.periode_trace_s)
		for colon in _colons:
			print(ligne_trace(_temps, colon, _colons, _config, _catalogue_liens))

	_rafraichir_tout()

# ---------------------------------------------------------------------------
# Construction (pure, testable headless)
# ---------------------------------------------------------------------------

# Les quatre colons, CONSTRUITS A LA MAIN (voir en-tete). 'liens_personnels' et
# 'marques_epigenetiques' partent VIDES et sont STRUCTURELLES : leur cle doit
# exister (lien_personnel.gd et epigenetique.gd alarment sinon), leur contenu
# vide est legitime. Les liens initiaux sont poses par LienPersonnel.poser,
# jamais par un Dictionary recopie -- etat INITIAL de la scene, au meme titre
# qu'une position (patron banc_croyance.gd:fabriquer_colons) ; leur naissance
# par evenement vecu est deja prouvee ailleurs (banc_lien_personnel.gd).
# 'etats' porte le canal de charge du grief de transgression, DUPLIQUE par
# colon (duplicate(true)) -- jamais partage avec le Dictionary du disque, meme
# precaution d'aliasing que banc_commun.gd:resoudre_chantier (bug reel ferme
# la-bas : charge.gd mute le canal EN PLACE, un canal partage ferait basculer
# les quatre colons ensemble).
static func construire_colons(config: Dictionary) -> Array:
	var colons: Array = []
	for decl in config.get("colons", []):
		var pos: Array = decl.position
		var proprietes: Dictionary = {
			"etats_actifs": [],
			"attaches": [],
			"forme": config.forme_colon.duplicate(true),
			"poids_verbes": config.poids_verbes_colon.duplicate(true),
			"liens_personnels": {},
			"marques_epigenetiques": {},
			"etats": {String(config.nom_canal_transgression): config.canal_transgression.duplicate(true)},
		}
		proprietes[String(config.nom_masse)] = float(decl.masse)
		proprietes[String(config.nom_force)] = float(decl.force)
		proprietes[String(config.nom_plafond_confiance)] = float(decl.plafond_confiance)
		proprietes[String(config.nom_cout_conflit)] = float(decl.cout_conflit)
		proprietes[String(config.nom_reference)] = String(decl.reference_confiance)
		var colon: Dictionary = {
			"id": String(decl.id),
			"position": Vector3(float(pos[0]), float(pos[1]), float(pos[2])),
			"proprietes": proprietes,
			"action_en_cours": {},
			"action_precedente": "__jamais__",
		}
		colon[CLE_HORLOGE] = 0.0
		for cible in decl.get("liens_initiaux", {}):
			LienPersonnel.poser(colon, String(cible), float(decl.liens_initiaux[cible]))
		colons.append(colon)
	marquer_cible_ordre(colons, config)
	return colons

# LA CIBLE DE L'ORDRE EST UN COLON, jamais un cinquieme objet : c'est ce qui
# fait que le nombre affiche sur la paire (soldat -> ami) EST celui qui
# declenche le refus. La propriete actionnable est posee ICI plutot qu'a la
# construction du colon -- elle ne concerne QUE la cible designee, et
# agir.gd:_action la resout contre le catalogue local.
static func marquer_cible_ordre(colons: Array, config: Dictionary) -> void:
	var cible := String(config.cible_ordre_id)
	for colon in colons:
		if String(colon.id) == cible:
			colon.proprietes[String(config.propriete_cible_ordre)] = true

static func construire_menace(config: Dictionary) -> Dictionary:
	var decl: Dictionary = config.menace
	var pos: Array = decl.position
	var proprietes: Dictionary = {}
	proprietes[String(config.propriete_menace)] = true
	return {
		"id": String(decl.id),
		"position": Vector3(float(pos[0]), float(pos[1]), float(pos[2])),
		"proprietes": proprietes,
		"type_banc": "menace",
	}

# UN ouvrage par colon -- la CONCURRENCE, sans laquelle le retrait d'une
# entree ne se verrait pas : un colon qui refuse de tuer doit avoir quelque
# chose vers quoi retourner, sinon « il refuse » et « la scene est vide » sont
# indistinguables. Il ne se consomme jamais (extinction.gd n'est pas cable) :
# ce banc observe une DECISION, pas un travail.
static func construire_ouvrages(config: Dictionary) -> Dictionary:
	var ouvrages: Dictionary = {}
	for decl in config.get("colons", []):
		var pos: Array = decl.ouvrage
		var proprietes: Dictionary = {}
		proprietes[String(config.propriete_ouvrage)] = true
		ouvrages[String(decl.id)] = {
			"id": "ouvrage_%s" % String(decl.id),
			"position": Vector3(float(pos[0]), float(pos[1]), float(pos[2])),
			"proprietes": proprietes,
			"type_banc": "ouvrage",
		}
	return ouvrages

# `classe_monde` est recu en PARAMETRE (jamais preload ici) pour que le test
# puisse construire le meme Monde sans dependre d'un chemin ecrit deux fois --
# patron banc_grief.gd:construire_monde.
static func construire_monde(colons: Array, menace: Dictionary, ouvrages: Array, classe_monde):
	var monde = classe_monde.new()
	for colon in colons:
		monde.ajouter(colon, "colon", colon.position)
	monde.ajouter(menace, "menace", menace.position)
	for ouvrage in ouvrages:
		monde.ajouter(ouvrage, "ouvrage", ouvrage.position)
	return monde

# ---------------------------------------------------------------------------
# Le catalogue par paire -- LA PIECE QUI REND LA PAIRE POSSIBLE
# ---------------------------------------------------------------------------

# Le nom de marque d'une paire. Un seul endroit dans tout le fichier compose
# ce nom, et un seul le decompose (nom_cible_de) : sans ca, un separateur
# change a un endroit et pas a l'autre casserait en silence.
static func marque_paire(base: String, cible_id: String) -> String:
	return "%s:%s" % [base, cible_id]

# DERIVE UNE ENTREE PAR PAIRE depuis UNE SEULE entree partagee de
# data/epigenetique.json. C'est ce qui repond a l'objection de l'audit
# (« il faudrait une entree par paire de colons » -- oui, dans le CATALOGUE
# RECU, non dans le FICHIER). La loi vit une fois en donnee ; ce catalogue-ci
# est jetable, reconstruit a chaque montage de scene, et n'est jamais ecrit
# sur le disque.
#
# Une base absente de data/epigenetique.json alarme ICI plutot que quatre
# paires plus tard dans epigenetique.gd, ou le message ne dirait plus d'ou
# vient la reference cassee.
static func catalogue_paires(config: Dictionary, colons: Array, catalogue_epigenetique: Dictionary) -> Dictionary:
	var derive: Dictionary = {}
	for role in config.get("marques", {}):
		var base := String(config.marques[role])
		if not catalogue_epigenetique.has(base):
			push_error("banc_social_paire : marque '%s' absente de data/epigenetique.json" % base)
			continue
		for colon in colons:
			derive[marque_paire(base, String(colon.id))] = catalogue_epigenetique[base]
	return derive

# ---------------------------------------------------------------------------
# Les quatre registres par paire -- LECTURES PURES, jamais des ecritures
# ---------------------------------------------------------------------------

# Le modulateur brut d'une marque par paire. Marque absente -> 0.0, point
# neutre legitime (avancer() la retire sous son plancher, elle n'est jamais
# inventee) -- meme lecture que banc_psycho_social.gd:modulateur_experience et
# banc_marche_competence.gd.
static func modulateur_paire(colon: Dictionary, base: String, cible_id: String) -> float:
	var marques: Dictionary = colon.proprietes.get("marques_epigenetiques", {})
	var canal: Dictionary = marques.get(marque_paire(base, cible_id), {})
	return float(canal.get("modulateur", 0.0))

# LE PLAFOND VIT ICI, jamais dans epigenetique.gd : poser() ajoute sans borne
# haute, et sans ce clamp la confiance monterait LINEAIREMENT ET SANS BORNE
# (constat F de l'audit -- aucune asymptote nulle part dans le coeur, toutes
# les decroissances sont des soustractions fixes). PAR COLON, et c'est le
# coeur de l'escalier : l'ami plafonne entre les deux seuils.
static func confiance(colon: Dictionary, cible_id: String, config: Dictionary) -> float:
	var plafond: float = float(colon.proprietes.get(String(config.nom_plafond_confiance), 0.0))
	return min(modulateur_paire(colon, String(config.marques.confiance), cible_id), plafond)

static func lien_positif(colon: Dictionary, cible_id: String, catalogue_liens: Dictionary) -> float:
	return LienPersonnel.force(colon, cible_id, catalogue_liens)

# Plafond PARTAGE ici (contrairement a la confiance) : rien dans ce chantier
# ne demande que deux colons haissent differemment.
static func lien_negatif(colon: Dictionary, cible_id: String, config: Dictionary) -> float:
	return min(
		modulateur_paire(colon, String(config.marques.lien_negatif), cible_id),
		float(config.plafond_lien_negatif),
	)

# LE SCORE NET -- la reponse a la ligne 2. Une LECTURE, refaite a neuf, jamais
# une valeur stockee : c'est ce qui permet aux deux registres de rester
# POSITIFS chacun de leur cote pendant que leur difference, elle, est signee.
static func score_net(colon: Dictionary, cible_id: String, config: Dictionary, catalogue_liens: Dictionary) -> float:
	return lien_positif(colon, cible_id, catalogue_liens) - lien_negatif(colon, cible_id, config)

static func service_rendu(colon: Dictionary, cible_id: String, config: Dictionary) -> float:
	return min(
		modulateur_paire(colon, String(config.marques.service), cible_id),
		float(config.plafond_service),
	)

# LA DETTE, lue sur DEUX ENTITES : ce que `colon` a rendu a `autre`, moins ce
# qu'`autre` lui a rendu. Negative quand le colon a RECU plus qu'il n'a rendu.
# Constat (E) de l'audit : aucun mecanisme du coeur ne compare une propriete
# de A a une propriete de B, cette soustraction est donc du cablage.
static func dette_sociale(colon: Dictionary, autre: Dictionary, config: Dictionary) -> float:
	return service_rendu(colon, String(autre.id), config) - service_rendu(autre, String(colon.id), config)

# Le MINIMUM sur toutes les paires, jamais la somme : etre lourdement en dette
# envers UN colon suffit, et deux dettes opposees envers deux colons ne
# doivent pas s'annuler. Rend { valeur, cible } -- la cible sert au label et a
# la trace, jamais au seuil (un etat ne porte qu'un nom, il ne sait pas dire
# envers qui). Aucun autre colon : 0.0, jamais une dette inventee.
static func dette_minimale(colon: Dictionary, colons: Array, config: Dictionary) -> Dictionary:
	var pire := 0.0
	var cible := ""
	for autre in colons:
		if String(autre.id) == String(colon.id):
			continue
		var valeur := dette_sociale(colon, autre, config)
		if valeur < pire:
			pire = valeur
			cible = String(autre.id)
	return {"valeur": pire, "cible": cible}

# SOMME PONDEREE DE PROPRIETES, RECALCULEE A NEUF a chaque appel -- jamais un
# '+=', jamais une valeur stockee : c'est ce recalcul, et lui seul, qui
# empeche un champ derive de deriver (resultat negatif mesure deux fois dans
# le depot, voir data/epigenetique.json). Copie exacte du geste de
# banc_predation.gd:score_hierarchie, lui-meme copie de
# banc_bonheur.gd:calculer_bonheur. LECTURE PURE.
static func score_hierarchie(colon: Dictionary, config: Dictionary) -> float:
	var regle: Dictionary = config.get("hierarchie", {})
	var proprietes: Dictionary = colon.proprietes
	return float(regle.get("poids_masse", 0.0)) * float(proprietes.get(String(config.nom_masse), 0.0)) \
		+ float(regle.get("poids_force", 0.0)) * float(proprietes.get(String(config.nom_force), 0.0))

# LE SCORE DE CESSION (ligne 14). Somme ponderee de DEUX termes qui ne se
# ressemblent pas : ce que le chef vaut POUR CE COLON (le score net de la
# paire) et ce que le chef vaut EN SOI (son score de hierarchie).
#
# LE TERME DE LIEN EST LE SCORE NET, pas LienPersonnel.force nue -- ECART
# ASSUME A LA LETTRE DE LA CONSIGNE, et il est necessaire : sans lui, « un
# chef HAI se fait resister » n'est observable nulle part, la haine n'entrant
# dans aucun calcul. C'est la meme lecture de paire que partout ailleurs dans
# ce fichier ; lire le positif nu ici serait la seule exception.
static func score_cession(colon: Dictionary, chef: Dictionary, config: Dictionary, catalogue_liens: Dictionary) -> float:
	return float(config.poids_lien_cession) * score_net(colon, String(chef.id), config, catalogue_liens) \
		+ float(config.poids_hierarchie_cession) * score_hierarchie(chef, config)

static func colon_par_id(colons: Array, id: String) -> Dictionary:
	for colon in colons:
		if String(colon.id) == id:
			return colon
	return {}

# ---------------------------------------------------------------------------
# Les interactions -- le seul endroit qui ECRIT les registres par paire
# ---------------------------------------------------------------------------

# UNE CADENCE, jamais un appel par image (contrainte (c) en tete : poser() n'a
# pas de delta). L'horloge vit sur le colon SOURCE, hors de proprietes, pour
# que cette fonction reste pure et testable sans la scene (patron
# banc_croyance.gd:observer_si_cadence, banc_psycho_social.gd:
# avancer_experience). La boucle `while` rattrape un delta plus grand que
# l'intervalle plutot que de perdre des poses.
#
# « A PORTEE » EST REEL, pas decoratif : une interaction declaree dont la
# source et la cible sont trop loin ne se pose PAS. C'est ce qui fait que le
# temps partage est un fait du monde et non une table. Verrouille par test
# (un colon eloigne cesse d'accumuler, sa confiance redescend et ses etats se
# retirent).
#
# QUI RECOIT LA MARQUE, et ce n'est pas le meme pour les trois genres :
# - temps_partage : sur la SOURCE, marque 'confiance:<cible>' -- c'est A qui
#   apprend a faire confiance a B.
# - service : sur la SOURCE, marque 'service_rendu:<cible>' -- c'est A qui a
#   rendu. Le beneficiaire n'ecrit rien ; sa dette est la LECTURE de ce
#   registre dans l'autre sens (voir dette_sociale).
# - agression : sur la CIBLE, marque 'lien_negatif:<source>' -- c'est la
#   VICTIME qui hait l'agresseur, jamais l'inverse.
#
# Rend l'Array des poses effectuees ({ source, cible, genre }) -- pour la
# trace et le test, jamais relu par le calcul.
static func appliquer_interactions(
	colons: Array,
	mode: String,
	config: Dictionary,
	catalogue_paires_local: Dictionary,
	delta: float,
) -> Array:
	var intervalle: float = float(config.intervalle_interaction_s)
	if intervalle <= 0.0:
		push_error("banc_social_paire : intervalle_interaction_s doit etre strictement positif")
		return []
	var declarees: Array = config.get("interactions", {}).get(mode, [])
	var portee: float = float(config.portee_interaction)
	var poses: Array = []
	for colon in colons:
		var horloge: float = float(colon.get(CLE_HORLOGE, 0.0)) + delta
		while horloge >= intervalle:
			horloge -= intervalle
			for declaree in declarees:
				if String(declaree.source) != String(colon.id):
					continue
				var cible := colon_par_id(colons, String(declaree.cible))
				if cible.is_empty():
					push_error("banc_social_paire : interaction vers un colon inconnu '%s'" % String(declaree.cible))
					continue
				if colon.position.distance_to(cible.position) > portee:
					continue
				_poser_interaction(colon, cible, String(declaree.genre), config, catalogue_paires_local)
				poses.append({"source": String(colon.id), "cible": String(cible.id), "genre": String(declaree.genre)})
		colon[CLE_HORLOGE] = horloge
	return poses

# Le genre decide QUI porte la marque, LAQUELLE, et contre QUEL plafond -- un
# genre inconnu alarme plutot que de ne rien faire en silence.
static func _poser_interaction(
	source: Dictionary,
	cible: Dictionary,
	genre: String,
	config: Dictionary,
	catalogue_paires_local: Dictionary,
) -> void:
	var marques: Dictionary = config.marques
	match genre:
		"temps_partage":
			_poser_borne(source, String(marques.confiance), String(cible.id),
				float(source.proprietes.get(String(config.nom_plafond_confiance), 0.0)), catalogue_paires_local)
		"service":
			_poser_borne(source, String(marques.service), String(cible.id),
				float(config.plafond_service), catalogue_paires_local)
		"agression":
			_poser_borne(cible, String(marques.lien_negatif), String(source.id),
				float(config.plafond_lien_negatif), catalogue_paires_local)
		_:
			push_error("banc_social_paire : genre d'interaction inconnu '%s'" % genre)

# LE PLAFOND EST APPLIQUE A LA POSE, PAS SEULEMENT A LA LECTURE -- et ce n'est
# pas un raffinement, c'est un DEFAUT REEL TROUVE EN LANCANT LE TEST.
#
# epigenetique.gd:poser ajoute SANS BORNE HAUTE (constat (F) de l'audit : il
# n'existe AUCUNE asymptote dans le coeur, toutes les decroissances sont des
# soustractions fixes). Un modulateur laisse libre monte donc LINEAIREMENT au
# -dela du plafond -- et comme les lecteurs le clampent, la valeur affichee
# reste collee au plafond pendant tout le temps qu'il faut a l'exces pour
# redescendre. Mesure : apres 6 s de temps partage le modulateur du soldat
# valait 1.08 pour un plafond de 1.00 ; eloigne, il a mis quatre secondes a
# seulement REDEVENIR visible, et le test « hors de portee, la confiance doit
# descendre » lisait 1.000 -> 1.000. Une HYSTERESIS PAR ACCIDENT, invisible,
# proportionnelle au temps passe ensemble -- exactement le genre de chose
# qu'un banc existe pour ne pas laisser passer.
#
# Corrige en ne POSANT PLUS quand le registre a atteint son plafond : le
# modulateur reste borne, la decroissance est visible des le premier tick
# d'absence, et la reversibilite ne depend plus de l'histoire. Ce n'est pas un
# cas particulier code -- c'est le patron de banc_marche_competence.gd (« un
# novice a competence nulle : magnitude 0.0, le cablage n'appelle meme pas
# poser() »), la meme arithmetique lue a l'autre bout.
#
# Le clamp a la LECTURE reste en place malgre tout : ce sont deux gardes
# differentes. Celle-ci borne ce que le CABLAGE accumule ; l'autre borne ce
# qu'un registre pose AUTREMENT (un etat initial, un test) pourrait valoir.
static func _poser_borne(
	porteur: Dictionary,
	base: String,
	cible_id: String,
	plafond: float,
	catalogue_paires_local: Dictionary,
) -> void:
	if modulateur_paire(porteur, base, cible_id) >= plafond:
		return
	Epigenetique.poser(porteur, marque_paire(base, cible_id), catalogue_paires_local)

# ---------------------------------------------------------------------------
# Les deux miroirs plats -- ECRIVAIN UNIQUE
# ---------------------------------------------------------------------------

# UNIQUE ECRIVAIN de 'confiance' ET de 'dette_negative'. Les deux dans le MEME
# geste, chacun RECALCULE A NEUF depuis les registres par paire, jamais un
# '+=' : c'est ce recalcul qui les rend reversibles sans une ligne de plus
# (seuil_etat.gd retire l'etat au franchissement descendant). Patron
# banc_bonheur.gd:poser_bonheur -- deux morceaux de cablage qui ecriraient
# chacun un miroir se desynchroniseraient EN SILENCE, aucun test ne rougirait.
#
# 'confiance' est la confiance envers la REFERENCE declaree du colon, pas un
# maximum : l'escalier de la ligne 1 parle d'une relation precise (« se battre
# a SES cotes », « obeir a SES ordres »), et un maximum sur toutes les paires
# aurait fait obeir un colon au chef parce qu'il a confiance en quelqu'un
# d'autre. Reference vide ou inconnue -> 0.0, chemin mort silencieux.
#
# 'dette_negative' est INVERSE (max(0, -dette_min)) : seuil_etat.gd ne compare
# que vers le HAUT, « la dette descend sous -1.0 » ne s'ecrit que « son oppose
# monte au-dessus de 1.0 ». Borne a 0.0 par le bas -- un colon qui n'a que des
# dettes positives n'a pas une rancune negative, il n'en a pas.
#
# MUTE le colon en place ; rend le detail pour que l'affichage relise sans
# jamais rien recalculer.
static func poser_miroirs(colon: Dictionary, colons: Array, config: Dictionary) -> Dictionary:
	var reference := String(colon.proprietes.get(String(config.nom_reference), ""))
	var valeur_confiance := 0.0
	if reference != "":
		valeur_confiance = confiance(colon, reference, config)
	var pire := dette_minimale(colon, colons, config)
	var dette_negative: float = max(0.0, -float(pire.valeur))
	colon.proprietes[String(config.nom_confiance)] = valeur_confiance
	colon.proprietes[String(config.nom_dette_negative)] = dette_negative
	return {
		"confiance": valeur_confiance,
		"reference": reference,
		"dette_negative": dette_negative,
		"dette_min": float(pire.valeur),
		"dette_cible": String(pire.cible),
	}

# ---------------------------------------------------------------------------
# La cession (ligne 14) -- bifurcation.gd
# ---------------------------------------------------------------------------

static func ordre_suivant(index: int) -> int:
	return (index + 1) % 3

static func ordre_present(index: int) -> bool:
	return index != ORDRE_AUCUN

static func ordre_est_force(index: int) -> bool:
	return index == ORDRE_FORCE

# Un colon est destinataire de l'ordre s'il n'en est ni l'emetteur ni la
# cible -- CALCULE, jamais liste en donnee : une liste serait une seconde
# verite a garder d'accord avec chef_id/cible_ordre_id.
static func destinataire_ordre(colon: Dictionary, config: Dictionary) -> bool:
	var id := String(colon.id)
	return id != String(config.chef_id) and id != String(config.cible_ordre_id)

# LA CESSION. bifurcation.gd est appele TEL QUEL, et toute la loi de decision
# vit dans le BIAIS -- voir contrainte (b) en tete : la grandeur est un
# scalaire COMMUN qui ne peut jamais departager deux sorties, elle ne sert
# qu'a GATER (1.0 s'il y a un ordre pour ce colon, 0.0 sinon : aucune sortie
# n'est rendue sans ordre, PAR LA SEULE ARITHMETIQUE, sans qu'aucun `if` ne
# l'interdise -- idiome que bifurcation.gd annonce lui-meme).
#
# Le biais est une LECTURE composee a neuf a chaque tick, jamais une donnee
# portee par le colon (patron banc_menace_combat.gd:biais_effectif) :
# { ceder: score_cession, resister: cout_conflit }. L'argmax retient donc
# 'ceder' quand la somme ponderee depasse le cout du conflit, 'resister'
# sinon -- c'est exactement « le cablage compare cout_conflit a la somme
# ponderee, bifurcation.gd tranche ».
#
# Rend le Dictionary COMPLET de Bifurcation.resoudre ({ sortie, score,
# scores, a_egalite }), jamais la seule sortie : l'affichage doit pouvoir
# EXPLIQUER pourquoi sans reimplementer la loi.
static func resoudre_cession(
	colon: Dictionary,
	chef: Dictionary,
	config: Dictionary,
	catalogue_liens: Dictionary,
	index_ordre: int,
) -> Dictionary:
	var grandeur := 1.0 if (ordre_present(index_ordre) and destinataire_ordre(colon, config)) else 0.0
	var biais: Dictionary = {
		"ceder": score_cession(colon, chef, config, catalogue_liens),
		"resister": float(colon.proprietes.get(String(config.nom_cout_conflit), 0.0)),
	}
	return Bifurcation.resoudre(grandeur, biais, config.sorties_cession)

# ---------------------------------------------------------------------------
# Les entrees de saillance, le filtre, la decision
# ---------------------------------------------------------------------------

static func entree_menace(menace: Dictionary, config: Dictionary) -> Dictionary:
	return {
		"chose": menace,
		"type": String(menace.get("type_banc", "menace")),
		"position": menace.position,
		"saillance": float(config.saillance_menace),
	}

static func entree_ouvrage(ouvrage: Dictionary, config: Dictionary) -> Dictionary:
	return {
		"chose": ouvrage,
		"type": String(ouvrage.get("type_banc", "ouvrage")),
		"position": ouvrage.position,
		"saillance": float(config.saillance_ouvrage),
	}

# L'ordre est UNE SAILLANCE CONCURRENTE, jamais un drapeau ni un bonus additif
# (docs/design.md, « Ordre et tension » : « Un ordre ne supprime jamais une
# saillance. Il en AJOUTE une, concurrente. »). agir.gd retient le MEILLEUR
# score, il n'additionne jamais : bonus_ordre doit DEPASSER la menace et
# l'ouvrage pour etre suivi. Patron banc_grief.gd:entree_directive et
# banc_psycho_social.gd:entree_directive.
static func entree_ordre(cible: Dictionary, config: Dictionary) -> Dictionary:
	return {
		"chose": cible,
		"type": "ordre",
		"position": cible.position,
		"saillance": float(config.bonus_ordre),
		"ordre": true,
	}

# Les trois entrees BRUTES, avant tout gate -- construites pour tout le monde
# et dans le meme ordre, de sorte que ce qui distingue deux colons soit
# entierement dans le FILTRE et jamais dans ce qui leur est propose.
static func resultats_bruts(
	colon: Dictionary,
	menace: Dictionary,
	ouvrage: Dictionary,
	cible_ordre: Dictionary,
	config: Dictionary,
	index_ordre: int,
) -> Array:
	var resultats: Array = [entree_menace(menace, config), entree_ouvrage(ouvrage, config)]
	if ordre_present(index_ordre) and destinataire_ordre(colon, config) and not cible_ordre.is_empty():
		resultats.append(entree_ordre(cible_ordre, config))
	return resultats

# LE GESTE CENTRAL DE LA LIGNE 11 : RETIRER des entrees de resultats AVANT
# dominance.gd. Patron banc_economie.gd:filtrer_rentables, precedent UNIQUE du
# depot pour ce geste -- et necessaire parce que dominance.gd est RELATIF par
# construction (il garde ce qui est a moins de seuil_ecrasement du sommet) et
# ne peut porter aucun seuil ABSOLU.
#
# Rend { gardes, retires } plutot que la seule liste gardee : ce qui a ete
# ecarte doit rester lisible (l'ecran le grise, la console le nomme), sans
# quoi un filtre severe ressemblerait a une scene vide. Chaque retire porte
# son MOTIF -- une CLE, jamais du texte.
#
# QUATRE GATES, dans cet ordre, et il n'est pas interchangeable :
#  1. la menace exige 'confiant_combattre' -- on ne se bat pas aux cotes de
#     qui l'on ne connait pas assez (ligne 1) ;
#  2. l'ordre exige que le colon ait CEDE -- la cession est un fait de
#     l'instant (ligne 14) ;
#  3. l'ordre exige 'confiant_obeir' -- la confiance est un fait accumule
#     (ligne 1). Distinct du precedent, voir (4) en tete ;
#  4. l'ordre tombe si le lien positif vers la cible depasse seuil_attache --
#     LE REFUS DE TUER UN PROCHE (ligne 11). C'est le SEUL gate que l'ordre
#     FORCE peut outrepasser, et l'entree gardee est alors marquee
#     'transgression' : c'est elle qui alimentera charge.gd.
#
# LE LECTEUR DU LIEN EST LienPersonnel.force, PAS attaches.gd -- correction de
# voie de l'audit ligne 11, verifiee sur le code : attaches.gd:evaluer rend une
# entree PAR ATTACHE, et une attache lie a un TRAIT (attache.propriete), jamais
# a un individu. Elle ne peut structurellement pas porter « la force de A
# envers B ».
#
# Le lien lu est le POSITIF NU, pas le score net : on refuse de tuer qui l'on
# aime, et une haine par ailleurs n'annule pas cet amour -- les deux registres
# sont distincts, c'est tout le point de la ligne 2. (Le score net, lui, sert
# a la cession : voir score_cession.)
static func filtrer_resultats(
	colon: Dictionary,
	resultats: Array,
	cession: Dictionary,
	config: Dictionary,
	catalogue_liens: Dictionary,
	index_ordre: int,
) -> Dictionary:
	var actifs: Array = colon.proprietes.get("etats_actifs", [])
	var gardes: Array = []
	var retires: Array = []
	for entree in resultats:
		# Dictionary NEUF, jamais entree.duplicate(true) : une copie profonde
		# dupliquerait la CHOSE elle-meme, et dominance.gd rendrait des entrees
		# pointant sur des copies mortes que plus rien du monde ne mute (bug
		# nomme et evite par banc_economie.gd:filtrer_rentables).
		var copie: Dictionary = {
			"chose": entree.chose,
			"type": entree.type,
			"position": entree.position,
			"saillance": float(entree.saillance),
		}
		if entree.get("ordre", false):
			copie["ordre"] = true

		if entree.chose.proprietes.get(String(config.propriete_menace), false):
			if not actifs.has(String(config.etat_confiant_combattre)):
				retires.append(_retire(copie, MOTIF_SANS_CONFIANCE_COMBATTRE))
				continue
			gardes.append(copie)
			continue

		if not entree.get("ordre", false):
			gardes.append(copie)
			continue

		if String(cession.get("sortie", "")) != "ceder":
			retires.append(_retire(copie, MOTIF_RESISTE))
			continue
		if not actifs.has(String(config.etat_confiant_obeir)):
			retires.append(_retire(copie, MOTIF_SANS_CONFIANCE_OBEIR))
			continue
		var lien: float = lien_positif(colon, String(entree.chose.id), catalogue_liens)
		if lien > float(config.seuil_attache):
			if not ordre_est_force(index_ordre):
				retires.append(_retire(copie, MOTIF_REFUS_LIEN))
				continue
			copie["transgression"] = true
		gardes.append(copie)
	return {"gardes": gardes, "retires": retires}

static func _retire(copie: Dictionary, motif: String) -> Dictionary:
	copie["motif"] = motif
	return copie

# Les entrees SYNTHETIQUES filtrees, puis l'arbitrage REEL : dominance.gd
# ecrase ce qui est trop loin du sommet, agir.gd retient le meilleur score et
# resout le verbe contre le catalogue LOCAL. Rend tout ce que l'affichage et
# le test ont besoin de relire, sans jamais rien recalculer ailleurs.
static func decider(
	colon: Dictionary,
	menace: Dictionary,
	ouvrage: Dictionary,
	cible_ordre: Dictionary,
	cession: Dictionary,
	config: Dictionary,
	catalogue_liens: Dictionary,
	index_ordre: int,
	monde,
) -> Dictionary:
	var bruts := resultats_bruts(colon, menace, ouvrage, cible_ordre, config, index_ordre)
	var filtre := filtrer_resultats(colon, bruts, cession, config, catalogue_liens, index_ordre)
	if filtre.gardes.is_empty():
		return {"decision": null, "bruts": bruts, "gardes": [], "retires": filtre.retires, "visibles": [], "transgresse": false}
	var visibles := Dominance.visibles(filtre.gardes, colon)
	var decision = Agir.choisir(visibles, colon, config.catalogue_local, monde)
	# LA TRANSGRESSION N'EST PAS « l'entree a survecu au gate », c'est « le
	# colon a REELLEMENT choisi de tuer » : une entree gardee que dominance.gd
	# ou agir.gd n'auraient pas retenue ne coute rien. Lu sur la DECISION,
	# jamais sur le filtre.
	var transgresse: bool = decision != null and bool(decision.get("transgression", false))
	return {
		"decision": decision,
		"bruts": bruts,
		"gardes": filtre.gardes,
		"retires": filtre.retires,
		"visibles": visibles,
		"transgresse": transgresse,
	}

# ---------------------------------------------------------------------------
# Le grief de transgression -- charge.gd
# ---------------------------------------------------------------------------

# CAUSE SYNTHETISEE : le colon est SA PROPRE cause, a portee_charge 0.0 --
# charge.gd ne scanne jamais le monde ici (patron
# banc_menace_combat.gd:causes_de_menace, banc_fatigue_circadien.gd:
# causes_dette, banc_nutrition.gd). Rend un Array VIDE quand le colon ne
# transgresse pas, et c'est ce vide -- jamais un poids a 0.0 -- qui declenche
# la redescente autonome de charge.gd (son taux_decroissance n'est applique
# que si la somme des poids a portee est nulle ce pas ; un poids nul y serait
# une somme nulle aussi, mais l'Array vide dit l'intention).
#
# POURQUOI charge.gd ET NON UN TERME DE PROPRIETE PLATE, ecart assume a
# l'audit ligne 11 (qui renvoyait vers banc_grief.gd:poser_grief, « pas
# charge.gd ») : la transgression de ce banc n'est PAS un evenement ponctuel,
# elle DURE tant que l'ordre force est execute. C'est exactement le domaine de
# charge.gd -- monte sous cause, redescend seule, pose et RETIRE son marqueur
# au franchissement. Le rendre reversible avec une propriete plate aurait
# demande d'ecrire a la main les deux sens.
static func causes_transgression(colon: Dictionary, transgresse: bool, config: Dictionary) -> Array:
	if not transgresse:
		return []
	return [{"position": colon.position, "poids": float(config.cout_transgression)}]

static func charge_transgression(colon: Dictionary, config: Dictionary) -> float:
	return float(colon.proprietes.get("etats", {})
		.get(String(config.nom_canal_transgression), {}).get("charge", 0.0))

static func est_transgresseur(colon: Dictionary, config: Dictionary) -> bool:
	return bool(colon.proprietes.get(String(config.nom_marqueur_transgression), false))

# ---------------------------------------------------------------------------
# LE TICK ENTIER, en une fonction pure et testable
# ---------------------------------------------------------------------------

# (Regle d'etat, CLAUDE.md : ce qui a marche une fois sort de _process pour
# etre verrouille.) MUTE les colons en place. L'ordre n'est PAS
# interchangeable :
#   1. les interactions ecrivent les registres par paire (cadence, a portee)
#   2. les registres decroissent   (Epigenetique.avancer, LienPersonnel.avancer
#      -- INCONDITIONNELS : la decroissance ne s'arrete jamais, c'est la pose
#      qui la depasse)
#   3. les miroirs plats sont recrits a neuf   (poser_miroirs, ecrivain unique)
#   4. les seuils tranchent   (SeuilEtat.avancer, catalogue PARTAGE tel quel)
#   5. la cession est resolue   (bifurcation.gd)
#   6. la decision est prise   (filtre -> dominance -> agir)
#   7. le grief de transgression monte ou descend   (charge.gd)
# Mettre 3 avant 2 comparerait des registres perimes d'un tick ; mettre 4
# avant 3 ferait trancher les seuils sur le miroir du tick precedent ; mettre
# 7 avant 6 chargerait le grief d'une transgression pas encore decidee.
#
# Le catalogue PARTAGE de seuils est passe EN ENTIER, tel quel : les autres
# entrees (point_fusion, faim, grief, hygiene...) comparent des proprietes que
# ces colons ne portent pas -- chemins morts silencieux, aucune collision
# possible (verrouille POSITIVEMENT par test).
static func avancer(
	colons: Array,
	menace: Dictionary,
	ouvrages: Dictionary,
	mode: String,
	index_ordre: int,
	config: Dictionary,
	catalogue_seuils: Dictionary,
	catalogue_liens: Dictionary,
	catalogue_paires_local: Dictionary,
	monde,
	delta: float,
) -> Dictionary:
	var poses := appliquer_interactions(colons, mode, config, catalogue_paires_local, delta)

	for colon in colons:
		Epigenetique.avancer(colon, delta, catalogue_paires_local)
		LienPersonnel.avancer(colon, delta, catalogue_liens)

	var miroirs: Dictionary = {}
	for colon in colons:
		miroirs[colon.id] = poser_miroirs(colon, colons, config)

	var avant: Dictionary = {}
	for colon in colons:
		avant[colon.id] = colon.proprietes.get("etats_actifs", []).duplicate()
	SeuilEtat.avancer(colons, catalogue_seuils)

	var chef := colon_par_id(colons, String(config.chef_id))
	var cible_ordre := colon_par_id(colons, String(config.cible_ordre_id))
	var etats: Array = []
	for colon in colons:
		var cession: Dictionary = {"sortie": "", "score": 0.0, "scores": {}, "a_egalite": []}
		if not chef.is_empty():
			cession = resoudre_cession(colon, chef, config, catalogue_liens, index_ordre)
		var ouvrage: Dictionary = ouvrages.get(colon.id, {})
		var r := decider(colon, menace, ouvrage, cible_ordre, cession, config,
			catalogue_liens, index_ordre, monde)
		if r.decision != null:
			colon.action_en_cours = Agir.etat_courant(r.decision)
		Charge.avancer([colon], causes_transgression(colon, r.transgresse, config), delta)
		etats.append({
			"id": String(colon.id),
			"miroirs": miroirs[colon.id],
			"cession": cession,
			"verbe": "" if r.decision == null else String(r.decision.get("action", "")),
			"cible": "" if r.decision == null else String(r.decision.get("chose", {}).get("id", "")),
			"retires": r.retires,
			"visibles": r.visibles,
			"transgresse": bool(r.transgresse),
			"charge": charge_transgression(colon, config),
			"changements": changements_etats(avant[colon.id], colon.proprietes.get("etats_actifs", [])),
		})
	return {"poses": poses, "colons": etats}

# Compare deux instantanes d'etats_actifs -- seuil_etat.gd rend les ids ayant
# bascule, jamais QUELS etats, d'ou cette comparaison cote cablage (patron
# banc_bonheur.gd:changements_etats). PURE.
static func changements_etats(avant: Array, apres: Array) -> Dictionary:
	var gagnes: Array = []
	var perdus: Array = []
	for etat in apres:
		if not avant.has(etat):
			gagnes.append(String(etat))
	for etat in avant:
		if not apres.has(etat):
			perdus.append(String(etat))
	return {"gagnes": gagnes, "perdus": perdus}

# ---------------------------------------------------------------------------
# Textes (purs eux aussi : le test les verrouille sans ouvrir la scene)
# ---------------------------------------------------------------------------

static func texte_etats(colon: Dictionary) -> String:
	var noms: Array = []
	for etat in colon.proprietes.get("etats_actifs", []):
		noms.append(String(etat))
	noms.sort()
	return " + ".join(noms) if not noms.is_empty() else "neutre"

static func texte_colon(colon: Dictionary, etat_colon: Dictionary, config: Dictionary) -> String:
	var miroirs: Dictionary = etat_colon.miroirs
	var cession := String(etat_colon.cession.get("sortie", ""))
	return "%s\netats : %s\nhierarchie %.2f -- confiance(%s) %.2f\ndette %+.2f -- rancune %.2f\ncession : %s\nverbe : %s %s%s" % [
		String(colon.id),
		texte_etats(colon),
		score_hierarchie(colon, config),
		String(miroirs.reference),
		float(miroirs.confiance),
		float(miroirs.dette_min),
		float(miroirs.dette_negative),
		cession if cession != "" else "-",
		String(etat_colon.verbe) if String(etat_colon.verbe) != "" else "-",
		String(etat_colon.cible),
		"" if not bool(etat_colon.transgresse) else "  [TRANSGRESSE %.2f]" % float(etat_colon.charge),
	]

# LE LABEL PAR PAIRE, les DEUX sens sur deux lignes : un lien n'est jamais
# symetrique et l'afficher moyenne mentirait. Pose au milieu du segment.
static func texte_paire(a: Dictionary, b: Dictionary, config: Dictionary, catalogue_liens: Dictionary) -> String:
	return "%s\n%s" % [_texte_sens(a, b, config, catalogue_liens), _texte_sens(b, a, config, catalogue_liens)]

static func _texte_sens(source: Dictionary, cible: Dictionary, config: Dictionary, catalogue_liens: Dictionary) -> String:
	var id_cible := String(cible.id)
	return "%s>%s c%.2f +%.2f -%.2f net%+.2f d%+.2f" % [
		String(source.id).substr(0, 3),
		id_cible.substr(0, 3),
		confiance(source, id_cible, config),
		lien_positif(source, id_cible, catalogue_liens),
		lien_negatif(source, id_cible, config),
		score_net(source, id_cible, config, catalogue_liens),
		dette_sociale(source, cible, config),
	]

# Les trois noms d'etat arrivent de la donnee, jamais ecrits ici -- c'est ce
# qui permet au test hors domaine de faire traverser ce meme code par un
# vocabulaire entierement invente. `transgresseur` n'est pas un etat mais une
# propriete PLATE posee par charge.gd : compte a part, lu par est_transgresseur.
static func noms_etats(config: Dictionary) -> Array:
	return [
		String(config.etat_confiant_combattre),
		String(config.etat_confiant_obeir),
		String(config.etat_rancunier),
	]

static func texte_compteur(colons: Array, config: Dictionary, mode: String, index_ordre: int, temps: float) -> String:
	var noms := noms_etats(config)
	var comptes: Dictionary = {}
	for nom in noms:
		comptes[nom] = 0
	var transgresseurs := 0
	for colon in colons:
		var actifs: Array = colon.proprietes.get("etats_actifs", [])
		for nom in noms:
			if actifs.has(nom):
				comptes[nom] = int(comptes[nom]) + 1
		if est_transgresseur(colon, config):
			transgresseurs += 1
	var morceaux: Array = []
	for nom in noms:
		morceaux.append("%s %d" % [nom, int(comptes[nom])])
	morceaux.append("%s %d" % [String(config.nom_marqueur_transgression), transgresseurs])
	return "t=%.1f s -- interactions : %s -- ordre : %s -- %s" % [
		temps, mode, mot_ordre(index_ordre), " | ".join(morceaux),
	]

static func mot_ordre(index_ordre: int) -> String:
	match index_ordre:
		ORDRE_DONNE: return "donne"
		ORDRE_FORCE: return "FORCE"
		_: return "aucun"

static func texte_aide(config: Dictionary) -> String:
	return "clic GAUCHE : ordre de tuer '%s' -- aucun / donne / FORCE    clic DROIT : interactions service <-> agression\nlignes VERTES = score net positif, ROUGES = negatif ; le score net est lien_positif - lien_negatif, jamais une valeur signee stockee" % String(config.cible_ordre_id)

static func ligne_pose(config: Dictionary, colons: Array, catalogue_seuils: Dictionary) -> String:
	var morceaux: Array = []
	for colon in colons:
		morceaux.append("%s (hierarchie %.2f, plafond confiance %.2f, cout conflit %.1f)" % [
			String(colon.id), score_hierarchie(colon, config),
			float(colon.proprietes.get(String(config.nom_plafond_confiance), 0.0)),
			float(colon.proprietes.get(String(config.nom_cout_conflit), 0.0)),
		])
	return "t=0.0 %d colons poses -- %s\nseuils partages : confiance > %.2f (combattre), confiance > %.2f (obeir), dette_negative > %.2f (rancune) ; seuil d'attache %.2f" % [
		colons.size(), " | ".join(morceaux),
		seuil_de(catalogue_seuils, String(config.ref_seuil_combattre)),
		seuil_de(catalogue_seuils, String(config.ref_seuil_obeir)),
		seuil_de(catalogue_seuils, String(config.ref_seuil_rancune)),
		float(config.seuil_attache),
	]

# Les trois seuils vivent dans le catalogue PARTAGE, jamais recopies en donnee
# de banc : une seule source de verite, jamais deux nombres a garder d'accord
# (geste de banc_bonheur.gd:seuil_de). Le banc ne les relit que pour son
# affichage -- c'est seuil_etat.gd, et lui seul, qui pose les etats.
static func seuil_de(catalogue_seuils: Dictionary, ref: String) -> float:
	if not catalogue_seuils.has(ref) or not catalogue_seuils[ref].has("seuil"):
		push_error("banc_social_paire : entree '%s' sans 'seuil' dans data/seuils_etat.json" % ref)
		return INF
	return float(catalogue_seuils[ref].seuil)

static func ligne_ordre(t: float, index_ordre: int, config: Dictionary) -> String:
	return "t=%.1f ORDRE : %s (cible '%s')" % [t, mot_ordre(index_ordre), String(config.cible_ordre_id)]

static func ligne_mode(t: float, mode: String) -> String:
	return "t=%.1f INTERACTIONS : %s" % [t, mode]

# La console ne trace QUE les evenements, jamais l'etat continu : un seuil
# franchi, un refus, une cession qui change, une transgression qui bascule.
# Les valeurs continues vivent dans les labels et dans ligne_trace.
static func lignes_bilan(t: float, bilan: Dictionary) -> Array:
	var lignes: Array = []
	for etat_colon in bilan.get("colons", []):
		for etat in etat_colon.changements.get("gagnes", []):
			lignes.append("t=%.1f SEUIL FRANCHI : %s gagne '%s'" % [t, String(etat_colon.id), String(etat)])
		for etat in etat_colon.changements.get("perdus", []):
			lignes.append("t=%.1f SEUIL REDESCENDU : %s perd '%s'" % [t, String(etat_colon.id), String(etat)])
		for retire in etat_colon.retires:
			if String(retire.motif) == MOTIF_REFUS_LIEN:
				lignes.append("t=%.1f REFUS : %s refuse de tuer '%s' (lien au-dessus du seuil d'attache)" % [
					t, String(etat_colon.id), String(retire.chose.id)])
			elif String(retire.motif) == MOTIF_RESISTE:
				lignes.append("t=%.1f RESISTANCE : %s resiste au chef (cession %.2f contre cout de conflit %.2f)" % [
					t, String(etat_colon.id),
					float(etat_colon.cession.get("scores", {}).get("ceder", 0.0)),
					float(etat_colon.cession.get("scores", {}).get("resister", 0.0))])
		if bool(etat_colon.transgresse):
			lignes.append("t=%.1f TRANSGRESSION : %s execute l'ordre force (grief %.2f)" % [
				t, String(etat_colon.id), float(etat_colon.charge)])
	return lignes

static func ligne_trace(t: float, colon: Dictionary, colons: Array, config: Dictionary, catalogue_liens: Dictionary) -> String:
	var paires: Array = []
	for autre in colons:
		if String(autre.id) == String(colon.id):
			continue
		paires.append(_texte_sens(colon, autre, config, catalogue_liens))
	return "t=%.1f %s | %s | %s" % [t, String(colon.id), texte_etats(colon), "  ".join(paires)]

# ---------------------------------------------------------------------------
# Rendu (impur, Node) -- aucune decision, seulement des noeuds et des couleurs
# ---------------------------------------------------------------------------

# Les cles de couleur d'etat SONT les noms d'etat lus en donnee : une donnee
# qui renommerait les etats sans renommer les couleurs retombe sur 'neutre'
# plutot que de faire planter le rendu. Ce chemin n'est atteint que par la
# scene, jamais par un test headless.
func _couleur(cle: String) -> Color:
	var couleurs: Dictionary = _config.couleurs
	var rgb: Array = couleurs.get(cle, couleurs.neutre)
	return Color(float(rgb[0]), float(rgb[1]), float(rgb[2]))

# LA COULEUR DU COLON : le plus GRAVE gagne. seuil_etat.gd ne hierarchise
# jamais les etats entre eux (c'est ecrit dans son en-tete), c'est a
# l'appelant de choisir -- meme geste que banc_bonheur.gd:etat_dominant.
# 'transgresseur' passe devant tout : c'est le seul qui ne soit pas pose par
# un seuil de confiance mais par charge.gd, et le seul qui dise un acte.
func _cle_couleur(colon: Dictionary) -> String:
	if est_transgresseur(colon, _config):
		return "transgresseur"
	var actifs: Array = colon.proprietes.get("etats_actifs", [])
	# Du plus grave au moins grave, tous lus en donnee : rancune, puis le
	# second palier de confiance, puis le premier.
	for cle in ["etat_rancunier", "etat_confiant_obeir", "etat_confiant_combattre"]:
		if actifs.has(String(_config[cle])):
			return String(_config[cle])
	return "neutre"

func _creer_rendu() -> void:
	_noeuds[_menace.id] = _creer_carre(_menace.position, float(_config.taille_chose), _couleur("menace"))
	for id in _ouvrages:
		var ouvrage: Dictionary = _ouvrages[id]
		_noeuds[ouvrage.id] = _creer_carre(ouvrage.position, float(_config.taille_chose), _couleur("ouvrage"))

	# UNE ligne par paire NON ORDONNEE (six pour quatre colons) : deux lignes
	# superposees sur le meme segment seraient illisibles. Sa couleur est la
	# MOYENNE des deux sens ; le label, lui, porte les deux separement.
	for i in range(_colons.size()):
		for j in range(i + 1, _colons.size()):
			var cle := "%s|%s" % [String(_colons[i].id), String(_colons[j].id)]
			var ligne := Line2D.new()
			ligne.width = float(_config.largeur_ligne)
			ligne.default_color = _couleur("lien_nul")
			ligne.points = PackedVector2Array([
				Vector2(_colons[i].position.x, _colons[i].position.y),
				Vector2(_colons[j].position.x, _colons[j].position.y),
			])
			add_child(ligne)
			_lignes[cle] = ligne
			_labels_paires[cle] = _creer_label(int(_config.taille_police_paire))

	for colon in _colons:
		_noeuds[colon.id] = _creer_carre(colon.position, float(_config.taille_colon), _couleur("neutre"))
		_labels[colon.id] = _creer_label(int(_config.taille_police_label))

	_label_compteur = _creer_label_fixe(int(_config.taille_police_compteur), Vector2(10.0, 10.0))
	_label_aide = _creer_label_fixe(int(_config.taille_police_label), Vector2(10.0, 36.0))
	_label_aide.text = texte_aide(_config)

func _creer_carre(position: Vector3, taille: float, couleur: Color) -> ColorRect:
	var carre := ColorRect.new()
	carre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	carre.size = Vector2(taille, taille)
	carre.position = Vector2(position.x, position.y) - carre.size / 2.0
	carre.color = couleur
	add_child(carre)
	return carre

func _creer_label(taille: int) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", taille)
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	label.add_theme_constant_override("outline_size", 4)
	add_child(label)
	return label

func _creer_label_fixe(taille: int, position_ecran: Vector2) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", taille)
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	label.add_theme_constant_override("outline_size", 4)
	label.position = position_ecran
	_couche_ui.add_child(label)
	return label

func _rafraichir_tout() -> void:
	if _dernier_bilan.is_empty():
		_label_compteur.text = texte_compteur(_colons, _config, _mode, _ordre, _temps)
		return
	var par_id: Dictionary = {}
	for etat_colon in _dernier_bilan.colons:
		par_id[String(etat_colon.id)] = etat_colon

	for colon in _colons:
		var noeud: ColorRect = _noeuds[colon.id]
		noeud.color = _couleur(_cle_couleur(colon))
		_labels[colon.id].position = noeud.position + Vector2(float(_config.taille_colon) + 8.0, -10.0)
		_labels[colon.id].text = texte_colon(colon, par_id[String(colon.id)], _config)

	for i in range(_colons.size()):
		for j in range(i + 1, _colons.size()):
			var a: Dictionary = _colons[i]
			var b: Dictionary = _colons[j]
			var cle := "%s|%s" % [String(a.id), String(b.id)]
			var moyen: float = (score_net(a, String(b.id), _config, _catalogue_liens)
				+ score_net(b, String(a.id), _config, _catalogue_liens)) / 2.0
			_lignes[cle].default_color = _couleur_lien(moyen)
			var milieu := Vector2((a.position.x + b.position.x) / 2.0, (a.position.y + b.position.y) / 2.0)
			_labels_paires[cle].position = milieu
			_labels_paires[cle].text = texte_paire(a, b, _config, _catalogue_liens)

	_label_compteur.text = texte_compteur(_colons, _config, _mode, _ordre, _temps)

# Vert quand le net est positif, rouge quand il est negatif, gris a
# exactement zero -- « nul » et « faible » ne se disent pas pareil, et une
# interpolation qui passerait par le gris ferait disparaitre les liens
# faibles au lieu de les montrer faibles.
func _couleur_lien(net: float) -> Color:
	if net > 0.0:
		return _couleur("lien_positif")
	if net < 0.0:
		return _couleur("lien_negatif")
	return _couleur("lien_nul")

func _poser_camera() -> void:
	var decl: Dictionary = _config.get("camera", {})
	var pos: Array = decl.get("position", [0.0, 0.0])
	var camera := Camera2D.new()
	camera.position = Vector2(float(pos[0]), float(pos[1]))
	camera.zoom = Vector2(float(decl.get("zoom", 1.0)), float(decl.get("zoom", 1.0)))
	camera.enabled = true
	add_child(camera)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
