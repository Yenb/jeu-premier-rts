extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_dominance.gd
#
# _le_modele_ignore_le_domaine() verrouille que dominance.gd n'ecrase que
# par NOMBRE : des saillances etiquetees de domaines inventes ("echo",
# "parfum", "bourdonnement", absents de tout le moteur, verifie par grep)
# survivent ou sont ecrasees selon leur seul saillance, jamais selon leur
# domaine.

const Dominance = preload("res://scripts/dominance.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

func _init() -> void:
	var resultats := [
		{"attache": {"type": "a"}, "menace": 0.9, "saillance": 2.8},
		{"attache": {"type": "b"}, "menace": 0.0, "saillance": 0.4},
		{"attache": {"type": "c"}, "menace": 0.3, "saillance": 1.3},
	]

	var large := {"proprietes": {"forme": {"seuil_ecrasement": 3.0}}}
	var etroit := {"proprietes": {"forme": {"seuil_ecrasement": 1.0}}}

	var vu_large = Dominance.visibles(resultats, large)
	var vu_etroit = Dominance.visibles(resultats, etroit)

	verif.v(vu_large.size() == 3, "large : tout doit rester visible")
	verif.v(vu_etroit.size() == 1, "etroit : un seul doit rester")
	verif.v(vu_etroit[0].attache.type == "a", "etroit : le sommet reste")

	_le_modele_ignore_le_domaine(verif)
	_forme_absente_alarme_et_rend_la_liste_telle_quelle(verif)
	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return

	print("OK: memes saillances, champs differents (%d vs %d), " % [
		vu_large.size(), vu_etroit.size()
	] + "domaines inventes ecrases par pur seuil numerique")
	quit(0)

# LA GARDE STRUCTURELLE de dominance.gd, exercee ici et nulle part ailleurs
# (doctrine : docs/design.md). Laisser passer la liste entiere serait le
# pire des deux : une decision prise sur un ecrasement qui n'a pas eu lieu.
func _forme_absente_alarme_et_rend_la_liste_telle_quelle(v) -> void:
	var resultats := [
		{"type": "a", "saillance": 5.0},
		{"type": "b", "saillance": 0.1},
	]
	v.v(Dominance.visibles(resultats, {"proprietes": {}}).is_empty(),
		"'forme' absente : alarme puis retour neutre, jamais la liste non ecrasee")
	v.v(Dominance.visibles([], {"proprietes": {}}).is_empty(),
		"liste vide : rien a ecraser, aucune alarme a lever")

# LA serrure hors domaine : des saillances de domaines inventes, sans
# aucun rapport avec le feu ni entre eux, doivent survivre ou etre
# ecrasees par le SEUL nombre, jamais par leur nom. Si ce test passe,
# dominance.gd ne connait aucun domaine.
func _le_modele_ignore_le_domaine(v) -> void:
	# Seuil large : deux domaines invente + un domaine "feu" survivent
	# ensemble -- aucun domaine n'est privilegie.
	var mixte := [
		{"type": "echo", "saillance": 5.0},
		{"type": "parfum", "saillance": 4.0},
		{"type": "feu", "saillance": 3.5},
	]
	var vu_mixte := Dominance.visibles(mixte, {"proprietes": {"forme": {"seuil_ecrasement": 2.0}}})
	v.v(vu_mixte.size() == 3,
		"seuil large : des domaines inventes et un domaine reel survivent ensemble")

	# Seuil etroit : seul le sommet numerique survit, que le sommet soit
	# invente et que ce qui est ecrase soit du feu, ou l'inverse.
	var invente_au_sommet := [
		{"type": "bourdonnement", "saillance": 9.0},
		{"type": "feu", "saillance": 2.0},
	]
	var vu_a := Dominance.visibles(invente_au_sommet, {"proprietes": {"forme": {"seuil_ecrasement": 0.5}}})
	v.v(vu_a.size() == 1 and vu_a[0].type == "bourdonnement",
		"seuil etroit : le domaine invente au sommet ecrase le feu, par le seul nombre")

	var feu_au_sommet := [
		{"type": "feu", "saillance": 9.0},
		{"type": "echo", "saillance": 2.0},
	]
	var vu_b := Dominance.visibles(feu_au_sommet, {"proprietes": {"forme": {"seuil_ecrasement": 0.5}}})
	v.v(vu_b.size() == 1 and vu_b[0].type == "feu",
		"seuil etroit : le feu au sommet ecrase le domaine invente, par le seul nombre")

	# Egalite de sommet entre deux domaines inventes : les deux survivent,
	# l'egalite ne departage jamais par domaine.
	var egalite := [
		{"type": "echo", "saillance": 6.0},
		{"type": "parfum", "saillance": 6.0},
		{"type": "bourdonnement", "saillance": 1.0},
	]
	var vu_egalite := Dominance.visibles(egalite, {"proprietes": {"forme": {"seuil_ecrasement": 0.5}}})
	var types_egalite: Array = []
	for r in vu_egalite:
		types_egalite.append(r.type)
	v.v(types_egalite.size() == 2 and types_egalite.has("echo") and types_egalite.has("parfum"),
		"deux domaines inventes a egalite de sommet survivent tous les deux")
