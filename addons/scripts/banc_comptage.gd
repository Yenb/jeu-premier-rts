extends Node2D

# Cablage de banc VISUEL, separe des autres bancs (Scene/banc_comptage.tscn,
# PAS la scene principale -- run/main_scene reste banc_p1). Existe pour VOIR
# scripts/comptage.gd (ferme et prouve hors domaine par test_comptage.gd,
# voir CARTE.md §2) recevoir son PREMIER CABLAGE REEL -- premiere brique de
# la couche lecteur (docs/design.md, "Les collectifs n'existent pas") jouant
# en jeu pour la premiere fois. JETABLE PAR DEFINITION.
#
# CE QUE CE BANC MONTRE : six lucioles independantes ({ id, position,
# proprietes: {} }), disposees en cercle, dont l'etat bascule au hasard (RNG
# SEEDE -- data/banc_comptage.json:seed, jamais de hasard non seede, voir
# CLAUDE.md) a chaque tick. Un compteur textuel affiche combien luisent EN
# CE MOMENT (Comptage.compter sur la liste des six lucioles, regle_id
# "poissons_luisants" -- deja dans data/comptages.json, mode "presente" sur
# la cle "luit", aucun enrichissement). Une seconde ligne affiche la MOYENNE
# GLISSANTE du compte sur les data/banc_comptage.json:fenetre_moyenne
# derniers ticks -- calculee ICI, jamais dans comptage.gd, qui reste un
# mecanisme pur sans notion de temps ni d'historique.
#
# "luit" EST POSEE (proprietes["luit"] = true) OU RETIREE (proprietes.erase),
# JAMAIS mise a false et laissee presente -- meme convention que design.md,
# "Extinction = retrait de propriete, pas mutation de type". Necessaire ici :
# le mode "presente" de comptage.gd teste .has(propriete), jamais la VALEUR
# -- un booleen "luit" en permanence present (true/false) rendrait le compte
# fige a 6/6 en toute circonstance, contredisant le but meme du banc.
#
# HORS DOMAINE STRICT (portee volontairement limitee) : ce fichier ne
# connait ni colon, ni contenu du jeu Orion -- une luciole n'est qu'un
# Dictionary { id, position, proprietes: { luit } } comme dans
# test_comptage.gd. Il ne nomme ni "groupe" ni aucun mot d'agregat pour les
# six lucioles : le compteur affiche n'est PAS une propriete d'un
# objet-agregat, c'est un CALCUL, refait a chaque tick a partir des six
# lucioles individuelles, par Comptage.compter -- exactement la doctrine
# "Les collectifs n'existent pas" appliquee en jeu pour la premiere fois.
# Ce banc prouve le CABLAGE de comptage.gd, pas une croyance collective
# reelle sur des colons -- celle-ci viendra plus tard, avec un banc separe,
# quand la couche lecteur aura mûri (voir docs/prototypes.md).
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge data/banc_comptage.json et
#   data/comptages.json, seede le RNG, construit les six lucioles. _process
#   appelle _appliquer_bascules(...) puis Comptage.compter(...), met a jour
#   l'historique et redessine (couleurs des carres, texte des deux labels).
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_comptage.gd) : _appliquer_bascules(lucioles, rng, seuil) --
#   mute la liste en place selon les tirages du RNG recu, rend les ids
#   bascules ce tick ; _moyenne_glissante(historique) -- moyenne arithmetique
#   d'un Array de comptes, 0.0 si vide. _process appelle ces fonctions PUIS
#   rafraichit l'affichage, jamais l'inverse (voir CLAUDE.md, "Regle
#   d'etat").

const Comptage = preload("res://scripts/comptage.gd")

const TAILLE_CARRE := 24.0

var _rng := RandomNumberGenerator.new()
var _lucioles: Array = []
var _seuil_bascule := 0.0
var _fenetre_moyenne := 60
var _regle_id := ""
var _catalogue_comptages: Dictionary = {}
var _historique_comptes: Array = []
var _couleur_luit := Color.WHITE
var _couleur_eteinte := Color.GRAY
var _noeuds: Dictionary = {}
var _label_compte: Label
var _label_moyenne: Label

func _ready() -> void:
	var donnees := _charger_json("res://data/banc_comptage.json")
	_catalogue_comptages = _charger_json("res://data/comptages.json")
	_regle_id = donnees.get("comptage_ref", "")
	_seuil_bascule = donnees.get("seuil_bascule", 0.0)
	_fenetre_moyenne = int(donnees.get("fenetre_moyenne", 60))
	_rng.seed = int(donnees.get("seed", 0))

	var rgb_luit: Array = donnees.get("couleur_luit", [1.0, 1.0, 0.0])
	var rgb_eteinte: Array = donnees.get("couleur_eteinte", [0.4, 0.4, 0.4])
	_couleur_luit = Color(rgb_luit[0], rgb_luit[1], rgb_luit[2])
	_couleur_eteinte = Color(rgb_eteinte[0], rgb_eteinte[1], rgb_eteinte[2])

	var positions: Array = donnees.get("positions", [])
	for i in positions.size():
		var pos: Dictionary = positions[i]
		var id := "luciole_%d" % i
		var position3 := Vector3(pos.get("x", 0.0), pos.get("y", 0.0), pos.get("z", 0.0))
		_lucioles.append({"id": id, "position": position3, "proprietes": {}})
		_noeuds[id] = _dessiner_carre(position3, _couleur_eteinte)

	_label_compte = _dessiner_label(Vector2(20.0, 20.0))
	_label_moyenne = _dessiner_label(Vector2(20.0, 44.0))
	_rafraichir_affichage(0, 0.0)

func _process(_delta: float) -> void:
	_appliquer_bascules(_lucioles, _rng, _seuil_bascule)
	var compte := Comptage.compter(_lucioles, _regle_id, _catalogue_comptages)
	_historique_comptes.append(compte)
	if _historique_comptes.size() > _fenetre_moyenne:
		_historique_comptes.pop_front()
	_rafraichir_affichage(compte, _moyenne_glissante(_historique_comptes))

# Mute `lucioles` en place : pour chaque luciole, un tirage rng.randf() sous
# `seuil` bascule sa propriete "luit" -- POSEE (true) si absente, RETIREE si
# presente, jamais mise a false et laissee presente (voir en-tete : le mode
# "presente" de comptage.gd teste la cle, pas la valeur). Rend les ids des
# lucioles basculees ce tick. Aucun hasard non seede : le generateur est
# recu en parametre, jamais instancie ici (voir CLAUDE.md).
static func _appliquer_bascules(lucioles: Array, rng: RandomNumberGenerator, seuil: float) -> Array:
	var bascules: Array = []
	for luciole in lucioles:
		if rng.randf() < seuil:
			if luciole.proprietes.has("luit"):
				luciole.proprietes.erase("luit")
			else:
				luciole.proprietes["luit"] = true
			bascules.append(luciole.id)
	return bascules

# Moyenne arithmetique d'un Array de comptes (int/float). 0.0 sur un
# historique vide, point neutre legitime -- aucune alarme, ce n'est pas une
# reference de catalogue.
static func _moyenne_glissante(historique: Array) -> float:
	if historique.is_empty():
		return 0.0
	var somme := 0.0
	for compte in historique:
		somme += compte
	return somme / historique.size()

func _dessiner_carre(position3: Vector3, couleur: Color) -> ColorRect:
	var carre := ColorRect.new()
	carre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	carre.size = Vector2(TAILLE_CARRE, TAILLE_CARRE)
	carre.color = couleur
	carre.position = Vector2(position3.x, position3.y) - carre.size / 2.0
	add_child(carre)
	return carre

func _dessiner_label(position2: Vector2) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.position = position2
	add_child(label)
	return label

func _rafraichir_affichage(compte: int, moyenne: float) -> void:
	for luciole in _lucioles:
		var carre: ColorRect = _noeuds[luciole.id]
		carre.color = _couleur_luit if luciole.proprietes.has("luit") else _couleur_eteinte
	_label_compte.text = "%d / %d luisent" % [compte, _lucioles.size()]
	_label_moyenne.text = "compte moyen sur les %d derniers ticks : %.1f" % [_fenetre_moyenne, moyenne]

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
