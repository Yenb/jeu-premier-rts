extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_produit.gd
#
# Verrouille scripts/produit.gd : rendement de MASSE (jamais de volume),
# aucun nom de matiere en dur, masse toujours DERIVEE via Objet.fabriquer
# (jamais posee a la main). Catalogues entierement fictifs, hors domaine
# de bout en bout -- aucun rapport avec bois/charbon/cendre (le chemin
# reel sur ces noms est verrouille par le banc dedie, pas ici).

const Produit = preload("res://scripts/produit.gd")
const Objet = preload("res://scripts/objet.gd")
const Verif = preload("res://scripts/verif.gd")

const MATERIAUX := {
	"poudre_zorg": {"densite": 1.0},
	"gel_zorg": {"densite": 2.0},
}

const TABLE := {
	"objet_zorg": {
		"composition": [{"materiau": "poudre_zorg", "volume": 4.0}],
	},
	"cristal_zorg": {
		"composition": [{"materiau": "poudre_zorg", "volume": 1.0}],
	},
	"alliage_zorg": {
		"composition": [
			{"materiau": "poudre_zorg", "volume": 1.0},
			{"materiau": "gel_zorg", "volume": 3.0},
		],
	},
	"vide_zorg": {
		"composition": [],
	},
}

func _init() -> void:
	var v := Verif.new()
	_rendement_plein_conserve_toute_la_masse(v)
	_rendement_partiel_donne_la_fraction_exacte(v)
	_rendement_zero_ne_produit_rien(v)
	_rendement_negatif_ne_produit_rien(v)
	_configuration_incomplete_ne_produit_rien(v)
	_type_produit_absent_de_la_table_ne_produit_rien(v)
	_type_sans_composition_exploitable_ne_produit_rien(v)
	_materiau_sans_densite_ne_produit_rien(v)
	_patron_produit_se_fusionne_sans_ecraser_la_composition(v)
	_multi_materiaux_conserve_la_masse_totale_exacte(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: produit.gd derive toujours la masse d'un rendement, jamais un nom de matiere en dur")
		quit(0)

func _masse_ancien(volume: float) -> float:
	var fab := Objet.fabriquer("ancien", "objet_zorg",
		Vector3.ZERO,
		{"objet_zorg": {"composition": [{"materiau": "poudre_zorg", "volume": volume}]}},
		MATERIAUX)
	return fab.proprietes.masse

func _rendement_plein_conserve_toute_la_masse(v: Verif) -> void:
	var masse_ancien := _masse_ancien(4.0)
	var proprietes := Produit.transformer({"masse": masse_ancien}, {"type_produit": "cristal_zorg", "rendement": 1.0}, TABLE, MATERIAUX)
	v.v(not proprietes.is_empty(), "rendement 1.0 doit produire un objet")
	v.v(is_equal_approx(proprietes.masse, masse_ancien), "rendement 1.0 doit conserver exactement la masse ancienne (%.4f vu, %.4f attendu)" % [proprietes.get("masse", -1.0), masse_ancien])

func _rendement_partiel_donne_la_fraction_exacte(v: Verif) -> void:
	var masse_ancien := _masse_ancien(4.0)
	var proprietes := Produit.transformer({"masse": masse_ancien}, {"type_produit": "cristal_zorg", "rendement": 0.3}, TABLE, MATERIAUX)
	v.v(is_equal_approx(proprietes.masse, masse_ancien * 0.3), "rendement 0.3 doit rendre exactement 30% de la masse ancienne")

func _rendement_zero_ne_produit_rien(v: Verif) -> void:
	var masse_ancien := _masse_ancien(4.0)
	var proprietes := Produit.transformer({"masse": masse_ancien}, {"type_produit": "cristal_zorg", "rendement": 0.0}, TABLE, MATERIAUX)
	v.v(proprietes.is_empty(), "rendement 0.0 ne doit rien produire (tout est perdu)")

func _rendement_negatif_ne_produit_rien(v: Verif) -> void:
	var proprietes := Produit.transformer({"masse": 10.0}, {"type_produit": "cristal_zorg", "rendement": -0.5}, TABLE, MATERIAUX)
	v.v(proprietes.is_empty(), "un rendement negatif ne doit rien produire")

func _configuration_incomplete_ne_produit_rien(v: Verif) -> void:
	var sans_type := Produit.transformer({"masse": 10.0}, {"rendement": 0.5}, TABLE, MATERIAUX)
	v.v(sans_type.is_empty(), "config sans type_produit ne doit rien produire")
	var sans_rendement := Produit.transformer({"masse": 10.0}, {"type_produit": "cristal_zorg"}, TABLE, MATERIAUX)
	v.v(sans_rendement.is_empty(), "config sans rendement ne doit rien produire")

func _type_produit_absent_de_la_table_ne_produit_rien(v: Verif) -> void:
	var proprietes := Produit.transformer({"masse": 10.0}, {"type_produit": "fantome_zorg", "rendement": 0.5}, TABLE, MATERIAUX)
	v.v(proprietes.is_empty(), "un type_produit absent de la table ne doit rien produire")

func _type_sans_composition_exploitable_ne_produit_rien(v: Verif) -> void:
	var proprietes := Produit.transformer({"masse": 10.0}, {"type_produit": "vide_zorg", "rendement": 0.5}, TABLE, MATERIAUX)
	v.v(proprietes.is_empty(), "un type produit sans composition exploitable ne doit rien produire")

func _materiau_sans_densite_ne_produit_rien(v: Verif) -> void:
	var table_locale: Dictionary = TABLE.duplicate(true)
	table_locale["cristal_sans_densite"] = {"composition": [{"materiau": "materiau_fantome", "volume": 1.0}]}
	var proprietes := Produit.transformer({"masse": 10.0}, {"type_produit": "cristal_sans_densite", "rendement": 0.5}, table_locale, MATERIAUX)
	v.v(proprietes.is_empty(), "un materiau absent de materiaux.json (ou sans densite) ne doit rien produire")

func _patron_produit_se_fusionne_sans_ecraser_la_composition(v: Verif) -> void:
	var masse_ancien := _masse_ancien(4.0)
	var config := {
		"type_produit": "cristal_zorg",
		"rendement": 0.5,
		"patron_produit": {"travail_restant": 2.0, "transformation": "consumer_cristal_zorg", "en_combustion": true},
	}
	var proprietes := Produit.transformer({"masse": masse_ancien}, config, TABLE, MATERIAUX)
	v.v(proprietes.get("travail_restant", -1.0) == 2.0, "patron_produit doit poser travail_restant")
	v.v(proprietes.get("transformation", "") == "consumer_cristal_zorg", "patron_produit doit poser transformation")
	v.v(proprietes.get("en_combustion", false), "patron_produit doit pouvoir poser une cle arbitraire")
	v.v(is_equal_approx(proprietes.masse, masse_ancien * 0.5), "patron_produit ne doit jamais ecraser la masse derivee de la composition")

func _multi_materiaux_conserve_la_masse_totale_exacte(v: Verif) -> void:
	var masse_ancien := _masse_ancien(8.0)
	var proprietes := Produit.transformer({"masse": masse_ancien}, {"type_produit": "alliage_zorg", "rendement": 0.4}, TABLE, MATERIAUX)
	v.v(not proprietes.is_empty(), "un produit a plusieurs materiaux doit se fabriquer")
	v.v(is_equal_approx(proprietes.masse, masse_ancien * 0.4), "la masse totale d'un produit a plusieurs materiaux doit rester exacte quelles que soient leurs densites respectives")
	v.v(proprietes.composition.size() == 2, "la composition du produit doit garder les deux materiaux du gabarit")
