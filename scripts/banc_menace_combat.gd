extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_menace_combat.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1). Chantier « menace -> peur/colere
# -- score, bifurcation, effets » (audit_mecaniques_psycho_sociales_prealable.md,
# lignes 1/2/3/4). Compose HUIT mecanismes deja fermes, TOUS INCHANGES :
# comptage.gd (le ratio d'effectifs), occlusion.gd (la visibilite), charge.gd
# (le stress qui monte sous cause synthetisee et redescend seul),
# bifurcation.gd (la sortie choisie par produit biais x grandeur),
# deformation.gd (la saillance de l'ennemi amplifiee pour CE colon seul),
# etat_duree.gd + etat_effectif.gd (l'etat pose et ses effets), plus le
# pipeline perception.gd -> proximite.gd -> dominance.gd -> agir.gd -> fuite.gd.
# AUCUN MECANISME DU COEUR TOUCHE, AUCUN .gd neuf du coeur.
#
# CE QUE CE BANC MONTRE, ET QU'AUCUN AUTRE NE MONTRAIT :
#
# 1) UN SCORE DE MENACE CONTINU, produit de trois grandeurs qui ne se
#    ressemblent pas -- distance (geometrie), ratio d'effectifs (comptage.gd,
#    deux appels et une division) et visibilite (occlusion.gd, facteur continu
#    [0,1]). Aucune de ces trois pieces n'est neuve ; ce qui l'est, c'est
#    qu'elles se multiplient et nourrissent le champ "poids" d'une cause de
#    charge.gd. TROISIEME cause SYNTHETISEE du depot (apres banc_nutrition.gd
#    et banc_fatigue_circadien.gd) : { position: colon.position, poids: score }
#    a portee_charge 0.0 -- le colon est sa propre cause, charge.gd ne scanne
#    jamais le monde.
#
# 2) LA PREMIERE BIFURCATION REELLE DU DEPOT. bifurcation.gd (livre par le
#    groupe 0 de ce meme chantier) n'avait aucun appelant : ici, au
#    franchissement du seuil de charge, le cablage lui passe la charge, le
#    biais du colon et deux sorties declarees en donnee, et POSE l'etat
#    gagnant. Trois colons, meme code, memes ennemis : seul biais_combat les
#    separe (docs/design.md, « Les archetypes n'existent pas »).
#
# 3) LA PREMIERE PROPRIETE A DEUX VERBES du depot
#    (data/types_choses.json:hostile -> ["approcher", "s_eloigner"]). Jusqu'ici
#    chaque propriete n'en proposait qu'un seul, ce qui rendait poids_verbes
#    fonctionnellement inerte (audit §5). C'est ce qui permet a la MEME chose,
#    percue par le MEME colon, d'appeler deux gestes opposes selon son etat
#    interne.
#
# AUCUN HASARD, NULLE PART -- docs/design.md, REGLE ANTI-BRUIT. Il n'y a pas
# un seul RNG dans ce fichier, et pas de "prob_fuite_par_s" : la peur ne tire
# aucun de. Elle fait DEUX choses, toutes deux deterministes et relisibles
# apres coup :
#   (a) elle amplifie la saillance de la propriete de menace via
#       deformation.gd (sens "monte", proximite.gd:_appliquer_deformation) --
#       l'ennemi finit par ECRASER l'ouvrage voisin (dominance.gd le RETIRE de
#       la liste, il ne devient pas "moins prioritaire") ;
#   (b) elle recompose poids_verbes pour que "s_eloigner" batte "approcher"
#       sur la propriete "hostile".
# LES DEUX SONT NECESSAIRES, et c'est le constat central de ce cablage
# (audit, constat A) : agir.gd:choisir choisit une CIBLE au score de saillance,
# puis _verbe_par_poids choisit un VERBE en ne lisant QUE poids_verbes. Une
# saillance amplifiee ne fait donc JAMAIS gagner un verbe, et un poids_verbes
# eleve ne fait JAMAIS gagner une cible. La deformation seule aurait produit un
# colon qui fonce sur ce qu'il craint ; poids_verbes seul, un colon qui fuit un
# ennemi qu'il ne regarde meme pas.
#
# UN SEUL ECRIVAIN DE poids_verbes (audit, constat C -- meme piege que
# depense.gd:surcout_action, ferme par banc_faim_thermo.gd) :
# poser_poids_verbes ci-dessous est le SEUL endroit du fichier qui ecrit cette
# cle, et il l'ecrit EN ENTIER a chaque tick depuis la donnee, jamais par
# increment. Deux morceaux de cablage qui l'auraient touchee chacun de leur
# cote se seraient ecrases EN SILENCE, sans qu'aucun test ne rougisse.
#
# "prob_fuite" EST LU, ce n'est pas un chemin mort -- et il n'est jamais tire
# au sort. data/etats.json:colere l'ECRASE a 0.0 (mode "ecraser", meme geste
# que mort_radiation sur vitesse) ; agir_et_deplacer le lit par
# EtatEffectif.valeur et n'entre dans sa branche de fuite QUE s'il est
# strictement positif. Un colon en colere ne fuit donc jamais, MEME si le
# verbe resolu etait "s_eloigner" -- garde deterministe, jamais un de. Sans
# cette lecture explicite, declarer l'effet dans data/etats.json n'aurait
# STRICTEMENT rien produit (audit, constat D : aucune couche de decision ne
# passe par etat_effectif.gd). Meme raison pour "precision"/"endurance"/
# "degats", lus par le label -- trois proprietes qui n'existaient nulle part
# dans le depot avant ce chantier, posees en base sur le colon de ce banc.
#
# LE BIAIS PASSE A LA BIFURCATION EST COMPOSE (voir biais_effectif) :
# bifurcation.gd multiplie chaque biais par UNE grandeur commune, qui ne peut
# donc jamais departager deux biais egaux -- un colon a 0.5/0.5 tomberait sur
# une egalite stricte, que le mecanisme refuse de trancher (push_error,
# premiere sortie declaree conservee). Le cablage compose donc la peur par le
# ratio d'effectifs et laisse la colere a 1.0. Le biais PERSONNEL
# (proprietes.biais_combat) n'est jamais reecrit : la composition est une
# LECTURE, refaite a neuf chaque tick.
#
# LES COLONS SONT CONSTRUITS A LA MAIN (patron banc_nutrition.gd/
# banc_maladie.gd), jamais Objet.fabriquer/BancCommun.fabriquer_colon --
# data/types.json:colon porte deja un canal de charge nomme "peur"
# (portee_charge 900.0) qui capterait la cause synthetisee de ce banc (distance
# 0.0) et ferait monter une seconde peur parasite. Consequence utile :
# data/types.json n'est pas touche, donc rien a enregistrer dans
# scripts/test_lint_donnees.gd.
#
# LIMITE DITE, PAS MASQUEE : un colon qui fuit s'eloigne, son score baisse, sa
# charge repasse sous le seuil, son etat se retire, il revient vers son
# ouvrage -- et le cycle recommence. C'est physiquement juste (on cesse d'avoir
# peur quand on est hors de danger) et non corrige : aucune hysteresis n'est
# posee, charge.gd n'en a pas (voir son en-tete, « UN SEUL SEUIL PAR CANAL »).
#
# CONTROLE : clic gauche = palier d'effectifs suivant (4 ennemis -> 2 -> 6 ->
# 0, cycle). Le Monde est RECONSTRUIT DU NEANT a chaque palier (monde.gd n'a
# aucune fonction de retrait, dette deja recensee) et les colons y sont
# RE-AJOUTES PAR REFERENCE, donc leur position, leur charge et leur deformation
# survivent au changement -- meme geste que banc_elimination_salete.gd.
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge les catalogues et construit, _unhandled_input
#   change de palier, _process appelle avancer(...) puis redessine.
# - Fonctions statiques (pures, testables headless, voir
#   scripts/test_banc_menace_combat.gd) : tout le reste.

const Perception = preload("res://scripts/perception.gd")
const Proximite = preload("res://scripts/proximite.gd")
const Dominance = preload("res://scripts/dominance.gd")
const Agir = preload("res://scripts/agir.gd")
const Fuite = preload("res://scripts/fuite.gd")
const Monde = preload("res://scripts/monde.gd")
const Charge = preload("res://scripts/charge.gd")
const Comptage = preload("res://scripts/comptage.gd")
const Occlusion = preload("res://scripts/occlusion.gd")
const Bifurcation = preload("res://scripts/bifurcation.gd")
const Deformation = preload("res://scripts/deformation.gd")
const EtatDuree = preload("res://scripts/etat_duree.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")

const SORTIE_AUCUNE := ""

const TAILLE_COLON := 34.0
const TAILLE_ENNEMI := 26.0
const TAILLE_OUVRAGE := 30.0
const TAILLE_MUR := Vector2(160.0, 22.0)
const LARGEUR_BARRE := 110.0
const HAUTEUR_BARRE := 9.0
const TAILLE_POLICE_LABEL := 11
const TAILLE_POLICE_COMPTEUR := 14
const LARGEUR_LIGNE := 2.0
const LONGUEUR_LIGNE_FUITE := 130.0
const PERIODE_TRACE_S := 2.0

var _config: Dictionary = {}
var _etats: Dictionary = {}
var _catalogue_canaux: Dictionary = {}
var _catalogue_deformations: Dictionary = {}
var _catalogue_actions: Dictionary = {}
var _orientations: Dictionary = {}
var _profils_saillance: Dictionary = {}

var _monde := Monde.new()
var _colons: Array = []
var _ennemis: Array = []
var _ouvrages: Array = []
var _murs: Array = []
var _palier := 0
var _temps := 0.0
var _prochaine_trace := 0.0
var _sorties_precedentes: Dictionary = {}

var _couche_ui: CanvasLayer
var _noeuds: Dictionary = {}
var _labels: Dictionary = {}
var _fonds_barres: Dictionary = {}
var _barres_stress: Dictionary = {}
var _lignes: Dictionary = {}
var _label_compteur: Label

# Le rendu relit l'etat du DERNIER pas, jamais une valeur recalculee a cote --
# le label ne peut donc pas mentir sur ce que le colon subit (meme discipline
# que banc_fatigue_circadien.gd sur son horloge affichee).
var _dernier_resultat: Dictionary = {}

func _ready() -> void:
	_config = _charger_json("res://data/banc_menace_combat.json")
	_etats = _charger_json("res://data/etats.json")
	_catalogue_canaux = _charger_json("res://data/canaux.json")
	_catalogue_deformations = _charger_json("res://data/deformations.json")
	_catalogue_actions = _charger_json("res://data/types_choses.json")
	_orientations = _charger_json("res://data/orientations.json")
	_profils_saillance = _charger_json("res://data/profils_saillance.json")

	_colons = fabriquer_colons(_config)
	_ouvrages = fabriquer_ouvrages(_config)
	_murs = fabriquer_murs(_config)
	_ennemis = fabriquer_ennemis(_config, nombre_du_palier(_config, 0))
	_reconstruire_monde()

	_couche_ui = CanvasLayer.new()
	add_child(_couche_ui)
	_creer_rendu()
	_poser_camera()
	_rafraichir_tout()
	print(_ligne_palier(0.0, _ennemis.size(), _colons.size()))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_palier = palier_suivant(_palier, _config)
		_ennemis = fabriquer_ennemis(_config, nombre_du_palier(_config, _palier))
		_reconstruire_monde()
		_recreer_noeuds_ennemis()
		print(_ligne_palier(_temps, _ennemis.size(), _colons.size()))

func _process(delta: float) -> void:
	_temps += delta
	var resultat := avancer(
		_colons, BancCommun.objets_de(_monde), _monde, _config, _etats,
		_catalogue_canaux, _catalogue_deformations, _profils_saillance,
		_catalogue_actions, _orientations, delta,
	)
	_dernier_resultat = resultat

	for etat_colon in resultat.colons:
		var precedente: String = _sorties_precedentes.get(etat_colon.id, SORTIE_AUCUNE)
		if etat_colon.sortie != precedente:
			_sorties_precedentes[etat_colon.id] = etat_colon.sortie
			print(_ligne_bifurcation(_temps, etat_colon, resultat.ratio))
	if _temps >= _prochaine_trace:
		_prochaine_trace = _temps + PERIODE_TRACE_S
		for etat_colon in resultat.colons:
			print(_ligne_etat(_temps, etat_colon, resultat.ratio))

	_rafraichir_tout()

# ---- Fonctions PURES, testables headless (voir test_banc_menace_combat.gd) ----

# Les trois colons, CONSTRUITS A LA MAIN (voir en-tete). Tout ce qui est commun
# vient de config.colon_commun et est DUPLIQUE par colon (duplicate(true)) --
# jamais partage avec le Dictionary du disque, meme precaution d'aliasing que
# banc_nutrition.gd:fabriquer_colon. Seuls "position" et "biais_combat"
# different d'un colon a l'autre : c'est la doctrine « les archetypes n'existent
# pas » rendue litterale -- meme corps, meme perception, meme forme, seul le
# poids sur chaque sortie separe le lache de l'agressif.
#
# deformation_sources porte LES DEUX sources (une par sortie possible) :
# Deformation.poser refuse (push_error, aucune ecriture) toute source non
# declaree, donc les declarer ici est structurel, jamais decoratif.
static func fabriquer_colons(config: Dictionary) -> Array:
	var commun: Dictionary = config.get("colon_commun", {})
	var sources: Array = []
	for sortie in config.get("deformation_par_sortie", {}):
		sources.append(String(config.deformation_par_sortie[sortie]))
	var colons: Array = []
	for nom in config.get("colons", {}):
		var decl: Dictionary = config.colons[nom]
		var pos: Array = decl.position
		colons.append({
			"id": String(nom),
			"position": Vector3(pos[0], pos[1], pos[2]),
			"action_en_cours": {},
			"action_precedente": "__jamais__",
			"proprietes": {
				String(config.propriete_allie): true,
				"vitesse": float(commun.vitesse),
				"precision": float(commun.precision),
				"endurance": float(commun.endurance),
				"degats": float(commun.degats),
				String(config.propriete_prob_fuite): float(commun.prob_fuite),
				"forme": commun.forme.duplicate(true),
				"attaches": [],
				"poids_verbes": config.poids_verbes_repos.duplicate(true),
				"canaux": commun.canaux.duplicate(true),
				"canaux_config": commun.canaux_config.duplicate(true),
				"biais_combat": decl.biais_combat.duplicate(true),
				"deformation_sources": sources.duplicate(),
				"deformation_etat": {},
				"etats": {String(config.nom_canal_stress): config.canal_stress.duplicate(true)},
				"etats_actifs": [],
			},
		})
	return colons

# Les "nombre" premiers ennemis declares -- l'ORDRE de config.ennemis est donc
# l'ordre d'apparition, et un palier plus bas retire toujours les DERNIERS
# declares. Chacun porte la propriete de menace (plate, lue par agir.gd:_action
# contre data/types_choses.json) ET un profil de saillance (lu par
# proximite.gd) : sans le premier il ne resout aucun verbe, sans le second il
# n'entre jamais dans la decision.
static func fabriquer_ennemis(config: Dictionary, nombre: int) -> Array:
	var ennemis: Array = []
	for decl in config.get("ennemis", []):
		if ennemis.size() >= nombre:
			break
		var pos: Array = decl.position
		ennemis.append({
			"id": String(decl.id),
			"position": Vector3(pos[0], pos[1], pos[2]),
			"proprietes": {
				String(config.propriete_menace): true,
				"profil_saillance": String(config.profil_saillance_ennemi),
				"etats_actifs": [],
			},
		})
	return ennemis

# L'OUVRAGE est la CONCURRENCE, sans laquelle l'ecrasement de dominance.gd
# n'aurait rien a ecraser (voir en-tete). Il porte la propriete actionnable et
# un profil de saillance, rien d'autre -- il ne bouge jamais, ne se consomme
# jamais, n'a aucun travail_restant (proximite.gd:_poids_avancement rend donc
# 1.0, point neutre legitime).
static func fabriquer_ouvrages(config: Dictionary) -> Array:
	var ouvrages: Array = []
	for decl in config.get("ouvrages", []):
		var pos: Array = decl.position
		ouvrages.append({
			"id": String(decl.id),
			"position": Vector3(pos[0], pos[1], pos[2]),
			"proprietes": {
				String(config.propriete_ouvrage): true,
				"profil_saillance": String(config.profil_saillance_ouvrage),
				"etats_actifs": [],
			},
		})
	return ouvrages

# Le mur ne porte QUE la propriete d'occlusion : aucun profil de saillance
# (proximite.gd l'ignore, ref == "" -> continue), aucune propriete actionnable
# (agir.gd n'y resout aucun verbe). Il n'existe que pour se trouver ENTRE un
# colon et des ennemis.
static func fabriquer_murs(config: Dictionary) -> Array:
	var murs: Array = []
	for decl in config.get("murs", []):
		var pos: Array = decl.position
		murs.append({
			"id": String(decl.id),
			"position": Vector3(pos[0], pos[1], pos[2]),
			"proprietes": {String(config.propriete_obstacle): float(decl.opacite)},
		})
	return murs

static func palier_suivant(palier: int, config: Dictionary) -> int:
	var paliers: Array = config.get("paliers_ennemis", [])
	if paliers.is_empty():
		return 0
	return (palier + 1) % paliers.size()

static func nombre_du_palier(config: Dictionary, palier: int) -> int:
	var paliers: Array = config.get("paliers_ennemis", [])
	if paliers.is_empty():
		return 0
	return int(paliers[palier % paliers.size()])

# RATIO D'EFFECTIFS -- deux appels a comptage.gd et une division, zero ligne de
# mecanisme (audit ligne 1). Le catalogue de regles est LOCAL au banc (format
# exact de data/comptages.json, passe tel quel -- comptage.gd recoit toujours
# son catalogue en parametre), meme geste que
# data/banc_elimination_salete.json:seuils_elimination.
#
# AUCUN ALLIE (liste vide, ou colons tous retires) : rend 0.0 plutot qu'une
# division par zero. Ce n'est pas « pas de menace » -- c'est « on ne sait pas
# comparer », et un score nul est la seule reponse honnete d'un ratio sans
# denominateur ; le cas ne se produit jamais dans ce banc (les trois colons ne
# sont jamais retires), il est garde parce qu'une division par zero rendrait INF
# et ferait exploser la charge en silence.
static func ratio_effectifs(objets: Array, config: Dictionary) -> float:
	var comptages: Dictionary = config.get("comptages", {})
	var ennemis: int = Comptage.compter(objets, String(config.regle_ennemi), comptages)
	var allies: int = Comptage.compter(objets, String(config.regle_allie), comptages)
	if allies <= 0:
		return 0.0
	return float(ennemis) / float(allies)

# VISIBILITE d'une menace depuis un colon -- occlusion.gd tel quel, facteur
# continu [0,1]. "obstacles" est la liste ENTIERE des choses du monde : celles
# qui ne portent pas la propriete d'occlusion valent 0.0 (transparent, sans
# alarme, voir occlusion.gd), il n'y a donc aucun filtre a faire ici. La source
# elle-meme est deja exclue par la geometrie (projection t >= 1.0), jamais par
# un ids_exclus.
static func visibilite(colon: Dictionary, menace: Dictionary, obstacles: Array, config: Dictionary) -> float:
	return Occlusion.facteur(
		colon.position, menace.position, obstacles,
		String(config.propriete_obstacle), float(config.largeur_obstacle),
	)

# LE SCORE DE MENACE (audit ligne 1). Par ennemi : facteur de distance
# (LINEAIRE et BORNE A ZERO -- un ennemi au-dela de portee_max_menace ne
# soulage jamais, il ne compte simplement plus ; sans ce max() un colon qui
# fuit assez loin produirait un score NEGATIF, et charge.gd traiterait cette
# somme negative comme « aucune cause », ce qui marcherait par accident) fois
# le ratio fois la visibilite. SOMME sur les ennemis -- decision de ce banc,
# absente de la consigne : quatre ennemis doivent peser plus que deux, un max()
# ne l'aurait jamais rendu.
static func score_menace(colon: Dictionary, ennemis: Array, ratio: float, obstacles: Array, config: Dictionary) -> float:
	var portee: float = float(config.portee_max_menace)
	if portee <= 0.0:
		return 0.0
	var total := 0.0
	for menace in ennemis:
		var distance: float = colon.position.distance_to(menace.position)
		var facteur_distance: float = max(0.0, 1.0 - distance / portee)
		if facteur_distance <= 0.0:
			continue
		total += facteur_distance * ratio * visibilite(colon, menace, obstacles, config)
	return total

# LA CAUSE SYNTHETISEE (voir en-tete, point 1). Rend un Array VIDE quand le
# score est nul -- et c'est ce vide, jamais un poids a 0.0, qui declenche la
# redescente autonome de charge.gd (taux_decroissance n'est applique que si la
# somme des poids a portee est nulle ce pas ; un poids 0.0 y serait une somme
# nulle aussi, mais l'Array vide dit l'intention).
static func causes_de_menace(colon: Dictionary, score: float) -> Array:
	if score <= 0.0:
		return []
	return [{"position": colon.position, "poids": score}]

static func ennemis_de(objets: Array, config: Dictionary) -> Array:
	var resultat: Array = []
	for chose in objets:
		if chose.proprietes.get(String(config.propriete_menace), false):
			resultat.append(chose)
	return resultat

static func charge_stress(colon: Dictionary, config: Dictionary) -> float:
	return float(colon.proprietes.get("etats", {})
		.get(String(config.nom_canal_stress), {}).get("charge", 0.0))

static func stress_franchi(colon: Dictionary, config: Dictionary) -> bool:
	return colon.proprietes.get(String(config.nom_marqueur_stress), false)

# La sortie ACTIVE, lue sur etats_actifs -- jamais une variable tenue a cote.
# Rend "" si aucune des sorties declarees n'y figure.
static func sortie_active(colon: Dictionary, config: Dictionary) -> String:
	var actifs: Array = colon.proprietes.get("etats_actifs", [])
	for sortie in config.get("sorties_bifurcation", []):
		if actifs.has(String(sortie)):
			return String(sortie)
	return SORTIE_AUCUNE

# LE BIAIS COMPOSE (voir en-tete). LECTURE PURE : ne mute jamais
# proprietes.biais_combat, qui reste le biais PERSONNEL du colon, en donnee.
# La peur est ponderee par le ratio d'effectifs, la colere ne l'est pas -- ce
# qui donne, a biais personnels egaux (0.5/0.5), une bascule exactement a
# ratio 1.0 : autant d'ennemis que d'allies. Une sortie absente de
# biais_combat vaut 0.0 (bifurcation.gd la traite deja ainsi), aucune alarme.
#
# CE N'EST PAS UN CONTOURNEMENT, c'est la seule voie que le mecanisme laisse,
# et il le dit lui-meme (bifurcation.gd, « LIMITE REELLE DE CETTE LOI ») : la
# grandeur est UN SEUL SCALAIRE commun a toutes les sorties, elle multiplie
# donc tous les scores par le meme nombre et NE CHANGE JAMAIS QUI GAGNE --
# l'argmax est celui des poids seuls. Faire dependre le choix de la situation
# EXIGE donc de composer le biais, ou d'avoir une grandeur PAR sortie, ce qui
# serait une autre signature et un autre chantier. Le cablage compose ; le
# mecanisme reste intact.
static func biais_effectif(colon: Dictionary, ratio: float, config: Dictionary) -> Dictionary:
	var base: Dictionary = colon.proprietes.get("biais_combat", {})
	var facteurs: Dictionary = {}
	for sortie in config.get("sorties_bifurcation", []):
		facteurs[String(sortie)] = 1.0
	if facteurs.has("peur"):
		facteurs["peur"] = ratio
	var compose: Dictionary = {}
	for sortie in facteurs:
		compose[sortie] = float(base.get(sortie, 0.0)) * float(facteurs[sortie])
	return compose

# BIFURQUER PUIS POSER. Tant que le marqueur de charge.gd est absent, AUCUNE
# sortie n'est active : le cablage efface les deux d'etats_actifs (miroir exact
# du marqueur reversible, meme geste que banc_nutrition.gd:_relayer_marqueur --
# ni "peur" ni "colere" ne portent de "duree", etat_duree.gd:avancer ne les
# retirerait donc JAMAIS tout seul).
#
# Marqueur present : Bifurcation.selectionner(charge, biais compose, sorties).
# EtatDuree.poser est idempotent (il n'ajoute le nom que s'il n'y est pas
# deja), il peut donc etre rappele a chaque tick sans empiler quoi que ce soit
# -- meme idiome que 'nausee_radiation'. La sortie PERDANTE est effacee au
# meme instant : une seule sortie active a la fois est une garantie du
# CABLAGE, jamais du catalogue.
#
# Rend la sortie retenue ("" si aucune).
static func relayer_bifurcation(colon: Dictionary, ratio: float, config: Dictionary, etats: Dictionary) -> String:
	var sorties: Array = config.get("sorties_bifurcation", [])
	var retenue := SORTIE_AUCUNE
	if stress_franchi(colon, config):
		var choix: Dictionary = Bifurcation.resoudre(charge_stress(colon, config), biais_effectif(colon, ratio, config), sorties)
		retenue = String(choix.sortie)
	var actifs: Array = colon.proprietes.get("etats_actifs", [])
	for sortie in sorties:
		var nom: String = String(sortie)
		if nom == retenue:
			EtatDuree.poser(colon, nom, etats)
		else:
			actifs.erase(nom)
	return retenue

# UNIQUE ECRIVAIN de poids_verbes (voir en-tete). Ecrit la table EN ENTIER
# depuis la donnee, jamais un increment sur la precedente -- deux tables
# successives ne peuvent donc pas se melanger, et l'etat de repos est retabli
# exactement quand la sortie retombe a "".
static func poser_poids_verbes(colon: Dictionary, sortie: String, config: Dictionary) -> void:
	var par_sortie: Dictionary = config.get("poids_verbes_par_sortie", {})
	var table: Dictionary = par_sortie.get(sortie, config.get("poids_verbes_repos", {}))
	colon.proprietes["poids_verbes"] = table.duplicate(true)

# LA DEFORMATION, posee tant qu'une sortie est active et sur la cible nommee en
# donnee (la propriete de menace) -- jamais un nom en dur.
#
# DEUX CONTRAINTES QUE deformation.gd IMPOSE, aucune contournable en donnee, et
# toutes deux payees ici :
# (1) poser() n'a AUCUN parametre de temps (meme limite qu'epigenetique.gd:
#     poser, nommee par l'audit ligne 12) -- une magnitude fixe par image ferait
#     monter le biais a une vitesse dependant de la machine. La magnitude posee
#     est donc un DEBIT PAR SECONDE multiplie par delta.
# (2) IL N'EXISTE AUCUN EQUILIBRE NATUREL. avancer() decroit par SOUSTRACTION
#     FIXE (max(0, registre - taux*delta)), jamais par une fraction du registre
#     courant : tant que le debit de pose depasse le taux, le registre monte
#     LINEAIREMENT ET SANS BORNE. LE PLAFOND EST DONC AU CABLAGE -- ce fichier
#     cesse de poser des que Deformation.biais atteint config.plafond_biais,
#     ce qui borne la montee ET garde une descente courte. Meme resultat, paye
#     independamment par banc_psycho_social.gd (session concurrente) et note
#     dans data/deformations.json.
#
# avancer() est appele DANS TOUS LES CAS, y compris sans sortie active et y
# compris au plafond : c'est lui, et lui seul, qui fait redescendre le biais
# quand la menace disparait.
static func avancer_deformation(
	colon: Dictionary,
	sortie: String,
	config: Dictionary,
	catalogue_deformations: Dictionary,
	delta: float,
) -> void:
	if sortie != SORTIE_AUCUNE:
		var source: String = String(config.get("deformation_par_sortie", {}).get(sortie, ""))
		var cible: String = String(config.propriete_menace)
		if source != "" and Deformation.biais(colon, source, cible, catalogue_deformations) < float(config.plafond_biais):
			Deformation.poser(colon, source, cible, float(config.magnitude_deformation_par_s) * delta)
	Deformation.avancer(colon, delta, catalogue_deformations)

# QUATRE COUCHES : perception -> proximite -> dominance -> agir. Ni attaches.gd
# (les colons de ce banc ne tiennent a rien -- attaches: []), ni jugement.gd
# (aucun declencheur juge ici) : les ajouter n'aurait rien apporte a ce que le
# banc doit montrer, et chaque couche de plus est une saillance de plus a
# calibrer. Rend { decision, resultats, visibles, perceptions }, meme forme que
# banc_charge.gd:decider.
static func decider(
	colon: Dictionary,
	monde,
	catalogue_canaux: Dictionary,
	profils_saillance: Dictionary,
	catalogue_deformations: Dictionary,
	catalogue_actions: Dictionary,
) -> Dictionary:
	var perceptions := Perception.percevoir(colon, monde, catalogue_canaux)
	var resultats := Proximite.evaluer(perceptions, colon, profils_saillance, catalogue_deformations)
	var visibles := Dominance.visibles(resultats, colon)
	var decision = Agir.choisir(visibles, colon, catalogue_actions, monde)
	colon.action_en_cours = Agir.etat_courant(decision)
	return {"decision": decision, "resultats": resultats, "visibles": visibles, "perceptions": perceptions}

# GESTE COMPLET decision -> mouvement. MUTE colon.position EN PLACE.
#
# LE GATE prob_fuite (voir en-tete) : la branche de fuite exige DEUX conditions,
# le verbe resolu oriente "fuite" ET une prob_fuite effective strictement
# positive. Un colon en colere (prob_fuite ecrasee a 0.0) dont le verbe serait
# malgre tout "s_eloigner" NE BOUGE PAS -- il tient sa position plutot que de
# fuir, et ce cas ne se produit jamais avec les poids_verbes de ce banc (la
# colere met "approcher" au-dessus) : le gate est une garde, pas un chemin
# principal. Il est verrouille par test parce qu'une garde jamais exercee est
# une garde qu'on croit avoir.
static func agir_et_deplacer(
	colon: Dictionary,
	monde,
	catalogue_canaux: Dictionary,
	profils_saillance: Dictionary,
	catalogue_deformations: Dictionary,
	catalogue_actions: Dictionary,
	orientations: Dictionary,
	etats: Dictionary,
	config: Dictionary,
	delta: float,
) -> Dictionary:
	var r := decider(colon, monde, catalogue_canaux, profils_saillance, catalogue_deformations, catalogue_actions)
	var decision = r.decision
	var position_avant: Vector3 = colon.position
	var cible: Vector3 = colon.position
	var fuite := false
	var direction := Vector3.ZERO
	if decision != null:
		if orientations.get(decision.get("action", ""), "declencheur") == "fuite":
			fuite = true
			if EtatEffectif.valeur(colon, String(config.propriete_prob_fuite), etats) > 0.0:
				direction = Fuite.direction(
					colon.position,
					BancCommun.choses_a_fuir(r.visibles, colon, catalogue_actions, orientations, monde),
				)
				colon.position = BancCommun.bouger_selon(colon.position, direction, colon.proprietes.vitesse, delta)
		else:
			cible = decision.position
			colon.position = BancCommun.bouger_vers(colon.position, cible, colon.proprietes.vitesse, delta)
	return {
		"decision": decision, "resultats": r.resultats, "visibles": r.visibles,
		"perceptions": r.perceptions, "fuite": fuite, "direction": direction,
		"cible": cible, "position_avant": position_avant,
	}

# UN PAS COMPLET, pour tous les colons. ORDRE FIXE ET ASSUME :
#   ratio -> score -> charge -> bifurcation -> poids_verbes -> deformation ->
#   agir.
# La bifurcation lit la charge du MEME tick (jamais celle du precedent), et la
# deformation est posee AVANT que la saillance ne soit evaluee -- un colon qui
# bascule voit donc son ennemi amplifie des ce tick, sans un tick de retard
# invisible a l'oeil mais mesurable au test.
#
# Rend { ratio, ennemis, colons: [ { id, score, charge, sortie, franchi,
# precision, endurance, degats, prob_fuite, fuit, cible_id } ] } -- tout ce que
# le rendu et les traces affichent, jamais recalcule ailleurs.
static func avancer(
	colons: Array,
	objets: Array,
	monde,
	config: Dictionary,
	etats: Dictionary,
	catalogue_canaux: Dictionary,
	catalogue_deformations: Dictionary,
	profils_saillance: Dictionary,
	catalogue_actions: Dictionary,
	orientations: Dictionary,
	delta: float,
) -> Dictionary:
	var ratio := ratio_effectifs(objets, config)
	var ennemis := ennemis_de(objets, config)
	var etats_colons: Array = []
	for colon in colons:
		var score := score_menace(colon, ennemis, ratio, objets, config)
		Charge.avancer([colon], causes_de_menace(colon, score), delta)
		var sortie := relayer_bifurcation(colon, ratio, config, etats)
		poser_poids_verbes(colon, sortie, config)
		avancer_deformation(colon, sortie, config, catalogue_deformations, delta)
		var geste := agir_et_deplacer(
			colon, monde, catalogue_canaux, profils_saillance, catalogue_deformations,
			catalogue_actions, orientations, etats, config, delta,
		)
		etats_colons.append({
			"id": String(colon.id),
			"score": score,
			"charge": charge_stress(colon, config),
			"sortie": sortie,
			"franchi": stress_franchi(colon, config),
			"precision": EtatEffectif.valeur(colon, "precision", etats),
			"endurance": EtatEffectif.valeur(colon, "endurance", etats),
			"degats": EtatEffectif.valeur(colon, "degats", etats),
			"prob_fuite": EtatEffectif.valeur(colon, String(config.propriete_prob_fuite), etats),
			"fuit": geste.fuite,
			"direction": geste.direction,
			"cible_id": _identifiant_decision(geste.decision),
		})
	return {"ratio": ratio, "ennemis": ennemis.size(), "colons": etats_colons}

static func _identifiant_decision(decision) -> String:
	if decision == null:
		return ""
	var chose = decision.get("chose", null)
	if chose is Dictionary:
		return String(chose.get("id", ""))
	return ""

# ---- Textes (purs) ----

static func _ligne_palier(t: float, nb_ennemis: int, nb_allies: int) -> String:
	return "t=%.1fs PALIER : %d ennemi(s) contre %d allie(s)" % [t, nb_ennemis, nb_allies]

static func _ligne_bifurcation(t: float, etat_colon: Dictionary, ratio: float) -> String:
	if String(etat_colon.sortie) == SORTIE_AUCUNE:
		return "t=%.1fs %s : sortie RETIREE (charge=%.2f, score=%.2f, ratio=%.2f)" % [
			t, etat_colon.id, etat_colon.charge, etat_colon.score, ratio,
		]
	return "t=%.1fs %s BIFURQUE -> %s (charge=%.2f, score=%.2f, ratio=%.2f, precision=%.2f, endurance=%.2f, degats=%.2f, prob_fuite=%.2f)" % [
		t, etat_colon.id, etat_colon.sortie, etat_colon.charge, etat_colon.score, ratio,
		etat_colon.precision, etat_colon.endurance, etat_colon.degats, etat_colon.prob_fuite,
	]

static func _ligne_etat(t: float, etat_colon: Dictionary, ratio: float) -> String:
	return "t=%.1fs %s | score=%.2f charge=%.2f ratio=%.2f | sortie=%s | %s | cible=%s" % [
		t, etat_colon.id, etat_colon.score, etat_colon.charge, ratio,
		String(etat_colon.sortie) if String(etat_colon.sortie) != SORTIE_AUCUNE else "aucune",
		"FUIT" if etat_colon.fuit else "avance",
		String(etat_colon.cible_id) if String(etat_colon.cible_id) != "" else "(rien)",
	]

static func texte_colon(etat_colon: Dictionary, colon: Dictionary) -> String:
	var biais: Dictionary = colon.proprietes.get("biais_combat", {})
	var morceaux: Array = []
	for sortie in biais:
		morceaux.append("%s=%.1f" % [sortie, float(biais[sortie])])
	morceaux.sort()
	return "%s\nstress=%.2f\nbiais %s\nsortie=%s\nprecision=%.2f\nendurance=%.2f" % [
		colon.id, etat_colon.charge, " ".join(morceaux),
		String(etat_colon.sortie) if String(etat_colon.sortie) != SORTIE_AUCUNE else "aucune",
		etat_colon.precision, etat_colon.endurance,
	]

static func texte_compteur(resultat: Dictionary, nb_allies: int) -> String:
	var peur := 0
	var colere := 0
	for etat_colon in resultat.colons:
		if String(etat_colon.sortie) == "peur":
			peur += 1
		elif String(etat_colon.sortie) == "colere":
			colere += 1
	return "ennemis %d | allies %d | ratio %.2f | en peur %d | en colere %d  (clic : palier suivant)" % [
		resultat.ennemis, nb_allies, resultat.ratio, peur, colere,
	]

# ---- Rendu (impur, Node) -- aucune decision, seulement couleurs et positions.

func _reconstruire_monde() -> void:
	_monde = BancCommun.monde_depuis([
		{"choses": _colons, "type": "colon"},
		{"choses": _ennemis, "type": "ennemi"},
		{"choses": _ouvrages, "type": "ouvrage"},
		{"choses": _murs, "type": "mur"},
	])

func _couleur(cle: String, defaut: Array) -> Color:
	var rgb: Array = _config.get("couleurs", {}).get(cle, defaut)
	return Color(rgb[0], rgb[1], rgb[2])

func _creer_rendu() -> void:
	for chose in _ouvrages:
		_noeuds[chose.id] = _creer_carre(chose.position, TAILLE_OUVRAGE, _couleur("ouvrage", [0.55, 0.5, 0.45]))
	for chose in _murs:
		var mur := ColorRect.new()
		mur.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mur.size = TAILLE_MUR
		mur.color = _couleur("mur", [0.4, 0.4, 0.45])
		mur.position = Vector2(chose.position.x, chose.position.y) - mur.size / 2.0
		add_child(mur)
		_noeuds[chose.id] = mur
	_recreer_noeuds_ennemis()
	for colon in _colons:
		_noeuds[colon.id] = _creer_carre(colon.position, TAILLE_COLON, _couleur("colon_neutre", [0.35, 0.75, 0.4]))
		var origine := Vector2(colon.position.x, colon.position.y) - Vector2(LARGEUR_BARRE / 2.0, TAILLE_COLON)
		_fonds_barres[colon.id] = _creer_barre(_couleur("fond_barre", [0.15, 0.15, 0.15]), origine, LARGEUR_BARRE)
		_barres_stress[colon.id] = _creer_barre(_couleur("stress", [0.95, 0.55, 0.1]), origine, 0.0)
		var label := Label.new()
		label.add_theme_font_size_override("font_size", TAILLE_POLICE_LABEL)
		add_child(label)
		_labels[colon.id] = label
		var ligne := Line2D.new()
		ligne.width = LARGEUR_LIGNE
		add_child(ligne)
		_lignes[colon.id] = ligne

	_label_compteur = Label.new()
	_label_compteur.add_theme_font_size_override("font_size", TAILLE_POLICE_COMPTEUR)
	_label_compteur.position = Vector2(10.0, 10.0)
	_couche_ui.add_child(_label_compteur)

func _recreer_noeuds_ennemis() -> void:
	for decl in _config.get("ennemis", []):
		var id := String(decl.id)
		if _noeuds.has(id):
			_noeuds[id].queue_free()
			_noeuds.erase(id)
	for chose in _ennemis:
		_noeuds[chose.id] = _creer_carre(chose.position, TAILLE_ENNEMI, _couleur("ennemi", [0.05, 0.05, 0.05]))

func _creer_carre(position: Vector3, taille: float, couleur: Color) -> ColorRect:
	var carre := ColorRect.new()
	carre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	carre.size = Vector2(taille, taille)
	carre.color = couleur
	carre.position = Vector2(position.x, position.y) - carre.size / 2.0
	add_child(carre)
	return carre

func _creer_barre(couleur: Color, origine: Vector2, largeur: float) -> ColorRect:
	var barre := ColorRect.new()
	barre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	barre.color = couleur
	barre.position = origine
	barre.size = Vector2(largeur, HAUTEUR_BARRE)
	add_child(barre)
	return barre

func _rafraichir_tout() -> void:
	if _dernier_resultat.is_empty():
		return
	for etat_colon in _dernier_resultat.colons:
		var colon := _colon_par_id(String(etat_colon.id))
		if colon.is_empty():
			continue
		var noeud: ColorRect = _noeuds[colon.id]
		noeud.color = _couleur_sortie(String(etat_colon.sortie))
		noeud.position = Vector2(colon.position.x, colon.position.y) - noeud.size / 2.0
		var origine := Vector2(colon.position.x, colon.position.y) - Vector2(LARGEUR_BARRE / 2.0, TAILLE_COLON)
		_fonds_barres[colon.id].position = origine
		_barres_stress[colon.id].position = origine
		var maxi: float = float(_config.charge_max_affichee)
		_barres_stress[colon.id].size = Vector2(
			LARGEUR_BARRE * clamp(float(etat_colon.charge) / maxi, 0.0, 1.0), HAUTEUR_BARRE,
		)
		_labels[colon.id].position = origine + Vector2(0.0, TAILLE_COLON * 2.0)
		_labels[colon.id].text = texte_colon(etat_colon, colon)
		_tracer_ligne(colon, etat_colon)
	_label_compteur.text = texte_compteur(_dernier_resultat, _colons.size())

# UNE ligne par colon : vers sa cible quand il avance, dans la direction de
# fuite quand il fuit (la fuite n'a AUCUNE cible -- fuite.gd rend une direction,
# jamais une position, voir son en-tete), aucune quand il ne decide rien.
func _tracer_ligne(colon: Dictionary, etat_colon: Dictionary) -> void:
	var ligne: Line2D = _lignes[colon.id]
	var depart := Vector2(colon.position.x, colon.position.y)
	ligne.default_color = _couleur_sortie(String(etat_colon.sortie))
	if etat_colon.fuit:
		var direction: Vector3 = etat_colon.direction
		if direction == Vector3.ZERO:
			ligne.points = PackedVector2Array()
			return
		ligne.points = PackedVector2Array([
			depart, depart + Vector2(direction.x, direction.y).normalized() * LONGUEUR_LIGNE_FUITE,
		])
		return
	var cible_id := String(etat_colon.cible_id)
	if cible_id == "" or not _noeuds.has(cible_id):
		ligne.points = PackedVector2Array()
		return
	var wrapper = _monde.par_id(cible_id)
	if wrapper == null:
		ligne.points = PackedVector2Array()
		return
	var pos: Vector3 = wrapper.chose.position
	ligne.points = PackedVector2Array([depart, Vector2(pos.x, pos.y)])

func _couleur_sortie(sortie: String) -> Color:
	if sortie == "peur":
		return _couleur("colon_peur", [0.3, 0.5, 0.95])
	if sortie == "colere":
		return _couleur("colon_colere", [0.9, 0.2, 0.2])
	return _couleur("colon_neutre", [0.35, 0.75, 0.4])

func _colon_par_id(id: String) -> Dictionary:
	for colon in _colons:
		if String(colon.id) == id:
			return colon
	return {}

func _poser_camera() -> void:
	var decl: Dictionary = _config.get("camera", {})
	var pos: Array = decl.get("position", [0.0, 0.0, 0.0])
	var camera := Camera2D.new()
	camera.position = Vector2(pos[0], pos[1])
	camera.zoom = Vector2(decl.get("zoom", 1.0), decl.get("zoom", 1.0))
	camera.enabled = true
	add_child(camera)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
