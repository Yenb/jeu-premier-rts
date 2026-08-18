extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_pourriture.gd
#
# Verrouille le cablage de banc_pourriture.gd -- les TROIS phases :
# 1. charge.gd (canal de pourriture, un appel par objet pondere par
#    sensibilite_pourriture) + EtatDuree.poser/avancer (pose de "pourri"
#    tant que l'objet reste expose, guerison progressive une fois la
#    source coupee) + EtatEffectif.valeur (inflammabilite/comestibilite
#    effectives, jamais reimplementees ici) ;
# 2. depense.gd (reserve "integrite", cout_base gele a 0.0 tant que "pourri"
#    est absent) + produit.gd (transformer, appele DIRECTEMENT par ce
#    fichier au franchissement du seuil terminal -- depense.gd lui-meme
#    n'a pas de branche "produire").
#
# AUCUN MECANISME DU COEUR TOUCHE par ce chantier : charge.gd/etat_duree.gd/
# etat_effectif.gd/depense.gd/produit.gd/extinction.gd/objet.gd restent
# exactement ceux deja verrouilles par leurs propres tests -- ce fichier
# verrouille uniquement banc_pourriture.gd.

const BancPourriture = preload("res://scripts/banc_pourriture.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")
const EtatDuree = preload("res://scripts/etat_duree.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

const ETATS := {
	"pourri": {
		"duree": 10.0,
		"effets": [
			{ "propriete": "comestibilite", "mode": "ecraser", "valeur": 0.0 },
			{ "propriete": "inflammabilite", "mode": "moduler", "facteur": 1.4 },
		],
	},
}

const CONFIG := {
	"propriete_cause": "source_pourriture",
	"declencheur_expose": "expose_pourriture",
	"propriete_sensibilite": "sensibilite_pourriture",
	"nom_etat": "pourri",
	"nom_canal": "pourriture",
	"nom_reserve_integrite": "integrite",
	"cout_integrite_actif": 1.0,
	"marqueur_terminal": "pourriture_totale",
}

const CATALOGUE_SEUILS_INTEGRITE := {
	"epuisement_pourriture": [
		{ "seuil": 0.0, "poser": { "pourriture_totale": true } },
	],
}

const CONFIG_PRODUIRE := {
	"type_produit": "compost_test",
	"rendement": 0.35,
}

const TABLE := {
	"compost_test": { "composition": [ { "materiau": "compost_test_mat", "volume": 1.0 } ] },
}

const MATERIAUX_LOCAUX := {
	"compost_test_mat": { "densite": 0.5 },
}

func _init() -> void:
	_sans_source_rien_ne_bouge()
	_objet_a_portee_devient_pourri_et_degrade()
	_objet_hors_portee_reste_sain()
	_sensibilite_nulle_ne_pourrit_jamais()
	_source_retiree_pourri_guerit_progressivement_objet_sauve()
	_reserve_integrite_epuisee_transforme_en_produit()
	_hors_domaine_avancer_ignore_le_domaine()
	_causes_de_et_ponderees()
	_basculer_source()
	_fabrication_reelle_fusionne_sensibilite_et_comestibilite_depuis_materiaux_json()
	_chemin_reel_bois_pourrit_et_se_transforme_pierre_jamais()
	_donnees_reelles_banc_pourriture_json()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: sans source rien ne bouge, un objet a portee monte et devient pourri puis se degrade, " +
		"un objet hors portee reste sain, une sensibilite nulle ne pourrit jamais, la source retiree " +
		"guerit progressivement (objet sauve avant l'epuisement), la reserve d'integrite epuisee " +
		"transforme l'objet en produit (masse exacte au rendement), avancer() ignore le domaine, " +
		"causes_de/causes_ponderees/basculer_source purs, la fabrication reelle fusionne " +
		"sensibilite_pourriture/comestibilite depuis materiaux.json, le chemin reel bois/pierre " +
		"se comporte comme attendu, et data/banc_pourriture.json charge correctement")
	quit(0)

func _objet(id: String, position: Vector3, sensibilite: float, inflammabilite: float, comestibilite: float, masse: float, canal: Dictionary, reserve_integrite: Dictionary) -> Dictionary:
	return {
		"id": id,
		"position": position,
		"proprietes": {
			"sensibilite_pourriture": sensibilite,
			"inflammabilite": inflammabilite,
			"comestibilite": comestibilite,
			"masse": masse,
			"etats": {"pourriture": canal.duplicate(true)},
			"etats_actifs": [],
			"reserves": {"integrite": reserve_integrite.duplicate(true)},
		},
	}

func _canal(seuil: float, portee: float, taux_decroissance: float) -> Dictionary:
	return {
		"charge": 0.0, "seuil": seuil, "portee_charge": portee,
		"taux_decroissance": taux_decroissance, "poser": {"expose_pourriture": true},
	}

func _reserve_integrite(reserve: float) -> Dictionary:
	return {
		"reserve": reserve, "cout_base": 0.0, "surcout_action": 0.0,
		"seuils_ref": "epuisement_pourriture",
	}

func _source(active: bool) -> Dictionary:
	return {"id": "source", "position": Vector3.ZERO, "proprietes": {"source_pourriture": active}}

func _sans_source_rien_ne_bouge() -> void:
	var objet := _objet("bois", Vector3(100, 0, 0), 0.8, 0.9, 0.0, 1800.0, _canal(1.0, 900.0, 0.5), _reserve_integrite(5.0))
	var source := _source(false)
	for i in 10:
		BancPourriture.avancer([objet], source, 1.0, CONFIG, ETATS, CATALOGUE_SEUILS_INTEGRITE, CONFIG_PRODUIRE, TABLE, MATERIAUX_LOCAUX)
	verif.v(objet.proprietes.etats.pourriture.charge == 0.0, "sans source active, la charge de pourriture doit rester a 0.0")
	verif.v(not objet.proprietes.get("expose_pourriture", false), "sans source active, expose_pourriture ne doit jamais etre pose")
	verif.v(objet.proprietes.etats_actifs.is_empty(), "sans source active, aucun etat ne doit etre pose")
	verif.v(objet.proprietes.reserves.integrite.reserve == 5.0, "sans pourriture, la reserve d'integrite ne doit jamais decroitre")

func _objet_a_portee_devient_pourri_et_degrade() -> void:
	var objet := _objet("bois", Vector3(100, 0, 0), 0.8, 0.9, 0.3, 1800.0, _canal(1.0, 900.0, 0.5), _reserve_integrite(5.0))
	var source := _source(true)
	for i in 15:
		BancPourriture.avancer([objet], source, 0.1, CONFIG, ETATS, CATALOGUE_SEUILS_INTEGRITE, CONFIG_PRODUIRE, TABLE, MATERIAUX_LOCAUX)
	verif.v(objet.proprietes.get("expose_pourriture", false), "apres exposition suffisante (charge > seuil), expose_pourriture doit etre pose")
	verif.v(objet.proprietes.etats_actifs.has("pourri"), "expose_pourriture pose doit avoir declenche EtatDuree.poser('pourri')")
	verif.v(objet.proprietes.etats_intensite.get("pourri", 0.0) > 0.9, "juste apres la pose, l'intensite doit rester tres proche de 1.0")
	var pondere := EtatDuree.etats_ponderes(objet, ETATS)
	var eff_inflammabilite := EtatEffectif.valeur(objet, "inflammabilite", pondere)
	var eff_comestibilite := EtatEffectif.valeur(objet, "comestibilite", pondere)
	verif.v(eff_inflammabilite > 0.9, "pourri avec une intensite proche de 1.0, l'inflammabilite effective doit etre modulee au-dessus de la base (0.9 * 1.4)")
	verif.v(eff_comestibilite < 0.05, "pourri avec une intensite proche de 1.0, la comestibilite effective doit etre ecrasee pres de 0.0 (base 0.3)")

func _objet_hors_portee_reste_sain() -> void:
	var objet := _objet("loin", Vector3(2000, 0, 0), 0.9, 0.9, 0.0, 1800.0, _canal(1.0, 50.0, 0.5), _reserve_integrite(5.0))
	var source := _source(true)
	for i in 20:
		BancPourriture.avancer([objet], source, 1.0, CONFIG, ETATS, CATALOGUE_SEUILS_INTEGRITE, CONFIG_PRODUIRE, TABLE, MATERIAUX_LOCAUX)
	verif.v(objet.proprietes.etats.pourriture.charge == 0.0, "hors de portee_charge, la charge doit rester a 0.0 quelle que soit la sensibilite")
	verif.v(objet.proprietes.etats_actifs.is_empty(), "hors de portee_charge, l'objet ne doit jamais devenir pourri")
	verif.v(objet.proprietes.reserves.integrite.reserve == 5.0, "hors de portee_charge, la reserve d'integrite ne doit jamais decroitre")

func _sensibilite_nulle_ne_pourrit_jamais() -> void:
	var objet := _objet("pierre", Vector3(100, 0, 0), 0.0, 0.0, 0.0, 8100.0, _canal(1.0, 900.0, 0.5), _reserve_integrite(5.0))
	var source := _source(true)
	for i in 100:
		BancPourriture.avancer([objet], source, 1.0, CONFIG, ETATS, CATALOGUE_SEUILS_INTEGRITE, CONFIG_PRODUIRE, TABLE, MATERIAUX_LOCAUX)
	verif.v(objet.proprietes.etats.pourriture.charge == 0.0, "sensibilite 0.0, la charge doit rester a 0.0 meme apres cent ticks a portee")
	verif.v(objet.proprietes.etats_actifs.is_empty(), "sensibilite 0.0, l'objet ne doit jamais devenir pourri")
	verif.v(objet.proprietes.reserves.integrite.reserve == 5.0, "sensibilite 0.0, sans jamais devenir pourri, la reserve d'integrite ne doit jamais decroitre")
	verif.v(objet.proprietes.masse == 8100.0, "sensibilite 0.0, la masse ne doit jamais changer -- jamais transforme")

func _source_retiree_pourri_guerit_progressivement_objet_sauve() -> void:
	# Reserve genereuse expres : ce test verifie qu'un objet SAUVE A TEMPS
	# ne se transforme jamais -- il faut donc plus de reserve que ce que
	# "pourri" peut consommer meme s'il decroit pendant les 10.0s completes
	# de sa duree (cout_base reste actif tant que "pourri" figure dans
	# etats_actifs, quelle que soit son intensite -- voir avancer()).
	var objet := _objet("bois", Vector3(100, 0, 0), 0.8, 0.9, 0.0, 1800.0, _canal(1.0, 900.0, 0.5), _reserve_integrite(30.0))
	var source := _source(true)
	for i in 15:
		BancPourriture.avancer([objet], source, 0.1, CONFIG, ETATS, CATALOGUE_SEUILS_INTEGRITE, CONFIG_PRODUIRE, TABLE, MATERIAUX_LOCAUX)
	verif.v(objet.proprietes.etats_actifs.has("pourri"), "l'objet doit d'abord etre pourri avant de pouvoir guerir")
	var reserve_avant_coupure: float = objet.proprietes.reserves.integrite.reserve
	verif.v(reserve_avant_coupure < 30.0 and reserve_avant_coupure > 0.0, "la reserve d'integrite doit avoir commence a decroitre pendant l'exposition, sans etre epuisee")

	BancPourriture.basculer_source(source, CONFIG.propriete_cause)
	verif.v(not source.proprietes.source_pourriture, "basculer_source doit desactiver une source active")

	# charge (taux_decroissance 0.5/s) redescend vite sous le seuil -- le
	# marqueur expose_pourriture doit se retirer BIEN AVANT que "pourri" ne
	# soit retire par la decroissance lente d'EtatDuree (10.0s).
	for i in 3:
		BancPourriture.avancer([objet], source, 0.5, CONFIG, ETATS, CATALOGUE_SEUILS_INTEGRITE, CONFIG_PRODUIRE, TABLE, MATERIAUX_LOCAUX)
	verif.v(not objet.proprietes.get("expose_pourriture", false), "source coupee, expose_pourriture doit se retirer rapidement (charge sous le seuil)")
	verif.v(objet.proprietes.etats_actifs.has("pourri"), "expose_pourriture retire ne doit PAS retirer 'pourri' instantanement -- seul EtatDuree.avancer le fait, progressivement")
	verif.v(objet.proprietes.reserves.integrite.reserve <= reserve_avant_coupure, "'pourri' encore actif juste apres la coupure : la reserve d'integrite doit continuer de decroitre (ou rester egale au pas pres), jamais remonter")

	# Ecoule le reste de la duree (10.0s) pour atteindre le retrait complet
	# de "pourri" -- le cout_base de la reserve d'integrite doit alors se
	# regeler a 0.0, la reserve reste FIGEE la ou elle en etait.
	for i in 20:
		BancPourriture.avancer([objet], source, 0.5, CONFIG, ETATS, CATALOGUE_SEUILS_INTEGRITE, CONFIG_PRODUIRE, TABLE, MATERIAUX_LOCAUX)
	verif.v(not objet.proprietes.etats_actifs.has("pourri"), "apres 10.0s ecoulees sans exposition, 'pourri' doit avoir ete retire par EtatDuree.avancer")
	verif.v(objet.proprietes.reserves.integrite.reserve > 0.0, "l'objet gueri AVANT l'epuisement de sa reserve d'integrite doit rester sauve -- jamais transforme")
	verif.v(objet.proprietes.masse == 1800.0, "objet sauve : la masse ne doit jamais avoir change, jamais transforme en produit")
	var reserve_finale: float = objet.proprietes.reserves.integrite.reserve
	for i in 20:
		BancPourriture.avancer([objet], source, 0.5, CONFIG, ETATS, CATALOGUE_SEUILS_INTEGRITE, CONFIG_PRODUIRE, TABLE, MATERIAUX_LOCAUX)
	verif.v(objet.proprietes.reserves.integrite.reserve == reserve_finale, "'pourri' absent et source coupee : la reserve d'integrite doit rester FIGEE indefiniment (cout_base regele a 0.0), jamais reprendre sa decroissance seule")

func _reserve_integrite_epuisee_transforme_en_produit() -> void:
	var objet := _objet("bois", Vector3(100, 0, 0), 0.8, 0.9, 0.0, 1800.0, _canal(1.0, 900.0, 0.5), _reserve_integrite(5.0))
	var source := _source(true)
	var resultat: Dictionary = {}
	var transforme_a_ce_tick := false
	for i in 40:
		resultat = BancPourriture.avancer([objet], source, 0.5, CONFIG, ETATS, CATALOGUE_SEUILS_INTEGRITE, CONFIG_PRODUIRE, TABLE, MATERIAUX_LOCAUX)
		if resultat.transformes.has("bois"):
			transforme_a_ce_tick = true
			break
	verif.v(transforme_a_ce_tick, "expose sans interruption, la reserve d'integrite doit finir par s'epuiser et transformer l'objet")
	verif.v(not objet.proprietes.has("etats"), "un objet transforme ne doit plus porter 'etats' -- proprietes entierement remplacees")
	verif.v(not objet.proprietes.has("reserves"), "un objet transforme ne doit plus porter 'reserves' -- proprietes entierement remplacees")
	verif.v(not objet.proprietes.has("pourriture_totale"), "un objet transforme ne doit plus porter le marqueur terminal -- proprietes entierement remplacees")
	verif.v(objet.proprietes.composition[0].materiau == "compost_test_mat", "l'objet transforme doit porter la composition du type_produit configure")
	verif.v(abs(objet.proprietes.masse - 1800.0 * 0.35) < 0.01, "la masse produite doit valoir exactement rendement * masse_ancien, jamais posee a la main")

	# Un objet deja transforme ne porte plus "etats"/"reserves" -- un pas
	# supplementaire ne doit produire aucune erreur ni aucun second passage
	# par Produit.transformer (chemin mort garanti par charge.gd/depense.gd
	# eux-memes sur un Dictionary absent/vide).
	var resultat_suivant := BancPourriture.avancer([objet], source, 0.5, CONFIG, ETATS, CATALOGUE_SEUILS_INTEGRITE, CONFIG_PRODUIRE, TABLE, MATERIAUX_LOCAUX)
	verif.v(resultat_suivant.transformes.is_empty(), "un objet deja transforme ne doit plus jamais reapparaitre dans transformes")

# Un canal/declencheur/etat/reserve/type_produit invente, sans aucun rapport
# avec la pourriture ou le bois, doit traverser exactement le meme code --
# meme serrure que test_banc_humidite.gd:_hors_domaine_avancer_ignore_le_domaine,
# etendue aux trois phases (accumulation, degradation, transformation).
func _hors_domaine_avancer_ignore_le_domaine() -> void:
	var config_invente := {
		"propriete_cause": "emet_zorglonium",
		"declencheur_expose": "irradie_zorglonium",
		"propriete_sensibilite": "sensibilite_zorglonium",
		"nom_etat": "contamine_zorg",
		"nom_canal": "zorglonium",
		"nom_reserve_integrite": "noyau_zorg",
		"cout_integrite_actif": 1.0,
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
			"sensibilite_zorglonium": 1.0, "resistance_zorg": 5.0, "masse": 100.0,
			"etats": {"zorglonium": {"charge": 0.0, "seuil": 1.0, "portee_charge": 50.0, "taux_decroissance": 0.2, "poser": {"irradie_zorglonium": true}}},
			"etats_actifs": [],
			"reserves": {"noyau_zorg": {"reserve": 2.0, "cout_base": 0.0, "surcout_action": 0.0, "seuils_ref": "epuisement_zorg"}},
		},
	}
	var emetteur := {"id": "emetteur", "position": Vector3.ZERO, "proprietes": {"emet_zorglonium": true}}

	var resultat: Dictionary = {}
	var transforme := false
	for i in 15:
		resultat = BancPourriture.avancer([cible], emetteur, 0.5, config_invente, etats_invente, catalogue_seuils_invente, config_produire_invente, table_invente, materiaux_invente)
		if resultat.transformes.has("cobaye"):
			transforme = true
			break
	verif.v(transforme, "un domaine invente doit traverser les trois phases (accumulation/degradation/transformation) exactement comme le bois")
	verif.v(cible.proprietes.composition[0].materiau == "poussiere_zorg_mat", "le domaine invente doit produire le type_produit configure")
	verif.v(abs(cible.proprietes.masse - 100.0 * 0.5) < 0.01, "le domaine invente doit respecter le rendement exact, comme le domaine reel")

func _causes_de_et_ponderees() -> void:
	var objets := [
		{"id": "a", "position": Vector3.ZERO, "proprietes": {"source_pourriture": true}},
		{"id": "b", "position": Vector3(5, 0, 0), "proprietes": {"source_pourriture": false}},
	]
	var causes := BancPourriture.causes_de(objets, "source_pourriture")
	verif.v(causes.size() == 1 and causes[0].position == Vector3.ZERO, "causes_de doit retenir uniquement les objets portant propriete_cause a vrai")

	var ponderees := BancPourriture.causes_ponderees(causes, 0.4)
	verif.v(ponderees.size() == 1 and abs(ponderees[0].poids - 0.4) < 0.0001, "causes_ponderees doit multiplier le poids implicite (1.0) par le facteur donne")

	var causes_avec_poids := [{"position": Vector3.ZERO, "poids": 2.0}]
	var ponderees2 := BancPourriture.causes_ponderees(causes_avec_poids, 0.5)
	verif.v(abs(ponderees2[0].poids - 1.0) < 0.0001, "causes_ponderees doit multiplier un poids DEJA explicite, jamais l'ignorer")

func _basculer_source() -> void:
	var source := _source(true)
	BancPourriture.basculer_source(source, "source_pourriture")
	verif.v(not source.proprietes.source_pourriture, "basculer_source doit inverser true -> false")
	BancPourriture.basculer_source(source, "source_pourriture")
	verif.v(source.proprietes.source_pourriture, "basculer_source doit inverser false -> true")

# Chemin REEL : materiaux.json/proprietes_immuables_composition.json lus sur
# disque, comme test_banc_humidite.gd le fait -- verrouille que
# sensibilite_pourriture ET comestibilite sont bien fusionnees par
# Objet.fabriquer via fabriquer_objets(), independamment de tout cablage de
# scene.
func _fabrication_reelle_fusionne_sensibilite_et_comestibilite_depuis_materiaux_json() -> void:
	var materiaux: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))
	var proprietes_immuables: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/proprietes_immuables_composition.json")).get("proprietes", [])
	verif.v(proprietes_immuables.has("sensibilite_pourriture"), "data/proprietes_immuables_composition.json doit lister sensibilite_pourriture")
	verif.v(proprietes_immuables.has("comestibilite"), "data/proprietes_immuables_composition.json doit lister comestibilite")

	var declarations := [
		{"id": "bois", "position": [0.0, 0.0, 0.0], "composition": [ {"materiau": "bois", "volume": 3.0} ]},
		{"id": "pierre", "position": [10.0, 0.0, 0.0], "composition": [ {"materiau": "pierre", "volume": 3.0} ]},
	]
	var config := {
		"nom_canal": "pourriture", "canal_defaut": _canal(1.0, 700.0, 0.5),
		"nom_reserve_integrite": "integrite", "reserve_integrite_defaut": _reserve_integrite(5.0),
	}
	var objets := BancPourriture.fabriquer_objets(declarations, materiaux, proprietes_immuables, config)

	var bois: Dictionary = objets[0]
	var pierre: Dictionary = objets[1]
	verif.v(abs(bois.proprietes.sensibilite_pourriture - 0.8) < 0.0001, "bois reel doit fusionner sensibilite_pourriture=0.8 depuis materiaux.json")
	verif.v(abs(pierre.proprietes.sensibilite_pourriture - 0.0) < 0.0001, "pierre reelle doit fusionner sensibilite_pourriture=0.0 depuis materiaux.json")
	verif.v(abs(bois.proprietes.comestibilite - 0.0) < 0.0001, "bois reel doit aussi fusionner comestibilite=0.0 (meme patron)")
	verif.v(abs(bois.proprietes.inflammabilite - 0.9) < 0.0001, "bois reel doit continuer de fusionner inflammabilite=0.9 (deja demontre par banc_humidite/banc_inflammabilite)")
	verif.v(not is_same(bois.proprietes.etats.pourriture, pierre.proprietes.etats.pourriture), "chaque objet fabrique doit avoir son propre canal, jamais un Dictionary partage")
	verif.v(not is_same(bois.proprietes.reserves.integrite, pierre.proprietes.reserves.integrite), "chaque objet fabrique doit avoir sa propre reserve d'integrite, jamais un Dictionary partage")

# Chemin REEL complet : data/types.json/data/materiaux.json/
# data/transformations.json lus sur disque, comme banc_pourriture.gd les
# charge lui-meme a _ready() -- le bois pourrit et finit par devenir du
# compost reel (data/transformations.json:pourriture_bois), la pierre ne
# bouge jamais.
func _chemin_reel_bois_pourrit_et_se_transforme_pierre_jamais() -> void:
	var materiaux: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))
	var proprietes_immuables: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/proprietes_immuables_composition.json")).get("proprietes", [])
	var catalogue_types: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/types.json"))
	var transformations: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/transformations.json")).get("transformations", {})
	var config_produire_reel: Dictionary = transformations.get("pourriture_bois", {}).get("a_zero", {}).get("produire", {})
	verif.v(config_produire_reel.get("type_produit", "") == "compost", "data/transformations.json:pourriture_bois doit produire 'compost'")

	var declarations := [
		{"id": "bois_reel", "position": [0.0, 0.0, 0.0], "composition": [ {"materiau": "bois", "volume": 3.0} ]},
		{"id": "pierre_reel", "position": [10.0, 0.0, 0.0], "composition": [ {"materiau": "pierre", "volume": 3.0} ]},
	]
	var config := {
		"nom_canal": "pourriture", "canal_defaut": _canal(1.0, 700.0, 0.5),
		"nom_reserve_integrite": "integrite", "reserve_integrite_defaut": _reserve_integrite(5.0),
	}
	var objets := BancPourriture.fabriquer_objets(declarations, materiaux, proprietes_immuables, config)
	var bois: Dictionary = objets[0]
	var pierre: Dictionary = objets[1]
	var masse_bois_avant: float = bois.proprietes.masse

	var source := _source(true)
	var config_avancer := {
		"propriete_cause": "source_pourriture", "declencheur_expose": "expose_pourriture",
		"propriete_sensibilite": "sensibilite_pourriture", "nom_etat": "pourri", "nom_canal": "pourriture",
		"nom_reserve_integrite": "integrite", "cout_integrite_actif": 1.0, "marqueur_terminal": "pourriture_totale",
	}
	var transforme_bois := false
	for i in 40:
		var r := BancPourriture.avancer(objets, source, 0.5, config_avancer, ETATS, CATALOGUE_SEUILS_INTEGRITE, config_produire_reel, catalogue_types, materiaux)
		if r.transformes.has("bois_reel"):
			transforme_bois = true
			break

	verif.v(transforme_bois, "chemin reel : le bois expose sans interruption doit finir par devenir du compost")
	verif.v(bois.proprietes.composition[0].materiau == "compost", "chemin reel : le bois transforme doit porter la composition 'compost'")
	verif.v(abs(bois.proprietes.masse - masse_bois_avant * 0.35) < 0.01, "chemin reel : la masse de compost doit valoir exactement rendement (0.35) * masse du bois")

	verif.v(pierre.proprietes.etats.pourriture.charge == 0.0, "chemin reel : la pierre ne doit jamais accumuler de charge de pourriture")
	verif.v(pierre.proprietes.etats_actifs.is_empty(), "chemin reel : la pierre ne doit jamais devenir pourrie")
	verif.v(pierre.proprietes.reserves.integrite.reserve == 5.0, "chemin reel : la reserve d'integrite de la pierre ne doit jamais decroitre")
	verif.v(pierre.proprietes.composition[0].materiau == "pierre", "chemin reel : la pierre ne doit jamais etre transformee")

# Verrouille que data/banc_pourriture.json charge et resout bien les champs
# que banc_pourriture.gd lit.
func _donnees_reelles_banc_pourriture_json() -> void:
	var donnees: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_pourriture.json"))
	verif.v(donnees.propriete_cause == "source_pourriture", "data/banc_pourriture.json doit declarer propriete_cause")
	verif.v(donnees.declencheur_expose == "expose_pourriture", "data/banc_pourriture.json doit declarer declencheur_expose")
	verif.v(donnees.propriete_sensibilite == "sensibilite_pourriture", "data/banc_pourriture.json doit declarer propriete_sensibilite")
	verif.v(donnees.nom_etat == "pourri", "data/banc_pourriture.json doit reutiliser l'etat 'pourri' (data/etats.json)")
	verif.v(donnees.nom_reserve_integrite == "integrite", "data/banc_pourriture.json doit declarer nom_reserve_integrite")
	verif.v(donnees.transformation_terminale == "pourriture_bois", "data/banc_pourriture.json doit reutiliser l'entree 'pourriture_bois' (data/transformations.json)")
	verif.v(donnees.objets.size() == 2, "data/banc_pourriture.json doit declarer deux objets (bois/pierre)")
	var ids: Array = []
	for objet in donnees.objets:
		ids.append(objet.id)
	verif.v(ids.has("bois") and ids.has("pierre"), "data/banc_pourriture.json doit porter les deux materiaux du chantier")

	var etats: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/etats.json"))
	verif.v(etats.has("pourri"), "data/etats.json doit porter l'entree partagee 'pourri'")
	var transformations: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/transformations.json")).get("transformations", {})
	verif.v(transformations.has("pourriture_bois"), "data/transformations.json doit porter l'entree partagee 'pourriture_bois'")
	var seuils: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/seuils_combustible.json"))
	verif.v(seuils.has("epuisement_pourriture"), "data/seuils_combustible.json (catalogue PARTAGE de seuils_ref) doit porter l'entree 'epuisement_pourriture'")
	verif.v(donnees.reserve_integrite_defaut.seuils_ref == "epuisement_pourriture", "data/banc_pourriture.json:reserve_integrite_defaut doit referencer 'epuisement_pourriture'")
