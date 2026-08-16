extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_frappe.gd
#
# Verrouille scripts/frappe.gd -- calcul PUR, hors domaine par construction
# (materiaux/proprietes/reserve FICTIFS, "zorg", jamais lus sur disque ni
# vus ailleurs dans le depot). Chantier « foudre -- evenement ponctuel »,
# audit_foudre_prealable.md.

const Frappe = preload("res://scripts/frappe.gd")
const Verif = preload("res://scripts/verif.gd")

const MATERIAUX_FICTIFS := {
	"cristal_zorg": {"densite": 1.0, "resonance_zorg": 0.8},
	"mousse_zorg": {"densite": 1.0, "resonance_zorg": 0.1},
}

func _init() -> void:
	var v := Verif.new()
	_selectionne_le_score_le_plus_haut_parmi_les_objets_a_portee(v)
	_objet_hors_portee_jamais_candidat(v)
	_aucun_objet_a_portee_rend_dictionnaire_vide(v)
	_liste_d_objets_vide_rend_dictionnaire_vide(v)
	_egalite_stricte_garde_le_premier_trouve_dans_l_ordre_d_iteration(v)
	_source_de_critere_inconnue_ignoree_sans_bloquer_les_autres(v)
	_score_composite_somme_ponderee_les_deux_criteres(v)
	_frapper_soustrait_les_degats_bornee_a_zero(v)
	_frapper_reserve_absente_alarme_et_ne_mute_rien(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: frappe.gd -- selection au score composite le plus haut parmi les objets a portee, " +
			"egalite stricte garde le premier trouve, source de critere inconnue ignoree sans bloquer " +
			"les autres, degat instantane soustrait et borne a zero, reserve absente alarme sans muter")
		quit(0)

func _objet(id: String, position: Vector3, composition: Variant, reserves: Dictionary = {}) -> Dictionary:
	var proprietes: Dictionary = {}
	if composition != null:
		proprietes["composition"] = composition
	if not reserves.is_empty():
		proprietes["reserves"] = reserves
	return {"id": id, "position": position, "proprietes": proprietes}

func _selectionne_le_score_le_plus_haut_parmi_les_objets_a_portee(v) -> void:
	var a := _objet("a", Vector3(10.0, 0.0, 5.0), [{"materiau": "cristal_zorg", "volume": 1.0}])
	var b := _objet("b", Vector3(10.0, 0.0, 5.0), [{"materiau": "mousse_zorg", "volume": 1.0}])
	var criteres := [
		{"propriete": "resonance_zorg", "poids": 10.0, "source": "materiau"},
		{"poids": 1.0, "source": "position_z"},
	]
	# score_a = 0.8*10 + 5*1 = 13.0 ; score_b = 0.1*10 + 5*1 = 6.0 -- meme z, seul le materiau distingue
	var resultat := Frappe.selectionner([a, b], Vector3.ZERO, 50.0, criteres, MATERIAUX_FICTIFS)
	v.v(resultat.get("id", "") == "a", "doit selectionner l'objet au score composite le plus haut ('a', 13.0 > 6.0)")

func _objet_hors_portee_jamais_candidat(v) -> void:
	var a := _objet("a", Vector3(10.0, 0.0, 0.0), [{"materiau": "mousse_zorg", "volume": 1.0}])
	var c := _objet("c", Vector3(1000.0, 0.0, 0.0), [{"materiau": "cristal_zorg", "volume": 100.0}])
	var criteres := [{"propriete": "resonance_zorg", "poids": 10.0, "source": "materiau"}]
	# c aurait un score enorme (0.8*10*100=800) mais est hors du rayon -- jamais candidat
	var resultat := Frappe.selectionner([a, c], Vector3.ZERO, 20.0, criteres, MATERIAUX_FICTIFS)
	v.v(resultat.get("id", "") == "a", "un objet hors portee ne doit jamais etre candidat, meme a score enorme")

func _aucun_objet_a_portee_rend_dictionnaire_vide(v) -> void:
	var c := _objet("c", Vector3(1000.0, 0.0, 0.0), [{"materiau": "cristal_zorg", "volume": 1.0}])
	var criteres := [{"propriete": "resonance_zorg", "poids": 1.0, "source": "materiau"}]
	var resultat := Frappe.selectionner([c], Vector3.ZERO, 5.0, criteres, MATERIAUX_FICTIFS)
	v.v(resultat.is_empty(), "aucun objet a portee doit rendre un Dictionary vide, chemin mort")

func _liste_d_objets_vide_rend_dictionnaire_vide(v) -> void:
	var criteres := [{"propriete": "resonance_zorg", "poids": 1.0, "source": "materiau"}]
	var resultat := Frappe.selectionner([], Vector3.ZERO, 50.0, criteres, MATERIAUX_FICTIFS)
	v.v(resultat.is_empty(), "une liste d'objets vide doit rendre un Dictionary vide, chemin mort")

func _egalite_stricte_garde_le_premier_trouve_dans_l_ordre_d_iteration(v) -> void:
	var a := _objet("a", Vector3(5.0, 0.0, 0.0), [{"materiau": "cristal_zorg", "volume": 1.0}])
	var b := _objet("b", Vector3(5.0, 0.0, 0.0), [{"materiau": "cristal_zorg", "volume": 1.0}])
	var criteres := [{"propriete": "resonance_zorg", "poids": 10.0, "source": "materiau"}]
	var resultat_ab := Frappe.selectionner([a, b], Vector3.ZERO, 50.0, criteres, MATERIAUX_FICTIFS)
	v.v(resultat_ab.get("id", "") == "a", "egalite stricte : garde le premier trouve dans l'ordre d'iteration ('a' avant 'b')")
	var resultat_ba := Frappe.selectionner([b, a], Vector3.ZERO, 50.0, criteres, MATERIAUX_FICTIFS)
	v.v(resultat_ba.get("id", "") == "b", "egalite stricte : l'ordre d'ITERATION decide, pas un ordre fixe par id ('b' avant 'a' cette fois)")

func _source_de_critere_inconnue_ignoree_sans_bloquer_les_autres(v) -> void:
	var a := _objet("a", Vector3(0.0, 0.0, 1.0), null)
	var b := _objet("b", Vector3(0.0, 0.0, 5.0), null)
	var criteres := [
		{"propriete": "whatever", "poids": 1000.0, "source": "bogus"},
		{"poids": 1.0, "source": "position_z"},
	]
	# "bogus" contribue 0.0 pour les deux -- seul position_z distingue (5.0 > 1.0)
	var resultat := Frappe.selectionner([a, b], Vector3.ZERO, 50.0, criteres, MATERIAUX_FICTIFS)
	v.v(resultat.get("id", "") == "b", "une source de critere inconnue doit contribuer 0.0 sans bloquer les autres criteres")

func _score_composite_somme_ponderee_les_deux_criteres(v) -> void:
	var a := _objet("a", Vector3(0.0, 0.0, 1.0), [{"materiau": "cristal_zorg", "volume": 10.0}])
	var b := _objet("b", Vector3(0.0, 0.0, 100.0), [{"materiau": "mousse_zorg", "volume": 1.0}])
	# materiau dominant : score_a = 0.8*10*100=800 + 1*0.01=0.01 (800.01) ; score_b = 0.1*100=10 + 100*0.01=1 (11.0)
	var criteres_materiau_dominant := [
		{"propriete": "resonance_zorg", "poids": 100.0, "source": "materiau"},
		{"poids": 0.01, "source": "position_z"},
	]
	var resultat_materiau := Frappe.selectionner([a, b], Vector3.ZERO, 200.0, criteres_materiau_dominant, MATERIAUX_FICTIFS)
	v.v(resultat_materiau.get("id", "") == "a", "poids materiau dominant : 'a' doit gagner (800.01 > 11.0)")
	# hauteur dominante : score_a = 0.8*10*0.01=0.08 + 1*100=100 (100.08) ; score_b = 0.1*1*0.01=0.001 + 100*100=10000 (10000.001)
	var criteres_hauteur_dominante := [
		{"propriete": "resonance_zorg", "poids": 0.01, "source": "materiau"},
		{"poids": 100.0, "source": "position_z"},
	]
	var resultat_hauteur := Frappe.selectionner([a, b], Vector3.ZERO, 200.0, criteres_hauteur_dominante, MATERIAUX_FICTIFS)
	v.v(resultat_hauteur.get("id", "") == "b", "poids hauteur dominant : 'b' doit gagner (10000.001 > 100.08) -- preuve que les DEUX criteres pesent reellement dans la somme")

func _frapper_soustrait_les_degats_bornee_a_zero(v) -> void:
	var cible := _objet("cible", Vector3.ZERO, null, {"puissance_zorg": {"reserve": 10.0}})
	Frappe.frapper(cible, 4.0, "puissance_zorg")
	v.v(is_equal_approx(cible.proprietes.reserves.puissance_zorg.reserve, 6.0),
		"un degat instantane doit soustraire directement de la reserve (10.0 - 4.0 = 6.0)")
	Frappe.frapper(cible, 100.0, "puissance_zorg")
	v.v(is_equal_approx(cible.proprietes.reserves.puissance_zorg.reserve, 0.0),
		"la reserve doit rester bornee a zero, jamais negative, meme sous un degat enorme")

func _frapper_reserve_absente_alarme_et_ne_mute_rien(v) -> void:
	var cible := _objet("cible2", Vector3.ZERO, null, {"autre_zorg": {"reserve": 5.0}})
	var avant := JSON.stringify(cible.proprietes)
	Frappe.frapper(cible, 4.0, "puissance_zorg")
	var apres := JSON.stringify(cible.proprietes)
	v.v(avant == apres, "une reserve nommee absente doit alarmer (push_error) sans muter 'proprietes'")
