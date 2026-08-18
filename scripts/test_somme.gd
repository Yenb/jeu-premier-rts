extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_somme.gd
#
# Verrouille scripts/somme.gd -- lecture PURE, HORS DOMAINE PAR
# CONSTRUCTION : des SILOS ORBITAUX qui stockent du "plasma_zorg" et
# portent une "masse_zorg". Aucun de ces noms n'existe dans data/, aucun
# fichier n'est lu sur disque. Le geste extrait vient pourtant de quatre
# bancs de TERRAIN (eau, sol) : la preuve de genericite est qu'il
# traverse le meme code sur des silos.

const Somme = preload("res://scripts/somme.gd")
const Verif = preload("res://scripts/verif.gd")

func _init() -> void:
	var v := Verif.new()
	_reserves_somme_toutes_les_entites(v)
	_reserves_sur_liste_vide_rend_zero(v)
	_reserves_ignore_une_entite_sans_la_reserve_nommee(v)
	_propriete_somme_toutes_les_entites(v)
	_propriete_sur_liste_vide_rend_zero(v)
	_propriete_ignore_une_cle_absente(v)
	_element_mal_forme_est_ignore_sans_planter(v)
	_valeur_non_numerique_alarme_et_contribue_zero(v)
	_ne_mute_jamais_les_entites(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: somme.gd -- reserves() et propriete() somment exactement sur N entites, rendent 0.0 sur " +
			"une liste vide, ignorent sans alarme une entite qui ne porte pas la grandeur demandee, ignorent " +
			"sans planter un element mal forme, alarment sur une valeur non numerique en la comptant 0.0 " +
			"sans arreter la somme, et ne mutent jamais les entites")
		quit(0)

func _silo(id: String, reserve_plasma, masse) -> Dictionary:
	var proprietes: Dictionary = {}
	if reserve_plasma != null:
		proprietes["reserves"] = {"plasma_zorg": {"reserve": reserve_plasma, "capacite": 100.0}}
	if masse != null:
		proprietes["masse_zorg"] = masse
	return {"id": id, "position": Vector3.ZERO, "proprietes": proprietes}

func _reserves_somme_toutes_les_entites(v) -> void:
	var silos := [_silo("s1", 12.5, null), _silo("s2", 7.5, null), _silo("s3", 30.0, null)]
	v.v(is_equal_approx(Somme.reserves(silos, "plasma_zorg"), 50.0),
		"reserves() doit sommer la reserve de CHAQUE entite (12.5 + 7.5 + 30.0 = 50.0)")

func _reserves_sur_liste_vide_rend_zero(v) -> void:
	v.v(is_equal_approx(Somme.reserves([], "plasma_zorg"), 0.0),
		"reserves() sur un Array vide doit rendre 0.0, jamais une alarme")

func _reserves_ignore_une_entite_sans_la_reserve_nommee(v) -> void:
	var silos := [
		_silo("s1", 10.0, null),
		_silo("s2", null, 4.0),                                              # aucune table "reserves"
		{"id": "s3", "position": Vector3.ZERO, "proprietes": {"reserves": {}}},  # table vide
		{"id": "s4", "position": Vector3.ZERO,
			"proprietes": {"reserves": {"gaz_zorg": {"reserve": 999.0}}}},   # une AUTRE reserve
		{"id": "s5", "position": Vector3.ZERO,
			"proprietes": {"reserves": {"plasma_zorg": {"capacite": 50.0}}}},# canal sans la cle "reserve"
	]
	v.v(is_equal_approx(Somme.reserves(silos, "plasma_zorg"), 10.0),
		"reserves() doit ignorer sans alarme toute entite qui ne porte pas la reserve nommee (table absente, " +
		"table vide, autre reserve, canal sans cle 'reserve') et ne compter que les 10.0 reels")

func _propriete_somme_toutes_les_entites(v) -> void:
	var silos := [_silo("s1", null, 2.0), _silo("s2", null, 3.5), _silo("s3", null, 4)]
	v.v(is_equal_approx(Somme.propriete(silos, "masse_zorg"), 9.5),
		"propriete() doit sommer la propriete plate de CHAQUE entite, int comme float (2.0 + 3.5 + 4 = 9.5)")

func _propriete_sur_liste_vide_rend_zero(v) -> void:
	v.v(is_equal_approx(Somme.propriete([], "masse_zorg"), 0.0),
		"propriete() sur un Array vide doit rendre 0.0, jamais une alarme")

func _propriete_ignore_une_cle_absente(v) -> void:
	var silos := [_silo("s1", null, 6.0), _silo("s2", 100.0, null), _silo("s3", null, 1.0)]
	v.v(is_equal_approx(Somme.propriete(silos, "masse_zorg"), 7.0),
		"propriete() doit ignorer sans alarme une entite qui ne porte pas la cle demandee (6.0 + 1.0 = 7.0)")

func _element_mal_forme_est_ignore_sans_planter(v) -> void:
	var silos := [
		_silo("s1", 5.0, 5.0),
		"pas un dictionnaire",
		{"id": "sans_proprietes", "position": Vector3.ZERO},
		{"id": "proprietes_du_mauvais_type", "proprietes": "texte"},
	]
	v.v(is_equal_approx(Somme.reserves(silos, "plasma_zorg"), 5.0),
		"reserves() doit ignorer sans planter un element mal forme (non Dictionary, sans 'proprietes', " +
		"'proprietes' du mauvais type) et sommer les autres")
	v.v(is_equal_approx(Somme.propriete(silos, "masse_zorg"), 5.0),
		"propriete() doit ignorer sans planter un element mal forme et sommer les autres")

func _valeur_non_numerique_alarme_et_contribue_zero(v) -> void:
	var silos_reserve := [
		{"id": "corrompu", "position": Vector3.ZERO,
			"proprietes": {"reserves": {"plasma_zorg": {"reserve": "beaucoup"}}}},
		_silo("sain", 8.0, null),
	]
	v.v(is_equal_approx(Somme.reserves(silos_reserve, "plasma_zorg"), 8.0),
		"reserves() : une reserve non numerique doit alarmer et contribuer 0.0 sans empecher les AUTRES " +
		"entites de contribuer (8.0)")
	var silos_propriete := [_silo("corrompu", null, true), _silo("sain", null, 3.0)]
	v.v(is_equal_approx(Somme.propriete(silos_propriete, "masse_zorg"), 3.0),
		"propriete() : une valeur non numerique (bool) doit alarmer et contribuer 0.0 sans empecher les " +
		"AUTRES entites de contribuer (3.0)")

func _ne_mute_jamais_les_entites(v) -> void:
	var silos := [_silo("s1", 12.5, 2.0), _silo("s2", 7.5, 3.0)]
	var avant := JSON.stringify(silos)
	Somme.reserves(silos, "plasma_zorg")
	Somme.reserves(silos, "absente_zorg")
	Somme.propriete(silos, "masse_zorg")
	Somme.propriete(silos, "absente_zorg")
	v.v(avant == JSON.stringify(silos),
		"reserves() et propriete() ne doivent jamais muter les entites -- lecture PURE, y compris sur une " +
		"grandeur absente (aucune cle creee par un .get() a defaut)")
