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
