# PATRON ENTITÉS SPLIT DONNÉE/RENDU — proto

Recette pour ajouter un nouveau type d'entité (ennemi, ressource, décor
interactif) sans recommencer l'infrastructure. Ce document décrit ce qui
est RÉUTILISABLE tel quel vs ce qu'il faut DUPLIQUER + ADAPTER.

## Ce qui est déjà là, réutilisable tel quel

### Helpers dans `manager_proto.gd`
- `_gerer_freeze_kinematic(rb, data, en_zone_safe)` : bascule freeze
  KINEMATIC selon zone. Reset velocity au dégel. Snap logique via carte
  après timeout. Le `data` dict doit porter `frames_sans_sol` et `position`.
- `_snap_sol_via_carte(cr)` : scan cellule + 8 voisines pour trouver
  sommet valide. Snap X/Z/Y.
- `_sol_present_sous(pos)` : raycast vertical [+0.5, −3] m.

### Constantes
- `MARGE_SAFE`, `FRAMES_SANS_SOL_MAX`, `_rayon_safe` (calculé au ready
  depuis terrain streamed).

## Ce qu'il faut dupliquer + adapter (recette pour un nouveau type)

Pour ajouter, par exemple, un `_ennemis`, dupliquer les 5 blocs suivants
dans `manager_proto.gd` :

### 1. Constante de scène
```gdscript
const EnnemiScene = preload("res://jeu/Proto/ennemi.tscn")
```

### 2. Tableau + champs dict
```gdscript
var _ennemis: Array = []

# Dict par entité : {position, cible, noeud, frames_sans_sol, est_detruit,
# + champs métier (vie, comportement, etc.)}
```

### 3. Fonction de spawn (équivalent `_pondre`)
```gdscript
func _spawn_ennemi(pos: Vector3, ...) -> void:
    _ennemis.append({
        "position": pos,
        "cible": null,
        "noeud": null,
        "frames_sans_sol": 0,
        "est_detruit": false,
        # champs métier
    })
```

### 4. Tick de simulation (équivalent `_tick_extraction`)
La donnée tourne **toujours**, indépendante du rendu :
```gdscript
func _tick_ia_ennemis() -> void:
    for e in _ennemis:
        # Pathfinding : CONSULTER carte_terrain.est_pleine(colonne, couche)
        # pour éviter les murs par construction.
        # Mise à jour état IA, décisions.
```

### 5. Bascule rendu + freeze conditionnel
Copier `_bascule_rendu_carres` (data statique) OU `_bascule_rendu_producteurs`
(data mobile, velocity) selon comportement :

**Data mobile** (patron producteur) :
- Zone safe (freeze=false) : `linear_velocity` vers cible, sync
  `e.position ← noeud.global_position`.
- Zone buffer (freeze=true KINEMATIC) : `noeud.global_position = e.position`.
- Hors rayon : queue_free, `noeud = null`.

**Data statique** (patron carré) :
- Zone safe : sync `e.position ← noeud.global_position` (capte cognement).
- Zone buffer : freeze KINEMATIC, position stable.
- Hors rayon : queue_free.

### 6. Appeler dans `_process`
```gdscript
func _process(delta):
    # ... existing
    _tick_ia_ennemis()
    _bascule_rendu_ennemis()
```

## Ce que la scène de l'entité doit avoir

- `RigidBody3D` avec `CollisionShape3D`, `MeshInstance3D`.
- Si destructible par balle : node dans `groups=["destructible"]` (via
  tscn) + méthode `subir_frappe(degats)` + signal `detruit` émis avant
  `queue_free` (patron `carre_rouge.gd`).
- Si un manager gère la simulation en donnée : `@export var passif: bool`
  + `set_passif(bool)` qui désactive Timer/process interne.

## Ce que le manager doit trouver au `_ready`

- L'observateur : `get_tree().get_first_node_in_group("observateur")`
  (personnage a `groups=["observateur"]` dans tscn).
- La carte : via `_grille.get("carte")` (Terrain frère du manager).
- La grille : `_grille = terrain as GridMap`.

## Refactor futur possible (vers 0 duplication)

Si le nombre de types monte (5+), refactor vers système générique :
```gdscript
func register_type(nom: String, config: Dictionary) -> void:
    # config = {scene, tick_fn, spawn_fn, sync_direction, ...}
```
Une seule méthode `_bascule_rendu_generique(nom, config)` gère tout via
callbacks. Non implémenté aujourd'hui — attendre 5+ types pour justifier.

## LA RÈGLE ABSOLUE

**TOUT se passe en données. Le rendu est une peau qui s'allume quand le
joueur arrive et montre l'état courant.**

Sans exception : gravité, IA, perception, collision, mort par frappe,
reproduction, extraction, cognement. **Aucune interaction ne dépend du
rendu.** Le monde tourne sans le joueur : un ennemi tué en data reste
tué, un carré tombé en data reste au sol, une reproduction en data
produit une nouvelle entité.

Quand le joueur arrive dans le rayon d'une entité, le rendu instancie
un nœud à la position/état courants — c'est la seule chose que le
rendu fait. **Il n'invente rien**, il montre.

## Invariants à respecter

- **Simulation données tourne partout, indépendamment du rendu**. Aucune
  logique métier ne doit dépendre de `noeud != null`.
- **Freeze KINEMATIC obligatoire** (pas STATIC) pour que Area3D (balles)
  détecte encore les collisions.
- **Reset `linear_velocity` + `angular_velocity` au dégel** (issue
  godotengine/godot#35534 : freed refs comparent `== null` true en Dict).
- **Signal `detruit`** est la seule voie fiable de purge (pas
  `is_instance_valid` seul).
- **Pathfinding en données** consulte `carte_terrain.est_pleine` pour
  éviter murs par construction (évite spawn dans un mur au retour du
  joueur).
