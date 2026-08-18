extends SceneTree

# Lanceur de tests : outil de developpement, pas une couche du moteur.
# Decouvre et execute tous les scripts/test_*.gd, chacun en sous-processus
# godot --headless independant (chaque test est deja un point d'entree
# SceneTree autonome, on ne peut pas les instancier dans ce process-ci).
#
# Entree : aucune -- lit le systeme de fichiers res://scripts/ et relance
# le meme executable Godot (OS.get_executable_path()) pour chaque test
# trouve.
# Sortie : un tableau "nom -> VERT/ROUGE/DEPASSE" imprime sur stdout,
# message d'erreur (ou extrait de sortie) pour chaque non-VERT. Code de
# sortie 0 si tout est vert, 1 sinon.
#
# Regles :
# - Decouverte automatique par DirAccess sur le motif test_*.gd. Aucun
#   nom de fichier en dur ici : un fichier hors motif (verif.gd, ce
#   lanceur lui-meme, nomme hors motif expres) n'est jamais ramasse.
# - Verdict a trois etats :
#     VERT    -> le sous-processus s'est termine ET (exit == 0 ET la
#                sortie contient "OK:") -- ou, pour un test marque
#                "echec-attendu", exit != 0.
#     ROUGE   -> le sous-processus s'est termine mais le verdict ci-dessus
#                est faux (assertion ratee, pas de "OK:", etc.).
#     DEPASSE -> le sous-processus n'a PAS rendu la main avant DELAI_MSEC.
#                Etat distinct de ROUGE a dessein : un depassement peut
#                venir d'une boucle infinie, d'une attente d'entree, ou
#                (constate en session) d'un assert() natif de GDScript
#                qui, une fois son message imprime, ne rend jamais la
#                main en --headless --script -- perdre cette distinction
#                dans un ROUGE indifferencie cacherait que le test n'a
#                jamais fini, pas juste rate une valeur attendue.
#
# MECANISME DE DELAI (chantier "le lanceur ne doit plus geler") :
# OS.execute(..., blocking=true) (ancienne forme) n'a pas de timeout et
# gele le lanceur ENTIER des le premier sous-processus qui ne rend pas la
# main. OS.execute_with_pipe a ete essaye et abandonne : sur cette machine,
# is_process_running() sur le pid qu'il rend ne detecte jamais la fin du
# processus, meme pour un test rapide et sain (verifie empiriquement,
# is_process_running restait "true" apres 10+ secondes pour un test qui
# finit normalement en moins d'une seconde) -- bug d'implementation cote
# pipe sur cette plateforme, pas un choix a reproduire.
#
# Solution retenue, verifiee empiriquement : OS.create_process (SANS
# pipe) sur "cmd.exe" avec redirection shell ("> fichier 2>&1") pour
# capturer la sortie dans un fichier temporaire hors du depot
# (OS.get_environment("TEMP")). is_process_running(pid) sur le pid de
# cmd.exe rendu par create_process detecte correctement la fin du
# sous-processus (verifie : ~1s pour un test rapide, jamais bloque). Si
# DELAI_MSEC est atteint sans que le processus ne se termine, "taskkill
# /F /T /PID <pid>" est utilise plutot que OS.kill(pid) seul : kill() ne
# tue que le cmd.exe immediat, pas l'arbre de processus -- le vrai
# sous-processus godot.exe (celui qui pend reellement) survivrait en
# orphelin sinon. Verifie : taskkill /T termine bien cmd.exe ET l'enfant
# godot.exe, aucun processus Godot ne reste apres.
#
# DELAI_MSEC = 30s : les tests les plus lents observes tournent en ~1-2s
# reels (les boucles a centaines d'iterations le sont en temps simule,
# pas en temps mur). 30s laisse une marge large (15-30x) pour une machine
# chargee sans laisser un test bloque geler le lanceur plus que quelques
# dizaines de secondes.

const DOSSIER := "res://scripts"
const MARQUEUR_ECHEC_ATTENDU := "# LANCEUR: echec-attendu"
const DELAI_MSEC := 30000
const PAS_SONDAGE_MSEC := 100

func _init() -> void:
	var fichiers := _decouvrir_tests()
	fichiers.sort()

	var resultats: Array = []
	for fichier in fichiers:
		resultats.append(_executer(fichier))

	var tout_vert := _imprimer_tableau(resultats)
	quit(0 if tout_vert else 1)

func _decouvrir_tests() -> Array:
	var fichiers: Array = []
	var dir := DirAccess.open(DOSSIER)
	if dir == null:
		push_error("impossible d'ouvrir %s" % DOSSIER)
		return fichiers
	dir.list_dir_begin()
	var nom := dir.get_next()
	while nom != "":
		if not dir.current_is_dir() and nom.begins_with("test_") and nom.ends_with(".gd"):
			fichiers.append(nom)
		nom = dir.get_next()
	dir.list_dir_end()
	return fichiers

func _executer(fichier: String) -> Dictionary:
	var chemin := "%s/%s" % [DOSSIER, fichier]
	var contenu := FileAccess.get_file_as_string(chemin)
	var attendu_en_echec := contenu.find(MARQUEUR_ECHEC_ATTENDU) != -1

	var exe := OS.get_executable_path()
	var dossier_temp := OS.get_environment("TEMP")
	if dossier_temp == "":
		dossier_temp = ProjectSettings.globalize_path("res://")
	# Le PID separe deux lanceurs simultanes -- voir CARTE.md §6.
	var sortie_os := "%s/orion_lanceur_%d_%s.tmp" % [dossier_temp, OS.get_process_id(), fichier.get_basename()]
	var ligne := "\"%s\" --headless --script \"scripts/%s\" > \"%s\" 2>&1" % [exe, fichier, sortie_os]
	var pid := OS.create_process("cmd.exe", ["/c", ligne])

	var ecoule := 0
	var termine := false
	while ecoule < DELAI_MSEC:
		if not OS.is_process_running(pid):
			termine = true
			break
		OS.delay_msec(PAS_SONDAGE_MSEC)
		ecoule += PAS_SONDAGE_MSEC

	var code := -1
	if termine:
		code = OS.get_process_exit_code(pid)
	else:
		OS.execute("taskkill", ["/F", "/T", "/PID", str(pid)], [], true)
		OS.delay_msec(300)

	var texte := ""
	if FileAccess.file_exists(sortie_os):
		texte = FileAccess.get_file_as_string(sortie_os)
		DirAccess.remove_absolute(sortie_os)

	var vert: bool
	if not termine:
		vert = false
	elif attendu_en_echec:
		vert = code != 0
	else:
		vert = code == 0 and texte.find("OK:") != -1

	return {"nom": fichier, "vert": vert, "depasse": not termine, "sortie": texte}

func _imprimer_tableau(resultats: Array) -> bool:
	var tout_vert := true
	print("")
	print("=== Resultats (%d tests) ===" % resultats.size())
	for r in resultats:
		var etat: String
		if r.depasse:
			etat = "DEPASSE"
			tout_vert = false
		elif r.vert:
			etat = "VERT"
		else:
			etat = "ROUGE"
			tout_vert = false
		print("%s -> %s" % [_pad(r.nom, 24), etat])
		if not r.vert:
			print("    %s" % r.sortie.strip_edges())
	return tout_vert

func _pad(texte: String, largeur: int) -> String:
	var r := texte
	while r.length() < largeur:
		r += " "
	return r
