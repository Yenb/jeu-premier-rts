extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_fatigue_circadien.tscn, PAS la
# scene principale -- run/main_scene reste banc_p1, coexiste avec les autres
# bancs). Chantier « fatigue + circadien + blesse != repos »
# (audit_mecaniques_corps_prealable.md, lignes 4/5/6 -- toutes trois au
# verdict CABLABLE, tenu). Compose SIX mecanismes deja fermes, TOUS
# INCHANGES : scripts/depense.gd, scripts/velocite.gd, scripts/seuil_etat.gd,
# scripts/conditions.gd, scripts/charge.gd, scripts/etat_duree.gd (+
# scripts/etat_effectif.gd en lecture pure). AUCUN MECANISME DU COEUR TOUCHE,
# aucun .gd neuf du coeur.
#
# COLONS CONSTRUITS A LA MAIN (pas Objet.fabriquer, meme statut que
# banc_maladie.gd/banc_toxicite.gd/banc_ecoulement.gd -- un colon de banc n'a
# pas de composition ici, aucun materiau n'intervient). Positions en PIXELS
# (patron banc_lumiere.gd), z=0.0 TOUJOURS -- VERTICALITE.
#
# ---------------------------------------------------------------------------
# CE QU'IL DOIT MONTRER
# ---------------------------------------------------------------------------
# 1. LA FATIGUE EST UNE RESERVE. `reserves.sommeil` descend par depense.gd,
#    d'un cout_base constant (le metabolisme de la veille) PLUS un surcout
#    proportionnel au mouvement reel (coef_effort * velocite.length(), la
#    velocite etant DERIVEE par velocite.gd, jamais ecrite a la main).
# 2. LE SOMMEIL LA FAIT REMONTER, SANS UNE LIGNE DE MECANISME NEUF. Quand un
#    colon dort, ce cablage pose un cout_base NEGATIF sur le meme canal :
#    depense.gd calcule `reserve - (cout_base + surcout) * delta`, un cout
#    negatif REMONTE donc la reserve. Neutralite du mecanisme EXPLOITEE,
#    jamais contournee -- patron exact de la jachere de banc_fertilite.gd.
#    Un colon qui dort ne bouge plus (son horloge de patrouille s'arrete).
# 3. UN CYCLE CIRCADIEN impose une ZONE DE SOMMEIL (16 h -> 8 h) qui ENJAMBE
#    MINUIT. Ce n'est donc PAS un seuil (seuil_etat.gd ne compare qu'une
#    propriete a un seuil, dans un seul sens) mais « heure >= 16 OU heure
#    <= 8 » : deux entrees d'un catalogue de conditions.gd posant TOUTES DEUX
#    la meme cle `doit_dormir`, avec retirer_si_faux=true. C'est EXACTEMENT le
#    cas que les DEUX PASSES DISJOINTES de conditions.gd ferment -- une entree
#    VRAIE gagne toujours sur une entree FAUSSE, quel que soit l'ordre ; en une
#    seule passe, l'entree « <= 8 » fausse a 20 h effacerait le `doit_dormir`
#    que l'entree « >= 16 » vient de poser.
# 4. VEILLER EN ZONE DE SOMMEIL ACCUMULE UNE DETTE. charge.gd, canal
#    `etats.dette_sommeil`, dont la CAUSE est SYNTHETISEE par ce cablage (le
#    colon lui-meme, quand `doit_dormir` est vrai ET qu'il ne dort pas).
#    Elle REDESCEND toute seule (taux_decroissance) des que la cause cesse --
#    charge.gd est le SEUL mecanisme du depot a monter, basculer, puis
#    redescendre seul. Au franchissement il pose un MARQUEUR sur proprietes
#    (jamais dans etats_actifs) ; ce cablage relaie le marqueur vers
#    EtatDuree.poser("endette_sommeil"), repose chaque tick tant qu'il dure --
#    idiome litteral de `nausee_radiation` (banc_produit_nucleaire.gd).
# 5. BLESSE != REPOS. `reserves.sante` et `reserves.sommeil` sont deux canaux
#    du MEME Dictionary `reserves`, avances independamment par la boucle
#    `for nom in reserves` de depense.gd. Le gate de blessure n'ecrit QUE
#    dans le canal `sante` : la fatigue est intouchee PAR CONSTRUCTION, pas
#    par precaution. Le colon blesse recupere sa sante et continue de fatiguer.
#
# ---------------------------------------------------------------------------
# DEUX POINTS OU CE CABLAGE FAIT LE TRAVAIL QUE LE COEUR NE FAIT PAS
# ---------------------------------------------------------------------------
# (a) MIROIR PLAT INVERSE. seuil_etat.gd ne lit que des cles PLATES (une
#     reserve vit a proprietes.reserves.<nom>.reserve -- inatteignable, aucun
#     parcours de chemin en points) et ne compare que VERS LE HAUT. « la
#     fatigue tombe sous un seuil » s'ecrit donc « manque_sommeil monte
#     au-dessus d'un seuil » : ce cablage ecrit `manque_sommeil = capacite -
#     reserve` a chaque tick, seuil_etat.gd le compare (data/seuils_etat.json:
#     epuisement) et pose/retire `epuise`. Precedent exact et documente :
#     `dose_radiation_objet` (banc_activation_neutronique.gd). DIFFERENCE
#     REELLE avec toutes les grandeurs de ce genre deja au depot : le miroir
#     REDESCEND ici, donc l'etat se retire vraiment de lui-meme quand le colon
#     dort -- premiere reversibilite REELLE d'une entree de seuils_etat.json.
# (b) LE PLAFOND EST DU CABLAGE. depense.gd borne le BAS (0.0) et RIEN dans le
#     coeur ne borne le HAUT d'une reserve -- constat deja pose par
#     banc_fertilite.gd. `capacite_sommeil`/`capacite_sante` sont donc posees
#     en donnee mais ecretees ici (plafonner_reserves), apres le pas de
#     depense.
#
# UN SEUL ECRIVAIN PAR `surcout_action` (piege nomme par
# audit_mecaniques_corps_prealable.md, constat (D) : un canal n'a QU'UN
# emplacement de surcout, trois morceaux de cablage qui y ecrivent chacun le
# leur se detruisent en silence). Ici `poser_couts` est le SEUL endroit du
# fichier qui ecrit dans un canal, et il ecrit les deux canaux d'un coup :
# aucun autre surcout ne peut se glisser sans passer par cette fonction.
#
# HORLOGE DU JOUR RECOPIEE, JAMAIS REFERENCEE : `heure_courante` est le meme
# accumulateur de secondes + fmod que banc_lumiere.gd, RECOPIE ici (deux bancs
# jetables ne se referencent jamais entre eux -- precedent explicite
# banc_erosion.gd, qui recopie la boucle d'ecoulement.gd). `heures_par_jour`
# vient de data/banc_fatigue_circadien.json, jamais 24.0 en dur. Si cette
# horloge doit un jour servir un troisieme banc, elle devient candidate au
# coeur : SIGNALE, jamais decide ici. Elle est en SECONDES, jamais en ANNEES
# -- senescence.gd (le seul mecanisme en annees) est deliberement absent de ce
# banc, voir audit_mecaniques_corps_prealable.md ligne 5.
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge les donnees et construit colons/rendu.
#   _unhandled_input bascule le sommeil du colon clique. _process appelle
#   UNIQUEMENT avancer() et lit son resultat pour l'affichage/la console --
#   aucune decision dans _process.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_fatigue_circadien.gd) : heure_courante, construire_colons,
#   poser_heure, evaluer_zone, dans_zone, segments_horloge, deplacer,
#   poser_couts, plafonner_reserves, poser_miroir, causes_dette,
#   relayer_dette, basculer_sommeil, vitesse_effective, avancer, plus les
#   textes d'affichage et de trace.

const Depense = preload("res://scripts/depense.gd")
const Velocite = preload("res://scripts/velocite.gd")
const SeuilEtat = preload("res://scripts/seuil_etat.gd")
const Conditions = preload("res://scripts/conditions.gd")
const Charge = preload("res://scripts/charge.gd")
const EtatDuree = preload("res://scripts/etat_duree.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")

const TAILLE_COLON := 60.0
const LARGEUR_BARRE := 170.0
const HAUTEUR_BARRE := 16.0
const ECART_BARRE := 20.0
const RAYON_CLIC := 90.0
const HORLOGE_ORIGINE := Vector2(20.0, 44.0)
const HORLOGE_LARGEUR := 620.0
const HORLOGE_HAUTEUR := 24.0
const HORLOGE_SEGMENTS := 48

var _config: Dictionary = {}
var _etats: Dictionary = {}
var _catalogue_seuils: Dictionary = {}
var _catalogue_zone: Array = []
var _colons: Array = []

var _fond: ColorRect
var _noeuds: Dictionary = {}          # id -> ColorRect
var _labels: Dictionary = {}          # id -> Label
var _barres: Dictionary = {}          # id -> { nom_barre -> { fond, remplissage } }
var _label_horloge: Label
var _segments_horloge: Array = []     # ColorRect, un par segment
var _curseur_horloge: ColorRect

var _temps := 0.0
var _prochain_print := 0.0

func _ready() -> void:
	_config = _charger_json("res://data/banc_fatigue_circadien.json")
	_etats = _charger_json("res://data/etats.json")
	_catalogue_seuils = _charger_json("res://data/seuils_etat.json")
	_catalogue_zone = _config.get("zone_sommeil", [])

	_colons = construire_colons(_config, _etats)

	_fond = ColorRect.new()
	_fond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fond.size = Vector2(4000.0, 3000.0)
	_fond.position = Vector2(-2000.0, -1500.0)
	add_child(_fond)
	move_child(_fond, 0)

	for colon in _colons:
		_creer_rendu_colon(colon)

	_creer_horloge()
	_poser_camera()
	_rafraichir_tout(float(_config.cycle.heure_depart), dans_zone(float(_config.cycle.heure_depart), _catalogue_zone, _config))
	print(ligne_pose_initiale(_colons, _config, _catalogue_zone))

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var colon: Variant = colon_le_plus_proche(_colons, get_global_mouse_position(), RAYON_CLIC)
	if colon == null:
		return
	var dort := basculer_sommeil(colon)
	print(ligne_toggle(_temps, colon, dort, _config))

func _process(delta: float) -> void:
	_temps += delta
	var bilan := avancer(_colons, _config, _etats, _catalogue_zone, _catalogue_seuils, _temps, delta)
	_rafraichir_tout(bilan.heure, bilan.zone)

	for changement in bilan.bascules_zone:
		print(ligne_zone(bilan.heure, changement))
	for id in bilan.bascules_seuil:
		print(ligne_bascule_etat(bilan.heure, id, _config.nom_etat_epuise, _colons))
	for id in bilan.bascules_dette:
		print(ligne_bascule_dette(bilan.heure, id, _colons, _config))
	for expiree in bilan.expirees:
		print(ligne_expiration(bilan.heure, expiree))

	if _temps >= _prochain_print:
		_prochain_print = _temps + float(_config.intervalle_print)
		print(ligne_trace(_temps, bilan, _colons, _config))

# ---------------------------------------------------------------------------
# Fonctions PURES, testables headless (voir test_banc_fatigue_circadien.gd)
# ---------------------------------------------------------------------------

# Heure simulee au temps ecoule (secondes reelles) : mappe lineairement
# `duree_jour_secondes` sur `heures_par_jour` (lu en donnee, jamais 24.0 en
# dur), boucle sans fin (fmod), part de `heure_depart`. RECOPIE du patron de
# banc_lumiere.gd:heure_courante -- deux bancs jetables ne se referencent
# jamais entre eux. duree_jour_secondes <= 0.0 : reste bloque sur
# heure_depart, jamais une division par zero.
static func heure_courante(temps_ecoule: float, duree_jour_secondes: float, heures_par_jour: float, heure_depart: float) -> float:
	if duree_jour_secondes <= 0.0:
		return heure_depart
	var heures_ecoulees: float = (temps_ecoule / duree_jour_secondes) * heures_par_jour
	return fmod(heure_depart + heures_ecoulees, heures_par_jour)

# Construit les colons declares en donnee. Chaque colon porte :
# - deux canaux de reserve (sommeil, sante) sur le MEME Dictionary
#   `reserves` -- depense.gd les avance independamment, sans qu'aucun ne
#   connaisse l'autre ;
# - un canal de charge (`etats.<nom_canal_dette>`) a portee_charge 0.0 : voir
#   causes_dette ci-dessous, la cause est le colon LUI-MEME ;
# - `vitesse` (base, modulee par etat_effectif.gd), `patrouille`
#   (amplitude/periode, propres a ce banc), `temps_eveille` (horloge de
#   patrouille, ne tourne que quand le colon veille), `dort` (bool, propre a
#   ce banc, jamais lu par un mecanisme du coeur).
# Les etats declares (`etats_actifs` en donnee, verifie contre
# data/etats.json par scripts/test_lint_donnees.gd) sont poses par
# EtatDuree.poser -- jamais recopies a la main dans proprietes.
static func construire_colons(config: Dictionary, etats: Dictionary) -> Array:
	var colons: Array = []
	for decl in config.get("colons", []):
		var pos: Array = decl.position
		var patrouille: Dictionary = decl.get("patrouille", {})
		var colon: Dictionary = {
			"id": decl.id,
			"position": Vector3(pos[0], pos[1], pos[2]),
			"proprietes": {
				config.nom_propriete_vitesse: float(decl.get("vitesse", 0.0)),
				"dort": bool(decl.get("dort", false)),
				"temps_eveille": 0.0,
				"centre_patrouille": Vector3(pos[0], pos[1], pos[2]),
				"amplitude_patrouille": float(patrouille.get("amplitude", 0.0)),
				"periode_patrouille": float(patrouille.get("periode", 0.0)),
				"reserves": {
					config.nom_reserve_sommeil: {
						"reserve": float(decl.get("sommeil_initial", 0.0)),
						"cout_base": 0.0,
						"surcout_action": 0.0,
						"seuils_ref": "",
					},
					config.nom_reserve_sante: {
						"reserve": float(decl.get("sante_initial", 0.0)),
						"cout_base": 0.0,
						"surcout_action": 0.0,
						"seuils_ref": "",
					},
				},
				"etats": {
					config.nom_canal_dette: {
						"charge": 0.0,
						"seuil": float(config.dette.seuil),
						"portee_charge": float(config.dette.portee_charge),
						"taux_decroissance": float(config.dette.taux_decroissance),
						"poser": { config.nom_marqueur_dette: true },
					},
				},
			},
		}
		for nom_etat in decl.get("etats_actifs", []):
			EtatDuree.poser(colon, String(nom_etat), etats)
		colons.append(colon)
	return colons

# Ecrit l'heure du jour sur chaque colon, en propriete PLATE -- c'est le seul
# moyen pour conditions.gd de la comparer (il lit `proprietes[nom]`, jamais
# une variable du banc).
static func poser_heure(colons: Array, heure: float, config: Dictionary) -> void:
	for colon in colons:
		colon.proprietes[config.nom_propriete_heure] = heure

# Rejoue Conditions.evaluer sur chaque colon avec retirer_si_faux=true et rend
# UNIQUEMENT les changements ({ id, avant, apres }), jamais l'etat. Le
# changement est lu AVANT/APRES sur le colon, jamais deduit de la trace rendue
# par le mecanisme : celle-ci dit ce qui a ete POSE, pas si la valeur a change
# (reposer `doit_dormir` sur un colon qui le porte deja figure dans `poses` et
# n'est pourtant pas un changement). Meme geste exact que
# banc_biomes.gd:evaluer_biomes, et meme raison : sans lui la console cracherait
# a chaque frame.
static func evaluer_zone(colons: Array, catalogue: Array, config: Dictionary) -> Array:
	var nom: String = config.nom_marqueur_zone
	var changements: Array = []
	for colon in colons:
		var avant: bool = bool(colon.proprietes.get(nom, false))
		Conditions.evaluer(colon.proprietes, catalogue, true)
		var apres: bool = bool(colon.proprietes.get(nom, false))
		if avant != apres:
			changements.append({"id": colon.id, "avant": avant, "apres": apres})
	return changements

# Est-ce l'heure de dormir, GLOBALEMENT (pour le fond de l'ecran et
# l'horloge) ? Passe par le MEME catalogue et la MEME loi que les colons --
# jamais une comparaison recodee ici, sinon l'affichage pourrait mentir sur ce
# que les colons subissent. Le Dictionary est jetable, cree pour l'appel :
# Conditions.evaluer mute son argument, on ne lui donne donc rien de vivant.
static func dans_zone(heure: float, catalogue: Array, config: Dictionary) -> bool:
	var sonde: Dictionary = { config.nom_propriete_heure: heure }
	var trace: Dictionary = Conditions.evaluer(sonde, catalogue, false)
	return trace.poses.has(config.nom_marqueur_zone)

# L'horloge affichee est ECHANTILLONNEE depuis le catalogue reel (un booleen
# par segment de journee), jamais depuis deux nombres recopies quelque part :
# c'est ce qui garantit que la bande sombre dessinee A L'ECRAN et la zone que
# les colons SUBISSENT ne peuvent pas diverger. nb_segments <= 0 : rend un
# Array vide, jamais une division par zero.
static func segments_horloge(catalogue: Array, config: Dictionary, heures_par_jour: float, nb_segments: int) -> Array:
	var segments: Array = []
	if nb_segments <= 0:
		return segments
	for i in range(nb_segments):
		var heure: float = (float(i) + 0.5) / float(nb_segments) * heures_par_jour
		segments.append(dans_zone(heure, catalogue, config))
	return segments

# Vitesse EFFECTIVE d'un colon : la base (proprietes.vitesse) modulee par tous
# ses etats actifs, via etat_effectif.gd sur le catalogue PONDERE PAR
# L'INTENSITE (etat_duree.gd:etats_ponderes) -- jamais le catalogue brut, sinon
# `endette_sommeil` garderait son plein effet pendant toute son extinction au
# lieu de s'estomper. La loi de resolution (ecraser gagne sur moduler, tri
# alphabetique) n'est JAMAIS reimplementee ici.
static func vitesse_effective(colon: Dictionary, config: Dictionary, etats: Dictionary) -> float:
	var ponderes: Dictionary = EtatDuree.etats_ponderes(colon, etats)
	return EtatEffectif.valeur(colon, config.nom_propriete_vitesse, ponderes)

# Deplace les colons EVEILLES seulement. L'argument du sinus n'est pas le temps
# reel mais `temps_eveille`, une horloge PROPRE au colon qui n'avance que
# lorsqu'il veille et au RYTHME de sa vitesse effective : un colon endormi se
# fige exactement ou il etait et repart d'ou il s'etait arrete (jamais un saut
# de position au reveil), un colon epuise patrouille visiblement plus lentement
# sans qu'aucune branche `if epuise` n'existe. periode <= 0.0 ou amplitude
# 0.0 : le colon ne bouge jamais, cas legitime (le blesse au repos), aucune
# alarme. vitesse de base 0.0 : facteur 1.0, jamais une division par zero.
static func deplacer(colons: Array, config: Dictionary, etats: Dictionary, delta: float) -> void:
	for colon in colons:
		var p: Dictionary = colon.proprietes
		if bool(p.get("dort", false)):
			continue
		var base: float = float(p.get(config.nom_propriete_vitesse, 0.0))
		var facteur: float = 1.0 if base <= 0.0 else vitesse_effective(colon, config, etats) / base
		p["temps_eveille"] = float(p.get("temps_eveille", 0.0)) + delta * facteur
		var periode: float = float(p.get("periode_patrouille", 0.0))
		var amplitude: float = float(p.get("amplitude_patrouille", 0.0))
		if periode <= 0.0 or amplitude == 0.0:
			continue
		var centre: Vector3 = p.centre_patrouille
		var decalage: float = amplitude * sin(TAU * float(p.temps_eveille) / periode)
		colon.position = centre + Vector3(decalage, 0.0, 0.0)

# LE SEUL ENDROIT DU FICHIER QUI ECRIT DANS UN CANAL (voir en-tete, UN SEUL
# ECRIVAIN PAR surcout_action). Deux canaux, deux lois disjointes :
# - sommeil : cout_base POSITIF (metabolisme de la veille) + surcout
#   proportionnel au mouvement REEL, ou cout_base NEGATIF (recuperation) et
#   surcout nul pendant le sommeil ;
# - sante : cout_base NEGATIF (soin) tant que l'etat de blessure est actif,
#   0.0 sinon. Ce gate ne touche QUE le canal sante -- la fatigue est
#   intouchee PAR CONSTRUCTION, jamais par precaution.
# La velocite lue ici est celle que velocite.gd vient de deriver CE TICK (voir
# avancer, l'ordre est fixe) : ce fichier ne calcule jamais un deplacement pour
# en deduire un effort.
static func poser_couts(colons: Array, config: Dictionary) -> void:
	for colon in colons:
		var p: Dictionary = colon.proprietes
		var canal_sommeil: Dictionary = p.reserves[config.nom_reserve_sommeil]
		if bool(p.get("dort", false)):
			canal_sommeil["cout_base"] = -float(config.recuperation_sommeil_par_s)
			canal_sommeil["surcout_action"] = 0.0
		else:
			canal_sommeil["cout_base"] = float(config.cout_veille_par_s)
			var velocite: Vector3 = p.get("velocite", Vector3.ZERO)
			canal_sommeil["surcout_action"] = float(config.coef_effort) * velocite.length()
		var canal_sante: Dictionary = p.reserves[config.nom_reserve_sante]
		var actifs: Array = p.get("etats_actifs", [])
		canal_sante["cout_base"] = -float(config.recuperation_sante_par_s) if actifs.has(config.nom_etat_blesse) else 0.0
		canal_sante["surcout_action"] = 0.0

# ECRETAGE AU PLAFOND -- du cablage, jamais un mecanisme : depense.gd ne borne
# que le BAS (0.0) et rien dans le coeur ne borne le HAUT d'une reserve
# (constat deja pose par banc_fertilite.gd). Rend le total ecrete ce pas
# (surplus perdu, jamais reverse ailleurs), pour la trace.
static func plafonner_reserves(colons: Array, config: Dictionary) -> float:
	var ecrete := 0.0
	var plafonds: Dictionary = {
		config.nom_reserve_sommeil: float(config.capacite_sommeil),
		config.nom_reserve_sante: float(config.capacite_sante),
	}
	for colon in colons:
		var reserves: Dictionary = colon.proprietes.reserves
		for nom in plafonds:
			var canal: Dictionary = reserves[nom]
			var reserve: float = float(canal.get("reserve", 0.0))
			if reserve > plafonds[nom]:
				ecrete += reserve - plafonds[nom]
				canal["reserve"] = plafonds[nom]
	return ecrete

# MIROIR PLAT INVERSE (voir en-tete, point (a)) : la seule forme sous laquelle
# seuil_etat.gd peut voir une reserve descendre. Toujours >= 0.0, la reserve
# etant bornee dans [0, capacite] par depense.gd et plafonner_reserves.
static func poser_miroir(colons: Array, config: Dictionary) -> void:
	var capacite: float = float(config.capacite_sommeil)
	for colon in colons:
		var reserve: float = float(colon.proprietes.reserves[config.nom_reserve_sommeil].get("reserve", 0.0))
		colon.proprietes[config.nom_miroir_manque] = capacite - reserve

# CAUSE SYNTHETISEE, le geste que charge.gd rend possible sans rien connaitre :
# charge.gd ne lit jamais une reserve ni une propriete, il ne recoit qu'un
# Array de { position, poids } construit par l'appelant. La cause est ici le
# colon LUI-MEME, a sa propre position -- combinee a portee_charge 0.0
# (en_portee rend `distance <= 0.0`), elle ne peut alimenter QUE le colon qui
# l'a produite, jamais son voisin. Les colons du banc sont declares a des
# positions distinctes en donnee ; deux colons superposes se chargeraient
# mutuellement, limite assumee de ce montage et verrouillee a l'envers par le
# test (un second veilleur ailleurs ne contribue jamais).
static func causes_dette(colons: Array, config: Dictionary) -> Array:
	var causes: Array = []
	for colon in colons:
		var p: Dictionary = colon.proprietes
		if not bool(p.get(config.nom_marqueur_zone, false)):
			continue
		if bool(p.get("dort", false)):
			continue
		causes.append({"position": colon.position, "poids": float(config.dette.poids)})
	return causes

# RELAIS DU MARQUEUR VERS L'ETAT : charge.gd pose ses cles sur `proprietes`,
# jamais dans `etats_actifs` -- etat_effectif.gd ne verrait donc rien. Ce
# cablage lit le marqueur et repose l'etat CHAQUE TICK tant qu'il dure (idiome
# litteral de `nausee_radiation`/`empoisonne`/`irradie`) : la remise a 1.0 de
# etat_duree.gd:poser n'est jamais un cumul, et des que charge.gd retire son
# marqueur, plus personne ne repose l'etat -- son intensite s'epuise seule et
# etat_duree.gd le retire. Rend les ids reposes ce pas.
static func relayer_dette(colons: Array, config: Dictionary, etats: Dictionary) -> Array:
	var reposes: Array = []
	for colon in colons:
		if not bool(colon.proprietes.get(config.nom_marqueur_dette, false)):
			continue
		EtatDuree.poser(colon, config.nom_etat_endette, etats)
		reposes.append(colon.id)
	return reposes

# Toggle du sommeil au clic. `dort` est une propriete DE CE BANC, jamais lue
# par un mecanisme du coeur : elle ne fait que decider, ici, quel cout_base
# poser et si le colon se deplace. Rend le nouvel etat.
static func basculer_sommeil(colon: Dictionary) -> bool:
	var dort: bool = not bool(colon.proprietes.get("dort", false))
	colon.proprietes["dort"] = dort
	return dort

# LE PAS COMPLET, seul appele par _process (qui ne calcule jamais rien
# lui-meme). ORDRE FIXE ET VOULU, chaque etape depend de la precedente :
#  1. l'heure du jour (accumulateur local + fmod) ;
#  2. elle est ecrite en propriete PLATE sur chaque colon -- sans quoi
#     conditions.gd n'a rien a comparer ;
#  3. conditions.gd pose/retire `doit_dormir`, reversiblement ;
#  4. les colons eveilles se deplacent ;
#  5. velocite.gd derive la velocite -- EN DERNIER apres toute mutation de
#     position, contrat explicite de son en-tete ;
#  6. les couts sont poses (le surcout d'effort lit la velocite de l'etape 5) ;
#  7. depense.gd avance les deux reserves ;
#  8. ecretage au plafond (le coeur ne borne pas le haut) ;
#  9. le miroir plat est reecrit sur la reserve fraiche ;
# 10. seuil_etat.gd pose/retire `epuise` en comparant ce miroir ;
# 11. la cause de dette est synthetisee, charge.gd monte/descend ;
# 12. le marqueur de charge est relaye vers l'etat a duree ;
# 13. etat_duree.gd fait decroitre les intensites et retire ce qui expire.
# Rend { heure, zone, bascules_zone, bascules_seuil, bascules_dette, reposes,
# expirees, ecrete } -- diagnostic de trace, jamais relu comme une source de
# verite.
static func avancer(
	colons: Array,
	config: Dictionary,
	etats: Dictionary,
	catalogue_zone: Array,
	catalogue_seuils: Dictionary,
	temps_ecoule: float,
	delta: float,
) -> Dictionary:
	var cycle: Dictionary = config.cycle
	var heure := heure_courante(temps_ecoule, float(cycle.duree_jour_secondes), float(cycle.heures_par_jour), float(cycle.heure_depart))
	poser_heure(colons, heure, config)
	var bascules_zone := evaluer_zone(colons, catalogue_zone, config)
	deplacer(colons, config, etats, delta)
	Velocite.avancer(colons, delta)
	poser_couts(colons, config)
	Depense.avancer(colons, delta, {})
	var ecrete := plafonner_reserves(colons, config)
	poser_miroir(colons, config)
	var bascules_seuil := SeuilEtat.avancer(colons, catalogue_seuils)
	var bascules_dette := Charge.avancer(colons, causes_dette(colons, config), delta)
	var reposes := relayer_dette(colons, config, etats)
	var expirees := EtatDuree.avancer(colons, delta, etats)
	return {
		"heure": heure,
		"zone": dans_zone(heure, catalogue_zone, config),
		"bascules_zone": bascules_zone,
		"bascules_seuil": bascules_seuil,
		"bascules_dette": bascules_dette,
		"reposes": reposes,
		"expirees": expirees,
		"ecrete": ecrete,
	}

static func colon_le_plus_proche(colons: Array, position_ecran: Vector2, rayon: float) -> Variant:
	var meilleur: Variant = null
	var meilleure_distance := INF
	for colon in colons:
		var pos: Vector3 = colon.position
		var distance: float = Vector2(pos.x, pos.y).distance_to(position_ecran)
		if distance < meilleure_distance and distance <= rayon:
			meilleure_distance = distance
			meilleur = colon
	return meilleur

# COULEUR PAR ETAT, PRIORITE ASSUMEE ET DECLAREE EN DONNEE : plusieurs etats
# coexistent legitimement sur le meme colon (un blesse peut etre epuise ET
# endette), un carre n'a qu'une couleur. L'ordre de `priorite_couleurs`
# tranche, et c'est de l'AFFICHAGE seul -- meme geste que
# banc_changement_etat.gd:couleur_pour_etats priorisant `gaz` sur `liquide`.
# Aucun mecanisme ne hierarchise jamais les etats entre eux.
static func couleur_pour_colon(colon: Dictionary, config: Dictionary) -> Color:
	var couleurs: Dictionary = config.couleurs
	if bool(colon.proprietes.get("dort", false)):
		return _couleur(couleurs.dort)
	var actifs: Array = colon.proprietes.get("etats_actifs", [])
	for nom in config.priorite_couleurs:
		if actifs.has(nom):
			return _couleur(couleurs.get(nom, couleurs.eveille))
	return _couleur(couleurs.eveille)

static func texte_colon(colon: Dictionary, config: Dictionary) -> String:
	var p: Dictionary = colon.proprietes
	var actifs: Array = p.get("etats_actifs", [])
	var noms: Array = []
	for nom in actifs:
		noms.append(String(nom))
	noms.sort()
	if bool(p.get(config.nom_marqueur_zone, false)):
		noms.append(config.nom_marqueur_zone)
	return "%s%s\n%s=%.1f  %s=%.1f\ndette=%.2f/%.1f\n%s" % [
		colon.id,
		"  [DORT]" if bool(p.get("dort", false)) else "",
		config.nom_reserve_sommeil, reserve_de(colon, config.nom_reserve_sommeil),
		config.nom_reserve_sante, reserve_de(colon, config.nom_reserve_sante),
		dette_de(colon, config), float(config.dette.seuil),
		("etats : " + ", ".join(noms)) if not noms.is_empty() else "etats : aucun",
	]

static func reserve_de(colon: Dictionary, nom: String) -> float:
	return float(colon.proprietes.reserves.get(nom, {}).get("reserve", 0.0))

static func dette_de(colon: Dictionary, config: Dictionary) -> float:
	return float(colon.proprietes.etats.get(config.nom_canal_dette, {}).get("charge", 0.0))

# Les bornes de la zone ne sont JAMAIS recopiees ici : la fraction affichee est
# comptee sur les segments echantillonnes depuis le catalogue reel (voir
# segments_horloge) -- une seule source de verite, celle que les colons
# subissent.
static func ligne_pose_initiale(colons: Array, config: Dictionary, catalogue_zone: Array) -> String:
	var segments := segments_horloge(catalogue_zone, config, float(config.cycle.heures_par_jour), 240)
	var dans := 0
	for actif in segments:
		if bool(actif):
			dans += 1
	return "t=0.0 %d colons poses, heure de depart=%.2f, zone de sommeil = %.1f h sur %.1f (%d entrees de conditions.gd)" % [
		colons.size(), float(config.cycle.heure_depart),
		float(dans) / 240.0 * float(config.cycle.heures_par_jour), float(config.cycle.heures_par_jour),
		catalogue_zone.size(),
	]

static func ligne_toggle(t: float, colon: Dictionary, dort: bool, config: Dictionary) -> String:
	return "t=%.1f %s : %s (%s=%.1f)" % [
		t, colon.id, "S'ENDORT" if dort else "SE REVEILLE",
		config.nom_reserve_sommeil, reserve_de(colon, config.nom_reserve_sommeil),
	]

static func ligne_zone(heure: float, changement: Dictionary) -> String:
	return "h=%.2f %s : %s" % [
		heure, changement.id,
		"entre en zone de sommeil" if bool(changement.apres) else "sort de la zone de sommeil",
	]

static func ligne_bascule_etat(heure: float, id: String, nom_etat: String, colons: Array) -> String:
	for colon in colons:
		if colon.id != id:
			continue
		var actif: bool = colon.proprietes.get("etats_actifs", []).has(nom_etat)
		return "h=%.2f %s : %s %s" % [heure, id, nom_etat, "POSE" if actif else "RETIRE"]
	return "h=%.2f %s : bascule de seuil" % [heure, id]

static func ligne_bascule_dette(heure: float, id: String, colons: Array, config: Dictionary) -> String:
	for colon in colons:
		if colon.id != id:
			continue
		var franchi: bool = bool(colon.proprietes.get(config.nom_marqueur_dette, false))
		return "h=%.2f %s : dette de sommeil %s (charge=%.2f)" % [
			heure, id, "FRANCHIE" if franchi else "RESORBEE", dette_de(colon, config),
		]
	return "h=%.2f %s : bascule de dette" % [heure, id]

static func ligne_expiration(heure: float, expiree: Dictionary) -> String:
	return "h=%.2f %s : etat '%s' expire" % [heure, expiree.id, expiree.nom_etat]

static func ligne_trace(t: float, bilan: Dictionary, colons: Array, config: Dictionary) -> String:
	var texte := "t=%.1f h=%.2f zone=%s" % [t, bilan.heure, "sommeil" if bool(bilan.zone) else "veille"]
	for colon in colons:
		var actifs: Array = colon.proprietes.get("etats_actifs", [])
		texte += " | %s %s=%.1f %s=%.1f dette=%.2f%s etats=%d" % [
			colon.id,
			config.nom_reserve_sommeil, reserve_de(colon, config.nom_reserve_sommeil),
			config.nom_reserve_sante, reserve_de(colon, config.nom_reserve_sante),
			dette_de(colon, config),
			" DORT" if bool(colon.proprietes.get("dort", false)) else "",
			actifs.size(),
		]
	return texte

static func _couleur(rgb: Array) -> Color:
	return Color(rgb[0], rgb[1], rgb[2])

# ---------------------------------------------------------------------------
# Rendu (impur, Node) -- aucune decision, seulement des noeuds et une camera.
# ---------------------------------------------------------------------------

func _rafraichir_tout(heure: float, zone: bool) -> void:
	_fond.color = _couleur(_config.couleurs.fond_nuit if zone else _config.couleurs.fond_jour)
	for colon in _colons:
		var noeud: ColorRect = _noeuds[colon.id]
		noeud.position = Vector2(colon.position.x, colon.position.y) - noeud.size / 2.0
		noeud.color = couleur_pour_colon(colon, _config)
		_labels[colon.id].text = texte_colon(colon, _config)
		_rafraichir_barres(colon)
	_label_horloge.text = "heure = %.2f    zone de sommeil : %s" % [heure, "OUI" if zone else "non"]
	var heures_par_jour: float = float(_config.cycle.heures_par_jour)
	var ratio: float = clamp(heure / heures_par_jour, 0.0, 1.0) if heures_par_jour > 0.0 else 0.0
	_curseur_horloge.position = HORLOGE_ORIGINE + Vector2(HORLOGE_LARGEUR * ratio - 2.0, 0.0)

func _rafraichir_barres(colon: Dictionary) -> void:
	var barres: Dictionary = _barres[colon.id]
	_regler_barre(barres[_config.nom_reserve_sommeil], reserve_de(colon, _config.nom_reserve_sommeil) / float(_config.capacite_sommeil))
	_regler_barre(barres[_config.nom_reserve_sante], reserve_de(colon, _config.nom_reserve_sante) / float(_config.capacite_sante))
	_regler_barre(barres[_config.nom_canal_dette], dette_de(colon, _config) / max(float(_config.dette.seuil), 0.0001))

func _regler_barre(barre: Dictionary, ratio: float) -> void:
	var remplissage: ColorRect = barre.remplissage
	remplissage.size = Vector2(LARGEUR_BARRE * clamp(ratio, 0.0, 1.0), HAUTEUR_BARRE)

func _creer_rendu_colon(colon: Dictionary) -> void:
	var centre := Vector2(colon.position.x, colon.position.y)

	var noeud := ColorRect.new()
	noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noeud.size = Vector2(TAILLE_COLON, TAILLE_COLON)
	noeud.position = centre - noeud.size / 2.0
	add_child(noeud)
	_noeuds[colon.id] = noeud

	var label := Label.new()
	label.add_theme_font_size_override("font_size", 14)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.position = Vector2(_config.colonne_labels_x, centre.y - 46.0)
	add_child(label)
	_labels[colon.id] = label

	var barres: Dictionary = {}
	var y := centre.y + 54.0
	for nom in [_config.nom_reserve_sommeil, _config.nom_reserve_sante, _config.nom_canal_dette]:
		barres[nom] = _creer_barre(Vector2(_config.colonne_labels_x, y), _config.couleurs.get("barre_" + String(nom), [1.0, 1.0, 1.0]))
		y += ECART_BARRE
	_barres[colon.id] = barres

func _creer_barre(position: Vector2, rgb: Array) -> Dictionary:
	var fond := ColorRect.new()
	fond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fond.size = Vector2(LARGEUR_BARRE, HAUTEUR_BARRE)
	fond.position = position
	fond.color = _couleur(_config.couleurs.barre_fond)
	add_child(fond)

	var remplissage := ColorRect.new()
	remplissage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	remplissage.size = Vector2(0.0, HAUTEUR_BARRE)
	remplissage.position = position
	remplissage.color = _couleur(rgb)
	add_child(remplissage)

	return {"fond": fond, "remplissage": remplissage}

func _creer_horloge() -> void:
	var couche_ui := CanvasLayer.new()
	add_child(couche_ui)

	_label_horloge = Label.new()
	_label_horloge.position = Vector2(20.0, 14.0)
	couche_ui.add_child(_label_horloge)

	var etats_segments := segments_horloge(_catalogue_zone, _config, float(_config.cycle.heures_par_jour), HORLOGE_SEGMENTS)
	var largeur_segment := HORLOGE_LARGEUR / float(HORLOGE_SEGMENTS)
	for i in range(etats_segments.size()):
		var segment := ColorRect.new()
		segment.mouse_filter = Control.MOUSE_FILTER_IGNORE
		segment.size = Vector2(largeur_segment + 1.0, HORLOGE_HAUTEUR)
		segment.position = HORLOGE_ORIGINE + Vector2(largeur_segment * float(i), 0.0)
		segment.color = _couleur(_config.couleurs.horloge_nuit if bool(etats_segments[i]) else _config.couleurs.horloge_jour)
		couche_ui.add_child(segment)
		_segments_horloge.append(segment)

	_curseur_horloge = ColorRect.new()
	_curseur_horloge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_curseur_horloge.size = Vector2(4.0, HORLOGE_HAUTEUR)
	_curseur_horloge.position = HORLOGE_ORIGINE
	_curseur_horloge.color = _couleur(_config.couleurs.horloge_curseur)
	couche_ui.add_child(_curseur_horloge)

func _poser_camera() -> void:
	var decl: Dictionary = _config.get("camera", {})
	var pos: Array = decl.get("position", [0.0, 0.0])
	var camera := Camera2D.new()
	camera.position = Vector2(pos[0], pos[1])
	camera.zoom = Vector2(decl.get("zoom", 1.0), decl.get("zoom", 1.0))
	camera.enabled = true
	add_child(camera)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
