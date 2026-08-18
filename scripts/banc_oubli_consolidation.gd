extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_oubli_consolidation.tscn, PAS la
# scene principale -- run/main_scene reste banc_p1, coexiste avec les autres
# bancs). Chantier « oubli exponentiel + consolidation nocturne », audit
# prealable audit_perception_croyance_memoire_prealable.md, lignes 3 et 4
# (PARTIELLEMENT COUVERT et CABLABLE, toutes deux sous la meme dependance :
# « il n'y a rien a oublier tant que la ligne 1 ou 5 n'a pas produit un objet
# memorise »). Les deux sont fermees, ce banc les consomme.
#
# Compose CINQ mecanismes deja fermes, TOUS INCHANGES : scripts/croyance.gd,
# scripts/memoire_spatiale.gd, scripts/horloge.gd, scripts/perception.gd,
# scripts/monde.gd (+ scripts/etat_effectif.gd et scripts/etat_duree.gd en
# lecture/pose pures). AUCUN MECANISME DU COEUR TOUCHE, aucun .gd neuf du
# coeur. La seule donnee PARTAGEE enrichie est data/etats.json, qui gagne un
# effet 'charge_emotionnelle' sur 'peur'/'colere'/'heureux' -- voir la note de
# 'peur' dans ce fichier, ecrite une fois pour les trois.
#
# COLON ET OBJETS CONSTRUITS A LA MAIN (pas Objet.fabriquer, meme statut que
# banc_croyance.gd/banc_memoire_navigation.gd/banc_maladie.gd -- aucun materiau
# n'intervient). Positions en PIXELS (patron banc_lumiere.gd), z = 0.0
# TOUJOURS -- VERTICALITE.
#
# ---------------------------------------------------------------------------
# CE QU'IL DOIT MONTRER
# ---------------------------------------------------------------------------
# 1. L'OUBLI EST UNE EXPONENTIELLE, ET AUCUN MECANISME NE LE SAIT. croyance.gd
#    et memoire_spatiale.gd decroissent par SOUSTRACTION FIXE et lisent leur
#    taux AU CATALOGUE (constat (F) de l'audit : il n'existe AUCUNE
#    decroissance exponentielle dans le depot). Ce cablage ecrit chaque tick,
#    ET PAR SOUVENIR, taux = valeur_courante / (S x charge) : la soustraction
#    fixe devient dR/dt = -R/(S x charge), donc R = R0 x e^(-t/(S x charge)) par
#    integration d'Euler. Vite au debut, lentement ensuite -- zero ligne de
#    mecanisme, et l'erreur d'Euler (~delta/(2S), soit 0.14% a 60 im/s pour
#    S = 6 s) est sous le bruit d'affichage.
# 2. LE RAPPEL RENFORCE, DEUX FOIS. Chaque observation monte la certitude
#    (gain_par_verification, deja dans croyance.gd) ET ETIRE S
#    (gain_espacement_par_rappel, ce cablage) : ce n'est pas seulement « j'en
#    suis plus sur », c'est « je l'oublierai moins vite ». L'effet d'espacement
#    est la seule chose que ce banc ajoute a la loi de l'oubli.
# 3. L'EMOTION S'ATTACHE AU SOUVENIR, PAS AU COLON. data/etats.json module
#    'charge_emotionnelle' sur le colon entier ; le cablage la FIGE, au moment
#    de l'observation, dans un registre local, et seulement pour les choses qui
#    portent la propriete de menace. La braise reste chargee longtemps apres
#    que la peur est retombee, la baie ne l'a jamais ete -- deux souvenirs du
#    meme colon, deux vitesses d'oubli.
# 4. LE SOMMEIL CONSOLIDE. Sous heures_minimum_sommeil, rien. Au-dela, le
#    cablage rejoue ce que le colon croit deja (perceptions SYNTHETIQUES tirees
#    de son propre registre) et appelle observer()/memoriser() avec un
#    catalogue dont le gain est celui du sommeil. Aucune valeur n'est inventee :
#    le sommeil ne renforce que ce qui a ete percu eveille.
# 5. CE QUI TOMBE SOUS LE PLANCHER DISPARAIT. Un souvenir a 0.001 n'est pas un
#    souvenir faible, c'est un souvenir oublie -- et c'est le MECANISME qui le
#    retire, jamais ce fichier (voir LE BALAYAGE A DELTA NUL, plus bas).
#
# ---------------------------------------------------------------------------
# LE POINT TECHNIQUE DU CHANTIER : UN TAUX PAR SOUVENIR, SANS TOUCHER LE COEUR
# ---------------------------------------------------------------------------
# croyance.gd:avancer et memoire_spatiale.gd:avancer prennent UN taux au
# catalogue et le passent a TOUS les souvenirs de l'entite. Or un oubli
# exponentiel veut un taux PAR souvenir (il est proportionnel a ce qui reste),
# et l'espacement comme la charge emotionnelle different d'un souvenir a
# l'autre. Deux gestes, et aucun des deux ne recopie une loi :
#
# (a) UNE VUE PAR SOUVENIR. Le cablage appelle avancer() sur un Dictionary
#     JETABLE dont le registre ne contient qu'une entree -- mais cette entree
#     est LA REFERENCE REELLE du champ (Dictionary), si bien que la
#     decroissance ecrite par le mecanisme atteint le vrai registre. Ce qui ne
#     traverse PAS la vue, dit plutot que masque : les `erase` de niveau
#     racine, qui portent sur le Dictionary jetable.
# (b) LE BALAYAGE A DELTA NUL. Un dernier appel a avancer(), sur l'entite
#     REELLE cette fois, avec delta = 0.0 et le catalogue INTACT : max(0, c -
#     taux x 0) laisse toute valeur inchangee, et le mecanisme applique
#     pourtant son propre plancher_suppression et ses retraits (propriete
#     tombee, puis chose devenue vide). Le plancher n'est donc JAMAIS recopie
#     ici -- ce fichier n'ecrit aucun seuil de suppression, il rappelle celui
#     du catalogue en le laissant s'exercer.
#
# ---------------------------------------------------------------------------
# QUATRE DECISIONS DE CE CABLAGE, dites plutot que masquees
# ---------------------------------------------------------------------------
# (a) depense.gd N'INTERVIENT PAS, contrairement a ce que l'audit ligne 3
#     proposait. Sa piste (« une reserve memoire dont le cablage reecrit
#     cout_base = reserve / S ») etait juste QUAND rien ne portait la memoire ;
#     depuis croyance.gd et memoire_spatiale.gd, la memoire A une structure, et
#     la faire vivre en double dans un canal de `reserves` obligerait a
#     synchroniser deux compteurs -- exactement ce que la doctrine « jamais les
#     deux compteurs » a deja tranche pour la fatigue (voir docs/ETAT.md,
#     chantier fatigue + circadien, ECARTE DOCTRINAL).
# (b) LE COLON NE BOUGE PAS et aucune couche de saillance n'est montee -- ni
#     proximite.gd, ni dominance.gd, ni agir.gd. Le sujet est ce qu'un souvenir
#     DEVIENT avec le temps, jamais ce qu'il fait decider (banc_croyance.gd
#     montre la decision sur une copie, banc_memoire_navigation.gd le
#     deplacement vers un souvenir : ni l'un ni l'autre n'a a etre rejoue ici).
# (c) memoire_spatiale.gd:position_memorisee N'EST PAS APPELEE : la position du
#     souvenir est relue BRUTE dans le registre, pour l'affichage et pour la
#     consolidation. Deliberement -- position_memorisee rend une position DEJA
#     BIAISEE par l'erreur de navigation, et la reinjecter dans memoriser()
#     ferait deriver le souvenir un peu plus a chaque nuit. La lecture directe
#     du registre est le geste explicitement legitime de
#     banc_memoire_navigation.gd:force_memorisee (« la structure est declaree et
#     documentee par memoire_spatiale.gd »).
# (d) LES OBJETS NE SONT PAS RETIRES DU MONDE mais ELOIGNES hors de portee de
#     vue (patron litteral de banc_croyance.gd:basculer_feu) -- monde.gd n'a
#     aucune fonction de retrait, dette deja recensee.
#
# LIMITE DITE, PAS MASQUEE : croyance.gd:corriger n'est jamais appele ici, donc
# rien ne contredit jamais une croyance -- un souvenir de ce banc ne peut que
# monter, decroitre ou disparaitre, jamais devenir faux. La fausse croyance est
# le sujet de banc_croyance.gd, deja ecrit.
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge les catalogues et construit, _unhandled_input
#   bascule les deux toggles, _process appelle UNIQUEMENT avancer() et lit son
#   resultat pour l'affichage et la console -- aucune decision dans _process.
# - Fonctions statiques (pures, testables headless, voir
#   scripts/test_banc_oubli_consolidation.gd) : tout le reste.

const Croyance = preload("res://scripts/croyance.gd")
const MemoireSpatiale = preload("res://scripts/memoire_spatiale.gd")
const Horloge = preload("res://scripts/horloge.gd")
const Perception = preload("res://scripts/perception.gd")
const Monde = preload("res://scripts/monde.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")
const EtatDuree = preload("res://scripts/etat_duree.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")

const TAILLE_COLON := 54.0
const TAILLE_OBJET := 40.0
const TAILLE_SOUVENIR := 22.0
const LARGEUR_BARRE := 150.0
const HAUTEUR_BARRE := 14.0
const ECART_BARRE := 18.0

var _config: Dictionary = {}
var _catalogue_canaux: Dictionary = {}
var _catalogue_croyances: Dictionary = {}
var _catalogue_memoire: Dictionary = {}
var _etats: Dictionary = {}

var _monde
var _colon: Dictionary = {}
var _objets: Array = []

var _temps := 0.0
var _prochain_print := 0.0
var _sommeil_force := false
var _rappel_force := false

var _fond: ColorRect
var _noeud_colon: ColorRect
var _noeuds: Dictionary = {}
var _souvenirs: Dictionary = {}
var _barres: Dictionary = {}
var _labels: Dictionary = {}
var _label_colon: Label
var _label_aide: Label
var _barre_sommeil: Dictionary = {}

func _ready() -> void:
	_config = _charger_json("res://data/banc_oubli_consolidation.json")
	_catalogue_canaux = _charger_json("res://data/canaux.json")
	_catalogue_croyances = _charger_json("res://data/croyances.json")
	_catalogue_memoire = _charger_json("res://data/memoire_spatiale.json")
	_etats = _charger_json("res://data/etats.json")

	_colon = construire_colon(_config)
	_objets = construire_objets(_config)
	_monde = BancCommun.monde_depuis([
		{"choses": [_colon], "type": "colon"},
		{"choses": _objets, "type": "objet"},
	])

	_creer_rendu()
	print(ligne_pose_initiale(_config))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_sommeil_force = not _sommeil_force
		print(ligne_toggle(_temps, "SOMMEIL FORCE", "OUI" if _sommeil_force else "non"))
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		_rappel_force = not _rappel_force
		print(ligne_toggle(_temps, "RAPPEL FORCE", "OBJET RAMENE" if _rappel_force else "deroulement normal"))

func _process(delta: float) -> void:
	_temps += delta
	var bilan := avancer(
		_colon, _objets, _monde, _config,
		_catalogue_canaux, _catalogue_croyances, _catalogue_memoire, _etats,
		_sommeil_force, _rappel_force, _temps, delta)
	_rafraichir(bilan)

	for id in bilan.oublies:
		print(ligne_oubli(_temps, String(id)))
	if int(bilan.consolidations_ce_pas) > 0:
		print(ligne_consolidation(_temps, bilan))
	if _temps >= _prochain_print:
		_prochain_print = _temps + float(_config.intervalle_print)
		print(ligne_trace(_temps, bilan))

# ---------------------------------------------------------------------------
# Construction (pure)
# ---------------------------------------------------------------------------

# Le colon porte huit choses et rien d'autre :
# - le canal de perception (lu par perception.gd) ;
# - `croyances` et `memoire_spatiale`, toutes deux STRUCTURELLES (leur cle
#   absente alarme dans les deux mecanismes) : posees VIDES, jamais remplies en
#   dur -- tout ce qu'il croit naitra de ce qu'il aura percu (docs/design.md,
#   meme precedent que lien_personnel.gd) ;
# - `forme`, dont memoire_spatiale.gd ne lit que `biais` : 0.0 ici, le sujet de
#   ce banc n'est pas de se tromper d'endroit mais d'oublier ;
# - `charge_emotionnelle` A 1.0 EN BASE, et c'est OBLIGATOIRE : etat_effectif.gd
#   rend base x facteur, un colon sans base donnerait 0.0 x 2.0 = 0.0 et le
#   cablage diviserait par zero (voir data/etats.json:peur, meme piege que
#   'precision'/'endurance') ;
# - les deux registres LOCAUX de ce banc (espacement et charge par souvenir),
#   et les trois compteurs de cycle de sommeil.
static func construire_colon(config: Dictionary) -> Dictionary:
	var decl: Dictionary = config.colon
	var pos: Array = decl.position
	return {
		"id": String(decl.id),
		"position": Vector3(pos[0], pos[1], pos[2]),
		"prochaine_observation": 0.0,
		"prochaine_consolidation": 0.0,
		"proprietes": {
			"canaux": [String(config.nom_canal_vue)],
			"canaux_config": {
				String(config.nom_canal_vue): {
					"portee": float(decl.portee_vue), "angle": 360.0,
					"sensibilite": 1.0, "seuil": 0.0,
				},
			},
			"croyances": {},
			"memoire_spatiale": {},
			"forme": {"biais": 0.0},
			"etats_actifs": [],
			String(config.nom_propriete_charge): float(config.charge_neutre),
			String(config.nom_registre_espacement): {},
			String(config.nom_registre_charge): {},
			"dort": false,
			"heures_dormies_ce_cycle": 0.0,
			"consolidations_ce_cycle": 0,
		},
	}

# Les trois objets. L'id EST la cle de configuration. Les proprietes sont
# DUPLIQUEES : sans quoi ce banc muterait le Dictionary du disque, deja partage
# avec toute autre lecture du meme fichier.
static func construire_objets(config: Dictionary) -> Array:
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

# ---------------------------------------------------------------------------
# Le temps, le sommeil, la mise en scene (pures)
# ---------------------------------------------------------------------------

# L'heure vient de scripts/horloge.gd, mecanisme du COEUR -- jamais une
# troisieme recopie de banc_lumiere.gd/banc_fatigue_circadien.gd (c'est
# exactement le seuil que l'en-tete du second avait nomme).
static func heure_a(temps: float, config: Dictionary) -> float:
	var cycle: Dictionary = config.cycle
	return Horloge.heure(
		temps, float(cycle.duree_jour_secondes),
		float(cycle.heures_par_jour), float(cycle.heure_depart))

# La zone nocturne ENJAMBE MINUIT (heure >= coucher OU heure <= lever) : un
# simple « entre deux bornes » serait faux. Le banc n'appelle PAS conditions.gd
# pour si peu -- il n'a aucune propriete a poser sur une entite, seulement un
# booleen a lire (banc_fatigue_circadien.gd, lui, en a besoin parce que ses
# colons portent `doit_dormir`).
static func nuit_a(heure: float, config: Dictionary) -> bool:
	var cycle: Dictionary = config.cycle
	return heure >= float(cycle.heure_coucher) or heure <= float(cycle.heure_lever)

# UN SEUL ECRIVAIN pour `dort` : l'horloge OU le forcage, jamais deux morceaux
# de cablage qui s'ecrasent (piege nomme par les audits, constat (D)).
static func dort_a(heure: float, config: Dictionary, sommeil_force: bool) -> bool:
	return sommeil_force or nuit_a(heure, config)

# Ou est un objet REELLEMENT. Trois jalons declares en donnee, aucune
# interpolation : a portee au depart (le colon l'observe), eloigne a
# `retrait_a`, et pour le SEUL objet rappele un retour entre `retour_a` et
# `redepart_a`. Le forcage clavier ramene cet objet-la immediatement.
static func position_objet(id: String, temps: float, rappel_force: bool, config: Dictionary) -> Vector3:
	var decl: Dictionary = config.get("objets", {}).get(id, {})
	var loin: bool = temps >= float(config.retrait_a)
	if id == String(config.id_objet_rappele):
		if rappel_force:
			loin = false
		elif temps >= float(config.retour_a) and temps < float(config.redepart_a):
			loin = false
	var brut: Array = decl.position_lointaine if loin else decl.position
	return Vector3(brut[0], brut[1], brut[2])

static func poser_positions(objets: Array, temps: float, rappel_force: bool, config: Dictionary) -> void:
	for objet in objets:
		objet.position = position_objet(String(objet.id), temps, rappel_force, config)

# ---------------------------------------------------------------------------
# L'emotion (pure)
# ---------------------------------------------------------------------------

# La peur est posee tant qu'une chose PORTANT LA PROPRIETE DE MENACE est
# percue, et effacee sinon -- filtre sur une propriete nommee en donnee, jamais
# sur un type. 'peur' n'a pas de `duree` (voir data/etats.json), donc il n'entre
# jamais dans etats_intensite et EtatDuree.avancer ne le retirera JAMAIS : c'est
# au cablage de l'effacer d'etats_actifs, miroir exact du marqueur reversible
# de 'malnutri'. Rend true si la peur est active apres ce pas.
static func poser_peur(colon: Dictionary, perceptions: Array, config: Dictionary, etats: Dictionary) -> bool:
	var nom_menace := String(config.nom_propriete_menace)
	var menace := false
	for entree in perceptions:
		if bool(entree.chose.proprietes.get(nom_menace, false)):
			menace = true
	var nom_etat := String(config.nom_etat_peur)
	var actifs: Array = colon.proprietes.etats_actifs
	if menace:
		EtatDuree.poser(colon, nom_etat, etats)
	elif actifs.has(nom_etat):
		actifs.erase(nom_etat)
	return menace

# La charge EFFECTIVE du colon : sa base modulee par ses etats actifs, via
# etat_effectif.gd. La loi de resolution (ecraser gagne sur moduler, tri
# alphabetique, composition multiplicative) n'est JAMAIS reimplementee ici.
static func charge_effective(colon: Dictionary, config: Dictionary, etats: Dictionary) -> float:
	return EtatEffectif.valeur(colon, String(config.nom_propriete_charge), etats)

# ---------------------------------------------------------------------------
# Les deux registres locaux (purs)
# ---------------------------------------------------------------------------

static func espacement_de(colon: Dictionary, chose_id: String, config: Dictionary) -> float:
	var registre: Dictionary = colon.proprietes[String(config.nom_registre_espacement)]
	return float(registre.get(chose_id, float(config.espacement_initial)))

static func charge_de(colon: Dictionary, chose_id: String, config: Dictionary) -> float:
	var registre: Dictionary = colon.proprietes[String(config.nom_registre_charge)]
	return float(registre.get(chose_id, float(config.charge_neutre)))

# LA CONSTANTE DE TEMPS EFFECTIVE d'un souvenir : son espacement multiplie par
# la charge emotionnelle figee a l'observation. Bornee STRICTEMENT au-dessus de
# zero -- un diviseur nul rendrait un taux infini, c'est-a-dire un oubli
# instantane silencieux ; le point neutre est `charge_neutre`, jamais 0.0.
static func constante_de_temps(colon: Dictionary, chose_id: String, config: Dictionary) -> float:
	return max(espacement_de(colon, chose_id, config) * charge_de(colon, chose_id, config), 0.0001)

# L'EFFET D'ESPACEMENT. La premiere observation POSE l'espacement initial ;
# chacune des suivantes le multiplie, plafonne par le cablage (le coeur ne
# borne jamais le haut). La charge, elle, n'est ECRITE QUE pour les choses qui
# portent la propriete de menace -- une chose neutre reste au point neutre,
# meme observee en pleine panique.
static func marquer_observation(colon: Dictionary, chose: Dictionary, charge: float, config: Dictionary) -> void:
	var chose_id := String(chose.id)
	var espacements: Dictionary = colon.proprietes[String(config.nom_registre_espacement)]
	if not espacements.has(chose_id):
		espacements[chose_id] = float(config.espacement_initial)
	else:
		espacements[chose_id] = min(
			float(espacements[chose_id]) * float(config.gain_espacement_par_rappel),
			float(config.plafond_espacement))
	if bool(chose.proprietes.get(String(config.nom_propriete_menace), false)):
		colon.proprietes[String(config.nom_registre_charge)][chose_id] = charge

# ---------------------------------------------------------------------------
# Observer / memoriser a la cadence (purs)
# ---------------------------------------------------------------------------

# UNE cadence pour les deux mecanismes : « revenir regarder » forme la croyance
# ET rafraichit la position, c'est le meme geste. Ni observer() ni memoriser()
# n'ont de notion de temps propre (meme limite qu'epigenetique.gd:poser), la
# cadence vit donc au cablage -- appeles a chaque image, ils satureraient tout
# en quelques images. Rend les ids observes ce pas.
static func observer_si_cadence(
	colon: Dictionary,
	perceptions: Array,
	config: Dictionary,
	catalogue_croyances: Dictionary,
	catalogue_memoire: Dictionary,
	charge: float,
	temps: float,
) -> Array:
	if temps < float(colon.prochaine_observation):
		return []
	colon["prochaine_observation"] = temps + float(config.cadence_observation)
	var nom_repere := String(config.nom_propriete_repere)
	var observes: Array = []
	Croyance.observer(colon, perceptions, catalogue_croyances)
	for entree in perceptions:
		if not bool(entree.chose.proprietes.get(nom_repere, false)):
			continue
		MemoireSpatiale.memoriser(colon, String(entree.chose.id), entree.position, catalogue_memoire)
		marquer_observation(colon, entree.chose, charge, config)
		observes.append(String(entree.chose.id))
	return observes

# ECRETAGE AU PLAFOND -- du cablage, jamais un mecanisme : memoire_spatiale.gd
# ne borne pas le haut d'une force (constat pose par banc_fertilite.gd, repete
# six fois). Sans lui, un souvenir revu longtemps monterait sans fin et
# l'exponentielle partirait d'une valeur arbitraire. La certitude, elle, est
# deja bornee DANS le catalogue (plafond_certitude) -- une certitude est bornee
# par nature, une force accumulee non.
static func plafonner_memoire(colon: Dictionary, config: Dictionary) -> void:
	var plafond: float = float(config.plafond_force_memoire)
	for chose_id in colon.proprietes.memoire_spatiale:
		var entree: Dictionary = colon.proprietes.memoire_spatiale[chose_id]
		if float(entree.get("force", 0.0)) > plafond:
			entree["force"] = plafond

# ---------------------------------------------------------------------------
# La consolidation nocturne (pure)
# ---------------------------------------------------------------------------

# Accumule les heures dormies DU CYCLE COURANT et remet les compteurs a zero au
# reveil. Aucun mecanisme du coeur ne compte les heures dormies (constat de
# l'audit, ligne 4) : c'est une propriete plate accumulee par le cablage, idiome
# de 'duree_maladie_cumulee'/'dose_radiation_cumulee'. Rend true si le colon
# vient de se reveiller.
static func cumuler_sommeil(colon: Dictionary, dort: bool, heures_ecoulees: float) -> bool:
	var p: Dictionary = colon.proprietes
	var dormait: bool = bool(p.get("dort", false))
	p["dort"] = dort
	if dort:
		p["heures_dormies_ce_cycle"] = float(p.get("heures_dormies_ce_cycle", 0.0)) + heures_ecoulees
		return false
	if not dormait:
		return false
	p["heures_dormies_ce_cycle"] = 0.0
	p["consolidations_ce_cycle"] = 0
	return true

# LES PERCEPTIONS SYNTHETIQUES du sommeil : le colon ne percoit rien, il rejoue
# ce qu'il croit deja. Chaque entree porte la valeur CRUE telle quelle, si bien
# que observer() la reecrit a l'identique et ne fait monter que la certitude --
# aucune valeur n'est inventee, aucune croyance n'est creee (observer() ne cree
# que sur une propriete PRESENTE, et celles-ci viennent du registre lui-meme).
# Patron des entrees synthetiques (constat (H) de l'audit), applique un cran
# plus tot dans la chaine : la ou banc_psycho_social.gd/banc_grief.gd
# fabriquent une entree de SAILLANCE, celui-ci fabrique une entree de
# PERCEPTION.
static func perceptions_synthetiques(colon: Dictionary) -> Array:
	var sortie: Array = []
	var croyances: Dictionary = colon.proprietes.croyances
	var registre: Dictionary = colon.proprietes.memoire_spatiale
	for chose_id in croyances:
		var crues: Dictionary = {}
		for propriete in croyances[chose_id]:
			crues[propriete] = croyances[chose_id][propriete].valeur
		var position := position_brute(registre, String(chose_id))
		sortie.append({
			"chose": {"id": chose_id, "position": position, "proprietes": crues},
			"type": "",
			"position": position,
			"distance": 0.0,
			"canaux": {},
		})
	return sortie

# La position MEMORISEE, relue BRUTE dans le registre -- jamais celle rendue par
# position_memorisee(), qui est deja biaisee par l'erreur de navigation (voir
# en-tete, decision (c)). Vector3.ZERO pour une chose absente du registre : la
# croyance peut survivre a son souvenir spatial, les deux registres ont leur
# propre plancher.
static func position_brute(registre: Dictionary, chose_id: String) -> Vector3:
	var brute: Dictionary = registre.get(chose_id, {}).get("position", {})
	return Vector3(brute.get("x", 0.0), brute.get("y", 0.0), brute.get("z", 0.0))

# LE GAIN DU SOMMEIL passe par un CATALOGUE MODIFIE, jamais par une ecriture
# directe dans le registre : observer() lit gain_par_verification au catalogue
# et memoriser() y lit force_initiale, il suffit donc de leur en presenter un
# autre. Le catalogue du disque n'est jamais mute (duplicate avant ecriture).
#
# TROIS GATES, dans cet ordre : il faut dormir, avoir assez dormi DANS CE CYCLE,
# et n'avoir pas epuise le plafond de la nuit. Rend le nombre de passes faites
# ce pas (0 ou 1).
#
# LES DEUX REGISTRES SONT REJOUES DEPUIS LES CROYANCES, jamais depuis le
# registre spatial -- DEFAUT REEL TROUVE EN LANCANT LA SCENE, invisible au test.
# La boucle de memorisation iterait d'abord proprietes.memoire_spatiale : une
# chose dont la CROYANCE etait tombee sous le plancher (donc retiree) voyait
# quand meme sa POSITION reconsolidee chaque nuit, remontait plus qu'elle
# n'avait decru dans la journee, et devenait un souvenir IMMORTEL dont le colon
# ne savait plus rien. Le sommeil ne rejoue que ce qui est encore CRU ; une
# chose sortie des croyances cesse d'etre entretenue et son souvenir spatial
# finit par tomber a son tour sous son propre plancher.
static func consolider_si_possible(
	colon: Dictionary,
	config: Dictionary,
	catalogue_croyances: Dictionary,
	catalogue_memoire: Dictionary,
	temps: float,
) -> int:
	var p: Dictionary = colon.proprietes
	if not bool(p.get("dort", false)):
		return 0
	if float(p.get("heures_dormies_ce_cycle", 0.0)) < float(config.heures_minimum_sommeil):
		return 0
	if int(p.get("consolidations_ce_cycle", 0)) >= int(config.consolidations_max_par_nuit):
		return 0
	if temps < float(colon.prochaine_consolidation):
		return 0
	colon["prochaine_consolidation"] = temps + float(config.cadence_consolidation)
	p["consolidations_ce_cycle"] = int(p.get("consolidations_ce_cycle", 0)) + 1

	var cat_croyances: Dictionary = catalogue_croyances.duplicate()
	cat_croyances["gain_par_verification"] = float(config.gain_consolidation_certitude)
	Croyance.observer(colon, perceptions_synthetiques(colon), cat_croyances)

	var cat_memoire: Dictionary = {"defaut": catalogue_memoire["defaut"].duplicate()}
	cat_memoire["defaut"]["force_initiale"] = float(config.gain_consolidation_force)
	var registre: Dictionary = p.memoire_spatiale
	for chose_id in p.croyances.keys():
		if registre.has(chose_id):
			MemoireSpatiale.memoriser(colon, String(chose_id), position_brute(registre, String(chose_id)), cat_memoire)
	plafonner_memoire(colon, config)
	return 1

# ---------------------------------------------------------------------------
# L'OUBLI EXPONENTIEL (pur) -- voir en-tete, LE POINT TECHNIQUE DU CHANTIER
# ---------------------------------------------------------------------------

# Le taux qu'un souvenir subira ce pas : ce qu'il vaut, divise par sa constante
# de temps. C'est la seule formule de ce fichier, et elle ne vit nulle part
# ailleurs -- le rendu la relit, il ne la recalcule jamais.
static func taux_effectif(valeur: float, colon: Dictionary, chose_id: String, config: Dictionary) -> float:
	return valeur / constante_de_temps(colon, chose_id, config)

static func certitude_de(colon: Dictionary, chose_id: String) -> float:
	var par_chose: Dictionary = colon.proprietes.croyances.get(chose_id, {})
	for propriete in par_chose:
		return float(par_chose[propriete].get("certitude", 0.0))
	return 0.0

static func force_de(colon: Dictionary, chose_id: String) -> float:
	return float(colon.proprietes.memoire_spatiale.get(chose_id, {}).get("force", 0.0))

# Aplatit le registre de croyances en cles « chose/propriete », pour DIFFERENCE
# avant/apres : c'est ainsi que ce fichier detecte un oubli, en comparant deux
# etats et JAMAIS en recopiant le plancher de croyance.gd. Patron exact de
# banc_croyance.gd:instantane.
static func instantane(colon: Dictionary) -> Dictionary:
	var plat: Dictionary = {}
	var croyances: Dictionary = colon.proprietes.croyances
	for chose_id in croyances:
		for propriete in croyances[chose_id]:
			plat["%s/%s" % [chose_id, propriete]] = true
	return plat

# UNE VUE PAR SOUVENIR, puis LE BALAYAGE A DELTA NUL (en-tete). Les catalogues
# du disque ne sont jamais mutes : chaque appel recoit une copie dont le seul
# taux est reecrit.
static func oublier(
	colon: Dictionary,
	config: Dictionary,
	catalogue_croyances: Dictionary,
	catalogue_memoire: Dictionary,
	delta: float,
) -> void:
	var croyances: Dictionary = colon.proprietes.croyances
	for chose_id in croyances.keys():
		var par_chose: Dictionary = croyances[chose_id]
		for propriete in par_chose.keys():
			var champ: Dictionary = par_chose[propriete]
			var cat: Dictionary = catalogue_croyances.duplicate()
			cat["taux_decroissance"] = taux_effectif(
				float(champ.get("certitude", 0.0)), colon, String(chose_id), config)
			Croyance.avancer(
				{"proprietes": {"croyances": {chose_id: {propriete: champ}}}}, delta, cat)
	Croyance.avancer(colon, 0.0, catalogue_croyances)

	var registre: Dictionary = colon.proprietes.memoire_spatiale
	for chose_id in registre.keys():
		var entree: Dictionary = registre[chose_id]
		var cat_m: Dictionary = {"defaut": catalogue_memoire["defaut"].duplicate()}
		cat_m["defaut"]["taux_decroissance"] = taux_effectif(
			float(entree.get("force", 0.0)), colon, String(chose_id), config)
		MemoireSpatiale.avancer(
			{"proprietes": {"memoire_spatiale": {chose_id: entree}}}, delta, cat_m)
	MemoireSpatiale.avancer(colon, 0.0, catalogue_memoire)

# ---------------------------------------------------------------------------
# LE PAS COMPLET (pur)
# ---------------------------------------------------------------------------

# Seul appele par _process (qui ne calcule jamais rien lui-meme). ORDRE FIXE ET
# VOULU, chaque etape depend de la precedente :
#  1. l'heure vient de horloge.gd, la nuit de la zone declaree en donnee ;
#  2. les objets sont poses a leur position REELLE du moment (monde.gd relit
#     chose.position a chaque requete, aucune reinscription necessaire) ;
#  3. perception.gd dit ce que le colon voit MAINTENANT -- rien s'il dort ;
#  4. la peur est posee ou effacee selon ce qu'il percoit ;
#  5. la charge effective est composee (etat_effectif.gd) ;
#  6. les compteurs de sommeil sont cumules, remis a zero au reveil ;
#  7. EVEILLE : observer/memoriser a la cadence, puis ecretage de la force ;
#     ENDORMI : consolidation, sous ses trois gates ;
#  8. L'OUBLI EN DERNIER -- une observation faite ce pas ne doit pas perdre sa
#     certitude avant d'avoir compte une seule fois (meme ordre que
#     banc_croyance.gd, inverse de banc_memoire_navigation.gd qui n'observe
#     qu'a portee et n'a pas ce risque).
# Rend un diagnostic de trace, jamais relu comme une source de verite.
static func avancer(
	colon: Dictionary,
	objets: Array,
	monde,
	config: Dictionary,
	catalogue_canaux: Dictionary,
	catalogue_croyances: Dictionary,
	catalogue_memoire: Dictionary,
	etats: Dictionary,
	sommeil_force: bool,
	rappel_force: bool,
	temps: float,
	delta: float,
) -> Dictionary:
	var cycle: Dictionary = config.cycle
	var heure := heure_a(temps, config)
	var dort := dort_a(heure, config, sommeil_force)
	poser_positions(objets, temps, rappel_force, config)

	var perceptions: Array = [] if dort else Perception.percevoir(colon, monde, catalogue_canaux)
	var peur := poser_peur(colon, perceptions, config, etats)
	var charge := charge_effective(colon, config, etats)

	var heures_ecoulees: float = 0.0
	if float(cycle.duree_jour_secondes) > 0.0:
		heures_ecoulees = delta / float(cycle.duree_jour_secondes) * float(cycle.heures_par_jour)
	var reveil := cumuler_sommeil(colon, dort, heures_ecoulees)

	var observes: Array = []
	var consolidations := 0
	if dort:
		consolidations = consolider_si_possible(colon, config, catalogue_croyances, catalogue_memoire, temps)
	else:
		observes = observer_si_cadence(
			colon, perceptions, config, catalogue_croyances, catalogue_memoire, charge, temps)
		plafonner_memoire(colon, config)

	var avant := instantane(colon)
	oublier(colon, config, catalogue_croyances, catalogue_memoire, delta)
	var apres := instantane(colon)
	var oublies: Array = []
	for cle in avant:
		if not apres.has(cle):
			oublies.append(String(cle).split("/")[0])

	return {
		"heure": heure,
		"nuit": nuit_a(heure, config),
		"dort": dort,
		"reveil": reveil,
		"peur": peur,
		"charge": charge,
		"heures_dormies": float(colon.proprietes.heures_dormies_ce_cycle),
		"consolidations": int(colon.proprietes.consolidations_ce_cycle),
		"consolidations_ce_pas": consolidations,
		"observes": observes,
		"oublies": oublies,
		"souvenirs": souvenirs_de(colon, objets, config),
	}

# L'etat de chaque objet, tel que le colon le porte. Le rendu et la trace ne
# lisent QUE ceci -- ils ne peuvent donc pas mentir sur ce que le colon garde
# (meme discipline que banc_menace_combat.gd/banc_croyance.gd).
static func souvenirs_de(colon: Dictionary, objets: Array, config: Dictionary) -> Array:
	var sortie: Array = []
	for objet in objets:
		var id := String(objet.id)
		var certitude := certitude_de(colon, id)
		var force := force_de(colon, id)
		sortie.append({
			"id": id,
			"certitude": certitude,
			"force": force,
			"taux_certitude": taux_effectif(certitude, colon, id, config),
			"taux_force": taux_effectif(force, colon, id, config),
			"espacement": espacement_de(colon, id, config),
			"charge": charge_de(colon, id, config),
			"connu": certitude > 0.0 or force > 0.0,
			"position_memorisee": position_brute(colon.proprietes.memoire_spatiale, id),
		})
	return sortie

# ---------------------------------------------------------------------------
# Textes -- affichage et trace console. Aucun calcul, ils ne font que LIRE le
# bilan rendu par avancer(). (Traces de mise au point, pas une interface
# joueur : la regle d'INTERNATIONALISATION de CLAUDE.md vise « les chaines
# visibles par le joueur ».)
# ---------------------------------------------------------------------------

static func ligne_pose_initiale(config: Dictionary) -> String:
	return "t=0.0 colon '%s' pose, %d objets a portee ; retrait a t=%.1f s, retour de '%s' a t=%.1f s ; nuit de %.0f h a %.0f h" % [
		config.colon.id, config.get("objets", {}).size(), float(config.retrait_a),
		config.id_objet_rappele, float(config.retour_a),
		float(config.cycle.heure_coucher), float(config.cycle.heure_lever),
	]

static func ligne_toggle(t: float, nom: String, valeur: String) -> String:
	return "t=%.1f bascule %s -> %s" % [t, nom, valeur]

static func ligne_oubli(t: float, id: String) -> String:
	return "t=%.1f OUBLIE : '%s' sort des croyances (sous le plancher)" % [t, id]

static func ligne_consolidation(t: float, bilan: Dictionary) -> String:
	return "t=%.1f CONSOLIDE (passe %d, %.1f h dormies)%s" % [
		t, int(bilan.consolidations), float(bilan.heures_dormies),
		"".join(_morceaux_consolidation(bilan)),
	]

static func _morceaux_consolidation(bilan: Dictionary) -> Array:
	var morceaux: Array = []
	for s in bilan.souvenirs:
		if not bool(s.connu):
			continue
		morceaux.append(" | %s %.3f/%.3f" % [s.id, float(s.certitude), float(s.force)])
	return morceaux

static func ligne_trace(t: float, bilan: Dictionary) -> String:
	var texte := "t=%.1f h=%.1f %s charge=%.2f dormi=%.1fh cons=%d" % [
		t, float(bilan.heure),
		"DORT" if bool(bilan.dort) else ("PEUR" if bool(bilan.peur) else "    "),
		float(bilan.charge), float(bilan.heures_dormies), int(bilan.consolidations),
	]
	for s in bilan.souvenirs:
		texte += " | %s c=%.3f f=%.3f taux=%.4f S=%.1f e=%.1f" % [
			s.id, float(s.certitude), float(s.force),
			float(s.taux_certitude), float(s.espacement), float(s.charge),
		]
	return texte

static func texte_colon(bilan: Dictionary, config: Dictionary) -> String:
	return "%s\nheure = %.1f  (%s)\ncharge_emotionnelle = %.2f%s\nheures dormies = %.2f / %.1f minimum\nconsolidations = %d / %d" % [
		"DORT" if bool(bilan.dort) else "eveille",
		float(bilan.heure), "nuit" if bool(bilan.nuit) else "jour",
		float(bilan.charge), "   [PEUR]" if bool(bilan.peur) else "",
		float(bilan.heures_dormies), float(config.heures_minimum_sommeil),
		int(bilan.consolidations), int(config.consolidations_max_par_nuit),
	]

static func texte_souvenir(s: Dictionary) -> String:
	if not bool(s.connu):
		return "%s\n(oublie)" % s.id
	return "%s\ncertitude %.3f  (taux %.4f/s)\nforce     %.3f  (taux %.4f/s)\nS = %.1f s   charge = %.1f" % [
		s.id, float(s.certitude), float(s.taux_certitude),
		float(s.force), float(s.taux_force),
		float(s.espacement), float(s.charge),
	]

static func texte_aide() -> String:
	return "clic gauche : forcer le sommeil      touche R : ramener / eloigner l'objet rappele"

# ---------------------------------------------------------------------------
# Rendu (impur, Node) -- aucune decision, seulement des noeuds et une camera.
# ---------------------------------------------------------------------------

func _rafraichir(bilan: Dictionary) -> void:
	_fond.color = _couleur(_config.couleurs.fond_nuit if bool(bilan.nuit) else _config.couleurs.fond_jour)

	var cle_colon := "colon"
	if bool(bilan.dort):
		cle_colon = "colon_dort"
	elif bool(bilan.peur):
		cle_colon = "colon_peur"
	_noeud_colon.color = _couleur(_config.couleurs[cle_colon])
	_label_colon.text = texte_colon(bilan, _config)

	for objet in _objets:
		var noeud: ColorRect = _noeuds[objet.id]
		noeud.position = Vector2(objet.position.x, objet.position.y) - noeud.size / 2.0

	for s in bilan.souvenirs:
		var id := String(s.id)
		_labels[id].text = texte_souvenir(s)
		var marqueur: ColorRect = _souvenirs[id]
		marqueur.visible = bool(s.connu)
		if bool(s.connu):
			var pos: Vector3 = s.position_memorisee
			marqueur.position = Vector2(pos.x, pos.y) - marqueur.size / 2.0
		_regler_barre(_barres[id].certitude, float(s.certitude))
		_regler_barre(_barres[id].force, float(s.force))

	var minimum: float = max(float(_config.heures_minimum_sommeil), 0.0001)
	_regler_barre(_barre_sommeil, float(bilan.heures_dormies) / minimum)

func _regler_barre(barre: Dictionary, ratio: float) -> void:
	var remplissage: ColorRect = barre.remplissage
	remplissage.size = Vector2(LARGEUR_BARRE * clamp(ratio, 0.0, 1.0), HAUTEUR_BARRE)

func _creer_rendu() -> void:
	_fond = ColorRect.new()
	_fond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fond.size = Vector2(6000.0, 5000.0)
	_fond.position = Vector2(-3000.0, -2500.0)
	add_child(_fond)

	for objet in _objets:
		_souvenirs[objet.id] = _creer_carre(TAILLE_SOUVENIR, _config.couleurs.souvenir)
		_noeuds[objet.id] = _creer_carre(TAILLE_OBJET, _config.couleurs.get(String(objet.id), [0.6, 0.6, 0.6]))

	_noeud_colon = _creer_carre(TAILLE_COLON, _config.couleurs.colon)
	_noeud_colon.position = Vector2(_colon.position.x, _colon.position.y) - _noeud_colon.size / 2.0

	var couche_ui := CanvasLayer.new()
	add_child(couche_ui)

	_label_colon = _creer_label(couche_ui, Vector2(20.0, 14.0), 16)

	var y := 140.0
	for objet in _objets:
		_labels[objet.id] = _creer_label(couche_ui, Vector2(20.0, y), 14)
		_barres[objet.id] = {
			"certitude": _creer_barre(couche_ui, Vector2(300.0, y + 6.0), _config.couleurs.barre_certitude),
			"force": _creer_barre(couche_ui, Vector2(300.0, y + 6.0 + ECART_BARRE), _config.couleurs.barre_force),
		}
		y += 92.0

	_barre_sommeil = _creer_barre(couche_ui, Vector2(300.0, 60.0), _config.couleurs.barre_sommeil)
	_label_aide = _creer_label(couche_ui, Vector2(20.0, y + 10.0), 14)
	_label_aide.text = texte_aide()

	_poser_camera()

func _creer_label(couche: CanvasLayer, position: Vector2, taille: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", taille)
	label.position = position
	couche.add_child(label)
	return label

func _creer_barre(couche: CanvasLayer, position: Vector2, rgb: Array) -> Dictionary:
	var fond := ColorRect.new()
	fond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fond.size = Vector2(LARGEUR_BARRE, HAUTEUR_BARRE)
	fond.position = position
	fond.color = _couleur(_config.couleurs.barre_fond)
	couche.add_child(fond)

	var remplissage := ColorRect.new()
	remplissage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	remplissage.size = Vector2(0.0, HAUTEUR_BARRE)
	remplissage.position = position
	remplissage.color = _couleur(rgb)
	couche.add_child(remplissage)

	return {"fond": fond, "remplissage": remplissage}

func _creer_carre(taille: float, rgb: Array) -> ColorRect:
	var carre := ColorRect.new()
	carre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	carre.size = Vector2(taille, taille)
	carre.color = _couleur(rgb)
	add_child(carre)
	return carre

func _poser_camera() -> void:
	var decl: Dictionary = _config.get("camera", {})
	var pos: Array = decl.get("position", [0.0, 0.0])
	var camera := Camera2D.new()
	camera.position = Vector2(pos[0], pos[1])
	camera.zoom = Vector2(decl.get("zoom", 1.0), decl.get("zoom", 1.0))
	camera.enabled = true
	add_child(camera)

static func _couleur(rgb: Array) -> Color:
	return Color(rgb[0], rgb[1], rgb[2])

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
