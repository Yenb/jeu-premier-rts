# MESURES DU COUVERT VEGETAL

Relevé de mesures, pas un compte rendu de chantier. Ce que ce fichier contient
et rien d'autre : des chiffres obtenus en LANÇANT, la méthode qui les a
produits, et les conclusions que ces chiffres portent. Ce qui reste à décider
n'est pas ici.

CES CHIFFRES SONT D'AVANT L'INDEX SPATIAL de `scripts/monde.gd`. Ils mesurent
un `choses_dans_rayon()` qui balayait toutes les choses à chaque requête ; il
range désormais par case et son coût suit le RAYON, plus la population. Tout ce
que ce fichier attribue à la requête de voisinage — le coût quadratique en N
(§2), la part de la phase 9 (§3), le coût par plante (§6) — porte donc sur un
moteur qui n'existe plus. La méthode reste valable, les nombres non : ce qu'ils
mesurent après l'index n'a jamais été relevé.

Machine : Windows 11, Godot 4.7.1 stable, `--headless`. Terrain : celui de
`jeu/terrain/carte.tscn` (16 900 colonnes relevées, cellule de 2 m, couche de
référence 6). Tous les chiffres viennent de `jeu/plantes/vegetation.gd` recopié
tel quel hors dépôt et instrumenté de chronomètres — la copie n'a changé aucune
ligne de logique.

---

## 1. Ce qui a été mesuré, et comment

| banc | ce qu'il isole | protocole |
|---|---|---|
| paliers | le coût du tick en fonction de N | N plantes posées à densité locale CONSTANTE (1 plante / 12 colonnes), âges étalés au hasard sur la longévité, pas de 2 s, moyenne sur 25 ticks. Seule variable entre deux lignes : N |
| équilibre | la population que le terrain porte | semis de la scène, pas égal au plus grand pas fidèle (`vegetation.gd:pas_maximal`), jusqu'à plateau ou budget épuisé |
| nœuds | la pose et le retrait d'un corps | exactement les gestes de `couvert.gd:_poser_plante` / `_poser_modele` / `_retirer_plante`, 1000 fois |
| jeu | le démarrage réel | `carte.tscn` montée dans un arbre de scène, `_ready` complet (relevé + préchauffage + pose) puis 400 images |

DEUX PRÉCAUTIONS QUI CHANGENT TOUT, et sans lesquelles les chiffres mentent :

- LES ÂGES SONT ÉTALÉS. Sans cela, N plantes créées ensemble franchissent leurs
  seuils au MÊME tick : on mesure un instant, pas un régime.
- LA DENSITÉ LOCALE EST CONSTANTE ENTRE PALIERS. Sans cela, faire varier N fait
  aussi varier le nombre de voisines par requête, et deux causes bougent
  ensemble.

## 2. Le coût d'un tick selon le nombre de plantes

Millisecondes par tick, pas de 2 s.

| N | arbres seuls | herbe seule | mélange 50/50 |
|---|---|---|---|
| 50 | 0,87 | 1,43 | 1,05 |
| 200 | 4,01 | 6,67 | 5,30 |
| 500 | 13,96 | 34,19 | 20,55 |
| 1000 | 40,80 | 119,52 | 65,84 |

LE COÛT EST QUADRATIQUE EN N, mesuré et non déduit : ×20 de plantes rend ×47
(arbre) et ×84 (herbe) de coût. Le compteur qui le prouve directement est le
nombre de candidats balayés par tick — 239 → 105 803 pour l'arbre, 1 587 →
512 076 pour l'herbe, soit ×322 pour ×20 de plantes.

## 3. La part de chaque phase

Millisecondes par tick à N = 1000. Les neuf pas sont ceux de l'en-tête de
`vegetation.gd`.

| phase | arbre | herbe |
|---|---|---|
| 1 croissance (âge, stade, stature) | 7,89 | 8,19 |
| 2 mort au seuil de longévité | 2,78 | 3,38 |
| 3b carte des colonnes prises | 0,96 | 0,96 |
| 4 production | 2,40 | 1,93 |
| 5-7 reproduction (gestation + rejets) | 2,48 | 6,32 |
| 8 reconstruction du Monde | 2,72 | 2,96 |
| **9 ombre + densité** | **19,85 (49 %)** | **93,58 (78 %)** |
| — dont lecture d'ombre | 9,18 | 41,02 |
| — dont compte de voisins | 9,15 | 40,91 |
| — dont balayage des foyers | 1,25 | 10,29 |
| trouée (comptée dans 5-7) | 0,00 | 3,12 |

LA PHASE 9 DOMINE, ET SEULE. À 1000 herbes, 95 des 119 ms du tick — 80 % —
sont dans les requêtes de voisinage, et 98,5 % de la phase 9 elle-même.

## 4. La fonction qui coûte

`scripts/monde.gd:choses_dans_rayon()` — FRAMEWORK, pas jeu. AU MOMENT DE CE
RELEVÉ, un balayage de toutes les plantes enregistrées à chaque requête : le
rayon ne réduisait pas le travail, il ne filtrait que la réponse.

Le jeu l'appelle depuis `jeu/plantes/vegetation.gd`, en trois endroits :
`ombragee()` et `voisinage()`, toutes deux via `rafraichir_plante()` que pilote
`rafraichir_autour()` (pas 9), et `trouee_suffisante()` (pas 7). Ces trois
adresses tiennent toujours.

CE N'EST PLUS UN CHANTIER DE JEU. `rafraichir_autour` ne relit déjà que les
foyers, `peut_pousser` ne fait plus aucune requête, l'ombre est déjà portée par
chaque plante. Ce qui restait était la requête elle-même, et elle vit dans le
framework : elle y porte désormais un index par case, à plusieurs résolutions
nées à la demande. LE GOULOT QUE CE FICHIER DÉSIGNE N'EN EST DONC PLUS UN, et
aucune des trois lignes ci-dessus ne dit ce qu'il coûte aujourd'hui.

## 5. La population que le terrain porte

Semis de la scène, terrain de la scène.

| configuration | temps simulé | population | ms/tick |
|---|---|---|---|
| arbres seuls | 600 000 s | oscille 5 à 80, sommet 179 | 0,2 à 2,0 |
| herbe seule (10 semis) | 5 594 s | plateau ~1 250, sommet 1 371 | ~490 |
| les deux (10 semis d'herbe) | 3 000 s | plateau ~1 260, dont 2 à 7 arbres | ~490 |

TROIS FAITS QUE CES TROIS LIGNES PORTENT :

- L'ARBRE N'A JAMAIS ÉTÉ ÉPROUVÉ AU NOMBRE QUE L'HERBE FAIT VIVRE. Il plafonne
  à 179 dans son meilleur pic, autour de 30 en régime. L'herbe atteint 1 250 en
  900 secondes simulées.
- L'HERBE ÉTOUFFE L'ARBRE. Là où l'arbre seul tient 30 à 80 individus, il n'en
  reste que 2 à 7 dès que l'herbe est là. La trouée fait ce pour quoi elle est
  écrite, et elle le fait fort.
- UN SEMIS D'HERBE UNIQUE MEURT UNE FOIS SUR DEUX avant d'avoir semé. Son sort
  ne dit rien de l'équilibre : toute mesure de population part de dix semis.

## 6. Le coût par plante dépend de l'espèce

À N = 1000, à densité et terrain identiques.

| | ms/tick | ms/plante | foyers/tick | plantes rafraîchies/tick | requêtes/tick |
|---|---|---|---|---|---|
| arbre | 40,80 | 0,041 | 6,8 | 51,7 | 110 |
| herbe | 119,52 | 0,120 | 55,6 | 225,6 | 527 |

L'herbe coûte 2,9 fois l'arbre à nombre égal. LA CAUSE EST DANS LES DONNÉES,
PAS DANS LE CODE : ses stades durent 25/35/40 s contre 180/240/180, et elle se
reproduit toutes les 30 s contre 240. Elle produit huit fois plus d'événements,
et chaque événement déclenche une relecture d'ombre et de densité autour de
lui. Un contenu plus rapide coûte plus cher, sans qu'une ligne de moteur le
sache.

## 7. Ce qui ne coûte PAS

- LA POSE ET LE RETRAIT DE NŒUDS. 5,6 µs par plante pour une touffe
  procédurale, 6,8 µs pour un `.glb`, 0,2 µs au retrait. Poser mille plantes
  coûte 6 ms, une fois. Le maillage de touffe est fabriqué une fois par espèce
  et par stade (`couvert.gd:_preparer_les_rendus`) et n'entre pas dans le coût
  par plante.
- LA CROISSANCE, LA MORT, LA PRODUCTION, LA RECONSTRUCTION DU MONDE. Ensemble,
  16 ms sur 119 à 1000 herbes. Aucune ne mérite qu'on l'optimise tant que la
  phase 9 pèse 80 %.

## 8. Le démarrage

Le préchauffage joue la simulation entière avant la première image. Son coût
est celui du tick, multiplié par le nombre de ticks, à la population du moment.

| scène | vivantes après préchauffage | démarrage |
|---|---|---|
| telle quelle (0 semis d'herbe) | 7 arbres | ~0,1 s |
| + 10 semis d'herbe | 1 284 | **126 s** |

CE N'EST PAS DU LAG DE JEU, C'EST DU GEL DE CHARGEMENT — mais c'est le même
calcul, et il monte comme lui.

## 9. Ce qui n'a PAS pu être mesuré

Dit plutôt que masqué, et à ne pas confondre avec « négligeable ».

- LE COÛT D'AFFICHAGE. `--headless` ne dessine rien. Mille deux cent cinquante
  touffes font autant de `MeshInstance3D` à `cull_mode` désactivé, sous une
  lumière directionnelle qui porte ses ombres à 400 m. Si une part du
  ralentissement est graphique, aucun chiffre de ce fichier ne la contient.
- L'ÉTAT DE LA SCÈNE AU MOMENT OÙ LE RALENTISSEMENT A ÉTÉ VU. `jeu/plantes/` et
  `jeu/terrain/` ne sont pas suivis par git : aucune version antérieure de
  `carte.tscn` n'est récupérable.

## 10. Deux pièges de méthode payés pendant ces mesures

- MESURER À TRAVERS `avancer_par_tranches` SANS FIXER LE PAS. Un pas de 200 s
  découpé par `pas_maximal` joue 32 tranches pour l'herbe et 7 pour l'arbre : la
  comparaison entre espèces mesurait alors le nombre de tranches, pas le coût du
  tick. Le pas se fixe à la main pour toute comparaison — 2 s donne UNE tranche
  pour les deux espèces.
- LA SCÈNE EST UN OBJET VIVANT. `carte.tscn` a changé trois fois pendant la
  session, Godot étant ouvert à côté. Toute mesure qui la lit dit à quelle heure
  elle l'a lue, ou elle ne dit rien.

## 11. Le pas de prechauffage decide de la population, et `pas_maximal` ne protege pas

Une seule espece declaree (arbre), aucun semis d'herbe, meme graine, meme
terrain, memes semis. SEULE VARIABLE : la taille du pas.

| temps simule | pas 30 s | pas 6,25 s | pas 2 s |
|---|---|---|---|
| 2 000 | 15 | 3 | 7 |
| 8 000 | 53 | 53 | 9 |
| 14 000 | 51 | 78 | 4 |
| 26 000 | 96 | 34 | 0 |
| 40 000 | 79 | 11 | 0 |
| 50 000 | 145 | 1 | 0 |
| 58 000 | 143 | 0 | 0 |

TROIS FAITS, ET ILS SE LISENT SUR CE SEUL TABLEAU :

- LE GROS PAS FABRIQUE DE LA POPULATION. Plus le pas est fin, plus la foret
  meurt vite, et c'est monotone -- un biais systematique, pas du bruit. Meme sens
  que le defaut deja recense pour l'herbe (`SUIVI.md`, PIEGES DEJA PAYES, « TEST
  TAUTOLOGIQUE »).
- LA POPULATION D'ARBRES N'EST PAS VIABLE. A pas fidele elle s'eteint : zero
  arbre a 58 000 s. Il n'existe donc AUCUN reglage de prechauffage qui rende une
  foret durable -- ce qu'on croyait regler etait l'instant ou l'on arretait de
  regarder une extinction. La cause est dans les donnees de l'espece :
  `trouee_max_voisins = 1` (un rejet renonce des qu'UNE voisine vivante est dans
  2 cellules), une fenetre fertile d'un seul stade de 240 s, et un intervalle de
  reproduction de 240 s -- soit UNE portee par vie.
- `pas_maximal` NE TIENT PAS SA PROMESSE. Il declare 30 s comme le plus grand pas
  fidele pour l'arbre seul (le quart de 120 s, son intervalle de production), et
  a 30 s la population rend 145 arbres la ou la simulation fine en rend 0. La
  regle du quart est trop lache pour cette espece. `test_plante.gd` verrouille
  bien l'equivalence gros pas / petit pas, mais sur un cycle court : a l'echelle
  d'un ecosysteme sur 60 000 s, la garantie est fausse.

## 12. Declarer une espece change le pas de TOUTES les autres

`vegetation.gd:pas_maximal` prend le quart de la plus courte duree de toutes les
especes DECLAREES -- pas plantees, declarees.

| especes declarees | plus courte duree | pas maximal |
|---|---|---|
| arbre seul | 120 s (intervalle de production) | 30,00 s |
| arbre + herbe | 25 s (stade « brin ») | 6,25 s |

POSER UN NOEUD D'ESPECE SOUS LE COUVERT DIVISE DONC LE PAS DE TOUT LE MONDE,
sans qu'un seul individu de cette espece ne pousse. Combine au point 11, cela
suffit a faire disparaitre une foret qui tenait la veille. Effet mesure sur le
prechauffage, aucun semis d'herbe pose :

| ticks x delta | temps simule | arbres, herbe declaree | arbres, herbe non declaree |
|---|---|---|---|
| 1000 x 50 | 50 000 | 1 | 82 |
| 1000 x 30 | 30 000 | 0 | 53 |
| 500 x 30 | 15 000 | 11 | 38 |
| 300 x 30 | 9 000 | 5 | 19 |
| 200 x 30 | 6 000 | 18 | 21 |
| 300 x 10 | 3 000 | 18 | 18 |
| 200 x 10 | 2 000 | 7 | 7 |

Et le facteur purement arithmetique, qui se cumule aux deux precedents : le
temps simule est le PRODUIT ticks x delta. 1000 x 50 = 50 000 s ; 200 x 10 =
2 000 s. Vingt-cinq fois moins. A 2 000 s, deux semis d'arbre ont vecu trois
generations : 3 a 7 arbres, quel que soit le pas.
