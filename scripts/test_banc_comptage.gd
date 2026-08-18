extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_comptage.gd
#
# Verrouille le cablage de banc_comptage.gd : PREMIER CABLAGE REEL de
# scripts/comptage.gd (ferme et prouve hors domaine par test_comptage.gd).
# Domaine hors colon/faction/ville, comme comptage.gd lui-meme : des
# lucioles ({ id, position, proprietes: { luit: bool } }) qui basculent au
# hasard sur un RNG seede.
#
# Fonction pure pour les deux fonctions statiques testees
# (_appliquer_bascules, _moyenne_glissante) : aucun noeud, aucun rendu,
# aucun disque pour ces deux-la. _comptage_reel_sur_la_liste_apres_bascule
# et _resumabilite_des_lucioles lisent data/comptages.json REEL, sur
# disque, comme le fait banc_comptage.gd -- chemin reel, pas une fixture
# locale.

const BancComptage = preload("res://scripts/banc_comptage.gd")
const Comptage = preload("res://scripts/comptage.gd")
const Verif = preload("res://scripts/verif.gd")

func _init() -> void:
	var v := Verif.new()
	_appliquer_bascules_est_deterministe_avec_rng_seede(v)
	_appliquer_bascules_bascule_la_luciole_qui_franchit_le_seuil(v)
	_comptage_reel_sur_la_liste_apres_bascule(v)
	_moyenne_glissante_lisse_le_compte(v)
	_resumabilite_des_lucioles(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: banc_comptage.gd cable comptage.gd en jeu -- bascules deterministes " +
			"sur RNG seede, comptage reel sur la liste, moyenne glissante, resumabilite JSON")
		quit(0)

func _luciole(id: String, proprietes: Dictionary) -> Dictionary:
	return {"id": id, "position": Vector3.ZERO, "proprietes": proprietes}

func _catalogue_comptages_reel() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/comptages.json"))

# "luit" est POSEE (proprietes["luit"] = true) ou RETIREE, jamais mise a
# false et laissee presente -- le mode "presente" de comptage.gd teste
# .has(propriete), jamais sa valeur (voir scripts/banc_comptage.gd, en-tete).
# Une luciole "eteinte" porte donc des proprietes VIDES ({}), jamais
# { "luit": false }.

func _appliquer_bascules_est_deterministe_avec_rng_seede(v) -> void:
	var seuil := 0.5
	var lucioles_a := [
		_luciole("a1", {}),
		_luciole("a2", {"luit": true}),
		_luciole("a3", {}),
	]
	var lucioles_b := [
		_luciole("a1", {}),
		_luciole("a2", {"luit": true}),
		_luciole("a3", {}),
	]
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 123
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 123

	var bascules_a := BancComptage._appliquer_bascules(lucioles_a, rng_a, seuil)
	var bascules_b := BancComptage._appliquer_bascules(lucioles_b, rng_b, seuil)

	v.v(bascules_a == bascules_b,
		"deux RNG seedes identiquement doivent produire exactement la meme sequence de bascules")
	for i in lucioles_a.size():
		v.v(lucioles_a[i].proprietes.has("luit") == lucioles_b[i].proprietes.has("luit"),
			"l'etat luit final doit etre identique pour un meme seed, aucun hasard non seede ne doit se glisser")

func _appliquer_bascules_bascule_la_luciole_qui_franchit_le_seuil(v) -> void:
	var seuil := 0.5
	var lucioles := [
		_luciole("l1", {}),
		_luciole("l2", {}),
		_luciole("l3", {}),
		_luciole("l4", {}),
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var bascules := BancComptage._appliquer_bascules(lucioles, rng, seuil)

	# Rejoue la MEME sequence de tirages avec un second RNG identiquement
	# seede pour determiner, tirage par tirage, quelles lucioles auraient
	# du basculer -- preuve que _appliquer_bascules applique exactement
	# "tirage < seuil", sans figer en dur une valeur de tirage fragile a
	# l'implementation du generateur.
	var rng_reference := RandomNumberGenerator.new()
	rng_reference.seed = 7
	var attendu: Array = []
	for id in ["l1", "l2", "l3", "l4"]:
		if rng_reference.randf() < seuil:
			attendu.append(id)

	v.v(bascules == attendu,
		"les ids bascules doivent correspondre exactement aux tirages strictement sous le seuil")
	for luciole in lucioles:
		var doit_avoir_bascule: bool = attendu.has(luciole.id)
		v.v(luciole.proprietes.has("luit") == doit_avoir_bascule,
			"'luit' doit etre posee si et seulement si le tirage etait sous le seuil, pour '%s'" % luciole.id)

func _comptage_reel_sur_la_liste_apres_bascule(v) -> void:
	var lucioles := [
		_luciole("c1", {"luit": true}),
		_luciole("c2", {}),
		_luciole("c3", {"luit": true}),
		_luciole("c4", {}),
		_luciole("c5", {"luit": true}),
		_luciole("c6", {}),
	]
	var compte := Comptage.compter(lucioles, "poissons_luisants", _catalogue_comptages_reel())
	v.v(compte == 3,
		"Comptage.compter avec la regle reelle 'poissons_luisants' doit rendre le compte exact de lucioles qui portent la cle 'luit'")

func _moyenne_glissante_lisse_le_compte(v) -> void:
	var historique := [3, 4, 3, 4, 3, 4]
	var moyenne := BancComptage._moyenne_glissante(historique)
	v.v(is_equal_approx(moyenne, 3.5), "la moyenne glissante doit rendre la moyenne exacte de l'historique")
	v.v(moyenne != float(historique[-1]),
		"la moyenne glissante doit lisser, rester distincte du dernier compte instantane")

func _resumabilite_des_lucioles(v) -> void:
	var lucioles := [
		_luciole("r1", {"luit": true}),
		_luciole("r2", {}),
		_luciole("r3", {"luit": true}),
	]
	var catalogue := _catalogue_comptages_reel()
	var texte := JSON.stringify(lucioles)
	var relues: Variant = JSON.parse_string(texte)
	v.v(relues != null, "JSON.stringify puis parse_string doit reussir sans erreur sur la liste de lucioles")
	v.v(Comptage.compter(relues, "poissons_luisants", catalogue) == Comptage.compter(lucioles, "poissons_luisants", catalogue),
		"le compte doit etre identique avant et apres un aller-retour JSON sur la liste de lucioles")
