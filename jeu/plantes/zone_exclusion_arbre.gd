# ZONE D'EXCLUSION POUR UN PEUPLEMENT (patron `jeu/plantes/`).
#
# Noeud Node3D pose dans l'EDITEUR par le designer, pas en jeu. Emprise
# ou aucune graine ne germe : menager des clairieres pour placer les
# agents, laisser respirer la foret autour d'un point d'interet.
#
# ---- ROLE ----
# Le noeud DECLARE une forme (cercle ou carre) autour de sa position
# monde (`global_position.x`, `global_position.z`) et s'ajoute au
# groupe `&"exclusion_arbre"` a `_ready`. Un peuplement (par exemple
# `jeu/bancs/banc_peuplement_arbre.gd` en mode hote) lit ce groupe une
# fois a son `_ready`, copie l'emprise en data (aucune reference
# vivante au noeud dans le hot path), et rejette d'office toute
# naissance dont la position tombe dans l'emprise -- avant meme le
# gate de couvert ou de trouee.
#
# COMME LES ZONES SONT POSEES AVANT LE LANCEMENT, aucune foret n'y a
# encore pousse : le mecanisme ne fait que BLOQUER la naissance dans
# l'emprise, il n'a AUCUN arbre existant a retirer.
#
# ---- ENTREES ----
# `forme` : 0 = cercle (`rayon`), 1 = carre (`demi_x`, `demi_z`). Le
#   designer edite l'entier dans l'inspecteur. Convention documentee
#   ici et dans le peuplement lecteur.
# `rayon` : rayon du cercle en unites monde (utilise si `forme`=0).
# `demi_x`, `demi_z` : demi-etendues du carre en X et Z, unites monde
#   (utilises si `forme`=1). Rectangulaire possible (demi_x != demi_z).
#
# La POSITION de la zone est celle du noeud dans la scene :
# `global_position.x` et `global_position.z`. Le noeud se deplace avec
# le gizmo dans la vue 3D de l'editeur, la zone suit.
#
# ---- SORTIE ----
# `contient(x, z) -> bool` : true si (x, z) MONDE tombe dans l'emprise.
# Utilise par le peuplement dans son gate de germination.
#
# ---- INSCRIPTION ----
# `add_to_group(&"exclusion_arbre")` au `_ready` (patron identique aux
# autres groupes de scene du depot, voir `banc_peuplement_arbre.gd`
# qui pose `add_to_group(&"observateur")` sur sa camera). Un peuplement
# lit tous les noeuds du groupe une fois -- aucune coordonnee en dur
# ni cote code ni cote JSON, tout vient de la position du noeud dans
# la scene.
#
# ---- LIMITE ACTUELLE ----
# Le peuplement teste chaque graine candidate contre CHAQUE zone
# lineairement. Pour une poignee de zones (< 10) et une centaine de
# graines par tick, cout negligeable. Au-dela, prevoir une indexation
# spatiale (patron `scripts/monde.gd`) -- pas necessaire pour l'usage
# de depart (menager quelques clairieres autour des agents).
#
# PAS de class_name (doctrine CLAUDE.md).

extends Node3D

const FORME_CERCLE: int = 0
const FORME_CARRE: int = 1

# 0 = cercle (`rayon`), 1 = carre (`demi_x`, `demi_z`).
@export var forme: int = FORME_CERCLE
# Rayon du cercle, en unites monde (ignore si `forme`=1).
@export var rayon: float = 10.0
# Demi-etendues du carre en X et Z, en unites monde (ignorees si
# `forme`=0). Rectangulaire possible (demi_x != demi_z).
@export var demi_x: float = 10.0
@export var demi_z: float = 10.0

func _ready() -> void:
	add_to_group(&"exclusion_arbre")

# Rend true si (x, z) MONDE tombe dans l'emprise de la zone. Delegue
# a `contient_avec_centre` en passant `global_position.xz` --
# separation qui rend la logique testable hors scene (le test appelle
# `contient_avec_centre` directement, sans avoir besoin d'inserer le
# noeud dans un tree pour que `global_position` soit valide).
func contient(x: float, z: float) -> bool:
	return contient_avec_centre(global_position.x, global_position.z, x, z)

# Predicat pur, sans dependance a `global_position` : le centre (cx,
# cz) est passe en argument. Cercle : distance carree <= rayon carre
# (evite la racine). Carre : ecart absolu en X et Z sous les
# demi-etendues.
func contient_avec_centre(cx: float, cz: float, x: float, z: float) -> bool:
	var dx: float = x - cx
	var dz: float = z - cz
	if forme == FORME_CERCLE:
		return dx * dx + dz * dz <= rayon * rayon
	return absf(dx) <= demi_x and absf(dz) <= demi_z
