# LOGBOOK

Le mécanisme qui NOMME au joueur ce que le système vient de produire.
Sans lui, une émergence marquante passe inaperçue — un joueur qui n'est
pas designer voit "des cubes rouges qui bougent, j'ai perdu", alors que
le système vient de produire une masse de mêlée coordonnée que rien
n'avait scriptée.

## Le problème

L'émergence par principe ne dit rien d'elle-même. Elle SE PRODUIT. Ce
qui se produit n'est reconnu que par qui sait quoi regarder. Le
designer voit ; le joueur non.

Trois trous, mesurés en jouant :

1. **Rien ne se rejoue.** Une partie qui a produit "la masse compacte
   qui écrase le joueur" ne laisse aucune trace. Le lendemain, le
   joueur ne peut pas raconter à un ami autre chose que "je suis
   mort". Il ne PEUT PAS raconter, parce que le système ne lui a rien
   donné à répéter.
2. **Rien ne se compare.** Deux parties similaires, un moment rare
   dans une, plat dans l'autre. Le joueur n'a aucun repère pour
   savoir laquelle des deux était l'exception.
3. **Rien ne se cherche.** Sans logbook, le joueur ne sait pas ce
   qu'il faudrait chercher. Il rejoue au hasard. Avec un logbook qui
   dit "en 5843, la masse s'est formée", il rejoue POUR provoquer
   ça — ou pour l'éviter.

## Ce qu'un moment mérite d'être noté

Quatre conditions, à valider AVANT de créer une entrée. Une seule qui
manque, on n'écrit rien : un logbook plein d'entrées triviales n'est
plus un logbook, c'est un flux.

1. **RARE** : le moment ne se produit pas chaque partie. Un
   compteur ("+50 métal") n'est jamais rare, donc jamais dans le
   logbook.
2. **COMPOSÉ** : plusieurs mécaniques ont interagi pour le produire.
   Une frappe seule n'est pas composée ; une masse coordonnée l'est
   (perception locale + mémoire + territoire, aucune n'a demandé la
   coordination).
3. **CONSÉQUENT** : le moment a modifié la partie. Un cube violet qui
   meurt sans avoir rien affecté n'est pas conséquent. Un cube violet
   qui meurt en emportant les 3 transporteurs qui avaient tout le
   stock de la partie l'est.
4. **NOMMABLE** : le moment tient dans une phrase. "En 5843, la
   masse a écrasé le joueur" est nommable. "Le système a fluctué"
   ne l'est pas.

## Forme d'une entrée

Une ligne, pas plus. Un tick de temps de jeu, un fait, les acteurs
nommés (id ou nom), un verbe fort. Jamais un adjectif, jamais un
commentaire du narrateur.

    [tick 5843] La masse orange a submergé le joueur. 4 soldats
                nés du cube violet #12, 2 autres du cube #7.
                Aucun soldat perdu.

Ce que ça n'est PAS :
- Un log de dev (« debug: 4 soldats spawned »)
- Une notification push (« un cube violet est mort ! »)
- Un compteur (« 4 soldats vivants »)
- Un journal de missions scripté

## Où ça vit

Dans le monde partagé, jamais dans une couche UI qui écoute des
signaux. Le logbook est une DONNÉE du monde, comme le stock d'un cube
violet. Il survit à la mort du joueur (dans un futur avec save/load,
il est écrit sur le disque comme le reste du monde — voir jeu/monde/
archiviste.gd).

Le fait d'ÊTRE ÉCRIT est un mécanisme. Le fait d'être AFFICHÉ est un
autre mécanisme. Les deux ne se confondent pas :
- Un écriveur (un module qui décide ce qui mérite une entrée)
- Une couche d'affichage (ce que le joueur voit — HUD, écran d'après
  partie, etc.)

## Ce qui reste à décider

- Quel(s) module(s) sont autorisés à écrire dans le logbook, et
  pourquoi eux et pas d'autres. Une règle centrale : un module n'écrit
  que ce qu'il PEUT SEUL voir (le module de combat voit les batailles ;
  le module d'économie voit les faillites).
- La densité cible. Combien d'entrées par heure de jeu ? Trop peu :
  logbook vide, invisible. Trop : bruit, chaque partie ressemble aux
  autres. À calibrer au playtest, comme le reste.
- La granularité de l'affichage. Toutes les entrées d'un coup ? Un
  résumé par partie ? Une notification à chaque nouvelle entrée ?
  À trancher quand un premier écriveur existe.

## Ce que le système produit déjà — observations

Observations venant du playtest, jamais du code lu. Chacune décrit une
propriété émergente que le logbook devra un jour NOMMER pour le joueur.
Elles calibrent aussi les 4 conditions (rare, composé, conséquent,
nommable) : c'est en regardant ces cas qu'on saura si un moment mérite
une entrée.

### La fenêtre de 5 minutes

Corollaire direct de l'observation "explosion en zone riche" ci-dessous.
La colonie a une FENÊTRE DE VULNÉRABILITÉ de ~5 min entre l'installation
et le point de non-retour. Avant la fenêtre : quelques individus
fragiles, tout peut être détruit à la main. Après la fenêtre : la
production dépasse la destruction possible par un joueur seul --
mathématiquement perdu, la zone est concédée.

TOUTE L'ACTION STRATEGIQUE DU JOUEUR TIENT DANS CETTE FENETRE. Le jeu
n'est pas "combattre la colonie", c'est "la reperer avant qu'elle
bascule". Passe le seuil, le joueur DOIT accepter de la contourner --
tenter la destruction frontale est un choix perdant, pas une option
strategique.

Consequence de design : c'est la fenetre qui doit etre l'objet du
jeu. Une carte de N km² a M colonies naissantes ; le joueur ne peut
en surveiller que K. Les autres explosent. Le drame vient de la
priorisation impossible, pas du combat direct.

### L'explosion en zone riche

Une lignée de cube violet posée sur une zone riche (~80 000 métal
accessible) passe de FRAGILE à QUASI INVINCIBLE en environ 5 minutes.
Une minute avant, il y a un cube et deux transporteurs qui se cassent
en 10 clics. Cinq minutes après, 100 à 300 individus, plusieurs
lignées, soldats prêts à naître dès qu'on frappe le premier cube.
Attaquer une colonie mûre déclenche une masse de soldats qui sature
le joueur.

Conséquence de design : DÉTRUIRE À 99 % N'EST PAS GAGNER. Un seul
cube oublié dans une zone riche recolonise plus vite que le joueur
ne peut traquer. C'est le patron "ork Warhammer / tyranide / zerg /
zombie" — la menace n'est jamais battue, elle est repoussée. C'est
aussi la propriété narrative la plus forte du système, celle qui
produit les histoires que les joueurs se racontent.

Forme d'entrée que l'écriveur devra pondre le jour où ça arrive :
`[tick 8420] La colonie du secteur E-3 compte 217 individus. Il y a
5 min elle en comptait 4.` Rare (une par partie, dans une zone
donnée), composé (reproduction + gisement riche + absence du joueur),
conséquent (change complètement la difficulté de la fin de partie),
nommable (un chiffre, une zone).

## Ce qui est écarté

- **Une IA qui commente en temps réel.** Trop cher à faire tourner
  côté joueur, et surtout le comment se trahit à la lecture : deux
  commentaires générés se ressemblent. Le fait sec ("la masse a
  submergé") est plus fort qu'une phrase brodée.
- **Un journal du joueur (écrit par le joueur).** C'est une autre
  couche, complémentaire, jamais le logbook. Le logbook est un
  témoignage OBJECTIF de ce que le système a fait ; un journal joueur
  est une lecture SUBJECTIVE. Les deux peuvent coexister, jamais se
  substituer.
