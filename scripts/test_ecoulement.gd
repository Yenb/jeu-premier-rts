extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_ecoulement.gd
#
# Verrouille scripts/ecoulement.gd comme TRANSFERT CONSERVE PAIR-A-PAIRE,
# jamais comme un code d'eau/terrain. Noms de reserve/propriete fictifs
# ("grandeur_ecoulee"/"grandeur_verticale"), sans aucun rapport avec l'eau
# ou l'altitude -- meme discipline hors domaine que test_velocite.gd/
# test_consommer.gd.

const Ecoulement = preload("res://scripts/ecoulement.gd")
const Verif = preload("res://scripts/verif.gd")

const RESERVE := "grandeur_ecoulee"
const ALTITUDE := "grandeur_verticale"

func _init() -> void:
	var v := Verif.new()
	_la_case_haute_transfere_vers_la_case_basse(v)
	_une_case_basse_ne_transfere_jamais_vers_le_haut_meme_avec_de_la_reserve(v)
	_le_transfert_est_conserve_sur_toutes_les_cases(v)
	_une_case_sans_reserve_ne_transfere_rien(v)
	_deux_cases_a_hauteur_effective_egale_ne_echangent_rien(v)
	_le_taux_module_la_vitesse_d_ecoulement(v)
	_un_delta_tres_petit_transfere_peu(v)
	_la_quantite_transferee_est_bornee_a_la_reserve_source(v)
	_le_retour_liste_les_transferts_effectues(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: ecoulement.gd transfere une reserve de la case la plus haute vers la " +
			"plus basse (altitude + reserve), jamais en sens inverse, borne a ce que la " +
			"source possede, conserve la somme totale, aucun nom de propriete de domaine")
		quit(0)

func _case(id: String, position: Vector3, altitude: float, reserve: float) -> Dictionary:
	return {
		"id": id,
		"position": position,
		"proprietes": {
			ALTITUDE: altitude,
			"reserves": {RESERVE: {"reserve": reserve}},
		},
	}

func _reserve_de(case: Dictionary) -> float:
	return case.proprietes.reserves[RESERVE].reserve

func _la_case_haute_transfere_vers_la_case_basse(v) -> void:
	var haute := _case("haute", Vector3(0.0, 0.0, 0.0), 10.0, 5.0)
	var basse := _case("basse", Vector3(1.0, 0.0, 0.0), 0.0, 0.0)
	Ecoulement.avancer([haute, basse], 2.0, RESERVE, ALTITUDE, 1.0, 1.0)
	v.v(_reserve_de(basse) > 0.0, "la case basse doit recevoir une reserve strictement positive")
	v.v(_reserve_de(haute) < 5.0, "la case haute doit perdre une partie de sa reserve")
	v.v(is_equal_approx(_reserve_de(haute) + _reserve_de(basse), 5.0),
		"la somme des deux reserves doit rester exactement 5.0 (conservation)")

func _une_case_basse_ne_transfere_jamais_vers_le_haut_meme_avec_de_la_reserve(v) -> void:
	# "vallee" porte une reserve mais son altitude est basse (hauteur effective
	# 8.0, sous "sommet" a 10.0) -- "sommet" n'a AUCUNE reserve a donner. Si le
	# sens du transfert etait inverse, "vallee" enverrait vers "sommet" parce
	# que "sommet" est vide -- ca ne doit JAMAIS arriver : seule la hauteur
	# effective decide, jamais le manque du voisin.
	var vallee := _case("vallee", Vector3(0.0, 0.0, 0.0), 0.0, 8.0)
	var sommet := _case("sommet", Vector3(1.0, 0.0, 0.0), 10.0, 0.0)
	Ecoulement.avancer([vallee, sommet], 2.0, RESERVE, ALTITUDE, 1.0, 1.0)
	v.v(is_equal_approx(_reserve_de(vallee), 8.0),
		"une case a hauteur effective plus basse ne doit jamais perdre sa reserve vers un voisin plus haut")
	v.v(is_equal_approx(_reserve_de(sommet), 0.0),
		"une case plus haute mais vide ne doit jamais recevoir une reserve venue d'en bas")

func _le_transfert_est_conserve_sur_toutes_les_cases(v) -> void:
	var a := _case("a", Vector3(0.0, 0.0, 0.0), 20.0, 6.0)
	var b := _case("b", Vector3(1.0, 0.0, 0.0), 10.0, 2.0)
	var c := _case("c", Vector3(2.0, 0.0, 0.0), 0.0, 0.0)
	var cases: Array = [a, b, c]
	var total_avant := _reserve_de(a) + _reserve_de(b) + _reserve_de(c)
	for _i in range(20):
		Ecoulement.avancer(cases, 1.5, RESERVE, ALTITUDE, 0.5, 0.1)
	var total_apres := _reserve_de(a) + _reserve_de(b) + _reserve_de(c)
	v.v(is_equal_approx(total_avant, total_apres),
		"la somme des reserves sur toutes les cases doit rester constante, aucune absorption/evaporation ici")

func _une_case_sans_reserve_ne_transfere_rien(v) -> void:
	var haute := _case("haute", Vector3(0.0, 0.0, 0.0), 10.0, 0.0)
	var basse := _case("basse", Vector3(1.0, 0.0, 0.0), 0.0, 0.0)
	Ecoulement.avancer([haute, basse], 2.0, RESERVE, ALTITUDE, 1.0, 1.0)
	v.v(is_equal_approx(_reserve_de(basse), 0.0),
		"une case source sans reserve (0.0) ne doit jamais transferer quoi que ce soit, meme plus haute")

func _deux_cases_a_hauteur_effective_egale_ne_echangent_rien(v) -> void:
	var a := _case("a", Vector3(0.0, 0.0, 0.0), 5.0, 0.0)
	var b := _case("b", Vector3(1.0, 0.0, 0.0), 0.0, 5.0)
	Ecoulement.avancer([a, b], 2.0, RESERVE, ALTITUDE, 1.0, 1.0)
	v.v(is_equal_approx(_reserve_de(a), 0.0) and is_equal_approx(_reserve_de(b), 5.0),
		"deux cases a hauteur effective strictement egale (5.0 des deux cotes) ne doivent jamais s'echanger de reserve")

func _le_taux_module_la_vitesse_d_ecoulement(v) -> void:
	# delta petit (0.01) : le premier transfert reste tres sous la reserve
	# des deux cotes (quantite << reserve), pour ne jamais franchir le point
	# d'equilibre et declencher un aller-retour dans le MEME appel (la paire
	# ordonnee (basse, haute) est aussi visitee par avancer -- voir en-tete
	# de ecoulement.gd, "SEQUENCE").
	var haute_lent := _case("haute_lent", Vector3(0.0, 0.0, 0.0), 10.0, 100.0)
	var basse_lent := _case("basse_lent", Vector3(1.0, 0.0, 0.0), 0.0, 0.0)
	Ecoulement.avancer([haute_lent, basse_lent], 2.0, RESERVE, ALTITUDE, 0.1, 0.01)

	var haute_rapide := _case("haute_rapide", Vector3(0.0, 0.0, 0.0), 10.0, 100.0)
	var basse_rapide := _case("basse_rapide", Vector3(1.0, 0.0, 0.0), 0.0, 0.0)
	Ecoulement.avancer([haute_rapide, basse_rapide], 2.0, RESERVE, ALTITUDE, 1.0, 0.01)

	v.v(_reserve_de(basse_rapide) > _reserve_de(basse_lent),
		"un taux plus grand doit transferer une quantite strictement plus grande sur le meme pas")

func _un_delta_tres_petit_transfere_peu(v) -> void:
	var haute := _case("haute", Vector3(0.0, 0.0, 0.0), 10.0, 100.0)
	var basse := _case("basse", Vector3(1.0, 0.0, 0.0), 0.0, 0.0)
	Ecoulement.avancer([haute, basse], 2.0, RESERVE, ALTITUDE, 1.0, 0.001)
	v.v(_reserve_de(basse) > 0.0, "un delta tres petit doit quand meme transferer une quantite strictement positive")
	v.v(_reserve_de(basse) < 1.0, "un delta tres petit doit transferer une quantite tres petite, jamais un pas entier")

func _la_quantite_transferee_est_bornee_a_la_reserve_source(v) -> void:
	var haute := _case("haute", Vector3(0.0, 0.0, 0.0), 10.0, 3.0)
	var basse := _case("basse", Vector3(1.0, 0.0, 0.0), 0.0, 0.0)
	Ecoulement.avancer([haute, basse], 2.0, RESERVE, ALTITUDE, 10.0, 1.0)
	v.v(_reserve_de(haute) >= 0.0, "la reserve source ne doit jamais descendre sous zero")
	v.v(is_equal_approx(_reserve_de(haute), 0.0), "une demande superieure au restant doit borner exactement a zero")
	v.v(is_equal_approx(_reserve_de(basse), 3.0), "le receveur doit gagner exactement ce que la source avait, jamais plus")

func _le_retour_liste_les_transferts_effectues(v) -> void:
	var haute := _case("haute", Vector3(0.0, 0.0, 0.0), 10.0, 5.0)
	var basse := _case("basse", Vector3(1.0, 0.0, 0.0), 0.0, 0.0)
	var transferts: Array = Ecoulement.avancer([haute, basse], 2.0, RESERVE, ALTITUDE, 1.0, 1.0)
	v.v(transferts.size() == 1, "un seul transfert doit etre rapporte pour une paire haute/basse a portee")
	v.v(transferts[0].source_id == "haute" and transferts[0].receveur_id == "basse",
		"le transfert rapporte doit nommer la case source et la case receveuse")
	v.v(transferts[0].quantite > 0.0, "la quantite rapportee doit etre strictement positive")
