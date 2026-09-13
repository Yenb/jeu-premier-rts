# ZONE D'EXCLUSION POUR UN PEUPLEMENT (patron `jeu/plantes/`).
#
# Noeud MeshInstance3D pose dans l'EDITEUR par le designer, pas en jeu.
# Emprise ou aucune graine ne germe : menager des clairieres pour placer
# les agents, laisser respirer la foret autour d'un point d'interet.
#
# ---- VISUEL DANS L'EDITEUR ----
# `@tool` : le script s'execute aussi dans l'editeur, meme patron que
# `jeu/Proto/arbre_seul.gd`. Le noeud AFFICHE un mesh transparent
# (CylinderMesh plat pour cercle, BoxMesh plat pour carre) aux
# dimensions courantes -- visuel comparable aux `ZoneSpawn` jaunes de
# `verification.tscn`. Les setters de forme/rayon/demi_x/demi_z
# reconstruisent le mesh -> le designer voit la zone changer en temps
# reel quand il edite les @export dans l'inspecteur.
#
# ---- ROLE ----
# Le noeud DECLARE une forme (cercle ou carre) autour de sa position
# monde (`global_position.x`, `global_position.z`) et s'ajoute au
# groupe `&"exclusion_arbre"` a `_ready` (uniquement en runtime, gate
# `not Engine.is_editor_hint()` pour ne pas polluer l'editeur). Un
# peuplement (par exemple `jeu/bancs/banc_peuplement_arbre.gd` en mode
# hote) lit ce groupe une fois a son `_ready`, copie l'emprise en data
# (aucune reference vivante au noeud dans le hot path), et rejette
# d'office toute naissance dont la position tombe dans l'emprise --
# avant meme le gate de couvert ou de trouee.
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
# le gizmo dans la vue 3D de l'editeur, la zone suit visuellement ET
# logiquement.
#
# ---- SORTIE ----
# `contient(x, z) -> bool` : true si (x, z) MONDE tombe dans l'emprise.
# `contient_avec_centre(cx, cz, x, z) -> bool` : predicat pur sans
# dependance a la scene, testable hors tree.
#
# ---- INSCRIPTION ----
# `add_to_group(&"exclusion_arbre")` au `_ready` (patron identique aux
# autres groupes de scene du depot, voir `banc_peuplement_arbre.gd`
# qui pose `add_to_group(&"observateur")` sur sa camera). Un peuplement
# lit tous les noeuds du groupe une fois -- aucune coordonnee en dur
# ni cote code ni cote JSON, tout vient de la position du noeud dans
# la scene. Gate `Engine.is_editor_hint()` : pas d'inscription en
# editeur, uniquement au runtime.
#
# ---- LIMITE ACTUELLE ----
# Le peuplement teste chaque graine candidate contre CHAQUE zone
# lineairement. Pour une poignee de zones (< 10) et une centaine de
# graines par tick, cout negligeable. Au-dela, prevoir une indexation
# spatiale (patron `scripts/monde.gd`) -- pas necessaire pour l'usage
# de depart (menager quelques clairieres autour des agents).
#
# PAS de class_name (doctrine CLAUDE.md).

@tool
extends MeshInstance3D

const FORME_CERCLE: int = 0
const FORME_CARRE: int = 1

# Hauteur du mesh visuel (dalle plate). La forme etale l'empreinte au
# sol, la hauteur ne borne rien de la logique.
const HAUTEUR_VISUEL: float = 0.4
# Couleur du mesh transparent (rouge translucide, distincte des
# `ZoneSpawn` jaunes de `verification.tscn`).
const COULEUR_VISUEL: Color = Color(0.9, 0.2, 0.2, 0.35)

# 0 = cercle (`rayon`), 1 = carre (`demi_x`, `demi_z`).
@export var forme: int = FORME_CERCLE:
	set(v):
		forme = v
		_reconstruire_mesh()
# Rayon du cercle, en unites monde (ignore si `forme`=1).
@export var rayon: float = 10.0:
	set(v):
		rayon = v
		_reconstruire_mesh()
# Demi-etendues du carre en X et Z, en unites monde (ignorees si
# `forme`=0). Rectangulaire possible (demi_x != demi_z).
@export var demi_x: float = 10.0:
	set(v):
		demi_x = v
		_reconstruire_mesh()
@export var demi_z: float = 10.0:
	set(v):
		demi_z = v
		_reconstruire_mesh()

func _ready() -> void:
	if Engine.is_editor_hint():
		# EDITEUR : reconstruit la dalle transparente pour que le
		# designer VOIE l'emprise. Aucune inscription au groupe (pas de
		# peuplement qui tourne en editeur).
		_reconstruire_mesh()
	else:
		# JEU : la zone est un outil d'edition -- invisible au joueur.
		# Aucun mesh a poser, `contient()` lit forme + dimensions +
		# global_position (aucune dependance au mesh).
		visible = false
		add_to_group(&"exclusion_arbre")

# Rebati le mesh selon `forme` et les dimensions courantes. Patron
# identique a `jeu/Proto/arbre_seul.gd:_reconstruire`.
func _reconstruire_mesh() -> void:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = COULEUR_VISUEL
	if forme == FORME_CERCLE:
		var cyl := CylinderMesh.new()
		cyl.top_radius = maxf(0.001, rayon)
		cyl.bottom_radius = maxf(0.001, rayon)
		cyl.height = HAUTEUR_VISUEL
		cyl.material = mat
		mesh = cyl
	else:
		var box := BoxMesh.new()
		box.size = Vector3(maxf(0.001, demi_x * 2.0), HAUTEUR_VISUEL, maxf(0.001, demi_z * 2.0))
		box.material = mat
		mesh = box

# Rend true si (x, z) MONDE tombe dans l'emprise de la zone. Delegue
# a `contient_avec_centre` en passant `global_position.xz` --
# separation qui rend la logique testable hors scene.
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
