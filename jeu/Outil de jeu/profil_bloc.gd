extends Resource

# BANC "test_ennemi2 Mother box" -- PROFIL DE BLOC. Un profil par couleur
# de bloc du MeshLibrary. Editable a l'inspecteur (Resource Godot). Le
# `nom_item` doit MATCHER exactement le nom de l'item dans le MeshLibrary
# (voir `jeu/terrain/bloc.tres`) -- c'est par ce nom que
# ressources_terrain.gd retrouve le bon profil au demarrage.
#
# REGENERATION : `quantite_regen` unites tous les `duree_regen_secondes`.
# Exemple : quantite_regen=2, duree_regen_secondes=60 -> +2 unites toutes
# les 60 secondes. La regeneration se produit UNIQUEMENT si rien ne couvre
# la case (voir ressources_terrain.gd).
#
# AJOUTER UNE VALEUR : suffit d'ecrire ici un `@export` supplementaire.
# Il apparait automatiquement dans l'inspecteur de TOUS les fichiers
# `.tres` derives de ce script.

@export var nom_item: String = ""
@export var reserve: int = 0
@export var quantite_regen: int = 0
@export var duree_regen_secondes: float = 60.0
# PRELEVABLE : le joueur peut-il RETIRER de la reserve en cliquant (extraction) ?
# Defaut true : un bloc profile se collecte (bloc_bleu = nourriture). false pour
# une reserve qui est une PROPRIETE DU SOL lue par d'autres (la fertilite du bloc
# bêché), jamais recoltee au clic. Gate arithmetique dans ressources_terrain
# :preleve, aucune categorie nommee (doctrine ADN).
@export var prelevable: bool = true
# TYPE D'EFFONDREMENT quand un sous-cube casse :
# - "structurel" (defaut) : cassure LOCALE, seul le sous-cube touche tombe,
#   le reste du bloc tient. Murs, fortifications, pierre.
# - "meuble" : cassure -> CASCADE, tous les sous-cubes du bloc se detachent
#   en meme temps. Terre, sable, gravats.
@export var type_effondrement: String = "structurel"
# ANGLE DE REPOS pour les sous-cubes LIBRES de cette matiere (tas empiles).
# Ecart de hauteur MINIMUM entre deux colonnes voisines pour qu'un grain
# roule de la haute vers la basse -- mecanisme scripts/sandpile.gd.
# Terre : 3 (tas moyennement stable, ~30 degres). Sable : 2 (s'effondre
# vite). Roche cassee : 5 (tient bien). Valeur en NOMBRE DE SOUS-CUBES.
@export var angle_repos: float = 3.0
# HAUTEUR MAX EN SOUS-CUBES sur une seule colonne pour cette matiere.
# Terre naturelle : ~60 sc = ~40 m (Silbury Hill, tumulus d'accumulation).
# Roche compacte tiendrait plus haut, sable moins. 0 = pas de limite (defaut,
# securite -- une matiere sans limite explicite ne se plafonne pas).
# Applique SEULEMENT au depot par sandpile : le sc source ne se transfere pas
# vers une colonne receveur deja a la limite pour cette matiere.
@export var hauteur_max_sous_cubes: int = 0
