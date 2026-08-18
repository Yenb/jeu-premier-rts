extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_porosite.gd
#
# Verrouille le cablage de banc_porosite.gd -- chantier « banc_porosite --
# un banc transversal » : deux objets identiques sauf sur leur porosite
# (data/materiaux.json:porosite_haute_demo/porosite_basse_demo) exposes en
# meme temps a une source d'humidite (charge.gd, mecanisme reel) ET deja en
# feu (depense.gd/combustible.gd, mecanisme reel) doivent diverger sur LES
# DEUX fronts a la fois, dans le meme sens (le poreux devient mouille en
# premier ET epuise son combustible en premier).
#
# AUCUN MECANISME DU COEUR TOUCHE par ce chantier : charge.gd/etat_duree.gd/
# depense.gd/combustible.gd/temperature.gd/objet.gd restent exactement ceux
# deja verrouilles par leurs propres tests -- ce fichier verrouille
# uniquement banc_porosite.gd.

const BancPorosite = preload("res://scripts/banc_porosite.gd")
const Objet = preload("res://scripts/objet.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

const ETATS := {
	"mouille": {
		"duree": 6.0,
		"effets": [ { "propriete": "inflammabilite", "mode": "ecraser", "valeur": 0.0 } ],
	},
}

const CONFIG := {
	"propriete_cause": "source_humidite",
	"declencheur_expose": "expose_humidite",
	"propriete_absorption": "absorption_humidite",
	"propriete_porosite": "porosite",
	"facteur_porosite": 1.5,
	"nom_etat": "mouille",
	"nom_canal": "humidite",
	"canal_defaut": {
		"charge": 0.0, "seuil": 1.0, "portee_charge": 900.0,
		"taux_decroissance": 0.5, "poser": {"expose_humidite": true},
	},
}

const RESERVE_COMBUSTIBLE := {
	"nom_reserve": "combustible", "propriete_materiau": "pouvoir_calorifique",
	"propriete_porosite": "porosite", "cout_base": 1.0,
	"facteur_densite": 0.5, "facteur_porosite": 1.3,
	"surcout_action": 0.0, "seuils_ref": "epuisement",
}

const SEUILS_COMBUSTIBLE := {
	"epuisement": [ { "seuil": 0.0, "retirer": ["inflammable", "brule", "profil_saillance", "travail_restant", "transformation"] } ],
}

const CATALOGUE_TEMPERATURE := {
	"defaut": { "ambiante": 20.0, "attenuation": { "exposant": 1.0 } },
}

const CONFIG_FEU := { "rayon": 400.0, "temperature": 600.0, "force": 1.0 }

func _init() -> void:
	_causes_de_et_ponderees()
	_porosite_ponderee_lit_depuis_composition()
	_poids_receveur_humidite_croit_avec_la_porosite()
	_basculer_source()
	_sources_chaleur_ne_retient_que_les_objets_en_feu()
	_diagnostiquer_porte_les_sept_champs()
	_hors_domaine_avancer_ignore_le_domaine()
	_a_porosite_egale_les_deux_objets_evoluent_identiquement()
	_source_coupee_l_exposition_redescend_jamais_instantanement()
	_chemin_reel_fabrication_et_capacites()
	_chemin_reel_le_poreux_devient_mouille_et_s_epuise_avant_le_dense()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: causes_de/causes_ponderees/porosite_ponderee/poids_receveur_humidite/" +
		"basculer_source/sources_chaleur/diagnostiquer pures, source coupee l'exposition " +
		"redescend (jamais instantanement retiree), avancer() ignore le domaine, a porosite " +
		"egale les deux objets evoluent EXACTEMENT identiquement (humidite et combustion), " +
		"chemin reel -- fabrication/capacites verifiees, le poreux devient mouille ET " +
		"epuise son combustible STRICTEMENT avant le dense, la meme porosite cause les deux ecarts")
	quit(0)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))

# ---- Fonctions pures ----

func _causes_de_et_ponderees() -> void:
	var objets := [
		{"id": "a", "position": Vector3.ZERO, "proprietes": {"source_humidite": true}},
		{"id": "b", "position": Vector3(5, 0, 0), "proprietes": {"source_humidite": false}},
	]
	var causes := BancPorosite.causes_de(objets, "source_humidite")
	verif.v(causes.size() == 1 and causes[0].position == Vector3.ZERO, "causes_de doit retenir uniquement les objets portant propriete_cause a vrai")

	var ponderees := BancPorosite.causes_ponderees(causes, 0.4)
	verif.v(ponderees.size() == 1 and abs(ponderees[0].poids - 0.4) < 0.0001, "causes_ponderees doit multiplier le poids implicite (1.0) par le facteur donne")

func _objet_avec_composition(id: String, position: Vector3, composition: Array, absorption: float, temperature: float, brule: bool, canal: Dictionary) -> Dictionary:
	return {
		"id": id,
		"position": position,
		"proprietes": {
			"composition": composition,
			"absorption_humidite": absorption,
			"temperature": temperature,
			"brule": brule,
			"etats": {"humidite": canal.duplicate(true)},
			"etats_actifs": [],
		},
	}

func _porosite_ponderee_lit_depuis_composition() -> void:
	var materiaux_test := {"materiau_poreux": {"porosite": 0.9}, "materiau_dense": {"porosite": 0.05}}
	var objet := _objet_avec_composition("x", Vector3.ZERO, [{"materiau": "materiau_poreux", "volume": 1.0}], 0.5, 20.0, true, CONFIG.canal_defaut)
	verif.v(abs(BancPorosite.porosite_ponderee(objet, materiaux_test, "porosite") - 0.9) < 0.0001, "porosite_ponderee doit lire la porosite de la fiche materiau resolue")
	verif.v(BancPorosite.porosite_ponderee({"proprietes": {}}, materiaux_test, "porosite") == 0.0, "sans composition, porosite_ponderee doit rendre 0.0 -- chemin mort")
	verif.v(BancPorosite.porosite_ponderee(objet, materiaux_test, "") == 0.0, "propriete_porosite vide doit rendre 0.0")

func _poids_receveur_humidite_croit_avec_la_porosite() -> void:
	var materiaux_test := {"materiau_poreux": {"porosite": 0.9}, "materiau_dense": {"porosite": 0.05}}
	var config := CONFIG.duplicate(true)
	var poreux := _objet_avec_composition("poreux", Vector3.ZERO, [{"materiau": "materiau_poreux", "volume": 1.0}], 0.5, 20.0, true, CONFIG.canal_defaut)
	var dense := _objet_avec_composition("dense", Vector3.ZERO, [{"materiau": "materiau_dense", "volume": 1.0}], 0.5, 20.0, true, CONFIG.canal_defaut)
	var poids_poreux := BancPorosite.poids_receveur_humidite(poreux, materiaux_test, config)
	var poids_dense := BancPorosite.poids_receveur_humidite(dense, materiaux_test, config)
	verif.v(poids_poreux > poids_dense, "a absorption_humidite egale, le poids receveur doit croitre avec la porosite")
	verif.v(abs(poids_poreux - 0.5 * (1.0 + 1.5 * 0.9)) < 0.0001, "formule exacte : absorption * (1 + facteur_porosite * porosite)")

# Meme geste que test_banc_humidite.gd:_basculer_source -- pure, inverse
# uniquement la cause sur le Dictionary source recu.
func _basculer_source() -> void:
	var source := {"id": "source", "position": Vector3.ZERO, "proprietes": {"source_humidite": true}}
	BancPorosite.basculer_source(source, "source_humidite")
	verif.v(not source.proprietes.source_humidite, "basculer_source doit inverser true -> false")
	BancPorosite.basculer_source(source, "source_humidite")
	verif.v(source.proprietes.source_humidite, "basculer_source doit inverser false -> true")

func _sources_chaleur_ne_retient_que_les_objets_en_feu() -> void:
	var objets := [
		{"id": "allume", "position": Vector3(10, 0, 0), "proprietes": {"brule": true}},
		{"id": "eteint", "position": Vector3(20, 0, 0), "proprietes": {"brule": false}},
		{"id": "jamais_allume", "position": Vector3(30, 0, 0), "proprietes": {}},
	]
	var sources := BancPorosite.sources_chaleur(objets, CONFIG_FEU)
	verif.v(sources.size() == 1, "seul l'objet 'brule' doit rayonner")
	verif.v(sources[0].position == Vector3(10, 0, 0), "la source doit rayonner depuis la position de l'objet en feu")
	verif.v(sources[0].rayon == 400.0 and sources[0].temperature == 600.0 and sources[0].force == 1.0, "la source doit reprendre le profil rayon/temperature/force de config_feu")

func _diagnostiquer_porte_les_sept_champs() -> void:
	var objet := {
		"id": "x", "position": Vector3.ZERO,
		"proprietes": {
			"composition": [{"materiau": "materiau_poreux", "volume": 1.0}],
			"etats": {"humidite": {"charge": 0.4, "seuil": 1.0}},
			"etats_actifs": ["mouille"],
			"reserves": {"combustible": {"capacite": 3.0, "reserve": 1.5}},
			"temperature": 55.0,
			"brule": true,
		},
	}
	var materiaux_test := {"materiau_poreux": {"porosite": 0.9}}
	var diag := BancPorosite.diagnostiquer(objet, CONFIG, ETATS, materiaux_test, "combustible")
	verif.v(abs(diag.porosite - 0.9) < 0.0001, "diagnostiquer doit porter la porosite ponderee")
	verif.v(diag.mouille == true, "diagnostiquer doit porter l'etat mouille")
	verif.v(abs(diag.charge - 0.4) < 0.0001 and abs(diag.seuil - 1.0) < 0.0001, "diagnostiquer doit porter charge et seuil du canal d'humidite")
	verif.v(abs(diag.reserve_absolu - 1.5) < 0.0001 and abs(diag.reserve_proportion - 0.5) < 0.0001, "diagnostiquer doit deleguer a Combustible.restant, jamais reimplementer sa loi")
	verif.v(abs(diag.temperature - 55.0) < 0.0001, "diagnostiquer doit porter la temperature courante")
	verif.v(diag.brule == true, "diagnostiquer doit porter l'etat brule")

# Un canal/declencheur/etat/reserve/catalogue de temperature inventes, sans
# aucun rapport avec l'humidite/le feu/la porosite, doivent traverser
# EXACTEMENT le meme code -- meme serrure que test_banc_humidite.gd:
# _hors_domaine_avancer_ignore_le_domaine.
func _hors_domaine_avancer_ignore_le_domaine() -> void:
	var config_invente := {
		"propriete_cause": "emet_zorglonium", "declencheur_expose": "irradie_zorglonium",
		"propriete_absorption": "sensibilite_zorglonium", "propriete_porosite": "densite_cristalline",
		"facteur_porosite": 2.0, "nom_etat": "contamine", "nom_canal": "zorglonium",
		"canal_defaut": {"charge": 0.0, "seuil": 1.0, "portee_charge": 900.0, "taux_decroissance": 0.5, "poser": {"irradie_zorglonium": true}},
	}
	var etats_invente := {
		"contamine": {"duree": 20.0, "effets": [ { "propriete": "resistance", "mode": "ecraser", "valeur": 0.0 } ] },
	}
	var reserve_invente := {
		"nom_reserve": "energie_gravitique", "propriete_materiau": "charge_gravitique",
		"propriete_porosite": "densite_cristalline", "cout_base": 1.0,
		"facteur_densite": 0.5, "facteur_porosite": 1.0,
		"surcout_action": 0.0, "seuils_ref": "epuisement_gravitique",
	}
	var seuils_invente := {
		"epuisement_gravitique": [ { "seuil": 0.0, "retirer": ["rayonne"] } ],
	}
	var catalogue_temperature_invente := {"defaut": {"ambiante": -50.0, "attenuation": {"exposant": 1.0}}}
	var config_feu_invente := {"rayon": 100.0, "temperature": 200.0, "force": 1.0}

	var materiaux_avec_charge := {"cristal_gravitique": {"densite": 2.0, "densite_cristalline": 0.8, "charge_gravitique": 0.6}}
	var declarations := [{"id": "cristal", "position": [0.0, 0.0, 0.0], "composition": [{"materiau": "cristal_gravitique", "volume": 4.0}]}]
	var objets := BancPorosite.fabriquer_objets(declarations, materiaux_avec_charge, [], reserve_invente, config_invente, -50.0)
	verif.v(objets.size() == 1, "un catalogue/materiau invente doit tout de meme fabriquer un objet, sans nom de domaine en dur")
	var cristal: Dictionary = objets[0]
	cristal.proprietes["rayonne"] = true
	cristal.proprietes["sensibilite_zorglonium"] = 1.0

	var emetteur := {"id": "emetteur", "position": Vector3.ZERO, "proprietes": {"emet_zorglonium": true}}
	for i in 40:
		BancPorosite.avancer(objets, emetteur, 0.5, config_invente, etats_invente, materiaux_avec_charge, seuils_invente, config_feu_invente, catalogue_temperature_invente)
	verif.v(cristal.proprietes.etats_actifs.has("contamine"), "un canal/declencheur/etat invente doit traverser avancer() sans ligne ajoutee, exactement comme 'mouille'")
	verif.v(not cristal.proprietes.get("rayonne", false), "le canal de reserve invente doit s'epuiser et retirer sa propre cle, exactement comme 'brule'")

# Chantier "banc_porosite" : a porosite STRICTEMENT egale (deux materiaux
# fictifs partageant absorption_humidite/porosite/pouvoir_calorifique/
# densite), a distance identique de la meme source, deux objets doivent
# evoluer EXACTEMENT identiquement, tick par tick, sur les deux fronts --
# non-regression qui prouve que seule la porosite explique tout ecart mesure
# dans _chemin_reel_le_poreux_devient_mouille_et_s_epuise_avant_le_dense.
func _a_porosite_egale_les_deux_objets_evoluent_identiquement() -> void:
	var materiaux_test := {
		"materiau_a": {"densite": 1.0, "porosite": 0.5, "absorption_humidite": 0.5, "pouvoir_calorifique": 0.5},
		"materiau_b": {"densite": 1.0, "porosite": 0.5, "absorption_humidite": 0.5, "pouvoir_calorifique": 0.5},
	}
	var declarations := [
		{"id": "a", "position": [100.0, 0.0, 0.0], "composition": [{"materiau": "materiau_a", "volume": 6.0}]},
		{"id": "b", "position": [-100.0, 0.0, 0.0], "composition": [{"materiau": "materiau_b", "volume": 6.0}]},
	]
	var config := CONFIG.duplicate(true)
	config["canal_defaut"] = {"charge": 0.0, "seuil": 1.0, "portee_charge": 900.0, "taux_decroissance": 0.5, "poser": {"expose_humidite": true}}
	var objets := BancPorosite.fabriquer_objets(declarations, materiaux_test, ["absorption_humidite"], RESERVE_COMBUSTIBLE, config, 20.0)
	verif.v(objets.size() == 2, "les deux objets a porosite egale doivent se fabriquer")
	var source := {"id": "source", "position": Vector3(0, 200.0, 0), "proprietes": {"source_humidite": true}}

	for i in 40:
		BancPorosite.avancer(objets, source, 0.1, config, ETATS, materiaux_test, SEUILS_COMBUSTIBLE, CONFIG_FEU, CATALOGUE_TEMPERATURE)
		var a: Dictionary = objets[0]
		var b: Dictionary = objets[1]
		verif.v(abs(a.proprietes.etats.humidite.charge - b.proprietes.etats.humidite.charge) < 0.0001, "a porosite egale, la charge d'humidite doit rester IDENTIQUE tick par tick (i=%d)" % i)
		verif.v(abs(a.proprietes.reserves.combustible.reserve - b.proprietes.reserves.combustible.reserve) < 0.0001, "a porosite egale, la reserve de combustible doit rester IDENTIQUE tick par tick (i=%d)" % i)
		verif.v(abs(a.proprietes.temperature - b.proprietes.temperature) < 0.0001, "a porosite egale et positions symetriques, la temperature doit rester IDENTIQUE tick par tick (i=%d)" % i)

# Chantier "eau activable/desactivable" (retour Yael) : meme geste que
# test_banc_humidite.gd:_source_retiree_objet_seche_progressivement_
# jamais_instantanement -- basculer_source coupe l'exposition, la charge
# redescend et "expose_humidite" se retire vite (taux_decroissance), mais
# "mouille" ne doit JAMAIS etre retire instantanement -- seul EtatDuree.
# avancer le fait, progressivement (6.0s, data/etats.json:mouille.duree).
func _source_coupee_l_exposition_redescend_jamais_instantanement() -> void:
	var objet := {
		"id": "x", "position": Vector3(100, 0, 0),
		"proprietes": {
			"absorption_humidite": 0.7, "temperature": 20.0, "brule": false,
			"etats": {"humidite": CONFIG.canal_defaut.duplicate(true)},
			"etats_actifs": [],
		},
	}
	var source := {"id": "source", "position": Vector3.ZERO, "proprietes": {"source_humidite": true}}

	for i in 15:
		BancPorosite.avancer([objet], source, 0.1, CONFIG, ETATS, {}, {}, CONFIG_FEU, CATALOGUE_TEMPERATURE)
	verif.v(objet.proprietes.get("expose_humidite", false), "avant bascule, l'objet doit etre expose (charge > seuil)")
	verif.v(objet.proprietes.etats_actifs.has("mouille"), "avant bascule, l'objet doit etre mouille")

	BancPorosite.basculer_source(source, CONFIG.propriete_cause)
	verif.v(not source.proprietes.source_humidite, "basculer_source doit desactiver une source active")

	for i in 3:
		BancPorosite.avancer([objet], source, 0.5, CONFIG, ETATS, {}, {}, CONFIG_FEU, CATALOGUE_TEMPERATURE)
	verif.v(not objet.proprietes.get("expose_humidite", false), "source coupee, expose_humidite doit se retirer rapidement (charge sous le seuil, taux_decroissance)")
	verif.v(objet.proprietes.etats_actifs.has("mouille"), "expose_humidite retire ne doit PAS retirer 'mouille' instantanement -- seul EtatDuree.avancer le fait, progressivement")

	for i in 12:
		BancPorosite.avancer([objet], source, 0.5, CONFIG, ETATS, {}, {}, CONFIG_FEU, CATALOGUE_TEMPERATURE)
	verif.v(not objet.proprietes.etats_actifs.has("mouille"), "apres 6.0s ecoulees sans exposition, 'mouille' doit avoir ete retire par EtatDuree.avancer")

# ---- Chemin reel : data/banc_porosite.json / data/materiaux.json /
# data/proprietes_immuables_composition.json / data/reserve_combustible_
# composition.json / data/seuils_combustible.json / data/etats.json /
# data/temperature.json lus sur disque.

func _chemin_reel_fabrication_et_capacites() -> void:
	var config := _charger_json("res://data/banc_porosite.json")
	var materiaux := _charger_json("res://data/materiaux.json")
	var proprietes_immuables: Array = _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", [])
	var reserve_combustible := _charger_json("res://data/reserve_combustible_composition.json")

	verif.v(config.objets.size() == 2, "data/banc_porosite.json doit declarer exactement deux objets")
	verif.v(materiaux.has("porosite_haute_demo") and materiaux.has("porosite_basse_demo"), "materiaux.json doit porter les deux materiaux de demonstration")
	verif.v(is_equal_approx(materiaux.porosite_haute_demo.absorption_humidite, materiaux.porosite_basse_demo.absorption_humidite), "les deux materiaux doivent partager la meme absorption_humidite")
	verif.v(is_equal_approx(materiaux.porosite_haute_demo.inflammabilite, materiaux.porosite_basse_demo.inflammabilite), "les deux materiaux doivent partager la meme inflammabilite")
	verif.v(is_equal_approx(materiaux.porosite_haute_demo.pouvoir_calorifique, materiaux.porosite_basse_demo.pouvoir_calorifique), "les deux materiaux doivent partager le meme pouvoir_calorifique")
	verif.v(is_equal_approx(materiaux.porosite_haute_demo.conductivite_thermique, materiaux.porosite_basse_demo.conductivite_thermique), "les deux materiaux doivent partager la meme conductivite_thermique")
	verif.v(is_equal_approx(materiaux.porosite_haute_demo.densite, materiaux.porosite_basse_demo.densite), "les deux materiaux doivent partager la meme densite")
	verif.v(materiaux.porosite_haute_demo.porosite > materiaux.porosite_basse_demo.porosite, "seule la porosite doit diverger, dans le sens haute > basse")

	var ambiante: float = _charger_json("res://data/temperature.json").defaut.ambiante
	var objets := BancPorosite.fabriquer_objets(config.objets, materiaux, proprietes_immuables, reserve_combustible, config, ambiante)
	verif.v(objets.size() == 2, "les deux objets reels doivent se fabriquer")

	var haute := BancPorosite._par_id(objets, "porosite_haute")
	var basse := BancPorosite._par_id(objets, "porosite_basse")
	verif.v(not haute.is_empty() and not basse.is_empty(), "porosite_haute et porosite_basse doivent tous deux exister")
	verif.v(is_equal_approx(haute.proprietes.reserves.combustible.capacite, basse.proprietes.reserves.combustible.capacite), "meme volume et meme pouvoir_calorifique -- la CAPACITE doit etre IDENTIQUE pour les deux, seule la vitesse doit differer")
	verif.v(haute.proprietes.reserves.combustible.cout_base > basse.proprietes.reserves.combustible.cout_base, "a densite egale, la porosite plus haute doit produire un cout_base EFFECTIF plus haut (combustion plus rapide)")
	verif.v(haute.proprietes.get("brule", false) and basse.proprietes.get("brule", false), "les deux objets doivent demarrer deja en feu")
	var poids_haute := BancPorosite.poids_receveur_humidite(haute, materiaux, config)
	var poids_basse := BancPorosite.poids_receveur_humidite(basse, materiaux, config)
	verif.v(poids_haute > poids_basse, "a absorption_humidite egale, le poids receveur d'humidite doit etre plus haut pour porosite_haute")

func _chemin_reel_le_poreux_devient_mouille_et_s_epuise_avant_le_dense() -> void:
	var config := _charger_json("res://data/banc_porosite.json")
	var materiaux := _charger_json("res://data/materiaux.json")
	var proprietes_immuables: Array = _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", [])
	var reserve_combustible := _charger_json("res://data/reserve_combustible_composition.json")
	var seuils_combustible := _charger_json("res://data/seuils_combustible.json")
	var etats := _charger_json("res://data/etats.json")
	var catalogue_temperature := _charger_json("res://data/temperature.json")
	var ambiante: float = catalogue_temperature.defaut.ambiante

	var objets := BancPorosite.fabriquer_objets(config.objets, materiaux, proprietes_immuables, reserve_combustible, config, ambiante)
	var pos_source: Array = config.source_humidite.position
	var source := {
		"id": config.source_humidite.id,
		"position": Vector3(pos_source[0], pos_source[1], pos_source[2]),
		"proprietes": {config.propriete_cause: true},
	}

	var tick_mouille: Dictionary = {}
	var tick_extinction: Dictionary = {}
	var pas := 0.05
	for i in 400:
		var t: float = float(i) * pas
		var resultat := BancPorosite.avancer(objets, source, pas, config, etats, materiaux, seuils_combustible, config.feu, catalogue_temperature)
		for id in resultat.extinctions:
			if not tick_extinction.has(id):
				tick_extinction[id] = t
		for objet in objets:
			if objet.proprietes.etats_actifs.has(config.nom_etat) and not tick_mouille.has(objet.id):
				tick_mouille[objet.id] = t
		if tick_extinction.size() == objets.size() and tick_mouille.size() == objets.size():
			break

	verif.v(tick_mouille.has("porosite_haute") and tick_mouille.has("porosite_basse"), "les deux objets doivent finir par devenir mouilles dans la fenetre d'observation")
	verif.v(tick_extinction.has("porosite_haute") and tick_extinction.has("porosite_basse"), "les deux objets doivent finir par s'eteindre (combustible epuise) dans la fenetre d'observation")
	verif.v(tick_mouille.porosite_haute < tick_mouille.porosite_basse, "porosite_haute doit devenir mouille STRICTEMENT avant porosite_basse -- meme porosite qui cause l'ecart d'humidite")
	verif.v(tick_extinction.porosite_haute < tick_extinction.porosite_basse, "porosite_haute doit epuiser son combustible STRICTEMENT avant porosite_basse -- MEME porosite qui cause l'ecart de combustion")

	for objet in objets:
		verif.v(not objet.proprietes.get("brule", false), "%s doit avoir 'brule' retire une fois eteint" % objet.id)
		verif.v(objet.proprietes.reserves.combustible.reserve == 0.0, "%s doit avoir une reserve residuelle exactement nulle une fois eteint" % objet.id)
