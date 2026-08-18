# Game Design — Premier RTS

Ce document porte les décisions de game design du jeu. Il ne
porte PAS le design du framework (voir addons/documents/design.md).
Il se lit et se met à jour à chaque session qui touche au gameplay.

## Principes

- La logistique a un coût réel : la distance fatigue les unités,
  consomme les ressources, dégrade l'efficacité au combat.
- Le rush est viable mais facturé : un pari à haut rendement et
  haut risque, pas une stratégie sans coût.
- Chaque style de jeu a un prix. Défensif, offensif, économique
  — aucun n'est gratuit, aucun n'est dominant. Le joueur choisit
  quel prix il accepte de payer.
- Mille joueurs, mille heures, mille doctrines : le test de
  réussite du jeu. Si le joueur n'a pas développé sa propre
  façon de jouer, le game design a échoué.

## Philosophie — le jeu ne juge pas, il facture

Prolonge Principes : ici, la conséquence pour le joueur.

- La question posée par le jeu n'est JAMAIS « est-ce optimal », c'est
  « est-ce que le joueur a payé le prix ». Une stratégie sous-optimale
  n'est pas punie, elle est facturée.
- Les stratégies débiles qui fonctionnent sont le cœur du jeu. Douze
  canons sur une machine qui ne peut plus bouger : si le joueur a miné
  le fer, bâti la logistique qui la nourrit et posé son monstre au bon
  endroit, ça marche. C'est débile, c'est magnifique, et c'est une
  histoire.
- Le jeu est CONTRE l'optimisation comme voie unique. L'optimisateur
  gagne par l'efficacité, l'Ork par le volume, le défensif par le
  temps ; aucune des trois ne domine les deux autres. L'optimisation
  est un style, pas la méta.
- Forme exigeante du test de Principes : personne ne raconte « j'ai
  fait le build optimal ». Tout le monde raconte « j'ai fait un truc
  absurde et ça a marché ».

## IA

- L'IA adversaire est un classifieur LLM, pas un arbre de
  comportement. Elle pèse l'état, elle ne suit pas un script.
- Chaque agent IA est un Modelfile Ollama séparé avec son propre
  system prompt.
- Les agents mémoire sont côté code. Le modèle n'a aucune
  mémoire entre les appels.
- Le comportement de l'IA émerge de l'état, pas d'un profil
  câblé. Pas d'étiquette « turtle » ou « rusher » — l'IA
  réagit à ce qu'elle voit.

## Terrain destructible

Cette section engage le pont laissé ouvert par `SUIVI.md` § DÉCISIONS :
un terrain que la gravité fait tomber est un terrain LU par un
mécanisme, donc modélisé en cases-objets, pas seulement affiché par le
GridMap.

La gravité ne s'applique QU'EN JEU. Pendant la sculpture dans
l'éditeur, rien ne tombe : le terrain se pose tel qu'il est écrit.

### Conservation des masses

- Miner un cube ne le fait pas disparaître : il devient un objet
  physique que le colon porte et déplace.
- Aucun inventaire magique. La matière existe dans le monde, elle
  circule, elle encombre — porter du minerai coûte une place et une
  charge, pas une ligne de compteur.
- Un cube de 2 m est composé de sous-cubes : le minage est progressif,
  jamais instantané.

### Gravité et effondrement

- Un cube est SOUTENU s'il a un appui plein en dessous, ou s'il est
  relié latéralement à un cube soutenu par une chaîne de cubes de même
  matériau.
- La chaîne a une longueur maximale : au-delà, ça cède. Cette longueur
  est la COHÉSION du matériau — terre faible, pierre moyenne, fer
  élevée.
- La cohésion est une propriété de MATÉRIAU : elle vit dans
  `data/materiaux.json`, aux côtés de `densite` et `resistance_impact`.
  Le cube la porte par sa `composition` (`data/types.json`), jamais en
  propre.
- L'effondrement n'est pas instantané. Le cube en excès de chaîne passe
  d'abord FISSURÉ (un état porté par le cube), et ne tombe qu'après un
  délai. Le joueur voit venir et peut réagir.
- Un cube qui tombe ne disparaît pas : il se dépose sur le premier cube
  plein en dessous, ou écrase ce qui s'y trouve.

### Points de soutènement

- Un pont de pierre tient sur quelques cubes sans appui en dessous —
  c'est la cohésion du matériau qui le porte, et elle seule.
- Retirer un mur porteur rallonge la chaîne au-delà de la cohésion :
  le pont s'effondre. Rien de scripté, la règle de chaîne suffit.

### Étayage

- Le joueur pose des poutres : un objet portant une propriété de
  soutènement, qui vaut appui sans être un cube plein.
- Miner sans étayer est rapide et dangereux. Miner en étayant est lent
  et sûr. Le choix est stratégique, et il se paie dans les deux sens —
  voir Principes, « chaque style de jeu a un prix ».

### Ce que ces mécaniques exigent du framework

Aucune de ces règles ne s'écrit depuis le jeu : la Frontière interdit
d'ouvrir `scripts/`. Elles se composent de mécanismes déjà fermés —
seuils (`seuil_etat.gd`), états à durée (`etat_duree.gd`), propagation
de proche en proche (`propagation.gd`), propriétés par matériau
(`data/materiaux.json`).

POINT OUVERT, à trancher avant tout câblage : la chaîne « relié à un
support » est un parcours de connexité sur voisinage, et aucun
mécanisme du cœur identifié à ce jour ne le fait. S'il manque
réellement, c'est un chantier FRAMEWORK, dans l'autre dépôt — le
gameplay attend qu'il soit fermé.

## Personnalisation des unités

- Toute unité est personnalisable de bout en bout par le joueur. Il n'y
  a pas de catalogue d'unités finies à choisir.
- Chaque composant ajouté se paie quatre fois : en matériaux, en poids,
  en consommation, en temps de production. Plus de canons = plus de
  poids = plus lent = plus de ravitaillement. Plus d'armure, même
  chaîne.
- Pas de curseur dans un menu : LA PERSONNALISATION EST LA PHYSIQUE.
  Ajouter un canon, c'est ajouter du fer, du poids et un canal de
  munition dans `data/types.json` — pas un point de dégât dans une
  fiche.
- Trois familles apparaissent d'elles-mêmes, aucune n'est écrite comme
  une catégorie : la MASSE (peu chère, vite produite, fragile ;
  chacune consomme peu, mille consomment beaucoup), le GARGANT
  (puissant, lent, production et ravitaillement colossaux — un seul
  bloque une armée, sa perte est catastrophique), le RAPIDE (léger,
  vif, réserves courtes — inutile loin de la base sans logistique).
- Le framework porte tout ça par des propriétés qui existent déjà :
  masse, vélocité, réserves, dépense, consommation.

## Races — une pente, pas un mur

- Une race est iconique et donne un point de DÉPART, jamais un
  plafond.
- Ce qu'une race change : des modificateurs sur les propriétés — coût
  de production, tolérance au poids, vitesse de base, consommation,
  maintenance. Ils rendent certaines doctrines moins chères et
  d'autres plus chères. Ils n'en interdisent aucune.
- Le champ de personnalisation est IDENTIQUE pour toutes les races :
  mêmes composants, mêmes canons, mêmes matériaux. Seul le prix
  change.
- Jouer dans la pente de sa race est efficace. Jouer contre la pente
  est inefficace et libre. Trouver une doctrine inattendue pour sa
  race, c'est fabriquer ce que personne n'a vu venir.
- Une race Ork a des bonus sur la production d'armes, la tolérance au
  poids, la maintenance rustique. Un Ork qui fait de l'infiltration
  subtile PEUT — ça coûte plus cher. Une race subtile qui empile du
  Dakka PEUT — ses structures portent moins de poids, mais le prix
  payé suffit.
- Tout vit en données (`data/types.json`) : des modificateurs sur des
  propriétés qui existent déjà, zéro ligne de moteur. Une race n'est
  JAMAIS une catégorie dans le code, seulement un sac de modificateurs
  — voir `CLAUDE.md` § ADN.

## Asymétrie

- Les cartes sont asymétriques : aucun côté ne ressemble à l'autre.
  Partir du nord n'ouvre pas les mêmes options que partir du sud.
- L'équilibre ne vient PAS de la symétrie des conditions de départ, il
  vient de la logistique — chaque position a son coût et son avantage.
  Le plateau domine et s'expose. La vallée protège et rend aveugle.
- Les cartes sont faites à la main, pour garantir la qualité
  stratégique. La génération procédurale attend que la pratique ait
  dégagé les règles de ce qui fait une bonne carte.

## Unités et ressources

### Végétation — un écosystème, pas un décor

Plusieurs espèces partagent le terrain. Ce qui les sépare tient en données : la
vitesse de leur cycle, leur STATURE à chaque stade, la couche jusqu'où elles
montent, et la densité qu'elles tolèrent pour s'installer.

**Trois contraintes, et il faut les trois.** Les confondre supprimerait une
dynamique entière :

| | ce qu'elle gate | ce qu'elle produit |
|---|---|---|
| densité | la mère qui se reproduit | une population bornée |
| dominance | la croissance de la dominée | qui l'emporte sur qui |
| établissement | l'endroit où le rejet tombe | qui peut s'installer où |

**L'équilibre vient de la NICHE, pas du réglage.** Une espèce qui monte haut sur
le relief garde un refuge que l'espèce d'en bas ne peut pas lui prendre : la
forêt, plafonnée bas, ne montera jamais l'y déloger, et le couvert repart de ces
hauteurs quand la plaine se referme. C'est pour cela que le plafond de couche est
PAR ESPÈCE et pas commun — deux espèces au même plafond ne se partagent rien,
elles s'excluent, et la coexistence redevient une bande étroite de chiffres à
retrouver à la main. Corollaire : sur un terrain plat la niche ne joue pas, et
c'est le RELIEF qui décide de la biodiversité.

**La dominance compare des STATURES, jamais des numéros de stade.** Entre deux
espèces un numéro ne veut rien dire : le stade 3 d'une herbe n'est pas plus grand
que le stade 2 d'un arbre. Une herbe basse à tous ses stades n'ombrage donc jamais
un arbre, et se fige sous n'importe lequel.

**L'établissement vient de l'écologie réelle.** En savane, l'herbe ne tue pas les
arbres : elle tue leurs SEMIS, faute de trouée dans le tapis racinaire. Elle
n'affecte pas leur vitesse de croissance — seulement leur installation. D'où deux
pressions opposées à deux moments de la vie, et **deux gestes opposés pour le
joueur** : arracher l'herbe pour laisser monter les arbres, abattre les arbres
pour laisser revenir l'herbe.

Le reste suit :

- LE COLON RAMASSE LE PRODUIT, JAMAIS LA PLANTE. La graine tombe au sol, la plante
  reste. C'est ce qui sépare une ressource RENOUVELABLE d'un gisement.
- Le plafond au sol est un ENCOMBREMENT, pas un quota de vie : une plante cesse de
  produire tant que personne ne ramasse. Ne pas venir chercher coûte de la
  production perdue — la logistique se facture jusque dans la cueillette.
- Le vieillissement est la seule cause de mort. Le joueur ne peut pas raser une
  ressource, seulement la laisser vieillir — ou l'étouffer sous une autre espèce.
- Une plante dominée cesse de GRANDIR, mais elle meurt quand même à son heure. La
  mort ne regarde pas la lumière — sans quoi le sous-bois deviendrait éternel et
  la forêt ne pourrait jamais reprendre le terrain.
- DE LÀ SORT LA SUCCESSION, sans une règle de plus : l'herbe colonise vite un sol
  nu, la forêt monte lentement au travers et l'étouffe, et la chute d'un arbre
  rend la clairière à l'herbe avant qu'elle ne redevienne forêt. Trop d'herbe
  RETARDE la forêt, elle ne l'empêche pas.
- Abattre libère la strate : le joueur a une raison de couper qui n'est pas
  seulement la ressource.
- Le relief fait le paysage sans une règle de plus : chaque espèce déclare
  jusqu'où elle monte. Les arbres dans les bas-fonds, l'herbe partout.

## Conditions de victoire

(à remplir au fil des sessions)
