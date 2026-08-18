extends SceneTree

# Fait respecter « Solde nul » (CLAUDE.md, « La doc ne croit pas plus vite que
# le code ») -- la SEULE regle de CLAUDE.md qu'aucun test ne tenait, et la
# raison pour laquelle trois purifications successives des documents n'ont pas
# tenu : retirer du texte ne change rien a ce qui le produit. Chaque document
# porte ici un PLAFOND en OCTETS. Le depasser fait ECHOUER le test, avec le
# nom de ce qui a grossi et de combien.
#
# POURQUOI EN OCTETS ET JAMAIS EN LIGNES : mesure faite le jour de l'ecriture
# de ce test -- la section 4 de CARTE.md ne pesait que 156 LIGNES (1 % du
# fichier) pour 228 794 OCTETS (17,5 % du fichier), une seule cellule de
# tableau atteignant 18 797 caracteres. Un plafond en lignes n'aurait rien vu.
#
# CE QUE CE TEST N'EST PAS : un interdit d'ecrire. Un plafond depasse ne dit
# pas « n'ecris pas », il dit « nomme ce qui sort en echange ». Les deux
# reponses legitimes sont RETIRER autant qu'on ajoute, ou -- si le document a
# reellement grandi pour une bonne raison -- remonter son plafond ICI, dans le
# meme commit, ce qui rend la croissance VISIBLE dans le diff au lieu de la
# laisser passer en silence. C'est tout ce qui manquait.
#
# Entree : aucune -- lit les documents sur le disque et compare leur taille au
# plafond declare. Sortie : "OK:" / exit 0 si tous sont sous leur plafond ;
# "ECHEC:" / exit 1 en nommant chaque document en depassement, son poids, son
# plafond et l'ecart, sinon.
#
# Regle : les plafonds sont des DONNEES de ce test, calibres sur l'etat reel
# du depot plus une marge de respiration deliberee. Ce test SIGNALE un
# depassement, il ne reecrit jamais un document.

const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

# Chemin -> plafond en octets. Marge de respiration comprise : un chantier
# ordinaire doit pouvoir ecrire sans toucher a ce fichier, un chantier qui
# fait exploser un document doit s'y arreter.
const PLAFONDS := {
	"res://CARTE.md": 400000,
	"res://docs/prototypes.md": 400000,
	"res://docs/ETAT.md": 25000,
	"res://docs/design.md": 160000,
	"res://CLAUDE.md": 26000,
}

# Somme de ce que CLAUDE.md (« Contexte au demarrage ») impose de relire EN
# ENTIER avant toute tache. C'est le vrai cout, celui qu'aucun plafond par
# fichier ne mesure : quatre documents chacun sous son plafond peuvent tout de
# meme rendre le demarrage impraticable.
const RELUS_AU_DEMARRAGE := [
	"res://docs/ETAT.md",
	"res://CARTE.md",
	"res://docs/design.md",
	"res://docs/prototypes.md",
]

const PLAFOND_DEMARRAGE := 1000000

func _init() -> void:
	for chemin in PLAFONDS:
		_verifier_plafond(chemin, PLAFONDS[chemin])

	_verifier_total_demarrage()

	if verif.echecs() > 0:
		print("ECHEC: %d document(s) au-dessus de leur plafond -- " % verif.echecs() +
			"retirer autant qu'ajoute, ou remonter le plafond dans " +
			"scripts/test_volume_docs.gd DANS LE MEME COMMIT")
		quit(1)
		return
	print("OK: tous les documents suivis sont sous leur plafond de taille, " +
		"et la relecture de demarrage tient sous %d octets" % PLAFOND_DEMARRAGE)
	quit(0)

func _verifier_plafond(chemin: String, plafond: int) -> void:
	if not FileAccess.file_exists(chemin):
		verif.v(false, "%s n'existe pas -- plafond declare pour un document absent" % chemin)
		return

	var taille := _taille(chemin)
	verif.v(taille <= plafond,
		"%s pese %d octets pour un plafond de %d (%d de trop) -- nommer ce qui sort en echange" %
		[chemin, taille, plafond, taille - plafond])

func _verifier_total_demarrage() -> void:
	var total := 0
	for chemin in RELUS_AU_DEMARRAGE:
		total += _taille(chemin)

	verif.v(total <= PLAFOND_DEMARRAGE,
		"la relecture imposee au demarrage pese %d octets pour un plafond de %d (%d de trop) -- " %
		[total, PLAFOND_DEMARRAGE, total - PLAFOND_DEMARRAGE] +
		"c'est le cout paye par chaque session avant d'ecrire la moindre ligne")

func _taille(chemin: String) -> int:
	var fichier := FileAccess.open(chemin, FileAccess.READ)
	if fichier == null:
		return 0
	var taille := fichier.get_length()
	fichier.close()
	return int(taille)
