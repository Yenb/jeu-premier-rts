extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_social_foule.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1). Compose SEPT mecanismes deja
# fermes, TOUS APPELES TELS QUELS ET TOUS INCHANGES : comptage.gd, somme.gd,
# charge.gd, seuil_etat.gd, depense.gd, lien_personnel.gd (lecture seule) et
# portee.gd. AUCUN MECANISME DU COEUR TOUCHE, AUCUN .gd NEUF.
#
# CE QU'ON DOIT VOIR : vingt colons sur une grille 4x4, douze entasses dans un
# coin (trois par case, au-dessus du confort : ces cases jaunissent puis
# rougissent toutes seules) et huit au large (deux par case, au confort exact :
# elles restent vertes). La colonne de droite est BRUYANTE : les colons qui y
# dorment perdent leur sommeil au lieu de le refaire. Une barre de cohesion
# tient en haut. Quatre gestes, chacun observable seul : mettre un colon en
# colere au clic (a 3 sur 20 rien ne bouge, 0.15 n'est pas > 0.15 ; au
# QUATRIEME la fraction passe, et trois secondes plus tard -- pas avant -- la
# foule bascule en EMEUTE, et rendre un seul colon au calme la defait) ; tuer
# ou rendre le chef ; entasser ou disperser ; faire tourner le bruit d'une case
# au clic droit.
#
# ---------------------------------------------------------------------------
# TROIS PORTEURS DE CHARGE, ET C'EST UNE CONTRAINTE DURE DU MECANISME
# ---------------------------------------------------------------------------
# RESULTAT NEGATIF, a ne jamais repayer : charge.gd:avancer applique LA MEME
# liste de causes a TOUS les canaux de chaque chose. Les causes ne portent
# aucun type -- seules la POSITION et la portee du canal les selectionnent.
# DEUX CANAUX SUR LE MEME OBJET NE PEUVENT DONC PAS ETRE ALIMENTES PAR DEUX
# CAUSES DIFFERENTES, et aucune portee ne les separe : une portee large
# contient toujours la petite.
# Ce banc en veut trois, d'ou trois FAMILLES D'OBJETS DISJOINTES et trois
# appels separes :
#   - les CASES portent le stress de densite -- une densite est une propriete
#     du LIEU ;
#   - les MEMBRES portent la montee d'emeute -- une foule bascule par ceux qui
#     la composent ;
#   - LE CHEF, et lui seul, porte le choc de cohesion. Ce n'est pas un
#     pis-aller : les quatre axes de cohesion se mesurent TOUS contre lui, la
#     cohesion est une grandeur de forme chef, et son choc se porte la ou il se
#     produit. Le chef ne porte donc PAS la montee d'emeute -- un chef ne
#     bascule pas avec la foule, dit ici une fois plutot que code en cas
#     particulier ailleurs.
# CE QUI N'EST PAS FAIT : ce constat justifierait un jour des causes NOMMEES
# dans charge.gd (un champ "canal" sur la cause, filtre a l'entree). C'est un
# chantier de FRAMEWORK, il ne se bricole pas au passage (CLAUDE.md, « S'IL
# MANQUE VRAIMENT UNE MECANIQUE »). Trois familles suffisent ici et ne coutent
# rien.
#
# ---------------------------------------------------------------------------
# LES QUATRE LIGNES, ET LA VOIE RETENUE POUR CHACUNE
# ---------------------------------------------------------------------------
#
# UNE FRACTION DE LA FOULE SUFFIT A LA RETOURNER. Chaine complete :
#   Comptage.compter(en colere) / Comptage.compter(membres)   <- CABLAGE
#     -> fraction, cle PLATE sur chaque colon                  <- MIROIR
#     -> seuil_etat.gd pose le marqueur de majorite            <- SEUIL
#     -> cause synthetisee tant que ce marqueur dure           <- CABLAGE
#     -> charge.gd monte, franchit la fenetre                  <- FENETRE
#     -> miroir plat 0.0/1.0                                   <- MIROIR
#     -> seuil_etat.gd pose l'emeute.
# comptage.gd rend un int et NE DIVISE RIEN : la fraction est une division de
# cablage, denominateur passe par max(1, ...).
#   LA FENETRE EST charge.gd, PAS etat_duree.gd, et c'est la decision la plus
#   importante du banc : etat_duree.gd fait DECROITRE une intensite et retire
#   l'etat a zero, il ne monte jamais -- il ne sait donc pas dire « la fraction
#   est restee au-dessus pendant N secondes ». charge.gd est le seul mecanisme
#   qui monte tant qu'une cause dure, franchit, puis redescend seul. C'est
#   aussi ce qui rend l'emeute REVERSIBLE sans une ligne de plus.
#   LE MIROIR 0.0/1.0 N'EST PAS UNE COQUETTERIE, c'est un defaut reel de
#   chainage : charge.gd EFFACE ses cles au franchissement descendant, et
#   seuil_etat.gd SORT quand la propriete comparee est absente. Branches
#   directement, l'etat serait pose a la montee et JAMAIS retire a la descente,
#   en silence. Vaut a l'identique pour la surdensite.
#
# LE GROUPE SE DISLOQUE. La cohesion est une SOMME PONDEREE RECALCULEE A NEUF
# chaque tick, JAMAIS un `+=` : c'est la seule chose qui empeche un champ
# derive de DERIVER. Quatre axes, plus un cinquieme terme de signe oppose --
# moyenne des liens entre membres, fraction qui croit ce que croit le chef,
# fraction de sa culture, fraction ayant assez vecu, moins le choc.
#   Les trois fractions passent par Comptage.compter sur des MIROIRS PLATS, et
#   c'est obligatoire : liens_personnels et croyances sont des Dictionary
#   IMBRIQUES, aucun lecteur agrege du coeur n'y descend.
#   expression.gd N'EST PAS APPELE : rappele chaque tick, il relit ce qu'il
#   vient d'ecrire et diverge sans borne.
#   LA COHESION VIT PAR COLON, jamais dans un objet-groupe (« Les collectifs
#   n'existent pas ») -- la meme valeur ecrite sur chacun, par UN SEUL ecrivain
#   qui pose la valeur ET son miroir inverse dans le MEME geste et depuis le
#   MEME nombre. Deux ecrivains se desynchroniseraient EN SILENCE au bord exact.
#   bifurcation.gd ECARTE : lui donner une FORME (scission, desertion, revolte)
#   exige de NOMMER ces sorties, donc du contenu de jeu. Les ajouter plus tard
#   ne demandera aucune ligne de mecanisme.
#
# TROP DE MONDE STRESSE. Ce qui est compare au seuil n'est pas la densite mais
# le STRESS ACCUMULE : la densite au-dela du confort devient le POIDS d'une
# cause de charge, proportionnel a l'exces. Une case bondee un instant ne
# stresse personne, une case bondee longtemps si. A exces nul aucune cause
# n'est construite -- le gate est desactive PAR LA SEULE ARITHMETIQUE, jamais
# par une branche.
#   AUCUN RAYON DERIVE D'UNE DENSITE MESUREE DANS CE MEME RAYON : l'appariement
#   colon/case passe par une portee FIXE en donnee, et la densite est recomptee
#   A NEUF chaque tick, jamais incrementee.
#
# LE BRUIT EMPECHE DE DORMIR. Chaque case porte son bruit ; le cablage le
# recopie en cle PLATE sur le colon ; seuil_etat.gd le compare a un seuil de
# gene LU PAR COLON (un dormeur leger, un dormeur lourd) ; l'etat GATE le
# surcout du canal de sommeil, proportionnel au bruit.
#   LE SOMMEIL REMONTE PAR UN cout_base NEGATIF -- neutralite de depense.gd
#   exploitee, jamais contournee. Le bruit ne fait pas dormir moins bien : il
#   fait perdre plus vite que la recuperation ne rend.
#   La penalite passe par surcout_action et non par cout_base : ici personne ne
#   marche, l'emplacement est libre, et un seul ecrivain l'occupe.
#   LE BRUIT EST UNE PROPRIETE DE CASE, simplification assumee : le bruit du
#   depot est une EMISSION PAR SOURCE dont le niveau se calcule deja par
#   champ_occulte.gd, attenue par la distance ET les obstacles. Ce banc
#   n'observe pas la propagation du son ; le brancher un jour ne changerait
#   AUCUNE ligne en aval du miroir.
#
# ---------------------------------------------------------------------------
# CE QUE CE BANC NE MONTRE PAS, dit plutot que masque
# ---------------------------------------------------------------------------
# - AUCUN COLON NE PERCOIT NI NE DECIDE : ni perception.gd, ni proximite.gd, ni
#   dominance.gd, ni agir.gd. Les colons ne se deplacent qu'au bouton. Ce banc
#   observe une FOULE et un ENVIRONNEMENT, pas un agent.
# - LES CINQ ETATS POSES SONT DES MARQUEURS PURS, et c'est un choix : ce banc
#   ne compose EtatEffectif.valeur nulle part, il n'a donc rien a moduler.
#   Declarer une modulation serait VRAI EN DONNEE ET INERTE DANS LE JEU, en
#   silence.
# - LIEN_PERSONNEL EN LECTURE SEULE : avancer() n'est PAS appele. Les liens
#   sont poses une fois et ne decroissent jamais -- sans quoi la cohesion
#   baisserait toute seule et la dislocation finirait par arriver sans qu'aucun
#   geste ne l'ait causee, rendant le choc du chef inobservable. La
#   decroissance des liens est le sujet de banc_vecu_inter_colon.gd.
# - AUCUN HASARD, NULLE PART. Pas un RNG dans ce fichier.
# - UN TICK DE RETARD sur l'emeute seule : la cause de la fenetre lit le
#   marqueur pose au tick precedent, charge.gd tournant avant seuil_etat.gd
#   pour que la cohesion lise le choc du tick COURANT. Negligeable devant la
#   fenetre, mesurable au test, invisible a l'oeil.
# - DEUX COLONS SUPERPOSES se chargeraient mutuellement a portee nulle. Toutes
#   les positions declarees sont distinctes, au repos comme entassees.
#
# COLONS ET CASES CONSTRUITS A LA MAIN (pas Objet.fabriquer) : ni composition
# ni materiau, donc data/types.json n'est PAS touche et rien n'est a enregistrer
# dans scripts/test_lint_donnees.gd.
#
# Deux moities, meme decoupage que les autres bancs : le Node charge, construit
# et affiche, et ses clics ne font que BASCULER un booleen ou une cle, jamais
# calculer ; tout le reste est en fonctions statiques pures, testables headless.
#
# AUCUN NOM DE PROPRIETE EN DUR : noms de cle, d'etat et de regle viennent tous
# de data/banc_social_foule.json -- c'est ce qui permet au test de faire
# traverser le meme code par un domaine entierement invente.

const Comptage = preload("res://scripts/comptage.gd")
const Somme = preload("res://scripts/somme.gd")
const SeuilEtat = preload("res://scripts/seuil_etat.gd")
const Charge = preload("res://scripts/charge.gd")
const Depense = preload("res://scripts/depense.gd")
const LienPersonnel = preload("res://scripts/lien_personnel.gd")
const Portee = preload("res://scripts/portee.gd")

var _config: Dictionary = {}
var _comptages: Dictionary = {}
var _catalogue_seuils: Dictionary = {}
var _catalogue_liens: Dictionary = {}

var _cases: Array = []
var _colons: Array = []
var _entasse := false
var _temps := 0.0
var _prochaine_trace := 0.0
var _dernier: Dictionary = {}

var _couche_ui: CanvasLayer
var _noeuds_cases: Dictionary = {}
var _labels_cases: Dictionary = {}
var _marqueurs_bruit: Dictionary = {}
var _noeuds_colons: Dictionary = {}
var _barre_fond: ColorRect
var _barre_cohesion: ColorRect
var _label_compteur: Label
var _label_aide: Label

func _ready() -> void:
	_config = _charger("res://data/banc_social_foule.json")
	_comptages = _charger("res://data/comptages.json")
	_catalogue_seuils = _charger("res://data/seuils_etat.json")
	_catalogue_liens = _charger("res://data/liens_personnels.json")

	_cases = construire_cases(_config)
	_colons = construire_colons(_config)
	poser_liens(_colons, _config)

	_couche_ui = CanvasLayer.new()
	add_child(_couche_ui)
	_creer_rendu()
	_poser_camera()

	# Un premier pas a delta NUL avant la premiere image : les miroirs sont
	# ecrits, les densites comptees, la cohesion posee -- la grille s'affiche
	# donc deja renseignee (patron banc_ecosysteme_terrain.gd). delta 0.0 ne
	# fait rien avancer : Charge.avancer n'ajoute rien, Depense.avancer
	# ponctionne zero.
	_dernier = avancer(_cases, _colons, _config, _comptages, _catalogue_seuils, _catalogue_liens, 0.0)
	_rafraichir_tout()
	print(ligne_pose(_cases, _colons, _config, _dernier))

func _unhandled_input(event: InputEvent) -> void:
	# NE CALCULE RIEN : bascule une cle ou un nombre, c'est tout. Toute la
	# consequence est recalculee par avancer() au tick suivant -- meme
	# discipline que banc_ecosysteme_terrain.gd:_unhandled_input.
	if not (event is InputEventMouseButton and event.pressed):
		return
	var souris := get_global_mouse_position()
	if event.button_index == MOUSE_BUTTON_LEFT:
		var colon: Variant = colon_le_plus_proche(_colons, souris, float(_config.rendu.rayon_clic))
		if colon == null:
			return
		var fache := basculer_colere(colon, _config)
		print(ligne_toggle_colere(_temps, String(colon.id), fache))
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		var case: Variant = case_a_la_position(_cases, souris, float(_config.portee_appariement))
		if case == null:
			return
		var niveau := bruit_suivant(case, _config)
		print(ligne_toggle_bruit(_temps, String(case.id), niveau))

func _process(delta: float) -> void:
	_temps += delta
	var bilan := avancer(_cases, _colons, _config, _comptages, _catalogue_seuils, _catalogue_liens, delta)
	_dernier = bilan

	for changement in bilan.changements_colere:
		print(ligne_changement_colere(_temps, changement))
	for changement in bilan.changements_etats:
		print(ligne_changement_etat(_temps, changement))

	if _temps >= _prochaine_trace:
		_prochaine_trace = _temps + float(_config.periode_trace_s)
		print(ligne_trace(_temps, bilan, _config))

	_rafraichir_tout()

func _toggle_chef() -> void:
	var porteur := porteur_choc(_colons, _config)
	if porteur.is_empty():
		return
	var vivant := basculer_chef(porteur, _config)
	print(ligne_toggle_chef(_temps, String(porteur.id), vivant))

func _toggle_entassement() -> void:
	_entasse = not _entasse
	appliquer_entassement(_colons, _entasse)
	print(ligne_toggle_entassement(_temps, _entasse))

# ===========================================================================
# Fonctions PURES, testables headless (voir test_banc_social_foule.gd)
# ===========================================================================

# ---- Construction ----

# Grille grille_lignes x grille_colonnes, ordre ligne-majeur, positions en
# unites MONDE (colonne * taille_case). z reste 0.0 -- VERTICALITE : Vector3
# partout, meme quand la troisieme dimension ne sert pas encore.
# Chaque case porte son `bruit` (donnee, mutee par le clic droit), son
# `seuil_confort` (recopie de la config pour que la lecture soit locale, comme
# `capacite_charge` par case dans banc_ecosysteme_terrain.gd) et SON canal de
# charge -- le seul des trois du banc qu'elle porte (voir en-tete, TROIS
# PORTEURS).
static func construire_cases(config: Dictionary) -> Array:
	var taille: float = float(config.taille_case)
	var cases: Array = []
	for ligne in range(int(config.grille_lignes)):
		for colonne in range(int(config.grille_colonnes)):
			var proprietes: Dictionary = {"etats_actifs": []}
			proprietes[String(config.nom_bruit)] = bruit_declare(colonne, ligne, config)
			proprietes[String(config.nom_seuil_confort)] = float(config.densite.seuil_confort)
			proprietes[String(config.nom_densite_locale)] = 0.0
			proprietes[String(config.nom_miroir_stress)] = 0.0
			proprietes["etats"] = {
				String(config.nom_canal_stress): {
					"charge": 0.0,
					"seuil": float(config.densite.seuil),
					"portee_charge": 0.0,
					"taux_decroissance": float(config.densite.taux_decroissance),
					"poser": { String(config.nom_marqueur_stress): 1.0 },
				},
			}
			cases.append({
				"id": "case_%d_%d" % [colonne, ligne],
				"position": Vector3(float(colonne) * taille, float(ligne) * taille, 0.0),
				"proprietes": proprietes,
			})
	return cases

# Le bruit declare d'une case, ou le bruit par defaut. Une case absente de
# `cases_bruyantes` n'est pas silencieuse : elle porte le fond sonore commun --
# distinguer « pas declaree » de « declaree a zero » est exactement ce que le
# cycle du clic droit rend visible (le premier niveau du cycle EST 0.0).
static func bruit_declare(colonne: int, ligne: int, config: Dictionary) -> float:
	for declaration in config.get("cases_bruyantes", []):
		if int(declaration.colonne) == colonne and int(declaration.ligne) == ligne:
			return float(declaration.bruit)
	return float(config.bruit_par_defaut)

# Les colons, CONSTRUITS A LA MAIN (voir en-tete). Le CHEF (`chef: true` en
# donnee) porte le canal de choc et JAMAIS celui d'emeute ; tous les autres
# l'inverse -- c'est ce qui rend les trois familles disjointes.
# `x_depart`/`y_depart`/`x_entasse`/`y_entasse` sont quatre FLOTTANTS et jamais
# deux Vector3 dans proprietes : resumabilite JSON stricte (docs/design.md),
# meme precaution que banc_infrastructure.gd:construire_colons.
# `croyances` est construite ici, croyance.gd n'etant PAS cable dans ce banc --
# forme respectee a l'identique (croyances[chose][propriete] = { valeur,
# certitude }), ce qui laisse la porte ouverte a un cablage reel plus tard.
static func construire_colons(config: Dictionary) -> Array:
	var colons: Array = []
	for decl in config.get("colons", []):
		var pos: Array = decl.position
		var entassee: Array = decl.get("position_entassee", pos)
		var est_le_chef: bool = bool(decl.get("chef", false))

		var croyances: Dictionary = {}
		croyances[String(config.croyance_chose)] = {
			String(config.croyance_propriete): { "valeur": decl.get("croyance", null), "certitude": 1.0 },
		}

		var proprietes: Dictionary = {
			"etats_actifs": [],
			"liens_personnels": {},
			"croyances": croyances,
			"x_depart": float(pos[0]),
			"y_depart": float(pos[1]),
			"x_entasse": float(entassee[0]),
			"y_entasse": float(entassee[1]),
			"reserves": {
				String(config.nom_reserve_sommeil): {
					"reserve": float(config.sommeil.reserve_initiale),
					"cout_base": 0.0,
					"surcout_action": 0.0,
				},
			},
		}
		proprietes[String(config.nom_membre)] = true
		proprietes[String(config.nom_culture)] = String(decl.culture)
		proprietes[String(config.nom_cycles_vecus)] = float(decl.cycles_vecus)
		proprietes[String(config.nom_seuil_gene)] = float(decl.seuil_gene_sommeil)
		proprietes["force_lien"] = float(decl.force_lien)
		proprietes[String(config.nom_bruit_local)] = 0.0
		proprietes[String(config.nom_densite_locale)] = 0.0
		proprietes[String(config.nom_fraction_colere)] = 0.0
		if bool(decl.get("colere_initiale", false)):
			proprietes[String(config.nom_colere)] = true

		if est_le_chef:
			proprietes[String(config.nom_chef)] = true
			proprietes["etats"] = {
				String(config.nom_canal_choc): {
					"charge": 0.0,
					"seuil": float(config.choc.seuil),
					"portee_charge": 0.0,
					"taux_decroissance": float(config.choc.taux_decroissance),
					"poser": { String(config.nom_marqueur_choc): 1.0 },
				},
			}
		else:
			proprietes[String(config.nom_miroir_emeute)] = 0.0
			proprietes["etats"] = {
				String(config.nom_canal_emeute): {
					"charge": 0.0,
					"seuil": float(config.foule.fenetre_s) * float(config.foule.poids_cause),
					"portee_charge": 0.0,
					"taux_decroissance": float(config.foule.taux_decroissance),
					"poser": { String(config.nom_marqueur_emeute): 1.0 },
				},
			}

		colons.append({
			"id": String(decl.id),
			"position": Vector3(float(pos[0]), float(pos[1]), float(pos[2])),
			"proprietes": proprietes,
		})
	return colons

# Chaque colon recoit un lien personnel de SA propre force vers CHAQUE autre
# colon -- registre reel, pose par lien_personnel.gd:poser et relu par
# lien_personnel.gd:force, jamais un nombre recopie a cote. Appele UNE FOIS a
# la construction : LienPersonnel.avancer n'etant pas cable (voir en-tete), ces
# forces ne bougent plus.
# Le lien vers le chef reste pose apres sa mort -- ce sont les MEMBRES qui
# entrent dans la moyenne, et lui n'en est plus un : la moyenne l'ignore d'
# elle-meme, sans qu'aucune ligne ne retire quoi que ce soit.
static func poser_liens(colons: Array, config: Dictionary) -> void:
	for colon in colons:
		var force: float = float(colon.proprietes.get("force_lien", 0.0))
		if force <= 0.0:
			continue
		for autre in colons:
			if String(autre.id) == String(colon.id):
				continue
			LienPersonnel.poser(colon, String(autre.id), force)

# ---- Lectures de structure ----

static func membres_de(colons: Array, config: Dictionary) -> Array:
	var cle := String(config.nom_membre)
	var membres: Array = []
	for colon in colons:
		if colon.proprietes.has(cle):
			membres.append(colon)
	return membres

# Les colons qui portent le canal d'emeute -- tous sauf le porteur du choc.
# Lu sur `etats`, jamais deduit d'un `est_chef` : c'est le CANAL qui decide de
# quelle famille un objet releve (voir en-tete, TROIS PORTEURS).
static func porteurs_emeute(colons: Array, config: Dictionary) -> Array:
	var nom := String(config.nom_canal_emeute)
	var porteurs: Array = []
	for colon in colons:
		if colon.proprietes.get("etats", {}).has(nom):
			porteurs.append(colon)
	return porteurs

# LE PORTEUR DU CHOC : celui qui porte le canal, vivant ou mort. A ne pas
# confondre avec `chef_vivant` -- le porteur ne disparait jamais (le cadavre
# reste dans le monde), c'est la CLE de chef qui se retire.
static func porteur_choc(colons: Array, config: Dictionary) -> Dictionary:
	var nom := String(config.nom_canal_choc)
	for colon in colons:
		if colon.proprietes.get("etats", {}).has(nom):
			return colon
	push_error("banc_social_foule : aucun porteur du canal '%s'" % nom)
	return {}

static func chef_vivant(colons: Array, config: Dictionary) -> bool:
	var cle := String(config.nom_chef)
	for colon in colons:
		if colon.proprietes.has(cle):
			return true
	return false

# ---- Appariement colon / case ----

# APPARIEMENT « quelle case sous cette chose » -- du CABLAGE, jamais un
# mecanisme : comparaison de positions deleguee a Portee.en_portee, jamais
# reimplementee. Patron exact banc_ecosysteme_terrain.gd:case_sous. Rend null
# si aucune case ne coincide (une chose hors grille n'est sur aucune case, cas
# neutre legitime).
static func case_sous(objet: Dictionary, cases: Array, portee_appariement: float) -> Variant:
	for case in cases:
		if Portee.en_portee(case.position, objet.position, portee_appariement):
			return case
	return null

# Recopie sur chaque colon l'id de la case sous lui ET son bruit, en cles
# PLATES. C'est cette recopie, et elle seule, qui permet ensuite a comptage.gd
# de compter « par case » (il n'a AUCUNE notion d'espace) et a seuil_etat.gd de
# comparer le bruit (il ne lit qu'une cle plate). Un colon hors grille perd les
# deux -- jamais une case ni un bruit inventes.
static func poser_case_locale(colons: Array, cases: Array, config: Dictionary) -> void:
	var nom_case := String(config.nom_case_locale)
	var nom_bruit := String(config.nom_bruit)
	var nom_bruit_local := String(config.nom_bruit_local)
	var portee := float(config.portee_appariement)
	for colon in colons:
		var case: Variant = case_sous(colon, cases, portee)
		if case == null:
			colon.proprietes.erase(nom_case)
			colon.proprietes.erase(nom_bruit_local)
			continue
		colon.proprietes[nom_case] = String(case.id)
		colon.proprietes[nom_bruit_local] = float(case.proprietes.get(nom_bruit, 0.0))

# ---- LIGNE 5 : la bascule de foule ----

# UNIQUE ECRIVAIN du nom d'etat de colere dans etats_actifs. La verite est la
# cle PLATE (posee par le clic, comptee par comptage.gd, qui ne sait pas lire
# un Array de String) ; cet etat n'en est que le REFLET. Deux ecrivains
# diraient deux verites qui divergeraient au bord, sans qu'aucun test ne
# rougisse -- meme parade que banc_infrastructure.gd:poser_encombrement, qui
# pose son etat depuis le meme predicat que son gate.
# Rend les CHANGEMENTS ({ id, en_colere }), jamais l'etat : sans quoi la
# console cracherait vingt lignes par image.
static func poser_etat_colere(colons: Array, config: Dictionary) -> Array:
	var etat := String(config.etat_colere)
	var cle := String(config.nom_colere)
	var changements: Array = []
	for colon in colons:
		var actifs: Array = colon.proprietes.get("etats_actifs", [])
		var veut: bool = colon.proprietes.has(cle)
		var present: bool = actifs.has(etat)
		if veut and not present:
			actifs.append(etat)
			changements.append({"id": String(colon.id), "en_colere": true})
		elif present and not veut:
			actifs.erase(etat)
			changements.append({"id": String(colon.id), "en_colere": false})
		colon.proprietes["etats_actifs"] = actifs
	return changements

# LA FRACTION : deux Comptage.compter et une division, zero ligne de mecanisme
# (patron banc_menace_combat.gd:ratio_effectifs). comptage.gd rend un int et ne
# divise rien -- c'est ecrit dans son en-tete. Le denominateur passe par
# max(1, ...) : aucune division par zero, meme si tous les membres
# disparaissaient.
static func fraction_colere(colons: Array, comptages: Dictionary, config: Dictionary) -> float:
	var membres: int = Comptage.compter(colons, String(config.regle_membres), comptages)
	var faches: int = Comptage.compter(colons, String(config.regle_colere), comptages)
	return float(faches) / float(max(1, membres))

# Recopie la fraction en cle PLATE sur chaque colon -- seul moyen pour
# seuil_etat.gd de la comparer. RECALCULEE A NEUF chaque tick, jamais
# accumulee : c'est ce recalcul, et lui seul, qui rend `colere_majoritaire`
# reversible sans une ligne de plus.
static func poser_fraction_colere(colons: Array, fraction: float, config: Dictionary) -> void:
	var cle := String(config.nom_fraction_colere)
	for colon in colons:
		colon.proprietes[cle] = fraction

# CAUSE SYNTHETISEE, le geste que charge.gd rend possible sans rien connaitre :
# il ne lit jamais une propriete, il ne recoit qu'un Array de { position,
# poids } construit par l'appelant. La cause est ici le colon LUI-MEME, a sa
# propre position -- combinee a portee_charge 0.0, elle ne peut alimenter QUE
# le canal du colon qui l'a produite (patron litteral
# banc_fatigue_circadien.gd:causes_dette).
static func causes_emeute(colons: Array, config: Dictionary) -> Array:
	var etat := String(config.etat_colere_majoritaire)
	var poids: float = float(config.foule.poids_cause)
	var causes: Array = []
	for colon in porteurs_emeute(colons, config):
		if not colon.proprietes.get("etats_actifs", []).has(etat):
			continue
		causes.append({"position": colon.position, "poids": poids})
	return causes

# ---- LIGNE 7 : la cohesion ----

static func causes_choc(porteur: Dictionary, vivant: bool, config: Dictionary) -> Array:
	if vivant or porteur.is_empty():
		return []
	return [{"position": porteur.position, "poids": float(config.choc.poids_cause)}]

# La valeur crue d'un colon sur la chose et la propriete surveillees. Rend null
# si le colon n'a pas d'avis -- distinct de « il croit false ». Lecture directe
# du Dictionary imbriquee de croyance.gd : le mecanisme n'expose aucun getter
# (ses quatre fonctions sont observer/filtrer/corriger/avancer), et ce banc ne
# le cable pas.
static func croyance_de(colon: Dictionary, chose: String, propriete: String):
	var par_chose: Dictionary = colon.proprietes.get("croyances", {}).get(chose, {})
	if not par_chose.has(propriete):
		return null
	return par_chose[propriete].get("valeur", null)

# La moyenne des forces de lien de CE colon vers les autres MEMBRES. Passe par
# LienPersonnel.force (lecture pure du mecanisme), jamais par une lecture
# directe de proprietes.liens_personnels. Aucun membre en face : 0.0, point
# neutre legitime -- un colon seul n'est lie a personne.
static func force_liens_moyenne(colon: Dictionary, membres: Array, catalogue_liens: Dictionary) -> float:
	var total := 0.0
	var nombre := 0
	for autre in membres:
		if String(autre.id) == String(colon.id):
			continue
		total += LienPersonnel.force(colon, String(autre.id), catalogue_liens)
		nombre += 1
	if nombre == 0:
		return 0.0
	return total / float(nombre)

# LES TROIS MIROIRS PLATS DES AXES, poses ou RETIRES (jamais mis a false : les
# regles de data/comptages.json sont en mode « presente », qui compte une cle
# presente QUELLE QUE SOIT sa valeur). Obligatoires, constat (D) de l'audit :
# `croyances` est un Dictionary imbrique qu'aucun lecteur agrege n'atteint, et
# une EGALITE ENTRE DEUX OBJETS n'est lisible par aucun mecanisme du coeur
# (constat (E)) -- la comparaison au chef vit donc ici, a sa place.
# La reference est le PORTEUR du choc, vivant ou mort : ce que le groupe
# partageait ne disparait pas avec celui qui l'incarnait. C'est ce qui rend le
# choc ISOLABLE -- tuer le chef ne fait bouger QUE la charge, jamais les axes.
static func poser_axes(colons: Array, reference: Dictionary, config: Dictionary, catalogue_liens: Dictionary) -> void:
	var cle_croyance := String(config.nom_croyance_partagee)
	var cle_culture := String(config.nom_culture_partagee)
	var cle_force := String(config.nom_force_liens_locale)
	var chose := String(config.croyance_chose)
	var propriete := String(config.croyance_propriete)
	var membres := membres_de(colons, config)

	var croyance_reference = null
	var culture_reference := ""
	if not reference.is_empty():
		croyance_reference = croyance_de(reference, chose, propriete)
		culture_reference = String(reference.proprietes.get(String(config.nom_culture), ""))

	for colon in colons:
		if croyance_reference != null and croyance_de(colon, chose, propriete) == croyance_reference:
			colon.proprietes[cle_croyance] = true
		else:
			colon.proprietes.erase(cle_croyance)
		if culture_reference != "" and String(colon.proprietes.get(String(config.nom_culture), "")) == culture_reference:
			colon.proprietes[cle_culture] = true
		else:
			colon.proprietes.erase(cle_culture)
		colon.proprietes[cle_force] = force_liens_moyenne(colon, membres, catalogue_liens)

# LES QUATRE AXES, chacun une FRACTION dans [0, 1]. Trois passent par
# Comptage.compter (combien d'entites), le quatrieme par Somme.propriete
# (combien au total) -- les deux briques de la couche lecteur, chacune sur la
# question qui est la sienne : « combien sont d'accord » n'est pas « combien
# tiennent les uns aux autres ». Aucun objet-groupe n'est jamais construit :
# tout est refait A NEUF a chaque appel.
static func calculer_axes(colons: Array, comptages: Dictionary, config: Dictionary) -> Dictionary:
	var membres := membres_de(colons, config)
	var n := float(max(1, membres.size()))
	var reference: float = float(config.cohesion.reference_liens)
	var somme_forces: float = Somme.propriete(membres, String(config.nom_force_liens_locale))
	var liens := 0.0
	if reference > 0.0:
		liens = clamp(somme_forces / n / reference, 0.0, 1.0)
	else:
		push_error("banc_social_foule : reference_liens nulle ou negative, axe des liens force a 0.0")
	return {
		"liens": liens,
		"croyance": float(Comptage.compter(membres, String(config.regle_croyance_partagee), comptages)) / n,
		"culture": float(Comptage.compter(membres, String(config.regle_culture_partagee), comptages)) / n,
		"vecu": float(Comptage.compter(membres, String(config.regle_vecu_suffisant), comptages)) / n,
		"membres": membres.size(),
	}

static func charge_de(objet: Dictionary, nom_canal: String) -> float:
	return float(objet.get("proprietes", {}).get("etats", {}).get(nom_canal, {}).get("charge", 0.0))

# UNIQUE ECRIVAIN de `cohesion` ET de son miroir inverse `manque_cohesion` --
# les deux dans le MEME geste, depuis le MEME nombre (patron
# banc_bonheur.gd:poser_bonheur). SOMME PONDEREE RECALCULEE A NEUF, jamais un
# `+=` : c'est ce qui empeche le champ derive de deriver.
# Le choc est le CINQUIEME TERME de la meme somme, de signe oppose -- jamais
# une soustraction posee ailleurs, qui serait un second ecrivain.
# Rend la decomposition pour que l'affichage et la trace relisent sans jamais
# rien recalculer.
static func poser_cohesion(colons: Array, axes: Dictionary, charge_choc: float, config: Dictionary) -> Dictionary:
	var c: Dictionary = config.cohesion
	var capacite: float = float(c.capacite)
	var brute: float = (
		float(c.poids_liens) * float(axes.liens)
		+ float(c.poids_croyance) * float(axes.croyance)
		+ float(c.poids_culture) * float(axes.culture)
		+ float(c.poids_vecu) * float(axes.vecu)
	)
	var malus: float = float(c.poids_choc) * charge_choc
	var cohesion: float = clamp(brute - malus, 0.0, capacite)
	var manque: float = max(0.0, capacite - cohesion)
	var nom_cohesion := String(config.nom_cohesion)
	var nom_manque := String(config.nom_manque_cohesion)
	for colon in colons:
		colon.proprietes[nom_cohesion] = cohesion
		colon.proprietes[nom_manque] = manque
	return {"brute": brute, "malus": malus, "cohesion": cohesion, "manque": manque}

# ---- LIGNE 9 : la densite ----

# La population de CHAQUE case, par Comptage.compter sur une liste que le
# cablage construit lui-meme (filtrage sur la cle plate `case_locale`) --
# comptage.gd n'a aucune notion d'espace. RECOMPTEE A NEUF chaque tick, jamais
# accumulee. Le compte est recopie en cle plate sur la case ET sur les colons
# qui s'y trouvent : la case en a besoin pour son stress, le colon pour son
# affichage.
# Les colons sont remis a 0.0 AVANT le comptage : sans quoi un colon sorti de
# la grille garderait la densite de sa derniere case, indefiniment.
static func poser_densites(cases: Array, colons: Array, comptages: Dictionary, config: Dictionary) -> void:
	var nom_case := String(config.nom_case_locale)
	var nom_densite := String(config.nom_densite_locale)
	var regle := String(config.regle_membres)
	for colon in colons:
		colon.proprietes[nom_densite] = 0.0
	for case in cases:
		var sur_place: Array = []
		for colon in colons:
			if String(colon.proprietes.get(nom_case, "")) == String(case.id):
				sur_place.append(colon)
		var densite: float = float(Comptage.compter(sur_place, regle, comptages))
		case.proprietes[nom_densite] = densite
		for colon in sur_place:
			colon.proprietes[nom_densite] = densite

# Une cause par case EN EXCES, de poids proportionnel a cet exces. A exces nul
# aucune cause n'est construite : la charge redescend d'elle-meme, le gate est
# desactive PAR LA SEULE ARITHMETIQUE (idiome propagation.gd:delai_ignition).
# Case sans `seuil_confort` : repli INF, elle ne stresse JAMAIS -- meme idiome
# qu'« un objet sans point_fusion ne fond jamais ».
static func causes_densite(cases: Array, config: Dictionary) -> Array:
	var nom_densite := String(config.nom_densite_locale)
	var nom_seuil := String(config.nom_seuil_confort)
	var par_point: float = float(config.densite.stress_par_point)
	var causes: Array = []
	for case in cases:
		var densite: float = float(case.proprietes.get(nom_densite, 0.0))
		var confort: float = float(case.proprietes.get(nom_seuil, INF))
		var exces: float = max(0.0, densite - confort)
		if exces <= 0.0:
			continue
		causes.append({"position": case.position, "poids": exces * par_point})
	return causes

# ---- Charges : plafond et miroirs ----

# LE PLAFOND EST DU CABLAGE : rien dans le coeur ne borne le HAUT d'une charge
# (constat (F) de l'audit, deja pose cinq fois dans le depot). Sans lui, une
# cause qui dure ferait monter la charge sans fin et il faudrait aussi
# longtemps pour la redescendre -- une foule calmee resterait en emeute
# plusieurs minutes.
# Un objet VIDE traverse sans rien faire : `avancer` passe [porteur] tel quel,
# et porteur_choc rend {} (deja alarme) quand aucun objet ne porte le canal --
# jamais une deuxieme alarme pour le meme defaut.
static func plafonner_charge(objets: Array, nom_canal: String, plafond: float) -> void:
	for objet in objets:
		var canal: Dictionary = objet.get("proprietes", {}).get("etats", {}).get(nom_canal, {})
		if canal.is_empty():
			continue
		if float(canal.get("charge", 0.0)) > plafond:
			canal["charge"] = plafond

# LE MIROIR 0.0/1.0 DU MARQUEUR DE CHARGE -- voir en-tete, LIGNE 5, et
# data/seuils_etat.json:emeute pour le detail complet. charge.gd ERASE ses cles
# au franchissement descendant, seuil_etat.gd sort sur propriete ABSENTE : sans
# ce miroir, l'etat serait pose a la montee et jamais retire a la descente, en
# silence. La cle miroir, elle, existe TOUJOURS. UNIQUE ECRIVAIN.
static func poser_miroir_charge(objets: Array, nom_marqueur: String, nom_miroir: String) -> void:
	for objet in objets:
		var proprietes: Dictionary = objet.get("proprietes", {})
		if proprietes.is_empty():
			continue
		proprietes[nom_miroir] = 1.0 if proprietes.has(nom_marqueur) else 0.0

# ---- LIGNE 10 : le bruit et le sommeil ----

# LE SEUL ENDROIT DU FICHIER QUI ECRIT DANS UN CANAL DE RESERVE (voir en-tete,
# LIGNE 10). depense.gd calcule reserve - (cout_base + surcout_action) * delta
# et n'a QU'UN emplacement de chaque par canal : deux morceaux de cablage qui y
# ecriraient chacun le leur se detruiraient EN SILENCE, aucun test ne rougirait
# (piege nomme quatre fois dans le depot).
# `cout_base` NEGATIF : la recuperation du sommeil, neutralite de depense.gd
# exploitee, jamais contournee. `surcout_action` : la penalite de bruit, GATEE
# par l'etat que seuil_etat.gd vient de poser -- proportionnelle au bruit reel,
# jamais a l'exces au-dessus du seuil (l'etat ouvre la porte, il ne dose rien).
# Ecriture COMPLETE a chaque tick, jamais un `+=` : un colon rendu au silence
# retombe exactement a 0.0 de surcout, sans residu.
static func poser_couts(colons: Array, config: Dictionary) -> void:
	var nom := String(config.nom_reserve_sommeil)
	var etat_gene := String(config.etat_gene_bruit)
	var nom_bruit_local := String(config.nom_bruit_local)
	var recuperation: float = float(config.sommeil.recuperation_par_s)
	var penalite: float = float(config.sommeil.penalite_par_point_de_bruit)
	for colon in colons:
		var canal: Dictionary = colon.proprietes.get("reserves", {}).get(nom, {})
		if canal.is_empty():
			push_error("banc_social_foule : canal '%s' absent de '%s', couts non poses" % [nom, colon.get("id", "?")])
			continue
		canal["cout_base"] = -recuperation
		var gene: bool = colon.proprietes.get("etats_actifs", []).has(etat_gene)
		var bruit: float = float(colon.proprietes.get(nom_bruit_local, 0.0))
		canal["surcout_action"] = bruit * penalite if gene else 0.0

# ECRETAGE AU PLAFOND -- du CABLAGE, jamais un mecanisme : depense.gd borne le
# BAS (0.0) et RIEN dans le coeur ne borne le HAUT d'une reserve (constat deja
# pose par banc_fertilite.gd). Sans lui, un colon au silence monterait sans fin.
# Le surplus est PERDU, jamais reverse ailleurs.
static func plafonner_sommeil(colons: Array, config: Dictionary) -> void:
	var nom := String(config.nom_reserve_sommeil)
	var capacite: float = float(config.sommeil.capacite)
	for colon in colons:
		var canal: Dictionary = colon.proprietes.get("reserves", {}).get(nom, {})
		if float(canal.get("reserve", 0.0)) > capacite:
			canal["reserve"] = capacite

static func sommeil_de(colon: Dictionary, config: Dictionary) -> float:
	return float(colon.proprietes.get("reserves", {}).get(String(config.nom_reserve_sommeil), {}).get("reserve", 0.0))

# ---- Les quatre gestes ----

# Bascule la cle PLATE, jamais l'etat : `poser_etat_colere` en est l'unique
# reflet, au tick suivant. Rend le nouvel etat.
static func basculer_colere(colon: Dictionary, config: Dictionary) -> bool:
	var cle := String(config.nom_colere)
	if colon.proprietes.has(cle):
		colon.proprietes.erase(cle)
		return false
	colon.proprietes[cle] = true
	return true

# LA MORT DU CHEF EST UN GATE DE CABLAGE, jamais un etat (patron
# banc_ecosysteme_terrain.gd, « LA MORT EST UN GATE DE CABLAGE ») : aucun etat
# `mort` n'est ajoute a un catalogue partage. Le corps RESTE dans le monde --
# il porte le canal de choc, et les axes se mesurent toujours contre ce qu'il
# etait. Ce qui se retire, ce sont les deux cles : il n'est plus chef, il n'est
# plus membre (le denominateur des fractions tombe de 20 a 19).
# Rend l'etat VIVANT apres bascule.
static func basculer_chef(porteur: Dictionary, config: Dictionary) -> bool:
	var cle_chef := String(config.nom_chef)
	var cle_membre := String(config.nom_membre)
	if porteur.proprietes.has(cle_chef):
		porteur.proprietes.erase(cle_chef)
		porteur.proprietes.erase(cle_membre)
		return false
	porteur.proprietes[cle_chef] = true
	porteur.proprietes[cle_membre] = true
	return true

# Deplace chaque colon vers sa position d'entassement ou de depart. Un colon
# dont les deux positions sont identiques (les douze deja denses, et le chef)
# ne bouge jamais -- aucun cas particulier, la meme arithmetique lue sur deux
# nombres egaux.
static func appliquer_entassement(colons: Array, entasse: bool) -> void:
	for colon in colons:
		var p: Dictionary = colon.proprietes
		if entasse:
			colon.position = Vector3(float(p.get("x_entasse", 0.0)), float(p.get("y_entasse", 0.0)), 0.0)
		else:
			colon.position = Vector3(float(p.get("x_depart", 0.0)), float(p.get("y_depart", 0.0)), 0.0)

# Fait tourner le bruit d'une case dans les niveaux declares. Un bruit hors des
# niveaux (le fond sonore par defaut) retombe sur le PREMIER du cycle -- jamais
# une alarme : le fond sonore n'a pas a figurer dans un cycle de clic.
static func bruit_suivant(case: Dictionary, config: Dictionary) -> float:
	var niveaux: Array = config.get("niveaux_bruit", [])
	if niveaux.is_empty():
		push_error("banc_social_foule : 'niveaux_bruit' vide, bruit inchange")
		return float(case.proprietes.get(String(config.nom_bruit), 0.0))
	var courant: float = float(case.proprietes.get(String(config.nom_bruit), 0.0))
	var index := -1
	for i in range(niveaux.size()):
		if is_equal_approx(float(niveaux[i]), courant):
			index = i
			break
	var suivant: float = float(niveaux[(index + 1) % niveaux.size()])
	case.proprietes[String(config.nom_bruit)] = suivant
	return suivant

static func colon_le_plus_proche(colons: Array, position_ecran: Vector2, rayon: float) -> Variant:
	var meilleur: Variant = null
	var meilleure := INF
	for colon in colons:
		var distance: float = Vector2(colon.position.x, colon.position.y).distance_to(position_ecran)
		if distance < meilleure and distance <= rayon:
			meilleure = distance
			meilleur = colon
	return meilleur

static func case_a_la_position(cases: Array, position_ecran: Vector2, portee: float) -> Variant:
	var sonde: Dictionary = {"position": Vector3(position_ecran.x, position_ecran.y, 0.0)}
	return case_sous(sonde, cases, portee)

# ---- Instantanes d'etats (pour les traces) ----

# seuil_etat.gd rend les ids ayant bascule, jamais QUELS etats -- d'ou cette
# comparaison avant/apres cote cablage. Patron
# banc_bonheur.gd:changements_etats.
static func instantane_etats(objets: Array) -> Dictionary:
	var instantane: Dictionary = {}
	for objet in objets:
		instantane[String(objet.id)] = objet.proprietes.get("etats_actifs", []).duplicate()
	return instantane

static func changements_etats(avant: Dictionary, objets: Array) -> Array:
	var changements: Array = []
	for objet in objets:
		var id := String(objet.id)
		var precedents: Array = avant.get(id, [])
		var actuels: Array = objet.proprietes.get("etats_actifs", [])
		for etat in actuels:
			if not precedents.has(etat):
				changements.append({"id": id, "etat": String(etat), "pose": true})
		for etat in precedents:
			if not actuels.has(etat):
				changements.append({"id": id, "etat": String(etat), "pose": false})
	return changements

# ---- LE PAS COMPLET, seul appele par _process ----

# ORDRE FIXE ET ASSUME, aucune permutation innocente :
#   1. case sous chaque colon (id + bruit) -- tout le reste en depend ;
#   2. l'etat de colere reflete la cle plate ;
#   3. la fraction de colere, comptee puis recopiee a plat ;
#   4. la densite par case, comptee puis recopiee a plat ;
#   5. les TROIS charges, sur leurs TROIS familles disjointes, puis les
#      plafonds et les miroirs ;
#   6. les axes, puis la cohesion (elle lit la charge de choc de CE tick) ;
#   7. seuil_etat.gd sur les colons, puis sur les cases ;
#   8. les couts de sommeil (ils lisent `gene_bruit` pose en 7), puis
#      depense.gd, puis le plafond.
# Inverser 4 et 5 ferait stresser sur la densite du tick precedent ; inverser
# 5 et 6 ferait lire a la cohesion un choc vieux d'un tick ; inverser 7 et 8
# ferait payer la penalite de bruit du tick precedent.
# LE SEUL RETARD ASSUME est celui de la cause d'emeute, qui lit le
# `colere_majoritaire` pose au tick precedent (5 vient avant 7) -- consequence
# directe de l'ordre 5-avant-6, et negligeable devant fenetre_s.
# Rend tout ce que le rendu et les traces affichent, jamais recalcule ailleurs.
static func avancer(
	cases: Array,
	colons: Array,
	config: Dictionary,
	comptages: Dictionary,
	catalogue_seuils: Dictionary,
	catalogue_liens: Dictionary,
	delta: float,
) -> Dictionary:
	poser_case_locale(colons, cases, config)
	var changements_colere := poser_etat_colere(colons, config)

	var fraction := fraction_colere(colons, comptages, config)
	poser_fraction_colere(colons, fraction, config)
	poser_densites(cases, colons, comptages, config)

	var porteur := porteur_choc(colons, config)
	var vivant := chef_vivant(colons, config)
	var membres_emeute := porteurs_emeute(colons, config)

	Charge.avancer(cases, causes_densite(cases, config), delta)
	Charge.avancer(membres_emeute, causes_emeute(colons, config), delta)
	if not porteur.is_empty():
		Charge.avancer([porteur], causes_choc(porteur, vivant, config), delta)

	plafonner_charge(cases, String(config.nom_canal_stress), float(config.densite.plafond_charge))
	plafonner_charge(membres_emeute, String(config.nom_canal_emeute), float(config.foule.plafond_charge))
	plafonner_charge([porteur], String(config.nom_canal_choc), float(config.choc.plafond_charge))

	poser_miroir_charge(cases, String(config.nom_marqueur_stress), String(config.nom_miroir_stress))
	poser_miroir_charge(membres_emeute, String(config.nom_marqueur_emeute), String(config.nom_miroir_emeute))

	poser_axes(colons, porteur, config, catalogue_liens)
	var axes := calculer_axes(colons, comptages, config)
	var charge_choc := charge_de(porteur, String(config.nom_canal_choc))
	var cohesion := poser_cohesion(colons, axes, charge_choc, config)

	var avant := instantane_etats(colons + cases)
	SeuilEtat.avancer(colons, catalogue_seuils)
	SeuilEtat.avancer(cases, catalogue_seuils)
	var changements := changements_etats(avant, colons + cases)

	poser_couts(colons, config)
	Depense.avancer(colons, delta, {})
	plafonner_sommeil(colons, config)

	return {
		"fraction_colere": fraction,
		"axes": axes,
		"cohesion": cohesion,
		"charge_choc": charge_choc,
		"chef_vivant": vivant,
		"changements_colere": changements_colere,
		"changements_etats": changements,
	}

# ---- Lectures d'etat (pures) ----

static func porte_etat(objet: Dictionary, nom_etat: String) -> bool:
	return objet.proprietes.get("etats_actifs", []).has(nom_etat)

static func compter_etat(objets: Array, nom_etat: String) -> int:
	var compte := 0
	for objet in objets:
		if porte_etat(objet, nom_etat):
			compte += 1
	return compte

static func densite_maximale(cases: Array, config: Dictionary) -> float:
	var maximum := 0.0
	var nom := String(config.nom_densite_locale)
	for case in cases:
		maximum = max(maximum, float(case.proprietes.get(nom, 0.0)))
	return maximum

# ---- Textes (purs -- aucun nombre n'y est recalcule) ----

static func texte_label_case(case: Dictionary, config: Dictionary) -> String:
	var p: Dictionary = case.proprietes
	return "%s\ndensite %d / %.0f\nbruit %.2f\nstress %.1f / %.0f%s" % [
		String(case.id),
		int(float(p.get(String(config.nom_densite_locale), 0.0))),
		float(p.get(String(config.nom_seuil_confort), 0.0)),
		float(p.get(String(config.nom_bruit), 0.0)),
		charge_de(case, String(config.nom_canal_stress)),
		float(config.densite.seuil),
		"\nSURDENSITE" if porte_etat(case, String(config.etat_surdensite)) else "",
	]

static func texte_compteur(cases: Array, colons: Array, bilan: Dictionary, config: Dictionary, temps: float) -> String:
	var membres := membres_de(colons, config)
	var faches := compter_etat(colons, String(config.etat_colere))
	return ("t=%.1f s | colere %d / %d = %.2f (critique %.2f)%s | cohesion %.3f / %.2f%s | " +
		"densite max %d (confort %.0f) | surdensite %d cases | genes %d | chef %s") % [
			temps,
			faches, membres.size(), float(bilan.fraction_colere), float(config.foule.fraction_critique),
			"  [EMEUTE]" if compter_etat(colons, String(config.etat_emeute)) > 0 else "",
			float(bilan.cohesion.cohesion), float(config.cohesion.capacite),
			"  [DISLOQUE]" if compter_etat(colons, String(config.etat_disloque)) > 0 else "",
			int(densite_maximale(cases, config)), float(config.densite.seuil_confort),
			compter_etat(cases, String(config.etat_surdensite)),
			compter_etat(colons, String(config.etat_gene_bruit)),
			"vivant" if bool(bilan.chef_vivant) else "MORT",
		]

static func texte_aide(config: Dictionary) -> String:
	return ("clic gauche sur un colon : le mettre en colere (il en faut plus de %.0f %% pendant %.1f s pour l'emeute)   |   " +
		"clic droit sur une case : faire tourner son bruit   |   " +
		"les deux boutons : tuer le chef, entasser la foule") % [
			float(config.foule.fraction_critique) * 100.0,
			float(config.foule.fenetre_s),
		]

static func ligne_pose(cases: Array, colons: Array, config: Dictionary, bilan: Dictionary) -> String:
	var axes: Dictionary = bilan.axes
	return ("t=0.0 pose : %d cases, %d colons dont %d membres (1 chef) -- " +
		"cohesion %.3f = liens %.2f x%.2f + croyance %.2f x%.2f + culture %.2f x%.2f + vecu %.2f x%.2f") % [
			cases.size(), colons.size(), int(axes.membres),
			float(bilan.cohesion.cohesion),
			float(axes.liens), float(config.cohesion.poids_liens),
			float(axes.croyance), float(config.cohesion.poids_croyance),
			float(axes.culture), float(config.cohesion.poids_culture),
			float(axes.vecu), float(config.cohesion.poids_vecu),
		]

static func ligne_changement_colere(t: float, changement: Dictionary) -> String:
	return "t=%.1f %s : colere %s" % [t, String(changement.id), "POSEE" if bool(changement.en_colere) else "RETIREE"]

static func ligne_changement_etat(t: float, changement: Dictionary) -> String:
	return "t=%.1f %s : etat '%s' %s" % [t, String(changement.id), String(changement.etat), "POSE" if bool(changement.pose) else "RETIRE"]

static func ligne_toggle_colere(t: float, id: String, fache: bool) -> String:
	return "t=%.1f CLIC : %s %s" % [t, id, "entre en colere" if fache else "revient au calme"]

static func ligne_toggle_chef(t: float, id: String, vivant: bool) -> String:
	return "t=%.1f CHEF : %s %s" % [t, id, "rendu au groupe -- le choc va se resorber" if vivant else "TUE -- le choc monte sur le canal de cohesion"]

static func ligne_toggle_entassement(t: float, entasse: bool) -> String:
	return "t=%.1f FOULE : %s" % [t, "ENTASSEE sur les cases denses" if entasse else "DISPERSEE a ses positions de depart"]

static func ligne_toggle_bruit(t: float, id: String, niveau: float) -> String:
	return "t=%.1f BRUIT : %s passe a %.2f" % [t, id, niveau]

static func ligne_trace(t: float, bilan: Dictionary, config: Dictionary) -> String:
	var axes: Dictionary = bilan.axes
	var cohesion: Dictionary = bilan.cohesion
	return ("t=%.1f fraction=%.3f | cohesion=%.3f (brute %.3f - choc %.3f, charge %.2f) | " +
		"axes liens=%.2f croyance=%.2f culture=%.2f vecu=%.2f | membres=%d") % [
			t, float(bilan.fraction_colere),
			float(cohesion.cohesion), float(cohesion.brute), float(cohesion.malus), float(bilan.charge_choc),
			float(axes.liens), float(axes.croyance), float(axes.culture), float(axes.vecu),
			int(axes.membres),
		]

# ===========================================================================
# Rendu (impur, Node) -- aucune decision, seulement des noeuds, des couleurs
# et des longueurs de barre.
# ===========================================================================

func _creer_rendu() -> void:
	var rendu: Dictionary = _config.rendu

	var fond := ColorRect.new()
	fond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fond.color = _couleur(_config.couleurs.fond)
	fond.position = Vector2(-600.0, -600.0)
	fond.size = Vector2(2400.0, 2000.0)
	add_child(fond)

	for case in _cases:
		_creer_rendu_case(case, rendu)
	for colon in _colons:
		_creer_noeud_colon(colon, rendu)

	var centre_barre := Vector2(10.0, 96.0)
	_barre_fond = _creer_barre(_couleur(_config.couleurs.barre_fond), centre_barre,
		float(rendu.largeur_barre), float(rendu.hauteur_barre), true)
	_barre_cohesion = _creer_barre(_couleur(_config.couleurs.barre_cohesion), centre_barre,
		0.0, float(rendu.hauteur_barre), true)

	_label_compteur = _creer_label_fixe(int(rendu.taille_police_compteur), Vector2(10.0, 10.0))
	_couche_ui.add_child(_label_compteur)
	_label_aide = _creer_label_fixe(int(rendu.taille_police), Vector2(10.0, 38.0))
	_label_aide.text = texte_aide(_config)
	_couche_ui.add_child(_label_aide)

	_creer_bouton("TUER / RENDRE LE CHEF", Vector2(10.0, 62.0), _toggle_chef)
	_creer_bouton("ENTASSER / DISPERSER", Vector2(210.0, 62.0), _toggle_entassement)

func _creer_rendu_case(case: Dictionary, rendu: Dictionary) -> void:
	var taille: float = float(rendu.taille_case)
	var centre := Vector2(case.position.x, case.position.y)

	var noeud := ColorRect.new()
	noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noeud.size = Vector2(taille, taille)
	noeud.position = centre - noeud.size / 2.0
	add_child(noeud)
	_noeuds_cases[case.id] = noeud

	# Le marqueur de bruit : un carre clair dans le coin de la case, visible
	# seulement au-dessus du fond sonore par defaut. Sa TAILLE ne varie pas --
	# c'est le texte de la case qui porte le nombre ; le marqueur ne dit que
	# « ici, on ne dort pas ».
	var marqueur := ColorRect.new()
	marqueur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marqueur.size = Vector2(float(rendu.taille_marqueur_bruit), float(rendu.taille_marqueur_bruit))
	marqueur.position = centre + Vector2(taille / 2.0 - marqueur.size.x - 6.0, -taille / 2.0 + 6.0)
	marqueur.color = Color(1.0, 1.0, 1.0, 0.85)
	add_child(marqueur)
	_marqueurs_bruit[case.id] = marqueur

	var label := _creer_label(int(rendu.taille_police))
	label.position = centre - Vector2(taille / 2.0 - 6.0, taille / 2.0 - 4.0)
	add_child(label)
	_labels_cases[case.id] = label

func _creer_noeud_colon(colon: Dictionary, rendu: Dictionary) -> void:
	var taille: float = float(rendu.taille_colon)
	var noeud := ColorRect.new()
	noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noeud.size = Vector2(taille, taille)
	noeud.position = Vector2(colon.position.x, colon.position.y) - noeud.size / 2.0
	add_child(noeud)
	_noeuds_colons[String(colon.id)] = noeud

func _creer_label(taille: int) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", taille)
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	label.add_theme_constant_override("outline_size", 4)
	return label

func _creer_label_fixe(taille: int, position_ecran: Vector2) -> Label:
	var label := _creer_label(taille)
	label.position = position_ecran
	return label

func _creer_barre(couleur: Color, origine: Vector2, largeur: float, hauteur: float, sur_ui: bool) -> ColorRect:
	var barre := ColorRect.new()
	barre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	barre.color = couleur
	barre.position = origine
	barre.size = Vector2(largeur, hauteur)
	if sur_ui:
		_couche_ui.add_child(barre)
	else:
		add_child(barre)
	return barre

func _creer_bouton(texte: String, position_ecran: Vector2, action: Callable) -> void:
	var bouton := Button.new()
	bouton.text = texte
	bouton.position = position_ecran
	bouton.pressed.connect(action)
	_couche_ui.add_child(bouton)

func _rafraichir_tout() -> void:
	if _dernier.is_empty():
		return
	for case in _cases:
		_noeuds_cases[case.id].color = _couleur_case(case)
		_labels_cases[case.id].text = texte_label_case(case, _config)
		_marqueurs_bruit[case.id].visible = \
			float(case.proprietes.get(String(_config.nom_bruit), 0.0)) > float(_config.bruit_par_defaut)
	for colon in _colons:
		var noeud: ColorRect = _noeuds_colons[String(colon.id)]
		noeud.color = _couleur_colon(colon)
		noeud.position = Vector2(colon.position.x, colon.position.y) - noeud.size / 2.0

	var capacite: float = float(_config.cohesion.capacite)
	var cohesion: float = float(_dernier.cohesion.cohesion)
	var ratio: float = clamp(cohesion / capacite, 0.0, 1.0) if capacite > 0.0 else 0.0
	_barre_cohesion.size.x = float(_config.rendu.largeur_barre) * ratio
	_label_compteur.text = texte_compteur(_cases, _colons, _dernier, _config, _temps)

# COULEUR PAR ETAT, PRIORITE ASSUMEE : plusieurs etats coexistent legitimement
# sur le meme objet, un carre n'a qu'une couleur. Le PLUS GRAVE gagne -- meme
# geste que banc_bonheur.gd:etat_dominant et banc_changement_etat.gd:
# couleur_pour_etats (gaz priorise sur liquide). C'est de l'AFFICHAGE seul :
# aucun mecanisme ne hierarchise jamais les etats entre eux.
func _couleur_case(case: Dictionary) -> Color:
	if porte_etat(case, String(_config.etat_surdensite)):
		return _couleur(_config.couleurs.case_surdensite)
	var charge := charge_de(case, String(_config.nom_canal_stress))
	var seuil: float = float(_config.densite.seuil)
	var ratio: float = clamp(charge / seuil, 0.0, 1.0) if seuil > 0.0 else 0.0
	return _couleur(_config.couleurs.case_aeree).lerp(_couleur(_config.couleurs.case_stressee), ratio)

func _couleur_colon(colon: Dictionary) -> Color:
	if colon.proprietes.get("etats", {}).has(String(_config.nom_canal_choc)):
		var vivant: bool = colon.proprietes.has(String(_config.nom_chef))
		return _couleur(_config.couleurs.colon_chef if vivant else _config.couleurs.colon_chef_mort)
	if porte_etat(colon, String(_config.etat_emeute)):
		return _couleur(_config.couleurs.colon_emeute)
	if porte_etat(colon, String(_config.etat_disloque)):
		return _couleur(_config.couleurs.colon_disloque)
	if porte_etat(colon, String(_config.etat_colere)):
		return _couleur(_config.couleurs.colon_colere)
	return _couleur(_config.couleurs.colon_calme)

func _couleur(rgb: Array) -> Color:
	return Color(float(rgb[0]), float(rgb[1]), float(rgb[2]))

func _poser_camera() -> void:
	var decl: Dictionary = _config.get("camera", {})
	var pos: Array = decl.get("position", [0.0, 0.0])
	var camera := Camera2D.new()
	camera.position = Vector2(float(pos[0]), float(pos[1]))
	camera.zoom = Vector2(float(decl.get("zoom", 1.0)), float(decl.get("zoom", 1.0)))
	camera.enabled = true
	add_child(camera)

func _charger(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
