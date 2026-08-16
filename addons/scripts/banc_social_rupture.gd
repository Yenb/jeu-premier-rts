extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_social_rupture.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1). Chantier « rupture + migration »
# (tableau Social et relations, lignes 8 « le deuil », 12 « la trahison » et 13
# « la migration »). AUCUN MECANISME DU COEUR TOUCHE NI CREE : charge.gd,
# seuil_etat.gd, bifurcation.gd, etat_duree.gd, etat_effectif.gd, conditions.gd,
# consommer.gd, lien_personnel.gd, monde.gd et banc_commun.gd sont appeles TELS
# QUELS, aucun n'a une ligne de changee. Les seuls fichiers neufs de ce chantier
# sont ce banc, son test, sa scene et sa donnee ; les seuls ajouts partages sont
# TROIS etats (data/etats.json:en_deuil/tentation_trahison/traitre) et UNE entree
# de seuil (data/seuils_etat.json:tentation_trahison).
#
# ---- CE QU'ON DOIT VOIR ----
#
# Deux colonies, cinq colons (trois au nord, deux au sud), un chef au nord, une
# reserve commune par colonie, et un compagnon au milieu du camp nord.
#
# Le monde du nord est injuste : le grief des trois colons du nord monte. Au
# PREMIER palier chacun rompt -- le chef se soumet, le cupide conteste. Le cupide
# continue de monter (il subit en plus une agression) et franchit un SECOND
# palier : il ne conteste plus, il TRAHIT, et la reserve commune du nord se vide
# dans sa poche pendant que celle du sud ne bouge pas. Un clic tue le compagnon :
# le colon qui l'aimait entre en deuil -- son rythme tombe a 0.7, la reserve
# commune monte moins vite, et son grief se met a monter pour cette raison-la
# aussi. Le deuil s'estompe tout seul en dix-huit secondes, sans que rien ne le
# retire. Pendant ce temps ce meme colon, dont la loyaute est basse, marche vers
# la colonie du sud : deux touches font monter ou descendre l'attractivite du sud
# et il repart ou fait demi-tour EN COURS DE ROUTE. Son voisin cupide voit
# EXACTEMENT la meme attractivite et ne bouge pas : sa loyaute est haute.
#
# ---- CE QUE CE BANC ETABLIT, ET QUI N'EXISTAIT PAS ----
#
# (1) UN QUATRIEME PALIER, ET DONC UNE QUATRIEME SORTIE. banc_grief.gd a un seul
# seuil qui ouvre TROIS sorties d'un coup, departagees au biais seul. Ici un
# SECOND palier ('tentation_trahison', data/seuils_etat.json) ouvre une
# QUATRIEME sortie ('trahison') sur le meme grief. bifurcation.gd ne connait ni
# seuil ni palier -- il multiplie des poids par une grandeur et prend le maximum
# sur l'ensemble qu'on lui DONNE : « la trahison demande plus de grief que la
# revolte » ne peut donc s'ecrire QUE comme un ensemble de sorties qui grandit.
# D'ou sorties_ouvertes() ci-dessous, et la MEMOIRE de cet ensemble sur le colon
# (voir bifurquer, RE-BIFURCATION).
#
# (2) LA MORT N'EST PAS UN EVENEMENT, C'EST UNE ABSENCE. Rien dans ce fichier ne
# s'appelle « mourir ». Le cablage retire le compagnon du Monde ; poser_deuil()
# constate qu'un lien personnel vise une chose qui n'est PLUS dans le Monde et
# pose le deuil. Consequence voulue : tuer n'importe quoi vers quoi un colon
# porte un lien assez fort produit le meme deuil, sans un cas particulier de
# plus.
#
# (3) LE DEUIL S'ESTOMPE, IL NE S'ARRETE PAS D'UN COUP. 'en_deuil' porte une
# 'duree', donc une INTENSITE suivie par etat_duree.gd. rythme_effectif() passe
# par EtatDuree.etats_ponderes AVANT EtatEffectif.valeur : la penalite vaut 0.7
# a l'instant du deuil et remonte continument vers 1.0. Sans ce passage, l'effet
# serait PLEIN dix-huit secondes puis nul d'un coup. Et la CAUSE de grief que le
# deuil represente suit la meme intensite -- son integrale (45.0) est SOUS le
# palier de trahison (60.0) : un deuil seul ne fait jamais un traitre.
#
# (4) UNE COLONIE RIVALE SANS OBJET-COLONIE. 'attractivite_autre' est un RESUME
# LU, ecrit sur chaque colon a chaque tick (resume de l'autre colonie x son
# ouverture propre), champ derive RECALCULE A NEUF, jamais accumule -- patron
# banc_marche_competence.gd:poser_prix. Aucune entite 'colonie' n'existe et
# aucune n'est percue : « Les collectifs n'existent pas » (docs/design.md). En
# multijoueur, ce nombre serait pose par la couche serveur et lu ici sans une
# ligne de changee -- c'est deja une propriete plate comme une autre.
#
# ---- QUATRE ECARTS A LA CONSIGNE, constates AVANT d'ecrire ----
#
# (a) LE GRIEF PASSE PAR charge.gd, comme la consigne le demande -- alors que
# banc_grief.gd l'avait ECARTE pour une raison mesurable (constat G : deux
# regimes disjoints ; une cause d'amelioration a poids negatif ne produit pas
# une descente proportionnelle, elle bascule seulement dans le regime de decrue
# fixe). Ce n'est pas un revirement : ici c'est le comportement VOULU. Une cause
# encore active bloque toute decrue, l'amelioration ne defait que ce qui n'a
# plus de cause -- « l'injustice cesse, mais l'agression continue » se lit
# directement. Les causes sont SYNTHETISEES a la position du colon lui-meme,
# portee 0.0 (idiome banc_fatigue_circadien.gd), et charge.gd est appele UN
# COLON A LA FOIS : deux colons a la meme position se voleraient leurs causes
# sinon, ce qu'aucune donnee n'interdit.
#
# (b) LE CANAL DE CHARGE N'A NI 'seuil' NI 'poser', et c'est deliberе : la
# bascule de charge.gd est un chemin mort volontaire ici. La comparaison reelle
# se fait par seuil_etat.gd, sur le MIROIR PLAT que poser_grief_plat() ecrit --
# charge.gd range sa valeur dans proprietes.etats.<canal>.charge, un chemin en
# points que seuil_etat.gd ne sait pas lire (meme raison exacte que
# 'manque_energie'/'urgence_elimination'). Deux mecanismes de seuil sur la meme
# grandeur divergeraient au bord ; il n'y en a qu'un.
#
# (c) LE GATE COMBINE PASSE PAR conditions.gd, jamais par seuil_etat.gd. La
# consigne demande « loyaute basse ET attractivite haute » : seuil_etat.gd
# compare UNE propriete a UN seuil et pose UN nom (« UNE ENTREE, UN SEUL ETAT »,
# son en-tete) -- il ne sait pas faire un ET. conditions.gd est exactement N
# conditions en ET logique sur N proprietes, reversible (retirer_si_faux). Le
# catalogue est LOCAL au banc (data/banc_social_rupture.json:gate_migration),
# jamais ajoute a un catalogue partage -- meme geste que
# data/banc_psycho_social.json:seuils_locaux.
#
# (d) TROIS BASCULES NE TIENNENT PAS SUR DEUX BOUTONS DE SOURIS. Clic GAUCHE :
# tuer le compagnon (UNE SEULE FOIS -- une mort ne se defait pas, et un toggle
# aurait menti sur ce point). Clic DROIT : injustice on/off. Touches HAUT/BAS :
# attractivite de la colonie rivale. Precedent exact : banc_marche_competence.gd
# (touches 1/2/3) et banc_biomes.gd (fleches), meme raison.
#
# ---- CE QUE CE BANC NE MONTRE PAS, dit plutot que masque ----
#
# Il ne monte NI perception.gd, NI proximite.gd, NI dominance.gd, NI agir.gd :
# aucun colon ne choisit de cible, aucun ne resout de verbe. Le sujet est ce qui
# se passe DANS un colon (un grief qui monte, un palier franchi, une loyaute qui
# tombe) et le seul deplacement est la migration, qui n'est pas une decision de
# saillance mais la consequence d'un gate. Le Monde (monde.gd) est monte quand
# meme, et il n'est pas decoratif : c'est LUI qui porte la mort du compagnon
# (voir (2) ci-dessus).
#
# Il ne refait pas le DEPART VERS LE BORD : banc_grief.gd le montre deja. Ici la
# sortie 'depart' arrete la production, rien de plus. Les colons ne portent donc
# PAS 'vitesse' -- data/etats.json:en_depart l'ECRASE a 0.0, et un colon a la
# fois en depart et en partance serait cloue au sol ; la migration passe par
# 'vitesse_migration' (donnee de banc), meme separation que
# banc_grief.json:vitesse_sortie.
#
# Les liens personnels ne DECROISSENT pas : LienPersonnel.avancer n'est jamais
# appele, aucun evenement de ce banc ne renouvelle un lien. LienPersonnel.force
# ne lit pas son catalogue, un Dictionary vide lui est donc passe -- dit ici
# plutot que masque derriere un fichier charge pour rien.
#
# ---- Deux moities, meme decoupage que les autres bancs ----
# - Node (impur) : _ready charge les trois fichiers de donnees et construit la
#   scene ; _unhandled_input ne fait que basculer des drapeaux ; _process appelle
#   UNIQUEMENT avancer() et lit son bilan pour l'affichage et la console --
#   aucune decision dans _process ; _draw ne dessine que ce que le tick a produit.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_social_rupture.gd) : avancer() et tout ce qu'elle enchaine.
#   LE TICK N'EST JAMAIS RECONSTITUE DANS LE TEST : il appelle avancer(), la
#   MEME fonction que _process (regle d'etat de CLAUDE.md).
#
# AUCUN NOM DE PROPRIETE EN DUR : les vingt-cinq noms que le cablage lit
# arrivent tous de data/banc_social_rupture.json -- c'est ce qui permet au test
# de faire traverser le meme code par un domaine entierement invente.

const Charge = preload("res://scripts/charge.gd")
const SeuilEtat = preload("res://scripts/seuil_etat.gd")
const Bifurcation = preload("res://scripts/bifurcation.gd")
const EtatDuree = preload("res://scripts/etat_duree.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")
const Conditions = preload("res://scripts/conditions.gd")
const Consommer = preload("res://scripts/consommer.gd")
const LienPersonnel = preload("res://scripts/lien_personnel.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")
const Monde = preload("res://scripts/monde.gd")

var _config: Dictionary = {}
var _etats: Dictionary = {}
var _catalogue_seuils: Dictionary = {}

var _colons: Array = []
var _depots: Dictionary = {}
var _compagnon: Dictionary = {}
var _monde
var _resumes: Dictionary = {}
var _injustice := true
var _compagnon_vivant := true
var _temps := 0.0
var _horloge_trace := 0.0
var _bilan: Dictionary = {}

var _labels: Dictionary = {}
var _label_compteur: Label
var _label_aide: Label

func _ready() -> void:
	_config = _charger_json("res://data/banc_social_rupture.json")
	_etats = _charger_json("res://data/etats.json")
	_catalogue_seuils = _charger_json("res://data/seuils_etat.json")

	for decl in _config.get("colons", []):
		_colons.append(construire_colon(decl, _config))
	for nom_colonie in _config.get("colonies", {}):
		_depots[String(nom_colonie)] = construire_depot(String(nom_colonie), _config)
	_compagnon = construire_compagnon(_config)
	_resumes = resumes_initiaux(_config)
	_monde = construire_monde(_colons, _depots.values(), _compagnon, Monde)

	_construire_rendu()
	print(ligne_pose(_colons, _config))

func _unhandled_input(evenement: InputEvent) -> void:
	if evenement is InputEventMouseButton and evenement.pressed:
		if evenement.button_index == MOUSE_BUTTON_LEFT:
			if _compagnon_vivant:
				_compagnon_vivant = false
				_monde = construire_monde(_colons, _depots.values(), null, Monde)
				print(ligne_mort(_temps, String(_compagnon.id)))
			else:
				print(ligne_deja_mort(_temps, String(_compagnon.id)))
		elif evenement.button_index == MOUSE_BUTTON_RIGHT:
			_injustice = not _injustice
			print(ligne_injustice(_temps, _injustice))
	elif evenement is InputEventKey and evenement.pressed and not evenement.echo:
		var autre := String(_config.get("colonie_principale", ""))
		var cible := autre_colonie(autre, _config)
		if evenement.keycode == KEY_UP:
			_resumes[cible] = attractivite_suivante(float(_resumes.get(cible, 0.0)), 1, _config)
			print(ligne_attractivite(_temps, cible, float(_resumes[cible])))
		elif evenement.keycode == KEY_DOWN:
			_resumes[cible] = attractivite_suivante(float(_resumes.get(cible, 0.0)), -1, _config)
			print(ligne_attractivite(_temps, cible, float(_resumes[cible])))

func _process(delta: float) -> void:
	_temps += delta
	_bilan = avancer(_colons, _depots, _monde, _resumes, _injustice, _config,
		_etats, _catalogue_seuils, delta)
	for ligne in lignes_bilan(_temps, _bilan):
		print(ligne)
	_horloge_trace += delta
	if _horloge_trace >= float(_config.intervalle_trace_s):
		_horloge_trace = 0.0
		for colon in _colons:
			print(ligne_trace(_temps, colon, _config, _etats))
	_rafraichir()
	queue_redraw()

# ---------------------------------------------------------------------------
# Construction de la scene (pure)
# ---------------------------------------------------------------------------

# Le colon ne porte ni composition ni materiau (construit A LA MAIN, meme statut
# que banc_grief.gd/banc_bonheur.gd/banc_marche_competence.gd) : c'est pourquoi
# les deux paliers sont poses ICI en proprietes plates, et non fusionnes depuis
# une fiche materiau. 'etats_actifs' part VIDE -- aucun etat n'est jamais recopie
# a la main dedans : seuil_etat.gd, etat_duree.gd et bifurquer() sont ses seuls
# ecrivains. 'liens_personnels' est STRUCTURELLE pour lien_personnel.gd, et les
# liens declares y sont poses PAR LienPersonnel.poser, jamais par un Dictionary
# recopie (patron banc_croyance.gd:fabriquer_colons). 'etats' porte le SEUL canal
# de charge du banc, sans 'seuil' ni 'poser' -- voir l'ecart (b) en tete.
static func construire_colon(decl: Dictionary, config: Dictionary) -> Dictionary:
	var pos: Array = decl.position
	var proprietes: Dictionary = {
		"etats_actifs": [],
		"liens_personnels": {},
	}
	proprietes["etats"] = {
		String(config.canal_grief): {
			"charge": 0.0,
			"portee_charge": 0.0,
			"taux_decroissance": float(config.taux_decroissance_grief),
		},
	}
	proprietes[String(config.nom_grief)] = 0.0
	proprietes[String(config.nom_seuil_rupture)] = float(config.seuil_rupture)
	proprietes[String(config.nom_seuil_trahison)] = float(config.seuil_trahison)
	proprietes[String(config.nom_rythme)] = float(config.rythme_base)
	proprietes[String(config.nom_colonie)] = String(decl.colonie)
	proprietes[String(config.nom_chef)] = bool(decl.get("chef", false))
	proprietes[String(config.nom_cupidite)] = float(decl.get("poids_cupidite", 1.0))
	proprietes[String(config.nom_ouverture)] = float(decl.get("ouverture_ailleurs", 0.0))
	proprietes[String(config.nom_poids_loyaute)] = decl.get("poids_loyaute", {}).duplicate(true)
	proprietes[String(config.nom_adhesions)] = decl.get("adhesions", {}).duplicate(true)
	proprietes[String(config.nom_vecu_cumule)] = 0.0
	proprietes[String(config.nom_deuils_faits)] = []
	proprietes[String(config.nom_sorties_ouvertes)] = []
	proprietes["biais_grief"] = decl.get("biais_grief", {}).duplicate(true)
	for cle in decl.get("causes_propres", {}):
		proprietes[String(cle)] = float(decl.causes_propres[cle])
	var colon: Dictionary = {
		"id": String(decl.id),
		"position": Vector3(float(pos[0]), float(pos[1]), float(pos[2])),
		"proprietes": proprietes,
	}
	for cible in decl.get("liens", {}):
		LienPersonnel.poser(colon, String(cible), float(decl.liens[cible]))
	return colon

# Le depot d'une colonie : une reserve nue, sans cout (depense.gd n'est jamais
# appele dessus) -- elle ne monte que par la production des colons et ne descend
# que par le detournement d'un traitre (consommer.gd).
static func construire_depot(nom_colonie: String, config: Dictionary) -> Dictionary:
	var decl: Dictionary = config.colonies[nom_colonie].depot
	var pos: Array = decl.position
	var reserves: Dictionary = {}
	reserves[String(config.nom_reserve_commune)] = {"reserve": float(decl.reserve)}
	var proprietes: Dictionary = {"reserves": reserves}
	proprietes[String(config.nom_colonie)] = nom_colonie
	return {
		"id": String(decl.id),
		"position": Vector3(float(pos[0]), float(pos[1]), float(pos[2])),
		"proprietes": proprietes,
		"type_banc": "depot",
	}

# Le compagnon n'est PAS l'un des cinq colons, et c'est une decision : le tuer
# retirerait un decideur de la scene, et le grief des quatre autres bougerait
# alors pour deux raisons a la fois (le deuil ET la colonie qui se vide). Il ne
# porte aucune propriete : sa seule fonction est d'etre PRESENT dans le Monde,
# puis de ne plus l'etre.
static func construire_compagnon(config: Dictionary) -> Dictionary:
	var decl: Dictionary = config.compagnon
	var pos: Array = decl.position
	return {
		"id": String(decl.id),
		"position": Vector3(float(pos[0]), float(pos[1]), float(pos[2])),
		"proprietes": {},
		"type_banc": "compagnon",
	}

# `classe_monde` est recu en PARAMETRE (jamais preload ici) pour que le test
# puisse construire le meme Monde sans dependre d'un chemin ecrit deux fois.
# `compagnon` a null = le compagnon est mort : monde.gd n'a AUCUNE fonction de
# retrait (dette recensee CARTE.md §6), le Monde est donc RECONSTRUIT DU NEANT,
# meme idiome que banc_grief.gd et banc_marche_competence.gd. Colons et depots y
# sont re-ajoutes PAR REFERENCE : leur etat interne est integralement preserve.
static func construire_monde(colons: Array, depots: Array, compagnon, classe_monde):
	var monde = classe_monde.new()
	for colon in colons:
		monde.ajouter(colon, "colon", colon.position)
	for depot in depots:
		monde.ajouter(depot, "depot", depot.position)
	if compagnon != null:
		monde.ajouter(compagnon, "compagnon", compagnon.position)
	return monde

static func resumes_initiaux(config: Dictionary) -> Dictionary:
	var resumes: Dictionary = {}
	for nom_colonie in config.get("colonies", {}):
		resumes[String(nom_colonie)] = float(config.colonies[nom_colonie].resume_attractivite)
	return resumes

# L'AUTRE colonie -- la premiere du catalogue qui n'est pas celle-ci. Ce banc
# n'en declare que deux ; a trois, ce serait la premiere declaree, ce qui ne
# voudrait plus rien dire : la generalisation demanderait un choix (la plus
# attractive ? la plus proche ?) que ce chantier n'a pas a trancher.
static func autre_colonie(colonie: String, config: Dictionary) -> String:
	for nom_colonie in config.get("colonies", {}):
		if String(nom_colonie) != colonie:
			return String(nom_colonie)
	return colonie

static func attractivite_suivante(valeur: float, sens: int, config: Dictionary) -> float:
	return clamp(valeur + float(sens) * float(config.pas_attractivite),
		float(config.attractivite_min), float(config.attractivite_max))

# ---------------------------------------------------------------------------
# LIGNE 8 et LIGNE 12 : le grief, ses causes, ses deux paliers
# ---------------------------------------------------------------------------

# UNIQUE ECRIVAIN des deux causes VARIABLES (l'injustice subie et le deuil
# ressenti) -- meme discipline que banc_grief.gd:poser_grief et
# banc_bonheur.gd:poser_bonheur : deux morceaux de cablage qui ecriraient chacun
# leur terme s'ecraseraient EN SILENCE. Les autres causes (faim, agression) sont
# des donnees de scene posees a la construction et jamais reecrites.
#
# L'injustice ne frappe que la colonie PRINCIPALE : c'est ce qui fait que les
# deux colons du sud traversent tout le banc sans grief, sans qu'aucun cas
# particulier ne les exclue.
#
# Le deuil ressenti SUIT L'INTENSITE de l'etat, jamais sa simple presence : la
# cause s'attenue comme la peine. Un etat actif sans intensite suivie (aucune
# 'duree' au catalogue) vaudrait 1.0 en permanence -- repli legitime, jamais une
# alarme.
static func poser_causes(colon: Dictionary, injustice: bool, config: Dictionary) -> Dictionary:
	var proprietes: Dictionary = colon.proprietes
	var principale: bool = String(proprietes.get(String(config.nom_colonie), "")) \
		== String(config.colonie_principale)
	proprietes[String(config.nom_injustice)] = 1.0 if (injustice and principale) else 0.0

	var etat_deuil := String(config.etat_deuil)
	var actifs: Array = proprietes.get("etats_actifs", [])
	var deuil := 0.0
	if actifs.has(etat_deuil):
		deuil = float(proprietes.get("etats_intensite", {}).get(etat_deuil, 1.0))
	proprietes[String(config.nom_deuil_ressenti)] = deuil
	return {
		String(config.nom_injustice): proprietes[String(config.nom_injustice)],
		String(config.nom_deuil_ressenti): deuil,
	}

# Les causes de CE colon, SYNTHETISEES a sa propre position (portee 0.0) --
# idiome banc_fatigue_circadien.gd. Une cause de poids nul n'est pas ajoutee :
# charge.gd distingue « somme > 0 » (la charge monte) de « somme nulle » (elle
# decroit a taux fixe), et une cause a 0.0 ferait basculer dans le premier regime
# sans rien faire monter -- le grief serait alors GELE au lieu de redescendre.
static func causes_du_colon(colon: Dictionary, config: Dictionary) -> Array:
	var causes: Array = []
	for cause in config.get("causes_grief", []):
		var valeur: float = float(colon.proprietes.get(String(cause.propriete), 0.0))
		var poids: float = float(cause.poids) * valeur
		if poids <= 0.0:
			continue
		causes.append({"position": colon.position, "poids": poids})
	return causes

# UN COLON A LA FOIS (voir l'ecart (a) en tete) : charge.gd teste la portee
# contre TOUTES les causes recues, et deux colons a la meme position se
# voleraient leurs causes a portee 0.0. Rien dans la donnee ne l'interdit.
static func avancer_charge(colon: Dictionary, config: Dictionary, delta: float) -> void:
	Charge.avancer([colon], causes_du_colon(colon, config), delta)

# LE MIROIR PLAT (voir l'ecart (b) en tete). UNIQUE ECRIVAIN de la propriete que
# seuil_etat.gd compare. RECOPIE, jamais un '+=' : la valeur qui accumule vit
# dans le canal de charge.gd et nulle part ailleurs.
static func poser_grief_plat(colon: Dictionary, config: Dictionary) -> float:
	var canal: Dictionary = colon.proprietes.get("etats", {}).get(String(config.canal_grief), {})
	var valeur: float = float(canal.get("charge", 0.0))
	colon.proprietes[String(config.nom_grief)] = valeur
	return valeur

# LES SORTIES OUVERTES A CET INSTANT : celles dont le MARQUEUR est actif. Les
# trois sorties heritees de banc_grief partagent le marqueur du premier palier ;
# 'trahison' est la seule a demander le second. Aucun nom de sortie ni d'etat
# n'est ecrit ici -- tout vient de config.marqueur_par_sortie.
static func sorties_ouvertes(colon: Dictionary, config: Dictionary) -> Array:
	var actifs: Array = colon.proprietes.get("etats_actifs", [])
	var par_sortie: Dictionary = config.marqueur_par_sortie
	var ouvertes: Array = []
	for sortie in config.sorties:
		var marqueur := String(par_sortie.get(String(sortie), ""))
		if marqueur != "" and actifs.has(marqueur):
			ouvertes.append(String(sortie))
	return ouvertes

# La sortie ACTUELLEMENT posee sur ce colon, ou "" -- lue depuis etats_actifs,
# jamais memorisee a cote (une memoire parallele divergerait du jour ou un autre
# mecanisme retirerait l'etat).
static func sortie_active(colon: Dictionary, config: Dictionary) -> String:
	var actifs: Array = colon.proprietes.get("etats_actifs", [])
	var par_sortie: Dictionary = config.etats_par_sortie
	for sortie in config.sorties:
		if actifs.has(String(par_sortie.get(String(sortie), ""))):
			return String(sortie)
	return ""

# LE BIAIS, COMPOSE AU CABLAGE. 'poids_cupidite' MULTIPLIE le seul biais de
# trahison, avant l'appel a bifurcation.gd -- qui, lui, ne compose rien : il
# multiplie des poids par une grandeur et prend le maximum. JAMAIS par
# deformation.gd : une deformation fait gagner une CIBLE en saillance (indexee
# par percevant ET par cible), elle ne pese jamais entre deux SORTIES declarees
# -- il n'y a aucune cible a nommer dans « trahir plutot que se soumettre ».
# PURE : construit et rend un Dictionary neuf, ne mute jamais le biais du colon.
static func biais_effectif(colon: Dictionary, config: Dictionary) -> Dictionary:
	var biais: Dictionary = colon.proprietes.get("biais_grief", {}).duplicate(true)
	var sortie := String(config.sortie_detournement)
	if biais.has(sortie):
		biais[sortie] = float(biais[sortie]) * float(colon.proprietes.get(String(config.nom_cupidite), 1.0))
	return biais

# LE COEUR DU CHANTIER. Appelee APRES SeuilEtat.avancer : elle ne fait que lire
# les marqueurs et en tirer les consequences.
#
# RE-BIFURCATION, et c'est ce qui separe ce banc de banc_grief.gd. La garde de
# banc_grief est « marqueur present ET sortie deja posee -> RIEN », ce qui
# suffit tant qu'un seul palier ouvre toutes les sorties d'un coup. Ici
# l'ensemble des sorties GRANDIT quand le second palier est franchi : sans
# rejouer la bifurcation a ce moment-la, la quatrieme sortie ne serait JAMAIS
# atteignable -- le colon aurait deja choisi parmi les trois premieres. La
# bifurcation est donc rejouee EXACTEMENT quand l'ensemble ouvert CHANGE, jamais
# a chaque tick : l'ensemble du dernier arbitrage est memorise sur le colon
# (proprietes.<nom_sorties_ouvertes>), meme idiome de memoire par entree que
# seuil_etat.gd:seuils_etat_memoire.
#
# Une sortie rendue vide par bifurcation.gd (biais entierement nul, ou grandeur
# non positive) ne pose RIEN et n'alarme pas -- un colon qui ne penche pour rien
# est legitime, le mecanisme le dit deja dans son en-tete.
# Rend { id, sortie, sens } pour chaque changement, jamais l'etat.
static func bifurquer(colons: Array, config: Dictionary) -> Array:
	var bascules: Array = []
	var nom_grief := String(config.nom_grief)
	var nom_memoire := String(config.nom_sorties_ouvertes)
	var par_sortie: Dictionary = config.etats_par_sortie
	for colon in colons:
		var proprietes: Dictionary = colon.proprietes
		var ouvertes := sorties_ouvertes(colon, config)
		var memoire: Array = proprietes.get(nom_memoire, [])
		var deja := sortie_active(colon, config)
		if _meme_liste(ouvertes, memoire) and (deja != "" or ouvertes.is_empty()):
			continue
		proprietes[nom_memoire] = ouvertes.duplicate()

		var choisie := ""
		if not ouvertes.is_empty():
			var grief: float = float(proprietes.get(nom_grief, 0.0))
			choisie = Bifurcation.selectionner(grief, biais_effectif(colon, config), ouvertes)
		if choisie == deja:
			continue

		var actifs: Array = proprietes.get("etats_actifs", [])
		if deja != "":
			actifs.erase(String(par_sortie.get(deja, "")))
			bascules.append({"id": colon.id, "sortie": deja, "sens": "retire"})
		if choisie != "":
			var nom_etat := String(par_sortie.get(choisie, ""))
			if nom_etat == "":
				push_error("banc_social_rupture : sortie '%s' sans etat dans etats_par_sortie" % choisie)
			else:
				actifs.append(nom_etat)
				bascules.append({"id": colon.id, "sortie": choisie, "sens": "pose"})
		proprietes["etats_actifs"] = actifs
	return bascules

static func _meme_liste(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if String(a[i]) != String(b[i]):
			return false
	return true

# LA MORT EST UNE ABSENCE (voir (2) en tete). Un lien personnel assez fort vers
# une chose qui n'est PLUS dans le Monde pose le deuil, UNE SEULE FOIS par chose
# (memoire proprietes.<nom_deuils_faits>, sans quoi le deuil serait repose a
# chaque tick et son intensite ne descendrait jamais). `monde.choses.has(id)` et
# jamais `monde.par_id(id)` : par_id ALARME sur un id absent, et l'absence est
# precisement ce qu'on cherche ici.
# Rend { id, chose_id } pour chaque deuil pose ce tick.
static func poser_deuil(colons: Array, monde, config: Dictionary, catalogue_etats: Dictionary) -> Array:
	var poses: Array = []
	var seuil: float = float(config.seuil_proche)
	var nom_memoire := String(config.nom_deuils_faits)
	for colon in colons:
		var faits: Array = colon.proprietes.get(nom_memoire, [])
		for chose_id in colon.proprietes.get("liens_personnels", {}):
			var cle := String(chose_id)
			if faits.has(cle):
				continue
			if monde.choses.has(cle):
				continue
			if LienPersonnel.force(colon, cle, {}) < seuil:
				continue
			EtatDuree.poser(colon, String(config.etat_deuil), catalogue_etats)
			faits.append(cle)
			poses.append({"id": colon.id, "chose_id": cle})
		colon.proprietes[nom_memoire] = faits
	return poses

# LE PIEGE DU CONSTAT (D), tenu : aucune couche de decision ne passe par
# etat_effectif.gd, et banc_commun.gd:agents_rythme lit 'rythme' BRUTE. Sans
# cette fonction, le x0.7 de 'en_deuil' et celui de 'soumis' seraient vrais dans
# data/etats.json et sans le moindre effet dans le jeu, EN SILENCE.
# EtatDuree.etats_ponderes AVANT EtatEffectif.valeur : c'est ce qui rend la
# penalite PROPORTIONNELLE a l'intensite restante du deuil (voir (3) en tete).
static func rythme_effectif(colon: Dictionary, config: Dictionary, catalogue_etats: Dictionary) -> float:
	return EtatEffectif.valeur(colon, String(config.nom_rythme),
		EtatDuree.etats_ponderes(colon, catalogue_etats))

# Le temps qu'il reste au deuil, en secondes -- intensite x duree totale. Lecture
# PURE, pour l'affichage et la console : rien ici ne recalcule une duree.
static func deuil_restant(colon: Dictionary, config: Dictionary, catalogue_etats: Dictionary) -> float:
	var etat := String(config.etat_deuil)
	var intensite: float = float(colon.proprietes.get("etats_intensite", {}).get(etat, 0.0))
	return intensite * float(catalogue_etats.get(etat, {}).get("duree", 0.0))

# ---------------------------------------------------------------------------
# LIGNE 13 : loyaute, attractivite, migration
# ---------------------------------------------------------------------------

# La force MOYENNE des liens de ce colon vers les AUTRES membres de sa colonie,
# ramenee a [0, 1] par un plafond de donnee. Un colon seul dans sa colonie rend
# 0.0 -- point neutre legitime, jamais une alarme.
static func lien_colonie(colon: Dictionary, colons: Array, config: Dictionary) -> float:
	var nom_colonie := String(config.nom_colonie)
	var sienne := String(colon.proprietes.get(nom_colonie, ""))
	var total := 0.0
	var nombre := 0
	for autre in colons:
		if autre.id == colon.id:
			continue
		if String(autre.proprietes.get(nom_colonie, "")) != sienne:
			continue
		total += LienPersonnel.force(colon, String(autre.id), {})
		nombre += 1
	if nombre == 0:
		return 0.0
	var plafond: float = float(config.plafond_lien)
	if plafond <= 0.0:
		return 0.0
	return clamp((total / float(nombre)) / plafond, 0.0, 1.0)

# La fraction des adhesions de ce colon qui coincident avec celles du CHEF de sa
# colonie. Aucun chef (la colonie du sud n'en declare pas) : 0.0, point neutre
# legitime -- une colonie sans voix commune ne partage rien. Le chef compare a
# lui-meme rend 1.0, ce qui est exactement ce qu'il faut dire.
static func adhesions_partagees(colon: Dictionary, colons: Array, config: Dictionary) -> float:
	var nom_colonie := String(config.nom_colonie)
	var nom_adhesions := String(config.nom_adhesions)
	var siennes: Dictionary = colon.proprietes.get(nom_adhesions, {})
	if siennes.is_empty():
		return 0.0
	var chef: Dictionary = {}
	for autre in colons:
		if String(autre.proprietes.get(nom_colonie, "")) != String(colon.proprietes.get(nom_colonie, "")):
			continue
		if bool(autre.proprietes.get(String(config.nom_chef), false)):
			chef = autre
			break
	if chef.is_empty():
		return 0.0
	var reference: Dictionary = chef.proprietes.get(nom_adhesions, {})
	var accord := 0
	for sujet in siennes:
		if reference.has(sujet) and reference[sujet] == siennes[sujet]:
			accord += 1
	return float(accord) / float(siennes.size())

# UNIQUE ECRIVAIN des trois sources de loyaute ET du vecu cumule -- meme geste,
# meme nombre, meme tick (patron banc_bonheur.gd:poser_bonheur). Les trois sont
# ecrites en cles PLATES parce que la somme ponderee, elle, boucle sur les POIDS
# DU COLON et lit chaque source par son nom : un colon qui ne pese pas une source
# la laisse simplement a zero dans la somme, sans alarme, par contrat.
# Le vecu est la SEULE des trois qui accumule ; sa forme normalisee est un miroir
# recalcule a neuf, jamais un second accumulateur.
static func poser_sources_loyaute(colon: Dictionary, colons: Array, config: Dictionary, delta: float) -> Dictionary:
	var proprietes: Dictionary = colon.proprietes
	var nom_cumule := String(config.nom_vecu_cumule)
	proprietes[nom_cumule] = float(proprietes.get(nom_cumule, 0.0)) + float(config.vecu_par_s) * delta
	var plafond: float = float(config.plafond_vecu)
	var vecu: float = clamp(float(proprietes[nom_cumule]) / plafond, 0.0, 1.0) if plafond > 0.0 else 0.0
	proprietes[String(config.source_lien_colonie)] = lien_colonie(colon, colons, config)
	proprietes[String(config.source_adhesions_partagees)] = adhesions_partagees(colon, colons, config)
	proprietes[String(config.source_vecu)] = vecu
	return {
		String(config.source_lien_colonie): proprietes[String(config.source_lien_colonie)],
		String(config.source_adhesions_partagees): proprietes[String(config.source_adhesions_partagees)],
		String(config.source_vecu): vecu,
	}

# LA SOMME PONDEREE. Lecture PURE : n'ecrit rien -- poser_loyaute est le seul
# ecrivain. Boucle sur les poids DU COLON, jamais sur une liste de sources connue
# de ce fichier : un poids sur une source que personne n'ecrit rend exactement
# 0.0 (`get(source, 0.0)`), sans alarme, par contrat.
static func calculer_loyaute(colon: Dictionary, config: Dictionary) -> float:
	var proprietes: Dictionary = colon.proprietes
	var poids: Dictionary = proprietes.get(String(config.nom_poids_loyaute), {})
	var loyaute := 0.0
	for source in poids:
		loyaute += float(poids[source]) * float(proprietes.get(String(source), 0.0))
	return loyaute

# UNIQUE ECRIVAIN de la loyaute. CHAMP DERIVE RECALCULE A NEUF chaque tick et
# ECRIT PAR-DESSUS, JAMAIS un '+=' : c'est la seule chose qui empeche un champ
# derive de DERIVER (resultat negatif deja mesure deux fois sur expression.gd,
# voir data/epigenetique.json).
static func poser_loyaute(colon: Dictionary, config: Dictionary) -> float:
	var valeur: float = calculer_loyaute(colon, config)
	colon.proprietes[String(config.nom_loyaute)] = valeur
	return valeur

# UNIQUE ECRIVAIN de l'attractivite. LE RESUME DE L'AUTRE COLONIE, LU, jamais une
# colonie percue (voir (4) en tete) -- pondere par l'ouverture PROPRE du colon :
# deux colons de la meme colonie lisent le meme resume et n'en tirent pas le meme
# nombre, ce qui est exactement « Les archetypes n'existent pas ».
static func poser_attractivite(colon: Dictionary, config: Dictionary, resumes: Dictionary) -> float:
	var sienne := String(colon.proprietes.get(String(config.nom_colonie), ""))
	var autre := autre_colonie(sienne, config)
	var valeur: float = float(resumes.get(autre, 0.0)) \
		* float(colon.proprietes.get(String(config.nom_ouverture), 0.0))
	colon.proprietes[String(config.nom_attractivite)] = valeur
	return valeur

# LE GATE COMBINE (voir l'ecart (c) en tete) : conditions.gd, catalogue LOCAL,
# retirer_si_faux = true pour que le depart se DEFASSE quand l'une des deux
# conditions cesse -- c'est ce qui permet a un colon en route de faire demi-tour.
# MUTE proprietes en place (contrat de conditions.gd) ; rend l'etat du drapeau.
static func evaluer_migration(colon: Dictionary, config: Dictionary) -> bool:
	Conditions.evaluer(colon.proprietes, config.get("gate_migration", []), true)
	return float(colon.proprietes.get(String(config.nom_veut_migrer), 0.0)) > 0.0

# Le pas de migration. Rend "" tant que le colon marche, "arrivee" au tick ou il
# change de colonie. Le vecu repart de zero : ce qu'on a vecu ailleurs ne compte
# pas dans la loyaute d'ici. MUTE le colon en place.
static func avancer_migration(colon: Dictionary, config: Dictionary, delta: float) -> String:
	var nom_colonie := String(config.nom_colonie)
	var sienne := String(colon.proprietes.get(nom_colonie, ""))
	var cible := autre_colonie(sienne, config)
	var pos: Array = config.colonies[cible].position
	var destination := Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	colon.position = BancCommun.bouger_vers(colon.position, destination,
		float(config.vitesse_migration), delta)
	if colon.position.distance_to(destination) > float(config.rayon_arrivee):
		return ""
	colon.proprietes[nom_colonie] = cible
	colon.proprietes[String(config.nom_vecu_cumule)] = 0.0
	return "arrivee"

# ---------------------------------------------------------------------------
# Ce que les colons font de leurs journees
# ---------------------------------------------------------------------------

# La production : le rythme EFFECTIF du colon verse dans la reserve commune de sa
# colonie. UNIQUE ECRIVAIN de cette reserve a la hausse (le detournement est le
# seul a la faire baisser). Un colon en depart ne produit plus, un colon en route
# vers l'ailleurs non plus -- marcher n'est pas travailler.
static func produire(colon: Dictionary, depots: Dictionary, config: Dictionary,
		rythme: float, en_migration: bool, delta: float) -> float:
	if en_migration:
		return 0.0
	if sortie_active(colon, config) == String(config.sortie_sans_production):
		return 0.0
	var depot = depots.get(String(colon.proprietes.get(String(config.nom_colonie), "")), null)
	if depot == null:
		return 0.0
	var canal: Dictionary = depot.proprietes.reserves[String(config.nom_reserve_commune)]
	var quantite: float = rythme * delta
	canal["reserve"] = float(canal.get("reserve", 0.0)) + quantite
	return quantite

# LE DETOURNEMENT : consommer.gd, mecanisme du coeur appele TEL QUEL -- transfert
# DESTRUCTIF, ce qui sort de la reserve commune entre EXACTEMENT dans la poche du
# traitre, rien n'est cree (le mecanisme credite la quantite REELLEMENT retiree).
# Reserve commune vide : le transfert rend 0.0 et 'source_epuisee', aucune alarme.
static func detourner(colon: Dictionary, depots: Dictionary, config: Dictionary, delta: float) -> float:
	if sortie_active(colon, config) != String(config.sortie_detournement):
		return 0.0
	var depot = depots.get(String(colon.proprietes.get(String(config.nom_colonie), "")), null)
	if depot == null:
		return 0.0
	return float(Consommer.transferer(depot, colon,
		String(config.nom_reserve_commune), String(config.nom_reserve_butin),
		float(config.taux_detournement_par_s), delta).quantite)

static func butin(colon: Dictionary, config: Dictionary) -> float:
	return float(colon.proprietes.get("reserves", {})
		.get(String(config.nom_reserve_butin), {}).get("reserve", 0.0))

static func reserve_commune(depots: Dictionary, nom_colonie: String, config: Dictionary) -> float:
	var depot = depots.get(nom_colonie, null)
	if depot == null:
		return 0.0
	return float(depot.proprietes.reserves[String(config.nom_reserve_commune)].reserve)

# ---------------------------------------------------------------------------
# LE TICK ENTIER, en une fonction pure et testable
# ---------------------------------------------------------------------------

# MUTE les colons et les depots en place. Rend { bascules, deuils, migrations,
# infos } -- tout ce que l'affichage et les traces lisent, jamais recalcule
# ailleurs.
#
# L'ORDRE N'EST PAS LIBRE, six contraintes le fixent :
#   (1) le deuil AVANT les causes : un deuil pose ce tick doit compter comme
#       cause DES ce tick, sinon la peine arrive avec un tick de retard.
#   (2) les causes AVANT charge.gd : sans quoi la charge de ce tick lirait les
#       causes du precedent.
#   (3) le miroir plat APRES charge.gd et AVANT seuil_etat.gd : c'est la valeur
#       de CE tick que les deux paliers doivent comparer.
#   (4) la bifurcation APRES seuil_etat.gd : l'inverse la ferait trancher sur les
#       marqueurs du tick precedent (contrainte deja etablie par banc_grief.gd).
#   (5) loyaute et attractivite AVANT le gate : conditions.gd ne calcule rien, il
#       compare ce qui est ecrit sur l'objet.
#   (6) EtatDuree.avancer EN DERNIER : un deuil pose ce tick doit avoir servi une
#       fois -- a la cause, au rythme, a l'affichage -- avant d'etre rabote
#       (meme raison que l'oubli en dernier dans banc_croyance.gd:avancer).
static func avancer(
	colons: Array,
	depots: Dictionary,
	monde,
	resumes: Dictionary,
	injustice: bool,
	config: Dictionary,
	catalogue_etats: Dictionary,
	catalogue_seuils: Dictionary,
	delta: float,
) -> Dictionary:
	var deuils := poser_deuil(colons, monde, config, catalogue_etats)

	for colon in colons:
		poser_causes(colon, injustice, config)
		avancer_charge(colon, config, delta)
		poser_grief_plat(colon, config)

	# Catalogue COMPLET passe tel quel : les autres entrees comparent des
	# proprietes que ces colons ne portent pas -- chemins morts silencieux.
	SeuilEtat.avancer(colons, catalogue_seuils)
	var bascules := bifurquer(colons, config)

	var migrations: Array = []
	var infos: Dictionary = {}
	for colon in colons:
		poser_sources_loyaute(colon, colons, config, delta)
		var loyaute := poser_loyaute(colon, config)
		var attractivite := poser_attractivite(colon, config, resumes)
		var veut := evaluer_migration(colon, config)
		var arrivee := ""
		if veut:
			arrivee = avancer_migration(colon, config, delta)
			if arrivee != "":
				migrations.append({
					"id": colon.id,
					"colonie": String(colon.proprietes.get(String(config.nom_colonie), "")),
				})
		var rythme := rythme_effectif(colon, config, catalogue_etats)
		infos[colon.id] = {
			"grief": float(colon.proprietes.get(String(config.nom_grief), 0.0)),
			"loyaute": loyaute,
			"attractivite": attractivite,
			"veut_migrer": veut,
			"rythme": rythme,
			"sortie": sortie_active(colon, config),
			"produit": produire(colon, depots, config, rythme, veut, delta),
			"detourne": detourner(colon, depots, config, delta),
			"deuil_restant": deuil_restant(colon, config, catalogue_etats),
		}

	EtatDuree.avancer(colons, delta, catalogue_etats)
	return {"bascules": bascules, "deuils": deuils, "migrations": migrations, "infos": infos}

# ---------------------------------------------------------------------------
# Textes (purs eux aussi : le test les verrouille sans ouvrir la scene)
# ---------------------------------------------------------------------------

static func ligne_pose(colons: Array, config: Dictionary) -> String:
	var morceaux: Array = []
	for colon in colons:
		morceaux.append("%s (%s)" % [
			String(colon.id),
			String(colon.proprietes.get(String(config.nom_colonie), "")),
		])
	return "t=0.0 %d colons poses -- paliers %.1f (rupture) puis %.1f (trahison) -- %s" % [
		colons.size(), float(config.seuil_rupture), float(config.seuil_trahison),
		", ".join(morceaux),
	]

static func ligne_mort(t: float, id: String) -> String:
	return "t=%.1f MORT : %s a quitte le monde" % [t, id]

static func ligne_deja_mort(t: float, id: String) -> String:
	return "t=%.1f %s est deja mort -- une mort ne se defait pas" % [t, id]

static func ligne_injustice(t: float, actif: bool) -> String:
	return "t=%.1f INJUSTICE : %s" % [t, "subie" if actif else "levee"]

static func ligne_attractivite(t: float, colonie: String, valeur: float) -> String:
	return "t=%.1f ATTRACTIVITE de '%s' : %.2f" % [t, colonie, valeur]

static func lignes_bilan(t: float, bilan: Dictionary) -> Array:
	var lignes: Array = []
	for deuil in bilan.get("deuils", []):
		lignes.append("t=%.1f DEUIL : %s entre en deuil de %s" % [t, String(deuil.id), String(deuil.chose_id)])
	for bascule in bilan.get("bascules", []):
		if String(bascule.sens) == "pose":
			lignes.append("t=%.1f BIFURCATION : %s -> %s" % [t, String(bascule.id), String(bascule.sortie)])
		else:
			lignes.append("t=%.1f RETOUR : %s quitte '%s'" % [t, String(bascule.id), String(bascule.sortie)])
	for migration in bilan.get("migrations", []):
		lignes.append("t=%.1f MIGRATION : %s rejoint la colonie '%s'" % [
			t, String(migration.id), String(migration.colonie)])
	return lignes

static func ligne_trace(t: float, colon: Dictionary, config: Dictionary, catalogue_etats: Dictionary) -> String:
	var proprietes: Dictionary = colon.proprietes
	return "t=%.1f %s [%s] | grief %.1f | %s | loyaute %.2f | attractivite %.2f | rythme %.2f | deuil %.1f s | butin %.1f" % [
		t,
		String(colon.id),
		String(proprietes.get(String(config.nom_colonie), "")),
		float(proprietes.get(String(config.nom_grief), 0.0)),
		sortie_active(colon, config) if sortie_active(colon, config) != "" else "-",
		float(proprietes.get(String(config.nom_loyaute), 0.0)),
		float(proprietes.get(String(config.nom_attractivite), 0.0)),
		rythme_effectif(colon, config, catalogue_etats),
		deuil_restant(colon, config, catalogue_etats),
		butin(colon, config),
	]

static func texte_colon(colon: Dictionary, infos: Dictionary, config: Dictionary) -> String:
	var proprietes: Dictionary = colon.proprietes
	var sortie := String(infos.get("sortie", ""))
	var deuil: float = float(infos.get("deuil_restant", 0.0))
	return "%s  [%s]\ngrief %.1f / %.1f / %.1f\nsortie : %s%s\nloyaute %.2f   ailleurs %.2f%s\nrythme %.2f   butin %.1f" % [
		String(colon.id),
		String(proprietes.get(String(config.nom_colonie), "")),
		float(infos.get("grief", 0.0)),
		float(proprietes.get(String(config.nom_seuil_rupture), 0.0)),
		float(proprietes.get(String(config.nom_seuil_trahison), 0.0)),
		sortie if sortie != "" else "-",
		"" if deuil <= 0.0 else "   deuil %.1f s" % deuil,
		float(infos.get("loyaute", 0.0)),
		float(infos.get("attractivite", 0.0)),
		"   -> PART" if bool(infos.get("veut_migrer", false)) else "",
		float(infos.get("rythme", 0.0)),
		butin(colon, config),
	]

static func texte_compteur(t: float, depots: Dictionary, resumes: Dictionary,
		injustice: bool, config: Dictionary) -> String:
	var morceaux: Array = []
	for nom_colonie in config.get("colonies", {}):
		morceaux.append("%s : commun %.1f (attractivite %.2f)" % [
			String(nom_colonie),
			reserve_commune(depots, String(nom_colonie), config),
			float(resumes.get(String(nom_colonie), 0.0)),
		])
	return "t=%.1f s -- injustice : %s -- %s" % [
		t, "subie" if injustice else "levee", "   |   ".join(morceaux),
	]

static func texte_aide() -> String:
	return "clic GAUCHE : tuer le compagnon (une seule fois)   clic DROIT : injustice on/off   FLECHES HAUT/BAS : attractivite de la colonie rivale"

# ---------------------------------------------------------------------------
# Rendu (impur, Node) -- aucune decision, seulement des rectangles et du texte.
# ---------------------------------------------------------------------------

func _couleur(rgb: Array) -> Color:
	return Color(float(rgb[0]), float(rgb[1]), float(rgb[2]))

func _construire_rendu() -> void:
	for colon in _colons:
		var label := _creer_label(int(_config.taille_police_label))
		add_child(label)
		_labels[colon.id] = label
	var couche := CanvasLayer.new()
	add_child(couche)
	_label_compteur = _creer_label(int(_config.taille_police_compteur))
	_label_compteur.position = Vector2(10.0, 10.0)
	couche.add_child(_label_compteur)
	_label_aide = _creer_label(int(_config.taille_police_aide))
	_label_aide.position = Vector2(10.0, 36.0)
	_label_aide.text = texte_aide()
	couche.add_child(_label_aide)
	_poser_camera()

func _creer_label(taille: int) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", taille)
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	label.add_theme_constant_override("outline_size", 4)
	return label

func _draw() -> void:
	var couleurs: Dictionary = _config.couleurs
	draw_rect(Rect2(Vector2.ZERO, Vector2(float(_config.terrain_largeur), float(_config.terrain_hauteur))),
		_couleur(couleurs.fond_injustice if _injustice else couleurs.fond_calme))

	# Une zone par colonie, a sa position declaree : c'est vers ce point que
	# marche un migrant, jamais vers un decor pose a cote.
	for nom_colonie in _config.get("colonies", {}):
		var decl: Dictionary = _config.colonies[nom_colonie]
		var pos: Array = decl.position
		draw_circle(Vector2(float(pos[0]), float(pos[1])), float(_config.rayon_arrivee) * 4.0,
			_couleur(couleurs.zone_colonie))
		var depot: Dictionary = _depots[String(nom_colonie)]
		var taille: float = float(_config.taille_depot)
		draw_rect(Rect2(Vector2(depot.position.x, depot.position.y) - Vector2(taille, taille) / 2.0,
			Vector2(taille, taille)), _couleur(couleurs.depot))

	var taille_c: float = float(_config.taille_compagnon)
	draw_rect(Rect2(Vector2(_compagnon.position.x, _compagnon.position.y) - Vector2(taille_c, taille_c) / 2.0,
		Vector2(taille_c, taille_c)),
		_couleur(couleurs.compagnon if _compagnon_vivant else couleurs.compagnon_mort))

	for colon in _colons:
		_dessiner_colon(colon)

# Le carre porte la COULEUR DE LA COLONIE, le lisere celle de la SORTIE active
# (ou du deuil, prioritaire a l'affichage tant qu'il dure) : deux lectures qui ne
# se recouvrent jamais -- un traitre reste visiblement du nord, c'est tout le
# sujet.
func _dessiner_colon(colon: Dictionary) -> void:
	var infos: Dictionary = _bilan.get("infos", {}).get(colon.id, {})
	var couleurs: Dictionary = _config.couleurs
	var centre := Vector2(colon.position.x, colon.position.y)
	var taille: float = float(_config.taille_colon)
	var colonie := String(colon.proprietes.get(String(_config.nom_colonie), ""))
	var rgb: Array = _config.colonies.get(colonie, {}).get("couleur", couleurs.neutre)

	var cle_lisere := "neutre"
	var sortie := String(infos.get("sortie", ""))
	if float(infos.get("deuil_restant", 0.0)) > 0.0:
		cle_lisere = String(_config.etat_deuil)
	elif sortie != "":
		cle_lisere = String(_config.etats_par_sortie[sortie])
	draw_rect(Rect2(centre - Vector2(taille, taille) / 2.0 - Vector2(4.0, 4.0),
		Vector2(taille + 8.0, taille + 8.0)), _couleur(couleurs[cle_lisere]))
	draw_rect(Rect2(centre - Vector2(taille, taille) / 2.0, Vector2(taille, taille)), _couleur(rgb))

	# La barre de grief porte les DEUX paliers REELS lus sur le colon, jamais des
	# nombres recopies : elle ne peut pas mentir sur ce que seuil_etat.gd compare.
	var largeur: float = float(_config.largeur_barre)
	var hauteur: float = float(_config.hauteur_barre)
	var origine := centre + Vector2(-largeur / 2.0, taille / 2.0 + 8.0)
	var trahison: float = float(colon.proprietes.get(String(_config.nom_seuil_trahison), 1.0))
	var echelle: float = trahison if trahison > 0.0 else 1.0
	draw_rect(Rect2(origine, Vector2(largeur, hauteur)), _couleur(couleurs.barre_fond))
	draw_rect(Rect2(origine, Vector2(largeur * clamp(float(infos.get("grief", 0.0)) / echelle, 0.0, 1.0), hauteur)),
		_couleur(couleurs.barre_grief))
	var x_rupture: float = origine.x + largeur \
		* clamp(float(colon.proprietes.get(String(_config.nom_seuil_rupture), 0.0)) / echelle, 0.0, 1.0)
	draw_line(Vector2(x_rupture, origine.y - 2.0), Vector2(x_rupture, origine.y + hauteur + 2.0),
		_couleur(couleurs.trait_rupture), 2.0)
	draw_line(Vector2(origine.x + largeur, origine.y - 2.0),
		Vector2(origine.x + largeur, origine.y + hauteur + 2.0), _couleur(couleurs.trait_trahison), 2.0)

func _rafraichir() -> void:
	var infos: Dictionary = _bilan.get("infos", {})
	for colon in _colons:
		var label: Label = _labels[colon.id]
		label.position = Vector2(colon.position.x, colon.position.y) \
			+ Vector2(float(_config.taille_colon), float(_config.taille_colon) / 2.0 + 24.0)
		label.text = texte_colon(colon, infos.get(colon.id, {}), _config)
	_label_compteur.text = texte_compteur(_temps, _depots, _resumes, _injustice, _config)

func _poser_camera() -> void:
	var camera := Camera2D.new()
	camera.position = Vector2(float(_config.terrain_largeur), float(_config.terrain_hauteur)) / 2.0
	camera.zoom = Vector2(0.82, 0.82)
	camera.enabled = true
	add_child(camera)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
