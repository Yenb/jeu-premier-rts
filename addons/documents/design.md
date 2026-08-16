# ORION — DESIGN

Frontière : ce fichier porte le design et le pourquoi, jamais une dette
ni un état de code précis. Une dette précise (fichier ET fonction ou
constante — jamais un numéro de ligne, qui périme silencieusement à
chaque édition et ne se retrouve pas par grep) vit dans `CARTE.md` §6 ou
`docs/prototypes.md`, pas ici — de même pour tout compte ou état exact
(nombre d'entrées d'un catalogue, liste de scripts câblés). Une adresse
`fichier:fonction` citée à titre d'EXEMPLE, pour illustrer où une règle
s'applique, reste admise ici (ce fichier en use couramment) — ce n'est
ni une dette ni un état à tenir à jour, juste un repère de lecture.

## Modèle objet (session refonte)

Un objet = { id, position, proprietes }. Le "type" est un raccourci de
fabrication : il charge un paquet de propriétés depuis une table puis
disparaît. Après fabrication, le cœur lit instance.chose.proprietes,
JAMAIS catalogue.get(type). Tout catalogue.get(type) dans une couche du
cœur est un bug.

## Propriété vs relation

Une propriété vit sur un objet seul (inflammable, saillant, brule). Une
relation met en jeu deux objets. Les propriétés vivent dans proprietes ;
les couples d'interaction (qui met en jeu deux propriétés) vivent dans une
table de données dédiée, jamais nommés en dur dans le moteur.

## Propriété structurelle vs facultative

Toute lecture d'une propriété distingue deux cas, jamais confondus.

FACULTATIVE — son absence est un fait légitime du monde. Une chose sans
`saillance_intrinseque` n'est simplement pas saillante ; un agent
d'extinction sans `rythme` travaille au rythme par défaut. Le mécanisme
l'ignore, aucune alarme : `.get(cle, defaut)` est correct et suffisant.

STRUCTURELLE — son absence signifie que l'objet reçu n'aurait jamais dû
arriver dans ce mécanisme. `attaches` et `forme` sur un colon en sont :
leur absence ne dit pas « ce colon est neutre », elle dit « ceci n'est
pas un colon ». `canaux` de même pour `perception.gd`. Ça
doit échouer BRUYAMMENT, jamais retomber sur un défaut silencieux.

Le critère n'est PAS « vide ou pas » — c'est CLÉ ABSENTE ou CLÉ PRÉSENTE
ET VIDE. Un placide porte `attaches : []` : clé présente, liste vide,
absence légitime, aucune alarme. Un objet sans clé `attaches` du tout :
alarme. Concrètement : `has` avant `get` sur les propriétés
structurelles — la clé absente crie, la valeur vide passe.

Forme de l'alarme, tranchée par l'expérience, pas par principe :
`assert` natif de GDScript a été essayé puis abandonné — en
`--headless --script`, un assert qui échoue ne rend jamais la main, le
processus pend au lieu de se terminer (constaté et vérifié à
l'exécution). La forme retenue partout où une propriété structurelle est
lue : `push_error(message)` — log visible, jamais avalé en silence,
jamais bloquant — suivi d'un retour neutre (`[]`, `null`). Le mécanisme
se dégrade proprement au lieu de planter ou de pendre.

**Règle opposable — classer une propriété qu'on n'a pas encore imaginée**

Test, applicable sans connaître le nom de la propriété : si elle
manquait, l'objet reçu resterait-il, PAR DÉFINITION, un exemplaire de ce
que ce mécanisme a vocation à traiter ? Oui → FACULTATIVE : un défaut
neutre décrit un point réel que le monde peut occuper. Non →
STRUCTURELLE : un défaut serait une invention, l'objet reçu n'appartient
pas au domaine du mécanisme et aucune valeur ne peut le faire semblant
d'y appartenir.

**Le cas du couple**

Ce test juge une propriété seule ; il ne suffit pas quand deux
propriétés du même objet forment un couple — l'une déclare une capacité
ou un comportement, l'autre le qualifie ou le borne. Prise seule, la
seconde peut être facultative : son absence, en l'absence de la
première, décrit un état neutre légitime. Mais dès que la première est
présente sur le même objet, l'absence de la seconde ne retombe plus sur
un défaut neutre — elle retombe sur un défaut qui CONTREDIT ce que la
première vient de déclarer, un comportement plus fort, plus large ou
plus permanent que ce que la déclaration seule, sans borne, aurait dû
produire. Dans ce contexte précis, la seconde devient STRUCTURELLE : sa
clé absente doit échouer bruyamment, pas retomber sur le défaut qui
vaut quand la première est elle-même absente. La structuralité n'est
alors plus une propriété du mécanisme seul, elle est une propriété du
COUPLE — ce qui bascule, c'est la présence de l'autre propriété sur
l'objet, jamais le mécanisme.

**Pourquoi le basculement ne va que dans un sens**

Une propriété structurelle définit l'appartenance au domaine du
mécanisme, et cette appartenance ne dépend d'aucune autre propriété de
l'objet : `attaches` et `forme` définissent à elles seules ce qu'est un
colon pour `attaches.gd` ; `canaux` définit à elle seule ce
qu'est un objet perceptif pour `perception.gd` — quoi que porte par
ailleurs l'objet. Rien ne peut donc rendre une propriété structurelle
facultative en lui ajoutant une compagne : sa condition d'appartenance
ne s'exprimait déjà en fonction d'aucune autre propriété, il n'y a rien
à faire varier. Seule une propriété facultative — dont l'appartenance au
domaine ne dépendait justement de rien au départ — peut voir cette
appartenance se reconditionner sur l'arrivée d'une compagne qui la
qualifie.

## Propriété du monde vs champ de configuration technique

Deux catégories de champs vivent sur un objet dans `data/types.json`,
jamais à confondre dans les listes que lisent les mécanismes.

PROPRIÉTÉ DU MONDE — décrit ce que la chose EST ou FAIT dans le monde.
Elle est perceptible (un canal peut la capter) et manipulable par les
mécanismes du cœur (posée, retirée, lue comme cause). Exemples :
`brule`, `cassable`, `inflammable`, `dangereux`, `irremplacable`,
`notre_ouvrage`, `rythme`, `vitesse`, `portee_*`.

CHAMP DE CONFIGURATION TECHNIQUE — pointeur ou drapeau qui référence une
règle du moteur ou une entrée de catalogue. Il n'est pas perceptible
(aucun canal ne le capte) et ne se manipule jamais comme cause : il sert
au moteur à retrouver la règle applicable à cette chose, rien de plus.
Exemples : `profil_saillance` (pointeur vers `data/profils_saillance.json`),
`seuils_ref` (pointeur vers une table de seuils), `materiau` (pointeur vers
`data/materiaux.json`), `canaux` (Array de pointeurs vers
`data/canaux.json`), `deformation_sources` (Array de pointeurs vers
`data/deformations.json`), `herite` (Array de noms de paquet lu par
`objet.gd:fabriquer`). Un seul patron pour toute référence de catalogue
dans le dépôt : un champ String (ou un Array de String) qui CONTIENT la
référence — jamais une clé de Dictionary qui EST la référence (ancienne
structure de `canaux`/`deformation`, éliminée par le chantier « un seul
patron de référence de catalogue », voir `scripts/test_lint_donnees.gd`,
qui vérifie ces six champs au chargement).

**Règle opposable** — un champ dont le nom finit par `_ref`, `_id`, ou
commence par `profil_`, ou vaut exactement `herite`, est très
probablement un champ de configuration. Un champ dont le nom décrit un
état ou une capacité
(adjectif, verbe, mesure) est très probablement une propriété du monde.
En cas de doute, poser la question : « un canal sensoriel pourrait-il
capter ce champ ? » Si non, c'est de la configuration.

**Conséquence architecturale** — les catalogues des mécanismes du cœur
(`data/canaux.json:proprietes_captees`, `data/menaces.json`,
`data/jugements.json`, `data/engagements.json`, etc.) ne référencent QUE
des propriétés du monde. Un champ de configuration technique n'a rien à
faire dans ces listes.

Erreur historique documentée : PHASE 3.5 a produit une première version
de `data/canaux.json:vue` qui listait `profil_saillance` comme propriété
captée, avant correction en conversation.

## action_en_cours vit hors de proprietes

`action_en_cours` (colon) référence une AUTRE chose (`{ id, position,
type }`) et change à CHAQUE tick — ce n'est pas un fait stable de
l'objet, contrairement à `attaches`/`forme`/`canaux`. Elle
n'a rien à faire dans le flux que parcourent `depense.gd`, `flux.gd`,
`extinction.gd`, `propagation.gd` (qui lisent tous `proprietes` en
boucle sur l'ensemble du monde, sans jamais s'attendre à une référence
vers un autre objet ni à une valeur qui change plus vite que le reste).
Elle vit au même niveau que `id`/`position`, HORS `proprietes`.

Elle reste néanmoins lisible et résumable (voir « L'LLM : lecteur ancré,
jamais auteur », condition de l'ancrage) : `{ id, position, type }` est
un vecteur court, pas un historique — l'exclure de `proprietes` ne
l'exclut pas de ce que l'LLM peut lire.

RÉSULTAT NÉGATIF, à ne pas reproduire : un mécanisme de banc qui gèle la
saillance d'une chose (l'exclut temporairement de la compétition) ne doit
JAMAIS se re-détecter via une décision de colon (`action_en_cours`) — un
premier essai (occupation d'un chantier, `banc_p1.gd`) détectait « qui
occupe » via `colon.action_en_cours.id`, et faisait clignoter la
saillance gelée à chaque tick : la chose gelée n'est plus saillante pour
PERSONNE, son propre occupant compris, sa décision devient `null`, ce qui
vide `action_en_cours` au tick suivant (réécrit à chaque tick depuis la
décision fraîche, jamais une mémoire), ce qui « libère » la chose, qui
redevient saillante, qui la refait geler — boucle qui se mord la queue,
la décision dépendant de la saillance qu'elle vient elle-même de geler.
Détecter par un fait INDÉPENDANT de toute décision (la position physique,
comme le fait déjà `extinction.gd`) est la seule base stable.

## Menace par propriétés (étape 4)

La menace n'est plus nominale (fini "feu menace arbre"). Elle émerge de la
rencontre de deux propriétés dans l'espace : une chose portant une
propriété de vulnérabilité (inflammable) + une chose portant la propriété
de menace correspondante (brule) à proximité = danger. Le couple vit dans
menaces.json. Le moteur ne nomme aucune propriété en dur.

## Extinction = retrait de propriétés, pas mutation de type

Éteindre un feu RETIRE de l'objet ses propriétés (saillance, brule) — le
moteur retire ou pose des propriétés en donnée, il ne mute jamais un
champ "type".

## Direction majeure : ABANDONNÉE — un seul geste extrait, pas un mécanisme unique

ÉCARTÉ (audit dédié, mesure faite sur le code réel des cinq mécanismes,
pas sur l'intention qui suit) : l'hypothèse ci-dessous, telle qu'écrite à
l'origine, affirmait qu'extinction, propagation, flux, charge et attaches
sont « le même mécanisme abstrait » et que seul l'effet varie. Ce n'est
pas vrai. La part réellement partagée par les cinq — une seule
comparaison, `distance <= portee` — pèse de l'ordre de 5 à 10 % du code de
détection de chacun. Les quatre autres axes varient tous indépendamment,
et aucun n'est accessoire :

- QUELLE LISTE PARCOURIR — les perceptions du colon (`attaches.gd`), le
 monde entier en une ou deux passes (`propagation.gd`, `flux.gd`), le
 monde plus une liste tierce construite par l'appelant (`extinction.gd`
 avec `agents`, `charge.gd` avec `causes`), ou les règles d'un catalogue
 en premier (`flux.gd`).
- OÙ VIT LA PORTÉE — sur la forme du colon percevant (`attaches.gd`), sur
 l'instance cible (`propagation.gd`), sur l'instance source
 (`flux.gd`), sur le canal de l'objet récepteur (`charge.gd`), ou dans
 une référence de catalogue partagée (`extinction.gd`).
- COMMENT AGRÉGER — maximum, somme, ou simple présence (OU booléen).
- QUELLE NATURE D'EFFET en résulte (voir plus bas).

Fusionner les cinq sous une seule signature coûterait de l'ordre de vingt
fichiers (les cinq mécanismes, leurs tests, les neuf bancs qui les
appellent directement) pour un changement D'ARITÉ non rétrocompatible —
pas un paramètre facultatif de plus : cinq signatures aujourd'hui,
aucune sous-ensemble d'une autre. NE PAS ROUVRIR ce chantier sur la seule
foi de ce paragraphe — la décision n'est pas un manque de temps, c'est que
la fusion coûte durablement plus qu'elle ne fait gagner, sur un geste
partagé qui tient en une ligne.

CE QUI EST GARDÉ, seul geste réellement commun : la comparaison
géométrique elle-même, extraite dans `scripts/portee.gd` (même patron
que `quantite_matiere.gd` : une extraction étroite, appelée par
plusieurs fichiers, qui n'unifie rien d'autre autour d'elle).
`attaches.gd`, `propagation.gd`, `flux.gd`,
`extinction.gd`, `charge.gd` l'appellent tous ; leurs boucles, leurs
agrégations et leurs effets restent chacun dans leur fichier, inchangés.
Détail : `CARTE.md` §2, `scripts/portee.gd`.

QUATRE CORRECTIONS DE DOCTRINE, établies par l'audit, à ne pas reperdre :

- `charge.gd` est une QUATRIÈME nature d'effet, jamais nommée ci-dessous
 avant ce chantier : un seuil RÉVERSIBLE, qui pose ET retire la même clé
 selon le sens du franchissement — ni une lecture pure, ni une écriture
 différée irréversible, ni un transfert continu.
- `extinction.gd` n'est PAS une simple écriture différée, contrairement à
 ce que ce fichier affirmait : c'est un HYBRIDE — un décrément continu
 (`travail_restant -= somme * delta`, la même nature que `flux.gd`) qui
 ne devient une écriture différée qu'au moment où il atteint zéro.
- Le déclencheur « action », listé plus bas comme « à concevoir »,
 EXISTE déjà : `agir.gd:_appliquer_actes_liants` (PHASE 5, ACTES LIANTS)
 pose un lien personnel dès qu'un verbe DÉCIDÉ correspond à une règle —
 aucune position, aucune portée. Jamais rattaché à cette doctrine avant
 aujourd'hui.
- Le déclencheur « contact » N'EXISTE PAS comme forme distincte : la
 géométrie `"contact"` de `perception.gd` est le même code que les
 géométries sphériques (`_sphere_brute`), portée réglée courte en
 donnée — une proximité à petit rayon, pas un troisième mécanisme.

Ce qui reste vrai malgré l'abandon de la fusion, non remis en cause par
l'audit : la menace émerge d'une rencontre de propriétés dans l'espace
(voir « Menace par propriétés » ci-dessus), et coder un mécanisme de
transformation nommant le feu en dur serait toujours la même erreur que
`menace_par` nominal — c'est la GÉNÉRICITÉ PAR FICHIER qui reste
obligatoire, pas la fusion des fichiers entre eux. Reste ouvert, non
tranché : la GÉNÉRALISATION à coupe/forge/effondrement (aucun des trois
n'a de mécanisme écrit à ce jour — rien n'empêche d'en écrire un nouveau,
sur le patron d'un des cinq existants, sans jamais les fusionner) ; et si
un futur déclencheur « contact » réel (collision, surface) devrait un
jour exister séparément de la proximité — aucun besoin de jeu ne l'a
encore réclamé.

CINQUIÈME nature d'effet, établie par un second audit (chantier
« foudre ») : ÉVÉNEMENT PONCTUEL PAR
SÉLECTION (`scripts/frappe.gd`) — sélectionne UNE cible parmi plusieurs
objets physiques du monde par un score composite (max-reduction, idiome
`dominance.gd:visibles`), puis lui applique un effet immédiat et
PERMANENT, sans accumulation préalable. Ne correspond à AUCUNE des
quatre natures ci-dessus (ni une lecture pure, ni une écriture différée
irréversible sur une cible déjà connue de l'appelant — `extinction.gd`/
`depense.gd` —, ni un transfert continu, ni un seuil réversible) et
n'appartient à AUCUN des trois déclencheurs déjà nommés (portée, action,
contact-comme-proximité) : c'est la SÉLECTION elle-même, jamais
rencontrée avant ce chantier, qui distingue cette nature — les quatre
autres reçoivent toutes leur cible déjà désignée par l'appelant.

VARIANTE de cette cinquième nature, PAS une nature de plus
(`scripts/bifurcation.gd`, chantier « bifurcation pondérée », audit
) : SÉLECTION DE SORTIE.
Le geste est identique à celui de `frappe.gd` — pondérer chaque candidat,
prendre le maximum, alarmer sur égalité stricte sans trancher, garder le
premier déclaré. Ce qui change est l'ENSEMBLE où l'on choisit : non plus
des objets du monde à portée, mais des NOMS DE SORTIE déclarés en donnée,
qu'aucun objet ne porte — rien à mesurer sur eux, seul le biais que
l'entité met sur chacun les distingue (même doctrine que `poids_verbes`,
voir « Les archétypes n'existent pas » : les mêmes sorties sont offertes à
tous, seul le POIDS distingue). La nature d'effet, elle, est inchangée :
une sélection, immédiate, sans accumulation préalable. Règle générale à
retenir de ce cas : changer l'ensemble des candidats ne crée jamais une
nature — seule la nature de l'EFFET en crée une. Contrat exact :
`CARTE.md` §2, `scripts/bifurcation.gd`.

SIXIÈME nature de mécanisme, établie par un troisième audit (chantier
« velocite ») : DÉRIVATION
PASSIVE (`scripts/velocite.gd`) — une OBSERVATION, jamais une décision.
Ne correspond à AUCUNE des cinq précédentes : elle ne lit pas une
propriété déjà là (lecture pure), ne pose ni ne retire une cause
(écriture différée, seuil réversible), ne transfère rien d'une réserve à
une autre (transfert continu), ne sélectionne aucune cible (événement
ponctuel). Elle regarde la différence entre deux états successifs d'une
MÊME grandeur déjà mutée par d'AUTRES mécanismes (`champ.gd`,
`banc_commun.gd:bouger_vers`/`bouger_selon`, potentiellement plusieurs
dans le même tick, sans coordination entre eux) et la rend lisible —
`velocite = (position - position_precedente) / delta`, calculée UNE
SEULE FOIS en fin de tick, jamais écrite par les mécanismes qui
déplacent. Brique TRANSVERSALE, pas un phénomène de jeu : elle
débloque la lecture d'une vitesse d'objet pour l'induction magnétique
(vitesse × champ local), la résistance aérodynamique (vitesse relative
au vent de `vent.gd` × densité de l'air), et un futur rebond réaliste
généralisé (vitesse avant impact × restitution) — chacun de ces trois
chantiers reste À CONCEVOIR séparément, `velocite.gd` ne fait que
rendre leur grandeur d'entrée lisible. NE PAS CONFONDRE avec « vitesse
de propagation du son par matériau » (racine(rigidite/densite),
plus bas) : cette dernière est une vitesse d'ONDE dans un matériau,
sans aucun rapport avec la vélocité d'un OBJET — `velocite.gd` ne la
débloque pas, un mécanisme de délai temporel dans `perception.gd` reste
requis séparément.

SEPTIÈME nature (transfert DESTRUCTIF entre deux objets DÉJÀ identifiés
par l'appelant) : `scripts/consommer.gd`, voir « Consommer : transfert
DESTRUCTIF, sœur de flux.gd jamais une variante » plus bas.

HUITIÈME nature de mécanisme, établie par un quatrième audit (chantier
« écoulement gravitaire — eau par pente ») : TRANSFERT CONSERVÉ PAIR-À-PAIRE CONDITIONNÉ PAR
COMPARAISON RELATIVE (`scripts/ecoulement.gd`). Ne correspond à aucune
des sept précédentes : ni un transfert continu non conservé (`flux.gd`),
ni un seuil réversible (`charge.gd`), ni un événement ponctuel par
sélection (`frappe.gd`), ni une dérivation passive (`velocite.gd`), ni un
transfert destructif entre DEUX objets DÉJÀ identifiés par l'appelant
(`consommer.gd`, ci-dessus) — ici c'est le mécanisme LUI-MÊME qui
identifie la paire source/receveur, par comparaison mutuelle de deux
voisins du même ensemble (`hauteur = altitude + réserve courante`,
transfère du plus haut vers le plus bas seulement, jamais en sens
inverse). Aucun des sept précédents ne compare jamais deux instances
entre elles pour décider un sens de transfert. Détail : `CARTE.md` §2,
`scripts/ecoulement.gd`.

Forme proposée pour la ligne de flux, validée en partie : `{ source,
receptrice, cible, taux, portee }` — un couple de propriétés
(source/réceptrice) comme menaces.json, plus `cible` (quelle propriété
numérique modifier) et `taux` (quantité transférée par seconde et par
source en portée).

TRANCHÉ : une portée d'ÉMISSION ne vit PAS dans une table de règles
partagée. Elle décrit la SOURCE, pas la relation — un feu chauffe à cinq
mètres quoi qu'il chauffe. Elle vit sur l'objet source, posée à la
fabrication : `portee_saillance` (proximite.gd), `portee_propagation`
(propagation.gd), `portee_flux` (flux.gd) — `perception.gd` suit le même
principe à un grain plus fin depuis PHASE 3.5 (chantier « L'entité comme
agent complet ») : une portée par canal, `canaux_config.<nom>.portee`,
jamais une portée unique (voir CARTE.md, `perception.gd`).

CORRECTION (chantier « émission et seuil ») : pour `propagation.gd`
spécifiquement, `portee_propagation` n'a JAMAIS vécu sur la source malgré
ce que le paragraphe ci-dessus affirmait — le code l'a toujours lue sur la
CIBLE (la chose vulnérable), jamais sur le feu. Ce n'était pas une portée
mal placée mais DEUX grandeurs confondues en un seul nombre, qui ne
pouvaient donc pas se régler séparément : une chose ne peut porter plus
loin selon sa TAILLE (un grand feu vs une brindille) ni un matériau réagir
différemment d'un autre à distance égale. Les deux vivent maintenant
séparément, toutes deux facultatives (`data/emission_propagation.json`,
défaut `{}` — comportement inchangé tant que non fourni) : une ÉMISSION
portée par la SOURCE, dérivée de sa taille (`proprietes.reserves.<nom>.
capacite`, la même capacité de combustible que `combustible.gd` lit déjà
— aucun nombre libre inventé pour ce chantier) et décroissante avec la
distance en 1/distance²; un SEUIL porté par la CIBLE, dérivé de la même
valeur EFFECTIVE d'inflammabilité que `delai_ignition` lit déjà
(`etat_effectif.gd`), jamais une propriété séparée — CONSÉQUENCE ASSUMÉE :
l'intensité effective joue donc à deux endroits (la distance à laquelle
l'exposition commence, la vitesse à laquelle elle aboutit), l'écart entre
deux matières se MULTIPLIE, jamais ne s'additionne. L'exposition démarre
quand ce que la cible reçoit dépasse son seuil — une portée effective qui
en RÉSULTE, jamais déclarée en dur. `portee_propagation`, lue sur la
cible, reste le chemin de repli exact quand ce nouveau mécanisme n'est pas
configuré. Détail : `scripts/propagation.gd`, `CARTE.md` §2.

`portee_travail` (extinction.gd) est un cas distinct, pas une exception à
cette règle : elle décrit un CHANTIER, pas une source d'émission —
jusqu'où un agent peut travailler dessus, pas ce qu'une chose émet
autour d'elle. Elle vit légitimement dans l'entrée de transformation
partagée (`data/transformations.json`), la même pour toutes les choses
qui partagent cette entrée. Différencier deux chantiers (un feu qui se
travaille à 25, un rocher à 5) se fait en ajoutant une entrée à la
table — jamais une exception dans le code qui la lit.

TRANCHÉ : `taux` suit `portee`, même raisonnement — un feu chauffe à une
intensité qui lui est propre, pas prêtée par la table pour telle paire
receveuse. Il vit sur l'objet source, posé à la fabrication, pas dans la
table. La ligne de flux se réduit à `{ source, receptrice, cible }` : un
couple de propriétés (comme menaces.json) plus la propriété numérique à
modifier — plus aucune intensité ni portée dans la table elle-même.

CONVENTION DE NOMMAGE, tenue depuis et à ne pas relâcher : une portée est
toujours préfixée par le MÉCANISME qui la lit — `portee_travail`
(extinction.gd), `portee_saillance` (proximite.gd), `portee_propagation`
(propagation.gd), `portee_flux` (flux.gd). Jamais par le sens qu'elle
porte pour le monde (« rayon_vision »), jamais bare (« portee »). Un
`portee` bare s'est glissé sur le colon (rayon de perception) avant
d'être renommé une première fois en une portée unique préfixée par le
mécanisme, puis éclaté en PHASE 3.5 (chantier « L'entité comme agent complet ») en une portée PAR
CANAL (`canaux_config.<nom>.portee`, voir CARTE.md, `perception.gd`) — sans
préfixe ni regroupement par canal, un objet qui cumule plusieurs portées
(un colon devient agent d'extinction, par exemple, et porte alors à la
fois ses canaux perceptifs et un futur `portee_travail`) ne peut plus
dire laquelle appartient à quel mécanisme.

Une chose portant la propriété source recharge la réserve d'une chose à
portée portant la propriété réceptrice correspondante. Le moteur ne
nomme ni la source ni la réserve. Nom de script neutre — pas `gain.gd` —
puisque rien n'y est spécifique au gain (le même code sert un flux
négatif si `taux` est négatif). Test hors domaine obligatoire à l'écriture :
une source et une réserve sans rapport avec lumière ou énergie doivent
traverser le même code, comme `_le_modele_ignore_le_domaine` pour
`depense.gd`.

## Consommer : transfert DESTRUCTIF, sœur de flux.gd jamais une variante

SIXIÈME mécanisme du cœur neuf de cette session (chantier « consommer.gd —
transfert destructif + banc_manger »), `scripts/consommer.gd`. `flux.gd`
transfère « selon un nombre, dans un sens ou dans l'autre » sans jamais
dépléter sa source — l'herbe de `banc_animal.gd` reste une source infinie.
`consommer.gd` répond à un besoin structurellement différent : manger,
boire, miner, récolter, traire, vampiriser — la source se VIDE
exactement de ce que le receveur gagne, au même tick. Ce n'est pas
`flux.gd` avec un paramètre de plus : la signature entière change (source
ET receveur explicites, jamais une boucle règles-d'abord sur tout le
monde) parce que la relation est une TRANSACTION UNIQUE entre deux objets
déjà identifiés par l'appelant, jamais une règle appliquée à toute paire
source/réceptrice du monde.

`taux` est un nombre DÉJÀ RÉSOLU par l'appelant (peut composer plusieurs
propriétés, ex. `valeur_nutritive_energie * comestibilite` pour
« manger ») — `consommer.gd` ne lit et ne connaît aucun nom de propriété
de domaine, seulement des noms de RÉSERVE. Même discipline que
`frappe.gd` : ne transforme jamais l'objet source lui-même, rend
seulement un flag `source_epuisee` — c'est au câblage du banc d'appeler
`produit.gd:transformer` quand ce flag est vrai.

CONSERVATIF PAR CONSTRUCTION — la conservation est une garantie DU
MÉCANISME, jamais une discipline demandée à l'appelant. Le receveur gagne
la quantité RÉELLEMENT retirée à la source (`reserve_avant -
reserve_apres`), jamais la quantité DEMANDÉE (`taux*delta`) : demander
plus que la source ne possède ne crée aucune matière, la somme
source + receveur est invariante quels que soient le taux et le delta.
RÉSULTAT NÉGATIF, à ne pas refaire : pendant trois chantiers le crédit
valait la quantité demandée, et chaque appelant devait pré-borner
lui-même (`min(demande, restant)`, puis `delta=1.0`) — `ecoulement.gd`,
`banc_fertilite.gd`, `banc_erosion.gd` l'ont tous fait, chacun découvrant
le défaut par son propre test. Trois contournements du même défaut sont
la preuve d'une dette du MÉCANISME, pas d'une exigence légitime envers
les câblages : une invariante physique (rien ne se crée) se tient là où
elle peut être garantie, jamais déléguée à N appelants qui doivent y
penser. Ne plus jamais demander à un appelant de pré-borner.

## Dépense : réserve bornée à zéro

DÉCIDÉ (bug fermé 2026-08-07, décision Yael) : `scripts/depense.gd` borne
désormais `reserve` à `0.0` À LA SOUSTRACTION (`max(0.0,...)`), jamais
négative. Une chose porte un ENSEMBLE NOMMÉ de réserves
(`proprietes.reserves.<nom>`, ex. `proprietes.reserves.energie.reserve`),
chacune indépendante.

ANCIENNE DOCTRINE ABANDONNÉE, à ne pas reproposer telle quelle : une
réserve non bornée devait laisser la valeur négative mesurer la
profondeur du manque, pour une remontée proportionnelle future (un manque
profond remonte plus lentement, ou coûte plus cher à combler, qu'un
manque léger). Jamais implémentée — aucun mécanisme du dépôt ne lisait
cette profondeur — et le symptôme observable (un `reste=` négatif affiché
au banc combustible après extinction) l'a emporté sur l'idée non
concrétisée. Si la remontée proportionnelle au manque redevient un besoin
réel, elle se reconçoit sur une AUTRE mesure explicite (ex. un compteur
de temps passé à zéro), pas sur une réserve laissée négative.

Le coût vient de la DÉPENSE, jamais du simple écoulement du temps : une
réserve ne descend que parce qu'un `cout_base` (l'état de la chose) et un
`surcout_action` (l'action en cours) le disent, tous deux en données. Le
temps (`delta`) ne fait que discrétiser le calcul, il n'est jamais la
cause — une chose au repos, sans coût d'état ni action coûteuse, ne perd
rien même si le temps passe.

Distinction avec `extinction.gd`, à ne pas confondre : `depense.gd` est
INTERNE et sans portée — la chose se ponctionne elle-même, personne
d'autre n'intervient. `extinction.gd` est une consommation par des AGENTS
À DISTANCE — le chantier ne bouge que si quelqu'un vient le manger.
Deux formes de décroissance, jamais la même : l'une vient de ce qu'on
EST, l'autre de ce qu'on SUBIT.

Le câblage action → surcoût (résoudre la clé de l'action en cours en un
nombre `surcout_action` à poser sur le canal concerné) vit provisoirement
dans le banc, comme les autres catalogues de câblage de `banc_p1.gd`
(`cible_pour_decision`, `feu_le_plus_proche`). Il devra migrer avec
`_monde` le jour où celui-ci portera le vrai monde à objets-propriétés
(voir "_monde est le contenant réel du jeu" ci-dessous et `CARTE.md` §2
`monde.gd`) — même destin que le reste du câblage aujourd'hui jetable.

## Scalaire ambiant à deux composantes : deux lois de composition, jamais une seule

`vent.gd` (vecteur) et `temperature.gd` (scalaire) partageaient déjà un
patron — sources locales possédées par l'appelant, superposition additive,
atténuation `(1 - distance/rayon) ^ exposant`. `lumiere.gd` (chantier
« lumière ambiante — scalaire ambiant avec température de couleur »,
`CARTE.md` §2) est le premier scalaire ambiant à porter DEUX composantes
couplées — intensité et couleur — et elles n'obéissent PAS à la même loi
de composition, décision tranchée dès l'écriture plutôt que découverte
après coup :

- L'INTENSITÉ (combien de lumière) est ADDITIVE, comme le vent ou la
 chaleur : deux sources qui se recouvrent s'AJOUTENT, bornée à `[0.0,
 1.0]` (un plafond physique que `temperature.gd` n'a pas — rien
 n'empêche une température de dépasser toute référence).
- La COULEUR (quelle teinte) est une MOYENNE PONDÉRÉE, jamais additive :
 deux sources qui se recouvrent rendent une teinte ENTRE les deux, pas
 « plus forte ». Le poids de chaque source est SA PROPRE contribution
 d'intensité à ce point — la couleur ne se calcule jamais indépendamment
 de l'intensité, les deux boucles partagent le même poids.

Généralisable : une grandeur qui s'ACCUMULE (énergie, matière, force) suit
l'addition ; une grandeur qui QUALIFIE (teinte, timbre, texture) suit la
moyenne pondérée par ce qui la porte. Confondre les deux — additionner des
couleurs, moyenner des intensités — produit un résultat qui ne correspond
à aucune intuition physique. Un futur scalaire ambiant à plusieurs
composantes doit trancher, composante par composante, laquelle des deux
lois s'applique — jamais supposer que la même loi vaut pour toutes.

## Champ ambiant occulté : l'occlusion sort de la perception

L'occlusion (une chose entre A et B atténue ce qui passe) n'appartient plus
à `perception.gd` : sa géométrie vit dans `scripts/occlusion.gd`, appelable
par n'importe quel mécanisme (chantier « ombre pluviométrique », `CARTE.md`
§2). `perception.gd:_facteur_obstacles` subsiste et délègue — la doctrine
« l'occlusion vit dans `perception.gd`, pas dans `monde.gd` » (voir
Perception : profil et cadence) reste vraie sur le FOND : la propriété qui
atténue est toujours nommée par le canal, jamais par le contenant spatial.
Ce qui change : elle n'est plus RÉSERVÉE à la perception.

`champ_occulte.gd` est le premier autre appelant. Ce qu'il ajoute au dépôt,
et qui n'existait nulle part : un champ ambiant qui rend une INTENSITÉ
atténuée par la distance ET par les obstacles. Les deux moitiés existaient
et ne se parlaient pas — `temperature.gd`/`lumiere.gd` ignorent les
obstacles, `perception.gd` connaît les obstacles mais rend une liste filtrée,
jetant l'intensité qu'il calcule pourtant en interne.

**Ce n'est PAS une neuvième nature de mécanisme** (voir Direction majeure) :
c'est de la LECTURE PURE, la première des natures déjà nommées. Il ne mute
rien ; c'est au câblage d'écrire ce qu'il rend.

Trois règles qui commandent tout champ futur :

- **Une intensité, jamais un booléen.** Derrière un obstacle, la valeur est
 RÉDUITE, jamais coupée — une ombre, pas une frontière. Un filtre
 perçu/non-perçu (ce que `perception.gd` est, par construction) ne peut pas
 produire un gradient : il produit une frontière nette, qui ne ressemble à
 rien de physique.
- **Deux lois d'atténuation par distance coexistent, délibérément.** La
 LINÉAIRE BORNÉE (`(1 - d/rayon)^exposant`, nulle au bord) de `vent.gd`/
 `temperature.gd`/`lumiere.gd`/`perception.gd` décrit une influence à
 portée FRANCHE — au-delà, plus rien. La PUISSANCE INVERSE
 (`force / d^exposant`, jamais nulle) d'`occlusion.gd:attenuer_par_distance`
 décrit une influence SANS portée — la mer se fait sentir partout, de moins
 en moins. Choisir selon ce qu'on modélise ; ne pas les refondre en une
 seule, elles ne disent pas la même chose.
- **Le facteur d'occlusion est borné `[0,1]`, donc toute grandeur physique
 brute doit être NORMALISÉE EN DONNÉE avant d'y entrer.** Une altitude de
 14.0, une densité de 7.87 y clampent à 1.0 : blocage total, aucune
 gradation. C'est une propriété normalisée qui entre (`relief_bloquant`,
 dérivée de l'altitude à la construction de la grille) — jamais la grandeur
 elle-même. Même geste que `densite` pour le canal `radiation`.

## Exemple travaillé : l'animal photosynthétique

Un cas concret pour la dépense à réserves multiples (`depense.gd`), la
composition multiplicative des carences et les transformations qui
atteignent l'immuable — les trois à la fois.

Deux besoins non substituables : ÉNERGIE (lumière — partout, mais
EXPOSANTE, il faut être à découvert pour la recevoir) et MATIÈRE (herbe
— rare et localisée, il faut la chercher). L'un ne compense jamais
l'autre : un animal gorgé de lumière mais sans matière ne s'en porte pas
mieux. C'est la composition multiplicative des carences (voir Lecture
des calques), pas une moyenne des deux.

Les deux réserves croisées produisent QUATRE régimes, pas deux : énergie
haute/matière haute, énergie haute/matière basse, énergie basse/matière
haute, énergie basse/matière basse. Un seul de ces quatre permet la
reproduction — celui où les deux réserves sont hautes. Aucun cas
particulier codé : c'est la lecture croisée de deux jauges, comme
n'importe quelle composition multiplicative.

La carence en MATIÈRE spécifiquement dégrade par paliers, en escalier
(les `seuils` de `depense.gd`), chacun une CAUSE posée, jamais un
résultat :
- premier palier — la reproduction se coupe. Réversible : la cause se
 retire dès que la matière revient.
- deuxième palier — le muscle est consommé, lentement, partiellement.
 Encore réversible, mais lent à reconstruire.
- troisième palier — la structure elle-même est atteinte,
 IRRÉVERSIBLE : le plafond de l'animal baisse à vie. Ce n'est plus un
 calque qui s'empile, c'est une transformation qui atteint l'immuable
 (voir « Piste ouverte — transformations qui atteignent l'immuable »,
 qui citait déjà la reproduction comme candidat) : elle change la
 forme elle-même, pas ce qui se lit par-dessus.

## Exemple travaillé : la croissance végétale — FERMÉ (`banc_croissance.gd`, `CARTE.md` `banc_croissance`)

Même patron que l'animal photosynthétique ci-dessus, appliqué à la
CROISSANCE plutôt qu'à l'entretien. ÉCART ASSUMÉ entre l'intention posée
ici à l'origine et le chantier réel : l'intention envisageait DEUX SOURCES
via `flux.gd` (un couple `{ source, receptrice, cible }` pour la lumière,
un pour l'eau) ; le chantier lit `lumiere_locale` DIRECTEMENT (`lumiere.gd`)
et un canal `charge.gd` dédié pour l'eau — `flux.gd` n'intervient que pour
la TROISIÈME réserve (maturité), celle qui MONTE, via un émetteur
synthétique dont le taux compose les deux premières. Le principe posé ici
reste vrai : si une des deux sources manque, la croissance ralentit ou
s'arrête, jamais compensée par l'autre — même composition multiplicative
que « Lecture des calques » et que les quatre régimes croisés de l'animal
photosynthétique ci-dessus. Détail exact du câblage : `CARTE.md`
`banc_croissance`, `docs/prototypes.md`.

## Cause, jamais résultat : ce qu'une transformation pose

Un seuil (`depense.gd`) ou une transformation (`a_zero`, table de
transformations à venir) ne pose jamais un résultat calculable — jamais
`vitesse : 0.5` en dur. Il pose une CAUSE : `carence_matiere : true`,
`carence_energie : true`. Le résultat (vitesse, portée, fécondité...) se
calcule à la LECTURE, à partir de l'ensemble des causes présentes sur
l'objet à cet instant, jamais posé directement par la transformation qui
l'a déclenché.

Pourquoi : deux transformations qui posent chacune un résultat s'écrasent
si elles visent la même clé — l'ordre d'application décide, silencieusement.
Deux transformations qui posent chacune leur propre cause ne s'écrasent
jamais : elles s'accumulent, et la lecture les combine, quel que soit
l'ordre dans lequel elles ont été posées. C'est le même principe causal
que pour les calques (voir Questions ouvertes, « calque vs mutation de
forme » — la question du SUPPORT y reste ouverte, mais le principe
causal qui suit est, lui, acquis) : un calque s'empile au-dessus de la
forme et se lit au moment du calcul, il n'écrase jamais rien. Conséquence
directe : deux seuils de `depense.gd` à
la même valeur redeviennent légitimes dès que leurs `poser()` visent des
causes disjointes — rien à refuser, l'écrasement qui rendait ça dangereux
disparaît avec la règle.

## Lecture des calques : composition multiplicative, pas additive

Tirée du vivant : deux carences ne s'additionnent pas. Chacune détruit le
mécanisme qui compensait l'autre — le système passe d'amorti à cassant.
La lecture qui combine plusieurs causes présentes sur un objet est donc
MULTIPLICATIVE, jamais additive : `vitesse = base * f(carence_matiere) *
f(carence_energie)`, jamais `base - carence_matiere - carence_energie`.
Une composition multiplicative peut franchir un palier que ni l'une ni
l'autre des causes n'aurait atteint seule — c'est voulu, c'est l'effet
recherché : la fragilité de la combinaison doit pouvoir dépasser la somme
des fragilités individuelles.

## _monde est le contenant réel du jeu

_monde n'est pas une structure jetable. C'est le monde : terrain, reliefs,
environnements, et à terme la génération procédurale. Il doit rester et
porter des objets à propriétés { id, position, proprietes }, comme tout le
reste. _monde_stub n'est qu'un échafaudage de test destiné à fusionner dans
_monde une fois que _monde porte la bonne forme (y compris la requête
spatiale choses_dans_rayon que la perception appelle). Ne jamais supprimer
_monde : ce serait jeter le concept parce que son implémentation provisoire
(nominal + bool) est pauvre.

## Correction des couches

L'ancienne formule "couche 2 = perception = saillance" est FAUSSE.
Deuxième correction : "universel = proximité" est FAUSSE aussi. La
proximité est un fait spatial, pas l'interprétation du monde. Elle
occupait la place d'une couche qui manquait.

Trois temps, dans cet ordre, identiques pour tous les colons :

1. PERCEPTION — ce qui entre dans le rayon. Un objet, sa position, sa
 distance, sa taille. Neutre, commun. Gaston et Sobre voient
 exactement la même chose.

2. INTERPRÉTATION UNIVERSELLE — les faits vrais pour tous : c'est une
 bouteille, c'est du pinard, c'est inflammable, c'est opaque. Ne
 dépend d'aucun colon. Sobre ne voit pas "pas du pinard": il voit du
 pinard, comme Gaston. Le fait ne connaît pas celui qui regarde.

3. SAILLANCE INDIVIDUELLE — la valeur pour CE colon : ça me menace, ça
 m'attire, je m'en fiche. Gaston s'allume, Sobre reste au plancher.
 Même entrée, valeurs opposées. C'est la divergence, et c'est elle
 qui produit l'histoire.

La couche 2 EXISTE DÉJÀ : c'est Objet.fabriquer qui lit types.json une
fois et pose proprietes, avant tout colon, identique pour tous. Son
problème n'est pas d'être absente — c'est que son vocabulaire est
incomplet à certains endroits et court-circuité à d'autres.

Deux fautes distinctes, à ne pas confondre :

- CONTOURNEMENT d'une couche 2 complète : la réponse est déjà dans
 proprietes, le code va la rechercher par nom au lieu de la lire. Rien
 à ajouter en données.
- VOCABULAIRE MANQUANT : couche 2 n'a jamais dit ce qui distingue un
 arbre d'une bâtisse, donc une couche plus haute va le chercher dans le
 nom (`instance.type != attache.type`) — une question de couche 2 posée
 ailleurs qu'en couche 2.

Instances actuelles de ces deux fautes, avec fichier et numéro de ligne :
voir `CARTE.md` §6 ou `docs/prototypes.md`, pas ici — ce sont les fichiers
mis à jour à chaque session. Un numéro de ligne cité dans CE fichier
périme dès que le code bouge sans que personne n'y repense (ça s'est déjà
produit).

TRAIT vs IDENTITÉ. vegetal : true est un TRAIT : plusieurs choses peuvent
le porter, aucune n'a besoin d'être nommée pour ça. espece : "arbre" ou
est_arbre est le type maquillé — un mot que seule une chose peut porter.
Règle opposable : un trait doit pouvoir être porté par des choses qu'on
n'a pas encore imaginées. Ajouter un buisson en données doit suffire à
ce que le fanatique le défende, sans une ligne de code.

Trois pistes écartées pour combler le vocabulaire manquant, à ne pas
reproposer :
- tag type immuable : un nom comparé reste un nom, immuable ou non ;
- propriété d'identité "espece"/"est_arbre": donnée universelle
 déguisée pour répondre à une question individuelle ;
- liste d'ids côté colon : un registre consulté — remplacer un == sur
 un nom par un `in` sur une liste est le même geste.

Un colon ne reconnaît rien et ne consulte rien. Il perçoit, l'universel
dit ce que c'est, et sa saillance monte ou non selon ce qu'il est. Le
fanatique n'a pas sa forêt en mémoire : la forêt pèse chez lui et pas
chez le bâtisseur.

AMENDÉ, et il faut le lire avec ce qui précède : « ne consulte rien » vaut
toujours contre un REGISTRE D'IDENTITÉS déclaré en donnée (les trois pistes
écartées ci-dessus). Il ne vaut plus contre une COPIE née de ce que le colon
a lui-même perçu — voir « La croyance : une copie partielle, née de la
perception vécue », plus bas.

Corollaire : la saillance est une VALEUR, pas une appartenance.
attaches.gd rend un nombre, jamais une position ni une identité — c'est
pour ça qu'un mécanisme séparé retrouve OÙ aller, une fois la décision
prise (voir « Cible par verbe : vers quoi va le colon », plus bas). Une
couche qui rendrait "c'est cet objet-là" serait un registre, pas une
saillance.

DEUX SOURCES DE SAILLANCE, additives, jamais confondues :

- ATTACHE PAR TRAIT { propriete, force }: collective par nature. Le
 fanatique s'allume sur toute forêt, même une qu'il n'a jamais vue. Vit
 dans les données du colon.
- LIEN PERSONNEL : cet objet-là précisément — sa chambre, la forêt qu'il
 a défendue trois fois. Naît de l'usage, vit côté agent, JAMAIS sur
 l'objet. Un objet ne sait pas qu'il est aimé.

Les deux alimentent la même couche 3 et se concatènent comme att + prox :
dominance ne distingue pas les sources. Sa propre forêt pèse trait PLUS
lien, sans aucun cas particulier — il partira quand même défendre une
autre forêt si elle est plus menacée.

Le lien personnel rend saillant CE QUI S'EN APPROCHE : un colon près de
sa forêt devient menaçant, le même colon ailleurs n'est rien. La menace
est dans la relation, pas dans l'autre colon.

À faire plus tard, hors de cette correction : la saillance varie dans le
temps (monte, retombe), pas seulement selon l'état de l'attache (intacte
basse / menacée haute, voir plus bas). Évolution de la couche 3, pas sa
fondation. Le lien personnel, lui, est FERMÉ depuis (PHASE 5, voir « Le
chantier » plus bas) : il naît d'un événement (avoir défendu, avoir
dormi dedans), jamais posé en dur dans un fichier de données — ce qui
aurait recréé le registre écarté plus haut.




## La croyance : une copie partielle, née de la perception vécue

ÉVOLUTION DE DOCTRINE, tranchée par Yael, nommée avant la première ligne de
code (`CLAUDE.md`, Discipline point 3 : « NOMMER LA DÉRIVE »). Ce qui précède
posait « un colon ne reconnaît rien et ne consulte rien ». Une entité porte
désormais une COPIE PARTIELLE de ce qu'elle a PERÇU, avec une CERTITUDE par
champ, et ce sont les couches de saillance qui lisent cette copie — plus le
monde.

**Pourquoi ce n'est pas le registre écarté.** La contradiction est levée
exactement là où elle l'a déjà été pour le lien personnel (voir « Correction
des couches », DEUX SOURCES DE SAILLANCE) : la croyance NAÎT D'UN ÉVÉNEMENT
VÉCU — avoir perçu, avoir touché, avoir entendu quelqu'un — et n'est JAMAIS
posée en dur dans un fichier de données. Un registre déclaré en donnée serait
toujours la même faute ; une trace laissée par ce qui est arrivé au colon ne
l'est pas.

**Pourquoi ce n'est pas BDI** (voir « Contraintes structurelles ») : les
quatre griefs qui ont fait rejeter Bratman portent sur la déformation placée
APRÈS la perception, l'énumération de goals candidats, les plans pré-écrits et
l'intention défendue contre la distraction. La croyance REMPLACE L'ENTRÉE de
la couche 2 et ne touche à aucune des quatre couches : elle ne tombe sous
aucun des quatre. Le mot *belief* décrit ce qu'on voit de l'extérieur ; il ne
ramène pas la mécanique avec lui.

**Trois conséquences qui commandent tout mécanisme futur de connaissance:**

- **CE QUI EST COPIÉ EST LE MONDE, JAMAIS LA CONFIGURATION.** Une propriété du
 monde (`comestible`, `brule`) est perceptible et devient donc objet de
 croyance ; un champ de configuration technique (`profil_saillance`,
 `transformation`, `materiau` — voir « Propriété du monde vs champ de
 configuration technique ») n'est capté par aucun canal et traverse la copie
 intact. Il ne décrit pas ce que la chose EST pour le colon, il dit au MOTEUR
 quelle règle s'applique. Confondre les deux rendrait la couche 2 muette sans
 qu'aucun test ne rougisse.
- **CE QUI N'A JAMAIS ÉTÉ PERÇU EST ABSENT, jamais présent à zéro.** « Je ne
 sais pas » et « je sais que non » sont deux états distincts, et le second
 s'acquiert — par le contact, par l'usage, par la parole d'un autre.
- **LE DOGME EST UNE CONSÉQUENCE, PAS UNE RÈGLE.** Au-delà d'une certitude
 seuil, une correction est refusée. Cette certitude ne vient que d'avoir
 REGARDÉ souvent : deux colons au corps identique divergent par la seule
 fréquence à laquelle ils reviennent vérifier (« Les archétypes n'existent
 pas », appliqué à la connaissance). Rien dans le moteur ne nomme un
 « dogmatique ».

**La crédibilité d'une source n'est pas un concept neuf**: un autre colon est
une chose comme une autre, et `liens_personnels` porte déjà une force colon →
chose. La parole de quelqu'un pèse ce que pèse le lien qu'on a vers lui —
zéro mécanisme ajouté pour ça.

Ce que la croyance NE couvre pas : la MÉMOIRE SPATIALE (retenir OÙ était une
chose, et non ce qu'elle est) est un mécanisme DISTINCT, `memoire_spatiale.gd`
— la copie de croyance rend toujours la position VIVANTE, un colon qui n'aurait
qu'elle suivrait par télépathie une chose qui bougerait. Les deux ne se
recouvrent pas et ne s'appellent pas : ce qu'une chose EST et OÙ elle était
sont deux questions séparées, et rien n'oblige un percevant à porter les deux.
Contrat exact du mécanisme :
`CARTE.md` §2, `scripts/croyance.gd` ; premier câblage observable :
`CARTE.md` `banc_stress_thermo_vivant`, `docs/prototypes.md`.

## Principe

LE COLON PERÇOIT SON MONDE ; IL N'EN LIT PAS LA LISTE.

Au-dessus du monde brut — ce qui existe, sans jugement : un feu, un arbre,
un homme au sol — quatre couches :

1. LA PERCEPTION — brute, aveugle, exhaustive dans le rayon du colon.
 Elle rend ce qui existe autour de lui, sans tri, sans poids : pas
 encore des saillances. Une entité qui perçoit ne se perçoit jamais
 elle-même — filtre unique dans `perception.gd`, jamais dans les
 appelants (chantier « colon saillant » : le jour où un type devient
 saillant, ce filtre l'empêche de se voir).
2. LA SAILLANCE — le colon ne voit pas des objets, il voit ce qui COMPTE
 POUR LUI. Deux colons face à la même perception n'en tirent pas la
 même chose.
3. LA DOMINANCE — pas un tri, un écrasement. La saillance la plus haute
 écrase les autres : elles deviennent invisibles, pas secondaires.
4. AGIR — parmi ce qui reste visible, le colon choisit une action.
 L'inertie y pèse : une tâche commencée résiste au changement.

Dominance et agir sont deux verbes distincts : l'une écrase, l'autre
choisit. Ne pas les fusionner. Perception et saillance aussi : la
perception est aveugle, la saillance ne l'est pas — voir État des
couches.

Trois propriétés d'une saillance — INERTIE et DOMINANCE, déjà posées
ci-dessus (exemple d'inertie : le pion qui fait cinq secondes de mur
puis change d'avis, supprimé ; exemple de dominance : un homme qui
saigne rend le caillou invisible, pas juste secondaire), plus une
troisième :

- SATURATION — une tâche négligée monte lentement. Le sol sale finit
 par battre l'oisiveté ; pas de liste de priorités 1-4, une pression
 auto-régulée.

## Règle dure : moteur/données

Rappel (règle complète et test opposable : `CLAUDE.md`, « ADN : le
moteur ne connaît que des verbes ») — pourquoi elle tient, trois
raisons :

- ÉCHELLE — des centaines de traits, d'événements, de factions. En dur,
 illisible.
- ORGANIQUE — les combinaisons ne s'écrivent pas, elles émergent. Le
 moteur additionne les effets qu'il trouve.
- LE LLM — il lit un fichier de données, pas le code source. Sans
 données, le narrateur est aveugle.

## Les bancs : le livrable est le test vert, jamais l'image

Un banc n'est pas forcément une démo jouable. Son livrable est le TEST
VERT qui prouve qu'une entrée de `data/` fonctionne avec le cœur. Le
visuel est un outil de mise au point, pas un produit : dès que le test
est vert, le banc a rempli son rôle — polir son affichage est du temps
perdu.

Un banc ne se supprime JAMAIS, même quand il paraît obsolète. Il est la
seule régression automatique sur les données : le jour où le cœur change
et qu'une entrée JSON cesse de passer, c'est le banc qui rougit, rien
d'autre ne le fait.

Ce qui se jette et ce qui ne se jette pas, précisément : le banc en
surface — la scène, l'image, les touches, la mise en situation — n'est
définitif en rien ; ce n'est pas le jeu, on le modifie librement, on s'en
fout. Ce qui compte est DESSOUS : les connexions qu'il établit entre une
entrée de `data/` et les mécanismes du cœur. C'est ça qui est acquis, et
c'est ça que le test verrouille. Modifier un banc est gratuit ; le
supprimer coupe les connexions et personne ne le voit passer.

Ce qu'un banc doit montrer, et ce qui lui manque encore pour l'observer :
`docs/prototypes.md`, jamais ici.

## L'LLM : lecteur ancré, jamais auteur (règle portante)

Frontière : cette section pose une règle qui contraint TOUT code écrit
ensuite, au même rang que « moteur/données » ou « Vector3 partout ».
Elle ne décrit pas un système à coder aujourd'hui ; elle fixe une
condition que chaque système futur doit respecter — rien ici n'exige de
coder un LLM aujourd'hui. Elle est posée maintenant parce qu'elle ne se
rétrofitte pas, comme Vector3 ou l'i18n : un seul état du monde rendu
illisible, un seul colon rendu non-résumable, et l'ancrage est percé le
jour où l'LLM se branche. Le coût est nul aujourd'hui, entier plus tard.

Le jeu tournera sur SERVEUR, et un ou plusieurs LLM y liront le monde pour
produire ce que le moteur ne calcule pas : dialogue, dynamiques politiques,
négociation. La règle est unique et dure :

**L'LLM EST UN LECTEUR DE LA SIMULATION, JAMAIS L'AUTEUR DE SON ÉTAT.**

Le moteur est la seule autorité sur ce qui est vrai. L'LLM lit cet état et
l'habille en langage. Il ne décide jamais un fait du monde ; s'il en pose un
que le moteur ignore, c'est une hallucination — et une hallucination est un
passif, surtout hors jeu (assurance, simulation à tolérance zéro pour le fait
inventé).

### Trois propriétés du matériau LLM commandent la règle

Ce ne sont pas des précautions. Ce sont des faits établis sur les LLM, à
traiter comme des contraintes physiques du matériau.

- ANCRAGE (grounding). Un LLM laissé libre complète avec le mot le plus
 probable, pas le vrai. On supprime l'hallucination en DÉCOUPLANT la
 génération de la connaissance : les faits vivent hors du modèle, dans une
 source que la génération est forcée d'utiliser. Corollaire dur, à ne pas
 rater : lire ne suffit pas. Un modèle peut lire toute la chronique et
 halluciner quand même — il « fait plus confiance » à son pré-entraînement
 qu'au prompt (biais de connaissance paramétrique). L'accès à la vérité doit
 donc être DOUBLÉ d'une contrainte qui l'impose (voir Pipeline, point 4).

- STATELESSNESS. Chaque appel à un LLM est indépendant : le modèle n'a
 aucune mémoire d'un appel à l'autre, toute continuité doit être ré-injectée
 dans le prompt à chaque fois. Ici c'est un AVANTAGE, pas un défaut : pas de
 mémoire conversationnelle fragile qui dérive ; l'LLM repart de la vérité de
 terrain à chaque appel, jamais d'un souvenir accumulé. Mais ça impose que
 le monde sache se re-présenter en entier, à chaque tour, en peu de jetons.

- POURRISSEMENT DU CONTEXTE (context rot / lost in the middle). La qualité
 d'un LLM chute quand on le gave : information au milieu d'un long contexte
 ignorée (courbe en U, chute d'attention mesurée), dilution de l'attention,
 interférence des distracteurs. Ça s'aggrave à CHAQUE tranche ajoutée, pas
 seulement près de la limite. Donc « le jeu nourrit l'LLM » ne peut jamais
 vouloir dire « le jeu déverse tout l'état ». Il donne la BONNE TRANCHE
 RÉSUMÉE — le pertinent, jamais le firehose.

### Ce que la règle impose à tout code futur

1. TOUT ÉTAT DU MONDE VIT EN DONNÉE LISIBLE. Déjà l'ADN (« moteur/données »),
 mais ici la raison change et se durcit : ce n'est plus seulement pour
 ajouter du contenu sans code, c'est la CONDITION de l'ancrage. Un seul
 fait caché dans le code est un fait que l'LLM ne voit pas — donc un trou
 par lequel il hallucinera. Data-lisible et zéro-hallucination sont la même
 exigence, pas deux qui s'opposent.

2. LE JEU ALIMENTE L'LLM PAR TRANCHE RÉSUMÉE, JAMAIS PAR FIREHOSE. Le
 mécanisme qui produit cette tranche existe déjà sous deux autres noms : la
 RÉSUMABILITÉ (un colon se compresse en quelques nombres, voir « Deux
 régimes de simulation ») et les DEUX RÉGIMES eux-mêmes (faction lointaine =
 état grossier, instanciée à l'approche). « Le jeu nourrit l'LLM » et « un
 colon doit être résumable » sont la même exigence vue des deux bouts.

3. L'ÉTAT PAR INSTANCE DOIT TENIR DANS LE PROMPT. Pour que l'LLM narre le
 comportement d'un colon sans halluciner, sa déformation individuelle
 (cicatrice, set-point dérivé) doit être lisible ET courte. Un vecteur
 résumable tient dans un prompt ; un historique lourd, non. C'est un
 troisième argument — avec la résumabilité et les deux régimes — qui pousse
 la décision de forme de la déformation individuelle vers le VECTEUR. La
 décision se tranche ailleurs, mais une de ses contraintes vient d'ici.

4. AUCUNE COUCHE N'EST CRUE SUR PAROLE : PIPELINE ANCRER → GÉNÉRER →
 VÉRIFIER. Un modèle ancre (tient l'état vrai, lit la chronique et les
 données), un modèle génère (contraint par l'ancre), un modèle vérifie
 (confronte la génération à la chronique, signale la contradiction avant
 qu'elle atteigne le joueur). C'est le même principe que le moteur : aucune
 couche ne décide seule, le pipeline contraint. C'est ce qui rend « zéro
 hallucination » atteignable — pas un modèle parfait, un pipeline
 structurellement intolérant au fait non vérifié. Le nombre exact de
 modèles est un choix de design, ouvert par le serveur (voir ci-dessous),
 pas une contrainte matérielle.

5. LE JOUEUR N'EST JAMAIS LA SOURCE DE VÉRITÉ DE L'LLM. Dans un chatbot, les
 mots du joueur SONT le monde, donc l'LLM confabule la continuité. Ici,
 l'inverse : le joueur est un acteur DANS le monde ; il agit, l'état change,
 l'LLM lit l'état changé. Un joueur absent, qui ment ou qui oublie ne
 désinforme pas l'LLM — ses faits sortent de la donnée, jamais de la bouche
 du joueur. Le joueur ne « rend » aucune information à l'LLM.

6. QUAND LA PREUVE MANQUE, REFUSER OU ESCALADER, JAMAIS GÉNÉRER À FAIBLE
 CONFIANCE. Un LLM sans donnée sur un point doit dire qu'il n'a rien, pas
 combler. Le silence est une information ; le fait inventé est un passif.

### Pourquoi le serveur, et pourquoi maintenant

Le serveur n'est pas un détail de déploiement, c'est l'ACTIVATEUR. Un pipeline
de plusieurs modèles en séquence est impossible sur la machine d'un joueur (on
n'y fait pas tourner 3–4 modèles à latence jouable). Côté serveur, le calcul
est centralisé et amorti sur tous les joueurs : « combien de modèles » cesse
d'être une contrainte matérielle et devient un choix de design. Le moteur
était déjà taillé pour ça — sim indépendante du rendu, RNG seedé,
résumabilité : les règles posées « pour garder la porte du multijoueur
ouverte » sont exactement celles d'un déploiement serveur.

Conséquence directe : Orion n'est pas un simulateur de colonie, c'est un
moteur qui doit pouvoir rejouer N'IMPORTE QUELLE scène — siège, razzia,
montée de civilisation, phénomène pas encore imaginé — en données seules,
sans une ligne de code par phénomène. Un scénario est un état initial plus
des règles, tous deux en données ; le moteur ne nomme aucun phénomène.

## Deux dimensions d'universalité, pas une.

Le test hors domaine prouve l'indifférence au DOMAINE : un phénomène inventé
traverse le même code sans ligne ajoutée. Il reste l'indifférence à
l'ÉCHELLE : la même scène doit tourner à toute échelle de temps et de
nombre — trois individus sur une journée comme une ville sur cinq mille
ans — sans changer de lois. Seule l'échelle, posée en données, change ; le
moteur ne sait pas s'il joue « petit » ou « grand », il applique les mêmes
lois. Une loi qui ne tiendrait qu'à une échelle n'est pas une loi. Cette
exigence a déjà ses mécanismes dans ce fichier, sous d'autres noms : la
contrainte de RÉSUMABILITÉ (un colon se compresse en quelques nombres) et
les DEUX RÉGIMES DE SIMULATION (une faction lointaine est un état
grossier ; instanciée en colons à l'approche du joueur). Un scénario
« civilisation avancée au départ » n'est rien d'autre qu'un état résumé
posé à la main que le moteur instancie — le même mécanisme qui résume un
village lointain sert à démarrer une partie à mi-course.
L'indifférence à l'échelle est une EXIGENCE distincte de l'indifférence au
domaine, pas automatique : un mécanisme prouvé générique par un test hors
domaine n'est pas prouvé pour autant indifférent à l'échelle de temps ou
de nombre — rien ne garantit l'un par l'autre, seule une vérification
dédiée le ferait. Résumabilité et deux régimes sont écrits ici comme
intentions ; leur vérification est un chantier à part entière.

## Le modèle : attaches et forme

Une ATTACHE lie le colon à un TRAIT perçu : `{ propriete, force }`. Rien
de plus — une des deux sources de saillance individuelle (voir
Correction des couches, DEUX SOURCES). L'idéologie donne des attaches
par trait ; le vécu donne des liens personnels, qui ne vivent jamais
dans cette liste. Le moteur n'a pas à savoir POURQUOI une attache
existe, mais il distingue bien SES DEUX MÉCANISMES : lecture de
propriété d'un côté, lien colon-objet précis de l'autre.

Une FORME est antérieure aux attaches. Elle ne les crée pas, ne les
transforme pas : elle déforme comment elles se forment et jusqu'où
elles montent. Immuable. C'est la forme du seau, pas son contenu.
(Nommée "forme" et non "trait" dans le code — "trait" est un mot
réservé du langage.)

Deux effets pour une seule attache :

- attache intacte → saillance BASSE (familiarité)
- attache menacée → saillance HAUTE

OPTION B, tranchée : le monde n'émet aucun drapeau "menacé". Il émet
des choses, séparément — un feu, un arbre. Le colon perçoit les deux
et fait le lien LUI-MÊME. Le rayon de liaison vient de la forme. La
fonction compare des distances ENTRE CHOSES perçues, jamais la
distance au colon. Deux colons face à la même scène concluent
différemment. Le colon peut se tromper.

RÈGLE ANTI-BRUIT : le colon se trompe toujours dans le sens de son
trait. Le stressé relie trop, le placide trop peu. Jamais l'inverse.
Aucun hasard : l'erreur est déterministe, lisible après coup depuis la
forme qui l'a produite.

TRANCHÉ : un lien personnel n'est jamais collectif par défaut — rien
dans le moteur ne donne gratuitement la solidarité entre deux colons
liés chacun à leur propre chose.

L'ÉLARGISSEMENT, précisé : « mon arbre devient les arbres » n'est pas
une attache qui change de portée — { propriete, force } ne peut pas
viser un objet précis sans recréer une identité. C'est le passage d'une
source à l'autre : le colon lié à CET arbre finit par porter une
attache au trait vegetal. Le lien demeure, l'attache s'ajoute. Le
mécanisme (ce qui déclenche ce passage) : FERMÉ (PHASE 5 étape 4) — voir
Questions ouvertes pour le détail (`attache_par_trait.gd`, seuil
composite nombre ET force).

## Les archétypes n'existent pas — un espace continu

« Fanatique », « bâtisseur », « placide » ne sont pas des types de
colons. Ce sont des points dans un espace continu, et rien dans le
moteur ne les connaît.

Un colon porte une LISTE d'attaches `{ propriete, force }`, pas une
seule. Les mêmes propriétés sont disponibles pour tous. Ce qui distingue
deux colons est le POIDS qu'ils mettent sur chacune, pas la nature de ce
à quoi ils tiennent.

Exemples, tous en données, zéro ligne de code :
- irremplacable 3.0 / notre_ouvrage 0.0 → le fanatique pur
- irremplacable 0.0 / notre_ouvrage 3.0 → le bâtisseur pur
- irremplacable 3.0 / notre_ouvrage 0.5 → tient surtout à la forêt,
 mais lâche la muraille moins vite qu'un fanatique pur
- irremplacable 1.5 / notre_ouvrage 1.5 → déchiré ; son comportement
 dépend de ce qui est le plus menacé sur l'instant, et il changera
 d'avis selon la situation
- aucune attache → le placide, porté par la seule proximité

Conséquences, à ne pas perdre de vue :

1. Aucun cas particulier par colon n'est possible ni nécessaire. Le
 moteur applique la même règle à tous ; la divergence naît des
 nombres.

2. Le conflit n'est plus entre deux archétypes, mais entre deux
 pondérations. Deux colons qui pèsent les mêmes choses différemment
 se disputent la même situation — c'est plus riche qu'une opposition
 de catégories.

3. Un colon peut être ambivalent, ce qu'un archétype ne permet pas. Un
 fanatique qui tient un peu aux murailles est représentable ;
 « fanatique ET bâtisseur » ne l'était pas.

4. Générer une population devient trivial : tirer des forces au hasard
 produit une colonie où personne n'est identique, sans catalogue de
 personnalités.

5. Corollaire pour les traits : un trait ne doit jamais désigner une
 catégorie de colon. `irremplacable` et `notre_ouvrage` décrivent les
 CHOSES et sont vus identiquement par tous (couche 2, interprétation
 universelle). Seule la force d'attache est individuelle (couche 3).
 Le fait ne connaît pas celui qui regarde.

## Plusieurs verbes par propriété, poids par colon

Une propriété perçue ne propose plus UN verbe, elle en propose PLUSIEURS.
La propriété qui dit qu'une chose brûle ne dicte pas « approcher » à tout
colon qui la perçoit : elle propose un choix — éteindre, attiser (fuir,
voir plus bas) — et c'est le colon qui tranche. Même principe que « Les
archétypes n'existent pas » appliqué à un troisième axe : ce n'est pas la
propriété qui décide de l'action, c'est le poids que CE colon met sur
chaque verbe disponible.

Éteindre/attiser illustrent ce que la mécanique PERMET, pas la donnée du
dépôt : `data/types_choses.json` ne propose aujourd'hui qu'un seul verbe
pour `brule` (`approcher`) — un deuxième verbe réel est un chantier de
design séparé, non tranché. Détail exact de l'état actuel : `CARTE.md` §4.

**La forme.** Le colon porte `proprietes.poids_verbes`, un Dictionary
`verbe -> poids`. Troisième axe de son individualité, au même rang
qu'`attaches` et `forme` (voir « Le modèle : attaches et forme ») —
jamais nesté dans l'un ou l'autre. `attaches` dit à QUOI il tient,
`forme` dit COMMENT cette attache se déforme, `poids_verbes` dit ce
qu'il FAIT une fois qu'une chose retient son attention. Trois questions
disjointes, trois axes, jamais confondus.

**Trois régimes, jamais un continuum flou:**
- poids POSITIF — le verbe est disponible, ce colon peut le choisir.
- poids NUL (ou absent du Dictionary, même chose — voir plus bas) — le
 colon n'a pas d'avis sur ce verbe, il ne le choisit jamais, mais rien
 ne le lui interdit dans l'absolu : c'est un point neutre légitime du
 continuum, pas un refus.
- poids NÉGATIF — le verbe est INTERDIT. Pas « un poids négatif », un
 refus actif : même si c'est la seule option de la liste, ce colon ne
 le fait pas.

Parmi les verbes que propose la propriété résolue, le colon retient
celui dont le poids est le plus haut STRICTEMENT POSITIF. Si aucun verbe
n'est positif chez lui (tous nuls ou négatifs), il ne fait rien de
particulier sur cette chose — même contrat que « chose sans propriété
actionnable » (voir agir.gd, `docs/prototypes.md`) : une chose ordinaire
aux yeux de ce colon, pas un bug. Deux verbes à poids strictement égal :
NON TRANCHÉ, l'ordre d'itération de la liste décide (le premier déclaré
l'emporte) — même famille que « Ordre dans menaces.json » ci-dessous,
un résultat qui dépend d'un détail d'implémentation plutôt que du monde.

Second cas NON TRANCHÉ, distinct du précédent : une chose portant DEUX
propriétés actionnables à la fois (deux clés du catalogue présentes sur
la même chose perçue, chacune avec sa propre liste de verbes) — la
première propriété rencontrée dans l'ordre d'itération du catalogue
l'emporte, la seconde n'est même pas consultée. Même famille : un
résultat qui dépend d'un détail d'implémentation plutôt que du monde,
aucune priorité voulue dans un cas comme dans l'autre.

**Structurel vs facultatif, appliqué** (voir « Propriété structurelle vs
facultative ») : le CONTENEUR `poids_verbes` est STRUCTURELLE sur
`proprietes`, même convention qu'`attaches`/`forme` — sa clé absente dit
« ceci n'est pas un colon équipé pour peser un verbe », pas « ce colon
est neutre ». Sa valeur VIDE (`{}`) est légitime : le placide, qui ne
pèse jamais rien, la porte vide — exactement comme il porte `attaches :
[]`. CHAQUE poids à l'intérieur du dictionnaire reste FACULTATIF : son
absence retombe sur `0.0` (nul), un point réel du continuum, jamais une
alarme.

**Fuir (`s_eloigner`) : mouvement de répulsion, jamais vers une cible —
motif corrigé deux fois.** Fuir n'est pas un poids négatif sur éteindre
ou attiser — ce sont des verbes DISTINCTS, jamais des degrés d'un même
verbe (interdire d'attiser ne fait pas fuir). Premier motif, ÉCARTÉ :
fuir exigerait une fonction de mouvement symétrique de `bouger_vers`, qui
ÉLOIGNE — faux, ce n'était pas une fonction de mouvement qui manquait.
Second motif, ÉCARTÉ À SON TOUR (celui qui avait remplacé le premier) :
fuir irait TOUJOURS vers une chose réelle, un abri, exactement comme
éteindre ou attiser — faux aussi. Le colon fuyant devant dix hommes ne
vise rien : il part à l'OPPOSÉ de la PRESSION qu'exercent les choses
dont le verbe résolu est orienté fuite — une répulsion calculée
directement depuis les choses perçues et leur saillance déjà connue
(sommée, pondérée), jamais depuis un lieu ni une cible.

La peur n'est NI sur la chose NI dans la saillance (un nombre nu, jamais
signé) : elle vit dans le poids que CE colon met sur le verbe
`s_eloigner`, comme pour tout autre verbe (voir plus haut) — et dans le
choix, fait par le câblage plutôt que par le mouvement lui-même, de
quelles choses perçues rejoignent la répulsion.

Distinct de `se_proteger` — la même propriété peut proposer les deux
verbes à la fois, c'est `poids_verbes` qui tranche entre eux, comme pour
tout choix de verbe (voir plus haut). `se_proteger` VISE une chose
précise, la chose JUGÉE (voir « Jugement : troisième source de
saillance » et « Cible par verbe : vers quoi va le colon » plus bas) —
un abri réel vers lequel le colon se dirige, exactement comme pour
éteindre ou attiser. `s_eloigner` ne vise rien : deux verbes qui peuvent
naître de la même propriété, deux mouvements opposés dans leur nature
— pas deux degrés d'un même geste.

## Le colon n'est pas un type parent

`data/types.json` ne connaît pas de hiérarchie. Un montagnard, un raider,
un colon de base sont des types FRÈRES — chacun sa propre entrée, chacun
son propre paquet de propriétés (`rythme`, `canaux`,
`vitesse`, et ce qui les distingue). Aucun n'hérite de « colon » comme
d'une classe de base : il n'existe pas de type parent à hériter, parce
qu'hériter recréerait la hiérarchie de catégories que « Les archétypes
n'existent pas » écarte déjà pour les colons eux-mêmes.

Un montagnard n'est pas un « colon + neige » au sens d'une sous-classe :
c'est une entrée à part entière dans `types.json`, qui se trouve
partager la plupart de ses propriétés avec l'entrée « colon » par
coïncidence de contenu, jamais par filiation de code. `Objet.fabriquer`
ne sait pas qu'un type « hérite » d'un autre — il n'existe rien à
hériter, chaque type est un paquet de propriétés complet et autonome.

## Doctrine des compartiments : présence complète, activation variable

Tout agent porte l'ensemble complet des compartiments définis par son
paquet — les cinq réserves de `dynamique` (énergie, faim, soif, sommeil,
chaleur) en sont le cas typique. Un compartiment sans objet pour cet
agent est PRÉSENT ET ÉTEINT, jamais absent. Un golem n'a pas faim parce
que sa faim est éteinte, pas parce qu'il l'a supprimée.

ÉTEINT VEUT DIRE PLEIN ET SANS COÛT, jamais à zéro. Le dépôt lit
partout le manque comme `capacite - reserve` (voir `banc_faim_thermo`,
`banc_fatigue_circadien`, `banc_affordances_travail`,
`banc_affordances_choix`) : une réserve à zéro est donc un manque
MAXIMAL, l'exact opposé de l'inactivité. Un compartiment éteint porte sa
réserve pleine, `cout_base` et `surcout_action` à zéro — rien ne le fait
descendre, rien ne le lit comme un manque.

Conséquence sur l'écriture des types : quand un type redéclare un
conteneur hérité, il le redéclare EN ENTIER. Le moteur remplace le
conteneur en bloc, il n'ajoute jamais — réécrire une seule sous-clé
efface les autres en silence. Une redéclaration partielle est donc
toujours une erreur, jamais une intention.

Pourquoi la présence plutôt que la composition à la carte : ce qui
distingue deux agents est un NOMBRE, jamais la liste de ce qu'ils
portent (voir « Les archétypes n'existent pas »). Un agent dont la forme
même diffère n'est plus comparable à un autre — ni pour un lecteur, ni
pour un résumé (voir « L'LLM : lecteur ancré »). ÉCARTÉ, à ne pas
reproposer : sortir les réserves de `dynamique` vers un paquet `vivant`
pour que les agents sans corps n'en portent aucune — ça ferme le même
trou, mais au prix d'agents de formes différentes.

Opposable : `scripts/test_lint_donnees.gd` refuse toute surcharge
partielle d'un conteneur hérité. Son registre d'exceptions doit rester
VIDE — une entrée y contredit la présente doctrine.

## objet_physique comme paquet fondateur

Quatre propriétés physiques universelles — `masse`, `volume`, `densite`,
`temperature` — sont posées comme un paquet indépendant, `objet_physique`
(`data/types.json`), au même titre que `dynamique`/`percevant`/`agent`
(voir « L'entité comme agent complet » plus bas) : rien de spécial ne le
distingue des autres paquets composables par `herite`, aucune
automatisation, aucune hiérarchie devinée (même règle que « Le colon
n'est pas un type parent », ci-dessus).

Tout type qui a une MATIÈRE le compose (`arbre`, `bloc`, aujourd'hui) ;
les types abstraits (`feu`, `menace`) ne le composent pas — ils décrivent
un phénomène ou une catégorie de danger, pas une chose de matière. Rien
n'empêche un type futur de composer `objet_physique` sans composer
`entité`, ou l'inverse : les deux paquets sont indépendants. Un objet
physique n'est pas un agent — `entité` (perception, décision, réserves,
état interne) compose PAR-DESSUS quand la chose perçoit et décide, jamais
en dessous ; un colon compose les deux, un bloc de pierre n'en compose
qu'un.

DONNÉE PARTIELLEMENT DORMANTE, comme `data/materiaux.json` : `densite`/
`masse`/`volume` (calculés à la fabrication, voir ci-dessous) et
`temperature` (lu par `temperature.gd`) sont désormais lus par un
mécanisme réel — les autres propriétés du paquet restent dormantes, en
attendant les mécanismes physiques futurs (poids, écrasement, résistance
thermique...) qui les liront par le même patron que
`profil_saillance`/`transformation` (référence + catalogue, alarme sur
référence absente).

TENSION CONNUE — RÉSOLUE (chantier « la densité effective calculée à la
fabrication ») : `densite` existait à deux endroits — `objet_physique.
densite`, par instance/type, et `data/materiaux.json:densite`, par
MATÉRIAU. Ce n'est plus le cas : `data/materiaux.json` est désormais la
SEULE source éditable ; `objet_physique.densite`/`masse`/`volume` sur une
instance qui porte `composition` (voir « Le matériau comme paquet de
propriétés » plus bas) sont des SORTIES calculées une fois à la
fabrication, jamais posées à la main (détail du calcul : `CARTE.md` §2
`objet.gd`). Une instance qui ne porte pas `composition` garde le défaut
neutre du paquet, inchangé.

## Saillance de proximité

Une chose peut être saillante EN SOI, sans attache en jeu : un feu est
saillant pour tout colon, un arbre ne l'est pas. C'est un plancher
commun — aucun colon n'y est aveugle. Elle ne mesure jamais une
distance entre deux choses (ça, c'est le travail de l'attache) : elle
utilise la distance au colon, déjà connue depuis la perception. Plus
c'est près, plus c'est saillant.

Ce qui distingue les colons reste ce qui s'ajoute PAR-DESSUS quand une
attache est menacée : le placide (sans attache) va toujours au plus
proche ; le fanatique peut abandonner un feu à ses pieds pour un feu
lointain qui menace sa forêt, parce que là, la saillance d'attache est
plus haute.

Les deux sources — attache et proximité — alimentent la même liste. La
dominance ne sait pas d'où vient un nombre.

Un colon ne se compte jamais comme occupant de sa propre cible. La
saillance d'un chantier est pondérée par son AVANCEMENT
(`travail_restant` / `travail_initial`, `proximite.gd`) — un chantier
presque fini pèse moins qu'un chantier frais, jamais par un comptage
d'agents. Un colon perçoit l'ÉTAT de la chose (combien de travail il
reste), jamais le nombre d'agents autour d'elle : compter des agents a
été essayé (`colon_id`, retiré depuis) et oscillait — la saillance
dépendait de ce qu'un colon DÉCIDAIT d'un tick à l'autre, jamais stable.
L'avancement, lui, ne dépend d'aucune décision : il ne change que quand
un agent TRAVAILLE physiquement (`extinction.gd`), jamais parce qu'un
colon REGARDE.

## Jugement : troisième source de saillance

La valeur d'une chose n'est pas dans la chose, elle naît de sa rencontre
avec une autre. Une pierre ne vaut rien ; une pierre quand le feu est là
vaut quelque chose. Le monde n'émet aucun drapeau — c'est le colon qui
juge, même inversion fondatrice que pour la menace (voir « Menace par
propriétés »).

Table : `data/jugements.json`, couples `{ propriete_jugee :
propriete_declencheur }`, ex. `{ "abrite": "brule" }` — forme identique
à `menaces.json`. Ajouter un cas coûte une ligne de donnée, zéro ligne de
code.

Sortie : une saillance sur une chose réelle et perçue, absente du
résultat tant qu'aucune PRESSION n'existe. TRANCHÉ : la pression n'est
jamais une distance — c'est la somme des saillances déjà portées, en
couche 2, par les choses perçues qui déclenchent. Le feu vaut déjà ce
qu'il vaut pour CE colon (attache ou proximité) ; l'abri hérite de cette
valeur sans qu'aucune portée ni aucune distance supplémentaire n'entre
dans le calcul — ni entre l'abri et le feu, ni entre l'abri et le colon.
Une distance de plus referait ce que la proximité fait déjà (voir
« Saillance de proximité ») : la pression mesure une SITUATION, pas un
rapprochement. Elle se concatène à att + prox comme les deux autres ; la
dominance ne sait pas d'où vient un nombre.

LA FORME DU COLON DÉFORME LE JUGEMENT, exactement comme elle déforme
l'attache — c'est ce qui distingue ce mécanisme du plancher commun de la
proximité, aveugle au colon. Elle ne crée rien : elle règle à partir de
quelle pression le jugement s'allume et jusqu'où il monte. Raison : un
colon calme éteint un feu et fuit devant dix, sans que sa préférence ait
changé — c'est la saillance de l'abri qui a monté chez lui, et son seuil
de bascule lui est propre. Si le jugement était un plancher commun, seul
`poids_verbes` séparerait deux colons, et aucun colon ne changerait
jamais de comportement selon l'ampleur de la scène.

Le CHOIX entre plusieurs jugements concurrents ne change rien et
n'ajoute aucun mécanisme : un même déclencheur peut rendre plusieurs
choses saillantes à la fois — un ennemi rend saillants l'épée et l'arc,
`{ "tranchant": "hostile" }` et `{ "tire": "hostile" }`. C'est
`poids_verbes` qui tranche entre les deux, déjà écrit et déjà verrouillé
par test (voir « Plusieurs verbes par propriété, poids par colon »).

PORTÉE du mécanisme — il ne connaît ni le feu, ni l'abri : toute chose
qui n'a de valeur qu'en situation. L'abri (`{ "abrite": "brule" }`),
l'outil (`{ "tranchant": "abattable" }` — la hache ne compte que si un
arbre est à abattre), l'arme, le poste de défense. Le porteur et le
déclencheur peuvent tous deux être des colons — le colon est déjà un
objet perceptible.

CE QUE LE JUGEMENT NE COUVRE PAS : il ne rend jamais qu'une VALEUR sur
une chose perçue, jamais une direction. Mettre de la distance sans
viser aucune chose est un mécanisme séparé (voir « Fuir » ci-dessus et
« Cible par verbe : vers quoi va le colon » plus bas) : ancienne
hypothèse ÉCARTÉE, s'éloigner n'exige PAS de pondérer un ENDROIT (une
« zone ») — la répulsion se calcule directement depuis les choses
perçues et leur saillance déjà connue, sans lieu abstrait. Le verrou
« zone » (voir Questions ouvertes, « Ce qu'une zone représente, TRANCHÉ »
depuis — une zone est un résumé lu à la demande, jamais un objet) ne
bloquait déjà plus rien pour fuir ; ce qui reste ouvert (granularité de
la grille, câblage d'un futur lecteur de résumé) sert d'autres besoins —
sédimentation psychique, résumé de zone — jamais fuir.

## Cible par verbe : vers quoi va le colon

Tant qu'une seule chose répondait à une décision — le déclencheur, celui
qui menace le trait ou celui qui est saillant en soi — retrouver OÙ
aller ne posait pas de question : il n'y avait qu'une réponse possible.
Avec le jugement, ce n'est plus vrai. Une même situation perçue produit
DEUX choses distinctes, perçues séparément : la chose JUGÉE (l'abri) et
son DÉCLENCHEUR (le feu). La saillance qui gagne peut porter sur l'une
ou sur l'autre — encore faut-il savoir, une fois la décision prise,
laquelle des deux le colon doit rejoindre.

C'est le VERBE retenu qui tranche (voir « Plusieurs verbes par
propriété, poids par colon ») : il décide non seulement CE QUE le colon
fait, mais aussi VERS QUOI il va. Éteindre un feu vise le feu (le
déclencheur) ; se protéger vise l'abri (la chose jugée) — même situation
perçue, deux verbes, deux cibles opposées. Ce choix ne se lit jamais
dans le nom du verbe (catégorie interdite par l'ADN, voir « Règle dure :
moteur/données ») : une table de données dédiée, à la forme des autres
tables de couples (`menaces.json`, `jugements.json`), dit PAR VERBE si
la cible est la chose jugée ou le déclencheur. Le déclencheur reste le
comportement PAR DÉFAUT — celui qui a toujours existé avant que le
jugement n'apparaisse, jamais une alarme pour un verbe absent de la
table : la table ne fait que documenter les EXCEPTIONS. Ajouter un
verbe qui vise la chose jugée coûte une ligne de donnée, zéro ligne de
code.

Ce mécanisme est distinct de fuir (voir plus haut) : viser une chose et
fuir sans en viser aucune sont deux issues opposées, pas deux variantes
d'un même geste. La table d'orientation porte donc une troisième
valeur, à côté de « viser la chose jugée » et du défaut « viser le
déclencheur » : « fuite », qui ne dit pas où viser, mais qu'il n'y a
rien à viser du tout — seulement une direction à fuir.

## Verticalité

Toutes les positions sont des Vector3. Jamais Vector2. Z reste à zéro
aujourd'hui. Le Z ne se greffe pas après coup : le rétrofit coûte le
moteur entier (le mod Z-Levels de RimWorld n'a jamais été stabilisé en
cinq ans).

Pourquoi le Z, et pas la 3D. La 3D est un rendu, le Z est une grille.
Deux choses sans rapport : Stranded Alien Dawn est en 3D et n'a pas de
Z, il est vide. Odd Realm est en pixel art plat et a le Z. Le rendu ne
décide de rien.

Pourquoi le Z est nécessaire. À plat, un combat n'a que deux
variables : le nombre et le feu. C'est pourquoi RimWorld converge vers
le killbox — la seule optimisation possible est le couloir, et la
géométrie tue à la place du joueur. Le Z rend le terrain disputable :
il transforme la géométrie de "ce que je construis" en "ce que je
tiens". Un escalier est indéfendable par la construction seule. Il
faut des hommes dedans.

La guerre est verticale. Le siège médiéval est un problème de Z et
rien d'autre : échelle, beffroi, sape. La sape est la solution
décisive — au lieu de monter, on descend. La guerre urbaine
(Stalingrad, Grozny, Bakhmout) se joue en étages : un immeuble est
trois champs de bataille superposés. Le tunnel est la sape, inchangée.
Dans tous les cas, ce qui décide n'est pas la puissance de feu : c'est
qui tient le point de passage. Un goulot vertical est le seul terrain
où le nombre cesse de compter.

Échelle : deux ou trois niveaux, pas cinquante. À cinquante, la
lisibilité est morte (Dwarf Fortress). Un toit, un sol, un sous-sol
suffisent à produire le goulot.

## Affichage du Z

Aucun jeu n'affiche tous les étages. Tous coupent. La question n'est
pas "comment tout montrer" mais "où couper, et que reste-t-il de
visible en dessous".

Solution retenue, celle d'Odd Realm : une seule tranche affichée. Le
relief est rendu par un liseré sombre sur chaque bord de dénivelé. Ce
qui est en dessous n'est pas dessiné : c'est du noir. Le noir n'est
pas un manque d'information, il EST l'information — "ici ça descend,
tu ne vois pas".

Corollaire, et c'est le principe d'Orion appliqué au Z : le joueur ne
voit pas l'étage. Il voit des hommes qui réagissent à un étage qu'il
ne voit pas. La fumée filtre par le plancher, un colon lève la tête,
un autre court vers l'escalier. Le joueur déduit. Il peut se tromper.

Si le joueur peut lire l'étage, il ne regardera plus jamais l'homme.

## Internationalisation

Aucune chaîne de texte visible par le joueur n'apparaît en dur dans le
code. Le code ne manipule que des CLÉS. Les textes vivent en données.

Aucune phrase construite par concaténation. Une phrase = une clé, avec
des trous nommés. L'ordre des mots change selon la langue. C'est
l'erreur de Dwarf Fortress : le texte y est composé à la volée à
partir de fragments anglais, donc intraduisible.

Ajouter une langue = un fichier, zéro ligne de code. Vaut dès la
première ligne d'interface. Ne se rétrofitte pas.

**PREMIER FICHIER : `data/textes.json`** (chantier « perception du temps
+ anticipation », `CARTE.md` `banc_temps_anticipation`). La règle ci-dessus était
posée depuis le début et n'avait jamais mordu : aucun banc n'affichait
de texte joueur, et l'audit préalable l'avait constaté (« aucun fichier
de textes n'existe dans `data/` — cette ligne serait la PREMIÈRE du
dépôt à mordre sur la règle i18n »). Elle mord ici, et la règle tient
sans rien rétrofitter.

Forme retenue : racine = CODE DE LANGUE, puis clé → texte. Ajouter une
langue = une clé à la racine, zéro ligne de code — le câblage lit
`textes[langue][cle]`, et `langue` est elle-même une donnée. Écart de
forme signalé, jamais masqué : la règle dit « un fichier », la forme
retenue met les langues dans un seul ; les deux tiennent la même
garantie, et passer de l'une à l'autre ne changerait que le chemin
chargé.

DEUX RÉGIMES À NE PAS CONFONDRE, et c'est ce qui décide si un texte
doit passer par ici. Les LABELS à l'écran sont vus par le joueur : tout
ce qui les compose vient du catalogue. Les traces console (`print`
des bancs) ne le sont pas — ce sont des sorties de mise au point, la
règle ne les vise pas (« les chaînes visibles par le joueur »). Un banc
qui afficherait un texte joueur sans passer par le catalogue serait en
faute, même jetable.

Une clé absente ressort TELLE QUELLE à l'écran, jamais remplacée par un
texte de repli écrit dans le code : le trou doit être visible pour être
corrigé, et un repli en dur serait exactement la faute que la règle
interdit.

## Rôle du joueur

Le colon est autonome. Le joueur n'agit pas sur ce qu'il fait,
seulement sur ce qu'il perçoit.

- Il pose des raisons, pas des ordres. Vouloir quelqu'un au nord ne
 consiste pas à y envoyer un colon : il faut y mettre une chose à
 laquelle quelqu'un tient.
- Il choisit qui entre. On ne recrute pas des compétences, on recrute
 des tempéraments. Un fanatique est irremplaçable et ingouvernable.
- Il compose un alliage. Des fanatiques seuls sont mangés un par un.
 Des bâtisseurs seuls sont anéantis en une bataille. Des placides
 seuls tiennent partout, mal, et s'effondrent d'un coup.
- Il choisit où regarder. À cent colons, trois montent en saturation ;
 un seul peut être sauvé. C'est un arbitrage de l'attention.
- Commander est un coût (voir « Ordre et tension » ci-dessous). Sans
 ordre, la saillance dominante d'un colon est son attache — le temps
 libre est le temps où il se découvre.

En une phrase : le joueur de RimWorld dit à ses gens quoi faire. Le
joueur d'Orion fabrique le monde dans lequel ses gens décident.

## Ordre et tension

Un ordre ne supprime jamais une saillance. Il en AJOUTE une,
concurrente, du côté du colon. La couche 3 arbitre comme d'habitude : si
l'ordre pèse plus que ce à quoi le colon tient, il obéit ; sinon il
désobéit. Aucun cas particulier.

Conséquence : un colon obéissant continue de ressentir ce qu'il
ressentait. Un fanatique qui abandonne sa forêt sur ordre reste un
fanatique.

Le coût d'un ordre est l'ÉCART entre ce qui pèse chez le colon et ce
qu'il fait. Il ne se déclare pas, il se calcule. Commander des colons à
fortes attaches coûte cher, commander un placide ne coûte rien — sans
qu'aucune règle ne l'ait écrit.

Non tranché : ce que l'écart accumulé produit (désobéissance, départ,
palier de dégradation), et ce qui donne du poids à un ordre. La
hiérarchie n'existe pas (voir « État des couches », aucun colon n'a de
subordonnés).

## L'attachement du joueur

Ce n'est pas une mécanique, c'est ce qui arrive AU joueur. Il perd des
gens auxquels il tient.

Aucun chiffre, aucun passé écrit ne l'attache. Ce qui l'attache, c'est
le fait d'avoir VU. Le colon qui regardait vers l'ouest pendant qu'on
le forçait à travailler : le joueur l'a vu, a choisi d'ignorer, il a
lâché.

Ce lien est plus fort qu'une fiche de personnage : il est fait de la
culpabilité du joueur. RimWorld ne peut pas le produire — là-bas, rien
n'est ignoré, tout est optimisé.

## La défaite est un état, pas une fin

Aucun colony sim ne traite la défaite autrement que comme une fin
binaire :

- RimWorld : l'esclavage n'existe que dans un sens (le joueur capture,
 jamais l'inverse). Un raid a deux issues, gagner ou mourir.
- Humankind, Civilization, Europa Universalis : la vassalisation
 existe, mais à l'échelle des empires, jamais à celle des hommes.
- La reddition conditionnelle n'existe dans aucun colony sim —
 seulement à l'état de suggestion de joueur sur un forum.

Un raid a plus de deux issues, selon ce que veut l'assaillant :

- ils veulent ta terre → vassalité (tribut, protection, retour en
 force si le tribut cesse).
- ils veulent tes bras → capture (le groupe devient esclave).
- ils veulent ta mort → pas de négociation.

Ce ne sont pas trois boutons pour le joueur : ce sont les conséquences
de ce qui tient l'assaillant. Le raider a des attaches, comme le
colon. Celui dont on a tué le frère ne négocie pas. Le joueur ne lit
pas les intentions de l'ennemi, il les découvre — souvent trop tard,
avec le même droit à l'erreur que pour ses propres colons.

Conséquence sur le killbox : un assaillant qui peut capturer plutôt
que tuer n'a aucune raison d'entrer dans un couloir. Il assiège,
coupe, attend. La géométrie cesse d'être une solution.

Corollaire d'architecture : le moteur des saillances s'applique à
l'ennemi ou il ne sert à rien. Il n'existe pas de code des raiders
séparé — un raider est un colon avec d'autres attaches.

## Les factions et la guerre non déclarée

La faction fanatique n'est pas une menace, c'est un terrain. Elle ne
veut rien du joueur — on peut passer toute la partie sans la voir,
jusqu'à couper un arbre. Une forêt est une frontière invisible ; le
seul moyen de savoir où elle passe est de la franchir. On ne négocie
pas avec un fanatique : il ne veut rien, il n'y a rien à offrir. La
seule paix est de ne pas y aller.

Le pillard, lui, se calcule : il veut quelque chose, ce qui le rend
plus meurtrier — rien ne le retient. Fanatique et pillard ne sont pas
deux points sur une échelle d'agressivité : l'un se déclenche, l'autre
se calcule.

La guerre naît sans qu'elle soit déclarée. Un bâtisseur coupe du bois
à la lisière, ignorant qu'il y a une frontière — il n'y en a pas, il
n'y a que des attaches. Un fanatique vient, tue. Le bâtisseur ne
comprend rien : un homme est mort sans raison visible pour lui, il ne
perçoit pas l'attache de l'autre. Il envoie des hommes ; plus d'arbres
tombent, plus de fanatiques viennent. Puis il rase la lisière pour
être en sécurité — la seule chose qui unit les fanatiques. Chaque
forêt voisine voit la première tomber ; le lien à celle-ci ajoute une
attache au trait végétal — « mon arbre » ne s'efface pas, « les arbres »
s'ajoute. Ils convergent, pas par alliance : par contagion de
perception. Aucune paix n'est possible, et aucune n'a été refusée.

Rien dans ce récit n'exige un système de factions, de réputation, de
casus belli ou de diplomatie. Tout sort des quatre couches — c'est la
preuve que le moteur est bon.

Corollaire, la solitude structurelle des fanatiques : plusieurs
groupes de fanatiques face à un envahisseur sont écrasés un par un,
chacun défendant sa forêt sans relier celle du voisin. Aucun ne
trahit, aucun n'est lâche — c'est précisément ce qui les tue.
L'alliance n'est pas un traité, c'est ce qui arrive quand assez de
gens ont vu assez de choses brûler ; elle se paie en morts et arrive
toujours trop tard. Le joueur ne peut pas leur ordonner de s'unir. Il
peut les emmener voir.

## La hiérarchie : le chef est un colon

Le chef n'est pas un filtre vide au-dessus de la liste — il est
lui-même un colon :

- il peut se tromper, dans le sens de son trait ; son erreur est
 lisible après coup ;
- il a ses propres attaches — un chef attaché à la forêt n'enverra
 jamais personne au bâtiment ;
- il peut être désobéi, son ordre est une saillance, pas un flag ;
- il ne peut pas être vérifié : le champ est sa fiche d'évaluation.

L'information se perd en montant. Le joueur ne sait pas ce qui se
passe au nord, il sait ce que son chef du nord perçoit du nord. Le
brouillard n'est pas sur la carte, il est dans les hommes du joueur,
et il est irréductible.

Exemple, la guerre lointaine : le joueur part avec vingt hommes et
emporte leurs attaches. Le fanatique ne vient pas, sa forêt est ici.
Le bâtisseur ne quitte pas son mur. Les seuls emmenables sont les
placides — les moins fiables au combat. Et ceux qui restent ne sont
pas une garnison : ce sont ceux que rien ne pouvait faire partir. La
notification que reçoit le joueur n'est pas neutre, c'est ce que son
chef a vu : le chef placide dira que ça va, le chef stressé dira que
tout brûle. Le joueur n'arbitre pas entre deux fronts, il arbitre
entre deux témoignages.

## Le monde porte tes actes

Pas de Nemesis, pas d'agent, pas d'apprentissage automatique — une
seule mécanique : les attaches peuvent se former par la perception en
cours de partie, pas seulement être données au départ.

Un colon qui a passé cent heures dans la colonie l'a vue : ce que le
joueur protégeait, ce qu'il laissait tomber. Ses attaches se sont
formées sur ce qu'il a vu. Envoyé fonder un village, il ne copie pas
le style du joueur — il tient à ce qu'il a appris à tenir chez lui. Le
monde ne porte pas la stratégie du joueur, il porte ses actes.

(Nemesis, 2014, est le seul précédent connu — breveté par Warner en
2021, jamais réutilisé, jamais licencié : une table de souvenirs, du
contenu écrit à la main. Ici, pas de table : le même résultat sort de
l'architecture, et l'architecture monte en charge.)

Pas fait : voir État des couches.

## Interface : zéro nombre affiché

Le joueur ne voit aucune barre de saillance, aucun pourcentage de
menace, aucun score. Il lit des SIGNES — posture, vitesse, direction,
hésitation d'un colon — et il DÉDUIT ce qui se passe. Personne
n'affiche sa peur en pourcentage.

Le joueur ne règle pas un tableau de priorités, il fixe une doctrine
et regarde ce qu'elle produit. Si un chiffre semble nécessaire pour
comprendre une scène, c'est la lisibilité du geste qui est à corriger
— pas un HUD à ajouter.

Le risque, dit net : rien n'est expliqué, aucune raison n'est
affichée. Un joueur qui perd un colon ne saura pas pourquoi — il devra
le déduire, et aucun wiki ne réparera ça. Ce n'est pas un défaut
d'interface, c'est le jeu. Le danger : un joueur qui ne comprend pas
pourquoi il perd ne dira pas « c'est profond », il dira « c'est
aléatoire ». La seule protection contre ça est la RÈGLE ANTI-BRUIT
(voir Le modèle : attaches et forme) : l'erreur du colon doit rester
lisible après coup. Ce n'est pas un principe esthétique, c'est le
contrat de survie du jeu.

## État des couches

### Tout est objet

Un seul moule : l'objet. Aucune catégorie de type dans le code — pas de
« colon », « mur », « animal » comme boîtes.

Un objet est un sac de propriétés cumulables : position, opaque, solide,
mouvant, inflammable, attaches, perception... Le code ne lit jamais un nom
de chose (`type == "mur"`), seulement des propriétés (`si objet.opaque`).

« colon » = objet qui a `attaches`. « mur » = objet qui a `opaque` +
`solide`. Retirer une propriété change la nature de l'objet sans toucher
au code.

Pourquoi : à l'échelle d'Orion (centaines de paramètres combinables), les
catégories explosent en combinatoire ; les propriétés ont un coût fixe.
L'émergence combinatoire est impossible sur une architecture qui explose
en combinatoire.

État : le cœur et le chemin de décision du banc sont entièrement par
propriétés — voir FAIT, TESTÉ ci-dessous.

PROPRIÉTÉS ÉMERGENTES (chantier « propriétés émergentes — capacités
conditionnelles à la fabrication ») : conséquence directe du sac de
propriétés — un objet composé peut acquérir une propriété qu'AUCUN de ses
composants ne porte individuellement, si la COMBINAISON remplit des
conditions déclarées en donnée (`data/emergences.json`). Dernier pas de
`objet.gd:fabriquer`, générique (aucun nom de contenu, catalogue reçu en
paramètre), symétrique à `seuil_etat.gd` (compare une propriété à un
seuil) mais évalué UNE FOIS à la fabrication plutôt qu'à chaque tick — la
combinaison de matériaux est immuable après fabrication, comme la
densité (voir DENSITÉ EFFECTIVE, `CARTE.md` §2). Contrat exact
(opérateurs, forme du catalogue) : `CARTE.md` §2 `scripts/objet.gd`,
`banc_emergences` `scripts/banc_emergences.gd`.

### Perception : profil et cadence

La perception se lit depuis un profil porté par la créature — PAR CANAL
(`canaux_config.<nom>.portee`, depuis PHASE 3.5), jamais un rayon unique
ni un rayon en dur dans le code (état exact — `angle`/`sensibilite`/
`seuil` par canal, `cadence` absente : voir « PAS FAIT » plus bas).

L'occlusion vit dans `perception.gd`, pas dans le monde (`choses_dans_rayon`,
qui reste un test de DISTANCE seul). DOCTRINE REMPLACÉE (chantier
« occlusion -- un obstacle entre A et B bloque la perception », décision
Yael) : la phrase précédente plaçait l'occlusion dans `monde.gd` — écartée
avant d'écrire, parce que la propriété qui atténue dépend du CANAL
(`opacite` pour une future vue, `absorption_sonore` pour l'ouïe déjà câblée),
une notion étrangère à `monde.gd`, contenant spatial générique qui ne connaît
aucun canal. Une chose sur le segment entre percepteur et source atténue la
perception proportionnellement à sa valeur de `propriete_obstacle` (nommée
PAR CANAL dans `data/canaux.json`, jamais en dur) ; le moteur ne connaît
toujours pas « mur », seulement la propriété que le canal désigne (voir Tout
est objet). MÊME PATRON pour la SOURCE (chantier « propriete_emission
configurable par canal », session ultérieure) : le nom de la propriété
d'émission lue sur la source est lui aussi nommé PAR CANAL
(`data/canaux.json[nom].propriete_emission`, défaut `"son_emis"` si absent),
jamais en dur — le moteur ne sait toujours pas ce qu'est un son, seulement
quelle propriété le canal désigne comme émission. Détail et coût : `scripts/perception.gd:_percevoir_propagation_obstacles`/
`_facteur_obstacles`, `CARTE.md` §2/§3. GÉOMÉTRIE EXTRAITE depuis (chantier
« ombre pluviométrique ») : le calcul lui-même vit dans
`scripts/occlusion.gd`, partagé avec `champ_occulte.gd` — `_facteur_obstacles`
ne fait plus que déléguer, aucune règle changée. Voir « Champ ambiant
occulté ».

Un second canal de perception (son, odeur) ne se justifie que pour
contourner un obstacle à la vue. Pas avant un besoin de jeu réel qui
l'exige.

Vision différée : deux choses distinctes, à ne pas confondre.
- Latence de perception — la cadence du profil ; en dessous d'une
 fréquence où l'écart ne se ressent pas, c'est une optimisation, pas un
 trait.
- Vision-du-passé — une créature qui agit sur une scène périmée est un
 TRAIT de comportement, à construire plus tard, pas une conséquence
 mécanique de la cadence.

FAIT, TESTÉ : les quatre couches (perception ; saillance — attaches,
proximité, jugement, chacune lisant aussi le biais de déformation
individuelle du colon —; dominance ; agir, avec inertie) sont câblées
et testées de bout en bout. État exact de chaque script (rôle, entrées,
sorties, fichier de test) : voir `CARTE.md` §2, jamais recopié ici.

PAS FAIT :

- Couche 2, autres sources de saillance que les attaches, la proximité
 et le jugement (ressource, tâche, dette, sacré...).
- Saturation : décrite dans le principe, non implémentée.
- Formation d'attaches par la perception en cours de partie (voir Le
 monde porte tes actes) : FERMÉ (PHASE 5, chantier « L'entité comme
 agent complet ») — un lien personnel né de la défense répétée d'une
 même chose se généralise en attache par trait une fois un seuil
 composite (nombre ET force) atteint, surchargeable par colon ; câblé
 et observable dans `banc_lien_personnel` (voir `CARTE.md` §2/`banc_lien_personnel`,
 `docs/prototypes.md`). Reste hors de ce mécanisme : toute source
 d'attache autre que la défense (voir Questions ouvertes, seuil non
 affiné au-delà des valeurs de démarrage).
- Chef de colonie (voir La hiérarchie) : n'existe pas, aucun colon n'a
 de subordonnés.
- Combat, capture, vassalité (voir La défaite est un état, pas une
 fin) : rien n'est construit.
- Interface de JEU : rien n'est construit — les barres/couleurs/marqueurs
 textuels des bancs (réserves, `effraye`, `abrite`/`refuge`) sont des
 outils d'observation jetables pour Claude/Yael, pas le système de
 signes visé pour le joueur ; la question des signes reste un principe,
 pas un système.
- Modèle objet à propriétés (voir Tout est objet) : engagé pour le cœur
 — fabrication (`objet.gd`), perception, proximité, attaches par
 propriétés (voir FAIT, TESTÉ ci-dessus), tous verts au lanceur. Ce qui
 reste comme dette de câblage (pas du cœur) : voir `CARTE.md` §6 et
 `docs/prototypes.md` pour l'état exact — ne pas le recopier ici, un
 état recopié ici a déjà périmé une fois sans que personne ne le
 remarque.
- Profil de perception `{ portee, cadence }` (voir Perception : profil et
 cadence) : `portee` existe désormais PAR CANAL (`canaux_config.<nom>.portee`,
 PHASE 3.5, en donnée — plus un rayon unique en dur), avec `angle`/
 `sensibilite`/`seuil` en plus par canal ; `cadence` reste absente,
 perception recalculée à chaque tick pour tous les canaux.
- Occlusion : `choses_dans_rayon` (`monde.gd`) ne teste que la
 distance, aucune ligne de vue, aucune notion d'opaque.
- Second canal de perception (son, odeur) : EXISTE désormais comme
 mécanisme (PHASE 3.5, `perception.gd`/`data/canaux.json` — ouïe,
 odorat, toucher, goût, nociception, en plus de la vue). L'ODORAT
 DIRECTIONNEL est désormais exercé RÉELLEMENT (chantier « vent »,
 `scripts/vent.gd`/`scripts/banc_vent.gd`, voir `CARTE.md` §2/§3) : un
 nez perçoit des sources d'odeur dont la portée effective tourne avec
 le vent. Les quatre autres canaux (ouïe, toucher, goût, nociception)
 restent géométriquement inactifs dans les bancs actuels — leur portée
 y est trop courte pour capter quoi que ce soit ; un banc qui les
 exerce reste à construire.

## Le matériau comme paquet de propriétés

Un matériau n'existe pas comme concept dans le moteur — c'est une
référence de catalogue, exactement comme `profil_saillance`,
`transformation` ou `seuils_ref` (voir `CARTE.md` §4,
`data/materiaux.json`) : LE MATÉRIAU SE LIT COMME `profil_saillance` —
une String sur l'instance (ou, depuis ce chantier, sur un élément de
composition, voir plus bas), un catalogue reçu EN PARAMÈTRE du
mécanisme qui le résout, jamais fusionné en dur à l'écriture des
données. Ajouter un matériau = une entrée de plus dans
`data/materiaux.json`, zéro ligne de code — même pattern, même
contrat que les autres références déjà éprouvées : alarme sur
référence absente, jamais un défaut silencieux.

Une chose physique ne porte plus `materiau` (String unique) mais
`composition` (Array de `{ materiau, volume }`, TOUJOURS une liste —
le mono-matériau est le cas à un seul élément, aucune branche mono/
multi, `data/types.json:arbre`/`bloc`). `materiau`, à l'intérieur de
chaque élément, reste la référence — le renommage du champ conteneur
ne change rien au patron de résolution.

LA DENSITÉ EFFECTIVE EST CALCULÉE À LA FABRICATION (chantier « la
densité effective calculée à la fabrication ») — SEULE exception au
statut dormant ci-dessous, et seule propriété de matériau fusionnée
plutôt que lue à la demande : `objet.gd:fabriquer`, dès qu'un type
porte `composition`, calcule UNE FOIS `densite`/`volume`/`masse` par
moyenne pondérée des volumes (`Σ(rho_i·volume_i)/Σ(volume_i)`) et les
écrit sur `proprietes`, remplaçant les défauts hérités du paquet
`objet_physique` — voir « objet_physique comme paquet fondateur »
ci-dessus, TENSION CONNUE désormais résolue. Justifié par l'immuabilité
de la composition (un objet ne change jamais de composition de sa vie :
se casser le détruit et en crée d'autres, ça ne le modifie pas) : une
valeur immuable se calcule une fois, jamais à la demande. Un matériau
absent du catalogue, ou une fiche sans `densite`, REFUSE toute la
fabrication (`objet.gd:fabriquer` rend `{}`) — pas le patron
« ignorer + continuer » du reste du fichier, la composition est ce
dont l'objet EST FAIT, une donnée cassée à la racine ne se contourne
pas. Conversion d'unité (g/cm³ du catalogue → kg/m³ SI) : une seule
constante nommée dans `objet.gd`, jamais une mutation du catalogue.

État des 45 AUTRES propriétés (dureté, conductivité thermique,
inflammabilité, résistances mécaniques, sensibilités chimiques et
magiques...) : toujours donnée DORMANTE, à ne PAS généraliser au
patron de fusion ci-dessus sans décision séparée — elles resteront
lues À LA DEMANDE par chaque futur mécanisme d'élément
(`docs/orion-matrice-elements.md`), jamais fusionnées à la
fabrication. `data/materiaux.json` existe, posé sur
`data/types.json:arbre`/`bloc` — compte d'entrées à jour : `CARTE.md`
§4, jamais recopié ici. Prépare le
terrain pour les mécanismes physiques futurs (feu enrichi, thermique,
humidité, mécanique) et pour l'ancrage LLM (voir « L'LLM : lecteur
ancré, jamais auteur ») — le vocabulaire existe avant le lecteur,
jamais l'inverse.

`corrodable` ne concerne que les métaux. Un matériau non métallique
exposé à l'humidité ne se corrode pas : le bois pourrit
(`sensibilite_pourriture`), la pierre se dissout (`solubilite`). Le
produit de la corrosion dépend du métal — le fer donne de la rouille,
le cuivre donnerait du vert-de-gris. Ne jamais câbler un produit de
corrosion générique pour tous les matériaux.

### Les propriétés matériau comme nœuds de connexion transversaux

Une propriété de `data/materiaux.json` n'appartient à aucun mécanisme en
propre — elle est un NŒUD où plusieurs colonnes de
`docs/orion-matrice-elements.md` se croisent. `densite` apparaît en
Sonore, Mécanique, Magnétique et Nucléaire ; `inflammabilite` réapparaît
en Chimique après le Feu ; `biodegradabilite` apparaît à la fois en
Radiante et en Chimique (voir plus bas). Ce n'est pas une redondance à
corriger : c'est le PATRON recherché. Les mécanismes du cœur restent
génériques et ne savent pas quel domaine ils servent — `charge.gd` ne
sait pas s'il pose de l'humidité, une corrosion ou une électrocution
(mêmes lignes, trois chantiers différents : `banc_humidite.gd`/
`banc_corrosion.gd`/`banc_conduction.gd`, `CARTE.md` §2) — ce sont les
propriétés matériau, en donnée, qui les branchent chacun sur un cas
différent, jamais une ligne de code par cas. Une propriété qui ne sert
qu'à un seul mécanisme reste légitime (la plupart le sont encore, voir
« État des 45 AUTRES propriétés » ci-dessus) ; une propriété qui
traverse plusieurs colonnes de la matrice est la preuve que le patron a
déjà pris.

`biodegradabilite` illustre ce patron : une donnée UNIQUE, DEUX
déclencheurs distincts. Colonne Radiante (`docs/orion-matrice-elements.md`
§ « Radiante ») : DÉSORMAIS CÂBLÉE — le soleil PHOTODÉGRADE, les UV
cassent des liaisons chimiques, la lumière locale accélère la dégradation
(`banc_photodegradation.gd`, seul survivant — DOCTRINE TRANCHÉE, session
ultérieure : un premier banc concurrent, `banc_uv_degradation.gd`,
câblait l'UV comme un ralentisseur de la pourriture, physique fausse
écartée, fichiers retirés du dépôt — détail : `CARTE.md`
`banc_photodegradation`). Colonne Chimique
(§ « Chimique ») : les microbes du sol BIODÉGRADENT — humidité + contact
avec le sol, même famille que `sensibilite_pourriture` (`charge.gd`, patron
déjà câblé par `banc_humidite.gd`/`banc_pourriture.gd`) — mais
`biodegradabilite` elle-même reste DORMANTE sur cette colonne :
`sensibilite_pourriture` est une propriété SÉPARÉE, jamais la même donnée.
Les deux agissent en SYNERGIE, jamais en parallèle indépendant, RESTE À
CONCEVOIR : le soleil pré-casse le matériau, ce qui accélère ensuite la
biodégradation microbienne — la forme exacte de cette synergie
(probablement multiplicative, voir « Lecture des calques : composition
multiplicative, pas additive ») reste à trancher, pas ici.

Même patron appliqué à la fondation génétique (chantier « fondation
génétique dormante ») — état exact de qui lit quoi et de ce qui reste
dormant : `CARTE.md` §2/§4, jamais recopié ici.

`couleur_physique` (String) est le nommage humain et le rendu visuel.
`absorption_sombre` (scalaire 0.0-1.0) est la grandeur lue par les
mécanismes pour l'absorption de lumière et la chaleur radiante. Les
deux coexistent.

### Vitesse de propagation du son par matériau — fondation dormante

La physique donne `vitesse = racine(rigidite / densite)`. Les deux
propriétés existent déjà dans `data/materiaux.json` — `rigidite` (bois
`11.0`/pierre `50.0`/fer `200.0`, présente depuis la création du
catalogue, jamais fusionnée) et `densite` (calculée à la fabrication,
voir plus haut). Le câblage attend un mécanisme de DÉLAI TEMPOREL dans
la perception : un son émis à un instant ne serait reçu que N ticks
plus tard, N dépendant du matériau traversé sur le trajet — chose que
`perception.gd` (canal `ouie`) ne modélise pas aujourd'hui, qui ne
connaît que l'atténuation par la distance et par obstacle
(`son_emis`/`absorption_sonore`, instantanées). Ce mécanisme n'existe
pas dans le moteur. FONDATION DORMANTE, même statut qu'`opacite`/
`absorption_sombre` avant leur premier câblage.

## L'entité comme agent complet

### Le concept d'entité

RÉSOLUTION D'UNE CONTRADICTION (session ultérieure) : ce passage et « Le
colon n'est pas un type parent » (plus haut) se contredisaient — l'un
parlait de composition de paquets, l'autre de type et d'héritage pour la
même relation `entité` → `colon`. Celui-ci a été réécrit ; l'autre
prévaut et n'a pas changé.

`entité` désigne un CONCEPT — tout ce qui bouge, décide, a des
alliances peut en relever — tangible ou non, biologique, spirituel,
artificiel, démoniaque, robotique. `colon` n'est pas un sous-type
d'`entité`, c'est un type qui COMPOSE des paquets avec ses propres
propriétés (voir `objet.gd:fabriquer`, la cle `herite`, une liste de
paquets à fusionner, jamais une chaîne de filiation), exactement comme
`docs/design.md`, « Le colon n'est pas un type parent » le pose pour
tout `data/types.json`.

ÉCLATEMENT (session ultérieure, « éclatement du corps interne ») :
`entité` ne vit plus comme UN SEUL paquet de données. L'ancien paquet
unique regroupait huit clés par accident de construction — un type qui
le composait les héritait toutes d'un coup, qu'il en ait besoin ou
non, rendant impossible de composer « ce qui perçoit sans décider »
(un animal, un capteur) ou « ce qui décide sans corps physiologique
universel » (un golem, une entité spirituelle). Trois paquets
indépendants le remplacent dans `data/types.json`, composables seuls
ou en combinaison via `herite` — un Array à PLAT : la résolution de
`herite` N'EST PAS récursive (voir `objet.gd:fabriquer`), un type qui
veut plusieurs paquets les nomme TOUS lui-même, jamais par
transitivité au travers d'un paquet intermédiaire :

- `dynamique` — ce qui a un ÉTAT INTERNE QUI ÉVOLUE, sans impliquer
 perception ni décision : `engagement`, `reserves`, `liens_personnels`,
 `deformation_sources`/`deformation_etat`, `etats`.
- `percevant` — ce qui PERÇOIT : `canaux`/`canaux_config`, `orientation`.
- `agent` — ce qui DÉCIDE : `attaches`.

`colon` compose les quatre paquets (`objet_physique`, `dynamique`,
`percevant`, `agent` — voir `data/types.json:colon`), plus ses propres
surcharges (`rythme`, `vitesse`, `canaux_config` élargi, `etats.peur`,
`deformation_sources`/`deformation_etat.habituation.brule` — restés SUR
`colon`, jamais remontés dans un paquet partagé : la peur est humaine,
pas universelle à tout
ce qui compose `dynamique`). Un robot qui compose `dynamique` +
`percevant` + `agent` les reçoit tous ; un animal qui perçoit et a un
corps physiologique sans décider compose `dynamique` + `percevant`
sans `agent` ; un golem ou une entité spirituelle qui décide sans
réserves physiologiques universelles compose `agent` (+ `percevant` au
besoin) en écrasant ou ignorant `dynamique.reserves`. Voir « Les cinq
composants du corps interne » ci-dessous pour le détail de qui va où
et pourquoi.

### Le chantier

Quatre tâches actuellement dispersées dans la carte étaient les faces d'un même problème :

- Formation d'attaches en jeu (Structurel) — les attaches naissent de la perception en cours de partie, pas seulement au départ. FERMÉ (PHASE 5) : un colon qui a personnellement défendu assez de choses distinctes portant le même trait, avec assez de force sur chacune (seuil composite nombre ET force, surchargeable par colon), généralise en une attache par trait — voir `attache_par_trait.gd`, `CARTE.md` §2.
- Lien personnel (Structurel) — 2ᵉ source de saillance, cet objet-là, né de l'usage, vit côté agent. FERMÉ (PHASE 5) : `lien_personnel.gd` (l'événement, posé par `agir.gd:choisir`) et `lien_personnel_saillance.gd` (la lecture, additive à la saillance nue) — voir `CARTE.md` §2, `docs/prototypes.md` (`banc_lien_personnel`).
- La déformation individuelle (vecteur) (Cœur restant) — biais qui agit sur la saillance, trois sources (habituation, trauma, compétence), stacking multiplicatif, deux registres de durabilité, signal composite.
- en_detresse / appeler à l'aide (Cœur restant) — état interne posé par événement.

Ces quatre tâches sont un seul chantier : doter l'entité d'un état interne persistant entre ticks. Aujourd'hui, l'entité recalcule tout à chaque tick sans rien porter entre. Elle perçoit, calcule des saillances, agit, oublie. Le bug d'oscillation d'un colon entre chantiers identiques est le symptôme observable de ce manque.

### Les cinq composants du corps interne

Éclatés en trois paquets indépendants (`data/types.json:dynamique`/
`percevant`/`agent`, « éclatement du corps interne ») — le
regroupement ci-dessous dit QUOI va où et POURQUOI, pas seulement CE
QUE fait chaque composant.

**`dynamique`** — ce qui a un état interne qui évolue tout seul, par
mécanisme, sans perception ni décision propre :

- **engagement** — état de couplage physique entre l'entité et sa cible. Tant que l'entité est physiquement à `portee_travail` de sa cible, la cible pèse plus lourd dans son évaluation. Se pose par présence, se retire par absence, jamais par décision. N'EST PAS une "intention" au sens BDI (pas un plan choisi, pas défendu contre les distractions). N'EST PAS une préférence de personnalité (ça, c'est `gain_inertie`, qui reste).
- **reserves** — corps physiologique (energie, faim, soif, sommeil, chaleur). Descendent en continu, se rechargent au contact d'une source. Bornées à `0.0`, jamais négatives (voir « Dépense : réserve bornée à zéro »). Seul composant PLEIN par défaut dans son paquet — ces cinq canaux sont universels au vivant standard ; un type non vivant qui compose `dynamique` sans en vouloir les écrase en donnée.
- **liens_personnels** — 2ᵉ source de saillance, force accumulée vers une chose précise, née de l'usage (`lien_personnel.gd`), décroît seule dans le temps — même forme mécanique que `deformation_etat` (registre qui évolue tout seul, sans intervention d'une décision ; `deformation_sources` l'accompagne, forme A, voir CARTE.md §2 `deformation.gd`), d'où son rattachement ici : ce composant NOURRIT la décision (voir « Le chantier » plus haut, « vit côté agent »), mais sa NATURE MÉCANIQUE — ce qui détermine le paquet — reste un état qui évolue, pas un acte de décider.
- **etats** — canaux d'état interne traversables, nommés `etats`. Montent par charge, basculent à seuil (`effraye`, `en_detresse`, `epuise`).

**`percevant`** — ce qui perçoit, sans état qui évolue ni décision propre :

- **canaux** — Array de String, six noms de canal par défaut (vue, ouïe, odorat, toucher, goût, nociception), chacun une référence à `data/canaux.json` (forme A, vérifiée par `scripts/test_lint_donnees.gd`) ; les réglages (`portee`/`angle`/`sensibilite`/`seuil`) vivent séparément sur `canaux_config` (Dictionary nom → réglages, jamais vérifié par le linter — ce sont des données, pas des références). Une entité peut avoir un canal désactivé (aveugle = liste `canaux` sans "vue"). La douleur ≠ nociception : la nociception est un canal sensoriel, la douleur est un mécanisme ultérieur (probablement de type `etats`, donc côté `dynamique`) qui prend en entrée la nociception soutenue.
- **orientation** — direction que l'entité regarde (Vector3 sérialisé, défaut `z:1`). Fait cinématique statique : jamais avancé par aucun mécanisme du cœur, seulement lu par `perception.gd` pour orienter le cône de vue — n'évolue pas de lui-même, ne décide rien, classé ici parce qu'il ne sert qu'à la perception.

**`agent`** — ce qui décide :

- **attaches** — ce à quoi l'entité tient, lu par la couche saillance (`attaches.gd`) pour peser ses décisions. Se peuple par généralisation depuis `liens_personnels` (`attache_par_trait.gd`) — un mécanisme automatique fait grandir son contenu, mais ce qu'il REPRÉSENTE (l'identité qui oriente le choix) le range côté décision, pas côté état brut. Aujourd'hui vide FONCTIONNELLEMENT : `banc_commun.gd:fabriquer_colon` écrase encore cette clé par la donnée locale de chaque banc ; `forme`/`poids_verbes`, qui décident aussi, vivent hors `data/types.json` (côté banc) et migreront dans ce paquet quand `fabriquer_colon` disparaîtra.

### Contraintes structurelles

- **Cadre venu de la doctrine, pas d'un modèle importé.** Les tentatives d'importer BDI (Bratman) ont été rejetées : BDI met la déformation après la perception (l'inverse de la doctrine Orion), énumère des goals candidats (Orion n'énumère rien, la saillance émerge), exige des plans pré-écrits (Orion est data-driven), défend l'intention contre la distraction (Orion laisse la dominance réévaluer à chaque tick). Le vocabulaire (belief, desire, intention, memory) peut décrire ce que fait l'entité vue de l'extérieur, mais la mécanique BDI ne construit pas ce que fait Orion. PRÉCISÉ depuis, sans rien retirer de ce rejet : une croyance qui REMPLACE L'ENTRÉE de la couche 2 sans toucher aux quatre couches ne tombe sous aucun des quatre griefs — voir « La croyance : une copie partielle, née de la perception vécue ».
- **Résumabilité JSON stricte.** `proprietes` d'une entité contient exclusivement du JSON pur : int, float, string, bool, null, Array, Dictionary. Positions en `{x, y, z}` (Vector3 en interne, sérialisé Dictionary), références par ID string, zéro Callable. Contrainte alignée avec le régime "deux régimes de simulation" (compression des factions lointaines), l'LLM lecteur ancré, et le déploiement serveur.
- **Test hors domaine obligatoire.** Chaque nouveau mécanisme du cœur (engagement, canal, déformation) doit prouver sa généricité par un test sur un domaine sans rapport avec le colon. Sans exception.
- **Spirale d'approfondissement.** Le chantier n'est pas une liste de tâches à cocher, c'est une spirale : chaque phase pose des mécanismes que les suivantes utilisent comme briques. Ordre : PHASE 0 → 1 → 3.5 → 2 → 3 → 4 → 5 → 6 → 7.

### Renvoi

Cadrage détaillé, questions tranchées, points reportés, décisions par composant : `docs/cadrage_corps_interne_colon.md`. Suivi opérationnel de l'avancement : `docs/suivi_corps_interne_entite.md`.

## Questions ouvertes

Les modificateurs temporaires (malédiction, mutation, blessure)
doivent-ils muter la forme, ou se poser comme un CALQUE au-dessus
d'une forme qui reste immuable ? Muter la forme casse "immuable" et
complique tout retour arrière. Un calque empile un modificateur
temporaire, lu en même temps que la forme au moment du calcul, sans
jamais l'altérer. Piste privilégiée, non tranchée.

Le passage lien personnel → attache par trait (voir Le modèle : attaches
et forme, L'ÉLARGISSEMENT) : FERMÉ (PHASE 5 étape 4). Le déclencheur
n'est ni `deformer` (la forme reste immuable) ni la table de
transformations (hypothèse écartée en pratique) : un mécanisme dédié,
`attache_par_trait.gd`, appelé comme deuxième effet de bord de
`agir.gd:choisir`. Le seuil est COMPOSITE, nombre ET force (option (c),
tranché par Yael) — surchargeable par colon, valeurs de démarrage dans
`data/attaches_par_trait.json` (ajustables au playtest, pas figées).

`vegetal`/`bati`, écartés : c'est « arbre »/« batisse » déguisés en
adjectifs, pas des traits. Une tour de guet en bois porterait les deux
sans que ça dise pourquoi elle est défendable — le mot ne pointe vers
aucune raison, juste vers la matière de la chose. `irremplacable`
(ce qui ne se rebâtit pas) et `notre_ouvrage` (ce que la colonie a fait)
répondent à la question que « Règle opposable » pose : un trait doit
pouvoir être porté par une chose qu'on n'a pas encore imaginée POUR LA
MÊME RAISON qu'une bâtisse ou un arbre — pas seulement par coïncidence
de matière.

Vocabulaire de traits défendables, NON TRANCHÉ : `irremplacable` et
`notre_ouvrage` sont des booléens ajoutés au besoin, pas des axes de
description. À deux traits c'est sain ; à vingt ce sera un catalogue
déguisé — le nom revenu, découpé en morceaux. La question d'un
vocabulaire d'axes (matière, taille, vivant, mobile, ce qui l'endommage)
reste ouverte, à trancher avant que la liste de traits ne grossisse.

Le verbe d'action, TRANCHÉ (voir « Plusieurs verbes par propriété, poids
par colon ») : ni la chose seule, ni le colon seul — la propriété propose
une LISTE de verbes (couche 2, universel), le colon choisit lequel par
son propre `poids_verbes` (troisième axe, au même rang qu'attaches et
forme). Restent NON TRANCHÉS, décrits dans cette même section : deux
verbes à poids égal chez un colon, et une chose portant deux propriétés
actionnables à la fois.

Ce qu'une zone représente, TRANCHÉ : une zone n'est pas un objet — c'est
un résumé lu à la demande sur les objets/colons présents dans une
région, jamais un état détaché qui vivrait indépendamment d'eux (voir
« Les collectifs n'existent pas »). `_monde`/`_monde_stub` continuent de
ne porter que des objets, jamais un état détaché d'un objet — ça ne
change pas, ça cesse d'être un manque : c'est la doctrine. Non tranché
encore : granularité de la grille, qui écrit/lit une cellule — question
de câblage d'un futur lecteur de résumé, pas de modèle du monde.

Propagation et terrain — TRANCHÉ par le chantier « écoulement gravitaire —
eau par pente » (`scripts/banc_ecoulement.gd`, `CARTE.md` `banc_ecoulement`) :
QUAND un terrain est nécessaire, il se modélise en CASES-OBJETS ordinaires
(`{ id, position, proprietes }`), enregistrées comme n'importe quelle autre
chose — jamais une structure séparée, jamais une grille hors du modèle
« tout est objet ». L'ancien prototype (`feu_proto.gd`, supprimé)
utilisait une grille de cases où le vide servait de coupe-feu naturel ;
`propagation.gd` reste en distance libre, sans terrain — ce chantier ne
l'a pas changé, il a seulement prouvé la voie pour tout futur mécanisme
qui en aurait besoin. Position reste un FAIT SPATIAL PUR (jamais
l'altitude — voir « Verticalité » : Z reste à zéro même pour un terrain en
pente) ; une grandeur comme l'altitude vit en PROPRIÉTÉ NOMMÉE,
découplée de `position`, lue par le mécanisme via un nom passé en
paramètre (voir `scripts/ecoulement.gd:avancer`, paramètre `nom_altitude`).

Ordre dans menaces.json, non tranché : la résolution de vulnérabilité
(dans la propagation) retourne la première trouvée en itérant `menaces` ;
la détection « en feu » (dans la propagation) teste si UNE quelconque
propriété-menace est présente — extinction.gd ne connaît plus la menace,
seulement un chantier déjà résolu (adresses exactes : `CARTE.md` §2).
Correct tant que menaces.json
n'a qu'une ligne. Dès qu'il y en a deux, une chose portant deux
vulnérabilités se comporte selon l'ordre des clés du JSON — un résultat
qui dépend d'un détail d'implémentation, pas du monde. À trancher :
quelle menace l'emporte quand plusieurs s'appliquent à la même chose.

Le placide : il vient partout, il ne tient nulle part. Seul colon
capable de renforcer n'importe quel front, seul aussi capable de le
lâcher. Le compromis — assez d'attache pour qu'il reste quelque chose,
assez peu pour ne pas mourir dessus — n'a pas de forme gagnante
identifiée.

Personne n'est stupide — un seul mécanisme de décision, pas encore écrit
ailleurs que dans cette phrase : il n'existe aucune branche « colon
intelligent » et « colon stupide ». Les quatre couches sont les mêmes
pour tous (voir « Les archétypes n'existent pas »). Ce qui a l'air
stupide de l'extérieur — défendre une cabane pendant que le village
brûle — n'est pas une erreur de calcul, c'est une coïncidence RATÉE
entre la forme d'un colon et la situation du moment : la même forme qui
le sert dans un contexte le dessert dans un autre. La RÈGLE ANTI-BRUIT
(voir Le modèle : attaches et forme) dit déjà que l'erreur est
déterministe et lisible depuis la forme — cette entrée en tire la
conséquence générale : rien à corriger dans un colon qui « se trompe »,
parce qu'aucun colon ne calcule mieux qu'un autre. Non tranché : si un
joueur peut apprendre à lire cette distinction (forme mal accordée à la
situation) sans qu'elle ressemble à de la bêtise à l'écran — question
d'interface, pas de moteur.

Notes héritées, non retravaillées, à reprendre une par une :

- Contrepartie du fanatique : il voit avant les autres. Portée de
 perception étendue sur ce qui touche son attache — même nombre que
 le rayon de liaison, lu dans l'autre sens.
- La compétence est dans le résultat, pas dans une fiche de stats. Le
 champ est la fiche.
- À creuser (n'existe dans aucun jeu connu) : le joueur pose des
 tâches disponibles, les colons choisissent. La tâche que personne ne
 prend est une information sur ses gens.
### Deux régimes de simulation

Loin du joueur, les colons existent toujours — chacun reste un
Dictionary `{ id, position, proprietes }` (voir plus bas), mis à jour à
basse fréquence plutôt qu'à chaque tick. Ce que le joueur perçoit comme
« l'état d'une faction » (population, ressources, territoire, tensions)
n'est jamais un objet séparé qui remplacerait ces colons : c'est un
RÉSUMÉ lu à la demande sur l'ensemble des colons dormants de la région
— voir « Les collectifs n'existent pas ». À l'approche du joueur, rien
n'est instancié depuis un état abstrait : ce sont les mêmes colons,
déjà là, qui montent en fréquence et reçoivent un rendu.

Contrainte que ça impose au colon, dès maintenant : un colon doit être
RÉSUMABLE. Ses attaches, sa forme, sa position se compressent en quelques
nombres. Rien de ce qu'on lui ajoute ne doit rendre cette compression
impossible.

Non tranché :
- comment l'état abstrait garantit une instanciation cohérente (si l'état
 dit "affamés après une guerre perdue", le village instancié doit le
 montrer)
- comment une zone détaillée se RE-RÉSUME quand le joueur s'en va, sans
 perdre ce qui s'y est passé

Contrainte de résumabilité, conséquence : tant que des fragments de règles
sont copiés PAR VALEUR sur chaque instance au lieu d'être référencés par une
clé de catalogue, résumer un objet n'est pas résumer « quelques nombres »,
c'est aussi résumer ces fragments dupliqués. L'état exact de ce qui est
encore copié par valeur (vs déjà passé en référence) est une dette de
câblage, pas de design : elle vit dans `CARTE.md` §2 et `docs/prototypes.md`,
jamais ici — un état recopié dans design.md périme sans que personne ne le
remarque (même raison qu'à « Modèle objet », plus haut).

RÉSULTAT VÉRIFIÉ, à ne pas reperdre : la migration vers la référence de
catalogue (`profil_saillance`, `seuils_ref`) devait encore prouver que la
contagion — une chose qui hérite une clé du patron à l'allumage
(`propagation.gd` + le patron réel) — pose bien une référence RÉSOLUBLE,
pas une copie de valeur figée. Confirmé par un script jetable (jamais
commité, hors du dépôt) : chaque chose enflammée par propagation porte
une référence de catalogue qui se résout correctement, indépendamment des
autres choses déjà enflammées.

Un colon est un Dictionary, quelle que soit sa distance au joueur. Proche :
le Dictionary est mis à jour chaque tick, un rendu (ColorRect, sprite,
mesh) est accroché dessus, la physique et les collisions sont actives.
Loin : le même Dictionary est mis à jour à basse fréquence (par jour, par
saison), aucun rendu, aucune collision, aucune physique. La promotion
(loin → proche) accroche le rendu sur un Dictionary qui existait déjà. La
dégradation (proche → loin) décroche le rendu, le Dictionary reste. Il
n'y a pas de compression, pas de décompression, pas de graine, pas de
forme distincte entre les deux régimes. L'état est le même objet — seuls
le rendu et la fréquence de mise à jour changent. Le coût mémoire d'un
colon sans rendu est son Dictionary seul — quelques clés, quelques
nombres, coût quasi nul.

### Simulation accélérée : delta petit et facteur d'échelle, jamais un grand delta

TRANCHÉ par le chantier « simulation accélérée — le monde existait avant
toi » (`scripts/banc_simulation_acceleree.gd`, `CARTE.md`
`banc_simulation_acceleree` ; question posée par, laissée ouverte jusque-là).

Simuler des millénaires en quelques secondes se fait en RÉPÉTANT un pas
PETIT et FIXE et en montant un FACTEUR D'ÉCHELLE — jamais en agrandissant
`delta`.

ÉCARTÉ, et pourquoi : un grand delta donne le même âge simulé et pas le
même monde. Deux mécanismes le cassent, chacun à sa façon —
`temperature.gd` DIVERGE (Euler explicite : dès que
`(conductivite/chaleur_specifique)·delta > 2`, l'oscillation croît sans
borne) ; `ecoulement.gd` devient NON PHYSIQUE (une case se vide
intégralement vers son premier voisin plus bas dans l'ordre d'itération —
son propre en-tête l'assume déjà, « accepté par calibration, delta petit »).
Ils étaient TROIS : `consommer.gd` perdait la conservation à grand delta
(il créditait la quantité demandée, pas la quantité retirée) — corrigé
depuis, il est conservatif par construction, voir « Consommer : transfert
DESTRUCTIF » ci-dessus. Les deux qui restent viennent du même choix
implicite (Euler explicite non sous-échantillonné). Rendre un grand delta sûr exigerait un
découpage en sous-pas INTERNE aux mécanismes — donc de toucher le cœur. Ne
pas le reproposer sans que ce coût soit explicitement accepté.

Le facteur d'échelle, lui, était déjà doctrinal : `senescence.gd:avancer`
reçoit `annees_par_seconde` en paramètre — « c'est au CÂBLAGE de choisir à
quelle vitesse le temps du jeu vieillit ses entités, pas à ce mécanisme de
le deviner ». La boucle accélérée est donc du CÂBLAGE, jamais un mécanisme :
aucun `.gd` du cœur n'a été écrit ni modifié pour ce chantier.

TROISIÈME HORLOGE, ajoutée depuis (chantier « horloge du monde — heure et
saison dans le cœur », `scripts/horloge.gd`, `CARTE.md` §2) : le TEMPS DU
MONDE — heure du jour et saison courante. La note de `data/senescence.json`
(« aucun concept de temps du monde — tick_total/saison — n'est implémenté »)
est RÉSOLUE ; ce qui reste vrai, et ne change pas, c'est que rien dans le
moteur ne TIENT ce temps : `horloge.gd` le CALCULE à partir d'un
`temps_ecoule` que le câblage lui donne, `senescence.gd:avancer` l'ÉCRIT sur
l'entité (`heure_courante`/`saison`) quand une horloge lui est fournie —
aucun accumulateur global n'a été créé, et il n'y a toujours pas de boucle de
tick centrale dans ce dépôt (`monde.gd` n'a pas de `_process()`).

Ce qui décide de la forme, et qui vaut pour toute grandeur temporelle future :
le temps du monde suit la MÊME règle que le facteur d'échelle ci-dessus — un
`duree_jour_secondes` reçu en paramètre relie les secondes de simulation au
calendrier, exactement comme `annees_par_seconde` les relie à l'âge. Un
mécanisme du cœur ne devine JAMAIS combien de temps dure un jour, ni combien
d'heures il compte (aucun `24.0` en dur — un monde à dix heures par jour doit
traverser le même code), ni comment s'appellent ses saisons (un Array de noms
déclaré en donnée, comme `stades_config` pour `stade.gd`).

CONSÉQUENCE À NE PAS REPERDRE — trois horloges découplées. `senescence.gd`
est le seul mécanisme dont l'unité de sortie est l'ANNÉE (`proprietes.age`,
INDIVIDUELLE — chaque entité a la sienne) ; le temps du monde est en heures
et en nom de saison (MONDIAL — identique pour toutes les entités du même
tick) ; tous les autres mécanismes travaillent en SECONDES DE SIMULATION.
L'âge ne se déduit jamais de l'heure, ni l'inverse. Monter `annees_par_seconde` fait donc
vieillir le vivant vite SANS accélérer la physique d'un iota. C'est voulu :
une forêt pousse en millénaires, une flaque s'écoule en secondes, et les
accélérer d'un même facteur donnerait un monde où l'eau aurait traversé la
vallée un million de fois avant le premier arbre. « N années simulées » ne
se lit jamais « N années de pluie ».

RÉSULTAT NÉGATIF MESURÉ, à ne pas refaire : le débit en années par seconde
réelle NE DÉPEND PAS du nombre d'itérations par tick — doubler N divise le
nombre de ticks par deux, le produit est constant. N ne règle que la finesse
du pas physique et la fluidité du rendu ; seul `annees_par_seconde` règle la
vitesse. Monter N pour « aller plus vite » ne fait que rendre le rendu
saccadé.

## Les collectifs n'existent pas — un résumé lu, pas un objet posé

Sur le modèle de « Les archétypes n'existent pas » et « Tout est objet »,
un cran au-dessus : la première dit qu'un fanatique n'est pas un TYPE, la
seconde dit qu'un colon n'est pas une CATÉGORIE. Celle-ci dit qu'une
faction, une cité, une colonie, une foule, une croyance partagée ne sont
pas des ENTITÉS.

Le monde ne contient que des colons individuels (`{ id, position,
proprietes }`). Aucun objet-groupe. Aucun conteneur qui porterait des
propriétés qu'aucun colon ne porte.

Un mot collectif (« faction », « cité », « croyance rouge ») est produit
à la demande par un LECTEUR — l'LLM ancré, ou un futur module de résumé
pour le joueur — qui scanne N colons et en tire un fait agrégé. Le mot
naît du regard porté sur les colons, pas d'un objet qui les
contiendrait.

Analogie : les États-Unis. Retire les habitants, le mot n'a plus de
référent. La densité, la population, les tensions politiques ne sont pas
des objets qui existent quelque part ; ce sont des lectures faites sur
les gens qui existent.

Analogie 2 : mille colons construisent chacun leur maison. Aucun ne
« construit une cité ». Le joueur dézoome, il voit un motif, il l'appelle
« cité ». Le mot naît du dézoome — la cité n'a pas d'existence
indépendante des colons qui la composent.

Ce que ça n'interdit PAS : utiliser les mots collectifs pour parler du
jeu — au joueur, à l'LLM, à soi-même. Sans eux, on ne peut plus rien dire
(« la Chine, c'est un milliard d'individus » — s'il faut les nommer un
par un, on ne s'en sort pas). Les mots collectifs sont des outils de
lisibilité, pas des mensonges, à condition qu'ils restent au niveau de
la LECTURE, jamais au niveau du monde.

Ce que ça implique pour le noyau : aucun mécanisme du cœur ne gagne le
concept d'objet-groupe. La couche qui parle au joueur (encore à
construire) sait scanner N colons et produire un résumé ; le noyau lui
fournit les colons, jamais un raccourci pré-calculé.

Ce que ça implique pour l'LLM ancré (voir « L'LLM : lecteur ancré, jamais
auteur ») : sa règle habituelle tient — il lit l'état vrai, il l'habille
en langage. Ici, le « vrai » est distribué sur N colons ; l'LLM l'agrège
au moment de parler, il ne trouve jamais d'objet-faction à lire
directement. C'est ce qui l'empêche de halluciner une propriété
collective qui ne serait posée nulle part dans le monde.

Ce que ça débloque, en une seule décision :
- la « zone » — TRANCHÉ, voir Questions ouvertes : une zone est un
 résumé lu sur les objets présents dans une région, jamais un objet
 qui porterait un état indépendamment.
- la sédimentation psychique (voir « Principe de magie ») ne cherche
 plus où vivre : chaque acte marque le colon qui l'a fait, l'agrégat
 magique se lit ensuite sur l'ensemble des colons d'une région.
- le résumé de zone des « Deux régimes de simulation » n'a plus besoin
 d'être un objet séparé : c'est un calcul sur les colons dormants, pas
 une compression qui les remplacerait.

Cette couche lecteur a deux briques, et elles répondent à deux questions
qu'il ne faut pas confondre : COMBIEN D'ENTITÉS satisfont une règle
(`comptage.gd`, un `int`) et COMBIEN AU TOTAL une liste porte d'une
grandeur (`somme.gd`, un `float`). Une lecture agrégée de plus se pose
d'abord la question de savoir laquelle des deux elle est ; si elle n'est
ni l'une ni l'autre, c'est une troisième brique, jamais un mode ajouté à
l'une d'elles (un mode `somme` dans `comptage.gd` changerait son type de
retour, donc sa signature, pour tous ses appelants). Voir CARTE.md §2.
Premier banc du vécu inter-colon : voir CARTE.md §3 banc_vecu_inter_colon.
La contagion se fait par lien_personnel_croissance.gd, mécanisme du cœur
qui fait monter les liens depuis les perceptions filtrées par trait.

## Ce qu'une transformation ne peut pas faire

Une transformation change ce qui existe : elle retire, remplace ou
dégrade des propriétés. Elle ne crée ni masse, ni échelle, ni
complexité nouvelle. Un mal qui corrompt fait du lapin une chose
informe et toxique, jamais un dragon : la corruption défait, elle ne
construit pas. Tout gain réel exige une source extérieure, finie et
localisée — la lumière, la matière ingérée. Sans source identifiée
dans le monde, une transformation qui enrichit est un bug de design.

## Piste ouverte — transformations qui atteignent l'immuable

Trois niveaux, pas deux :
- l'immuable (la forme), référence de tout retrait
- les calques empilés au-dessus (blessures, séquelles, malédictions)
- les rares transformations qui atteignent l'immuable lui-même

La mort est le cas évident : elle ne s'empile pas, elle rend les
calques sans objet. Candidats à examiner : maturation, reproduction.

## Principe de magie — sédimentation psychique

La magie n'est pas une ressource ni un pouvoir accordé. Elle est un
RÉSIDU de ce que le monde fait.

Chaque acte dépose une unité dans une sous-couche selon sa nature :
abattre un arbre dépose du végétal, forger une arme dépose de la guerre,
bâtir dépose de la construction. Un acte peut alimenter plusieurs
sous-couches à la fois (un animal de guerre alimente la guerre et
l'animal). Le dépôt est mécanique, SANS JUGEMENT : aucune sous-couche
n'est bonne ou mauvaise, aucune faction n'est punie ou récompensée par
ce qu'elle dépose.

OPACITÉ TOTALE : le joueur ne voit aucune jauge de sédimentation, aucun
nom de sous-couche, aucun total — même principe que « Interface : zéro
nombre affiché ». Ce qui sédimente se déduit des effets qu'il produit
dans le monde, jamais d'un chiffre consulté. Si un joueur peut ouvrir un
écran et lire « guerre : 340 », l'opacité a déjà été percée.

Non tranché : ce qui qualifie une transformation pour ce troisième
niveau, et comment le moteur la distingue d'un calque irrétirable.
À reprendre quand le besoin se présentera.

OÙ VIT LE DÉPÔT (voir « Les collectifs n'existent pas ») : chaque acte
marque le colon qui l'a accompli — pas un dépôt séparé, pas un
objet-zone qui l'accumulerait. Lire une sous-couche (« combien de guerre
a été déposée ici ») est un résumé sur les colons présents dans une
région donnée, calculé à la demande, jamais un total qui vivrait quelque
part en dehors d'eux. Aucun objet-couche à créer.

## Chaînage automatique de réactions : par le temps, jamais par une boucle interne

`scripts/reaction.gd` (chantier « composition en profondeur — chaînage
automatique de réactions », détail : `CARTE.md` §2/`banc_chaine_reactions`) pose un
principe généralisable à toute future transformation en cascade, pas
seulement aux réactions chimiques : une cascade est une PROPRIÉTÉ DU
TEMPS, jamais une boucle que le mécanisme parcourt lui-même en interne.
Un mécanisme qui détecterait puis appliquerait plusieurs étages de
transformation dans le MÊME appel produirait un résultat qui dépend de
l'ordre d'itération interne (quel objet est visité en premier) — la même
faute que les calques qui s'écrasent (voir « Cause, jamais résultat »).
La discipline retenue, applicable à tout futur mécanisme de cascade : deux
passes disjointes, DÉTECTION sur l'état du monde au début de l'appel, puis
APPLICATION — un objet transformé pendant l'appel n'est jamais relu par la
détection de ce même appel. La cascade émerge du prochain appel (le
prochain tick du câblage), jamais d'une récursion.

`profondeur_chaine_max` est la protection GÉNÉRIQUE contre les boucles
infinies d'une telle cascade (A+B→C, C+D→A, A+B→C...) : chaque objet porte
`_profondeur_chaine` (0 par défaut, un objet de base n'est le produit
d'aucune réaction), et un objet à `_profondeur_chaine >= profondeur_max`
sort de la détection, qu'il joue le rôle de source ou de cible. C'est la
MÊME famille de garde que `profondeur_max` ailleurs dans le dépôt
(récursion bornée), jamais une exception locale à la chimie.

MODÈLE ASYMÉTRIQUE, DÉCISION YAEL : entre deux réactifs, l'un (source,
« materiau_a ») n'est jamais transformé par la réaction, l'autre (cible,
« materiau_b ») seul le devient. Retenu plutôt qu'un modèle symétrique (les
deux réactifs deviennent chacun une copie du même produit) parce qu'un
réactif source doit pouvoir survivre à sa propre réaction pour continuer
d'en déclencher d'autres à portée — c'est ce qui permet à un catalyseur
(l'eau, un acide) de rester lui-même pendant qu'il fait réagir plusieurs
cibles successives, sans qu'aucun cas particulier ne le distingue dans le
mécanisme.
