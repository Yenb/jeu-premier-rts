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
# redeposer(centre_x, centre_z, ancien_rayon_m, nouveau_rayon_m, taille_case,
#   ancienne_magnitude, nouvelle_magnitude) : applique en UNE PASSE le retrait
#   de l'empreinte ancienne (signe -1) et le depot de la nouvelle (signe +1)
#   sur les cases de l'union des deux empreintes. Bit a bit equivalent a
#   deposer(..., ancienne, -1) puis deposer(..., nouvelle, +1). Utile quand
#   un centre change de magnitude ou de rayon sans bouger de position.
#
# redeposer_lot(centres_x, centres_z, anciens_rayons_m, nouveaux_rayons_m,
#   taille_case, anciennes_magnitudes, nouvelles_magnitudes) : applique en
#   UN appel un lot de N transitions (PackedFloat32Array paralleles).
#   Meme resultat exact que N appels a `redeposer` dans le meme ordre.
#   Reduit les franchissements de frontiere quand un manager de population
#   a beaucoup de transitions par tick.
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

# TRANSITION EN UNE PASSE : applique en un seul balayage le retrait de
# l'empreinte ANCIENNE (signe -1, ancienne_magnitude, ancien_rayon_m) et
# le depot de la NOUVELLE (signe +1, nouvelle_magnitude, nouveau_rayon_m).
# Invariant strict : appeler redeposer(A -> B) est equivalent a deposer(A,
# signe -1) puis deposer(B, signe +1) sur chaque case (le cumul par case
# est la SOMME des deux apports, la boucle iteration/erase par case garde
# la meme relation d'ordre). Le carre balaye a pour rayon
# max(rayon_ancien_cases, rayon_nouveau_cases) : une case hors de la
# petite empreinte a un poids nul cote empreinte concernee, seule l'autre
# contribue. Aucun autre effet de bord : deux appels a deposer restent
# valides pour les cas ou l'ancien ou le nouveau depot n'existe pas
# (naissance, mort).
func redeposer(centre_x: float, centre_z: float, ancien_rayon_m: float, nouveau_rayon_m: float, taille_case: float, ancienne_magnitude: float, nouvelle_magnitude: float) -> void:
	if taille_case <= 0.0:
		return
	var rayon_ancien: int = 0
	if ancien_rayon_m > 0.0:
		rayon_ancien = int(ceil(ancien_rayon_m / taille_case))
	var rayon_nouveau: int = 0
	if nouveau_rayon_m > 0.0:
		rayon_nouveau = int(ceil(nouveau_rayon_m / taille_case))
	var rayon_max: int = maxi(rayon_ancien, rayon_nouveau)
	# Rien a poser ni a retirer : chemin degrade des deux magnitudes nulles.
	if ancienne_magnitude == 0.0 and nouvelle_magnitude == 0.0:
		return
	var cx0: int = floori(centre_x / taille_case)
	var cz0: int = floori(centre_z / taille_case)
	var dcx: int = -rayon_max
	while dcx <= rayon_max:
		var dcz: int = -rayon_max
		while dcz <= rayon_max:
			var d: int = maxi(absi(dcx), absi(dcz))
			# Contribution retrait (empreinte ancienne).
			var apport: float = 0.0
			if ancienne_magnitude != 0.0 and d <= rayon_ancien:
				var poids_a: float = 1.0
				if rayon_ancien > 0:
					poids_a = 1.0 - float(d) / float(rayon_ancien)
				if poids_a > 0.0:
					apport -= ancienne_magnitude * poids_a
			# Contribution depot (empreinte nouvelle).
			if nouvelle_magnitude != 0.0 and d <= rayon_nouveau:
				var poids_n: float = 1.0
				if rayon_nouveau > 0:
					poids_n = 1.0 - float(d) / float(rayon_nouveau)
				if poids_n > 0.0:
					apport += nouvelle_magnitude * poids_n
			if apport == 0.0:
				dcz += 1
				continue
			var cle: Vector2i = Vector2i(cx0 + dcx, cz0 + dcz)
			var v: float = float(_champ.get(cle, 0.0)) + apport
			if absf(v) < EPS_COUVERT:
				_champ.erase(cle)
			else:
				_champ[cle] = v
			dcz += 1
		dcx += 1

# LOT DE TRANSITIONS en UNE passe : applique N transitions sur des
# colonnes paralleles (PackedFloat32Array). Ordre = ordre d'insertion.
# Meme resultat exact que N appels a `redeposer` dans le meme ordre.
# Toutes les colonnes doivent avoir la meme taille ; taille_case commun
# a tout le lot.
#
# LOGIQUE INLINE : le corps de `redeposer` est reproduit ici pour retirer
# l'appel par transition (~N franchissements de frontiere internes
# elimines par tick). `redeposer` reste utilisee ailleurs (test d'oracle,
# appels manager hors boucle) -- duplication assumee, meme discipline
# que le miroir C++ des fonctions chaudes d'index_spatial.
func redeposer_lot(centres_x: PackedFloat32Array, centres_z: PackedFloat32Array, anciens_rayons_m: PackedFloat32Array, nouveaux_rayons_m: PackedFloat32Array, taille_case: float, anciennes_magnitudes: PackedFloat32Array, nouvelles_magnitudes: PackedFloat32Array) -> void:
	if taille_case <= 0.0:
		return
	var n: int = centres_x.size()
	if n == 0:
		return
	var k: int = 0
	while k < n:
		var ancienne_magnitude: float = anciennes_magnitudes[k]
		var nouvelle_magnitude: float = nouvelles_magnitudes[k]
		if ancienne_magnitude == 0.0 and nouvelle_magnitude == 0.0:
			k += 1
			continue
		var ancien_rayon_m: float = anciens_rayons_m[k]
		var nouveau_rayon_m: float = nouveaux_rayons_m[k]
		var rayon_ancien: int = 0
		if ancien_rayon_m > 0.0:
			rayon_ancien = int(ceil(ancien_rayon_m / taille_case))
		var rayon_nouveau: int = 0
		if nouveau_rayon_m > 0.0:
			rayon_nouveau = int(ceil(nouveau_rayon_m / taille_case))
		var rayon_max: int = maxi(rayon_ancien, rayon_nouveau)
		var cx0: int = floori(centres_x[k] / taille_case)
		var cz0: int = floori(centres_z[k] / taille_case)
		k += 1
		var dcx: int = -rayon_max
		while dcx <= rayon_max:
			var dcz: int = -rayon_max
			while dcz <= rayon_max:
				var d: int = maxi(absi(dcx), absi(dcz))
				var apport: float = 0.0
				if ancienne_magnitude != 0.0 and d <= rayon_ancien:
					var poids_a: float = 1.0
					if rayon_ancien > 0:
						poids_a = 1.0 - float(d) / float(rayon_ancien)
					if poids_a > 0.0:
						apport -= ancienne_magnitude * poids_a
				if nouvelle_magnitude != 0.0 and d <= rayon_nouveau:
					var poids_n: float = 1.0
					if rayon_nouveau > 0:
						poids_n = 1.0 - float(d) / float(rayon_nouveau)
					if poids_n > 0.0:
						apport += nouvelle_magnitude * poids_n
				if apport == 0.0:
					dcz += 1
					continue
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
