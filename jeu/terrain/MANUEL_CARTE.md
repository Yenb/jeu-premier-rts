# MANUEL — la carte de 100 km²

Comment on s'en sert, et où vit quoi. Le POURQUOI de chaque décision est dans
l'en-tête du fichier concerné, jamais ici : ce document ne porte que l'INDEX et
les GESTES. Le journal du chantier est dans `SUIVI.md`.

## Les gestes

### Sculpter

Ouvrir `carte_100km2.tscn`. La maquette flotte au-dessus, la dalle orange
montre où tombera la fenêtre.

1. Sélectionner **`Apercu/Repere`** — la dalle orange — et la **tirer au gizmo**
   là où l'on veut travailler. Le centre de `Fenetre` suit tout seul.
   Le geste s'arrête ? La zone quittée s'enregistre, le GridMap se vide, la
   nouvelle zone se rend. Rien à cocher.
2. Sculpter : **`Sculpteur`** (boîtes : deux coins, un mode, `appliquer`),
   **`Remplisseur`**, ou le pinceau GridMap natif — sélectionner `Terrain`, le
   panneau s'ouvre en bas. **Régler *Grid Floor* à 7 pour poser au-dessus du
   sol** ; à 0 on peint six couches sous la surface, invisible.
3. **`Enregistrer`** sur `Fenetre` — ce que porte le GridMap part dans la carte
   et sur le disque.
4. **`Vider`** avant Ctrl+S — sans ça la scène embarque les cellules, mesuré à
   7,8 Mo par sauvegarde pour un contenu que la carte reconstruit.

### Repérer

`Apercu/Maquette` montre les 100 km² d'un coup, teintés par hauteur. Elle se
construit à l'ouverture ; `reconstruire` la refait après un enregistrement.
Elle n'existe **que** dans l'éditeur.

### Premier chargement, à la main

Régler `centre` sur `Fenetre`, cocher `charger`. Utile quand rien n'est encore
chargé : le déplacement automatique ne s'amorce que sur une fenêtre déjà là.

## Diagnostiquer, quand quelque chose ne va pas

Ce qui a réellement servi sur ce chantier, dans l'ordre où ça a tranché. Les
règles de fond sont dans `CLAUDE.md` § « Quand Yael dit que ça ne marche pas » ;
ici, les gestes.

**LE BANC JETABLE.** Un `.gd` de vingt lignes dans `jeu/terrain/`, lancé en
headless, qui MESURE la chose contestée et rien d'autre — puis supprimé. Six
ont été écrits ici, tous jetés. Ils ont tranché ce qu'aucun raisonnement
n'aurait tranché : que poser 630 000 cellules coûte 215 ms et que les 28
secondes suivantes sont la création des corps physiques ; que la maquette
ajoutait 1,04 Mo au fichier de scène ; que la carte ne contenait que des trous.

**UN TEST DOIT ROUGIR AVANT D'ÊTRE GARDÉ.** Écrire le jugement, casser le code
exprès, vérifier qu'il échoue, restaurer. Trois jugements de ce chantier
passaient sans rien tenir — ils comparaient une valeur à elle-même. Un test
qu'on n'a pas vu échouer ne protège rien.

**INSTRUMENTER LE VRAI CHEMIN, PAS UN BANC.** `Engine.is_editor_hint()` est
faux hors éditeur : tout ce qui ne tourne que dans l'éditeur échappe aux tests.
Le seul moyen est d'écrire dans la console à chaque étape — d'où le champ
`journal` sur les outils. Y mettre un MARQUEUR DE VERSION : l'éditeur garde en
mémoire des versions intermédiaires d'un script `@tool`, et on peut corriger
longtemps du code qui ne s'exécute pas.

**MESURER L'ÉTAT, PAS SEULEMENT LE CODE.** Quand le symptôme est « mon travail
disparaît », lire le fichier de données avant de lire le code : combien de
colonnes montées, combien creusées, sur quelle étendue. C'est ce relevé qui a
montré que la carte ne portait que des trous, et non un relief abîmé.

**CE QU'UN TEST NE DOIT JAMAIS MESURER : le contenu.** Un rayon tiré à un point
fixe, un plafond qui exige une carte vierge — les deux rougissent le jour où la
carte est travaillée, sans qu'aucun code n'ait changé. Mesurer un invariant du
code : coût par colonne sculptée, sol sous le personnage.

## L'index

| fichier | ce qu'il fait |
|---|---|
| `carte_terrain.gd` | LA DONNÉE : emprise, sommet de chaque colonne, `hauteur_du_sol`. Aucun nœud |
| `ecrire_carte_terrain.gd` | outil d'échafaudage : écrit une carte vierge (`emprise=`, `vers=`, `forcer`) |
| `terrain_visible.gd` | rend un disque de terrain autour de l'observateur, en jeu |
| `outil_fenetre.gd` | `charger` / `enregistrer` / `vider` / déplacement automatique |
| `repere_fenetre.gd` | la dalle orange : curseur déplaçable, écrit le centre de la fenêtre |
| `maquette.gd` | la vue d'ensemble, éditeur seulement |
| `terrain_commun.gd` | gestes partagés : trouver le terrain, l'emprise, la bibliothèque de jeu |
| `../objets/objets_visibles.gd` | fait basculer un objet de donnée à nœud près de l'observateur |

`carte_100km2.tres` est la carte. `carte_100km2.tscn` est la scène — sculpture
et jeu dans la même.

## La méthode, et pourquoi elle est celle-là

**Tout est donnée ; le rendu et la collision sont une couche temporaire.** La
règle complète, ses mesures et ses deux pièges sont dans `SUIVI.md` § DÉCISIONS.

Trois conséquences qui se retrouvent partout dans ces fichiers :

- **une seule source par grandeur.** La carte dit la taille de cellule et la
  hauteur du sol ; `terrain_visible` et `outil_fenetre` la lui demandent, la
  scène ne la répète pas. Le curseur ne porte ni son arête ni son centre.
- **ce que la scène transporte ne fait jamais autorité.** Cellules,
  bibliothèque, taille de cellule sont repris au lancement depuis la carte.
- **un coût se plafonne par un test, jamais par un commentaire.** Voir
  ci-dessous.

## Les tests, et ce que chacun tient

`godot --headless --script jeu/terrain/test_xxx.gd`

| test | ce qu'il rend impossible |
|---|---|
| `test_carte_terrain` | qu'une carte vierge pèse selon son emprise ; qu'une lecture coûte selon ce qui est sculpté |
| `test_terrain_visible` | que le compte de cellules suive la carte ; qu'un nœud traîne derrière l'observateur |
| `test_scene_carte` | que la scène perde son câblage ; qu'un sol rendu ne collisionne pas |
| `test_outil_fenetre` | qu'un enregistrement creuse ce qui n'a pas été chargé, ou oublie ce qui est sculpté ailleurs |
| `test_maquette` | que la vue d'ensemble relise l'emprise ; qu'elle tienne à un seul `_ready` |
| `test_repere_fenetre` | que le curseur porte une donnée en double ; qu'il dépende de son parent |
| `../objets/test_objets_visibles` | que le nombre de nœuds suive la population ; qu'un objet flotte ou s'enfonce |

**Ce qu'aucun ne voit** : voir ci-dessus, « instrumenter le vrai chemin ».

## Les mesures qui servent de repère

Prises sur Godot 4.7.1, à relever de nouveau si le moteur change.

| | |
|---|---|
| carte vierge, 25 M de colonnes | 185 octets |
| GridMap plein, même emprise | 16,5 o/cellule, soit ~2,9 Go |
| traverser 9,6 km en jeu | 19 747 cellules, invariant |
| charger une fenêtre de 600 m | 547 ms — 28 000 ms si la bibliothèque porte ses collisions |
| maquette, carte vierge | 10 ms ; +0,66 µs par colonne sculptée |
| 10 000 objets semés | 5 nœuds vivants au plus |
