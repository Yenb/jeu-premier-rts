# CHAMP DE SATURATION PLAT : variante ALLOCATION-REDUITE de
# `scripts/champ_saturation.gd`. Stockage `PackedFloat32Array` indexe
# par une grille BORNEE (`z * largeur + x`) au lieu de
# `Dictionary<Vector2i, float>` -- elimine le hash par case sur
# `redeposer_lot` / `deposer_lot` / `lire` / `lire_lot`, lookup et
# ecriture en O(1) direct.
#
# API IDENTIQUE a `ChampSaturation` (`deposer`, `deposer_lot`,
# `redeposer`, `redeposer_lot`, `lire`, `lire_lot`, `nombre_cases`),
# plus `configurer(x_min, z_min, x_max, z_max)` a appeler UNE fois
# avant tout depot. Sans configuration, la grille est vide (largeur =
# 0), tous les depots et lectures sont silencieusement inertes.
#
# ---- ECART FRAMEWORK ----
# Ce fichier n'existe pas dans le depot framework Orion, ajoute ici
# sous l'exception CLAUDE.md § Frontiere pour reduire le cout du
# champ scalaire sur le banc arbre (poste dominant au profileur :
# `redeposer_lot` sous Dictionary + hash Vector2i par case). Meme
# geste doctrinal que `scripts/monde.gd:retirer`,
# `scripts/champ_saturation.gd` et
# `scripts/monde.gd:choses_dans_rayons_brut`.
#
# ---- BORNES ET DEPOTS HORS EMPRISE ----
# La grille couvre les cases [`x_min`, `x_max`] x [`z_min`, `z_max`]
# en INDICES de case (pas en unites monde). Une case hors bornes est
# silencieusement skippee au depot (comme si son cumul restait 0).
# En lecture, elle rend `0.0`. Comportement equivalent a
# `ChampSaturation` (Dictionary) : hors bornes = case absente = 0.
#
# ---- LIMITE MEMOIRE ----
# Memoire = `largeur * hauteur * 4` octets, alloue au `configurer`.
# 601x601 (demi_carte=300 taille_case=1) = 1.4 Mo. 501x501
# (demi_carte=250) = 1.0 Mo. Une carte plus grande a `taille_case=1`
# (100 km2 = 400 Mo) doit soit augmenter taille_case soit rester sur
# `ChampSaturation` (Dictionary).
#
# ---- ORDRE DES OPERATIONS ----
# Meme sequence bit a bit que `ChampSaturation`, avec UNE variante :
# `1.0 - float(d) / float(rayon)` remplace par
# `1.0 - float(d) * inv_rayon` (pre-calc de l'inverse hors boucle
# interne). Pour `rayon` entier non nul, le resultat float peut
# differer de 1 ULP sur certaines valeurs (l'inversion 1.0/rayon puis
# multiplication n'est pas strictement egale a la division directe en
# IEEE 754). Test hors domaine tolere jusqu'a 1e-5 de difference par
# case cumulee.
#
# PAS de class_name (doctrine CLAUDE.md).

extends RefCounted

const EPS_COUVERT: float = 1.0e-6

var _valeurs: PackedFloat32Array = PackedFloat32Array()
var _n_non_nulles: int = 0
var _x_min: int = 0
var _z_min: int = 0
var _largeur: int = 0
var _hauteur: int = 0

# Configure les bornes de la grille en INDICES de case. L'appelant
# traduit `demi_carte / taille_case` en indices avant d'appeler. Reset
# le champ a zero. Bornes inclusives.
func configurer(x_min: int, z_min: int, x_max: int, z_max: int) -> void:
	_x_min = x_min
	_z_min = z_min
	_largeur = maxi(0, x_max - x_min + 1)
	_hauteur = maxi(0, z_max - z_min + 1)
	_valeurs.resize(_largeur * _hauteur)
	_valeurs.fill(0.0)
	_n_non_nulles = 0

func deposer(centre_x: float, centre_z: float, rayon_m: float, taille_case: float, magnitude: float, signe: int) -> void:
	if taille_case <= 0.0 or _largeur == 0:
		return
	var mag: float = magnitude * float(signe)
	if mag == 0.0:
		return
	var rayon: int = 0
	if rayon_m > 0.0:
		rayon = int(ceil(rayon_m / taille_case))
	var cx0: int = floori(centre_x / taille_case)
	var cz0: int = floori(centre_z / taille_case)
	var inv_rayon: float = 0.0
	if rayon > 0:
		inv_rayon = 1.0 / float(rayon)
	var dcx: int = -rayon
	while dcx <= rayon:
		var dcz: int = -rayon
		while dcz <= rayon:
			var d: int = maxi(absi(dcx), absi(dcz))
			var poids: float = 1.0
			if rayon > 0:
				poids = 1.0 - float(d) * inv_rayon
			if poids <= 0.0:
				dcz += 1
				continue
			var apport: float = mag * poids
			var cx: int = (cx0 + dcx) - _x_min
			var cz: int = (cz0 + dcz) - _z_min
			if cx >= 0 and cx < _largeur and cz >= 0 and cz < _hauteur:
				var idx: int = cz * _largeur + cx
				var ancien: float = float(_valeurs[idx])
				var v: float = ancien + apport
				var etait_non_nulle: bool = absf(ancien) >= EPS_COUVERT
				if absf(v) < EPS_COUVERT:
					_valeurs[idx] = 0.0
					if etait_non_nulle:
						_n_non_nulles -= 1
				else:
					_valeurs[idx] = v
					if not etait_non_nulle:
						_n_non_nulles += 1
			dcz += 1
		dcx += 1

func redeposer(centre_x: float, centre_z: float, ancien_rayon_m: float, nouveau_rayon_m: float, taille_case: float, ancienne_magnitude: float, nouvelle_magnitude: float) -> void:
	if taille_case <= 0.0 or _largeur == 0:
		return
	var rayon_ancien: int = 0
	if ancien_rayon_m > 0.0:
		rayon_ancien = int(ceil(ancien_rayon_m / taille_case))
	var rayon_nouveau: int = 0
	if nouveau_rayon_m > 0.0:
		rayon_nouveau = int(ceil(nouveau_rayon_m / taille_case))
	var rayon_max: int = maxi(rayon_ancien, rayon_nouveau)
	if ancienne_magnitude == 0.0 and nouvelle_magnitude == 0.0:
		return
	var cx0: int = floori(centre_x / taille_case)
	var cz0: int = floori(centre_z / taille_case)
	var inv_rayon_ancien: float = 0.0
	if rayon_ancien > 0:
		inv_rayon_ancien = 1.0 / float(rayon_ancien)
	var inv_rayon_nouveau: float = 0.0
	if rayon_nouveau > 0:
		inv_rayon_nouveau = 1.0 / float(rayon_nouveau)
	var dcx: int = -rayon_max
	while dcx <= rayon_max:
		var dcz: int = -rayon_max
		while dcz <= rayon_max:
			var d: int = maxi(absi(dcx), absi(dcz))
			var apport: float = 0.0
			if ancienne_magnitude != 0.0 and d <= rayon_ancien:
				var poids_a: float = 1.0
				if rayon_ancien > 0:
					poids_a = 1.0 - float(d) * inv_rayon_ancien
				if poids_a > 0.0:
					apport -= ancienne_magnitude * poids_a
			if nouvelle_magnitude != 0.0 and d <= rayon_nouveau:
				var poids_n: float = 1.0
				if rayon_nouveau > 0:
					poids_n = 1.0 - float(d) * inv_rayon_nouveau
				if poids_n > 0.0:
					apport += nouvelle_magnitude * poids_n
			if apport == 0.0:
				dcz += 1
				continue
			var cx: int = (cx0 + dcx) - _x_min
			var cz: int = (cz0 + dcz) - _z_min
			if cx >= 0 and cx < _largeur and cz >= 0 and cz < _hauteur:
				var idx: int = cz * _largeur + cx
				var ancien: float = float(_valeurs[idx])
				var v: float = ancien + apport
				var etait_non_nulle: bool = absf(ancien) >= EPS_COUVERT
				if absf(v) < EPS_COUVERT:
					_valeurs[idx] = 0.0
					if etait_non_nulle:
						_n_non_nulles -= 1
				else:
					_valeurs[idx] = v
					if not etait_non_nulle:
						_n_non_nulles += 1
			dcz += 1
		dcx += 1

func redeposer_lot(centres_x: PackedFloat32Array, centres_z: PackedFloat32Array, anciens_rayons_m: PackedFloat32Array, nouveaux_rayons_m: PackedFloat32Array, taille_case: float, anciennes_magnitudes: PackedFloat32Array, nouvelles_magnitudes: PackedFloat32Array) -> void:
	if taille_case <= 0.0 or _largeur == 0:
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
		var inv_rayon_ancien: float = 0.0
		if rayon_ancien > 0:
			inv_rayon_ancien = 1.0 / float(rayon_ancien)
		var inv_rayon_nouveau: float = 0.0
		if rayon_nouveau > 0:
			inv_rayon_nouveau = 1.0 / float(rayon_nouveau)
		var dcx: int = -rayon_max
		while dcx <= rayon_max:
			var dcz: int = -rayon_max
			while dcz <= rayon_max:
				var d: int = maxi(absi(dcx), absi(dcz))
				var apport: float = 0.0
				if ancienne_magnitude != 0.0 and d <= rayon_ancien:
					var poids_a: float = 1.0
					if rayon_ancien > 0:
						poids_a = 1.0 - float(d) * inv_rayon_ancien
					if poids_a > 0.0:
						apport -= ancienne_magnitude * poids_a
				if nouvelle_magnitude != 0.0 and d <= rayon_nouveau:
					var poids_n: float = 1.0
					if rayon_nouveau > 0:
						poids_n = 1.0 - float(d) * inv_rayon_nouveau
					if poids_n > 0.0:
						apport += nouvelle_magnitude * poids_n
				if apport == 0.0:
					dcz += 1
					continue
				var cx: int = (cx0 + dcx) - _x_min
				var cz: int = (cz0 + dcz) - _z_min
				if cx >= 0 and cx < _largeur and cz >= 0 and cz < _hauteur:
					var idx: int = cz * _largeur + cx
					var ancien: float = float(_valeurs[idx])
					var v: float = ancien + apport
					var etait_non_nulle: bool = absf(ancien) >= EPS_COUVERT
					if absf(v) < EPS_COUVERT:
						_valeurs[idx] = 0.0
						if etait_non_nulle:
							_n_non_nulles -= 1
					else:
						_valeurs[idx] = v
						if not etait_non_nulle:
							_n_non_nulles += 1
				dcz += 1
			dcx += 1

func deposer_lot(centres_x: PackedFloat32Array, centres_z: PackedFloat32Array, rayons_m: PackedFloat32Array, taille_case: float, magnitudes: PackedFloat32Array, signes: PackedByteArray) -> void:
	if taille_case <= 0.0 or _largeur == 0:
		return
	var n: int = centres_x.size()
	if n == 0:
		return
	var k: int = 0
	while k < n:
		var magnitude: float = magnitudes[k]
		var signe: int = 1 if signes[k] == 1 else -1
		var mag: float = magnitude * float(signe)
		if mag == 0.0:
			k += 1
			continue
		var rayon_m: float = rayons_m[k]
		var rayon: int = 0
		if rayon_m > 0.0:
			rayon = int(ceil(rayon_m / taille_case))
		var cx0: int = floori(centres_x[k] / taille_case)
		var cz0: int = floori(centres_z[k] / taille_case)
		k += 1
		var inv_rayon: float = 0.0
		if rayon > 0:
			inv_rayon = 1.0 / float(rayon)
		var dcx: int = -rayon
		while dcx <= rayon:
			var dcz: int = -rayon
			while dcz <= rayon:
				var d: int = maxi(absi(dcx), absi(dcz))
				var poids: float = 1.0
				if rayon > 0:
					poids = 1.0 - float(d) * inv_rayon
				if poids <= 0.0:
					dcz += 1
					continue
				var apport: float = mag * poids
				var cx: int = (cx0 + dcx) - _x_min
				var cz: int = (cz0 + dcz) - _z_min
				if cx >= 0 and cx < _largeur and cz >= 0 and cz < _hauteur:
					var idx: int = cz * _largeur + cx
					var ancien: float = float(_valeurs[idx])
					var v: float = ancien + apport
					var etait_non_nulle: bool = absf(ancien) >= EPS_COUVERT
					if absf(v) < EPS_COUVERT:
						_valeurs[idx] = 0.0
						if etait_non_nulle:
							_n_non_nulles -= 1
					else:
						_valeurs[idx] = v
						if not etait_non_nulle:
							_n_non_nulles += 1
				dcz += 1
			dcx += 1

func lire(x: float, z: float, taille_case: float) -> float:
	if taille_case <= 0.0 or _largeur == 0:
		return 0.0
	var cx: int = floori(x / taille_case) - _x_min
	var cz: int = floori(z / taille_case) - _z_min
	if cx < 0 or cx >= _largeur or cz < 0 or cz >= _hauteur:
		return 0.0
	return float(_valeurs[cz * _largeur + cx])

func lire_lot(positions_x: PackedFloat32Array, positions_z: PackedFloat32Array, taille_case: float) -> PackedFloat32Array:
	var n: int = positions_x.size()
	var out := PackedFloat32Array()
	out.resize(n)
	if taille_case <= 0.0 or _largeur == 0:
		return out
	var k: int = 0
	while k < n:
		var cx: int = floori(positions_x[k] / taille_case) - _x_min
		var cz: int = floori(positions_z[k] / taille_case) - _z_min
		if cx >= 0 and cx < _largeur and cz >= 0 and cz < _hauteur:
			out[k] = float(_valeurs[cz * _largeur + cx])
		k += 1
	return out

func nombre_cases() -> int:
	return _n_non_nulles
