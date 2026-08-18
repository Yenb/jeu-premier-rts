extends Node2D

# Cablage de banc VISUEL, separe des autres bancs (Scene/banc_reproduction.tscn,
# PAS la scene principale -- run/main_scene reste banc_p1). Existe pour VOIR
# le cycle de reproduction complet -- stade.gd -> accouplement.gd ->
# gestation.gd -> heredite.gd -> Objet.fabriquer -- tourner ENSEMBLE, de bout
# en bout, pour la PREMIERE FOIS (aucun banc anterieur ne cable ce cycle,
# voir data/heredite.json:_note). JETABLE PAR DEFINITION.
#
# CE QUE CE BANC MONTRE : deux colons adjacents et immobiles, parent_a
# (rouge) et parent_b (bleu), demarrent a age 0.0 (stade "nouveau_ne", pose
# par stade.gd des le premier tick). Ils vieillissent -- Senescence.avancer
# (annees_par_seconde 2.0, data/banc_reproduction.json) fait monter
# proprietes.age, Stade.avancer les fait progresser dans
# data/types.json:colon.stades_config (nouveau_ne -> enfant -> adolescent ->
# adulte a 18 ans, 9 secondes reelles). Un print signale CHAQUE changement de
# stade, pour les deux colons ET pour l'enfant une fois ne -- preuve
# qu'aucun n'est special-case. Une fois les deux "adulte"
# (stades_fertiles), accouplement.gd accumule leur exposition mutuelle
# (deja proches, AUCUN deplacement dans ce banc -- perception seule, patron
# banc_convergence_attache.gd/banc_vecu_inter_colon.gd : "processus passif,
# hors pipeline de decision", ni jugement.gd ni agir.gd ne sont jamais
# cables ici) jusqu'au seuil REEL (data/reproduction.json:colon, 20
# secondes) -- print au franchissement.
#
# UN SEUL DES DEUX GESTE, ET C'EST LA DONNEE QUI LE DIT : parent_a declare
# role_gestation "porteur", parent_b "non_porteur"
# (data/banc_reproduction.json). accouplement.gd traite les deux et n'ecrit
# l'etat que sur le premier. Ce fichier ne designe donc personne :
# avancer_cycle fait avancer la gestation de TOUT colon qui en porte une, et
# il n'y en a qu'une. Ce n'est pas un concept de sexe -- une espece
# hermaphrodite declarerait "les_deux" des deux cotes et pondrait deux fois,
# sans une ligne de ce fichier a changer. parent_b reste de fait
# indisponible pour tout accouplement futur : la garde d'accouplement.gd
# ignore un partenaire percu qui porte deja "gestation".
#
# Au franchissement de naissance_prete (data/reproduction.json:colon.
# duree_gestation, 30 secondes REELLES) : Heredite.fabriquer_genes_enfant
# (RNG seede, catalogue REEL data/heredite.json:defaut) produit le kit
# genetique de l'enfant depuis les genes de parent_a et la copie figee des
# genes de parent_b (gestation.partenaire_genes_etat) ; BancCommun.
# fabriquer_colon + Objet.fabriquer construisent l'enfant (meme type
# "colon", position a cote de parent_a, genes_actifs copies de parent_a) ;
# ExpressionGenetique.exprimer + .appliquer traduisent son genes_etat
# herite en vitesse effective -- print des allees des DEUX parents et de
# l'enfant. proprietes.gestation est ENSUITE retire de parent_a
# (gestation.gd/heredite.gd ne le font jamais eux-memes, voir leurs
# en-tetes -- c'est le role de l'appelant).
#
# GENE UNIQUE, `vivacite` (data/banc_reproduction.json:catalogue_genes,
# LOCAL -- meme discipline que data/banc_genetique.json : une regle de banc
# de demonstration ne rejoint data/genes.json que si un second banc en a
# besoin), UNE SEULE cible (vitesse, poids 40.0, additif) -- parent_a
# allees [1,1] (vitesse 230.0), parent_b allees [-1,-1] (vitesse 70.0),
# tous deux HOMOZYGOTES : l'enfant nait TOUJOURS a la vitesse de BASE du
# type colon (150.0), exactement entre ses deux parents, avant l'effet
# (rare, non borne) d'une mutation.
#
# CANAUX SEULS, AUCUN JUGEMENT NI AGIR : ce banc ne charge que
# data/types.json (paquets + colon), data/canaux.json (Perception.percevoir),
# data/reproduction.json (REEL, accouplement.gd/gestation.gd) et
# data/heredite.json (REEL, heredite.gd) -- ni menaces.json, ni
# profils_saillance.json, ni types_choses.json, ni orientations.json, ni
# transformations.json : aucune decision n'est jamais resolue ici, les deux
# colons restent immobiles pour toute la duree de l'observation.
#
# CATALOGUES EPIGENETIQUE/SENESCENCE VIDES A ExpressionGenetique.exprimer
# (meme geste que banc_genetique.gd) : aucun colon de ce banc ne pose
# jamais de marque epigenetique (proprietes.marques_epigenetiques reste
# {} pour tous), et data/senescence.json ne porte qu'une entree HORS
# DOMAINE (declin_gravitique, cible champ_gravitique.intensite, age_debut
# 40.0) qui ALARMERAIT (expression.gd:_ecrire_chemin, segment
# 'champ_gravitique' absent) des qu'un colon depasse 40 ans simules --
# aucun colon de ce depot ne porte cette structure. Passer {} evite ce
# risque sans jamais deviner un defaut : ce chantier ne fait la preuve
# d'aucune courbe de senescence sur les proprietes, seulement de
# l'AVANCEMENT de l'age (senescence.gd) et du STADE (stade.gd).
# Heredite.fabriquer_genes_enfant recoit lui aussi un catalogue_epigenetique
# vide : aucun parent de ce banc ne porte jamais de marque, le parametre
# n'est jamais consulte (voir heredite.gd : union des cles de
# marques_epigenetiques des deux parents, toujours vide ici).
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge data/banc_reproduction.json + les
#   catalogues partages reels (types.json, canaux.json, reproduction.json,
#   heredite.json), fabrique les deux colons, pose la Camera2D. _process
#   appelle avancer_cycle (statique, pure) puis gere l'evenementiel
#   (changement de stade, franchissement d'accouplement, progression de
#   gestation, naissance) et le rendu.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_reproduction.gd) : _fabriquer_colon_reproduction, avancer_cycle,
#   naissance_prete, fabriquer_enfant.

const Objet = preload("res://scripts/objet.gd")
const Monde = preload("res://scripts/monde.gd")
const Perception = preload("res://scripts/perception.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")
const Senescence = preload("res://scripts/senescence.gd")
const Stade = preload("res://scripts/stade.gd")
const Accouplement = preload("res://scripts/accouplement.gd")
const Gestation = preload("res://scripts/gestation.gd")
const Heredite = preload("res://scripts/heredite.gd")
const ExpressionGenetique = preload("res://scripts/expression.gd")

const ID_PORTEUR := "parent_a"
const TAILLE_CARRE_COLON := 24.0
const TAILLE_CARRE_ENFANT := 14.0

var _donnees: Dictionary = {}
var _catalogue_types: Dictionary = {}
var _catalogue_canaux: Dictionary = {}
var _catalogue_reproduction: Dictionary = {}
var _catalogue_heredite: Dictionary = {}
var _catalogue_genes: Dictionary = {}
var _couleurs_colons: Dictionary = {}
var _couleur_enfant := Color.WHITE
var _annees_par_seconde := 1.0
var _intervalle_print_age := 5.0
var _intervalle_print_gestation := 5.0
var _offset_enfant := Vector3.ZERO
var _rng := RandomNumberGenerator.new()

var _monde := Monde.new()
var _colons: Array = []
var _porteur: Dictionary = {}
var _noeuds: Dictionary = {}
var _stades_precedents: Dictionary = {}

var _temps_ecoule := 0.0
var _tick_actuel := 0
var _compteur_enfant := 0
var _prochain_print_age := 0.0
var _prochain_print_gestation := 0.0
var _accouplement_annonce := false
var _naissance_annoncee := false

func _ready() -> void:
	_donnees = _charger_json("res://data/banc_reproduction.json")
	_couleurs_colons = _donnees.get("couleurs_colons", {})
	var rgb_enfant: Array = _donnees.get("couleur_enfant", [1.0, 1.0, 1.0])
	_couleur_enfant = Color(rgb_enfant[0], rgb_enfant[1], rgb_enfant[2])
	_annees_par_seconde = _donnees.get("annees_par_seconde", 1.0)
	_intervalle_print_age = _donnees.get("intervalle_print_age", 5.0)
	_intervalle_print_gestation = _donnees.get("intervalle_print_gestation", 5.0)
	var off: Array = _donnees.get("offset_enfant", [20.0, -30.0, 0.0])
	_offset_enfant = Vector3(off[0], off[1], off[2])
	_catalogue_genes = _donnees.get("catalogue_genes", {})
	_rng.seed = int(_donnees.get("seed", 0))

	_catalogue_types = {}
	var types_partages := _charger_json("res://data/types.json")
	_catalogue_types["objet_physique"] = types_partages.get("objet_physique", {})
	_catalogue_types["dynamique"] = types_partages.get("dynamique", {})
	_catalogue_types["percevant"] = types_partages.get("percevant", {})
	_catalogue_types["agent"] = types_partages.get("agent", {})
	_catalogue_types["colon"] = types_partages.get("colon", {})

	_catalogue_canaux = _charger_json("res://data/canaux.json")
	_catalogue_reproduction = _charger_json("res://data/reproduction.json")
	_catalogue_heredite = _charger_json("res://data/heredite.json")

	var declarations: Dictionary = _donnees.get("colons", {})
	for nom in declarations:
		_ajouter_colon(nom, declarations[nom])
	_porteur = _colon_par_id(ID_PORTEUR)

	_poser_camera()

func _ajouter_colon(nom: String, decl: Dictionary) -> void:
	var colon := _fabriquer_colon_reproduction(nom, decl, _catalogue_types, _catalogue_genes)
	_monde.ajouter(colon, "colon", colon.position)
	_colons.append(colon)
	_stades_precedents[colon.id] = colon.proprietes.get("stade", "")
	_noeuds[colon.id] = _dessiner_carre(colon.position, _couleur_colon(nom), TAILLE_CARRE_COLON)

func _colon_par_id(id: String) -> Dictionary:
	for colon in _colons:
		if colon.id == id:
			return colon
	return {}

# Fabrication PURE (testable headless) : composition de paquets
# (BancCommun.fabriquer_colon) -> surcharge TOTALE de genes_actifs/
# genes_etat (patron de remplacement, meme discipline que
# banc_genetique.gd:_fabriquer_colon_genetique) -> ExpressionGenetique.
# exprimer + .appliquer pour que la vitesse effective reflete le gene des
# la fabrication.
static func _fabriquer_colon_reproduction(nom: String, decl: Dictionary, catalogue_types: Dictionary, catalogue_genes: Dictionary) -> Dictionary:
	var colon := BancCommun.fabriquer_colon(nom, "colon", decl, catalogue_types)
	colon.proprietes["genes_actifs"] = decl.get("genes_actifs", [])
	colon.proprietes["genes_etat"] = decl.get("genes_etat", {})
	# QUI PORTE vient de la donnee, plus d'une convention de ce fichier : le
	# type colon nait "non_porteur", chaque colon declare le sien.
	colon.proprietes["role_gestation"] = decl.get("role_gestation", colon.proprietes.get("role_gestation", ""))
	var valeurs := ExpressionGenetique.exprimer(colon, catalogue_genes, {}, {})
	ExpressionGenetique.appliquer(colon, valeurs)
	return colon

# UN APPEL PAR MECANISME PAR TICK, dans l'ordre decide (Senescence -> Stade
# -> Accouplement -> Gestation) -- structure par MECANISME (une boucle sur
# tous les colons par mecanisme) plutot que par COLON, pour que l'ordre des
# quatre reste un fait local et visible ICI, jamais reparti sur plusieurs
# boucles. Gestation.avancer tourne sur TOUT colon qui porte une gestation :
# aucun porteur n'est designe ici, c'est role_gestation qui a deja tranche
# en amont. PURE et testable : mute colons en place, ne dessine rien, ne lit
# aucun fichier.
static func avancer_cycle(
	colons: Array,
	monde,
	catalogue_canaux: Dictionary,
	catalogue_reproduction: Dictionary,
	delta: float,
	tick_actuel: int,
	annees_par_seconde: float,
) -> void:
	for colon in colons:
		Senescence.avancer(colon, delta, annees_par_seconde)
		Stade.avancer(colon)
	for colon in colons:
		var perceptions := Perception.percevoir(colon, monde, catalogue_canaux)
		Accouplement.avancer(colon, perceptions, catalogue_reproduction, delta, tick_actuel)
	for colon in colons:
		if colon.proprietes.has("gestation"):
			Gestation.avancer(colon, catalogue_reproduction, delta)

static func naissance_prete(porteur: Dictionary) -> bool:
	return porteur.proprietes.has("gestation") and porteur.proprietes.gestation.get("naissance_prete", false)

# Fabrique l'enfant depuis le kit genetique rendu par heredite.gd -- meme
# sequence que _fabriquer_colon_reproduction (composition de paquets ->
# surcharge genes -> expression), sauf que les genes viennent du kit
# herite, jamais d'une declaration de data/banc_reproduction.json.
# genes_actifs copie de PORTEUR (heredite.gd ne le produit jamais, voir son
# en-tete : "c'est le TYPE qui le porte pour l'enfant").
static func fabriquer_enfant(
	id: String,
	porteur: Dictionary,
	position: Vector3,
	catalogue_types: Dictionary,
	catalogue_genes: Dictionary,
	catalogue_heredite: Dictionary,
	rng: RandomNumberGenerator,
) -> Dictionary:
	var kit := Heredite.fabriquer_genes_enfant(porteur, catalogue_heredite, {}, rng)
	var decl := {"position": [position.x, position.y, position.z], "attaches": [], "forme": {}, "poids_verbes": {}}
	var enfant := BancCommun.fabriquer_colon(id, "colon", decl, catalogue_types)
	enfant.proprietes["genes_actifs"] = porteur.proprietes.get("genes_actifs", []).duplicate()
	enfant.proprietes["genes_etat"] = kit.genes_etat
	enfant.proprietes["marques_epigenetiques"] = kit.marques_epigenetiques
	var valeurs := ExpressionGenetique.exprimer(enfant, catalogue_genes, {}, {})
	ExpressionGenetique.appliquer(enfant, valeurs)
	return enfant

func _poser_camera() -> void:
	var centre := Vector2.ZERO
	for colon in _colons:
		centre += Vector2(colon.position.x, colon.position.y)
	if _colons.size() > 0:
		centre /= _colons.size()
	var camera := Camera2D.new()
	camera.position = centre
	camera.enabled = true
	add_child(camera)

func _process(delta: float) -> void:
	_temps_ecoule += delta
	_tick_actuel += 1

	avancer_cycle(_colons, _monde, _catalogue_canaux, _catalogue_reproduction, delta, _tick_actuel, _annees_par_seconde)

	for colon in _colons:
		_verifier_changement_stade(colon)
	_verifier_accouplement()
	if _porteur.proprietes.has("gestation"):
		_verifier_progression_gestation()
		if naissance_prete(_porteur) and not _naissance_annoncee:
			_accoucher()

	if _temps_ecoule >= _prochain_print_age:
		_imprimer_ages()
		_prochain_print_age += _intervalle_print_age

# Imprime UNE FOIS par changement, jamais par tick (meme discipline que
# tous les autres bancs) -- generique par colon, l'enfant y passe comme les
# deux parents des qu'il existe (aucun cas special).
func _verifier_changement_stade(colon: Dictionary) -> void:
	var precedent: String = _stades_precedents.get(colon.id, "")
	var courant: String = colon.proprietes.get("stade", "")
	if courant != precedent:
		print("t=%.1f %s : stade -> %s (age %.2f)" % [_temps_ecoule, colon.id, courant, colon.proprietes.age])
		_stades_precedents[colon.id] = courant

func _verifier_accouplement() -> void:
	if not _accouplement_annonce and _porteur.proprietes.has("gestation"):
		_accouplement_annonce = true
		print("t=%.1f accouplement : seuil franchi avec %s, gestation posee sur %s (le seul porteur declare)" % [
			_temps_ecoule, _porteur.proprietes.gestation.partenaire_id, _porteur.id,
		])

func _verifier_progression_gestation() -> void:
	if _temps_ecoule < _prochain_print_gestation:
		return
	_prochain_print_gestation = _temps_ecoule + _intervalle_print_gestation
	var gestation: Dictionary = _porteur.proprietes.gestation
	var ecoulee: float = gestation.get("duree_gestation_ecoulee", 0.0)
	var ref: String = _porteur.proprietes.reproduction_ref
	var duree: float = _catalogue_reproduction.get(ref, {}).get("duree_gestation", 0.0)
	print("t=%.1f gestation : %.1f / %.1f" % [_temps_ecoule, ecoulee, duree])

func _accoucher() -> void:
	_naissance_annoncee = true
	_compteur_enfant += 1
	var id := "enfant_%d" % _compteur_enfant
	var position: Vector3 = _porteur.position + _offset_enfant
	var enfant := fabriquer_enfant(id, _porteur, position, _catalogue_types, _catalogue_genes, _catalogue_heredite, _rng)

	_monde.ajouter(enfant, "colon", enfant.position)
	_colons.append(enfant)
	_stades_precedents[enfant.id] = enfant.proprietes.get("stade", "")
	_noeuds[enfant.id] = _dessiner_carre(enfant.position, _couleur_enfant, TAILLE_CARRE_ENFANT)

	_imprimer_naissance(enfant)
	cloturer_gestation(_porteur, _colons)

# CLOTURER, JAMAIS SEULEMENT RETIRER LA GESTATION : accouplement.gd n'a aucune
# decroissance, l'accumulateur des deux parents reste au-dessus du seuil pour
# toujours (voir son en-tete). Le retirer d'un seul cote suffit a ce que le
# partenaire repose une gestation au tick suivant, en silence, et le couple
# ponde en rafale.
static func cloturer_gestation(porteur: Dictionary, colons: Array) -> void:
	var partenaire_id := String(porteur.proprietes.get("gestation", {}).get("partenaire_id", ""))
	porteur.proprietes.erase("gestation")
	porteur.proprietes.erase("accouplement_accumulateur")
	for colon in colons:
		if String(colon.id) == partenaire_id:
			colon.proprietes.erase("accouplement_accumulateur")

# Generique sur genes_actifs -- ne nomme jamais "vivacite" en dur, lit les
# allees des DEUX parents (porteur direct, partenaire via la copie figee
# dans gestation.partenaire_genes_etat, jamais son etat vivant) et de
# l'enfant.
func _imprimer_naissance(enfant: Dictionary) -> void:
	print("t=%.1f naissance : %s" % [_temps_ecoule, enfant.id])
	var partenaire_id: String = _porteur.proprietes.gestation.partenaire_id
	var partenaire_genes: Dictionary = _porteur.proprietes.gestation.get("partenaire_genes_etat", {})
	for nom_gene in _porteur.proprietes.get("genes_actifs", []):
		var alleles_porteur: Array = _porteur.proprietes.genes_etat.get(nom_gene, {}).get("alleles", [])
		var alleles_partenaire: Array = partenaire_genes.get(nom_gene, {}).get("alleles", [])
		var alleles_enfant: Array = enfant.proprietes.genes_etat.get(nom_gene, {}).get("alleles", [])
		print("  gene %s : %s %s, %s %s -> %s %s" % [
			nom_gene, _porteur.id, alleles_porteur, partenaire_id, alleles_partenaire, enfant.id, alleles_enfant,
		])
	var partenaire: Dictionary = _colon_par_id(partenaire_id)
	print("  vitesse : %s %.1f, %s %.1f -> %s %.1f" % [
		_porteur.id, _porteur.proprietes.vitesse, partenaire_id, partenaire.proprietes.vitesse, enfant.id, enfant.proprietes.vitesse,
	])

func _imprimer_ages() -> void:
	for colon in _colons:
		print("t=%.1f %s : age %.2f (stade %s)" % [_temps_ecoule, colon.id, colon.proprietes.age, colon.proprietes.get("stade", "")])

func _couleur_colon(nom: String) -> Color:
	var rgb: Array = _couleurs_colons.get(nom, [1.0, 1.0, 1.0])
	return Color(rgb[0], rgb[1], rgb[2])

func _dessiner_carre(position3: Vector3, couleur: Color, taille: float) -> ColorRect:
	var carre := ColorRect.new()
	carre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	carre.size = Vector2(taille, taille)
	carre.color = couleur
	carre.position = Vector2(position3.x, position3.y) - carre.size / 2.0
	add_child(carre)
	return carre

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
