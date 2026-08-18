extends SceneTree

# Verrouille l'alignement entre les documents (CARTE.md, docs/prototypes.md,
# docs/design.md) et le code : toute adresse au format <nom>.gd:<identifiant>
# citee dans ces trois documents doit designer une fonction reellement
# declaree dans res://scripts/<nom>.gd. Rien ne relie ces documents au code
# autrement -- une fonction renommee ou supprimee ne fait rougir aucun autre
# test, alors que ces documents sont relus en entier a chaque session
# (CLAUDE.md, "Contexte au demarrage") et servent a decider sans ouvrir le
# code. Ce test ferme ce trou.
#
# Verrouille aussi les renvois de SECTION (§N, §Nter, §3quindecies...) : seul
# CARTE.md numerote ses sections (## <id>. Titre) ; docs/prototypes.md et
# docs/design.md n'en ont aucune (titres nommes uniquement) et tout §<id>
# rencontre, dans les trois documents, cite donc TOUJOURS une section de
# CARTE.md -- verifie empiriquement (aucune exception au moment ou ce test a
# ete ecrit). Un renvoi vers une section absente de CARTE.md fait rougir le
# test. Les renvois NOMMES entre guillemets ont leur propre scan, plus bas :
# ils ne craignent pas l'insertion d'une section, mais ils meurent en silence
# des qu'un titre est reecrit -- neuf d'entre eux etaient morts le jour ou ce
# scan a ete ecrit.
#
# Entree : aucune -- lit CARTE.md, docs/prototypes.md et docs/design.md sur
# le disque. Pour les adresses : extrait chaque adresse par RegEx (motif
# <nom>.gd:<identifiant>, sans espace autour du ":"), resout <nom>.gd vers
# res://scripts/<nom>.gd, et verifie par recherche textuelle qu'une ligne
# "func <identifiant>(" y existe. Pour les sections : extrait les identifiants
# reels de CARTE.md (motif "## <id>." en tete de ligne) puis verifie que
# chaque §<id> cite dans les trois documents figure dans cet ensemble.
# Sortie : "OK:" / exit 0 si toutes les adresses et tous les renvois de
# section sont justes ; "ECHEC:" / exit 1 en nommant chaque adresse ou renvoi
# fautif et son document sinon.
#
# Regle : aucune adresse, aucun renvoi de section ni aucun nom de fichier de
# script en dur ici -- tout est decouvert par lecture des documents (seuls
# les CHEMINS DES TROIS DOCUMENTS eux-memes sont fixes, ce sont les entrees
# du test, pas des adresses ou des sections a verifier). Ce test SIGNALE une
# adresse ou un renvoi fautif, il ne le corrige jamais.
#
# PIEGE DEJA PAYE QUATRE FOIS, a ne pas repayer : la forme `fichier:nom` est
# RESERVEE AUX FONCTIONS. Ecrire `test_lint_donnees.gd:REFERENCES` ou
# `epigenetique.gd:age_marque` dans un document -- une CONSTANTE, un CHAMP --
# fait rougir ce test, qui ne sait chercher qu'une ligne "func <nom>(". Pour
# citer autre chose qu'une fonction, nommer en prose : « la constante
# `REFERENCES` de `scripts/test_lint_donnees.gd` ».

const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

# Les documents PERMANENTS : ceux qu'une session relit pour decider sans
# ouvrir le code. Les journaux (cadrage, suivi) en sont exclus -- chacune
# de leurs entrees fige un etat a l'instant ou elle est ecrite, l'exiger
# vraie pour toujours obligerait a reecrire l'historique.
const DOCUMENTS := [
	"res://CARTE.md",
	"res://docs/prototypes.md",
	"res://docs/design.md",
	"res://docs/ETAT.md",
	"res://CLAUDE.md",
]

const DOCUMENT_SECTIONS := "res://CARTE.md"

# Les rapports d'audit sont JETABLES et gitignores (CLAUDE.md, Arborescence) :
# un document permanent qui renvoie vers l'un d'eux renvoie vers un fichier
# que personne d'autre n'a et que git ne retrouvera jamais. Le fait cite doit
# etre recopie dans le document permanent, ou le renvoi retire.
# La classe accepte le TIRET et le POINT : un nom de rapport porte
# couramment une date, et une classe reduite aux minuscules et au
# soulignement laisse passer precisement ce que ce garde vise.
const MOTIF_AUDIT := "audit_[A-Za-z0-9_.-]+\\.md"

func _init() -> void:
	var motif_adresse := RegEx.new()
	motif_adresse.compile("([A-Za-z0-9_]+)\\.gd:([A-Za-z_][A-Za-z0-9_]*)")

	for doc in DOCUMENTS:
		var texte := FileAccess.get_file_as_string(doc)
		for correspondance in motif_adresse.search_all(texte):
			var nom_fichier: String = correspondance.get_string(1)
			var identifiant: String = correspondance.get_string(2)
			_verifier_adresse(doc, nom_fichier, identifiant)

	_verifier_renvois_section()
	_verifier_renvois_audit()
	_verifier_renvois_nommes()

	if verif.echecs() > 0:
		print("ECHEC: %d adresse(s)/renvoi(s) fautif(s)" % verif.echecs())
		quit(1)
		return
	print("OK: toutes les adresses fichier:fonction et tous les renvois de " +
		"section §N citees dans les %d documents permanents designent une " % DOCUMENTS.size() +
		"fonction ou une section reelle, aucun d'eux ne renvoie vers un " +
		"rapport d'audit jetable, et tout renvoi NOMME -- documents ET prose " +
		"du code -- cite un texte qui existe encore dans le document vise")
	quit(0)

func _verifier_renvois_audit() -> void:
	var motif := RegEx.new()
	motif.compile(MOTIF_AUDIT)

	for doc in DOCUMENTS:
		var texte := FileAccess.get_file_as_string(doc)
		var deja_vus := {}
		for correspondance in motif.search_all(texte):
			var nom: String = correspondance.get_string(0)
			if deja_vus.has(nom):
				continue
			deja_vus[nom] = true
			var ligne := texte.substr(0, correspondance.get_start()).count("\n") + 1
			verif.v(false,
				"%s:%d renvoie vers `%s` -- les rapports d'audit sont jetables et " %
				[doc, ligne, nom] +
				"gitignores : recopier le fait cite dans ce document, ou retirer le renvoi")

func _verifier_adresse(doc: String, nom_fichier: String, identifiant: String) -> void:
	var chemin := "res://scripts/%s.gd" % nom_fichier
	if not FileAccess.file_exists(chemin):
		verif.v(false, "%s cite %s.gd:%s -- %s n'existe pas dans scripts/" %
			[doc, nom_fichier, identifiant, chemin])
		return

	var contenu := FileAccess.get_file_as_string(chemin)
	var motif_fonction := RegEx.new()
	motif_fonction.compile("func\\s+%s\\s*\\(" % identifiant)
	var declaree := motif_fonction.search(contenu) != null
	verif.v(declaree, "%s cite %s:%s -- aucune ligne 'func %s(' dans %s" %
		[doc, nom_fichier, identifiant, identifiant, chemin])

func _verifier_renvois_section() -> void:
	var sections_reelles := _extraire_sections(FileAccess.get_file_as_string(DOCUMENT_SECTIONS))

	var motif_renvoi := RegEx.new()
	motif_renvoi.compile("§([0-9]+[a-z]*)")

	for doc in DOCUMENTS:
		var texte := FileAccess.get_file_as_string(doc)
		for correspondance in motif_renvoi.search_all(texte):
			var id_section: String = correspondance.get_string(1)
			var ligne := texte.substr(0, correspondance.get_start()).count("\n") + 1
			verif.v(sections_reelles.has(id_section),
				"%s:%d cite §%s -- %s n'a pas de section « ## %s. » " %
				[doc, ligne, id_section, DOCUMENT_SECTIONS, id_section])

func _extraire_sections(texte: String) -> Dictionary:
	var sections := {}
	var motif_entete := RegEx.new()
	motif_entete.compile("(?m)^## ([0-9]+[a-z]*)\\.")
	for correspondance in motif_entete.search_all(texte):
		sections[correspondance.get_string(1)] = true
	return sections

# TROISIEME SCAN : LE RENVOI NOMME. Un renvoi numerote (§N) est verrouille
# plus haut ; un renvoi par TITRE ne l'etait par rien, et c'est par la que
# passent les references mortes -- un titre de section renomme laisse derriere
# lui des citations qui ne designent plus rien, dans des fichiers que personne
# ne relit en meme temps que le document.
#
# CE QUI EST EXIGE, et c'est volontairement FAIBLE : que le texte cite existe
# ENCORE dans le document vise, en titre OU en corps. Exiger un TITRE serait
# faux -- beaucoup de renvois legitimes visent un passage nomme en majuscules
# a l'interieur d'une section, jamais son en-tete. La garantie tenue est donc
# « ce renvoi ne pointe pas vers une phrase disparue », pas « ce renvoi
# designe une section ».
#
# OU L'ON CHERCHE : dans les documents, mais aussi dans la PROSE du code --
# lignes de commentaire des scripts/*.gd et lignes portant une cle de note des
# data/*.json (memes conventions que test_recit_dans_le_code.gd). C'est la que
# vivaient les renvois morts que ce scan existe pour attraper, jamais dans un
# document.
#
# COMPARAISON NORMALISEE : minuscules, accents retires, ponctuation ramenee a
# une espace. Sans elle rien ne matcherait -- les .gd citent sans accent, les
# .md avec, et les guillemets different d'un fichier a l'autre.
const DOCUMENTS_NOMMES := {
	"CARTE.md": "res://CARTE.md",
	"prototypes.md": "res://docs/prototypes.md",
	"design.md": "res://docs/design.md",
}

# Sous ce nombre de caracteres normalises, un texte entre guillemets pres d'un
# nom de document est trop court pour etre un renvoi : c'est un mot cite.
const LONGUEUR_MIN_RENVOI := 12

const ACCENTS_RENVOI := {
	"à": "a", "â": "a", "ä": "a", "é": "e", "è": "e", "ê": "e", "ë": "e",
	"î": "i", "ï": "i", "ô": "o", "ö": "o", "ù": "u", "û": "u", "ü": "u",
	"ç": "c", "œ": "oe", "æ": "ae",
}

func _verifier_renvois_nommes() -> void:
	var corpus := {}
	for nom in DOCUMENTS_NOMMES:
		corpus[nom] = _normaliser_renvoi(FileAccess.get_file_as_string(DOCUMENTS_NOMMES[nom]))

	var motif := RegEx.new()
	motif.compile('(CARTE|prototypes|design)\\.md[^"«\\n]{0,24}["«]\\s*([^"»\\n]{4,90}?)\\s*["»]')

	for source in _sources_de_prose():
		var texte: String = source.texte
		for correspondance in motif.search_all(texte):
			var cible: String = "%s.md" % correspondance.get_string(1)
			var cite: String = _normaliser_renvoi(correspondance.get_string(2))
			if cite.length() < LONGUEUR_MIN_RENVOI:
				continue
			if corpus[cible].find(cite) != -1:
				continue
			var ligne := texte.substr(0, correspondance.get_start()).count("\n") + 1
			verif.v(false,
				"%s:%d renvoie a %s « %s » -- ce texte n'existe plus dans %s, " %
				[source.chemin, ligne, cible, correspondance.get_string(2), cible] +
				"ni en titre ni en corps : le renvoi est mort")

# Substitution par RegEx, jamais caractere par caractere : les documents
# pesent des centaines de milliers d'octets, et une concatenation en boucle
# GDScript y coute assez pour faire DEPASSER le lanceur (constate). Le motif
# est compile UNE FOIS.
var _motif_normalisation: RegEx = null

func _normaliser_renvoi(texte: String) -> String:
	if _motif_normalisation == null:
		_motif_normalisation = RegEx.new()
		_motif_normalisation.compile("[^a-z0-9]+")
	var bas := texte.to_lower()
	for accent in ACCENTS_RENVOI:
		bas = bas.replace(accent, ACCENTS_RENVOI[accent])
	return _motif_normalisation.sub(bas, " ", true).strip_edges()

# Les documents EN ENTIER, plus la seule PROSE du code : un renvoi ecrit dans
# une chaine de caracteres executee (un print, un message d'erreur) n'est pas
# une reference de lecture, il ne se verifie pas ici.
func _sources_de_prose() -> Array:
	var sources: Array = []
	for doc in DOCUMENTS:
		sources.append({"chemin": doc, "texte": FileAccess.get_file_as_string(doc)})

	var motif_note := RegEx.new()
	motif_note.compile('"[a-z_]*(note|commentaire|pourquoi|description|remarque)[a-z_]*"[ \\t]*:')

	for dossier_nom in [["res://scripts", ".gd"], ["res://data", ".json"]]:
		var dossier := DirAccess.open(dossier_nom[0])
		if dossier == null:
			verif.v(false, "impossible d'ouvrir %s" % dossier_nom[0])
			continue
		dossier.list_dir_begin()
		var nom := dossier.get_next()
		while nom != "":
			if not dossier.current_is_dir() and nom.ends_with(dossier_nom[1]):
				var chemin: String = "%s/%s" % [dossier_nom[0], nom]
				var lignes: PackedStringArray = []
				for ligne in FileAccess.get_file_as_string(chemin).split("\n"):
					var garde: bool = ligne.strip_edges().begins_with("#") if dossier_nom[1] == ".gd" \
						else motif_note.search(ligne) != null
					lignes.append(ligne if garde else "")
				sources.append({"chemin": chemin, "texte": "\n".join(lignes)})
			nom = dossier.get_next()
		dossier.list_dir_end()
	return sources
