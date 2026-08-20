extends SceneTree

# Lancement :
# godot --headless --script jeu/terrain/ecrire_carte_terrain.gd -- emprise=2500
# godot --headless --script jeu/terrain/ecrire_carte_terrain.gd -- emprise=2500 vers=res://jeu/terrain/autre.tres forcer
#
# OUTIL D'ECHAFAUDAGE, lance a la main. Il ECRIT un fichier et rend la main ; le
# jeu ne l'appelle jamais, rien ne le charge au demarrage. Son seul role : poser
# une carte VIERGE a l'emprise demandee, que la sculpture creuse ensuite.
#
# Entree : deux arguments utilisateur, « emprise=<demi-cote en cellules> » et
# « vers=<chemin> », plus « forcer ». Sortie : une ressource carte_terrain.gd.
# Code de sortie 0 sur VERT, 1 sur ROUGE.
#
# LE CHEMIN SE LIT PAR LE MEME GESTE QUE CHEZ generer_carte.gd, jamais une
# seconde facon de le dire -- generer_murs.gd fait deja ce meme emprunt.
#
# GARDE-FOU : sans « forcer », le script REFUSE d'ecrire si le fichier existe
# deja. Une carte deja sculptee ne vit que la, et la reecrire vierge effacerait
# tout le relief d'un coup.
#
# IL SE RELIT SUR LE DISQUE AVANT DE CONCLURE : le verdict porte sur le FICHIER
# RELU, jamais sur l'objet qui vient d'etre construit en memoire -- meme regle
# que generer_murs.gd.
#
# Regles tenues : aucun hasard. Les prints sont des traces de mise au point, pas
# du texte joueur. Rien de scripts/, data/ ni documents/ n'est lu ni ecrit.

const Generateur = preload("res://jeu/terrain/generer_carte.gd")
const CarteTerrain = preload("res://jeu/terrain/carte_terrain.gd")

const CHEMIN_DEFAUT := "res://jeu/terrain/carte_100km2.tres"
const PREFIXE_EMPRISE := "emprise="

# 2500 cellules de demi-cote a 2 m la cellule = 10 km de cote = 100 km².
const EMPRISE_DEFAUT := 2500

# La demi-emprise lue dans les arguments utilisateur, ou le defaut. Statique et
# pure : elle ne lit ni la ligne de commande ni le disque.
static func emprise_demandee(arguments: PackedStringArray, defaut: int) -> int:
	for argument in arguments:
		if argument.begins_with(PREFIXE_EMPRISE):
			var demande := argument.substr(PREFIXE_EMPRISE.length()).strip_edges()
			if demande.is_valid_int() and demande.to_int() > 0:
				return demande.to_int()
	return defaut

func _init() -> void:
	var arguments := OS.get_cmdline_user_args()
	var chemin := Generateur.chemin_demande(arguments, CHEMIN_DEFAUT)
	var demi_cote := emprise_demandee(arguments, EMPRISE_DEFAUT)

	if FileAccess.file_exists(chemin) and not arguments.has("forcer"):
		print("ROUGE: %s existe deja. La reecrire EFFACERAIT tout le relief sculpte." % chemin)
		print("       Relancer avec « -- forcer » si c'est bien ce qui est voulu.")
		quit(1)
		return

	var carte: Resource = CarteTerrain.new()
	carte.demi_cote = demi_cote
	var erreur := ResourceSaver.save(carte, chemin)
	if erreur != OK:
		print("ROUGE: ecriture de %s impossible (erreur %d)" % [chemin, erreur])
		quit(1)
		return

	var relue: Resource = load(chemin)
	if relue == null:
		print("ROUGE: %s ecrit mais illisible" % chemin)
		quit(1)
		return
	if relue.demi_cote != demi_cote:
		print("ROUGE: %s relu porte une emprise de %d, %d etait demande" % [
			chemin, relue.demi_cote, demi_cote])
		quit(1)
		return

	var octets := FileAccess.open(chemin, FileAccess.READ).get_length()
	print("Ecrit : %s" % chemin)
	print("  emprise %d cellules de demi-cote, %.0f m de cote, %.2f km²" % [
		relue.demi_cote, relue.metres(), relue.superficie_km2()])
	print("  %d colonnes, dont %d sculptees, sommet par defaut couche %d" % [
		relue.colonnes(), relue.colonnes_sculptees(), relue.sommet_de_base()])
	print("  %d octets sur le disque" % octets)
	print("VERT: carte vierge ecrite.")
	quit(0)
