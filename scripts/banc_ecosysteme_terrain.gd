extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_ecosysteme_terrain.tscn, PAS la
# scene principale -- run/main_scene reste banc_p1). Chantier « refuge +
# extinction + capacite de charge + territoire »
# (audit_ecosysteme_vivant_prealable.md, lignes 1/2/3/4, toutes les quatre au
# verdict CABLABLE). Compose SEPT mecanismes deja fermes, TOUS APPELES TELS
# QUELS ET TOUS INCHANGES : conditions.gd (les biomes, reversibles),
# comptage.gd (les populations), seuil_etat.gd (le surpeuplement, la faim),
# perception.gd + proximite.gd (le predateur voit, ou ne voit pas),
# consommer.gd (la chasse, transfert conserve), depense.gd (l'energie qui
# descend ou remonte), etat_effectif.gd (la vitesse modulee), plus monde.gd et
# portee.gd. AUCUN MECANISME DU COEUR TOUCHE, AUCUN .gd NEUF DU COEUR.
#
# CE QU'ON DOIT VOIR : une grille 8x8 en trois bandes de biome -- foret (a
# gauche), prairie (au milieu), desert (a droite). Six proies y vivent, trois
# predateurs les chassent. Les deux proies de FORET sont VERT FONCE : leur
# biome porte 0.6 de couvert, elles sont CACHEES, et aucun predateur ne les
# voit jamais. Les quatre autres sont VERT CLAIR, exposees, et se font manger.
# Chaque predateur porte un CERCLE de territoire qui grandit a mesure que les
# proies se rarefient autour de lui. Un clic gauche leve le refuge partout :
# toutes les proies se cachent d'un coup, les trois predateurs cessent de
# percevoir quoi que ce soit, et meurent de faim les uns apres les autres. Un
# clic droit pose huit proies de plus dans le DESERT, dont la capacite de
# charge est 8 : la case passe en SURPEUPLEMENT (bord rouge), l'energie de tout
# ce qui y vit se met a descendre, les plus faibles meurent, et la population
# redescend d'elle-meme jusqu'a repasser sous la capacite.
#
# ---------------------------------------------------------------------------
# LES QUATRE LIGNES, ET LA VOIE RETENUE POUR CHACUNE
# ---------------------------------------------------------------------------
#
# LIGNE 1 -- LE REFUGE CACHE UNE PROIE, PAS TOUTES. La voie est le CABLAGE qui
# REECRIT la cle plate chose.proprietes.profil_saillance (poser_profils_proies
# ci-dessous, UNIQUE ECRIVAIN de cette cle dans tout le fichier), entre deux
# profils declares en donnee partagee (data/profils_saillance.json :
# proie_exposee 6.0, proie_cachee 0.8). Precedents exacts de ce geste :
# banc_maladie.gd ('porteur'), banc_succession.gd ('stade'),
# banc_activation_neutronique.gd ('force_radiation').
# LES DEUX AUTRES VOIES SONT FAUSSES, et ce banc ne les prend pas :
#   (a) moduler la PORTEE de perception du predateur -- perception.gd:
#       _portee_effective lit portee/sensibilite sur canaux_config du
#       PERCEPTEUR, jamais sur la chose percue. L'ecraser rend le predateur
#       aveugle a TOUT, y compris aux proies a decouvert : la portee ne sait
#       pas cacher UNE proie en particulier. (Ce banc ecrit bien cette portee,
#       mais pour le TERRITOIRE, ligne 4 -- jamais pour le refuge.)
#   (b) un etat 'cache' qui modulerait 'saillance_intrinseque' via
#       etat_effectif.gd -- proximite.gd lit ce nombre DANS LE CATALOGUE
#       (data/profils_saillance.json), jamais sur l'objet, et n'appelle JAMAIS
#       EtatEffectif : l'etat serait vrai dans data/etats.json et sans le
#       moindre effet, EN SILENCE (audit, constat A, sous sa forme la plus
#       dure).
# CE QUI EXCLUT REELLEMENT LA PROIE CACHEE : pas proximite.gd (il n'exclut
# qu'une saillance nulle ou une portee depassee), mais le SEUIL DE DECISION du
# predateur, au cablage (proies_percues, config.seuil_perception_proie). Une
# proie cachee est bel et bien PERCUE et EVALUEE -- sa saillance plafonne a
# 0.8, sous le seuil 1.5, a toute distance. Le dire ainsi plutot que « elle
# disparait » : c'est ce qui se passe.
#
# LIGNE 2 -- TROP DE REFUGE TUE LES PREDATEURS, et la mort est INDIVIDUELLE.
# « une reserve de population predatrice » serait un COLLECTIF POSE (« les
# collectifs n'existent pas », docs/design.md) : aucune case ne porte ici de
# reserve de population. Chaque predateur porte SA reserve d'energie, il meurt
# SEUL quand elle atteint 0.0, et la « population » n'est jamais une grandeur
# stockee -- c'est un Comptage.compter refait a NEUF chaque tick (patron
# banc_comptage.gd, « le compteur affiche n'est PAS une propriete d'un
# objet-agregat, c'est un CALCUL »). La mort elle-meme est un GATE DE CABLAGE
# et non un etat (patron banc_faim_thermo.gd, « L'ARRET FINAL ») : aucun etat
# 'mort' n'a ete ajoute a un catalogue partage, un animal a reserve nulle est
# simplement retire du monde.
#
# LIGNE 3 -- LA CAPACITE DE CHARGE VIT SUR LA CASE, ET VARIE PAR BIOME.
# comptage.gd n'a AUCUNE notion d'espace (son en-tete le dit) : c'est ce
# fichier qui construit la liste (les animaux dont 'biome_local' vaut ce
# biome), puis appelle. Le comptage rend un int, jamais une propriete -- le
# cablage l'ecrit en cle plate 'population_locale' sur chaque case du biome,
# et seuil_etat.gd la compare a 'capacite_charge', LUE PAR CASE
# ('seuil_propriete', exactement comme 'point_fusion' varie par materiau) et
# posee par conditions.gd depuis data/biomes.json. L'entree de seuil vit dans
# un catalogue LOCAL (data/banc_ecosysteme_terrain.json:seuils_locaux, format
# exact de data/seuils_etat.json) -- patron banc_elimination_salete.gd ; le
# catalogue PARTAGE n'est que LU (faim/famine sur les animaux), et les deux
# appels par tick ne se collisionnent pas, la memoire de franchissement de
# seuil_etat.gd etant PAR ENTREE.
#
# LIGNE 4 -- LE TERRITOIRE, ET LE PIEGE QUE L'AUDIT NOMME. Ce banc est le
# PREMIER ECRIVAIN DYNAMIQUE de canaux_config du depot : perception.gd relit
# 'portee' sur proprietes.canaux_config.<canal> a CHAQUE appel, rien dans le
# coeur ne s'oppose a ce qu'un cablage la reecrive, mais aucun banc ne le
# faisait -- d'ou le verrou par test des la premiere ligne.
# LE PIEGE : « rayon = rayon_base / densite » ou la densite serait mesuree DANS
# CE MEME rayon est une BOUCLE (le rayon grandit, capte plus de proies, la
# densite monte, le rayon retrecit -- oscillation garantie). Deux gardes, et
# elles sont structurelles, pas des precautions :
#   (1) 'rayon_echantillon' est FIXE, en donnee, et n'est JAMAIS derive du
#       territoire ; rayon_territoire() ne lit QUE la densite et la config,
#       jamais la portee courante du canal -- le territoire est recalcule A
#       NEUF depuis 'rayon_territoire_base', jamais incremente depuis sa valeur
#       precedente. Geste exact de banc_biomes.gd (« LE CLIMAT NE DERIVE
#       JAMAIS » : humidite_base posee une fois, jamais mutee).
#   (2) division par zero : le denominateur passe par max(0.1, densite) --
#       aucune proie a portee rend le rayon MAXIMUM, jamais INF (patron
#       banc_menace_combat.gd:ratio_effectifs, « une division par zero rendrait
#       INF et ferait exploser la charge en silence »). Le plafond
#       'rayon_territoire_max' est du CABLAGE : sans lui un predateur sans
#       proie couvrirait 2600 unites sur un terrain qui en fait 672, et le
#       cercle affiche mentirait sur ce que le mecanisme fait.
#
# ---------------------------------------------------------------------------
# UNE SEULE ECRITURE DE surcout_action PAR ANIMAL ET PAR TICK
# ---------------------------------------------------------------------------
# depense.gd calcule reserve -= (cout_base + surcout_action) * delta : il n'y a
# QU'UN emplacement surcout_action par canal (audit, constat C). Deux choses
# veulent y ecrire ici -- l'effort de chasse et le surpeuplement --, et
# poser_surcout_action est le SEUL endroit du fichier qui ecrit cette cle. Deux
# morceaux de cablage separes se seraient ecrases EN SILENCE : aucun test
# n'aurait rougi, la depense aurait seulement ete fausse. Piege ferme la
# premiere fois par banc_faim_thermo.gd:poser_surcout_action.
#
# LE cout_base DE LA PROIE EST NEGATIF : elle broute, sa reserve REMONTE toute
# seule. Neutralite de depense.gd EXPLOITEE, jamais contournee -- exactement la
# jachere de banc_fertilite.gd. C'est ce qui rend la capacite de charge
# REGULATRICE et non seulement mortelle : sous surpeuplement le surcout depasse
# le broutage et la population redescend ; des qu'elle repasse sous la
# capacite, l'etat se retire et les survivants se refont.
# LE PLAFOND, LUI, EST DU CABLAGE : depense.gd borne le BAS (0.0), RIEN dans le
# coeur ne borne le HAUT d'une reserve -- meme constat que
# banc_fertilite.gd:plafonner_fertilite, d'ou plafonner_energie ci-dessous.
#
# LE MIROIR PLAT 'manque_energie' EST OBLIGATOIRE (audit, constat B) :
# seuil_etat.gd ne lit qu'une cle PLATE (une reserve vit sous
# proprietes.reserves.<nom>.reserve, chemin qu'il ne parcourt jamais) et ne
# compare que VERS LE HAUT. « L'energie descend sous un seuil » s'ecrit donc
# « son manque monte au-dessus d'un seuil », RECALCULE A NEUF chaque tick,
# jamais accumule par '+=' -- c'est ce recalcul, et lui seul, qui rend 'affame'
# reversible. Patron banc_faim_thermo.gd:poser_manque_energie. La capacite est
# 100.0, la MEME que celle contre laquelle data/seuils_etat.json:faim/famine
# sont calibrees : leur _note l'exige de tout cablage qui les reutilise.
#
# ---------------------------------------------------------------------------
# AUCUN HASARD, NULLE PART, ET AUCUNE MORT PAR AGREGAT
# ---------------------------------------------------------------------------
# Il n'y a pas un seul RNG dans ce fichier (meme discipline que
# banc_menace_combat.gd). Les proies ne bougent pas ; un predateur va vers la
# proie qu'il a REELLEMENT retenue, et ne bouge pas quand il n'en retient
# aucune -- un predateur aveugle qui se viderait en patrouillant au hasard
# rendrait la famine par refuge indistinguable d'une famine par malchance.
#
# LIMITES DITES, PAS MASQUEES :
#   - AUCUNE REPRODUCTION. La population ne fait que descendre (c'est la ligne
#     11 de l'audit, un autre chantier) : le clic droit est le seul moyen d'en
#     remettre. Le cycle proies/predateurs qui OSCILLE est la ligne 5, encore
#     un autre chantier.
#   - AUCUNE AGRESSION, aucune hierarchie, aucun verbe resolu : agir.gd et
#     dominance.gd ne sont PAS montes ici. Le predateur ne CHOISIT pas entre
#     plusieurs gestes, il chasse -- ce sont les lignes 6 et 7 de l'audit.
#   - LE COUT DES REQUETES SPATIALES est signale et non optimise (consigne
#     explicite de perception.gd) : monde.gd:choses_dans_rayon est un balayage
#     LINEAIRE. Avec 9 animaux au repos et 17 sous renfort, on reste tres loin
#     des ~50 candidats par requete au-dela desquels perception.gd demande de
#     le signaler.
#   - UN TICK DE RETARD sur le deplacement : le predateur se deplace vers la
#     cible retenue AVANT la depense de ce tick, jamais apres -- inherent a
#     l'ordre fixe, invisible a l'oeil, mesurable au test.
#
# ANIMAUX CONSTRUITS A LA MAIN (patron banc_maladie.gd/banc_faim_thermo.gd/
# banc_menace_combat.gd) : aucune composition, aucune masse a calculer, et
# data/types.json n'est PAS touche -- donc RIEN a enregistrer dans
# scripts/test_lint_donnees.gd.
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge les catalogues et construit ; _unhandled_input
#   ne fait que basculer deux booleens, jamais calculer ; _process appelle
#   UNIQUEMENT avancer() et lit son resultat pour l'affichage et la console.
# - Fonctions statiques (pures, testables headless, voir
#   scripts/test_banc_ecosysteme_terrain.gd) : tout le reste.
#
# AUCUN NOM DE PROPRIETE EN DUR : les 'nom_*' viennent tous de
# data/banc_ecosysteme_terrain.json -- c'est ce qui permet au test de faire
# traverser le meme code par un domaine entierement invente.

const Conditions = preload("res://scripts/conditions.gd")
const Comptage = preload("res://scripts/comptage.gd")
const SeuilEtat = preload("res://scripts/seuil_etat.gd")
const Perception = preload("res://scripts/perception.gd")
const Proximite = preload("res://scripts/proximite.gd")
const Consommer = preload("res://scripts/consommer.gd")
const Depense = preload("res://scripts/depense.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")
const Portee = preload("res://scripts/portee.gd")
const Monde = preload("res://scripts/monde.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")

var _config: Dictionary = {}
var _catalogue_biomes: Array = []
var _catalogue_comptages: Dictionary = {}
var _catalogue_seuils: Dictionary = {}
var _catalogue_etats: Dictionary = {}
var _catalogue_canaux: Dictionary = {}
var _profils_saillance: Dictionary = {}

var _cases: Array = []
var _animaux: Array = []
var _monde := Monde.new()
var _refuge_leve := false
var _renfort_pose := false
var _temps := 0.0
var _prochaine_trace := 0.0
var _morts := 0
var _dernier: Dictionary = {}

var _couche_ui: CanvasLayer
var _noeuds_cases: Dictionary = {}
var _labels_cases: Dictionary = {}
var _noeuds_animaux: Dictionary = {}
var _labels_animaux: Dictionary = {}
var _label_compteur: Label
var _label_aide: Label

func _ready() -> void:
	_config = _charger("res://data/banc_ecosysteme_terrain.json")
	_catalogue_biomes = _charger("res://data/biomes.json").get("biomes", [])
	_catalogue_comptages = _charger("res://data/comptages.json")
	_catalogue_seuils = _charger("res://data/seuils_etat.json")
	_catalogue_etats = _charger("res://data/etats.json")
	_catalogue_canaux = _charger("res://data/canaux.json")
	_profils_saillance = _charger("res://data/profils_saillance.json")

	_cases = construire_grille(_config)
	_animaux = construire_animaux(_config, false)
	_reconstruire_monde()

	_couche_ui = CanvasLayer.new()
	add_child(_couche_ui)
	_creer_rendu()
	_poser_camera()
	# Un premier pas a delta NUL avant la premiere image : les biomes sont
	# evalues, les profils poses et les territoires ecrits, donc la grille
	# s'affiche deja peuplee (patron banc_biomes.gd, « premiere evaluation AVANT
	# le premier _process »). delta 0.0 ne fait rien avancer -- Depense.avancer
	# ponctionne zero, Consommer.transferer court-circuite sur demande <= 0.0.
	_dernier = avancer(
		_cases, _animaux, _monde, _config, _catalogue_biomes, _catalogue_comptages,
		_catalogue_seuils, _catalogue_etats, _catalogue_canaux, _profils_saillance,
		bonus_refuge(_refuge_leve, _config), 0.0,
	)
	_rafraichir_tout()
	print(ligne_pose(_cases, _animaux, _config))
	for changement in _dernier.changements_profil:
		print(ligne_changement_profil(0.0, changement))

func _unhandled_input(event: InputEvent) -> void:
	# NE CALCULE RIEN : bascule deux booleens, c'est tout. Toute la consequence
	# est recalculee par avancer() au tick suivant -- meme discipline que
	# banc_biomes.gd:_unhandled_input.
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		_refuge_leve = not _refuge_leve
		print(ligne_toggle_refuge(_temps, _refuge_leve, _config))
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_renfort_pose = not _renfort_pose
		_appliquer_renfort()
		print(ligne_toggle_renfort(_temps, _renfort_pose, _animaux, _config))

func _process(delta: float) -> void:
	_temps += delta

	var resultat := avancer(
		_cases, _animaux, _monde, _config, _catalogue_biomes, _catalogue_comptages,
		_catalogue_seuils, _catalogue_etats, _catalogue_canaux, _profils_saillance,
		bonus_refuge(_refuge_leve, _config), delta,
	)
	_dernier = resultat

	for changement in resultat.changements_biome:
		print(ligne_changement_biome(_temps, changement))
	for changement in resultat.changements_profil:
		print(ligne_changement_profil(_temps, changement))
	for changement in resultat.changements_surpeuplement:
		print(ligne_changement_surpeuplement(_temps, changement))
	for mort in resultat.morts:
		print(ligne_mort(_temps, mort))

	if not resultat.morts.is_empty():
		_morts += resultat.morts.size()
		_animaux = resultat.survivants
		_retirer_noeuds(resultat.morts)
		_reconstruire_monde()

	if _temps >= _prochaine_trace:
		_prochaine_trace = _temps + float(_config.periode_trace_s)
		print(ligne_trace(_temps, resultat, _morts, _config))

	_rafraichir_tout()
	queue_redraw()

# ---- Fonctions PURES, testables headless (voir test_banc_ecosysteme_terrain.gd) ----

# Grille grille_lignes x grille_colonnes, ordre ligne-majeur. La position est
# en unites MONDE (colonne * taille_case), et non en unites de grille comme
# banc_biomes.gd/banc_fertilite.gd : ce banc fait cohabiter des cases et des
# animaux qui PERCOIVENT, et portee_saillance/portee de perception vivent a
# cette echelle-la. z reste 0.0 (VERTICALITE : Vector3 partout, meme quand la
# troisieme dimension ne sert pas encore).
# Chaque case porte ses conditions CLIMATIQUES (humidite/temperature, posees
# ICI une fois et JAMAIS mutees ensuite) et un 'etats_actifs' vide -- c'est
# conditions.gd qui posera biome/fraction_refuge/capacite_charge, a chaque
# tick, et seuil_etat.gd qui posera 'surpeuplement'.
static func construire_grille(config: Dictionary) -> Array:
	var lignes: int = config.grille_lignes
	var colonnes: int = config.grille_colonnes
	var taille: float = float(config.taille_case)
	var cases: Array = []
	for ligne in range(lignes):
		for colonne in range(colonnes):
			var zone: Dictionary = zone_pour_colonne(colonne, config)
			var proprietes: Dictionary = {
				"zone": String(zone.get("nom", config.get("zone_defaut", ""))),
				"etats_actifs": [],
			}
			proprietes[String(config.nom_humidite)] = float(zone.get("humidite", 0.0))
			proprietes[String(config.nom_temperature)] = float(zone.get("temperature", 0.0))
			cases.append({
				"id": "case_%d_%d" % [colonne, ligne],
				"position": Vector3(float(colonne) * taille, float(ligne) * taille, 0.0),
				"proprietes": proprietes,
			})
	return cases

# Bande de colonnes a laquelle appartient une colonne. Nommer des zones est le
# seul nommage de categorie qu'un banc jetable s'autorise (CLAUDE.md) -- aucun
# mecanisme du coeur ne lit jamais "zone", et le BIOME, lui, n'est jamais
# nomme ici : il est deduit par conditions.gd des deux nombres que la zone
# pose. Colonne hors de toute bande : Dictionary vide, la case retombe sur des
# conditions nulles et ne remplira aucune entree -- absence legitime, jamais
# une alarme (chemin mort avec la config reelle, qui pave les 8 colonnes).
static func zone_pour_colonne(colonne: int, config: Dictionary) -> Dictionary:
	for zone in config.get("zones", []):
		if colonne >= int(zone.colonne_min) and colonne <= int(zone.colonne_max):
			return zone
	return {}

# Rejoue le catalogue sur CHAQUE case via Conditions.evaluer (mecanisme du
# coeur, JAMAIS reimplemente ici) avec retirer_si_faux=true -- c'est ce drapeau,
# et lui seul, qui rend biome/fraction_refuge/capacite_charge REVERSIBLES.
# Rend l'Array des CHANGEMENTS de biome ({ id, avant, apres }) : une case dont
# le biome ne bouge pas n'y figure jamais, sans quoi la console cracherait 64
# lignes par image. Le changement est lu AVANT/APRES sur la case, jamais deduit
# de la trace de Conditions.evaluer (qui dit ce qui a ete pose, pas si la
# VALEUR a change). Recopie de banc_biomes.gd:evaluer_biomes -- deux bancs
# jetables ne se referencent jamais entre eux.
static func evaluer_biomes(cases: Array, catalogue: Array, nom_biome: String) -> Array:
	var changements: Array = []
	for case in cases:
		var avant: String = String(case.proprietes.get(nom_biome, ""))
		Conditions.evaluer(case.proprietes, catalogue, true)
		var apres: String = String(case.proprietes.get(nom_biome, ""))
		if avant != apres:
			changements.append({"id": case.id, "avant": avant, "apres": apres})
	return changements

# APPARIEMENT « quelle case est sous cette chose » -- du CABLAGE, jamais un
# mecanisme : comparaison de positions deleguee a Portee.en_portee, jamais
# reimplementee. Patron exact banc_fertilite.gd:case_sous. Rend null si aucune
# case ne coincide (une chose hors grille n'est sur aucun biome, cas neutre
# legitime).
static func case_sous(objet: Dictionary, cases: Array, portee_appariement: float) -> Variant:
	for case in cases:
		if Portee.en_portee(case.position, objet.position, portee_appariement):
			return case
	return null

# Les animaux, CONSTRUITS A LA MAIN (voir en-tete). Un seul canal de reserve
# par animal. Le predateur porte en plus le canal de perception 'vue' et sa
# config -- c'est cette 'portee'-la que poser_territoire reecrira chaque tick.
# La proie n'a AUCUN canal : elle ne percoit rien, elle est percue.
# 'profil_saillance' n'est PAS pose ici : c'est poser_profils_proies qui le
# pose, des le premier tick, depuis le refuge du biome -- le poser aussi ici
# ferait deux ecrivains pour une seule cle.
static func construire_animaux(config: Dictionary, avec_renfort: bool) -> Array:
	var animaux: Array = []
	for decl in config.get("proies", []):
		animaux.append(construire_proie(decl, config))
	if avec_renfort:
		for decl in config.get("renfort_proies", []):
			animaux.append(construire_proie(decl, config))
	for decl in config.get("predateurs", []):
		animaux.append(construire_predateur(decl, config))
	return animaux

static func construire_proie(decl: Dictionary, config: Dictionary) -> Dictionary:
	var proprietes: Dictionary = _proprietes_communes(decl, config, float(config.cout_base_proie))
	proprietes[String(config.nom_espece)] = String(config.valeur_espece_proie)
	return {"id": String(decl.id), "position": _position(decl), "proprietes": proprietes}

static func construire_predateur(decl: Dictionary, config: Dictionary) -> Dictionary:
	var proprietes: Dictionary = _proprietes_communes(decl, config, float(config.cout_base_predateur))
	proprietes[String(config.nom_espece)] = String(config.valeur_espece_predateur)
	proprietes[String(config.nom_vitesse)] = float(config.vitesse_predateur)
	proprietes["canaux"] = [String(config.nom_canal_vue)]
	proprietes["canaux_config"] = {
		String(config.nom_canal_vue): {
			"portee": float(config.rayon_territoire_base),
			"angle": float(config.angle_vue),
			"sensibilite": float(config.sensibilite_vue),
		},
	}
	proprietes[String(config.nom_rayon_territoire)] = float(config.rayon_territoire_base)
	return {"id": String(decl.id), "position": _position(decl), "proprietes": proprietes}

static func _proprietes_communes(decl: Dictionary, config: Dictionary, cout_base: float) -> Dictionary:
	var reserves: Dictionary = {}
	reserves[String(config.nom_reserve_energie)] = {
		"reserve": float(decl.get("energie", config.capacite_energie)),
		"cout_base": cout_base,
		"surcout_action": 0.0,
	}
	return {"reserves": reserves, "etats_actifs": []}

static func _position(decl: Dictionary) -> Vector3:
	var p: Array = decl.position
	return Vector3(float(p[0]), float(p[1]), float(p[2]))

# Recopie sur chaque animal le biome de la case sous lui, en cle PLATE -- c'est
# elle, et elle seule, qui permet a comptage.gd (qui n'a aucune notion
# d'espace) de compter « par biome » : le cablage filtre sur cette cle avant
# d'appeler. Un animal hors grille perd la cle (jamais un biome invente).
static func poser_biome_local(animaux: Array, cases: Array, config: Dictionary) -> void:
	var nom_biome := String(config.nom_biome)
	var nom_local := String(config.nom_biome_local)
	var portee := float(config.portee_appariement)
	for animal in animaux:
		var case: Variant = case_sous(animal, cases, portee)
		if case == null or not case.proprietes.has(nom_biome):
			animal.proprietes.erase(nom_local)
			continue
		animal.proprietes[nom_local] = String(case.proprietes[nom_biome])

# Le refuge EFFECTIF d'une case : la fraction du biome (posee par
# conditions.gd, JAMAIS mutee) PLUS le bonus global du toggle, borne a [0,1].
# Recompose a NEUF a chaque lecture -- geste exact de
# banc_biomes.gd:appliquer_climat : la valeur du catalogue reste la reference
# immuable, un '+=' sur la case l'aurait fait deriver au premier tick manque.
# Case sans biome (donc sans fraction_refuge) : 0.0, aucun couvert.
static func refuge_effectif(case: Variant, bonus: float, config: Dictionary) -> float:
	if case == null:
		return 0.0
	var base: float = float(case.proprietes.get(String(config.nom_fraction_refuge), 0.0))
	return clamp(base + bonus, 0.0, 1.0)

static func bonus_refuge(refuge_leve: bool, config: Dictionary) -> float:
	return float(config.bonus_refuge_toggle) if refuge_leve else 0.0

# UNIQUE ECRIVAIN de proprietes.profil_saillance (voir en-tete, LIGNE 1). Rend
# les CHANGEMENTS ({ id, avant, apres }) et non l'etat : une proie qui reste
# cachee n'y figure jamais.
static func poser_profils_proies(animaux: Array, cases: Array, bonus: float, config: Dictionary) -> Array:
	var seuil: float = float(config.seuil_refuge_cachee)
	var expose := String(config.profil_proie_exposee)
	var cache := String(config.profil_proie_cachee)
	var changements: Array = []
	for animal in animaux:
		if not est_proie(animal, config):
			continue
		var case: Variant = case_sous(animal, cases, float(config.portee_appariement))
		var apres: String = cache if refuge_effectif(case, bonus, config) >= seuil else expose
		var avant: String = String(animal.proprietes.get("profil_saillance", ""))
		animal.proprietes["profil_saillance"] = apres
		if avant != apres:
			changements.append({"id": String(animal.id), "avant": avant, "apres": apres})
	return changements

static func est_proie(animal: Dictionary, config: Dictionary) -> bool:
	return String(animal.proprietes.get(String(config.nom_espece), "")) == String(config.valeur_espece_proie)

static func est_predateur(animal: Dictionary, config: Dictionary) -> bool:
	return String(animal.proprietes.get(String(config.nom_espece), "")) == String(config.valeur_espece_predateur)

# Populations PAR BIOME -- deux appels a comptage.gd par biome et rien d'autre,
# zero ligne de mecanisme (patron banc_menace_combat.gd:ratio_effectifs). La
# LISTE est construite ici (filtrage sur la cle plate 'biome_local'), jamais
# par comptage.gd, qui ne sait rien de l'espace. Le total compte proies ET
# predateurs : une capacite de charge est ce que le milieu nourrit, pas ce
# qu'une espece y occupe. Rend { biome -> { proies, predateurs, total } }.
static func populations_par_biome(animaux: Array, cases: Array, catalogue_comptages: Dictionary, config: Dictionary) -> Dictionary:
	var nom_biome := String(config.nom_biome)
	var nom_local := String(config.nom_biome_local)
	var populations: Dictionary = {}
	for case in cases:
		var biome: String = String(case.proprietes.get(nom_biome, ""))
		if biome == "" or populations.has(biome):
			continue
		var sur_place: Array = []
		for animal in animaux:
			if String(animal.proprietes.get(nom_local, "")) == biome:
				sur_place.append(animal)
		var proies: int = Comptage.compter(sur_place, String(config.regle_proie), catalogue_comptages)
		var predateurs: int = Comptage.compter(sur_place, String(config.regle_predateur), catalogue_comptages)
		populations[biome] = {"proies": proies, "predateurs": predateurs, "total": proies + predateurs}
	return populations

# Recopie le comptage en cle PLATE sur chaque case -- seul moyen pour
# seuil_etat.gd de le comparer (il ne lit ni un int rendu par un appel, ni un
# chemin en points). RECALCULE A NEUF chaque tick, jamais accumule : c'est ce
# qui rend 'surpeuplement' reversible sans une ligne de plus. Une case sans
# biome recoit 0.0 -- elle ne porte pas de 'capacite_charge' non plus, donc
# seuil_etat.gd repliera sur INF et ne posera jamais rien.
static func poser_population_locale(cases: Array, populations: Dictionary, config: Dictionary) -> void:
	var nom_biome := String(config.nom_biome)
	var nom_population := String(config.nom_population_locale)
	for case in cases:
		var biome: String = String(case.proprietes.get(nom_biome, ""))
		case.proprietes[nom_population] = float(populations.get(biome, {}).get("total", 0))

# Quels biomes sont en surpeuplement CE tick -- lu sur etats_actifs des cases,
# jamais une variable tenue a cote (meme discipline que
# banc_menace_combat.gd:sortie_active).
static func biomes_surpeuples(cases: Array, config: Dictionary) -> Dictionary:
	var nom_biome := String(config.nom_biome)
	var surpeuples: Dictionary = {}
	for case in cases:
		var biome: String = String(case.proprietes.get(nom_biome, ""))
		if biome == "":
			continue
		if case.proprietes.get("etats_actifs", []).has(String(config.nom_etat_surpeuplement)):
			surpeuples[biome] = true
	return surpeuples

# DENSITE de proies autour d'un predateur, mesuree dans un rayon FIXE
# (config.rayon_echantillon) qui n'a AUCUN rapport avec son territoire courant
# -- voir en-tete, LE PIEGE. Deux gestes de cablage : une requete spatiale
# (monde.choses_dans_rayon) puis un Comptage.compter, aucun mecanisme neuf.
static func densite_proies(predateur: Dictionary, monde, catalogue_comptages: Dictionary, config: Dictionary) -> float:
	var candidats: Array = []
	for entree in monde.choses_dans_rayon(predateur.position, float(config.rayon_echantillon)):
		candidats.append(entree.chose)
	var proies: int = Comptage.compter(candidats, String(config.regle_proie), catalogue_comptages)
	var reference: float = float(config.densite_reference)
	if reference <= 0.0:
		push_error("banc_ecosysteme_terrain : densite_reference nulle ou negative, densite forcee a 0.0")
		return 0.0
	return float(proies) / reference

# LE TERRITOIRE, recalcule A NEUF depuis rayon_territoire_base -- jamais depuis
# la portee courante du canal, sans quoi il derivertait tick apres tick.
# max(0.1, densite) : aucune proie a portee ne rend JAMAIS INF, il rend le
# rayon maximum. Le plafond est du cablage (voir en-tete).
static func rayon_territoire(densite: float, config: Dictionary) -> float:
	var diviseur: float = max(0.1, densite)
	return min(float(config.rayon_territoire_base) / diviseur, float(config.rayon_territoire_max))

# UNIQUE ECRIVAIN de canaux_config.<vue>.portee -- PREMIER ECRIVAIN DYNAMIQUE
# de canaux_config du depot (voir en-tete, LIGNE 4). Ecrit AUSSI la cle plate
# 'rayon_territoire', pour que le label et le cercle relisent un nombre deja
# calcule sans jamais rien recalculer (meme discipline que
# banc_faim_thermo.gd). Canal absent : push_error, rien n'ecrit -- jamais un
# canal invente a la volee.
static func poser_territoire(predateur: Dictionary, rayon: float, config: Dictionary) -> void:
	var nom_canal := String(config.nom_canal_vue)
	var canaux_config: Dictionary = predateur.proprietes.get("canaux_config", {})
	if not canaux_config.has(nom_canal):
		push_error("banc_ecosysteme_terrain : canal '%s' absent de canaux_config, territoire non pose" % nom_canal)
		return
	canaux_config[nom_canal]["portee"] = rayon
	predateur.proprietes[String(config.nom_rayon_territoire)] = rayon

# CE QUE LE PREDATEUR RETIENT REELLEMENT. perception.gd rend tout ce qui est
# dans la portee (donc les proies cachees AUSSI, et les autres predateurs) ;
# proximite.gd resout leur profil et rend une saillance. Le tri final est ICI :
# seules les PROIES dont la saillance depasse seuil_perception_proie sont
# retenues. C'est ce seuil, jamais proximite.gd, qui rend une proie cachee
# inatteignable (voir en-tete, LIGNE 1).
# Ordre DETERMINISTE : saillance decroissante, egalites departagees par id --
# l'ordre d'une requete spatiale ne doit jamais decider de ce que le predateur
# chasse.
static func proies_percues(
	predateur: Dictionary,
	monde,
	catalogue_canaux: Dictionary,
	profils_saillance: Dictionary,
	config: Dictionary,
) -> Array:
	var perceptions: Array = Perception.percevoir(predateur, monde, catalogue_canaux)
	var resultats: Array = Proximite.evaluer(perceptions, predateur, profils_saillance)
	var seuil: float = float(config.seuil_perception_proie)
	var retenues: Array = []
	for resultat in resultats:
		if float(resultat.saillance) < seuil:
			continue
		if not est_proie(resultat.chose, config):
			continue
		retenues.append(resultat)
	retenues.sort_custom(func(a, b):
		if is_equal_approx(float(a.saillance), float(b.saillance)):
			return String(a.chose.id) < String(b.chose.id)
		return float(a.saillance) > float(b.saillance))
	return retenues

# LA CHASSE : consommer.gd tel quel, transfert CONSERVE (le receveur est
# credite de ce que la source a REELLEMENT perdu -- le bug de sur-credit que
# banc_fertilite.gd contournait a ete ferme depuis dans consommer.gd, plus
# rien a pre-borner ici). Ne transforme jamais la proie videe en autre chose :
# consommer.gd ne transforme rien (meme discipline que frappe.gd), et ce banc
# n'a pas de terminus a produire -- une proie a reserve nulle est simplement
# retiree du monde. Rend la quantite reellement transferee.
static func chasser(predateur: Dictionary, proie: Dictionary, config: Dictionary, delta: float) -> float:
	var nom := String(config.nom_reserve_energie)
	var resultat: Dictionary = Consommer.transferer(proie, predateur, nom, nom, float(config.taux_predation), delta)
	return float(resultat.quantite)

# UNIQUE ECRIVAIN de canal.surcout_action (voir en-tete). Somme les DEUX
# contributions et ecrit UNE fois, puis rend la decomposition pour que
# l'affichage la relise sans jamais rien recalculer. Canal absent : push_error,
# rien n'est ecrit.
static func poser_surcout_action(animal: Dictionary, en_chasse: bool, surpeuple: bool, config: Dictionary) -> Dictionary:
	var chasse: float = float(config.surcout_chasse) if en_chasse else 0.0
	var foule: float = float(config.surcout_surpeuplement) if surpeuple else 0.0
	var reserves: Dictionary = animal.proprietes.get("reserves", {})
	var nom := String(config.nom_reserve_energie)
	if not reserves.has(nom):
		push_error("banc_ecosysteme_terrain : canal '%s' absent de '%s', surcout non pose" % [nom, animal.get("id", "?")])
		return {"chasse": chasse, "surpeuplement": foule, "total": 0.0}
	reserves[nom]["surcout_action"] = chasse + foule
	return {"chasse": chasse, "surpeuplement": foule, "total": chasse + foule}

# ECRETAGE AU PLAFOND -- du CABLAGE, jamais un mecanisme : depense.gd borne le
# BAS (0.0) et RIEN dans le coeur ne borne le HAUT d'une reserve (meme constat
# que banc_fertilite.gd:plafonner_fertilite). Sans lui une proie qui broute
# sans predateur, ou un predateur qui se gave, monteraient sans fin. Le surplus
# est PERDU, jamais reverse ailleurs.
static func plafonner_energie(animaux: Array, config: Dictionary) -> void:
	var capacite: float = float(config.capacite_energie)
	var nom := String(config.nom_reserve_energie)
	for animal in animaux:
		var canal: Dictionary = animal.proprietes.get("reserves", {}).get(nom, {})
		if float(canal.get("reserve", 0.0)) > capacite:
			canal["reserve"] = capacite

# LE MIROIR PLAT, ecrit APRES Depense.avancer pour que le seuil de faim compare
# la reserve de CE tick (voir en-tete). RECALCULE A NEUF, jamais '+=' : c'est
# ce recalcul, et lui seul, qui rend 'affame' reversible.
static func poser_manque_energie(animal: Dictionary, config: Dictionary) -> float:
	var canal: Dictionary = animal.proprietes.get("reserves", {}).get(String(config.nom_reserve_energie), {})
	var manque: float = max(0.0, float(config.capacite_energie) - float(canal.get("reserve", 0.0)))
	animal.proprietes[String(config.nom_manque_energie)] = manque
	return manque

static func energie_de(animal: Dictionary, config: Dictionary) -> float:
	return float(animal.proprietes.get("reserves", {}).get(String(config.nom_reserve_energie), {}).get("reserve", 0.0))

# LA MORT EST UN GATE DE CABLAGE, jamais un etat (voir en-tete, LIGNE 2).
static func vivant(animal: Dictionary, config: Dictionary) -> bool:
	return energie_de(animal, config) > 0.0

static func survivants(animaux: Array, config: Dictionary) -> Array:
	var restants: Array = []
	for animal in animaux:
		if vivant(animal, config):
			restants.append(animal)
	return restants

static func morts_de(animaux: Array, config: Dictionary) -> Array:
	var morts: Array = []
	for animal in animaux:
		if not vivant(animal, config):
			morts.append({"id": String(animal.id), "espece": String(animal.proprietes.get(String(config.nom_espece), ""))})
	return morts

# Compare deux instantanes d'etats_actifs -- seuil_etat.gd rend les ids ayant
# bascule, jamais QUELS etats. Recopie de banc_faim_thermo.gd:changements_etats.
static func changements_surpeuplement(avant: Dictionary, cases: Array, config: Dictionary) -> Array:
	var nom_etat := String(config.nom_etat_surpeuplement)
	var changements: Array = []
	for case in cases:
		var etait: bool = bool(avant.get(String(case.id), false))
		var est: bool = case.proprietes.get("etats_actifs", []).has(nom_etat)
		if etait != est:
			changements.append({"id": String(case.id), "surpeuple": est})
	return changements

static func instantane_surpeuplement(cases: Array, config: Dictionary) -> Dictionary:
	var nom_etat := String(config.nom_etat_surpeuplement)
	var instantane: Dictionary = {}
	for case in cases:
		instantane[String(case.id)] = case.proprietes.get("etats_actifs", []).has(nom_etat)
	return instantane

# UN PAS COMPLET. ORDRE FIXE ET ASSUME, aucune permutation innocente :
#   1. biomes (conditions.gd) -- refuge et capacite reposes a neuf ;
#   2. biome_local sur chaque animal -- il faut le biome AVANT de compter ;
#   3. profils des proies -- le refuge de CE tick, pas du precedent ;
#   4. populations puis population_locale ;
#   5. surpeuplement (seuils LOCAUX) -- avant le surcout qui le lit ;
#   6. territoires -- avant la perception, qui lit la portee ;
#   7. perception : qui chasse quoi, sans encore rien transferer ;
#   8. surcout (UNIQUE ECRIVAIN) puis depense ;
#   9. LA CHASSE, EN DERNIER -- voir le resultat negatif ecrit dans avancer() ;
#  10. plafond, miroir ;
#  11. faim/famine (seuils PARTAGES) -- apres tout mouvement d'energie ;
#  12. deplacement a la vitesse EFFECTIVE (etat_effectif.gd) ;
#  13. morts.
# Inverser 5 et 8 ferait payer le surcout du tick PRECEDENT ; inverser 6 et 7
# ferait percevoir avec le territoire du tick precedent ; inverser 8 et 9
# empecherait TOUTE proie de mourir d'etre mangee (mesure en scene reelle).
# Rend tout ce que le rendu et les traces affichent, jamais recalcule ailleurs.
static func avancer(
	cases: Array,
	animaux: Array,
	monde,
	config: Dictionary,
	catalogue_biomes: Array,
	catalogue_comptages: Dictionary,
	catalogue_seuils_partages: Dictionary,
	catalogue_etats: Dictionary,
	catalogue_canaux: Dictionary,
	profils_saillance: Dictionary,
	bonus: float,
	delta: float,
) -> Dictionary:
	var changements_biome := evaluer_biomes(cases, catalogue_biomes, String(config.nom_biome))
	poser_biome_local(animaux, cases, config)
	var changements_profil := poser_profils_proies(animaux, cases, bonus, config)

	var populations := populations_par_biome(animaux, cases, catalogue_comptages, config)
	poser_population_locale(cases, populations, config)
	var avant_surpeuplement := instantane_surpeuplement(cases, config)
	SeuilEtat.avancer(cases, config.get("seuils_locaux", {}))
	var changements_foule := changements_surpeuplement(avant_surpeuplement, cases, config)
	var surpeuples := biomes_surpeuples(cases, config)

	var etats_predateurs: Array = []
	var cibles: Dictionary = {}
	for animal in animaux:
		if not est_predateur(animal, config):
			continue
		var densite := densite_proies(animal, monde, catalogue_comptages, config)
		poser_territoire(animal, rayon_territoire(densite, config), config)
		var percues := proies_percues(animal, monde, catalogue_canaux, profils_saillance, config)
		var cible_id := ""
		if not percues.is_empty():
			var cible: Dictionary = percues[0].chose
			cible_id = String(cible.id)
			cibles[String(animal.id)] = cible
		etats_predateurs.append({
			"id": String(animal.id),
			"densite": densite,
			"rayon": float(animal.proprietes.get(String(config.nom_rayon_territoire), 0.0)),
			"percues": percues.size(),
			"cible_id": cible_id,
			"mange": 0.0,
		})

	for animal in animaux:
		var en_chasse: bool = cibles.has(String(animal.id))
		var surpeuple: bool = surpeuples.has(String(animal.proprietes.get(String(config.nom_biome_local), "")))
		poser_surcout_action(animal, en_chasse, surpeuple, config)

	Depense.avancer(animaux, delta)

	# LA CHASSE EST LE DERNIER MOUVEMENT D'ENERGIE DU TICK, APRES Depense --
	# RESULTAT NEGATIF MESURE EN SCENE REELLE, invisible au test, a ne pas
	# repayer. Dans le premier jet, la chasse passait AVANT depense.gd : la
	# proie etait videe, puis son cout_base NEGATIF (le broutage) la
	# remplissait de taux_broutage * delta dans le meme tick. Consequence,
	# constatee console en main : une proie chassee se stabilisait a
	# taux_broutage * delta (0.07 a 60 images/s) et NE MOURAIT JAMAIS, et le
	# predateur ne recevait plus que ce meme filet -- il perdait de l'energie
	# EN CHASSANT une proie qu'il ne pouvait pas achever. Rien ne rougissait
	# nulle part : les deux mecanismes faisaient exactement ce qu'ils
	# promettent, c'est leur ORDRE qui etait faux. Chasser en dernier fait
	# ponctionner un stock DEJA reconstitue -- la proie descend reellement de
	# (taux_predation - taux_broutage) par seconde, et le dernier transfert la
	# vide a zero exact.
	for animal in animaux:
		if not cibles.has(String(animal.id)):
			continue
		var cible: Dictionary = cibles[String(animal.id)]
		if not Portee.en_portee(animal.position, cible.position, float(config.portee_capture)):
			continue
		var mange := chasser(animal, cible, config, delta)
		for etat in etats_predateurs:
			if String(etat.id) == String(animal.id):
				etat["mange"] = mange

	plafonner_energie(animaux, config)
	for animal in animaux:
		poser_manque_energie(animal, config)
	SeuilEtat.avancer(animaux, catalogue_seuils_partages)

	for animal in animaux:
		if not cibles.has(String(animal.id)):
			continue
		var vitesse: float = EtatEffectif.valeur(animal, String(config.nom_vitesse), catalogue_etats)
		if vitesse > 0.0:
			animal.position = BancCommun.bouger_vers(animal.position, cibles[String(animal.id)].position, vitesse, delta)

	for etat in etats_predateurs:
		var predateur := _animal_par_id(animaux, String(etat.id))
		etat["energie"] = energie_de(predateur, config) if not predateur.is_empty() else 0.0
		etat["etats"] = predateur.proprietes.get("etats_actifs", []).duplicate() if not predateur.is_empty() else []

	return {
		"changements_biome": changements_biome,
		"changements_profil": changements_profil,
		"changements_surpeuplement": changements_foule,
		"populations": populations,
		"surpeuples": surpeuples,
		"predateurs": etats_predateurs,
		"morts": morts_de(animaux, config),
		"survivants": survivants(animaux, config),
	}

static func _animal_par_id(animaux: Array, id: String) -> Dictionary:
	for animal in animaux:
		if String(animal.id) == id:
			return animal
	return {}

static func compter_especes(animaux: Array, config: Dictionary) -> Dictionary:
	var proies := 0
	var predateurs := 0
	for animal in animaux:
		if est_proie(animal, config):
			proies += 1
		elif est_predateur(animal, config):
			predateurs += 1
	return {"proies": proies, "predateurs": predateurs}

# ---- Textes (purs) ----

static func texte_label_case(case: Dictionary, config: Dictionary) -> String:
	var p: Dictionary = case.proprietes
	var biome: String = String(p.get(String(config.nom_biome), ""))
	var refuge: float = float(p.get(String(config.nom_fraction_refuge), 0.0))
	var capacite: float = float(p.get(String(config.nom_capacite_charge), 0.0))
	var population: float = float(p.get(String(config.nom_population_locale), 0.0))
	var surpeuple: bool = p.get("etats_actifs", []).has(String(config.nom_etat_surpeuplement))
	return "%s\nrefuge %.2f\npop %d / %.0f%s" % [
		biome if biome != "" else "-", refuge, int(population), capacite,
		"\nSURPEUPLE" if surpeuple else "",
	]

static func texte_label_predateur(etat: Dictionary, config: Dictionary) -> String:
	var noms: Array = []
	for nom in etat.get("etats", []):
		noms.append(String(nom))
	noms.sort()
	return "%s\nenergie %.1f / %.0f\nterritoire %.0f (densite %.2f)\nproies percues %d%s\n%s" % [
		String(etat.id), float(etat.energie), float(config.capacite_energie),
		float(etat.rayon), float(etat.densite), int(etat.percues),
		" -> %s" % String(etat.cible_id) if String(etat.cible_id) != "" else "",
		" + ".join(noms) if not noms.is_empty() else "-",
	]

static func texte_compteur(animaux: Array, morts: int, config: Dictionary) -> String:
	var comptes := compter_especes(animaux, config)
	return "proies %d | predateurs %d | morts %d" % [comptes.proies, comptes.predateurs, morts]

static func ligne_pose(cases: Array, animaux: Array, config: Dictionary) -> String:
	var comptes := compter_especes(animaux, config)
	return "t=0.0 terrain pose : %d cases, %d proies, %d predateurs -- clic gauche = refuge, clic droit = renfort de proies" % [
		cases.size(), comptes.proies, comptes.predateurs,
	]

static func ligne_changement_biome(t: float, changement: Dictionary) -> String:
	return "t=%.1f %s : biome %s -> %s" % [
		t, String(changement.id),
		String(changement.avant) if String(changement.avant) != "" else "aucun",
		String(changement.apres) if String(changement.apres) != "" else "aucun",
	]

static func ligne_changement_profil(t: float, changement: Dictionary) -> String:
	return "t=%.1f %s : profil de saillance %s -> %s" % [
		t, String(changement.id),
		String(changement.avant) if String(changement.avant) != "" else "aucun",
		String(changement.apres),
	]

static func ligne_changement_surpeuplement(t: float, changement: Dictionary) -> String:
	return "t=%.1f %s : surpeuplement %s" % [t, String(changement.id), "POSE" if changement.surpeuple else "RETIRE"]

static func ligne_mort(t: float, mort: Dictionary) -> String:
	return "t=%.1f %s (%s) MORT de faim -- retire du monde" % [t, String(mort.id), String(mort.espece)]

static func ligne_toggle_refuge(t: float, leve: bool, config: Dictionary) -> String:
	return "t=%.1f refuge %s (+%.2f sur la fraction de chaque biome)" % [
		t, "LEVE" if leve else "RETABLI", float(config.bonus_refuge_toggle) if leve else 0.0,
	]

static func ligne_toggle_renfort(t: float, pose: bool, animaux: Array, config: Dictionary) -> String:
	var comptes := compter_especes(animaux, config)
	return "t=%.1f renfort de proies %s -- %d proies au total" % [t, "POSE" if pose else "RETIRE", comptes.proies]

static func ligne_trace(t: float, resultat: Dictionary, morts: int, config: Dictionary) -> String:
	var morceaux: Array = []
	var biomes: Array = resultat.populations.keys()
	biomes.sort()
	for biome in biomes:
		var p: Dictionary = resultat.populations[biome]
		morceaux.append("%s %d/%d%s" % [
			String(biome), int(p.total), int(p.proies),
			" SURPEUPLE" if resultat.surpeuples.has(biome) else "",
		])
	var predateurs: Array = []
	for etat in resultat.predateurs:
		predateurs.append("%s e=%.1f r=%.0f v=%d" % [
			String(etat.id), float(etat.energie), float(etat.rayon), int(etat.percues),
		])
	return "t=%.1f morts=%d | %s | %s" % [t, morts, " ".join(morceaux), " ".join(predateurs)]

# ---- Rendu (impur, Node) -- aucune decision, seulement couleurs et positions.

func _appliquer_renfort() -> void:
	if _renfort_pose:
		for decl in _config.get("renfort_proies", []):
			var proie := construire_proie(decl, _config)
			_animaux.append(proie)
			_creer_noeud_animal(proie)
	else:
		var ids: Array = []
		for decl in _config.get("renfort_proies", []):
			ids.append(String(decl.id))
		var restants: Array = []
		for animal in _animaux:
			if ids.has(String(animal.id)):
				continue
			restants.append(animal)
		_animaux = restants
		_retirer_noeuds_par_id(ids)
	_reconstruire_monde()

func _reconstruire_monde() -> void:
	# monde.gd n'a AUCUNE fonction de retrait (dette deja recensee) : on
	# reconstruit du neant et on re-ajoute les vivants PAR REFERENCE, donc
	# leur position, leur reserve et leurs etats survivent -- meme geste que
	# banc_menace_combat.gd:_reconstruire_monde et banc_elimination_salete.gd.
	_monde = BancCommun.monde_depuis([
		{"choses": _animaux, "type_depuis": String(_config.nom_espece)},
	])

func _retirer_noeuds(morts: Array) -> void:
	var ids: Array = []
	for mort in morts:
		ids.append(String(mort.id))
	_retirer_noeuds_par_id(ids)

func _retirer_noeuds_par_id(ids: Array) -> void:
	for id in ids:
		if _noeuds_animaux.has(id):
			_noeuds_animaux[id].queue_free()
			_noeuds_animaux.erase(id)
		if _labels_animaux.has(id):
			_labels_animaux[id].queue_free()
			_labels_animaux.erase(id)

func _creer_rendu() -> void:
	for case in _cases:
		_creer_rendu_case(case)
	for animal in _animaux:
		_creer_noeud_animal(animal)

	_label_compteur = _creer_label(16)
	_label_compteur.position = Vector2(10.0, 10.0)
	_couche_ui.add_child(_label_compteur)
	_label_aide = _creer_label(13)
	_label_aide.position = Vector2(10.0, 36.0)
	_label_aide.text = "clic gauche : lever/retablir le refuge (les proies se cachent, les predateurs meurent de faim) -- clic droit : poser/retirer un renfort de proies dans le desert (surpeuplement)"
	_couche_ui.add_child(_label_aide)

func _creer_rendu_case(case: Dictionary) -> void:
	var taille: float = float(_config.taille_case)
	var centre := Vector2(case.position.x, case.position.y)
	var noeud := ColorRect.new()
	noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noeud.size = Vector2(taille - 6.0, taille - 6.0)
	noeud.position = centre - noeud.size / 2.0
	add_child(noeud)
	_noeuds_cases[case.id] = noeud

	var label := _creer_label(11)
	label.position = centre - Vector2(taille / 2.0 - 6.0, taille / 2.0 - 4.0)
	add_child(label)
	_labels_cases[case.id] = label

func _creer_noeud_animal(animal: Dictionary) -> void:
	var predateur := est_predateur(animal, _config)
	var taille: float = float(_config.taille_predateur) if predateur else float(_config.taille_proie)
	var noeud := ColorRect.new()
	noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noeud.size = Vector2(taille, taille)
	noeud.position = Vector2(animal.position.x, animal.position.y) - noeud.size / 2.0
	add_child(noeud)
	_noeuds_animaux[String(animal.id)] = noeud
	if predateur:
		var label := _creer_label(11)
		add_child(label)
		_labels_animaux[String(animal.id)] = label

func _creer_label(taille: int) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", taille)
	# Contour sombre : le meme label doit rester lisible sur le vert fonce de
	# la foret comme sur le jaune du desert.
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	label.add_theme_constant_override("outline_size", 4)
	return label

# Les cercles de territoire : dessines a leur rayon REEL, relu sur le
# predateur, jamais un rayon decoratif qui mentirait sur la portee de
# perception effectivement posee dans canaux_config.
func _draw() -> void:
	var rgb: Array = _config.couleur_territoire
	var couleur := Color(rgb[0], rgb[1], rgb[2], 0.75)
	for animal in _animaux:
		if not est_predateur(animal, _config):
			continue
		var rayon: float = float(animal.proprietes.get(String(_config.nom_rayon_territoire), 0.0))
		if rayon <= 0.0:
			continue
		draw_arc(Vector2(animal.position.x, animal.position.y), rayon, 0.0, TAU, 96, couleur, 2.0)

func _rafraichir_tout() -> void:
	if _dernier.is_empty():
		return
	for case in _cases:
		_noeuds_cases[case.id].color = _couleur_case(case)
		_labels_cases[case.id].text = texte_label_case(case, _config)
	for animal in _animaux:
		var id := String(animal.id)
		if not _noeuds_animaux.has(id):
			continue
		var noeud: ColorRect = _noeuds_animaux[id]
		noeud.color = _couleur_animal(animal)
		noeud.position = Vector2(animal.position.x, animal.position.y) - noeud.size / 2.0
	for etat in _dernier.predateurs:
		var id := String(etat.id)
		if not _labels_animaux.has(id):
			continue
		var animal := _animal_par_id(_animaux, id)
		if animal.is_empty():
			continue
		_labels_animaux[id].position = Vector2(animal.position.x, animal.position.y) + Vector2(20.0, 16.0)
		_labels_animaux[id].text = texte_label_predateur(etat, _config)
	_label_compteur.text = texte_compteur(_animaux, _morts, _config)

func _couleur_case(case: Dictionary) -> Color:
	if case.proprietes.get("etats_actifs", []).has(String(_config.nom_etat_surpeuplement)):
		return _couleur_de(_config.couleur_surpeuplement)
	var biome: String = String(case.proprietes.get(String(_config.nom_biome), ""))
	var palette: Dictionary = _config.get("couleurs_biome", {})
	return _couleur_de(palette.get(biome, _config.couleur_aucun_biome))

func _couleur_animal(animal: Dictionary) -> Color:
	if est_predateur(animal, _config):
		return _couleur_de(_config.couleur_predateur)
	if String(animal.proprietes.get("profil_saillance", "")) == String(_config.profil_proie_cachee):
		return _couleur_de(_config.couleur_proie_cachee)
	return _couleur_de(_config.couleur_proie_exposee)

func _couleur_de(rgb: Array) -> Color:
	return Color(float(rgb[0]), float(rgb[1]), float(rgb[2]))

func _poser_camera() -> void:
	var taille: float = float(_config.taille_case)
	var camera := Camera2D.new()
	camera.position = Vector2(float(_config.grille_colonnes - 1), float(_config.grille_lignes - 1)) * taille / 2.0
	camera.zoom = Vector2(float(_config.camera_zoom), float(_config.camera_zoom))
	camera.enabled = true
	add_child(camera)

func _charger(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
