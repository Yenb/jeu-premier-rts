extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_encodage.gd
#
# GARDE CONTRE LE DOUBLE ENCODAGE UTF-8 dans scripts/*.gd et data/*.json.
# Un caractere accentue s'ecrit sur deux octets. Un outil qui relit le fichier
# en croyant que chaque octet est une lettre voit DEUX lettres a la place, et
# les reecrit telles quelles : un guillemet ouvrant se retrouve precede d'un
# A-circonflexe parasite, un e-accent precede d'un A-tilde. Le texte est abime,
# le programme continue de marcher, et AUCUN autre test ne le voit -- ils
# verifient ce que le code FAIT, jamais si ses caracteres sont justes.
# (Les sequences ne sont pas reproduites ici : ce fichier rougirait sur son
# propre en-tete. Elles se lisent dans TETES, plus bas.)
#
# LE RISQUE EST REEL ET RECURRENT : toute manipulation par script des fichiers
# du depot le recree si l'outil lit en ANSI ce qui est ecrit en UTF-8.
# PowerShell 5.1 le fait par defaut (Get-Content), et c'est ainsi que trois
# en-tetes de banc ont ete abimes avant que ce garde n'existe.
#
# CE QUI EST CHERCHE, et pas autre chose : une des deux tetes de TETES SUIVIE
# d'un autre caractere non ASCII -- la signature du double encodage. LE PIEGE A
# EVITER, paye une fois : chercher la tete SEULE rougit sur chaque occurrence
# du mot « cablage » ecrit en majuscules accentuees, qui est du francais
# parfaitement valide. C'est la SEQUENCE qui trahit, jamais la lettre.
#
# Entree : aucune -- lit les fichiers sur le disque. Sortie : "OK:" / exit 0 si
# aucun fichier ne porte la sequence ; "ECHEC:" / exit 1 en nommant chaque
# fichier, sa ligne et l'extrait fautif, sinon.

const Verif = preload("res://scripts/verif.gd")

const DOSSIER_CODE := "res://scripts"
const DOSSIER_DONNEES := "res://data"

# Les deux tetes de sequence que produit une relecture ANSI d'un texte UTF-8 :
# 0xC3 (A-tilde) et 0xC2 (A-circonflexe), lus comme des lettres puis reencodes.
const TETES := ["Ã", "Â"]

var verif := Verif.new()

func _init() -> void:
	var chemins := _lister_cibles()
	if chemins.is_empty():
		print("ECHEC: aucun fichier trouve -- le test ne mesure rien")
		quit(1)
		return

	for chemin in chemins:
		_verifier(chemin)

	if verif.echecs() > 0:
		print("ECHEC: %d fichier(s) portent une sequence de double encodage -- " % verif.echecs() +
			"les reecrire en lisant l'UTF-8 comme de l'UTF-8, jamais comme de l'ANSI")
		quit(1)
		return

	print("OK: les %d fichiers de scripts/ et data/ sont en UTF-8 simple, aucune sequence de double encodage" % chemins.size())
	quit(0)

func _lister_cibles() -> Array:
	var chemins: Array = []
	for nom in DirAccess.get_files_at(DOSSIER_CODE):
		if nom.ends_with(".gd"):
			chemins.append("%s/%s" % [DOSSIER_CODE, nom])
	for nom in DirAccess.get_files_at(DOSSIER_DONNEES):
		if nom.ends_with(".json"):
			chemins.append("%s/%s" % [DOSSIER_DONNEES, nom])
	chemins.sort()
	return chemins

# Une tete de sequence suivie d'un caractere NON ASCII est du double encodage.
# Suivie d'une lettre ordinaire (« CÂBLAGE », « Ça »), c'est du francais.
func _verifier(chemin: String) -> void:
	var texte := FileAccess.get_file_as_string(chemin)
	if texte.is_empty():
		push_error("test_encodage.gd : %s illisible ou vide" % chemin)
		return
	var lignes := texte.split("\n")
	for i in range(lignes.size()):
		var ligne: String = lignes[i]
		for tete in TETES:
			var pos := ligne.find(tete)
			while pos != -1:
				if pos + 1 < ligne.length() and ligne.unicode_at(pos + 1) > 127:
					var debut: int = max(0, pos - 20)
					verif.v(false, "%s:%d porte une sequence de double encodage -- « %s »" % [
						chemin, i + 1, ligne.substr(debut, 45).strip_edges()])
					return
				pos = ligne.find(tete, pos + 1)
