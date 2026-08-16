extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_humidite.gd
#
# Verrouille le cablage de banc_humidite.gd -- charge.gd (canal d'humidite,
# un appel par objet pondere par absorption_humidite) + EtatDuree.poser/
# avancer (pose de "mouille" tant que l'objet reste expose, sechage
# progressif une fois la source coupee) + EtatEffectif.valeur (inflammabilite
# effective ecrasee a 0.0 par "mouille", jamais reimplementee ici).
#
# AUCUN MECANISME DU COEUR TOUCHE par ce chantier : charge.gd/etat_duree.gd/
# etat_effectif.gd/objet.gd restent exactement ceux deja verrouilles par
# leurs propres tests -- ce fichier verrouille uniquement banc_humidite.gd.

const BancHumidite = preload("res://scripts/banc_humidite.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")
const EtatDuree = preload("res://scripts/etat_duree.gd")
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
	"nom_etat": "mouille",
	"nom_canal": "humidite",
}

func _init() -> void:
	_sans_source_rien_ne_bouge()
	_objet_a_portee_monte_et_devient_mouille_puis_ne_brule_pas()
	_objet_hors_portee_reste_sec()
	_absorption_quasi_nulle_ne_monte_jamais_en_pratique()
	_source_retiree_objet_seche_progressivement_jamais_instantanement()
	_hors_domaine_avancer_ignore_le_domaine()
	_causes_de_et_ponderees()
	_basculer_source()
	_porosite_haute_monte_plus_vite_qu_a_porosite_basse_a_absorption_egale()
	_porosite_nulle_comportement_identique_a_l_existant()
	_fabrication_reelle_fusionne_absorption_humidite_depuis_materiaux_json()
	_donnees_reelles_banc_humidite_json()
	_donnees_reelles_dense_mixte_et_poreux_mixte_partagent_l_absorption_divergent_sur_la_porosite()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: sans source rien ne bouge, un objet a portee monte et devient mouille puis ne brule " +
		"pas, un objet hors portee reste sec, une absorption quasi nulle ne monte jamais en pratique, " +
		"la source retiree seche progressivement (jamais instantanement), avancer() ignore le domaine, " +
		"causes_de/causes_ponderees/basculer_source pures, a absorption egale une porosite haute monte " +
		"plus vite qu'une porosite basse, a porosite nulle le comportement reste identique a l'existant, " +
		"la fabrication reelle fusionne absorption_humidite depuis materiaux.json, data/banc_humidite.json " +
		"charge correctement, et dense_mixte/poreux_mixte partagent bien la meme absorption tout en " +
		"divergeant sur la porosite")
	quit(0)

func _objet(id: String, position: Vector3, absorption: float, inflammabilite: float, canal: Dictionary) -> Dictionary:
	return {
		"id": id,
		"position": position,
		"proprietes": {
			"absorption_humidite": absorption,
			"inflammabilite": inflammabilite,
			"etats": {"humidite": canal.duplicate(true)},
			"etats_actifs": [],
		},
	}

# absorption est passee explicitement (pas recalculee depuis composition) :
# absorption_humidite est une propriete FUSIONNEE UNE FOIS a la fabrication
# (objet.gd:_fusionner_proprietes_immuables), jamais recalculee a la demande
# -- ces objets synthetiques simulent directement le RESULTAT de cette
# fusion, comme _objet() le fait deja pour les autres tests de ce fichier.
# "composition"/materiaux_test ne servent ici qu'a exercer porosite_ponderee,
# seule lecture A LA DEMANDE de ce chantier.
func _objet_avec_composition(id: String, position: Vector3, composition: Array, absorption: float, canal: Dictionary) -> Dictionary:
	return {
		"id": id,
		"position": position,
		"proprietes": {
			"composition": composition,
			"absorption_humidite": absorption,
			"inflammabilite": 0.9,
			"etats": {"humidite": canal.duplicate(true)},
			"etats_actifs": [],
		},
	}

func _canal(seuil: float, portee: float, taux_decroissance: float) -> Dictionary:
	return {
		"charge": 0.0, "seuil": seuil, "portee_charge": portee,
		"taux_decroissance": taux_decroissance, "poser": {"expose_humidite": true},
	}

func _source(active: bool) -> Dictionary:
	return {"id": "source", "position": Vector3.ZERO, "proprietes": {"source_humidite": active}}

func _sans_source_rien_ne_bouge() -> void:
	var objet := _objet("bois", Vector3(100, 0, 0), 0.7, 0.9, _canal(1.0, 900.0, 0.5))
	var source := _source(false)
	for i in 10:
		BancHumidite.avancer([objet], source, 1.0, CONFIG, ETATS)
	verif.v(objet.proprietes.etats.humidite.charge == 0.0, "sans source active, la charge d'humidite doit rester a 0.0")
	verif.v(not objet.proprietes.get("expose_humidite", false), "sans source active, expose_humidite ne doit jamais etre pose")
	verif.v(objet.proprietes.etats_actifs.is_empty(), "sans source active, aucun etat ne doit etre pose")
	var effective := EtatEffectif.valeur(objet, "inflammabilite", EtatDuree.etats_ponderes(objet, ETATS))
	verif.v(effective == 0.9, "sans mouille, l'inflammabilite effective doit rester la valeur de base (0.9)")

func _objet_a_portee_monte_et_devient_mouille_puis_ne_brule_pas() -> void:
	var objet := _objet("bois", Vector3(100, 0, 0), 0.7, 0.9, _canal(1.0, 900.0, 0.5))
	var source := _source(true)
	var resultat: Dictionary = {}
	for i in 15:
		resultat = BancHumidite.avancer([objet], source, 0.1, CONFIG, ETATS)
	verif.v(objet.proprietes.get("expose_humidite", false), "apres exposition suffisante (charge > seuil), expose_humidite doit etre pose")
	verif.v(objet.proprietes.etats_actifs.has("mouille"), "expose_humidite pose doit avoir declenche EtatDuree.poser('mouille')")
	verif.v(objet.proprietes.etats_intensite.get("mouille", 0.0) > 0.9, "juste apres la pose, l'intensite doit rester tres proche de 1.0")
	var effective := EtatEffectif.valeur(objet, "inflammabilite", EtatDuree.etats_ponderes(objet, ETATS))
	verif.v(effective < 0.1, "mouille avec une intensite proche de 1.0, l'inflammabilite effective doit etre ecrasee pres de 0.0 -- l'objet ne brule pas")

func _objet_hors_portee_reste_sec() -> void:
	var objet := _objet("loin", Vector3(2000, 0, 0), 0.9, 0.9, _canal(1.0, 50.0, 0.5))
	var source := _source(true)
	for i in 20:
		BancHumidite.avancer([objet], source, 1.0, CONFIG, ETATS)
	verif.v(objet.proprietes.etats.humidite.charge == 0.0, "hors de portee_charge, la charge doit rester a 0.0 quelle que soit l'absorption")
	verif.v(objet.proprietes.etats_actifs.is_empty(), "hors de portee_charge, l'objet ne doit jamais devenir mouille")

func _absorption_quasi_nulle_ne_monte_jamais_en_pratique() -> void:
	var objet := _objet("fer", Vector3(100, 0, 0), 0.01, 0.02, _canal(1.0, 900.0, 0.5))
	var source := _source(true)
	for i in 30:
		BancHumidite.avancer([objet], source, 1.0, CONFIG, ETATS)
	# 30 ticks * 1.0s * absorption 0.01 = charge 0.30, tres sous le seuil 1.0.
	verif.v(objet.proprietes.etats.humidite.charge < 0.5, "avec une absorption quasi nulle, la charge doit monter tres lentement")
	verif.v(objet.proprietes.etats_actifs.is_empty(), "avec une absorption quasi nulle, l'objet ne doit jamais devenir mouille dans une fenetre d'observation raisonnable")

func _source_retiree_objet_seche_progressivement_jamais_instantanement() -> void:
	var objet := _objet("bois", Vector3(100, 0, 0), 0.7, 0.9, _canal(1.0, 900.0, 0.5))
	var source := _source(true)
	for i in 15:
		BancHumidite.avancer([objet], source, 0.1, CONFIG, ETATS)
	verif.v(objet.proprietes.etats_actifs.has("mouille"), "l'objet doit d'abord etre mouille avant de pouvoir secher")

	BancHumidite.basculer_source(source, CONFIG.propriete_cause)
	verif.v(not source.proprietes.source_humidite, "basculer_source doit desactiver une source active")

	# charge (taux_decroissance 0.5/s) redescend vite sous le seuil -- le
	# marqueur expose_humidite doit se retirer BIEN AVANT que "mouille" ne
	# soit retire par la decroissance lente d'EtatDuree (6.0s).
	for i in 3:
		BancHumidite.avancer([objet], source, 0.5, CONFIG, ETATS)
	verif.v(not objet.proprietes.get("expose_humidite", false), "source coupee, expose_humidite doit se retirer rapidement (charge sous le seuil)")
	verif.v(objet.proprietes.etats_actifs.has("mouille"), "expose_humidite retire ne doit PAS retirer 'mouille' instantanement -- seul EtatDuree.avancer le fait, progressivement")
	var effective_partiel := EtatEffectif.valeur(objet, "inflammabilite", EtatDuree.etats_ponderes(objet, ETATS))
	verif.v(effective_partiel > 0.0 and effective_partiel < 0.9, "a mi-sechage, l'inflammabilite effective doit etre STRICTEMENT entre 0.0 et la base -- preuve de la progressivite (jamais un saut)")

	# Ecoule le reste de la duree (etats.json:mouille.duree = 6.0s) pour
	# atteindre le retrait complet.
	for i in 12:
		BancHumidite.avancer([objet], source, 0.5, CONFIG, ETATS)
	verif.v(not objet.proprietes.etats_actifs.has("mouille"), "apres 6.0s ecoulees sans exposition, 'mouille' doit avoir ete retire par EtatDuree.avancer")
	var effective_final := EtatEffectif.valeur(objet, "inflammabilite", EtatDuree.etats_ponderes(objet, ETATS))
	verif.v(effective_final == 0.9, "'mouille' retire, l'inflammabilite effective doit etre revenue exactement a la base (0.9)")

# Un canal/declencheur/etat/propriete d'absorption inventes, sans aucun
# rapport avec l'humidite ou le feu, doivent traverser exactement le meme
# code -- meme serrure que test_banc_charge.gd:_hors_domaine_decider_ignore_le_domaine.
func _hors_domaine_avancer_ignore_le_domaine() -> void:
	var config_invente := {
		"propriete_cause": "emet_zorglonium",
		"declencheur_expose": "irradie_zorglonium",
		"propriete_absorption": "sensibilite_zorglonium",
		"nom_etat": "contamine",
		"nom_canal": "zorglonium",
	}
	var etats_invente := {
		"contamine": {"duree": 20.0, "effets": [ { "propriete": "resistance", "mode": "ecraser", "valeur": 0.0 } ] },
	}
	var cible := {
		"id": "cobaye",
		"position": Vector3(10, 0, 0),
		"proprietes": {
			"sensibilite_zorglonium": 1.0, "resistance": 5.0,
			"etats": {"zorglonium": {"charge": 0.0, "seuil": 1.0, "portee_charge": 50.0, "taux_decroissance": 0.2, "poser": {"irradie_zorglonium": true}}},
			"etats_actifs": [],
		},
	}
	var emetteur := {"id": "emetteur", "position": Vector3.ZERO, "proprietes": {"emet_zorglonium": true}}
	for i in 3:
		BancHumidite.avancer([cible], emetteur, 1.0, config_invente, etats_invente)
	verif.v(cible.proprietes.etats_actifs.has("contamine"), "un canal/declencheur/etat invente doit traverser avancer() sans ligne ajoutee, exactement comme 'mouille'")
	var effective := EtatEffectif.valeur(cible, "resistance", EtatDuree.etats_ponderes(cible, etats_invente))
	verif.v(effective < 0.5, "l'ecrasement du domaine invente doit fonctionner a l'identique de inflammabilite/mouille (intensite proche de 1.0 -> effective proche de 0.0)")

func _causes_de_et_ponderees() -> void:
	var objets := [
		{"id": "a", "position": Vector3.ZERO, "proprietes": {"source_humidite": true}},
		{"id": "b", "position": Vector3(5, 0, 0), "proprietes": {"source_humidite": false}},
	]
	var causes := BancHumidite.causes_de(objets, "source_humidite")
	verif.v(causes.size() == 1 and causes[0].position == Vector3.ZERO, "causes_de doit retenir uniquement les objets portant propriete_cause a vrai")

	var ponderees := BancHumidite.causes_ponderees(causes, 0.4)
	verif.v(ponderees.size() == 1 and abs(ponderees[0].poids - 0.4) < 0.0001, "causes_ponderees doit multiplier le poids implicite (1.0) par le facteur donne")

	var causes_avec_poids := [{"position": Vector3.ZERO, "poids": 2.0}]
	var ponderees2 := BancHumidite.causes_ponderees(causes_avec_poids, 0.5)
	verif.v(abs(ponderees2[0].poids - 1.0) < 0.0001, "causes_ponderees doit multiplier un poids DEJA explicite, jamais l'ignorer")

func _basculer_source() -> void:
	var source := _source(true)
	BancHumidite.basculer_source(source, "source_humidite")
	verif.v(not source.proprietes.source_humidite, "basculer_source doit inverser true -> false")
	BancHumidite.basculer_source(source, "source_humidite")
	verif.v(source.proprietes.source_humidite, "basculer_source doit inverser false -> true")

# Chantier "porosite -- la porosite comme facteur de vitesse d'absorption".
# Deux objets a composition FICTIVE (materiaux inventes, hors domaine reel)
# partageant la MEME absorption_humidite mais une porosite opposee doivent
# accumuler leur charge d'humidite a des vitesses differentes -- seul la
# porosite les separe (meme discipline que test_combustible.gd/
# test_propagation.gd pour densite/porosite sur la combustion).
func _porosite_haute_monte_plus_vite_qu_a_porosite_basse_a_absorption_egale() -> void:
	var materiaux_test := {
		"materiau_poreux": {"densite": 1.0, "absorption_humidite": 0.5, "porosite": 0.9},
		"materiau_dense": {"densite": 1.0, "absorption_humidite": 0.5, "porosite": 0.05},
	}
	var config := CONFIG.duplicate(true)
	config["propriete_porosite"] = "porosite"
	config["facteur_porosite"] = 2.0

	var objet_poreux := _objet_avec_composition("poreux", Vector3(100, 0, 0), [{"materiau": "materiau_poreux", "volume": 1.0}], 0.5, _canal(1.0, 900.0, 0.5))
	var objet_dense := _objet_avec_composition("dense", Vector3(100, 0, 0), [{"materiau": "materiau_dense", "volume": 1.0}], 0.5, _canal(1.0, 900.0, 0.5))
	verif.v(abs(objet_poreux.proprietes.absorption_humidite - objet_dense.proprietes.absorption_humidite) < 0.0001, "les deux objets fictifs doivent partager exactement la meme absorption_humidite -- seule la porosite doit les separer")
	verif.v(abs(BancHumidite.porosite_ponderee(objet_poreux, materiaux_test, "porosite") - 0.9) < 0.0001, "porosite_ponderee doit lire 0.9 depuis la fiche materiau_poreux")
	verif.v(abs(BancHumidite.porosite_ponderee(objet_dense, materiaux_test, "porosite") - 0.05) < 0.0001, "porosite_ponderee doit lire 0.05 depuis la fiche materiau_dense")

	var source := _source(true)
	for i in 5:
		BancHumidite.avancer([objet_poreux], source, 0.5, config, ETATS, materiaux_test)
		BancHumidite.avancer([objet_dense], source, 0.5, config, ETATS, materiaux_test)
	verif.v(objet_poreux.proprietes.etats.humidite.charge > objet_dense.proprietes.etats.humidite.charge, "a absorption_humidite egale, l'objet a porosite plus haute doit accumuler sa charge d'humidite plus vite que l'objet a porosite plus basse")

# A porosite nulle (objet sans "composition", donc porosite non calculable),
# le comportement doit rester RIGOUREUSEMENT IDENTIQUE a celui d'avant ce
# chantier -- meme trajectoire de charge que l'appel a l'ancienne signature
# (sans "materiaux", sans facteur_porosite dans la config).
func _porosite_nulle_comportement_identique_a_l_existant() -> void:
	var objet_avant_chantier := _objet("bois", Vector3(100, 0, 0), 0.7, 0.9, _canal(1.0, 900.0, 0.5))
	var objet_apres_chantier := _objet("bois", Vector3(100, 0, 0), 0.7, 0.9, _canal(1.0, 900.0, 0.5))
	var source := _source(true)

	var config_avec_porosite := CONFIG.duplicate(true)
	config_avec_porosite["propriete_porosite"] = "porosite"
	config_avec_porosite["facteur_porosite"] = 1.5

	for i in 15:
		BancHumidite.avancer([objet_avant_chantier], source, 0.1, CONFIG, ETATS)
		BancHumidite.avancer([objet_apres_chantier], source, 0.1, config_avec_porosite, ETATS, {})

	verif.v(objet_avant_chantier.proprietes.etats.humidite.charge == objet_apres_chantier.proprietes.etats.humidite.charge, "sans composition (porosite non calculable, rend 0.0), le facteur_porosite ne doit rien changer -- charge identique a l'appel pre-chantier")
	verif.v(objet_avant_chantier.proprietes.etats_actifs.has("mouille") == objet_apres_chantier.proprietes.etats_actifs.has("mouille"), "meme bascule de 'mouille' avec ou sans facteur_porosite quand la porosite ne peut pas se calculer")

# Chemin REEL : materiaux.json/proprietes_immuables_composition.json lus sur
# disque, comme test_banc_charge.gd le fait pour data/types.json -- verrouille
# que absorption_humidite (bois 0.7, pierre 0.1, fer 0.01) est bien fusionnee
# par Objet.fabriquer via fabriquer_objets(), independamment de tout cablage
# de scene.
func _fabrication_reelle_fusionne_absorption_humidite_depuis_materiaux_json() -> void:
	var materiaux: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))
	var proprietes_immuables: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/proprietes_immuables_composition.json")).get("proprietes", [])
	verif.v(proprietes_immuables.has("absorption_humidite"), "data/proprietes_immuables_composition.json doit lister absorption_humidite")

	var declarations := [
		{"id": "bois", "position": [0.0, 0.0, 0.0], "composition": [ {"materiau": "bois", "volume": 3.0} ]},
		{"id": "pierre", "position": [10.0, 0.0, 0.0], "composition": [ {"materiau": "pierre", "volume": 3.0} ]},
		{"id": "fer", "position": [20.0, 0.0, 0.0], "composition": [ {"materiau": "fer", "volume": 3.0} ]},
	]
	var config := {"nom_canal": "humidite", "canal_defaut": _canal(1.0, 700.0, 0.5)}
	var objets := BancHumidite.fabriquer_objets(declarations, materiaux, proprietes_immuables, config)

	var bois: Dictionary = objets[0]
	var pierre: Dictionary = objets[1]
	var fer: Dictionary = objets[2]
	verif.v(abs(bois.proprietes.absorption_humidite - 0.7) < 0.0001, "bois reel doit fusionner absorption_humidite=0.7 depuis materiaux.json")
	verif.v(abs(pierre.proprietes.absorption_humidite - 0.1) < 0.0001, "pierre reelle doit fusionner absorption_humidite=0.1 depuis materiaux.json")
	verif.v(abs(fer.proprietes.absorption_humidite - 0.01) < 0.0001, "fer reel doit fusionner absorption_humidite=0.01 depuis materiaux.json")
	verif.v(abs(bois.proprietes.inflammabilite - 0.9) < 0.0001, "bois reel doit aussi fusionner inflammabilite=0.9 (meme patron, deja demontre)")
	verif.v(not is_same(bois.proprietes.etats.humidite, pierre.proprietes.etats.humidite), "chaque objet fabrique doit avoir son propre canal, jamais un Dictionary partage")

# Verrouille que data/banc_humidite.json charge et resout bien les trois
# objets attendus avec les noms de champ que banc_humidite.gd lit.
func _donnees_reelles_banc_humidite_json() -> void:
	var donnees: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_humidite.json"))
	verif.v(donnees.propriete_cause == "source_humidite", "data/banc_humidite.json doit declarer propriete_cause")
	verif.v(donnees.declencheur_expose == "expose_humidite", "data/banc_humidite.json doit declarer declencheur_expose")
	verif.v(donnees.propriete_absorption == "absorption_humidite", "data/banc_humidite.json doit declarer propriete_absorption")
	verif.v(donnees.nom_etat == "mouille", "data/banc_humidite.json doit reutiliser l'etat 'mouille' existant (data/etats.json)")
	verif.v(donnees.objets.size() == 5, "data/banc_humidite.json doit declarer cinq objets (bois/pierre/fer, dense_mixte/poreux_mixte)")
	var ids: Array = []
	for objet in donnees.objets:
		ids.append(objet.id)
	verif.v(ids.has("bois") and ids.has("pierre") and ids.has("fer"), "data/banc_humidite.json doit porter les trois materiaux du chantier")
	verif.v(ids.has("dense_mixte") and ids.has("poreux_mixte"), "data/banc_humidite.json doit porter la paire dense_mixte/poreux_mixte du chantier porosite")

# Chemin REEL : verrouille que dense_mixte et poreux_mixte, tels que
# declares dans data/banc_humidite.json et fabriques via Objet.fabriquer
# (composition mixte, materiaux reels de data/materiaux.json), partagent
# bien la MEME absorption_humidite (fusionnee) tout en divergeant nettement
# sur la porosite (lue a la demande par porosite_ponderee) -- la preuve que
# la demonstration visuelle isole reellement la porosite comme seule
# variable.
func _donnees_reelles_dense_mixte_et_poreux_mixte_partagent_l_absorption_divergent_sur_la_porosite() -> void:
	var materiaux: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))
	var proprietes_immuables: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/proprietes_immuables_composition.json")).get("proprietes", [])
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_humidite.json"))

	var declarations := []
	for objet_decl in config.objets:
		if objet_decl.id == "dense_mixte" or objet_decl.id == "poreux_mixte":
			declarations.append(objet_decl)
	var objets := BancHumidite.fabriquer_objets(declarations, materiaux, proprietes_immuables, config)
	var dense: Dictionary = objets[0] if objets[0].id == "dense_mixte" else objets[1]
	var poreux: Dictionary = objets[0] if objets[0].id == "poreux_mixte" else objets[1]

	verif.v(abs(dense.proprietes.absorption_humidite - 0.05) < 0.0001, "dense_mixte reel doit fusionner une absorption_humidite de 0.05")
	verif.v(abs(poreux.proprietes.absorption_humidite - 0.05) < 0.0001, "poreux_mixte reel doit fusionner une absorption_humidite de 0.05")
	verif.v(abs(dense.proprietes.absorption_humidite - poreux.proprietes.absorption_humidite) < 0.0001, "dense_mixte et poreux_mixte doivent partager exactement la meme absorption_humidite")

	var porosite_dense := BancHumidite.porosite_ponderee(dense, materiaux, config.propriete_porosite)
	var porosite_poreux := BancHumidite.porosite_ponderee(poreux, materiaux, config.propriete_porosite)
	verif.v(abs(porosite_dense - 0.05362) < 0.001, "dense_mixte reel doit avoir une porosite ponderee proche de 0.0536")
	verif.v(abs(porosite_poreux - 0.525) < 0.0001, "poreux_mixte reel doit avoir une porosite ponderee de 0.525")
	verif.v(porosite_poreux > porosite_dense * 5.0, "poreux_mixte doit etre nettement plus poreux que dense_mixte -- l'ecart doit rester lisible a l'ecran")

	var poids_dense := BancHumidite.poids_receveur_humidite(dense, materiaux, config)
	var poids_poreux := BancHumidite.poids_receveur_humidite(poreux, materiaux, config)
	verif.v(poids_poreux > poids_dense, "a absorption egale, le poids receveur effectif de poreux_mixte doit depasser celui de dense_mixte -- il doit monter plus vite dans le banc reel")
