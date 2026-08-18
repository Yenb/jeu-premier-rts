extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_produit_nucleaire.gd
#
# Verrouille le cablage de banc_produit_nucleaire.gd -- chantier « Produit
# nucleaire -- contamination, mutation, maladie » :
# 1. avancer_source (depense.gd -> combustible.gd -> produit.gd, tous
#    INCHANGES) fait decroitre force_radiation proportionnellement a la
#    reserve restante, puis transforme la source epuisee en residu qui
#    irradie plus faiblement ;
# 2. avancer_objets reprend TEL QUEL le mecanisme deja verrouille par
#    test_banc_radiation.gd (perception -> charge.gd -> etat_duree.gd ->
#    depense.gd) ;
# 3. avancer_colon (charge.gd -> epigenetique.gd / etat_duree.gd /
#    seuil_etat.gd -> etat_effectif.gd, tous INCHANGES) accumule
#    dose_radiation_cumulee, pose nausee_radiation (reversible) puis
#    syndrome_radiation/mort_radiation (irreversibles) selon la dose, et
#    accumule une marque epigenetique tant que le colon reste expose.
#
# AUCUN MECANISME DU COEUR TOUCHE par ce chantier : charge.gd/depense.gd/
# seuil_etat.gd/etat_duree.gd/etat_effectif.gd/epigenetique.gd/produit.gd/
# combustible.gd/perception.gd/objet.gd restent exactement ceux deja
# verrouilles par leurs propres tests -- ce fichier verrouille uniquement
# banc_produit_nucleaire.gd.

const BancProduitNucleaire = preload("res://scripts/banc_produit_nucleaire.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

func _init() -> void:
	_source_decroit_proportionnellement_a_la_reserve()
	_source_epuisee_se_transforme_en_residu_plus_faible()
	_source_transformee_ne_se_retransforme_jamais()

	_objets_irradient_comme_banc_radiation()

	_colon_expose_accumule_la_dose()
	_colon_hors_de_portee_aucune_dose()
	_nausee_posee_sous_exposition_puis_s_estompe()
	_syndrome_pose_au_seuil_et_reste_permanent()
	_mort_posee_au_seuil_suivant_vitesse_effective_nulle()
	_colon_mort_est_fige_plus_aucun_mecanisme_ne_le_met_a_jour()
	_marque_epigenetique_accumulee_pendant_l_exposition_puis_persiste()

	_mur_bloque_la_radiation_pour_le_colon()

	_donnees_reelles_catalogues()
	_chemin_reel_source_objets_colon()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: la source decroit en force proportionnellement a sa reserve puis se transforme en " +
		"residu plus faible qui ne se retransforme jamais, les trois objets cibles irradient comme " +
		"banc_radiation.gd, le colon expose accumule dose_radiation_cumulee (jamais hors de portee), " +
		"nausee_radiation reversible s'estompe en s'eloignant, syndrome_radiation et mort_radiation " +
		"sont poses en escalier et permanents (vitesse effective nulle une fois mort), la marque " +
		"epigenetique s'accumule puis persiste en decroissant, le mur de blindage bloque " +
		"simultanement fer_nucleaire et le colon, et les catalogues/donnees reels chargent et se " +
		"comportent comme attendu chemin reel")
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
	"declencheur_expose_radiation": "expose_radiation",
	"canal_radiation_defaut": {
		"charge": 0.0, "seuil": 1.0, "portee_charge": 400.0,
		"taux_decroissance": 0.3, "poser": { "expose_radiation": true },
	},
	"nom_etat_irradie": "irradie",
	"nom_reserve_integrite": "integrite",
	"reserve_integrite_defaut": { "reserve": 10.0, "cout_base": 0.0, "surcout_action": 0.0 },
	"degat_par_s": 1.0,

	"portee_perception_radiation": 400.0,
	"seuil_perception_radiation": 0.001,

	"nom_reserve_source": "radioactivite",
	"nom_reserve_residu": "radioactivite_residuelle",
	"force_radiation_source_base": 0.3,
	"force_radiation_residu_base": 0.15,
	"reserve_residuelle_defaut": { "capacite": 10.0, "reserve": 10.0, "cout_base": 0.5, "surcout_action": 0.0 },
	"declencheur_radioactivite_epuisee": "radioactivite_epuisee",
	"transformation_source": "epuisement_source_radiation",

	"nom_canal_mutation": "exposition_radioactive",
	"declencheur_mutation": "expose_radiation_chronique",
	"canal_mutation_defaut": {
		"charge": 0.0, "seuil": 5.0, "portee_charge": 400.0,
		"taux_decroissance": 0.5, "poser": { "expose_radiation_chronique": true },
	},
	"nom_marque_epigenetique": "exposition_radioactive",

	"nom_canal_nausee": "nausee_radiation",
	"declencheur_nausee": "expose_nausee_radiation",
	"canal_nausee_defaut": {
		"charge": 0.0, "seuil": 2.0, "portee_charge": 400.0,
		"taux_decroissance": 0.5, "poser": { "expose_nausee_radiation": true },
	},
	"nom_etat_nausee": "nausee_radiation",
	"dose_par_s": 0.5,
}

const ETATS := {
	"irradie": { "duree": 5.0, "effets": [] },
	"nausee_radiation": { "duree": 5.0, "effets": [ { "propriete": "vitesse", "mode": "moduler", "facteur": 0.5 } ] },
	"syndrome_radiation": { "effets": [ { "propriete": "vitesse", "mode": "moduler", "facteur": 0.2 } ] },
	"mort_radiation": { "effets": [ { "propriete": "vitesse", "mode": "ecraser", "valeur": 0.0 } ] },
}

const SEUILS_ETAT := {
	"syndrome_radiation": { "propriete_continue": "dose_radiation_cumulee", "seuil": 50.0, "etat": "syndrome_radiation" },
	"mort_radiation": { "propriete_continue": "dose_radiation_cumulee", "seuil": 100.0, "etat": "mort_radiation" },
}

const SEUILS_COMBUSTIBLE := {
	"epuisement_radioactivite": [ { "seuil": 0.0, "poser": { "radioactivite_epuisee": true } } ],
}

const EPIGENETIQUE := {
	"exposition_radioactive": {
		"cible": "vitesse", "modulateur_pose": 0.01, "taux_decroissance": 0.001,
		"plancher_suppression": 0.005, "source_environnementale": "radiation",
	},
}

const TABLE_TYPES_MIN := {
	"objet_physique": { "masse": 1.0, "volume": 0.001, "densite": 1000.0 },
	"residu_radioactif": { "herite": ["objet_physique"], "composition": [ { "materiau": "residu_radioactif", "volume": 1.0 } ] },
}

const MATERIAUX_MIN := {
	"residu_radioactif": { "densite": 4.0 },
}

const TRANSFORMATIONS := {
	"epuisement_source_radiation": {
		"a_zero": { "produire": { "type_produit": "residu_radioactif", "rendement": 0.8 } },
	},
}

func _source(force: float, masse: float, reserve: float, position: Vector3 = Vector3.ZERO) -> Dictionary:
	return {
		"id": "source_test",
		"position": position,
		"proprietes": {
			"force_radiation": force,
			"masse": masse,
			"reserves": { CONFIG.nom_reserve_source: { "capacite": reserve, "reserve": reserve, "cout_base": 1.0, "surcout_action": 0.0, "seuils_ref": "epuisement_radioactivite" } },
		},
	}

func _mur(position: Vector3, densite: float) -> Dictionary:
	return { "id": "mur_test", "position": position, "proprietes": { "densite": densite } }

func _objet_radiation(id: String, position: Vector3, sensibilite: float) -> Dictionary:
	return {
		"id": id,
		"position": position,
		"proprietes": {
			"sensibilite_radiation": sensibilite,
			"etats": { CONFIG.nom_canal_radiation: CONFIG.canal_radiation_defaut.duplicate(true) },
			"etats_actifs": [],
			"reserves": { CONFIG.nom_reserve_integrite: CONFIG.reserve_integrite_defaut.duplicate(true) },
		},
	}

func _colon(id: String, position: Vector3, dose: float = 0.0) -> Dictionary:
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
			"dose_radiation_cumulee": dose,
			"vitesse": 150.0,
		},
	}

# ---- Effet 1 : la source ----

func _source_decroit_proportionnellement_a_la_reserve() -> void:
	var source := _source(0.3, 50.0, 20.0)
	var mur := _mur(Vector3.ZERO, 0.0)
	var force_initiale: float = source.proprietes.force_radiation
	BancProduitNucleaire.avancer_source(source, 5.0, CONFIG, SEUILS_COMBUSTIBLE, TABLE_TYPES_MIN, MATERIAUX_MIN, TRANSFORMATIONS)
	verif.v(source.proprietes.force_radiation < force_initiale, "apres 5s de decroissance, force_radiation doit avoir baisse")
	var proportion_attendue: float = 15.0 / 20.0
	verif.v(abs(source.proprietes.force_radiation - 0.3 * proportion_attendue) < 0.0001, "force_radiation doit suivre exactement force_base * proportion restante")

func _source_epuisee_se_transforme_en_residu_plus_faible() -> void:
	var source := _source(0.3, 50.0, 5.0)
	var mur := _mur(Vector3.ZERO, 0.0)
	var transformee := false
	var force_juste_transforme := 0.0
	for i in 10:
		var r := BancProduitNucleaire.avancer_source(source, 1.0, CONFIG, SEUILS_COMBUSTIBLE, TABLE_TYPES_MIN, MATERIAUX_MIN, TRANSFORMATIONS)
		if r.transformee and not transformee:
			transformee = true
			force_juste_transforme = source.proprietes.force_radiation
	verif.v(transformee, "la source doit finir par se transformer une fois sa reserve epuisee")
	verif.v(not source.proprietes.reserves.has(CONFIG.nom_reserve_source), "apres transformation, l'ancienne reserve 'radioactivite' ne doit plus exister")
	verif.v(source.proprietes.reserves.has(CONFIG.nom_reserve_residu), "apres transformation, la nouvelle reserve 'radioactivite_residuelle' doit exister")
	verif.v(abs(force_juste_transforme - CONFIG.force_radiation_residu_base) < 0.0001, "juste transforme, force_radiation doit valoir force_radiation_residu_base (reserve residuelle pleine)")
	verif.v(CONFIG.force_radiation_residu_base < CONFIG.force_radiation_source_base, "le residu doit irradier plus faiblement que la source d'origine")

func _source_transformee_ne_se_retransforme_jamais() -> void:
	var source := _source(0.3, 50.0, 1.0)
	var mur := _mur(Vector3.ZERO, 0.0)
	var nb_transformations := 0
	for i in 60:
		var r := BancProduitNucleaire.avancer_source(source, 1.0, CONFIG, SEUILS_COMBUSTIBLE, TABLE_TYPES_MIN, MATERIAUX_MIN, TRANSFORMATIONS)
		if r.transformee:
			nb_transformations += 1
	verif.v(nb_transformations == 1, "la source ne doit se transformer qu'UNE SEULE fois, obtenu %d" % nb_transformations)
	verif.v(source.proprietes.force_radiation == 0.0 or source.proprietes.force_radiation < CONFIG.force_radiation_residu_base, "assez longtemps apres transformation, le residu doit finir par s'epuiser aussi (force_radiation retombe vers 0.0)")

# ---- Effet 1 (suite) : les trois objets, meme mecanique que banc_radiation.gd ----

func _objets_irradient_comme_banc_radiation() -> void:
	var source := _source(0.3, 50.0, 999.0, Vector3.ZERO)
	var mur := _mur(Vector3.ZERO, 0.0)
	var objet_haut := _objet_radiation("haut", Vector3(100, 0, 0), 0.3)
	var objet_bas := _objet_radiation("bas", Vector3(100, 0, 0), 0.1)
	for i in 3:
		BancProduitNucleaire.avancer_objets([objet_haut], source, mur, false, 1.0, CONFIG, ETATS, CATALOGUE_CANAUX)
		BancProduitNucleaire.avancer_objets([objet_bas], source, mur, false, 1.0, CONFIG, ETATS, CATALOGUE_CANAUX)
	var charge_haut: float = objet_haut.proprietes.etats.radiation.charge
	var charge_bas: float = objet_bas.proprietes.etats.radiation.charge
	verif.v(charge_haut > 0.0 and charge_bas > 0.0, "les deux charges doivent avoir monte")
	verif.v(charge_haut > charge_bas, "sensibilite plus haute doit accumuler plus vite")

	var objet_neutre := _objet_radiation("neutre", Vector3(100, 0, 0), 0.0)
	for i in 50:
		BancProduitNucleaire.avancer_objets([objet_neutre], source, mur, false, 0.5, CONFIG, ETATS, CATALOGUE_CANAUX)
	verif.v(objet_neutre.proprietes.etats.radiation.charge == 0.0, "sensibilite_radiation 0.0 ne doit jamais produire de charge")

# ---- Effets 2+3 : le colon ----

func _colon_expose_accumule_la_dose() -> void:
	var source := _source(0.3, 50.0, 999.0, Vector3.ZERO)
	var mur := _mur(Vector3.ZERO, 0.0)
	var colon := _colon("c1", Vector3(100, 0, 0))
	for i in 20:
		BancProduitNucleaire.avancer_colon(colon, source, mur, false, 1.0, CONFIG, ETATS, SEUILS_ETAT, EPIGENETIQUE, CATALOGUE_CANAUX)
	verif.v(colon.proprietes.dose_radiation_cumulee > 0.0, "expose en continu, dose_radiation_cumulee doit avoir monte")
	verif.v(abs(colon.proprietes.dose_radiation_cumulee - 20.0 * CONFIG.dose_par_s) < 0.0001, "dose_radiation_cumulee doit egaler exactement dose_par_s * temps expose")

func _colon_hors_de_portee_aucune_dose() -> void:
	var source := _source(0.3, 50.0, 999.0, Vector3(9000, 0, 0))
	var mur := _mur(Vector3.ZERO, 0.0)
	var colon := _colon("c2", Vector3.ZERO)
	for i in 20:
		BancProduitNucleaire.avancer_colon(colon, source, mur, false, 1.0, CONFIG, ETATS, SEUILS_ETAT, EPIGENETIQUE, CATALOGUE_CANAUX)
	verif.v(colon.proprietes.dose_radiation_cumulee == 0.0, "hors de portee, dose_radiation_cumulee ne doit jamais monter")
	verif.v(colon.proprietes.marques_epigenetiques.is_empty(), "hors de portee, aucune marque epigenetique ne doit s'accumuler")

func _nausee_posee_sous_exposition_puis_s_estompe() -> void:
	var source := _source(0.3, 50.0, 999.0, Vector3.ZERO)
	var mur := _mur(Vector3.ZERO, 0.0)
	var colon := _colon("c3", Vector3(50, 0, 0))
	var deja_nauseeux := false
	for i in 20:
		BancProduitNucleaire.avancer_colon(colon, source, mur, false, 1.0, CONFIG, ETATS, SEUILS_ETAT, EPIGENETIQUE, CATALOGUE_CANAUX)
		if colon.proprietes.etats_actifs.has("nausee_radiation"):
			deja_nauseeux = true
	verif.v(deja_nauseeux, "expose sans interruption a une source visible, le colon doit finir par avoir la nausee")

	var source_loin := _source(0.3, 50.0, 999.0, Vector3(9000, 0, 0))
	for i in 20:
		BancProduitNucleaire.avancer_colon(colon, source_loin, mur, false, 1.0, CONFIG, ETATS, SEUILS_ETAT, EPIGENETIQUE, CATALOGUE_CANAUX)
	verif.v(not colon.proprietes.etats_actifs.has("nausee_radiation"), "eloigne de toute source, la nausee doit finir par s'estomper")

func _syndrome_pose_au_seuil_et_reste_permanent() -> void:
	var colon := _colon("c4", Vector3.ZERO, 60.0)
	var bascules := BancProduitNucleaire.avancer_colon(colon, _source(0.0, 50.0, 999.0, Vector3(9000, 0, 0)), _mur(Vector3.ZERO, 0.0), false, 1.0, CONFIG, ETATS, SEUILS_ETAT, EPIGENETIQUE, CATALOGUE_CANAUX)
	verif.v(colon.proprietes.etats_actifs.has("syndrome_radiation"), "dose deja au-dessus de 50.0, syndrome_radiation doit etre pose")
	verif.v(not colon.proprietes.etats_actifs.has("mort_radiation"), "dose 60.0 sous 100.0, mort_radiation ne doit pas etre pose")
	# la dose ne redescend jamais et le colon n'est plus expose : syndrome_radiation doit rester actif.
	for i in 20:
		BancProduitNucleaire.avancer_colon(colon, _source(0.0, 50.0, 999.0, Vector3(9000, 0, 0)), _mur(Vector3.ZERO, 0.0), false, 1.0, CONFIG, ETATS, SEUILS_ETAT, EPIGENETIQUE, CATALOGUE_CANAUX)
	verif.v(colon.proprietes.etats_actifs.has("syndrome_radiation"), "syndrome_radiation doit rester actif en permanence, meme loin de toute source")

func _mort_posee_au_seuil_suivant_vitesse_effective_nulle() -> void:
	var colon := _colon("c5", Vector3.ZERO, 120.0)
	BancProduitNucleaire.avancer_colon(colon, _source(0.0, 50.0, 999.0, Vector3(9000, 0, 0)), _mur(Vector3.ZERO, 0.0), false, 1.0, CONFIG, ETATS, SEUILS_ETAT, EPIGENETIQUE, CATALOGUE_CANAUX)
	verif.v(colon.proprietes.etats_actifs.has("mort_radiation"), "dose 120.0 au-dessus de 100.0, mort_radiation doit etre pose")
	var diag := BancProduitNucleaire.diagnostiquer_colon(colon, ETATS, CONFIG)
	verif.v(diag.vitesse_effective == 0.0, "mort_radiation doit ecraser la vitesse effective a 0.0, obtenu %.2f" % diag.vitesse_effective)
	verif.v(diag.etat == "mort", "diagnostiquer_colon doit resumer l'etat a 'mort'")

func _colon_mort_est_fige_plus_aucun_mecanisme_ne_le_met_a_jour() -> void:
	var colon := _colon("c8", Vector3(50, 0, 0), 120.0)
	verif.v(not BancProduitNucleaire.colon_fige(colon), "un colon avec une dose au-dessus de 100.0 mais sans etat encore pose n'est pas fige avant le premier avancer_colon")

	var source := _source(0.3, 50.0, 999.0, Vector3.ZERO)
	var mur := _mur(Vector3.ZERO, 0.0)
	BancProduitNucleaire.avancer_colon(colon, source, mur, false, 1.0, CONFIG, ETATS, SEUILS_ETAT, EPIGENETIQUE, CATALOGUE_CANAUX)
	verif.v(colon.proprietes.etats_actifs.has("mort_radiation"), "dose deja au-dessus de 100.0, mort_radiation doit basculer des ce premier avancer_colon")
	verif.v(BancProduitNucleaire.colon_fige(colon), "une fois mort_radiation actif, colon_fige doit rendre vrai")

	var objets: Array = []
	var dose_avant: float = colon.proprietes.dose_radiation_cumulee
	var marques_avant: Dictionary = colon.proprietes.marques_epigenetiques.duplicate(true)
	var etats_actifs_avant: Array = colon.proprietes.etats_actifs.duplicate()
	for i in 50:
		BancProduitNucleaire.avancer(source, mur, false, objets, colon, 1.0, CONFIG, ETATS, SEUILS_ETAT, SEUILS_COMBUSTIBLE, EPIGENETIQUE, CATALOGUE_CANAUX, TABLE_TYPES_MIN, MATERIAUX_MIN, TRANSFORMATIONS)
	verif.v(colon.proprietes.dose_radiation_cumulee == dose_avant, "fige, dose_radiation_cumulee ne doit plus jamais bouger, meme expose 50 pas de plus")
	verif.v(colon.proprietes.marques_epigenetiques == marques_avant, "fige, la marque epigenetique ne doit plus jamais bouger (ni s'accumuler, ni decroitre)")
	verif.v(colon.proprietes.etats_actifs == etats_actifs_avant, "fige, etats_actifs ne doit plus jamais changer")

func _marque_epigenetique_accumulee_pendant_l_exposition_puis_persiste() -> void:
	var source := _source(0.3, 50.0, 999.0, Vector3.ZERO)
	var mur := _mur(Vector3.ZERO, 0.0)
	var colon := _colon("c6", Vector3(50, 0, 0))
	for i in 30:
		BancProduitNucleaire.avancer_colon(colon, source, mur, false, 1.0, CONFIG, ETATS, SEUILS_ETAT, EPIGENETIQUE, CATALOGUE_CANAUX)
	var modulateur_expose: float = colon.proprietes.marques_epigenetiques.get("exposition_radioactive", {}).get("modulateur", 0.0)
	verif.v(modulateur_expose > 0.0, "expose, la marque epigenetique doit s'etre accumulee")

	var source_loin := _source(0.3, 50.0, 999.0, Vector3(9000, 0, 0))
	for i in 20:
		BancProduitNucleaire.avancer_colon(colon, source_loin, mur, false, 1.0, CONFIG, ETATS, SEUILS_ETAT, EPIGENETIQUE, CATALOGUE_CANAUX)
	verif.v(not colon.proprietes.get(CONFIG.declencheur_mutation, false), "assez longtemps loin de toute source, le marqueur d'exposition chronique doit s'etre retire")
	var modulateur_marqueur_retire: float = colon.proprietes.marques_epigenetiques.get("exposition_radioactive", {}).get("modulateur", 0.0)
	verif.v(modulateur_marqueur_retire > 0.0, "juste apres le retrait du marqueur, la marque doit encore persister (decroissance lente, jamais un retrait instantane)")

	# Le marqueur retire, la marque ne peut plus que decroitre (Epigenetique.avancer
	# tourne inconditionnellement, jamais plus de Epigenetique.poser) -- laisser passer
	# largement assez de temps pour que la lente decroissance (taux_decroissance) devienne
	# observable, sans dependre du transitoire de retrait du marqueur teste ci-dessus.
	for i in 400:
		BancProduitNucleaire.avancer_colon(colon, source_loin, mur, false, 1.0, CONFIG, ETATS, SEUILS_ETAT, EPIGENETIQUE, CATALOGUE_CANAUX)
	var modulateur_bien_plus_tard: float = colon.proprietes.marques_epigenetiques.get("exposition_radioactive", {}).get("modulateur", 0.0)
	verif.v(modulateur_bien_plus_tard < modulateur_marqueur_retire, "longtemps apres le retrait du marqueur, la marque doit avoir decru")

# ---- Le mur bloque simultanement fer_nucleaire et le colon ----

func _mur_bloque_la_radiation_pour_le_colon() -> void:
	var source := _source(0.3, 50.0, 999.0, Vector3.ZERO)
	var mur := _mur(Vector3(0, -100, 0), 7.87)
	var colon := _colon("c7", Vector3(0, -300, 0))
	for i in 30:
		BancProduitNucleaire.avancer_colon(colon, source, mur, true, 1.0, CONFIG, ETATS, SEUILS_ETAT, EPIGENETIQUE, CATALOGUE_CANAUX)
	verif.v(colon.proprietes.dose_radiation_cumulee == 0.0, "mur actif, EXACTEMENT sur le segment source->colon : aucune dose ne doit s'accumuler")
	verif.v(colon.proprietes.marques_epigenetiques.is_empty(), "mur actif : aucune marque epigenetique ne doit s'accumuler")
	verif.v(not colon.proprietes.etats_actifs.has("nausee_radiation"), "mur actif : le colon ne doit jamais avoir la nausee")

	var bois := _objet_radiation("bois_test", Vector3(200, 0, 0), 0.3)
	for i in 30:
		BancProduitNucleaire.avancer_objets([bois], source, mur, true, 1.0, CONFIG, ETATS, CATALOGUE_CANAUX)
	verif.v(bois.proprietes.etats.radiation.charge > 0.0, "mur actif mais HORS de son segment : bois_test doit s'irradier normalement")

# ---- Chemin REEL : data/banc_produit_nucleaire.json + tous les catalogues ----

func _charger(chemin: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))

func _donnees_reelles_catalogues() -> void:
	var types_json: Dictionary = _charger("res://data/types.json")
	verif.v(types_json.has("residu_radioactif"), "data/types.json doit porter l'entree 'residu_radioactif'")

	var materiaux: Dictionary = _charger("res://data/materiaux.json")
	verif.v(materiaux.has("residu_radioactif") and materiaux.residu_radioactif.has("densite"), "data/materiaux.json doit porter 'residu_radioactif' avec une densite")

	var transformations: Dictionary = _charger("res://data/transformations.json").get("transformations", {})
	verif.v(transformations.has("epuisement_source_radiation"), "data/transformations.json doit porter 'epuisement_source_radiation'")
	verif.v(transformations.epuisement_source_radiation.a_zero.produire.type_produit == "residu_radioactif", "epuisement_source_radiation doit produire 'residu_radioactif'")

	var epigenetique: Dictionary = _charger("res://data/epigenetique.json")
	verif.v(epigenetique.has("exposition_radioactive") and epigenetique.exposition_radioactive.cible == "vitesse", "data/epigenetique.json doit porter 'exposition_radioactive' ciblant 'vitesse'")

	var etats_reels: Dictionary = _charger("res://data/etats.json")
	verif.v(etats_reels.has("nausee_radiation") and etats_reels.nausee_radiation.has("duree"), "data/etats.json doit porter 'nausee_radiation' avec une duree (reversible)")
	verif.v(etats_reels.has("syndrome_radiation") and not etats_reels.syndrome_radiation.has("duree"), "data/etats.json doit porter 'syndrome_radiation' SANS duree (permanent)")
	verif.v(etats_reels.has("mort_radiation") and not etats_reels.mort_radiation.has("duree"), "data/etats.json doit porter 'mort_radiation' SANS duree (permanent)")

	var seuils_etat_reels: Dictionary = _charger("res://data/seuils_etat.json")
	verif.v(seuils_etat_reels.has("syndrome_radiation") and seuils_etat_reels.syndrome_radiation.propriete_continue == "dose_radiation_cumulee", "data/seuils_etat.json doit porter 'syndrome_radiation' sur 'dose_radiation_cumulee'")
	verif.v(seuils_etat_reels.has("mort_radiation") and seuils_etat_reels.mort_radiation.seuil > seuils_etat_reels.syndrome_radiation.seuil, "le seuil de 'mort_radiation' doit etre strictement superieur a celui de 'syndrome_radiation'")

	var seuils_combustible_reels: Dictionary = _charger("res://data/seuils_combustible.json")
	verif.v(seuils_combustible_reels.has("epuisement_radioactivite"), "data/seuils_combustible.json doit porter 'epuisement_radioactivite'")

func _chemin_reel_source_objets_colon() -> void:
	var donnees: Dictionary = _charger("res://data/banc_produit_nucleaire.json")
	var materiaux: Dictionary = _charger("res://data/materiaux.json")
	var etats: Dictionary = _charger("res://data/etats.json")
	var seuils_etat: Dictionary = _charger("res://data/seuils_etat.json")
	var seuils_combustible: Dictionary = _charger("res://data/seuils_combustible.json")
	var epigenetique: Dictionary = _charger("res://data/epigenetique.json")
	var canaux: Dictionary = _charger("res://data/canaux.json")
	var table_types: Dictionary = _charger("res://data/types.json")
	var transformations: Dictionary = _charger("res://data/transformations.json").get("transformations", {})
	var proprietes_immuables: Array = _charger("res://data/proprietes_immuables_composition.json").get("proprietes", [])

	var source := BancProduitNucleaire.fabriquer_source(donnees.source)
	var mur := BancProduitNucleaire.fabriquer_mur(donnees.mur, materiaux, proprietes_immuables)
	var objets := BancProduitNucleaire.fabriquer_objets(donnees.objets, materiaux, proprietes_immuables, donnees)
	var pos_colon: Array = donnees.colon.position
	var colon := BancProduitNucleaire.fabriquer_colon(donnees.colon.id, Vector3(pos_colon[0], pos_colon[1], pos_colon[2]), table_types, donnees)

	verif.v(not colon.is_empty(), "chemin reel : le colon doit se fabriquer sans erreur (type 'colon' + quatre paquets 'herite')")
	verif.v(colon.proprietes.has("marques_epigenetiques"), "chemin reel : le colon fabrique doit deja porter 'marques_epigenetiques' (paquet dynamique)")
	verif.v(colon.proprietes.etats.has("exposition_radioactive") and colon.proprietes.etats.has("nausee_radiation"), "chemin reel : le colon fabrique doit porter les deux canaux neufs sous 'etats'")

	var fer: Dictionary = objets.filter(func(o): return o.id == "fer_nucleaire")[0]

	# Sans mur, assez longtemps : la source finit par se transformer, fer_nucleaire
	# et le colon (tous deux visibles) accumulent des effets ; le mur, une fois
	# active, bloque simultanement fer_nucleaire et le colon (memes tests que
	# banc_radiation.gd, plus les effets 2/3 du colon).
	var source_transformee := false
	for i in 25:
		var r := BancProduitNucleaire.avancer(source, mur, false, objets, colon, 1.0, donnees, etats, seuils_etat, seuils_combustible, epigenetique, canaux, table_types, materiaux, transformations)
		if r.source_transformee:
			source_transformee = true
	verif.v(source_transformee, "chemin reel, sans mur, assez longtemps (reserve 20.0 a cout_base 1.0) : la source doit se transformer")
	verif.v(fer.proprietes.etats.radiation.charge > 0.0, "chemin reel, sans mur : fer_nucleaire doit avoir accumule de la charge de radiation")
	verif.v(colon.proprietes.dose_radiation_cumulee > 0.0, "chemin reel, sans mur : le colon doit avoir accumule de la dose")

	var source2 := BancProduitNucleaire.fabriquer_source(donnees.source)
	var mur2 := BancProduitNucleaire.fabriquer_mur(donnees.mur, materiaux, proprietes_immuables)
	var objets2 := BancProduitNucleaire.fabriquer_objets(donnees.objets, materiaux, proprietes_immuables, donnees)
	var colon2 := BancProduitNucleaire.fabriquer_colon(donnees.colon.id, Vector3(pos_colon[0], pos_colon[1], pos_colon[2]), table_types, donnees)
	for i in 25:
		BancProduitNucleaire.avancer(source2, mur2, true, objets2, colon2, 1.0, donnees, etats, seuils_etat, seuils_combustible, epigenetique, canaux, table_types, materiaux, transformations)
	var fer2: Dictionary = objets2.filter(func(o): return o.id == "fer_nucleaire")[0]
	var bois2: Dictionary = objets2.filter(func(o): return o.id == "bois_nucleaire")[0]
	verif.v(fer2.proprietes.etats.radiation.charge == 0.0, "chemin reel, mur actif : fer_nucleaire (sur le segment du mur) ne doit jamais accumuler de charge")
	verif.v(bois2.proprietes.etats.radiation.charge > 0.0, "chemin reel, mur actif : bois_nucleaire (hors du segment du mur) doit s'irradier normalement")
	verif.v(colon2.proprietes.dose_radiation_cumulee == 0.0, "chemin reel, mur actif : le colon (sur le segment du mur) ne doit jamais accumuler de dose")
