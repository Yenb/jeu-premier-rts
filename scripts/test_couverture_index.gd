extends SceneTree

# Verrouille la COUVERTURE de l'index : tout fichier de scripts/ doit etre
# nomme quelque part dans CARTE.md, et tout fichier de data/ doit avoir sa
# LIGNE D'INDEX dans la section 4. C'est le pendant exact de
# scripts/test_volume_docs.gd -- celui-la empeche la doc d'ENFLER, celui-ci
# l'empeche de MANQUER. Les deux ensemble tiennent « la doc ne croit pas plus
# vite que le code » dans les deux sens.
#
# POURQUOI IL EXISTE : mesure faite le jour de son ecriture -- treize
# data/*.json et deux scripts/*.gd vivaient dans le depot sans qu'aucune
# ligne de CARTE.md ne les nomme. Aucun test ne rougissait : test_docs.gd ne
# verifie que les adresses CITEES, jamais celles qui MANQUENT. Un fichier
# absent de l'index est un fichier qu'une session suivante reecrira de zero
# sans savoir qu'il existe.
#
# UNE LIGNE D'INDEX, ET PAS UNE MENTION EN PASSANT : pour data/, la presence
# du nom quelque part dans le fichier ne suffit pas -- un catalogue cite dans
# la cellule d'un AUTRE catalogue n'est pas indexe, il est mentionne. Le test
# exige une ligne de tableau commencant par | `nom.json` |.
#
# Entree : aucune -- liste scripts/*.gd et data/*.json sur le disque, lit
# CARTE.md. Sortie : "OK:" / exit 0 si tout est couvert ; "ECHEC:" / exit 1
# en nommant chaque fichier absent de l'index, sinon.
#
# Regle : aucune liste de fichiers en dur ici -- le disque est la source. Ce
# test SIGNALE un trou d'index, il ne l'ecrit jamais.

const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

const CARTE := "res://CARTE.md"
const DOSSIER_SCRIPTS := "res://scripts"
const DOSSIER_DATA := "res://data"

func _init() -> void:
	var carte := FileAccess.get_file_as_string(CARTE)

	for nom in _fichiers(DOSSIER_SCRIPTS, ".gd"):
		verif.v(_nomme_dans(carte, nom),
			"scripts/%s n'est nomme NULLE PART dans CARTE.md -- " % nom +
			"un fichier absent de l'index sera reecrit de zero par la session suivante")

	var lignes_index := _lignes_index_data(carte)
	for nom in _fichiers(DOSSIER_DATA, ".json"):
		verif.v(lignes_index.has(nom),
			"data/%s n'a pas de LIGNE D'INDEX dans CARTE.md section 4 " % nom +
			"(une mention dans la cellule d'un autre catalogue ne compte pas)")

	if verif.echecs() > 0:
		print("ECHEC: %d fichier(s) hors de l'index de CARTE.md" % verif.echecs())
		quit(1)
		return
	print("OK: tout scripts/*.gd est nomme dans CARTE.md et tout data/*.json " +
		"porte sa ligne d'index en section 4")
	quit(0)

# Frontiere de mot OBLIGATOIRE : une simple recherche de sous-chaine rendrait
# `banc_succession.gd` couvert par la seule presence de
# `test_banc_succession.gd`, et le trou resterait invisible (constate a
# l'ecriture de ce test).
func _nomme_dans(texte: String, nom: String) -> bool:
	var motif := RegEx.new()
	motif.compile("(?<![A-Za-z0-9_])" + nom.replace(".", "\\."))
	return motif.search(texte) != null

func _fichiers(dossier: String, extension: String) -> Array:
	var noms := []
	var repertoire := DirAccess.open(dossier)
	if repertoire == null:
		verif.v(false, "%s illisible" % dossier)
		return noms
	repertoire.list_dir_begin()
	var nom := repertoire.get_next()
	while nom != "":
		if not repertoire.current_is_dir() and nom.ends_with(extension):
			noms.append(nom)
		nom = repertoire.get_next()
	repertoire.list_dir_end()
	noms.sort()
	return noms

# Les lignes d'index de la section 4 : « | `nom.json` | ... ». La section
# s'ouvre sur « ## 4. » et se ferme sur l'entete suivant de meme niveau.
func _lignes_index_data(carte: String) -> Dictionary:
	var trouves := {}
	var dans_section := false
	for ligne in carte.split("\n"):
		var texte: String = ligne
		if texte.begins_with("## "):
			dans_section = texte.begins_with("## 4.")
			continue
		if not dans_section:
			continue
		var motif := RegEx.new()
		motif.compile("^\\|\\s*`([a-z0-9_]+\\.json)`")
		var correspondance := motif.search(texte)
		if correspondance != null:
			trouves[correspondance.get_string(1)] = true
	return trouves
