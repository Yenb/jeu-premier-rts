extends RefCounted

# Un niveau de resolution du monde spatial (`scripts/monde.gd`). Une instance
# par arete ouverte -- monde.gd tient une liste de niveaux dans
# `_niveaux_liste` et un Dictionary exposant -> Niveau dans `_niveaux`.
#
# CHAMPS TYPES, PAS UN DICTIONARY. Avant ce chantier, un niveau etait un
# Dictionary { "cases", "case_de", "_idx_dans_case", "_inv_arete",
# "_exposant", ... } : chaque acces dans le hot path `deplacer_simple` faisait
# un lookup de cle String hache. Ici, ces cles deviennent des PROPRIETES
# d'objet Godot -- acces par slot fixe (documente plus rapide qu'un lookup
# Dictionary hache dans la doc Godot 4).
#
# STRUCTURE CIBLE DU PORTAGE C++. Cette forme (petit objet avec champs typés)
# se porte 1-pour-1 en C++ comme un struct :
#
#     struct NiveauMonde {
#       std::unordered_map<Vector3i, std::vector<int>> cases;
#       std::unordered_map<int, Vector3i> case_de;   // structure_simple
#       std::unordered_map<int, int> idx_dans_case;
#       float inv_arete;
#       float arete;
#       int exposant;
#     };
#
# Les tableaux paralleles indexes par position dans `_niveaux_liste` avaient
# ete envisages : ECARTES parce que N tableaux a synchroniser en cas d'ajout/
# retrait de niveau, moins fidele a un struct C++. La version objet reflete
# directement la structure native.
#
# `cases` (Vector3i -> Array<id>) reste un Dictionary interne. Sous
# structure_simple, chaque valeur est un Array<id> a plat (append + swap-remove
# O(1)). Sous subdivision, la valeur peut etre soit un Array (case terminale)
# soit un Dictionary de sous-cases (case subdivisee). Ce polymorphisme se
# resout en C++ par une union ou un discriminant.
#
# `case_de` (id -> Vector3i sous structure_simple, id -> Array<Vector3i> sous
# subdivision) : le format depend du regime dans lequel le niveau est utilise,
# jamais mixte sur un meme Monde -- monde.gd:structure_simple fixe le regime
# au _ready, avant tout ajouter/deplacer.

var cases: Dictionary = {}
var case_de: Dictionary = {}
var idx_dans_case: Dictionary = {}
var inv_arete: float = 1.0
var arete: float = 1.0
var exposant: int = 0
