# SUIVI

Journal de bord de la programmation du jeu. SEUL document que Claude Code
modifie au fil des sessions.

Cinq sections, jamais d'autre. FAIT : une ligne par étape terminée, la plus
récente en tête, hash de commit si applicable — sinon la date — puis quoi, en
une phrase. EN COURS : ce qui est ouvert maintenant, un tiret par point.
DÉCISIONS : les choix pris en session qui ne sont écrits ni dans `CLAUDE.md` ni
dans le code ; une décision SORT d'ici dès qu'elle est écrite ailleurs.
PROCHAINES ÉTAPES : ce qui vient après, dans l'ordre. PIÈGES DÉJÀ PAYÉS :
autorisé explicitement par Yael, contre la règle du récit — un piège coûte deux
fois si personne ne l'a écrit. Symptôme, cause, règle. Jamais l'histoire.

## FAIT

- 2026-08-18 — Couvert MULTI-ESPÈCES et pression écologique : une RESSOURCE par
  espèce (`jeu/plantes/arbre.tres`, `herbe.tres`, décrites par `espece.gd` et
  `stade.gd`), déclarées sur le nœud Couvert et réglées à l'inspecteur —
  sélecteur de fichier compris pour les modèles ; un semis les réclame par son
  champ `Type`. Trois contraintes distinctes — la densité borne le
  nombre, l'OMBRE PAR STATURE tranche qui l'emporte, la TROUÉE décide qui peut
  s'installer où. Une herbe basse n'ombrage jamais un arbre et se fige sous
  n'importe lequel ; un rejet d'arbre renonce dans un tapis d'herbe dense, un
  rejet d'herbe non. Plafond de couche par espèce, et touffe fabriquée à
  l'exécution pour une espèce sans modèle
- 2026-08-18 — SUCCESSION : la mort ne regarde plus la lumière. Deux horloges —
  l'âge de CROISSANCE se fige à l'ombre et commande le stade, l'âge RÉEL avance
  toujours et commande la fin. Les confondre rendait les dominées IMMORTELLES
  (mesuré : une herbe sous un arbre encore vivante dix vies plus tard, âge zéro) :
  elles occupaient leur colonne et le plafond de densité pour toujours, et la
  forêt ne pouvait plus reprendre un sous-bois qui ne se vidait jamais. Mesuré
  après : à réglages identiques, les arbres passent de 0 à 4, et de 0 à 30 en
  desserrant leur trouée — la prairie s'installe vite, la forêt la remplace
  lentement, et une trouée d'arbre mort se recouvre d'herbe avant de redevenir
  forêt
- 2026-08-18 — UN SEMIS PAR ESPÈCE : `jeu/plantes/arbre.tscn` et `herbe.tscn`,
  scènes dérivées de `plante.tscn`, chacune avec son espèce déjà renseignée et son
  propre carré coloré. Le game designer choisit ce qu'il plante en choisissant la
  scène, plus en tapant un nom — une faute de frappe retombait en silence sur
  l'espèce par défaut. Les RÉGLAGES restent sur le nœud d'espèce sous le Couvert,
  un seul endroit par espèce : poser cent semis ne fait pas cent copies d'une
  durée à tenir d'accord
- 2026-08-18 — Couvert OPTIMISÉ d'un facteur ~4000 : le tick passe de la
  fréquence d'images à un pas FIXE de 2 s (mesuré : les éclaircies durent 9 s en
  médiane, un pas plus grand les raterait et ferait sous-pousser les plantes en
  concurrence), et l'ombre devient une valeur PORTÉE par chaque plante, relue
  seulement autour des trois événements qui peuvent la changer — mort, changement
  de stade, naissance. Mesuré : 1,1 ombre relue par tick au lieu de toutes.
  `vegetation.gd:retirer` est le geste qui ôte une plante du dehors en prévenant
  son voisinage ; `test_plante.gd` compare à chaque tick l'ombre portée à l'ombre
  recalculée entièrement. Le compte de voisins est porté de la même façon et
  vérifié par le même test — `peut_pousser` ne fait plus aucune requête
- 2026-08-18 — PRÉCHAUFFAGE du couvert : `couvert.gd` exporte un nombre de ticks
  joués avant la première image, rendu compris ; le joueur arrive sur une
  végétation déjà vécue au lieu d'un terrain nu. Aucune mécanique neuve — c'est la
  fonction de tick existante appelée en boucle. `test_plante.gd` verrouille que
  N ticks d'avance plus M normaux rendent le même état que N+M normaux, ce qui
  prouve surtout que `_process` ne simule rien de son côté. Le pas de temps est
  DÉCOUPÉ en tranches déduites des durées les plus courtes (`pas_maximal`) :
  sans ça un pas de 30 s rendait trois fois plus d'herbe qu'un pas de 1 s et
  sautait des stades — accélérer changeait le monde. Le premier test comparait
  N + M ticks à N+M ticks au MÊME pas : il prouvait une tautologie
- 2026-08-18 — Couvert VÉGÉTAL, premier gameplay du jeu : `jeu/plantes/` — des
  graines posées à la main qui traversent trois stades, changent de modèle 3D à
  chacun, déposent une graine ramassable au sol, se reproduisent au seul stade
  mature et meurent de vieillesse ; une plante dominée par une voisine plus
  avancée se fige et repart quand celle-ci meurt ; aucune mécanique écrite,
  `vegetation.gd`
  compose `senescence.gd` (dont le facteur nul fige un dominé), `stade.gd`,
  `seuil_etat.gd`, `gestation.gd` et
  `monde.gd` sur des catalogues LOCAUX au format des partagés, et
  `surface_terrain.gd` traduit le GridMap en cases une seule fois. Tous les
  réglages sont exportés par `couvert.gd` et surchargent `vegetation.json` sans
  que la simulation connaisse le nœud ; verrouillé par
  `jeu/plantes/test_plante.gd`, qui refuse aussi que l'inspecteur et le fichier
  divergent
- 2026-08-17 — Bloc RAMPE : `jeu/terrain/bloc.tres` porte un troisième item, un
  prisme triangulaire de 2 m plus sombre que le bloc plein, avec une
  ConvexPolygonShape3D qui épouse ses six sommets ; verrouillé par
  `jeu/terrain/test_rampe.gd`, qui mesure la pente au rayon sur une rampe posée
  et exige que le demi-tour du GridMap l'inverse
- 2026-08-17 — Limite de carte INVISIBLE : `jeu/terrain/generer_murs.gd`, script
  headless relançable qui pose 22 couches de murs sur les quatre bords, une
  cellule au-delà de l'emprise sculptable, avec l'item qui collisionne sans se
  rendre ; il relit la scène pour prouver que la sculpture est intacte
- 2026-08-17 — Terrain solide : `jeu/terrain/bloc.tres` porte deux items, le
  bloc visible et la limite sans maillage, tous deux avec une BoxShape3D de 2 m
  que le GridMap applique à toutes ses cellules d'un coup ; verrouillé par
  `jeu/terrain/test_collision_terrain.gd`, un témoin qui tombe et un témoin
  lancé vers le bord
- 2026-08-17 — Philosophie de facturation, personnalisation des unités, races
  comme pente et asymétrie des cartes documentées : `jeu/GAME_DESIGN.md`
- 2026-08-17 — Mécaniques du terrain destructible documentées (conservation
  des masses, cohésion par matériau, fissure puis effondrement, étayage) :
  `jeu/GAME_DESIGN.md` § Terrain destructible
- 2026-08-17 — Remplissage des contours : `jeu/terrain/outil_remplissage.gd`,
  script `@tool` qui lit une couche et comble les zones qu'elle enferme ;
  gestes partagés des outils dans `jeu/terrain/terrain_commun.gd`
- 2026-08-17 — Sculpture en masse : `jeu/terrain/outil_sculpture.gd`, script
  `@tool` qui remplit ou creuse une boîte de cellules depuis l'inspecteur
- 2026-08-16 — Terrain sculptable : GridMap de cubes de 2 m centré sur
  l'origine, bloc plein de 128×128×7 couches, `jeu/terrain/` — scène
  principale du projet
- 2026-08-16 — Création de `jeu/GAME_DESIGN.md`, principes fondateurs posés
- 2026-08-16 — Création du `CLAUDE.md` et du `SUIVI.md` du jeu
- 2026-08-16 — Architecture LLM décidée : micro-modèle stratégie + micro-modèle
  discussion (plus tard) + agents mémoire côté code
- 2026-08-16 — Modèle choisi : Llama 3.2 3B via Ollama
- 2026-08-16 — Connexion LLM prouvée (`banc_llm_connexion.gd`, réponse reçue)

## EN COURS

- `jeu/terrain/test_carte.gd` est ROUGE (12 échecs) : il verrouille le compte
  exact de cellules, l'absence de relief, l'emprise stricte et une bibliothèque
  à un seul item — que la carte actuelle dément point par point. À recentrer sur
  ce qui reste invariant : pas de grille, caméra,
  lumière, et chaque item de la bibliothèque porte sa forme de collision
- `jeu/terrain/generer_carte.gd` reconstruirait une bibliothèque à un seul item
  SANS collision : relancé avec « forcer », il rendrait le terrain traversable
  et effacerait la limite de carte, en silence

## DÉCISIONS

- OPTIMISER EST UN CRITÈRE PERMANENT, pas un chantier de fin. Les cartes
  grandiront, et ce qui tient à cent objets casse à mille : toute mécanique
  écrite désormais s'évalue AUSSI sur son coût à grande échelle, et se mesure
  avant d'être déclarée tenable. Deux leçons déjà payées, à ne pas repayer — un
  tick calé sur la fréquence d'images faisait soixante évaluations par seconde
  pour des plantes qui changent toutes les vingt-cinq secondes ; et un état
  spatial redemandé à chaque tick découvrait 99,6 % du temps qu'il ne s'était
  rien passé. Les deux se voient en MESURANT, jamais en relisant le code

- Le terrain est un GridMap : un objet d'AFFICHAGE et d'édition, que la
  simulation ne lit pas. Le pont vers les cases-objets qu'exige `design.md` est
  écrit et tient dans un seul fichier — voir `jeu/plantes/surface_terrain.gd`,
  seul du jeu à connaître GridMap. Les cases n'entrent PAS dans le Monde :
  `monde.gd` balaie linéairement, et une carte entière y rendrait chaque requête
  de voisinage proportionnelle au terrain. La collision du GridMap n'entame rien :
  elle n'est lue que par le moteur physique de Godot, jamais par un mécanisme
- Le résumé d'état est une photo complète à chaque appel, pas d'historique
  cumulé
- Le modèle de discussion est séparé du modèle de stratégie
- Plan de repli : si la machine du joueur ne tient pas, mêmes modèles sur
  serveur, même code d'appel

## PROCHAINES ÉTAPES

1. Trancher le point ouvert de `jeu/GAME_DESIGN.md` § Terrain destructible :
   chercher si un mécanisme du cœur porte déjà la connexité de voisinage, sinon
   ouvrir le chantier framework
2. Le coût restant du couvert est `monde.gd:choses_dans_rayon`, qui balaie TOUTES
   les plantes à chaque requête — mesuré : 155 ms par tick à 1 128 plantes, soit
   78 ms par seconde réelle. Le jeu a donné ce qu'il pouvait (facteur ~350) ;
   l'ordre de grandeur suivant demande un index spatial DANS `monde.gd`, donc un
   chantier FRAMEWORK. `perception.gd` le dit lui-même : « si un appelant réel
   dépasse ~50 candidats par requête, le signaler plutôt que d'ajouter une
   structure d'accélération en silence ». C'est signalé
3. Câbler le ramassage des graines par les unités : `vegetation.gd:ramasser` et
   `couvert.gd:retirer_graine` sont posées et testées, personne ne les appelle —
   `consommer.gd` est le mécanisme qui attend, il transfère entre deux choses
4. Second banc LLM avec grammaire GBNF contrainte
5. Carré rouge (joueur) + carré violet (IA) + caméra scrollable
6. Premier Modelfile agent stratégie avec system prompt
7. Boucle complète : état → résumé → modèle → clé → action visible

## PIÈGES DÉJÀ PAYÉS

Ce que le prochain chantier de couvert doit savoir avant d'écrire une ligne. Un
seul de ces pièges a coûté une demi-session ; tous ont été payés une fois.

- FAUX VERT — un test qui imprime `OK` alors qu'un objet ne s'est pas
  instancié. `Couvert.new()` rend `null` quand le script ne compile pas, et les
  jugements qui en dépendaient étaient SAUTÉS sans un mot. Règle : un objet qui
  ne s'instancie pas ROUGIT, il ne se saute jamais.
- SCRIPT QUI NE REND PAS LA MAIN — un `--headless --script` qui dépasse la
  minute n'est pas lent : il ne compile pas, le `SceneTree` ne quitte jamais.
  Ne pas attendre, lire l'erreur.
- TEST TAUTOLOGIQUE — le préchauffage comparé à lui-même AU MÊME PAS DE TEMPS
  prouvait seulement que l'addition est commutative. Mesuré ensuite : un pas de
  30 s donne TROIS FOIS plus d'herbe qu'un pas fin. Règle : un test
  d'équivalence qui ne fait pas varier ce qu'il prétend rendre indifférent ne
  teste rien. D'où `pas_maximal` et le découpage en tranches.
- MORT BRANCHÉE SUR LA MAUVAISE HORLOGE — voir la ligne FAIT du 2026-08-18.
  Symptôme trompeur : tous les tests verts, et zéro arbre à l'écran.
- CADAVRE QUI FAIT ENCORE DE L'OMBRE — `monde.gd` garde les disparues un tick.
  Toute lecture du monde double-filtre les mortes. Précédent framework :
  `banc_parasites_reproduction.gd`.
- FENÊTRE FERTILE PLUS COURTE QUE L'INTERVALLE — une espèce fertile à 25 s et
  morte à 100 s n'a que 75 s pour semer ; un intervalle de 80 la rend stérile,
  verte à tous les tests de cycle. Le test de reproduction exige une SECONDE
  plante, jamais un cycle qui se déroule bien.
- MODÈLE GLB NON CENTRÉ — les `.glb` sont sortis du modeleur avec l'origine à
  côté (jusqu'à 20 m), les plantes sautaient en grandissant. Invisible aux
  tests : `couvert.gd` n'en avait aucun. Recentrage à l'exécution, et une
  assertion de géométrie dans le test.
- OPTIMISER SANS MESURER — l'hypothèse « les colonnes prises sont le goulot »
  était fausse : 163 ms → 155 ms. Mesurer d'abord, toujours.
- DEUX ÉCRIVAINS SUR `carte.tscn` — la sauvegarde de l'éditeur ouvert écrase le
  fichier écrit à côté. Quand Godot est ouvert, les valeurs se dictent, elles ne
  s'écrivent pas.
