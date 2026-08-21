# CARNET DE JEU

Ce que le jeu SAIT FAIRE, où ça vit, et quoi tourner pour changer ce qu'on voit.
Destiné à qui reprend le jeu — Yael ou un agent — et il répond à trois questions,
dans cet ordre : qu'est-ce qui tourne aujourd'hui, où se prend chaque décision,
quel réglage produit quel effet.

Ce carnet dit ce qui EST. Il ne raconte rien et ne tient aucun état : ce qui est
ouvert, rouge ou en cours vit dans `SUIVI.md`, jamais ici.

Ce qu'il ne contient pas, et où c'est :

| ce qu'on cherche | où |
|---|---|
| le POURQUOI d'une règle du monde | `jeu/GAME_DESIGN.md` |
| le journal, les décisions, les pièges, ce qui est rouge | `SUIVI.md` |
| les GESTES de la carte, l'index du terrain, ses tests | `jeu/terrain/MANUEL_CARTE.md` |
| les chiffres du couvert et leur méthode | `jeu/plantes/MESURES_COUVERT.md` |
| les mécanismes du moteur | `documents/CARTE.md` (lecture seule) |
| le pourquoi d'UN fichier | son en-tête, en tête du `.gd` |
| les commandes de lancement | `CLAUDE.md` § TRAVAILLER SUR LE PROJET |

---

## 1. La forme du jeu — quatre couches

```
  DONNÉE DU MONDE     carte_terrain.gd  (le sol, en volume)
       │              scripts/monde.gd  (les choses vivantes, rangées par case)
       │
       │   registre.gd « j'ai changé » ──> archiviste.gd « alors je t'écris »
       ▼
  SIMULATION          vegetation.gd — aucun nœud, aucun rendu, testable headless
       │              rend un RAPPORT par tick ; ne connaît ni GridMap ni .glb
       ▼
  COUCHE VISIBLE      terrain_visible.gd · couvert.gd · objets_visibles.gd
       │              fabriquée autour de l'observateur, libérée derrière lui
       ▼
  ÉCRAN

  À CÔTÉ, JAMAIS EN JEU — les outils d'éditeur (@tool) :
  outil_fenetre · outil_sculpture · outil_remplissage · maquette · repere_fenetre
```

La règle qui tient ces quatre couches — « tout est donnée, le rendu et la
collision sont une couche temporaire » — et ce qu'elle coûte : `SUIVI.md`
§ DÉCISIONS. Le carnet ne la redit pas, il montre où elle est appliquée.

DEUX CHOSES SEULEMENT VIVENT DANS LE MONDE (`scripts/monde.gd`) : les plantes
vivantes et les objets semés. Le terrain n'y entre pas — il se lit par colonne,
en temps constant. Les produits tombés au sol non plus.

---

## 2. Ce qui se lance

| scène | ce qu'on voit | ce qu'elle monte |
|---|---|---|
| `terrain/carte_100km2.tscn` — **scène principale** | 100 km², un disque de terrain autour du personnage, sculptable dans la même scène | terrain + personnage + les quatre outils d'éditeur |
| `terrain/carte_prototype.tscn` | 200 m de côté, ceinture de murs, forêt et herbe, objets qui apparaissent quand on approche | **la seule qui monte TOUT** : terrain, ceinture, couvert, objets, archiviste |
| `terrain/carte.tscn` | l'ancienne carte, GridMap entièrement posé, couvert et semis dessus | terrain plein + couvert + personnage + caméra fixe |
| `terrain/grande_carte.tscn` | 300×300 de terrain nu | GridMap plein + personnage, aucun script de jeu |
| `terrain/sculpture.tscn`, `terrain/maquette.tscn` | postes d'éditeur sur la carte de 100 km², sans personnage | les outils seuls |
| `Outil de jeu/test_ennemi.tscn` | 7 ha ceinturés, écosystème complet du prototype ennemi : cube violet + transporteurs + gisement + mode combat + soldat + vie joueur | monde partagé, personnage avec vie/présence, une lignée de cube violet (garde + gestations stock/soldat), gisement de fer, HUD vie du joueur |

---

## 3. Les cinq domaines

### 3.1 `jeu/monde/` — ce dont le monde se souvient

Une donnée qui doit survivre au lancement hérite de `registre.gd`, appelle
`marquer_sale()` quand elle change, et se glisse dans la liste d'un nœud
`Archiviste`. C'est tout : il n'y a aucune ligne d'écriture à écrire, et
`archiviste.gd` est le seul fichier du jeu qui appelle `ResourceSaver`.

- `registre.gd:marquer_sale`, `est_sale`, `peut_etre_ecrit`
- `archiviste.gd:ecrire_les_sales` (à intervalle, jamais à chaque image), `en_attente`
- la marche à suivre complète : `MANUEL_CARTE.md` § Ajouter une sorte de donnée au monde

### 3.2 `jeu/terrain/` — la carte est un VOLUME

Chaque colonne porte le MASQUE de ses couches pleines, pas sa hauteur : grottes,
ponts, surplombs et niveaux séparés sont représentables. Les cellules qui
s'écartent du bloc par défaut sont gardées à part avec leur item et leur
orientation — c'est ce qui fait survivre une rampe, et ce qui fera survivre un
bloc pas encore inventé.

- lire : `carte_terrain.gd:sommet`, `est_pleine`, `hauteur_du_sol`, `masque` — temps constant
- écrire : `poser_masque`, `sculpter`, `poser_cellule`, `retirer_cellule`
- la bibliothèque `bloc.tres` porte trois items : le bloc plein, la **limite**
  (collisionne sans se dessiner), la **rampe** (prisme, collision qui épouse ses
  six sommets, demi-tour qui inverse la montée)
- la ceinture : `murs_limite.gd` la pose au lancement depuis la carte ;
  `generer_murs.gd` l'écrit en dur dans une scène
- index fichier par fichier, gestes de sculpture, tests : `MANUEL_CARTE.md`

### 3.3 `jeu/plantes/` — le couvert végétal

Le seul gameplay complet du jeu à ce jour. Plusieurs espèces poussent, se font de
l'ombre, se reproduisent, déposent un produit ramassable et meurent de vieillesse.
Aucune mécanique n'est écrite ici : `vegetation.gd` compose `senescence.gd`,
`stade.gd`, `seuil_etat.gd`, `gestation.gd` et `monde.gd` du moteur.

TROIS CONTRAINTES, ET IL FAUT LES TROIS — la densité borne le NOMBRE, l'ombre
tranche QUI L'EMPORTE (par stature, jamais par numéro de stade), la trouée décide
QUI PEUT S'INSTALLER OÙ. Ce qu'elles produisent ensemble : `GAME_DESIGN.md`
§ Végétation.

- l'ordre du tick, ses neuf pas, et pourquoi cet ordre : en-tête de `vegetation.gd`
- avancer : `vegetation.gd:avancer`, `avancer_par_tranches`, `pas_maximal`
- agir dessus du dehors : `vegetation.gd:retirer` (ôter une plante en prévenant
  son voisinage), `ramasser` (prendre un produit au sol)
- le pont vers le terrain : `surface_terrain.gd` — le SEUL fichier du jeu qui
  connaisse GridMap ; il relève depuis une grille pleine ou depuis une carte
- le rendu : `couvert.gd` — une plante n'est pas un nœud, c'est une LIGNE dans un
  MultiMesh ; seule une espèce à `rayon_collision` reçoit un vrai corps solide
- poser une graine : une scène dérivée de `plante.tscn` (`arbre.tscn`,
  `herbe.tscn`) glissée sous le nœud `Couvert`

### 3.4 `jeu/objets/` — de la donnée au nœud

Dix mille objets semés coûtent le même nombre de nœuds que cinquante : le rayon
seul décide. Agrandir la carte coûte zéro.

- `semer_objets.gd:semer` — peuple le Monde en données, hasard seedé, la hauteur
  vient de la carte
- `objets_visibles.gd:rafraichir` — fabrique un corps pour ce qui entre dans le
  rayon, libère ce qui en sort ; `montres()` dit combien sont vivants
- ajouter une sorte d'objet = une ligne dans `semis`, une dans `scenes`, sur la
  scène. Zéro ligne de code.

### 3.5 `jeu/unites/` — le personnage arpenteur

Une capsule d'un mètre — une demi-cellule — vue à la première personne. Elle sert
à vérifier à hauteur d'homme qu'un tronc barre le passage, qu'une touffe est à la
bonne échelle, qu'une pente se monte. Elle ne simule rien du monde.

- flèches : haut/bas avancent, gauche/droite TOURNENT ; souris : horizontale =
  le corps pivote, verticale = les yeux seuls s'inclinent, sous le quart de tour
- curseur pris au PREMIER CLIC, rendu par Échap
- le calcul est en fonctions pures : `personnage.gd:vitesse_voulue`,
  `rotation_voulue`, `pivot_souris`, `inclinaison_voulue`, `souris_pilote`
- il est dans le groupe `observateur` : c'est ce lien, et lui seul, qui fait que
  le terrain et les objets se dessinent autour de lui

---

## 4. Les leviers — ce qui change le jeu sans écrire une ligne

### Sur un nœud d'espèce (`Arbre`, `Herbe`… sous le `Couvert`)

| levier | ce qu'il produit à l'écran |
|---|---|
| `duree_stade_1..3`, `stature_stade_1..3` | la vitesse du cycle, et QUI ombrage qui |
| `modele_stade_1..3` | le corps de chaque stade ; vide = touffe fabriquée à l'exécution |
| `marge_couches` | jusqu'où l'espèce monte sur le relief — la NICHE, donc deux paysages |
| `trouee_max_voisins` | bas : elle exige une vraie trouée ; haut : elle s'étend dans son propre tapis |
| `rayon_dispersion_min/max` | anneau serré = tapis continu ; anneau large = semis clairsemé |
| `max_voisins` | ce qui borne la population : au-delà, la mère cesse de se reproduire |
| `stade_reproduction_min/max`, `intervalle_reproduction` | la fenêtre fertile — trop courte devant la vie, l'espèce est stérile |
| `stade_production_min`, `intervalle_production`, `max_produits_par_plante` | le débit de ressource, et son encombrement au sol |
| `duree_vie_produit` | combien de temps le joueur a pour venir ramasser |
| `rayon_collision` | zéro : traversable. Non nul : un fût qu'aucune unité ne franchit |
| `dispersion_duree` | l'écart de vie entre individus — sans lui, une population est des cohortes synchronisées |
| `distance_rendu` | au-delà, Godot cesse de DESSINER. Le nœud reste, le tronc barre toujours |

### Sur le `Couvert`

`rayon_voisinage_cellules` / `rayon_ombre_cellules` / `rayon_trouee_cellules` :
l'échelle des trois contraintes, commune à toutes les espèces.
`ticks_prechauffage` × `delta_prechauffage` : le temps déjà vécu quand le joueur
arrive — le PRODUIT des deux est le temps simulé, et ce qu'il fait à une
population est mesuré dans `MESURES_COUVERT.md` §11-12.
`pas_simulation`, `ticks_max_par_image`, `facteur_temps` : le rythme, jamais le
contenu.

### Sur la carte et son rendu

`demi_cote` (l'emprise, portée par la carte elle-même), `couche_base`,
`couches_pleines`, `cote` sur `carte_terrain.gd` ; `rayon_cellules` et
`pas_de_rafraichissement` sur `terrain_visible.gd` — le rayon décide seul du coût.

### Sur les objets et le personnage

`semis` (clé → combien), `scenes` (clé → PackedScene), `graine`, `rayon_metres` ;
`vitesse`, `vitesse_rotation`, `sensibilite_souris`, `inclinaison_max`, `gravite`.

---

## 5. Écrit, testé, et que personne n'appelle encore

- **LE RAMASSAGE.** `vegetation.gd:ramasser` et `couvert.gd:retirer_graine`
  fonctionnent et sont verrouillés ; aucune unité ne les appelle. Le mécanisme du
  moteur qui transfère entre deux choses est `scripts/consommer.gd`.
- **ARRACHER ET ABATTRE.** `vegetation.gd:retirer` est le geste ; aucune commande
  ne l'atteint. Ce sont les deux gestes opposés que `GAME_DESIGN.md` attend du
  joueur pour piloter la succession.
- **LE COUVERT ET LES OBJETS NE SONT PAS DANS LA SCÈNE PRINCIPALE.**
  `carte_100km2.tscn` ne porte ni `Couvert`, ni `Objets`, ni `Archiviste` ;
  `carte_prototype.tscn` est la seule scène où tout tourne ensemble.
- **L'LLM.** Rien dans `jeu/` ne parle à Ollama. Le seul appel prouvé est un banc
  du framework, `scripts/banc_llm_connexion.gd`.
- **`godot_rl_agents/`** est un greffon posé à la racine, activé par rien et
  référencé par aucun fichier du jeu.
- **Bancs jetables encore sur le disque** : `jeu/terrain/diag_temp.gd`. Un banc
  jetable se supprime après avoir tranché (`MANUEL_CARTE.md` § Diagnostiquer).

---

## 6. Ce que le jeu ne sait pas encore faire

Aucune de ces lignes n'est un défaut : c'est la frontière de ce qui existe.

- **Aucun ordre RTS** : ni sélection, ni clic de déplacement, ni caméra de
  stratégie. Le seul pilotage est la marche à la première personne.
- **Aucune unité autre que le personnage**, aucun combat, aucune faction.
- **Aucune interface**, donc aucun texte joueur — et l'internationalisation ne se
  rétrofitte pas : elle vaut dès la première ligne d'interface (`CLAUDE.md`).
- **Le terrain destructible n'est pas écrit.** La donnée est prête — un volume
  par colonne, ce dont tout le reste dépend — mais ni gravité, ni cohésion, ni
  fissure, ni étayage. Le point ouvert (la connexité de voisinage) est un
  chantier FRAMEWORK : `GAME_DESIGN.md` § Terrain destructible.
- **Rien ne transporte de matière** : ni inventaire, ni charge, ni logistique —
  ce sur quoi repose pourtant toute la philosophie de facturation.
- **Aucune condition de victoire.**

---

## 7. Où se prend la décision

| je veux changer… | j'ouvre |
|---|---|
| ce qu'est une espèce (rythme, taille, niche, ressource) | le nœud d'espèce sous le `Couvert`, à l'inspecteur |
| ce qui est commun à toutes les espèces | `jeu/plantes/vegetation.json`, ou les `@export` du `Couvert` qui le surchargent |
| la vie, la mort, l'ombre, la reproduction | `jeu/plantes/vegetation.gd`, et nulle part ailleurs |
| ce qui se dessine d'une plante | `jeu/plantes/couvert.gd` |
| la forme du sol | la carte `.tres`, par les outils de sculpture |
| jusqu'où le monde se dessine | `rayon_cellules` (terrain), `rayon_metres` (objets) |
| ce qui est semé sur la carte | `semis` et `scenes`, sur la scène |
| ce qui survit au lancement | la liste `registres` du nœud `Archiviste` |
| comment le joueur se déplace | `jeu/unites/personnage.gd` |
| une mécanique qui n'existe pas | **le dépôt du framework, jamais ici** (`CLAUDE.md` § Frontière) |

---

## 8. Les tests du jeu

`& "<chemin godot>" --headless --script jeu/<...>/test_xxx.gd`

Ceux du terrain et du monde sont listés dans `MANUEL_CARTE.md` § Les tests.
Les autres :

| test | ce qu'il rend impossible |
|---|---|
| `plantes/test_plante.gd` | que le couvert dépende du rendu ; qu'une dominée devienne immortelle ; que l'inspecteur et le fichier de réglages divergent |
| `plantes/test_couvert_carte.gd` | qu'une plante ne pousse que là où des cellules sont rendues |
| `objets/test_semer_objets.gd` | qu'un semis ne soit pas reproductible à graine égale, ou qu'un objet tombe dans le vide |
| `unites/test_personnage.gd` | que la marche, le pivot ou la visée régressent en silence dans un rappel du moteur |
| `terrain/test_carte_prototype.gd` | que la scène qui monte TOUT ensemble perde un branchement |

Un test headless ne voit rien de l'éditeur : `MANUEL_CARTE.md` § Diagnostiquer.
