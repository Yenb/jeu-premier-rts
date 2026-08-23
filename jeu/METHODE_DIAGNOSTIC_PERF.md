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
