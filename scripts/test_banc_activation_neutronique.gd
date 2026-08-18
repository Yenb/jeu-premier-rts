extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_activation_neutronique.gd
#
# Verrouille le cablage de banc_activation_neutronique.gd -- chantier
# « activation neutronique -- objet irradie devient source secondaire » :
# 1. avancer_objets (perception -> charge.gd -> "dose_radiation_objet" =
#    MAXIMUM jamais atteint par la charge -> seuil_etat.gd -> depense.gd sur
#    "radioactivite_acquise" -> combustible.gd, tous INCHANGES) fait monter
#    la dose d'un objet expose, pose "active_neutronique" au seuil fixe
#    30.0, et fait decroitre force_radiation avec la reserve acquise.
# 2. avancer_colon (perception sur un Monde d'OBJETS, jamais la source
#    primaire -> charge.gd -> epigenetique.gd/etat_duree.gd/seuil_etat.gd,
#    tous INCHANGES) montre qu'un objet active irradie le colon, y compris
#    quand la source primaire est absente ou hors de portee.
#
# AUCUN MECANISME DU COEUR TOUCHE par ce chantier : charge.gd/depense.gd/
# seuil_etat.gd/etat_duree.gd/etat_effectif.gd/epigenetique.gd/combustible.gd/
# perception.gd/objet.gd restent exactement ceux deja verrouilles par leurs
# propres tests -- ce fichier verrouille uniquement
# banc_activation_neutronique.gd.

const BancActivationNeutronique = preload("res://scripts/banc_activation_neutronique.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

func _init() -> void:
	_objet_expose_accumule_dose_radiation_objet()
	_seuil_franchi_objet_gagne_force_radiation_et_devient_source()
	_objet_active_irradie_colon_a_portee()
	_colon_recoit_radiation_d_un_objet_actif_meme_sans_source_primaire_a_portee()
	_force_radiation_decroit_avec_la_reserve()
	_reserve_epuisee_force_radiation_devient_nulle()
	_objet_jamais_expose_ne_devient_jamais_source()

	_donnees_reelles_catalogues()
	_chemin_reel_source_objets_colon()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: un objet expose accumule dose_radiation_objet (maximum jamais atteint, jamais un miroir " +
		"direct de charge.gd), franchit le seuil fixe 30.0 et devient source secondaire (force_radiation " +
		"> 0, reserve radioactivite_acquise posee UNE SEULE fois), un objet active irradie le colon a " +
		"portee y compris quand la source primaire est absente ou hors de portee (elle n'entre jamais " +
		"dans le Monde interroge par avancer_colon), force_radiation decroit avec la reserve acquise et " +
		"retombe exactement a 0.0 une fois epuisee, un objet jamais expose (ou a sensibilite nulle) ne " +
		"devient jamais source, et les catalogues/donnees reels chargent et se comportent comme attendu " +
		"chemin reel")
	quit(0)

# ---- Fixtures ----

const CATALOGUE_CANAUX := {
	"radiation": {
		"geometrie": "propagation_obstacles",
		"propriete_obstacle": "densite",
		"largeur_obstacle": 40.0,
		"propriete_emission": "force_radiation",
	},
}

const CONFIG := {
	"nom_canal_radiation": "radiation",
	"canal_radiation_defaut": {
		"charge": 0.0, "seuil": 5.0, "portee_charge": 600.0,
		"taux_decroissance": 0.5, "poser": {},
	},

	"portee_perception_primaire": 500.0,
	"seuil_perception_primaire": 0.001,

	"force_radiation_secondaire_base": 1.8,
	"reserve_acquise_defaut": { "capacite": 20.0, "reserve": 20.0, "cout_base": 1.0, "surcout_action": 0.0 },

	"portee_perception_secondaire": 500.0,
	"seuil_perception_secondaire": 0.001,

	"nom_canal_mutation": "exposition_radioactive",
	"declencheur_mutation": "expose_radiation_chronique",
	"canal_mutation_defaut": {
		"charge": 0.0, "seuil": 5.0, "portee_charge": 500.0,
		"taux_decroissance": 0.5, "poser": { "expose_radiation_chronique": true },
	},
	"nom_marque_epigenetique": "exposition_radioactive",

	"nom_canal_nausee": "nausee_radiation",
	"declencheur_nausee": "expose_nausee_radiation",
	"canal_nausee_defaut": {
		"charge": 0.0, "seuil": 2.0, "portee_charge": 500.0,
		"taux_decroissance": 0.5, "poser": { "expose_nausee_radiation": true },
	},
	"nom_etat_nausee": "nausee_radiation",
	"dose_par_s": 0.5,
}

const ETATS := {
	"active_neutronique": { "effets": [] },
	"nausee_radiation": { "duree": 5.0, "effets": [ { "propriete": "vitesse", "mode": "moduler", "facteur": 0.5 } ] },
	"syndrome_radiation": { "effets": [ { "propriete": "vitesse", "mode": "moduler", "facteur": 0.2 } ] },
	"mort_radiation": { "effets": [ { "propriete": "vitesse", "mode": "ecraser", "valeur": 0.0 } ] },
}

const SEUILS_ETAT := {
	"activation_neutronique": { "propriete_continue": "dose_radiation_objet", "seuil": 30.0, "etat": "active_neutronique" },
	"syndrome_radiation": { "propriete_continue": "dose_radiation_cumulee", "seuil": 50.0, "etat": "syndrome_radiation" },
	"mort_radiation": { "propriete_continue": "dose_radiation_cumulee", "seuil": 100.0, "etat": "mort_radiation" },
}

const EPIGENETIQUE := {
	"exposition_radioactive": {
		"cible": "vitesse", "modulateur_pose": 0.01, "taux_decroissance": 0.001,
		"plancher_suppression": 0.005, "source_environnementale": "radiation",
	},
}

func _source(force: float, position: Vector3) -> Dictionary:
	return { "id": "source_test", "position": position, "proprietes": { "force_radiation": force } }

func _objet(id: String, position: Vector3, sensibilite: float) -> Dictionary:
	return {
		"id": id,
		"position": position,
		"proprietes": {
			"sensibilite_radiation": sensibilite,
			"etats": { CONFIG.nom_canal_radiation: CONFIG.canal_radiation_defaut.duplicate(true) },
			"etats_actifs": [],
			"reserves": {},
			"dose_radiation_objet": 0.0,
			"force_radiation": 0.0,
		},
	}

# Objet DEJA active_neutronique, avec sa reserve acquise a une proportion
# donnee -- isole les tests 3/4/5/6 de la rampe d'activation elle-meme
# (deja verrouillee par _seuil_franchi_objet_gagne_force_radiation_et_devient_source).
func _objet_active(id: String, position: Vector3, proportion_reserve: float) -> Dictionary:
	var objet := _objet(id, position, 0.0)
	objet.proprietes.etats_actifs = ["active_neutronique"]
	objet.proprietes.dose_radiation_objet = 35.0
	var capacite: float = CONFIG.reserve_acquise_defaut.capacite
	objet.proprietes.reserves["radioactivite_acquise"] = {
		"capacite": capacite, "reserve": capacite * proportion_reserve,
		"cout_base": CONFIG.reserve_acquise_defaut.cout_base, "surcout_action": 0.0,
	}
	objet.proprietes.force_radiation = CONFIG.force_radiation_secondaire_base * proportion_reserve
	return objet

func _colon(id: String, position: Vector3) -> Dictionary:
	return {
		"id": id,
		"position": position,
		"proprietes": {
			"etats": {
				CONFIG.nom_canal_mutation: CONFIG.canal_mutation_defaut.duplicate(true),
				CONFIG.nom_canal_nausee: CONFIG.canal_nausee_defaut.duplicate(true),
			},
			"etats_actifs": [],
			"marques_epigenetiques": {},
			"dose_radiation_cumulee": 0.0,
			"vitesse": 150.0,
		},
	}

# ---- 1. Un objet expose accumule dose_radiation_objet ----

func _objet_expose_accumule_dose_radiation_objet() -> void:
	var source := _source(6.0, Vector3.ZERO)
	var objet := _objet("o1", Vector3(100, 0, 0), 0.3)
	for i in 5:
		BancActivationNeutronique.avancer_objets([objet], source, true, 1.0, CONFIG, ETATS, SEUILS_ETAT, CATALOGUE_CANAUX)
	verif.v(objet.proprietes.dose_radiation_objet > 0.0, "expose, dose_radiation_objet doit avoir monte")
	verif.v(not objet.proprietes.etats_actifs.has("active_neutronique"), "5s a 1.8/s (=9.0), sous le seuil 30.0 : pas encore actif")

# ---- 2. Au seuil, l'objet gagne force_radiation > 0 (devient source) ----

func _seuil_franchi_objet_gagne_force_radiation_et_devient_source() -> void:
	var source := _source(6.0, Vector3.ZERO)
	var objet := _objet("o2", Vector3(100, 0, 0), 0.3)
	for i in 25:
		BancActivationNeutronique.avancer_objets([objet], source, true, 1.0, CONFIG, ETATS, SEUILS_ETAT, CATALOGUE_CANAUX)
	verif.v(objet.proprietes.etats_actifs.has("active_neutronique"), "apres 25s a 1.8/s (=45.0 > 30.0), active_neutronique doit etre pose")
	verif.v(objet.proprietes.reserves.has("radioactivite_acquise"), "une fois actif, l'objet doit porter la reserve radioactivite_acquise")
	verif.v(objet.proprietes.force_radiation > 0.0, "une fois actif, force_radiation doit etre strictement positif")

# ---- 3. L'objet active irradie le colon a portee ----

func _objet_active_irradie_colon_a_portee() -> void:
	var objet := _objet_active("o3", Vector3(400, 0, 0), 1.0)
	var colon := _colon("c1", Vector3(500, 0, 0))
	for i in 5:
		BancActivationNeutronique.avancer_colon(colon, [objet], 1.0, CONFIG, ETATS, SEUILS_ETAT, EPIGENETIQUE, CATALOGUE_CANAUX)
	verif.v(colon.proprietes.dose_radiation_cumulee > 0.0, "un objet active a portee doit irradier le colon")

# ---- 4. Le colon, hors de portee de la source primaire, recoit quand meme
# la radiation de l'objet active (la source primaire n'entre JAMAIS dans le
# Monde interroge par avancer_colon -- protection PAR CONSTRUCTION) ----

func _colon_recoit_radiation_d_un_objet_actif_meme_sans_source_primaire_a_portee() -> void:
	var source_loin := _source(6.0, Vector3(9000, 0, 0))
	var objet := _objet_active("o4", Vector3(400, 0, 0), 1.0)
	var colon := _colon("c2", Vector3(500, 0, 0))
	for i in 5:
		BancActivationNeutronique.avancer(source_loin, false, [objet], colon, 1.0, CONFIG, ETATS, SEUILS_ETAT, EPIGENETIQUE, CATALOGUE_CANAUX)
	verif.v(colon.proprietes.dose_radiation_cumulee > 0.0, "source primaire absente/hors de portee : le colon doit quand meme recevoir la radiation de l'objet actif")

# ---- 5. force_radiation decroit avec la reserve radioactivite_acquise ----

func _force_radiation_decroit_avec_la_reserve() -> void:
	var objet := _objet_active("o5", Vector3(400, 0, 0), 1.0)
	var source_loin := _source(0.0, Vector3(9000, 0, 0))
	var force_avant: float = objet.proprietes.force_radiation
	for i in 5:
		BancActivationNeutronique.avancer_objets([objet], source_loin, false, 1.0, CONFIG, ETATS, SEUILS_ETAT, CATALOGUE_CANAUX)
	verif.v(objet.proprietes.force_radiation < force_avant, "la reserve se videant, force_radiation doit avoir baisse")
	verif.v(objet.proprietes.force_radiation > 0.0, "apres seulement 5s sur une reserve de 20.0, force_radiation ne doit pas encore etre nul")

# ---- 6. Quand la reserve atteint zero, force_radiation = 0 ----

func _reserve_epuisee_force_radiation_devient_nulle() -> void:
	var objet := _objet_active("o6", Vector3(400, 0, 0), 1.0)
	var source_loin := _source(0.0, Vector3(9000, 0, 0))
	for i in 25:
		BancActivationNeutronique.avancer_objets([objet], source_loin, false, 1.0, CONFIG, ETATS, SEUILS_ETAT, CATALOGUE_CANAUX)
	verif.v(objet.proprietes.reserves.radioactivite_acquise.reserve == 0.0, "apres 25s a cout_base 1.0 sur une reserve de 20.0, elle doit etre epuisee")
	verif.v(objet.proprietes.force_radiation == 0.0, "reserve epuisee, force_radiation doit valoir exactement 0.0")
	verif.v(objet.proprietes.etats_actifs.has("active_neutronique"), "meme reserve epuisee, active_neutronique doit rester pose -- cicatrice permanente")

# ---- 7. Un objet jamais expose au seuil ne devient jamais source ----

func _objet_jamais_expose_ne_devient_jamais_source() -> void:
	var source_loin := _source(6.0, Vector3(9000, 0, 0))
	var objet := _objet("o7", Vector3(100, 0, 0), 0.3)
	for i in 60:
		BancActivationNeutronique.avancer_objets([objet], source_loin, true, 1.0, CONFIG, ETATS, SEUILS_ETAT, CATALOGUE_CANAUX)
	verif.v(objet.proprietes.dose_radiation_objet < 30.0, "jamais expose (source hors de portee), dose_radiation_objet doit rester sous le seuil")
	verif.v(not objet.proprietes.etats_actifs.has("active_neutronique"), "jamais expose, l'objet ne doit jamais devenir source secondaire")
	verif.v(not objet.proprietes.reserves.has("radioactivite_acquise"), "jamais actif, aucune reserve radioactivite_acquise ne doit exister")

	var source_proche := _source(6.0, Vector3.ZERO)
	var objet_insensible := _objet("o7b", Vector3(100, 0, 0), 0.0)
	for i in 60:
		BancActivationNeutronique.avancer_objets([objet_insensible], source_proche, true, 1.0, CONFIG, ETATS, SEUILS_ETAT, CATALOGUE_CANAUX)
	verif.v(objet_insensible.proprietes.dose_radiation_objet == 0.0, "sensibilite_radiation 0.0 ne doit jamais produire de dose, meme expose reellement")

# ---- Donnees reelles : data/etats.json + data/seuils_etat.json ----

func _charger(chemin: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))

func _donnees_reelles_catalogues() -> void:
	var etats_reels: Dictionary = _charger("res://data/etats.json")
	verif.v(etats_reels.has("active_neutronique"), "data/etats.json doit porter 'active_neutronique'")
	verif.v(not etats_reels.active_neutronique.has("duree"), "'active_neutronique' ne doit pas porter 'duree' (permanent)")
	verif.v(etats_reels.active_neutronique.effets.is_empty(), "'active_neutronique' doit etre un marqueur pur (effets vide)")

	var seuils_etat_reels: Dictionary = _charger("res://data/seuils_etat.json")
	verif.v(seuils_etat_reels.has("activation_neutronique"), "data/seuils_etat.json doit porter 'activation_neutronique'")
	verif.v(seuils_etat_reels.activation_neutronique.propriete_continue == "dose_radiation_objet", "'activation_neutronique' doit comparer 'dose_radiation_objet'")
	verif.v(not seuils_etat_reels.activation_neutronique.has("seuil_propriete"), "'activation_neutronique' doit avoir un seuil FIXE, pas par materiau")
	verif.v(seuils_etat_reels.activation_neutronique.seuil == 30.0, "le seuil d'activation neutronique doit valoir 30.0")
	verif.v(seuils_etat_reels.activation_neutronique.etat == "active_neutronique", "'activation_neutronique' doit poser l'etat 'active_neutronique'")

# ---- Chemin REEL : data/banc_activation_neutronique.json + tous les catalogues ----

func _chemin_reel_source_objets_colon() -> void:
	var donnees: Dictionary = _charger("res://data/banc_activation_neutronique.json")
	var materiaux: Dictionary = _charger("res://data/materiaux.json")
	var etats: Dictionary = _charger("res://data/etats.json")
	var seuils_etat: Dictionary = _charger("res://data/seuils_etat.json")
	var epigenetique: Dictionary = _charger("res://data/epigenetique.json")
	var canaux: Dictionary = _charger("res://data/canaux.json")
	var table_types: Dictionary = _charger("res://data/types.json")
	var proprietes_immuables: Array = _charger("res://data/proprietes_immuables_composition.json").get("proprietes", [])

	var source := BancActivationNeutronique.fabriquer_source(donnees.source)
	var objets := BancActivationNeutronique.fabriquer_objets(donnees.objets, materiaux, proprietes_immuables, donnees)
	var pos_colon: Array = donnees.colon.position
	var colon := BancActivationNeutronique.fabriquer_colon(donnees.colon.id, Vector3(pos_colon[0], pos_colon[1], pos_colon[2]), table_types, donnees)

	verif.v(not colon.is_empty(), "chemin reel : le colon doit se fabriquer sans erreur")
	verif.v(objets.size() == 3, "chemin reel : les trois objets doivent se fabriquer")

	var bois: Dictionary = objets.filter(func(o): return o.id == "bois_active")[0]

	var bois_actif := false
	for i in 20:
		var r := BancActivationNeutronique.avancer(source, true, objets, colon, 1.0, donnees, etats, seuils_etat, epigenetique, canaux)
		if r.bascules_activation.has("bois_active"):
			bois_actif = true
	verif.v(bois_actif, "chemin reel : bois_active (sensibilite_radiation la plus haute, 0.3) doit s'activer en moins de 20s")
	verif.v(bois.proprietes.force_radiation > 0.0, "chemin reel : bois_active doit irradier une fois source secondaire")

	for i in 10:
		BancActivationNeutronique.avancer(source, true, objets, colon, 1.0, donnees, etats, seuils_etat, epigenetique, canaux)
	verif.v(colon.proprietes.dose_radiation_cumulee > 0.0, "chemin reel : le colon, hors de portee de la source primaire, doit finir par recevoir de la radiation via bois_active")
