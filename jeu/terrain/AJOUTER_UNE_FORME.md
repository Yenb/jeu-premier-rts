# AJOUTER UNE FORME DE TERRAIN

Une forme = une entrée dans `bloc.tres`. **ZÉRO ligne de code.** Le rendu
(`rendu_terrain_multimesh.gd`) et la collision (`terrain_visible.gd`) prennent
toute forme de la bibliothèque tout seuls.

## Recette

1. Dans `jeu/terrain/bloc.tres`, ajouter un item : un `mesh` (avec son
   matériau), et une forme de collision (`shapes`). Prendre un **id libre**.
   - Caler la taille sur la cellule : `cote = 2 m`, donc un mesh d'environ 2 m
     remplit la case (les cubes font `size = 2`).
   - Copier le bloc `item/N/...` d'un item existant et changer le mesh, le
     matériau, la shape, le nom, l'id.
2. **Poser des cellules** de cette forme dans la carte (sculpter avec). Une
   forme ajoutée à la bibliothèque mais jamais posée ne s'affiche pas — le rendu
   montre ce que la carte contient, pas ce qui dort dans la bibliothèque.
3. Rien d'autre. **Ne pas toucher `rendu_terrain_multimesh.gd`.**

## Pourquoi ça marche sans code

Le rendu lit chaque forme par les conversions **natives** du GridMap, jamais
recalculées à la main :

- mesh : `mesh_library.get_item_mesh(item)`
- calage propre de la forme : `mesh_library.get_item_mesh_transform(item)`
- position de la cellule : `GridMap.map_to_local(cellule)`
- orientation de la cellule : `GridMap.get_basis_with_orthogonal_index(orientation)`

Aucune forme n'est nommée dans le code. Cylindre, sphère, cône, n'importe quel
mesh passe par le même chemin.

## Ce qui casse si on dévie — déjà payé, à ne pas repayer

- **Recalculer la position ou l'orientation à la main** (`index × cote`, une
  rotation posée en dur) → la forme se décale du centrage des cellules. Corrigé
  une fois en passant par `map_to_local` ; ne jamais y revenir.
- **Coder un cas spécial par forme** (`if forme == "rampe"`) → casse la
  généricité. Le rendu ne connaît que des items, jamais des noms.

## Réservé

- **id 1 = `limite`** : le mur invisible du bord de carte. Il n'a pas de mesh et
  le rendu le saute. Ne pas donner cet id à une forme visible.

## Collision

Le rendu MultiMesh ne porte **aucune** collision (loin du joueur, le terrain est
de la donnée plus du rendu). La collision reste sur le GridMap `Terrain` proche,
qui lit la même bibliothèque : donner une `shapes` à l'item suffit pour que le
sol proche porte le joueur.
