extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_reaction.gd
#
# Verrouille scripts/reaction.gd comme MECANISME GENERIQUE DE DETECTION DE
# PAIRES REACTIVES + CHAINAGE PAR PROFONDEUR -- catalogue et materiaux
# entierement fictifs, hors domaine de bout en bout (aucun rapport avec
# acide_demo/fer/eau_demo/sel_metallique, verrouilles ailleurs par
# scripts/test_banc_reactivite.gd et un futur test_banc_chaine_reactions.gd).

const Reaction = preload("res://scripts/reaction.gd")
const Verif = preload("res://scripts/verif.gd")

# zorg_a + zorg_b -> zorg_c (zorg_a reste zorg_a, seul zorg_b se transforme).
# zorg_d + zorg_c -> zorg_e (deuxieme etage de la chaine, profondeur 1 -> 2).
const CATALOGUE := [
	{"materiau_a": "zorg_a", "materiau_b": "zorg_b", "seuil_reactivite": 1.0, "type_produit": "zorg_c", "rendement": 1.0, "portee_reaction": 10.0},
	{"materiau_a": "zorg_d", "materiau_b": "zorg_c", "seuil_reactivite": 1.0, "type_produit": "zorg_e", "rendement": 1.0, "portee_reaction": 10.0},
]

const MATERIAUX := {
	"zorg_a": {"densite": 1.0},
	"zorg_b": {"densite": 1.0},
	"zorg_c": {"densite": 1.0, "reactivite": 1.0},
	"zorg_d": {"densite": 1.0},
	"zorg_e": {"densite": 1.0},
	"zorg_x": {"densite": 1.0},
	"zorg_y": {"densite": 1.0},
}

const TABLE := {
	"zorg_c": {"composition": [{"materiau": "zorg_c", "volume": 1.0}]},
	"zorg_e": {"composition": [{"materiau": "zorg_e", "volume": 1.0}]},
}

func _init() -> void:
	var v := Verif.new()
	_deux_reactifs_a_portee_reagissent_et_produisent(v)
	_deux_reactifs_hors_portee_ne_reagissent_pas(v)
	_le_produit_reagit_au_tick_suivant_avec_un_troisieme_objet(v)
	_un_produit_a_profondeur_max_ne_reagit_plus(v)
	_deux_objets_non_reactifs_ne_reagissent_jamais(v)
	_profondeur_chaine_max_zero_empeche_toute_reaction(v)
	_profondeur_chaine_max_un_permet_premiere_reaction_mais_pas_la_cascade(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: reaction.gd detecte les paires a portee, produit au seuil, chaine par le temps (jamais dans un seul appel), profondeur_chaine_max borne la cascade")
		quit(0)

func _chose(id: String, position: Vector3, materiau: String, reactivite: float, profondeur: int = 0) -> Dictionary:
	var proprietes: Dictionary = {
		"composition": [{"materiau": materiau, "volume": 1.0}],
		"masse": 10.0,
		"reactivite": reactivite,
	}
	if profondeur > 0:
		proprietes["_profondeur_chaine"] = profondeur
	return {"id": id, "position": position, "proprietes": proprietes}

func _materiau_de(objet: Dictionary) -> String:
	return String(objet.proprietes.composition[0].materiau)

# Fait avancer detecter_et_reagir jusqu'a N appels ou jusqu'a la premiere
# transformation retournee -- evite de calculer a la main le nombre exact
# de pas necessaires pour franchir un seuil (detail interne de charge.gd).
func _avancer_jusqua_transformation(monde: Array, profondeur_max: int, n_max: int, delta: float) -> Array:
	for i in range(n_max):
		var resultat := Reaction.detecter_et_reagir(monde, CATALOGUE, delta, profondeur_max, TABLE, MATERIAUX)
		if not resultat.is_empty():
			return resultat
	return []

func _deux_reactifs_a_portee_reagissent_et_produisent(v) -> void:
	var a := _chose("a", Vector3(0, 0, 0), "zorg_a", 1.0)
	var b := _chose("b", Vector3(1, 0, 0), "zorg_b", 1.0)
	var monde: Array = [a, b]
	var resultat := _avancer_jusqua_transformation(monde, 4, 20, 0.3)
	v.v(not resultat.is_empty(), "deux reactifs a portee avec score >= seuil doivent finir par produire")
	v.v(_materiau_de(b) == "zorg_c", "la cible (materiau_b) doit devenir exactement le type_produit de l'entree")
	v.v(_materiau_de(a) == "zorg_a", "la source (materiau_a) ne doit JAMAIS etre transformee -- modele asymetrique")
	v.v(int(b.proprietes.get("_profondeur_chaine", -1)) == 1, "un produit issu d'objets de base (profondeur 0) doit porter _profondeur_chaine=1")

func _deux_reactifs_hors_portee_ne_reagissent_pas(v) -> void:
	var a := _chose("a", Vector3(0, 0, 0), "zorg_a", 1.0)
	var b := _chose("b", Vector3(1000, 0, 0), "zorg_b", 1.0)
	var monde: Array = [a, b]
	var resultat := _avancer_jusqua_transformation(monde, 4, 20, 0.3)
	v.v(resultat.is_empty(), "hors de la portee_reaction de l'entree, aucune reaction ne doit jamais se produire")
	v.v(_materiau_de(b) == "zorg_b", "hors portee, la cible ne doit jamais changer de materiau")

func _le_produit_reagit_au_tick_suivant_avec_un_troisieme_objet(v) -> void:
	var a := _chose("a", Vector3(0, 0, 0), "zorg_a", 1.0)
	var b := _chose("b", Vector3(1, 0, 0), "zorg_b", 1.0)
	var d := _chose("d", Vector3(1, 1, 0), "zorg_d", 1.0)
	var monde: Array = [a, b, d]

	var resultat_etape_1 := _avancer_jusqua_transformation(monde, 4, 20, 0.3)
	v.v(not resultat_etape_1.is_empty() and _materiau_de(b) == "zorg_c",
		"premiere etape : a+b doit produire c avant qu'on cherche la cascade")
	v.v(resultat_etape_1[0].id == "b" and resultat_etape_1.size() == 1,
		"UN SEUL objet (b) doit se transformer ce pas -- jamais une cascade en un seul appel (d+c inexistant tant que b est encore b au debut de cet appel)")

	var resultat_etape_2 := _avancer_jusqua_transformation(monde, 4, 20, 0.3)
	v.v(not resultat_etape_2.is_empty(), "b devenu c doit finir par reagir avec d, a un TICK ULTERIEUR")
	v.v(_materiau_de(b) == "zorg_e", "le produit de la cascade doit etre exactement zorg_e (entree materiau_d+materiau_c)")
	v.v(int(b.proprietes.get("_profondeur_chaine", -1)) == 2,
		"profondeur_chaine du produit de cascade = max(profondeur de d=0, profondeur de c=1) + 1 = 2")

func _un_produit_a_profondeur_max_ne_reagit_plus(v) -> void:
	var a := _chose("a", Vector3(0, 0, 0), "zorg_a", 1.0)
	var c_deja_a_profondeur_1 := _chose("c", Vector3(1, 0, 0), "zorg_c", 1.0, 1)
	var d := _chose("d", Vector3(1, 1, 0), "zorg_d", 1.0)
	var monde: Array = [a, c_deja_a_profondeur_1, d]
	# profondeur_max=1 : c est deja a profondeur 1 >= 1, exclu de toute detection.
	var resultat := _avancer_jusqua_transformation(monde, 1, 20, 0.3)
	v.v(resultat.is_empty(), "un objet dont _profondeur_chaine >= profondeur_max ne doit plus jamais reagir, ni comme source ni comme cible")
	v.v(_materiau_de(c_deja_a_profondeur_1) == "zorg_c", "l'objet a profondeur maximale ne doit jamais changer de materiau")

func _deux_objets_non_reactifs_ne_reagissent_jamais(v) -> void:
	var x := _chose("x", Vector3(0, 0, 0), "zorg_x", 1.0)
	var y := _chose("y", Vector3(1, 0, 0), "zorg_y", 1.0)
	var monde: Array = [x, y]
	var resultat := _avancer_jusqua_transformation(monde, 4, 20, 0.3)
	v.v(resultat.is_empty(), "une paire sans entree dans le catalogue ne doit jamais reagir, quelle que soit la distance")
	v.v(not x.proprietes.has("etats"), "aucun canal 'reaction' ne doit meme etre cree pour une paire sans entree correspondante")

func _profondeur_chaine_max_zero_empeche_toute_reaction(v) -> void:
	var a := _chose("a", Vector3(0, 0, 0), "zorg_a", 1.0)
	var b := _chose("b", Vector3(1, 0, 0), "zorg_b", 1.0)
	var monde: Array = [a, b]
	var resultat := _avancer_jusqua_transformation(monde, 0, 20, 0.3)
	v.v(resultat.is_empty(), "profondeur_chaine_max=0 exclut tout objet de base (profondeur 0 >= 0) : aucune reaction, jamais")
	v.v(_materiau_de(b) == "zorg_b", "profondeur_chaine_max=0 : la cible ne doit jamais changer de materiau")

func _profondeur_chaine_max_un_permet_premiere_reaction_mais_pas_la_cascade(v) -> void:
	var a := _chose("a", Vector3(0, 0, 0), "zorg_a", 1.0)
	var b := _chose("b", Vector3(1, 0, 0), "zorg_b", 1.0)
	var d := _chose("d", Vector3(1, 1, 0), "zorg_d", 1.0)
	var monde: Array = [a, b, d]

	var resultat_etape_1 := _avancer_jusqua_transformation(monde, 1, 20, 0.3)
	v.v(not resultat_etape_1.is_empty() and _materiau_de(b) == "zorg_c",
		"profondeur_chaine_max=1 : la PREMIERE reaction (objets de base, profondeur 0 < 1) doit avoir lieu")

	var resultat_etape_2 := _avancer_jusqua_transformation(monde, 1, 20, 0.3)
	v.v(resultat_etape_2.is_empty(),
		"profondeur_chaine_max=1 : c est desormais a profondeur 1 >= 1, la cascade vers zorg_e ne doit jamais avoir lieu")
	v.v(_materiau_de(b) == "zorg_c", "sans cascade autorisee, le produit de la premiere etape doit rester zorg_c")
