extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_affordances_choix.tscn, PAS la
# scene principale -- run/main_scene reste banc_p1). AUCUN MECANISME DU COEUR
# TOUCHE NI CREE : perception.gd, proximite.gd, dominance.gd, agir.gd,
# deformation.gd, couplage.gd et monde.gd sont appeles TELS QUELS.
#
# DEUX LIGNES DANS UN SEUL BANC, parce que c'est la MEME question posee deux
# fois : comment un colon tranche entre trois options, et a quelle CADENCE il
# retranche. Separees, l'une rendrait un score qu'on ne verrait jamais tenir,
# l'autre une horloge qui ne rythmerait rien.
#
# CE QU'ON DOIT VOIR. Un colon pose au centre, trois cibles autour : un REPAS
# loin (500 unites), un TAS DE BOIS tout pres (120), une FORGE a mi-distance
# (400). Rien ne bouge dans cette scene sauf ce que le colon PORTE. Rassasie et
# le bois proche, il ramasse le bois parce qu'il est PRES -- la forge, ou il a
# pourtant ses habitudes, ne pese pas assez. Clic DROIT : le bois s'eloigne de
# 160 unites et s'eteint presque, sa portee de saillance etant courte ; au
# prochain re-scoring le colon se tourne vers la forge, par HABITUDE. Clic
# GAUCHE : il a faim, son biais d'urgence monte pendant trois secondes, et au
# re-scoring suivant le repas -- la cible la plus lointaine et la moins
# saillante en soi -- ecrase tout, la forge SORT meme de la liste. Entre deux
# re-scorings, la barre blanche descend et RIEN ne change.
#
# ---------------------------------------------------------------------------
# LES TROIS POIDS D'UN CHOIX NE VIVENT PAS DANS UNE TABLE DE POIDS
# ---------------------------------------------------------------------------
# Aucun des elements qu'on attendrait n'existe sous cette forme, et aucun n'a
# ete cree :
#   - L'URGENCE EST une entree de data/deformations.json. C'est la SEULE voie
#     du depot qui fasse GAGNER une cible par un etat interne, parce que
#     deformation.gd indexe PAR PERCEVANT et que proximite.gd la lit
#     multiplicativement. Le « poids » est le DEBIT de pose x delta et le
#     PLAFOND -- les deux au cablage.
#   - LA DISTANCE N'EXISTE PAS COMME POIDS. proximite.gd applique une
#     attenuation LINEAIRE FIXE, clamp(1.0 - distance/portee) : pas d'exposant,
#     pas de coefficient. Le seul reglage est portee_saillance PAR PROFIL.
#     Peser la distance plus fort, c'est RACCOURCIR LA PORTEE, rien d'autre --
#     d'ou le couple 5.0/300.0 du bois contre 2.0/900.0 de la forge.
#   - L'HABITUDE est le MEME outil, deuxieme entree. Deux sources distinctes
#     sur deux cibles distinctes, que deformation.gd tient separement et que
#     proximite.gd compose EN SEQUENCE.
#   - LA DIVISION PAR UN COUT N'EXISTE NULLE PART. Rien ne divise une saillance
#     dans ce depot ; le plus proche serait une deformation de sens « baisse »,
#     non demandee ici et donc non ecrite.
#
# DEUX RESULTATS NEGATIFS DEJA PAYES AILLEURS, rappeles pour ne pas l'etre une
# fois de plus ici :
#   - poids_verbes NE PESE JAMAIS ENTRE DEUX CIBLES. agir.gd:choisir retient la
#     CIBLE au score (saillance + gain_inertie + engagement, poids_verbes n'y
#     entre pas), PUIS resout un verbe parmi ceux que la propriete gagnante
#     propose. Les trois verbes de ce banc portent donc le MEME poids : le
#     verbe affiche change parce que la CIBLE a change, jamais l'inverse.
#   - UN ETAT QUI MODULERAIT saillance_intrinseque VIA etat_effectif.gd NE
#     PRODUIT STRICTEMENT RIEN. proximite.gd lit ce nombre DANS le catalogue de
#     profils, jamais sur l'objet, et n'appelle JAMAIS etat_effectif.gd.
# ---------------------------------------------------------------------------
#
# LA CADENCE, ET CE QU'ELLE COUTE. Le re-scoring ne tourne qu'a
# cadence_scoring_s, jamais a chaque tick ; l'echeance est gardee HORS de
# proprietes, au meme rang qu'action_en_cours, parce qu'elle change a chaque
# tick et n'est pas un fait stable de l'objet (docs/design.md). CE N'EST PAS
# UNE OPTIMISATION NEUTRE, et le banc le montre plutot que de le taire : entre
# deux re-scorings le colon est AVEUGLE -- on peut lui rapprocher le bois,
# l'affamer, tout changer, il ne s'en apercevra qu'a l'echeance. C'est un
# changement de COMPORTEMENT, assume.
#
# QUATRE MECANISMES TIENNENT LA DECISION ENTRE DEUX RE-SCORINGS, pas un :
#   (1) LE FAIT DE NE PAS RESCORER : la decision precedente est CONSERVEE,
#       rien n'est recalcule, donc rien ne peut basculer.
#   (2) gain_inertie : bonus ADDITIF a la tache en cours AVANT comparaison, une
#       preference de PERSONNALITE. A tache egale elle gagne ; il faut une
#       saillance strictement superieure pour en sortir.
#   (3) couplage.gd : bonus additif de plus, jamais un remplacement -- un FAIT
#       PHYSIQUE, pose par PRESENCE et retire par ABSENCE. Les deux coexistent
#       sans se confondre.
#   (4) le poids d'avancement de proximite.gd, PRESENT et MESURABLEMENT NEUTRE
#       ici : chaque cible porte travail_restant == travail_initial, le facteur
#       vaut donc exactement 1.000. Il est la parce que couplage.gd a besoin de
#       travail_restant pour sa satisfaction, pas pour decorer -- et le test
#       verrouille sa neutralite plutot que de la supposer.
#
# 'actions_gardees' N'EXISTE PAS, ET C'EST UNE DECISION DOCTRINALE, PAS UN
# OUBLI : c'est une FILE DE PLAN, et elle tombe sous deux des quatre griefs qui
# ont fait rejeter BDI (docs/design.md, Contraintes structurelles -- exige des
# plans pre-ecrits, defend l'intention contre la distraction). ABANDONNEE. Ce
# banc ne porte AUCUNE file, AUCUNE liste d'actions futures : a chaque
# re-scoring, les quatre couches repartent de zero sur le monde tel qu'il est.
# 'sur_changement' N'EXISTE PAS NON PLUS et n'est pas cree : aucun drapeau de
# mutation, aucun bus d'evenement nulle part dans le depot, et la cadence rend
# la question sans objet.
# Verrouille NEGATIVEMENT par test, qui relit ce fichier sur le disque -- et le
# verrou cherche une FORME DE CODE, jamais un mot : les deux noms DOIVENT etre
# nommes ici, sans quoi le verrou interdirait d'expliquer pourquoi on ne les a
# pas ecrits.
#
# LE CATALOGUE D'ENGAGEMENT EST LOCAL AU BANC, jamais une entree ajoutee au
# catalogue partage : couplage.gd recoit son catalogue en PARAMETRE. Raison :
# le poids y est calibre sur les saillances DE CE BANC (0.5 face a des scores
# de 0.3 a 5.0), la ou l'entree partagee porte 5.0 -- la reutiliser aurait
# rendu l'engagement indelogeable et l'urgence inobservable.
#
# L'ENGAGEMENT NE SE SATISFAIT JAMAIS ICI, et c'est voulu : sa regle se
# satisfait sous un seuil de travail_restant, chaque cible porte
# travail_restant == travail_initial > 0, et extinction.gd N'EST PAS CABLE --
# personne ne travaille. Il ne se relache donc que par l'ABSENCE (cible hors de
# portee, Couplage.avancer recoit null) ou par le retrait explicite du cablage
# quand la decision change de cible malgre lui, geste que agir.gd reclame
# nommement. C'est la doctrine meme de couplage.gd : pose par presence, retire
# par absence, jamais par choix.
#
# LE COLON NE SE DEPLACE PAS, meme decoupage que banc_marche_competence.gd et
# banc_temps_anticipation.gd. Un colon qui marche change LUI-MEME les
# distances, donc les saillances, donc l'arbitrage : « la distance avantage le
# bois proche » serait vrai une seconde puis faux, et la calibration ne serait
# verifiable a aucun instant precis. Le sujet est le SCORE, pas le trajet. On
# voit le colon CHOISIR, on ne le voit pas aller.
#
# AUCUNE DEPENSE, AUCUN METABOLISME : depense.gd n'est pas appele, la reserve
# n'est ecrite QUE par le clic. Une reserve qui descendrait toute seule rendrait
# l'etat de depart intenable en quelques secondes et le banc ne montrerait plus
# qu'un colon qui mange en boucle. Le cycle de la faim est deja montre ailleurs.
#
# LE SCORE AFFICHE EST UNE RECOMPOSITION, ET IL EST VERROUILLE COMME TELLE.
# agir.gd:_score est prive et choisir() ne rend pas le nombre qu'il a compare :
# il n'existe aucune voie pour l'afficher sans le recomposer. score_visible()
# refait donc la MEME somme, et le test exige que l'argmax de cette
# recomposition soit EXACTEMENT la cible que Agir.choisir a retenue, dans les
# trois etats du banc. Une divergence future de agir.gd:_score fera donc rougir
# ce banc au lieu de mentir en silence a l'ecran. C'est le seul endroit ou une
# arithmetique du coeur est redite, et il est signale plutot que masque.
#
# COLON ET CIBLES CONSTRUITS A LA MAIN (pas Objet.fabriquer) : ni composition
# ni materiau, donc data/types.json n'est PAS touche et rien n'est a enregistrer
# dans test_lint_donnees.gd. Le colon ne porte PAS "attaches" : attaches.gd
# n'est pas appele ici, et poser une cle que personne ne lit serait de la donnee
# morte. Si un chantier futur branche attaches.gd, son alarme structurelle le
# dira.
#
# ECART A LA CONSIGNE, ASSUME : elle annoncait trois deformations (urgence,
# distance, habitude), puis sa propre correction etablissait que la distance
# n'en est pas une. DEUX entrees ont donc ete ecrites, pas trois -- la
# troisieme « pesee » est la portee de profil, qui ne vit ni dans le catalogue
# de deformations ni sur le colon.
#
# Deux moities, meme decoupage que les autres bancs : le Node charge, construit
# et affiche, et ses deux bascules ne calculent jamais rien ; tout le reste est
# en fonctions statiques pures. LE TICK N'EST JAMAIS RECONSTITUE DANS LE TEST :
# il appelle avancer_tick, la MEME fonction que _process (CLAUDE.md, Regle
# d'etat).
#
# AUCUN NOM DE PROPRIETE, DE SOURCE NI DE VERBE EN DUR : tous arrivent de
# data/banc_affordances_choix.json -- c'est ce qui permet au test de faire
# traverser le meme code par un domaine entierement invente.

const Perception = preload("res://scripts/perception.gd")
const Proximite = preload("res://scripts/proximite.gd")
const Dominance = preload("res://scripts/dominance.gd")
const Agir = preload("res://scripts/agir.gd")
const Deformation = preload("res://scripts/deformation.gd")
const Couplage = preload("res://scripts/couplage.gd")
const Monde = preload("res://scripts/monde.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")

# Les trois cles de CABLAGE posees sur le colon HORS de proprietes, au meme rang
# qu'action_en_cours : elles changent a chaque tick, ce ne sont pas des faits
# stables de l'objet (docs/design.md, « action_en_cours vit hors de
# proprietes »). Patron exact : banc_croyance.gd, qui garde 'prochaine_observation'
# et 'cadence_observation' au meme endroit et pour la meme raison.
const CLE_CADENCE := "cadence_scoring"
const CLE_ECHEANCE := "prochain_scoring"
const CLE_DECISION := "decision_en_cours"
# CE QUE dominance.gd A LAISSE PASSER au dernier re-scoring, garde pour que
# l'ecran ne CLIGNOTE PAS entre deux echeances : sans lui, une cible ecrasee
# redeviendrait « visible » a chaque tick sans re-scoring, et le carre grise
# battrait au rythme de la cadence. N'EST PAS UNE FILE DE PLAN (voir en-tete,
# « actions_gardees ») : c'est le compte rendu d'une lecture DEJA FAITE, jamais
# une liste d'actions a venir -- il ne pese sur aucune decision, seul
# l'affichage et la trace le relisent.
const CLE_VISIBLES := "visibles_au_dernier_scoring"

var _config: Dictionary = {}
var _catalogue_canaux: Dictionary = {}
var _profils_saillance: Dictionary = {}
var _catalogue_deformations: Dictionary = {}
var _catalogue_actions: Dictionary = {}

var _colon: Dictionary = {}
var _cibles: Array = []
var _monde
var _temps := 0.0
var _affame := false
var _eloigne := false
var _infos: Dictionary = {}

var _labels: Dictionary = {}
var _label_colon: Label
var _label_entete: Label
var _label_aide: Label

func _ready() -> void:
	_config = _charger_json("res://data/banc_affordances_choix.json")
	_catalogue_canaux = _charger_json("res://data/canaux.json")
	_profils_saillance = _charger_json("res://data/profils_saillance.json")
	_catalogue_deformations = _charger_json("res://data/deformations.json")

	# Catalogue d'actions PARTAGE, complete par le vocabulaire propre au banc
	# (exception banc-jetable, patron banc_charge.gd/banc_psycho_social.gd) --
	# data/types_choses.json n'est jamais touche sur le disque.
	_catalogue_actions = _charger_json("res://data/types_choses.json")
	var local: Dictionary = _config.get("catalogue_local", {})
	for cle in local:
		if String(cle).begins_with("_"):
			continue
		_catalogue_actions[cle] = local[cle]

	_colon = construire_colon(_config)
	_cibles = construire_cibles(_config)
	_reconstruire_monde()
	_construire_rendu()
	print(ligne_pose(_config))

func _unhandled_input(evenement: InputEvent) -> void:
	# Le clic ne fait que basculer un etat : aucune decision, aucun calcul.
	if not (evenement is InputEventMouseButton and evenement.pressed):
		return
	if evenement.button_index == MOUSE_BUTTON_LEFT:
		_affame = basculer_faim(_colon, _config, _affame)
		print(ligne_bascule_faim(_temps, _affame, _config))
	elif evenement.button_index == MOUSE_BUTTON_RIGHT:
		_eloigne = basculer_distance(_cibles, _config, _eloigne)
		print(ligne_bascule_distance(_temps, _colon, _cibles, _config, _eloigne))

func _process(delta: float) -> void:
	_temps += delta
	_infos = avancer_tick(
		_colon, _monde, _cibles, delta, _temps, _config,
		_catalogue_canaux, _profils_saillance, _catalogue_deformations, _catalogue_actions)
	for ligne in lignes_trace(_temps, _colon, _infos, _config):
		print(ligne)
	_rafraichir()
	queue_redraw()

# ---- Fonctions PURES, testables headless ----

# UN TICK COMPLET, l'ordre compris. Statique et sans noeud : le test rejoue
# EXACTEMENT ce que la scene execute, jamais une reconstitution parallele qui
# pourrait deriver. MUTE le colon en place ; rend tout ce que l'affichage et la
# console relisent, jamais recalcule ailleurs.
#
# L'ORDRE N'EST PAS LIBRE, quatre contraintes le fixent :
#   (1) POSER AVANT AVANCER pour les deformations -- une exposition de CE tick
#       doit compter avant la decroissance de CE tick, sinon le biais frais est
#       rabote avant d'avoir servi (patron banc_psycho_social.gd/
#       banc_marche_competence.gd).
#   (2) LES DEFORMATIONS A CHAQUE TICK, LE RE-SCORING A LA CADENCE. C'est le
#       sujet de la ligne 12 : le monde interne du colon evolue en continu, sa
#       DECISION se reprend par a-coups. Cadencer aussi les deformations
#       reviendrait a geler son corps entre deux pensees.
#   (3) Couplage.avancer AVANT le re-scoring -- l'arrachement par absence doit
#       etre constate avant que agir.gd ne reinjecte la cible engagee ; sinon
#       une cible sortie de portee peserait encore pour un tick.
#   (4) Les lectures de saillance EN DERNIER, apres la deformation de ce tick --
#       sinon l'ecran montrerait toujours le biais du tick precedent.
static func avancer_tick(
	colon: Dictionary,
	monde,
	cibles: Array,
	delta: float,
	temps: float,
	config: Dictionary,
	catalogue_canaux: Dictionary,
	profils_saillance: Dictionary,
	catalogue_deformations: Dictionary,
	catalogue_actions: Dictionary,
) -> Dictionary:
	# (1) et (2)
	var urgence: float = urgence_faim(colon, config)
	var magnitudes: Dictionary = poser_deformations(colon, urgence, delta, config, catalogue_deformations)
	Deformation.avancer(colon, delta, catalogue_deformations)

	# (3)
	var issue_engagement: String = avancer_engagement(colon, monde, delta, config)

	# Le re-scoring, a la cadence et a elle seule.
	var avant: Dictionary = colon.get(CLE_DECISION, {}).duplicate()
	var scoring: Dictionary = rescorer_si_cadence(
		colon, monde, temps, config, catalogue_canaux, profils_saillance,
		catalogue_deformations, catalogue_actions)
	var a_rescore: bool = bool(scoring.get("rescore", false))
	if a_rescore:
		gerer_engagement(colon, monde, config)
	var apres: Dictionary = colon.get(CLE_DECISION, {})
	var change: bool = a_rescore and String(avant.get("cible_id", "")) != String(apres.get("cible_id", ""))

	# (4)
	var perceptions: Array = Perception.percevoir(colon, monde, catalogue_canaux)
	return {
		"urgence": urgence,
		"magnitudes": magnitudes,
		"biais_urgence": Deformation.biais(
			colon, String(config.source_deformation_urgence),
			String(config.cible_deformation_urgence), catalogue_deformations),
		"biais_habitude": Deformation.biais(
			colon, String(config.source_deformation_habitude),
			String(config.cible_deformation_habitude), catalogue_deformations),
		"issue_engagement": issue_engagement,
		"rescore": a_rescore,
		"change": change,
		"decision_avant": avant,
		"decision": apres,
		"visibles_ids": colon.get(CLE_VISIBLES, []),
		"saillances": saillances_par_cible(perceptions, colon, cibles, profils_saillance, catalogue_deformations),
		"restant_cadence": max(0.0, float(colon.get(CLE_ECHEANCE, 0.0)) - temps),
	}

# ---- Construction de la scene ----

# Le colon ne porte NI composition NI materiau NI 'attaches' (voir en-tete). Les
# cinq proprietes STRUCTURELLES que les mecanismes appeles exigent sont posees
# ici, et rien d'autre : 'forme' (dominance.gd + agir.gd), 'poids_verbes'
# (agir.gd), 'canaux' (perception.gd), 'deformation_sources'/'deformation_etat'
# (deformation.gd), 'engagement' a null (couplage.gd). 'reserves' est lue par ce
# seul cablage (l'urgence), depense.gd n'est jamais appele.
# duplicate(true) sur tout ce qui vient du disque -- jamais partage avec le
# Dictionary charge, meme precaution d'aliasing que banc_bonheur.gd et
# banc_marche_competence.gd.
static func construire_colon(config: Dictionary) -> Dictionary:
	var decl: Dictionary = config.colon
	var pos: Array = decl.position
	var reserves: Dictionary = {}
	reserves[String(config.nom_reserve_energie)] = {
		"reserve": float(config.energie_rassasie),
		"cout_base": 0.0,
		"surcout_action": 0.0,
	}
	var canaux_config: Dictionary = {}
	for nom_canal in config.get("canaux", []):
		canaux_config[String(nom_canal)] = {"portee": float(decl.portee_vue), "angle": 360.0}
	var proprietes: Dictionary = {
		"reserves": reserves,
		"canaux": config.canaux.duplicate(true),
		"canaux_config": canaux_config,
		"deformation_sources": config.deformation_sources.duplicate(true),
		"deformation_etat": {},
		"engagement": null,
		"forme": _sans_notes(decl.forme),
		"poids_verbes": _sans_notes(decl.poids_verbes),
	}
	# LE PLI D'ATELIER EST UNE DONNEE PAR COLON, jamais une constante du cablage
	# (patron biais_combat_base de banc_psycho_social.gd, plancher_competence de
	# banc_marche_competence.gd) : un colon a pli NUL ne pose aucune deformation
	# d'habitude, et la forge lui arrive inchangee -- meme arithmetique lue a zero.
	proprietes[String(config.nom_pli_atelier)] = float(decl.get("pli_atelier", 0.0))
	return {
		"id": String(decl.id),
		"position": Vector3(float(pos[0]), float(pos[1]), float(pos[2])),
		"proprietes": proprietes,
		"action_en_cours": {},
		CLE_CADENCE: float(config.cadence_scoring_s),
		CLE_ECHEANCE: 0.0,
		CLE_DECISION: {},
		CLE_VISIBLES: [],
	}

# Chaque cible porte SA propriete actionnable, SA reference de profil de
# saillance, et le couple travail_restant/travail_initial (voir en-tete : lu par
# couplage.gd pour la satisfaction, et par proximite.gd:_poids_avancement, ou il
# vaut exactement 1.000 puisque rien ne l'avance). Ce fichier ne nomme aucune des
# trois : tout vient de la declaration.
static func construire_cibles(config: Dictionary) -> Array:
	var cibles: Array = []
	for decl in config.get("cibles", []):
		var pos: Array = decl.position
		var proprietes: Dictionary = _sans_notes(decl.proprietes)
		var travail: float = float(decl.get("travail", 0.0))
		proprietes["travail_restant"] = travail
		proprietes["travail_initial"] = travail
		cibles.append({
			"id": String(decl.id),
			"position": Vector3(float(pos[0]), float(pos[1]), float(pos[2])),
			"proprietes": proprietes,
		})
	return cibles

# Recopie un Dictionary de donnee en laissant tomber les cles de commentaire --
# un '_note' recopie sur un objet du monde deviendrait une propriete que
# agir.gd:_action scannerait et que le linter compterait, alors que ce n'est
# qu'un texte (meme convention que test_lint_donnees.gd, qui ignore toute cle
# commencant par '_').
static func _sans_notes(source: Dictionary) -> Dictionary:
	var sortie: Dictionary = {}
	for cle in source:
		if String(cle).begins_with("_"):
			continue
		var valeur = source[cle]
		if valeur is Dictionary or valeur is Array:
			valeur = valeur.duplicate(true)
		sortie[String(cle)] = valeur
	return sortie

static func cible_par_id(cibles: Array, id: String) -> Dictionary:
	for cible in cibles:
		if String(cible.id) == id:
			return cible
	return {}

# ---- LIGNE 11 : les deux deformations ----

# L'URGENCE, lue sur la reserve et rien d'autre : (capacite - reserve)/capacite,
# bornee a [0,1]. LINEAIRE ET NON SIGMOIDE, deliberement -- banc_psycho_social.gd
# porte deja la sigmoide et la courbe qui va avec ; ce qui doit se voir ICI est
# l'ARBITRAGE entre trois cibles, pas la forme de la montee du besoin. Capacite
# nulle ou negative (config incoherente) : 0.0, jamais une division par zero.
static func urgence_faim(colon: Dictionary, config: Dictionary) -> float:
	var capacite: float = float(config.capacite_energie)
	if capacite <= 0.0:
		return 0.0
	var canal: Dictionary = colon.proprietes.get("reserves", {}).get(String(config.nom_reserve_energie), {})
	return clamp((capacite - float(canal.get("reserve", 0.0))) / capacite, 0.0, 1.0)

# LES DEUX SOURCES, posees d'un meme geste. Rend les magnitudes reellement
# posees, pour l'affichage.
static func poser_deformations(
	colon: Dictionary,
	urgence: float,
	delta: float,
	config: Dictionary,
	catalogue_deformations: Dictionary,
) -> Dictionary:
	var pli: float = float(colon.proprietes.get(String(config.nom_pli_atelier), 0.0))
	return {
		"urgence": _poser_une_deformation(
			colon, String(config.source_deformation_urgence), String(config.cible_deformation_urgence),
			float(config.gain_deformation_urgence_par_s) * urgence * delta,
			float(config.plafond_biais_urgence), catalogue_deformations),
		"habitude": _poser_une_deformation(
			colon, String(config.source_deformation_habitude), String(config.cible_deformation_habitude),
			float(config.gain_deformation_habitude_par_s) * pli * delta,
			float(config.plafond_biais_habitude), catalogue_deformations),
	}

# MAGNITUDE NULLE : rien n'est pose du tout, et ce n'est pas une optimisation --
# c'est ce qui garde VIDE le deformation_etat d'un colon rassasie ou sans pli.
# Une entree posee a 0.0 ferait quand meme exister le couple [source][cible], et
# « il n'a aucune deformation » deviendrait faux tout en restant sans effet
# visible. MULTIPLIEE PAR delta cote appelant : poser() n'a AUCUN parametre de
# temps. PLAFOND AU CABLAGE : deformation.gd n'a aucune borne haute et decroit
# par SOUSTRACTION FIXE -- il n'existe AUCUN equilibre naturel, le registre
# monterait LINEAIREMENT ET SANS BORNE (resultat negatif mesure cinq fois, voir
# data/deformations.json). Passe par poser(), jamais par une ecriture directe
# dans deformation_etat : poser() refuse (push_error) toute source non declaree
# dans deformation_sources, garde qu'une ecriture a la main contournerait.
static func _poser_une_deformation(
	colon: Dictionary,
	source: String,
	cible: String,
	magnitude: float,
	plafond: float,
	catalogue_deformations: Dictionary,
) -> float:
	if magnitude <= 0.0:
		return 0.0
	if Deformation.biais(colon, source, cible, catalogue_deformations) >= plafond:
		return 0.0
	Deformation.poser(colon, source, cible, magnitude)
	return magnitude

# ---- LIGNE 12 : la cadence, la decision, l'engagement ----

# LES QUATRE COUCHES, mais SEULEMENT a l'echeance. Patron LITTERAL de
# banc_croyance.gd:observer_si_cadence -- meme garde en tete, meme echeance
# gardee hors de proprietes, meme rearmement immediat. Avant l'echeance : rien
# n'est calcule, rien n'est mute, la decision precedente reste telle quelle.
# Rend { rescore } ; la decision ET ce que dominance.gd a laisse passer vivent
# sur le colon (CLE_DECISION / CLE_VISIBLES), pour survivre aux ticks sans
# re-scoring -- sinon l'ecran perdrait l'un et l'autre entre deux echeances.
static func rescorer_si_cadence(
	colon: Dictionary,
	monde,
	temps: float,
	config: Dictionary,
	catalogue_canaux: Dictionary,
	profils_saillance: Dictionary,
	catalogue_deformations: Dictionary,
	catalogue_actions: Dictionary,
) -> Dictionary:
	if temps < float(colon.get(CLE_ECHEANCE, 0.0)):
		return {"rescore": false}
	colon[CLE_ECHEANCE] = temps + float(colon.get(CLE_CADENCE, 0.0))
	var r: Dictionary = decider(colon, monde, config, catalogue_canaux, profils_saillance,
		catalogue_deformations, catalogue_actions)
	# LE RESUME AVANT LA MEMORISATION, ET L'ORDRE N'EST PAS LIBRE -- DEFAUT REEL
	# TROUVE EN LANCANT LA SCENE, invisible au test d'argmax : ecrit dans l'autre
	# sens, action_en_cours portait DEJA la decision fraiche au moment ou
	# score_visible la relisait, et le score affiche au TOUT PREMIER re-scoring
	# valait 3.250 la ou agir.gd avait compare 3.000 -- une inertie appliquee
	# retroactivement a une tache qui venait de naitre. Le resume doit lire l'etat
	# EXACT que agir.gd a lu.
	colon[CLE_DECISION] = resume_decision(r.decision, r.visibles, colon, config)
	colon.action_en_cours = Agir.etat_courant(r.decision)
	var ids: Array = []
	for v in r.visibles:
		var chose = v.get("chose", null)
		if chose is Dictionary:
			ids.append(String(chose.get("id", "")))
	colon[CLE_VISIBLES] = ids
	return {"rescore": true}

# LES QUATRE COUCHES, dans l'ordre et sans une ligne d'ecart : perception.gd ->
# proximite.gd (qui applique lui-meme les deux biais, ce fichier ne les
# reapplique JAMAIS) -> dominance.gd -> agir.gd. attaches.gd et jugement.gd ne
# sont PAS montes : ce banc n'a ni attache ni propriete jugee, et les appeler
# aurait demande de poser sur le colon des cles structurelles que personne
# n'aurait lues. Rend { perceptions, resultats, visibles, decision }, meme forme
# que banc_feu.gd:decider / banc_psycho_social.gd:decider.
static func decider(
	colon: Dictionary,
	monde,
	config: Dictionary,
	catalogue_canaux: Dictionary,
	profils_saillance: Dictionary,
	catalogue_deformations: Dictionary,
	catalogue_actions: Dictionary,
) -> Dictionary:
	var perceptions: Array = Perception.percevoir(colon, monde, catalogue_canaux)
	var resultats: Array = Proximite.evaluer(perceptions, colon, profils_saillance, catalogue_deformations)
	var visibles: Array = Dominance.visibles(resultats, colon)
	var decision = Agir.choisir(visibles, colon, catalogue_actions, monde)
	return {"perceptions": perceptions, "resultats": resultats, "visibles": visibles, "decision": decision}

# CE QUI SURVIT D'UN RE-SCORING AU SUIVANT, et rien de plus : un id, un verbe,
# un nombre. JAMAIS la chose elle-meme -- une reference d'objet gardee ici
# survivrait a une reconstruction du Monde et pointerait vers un fantome, et
# elle sortirait de la resumabilite JSON stricte (docs/design.md). Ce n'est PAS
# une file de plan : c'est UNE decision, celle du dernier re-scoring, ecrasee au
# suivant -- voir en-tete, « actions_gardees n'existe pas ».
static func resume_decision(decision, visibles: Array, colon: Dictionary, config: Dictionary) -> Dictionary:
	if decision == null:
		return {}
	var chose = decision.get("chose", null)
	return {
		"cible_id": String(chose.get("id", "")) if chose is Dictionary else "",
		"verbe": String(decision.get("action", "")),
		"saillance": float(decision.get("saillance", 0.0)),
		"score": score_visible(decision, colon),
	}

# RECOMPOSITION D'AFFICHAGE, jamais la decision -- voir en-tete, « LE SCORE
# AFFICHE EST UNE RECOMPOSITION ». Refait la somme de agir.gd:_score (prive, et
# choisir() ne rend pas le nombre compare) : saillance + gain_inertie si la
# tache est la meme + poids d'engagement si l'id correspond. Le test exige que
# l'argmax de cette fonction soit EXACTEMENT la cible retenue par Agir.choisir,
# dans les trois etats du banc -- une divergence future fera rougir le banc au
# lieu de mentir a l'ecran.
static func score_visible(visible: Dictionary, colon: Dictionary) -> float:
	var proprietes: Dictionary = colon.get("proprietes", {})
	var score: float = float(visible.get("saillance", 0.0))
	var identite = _identifiant(visible)
	var en_cours: Dictionary = colon.get("action_en_cours", {})
	var id_en_cours = en_cours.get("id", null)
	if id_en_cours != null:
		if identite == id_en_cours:
			score += float(proprietes.get("forme", {}).get("gain_inertie", 0.0))
	elif String(visible.get("type", "")) == String(en_cours.get("type", "")) and en_cours.has("type"):
		score += float(proprietes.get("forme", {}).get("gain_inertie", 0.0))
	var engagement = proprietes.get("engagement", null)
	if engagement != null and identite == engagement.get("cible_id", null):
		score += float(engagement.get("poids", 0.0))
	return score

static func _identifiant(visible: Dictionary):
	var chose = visible.get("chose", null)
	if chose is Dictionary:
		return chose.get("id", null)
	return null

static func a_portee_engagement(colon: Dictionary, chose: Dictionary, config: Dictionary) -> bool:
	if chose.is_empty():
		return false
	return colon.position.distance_to(chose.position) <= float(config.portee_engagement)

# L'ENGAGEMENT AVANCE A CHAQUE TICK, jamais a la cadence : c'est un FAIT
# PHYSIQUE, pas une pensee. La cible est passee a Couplage.avancer SEULEMENT si
# elle est encore a portee -- sinon null, et le mecanisme rend « arrache » et
# remet l'engagement a null lui-meme. C'est litteralement « se retire par
# absence » (couplage.gd, en-tete). Rend l'issue rendue par le mecanisme, pour
# la trace.
static func avancer_engagement(colon: Dictionary, monde, delta: float, config: Dictionary) -> String:
	var engagement = colon.proprietes.get("engagement", null)
	if engagement == null:
		return "vide"
	var wrapper = monde.par_id(engagement.get("cible_id", ""))
	var cible = null
	if wrapper != null and a_portee_engagement(colon, wrapper.chose, config):
		cible = wrapper.chose
	return Couplage.avancer(colon, cible, delta, config.engagements_locaux)

# APRES le re-scoring, et seulement la : deux gestes distincts, jamais un seul.
# (a) LE RETRAIT que agir.gd reclame nommement dans son en-tete -- « c'est au
#     cablage de banc de detecter que la decision a change de cible malgre
#     l'engagement et d'appeler Couplage.retirer en consequence ». Sans lui, un
#     colon parti manger resterait couple au bois qu'il a quitte, et le poids
#     d'engagement le ramenerait au re-scoring suivant : une oscillation a deux
#     temps, invisible tant qu'on ne regarde pas deux echeances de suite.
# (b) LA POSE PAR PRESENCE : la nouvelle cible ne recoit un engagement que si
#     elle est a 'portee_engagement'. Le repas de ce banc est a 500 unites pour
#     une portee de 450 : un colon parti manger n'est couple a RIEN, et c'est
#     exactement ce que « se pose par presence » veut dire.
static func gerer_engagement(colon: Dictionary, monde, config: Dictionary) -> void:
	var cible_id := String(colon.get(CLE_DECISION, {}).get("cible_id", ""))
	var engagement = colon.proprietes.get("engagement", null)
	if engagement != null and String(engagement.get("cible_id", "")) != cible_id:
		Couplage.retirer(colon, "la decision a change de cible malgre l'engagement")
		engagement = null
	if engagement != null or cible_id == "":
		return
	var wrapper = monde.par_id(cible_id)
	if wrapper == null:
		return
	if not a_portee_engagement(colon, wrapper.chose, config):
		return
	Couplage.poser(colon, wrapper.chose, String(config.regle_engagement), config.engagements_locaux)

# ---- Lectures (elles ne calculent aucun etat, elles le racontent) ----

# La saillance de chaque cible, DEUX FOIS : telle que CE colon la voit (biais
# compris) et telle qu'un lecteur SANS deformation la verrait, aux memes
# distances et par le MEME mecanisme. Passe par Proximite.evaluer -- jamais une
# reimplementation de son arithmetique (poids x facteur de distance x
# avancement, puis composition multiplicative des biais) : une copie locale
# deriverait du mecanisme sans que rien ne rougisse.
static func saillances_par_cible(
	perceptions: Array,
	colon: Dictionary,
	cibles: Array,
	profils_saillance: Dictionary,
	catalogue_deformations: Dictionary,
) -> Dictionary:
	var vues: Dictionary = _saillances(perceptions, colon, profils_saillance, catalogue_deformations)
	var nues: Dictionary = _saillances(perceptions, lecteur_sans_deformation(), profils_saillance, catalogue_deformations)
	var sortie: Dictionary = {}
	for cible in cibles:
		var id := String(cible.id)
		sortie[id] = {
			"saillance": float(vues.get(id, 0.0)),
			"nue": float(nues.get(id, 0.0)),
			"distance": colon.position.distance_to(cible.position),
		}
	return sortie

static func _saillances(
	perceptions: Array,
	lecteur: Dictionary,
	profils_saillance: Dictionary,
	catalogue_deformations: Dictionary,
) -> Dictionary:
	var par_id: Dictionary = {}
	for entree in Proximite.evaluer(perceptions, lecteur, profils_saillance, catalogue_deformations):
		par_id[String(entree.chose.get("id", ""))] = float(entree.saillance)
	return par_id

# Le TEMOIN : un lecteur reduit a un deformation_etat vide, pour obtenir la
# saillance NUE des memes choses, aux memes distances, par le MEME mecanisme.
# proximite.gd ne lit rien d'autre du colon (deformation_etat y est FACULTATIVE)
# -- c'est la seule facon de mesurer l'effet des deux biais sans recalculer la
# saillance a la main. Patron exact banc_marche_competence.gd.
static func lecteur_sans_deformation() -> Dictionary:
	return {"proprietes": {"deformation_etat": {}}}

# ---- Bascules (pures) ----

# ECRIT LA RESERVE, jamais un etat pose : c'est la reserve qui porte l'urgence,
# et l'urgence qui pilote la magnitude posee. Rend le nouvel etat (true =
# affame). Le biais, lui, ne bascule PAS avec le clic -- il monte et redescend
# en quelques secondes, et c'est ce delai qui rend la ligne 12 visible : le clic
# ne change pas la decision, il change ce que le prochain re-scoring lira.
static func basculer_faim(colon: Dictionary, config: Dictionary, affame_avant: bool) -> bool:
	var canal: Dictionary = colon.proprietes.get("reserves", {}).get(String(config.nom_reserve_energie), {})
	if canal.is_empty():
		push_error("banc_affordances_choix : canal de reserve '%s' absent du colon, faim non basculee"
			% String(config.nom_reserve_energie))
		return affame_avant
	canal["reserve"] = float(config.energie_rassasie) if affame_avant else float(config.energie_affame)
	return not affame_avant

# MUTE chose.position en place : monde.gd relit toujours la position VIVANTE
# (son en-tete : « l'argument position n'est PAS stocke »), il n'y a rien a
# re-enregistrer et le Monde n'est jamais reconstruit. Patron exact
# banc_croyance.gd:basculer_feu. Rend le nouvel etat (true = eloigne).
static func basculer_distance(cibles: Array, config: Dictionary, eloigne_avant: bool) -> bool:
	var id := String(config.cible_distance)
	var cible := cible_par_id(cibles, id)
	if cible.is_empty():
		push_error("banc_affordances_choix : cible de distance '%s' absente de la scene" % id)
		return eloigne_avant
	var decl: Dictionary = {}
	for d in config.get("cibles", []):
		if String(d.id) == id:
			decl = d
			break
	var pos: Array = decl.position if eloigne_avant else decl.position_alternee
	cible["position"] = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	return not eloigne_avant

# ---- Textes (purs -- aucun nombre n'y est recalcule) ----

static func ligne_pose(config: Dictionary) -> String:
	return ("t=0.0 banc pose -- cadence de re-scoring %.1f s, portee d'engagement %.0f, " +
		"gain_inertie %.2f, seuil_ecrasement %.2f ; plafonds de biais : urgence %.1f, habitude %.1f") % [
		float(config.cadence_scoring_s), float(config.portee_engagement),
		float(config.colon.forme.gain_inertie), float(config.colon.forme.seuil_ecrasement),
		float(config.plafond_biais_urgence), float(config.plafond_biais_habitude),
	]

static func ligne_bascule_faim(temps: float, affame: bool, config: Dictionary) -> String:
	return "t=%.1f FAIM : %s (reserve %.0f / %.0f) -- le biais met quelques secondes a suivre" % [
		temps, "AFFAME" if affame else "RASSASIE",
		float(config.energie_affame) if affame else float(config.energie_rassasie),
		float(config.capacite_energie),
	]

static func ligne_bascule_distance(temps: float, colon: Dictionary, cibles: Array, config: Dictionary, eloigne: bool) -> String:
	var cible := cible_par_id(cibles, String(config.cible_distance))
	var d: float = colon.position.distance_to(cible.position) if not cible.is_empty() else 0.0
	return "t=%.1f DISTANCE : '%s' %s, a %.0f unites du colon" % [
		temps, String(config.cible_distance), "ELOIGNE" if eloigne else "RAPPROCHE", d,
	]

# DEUX TRACES DISTINCTES, jamais fondues en une : le RE-SCORING (il a eu lieu,
# voici ce qu'il a lu) et le CHANGEMENT DE DECISION (il a produit autre chose
# que la fois d'avant). Un re-scoring qui ne change rien est exactement ce que
# la ligne 12 existe pour montrer -- il doit se voir, pas se taire.
static func lignes_trace(temps: float, colon: Dictionary, infos: Dictionary, config: Dictionary) -> Array:
	var lignes: Array = []
	if not bool(infos.get("rescore", false)):
		return lignes
	var d: Dictionary = infos.get("decision", {})
	var morceaux: Array = []
	for id in infos.get("saillances", {}):
		var s: Dictionary = infos.saillances[id]
		var marque := ""
		if not infos.get("visibles_ids", []).has(String(id)):
			marque = " [ECRASEE]"
		morceaux.append("%s %.3f (nue %.3f, d=%.0f)%s" % [
			String(id), float(s.saillance), float(s.nue), float(s.distance), marque,
		])
	lignes.append("t=%.1f RE-SCORING -> %s / %s (score %.3f) | %s | biais urgence %.2f, habitude %.2f" % [
		temps,
		String(d.get("cible_id", "(rien)")) if String(d.get("cible_id", "")) != "" else "(rien)",
		String(d.get("verbe", "")) if String(d.get("verbe", "")) != "" else "(aucun verbe)",
		float(d.get("score", 0.0)),
		"   ".join(morceaux),
		float(infos.get("biais_urgence", 0.0)), float(infos.get("biais_habitude", 0.0)),
	])
	if bool(infos.get("change", false)):
		var avant: Dictionary = infos.get("decision_avant", {})
		lignes.append("t=%.1f DECISION CHANGE : %s -> %s (engagement : %s)" % [
			temps,
			String(avant.get("cible_id", "")) if String(avant.get("cible_id", "")) != "" else "(rien)",
			String(d.get("cible_id", "")) if String(d.get("cible_id", "")) != "" else "(rien)",
			String(infos.get("issue_engagement", "vide")),
		])
	return lignes

static func texte_cible(id: String, infos: Dictionary, config: Dictionary) -> String:
	var s: Dictionary = infos.get("saillances", {}).get(id, {})
	var d: Dictionary = infos.get("decision", {})
	var lignes: Array = ["%s%s" % [id, "   <- DECISION" if String(d.get("cible_id", "")) == id else ""]]
	lignes.append("saillance %.3f  (nue %.3f)" % [float(s.get("saillance", 0.0)), float(s.get("nue", 0.0))])
	lignes.append("distance %.0f" % float(s.get("distance", 0.0)))
	var facteur: float = float(s.saillance) / float(s.nue) if float(s.get("nue", 0.0)) > 0.0 else 1.0
	if abs(facteur - 1.0) > 0.001:
		lignes.append("deformation x%.2f" % facteur)
	else:
		lignes.append("aucune deformation")
	if not infos.get("visibles_ids", []).has(id):
		lignes.append("ECRASEE (dominance.gd)")
	return "\n".join(lignes)

static func texte_colon(colon: Dictionary, infos: Dictionary, config: Dictionary) -> String:
	var d: Dictionary = infos.get("decision", {})
	var canal: Dictionary = colon.proprietes.get("reserves", {}).get(String(config.nom_reserve_energie), {})
	var engagement = colon.proprietes.get("engagement", null)
	return ("%s\ndecision : %s / %s   score %.3f\nre-scoring dans %.1f s (cadence %.1f s)\n" +
		"energie %.0f / %.0f   urgence %.2f\nbiais urgence %.2f   biais habitude %.2f\nengagement : %s") % [
		String(colon.id),
		String(d.get("cible_id", "")) if String(d.get("cible_id", "")) != "" else "(rien)",
		String(d.get("verbe", "")) if String(d.get("verbe", "")) != "" else "(aucun verbe)",
		float(d.get("score", 0.0)),
		float(infos.get("restant_cadence", 0.0)), float(config.cadence_scoring_s),
		float(canal.get("reserve", 0.0)), float(config.capacite_energie),
		float(infos.get("urgence", 0.0)),
		float(infos.get("biais_urgence", 0.0)), float(infos.get("biais_habitude", 0.0)),
		"%s (poids %.2f)" % [String(engagement.cible_id), float(engagement.poids)] if engagement != null else "-",
	]

static func texte_aide() -> String:
	return "clic GAUCHE : le colon a faim / est rassasie   |   clic DROIT : le bois s'eloigne / se rapproche"

# ---- Rendu (impur, Node) -- aucune decision, seulement des couleurs et des
# rectangles.

func _reconstruire_monde() -> void:
	_monde = BancCommun.monde_depuis([
		{"choses": [_colon], "type": "colon"},
		{"choses": _cibles, "type": "cible"},
	])

func _couleur(rgb: Array) -> Color:
	return Color(float(rgb[0]), float(rgb[1]), float(rgb[2]))

func _construire_rendu() -> void:
	for cible in _cibles:
		var label := _creer_label(int(_config.taille_police_label))
		add_child(label)
		_labels[cible.id] = label
	_label_colon = _creer_label(int(_config.taille_police_label))
	add_child(_label_colon)

	var couche := CanvasLayer.new()
	add_child(couche)
	_label_entete = _creer_label(int(_config.taille_police_entete))
	_label_entete.position = Vector2(10.0, 8.0)
	couche.add_child(_label_entete)
	_label_aide = _creer_label(int(_config.taille_police_aide))
	_label_aide.position = Vector2(10.0, 34.0)
	_label_aide.text = texte_aide()
	couche.add_child(_label_aide)

	var camera := Camera2D.new()
	camera.position = Vector2(float(_config.terrain_largeur), float(_config.terrain_hauteur)) / 2.0
	camera.zoom = Vector2(float(_config.camera_zoom), float(_config.camera_zoom))
	camera.enabled = true
	add_child(camera)

func _creer_label(taille: int) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", taille)
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	label.add_theme_constant_override("outline_size", 4)
	return label

func _rafraichir() -> void:
	for cible in _cibles:
		var label: Label = _labels[cible.id]
		var taille: float = _taille_cible(String(cible.id))
		label.position = Vector2(cible.position.x, cible.position.y) + Vector2(taille * 0.7, taille * 0.7)
		label.text = texte_cible(String(cible.id), _infos, _config)
	var t: float = float(_config.colon.taille)
	_label_colon.position = Vector2(_colon.position.x, _colon.position.y) + Vector2(-t * 5.0, t * 0.7)
	_label_colon.text = texte_colon(_colon, _infos, _config)
	_label_entete.text = "t=%.1f s   faim : %s   bois : %s   re-scoring dans %.1f s" % [
		_temps, "AFFAME" if _affame else "rassasie", "eloigne" if _eloigne else "proche",
		float(_infos.get("restant_cadence", 0.0)),
	]

func _taille_cible(id: String) -> float:
	for decl in _config.get("cibles", []):
		if String(decl.id) == id:
			return float(decl.taille)
	return 40.0

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(float(_config.terrain_largeur), float(_config.terrain_hauteur))),
		_couleur(_config.couleur_fond))

	var centre_colon := Vector2(_colon.position.x, _colon.position.y)
	# Les deux rayons REELS, jamais des disques decoratifs : la portee de vue
	# decide ce qui entre dans perception.gd, la portee d'engagement decide ce a
	# quoi le colon peut se coupler.
	draw_arc(centre_colon, float(_config.colon.portee_vue), 0.0, TAU, 96, _couleur(_config.couleur_portee_vue), 2.0)
	draw_arc(centre_colon, float(_config.portee_engagement), 0.0, TAU, 96, _couleur(_config.couleur_portee_engagement), 2.0)

	var decision: Dictionary = _infos.get("decision", {})
	var visibles: Array = _infos.get("visibles_ids", [])
	for cible in _cibles:
		var id := String(cible.id)
		var taille: float = _taille_cible(id)
		var centre := Vector2(cible.position.x, cible.position.y)
		var couleur := _couleur(_couleur_declaree(id))
		if not visibles.has(id):
			couleur = _couleur(_config.couleur_ecrasee)
		draw_rect(Rect2(centre - Vector2(taille, taille) / 2.0, Vector2(taille, taille)), couleur)
		# LA HAUTEUR DE LA BARRE EST LA SAILLANCE REELLE, graduee sur le score le
		# plus haut de CE tick : c'est le seul dessin qui dise l'arbitrage sans
		# qu'on ait a lire un nombre.
		_dessiner_barre_saillance(id, centre, taille)

	if String(decision.get("cible_id", "")) != "":
		var visee := cible_par_id(_cibles, String(decision.cible_id))
		if not visee.is_empty():
			draw_line(centre_colon, Vector2(visee.position.x, visee.position.y),
				_couleur(_config.couleur_decision), 3.0)
	var engagement = _colon.proprietes.get("engagement", null)
	if engagement != null:
		var couplee := cible_par_id(_cibles, String(engagement.cible_id))
		if not couplee.is_empty():
			draw_dashed_line(centre_colon, Vector2(couplee.position.x, couplee.position.y),
				_couleur(_config.couleur_engagement), 3.0, 12.0)

	var tc: float = float(_config.colon.taille)
	draw_rect(Rect2(centre_colon - Vector2(tc, tc) / 2.0, Vector2(tc, tc)), _couleur(_config.colon.couleur))
	_dessiner_barres_colon(centre_colon, tc)

func _dessiner_barre_saillance(id: String, centre: Vector2, taille: float) -> void:
	var s: Dictionary = _infos.get("saillances", {}).get(id, {})
	var maximum := 0.0
	for autre in _infos.get("saillances", {}).values():
		maximum = max(maximum, float(autre.get("saillance", 0.0)))
	var largeur: float = float(_config.largeur_barre)
	var hauteur: float = float(_config.hauteur_barre)
	var origine := centre + Vector2(-largeur / 2.0, -taille / 2.0 - hauteur - 6.0)
	draw_rect(Rect2(origine, Vector2(largeur, hauteur)), _couleur(_config.couleur_fond_barre))
	var f: float = clamp(float(s.get("saillance", 0.0)) / max(maximum, 0.0001), 0.0, 1.0)
	draw_rect(Rect2(origine, Vector2(largeur * f, hauteur)), _couleur(_config.couleur_decision))
	# Le trait de la saillance NUE : c'est l'ecart entre le trait et la barre qui
	# EST la deformation, jamais un nombre a lire a cote.
	var fn: float = clamp(float(s.get("nue", 0.0)) / max(maximum, 0.0001), 0.0, 1.0)
	draw_line(origine + Vector2(largeur * fn, -2.0), origine + Vector2(largeur * fn, hauteur + 2.0),
		_couleur(_config.couleur_portee_vue), 2.0)

# Trois barres sous le colon : urgence (rouge), habitude (verte), cadence
# restante (blanche). Chacune est une FRACTION d'un maximum lu en donnee, jamais
# un nombre brut en pixels qui mentirait des que la calibration change.
func _dessiner_barres_colon(centre: Vector2, taille: float) -> void:
	var largeur: float = float(_config.largeur_barre)
	var hauteur: float = float(_config.hauteur_barre)
	var espacement: float = float(_config.espacement_barre)
	var origine := centre + Vector2(-largeur / 2.0, -taille / 2.0 - 3.0 * espacement - 6.0)
	var barres := [
		{"f": float(_infos.get("biais_urgence", 0.0)) / max(float(_config.plafond_biais_urgence), 0.0001),
			"c": _couleur(_config.couleur_barre_urgence)},
		{"f": float(_infos.get("biais_habitude", 0.0)) / max(float(_config.plafond_biais_habitude), 0.0001),
			"c": _couleur(_config.couleur_barre_habitude)},
		{"f": float(_infos.get("restant_cadence", 0.0)) / max(float(_config.cadence_scoring_s), 0.0001),
			"c": _couleur(_config.couleur_barre_cadence)},
	]
	for i in range(barres.size()):
		var haut := origine + Vector2(0.0, float(i) * espacement)
		draw_rect(Rect2(haut, Vector2(largeur, hauteur)), _couleur(_config.couleur_fond_barre))
		draw_rect(Rect2(haut, Vector2(largeur * clamp(float(barres[i].f), 0.0, 1.0), hauteur)), barres[i].c)

func _couleur_declaree(id: String) -> Array:
	for decl in _config.get("cibles", []):
		if String(decl.id) == id:
			return decl.couleur
	return [1.0, 1.0, 1.0]

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
