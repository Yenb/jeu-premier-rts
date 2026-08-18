extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_croissance.gd
#
# Verrouille le cablage de banc_croissance.gd -- croissance_max (data/
# materiaux.json:plante_demo) plafonne un taux compose de lumiere_locale
# (scripts/lumiere.gd, NON TOUCHE) et d'une charge d'humidite normalisee
# (scripts/charge.gd, NON TOUCHE), applique a une reserve 'maturite' via un
# emetteur flux.gd (scripts/flux.gd, NON TOUCHE) synthetique construit
# CHAQUE TICK. AUCUN MECANISME DU COEUR TOUCHE par ce chantier -- ce
# fichier verrouille uniquement banc_croissance.gd.

const BancCroissance = preload("res://scripts/banc_croissance.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

const CONFIG := {
	"propriete_source_croissance": "emission_croissance",
	"propriete_receptrice_croissance": "recepteur_croissance",
	"nom_reserve_maturite": "maturite",
	"nom_canal_humidite": "humidite",
	"propriete_croissance_max": "croissance_max",
	"portee_flux_croissance": 5.0,
	"canal_humidite_defaut": {"charge": 0.0, "seuil": 5.0, "portee_charge": 200.0, "taux_decroissance": 0.5, "poser": {}},
}

const CATALOGUE_LUMIERE := {
	"defaut": {"ambiante": {"intensite": 0.0, "couleur": 0.9}, "attenuation": {"exposant": 1.0}},
}

const SOURCE_LUMIERE := {"position": Vector3(0, 0, 0), "rayon": 200.0, "intensite": 1.0, "temperature_couleur": 0.3, "force": 1.0}
const SOURCE_EAU := {"id": "eau_test", "position": Vector3(0, 0, 0)}

const CANAL_HUMIDITE_DEFAUT := {"charge": 0.0, "seuil": 5.0, "portee_charge": 200.0, "taux_decroissance": 0.5, "poser": {}}

func _init() -> void:
	_basculer_pur()
	_charge_humidite_normalisee_pure()
	_taux_croissance_haute_bat_basse()
	_lumiere_et_eau_maturite_monte()
	_lumiere_sans_eau_maturite_stagne()
	_eau_sans_lumiere_maturite_stagne()
	_les_deux_absentes_maturite_stagne()
	_croissance_max_haute_pousse_plus_vite_que_basse_via_avancer()
	_maturite_bornee_a_un()
	_hors_domaine_avancer_ignore_le_domaine()
	_fabrication_reelle_fusionne_croissance_max_depuis_materiaux_json()
	_donnees_reelles_banc_croissance_json()
	_chemin_reel_trois_plantes()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: bascule pure, charge_humidite_normalisee pure, croissance_max plafonne bien la vitesse, " +
		"lumiere+eau fait monter la maturite, lumiere sans eau stagne, eau sans lumiere stagne, " +
		"les deux absentes stagne, croissance_max haute pousse plus vite que basse, la maturite " +
		"reste bornee a 1.0, avancer() ignore le domaine, la fabrication reelle fusionne " +
		"croissance_max depuis materiaux.json, data/banc_croissance.json charge correctement, " +
		"et le chemin reel complet (trois plantes, donnees sur disque) se comporte comme attendu")
	quit(0)

func _plante(id: String, position: Vector3, croissance_max: float) -> Dictionary:
	return {
		"id": id,
		"position": position,
		"proprietes": {
			CONFIG.propriete_croissance_max: croissance_max,
			CONFIG.propriete_receptrice_croissance: true,
			"etats": {CONFIG.nom_canal_humidite: CANAL_HUMIDITE_DEFAUT.duplicate(true)},
			"reserves": {CONFIG.nom_reserve_maturite: {"reserve": 0.0}},
		},
	}

func _maturite(plante: Dictionary) -> float:
	return plante.proprietes.reserves[CONFIG.nom_reserve_maturite].reserve

func _basculer_pur() -> void:
	verif.v(not BancCroissance.basculer(true), "un actif bascule vers coupe")
	verif.v(BancCroissance.basculer(false), "un coupe bascule vers actif")

func _charge_humidite_normalisee_pure() -> void:
	verif.v(BancCroissance.charge_humidite_normalisee({"charge": 2.5, "seuil": 5.0}) == 0.5, "charge a mi-seuil doit normaliser a 0.5")
	verif.v(BancCroissance.charge_humidite_normalisee({"charge": 50.0, "seuil": 5.0}) == 1.0, "une charge au-dela du seuil doit rester bornee a 1.0 -- jamais la charge brute")
	verif.v(BancCroissance.charge_humidite_normalisee({"charge": 0.0, "seuil": 5.0}) == 0.0, "aucune charge doit normaliser a 0.0")
	verif.v(BancCroissance.charge_humidite_normalisee({"charge": 0.0, "seuil": 0.0}) == 0.0, "seuil nul sans charge doit replier sur 0.0, jamais une division par zero")
	verif.v(BancCroissance.charge_humidite_normalisee({"charge": 3.0, "seuil": 0.0}) == 1.0, "seuil nul avec une charge deja positive doit replier sur 1.0")

func _taux_croissance_haute_bat_basse() -> void:
	var haut := BancCroissance.taux_croissance(0.8, 0.5, 0.5)
	var bas := BancCroissance.taux_croissance(0.2, 0.5, 0.5)
	verif.v(haut > bas, "a lumiere et humidite egales, un croissance_max plus haut doit produire un taux plus haut")
	verif.v(abs(haut - 0.2) < 0.0001, "le taux doit valoir exactement croissance_max * lumiere_locale * charge_humidite")
	verif.v(BancCroissance.taux_croissance(0.9, 0.0, 1.0) == 0.0, "lumiere nulle doit annuler le taux quel que soit croissance_max")
	verif.v(BancCroissance.taux_croissance(0.9, 1.0, 0.0) == 0.0, "humidite nulle doit annuler le taux quel que soit croissance_max")

func _lumiere_et_eau_maturite_monte() -> void:
	var plante := _plante("p", Vector3(50, 0, 0), 0.5)
	for i in 30:
		BancCroissance.avancer([plante], SOURCE_LUMIERE, true, SOURCE_EAU, true, 1.0, CONFIG, CATALOGUE_LUMIERE)
	verif.v(_maturite(plante) > 0.0, "lumiere ET eau presentes : la maturite doit strictement monter")

func _lumiere_sans_eau_maturite_stagne() -> void:
	var plante := _plante("p", Vector3(50, 0, 0), 0.5)
	for i in 30:
		BancCroissance.avancer([plante], SOURCE_LUMIERE, true, SOURCE_EAU, false, 1.0, CONFIG, CATALOGUE_LUMIERE)
	verif.v(_maturite(plante) == 0.0, "lumiere sans eau (source d'eau coupee) : la maturite ne doit jamais bouger")

func _eau_sans_lumiere_maturite_stagne() -> void:
	var plante := _plante("p", Vector3(50, 0, 0), 0.5)
	for i in 30:
		BancCroissance.avancer([plante], SOURCE_LUMIERE, false, SOURCE_EAU, true, 1.0, CONFIG, CATALOGUE_LUMIERE)
	verif.v(_maturite(plante) == 0.0, "eau sans lumiere (source de lumiere coupee) : la maturite ne doit jamais bouger, meme si la charge d'humidite monte")

func _les_deux_absentes_maturite_stagne() -> void:
	var plante := _plante("p", Vector3(50, 0, 0), 0.5)
	for i in 30:
		BancCroissance.avancer([plante], SOURCE_LUMIERE, false, SOURCE_EAU, false, 1.0, CONFIG, CATALOGUE_LUMIERE)
	verif.v(_maturite(plante) == 0.0, "les deux sources absentes : la maturite ne doit jamais bouger")

func _croissance_max_haute_pousse_plus_vite_que_basse_via_avancer() -> void:
	# Croissance_max volontairement basse pour les deux (0.3/0.05) et peu de
	# pas -- evite que l'une ou l'autre n'atteigne le plafond de maturite
	# 1.0 (voir _maturite_bornee_a_un ci-dessous), ce qui rendrait la
	# comparaison triviale (1.0 == 1.0 n'est jamais > 1.0).
	var haute := _plante("haute", Vector3(50, 0, 0), 0.3)
	var basse := _plante("basse", Vector3(50, 0, 0), 0.05)
	for i in 5:
		BancCroissance.avancer([haute, basse], SOURCE_LUMIERE, true, SOURCE_EAU, true, 1.0, CONFIG, CATALOGUE_LUMIERE)
	verif.v(_maturite(haute) < 1.0 and _maturite(basse) < 1.0, "cette comparaison suppose qu'aucune des deux n'a encore atteint le plafond (sinon triviale)")
	verif.v(_maturite(haute) > _maturite(basse), "meme exposition, croissance_max plus haut doit produire une maturite strictement plus grande")

func _maturite_bornee_a_un() -> void:
	var plante := _plante("p", Vector3(0, 0, 0), 1.0)
	for i in 200:
		BancCroissance.avancer([plante], SOURCE_LUMIERE, true, SOURCE_EAU, true, 1.0, CONFIG, CATALOGUE_LUMIERE)
		verif.v(_maturite(plante) <= 1.0, "la maturite ne doit jamais depasser 1.0, meme en cours de simulation")
	verif.v(_maturite(plante) == 1.0, "une exposition longue et maximale doit atteindre exactement 1.0, jamais plus")

# Un couple source/receptrice/reserve invente, sans aucun rapport avec la
# lumiere ou l'eau, doit traverser exactement le meme code -- meme serrure
# que test_banc_conduction.gd/test_banc_photodegradation.gd.
func _hors_domaine_avancer_ignore_le_domaine() -> void:
	var config_invente := {
		"propriete_source_croissance": "emission_zorg",
		"propriete_receptrice_croissance": "recepteur_zorg",
		"nom_reserve_maturite": "essor_zorg",
		"nom_canal_humidite": "humidite_zorg",
		"propriete_croissance_max": "vitesse_zorg",
		"portee_flux_croissance": 5.0,
	}
	var source_lumiere_zorg := {"position": Vector3(0, 0, 0), "rayon": 200.0, "intensite": 1.0, "temperature_couleur": 0.5, "force": 1.0}
	var source_eau_zorg := {"id": "zorg_eau", "position": Vector3(0, 0, 0)}
	var cobaye := {
		"id": "cobaye",
		"position": Vector3(20, 0, 0),
		"proprietes": {
			"vitesse_zorg": 0.6,
			"recepteur_zorg": true,
			"etats": {"humidite_zorg": {"charge": 0.0, "seuil": 5.0, "portee_charge": 200.0, "taux_decroissance": 0.5, "poser": {}}},
			"reserves": {"essor_zorg": {"reserve": 0.0}},
		},
	}
	for i in 30:
		BancCroissance.avancer([cobaye], source_lumiere_zorg, true, source_eau_zorg, true, 1.0, config_invente, CATALOGUE_LUMIERE)
	verif.v(cobaye.proprietes.reserves.essor_zorg.reserve > 0.0, "un domaine invente doit voir sa reserve monter exactement comme une plante")

# Chemin REEL : materiaux.json/proprietes_immuables_composition.json lus
# sur disque -- verrouille que croissance_max (fusionnee par ce chantier)
# est bien lue par fabriquer_plantes(), independamment de tout cablage de
# scene.
func _fabrication_reelle_fusionne_croissance_max_depuis_materiaux_json() -> void:
	var materiaux: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))
	var proprietes_immuables: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/proprietes_immuables_composition.json")).get("proprietes", [])
	verif.v(proprietes_immuables.has("croissance_max"), "data/proprietes_immuables_composition.json doit lister croissance_max")
	verif.v(materiaux.has("plante_demo"), "data/materiaux.json doit declarer plante_demo")

	var declarations := [
		{"id": "test_plante", "position": [0.0, 0.0, 0.0], "composition": [{"materiau": "plante_demo", "volume": 1.0}]},
	]
	var plantes := BancCroissance.fabriquer_plantes(declarations, materiaux, proprietes_immuables, CONFIG)
	verif.v(plantes.size() == 1, "une declaration doit fabriquer une plante")
	var plante: Dictionary = plantes[0]
	verif.v(abs(plante.proprietes.croissance_max - 0.5) < 0.0001, "une plante reelle doit fusionner croissance_max=0.5 depuis materiaux.json:plante_demo")
	verif.v(plante.proprietes.get(CONFIG.propriete_receptrice_croissance, false), "une plante fabriquee doit porter le marqueur receptrice de croissance")
	verif.v(plante.proprietes.reserves[CONFIG.nom_reserve_maturite].reserve == 0.0, "une plante fraichement fabriquee demarre a maturite 0.0")

func _donnees_reelles_banc_croissance_json() -> void:
	var donnees: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_croissance.json"))
	verif.v(donnees.nom_reserve_maturite == "maturite", "data/banc_croissance.json doit declarer nom_reserve_maturite")
	verif.v(donnees.nom_canal_humidite == "humidite", "data/banc_croissance.json doit declarer nom_canal_humidite")
	verif.v(donnees.plantes.size() == 3, "data/banc_croissance.json doit declarer trois plantes")
	var ids: Array = []
	for plante in donnees.plantes:
		ids.append(plante.id)
	for id_attendu in ["plante_1", "plante_2", "plante_3"]:
		verif.v(ids.has(id_attendu), "data/banc_croissance.json doit declarer la plante '%s'" % id_attendu)

# Chemin REEL complet : data/banc_croissance.json/data/lumiere.json/
# data/materiaux.json/data/proprietes_immuables_composition.json lus sur
# disque, comme banc_croissance.gd les charge lui-meme a _ready() --
# reproduit sa boucle de simulation pour les trois plantes reelles, les
# deux sources actives en permanence (c'est la POSITION de chaque plante,
# jamais un toggle par plante, qui separe les trois destins -- voir
# data/banc_croissance.json._note).
func _chemin_reel_trois_plantes() -> void:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_croissance.json"))
	var catalogue_lumiere: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/lumiere.json"))
	var materiaux: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))
	var proprietes_immuables: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/proprietes_immuables_composition.json")).get("proprietes", [])

	var plantes := BancCroissance.fabriquer_plantes(config.get("plantes", []), materiaux, proprietes_immuables, config)
	var par_id: Dictionary = {}
	for plante in plantes:
		par_id[plante.id] = plante

	var pos_lumiere: Array = config.source_lumiere.position
	var source_lumiere := {
		"position": Vector3(pos_lumiere[0], pos_lumiere[1], pos_lumiere[2]),
		"rayon": config.source_lumiere.rayon, "intensite": config.source_lumiere.intensite,
		"temperature_couleur": config.source_lumiere.get("temperature_couleur", 0.0), "force": config.source_lumiere.force,
	}
	var pos_eau: Array = config.source_eau.position
	var source_eau := {"id": config.source_eau.id, "position": Vector3(pos_eau[0], pos_eau[1], pos_eau[2])}

	var delta := 1.0
	for i in 60:
		BancCroissance.avancer(plantes, source_lumiere, true, source_eau, true, delta, config, catalogue_lumiere)

	verif.v(_maturite(par_id.plante_1) > 0.0, "chemin reel : plante_1 (lumiere ET eau a portee) doit avoir strictement pousse")
	verif.v(_maturite(par_id.plante_2) == 0.0, "chemin reel : plante_2 (lumiere seule, hors de portee de l'eau) ne doit jamais avoir pousse")
	verif.v(_maturite(par_id.plante_3) == 0.0, "chemin reel : plante_3 (eau seule, hors de portee de la lumiere) ne doit jamais avoir pousse")
