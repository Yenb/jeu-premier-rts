extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_registre_banc_commun.gd
#
# Verrouille l'alignement entre le REGISTRE inscrit dans l'en-tete de
# scripts/banc_commun.gd et les static func publiques qu'il porte
# reellement -- meme principe que test_docs.gd (code<->doc), applique
# ici a code<->registre. Une fonction ajoutee sans sa ligne de registre
# (ou une ligne de registre sans fonction correspondante) est exactement
# la derive que la NOTICE D'EXTENSION de banc_commun.gd interdit -- ce
# test la PROUVE, il ne la corrige jamais (comme test_docs.gd).
#
# Entree : aucune -- lit scripts/banc_commun.gd sur le disque.
# Sortie : "OK:"/exit 0 si chaque static func publique (nom qui ne
# commence pas par "_") a exactement une ligne "# - nom : ..." dans
# l'en-tete, et reciproquement ; "ECHEC:"/exit 1 en nommant chaque ecart
# sinon.

const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

const CHEMIN := "res://scripts/banc_commun.gd"

func _init() -> void:
	var texte := FileAccess.get_file_as_string(CHEMIN)

	var fonctions := _fonctions_publiques(texte)
	var registre := _entrees_registre(texte)

	for nom in fonctions:
		verif.v(registre.has(nom),
			"banc_commun.gd:%s est une static func publique sans ligne de registre" % nom)
	for nom in registre:
		verif.v(fonctions.has(nom),
			"le registre de banc_commun.gd cite '%s', aucune static func publique de ce nom" % nom)

	if verif.echecs() > 0:
		print("ECHEC: %d ecart(s) entre le registre et le code" % verif.echecs())
		quit(1)
		return
	print("OK: chaque static func publique de banc_commun.gd a sa ligne de registre, " +
		"et reciproquement")
	quit(0)

# Toute static func dont le nom NE commence PAS par "_" -- convention deja
# en place dans le depot (les helpers prives commencent par "_", voir
# extinction.gd:_appliquer_a_zero, agir.gd:_action...) pour distinguer une
# fonction publique d'un helper prive, qui n'a pas a figurer au registre.
func _fonctions_publiques(texte: String) -> Array:
	var motif := RegEx.new()
	motif.compile("static func ([A-Za-z_][A-Za-z0-9_]*)\\s*\\(")
	var noms: Array = []
	for correspondance in motif.search_all(texte):
		var nom: String = correspondance.get_string(1)
		if not nom.begins_with("_"):
			noms.append(nom)
	return noms

# Une ligne de registre commence EXACTEMENT par "# - " (un espace de
# chaque cote du tiret, en debut de ligne) -- distinct des puces du
# CRITERE D'ENTREE dans le meme en-tete, qui s'indentent de trois espaces
# ("#   - STATIQUE :") : begins_with("# - ") les exclut deja par
# construction, aucun filtre supplementaire necessaire.
func _entrees_registre(texte: String) -> Array:
	var noms: Array = []
	for ligne in texte.split("\n"):
		if not ligne.begins_with("# - "):
			continue
		var reste := ligne.substr(4)
		var fin := reste.find(" :")
		if fin == -1:
			continue
		noms.append(reste.substr(0, fin))
	return noms
