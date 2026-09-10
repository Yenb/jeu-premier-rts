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
# dans [0.0, 2.0] (jamais negatif). amplitude = 0 -> 1.0 exact ;
# amplitude = 1 -> facteur dans [0, 2] ; amplitude > 1 -> clampe a 1
# (aucune valeur negative silencieuse). Aucun etat interne, aucun cache :
# l'appelant tire, garde la valeur ou la jette.
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
# ECART FRAMEWORK : ce fichier est ajoute dans la copie scripts/ du jeu,
# pas dans le depot framework (voir CLAUDE.md § Frontiere, precedent
# scripts/monde.gd:retirer). A remonter au framework quand un second
# banc en aura besoin.

static func tirer(rng: RandomNumberGenerator, amplitude: float) -> float:
	var a: float = clampf(amplitude, 0.0, 1.0)
	if a == 0.0:
		return 1.0
	return 1.0 + rng.randf_range(-a, a)
