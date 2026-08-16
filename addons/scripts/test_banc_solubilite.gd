extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_solubilite.gd
#
# Verrouille le cablage de banc_solubilite.gd -- les DEUX phases :
# 1. charge.gd (canal d'humidite, un appel par objet pondere par
#    absorption_humidite du receveur) + EtatDuree.poser/avancer (pose de
#    l'etat PARTAGE "mouille" tant que l'objet reste expose, sechage
#    progressif une fois la source coupee) ;
# 2. depense.gd (reserve "integrite", cout_base gele a 0.0 tant que
#    "mouille" est absent, PROPORTIONNEL a solubilite tant que "mouille"
#    est actif) + produit.gd (transformer, appele DIRECTEMENT par ce
#    fichier au franchissement du seuil terminal -- depense.gd lui-meme
#    n'a pas de branche "produire").
#
# AUCUN MECANISME DU COEUR TOUCHE par ce chantier : charge.gd/etat_duree.gd/
# etat_effectif.gd/depense.gd/produit.gd/extinction.gd/objet.gd/
# banc_humidite.gd restent exactement ceux deja verrouilles par leurs
# propres tests -- ce fichier verrouille uniquement banc_solubilite.gd.

const BancSolubilite = preload("res://scripts/banc_solubilite.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")
const EtatDuree = preload("res://scripts/etat_duree.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

const ETATS := {
	"mouille": {
		"duree": 6.0,
		"effets": [
			{ "propriete": "inflammabilite", "mode": "ecraser", "valeur": 0.0 },
		],
	},
}

const CONFIG := {
	"propriete_cause": "source_humidite",
	"declencheur_expose": "expose_humidite",
	"propriete_absorption": "absorption_humidite",
	"propriete_solubilite": "solubilite",
	"nom_etat": "mouille",
	"nom_canal": "humidite",
	"nom_reserve_integrite": "integrite",
	"facteur_dissolution": 1.0,
	"marqueur_terminal": "dissolution_totale",
}

const CATALOGUE_SEUILS_INTEGRITE := {
	"epuisement_solubilite": [
		{ "seuil": 0.0, "poser": { "dissolution_totale": true } },
	],
}

const CONFIG_PRODUIRE := {
	"type_produit": "residu_test",
	"rendement": 0.02,
}

const TABLE := {
	"residu_test": { "composition": [ { "materiau": "residu_test_mat", "volume": 1.0 } ] },
}

const MATERIAUX_LOCAUX := {
	"residu_test_mat": { "densite": 0.3 },
}

func _init() -> void:
	_sans_source_rien_ne_bouge()
	_objet_a_portee_devient_mouille_et_integrite_decroit()
	_objet_hors_portee_reste_sec()
	_solubilite_nulle_ne_dissout_jamais()
	_source_retiree_mouille_seche_progressivement_objet_sauve()
	_reserve_integrite_epuisee_transforme_en_residu()
	_vitesse_dissolution_proportionnelle_a_solubilite()
	_hors_domaine_avancer_ignore_le_domaine()
	_causes_de_et_ponderees()
	_basculer_source()
	_fabrication_reelle_fusionne_solubilite_et_absorption_depuis_materiaux_json()
	_chemin_reel_sel_se_dissout_et_pierre_jamais()
	_donnees_reelles_banc_solubilite_json()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: sans source rien ne bouge, un objet a portee monte et devient mouille puis son integrite decroit, " +
		"un objet hors portee reste sec, une solubilite nulle ne dissout jamais (meme mouille), la source retiree " +
		"seche progressivement (objet sauve avant l'epuisement), la reserve d'integrite epuisee transforme " +
		"l'objet en residu (masse exacte au rendement), la vitesse de dissolution est exactement proportionnelle " +
		"a solubilite, avancer() ignore le domaine, causes_de/causes_ponderees/basculer_source purs, la " +
		"fabrication reelle fusionne solubilite/absorption_humidite depuis materiaux.json, le chemin reel " +
		"sel/pierre se comporte comme attendu, et data/banc_solubilite.json charge correctement")
	quit(0)

func _objet(id: String, position: Vector3, absorption: float, solubilite: float, masse: float, canal: Dictionary, reserve_integrite: Dictionary) -> Dictionary:
	return {
		"id": id,
		"position": position,
		"proprietes": {
			"absorption_humidite": absorption,
			"solubilite": solubilite,
			"inflammabilite": 0.0,
			"masse": masse,
			"etats": {"humidite": canal.duplicate(true)},
			"etats_actifs": [],
			"reserves": {"integrite": reserve_integrite.duplicate(true)},
		},
	}

func _canal(seuil: float, portee: float, taux_decroissance: float) -> Dictionary:
	return {
		"charge": 0.0, "seuil": seuil, "portee_charge": portee,
		"taux_decroissance": taux_decroissance, "poser": {"expose_humidite": true},
	}

func _reserve_integrite(reserve: float) -> Dictionary:
	return {
		"reserve": reserve, "cout_base": 0.0, "surcout_action": 0.0,
		"seuils_ref": "epuisement_solubilite",
	}

func _source(active: bool) -> Dictionary:
	return {"id": "source", "position": Vector3.ZERO, "proprietes": {"source_humidite": active}}

func _sans_source_rien_ne_bouge() -> void:
	var objet := _objet("sel", Vector3(100, 0, 0), 0.6, 0.9, 100.0, _canal(1.0, 900.0, 0.5), _reserve_integrite(5.0))
	var source := _source(false)
	for i in 10:
		BancSolubilite.avancer([objet], source, 1.0, CONFIG, ETATS, CATALOGUE_SEUILS_INTEGRITE, CONFIG_PRODUIRE, TABLE, MATERIAUX_LOCAUX)
	verif.v(objet.proprietes.etats.humidite.charge == 0.0, "sans source active, la charge d'humidite doit rester a 0.0")
	verif.v(not objet.proprietes.get("expose_humidite", false), "sans source active, expose_humidite ne doit jamais etre pose")
	verif.v(objet.proprietes.etats_actifs.is_empty(), "sans source active, aucun etat ne doit etre pose")
	verif.v(objet.proprietes.reserves.integrite.reserve == 5.0, "sans humidite, la reserve d'integrite ne doit jamais decroitre")

func _objet_a_portee_devient_mouille_et_integrite_decroit() -> void:
	var objet := _objet("sel", Vector3(100, 0, 0), 0.6, 0.9, 100.0, _canal(1.0, 900.0, 0.5), _reserve_integrite(5.0))
	var source := _source(true)
	for i in 20:
		BancSolubilite.avancer([objet], source, 0.1, CONFIG, ETATS, CATALOGUE_SEUILS_INTEGRITE, CONFIG_PRODUIRE, TABLE, MATERIAUX_LOCAUX)
	verif.v(objet.proprietes.get("expose_humidite", false), "apres exposition suffisante (charge > seuil), expose_humidite doit etre pose")
	verif.v(objet.proprietes.etats_actifs.has("mouille"), "expose_humidite pose doit avoir declenche EtatDuree.poser('mouille')")
	verif.v(objet.proprietes.etats_intensite.get("mouille", 0.0) > 0.9, "juste apres la pose, l'intensite doit rester tres proche de 1.0")
	verif.v(objet.proprietes.reserves.integrite.reserve < 5.0, "une fois mouille, la reserve d'integrite doit avoir commence a decroitre")

func _objet_hors_portee_reste_sec() -> void:
	var objet := _objet("loin", Vector3(2000, 0, 0), 0.9, 0.9, 100.0, _canal(1.0, 50.0, 0.5), _reserve_integrite(5.0))
	var source := _source(true)
	for i in 20:
		BancSolubilite.avancer([objet], source, 1.0, CONFIG, ETATS, CATALOGUE_SEUILS_INTEGRITE, CONFIG_PRODUIRE, TABLE, MATERIAUX_LOCAUX)
	verif.v(objet.proprietes.etats.humidite.charge == 0.0, "hors de portee_charge, la charge doit rester a 0.0 quelle que soit l'absorption")
	verif.v(objet.proprietes.etats_actifs.is_empty(), "hors de portee_charge, l'objet ne doit jamais devenir mouille")
	verif.v(objet.proprietes.reserves.integrite.reserve == 5.0, "hors de portee_charge, la reserve d'integrite ne doit jamais decroitre")

# "solubilite 0.0 ne dissout jamais" : l'objet devient MOUILLE normalement
# (absorption elevee), mais sa solubilite exactement nulle doit laisser sa
# reserve d'integrite parfaitement intacte, meme apres cent ticks mouille.
func _solubilite_nulle_ne_dissout_jamais() -> void:
	var objet := _objet("insoluble", Vector3(100, 0, 0), 0.9, 0.0, 100.0, _canal(1.0, 900.0, 0.5), _reserve_integrite(5.0))
	var source := _source(true)
	for i in 100:
		BancSolubilite.avancer([objet], source, 1.0, CONFIG, ETATS, CATALOGUE_SEUILS_INTEGRITE, CONFIG_PRODUIRE, TABLE, MATERIAUX_LOCAUX)
	verif.v(objet.proprietes.etats_actifs.has("mouille"), "l'objet doit bien devenir mouille (absorption elevee) malgre une solubilite nulle")
	verif.v(objet.proprietes.reserves.integrite.reserve == 5.0, "solubilite 0.0, meme mouille pendant cent ticks, la reserve d'integrite ne doit jamais decroitre")
	verif.v(objet.proprietes.masse == 100.0, "solubilite 0.0, la masse ne doit jamais changer -- jamais transforme")

func _source_retiree_mouille_seche_progressivement_objet_sauve() -> void:
	# Reserve genereuse expres : ce test verifie qu'un objet SAUVE A TEMPS
	# ne se transforme jamais -- il faut donc plus de reserve que ce que
	# "mouille" peut consommer meme s'il decroit pendant les 6.0s completes
	# de sa duree (cout_base reste actif tant que "mouille" figure dans
	# etats_actifs, quelle que soit son intensite -- voir avancer()).
	var objet := _objet("sel", Vector3(100, 0, 0), 0.6, 0.9, 100.0, _canal(1.0, 900.0, 0.5), _reserve_integrite(30.0))
	var source := _source(true)
	for i in 20:
		BancSolubilite.avancer([objet], source, 0.1, CONFIG, ETATS, CATALOGUE_SEUILS_INTEGRITE, CONFIG_PRODUIRE, TABLE, MATERIAUX_LOCAUX)
	verif.v(objet.proprietes.etats_actifs.has("mouille"), "l'objet doit d'abord etre mouille avant de pouvoir secher")
	var reserve_avant_coupure: float = objet.proprietes.reserves.integrite.reserve
	verif.v(reserve_avant_coupure < 30.0 and reserve_avant_coupure > 0.0, "la reserve d'integrite doit avoir commence a decroitre pendant l'exposition, sans etre epuisee")

	BancSolubilite.basculer_source(source, CONFIG.propriete_cause)
	verif.v(not source.proprietes.source_humidite, "basculer_source doit desactiver une source active")

	# charge (taux_decroissance 0.5/s) redescend vite sous le seuil -- le
	# marqueur expose_humidite doit se retirer BIEN AVANT que "mouille" ne
	# soit retire par la decroissance lente d'EtatDuree (6.0s).
	for i in 3:
		BancSolubilite.avancer([objet], source, 0.5, CONFIG, ETATS, CATALOGUE_SEUILS_INTEGRITE, CONFIG_PRODUIRE, TABLE, MATERIAUX_LOCAUX)
	verif.v(not objet.proprietes.get("expose_humidite", false), "source coupee, expose_humidite doit se retirer rapidement (charge sous le seuil)")
	verif.v(objet.proprietes.etats_actifs.has("mouille"), "expose_humidite retire ne doit PAS retirer 'mouille' instantanement -- seul EtatDuree.avancer le fait, progressivement")
	verif.v(objet.proprietes.reserves.integrite.reserve <= reserve_avant_coupure, "'mouille' encore actif juste apres la coupure : la reserve d'integrite doit continuer de decroitre (ou rester egale au pas pres), jamais remonter")

	# Ecoule le reste de la duree (6.0s) pour atteindre le retrait complet
	# de "mouille" -- le cout_base de la reserve d'integrite doit alors se
	# regeler a 0.0, la reserve reste FIGEE la ou elle en etait.
	for i in 15:
		BancSolubilite.avancer([objet], source, 0.5, CONFIG, ETATS, CATALOGUE_SEUILS_INTEGRITE, CONFIG_PRODUIRE, TABLE, MATERIAUX_LOCAUX)
	verif.v(not objet.proprietes.etats_actifs.has("mouille"), "apres 6.0s ecoulees sans exposition, 'mouille' doit avoir ete retire par EtatDuree.avancer")
	verif.v(objet.proprietes.reserves.integrite.reserve > 0.0, "l'objet seche AVANT l'epuisement de sa reserve d'integrite doit rester sauve -- jamais transforme")
	verif.v(objet.proprietes.masse == 100.0, "objet sauve : la masse ne doit jamais avoir change, jamais transforme en residu")
	var reserve_finale: float = objet.proprietes.reserves.integrite.reserve
	for i in 20:
		BancSolubilite.avancer([objet], source, 0.5, CONFIG, ETATS, CATALOGUE_SEUILS_INTEGRITE, CONFIG_PRODUIRE, TABLE, MATERIAUX_LOCAUX)
	verif.v(objet.proprietes.reserves.integrite.reserve == reserve_finale, "'mouille' absent et source coupee : la reserve d'integrite doit rester FIGEE indefiniment (cout_base regele a 0.0), jamais reprendre sa decroissance seule")

func _reserve_integrite_epuisee_transforme_en_residu() -> void:
	var objet := _objet("sel", Vector3(100, 0, 0), 0.6, 0.9, 100.0, _canal(1.0, 900.0, 0.5), _reserve_integrite(5.0))
	var source := _source(true)
	var resultat: Dictionary = {}
	var transforme_a_ce_tick := false
	for i in 40:
		resultat = BancSolubilite.avancer([objet], source, 0.5, CONFIG, ETATS, CATALOGUE_SEUILS_INTEGRITE, CONFIG_PRODUIRE, TABLE, MATERIAUX_LOCAUX)
		if resultat.transformes.has("sel"):
			transforme_a_ce_tick = true
			break
	verif.v(transforme_a_ce_tick, "expose sans interruption, la reserve d'integrite doit finir par s'epuiser et transformer l'objet")
	verif.v(not objet.proprietes.has("etats"), "un objet transforme ne doit plus porter 'etats' -- proprietes entierement remplacees")
	verif.v(not objet.proprietes.has("reserves"), "un objet transforme ne doit plus porter 'reserves' -- proprietes entierement remplacees")
	verif.v(not objet.proprietes.has("dissolution_totale"), "un objet transforme ne doit plus porter le marqueur terminal -- proprietes entierement remplacees")
	verif.v(objet.proprietes.composition[0].materiau == "residu_test_mat", "l'objet transforme doit porter la composition du type_produit configure")
	verif.v(abs(objet.proprietes.masse - 100.0 * 0.02) < 0.01, "la masse produite doit valoir exactement rendement * masse_ancien, jamais posee a la main")

	# Un objet deja transforme ne porte plus "etats"/"reserves" -- un pas
	# supplementaire ne doit produire aucune erreur ni aucun second passage
	# par Produit.transformer (chemin mort garanti par charge.gd/depense.gd
	# eux-memes sur un Dictionary absent/vide).
	var resultat_suivant := BancSolubilite.avancer([objet], source, 0.5, CONFIG, ETATS, CATALOGUE_SEUILS_INTEGRITE, CONFIG_PRODUIRE, TABLE, MATERIAUX_LOCAUX)
	verif.v(resultat_suivant.transformes.is_empty(), "un objet deja transforme ne doit plus jamais reapparaitre dans transformes")

# "la vitesse de dissolution est proportionnelle a solubilite" : deux objets
# DEJA mouilles (etats_actifs poses directement, sans passer par la phase
# d'exposition -- isole la seule grandeur testee), meme reserve initiale,
# solubilite differente -- la perte de reserve doit etre EXACTEMENT
# proportionnelle au rapport des deux solubilites (facteur_dissolution
# constant, cout_base = facteur * solubilite).
func _vitesse_dissolution_proportionnelle_a_solubilite() -> void:
	var reserve_initiale := 10.0
	var objet_haute := _objet("haute", Vector3(1000, 0, 0), 0.0, 0.9, 100.0, _canal(1.0, 900.0, 0.5), _reserve_integrite(reserve_initiale))
	var objet_basse := _objet("basse", Vector3(1000, 0, 0), 0.0, 0.3, 100.0, _canal(1.0, 900.0, 0.5), _reserve_integrite(reserve_initiale))
	objet_haute.proprietes.etats_actifs = ["mouille"]
	objet_basse.proprietes.etats_actifs = ["mouille"]
	var source := _source(false)
	for i in 10:
		BancSolubilite.avancer([objet_haute], source, 0.5, CONFIG, ETATS, CATALOGUE_SEUILS_INTEGRITE, CONFIG_PRODUIRE, TABLE, MATERIAUX_LOCAUX)
		BancSolubilite.avancer([objet_basse], source, 0.5, CONFIG, ETATS, CATALOGUE_SEUILS_INTEGRITE, CONFIG_PRODUIRE, TABLE, MATERIAUX_LOCAUX)
	var perte_haute: float = reserve_initiale - objet_haute.proprietes.reserves.integrite.reserve
	var perte_basse: float = reserve_initiale - objet_basse.proprietes.reserves.integrite.reserve
	verif.v(perte_haute > perte_basse, "une solubilite plus haute doit dissoudre la reserve d'integrite plus vite")
	verif.v(abs(perte_haute / perte_basse - (0.9 / 0.3)) < 0.001, "la vitesse de dissolution doit etre exactement proportionnelle a solubilite (rapport attendu 0.9/0.3 = 3.0)")

# Un canal/declencheur/etat/reserve/type_produit invente, sans aucun rapport
# avec l'humidite ou le sel, doit traverser exactement le meme code -- meme
# serrure que test_banc_pourriture.gd:_hors_domaine_avancer_ignore_le_domaine,
# etendue aux deux phases (accumulation, transformation).
func _hors_domaine_avancer_ignore_le_domaine() -> void:
	var config_invente := {
		"propriete_cause": "emet_zorglonium",
		"declencheur_expose": "irradie_zorglonium",
		"propriete_absorption": "absorption_zorglonium",
		"propriete_solubilite": "solubilite_zorglonium",
		"nom_etat": "contamine_zorg",
		"nom_canal": "zorglonium",
		"nom_reserve_integrite": "noyau_zorg",
		"facteur_dissolution": 1.0,
		"marqueur_terminal": "instable_zorg",
	}
	var etats_invente := {
		"contamine_zorg": {"duree": 5.0, "effets": [ { "propriete": "resistance_zorg", "mode": "ecraser", "valeur": 0.0 } ] },
	}
	var catalogue_seuils_invente := {
		"epuisement_zorg": [ { "seuil": 0.0, "poser": { "instable_zorg": true } } ],
	}
	var config_produire_invente := { "type_produit": "poussiere_zorg", "rendement": 0.5 }
	var table_invente := { "poussiere_zorg": { "composition": [ { "materiau": "poussiere_zorg_mat", "volume": 1.0 } ] } }
	var materiaux_invente := { "poussiere_zorg_mat": { "densite": 2.0 } }

	var cible := {
		"id": "cobaye",
		"position": Vector3(10, 0, 0),
		"proprietes": {
			"absorption_zorglonium": 1.0, "solubilite_zorglonium": 1.0, "resistance_zorg": 5.0, "masse": 100.0,
			"etats": {"zorglonium": {"charge": 0.0, "seuil": 1.0, "portee_charge": 50.0, "taux_decroissance": 0.2, "poser": {"irradie_zorglonium": true}}},
			"etats_actifs": [],
			"reserves": {"noyau_zorg": {"reserve": 2.0, "cout_base": 0.0, "surcout_action": 0.0, "seuils_ref": "epuisement_zorg"}},
		},
	}
	var emetteur := {"id": "emetteur", "position": Vector3.ZERO, "proprietes": {"emet_zorglonium": true}}

	var resultat: Dictionary = {}
	var transforme := false
	for i in 15:
		resultat = BancSolubilite.avancer([cible], emetteur, 0.5, config_invente, etats_invente, catalogue_seuils_invente, config_produire_invente, table_invente, materiaux_invente)
		if resultat.transformes.has("cobaye"):
			transforme = true
			break
	verif.v(transforme, "un domaine invente doit traverser les deux phases (accumulation/transformation) exactement comme le sel")
	verif.v(cible.proprietes.composition[0].materiau == "poussiere_zorg_mat", "le domaine invente doit produire le type_produit configure")
	verif.v(abs(cible.proprietes.masse - 100.0 * 0.5) < 0.01, "le domaine invente doit respecter le rendement exact, comme le domaine reel")

func _causes_de_et_ponderees() -> void:
	var objets := [
		{"id": "a", "position": Vector3.ZERO, "proprietes": {"source_humidite": true}},
		{"id": "b", "position": Vector3(5, 0, 0), "proprietes": {"source_humidite": false}},
	]
	var causes := BancSolubilite.causes_de(objets, "source_humidite")
	verif.v(causes.size() == 1 and causes[0].position == Vector3.ZERO, "causes_de doit retenir uniquement les objets portant propriete_cause a vrai")

	var ponderees := BancSolubilite.causes_ponderees(causes, 0.4)
	verif.v(ponderees.size() == 1 and abs(ponderees[0].poids - 0.4) < 0.0001, "causes_ponderees doit multiplier le poids implicite (1.0) par le facteur donne")

	var causes_avec_poids := [{"position": Vector3.ZERO, "poids": 2.0}]
	var ponderees2 := BancSolubilite.causes_ponderees(causes_avec_poids, 0.5)
	verif.v(abs(ponderees2[0].poids - 1.0) < 0.0001, "causes_ponderees doit multiplier un poids DEJA explicite, jamais l'ignorer")

func _basculer_source() -> void:
	var source := _source(true)
	BancSolubilite.basculer_source(source, "source_humidite")
	verif.v(not source.proprietes.source_humidite, "basculer_source doit inverser true -> false")
	BancSolubilite.basculer_source(source, "source_humidite")
	verif.v(source.proprietes.source_humidite, "basculer_source doit inverser false -> true")

# Chemin REEL : materiaux.json/proprietes_immuables_composition.json lus sur
# disque, comme test_banc_pourriture.gd le fait -- verrouille que
# solubilite ET absorption_humidite sont bien fusionnees par Objet.fabriquer
# via fabriquer_objets(), independamment de tout cablage de scene.
func _fabrication_reelle_fusionne_solubilite_et_absorption_depuis_materiaux_json() -> void:
	var materiaux: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))
	var proprietes_immuables: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/proprietes_immuables_composition.json")).get("proprietes", [])
	verif.v(proprietes_immuables.has("solubilite"), "data/proprietes_immuables_composition.json doit lister solubilite")
	verif.v(proprietes_immuables.has("absorption_humidite"), "data/proprietes_immuables_composition.json doit deja lister absorption_humidite")

	var declarations := [
		{"id": "sel", "position": [0.0, 0.0, 0.0], "composition": [ {"materiau": "sel_demo", "volume": 3.0} ]},
		{"id": "pierre", "position": [10.0, 0.0, 0.0], "composition": [ {"materiau": "pierre", "volume": 3.0} ]},
	]
	var config := {
		"nom_canal": "humidite", "canal_defaut": _canal(1.0, 900.0, 0.5),
		"nom_reserve_integrite": "integrite", "reserve_integrite_defaut": _reserve_integrite(5.0),
	}
	var objets := BancSolubilite.fabriquer_objets(declarations, materiaux, proprietes_immuables, config)

	var sel: Dictionary = objets[0]
	var pierre: Dictionary = objets[1]
	verif.v(abs(sel.proprietes.solubilite - 0.9) < 0.0001, "sel reel doit fusionner solubilite=0.9 depuis materiaux.json")
	verif.v(abs(pierre.proprietes.solubilite - 0.02) < 0.0001, "pierre reelle doit fusionner solubilite=0.02 depuis materiaux.json")
	verif.v(abs(sel.proprietes.absorption_humidite - 0.6) < 0.0001, "sel reel doit aussi fusionner absorption_humidite=0.6 (meme patron)")
	verif.v(not is_same(sel.proprietes.etats.humidite, pierre.proprietes.etats.humidite), "chaque objet fabrique doit avoir son propre canal, jamais un Dictionary partage")
	verif.v(not is_same(sel.proprietes.reserves.integrite, pierre.proprietes.reserves.integrite), "chaque objet fabrique doit avoir sa propre reserve d'integrite, jamais un Dictionary partage")

# Chemin REEL complet : data/types.json/data/materiaux.json/
# data/transformations.json lus sur disque, comme banc_solubilite.gd les
# charge lui-meme a _ready() -- le sel se mouille puis finit par se
# dissoudre en residu reel (data/transformations.json:dissolution_sel_demo),
# la pierre reste intacte sur la meme fenetre d'observation (solubilite
# 0.02, plus de 200s seraient necessaires pour l'epuiser -- jamais en
# pratique, meme convention que "le fer ne mouille jamais en pratique" dans
# banc_humidite.gd -- la preuve STRICTE solubilite==0.0 vit dans
# _solubilite_nulle_ne_dissout_jamais ci-dessus, sur un objet synthetique).
func _chemin_reel_sel_se_dissout_et_pierre_jamais() -> void:
	var materiaux: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))
	var proprietes_immuables: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/proprietes_immuables_composition.json")).get("proprietes", [])
	var catalogue_types: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/types.json"))
	var transformations: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/transformations.json")).get("transformations", {})
	var config_produire_reel: Dictionary = transformations.get("dissolution_sel_demo", {}).get("a_zero", {}).get("produire", {})
	verif.v(config_produire_reel.get("type_produit", "") == "residu_dissous", "data/transformations.json:dissolution_sel_demo doit produire 'residu_dissous'")

	var declarations := [
		{"id": "sel_reel", "position": [0.0, 0.0, 0.0], "composition": [ {"materiau": "sel_demo", "volume": 3.0} ]},
		{"id": "pierre_reel", "position": [10.0, 0.0, 0.0], "composition": [ {"materiau": "pierre", "volume": 3.0} ]},
	]
	var config := {
		"nom_canal": "humidite", "canal_defaut": _canal(1.0, 900.0, 0.5),
		"nom_reserve_integrite": "integrite", "reserve_integrite_defaut": _reserve_integrite(5.0),
	}
	var objets := BancSolubilite.fabriquer_objets(declarations, materiaux, proprietes_immuables, config)
	var sel: Dictionary = objets[0]
	var pierre: Dictionary = objets[1]
	var masse_sel_avant: float = sel.proprietes.masse

	var source := _source(true)
	var config_avancer := {
		"propriete_cause": "source_humidite", "declencheur_expose": "expose_humidite",
		"propriete_absorption": "absorption_humidite", "propriete_solubilite": "solubilite",
		"nom_etat": "mouille", "nom_canal": "humidite",
		"nom_reserve_integrite": "integrite", "facteur_dissolution": 1.0, "marqueur_terminal": "dissolution_totale",
	}
	var transforme_sel := false
	for i in 40:
		var r := BancSolubilite.avancer(objets, source, 0.5, config_avancer, ETATS, CATALOGUE_SEUILS_INTEGRITE, config_produire_reel, catalogue_types, materiaux)
		if r.transformes.has("sel_reel"):
			transforme_sel = true
			break

	verif.v(transforme_sel, "chemin reel : le sel expose sans interruption doit finir par se dissoudre en residu")
	verif.v(sel.proprietes.composition[0].materiau == "residu_dissous", "chemin reel : le sel transforme doit porter la composition 'residu_dissous'")
	verif.v(abs(sel.proprietes.masse - masse_sel_avant * 0.02) < 0.01, "chemin reel : la masse du residu doit valoir exactement rendement (0.02) * masse du sel")

	verif.v(pierre.proprietes.composition[0].materiau == "pierre", "chemin reel : la pierre ne doit jamais etre transformee sur cette fenetre d'observation")
	verif.v(pierre.proprietes.reserves.integrite.reserve > 4.0, "chemin reel : la reserve d'integrite de la pierre doit rester tres largement intacte (solubilite 0.02, jamais en pratique)")

# Verrouille que data/banc_solubilite.json charge et resout bien les champs
# que banc_solubilite.gd lit.
func _donnees_reelles_banc_solubilite_json() -> void:
	var donnees: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_solubilite.json"))
	verif.v(donnees.propriete_cause == "source_humidite", "data/banc_solubilite.json doit declarer propriete_cause")
	verif.v(donnees.declencheur_expose == "expose_humidite", "data/banc_solubilite.json doit declarer declencheur_expose")
	verif.v(donnees.propriete_absorption == "absorption_humidite", "data/banc_solubilite.json doit declarer propriete_absorption")
	verif.v(donnees.propriete_solubilite == "solubilite", "data/banc_solubilite.json doit declarer propriete_solubilite")
	verif.v(donnees.nom_etat == "mouille", "data/banc_solubilite.json doit reutiliser l'etat partage 'mouille' (data/etats.json)")
	verif.v(donnees.nom_reserve_integrite == "integrite", "data/banc_solubilite.json doit declarer nom_reserve_integrite")
	verif.v(donnees.transformation_terminale == "dissolution_sel_demo", "data/banc_solubilite.json doit reutiliser l'entree 'dissolution_sel_demo' (data/transformations.json)")
	verif.v(donnees.objets.size() == 2, "data/banc_solubilite.json doit declarer deux objets (sel/pierre)")
	var ids: Array = []
	for objet in donnees.objets:
		ids.append(objet.id)
	verif.v(ids.has("sel") and ids.has("pierre"), "data/banc_solubilite.json doit porter les deux materiaux du chantier")

	var etats: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/etats.json"))
	verif.v(etats.has("mouille"), "data/etats.json doit porter l'entree partagee 'mouille'")
	var transformations: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/transformations.json")).get("transformations", {})
	verif.v(transformations.has("dissolution_sel_demo"), "data/transformations.json doit porter l'entree partagee 'dissolution_sel_demo'")
	var seuils: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/seuils_combustible.json"))
	verif.v(seuils.has("epuisement_solubilite"), "data/seuils_combustible.json (catalogue PARTAGE de seuils_ref) doit porter l'entree 'epuisement_solubilite'")
	verif.v(donnees.reserve_integrite_defaut.seuils_ref == "epuisement_solubilite", "data/banc_solubilite.json:reserve_integrite_defaut doit referencer 'epuisement_solubilite'")
	var materiaux: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))
	verif.v(materiaux.has("sel_demo"), "data/materiaux.json doit porter l'entree demo 'sel_demo'")
	verif.v(materiaux.has("residu_dissous"), "data/materiaux.json doit porter le materiau terminal 'residu_dissous'")
