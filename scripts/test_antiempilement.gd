extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_antiempilement.gd
#
# Verrouille la PONDERATION PAR AVANCEMENT de proximite.gd
# (travail_restant/travail_initial) : un chantier presque fini pese moins
# qu'un chantier frais -- pas d'exception codee, pas de comptage d'agents.
# REMPLACE l'ancien mecanisme "facteur_occupation" (comptage d'agents a
# portee/en route + auto-exclusion du colon, retire de proximite.gd --
# voir CARTE.md §6) : celui-la oscillait, parce que la saillance changeait
# selon ce qu'un colon DECIDAIT. Celui-ci ne peut PAS osciller : rien ici
# ne lit de decision de colon, seulement deux nombres deja sur la chose --
# travail_restant ne bouge que quand un agent TRAVAILLE (extinction.gd),
# jamais parce qu'un colon REGARDE (Proximite.evaluer ne mute rien).
#
# _le_modele_ignore_le_domaine() verrouille que proximite.gd ne connait
# aucun nom de domaine : un chantier invente, sans rapport avec le feu,
# traverse le meme code.

const Proximite = preload("res://scripts/proximite.gd")
const BancP1 = preload("res://scripts/banc_p1.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

# Catalogue de canaux local (equivalent a data/canaux.json) : le colon ne
# porte que "vue" (aucun "angle" -- degenere en sphere, meme comportement
# que l'ancienne portee unique du colon, voir scripts/perception.gd).
const CATALOGUE_CANAUX := {
	"vue": { "geometrie": "cone_oriente" },
}

func _init() -> void:
	_feu_frais_saillance_pleine(verif)
	_feu_presque_eteint_saillance_quasi_nulle(verif)
	_chose_sans_chantier_saillance_inchangee(verif)
	_travail_initial_nul_ou_absent_traite_comme_neutre(verif)
	_le_modele_ignore_le_domaine(verif)
	_deux_feux_colon_va_au_frais(verif)
	_un_seul_feu_presque_eteint_colon_y_va_quand_meme(verif)
	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: la saillance d'un chantier est ponderee par son avancement " +
		"(travail_restant/travail_initial), sans comptage d'agents ni possibilite d'osciller")
	quit(0)

func _perception(id: String, pos: Vector3, distance: float, proprietes: Dictionary) -> Dictionary:
	return {
		"chose": {"id": id, "position": pos, "proprietes": proprietes},
		"type": "chose",
		"position": pos,
		"distance": distance,
	}

const CATALOGUE := {
	"chantier": {"saillance_intrinseque": 3.0, "portee_saillance": 900.0},
}

# Un chantier FRAIS (travail_restant == travail_initial) doit peser EXACTEMENT
# comme une chose saillante sans aucun chantier -- l'avancement complet (1.0)
# est l'identite multiplicative, jamais un bonus ni une penalite.
func _feu_frais_saillance_pleine(v) -> void:
	var colon := {"proprietes": {}}
	var proprietes_chantier := {"profil_saillance": "chantier", "travail_restant": 3.0, "travail_initial": 3.0}
	var proprietes_sans := {"profil_saillance": "chantier"}
	var frais := Proximite.evaluer([_perception("frais", Vector3(100, 0, 0), 100.0, proprietes_chantier)], colon, CATALOGUE, {})
	var sans := Proximite.evaluer([_perception("sans", Vector3(100, 0, 0), 100.0, proprietes_sans)], colon, CATALOGUE, {})
	v.v(frais.size() == 1 and sans.size() == 1, "les deux choses doivent rester saillantes")
	if frais.size() == 1 and sans.size() == 1:
		v.v(is_equal_approx(frais[0].saillance, sans[0].saillance),
			"un chantier frais doit peser exactement comme une chose sans chantier")

# Un chantier PRESQUE FINI (travail_restant proche de 0) doit peser presque
# rien -- le rapport doit etre exact, pas juste "plus petit".
func _feu_presque_eteint_saillance_quasi_nulle(v) -> void:
	var colon := {"proprietes": {}}
	var proprietes := {"profil_saillance": "chantier", "travail_restant": 0.1, "travail_initial": 3.0}
	var resultats := Proximite.evaluer([_perception("presque_fini", Vector3(100, 0, 0), 100.0, proprietes)], colon, CATALOGUE, {})
	v.v(resultats.size() == 1, "un chantier presque fini doit rester saillant, jamais exclu")
	if resultats.size() == 1:
		var brute: float = 3.0 * (1.0 - 100.0 / 900.0)
		var attendu: float = brute * (0.1 / 3.0)
		v.v(is_equal_approx(resultats[0].saillance, attendu),
			"la ponderation doit suivre exactement (travail_restant / travail_initial)")
		v.v(resultats[0].saillance < brute * 0.1, "un chantier presque fini doit peser quasi rien face au meme chantier frais")

# Une chose SANS "travail_restant" du tout (pas un chantier -- un arbre, une
# menace) garde sa saillance inchangee, jamais une alarme : ce n'est pas une
# reference de catalogue a resoudre, juste deux nombres facultatifs.
func _chose_sans_chantier_saillance_inchangee(v) -> void:
	var colon := {"proprietes": {}}
	var proprietes := {"profil_saillance": "chantier"}
	var resultats := Proximite.evaluer([_perception("ordinaire", Vector3(100, 0, 0), 100.0, proprietes)], colon, CATALOGUE, {})
	v.v(resultats.size() == 1, "une chose sans chantier doit rester saillante normalement")
	if resultats.size() == 1:
		var brute: float = 3.0 * (1.0 - 100.0 / 900.0)
		v.v(is_equal_approx(resultats[0].saillance, brute), "sans travail_restant, la saillance ne doit jamais changer")

# CAS DU COUPLE, sens inverse de la doctrine habituelle : ici c'est
# l'ABSENCE totale de ponderation qui est le point neutre, donc
# travail_initial absent OU <= 0.0 (jamais une reference a resoudre, jamais
# une division par zero) retombe sur 1.0, sans alarme -- pas un defaut
# silencieux dangereux, l'inverse : le seul defaut qui ne PEUT rien casser.
func _travail_initial_nul_ou_absent_traite_comme_neutre(v) -> void:
	var colon := {"proprietes": {}}
	var brute: float = 3.0 * (1.0 - 100.0 / 900.0)
	var sans_initial := Proximite.evaluer(
		[_perception("sans_initial", Vector3(100, 0, 0), 100.0, {"profil_saillance": "chantier", "travail_restant": 1.0})],
		colon, CATALOGUE, {},
	)
	var initial_nul := Proximite.evaluer(
		[_perception("initial_nul", Vector3(100, 0, 0), 100.0, {"profil_saillance": "chantier", "travail_restant": 1.0, "travail_initial": 0.0})],
		colon, CATALOGUE, {},
	)
	v.v(sans_initial.size() == 1 and initial_nul.size() == 1, "les deux doivent rester saillantes")
	if sans_initial.size() == 1 and initial_nul.size() == 1:
		v.v(is_equal_approx(sans_initial[0].saillance, brute), "travail_initial absent -- aucune ponderation")
		v.v(is_equal_approx(initial_nul[0].saillance, brute), "travail_initial a 0.0 -- aucune ponderation, jamais une division par zero")

# LA serrure hors domaine : un chantier SANS AUCUN rapport avec le feu (une
# mine qui s'epuise) doit traverser le meme code.
func _le_modele_ignore_le_domaine(v) -> void:
	var colon := {"proprietes": {}}
	var catalogue := {"filon": {"saillance_intrinseque": 4.0, "portee_saillance": 500.0}}
	var frais := Proximite.evaluer(
		[_perception("filon_frais", Vector3(50, 0, 0), 50.0, {"profil_saillance": "filon", "travail_restant": 10.0, "travail_initial": 10.0})],
		colon, catalogue, {},
	)
	var epuise := Proximite.evaluer(
		[_perception("filon_epuise", Vector3(50, 0, 0), 50.0, {"profil_saillance": "filon", "travail_restant": 1.0, "travail_initial": 10.0})],
		colon, catalogue, {},
	)
	v.v(frais.size() == 1 and epuise.size() == 1, "un filon doit rester saillant dans les deux cas")
	if frais.size() == 1 and epuise.size() == 1:
		v.v(epuise[0].saillance < frais[0].saillance,
			"un filon presque epuise doit peser moins qu'un filon frais, meme code que le feu")

# ---- Niveau decider() : le colon va naturellement au chantier le plus
# gros, avec les vraies donnees du depot. ----

func _profils_saillance() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/profils_saillance.json"))

func _colon_placide(pos: Vector3) -> Dictionary:
	return {
		"id": "colon_test",
		"position": pos,
		"proprietes": {
			"attaches": [], "forme": {}, "poids_verbes": {},
			"canaux": ["vue"], "canaux_config": {"vue": {"portee": 2000.0}},
		},
		"action_en_cours": {},
	}

func _feu(id: String, pos: Vector3, travail_restant: float) -> Dictionary:
	return {
		"id": id, "position": pos,
		"proprietes": {"profil_saillance": "feu", "travail_restant": travail_restant, "travail_initial": 3.0},
	}

# Deux feux a EGALE distance, un FRAIS (3.0/3.0) et un PRESQUE ETEINT
# (0.1/3.0) : le colon doit choisir le frais -- le travail restant, pas la
# proximite ni un comptage d'agents, decide.
func _deux_feux_colon_va_au_frais(v) -> void:
	const Monde = preload("res://scripts/monde.gd")
	var monde := Monde.new()
	var feu_frais := _feu("feu_frais", Vector3(100, 0, 0), 3.0)
	var feu_presque_eteint := _feu("feu_presque_eteint", Vector3(0, 100, 0), 0.1)
	monde.ajouter(feu_frais, "feu", feu_frais.position)
	monde.ajouter(feu_presque_eteint, "feu", feu_presque_eteint.position)

	var colon := _colon_placide(Vector3.ZERO)
	var r := BancP1.decider(colon, monde, CATALOGUE_CANAUX, {}, _profils_saillance(), {}, {})
	v.v(r.decision != null and r.decision.has("chose"), "le colon doit viser un feu")
	if r.decision != null and r.decision.has("chose"):
		v.v(r.decision.chose.id == "feu_frais", "le colon doit choisir le feu frais, pas le feu presque eteint")

# Un seul feu, presque eteint : le colon doit y aller QUAND MEME -- la
# ponderation attenue, elle n'exclut jamais, pas d'alternative.
func _un_seul_feu_presque_eteint_colon_y_va_quand_meme(v) -> void:
	const Monde = preload("res://scripts/monde.gd")
	var monde := Monde.new()
	var feu := _feu("feu_unique", Vector3(100, 0, 0), 0.1)
	monde.ajouter(feu, "feu", feu.position)

	var colon := _colon_placide(Vector3.ZERO)
	var r := BancP1.decider(colon, monde, CATALOGUE_CANAUX, {}, _profils_saillance(), {}, {})
	v.v(r.decision != null, "meme presque eteint, l'unique feu doit rester une decision, jamais RIEN")
	if r.decision != null:
		v.v(r.decision.has("chose") and r.decision.chose.id == "feu_unique",
			"le colon doit viser l'unique feu malgre son avancement presque termine")
