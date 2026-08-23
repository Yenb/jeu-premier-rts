# A PRÉVOIR — chantiers de design tranchés, non implémentés

Ce fichier note les décisions de design prises en discussion mais pas
encore codées, pour ne pas les perdre. Chaque section = un chantier
délimité, avec les raisons qui justifient la décision — utile quand on
reviendra dessus dans plusieurs semaines.

## 1. Rayon englobant par entité pour la bascule rendu

**Problème.** Le test actuel `dist(observateur, entite.position) < rayon_rendu`
suppose que l'entité est un point. Une entité de grande taille (tour de
20 m, structure de 500 m, pyramide de 1 km) doit apparaître dès que son
BORD entre dans le rayon, pas seulement son centre.

**Décision.** Chaque entité porte un `rayon_englobant` dérivé de sa
taille (demi-diagonale de sa bounding sphere). Le test devient
`dist(obs, centre) < rayon_rendu + rayon_englobant`. Une tour de 500 m
devient visible à 560 m au lieu de 60 m (ou du rayon actuel).

## 2. Buckets par ordre de grandeur pour le filtre grossier

**Problème.** Le test avec somme par entité empêche un filtre unique
sur seuil constant. Naïvement, on prend `RAYON_MAX_GLOBAL` = max des
rayons englobants, ce qui donne un filtre `dist2 < (rayon_rendu +
RAYON_MAX)²` en une comparaison. Mais si une entité géante (pyramide
500 m) est présente, RAYON_MAX = 560 m et TOUS les petits (carrés de
0.5 m) passent un filtre à 560 m — autant dire pas de filtre.

**Décision.** Buckets par ordre de grandeur du `rayon_englobant`
(exemple : 0–2 m, 2–16 m, 16–128 m, 128 m+). Chaque bucket porte son
propre `RAYON_MAX` local et son propre filtre grossier. Un carré ne
paye jamais la présence d'une pyramide dans le monde — il ne teste
que son bucket. Le bucketing se fait à l'ajout de l'entité (log2 du
rayon), coût nul.

## 3. Cycle skin différencié selon la taille du mesh

**Problème.** Un carré de nourriture (mesh trivial) supporte le cycle
instanciation/destruction chaque fois que le joueur entre/sort du
rayon. Une pyramide de 1 km (mesh lourd) ne le supporte pas —
recharger le mesh à chaque approche = lag garanti.

**Décision.** Deux régimes selon le bucket :

- **Bucket petit/moyen** (carré, producteur, ennemi standard) : cycle
  instanciation/destruction actif. Skin éphémère bon marché.
- **Bucket géant** (pyramide, montagne unique) : skin instancié UNE
  fois quand le joueur entre dans son rayon englobant, **jamais
  détruit tant que l'entité existe en donnée**. Ces objets sont rares
  (dizaine sur toute la carte), leur mesh vit en RAM à un coût 1 draw
  call quelle que soit la taille visible, la destruction/rechargement
  coûterait bien plus que la présence continue. Hystérésis inutile
  puisqu'on ne cycle pas.

Concrètement : chaque bucket a un flag `cycle_skin: bool`. Le bucket
géant a `cycle_skin = false`. On détruit le skin seulement si l'entité
meurt en donnée.

## 4. Cas évité : mesh géant animé en donnée

**Problème non résolu.** Une structure géante dont le tick n'est plus
vide (pyramide qui s'écroule, montagne qui s'ouvre) : skin permanent
+ tick actif = RAM continue + calcul continu, même quand le joueur est
à l'autre bout de la carte.

**Statut.** Question à trancher **quand un tel cas apparaît**, pas
avant. Pistes possibles pour ce moment-là :
- Découpage en sous-entités qui se déclenchent seulement en zone visible.
- Simulation en donnée compressée (une variable "phase d'effondrement")
  qui ne coûte rien tant que le joueur ne regarde pas.
- Streaming du mesh en tuiles internes à l'entité.

Ne pas anticiper une solution avant que le cas soit réel.

## 5. Décor statique intégré au système données (pas d'exception)

**Décision.** Le décor statique (pyramide, montagne, bâtiment fixe)
n'échappe PAS à la règle « tout est donnée ». Il entre dans le système
avec une entrée `(position, mesh_id, rayon_englobant)` et un **tick
vide**. Cohérence architecturale préservée à coût CPU nul.

Cette décision ferme la porte à une exception qui aurait été fragile
— une fois qu'on commence à mettre du décor hors système, la frontière
avec les entités actives devient floue et la règle absolue se dilue.

## 6. LOD terrain à distance

**Problème posé aujourd'hui.** Le rayon rendu des entités (`rayon_rendu`
dans `manager_proto.gd`) est aligné sur le rayon terrain streamé
(`rayon_cellules` × `cote` dans `terrain_visible.gd`) pour éviter que
des entités flottent dans le vide sans sol visuel sous elles. À
rayon_cellules=120 (cote=2), le terrain visuel monte à 240 m. Au-delà,
il faudrait un LOD terrain (mesh grossier, textures basse résolution)
pour continuer d'afficher un sol sans multiplier les cellules.

**Non tranché.** Le format du LOD (heightmap, mesh unique à faible
polycount, tuiles à plusieurs niveaux) n'est pas décidé. Le
déclenchement (au-delà de X m, chargé une fois, jamais rafraîchi ?)
non plus. À traiter quand le besoin de dépasser 240 m devient réel.

## 7. Cache directionnel absent dans `_retargeter`

**Constat.** `terrain_visible.gd:169-193` recalcule le disque entier
à chaque retarget, diff contre `_pose` pour produire `_a_poser` +
`_a_effacer`. Aucun cache spatial : une colonne effacée puis revisée
plus tard refait toute la pose. Le SEUL cache est temps-court (une
colonne encore dans `_a_effacer` au retarget suivant sort de la file
gratuitement).

**Impact concret.** Un joueur qui fait un demi-tour ou un zigzag lent
(intervalle > 130 ms à rayon 120) paie deux fois la pose des mêmes
colonnes. En marche continue linéaire, aucun coût.

**Non tranché.** Ajouter un cache LRU des N dernières colonnes
effacées (garder les meshes en mémoire, ne les libérer qu'à
saturation) reste possible. Coût mémoire vs gain à mesurer d'abord
sur un cas réel de zigzag.

## 8. Gestion du pop-in au téléport

**Problème.** Rayon terrain 120 cellules → premier draw ou téléport de
plus de rayon complet coûte ~45 000 colonnes = ~710 ms en synchrone,
ou ~6,8 s en streaming étalé (débit 120 col/frame).

**Statut aujourd'hui.** Le proto n'a AUCUN téléport (personnage marche
uniquement, `personnage.gd`). Question théorique tant qu'aucun
mécanisme de téléport n'existe.

**Options connues quand il faudra trancher.**
- Accepter le pop-in progressif (téléport rare, joueur voit le monde
  se peupler autour de lui).
- Boost temporaire `colonnes_par_image` à ~500 pendant N frames après
  détection d'un téléport.
- Fondu noir + appel à la version synchrone `rafraichir()` déjà
  présente (`terrain_visible.gd:313-337`) → gel 710 ms mais monde
  complet à la sortie du fondu.

## 9. Cycle skin d'un carré / producteur (rappel de l'existant)

Pour mémoire, l'implémentation actuelle du bucket petit/moyen dans
`manager_proto.gd` :
- Dans `rayon_rendu` : instancier le skin, freeze KINEMATIC par défaut,
  degel si sol confirmé (voir `_gerer_freeze_kinematic`).
- Hors `rayon_rendu` : `queue_free` du skin, `noeud = null`. La data
  reste dans `_carres` / `_producteurs` — le tick continue.

C'est ce cycle qui sera étendu aux futures entités du bucket petit/moyen
(ennemis mobiles, projectiles longue durée, etc.).
