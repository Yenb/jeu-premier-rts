extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_soudure.gd
#
# Verrouille scripts/soudure.gd (chantier "soudabilite", voir
# audit_soudabilite.md) -- fabriquer_composite (PURE) et souder (mutation
# en place). HORS DOMAINE INTEGRAL : materiaux et compositions fictifs,
# jamais lus sur disque, aucun rapport avec fer/bois -- meme discipline
# que test_produit.gd. Le chemin reel (fer/bois, data/materiaux.json,
# data/proprietes_immuables_composition.json) est verrouille par
# test_banc_soudure.gd, pas ici.

const Objet = preload("res://scripts/objet.gd")
const Soudure = preload("res://scripts/soudure.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

func _init() -> void:
	_fusion_simple_masse_exacte()
	_second_objet_vide_apres_soudure()
	_premier_objet_garde_son_id_et_sa_position()
	_multi_materiaux_masse_totale_exacte()
	_patron_composite_fusionne_sans_ecraser_la_composition()
	_composition_absente_sur_a_refuse_sans_rien_produire()
	_composition_absente_sur_b_refuse_sans_rien_produire()
	_materiau_absent_du_catalogue_refuse()
	_meme_id_refuse_sans_rien_muter()
	_resumabilite_json_stricte()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: soudure.gd fusionne deux compositions reelles (hors domaine) en un " +
		"composite de masse exacte (somme des deux, jamais reinventee), le second " +
		"objet est vide apres soudure, le premier garde id/position, patron_composite " +
		"se fusionne sans ecraser la composition derivee, composition/materiau absents " +
		"refusent sans rien produire, une chose ne se soude jamais a elle-meme, " +
		"resumabilite JSON stricte")
	quit(0)

# ---- fixtures hors domaine, jamais lues sur disque ----

func _materiaux_zorg() -> Dictionary:
	return {
		"alliage_zorg_a": {"densite": 2.0},
		"alliage_zorg_b": {"densite": 5.0},
		"alliage_zorg_c": {"densite": 8.0},
		"sans_densite_zorg": {},
	}

func _proprietes_zorg(materiau: String, volume: float) -> Dictionary:
	return {"composition": [{"materiau": materiau, "volume": volume}]}

func _chose_zorg(id: String, materiau: String, volume: float) -> Dictionary:
	return {"id": id, "position": Vector3(4.0, 5.0, 6.0), "proprietes": _proprietes_zorg(materiau, volume)}

# ---- fusion ----

func _fusion_simple_masse_exacte() -> void:
	var materiaux := _materiaux_zorg()
	var masse_a: float = Objet.fabriquer("a", "a", Vector3.ZERO, {"a": _proprietes_zorg("alliage_zorg_a", 2.0)}, materiaux).proprietes.masse
	var masse_b: float = Objet.fabriquer("b", "b", Vector3.ZERO, {"b": _proprietes_zorg("alliage_zorg_b", 3.0)}, materiaux).proprietes.masse

	var composite := Soudure.fabriquer_composite(_proprietes_zorg("alliage_zorg_a", 2.0), _proprietes_zorg("alliage_zorg_b", 3.0), materiaux)
	verif.v(not composite.is_empty(), "une fusion de deux compositions valides doit produire un resultat non vide")
	verif.v(is_equal_approx(float(composite.masse), masse_a + masse_b), "la masse du composite doit etre EXACTEMENT la somme des deux masses d'origine (%f + %f), recu %f" % [masse_a, masse_b, composite.masse])
	verif.v(composite.composition.size() == 2, "la composition combinee doit porter les DEUX elements d'origine, recu %d" % composite.composition.size())

func _second_objet_vide_apres_soudure() -> void:
	var materiaux := _materiaux_zorg()
	var a := _chose_zorg("a", "alliage_zorg_a", 2.0)
	var b := _chose_zorg("b", "alliage_zorg_b", 3.0)
	var ok := Soudure.souder(a, b, materiaux)
	verif.v(ok, "souder() doit reussir sur deux compositions valides")
	verif.v(b.proprietes.is_empty(), "l'objet absorbe doit voir ses proprietes ENTIEREMENT videes apres soudure, recu %s" % str(b.proprietes))
	verif.v(not a.proprietes.is_empty(), "l'objet survivant ne doit jamais etre vide apres une soudure reussie")

func _premier_objet_garde_son_id_et_sa_position() -> void:
	var materiaux := _materiaux_zorg()
	var a := _chose_zorg("survivant_zorg", "alliage_zorg_a", 2.0)
	var position_avant: Vector3 = a.position
	var b := _chose_zorg("absorbe_zorg", "alliage_zorg_b", 3.0)
	Soudure.souder(a, b, materiaux)
	verif.v(a.id == "survivant_zorg", "l'id du premier objet ne doit jamais changer apres soudure, recu '%s'" % a.id)
	verif.v(a.position == position_avant, "la position du premier objet ne doit jamais changer apres soudure, recu %s" % a.position)

func _multi_materiaux_masse_totale_exacte() -> void:
	var materiaux := _materiaux_zorg()
	# a est deja composite (deux materiaux), b est simple -- verifie que la
	# concatenation ne suppose jamais un seul element par cote.
	var proprietes_a := {"composition": [{"materiau": "alliage_zorg_a", "volume": 1.0}, {"materiau": "alliage_zorg_c", "volume": 1.0}]}
	var proprietes_b := _proprietes_zorg("alliage_zorg_b", 4.0)
	var masse_a: float = Objet.fabriquer("a", "a", Vector3.ZERO, {"a": proprietes_a}, materiaux).proprietes.masse
	var masse_b: float = Objet.fabriquer("b", "b", Vector3.ZERO, {"b": proprietes_b}, materiaux).proprietes.masse

	var composite := Soudure.fabriquer_composite(proprietes_a, proprietes_b, materiaux)
	verif.v(composite.composition.size() == 3, "trois elements de composition (deux + un) doivent tous survivre a la concatenation, recu %d" % composite.composition.size())
	verif.v(is_equal_approx(float(composite.masse), masse_a + masse_b), "masse totale exacte meme quand un cote est deja multi-materiaux, attendu %f, recu %f" % [masse_a + masse_b, composite.masse])

func _patron_composite_fusionne_sans_ecraser_la_composition() -> void:
	var materiaux := _materiaux_zorg()
	var composite := Soudure.fabriquer_composite(
		_proprietes_zorg("alliage_zorg_a", 2.0), _proprietes_zorg("alliage_zorg_b", 3.0),
		materiaux, [], {"chantier_zorg": true, "travail_restant": 9.0}
	)
	verif.v(composite.get("chantier_zorg", false) == true, "patron_composite doit se retrouver TEL QUEL sur le composite")
	verif.v(is_equal_approx(float(composite.travail_restant), 9.0), "patron_composite doit pouvoir ajouter n'importe quelle cle, ici un chantier a reprendre")
	verif.v(composite.composition.size() == 2, "patron_composite ne doit jamais toucher a la composition derivee")

# ---- refus structurels ----

func _composition_absente_sur_a_refuse_sans_rien_produire() -> void:
	var materiaux := _materiaux_zorg()
	var composite := Soudure.fabriquer_composite({}, _proprietes_zorg("alliage_zorg_b", 3.0), materiaux)
	verif.v(composite.is_empty(), "proprietes_a sans 'composition' doit refuser la fusion (Dictionary vide)")

func _composition_absente_sur_b_refuse_sans_rien_produire() -> void:
	var materiaux := _materiaux_zorg()
	var composite := Soudure.fabriquer_composite(_proprietes_zorg("alliage_zorg_a", 2.0), {}, materiaux)
	verif.v(composite.is_empty(), "proprietes_b sans 'composition' doit refuser la fusion (Dictionary vide)")

func _materiau_absent_du_catalogue_refuse() -> void:
	var materiaux := _materiaux_zorg()
	var composite := Soudure.fabriquer_composite(_proprietes_zorg("alliage_zorg_a", 2.0), _proprietes_zorg("materiau_inexistant_zorg", 1.0), materiaux)
	verif.v(composite.is_empty(), "un materiau absent du catalogue doit refuser toute la fusion, meme severite qu'Objet.fabriquer")

	var composite_sans_densite := Soudure.fabriquer_composite(_proprietes_zorg("alliage_zorg_a", 2.0), _proprietes_zorg("sans_densite_zorg", 1.0), materiaux)
	verif.v(composite_sans_densite.is_empty(), "une fiche materiau sans 'densite' doit refuser toute la fusion")

func _meme_id_refuse_sans_rien_muter() -> void:
	var materiaux := _materiaux_zorg()
	var a := _chose_zorg("meme_id_zorg", "alliage_zorg_a", 2.0)
	var b := _chose_zorg("meme_id_zorg", "alliage_zorg_b", 3.0)
	var proprietes_a_avant: Dictionary = a.proprietes.duplicate(true)
	var proprietes_b_avant: Dictionary = b.proprietes.duplicate(true)

	var ok := Soudure.souder(a, b, materiaux)
	verif.v(not ok, "deux choses portant le MEME id ne doivent jamais se souder, recu ok=true")
	verif.v(a.proprietes == proprietes_a_avant, "un refus par meme id ne doit RIEN muter sur le premier objet")
	verif.v(b.proprietes == proprietes_b_avant, "un refus par meme id ne doit RIEN muter sur le second objet")

func _resumabilite_json_stricte() -> void:
	var materiaux := _materiaux_zorg()
	var composite := Soudure.fabriquer_composite(_proprietes_zorg("alliage_zorg_a", 2.0), _proprietes_zorg("alliage_zorg_b", 3.0), materiaux)
	var serialise := JSON.stringify(composite)
	var relu: Variant = JSON.parse_string(serialise)
	verif.v(relu is Dictionary, "le composite doit rester serialisable en JSON pur (Dictionary apres aller-retour)")
	verif.v(is_equal_approx(float(relu.masse), float(composite.masse)), "la masse doit survivre a l'aller-retour JSON sans perte")
