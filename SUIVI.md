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

- bbab9b6 — BANC TEST_ENNEMI complet : gisement (500 métal, se détruit à zéro),
  transporteurs qui prospectent (perception+saillance, vision 5 m, marche
  aléatoire, cognent, rapportent), cube violet (vie 50, stock 200 max) qui se
  reproduit à 30 métal, transporteur qui cherche un autre cube quand sa mère est
  pleine, mode combat DÉCLENCHÉ à la frappe et PERSISTANT jusqu'à la naissance
  du soldat (aucun timer), signal aux voisins dans 15 m, soldat rouge (20 vie,
  vitesse 3, dégâts 10) territorial (rayon 10 m du cube parent), mémoire de
  cible via `scripts/lien_personnel.gd` du framework (magnitude 1.0, décroissance
  0.4/s, plancher 0.05 → ~3 s de traque après perte de vue), joueur (100 vie,
  barre HUD 2D, reload de scène à zéro). Composant `PresenceDansMonde`
  générique. Framework composé partout, rien inventé sur les mécaniques.
- LOGBOOK.md : le mécanisme qui nommera au joueur ce que le système produit,
  décide les 4 conditions (rare, composé, conséquent, nommable) et écarte deux
  fausses pistes (IA narrateur, journal joueur). Rien d'implémenté encore
- `jeu/Ennemie/` et `jeu/terrain/test_ennemi.tscn` déplacés dans
  `jeu/Outil de jeu/` (regroupement du banc), tous les paths mis à jour dans les
  13 fichiers concernés. Vérifié : la scène charge, ses 14 nœuds sont là
- LE RAFRAICHISSEMENT DU TERRAIN EN JEU S'ETALE SUR PLUSIEURS IMAGES.
  `terrain_visible.gd` posait et effaçait toute la couronne d'un seuil franchi
  en un seul appel synchrone — MESURÉ à 12,5 ms pour 796 colonnes au rayon et
  au pas de jeu (rayon 50, pas 4), soit les trois quarts d'une image à 60
  i/s, à CHAQUE fois que le joueur avance de huit mètres : le freeze régulier
  en marchant. `_retargeter`/`_avancer_file` mettent deux files (`_a_poser`,
  `_a_effacer`) à jour sans jamais les vider ni les recréer — un demi-tour
  avant la fin d'un étalement annule le travail en attente au lieu de le
  refaire — et `_process` n'en draine que `colonnes_par_image` (120, sous
  2 ms) par image. `rafraichir()` reste inchangée, synchrone, verrouillée par
  les tests existants ; c'est elle qui pose le tout premier affichage
- L'ARCHIVISTE MANQUAIT DANS `carte_100km2.tscn` : aucun noeud ne portait
  `archiviste.gd`, donc rien de ce qui était sculpté ne s'écrivait jamais sur
  le disque, quel que soit le temps passé — seul `Ctrl+S` de la scène
  transportait quoi que ce soit, et de façon coûteuse (voir plus bas). Nœud
  ajouté, cablé sur `carte_100km2.tres`
- LA MAQUETTE N'A PLUS DE RELIEF PAR DEFAUT : `relief` (faux par defaut) pose
  chaque echantillon au sommet par defaut de la carte, quelle que soit la
  sculpture reelle. Personne ne marche sur la maquette, elle sert a s'orienter,
  pas a previsualiser un denivele. Avant ce drapeau, un ecart de quelques
  couches sur une carte presque plate s'etirait sur toute la gamme de couleur
  et se peignait en blanc pur, comme un sommet. `etendue_minimale` (plancher
  d'ecart avant d'atteindre la teinte du haut) reste pour le jour ou `relief`
  repasse a vrai
- 4c1116c — LE CURSEUR CHARGE ENCORE APRES REOUVERTURE : `fenetre_chargee`
  redevient exporte ; la protection contre le creusement automatique n'est plus
  le drapeau mais `_colonnes_chargees`, transmis à `enregistrer_ce_qui_est_pose`
  pour n'effacer que ce qu'on sait avoir charge. Corrige l'effet de bord de
  9500437 : tirer le repere ne chargeait plus rien apres reouverture de la
  scene, sans aucune erreur pour le dire
- 2026-08-20 — CARNET DE JEU : `jeu/CARNET_DE_JEU.md`, l'index de ce que le jeu
  sait faire — les quatre couches, les scènes lançables, les cinq domaines, les
  leviers de réglage, ce qui est écrit sans être appelé, et où se prend chaque
  décision
- e1371d7 — CE QUE LA SCÈNE PORTE EST REPRIS AU LANCEMENT. `terrain_visible`
  effaçait le GridMap sans le lire : tout ce qui n'avait pas transité par
  l'éditeur était perdu, et ce transit tenait à quatre conditions dont aucune ne
  se signale quand elle manque. Il PREND, il écrit dans la carte, PUIS il
  efface. Sculpter sans avoir chargé de fenêtre s'enregistre aussi
- 4b09b41 — UNE SEULE COUCHE ÉCRIT LE MONDE : `jeu/monde/registre.gd` porte
  « ai-je changé ? », `archiviste.gd` porte « alors je t'écris ». Ajouter une
  sorte de donnée au monde ne demande aucune ligne d'écriture — voir
  MANUEL_CARTE.md
- 21393bb — LA CARTE EST UN VOLUME : chaque colonne porte le MASQUE de ses
  couches pleines, pas sa hauteur. Grottes, ponts, surplombs et niveaux séparés
  deviennent représentables, ce dont dépend tout le terrain destructible
- 5f41a86 — ENREGISTRER CONSERVE CE QUI EST SCULPTÉ HORS DES COLONNES CHARGÉES.
  La garde de a054506 bloquait toute colonne non chargée, y compris celles que
  la grille PORTE : le bouton creusait avant, il oubliait après. Elle ne
  s'applique plus qu'aux colonnes absentes de la grille. Mode d'emploi et index
  du terrain : `jeu/terrain/MANUEL_CARTE.md`
- a054506 — ENREGISTRER NE CREUSE PLUS CE QUI N'A JAMAIS ÉTÉ CHARGÉ. Le
  chargement retient les colonnes qu'il a réellement traitées ; l'enregistrement
  n'écrit que celles-là. Une colonne absente du GridMap comptait comme VIDE, et
  « absente » avait deux causes que rien ne distinguait — creusée par le
  sculpteur, ou jamais chargée. Voir PIÈGES
- e39ef42 — CARTE DE 100 km² : `carte_terrain.gd` porte l'emprise et le sommet
  de chaque colonne, sans nœud ni GridMap ; vierge elle pèse 185 octets pour
  25 millions de colonnes, contre 16,5 octets par cellule pour un GridMap plein.
  `terrain_visible.gd` ne rend qu'un disque autour de l'observateur — traverser
  9,6 km laisse 19 747 cellules, du premier au dernier pas. `outil_fenetre.gd`
  sculpte par fenêtre de 600 m, posée LÀ OÙ ELLE EST sur la carte, et déplacer
  le curseur enregistre la zone quittée avant de rendre la suivante ;
  `maquette.gd` montre les 100 km² d'un coup en ne relisant que ce qui est
  sculpté. `jeu/objets/objets_visibles.gd` fait basculer un objet de donnée à
  nœud près de l'observateur : 10 000 objets semés, 5 nœuds vivants au plus.
  Chaque carte porte son emprise, ce qui ferme le premier point EN COURS

- 2026-08-19 — DISTANCE DE RENDU PAR ESPÈCE : `espece.gd` porte un
  `distance_rendu` que `couvert.gd` pose en `visibility_range_end` sur CHAQUE
  `GeometryInstance3D` du corps instancié — un `.glb` est un `Node3D` qui en
  porte plusieurs plus bas, la poser sur la racine ne toucherait rien. Godot
  cesse de dessiner au-delà et c'est la CAMÉRA qui décide : aucun objet n'a
  besoin de savoir où est le joueur, donc rien à remplir sur mille types. À zéro
  rien n'est écrit — une scène existante ne change pas de comportement. Elle ne
  libère AUCUN nœud et ne touche PAS le tronc solide : un arbre qu'on ne voit
  plus barre toujours le passage. Mesuré à côté : un nœud de plante pèse 5,1 Ko
  (herbe) à 9,6 Ko (arbre), et `visibility_range_end` n'en rend pas un octet
- 2026-08-19 — GRANDE CARTE 300×300 : `jeu/terrain/grande_carte.tscn`, scène
  NEUVE — 630 000 cellules d'emprise plus 26 488 de ceinture, 10,7 Mo. Aucun
  outil neuf : `DEMI_COTE` passe de 64 à 150 et les quatre outils s'ouvrent d'un
  coup, c'est la seule déclaration de l'emprise. Deux outils gagnent
  `vers=<chemin>` — sans lui, une carte d'une autre taille ne s'obtient qu'en
  écrasant celle qui existe. Et `generer_carte.gd` RELIT la bibliothèque quand
  elle est sur le disque au lieu de la réécrire : il ne sait construire qu'un
  item, `bloc.tres` en porte trois, et les écraser aurait vidé toute cellule
  portant `limite` ou `rampe` — dans `carte.tscn` comme ailleurs. Mesuré :
  chargement 710 ms, instanciation 508 ms, relevé 217 ms pour 91 204 colonnes,
  contre 306/105/40 et 16 900 sur l'ancienne. Coût de démarrage, jamais de tick
- 2026-08-19 — VISÉE À LA SOURIS : le déplacement horizontal fait pivoter le
  CORPS, le vertical incline les YEUX SEULS — une capsule inclinée glisse sur le
  terrain au lieu de s'y tenir. L'inclinaison s'accumule (une souris rend un
  déplacement, jamais une position) et reste sous le quart de tour, sinon
  l'image se retourne et le lacet part à l'envers de ce que le joueur voit. Le
  curseur se prend au PREMIER CLIC et jamais au démarrage — capturé d'office il
  est pris avant qu'on ait rien demandé, à chaque lancement ; Échap le rend.
  Quatre fonctions statiques de plus, verrouillées sans souris ni moteur physique
- 1a764b4 — PERSONNAGE ARPENTEUR : `jeu/unites/personnage.tscn`, une capsule d'un
  mètre — une demi-cellule, et c'est ce rapport qui donne l'échelle à tout le
  reste. Haut/bas avancent, gauche/droite TOURNENT ; sans souris, tourner est le
  seul moyen de regarder ailleurs. Le calcul sort de `_physics_process` en
  fonctions statiques, verrouillées sans clavier ni moteur physique
- 45b3a4a — TRONC SOLIDE : une espèce qui déclare un `rayon_collision` reçoit un
  cylindre de ce rayon, haut comme la stature de son stade, échangé avec le
  modèle. C'est le fût, pas l'arbre — on circule sous la canopée. À rayon nul
  aucun corps n'est posé, et c'est le défaut : l'herbe reste traversable sans
  qu'une ligne ne la nomme
- 8818c26 — DISPERSION ET DENSITÉ PAR ESPÈCE : où tombent les rejets et combien
  de voisines une plante supporte étaient communs, si bien qu'un tapis d'herbe
  serré aurait fait des arbres serrés. Le rayon de comptage reste commun — il
  choisit le rayon de rafraîchissement de tout le couvert
- 7b715cb — REQUETE SPATIALE corrigee dans `scripts/monde.gd` : les choses sont
  rangees par case, a plusieurs resolutions nees a la demande, et une requete ne
  lit plus que les cases que son rayon touche. Mesure : 512 076 tests de distance
  par tick a 1 000 plantes, tombes a ~7 100. Le contrat change — une chose qui
  bouge le declare par `deplacer()`. Mesures completes :
  `jeu/plantes/MESURES_COUVERT.md`
- 7b715cb — Premier commit du contenu, et depot distant du jeu :
  `https://github.com/Yenb/jeu-premier-rts`

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

- LA CHAÎNE ÉDITEUR N'EST PARCOURUE PAR AUCUN TEST — voir PIÈGES, « ce qu'un
  banc headless ne voit pas ». Trois défauts s'y sont succédé sans qu'aucun ne
  rougisse
- TROIS FICHIERS DE `carte_prototype.tscn` NE VIENNENT PAS DE CETTE SESSION :
  `murs_limite.gd`, `semer_objets.gd`, `carte_prototype.tres`. À rattacher à un
  chantier avant d'y écrire — un fichier, un écrivain
- `carte_100km2.tscn` embarque les cellules du GridMap dès qu'on enregistre la
  scène en cours de sculpture — 7,8 Mo par sauvegarde, pour un contenu que la
  carte reconstruit. « vider » avant Ctrl+S le ramène à 3 Ko ; rien ne le force
- LES TRACES DE DIAGNOSTIC sont actives : `journal` exporté sur les outils

- UNE EMPRISE, DEUX CARTES DE TAILLES DIFFÉRENTES — à trancher avant tout
  chantier de terrain. `DEMI_COTE` est un nombre unique et vaut désormais 150,
  alors que `carte.tscn` porte une ceinture à 64 : `test_collision_terrain.gd`
  passe de VERT à ROUGE parce qu'il cherche le mur de l'ancienne carte à la
  nouvelle emprise. Deux issues, aucune bricolable au passage — refaire
  `carte.tscn` à 300×300 et n'en garder qu'une, ou sortir l'emprise du
  générateur pour qu'elle se lise SUR LA SCÈNE, chaque carte portant la sienne
- `jeu/terrain/test_carte.gd` est ROUGE (12 échecs) : il verrouille le compte
  exact de cellules, l'absence de relief, l'emprise stricte et une bibliothèque
  à un seul item — que la carte actuelle dément point par point. À recentrer sur
  ce qui reste invariant : pas de grille, caméra,
  lumière, et chaque item de la bibliothèque porte sa forme de collision
- `jeu/terrain/generer_carte.gd` reconstruirait une bibliothèque à un seul item
  SANS collision : relancé avec « forcer », il rendrait le terrain traversable
  et effacerait la limite de carte, en silence

## DÉCISIONS

- TOUT EST DONNÉE ; LE RENDU ET LA COLLISION SONT UNE COUCHE TEMPORAIRE. Vaut
  pour TOUT objet à venir, pas seulement le terrain. Loin du joueur, un objet
  n'a ni nœud ni corps physique : il est une position et des propriétés, et
  l'altitude du sol sous lui se LIT dans la carte — `carte_terrain.gd:sommet`,
  temps constant, mesuré à 0,66 µs, sans rien de chargé. Près du joueur il
  devient un nœud avec collision, posé à cette même altitude ; quand le joueur
  s'éloigne le nœud est libéré et la donnée reste. La simulation ne dépend
  d'aucune des deux couches et ne s'arrête jamais. `terrain_visible.gd`
  applique déjà exactement ça au terrain — traverser 10 km y laisse le compte
  de cellules identique au premier pas.
  CHARGER LA COLLISION PARTOUT EST ÉCARTÉ : c'est revenir aux 175 millions de
  cellules que toute cette architecture existe pour éviter.
  DEUX PIÈGES À TENIR LE JOUR OÙ UN OBJET BASCULE. La hauteur portée par la
  donnée et le sol rendu viennent de la MÊME source, sinon l'objet apparaît
  enfoncé ou en l'air. Et un objet qui devrait tomber pendant que personne ne
  le regarde n'a AUCUNE physique pour le faire : sa chute se calcule en
  données, ou elle n'a pas lieu — décision de game design, pas de technique.
  CE QUE ÇA COÛTE, ET POURQUOI C'EST TENABLE : le compte de nœuds vaut
  `π·r² × densité`, donc doubler le rayon coûte quatre fois et agrandir la carte
  coûte zéro. À la densité d'herbe mesurée (0,0185 plante/m²) : 23 plantes à
  20 m, 581 à 100 m. Deux millions d'agents portent le même nombre de nœuds que
  deux mille — le seul terme qui suive la population totale est la donnée.
  RIEN N'EST À DÉFAIRE POUR Y ARRIVER : `monde.gd` et `vegetation.gd` sont des
  Dictionary et des fonctions, sans Node ni `_process`. « Tout simulé, rien
  rendu » est l'état de DÉPART. Les couches à nœuds sont `couvert.gd`,
  `terrain_visible.gd` et `objets_visibles.gd` ; le nœud lit la donnée, la
  donnée n'a jamais connaissance du nœud.

- LE NŒUD COÛTE DE LA MÉMOIRE, ET C'EST TOUT. Mesuré sur les formes que
  `couvert.gd` fabrique : `Node3D` seul 1,4 Ko ; + `MeshInstance3D` (une herbe)
  5,1 Ko ; + `StaticBody3D` + `CollisionShape3D` (un arbre) 9,6 Ko. En temps,
  11,7 µs pour fabriquer un arbre — poser mille plantes coûte 12 ms, une fois.
  Donc le mur du rendu est la MÉMOIRE, jamais la fabrication
- `visibility_range_end` CACHE, IL NE LIBÈRE PAS. Propriété de tout
  `GeometryInstance3D`, la caméra décide seule, aucun objet n'a besoin de savoir
  qui est le joueur — c'est la réponse généraliste pour ne pas DESSINER. Mais le
  nœud reste, et ses 9,6 Ko avec lui. Tenir l'échelle demande de SUPPRIMER le
  nœud, ce qui exige de savoir où est l'observateur : par GROUPE
  (`get_first_node_in_group`), jamais un champ à remplir sur chaque type
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
  seul du jeu à connaître GridMap. Les cases n'entrent PAS dans le Monde — non
  plus parce que `monde.gd` balaierait tout, il range par case et son coût suit
  le rayon, mais parce qu'y verser le terrain mettrait une case-objet PAR
  COLONNE dans chaque case que le rayon touche : un comptage de plantes paierait
  le terrain de son rayon, où les colonnes dépassent les plantes de plusieurs
  ordres. Le relevé se lit par colonne, en temps constant, sans aucun rayon à
  parcourir. La collision du GridMap n'entame rien :
  elle n'est lue que par le moteur physique de Godot, jamais par un mécanisme
- Le résumé d'état est une photo complète à chaque appel, pas d'historique
  cumulé
- Le modèle de discussion est séparé du modèle de stratégie
- Plan de repli : si la machine du joueur ne tient pas, mêmes modèles sur
  serveur, même code d'appel

## PROCHAINES ÉTAPES

1. OBJETS EN DONNÉES, NŒUDS PRÈS DU JOUEUR : le mécanisme qui fait basculer un
   objet de donnée à nœud (rendu plus collision) quand le joueur approche, et
   l'inverse quand il s'éloigne. La règle est tranchée — voir DÉCISIONS, « tout
   est donnée » — et le terrain l'applique déjà ; rien ne le fait encore pour
   les objets. Patron à recopier : `couvert.gd`, seule couche à nœuds du jeu
1. Trancher le point ouvert de `jeu/GAME_DESIGN.md` § Terrain destructible :
   chercher si un mécanisme du cœur porte déjà la connexité de voisinage, sinon
   ouvrir le chantier framework
2. Câbler le ramassage des graines par les unités : `vegetation.gd:ramasser` et
   `couvert.gd:retirer_graine` sont posées et testées, personne ne les appelle —
   `consommer.gd` est le mécanisme qui attend, il transfère entre deux choses
3. Second banc LLM avec grammaire GBNF contrainte
4. Carré rouge (joueur) + carré violet (IA) + caméra scrollable
5. Premier Modelfile agent stratégie avec system prompt
6. Boucle complète : état → résumé → modèle → clé → action visible

## PIÈGES DÉJÀ PAYÉS

- TROIS COPIES DE LA MÊME CHOSE, ET UNE SEULE QUE LE JEU LIT. Le GridMap de la
  scène, la carte, le fichier de scène : on sculpte dans le premier, le jeu ne
  lit que la deuxième, et Ctrl+S écrit la troisième. Symptôme : le travail
  disparaît au lancement, trois fois de suite, pour trois raisons différentes.
  Règle : ce qui n'est pas la source de vérité doit être REPRIS avant d'être
  effacé, jamais jeté — et le chemin de reprise ne doit dépendre d'aucune
  condition qui ne se signale pas quand elle manque.
- UN MÉCANISME QUI N'A DE SENS QU'À GRANDE ÉCHELLE NE DOIT PAS CONDITIONNER LE
  RESTE. L'enregistrement exigeait qu'une fenêtre soit chargée — un geste qui ne
  sert que sur une carte de 100 km². Sur 200 m, tout tient à l'écran, personne
  ne le fait, et le travail était perdu sans une erreur.
- ÉCRIRE UNE FENÊTRE ENTIÈRE CREUSE CE QU'ELLE NE PORTE PAS. Symptôme : le
  terrain devient un damier de zones vides, et tout ce qui est sculpté
  disparaît — mesuré à 259 530 colonnes creusées, zéro relief monté. Cause : une
  colonne absente du GridMap compte comme VIDE, et « absente » a deux causes
  qu'il faut distinguer — creusée par le sculpteur, ou jamais chargée. Règle :
  ce qu'un chargement n'a pas traité ne s'écrit pas ; l'ensemble des colonnes
  posées se retient, il ne se déduit pas de l'emprise demandée.
- UN CENTRE RELU APRÈS UNE ATTENTE N'EST PLUS CELUI QU'ON A POSÉ. Une pose
  étalée sur plusieurs frames rend la main entre deux tranches, et ce qui
  pilotait a pu changer pendant. Règle : figer au début ce sur quoi on travaille,
  et ne jamais le relire à la fin pour annoncer ce qu'on a fait. Aucun test ne
  tient ce point — lancé depuis un test, le chargement se termine avant qu'on
  ait pu bouger quoi que ce soit.
- UN TEST QUI VISE UN POINT FIXE FINIT PAR MESURER LE TRAVAIL DU SCULPTEUR. Un
  rayon tiré à l'origine, un plafond qui exige une carte vierge : les deux
  rougissent le jour où la carte est travaillée, sans qu'aucun code n'ait
  changé. Règle : mesurer un invariant du code — coût par colonne sculptée,
  sol sous le personnage — jamais un état du contenu.
- CE QU'UN BANC HEADLESS NE VOIT PAS. `Engine.is_editor_hint()` est faux hors
  éditeur : tout ce qui ne s'exécute que dans l'éditeur — construction d'une
  vue d'outil, script `@tool` sur une ressource — n'est parcouru par aucun test
  lancé en ligne de commande. Règle : le dire AVANT de montrer un test vert, et
  vérifier le mode du script (`Script.is_tool()`) au lieu d'attendre l'erreur
  « placeholder instance ».

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
- UNE JUSTIFICATION RECOPIÉE PÉRIME EN SILENCE. « Les cases n'entrent pas dans
  le Monde parce que `monde.gd` balaie linéairement » vivait dans quatre
  fichiers ; l'index spatial a rendu la raison fausse partout d'un coup, et rien
  n'a rougi — aucun test ne lit un commentaire. Elle a servi une fois à conclure
  qu'une carte plus grande était hors de portée, sur des chiffres d'avant
  l'index. Règle : une décision cite le MÉCANISME qui la fonde à UN seul
  endroit ; les autres y renvoient. Et un relevé de mesures dit en tête sur quel
  moteur il a été pris — sans quoi il se relit comme un état courant.
- UN COÛT DOCUMENTÉ N'EST PAS UN COÛT CORRIGÉ. `monde.gd` portait en tête
  « COUT LINEAIRE par requete : signalé, jamais contourné en silence », et cette
  phrase est ce qui a laissé passer le défaut des mois : elle transforme un bug
  en état connu et assumé, et se lit comme une décision déjà prise. Règle : un
  coût se corrige, ou se plafonne par un test opposable — jamais par une note.
- AUCUN TEST NE MESURAIT UN COÛT. `test_volume_docs.gd` rougit quand un `.md`
  grossit de quelques milliers d'octets ; rien ne rougissait quand un tick passait
  de 1 ms à 500. Un test de correction ne peut pas voir ça — le résultat EST juste,
  il est seulement ruineux. D'où les compteurs exposés par `monde.gd` (requêtes,
  cases lues, candidats mesurés) : ils existent pour qu'un test puisse poser un
  plafond de coût.
- OPTIMISER SANS MESURER — l'hypothèse « les colonnes prises sont le goulot »
  était fausse : 163 ms → 155 ms. Mesurer d'abord, toujours.
- DEUX ÉCRIVAINS SUR `carte.tscn` — la sauvegarde de l'éditeur ouvert écrase le
  fichier écrit à côté. Quand Godot est ouvert, les valeurs se dictent, elles ne
  s'écrivent pas.
