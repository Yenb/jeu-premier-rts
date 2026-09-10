extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_attente_seuil.gd
#
# Verrouille scripts/attente_seuil.gd (mecanisme du coeur "attente sur seuil
# lu a la position"). ENTIEREMENT HORS DOMAINE : aucun catalogue reel n'est
# lu, aucun mot de contenu du jeu n'apparait -- prospects portant un suffixe
# neutre "_zork", champ scalaire fictif indexe par position. Si le mecanisme
# marche ici sur des nombres nus, il marche sur n'importe quel domaine.
#
# Couvre : ajouter enregistre et rend un index ; ajouter refuse une entree
# sans position ou avec position mal typee ; avancer au_dessus / en_dessous
# (deux sens, strict au seuil) ; le registre est INCHANGE apres avancer
# (aucune fabrication, aucun retrait automatique) ; donnees libres opaques
# transportees telles quelles dans le retour ; retirer(index) diminue le
# registre ; reversibilite (une meme entree devient realisable puis cesse
# de l'etre selon la valeur lue changeante) ; sens inconnu rend [].

const AttenteSeuil = preload("res://scripts/attente_seuil.gd")
const Verif = preload("res://scripts/verif.gd")

# Champ scalaire fictif : dictionnaire position -> valeur, lu par le Callable
# passe a avancer(). Le Callable est le SEUL pont entre le mecanisme et le
# champ : le mecanisme ne lit jamais ce champ directement.
var _champ_zork: Dictionary = {}


func _initialize() -> void:
	var verif := Verif.new()

	# --- Cas 1 : ajouter enregistre, rend un index croissant ---
	var registre := AttenteSeuil.new()
	var i0 := registre.ajouter({ "position": Vector3(0, 0, 0), "poids_zork": 1.0 })
	var i1 := registre.ajouter({ "position": Vector3(1, 0, 0), "poids_zork": 2.0 })
	var i2 := registre.ajouter({ "position": Vector3(2, 0, 0), "poids_zork": 3.0 })
	verif.v(i0 == 0 and i1 == 1 and i2 == 2, "indices attendus 0/1/2, obtenus %d/%d/%d" % [i0, i1, i2])
	verif.v(registre.nombre() == 3, "nombre attendu 3, obtenu %d" % registre.nombre())

	# --- Cas 2 : ajouter refuse une entree sans position ---
	var registre_garde := AttenteSeuil.new()
	var mauvais := registre_garde.ajouter({ "poids_zork": 42.0 })
	verif.v(mauvais == -1, "ajouter sans position doit rendre -1, obtenu %d" % mauvais)
	verif.v(registre_garde.nombre() == 0, "registre inchange apres ajout invalide, nombre=%d" % registre_garde.nombre())

	# --- Cas 3 : ajouter refuse position pas Vector3 ---
	var mauvais_type := registre_garde.ajouter({ "position": Vector2(0, 0) })
	verif.v(mauvais_type == -1, "ajouter position Vector2 doit rendre -1, obtenu %d" % mauvais_type)
	verif.v(registre_garde.nombre() == 0, "registre inchange apres position mal typee, nombre=%d" % registre_garde.nombre())

	# --- Cas 4 : avancer au_dessus, comparaison stricte ---
	# Champ : (0,0,0) -> 5.0, (1,0,0) -> 10.0, (2,0,0) -> 15.0. Seuil 10.0.
	# Seule (2,0,0) doit etre realisable (strict, > 10 pas >= 10).
	_champ_zork = {
		Vector3(0, 0, 0): 5.0,
		Vector3(1, 0, 0): 10.0,
		Vector3(2, 0, 0): 15.0,
	}
	var realisables := registre.avancer(Callable(self, "_lire_champ_zork"), 10.0, "au_dessus")
	verif.v(realisables.size() == 1, "au_dessus attendu 1 realisable, obtenu %d" % realisables.size())
	verif.v(realisables[0].index == 2, "index realisable attendu 2, obtenu %d" % realisables[0].index)
	verif.v(realisables[0].valeur == 15.0, "valeur realisable attendue 15.0, obtenue %f" % realisables[0].valeur)
	verif.v(realisables[0].entree.poids_zork == 3.0, "donnee libre poids_zork transportee, obtenue %f" % realisables[0].entree.poids_zork)

	# --- Cas 5 : le registre est INCHANGE apres avancer ---
	verif.v(registre.nombre() == 3, "registre inchange apres avancer, nombre=%d" % registre.nombre())

	# --- Cas 6 : avancer en_dessous, comparaison stricte ---
	# Meme champ, seuil 10.0. Seule (0,0,0) < 10.
	var realisables_bas := registre.avancer(Callable(self, "_lire_champ_zork"), 10.0, "en_dessous")
	verif.v(realisables_bas.size() == 1, "en_dessous attendu 1 realisable, obtenu %d" % realisables_bas.size())
	verif.v(realisables_bas[0].index == 0, "index realisable attendu 0, obtenu %d" % realisables_bas[0].index)
	verif.v(realisables_bas[0].valeur == 5.0, "valeur realisable attendue 5.0, obtenue %f" % realisables_bas[0].valeur)

	# --- Cas 7 : REVERSIBILITE (le champ change, l'entree devient puis cesse
	# d'etre realisable, sans aucune mutation du registre entre les deux) ---
	# Baisser la valeur en (2,0,0) sous le seuil ; l'entree qui etait
	# realisable au cas 4 ne l'est plus.
	_champ_zork[Vector3(2, 0, 0)] = 8.0
	var apres_baisse := registre.avancer(Callable(self, "_lire_champ_zork"), 10.0, "au_dessus")
	verif.v(apres_baisse.size() == 0, "aucun realisable apres baisse, obtenu %d" % apres_baisse.size())
	# Puis remonter, l'entree redevient realisable.
	_champ_zork[Vector3(2, 0, 0)] = 20.0
	var apres_montee := registre.avancer(Callable(self, "_lire_champ_zork"), 10.0, "au_dessus")
	verif.v(apres_montee.size() == 1, "un realisable apres remontee, obtenu %d" % apres_montee.size())
	verif.v(apres_montee[0].index == 2, "meme index 2 apres remontee, obtenu %d" % apres_montee[0].index)

	# --- Cas 8 : retirer diminue le registre ---
	registre.retirer(0)
	verif.v(registre.nombre() == 2, "nombre attendu 2 apres retrait, obtenu %d" % registre.nombre())

	# --- Cas 9 : sens inconnu rend [] ---
	var vide := registre.avancer(Callable(self, "_lire_champ_zork"), 10.0, "sens_zork_inconnu")
	verif.v(vide.size() == 0, "sens inconnu doit rendre [], obtenu taille %d" % vide.size())

	# --- Cas 10 : le retour est une copie -- muter le dict rendu n'affecte
	# pas le registre. ---
	_champ_zork = {
		Vector3(1, 0, 0): 100.0,
		Vector3(2, 0, 0): 100.0,
	}
	var copie := registre.avancer(Callable(self, "_lire_champ_zork"), 10.0, "au_dessus")
	verif.v(copie.size() == 2, "attendu 2 realisables au cas 10, obtenu %d" % copie.size())
	copie[0].entree.poids_zork = -999.0
	var lu_reel: Array = registre.prospects()
	verif.v(lu_reel[0].poids_zork != -999.0, "prospect interne intact apres mutation du retour, obtenu %f" % lu_reel[0].poids_zork)

	if verif.echecs() > 0:
		push_error("test_attente_seuil : %d echec(s)" % verif.echecs())
		quit(1)
	else:
		print("test_attente_seuil : OK")
		quit(0)


func _lire_champ_zork(position: Vector3) -> float:
	return float(_champ_zork.get(position, 0.0))
