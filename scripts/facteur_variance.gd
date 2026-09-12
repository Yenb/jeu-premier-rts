extends RefCounted

# FACTEUR DE VARIANCE : tire un multiplicateur individuel autour de 1.0,
# dans [1 - amplitude, 1 + amplitude], pour desynchroniser une grandeur
# uniforme (croissance, longevite, cadence, portee, cout...) entre les
# individus d'une meme population. Un mecanisme, un verbe -- un tirage
# uniforme borne.
#
# AGNOSTIQUE DU TYPE. Ne connait AUCUNE chose du monde : ni "arbre", ni
# "cohorte", ni "stade". Ne lit que le RNG et une amplitude. C'est un
# outil generique -- meme code pour toute grandeur qui doit varier
# individu par individu autour d'un pivot. Un test hors domaine
# (`scripts/test_facteur_variance.gd`) prouve la genericite sans passer
# par un contenu.
#
# PAS de class_name (doctrine) : preload("res://scripts/facteur_variance.gd").
#
# ---- CE QU'IL FAIT ----
# static tirer(rng, amplitude) : rend 1.0 + rng.randf_range(-a, +a), avec
# `a = clampf(amplitude, 0.0, 1.0)` pour garantir que le facteur reste
# dans [0.0, 2.0] (jamais negatif). Tirage SYMETRIQUE autour de 1.
# amplitude = 0 -> 1.0 exact ; amplitude = 1 -> facteur dans [0, 2] ;
# amplitude > 1 -> clampe a 1 (aucune valeur negative silencieuse).
#
# static tirer_entre(rng, bas, haut) : rend rng.randf_range(bas, haut),
# tirage ASYMETRIQUE a bornes INDEPENDANTES. Pour desynchroniser une
# grandeur avec des bornes qu'un tirage symetrique ne peut pas
# atteindre (ex : longevite dans [0.5, 2.0], impossible autour de 1
# avec une amplitude unique). bas > haut : push_error, rend bas.
# bas == haut : rend bas exact (aucun tirage). Ce chemin ne clampe
# rien -- l'appelant assume les bornes qu'il fournit, y compris
# negatives (facteur signe legitime dans certains cas).
#
# Aucun etat interne, aucun cache : l'appelant tire, garde ou jette.
#
# ---- OU LE STOCKER ----
# L'appelant tire A LA NAISSANCE de l'individu et stocke le facteur dans
# une colonne propre a sa population (Packed*Array indexee par slot),
# lu ensuite sans re-tirage. Le mecanisme ne tient AUCUNE memoire des
# tirages passes.
#
# ---- SEED ----
# Le RNG est passe en parametre : le mecanisme ne cree pas son propre
# RandomNumberGenerator. Un appelant qui exige la reproductibilite passe
# un RNG deja seede (voir CLAUDE.md § "Aucun hasard non-seede"). Deux
# appelants qui partagent le meme RNG partagent le meme flux -- coherent
# si les naissances sont serialisees, source de non-determinisme si
# elles sont concurrentes (a la charge de l'appelant, pas du mecanisme).
#
# ECART FRAMEWORK : ce fichier n'existe pas dans le depot framework Orion,
# ajoute dans cette copie faute d'equivalent generique. Le seul tirage
# individuel autour d'un pivot present dans le coeur vit ENFERME dans
# scripts/heredite.gd (rng.randi_range pour choisir un allele au tirage
# sexue, rng.randfn pour un bruit gaussien de mutation) -- usage cible
# reproduction, non reutilisable comme mecanisme de variance ouverte
# entre les individus d'une population. Meme geste doctrinal que
# scripts/monde.gd:retirer (premier precedent d'un ecart trace dans le
# fichier lui-meme). La fiche CARTE.md correspondante est un ajout a
# faire cote depot framework, pas ici (documents/ est lecture seule).

static func tirer(rng: RandomNumberGenerator, amplitude: float) -> float:
	var a: float = clampf(amplitude, 0.0, 1.0)
	if a == 0.0:
		return 1.0
	return 1.0 + rng.randf_range(-a, a)

# TIRAGE DE N PAIRES INTERLEAVED : rend deux PackedFloat32Array de taille
# n, remplis en INTERLEAVED (pour i in 0..n : randf_range(bas1, haut1)
# dans la premiere colonne, puis randf_range(bas2, haut2) dans la seconde).
# Meme sequence de randf_range que N appels alternes a `tirer_entre` --
# indispensable pour preserver l'ordre RNG bit a bit quand un manager
# de population appelle tirer_entre deux fois par naissance.
# bas > haut : push_error, colonne remplie de bas.
# n == 0 : rend deux Arrays vides.
#
# ECART FRAMEWORK : cette signature lot n'existe pas dans le depot Orion,
# ajoutee ici sous l'exception CLAUDE.md § Frontiere pour retirer les
# franchissements de frontiere par naissance du banc `jeu/bancs/
# banc_peuplement_arbre.gd:_naitre_lot`.
static func tirer_paires_entre_lot(rng: RandomNumberGenerator, n: int, bas1: float, haut1: float, bas2: float, haut2: float) -> Array:
	var col1: PackedFloat32Array = PackedFloat32Array()
	var col2: PackedFloat32Array = PackedFloat32Array()
	if n <= 0:
		return [col1, col2]
	col1.resize(n)
	col2.resize(n)
	var bornes_c1_ko: bool = bas1 > haut1
	var bornes_c2_ko: bool = bas2 > haut2
	if bornes_c1_ko:
		push_error("facteur_variance.gd : tirer_paires_entre_lot() -- bas1 %f > haut1 %f" % [bas1, haut1])
	if bornes_c2_ko:
		push_error("facteur_variance.gd : tirer_paires_entre_lot() -- bas2 %f > haut2 %f" % [bas2, haut2])
	var i: int = 0
	while i < n:
		if bornes_c1_ko:
			col1[i] = bas1
		elif bas1 == haut1:
			col1[i] = bas1
		else:
			col1[i] = rng.randf_range(bas1, haut1)
		if bornes_c2_ko:
			col2[i] = bas2
		elif bas2 == haut2:
			col2[i] = bas2
		else:
			col2[i] = rng.randf_range(bas2, haut2)
		i += 1
	return [col1, col2]

static func tirer_entre(rng: RandomNumberGenerator, bas: float, haut: float) -> float:
	# Params renommes de mini/maxi -> bas/haut : mini() et maxi() sont
	# des built-ins Godot, GDScript::reload emettait un warning par
	# masquage. Ecart framework (voir en-tete du fichier) trace ici
	# comme scripts/monde.gd:retirer, la copie framework du depot Orion
	# garde ses noms d'origine.
	if bas > haut:
		push_error("facteur_variance.gd : tirer_entre() -- bas %f > haut %f, rend bas" % [bas, haut])
		return bas
	if bas == haut:
		return bas
	return rng.randf_range(bas, haut)
