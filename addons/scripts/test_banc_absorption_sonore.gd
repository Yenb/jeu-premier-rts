extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_absorption_sonore.gd
#
# Verrouille le cablage de banc_absorption_sonore.gd -- chantier
# « absorption_sonore -- un materiau absorbe le son » :
# 1. etat_suivant -- cycle aucun -> bois -> pierre -> fer -> aucun ;
# 2. fabriquer_colon_absorption -- fusionne la surcharge locale
#    (ouie_surcharge) PAR-DESSUS canaux_config.ouie du type partage "colon" ;
# 3. monde_du_tick -- seule la variante de mur correspondant a "etat" entre
#    dans le Monde du tick, jamais deux a la fois, RECONSTRUIT du neant a
#    chaque appel ;
# 4. facteur_attenuation_affichage/intensite_recue_affichage -- formules
#    d'affichage seul ;
# 5. chemin reel (data/banc_absorption_sonore.json + materiaux.json +
#    proprietes_immuables_composition.json + canaux.json + types.json) :
#    sans mur le colon entend a pleine intensite (0.25) ; avec bois
#    l'attenuation reelle est de 30% ; avec pierre 5% ; avec fer 2% ; deux
#    murs reels empiles (bois + pierre) cumulent MULTIPLICATIVEMENT leur
#    attenuation (verifie par franchissement de seuil, meme methode que
#    test_perception.gd:_deux_murs_cumulent_leur_attenuation) ; un obstacle
#    d'absorption_sonore 0.0 ne reduit rien (facteur neutre, meme resultat
#    qu'aucun obstacle).
#
# AUCUN MECANISME DU COEUR TOUCHE par ce fichier : perception.gd/objet.gd/
# monde.gd/banc_commun.gd/banc_son.gd/banc_occlusion.gd restent exactement
# ceux deja verrouilles par leurs propres tests -- ce fichier verrouille
# uniquement banc_absorption_sonore.gd.

const BancAbsorptionSonore = preload("res://scripts/banc_absorption_sonore.gd")
const Monde = preload("res://scripts/monde.gd")
const Perception = preload("res://scripts/perception.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

func _init() -> void:
	_etat_suivant_cycle_les_quatre_etats()
	_fabriquer_colon_absorption_fusionne_la_surcharge_locale()

	_monde_du_tick_sans_mur_aucun_mur()
	_monde_du_tick_avec_bois_inclut_seulement_le_mur_bois()
	_monde_du_tick_avec_pierre_inclut_seulement_le_mur_pierre()

	_facteur_attenuation_affichage_neutre_si_aucun()
	_facteur_attenuation_affichage_reduit_selon_le_materiau()
	_intensite_recue_affichage_formule()

	_chemin_reel_sans_mur_intensite_pleine()
	_chemin_reel_avec_bois_reduction_30_pourcent()
	_chemin_reel_avec_pierre_reduction_5_pourcent()
	_chemin_reel_avec_fer_reduction_2_pourcent()
	_chemin_reel_deux_murs_cumulent_lattenuation()
	_chemin_reel_absorption_nulle_ne_reduit_rien()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: banc_absorption_sonore.gd -- le mur cycle aucun/bois/pierre/fer sans " +
		"jamais en superposer deux, le bois absorbe le plus (~30%), le fer le moins " +
		"(~2%) ; chemin reel (data/banc_absorption_sonore.json + materiaux.json + " +
		"canaux.json) : intensite pleine sans mur, reduction exacte par materiau, " +
		"deux murs reels empiles cumulent multiplicativement, un obstacle " +
		"d'absorption_sonore 0.0 ne reduit rien")
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

# ---- etat_suivant ----

func _etat_suivant_cycle_les_quatre_etats() -> void:
	verif.v(BancAbsorptionSonore.etat_suivant("aucun") == "bois", "etat_suivant : aucun -> bois")
	verif.v(BancAbsorptionSonore.etat_suivant("bois") == "pierre", "etat_suivant : bois -> pierre")
	verif.v(BancAbsorptionSonore.etat_suivant("pierre") == "fer", "etat_suivant : pierre -> fer")
	verif.v(BancAbsorptionSonore.etat_suivant("fer") == "aucun", "etat_suivant : fer -> aucun (boucle)")

# ---- fabriquer_colon_absorption ----

func _fabriquer_colon_absorption_fusionne_la_surcharge_locale() -> void:
	var decl := { "id": "colon_test", "position": [0.0, 0.0, 0.0], "attaches": [], "ouie_surcharge": { "portee": 200.0, "seuil": 0.17 } }
	var colon := BancAbsorptionSonore.fabriquer_colon_absorption(decl, CATALOGUE_TYPES)

	verif.v(is_equal_approx(colon.proprietes.canaux_config.ouie.portee, 200.0),
		"fabriquer_colon_absorption : la surcharge locale doit ecraser la portee par defaut du type (600.0 -> 200.0)")
	verif.v(is_equal_approx(colon.proprietes.canaux_config.ouie.seuil, 0.17),
		"fabriquer_colon_absorption : la surcharge locale doit poser le seuil (0.17), absent du type partage")

# ---- monde_du_tick ----

func _murs_synthetiques() -> Dictionary:
	return {
		"bois": _chose("mur_0", Vector3(50.0, 0.0, 0.0), { "absorption_sonore": 0.3 }),
		"pierre": _chose("mur_0", Vector3(50.0, 0.0, 0.0), { "absorption_sonore": 0.05 }),
		"fer": _chose("mur_0", Vector3(50.0, 0.0, 0.0), { "absorption_sonore": 0.02 }),
	}

func _monde_du_tick_sans_mur_aucun_mur() -> void:
	var colon := _chose("colon", Vector3.ZERO)
	var source := _chose("source", Vector3(100.0, 0.0, 0.0))
	var monde = BancAbsorptionSonore.monde_du_tick(colon, source, _murs_synthetiques(), "aucun")
	verif.v(not monde.choses.has("mur_0"), "monde_du_tick : etat 'aucun' ne doit jamais inclure de mur")

func _monde_du_tick_avec_bois_inclut_seulement_le_mur_bois() -> void:
	var colon := _chose("colon", Vector3.ZERO)
	var source := _chose("source", Vector3(100.0, 0.0, 0.0))
	var monde = BancAbsorptionSonore.monde_du_tick(colon, source, _murs_synthetiques(), "bois")
	verif.v(monde.choses.has("mur_0"), "monde_du_tick : etat 'bois' doit inclure le mur")
	verif.v(is_equal_approx(monde.par_id("mur_0").chose.proprietes.absorption_sonore, 0.3),
		"monde_du_tick : etat 'bois' doit inclure LA VARIANTE bois (absorption_sonore 0.3), pas une autre")

func _monde_du_tick_avec_pierre_inclut_seulement_le_mur_pierre() -> void:
	var colon := _chose("colon", Vector3.ZERO)
	var source := _chose("source", Vector3(100.0, 0.0, 0.0))
	var monde = BancAbsorptionSonore.monde_du_tick(colon, source, _murs_synthetiques(), "pierre")
	verif.v(is_equal_approx(monde.par_id("mur_0").chose.proprietes.absorption_sonore, 0.05),
		"monde_du_tick : etat 'pierre' doit inclure LA VARIANTE pierre (absorption_sonore 0.05), jamais bois ni fer en meme temps")

# ---- facteur_attenuation_affichage / intensite_recue_affichage ----

func _facteur_attenuation_affichage_neutre_si_aucun() -> void:
	var facteur := BancAbsorptionSonore.facteur_attenuation_affichage("aucun", _murs_synthetiques())
	verif.v(is_equal_approx(facteur, 1.0), "facteur_attenuation_affichage : etat 'aucun' doit rendre 1.0")

func _facteur_attenuation_affichage_reduit_selon_le_materiau() -> void:
	var murs := _murs_synthetiques()
	verif.v(is_equal_approx(BancAbsorptionSonore.facteur_attenuation_affichage("bois", murs), 0.7),
		"facteur_attenuation_affichage : bois (absorption 0.3) doit rendre 0.7")
	verif.v(is_equal_approx(BancAbsorptionSonore.facteur_attenuation_affichage("pierre", murs), 0.95),
		"facteur_attenuation_affichage : pierre (absorption 0.05) doit rendre 0.95")
	verif.v(is_equal_approx(BancAbsorptionSonore.facteur_attenuation_affichage("fer", murs), 0.98),
		"facteur_attenuation_affichage : fer (absorption 0.02) doit rendre 0.98")

func _intensite_recue_affichage_formule() -> void:
	var intensite := BancAbsorptionSonore.intensite_recue_affichage(0.5, 100.0, 200.0, 0.7)
	verif.v(is_equal_approx(intensite, 0.175), "intensite_recue_affichage : 0.5 * (1.0 - 100/200) * 0.7 = 0.175")
	verif.v(is_equal_approx(BancAbsorptionSonore.intensite_recue_affichage(0.5, 100.0, 0.0, 1.0), 0.0),
		"intensite_recue_affichage : portee <= 0.0 doit rendre 0.0, jamais une division par zero")

# ---- Chemin reel ----

func _config() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_absorption_sonore.json"))

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

# Fabrique colon/source/murs REELS depuis le disque, avec un seuil de
# canaux_config.ouie CHOISI PAR LE TEST (jamais celui de data/
# banc_absorption_sonore.json, qui vaut 0.0 -- ce fichier verifie ici des
# franchissements de seuil precis, le banc interactif lui-meme n'en a besoin
# d'aucun).
func _colon_reel_avec_seuil(seuil: float) -> Dictionary:
	var decl := { "id": "colon_0", "position": [0.0, 0.0, 0.0], "ouie_surcharge": { "portee": 200.0, "seuil": seuil } }
	return BancAbsorptionSonore.fabriquer_colon_absorption(decl, _catalogue_types_reel())

func _source_reelle() -> Dictionary:
	return BancAbsorptionSonore.fabriquer_source(_config().source, _catalogue_types_reel(), _materiaux(), _proprietes_immuables())

func _murs_reels() -> Dictionary:
	return BancAbsorptionSonore.fabriquer_murs(_config().mur, _catalogue_types_reel(), _materiaux(), _proprietes_immuables())

func _chemin_reel_sans_mur_intensite_pleine() -> void:
	# Seuil juste sous 0.25 (intensite sans mur) : capte sans mur, MEME seuil
	# que les tests avec mur ci-dessous -- seule la presence/le materiau du
	# mur doit expliquer une eventuelle non-capture.
	var colon := _colon_reel_avec_seuil(0.24)
	var source := _source_reelle()
	var monde := Monde.new()
	monde.ajouter(colon, "colon", colon.position)
	monde.ajouter(source, "source_son", source.position)

	var entendus := BancAbsorptionSonore.captures_ouie(colon, monde, _catalogue_canaux_reel())
	verif.v(BancAbsorptionSonore.ids_de(entendus).has(source.id),
		"chemin reel : sans mur, intensite 0.25 doit rester au-dessus du seuil 0.24 -- le colon entend a pleine intensite")

func _chemin_reel_avec_bois_reduction_30_pourcent() -> void:
	# Seuil entre l'intensite avec bois (0.175) et sans mur (0.25) : le bois
	# doit faire BASCULER la capture, preuve directe de la reduction ~30%.
	var colon := _colon_reel_avec_seuil(0.2)
	var source := _source_reelle()
	var mur: Dictionary = _murs_reels().bois
	verif.v(is_equal_approx(mur.proprietes.get("absorption_sonore", -1.0), 0.3),
		"chemin reel : le mur bois doit fusionner absorption_sonore=0.3 depuis data/materiaux.json")

	var monde := Monde.new()
	monde.ajouter(colon, "colon", colon.position)
	monde.ajouter(source, "source_son", source.position)
	monde.ajouter(mur, "mur", mur.position)

	var entendus := BancAbsorptionSonore.captures_ouie(colon, monde, _catalogue_canaux_reel())
	verif.v(not BancAbsorptionSonore.ids_de(entendus).has(source.id),
		"chemin reel : le bois (absorption_sonore 0.3) doit reduire l'intensite a 0.175, sous le seuil 0.2 (~30% de reduction)")

func _chemin_reel_avec_pierre_reduction_5_pourcent() -> void:
	# Seuil entre l'intensite avec pierre (0.2375) et sans mur (0.25).
	var colon := _colon_reel_avec_seuil(0.24)
	var source := _source_reelle()
	var mur: Dictionary = _murs_reels().pierre
	verif.v(is_equal_approx(mur.proprietes.get("absorption_sonore", -1.0), 0.05),
		"chemin reel : le mur pierre doit fusionner absorption_sonore=0.05 depuis data/materiaux.json")

	var monde := Monde.new()
	monde.ajouter(colon, "colon", colon.position)
	monde.ajouter(source, "source_son", source.position)
	monde.ajouter(mur, "mur", mur.position)

	var entendus := BancAbsorptionSonore.captures_ouie(colon, monde, _catalogue_canaux_reel())
	verif.v(not BancAbsorptionSonore.ids_de(entendus).has(source.id),
		"chemin reel : la pierre (absorption_sonore 0.05) doit reduire l'intensite a 0.2375, sous le seuil 0.24 (~5% de reduction)")

func _chemin_reel_avec_fer_reduction_2_pourcent() -> void:
	# Seuil entre l'intensite avec fer (0.245) et sans mur (0.25) -- marge la
	# plus fine des trois, le fer resonne, il n'absorbe presque pas.
	var colon := _colon_reel_avec_seuil(0.2475)
	var source := _source_reelle()
	var mur: Dictionary = _murs_reels().fer
	verif.v(is_equal_approx(mur.proprietes.get("absorption_sonore", -1.0), 0.02),
		"chemin reel : le mur fer doit fusionner absorption_sonore=0.02 depuis data/materiaux.json")

	var monde := Monde.new()
	monde.ajouter(colon, "colon", colon.position)
	monde.ajouter(source, "source_son", source.position)
	monde.ajouter(mur, "mur", mur.position)

	var entendus := BancAbsorptionSonore.captures_ouie(colon, monde, _catalogue_canaux_reel())
	verif.v(not BancAbsorptionSonore.ids_de(entendus).has(source.id),
		"chemin reel : le fer (absorption_sonore 0.02) doit reduire l'intensite a 0.245, sous le seuil 0.2475 (~2% de reduction)")

func _chemin_reel_deux_murs_cumulent_lattenuation() -> void:
	# Seuil entre l'intensite avec UN SEUL mur bois (0.175) et l'intensite
	# avec bois+pierre EMPILES (0.25 * 0.7 * 0.95 = 0.16625) -- un seul mur
	# passe encore, les deux ensemble tombent en dessous : preuve directe de
	# la cumulation MULTIPLICATIVE (meme methode que
	# test_perception.gd:_deux_murs_cumulent_leur_attenuation), ici avec des
	# materiaux REELS distincts plutot que deux valeurs synthetiques.
	var seuil := 0.17
	var source := _source_reelle()
	var murs := _murs_reels()
	var mur_bois: Dictionary = murs.bois
	var mur_pierre: Dictionary = murs.pierre.duplicate(true)
	mur_pierre["id"] = "mur_1"

	var colon_un_mur := _colon_reel_avec_seuil(seuil)
	var monde_un_mur := Monde.new()
	monde_un_mur.ajouter(colon_un_mur, "colon", colon_un_mur.position)
	monde_un_mur.ajouter(source, "source_son", source.position)
	monde_un_mur.ajouter(mur_bois, "mur", mur_bois.position)
	var entendus_un_mur := BancAbsorptionSonore.captures_ouie(colon_un_mur, monde_un_mur, _catalogue_canaux_reel())
	verif.v(BancAbsorptionSonore.ids_de(entendus_un_mur).has(source.id),
		"chemin reel : un seul mur bois (intensite 0.175) doit encore passer le seuil 0.17")

	var colon_deux_murs := _colon_reel_avec_seuil(seuil)
	var monde_deux_murs := Monde.new()
	monde_deux_murs.ajouter(colon_deux_murs, "colon", colon_deux_murs.position)
	monde_deux_murs.ajouter(source, "source_son", source.position)
	monde_deux_murs.ajouter(mur_bois, "mur", mur_bois.position)
	monde_deux_murs.ajouter(mur_pierre, "mur_pierre", mur_pierre.position)
	var entendus_deux_murs := BancAbsorptionSonore.captures_ouie(colon_deux_murs, monde_deux_murs, _catalogue_canaux_reel())
	verif.v(not BancAbsorptionSonore.ids_de(entendus_deux_murs).has(source.id),
		"chemin reel : bois + pierre EMPILES (intensite 0.16625) doivent cumuler MULTIPLICATIVEMENT et tomber sous le seuil 0.17, jamais atteint par le bois seul")

func _chemin_reel_absorption_nulle_ne_reduit_rien() -> void:
	# Seuil juste sous l'intensite sans mur (0.25) -- un obstacle
	# d'absorption_sonore 0.0 (synthetique, aucun materiau reel du depot ne
	# vaut exactement 0.0) doit laisser passer EXACTEMENT comme s'il
	# n'existait pas.
	var colon := _colon_reel_avec_seuil(0.24)
	var source := _source_reelle()
	var obstacle_neutre := _chose("obstacle_neutre", Vector3(50.0, 0.0, 0.0), { "absorption_sonore": 0.0 })

	var monde := Monde.new()
	monde.ajouter(colon, "colon", colon.position)
	monde.ajouter(source, "source_son", source.position)
	monde.ajouter(obstacle_neutre, "mur", obstacle_neutre.position)

	var entendus := BancAbsorptionSonore.captures_ouie(colon, monde, _catalogue_canaux_reel())
	verif.v(BancAbsorptionSonore.ids_de(entendus).has(source.id),
		"chemin reel : un obstacle d'absorption_sonore 0.0 ne doit RIEN reduire -- intensite 0.25 reste au-dessus du seuil 0.24, comme sans obstacle")
