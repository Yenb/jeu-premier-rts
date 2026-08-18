extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_occlusion.gd
#
# Verrouille le cablage de banc_occlusion.gd -- chantier « occlusion -- un
# obstacle entre A et B bloque la perception » :
# 1. fabriquer_colon_occlusion -- fusionne la surcharge locale (ouie_surcharge)
#    PAR-DESSUS canaux_config.ouie du type partage "colon", jamais un
#    mecanisme du coeur qui la lirait ;
# 2. monde_du_tick -- le mur n'entre dans le Monde du tick QUE si mur_actif
#    est vrai, RECONSTRUIT du neant a chaque appel (jamais une mutation en
#    place d'un objet deja enregistre) ;
# 3. facteur_obstacle_affichage -- neutre (1.0) si mur_actif est faux,
#    (1.0 - absorption_sonore) sinon, POUR L'AFFICHAGE SEUL ;
# 4. chemin reel (data/banc_occlusion.json + materiaux.json +
#    proprietes_immuables_composition.json + canaux.json + types.json) :
#    colon_avec_mur n'entend PAS source_avec_mur quand le mur (pierre) est
#    present, l'entend de nouveau une fois le mur absent -- colon_temoin
#    entend TOUJOURS source_temoin, mur present ou non, jamais affecte
#    (paire distincte, aucun mur).
#
# AUCUN MECANISME DU COEUR TOUCHE par ce fichier : perception.gd/objet.gd/
# monde.gd/banc_commun.gd/banc_son.gd restent exactement ceux deja
# verrouilles par leurs propres tests -- ce fichier verrouille uniquement
# banc_occlusion.gd.

const BancOcclusion = preload("res://scripts/banc_occlusion.gd")
const Monde = preload("res://scripts/monde.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

func _init() -> void:
	_fabriquer_colon_occlusion_fusionne_la_surcharge_locale()

	_monde_du_tick_inclut_le_mur_si_actif()
	_monde_du_tick_exclut_le_mur_si_inactif()
	_monde_du_tick_inclut_toujours_la_paire_temoin()

	_facteur_obstacle_affichage_neutre_si_mur_inactif()
	_facteur_obstacle_affichage_reduit_si_mur_actif()

	_chemin_reel_donnees_banc_occlusion_json()
	_chemin_reel_mur_present_bloque_la_source()
	_chemin_reel_mur_absent_la_source_est_percue()
	_chemin_reel_paire_temoin_jamais_affectee_par_le_mur()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: banc_occlusion.gd -- surcharge locale de canaux_config.ouie fusionnee, " +
		"le mur entre/sort du Monde du tick selon mur_actif (jamais une mutation en " +
		"place), facteur d'affichage neutre sans mur ; chemin reel (data/" +
		"banc_occlusion.json + materiaux.json + canaux.json) : un mur en pierre " +
		"bloque la source qu'il occulte, retire il la laisse repasser, la paire " +
		"temoin (sans mur) n'est jamais affectee")
	quit(0)

# ---- Catalogue local, memes canaux que la donnee reelle mais sans dependre
# du disque pour les tests hors chemin reel ----

const CATALOGUE_TYPES := {
	"colon": {
		"herite": [],
		"canaux": ["ouie"],
		"canaux_config": { "ouie": { "portee": 600.0, "sensibilite": 1.0, "seuil": 0.0 } },
		"attaches": [],
	},
}

const CATALOGUE_CANAUX := {
	"ouie": { "geometrie": "propagation_obstacles", "propriete_obstacle": "absorption_sonore", "largeur_obstacle": 40.0 },
}

func _chose(id: String, position: Vector3, proprietes: Dictionary = {}) -> Dictionary:
	return { "id": id, "position": position, "proprietes": proprietes }

# ---- fabriquer_colon_occlusion ----

func _fabriquer_colon_occlusion_fusionne_la_surcharge_locale() -> void:
	var decl := { "id": "colon_test", "position": [0.0, 0.0, 0.0], "attaches": [], "ouie_surcharge": { "portee": 200.0, "seuil": 0.24 } }
	var colon := BancOcclusion.fabriquer_colon_occlusion(decl, CATALOGUE_TYPES)

	verif.v(is_equal_approx(colon.proprietes.canaux_config.ouie.portee, 200.0),
		"fabriquer_colon_occlusion : la surcharge locale doit ecraser la portee par defaut du type (600.0 -> 200.0)")
	verif.v(is_equal_approx(colon.proprietes.canaux_config.ouie.seuil, 0.24),
		"fabriquer_colon_occlusion : la surcharge locale doit poser le seuil (0.24), absent du type partage")

# ---- monde_du_tick ----

func _monde_du_tick_inclut_le_mur_si_actif() -> void:
	var colon := _chose("colon", Vector3.ZERO)
	var source := _chose("source", Vector3(100.0, 0.0, 0.0))
	var mur := _chose("mur", Vector3(50.0, 0.0, 0.0), { "absorption_sonore": 0.05 })
	var colon_t := _chose("colon_t", Vector3(500.0, 0.0, 0.0))
	var source_t := _chose("source_t", Vector3(600.0, 0.0, 0.0))

	var monde = BancOcclusion.monde_du_tick(colon, source, mur, true, colon_t, source_t)
	verif.v(monde.choses.has("mur"), "monde_du_tick : mur_actif=true doit inclure le mur dans le Monde du tick")

func _monde_du_tick_exclut_le_mur_si_inactif() -> void:
	var colon := _chose("colon", Vector3.ZERO)
	var source := _chose("source", Vector3(100.0, 0.0, 0.0))
	var mur := _chose("mur", Vector3(50.0, 0.0, 0.0), { "absorption_sonore": 0.05 })
	var colon_t := _chose("colon_t", Vector3(500.0, 0.0, 0.0))
	var source_t := _chose("source_t", Vector3(600.0, 0.0, 0.0))

	var monde = BancOcclusion.monde_du_tick(colon, source, mur, false, colon_t, source_t)
	verif.v(not monde.choses.has("mur"), "monde_du_tick : mur_actif=false ne doit JAMAIS inclure le mur -- RECONSTRUIT du neant, jamais une mutation en place")

func _monde_du_tick_inclut_toujours_la_paire_temoin() -> void:
	var colon := _chose("colon", Vector3.ZERO)
	var source := _chose("source", Vector3(100.0, 0.0, 0.0))
	var mur := _chose("mur", Vector3(50.0, 0.0, 0.0), { "absorption_sonore": 0.05 })
	var colon_t := _chose("colon_t", Vector3(500.0, 0.0, 0.0))
	var source_t := _chose("source_t", Vector3(600.0, 0.0, 0.0))

	var monde = BancOcclusion.monde_du_tick(colon, source, mur, true, colon_t, source_t)
	verif.v(monde.choses.has("colon_t") and monde.choses.has("source_t"),
		"monde_du_tick : la paire temoin doit toujours etre presente, quel que soit mur_actif")

# ---- facteur_obstacle_affichage ----

func _facteur_obstacle_affichage_neutre_si_mur_inactif() -> void:
	var facteur := BancOcclusion.facteur_obstacle_affichage(false, 0.9)
	verif.v(is_equal_approx(facteur, 1.0), "facteur_obstacle_affichage : mur_actif=false doit rendre 1.0, peu importe absorption_sonore")

func _facteur_obstacle_affichage_reduit_si_mur_actif() -> void:
	var facteur := BancOcclusion.facteur_obstacle_affichage(true, 0.05)
	verif.v(is_equal_approx(facteur, 0.95), "facteur_obstacle_affichage : mur_actif=true doit rendre (1.0 - absorption_sonore) = 0.95")

# ---- Chemin reel ----

func _config() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_occlusion.json"))

func _materiaux() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))

func _proprietes_immuables() -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/proprietes_immuables_composition.json")).get("proprietes", [])

func _catalogue_types_reel() -> Dictionary:
	var types_partages: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/types.json"))
	var config: Dictionary = _config()
	var catalogue: Dictionary = config.get("types", {}).duplicate(true)
	catalogue["objet_physique"] = types_partages.get("objet_physique", {})
	catalogue["dynamique"] = types_partages.get("dynamique", {})
	catalogue["percevant"] = types_partages.get("percevant", {})
	catalogue["agent"] = types_partages.get("agent", {})
	catalogue["colon"] = types_partages.get("colon", {})
	return catalogue

func _catalogue_canaux_reel() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/canaux.json"))

func _donnees_reelles_banc_occlusion_json() -> void:
	var config := _config()
	verif.v(config.avec_mur.colon.ouie_surcharge.seuil > 0.0, "data/banc_occlusion.json doit porter un seuil surcharge strictement positif")
	verif.v(config.temoin.has("colon") and config.temoin.has("source") and not config.temoin.has("mur"),
		"data/banc_occlusion.json : la paire temoin ne doit JAMAIS declarer de mur")

func _chemin_reel_donnees_banc_occlusion_json() -> void:
	_donnees_reelles_banc_occlusion_json()

func _chemin_reel_mur_present_bloque_la_source() -> void:
	var config := _config()
	var materiaux := _materiaux()
	var proprietes_immuables := _proprietes_immuables()
	var catalogue_types := _catalogue_types_reel()
	var catalogue_canaux := _catalogue_canaux_reel()

	var colon := BancOcclusion.fabriquer_colon_occlusion(config.avec_mur.colon, catalogue_types)
	var source := BancOcclusion.fabriquer_source(config.avec_mur.source, catalogue_types, materiaux, proprietes_immuables)
	var mur := BancOcclusion.fabriquer_mur(config.avec_mur.mur, catalogue_types, materiaux, proprietes_immuables)

	verif.v(is_equal_approx(mur.proprietes.get("absorption_sonore", -1.0), 0.05),
		"chemin reel : le mur (pierre) doit fusionner absorption_sonore=0.05 depuis data/materiaux.json")

	var monde := Monde.new()
	monde.ajouter(colon, "colon", colon.position)
	monde.ajouter(source, "source_son", source.position)
	monde.ajouter(mur, "mur", mur.position)

	var entendus := BancOcclusion.captures_ouie(colon, monde, catalogue_canaux)
	verif.v(not BancOcclusion.ids_de(entendus).has(source.id),
		"chemin reel : mur present (pierre, absorption_sonore 0.05) entre colon_avec_mur et source_avec_mur -- intensite attenuee (0.2375) doit tomber sous le seuil (0.24)")

func _chemin_reel_mur_absent_la_source_est_percue() -> void:
	var config := _config()
	var materiaux := _materiaux()
	var proprietes_immuables := _proprietes_immuables()
	var catalogue_types := _catalogue_types_reel()
	var catalogue_canaux := _catalogue_canaux_reel()

	var colon := BancOcclusion.fabriquer_colon_occlusion(config.avec_mur.colon, catalogue_types)
	var source := BancOcclusion.fabriquer_source(config.avec_mur.source, catalogue_types, materiaux, proprietes_immuables)

	var monde := Monde.new()
	monde.ajouter(colon, "colon", colon.position)
	monde.ajouter(source, "source_son", source.position)
	# PAS de mur ajoute -- meme monde_du_tick(..., mur_actif=false, ...).

	var entendus := BancOcclusion.captures_ouie(colon, monde, catalogue_canaux)
	verif.v(BancOcclusion.ids_de(entendus).has(source.id),
		"chemin reel : sans le mur, la MEME source (intensite non attenuee 0.25) doit repasser le seuil (0.24)")

func _chemin_reel_paire_temoin_jamais_affectee_par_le_mur() -> void:
	var config := _config()
	var materiaux := _materiaux()
	var proprietes_immuables := _proprietes_immuables()
	var catalogue_types := _catalogue_types_reel()
	var catalogue_canaux := _catalogue_canaux_reel()

	var colon_avec_mur := BancOcclusion.fabriquer_colon_occlusion(config.avec_mur.colon, catalogue_types)
	var source_avec_mur := BancOcclusion.fabriquer_source(config.avec_mur.source, catalogue_types, materiaux, proprietes_immuables)
	var mur := BancOcclusion.fabriquer_mur(config.avec_mur.mur, catalogue_types, materiaux, proprietes_immuables)
	var colon_temoin := BancOcclusion.fabriquer_colon_occlusion(config.temoin.colon, catalogue_types)
	var source_temoin := BancOcclusion.fabriquer_source(config.temoin.source, catalogue_types, materiaux, proprietes_immuables)

	var monde = BancOcclusion.monde_du_tick(colon_avec_mur, source_avec_mur, mur, true, colon_temoin, source_temoin)

	var entendus_temoin := BancOcclusion.ids_de(BancOcclusion.captures_ouie(colon_temoin, monde, catalogue_canaux))
	verif.v(entendus_temoin.has(source_temoin.id),
		"chemin reel : colon_temoin doit toujours entendre source_temoin, MEME quand le mur de l'autre paire est actif -- aucune paire n'affecte l'autre")
