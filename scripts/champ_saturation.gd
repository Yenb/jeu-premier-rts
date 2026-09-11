extends RefCounted

# CHAMP DE SATURATION : depot d'un scalaire float SIGNE sur les cases d'une
# grille XZ autour d'un centre, avec decroissance lineaire en norme Chebyshev
# (plein au centre, zero au bord). Le champ est un Dictionary case -> float
# (Vector2i -> float), lu en O(1) a une position. Depot et retrait sont
# strictement symetriques : appeler deposer(...) puis deposer(...) avec le
# SIGNE OPPOSE aux memes parametres restaure l'etat initial. Une case dont
# le cumul absolu retombe sous EPS_COUVERT est retiree du Dictionary (evite
# les zeros residuels de float qui polluent l'index).
#
# CE FICHIER NE CONNAIT AUCUN NOM DU MONDE : ni "arbre", ni "ombre", ni
# "spore", ni "broutage". Il expose des cases, un centre, un rayon en unites
# monde, une magnitude et un signe. Meme discipline que scripts/champ.gd
# (aucun phenomene nomme en dur) et scripts/facteur_variance.gd (mecanisme
# generique teste hors domaine).
#
# ---- CE QU'IL FAIT ----
# deposer(centre_x, centre_z, rayon_m, taille_case, magnitude, signe) :
#   convertit le rayon en cases par ceil(rayon_m / taille_case) au moment de
#   la pose (jamais stocke), parcourt le carre [-r, +r] x [-r, +r] autour de
#   la case centrale, applique en chaque case un apport = magnitude * signe *
#   (1 - d / rayon) ou d = max(|dx|, |dz|) (Chebyshev). Case au poids <= 0
#   (bord strict) skippee. Case dont le cumul absolu retombe sous EPS_COUVERT
#   retiree du Dictionary. Rayon 0 (rayon_m nul ou taille_case >= rayon_m) :
#   seule la case centrale recoit magnitude * signe.
#
# lire(x, z, taille_case) : rend le cumul de la case (x, z) en float. 0.0 si
#   la case n'a jamais recu de depot ou a ete nettoyee.
#
# nombre_cases() : rend le nombre de cases actuellement non nulles dans le
#   champ (utile pour un releve, jamais lu par la logique).
#
# ---- INVARIANTS ----
# - Symetrie signe : deposer(x, z, r, tc, m, +1) puis deposer(x, z, r, tc, m,
#   -1) rend un champ strictement identique a l'etat initial (aucune derive).
# - Cumul : deux depots aux memes parametres sont additifs -- chaque case
#   recoit 2 * m * (1 - d/r).
# - Independance a `taille_case` : la portee PHYSIQUE d'un depot est rayon_m
#   (unites monde). Changer `taille_case` ne deforme pas l'empreinte
#   physique, seule la finesse du quadrillage evolue.
#
# ---- OU LE STOCKER ----
# Un champ par population qui depose la meme grandeur (une instance
# ChampSaturation.new() detenue par le manager). Aucune donnee globale,
# aucun singleton : chaque appelant tient son champ, la vie du champ suit
# la vie du manager.
#
# PAS de class_name (doctrine) : preload("res://scripts/champ_saturation.gd").
#
# ECART FRAMEWORK : ce fichier n'existe pas dans le depot framework Orion,
# ajoute dans cette copie faute d'equivalent generique. Ni scripts/champ.gd
# (FORCE qui deplace, pas champ scalaire lisible) ni jeu/Outil de jeu/
# champ_spatial.gd (compte ENTIER +1/-1 UNIFORME, pas de decroissance ni
# de signe float) ne remplissent ce role. Meme geste doctrinal que
# scripts/monde.gd:retirer et scripts/facteur_variance.gd (precedents d'un
# ecart trace dans le fichier lui-meme). La fiche CARTE.md correspondante
# est un ajout a faire cote depot framework, pas ici (documents/ est
# lecture seule).

const EPS_COUVERT: float = 1.0e-6

var _champ: Dictionary = {}

func deposer(centre_x: float, centre_z: float, rayon_m: float, taille_case: float, magnitude: float, signe: int) -> void:
	if taille_case <= 0.0:
		return
	var mag: float = magnitude * float(signe)
	if mag == 0.0:
		return
	var rayon: int = 0
	if rayon_m > 0.0:
		rayon = int(ceil(rayon_m / taille_case))
	var cx0: int = floori(centre_x / taille_case)
	var cz0: int = floori(centre_z / taille_case)
	var dcx: int = -rayon
	while dcx <= rayon:
		var dcz: int = -rayon
		while dcz <= rayon:
			var d: int = maxi(absi(dcx), absi(dcz))
			var poids: float = 1.0
			if rayon > 0:
				poids = 1.0 - float(d) / float(rayon)
			if poids <= 0.0:
				dcz += 1
				continue
			var apport: float = mag * poids
			var cle: Vector2i = Vector2i(cx0 + dcx, cz0 + dcz)
			var v: float = float(_champ.get(cle, 0.0)) + apport
			if absf(v) < EPS_COUVERT:
				_champ.erase(cle)
			else:
				_champ[cle] = v
			dcz += 1
		dcx += 1

func lire(x: float, z: float, taille_case: float) -> float:
	if taille_case <= 0.0:
		return 0.0
	var cle: Vector2i = Vector2i(floori(x / taille_case), floori(z / taille_case))
	return float(_champ.get(cle, 0.0))

func nombre_cases() -> int:
	return _champ.size()
