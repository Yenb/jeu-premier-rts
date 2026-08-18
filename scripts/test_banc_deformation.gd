extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_deformation.gd
#
# Verrouille le cablage de banc_deformation.gd (PHASE 4 piece 2, chantier
# "L'entite comme agent complet", voir docs/cadrage_phase4_deformation.md) :
# deux colons REELS (Objet.fabriquer contre data/types.json lu sur disque),
# identiques a leur naissance -- seule leur POSITION differe -- divergent
# OBSERVABLEMENT sur proprietes.deformation_etat.habituation.brule selon
# qu'ils percoivent ou non, tick apres tick, une chose portant "brule".
#
# percoit_declencheur/avancer_colon (banc_deformation.gd) sont exerces sur
# le CHEMIN REEL : data/types.json (colon.deformation_etat.habituation.brule
# preinitialise a zero, colon.deformation_sources = ["habituation"] --
# forme A depuis le chantier "un seul patron de reference de catalogue"),
# data/canaux.json (catalogue_canaux reel),
# data/deformations.json (catalogue_deformations reel, entree
# "habituation"). Ce fichier n'invoque ni attaches.gd, ni proximite.gd, ni
# jugement.gd, ni agir.gd -- hors perimetre de PHASE 4 piece 2 (voir
# cadrage : la lecture de biais() par une couche de saillance est piece 3).

const BancDeformation = preload("res://scripts/banc_deformation.gd")
const Deformation = preload("res://scripts/deformation.gd")
const Objet = preload("res://scripts/objet.gd")
const Monde = preload("res://scripts/monde.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

const DECLENCHEUR := "brule"
const SOURCE := "habituation"
const CIBLE := "brule"
const MAGNITUDE := 0.01
const DELTA_TICK := 0.1
const TICKS := 50

func _init() -> void:
	_divergence_reelle_entre_expose_et_isole()
	_resumabilite_json_stricte_du_colon_expose()
	_couleur_de_lit_le_type_pose_jamais_le_defaut()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: deux colons reels identiques a la naissance divergent sur " +
		"deformation_etat.habituation.brule selon exposition reelle a une source " +
		"brule (Perception.percevoir), biais strictement positif pour " +
		"l'expose et exactement nul pour l'isole, resumabilite JSON stricte")
	quit(0)

func _types_reels() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/types.json"))

func _catalogue_canaux_reel() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/canaux.json"))

func _catalogue_deformations_reel() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/deformations.json"))

# Colon REEL, fabrique directement contre data/types.json -- herite
# deformation_etat.habituation.brule = { rapide: 0.0, lent: 0.0 } sans
# aucune surcharge de banc (ni forme ni poids_verbes n'entrent en jeu ici :
# ce banc n'appelle jamais agir.gd).
func _colon_reel(id: String, position: Vector3) -> Dictionary:
	return Objet.fabriquer(id, "colon", position, _types_reels())

# "feu" local minimal (brule seul), meme convention que banc_deformation.gd
# et que data/banc_deformation.json -- pas le type partage data/types.json:feu.
func _monde_avec_feu(position_feu: Vector3) -> Monde:
	var monde := Monde.new()
	var feu := Objet.fabriquer("feu_0", "feu", position_feu, {"feu": {"brule": true}})
	monde.ajouter(feu, "feu", position_feu)
	return monde

func _divergence_reelle_entre_expose_et_isole() -> void:
	var canaux := _catalogue_canaux_reel()
	var deformations := _catalogue_deformations_reel()

	var position_feu := Vector3.ZERO
	# expose : 20 unites du feu, tres largement a portee de vue (1600.0,
	# data/types.json:colon.canaux_config.vue.portee). isole : 5000 unites, tres
	# largement HORS de cette meme portee -- aucun recouvrement possible.
	var expose := _colon_reel("expose", Vector3(20.0, 0.0, 0.0))
	var isole := _colon_reel("isole", Vector3(5000.0, 0.0, 0.0))

	verif.v(expose.proprietes.deformation_etat.habituation.brule.rapide == 0.0,
		"un colon reel doit heriter deformation_etat.habituation.brule.rapide a 0.0 avant toute exposition")
	verif.v(expose.proprietes.deformation_etat.habituation.brule.lent == 0.0,
		"un colon reel doit heriter deformation_etat.habituation.brule.lent a 0.0 avant toute exposition")
	verif.v(isole.proprietes.deformation_etat.habituation.brule.rapide == 0.0,
		"l'isole doit heriter le meme point de depart, rapide a 0.0")
	verif.v(isole.proprietes.deformation_etat.habituation.brule.lent == 0.0,
		"l'isole doit heriter le meme point de depart, lent a 0.0")

	var monde_expose := _monde_avec_feu(position_feu)
	monde_expose.ajouter(expose, "colon", expose.position)
	var monde_isole := _monde_avec_feu(position_feu)
	monde_isole.ajouter(isole, "colon", isole.position)

	for i in TICKS:
		BancDeformation.avancer_colon(
			expose, monde_expose, canaux, deformations,
			DECLENCHEUR, SOURCE, CIBLE, MAGNITUDE, DELTA_TICK,
		)
		BancDeformation.avancer_colon(
			isole, monde_isole, canaux, deformations,
			DECLENCHEUR, SOURCE, CIBLE, MAGNITUDE, DELTA_TICK,
		)

	var canal_expose: Dictionary = expose.proprietes.deformation_etat.habituation.brule
	var canal_isole: Dictionary = isole.proprietes.deformation_etat.habituation.brule

	verif.v(canal_expose.rapide > 0.0,
		"apres %d ticks a portee de vue d'une source brule, le registre rapide de l'expose doit etre strictement positif" % TICKS)
	verif.v(canal_expose.lent > 0.0,
		"apres %d ticks a portee de vue d'une source brule, le registre lent de l'expose doit etre strictement positif" % TICKS)
	verif.v(canal_isole.rapide == 0.0,
		"un colon jamais expose a une source brule doit garder son registre rapide a exactement 0.0")
	verif.v(canal_isole.lent == 0.0,
		"un colon jamais expose a une source brule doit garder son registre lent a exactement 0.0")

	var biais_expose := Deformation.biais(expose, SOURCE, CIBLE, deformations)
	var biais_isole := Deformation.biais(isole, SOURCE, CIBLE, deformations)
	verif.v(biais_expose > 0.0, "le biais de l'expose doit etre strictement positif apres exposition reelle")
	verif.v(biais_isole == 0.0, "le biais de l'isole doit rester exactement 0.0, jamais approche")

func _resumabilite_json_stricte_du_colon_expose() -> void:
	var canaux := _catalogue_canaux_reel()
	var deformations := _catalogue_deformations_reel()
	var expose := _colon_reel("expose_resumable", Vector3(20.0, 0.0, 0.0))
	var monde := _monde_avec_feu(Vector3.ZERO)
	monde.ajouter(expose, "colon", expose.position)

	for i in 10:
		BancDeformation.avancer_colon(
			expose, monde, canaux, deformations,
			DECLENCHEUR, SOURCE, CIBLE, MAGNITUDE, DELTA_TICK,
		)

	var texte := JSON.stringify(expose.proprietes.deformation_etat)
	var relu: Variant = JSON.parse_string(texte)
	verif.v(relu != null, "JSON.stringify puis parse_string doit reussir sans erreur sur proprietes.deformation_etat")
	var canal_original: Dictionary = expose.proprietes.deformation_etat.habituation.brule
	var canal_relu: Dictionary = relu.habituation.brule
	verif.v(is_equal_approx(canal_relu.rapide, canal_original.rapide),
		"le registre rapide doit survivre identique a l'aller-retour JSON")
	verif.v(is_equal_approx(canal_relu.lent, canal_original.lent),
		"le registre lent doit survivre identique a l'aller-retour JSON")

# Audit couverture 2026-08-06 : _couleur_de est une fonction INSTANCE,
# aucune appelee par un test avant cette session. Meme patron que les
# autres bancs : BancDeformation.new() nu, jamais ajoute a l'arbre.
func _couleur_de_lit_le_type_pose_jamais_le_defaut() -> void:
	var b := BancDeformation.new()
	b._couleurs_types = {"colon": [0.9, 0.2, 0.1], "feu": [0.1, 0.6, 0.9]}
	verif.v(b._couleur_de("colon") == Color(0.9, 0.2, 0.1), "doit rendre la couleur posee pour 'colon', pas le defaut blanc")
	verif.v(b._couleur_de("feu") == Color(0.1, 0.6, 0.9), "doit distinguer deux types poses")
	verif.v(b._couleur_de("inconnu") == Color(1.0, 1.0, 1.0), "un type absent doit rendre le blanc par defaut, jamais alarmer")
