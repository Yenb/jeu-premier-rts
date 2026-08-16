# Prototypes

Frontière : ce fichier porte l'état des bancs et leur dette précise
(fichier ET fonction ou constante concernée — jamais un numéro de ligne,
qui périme silencieusement à chaque édition du fichier cité et ne se
retrouve pas par grep), mis à jour à chaque session — pas le rationale de
design (ça, c'est `docs/design.md`) ni l'index du moteur (`CARTE.md`, qui
porte déjà le détail exhaustif de chaque mécanisme et de chaque câblage de
banc — non recopié ici, « voir CARTE.md » partout où c'est le cas).

## À quoi sert un banc
Un banc n'est pas une démo. Il existe pour VOIR une chose que les tests ne
montrent pas.

Tout ce qui empêche d'observer cette chose est un défaut du banc, même si
aucun test ne casse. Une saillance qui ne retombe jamais, des colons
superposés, un feu éternel : le code est juste et le banc ne sert à rien.

Règle : tout comportement d'un banc qui a marché une fois est verrouillé par
un test headless. Un banc régresse comme le reste.

Un banc est jetable. Ses tests ne le sont pas. Jetable ≠ supprimable :
c'est la surface (scène, image, touches) qui n'est définitive en rien et
se modifie librement ; les connexions qu'elle établit entre `data/` et le
cœur, elles, sont acquises et ne se coupent jamais — doctrine complète
dans `docs/design.md`, « Les bancs : le livrable est le test vert, jamais
l'image ».
Rien de décisif ne vit dans un banc : il câble les couches et traduit une
décision en image. Le jour où une règle de jeu commence à vivre dedans, il
cesse d'être jetable et devient une dette.

MOTIF RÉCURRENT, à appliquer à tout câblage neuf : une propriété câblée
entre un banc et le cœur se teste avec une valeur qui n'est JAMAIS le
défaut du lecteur — sinon la panne reste invisible, déguisée en
comportement normal. Toutes les instances connues sont fermées
(`CARTE.md` §6) ; le motif reste un principe, plus un défaut ouvert.

## banc_p1 — trois colons, une seule règle qui les sépare

`Scene/banc_p1.tscn`, `scripts/banc_p1.gd`, `data/banc_p1.json`. Test : `scripts/test_banc_p1.gd`. Détail du câblage : `CARTE.md` `banc_p1`.

**Montre.** Trois colons aux couches identiques ; seule leur table de
verbes les sépare. Un clic gauche allume un feu ; ils convergent et
l'éteignent. Le feu se propage aux choses inflammables voisines, qui se
consument seules faute de défenseur.

**Ne montre pas.** Aucune distinction visuelle entre un feu d'origine et
une chose qui vient de prendre feu — même orange. Rien ne rend visible
l'exposition ni le travail d'extinction qui s'accumulent avant la bascule :
embrasement et cendre arrivent d'un coup. `s_eloigner` est câblé mais
INERTE ici — aucun catalogue chargé par ce banc ne propose ce verbe, les
trois colons ne peuvent jamais le retenir. Pour le voir : `banc_feu`.

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée).

## banc_animal — flux et dépense joués ensemble

`Scene/banc_animal.tscn`, `scripts/banc_animal.gd`, `data/banc_animal.json`. Test : `scripts/test_banc_animal.gd`. Détail du câblage : `CARTE.md` `banc_animal`.

**Montre.** Un animal entre une source de lumière et une zone d'herbe.
Deux réserves vidées en continu par `depense.gd` et rechargées par
`flux.gd` UNIQUEMENT au contact (`portee_flux` = la taille du carré : pas
de régénération à distance). L'animal va vers la source qui recharge sa
réserve la plus basse. Deux barres au-dessus de lui, aucun nombre.

**Portée volontairement limitée** (`docs/design.md`, « Exemple travaillé :
l'animal photosynthétique ») : pas de paliers, pas de régimes croisés, pas
de reproduction, pas de prédateur, pas de refuge. Ces raffinements sont
des bancs suivants.

**Ne montre pas.** Aucun signal distinct quand une réserve devient
négative — la barre reste à largeur zéro, ce qui ne répond pas à
« l'animal meurt-il ? ».

**Non vérifié à l'œil** (pas d'écran).

## banc_feu — bascule individuelle entre éteindre et fuir

`Scene/banc_feu.tscn`, `scripts/banc_feu.gd`, `data/banc_feu.json`. Test : `scripts/test_banc_feu.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_feu`.

**Montre.** Trois colons — prudent, peureux, mesuré — mêmes couches, même
scène ; seuls `gain_jugement` et `poids_verbes` diffèrent. Un clic allume
un feu ; aucun au démarrage. Les trois pèsent `approcher` sur le feu. Sur
la propriété `abrite` (portée par deux choses fixes, eau et pierre), le
prudent ne pèse que `se_proteger`, le peureux que `s_eloigner`, le mesuré
LES DEUX. À peu de feux, la saillance du feu domine : tous éteignent. Vers
trois feux le peureux SEUL bascule et FUIT — un mouvement de répulsion qui
l'éloigne des deux abris, jamais vers eux. Vers cinq-six feux le mesuré
bascule à son tour, mais son `poids_verbes` retient `se_proteger` : il
REJOINT physiquement un abri, seul des trois à le faire. Le prudent
continue d'éteindre bien au-delà. Une ligne console par changement
d'action.

Eau et pierre portent chacune un marqueur textuel lu sur la propriété
`abrite`, jamais sur un nom de type : ce sont deux instances INDÉPENDANTES
de la même propriété, pas une chose dupliquée à l'écran.

**Ne montre pas.** La lecture de la déformation par `jugement.gd` est
INERTE ici — aucun des trois colons ne porte de déformation forcée sur
`brule` ; cette divergence n'est prouvée qu'en isolation par
`scripts/test_jugement_deformation.gd`. La distinction eau/pierre ne tient
qu'au marqueur textuel.

**Non vérifié à l'œil** (pas d'écran) : les deux marqueurs doivent rester
lisibles et alignés au-dessus des bons carrés.

## banc_charge — la peur s'accumule, elle ne réagit pas instantanément

`Scene/banc_charge.tscn`, `scripts/banc_charge.gd`, `data/banc_charge.json`. Test : `scripts/test_banc_charge.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_charge`.

**Montre.** Premier câblage réel de `charge.gd`. Deux colons, prudent et
peureux, mêmes couches ; seul le SEUIL de charge diffère. Chacun porte un
canal `peur` qui MONTE tant qu'un feu est à portée, FRANCHIT son propre
seuil et pose `effraye`, puis REDESCEND et le retire en l'absence de feu —
réversible, jamais un événement unique. Le peureux bascule après une
exposition courte, le prudent après une longue, par le MÊME code.
`effraye` est ensuite lu par `jugement.gd` : la propriété `refuge` devient
saillante et le colon quitte l'extinction pour fuir ou se protéger. Le
carré vire au rouge à la pose et revient à la couleur d'origine au
retrait, lu sur le retour de `Charge.avancer`, jamais sur un état suivi à
la main.

**La différence avec `banc_feu`, et c'est le sujet** : là-bas la bascule
dépend du NOMBRE de feux perçus à l'instant, ici de la DURÉE d'exposition
à un seul, quel que soit leur nombre.

**Confirmé par Yael à l'écran** : les deux éteignent, le peureux bascule
et fuit vers l'eau, le prudent bascule à son tour et se protège.

**Ne montre pas.** Aucune distinction eau/pierre au-delà de leur couleur
propre (même limite que `banc_feu`).

## banc_deformation — deux colons identiques, une divergence par le vécu

`Scene/banc_deformation.tscn`, `scripts/banc_deformation.gd`, `data/banc_deformation.json`. Test : `scripts/test_banc_deformation.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_deformation`.

**Montre.** Première source réelle de `deformation.gd` — habituation sur
`brule`. Deux colons identiques à leur naissance ; seule leur POSITION
diffère, unique variable expérimentale. `expose` reste en permanence à
portée de vue d'un feu stationnaire jamais éteint ; `isole` est hors de
portée de toute source. `Deformation.poser()` est appelé à chaque tick où
un colon perçoit `brule`, `Deformation.avancer()` tourne pour les deux.
Une barre par colon reflète le biais : celle de l'exposé grandit tick
après tick, celle de l'isolé reste nulle. Aucune interaction — la
divergence s'installe seule.

**Portée volontairement limitée.** Rien ne passe par
`attaches.gd`/`proximite.gd`/`jugement.gd`/`dominance.gd`/`agir.gd` :
`decider()` et `agir_et_deplacer()` n'existent pas dans ce fichier. La
divergence de SAILLANCE — et pas seulement de biais accumulé — est prouvée
par des chemins dédiés (`test_proximite_deformation.gd`,
`test_attaches_deformation.gd`, `test_jugement_deformation.gd`).

**Ne montre pas.** Aucun retour console sur la valeur du biais : seule la
barre la porte. Et AUCUN banc du dépôt ne montre encore cette divergence
de saillance se traduire en décision visible ; il faudrait un banc qui
compose l'exposition de celui-ci avec un pipeline complet — non construit,
recensé comme ouvert dans `docs/ETAT.md`.

## banc_lien_personnel — trois colons défendent le même ouvrage, à des rythmes différents

`Scene/banc_lien_personnel.tscn`, `scripts/banc_lien_personnel.gd`, `data/banc_lien_personnel.json`. Test : `scripts/test_banc_lien_personnel.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_lien_personnel`.

**Montre.** Quatre colons identiques à leur naissance — même
`poids_verbes`, mêmes `liens_personnels` vides ; seules leur POSITION et
leur `sensibilite_generalisation` diffèrent. Trois pompiers se déplacent
jusqu'à une bâtisse en feu, s'y engagent et l'éteignent réellement ; le
`spectateur`, hors de portée de vue de tous, reste inerte. À chaque tick
où la décision d'un colon résout `eteindre` sur une chose `notre_ouvrage`,
`Agir.choisir` pose lui-même un lien personnel, PUIS vérifie si assez de
choses liées assez fortement forment une attache par trait. Ce banc ne
pose ni ne vérifie jamais rien directement : il appelle le pipeline
complet et fait avancer la décroissance. Une barre par colon porte la
force du lien ; un CARRÉ DORÉ apparaît dès que l'attache se forme et y
reste pour toujours — `pompier_rapide` après 2 choses défendues,
`pompier_moyen` après 3, `pompier_lent` après 5.

Deux choses de plus, sans aucun clic : un `bois` placé du côté OPPOSÉ aux
pompiers s'enflamme par PROPAGATION pendant que la bâtisse brûle, puis se
consume seul faute de défenseur ; et un `feu_proche` sans `notre_ouvrage`,
posé plus loin du pompier que la bâtisse, dont la saillance DIVERGE
réellement entre les colons sans jamais faire basculer leur décision —
c'est la lecture du lien personnel qui devient observable, pas un
changement d'action.

**Contrôles.** Clic gauche : un feu de plus, portant `notre_ouvrage`. Le
premier colon qui l'éteint pose donc son propre lien — plusieurs clics
produisent plusieurs liens simultanés, sans une ligne de code neuve, juste
une donnée de plus sur le type cliqué.

**Portée volontairement limitée.** Rien ne passe par `jugement.gd` ni
`fuite.gd` : aucun abri, aucune fuite à démontrer. `lien_personnel_attraction.gd`
y a son seul câblage réel mais reste SANS EFFET OBSERVABLE ici — la cible
porte déjà un profil de saillance, le candidat qu'il ajoute double donc
une cible déjà gagnante. La preuve du trou comblé — une chose aimée sans
saillance propre devient atteignable — vit dans
`test_lien_personnel_attraction.gd`.

**Subtilité mesurée, à connaître avant d'observer.** Une fois qu'un
pompier a accumulé de la force sur la bâtisse, le bonus de lien l'y
VERROUILLE tant qu'elle brûle. Les trois finissant groupés au même point,
un clic posé près de l'un peut être perçu et défendu par un AUTRE : pour
isoler un pompier, cliquer hors de portée de vue des deux autres, ou lire
le log par décision pour savoir qui a réellement résolu le verbe.

**Ne montre pas.** Aucune valeur numérique du lien ni de la saillance en
console — la barre seule porte le lien, et le log ne donne que le compte
et la cible. Feux éteints et feux consumés partagent la même teinte
cendre. Et la seule bâtisse fixe ne suffit qu'à UNE défense : sans clic,
aucun pompier ne forme jamais son attache.

## banc_comptage — un compte qui varie, sans qu'aucun objet-groupe n'existe

`Scene/banc_comptage.tscn`, `scripts/banc_comptage.gd`, `data/banc_comptage.json`. Test : `scripts/test_banc_comptage.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_comptage`.

`scripts/comptage.gd` (premier mécanisme de lecture agrégée, voir CARTE.md
§2) reçoit ici son PREMIER CÂBLAGE RÉEL.

**Montre.** six lucioles indépendantes (`{ id, position,
proprietes : {} }`), disposées en cercle, dont l'état bascule au hasard
(RNG seedé, `data/banc_comptage.json:seed`) à chaque tick — un carré jaune
si `luit` est posée, gris sinon. `luit` est POSÉE ou RETIRÉE, jamais un
booléen permanent (voir CARTE.md `banc_comptage` — le mode `presente` de
`comptage.gd` teste la présence de la clé, pas sa valeur ; un booléen
toujours présent aurait figé le compte à 6/6). Deux lignes de texte en haut de la
scène : « N / 6 luisent » (instantané, recalculé à chaque tick par
`Comptage.compter`) et « compte moyen sur les 60 derniers ticks : X.X »
(moyenne glissante, calculée dans le banc, jamais dans `comptage.gd`). Le
compte varie en continu, jamais figé ; la moyenne glissante s'installe et
se stabilise plus que l'instantané — le même lecteur agrégé donne un fait
résumé lisible à deux échelles de temps différentes. Aucun objet-groupe
n'existe : les six lucioles sont six entités indépendantes, le compteur
affiché est un CALCUL refait à chaque tick à partir d'elles, jamais une
propriété portée par un objet-nuée.

**Portée limitée.** ce banc reste HORS DOMAINE STRICT — ni
colon, ni aucun contenu du jeu Orion, ni mot de regroupement (« nuée »,
« groupe », « région ») pour les six lucioles. Il prouve le CÂBLAGE de la
brique `comptage.gd`, pas une croyance collective réelle sur des colons —
celle-ci suppose des colons qui portent une propriété commune à observer
et un banc séparé, plus large, quand la couche lecteur aura mûri.

**Ne montre pas.** voir `banc_convergence_attache`
ci-dessous pour le premier compte agrégé sur des colons réels — celui-ci
ne prouve encore que le CÂBLAGE de la brique, aucune croyance collective
ne pèse sur une décision (chantier séparé, toujours non commencé). Non
vérifié visuellement par Claude (pas d'écran) : à confirmer par Yael —
les six carrés doivent alterner jaune/gris de façon visible sans figer,
et les deux lignes de texte doivent rester lisibles et se mettre à jour
en continu.

## banc_convergence_attache — un fait collectif produit, jamais porté par un objet-groupe

`Scene/banc_convergence_attache.tscn`, `scripts/banc_convergence_attache.gd`, `data/banc_convergence_attache.json`. Test : `scripts/test_banc_convergence_attache.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_convergence_attache`.

`scripts/comptage.gd` (voir CARTE.md §2) reçoit ici son PREMIER CÂBLAGE
RÉEL SUR DES COLONS ORION — après `banc_comptage.gd`, hors domaine.

**Montre.** trois colons perçoivent trois arbres déjà en feu
(`brule : true`, posés au démarrage). Chaque tick où un colon perçoit un
arbre en feu, un lien personnel s'accumule vers CET arbre précis — même
geste que `banc_deformation.gd` (perception répétée, aucune décision).
Une fois assez de liens distincts assez forts, un colon cristallise une
attache GÉNÉRALE au trait `brule` (carré rouge) : il ne s'agit plus alors
de ces arbres précis, mais de tout ce qui brûle. `Comptage.compter`
(`colons_attache_brule`) rend, à chaque tick, COMBIEN des trois colons ont
déjà cristallisé — « N / 3 colons portent attache au feu » — un FAIT
COLLECTIF lu à la demande sur trois colons individuels, jamais porté par
un objet-groupe. Les trois colons convergent à des instants différents
(seuil individuel différent, exposition identique — voir CARTE.md
`banc_convergence_attache`), rendant le compte observable en train de monter par paliers
(0 → 1 → 2 → 3) plutôt que d'un coup. Une moyenne glissante lisse ce
compte sur une fenêtre plus longue, même composition que `banc_comptage`.

**Portée limitée.** ce banc ne fait JAMAIS peser le fait
collectif produit sur la décision d'un colon — le fait est PRODUIT,
jamais CONSOMMÉ. La croyance collective (un colon qui pèse ce que
d'autres colons portent, via une règle de jugement par exemple) est un
chantier SÉPARÉ, non commencé.

**Ne montre pas.** aucun retour console périodique sur
la force exacte des liens (seul le compte et la moyenne sont affichés) ;
la distinction visuelle colon/arbre repose sur la forme (carré/cercle) en
plus de la couleur — non vérifiée visuellement par Claude (pas d'écran) :
à confirmer par Yael — les trois carrés doivent passer du bleu-gris au
rouge à des instants différents (jamais tous en même temps), le compteur
doit monter par paliers 0→1→2→3, jamais redescendre, et les trois cercles
oranges (arbres) doivent rester visuellement distincts des carrés.

## banc_contagion — un fait collectif ferme la boucle jusqu'à une décision interne

`Scene/banc_contagion.tscn`, `scripts/banc_contagion.gd`, `data/banc_contagion.json`. Test : `scripts/test_banc_contagion.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_contagion`.

`scripts/charge.gd` (voir CARTE.md §2, déjà câblé sur `banc_charge.gd`
pour une menace spatiale) reçoit ici sa PREMIÈRE SOURCE COLLECTIVE — la
même mécanique de seuil réversible, alimentée par un fait produit par un
lecteur agrégé plutôt que par une propriété perçue directement.

**Montre.** trois colons construits à la main, deux portant
l'attache `guerrier` dès le départ, un troisième (« récepteur ») qui les
observe. À chaque tick, `causes_de_attache` sélectionne les voisins
porteurs de l'attache (le récepteur exclu de lui-même) et transforme
chacun en une cause `{ position }` — le comptage émerge de la somme des
poids que `charge.gd` fait déjà en interne, aucun appel à
`Comptage.compter` sur ce chemin. La charge du récepteur monte tant que
les deux porteurs restent dans sa portée, franchit son seuil, pose
`sous_pression_guerrier : true` — un marqueur apparaît, réversible
(contrairement au marqueur immuable d'attache par trait de
`banc_lien_personnel`). Quatre lignes de texte : le compte instantané
(`pression_guerrier = X.XX / seuil = Y.YY`), l'état (`POSÉE`/`ABSENTE`),
la trace du dernier franchissement (`UP`/`DOWN`, horodatée), la moyenne
glissante de la charge.

**Portée limitée.** ce banc ne câble ni `jugement.gd` ni
`agir.gd` — il s'arrête au moment où `charge.gd` pose la propriété
interne. La lecture de cette propriété par `jugement.gd` (pression →
saillance → décision) est un chantier SÉPARÉ, non commencé. Sans
interactivité (aucun clic, aucune donnée ne retire jamais une attache
en direct) : la réversibilité de `charge.gd` — la charge qui redescend
et retire la propriété si les causes disparaissent — est prouvée par
`test_banc_contagion.gd`, jamais observable en direct dans ce banc (les
deux porteurs gardent leur attache pour toujours, la charge monte sans
plafond une fois le seuil franchi, la propriété reste posée).

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

## banc_vecu_inter_colon — la culture comme contamination progressive, sans objet-groupe

`Scene/banc_vecu_inter_colon.tscn`, `scripts/banc_vecu_inter_colon.gd`, `data/banc_vecu_inter_colon.json`. Test : `scripts/test_banc_vecu_inter_colon.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_vecu_inter_colon`.

`scripts/lien_personnel_croissance.gd` (voir CARTE.md §2) reçoit ici son
PREMIER CÂBLAGE RÉEL SUR DES COLONS ORION — deux colons se perçoivent
mutuellement, en continu, et cristallisent chacun une attache au trait que
l'autre porte, sans aucune décision (`agir.gd` non câblé, même limite que
`banc_convergence_attache`).

**Montre**, en trois phases. deux colons verts
(`colon_vert_1`/`colon_vert_2`, gris au démarrage) se perçoivent en
permanence et cristallisent chacun l'attache `venere_arbres_verts` vers
t=20s (carré gris → vert plein). À t=60s, un troisième colon
(`colon_rouge_3`) apparaît hors de toute portée de perception des deux
premiers, déjà rouge plein (attache `venere_arbres_rouges` posée à la
naissance, jamais formée par vécu — une identité d'origine). Il se déplace
vers un point d'écoute équidistant des deux verts et s'y arrête. Une fois
à portée, il cristallise EN PLUS l'attache verte sans jamais perdre la
rouge : rendu bicolore, bordure rouge / intérieur vert. Les attaches se
cumulent, ne s'effacent jamais — la décristallisation n'existe pas dans le
dépôt, ce banc n'ouvre pas cette question.

**Portée limitée.** ce banc ne câble ni `agir.gd`, ni
`dominance.gd`, ni `proximite.gd`/`attaches.gd` — les attaches formées
sont PRODUITES, jamais CONSOMMÉES par une décision. Convertir ce fait en
décision (`jugement.gd` lit les attaches acquises) est un chantier
SÉPARÉ, non commencé.

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

## banc_genetique — trois profils, aucun ne domine

`Scene/banc_genetique.tscn`, `scripts/banc_genetique.gd`, `data/banc_genetique.json`. Test : `scripts/test_banc_genetique.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_genetique`.

`scripts/expression.gd` reçoit ici son PREMIER CÂBLAGE RÉEL : la preuve
que la fondation génétique dormante produit un TRADE-OFF observable, pas
un tier list.

**Montre.** AUCUN feu au démarrage — seulement trois colons en
triangle (400 unités de l'origine). Un clic gauche pose un feu à la
position cliquée (patron `banc_p1.gd:_unhandled_input`, `Objet.fabriquer`,
plusieurs clics/plusieurs feux indépendants) : Yael choisit OÙ l'observer,
loin (seul le colon à la plus grande portée de vue réagit, les autres
restent immobiles — la différence de PERCEPTION devient visible), près
d'un seul colon (seule la VITESSE différencie l'arrivée), ou entre deux
colons (lequel réagit en premier dépend des deux à la fois). Un seul gène,
`vivacite`, trois cibles à la fois (portée de vue, vitesse, coût
énergétique) — `vif` (rouge, allèles hauts) voit loin et bouge vite,
ARRIVE LE PREMIER sur un feu qu'il perçoit et COMMENCE À L'ÉTEINDRE avant
les deux autres, mais son énergie se vide le plus vite ; `endurant` (bleu,
allèles bas) voit court et bouge lentement, ARRIVE LE DERNIER, mais son
énergie dure le plus longtemps ; `moyen` (jaune, allèles nuls) reste
exactement au défaut du type — ni le premier ni le dernier, ni le plus
résistant ni le plus fragile, par construction. `Extinction.avancer`
tourne chaque tick (patron `banc_p1.gd` : agents dérivés du monde brut par
rythme, `travail_restant`/`portee_travail` résolus depuis la référence
`transformation` du feu, `data/transformations.json:defaut` partagé,
inchangé) — plusieurs colons à portée du même feu contribuent tous, la
génétique ne différencie QUE l'instant d'arrivée, jamais la vitesse
d'extinction une fois sur place. Une barre par réserve au-dessus de chaque
colon (patron `banc_p1.gd`, largeur = grandeur visuelle) — celle d'énergie
doit baisser visiblement plus vite sur le vif que sur l'endurant. Console
horodatée : perception d'un feu, arrivée sur le feu ciblé, épuisement de
la réserve d'énergie (chacun une seule fois par colon, au franchissement)
— PLUS, automatique (`BancCommun.marquer_eteints`), une ligne par feu
éteint, carré viré cendre.

**Ne montre pas.** `test_banc_genetique.gd` continue de
placer son propre feu (fixture locale au test, à portée de vue des trois
profils) pour verrouiller un ordre d'ARRIVÉE/ÉPUISEMENT déterministe — il
ne verrouille jamais un ordre de PERCEPTION distinct, qui dépend
maintenant d'OÙ Yael clique, pas d'une donnée fixe (avec un feu et des
colons statiques tant qu'ils n'ont rien perçu, si le feu est à portée de
l'endurant — la plus courte — il l'est forcément aussi des deux autres :
les trois le perçoivent alors au même tick ; c'est en cliquant AU-DELÀ de
la portée d'un ou deux colons que la divergence de perception devient
observable). Aucune régénération de réserve dans ce banc (voulu, comme
`banc_p1.gd`) : une fois épuisée, l'énergie reste à zéro pour toujours
(`docs/design.md`, « Dépense : réserve bornée à zéro »).

RISQUE DORMANT, pas corrigé (audit 2026-08-06, voir en-tête de
`banc_genetique.gd`) : comme `banc_feu`/`banc_charge` avant leur
correction, `colon` hérite `profil_saillance` sans garde locale — ce banc
n'empile pas ses colons au repos aujourd'hui, mais par ACCIDENT DE
POSITION (~692 unités entre eux, au-delà de la portée de saillance
mutuelle ~350 unités), pas par une garde. Si les positions se rapprochent
un jour, le même empilement réapparaîtra sans avertissement.

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

## banc_reproduction — deux colons, un enfant, le cycle complet fermé

`Scene/banc_reproduction.tscn`, `scripts/banc_reproduction.gd`, `data/banc_reproduction.json`. Test : `scripts/test_banc_reproduction.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_reproduction`.

PREMIÈRE FERMETURE DU CYCLE DE REPRODUCTION COMPLET : `stade.gd` →
`accouplement.gd` → `gestation.gd` → `heredite.gd` → `Objet.fabriquer`
tournent ENSEMBLE pour la première fois (CARTE.md `banc_reproduction`).

**Montre.** deux colons immobiles et proches, `parent_a`
(rouge) et `parent_b` (bleu), naissent à l'âge 0.0 et vieillissent
visiblement (`annees_par_seconde` 2.0 — un print à CHAQUE changement de
stade, pour les deux colons ET pour l'enfant une fois né). Une fois les
deux adultes (18 années simulées, 9 secondes réelles), leur exposition
mutuelle (perception seule, aucun déplacement, aucune décision — ni
`jugement.gd` ni `agir.gd` câblés ici) accumule jusqu'au seuil réel
(`data/reproduction.json:colon`, 20 secondes) : print au franchissement,
`gestation` posée sur le seul `parent_a`, qui déclare `role_gestation`
« porteur ». Elle y avance (print périodique de la progression) ; au bout de 30 secondes
réelles, un enfant plus petit et blanc apparaît à côté de lui — console :
allèles des deux parents et de l'enfant, pour chaque gène actif
(génériquement, aucun nom de gène en dur). L'enfant vieillit à son tour si
le banc continue de tourner (même print de changement de stade que ses
parents, aucun cas spécial).

CE QU'ON VOIT À L'ÉCRAN, et qui n'a coûté que deux lignes de données :
`parent_b` ne porte JAMAIS de ventre, alors que rien dans le banc ne le
distingue de `parent_a` — sa déclaration seule l'exclut (détail : `CARTE.md`,
`banc_reproduction`).

Un seul gène local, `vivacite` (`data/banc_reproduction.json:catalogue_genes`,
patron `data/banc_genetique.json`, jamais `data/genes.json`), une seule
cible (vitesse). Les deux parents sont homozygotes aux extrêmes
(`[1,1]`/`[-1,-1]`) : l'enfant naît TOUJOURS exactement à la vitesse de
base du type colon, à mi-chemin entre ses deux parents, sauf l'effet rare
d'une mutation — la différence de vitesse EST la preuve de l'héritage.

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

## banc_controle — un golem obéit, un colon décide seul

`Scene/banc_controle.tscn`, `scripts/banc_controle.gd`, `data/banc_controle.json`. Test : `scripts/test_banc_controle.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_controle`.

PREMIÈRE FONDATION du chantier « contrôle direct du joueur » (décision
Yael, 2026-08-03) : `scripts/banc_controle.gd` est le seul lecteur des
trois clés dormantes de `data/types.json:dynamique` (`controlable`,
`ordre_joueur`, `lie_au_joueur`) — aucun mécanisme du cœur n'est créé ni
touché. La différence golem/colon vit entièrement en donnée.

**Montre.** un golem (violet, `controlable : true`, ne compose
que le paquet `dynamique` — ni `percevant` ni `agent`) et un colon (rouge,
`data/types.json:colon` inchangé, `controlable` reste à son défaut neutre
`false`) dans le même monde. Un clic GAUCHE pose un ordre de déplacement
sur le golem : il s'y déplace et s'arrête, l'ordre s'efface une fois
atteint ; sans ordre, il reste immobile pour toujours, aucun repli sur une
décision autonome. Un clic DROIT pose un feu (patron `banc_genetique.gd`,
sans combustible) : le colon le perçoit et décide SEUL de s'en approcher
puis de l'éteindre (pipeline complet à quatre couches, inchangé) ; le
golem ne réagit jamais au feu — structurellement incapable de percevoir
(pas de `canaux`) ou de décider (pas d'`attaches`). Une barre d'énergie
au-dessus de chaque carré. Le golem porte les CINQ réserves de `dynamique`
comme le colon (doctrine des compartiments, `docs/design.md`) : seule son
`energie` est vive, à `surcout_action` 2.5 contre le défaut 0.7, ponctionnée
par `Depense.avancer` déjà générique, sans câblage neuf ; les quatre autres
sont éteintes — pleines, sans coût, elles ne bougent jamais.
`max_par_joueur` (3, sur le type golem) n'est pas exercé par ce banc (un
seul golem) — verrouillé isolément par des fixtures dans le test.

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

**Ne montre pas.** aucune mise en scène de
`max_par_joueur` (un seul golem existe, jamais de refus visible à
l'écran) ; aucun geste pour « relâcher » un golem une fois `lie_au_joueur`
posé (non demandé, non construit) ; aucune distinction visuelle entre un
golem qui vient de recevoir un ordre et un golem qui l'a déjà accompli, au
delà de son arrêt (pas de marqueur dédié).

## banc_champ — le joueur clique, lutte, et perd le contrôle

`Scene/banc_champ.tscn`, `scripts/banc_champ.gd`, `data/banc_champ.json`. Test : `scripts/test_banc_champ.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_champ`.

`scripts/champ.gd` (voir CARTE.md §2) reçoit ici son PREMIER câblage réel —
premier mécanisme du cœur à écrire `position` hors d'une décision d'agent.

**Montre.** un golem contrôlable (violet, RÉUTILISE
`banc_controle.gd:donner_ordre`/`avancer_controle`, jamais réécrits) part à
280 unités (7 m) d'un aimant fixe (gris foncé, masse énorme — l'immobilité
émerge du rapport de masse, aucune propriété « fixe »). Un clic gauche pose
un ordre de déplacement sur le golem, comme dans `banc_controle`. Loin
(6-4 m), le clic gagne facilement, la traction est à peine perceptible.
Vers 3 m, la traction commence à contrer le pas volontaire, l'approche
ralentit visiblement. Vers 1-2 m (point de bascule calibré à 2.5 m,
100 unités), la traction dépasse le pas volontaire : le golem est aspiré
vers l'aimant même si le joueur clique ailleurs — AUCUNE branche « si
dominé » nulle part, la domination émerge de la simple SUCCESSION
pas-volontaire-puis-déviation dans `_process()` (décision Yael, `bouger_vers`/
`bouger_selon` restent inchangés). Un `Label` affiche à chaque tick la
distance golem-aimant et la force de traction courante
(`Champ.force_paire`, lecture seule) ; la console imprime la même paire de
valeurs toutes les 0.5 s.

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

## banc_etat_effectif — un état écrase ou module une propriété, à vue

`Scene/banc_etat_effectif.tscn`, `scripts/banc_etat_effectif.gd`, `data/banc_etat_effectif.json`. Test : `scripts/test_banc_etat_effectif.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_etat_effectif`.

`scripts/etat_effectif.gd` (voir CARTE.md §2) reçoit ici son PREMIER et
SEUL câblage réel — chantier préalable au chantier feu — inflammabilité
effective, demandé pour ne pas improviser un mécanisme d'écrasement à
l'intérieur de `propagation.gd`/`objet.gd` : `deformation.gd`/
`expression.gd` composent une valeur, aucun des deux ne l'écrase.

**Montre.** QUATRE objets côte à côte (aucun pipeline de
décision, même famille que `banc_deformation.gd`), chacun avec
`proprietes.inflammabilite = 0.9` (valeur illustrative, même ordre de
grandeur que le bois de `data/materiaux.json` — AUCUN lien réel avec le
chantier feu, aucun objet ne porte de composition ni de matériau) :
`sans_etat` (témoin, jamais touché, reste à `0.9` tout du long),
`ecrase` (`mouille` seul), `module` (`huile` seul), `ecrase_et_module`
(les DEUX à la fois). Chaque carré affiche EN PERMANENCE sa valeur
EFFECTIVE (`EtatEffectif.valeur`, recalculée chaque frame, jamais
réimplémentée) via sa teinte (gris à `0.0`, orange croissant jusqu'à `1.0`
puis saturé) et un `Label` juste au-dessus (identifiant, base, états
actifs, valeur effective — le texte, lui, ne borne jamais la valeur). Une
MINUTERIE (`periode_bascule`, 4.0s) pose puis retire `etats_role` de
chaque objet SAUF le témoin, en boucle : `ecrase` et `ecrase_et_module`
chutent à `0.0` (gris) EXACTEMENT ensemble, au même instant — preuve
visuelle directe que `huile` (modulateur) n'a aucun effet tant que
`mouille` (écraseur) est actif sur `ecrase_et_module`, sans qu'il faille
lire l'en-tête du fichier pour le savoir. `module` double sa valeur
(`0.9 -> 1.8`) pendant la même fenêtre puis revient. La console imprime
une ligne à CHAQUE changement (objet, pose/retire, états avant/après,
valeur avant/après, et l'explication du gagnant depuis
`EtatEffectif.resoudre`) : l'écran montre QUE la valeur a changé, la
console montre POURQUOI.

**Portée limitée.** ce banc ne câble aucun autre mécanisme du
cœur — pas de pipeline de décision, pas de matériau, pas de composition.
Le chantier feu — inflammabilité effective, qui a motivé ce chantier,
n'est PAS câblé ici : `etat_effectif.gd` ne pose ni ne lit jamais
`inflammabilite` sur un objet fabriqué par `objet.gd`, cette brique
reprend là où elle s'était arrêtée, avec ce mécanisme désormais disponible.

## banc_inflammabilite — quatre matières, une seule cause de l'écart

`Scene/banc_inflammabilite.tscn`, `scripts/banc_inflammabilite.gd`, `data/banc_inflammabilite.json`. Test : `scripts/test_banc_inflammabilite.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_inflammabilite`.

PREMIÈRE DÉMONSTRATION RÉELLE du chantier « feu — inflammabilité effective » (voir CARTE.md §2 `objet.gd`/`propagation.gd`, `banc_inflammabilite`) :

**Montre.** quatre objets côte à côte, aucun pipeline de
décision, aucun colon — un feu central déjà allumé (jamais éteint) les
expose en permanence. MÊME `delai_propagation` de base (2.0s) et MÊME
`portee_propagation` pour les quatre : seule l'inflammabilité effective
explique l'écart. `bois_vif` (bois pur, effective `0.9`) s'enflamme le
premier, nettement avant `melange` (bois+pierre, effective `~0.18` —
au-dessus du seuil `0.1` mais ~5x plus lent). `fer_inerte` (fer pur,
effective `0.02`) et `bois_mouille` (même composition que `bois_vif`,
mais `etats_actifs : ["mouille"]` l'écrase à `0.0` via `etat_effectif.gd`)
ne s'enflamment JAMAIS — deux raisons DIFFÉRENTES, distinguées à l'écran
sans lire la console : `fer_inerte` reste BLEU fixe (sous le seuil,
aucun état actif), `bois_mouille` reste CYAN fixe (état `mouille` actif,
écrase la base). Chaque carré affiche en permanence son nom, sa
composition, son inflammabilité effective, son délai requis et son
statut (INTACT/EXPOSE/EN FEU/BLOQUE), plus une barre dont le remplissage
suit `exposition/délai_requis` — `bois_vif` et `melange` virent de
l'orange au rouge à des vitesses différentes, visiblement, avant de se
figer rouge saturé (EN FEU). Une fois EN FEU, le carré affiche le délai
qu'il a REQUIS (chiffré, jamais « jamais ») et le temps qu'il a MIS
(`temps_mis`, capturé à l'instant de l'allumage, jamais l'exposition vive
qui retombe à `0.00s` par conception de `propagation.gd`) — un objet
`BLOQUE`, lui, garde `délai_requis = « jamais »`, l'unique sens légitime
de cette valeur. La console imprime une ligne à CHAQUE CHANGEMENT DE
STATUT (jamais par frame) : objet, inflammabilité effective, exposition
(vive avant l'allumage, temps réellement mis une fois `ALLUMAGE`),
événement (`expose`/`ALLUMAGE`/`seuil non atteint`/`état '<nom>' écrase`)
— l'écran montre CE QUI se passe, la console POURQUOI.

**Portée limitée.** ce fichier cable
UNIQUEMENT ce banc — aucun mécanisme neuf, aucune extension du cœur au-delà
de `proprietes_immuables`/`delai_ignition`, déjà couverts par leurs propres
tests. `attaches.gd`/`ciblage.gd`/`materiaux.json`/`champ.gd`/
`etat_effectif.gd` non touchés — vérifié à la lecture avant d'écrire.

## banc_etat_duree — une barre qui se vide, une valeur qui remonte au même rythme

`Scene/banc_etat_duree.tscn`, `scripts/banc_etat_duree.gd`, `data/banc_etat_duree.json`. Test : `scripts/test_banc_etat_duree.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_etat_duree`.

PREMIÈRE DÉMONSTRATION RÉELLE du chantier « un état a une intensité qui décroît » (voir CARTE.md §2 `etat_duree.gd`, `banc_etat_duree`) — évolution EN PLACE du premier chantier « un état peut cesser » (même fichier, décision explicite de Yael de ne pas dupliquer le mécanisme) :

**Montre.** deux objets, même base (`inflammabilite=0.9`).
`objet_expire` porte l'état RÉEL `mouille` (data/etats.json, `duree :
6.0` — temps pour aller de `1.0` à `0.0`) : une BARRE se VIDE en continu
sur 6 secondes, juste à côté d'une valeur effective qui REMONTE au MÊME
RYTHME (`0.0 → 0.9` linéairement, jamais un saut) — le carré suit du gris
vers l'orange en continu, la barre et la valeur bougent visiblement
ensemble. À intensité épuisée (`t=6s`), `EtatDuree.avancer` retire
`mouille` de lui-même — la BARRE ET LA LIGNE « état/intensité »
DISPARAISSENT de l'écran (masquées, pas juste vidées), sans qu'aucune
ligne de `banc_etat_duree.gd` n'ait touché la propriété :
`EtatEffectif.valeur`, jamais modifié, la relit simplement telle quelle
une fois l'état absent de la liste. `objet_permanent` porte l'état RÉEL
`huile` (aucune `duree` déclarée) : barre PLEINE, carré orange saturé
(`1.8`, modulé) pour toujours — le contraste avec `objet_expire` se lit à
l'écran sans lire la console. La console imprime une ligne de POSE par
objet au démarrage (état, intensité initiale ou `permanent`), un RAPPORT
PÉRIODIQUE (toutes les 1.5s) pour `objet_expire` (état, intensité
courante, valeur effective), et la ligne de RETRAIT à l'expiration
(`valeur AVANT -> valeur APRÈS`).

**Portée limitée.** ce fichier cable
UNIQUEMENT ce banc — aucun mécanisme neuf au-delà d'`etat_duree.gd`,
aucune extension du cœur. `propagation.gd`/`objet.gd`/`champ.gd`/
`materiaux.json`/`attaches.gd`/`ciblage.gd` non touchés. Un état qui
cesse par CONDITION DU MONDE (ex. température sous un seuil) reste hors
périmètre — inchangé depuis le premier chantier, le découpage vérifié
alors tient toujours : un futur mécanisme de ce type retirerait un état
par le même geste (`etats_actifs`/`etats_intensite`), sans aucun
couplage avec ce fichier.

## banc_combustible — un gros tronc brûle longtemps, une brindille en quelques secondes

`Scene/banc_combustible.tscn`, `scripts/banc_combustible.gd`, `data/banc_combustible.json`. Test : `scripts/test_banc_combustible.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_combustible`.

**Montre.** Sept objets DÉJÀ en feu au démarrage — aucune propagation,
aucun colon : ce banc observe la CONSUMATION, jamais l'allumage. Trois
bois de volumes croissants s'éteignent dans cet ordre, parce que leur
capacité suit leur volume, calculée UNE FOIS à la fabrication et jamais
écrite à la main. Un fer de volume identique au bois moyen tient bien
moins : même volume, autre matière. Une paille part la PREMIÈRE de tous
malgré une capacité supérieure à celle du fer — sa porosité accélère sa
vitesse de combustion au point de l'emporter. Enfin deux matériaux de
démonstration à volume ET capacité RIGOUREUSEMENT égaux, densité et
porosité opposées, isolent la vitesse comme seule variable : le poreux
part tôt, le dense survit à tous les autres, `bois_grand` compris.

**Ce que ce banc a servi à corriger** : jusqu'à lui, tout objet brûlait
pendant une durée forfaitaire posée par son type, sans rapport avec ce
dont il est fait. La capacité vient désormais de la composition, via
`pouvoir_calorifique` — une propriété DÉDIÉE et INDÉPENDANTE
d'`inflammabilite`. Le premier jet empruntait `inflammabilite` faute d'un
champ dédié : confusion de deux grandeurs, corrigée, et l'emprunt ne
subsiste nulle part.

**Le geste qui vaut au-delà de ce banc** : `quantite_matiere.gd` somme une
propriété matériau PONDÉRÉE PAR VOLUME — une grandeur extensive, JAMAIS
une moyenne. Et `combustible.gd` sépare la CAPACITÉ (immuable) de la
RÉSERVE (qui décroît, toujours par `depense.gd`) sur un même canal.

**Portée volontairement limitée.** Aucun mécanisme du cœur touché au-delà
du calcul de réserve à la fabrication.

**Non vérifié à l'œil** (pas d'écran) : les sept barres doivent se vider à
des vitesses visiblement différentes, et l'ordre d'extinction doit être
celui décrit.

## banc_emission — un grand feu porte plus loin, une matière prend où l'autre ne prend pas

`Scene/banc_emission.tscn`, `scripts/banc_emission.gd`, `data/banc_emission.json`. Test : `scripts/test_banc_emission.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_emission`.

PREMIÈRE DÉMONSTRATION RÉELLE du chantier « émission et seuil » (voir CARTE.md §2 `propagation.gd`, `banc_emission`) :

**Montre.** deux feux DÉJÀ allumés dès le démarrage (aucune
propagation entre eux, aucun colon), même matériau bois, volumes `1.0`
(`petit_feu`) et `8.0` (`grand_feu`) — mêmes volumes que
`banc_combustible.json:bois_petit`/`bois_moyen`, même capacité (`0.8`/
`6.4`). Devant chacun, deux cibles à la MÊME distance (`500.0`) : une en
bois, une en fer. SEUL `grand_feu`+`bois_grand` s'enflamme : `bois_petit`
(même matière, même distance que `bois_grand`, mais un feu huit fois plus
petit) ne franchit jamais son seuil — la PORTÉE manque ; `fer_petit`/
`fer_grand` (même feu que leur voisin bois) ne le franchissent jamais non
plus — la MATIÈRE bloque. Chaque cible affiche en permanence ce qu'elle
reçoit et son seuil, en plus du statut (HORS DE PORTÉE bleu, EXPOSÉ orange
progressif, EN FEU rouge) et d'une barre d'accumulation. La console
imprime une ligne à chaque changement de statut.

Décision assumée (Yael, tranchée en conversation) : l'intensité effective
sert donc à DEUX endroits distincts — la distance à laquelle l'exposition
commence (`seuil_exposition`) et la vitesse à laquelle elle aboutit une
fois commencée (`delai_ignition`, inchangé) — l'écart entre deux matières
se MULTIPLIE, jamais ne s'additionne. Loi de décroissance choisie :
1/distance² (pas linéaire) — un feu deux fois plus grand ne porte pas deux
fois plus loin, il porte `sqrt(2)` fois plus loin ; cohérent avec les
distances de sécurité réelles (un front dix fois plus grand ne réclame pas
dix fois plus de dégagement).

## banc_vent — une odeur porte plus loin sous le vent, l'ensemble pivote avec lui

`Scene/banc_vent.tscn`, `scripts/banc_vent.gd`, `data/banc_vent.json`. Test : `scripts/test_banc_vent.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_vent`.

`scripts/vent.gd` (voir CARTE.md §2) reçoit ici son PREMIER câblage réel —
module la portée de l'odorat (`scripts/perception.gd`, `sphere_directionnelle`
seule, chantier « vent ») pour la première fois sur une scène observable.

**Montre.** un « nez » (percepteur minimal, canal odorat seul —
aucune décision, même famille que banc_deformation/banc_etat_effectif) fixe
au centre. Huit sources d'odeur en cercle à distance égale (330 unités,
`positions_en_cercle`, jamais écrites à la main) — chacune un carré qui
change de couleur selon qu'elle est captée ce tick. Le vent RÉEL
(data/vent.json, jamais surchargé) tourne (variation lente) et souffle en
rafales (force) : l'ensemble des sources capturées pivote avec lui — à
`t=0` avec les valeurs réelles du dépôt, `odeur_0`/`odeur_1`/`odeur_7` sont
capturées (les trois les plus proches du sens du vent de départ), vérifié
par lancement réel headless. Une flèche (Line2D) pointe la direction du
vent, longueur proportionnelle à sa force (échelle en donnée). Trois
valeurs affichées en permanence (CanvasLayer, patron banc_champ) : direction
(degrés), force, portée effective de l'odorat dans le sens du vent
(`Vent.facteur_directionnel`, jamais réimplémentée) et, en contraste, contre
le vent. Console : rapport périodique (intervalle en donnée) + une ligne à
CHAQUE CHANGEMENT de capture d'une source (jamais par tick).

**Portée limitée.** ce banc ne route rien par
attaches.gd/proximite.gd/jugement.gd/dominance.gd/agir.gd — le nez ne bouge
jamais, seul le vent bouge. Aucune source locale de perturbation n'est
démontrée ici (limite stricte du chantier « vent ») — la preuve qu'une
source locale module le vent dans son rayon et pas au-delà vit dans
test_vent.gd/test_perception.gd, chemin dédié, pas dans ce banc. La
généralisation du vent à l'ouïe/au feu/à la vue reste un chantier séparé,
non commencé — voir scripts/vent.gd, en-tête, « RÉUTILISATION PAR D'AUTRES
CANAUX ».

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

## banc_temperature — un objet déplacé à la main se réchauffe et refroidit selon la loi de Newton

`Scene/banc_temperature.tscn`, `scripts/banc_temperature.gd`, `data/banc_temperature.json`. Test : `scripts/test_banc_temperature.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_temperature`.

`scripts/temperature.gd` (voir CARTE.md §2) reçoit ici son PREMIER et SEUL
câblage réel — recopie le patron de `banc_vent.gd` (voir CARTE.md
`banc_temperature` pour le détail complet).

**Montre.** un feu FIXE et une source MOBILE qui traverse la
scène toute seule (mouvement sinusoïdal, fonction pure du temps, aucun
hasard) — deux simples Dictionary `{ position, rayon, temperature, force }`
construits par ce banc, jamais par `temperature.gd`. Un troisième objet,
`objet_test`, se déplace AU CLAVIER — flèches OU ZQSD, à choisir librement
— pour être approché ou éloigné des sources en direct. Sa couleur (bleu
froid → rouge chaud, interpolation bornée sur `data/banc_temperature.json :
echelle_couleur`) et un texte permanent (température de l'objet,
température locale à sa position, écart entre les deux) le rendent lisible
sans lire la console. Le ralentissement de l'écart au fil du temps (vite
d'abord, puis de plus en plus lentement à mesure qu'on approche de la
cible) est la loi de Newton rendue visible à l'œil, jamais une valeur
écrite à la main. Trace console : un rapport périodique (`intervalle_print`),
une ligne par rapport.

**Portée limitée.** ce banc ne route rien par
attaches.gd/proximite.gd/jugement.gd/dominance.gd/agir.gd — aucune
décision, seulement un déplacement direct au clavier et l'appel du
mécanisme. Aucun allumage, aucun seuil de fusion, aucun abri — hors
périmètre du chantier « température », mécanisme de base seul.

**Ne montre pas.** le chantier « colonne
thermique » étend `temperature.gd:avancer` avec `chaleur_specifique`
(inertie thermique, divise la loi de Newton) — ce banc n'a pas été
retouché, `objet_test` ne porte toujours pas cette propriété (défaut
`1.0`, comportement visuel inchangé). L'effet (pierre 790 plus lente que
fer 450 à conductivité égale) n'est démontré qu'en headless par
`test_temperature.gd`, jamais à l'écran par ce banc.

## banc_point_ignition — un même bois prend au chaud, jamais au froid

`Scene/banc_point_ignition.tscn`, `scripts/banc_point_ignition.gd`, `data/banc_point_ignition.json`. Test : `scripts/test_banc_point_ignition.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_point_ignition`.

PREMIÈRE DÉMONSTRATION RÉELLE du chantier « point_ignition » (voir CARTE.md §2 `propagation.gd`, `banc_point_ignition`) :

**Montre.** deux objets de MÊME matière (bois, `point_ignition`
`300.0`), chacun exposé par son propre foyer voisin à la MÊME distance,
avec le MÊME `delai_propagation` — seule variable expérimentale la
température locale. `cible_chaude`, dans le rayon d'une source de
température fixe (`800°`), s'enflamme normalement, exactement au délai de
base (`2.0s`, vérifié réel). `cible_froide`, hors de ce rayon (température
ambiante seule, `20°`, loin sous `300°`), N'ACCUMULE JAMAIS D'EXPOSITION —
bloquée indéfiniment, malgré une inflammabilité et une exposition
IDENTIQUES à `cible_chaude`. Chaque objet affiche en permanence son nom,
la température locale à sa position, son `point_ignition`, son statut et
une barre d'exposition/délai requis ; la teinte encode le statut (orange
→ rouge en s'approchant de l'ignition, rouge saturé une fois EN FEU, BLEU
fixe si bloqué par le froid — jamais confondu avec « en feu »). La console
imprime une ligne de pose par objet au démarrage, puis une ligne à chaque
changement de statut.

**Portée limitée.** ce banc ne fournit jamais `intensite`/
`etats` à `Propagation.avancer` — le proxy d'intensité (déjà démontré par
`banc_inflammabilite`) reste inerte ici, `delai_requis < 0.0` ne peut donc
venir QUE du nouveau gate, sans ambiguïté à diagnostiquer().

**PIÈGE DE VÉRIFICATION, à ne pas reproduire** (vaut pour tout banc) :
`add_child()` seul ne garantit PAS `_ready()` synchrone en
`--headless --script`. Un script qui boucle `_process()` juste après
`add_child()` lit un banc VIDE et produit un faux résultat vert. Appeler
`_ready()` explicitement avant la boucle.

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

## banc_transformation_produit — le bois qui brûle devient du charbon, puis de la cendre

`Scene/banc_transformation_produit.tscn`, `scripts/banc_transformation_produit.gd`, `data/banc_transformation_produit.json`. Test : `scripts/test_banc_transformation_produit.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_transformation_produit`.

PREMIÈRE DÉMONSTRATION RÉELLE du chantier « transformation produit un objet neuf » (voir CARTE.md §2 `produit.gd`/`extinction.gd`, `banc_transformation_produit`) :

**Montre.** un seul objet en bois, déjà en combustion au
démarrage (aucun clic, aucune propagation — ce banc observe la chaîne de
produits, pas l'allumage, même parti pris que `banc_combustible`). Son
carré change de couleur à chaque étape (brun → gris foncé → gris clair,
`data/banc_transformation_produit.json:couleurs`). Un texte permanent
affiche le matériau actuel, sa masse et le rendement qui l'a produit
(« origine » pour le bois). La console imprime une ligne de pose au
démarrage puis une ligne PAR TRANSITION (jamais par tick), matériau
avant/après, rendement appliqué, masse avant/après — vérifié réel : bois
(masse 1800.00) → charbon (rendement 30%, masse 540.00) → cendre
(rendement 5%, masse 27.00), les deux rendements exactement ceux
documentés dans `data/transformations.json` (pyrolyse du bois ~30%,
teneur en cendre du charbon ~5%, valeurs réalistes documentées en
`_note`).

**Ne montre pas.** aucune interactivité (le rendement
et le matériau de départ sont fixes en donnée) — un futur banc pourrait
proposer plusieurs matières de départ au clic, hors périmètre de ce
chantier.

## banc_humidite — trois matières, trois vitesses pour devenir mouillé

`Scene/banc_humidite.tscn`, `scripts/banc_humidite.gd`, `data/banc_humidite.json`. Test : `scripts/test_banc_humidite.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_humidite`.

PREMIÈRE DÉMONSTRATION RÉELLE du chantier « humidité — pose automatique de mouille » (voir CARTE.md §2 `charge.gd`, `banc_humidite`) :

**Montre.** une source d'humidité fixe (clic gauche : bascule
active/inactive) expose en permanence CINQ objets alignés — bois,
pierre, fer, `dense_mixte`, `poreux_mixte` —, mêmes seuil/portée/
décroissance de charge. `absorption_humidite` du matériau explique
l'écart de vitesse entre bois/pierre/fer : le bois (0.7) devient mouillé
en ~1.4s, la pierre (0.1) en ~10s, le fer (0.01) quasiment jamais en
pratique. `dense_mixte`/`poreux_mixte` (compositions mixtes dosées,
matériaux réels seulement — voir `data/banc_humidite.json._note`)
partagent EXACTEMENT la même `absorption_humidite` (0.05) : seule leur
porosité diverge (~0.0536 contre 0.525, ~10× d'écart) — `poreux_mixte`
doit monter visiblement plus vite que `dense_mixte` malgré une
absorption identique, preuve que la porosité seule explique l'écart pour
cette paire. Chaque objet affiche sa charge d'humidité, son absorption,
SA POROSITÉ, son état (sec/exposé/mouillé), l'intensité de mouille et
son inflammabilité EFFECTIVE (`EtatEffectif.valeur`, jamais
réimplémentée) — un objet mouillé ne brûle pas. Couper la source fait
redescendre la charge rapidement, mais un objet déjà mouillé sèche
PROGRESSIVEMENT sur les 6.0s de `data/etats.json:mouille.duree` — jamais
un retrait instantané. La console imprime une ligne par changement
d'état, incluant la porosité, jamais par frame.

**Ne montre pas.** aucune source mobile (la source est
fixe, seule sa présence bascule au clic) — un futur banc pourrait la
faire suivre une trajectoire pour montrer l'exposition varier avec la
distance, hors périmètre de ce chantier. LIMITE CONNUE, ASSUMÉE (voir
en-tête de `banc_humidite.gd`) : si la source reste active en continu,
l'intensité de mouille ne redescend jamais tout à fait à 1.0 — elle se
stabilise juste sous 1.0 (le repos de chaque tick étant immédiatement
suivi d'un pas de décroissance) — cosmétique, sans effet observable sur
l'inflammabilité effective (reste proche de 0.0).

## banc_changement_etat — du fer qui fond, bout, puis se resolidifie en refroidissant

`Scene/banc_changement_etat.tscn`, `scripts/banc_changement_etat.gd`, `data/banc_changement_etat.json`. Test : `scripts/test_banc_changement_etat.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_changement_etat`.

PREMIÈRE DÉMONSTRATION RÉELLE du chantier « colonne thermique », cases 3/4/8 du tableau Thermique (voir CARTE.md §2 `seuil_etat.gd`, `banc_changement_etat`) :

**Montre.** un fer immobile, chauffé par une source fixe à sa
propre position (distance nulle) dont la température croît
progressivement (rampe linéaire, 90s) puis s'éteint d'un coup — l'objet
retombe alors vers l'ambiante par la même loi de Newton que loin de toute
source. La couleur du carré encode la phase (gris acier solide,
orange-rouge liquide, jaune pâle quasi-transparent gazeux) plus un liseré
plus chaud dès que l'état « chaud » est actif sur la phase solide
(annonce visuelle avant la fusion). Le Label affiche en permanence la
température, la température locale, les états actifs et la malléabilité
EFFECTIVE (monte dès que « chaud » est actif, quelle que soit la phase).
La console imprime une ligne à chaque bascule, plus un rapport
périodique.

**Ne montre pas.** aucune interaction joueur (source
non contrôlable au clic, contrairement à `banc_humidite`) — la rampe et
la coupure sont entièrement pilotées par le temps écoulé, en donnée.
Cases 5/6 (`dilatation_thermique`/`soudabilite`) restent hors périmètre
de ce chantier.

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

## banc_soudure — le joueur chauffe au clic, deux fers au contact se soudent d'eux-mêmes

`Scene/banc_soudure.tscn`, `scripts/banc_soudure.gd`, `data/banc_soudure.json`. Test : `scripts/test_banc_soudure.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_soudure`.

**Écarté à l'ouverture du chantier** : le JOINT — deux objets qui
resteraient couplés. Retenu : la FUSION par composition, deux objets
disparaissent et un troisième naît.

**Montre.** Deux blocs de fer à portée de contact, un bloc de bois tout
aussi proche de l'un d'eux. Le clic gauche maintenu place une source de
chaleur qui SUIT le curseur ; relâcher la coupe, et les objets
refroidissent vers l'ambiante par la même loi de Newton que partout
ailleurs, sans cas spécial. Chauffés, les deux fers passent « chaud »,
leur charge de soudure monte et pose `pret_a_souder` sur chacun ; dès que
les deux le portent en contact, ils fusionnent SANS clic supplémentaire —
le second devient un fantôme, le premier porte la masse combinée, somme
exacte des deux. Le bois, exposé à LA MÊME source, ne se soude JAMAIS :
c'est la matière seule qui l'exclut, jamais la mise en scène ni la chaleur
reçue. Un Label fixe donne pour chaque objet, fantôme compris, son statut,
sa température, ses états, sa charge et sa masse.

**Manque structurel, pas corrigé** (`CARTE.md` §6) : `monde.gd` n'a AUCUNE
fonction de retrait. L'objet absorbé reste dans le monde pour toujours,
propriétés vidées, affiché comme fantôme.

**Convention NON tranchée**, signalée en `CARTE.md` §6 : la fusion fait
toujours survivre le PREMIER argument et absorbe le second. C'est un choix
d'API, jamais une règle de jeu sur qui devrait survivre — le plus gros ? le
plus vieux ? Ce banc ne tranche rien, il suit.

**Ne montre pas.** Aucun indice visuel ne distingue `pret_a_souder` de
`chaud` au-delà de la teinte — le Label le dit, le carré non. La source ne
chauffe qu'un point à la fois : souder trois objets d'un coup n'est pas
démontré, alors que le mécanisme le permettrait.

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée).

## banc_dilatation — un objet gonfle en chauffant, un autre rétrécit en refroidissant

`Scene/banc_dilatation.tscn`, `scripts/banc_dilatation.gd`, `data/banc_dilatation.json`. Test : `scripts/test_banc_dilatation.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_dilatation`.

PREMIÈRE DÉMONSTRATION RÉELLE de la DILATATION THERMIQUE (chantier « colonne thermique », case 5, DERNIÈRE case du tableau Thermique — `scripts/temperature.gd:avancer`, voir CARTE.md §2/`banc_dilatation`) :

**Montre.** deux objets construits DIRECTEMENT par ce banc
(température/conductivité/dilatation/volume/masse posés en donnée locale,
PAS via `Objet.fabriquer`/composition/`materiaux.json`, même discipline que
`banc_temperature.gd`). `chauffe` part à l'ambiante (20°) près d'une source
fixe à 90° et GROSSIT en chauffant ; `refroidi` part déjà à 90°, hors de
portée de toute source, et RETRÉCIT en retombant vers l'ambiante — même
coefficient, même conductivité, mouvement en miroir, même masse pour que
la comparaison ne soit jamais brouillée. Chaque carré change de taille
(aire proportionnelle au volume, racine carrée, jamais linéaire) et de
couleur (froid → chaud). Un Label au-dessus de chaque carré affiche en
permanence température/volume/densité. La console imprime une ligne par
objet à chaque changement significatif de volume, jamais à chaque frame.

COEFFICIENT DE DÉMONSTRATION, PAS LA VALEUR RÉELLE (demande explicite de
Yael : une plage de température modeste, pour que l'effet reste lisible
sans que le volume explose) : `dilatation_thermique` vaut ici `0.04`, jamais
`5.0`/`8.0`/`12.0` (bois/pierre/fer, déjà fusionnés au mécanisme depuis la
pièce 1 de ce chantier) — la formule littérale de `temperature.gd` (`dV =
dilatation_thermique * dT`, sans mise à l'échelle) rendrait le volume d'un
objet réel démesuré sur l'écart de température ici demandé. Ce banc ne
touche donc jamais `data/materiaux.json` ni `data/proprietes_immuables_
composition.json` : sa valeur de dilatation reste LOCALE, comme
`conductivite_thermique` l'est déjà dans `banc_temperature.gd`.

CONSÉQUENCE ACCEPTÉE, SIGNALÉE AVANT D'ÉCRIRE, PAS CORRIGÉE (hors périmètre
explicite de cette tâche) : `banc_changement_etat.gd`/`banc_soudure.gd`,
qui chauffent du fer réel sur de larges plages (jusqu'à ~2860°), héritent
désormais `dilatation_thermique` (12.0) depuis la pièce 1 de ce chantier —
leur volume/densité bougent donc fortement en tâche de fond sur ces deux
bancs existants si on les relance sur toute leur plage (masse inchangée,
aucun test cassé, vérifié) ; ni l'un ni l'autre banc n'est touché par ce
chantier.

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

**Ne montre pas.** aucune interaction joueur (les deux
objets suivent une trajectoire entièrement déterminée par leurs conditions
de départ, comme `banc_changement_etat`/`banc_soudure`) ; aucune démonstration
d'un troisième objet à `dilatation_thermique` nulle pour contraster
directement à l'écran (couvert par test headless seul, `_dilatation_
absente_aucun_changement_de_volume_ni_de_densite` dans `test_temperature.gd`).

## banc_pourriture — le bois pourrit, la pierre jamais, le terme est du compost

`Scene/banc_pourriture.tscn`, `scripts/banc_pourriture.gd`, `data/banc_pourriture.json`. Test : `scripts/test_banc_pourriture.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_pourriture`.

PREMIÈRE FERMETURE RÉELLE du patron « accumulation → état → dégradation →
transformation » dans ce dépôt (voir CARTE.md `banc_pourriture`) : le chantier
« corrosion », censé avoir déjà prouvé ce patron, n'a en réalité jamais
tourné (aucun `banc_corrosion.gd` sur le disque). `charge.gd` (phase 1,
déjà câblé sur banc_charge/banc_contagion/banc_humidite), `etat_duree.gd`/
`etat_effectif.gd` (phase 2, déjà câblés sur banc_etat_duree/
banc_inflammabilite/banc_humidite) et `depense.gd` + `produit.gd` (phase 3,
COMBINÉS ici pour la première fois — jamais ensemble avant ce chantier)
composent sans qu'aucun ne soit modifié.

**Montre.** une source d'humidité fixe (clic gauche : bascule
active/inactive, même geste que banc_humidite) expose en permanence un
bois et une pierre alignés, mêmes seuil/portée/décroissance de charge.
Seule `sensibilite_pourriture` (data/materiaux.json : bois `0.8`, pierre
`0.0`) explique l'écart total de destin. Le bois : monte en charge,
« exposé », puis « pourri » (data/etats.json, RÉVERSIBLE comme « mouille » —
écrase comestibilité à 0.0, module inflammabilité par 1.4, teinte qui
fonce), puis sa réserve d'intégrité (canal `depense.gd` séparé, actif
UNIQUEMENT tant que « pourri » figure dans `etats_actifs`) s'épuise et il
devient du COMPOST — teinte très sombre, masse exactement `0.35 *` sa
masse de bois, plus aucune trace de canal ni de réserve (`proprietes`
entièrement remplacées par `produit.gd:transformer`, appelé directement
par ce fichier — `depense.gd` n'a pas de branche « produire »,
contrairement à `extinction.gd`). La pierre ne bouge JAMAIS : charge à
0.0 pour toujours, jamais « pourrie », jamais transformée. Couper la
source AVANT le terme sauve l'objet — « pourri » guérit progressivement
(10.0s), la réserve d'intégrité (calibrée à 15.0, marge au-dessus de
`1.0 * 10.0`) survit si la coupure est assez précoce, même logique de
sauvetage que banc_p1 (feu éteint à temps vs consumé). Chaque objet
affiche sa charge, sa sensibilité, son état, l'intensité de « pourri »,
l'inflammabilité et la comestibilité effectives, et sa réserve
d'intégrité. La console imprime une ligne par changement d'état
(exposition, pourri posé/expiré, transformation), jamais par frame.

**Ne montre pas.** aucune interaction pour observer
directement, à l'écran, le cas « sauvetage tardif » (reserve d'intégrité
presque épuisée puis source coupée juste à temps) — seul le test headless
le prouve avec des valeurs calibrées ; le `cout_base` de la réserve
d'intégrité n'est pas modulé par l'INTENSITÉ de « pourri » (seulement sa
présence binaire dans `etats_actifs`) — un objet dont la source est coupée
très tard dans la fenêtre de guérison continue donc de perdre de
l'intégrité au même rythme qu'à pleine exposition, décision assumée pour
rester simple, signalée ici plutôt que corrigée.

## banc_corrosion — quatre métaux, trois destins : rouille destructive, patine et ternissure cosmétiques

`Scene/banc_corrosion.tscn`, `scripts/banc_corrosion.gd`, `data/banc_corrosion.json`. Test : `scripts/test_banc_corrosion.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_corrosion`.

SECONDE FERMETURE RÉELLE du patron « accumulation → état → dégradation →
transformation » (voir CARTE.md `banc_corrosion`), inauguré par `banc_pourriture.gd`
(`banc_pourriture`, ci-dessus). CORRECTION DE DOMAINE (retour Yael, vérifiée en
ligne, APRÈS une première version qui opposait fer et BOIS) : le bois ne
rouille PAS — rouiller est spécifique au fer/acier, le bois se dégrade par
un tout autre processus déjà modélisé séparément (pourriture, ci-dessus).
Ce chantier a donc été GÉNÉRALISÉ une seconde fois, au-delà du patron de
`banc_pourriture.gd` : chaque objet porte désormais SON PROPRE état cible
et SA PROPRE propriété visée, jamais un seul état/une seule propriété
partagés par tout le banc. Quatre objets, trois destins :
- FER → ROUILLE (`corrode`, module `durete`) : DESTRUCTIF, seul objet qui
 suit la Phase 3 (réserve d'intégrité, transformation en objet neuf).
- CUIVRE/BRONZE → VERT-DE-GRIS (`patine_verte`, module `reflectivite`) :
 COSMÉTIQUE — la patine est une couche PROTECTRICE, elle ne ronge pas le
 métal. Jamais de réserve d'intégrité, jamais transformés.
- ARGENT → TERNISSURE (`ternissure`, module `reflectivite` plus fort) :
 COSMÉTIQUE, même raison.

**Montre.** une source d'humidité fixe (clic gauche : bascule
active/inactive, même geste que banc_humidite/banc_pourriture) expose en
permanence quatre objets alignés — fer, cuivre, bronze, argent. Le fer
(`corrodable` `0.8`) : monte en charge, « exposé », puis « corrodé »
(RÉVERSIBLE comme « pourri »/« mouille » — module UNIQUEMENT durete par
`0.4`, inflammabilite DÉLIBÉRÉMENT inchangée), puis sa réserve d'intégrité
s'épuise et il devient de la ROUILLE — teinte brique sombre, masse
exactement `0.85 *` sa masse de fer (rendement plus haut que le compost
`0.35` : l'oxydation conserve l'essentiel de la masse), plus aucune trace
de canal ni de réserve. Cuivre (`0.5`) et bronze (`0.45`) verdissent
progressivement (reflectivité effective qui chute) et RESTENT VERTS POUR
TOUJOURS une fois la patine formée — jamais détruits, jamais transformés,
même longuement exposés. Argent (`0.55`) ternit (reflectivité effective
qui chute plus fort que la patine) — même statut cosmétique. Couper la
source AVANT le terme fait guérir chaque état progressivement (10-12s) —
pour le fer seul, la réserve d'intégrité cesse alors de décroître, même
logique de sauvetage que banc_pourriture/banc_p1. Chaque objet affiche sa
charge, sa corrodabilité, son état, l'intensité, la propriété visée
effective (durete pour le fer, reflectivite pour les trois autres) et sa
réserve d'intégrité s'il en porte une. La console imprime une ligne par
changement d'état, jamais par frame.

COSMÉTIQUE, JAMAIS DESTRUCTIF, VÉRROUILLÉ PAR TEST : un cuivre exposé sans
réserve d'intégrité pendant 40 secondes simulées développe sa patine (la
reflectivité effective chute) mais ne se transforme JAMAIS et sa masse ne
bouge jamais — vérifié en isolation ET sur le chemin réel, sur la MÊME
fenêtre que celle où le fer devient réellement de la rouille.

**Ne montre pas.** même limite que banc_pourriture —
aucune interaction pour observer directement, à l'écran, le cas
« sauvetage tardif » (seul le test headless le prouve) ; le `cout_base` de
la réserve d'intégrité du fer n'est pas modulé par l'INTENSITÉ de
« corrodé » (seulement sa présence binaire dans `etats_actifs`), même
décision assumée que pour la pourriture, signalée plutôt que corrigée.

## banc_porosite — la même porosité fait mouiller et brûler plus vite

`Scene/banc_porosite.tscn`, `scripts/banc_porosite.gd`, `data/banc_porosite.json`. Test : `scripts/test_banc_porosite.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_porosite`.

Chantier « banc_porosite — un banc transversal » (voir CARTE.md
`banc_porosite`) : montre qu'UNE SEULE propriété matériau (`porosite`)
traverse DEUX mécanismes indépendants EN MÊME TEMPS — l'humidité
(`charge.gd`, même patron que `banc_humidite`) et la combustion
(`objet.gd`/`depense.gd`, même patron que `banc_combustible`). Recopie
localement les fonctions pures dont il a besoin de ces deux bancs (jamais
un appel croisé) ; aucun mécanisme du cœur ni aucun banc existant touché.

**Montre.** deux objets côte à côte, `porosite_basse` et
`porosite_haute` (deux nouveaux matériaux de démonstration —
`absorption_humidite`/`inflammabilite`/`pouvoir_calorifique`/
`conductivite_thermique`/`densite` IDENTIQUES entre les deux, densité
COMPRISE ; contrairement à `combustible_dense_demo`/`combustible_poreux_demo`,
qui variaient densité ET porosité à la fois — seule `porosite` diverge ici,
`0.9` contre `0.05`), déjà EN FEU dès le démarrage (comme banc_combustible
— aucune propagation, aucun colon) ET exposés en permanence à la MÊME
source d'humidité fixe (clic gauche : bascule active/inactive, MÊME GESTE
que banc_humidite/banc_pourriture/banc_corrosion — retour Yael après
première fermeture), à distance identique des deux objets. `porosite_haute`
devient mouillée avant `porosite_basse` (poids receveur d'humidité plus
haut) ET épuise sa réserve de combustible avant `porosite_basse` (`cout_base`
effectif plus haut) — LA MÊME porosité cause les deux écarts, en parallèle.
Chaque objet affiche en continu sa porosité, son état mouillé ou non, sa
charge d'humidité, ce qu'il reste de sa réserve de combustible (absolu et
proportion) et sa température (chaque objet EN FEU rayonne pour l'autre,
via `temperature.gd` — mécanisme non différenciant ici puisque
`conductivite_thermique`/`densite` sont identiques entre les deux, présent
pour l'affichage, pas la démonstration). La console imprime une phrase par
changement significatif, NOMMANT la porosité de l'objet à chaque fois.

Vérifié par lancement réel (`--headless --script scripts/test_banc_porosite.gd`
puis `scripts/lanceur.gd`, 85 tests) : VERT. Simulation tick par tick
réelle (chemin réel, `data/banc_porosite.json` lu sur disque) : `porosite_haute`
devient mouillée ET s'éteint STRICTEMENT avant `porosite_basse` ; à
porosité strictement égale (deux matériaux fictifs), les deux fronts
évoluent EXACTEMENT identiquement tick par tick — preuve que seule la
porosité explique l'écart mesuré sur les matériaux réels ; couper la
source (clic) fait redescendre la charge des deux objets (`taux_decroissance`),
un objet déjà mouillé sèche PROGRESSIVEMENT sur 6.0s — jamais un retrait
instantané, même geste que banc_humidite. Non vérifié VISUELLEMENT par
Claude (pas d'écran) : à confirmer par Yael — les deux carrés doivent être
visibles côte à côte, labels lisibles (porosité/mouillé/charge/réserve/
température), `porosite_haute` doit virer au bleu (mouillée) et
s'assombrir jusqu'à l'extinction NETTEMENT avant `porosite_basse` ; le
clic gauche doit basculer la source (marqueur bleu ↔ gris, label
ACTIVE/INACTIVE), la combustion continue de tourner sans interruption
(le feu n'est jamais lié à la source d'eau).

**Ne montre pas.** aucune source d'humidité mobile — un
futur banc pourrait la faire suivre une trajectoire pour montrer
l'exposition varier avec la distance, hors périmètre de ce chantier ; pas
de troisième axe (ex. corrosion) sur les mêmes deux objets.

## banc_permeabilite — un objet laisse passer l'eau, l'autre la retient

`Scene/banc_permeabilite.tscn`, `scripts/banc_permeabilite.gd`, `data/banc_permeabilite.json`. Test : `scripts/test_banc_permeabilite.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_permeabilite`.

Chantier « permeabilite » (voir CARTE.md `banc_permeabilite`) : `permeabilite`
module la RÉTENTION d'eau, jamais l'absorption — à la différence de
`banc_humidite` (`absorption_humidite`/`porosite` modulent la MONTÉE),
ici les deux objets montent à l'identique et seule leur DÉCROISSANCE
(`taux_decroissance` du canal `humidite`, `charge.gd`) diverge. Aucun
mécanisme du cœur ni aucun banc existant touché.

**Montre.** deux objets, `permeable` (bois, permeabilite
`0.5`) et `impermeable` (fer, permeabilite `0.0`), exposés à la même
source d'humidité fixe (clic gauche : bascule active/inactive, même geste
que `banc_humidite`). Tant que la source est active, les deux montent
STRICTEMENT à la même vitesse (même cause, même poids — la permeabilite
n'intervient jamais ici). Une fois la source coupée, `permeable` sèche
vite (`taux_decroissance` 1.05) et repasse sous le seuil en quelques
secondes ; `impermeable` sèche beaucoup plus lentement (`taux_decroissance`
0.05, plancher seul) et reste marqué « saturé » bien plus longtemps —
l'eau reste piégée, jamais pour toujours (un plancher de décroissance
strictement positif garantit qu'il finit par sécher même à permeabilite
nulle). Chaque objet affiche sa permeabilite, son taux_decroissance, sa
charge/seuil et son état (sec/saturé). Console : une phrase par bascule de
l'état saturé, nommant permeabilite et taux_decroissance.

**Ne montre pas.** aucune source d'humidité mobile (même
limite que `banc_porosite`) ; aucun troisième objet à permeabilite
intermédiaire (pierre, `0.05`) pour montrer un gradient plutôt qu'une
simple opposition binaire — hors périmètre de ce chantier.

## banc_solubilite — le sel fond dans l'eau, la pierre non

`Scene/banc_solubilite.tscn`, `scripts/banc_solubilite.gd`, `data/banc_solubilite.json`. Test : `scripts/test_banc_solubilite.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_solubilite`.

Chantier « solubilite » (voir CARTE.md `banc_solubilite`) : un objet soluble
exposé à l'humidité perd de la masse progressivement jusqu'à disparaître.
TROISIÈME fermeture réelle du patron « accumulation → état → dégradation →
transformation », après `banc_pourriture.gd`/`banc_corrosion.gd` — mais la
Phase 1 (accumulation → « mouillé ») recopie cette fois EXACTEMENT
`banc_humidite.gd` (état PARTAGÉ `mouille`, jamais un nouvel état inventé)
plutôt que de poser un état dédié au chantier. Seule différence assumée
avec le patron pourriture/corrosion : le `cout_base` de la réserve
d'intégrité n'est pas une constante fixe, il est PROPORTIONNEL à
`solubilite` (`facteur_dissolution * solubilite`) — c'est la vitesse de
dissolution elle-même que ce chantier voulait montrer varier avec la
matière, pas seulement le fait de se dissoudre ou non. Aucun mécanisme du
cœur ni banc existant touché.

**Montre.** une source d'humidité fixe (clic gauche : bascule
active/inactive, même geste que banc_humidite/banc_pourriture/
banc_corrosion/banc_porosite) expose en permanence un `sel` et une
`pierre` alignés. Le sel (`absorption_humidite` `0.6`, `solubilite` `0.9`)
mouille vite puis, une fois mouillé, sa réserve d'intégrité s'effondre vite
— en quelques secondes il devient un RÉSIDU DISSOUS (teinte très claire/
délavée, masse quasi nulle, rendement `0.02` — presque toute la masse part
en solution). La pierre (`absorption_humidite` `0.1`, `solubilite` `0.02`)
mouille lentement et, même mouillée, sa réserve décroît si lentement (plus
de 200s pour s'épuiser) qu'elle reste intacte sur toute la fenêtre
d'observation — jamais en pratique, même convention que « le fer ne
mouille jamais en pratique » dans banc_humidite. Chaque objet affiche son
absorption, sa solubilité, sa charge/seuil, son état (sec/exposé/mouillé)
et sa réserve d'intégrité. Couper la source avant dissolution complète
fait sécher « mouillé » progressivement (6.0s) — la réserve d'intégrité
cesse alors de décroître, l'objet est sauvé.

**Ne montre pas.** aucune interaction pour observer
directement, à l'écran, le cas « sauvetage tardif » (seul le test headless
le prouve) ; le `cout_base` de la réserve d'intégrité n'est pas modulé par
l'INTENSITÉ de « mouillé » (seulement sa présence binaire dans
`etats_actifs`), même décision assumée que pour pourriture/corrosion,
signalée plutôt que corrigée.

## banc_conduction — le courant traverse le fer, s'arrête net au bois

`Scene/banc_conduction.tscn`, `scripts/banc_conduction.gd`, `data/banc_conduction.json`. Test : `scripts/test_banc_conduction.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_conduction`.

Chantier « conduction électrique — courant continu » (voir CARTE.md
`banc_conduction`) : un objet conducteur relié à une source de courant
transmet le courant à ses voisins conducteurs tant que le contact dure, un
agent en contact avec un objet sous tension prend des dégâts continus
proportionnels à la conductivité. Compose deux patrons déjà fermés, jamais
réécrits — `flux.gd` (transfert continu, déjà câblé sur `banc_animal.gd`)
et `charge.gd` → `etat_duree.gd` → `depense.gd` (patron « accumulation →
état → dégât », déjà fermé trois fois par pourriture/corrosion/solubilité).
Aucun mécanisme du cœur touché.

**Montre.** un clic gauche bascule TOUS les générateurs actifs/
inactifs à la fois. Trois rangées : fer-bois-fer (le second fer ne
s'énergise jamais, bloqué net au bois — aucune atténuation, une simple
absence de propagation au-delà de l'isolant), fer-fer-fer (les trois
s'énergisent en chaîne — remplacer le bois par du fer fait traverser les
trois), et une paire fer sec/fer mouillé (chacun sa propre source, même
distance) dont la réserve « courant » grandit EXACTEMENT dix fois plus
vite pour le mouillé — première consommation réelle de la fondation
dormante « `mouille` module `conductivite_electrique` ×10.0 » (chantier
« fondations dormantes friction et conductivite_electrique sous
humidité »). Un agent posé près du fer central de la rangée qui traverse
prend des dégâts continus (réserve `integrite` qui décroît) tant qu'elle
reste sous tension ; couper les générateurs arrête les dégâts,
« electrocute » s'estompe progressivement (`etat_duree.gd`, durée 1.5s),
jamais un retrait instantané. Chaque objet affiche sa conductivité
effective, s'il conduit, s'il est sous tension et sa réserve de courant ;
l'agent affiche s'il est électrocuté, sa charge/seuil et sa réserve
d'intégrité. La console imprime une phrase par changement significatif
(bascule de générateur, objet énergisé/hors tension, agent électrocuté/
guéri).

**Ce qui a été ajouté.** `facteur_conductivite_ base` (1e-6, donnée) compense l'écart d'échelle entre les unités réelles de `materiaux.json` (S/m, 1e-15 à 1e7) et une réserve/charge lisible en quelques secondes — même geste que la masse minuscule de `leger_golem` dans `banc_champ.json`.

**Ne montre pas.** aucune interaction pour faire
basculer un objet entre bois et fer en direct (les deux rangées bloquée/
traversée sont montrées côte à côte plutôt que par un remplacement au
clic) — choix délibéré pour rester dans le patron « clic bascule
uniquement les générateurs » déjà établi par les autres bancs d'humidité,
signalé plutôt que corrigé ; aucun troisième matériau intermédiaire
(pierre, conductivité `1e-9`, également isolante en pratique) pour montrer
un gradient plutôt qu'une simple opposition binaire fer/bois.

## banc_foudre — un éclair choisit sa cible, frappe une fois, chauffe une fois

`Scene/banc_foudre.tscn`, `scripts/banc_foudre.gd`, `data/banc_foudre.json`. Test : `scripts/test_banc_foudre.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_foudre`.

Chantier « foudre — événement ponctuel » (voir CARTE.md `banc_foudre`) : PREMIÈRE DÉMONSTRATION
RÉELLE de `scripts/frappe.gd`, cinquième nature d'effet du moteur
(événement ponctuel par sélection, voir `docs/design.md` « Direction
majeure ») — un mécanisme qui sélectionne UNE cible parmi plusieurs et lui
applique un effet immédiat et permanent, sans accumulation préalable,
n'existait nulle part avant ce chantier.

**Montre.** quatre objets fixes, vrais fer/bois du catalogue
partagé — `fer_haut` (conducteur, en hauteur, doit être frappé),
`bois_bas` (ni l'un ni l'autre, jamais frappé), `fer_bas` (conducteur
seul, moins prioritaire que `fer_haut`), `bois_haut` (haut seul, prouve
que la hauteur SEULE ne bat jamais un objet conducteur — les poids des
critères sont calibrés pour ça, voir `data/banc_foudre.json._note`). Un
clic gauche déclenche UN SEUL éclair : `Frappe.selectionner` choisit la
cible au score le plus haut parmi les objets FRAPPABLES (pas déjà
détruits) à portée d'un épicentre fixe ; `Frappe.frapper` applique un
dégât instantané sur sa réserve `integrite` (le dégât détruit sa cible
d'un coup, `degats == reserve` de départ) ; une source de chaleur extrême
est appliquée à `Temperature.avancer` pour UN SEUL appel, à la position de
l'impact — jamais reconstruite au tick suivant. Le carré frappé vire
visiblement vers le rouge (dégâts) et sa température bondit, puis
redescend tick après tick vers l'ambiante (loi de Newton, `Temperature.
avancer` tourne en continu avec une liste de sources vide en dehors des
frappes). Un second clic déclenche un second éclair indépendant — un
objet déjà détruit n'est plus jamais candidat, le prochain éclair frappe
la cible frappable au score le plus haut restante. La console imprime, à
chaque frappe, qui a été frappé, le détail de chaque critère de score
(valeur, poids, contribution), les dégâts infligés et la température
avant/après.

**Ne montre pas.** aucune distinction visuelle entre
« température qui monte » et « dégâts » au-delà du texte du `Label` (la
couleur du carré n'encode que les dégâts, jamais la température) ; aucun
retour visuel sur l'épicentre ou le rayon de frappe (invisibles à
l'écran, seule leur conséquence — qui est frappé — se voit) ; lumière/son
de l'impact restent purement absents (cosmétique non tranché).

## banc_chaleur_emise — le bois qui brûle réchauffe plus vite que le fer

`Scene/banc_chaleur_emise.tscn`, `scripts/banc_chaleur_emise.gd`, `data/banc_chaleur_emise.json`. Test : `scripts/test_banc_chaleur_emise.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_chaleur_emise`.

Chantier « chaleur_emise — un feu émet de la chaleur » (voir CARTE.md
`banc_chaleur_emise`
§2/§5/§6) : PREMIÈRE DÉMONSTRATION RÉELLE qu'un objet qui brûle émet de la
chaleur en continu — le patron `temperature.gd` (sources locales
construites et possédées entièrement par l'appelant, déjà démontré par
`banc_temperature.gd` pour une source mobile) couvre aussi le cas d'une
source stable tant qu'un état persiste, sans qu'une seule ligne du
mécanisme ne change.

Aucun mécanisme du cœur touché : `temperature.gd`/`depense.gd`/
`combustible.gd`/`objet.gd` restent inchangés. Ce banc compose trois
patrons déjà fermés — `Objet.fabriquer` (vrais bois/fer/pierre, composant
`objet_physique` pour `temperature`, plus une réserve `combustible` réelle
pour les deux objets qui brûlent), `Temperature.avancer` (appelé chaque
tick avec les sources construites par `sources_chaleur`, fonction PROPRE
à ce fichier), `Depense.avancer` (détecte l'épuisement de la réserve
`combustible` et retire `brule`, catalogue `seuils_combustible.json :
epuisement` partagé, inchangé).

**Montre.** quatre objets fixes — `bois_brule`/`fer_brule`
déjà allumés au démarrage, `froid_pres_bois`/`froid_pres_fer` froids
(ambiante, jamais allumés), chacun à la MÊME distance (`150.0`) de son
propre foyer pour une comparaison propre. `froid_pres_bois` se réchauffe
strictement plus vite que `froid_pres_fer` (chaleur_emise du bois, `0.8`,
supérieure à celle du fer, `0.3`, à distance et rayon identiques). Chaque
foyer s'éteint après ~20-23s (réserve `combustible` épuisée) — la source
de chaleur correspondante disparaît au tick suivant, la console imprime
la ligne d'extinction. Un Label par objet affiche en permanence
`chaleur_emise`, `temperature`, et l'état `brule`/`eteint`.

**Ne montre pas.** aucune barre de réserve `combustible`
affichée (contrairement à `banc_combustible.gd`) — l'extinction ne se lit
qu'au changement de couleur/texte et à la ligne console ; aucune
distinction visuelle entre les deux foyers eux-mêmes au-delà du texte.

## banc_fracture — un objet fragile casse, un objet résistant se déforme

`Scene/banc_fracture.tscn`, `scripts/banc_fracture.gd`, `data/banc_fracture.json`. Test : `scripts/test_banc_fracture.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_fracture`.

Chantier « resistance_impact — fracture par choc » (voir CARTE.md
`banc_fracture`) :
PREMIÈRE DÉMONSTRATION RÉELLE que `resistance_impact`/`fragilite`
(dormantes dans `data/materiaux.json` depuis leur création) tranchent un
choc — un objet frappé au-delà de sa résistance se fracture, et sa
fragilité décide s'il se réduit en éclats ou se contente de se déformer.

Aucun mécanisme du cœur touché : `frappe.gd`/`seuil_etat.gd`/
`etat_effectif.gd`/`produit.gd`/`objet.gd` restent inchangés. Ce banc
compose trois patrons déjà fermés — `Frappe.selectionner`/`frapper` (QUI
est frappé et le dégât instantané, mais `position_source` est ici le
CLIC, jamais une position fixe en donnée comme `banc_foudre.gd` — voir
CARTE.md `banc_fracture` pour le détail de cette différence), `SeuilEtat.
avancer` (pose `fracture` au franchissement de `degats_impact_cumules`,
grandeur que le câblage écrit lui-même après chaque `Frappe.frapper` —
`frappe.gd` ne monte jamais aucune propriété), `Produit.transformer`
(appelé PAR CE BANC, jamais par `seuil_etat.gd`, uniquement si l'objet
fracturé porte une fragilité au-dessus d'un seuil local au banc).

**Montre.** un objet en fer et un objet en pierre côte à
côte. Un clic près de l'un des deux déclenche un seul choc dessus — un
rayon de frappe petit fait office de visée, cliquer près du fer ne met
jamais la pierre à portée. CHAQUE choc (pas seulement une fracture) fait
flasher brièvement le carré touché en blanc et secoue la caméra (retour
Yael, RENFORCÉ, voir plus bas) — l'instant de l'impact reste visible,
pas seulement l'état après coup. La pierre (`resistance_impact` 2.0)
fracture dès le premier coup (`degats` 3.0) et se transforme aussitôt :
son carré disparaît, remplacé par une grappe de cinq petits éclats
dispersés d'une teinte sable claire, nettement contrastée avec le gris
intact et le rouge de fracture (masse totale réduite à 90% de la pierre
d'origine). Le fer (`resistance_impact` 8.0) encaisse deux coups sans
rien montrer d'autre qu'une réserve `integrite` qui baisse (teinte qui
vire à l'orange), puis fracture au troisième coup (cumul 9.0) — mais sa
fragilité (0.2) reste sous le seuil de production d'éclats : son carré
entier vire au rouge sombre, il reste fer, jamais transformé, jamais
réduit en morceaux, seulement `durete`/`resistance_compression`
effectives réduites (×0.3, tracées en console). Label sur chaque objet
intact : `resistance_impact`/`fragilite`/`degats_impact_cumules`/état.

Testé par `scripts/test_banc_fracture.gd` : sélection/cumul de dégâts sur
plusieurs coups, aucune fracture sans avoir été frappé ni sous le seuil,
bascule au franchissement sans jamais rebasculer (irréversible), fragilité
haute produit une transformation, fragilité basse laisse déformé même
avec une transformation valide en donnée, fabrication réelle fusionne les
trois propriétés depuis `data/materiaux.json`, chemin réel complet (la
pierre casse et produit des éclats, le fer résiste à deux coups puis
fracture au troisième sans jamais se transformer, masse inchangée),
données réelles cohérentes, grappe d'éclats et secousse de caméra
DÉTERMINISTES (deux appels aux mêmes arguments rendent exactement le même
résultat, aucun hasard), le flash domine tout autre état visuel (fracture,
transformé, ou simple dégât). 94 tests VERT. Non vérifié VISUELLEMENT par
Claude (pas d'écran, pas de souris) : à confirmer par Yael — les deux
carrés doivent être visibles dès l'ouverture ; un clic près de la pierre
doit produire un flash blanc bref puis faire apparaître la grappe
d'éclats sable dès le premier coup ; trois clics près du fer doivent
chacun produire un flash/une secousse, le troisième doit faire virer le
carré au rouge sombre (`fracture`) sans jamais changer sa forme ni se
transformer — À CONFIRMER SPÉCIFIQUEMENT : ce renfort est-il maintenant
suffisamment visible, ou faut-il aller plus loin (amplitude de secousse,
durée de flash, taille de la grappe) ?

**Ne montre pas.** `durete`/`resistance_compression`
effectives réduites par `fracture` ne sont tracées qu'en console
(`_ligne_fracture`), jamais affichées au label ou par une teinte dédiée
sur le carré du fer lui-même — seul le passage à la couleur « fracture »
(rouge sombre) est visible à l'écran, pas l'ampleur de la dégradation.

## banc_lumiere — le cycle jour/nuit change l'intensité et la couleur, deux sources se mélangent

`Scene/banc_lumiere.tscn`, `scripts/banc_lumiere.gd`, `data/banc_lumiere.json`. Test : `scripts/test_banc_lumiere.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_lumiere`.

`scripts/lumiere.gd` (voir CARTE.md §2) reçoit ici son PREMIER câblage
réel — chantier « lumière ambiante — scalaire ambiant avec température de
couleur », TROISIÈME scalaire/vecteur ambiant après `vent.gd`/
`temperature.gd`, PREMIER à porter deux composantes couplées (intensité ET
couleur).

Ce qu'il doit montrer, cinq points du chantier : le cycle jour/nuit
(l'heure simulée avance, mappée sur des secondes réelles — `data/
banc_lumiere.json:cycle_reel` —, l'intensité ambiante monte/descend et la
couleur passe orange aube → blanc-jaune midi → orange crépuscule → bleu
nuit ; le lecteur `temoin_ambiant`, loin de toute source, montre le cycle
PUR, le fond de l'écran le suit) ; une torche fixe orange chaude (le
lecteur `pres_torche`, dans son rayon, reste orange et lumineux la nuit,
se fond dans le jour) ; une lanterne MOBILE (mouvement sinusoïdal, fonction
pure du temps) suivie par deux lecteurs (`porteur_lanterne`, recalculé
chaque tick à sa position exacte ; `passage_lanterne`, fixe sur sa
trajectoire, capte le passage puis le perd) ; deux sources de couleurs
différentes qui se recouvrent (torche orange/cristal bleu) — le lecteur
`zone_melange`, dans le recouvrement, affiche une couleur STRICTEMENT
ENTRE les deux, jamais écrasée par l'une ; un Label par lecteur affiche en
permanence `intensite_lumiere`/`couleur_lumiere`. Trace console : un
rapport périodique (heure, ambiante, valeurs de chaque lecteur) plus une
ligne à chaque changement de ZONE discrète (`jour`/`penombre`/`nuit`,
seuils en donnée) — jamais l'épsilon fin du retour d'`avancer()`, qui
aurait loggé à quasiment chaque frame pendant que l'ambiante dérive en
continu.

**Ne montre pas.** aucune interaction joueur (source,
heure et latitude entièrement pilotées par la donnée et le temps écoulé) ;
aucune démonstration de l'occlusion (`opacite` fusionnée mais lue par
aucun mécanisme, hors périmètre explicite de ce chantier).

## banc_reflectivite — un objet réfléchissant renvoie la lumière, un objet sombre absorbe la chaleur

`Scene/banc_reflectivite.tscn`, `scripts/banc_reflectivite.gd`, `data/banc_reflectivite.json`. Test : `scripts/test_banc_reflectivite.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_reflectivite`.

Chantier « réflectivité sous lumière ». `scripts/lumiere.gd` (voir CARTE.md
§2) reçoit ici son PREMIER usage comme SOURCE SECONDAIRE (jusqu'ici,
`banc_lumiere.gd` ne l'utilisait qu'en simple lecteur) — un objet
réfléchissant devient lui-même une source posée à sa propre position, dont
le produit `intensite * force` vaut exactement `reflectivite effective *
lumiere_locale reçue`, sans réimplémenter la multiplication que
`lumiere.gd` fait déjà en interne. `scripts/temperature.gd` y compose une
DEUXIÈME fois le patron « source par objet » de `banc_chaleur_emise.gd`
(rayon minuscule, force propre à chacun) pour l'absorption plutôt que
l'émission.

DÉRIVE SIGNALÉE ET TRANCHÉE PAR YAEL avant écriture : la consigne d'origine
demandait « fer corrodé avec ternissure » — impossible tel quel, `ternissure`
n'existe que sur l'argent dans tout le dépôt (`scripts/banc_corrosion.gd`,
`data/etats.json`), le fer ne suit que `corrode` (module `durete`, jamais
`reflectivite`). Remplacé par CUIVRE + `patine_verte` (même famille de
modulation que `ternissure`, x0.3) — aucune donnée ni règle de contenu déjà
tranchée n'est rouverte.

**Montre.** une lampe fixe neutre (source primaire) éclaire
trois objets à ÉGALE distance d'elle (argent/bois/cuivre patiné — seule leur
composition diverge, isolant la réflectivité comme unique variable).
`cuivre_patine_0` porte `patine_verte` POSÉ STATIQUEMENT dès la fabrication
(jamais via `charge.gd`/`etat_duree.gd` — ce banc montre une réflectivité
MODULÉE, pas une corrosion qui progresse dans le temps comme
`banc_corrosion.gd`) : réflectivité effective ~0.195 contre une base de
0.65, affichées côte à côte sur son Label. Chaque objet devient une source
secondaire ; un témoin par objet, à égale distance de lui et hors de portée
de la lampe et des deux autres objets, lit ce reflet seul — le témoin près
de l'argent (réflectivité 0.95) reçoit nettement plus de lumière que celui
près du bois (0.15) ou du cuivre patiné (0.195). En parallèle,
`chaleur_absorbee = absorption_sombre * (1 - reflectivite) * lumiere_locale`
pilote une source radiante propre à chaque objet : sous la même lampe,
l'argent reste thermiquement quasi inerte pendant que le bois et le cuivre
patiné chauffent visiblement. Conductivité thermique et chaleur spécifique
sont des CONSTANTES LOCALES PARTAGÉES par les trois objets (`data/
banc_reflectivite.json._note`) — argent/cuivre n'ont pas de fiche thermique
réelle dans `data/materiaux.json` (fiches MINIMALES), les lire aurait
laissé l'écart venir d'une donnée manquante plutôt que de la réflectivité.
Un Label par objet (réflectivité base ET effective, `lumiere_locale`,
`chaleur_absorbee`, température) et par témoin (`intensite_lumiere`/
`couleur_lumiere`), tous les deux mis à jour EN CONTINU (`_process()` →
`_rafraichir_tout`, jamais une seule fois au démarrage). Trace console :
une ligne de pose par objet au démarrage, un rapport périodique.

**Ne montre pas.** aucun retour visuel sur la
température (seul le Label la chiffre, aucune teinte ne la code) ; aucune
comparaison directe cuivre intact / cuivre patiné à l'écran (la réduction
se lit sur le Label du seul cuivre patiné, base vs effective, jamais par
un second objet cuivre neuf côte à côte) ; la source mobile n'est pas
togglable (toujours active, seule la lampe fixe l'est).

## banc_photodegradation — le soleil casse la matière organique, jamais dans le noir

`Scene/banc_photodegradation.tscn`, `scripts/banc_photodegradation.gd`, `data/banc_photodegradation.json`. Test : `scripts/test_banc_photodegradation.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_photodegradation`.

Chantier « photodégradation — le soleil dégrade la matière organique
morte ». DEUXIÈME câblage de `scripts/lumiere.gd` avec
`scripts/depense.gd`, DÉLIBÉRÉMENT ISOLÉ d'un seul effet : pas
d'humidité, pas de feu, pas de canal `pourriture` de `charge.gd`.
DOCTRINE TRANCHÉE (décision Yael, session ultérieure) : un premier banc
concurrent, `scripts/banc_uv_degradation.gd`, câblait l'UV comme un
RALENTISSEUR de la pourriture — physique fausse, la stérilisation UV ne
domine pas la décomposition en environnement naturel. Tranché en faveur
de ce chantier-ci (accélération seule) ; `banc_uv_degradation.gd` et ses
fichiers associés ont été retirés du dépôt.

**Montre.** trois objets. `bois_soleil` (bois,
`biodegradabilite` `0.9`) et `pierre_soleil` (pierre, `biodegradabilite`
`0.0`) reçoivent EXACTEMENT la même `lumiere_locale` (même distance à la
source `soleil`) : seul `bois_soleil` perd de l'intégrité, `pierre_soleil`
n'en perd jamais — preuve que `biodegradabilite` `0.0` neutralise l'effet
quelle que soit l'exposition. `bois_noir`, même matériau que
`bois_soleil`, placé hors de portée du soleil EN PERMANENCE : ne perd
jamais d'intégrité non plus, pour une raison DIFFÉRENTE (position, pas
biodégradabilité) — le banc distingue donc VISUELLEMENT deux causes de
« rien ne se passe ». Un clic gauche n'importe où bascule le soleil
ACTIF/COUPÉ (carré jaune/gris au-dessus des objets) : soleil coupé,
`lumiere_locale` retombe à l'ambiante partout et la dégradation de
`bois_soleil` s'arrête net, même si elle était déjà entamée — elle ne
reprend que si le soleil est réactivé. Un Label par objet
(biodégradabilité, `lumiere_locale`, intégrité/capacité) mis à jour en
continu ; une barre d'intégrité par objet. Trace console : une ligne au
changement d'état du soleil, un rapport périodique par objet.

**Ne montre pas.** aucune interaction sur la position
des objets ni sur l'intensité du soleil (seule la bascule actif/coupé est
jouable) ; ce banc ne compose jamais d'effet de ralentissement de la
pourriture sous UV (voir DOCTRINE TRANCHÉE ci-dessus — écarté) ; la
synergie entre photodégradation et biodégradation microbienne (voir
`docs/design.md`, « Les propriétés matériau comme nœuds de connexion
transversaux ») reste NON EXPLORÉE.

## banc_son — un colon entend selon l'intensité ET la fréquence, jamais selon le nom de ce qui sonne

`Scene/banc_son.tscn`, `scripts/banc_son.gd`, `data/banc_son.json`. Test : `scripts/test_banc_son.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_son`.

SEUL banc de ce dépôt à ce jour dont le chantier touche un mécanisme du
CŒUR au-delà de son propre fichier : `scripts/perception.gd` active le
champ `seuil` de `canaux_config.ouie`, dormant depuis PHASE 3.5 — détail
complet (formule, portée du changement, non-régression) : `CARTE.md`,
entrée `perception.gd`, et `CARTE.md` `banc_son`.

**Montre.** deux grappes spatiales éloignées (aucune
contamination croisée), chacune un colon entouré de quatre sources
sonores réelles à distance identique (fer/bois/pierre, `data/
materiaux.json`) — `source_forte` (fer, `son_emis` `0.5`), `source_
moyenne` (bois, `0.1`), `source_faible` (pierre, `0.05`), `source_
ultrason` (fer, `0.5` — MÊME intensité que `source_forte`, seule la
fréquence diverge). `colon_humain` et `colon_chien` partagent le MÊME
seuil (`0.04`) : les deux entendent `source_forte`/`source_moyenne`,
aucun des deux n'entend `source_faible` (intensité atténuée par la
distance sous le seuil) — la preuve que le seuil seul ne suffit pas à
motiver l'ultrason : `colon_humain` (plage `20-20000` Hz) ne l'entend
jamais, `colon_chien` (plage `20-45000` Hz) l'entend, MALGRÉ une
intensité identique à `source_forte` — deux filtres indépendants,
observables séparément. Un label par source (`son_emis`, `frequence`) ;
un label par colon (`seuil`, plage de fréquence, liste des sons
actuellement entendus). Trace console : une ligne par colon au
CHANGEMENT de ce qu'il entend seulement (jamais chaque frame), plus un
rapport périodique par source. Scène statique — aucune interaction
joueur, aucun mouvement : la démonstration tourne seule.

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

**Ne montre pas.** aucune interaction joueur ; aucun
objet positionné entre source et colon pour exercer visuellement
l'occlusion (chantier « occlusion », session ultérieure — `data/
canaux.json:ouie` porte désormais `propriete_obstacle`/`largeur_obstacle`,
`propagation_obstacles` n'est plus une sphère pure au niveau du mécanisme,
seul ce banc ne positionne aucun obstacle réel pour le montrer) ; le label
du colon ne distingue pas visuellement LEQUEL des filtres (seuil, fréquence
ou occlusion) a retiré une source ignorée.

## banc_fracture_sonore — un son intense casse le verre, pas le fer

`Scene/banc_fracture_sonore.tscn`, `scripts/banc_fracture_sonore.gd`, `data/banc_fracture_sonore.json`. Test : `scripts/test_banc_fracture_sonore.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_fracture_sonore`.

Même patron que banc_fracture (choc mécanique) mais un déclencheur
différent : `intensite_sonore_cumulee` (accumulée en continu, avec delta,
tant qu'une source sonore reste active) plutôt que `degats_impact_cumules`
(accumulée par coup instantané). Les deux grandeurs comparent contre la
même `resistance_impact` et posent le même état `fracture` (`data/
seuils_etat.json:fracture_sonore`, deuxième entrée visant ce nom, jamais
une collision — les deux grandeurs ne sont jamais présentes sur le même
objet). `frappe.gd` n'est jamais utilisé ici — aucun mécanisme du cœur
touché.

**Montre.** un objet en verre (verre_demo, resistance_impact
1.0, fragilite 0.9) et un objet en fer (resistance_impact 8.0, fragilite
0.2), à égale distance d'une source sonore togglable au clic gauche
(n'importe où sur l'écran). Source coupée : rien ne bouge. Source active :
le verre vire progressivement du gris à l'orange puis fracture et se
transforme en éclats en quelques secondes ; le fer suit la même
progression mais huit fois plus lentement, fracture sans jamais se
transformer (fragilite sous le seuil). Label par objet intact :
resistance_impact/fragilite/intensite_sonore_cumulee/état. Console :
bascule de la source, chaque fracture (durete/resistance_compression
effectives via EtatEffectif.valeur), chaque transformation en éclats,
rapport périodique tant qu'un objet n'est pas transformé.

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

## banc_croissance — une plante pousse sous la lumière et l'eau, jamais sous une seule des deux

`Scene/banc_croissance.tscn`, `scripts/banc_croissance.gd`, `data/banc_croissance.json`. Test : `scripts/test_banc_croissance.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_croissance`.

Compose lumiere.gd (lumiere_locale, lue directement), charge.gd (un canal
humidite par plante) et flux.gd (fait monter une réserve maturite), aucun
des trois touché. croissance_max (data/materiaux.json:plante_demo) est
une vitesse MAXIMALE : le taux appliqué est croissance_max * lumiere_locale
* charge_humidite_normalisee (les deux derniers facteurs bornés [0.0, 1.0]
— la charge brute de charge.gd n'est jamais bornée au-dessus, seul le
ratio charge/seuil clampé l'est), transmis à flux.gd via un émetteur
synthétique reconstruit chaque tick (même idiome que banc_conduction.gd).
La réserve maturite est plafonnée à 1.0 par ce banc après chaque appel —
flux.gd ne borne jamais rien lui-même.

**Montre.** trois plantes (même croissance_max 0.5, toutes
plante_demo) alignées autour d'une source de lumière et d'une source d'eau
distinctes, chacune togglable indépendamment (clic gauche = lumière, clic
droit = eau, actives par défaut). plante_1 (à portée des deux) pousse :
sa teinte vire du brun au vert et sa barre de maturité grandit. plante_2
(lumière seule, hors de portée de l'eau) et plante_3 (eau seule, hors de
portée de la lumière) restent brunes, maturité nulle en permanence — c'est
la POSITION de chaque plante, jamais un toggle par plante, qui sépare les
trois destins. Couper la lumière ou l'eau entièrement (clic) arrête toute
croissance en cours, même pour plante_1. Label par plante :
croissance_max/lumiere_locale/charge_humidite/maturite. Console : bascule
de chaque source, un changement d'état croissance ACTIVE/ARRETEE par
plante (jamais chaque tick), et la maturité atteinte pour chaque plante
qui devient adulte.

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

## banc_resonance — un objet résonnant amplifie le son, un objet qui l'absorbe l'étouffe

`Scene/banc_resonance.tscn`, `scripts/banc_resonance.gd`, `data/banc_resonance.json`. Test : `scripts/test_banc_resonance.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_resonance`.

Compose `Perception.percevoir` (canal ouïe, exactement comme `banc_son.gd`)
avec un mécanisme PROPRE à ce banc — `sources_resonantes`, même idiome que
`banc_chaleur_emise.gd:sources_chaleur` : une source secondaire par objet
qui reçoit du son, reconstruite du néant à chaque tick, jamais posée à
force nulle. AUCUN mécanisme du cœur touché ; `banc_son.gd` non plus.

**Montre.** une source sonore (togglable au clic gauche) et
trois objets résonnants réels (fer 0.6, bois 0.7, pierre 0.2) à égale
distance de la source, entre elle et un colon. Chaque objet reçoit du son
de la source (`son_recu`, même formule que `perception.gd`) et le réémet
comme source secondaire (`son_reemis = son_recu * resonance`). Le colon
perçoit la source originale ET les trois sources secondaires — son label
affiche la liste des sources perçues et le son total, qui monte nettement
au-delà de ce que la seule source produirait. Le fer et le bois (résonance
haute) amplifient fortement ; la pierre (résonance basse) contribue peu.
Label par objet : resonance/son_recu/son_reemis. Trace console au
changement de ce que le colon entend, plus un rapport périodique.

**Ne montre pas.** aucun objet positionné entre la
source, les objets résonnants et le colon pour exercer visuellement
l'occlusion (même limite que `banc_son.gd` — voir `CARTE.md`, entrée
`perception.gd` : `propagation_obstacles` n'est plus une sphère pure au
niveau du mécanisme depuis le chantier « occlusion », ce banc ne le montre
simplement pas) ; aucune distinction
visuelle entre « n'amplifie pas parce que hors de portée » et « n'amplifie
pas parce que la source est coupée », au-delà du texte du label.

## banc_occlusion — un obstacle entre A et B bloque la perception

`Scene/banc_occlusion.tscn`, `scripts/banc_occlusion.gd`, `data/banc_occlusion.json`. Test : `scripts/test_banc_occlusion.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_occlusion`.

PREMIÈRE DÉMONSTRATION RÉELLE du troisième filtre de `scripts/perception.gd:_percevoir_propagation_obstacles` (canal ouïe, chantier « occlusion — un obstacle entre A et B bloque la perception », voir `CARTE.md` §2).

**Montre.** deux paires colon/source, matière RÉELLE (fer pour
les sources, pierre pour le mur). Paire `avec_mur` : un mur togglable au
clic gauche, positionné exactement entre `colon_avec_mur` et
`source_avec_mur` — mur présent, le colon ne perçoit plus la source (marge
fine, la pierre réelle n'atténue que de 5%, juste assez pour faire tomber
un signal proche du seuil) ; mur absent, la perception revient. Paire
`temoin` (aucun mur, jamais touchée, à distance) : référence visuelle
constante, prouve que le toggle de la première paire n'affecte jamais la
seconde. Label par source (son_emis, atténuation par obstacle en %), label
par colon (sources perçues), label sur le mur (absorption_sonore). Trace
console au changement de ce que chaque colon entend, plus au toggle du
mur.

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

**Ne montre pas.** un seul obstacle à la fois (jamais
deux murs simultanés dans ce banc, contrairement à
`test_perception.gd:_deux_murs_cumulent_leur_attenuation`) ; aucune
démonstration visuelle du canal vue (`propriete_obstacle` n'est déclaré
que sur `ouie` à ce jour, voir `data/canaux.json`).

## banc_absorption_sonore — un matériau absorbe le son

`Scene/banc_absorption_sonore.tscn`, `scripts/banc_absorption_sonore.gd`, `data/banc_absorption_sonore.json`. Test : `scripts/test_banc_absorption_sonore.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_absorption_sonore`.

Ne code rien de neuf : PROUVE, avec des matériaux DIFFÉRENTS, que le
troisième filtre de `scripts/perception.gd:_percevoir_propagation_obstacles`
(canal ouïe, chantier « occlusion ») réduit le son proportionnellement à la
valeur RÉELLE d'`absorption_sonore` de l'obstacle — là où `banc_occlusion`
ne démontrait qu'une coupure binaire avec la pierre seule. AUCUN mécanisme
du cœur touché ; voir `CARTE.md` `banc_absorption_sonore`.

**Montre.** UN colon et UNE source (fer, `son_emis` 0.5), et UN
mur dont le matériau cycle au clic gauche parmi QUATRE états — `aucun`
(le colon entend à pleine intensité, 0.25), `bois` (`absorption_sonore`
0.3, réduction ~30% — le bois absorbe le plus, panneau acoustique),
`pierre` (0.05, réduction ~5%), `fer` (0.02, réduction ~2% — le métal
résonne, il n'absorbe presque pas). Le seuil de perception du colon est
VOLONTAIREMENT NUL : le colon entend toujours la source, quel que soit le
mur — ce banc montre un POURCENTAGE de réduction, jamais une disparition
(contraste assumé avec `banc_occlusion`, qui cherche une coupure). Label
sur le colon : sources perçues, intensité reçue, atténuation par obstacle
en %. Label sur le mur (visible seulement hors de l'état `aucun`) :
matériau, `absorption_sonore`. Trace console à chaque clic (nouvel état) et
à chaque changement de ce que le colon perçoit.

**Ne montre pas.** jamais deux murs visibles en même
temps dans l'interaction (seule la preuve de cumulation, en test, les
superpose) ; aucune distinction visuelle entre les trois matériaux au-delà
de la couleur du carré et du texte du label.

## banc_friction — le bois glisse loin, la pierre s'arrête net, mouillé glisse encore plus

`Scene/banc_friction.tscn`, `scripts/banc_friction.gd`, `data/banc_friction.json`. Test : `scripts/test_banc_friction.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_friction`.

PREMIÈRE DÉMONSTRATION RÉELLE de `friction` (chantier « friction — fusionner et câbler », voir `CARTE.md` `banc_friction`) :

**Montre.** trois objets FABRIQUÉS (`Objet.fabriquer`, pas
construits à la main — contrairement à `banc_dilatation.gd`), un matériau
réel chacun (bois `friction` 0.4, pierre 0.65, fer 0.5). Une force
identique les pousse tous les trois dès `t=0`, sans bouton — la vitesse
effective de chaque objet est `vitesse_base * (1.0 - friction_effective)`,
`friction_effective` lue via `EtatEffectif.valeur`, jamais réimplémentée. À
sec, le bois glisse le plus loin, le fer au milieu, la pierre le moins — la
distance parcourue s'accumule sans jamais redescendre. Un clic gauche
bascule `mouille` sur LES TROIS OBJETS À LA FOIS : leur friction effective
tombe à ×0.4 de sa base, les trois glissent alors visiblement plus loin
qu'à sec, l'écart bois/pierre restant net une fois mouillés. Label sur
chaque objet : friction (base), friction (effective), état (sec/mouillé),
distance parcourue. Trace console : ligne initiale par objet (t=0), ligne à
chaque bascule de `mouille`, ligne récapitulative des trois distances à
intervalle fixe (`intervalle_log`, donnée).

**Ne montre pas.** aucune borne d'arrêt (les objets
glissent indéfiniment vers la droite, la caméra fixe finit par les perdre
hors champ sur une session longue) — suffisant pour la comparaison des
trois vitesses sur une fenêtre d'observation courte, pas conçu pour une
session prolongée.

## banc_restitution — le fer rebondit haut et longtemps, le bois s'arrête vite

`Scene/banc_restitution.tscn`, `scripts/banc_restitution.gd`, `data/banc_restitution.json`. Test : `scripts/test_banc_restitution.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_restitution`.

PREMIÈRE DÉMONSTRATION RÉELLE de `restitution` (chantier « restitution — rebond après impact », `CARTE.md` `banc_restitution`) :

**Montre.** trois objets FABRIQUÉS (`Objet.fabriquer`, même
patron que `banc_friction.gd`), un matériau réel chacun (bois `restitution`
0.5, pierre 0.6, fer 0.65), immobiles en l'air à `hauteur_initiale` jusqu'au
premier clic gauche, qui RELÂCHE LES TROIS À LA FOIS (`basculer_chute`,
même geste bistable que `banc_friction.gd:basculer_mouille` — un second
clic les RÉINITIALISE en l'air, prêts pour une nouvelle chute). Aucune
physique Godot ni RigidBody : la hauteur vit sur `position.z` (même
convention que `frappe.gd`/`banc_foudre.gd`), un calcul de position par
tick câblé à la main (`avancer()` — gravité constante, rebond déclenché au
franchissement du sol en tombant). À chaque impact, la nouvelle hauteur de
rebond vaut `hauteur_precedente * restitution` — le fer rebondit le plus
haut et le plus longtemps, le bois s'arrête le plus vite, la pierre entre
les deux ; un rebond calculé sous `seuil_arret` arrête l'objet pour de bon.
Label sur chaque objet : restitution, hauteur actuelle, nombre de rebonds.
Trace console : une ligne par impact (rebond ou arrêt final), jamais par
tick, plus une ligne à chaque bascule (relâche/réinitialise).

**Ne montre pas.** rien de spécifique — le banc est
complet pour la comparaison des trois matériaux sur une chute unique ; une
session prolongée après arrêt des trois objets ne montre plus rien de
nouveau tant qu'aucun clic ne relance la chute (comportement voulu, pas une
dette).

## banc_rigidite — le bois plie beaucoup, le fer à peine, la pierre au milieu

`Scene/banc_rigidite.tscn`, `scripts/banc_rigidite.gd`, `data/banc_rigidite.json`. Test : `scripts/test_banc_rigidite.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_rigidite`.

PREMIÈRE DÉMONSTRATION RÉELLE de `rigidite` pour un usage MÉCANIQUE (chantier « rigidite — résistance à la flexion », `CARTE.md` `banc_rigidite`) :

**Montre.** trois poutres horizontales FABRIQUÉES
(`Objet.fabriquer`, même patron que `banc_friction.gd`), un matériau réel
chacune (bois `rigidite` 11.0, pierre 50.0, fer 200.0), soutenues à leurs
deux extrémités (ancrages fixes, poutre en `Line2D` à trois points —
gauche/centre/droite, aucune courbe de Bézier). Aucune charge au
démarrage ; un clic gauche bascule une charge identique sur LES TROIS À LA
FOIS (`basculer_charge`, même geste bistable que
`banc_friction.gd:basculer_mouille`). La flèche de chaque poutre est
`charge / rigidite_effective` (`EtatEffectif.valeur`, jamais
réimplémentée) : le bois plie beaucoup, le fer à peine, la pierre au
milieu. Le point central affiché se déplace vers le bas selon la flèche
MAXIMALE ATTEINTE, jamais la flèche instantanée — un accumulateur qui ne
redescend jamais, même principe que `degats_impact_cumules` dans
`banc_fracture.gd` : une poutre déjà fléchie reste visuellement déformée
même si la charge est ensuite retirée. Si la flèche maximale dépasse
`seuil_flexion` (donnée locale au banc), la poutre casse (état `fracture`,
posé via `SeuilEtat.avancer` sur un catalogue LOCAL à ce banc, jamais
`data/seuils_etat.json` partagé) — irréversible en pratique, la flèche
maximale ne redescendant jamais. Avec les valeurs de démonstration (charge
500.0, seuil 20.0), le bois (flèche ~45.5) casse, la pierre (~10.0) et le
fer (~2.5) résistent. Label sur chaque poutre : rigidité (base/effective),
charge, flèche courante/maximale, état. Trace console : une ligne à chaque
bascule de charge, une ligne à chaque fracture.

**Ne montre pas.** rien de spécifique — le banc est
complet pour la comparaison des trois matériaux sous une charge fixe ;
aucune charge variable (plusieurs niveaux) n'est exposée, une seule
intensité de charge, togglée on/off.

## banc_elasticite — le bois remonte, la pierre reste écrasée, le fer entre les deux

`Scene/banc_elasticite.tscn`, `scripts/banc_elasticite.gd`, `data/banc_elasticite.json`. Test : `scripts/test_banc_elasticite.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_elasticite`.

PREMIÈRE DÉMONSTRATION RÉELLE de `elasticite` (chantier « elasticite — déformation réversible », `CARTE.md` `banc_elasticite`) :

**Montre.** trois objets FABRIQUÉS (`Objet.fabriquer`, même
patron que `banc_friction.gd`/`banc_rigidite.gd`), un matériau réel chacun
(bois `elasticite` 0.3, pierre 0.05, fer 0.2), côte à côte, hauteur pleine
au repos. Un clic gauche bascule une force de compression identique sur
LES TROIS À LA FOIS (`basculer_force`, même geste bistable que
`banc_friction.gd:basculer_mouille`) : sous force, les trois s'écrasent —
le bois (rigidité 11.0) le plus, le fer (200.0) à peine, la pierre (50.0)
au milieu (même ordre que `banc_rigidite.gd`). Un second clic retire la
force : le bois remonte le plus (30% de sa déformation maximale
récupérée), la pierre reste quasi écrasée (95% de déformation permanente),
le fer remonte partiellement (20% récupéré). La déformation MAXIMALE
ATTEINTE ne redescend jamais tant que la force reste active (même principe
que `fleche_maximale_atteinte` de `banc_rigidite.gd`) ; une fois la force
retirée, `deformation_permanente = deformation_maximale_atteinte * (1.0 -
elasticite)` fige la déformation actuelle. Label sur chaque objet :
élasticité, déformation actuelle, déformation permanente, force posée ou
non. Trace console : une ligne à chaque bascule de force, un
récapitulatif périodique.

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

**PIÈGE ÉVITÉ, mesuré**: sur les valeurs RÉELLES du dépôt, le ratio
`elasticite/rigidite` de la pierre et du fer coïncide exactement — la
quantité récupérée EN ABSOLU serait donc identique pour les deux. Seule la
FRACTION récupérée les ordonne sans ambiguïté ; le test isole l'élasticité
à rigidité égale plutôt que de conclure sur le chemin réel.

**Ne montre pas.** rien de spécifique — le banc est
complet pour la comparaison des trois matériaux sous une force fixe ;
aucune force variable n'est exposée, une seule intensité, togglée on/off.

## banc_coupe — le fer coupe le bois facilement, résiste sur la pierre, résiste beaucoup sur le fer

`Scene/banc_coupe.tscn`, `scripts/banc_coupe.gd`, `data/banc_coupe.json`. Test : `scripts/test_banc_coupe.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_coupe`.

PREMIÈRE DÉMONSTRATION RÉELLE de `resistance_cisaillement`/`tranchant_max` (chantier « cisaillement et tranchant — couper un objet », `CARTE.md` `banc_coupe`) :

**Montre.** un outil (par défaut en fer, `tranchant_max` 9.0)
et trois cibles FABRIQUÉES côte à côte (bois/pierre/fer, un matériau réel
chacune). Un clic gauche près d'une cible déclenche une coupe dessus
(`Frappe.selectionner`/`frapper`, même visée par clic que
`banc_fracture.gd`) : le degat = `tranchant_effectif` de l'outil /
`resistance_cisaillement` de la cible — le bois (10.0) est coupé
facilement (0.9/coup avec l'outil en fer), la pierre (20.0) résiste
(0.45/coup), le fer (170.0) résiste beaucoup (0.05/coup). Chaque coupe
émousse l'outil (`tranchant_effectif -= taux_emoussement * durete_cible`,
borné à zéro) : un outil en bois (`tranchant_max` 2.0, durete faible)
s'émousse totalement avant d'avoir entamé significativement la pierre ou
le fer — « le bois ne coupe pas la pierre ». Un tranchant à zéro ne coupe
plus rien, par la seule arithmétique (`0.0 / resistance = 0.0`). Un clic
droit fait cycler l'outil (fer → bois → pierre → fer), lui redonnant un
tranchant frais. Une cible dont l'intégrité atteint zéro se transforme en
débris (`copeaux_bois`/`eclats_pierre`/`limaille_fer`, `Produit.
transformer`, INCHANGÉ) — TOUTE cible coupée à bout transforme ici,
contrairement à `banc_fracture.gd` (pas de branche « reste déformée »).
Label sur l'outil : tranchant_max, tranchant_effectif. Label sur chaque
cible intacte : resistance_cisaillement, intégrité. Trace console : une
ligne par coupe et par transformation.

**Ne montre pas.** rien de spécifique pour la
démonstration demandée — aucun retour visuel de type flash/secousse au
moment du coup (contrairement à `banc_fracture.gd`), non demandé par ce
chantier.

## banc_usinabilite — le bois se travaille vite, le fer plus lentement, la pierre encore plus lentement

`Scene/banc_usinabilite.tscn`, `scripts/banc_usinabilite.gd`, `data/banc_usinabilite.json`. Test : `scripts/test_banc_usinabilite.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_usinabilite`.

PREMIÈRE DÉMONSTRATION RÉELLE de `usinabilite` (chantier « usinabilite — temps de fabrication par matériau », voir `CARTE.md` `banc_usinabilite`) :

FORMULE tranchée en conversation avant d'écrire : la consigne d'origine
(`cout_effectif = cout_base / usinabilite`) contredisait son propre récit
(elle aurait fait finir la pierre en premier) — `depense.gd` retire
`cout_base * delta` de la réserve, donc un `cout_base` plus grand épuise
plus vite. Retenu : `cout_effectif = cout_base_reference *
usinabilite_effective` — un matériau facile à usiner consomme SA réserve
plus vite et finit plus tôt.

**Montre.** trois objets FABRIQUÉS (`Objet.fabriquer`), un
matériau réel chacun (bois `usinabilite` 0.8, pierre 0.3, fer 0.5), chacun
avec une réserve `depense.gd` nommée `travail` (même `travail_restant`
initial pour les trois). RIEN ne descend avant le premier clic gauche
(contraste avec `banc_friction.gd`, qui glisse dès `t=0`) — le clic
bascule la fabrication des trois à la fois ; un second clic la suspend
sans jamais réinitialiser `travail_restant`. Le bois descend le plus vite,
le fer au milieu, la pierre le plus lentement — le bois devient donc
« fabriqué » en premier, le fer ensuite, la pierre en dernier. Label sur
chaque objet : usinabilité, travail restant/initial, état (en cours/
fabriqué) — couleur qui change au passage à « fabriqué ». Trace console :
ligne initiale par objet (t=0), ligne à chaque bascule de fabrication,
ligne dès qu'un objet devient fabriqué, récapitulatif périodique.

**Ne montre pas.** rien de spécifique pour la
démonstration demandée — aucune borne de temps maximal si la fabrication
reste active indéfiniment sans qu'aucun objet n'atteigne jamais zéro
(situation qui ne se produit pas avec les données réelles du dépôt).

## banc_traction — le lien en pierre casse vite, le bois résiste longtemps, le fer résiste le plus

`Scene/banc_traction.tscn`, `scripts/banc_traction.gd`, `data/banc_traction.json`. Test : `scripts/test_banc_traction.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_traction`.

PREMIÈRE DÉMONSTRATION RÉELLE de `resistance_traction` (chantier « resistance_traction — rupture par traction », voir `CARTE.md` `banc_traction`) :

**Montre.** trois objets FABRIQUÉS (bois/pierre/fer, un
matériau réel chacun), suspendus sous un point d'ancrage fixe dessiné
au-dessus de chacun. Aucune force au démarrage ; un clic gauche BASCULE
une force de traction identique sur les trois à la fois. Avec les valeurs
de démonstration (force 8.0/s), la pierre (résistance 5.0) rompt vers
t=0.6s, le bois (90.0) vers t=11.25s, le fer (250.0) résiste au-delà de
30s. Dès qu'un objet rompt, son ancrage disparaît et il tombe (aucune
physique Godot — un calcul de position par tick, même convention de
hauteur que `banc_restitution.gd`, mais SANS rebond : il touche le sol et
y reste). Label par objet : résistance_traction, force cumulée, état
rompu ou non. Trace console : une ligne à chaque bascule de force, à
chaque rupture, à chaque atterrissage.

**Ne montre pas.** rien de spécifique pour la
démonstration demandée.

## banc_velocite — le colon s'arrête net, le golem accélère en approchant, le repère ne bouge jamais

`Scene/banc_velocite.tscn`, `scripts/banc_velocite.gd`, `data/banc_velocite.json`. Test : `scripts/test_banc_velocite.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_velocite`.

`scripts/velocite.gd` (voir CARTE.md §2) reçoit ici son PREMIER câblage
réel — chantier « velocite — vitesse instantanée passive ». AUCUN mécanisme du
cœur touché : `champ.gd`/`objet.gd`/`banc_commun.gd`/`banc_controle.gd`/
`banc_champ.gd` inchangés.

**Montre.** quatre objets. Un colon (rouge, `bouger_vers` via
`banc_controle.gd`, REUTILISÉ, sans aucune composition — jamais dans le
champ magnétique) part immobile, velocite affichée `(0,0,0)`. Le golem
(violet) et l'aimant (gris foncé) sont EXACTEMENT ceux de `banc_champ.gd`
(`BancChamp.fabriquer_golem_magnetique`/`_fabriquer_aimant`, REUTILISÉS).
Un clic gauche pose le MÊME point-cible sur le colon ET le golem
(`BancControle.donner_ordre`, appelé deux fois — un seul clic, deux
ordres, aucune ambiguïté d'entrée). Le colon avance à vitesse plafond
(velocite affichée correspond exactement à `proprietes.vitesse`, 150.0)
puis s'arrête NET à l'arrivée — la velocite retombe exactement à zéro,
dérivée passivement, jamais posée par un cas particulier. Le golem
reproduit l'interaction déjà prouvée par `banc_champ.gd` : sa velocite
monte en s'approchant de l'aimant (le champ domine, 1/d²) et peut
redescendre si le clic suivant l'envoie loin dans la direction opposée
(le pas volontaire domine, le champ faiblit) — AUCUNE branche « si
proche » nulle part, la différence émerge de la même composition que
`banc_champ.gd`. Le repère (gris clair), un cinquième type LOCAL jamais
touché par aucun mécanisme, affiche `velocite=(0,0,0)` sur toute
l'observation — démonstration directe : aucune propriété « immobile »
n'existe, le zéro EST le résultat du calcul sur une position qui ne
change jamais. Un `Label` recapitule les quatre lignes (id, velocite,
magnitude) à chaque tick ; la console imprime la même chose toutes les
0.5s.

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

**Ne montre pas.** aucune distinction visuelle entre
la contribution volontaire et la contribution du champ dans la velocite
du golem (le Label affiche la velocite totale, jamais décomposée en deux
parts) — non nécessaire à ce que ce chantier devait prouver.

## banc_acide — le fer corrode vite, le bois résiste longtemps, la pierre entre les deux

`Scene/banc_acide.tscn`, `scripts/banc_acide.gd`, `data/banc_acide.json`. Test : `scripts/test_banc_acide.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_acide`.

PREMIÈRE DÉMONSTRATION RÉELLE de `resistance_acide` (chantier « resistance_acide — corrosion par acide », voir `CARTE.md` `banc_acide`) :

**Montre.** trois objets FABRIQUÉS (bois/pierre/fer, un
matériau réel chacun), côte à côte, sans mouvement ni ancrage. Aucune
exposition au démarrage ; un clic gauche BASCULE une source d'acide
identique sur les trois à la fois. Avec les valeurs de démonstration
(exposition 0.05/s), le fer (résistance 0.1) corrode vers t=2s, la
pierre (0.3) vers t=6s, le bois (0.5) vers t=10s. Un objet corrodé
change de couleur et le reste pour toujours (état irréversible). Label
par objet : résistance_acide, exposition cumulée, état corrode_acide ou
non. Trace console : une ligne à chaque bascule de source, à chaque
corrosion.

**Ne montre pas.** rien de spécifique pour la
démonstration demandée.

## banc_toxicite — le poison empoisonne vite, le fer lentement, la pierre jamais

`Scene/banc_toxicite.tscn`, `scripts/banc_toxicite.gd`, `data/banc_toxicite.json`. Test : `scripts/test_banc_toxicite.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_toxicite`.

PREMIÈRE DÉMONSTRATION RÉELLE de `toxicite` (chantier « toxicite — empoisonnement par contact », voir `CARTE.md` `banc_toxicite`) :

**Montre.** trois objets FABRIQUÉS fixes, espacés de 300
unités (poison_demo, matériau de démonstration à toxicité 0.9 ; fer,
toxicité 0.1 ; pierre, toxicité 0.0), chacun affichant sa toxicité. Le
colon démarre à côté de poison_demo ; un clic gauche le déplace vers
l'objet suivant, cycle circulaire sur les trois. Près de poison_demo il
s'empoisonne vite (~1.1s) et sa réserve de santé décroît en continu tant
qu'il reste exposé ; près du fer, nettement plus lentement (~10s) ; près
de la pierre, jamais — sa charge d'empoisonnement redescend au lieu de
monter. S'éloigner (ou changer d'objet) laisse l'état « empoisonne »
s'estomper progressivement (`etat_duree.gd`, durée 3.0s), jamais un
retrait instantané ; la reserve de sante cesse alors de decroitre. Label
par objet : toxicité. Label du colon : empoisonné ou non, charge
d'empoisonnement/seuil, réserve de santé. Trace console : une ligne à
chaque déplacement, à chaque bascule d'exposition, à chaque changement
d'état empoisonné.

**Ne montre pas.** rien de spécifique pour la
démonstration demandée.

## banc_mana_conduction — le mana traverse le fer, s'arrête net au bois

`Scene/banc_mana_conduction.tscn`, `scripts/banc_mana_conduction.gd`, `data/banc_mana_conduction.json`. Test : `scripts/test_banc_mana_conduction.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_mana_conduction`.

Chantier « conductivite_electrique pour la magie — canalisation de mana »
(voir CARTE.md `banc_mana_conduction`) : MÊME PATRON que `banc_conduction.gd`, RECOPIÉ
localement (deux bancs jetables ne se référencent jamais entre eux), sur le
domaine du mana plutôt que du courant — un objet conducteur relié à une
source de mana canalise le mana à ses voisins conducteurs tant que le
contact dure. SEULE DIFFÉRENCE ASSUMÉE : pas de volet dégâts à un agent
(pas de `charge.gd`/`etat_duree.gd`/`depense.gd`) — seule la canalisation
elle-même est montrée, via `flux.gd` (INCHANGÉ). Aucun mécanisme du cœur
touché ; `scripts/banc_conduction.gd`/`test_banc_conduction.gd` inchangés
eux aussi.

**Montre.** un clic gauche bascule TOUTES les sources actives/
inactives à la fois. Deux rangées : fer-bois-fer (le second fer ne reçoit
jamais de mana, bloqué net au bois) et fer-fer-fer (les trois se
canalisent en chaîne — remplacer le bois par du fer fait traverser les
trois). Chaque objet affiche sa conductivité effective, s'il conduit, s'il
est sous mana et sa réserve de mana. Couper les sources arrête la
canalisation et fait redescendre la réserve de mana de chaque objet vers
zéro (`TAUX_DECROISSANCE_MANA`, même correctif que `TAUX_DECROISSANCE_
COURANT` dans `banc_conduction.gd` — `flux.gd` n'a lui-même aucun geste de
décroissance). La console imprime une phrase par changement significatif
(bascule de source, objet canalisé/hors canalisation).

**Ne montre pas.** aucun troisième matériau
intermédiaire (pierre, conductivité `1e-9`) pour montrer un gradient
plutôt qu'une simple opposition binaire fer/bois — même limite déjà
signalée pour `banc_conduction.gd`, non corrigée ici non plus.

## banc_choc_magique — un sort casse le verre, puis le bois, puis le fer

`Scene/banc_choc_magique.tscn`, `scripts/banc_choc_magique.gd`, `data/banc_choc_magique.json`. Test : `scripts/test_banc_choc_magique.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_choc_magique`.

Chantier « resistance_impact pour le choc magique » (voir CARTE.md
`banc_choc_magique`) : TROISIÈME chemin vers l'état `fracture`, après le choc
mécanique (`banc_fracture.gd`) et le son intense (`banc_fracture_sonore.gd`)
— même nom d'état, une troisième entrée dans `data/seuils_etat.json`
(`choc_magique`, compare `choc_magique_cumule` à `resistance_impact`).
Compose `Frappe.selectionner`/`frapper`, `SeuilEtat.avancer` et
`Produit.transformer`, tous INCHANGÉS. Aucun mécanisme du cœur touché.

**Montre.** trois objets fixes espacés de 250 unités —
verre_0 (verre_demo), bois_0, fer_0. Un clic gauche ACTIVE un sort
togglable (label « sort : actif ») : toutes les 0.4s, chaque cible
encaisse un coup magique instantané sur sa propre position (trois casters
indépendants, jamais un seul caster qui monopoliserait la cible au score
le plus haut). verre_0 (`resistance_impact` 1.0) fracture dès le premier
coup et se transforme aussitôt en éclats ; bois_0 (4.0) fracture après le
troisième coup, déformé sans transformation ; fer_0 (8.0) après le
sixième, déformé sans transformation — ordre strict qui reproduit
`resistance_impact`. Un second clic COUPE le sort (label « sort : coupe »).

**Ce qui a été ajouté.** DEUX DÉCISIONS TRANCHÉES PAR YAEL avant d'écrire (question posée) : le critère de sélection de `Frappe.selectionner` est `sensibilite_magique` SEULE, la distance restant le filtre de portée déjà existant (rayon), jamais une deuxième source ajoutée au score composite ;

**Ne montre pas.** aucun retour visuel distinct au
moment précis de chaque coup (flash/secousse, comme `banc_fracture.gd`) —
la teinte progresse en continu vers le violet/rouge mais rien ne marque
l'instant de la frappe elle-même.

## banc_reactivite — l'acide attaque le fer vite, le bois entre les deux, la pierre lentement, puis se vide

`Scene/banc_reactivite.tscn`, `scripts/banc_reactivite.gd`, `data/banc_reactivite.json`. Test : `scripts/test_banc_reactivite.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_reactivite`.

PREMIÈRE DÉMONSTRATION RÉELLE de `reactivite` (chantier « reactivite — réaction chimique entre deux objets », voir `CARTE.md` `banc_reactivite`, « aucun mécanisme de contact-entre-deux-objets générique n'existe aujourd'hui »).

DÉCISION DE DESIGN tranchée par Yael avant d'écrire (constat posé
d'abord : `produit.gd:transformer` ne prend qu'UN SEUL
`proprietes_ancien`, `monde.gd` n'a aucune fonction de retrait d'objet,
le seul précédent « deux objets réels → un » est `soudure.gd`, qui
FUSIONNE plutôt que produit un `type_produit` choisi) : les deux
réactifs sont transformés SÉPARÉMENT, deux appels distincts à
`produit.gd:transformer` — la CIBLE (fer/pierre/bois) devient son
produit quand SON PROPRE canal `charge.gd` (« reaction ») franchit son
seuil (initialisé depuis `data/reactions.json:seuil_reactivite`,
pondéré par `score_reaction = reactivite(acide) * reactivite(cible)`,
recalculé chaque tick) ; l'ACIDE devient `residu_acide` quand SA PROPRE
réserve `depense.gd` (« acide ») atteint zéro — `cout_base` recalculé
chaque tick, proportionnel à la somme des `reactivite` des cibles ENCORE
réactives à portée, FORCÉ à zéro dès qu'aucune cible ne reste réactive
(sans cette fermeture explicite, la consommation se fige à une valeur
résiduelle dès la dernière réaction, l'acide ne s'épuiserait jamais).

**Montre.** un acide_demo et trois cibles (fer/pierre/bois)
fabriquées par composition. Un clic gauche BASCULE la position de
l'acide entre « proche » (à portée de contact des trois cibles à la
fois) et « loin » (hors de toute portée). Proche : le fer (`reactivite`
0.6) devient `sel_metallique` en premier, le bois (0.2) ensuite, la
pierre (0.1) en dernier — l'acide se vide plus vite au début (trois
cibles actives) qu'à la fin (la pierre seule) ; une fois les trois
transformées, l'acide devient `residu_acide`. Loin : rien ne bouge.
Label par objet : réactivité, charge de réaction (cible) ou réserve
(acide), produit attendu (cible) ou statut (acide). Trace console : une
ligne par bascule de position, par cible transformée, et quand l'acide
devient résidu.

## banc_radiation — le bois s'irradie plus vite que le fer, le fer plus vite que la pierre, un mur dense bloque tout

`Scene/banc_radiation.tscn`, `scripts/banc_radiation.gd`, `data/banc_radiation.json`. Test : `scripts/test_banc_radiation.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_radiation`.

Chantier « sensibilite_radiation — irradiation et blindage » (voir
`CARTE.md` `banc_radiation`). BLOQUÉ une session entière : `perception.gd` lisait
`"son_emis"` en dur comme force d'émission de la source, jamais
paramétré par canal — bloquer le blindage radiation exigeait de
généraliser ce nom en `propriete_emission`, un chantier séparé, livré
par une autre session pendant l'attente (voir `docs/ETAT.md`). Une fois
livré, AUCUN mécanisme du cœur touché : `perception.gd`/`charge.gd`/
`etat_duree.gd`/`etat_effectif.gd`/`depense.gd`/`objet.gd`/`monde.gd`
inchangés.

**Montre.** une source radioactive fixe au centre, trois
objets fabriqués (bois/pierre/fer) à ÉGALE distance disposés
perpendiculairement, affichant chacun sa `sensibilite_radiation`, sa
charge de radiation et son intégrité. Sans mur (état initial), le bois
(sensibilité 0.3) s'irradie le plus vite, le fer (0.2) ensuite, la
pierre (0.1) le plus lentement — les trois finissent par passer
« irradié » et voient leur intégrité décroître en continu tant qu'ils le
restent. Un clic gauche fait apparaître un mur (fer, très dense) placé
exactement entre la source et fer_radiation : celui-ci cesse aussitôt
d'accumuler de la radiation, bois/pierre continuent inchangés. Un second
clic retire le mur, fer_radiation redevient exposé comme avant. Trace
console : sensibilité initiale par objet, bascule du mur, pose/retrait
d'`expose_radiation` et d'« irradié » par objet.

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

**Ne montre pas.** rien de spécifique pour la
démonstration demandée.

## banc_manger — le colon mange la nourriture, ignore le bois et la pierre

`Scene/banc_manger.tscn`, `scripts/banc_manger.gd`, `data/banc_manger.json`. Test : `scripts/test_banc_manger.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_manger`.

Chantier « consommer.gd — transfert destructif + banc_manger » (voir
`CARTE.md` `banc_manger`).
PREMIÈRE DÉMONSTRATION RÉELLE de `scripts/consommer.gd` (SIXIÈME mécanisme
du cœur neuf de cette session) et du verbe `manger`. AUCUN mécanisme du
cœur touché : `perception.gd`/`proximite.gd`/`dominance.gd`/`agir.gd`/
`ciblage.gd`/`consommer.gd`/`produit.gd`/`etat_effectif.gd`/`objet.gd`
inchangés.

**Montre.** un colon et trois objets côte à côte (nourriture_
demo, bois, pierre). Le colon perçoit et converge sur la nourriture (seule
chose saillante — `profil_saillance : "nourriture"`, bois/pierre n'en
portent aucun, jamais candidats de décision), l'atteint puis mange :
`contenu` de la nourriture décroît, `energie` du colon croît de la MÊME
quantité exacte (même `taux`, voir `consommer.gd`), jusqu'à épuisement puis
transformation en `reste_nourriture` (`produit.gd:transformer`, teinte
différente). Bois et pierre ne sont jamais approchés ni mangés — le colon
les ignore entièrement, pas seulement « ne les mange pas ». Vérifié par
lancement réel headless (console lue) : premier repas à `t=2.4s`, contenu
épuisé et transformation à `t=7.0s`, énergie montée exactement de 10.00 sur
la même période, aucune erreur console. Label sur le colon : énergie,
action en cours. Label sur chaque objet : contenu restant/comestibilité/
valeur_nutritive_energie (nourriture) ou comestibilité seule (bois/pierre,
`0.0`). Trace console : une ligne par consommation, une à la
transformation.

**Ce qui a été ajouté.** COLLISION FERMÉE avec `test_lint_donnees.gd` (même décision que `leger_golem`/`aimant_metal`, chantier `champ.gd`) : `profil_saillance`/`type_produit` sont vérifiés contre les catalogues PARTAGÉS quel que soit le fichier source — `nourriture` (`data/ profils_saillance.json`) et `reste_nourriture` (`data/types.json`) rejoignent donc les catalogues partagés plutôt qu'une table locale au banc.

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

## banc_magie_perception — le mage perçoit tout, le guerrier ne perçoit que les sources fortes

`Scene/banc_magie_perception.tscn`, `scripts/banc_magie_perception.gd`, `data/banc_magie_perception.json`. Test : `scripts/test_banc_magie_perception.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_magie_perception`.

Chantier « sensibilite_magique — perception magique » (voir `CARTE.md`
`banc_magie_perception`). BLOQUÉ en début de session, décision Yael prise EN
CONVERSATION avant tout code : le mécanisme de seuil de `perception.gd`
lisait `"son_emis"` en dur, jamais paramétré par canal — attendu la
livraison du chantier séparé « propriete_emission configurable par
canal » (livré par une autre session pendant l'attente, voir
`docs/ETAT.md`). Une fois livré, AUCUN mécanisme du cœur touché :
`perception.gd`/`charge.gd`/`etat_effectif.gd`/`objet.gd`/`monde.gd`/
`banc_commun.gd` inchangés.

DÉCISION DE SENS, tranchée par Yael avant d'écrire : `sensibilite_
magique` (matériau, dormante) N'EST PAS l'équivalent magique de
`son_emis` — c'est un stat du RÉCEPTEUR (seuil de détection), jamais
fusionnée, jamais lue ici. Le seuil réel vit sur le COLON
(`canaux_config.magie.seuil`). La SOURCE porte une propriété séparée,
NOUVELLE, `force_magique` (rôle ÉMETTEUR).

RENDU LISIBLE (session ultérieure, chantier « rendu lisible de
banc_magie_perception ») : la position d'AFFICHAGE (carrés, labels,
lignes) est désormais SÉPARÉE de la position LOGIQUE (celle que lit
`Perception.percevoir`/`Monde`, strictement inchangée — mêmes distances,
mêmes seuils, mêmes `force_magique`, verrouillées par les mêmes tests
mécanisme/chemin réel qu'avant ce chantier). `data/
banc_magie_perception.json:affichage` place chaque colon (mage à gauche,
guerrier à droite, 500 unités d'écart horizontal — au-delà du minimum de
400 demandé), et empile les sources de son cluster en colonne verticale
à côté de lui (`scripts/banc_magie_perception.gd:position_colonne`, 100
unités entre deux sources consécutives — dans la fourchette 80-100
demandée), décalée horizontalement pour ne jamais chevaucher le label du
colon. La source lointaine est isolée, en bas au centre. AUCUN mécanisme
du cœur touché, RIEN de la logique de perception modifié :
`perception.gd`/`charge.gd`/`etat_effectif.gd`/`objet.gd`/`monde.gd`/
`banc_commun.gd` inchangés — seul ce fichier.

**Montre.** deux colons très éloignés (mage jaune à gauche,
guerrier cyan à droite), chacun entouré de sources magiques réelles
(bois/pierre/fer, plus une source de démonstration très forte) empilées
en colonne à côté de lui, jamais serrées. Le mage (seuil bas) perçoit
les quatre sources de son cluster, y compris la plus faible (fer). Le
guerrier (seuil haut) ne perçoit que les deux plus fortes (bois et la
source de démonstration) — pierre et fer restent sous son seuil. Une
source sans `force_magique` (verre, à portée) n'est jamais perçue par
aucun des deux, quel que soit leur seuil. Une source lointaine (isolée,
en bas au centre) n'est jamais perçue non plus, mais pour une raison
géométrique distincte. Nom au-dessus de chaque carré ; en dessous du
nom, `force_magique` (source) ou rien (colon). Sous chaque colon,
`seuil=X.XX` dans sa couleur. Une LIGNE, dans la couleur du colon, relie
celui-ci à chaque source qu'il perçoit CE TICK — jamais vers une source
non perçue ; plus de texte « perçoit:... ». Légende fixe en haut à
gauche, deux lignes colorées (mage/guerrier) rappelant le sens de
chaque seuil. Trace console au changement de perception (inchangée).

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

## banc_sorts — un catalogue de données choisit le mécanisme, jamais le code

`Scene/banc_sorts.tscn`, `scripts/banc_sorts.gd`, `data/banc_sorts.json`. Test : `scripts/test_banc_sorts.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_sorts`.

Chantier « sorts — câblage de base + banc de démonstration ». POSE LA TUYAUTERIE,
pas les sorts eux-mêmes : `lancer_sort(caster, sort_id, catalogue_sorts,
monde, catalogue_etats, materiaux) -> { succes, cible, effet }` lit une
entrée de `data/sorts.json` et dispatche vers UN SEUL mécanisme déjà
fermé, selon le nom de son `effet` — jamais un nom de sort en dur au-delà
de ce match. AUCUN MÉCANISME DU CŒUR TOUCHÉ : `frappe.gd`/`flux.gd`/
`etat_duree.gd`/`etat_effectif.gd`/`seuil_etat.gd`/`depense.gd`/
`perception.gd`/`portee.gd`/`agir.gd`/`objet.gd` restent exactement ceux
déjà verrouillés par leurs propres tests.

QUATRE EFFETS CÂBLÉS, quatre patrons déjà fermés, jamais réécrits :
`"frappe"` → `Frappe.selectionner` (critère lu depuis
`grandeur.critere`, même forme exacte que `banc_choc_magique.gd`) +
`Frappe.frapper` ; `"flux"` → `Flux.avancer` avec un ÉMETTEUR SYNTHÉTIQUE
reconstruit à chaque appel (patron `banc_mana_conduction.gd`), appelé
avec `delta=1.0` — un sort est un ÉVÉNEMENT PONCTUEL, jamais un taux
continu, `taux` sert directement de quantité appliquée UNE FOIS ;
`"etat"` → `EtatDuree.poser`, INCHANGÉ (la durée réellement appliquée
vient de `data/etats.json:<nom_etat>.duree`, jamais d'un paramètre du
sort) ; `"frappe_zone"` → boucle `Portee.en_portee` + `Frappe.frapper`
sur CHAQUE objet à portée, PAS `Frappe.selectionner` (qui ne rend qu'UN
SEUL objet, jamais une liste — nuance de l'audit préalable).

MANA : `proprietes.reserves.mana.reserve` vérifiée AVANT tout effet,
soustraite DIRECTEMENT (`max(0.0,...)`, patron `depense.gd` — jamais via
`Depense.avancer`, même raison que `Frappe.frapper` : ponctuel, pas un
taux). Remonte en continu via une source ambiante (`Flux.avancer`, patron
`banc_animal.gd`, hors de `lancer_sort`).

AFFINITE_MAGIQUE : `proprietes.get("affinite_magique", 1.0)` du LANCEUR,
jamais fusionnée par composition — posée directement sur le type du
caster (`data/banc_sorts.json`). MULTIPLIE toute grandeur D'INTENSITÉ
(degats/taux) avant l'appel au mécanisme, jamais nom_etat/duree/
nom_reserve.

VOLATILITE_MAGIQUE : DÉCISION YAEL (question posée avant d'écrire) — les
valeurs dormantes existantes de `data/materiaux.json` (bois 0.3/pierre
0.1/fer 0.05) sont hors d'échelle avec des dégâts de sort (3.0-10.0 par
coup, un seul coup les dépasserait toutes) ET dans un ORDRE qui
contredirait la démonstration voulue (fer y est la valeur la PLUS BASSE,
pas la plus haute). `volatilite_magique` est donc POSÉE À LA MAIN sur les
quatre cibles FABRIQUÉES de ce banc (même geste que `force_radiation`
dans `banc_radiation.gd`), à des valeurs propres à CE banc (verre_sort
8.0 < bois_sort 20.0 < pierre_sort 35.0 < fer_sort 60.0) — bois/pierre/
fer restent INCHANGÉS partout ailleurs dans le dépôt. Chaque objet touché
par `"frappe"`/`"frappe_zone"` accumule `charge_magique_cumulee` (même
geste que `degats_impact_cumules`/`choc_magique_cumule`) ;
`scripts/seuil_etat.gd` (INCHANGÉ, nouvelle entrée `explosion_magique`)
la compare à `volatilite_magique` et pose `explose` (nouvel état,
marqueur pur, aucun effet modulé, IRRÉVERSIBLE) ; `avancer_explosions`
(fonction PROPRE à ce banc) détecte `explose` fraîchement posé et
déclenche `Frappe.frapper` sur tout ce qui est à portée
(`rayon_explosion_volatilite`), une seule fois par objet.

**Montre.** un caster (bleu, affinité magique 1.5) entouré de
quatre cibles fabriquées en croix (fer/bois/pierre/verre, 150 unités).
Touche 1 (`eclair`) frappe la cible la plus conductrice (fer_sort, seule
à haute `conductivite_electrique`). Touche 2 (`soin`) remonte la réserve
`sante` du caster. Touche 3 (`bouclier`) pose `protege` (module
`resistance_impact` ×3.0, s'estompe après 8s). Touche 4 (`explosion`)
frappe toutes les cibles à portée (200 unités) à la fois. Chaque sort
lancé sans mana suffisant échoue sans rien consommer ni toucher personne.
Après plusieurs sorts reçus, verre_sort (volatilité basse) finit par
exploser et déclenche une frappe de zone sur ses voisins ; fer_sort
(volatilité haute) résiste sur toute la durée d'observation normale.
Label sur le caster (mana, santé, affinité, `protege`, sort en cours) ;
label sur chaque cible (intégrité, charge magique cumulée, volatilité,
état). Trace console à chaque sort lancé et à chaque explosion.

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

## banc_produit_nucleaire — une source radioactive s'épuise et contamine, un colon mute puis tombe malade

`Scene/banc_produit_nucleaire.tscn`, `scripts/banc_produit_nucleaire.gd`, `data/banc_produit_nucleaire.json`. Test : `scripts/test_banc_produit_nucleaire.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_produit_nucleaire`.

Chantier « Produit nucléaire — contamination, mutation, maladie » (voir
`CARTE.md` `banc_produit_nucleaire`). Compose TROIS effets d'une même
source radioactive sur les mécanismes déjà verrouillés par `banc_radiation.gd`
(`banc_radiation`), plus quatre de plus jamais composés ensemble avant ce
chantier : `charge.gd`/`depense.gd`/`seuil_etat.gd`/`etat_duree.gd`/
`etat_effectif.gd`/`epigenetique.gd`/`produit.gd`/`combustible.gd`/
`perception.gd`/`objet.gd`. AUCUN mécanisme du cœur touché.

**Montre.** une source radioactive fixe au centre, deux objets
(bois/pierre) disposés perpendiculairement, un troisième (fer) et un colon
alignés sur le même axe qu'un mur de blindage togglable au clic. La source
irradie les trois objets (même mécanique que `banc_radiation.gd`) tout en
épuisant sa propre réserve — sa `force_radiation` décroît, jusqu'à se
transformer en résidu radioactif qui continue d'irradier, plus faiblement,
en décroissant à son tour. Le colon exposé accumule en parallèle une dose
qui ne redescend jamais (nausée réversible d'abord, syndrome permanent
ensuite, mort permanente enfin — sa vitesse effective chute puis tombe à
zéro) et une marque épigénétique qui persiste en décroissant lentement une
fois éloigné. Une fois mort, le colon est FIGÉ (décision Yael) : plus aucun
mécanisme du banc ne le met à jour, il reste visible comme un corps —
aucun retrait du monde (`monde.gd` n'a aucune fonction de retrait d'objet,
un vrai chantier séparé, jamais ouvert ici). Le mur bloque simultanément
fer_nucleaire ET le colon (même segment), jamais bois/pierre. Trace
console : bascule du mur, transformation de la source, pose/retrait
d'« irradié » par objet, chaque changement d'état du colon
(sain/nausée/syndrome/mort).

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

## banc_activation_neutronique — un objet irradié devient à son tour source de radiation

`Scene/banc_activation_neutronique.tscn`, `scripts/banc_activation_neutronique.gd`, `data/banc_activation_neutronique.json`. Test : `scripts/test_banc_activation_neutronique.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_activation_neutronique`.

Chantier « activation neutronique — objet irradié devient source
secondaire » (voir `CARTE.md` `banc_activation_neutronique`). AUCUN mécanisme du cœur
touché : `charge.gd`/`depense.gd`/`seuil_etat.gd`/`combustible.gd`/
`perception.gd`/`etat_duree.gd`/`etat_effectif.gd`/`epigenetique.gd`/
`objet.gd` restent exactement ceux déjà verrouillés par leurs propres
tests.

**Montre.** une source radioactive fixe, togglable au clic,
irradie trois objets fabriqués (bois/pierre/fer, même mécanique que
`banc_radiation.gd`). Chaque objet accumule `dose_radiation_objet` (le
MAXIMUM jamais atteint par sa charge, jamais un miroir direct — voir
DÉCISION YAEL plus bas) ; au seuil fixe 30.0, il devient source
secondaire (`force_radiation` propre, réserve `radioactivite_acquise` qui
s'épuise et fait retomber `force_radiation` à 0.0 — l'état
`active_neutronique` reste posé pour toujours, cicatrice permanente). Un
colon, hors de portée de la source primaire et qui ne l'interroge d'ailleurs
jamais mécaniquement, perçoit UNIQUEMENT les objets activés et subit
l'escalier déjà montré par `banc_produit_nucleaire.gd` (nausée réversible,
marque épigénétique, syndrome puis mort permanents). Retirer la source
primaire au clic ne coupe pas les objets déjà activés : ils continuent
d'irradier le colon en décroissant.

**Ce qui a été ajouté.** DÉCISION YAEL (question posée avant d'écrire, consigne d'origine ambiguë) : `dose_radiation_objet` suit le MAXIMUM jamais atteint par `etats.radiation.charge` (`scripts/charge.gd`, réversible par construction), jamais un miroir direct — un miroir aurait rendu `active_neutronique` réversible, en contradiction avec le rôle de cicatrice permanente voulu.

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

## banc_emergences — un objet composé gagne une capacité qu'aucun de ses composants ne porte seul

`Scene/banc_emergences.tscn`, `scripts/banc_emergences.gd`, `data/banc_emergences.json`. Test : `scripts/test_banc_emergences.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_emergences`.

Chantier « propriétés émergentes — capacités conditionnelles à la
fabrication » (voir `CARTE.md` `banc_emergences`). SEUL chantier de cette
liste qui MODIFIE un mécanisme du cœur : `objet.gd:fabriquer` gagne un
dernier pas, `_evaluer_emergences`, qui compare des propriétés déjà
fusionnées à des seuils lus depuis un catalogue et pose des propriétés
supplémentaires si toutes les conditions d'une entrée sont remplies.
Aucun autre mécanisme du cœur touché.

**Montre.** trois objets, BISTABLES au clic gauche (même geste
que `banc_restitution.gd`) — AVANT (composition seule, aucune fusion) /
APRÈS (un clic fabrique les trois à la fois, composition fusionnée +
émergences évaluées ; un second clic réinitialise à AVANT). `fer_cristal`
(fer + cristal_demo, volumes égaux) combine un bon conducteur et une
matière sensible à la magie — aucun des deux seuls ne suffit, la
combinaison gagne `canalise_mana : true`. `balsa` (balsa_demo seul) est
assez léger et assez résistant pour gagner `flotte : true`, sans aucune
composition. `fer_seul` (fer seul) remplit une condition sur deux
(conductivité) mais rate l'autre (sensibilité magique) — ET logique,
aucune émergence. Label APRÈS : composition, propriétés fusionnées
pertinentes, PUIS pour chaque émergence du catalogue le détail par
condition (valeur mesurée face au seuil, colorée OK/RATE) et le verdict
final (ACQUISE/non). Trace console à chaque bascule (fabrication ou
reset).

**Ce qui a été ajouté.** DÉCISION (constat posé avant d'écrire, question posée à Yael) : `sensibilite_magique` est dormante partout dans le dépôt (décision explicite du chantier `banc_magie_perception.gd`) — ce banc étend sa PROPRE liste locale de propriétés immuables plutôt que de toucher au catalogue partagé `data/proprietes_immuables_composition.json`, pour ne jamais affecter aucun autre banc ni revenir sur la dormance déjà actée.

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

Vérifié (headless, test_emergences.gd + test_banc_emergences.gd + suite
complète, 128 tests VERT, aucune régression) : fer+cristal_demo gagne
canalise_mana et jamais flotte ; balsa_demo seul gagne flotte et jamais
canalise_mana ; fer seul ne gagne ni l'un ni l'autre ; une propriété
absente de l'objet fait toujours échouer sa condition (jamais un défaut
permissif) ; un catalogue vide ne change jamais rien ; plusieurs
émergences indépendantes peuvent se poser sur le même objet ; en état
AVANT (`objets_bruts`) aucune propriété fusionnée n'apparaît jamais ;
`basculer_fabrique` inverse strictement son booléen ;
`diagnostic_conditions` reporte le même verdict par condition que le
verdict final déjà posé par `objet.gd`.

## banc_chaine_reactions — acide+fer produit du sel, le sel réagit ensuite avec l'eau, deux étages sans recâblage

`Scene/banc_chaine_reactions.tscn`, `scripts/banc_chaine_reactions.gd`, `data/banc_chaine_reactions.json`. Test : `scripts/test_banc_chaine_reactions.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_chaine_reactions`.

PREMIÈRE DÉMONSTRATION RÉELLE de `scripts/reaction.gd` (chantier « composition en profondeur — chaînage automatique de réactions », voir `CARTE.md` §2 et `banc_chaine_reactions`) :

MODÈLE ASYMÉTRIQUE (décision Yael, question posée avant d'écrire — la
consigne d'origine disait transformer les deux réactifs, contredite par
son propre exemple narratif « l'eau reste de l'eau ») : dans une entrée
`{ materiau_a, materiau_b }`, `materiau_a` (source/catalyseur) n'est
JAMAIS transformé, seul `materiau_b` (la cible) le devient.

BUG TROUVÉ EN ÉCRIVANT `reaction.gd`, CORRIGÉ DANS LE MÉCANISME LUI-MÊME :
`produit.gd:transformer` ne refusionne jamais les propriétés immuables de
composition sur l'objet neuf (constat déjà posé par le chantier « Produit
nucléaire »). Sans correctif, un produit de réaction perdait sa
`reactivite` et ne pouvait plus jamais réagir — le chaînage à plus d'un
étage était structurellement impossible. `reaction.gd` repose
`reactivite` depuis la fiche matériau du produit après chaque
transformation.

**Montre.** acide_demo et eau_demo de part et d'autre de fer
(fixe), tous trois RÉELS. Un clic gauche RAPPROCHE les trois : acide_demo
+ fer -> sel_metallique (entrée déjà connue de `banc_reactivite.gd`),
puis, AU TICK SUIVANT, sel_metallique (à la position d'origine de fer) +
eau_demo -> sel_dissous — cascade à deux étages, jamais dans le même
appel. acide_demo et eau_demo ne changent jamais de matériau. Un second
clic ÉLOIGNE les trois : hors `portee_reaction`, rien n'accumule, rien ne
se transforme, même après l'avoir déjà été. Label par objet : matériau,
réactivité, `profondeur_chaine`, charge du canal `reaction` s'il existe.
Trace console à chaque bascule de position et à chaque transformation.

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

## banc_maladie — neuf colons, un patient zéro, la maladie se propage de proche en proche puis tue

`Scene/banc_maladie.tscn`, `scripts/banc_maladie.gd`, `data/banc_maladie.json`. Test : `scripts/test_banc_maladie.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_maladie`.

**Montre.** neuf colons (ColorRect) errant aléatoirement (RNG
seedée) dans une zone. Le patient zéro démarre orange (déjà malade, aucune
incubation). Un colon sain à portée d'un porteur devient jaune (incubation
— déjà contagieux, aucun symptôme visible), puis orange après l'incubation
(vitesse réduite ×0.3), puis rouge et immobile s'il meurt (sous la
calibration réelle du banc, la mort arrive systématiquement avant toute
guérison naturelle — voir plus bas). Compteur en haut d'écran
(sains/incubation/malades/morts). Label par colon : nom, état, vitesse
effective, charge du canal maladie, porteur oui/non. Trace console à
chaque contamination (avec le nom de l'infecteur), passage aux symptômes,
guérison, mort. Clic gauche : pause/reprend toute la simulation — aucune
infection manuelle, la propagation est entièrement autonome.

CHAÎNE DE CONTAGION SANS ÉTAT `_avant` (différence avec banc_toxicite) :
un colon qui sort du pool des receveurs de `charge.gd` dès sa contamination
(son canal `etats.maladie` est retiré) ne peut plus jamais y rebasculer —
chaque bascule rendue par `Charge.avancer` est donc déjà une contamination
fraîche, jamais besoin de comparer un état avant/après. Un porteur reste
une cause de contagion pour les autres PENDANT toute son incubation, avant
même ses propres symptômes — vérifié : un porteur en incubation contamine
un troisième colon.

CALIBRATION ASSUMÉE : `seuil_mort` (16.0s) délibérément sous
`maladie_duree_s` (20.0s) — un colon malade meurt avant de guérir
naturellement, cohérent avec l'absence de tout mécanisme de traitement
dans ce banc. La réversibilité de `malade` (guérison si le seuil de mort
n'est jamais atteint) n'est donc jamais observée EN DIRECT dans ce banc —
prouvée seulement par le test, même statut que la réversibilité de
`charge.gd` dans banc_contagion. `seuil_mort` est un INTERRUPTEUR, pas un
curseur : dès qu'il dépasse `maladie_duree_s`, `malade` expire avant la
mort et le banc passe de létalité totale à létalité NULLE, sans palier
(mesuré).

RÉSULTAT NÉGATIF, à ne pas refaire (détail chiffré dans le `_note` de
data/banc_maladie.json) : la calibration d'origine du canal (`seuil` 3.0,
`taux_decroissance` 1.0) ne contaminait JAMAIS personne — trois valeurs se
contredisaient (3s de contact exigées, croisement de ~2s au mieux, et 16s
de fenêtre avant que l'unique porteur meure). Le seuil est le verrou :
1.5 suffit. ÉCARTÉ, mesuré : cumuler `portee_charge` 100 par-dessus rend la
chaîne « qui infecte qui » illisible (six contaminations en moins de 6s).
`taux_decroissance` 0.0 est un choix de modélisation (une dose reçue ne
s'efface pas quand on s'éloigne), sans effet mesuré sur l'issue. ÉCARTÉ,
doctrinal : faire croître la charge SEULE sous le seuil — la distance et la
durée de contact cesseraient de protéger, et il faudrait un cinquième verbe
dans `charge.gd` ; au-dessus du seuil l'infection s'auto-entretient déjà
(canal `etats` retiré, `duree_maladie_cumulee` monte sans aucune source).

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

## banc_ecoulement — une grille de terrain en pente, l'eau coule de case en case puis s'infiltre ou s'évapore

`Scene/banc_ecoulement.tscn`, `scripts/banc_ecoulement.gd`, `data/banc_ecoulement.json`. Test : `scripts/test_banc_ecoulement.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_ecoulement`.

**Montre.** une grille 8×8 de cases (ColorRect), montagne à
gauche (altitude_max) descendant vers une vallée à droite (altitude_min),
moitié gauche en terre (perméable, brun), moitié droite en roche
(imperméable, gris). De l'eau posée sur les 8 cases de la colonne de
gauche (eau_initiale=10.0) coule case en case vers le bas de la pente
(scripts/ecoulement.gd, hauteur = altitude + eau, jamais en sens inverse),
chaque case changeant de couleur (sec → bleu saturé) et de niveau de barre
verticale selon sa réserve d'eau. Compteur en haut : eau totale du
système, qui descend au fil du temps (absorption+évaporation, jamais
l'écoulement seul qui ne fait que déplacer l'eau — la terre absorbe
nettement plus vite que la roche). Label de détail (altitude/niveau_eau/
permeabilite/type_sol) sur la case survolée. Clic gauche : ajoute
ajout_clic (5.0) sur la case sous la souris. Trace console par seconde
(transferts/eau totale/absorbée/évaporée).

TERRAIN EN OBJETS ORDINAIRES (résout `docs/design.md`, « Propagation et
terrain » — TRANCHÉ par ce chantier) : la grille est 64 cases-objets `{
id, position, proprietes }` construites À LA MAIN (pas Objet.fabriquer —
une case n'a pas de composition, même statut que banc_maladie/
banc_toxicite), enregistrables dans monde.gd comme n'importe quel autre
objet — aucune structure de terrain séparée. position reste un FAIT
SPATIAL PUR (x=colonne, y=ligne, z=0.0 toujours) ; l'altitude vit dans
proprietes.altitude, DÉCOUPLÉE de position (décision Yael, question posée
avant d'écrire — voir CARTE.md `banc_ecoulement` pour la contradiction de
calibration qui a motivé ce découplage).

BUG TROUVÉ EN ÉCRIVANT scripts/ecoulement.gd, depuis FERMÉ dans
consommer.gd (conservatif par construction — il crédite la quantité
réellement retirée, plus jamais la quantité demandée) : le pré-bornage
d'ecoulement.gd est resté en place, désormais redondant. Voir CARTE.md §2,
entrée consommer.gd.

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

## banc_erosion — l'eau et le vent emportent le sol, qui se dépose en aval sans jamais disparaître

`Scene/banc_erosion.tscn`, `scripts/banc_erosion.gd`, `data/banc_erosion.json`. Test : `scripts/test_banc_erosion.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_erosion`.

**Montre.** une grille 8×8 en pente (montagne colonne 0 à
gauche, vallée à droite), chaque case portant la même réserve de sol au
départ. La couleur dit l'épaisseur de sol (brun foncé = beaucoup, brun
clair = peu, gris = roche nue), une superposition bleue dit l'eau, une
flèche affiche le vent, un label par case donne sol / couvert végétal /
niveau d'eau. L'eau posée sur la colonne 0 coule vers le bas de la pente
et emporte du sol au passage ; un vent constant de gauche à droite emporte
le sol NU. La moitié gauche porte un couvert végétal (0.8) et résiste ; la
moitié droite est nue et s'érode vite. Le sol emporté se dépose en aval :
le compteur de sol total ne bouge jamais — c'est la preuve visible de la
conservation. Clic gauche : ajoute de l'eau sur la case sous la souris.

RÉSULTAT NÉGATIF, à ne pas refaire : appeler une seconde fois
Ecoulement.avancer avec nom_reserve="sol" compile et tourne, mais applique
une loi fausse — `_hauteur()` vaut altitude + réserve, le sol coulerait
donc de sa propre gravité, indépendamment de l'eau (de la boue, pas de
l'érosion).

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

## banc_succession — un terrain nu qui devient prairie, taillis puis forêt, et qu'un feu ramène à zéro

`Scene/banc_succession.tscn`, `scripts/banc_succession.gd`, `data/banc_succession.json`. Test : `scripts/test_banc_succession.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_succession`.

**Montre.** une grille 6×6 de cases (ColorRect) entièrement
brune au départ (tout le monde au stade `nu`), qui verdit par vagues —
vert clair (`prairie`) vers 0,5 s, vert moyen (`taillis`) vers 2 s, vert
foncé (`foret`) vers 7,5 s à annees_par_seconde=8.0. La DERNIÈRE COLONNE
est stérile (croissance_possible=false) et reste brune indéfiniment,
juste à côté de cinq colonnes qui progressent : c'est la preuve visible
du vieillissement conditionnel. Chaque case affiche son stade et son âge
en années ; un compteur en haut donne le nombre de cases par stade. Un
clic gauche brûle la case sous la souris et ses 8 voisines immédiates :
elles repassent brunes et refont TOUTE la succession depuis zéro pendant
que le reste de la grille continue de vieillir. Trace console à chaque
changement de stade et à chaque feu.

STADES EXCLUSIFS, ET POURQUOI PAS seuil_etat.gd : proprietes.stade est UNE
String écrite par scripts/stade.gd — jamais deux stades actifs en même
temps. Un escalier de data/seuils_etat.json aurait laissé `prairie` ET
`taillis` ET `foret` tous actifs au-delà du dernier seuil (comportement
voulu et documenté de seuil_etat.gd, voir `liquide`/`gaz` de
banc_changement_etat). C'est la raison d'être de stade.gd.

LE FEU EST UN CLIC, PAS UNE PROPAGATION : propagation.gd:avancer rend
l'Array des ids nouvellement enflammés et ferait un déclencheur légitime,
mais il n'est PAS câblé ici — ce banc montre la succession et sa remise à
zéro, pas la transmission du feu. Le câblage écrit directement age=0.0 ET
stade=<premier stade>; les DEUX écritures sont obligatoires, stade.gd
refusant tout retour en arrière (il compare des index dans stades_config,
un âge remis seul laisserait le stade figé et bloquerait la remontée pour
toujours).

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

Vérifié (headless, test_banc_succession.gd + suite complète, 132 tests
VERT, aucune régression, + scène réelle headless 10 s) : une case fertile
traverse exactement nu → prairie → taillis → forêt dans cet ordre ; elle
ne porte à tout instant qu'UN seul stade du catalogue, et aucun nom de
stade ne devient jamais une propriété à part ; un feu remet age à 0.0 et
stade au premier stade ; après le feu la succession est intégralement
rejouée ; à annees_par_seconde=0.0 l'âge ne bouge d'aucun iota sur 200 s
simulées ; la colonne stérile reste immobile pendant que les autres
atteignent forêt ; un feu au centre d'une grille 5×5 brûle exactement 9
cases et aucune au-delà ; une case stérile brûlée reste stérile ; en
scène réelle, les 30 cases fertiles franchissent les trois seuils à
t=0,5 s / 2,0 s / 7,5 s et les 6 cases stériles n'apparaissent dans
aucune trace.

## banc_cratere — un impact creuse le terrain, l'eau s'y accumule, puis la trace s'efface et l'eau repart

`Scene/banc_cratere.tscn`, `scripts/banc_cratere.gd`, `data/banc_cratere.json`. Test : `scripts/test_banc_cratere.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_cratere`.

**Montre.** une grille 6×6 de cases brunes, terrain PLAT
(altitude uniforme — le seul relief du banc vient du creusement). De l'eau
posée sur la ligne du haut (eau_initiale=12.0) se répand jusqu'à un niveau
à peu près uniforme (teinte bleue). Bouton « FRAPPER LE CENTRE » (ou clic
gauche n'importe où) : frappe.gd:frapper vide l'intégrité de la case
case_3_3, le câblage traduit le franchissement en creusement=2.0 — la case
vire au noir et l'eau s'y accumule, son niveau montant au-dessus de celui
de ses quatre voisines. trace_age décompte à l'écran (8.0 → 0.0, une
seconde par seconde) ; à zéro le cratère disparaît d'un coup, la case
redevient brune et l'eau accumulée repart vers les voisines. Label par
case : alt / creus / trace / eau. Compteur en haut : eau totale (constante
— aucune absorption ni évaporation ici, contrairement à banc_ecoulement) et
nombre de cratères actifs. Console : une ligne par impact, une par
effacement, une par seconde.

TROIS PROPRIÉTÉS D'ALTITUDE, TROIS CONTRATS DISJOINTS : `altitude` (base,
JAMAIS réécrite), `creusement` (la trace, écrite par le câblage, remise à
0.0 par depense.gd), `altitude_effective` (dérivée chaque tick,
altitude − creusement — la SEULE passée à Ecoulement.avancer ;
ecoulement.gd ne connaît pas `creusement`). Voie (b) de, préférée à la restauration
d'altitude par le catalogue : `poser()` n'écrit qu'une CONSTANTE partagée,
donc incapable de restaurer l'altitude d'une case en pente — restaurer un
creusement, toujours 0.0, reste exact.

L'EFFACEMENT EST FAIT PAR depense.gd LUI-MÊME : l'entrée neuve
`data/seuils_combustible.json:effacement_trace` est la seule du fichier
dont `poser()` écrit une valeur numérique (`creusement : 0.0`) et non un
marqueur booléen. Le câblage ne remet donc jamais creusement à zéro — il ne
fait que croiser les ids rendus par Depense.avancer avec les cases qui
étaient creusées AVANT l'appel, pour la trace console. L'impact, lui,
recharge trace_age et VIDE ses seuils_franchis (sans quoi depense.gd
n'effacerait jamais un second cratère) et RÉARME l'intégrité du sol (sans
quoi une case ne serait creusable qu'une seule fois de toute la vie du
banc) — deux décisions de câblage assumées, absentes de la consigne.

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

## banc_simulation_acceleree — le terrain vieillit de milliers d'années en quelques secondes, puis le joueur arrive sur un monde qui a une histoire

`Scene/banc_simulation_acceleree.tscn`, `scripts/banc_simulation_acceleree.gd`, `data/banc_simulation_acceleree.json`. Test : `scripts/test_banc_simulation_acceleree.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_simulation_acceleree`.

**Montre.** une grille 8×8 en pente (sommet à gauche,
altitude_max ; bas de pente à droite, altitude_min), moitié gauche en terre
perméable, moitié droite en roche imperméable, de l'eau posée au sommet.
Au démarrage le banc est en mode ACCÉLÉRÉ : le compteur d'années grimpe de
milliers d'années en quelques secondes, chaque case traverse nu → prairie →
taillis → forêt (couleur du stade, lue en donnée) pendant que l'eau descend
la pente, s'accumule en bas, s'y stabilise, et que le sol l'absorbe
lentement (eau totale qui décroît). Un clic gauche bascule en TEMPS RÉEL :
même code, une seule itération par tick, facteur d'échelle lent — le joueur
arrive alors sur un monde qui a déjà une histoire. Label du haut : années
simulées, mode courant, iterations_par_tick et le facteur d'échelle en
vigueur. Compteur : cases par stade, eau totale. Label de détail au survol.
Trace console au changement de mode et tous les 1000 ans simulés.

LE PATRON QUE CE BANC DÉMONTRE (doctrine, docs/design.md « Simulation
accélérée ») : accélérer le temps = répéter un delta PETIT et FIXE
(delta_fixe 0.016 s, iterations_par_tick fois par tick) en montant un
FACTEUR D'ÉCHELLE (annees_par_seconde), JAMAIS agrandir le delta — à grand
delta temperature.gd diverge et ecoulement.gd devient non physique
(consommer.gd était le troisième — il perdait la conservation, corrigé
depuis, voir CARTE.md §2). Le test le rend visible : à âge simulé
ÉGAL, N pas petits et un pas géant laissent deux états d'eau DIFFÉRENTS.

DEUX HORLOGES DÉCOUPLÉES : senescence.gd est le seul mécanisme en ANNÉES,
tous les autres en SECONDES DE SIMULATION. Un tick accéléré avance de 120
années de succession mais de 0,4 seconde d'hydrologie. « 33 000 années
simulées » ne se lit jamais « 33 000 années de pluie ».

TEMPÉRATURE ABSENTE PAR CHOIX DOCTRINAL : aucune case ne porte temperature,
temperature.gd n'est jamais appelé — la divergence est impossible PAR
CONSTRUCTION, et un test le verrouille positivement. La rendre sûre à grand
delta demanderait de sous-échantillonner le mécanisme en interne, donc de
toucher le cœur : hors périmètre, à trancher par Yael avant d'écrire.

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

DÉBIT MESURÉ, PAS GARANTI : iterations_par_tick a été fixé à 25 et non 100
sur MESURE — Ecoulement.avancer est en O(cases²) par itération, et à 100 le
banc ne tenait que ~35 années/s, la promesse « milliers d'années en quelques
secondes » était fausse. Résultat négatif à ne pas refaire : le débit en
années NE DÉPEND PAS de iterations_par_tick (doubler N divise les ticks par
deux, le produit est constant), seulement de annees_par_seconde ; N ne règle
que la finesse du pas physique et la fluidité du rendu.

## banc_fertilite — le sol s'épuise sous la récolte et se refait par la jachère, la légumineuse et les morts

`Scene/banc_fertilite.tscn`, `scripts/banc_fertilite.gd`, `data/banc_fertilite.json`. Test : `scripts/test_banc_fertilite.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_fertilite`.

**Montre.** une grille 4×4 de cases de terrain colorées par leur
fertilité (vert foncé = fertile, jaune = appauvri, rouge = épuisé), chacune
labellée fertilité / zone / source active. Quatre zones, quatre destins
simultanés :
- RÉCOLTE (2 cases, en haut à gauche) — la fertilité chute vite dès
 l'ouverture (la récolte est active au départ). Un clic gauche l'ARRÊTE :
 la case se refait doucement. Un second clic la relance. L'autre case de
 la même zone n'est jamais affectée par le clic.
- LÉGUMINEUSE (2 cases) — un objet legumineuse_demo posé entre les deux les
 recharge en continu jusqu'au plafond (100), où elles s'arrêtent net.
- CADAVRE (2 cases) — un cadavre_demo posé sur chacune lui transfère sa
 matière organique, exactement (ce que le cadavre perd, le sol le gagne).
 Le petit cadavre se vide vers t≈8 s, devient un humus inerte (couleur et
 label changent), et sa case cesse alors de monter — rien ne repart.
- JACHÈRE (10 cases) — remontent lentement, sans aucune source.
Compteur en haut : fertilité moyenne. Trace console par seconde (moyenne,
min/max nommés, transferts, total écrêté au plafond).

QUATRE MÉCANISMES DÉJÀ FERMÉS, AUCUN.gd NEUF : depense.gd descend (et REMONTE —
un cout_base négatif fait monter la réserve, exactement comme un taux_flux
négatif la fait descendre dans flux.gd : c'est ainsi que la jachère se
refait, sans une ligne de code neuve), flux.gd remonte par source ambiante
sans jamais dépléter sa source (une légumineuse fixe l'azote de l'AIR),
consommer.gd remonte par transfert conservé depuis un cadavre, produit.gd
transforme le cadavre vide en humus. Le cadavre perd une RÉSERVE NOMMÉE
(matiere_organique), JAMAIS sa masse — masse/volume/densite sont des
sorties dérivées de la composition, interdites en écriture. L'appariement
« la case sous le cadavre » est une boucle de CÂBLAGE (comparaison de
positions), jamais un mécanisme : consommer.gd exige que l'appelant ait
déjà apparié source et receveur.

LE PLAFOND EST DU CÂBLAGE, PAS UN MÉCANISME : depense.gd borne le bas
(0.0), rien dans le cœur ne borne le haut — ni flux.gd ni consommer.gd ne
connaissent de capacité. Le banc écrête après chaque pas ; le surplus est
perdu (un sol saturé ne stocke pas plus), visible sur les cases légumineuse
qui butent à 100.

BUG DE consommer.gd, DEUXIÈME OCCURRENCE, depuis FERMÉ DANS LE MÉCANISME :
Consommer.transferer créditait au receveur la quantité DEMANDÉE, pas celle
réellement retirée à la source une fois bornée à zéro — trouvé par le test
de ce chantier (le sol recevait 6.08 pour un cadavre de 6.00), après
ecoulement.gd qui s'en était déjà protégé. C'était bien une dette du
mécanisme : consommer.gd est maintenant conservatif par construction
(CARTE.md §2, entrée consommer.gd). Le pré-bornage de banc_fertilite.gd est
resté en place, désormais redondant.

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

## banc_ombre_pluvio — la mer arrose la plaine, la montagne porte une ombre sèche derrière elle

`Scene/banc_ombre_pluvio.tscn`, `scripts/banc_ombre_pluvio.gd`, `data/banc_ombre_pluvio.json`. Test : `scripts/test_banc_ombre_pluvio.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_ombre_pluvio`.

**Montre.** une grille 10×6 de cases (ColorRect), une mer
dessinée hors grille à gauche (source unique, humidite_emission=60.0,
alignée sur la ligne du sommet) et une montagne de trois cases au centre
(colonne 4, lignes 1-2-3 : un sommet à altitude 14.0 encadré de deux
épaules à 8.0). Chaque case reçoit, chaque tick, l'intensité rendue par
scripts/champ_occulte.gd — atténuée par la distance à la mer (loi en 1/d,
scripts/occlusion.gd) ET par ce qui se dresse sur le segment
mer→case (occlusion). Couleur du jaune (sec) au bleu (humide), gradient
continu ; cases de relief en brun d'autant plus sombre qu'elles bloquent,
dessinées PLUS HAUTES que les autres ; label par case (humidité,
relief_bloquant) ; flèche de vent en haut ; label de détail
(humidite/relief_bloquant/altitude) sur la case survolée.

Devant la montagne : de 15.00 (colonne 0, sur l'axe) à 7.50 (colonne 4) —
la seule décroissance est celle de la distance. Derrière : à la colonne 9,
1.54 sur l'axe mer→sommet, 3.07 une ligne à côté, 4.50 au bord de la
grille. L'ombre est GRADUÉE, jamais une coupure — même la case la plus
sèche garde une humidité strictement positive. Ce qui s'estompe, c'est la
PROFONDEUR de l'ombre quand on s'écarte de l'axe ; le cône d'ombre, lui,
S'ÉLARGIT avec la distance (source ponctuelle, occulteur dur, aucune
pénombre).

Clic gauche : bascule l'occlusion (relief ACTIF/INACTIF). C'est la
comparaison avant/après qui rend l'ombre lisible d'un coup d'œil — relief
INACTIF, la colonne 9 remonte à 4.62/4.60/4.50 sur les trois mêmes lignes.
C'est la seule chose qui bouge : le champ est une fonction PURE des
positions, rien n'y évolue avec le temps.

Trace console : la grille complète d'humidités à la pose et à chaque
bascule, puis une ligne de trois témoins (devant / derrière-axe /
derrière-bord) toutes les 2 s. C'est la seule façon d'observer ce banc en
headless.

Le vent est un DÉCOR : la flèche et son libellé viennent de
vent_direction/vent_force, ce banc n'appelle jamais scripts/vent.gd et le
vent n'entre dans aucun calcul (champ_occulte.gd n'a pas de paramètre de
vent). Une humidité PORTÉE par le vent serait un autre chantier.

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

## banc_biomes — le climat décide le terrain, et le lui reprend quand il change

`Scene/banc_biomes.tscn`, `scripts/banc_biomes.gd`, `data/banc_biomes.json`. Test : `scripts/test_banc_biomes.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_biomes`.

**Montre.** une grille 6×6 de cases (ColorRect) où l'humidité
croît vers la DROITE (colonnes, 0.05 → 0.95) et la température vers le BAS
(lignes, 0 → 35 °C). Deux axes croisés, donc les cinq rendus possibles
présents dès le démarrage, sans aucun clic : jaune (désert), vert foncé
(forêt), blanc (toundra), bleu-vert (marais), brun (aucun biome). SIX depuis
que le chantier « refuge + extinction + capacité de charge + territoire » a
ajouté une entrée `prairie` à data/biomes.json (catalogue PARTAGÉ) : elle prend
6 des 18 cases qui ne portaient aucun biome, il en reste 12, et sa couleur
(vert clair) a été ajoutée à data/banc_biomes.json pour qu'elle ne s'affiche
pas comme une absence. Ses conditions sont disjointes des quatre autres :
aucune case ne change de biome. Label par
case (humidité, température, biome) ; compteur des cases par biome en haut ;
trace console à chaque CHANGEMENT de biome d'une case, jamais son état.

Ce qu'il prouve, et que banc_emergences ne pouvait pas montrer : la
RÉVERSIBILITÉ. `objet.gd:_evaluer_emergences` n'évalue qu'une fois, à la
naissance de l'objet, et ne retire jamais rien. Ici `Conditions.evaluer` est
rejoué CHAQUE TICK sur chaque case avec `retirer_si_faux=true` — une forêt
refroidie perd son biome puis devient toundra, et le retrouve à l'identique
si on la réchauffe.

**Contrôles.** clic gauche +5 °C, clic droit −5 °C sur TOUTE la grille,
cumulatif (jamais bistable : un toggle de sens n'aurait pas permis de
descendre une forêt à 14 °C sous le seuil de 5 °C, donc le banc n'aurait
rien pu montrer). Flèches Haut/Bas : ±0.1 d'humidité globale — AJOUT hors de
la consigne d'origine, seul moyen de rendre observable « le marais devient
désert » (désert exige humidité<0.2, marais ≥0.8 : l'écart est
infranchissable par la seule température).

Le climat ne dérive jamais : chaque case garde ses valeurs de BASE, posées
une fois à la construction et jamais mutées ; l'humidité/température
effective est recalculée chaque tick comme base + décalage global
(`appliquer_climat`, PURE et IDEMPOTENTE). L'humidité est bornée à [0,1],
la température ne l'est pas.

Calibration assumée, verrouillée par le test : 18 des 36 cases n'ont AUCUN
biome au repos. Ce n'est pas un mauvais réglage du gradient mais la lecture
directe des conditions de data/biomes.json, qui ne pavent pas tout l'espace
climatique (bande humidité 0.2–0.5 à température tempérée). Le brun rend
cette absence VISIBLE plutôt que d'inventer un biome par défaut.

Un seul chevauchement entre les quatre entrées : `foret` (h≥0.5, 10≤t≤30) et
`marais` (h≥0.8, t≥5) sont toutes deux vraies dès h≥0.8 et 10≤t≤30 —
`marais` est déclarée APRÈS exprès, la plus spécifique gagne. C'est l'ordre
du catalogue qui tranche, jamais le code.

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

## banc_fatigue_circadien — la fatigue descend et remonte, l'heure dit quand dormir, et se soigner n'est pas se reposer

`Scene/banc_fatigue_circadien.tscn`, `scripts/banc_fatigue_circadien.gd`, `data/banc_fatigue_circadien.json`. Test : `scripts/test_banc_fatigue_circadien.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_fatigue_circadien`.

**Montre.** deux colons. En haut, une bande d'horloge sur 24 h
avec la zone de sommeil (16 h → 8 h) en sombre et un curseur rouge qui la
parcourt ; le fond de l'écran s'assombrit quand on y entre. Sous chaque colon,
trois barres — sommeil, santé, dette de sommeil — et un label qui liste ses
états réellement actifs. Trace console par seconde, plus une ligne à chaque
bascule (entrée/sortie de zone, epuise posé/retiré, dette franchie/résorbée,
expiration d'état, endormissement/réveil).

`colon_actif` patrouille. Sa fatigue descend d'un coût de veille constant plus
un surcoût proportionnel à son mouvement RÉEL (la vélocité dérivée par
velocite.gd, jamais un nombre posé à la main) : il tombe sous le seuil
d'épuisement en une douzaine de secondes, gagne l'état `epuise`, et ralentit
visiblement — sans qu'aucune branche `if epuise` n'existe, sa patrouille étant
cadencée par sa vitesse EFFECTIVE (etat_effectif.gd).

`colon_blesse` ne bouge pas et part à 25 de santé. Sa santé remonte pendant
que sa fatigue descend jusqu'à zéro : les deux réserves sont deux canaux du
même Dictionary `reserves`, avancés par depense.gd sans qu'aucun ne connaisse
l'autre. La séparation est structurelle, pas une précaution — c'est la
démonstration centrale de « se soigner n'est pas se reposer ».

**Contrôles.** clic gauche sur un colon = toggle du sommeil. Endormi, il cesse de
bouger et sa fatigue REMONTE — un `cout_base` NÉGATIF sur le même canal, la
neutralité de depense.gd exploitée, jamais contournée (patron de la jachère de
banc_fertilite). Au réveil il repart d'où il s'était arrêté, jamais un saut :
l'horloge de patrouille est propre au colon et ne tourne que lorsqu'il veille.
Le blessé est cliquable comme l'autre, délibérément — l'endormir montre qu'il
récupère alors AUSSI sa fatigue : les deux réserves sont indépendantes, pas
mutuellement exclusives.

**Prouve.** une zone qui ENJAMBE MINUIT
n'est pas un seuil. « heure ≥ 16 OU heure ≤ 8 » s'écrit en deux entrées de
conditions.gd posant TOUTES DEUX la clé `doit_dormir`, rejouées chaque tick
avec retirer_si_faux=true. À 20 h l'entrée « ≤ 8 » est FAUSSE : en une seule
passe elle effacerait ce que l'entrée « ≥ 16 » vient de poser. banc_biomes
montrait la réversibilité de conditions.gd ; celui-ci montre la raison d'être
de ses DEUX PASSES DISJOINTES.

Veiller en zone de sommeil accumule une DETTE (charge.gd) dont la cause est
SYNTHÉTISÉE par le câblage : le colon lui-même, à portée 0.0, quand
`doit_dormir` est vrai et qu'il ne dort pas. Elle redescend toute seule hors
zone. Au franchissement, charge.gd pose un marqueur sur proprietes (jamais
dans etats_actifs) que le câblage relaie vers un état à durée reposé chaque
tick — idiome littéral de nausee_radiation ; dès que le marqueur tombe, plus
personne ne repose l'état et son intensité s'épuise seule.

Écarté doctrinal, à ne pas reproposer : la fatigue comme charge.gd (voie (a)
de l'audit). Elle marcherait, mais design.md range `sommeil` parmi les cinq
canaux de `reserves` du paquet `dynamique` — « descend en continu, se recharge
au contact d'une source ». Une charge et une réserve ne sont pas le même
compteur (proprietes.etats.<nom>.charge contre
proprietes.reserves.<nom>.reserve) et il ne faut jamais mettre les deux.

Limite assumée, dite plutôt que masquée : la cause de dette est à portée 0.0,
donc deux colons SUPERPOSÉS se chargeraient mutuellement. Les positions
déclarées en donnée sont distinctes, et un test le verrouille à l'envers (deux
veilleurs accumulent 1.0 chacun, jamais 2.0).

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

## banc_faim_thermo — il marche, il a froid, il a faim, et il n'y a rien à manger

`Scene/banc_faim_thermo.tscn`, `scripts/banc_faim_thermo.gd`, `data/banc_faim_thermo.json`. Test : `scripts/test_banc_faim_thermo.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_faim_thermo`.

**Montre.** un colon (carré clair) qui marche sans fin entre des
points tirés au sort, sur un terrain à trois fonds — disque bleu à gauche (zone
froide), disque rouge à droite (zone chaude), vert entre les deux (neutre). Son
énergie ne peut que DESCENDRE : rien dans ce banc ne la recharge. Label attaché
au colon : énergie / capacité, manque_energie, vitesse effective face à sa base,
surcout_action DÉCOMPOSÉ (effort + thermo), température locale, froid_ressenti
et chaud_ressenti, liste des états actifs. Compteur en haut : énergie restante,
secondes avant famine, secondes avant arrêt — projections au taux courant,
jamais des prédictions. Trace console à chaque état posé ou retiré.

**Prouve.** TROIS SURCOÛTS
SUR UN SEUL EMPLACEMENT. depense.gd n'a qu'un `surcout_action` par canal ;
l'effort, le froid et le chaud veulent tous les trois y écrire sur la même
réserve. `poser_surcout_action` en est l'UNIQUE ÉCRIVAIN : elle somme puis
écrit une fois, et rend la décomposition que le label relit sans jamais rien
recalculer. Trois morceaux de câblage séparés se seraient écrasés EN SILENCE —
aucun test n'aurait rougi, la dépense aurait seulement été fausse.

**Prouve aussi.** les MIROIRS PLATS RÉVERSIBLES. seuil_etat.gd ne lit
qu'une clé plate et ne compare que vers le haut — « l'énergie descend sous un
seuil » n'est pas exprimable. Le câblage écrit chaque tick trois propriétés qui
MONTENT quand la situation empire (manque_energie, froid_ressenti,
chaud_ressenti), recalculées à neuf et jamais accumulées par `+=`. C'est ce qui
les distingue de toutes les grandeurs cumulées du dépôt et ce qui rend les
quatre états réversibles sans une ligne de plus. Visible en direct sur le
froid : frisson puis hypothermie en entrant dans le bleu, retirés dans l'ordre
INVERSE en en sortant.

temp_cible vaut 20.0, pas 37.0 — écart assumé à la valeur citée par l'audit
préalable. C'est une température de CONFORT, pas celle d'un corps : l'ambiante
partagée de data/temperature.json valant 20.0, un confort à 37 aurait donné 17
de froid_ressenti PARTOUT, donc hypothermie permanente jusqu'au cœur de la zone
chaude, et le banc n'aurait plus rien montré.

Deux miroirs thermiques distincts, jamais un abs() unique (question laissée
ouverte par l'audit, tranchée ici) : le froid bascule sous temp_cible (20.0), le
chaud au-dessus de seuil_chaud (26.0), avec deux coûts par degré différents.
Entre les deux, une bande où seuls le métabolisme et la marche coûtent.

La température du CORPS n'existe pas ici : temperature.gd:avancer n'est jamais
appelé et le colon ne porte aucune propriété `temperature`. Conséquence utile,
verrouillée positivement par test : les entrées thermiques du catalogue partagé
(point_fusion, chaud…) sont pour lui des chemins morts, aucun état parasite ne
peut se poser. L'inertie thermique du corps serait un autre chantier.

L'arrêt final est un gate de câblage, pas un état : réserve à 0.0 → vitesse
effective 0.0. Aucun état « épuisé » n'a été ajouté au catalogue partagé — la
consigne n'en demandait pas, et un état de plus se paie pour tout le dépôt.

**Ne montre pas.** la réversibilité de
`affame`. Il n'y a aucune nourriture — l'énergie ne remonte jamais. Elle est
prouvée par le test seul (réserve remontée à la main, l'état est retiré), même
statut que la guérison de `malade` dans banc_maladie.

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

---

## banc_hygiene_apparence — un colon qui ne se lave plus finit par sentir, et les autres s'écartent

`Scene/banc_hygiene_apparence.tscn`, `scripts/banc_hygiene_apparence.gd`,
`data/banc_hygiene_apparence.json`. Chantier « hygiène + apparence —
perception sociale » (lignes 9 et 13,
livrées ensemble).

**Montre.** Quatre colons errent. L'un ne se lave
jamais : sa réserve `hygiene` descend, franchit un seuil, il devient `sale`,
se met à émettre une odeur, et les trois autres s'écartent dès qu'ils le
perçoivent. En parallèle, un deuxième colon est `blessé` : il est
VISUELLEMENT repérable — le colon attentif le remarque de loin, le distrait
seulement de près — et n'est jamais fui, parce qu'aucun verbe ne se résout
sur `blesse`. Un clic lave tout le monde : l'état se retire, l'odeur cesse,
et le cycle peut recommencer.

**Ce qui est neuf.** Deux canaux de `data/canaux.json` :
`odeur_corporelle` (aucune occlusion — une odeur contourne un mur) et
`apparence` (occlusion par `opacite` — un mur cache un colon). Deux états de
`data/etats.json` (`sale`, `blesse` — marqueurs purs), une entrée
`data/seuils_etat.json:hygiene`, une entrée `data/types_choses.json:sale`
(verbe `s_eloigner`). **Aucun mécanisme du cœur touché ni créé.**

**Écarté, à ne pas reproposer.** Faire porter l'odeur variable par le canal
`odorat` existant : sa géométrie `sphere_directionnelle` est la SEULE
porteuse de la modulation par le vent et ne lit ni `propriete_emission` ni
`seuil` — la basculer retirerait le vent à l'odorat en silence, dans un
catalogue partagé. Un canal neuf est la seule voie qui ne touche pas au cœur.

**Écarté, mesuré.** Laisser aux colons les six canaux de `percevant` :
`vue` a une portée de 1600 et aucun filtre d'intensité, elle ferait capter
tout colon par tout colon à toute distance et ni l'odeur ni le seuil
d'apparence ne prouveraient plus rien. La liste `canaux` est donc REMPLACÉE
par deux noms, localement, après fabrication.

**Ce qui borne réellement la fuite, et ce n'est pas la perception.** Une
entrée n'est fuyable que si elle survit à `Proximite.evaluer`, et
`data/profils_saillance.json:colon` borne la saillance inter-colon à 350.
Le colon attentif PERÇOIT le colon sale jusqu'à 600 (apparence) mais ne le
FUIT qu'à partir de 350 ; les deux autres ne le perçoivent que par l'odeur
(285). Visible en console : `colon_attentif : fuit (personne) | perçoit
colon_blesse, colon_sale`.

**Ce qui manque encore pour observer plus.** Le mur ne bloque aucun
déplacement (aucune collision dans ce dépôt) : un colon le traverse, et
l'occlusion d'`apparence` n'est donc visible qu'au passage. `malnutri`
n'existe pas encore comme état (audit ligne 3, autre chantier) — le jour où
il existera, il rejoint `emission_apparence` en une ligne de donnée, sans
code.

**Lecture signalée à Yael, non tranchée par lui.** La consigne disait
« toggle au clic » mais décrivait un événement ponctuel (« hygiène remise à
capacité ») — une remise à la capacité n'a rien vers quoi rebasculer.
Implémenté en CLIC PONCTUEL, répétable ; même lecture que `banc_succession`.

**Lancer:**

 & "<chemin godot>" --path . --scene Scene/banc_hygiene_apparence.tscn

**Vérifié** (headless : le test + la scène réelle + suite complète) : `sale`
posé à t=7.5 s à hygiène 40.0, les trois autres fuient dans le même tick puis
cessent en s'éloignant ; franchissement STRICT vérifié aux deux bornes
(manque 60.0 → pas sale, 64.0 → sale) ; le distrait ne capte le colon sale
QUE par `odeur_corporelle`, l'attentif par les deux canaux ; un mur opaque
bloque `apparence` et jamais `odeur_corporelle` ; lavage → état retiré au tick
suivant, miroir plat effacé, odeur et visibilité à 0.0, puis le colon se
resalit. **Non vérifié visuellement** (pas d'écran, pas de souris simulée) :
couleurs, nuage d'odeur, lignes de fuite, lisibilité des labels et clic de
lavage restent à confirmer par Yael.

## banc_nutrition — trois nutriments qui descendent à trois vitesses, et un colon qui se dégrade quand la somme tombe

`Scene/banc_nutrition.tscn`, `scripts/banc_nutrition.gd`, `data/banc_nutrition.json`. Test : `scripts/test_banc_nutrition.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_nutrition`.

**Montre.** un colon (ColorRect) surmonté de quatre barres —
gras (jaune), protéine (rouge), sucre (cyan), malnutrition (rouge vif) — et
trois repas alignés en dessous. Le repas SERVI est en couleur, les deux
autres en gris. Label sous le colon : les trois réserves, leur somme face à
seuil_qualite, la charge de malnutrition face à son seuil, l'état, la vitesse
effective, et ce qu'on lui sert. Trace console : une ligne par seconde
(l'état complet) plus une ligne à chaque pose et à chaque retrait de
`malnutri`.

**Prouve.** 1. Le PROFIL DE REPAS n'est pas du code. `depense.gd:avancer` boucle déjà sur
 TOUTES les réserves d'une chose et avance chaque canal avec son propre
 `cout_base`. Trois `cout_base` en donnée (0.10 / 0.30 / 1.00, ratio 1:3:10)
 suffisent : le gras cale longtemps, le sucre redescend vite. Une seule
 réserve à taux variable aurait exigé que le câblage recalcule un taux par
 tick selon le dernier repas — plus de code, moins lisible.
2. Une CAUSE SYNTHÉTISÉE À DISTANCE ZÉRO. `charge.gd` ne lit jamais une
 réserve et ne scanne jamais le monde : `causes` est un Array nu que
 l'appelant construit. Le câblage y met `{ position : colon.position, poids }`
 dès que la somme des trois réserves passe sous `seuil_qualite` — l'état
 interne du colon devient sa propre cause. C'est la première cause du dépôt
 qui ne vient pas d'une AUTRE chose du monde.

Le matériau nomme la réserve, jamais le code : chaque repas porte un
`type_nutriment` (String) lu directement sur sa fiche `data/materiaux.json`,
et c'est ce nom que le câblage passe à `Consommer.transferer` comme réserve
réceptrice. Les trois fiches ont la MÊME `comestibilite` (0.9) et la MÊME
`valeur_nutritive_energie` (0.8) — seul `type_nutriment` diffère, donc la
seule chose observable est la réserve alimentée et son `cout_base`. Écarté :
fabriquer les repas par `Objet.fabriquer` — la fusion par composition est une
moyenne pondérée par volume, sans aucun sens sur une String.

Pourquoi le câblage RETIRE l'état lui-même : `malnutri` ne porte pas de
`duree` (une malnutrition s'arrête quand on remange, jamais après N
secondes). Un état sans `duree` n'entre jamais dans `etats_intensite`, donc
`etat_duree.gd:avancer` ne le retirera JAMAIS. Le câblage le pose à chaque
tick tant que le marqueur de `charge.gd` est vrai (idiome
`nausee_radiation`), et l'efface d'`etats_actifs` dès que `charge.gd` retire
ce marqueur au franchissement descendant. Miroir exact, dans les deux sens.

Contrôle : clic gauche = toggle CYCLIQUE sur quatre états — gras, protéine,
sucre, RIEN. RIEN est un état à part entière (c'est lui qui produit la
malnutrition) ET l'état de départ : lancé sans un seul clic, le banc montre
la dégradation complète tout seul en une quinzaine de secondes. Le colon ne
se déplace pas et ne décide rien — pas de pipeline
perception/proximité/dominance/agir, contrairement à banc_manger. Le toggle
EST la décision : « on lui sert ce repas », jamais « il va le chercher » ; la
vitesse n'est affichée que pour rendre visible la modulation par `malnutri`.

Calibration assumée, verrouillée par le cas qui rejoue le JSON en entier
(leçon de banc_maladie, dont le seuil d'origine ne contaminait jamais
personne alors que son test restait vert) : réserves 20/15/10 contre
seuil_qualite 30.0, charge à 1.0/s pour un seuil de 3.0, `taux_decroissance`
2.0 — la charge redescend deux fois plus vite qu'elle ne monte, choix de
LISIBILITÉ, jamais une prétention physiologique.

Limite dite, pas masquée : `charge.gd` ne borne pas le HAUT d'une charge. Un
colon laissé affamé une minute accumule ~50 de malnutrition et met ~25 s à
s'en défaire ; le comportement est correct, mais la durée d'attente croît
linéairement avec le jeûne. La barre de malnutrition sature à
`charge_max_affichee` (6.0) — le nombre exact reste au label.

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

## banc_elimination_salete — trois colons qui salissent leur propre terrain, et finissent par en tomber malades

`Scene/banc_elimination_salete.tscn`, `scripts/banc_elimination_salete.gd`, `data/banc_elimination_salete.json`. Test : `scripts/test_banc_elimination_salete.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_elimination_salete`.

**Montre.** trois colons (ColorRect) errant aléatoirement (RNG
seedée). Un besoin d'élimination monte tout seul chez chacun — deux fois plus
vite chez celui qui mange le plus. Au seuil, un déchet brun apparaît AU SOL, à
l'endroit exact où le colon se trouvait, et son besoin repart de zéro. Les
déchets ne disparaissent jamais d'eux-mêmes : le sol se couvre. Un colon qui
traîne à portée des déchets voit sa charge de saleté monter et devient jaune
(exposé) ; au seuil, la chaîne maladie du catalogue partagé démarre —
incubation (jaune sombre), symptômes (orange, vitesse ×0.3), mort (rouge,
immobile). Label par colon : nom, état, besoin, charge de saleté, vitesse
effective. Compteur en haut : déchets au sol, et la répartition des colons.
Trace console à chaque élimination, exposition, symptômes, mort, nettoyage.
CLIC GAUCHE : nettoyage — tous les déchets quittent le monde d'un coup, et la
charge de saleté des colons REDESCEND d'elle-même.

CINQ COULEURS ET NON QUATRE (écart assumé à la consigne) : `incubation` a sa
propre teinte, entre `expose` et `malade` — sans elle, le moment où la saleté
cesse d'être réversible et devient une maladie serait invisible à l'écran.

UN COLON SE SALIT SUR SES PROPRES DÉCHETS, et c'est voulu : il élimine à ses
pieds. C'est ce qui rend la première calibration observable — mais c'est aussi
ce qui l'avait rendue trop rapide (voir résultat négatif ci-dessous).

LA SALETÉ EST UN FAIT DU LIEU, JAMAIS UNE PUNITION INDIVIDUELLE : dans la
mesure de référence, c'est le colon qui produit le MOINS (`colon_sobre`,
`taux_repas` 0.0) qui est exposé le PREMIER — il a traversé les tas des deux
autres. Un autre seed donnera un autre ordre.

RÉSULTAT NÉGATIF, à ne pas refaire (détail chiffré dans le `_note` de
data/banc_elimination_salete.json) : la calibration d'origine du canal de
saleté (`seuil` 4.0, `portee_charge` 90.0, `taux_decroissance` 0.6) exposait le
premier colon dès t=6.3 s — sur ses deux propres déchets, avant qu'aucun tas ne
soit visible — et tuait les trois avant t=31 s. Le banc ne montrait alors NI
l'accumulation qu'il est censé montrer, NI un moment où nettoyer change quoi
que ce soit. Retenu, mesuré : 12.0 / 75.0 / 0.8 → premier exposé t=18.6 s,
symptômes t=22.6 s, morts entre t=38.6 s et t=44.8 s, 29 déchets au sol.

SECOND RÉSULTAT NÉGATIF, invisible au test et trouvé en lançant la scène : un
colon MORT continuait de produire des déchets (t=27.0 s pour une mort à
t=26.3 s). Fermé par un gate de câblage qui met `cout_base` ET
`surcout_action` à 0.0 sur un colon mort — `depense.gd` ne consulte jamais
`etat_effectif.gd`, la modulation d'un taux par un état est TOUJOURS une ligne
de câblage (précédent unanime banc_corrosion/banc_conduction). Verrouillé
depuis par un cas de test dédié.

CE QUE CE BANC NE MONTRE PAS : la guérison. `malade` dure 20.0 s et le seuil de
mort est à 16.0 s (data/etats.json et data/seuils_etat.json, partagés avec
banc_maladie) — un colon malade meurt donc toujours avant de guérir, exactement
comme là-bas. Une fois les trois morts (~t=45 s), le banc est un tas de déchets
figé : le clic de nettoyage n'a plus d'intérêt que pour vérifier que la charge
redescend. C'est la fenêtre t=0 → t=38 s qui porte le banc.

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

Vérifié (headless, test dédié + suite complète) : le besoin monte exactement de
la montée dérivée du `cout_base` négatif ; au franchissement, un déchet et un
seul apparaît, à la position du colon, et la réserve repart exactement de zéro ;
`doit_eliminer` est retiré par `seuil_etat.gd` lui-même au tick suivant ; le
colon qui mange le plus produit strictement plus de déchets en 60 s ; un colon
mort n'élimine plus jamais ; `salete_emise` arrive sur le déchet par fusion
depuis la fiche matériau, jamais recopiée ; deux déchets à portée salissent
nettement plus vite qu'un seul ; un colon hors de `portee_charge` n'accumule
rien du tout pendant que son voisin se salit ; au seuil, le marqueur
`expose_salete` est posé ET relayé en `incube_maladie`, puis `malade` avec sa
vitesse réduite ; après nettoyage la charge redescend d'exactement
`taux_decroissance` par seconde ; le Monde reconstruit préserve l'état des
colons et ne réutilise jamais un id de déchet. En scène réelle (75 s) :
production aux instants prédits, 29 déchets, premier exposé t=18.6 s, morts
entre t=38.6 s et t=44.8 s, plus aucune élimination après la dernière mort,
aucune erreur au démarrage.

---

## banc_graisse_accoutumance — il fait du gras quand il mange trop, il le brûle quand il n'a plus rien, et le froid finit par lui coûter moins cher

`Scene/banc_graisse_accoutumance.tscn`, `scripts/banc_graisse_accoutumance.gd`,
`data/banc_graisse_accoutumance.json`. Chantier « graisse + accoutumance »
(lignes 10 et 12 — les DEUX seules des
treize au verdict PARTIELLEMENT COUVERT). Catalogues PARTAGÉS enrichis :
`data/etats.json` (famine, mort_famine), `data/seuils_etat.json` (famine,
mort_famine), `data/epigenetique.json` (accoutumance_froid).
`data/temperature.json` lu tel quel, NON touché. `data/types.json` non touché
(colon construit à la main). Aucun mécanisme du cœur touché ni créé.
Test : `scripts/test_banc_graisse_accoutumance.gd`.
Lancer : `& "<chemin trouvé, voir CLAUDE.md>" --path . --scene Scene/banc_graisse_accoutumance.tscn`

**Montre.** un colon immobile (carré clair) planté au centre exact
d'un disque bleu (zone froide), un tas de nourriture (carré orange) à côté.
Trois barres en haut à gauche — énergie (verte), graisse (jaune), accoutumance
au froid (bleu clair) — plus un compteur et un label attaché au colon :
énergie/capacité et seuil de surplus, graisse/capacité, les deux miroirs, la
température locale et le froid ressenti, le surcoût thermique DÉCOMPOSÉ
(`thermo = brut × (1 − accoutumance)`), la vitesse effective face à sa base,
et les états actifs. Trace console toutes les 3 s, plus chaque état posé ou
retiré.
Clic gauche : la nourriture disparaît (et revient). Clic droit : la source de
froid s'éteint (et se rallume).

Les trois phases ne sont codées nulle part comme des phases — elles sortent des
nombres. (1) Il mange plus qu'il ne brûle : le SURPLUS SEUL part en graisse, la
barre jaune se remplit pendant que la verte reste plaquée juste au-dessus du
seuil. (2) Nourriture retirée : l'énergie ne fait plus que descendre, touche
zéro, `affame` puis `famine` se posent. (3) En famine le transfert S'INVERSE :
la graisse alimente l'énergie exactement au rythme où elle est brûlée, puis
`mort_famine` écrase la vitesse à 0.0.

**Prouve.** `consommer.gd:transferer` appelé avec LA MÊME ENTITÉ comme source ET comme
receveur (deux réserves d'un même colon). Aucun appelant du dépôt ne le faisait
— c'est le maillon sans précédent qui valait à la ligne 10 son verdict
« partiel ». Et le sens famine ne PRÉ-BORNE RIEN : c'est la contre-épreuve de la
correction de `consommer.gd` (trois appelants avaient dû se protéger d'un défaut
fermé depuis) — demander plus de graisse qu'il n'en reste ne crée aucune
énergie, la somme énergie + graisse est invariante.

`expression.gd` reste DORMANT, et c'est intentionnel, pas un oubli.
`epigenetique.gd` pose et décroît la marque ; `exprimer()`/`appliquer` n'est
jamais appelé (divergence sans borne s'il est rappelé chaque tick — résultat
négatif déjà mesuré, écrit dans `data/epigenetique.json`). Le câblage lit
lui-même le modulateur et le compose dans son surcoût. Le champ `cible` de
l'entrée de catalogue est documentaire, lu par personne.

Écarté doctrinal, à ne pas reproposer : poser `mort_famine` directement dans
`etats_actifs` ne tient pas — `seuil_etat.gd` le retire au premier passage (son
miroir vaut 0.0 hors famine). La mort vient de la CONJONCTION de deux entrées de
catalogue, jamais d'une écriture directe.

Résultat négatif, à ne pas refaire : une marque fraîche vaut `modulateur_pose`
(0.01) et est RETIRÉE par `epigenetique.gd` dès qu'elle passe sous
`plancher_suppression` (0.008), soit après 0.4 s sans renouvellement. Poser par
intervalle ≥ 0.4 s n'accumule donc JAMAIS rien, en silence. Le banc pose toutes
les 0.25 s ; l'inégalité et sa contre-épreuve sont verrouillées par test.

Deux écarts à la consigne, assumés : le CLIC DROIT n'était pas demandé (sans
lui, l'exposition ne cesse jamais et la décroissance de la marque n'est
observable nulle part à l'écran) ; et le colon NE SE DÉPLACE PAS — sa vitesse
est portée, modulée et affichée, jamais consommée par un trajet.

**Ne montre pas.** les phases 2 et 3 exigent
un clic. En headless aucun clic n'existe — la famine, la consommation de graisse
et la mort ne sont donc prouvées que par le test, jamais en scène réelle. Même
statut que le cycle impact/effacement de banc_cratere.

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

---

## banc_bonheur — quatre colons, le même monde, quatre bonheurs : seuls les poids diffèrent

`Scene/banc_bonheur.tscn`, `scripts/banc_bonheur.gd`, `data/banc_bonheur.json`. Test : `scripts/test_banc_bonheur.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_bonheur`.

**Montre.** quatre colons côte à côte, immobiles, exposés AUX MÊMES
cinq sources (securite, nourriture, activite, liens, combat) AUX MÊMES niveaux
au même instant. Rien dans le monde ne les distingue — et pourtant leurs quatre
carrés n'ont pas la même couleur. UN BLOC PAR COLON, UNE LIGNE PAR RÔLE, de haut
en bas : le nom du colon ; la ligne bonheur + état(s), en grand et dans la
couleur de l'état ; les cinq barres de source, chacune avec le nom de la source
à GAUCHE de la barre et le poids de ce colon à DROITE (« ×0.50 », ou « - » quand
il ne la valorise pas — les deux valent 0.0 dans la somme, mais « je n'y mets
rien » et « j'y mets zéro » ne se disent pas pareil) ; le carré du colon ;
vitesse et rythme SEULS sur la dernière ligne, base → effectif. Une couleur par
source : securite bleu, nourriture vert, activite jaune, liens rose, combat
rouge. Couleur du carré ET de la ligne bonheur par état : vert (heureux), gris
(neutre), orange (malheureux), rouge (désespéré) — la ligne, elle, porte les
DEUX états quand l'escalier est franchi (« desespere + malheureux »), ce que la
couleur seule ne peut pas dire. Compteur en haut : combien de colons dans chaque
état. Trace console à chaque état posé ou retiré, et un état périodique par
colon. Clic gauche : coupe une source à tour de rôle, puis aucune — la barre de
la source coupée passe au rouge sombre à longueur nulle (sans quoi « coupée » et
« nulle par hasard » seraient indistinguables).

Toute la géométrie du rendu vit dans data/banc_bonheur.json (largeurs de colonne,
espacement entre barres, marges, cinq tailles de police, couleur par source) et
n'est lue que par _creer_rendu/_rafraichir_tout, jamais par une fonction pure :
changer le rendu ne peut pas changer un bonheur, et une sixième source déclarée
en donnée repousse le haut du bloc sans rien recouvrir. Les colons sont écartés
de 400 sur x parce que la ligne bonheur d'un désespéré est le texte le plus large
du banc et déborde de son bloc.

**Prouve.** LE TEMPÉRAMENT EST UN
POIDS, PAS UNE CATÉGORIE. Le code ne connaît ni « social », ni « guerrier », ni
« gourmand » : il boucle sur un Dictionary `poids_bonheur` porté par chaque
colon. Les mêmes sources sont offertes à tous ; seul le poids distingue.
C'est « Les archétypes n'existent pas » (design.md) rendu observable. Un
cinquième tempérament est une entrée de donnée, zéro ligne de code.

**Prouve aussi.** UN CHAMP DÉRIVÉ NE DÉRIVE QUE S'IL EST RECALCULÉ À NEUF.
Le bonheur n'est pas une réserve — depense.gd et charge.gd ne le touchent
jamais. Le câblage le réécrit chaque tick par-dessus la valeur précédente,
jamais par `+=`. Le résultat négatif inverse est déjà mesuré deux fois dans le
dépôt (expression.gd, qui relit la valeur qu'il vient d'écrire et diverge sans
borne) : expression.gd n'est donc pas appelé ici, contournement intentionnel,
même décision que banc_graisse_accoutumance. Verrouillé par test — cent
passages sur un monde immobile rendent exactement le même nombre.

Troisième chose, et c'est une PREMIÈRE de data/seuils_etat.json : `bonheur_haut`
compare une propriété qui MONTE quand la situation s'AMÉLIORE. Toutes les
entrées antérieures montent quand elle empire, d'où leurs miroirs inversés. Elle
compare donc `bonheur` directement, sans miroir. Le miroir `manque_bonheur`
n'existe que pour les deux entrées basses, et pour UNE SEULE des deux raisons
habituelles : retourner le SENS de la comparaison. Il n'a rien à aller chercher
sous proprietes.reserves.<nom>.reserve — `bonheur` est déjà une clé plate.

`manque_bonheur` et `bonheur` sont écrits par UN SEUL ÉCRIVAIN, dans le même
geste, depuis le même nombre. Deux morceaux de câblage écrivant l'un le champ et
l'autre son miroir se seraient désynchronisés EN SILENCE : aucun test n'aurait
rougi, seuil_etat.gd aurait comparé deux grandeurs qui ne se répondent plus.
Même parade que banc_faim_thermo.

`heureux` est le premier état du dépôt qui ACCÉLÈRE (×1.1 sur vitesse ET sur
rythme) : tous les états antérieurs ne savaient que ralentir ou écraser à 0.0,
et aucun ne visait `rythme`.

**Ne montre pas.** les colons ne se déplacent
pas et ne décident rien — aucun pipeline perception/proximité/dominance/agir.
`vitesse` et `rythme` effectifs sont AFFICHÉS pour rendre la modulation visible,
jamais pour bouger quoi que ce soit (même découpage assumé que banc_nutrition).
Et la modulation de `rythme` n'a d'effet QUE parce que ce banc compose lui-même
EtatEffectif.valeur : banc_commun.gd:agents_rythme lit la valeur BRUTE, donc
l'effet ×1.1 sur le rythme reste inerte partout ailleurs dans le dépôt. Dette du
câblage existant, signalée, non corrigée ici.

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

## banc_menace_combat — trois colons, les mêmes ennemis : l'un fuit, l'autre charge, le troisième dépend du ratio

`Scene/banc_menace_combat.tscn`, `scripts/banc_menace_combat.gd`, `data/banc_menace_combat.json`. Test : `scripts/test_banc_menace_combat.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_menace_combat`.

**Montre.** trois colons alignés (lâche à gauche, équilibré au
centre, agressif à droite), un groupe d'ennemis noirs au nord, un ouvrage
`cassable` derrière chaque colon, un mur semi-opaque sur la ligne de vue de
l'agressif. Le score de menace monte, le stress s'accumule, et au seuil chaque
colon bifurque : le lâche passe au BLEU et s'éloigne, l'agressif passe au ROUGE
et charge, l'équilibré suit le ratio d'effectifs. Couleur du carré : vert
(neutre), bleu (peur), rouge (colère). Label par colon : stress_combat,
biais_combat, sortie active, précision et endurance EFFECTIVES. Compteur en
haut : nombre d'ennemis, ratio, colons en peur / en colère. Lignes de
perception et de fuite. Trace console à chaque bifurcation. Clic gauche : palier
d'effectifs suivant (4 ennemis → 2 → 6 → 0, cycle) — le ratio change, le score
change, les bifurcations changent.

**Prouve.** UN SCORE CONTINU FAIT
DE TROIS GRANDEURS QUI NE SE RESSEMBLENT PAS — distance (géométrie), ratio
d'effectifs (comptage.gd, deux appels et une division) et visibilité
(occlusion.gd, facteur continu dans [0,1]) — multipliées puis sommées sur tous
les ennemis, et versées dans le champ `poids` d'une cause de charge.gd. Aucune
des trois pièces n'est neuve ; ce qui l'est, c'est qu'elles se composent.

Deuxième chose : C'EST LA PREMIÈRE BIFURCATION RÉELLE DU DÉPÔT. bifurcation.gd
n'avait aucun appelant. Trois colons, le MÊME code, les MÊMES ennemis : seul
biais_combat les sépare. Un quatrième tempérament est une entrée de donnée.

Troisième chose : LA PREMIÈRE PROPRIÉTÉ À DEUX VERBES (types_choses.json:hostile
→ ["approcher", "s_eloigner"]). Jusqu'ici chaque propriété n'en proposait qu'un,
ce qui rendait poids_verbes fonctionnellement inerte. C'est ce qui permet à la
MÊME chose, perçue par le MÊME colon, d'appeler deux gestes opposés selon son
état interne.

AUCUN HASARD, NULLE PART — design.md, RÈGLE ANTI-BRUIT. Pas un seul RNG dans le
fichier, et pas de « prob_fuite_par_s ». La peur fait DEUX choses, toutes deux
déterministes : elle amplifie la saillance de la propriété de menace via
deformation.gd (l'ennemi finit par ÉCRASER l'ouvrage voisin, dominance.gd le
RETIRE de la liste), et elle recompose poids_verbes pour que `s_eloigner` batte
`approcher`. LES DEUX SONT NÉCESSAIRES : agir.gd choisit d'abord une CIBLE au
score de saillance, puis un VERBE en ne lisant QUE poids_verbes. La déformation
seule aurait produit un colon qui fonce sur ce qu'il craint ; poids_verbes seul,
un colon qui fuit un ennemi qu'il ne regarde même pas.

`prob_fuite` est LU, jamais tiré au sort : `colere` l'écrase à 0.0 et le câblage
n'entre dans sa branche de fuite que s'il est strictement positif. Un colon en
colère ne fuit donc JAMAIS, même si le verbe résolu était `s_eloigner`.

Le biais passé à bifurcation.gd est COMPOSÉ (peur × ratio, colère × 1.0) et non
brut : le mécanisme multiplie chaque biais par UNE grandeur commune, qui ne peut
donc jamais départager deux biais égaux. Sans cette composition, « l'équilibré
dépend du ratio » serait infaisable. Le lâche a peur dès ratio > 0.25,
l'agressif seulement au-delà de 4.0, l'équilibré bascule exactement à 1.0.

**Ne montre pas.** il n'y a AUCUN combat — pas
de dégâts échangés, pas de mort. `degats` est modulé et AFFICHÉ, jamais appliqué
à quoi que ce soit. Et un colon qui fuit s'éloigne, son score baisse, son état
se retire, il revient vers son ouvrage : le cycle recommence. C'est
physiquement juste et non corrigé — aucune hystérésis, charge.gd n'en a pas.

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

## banc_psycho_social — il hésite entre deux options, il agit, ce qu'il fait change la scène, et l'ordre du joueur ne pèse que s'il pèse assez

`Scene/banc_psycho_social.tscn`, `scripts/banc_psycho_social.gd`, `data/banc_psycho_social.json`. Test : `scripts/test_banc_psycho_social.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_psycho_social`.

**Montre.** Deux colons à gauche, un feu et un allié blessé à droite posés
à distance EXACTEMENT égale, une nourriture au loin en zone froide, un
adversaire hors scène. Les deux plus hautes saillances sont trop proches :
les colons hésitent, virent à l'orange, et l'hésitation leur COÛTE de
l'énergie. Puis ils tranchent, soignent l'allié — leur énergie passe dans
sa santé, exactement — et à 100 il guérit, perd saillance et verbe, et
les libère. À mesure que leur énergie descend, une sigmoïde amplifie la
saillance de tout ce qui est comestible pour CE colon : passé un point la
nourriture écrase le reste et il va manger quoi qu'on lui dise, puis
l'énergie remonte et il revient à son dilemme.

**Contrôles.** Clic gauche : feu. Clic droit : nourriture. Touche D :
directive. Touche C : adversaire — il écrase tout, les colons le
combattent, sa vigueur descend et vaincu il SORT DU MONDE. Quatre toggles
ne tiennent pas sur deux boutons de souris (précédent `banc_biomes`).

**Ce qu'il prouve, et qu'aucun banc antérieur ne montrait.**

1. LE CONFLIT INTERNE SE MESURE SUR `resultats`, JAMAIS SUR `visibles` —
   `dominance.gd` a déjà retiré toute entrée dont l'écart au sommet dépasse
   son seuil, un écart supérieur n'y serait donc jamais mesurable. Le
   stress est un miroir plat recalculé à neuf : il redescend seul dès
   qu'une option se détache, et `seuil_etat.gd` retire l'état sans une
   ligne de plus.
2. LES DEUX SEULES VOIES QUI PÈSENT ENTRE DEUX CIBLES sont une déformation
   par source et une entrée de saillance SYNTHÉTIQUE ajoutée à `resultats`.
   `poids_verbes` n'en est PAS une : `agir.gd` choisit d'abord la CIBLE au
   score, et seulement ensuite un verbe parmi ceux qu'elle propose. Monter
   `poids_verbes.manger` à 10 000 ne ferait jamais gagner la nourriture
   contre un feu — le colon mourrait de faim devant un repas.
3. LA DÉSOBÉISSANCE EST PROUVÉE PAR DEUX CHEMINS INDÉPENDANTS. Par le
   POIDS : le bonus de directive est une saillance CONCURRENTE, jamais
   additive — elle doit dépasser le sommet naturel, et elle perd contre la
   faim critique. Par le GATE : sous état vital, l'entrée n'est même pas
   construite. Aucun cas particulier — c'est `dominance.gd` inchangé.
4. L'APPRENTISSAGE À BIAIS DE BASE ÉGAL. Vétéran et novice ont exactement
   le même biais de départ (« Les archétypes n'existent pas ») ; seule la
   marque épigénétique accumulée les sépare, et le novice se rouille s'il
   arrête. C'est un SEUIL sur un miroir plat, pas une bifurcation pondérée
   — `bifurcation.gd` existe et n'est pas appelé ici.
5. L'ARRIVÉE DOIT PRODUIRE QUELQUE CHOSE, et **c'est une leçon de méthode**
   payée en lançant la scène : sans effet derrière le verbe, le colon
   arrivait sur l'allié et y restait planté vingt-quatre secondes. Le test
   ne pouvait pas le voir — il mesurait tout au point de départ,
   statiquement, sans jamais faire avancer le colon dans le temps. **Un
   banc dont tous les cas sont verts peut ne rien montrer.**

**Deux gestes symétriques, deux mécanismes différents, et c'est voulu** :
`secourir` TRANSFÈRE (ce que l'allié gagne, le colon le perd), `combattre`
DÉTRUIT (la vigueur descend et ne va nulle part — un combat ne déplace pas
de la matière d'un corps à l'autre). Sortir une cible de la décision
demande DEUX retraits, visant deux couches : la propriété qui porte le
verbe, et le profil de saillance. N'en faire qu'un laisse soit une cible
muette qui attire encore, soit un verbe qui se résout sur une chose
invisible.

**DEUX PIÈGES FERMÉS, écrits pour ne pas être repayés.** UN SEUL ÉCRIVAIN
DE `surcout_action` : `depense.gd` n'a qu'un emplacement par canal et
quatre choses veulent y écrire — quatre morceaux de câblage séparés se
seraient écrasés EN SILENCE, aucun test n'aurait rougi, la dépense aurait
seulement été fausse. ET LE PLAFOND DE DÉFORMATION EST OBLIGATOIRE :
`deformation.gd` décroît par soustraction FIXE, il n'existe AUCUN équilibre
naturel — une calibration qui tablait sur un point fixe « débit = taux » a
fait monter le biais à 58 en vingt secondes, pour plus de deux minutes de
redescente.

**Ne montre pas.** Sommeil et chaleur ne sont pas câblés : la scène ne
porte ni lieu de repos ni abri, et aucune entrée n'a été inventée pour un
contenu qui n'existe pas. Le grief non plus (autre chantier) — aucune
barre vide n'a été dessinée pour faire semblant. `approcher` (le feu) n'a
toujours AUCUN effet : une fois l'allié guéri et l'adversaire vaincu, les
colons campent près de la nourriture — le motif « planté » n'a pas
disparu, il s'est déplacé sur une cible qui, elle, a un effet. Et il y a UN
TICK DE RETARD inhérent : la décision d'un tick lit les états posés au
précédent, l'ordre inverse serait circulaire.

**Non vérifié à l'œil** (pas d'écran, ni souris ni clavier simulés).

## banc_grief — trois colons rompent au même instant, et partent vers trois destins

`Scene/banc_grief.tscn`, `scripts/banc_grief.gd`, `data/banc_grief.json`. Test : `scripts/test_banc_grief.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_grief`.

**Montre.** trois colons alignés à gauche, chacun avec son ouvrage
au centre et une barre de grief marquée d'un trait de seuil ; un point de
rassemblement à droite, la directive du joueur. Le fond est rouge sombre tant
que la colonie est injuste : le grief des trois monte au MÊME rythme et franchit
le seuil au MÊME instant. Là, chacun bifurque selon son seul biais : le soumis
passe au JAUNE (il travaille encore, mais ×0.7 en vitesse et en rythme), le
rebelle au ROUGE (il cesse de recevoir la directive — le joueur perd la main sur
lui), le nomade au BLEU, marche vers le bord le plus proche et disparaît.
Couleur du carré : gris (neutre), jaune (soumis), rouge (contestataire), bleu
(en départ). Label par colon : grief, biais_grief, sortie active. Compteur en
haut : colons par état. Trace console à chaque bifurcation, à chaque départ et à
chaque changement de mode. Clic gauche : bascule injustice ↔ amélioration — le
fond verdit, le grief redescend, et sous le seuil chacun redevient ce qu'il
était (un nomade rattrapé avant le bord revient à son ouvrage). Clic droit :
coupe ou rétablit la directive.

**Prouve.** LE PREMIER CUMUL DU
DÉPÔT QUI REDESCEND. Les grandeurs comparées par seuil_etat.gd étaient soit
accumulées par `+=` et jamais décroissantes (degats_impact_cumules,
duree_maladie_cumulee), soit recalculées à neuf chaque tick depuis une réserve
(manque_energie, manque_sommeil, manque_bonheur). Le grief est les deux à la
fois : il repart de sa valeur précédente ET il redescend, borné à zéro par le
câblage — aucun mécanisme du cœur ne borne une propriété plate. Rien dans
seuil_etat.gd ne s'y oppose : il ne fait que comparer.

Deuxième chose : UNE ENTRÉE DE SEUIL NE SAIT POSER QU'UN ÉTAT. Elle ne peut pas
choisir entre trois sorties selon un biais individuel. D'où deux états
distincts, jamais confondus — `rupture_grief`, marqueur pur qui ne fait
qu'OUVRIR LA PORTE, puis `soumis`/`contestataire`/`en_depart`, dont un seul est
posé depuis la sortie retenue par bifurcation.gd. C'est le deuxième appelant
réel de ce mécanisme (après banc_menace_combat), et le premier à trois sorties.

Troisième chose : LE BIAIS SEUL DÉCIDE. Même seuil, même grief à chaque instant,
même instant de rupture — seul biais_grief sépare les trois colons (design.md,
« Les archétypes n'existent pas »). Un quatrième tempérament est une entrée de
donnée. Et le biais est passé BRUT, contrairement à banc_menace_combat qui le
compose : ici aucune grandeur externe n'a à départager les sorties.

Trois écarts à la consigne, constatés sur le disque avant d'écrire : « état pas
utilisé directement » n'est pas exprimable (seuil_etat.gd EXIGE le champ `etat`,
d'où le marqueur pur) ; le sens de déformation « coupe » n'existe pas et ne
pouvait pas servir (une entrée de directive est synthétique, elle ne traverse
jamais proximite.gd — aucune déformation ne peut l'atteindre, quel que soit son
sens), remplacé par un GATE PAR ÉTAT recopié de banc_psycho_social ; et
`en_depart` écrase bien `vitesse` à 0.0 comme demandé, le mouvement de sortie
passant par une propriété séparée, sans quoi un colon censé partir serait cloué
au sol.

Le piège du constat (D) de l'audit est tenu : etat_effectif.gd ne s'applique que
si quelqu'un l'appelle — banc_commun.gd:agents_rythme lit `rythme` BRUTE.
Déclarer `soumis` ×0.7 sur `rythme` ne suffit donc jamais : le banc compose
lui-même la valeur effective, et l'ouvrage est consommé à ce rythme-là. Sans ces
lignes, la modulation serait vraie dans le catalogue et sans le moindre effet,
en silence, sans qu'aucun test ne rougisse.

**Ne montre pas.** il ne monte ni
perception.gd ni proximite.gd — ses deux entrées de saillance (l'ouvrage, la
directive) sont construites par le câblage. L'arbitrage, lui, est réel
(dominance.gd puis agir.gd, tels quels) : la directive doit DÉPASSER la
saillance de l'ouvrage pour être suivie, agir.gd retient le meilleur score et
n'additionne jamais. La démonstration complète du pipeline vit dans
banc_psycho_social et n'est pas refaite ici.

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

## banc_croyance — il croit que le fruit est comestible, et il a tort

`Scene/banc_croyance.tscn`, `scripts/banc_croyance.gd`, `data/banc_croyance.json`. Test : `scripts/test_banc_croyance.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_croyance`.

**Montre.** quatre colons et trois objets. Un fruit (comestible),
un feu (dangereux), une pierre (rien du tout). Chaque colon forme ses croyances
en regardant, à SA propre cadence, et son label affiche ce qu'il croit — valeur
crue et certitude — pendant que le label de chaque objet affiche ce qui est
RÉELLEMENT vrai. Couleur du carré : vert (correct), orange (périmé — juste mais
plus vérifié), rouge (faux — une valeur crue contredit le monde), FAUX
l'emportant sur PÉRIMÉ. Une ligne relie chaque colon à ce que sa DÉCISION vise,
donc à ce qu'il CROIT saillant. Trace console à chaque observation neuve,
chaque correction, chaque refus et chaque oubli.

**Trois contrôles.** - clic GAUCHE — le fruit devient toxique. Il PERD la clé `comestible`, il ne la
 met pas à `false`. Les colons qui se contentent de regarder continuent de
 croire qu'il est comestible et continuent de résoudre le verbe `manger` :
 ils passent au ROUGE sans que rien n'ait changé chez eux.
- clic DROIT — le feu part hors de portée de vue. La croyance persiste (ORANGE,
 périmé), la certitude descend, puis la croyance DISPARAÎT du registre.
- touche T — l'émetteur (colon_informe) verse ses croyances aux autres. Trois
 issues différentes, et c'est le cœur du banc.

**Prouve.** LES QUATRE COUCHES
DÉCIDENT SUR UNE COPIE, PLUS SUR LE MONDE. Perception.percevoir →
Croyance.filtrer → Proximite.evaluer → Dominance.visibles → Agir.choisir : les
quatre dernières ne voient jamais l'objet réel, et aucune n'a une ligne de
changée. Un colon agit sur une information fausse SANS AUCUNE BRANCHE SPÉCIALE,
parce qu'agir.gd ne compare que des noms de propriété et des nombres reçus en
paramètre.

Deuxième chose : LE DOGME EST UNE CONSÉQUENCE, PAS UNE RÈGLE. Au-delà de
resistance_par_certitude (0.9), une correction est refusée. Cette certitude ne
vient QUE d'avoir regardé souvent. Le colon dogmatique de ce banc ne porte
aucun état posé en dur : il a le MÊME corps que le colon ouvert (forme,
poids_verbes, canaux_config identiques, vérifié par test) et n'en diffère que
par cadence_observation — 0.4 s contre 8.0 s. Il franchit 0.9 vers t≈3 s, et
plus rien ne l'atteint. Un tempérament de plus est une ligne de donnée.

Troisième chose : LA CRÉDIBILITÉ D'UNE SOURCE EST LA FORCE D'UN LIEN PERSONNEL.
Un autre colon est une chose comme une autre ; liens_personnels porte déjà une
force colon → chose, il n'y avait rien à inventer. DEUX REFUS DISTINCTS, à ne
jamais confondre : sous seuil_bornes_transmission (0.4) le CÂBLAGE renonce et
n'appelle même pas corriger — colon_isole, sans aucun lien, n'entend rien ;
au-delà, il appelle, et c'est le MÉCANISME qui refuse — colon_dogmatique écoute
et refuse quand même. Les deux sont détectés par différence d'état, jamais en
recopiant un seuil dans le banc.

Ce qui garde colon_informe corrigible, et c'est le seul réglage subtil du
banc : il ne REGARDE presque pas (cadence 60 s) et TOUCHE souvent (cadence
1 s). Chaque vérification au contact ÉCRASE sa certitude à gain_par_echec ×
1.0 = 0.8, sous la résistance — sa croyance reste donc éternellement
corrigible, et c'est ce qui en fait la source de vérité. RÉSULTAT MESURÉ, dit
plutôt que masqué : un colon qui regarde ET touche le même objet oscille —
l'observation pousse vers le dogme (+0.1 par regard), la vérification ramène en
deçà (:= 0.8). Avec ces cadences le croisement n'a pas lieu avant t = 60 s.

**Ne montre pas.** - LES COLONS NE BOUGENT PAS. Aucune vitesse, aucun bouger_vers, aucune fuite,
 aucun ciblage.gd. Le sujet est ce qu'un colon SAIT, jamais où il va — et
 faire marcher les quatre vers le fruit les aurait tous mis au contact, donc
 tous corrigés par l'expérience directe : il n'y aurait plus rien à
 transmettre.
- AUCUN REPAS N'A LIEU. consommer.gd n'est pas appelé, le fruit ne se vide
 jamais : « il mange » se lit dans le verbe résolu, pas dans une réserve qui
 bouge. Un vrai repas est banc_manger.
- AUCUNE MÉMOIRE SPATIALE ICI. La position rendue par le filtre est toujours la
 position VIVANTE : un objet qui bougerait serait suivi par télépathie. C'est
 un mécanisme DISTINCT — memoire_spatiale.gd, voir banc_memoire_navigation
 plus bas — que ce banc ne monte pas, et que croyance.gd ne lit jamais.
 Retenir OÙ était une chose et recopier CE QU'ELLE EST sont deux questions
 séparées ; les mélanger dans un seul banc rendrait illisible ce que chacune
 apporte.
- Le clic droit n'éloigne le feu que pour la VUE. Rien d'autre ne change dans
 le monde ; il n'est ni éteint ni détruit.

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

Vérifié (headless, les seize cas + scène réelle 6000 images, console lue) :
au départ personne ne croit rien ; à la première observation chacun croit ce
qu'il perçoit, à certitude 0.30 ; la pierre est perçue et ne produit jamais de
croyance ; le dogmatique franchit 0.9 quand l'ouvert reste dessous, sans
qu'aucune autre différence n'existe entre eux ; le fruit toxique perd sa clé et
la croyance périmée survit ; le verbe reste `manger` sur une croyance fausse ;
la décision ne bouge pas quand le monde change sans être réobservé ; l'ID
traverse la chaîne entière ; le contact corrige l'informé, y compris sur
`toxique` que l'œil ne capte pas, et son verbe tombe à vide ; la transmission
corrige l'ouvert (certitude = 0.8 × 0.8), le dogmatique refuse, l'isolé n'est
même pas écouté ; le feu éloigné donne PÉRIMÉ puis l'oubli retire la croyance
(mesuré en scène réelle : t = 25.0 s exactement, 0.30 → 0.05 à 0.01/s).

## banc_memoire_navigation — il marche vers un puits qui n'est plus là

`Scene/banc_memoire_navigation.tscn`, `scripts/banc_memoire_navigation.gd`, `data/banc_memoire_navigation.json`. Test : `scripts/test_banc_memoire_navigation.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_memoire_navigation`.

**Montre.** un colon (vert) et un puits. Le puits RÉEL est le carré
BLEU, la position MÉMORISÉE est le carré ORANGE, et une ligne relie le colon à
ce qu'il vise. Au départ les deux carrés sont confondus : le puits est à portée
de vue, le colon le mémorise à chaque image, la force du souvenir sature. À
t = 4 s le puits s'éloigne hors de portée — le BLEU part, l'ORANGE reste. Le
colon marche vers l'ORANGE. Le label donne les quatre nombres : force du
souvenir, erreur, luminosité, heure.

**Trois contrôles.** - clic GAUCHE — JOUR / NUIT. La luminosité passe de 1.00 à 0.00, l'erreur monte
 de coef_nuit, et le point visé s'écarte davantage du souvenir. Le colon se
 perd plus la nuit sans qu'aucune branche « si nuit » n'existe.
- clic DROIT — le temps de l'OUBLI accélère (×12). La force descend, l'erreur
 monte, l'ORANGE dérive LE LONG D'UNE DROITE FIXE. Assez longtemps, l'entrée
 passe sous le plancher et disparaît : plus rien à viser, le colon S'ARRÊTE.
- touche R — REPERCEVOIR : le puits revient à portée, à une TROISIÈME position.
 L'ORANGE saute sur le BLEU, la force remonte, l'erreur redescend.

**Prouve.** LE COLON VISE UN
SOUVENIR, PLUS LE MONDE. lien_personnel_attraction.gd rendait déjà une cible
hors de portée de perception — mais à sa position RÉELLE, relue vivante à
chaque tick (monde.gd : « la position est toujours relue depuis chose.position
au moment de la requête »). Un colon suivait donc un puits qui bouge, par
télépathie. Ici l'écart entre le bleu et l'orange est visible à l'œil et
dépasse la portée de vue.

Deuxième chose : L'ERREUR EST DÉTERMINISTE, et pourtant elle ne se répète
jamais bêtement. Pas un RNG dans le chantier (le dépôt n'en a aucun, par
doctrine). Le scalaire vient de deux causes qui s'additionnent — mémoire faible
et obscurité — et la DIRECTION vient du hash de l'id du puits, donc elle ne
change pas d'un tick à l'autre : le souvenir dérive, il ne tremble pas. Un
second colon, de forme_biais différente, dériverait dans la même direction mais
plus ou moins loin.

Troisième chose : LE JOUR EST FIGÉ EXPRÈS. L'heure passe par horloge.gd —
ce banc est le TROISIÈME demandeur, celui qui a fait franchir le seuil que
banc_fatigue_circadien.gd avait nommé — mais avec duree_jour_secondes à 0.0,
le point « temps du monde arrêté », légitime et documenté. Raison : l'erreur a
DEUX causes et le banc existe pour les séparer ; une heure qui dérive ferait
varier la luminosité sous chaque mesure. Faire tourner le jour = ce seul nombre.

**Ne montre pas.** - AUCUNE COUCHE DE SAILLANCE. Ni proximite.gd, ni dominance.gd, ni agir.gd, ni
 ciblage.gd. La cible est déclarée en donnée et le mouvement est direct.
 Brancher le souvenir sur la couche 2 — un candidat de saillance à position
 MÉMORISÉE, là où lien_personnel_attraction.gd en rend un à position RÉELLE —
 est le chantier SUIVANT : il touchera le cœur, il ne se bricole pas ici.
- UN SEUL COLON. Le fait que deux formes différentes dévient différemment est
 prouvé par le test, jamais à l'écran.
- AUCUNE CROYANCE. La mémoire porte des POSITIONS, jamais des propriétés.
 croyance.gd est un autre mécanisme et ne lit pas ce registre.
- LE TEMPS ACCÉLÉRÉ N'ACCÉLÈRE QUE L'OUBLI, jamais le déplacement ni la
 perception — sinon le colon traverserait l'écran et la dérive ne se verrait
 plus. Une vraie accélération de simulation est banc_simulation_acceleree.

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

Vérifié (headless, les douze cas + scène réelle console lue) : à t = 0.1 s le
puits est vu, force 0.50, erreur 0.50, l'orange à 45 px du bleu ; à t = 1.1 s la
force sature à 1.00, erreur 0.00, les deux carrés confondus, 0.50 écrêté par
tick ; à t = 4.1 s le puits est parti, écart 599.93 px et le souvenir n'a pas
bougé d'un pixel ; ensuite la force descend de 0.02/s et le point visé s'écarte
régulièrement (338, 1) → (336, 1) → (333, 2) le long de la même droite. Sous
temps accéléré le souvenir est retiré du registre et le colon ne bouge plus du
tout.

## banc_oubli_consolidation — il oublie vite, puis lentement, et la nuit le rattrape

`Scene/banc_oubli_consolidation.tscn`, `scripts/banc_oubli_consolidation.gd`, `data/banc_oubli_consolidation.json`. Test : `scripts/test_banc_oubli_consolidation.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_oubli_consolidation`.

**Montre.** un colon (vert) et trois objets — baie, souche, braise.
Deux barres par objet : CERTITUDE (croyance) et FORCE (mémoire spatiale). Un
carré jaune marque la position mémorisée. Le fond s'assombrit la nuit, le colon
devient bleu quand il dort, orange quand il a peur. La scène se déroule seule ;
cinq phases s'enchaînent sans qu'on touche à rien :
- PERCEPTION (0 → 6 s) — les trois objets sont à portée, le colon les observe
 toutes les 2 s : les barres montent.
- OUBLI (6 s → nuit) — les objets s'éloignent hors de portée. Les barres
 descendent VITE au début, puis de plus en plus lentement.
- CONSOLIDATION (nuit, 20 h → 6 h) — le colon dort. Rien pendant les 3 premières
 heures, puis cinq passes qui font REMONTER les barres.
- RAPPEL (26 → 30 s) — la baie seule revient. Sa certitude et sa force
 remontent, et son S s'étire (7.9 → 10.5 s) : elle s'oubliera moins vite après.
- ÉMOTION (permanente) — la braise porte « dangereux », le colon en a peur, et
 son souvenir a été figé à charge 2.0. Elle décroît deux fois moins vite que
 les deux autres, longtemps après que la peur est retombée.
La barre de sommeil monte pendant la nuit et retombe au réveil. Le label donne
certitude, force, taux effectif, S, charge, heures dormies et passes.

**Deux contrôles.** - clic GAUCHE — forcer le sommeil, à n'importe quelle heure.
- touche R — ramener / éloigner l'objet rappelé, sans attendre son jalon.

**Prouve.** L'OUBLI EST UNE
EXPONENTIELLE, ET AUCUN MÉCANISME NE LE SAIT. croyance.gd et memoire_spatiale.gd
décroissent par soustraction fixe et lisent leur taux au catalogue — le dépôt
n'avait aucune décroissance exponentielle. Le câblage écrit le taux par
souvenir (valeur / (S × charge)), et la soustraction fixe devient une
exponentielle. Le taux affiché BAISSE avec la certitude : c'est ça, la preuve à
l'œil.

Deuxième chose : LE MÉCANISME RETIRE, LE BANC NE RECOPIE AUCUN SEUIL. Comme le
taux est écrit par souvenir, avancer est appelé sur une VUE d'une seule
entrée — et les retraits de niveau racine ne traversent pas la vue. Le banc
rappelle donc avancer une dernière fois sur l'entité réelle avec delta = 0.0 :
rien ne décroît, et le mécanisme applique pourtant son propre plancher. Aucun
seuil de suppression n'est écrit dans le banc.

Troisième chose : L'ÉMOTION S'ATTACHE AU SOUVENIR, PAS AU COLON. data/etats.json
module charge_emotionnelle sur le colon entier ; le câblage la FIGE à
l'observation, et seulement pour les choses qui portent la propriété de menace.
Sans ce geste, un colon effrayé retiendrait mieux TOUT ce qu'il voit à cet
instant — la baie comme la braise — et la ligne serait fausse.

**Ne montre pas.** - AUCUNE COUCHE DE SAILLANCE, aucun déplacement. Le sujet est ce qu'un souvenir
 DEVIENT, jamais ce qu'il fait décider (banc_croyance) ni où il fait aller
 (banc_memoire_navigation).
- AUCUNE CORRECTION. croyance.gd:corriger n'est jamais appelé : un souvenir ne
 peut que monter, décroître ou disparaître, jamais devenir faux.
- LE COLON NE S'ENDORT PAS DE LUI-MÊME : c'est l'heure qui décide (ou le clic).
 Aucun mécanisme du dépôt ne fait dormir qui que ce soit.

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

## banc_stress_thermo_vivant — trois plantes, un animal, chacun son confort : le froid tue l'une, la chaleur tue l'autre

`Scene/banc_stress_thermo_vivant.tscn`, `scripts/banc_stress_thermo_vivant.gd`, `data/banc_stress_thermo_vivant.json`. Test : `scripts/test_banc_stress_thermo_vivant.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_stress_thermo_vivant`.

**Montre.** trois plantes et un animal, immobiles, chacun avec SA
température de confort — tropicale 30 (au cœur du disque rouge), tempérée 15 (au
milieu), arctique 5 (au cœur du disque bleu), animal 37 (au milieu). Au palier de
départ les trois plantes sont vertes, personne ne porte le moindre état, et la
barre de maturité monte. Clic gauche : l'ambiante passe à −16 — la TROPICALE
vire au rouge puis au brun et cesse de pousser, la tempérée jaunit sans mourir,
l'arctique ne bouge pas d'un chiffre. Clic gauche encore : canicule à 60 — c'est
l'ARCTIQUE qui meurt, la tempérée jaunit à nouveau, la tropicale va très bien.
Clic droit : l'arrosage se coupe, et au palier tempéré c'est la tropicale, la
plus assoiffée, qui bascule seule. L'animal ne meurt jamais de stress : il
DÉPENSE — sa barre d'énergie descend à 0.81/s au palier tempéré et à 1.89/s au
grand froid. Couleur du carré : vert → jaune → rouge selon le rapport du stress
au seuil MORTEL de cette plante-là, brun sombre à la mort (sans quoi « stress
maximal » et « morte » seraient indistinguables) ; l'animal garde une couleur
déclarée, il n'a pas de stress à montrer. Label par vivant : stress sur seuil
mortel, cible thermique, locale, froid et chaud ressentis, surcoût, énergie,
états. Compteur en haut : palier, arrosage, stressés, morts, vivants. Trace
console à chaque changement d'état et toutes les deux secondes.

**Prouve.** UNE SOMME PONDÉRÉE
COMPARÉE VERS LE HAUT SANS AUCUN MIROIR. Le patron est celui du bonheur —
recalcul à neuf chaque tick, boucle sur les poids portés par l'entité, jamais un
`+=`. Mais le bonheur monte quand la situation s'améliore, ce qui obligeait à
inverser (`manque_bonheur`) pour ses deux états bas ; le stress monte quand elle
empire, et la comparaison de seuil_etat.gd tombe juste telle quelle. Aucune
propriété de retournement n'existe dans ce banc.

Deuxième chose : LES SEUILS VARIENT PAR INDIVIDU, ce qu'un catalogue partagé ne
permettait pas. Les trois entrées thermiques de data/seuils_etat.json portent un
seuil UNIVERSEL ; les basculer vers seuil_propriete toucherait banc_faim_thermo,
fichier d'un autre chantier. Le catalogue LOCAL de ce banc n'utilise QUE
seuil_propriete : ses cinq entrées lisent leur seuil sur chaque vivant. Deux
vivants côte à côte, dans le même monde au même instant, franchissent donc des
seuils différents — et l'arctique RESSENT le froid (miroir non nul, frisson posé)
sans en être STRESSÉE, parce qu'elle ne porte aucun poids dessus. Ressentir n'est
pas souffrir : c'est le poids qui sépare les deux, et il est en donnée.

Troisième chose : JAMAIS UN abs(), ÉTENDU À L'EAU. La décision datait de
hyperthermie et ne portait que sur la température. Ici quatre bascules — froid
sous temp_cible, chaud au-dessus de seuil_chaud, sécheresse sous seuil_sec, excès
d'eau au-dessus de seuil_humide — avec quatre poids indépendants. Le même écart
de 10 degrés coûte 0.10 d'un côté et 0.30 de l'autre ; le même écart de 0.10
d'humidité pèse 0.20 en trop et 0.10 en trop peu. Entre les deux seuils d'eau
s'étend une bande où l'eau ne contribue EXACTEMENT rien.

Quatrième chose : LA MORT EST DÉFINITIVE PAR UN GATE DE CÂBLAGE, jamais par un
mécanisme. Le stress étant recalculé à neuf, mort_stress est réversible par
construction — sans gate, réchauffer l'ambiante ferait ressusciter la plante au
clic suivant. Le câblage cesse donc de recalculer le stress dès l'état posé, et
met à zéro le coût de base ET le surcoût : un mort ne dépense plus. Un chantier
qui voudrait verrouiller la mort STRUCTURELLEMENT devrait comparer une grandeur
monotone, pas une somme recalculée.

Un écart à la consigne, assumé et signalé : elle ne citait que trois sources de
stress (froid, excès d'eau, sécheresse). « L'arctique meurt de chaud » est
infaisable sans une quatrième. Elle a coûté zéro ligne de code — la liste des
sources est de la donnée, le fichier n'en nomme aucune.

Le piège du constat (A) de l'audit est tenu par une CHAÎNE, pas par une ligne :
déclarer que stress_leger module croissance ne produit rien tant que personne
n'appelle EtatEffectif.valeur. Le câblage compose la croissance effective puis la
passe à flux.gd comme taux d'un émetteur synthétique alimentant une réserve de
maturité. Une plante stressée pousse réellement deux fois moins vite ; une plante
morte ne pousse plus. Sans cette chaîne, le ×0.5 serait vrai dans le catalogue et
sans le moindre effet, en silence.

**Ne montre pas.** l'effet de mort_stress sur
`vitesse` est DORMANT — aucun vivant ne s'y déplace, il est déclaré parce que la
ligne 8 de l'audit le demande. Et il n'y a aucune température de CORPS
(temperature.gd:avancer jamais appelé) : le froid ressenti est celui du lieu, pas
celui de la bête — une vraie inertie thermique exigerait une composition et
Objet.fabriquer, c'est un autre chantier.

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

## banc_ecosysteme_terrain — la forêt cache les proies, le désert ne nourrit que huit, et le territoire s'ouvre quand la chasse maigrit

`Scene/banc_ecosysteme_terrain.tscn`, `scripts/banc_ecosysteme_terrain.gd`, `data/banc_ecosysteme_terrain.json`. Test : `scripts/test_banc_ecosysteme_terrain.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_ecosysteme_terrain`.

**Montre.** une grille 8×8 en trois bandes de biome — forêt à
gauche, prairie au milieu, désert à droite. Six proies, trois prédateurs.
Les DEUX proies de forêt sont vert foncé : leur biome porte 0.6 de couvert,
elles sont CACHÉES, et aucun prédateur ne les voit jamais — les quatre autres
sont vert clair et se font manger. Chaque prédateur porte un CERCLE tracé à
son rayon de territoire réel, qui s'ouvre à mesure que les proies se
raréfient. Label par case (biome, refuge, population/capacité, surpeuplement),
label par prédateur (énergie, territoire, densité, proies retenues, cible),
compteur proies/prédateurs/morts, trace console à chaque changement — biome,
profil de saillance, surpeuplement, mort — jamais l'état stable.

**Prouve.** — LE REFUGE CACHE UNE PROIE, PAS TOUTES. Le câblage réécrit chaque tick la clé
plate `profil_saillance` de la proie entre deux profils déclarés en donnée.
Les deux autres voies sont FAUSSES et écartées explicitement : moduler la
portée de perception du prédateur le rend aveugle à TOUT (perception.gd lit
portée et sensibilité sur le PERCEPTEUR, jamais sur la chose perçue) ; un état
`cache` qui modulerait `saillance_intrinseque` serait vrai dans data/etats.json
et sans le moindre effet, EN SILENCE (proximite.gd lit ce nombre dans le
catalogue, jamais sur l'objet, et n'appelle jamais etat_effectif.gd). Ce qui
exclut réellement la proie cachée n'est PAS proximite.gd mais le seuil de
décision du prédateur, au câblage : une proie cachée plafonne à 0.8 sous un
seuil de 1.5, donc à TOUTE distance, y compris collée au prédateur.
— PREMIER ÉCRIVAIN DYNAMIQUE DE `canaux_config` DU DÉPÔT. perception.gd relit
`portee` sur `canaux_config.<canal>` à chaque appel ; rien dans le cœur ne s'y
oppose, mais aucun banc ne le faisait. Le territoire est recalculé À NEUF
depuis `rayon_territoire_base` divisé par la densité mesurée dans un rayon
d'échantillonnage FIXE — jamais depuis la portée courante, sinon il dériverait
tick après tick. Densité nulle : `max(0.1, densité)` rend le rayon MAXIMUM,
jamais INF.
— LA CAPACITÉ DE CHARGE VARIE PAR BIOME sans une ligne de code : le seuil est
lu PAR CASE (`seuil_propriete : "capacite_charge"`, posée par conditions.gd),
exactement comme `point_fusion` varie par matériau. Une case sans biome n'en
porte aucune, replie sur INF, ne surpeuple jamais.
— LES COLLECTIFS N'EXISTENT PAS, littéralement : aucune case ne porte de
réserve de population. Chaque animal a SA réserve, meurt SEUL, et la
population est un `Comptage.compter` refait à neuf chaque tick.

**Contrôles.** clic gauche = lève/rétablit le refuge (+0.45 sur la fraction de
chaque biome, borné à 1) — toutes les proies se cachent d'un coup et les trois
prédateurs meurent de faim. Clic droit = pose/retire huit proies dans le
désert, dont la capacité est 8 : la population locale passe à 11, le
surpeuplement se pose, l'énergie de tout ce qui y vit se met à descendre, les
plus faibles meurent, et la population redescend d'elle-même sous la capacité.
Leurs énergies de départ sont ÉTAGÉES : à énergies égales elles mourraient
toutes au même instant et la population s'effondrerait d'un coup au lieu de se
réguler individu par individu — et c'est cette redescente qui EST la capacité
de charge.

RÉSULTAT NÉGATIF, trouvé EN LANÇANT LA SCÈNE et invisible au test — interdit
de le refaire : dans le premier jet, la chasse passait AVANT depense.gd. La
proie était vidée, puis son `cout_base` NÉGATIF (le broutage) la remplissait
dans le MÊME tick. Conséquence mesurée, console en main : une proie chassée se
stabilisait à `taux_broutage × delta` (0.07 à 60 images/s) et NE MOURAIT
JAMAIS, pendant que le prédateur ne recevait plus que ce filet et perdait de
l'énergie EN CHASSANT une proie qu'il ne pouvait pas achever. Rien ne
rougissait nulle part : les deux mécanismes faisaient exactement ce qu'ils
promettent, c'est leur ORDRE qui était faux. La chasse est donc le DERNIER
mouvement d'énergie du tick, et un cas de test dédié la verrouille là.

**Ne montre pas.** aucune REPRODUCTION (la
population ne fait que descendre — c'est la ligne 11 de l'audit), aucune
OSCILLATION proies/prédateurs (ligne 5), aucune AGRESSION ni hiérarchie —
agir.gd et dominance.gd ne sont pas montés ici, le prédateur ne choisit pas
entre plusieurs gestes (lignes 6 et 7). Il n'y a pas un seul RNG dans le
fichier : les proies ne bougent pas, et un prédateur qui ne retient rien ne
bouge pas non plus — un prédateur aveugle qui patrouillerait au hasard rendrait
la famine par refuge indistinguable d'une famine par malchance.

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

## banc_parasites_reproduction — trois parasites, six herbivores : la population naît, s'infeste, se réinfeste et meurt

`Scene/banc_parasites_reproduction.tscn`, `scripts/banc_parasites_reproduction.gd`, `data/banc_parasites_reproduction.json`. Test : `scripts/test_banc_parasites_reproduction.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_parasites_reproduction`.

**Montre.** six herbivores (grands carrés) et trois parasites
(petits carrés noirs) errant dans une zone. Un herbivore à portée d'un parasite
devient jaune (incubation — déjà contagieux pour ses congénères, aucun
symptôme), puis orange (infesté, vitesse ×0.6), puis soit vert à nouveau
(guéri — et immédiatement réinfestable, le canal n'est jamais retiré), soit
rouge et immobile (mort de parasitose). Les adultes verts qui se croisent assez
longtemps, réserves hautes, font un petit BLEU CLAIR qui grandit et devient
fertile à son tour. Les parasites pondent quand ils trouvent assez d'hôtes par
parasite, et meurent de vieillesse. Compteur en haut d'écran : sains / petits /
incubation / infestés / morts, parasites, naissances, facteur de temps. Label
par individu : nom, état, stade, charge d'infestation, gestation, vitesse
effective. Trace console à chaque transition. Clic gauche : ajoute ou retire
tous les parasites (bistable). Clic droit : accélère le temps (bistable).

LA DIFFÉRENCE AVEC banc_maladie, ET C'EST LE SUJET : là-bas un colon contaminé
se fait retirer son canal receveur POUR TOUJOURS (« porteur ou mort, jamais à
nouveau susceptible »). Ici le canal reste toute la vie de l'hôte, sa charge
peut redescendre (taux_decroissance non nul, là où banc_maladie a un cliquet à
0.0) et remonter. La garde contre une double incubation est donc un gate de
câblage (`peut_incuber`, patron banc_elimination_salete), jamais le retrait du
canal. Corollaire de calibration, voulu : le seuil de mort (14.0 de cumul) est
AU-DESSUS de la durée de `infeste` (12.0 s) — la première infestation ne tue
pas, elle use ; c'est la seconde qui tue. L'inverse exact de banc_maladie
(létalité totale dès la première fois).

CE QUI TIENT LE COUPLAGE — deux nombres, pas un : `min_hotes_par_parasite`
(hôtes vivants PAR parasite dans portee_ponte) et `max_voisins_hote` (hôtes
dans portee_rencontre). RÉSULTAT NÉGATIF MESURÉ, à ne pas refaire : un gate de
ponte sur le nombre d'hôtes ABSOLU ne freine RIEN — chaque parasite pond
indépendamment, aucun ne consomme la ressource, et la suite de tests a
réellement PENDU (les deux espèces en croissance exponentielle simultanée).
Freiner les seuls parasites ne fait que déplacer l'explosion sur les hôtes : la
mortalité parasitaire est leur SEUL frein, et elle disparaît justement quand
les parasites se raréfient. Il faut les deux bouts.

QUATRE AUTRES DÉFAUTS TROUVÉS EN LANÇANT, invisibles à l'écriture, tous fermés
et verrouillés par un cas de test : (a) un porteur s'infestait LUI-MÊME (il est
une cause à distance zéro de lui-même et charge.gd somme tout ce qui est à
portée) — sa charge ne redescendait jamais et la réinfestation était
impossible ; fermé en appelant Charge.avancer hôte par hôte, causes privées de
la sienne ; (b) les petits nommés `<espece>_<n>` heurtaient les `parasite_0/1/2`
de la donnée — monde.gd refuse un id déjà présent et la chose n'était PAS
enregistrée, en silence ; préfixe `petit_` obligatoire ; (c) un cadavre de
parasite PONDAIT (la liste des vivants est figée en tête de tick, le Monde n'est
reconstruit qu'à la fin) — fermé en refaisant la liste juste après les morts ;
(d) le test acceptait « au moins une mort » alors que les seules morts
observées en scène réelle étaient des parasites de VIEILLESSE : aucun hôte ne
mourait, la couleur rouge n'apparaissait jamais. L'assertion exige désormais
une mort PAR PARASITOSE et une RÉINFESTATION sur le chemin réel.

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

## banc_temps_anticipation — trois colons, le même automne, et un seul se prépare

`Scene/banc_temps_anticipation.tscn`, `scripts/banc_temps_anticipation.gd`, `data/banc_temps_anticipation.json`. Test : `scripts/test_banc_temps_anticipation.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_temps_anticipation`.

**Montre**, deux choses à la fois. le fond suit le jour et la nuit, le label du haut
donne l'heure et la saison. Une saison dure 16 s, une année 64 s. À chaque
changement de saison la console imprime une ligne et le compte de saisons vécues
de chaque colon monte de 1.

Ensuite les TROIS COLONS, un label chacun. Ils portent trois comptes de départ
(0.1 / 3.0 / 8.0) pour un seuil commun de 4.0. Le vieux est PRÉVOYANT dès le
premier instant (carré jaune), l'adulte le devient à t = 32 s sous les yeux, le
jeune reste vert. Quand l'AUTOMNE arrive (t = 32 s à 48 s), le grenier vire du
brun à l'ORANGE : la saillance qu'il a pour un colon prévoyant monte, et pour le
jeune elle ne bouge pas d'un poil — même monde, même instant, même grenier.
Passé l'automne le biais retombe et le grenier redevient brun.

Chaque label porte aussi la PERCEPTION DU TEMPS des deux repères (bleus). Celui
du bas reste à portée de vue : il est « C'était hier » pour toujours. L'autre
part à t = 3 s et traverse les trois textes — « C'était hier », puis « Il y a un
moment », puis « Il y a longtemps », puis plus rien du tout quand le souvenir
tombe sous le plancher et est retiré.

**Prouve.** LE COLON LIT LE TEMPS
DANS SES SOUVENIRS, JAMAIS SUR UNE HORLOGE. Les deux repères sont partis du même
instant et le même temps s'est écoulé pour les deux ; ce qui les sépare est que
l'un est revu et l'autre non. Le champ age_marque d'epigenetique.gd EST un
horodatage réel, disponible, et il est écarté exprès : l'utiliser contredirait
la ligne.

Deuxième chose : ANTICIPER N'EST PAS UN TRAIT, C'EST UN COMPTE. Les trois colons
sont identiques à leur compte près — même seuil, même débit, même catalogue. Le
jeune n'a pas une autre nature : il est plus bas sur la même échelle, et laissé
tourner assez longtemps il deviendrait prévoyant lui aussi (c'est le sujet, pas
un défaut). Ce qui fait que le vieux anticipe PLUS FORT n'est pas une seconde
entrée de catalogue mais un débit de pose plus grand — base + gain × compte.

**Ne montre pas.** PERSONNE NE SE DÉPLACE. Le banc
monte la couche 2 (proximite.gd) et s'arrête là — ni dominance.gd, ni agir.gd,
ni ciblage.gd. On voit la saillance du grenier monter, on ne voit pas le colon
aller le remplir. Brancher la chaîne complète de décision est un chantier
suivant, pas celui-ci.

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

## banc_predation — huit proies, trois prédateurs : le dominant mange, le second attend, et les deux populations oscillent

`Scene/banc_predation.tscn`, `scripts/banc_predation.gd`, `data/banc_predation.json`. Test : `scripts/test_banc_predation.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_predation`.

**Montre.** huit proies vertes à gauche, trois prédateurs rouges à
droite, taille proportionnelle à la masse. Les prédateurs ont faim, leur charge
d'agression monte, ils bifurquent, la proie qu'ils visent gagne en saillance et
ils chassent. Les proies fuient quand un prédateur approche, broutent sinon.
Quand deux prédateurs atteignent la même proie, le plus fort mange et l'autre
attend — la trace console le dit nommément. Les morts laissent un reste gris et
quittent le Monde ; les petits naissent jaunes, grandissent, deviennent
fertiles. Label par animal : énergie, stade, état d'agression, score de
hiérarchie. Compteur en haut : proies, prédateurs, naissances, morts, tick,
facteur de temps. Deux barres verticales à gauche : les deux populations, qui
montent et descendent. Clic gauche : facteur de temps suivant (×1 → ×3 → ×8).

**Prouve.** UNE POPULATION QUI
NAÎT ET MEURT EN CONTINU. Tous les autres bancs ont un casting fixe ;
banc_reproduction.gd fait naître UN enfant, une fois, d'UN couple. Ici la
naissance et le retrait (par RECONSTRUCTION du Monde — monde.gd n'a aucune
fonction de retrait) sont le geste central du tick.

Deuxième chose : LA HIÉRARCHIE DÉCIDE QUI MANGE, ET ELLE EST HÉRÉDITAIRE. Le
score est une somme pondérée masse/force recalculée à neuf, triée par le
câblage — ni dominance.gd (il écrase, il n'élit pas) ni frappe.gd (aucune source
« propriété plate ») ne savent le faire. Comme la force est la cible du gène
vigueur, un petit de dominant naît plus fort et mangera en premier à son tour.

Troisième chose : TROIS CAUSES D'AGRESSION, UNE SEULE CHARGE, UNE SEULE SORTIE.
charge.gd somme les trois contributions (« attaque-t-il ? »), bifurcation.gd
prend l'argmax des mêmes trois produits (« pourquoi ? »). Les trois prédateurs
ne diffèrent que par leur biais : le chasseur attaque par faim, le territorial
par densité d'intrus, le protecteur pour ses petits.

Quatrième chose : LES CYCLES ÉMERGENT DU COUPLAGE, ils ne sont écrits nulle
part. Le délai vient de la gestation ET des stades juvéniles — un nouveau-né
n'est pas fertile, la population de proies ne répond donc pas instantanément à
la pression de prédation.

DEUX RÉSULTATS NÉGATIFS MESURÉS, à ne pas repayer. (1) UN PROFIL DE SAILLANCE NE
PEUT PAS SERVIR LES DEUX SENS : une chose n'a qu'une saillance, la même pour
tous ceux qui la regardent (proximite.gd la lit dans le catalogue, jamais sur
l'objet). Prédateur 6.0 contre proie 3.0 donnait ZÉRO repas en 60 s — les
prédateurs se rejoignaient au lieu de chasser, tous les cas isolés restant
verts. Fermé en inversant les profils ET par une déformation de vigilance côté
proie : la déformation est PAR PERCEVANT, c'est la seule voie qui laisse deux
espèces lire le même monde différemment. (2) CE SONT LES DÉLAIS, PAS LES TAUX,
QUI FONT LE CYCLE : une première calibration de reproduction donnait une
décroissance monotone, les prédateurs ne restant jamais au-dessus de leur seuil
assez longtemps pour mener une gestation à terme.

**Ne montre pas.** il n'y a AUCUN combat — un
prédateur territorial CHARGE son congénère, il ne lui inflige rien (frappe.gd
n'est pas câblé). Les restes ne sont pas dans le Monde (décision de coût). Le
plafond de population est une borne d'OBSERVABILITÉ, pas une capacité de charge
— la vraie est spatiale et vit dans banc_ecosysteme_terrain.gd. Et l'extinction
des prédateurs est DÉFINITIVE : rien ne repeuple, donc le banc montre deux ou
trois cycles, puis des proies seules au plafond.

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

## banc_marche_competence — trois colons, un seul lingot, et trois prix qui n'ont rien à voir

`Scene/banc_marche_competence.tscn`, `scripts/banc_marche_competence.gd`, `data/banc_marche_competence.json`. Test : `scripts/test_banc_marche_competence.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_marche_competence`.

**Montre.** À gauche l'atelier : la forge (orange), son cercle de
portée, deux tas. À droite le comptoir : trois tas. Trois colons — un FORGERON
déjà compétent et un APPRENTI qui ne sait rien, tous deux à la forge ; un NOVICE
posté au comptoir. Les trois lisent le même monde et n'en tirent pas les mêmes
nombres.

LE PRIX. Le novice, avec sa longue portée de vue, voit les cinq tas et trouve le
lingot bon marché (~8). Les forgerons ne voient que le tas de l'atelier et le
trouvent cher (~40). Le même lingot, au même instant, à trois prix — parce que le
prix est un champ DÉRIVÉ écrit sur chaque colon, jamais un état posé sur un
marché. Clic gauche : un tas disparaît, le prix de qui le voyait monte, celui des
autres ne bouge pas d'une décimale.

LA SPÉCIALISATION. La forge est saillante ×4.8 pour le forgeron installé et à sa
valeur nue pour le novice. Le novice n'a AUCUNE déformation — pas parce qu'un cas
particulier l'exclut, mais parce que sa compétence effective est nulle et qu'une
magnitude nulle ne se pose pas.

L'HABITUDE. Touches 1/2/3 : le colon correspondant se met à forger ou s'arrête.
Sa barre verte monte en trois secondes, sa vitesse de forge avec elle, et le tas
de l'atelier grossit plus vite sous les yeux. Il s'arrête : le rythme se perd.

LE PLANCHER. Le forgeron arrête de forger. Sa barre orange descend, passe sous le
trait rouge du plancher, et la marque finit par être RETIRÉE par epigenetique.gd
(ligne console). Sa compétence effective, elle, s'arrête net sur le trait : le
vétéran rouillé reste un forgeron. L'apprenti, dont le plancher vaut zéro,
retombe à rien.

**Prouve.** UN PRIX N'EST PAS UN
FAIT DU MONDE, C'EST UNE LECTURE. Rien ne distingue les trois colons que leur
portée de perception, et pourtant leurs estimations n'ont rien à voir. L'offre
est un TOTAL (somme.gd) sur ce que ce colon perçoit, la demande un COMPTE
(comptage.gd) sur les colons affamés — deux questions, deux briques de la couche
lecteur, jamais un seul fichier.

Deuxième chose : plancher_suppression N'EST PAS UN PLANCHER. Sous lui,
epigenetique.gd RETIRE l'entrée — un vétéran ne se rouillerait pas, il
redeviendrait novice d'un coup. Le plancher réel est un clamp à la lecture, et il
est une donnée PAR COLON : écrit comme constante du câblage, il donnerait 0.3 au
novice aussi et « la forge n'est pas plus attractive pour lui » serait faux tous
tests verts. Prix payé, dit plutôt que masqué : age_marque repart de zéro à la
prochaine pose, l'ancienneté de la compétence est perdue.

**Ne montre pas.** PERSONNE NE SE DÉPLACE. Le banc
monte la couche 1 (perception.gd) et la couche 2 (proximite.gd) et s'arrête là —
ni dominance.gd, ni agir.gd, ni ciblage.gd. On voit la forge devenir plus
attractive pour le forgeron, on ne le voit pas y aller. Brancher la chaîne
complète de décision est un chantier suivant, pas celui-ci. Manque aussi : rien
n'ACHÈTE. Le prix est estimé, il n'est jamais payé — aucune transaction, aucun
transfert de monnaie ; c'est la ligne suivante de l'audit, pas celle-ci.

Écart à la consigne, assumé : trois colons à forger ne tiennent pas sur deux
boutons de souris — clic gauche pour les tas, touches 1/2/3 pour la forge.

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

## banc_infrastructure — le grenier se remplit, refuse, et la route s'use sous ceux qui l'empruntent

`Scene/banc_infrastructure.tscn`, `scripts/banc_infrastructure.gd`, `data/banc_infrastructure.json`. Test : `scripts/test_banc_infrastructure.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_infrastructure`.

**Montre.** un tas de marchandise dehors à gauche, un grenier à
droite, une route dorée de quatre cases entre les deux, et cinq colons qui font
la navette (bleus à vide, orange chargés). Quatre boutons en haut : +5 colons,
-5 colons, agrandir le grenier, réparer la route. Compteur : population active,
seuil de coordination, rythme effectif, remplissage du grenier. Trace console par
seconde.

Quatre phénomènes, chacun observable seul.

LE GRENIER SE REMPLIT ET REFUSE. Sa barre monte, il passe de 120 à 500 en une
vingtaine de secondes, puis vire au rouge et affiche ENCOMBRE. Les colons
s'entassent devant AVEC leur charge et n'en perdent pas un gramme — la console
compte les refus. « AGRANDIR » rend 100 de capacité et la file repart. C'est la
différence entre REFUSER et ÉCRÊTER : banc_fertilite écrête (le surplus est
perdu, et c'est correct pour un sol saturé) ; ici le porteur garde ce qu'il a
transporté à travers toute la carte.

LES LOTS DEHORS MEURENT VITE. Six lots : trois sous le grenier (verts), trois au
tas (rouges). En douze secondes les rouges sont noirs et à zéro ; au même
instant les verts sont encore à 86 sur 100. « Suis-je à l'abri » n'est pas un
drapeau posé à la main mais une comparaison de positions — déplacer un lot sous
le grenier le sauve, sans une ligne de code.

LA COORDINATION COÛTE. Chaque « +5 COLONS » ajoute des porteurs ; au-delà de 20
actifs, l'état surpeuplement est posé et le rythme effectif de CHACUN tombe (0.6
à trente colons). Le débit total cesse de suivre le nombre.

LA ROUTE S'USE ET SE RÉPARE. Les cases grisent d'autant plus vite qu'il y passe
du monde ; à zéro, le bonus de vitesse disparaît d'un coup et les colons
ralentissent à vue d'œil. « RÉPARER » le rend. Avec cinq colons il faut une
cinquantaine de secondes de trafic continu pour user la route — ajouter des
colons la tue bien plus vite : c'est ce qui relie la coordination aux routes.

**Prouve.** UN ÉTAT POSÉ PAR LE
CÂBLAGE PARCE QU'UN SEUIL NE PEUT PAS LE POSER. seuil_etat.gd compare
strictement vers le haut, alors que le refus est « réserve >= capacité » : à la
réserve pile égale à la capacité, le refus serait vrai et l'état absent. Deux
vérités qui divergent exactement au bord, c'est-à-dire la désynchronisation
silencieuse qu'« un seul écrivain » existe pour empêcher. Un seul prédicat sert
donc le refus ET l'état.

Deuxième chose : LA MATIÈRE SE CONSERVE DE BOUT EN BOUT. Tas + ce que portent
les colons + grenier reste invariant sur toute la durée, sans qu'aucun câblage
ne compte quoi que ce soit — consommer.gd est conservatif par construction.

DEUX ÉCARTS ASSUMÉS, dits plutôt que masqués. (1) « cout_base par passage »
n'est pas exprimable : cout_base est un coût par SECONDE. Le trafic passe donc
par surcout_action, ce qui est exactement la frontière que depense.gd pose —
cout_base est ce que la route EST, surcout_action est l'action en cours. (2) un
défaut trouvé en lançant la scène, pas au test : les colons arrêtés devant un
grenier plein restent dans le rayon de la dernière case et usaient la route à
plein régime. Une route usée par des gens qui attendent n'a aucun sens ; le
trafic ne compte plus que les colons EN TRANSIT.

**Ne montre pas.** PERSONNE NE DÉCIDE. Ni
perception.gd, ni proximite.gd, ni dominance.gd, ni agir.gd — la navette est une
machine à états de câblage. On voit une logistique, pas un agent qui CHOISIT
d'aller au grenier parce que sa saillance monte. Brancher la chaîne de décision
est un chantier suivant. Les lots à intégrité nulle ne se transforment pas non
plus (aucun produit.gd ici) : ils restent, noirs, à zéro.

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

## banc_economie — la masse ne bouge pas, et le colon ne va pas chercher la miette

`Scene/banc_economie.tscn`, `scripts/banc_economie.gd`, `data/banc_economie.json`. Test : `scripts/test_banc_economie.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_economie`.

**Montre.** Un colon, deux minerais proches, un gisement lointain, une
miette au fond à droite. Deux lieux : la forge (orange) et le grenier (bleu). En
haut de l'écran, un seul nombre — la masse totale du monde — qui ne bouge JAMAIS.

LE PORTAGE. Le colon ramasse un minerai : la ressource perd exactement ce que le
colon gagne, et sa masse fabriquée, elle, n'est jamais réécrite (ce qui bouge est
une réserve nommée). Chargé, il marche visiblement plus lentement — 66 unités/s
contre 220 à vide — et sa fatigue monte en proportion de ce qu'il porte. Il ne
charge jamais jusqu'à sa capacité (fraction_charge_max 0.7) : à charge égale à la
capacité, la vitesse composée rend exactement 0.0 et il serait cloué au sol. Les
gisements portent plusieurs charges, donc plusieurs allers-retours chacun.

LA FONTE. À la forge, il dépose. Le tas fond en DEUX objets — un lingot (0.85) et
un tas de scories (0.15) — dont la somme des masses égale exactement ce qui a été
fondu. C'est le point du banc : produit.gd, seul, perd le complément de son
rendement sans destination ; deux appels sur le même ancien ferment la fuite. Le
lingot repart au grenier (sa destination vient de la chose, pas d'une branche de
code) ; les scories restent au sol pour toujours, parce qu'elles ne portent pas
la propriété que le colon cherche.

LE COÛT DE TRAJET. La miette du fond est PERÇUE, évaluée, et RETIRÉE avant la
dominance : son score (valeur divisée par le coût du trajet) vaut 0.15 pour un
seuil de 1.00. Le colon ne va jamais la chercher — pas même quand elle est la
seule chose qui reste au monde. Le gisement lointain, lui, passe le seuil mais
reste écrasé par dominance.gd tant qu'une ressource proche existe : deux
arbitrages distincts, l'un absolu, l'autre relatif. Clic gauche : les ressources
proches sortent du plateau, et le gisement devient la décision sans que son score
ait bougé d'un chiffre. Re-clic : elles reviennent, avec leur réserve intacte.

LE CLIC, CORRIGÉ APRÈS OBSERVATION À L'ÉCRAN (Yael : « ton clic gauche ne fait
rien »). Le défaut était double et aucun test ne pouvait le voir : le colon
épuisait les deux ressources proches en moins de sept secondes, donc passé ce
délai le clic ne trouvait plus rien à sortir — et il l'écrivait en console, où
personne ne regarde pendant qu'une scène tourne. Trois corrections : le clic est
devenu une BASCULE (sortir puis remettre, la conservation tenant dans les deux
sens) ; les gisements proches portent désormais 420 et 378 kg, ce qui laisse plus
de cent secondes pour jouer avec ; et le label d'aide dit en permanence ce qui est
hors plateau, avec un COMPTEUR DE CLICS REÇUS.

CE QUE CE COMPTEUR EXISTE POUR TRANCHER, et qui dépasse ce banc : aucun clic
d'aucun banc du dépôt n'a son routage confirmé à l'écran — ETAT.md le dit banc par
banc, « en headless aucun clic n'existe ». S'il monte quand on clique,
_unhandled_input route correctement dans un banc Node2D et les 73 bancs qui en
portent un sont saufs. S'il reste à zéro, le défaut est le routage, et il est
partagé.

UNE ÉMERGENCE NON PRÉVUE, gardée : les scores du minerai proche et du gisement
lointain S'INVERSENT selon l'endroit d'où le colon décide. Depuis la forge, le
proche vaut 1.85 contre 1.04 ; depuis le grenier, où il revient après chaque
lingot, c'est 0.98 contre 1.53 — le proche tombe même sous le seuil de
rentabilité. Le colon exploite donc le gisement lointain avant d'avoir fini le
proche, ce qu'aucune ligne ne lui dit de faire : un coût de trajet se mesure
depuis là où l'on est.

**Ne montre pas.** aucune saillance de
proximite.gd (les entrées sont construites par le câblage depuis une propriété
locale — passer par le catalogue partagé de profils aurait coûté des entrées
partagées pour un banc jetable), aucun verbe résolu par agir.gd (la phase du
colon EST sa décision), aucune vélocité dérivée. Le colon ne peut pas se clouer
au sol, mais rien ne l'en empêche structurellement : à charge égale à la
capacité, la vitesse est exactement nulle — c'est la calibration qui l'évite, et
le cas dégénéré est verrouillé positivement par test.

AMBIGUÏTÉ DE LA CONSIGNE, tranchée et à confirmer : elle demandait qu'une même
ressource lointaine soit filtrée ET qu'elle « passe le filtre » une fois les
proches retirées. Sous un seuil absolu les deux ne tiennent pas ensemble — d'où
DEUX choses lointaines, le gisement (qui passe, et que seule la dominance
écrasait) et la miette (qui ne passe jamais).

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

## banc_affordances_travail — l'un abat, l'autre renonce, le troisième ne peut rien

`Scene/banc_affordances_travail.tscn`, `scripts/banc_affordances_travail.gd`, `data/banc_affordances_travail.json`. Test : `scripts/test_banc_affordances_travail.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_affordances_travail`.

**Montre.** Trois colons, trois outils, trois arbres, un lit. En haut
de l'écran, un bilan de masse et un compteur de trois issues.

CE QUI COUPE PEUT COUPER. Le bûcheron porte un outil en fer, l'apprenti un outil
en pierre, le manœuvre un outil en bois. Le manœuvre marche jusqu'à l'arbre et
n'y fait STRICTEMENT RIEN : son outil est sous le seuil, il n'entre même pas dans
la liste d'agents, le travail ne bouge pas d'un chiffre. C'est un REFUS, pas un
rendement nul — la différence se voit, la barre de travail reste immobile. La
teinte de son outil reste rouge quand celle des deux autres est verte.

LE TRAVAIL EST SUR L'ARBRE, PAS DANS LE COLON. La barre de travail descend à la
somme des rythmes de ceux qui sont présents. Un colon qui part cesse simplement
de contribuer ; un autre qui arrive reprend sur ce qui reste, jamais sur un
compte neuf. Rien n'a été câblé pour ça : c'est le seul modèle qui existe.

IL RENONCE, PUIS IL VA DORMIR. L'apprenti voit les trois arbres et n'en entame
aucun : douze secondes de travail pour onze secondes d'autonomie. Il attend,
fatigue, passe sous le seuil, marche jusqu'au lit — et ne récupère qu'une fois
ARRIVÉ, parce que la recharge est un transfert à portée. Il se réveille au-dessus
de son seuil de satisfaction sans qu'aucun seuil de réveil ne soit écrit nulle
part, puis repart travailler.

L'ENTAILLE. Un chantier lâché en route porte une entaille qui se dégrade — plus
vite sous la pluie. Si personne ne revient, l'arbre cicatrise et TOUT le travail
déjà fourni est perdu. Si un colon revient, l'entaille se referme d'elle-même.

L'ISSUE DÉPEND DE L'ÉTAT DE CELUI QUI FRAPPE. Un arbre bien abattu donne une
bûche, un arbre massacré des copeaux, un arbre saccagé un résidu — trois objets
réellement différents, fabriqués et posés dans le monde. Rien n'est tiré au sort :
la fatigue et la qualité de l'outil composent le choix, deux colons dans le même
état donnent toujours la même issue.

LE BILAN DIT CE QUI SE PERD. Contrairement à banc_economie, les trois issues ne
somment pas à 1.0 : rater DÉTRUIT vraiment de la matière. L'affichage montre
« monde + perdu à la coupe », qui reste constant — la matière perdue n'est pas
escamotée du bilan, elle y figure comme perdue.

**Ne montre pas.** L'abandon
spontané est STRUCTURELLEMENT impossible : une fois le chantier entamé, le
travail restant baisse plus vite que l'autonomie, la marge ne peut que
s'améliorer. C'est exactement ce que la marge de sécurité achète, et c'est
pourquoi le clic droit existe — sans lui, zéro entaille en quarante-cinq
secondes. Pour la même raison, l'issue « débris » n'apparaît pas dans la
calibration par défaut : la marge évite précisément le désastre qu'elle
représente. Elle est prouvée atteignable par le test, pas produite par la scène.

DEUX NOMBRES CORRIGÉS APRÈS LANCEMENT, tous deux invisibles au test. Le biais de
débris (1.6 → 2.0) : la pénalité maximale réellement atteignable est bornée par
le gate d'entame lui-même, et à 1.6 la troisième sortie ne gagnait JAMAIS — elle
existait en donnée et était morte. Le sommeil de départ de l'apprenti
(46 → 34) : il renonçait seize secondes avant de bouger, correct et illisible.
S'ajoute un défaut de console — un refus est un ÉTAT, le tracer tel quel
remplissait le terminal à chaque frame ; seule la bascule est tracée désormais.

**Ne montre pas.** rien côté simulation. Côté écran,
tout reste à confirmer à l'œil — les couleurs, les barres, la teinte de l'outil,
la lisibilité des labels. Les DEUX CLICS (gauche : basculer l'humidité ; droit
sur un colon : l'épuiser, ce qui lui fait lâcher son chantier) suivent le même
protocole que les autres bancs : cliquer et regarder si la console réagit — si
elle reste muette, c'est le routage d'entrée qu'il faut ouvrir, pour tous les
bancs à la fois.

## banc_affordances_portage — un colosse ou deux hommes, mais deux mains sur l'échelle

`Scene/banc_affordances_portage.tscn`, `scripts/banc_affordances_portage.gd`, `data/banc_affordances_portage.json`. Test : `scripts/test_banc_affordances_portage.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_affordances_portage`.

**Montre.** Trois chantiers côte à côte, rouge tant qu'il manque
quelque chose, vert dès que la condition est remplie, gris une fois accompli.
Sous chaque cible, les trois exigences et les trois totaux atteints ; sous chaque
colon, sa force et sa stabilisation.

DEUX HOMMES OU UN COLOSSE PORTENT LE TRONC. Le tronc demande 1.6 de force. Le
colosse en a 1.8 : il le soulève seul. Un faible en a 0.9 : il reste devant sans
que le travail bouge d'un chiffre. Les deux faibles ensemble en font 1.8 — la
MÊME somme que le colosse — et le tronc part. Rien dans le calcul ne distingue un
agent à 1.8 de deux agents à 0.9 : c'est une somme sur une liste, un point.

L'ÉCHELLE A DEUX BOUTS. Elle ne demande que 0.9 de force, moitié moins que le
tronc, et le colosse — deux fois trop fort — reste bloqué devant. Ce n'est pas un
manque de force : c'est le second gate, le NOMBRE. N'importe quel second porteur
débloque, même le plus faible. Deux gates SÉPARÉS sur la MÊME liste, sa somme et
sa taille — un gate composite unique (une force divisée par un nombre) n'aurait
jamais pu produire ce refus-là.

L'ÉTAU FAIT LE TRAVAIL D'UN AIDE. L'enclume ne demande aucune force particulière,
elle demande d'être TENUE. Un porteur seul apporte 0.5 de stabilisation pour 1.0
exigé : refusé. À côté de l'étau (1.0), ça passe. Sans l'étau mais à deux colons
(0.5 + 0.5), ça passe aussi. L'étau ne porte NI rythme NI force : il n'est ni
agent de chantier ni porteur — seulement stabilisateur. Un objet et un colon sont
interchangeables sur cette propriété, et aucune ligne ne demande si un
contributeur est vivant.

LE REFUS N'EST PAS UN RALENTISSEMENT. Quand une condition manque, le câblage ne
construit simplement pas la liste d'agents ; extinction.gd sort par `somme <= 0.0`
sans jamais rien savoir d'un refus. Mesuré et verrouillé : mille ticks sous le
seuil n'entament pas le chantier d'un chiffre. C'est exactement ce qui manquait à
extinction.gd employé seul, qui aurait fait avancer le travail plus lentement au
lieu de l'arrêter.

Mesuré en scène réelle headless (3000 images, console lue) : enclume PRÊTE à
t=0.1 s (force 0.90/0.00, prise 1/1, stabilisation 1.50/1.00), chantier accompli à
t=13.3 s — exactement travail_restant 20.0 / rythme 1.5. Aucune alarme au
démarrage.

**Ne montre pas.** rien côté simulation. Côté écran,
tout reste à confirmer à l'œil — les couleurs (vert/rouge/gris), la lisibilité des
labels, et l'éclaircissement du colon sélectionné. La SÉLECTION (touches 1/2/3) et
le DÉPLACEMENT (clic gauche) suivent le même protocole que les autres bancs :
appuyer, cliquer, et regarder si la console réagit — si elle reste muette, c'est le
routage d'entrée qu'il faut ouvrir, pour tous les bancs à la fois.

## banc_affordances_connaissance — le médecin sait, l'apprenti lit, le novice s'empoisonne

`Scene/banc_affordances_connaissance.tscn`, `scripts/banc_affordances_connaissance.gd`, `data/banc_affordances_connaissance.json`. Test : `scripts/test_banc_affordances_connaissance.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_affordances_connaissance`.

**Montre.** trois colons et quatre objets. Deux fruits d'apparence
identique, un objet inconnu, un pupitre. Chaque colon forme ses croyances en
regardant, à SA cadence, et son étiquette affiche ce qu'il croit — valeur crue et
certitude —, sa curiosité, son temps libre et son matériau. L'étiquette de chaque
objet affiche ce qui est RÉELLEMENT vrai, puis ce que le colon SÉLECTIONNÉ en
croit, côte à côte. La couleur d'un fruit dit la CROYANCE de ce colon, jamais la
réalité : vert (comestible cru), rouge (toxique cru), gris (inconnu). Une ligne
relie chaque colon à ce que sa décision vise. Trace console à chaque observation
neuve, chaque découverte par l'usage, chaque empoisonnement, chaque
expérimentation, chaque transmission, l'écriture du livre, chaque lecture et
chaque refus par dogme.

Ce qui se joue tout seul, sans un clic (mesuré en scène réelle headless, 22 s,
console lue) :
- t=0.1 s — chacun regarde et croit les deux fruits comestibles. Le médecin et le
 novice, tous deux à portée d'usage du fruit amer, s'en servent et apprennent
 qu'il n'est pas toxique. L'apprenti, hors de portée, n'apprendra jamais rien par
 lui-même.
- t=5.0 s — le fruit amer devient toxique. Il PERD la clé `comestible`, il ne la
 met pas à false.
- t=5.2 s — le médecin s'en sert, MANGE ce qu'il croyait comestible et
 s'empoisonne, puis corrige : `comestible = non`, `toxique = oui`. Il écrit
 aussitôt son carnet (trois choses figées, fidélité 0.75). L'apprenti le lit et
 sait, à certitude 0.60, ce qu'il n'a jamais touché. Le novice, lui, refuse la
 correction sur `comestible` : DOGME.
- t=7.2 s — libéré du repas, le temps libre du médecin franchit son seuil : le
 gate s'ouvre, il EXPÉRIMENTE l'objet inconnu et découvre sa toxicité, qu'aucun
 regard ne capte.
- t=8.2, 12.2 s — le novice remange le fruit toxique et se réempoisonne, à chaque
 fois refusant d'apprendre.
- t=15.2 s — le matériau du médecin est épuisé, le gate se referme de lui-même.
 Au même instant, l'oubli a ramené la certitude du novice sous la résistance : il
 lit enfin `comestible = non` et cesse de manger.
- t=17.2 s — la réserve d'intégrité du carnet est épuisée : ILLISIBLE. Son contenu
 reste intact sur l'objet — le savoir n'est pas détruit, il devient inatteignable.

**Quatre contrôles.** clic GAUCHE (fruit sain/toxique, à rejouer à volonté), clic
DROIT (dégradation du livre normale/accélérée ×6), touche T (transmission de vive
voix depuis l'auteur), touche C (colon suivant — c'est lui dont la croyance colore
les fruits).

**Prouve.** - UNE CONNAISSANCE A UNE SOURCE, ET LA SOURCE SE VOIT. Trois colons, un seul monde,
 trois façons d'apprendre : l'usage (crédibilité 1.0), la parole (force du lien ×
 0.85), le livre (0.75). Les trois passent par le MÊME verbe, Croyance.corriger,
 et ce qui les sépare est un seul nombre. La certitude finale le dit sans qu'on
 ait à demander d'où vient ce qu'un colon sait.
- UN SAVOIR PEUT DEVENIR UN OBJET. Le carnet est un vrai objet du Monde, fabriqué
 en cours de partie, qui PORTE un registre de croyances figé par copie profonde.
 Il se dégrade comme n'importe quelle chose, et meurt.
- UN VERBE PEUT ÊTRE INTERDIT SANS UNE SEULE BRANCHE. `experimenter` n'existe que
 si trois conditions tiennent ensemble ; il suffit qu'une seule tombe pour que le
 poids vaille 0.0 et que le verbe cesse d'être choisissable. Le matériau qui
 s'épuise referme le gate sans qu'une ligne ne dise « il s'arrête ».

Deux résultats MESURÉS, dits plutôt que masqués :
- LE DOGME PORTE PAR PROPRIÉTÉ, JAMAIS PAR CHOSE. Le novice, dogmatique sur
 `comestible`, n'a aucune croyance sur `toxique` : le livre la lui donne sans
 résistance. Il croit donc en même temps que le fruit est comestible ET qu'il est
 toxique — et il continue de le manger, parce que c'est `comestible` qui porte le
 verbe. C'est la mécanique exacte de croyance.gd, jamais un raccourci du banc.
- LE DOGME CÈDE À L'OUBLI. La clé retirée n'est plus rafraîchie par observer, la
 certitude retombe sous resistance_par_certitude vers t=15 s, et la source
 suivante passe. Un dogme ne dure que tant qu'on le nourrit.

**Ne montre pas.** - PERSONNE NE SE DÉPLACE — même décision et même raison que banc_croyance : mettre
 tout le monde au contact les corrigerait tous par l'expérience directe, et il
 n'y aurait plus ni ignorance, ni transmission, ni livre.
- AUCUN COLON SOURD. Les deux receveurs ont un lien assez fort pour que le câblage
 appelle corriger : le refus montré ici est le DOGME, celui du MÉCANISME. Le refus
 par crédibilité (le CÂBLAGE renonce) est déjà démontré par banc_croyance.
- LE CLIC DROIT NE RETIRE PAS LE LIVRE. monde.gd n'a aucune fonction de retrait, et
 détruire le livre supprimerait la seule chose que la ligne 17 demande de montrer :
 sa fin de vie. L'état atteint est le même, six fois plus vite.
- AUCUNE DÉFORMATION, AUCUN ENGAGEMENT, AUCUN CHANTIER. deformation.gd, couplage.gd
 et extinction.gd ne sont pas appelés : rien ici ne dispute une cible ni ne
 consomme un travail.

**Ne montre pas.** rien côté simulation — la scène
réelle a été lancée en headless et la console lue de bout en bout. Côté écran, tout
reste à confirmer à l'œil : les trois couleurs de croyance, la lisibilité des
étiquettes doubles (réel/cru) et du carnet, et les quatre contrôles. En headless
aucun clic ni aucune touche n'existe — la bascule manuelle du fruit, la dégradation
accélérée, la transmission et la sélection ne sont prouvées que par le test.

## banc_affordances_choix — trois cibles, un colon posé, et trois raisons de changer d'avis

`Scene/banc_affordances_choix.tscn`, `scripts/banc_affordances_choix.gd`, `data/banc_affordances_choix.json`. Test : `scripts/test_banc_affordances_choix.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_affordances_choix`.

**Montre.** Un colon posé au centre, trois cibles autour : un REPAS à
500 unités, un TAS DE BOIS à 120, une FORGE à 400. Rien ne bouge dans cette scène
sauf ce que le colon PORTE et ce que la souris déplace.

LA DISTANCE. Au départ il ramasse le bois, et il le fait SANS aucune déformation :
sa saillance nue (3.000) bat les deux autres par sa seule position. Clic droit : le
même bois, 160 unités plus loin, tombe à 0.333 et n'existe plus pour lui — parce
que sa portée de profil est courte. C'est là, et nulle part ailleurs, que vit le
« poids de la distance ».

L'HABITUDE. Le bois éloigné, la forge l'emporte à 2.000 — mais sa valeur nue vaut
1.111 : c'est la déformation, et elle seule, qui la porte. Un colon dont le
pli_atelier vaut zéro ne pose aucune déformation et voit la forge inchangée. Pas de
cas particulier : la même arithmétique lue à zéro.

L'URGENCE. Clic gauche : il a faim. Son biais monte pendant trois secondes, et le
repas — la cible la PLUS lointaine et la MOINS saillante en soi — passe à 5.000,
devant un bois pourtant proche et pourtant engagé. La forge, elle, sort littéralement
de la liste : dominance.gd la retire, elle n'est pas « moins prioritaire ».

LA CADENCE. La barre blanche sous le colon descend ; tant qu'elle n'est pas vide,
rien ne se re-score. On peut l'affamer, lui rapprocher le bois, tout changer : il ne
s'en apercevra qu'à l'échéance. Ce n'est pas une optimisation, c'est un changement
de comportement — et le prix est dit : entre deux re-scorings, il est AVEUGLE.

**Prouve.** LES TROIS POIDS D'UN CHOIX
NE VIVENT PAS DANS UNE TABLE DE POIDS. L'urgence et l'habitude sont deux entrées de
data/deformations.json (la seule voie qui fasse gagner une cible par un état
interne, parce qu'elle est indexée par percevant) ; la distance est une portée de
profil, et rien d'autre — proximite.gd atténue linéairement, sans exposant ni
coefficient, peser la distance plus fort c'est raccourcir la portée. Et rien ne
divise une saillance : le « ÷ coût » du prompt d'origine n'existe nulle part dans ce
dépôt.

Deuxième chose : QUATRE MÉCANISMES TIENNENT LA DÉCISION, pas un. Le fait de ne pas
re-scorer ; gain_inertie (préférence de personnalité) ; couplage.gd (fait physique,
posé par présence, arraché par absence) ; et le poids d'avancement de proximite.gd,
présent ici et EXACTEMENT neutre (les cibles portent travail_restant ==
travail_initial, dont couplage.gd a besoin) — vérifié plutôt que supposé.
L'engagement RALENTIT, il ne verrouille pas : au-delà de gain_inertie + son poids,
une alternative gagne quand même.

Troisième : actions_gardees est ABANDONNÉE, et c'est une décision de doctrine, pas
un oubli. C'est une file de plan, elle tombe sous deux des quatre griefs anti-BDI de
design.md. Ce banc ne porte aucune file : à chaque re-scoring les quatre couches
repartent de zéro sur le monde tel qu'il est. sur_changement n'existe pas non plus.

Décisions du câblage, dites plutôt que masquées :
- LE CATALOGUE D'ENGAGEMENT EST LOCAL au banc, jamais ajouté à
 data/engagements.json : couplage.gd reçoit son catalogue en paramètre, et le poids
 y est calibré sur les saillances de CE banc (0.5) là où colon_chantier porte 5.0 —
 l'entrée partagée aurait rendu l'engagement indélogeable et l'urgence
 inobservable.
- L'ENGAGEMENT NE SE SATISFAIT JAMAIS ICI : rien n'avance travail_restant
 (extinction.gd n'est pas câblé). Il ne se relâche que par l'absence, ou par le
 retrait explicite du câblage quand la décision change de cible — geste qu'agir.gd
 réclame nommément dans son en-tête.
- LE COLON NE SE DÉPLACE PAS, même découpage que banc_marche_competence et
 banc_temps_anticipation : un colon qui marche change lui-même les distances, donc
 les saillances, et « la distance avantage le bois proche » serait vrai une seconde
 puis faux.
- LE SCORE AFFICHÉ EST UNE RECOMPOSITION (agir.gd ne rend pas le nombre qu'il a
 comparé), verrouillée : le test exige que son argmax soit exactement la cible
 retenue, dans les trois états.

Écart à la consigne, assumé : le prompt annonçait trois déformations (urgence,
distance, habitude) puis sa propre correction de voie établissait que la distance
n'en est pas une. Deux entrées ont donc été écrites, pas trois.

Vérifié (headless — test rejouant les fichiers réels, plus la scène réelle lancée et
sa console lue) : les quatre distances et les quatre saillances nues du disque ; le
bois proche gagne sans déformation et perd une fois éloigné ; l'habitude fait gagner
la forge et vaut exactement nue × (1 + biais) ; un colon sans pli n'a aucun registre
d'habitude ; l'urgence fait gagner le repas puis le rend au bois une fois rassasié ;
aucun re-scoring sous l'échéance, même affamé, alors que le biais monte pendant ce
temps ; le re-scoring d'après bascule ; les deux plafonds tiennent et la pose cesse
au-dessus ; l'engagement se pose par présence, rend « garde » puis « arraché » hors
de portée, et est retiré quand la décision change de cible ; le poids d'avancement
vaut exactement 1.000 ; l'argmax du score recomposé est la cible d'agir.gd dans les
trois états, et vaut exactement la saillance au tout premier re-scoring ;
dominance.gd écrase la forge sous l'urgence et rien en état de départ ; un poids de
verbe absurde ne fait toujours pas gagner sa cible.

Deux défauts trouvés EN LANÇANT LA SCÈNE, invisibles au test tel qu'il était : le
score affiché au tout premier re-scoring valait 3.250 là où agir.gd avait comparé
3.000 (inertie appliquée rétroactivement à une tâche qui venait de naître) ; et ce
que dominance.gd avait laissé passer n'était rendu que sur les ticks de re-scoring,
donc le carré grisé d'une cible écrasée aurait battu au rythme de la cadence. Les
deux sont fermés, et le premier a désormais son cas dédié.

**Ne montre pas.** PERSONNE NE SE DÉPLACE ET RIEN NE SE
CONSOMME. Le colon choisit, il ne va pas, il ne mange pas, il ne ramasse pas. Le
verbe résolu est affiché — c'est lui qui prouve la décision. Brancher le trajet
demanderait de renoncer à la calibration fixe qui rend les trois bascules lisibles ;
c'est un chantier suivant, pas celui-ci.

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

---

## banc_social_information — il l'a vu, les autres l'ont entendu, et le novice apprend en regardant

Lancer : `& "<chemin trouvé, voir CLAUDE.md>" --path . --scene Scene/banc_social_information.tscn`

**Montre.** ce qui CIRCULE d'un colon à un autre quand ils se
voient. Cinq colons posés, personne ne bouge. En haut, un VOLEUR (rouge) et le
TÉMOIN (bleu) qui le voit ; à droite un LOINTAIN (gris), hors du cercle de
propagation. En bas un MAÎTRE forgeron (or) et un NOVICE (vert).

1. LA RÉPUTATION SE PROPAGE. Le témoin perçoit le vol, donc l'observe, et sa
 certitude monte jusqu'à 1.0. À la cadence, il verse cette croyance à tout colon à
 portée : le maître la reçoit à 0.432, le novice à 0.336 — jamais 0.800. La parole
 AFFAIBLIT ce qu'elle porte, et chacun reçoit un nombre différent parce que son
 lien vers le témoin est différent. Personne n'a écrit cette règle : c'est
 croyance.gd qui écrase la certitude à `gain_par_echec × crédibilité`.
2. LA PORTÉE EST RÉELLE. Le lointain est hors du cercle : il ne reçoit rien, et le
 câblage ne lui parle même pas. Clic droit, il se rapproche, il entre dans le
 cercle, il reçoit.
3. LA RÉPUTATION TOMBE PAR MARCHES. Clic gauche : le vol cesse. La clé disparaît du
 voleur, plus personne ne la ré-observe, et à CHAQUE SAISON (20 s) la certitude
 perd 0.20 D'UN COUP — jusqu'à ce que croyance.gd retire l'entrée. Ce n'est pas
 une pente douce : c'est un décrochement par saison, et c'est tout le sujet.
4. LE NOVICE IMITE. Il perçoit le maître à portée d'imitation, l'écart de compétence
 dépasse le seuil, sa barre orange monte de 0.0 à ~0.39 en deux secondes et demie
 — puis s'arrête net à `fidelite × la compétence du maître`. Celle du maître ne
 bouge pas : il exerce son métier pendant ce temps.

**Ce qui a été ajouté.** Ce n'était pas évitable — `observer()` ne recopie que ce qui figure dans cette liste, donc sans elle le témoin ne verrait rien et il n'y aurait rien à propager.

Deux écarts à la consigne d'origine, tranchés par l'audit préalable : le sens du lien
de crédibilité est celui du RECEVEUR vers l'émetteur (« à quel point je te crois »),
comme banc_croyance ; et la fidélité de propagation vaut 0.6 et non 0.4, parce qu'à
0.4 aucun destinataire ne franchit `seuil_bornes_transmission` et la scène ne
montrerait que des sourds.

Deux défauts trouvés EN LANÇANT LA SCÈNE, invisibles au test : le SUJET de la
réputation était compté comme destinataire « sourd » à chaque passage, alors que le
seul contenu qu'on aurait pu lui dire le concerne lui-même ; et une re-propagation
identique était étiquetée « dogme » alors qu'elle réécrit simplement la même
certitude. Les deux sont fermés. Conséquence dite : un refus par dogme serait
silencieux ici — sans portée, personne dans cette scène n'observant le sujet sauf le
témoin, qui n'écoute personne. C'est banc_croyance qui montre le dogme.

**Ne montre pas.** PERSONNE NE SE DÉPLACE ET PERSONNE NE
DÉCIDE. Ce banc monte la couche 1 et rien au-delà — ni proximité, ni dominance, ni
agir, ni même `Croyance.filtrer`. On voit ce que chacun SAIT, jamais ce qu'il en
fait. Faire agir un colon sur une réputation (refuser de commercer avec le voleur,
choisir le maître comme cible) demande la chaîne complète de décision, et c'est un
chantier suivant. La réputation ne se DÉFORME pas non plus en circulant : la fidélité
dégrade la certitude, jamais la valeur — un fait qui grossirait de bouche en bouche
serait un mécanisme neuf.

**Non vérifié à l'œil** (pas d'écran, pas de souris simulée) : rendu, couleurs, lisibilité des labels et contrôles restent à confirmer par Yael.

## banc_social_rupture — il perd un proche, il trahit, il s'en va

Lancer : `& "<chemin trouvé, voir CLAUDE.md>" --path . --scene Scene/banc_social_rupture.tscn`

Chantier « rupture + migration », tableau Social et relations, lignes 8 (le
deuil), 12 (la trahison) et 13 (la migration). Trois lignes, un seul banc, parce
qu'elles interagissent : le deuil fait monter le grief, le grief franchit un
palier puis un second, le second ouvre la trahison, le détournement vide la
réserve que le deuil ralentissait déjà, et le colon dont la loyauté est basse
s'en va chez le voisin.

**Montre.** Deux colonies, cinq colons (3 au nord, 2 au sud), un
chef au nord, une réserve commune par colonie, un compagnon au milieu du camp
nord. Le nord est injuste : le chef se soumet au premier palier ; le cupide, qui
subit en plus une agression permanente, conteste d'abord puis TRAHIT une fois le
second palier franchi — la réserve commune du nord se vide dans sa poche pendant
que celle du sud ne perd rien. Un clic tue le compagnon : le colon qui l'aimait
entre en deuil, son rythme tombe à 0.7 et remonte continûment vers 1.0 en
dix-huit secondes, et son grief monte pour cette raison-là aussi. Pendant ce
temps ce même colon marche vers le sud ; deux touches montent ou descendent
l'attractivité du sud et il repart ou s'arrête EN COURS DE ROUTE. Son voisin
cupide lit exactement la même attractivité et ne bouge pas : sa loyauté est
haute.

**Contrôles.** clic GAUCHE tue le compagnon (une seule fois — une mort ne se défait
pas) ; clic DROIT bascule l'injustice ; FLÈCHES HAUT/BAS règlent l'attractivité
de la colonie rivale. Trois bascules ne tiennent pas sur deux boutons de souris,
précédent banc_marche_competence (touches 1/2/3).

CE QUI A ÉTÉ AJOUTÉ, ET POURQUOI. Aucun mécanisme neuf, aucun `.gd` du cœur
touché : neuf mécanismes déjà fermés composés tels quels. Trois états partagés
(`en_deuil`, `tentation_trahison`, `traitre`) et une entrée de seuil
(`tentation_trahison`) — le détail vit dans `CARTE.md` `banc_social_rupture` et dans les
`_note` des deux catalogues, jamais recopié ici.

- LE QUATRIÈME PALIER. banc_grief a UN seuil qui ouvre TROIS sorties d'un coup ;
 ici un SECOND palier sur le même grief ouvre une QUATRIÈME sortie. La
 bifurcation ne connaît ni seuil ni palier — elle prend le maximum sur
 l'ensemble qu'on lui donne, donc « la trahison demande plus de grief que la
 révolte » ne peut s'écrire que comme un ensemble qui grandit. Conséquence : la
 bifurcation est REJOUÉE quand cet ensemble change, sinon la quatrième sortie
 serait inatteignable. Les trois états de sortie de banc_grief sont réutilisés
 tels quels ; seul `traitre` est neuf.
- LA MORT EST UNE ABSENCE, jamais un événement : le câblage retire le compagnon
 du Monde, et un lien personnel qui vise une chose absente du Monde pose le
 deuil. Tuer n'importe quoi vers quoi un colon porte un lien assez fort produit
 le même deuil. C'est aussi ce qui donne au Monde un rôle réel dans un banc qui
 ne monte aucune couche de décision.
- LE DEUIL S'ESTOMPE. Son intensité décroît, et la pénalité de rythme la suit —
 le câblage compose etats_ponderes avant etat_effectif, sans quoi l'effet serait
 plein jusqu'à la dernière seconde puis nul d'un coup. La cause de grief suit la
 même intensité : son intégrale (45) reste sous le palier de trahison (60), donc
 un deuil seul ne fait jamais un traître.
- L'ATTRACTIVITÉ EST UN RÉSUMÉ LU. Aucune entité « colonie » n'existe et aucune
 n'est perçue : un nombre plat écrit sur chaque colon à chaque tick. C'est déjà
 la forme qu'aurait une propriété posée par une couche serveur.

**Ne montre pas.** Les colons ne décident RIEN : ni
perception, ni saillance, ni verbe résolu — le seul déplacement est la migration,
qui n'est pas un choix de cible mais la conséquence d'un gate. La faim et
l'agression sont des données de scène constantes, pas des réserves câblées : les
brancher sur depense.gd rendrait les causes vivantes, c'est un chantier suivant.
Et le départ vers le bord n'est pas refait — banc_grief le montre déjà, ici la
sortie « depart » ne fait qu'arrêter la production.

NON VÉRIFIÉ (pas d'écran, pas de souris simulée) : les couleurs, la lisibilité
des cinq labels, les barres de grief et leurs deux traits, le liseré d'état et
les zones de colonie restent à confirmer à l'œil. En headless aucun clic n'existe
— les trois bascules ne sont prouvées que par le test.

---

## banc_social_foule — quatre en colère suffisent, et le chef mort disloque tout

Lancer : `& "<chemin trouvé, voir CLAUDE.md>" --path . --scene Scene/banc_social_foule.tscn`

Chantier « foule + environnement », tableau Social et relations, lignes 5 (la
bascule de foule), 7 (la dislocation), 9 (la densité) et 10 (le bruit). Quatre
lignes, un seul banc : ce sont les quatre manières dont un groupe et son lieu se
font mal l'un à l'autre, et elles partagent les mêmes vingt colons, les mêmes
seize cases et les mêmes comptages.

**Montre.** Vingt colons sur une grille 4×4. Douze sont
entassés dans le coin haut-gauche, trois par case — au-dessus du confort de deux :
ces quatre cases jaunissent puis virent au rouge toutes seules, sans qu'on
touche à rien. Huit sont au large dans le coin bas-droit, deux par case, exactement
au confort : elles restent vertes indéfiniment. La colonne de droite est bruyante :
trois colons y perdent leur sommeil au lieu de le refaire, et un quatrième, sous
EXACTEMENT le même bruit, n'y perd rien — c'est son seuil de gêne, propre à lui,
qui tranche. Une barre de cohésion tient en haut à 0.78 : quatre axes hauts.
Puis :
- METTRE DES COLONS EN COLÈRE. À trois sur vingt, la fraction fait exactement
 0.15 et RIEN ne se passe — le seuil se compare strictement au-dessus. Au
 quatrième (0.20), la colère devient majoritaire, une charge monte pendant trois
 secondes, et alors seulement toute la foule bascule en ÉMEUTE. Rendre un seul
 colon à son calme fait redescendre la charge et l'émeute se défait.
- TUER LE CHEF. La cohésion s'effondre en une seconde et le groupe se DISLOQUE.
 Le rendre fait redescendre la charge de choc à zéro et la cohésion remonte —
 rien ne la remet à la main.
- ENTASSER. Les huit du large viennent s'ajouter aux cases denses, qui passent à
 six : le stress y monte quatre fois plus vite, parce que le poids de la cause
 EST l'excès au-dessus du confort.
- CHANGER LE BRUIT D'UNE CASE, qui tourne entre silence, gêne et vacarme.

**Contrôles.** clic GAUCHE sur un colon (colère), clic DROIT sur une case (bruit),
et deux boutons — TUER / RENDRE LE CHEF, ENTASSER / DISPERSER.

CE QUI A ÉTÉ AJOUTÉ, ET POURQUOI. Aucun mécanisme neuf, aucun `.gd` du cœur
touché : le banc compose `comptage.gd`, `somme.gd`, `charge.gd`, `seuil_etat.gd`,
`depense.gd`, `lien_personnel.gd` (lecture seule) et `portee.gd`. En données :
cinq états, cinq entrées de seuil, cinq règles de comptage, tous partagés, plus
`data/banc_social_foule.json`. Détail complet et adresses : CARTE.md
`banc_social_foule`.

TROIS CHOSES QUE CE BANC A CORRIGÉES OU FERMÉES, et qu'il ne faut pas rouvrir :
- LA FENÊTRE TEMPORELLE EST `charge.gd`, PAS `etat_duree.gd`. Celui-ci fait
 DÉCROÎTRE une intensité et retire l'état à zéro ; il ne monte jamais, il ne
 peut donc pas dire « la fraction est restée au-dessus pendant N secondes ».
- UN SEUL CANAL DE `charge.gd` PAR OBJET dès qu'il y a plusieurs causes : les
 causes ne portent aucun type, tous les canaux d'une chose reçoivent la même
 liste. D'où trois familles d'objets disjointes ici (les cases, les membres, le
 chef seul).
- `charge.gd` ET `seuil_etat.gd` NE SE BRANCHENT PAS DIRECTEMENT : le premier
 efface ses clés à la descente, le second sort sur propriété absente — l'état
 serait irréversible en silence. Un miroir plat 0.0/1.0 s'intercale.
Les deux derniers points valent pour tout banc futur, pas seulement celui-ci.

`bifurcation.gd` ÉCARTÉ (décision de Yael) : l'audit le proposait pour donner une
FORME à la dislocation — scission, désertion, révolte — ce qui demande de nommer
ces sorties, donc du contenu de jeu. La dislocation reste un seul nom d'état.

**Ne montre pas.** Aucun colon ne perçoit ni ne décide :
`perception.gd`, `proximite.gd`, `dominance.gd` et `agir.gd` ne sont pas montés.
Les colons ne se déplacent que par le bouton ENTASSER — une foule qui SE
disperse d'elle-même sous le stress est un chantier suivant, et c'est ce qui
manque pour que la ligne 9 boucle. Les cinq états sont des marqueurs purs : rien
dans ce banc ne compose `EtatEffectif.valeur`, une émeute ne change donc aucune
vitesse. Le bruit est une propriété de case, pas une émission propagée par
`champ_occulte.gd` — le brancher un jour ne changerait rien en aval du miroir
`bruit_local`.

VERROUILLÉ PAR `scripts/test_banc_social_foule.gd` (vingt-quatre cas) : la
fraction sous la critique qui ne bascule jamais, même après trois fois la
fenêtre ; la fenêtre entière exigée avant l'émeute ; l'émeute qui se défait
quand la colère retombe ; les quatre axes et la somme pondérée recalculée à neuf
d'un tick à l'autre ; le choc qui fait chuter la cohésion puis se résorbe quand
on rend le chef ; la dislocation posée sous le seuil ; le stress proportionnel à
l'excès et nul au confort exact ; la surdensité qui se défait quand on disperse ;
le même bruit qui gêne l'un et pas l'autre selon leur seuil ; `surcout_action`
réécrit en entier sans résidu ; les trois familles de porteurs disjointes ; et,
sur le chemin réel, l'accord entre les noms que le banc écrit et ceux que les
entrées partagées comparent.

NON VÉRIFIÉ (pas d'écran, pas de souris simulée) : les couleurs des cases, la
lisibilité des seize labels, la barre de cohésion, les marqueurs de bruit et les
deux boutons restent à confirmer à l'œil. En headless aucun clic n'existe — les
quatre bascules ne sont prouvées que par le test.

## banc_social_paire — il se bat à ses côtés bien avant de lui obéir, et il refuse de tuer son ami

`Scene/banc_social_paire.tscn`, `scripts/banc_social_paire.gd`, `data/banc_social_paire.json`. Test : `scripts/test_banc_social_paire.gd`. Détail du câblage et des catalogues touchés : `CARTE.md` `banc_social_paire`.

**Montre.** Quatre colons : un chef, un soldat loyal, un ami proche, un
ennemi. Au départ personne ne se bat et personne n'obéit — la confiance est à zéro.
Elle monte par TEMPS PARTAGÉ, et les trois qui se fréquentent franchissent le
premier palier : ils acceptent de se battre aux côtés du chef. Le soldat seul
franchit le second et accepte ses ordres ; l'ami plafonne entre les deux et
n'obéira jamais. L'ennemi, que personne ne fréquente, ne franchit rien — et comme
le chef lui rend service sans rien recevoir, sa dette s'alourdit jusqu'à le rendre
RANCUNIER.

Clic gauche (trois états, cyclique) : le chef ordonne de tuer l'ami. Le soldat CÈDE
— il aime son chef, et son chef est fort — mais il refuse quand même : son lien
vers l'ami dépasse le seuil d'attache, l'entrée de l'ordre est RETIRÉE de resultats
avant dominance.gd, et il retourne à son ouvrage. Second clic : l'ordre est FORCÉ,
l'entrée survit au gate du lien, il tue — et son grief de transgression monte
jusqu'à le marquer TRANSGRESSEUR. Clic droit : les interactions passent de SERVICE
à AGRESSION ; l'ennemi frappe le soldat et l'ami, les lignes entre eux virent au
rouge, le service cesse et la rancune se retire d'elle-même.

**Prouve.** LE PREMIER REGISTRE PAR
PAIRE QUI NE SOIT PAS UN LIEN PERSONNEL. lien_personnel.gd est le seul registre par
paire du dépôt, et il est POSITIF SEULEMENT — avancer écrit max(0.0, force −
taux × delta), une haine n'y survit pas un tick, et le rendre signé toucherait CINQ
fichiers du cœur. Trois registres de plus vivent donc chez epigenetique.gd, sous
des noms COMPOSÉS ("confiance:chef") contre un catalogue dérivé PAR PAIRE d'une
seule entrée partagée. Le mécanisme ne voit que des noms opaques ; il ignore
totalement qu'ils encodent une paire.

Deuxième chose : LA HAINE EST UN SECOND REGISTRE POSITIF, PAS UN SIGNE. score_net =
lien_positif − lien_negatif est une LECTURE refaite à neuf, jamais une valeur
stockée. Les quatre lecteurs de lien_personnel.gd continuent de ne voir que le
positif, sans une ligne changée. Même geste pour la dette : un seul registre
positif posé sur celui qui REND, et dette(A,B) = service_rendu(A,B) −
service_rendu(B,A), lue sur DEUX entités.

Troisième : DEUX GATES INDÉPENDANTS SUR LE MÊME ORDRE, et ils ne se recouvrent pas.
« confiant_obeir » dit ce que le colon a ACCUMULÉ avec son chef ; la cession dit ce
que le chef PÈSE ici et maintenant. Un colon peut avoir assez confiance pour obéir
en principe et résister quand même parce que le conflit lui coûte moins cher que la
soumission.

Décisions du câblage, dites plutôt que masquées :
- LE PLAFOND DE CONFIANCE EST PAR COLON, et c'est LUI qui fait l'escalier — pas un
 seuil différent. Les trois seuils sont universels et partagés ; l'ami plafonne à
 0.50, entre 0.20 et 0.70. C'est « les archétypes n'existent pas » rendu littéral :
 un POIDS individuel, comme biais_grief ou poids_bonheur.
- score_cession LIT LE SCORE NET, pas LienPersonnel.force nue — écart assumé à la
 lettre de la consigne, et nécessaire : sans lui, « un chef HAÏ se fait résister »
 n'est observable nulle part.
- LA TRANSGRESSION PASSE PAR charge.gd, là où l'audit ligne 11 renvoyait vers un
 terme de propriété plate : elle n'est pas ponctuelle, elle DURE tant que l'ordre
 forcé est exécuté — domaine exact de charge.gd, qui rend le marqueur réversible
 sans écrire les deux sens à la main.
- LA CIBLE DE L'ORDRE EST LE COLON « ami » LUI-MÊME, jamais un cinquième objet : le
 nombre affiché sur la paire (soldat → ami) EST celui qui déclenche le refus.
- LES COLONS NE SE DÉPLACENT PAS, même découpage que banc_bonheur et
 banc_affordances_choix : un colon qui marche change lui-même qui est à portée,
 donc quelles paires accumulent.

Écart à l'audit, assumé et signalé : écrit
« la confiance est-elle une marque épigénétique ? Non, et il ne faut pas prendre
cette route », au motif qu'il faudrait une entrée de data/epigenetique.json par
paire de colons. Le motif ne tient pas : epigenetique.gd ne charge jamais son
catalogue, il le REÇOIT en paramètre — la dérivation par paire est du câblage, la
loi vit une fois en donnée. Et la route de l'audit (tout mettre dans
liens_personnels) était fermée pour une autre raison qu'il ne voit pas : les quatre
lecteurs de la famille itèrent ses clés et les passent à monde.par_id(), qui fait
push_error sur un id absent.

UN DÉFAUT TROUVÉ EN LANÇANT LE TEST, invisible au raisonnement : epigenetique.gd
ajoute sans borne haute, donc un modulateur laissé libre monte AU-DELÀ du plafond
et le clamp à la lecture masque la décroissance. Mesuré : 1.08 pour un plafond de
1.00 après 6 s, et « hors de portée, la confiance descend » lisait 1.000 → 1.000 —
une hystérésis PAR ACCIDENT, proportionnelle au temps passé ensemble. Fermé en ne
posant plus au-delà du plafond (patron banc_marche_competence).

**Ne montre pas.** PERSONNE NE MEURT. Le colon « tué »
reste dans la scène — le verbe est résolu et affiché, c'est lui qui prouve la
décision, mais rien ne retire la cible du monde. Brancher la mort demanderait de
reconstruire le Monde du néant (monde.gd n'a aucune fonction de retrait) et
rendrait la scène non rejouable sans relance ; c'est un chantier suivant.

NON VÉRIFIÉ (pas d'écran, pas de souris simulée) : les couleurs des quatre carrés,
les six lignes colorées par score net (vert positif, rouge négatif, gris à
exactement zéro) et la lisibilité des six labels de paire posés au milieu des
segments restent à confirmer à l'œil. En headless aucun clic n'existe — l'ordre à
trois états et la bascule service/agression ne sont prouvés que par le test.

---

## banc_temps_vieillissement — il décide aujourd'hui, il a faim dans deux ans

**Lancer** : `& "<chemin Godot>" --path . --scene Scene/banc_temps_vieillissement.tscn`

**Ce qu'on doit voir.** Huit colons posés, deux rangées. En haut quatre âges
qui ne bougeront plus de place : 5, 25, 40, 60 ans. En bas deux couples. Un
seul contrôle, le clic gauche, qui fait passer le temps de ×1 à ×4 puis ×16.

1. **Le sommet franchi sous les yeux.** La barre orange du colon de 25 ans
   monte encore trois secondes, atteint son maximum à 28 ans d'âge, puis
   commence à redescendre — et la console annonce `veteran` à cet instant
   précis. Celui de 40 ans descend déjà. Celui de 60 ans a la barre orange la
   plus courte et la barre bleue la plus longue : le plus faible est le plus
   savant. Aucun d'eux ne verra jamais sa barre bleue redescendre.
2. **L'attente, puis le coup.** Deux des quatre témoins ont décidé au premier
   tick. Pendant douze secondes rien ne les distingue : même barre verte, même
   coût. Au 730ᵉ jour la barre verte passe au rouge et se vide six fois plus
   vite, pendant que les deux autres continuent leur lente descente. Accélérer
   le temps raccourcit l'attente sans rien changer au reste.
3. **Deux enfants, deux héritages.** Vers la septième seconde chaque couple
   produit un petit carré jaune. Les deux naissent identiques en gènes — un
   allèle de chaque parent, donc au milieu exact — et reçoivent chacun la
   moitié du patrimoine de leur parent, qui perd d'autant. Ce qui les sépare
   tient à une ligne de donnée : l'enfant de la lignée A porte le lien hérité
   de son parent, celui de la lignée B ne porte rien. **C'est la question
   posée par la scène, pas une réponse qu'elle donne.**

**Ce qui reste à trancher.** Un enfant doit-il naître avec les attachements de
sa mère ? Les deux voies tournent côte à côte exprès. Contre : le registre de
lien ne vaut que parce qu'il naît d'un événement vécu, et un nouveau-né n'a
rien vécu — hériter d'un vécu qu'on n'a pas eu recrée le registre consulté que
le design écarte. Pour : sans transmission, aucune lignée n'a de continuité et
chaque génération repart de zéro socialement. À observer, puis décider.

**Ce qu'il ne montre pas.** Personne ne meurt — le colon de 60 ans finit à 100
ans avec une force au plancher et continue d'exister. Aucun colon ne se
déplace : la scène n'exerce ni décision ni mouvement, seulement des grandeurs
qui évoluent. Les enfants sont stériles, sans quoi la troisième génération
rendrait la scène illisible en une minute.

**NON VÉRIFIÉ (pas d'écran)** : la teinte du carré qui vire du vert au gris
avec l'âge, le liseré de couleur qui permet de retrouver un colon quand sa
teinte a changé, et la lisibilité des trois barres empilées au-dessus de
chaque bloc restent à confirmer à l'œil. En headless le clic n'existe pas —
l'accélération du temps n'est prouvée que par le test.

## banc_temps_saisons — l'année où le froid n'est pas venu, et la bibliothèque qui brûle

**Lancer** : `& "<chemin Godot>" --path . --scene Scene/banc_temps_saisons.tscn`

**Ce qu'on doit voir.** Trois champs à gauche, cinq colons et trois
rayonnages à droite, un brasier éteint entre les deux. En haut l'heure, la
saison, le numéro de cycle et une phrase qui dit dans quel régime on est.
Quatre commandes : clic gauche et clic droit forcent une année anormale, `F`
allume le brasier, `M` coupe la sérénité d'un colon.

1. **Les barres vertes montent doucement et tombent d'un cran.** Pendant les
   deux saisons de pousse elles grimpent image par image ; au moment précis où
   la saison froide s'ouvre elles perdent une tranche d'un seul coup, puis ne
   bougent plus jusqu'au passage suivant. La console imprime la tranche
   retirée. Une saison neutre sépare les deux régimes : là, rien ne bouge du
   tout, et c'est voulu.
2. **L'année sans froid.** Au deuxième cycle, l'horloge nomme quand même la
   saison froide — le libellé du haut, lui, annonce que le froid n'est pas
   venu, les champs restent verts et aucune tranche n'est retirée. Le clic
   gauche provoque la même chose sans attendre. Le clic droit fait l'inverse :
   les champs virent au bleu, se vident en continu, et deux clés de plus
   apparaissent sur eux.
3. **Un colon entraîne ses voisins.** `M` fait passer un carré au rouge et
   trace un cercle autour de lui. Les carrés qui tombent dans ce cercle
   passent à l'orange en une seconde ; celui du fond, à l'écart, ne change
   pas. Rendre la sérénité fait disparaître le cercle, puis l'orange.
4. **Les chroniques.** À chaque passage de saison un rayonnage apparaît, avec
   son titre et une barre d'intégrité qui descend lentement. Les colons à
   portée les lisent, leur compte de croyances monte, leur moral avec.
   Appuyer sur `F` : le feu prend au premier rayonnage, saute au deuxième,
   puis au troisième. Le gardien est collé au premier et l'éteint ; les deux
   autres virent au gris cendre. La fierté de tout le monde tombe d'autant —
   mais les croyances déjà lues restent affichées sur les colons.

**Prouve.** DEUX ÉCHELLES DE TEMPS SUR UNE SEULE GRANDEUR, sans qu'aucune des
deux ne sache que l'autre existe. Et surtout : UNE ANOMALIE DE CYCLE EST UNE
DONNÉE QUI MANQUE, jamais un cas particulier — rien dans la scène ne teste si
l'année est normale, le miroir est écrit ou il ne l'est pas.

Deuxième chose : L'HISTOIRE PROTÈGE DU FROID. Les poids sont calibrés pour
qu'une saison dure vidant les réserves laisse la colonie calme tant que les
rayonnages tiennent, et la fasse basculer une fois qu'ils ont brûlé. Ce n'est
pas une règle écrite quelque part : c'est la somme pondérée qui le produit.

**Ne montre pas.** Personne ne décide ni ne se déplace — la scène n'exerce
aucune couche de saillance. SEUL L'AUTEUR REGARDE LE MONDE ; les quatre autres
ne savent que ce qu'ils lisent, sans quoi ils sauraient déjà tout et la
transmission serait invisible. Le paniqué se charge lui-même, son propre
cercle le contenant — sans conséquence, il est déjà sous le seuil.

**NON VÉRIFIÉ (pas d'écran)** : couleurs, lisibilité des labels superposés,
et le cercle de contagion restent à confirmer à l'œil. En headless aucun clic
n'existe — les quatre commandes ne sont prouvées que par le test.
