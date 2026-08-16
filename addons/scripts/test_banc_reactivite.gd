extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_reactivite.gd
#
# Verrouille le cablage de banc_reactivite.gd -- les QUATRE phases :
# 1. charge.gd (canal "reaction" par cible, pondere par score_reaction =
#    reactivite(acide) * reactivite(cible), gate stricte sur une entree
#    data/reactions.json existante) ;
# 2. produit.gd (transforme la CIBLE, appele DIRECTEMENT par ce fichier au
#    franchissement du seuil de reaction -- charge.gd n'a pas de branche
#    "produire") ;
# 3. depense.gd (reserve "acide", cout_base recalcule chaque tick =
#    facteur_consommation_acide * somme des reactivites des cibles encore
#    reactives ET a portee de contact -- fermeture explicite a zero une fois
#    plus aucune cible reactive) ;
# 4. produit.gd (transforme l'ACIDE, appele DIRECTEMENT au franchissement du
#    seuil de la reserve).
#
# AUCUN MECANISME DU COEUR TOUCHE par ce chantier : charge.gd/depense.gd/
# produit.gd/portee.gd/objet.gd restent exactement ceux deja verrouilles par
# leurs propres tests -- ce fichier verrouille uniquement banc_reactivite.gd.

const BancReactivite = preload("res://scripts/banc_reactivite.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

const REACTIONS := [
	{ "materiau_a": "acide_test", "materiau_b": "reactif_rapide", "seuil_reactivite": 1.0, "type_produit": "produit_rapide", "rendement": 0.8 },
	{ "materiau_a": "acide_test", "materiau_b": "reactif_moyen", "seuil_reactivite": 1.0, "type_produit": "produit_moyen", "rendement": 0.75 },
	{ "materiau_a": "acide_test", "materiau_b": "reactif_lent", "seuil_reactivite": 1.0, "type_produit": "produit_lent", "rendement": 0.7 },
]

const CONFIG := {
	"materiau_acide": "acide_test",
	"nom_canal_reaction": "reaction",
	"marqueur_pret": "produit_reaction_pret",
	"nom_reserve_acide": "acide",
	"marqueur_acide_epuise": "acide_epuise",
	"facteur_consommation_acide": 0.4,
	"portee_contact": 320.0,
}

const CATALOGUE_SEUILS_ACIDE := {
	"epuisement_test": [ { "seuil": 0.0, "poser": { "acide_epuise": true } } ],
}

const CONFIG_PRODUIRE_ACIDE := {
	"type_produit": "residu_test_acide",
	"rendement": 0.05,
}

const TABLE := {
	"produit_rapide": { "composition": [ { "materiau": "produit_rapide_mat", "volume": 1.0 } ] },
	"produit_moyen": { "composition": [ { "materiau": "produit_moyen_mat", "volume": 1.0 } ] },
	"produit_lent": { "composition": [ { "materiau": "produit_lent_mat", "volume": 1.0 } ] },
	"residu_test_acide": { "composition": [ { "materiau": "residu_test_acide_mat", "volume": 1.0 } ] },
}

const MATERIAUX_LOCAUX := {
	"produit_rapide_mat": { "densite": 2.0 },
	"produit_moyen_mat": { "densite": 2.0 },
	"produit_lent_mat": { "densite": 2.0 },
	"residu_test_acide_mat": { "densite": 1.0 },
}

func _init() -> void:
	_fer_reagit_vite()
	_reactif_lent_reagit_plus_lentement_que_rapide()
	_reactif_moyen_entre_rapide_et_lent()
	_paire_non_reactive_ne_reagit_jamais()
	_hors_portee_aucune_reaction()
	_transformation_produit_lobjet_attendu()
	_hors_domaine_avancer_ignore_le_domaine()
	_acide_se_vide_plus_vite_avec_plus_de_cibles_actives()
	_hors_portee_lacide_ne_se_vide_jamais()
	_sans_aucune_cible_reactive_lacide_est_immediatement_epuise()
	_toutes_les_cibles_reagissent_puis_lacide_devient_residu()
	_trouver_reaction_et_materiau_de_et_score_reaction()
	_basculer_position_acide()
	_fabrication_reelle_fusionne_reactivite_et_initialise_le_seuil()
	_chemin_reel_fer_puis_bois_puis_pierre_puis_acide()
	_donnees_reelles()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: le fer reagit vite, un reactif lent reagit plus lentement qu'un rapide, un reactif moyen se place " +
		"entre les deux, une paire sans entree ne reagit jamais, hors de portee aucune reaction, la transformation " +
		"produit l'objet attendu (masse exacte au rendement), un domaine invente traverse le meme code, l'acide se " +
		"vide plus vite avec plus de cibles actives, hors de portee l'acide ne se vide jamais, sans aucune cible " +
		"reactive l'acide est immediatement epuise, les trois cibles reagissent puis l'acide devient residu sans " +
		"jamais s'epuiser prematurement, trouver_reaction/materiau_de/score_reaction/basculer_position_acide purs, " +
		"la fabrication reelle fusionne reactivite et initialise le seuil depuis data/reactions.json, le chemin " +
		"reel fer/bois/pierre/acide se comporte comme attendu, et data/banc_reactivite.json + les catalogues " +
		"partages chargent correctement")
	quit(0)

func _acide(position: Vector3, reactivite: float, reserve: float) -> Dictionary:
	return {
		"id": "acide",
		"position": position,
		"proprietes": {
			"reactivite": reactivite,
			"masse": 50.0,
			"composition": [ { "materiau": "acide_test", "volume": 1.0 } ],
			"reserves": { "acide": { "reserve": reserve, "cout_base": 0.0, "surcout_action": 0.0, "seuils_ref": "epuisement_test" } },
		},
	}

func _cible(id: String, position: Vector3, reactivite: float, materiau: String, seuil: float, masse: float) -> Dictionary:
	return {
		"id": id,
		"position": position,
		"proprietes": {
			"reactivite": reactivite,
			"masse": masse,
			"composition": [ { "materiau": materiau, "volume": 1.0 } ],
			"etats": { "reaction": { "charge": 0.0, "seuil": seuil, "portee_charge": 320.0, "taux_decroissance": 0.3, "poser": { "produit_reaction_pret": true } } },
		},
	}

func _fer_reagit_vite() -> void:
	var acide := _acide(Vector3.ZERO, 0.95, 3.0)
	var fer := _cible("fer", Vector3(100, 0, 0), 0.6, "reactif_rapide", 1.0, 100.0)
	var transforme := false
	for i in 20:
		var r := BancReactivite.avancer(acide, [fer], 0.5, CONFIG, REACTIONS, CATALOGUE_SEUILS_ACIDE, CONFIG_PRODUIRE_ACIDE, TABLE, MATERIAUX_LOCAUX)
		if r.transformes_cibles.has("fer"):
			transforme = true
			break
	verif.v(transforme, "un reactif a haute reactivite face a un acide reactif doit finir par franchir son seuil de reaction")
	verif.v(fer.proprietes.composition[0].materiau == "produit_rapide_mat", "le reactif transforme doit porter la composition du type_produit configure")

func _reactif_lent_reagit_plus_lentement_que_rapide() -> void:
	var acide_rapide := _acide(Vector3.ZERO, 0.95, 100.0)
	var rapide := _cible("rapide", Vector3(100, 0, 0), 0.6, "reactif_rapide", 1.0, 100.0)
	var acide_lent := _acide(Vector3.ZERO, 0.95, 100.0)
	var lent := _cible("lent", Vector3(100, 0, 0), 0.1, "reactif_lent", 1.0, 100.0)

	var tick_rapide := -1
	var tick_lent := -1
	for i in 40:
		var r1 := BancReactivite.avancer(acide_rapide, [rapide], 0.5, CONFIG, REACTIONS, CATALOGUE_SEUILS_ACIDE, CONFIG_PRODUIRE_ACIDE, TABLE, MATERIAUX_LOCAUX)
		if tick_rapide == -1 and r1.transformes_cibles.has("rapide"):
			tick_rapide = i
		var r2 := BancReactivite.avancer(acide_lent, [lent], 0.5, CONFIG, REACTIONS, CATALOGUE_SEUILS_ACIDE, CONFIG_PRODUIRE_ACIDE, TABLE, MATERIAUX_LOCAUX)
		if tick_lent == -1 and r2.transformes_cibles.has("lent"):
			tick_lent = i
	verif.v(tick_rapide != -1 and tick_lent != -1, "les deux reactifs doivent finir par reagir sur cette fenetre")
	verif.v(tick_lent > tick_rapide, "un reactif de plus basse reactivite doit mettre strictement plus de temps a reagir")

func _reactif_moyen_entre_rapide_et_lent() -> void:
	var acide_rapide := _acide(Vector3.ZERO, 0.95, 100.0)
	var rapide := _cible("rapide", Vector3(100, 0, 0), 0.6, "reactif_rapide", 1.0, 100.0)
	var acide_moyen := _acide(Vector3.ZERO, 0.95, 100.0)
	var moyen := _cible("moyen", Vector3(100, 0, 0), 0.2, "reactif_moyen", 1.0, 100.0)
	var acide_lent := _acide(Vector3.ZERO, 0.95, 100.0)
	var lent := _cible("lent", Vector3(100, 0, 0), 0.1, "reactif_lent", 1.0, 100.0)

	var tick_rapide := -1
	var tick_moyen := -1
	var tick_lent := -1
	for i in 40:
		var r1 := BancReactivite.avancer(acide_rapide, [rapide], 0.5, CONFIG, REACTIONS, CATALOGUE_SEUILS_ACIDE, CONFIG_PRODUIRE_ACIDE, TABLE, MATERIAUX_LOCAUX)
		if tick_rapide == -1 and r1.transformes_cibles.has("rapide"):
			tick_rapide = i
		var r2 := BancReactivite.avancer(acide_moyen, [moyen], 0.5, CONFIG, REACTIONS, CATALOGUE_SEUILS_ACIDE, CONFIG_PRODUIRE_ACIDE, TABLE, MATERIAUX_LOCAUX)
		if tick_moyen == -1 and r2.transformes_cibles.has("moyen"):
			tick_moyen = i
		var r3 := BancReactivite.avancer(acide_lent, [lent], 0.5, CONFIG, REACTIONS, CATALOGUE_SEUILS_ACIDE, CONFIG_PRODUIRE_ACIDE, TABLE, MATERIAUX_LOCAUX)
		if tick_lent == -1 and r3.transformes_cibles.has("lent"):
			tick_lent = i
	verif.v(tick_rapide != -1 and tick_moyen != -1 and tick_lent != -1, "les trois reactifs doivent finir par reagir sur cette fenetre")
	verif.v(tick_rapide < tick_moyen and tick_moyen < tick_lent, "un reactif moyen doit reagir strictement entre le rapide et le lent")

func _paire_non_reactive_ne_reagit_jamais() -> void:
	var acide := _acide(Vector3.ZERO, 0.95, 100.0)
	var inerte := _cible("inerte", Vector3(50, 0, 0), 0.9, "materiau_sans_entree", 1.0, 100.0)
	for i in 100:
		BancReactivite.avancer(acide, [inerte], 1.0, CONFIG, REACTIONS, CATALOGUE_SEUILS_ACIDE, CONFIG_PRODUIRE_ACIDE, TABLE, MATERIAUX_LOCAUX)
	verif.v(inerte.proprietes.etats.reaction.charge == 0.0, "une paire sans entree dans data/reactions.json ne doit jamais accumuler de charge de reaction, meme a haute reactivite et a portee")
	verif.v(not inerte.proprietes.get(CONFIG.marqueur_pret, false), "une paire non reactive ne doit jamais franchir le seuil de reaction")
	verif.v(inerte.proprietes.composition[0].materiau == "materiau_sans_entree", "une paire non reactive ne doit jamais etre transformee")

func _hors_portee_aucune_reaction() -> void:
	var acide := _acide(Vector3(5000, 0, 0), 0.95, 100.0)
	var fer := _cible("fer", Vector3(0, 0, 0), 0.6, "reactif_rapide", 1.0, 100.0)
	for i in 100:
		BancReactivite.avancer(acide, [fer], 1.0, CONFIG, REACTIONS, CATALOGUE_SEUILS_ACIDE, CONFIG_PRODUIRE_ACIDE, TABLE, MATERIAUX_LOCAUX)
	verif.v(fer.proprietes.etats.reaction.charge == 0.0, "hors de portee_charge, la charge de reaction doit rester a 0.0 quelle que soit la reactivite")
	verif.v(fer.proprietes.composition[0].materiau == "reactif_rapide", "hors de portee, la cible ne doit jamais etre transformee")

func _transformation_produit_lobjet_attendu() -> void:
	var acide := _acide(Vector3.ZERO, 0.95, 100.0)
	var fer := _cible("fer", Vector3(50, 0, 0), 0.6, "reactif_rapide", 1.0, 200.0)
	var resultat: Dictionary = {}
	for i in 20:
		resultat = BancReactivite.avancer(acide, [fer], 0.5, CONFIG, REACTIONS, CATALOGUE_SEUILS_ACIDE, CONFIG_PRODUIRE_ACIDE, TABLE, MATERIAUX_LOCAUX)
		if resultat.transformes_cibles.has("fer"):
			break
	verif.v(not fer.proprietes.has("etats"), "une cible transformee ne doit plus porter 'etats' -- proprietes entierement remplacees")
	verif.v(not fer.proprietes.has(CONFIG.marqueur_pret), "une cible transformee ne doit plus porter le marqueur de reaction -- proprietes entierement remplacees")
	verif.v(fer.proprietes.composition[0].materiau == "produit_rapide_mat", "la cible transformee doit porter la composition du type_produit configure")
	verif.v(abs(fer.proprietes.masse - 200.0 * 0.8) < 0.01, "la masse produite doit valoir exactement rendement * masse_ancien, jamais posee a la main")

# Un domaine invente (materiaux/reactions/seuils sans aucun rapport avec
# l'acide/le fer) doit traverser exactement le meme code -- meme serrure que
# test_banc_solubilite.gd:_hors_domaine_avancer_ignore_le_domaine.
func _hors_domaine_avancer_ignore_le_domaine() -> void:
	var reactions_invente := [
		{ "materiau_a": "zorglon_actif", "materiau_b": "cible_zorg", "seuil_reactivite": 1.0, "type_produit": "poussiere_zorg", "rendement": 0.5 },
	]
	var config_invente := {
		"materiau_acide": "zorglon_actif",
		"nom_canal_reaction": "zorglonium",
		"marqueur_pret": "instable_zorg",
		"nom_reserve_acide": "noyau_zorg",
		"marqueur_acide_epuise": "zorglon_epuise",
		"facteur_consommation_acide": 0.4,
		"portee_contact": 50.0,
	}
	var catalogue_seuils_invente := {
		"epuisement_zorg": [ { "seuil": 0.0, "poser": { "zorglon_epuise": true } } ],
	}
	var config_produire_invente := { "type_produit": "cendre_zorg", "rendement": 0.3 }
	var table_invente := {
		"poussiere_zorg": { "composition": [ { "materiau": "poussiere_zorg_mat", "volume": 1.0 } ] },
		"cendre_zorg": { "composition": [ { "materiau": "cendre_zorg_mat", "volume": 1.0 } ] },
	}
	var materiaux_invente := {
		"poussiere_zorg_mat": { "densite": 2.0 },
		"cendre_zorg_mat": { "densite": 1.0 },
	}
	var source := {
		"id": "zorglon", "position": Vector3.ZERO,
		"proprietes": { "reactivite": 1.0, "masse": 50.0, "composition": [ { "materiau": "zorglon_actif", "volume": 1.0 } ],
			"reserves": { "noyau_zorg": { "reserve": 0.5, "cout_base": 0.0, "surcout_action": 0.0, "seuils_ref": "epuisement_zorg" } } },
	}
	var cobaye := {
		"id": "cobaye", "position": Vector3(10, 0, 0),
		"proprietes": { "reactivite": 1.0, "masse": 100.0, "composition": [ { "materiau": "cible_zorg", "volume": 1.0 } ],
			"etats": { "zorglonium": { "charge": 0.0, "seuil": 1.0, "portee_charge": 50.0, "taux_decroissance": 0.2, "poser": { "instable_zorg": true } } } },
	}

	var transforme_cobaye := false
	var transforme_source := false
	for i in 20:
		var r := BancReactivite.avancer(source, [cobaye], 0.5, config_invente, reactions_invente, catalogue_seuils_invente, config_produire_invente, table_invente, materiaux_invente)
		if r.transformes_cibles.has("cobaye"):
			transforme_cobaye = true
		if r.acide_transforme:
			transforme_source = true
	verif.v(transforme_cobaye, "un domaine invente doit traverser la Phase 1/2 (accumulation/transformation de la cible) exactement comme l'acide reel")
	verif.v(cobaye.proprietes.composition[0].materiau == "poussiere_zorg_mat", "le domaine invente doit produire le type_produit configure pour la cible")
	verif.v(transforme_source, "un domaine invente doit traverser la Phase 3/4 (consommation/transformation de la source) exactement comme l'acide reel")
	verif.v(source.proprietes.composition[0].materiau == "cendre_zorg_mat", "le domaine invente doit produire le type_produit configure pour la source")

# "l'acide se vide plus vite avec plus de cibles actives" : deux scenarios,
# memes proprietes, seul le NOMBRE de cibles a portee (toutes reactives) varie
# -- le cout_base recalcule doit etre EXACTEMENT proportionnel a la somme des
# reactivites des cibles actives.
func _acide_se_vide_plus_vite_avec_plus_de_cibles_actives() -> void:
	var acide_seul := _acide(Vector3.ZERO, 0.95, 100.0)
	var fer_seul := _cible("fer", Vector3(50, 0, 0), 0.6, "reactif_rapide", 1.0, 100.0)
	BancReactivite.avancer(acide_seul, [fer_seul], 0.1, CONFIG, REACTIONS, CATALOGUE_SEUILS_ACIDE, CONFIG_PRODUIRE_ACIDE, TABLE, MATERIAUX_LOCAUX)
	var cout_seul: float = acide_seul.proprietes.reserves.acide.cout_base

	var acide_trois := _acide(Vector3.ZERO, 0.95, 100.0)
	var fer_trois := _cible("fer", Vector3(50, 0, 0), 0.6, "reactif_rapide", 1.0, 100.0)
	var moyen_trois := _cible("moyen", Vector3(50, 0, 0), 0.2, "reactif_moyen", 1.0, 100.0)
	var lent_trois := _cible("lent", Vector3(50, 0, 0), 0.1, "reactif_lent", 1.0, 100.0)
	BancReactivite.avancer(acide_trois, [fer_trois, moyen_trois, lent_trois], 0.1, CONFIG, REACTIONS, CATALOGUE_SEUILS_ACIDE, CONFIG_PRODUIRE_ACIDE, TABLE, MATERIAUX_LOCAUX)
	var cout_trois: float = acide_trois.proprietes.reserves.acide.cout_base

	verif.v(cout_trois > cout_seul, "trois cibles actives a portee doivent consommer l'acide plus vite qu'une seule")
	verif.v(abs(cout_seul - CONFIG.facteur_consommation_acide * 0.6) < 0.0001, "le cout_base avec une seule cible active doit valoir exactement facteur * sa reactivite")
	verif.v(abs(cout_trois - CONFIG.facteur_consommation_acide * (0.6 + 0.2 + 0.1)) < 0.0001, "le cout_base avec trois cibles actives doit valoir exactement facteur * la somme de leurs reactivites")

func _hors_portee_lacide_ne_se_vide_jamais() -> void:
	var acide := _acide(Vector3(5000, 0, 0), 0.95, 3.0)
	var fer := _cible("fer", Vector3(0, 0, 0), 0.6, "reactif_rapide", 1.0, 100.0)
	for i in 50:
		BancReactivite.avancer(acide, [fer], 1.0, CONFIG, REACTIONS, CATALOGUE_SEUILS_ACIDE, CONFIG_PRODUIRE_ACIDE, TABLE, MATERIAUX_LOCAUX)
	verif.v(acide.proprietes.reserves.acide.reserve == 3.0, "une cible reactive mais hors de portee_contact ne doit jamais consommer la reserve d'acide")
	verif.v(not acide.proprietes.get(CONFIG.marqueur_acide_epuise, false), "hors de portee, l'acide ne doit jamais s'epuiser")

func _sans_aucune_cible_reactive_lacide_est_immediatement_epuise() -> void:
	var acide := _acide(Vector3.ZERO, 0.95, 3.0)
	var inerte := _cible("inerte", Vector3(10, 0, 0), 0.9, "materiau_sans_entree", 1.0, 100.0)
	var resultat := BancReactivite.avancer(acide, [inerte], 0.5, CONFIG, REACTIONS, CATALOGUE_SEUILS_ACIDE, CONFIG_PRODUIRE_ACIDE, TABLE, MATERIAUX_LOCAUX)
	verif.v(acide.proprietes.reserves.get("acide", {}).get("reserve", -1.0) == 0.0 if not resultat.acide_transforme else true,
		"des lors qu'aucune cible ne porte d'entree reactions.json, la reserve d'acide doit etre forcee a zero (rien a consommer)")
	verif.v(resultat.acide_transforme, "sans aucune cible reactive, l'acide doit se transformer en residu des le premier pas")
	verif.v(acide.proprietes.composition[0].materiau == "residu_test_acide_mat", "l'acide sans rien a consommer doit produire le type_produit configure")

func _toutes_les_cibles_reagissent_puis_lacide_devient_residu() -> void:
	var acide := _acide(Vector3(400, 100, 0), 0.95, 3.0)
	var fer := _cible("fer", Vector3(150, 250, 0), 0.6, "reactif_rapide", 1.0, 100.0)
	var moyen := _cible("moyen", Vector3(400, 250, 0), 0.2, "reactif_moyen", 1.0, 100.0)
	var lent := _cible("lent", Vector3(650, 250, 0), 0.1, "reactif_lent", 1.0, 100.0)
	var cibles := [fer, moyen, lent]

	var reserve_minimale := 3.0
	var toutes_transformees_avant_epuisement := false
	var acide_transforme := false
	for i in 100:
		var r := BancReactivite.avancer(acide, cibles, 0.5, CONFIG, REACTIONS, CATALOGUE_SEUILS_ACIDE, CONFIG_PRODUIRE_ACIDE, TABLE, MATERIAUX_LOCAUX)
		if acide.proprietes.has("reserves"):
			reserve_minimale = min(reserve_minimale, acide.proprietes.reserves.acide.reserve)
		var toutes: bool = (fer.proprietes.composition[0].materiau != "reactif_rapide"
			and moyen.proprietes.composition[0].materiau != "reactif_moyen"
			and lent.proprietes.composition[0].materiau != "reactif_lent")
		if toutes and not toutes_transformees_avant_epuisement:
			toutes_transformees_avant_epuisement = true
		if r.acide_transforme:
			acide_transforme = true
			break

	verif.v(toutes_transformees_avant_epuisement, "les trois cibles (rapide/moyenne/lente) doivent toutes finir par reagir")
	verif.v(reserve_minimale > 0.0, "la reserve d'acide ne doit jamais toucher zero pendant que des cibles sont encore en train de reagir -- calibration verifiee")
	verif.v(acide_transforme, "une fois les trois cibles reagies, l'acide doit finir par devenir residu_test_acide_mat")
	verif.v(acide.proprietes.composition[0].materiau == "residu_test_acide_mat", "l'acide epuise doit porter la composition du type_produit configure")

func _trouver_reaction_et_materiau_de_et_score_reaction() -> void:
	var entree := BancReactivite.trouver_reaction(REACTIONS, "acide_test", "reactif_rapide")
	verif.v(entree.get("type_produit", "") == "produit_rapide", "trouver_reaction doit resoudre la paire declaree")
	var absente := BancReactivite.trouver_reaction(REACTIONS, "acide_test", "materiau_inconnu")
	verif.v(absente.is_empty(), "trouver_reaction doit rendre {} pour une paire non declaree")

	var objet := { "proprietes": { "composition": [ { "materiau": "fer", "volume": 1.0 } ] } }
	verif.v(BancReactivite.materiau_de(objet) == "fer", "materiau_de doit lire le premier element de composition")
	verif.v(BancReactivite.materiau_de({ "proprietes": {} }) == "", "materiau_de doit rendre '' pour un objet sans composition")

	var score := BancReactivite.score_reaction({ "reactivite": 0.95 }, { "reactivite": 0.6 })
	verif.v(abs(score - 0.57) < 0.0001, "score_reaction doit rendre exactement le produit des deux reactivites")

func _basculer_position_acide() -> void:
	var acide := { "position": Vector3(0, -2000, 0) }
	var proche := BancReactivite.basculer_position_acide(acide, false, [1.0, 2.0, 3.0], [0.0, -2000.0, 0.0])
	verif.v(proche, "basculer_position_acide doit passer de loin a proche")
	verif.v(acide.position == Vector3(1.0, 2.0, 3.0), "basculer_position_acide doit deplacer l'objet a la position_proche fournie")
	proche = BancReactivite.basculer_position_acide(acide, proche, [1.0, 2.0, 3.0], [0.0, -2000.0, 0.0])
	verif.v(not proche, "basculer_position_acide doit passer de proche a loin")
	verif.v(acide.position == Vector3(0.0, -2000.0, 0.0), "basculer_position_acide doit deplacer l'objet a la position_loin fournie")

# Chemin REEL : materiaux.json/proprietes_immuables_composition.json/
# reactions.json lus sur disque, comme test_banc_solubilite.gd le fait --
# verrouille que reactivite est bien fusionnee par Objet.fabriquer via
# fabriquer_cibles()/fabriquer_acide(), et que le seuil de chaque cible est
# bien initialise depuis data/reactions.json:seuil_reactivite.
func _fabrication_reelle_fusionne_reactivite_et_initialise_le_seuil() -> void:
	var materiaux: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))
	var proprietes_immuables: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/proprietes_immuables_composition.json")).get("proprietes", [])
	var reactions: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/reactions.json")).get("reactions", [])
	verif.v(proprietes_immuables.has("reactivite"), "data/proprietes_immuables_composition.json doit lister reactivite")

	var config := {
		"materiau_acide": "acide_demo",
		"nom_canal_reaction": "reaction",
		"nom_reserve_acide": "acide",
		"canal_reaction_defaut": { "charge": 0.0, "seuil": 0.0, "portee_charge": 320.0, "taux_decroissance": 0.3, "poser": { "produit_reaction_pret": true } },
		"reserve_acide_defaut": { "reserve": 3.0, "cout_base": 0.0, "surcout_action": 0.0, "seuils_ref": "epuisement_reactivite_acide" },
	}
	var decl_acide := { "id": "acide", "position_proche": [0.0, 0.0, 0.0], "position_loin": [0.0, -2000.0, 0.0], "composition": [ { "materiau": "acide_demo", "volume": 2.0 } ] }
	var acide := BancReactivite.fabriquer_acide(decl_acide, true, materiaux, proprietes_immuables, config)
	verif.v(abs(acide.proprietes.reactivite - 0.95) < 0.0001, "acide_demo reel doit fusionner reactivite=0.95 depuis materiaux.json")
	verif.v(not acide.proprietes.has("etats"), "l'acide ne porte jamais de canal 'etats' -- seule une reserve")

	var declarations := [
		{ "id": "fer", "position": [150.0, 0.0, 0.0], "composition": [ { "materiau": "fer", "volume": 3.0 } ] },
		{ "id": "pierre", "position": [400.0, 0.0, 0.0], "composition": [ { "materiau": "pierre", "volume": 3.0 } ] },
	]
	var cibles := BancReactivite.fabriquer_cibles(declarations, materiaux, proprietes_immuables, config, reactions)
	var fer: Dictionary = cibles[0]
	var pierre: Dictionary = cibles[1]
	verif.v(abs(fer.proprietes.reactivite - 0.6) < 0.0001, "fer reel doit fusionner reactivite=0.6 depuis materiaux.json")
	verif.v(abs(pierre.proprietes.reactivite - 0.1) < 0.0001, "pierre reelle doit fusionner reactivite=0.1 depuis materiaux.json")
	verif.v(abs(fer.proprietes.etats.reaction.seuil - 1.0) < 0.0001, "le canal 'reaction' du fer doit avoir son seuil initialise depuis data/reactions.json:seuil_reactivite")
	verif.v(not is_same(fer.proprietes.etats.reaction, pierre.proprietes.etats.reaction), "chaque cible fabriquee doit avoir son propre canal, jamais un Dictionary partage")

# Chemin REEL complet : data/types.json/data/materiaux.json/
# data/transformations.json/data/reactions.json lus sur disque, comme
# banc_reactivite.gd les charge lui-meme a _ready() -- le fer reagit avant le
# bois, le bois avant la pierre, puis l'acide devient residu_acide une fois
# les trois cibles reagies, sans jamais s'epuiser prematurement.
func _chemin_reel_fer_puis_bois_puis_pierre_puis_acide() -> void:
	var materiaux: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))
	var proprietes_immuables: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/proprietes_immuables_composition.json")).get("proprietes", [])
	var catalogue_types: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/types.json"))
	var reactions: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/reactions.json")).get("reactions", [])
	var transformations: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/transformations.json")).get("transformations", {})
	var config_produire_acide: Dictionary = transformations.get("reactivite_acide_epuise", {}).get("a_zero", {}).get("produire", {})
	var catalogue_seuils_acide: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/seuils_combustible.json"))
	verif.v(config_produire_acide.get("type_produit", "") == "residu_acide", "data/transformations.json:reactivite_acide_epuise doit produire 'residu_acide'")

	var donnees: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_reactivite.json"))
	var config: Dictionary = {
		"materiau_acide": donnees.materiau_acide,
		"nom_canal_reaction": donnees.nom_canal_reaction,
		"marqueur_pret": donnees.marqueur_pret,
		"nom_reserve_acide": donnees.nom_reserve_acide,
		"marqueur_acide_epuise": donnees.marqueur_acide_epuise,
		"facteur_consommation_acide": donnees.facteur_consommation_acide,
		"portee_contact": donnees.portee_contact,
		"canal_reaction_defaut": donnees.canal_reaction_defaut,
		"reserve_acide_defaut": donnees.reserve_acide_defaut,
	}
	var acide := BancReactivite.fabriquer_acide(donnees.acide, true, materiaux, proprietes_immuables, config)
	var cibles := BancReactivite.fabriquer_cibles(donnees.cibles, materiaux, proprietes_immuables, config, reactions)
	var fer: Dictionary = cibles[0]
	var pierre: Dictionary = cibles[1]
	var bois: Dictionary = cibles[2]

	var tick_fer := -1
	var tick_bois := -1
	var tick_pierre := -1
	var reserve_minimale: float = donnees.reserve_acide_defaut.reserve
	var acide_transforme := false
	for i in 100:
		var r := BancReactivite.avancer(acide, cibles, 0.5, config, reactions, catalogue_seuils_acide, config_produire_acide, catalogue_types, materiaux)
		if acide.proprietes.has("reserves"):
			reserve_minimale = min(reserve_minimale, acide.proprietes.reserves.acide.reserve)
		if tick_fer == -1 and r.transformes_cibles.has("fer"):
			tick_fer = i
		if tick_bois == -1 and r.transformes_cibles.has("bois"):
			tick_bois = i
		if tick_pierre == -1 and r.transformes_cibles.has("pierre"):
			tick_pierre = i
		if r.acide_transforme:
			acide_transforme = true
			break

	verif.v(tick_fer != -1 and tick_bois != -1 and tick_pierre != -1, "chemin reel : les trois materiaux doivent tous finir par reagir avec l'acide")
	verif.v(tick_fer < tick_bois and tick_bois < tick_pierre, "chemin reel : le fer (reactivite 0.6) reagit avant le bois (0.2), qui reagit avant la pierre (0.1)")
	verif.v(fer.proprietes.composition[0].materiau == "sel_metallique", "chemin reel : le fer doit devenir sel_metallique")
	verif.v(pierre.proprietes.composition[0].materiau == "residu_calcaire", "chemin reel : la pierre doit devenir residu_calcaire")
	verif.v(bois.proprietes.composition[0].materiau == "residu_organique", "chemin reel : le bois doit devenir residu_organique")
	verif.v(reserve_minimale > 0.0, "chemin reel : la reserve d'acide ne doit jamais toucher zero tant qu'une cible reagit encore -- calibration des constantes de demonstration verifiee")
	verif.v(acide_transforme, "chemin reel : une fois les trois cibles reagies, l'acide doit devenir residu_acide")
	verif.v(acide.proprietes.composition[0].materiau == "residu_acide", "chemin reel : l'acide epuise doit porter la composition 'residu_acide'")

# Verrouille que data/banc_reactivite.json et les catalogues partages neufs
# chargent et resolvent bien les champs que banc_reactivite.gd lit.
func _donnees_reelles() -> void:
	var donnees: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_reactivite.json"))
	verif.v(donnees.materiau_acide == "acide_demo", "data/banc_reactivite.json doit declarer materiau_acide")
	verif.v(donnees.nom_canal_reaction == "reaction", "data/banc_reactivite.json doit declarer nom_canal_reaction")
	verif.v(donnees.nom_reserve_acide == "acide", "data/banc_reactivite.json doit declarer nom_reserve_acide")
	verif.v(donnees.transformation_acide == "reactivite_acide_epuise", "data/banc_reactivite.json doit reutiliser l'entree 'reactivite_acide_epuise'")
	verif.v(donnees.cibles.size() == 3, "data/banc_reactivite.json doit declarer trois cibles (fer/pierre/bois)")
	var ids: Array = []
	for cible in donnees.cibles:
		ids.append(cible.id)
	verif.v(ids.has("fer") and ids.has("pierre") and ids.has("bois"), "data/banc_reactivite.json doit porter les trois materiaux du chantier")

	# data/reactions.json est PARTAGE depuis le chantier « composition en
	# profondeur -- chainage automatique de reactions » (scripts/reaction.gd,
	# mecanisme du coeur) : ce test ne verrouille plus un compte exact ni
	# "materiau_a == acide_demo partout", seulement que les trois entrees
	# necessaires a CE banc y figurent toujours.
	var reactions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/reactions.json"))
	var materiaux_b_pour_acide: Array = []
	for entree in reactions.reactions:
		if entree.materiau_a == "acide_demo":
			materiaux_b_pour_acide.append(entree.materiau_b)
	verif.v(materiaux_b_pour_acide.has("fer") and materiaux_b_pour_acide.has("pierre") and materiaux_b_pour_acide.has("bois"), "data/reactions.json doit toujours couvrir acide_demo+fer/pierre/bois")

	var materiaux: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))
	for nom in ["acide_demo", "sel_metallique", "residu_calcaire", "residu_organique", "residu_acide"]:
		verif.v(materiaux.has(nom), "data/materiaux.json doit porter l'entree '%s'" % nom)

	var types_catalogue: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/types.json"))
	for nom in ["sel_metallique", "residu_calcaire", "residu_organique", "residu_acide"]:
		verif.v(types_catalogue.has(nom), "data/types.json doit porter le type '%s'" % nom)

	var transformations: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/transformations.json")).get("transformations", {})
	verif.v(transformations.has("reactivite_acide_epuise"), "data/transformations.json doit porter l'entree 'reactivite_acide_epuise'")

	var seuils: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/seuils_combustible.json"))
	verif.v(seuils.has("epuisement_reactivite_acide"), "data/seuils_combustible.json doit porter l'entree 'epuisement_reactivite_acide'")
	verif.v(donnees.reserve_acide_defaut.seuils_ref == "epuisement_reactivite_acide", "data/banc_reactivite.json:reserve_acide_defaut doit referencer 'epuisement_reactivite_acide'")
