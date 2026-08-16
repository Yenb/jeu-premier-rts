extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_foudre.gd
#
# Verrouille le cablage de banc_foudre.gd -- chantier « foudre -- evenement
# ponctuel », audit_foudre_prealable.md :
# 1. Frappe.selectionner/frapper (INCHANGES, verrouilles hors domaine par
#    test_frappe.gd) choisissent et frappent la cible la plus conductrice et
#    la plus haute parmi les objets FRAPPABLES a portee, sur des fer/bois
#    REELS de data/materiaux.json ;
# 2. objets_frappables (PROPRE a ce banc) exclut tout objet deja detruit ;
# 3. Temperature.avancer (INCHANGE) applique un choc thermique UN SEUL tick
#    a la position de l'impact, puis refroidit normalement (loi de Newton)
#    une fois la source retiree.
#
# AUCUN MECANISME DU COEUR TOUCHE par ce chantier : frappe.gd/
# quantite_matiere.gd/portee.gd/temperature.gd/objet.gd restent exactement
# ceux deja verrouilles par leurs propres tests -- ce fichier verrouille
# uniquement banc_foudre.gd.

const BancFoudre = preload("res://scripts/banc_foudre.gd")
const Temperature = preload("res://scripts/temperature.gd")
const QuantiteMatiere = preload("res://scripts/quantite_matiere.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

func _init() -> void:
	_la_cible_la_plus_conductrice_et_la_plus_haute_est_selectionnee()
	_objet_hors_portee_jamais_candidat()
	_objet_sans_conductivite_et_sans_hauteur_jamais_selectionne()
	_degat_instantane_pas_continu()
	_temperature_monte_au_point_d_impact_puis_redescend()
	_objet_deja_detruit_n_est_plus_selectionne()
	_egalite_stricte_un_seul_est_frappe()
	_donnees_reelles_banc_foudre_json()
	_chemin_reel_fabrication_fusionne_conductivite_et_temperature()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: banc_foudre.gd -- la cible la plus conductrice et la plus haute est frappee, un objet " +
		"hors portee n'est jamais candidat, un objet ni conducteur ni haut n'est jamais selectionne, " +
		"le degat est instantane (independant du delta), la temperature monte au point d'impact puis " +
		"redescend, un objet deja detruit n'est plus jamais candidat, une egalite stricte ne frappe " +
		"qu'un seul objet, chemin reel (data/banc_foudre.json + materiaux.json + types.json)")
	quit(0)

# ---- Fixtures : chargement disque, meme discipline que test_banc_conduction.gd ----

func _charger(chemin: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))

func _config() -> Dictionary:
	return _charger("res://data/banc_foudre.json")

func _materiaux() -> Dictionary:
	return _charger("res://data/materiaux.json")

func _proprietes_immuables() -> Array:
	return _charger("res://data/proprietes_immuables_composition.json").get("proprietes", [])

func _objet_physique() -> Dictionary:
	return _charger("res://data/types.json").get("objet_physique", {})

func _catalogue_temperature() -> Dictionary:
	return _charger("res://data/temperature.json")

func _objets_reels(config: Dictionary) -> Array:
	return BancFoudre.fabriquer_objets(config.objets, _objet_physique(), _materiaux(), _proprietes_immuables(), config.nom_reserve_integrite, config.reserve_integrite_defaut)

func _par_id(objets: Array, id: String) -> Dictionary:
	for objet in objets:
		if objet.id == id:
			return objet
	return {}

func _reserve(objets: Array, id: String, nom: String) -> float:
	return _par_id(objets, id).proprietes.reserves[nom].reserve

func _temperature(objets: Array, id: String) -> float:
	return _par_id(objets, id).proprietes.temperature

# ---- Selection, chemin reel (fer/bois de data/materiaux.json) ----

func _la_cible_la_plus_conductrice_et_la_plus_haute_est_selectionnee() -> void:
	var config := _config()
	var objets := _objets_reels(config)
	var diag := BancFoudre.avancer_frappe(objets, config, _materiaux(), _catalogue_temperature())
	verif.v(not diag.is_empty(), "un eclair doit trouver une cible dans la scene par defaut")
	verif.v(diag.cible.id == "fer_haut", "la cible la plus conductrice et la plus haute (fer_haut) doit etre selectionnee")

func _objet_hors_portee_jamais_candidat() -> void:
	var config := _config()
	var objets := _objets_reels(config)
	# score enorme (volume 1000x) mais hors du rayon (450) depuis position_source -- ne doit jamais compter
	var extreme := {"id": "fer_extreme", "position": [5000.0, 0.0, 300.0], "composition": [{"materiau": "fer", "volume": 1000.0}]}
	objets.append_array(BancFoudre.fabriquer_objets([extreme], _objet_physique(), _materiaux(), _proprietes_immuables(), config.nom_reserve_integrite, config.reserve_integrite_defaut))
	var diag := BancFoudre.avancer_frappe(objets, config, _materiaux(), _catalogue_temperature())
	verif.v(diag.cible.id != "fer_extreme", "un objet hors du rayon ne doit jamais devenir candidat, meme a score enorme")
	verif.v(diag.cible.id == "fer_haut", "hors du rayon, la selection doit rester celle des objets a portee (fer_haut)")

func _objet_sans_conductivite_et_sans_hauteur_jamais_selectionne() -> void:
	var config := _config()
	var objets := _objets_reels(config)
	var diag := BancFoudre.avancer_frappe(objets, config, _materiaux(), _catalogue_temperature())
	verif.v(diag.cible.id != "bois_bas", "bois_bas (ni conducteur ni haut) ne doit jamais etre selectionne face aux trois autres")

# ---- Degat instantane ----

func _degat_instantane_pas_continu() -> void:
	var config := _config()
	var objets := _objets_reels(config)
	var reserve_avant := _reserve(objets, "fer_haut", config.nom_reserve_integrite)
	var config_delta_enorme := config.duplicate(true)
	config_delta_enorme.delta_impact = 1000.0
	BancFoudre.avancer_frappe(objets, config_delta_enorme, _materiaux(), _catalogue_temperature())
	var reserve_apres := _reserve(objets, "fer_haut", config.nom_reserve_integrite)
	verif.v(is_equal_approx(reserve_avant - reserve_apres, config.degats),
		"le degat doit etre exactement 'degats' (%.2f), jamais mis a l'echelle par delta_impact (meme a delta_impact=1000.0)" % config.degats)

# ---- Temperature : monte au point d'impact, redescend ensuite ----

func _temperature_monte_au_point_d_impact_puis_redescend() -> void:
	var config := _config()
	var objets := _objets_reels(config)
	var diag := BancFoudre.avancer_frappe(objets, config, _materiaux(), _catalogue_temperature())
	verif.v(diag.temperature_apres > diag.temperature_avant, "la temperature de la cible doit monter au tick de la frappe")

	var catalogue := _catalogue_temperature()
	var derniere := _temperature(objets, "fer_haut")
	for i in 5:
		Temperature.avancer(objets, [], 0.5, catalogue)
		var nouvelle := _temperature(objets, "fer_haut")
		verif.v(nouvelle < derniere, "la temperature doit redescendre strictement vers l'ambiante une fois la source de choc retiree (pas %d)" % i)
		derniere = nouvelle

# ---- Cible deja detruite ----

func _objet_deja_detruit_n_est_plus_selectionne() -> void:
	var config := _config()
	var objets := _objets_reels(config)
	var premier := BancFoudre.avancer_frappe(objets, config, _materiaux(), _catalogue_temperature())
	verif.v(premier.cible.id == "fer_haut", "premier eclair doit frapper fer_haut")
	verif.v(is_equal_approx(_reserve(objets, "fer_haut", config.nom_reserve_integrite), 0.0),
		"fer_haut doit etre entierement detruit (reserve a zero) apres un seul eclair (degats == reserve max)")

	var second := BancFoudre.avancer_frappe(objets, config, _materiaux(), _catalogue_temperature())
	verif.v(second.cible.id != "fer_haut", "un objet deja detruit ne doit plus jamais etre candidat")
	verif.v(second.cible.id == "fer_bas", "le second eclair doit frapper la cible frappable au score le plus haut restante (fer_bas)")

# ---- Egalite stricte : un seul frappe ----

func _egalite_stricte_un_seul_est_frappe() -> void:
	var config := _config()
	var jumeau_a := {"id": "jumeau_a", "position": [100.0, 0.0, 300.0], "composition": [{"materiau": "fer", "volume": 1.0}]}
	var jumeau_b := {"id": "jumeau_b", "position": [100.0, 0.0, 300.0], "composition": [{"materiau": "fer", "volume": 1.0}]}
	var objets := BancFoudre.fabriquer_objets([jumeau_a, jumeau_b], _objet_physique(), _materiaux(), _proprietes_immuables(), config.nom_reserve_integrite, config.reserve_integrite_defaut)
	var diag := BancFoudre.avancer_frappe(objets, config, _materiaux(), _catalogue_temperature())
	verif.v(not diag.is_empty(), "une egalite stricte doit quand meme produire une cible")

	var reserve_max: float = config.reserve_integrite_defaut.reserve
	var touches := 0
	if not is_equal_approx(_reserve(objets, "jumeau_a", config.nom_reserve_integrite), reserve_max):
		touches += 1
	if not is_equal_approx(_reserve(objets, "jumeau_b", config.nom_reserve_integrite), reserve_max):
		touches += 1
	verif.v(touches == 1, "en cas d'egalite stricte, un SEUL des deux objets doit perdre de l'integrite, jamais les deux")

# ---- Chemin REEL : data/banc_foudre.json ----

func _donnees_reelles_banc_foudre_json() -> void:
	var config := _config()
	verif.v(config.objets.size() == 4, "data/banc_foudre.json doit declarer quatre objets")
	verif.v(config.criteres.size() == 2, "data/banc_foudre.json doit declarer deux criteres (conductivite_electrique, position_z)")
	var par_id: Dictionary = {}
	for decl in config.objets:
		par_id[decl.id] = decl
	verif.v(par_id.fer_haut.composition[0].materiau == "fer", "fer_haut doit etre compose de fer")
	verif.v(par_id.bois_bas.composition[0].materiau == "bois", "bois_bas doit etre compose de bois")
	verif.v(par_id.fer_haut.position[2] > par_id.fer_bas.position[2], "fer_haut doit avoir une position.z strictement superieure a fer_bas")

func _chemin_reel_fabrication_fusionne_conductivite_et_temperature() -> void:
	var config := _config()
	var materiaux := _materiaux()
	var objets := _objets_reels(config)
	var par_id: Dictionary = {}
	for objet in objets:
		par_id[objet.id] = objet

	verif.v(par_id.fer_haut.proprietes.has("temperature"), "chemin reel : fer_haut doit porter 'temperature' (paquet objet_physique fusionne)")
	verif.v(is_equal_approx(par_id.fer_haut.proprietes.temperature, 20.0), "chemin reel : temperature initiale doit etre le defaut du paquet objet_physique (20.0)")

	var cond_fer: float = QuantiteMatiere.quantite(par_id.fer_haut.proprietes, "conductivite_electrique", materiaux)
	verif.v(is_equal_approx(cond_fer, 1e7), "chemin reel : fer_haut doit fusionner conductivite_electrique=1e7 depuis materiaux.json (volume 1.0)")
	var cond_bois: float = QuantiteMatiere.quantite(par_id.bois_bas.proprietes, "conductivite_electrique", materiaux)
	verif.v(is_equal_approx(cond_bois, 1e-15), "chemin reel : bois_bas doit fusionner conductivite_electrique=1e-15 depuis materiaux.json")
