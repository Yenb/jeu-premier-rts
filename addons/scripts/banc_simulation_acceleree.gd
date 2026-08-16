extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_simulation_acceleree.tscn, PAS la
# scene principale -- run/main_scene reste banc_p1). Chantier "simulation
# acceleree -- le monde existait avant toi", audit prealable
# audit_terrain_et_monde_prealable.md (ligne 1, PARTIELLEMENT COUVERT :
# "aucun .gd du coeur n'est necessaire si le pilote reste un banc et si la
# vitesse passe par un facteur d'echelle avec un delta petit").
#
# CE QUE CE FICHIER EST : un PILOTE DE BOUCLE, du cablage, jamais un
# mecanisme. Il n'invente aucune loi -- il appelle QUATRE mecanismes du coeur
# deja fermes, TOUS INCHANGES, dans un ordre fixe :
#   senescence.gd:avancer(case, delta, annees_par_seconde)  -- l'horloge
#   stade.gd:avancer(case)                                  -- la succession
#   ecoulement.gd:avancer(cases, ...)                       -- l'eau
#   depense.gd:avancer(cases, delta, {})                    -- absorption+evaporation
#
# LE PATRON, ET LA RAISON DE CE BANC : accelerer le temps se fait par un
# FACTEUR D'ECHELLE (annees_par_seconde ELEVE) avec un delta PETIT et FIXE
# (delta_fixe, 0.016 s), repete iterations_par_tick fois par tick reel --
# JAMAIS par un grand delta. Les deux voies donnent le meme age simule, elles
# ne donnent pas le meme monde :
# - un grand delta fait DIVERGER temperature.gd (Euler explicite : des que
#   (conductivite/chaleur_specifique)*delta > 2.0, l'objet depasse sa cible en
#   oscillant d'amplitude croissante), rend ecoulement.gd NON PHYSIQUE (une
#   case se vide integralement vers son premier voisin plus bas dans l'ordre
#   d'iteration -- son propre en-tete l'assume : "accepte par calibration,
#   delta petit, taux module") et CASSE LA CONSERVATION dans consommer.gd
#   (credite la quantite DEMANDEE, pas la quantite retiree) ;
# - un delta petit repete N fois ne touche aucun de ces trois defauts : chaque
#   pas reste dans le regime ou les mecanismes ont ete calibres et testes.
# Le facteur d'echelle est DOCTRINAL, pas une invention de ce banc :
# senescence.gd le recoit deja en parametre ("c'est au CABLAGE de choisir a
# quelle vitesse le temps du jeu vieillit ses entites, pas a ce mecanisme de
# le deviner"). Voir docs/design.md, "Simulation acceleree : delta petit et
# facteur d'echelle, jamais un grand delta".
#
# DEUX HORLOGES DECOUPLEES, CONSEQUENCE A NOMMER (elle n'est pas un defaut de
# ce banc, c'est la DEFINITION du facteur d'echelle) : senescence.gd est le
# SEUL mecanisme du depot dont l'unite de sortie est l'ANNEE ; ecoulement.gd
# et depense.gd travaillent en SECONDES DE SIMULATION, comme tout le reste.
# annees_par_seconde relie les deux -- l'augmenter fait vieillir le vivant
# vite SANS accelerer la physique d'un iota. A la calibration livree, un tick
# accelere avance de 120 annees de succession mais de 0.4 seconde d'hydrologie
# seulement. C'est voulu : une foret pousse en millenaires, une flaque
# s'ecoule en secondes, et les acceler d'un MEME facteur donnerait un monde ou
# l'eau aurait traverse la vallee un million de fois avant le premier arbre.
# Ne jamais lire "33 000 annees simulees" comme "33 000 annees de pluie" : ce
# sont 33 000 annees de vieillissement, et quelques minutes d'ecoulement.
#
# COUT MESURE, PAS SUPPOSE (headless, machine de developpement, grille 8x8) :
# Ecoulement.avancer est en O(cases^2) par iteration -- 64 cases donnent 4096
# comparaisons de paires par iteration, soit ~102 000 par tick a
# iterations_par_tick=25. Debit constate : ~9 ticks/s, ~1740 annees simulees
# par seconde reelle, le dernier stade (3000 ans) atteint vers 2 s. C'est ce
# qui a fixe iterations_par_tick a 25 plutot qu'a 100 : le debit en annees ne
# depend PAS de iterations_par_tick (doubler N divise le nombre de ticks par
# deux, le produit est constant), seulement de annees_par_seconde -- N ne
# regle que la FINESSE du pas physique et la fluidite du rendu. Ce nombre est
# une MESURE sur une machine, jamais une garantie : aucun test ne l'assert
# (voir test_banc_simulation_acceleree.gd, qui verifie la calibration en
# ANNEES PAR TICK, grandeur qui, elle, ne depend d'aucune machine).
#
# TEMPERATURE VOLONTAIREMENT ABSENTE, PAR CHOIX DOCTRINAL : aucune case ne
# porte proprietes.temperature et temperature.gd n'est JAMAIS appele ici. Ce
# n'est pas un oubli -- c'est le seul des mecanismes du depot qui diverge
# numeriquement a grand delta, et le rendre inoffensif demanderait de le
# sous-echantillonner EN INTERNE, donc de toucher un mecanisme du coeur (hors
# perimetre de ce chantier, a trancher par Yael avant d'ecrire). Verrouille
# POSITIVEMENT par test : test_banc_simulation_acceleree.gd verifie qu'aucune
# case ne porte "temperature", donc que la divergence est impossible PAR
# CONSTRUCTION, jamais par prudence d'appelant.
#
# DEUX MODES, bascule au clic gauche (etat _mode_accelere, meme geste
# bistable que banc_fracture_sonore.gd/banc_restitution.gd) :
# - ACCELERE (mode de depart -- "le monde existait avant toi") :
#   iterations_par_tick appels par tick reel, delta_fixe, annees_par_seconde
#   eleve. Aucun rendu entre les iterations : _process rafraichit UNE FOIS,
#   apres le bloc entier.
# - TEMPS REEL : UN SEUL appel par tick, avec le delta reel du moteur et
#   annees_par_seconde_temps_reel (lent). Le joueur observe. Rien d'autre ne
#   change : c'est LE MEME code (avancer_bloc avec iterations=1), jamais une
#   deuxieme branche de simulation.
#
# CE QU'ON DOIT VOIR : une grille 8x8 en pente (sommet a gauche, bas de pente
# a droite), moitie gauche en terre (permeable), moitie droite en roche
# (impermeable). En mode accelere, le compteur d'annees grimpe de milliers
# d'annees en quelques secondes : chaque case traverse nu -> prairie ->
# taillis -> foret (couleur du stade, lue en donnee) pendant que l'eau posee
# au sommet coule de case en case vers le bas de la pente, s'y accumule et se
# stabilise, et que le sol l'absorbe lentement (eau totale qui descend).
# Un clic bascule en temps reel : le joueur arrive alors sur un monde qui a
# deja une histoire.
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready construit la grille et le rendu ; _unhandled_input
#   bascule le mode ; _process appelle avancer_bloc (fonction PURE ci-dessous)
#   et lit son resultat pour l'affichage et la console.
# - Fonctions statiques (pures, testables headless -- voir
#   test_banc_simulation_acceleree.gd) : construire_grille /
#   type_sol_pour_colonne / altitude_pour_colonne / cout_base_absorption /
#   avancer_iteration / avancer_bloc / annees_simulees / compter_stades /
#   somme_colonne / couleur_pour_case / case_la_plus_proche,
#   plus les textes d'affichage et de trace.
#
# RECOPIE ASSUMEE de scripts/banc_ecoulement.gd (construire_grille /
# type_sol_pour_colonne / altitude_pour_colonne / cout_base_absorption /
# case_la_plus_proche) : deux bancs jetables ne se
# referencent JAMAIS entre eux (meme discipline que banc_mana_conduction.gd
# recopiant banc_conduction.gd, banc_solubilite.gd recopiant
# banc_humidite.gd). banc_ecoulement.gd reste inchange.
#
# stades_config EST COPIEE PAR VALEUR sur chaque case, jamais referencee dans
# un catalogue partage : c'est le CONTRAT de stade.gd ("NE RECOIT AUCUN
# CATALOGUE -- la table des stades vit DEJA sur l'entite"), pas un choix de ce
# banc. Consequence connue pour la resumabilite (docs/design.md, "Deux
# regimes de simulation") ; duplicate(true) a la construction pour qu'aucune
# case ne partage l'Array du fichier de config.
#
# AUCUN NOM DE STADE EN DUR ICI : "nu"/"prairie"/"taillis"/"foret" ne vivent
# que dans data/banc_simulation_acceleree.json (stades_config pour la logique,
# couleurs_stade pour l'affichage). Le code ne fait que lire des cles.
#
# RAPPORT A scripts/banc_succession.gd (banc voisin, livre par une session
# CONCURRENTE pendant ce chantier -- il n'existait pas au debut de celui-ci) :
# meme mecanique (senescence.gd + stade.gd), MEME PALETTE (couleurs_stade est
# recopiee a l'identique de data/banc_succession.json, meme nom de cle et
# memes quatre couleurs) mais DEUX ECHELLES OPPOSEES, delibererement : la-bas
# une succession lisible EN DIRECT (annees_par_seconde=8.0, foret a ~7.5 s,
# c'est un banc d'OBSERVATION du mecanisme), ici une succession MILLENAIRE
# repliee dans quelques secondes (foret vers 3000 ans, atteinte en ~2 s, c'est
# un banc de DEMONSTRATION du patron d'acceleration). Aucun des deux ne
# reference l'autre : deux bancs jetables ne se referencent JAMAIS entre eux
# (meme discipline que banc_mana_conduction.gd recopiant banc_conduction.gd).

const Senescence = preload("res://scripts/senescence.gd")
const Stade = preload("res://scripts/stade.gd")
const Ecoulement = preload("res://scripts/ecoulement.gd")
const Depense = preload("res://scripts/depense.gd")
const Somme = preload("res://scripts/somme.gd")

const TAILLE_CASE := 60.0
const MARGE_CASE := 4.0
const HAUTEUR_BARRE := 8.0

var _config: Dictionary = {}
var _materiaux: Dictionary = {}
var _cases: Array = []
var _noeuds: Dictionary = {}
var _barres_fond: Dictionary = {}
var _barres_remplies: Dictionary = {}
var _label_entete: Label
var _label_compteur: Label
var _label_detail: Label
var _mode_accelere: bool = true
var _prochaine_trace_annees: float = 0.0

func _ready() -> void:
	_config = _charger_json("res://data/banc_simulation_acceleree.json")
	_materiaux = _charger_json("res://data/materiaux.json")

	_cases = construire_grille(_config, _materiaux)
	for case in _cases:
		_creer_rendu_case(case)

	# Un pas NEUTRE (delta 0.0) : senescence n'ajoute rien, ecoulement ne
	# transfere rien (quantite bornee a 0), depense ne decremente rien -- seul
	# stade.gd ecrit, en posant le premier stade que l'age 0.0 autorise. La
	# grille est donc affichable avant tout tick, sans qu'aucun stade de
	# depart ne soit ecrit A LA MAIN par ce banc (le mecanisme le pose).
	avancer_bloc(_cases, _config, 0.0, 0.0, 1)

	var couche_ui := CanvasLayer.new()
	add_child(couche_ui)
	_label_entete = Label.new()
	_label_entete.position = Vector2(10.0, 10.0)
	couche_ui.add_child(_label_entete)
	_label_compteur = Label.new()
	_label_compteur.position = Vector2(10.0, 34.0)
	couche_ui.add_child(_label_compteur)
	_label_detail = Label.new()
	_label_detail.position = Vector2(10.0, 58.0)
	couche_ui.add_child(_label_detail)

	_poser_camera()
	_rafraichir_tout()
	print(ligne_pose_initiale(_cases, _config))
	print(ligne_mode(_cases, _config, _mode_accelere))

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	_mode_accelere = not _mode_accelere
	print(ligne_mode(_cases, _config, _mode_accelere))
	_rafraichir_tout()

func _process(delta: float) -> void:
	var iterations: int = int(_config.iterations_par_tick) if _mode_accelere else 1
	var pas: float = float(_config.delta_fixe) if _mode_accelere else delta
	var annees_par_seconde: float = float(_config.annees_par_seconde) if _mode_accelere else float(_config.annees_par_seconde_temps_reel)

	var bilan: Dictionary = avancer_bloc(_cases, _config, pas, annees_par_seconde, iterations)

	_rafraichir_tout()

	var annees: float = annees_simulees(_cases)
	if annees >= _prochaine_trace_annees:
		var intervalle: float = float(_config.intervalle_trace_annees)
		_prochaine_trace_annees = (floor(annees / intervalle) + 1.0) * intervalle
		print(ligne_trace(_cases, _config, _mode_accelere, bilan))

func _rafraichir_tout() -> void:
	_label_entete.text = texte_entete(_cases, _config, _mode_accelere)
	_label_compteur.text = texte_compteur(_cases, _config)

	var nom_reserve: String = _config.nom_reserve
	var reference: float = float(_config.eau_initiale)
	for case in _cases:
		var id: String = case.id
		var niveau: float = float(case.proprietes.reserves[nom_reserve].reserve)
		_noeuds[id].color = couleur_pour_case(case.proprietes.get("stade", ""), niveau, reference, _config)
		var ratio: float = clamp(niveau / reference, 0.0, 1.0) if reference > 0.0 else 0.0
		_barres_remplies[id].size.y = _barres_fond[id].size.y * ratio
		_barres_remplies[id].position.y = _barres_fond[id].position.y + _barres_fond[id].size.y * (1.0 - ratio)

	var case_survolee: Variant = case_la_plus_proche(_cases, get_global_mouse_position(), TAILLE_CASE)
	_label_detail.text = texte_detail(case_survolee, _config)

# ---- Fonctions PURES, testables headless (test_banc_simulation_acceleree.gd) ----

# Construit la grille grille_lignes x grille_colonnes, ordre ligne-majeur
# (index = ligne*grille_colonnes + colonne). position.x=colonne,
# position.y=ligne, position.z=0.0 TOUJOURS (fait spatial pur -- l'altitude
# vit dans proprietes[nom_altitude], voir en-tete).
#
# Chaque case porte, en plus du terrain de banc_ecoulement.gd (altitude /
# permeabilite / type_sol / reserves.<nom_reserve>), les DEUX proprietes
# STRUCTURELLES exigees par senescence.gd et stade.gd : "age" (float, en
# ANNEES -- leur unite de contrat) et "stades_config" (Array ordonne de
# { nom, age_seuil }). "stade" part de la chaine vide : stade.gd la remplira
# au premier appel (_index_du_stade rend -1 sur une chaine vide, donc le
# premier stade autorise par l'age est strictement plus avance).
static func construire_grille(config: Dictionary, materiaux: Dictionary) -> Array:
	var lignes: int = int(config.grille_lignes)
	var colonnes: int = int(config.grille_colonnes)
	var nom_reserve: String = config.nom_reserve
	var nom_altitude: String = config.nom_altitude
	var cases: Array = []
	for ligne in range(lignes):
		for colonne in range(colonnes):
			var type_sol := type_sol_pour_colonne(colonne, colonnes, config)
			var permeabilite: float = float(materiaux.get(type_sol, {}).get("permeabilite", 0.0))
			var altitude := altitude_pour_colonne(colonne, colonnes, float(config.altitude_max), float(config.altitude_min))
			var eau_initiale: float = float(config.eau_initiale) if colonne == 0 else 0.0
			cases.append({
				"id": "case_%d_%d" % [colonne, ligne],
				"position": Vector3(float(colonne), float(ligne), 0.0),
				"proprietes": {
					nom_altitude: altitude,
					"permeabilite": permeabilite,
					"type_sol": type_sol,
					"age": 0.0,
					"stades_config": config.stades_config.duplicate(true),
					"stade": "",
					"reserves": {
						nom_reserve: {
							"reserve": eau_initiale,
							"cout_base": cout_base_absorption(permeabilite, config),
							"surcout_action": float(config.evaporation_par_s),
							"seuils_ref": "",
						},
					},
				},
			})
	return cases

# Moitie gauche des colonnes (colonne < colonnes/2) : materiau_gauche
# (permeable) ; moitie droite : materiau_droite (impermeable).
static func type_sol_pour_colonne(colonne: int, colonnes: int, config: Dictionary) -> String:
	return config.materiau_gauche if colonne < colonnes / 2 else config.materiau_droite

# Interpolation lineaire, colonne 0 = altitude_max (sommet, gauche), derniere
# colonne = altitude_min (bas de pente, droite). colonnes<=1 : rend
# altitude_max, chemin degenere jamais atteint par la config reelle mais garde
# defensive contre une division par zero.
static func altitude_pour_colonne(colonne: int, colonnes: int, altitude_max: float, altitude_min: float) -> float:
	if colonnes <= 1:
		return altitude_max
	var ratio: float = float(colonne) / float(colonnes - 1)
	return lerp(altitude_max, altitude_min, ratio)

# cout_base = taux_decroissance_plancher + facteur_permeabilite*permeabilite
# -- MEME FORMULE que scripts/banc_permeabilite.gd:
# taux_decroissance_permeabilite, ecrite ici comme cout_base du canal de
# reserve (scripts/depense.gd), jamais comme un taux_decroissance de charge.gd
# (ce banc n'utilise pas charge.gd).
static func cout_base_absorption(permeabilite: float, config: Dictionary) -> float:
	var plancher: float = float(config.get("taux_decroissance_plancher", 0.0))
	var facteur: float = float(config.get("facteur_permeabilite", 0.0))
	return plancher + facteur * permeabilite

# UN pas de simulation : les QUATRE mecanismes du coeur, dans l'ordre, une
# seule fois chacun, avec le MEME delta. senescence.gd et stade.gd travaillent
# entite par entite (ils ne prennent pas d'Array, par contrat), ecoulement.gd
# et depense.gd prennent la liste entiere.
#
# Rend { transferts: int, quantite: float } -- le compte et la somme des
# transferts d'eau de CE pas, lus depuis le retour d'Ecoulement.avancer
# (jamais recalcules).
static func avancer_iteration(cases: Array, config: Dictionary, delta: float, annees_par_seconde: float) -> Dictionary:
	for case in cases:
		Senescence.avancer(case, delta, annees_par_seconde)
		Stade.avancer(case)
	var transferts: Array = Ecoulement.avancer(
		cases,
		float(config.rayon_voisinage),
		config.nom_reserve,
		config.nom_altitude,
		float(config.taux_ecoulement),
		delta
	)
	Depense.avancer(cases, delta, {})
	var quantite := 0.0
	for t in transferts:
		quantite += float(t.quantite)
	return {"transferts": transferts.size(), "quantite": quantite}

# N pas de simulation d'affilee, SANS AUCUN RENDU entre eux -- c'est TOUTE la
# difference entre le mode accelere (iterations = iterations_par_tick, delta =
# delta_fixe, annees_par_seconde eleve) et le mode temps reel (iterations = 1,
# delta = le delta reel du moteur, annees_par_seconde lent). UN SEUL chemin de
# code pour les deux modes, jamais deux branches de simulation.
#
# Rend { transferts, quantite, annees } -- annees = iterations*delta*
# annees_par_seconde, l'avance d'age de CE bloc (calcul de trace ; l'age
# reellement porte par les cases est toujours ecrit par senescence.gd, jamais
# par ce compte).
static func avancer_bloc(cases: Array, config: Dictionary, delta: float, annees_par_seconde: float, iterations: int) -> Dictionary:
	var transferts := 0
	var quantite := 0.0
	for _i in range(iterations):
		var bilan := avancer_iteration(cases, config, delta, annees_par_seconde)
		transferts += int(bilan.transferts)
		quantite += float(bilan.quantite)
	return {
		"transferts": transferts,
		"quantite": quantite,
		"annees": float(iterations) * delta * annees_par_seconde,
	}

# Les annees simulees SONT l'age porte par le terrain lui-meme (ecrit par
# senescence.gd), jamais un accumulateur parallele du banc -- une seule source
# de verite. Rend le MAXIMUM des ages (toutes les cases avancent du meme pas
# ici ; le max reste juste si un futur cablage remettait une case a zero).
static func annees_simulees(cases: Array) -> float:
	var maximum := 0.0
	for case in cases:
		maximum = max(maximum, float(case.proprietes.get("age", 0.0)))
	return maximum

# Rend { nom_de_stade: compte }, dans l'ordre de stades_config quand elle est
# fournie (pour un affichage stable), suivi de tout stade inattendu rencontre.
static func compter_stades(cases: Array, config: Dictionary) -> Dictionary:
	var comptes: Dictionary = {}
	for entree in config.get("stades_config", []):
		comptes[entree.get("nom", "")] = 0
	for case in cases:
		var stade: String = case.proprietes.get("stade", "")
		comptes[stade] = int(comptes.get(stade, 0)) + 1
	return comptes

# Somme de la reserve sur la seule colonne demandee (position.x) -- sert a
# montrer que l'eau descend la pente plutot que de rester au sommet.
static func somme_colonne(cases: Array, colonne: int, nom_reserve: String) -> float:
	var total := 0.0
	for case in cases:
		if int(case.position.x) != colonne:
			continue
		total += float(case.proprietes.get("reserves", {}).get(nom_reserve, {}).get("reserve", 0.0))
	return total

# Couleur d'une case : la couleur SECHE est celle de son STADE (lue dans
# config.couleurs_stade -- aucun nom de stade en dur ici ; un stade absent de
# la table retombe sur couleur_stade_inconnu, jamais une alarme), interpolee
# vers couleur_eau au ratio niveau/reference borne [0,1]. reference<=0.0 :
# rend systematiquement la couleur seche, jamais une division par zero.
static func couleur_pour_case(stade: String, niveau: float, reference: float, config: Dictionary) -> Color:
	var table: Dictionary = config.get("couleurs_stade", {})
	var sec := _couleur_depuis_liste(table.get(stade, config.get("couleur_stade_inconnu", [0.5, 0.5, 0.5])))
	var eau := _couleur_depuis_liste(config.get("couleur_eau", [0.0, 0.0, 1.0]))
	var ratio: float = clamp(niveau / reference, 0.0, 1.0) if reference > 0.0 else 0.0
	return sec.lerp(eau, ratio)

static func _couleur_depuis_liste(composantes) -> Color:
	if typeof(composantes) != TYPE_ARRAY or composantes.size() < 3:
		return Color(0.5, 0.5, 0.5)
	return Color(float(composantes[0]), float(composantes[1]), float(composantes[2]))

# Retrouve la case dont la position de GRILLE (convertie en pixels par
# taille_case) est la plus proche de "position_ecran". Rend null si "cases"
# est vide (chemin mort, jamais atteint en jeu reel).
static func case_la_plus_proche(cases: Array, position_ecran: Vector2, taille_case: float) -> Variant:
	if cases.is_empty():
		return null
	var meilleure: Variant = null
	var meilleure_distance := INF
	for case in cases:
		var pos: Vector3 = case.position
		var distance: float = (Vector2(pos.x, pos.y) * taille_case).distance_to(position_ecran)
		if distance < meilleure_distance:
			meilleure_distance = distance
			meilleure = case
	return meilleure

static func nom_mode(mode_accelere: bool) -> String:
	return "ACCELERE" if mode_accelere else "TEMPS REEL"

# Label du haut : annees simulees, mode courant, iterations_par_tick et le
# facteur d'echelle REELLEMENT en vigueur dans ce mode.
static func texte_entete(cases: Array, config: Dictionary, mode_accelere: bool) -> String:
	var iterations: int = int(config.iterations_par_tick) if mode_accelere else 1
	var aps: float = float(config.annees_par_seconde) if mode_accelere else float(config.annees_par_seconde_temps_reel)
	var pas: float = float(config.delta_fixe) if mode_accelere else -1.0
	var texte_pas: String = "delta_fixe=%.3f" % pas if mode_accelere else "delta=moteur"
	return "annees simulees : %.0f | mode : %s (clic pour basculer) | iterations_par_tick=%d %s annees_par_seconde=%.2f" % [
		annees_simulees(cases), nom_mode(mode_accelere), iterations, texte_pas, aps
	]

# Compteur : combien de cases par stade, et l'eau totale du systeme.
static func texte_compteur(cases: Array, config: Dictionary) -> String:
	var comptes := compter_stades(cases, config)
	var morceaux: Array = []
	for nom in comptes:
		morceaux.append("%s=%d" % [nom, comptes[nom]])
	return "stades : %s | eau totale : %.2f" % [" ".join(morceaux), Somme.reserves(cases, config.nom_reserve)]

static func texte_detail(case: Variant, config: Dictionary) -> String:
	if case == null:
		return ""
	var p: Dictionary = case.proprietes
	var niveau: float = float(p.get("reserves", {}).get(config.nom_reserve, {}).get("reserve", 0.0))
	return "%s : stade=%s age=%.0f altitude=%.2f niveau_eau=%.2f permeabilite=%.2f type_sol=%s" % [
		case.id, p.get("stade", "?"), p.get("age", 0.0), p.get(config.nom_altitude, 0.0),
		niveau, p.get("permeabilite", 0.0), p.get("type_sol", "?")
	]

static func ligne_pose_initiale(cases: Array, config: Dictionary) -> String:
	return "annees=0 grille posee : %d cases, eau totale=%.2f, %s" % [
		cases.size(), Somme.reserves(cases, config.nom_reserve), texte_compteur(cases, config)
	]

static func ligne_mode(cases: Array, config: Dictionary, mode_accelere: bool) -> String:
	return "MODE -> %s a annees=%.0f (%s)" % [
		nom_mode(mode_accelere), annees_simulees(cases), texte_compteur(cases, config)
	]

static func ligne_trace(cases: Array, config: Dictionary, mode_accelere: bool, bilan: Dictionary) -> String:
	return "annees=%.0f mode=%s transferts=%d eau_deplacee=%.2f | %s" % [
		annees_simulees(cases), nom_mode(mode_accelere), int(bilan.get("transferts", 0)),
		float(bilan.get("quantite", 0.0)), texte_compteur(cases, config)
	]

# ---- Rendu (impur, Node) -- aucune decision, seulement la construction des
# noeuds et la camera.

func _creer_rendu_case(case: Dictionary) -> void:
	var id: String = case.id
	var pos: Vector3 = case.position
	var centre := Vector2(pos.x, pos.y) * TAILLE_CASE
	var taille_visible := TAILLE_CASE - MARGE_CASE

	var noeud := ColorRect.new()
	noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noeud.size = Vector2(taille_visible, taille_visible)
	noeud.position = centre - noeud.size / 2.0
	add_child(noeud)
	_noeuds[id] = noeud

	var fond := ColorRect.new()
	fond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fond.color = Color(0.15, 0.15, 0.15)
	fond.size = Vector2(HAUTEUR_BARRE, taille_visible)
	fond.position = centre + Vector2(taille_visible / 2.0 + 3.0, -taille_visible / 2.0)
	add_child(fond)
	_barres_fond[id] = fond

	var rempli := ColorRect.new()
	rempli.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rempli.color = Color(0.2, 0.55, 0.9)
	rempli.size = Vector2(HAUTEUR_BARRE, 0.0)
	rempli.position = fond.position + Vector2(0.0, fond.size.y)
	add_child(rempli)
	_barres_remplies[id] = rempli

func _poser_camera() -> void:
	var lignes: int = int(_config.grille_lignes)
	var colonnes: int = int(_config.grille_colonnes)
	var centre := Vector2(float(colonnes - 1), float(lignes - 1)) * TAILLE_CASE / 2.0
	var camera := Camera2D.new()
	camera.position = centre
	camera.zoom = Vector2(0.9, 0.9)
	camera.enabled = true
	add_child(camera)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
