extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_parasites_reproduction.tscn, PAS
# la scene principale -- run/main_scene reste banc_p1). Chantier « parasites +
# reproduction animale » (audit_ecosysteme_vivant_prealable.md, lignes 10
# « PARASITES -- troisieme espece » et 11 « REPRODUCTION ET POPULATION »,
# toutes deux au verdict CABLABLE, avec les corrections de l'audit reprises
# telles quelles -- voir CE QUE L'AUDIT CORRIGEAIT plus bas).
#
# UN GAMEPLAY EST UNE COMPOSITION (CLAUDE.md) : ce fichier n'ecrit AUCUNE
# mecanique. Il compose ONZE mecanismes du coeur DEJA FERMES, tous INCHANGES --
# scripts/charge.gd (infestation par contact), scripts/etat_duree.gd
# (incubation puis infestation, qui expirent seules), scripts/etat_effectif.gd
# (vitesse modulee par 'infeste', ecrasee par les deux morts),
# scripts/seuil_etat.gd (mort par parasitose, fin de vie du parasite),
# scripts/depense.gd (la vigueur qui remonte), scripts/senescence.gd (l'age),
# scripts/stade.gd (la maturite), scripts/accouplement.gd (rencontre sexuee),
# scripts/gestation.gd (les deux points d'entree : avancer pour les sexues,
# poser pour les asexues), scripts/heredite.gd (le kit genetique du petit),
# scripts/expression.gd (le gene traduit en vitesse), plus scripts/monde.gd et
# scripts/banc_commun.gd. AUCUN MECANISME DU COEUR TOUCHE, AUCUN `.gd` neuf du
# coeur.
#
# ENTITES CONSTRUITES A LA MAIN depuis data/banc_parasites_reproduction.json
# (patron dominant depuis banc_maladie.gd -- pas Objet.fabriquer, pas
# data/types.json). CONSEQUENCE DIRECTE ET VOULUE : aucune propriete neuve ne
# rejoint data/types.json, donc RIEN a enregistrer dans les trois registres de
# scripts/test_lint_donnees.gd.
#
# DEUX ESPECES, UN SEUL CODE : hote et parasite portent le MEME gabarit de
# corps interne (age/stade/stades_config/mode_reproduction/role_gestation/espece_reproduction/
# stades_fertiles/reproduction_ref/genes_actifs/genes_etat/
# marques_epigenetiques), seules leurs VALEURS different. Les deux traversent
# les memes appels, sans un seul cas particulier. Ce qui les separe tient
# entierement a DEUX ABSENCES, jamais a une branche :
#   - le parasite ne porte NI le canal 'etats.infestation' NI
#     'charge_parasitaire_cumulee' -- charge.gd le saute (etats absent) et
#     l'entree de seuil 'mort_parasitose' est pour lui un chemin mort
#     silencieux (propriete_continue absente : seuil_etat.gd rend false AVANT
#     meme d'ecrire sa memoire) ;
#   - l'hote ne porte PAS 'seuil_longevite' -- l'entree 'fin_vie' replie donc
#     sur INF et ne se declenche JAMAIS pour lui (meme idiome que « un objet
#     sans point_fusion ne fond jamais »). Il vieillit quand meme : il en a
#     besoin pour ses stades.
# Les deux entrees de seuil coexistent donc dans le MEME catalogue sans
# jamais se croiser, par la SEULE ARITHMETIQUE.
#
# CE QUE L'AUDIT CORRIGEAIT, ET QUI EST TENU ICI :
# (1) L'INFECTION N'EST PAS UN TIRAGE. Aucun RNG n'intervient dans
#     l'infestation : charge.gd accumule a portee, exactement comme
#     banc_maladie.gd -- rester pres d'un parasite finit par infester, sans un
#     seul de. Les deux seuls RNG de ce fichier sont les destinations de
#     promenade et la mutation d'heredite.gd, tous deux SEEDES depuis la
#     donnee (CLAUDE.md).
# (2) LE CANAL N'EST JAMAIS RETIRE. banc_maladie.gd retire pour toujours le
#     canal receveur d'un colon contamine (« porteur ou mort, il ne redevient
#     jamais susceptible »). Un parasite se REATTRAPE : le canal reste sur
#     l'hote toute sa vie, la charge peut redescendre (taux_decroissance 0.5,
#     la ou banc_maladie.gd a un cliquet a 0.0) et remonter. La garde contre
#     une double incubation est donc un GATE DE CABLAGE -- peut_incuber(),
#     patron exact de banc_elimination_salete.gd:_peut_incuber -- et jamais le
#     retrait du canal.
# (3) LE NON-PORTEUR PERD SA GESTATION A LA NAISSANCE. L'hote declare
#     role_gestation "les_deux" : l'espece n'a pas de sexes, n'importe lequel
#     des deux peut porter, donc accouplement.gd pose 'gestation' des deux
#     cotes. Laisser les deux avancer ferait naitre DEUX petits d'un seul
#     accouplement.
#     Ce banc tranche par TRI ALPHABETIQUE des deux id (deterministe, aucune
#     propriete neuve, aucun concept de sexe -- meme nature d'arbitrage que
#     etat_effectif.gd entre deux ecraseurs), avec un repli : si le porteur
#     designe est mort ou a quitte le monde, le survivant gestate, sans quoi la
#     portee serait perdue. Et A LA NAISSANCE, le cablage retire 'gestation' du
#     porteur ET du partenaire -- sans ce second retrait, le non-porteur
#     resterait indisponible POUR TOUJOURS (garde d'accouplement.gd : un
#     partenaire percu qui porte deja 'gestation' est ignore), ce qui suffit a
#     eteindre une population en une generation.
#
# CE QUE LE CABLAGE VIDE EN PLUS, ET QUI N'ETAIT DIT NULLE PART :
# 'accouplement_accumulateur' des DEUX parents. accouplement.gd n'a AUCUNE
# decroissance -- son accumulation est IRREVERSIBLE par construction (son
# en-tete : « une exposition interrompue puis reprise CONTINUE d'accumuler »).
# Sans ce vidage, une gestation retiree serait REPOSEE AU TICK SUIVANT (le
# seuil est deja franchi et le reste pour toujours), le couple pondrait en
# rafale, et surtout la vitesse reduite d'un hote infeste cesserait de ralentir
# sa reproduction des la seconde portee -- le couplage que ce banc existe pour
# montrer serait faux, tous tests verts.
#
# LES DEUX BOUCLES, ET CE QUI LES FERME :
#   population dense -> un parasite trouve assez d'hotes PAR PARASITE a portee
#   -> il pond (gate de cablage, gestation.gd:poser en mode asexuee) -> plus de
#   parasites -> plus d'infestations -> plus de morts -> population basse -> le
#   gate se referme, aucun parasite neuf, et les parasites en place meurent de
#   leur 'seuil_longevite'. Le bras DESCENDANT vient de ces deux-la, et de
#   nulle part ailleurs : sans mortalite du parasite ET sans capacite de
#   charge, leur nombre ne pourrait que croitre (voir peut_pondre, RESULTAT
#   NEGATIF -- un gate sur le nombre d'hotes ABSOLU ne freine rien du tout, la
#   suite de tests a reellement PENDU dessus).
#   hote infeste -> vitesse x0.6 -> il croise moins souvent un partenaire ->
#   il accumule moins vite l'exposition mutuelle -> il se reproduit plus
#   lentement. GATE IMPLICITE, jamais un gate ecrit : accouplement.gd ne lit
#   aucune vitesse, il ne fait qu'accumuler tant que le partenaire est PERCU.
#
# LE GATE EXPLICITE, LUI, EST LA VIGUEUR : « reserves hautes pour s'accoupler ».
# accouplement.gd ne lit AUCUNE reserve (son en-tete : mode_reproduction,
# espece_reproduction, stades_fertiles, stade, perceptions -- rien d'autre) --
# c'est donc le banc qui refuse de l'appeler sous le seuil. Precedents exacts :
# banc_psycho_social.gd:directive_autorisee, banc_graisse_accoutumance.gd
# (gate sur manque_graisse), banc_elimination_salete.gd (gate sur cout_base
# pour qu'un mort cesse d'eliminer). La vigueur MONTE parce que son cout_base
# est NEGATIF (neutralite de depense.gd exploitee, jamais contournee --
# precedent, la jachere de banc_fertilite.gd) ; rien dans le coeur ne borne le
# HAUT d'une reserve, le plafond vit donc au CABLAGE (plafonner_vigueur, patron
# banc_fertilite.gd:plafonner_fertilite).
#
# PERCEPTION : ce banc N'APPELLE PAS perception.gd. accouplement.gd ne lit que
# la cle "chose" de chaque entree de perceptions (son en-tete) -- un test de
# DISTANCE suffit, et c'est exactement ce que rend monde.gd:choses_dans_rayon.
# Monter perception.gd exigerait de poser canaux/canaux_config sur des entites
# construites a la main, c'est-a-dire tout le vocabulaire du paquet 'percevant'
# pour n'en lire que la distance. ECART ASSUME au patron banc_reproduction.gd
# (qui, lui, fabrique de vrais colons par Objet.fabriquer et a donc deja ce
# vocabulaire). Les morts sont filtres DEUX FOIS -- ils quittent le Monde a la
# reconstruction, et perceptions_a_portee les ecarte quand meme : la
# reconstruction n'a lieu qu'aux ticks ou la composition change, il y a donc un
# tick ou un cadavre est encore enregistre.
#
# LES MORTS QUITTENT LE MONDE, PAS L'ECRAN : monde.gd n'a AUCUNE fonction de
# retrait (dette deja recensee, CARTE.md §6) -- le Monde est RECONSTRUIT DU
# NEANT avec les seuls vivants, ajoutes PAR REFERENCE (idiome
# banc_elimination_salete.gd/banc_menace_combat.gd/banc_grief.gd). Un mort
# reste dans la liste animee et a l'ecran (rouge, immobile) : il n'est plus
# percu, n'est plus une cause d'infestation, ne peut plus etre partenaire, mais
# le compteur continue de le compter -- une population qui s'effondre doit
# rester lisible.
#
# CONTROLES : clic gauche = ajouter/retirer les parasites (bistable -- s'il en
# reste un vivant, tous sont retires du monde ET de l'ecran ; sinon
# 'parasites_par_ajout' sont poses a des positions tirees de la RNG seedee) ;
# clic droit = accelerer le temps (bistable, x1 <-> facteur_temps_accelere --
# un simple facteur sur delta, aucune horloge separee).
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge les quatre fichiers de donnees, fabrique les
#   individus, cree le rendu. _unhandled_input tient les deux bascules.
#   _process appelle avancer(...) puis deplacer(...), imprime les traces,
#   redessine.
# - Fonctions statiques (pures, testables headless -- voir
#   test_banc_parasites_reproduction.gd) : fabriquer_individu/fabriquer_tout/
#   fabriquer_petit/causes_infestation/peut_incuber/est_mort/est_parasite/
#   stade_fertile/vigueur/vigueur_suffisante/poser_taux_vigueur/
#   plafonner_vigueur/vider_vigueur/perceptions_a_portee/voisinage/
#   peut_pondre/voisinage_supportable/est_porteur_de_gestation/
#   naissance_prete/monde_des_vivants/avancer/deplacer/etat_courant/compter,
#   plus les textes d'affichage et de log.

const Charge = preload("res://scripts/charge.gd")
const EtatDuree = preload("res://scripts/etat_duree.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")
const SeuilEtat = preload("res://scripts/seuil_etat.gd")
const Depense = preload("res://scripts/depense.gd")
const Senescence = preload("res://scripts/senescence.gd")
const Stade = preload("res://scripts/stade.gd")
const Accouplement = preload("res://scripts/accouplement.gd")
const Gestation = preload("res://scripts/gestation.gd")
const Heredite = preload("res://scripts/heredite.gd")
const ExpressionGenetique = preload("res://scripts/expression.gd")
const Monde = preload("res://scripts/monde.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")

const PROP_VITESSE := "vitesse"
const CANAL_INFESTATION := "infestation"
const MARQUEUR_EXPOSE := "expose_parasite"
const PROP_CUMUL := "charge_parasitaire_cumulee"
const PROP_PORTEUR := "porteur_parasite"
const NOM_VIGUEUR := "vigueur"
const ETAT_INCUBATION := "incube_parasite"
const ETAT_INFESTE := "infeste"
const ETAT_MORT_PARASITE := "mort_parasite"
const ETAT_MORT_VIEILLESSE := "mort_vieillesse"

const DISTANCE_ARRIVEE := 4.0
const TAILLE_POLICE_LABEL := 11

var _config: Dictionary = {}
var _etats: Dictionary = {}
var _reproduction: Dictionary = {}
var _heredite: Dictionary = {}
var _entites: Array = []
var _monde
var _compteurs: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _temps := 0.0
var _facteur_temps := 1.0
var _noeuds: Dictionary = {}
var _labels: Dictionary = {}
var _label_compteur: Label

func _ready() -> void:
	_config = _charger_json("res://data/banc_parasites_reproduction.json")
	_etats = _charger_json("res://data/etats.json")
	_reproduction = _charger_json("res://data/reproduction.json")
	_heredite = _charger_json("res://data/heredite.json")
	_rng.seed = int(_config.get("seed", 0))

	_entites = fabriquer_tout(_config)
	_monde = monde_des_vivants(_entites)
	_compteurs = {"tick": 0, "petits": 0, "parasites_nes": 0, "naissances": 0}
	for entite in _entites:
		_creer_rendu(entite)

	_label_compteur = Label.new()
	_label_compteur.position = Vector2(20.0, 10.0)
	add_child(_label_compteur)
	_poser_camera()
	_rafraichir_tout()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		_basculer_parasites()
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_facteur_temps = 1.0 if _facteur_temps > 1.0 else float(_config.facteur_temps_accelere)
		print(_ligne_temps(_temps, _facteur_temps))

func _process(delta: float) -> void:
	var pas: float = delta * _facteur_temps
	_temps += pas

	var resultat := avancer(_entites, _monde, _compteurs, pas, _config, _catalogues(), _rng)
	_monde = resultat.monde
	_compteurs = resultat.compteurs
	deplacer(_entites, _config.zone, _etats, _rng, pas)

	for id in resultat.incubations:
		print(_ligne_incubation(_temps, id))
	for id in resultat.declares:
		print(_ligne_declare(_temps, id))
	for id in resultat.gueris:
		print(_ligne_gueri(_temps, id))
	for entree in resultat.gestations:
		print(_ligne_gestation(_temps, entree.porteur_id, entree.partenaire_id))
	for entree in resultat.pontes:
		print(_ligne_ponte(_temps, entree.id, entree.hotes))
	for entree in resultat.naissances:
		print(_ligne_naissance(_temps, entree))
		_creer_rendu(_par_id(_entites, entree.id))
	for entree in resultat.morts:
		print(_ligne_mort(_temps, entree.id, entree.cause))

	_rafraichir_tout()

func _catalogues() -> Dictionary:
	return {"etats": _etats, "reproduction": _reproduction, "heredite": _heredite}

# ---- Fonctions PURES, testables headless (test_banc_parasites_reproduction.gd)

# Construit un individu depuis sa declaration (format de config.individus) et
# le gabarit de son espece (config.especes[decl.espece]). L'espece elle-meme
# est la CLE du gabarit -- elle devient proprietes.espece_reproduction, jamais
# recopiee une seconde fois dans la donnee (accouplement.gd compare cette
# propriete, jamais un type : « COMPATIBILITE PAR PROPRIETE, JAMAIS PAR TYPE »).
# Chaque Dictionary/Array du gabarit est DUPLIQUE (jamais partage entre
# individus -- bug d'aliasing deja ferme, voir banc_commun.gd:resoudre_chantier).
# TROIS CLES POSEES SOUS CONDITION, toutes trois par la seule donnee :
# 'seuil_longevite' si le gabarit en porte un (sinon l'entree de seuil 'fin_vie'
# replie sur INF pour cet individu) ; le canal receveur + le cumul + la reserve
# de vigueur si l'espece est celle de l'hote (sinon charge.gd, l'entree
# 'mort_parasitose' et depense.gd sont pour lui des chemins morts silencieux).
# Le gene est exprime UNE SEULE FOIS, ici : le rappeler chaque tick ferait
# diverger la vitesse sans borne (resultat negatif deja mesure deux fois,
# data/epigenetique.json -- expression.gd relit la valeur qu'il vient d'ecrire).
static func fabriquer_individu(decl: Dictionary, config: Dictionary) -> Dictionary:
	var espece: String = String(decl.espece)
	var gabarit: Dictionary = config.especes[espece]
	var pos: Array = decl.position
	var position3 := Vector3(pos[0], pos[1], pos[2])
	var proprietes: Dictionary = {
		"vitesse": float(gabarit.vitesse),
		"etats_actifs": [],
		"age": float(decl.get("age", 0.0)),
		"stade": "",
		"stades_config": gabarit.stades_config.duplicate(true),
		"mode_reproduction": String(gabarit.mode_reproduction),
		"espece_reproduction": espece,
		"role_gestation": String(gabarit.get("role_gestation", "")),
		"stades_fertiles": gabarit.stades_fertiles.duplicate(true),
		"reproduction_ref": String(gabarit.reproduction_ref),
		"genes_actifs": gabarit.genes_actifs.duplicate(true),
		"genes_etat": decl.get("genes_etat", {}).duplicate(true),
		"marques_epigenetiques": {},
	}
	if gabarit.has("seuil_longevite"):
		proprietes["seuil_longevite"] = float(gabarit.seuil_longevite)
	if espece == String(config.espece_hote):
		proprietes["etats"] = {CANAL_INFESTATION: config.canal_infestation.duplicate(true)}
		proprietes[PROP_CUMUL] = 0.0
		proprietes[PROP_PORTEUR] = 0.0
		proprietes["reserves"] = {NOM_VIGUEUR: config.canal_vigueur.duplicate(true)}
	var individu: Dictionary = {
		"id": String(decl.id),
		"position": position3,
		"destination": position3,
		"proprietes": proprietes,
	}
	var valeurs := ExpressionGenetique.exprimer(individu, config.catalogue_genes, {}, {})
	ExpressionGenetique.appliquer(individu, valeurs)
	Stade.avancer(individu)
	return individu

static func fabriquer_tout(config: Dictionary) -> Array:
	var entites: Array = []
	for decl in config.individus:
		entites.append(fabriquer_individu(decl, config))
	return entites

# Le petit herite du kit rendu par heredite.gd (mode lu sur le parent :
# 'sexuee' melange les deux tableaux d'alleles, 'asexuee' recopie celui du
# parent unique) puis passe par EXACTEMENT la meme fabrication que ses
# parents -- aucun chemin special pour un nouveau-ne, il repart a age 0.0 et
# doit grandir comme eux. Heredite.fabriquer_genes_enfant EXIGE que le parent
# porte encore 'gestation' : cette fonction doit donc etre appelee AVANT que le
# cablage ne la retire. catalogue_epigenetique VIDE : aucune entite de ce banc
# ne pose jamais de marque, le parametre n'est jamais consulte (meme geste que
# banc_reproduction.gd).
static func fabriquer_petit(id: String, parent: Dictionary, config: Dictionary, catalogues: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var kit := Heredite.fabriquer_genes_enfant(parent, catalogues.heredite, {}, rng)
	var offset: Array = config.offset_petit
	var position: Vector3 = parent.position + Vector3(offset[0], offset[1], offset[2])
	var petit := fabriquer_individu({
		"id": id,
		"espece": String(parent.proprietes.espece_reproduction),
		"position": [position.x, position.y, position.z],
		"age": 0.0,
		"genes_etat": kit.genes_etat,
	}, config)
	petit.proprietes["marques_epigenetiques"] = kit.marques_epigenetiques
	return petit

static func est_mort(entite: Dictionary) -> bool:
	var actifs: Array = entite.proprietes.get("etats_actifs", [])
	return actifs.has(ETAT_MORT_PARASITE) or actifs.has(ETAT_MORT_VIEILLESSE)

static func est_parasite(entite: Dictionary, config: Dictionary) -> bool:
	return String(entite.proprietes.get("espece_reproduction", "")) == String(config.espece_parasite)

static func stade_fertile(entite: Dictionary) -> bool:
	var fertiles: Array = entite.proprietes.get("stades_fertiles", [])
	return fertiles.has(entite.proprietes.get("stade", ""))

# Une cause par PARASITE vivant (poids_parasite) et une par HOTE contagieux
# (porteur_parasite > 0.0, poids_porteur -- deux fois plus faible : un hote
# transmet moins bien que la bete elle-meme). Comptage IMPLICITE, jamais
# comptage.gd : charge.gd somme deja les poids de toutes les causes a portee,
# deux parasites cote a cote infestent deux fois plus vite sans une ligne de
# plus (meme decision que banc_maladie.gd/banc_contagion.gd/
# banc_elimination_salete.gd).
static func causes_infestation(entites: Array, config: Dictionary) -> Array:
	var causes: Array = []
	for entite in entites:
		if est_mort(entite):
			continue
		if est_parasite(entite, config):
			causes.append({"position": entite.position, "poids": float(config.poids_parasite), "source_id": String(entite.id)})
		elif entite.proprietes.get(PROP_PORTEUR, 0.0) > 0.0:
			causes.append({"position": entite.position, "poids": float(config.poids_porteur), "source_id": String(entite.id)})
	return causes

# UN PORTEUR NE S'INFESTE PAS LUI-MEME. DEFAUT REEL DE CE CHANTIER, trouve au
# premier lancement des tests et corrige ici : un hote devenu contagieux est
# une cause a distance ZERO de lui-meme -- charge.gd:_avancer_canal somme
# TOUTES les causes a portee, sans jamais savoir laquelle est la chose qu'il
# est en train de traiter (piege deja nomme par banc_fatigue_circadien.gd :
# « deux colons SUPERPOSES se chargeraient mutuellement »). Consequence
# mesuree : sa charge ne redescendait JAMAIS, meme parasite parti, et la
# guerison ne rouvrait donc jamais la porte a une reinfestation -- le sujet
# meme du banc, faux en silence.
#
# LA CORRECTION EST UN GESTE DE CABLAGE, jamais une garde de charge.gd :
# avancer() appelle Charge.avancer HOTE PAR HOTE, avec la liste des causes
# PRIVEE DE LA SIENNE. charge.gd accepte un monde d'un seul element sans rien
# savoir de tout ceci ; 'source_id' est une cle de plus sur chaque cause, qu'il
# ignore (il ne lit que 'position' et 'poids').
static func causes_hors_soi(causes: Array, id: String) -> Array:
	var retenues: Array = []
	for cause in causes:
		if String(cause.get("source_id", "")) == id:
			continue
		retenues.append(cause)
	return retenues

# GARDE CONTRE UNE DOUBLE INCUBATION (voir CE QUE L'AUDIT CORRIGEAIT, point 2).
# Le canal receveur restant en place toute la vie de l'hote, c'est ici -- et
# nulle part ailleurs -- qu'un hote deja en incubation, deja infeste ou mort
# cesse d'etre relance. Patron exact : banc_elimination_salete.gd:_peut_incuber.
static func peut_incuber(entite: Dictionary) -> bool:
	var actifs: Array = entite.proprietes.get("etats_actifs", [])
	return not (actifs.has(ETAT_INCUBATION) or actifs.has(ETAT_INFESTE) or est_mort(entite))

static func vigueur(entite: Dictionary) -> float:
	return float(entite.proprietes.get("reserves", {}).get(NOM_VIGUEUR, {}).get("reserve", 0.0))

static func vigueur_suffisante(entite: Dictionary, config: Dictionary) -> bool:
	return vigueur(entite) >= float(config.seuil_vigueur_accouplement)

# UN SEUL ECRIVAIN du canal (constat (C) de l'audit : un seul emplacement
# cout_base/surcout_action par canal, deux morceaux de cablage qui y ecrivent
# chacun le leur se detruisent EN SILENCE). cout_base NEGATIF : la reserve
# MONTE au lieu de descendre -- neutralite de depense.gd exploitee, jamais
# contournee. GATE DE CABLAGE SUR LA MORT (depense.gd ne consulte JAMAIS
# etat_effectif.gd, constat (A) ; precedents banc_elimination_salete.gd/
# banc_corrosion.gd/banc_conduction.gd) : un mort voit son taux mis a 0.0, sa
# vigueur se fige.
static func poser_taux_vigueur(entites: Array, config: Dictionary) -> void:
	var reference: Dictionary = config.canal_vigueur
	for entite in entites:
		var reserves: Dictionary = entite.proprietes.get("reserves", {})
		if not reserves.has(NOM_VIGUEUR):
			continue
		var canal: Dictionary = reserves[NOM_VIGUEUR]
		canal["cout_base"] = 0.0 if est_mort(entite) else float(reference.cout_base)
		canal["surcout_action"] = 0.0

# Rien dans le coeur ne borne le HAUT d'une reserve (depense.gd ne borne que
# par le bas, a 0.0) : le plafond vit donc au CABLAGE, patron exact
# banc_fertilite.gd:plafonner_fertilite.
static func plafonner_vigueur(entites: Array, config: Dictionary) -> void:
	var plafond: float = float(config.canal_vigueur.capacite)
	for entite in entites:
		var reserves: Dictionary = entite.proprietes.get("reserves", {})
		if not reserves.has(NOM_VIGUEUR):
			continue
		reserves[NOM_VIGUEUR]["reserve"] = min(float(reserves[NOM_VIGUEUR].get("reserve", 0.0)), plafond)

static func vider_vigueur(entite: Dictionary) -> void:
	var reserves: Dictionary = entite.proprietes.get("reserves", {})
	if reserves.has(NOM_VIGUEUR):
		reserves[NOM_VIGUEUR]["reserve"] = 0.0

# accouplement.gd ne lit que la cle "chose" de chaque entree (son en-tete) : un
# test de DISTANCE suffit, et monde.gd:choses_dans_rayon ne fait rien d'autre.
# Voir PERCEPTION en tete de fichier pour l'ecart assume a banc_reproduction.gd.
static func perceptions_a_portee(entite: Dictionary, monde, portee: float) -> Array:
	var perceptions: Array = []
	for entree in monde.choses_dans_rayon(entite.position, portee):
		if entree.chose.id == entite.id or est_mort(entree.chose):
			continue
		perceptions.append({"chose": entree.chose})
	return perceptions

# Combien de VIVANTS de chaque espece dans un rayon donne. Comptage au
# cablage, jamais comptage.gd -- ce dernier resout sa regle dans
# data/comptages.json, un catalogue PARTAGE qu'il faudrait etendre pour un
# comptage a deux criteres que cette boucle rend en six lignes (meme decision
# que le comptage implicite de causes_infestation ci-dessus). L'entite se
# compte ELLE-MEME (elle est a distance 0 de son propre rayon) : les deux
# gates ci-dessous en tiennent compte, aucun n'a besoin de l'exclure.
static func voisinage(entite: Dictionary, monde, config: Dictionary, portee: float) -> Dictionary:
	var compte := {"hotes": 0, "parasites": 0}
	for entree in monde.choses_dans_rayon(entite.position, portee):
		if est_mort(entree.chose):
			continue
		if est_parasite(entree.chose, config):
			compte["parasites"] = int(compte.parasites) + 1
		else:
			compte["hotes"] = int(compte.hotes) + 1
	return compte

# CAPACITE DE CHARGE, cote parasite : il ne pond que s'il reste assez d'hotes
# PAR PARASITE dans son rayon -- jamais un nombre d'hotes absolu.
#
# RESULTAT NEGATIF DE CE CHANTIER, mesure et a ne pas refaire : un gate sur le
# seul nombre d'hotes (« au moins N hotes a portee ») ne freine RIEN. Chaque
# parasite pond independamment, aucun ne consomme quoi que ce soit, et la
# population double a chaque duree_gestation -- le premier jet a fait PENDRE la
# suite de tests (croissance exponentielle sur les deux especes a la fois,
# aggravee par le cout O(n^2) des requetes spatiales que perception.gd signale
# deja dans son en-tete). Le ratio, lui, se referme tout seul : un parasite de
# plus a portee releve le nombre d'hotes exige, et la ponte s'arrete AVANT que
# la ressource ne soit epuisee. C'est la ligne 3 de l'audit (« capacite de
# charge : un milieu nourrit un nombre fini »), rendue par un comptage de
# cablage et zero mecanisme.
static func peut_pondre(entite: Dictionary, monde, config: Dictionary) -> bool:
	var compte := voisinage(entite, monde, config, float(config.portee_ponte))
	return int(compte.hotes) >= int(config.min_hotes_par_parasite) * max(1, int(compte.parasites))

# CAPACITE DE CHARGE, cote hote : meme loi, autre bout -- un hote entoure de
# trop de congeneres ne s'accouple pas. Sans elle, freiner les seuls parasites
# ne ferait que deplacer l'explosion sur l'autre espece : la mortalite
# parasitaire est le SEUL frein des hotes, et elle disparait justement quand
# les parasites se rarefient.
static func voisinage_supportable(entite: Dictionary, monde, config: Dictionary) -> bool:
	var compte := voisinage(entite, monde, config, float(config.portee_rencontre))
	return int(compte.hotes) <= int(config.max_voisins_hote)

# QUI DES DEUX GESTATE (voir CE QUE L'AUDIT CORRIGEAIT, point 3). Tri
# alphabetique des deux id : deterministe, aucune propriete neuve, aucun
# concept de sexe -- meme nature d'arbitrage que etat_effectif.gd entre deux
# ecraseurs sur la meme propriete. DEUX REPLIS, tous deux vers "oui" :
# partenaire_id egal a son propre id (mode asexuee, gestation.gd:poser pose
# l'entite comme sa propre source), et partenaire disparu ou mort -- sans ce
# second repli, la mort du porteur designe perdrait la portee en silence.
static func est_porteur_de_gestation(entite: Dictionary, entites: Array) -> bool:
	var gestation: Dictionary = entite.proprietes.get("gestation", {})
	var partenaire_id := String(gestation.get("partenaire_id", ""))
	if partenaire_id == String(entite.id):
		return true
	var partenaire: Variant = _par_id(entites, partenaire_id)
	if partenaire == null or est_mort(partenaire):
		return true
	return String(entite.id) <= partenaire_id

static func naissance_prete(entite: Dictionary) -> bool:
	return entite.proprietes.get("gestation", {}).get("naissance_prete", false)

# monde.gd n'a AUCUNE fonction de retrait (dette recensee, CARTE.md §6) : le
# seul geste disponible est de RECONSTRUIRE DU NEANT, les vivants y etant
# ré-ajoutes PAR REFERENCE -- leur etat interne traverse la reconstruction
# intact (idiome banc_elimination_salete.gd:monde_sans_dechets,
# banc_grief.gd, banc_occlusion.gd:monde_du_tick). Le type enregistre est
# l'espece : monde.gd ne s'en sert jamais lui-meme, mais il le rend a chaque
# requete.
static func monde_des_vivants(entites: Array):
	var vivants: Array = []
	for entite in entites:
		if not est_mort(entite):
			vivants.append(entite)
	return BancCommun.monde_depuis([{"choses": vivants, "type_depuis": "espece_reproduction"}])

static func _par_id(entites: Array, id: String) -> Variant:
	for entite in entites:
		if entite.id == id:
			return entite
	return null

# UN PAS complet (le deplacement est une fonction separee, voir deplacer).
# ORDRE FIXE ET ASSUME, non interchangeable -- patrons banc_menace_combat.gd/
# banc_fertilite.gd :
#   1. horloge et stades ;   2. infestation (charge.gd) ;
#   3. expirations d'etats ; 4. cumul parasitaire ;
#   5. seuils (les deux morts) ; 6. vigueur ;
#   7. accouplement ;        8. ponte des parasites ;
#   9. gestation ;          10. naissances ;  11. Monde reconstruit.
# Inverser 3 et 4 ferait perdre un tick de cumul a chaque infestation ; placer
# 5 avant 4 comparerait le cumul du tick precedent ; placer 10 avant 9 ferait
# naitre un tick trop tard.
#
# TOUT SAUF LES SEUILS NE VOIT QUE LES VIVANTS -- 'vivants' est fige EN TETE de
# tick : un cadavre ne charge plus, ne vieillit plus, ne percoit plus, ne
# depense plus. Un tick de retard subsiste, dit plutot que masque : une entite
# qui meurt AU pas 5 a deja charge et vieilli aux pas 1-2 du meme pas de temps.
#
# MUTE entites en place. 'monde' et 'compteurs' entrent et RESSORTENT par le
# resultat plutot que d'etre mutes : le Monde est reconstruit (nouvelle
# instance), et une fonction pure ne garde aucune memoire entre deux appels --
# deux tests dans le meme processus ne doivent jamais se contaminer.
#
# Rend { monde, compteurs, incubations, declares, gueris, morts (Array de
# { id, cause }), gestations (Array de { porteur_id, partenaire_id }), pontes
# (Array de { id, hotes }), naissances (Array de { id, parent_id,
# partenaire_id, espece, vitesse }) } -- pour que l'appelant (le Node, ou un
# test) trace chaque transition sans jamais relire l'etat avant/apres lui-meme.
static func avancer(entites: Array, monde, compteurs: Dictionary, delta: float, config: Dictionary, catalogues: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var suite: Dictionary = compteurs.duplicate(true)
	suite["tick"] = int(suite.get("tick", 0)) + 1
	var incubations: Array = []
	var declares: Array = []
	var gueris: Array = []
	var morts: Array = []
	var gestations: Array = []
	var pontes: Array = []
	var naissances: Array = []

	var vivants: Array = []
	for entite in entites:
		if not est_mort(entite):
			vivants.append(entite)

	# 1. horloge et stades
	for entite in vivants:
		Senescence.avancer(entite, delta, float(config.annees_par_seconde))
		Stade.avancer(entite)

	# 2. infestation -- charge.gd pose le seul marqueur qu'il connaisse
	# (expose_parasite, data/banc_parasites_reproduction.json:canal_infestation.
	# poser) ; ni 'incube_parasite' ni 'porteur_parasite' ne lui sont connus.
	var causes := causes_infestation(vivants, config)
	for hote in vivants:
		if not hote.proprietes.has("etats"):
			continue
		if Charge.avancer([hote], causes_hors_soi(causes, String(hote.id)), delta).is_empty():
			continue
		if not hote.proprietes.get(MARQUEUR_EXPOSE, false):
			continue
		if not peut_incuber(hote):
			continue
		EtatDuree.poser(hote, ETAT_INCUBATION, catalogues.etats)
		hote.proprietes[PROP_PORTEUR] = 1.0
		incubations.append(String(hote.id))

	# 3. expirations -- l'incubation qui expire DECLARE l'infestation ;
	# l'infestation qui expire est une GUERISON (le canal n'ayant jamais ete
	# retire, l'hote redevient immediatement susceptible).
	for entree in EtatDuree.avancer(vivants, delta, catalogues.etats):
		var entite: Variant = _par_id(vivants, String(entree.id))
		if entite == null:
			continue
		if entree.nom_etat == ETAT_INCUBATION:
			EtatDuree.poser(entite, ETAT_INFESTE, catalogues.etats)
			declares.append(String(entree.id))
		elif entree.nom_etat == ETAT_INFESTE:
			entite.proprietes[PROP_PORTEUR] = 0.0
			gueris.append(String(entree.id))

	# 4. cumul parasitaire -- accumule par CE cablage, jamais par un mecanisme
	# du coeur ; ne redescend JAMAIS (meme idiome que duree_maladie_cumulee),
	# c'est ce qui rend 'mort_parasite' irreversible et ce qui fait qu'une
	# premiere infestation survecue USE l'hote.
	for entite in vivants:
		if entite.proprietes.get("etats_actifs", []).has(ETAT_INFESTE):
			entite.proprietes[PROP_CUMUL] = float(entite.proprietes.get(PROP_CUMUL, 0.0)) + delta

	# 5. les deux morts -- catalogue LOCAL au banc, format exact de
	# data/seuils_etat.json (le catalogue partage n'est ni touche ni lu).
	for id in SeuilEtat.avancer(vivants, config.seuils_locaux):
		var entite: Variant = _par_id(vivants, String(id))
		if entite == null or not est_mort(entite):
			continue
		entite.proprietes[PROP_PORTEUR] = 0.0
		var cause := ETAT_MORT_PARASITE if entite.proprietes.etats_actifs.has(ETAT_MORT_PARASITE) else ETAT_MORT_VIEILLESSE
		morts.append({"id": String(id), "cause": cause})

	# 5bis. 'vivants' est REFAIT ICI, et c'est obligatoire : il a ete fige en
	# tete de tick, les morts que le pas 5 vient de poser y figurent encore.
	# DEFAUT REEL, trouve au test et corrige ici -- sans cette ligne un parasite
	# mort au pas 5 PONDAIT au pas 8 dans le meme tick (le Monde n'etant
	# reconstruit qu'au pas 11, il ne comptait deja plus les cadavres dans le
	# voisinage : le gate de capacite de charge s'ouvrait donc au moment precis
	# ou la population s'effondrait, exactement le contraire de ce qu'il est
	# cense faire). Tout ce qui suit -- vigueur, accouplement, ponte, gestation,
	# naissance -- est ainsi ferme aux morts du tick courant, sans un seul gate
	# recopie dans chaque boucle.
	if not morts.is_empty():
		var encore_vivants: Array = []
		for entite in vivants:
			if not est_mort(entite):
				encore_vivants.append(entite)
		vivants = encore_vivants

	# 6. vigueur
	poser_taux_vigueur(vivants, config)
	Depense.avancer(vivants, delta)
	plafonner_vigueur(vivants, config)

	# 7. accouplement des sexues, SOUS GATE DE VIGUEUR -- accouplement.gd ne
	# lit aucune reserve, c'est le refus de l'appeler qui EST le gate.
	for entite in vivants:
		if entite.proprietes.get("mode_reproduction", "") != "sexuee":
			continue
		if not vigueur_suffisante(entite, config):
			continue
		if not voisinage_supportable(entite, monde, config):
			continue
		var avait_gestation: bool = entite.proprietes.has("gestation")
		Accouplement.avancer(entite, perceptions_a_portee(entite, monde, float(config.portee_rencontre)), catalogues.reproduction, delta, int(suite.tick))
		if not avait_gestation and entite.proprietes.has("gestation"):
			gestations.append({
				"porteur_id": String(entite.id),
				"partenaire_id": String(entite.proprietes.gestation.partenaire_id),
			})

	# 8. ponte des asexues, SOUS GATE DE DENSITE -- c'est ce gate, et lui seul,
	# qui fait que « population dense -> plus de parasites ».
	for entite in vivants:
		if entite.proprietes.get("mode_reproduction", "") != "asexuee":
			continue
		if entite.proprietes.has("gestation") or not stade_fertile(entite):
			continue
		if not peut_pondre(entite, monde, config):
			continue
		Gestation.poser(entite, null, catalogues.reproduction)
		pontes.append({"id": String(entite.id), "hotes": int(voisinage(entite, monde, config, float(config.portee_ponte)).hotes)})

	# 9. gestation -- UN SEUL des deux parents avance, jamais les deux.
	for entite in vivants:
		if not entite.proprietes.has("gestation"):
			continue
		if not est_porteur_de_gestation(entite, entites):
			continue
		Gestation.avancer(entite, catalogues.reproduction, delta)

	# 10. naissances
	for entite in vivants:
		if not naissance_prete(entite):
			continue
		suite["naissances"] = int(suite.get("naissances", 0)) + 1
		var espece := String(entite.proprietes.espece_reproduction)
		# PREFIXE OBLIGATOIRE, jamais "<espece>_<n>" : les individus de depart
		# se nomment deja "parasite_0/1/2" dans la donnee, et un petit nomme
		# "parasite_1" entrait en COLLISION -- monde.gd:ajouter refuse un id
		# deja present et la chose n'etait PAS enregistree, en silence pour
		# tout le reste du banc (defaut reel, trouve au premier lancement).
		var id_petit := "petit_%s_%d" % [espece, int(suite.naissances)]
		var petit := fabriquer_petit(id_petit, entite, config, catalogues, rng)
		var partenaire_id := String(entite.proprietes.gestation.partenaire_id)
		_liberer_apres_naissance(entite)
		var partenaire: Variant = _par_id(entites, partenaire_id)
		if partenaire != null:
			_liberer_apres_naissance(partenaire)
		entites.append(petit)
		naissances.append({
			"id": id_petit,
			"parent_id": String(entite.id),
			"partenaire_id": partenaire_id,
			"espece": espece,
			"vitesse": float(petit.proprietes.vitesse),
		})

	# 11. le Monde ne se reconstruit qu'aux ticks ou sa composition change --
	# une reconstruction a chaque tick serait exacte mais gratuite.
	var monde_suite = monde
	if not morts.is_empty() or not naissances.is_empty():
		monde_suite = monde_des_vivants(entites)

	return {
		"monde": monde_suite,
		"compteurs": suite,
		"incubations": incubations,
		"declares": declares,
		"gueris": gueris,
		"morts": morts,
		"gestations": gestations,
		"pontes": pontes,
		"naissances": naissances,
	}

# TROIS RETRAITS, jamais un seul (voir CE QUE L'AUDIT CORRIGEAIT point 3, et
# CE QUE LE CABLAGE VIDE EN PLUS) : 'gestation' (sans quoi le non-porteur reste
# indisponible pour toujours), 'accouplement_accumulateur' (sans quoi le couple
# repose une gestation au tick suivant, l'exposition passee restant creditee
# pour toujours), et la vigueur (le gate qui tient le rythme des portees).
# gestation.gd/heredite.gd ne retirent JAMAIS rien eux-memes -- leurs en-tetes
# le disent : c'est le role de l'appelant.
static func _liberer_apres_naissance(entite: Dictionary) -> void:
	entite.proprietes.erase("gestation")
	entite.proprietes.erase("accouplement_accumulateur")
	vider_vigueur(entite)

# Deplacement aleatoire SEEDE, meme geste que banc_maladie.gd:deplacer_colons
# (deux bancs ne se referencent jamais entre eux). Une entite dont la vitesse
# EFFECTIVE est nulle (morte) ne bouge plus et ne tire plus de destination. La
# vitesse effective est composee par EtatEffectif.valeur -- et c'est CETTE
# ligne, et elle seule, qui fait que 'infeste' ralentit reellement : declarer
# le facteur dans data/etats.json ne produit rien tant que personne ne compose
# la valeur (constat (A) de l'audit).
static func deplacer(entites: Array, zone: Dictionary, etats: Dictionary, rng: RandomNumberGenerator, delta: float) -> void:
	for entite in entites:
		var vitesse: float = EtatEffectif.valeur(entite, PROP_VITESSE, etats)
		if vitesse <= 0.0:
			continue
		if entite.position.distance_to(entite.destination) <= DISTANCE_ARRIVEE:
			entite.destination = _destination_aleatoire(zone, rng)
		entite.position = BancCommun.bouger_vers(entite.position, entite.destination, vitesse, delta)

static func _destination_aleatoire(zone: Dictionary, rng: RandomNumberGenerator) -> Vector3:
	var mini: Array = zone["min"]
	var maxi: Array = zone["max"]
	return Vector3(rng.randf_range(mini[0], maxi[0]), rng.randf_range(mini[1], maxi[1]), 0.0)

# Etat courant pour l'affichage/couleur, PUR -- un seul nom a la fois. Priorite
# mort > parasite > infeste > incubation > petit > sain : un mort reste aussi
# 'infeste' dans etats_actifs, et un parasite mort est rouge comme un hote mort
# (la mort se lit avant l'espece). 'petit' est un hote vivant dont le stade
# n'est pas encore fertile -- lu sur stades_fertiles, jamais un nom de stade en
# dur. Ce fichier ne hierarchise jamais les etats ailleurs qu'ici.
static func etat_courant(entite: Dictionary, config: Dictionary) -> String:
	var actifs: Array = entite.proprietes.get("etats_actifs", [])
	if est_mort(entite):
		return "mort"
	if est_parasite(entite, config):
		return "parasite"
	if actifs.has(ETAT_INFESTE):
		return "infeste"
	if actifs.has(ETAT_INCUBATION):
		return "incubation"
	if not stade_fertile(entite):
		return "petit"
	return "sain"

static func compter(entites: Array, config: Dictionary) -> Dictionary:
	var compte := {"sain": 0, "incubation": 0, "infeste": 0, "mort": 0, "petit": 0, "parasite": 0}
	for entite in entites:
		var e := etat_courant(entite, config)
		compte[e] = compte.get(e, 0) + 1
	return compte

static func charge_infestation(entite: Dictionary) -> float:
	return float(entite.proprietes.get("etats", {}).get(CANAL_INFESTATION, {}).get("charge", 0.0))

static func _texte_gestation(entite: Dictionary) -> String:
	if not entite.proprietes.has("gestation"):
		return "-"
	var gestation: Dictionary = entite.proprietes.gestation
	if gestation.get("naissance_prete", false):
		return "prete"
	return "%.1fs" % float(gestation.get("duree_gestation_ecoulee", 0.0))

static func _texte_label(entite: Dictionary, config: Dictionary, etats: Dictionary) -> String:
	return "%s\netat=%s  stade=%s\ninfestation=%.2f\ngestation=%s\nvitesse=%.0f" % [
		entite.id,
		etat_courant(entite, config),
		entite.proprietes.get("stade", ""),
		charge_infestation(entite),
		_texte_gestation(entite),
		EtatEffectif.valeur(entite, PROP_VITESSE, etats),
	]

static func _texte_compteur(compte: Dictionary, compteurs: Dictionary, facteur_temps: float) -> String:
	return "hotes : sains=%d  petits=%d  incubation=%d  infestes=%d  morts=%d   |   parasites=%d   |   naissances=%d   |   temps x%.0f" % [
		compte.sain, compte.petit, compte.incubation, compte.infeste, compte.mort,
		compte.parasite, int(compteurs.get("naissances", 0)), facteur_temps,
	]

static func _ligne_incubation(t: float, id: String) -> String:
	return "t=%.1fs %s : INFESTE par contact (incubation, deja contagieux)" % [t, id]

static func _ligne_declare(t: float, id: String) -> String:
	return "t=%.1fs %s : infestation declaree (vitesse reduite)" % [t, id]

static func _ligne_gueri(t: float, id: String) -> String:
	return "t=%.1fs %s : gueri -- redevient susceptible (canal jamais retire)" % [t, id]

static func _ligne_gestation(t: float, porteur_id: String, partenaire_id: String) -> String:
	return "t=%.1fs accouplement : gestation posee sur %s et %s" % [t, porteur_id, partenaire_id]

static func _ligne_ponte(t: float, id: String, hotes: int) -> String:
	return "t=%.1fs %s : ponte (%d hotes a portee)" % [t, id, hotes]

static func _ligne_naissance(t: float, entree: Dictionary) -> String:
	return "t=%.1fs naissance : %s (%s) de %s x %s -- vitesse %.0f" % [
		t, entree.id, entree.espece, entree.parent_id, entree.partenaire_id, entree.vitesse,
	]

static func _ligne_mort(t: float, id: String, cause: String) -> String:
	return "t=%.1fs %s : MORT (%s)" % [t, id, cause]

static func _ligne_parasites(t: float, ajoutes: int, retires: int) -> String:
	if retires > 0:
		return "t=%.1fs PARASITES : %d retire(s) du monde" % [t, retires]
	return "t=%.1fs PARASITES : %d ajoute(s)" % [t, ajoutes]

static func _ligne_temps(t: float, facteur: float) -> String:
	return "t=%.1fs TEMPS : x%.0f" % [t, facteur]

# ---- Rendu (impur, Node) -- aucune decision, seulement la construction des
# noeuds et la couleur qui traduit l'etat.

func _couleur_pour(entite: Dictionary) -> Color:
	var rgb: Array = _config.couleurs.get(etat_courant(entite, _config), [1.0, 1.0, 1.0])
	return Color(rgb[0], rgb[1], rgb[2])

func _taille_pour(entite: Dictionary) -> float:
	var espece: String = String(entite.proprietes.get("espece_reproduction", ""))
	return float(_config.especes.get(espece, {}).get("taille", 20.0))

func _creer_rendu(entite) -> void:
	if entite == null or _noeuds.has(entite.id):
		return
	var taille := _taille_pour(entite)
	var carre := ColorRect.new()
	carre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	carre.size = Vector2(taille, taille)
	add_child(carre)
	_noeuds[entite.id] = carre

	var label := Label.new()
	label.add_theme_font_size_override("font_size", TAILLE_POLICE_LABEL)
	add_child(label)
	_labels[entite.id] = label

func _retirer_rendu(id: String) -> void:
	if _noeuds.has(id):
		_noeuds[id].queue_free()
		_noeuds.erase(id)
	if _labels.has(id):
		_labels[id].queue_free()
		_labels.erase(id)

# BISCTABLE : s'il reste un parasite VIVANT, tous les parasites (morts compris)
# quittent la liste animee, l'ecran et le Monde ; sinon 'parasites_par_ajout'
# parasites neufs sont poses a des positions tirees de la RNG SEEDEE. Le
# compteur de parasites ajoutes n'est jamais remis a zero -- monde.gd:ajouter
# refuse un id deja present, un id reutilise apres un retrait serait une chose
# non enregistree EN SILENCE (meme garde que le compteur de dechets de
# banc_elimination_salete.gd).
func _basculer_parasites() -> void:
	var vivants := 0
	for entite in _entites:
		if est_parasite(entite, _config) and not est_mort(entite):
			vivants += 1

	if vivants > 0:
		var restants: Array = []
		var retires := 0
		for entite in _entites:
			if est_parasite(entite, _config):
				_retirer_rendu(String(entite.id))
				retires += 1
			else:
				restants.append(entite)
		_entites = restants
		print(_ligne_parasites(_temps, 0, retires))
	else:
		var nombre := int(_config.parasites_par_ajout)
		for i in nombre:
			_compteurs["parasites_nes"] = int(_compteurs.get("parasites_nes", 0)) + 1
			var position := _destination_aleatoire(_config.zone, _rng)
			var parasite := fabriquer_individu({
				"id": "parasite_pose_%d" % int(_compteurs.parasites_nes),
				"espece": String(_config.espece_parasite),
				"position": [position.x, position.y, position.z],
				"age": 2.0,
				"genes_etat": {},
			}, _config)
			_entites.append(parasite)
			_creer_rendu(parasite)
		print(_ligne_parasites(_temps, nombre, 0))

	_monde = monde_des_vivants(_entites)
	_rafraichir_tout()

func _rafraichir_tout() -> void:
	for entite in _entites:
		if not _noeuds.has(entite.id):
			continue
		var carre: ColorRect = _noeuds[entite.id]
		carre.color = _couleur_pour(entite)
		carre.position = Vector2(entite.position.x, entite.position.y) - carre.size / 2.0
		var label: Label = _labels[entite.id]
		label.position = carre.position - Vector2(12.0, 72.0)
		label.text = _texte_label(entite, _config, _etats)
	_label_compteur.text = _texte_compteur(compter(_entites, _config), _compteurs, _facteur_temps)

func _poser_camera() -> void:
	var zone: Dictionary = _config.zone
	var mini: Array = zone["min"]
	var maxi: Array = zone["max"]
	var camera := Camera2D.new()
	camera.position = Vector2((mini[0] + maxi[0]) / 2.0, (mini[1] + maxi[1]) / 2.0)
	camera.zoom = Vector2(0.72, 0.72)
	camera.enabled = true
	add_child(camera)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
