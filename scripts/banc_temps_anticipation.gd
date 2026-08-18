extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_temps_anticipation.tscn, PAS la
# scene principale -- run/main_scene reste banc_p1, coexiste avec les autres
# bancs). Chantier « perception du temps + anticipation », audit prealable
# audit_perception_croyance_memoire_prealable.md, lignes 7 et 8.
#
# COMPOSE SEPT MECANISMES DEJA FERMES, TOUS RIGOUREUSEMENT INCHANGES :
# scripts/horloge.gd, scripts/lumiere.gd, scripts/memoire_spatiale.gd,
# scripts/perception.gd, scripts/proximite.gd, scripts/deformation.gd,
# scripts/seuil_etat.gd -- plus scripts/monde.gd et scripts/banc_commun.gd.
# AUCUN .gd du coeur n'est touche par ce chantier, et AUCUN mecanisme neuf
# n'est ecrit : les deux lignes de l'audit etaient « CABLABLE » (7) et
# « PARTIELLEMENT COUVERT » (8), la partie manquante de la 8 etant l'horloge
# du monde, livree entre-temps par scripts/horloge.gd.
#
# ---------------------------------------------------------------------------
# CE QU'IL DOIT MONTRER
# ---------------------------------------------------------------------------
# 1. LE COLON PERCOIT LE TEMPS SANS AUCUNE HORLOGE INTERNE. La seule grandeur
#    lue est la FORCE d'un souvenir (memoire_spatiale.gd). Deux reperes : l'un
#    reste a portee et reste donc « recent » pour toujours ; l'autre part a
#    t=3 s et traverse les trois cles a mesure que sa force decroit.
#    epigenetique.gd:age_marque EST un horodatage reel, et il est ECARTE
#    EXPRES (l'audit le nomme) : l'utiliser contredirait la ligne.
# 2. LE CODE NE MANIPULE QUE DES CLES. « C'etait hier » n'apparait nulle part
#    ici -- le cablage rend "souvenir.recent", le label le traduit par
#    data/textes.json, PREMIER fichier i18n du depot. Ajouter une langue = une
#    cle dans ce fichier-la, zero ligne ici (CLAUDE.md, INTERNATIONALISATION).
# 3. LE TEMPS DU MONDE TOURNE. horloge.gd rend l'heure ET la saison ; le fond
#    suit le jour et la nuit par lumiere.gd:soleil. Une saison dure 16 s.
# 4. VIVRE DES SAISONS REND PREVOYANT. A chaque CHANGEMENT de saison, le
#    cablage incremente la propriete plate 'cycles_vecus' de chaque colon ;
#    seuil_etat.gd la compare a 'seuil_prevoyance' et pose l'etat 'prevoyant'.
#    Le vieux l'est des le premier pas, l'adulte le devient a t=32 s, le jeune
#    ne l'est pas dans la fenetre observee.
# 5. UN PREVOYANT ANTICIPE, ET UN VIEUX ANTICIPE PLUS. Pendant la saison
#    declaree avant l'hiver, un colon prevoyant pose la deformation
#    'anticipation' sur la propriete de stockage : la saillance du grenier est
#    multipliee par (1 + biais) POUR LUI SEUL. Le jeune traverse le meme
#    automne sans rien poser -- son biais reste nul, le grenier ne monte pas.
#
# ---------------------------------------------------------------------------
# QUATRE DECISIONS DE CE CABLAGE, dites plutot que masquees
# ---------------------------------------------------------------------------
# (a) 'cycles_vecus' EST UNE PROPRIETE PLATE, accumulee ici. Patron
#     'degats_impact_cumules'/'duree_maladie_cumulee'/'dose_radiation_cumulee',
#     cinq precedents, zero mecanisme. epigenetique.gd (patron
#     'accoutumance_froid') a ete ECARTE et la raison est ecrite en donnee :
#     un appel PAR CYCLE est un intervalle enorme, et avec un taux de
#     decroissance non nul la marque est effacee entre deux poses et
#     n'accumule JAMAIS rien. stade.gd aussi, structurellement : il porte la
#     garde « JAMAIS un retour en arriere » alors qu'une saison est CYCLIQUE.
# (b) LE GATE EST UN ETAT, L'AMPLITUDE EST UN COMPTE. 'prevoyant' dit SI le
#     colon anticipe (marqueur pur, data/etats.json) ; c'est 'cycles_vecus'
#     qui dit COMBIEN, via le debit pose (biais_de_base + gain_par_cycle *
#     cycles_vecus, patron banc_psycho_social.gd:ardeur_combat). Un etat ne
#     porte qu'un nom -- il ne sait pas dire « beaucoup plus ». ECART A DIRE :
#     tant que le gate est ferme, le biais du jeune est EXACTEMENT nul ; sa
#     'base_innee' de 0.1 ne lui donne pas un petit biais, elle le place plus
#     haut sur le MEME compteur que le vieux, donc plus pres du seuil qu'un
#     colon qui naitrait a 0.0, et prevoyant plus tot. C'est la lecture
#     retenue des deux phrases de la consigne (« le jeune n'anticipe pas » /
#     « un jeune anticipe un tout petit peu ») ; l'autre lecture -- un
#     plancher de biais hors gate -- tiendrait en une ligne dans
#     poser_anticipation, elle n'a pas ete prise seule.
# (c) LE PLAFOND DU BIAIS EST DU CABLAGE, jamais du mecanisme. Le coeur ne
#     borne jamais le haut et IL N'EXISTE AUCUN EQUILIBRE NATUREL (constat
#     ecrit quatre fois dans data/deformations.json) : tant que le debit de
#     pose depasse le taux, le registre monte lineairement et sans borne. Ce
#     fichier cesse de poser des que biais() atteint plafond_biais_anticipation
#     -- patron litteral de banc_psycho_social.gd et banc_menace_combat.gd. Et
#     poser() n'ayant AUCUN parametre de temps, la magnitude est multipliee par
#     delta ici, sans quoi le biais monterait a la vitesse de la machine.
# (d) LE PLAFOND DE FORCE AUSSI, meme raison : memoriser() est appele CHAQUE
#     TICK tant qu'un repere est vu, donc la force monterait sans fin.
#     plafonner_memoire l'ecrete -- patron banc_memoire_navigation.gd. Ecreter
#     la FORCE plutot que sauter l'appel a memoriser est le seul ordre correct :
#     gater l'appel figerait aussi la POSITION.
#
# LIMITE DITE, PAS MASQUEE : ce banc monte la couche 2 (proximite.gd) mais NI
# dominance.gd, NI agir.gd, NI ciblage.gd -- personne ne se deplace. Ce qu'il
# montre est que la SAILLANCE du grenier monte pour le prevoyant et pas pour le
# jeune ; que le colon aille effectivement le remplir demande la chaine
# complete de decision, et ce n'est pas ce chantier.
#
# COLONS, GRENIER ET REPERES CONSTRUITS A LA MAIN (pas Objet.fabriquer, meme
# statut que banc_memoire_navigation.gd/banc_grief.gd -- aucun materiau
# n'intervient). Positions en PIXELS, z = 0.0 TOUJOURS -- VERTICALITE.
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge les donnees et construit le monde et le rendu ;
#   _process appelle UNIQUEMENT avancer() et lit son resultat pour l'affichage
#   et la console -- aucune decision dans _process.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_temps_anticipation.gd) : construire_colon, construire_grenier,
#   construire_repere, heure_du_jour, saison_courante, luminosite_a,
#   position_repere, compter_cycles, est_prevoyant, magnitude_anticipation,
#   biais_anticipation, poser_anticipation, memoriser_percus,
#   plafonner_memoire, force_memorisee, cle_perception_temps, cle_souvenir,
#   texte, saillance_grenier, avancer, plus les textes d'affichage et de trace.

const Horloge = preload("res://scripts/horloge.gd")
const Lumiere = preload("res://scripts/lumiere.gd")
const MemoireSpatiale = preload("res://scripts/memoire_spatiale.gd")
const Perception = preload("res://scripts/perception.gd")
const Proximite = preload("res://scripts/proximite.gd")
const Deformation = preload("res://scripts/deformation.gd")
const SeuilEtat = preload("res://scripts/seuil_etat.gd")
const Monde = preload("res://scripts/monde.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")

var _config: Dictionary = {}
var _textes: Dictionary = {}
var _catalogue_canaux: Dictionary = {}
var _catalogue_lumiere: Dictionary = {}
var _catalogue_memoire: Dictionary = {}
var _catalogue_profils: Dictionary = {}
var _catalogue_deformations: Dictionary = {}
var _catalogue_seuils_etat: Dictionary = {}

var _monde
var _colons: Array = []
var _grenier: Dictionary = {}
var _reperes: Array = []

var _noeuds_colons: Array = []
var _noeud_grenier: ColorRect
var _noeuds_reperes: Array = []
var _fond: ColorRect
var _label_horloge: Label
var _labels_colons: Array = []

var _temps := 0.0
var _prochain_print := 0.0

func _ready() -> void:
	_config = _charger_json("res://data/banc_temps_anticipation.json")
	_textes = _charger_json("res://data/textes.json")
	_catalogue_canaux = _charger_json("res://data/canaux.json")
	_catalogue_lumiere = _charger_json("res://data/lumiere.json")
	_catalogue_memoire = _charger_json("res://data/memoire_spatiale.json")
	_catalogue_profils = _charger_json("res://data/profils_saillance.json")
	_catalogue_deformations = _charger_json("res://data/deformations.json")
	_catalogue_seuils_etat = _charger_json("res://data/seuils_etat.json")

	var groupes: Array = []
	for decl in _config.colons:
		var colon := construire_colon(decl, _config)
		_colons.append(colon)
		groupes.append({"choses": [colon], "type": String(decl.type)})
	_grenier = construire_grenier(_config)
	groupes.append({"choses": [_grenier], "type": String(_config.grenier.type)})
	for decl in _config.reperes:
		var repere := construire_repere(decl)
		_reperes.append(repere)
		groupes.append({"choses": [repere], "type": String(decl.type)})
	_monde = BancCommun.monde_depuis(groupes)

	_creer_rendu()
	print(ligne_pose_initiale(_config))

func _process(delta: float) -> void:
	_temps += delta
	var bilan := avancer(
		_colons, _grenier, _reperes, _monde, _config,
		_catalogue_canaux, _catalogue_lumiere, _catalogue_memoire,
		_catalogue_profils, _catalogue_deformations, _catalogue_seuils_etat,
		_temps, delta)
	_rafraichir(bilan)

	if bool(bilan.changement_saison):
		print(ligne_saison(_temps, bilan))
	for etat in bilan.colons:
		if bool(etat.vient_de_devenir_prevoyant):
			print(ligne_prevoyance(_temps, etat))
		if bool(etat.commence_a_anticiper):
			print(ligne_anticipation(_temps, etat))
	if _temps >= _prochain_print:
		_prochain_print = _temps + float(_config.intervalle_print)
		print(ligne_trace(_temps, bilan))

# ---------------------------------------------------------------------------
# Fonctions PURES, testables headless (voir test_banc_temps_anticipation.gd)
# ---------------------------------------------------------------------------

# Le colon porte SEPT choses et rien d'autre :
# - le canal de perception (lu par perception.gd) ;
# - memoire_spatiale, STRUCTURELLE pour memoire_spatiale.gd (sa cle absente
#   alarme) -- posee VIDE ici, jamais oubliee ;
# - forme, dont memoire_spatiale.gd ne lit que 'biais' : a 0.0 ici, parce que
#   ce banc mesure la FORCE d'un souvenir, jamais la derive de sa position (ce
#   sujet-la est celui de banc_memoire_navigation.gd, et un biais non nul
#   deplacerait un point que ce banc n'affiche meme pas) ;
# - deformation_sources ET deformation_etat, TOUTES DEUX STRUCTURELLES pour
#   deformation.gd -- et poser() REFUSE une source absente de la premiere ;
# - etats_actifs et seuils_etat_memoire, le couple que seuil_etat.gd mute ;
# - 'cycles_vecus' (initialise a la valeur declaree, jamais a zero -- voir
#   'base_innee' en donnee) et 'seuil_prevoyance', les deux nombres plats que
#   data/seuils_etat.json:prevoyance compare.
# 'derniere_saison' est posee VIDE : le premier appel a compter_cycles
# l'inscrit SANS incrementer -- sans quoi le tout premier tick compterait un
# changement de saison qui n'a pas eu lieu.
static func construire_colon(decl: Dictionary, config: Dictionary) -> Dictionary:
	var pos: Array = decl.position
	return {
		"id": decl.id,
		"position": Vector3(pos[0], pos[1], pos[2]),
		"proprietes": {
			"nom": decl.nom,
			"canaux": [config.nom_canal_vue],
			"canaux_config": {
				config.nom_canal_vue: {"portee": float(config.portee_vue), "angle": 360.0},
			},
			"memoire_spatiale": {},
			"forme": {"biais": 0.0},
			"deformation_sources": [config.source_deformation],
			"deformation_etat": {},
			"etats_actifs": [],
			"seuils_etat_memoire": {},
			"cycles_vecus": float(decl.cycles_vecus),
			"seuil_prevoyance": float(config.seuil_prevoyance),
			"derniere_saison": "",
		},
	}

# Le grenier porte DEUX choses : la propriete que la deformation vise (nommee
# EN DONNEE, le cablage ne teste jamais `type == "grenier"`) et sa reference de
# profil de saillance, resolue par proximite.gd dans le catalogue PARTAGE.
static func construire_grenier(config: Dictionary) -> Dictionary:
	var decl: Dictionary = config.grenier
	var pos: Array = decl.position
	return {
		"id": decl.id,
		"position": Vector3(pos[0], pos[1], pos[2]),
		"proprietes": {
			config.nom_propriete_stockage: true,
			"profil_saillance": decl.profil_saillance,
		},
	}

# Un repere ne porte QUE le marqueur qui le rend digne d'etre retenu -- aucun
# profil_saillance : proximite.gd l'ignore donc totalement, il n'existe que
# pour la memoire. Sans quoi il concurrencerait le grenier dans la saillance et
# brouillerait la seule chose que ce banc mesure de ce cote-la.
static func construire_repere(decl: Dictionary) -> Dictionary:
	var pos: Array = decl.position_initiale
	return {
		"id": decl.id,
		"position": Vector3(pos[0], pos[1], pos[2]),
		"proprietes": {"repere": true, "nom": decl.nom},
	}

# L'heure et la saison passent par horloge.gd, mecanisme du coeur -- jamais un
# fmod recopie ici. Contrairement a banc_memoire_navigation.gd (jour fige a
# duree_jour_secondes 0.0), le temps TOURNE reellement : c'est le sujet.
static func heure_du_jour(temps: float, config: Dictionary) -> float:
	var cycle: Dictionary = config.cycle
	return Horloge.heure(
		temps, float(cycle.duree_jour_secondes), float(cycle.heures_par_jour), float(cycle.heure_depart))

# L'ORDRE des saisons vit en donnee (cycle.saisons) : horloge.gd ne sait pas
# quelle saison suit laquelle, et ne connait aucun nom de saison.
static func saison_courante(temps: float, config: Dictionary) -> String:
	var cycle: Dictionary = config.cycle
	return Horloge.saison(
		temps, float(cycle.duree_jour_secondes), float(cycle.jours_par_saison), cycle.saisons)

static func luminosite_a(heure: float, config: Dictionary, catalogue_lumiere: Dictionary) -> float:
	return float(Lumiere.soleil(heure, float(config.cycle.latitude), catalogue_lumiere).intensite)

# Ou est un repere REELLEMENT. Deux positions declarees, aucune interpolation :
# un repere marque 's_eloigne' part apres 'delai_eloignement' et sort de la
# portee de vue -- sa force de souvenir se met alors a decroitre, et c'est elle,
# et elle seule, qui fera changer la cle de perception du temps.
static func position_repere(decl: Dictionary, temps: float, config: Dictionary) -> Vector3:
	var brut: Array = decl.position_initiale
	if bool(decl.s_eloigne) and temps >= float(config.delai_eloignement):
		brut = decl.position_lointaine
	return Vector3(brut[0], brut[1], brut[2])

# LE COMPTEUR DE CYCLES. Incremente de 1.0 A CHAQUE CHANGEMENT DE SAISON, jamais
# a chaque tick -- c'est ce qui separe une propriete cumulee par le temps ecoule
# (patron 'duree_maladie_cumulee', un debit * delta) d'un compte d'evenements.
# La saison PRECEDENTE vit sur le colon ('derniere_saison', une String, donc
# resumable en JSON), jamais sur le Node : cette fonction reste pure, et l'etat
# reste sur l'entite comme tout le reste du corps interne.
# Une 'derniere_saison' VIDE est le point de depart legitime : on l'inscrit sans
# rien incrementer. Rend les id des colons ayant compte un cycle ce passage.
static func compter_cycles(colons: Array, saison: String) -> Array:
	var comptes: Array = []
	for colon in colons:
		var proprietes: Dictionary = colon.proprietes
		var precedente: String = String(proprietes.get("derniere_saison", ""))
		if precedente != "" and precedente != saison:
			proprietes["cycles_vecus"] = float(proprietes.get("cycles_vecus", 0.0)) + 1.0
			comptes.append(colon.id)
		proprietes["derniere_saison"] = saison
	return comptes

# Lecture du GATE. Le nom de l'etat vient de la donnee, jamais du code : ce banc
# aurait le droit de nommer une categorie (CLAUDE.md, exception des bancs), il
# ne s'en sert pas -- toutes les autres cles de ce fichier sont deja nommees en
# donnee, en excepter une seule la rendrait invisible a une relecture.
static func est_prevoyant(colon: Dictionary, config: Dictionary) -> bool:
	return colon.proprietes.get("etats_actifs", []).has(String(config.etat_prevoyant))

# LE DEBIT de pose, par seconde. base + modulateur, patron exact de
# banc_psycho_social.gd:ardeur_combat -- la base est identique pour tous, seule
# l'experience differe. C'est ICI, et nulle part ailleurs, que vit « un vieux
# anticipe beaucoup plus » : meme catalogue, meme loi, un debit plus grand.
static func magnitude_anticipation(colon: Dictionary, config: Dictionary) -> float:
	return float(config.biais_de_base) + float(config.gain_par_cycle) * float(colon.proprietes.get("cycles_vecus", 0.0))

static func biais_anticipation(colon: Dictionary, config: Dictionary, catalogue_deformations: Dictionary) -> float:
	return Deformation.biais(
		colon, String(config.source_deformation), String(config.nom_propriete_stockage), catalogue_deformations)

# LA POSE. Trois gates, dans cet ordre, et aucun n'est contournable en donnee :
# 1. l'etat 'prevoyant' (un jeune traverse l'automne sans rien poser) ;
# 2. la saison declaree avant l'hiver (hors de cette saison, personne ne pose,
#    et le biais deja accumule REDESCEND par deformation.gd:avancer) ;
# 3. le PLAFOND (le coeur ne borne jamais le haut, aucun equilibre naturel
#    n'existe -- sans ce gate le registre monterait sans borne).
# La magnitude est multipliee par DELTA : poser() n'a aucun parametre de temps.
# Rend le biais APRES pose, pour la trace et pour l'affichage.
static func poser_anticipation(
	colon: Dictionary,
	saison: String,
	config: Dictionary,
	catalogue_deformations: Dictionary,
	delta: float,
) -> float:
	if not est_prevoyant(colon, config):
		return biais_anticipation(colon, config, catalogue_deformations)
	if saison != String(config.saison_avant_hiver):
		return biais_anticipation(colon, config, catalogue_deformations)
	if biais_anticipation(colon, config, catalogue_deformations) >= float(config.plafond_biais_anticipation):
		return biais_anticipation(colon, config, catalogue_deformations)
	Deformation.poser(
		colon, String(config.source_deformation), String(config.nom_propriete_stockage),
		magnitude_anticipation(colon, config) * delta)
	return biais_anticipation(colon, config, catalogue_deformations)

# Ce que le colon voit ET juge digne d'etre retenu. Filtre sur une PROPRIETE
# nommee en donnee, jamais sur un type. perception.gd rend deja 'position' sur
# chaque entree : c'est celle-la qui est memorisee, jamais une position relue
# ailleurs (relire chose.position reintroduirait la telepathie que
# memoire_spatiale.gd existe pour fermer).
static func memoriser_percus(
	colon: Dictionary,
	perceptions: Array,
	config: Dictionary,
	catalogue_memoire: Dictionary,
) -> Array:
	var ids: Array = []
	for entree in perceptions:
		if not bool(entree.chose.proprietes.get(config.nom_propriete_repere, false)):
			continue
		MemoireSpatiale.memoriser(colon, String(entree.chose.id), entree.position, catalogue_memoire)
		ids.append(entree.chose.id)
	return ids

# ECRETAGE AU PLAFOND -- du cablage, jamais un mecanisme (en-tete, decision (d)).
static func plafonner_memoire(colon: Dictionary, config: Dictionary) -> float:
	var plafond: float = float(config.plafond_force)
	var ecrete := 0.0
	var registre: Dictionary = colon.proprietes.memoire_spatiale
	for chose_id in registre:
		var entree: Dictionary = registre[chose_id]
		var force: float = float(entree.get("force", 0.0))
		if force > plafond:
			ecrete += force - plafond
			entree["force"] = plafond
	return ecrete

static func force_memorisee(colon: Dictionary, chose_id: String) -> float:
	return float(colon.proprietes.memoire_spatiale.get(chose_id, {}).get("force", 0.0))

# LA PERCEPTION DU TEMPS. Une fonction PURE force -> CLE, et rien d'autre : pas
# une phrase, pas une concatenation, pas un nombre de secondes. Les deux seuils
# vivent en donnee de banc. C'est tout le mecanisme de la ligne 7 de l'audit --
# « CABLABLE, c'est une LECTURE, aucun mecanisme neuf ».
static func cle_perception_temps(force: float, config: Dictionary) -> String:
	if force >= float(config.seuil_souvenir_recent):
		return "souvenir.recent"
	if force >= float(config.seuil_souvenir_ancien):
		return "souvenir.ancien"
	return "souvenir.tres_ancien"

# Rend "" quand la chose n'a JAMAIS ete memorisee, ou quand son souvenir est
# tombe sous le plancher et a ete RETIRE du registre par memoire_spatiale.gd.
# Ne pas savoir n'est pas savoir vaguement : rendre "souvenir.tres_ancien" pour
# une chose jamais vue afficherait « Il y a longtemps » a propos de rien.
static func cle_souvenir(colon: Dictionary, chose_id: String, config: Dictionary) -> String:
	if not colon.proprietes.memoire_spatiale.has(chose_id):
		return ""
	return cle_perception_temps(force_memorisee(colon, chose_id), config)

# LA SEULE PORTE DE SORTIE VERS UN TEXTE JOUEUR. Le code n'a jamais tenu que la
# cle ; ici elle est resolue dans data/textes.json, a la langue declaree en
# donnee. Une cle absente rend la cle elle-meme -- visible a l'ecran, donc
# corrigee, jamais un texte vide qui masquerait le trou (et jamais un texte de
# repli ecrit en dur ici, ce qui serait exactement la faute que la regle
# d'INTERNATIONALISATION interdit).
static func texte(cle: String, config: Dictionary, textes: Dictionary) -> String:
	if cle == "":
		return ""
	return String(textes.get(String(config.langue), {}).get(cle, cle))

# La saillance du grenier TELLE QUE CE COLON LA VOIT. proximite.gd applique
# lui-meme le biais de deformation du colon (saillance *= 1 + biais pour une
# source de sens 'monte') -- ce fichier ne recalcule rien, il lit. Rend 0.0 si
# le grenier n'est pas percu ou n'est pas saillant a cette distance.
static func saillance_grenier(
	perceptions: Array,
	colon: Dictionary,
	config: Dictionary,
	catalogue_profils: Dictionary,
	catalogue_deformations: Dictionary,
) -> float:
	var evaluees: Array = Proximite.evaluer(perceptions, colon, catalogue_profils, catalogue_deformations)
	for entree in evaluees:
		if entree.chose.id == config.grenier.id:
			return float(entree.saillance)
	return 0.0

# LE PAS COMPLET, seul appele par _process (qui ne calcule jamais rien
# lui-meme). ORDRE FIXE ET VOULU, chaque etape depend de la precedente :
#  1. l'heure et la SAISON viennent de horloge.gd, la luminosite de
#     lumiere.gd:soleil ;
#  2. les reperes sont poses a leur position REELLE du moment (le Dictionary
#     est celui que Monde tient par reference -- monde.gd relit chose.position
#     a chaque requete, aucune reinscription n'est necessaire) ;
#  3. le COMPTE DE CYCLES d'abord, le SEUIL ensuite : dans cet ordre, la saison
#     qui vient de changer est prise en compte le tick meme ; l'ordre inverse
#     decalerait chaque bascule d'un tick, en silence ;
#  4. seuil_etat.gd pose ou retire 'prevoyant' -- catalogue PARTAGE passe tel
#     quel, ses autres entrees sont des chemins morts silencieux sur des colons
#     qui ne portent ni temperature, ni reserve, ni grief ;
#  5. par colon : perception, puis l'OUBLI (MemoireSpatiale.avancer) AVANT
#     l'observation -- dans cet ordre un repere vu ce tick est integralement
#     rafraichi, l'ordre inverse ferait decroitre une observation qui vient
#     d'arriver ; puis l'ecretage de force ;
#  6. la deformation DECROIT (Deformation.avancer) avant qu'on ne POSE, meme
#     raison exacte qu'au point 5 ;
#  7. la saillance du grenier est lue EN DERNIER, apres la pose : c'est celle
#     que le colon aurait maintenant.
# Rend un diagnostic de trace, jamais relu comme une source de verite.
static func avancer(
	colons: Array,
	grenier: Dictionary,
	reperes: Array,
	monde,
	config: Dictionary,
	catalogue_canaux: Dictionary,
	catalogue_lumiere: Dictionary,
	catalogue_memoire: Dictionary,
	catalogue_profils: Dictionary,
	catalogue_deformations: Dictionary,
	catalogue_seuils_etat: Dictionary,
	temps: float,
	delta: float,
) -> Dictionary:
	var heure := heure_du_jour(temps, config)
	var saison := saison_courante(temps, config)
	var luminosite := luminosite_a(heure, config, catalogue_lumiere)

	for i in range(reperes.size()):
		reperes[i].position = position_repere(config.reperes[i], temps, config)

	var comptes := compter_cycles(colons, saison)
	var bascules := SeuilEtat.avancer(colons, catalogue_seuils_etat)

	var etats: Array = []
	var biais_max := 0.0
	for colon in colons:
		var biais_avant := biais_anticipation(colon, config, catalogue_deformations)

		var perceptions: Array = Perception.percevoir(colon, monde, catalogue_canaux)
		MemoireSpatiale.avancer(colon, delta, catalogue_memoire)
		memoriser_percus(colon, perceptions, config, catalogue_memoire)
		plafonner_memoire(colon, config)

		Deformation.avancer(colon, delta, catalogue_deformations)
		var biais := poser_anticipation(colon, saison, config, catalogue_deformations, delta)
		if biais > biais_max:
			biais_max = biais

		var souvenirs: Dictionary = {}
		for decl in config.reperes:
			souvenirs[decl.id] = {
				"nom": decl.nom,
				"force": force_memorisee(colon, String(decl.id)),
				"cle": cle_souvenir(colon, String(decl.id), config),
			}

		var seuil_trace := float(config.seuil_trace_anticipation)
		etats.append({
			"id": colon.id,
			"nom": colon.proprietes.nom,
			"cycles_vecus": float(colon.proprietes.cycles_vecus),
			"prevoyant": est_prevoyant(colon, config),
			"vient_de_devenir_prevoyant": bascules.has(colon.id),
			"biais": biais,
			"commence_a_anticiper": biais_avant < seuil_trace and biais >= seuil_trace,
			"saillance_grenier": saillance_grenier(perceptions, colon, config, catalogue_profils, catalogue_deformations),
			"souvenirs": souvenirs,
		})

	return {
		"heure": heure,
		"saison": saison,
		"luminosite": luminosite,
		"changement_saison": not comptes.is_empty(),
		"biais_max": biais_max,
		"colons": etats,
	}

# ---------------------------------------------------------------------------
# Textes. DEUX REGIMES A NE PAS CONFONDRE (voir data/textes.json).
# - Les LABELS a l'ecran sont vus par le joueur : toute part de texte qui en
#   vient passe par data/textes.json (ici, les trois cles 'souvenir.*').
# - Les traces console (print) ne le sont pas : ce sont des sorties de mise au
#   point, la regle d'INTERNATIONALISATION ne les vise pas (« les chaines
#   visibles par le joueur »). Meme convention que banc_memoire_navigation.gd.
# Le reste des labels (chiffres, noms de saison, noms de colon) vient de la
# DONNEE, jamais d'une chaine ecrite ici -- ce qui reste en dur dans ce fichier
# est de la ponctuation et des unites.
# ---------------------------------------------------------------------------

static func texte_horloge(bilan: Dictionary) -> String:
	return "heure = %.1f    saison : %s    luminosite = %.2f" % [
		float(bilan.heure), String(bilan.saison), float(bilan.luminosite),
	]

static func texte_colon(etat: Dictionary, config: Dictionary, textes: Dictionary) -> String:
	var lignes: String = "%s\ncycles vecus = %.1f / %.1f    %s\nbiais d'anticipation = %.2f    saillance du grenier = %.2f" % [
		String(etat.nom),
		float(etat.cycles_vecus), float(config.seuil_prevoyance),
		"PREVOYANT" if bool(etat.prevoyant) else "-",
		float(etat.biais), float(etat.saillance_grenier),
	]
	for chose_id in etat.souvenirs:
		var souvenir: Dictionary = etat.souvenirs[chose_id]
		var rendu: String = texte(String(souvenir.cle), config, textes)
		lignes += "\n%s : %s" % [String(souvenir.nom), rendu if rendu != "" else "(aucun souvenir)"]
	return lignes

static func ligne_pose_initiale(config: Dictionary) -> String:
	return "t=0.0 trois colons poses (cycles vecus : %.1f / %.1f / %.1f, seuil %.1f) ; une saison dure %.1f s" % [
		float(config.colons[0].cycles_vecus), float(config.colons[1].cycles_vecus),
		float(config.colons[2].cycles_vecus), float(config.seuil_prevoyance),
		float(config.cycle.duree_jour_secondes) * float(config.cycle.jours_par_saison),
	]

static func ligne_saison(t: float, bilan: Dictionary) -> String:
	var comptes: String = ""
	for etat in bilan.colons:
		comptes += " %s=%.1f" % [String(etat.nom), float(etat.cycles_vecus)]
	return "t=%.1f CHANGEMENT DE SAISON -> %s ; cycles vecus :%s" % [t, String(bilan.saison), comptes]

static func ligne_prevoyance(t: float, etat: Dictionary) -> String:
	return "t=%.1f %s : etat 'prevoyant' %s (cycles vecus = %.1f)" % [
		t, String(etat.nom), "POSE" if bool(etat.prevoyant) else "retire", float(etat.cycles_vecus),
	]

static func ligne_anticipation(t: float, etat: Dictionary) -> String:
	return "t=%.1f %s ANTICIPE -- biais %.2f, saillance du grenier %.2f" % [
		t, String(etat.nom), float(etat.biais), float(etat.saillance_grenier),
	]

static func ligne_trace(t: float, bilan: Dictionary) -> String:
	var corps: String = ""
	for etat in bilan.colons:
		corps += " | %s cycles=%.1f %s biais=%.2f saillance=%.2f" % [
			String(etat.nom), float(etat.cycles_vecus),
			"PREV" if bool(etat.prevoyant) else "    ",
			float(etat.biais), float(etat.saillance_grenier),
		]
	return "t=%.1f h=%.1f %s%s" % [t, float(bilan.heure), String(bilan.saison), corps]

# ---------------------------------------------------------------------------
# Rendu (impur, Node) -- aucune decision, seulement des noeuds et une camera.
# ---------------------------------------------------------------------------

func _rafraichir(bilan: Dictionary) -> void:
	_fond.color = _couleur_melee(
		_config.couleurs.fond_nuit, _config.couleurs.fond_jour, float(bilan.luminosite))

	# Le grenier chauffe avec le biais MAXIMAL de la colonie, jamais avec une
	# saillance : une saillance depend de la distance du colon qui regarde, le
	# biais non -- c'est lui, et lui seul, le signal d'anticipation.
	var part: float = clamp(float(bilan.biais_max) / float(_config.plafond_biais_anticipation), 0.0, 1.0)
	_noeud_grenier.color = _couleur_melee(
		_config.couleurs.grenier_calme, _config.couleurs.grenier_anticipe, part)

	for i in range(_reperes.size()):
		var pos_repere := Vector2(_reperes[i].position.x, _reperes[i].position.y)
		_noeuds_reperes[i].position = pos_repere - _noeuds_reperes[i].size / 2.0

	for i in range(bilan.colons.size()):
		var etat: Dictionary = bilan.colons[i]
		_noeuds_colons[i].color = _couleur(
			_config.couleurs.colon_prevoyant if bool(etat.prevoyant) else _config.couleurs.colon)
		_labels_colons[i].text = texte_colon(etat, _config, _textes)

	_label_horloge.text = texte_horloge(bilan)

func _creer_rendu() -> void:
	_fond = ColorRect.new()
	_fond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fond.size = Vector2(6000.0, 5000.0)
	_fond.position = Vector2(-3000.0, -2500.0)
	add_child(_fond)

	_noeud_grenier = _creer_marqueur(float(_config.taille_grenier), _config.couleurs.grenier_calme)
	_noeud_grenier.position = Vector2(_grenier.position.x, _grenier.position.y) - _noeud_grenier.size / 2.0

	# Position posee des la construction, jamais laissee au premier _process :
	# sinon les deux reperes s'affichent une image a l'origine avant de sauter
	# a leur place.
	for repere in _reperes:
		var noeud_repere := _creer_marqueur(float(_config.taille_repere), _config.couleurs.repere)
		noeud_repere.position = Vector2(repere.position.x, repere.position.y) - noeud_repere.size / 2.0
		_noeuds_reperes.append(noeud_repere)

	for colon in _colons:
		var noeud := _creer_marqueur(float(_config.taille_colon), _config.couleurs.colon)
		noeud.position = Vector2(colon.position.x, colon.position.y) - noeud.size / 2.0
		_noeuds_colons.append(noeud)

	var couche_ui := CanvasLayer.new()
	add_child(couche_ui)

	_label_horloge = Label.new()
	_label_horloge.add_theme_font_size_override("font_size", 20)
	_label_horloge.position = Vector2(20.0, 14.0)
	couche_ui.add_child(_label_horloge)

	for i in range(_colons.size()):
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 15)
		label.position = Vector2(20.0 + 380.0 * float(i), 60.0)
		couche_ui.add_child(label)
		_labels_colons.append(label)

	_poser_camera()

func _creer_marqueur(taille: float, rgb: Array) -> ColorRect:
	var noeud := ColorRect.new()
	noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noeud.size = Vector2(taille, taille)
	noeud.color = _couleur(rgb)
	add_child(noeud)
	return noeud

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

static func _couleur_melee(rgb_bas: Array, rgb_haut: Array, part: float) -> Color:
	return _couleur(rgb_bas).lerp(_couleur(rgb_haut), clamp(part, 0.0, 1.0))

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
