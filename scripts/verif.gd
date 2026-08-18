extends RefCounted

# Aide de test partagee. assert() natif est INTERDIT dans les tests : en
# --headless --script, un assert qui echoue ne rend jamais la main -- le
# processus pend au lieu de se terminer (constat verifie a l'execution,
# chantier "le lanceur ne doit plus geler", docs/prototypes.md). v()
# compte les echecs a la place, via push_error (visible, ne bloque
# jamais) ; l'appelant DOIT conditionner sa sortie sur echecs() et
# quitter explicitement (quit(0) ou quit(1)), jamais laisser un assert
# natif faire le travail.
#
# Nomme hors motif test_*.gd exprès : ce n'est pas un test, lanceur.gd ne
# le ramasse jamais.

var _echecs := 0

func v(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		_echecs += 1

func echecs() -> int:
	return _echecs
