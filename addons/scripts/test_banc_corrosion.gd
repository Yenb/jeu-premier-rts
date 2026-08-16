extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_corrosion.gd
#
# Verrouille le cablage de banc_corrosion.gd -- les TROIS phases, chacune
# generalisee PAR OBJET (proprietes.etat_corrosion/propriete_corrosion,
# voir en-tete de banc_corrosion.gd pour la correction de domaine qui a
# motive cette generalisation -- le bois ne rouille pas, remplace par
# cuivre/bronze/argent qui suivent chacun leur propre etat d'oxydation) :
# 1. charge.gd (canal de corrosion, un appel par objet pondere par
#    corrodable) + EtatDuree.poser/avancer (pose de l'etat PROPRE A CHAQUE
#    OBJET tant qu'il reste expose, guerison progressive une fois la source
#    coupee) + EtatEffectif.valeur (propriete visee effective, propre a
#    chaque objet, jamais reimplementee ici) ;
# 2. depense.gd (reserve "integrite", SEULEMENT sur les objets qui la
#    portent -- le fer, jamais cuivre/bronze/argent, cosmetiques) +
#    produit.gd (transformer, appele DIRECTEMENT par ce fichier au
#    franchissement du seuil terminal -- depense.gd lui-meme n'a pas de
#    branche "produire").
#
# AUCUN MECANISME DU COEUR TOUCHE par ce chantier : charge.gd/etat_duree.gd/
# etat_effectif.gd/depense.gd/produit.gd/extinction.gd/objet.gd restent
# exactement ceux deja verrouilles par leurs propres tests -- ce fichier
# verrouille uniquement banc_corrosion.gd.

const BancCorrosion = preload("res://scripts/banc_corrosion.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")
const EtatDuree = preload("res://scripts/etat_duree.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

const ETATS := {
	"corrode": {
		"duree": 10.0,
		"effets": [
			{ "propriete": "durete", "mode": "moduler", "facteur": 0.4 },
		],
	},
	"patine_verte": {
		"duree": 12.0,
		"effets": [
			{ "propriete": "reflectivite", "mode": "moduler", "facteur": 0.3 },
		],
	},
	"ternissure": {
		"duree": 12.0,
		"effets": [
			{ "propriete": "reflectivite", "mode": "moduler", "facteur": 0.15 },
		],
	},
}

const CONFIG := {
	"propriete_cause": "source_humidite",
	"declencheur_expose": "expose_corrosion",
	"propriete_corrodable": "corrodable",
	"nom_canal": "corrosion",
	"nom_reserve_integrite": "integrite",
	"cout_integrite_actif": 1.0,
	"marqueur_terminal": "corrosion_totale",
}

const CATALOGUE_SEUILS_INTEGRITE := {
	"epuisement_corrosion": [
		{ "seuil": 0.0, "poser": { "corrosion_totale": true } },
	],
}

const CONFIG_PRODUIRE := {
	"type_produit": "rouille_test",
	"rendement": 0.85,
}

const TABLE := {
	"rouille_test": { "composition": [ { "materiau": "rouille_test_mat", "volume": 1.0 } ] },
}

const MATERIAUX_LOCAUX := {
	"rouille_test_mat": { "densite": 5.0 },
}

func _init() -> void:
	_sans_source_rien_ne_bouge()
	_fer_a_portee_devient_corrode_et_degrade()
	_objet_hors_portee_reste_sain()
	_corrodable_nulle_ne_corrode_jamais()
	_source_retiree_corrode_guerit_progressivement_objet_sauve()
	_reserve_integrite_epuisee_transforme_en_produit()
	_cuivre_verdit_mais_ne_se_transforme_jamais_meme_expose_longtemps()
	_hors_domaine_avancer_ignore_le_domaine()
	_causes_de_et_ponderees()
	_basculer_source()
	_fabrication_reelle_fusionne_corrodable_durete_reflectivite_depuis_materiaux_json()
	_chemin_reel_fer_devient_rouille_cuivre_verdit_sans_jamais_se_transformer()
	_donnees_reelles_banc_corrosion_json()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: sans source rien ne bouge, le fer a portee monte et devient corrode puis se degrade, " +
		"un objet hors portee reste sain, une corrodabilite nulle ne corrode jamais, la source retiree " +
		"guerit progressivement (objet sauve avant l'epuisement), la reserve d'integrite epuisee " +
		"transforme le fer en produit (masse exacte au rendement), le cuivre verdit sans jamais se " +
		"transformer meme expose longtemps, avancer() ignore le domaine, causes_de/causes_ponderees/" +
		"basculer_source purs, la fabrication reelle fusionne corrodable/durete/reflectivite depuis " +
		"materiaux.json, le chemin reel fer/cuivre se comporte comme attendu, et data/banc_corrosion.json " +
		"charge correctement")
	quit(0)

func _objet(id: String, position: Vector3, corrodable: float, nom_etat: String, propriete_visee: String, valeur_base: float, masse: float, canal: Dictionary, reserve_integrite) -> Dictionary:
	var proprietes: Dictionary = {
		"corrodable": corrodable,
		propriete_visee: valeur_base,
		"masse": masse,
		"etats": {"corrosion": canal.duplicate(true)},
		"etats_actifs": [],
		"etat_corrosion": nom_etat,
		"propriete_corrosion": propriete_visee,
	}
	if reserve_integrite != null:
		proprietes["reserves"] = {"integrite": reserve_integrite.duplicate(true)}
	return {"id": id, "position": position, "proprietes": proprietes}

func _canal(seuil: float, portee: float, taux_decroissance: float) -> Dictionary:
	return {
		"charge": 0.0, "seuil": seuil, "portee_charge": portee,
		"taux_decroissance": taux_decroissance, "poser": {"expose_corrosion": true},
	}

func _reserve_integrite(reserve: float) -> Dictionary:
	return {
		"reserve": reserve, "cout_base": 0.0, "surcout_action": 0.0,
		"seuils_ref": "epuisement_corrosion",
	}

func _source(active: bool) -> Dictionary:
	return {"id": "source", "position": Vector3.ZERO, "proprietes": {"source_humidite": active}}

func _sans_source_rien_ne_bouge() -> void:
	var objet := _objet("fer", Vector3(100, 0, 0), 0.8, "corrode", "durete", 4.5, 1800.0, _canal(1.0, 900.0, 0.5), _reserve_integrite(5.0))
	var source := _source(false)
	for i in 10:
		BancCorrosion.avancer([objet], source, 1.0, CONFIG, ETATS, CATALOGUE_SEUILS_INTEGRITE, CONFIG_PRODUIRE, TABLE, MATERIAUX_LOCAUX)
	verif.v(objet.proprietes.etats.corrosion.charge == 0.0, "sans source active, la charge de corrosion doit rester a 0.0")
	verif.v(not objet.proprietes.get("expose_corrosion", false), "sans source active, expose_corrosion ne doit jamais etre pose")
	verif.v(objet.proprietes.etats_actifs.is_empty(), "sans source active, aucun etat ne doit etre pose")
	verif.v(objet.proprietes.reserves.integrite.reserve == 5.0, "sans corrosion, la reserve d'integrite ne doit jamais decroitre")

func _fer_a_portee_devient_corrode_et_degrade() -> void:
	var objet := _objet("fer", Vector3(100, 0, 0), 0.8, "corrode", "durete", 4.5, 1800.0, _canal(1.0, 900.0, 0.5), _reserve_integrite(5.0))
	var source := _source(true)
	for i in 15:
		BancCorrosion.avancer([objet], source, 0.1, CONFIG, ETATS, CATALOGUE_SEUILS_INTEGRITE, CONFIG_PRODUIRE, TABLE, MATERIAUX_LOCAUX)
	verif.v(objet.proprietes.get("expose_corrosion", false), "apres exposition suffisante (charge > seuil), expose_corrosion doit etre pose")
	verif.v(objet.proprietes.etats_actifs.has("corrode"), "expose_corrosion pose doit avoir declenche EtatDuree.poser('corrode')")
	verif.v(objet.proprietes.etats_intensite.get("corrode", 0.0) > 0.9, "juste apres la pose, l'intensite doit rester tres proche de 1.0")
	var pondere := EtatDuree.etats_ponderes(objet, ETATS)
	var eff_durete := EtatEffectif.valeur(objet, "durete", pondere)
	verif.v(eff_durete < 4.5 * 0.41 and eff_durete > 4.5 * 0.39, "corrode avec une intensite proche de 1.0, la durete effective doit etre modulee pres de 0.4 * base (4.5)")

func _objet_hors_portee_reste_sain() -> void:
	var objet := _objet("loin", Vector3(2000, 0, 0), 0.9, "corrode", "durete", 4.5, 1800.0, _canal(1.0, 50.0, 0.5), _reserve_integrite(5.0))
	var source := _source(true)
	for i in 20:
		BancCorrosion.avancer([objet], source, 1.0, CONFIG, ETATS, CATALOGUE_SEUILS_INTEGRITE, CONFIG_PRODUIRE, TABLE, MATERIAUX_LOCAUX)
	verif.v(objet.proprietes.etats.corrosion.charge == 0.0, "hors de portee_charge, la charge doit rester a 0.0 quelle que soit la corrodabilite")
	verif.v(objet.proprietes.etats_actifs.is_empty(), "hors de portee_charge, l'objet ne doit jamais devenir corrode")
	verif.v(objet.proprietes.reserves.integrite.reserve == 5.0, "hors de portee_charge, la reserve d'integrite ne doit jamais decroitre")

# Non-regression : aucun materiau reel du depot n'est exactement a
# corrodable 0.0 (fer 0.8, cuivre 0.5, bronze 0.45, argent 0.55) -- verrou
# direct sur un objet construit a la main pour prouver que le cas limite ne
# casse rien.
func _corrodable_nulle_ne_corrode_jamais() -> void:
	var objet := _objet("verre", Vector3(100, 0, 0), 0.0, "corrode", "durete", 5.0, 1000.0, _canal(1.0, 900.0, 0.5), _reserve_integrite(5.0))
	var source := _source(true)
	for i in 100:
		BancCorrosion.avancer([objet], source, 1.0, CONFIG, ETATS, CATALOGUE_SEUILS_INTEGRITE, CONFIG_PRODUIRE, TABLE, MATERIAUX_LOCAUX)
	verif.v(objet.proprietes.etats.corrosion.charge == 0.0, "corrodable 0.0, la charge doit rester a 0.0 meme apres cent ticks a portee")
	verif.v(objet.proprietes.etats_actifs.is_empty(), "corrodable 0.0, l'objet ne doit jamais devenir corrode")
	verif.v(objet.proprietes.reserves.integrite.reserve == 5.0, "corrodable 0.0, sans jamais devenir corrode, la reserve d'integrite ne doit jamais decroitre")
	verif.v(objet.proprietes.masse == 1000.0, "corrodable 0.0, la masse ne doit jamais changer -- jamais transforme")

func _source_retiree_corrode_guerit_progressivement_objet_sauve() -> void:
	# Reserve genereuse expres : ce test verifie qu'un objet SAUVE A TEMPS ne
	# se transforme jamais -- il faut donc plus de reserve que ce que
	# "corrode" peut consommer meme s'il decroit pendant les 10.0s completes
	# de sa duree (cout_base reste actif tant que "corrode" figure dans
	# etats_actifs, quelle que soit son intensite -- voir avancer()).
	var objet := _objet("fer", Vector3(100, 0, 0), 0.8, "corrode", "durete", 4.5, 1800.0, _canal(1.0, 900.0, 0.5), _reserve_integrite(30.0))
	var source := _source(true)
	for i in 15:
		BancCorrosion.avancer([objet], source, 0.1, CONFIG, ETATS, CATALOGUE_SEUILS_INTEGRITE, CONFIG_PRODUIRE, TABLE, MATERIAUX_LOCAUX)
	verif.v(objet.proprietes.etats_actifs.has("corrode"), "l'objet doit d'abord etre corrode avant de pouvoir guerir")
	var reserve_avant_coupure: float = objet.proprietes.reserves.integrite.reserve
	verif.v(reserve_avant_coupure < 30.0 and reserve_avant_coupure > 0.0, "la reserve d'integrite doit avoir commence a decroitre pendant l'exposition, sans etre epuisee")

	BancCorrosion.basculer_source(source, CONFIG.propriete_cause)
	verif.v(not source.proprietes.source_humidite, "basculer_source doit desactiver une source active")

	# charge (taux_decroissance 0.5/s) redescend vite sous le seuil -- le
	# marqueur expose_corrosion doit se retirer BIEN AVANT que "corrode" ne
	# soit retire par la decroissance lente d'EtatDuree (10.0s).
	for i in 3:
		BancCorrosion.avancer([objet], source, 0.5, CONFIG, ETATS, CATALOGUE_SEUILS_INTEGRITE, CONFIG_PRODUIRE, TABLE, MATERIAUX_LOCAUX)
	verif.v(not objet.proprietes.get("expose_corrosion", false), "source coupee, expose_corrosion doit se retirer rapidement (charge sous le seuil)")
	verif.v(objet.proprietes.etats_actifs.has("corrode"), "expose_corrosion retire ne doit PAS retirer 'corrode' instantanement -- seul EtatDuree.avancer le fait, progressivement")
	verif.v(objet.proprietes.reserves.integrite.reserve <= reserve_avant_coupure, "'corrode' encore actif juste apres la coupure : la reserve d'integrite doit continuer de decroitre (ou rester egale au pas pres), jamais remonter")

	# Ecoule le reste de la duree (10.0s) pour atteindre le retrait complet
	# de "corrode" -- le cout_base de la reserve d'integrite doit alors se
	# regeler a 0.0, la reserve reste FIGEE la ou elle en etait.
	for i in 20:
		BancCorrosion.avancer([objet], source, 0.5, CONFIG, ETATS, CATALOGUE_SEUILS_INTEGRITE, CONFIG_PRODUIRE, TABLE, MATERIAUX_LOCAUX)
	verif.v(not objet.proprietes.etats_actifs.has("corrode"), "apres 10.0s ecoulees sans exposition, 'corrode' doit avoir ete retire par EtatDuree.avancer")
	verif.v(objet.proprietes.reserves.integrite.reserve > 0.0, "l'objet gueri AVANT l'epuisement de sa reserve d'integrite doit rester sauve -- jamais transforme")
	verif.v(objet.proprietes.masse == 1800.0, "objet sauve : la masse ne doit jamais avoir change, jamais transforme en produit")
	var reserve_finale: float = objet.proprietes.reserves.integrite.reserve
	for i in 20:
		BancCorrosion.avancer([objet], source, 0.5, CONFIG, ETATS, CATALOGUE_SEUILS_INTEGRITE, CONFIG_PRODUIRE, TABLE, MATERIAUX_LOCAUX)
	verif.v(objet.proprietes.reserves.integrite.reserve == reserve_finale, "'corrode' absent et source coupee : la reserve d'integrite doit rester FIGEE indefiniment (cout_base regele a 0.0), jamais reprendre sa decroissance seule")

func _reserve_integrite_epuisee_transforme_en_produit() -> void:
	var objet := _objet("fer", Vector3(100, 0, 0), 0.8, "corrode", "durete", 4.5, 1800.0, _canal(1.0, 900.0, 0.5), _reserve_integrite(5.0))
	var source := _source(true)
	var resultat: Dictionary = {}
	var transforme_a_ce_tick := false
	for i in 40:
		resultat = BancCorrosion.avancer([objet], source, 0.5, CONFIG, ETATS, CATALOGUE_SEUILS_INTEGRITE, CONFIG_PRODUIRE, TABLE, MATERIAUX_LOCAUX)
		if resultat.transformes.has("fer"):
			transforme_a_ce_tick = true
			break
	verif.v(transforme_a_ce_tick, "expose sans interruption, la reserve d'integrite du fer doit finir par s'epuiser et le transformer")
	verif.v(not objet.proprietes.has("etats"), "un objet transforme ne doit plus porter 'etats' -- proprietes entierement remplacees")
	verif.v(not objet.proprietes.has("reserves"), "un objet transforme ne doit plus porter 'reserves' -- proprietes entierement remplacees")
	verif.v(not objet.proprietes.has("corrosion_totale"), "un objet transforme ne doit plus porter le marqueur terminal -- proprietes entierement remplacees")
	verif.v(objet.proprietes.composition[0].materiau == "rouille_test_mat", "l'objet transforme doit porter la composition du type_produit configure")
	verif.v(abs(objet.proprietes.masse - 1800.0 * 0.85) < 0.01, "la masse produite doit valoir exactement rendement * masse_ancien, jamais posee a la main")

	# Un objet deja transforme ne porte plus "etats"/"reserves" -- un pas
	# supplementaire ne doit produire aucune erreur ni aucun second passage
	# par Produit.transformer (chemin mort garanti par charge.gd/depense.gd
	# eux-memes sur un Dictionary absent/vide).
	var resultat_suivant := BancCorrosion.avancer([objet], source, 0.5, CONFIG, ETATS, CATALOGUE_SEUILS_INTEGRITE, CONFIG_PRODUIRE, TABLE, MATERIAUX_LOCAUX)
	verif.v(resultat_suivant.transformes.is_empty(), "un objet deja transforme ne doit plus jamais reapparaitre dans transformes")

# COSMETIQUE, JAMAIS DESTRUCTIF : un objet SANS reserve d'integrite
# (reserve_integrite == null, comme cuivre/bronze/argent) accumule sa charge,
# devient "patine_verte", sa reflectivite effective chute -- mais reste
# indefiniment exposee sans jamais se transformer, meme sur une tres longue
# fenetre. Verrouille exactement le point souleve par Yael (correction de
# domaine) : contrairement a la rouille, la patine ne detruit pas l'objet.
func _cuivre_verdit_mais_ne_se_transforme_jamais_meme_expose_longtemps() -> void:
	var objet := _objet("cuivre", Vector3(100, 0, 0), 0.5, "patine_verte", "reflectivite", 0.65, 1800.0, _canal(1.0, 900.0, 0.5), null)
	var source := _source(true)
	verif.v(not objet.proprietes.has("reserves"), "cuivre/bronze/argent ne doivent jamais porter de reserve d'integrite")
	var resultat: Dictionary = {}
	for i in 80:
		resultat = BancCorrosion.avancer([objet], source, 0.5, CONFIG, ETATS, CATALOGUE_SEUILS_INTEGRITE, CONFIG_PRODUIRE, TABLE, MATERIAUX_LOCAUX)
	verif.v(objet.proprietes.etats_actifs.has("patine_verte"), "expose longtemps, le cuivre doit avoir developpe sa patine verte")
	var pondere := EtatDuree.etats_ponderes(objet, ETATS)
	var eff_reflectivite := EtatEffectif.valeur(objet, "reflectivite", pondere)
	# Bande large plutot que pincee sur 0.3 exact : sous exposition continue,
	# le facteur reste au REGIME STATIONNAIRE de poser+avancer (repose a 1.0
	# CHAQUE tick puis decremente aussitot de delta/duree, jamais exactement
	# 1.0 en continu) -- verrouille juste une reduction NETTE, pas la valeur
	# au dixieme pres.
	verif.v(eff_reflectivite < 0.65 * 0.4 and eff_reflectivite > 0.0, "la reflectivite effective doit etre nettement reduite par la patine (sous 0.4 * base 0.65)")
	verif.v(resultat.transformes.is_empty(), "meme apres 40 secondes simulees d'exposition continue, le cuivre ne doit JAMAIS se transformer (pas de Phase 3)")
	verif.v(objet.proprietes.masse == 1800.0, "la masse du cuivre ne doit jamais changer -- la patine est cosmetique, jamais destructive")
	verif.v(not objet.proprietes.has("corrosion_totale"), "sans reserve d'integrite, 'corrosion_totale' ne doit jamais etre pose sur le cuivre")

# Un canal/declencheur/etat/reserve/type_produit invente, sans aucun rapport
# avec la corrosion ou le fer, doit traverser exactement le meme code --
# meme serrure que test_banc_pourriture.gd:_hors_domaine_avancer_ignore_le_domaine,
# etendue aux trois phases (accumulation, degradation, transformation).
func _hors_domaine_avancer_ignore_le_domaine() -> void:
	var config_invente := {
		"propriete_cause": "emet_zorglonium",
		"declencheur_expose": "irradie_zorglonium",
		"propriete_corrodable": "sensibilite_zorglonium",
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
			"etat_corrosion": "contamine_zorg",
			"propriete_corrosion": "resistance_zorg",
			"reserves": {"noyau_zorg": {"reserve": 2.0, "cout_base": 0.0, "surcout_action": 0.0, "seuils_ref": "epuisement_zorg"}},
		},
	}
	var emetteur := {"id": "emetteur", "position": Vector3.ZERO, "proprietes": {"emet_zorglonium": true}}

	var resultat: Dictionary = {}
	var transforme := false
	for i in 15:
		resultat = BancCorrosion.avancer([cible], emetteur, 0.5, config_invente, etats_invente, catalogue_seuils_invente, config_produire_invente, table_invente, materiaux_invente)
		if resultat.transformes.has("cobaye"):
			transforme = true
			break
	verif.v(transforme, "un domaine invente doit traverser les trois phases (accumulation/degradation/transformation) exactement comme le fer")
	verif.v(cible.proprietes.composition[0].materiau == "poussiere_zorg_mat", "le domaine invente doit produire le type_produit configure")
	verif.v(abs(cible.proprietes.masse - 100.0 * 0.5) < 0.01, "le domaine invente doit respecter le rendement exact, comme le domaine reel")

func _causes_de_et_ponderees() -> void:
	var objets := [
		{"id": "a", "position": Vector3.ZERO, "proprietes": {"source_humidite": true}},
		{"id": "b", "position": Vector3(5, 0, 0), "proprietes": {"source_humidite": false}},
	]
	var causes := BancCorrosion.causes_de(objets, "source_humidite")
	verif.v(causes.size() == 1 and causes[0].position == Vector3.ZERO, "causes_de doit retenir uniquement les objets portant propriete_cause a vrai")

	var ponderees := BancCorrosion.causes_ponderees(causes, 0.4)
	verif.v(ponderees.size() == 1 and abs(ponderees[0].poids - 0.4) < 0.0001, "causes_ponderees doit multiplier le poids implicite (1.0) par le facteur donne")

	var causes_avec_poids := [{"position": Vector3.ZERO, "poids": 2.0}]
	var ponderees2 := BancCorrosion.causes_ponderees(causes_avec_poids, 0.5)
	verif.v(abs(ponderees2[0].poids - 1.0) < 0.0001, "causes_ponderees doit multiplier un poids DEJA explicite, jamais l'ignorer")

func _basculer_source() -> void:
	var source := _source(true)
	BancCorrosion.basculer_source(source, "source_humidite")
	verif.v(not source.proprietes.source_humidite, "basculer_source doit inverser true -> false")
	BancCorrosion.basculer_source(source, "source_humidite")
	verif.v(source.proprietes.source_humidite, "basculer_source doit inverser false -> true")

# Chemin REEL : materiaux.json/proprietes_immuables_composition.json lus sur
# disque, comme test_banc_humidite.gd/test_banc_pourriture.gd le font --
# verrouille que corrodable/durete/reflectivite sont bien fusionnees par
# Objet.fabriquer via fabriquer_objets(), independamment de tout cablage de
# scene, et que chaque objet recoit bien SON PROPRE etat/propriete visee
# depuis sa declaration.
func _fabrication_reelle_fusionne_corrodable_durete_reflectivite_depuis_materiaux_json() -> void:
	var materiaux: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))
	var proprietes_immuables: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/proprietes_immuables_composition.json")).get("proprietes", [])
	verif.v(proprietes_immuables.has("corrodable"), "data/proprietes_immuables_composition.json doit lister corrodable")
	verif.v(proprietes_immuables.has("durete"), "data/proprietes_immuables_composition.json doit lister durete")
	verif.v(proprietes_immuables.has("reflectivite"), "data/proprietes_immuables_composition.json doit lister reflectivite")

	var declarations := [
		{"id": "fer", "position": [0.0, 0.0, 0.0], "composition": [ {"materiau": "fer", "volume": 3.0} ], "nom_etat": "corrode", "propriete_visee": "durete", "reserve_integrite": true},
		{"id": "cuivre", "position": [10.0, 0.0, 0.0], "composition": [ {"materiau": "cuivre", "volume": 3.0} ], "nom_etat": "patine_verte", "propriete_visee": "reflectivite"},
		{"id": "argent", "position": [20.0, 0.0, 0.0], "composition": [ {"materiau": "argent", "volume": 3.0} ], "nom_etat": "ternissure", "propriete_visee": "reflectivite"},
	]
	var config := {
		"nom_canal": "corrosion", "canal_defaut": _canal(1.0, 700.0, 0.5),
		"nom_reserve_integrite": "integrite", "reserve_integrite_defaut": _reserve_integrite(5.0),
	}
	var objets := BancCorrosion.fabriquer_objets(declarations, materiaux, proprietes_immuables, config)

	var fer: Dictionary = objets[0]
	var cuivre: Dictionary = objets[1]
	var argent: Dictionary = objets[2]
	verif.v(abs(fer.proprietes.corrodable - 0.8) < 0.0001, "fer reel doit fusionner corrodable=0.8 depuis materiaux.json")
	verif.v(abs(fer.proprietes.durete - 4.5) < 0.0001, "fer reel doit fusionner durete=4.5 depuis materiaux.json")
	verif.v(fer.proprietes.etat_corrosion == "corrode", "fer doit porter son propre etat_corrosion 'corrode'")
	verif.v(fer.proprietes.has("reserves"), "fer doit porter une reserve d'integrite (reserve_integrite: true dans sa declaration)")

	verif.v(abs(cuivre.proprietes.corrodable - 0.5) < 0.0001, "cuivre reel doit fusionner corrodable=0.5 depuis materiaux.json")
	verif.v(abs(cuivre.proprietes.reflectivite - 0.65) < 0.0001, "cuivre reel doit fusionner reflectivite=0.65 depuis materiaux.json")
	verif.v(cuivre.proprietes.etat_corrosion == "patine_verte", "cuivre doit porter son propre etat_corrosion 'patine_verte'")
	verif.v(not cuivre.proprietes.has("reserves"), "cuivre ne doit JAMAIS porter de reserve d'integrite (reserve_integrite absent de sa declaration)")

	verif.v(abs(argent.proprietes.corrodable - 0.55) < 0.0001, "argent reel doit fusionner corrodable=0.55 depuis materiaux.json")
	verif.v(abs(argent.proprietes.reflectivite - 0.95) < 0.0001, "argent reel doit fusionner reflectivite=0.95 depuis materiaux.json")
	verif.v(argent.proprietes.etat_corrosion == "ternissure", "argent doit porter son propre etat_corrosion 'ternissure'")
	verif.v(not argent.proprietes.has("reserves"), "argent ne doit JAMAIS porter de reserve d'integrite")

	verif.v(not is_same(fer.proprietes.etats.corrosion, cuivre.proprietes.etats.corrosion), "chaque objet fabrique doit avoir son propre canal, jamais un Dictionary partage")

# Chemin REEL complet : data/types.json/data/materiaux.json/
# data/transformations.json lus sur disque, comme banc_corrosion.gd les
# charge lui-meme a _ready() -- le fer se corrode et finit par devenir de la
# rouille reelle (data/transformations.json:corrosion_fer), le cuivre verdit
# mais reste intact et n'est JAMAIS transforme meme sur une longue fenetre --
# preuve chemin reel de la correction de domaine (patine cosmetique, jamais
# destructive, contrairement a la rouille).
func _chemin_reel_fer_devient_rouille_cuivre_verdit_sans_jamais_se_transformer() -> void:
	var materiaux: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))
	var proprietes_immuables: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/proprietes_immuables_composition.json")).get("proprietes", [])
	var catalogue_types: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/types.json"))
	var transformations: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/transformations.json")).get("transformations", {})
	var config_produire_reel: Dictionary = transformations.get("corrosion_fer", {}).get("a_zero", {}).get("produire", {})
	verif.v(config_produire_reel.get("type_produit", "") == "rouille", "data/transformations.json:corrosion_fer doit produire 'rouille'")

	var declarations := [
		{"id": "fer_reel", "position": [0.0, 0.0, 0.0], "composition": [ {"materiau": "fer", "volume": 3.0} ], "nom_etat": "corrode", "propriete_visee": "durete", "reserve_integrite": true},
		{"id": "cuivre_reel", "position": [10.0, 0.0, 0.0], "composition": [ {"materiau": "cuivre", "volume": 3.0} ], "nom_etat": "patine_verte", "propriete_visee": "reflectivite"},
	]
	var config := {
		"nom_canal": "corrosion", "canal_defaut": _canal(1.0, 700.0, 0.5),
		"nom_reserve_integrite": "integrite", "reserve_integrite_defaut": _reserve_integrite(5.0),
	}
	var objets := BancCorrosion.fabriquer_objets(declarations, materiaux, proprietes_immuables, config)
	var fer: Dictionary = objets[0]
	var cuivre: Dictionary = objets[1]
	var masse_fer_avant: float = fer.proprietes.masse

	var source := _source(true)
	var config_avancer := {
		"propriete_cause": "source_humidite", "declencheur_expose": "expose_corrosion",
		"propriete_corrodable": "corrodable", "nom_canal": "corrosion",
		"nom_reserve_integrite": "integrite", "cout_integrite_actif": 1.0, "marqueur_terminal": "corrosion_totale",
	}
	var transforme_fer := false
	# 40 pas de 0.5s = 20s : largement suffisant pour epuiser la reserve du
	# fer (seuil franchi vers t=1.5s, reserve de 5.0 epuisee ~5s plus tard) ET
	# pour que le cuivre (corrodable 0.5, charge = 0.5*20 = 10.0 >> seuil
	# 1.0) developpe pleinement sa patine -- preuve que meme longuement
	# expose et corrode, le cuivre ne se transforme jamais (pas de Phase 3).
	for i in 40:
		var r := BancCorrosion.avancer(objets, source, 0.5, config_avancer, ETATS, CATALOGUE_SEUILS_INTEGRITE, config_produire_reel, catalogue_types, materiaux)
		if r.transformes.has("fer_reel"):
			transforme_fer = true

	verif.v(transforme_fer, "chemin reel : le fer expose sans interruption doit finir par devenir de la rouille")
	verif.v(fer.proprietes.composition[0].materiau == "rouille", "chemin reel : le fer transforme doit porter la composition 'rouille'")
	verif.v(abs(fer.proprietes.masse - masse_fer_avant * 0.85) < 0.01, "chemin reel : la masse de rouille doit valoir exactement rendement (0.85) * masse du fer")

	verif.v(cuivre.proprietes.etats_actifs.has("patine_verte"), "chemin reel : expose aussi longtemps que le fer, le cuivre doit avoir developpe sa patine")
	verif.v(cuivre.proprietes.composition[0].materiau == "cuivre", "chemin reel : le cuivre ne doit JAMAIS etre transforme, meme longuement expose et corrode")
	verif.v(not cuivre.proprietes.has("reserves"), "chemin reel : le cuivre ne doit jamais porter de reserve d'integrite")

# Verrouille que data/banc_corrosion.json charge et resout bien les champs
# que banc_corrosion.gd lit -- desormais quatre objets, chacun avec son
# propre etat/propriete visee, seul le fer avec reserve_integrite.
func _donnees_reelles_banc_corrosion_json() -> void:
	var donnees: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_corrosion.json"))
	verif.v(donnees.propriete_cause == "source_humidite", "data/banc_corrosion.json doit declarer propriete_cause")
	verif.v(donnees.declencheur_expose == "expose_corrosion", "data/banc_corrosion.json doit declarer declencheur_expose")
	verif.v(donnees.propriete_corrodable == "corrodable", "data/banc_corrosion.json doit declarer propriete_corrodable")
	verif.v(donnees.nom_reserve_integrite == "integrite", "data/banc_corrosion.json doit declarer nom_reserve_integrite")
	verif.v(donnees.transformation_terminale == "corrosion_fer", "data/banc_corrosion.json doit reutiliser l'entree 'corrosion_fer' (data/transformations.json)")
	verif.v(donnees.objets.size() == 4, "data/banc_corrosion.json doit declarer quatre objets (fer/cuivre/bronze/argent)")

	var par_id: Dictionary = {}
	for objet in donnees.objets:
		par_id[objet.id] = objet
	verif.v(par_id.has("fer_0") and par_id.has("cuivre_0") and par_id.has("bronze_0") and par_id.has("argent_0"), "data/banc_corrosion.json doit porter les quatre metaux du chantier")
	verif.v(par_id.fer_0.nom_etat == "corrode" and par_id.fer_0.get("reserve_integrite", false), "le fer doit viser 'corrode' et porter reserve_integrite")
	verif.v(par_id.cuivre_0.nom_etat == "patine_verte" and not par_id.cuivre_0.get("reserve_integrite", false), "le cuivre doit viser 'patine_verte' sans reserve_integrite")
	verif.v(par_id.bronze_0.nom_etat == "patine_verte" and not par_id.bronze_0.get("reserve_integrite", false), "le bronze doit viser 'patine_verte' sans reserve_integrite")
	verif.v(par_id.argent_0.nom_etat == "ternissure" and not par_id.argent_0.get("reserve_integrite", false), "l'argent doit viser 'ternissure' sans reserve_integrite")

	var etats: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/etats.json"))
	verif.v(etats.has("corrode") and etats.has("patine_verte") and etats.has("ternissure"), "data/etats.json doit porter les trois entrees partagees corrode/patine_verte/ternissure")
	var transformations: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/transformations.json")).get("transformations", {})
	verif.v(transformations.has("corrosion_fer"), "data/transformations.json doit porter l'entree partagee 'corrosion_fer'")
	var seuils: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/seuils_combustible.json"))
	verif.v(seuils.has("epuisement_corrosion"), "data/seuils_combustible.json (catalogue PARTAGE de seuils_ref) doit porter l'entree 'epuisement_corrosion'")
	verif.v(donnees.reserve_integrite_defaut.seuils_ref == "epuisement_corrosion", "data/banc_corrosion.json:reserve_integrite_defaut doit referencer 'epuisement_corrosion'")

	var mats: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))
	verif.v(mats.has("cuivre") and mats.has("bronze") and mats.has("argent") and mats.has("rouille"), "data/materiaux.json doit porter cuivre/bronze/argent/rouille")
