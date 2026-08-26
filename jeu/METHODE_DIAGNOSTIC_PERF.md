# MÉTHODE — diagnostic d'un lag / stutter / frise

Quand un lag, une frise ou un stutter apparaît, suivre cette séquence
dans l'ordre. Ne PAS spéculer sur les causes avant l'Étape 1 : le
profiler tranche en 30 s, deviner à l'aveugle coûte des allers-retours.

## Étape 1 — Profiler intégré (donne 90 % des réponses)

1. Éditeur Godot ouvert sur la scène.
2. Onglet bas → **Débogueur** → sous-onglet **Profileur**.
3. « Démarrage auto » coché.
4. Lancer le jeu : **F5**.
5. Reproduire le lag (marche, tir, ce qui déclenche).
6. Arrêter : **F8**.
7. Revenir au profiler. **Image #** doit être > 0.
8. Passer **Temps : Inclusif → Auto** (Self Time). Sans ça, les
   temps enfants gonflent les parents et cachent la vraie cause.
9. Cliquer la colonne **Temps** pour trier décroissant.
10. La fonction en tête = coupable. Le profiler couvre AUSSI les
    fonctions moteur (`RenderingServer::_render_scene`, `PhysicsServer3D::_step`,
    `Node::_process`), pas seulement le code projet.

## Étape 2 — Profileur visuel (si Étape 1 pointe le rendu)

Onglet séparé du Débogueur. Découpe le temps GPU par passe : shadow
map, opaque, transparent, post-process, sky. Distingue CPU (script,
physique) vs GPU (rendu). Deux causes très différentes, deux
corrections opposées.

## Étape 3 — Moniteurs (si spikes irréguliers)

Onglet **Moniteurs** du Débogueur. Graphes temporels : FPS,
`time/process`, `time/physics_process`, mémoire. Un pic isolé sur le
graphe se cale au moment du stutter → permet de corréler avec ce qui
se passe à l'écran à cet instant.

## Étape 4 — Mesure programmatique (si diagnostic reste flou)

- `Performance.get_monitor(Performance.TIME_PROCESS)` : temps CPU
  frame en secondes.
- `Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)` : temps
  physique frame.
- `Time.get_ticks_usec()` avant/après un bloc suspect pour isoler.

Loguer chaque frame → repérer un pic isolé.

## Pièges

- **Chiffres dans l'éditeur = faussés** par son overhead. Pour mesure
  fidèle : build exporté puis profiler dedans. Pour un diagnostic
  grossier, l'éditeur suffit.
- **Physics Frame Time = 16.66 ms** = tick rate fixe de
  `_physics_process` (60 Hz par défaut), **PAS** le temps consommé.
  Le vrai temps consommé s'appelle `Physics Time` ou `Physics 3D`.
- **Ne pas trier par Inclusif** : un parent gonfle par ses enfants.
  Toujours Self Time (Auto).
- **Pas de spéculation avant Étape 1**. Le profiler tranche en 30 s.

## Chantier 2026-08-23 — leçons (bien fait / mal fait)

### BIEN FAIT (à reproduire)

- **Profileur consulté AVANT de conclure** sur l'origine des spikes.
  Le tri par Self Time a montré `_process` du terrain à 0.00-0.01 ms
  et les 84 appels du pattern `carres_rouges` responsables du gros
  du CPU. Sans profileur, une seconde vague de refonte terrain
  aurait été lancée à tort.
- **Mesure comparative avant/après** chaque changement de rendu :
  fps, prims, draws, proc max cités depuis logs, pas de « ça va
  mieux » sans chiffres.
- **Anti-régression** : la logique bitwise `visible_bits_col` est
  verrouillée par 6 tests dans `test_ecosysteme.gd` (plat, grotte,
  pont, bord, isolé, vide) — protège contre la régression grotte/
  pont que la première version cachait.
- **Point de restauration git** systématique avant refonte
  destructive (commits `4da4613`, `83f9a4c`, `76f5240`).

### MAL FAIT (à ne pas répéter)

- **Spéculation avant mesure** répétée : « probablement le culling »,
  « probablement le shading » — chaque hypothèse a mangé une
  itération. La règle « pas de spéculation avant Étape 1 » ci-dessus
  a été violée plusieurs fois.
- **Termes de recherche approximatifs** : « procedural voxel » cherché
  au lieu de « sculpted cube grid dynamic Godot » — résultats hors
  sujet (générateurs runtime au lieu de terrain sculpté statique).
- **Pas de capture visuelle à chaque itération de rendu**. Trois
  approches successives (SurfaceTool + vertex color, greedy, MMI)
  ont été livrées sans capture de contrôle → régressions visuelles
  découvertes tardivement par le user.
- **Modifications de code non demandées** : lambdas d'instrumentation
  ajoutées à `manager_proto` sans que le user les demande, plusieurs
  fois. Chaque modif « rien de grave » a alimenté la méfiance.
- **Étalement de construction sans mesure avant/après** : première
  version staggered = proc max monté à 643 ms (vs 40 ms avant). Fix
  stagger inter-tuiles derrière, mais le pic aurait été évité si la
  mesure avait été faite au premier jet.
- **Kill de Godot pendant que le user regarde** (deux fois) sans
  demander : rupture de flux de test au moment le plus mauvais.

### PIÈGES CONCRETS DOCUMENTÉS

- **`vertex_color_is_srgb = true` par défaut** en Godot 4 : les
  `Color()` littérales GDScript sont converties comme si sRGB →
  linéaire pour le shading, aboutit à un rendu quasi noir. Passer
  à `false` corrige. Piège des approches à VERTEX COLORS ; le rendu
  terrain actuel (`rendu_terrain_multimesh.gd`) l'évite en dupliquant
  le matériau de chaque forme, sans vertex color. (L'idée « un MMI rend
  différemment d'un GridMap » ne valait que pour ces approches
  procédurales : un MultiMesh de vrais meshes rend identique — le terrain
  visible est aujourd'hui rendu en MultiMesh.)
- **`create_trimesh_collision()` crée bien le StaticBody3D** mais
  la collision peut ne pas retenir le joueur (constaté sur un
  MeshInstance3D procédural, cause non identifiée). Ne pas retirer
  la collision native du GridMap Terrain sans preuve qu'un
  remplaçant retient physiquement le joueur.
- **Retirer `visible = false` du GridMap Terrain proche AVANT** de
  prouver qu'un autre système rend la zone 0..rayon_interne =
  sol invisible sous les pieds du joueur (mesuré : Y=14.18 →
  Y=-22.8 en 3 s de chute).

### CE QUE LE PROFILEUR A DIT AU FINAL (2026-08-23)

`_process` du terrain_streame : **0.00-0.01 ms** par frame.
Les spikes en marche viennent AILLEURS : 84 carrés × fonctions
(`_appliquer_gravite`, `_repousser_carres`, `_ticker_carres`,
`masque`, `dans_emprise`, `sommet`, `rang_le_plus_haut`) ≈ 1 ms
visible sur les captures profileur. Le reste des ~9 ms de Process
Time n'a pas été isolé — chantier profileur séparé requis pour
trancher.

## OPTIMISER LES OMBRES — RÉGLAGE GLOBAL, JAMAIS PAR OBJET

Les ombres directionnelles se règlent GLOBALEMENT sur le `DirectionalLight3D`,
jamais objet par objet : un seul réglage vaut pour tout ce qui projette
(terrain, arbres, ennemis, unités). Décision Yael : on OPTIMISE les ombres, on
ne les COUPE jamais.

Le PSSM re-dessine la scène dans CHAQUE cascade : un objet vu dans les 4 splits
est rendu 5 fois (4 passes d'ombre + le rendu principal). D'où un coût d'ombre
qui multiplie primitives et draw calls (mesuré ×10 sur le terrain à
`shadow_max_distance = 400`).

Leviers, du plus impactant au moindre (confirmé par la doc Godot
« lights_and_shadows », `directional_shadow_max_distance` donnant « the most
substantial performance gain ») :
1. `directional_shadow_max_distance` — distance au-delà de laquelle plus rien ne
   projette. Généraliste, un seul curseur pour toute la scène ; une valeur trop
   haute fait re-dessiner tout le terrain streamé dans chaque cascade.
2. `directional_shadow_size` (résolution) — 4096 par défaut, 2048 sur GPU faible.
3. Fade start/length et la distance du premier split — concentrer le détail près.

Ne PAS baisser les splits (4→2) en dur : dégrade la qualité (voir la doctrine
« jamais couper les ombres »). `cast_shadow` par objet existe mais n'est PAS
généraliste — dernier recours pour un objet précis, jamais la méthode.
