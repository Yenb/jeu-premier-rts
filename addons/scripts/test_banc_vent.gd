extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_vent.gd
#
# Verrouille le cablage de banc_vent.gd, PREMIERE DEMONSTRATION REELLE du
# chantier "vent" sur l'odorat : positions_en_cercle/fabriquer_nez/ids_captes/
# couleur_pour_capture/changements_de_capture/texte_vent (fonctions statiques,
# pures) plus un CHEMIN REEL combinant Perception.percevoir avec
# data/vent.json/data/canaux.json lus sur disque -- le cercle de sources
# capturees doit reellement pivoter quand le vent reel tourne.

const BancVent = preload("res://scripts/banc_vent.gd")
const Perception = preload("res://scripts/perception.gd")
const Monde = preload("res://scripts/monde.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

func _init() -> void:
	_positions_en_cercle_espacees_egalement()
	_positions_en_cercle_rend_vide_sans_source()
	_fabriquer_nez_porte_le_seul_canal_odorat()
	_ids_captes_extrait_les_ids_des_perceptions()
	_couleur_pour_capture_distingue_les_deux_etats()
	_changements_de_capture_ne_rend_que_ce_qui_a_change()
	_texte_vent_porte_direction_force_et_les_deux_portees()
	_chemin_reel_le_cercle_de_sources_pivote_avec_le_vent()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: positions en cercle egalement espacees, fabrication du nez, " +
		"extraction des ids captes, couleur par capture, detection des " +
		"changements, texte du vent, chemin reel (data/vent.json/canaux.json) " +
		"ou le cercle de sources capturees pivote avec le vent reel")
	quit(0)

func _positions_en_cercle_espacees_egalement() -> void:
	var positions := BancVent.positions_en_cercle(Vector3.ZERO, 100.0, 4)
	verif.v(positions.size() == 4, "4 sources demandees doivent rendre 4 positions")
	for p in positions:
		verif.v(is_equal_approx(Vector3.ZERO.distance_to(p), 100.0), "chaque position doit etre exactement a distance 100.0 du centre")
	verif.v(is_equal_approx(positions[0].normalized().dot(positions[1].normalized()), 0.0),
		"deux sources consecutives sur un cercle de 4 doivent etre exactement perpendiculaires")
	verif.v(positions[0].normalized().dot(positions[2].normalized()) < -0.99,
		"les positions opposees (index 0 et 2 sur un cercle de 4) doivent pointer dans des sens opposes")

func _positions_en_cercle_rend_vide_sans_source() -> void:
	verif.v(BancVent.positions_en_cercle(Vector3.ZERO, 100.0, 0).is_empty(),
		"zero source demandee doit rendre un Array vide, jamais une erreur")

func _fabriquer_nez_porte_le_seul_canal_odorat() -> void:
	var nez := BancVent.fabriquer_nez(Vector3(1.0, 2.0, 0.0), 250.0)
	verif.v(nez.proprietes.canaux == ["odorat"], "le nez ne doit porter QUE le canal odorat, aucun autre")
	verif.v(nez.proprietes.canaux_config.odorat.portee == 250.0, "la portee d'odorat doit venir du parametre, jamais une valeur en dur")
	verif.v(nez.position == Vector3(1.0, 2.0, 0.0), "la position doit etre celle recue en parametre")

func _ids_captes_extrait_les_ids_des_perceptions() -> void:
	var perceptions := [
		{"chose": {"id": "a"}},
		{"chose": {"id": "b"}},
	]
	verif.v(BancVent.ids_captes(perceptions) == ["a", "b"], "doit rendre exactement les ids, dans l'ordre des perceptions")
	verif.v(BancVent.ids_captes([]).is_empty(), "aucune perception ne doit rendre un Array vide")

func _couleur_pour_capture_distingue_les_deux_etats() -> void:
	var vif := Color(1.0, 0.0, 0.0)
	var terne := Color(0.2, 0.2, 0.2)
	verif.v(BancVent.couleur_pour_capture(true, vif, terne) == vif, "captee doit rendre la couleur 'captee'")
	verif.v(BancVent.couleur_pour_capture(false, vif, terne) == terne, "non captee doit rendre la couleur 'non captee'")

func _changements_de_capture_ne_rend_que_ce_qui_a_change() -> void:
	var precedent := {"a": false, "b": true, "c": false}
	var courant := {"a": true, "b": true, "c": false}
	var changements := BancVent.changements_de_capture(precedent, courant)
	verif.v(changements.size() == 1, "un seul id a change ('a'), 'b' et 'c' sont restes identiques -- recu %d changement(s)" % changements.size())
	if changements.size() == 1:
		verif.v(changements[0].id == "a" and changements[0].captee == true, "le seul changement doit porter 'a' passe a capte")

func _texte_vent_porte_direction_force_et_les_deux_portees() -> void:
	var texte := BancVent.texte_vent(Vector3(1.0, 0.0, 0.0), 300.0, 100.0)
	verif.v(texte.find("300.0") != -1, "le texte doit porter la portee aval")
	verif.v(texte.find("100.0") != -1, "le texte doit porter la portee amont")
	var texte_nul := BancVent.texte_vent(Vector3.ZERO, 250.0, 250.0)
	verif.v(texte_nul.find("0.00") != -1, "un vent nul doit afficher une force exactement nulle, jamais une valeur devinee")

func _catalogue_canaux_reel() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/canaux.json"))

func _catalogue_vent_reel() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/vent.json"))

# CHEMIN REEL : le cercle de huit sources, la vraie donnee data/vent.json,
# tourne reellement -- l'ensemble des ids captes a t=0 ne doit pas etre
# l'ensemble des ids captes a un quart de la periode de rotation reelle
# (variation_lente.periode_angle), sans jamais supposer LEQUEL des huit est
# capte a quel instant precis.
func _chemin_reel_le_cercle_de_sources_pivote_avec_le_vent() -> void:
	var catalogue_canaux := _catalogue_canaux_reel()
	var catalogue_vent := _catalogue_vent_reel()
	var nez := BancVent.fabriquer_nez(Vector3.ZERO, 250.0)
	var positions := BancVent.positions_en_cercle(Vector3.ZERO, 330.0, 8)

	var monde := Monde.new()
	monde.ajouter(nez, "nez", nez.position)
	for i in positions.size():
		var source := {"id": "odeur_%d" % i, "position": positions[i], "proprietes": {}}
		monde.ajouter(source, "odeur", source.position)

	var periode: float = catalogue_vent.defaut.get("variation_lente", {}).get("periode_angle", 0.0)
	verif.v(periode > 0.0, "data/vent.json doit declarer une periode_angle strictement positive pour que ce chemin reel ait un sens")

	var captes_t0 := BancVent.ids_captes(Perception.percevoir(nez, monde, catalogue_canaux, catalogue_vent, 0.0, []))
	var captes_plus_tard := BancVent.ids_captes(Perception.percevoir(nez, monde, catalogue_canaux, catalogue_vent, periode * 0.25, []))
	captes_t0.sort()
	captes_plus_tard.sort()

	verif.v(captes_t0 != captes_plus_tard,
		"l'ensemble des sources capturees a t=0 et a un quart de periode de rotation plus tard doit differer -- le vent doit reellement faire pivoter ce qui est senti (t0=%s, t+T/4=%s)" % [captes_t0, captes_plus_tard])
