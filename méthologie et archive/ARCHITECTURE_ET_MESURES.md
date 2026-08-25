# Architecture des cartes et méthodologie de mesure

Archive du chantier perf/ceinture du 2026-08-25. Explique **pourquoi une carte
15× plus grande pèse ~500× moins**, avec quelle méthode ça se mesure et les
quatre bancs qui l'ont produit.

---

## 1. Le résultat qui surprend

| Carte | demi_cote | côté | superficie | poids fichier | architecture |
| --- | --- | --- | --- | --- | --- |
| `terrain/carte.tscn` (la première) | 64 | 256 m | ~0,065 km² | **2,5 Mo** | tout baké |
| `Proto/verification.tscn` | 250 | 1000 m | 1 km² | 15 Ko | donnée + streaming (propre) |
| `terrain/carte_100km2.tscn` | 2500 | 10 km | 100 km² | **9,3 Mo** ⚠ | donnée + streaming, mais FICHIER pollué (voir Correction) |

`verification` couvre **~15× plus de surface** que la première carte et pèse
**~500× moins** sur le disque. `carte_100km2` couvre **100 km²** — 1500× la
première — et pèse toujours quelques Ko.

Ce n'est pas un paradoxe : c'est deux façons opposées de payer une carte.

---

## 2. Les deux architectures

**Baké (GridMap statique).** Chaque cellule est stockée dans la scène, avec sa
collision et son maillage. Le poids **suit l'emprise × tout ce qu'elle porte** —
mur compris. Une carte de 128×128×7 couches stocke ses ~114 000 cellules ; une
carte deux fois plus large en stocke quatre fois plus. C'est `carte.tscn`, l'ancienne
architecture. Mesuré ailleurs : 16,5 octets de scène et 86 octets de mémoire par
cellule GridMap.

**Donnée + streaming.** Le monde vit en **donnée pure** (`carte_terrain.gd` : un
Dictionary d'écarts au défaut, 185 octets pour une carte vierge de 25 millions de
colonnes). Seul un **disque de cellules autour de l'observateur** devient des
nœuds rendus/collisionnés (`terrain_visible.gd` proche, `terrain_streame.gd`
lointain). Le coût **suit le rayon, jamais l'emprise** : traverser 10 km laisse le
compte de cellules identique au premier pas. C'est pourquoi la DONNÉE de 1 km²
et de 100 km² pèse pareil (185 o à vide, ~240 Ko sculptée) — ce que le FICHIER
de scène porte est une autre affaire, voir la Correction en fin de document.

**La ceinture était la même leçon à petite échelle.** L'ancienne ceinture
`murs_limite.gd` posait un anneau de cellules GridMap = `4·(2·demi_cote+2)−4`
colonnes × 22 couches. À demi_cote 250 : **44088 cellules de collision** pour
quatre murs droits. Le refactor `murs_limite_boite.gd` les remplace par **4
`BoxShape3D`** — coût constant, quelle que soit l'emprise (les mêmes 4 boîtes
borneraient les 100 km²).

---

## 3. Méthodologie de mesure (les invariants)

Ce qui rend un chiffre fiable, appris et re-appris sur ce dépôt :

1. **Fenêtre, pas `--headless`, pour les draw calls.** Le renderer doit tourner ;
   en headless les draw calls valent 0. La physique, elle, se mesure en headless.
2. **v-sync off + `Engine.max_fps = 0`.** Sinon le `dt` d'image est quantifié par
   la fréquence écran (16,7 / 33 ms…) et mesure l'attente, pas le travail.
   `DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)`.
3. **Moniteurs.** `RenderingServer.get_rendering_info(...)` ou
   `Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME /
   RENDER_TOTAL_PRIMITIVES_IN_FRAME / RENDER_TOTAL_OBJECTS_IN_FRAME)` ;
   `TIME_PROCESS` / `TIME_PHYSICS_PROCESS` (ms CPU) ; `OBJECT_NODE_COUNT`,
   `OBJECT_ORPHAN_NODE_COUNT`, `PHYSICS_3D_ACTIVE_OBJECTS/COLLISION_PAIRS/
   ISLAND_COUNT` ; `OS.get_static_memory_usage()` pour la mémoire.
4. **Élimination : un run isolé par contributeur.** On désactive UN élément et le
   **delta contre la baseline** est son coût. Runs séparés, jamais tout dans un
   seul (le warm-up moteur et l'interférence fausseraient).
5. **Un delta plus petit que la variance inter-run est du BRUIT.** Relancer la
   baseline deux fois donne la variance ; tout écart en dessous ne se conclut pas.
   Exemple vécu : retirer la ceinture « faisait gagner » 0,09 ms — mais la variance
   physique inter-run valait 0,13 ms. Verdict honnête : *sous le seuil de bruit*,
   pas « 0,09 ms ».
6. **Piège moniteurs physique.** `TIME_PHYSICS_PROCESS` n'inclut pas forcément le
   pas interne du `PhysicsServer3D` (broadphase/narrowphase). Un coût physique peut
   être hors du nombre mesuré — à vérifier avant de conclure. Le vrai coût de 44088
   corps statiques n'est pas par frame (0 paire active) mais à la **construction**
   et en **mémoire**.
7. **Géométrie déduite de l'emprise, jamais `map_to_local`.** Pour qu'un test vaille
   sans GridMap (sur les boîtes comme sur les cellules), les faces se calculent de
   `demi_cote`, `cote`, `couche_base`. Convention du moteur, vérifiée contre le
   GridMap réel : cellule d'indice `i` NON centrée, de `i·cote` à `(i+1)·cote`
   (centre `(i+0.5)·cote`) sur les trois axes — d'où faces internes à `±demi_cote·cote`.

---

## 4. Les quatre bancs

### (1) `jeu/Proto/banc_plancher_rendu.gd` — plancher de rendu

Charge `verification.tscn`, retire le Couvert (mesure le plancher SOUS lui), puis
désactive UN contributeur selon la config passée en `-- config=A..E`, échantillonne
sur une fenêtre de frames stable, écrit les chiffres bruts. Deux phases : immobile,
puis marche (le personnage avance, `Input.action_press("ui_up")`) pour capter le
coût du streaming.

- A : scène sans Couvert (baseline). B : − ceinture. C : − TerrainStreame.
  D : − terrain proche. E : ombre du Soleil coupée.
- Le delta A→config désigne le coût réel de l'élément désactivé.

### (2) `mesure_ceinture.gd` — mémoire de la ceinture (GridMap vs boîtes)

Banc jetable (supprimé après usage, reproduit ici). Isole la ceinture (libère tout
sauf `Limites`), chronomètre sa construction, relève node count / corps physiques /
mémoire. Le boot affiche ~0 pour le GridMap parce que sa collision est **bakée en
différé** : le vrai coût est la mémoire, pas le temps.

```gdscript
extends SceneTree

const CHEMIN := "res://jeu/Proto/verification.tscn"

func _init() -> void:
	var ps := load(CHEMIN) as PackedScene
	var racine := ps.instantiate()
	for enfant in racine.get_children():
		if enfant.name != "Limites":
			enfant.free()
	var mem_avant := OS.get_static_memory_usage()
	var t0 := Time.get_ticks_usec()
	root.add_child(racine)
	var boot_us := Time.get_ticks_usec() - t0
	await process_frame
	await process_frame
	var murs := racine.get_node_or_null("Limites/Murs")
	print("=== MESURE CEINTURE (%s) ===" % (murs.get_class() if murs else "ABSENT"))
	print("boot_construction_ms=%.2f" % (boot_us / 1000.0))
	print("node_count=%d" % int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	print("physics_active_objects=%d" % int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)))
	print("memory_static_mo=%.2f" % (OS.get_static_memory_usage() / 1048576.0))
	print("delta_memory_ceinture_mo=%.3f" % ((OS.get_static_memory_usage() - mem_avant) / 1048576.0))
	quit()
```

Résultat : GridMap **15,709 Mo** / boîtes **0,681 Mo** (~23×), 44088 formes → 4.

### (3) `jeu/terrain/test_ceinture_infranchissable.gd` — barrière + géométrie

Verrouille que la ceinture arrête les corps sur les quatre côtés, quel que soit son
implémentation (GridMap OU StaticBody de boîtes). Paramétrable `-- scene=`. Quatre
épreuves, chacune visant un bug Godot connu loin de l'origine (~500 m) :

- **A** barrière : un `CharacterBody3D` lancé vers chaque bord à 20 m/s ne sort pas.
- **B** tunneling : un `RigidBody3D` à 100 m/s (CCD) ne franchit pas (#39095).
- **C** jitter : collé au mur, poussé parallèlement, ne doit pas osciller
  perpendiculairement (#75537). Mesuré : variance 0.
- **D** glissement : avance le long du mur sans se bloquer (#69683). Mesuré : 10 m.

Sur GridMap avant comme sur boîtes après, aucun des trois bugs ne se manifeste.
La géométrie déduite est comparée au centrage réel du GridMap sur la baseline : si
elle diverge, le test rougit (c'est ainsi qu'une erreur de ±1 cellule a été prise).

### (4) `jeu/plantes/banc_pics_couvert.gd` — pics de frame du couvert

Charge `verification.tscn` (1000 arbres), v-sync off, échantillonne à chaque image
les moniteurs moteur plus les compteurs de `monde.gd` et l'instrumentation de
`couvert.gd`. Deux phases (immobile / marche). Sort la distribution des `dt`, la
liste des images au-dessus de 2× la médiane, et le `dt` médian selon qu'une image
porte un tick de simulation ou un churn de corps. Sert à séparer un pic de rendu
d'un pic de logique.

---

## 5. Résultats chiffrés de la session

**Plancher de rendu** (`verification`, sans Couvert, immobile) : ~1560 draw calls,
~15 ms/frame, borné par le rendu (physique ~0,8 ms). Contributeurs :

- **Passe d'ombre du Soleil** : ~1034 draws, ~3,5 ms (66 % des draws).
- **TerrainStreame** : ~926 draws, 522 k primitives (91 %), ~4,6 ms.
- Les deux sont **couplés** (l'ombre redessine la géométrie de TerrainStreame).
- **Ceinture** : 0 draw (aucun maillage). A et B ont des draws identiques au chiffre.
- Config D faussée : retirer le sol proche fait tomber l'observateur.

**Ceinture GridMap → 4 boîtes** : mémoire 15,7 → 0,68 Mo (~23×), 44088 formes de
collision → 4, par-frame indistinguable de zéro (statique, 0 paire). Face interne
inchangée (barrière au même endroit), épaisseur 10 m poussée vers l'extérieur,
hauteur 0→44 m. Appliqué à `verification.tscn`, `proto_terrain.tscn`,
`carte_prototype.tscn`. `murs_limite.gd` retiré du dépôt.

---

## Correction (2026-08-25) — le fichier du 100 km² n'est PAS optimisé

En conversation, j'avais dit « quelques Ko » pour le 100 km². **C'est faux.**
Tailles réelles sur le disque :

| Fichier | poids |
| --- | --- |
| `verification.tscn` | 15 Ko (propre) |
| `carte.tscn` (première, bakée) | 2,5 Mo |
| **`carte_100km2.tscn`** | **9,3 Mo** — plus lourd que la première carte |
| `carte_100km2.tres` (la donnée réelle) | 240 Ko |

**Cause.** Le nœud Terrain de `carte_100km2` embarque ~9 Mo de cellules GridMap
**bakées dans la scène**. Elles sont **redondantes** : la carte les reconstruit
depuis `carte_100km2.tres`, et `terrain_visible` vide le GridMap au boot pour
restreamer. Poids mort pur.

**Pourquoi `verification` reste à 15 Ko :** on ne le sculpte pas, aucune cellule
ne s'y accumule. `carte_100km2` est une scène d'édition — chaque `Ctrl+S` en cours
de sculpture bake le disque streamé dans le `.tscn`, et rien ne le nettoie
(documenté dans SUIVI, EN COURS : « vider avant Ctrl+S le ramène à 3 Ko ; rien ne
le force »).

**Distinction à retenir :** l'ARCHITECTURE (donnée + streaming) est légère par
nature ; c'est le FICHIER qui est pollué, pas l'architecture. Remède : vider le
GridMap avant sauvegarde, ou empêcher le bake au save. Chantier ouvert —
`carte_100km2` n'est donc PAS aussi optimisée que `verification` sur le disque,
alors que sa fondation, elle, l'est.
