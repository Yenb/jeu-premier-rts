extends Node

# CE QUI PEUPLE LA CARTE EN DONNEES, et rien d'autre. Il seme des objets dans un
# Monde, puis donne ce Monde au montreur qui les fera basculer en nœuds pres de
# l'observateur. Il ne rend rien, ne suit personne, et ne tourne qu'une fois.
#
# Entree : une carte, un semis (CLE DE TYPE -> combien), une graine de hasard, et
# le chemin du montreur. Sortie : un Monde peuple, pose sur le montreur.
#
# LE CONTENU ENTRE PAR LE SEMIS, jamais par ce fichier : les cles de type vivent
# dans la scene, a cote du catalogue de scenes que le montreur porte. Ajouter une
# sorte d'objet est une ligne de donnees, zero ligne de code.
#
# IL SEME EN DONNEES, PAS EN NŒUDS. Dix mille objets semes ne coutent aucun nœud
# tant que personne ne s'en approche -- c'est le montreur qui decide de ce qui
# existe a l'ecran, et son compte suit son rayon (voir objets_visibles.gd).
#
# LA POSITION VIENT DE LA CARTE, par le meme geste que le montreur : la colonne
# donne le sol, et une colonne sans sol ne recoit rien. Deux facons de placer un
# objet donneraient un objet enfonce ou flottant au moment de la bascule.
#
# LE HASARD EST SEEDE. Meme graine, meme semis : la carte se repeuple a
# l'identique d'un lancement a l'autre, ce qui rend un defaut de placement
# reproductible au lieu d'etre a rattraper au vol.
#
# LE CALCUL EST HORS DE _ready, tout entier dans une fonction statique : ce qui
# se verrouille sans arbre de scene est exactement ce qui decide de ce qui est
# seme.
#
# Regles tenues : positions en Vector3, jamais Vector2 -- une COLONNE est un
# Vector2i, un index et pas une position. Aucun hasard non seede. Aucun texte
# visible par le joueur. Aucun nom de contenu. Rien de scripts/, data/ ni
# documents/ n'est ecrit.

const Monde = preload("res://scripts/monde.gd")
const ObjetsVisibles = preload("res://jeu/objets/objets_visibles.gd")

# La carte qui dit ou est le sol. Sans elle, rien n'est seme.
@export var carte: Resource

# Le nœud qui montrera ce qui est seme. Sans lui, le Monde est peuple et
# personne ne le regarde -- ce qui n'est pas une panne, mais ne se voit pas.
@export var montreur: NodePath

# CLE DE TYPE -> COMBIEN. C'est ici que le contenu entre.
@export var semis: Dictionary = {}

@export var graine: int = 1

# Le Monde peuple. Garde ici parce que c'est ce fichier qui le construit ; le
# montreur ne fait que le lire.
var monde = null

func _ready() -> void:
	if carte == null:
		push_error("semer_objets sans carte : aucune colonne ou semer")
		return
	var choses := semer(carte, semis, graine)
	monde = Monde.new()
	for chose in choses:
		monde.ajouter(chose, String(chose["type"]), chose["position"])

	var vers := get_node_or_null(montreur)
	if vers == null:
		push_error("semer_objets ne trouve aucun montreur : rien ne montrera ce qui est seme")
		return
	vers.monde = monde
	print("semer_objets : %d objets semes en donnees, %d demandes" % [
		choses.size(), demandes(semis)])

# Combien d'objets le semis demande, toutes cles confondues.
static func demandes(demande: Dictionary) -> int:
	var total := 0
	for cle in demande:
		total += maxi(int(demande[cle]), 0)
	return total

# Les choses a semer : une liste de { id, type, colonne, position }.
#
# UNE COLONNE SANS SOL NE RECOIT RIEN, et le tirage n'est PAS rejoue pour la
# remplacer : un semis qui insiste jusqu'a atteindre son compte se mettrait a
# tourner sans fin sur une carte entierement creusee. Ce qui tombe dans le vide
# est perdu, et le compte rendu le dit.
#
# LES CLES SONT PARCOURUES DANS L'ORDRE DU DICTIONNAIRE, qui est celui de
# l'insertion : le semis est donc reproductible cle par cle, pas seulement dans
# son total.
static func semer(source: Resource, demande: Dictionary, graine: int) -> Array:
	var choses: Array = []
	var tirage := RandomNumberGenerator.new()
	tirage.seed = graine
	var demi: int = source.demi_cote
	var numero := 0
	for cle in demande:
		for i in range(maxi(int(demande[cle]), 0)):
			var colonne := Vector2i(
				tirage.randi_range(-demi, demi - 1),
				tirage.randi_range(-demi, demi - 1))
			var pose: Variant = ObjetsVisibles.position_posee(source, colonne)
			if pose == null:
				continue
			numero += 1
			choses.append({
				"id": numero,
				"type": cle,
				"colonne": colonne,
				"position": pose,
			})
	return choses
