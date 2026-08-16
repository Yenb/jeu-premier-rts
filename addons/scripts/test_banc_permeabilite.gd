extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_permeabilite.gd
#
# Verrouille le cablage de banc_permeabilite.gd -- charge.gd (canal
# d'humidite, un seul appel pour tous les objets, taux_decroissance PROPRE
# A CHAQUE CANAL calcule une fois a la fabrication depuis permeabilite).
#
# AUCUN MECANISME DU COEUR TOUCHE par ce chantier : charge.gd/objet.gd
# restent exactement ceux deja verrouilles par leurs propres tests -- ce
# fichier verrouille uniquement banc_permeabilite.gd.

const BancPermeabilite = preload("res://scripts/banc_permeabilite.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

const CONFIG := {
	"propriete_cause": "source_humidite",
	"propriete_permeabilite": "permeabilite",
	"nom_canal": "humidite",
	"nom_marque": "sature_eau",
	"taux_decroissance_plancher": 0.05,
	"facteur_permeabilite": 2.0,
}

func _init() -> void:
	_sans_source_rien_ne_bouge()
	_permeable_et_impermeable_montent_identiquement_sous_exposition()
	_permeable_seche_plus_vite_que_impermeable_apres_retrait_source()
	_a_permeabilite_egale_meme_comportement()
	_permeabilite_ponderee_moyenne_ponderee_par_volume()
	_permeabilite_ponderee_chemin_mort()
	_taux_decroissance_permeabilite_plancher_et_facteur()
	_causes_de()
	_basculer_source()
	_hors_domaine_avancer_ignore_le_domaine()
	_fabrication_reelle_fusionne_permeabilite_depuis_materiaux_json()
	_donnees_reelles_banc_permeabilite_json()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: sans source rien ne bouge, permeable et impermeable montent identiquement sous " +
		"exposition, une fois la source coupee le permeable seche strictement plus vite que " +
		"l'impermeable, a permeabilite egale le comportement est identique (non-regression), " +
		"permeabilite_ponderee moyenne ponderee par volume et rend 0.0 en chemin mort, " +
		"taux_decroissance_permeabilite applique plancher+facteur*permeabilite, causes_de/" +
		"basculer_source pures, avancer() ignore le domaine, la fabrication reelle fusionne " +
		"permeabilite depuis materiaux.json (bois 0.5 / fer 0.0), et data/banc_permeabilite.json " +
		"charge correctement")
	quit(0)

func _objet(id: String, position: Vector3, taux_decroissance: float, seuil: float, portee: float) -> Dictionary:
	return {
		"id": id,
		"position": position,
		"proprietes": {
			"etats": {
				"humidite": {
					"charge": 0.0, "seuil": seuil, "portee_charge": portee,
					"taux_decroissance": taux_decroissance, "poser": {"sature_eau": true},
				},
			},
		},
	}

func _source(active: bool) -> Dictionary:
	return {"id": "source", "position": Vector3.ZERO, "proprietes": {"source_humidite": active}}

func _sans_source_rien_ne_bouge() -> void:
	var objet := _objet("permeable", Vector3(100, 0, 0), 1.05, 1.0, 900.0)
	var source := _source(false)
	for i in 10:
		BancPermeabilite.avancer([objet], source, 1.0, CONFIG)
	verif.v(objet.proprietes.etats.humidite.charge == 0.0, "sans source active, la charge d'humidite doit rester a 0.0")
	verif.v(not objet.proprietes.get("sature_eau", false), "sans source active, sature_eau ne doit jamais etre pose")

# Preuve que la permeabilite n'est JAMAIS un facteur d'absorption dans ce
# chantier (voir en-tete banc_permeabilite.gd) : deux objets a
# taux_decroissance TRES different doivent malgre tout accumuler leur
# charge d'humidite a une vitesse RIGOUREUSEMENT IDENTIQUE tant que la
# source reste active -- seule la decroissance les separera, plus tard.
func _permeable_et_impermeable_montent_identiquement_sous_exposition() -> void:
	var permeable := _objet("permeable", Vector3(100, 0, 0), 1.05, 1.0, 900.0)
	var impermeable := _objet("impermeable", Vector3(100, 0, 0), 0.05, 1.0, 900.0)
	var source := _source(true)
	for i in 5:
		BancPermeabilite.avancer([permeable, impermeable], source, 0.3, CONFIG)
	verif.v(abs(permeable.proprietes.etats.humidite.charge - impermeable.proprietes.etats.humidite.charge) < 0.0001,
		"sous exposition, permeable et impermeable doivent accumuler exactement la meme charge -- seul taux_decroissance doit les separer, jamais la montee")

func _permeable_seche_plus_vite_que_impermeable_apres_retrait_source() -> void:
	var permeable := _objet("permeable", Vector3(100, 0, 0), 1.05, 1.0, 900.0)
	var impermeable := _objet("impermeable", Vector3(100, 0, 0), 0.05, 1.0, 900.0)
	var source := _source(true)

	for i in 3:
		BancPermeabilite.avancer([permeable, impermeable], source, 1.0, CONFIG)
	verif.v(permeable.proprietes.get("sature_eau", false), "permeable doit etre sature apres exposition suffisante")
	verif.v(impermeable.proprietes.get("sature_eau", false), "impermeable doit etre sature apres exposition suffisante (la montee ne depend jamais de la permeabilite)")

	BancPermeabilite.basculer_source(source, CONFIG.propriete_cause)
	verif.v(not source.proprietes.source_humidite, "basculer_source doit desactiver une source active")

	for i in 2:
		BancPermeabilite.avancer([permeable, impermeable], source, 1.0, CONFIG)

	verif.v(permeable.proprietes.etats.humidite.charge < impermeable.proprietes.etats.humidite.charge,
		"apres retrait de la source, la charge du permeable doit redescendre strictement plus vite que celle de l'impermeable")
	verif.v(not permeable.proprietes.get("sature_eau", false), "le permeable doit avoir seche (repasse sous le seuil) apres retrait de la source")
	verif.v(impermeable.proprietes.get("sature_eau", false), "l'impermeable doit rester sature bien plus longtemps -- l'eau reste piegee")

# Non-regression : a permeabilite strictement egale (donc taux_decroissance
# identique), deux objets independants doivent evoluer IDENTIQUEMENT tick
# par tick, quel que soit leur id -- preuve que seule la permeabilite (via
# taux_decroissance) explique tout ecart mesure par le test precedent.
func _a_permeabilite_egale_meme_comportement() -> void:
	var taux := BancPermeabilite.taux_decroissance_permeabilite(0.3, CONFIG)
	var a := _objet("a", Vector3(100, 0, 0), taux, 1.0, 900.0)
	var b := _objet("b", Vector3(100, 0, 0), taux, 1.0, 900.0)
	var source := _source(true)
	for i in 4:
		BancPermeabilite.avancer([a, b], source, 0.5, CONFIG)
	verif.v(a.proprietes.etats.humidite.charge == b.proprietes.etats.humidite.charge, "a permeabilite egale, la charge doit etre rigoureusement identique en montee")

	BancPermeabilite.basculer_source(source, CONFIG.propriete_cause)
	for i in 4:
		BancPermeabilite.avancer([a, b], source, 0.5, CONFIG)
	verif.v(a.proprietes.etats.humidite.charge == b.proprietes.etats.humidite.charge, "a permeabilite egale, la charge doit rester rigoureusement identique en decroissance")
	verif.v(a.proprietes.get("sature_eau", false) == b.proprietes.get("sature_eau", false), "a permeabilite egale, la bascule de sature_eau doit survenir au meme tick")

func _permeabilite_ponderee_moyenne_ponderee_par_volume() -> void:
	var materiaux_test := {
		"materiau_permeable": {"permeabilite": 0.8},
		"materiau_impermeable": {"permeabilite": 0.1},
	}
	var objet := {
		"id": "mixte", "position": Vector3.ZERO,
		"proprietes": {"composition": [
			{"materiau": "materiau_permeable", "volume": 1.0},
			{"materiau": "materiau_impermeable", "volume": 3.0},
		]},
	}
	# (0.8*1.0 + 0.1*3.0) / 4.0 = 1.1 / 4.0 = 0.275
	var resultat := BancPermeabilite.permeabilite_ponderee(objet, materiaux_test, "permeabilite")
	verif.v(abs(resultat - 0.275) < 0.0001, "permeabilite_ponderee doit rendre la moyenne ponderee par volume des fiches materiau")

func _permeabilite_ponderee_chemin_mort() -> void:
	var sans_composition := {"id": "x", "position": Vector3.ZERO, "proprietes": {}}
	verif.v(BancPermeabilite.permeabilite_ponderee(sans_composition, {"m": {"permeabilite": 0.5}}, "permeabilite") == 0.0, "sans composition, permeabilite_ponderee doit rendre 0.0")

	var avec_composition := {"id": "y", "position": Vector3.ZERO, "proprietes": {"composition": [{"materiau": "m", "volume": 1.0}]}}
	verif.v(BancPermeabilite.permeabilite_ponderee(avec_composition, {}, "permeabilite") == 0.0, "materiaux vide, permeabilite_ponderee doit rendre 0.0")
	verif.v(BancPermeabilite.permeabilite_ponderee(avec_composition, {"m": {"permeabilite": 0.5}}, "") == 0.0, "propriete_permeabilite vide, permeabilite_ponderee doit rendre 0.0")

func _taux_decroissance_permeabilite_plancher_et_facteur() -> void:
	var config := {"taux_decroissance_plancher": 0.05, "facteur_permeabilite": 2.0}
	verif.v(abs(BancPermeabilite.taux_decroissance_permeabilite(0.0, config) - 0.05) < 0.0001, "a permeabilite nulle, le taux doit retomber exactement sur le plancher -- jamais zero pur")
	verif.v(abs(BancPermeabilite.taux_decroissance_permeabilite(0.5, config) - 1.05) < 0.0001, "taux_decroissance doit valoir plancher + facteur*permeabilite")

func _causes_de() -> void:
	var objets := [
		{"id": "a", "position": Vector3.ZERO, "proprietes": {"source_humidite": true}},
		{"id": "b", "position": Vector3(5, 0, 0), "proprietes": {"source_humidite": false}},
	]
	var causes := BancPermeabilite.causes_de(objets, "source_humidite")
	verif.v(causes.size() == 1 and causes[0].position == Vector3.ZERO, "causes_de doit retenir uniquement les objets portant propriete_cause a vrai")

func _basculer_source() -> void:
	var source := _source(true)
	BancPermeabilite.basculer_source(source, "source_humidite")
	verif.v(not source.proprietes.source_humidite, "basculer_source doit inverser true -> false")
	BancPermeabilite.basculer_source(source, "source_humidite")
	verif.v(source.proprietes.source_humidite, "basculer_source doit inverser false -> true")

# Un canal/propriete/poser invente, sans aucun rapport avec l'humidite,
# doit traverser exactement le meme code -- meme serrure que
# test_banc_humidite.gd:_hors_domaine_avancer_ignore_le_domaine.
func _hors_domaine_avancer_ignore_le_domaine() -> void:
	var config_invente := {
		"propriete_cause": "emet_zorglonium",
		"propriete_permeabilite": "permeabilite_zorglonium",
		"nom_canal": "zorglonium",
		"nom_marque": "irradie_zorglonium",
		"taux_decroissance_plancher": 0.1,
		"facteur_permeabilite": 3.0,
	}
	var materiaux_invente := {"alliage_zorglonium": {"permeabilite_zorglonium": 0.4}}
	var cible := {
		"id": "cobaye",
		"position": Vector3(10, 0, 0),
		"proprietes": {
			"composition": [{"materiau": "alliage_zorglonium", "volume": 1.0}],
			"etats": {"zorglonium": {"charge": 0.0, "seuil": 1.0, "portee_charge": 50.0, "taux_decroissance": 0.0, "poser": {"irradie_zorglonium": true}}},
		},
	}
	var emetteur := {"id": "emetteur", "position": Vector3.ZERO, "proprietes": {"emet_zorglonium": true}}

	var permeabilite := BancPermeabilite.permeabilite_ponderee(cible, materiaux_invente, config_invente.propriete_permeabilite)
	verif.v(abs(permeabilite - 0.4) < 0.0001, "permeabilite_ponderee doit lire un domaine invente sans ligne ajoutee")
	var taux := BancPermeabilite.taux_decroissance_permeabilite(permeabilite, config_invente)
	cible.proprietes.etats.zorglonium.taux_decroissance = taux

	for i in 3:
		BancPermeabilite.avancer([cible], emetteur, 1.0, config_invente)
	verif.v(cible.proprietes.get("irradie_zorglonium", false), "un domaine invente doit traverser avancer() exactement comme sature_eau")

func _fabrication_reelle_fusionne_permeabilite_depuis_materiaux_json() -> void:
	var materiaux: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_permeabilite.json"))

	var declarations := [
		{"id": "bois", "position": [0.0, 0.0, 0.0], "composition": [ {"materiau": "bois", "volume": 3.0} ]},
		{"id": "fer", "position": [10.0, 0.0, 0.0], "composition": [ {"materiau": "fer", "volume": 3.0} ]},
	]
	var objets := BancPermeabilite.fabriquer_objets(declarations, materiaux, config)

	var bois: Dictionary = objets[0]
	var fer: Dictionary = objets[1]
	var permeabilite_bois := BancPermeabilite.permeabilite_ponderee(bois, materiaux, "permeabilite")
	var permeabilite_fer := BancPermeabilite.permeabilite_ponderee(fer, materiaux, "permeabilite")
	verif.v(abs(permeabilite_bois - 0.5) < 0.0001, "bois reel doit avoir une permeabilite de 0.5 (materiaux.json)")
	verif.v(abs(permeabilite_fer - 0.0) < 0.0001, "fer reel doit avoir une permeabilite de 0.0 (materiaux.json)")

	var taux_attendu_bois: float = config.taux_decroissance_plancher + config.facteur_permeabilite * permeabilite_bois
	var taux_attendu_fer: float = config.taux_decroissance_plancher + config.facteur_permeabilite * permeabilite_fer
	verif.v(abs(bois.proprietes.etats.humidite.taux_decroissance - taux_attendu_bois) < 0.0001, "bois reel doit porter le taux_decroissance calcule depuis sa permeabilite")
	verif.v(abs(fer.proprietes.etats.humidite.taux_decroissance - taux_attendu_fer) < 0.0001, "fer reel doit porter le taux_decroissance calcule depuis sa permeabilite (plancher seul, permeabilite nulle)")
	verif.v(bois.proprietes.etats.humidite.taux_decroissance > fer.proprietes.etats.humidite.taux_decroissance, "bois (plus permeable) doit avoir un taux_decroissance strictement superieur a fer")
	verif.v(not is_same(bois.proprietes.etats.humidite, fer.proprietes.etats.humidite), "chaque objet fabrique doit avoir son propre canal, jamais un Dictionary partage")

func _donnees_reelles_banc_permeabilite_json() -> void:
	var donnees: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_permeabilite.json"))
	verif.v(donnees.propriete_cause == "source_humidite", "data/banc_permeabilite.json doit declarer propriete_cause")
	verif.v(donnees.propriete_permeabilite == "permeabilite", "data/banc_permeabilite.json doit declarer propriete_permeabilite")
	verif.v(donnees.nom_marque == "sature_eau", "data/banc_permeabilite.json doit declarer nom_marque")
	verif.v(donnees.objets.size() == 2, "data/banc_permeabilite.json doit declarer deux objets")
	var ids: Array = []
	for objet in donnees.objets:
		ids.append(objet.id)
	verif.v(ids.has("permeable") and ids.has("impermeable"), "data/banc_permeabilite.json doit porter permeable et impermeable")
