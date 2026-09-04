# ORION — CARTE DU MOTEUR

But de ce fichier : donner à un agent (ou à un repreneur humain) une vue
d'ensemble immédiate, sans lire tout le code. Il dit CE QUI EXISTE, ce que
chaque script fait, ce qu'il reçoit et rend, et COMMENT les scripts sont
reliés. Il ne remplace ni `CLAUDE.md` (les règles de travail et l'ADN) ni
`docs/design.md` (le design et le pourquoi) ni `docs/prototypes.md` (l'état
des bancs et la dette). Il les indexe.

Frontière : toute dette de code précise (fichier ET fonction ou constante
concernée — jamais un numéro de ligne, qui périme silencieusement à
chaque édition du fichier cité et ne se retrouve pas par grep) vit ici
(§6) ou dans `docs/prototypes.md` — jamais dans `docs/design.md`, qui
n'est pas relu à chaque session et périme silencieusement sur ce genre de
détail.

Ordre de lecture conseillé pour une nouvelle session : ce fichier d'abord
(quoi + où), puis `CLAUDE.md` (comment travailler), puis la section de
`docs/design.md` qui concerne la tâche du jour.

> Rappel de discipline (voir CLAUDE.md) : le moteur ne connaît QUE des
> verbes. Aucun nom de chose (`"feu"`, `"arbre"`), aucun seuil, aucun trait
> n'est écrit en dur dans les scripts du cœur. Tout le contenu vit dans
> `data/`. Ce fichier signale les rares endroits où cette règle n'est pas
> encore tenue — ce sont des dettes, pas des exemples à suivre.

---

## 1. La colonne vertébrale : quatre couches

Tout le jeu passe par le même pipeline, identique pour tout colon. Ce qui
distingue un colon d'un autre n'est jamais du code : ce sont ses données
(`attaches`, `forme`, `poids_verbes`).

```
   monde (objets { id, position, proprietes })
        │
        ▼
  ┌───────────────┐  Couche 1 — PERCEPTION (aveugle, exhaustive dans le rayon)
  │ perception.gd │  → Array de { chose, type, position, distance }
  └───────┬───────┘
          │
     ┌────┴──────────────┐          Couche 2 — SAILLANCE (deux sources,
     ▼                   ▼           additives, jamais confondues)
┌────────────┐    ┌──────────────┐
│ attaches.gd│    │ proximite.gd │  attaches : menace sur ce à quoi le colon
└─────┬──────┘    └──────┬───────┘  tient (liaison en ESPACE entre choses)
      │                  │          proximite : saillance intrinsèque d'une
      └───── att + prox ─┘          chose (distance AU COLON) — plancher commun
                 │
          (optionnel — voir jugement.gd)
                 ▼
        ┌────────────────┐  Couche 2bis — JUGEMENT (troisième source de
        │  jugement.gd   │  saillance : lit att+prox déjà calculée comme
        └───────┬────────┘  PRESSION, aucune distance) → s'ajoute à att+prox
                 │
                 ▼
        ┌────────────────┐  Couche 3 — DOMINANCE (n'ordonne pas : ÉCRASE)
        │  dominance.gd  │  → ne garde que ce qui est à moins d'un écart
        └───────┬────────┘    du sommet ; le reste devient INVISIBLE
                │
                ▼
        ┌────────────────┐  Couche 4 — AGIR (choisit une action + inertie)
        │    agir.gd     │  → { ...saillance choisie, action: clé }
        └────────┬───────┘
                 │  (câblage post-décision, hors des quatre couches)
                 ▼
      ciblage.gd traduit la décision en la CHOSE visée ; fuite.gd traduit
      un verbe orienté "fuite" (data/orientations.json) en DIRECTION de
      répulsion, jamais une cible-position.
```

JUGEMENT (`jugement.gd`, voir docs/design.md « Jugement : troisième source
de saillance ») n'est PAS appelé par tout `decider()` : optionnel par
câblage, comme une source de saillance de plus à côté d'attache/proximité.
`banc_p1.gd:decider` reste aux quatre étapes (jamais de jugement) ;
`banc_feu.gd:decider` est le seul câblage qui l'inclut aujourd'hui — voir
`banc_feu`.

`lien_personnel_attraction.gd` (voir §2) est, de même, une source de
saillance optionnelle de plus, ajoutée à `att + prox` (`resultats`) avant
`dominance.gd` — jamais une cinquième couche. Seul `banc_lien_personnel.gd:
decider` le câble aujourd'hui — voir `banc_lien_personnel`.

État des quatre couches : **closes et vertes au lanceur**. Ce qui reste à
faire (saturation, formation d'attaches en jeu, chef, combat, occlusion…) est
listé dans `docs/design.md`, section « État des couches », rubrique PAS FAIT.

---

## 2. Les scripts du cœur, un par un

Chaque script est une classe `RefCounted` sans état (fonctions `static`),
chargée par `preload` (jamais de `class_name` — voir CLAUDE.md). « Reçoit /
Rend » décrit la fonction principale.

Presque tous les mécanismes sont prouvés génériques par un test HORS DOMAINE
dédié — un cas inventé, sans rapport avec le feu ni le colon, qui traverse le
même code sans une ligne ajoutée. Le détail des cas vit dans le test ; la
liste des tests et leur marque hors domaine vit en §5.

CONVENTION, valable partout et non répétée : un catalogue est TOUJOURS reçu
en paramètre, jamais chargé par le mécanisme lui-même. Une propriété
STRUCTURELLE absente déclenche `push_error` puis un retour neutre — jamais un
défaut silencieux ; une propriété FACULTATIVE absente est un point neutre
légitime, sans alarme. Voir `docs/design.md`, « Propriété structurelle vs
facultative ».

### `scripts/objet.gd` — fabrication
- **Rôle** : construit `{ id, position, proprietes }` à partir d'un `type` et
  d'une table. Le type est un raccourci de fabrication : il charge un paquet
  de propriétés puis disparaît.
- **Fonction** : `fabriquer(id, type, position, table, materiaux={},
  proprietes_immuables=[], reserve_combustible={}, catalogue_emergences=[])`.
- **Rend** : l'objet, `proprietes` copiées en PROFONDEUR (`duplicate(true)`)
  — sinon muter un objet contaminerait le gabarit partagé. **Rend `{}` si la
  fabrication est REFUSÉE** (voir ÉCHEC FORT) : tout appelant qui fabrique un
  type portant `composition` doit vérifier ce retour vide.
- **Règle clé** : après fabrication, le cœur lit `objet.proprietes`, JAMAIS
  `table.get(type)`. Tout `catalogue.get(type)` dans une couche est un bug.
- **COMPOSITION DE PAQUETS, jamais une hiérarchie devinée** : un type ne
  reçoit les propriétés d'aucun paquet sauf s'il porte lui-même
  `herite: [...]`, un Array de noms fusionnés DANS L'ORDRE DÉCLARÉ, le type
  écrasant tout par-dessus. `herite` est retirée du résultat dans tous les
  cas. NON RÉCURSIF : un paquet qui porte lui-même `herite` alarme, sa clé
  est ignorée, le reste du paquet fusionne quand même — un type qui veut
  plusieurs paquets les nomme tous, à plat. Un paquet absent de la table
  alarme et se replie sur les paquets résolus. Voir `docs/design.md`, « Le
  colon n'est pas un type parent ».
- **PIÈGE, merge SUPERFICIEL** : `proprietes.merge(paquet, true)` n'est pas
  récursif — une clé présente dans un paquet ET dans le type remplace la
  valeur du paquet EN BLOC. Une surcharge partielle d'un Dictionary imbriqué
  hérité efface silencieusement le reste (voir §4, `types.json`, et §6).
- **QUATRE CALCULS GATÉS SUR `composition`**, dans cet ordre, tous morts si
  la clé est absente :
  1. **DENSITÉ EFFECTIVE** — `composition` est TOUJOURS un Array de
     `{ materiau, volume }` (aucune branche mono/multi). `densite` = moyenne
     pondérée des volumes, `volume` = somme, `masse = densite * volume` : les
     trois ÉCRASENT les défauts hérités, ce sont des SORTIES, jamais posées à
     la main. Conversion g/cm³ → kg/m³ par une seule constante nommée ;
     `materiaux.json` n'est jamais muté ni relu dans une autre unité.
     **ÉCHEC FORT**, seul du fichier : matériau absent, fiche sans `densite`,
     ou volume total nul → `push_error` puis `{}`, l'objet n'est PAS produit
     — jamais une densité mensongère.
  2. **PROPRIÉTÉS IMMUABLES** — même moyenne pondérée, sans conversion ni
     dérivation, pour chaque nom listé dans `proprietes_immuables`. Le
     critère n'est pas « densité » mais L'IMMUABILITÉ DE LA COMPOSITION : ce
     qui ne peut jamais changer après fabrication se calcule une fois ici.
     FACULTATIF PAR FICHE (absente → `0.0`, aucune alarme). `"densite"` dans
     la liste alarme et est ignorée : son calcul dédié reste la seule voie.
  3. **RÉSERVE DE COMBUSTIBLE** — une SOMME (déléguée à
     `quantite_matiere.gd`), jamais une moyenne : une quantité de matière est
     EXTENSIVE. Écrit un canal complet sous `proprietes.reserves`, en
     FUSIONNANT (les autres canaux d'un type qui compose `dynamique` ne sont
     jamais écrasés). `capacite` et `reserve` démarrent égales ; `capacite`
     n'est plus jamais réécrite ensuite. Le `cout_base` écrit est EFFECTIF :
     la référence du catalogue modulée par la densité (ralentit, au
     dénominateur) et la porosité (accélère). Champ requis absent : alarme,
     rien n'est écrit.
  4. **ÉMERGENCES** — DERNIER pas, et le seul à NE PAS dépendre de
     `composition` : s'applique à tout objet fabriqué. La loi d'évaluation
     vit dans `conditions.gd`, jamais ici. Appelée SANS `retirer_si_faux` :
     à la fabrication une émergence se fusionne et ne se retire JAMAIS
     (un objet ne change jamais de composition) — sans ce défaut, une
     émergence non déclenchée effacerait une clé homonyme posée par un paquet.

### `scripts/perception.gd` — Couche 1
- **Rôle** : perception brute, aveugle, exhaustive DANS LA GÉOMÉTRIE de
  chaque canal actif. Ne calcule aucune saillance, ne trie rien.
- **Fonction** : `percevoir(entite, monde, catalogue_canaux, catalogue_vent={},
  temps=0.0, sources_vent=[])`.
- **Rend** : Array de `{ chose, type, position, distance, canaux }` — une
  entrée PAR CHOSE (jamais de doublon même captée par plusieurs canaux), la
  liste `canaux` portant tous ceux qui l'ont captée.
- **Structurel vs facultatif** : `proprietes.canaux` (Array de String, les
  noms ACTIFS) est STRUCTURELLE. `canaux_config` (les RÉGLAGES) est
  FACULTATIVE dans son ensemble ET par canal : absente, le canal est MUET,
  jamais une alarme — le catalogue ne porte aucun défaut de repli. Un nom
  listé mais absent du catalogue alarme et ce canal seul est ignoré.
  `orientation` FACULTATIVE. `canaux: []` est un point neutre légitime.
- **Quatre géométries**, choisies par le catalogue : `cone_oriente` (filtre
  par angle ; `angle >= 360` dégénère en sphère), `propagation_obstacles`,
  `sphere_directionnelle` (sphère dont la PORTÉE est modulée par le vent),
  `contact`. Portée/angle/sensibilité/seuil vivent SUR L'ENTITÉ ;
  `sensibilite` multiplie la portée, `seuil` n'est CONSOMMÉ que par
  `propagation_obstacles`.
- **`propagation_obstacles` applique TROIS filtres** : distance, puis
  occlusion (déléguée à `occlusion.gd`), puis seuil sur l'intensité atténuée
  (`propriete_emission` de la source, défaut `"son_emis"`, atténuation
  LINÉAIRE `1 - distance/portee`). AUCUNE deuxième requête spatiale : tout
  obstacle géométriquement entre deux choses de la sphère y est déjà.
- **`proprietes_captees` est une MÉTADONNÉE, PAS un filtre de détection** :
  filtrer par propriété romprait « perception aveugle et exhaustive » et
  ferait fuiter du vocabulaire de banc dans une donnée partagée.
- **AUTO-EXCLUSION** : une entité ne se perçoit jamais elle-même. Filtre
  UNIQUE ici, jamais dans un appelant. `id` sur l'entité percevante est
  FACULTATIF (accès par `.get`, jamais pointé — une entité sans id ne peut
  structurellement pas se retrouver).
- **Le vent module la PORTÉE, jamais l'intensité en aval** : `distance` reste
  la vraie distance géométrique (contrat de `proximite.gd`). Câblage
  GÉOMÉTRIQUE (`sphere_directionnelle`), jamais nominal.
- **COÛT** : O(n) candidats testés par source dans une boucle déjà O(n) —
  O(n²) par appel dans le pire cas, NON OPTIMISÉ. Signaler à Yael si un
  appelant réel dépasse ~50 candidats par requête plutôt que d'ajouter une
  structure d'accélération en silence.
- **Appelle** : `monde.choses_dans_rayon(...)`.

### `scripts/croyance.gd` — copie partielle et faillible du monde
- **Rôle** : S'INTERCALE entre `percevoir()` et les évaluateurs de saillance.
  Prend le rendu de la perception et rend LA MÊME FORME, avec des
  `proprietes` qui sont la copie CRUE du percevant. Aucun des six fichiers de
  la chaîne n'a une ligne de changée : ils reçoivent `perceptions` en
  paramètre et ne vont jamais chercher le monde eux-mêmes.
- **Modèle** : `proprietes.croyances[chose_id][propriete] = { valeur,
  certitude }`. Le registre naît d'un ÉVÉNEMENT VÉCU, jamais posé en donnée —
  c'est ce qui le sépare du « registre consulté » écarté par `docs/design.md`.
- **Fonctions** : `observer`, `filtrer`, `corriger`, `avancer`.
  `proprietes.croyances` STRUCTURELLE sur les quatre.
- **CE QUE `filtrer` CONSERVE** : la copie remplace les PROPRIÉTÉS DU MONDE,
  jamais les CHAMPS DE CONFIGURATION TECHNIQUE. Un pointeur de catalogue
  (`profil_saillance`, `transformation`, `seuils_ref`, `materiau`,
  `composition`) n'est capté par aucun canal et sert au MOTEUR à retrouver sa
  règle : la liste vit en donnée (`proprietes_conservees`). Sans elle,
  `proximite.gd` rendrait `[]` sur toute perception filtrée et
  `attaches.gd`/`jugement.gd` deviendraient inertes avec lui — trois fichiers
  vivants mais MUETS, sans que rien ne rougisse.
- **CONSERVE TOUJOURS**, sans catalogue et sans condition : l'entrée de
  perception entière, et sur la chose SON ID et SA POSITION VIVANTE. Le
  percevant voit OÙ est la chose ; il ne sait pas ce qu'elle EST. Sans les
  id, l'inertie, l'engagement, les actes liants et l'attraction cassent tous
  EN SILENCE. `filtrer` ne mute RIEN : chaque chose rendue est un Dictionary
  NEUF, sans quoi écrire la croyance d'un percevant la réécrirait pour tous.
- **La certitude est ÉCRASÉE par `corriger`, jamais incrémentée** :
  incrémenter ferait du dogme le produit de la vérification elle-même. **Le
  dogme ne peut donc naître QUE de l'accumulation d'observations.**
- **Ne fait pas** : ne décide ni quand observer ni quand corriger (faits du
  CÂBLAGE) ; ne connaît aucune crédibilité (`credibilite_source` est un
  nombre DÉJÀ RÉSOLU par l'appelant) ; n'a AUCUNE notion de temps propre —
  `observer()` n'a pas de `delta`, la CADENCE vit au câblage ; ne mémorise
  AUCUNE position — c'est `memoire_spatiale.gd`, mécanisme DISTINCT. Les deux
  ne se recouvrent pas : celui-ci recopie CE QU'UNE CHOSE EST et rend
  toujours sa position vivante, l'autre retient OÙ elle était.
- **Décroissance par SOUSTRACTION FIXE**, comme tout le dépôt : aucun
  équilibre naturel, aucune asymptote. `avancer` retire la propriété sous le
  plancher PUIS la chose devenue vide — sans les deux retraits, le registre
  grossirait de croyances résiduelles puis de coquilles vides.
- **`seuil_bornes_transmission` n'est JAMAIS lu ici** : crédibilité minimale
  sous laquelle un CÂBLAGE renonce à transmettre.

### `scripts/portee.gd` — utilitaire minimal
Deux positions, une portée, une réponse binaire. `en_portee(position_a,
position_b, portee) -> bool`. Contrat : en-tête du fichier. Test :
`test_portee.gd`.

### `scripts/attaches.gd` — Couche 2, source « attache »
- **Rôle** : état de menace de ce à quoi le colon tient. Le lien se fait par
  PROPRIÉTÉ, jamais par nom de type — une chose qu'on n'a pas encore
  imaginée peut porter le trait et être défendue sans une ligne de code.
- **Fonction** : `evaluer(perceptions, colon, menaces,
  catalogue_deformations={})` → une entrée PAR ATTACHE, menacée OU intacte,
  jamais absente : `{ type, attache, menace, saillance }`. Le champ `type`
  porte `attache.propriete` — nom de clé imposé par `agir.gd`, qui le traite
  comme un jeton opaque.
- **Structurel** : `proprietes.attaches` et `proprietes.forme`.
- **Comment la menace naît** : le colon relie LUI-MÊME deux propriétés
  perçues (vulnérabilité/menace) par la distance ENTRE LES DEUX CHOSES,
  jamais au colon ; le rayon vient de la `forme`.
- **Deux effets pour une attache** : intacte → saillance BASSE (familiarité),
  menacée → saillance HAUTE. L'attache vit dans la routine, pas seulement
  dans la crise.
- **`forme`** (le mot « trait » est réservé en GDScript) : ne crée ni ne
  transforme les attaches, elle DÉFORME leur rayon et la hauteur des deux
  branches. Immuable.
- **Rend un NOMBRE**, jamais une position ni une identité — d'où le besoin
  d'un ciblage en aval pour retrouver OÙ aller.
- **Ne fait pas** : ne POSE jamais la propriété-menace, il la LIT.
- **Lecture de la déformation** : après la saillance nue, chaque source de
  `deformation_etat` dont la cible-map contient `attache.propriete` applique
  un facteur MULTIPLICATIF (`baisse` → `× (1 - biais)`, `monte` →
  `× (1 + biais)`), les sources se composant EN SÉQUENCE. La « cible » est
  directement la propriété — une attache ne porte aucune identité de chose.
  `deformation_etat` est FACULTATIVE ICI (elle est structurelle dans
  `deformation.gd` : deux fichiers, deux contrats).

### `scripts/proximite.gd` — Couche 2, source « proximité »
- **Rôle** : plancher commun à tous les colons. Une chose saillante en soi
  l'est pour tout le monde, sans attache ni forme.
- **Fonction** : `evaluer(perceptions, colon, catalogue={},
  catalogue_deformations={})` → `{ chose, type, position, saillance }`.
- **Référence de catalogue** : une chose porte `profil_saillance` (String),
  jamais les deux nombres en valeur. FACULTATIVE (absente → non saillante) ;
  dès qu'elle est présente sa résolution devient STRUCTURELLE. Une entrée
  résolue portant une saillance sans portée alarme et est exclue — plus de
  saillance maximale silencieuse à toute distance.
- **Atténuation LINÉAIRE FIXE** `clamp(1 - distance/portee)` : pas
  d'exposant, pas de coefficient. Le SEUL réglage de la distance est
  `portee_saillance` par profil (voir §4).
- **Pondération par avancement** : quand une chose porte `travail_restant` ET
  `travail_initial > 0`, la saillance est multipliée par leur rapport — un
  chantier presque fini pèse moins, sans exception codée. L'une des deux
  clés absente garde la saillance inchangée (point neutre, aucune alarme).
  Ne peut PAS osciller par construction : ce fichier ne mute jamais rien.
- **Distance** : celle au colon, déjà calculée en couche 1. C'est la SEULE
  distance au colon autorisée dans tout le moteur de saillance.
- **Se concatène** à la sortie d'`attaches.gd` : la couche 3 ne sait pas d'où
  vient un nombre.
- **PREMIER LECTEUR de la déformation**, patron ensuite copié par
  `attaches.gd`/`jugement.gd` : facteur multiplicatif par `(source, cible)`
  que la chose évaluée porte réellement, sources composées EN SÉQUENCE.
  `deformation_etat` FACULTATIVE ici.
- **NE LIT JAMAIS `etat_effectif.gd`** : `saillance_intrinseque` vit dans le
  catalogue, jamais sur l'objet. Un état qui prétendrait moduler une
  saillance serait vrai en donnée et sans le moindre effet, EN SILENCE — la
  seule voie pour faire gagner une cible par un état interne est
  `deformation.gd`, qui indexe PAR PERCEVANT.

### `scripts/jugement.gd` — Couche 2bis, troisième source de saillance
- **Rôle** : valeur émergente d'une chose par sa RENCONTRE avec une autre —
  ni le feu ni l'abri n'existent en dur. Une chose portant une propriété
  JUGÉE ne devient saillante que si une PRESSION (saillance déjà calculée en
  couche 2 sur une chose portant le DÉCLENCHEUR) existe.
- **Fonction** : `evaluer(perceptions, colon, resultats, jugements,
  catalogue_deformations={})` — même forme de sortie que `proximite.gd`.
- **`resultats`** est la couche 2 déjà concaténée, AVANT jugement : la
  pression ne lit jamais sa propre sortie.
- **Structurel** : `forme`. `gain_jugement` FACULTATIF (absent → ne juge
  rien) ; `plafond_jugement` bascule STRUCTUREL dès que le gain est présent
  et positif — CAS DU COUPLE : un gain sans plafond ne retombe pas sur un
  état neutre mais sur une saillance NON BORNÉE, plus forte que ce que le
  gain seul aurait produit.
- **PRESSION** : somme des saillances des choses PERÇUES portant le
  déclencheur. Pression nulle → RIEN, jamais une entrée à zéro. Pression
  positive → chaque chose PERÇUE portant la propriété jugée rend une entrée
  (elle peut n'avoir aucune saillance propre).
- **AUCUNE DISTANCE** n'entre dans ce calcul — ni entre les deux choses, ni
  au colon.
- **Le biais s'applique à la pression DÉJÀ SOMMÉE**, jamais à chaque
  saillance avant sommation : sinon il serait compté deux fois sur la même
  exposition (`proximite.gd` l'a déjà appliqué).
- **Optionnel par câblage** : ce n'est pas une cinquième couche.

### `scripts/dominance.gd` — Couche 3
- **Rôle** : n'ordonne pas, ÉCRASE. La saillance la plus haute devient la
  référence ; tout ce qui est plus bas que `seuil_ecrasement` en dessous du
  sommet devient INVISIBLE (retiré de la liste, pas « secondaire »).
- **Fonction** : `visibles(resultats, colon)`.
- **Structurel** : `forme` ; `seuil_ecrasement` en son sein FACULTATIF
  (défaut `INF`).
- **Ne compare que des nombres.** Aucun type en dur, aucun tri, aucune
  élection d'un gagnant — c'est `agir.gd` qui choisit.
- **RELATIF par construction** : il garde ce qui est à moins d'un écart du
  sommet, il ne peut donc pas porter un seuil ABSOLU. Une ressource seule
  dans le champ reste la décision, aussi faible soit sa saillance ; filtrer
  en absolu est un geste de câblage, avant lui.

### `scripts/agir.gd` — Couche 4
- **Rôle** : transforme ce qui reste visible en action, avec inertie.
- **Fonction** : `choisir(visibles, colon, catalogue, monde,
  catalogue_actes_liants={}, catalogue_attaches_par_trait={})` → l'action, ou
  `null`.
- **CONSTAT PORTANT** : `choisir` choisit d'abord la CIBLE au score, PUIS
  résout un verbe parmi ceux que la propriété gagnante propose.
  **`poids_verbes` ne pèse donc JAMAIS entre deux cibles** — le monter à
  10 000 ne fera jamais gagner la nourriture contre un feu. Les deux seules
  voies qui pèsent sur une cible sont `deformation.gd` et l'ajout d'une
  entrée de saillance à `resultats` avant `dominance.gd`.
- **Résolution de la PROPRIÉTÉ, jamais par nom de type** : `_action`
  distingue les deux origines par la présence de la clé `chose`. Origine
  attache → `visible.type` porte déjà la propriété. Origine proximité → scan
  des clés du catalogue (des noms de PROPRIÉTÉ) contre `chose.proprietes`, la
  première présente l'emporte (ordre du JSON). Une chose sans aucune
  propriété du catalogue est un cas LÉGITIME : action vide, aucune alarme.
  Une clé de catalogue compte pour l'arrêt du scan même si son contenu est
  vide — vider une entrée sans retirer la clé ne suffit pas.
- **Résolution du VERBE** : `_verbe_par_poids` retient, parmi les verbes
  proposés, celui dont `poids_verbes` porte le poids le plus haut STRICTEMENT
  POSITIF (nul : pas choisi ; négatif : interdit). Aucun verbe positif :
  action vide, cas légitime. Deux verbes à égalité stricte au maximum :
  `push_error` et départage par ordre déclaré — on ne tranche pas, on refuse
  le silence. `poids_verbes` est STRUCTURELLE, vérifiée seulement quand une
  entrée `verbes` est réellement résolue.
- **Inertie** : la tâche en cours reçoit `gain_inertie` avant comparaison ; à
  saillance égale elle gagne. `etat_courant(decision)` rend ce que le câblage
  doit mémoriser sur `action_en_cours` — sans cet appel, `gain_inertie` reste
  sans effet malgré des données non nulles.
- **ENGAGEMENT** : `_score` ajoute `engagement.poids`, additif après
  `gain_inertie`, quand la cible engagée est celle qu'on note.
  `_avec_cible_engagee` RÉINJECTE dans `visibles`, avant notation, une entrée
  de secours pour la cible engagée si son id en est absent (cas d'un chantier
  dont le profil est gelé par occupation) — sans quoi l'engagement ne
  pourrait jamais peser sur une cible devenue invisible. L'ARRACHEMENT PAR
  SAILLANCE n'est PAS empêché : une alternative réellement plus forte gagne
  quand même. `engagement` est FACULTATIVE ici (structurelle dans
  `couplage.gd`).
- **DEUX EFFETS DE BORD**, seules mutations d'un décideur autrement pur, tous
  deux INERTES à catalogue vide : les ACTES LIANTS (pose un lien personnel
  quand le verbe résolu et la propriété de la chose visée matchent une règle
  — sur le VERBE DÉCIDÉ, pas sur le travail accompli) puis l'ATTACHE PAR
  TRAIT (appelée seulement si son catalogue n'est pas vide, garde posée ICI
  pour qu'un colon sans `liens_personnels` n'alarme pas à chaque décision).
- **Règle clé** : ne lit JAMAIS `attache` ni `menace` — l'origine d'une
  saillance ne le regarde pas.

### `scripts/ciblage.gd` — traduit une décision en la chose visée
- **Rôle** : la décision est déjà prise ; ni `attaches.gd` ni `jugement.gd`
  ne rendent une position. `viser` ne décide rien, il retrouve OÙ elle pointe.
- **Fonction** : `viser(decision, perceptions, menaces, jugements,
  orientations)` → la chose visée, ou `null`.
- **Dispatch PAR VERBE, jamais par nom en dur** : un verbe absent de la table
  d'orientations vise le DÉCLENCHEUR par défaut (seul comportement qui ait
  jamais existé avant le jugement), jamais une alarme.
  - Branche `declencheur` : `decision.chose` si présente ; sinon, si la
    décision porte une menace, recherche de la chose qui menace le trait.
  - Branche `jugee` : la chose visée EST déjà `decision.chose` ; la table des
    jugements sert à CONFIRMER, jamais à relocaliser. Absente ou sans
    propriété jugée connue : `null` plutôt que de deviner.

### `scripts/fuite.gd` — mouvement de répulsion (PAS une couche de saillance)
- **Rôle** : ne décide rien — ne lit ni verbe, ni propriété, ni type. Reçoit
  une liste DÉJÀ TRIÉE de choses à fuir et rend une DIRECTION, jamais une
  cible-position. Séparé de `ciblage.gd` à dessein : fuir ne vise aucune
  chose.
- **Fonction** : `direction(colon_position, choses_a_fuir) -> Vector3` —
  normalisée, ou `Vector3.ZERO` si rien à fuir ou si les répulsions
  s'annulent exactement (l'appelant ne déplace pas).
- **Calcul** : chaque chose contribue `(colon - chose).normalized() *
  saillance` ; deux sources ADDITIONNENT leurs répulsions, le colon part à
  l'opposé de la plus forte et passe entre deux menaces sans cas particulier.
- **Le TRI qui sélectionne la liste est fait par l'appelant** : ce fichier ne
  sait même pas qu'un verbe existe.

### `scripts/propagation.gd` — transformation (allumage)
- **Rôle** : calcul pur. Quelles choses vulnérables gagnent une
  propriété-menace ce pas de temps, et reçoivent leur chantier.
- **Fonction** : `avancer(monde, menaces, exposition, delta, patron={},
  intensite={}, etats={}, emission={}, temperature_locale={})` → ids
  nouvellement enflammés. Les cinq derniers sont FACULTATIFS : un appelant
  qui ne les fournit pas garde EXACTEMENT le comportement d'avant.
- **Effet** : une chose exposée assez longtemps GAGNE la propriété-menace
  (jamais un champ `type` ni un bool `enflamme`) et reçoit les clés du patron
  qu'elle n'a pas déjà, AU GRAIN DE LA SOUS-CLÉ (voir `banc_commun`) : une
  chose qui porte déjà `reserves` garde ses canaux ET reçoit celui du patron.
- **Ne fait pas** : ne calcule aucune saillance — il POSE la propriété,
  `attaches.gd` la LIT. Les deux lisent la même table, aucun n'écrit dans
  l'autre.
- **`delai_propagation` STRUCTURELLE dès que la vulnérabilité est confirmée**
  (facultative avant, la chose étant déjà filtrée) : son absence
  contredirait la vulnérabilité qu'elle borne, par un déclenchement
  INSTANTANÉ — alarme puis `continue`, plus aucun défaut `0.0` silencieux.
- **TROIS GATES QUI COEXISTENT**, aucun ne remplace l'autre, tous facultatifs
  et tous appliqués au MÊME délai :
  - **intensité effective** — sous `seuil_ignition`, l'exposition est remise
    à zéro (même traitement qu'une chose hors portée) ; au-dessus, le délai
    est DIVISÉ par l'intensité (plus intense, plus vite). Résolue via
    `etat_effectif.gd` : un état comme `mouille` peut donc l'écraser.
  - **émission et seuil** — sépare deux grandeurs que `portee_propagation`
    confondait : `recu` (ce qu'une cible reçoit d'UNE source : émission de la
    source, dérivée de la CAPACITÉ de sa réserve, divisée par le carré de la
    distance) et `seuil_exposition` (ce qu'il faut à la cible : seuil de base
    divisé par SON intensité effective). CONSÉQUENCE ASSUMÉE : l'intensité
    effective joue à DEUX endroits — la distance à laquelle l'exposition
    commence ET la vitesse à laquelle elle aboutit — donc l'écart entre deux
    matières se MULTIPLIE, jamais ne s'additionne.
  - **point d'ignition** — bloque si la propriété NOMMÉE PAR LA DONNÉE est
    strictement supérieure à la température locale (scalaire DÉJÀ RÉSOLU par
    l'appelant pour CETTE chose). Le défaut `INF` désactive le gate PAR LA
    SEULE ARITHMÉTIQUE, aucune branche « si absent » à écrire — de même que
    le défaut `""` du nom de propriété ne matche jamais rien. RISQUE ACCEPTÉ :
    un matériau sans la propriété dans sa fiche retombe à `0.0` et ne bloque
    donc JAMAIS ce gate.
- **`recu`, `seuil_exposition` et `delai_ignition` sont PUBLIQUES et en
  lecture seule**, destinées à l'observabilité d'un banc : MÊME calcul
  interne que `avancer()`, jamais dupliqué.
- **Précharge `banc_commun.gd`** pour poser les clés du patron — SEUL
  mécanisme du cœur à précharger cette boîte à outils. Exception assumée :
  il portait auparavant sa propre copie du geste, avec le même bug
  d'aliasing ; plutôt que corriger deux fois, il appelle l'unique version.

### `scripts/extinction.gd` — LE modèle de transformation générique
- **Rôle** : pas un « code du feu ». Une chose portant un chantier
  (`travail_restant` sur l'instance, `transformation` en référence) est
  mangée par les agents à portée jusqu'à zéro, puis change de propriétés.
  Sert aussi bien à éteindre un feu qu'à miner un rocher ou couper du bois.
- **Fonction** : `avancer(monde, agents, delta, transformations, table={},
  materiaux={})` → ids dont le chantier s'est accompli.
- **HYBRIDE, pas une simple écriture différée** : `travail_restant` décroît
  EN CONTINU à chaque tick ; ce n'est qu'à zéro que `a_zero` écrit une fois
  pour toutes. Deux natures d'effet dans le même fichier.
- **`a_zero`** vit dans l'entrée résolue, jamais sur la chose : `retirer`
  et/ou `poser`, ou `produire` qui REMPLACE entièrement les deux — l'objet
  existant disparaît et le nouveau le remplace SUR LA MÊME INSTANCE (même
  id, même position). `produire` sans table fournie alarme et se replie.
- **Le produit peut repartir dans un nouveau chantier** via `patron_produit`,
  ce qui permet une CHAÎNE sans dépendre d'un second allumage.
- **Garde complète** : `transformation` manquante, référence non résolue, ou
  `portee_travail` absente de l'entrée résolue — chacune alarme puis
  `continue`. Plus aucun défaut `0.0` silencieux.
- **Ne fait pas** : ne ponctionne jamais une chose toute seule, il faut des
  agents à portée. Une chose qui se consomme seule, c'est `depense.gd`.

### `scripts/produit.gd` — objet neuf par rendement de masse
- **Rôle** : calcul PUR, aucune mutation, aucune connaissance du monde ni des
  agents. Reçoit les propriétés de l'objet qui disparaît et rend celles du
  nouvel objet, ou `{}`.
- **Doctrine** : la masse n'est JAMAIS posée à la main. Ce fichier construit
  une composition dont chaque volume est calculé pour que `objet.gd`
  redérive exactement `rendement * masse_ancien` — généralisé à N matériaux,
  chaque élément gardant sa proportion. `rendement_perdu` n'existe pas comme
  champ : c'est le complément, jamais stocké.
- **La masse perdue n'est nulle part** : sauf pour la seule paire d'entrées
  du dépôt dont les rendements somment à 1.0, le complément disparaît. Un
  câblage qui veut la conserver appelle DEUX FOIS ce fichier sur le MÊME
  `proprietes_ancien`, avant tout écrasement.
- **NE RELAIE AUCUNE PROPRIÉTÉ IMMUABLE** sur l'objet neuf — constat
  systémique, jamais corrigé ici : un produit qui doit garder une propriété
  de sa matière doit se la faire reposer par le câblage juste après.
- **Chemins morts vs échecs** : rendement nul ou négatif → `{}` SANS alarme
  (rien ne se produit, c'est légitime). Config incomplète, type absent de la
  table, volume total nul, matériau sans densité → alarme puis `{}`.
- **`proprietes_ancien` peut être SYNTHÉTIQUE** (`{ "masse": m }`) : ce
  fichier ne lit que cette clé dessus. Geste généralisable à tout chantier
  qui produit depuis une quantité plutôt que depuis une chose.

### `scripts/depense.gd` — dépense de réserves nommées
Une chose se ponctionne elle-même, réserve par réserve, jusqu'à des seuils en
escalier. `avancer(monde, delta, catalogue={})`. Contrat, pièges et frontières :
en-tête du fichier. Test : `test_depense.gd`.

### `scripts/charge.gd` — charge à seuil, RÉVERSIBLE
- **Rôle** : un canal MONTE tant qu'une cause est perçue à portée (somme des
  contributions), FRANCHIT un seuil qui pose une cause en donnée, puis
  REDESCEND seul quand la cause disparaît et RETIRE la même cause en
  repassant sous le seuil. Une seule table `poser` suffit : le
  franchissement montant l'ajoute, le descendant retire exactement les mêmes
  clés.
- **Fonction** : `avancer(monde, causes, delta)` → ids ayant basculé dans un
  sens ou l'autre.
- **`causes`** est un Array nu de `{ position, poids? }` construit par
  l'appelant : ce fichier ne scanne JAMAIS le monde et ne lit jamais une
  réserve. Une cause SYNTHÉTISÉE à la position de l'objet lui-même, avec une
  portée nulle, ne peut alimenter que lui — c'est ainsi qu'un état interne
  devient sa propre cause.
- **PIÈGE STRUCTUREL** : `avancer` applique LA MÊME liste de causes à TOUS
  les canaux de chaque chose, et les causes ne portent aucun type. **Deux
  canaux sur le même objet ne peuvent donc pas être alimentés par deux causes
  différentes** — il faut soit des familles d'objets disjointes, soit un
  appel par objet. Aucune portée ne les sépare (une portée large contient
  toujours la petite).
- **SECOND PIÈGE** : au franchissement descendant, `avancer` EFFACE ses clés
  `poser`. Branché directement sur `seuil_etat.gd`, qui sort quand la
  propriété comparée est absente, l'état serait posé à la montée et JAMAIS
  retiré à la descente — irréversible en silence. D'où le miroir plat `0/1`
  que les câblages écrivent entre les deux.
- **UN SEUL SEUIL PAR CANAL, PAS D'HYSTÉRÉSIS** : une charge qui oscille pile
  autour du seuil pose et retire à chaque pas. Non corrigé — raffinement de
  câblage à ajouter en donnée si le besoin se présente, pas une garde du
  mécanisme.
- **Frontières** : `depense.gd` décroît en interne, sans portée, et applique
  ses seuils une seule fois ; `extinction.gd` décroît par agents à portée mais
  ne remonte jamais. `charge.gd` est le seul des trois à monter sous portée,
  basculer, puis redescendre seul.

### `scripts/couplage.gd` — continuité entre ticks
- **Rôle** : le VERBE — l'acte physique de rester lié à une cible tant qu'on
  reste à portée. N'EST PAS une intention BDI (aucun plan défendu contre la
  distraction, les quatre couches tournent toujours) ; N'EST PAS
  `gain_inertie` (préférence de PERSONNALITÉ, distincte). Le fichier suit le
  mécanisme, l'ÉTAT qu'il pose garde son nom.
- **Fonctions** : `poser`, `avancer` → `"vide"|"garde"|"satisfait"|"arrache"`,
  `retirer`. `proprietes.engagement` STRUCTURELLE ; valeur `null` légitime.
- **`satisfait_par`** : chemin en points, cherché D'ABORD sur la cible, SINON
  sur l'entité (un chantier se lit sur la CIBLE, une réserve sur l'ENTITÉ).
  Absent des deux → `0.0`. Peut porter des jetons substitués depuis un
  contexte posé à la pose, ce qui permet à UNE règle de servir N canaux
  interchangeables sans dupliquer l'entrée.
- **`sens_satisfaction`** : un chantier se satisfait en DESCENDANT vers son
  seuil, une réserve en MONTANT — deux sens opposés pour le même mécanisme,
  tranchés par ce champ et figés sur l'engagement au moment de la pose.
- **Ne fait pas** : l'ARRACHEMENT PAR SAILLANCE n'est PAS évalué ici (ce
  fichier ne reçoit ni saillance ni `visibles`) ; il vit dans `agir.gd` ou
  dans le câblage.

### `scripts/deformation.gd` — biais accumulé par exposition
- **Rôle** : un biais NOMMÉ PAR SOURCE puis PAR CIBLE, à DEUX REGISTRES DE
  DURABILITÉ jamais un seul nombre. `poser` incrémente les deux d'un coup ;
  `avancer` les décroît chacun à son propre taux — c'est cette DIFFÉRENCE de
  taux qui donne le « court terme vs long terme », pas une propriété du
  registre. `biais` ne fait que LIRE : combinaison pondérée des deux.
- **Fonctions** : `poser(entite, source, cible, magnitude)`, `avancer`,
  `biais` → float.
- **Deux champs, deux rôles** : `deformation_sources` (Array de String, les
  sources DÉCLARÉES, vérifiées par le linter) et `deformation_etat`
  (l'ÉTAT mutable, jamais vérifié). TOUTES DEUX STRUCTURELLES. `cible` est
  une simple clé, un nom de propriété du monde — jamais une référence de
  catalogue.
- **`poser` refuse une source non déclarée** : alarme, aucune écriture.
- **`sens` est PORTÉ, non lu ici** : il n'est appliqué qu'au moment où une
  couche de saillance lit le biais.
- **RÉSULTAT NÉGATIF MESURÉ DEUX FOIS, interdit de le repayer** : `avancer`
  décroît par SOUSTRACTION FIXE, jamais par une fraction du registre. Il
  n'existe donc AUCUNE asymptote — un débit de pose égal au taux laisse le
  registre PLAT, et tout débit supérieur le fait monter LINÉAIREMENT ET SANS
  BORNE. **Le plafond vit au CÂBLAGE, jamais espéré du mécanisme.** Plafonner
  chaque registre séparément a été essayé puis ÉCARTÉ : le biais retombait
  tout seul alors que la cause était toujours là.
- **SEULE VOIE DU DÉPÔT qui fasse gagner une CIBLE par un état interne**,
  parce qu'elle indexe PAR PERCEVANT : deux entités lisent le même monde
  différemment. Ni `poids_verbes` (qui départage des VERBES d'une cible déjà
  gagnante) ni un effet d'état (qui modifie une propriété DU PORTEUR) ne le
  peuvent.

### `scripts/lien_personnel.gd` — force de lien vers une chose précise
- **Rôle** : `proprietes.liens_personnels[chose_id] = force` — Dictionary
  PLAT, jamais imbriqué (un lien vise UN objet précis, pas une paire).
  `poser` ACCUMULE (un renouvellement ne remplace jamais) ; `avancer` décroît
  et RETIRE l'entrée sous un plancher — sans ce retrait le Dictionary
  grossirait indéfiniment de liens résiduels. `force` ne fait que LIRE.
- **Structurel** : `proprietes.liens_personnels`. Valeur vide légitime.
- **La valeur est un float NU, et sa résumabilité l'impose** : l'enrichir
  casserait les cinq fichiers du cœur qui le lisent. Écarté par audit, à ne
  pas reproposer — un registre à valeur enrichie est un fichier séparé
  (`memoire_spatiale.gd`).
- **Aucune notion de plafond** : il accumule sans borne, c'est son contrat.
  Un appelant qui veut un plafond lit la force et ne pose que le reliquat.
- Trois fichiers l'ÉTENDENT sans jamais le muter : `_saillance` (lit),
  `_attraction` (génère un candidat), `_croissance` (écrit).

### `scripts/lien_personnel_saillance.gd` — bonus de saillance par lien
- **Rôle** : ne rend PAS saillante la chose aimée : rend saillant ce qui
  s'en APPROCHE, dans l'espace — même géométrie « liaison entre deux choses,
  jamais au colon » qu'`attaches.gd`.
- **Fonction** : `bonus(colon, chose, monde, catalogue) -> float`.
- **Algorithme** : pour chaque chose liée, distance ENTRE la chose évaluée et
  la chose liée (jamais au colon) ; au-delà de la portée, contribution nulle ;
  en-deçà, décroissance linéaire. Retourne la SOMME — composition ADDITIVE,
  jamais multiplicative comme la déformation.
- **`monde` est duck-typé** (`par_id`), jamais un import : une chose liée
  détruite rend `null` et est simplement ignorée.
- **AMPLIFIE un candidat qui existe déjà**, il n'en crée jamais.

### `scripts/lien_personnel_attraction.gd` — le lien comme SOURCE de saillance
- **Rôle** : comble le trou laissé par le précédent — une chose aimée sans
  saillance propre n'apparaissait jamais dans `resultats`. Génère, pour
  chaque chose liée, un candidat de MÊME FORME que `proximite.gd`/
  `jugement.gd`.
- **DISTANCE AU COLON, pas entre deux choses**, et elle ne vient JAMAIS d'une
  perception (`perceptions` n'est pas même un paramètre) : c'est précisément
  le trou comblé — une chose aimée doit devenir une cible MÊME HORS DE PORTÉE
  DE PERCEPTION.
- **ADDITIF, AUCUN CAS PARTICULIER** : ajoute toujours son entrée, même si la
  chose a déjà un candidat par ailleurs. Le double compte est voulu et
  s'auto-régule par `dominance.gd`.
- **Rend `[]`**, jamais une entrée à saillance nulle.

### `scripts/lien_personnel_croissance.gd` — croissance par perception
- **Rôle** : ÉCRIT dans `liens_personnels` depuis des perceptions filtrées
  par TRAIT. Un lien peut naître de la perception RÉPÉTÉE d'une chose portant
  un trait recherché, pas seulement d'un événement liant.
- **CONVENTION D'UNITÉ, bug audité et fermé** : un montant FIXE par événement
  de pose, JAMAIS un débit multiplié par `delta`. La première version
  multipliait par le delta : à framerate réel le montant posé tombait sous le
  plancher de suppression, donc la décroissance appelée au même tick effaçait
  le lien avant qu'il survive — créé puis détruit à chaque frame,
  indéfiniment, aucune cristallisation possible.
- **COOLDOWN** : un montant fixe posé à CHAQUE tick accumule trop vite pour
  rester observable. `intervalle_pose` espace les poses ; le reliquat est
  conservé, jamais remis brutalement à zéro. Intervalle nul dégénère en
  « pose à chaque tick », point neutre légitime.
- **PLAFOND BORNÉ CÔTÉ APPELANT** : ce fichier lit la force déjà accumulée et
  ne pose que le reliquat manquant — `lien_personnel.gd` reste pur.
- **Trait cherché sur une propriété PLATE**, jamais une attache imbriquée.

### `scripts/attache_par_trait.gd` — lien personnel → attache générale
- **Rôle** : une entité qui a personnellement vécu plusieurs choses
  DIFFÉRENTES portant le même trait finit par porter une attache GÉNÉRALE sur
  ce trait — elle défendra désormais n'importe quelle chose qui le porte.
- **SEUIL COMPOSITE** : NOMBRE de choses liées ET FORCE individuelle, les
  deux exigés à la fois.
- **Fonction** : `avancer(entite, monde, catalogue)` → traits NOUVELLEMENT
  acquis. IDEMPOTENT ; aucun mécanisme d'oubli — une attache formée n'est
  jamais retirée ici (c'est `usure_attache.gd`, et il ne la retire pas non
  plus).
- **`propriete` nomme EXPLICITEMENT le trait** vérifié et posé, jamais deviné
  en décodant l'identifiant de règle.
- **SURCHARGE PAR COLON** : les trois seuils se lisent colon d'abord,
  catalogue en repli, chacun indépendamment (surcharge partielle valide). La
  clé de surcharge est FACULTATIVE.
- **PIÈGE MESURÉ** : une règle de ce catalogue est GLOBALE. Une règle ajoutée
  sur un trait très répandu se déclenche sur tous les objets qui le portent
  et fausse d'autres bancs — les règles propres à un banc restent locales.
- **En aval, aucune distinction** : `attaches.gd` ne sait pas si une attache
  a été posée à la fabrication ou formée ici.

### `scripts/usure_attache.gd` — érode les attaches cristallisées
- **DEUX FICHIERS, DEUX RESPONSABILITÉS** : `attache_par_trait.gd`
  CRISTALLISE du neuf et ne touche jamais l'existant ; celui-ci fait
  l'INVERSE et seulement l'inverse. Les deux cohabitent sur la même clé sans
  jamais s'appeler.
- **DOCTRINE (sédimentation, jamais effacement)** : une attache cristallisée
  ne disparaît JAMAIS. **PATRON NEUF dans ce dépôt** : tous les autres
  mécanismes de décroissance RETIRENT l'entrée sous un plancher ; celui-ci a
  un plancher STRICTEMENT POSITIF que la force ne franchit jamais, et
  l'entrée n'est jamais retirée.
- **DEUX CANAUX D'ÉROSION, jamais additifs** (un seul s'applique par attache
  et par tick) : usure passive par défaut, remplacée — jamais complétée — par
  l'usure de contradiction dès qu'une chose portant le trait CONTRADICTOIRE
  est perçue.
- **GEL PAR RENOUVELLEMENT, priorité absolue** : percevoir CE TICK une chose
  portant le trait de l'attache elle-même annule TOUTE érosion, même si une
  chose contradictoire est perçue en même temps. Le gel ne fait jamais
  REMONTER la force — elle ne remonte que par une cristallisation neuve.
- **Deux catalogues, deux contrats** : celui de l'usure a une sentinelle
  `defaut` et alarme si elle manque (l'usure est universelle) ; celui des
  contradictions est ITÉRÉ EN ENTIER et un catalogue VIDE est un point neutre
  légitime.
- **Non câblé à ce jour** : aucun banc ne l'appelle.

### `scripts/expression.gd` — gènes, marques, sénescence → valeurs effectives
- **Rôle** : lit les trois catalogues du corps interne et produit un effet
  mesurable. Deux fonctions : `exprimer` (PURE, rend
  `{ chemin: valeur_effective }`) et `appliquer` (mute par chemin).
- **COMPOSITION ADDITIVE** : gènes, marques et courbes qui visent le même
  chemin s'additionnent tous à la valeur de base, sans ordre de priorité —
  précédent `depense.gd` (deux modulateurs indépendants sur un canal), PAS
  celui de `deformation.gd` (un biais unique appliqué multiplicativement).
- **`_ecrire_chemin` est ASYMÉTRIQUE avec `_lire_chemin`** : un chemin absent
  en LECTURE rend `0.0` (point neutre) ; un segment intermédiaire absent en
  ÉCRITURE alarme et n'écrit rien — jamais de création silencieuse de
  structure imbriquée.
- **QUATRE MODES** (`dominant` = max, `recessif` = min, `additif` = somme,
  `incomplet` = moyenne). `codominant` est RETIRÉ : non traduisible en une
  seule valeur scalaire. Un mode inconnu alarme et contribue `0.0`, jamais
  une formule devinée. Côté sénescence, seul `lineaire` est implémenté : les
  autres exigent un champ absent du catalogue.
- **Aucune liste « senescence_actifs »** : chaque courbe s'applique dès que
  l'âge franchit son seuil, universellement — une courbe n'est pas une
  référence choisie par l'entité, contrairement à un gène.
- **RÉSULTAT NÉGATIF MESURÉ QUATRE FOIS, décisif** : appelé à CHAQUE TICK,
  `exprimer` relit par `_lire_chemin` la valeur que `appliquer` vient
  d'écrire au tick précédent et fait DIVERGER la propriété visée sans borne.
  **Aucun câblage du dépôt ne l'appelle donc dans une boucle** : ceux qui ont
  besoin d'un modulateur le lisent eux-mêmes et le composent. Contournement
  INTENTIONNEL, pas un oubli — et le champ `cible` des catalogues reste
  DOCUMENTAIRE tant que c'est le cas.

### `scripts/epigenetique.gd` — marque acquise par exposition, décroissante
- **Rôle** : entre la génétique (permanente) et le vécu cristallisé — une
  marque acquise par l'exposition, qui décroît si l'exposition cesse.
- **Deux fonctions** : `poser(entite, nom_marque, catalogue)` — l'appelant ne
  choisit PAS la magnitude, la donnée le fait — et `avancer` (soustraction
  fixe, retrait sous plancher, `age_marque` incrémenté
  INCONDITIONNELLEMENT).
- **`age_marque` ne fait que s'accumuler** : jamais lu ici, jamais remis à
  zéro, jamais consommé par la décroissance — un pur horodatage informatif.
- **Catalogue PAR MARQUE, jamais un `defaut` partagé** : une marque de guerre
  ne s'installe pas au rythme d'une marque de famine.
- **AUCUNE FONCTION DE LECTURE** : il n'a que `poser` et `avancer`. Lire un
  modulateur est un geste de CÂBLAGE.
- **AUCUNE BORNE HAUTE** : `poser` ajoute sans plafond. Un plafond est un
  geste de câblage, et il doit être un GATE DE POSE — un simple clamp à la
  lecture masque la décroissance et crée une hystérésis par accident.
- **CONTRAINTE DE CADENCE, résultat négatif mesuré deux fois** : une marque
  fraîche vaut `modulateur_pose` et tombe sous `plancher_suppression` après
  `(modulateur_pose - plancher_suppression) / taux_decroissance` secondes.
  **Un câblage qui pose à un intervalle supérieur n'accumule JAMAIS rien** —
  la marque est effacée entre deux poses, et rien ne rougit nulle part.
- **Qui appelle `poser`** : le câblage détecte l'exposition, jamais ce
  fichier — il ne sait pas ce qu'est un « environnement de guerre ».

### `scripts/senescence.gd` — âge de l'entité, et temps du monde
- **Rôle, DEUX horloges disjointes** : `proprietes.age` (INDIVIDUELLE, en
  ANNÉES) et `heure_courante`/`saison` (MONDIALES, identiques pour toutes les
  entités du même tick). L'âge ne se déduit jamais de l'heure, ni l'inverse.
- **Fichier MINIMAL, VOULU** : tout le calcul de sénescence vit dans
  `expression.gd` ; celui-ci ne fait qu'avancer l'horloge que l'autre lit, et
  écrire le temps du monde que `horloge.gd` calcule. Même séparation que
  `stade.gd` (compare) face à lui (incrémente).
- **Fonction** : `avancer(entite, delta, annees_par_seconde, horloge={})`.
  `annees_par_seconde` est REÇU EN PARAMÈTRE, jamais une constante : c'est au
  CÂBLAGE de choisir à quelle vitesse le temps du jeu vieillit ses entités —
  et c'est ce qui rend une simulation accélérée possible sans toucher le cœur.
- **`horloge` FACULTATIF** = ce monde n'a pas d'horloge : aucune écriture,
  aucune alarme. CAS DU COUPLE : chaque clé devient STRUCTURELLE dès que le
  Dictionary est fourni. **L'ÂGE AVANCE TOUJOURS**, horloge cassée ou non —
  deux rôles disjoints, jamais un chemin où l'un fait tomber l'autre.
- **`age` STRUCTURELLE ici**, FACULTATIVE dans `expression.gd` : deux
  fichiers, deux contrats sur la même clé.

### `scripts/stade.gd` — stade de vie selon l'âge
- **Rôle** : système OUVERT — chaque type déclare ses propres stades en
  donnée, ce fichier n'en connaît AUCUN nom. Un colon, un papillon et un
  arbre passent par le même mécanisme, seules les données diffèrent.
- **Fonction** : `avancer(entite)`. NE REÇOIT AUCUN CATALOGUE : la table des
  stades vit sur l'entité.
- **LE STADE NE RECULE JAMAIS**, garanti par comparaison d'INDEX dans la même
  table — jamais par une hypothèse sur le sens de variation de l'âge.
- **C'est ce qui en fait un NON-OUTIL pour tout cycle** : une saison, un
  cycle qui se répète, ne peuvent pas s'écrire avec — écarté par un chantier,
  à ne pas reproposer.
- **STADES EXCLUSIFS PAR CONSTRUCTION** : `proprietes.stade` est UNE String,
  jamais un ensemble de marqueurs cumulés — c'est exactement ce qui le
  distingue de `seuil_etat.gd`, où plusieurs états restent actifs ensemble.
- **Structurel** : `age` et `stades_config`. Table VIDE = point neutre
  légitime. `stade` lui-même n'est jamais vérifié, seulement comparé par
  index (une chaîne vide vaut « aucun stade atteint »).
- **NE POSE AUCUNE AUTRE PROPRIÉTÉ** : les mécanismes en aval LISENT le
  stade, ce fichier ne les connaît pas.

### `scripts/accouplement.gd` — 2ᵉ phase du cycle de reproduction
- **Rôle** : deux individus MATURS et COMPATIBLES qui se PERÇOIVENT
  accumulent une exposition ; au seuil, `gestation` est posée sur ceux des
  deux QUI PEUVENT GESTER — IRRÉVERSIBLE, et elle bloque elle-même tout
  nouvel accouplement (aucun cooldown séparé).
- **PROCESSUS PASSIF, HORS PIPELINE DE DÉCISION** : jamais appelé par
  `agir.gd`. Deux individus proches et compatibles se reproduisent SANS
  décision, sur la seule base de la perception.
- **COMPATIBILITÉ PAR PROPRIÉTÉ, JAMAIS PAR TYPE** : une String d'espèce qui
  doit matcher exactement. MATURITÉ par `stade` (posé par `stade.gd`), jamais
  un âge relu directement.
- **Ne s'exécute QUE pour le mode `"sexuee"`** : les autres modes sautent la
  phase silencieusement — ce fichier est appelé sur tout le monde, comme
  `charge.gd`.
- **CAS DU COUPLE** : dès que le mode est `"sexuee"`, trois clés deviennent
  STRUCTURELLES. Côté PARTENAIRE PERÇU, aucune de ces vérifications n'alarme
  (il aura sa propre alarme quand il sera lui-même l'entité traitée).
- **ACCUMULATION IRRÉVERSIBLE** : jamais réinitialisée tant que le seuil
  n'est pas franchi — contrairement à `charge.gd`, une exposition interrompue
  puis reprise CONTINUE d'accumuler. Elle n'oublie JAMAIS : un câblage qui
  retire une gestation doit vider l'accumulateur lui-même, sinon la gestation
  est REPOSÉE au tick suivant.
- **FÉCONDER LES DEUX, N'EN FAIRE GESTER QU'UN** : le
  partenaire perçu est muté lui aussi (ce que rend la perception est la chose
  du monde, jamais un double), mais l'état n'atterrit que sur qui `role_gestation`
  autorise. Chacun ne consulte que son rôle : rien n'arbitre entre eux, deux
  hermaphrodites pondent chacun le leur, un rôle absent ne produit rien.
  Chaque gestation emporte l'id de l'autre et une COPIE PROFONDE de ses
  gènes, figée là — l'état vivant n'est plus jamais relu.

### `scripts/gestation.gd` — 3ᵉ phase
- **Rôle** : un compteur avance depuis une gestation DÉJÀ POSÉE jusqu'à un
  seuil qui pose `naissance_prete` — IRRÉVERSIBLE, jamais retiré ici.
- **NE CRÉE JAMAIS L'ENFANT** : ce fichier ne connaît ni fabrication, ni
  monde, ni générateur d'id. C'est à l'appelant de lire le flag, d'appeler
  l'hérédité puis la fabrication, PUIS de retirer la gestation lui-même.
- **Deux fonctions** : `avancer` (silencieux si aucune gestation — appelé sur
  tout le monde ; IDEMPOTENT une fois le flag posé) et `poser`, POINT
  D'ENTRÉE SÉPARÉ pour les modes où l'accouplement ne tourne jamais. `poser`
  produit EXACTEMENT la même forme de gestation : une seule forme dans tout
  le dépôt, jamais deux selon le mode. `null` fait de l'entité sa propre
  source ; un Dictionary partiel ne surcharge que ce qui diverge.
- **En SECONDES BRUTES**, pas d'échelle en années : décision assumée.
- **CAS DU COUPLE** : dès qu'une gestation est présente, la référence de
  reproduction devient STRUCTURELLE. Le catalogue doit porter la durée —
  absente, alarme et rien n'est écrit, jamais un défaut `0.0` qui ferait
  naître l'entité au premier appel.

### `scripts/heredite.gd` — 4ᵉ phase, ferme le cycle
- **Rôle** : produit le KIT GÉNÉTIQUE de l'enfant — jamais l'enfant.
  FONCTION PURE, ne mute rien.
- **Fonction** : `fabriquer_genes_enfant(entite, catalogue_heredite,
  catalogue_epigenetique, rng)` → `{ genes_etat, marques_epigenetiques }`.
- **MODE lu sur l'entité**, jamais un paramètre séparé. Trois combinaisons
  des allèles de chaque gène actif : `sexuee` (un allèle tiré chez chacun —
  le résultat porte TOUJOURS exactement deux allèles, quelle que soit la
  taille des tableaux parents), `asexuee` (copie du tableau complet),
  `parthenogenese` (réarrangement avec remise, même taille en sortie qu'en
  entrée, généralisé à N allèles). Un mode inattendu alarme et rend un
  Dictionary VIDE : ce fichier n'est appelé qu'une fois le cycle établi, un
  mode inconnu ici est une donnée mal posée en amont.
- **MUTATION** : chaque position est indépendamment soumise à un tirage ;
  sous le taux, l'allèle reçoit un bruit gaussien ADDITIF. AUCUN BORNAGE —
  un allèle reste un float libre.
- **MARQUES** : pour chaque marque présente chez l'UN OU L'AUTRE parent, le
  modulateur transmis est le MAXIMUM des deux (jamais une moyenne ni une
  somme), multiplié par un taux résolu PAR NOM DE MARQUE. Sous le plancher,
  la marque n'est pas transmise. Une marque transmise démarre à un âge nul.
- **RNG REÇU en paramètre**, jamais instancié : le seed vit chez l'appelant.
  À seed égal, deux appels rendent le même résultat.
- **`genes_actifs` n'est PAS produit ici** : c'est le TYPE qui le porte pour
  l'enfant.
- **Deux champs du catalogue restent DORMANTS** : aucun paramètre
  d'environnement ni d'âge des parents n'est reçu, aucun des deux concepts
  n'est cadré.

### `scripts/flux.gd` — transfert continu NON conservé
- **Rôle** : une chose portant une propriété SOURCE recharge la réserve
  nommée de toute chose à portée portant la propriété RÉCEPTRICE. Neutre par
  construction : un taux NÉGATIF vide la réserve par le même code — ce n'est
  pas « le gain ».
- **Fonction** : `avancer(monde, table_flux, delta)` → ids modifiés.
- **NE DÉPLÈTE JAMAIS SA SOURCE** — c'est ce qui le sépare de
  `consommer.gd`, et c'est physiquement correct pour une source ambiante.
- **`portee_flux`/`taux_flux` sont posés sur la SOURCE** à la fabrication,
  jamais dans la table.
- **Ne connaît QU'UN SEUL taux par source** : un câblage qui veut un taux
  proportionnel au RECEVEUR construit un émetteur SYNTHÉTIQUE par receveur.
- **Ne borne rien** et ne sait pas propager de proche en proche (une
  réceptrice ne devient jamais source).
- **Même canal que `depense.gd`** à dessein : ce que l'un recharge, l'autre
  peut le ponctionner, sans structure concurrente.

### `scripts/consommer.gd` — transfert DESTRUCTIF
- **Rôle** : sœur de `flux.gd`, jamais une variante — déplète TOUJOURS la
  source de la quantité exacte que le receveur gagne, au même tick. Sert
  manger, boire, miner, récolter, traire, vampiriser.
- **Fonction** : `transferer(source, receveur, nom_reserve_source,
  nom_reserve_receveur, taux, delta)` → `{ source, receveur, source_epuisee,
  quantite }`. `taux` est DÉJÀ RÉSOLU par l'appelant : ce fichier ne connaît
  aucun nom de propriété de domaine, seulement des noms de RÉSERVE.
- **CONSERVATIF PAR CONSTRUCTION** (bug fermé) : le receveur est crédité de
  la quantité RÉELLEMENT retirée, jamais de la quantité DEMANDÉE — la somme
  source + receveur est invariante quels que soient le taux et le delta.
  Ne PAS reproposer un pré-bornage côté appelant : le mécanisme s'en charge.
- **`source_epuisee` est un ÉTAT**, vrai dès que la réserve EST à zéro, pas
  seulement un événement du tick. Une réserve jamais existante rend `false`.
- **Ne transforme JAMAIS l'objet source** : il calcule un flag, c'est au
  câblage d'appeler `produit.gd` quand il est vrai.
- **Fonctionne avec la MÊME entité en source ET en receveur**, tant que les
  clés de réserve diffèrent : aucun aliasing.

### `scripts/reaction.gd` — paires réactives + chaînage par profondeur
- **Rôle** : détecte, parmi les objets d'un monde à plat, les paires à portée
  correspondant à une entrée de catalogue, accumule un canal `charge.gd`
  dédié sur chaque paire, et transforme la CIBLE au franchissement. Compose
  `charge.gd`/`produit.gd`/`portee.gd`, n'en réimplémente aucun.
- **Modèle ASYMÉTRIQUE** : le premier matériau est source/catalyseur — JAMAIS
  transformé ; le second est la cible — seule transformée.
- **Chaînage PAR LE TEMPS, jamais par une boucle interne** : deux passes
  disjointes (détection sur l'état du DÉBUT de l'appel, puis application) —
  un objet transformé pendant cet appel n'est jamais relu comme réactif frais
  dans le MÊME appel. Il ne redevient réactif qu'au tick suivant.
- **Profondeur de chaîne**, seule protection contre les boucles infinies : un
  objet au-delà du maximum est exclu de toute détection, source ou cible. Le
  produit reçoit `max(profondeurs contributrices) + 1`, jamais posée à la main.
- **Refusionne la réactivité sur le produit** : `produit.gd` ne relaie jamais
  les propriétés immuables — sans ce geste, tout chaînage à plus d'un étage
  serait structurellement impossible.
- **Apparie par MATÉRIAU et scie une propriété FIGÉE** : rendre ce nom
  paramétrable toucherait le cœur. Un gate de contact entre deux objets qui
  doit scorer une AUTRE propriété se câble à la main.

### `scripts/comptage.gd` — 1ʳᵉ brique de la couche « lecteur »
Compte, sur une liste DÉJÀ CONSTRUITE par l'appelant, combien d'entités
satisfont une règle exprimée en donnée — un fait collectif est un résumé LU,
jamais un objet-groupe. `compter(entites, regle_id, catalogue) -> int`.
Contrat, quatre modes et limites : en-tête du fichier. Test :
`test_comptage.gd`.

### `scripts/somme.gd` — 2ᵉ brique de la couche « lecteur »
`comptage.gd` rend COMBIEN D'ENTITÉS satisfont une règle (`int`) ; celui-ci
rend COMBIEN AU TOTAL une liste porte d'une grandeur (`float`). Deux
questions, deux fichiers. `reserves(entites, nom_reserve)` (lecture profonde)
et `propriete(entites, nom_propriete)` (lecture plate). Contrat : en-tête du
fichier. Test : `test_somme.gd`.

### `scripts/champ.gd` — force générique à portée (déplace les objets)
- **Rôle** : PREMIER mécanisme du cœur qui écrit `position` HORS d'une
  décision d'agent. Magnétisme, explosion, vent, gravité sont la MÊME loi
  paramétrée ; aucun nom de phénomène n'apparaît ici. Deux choses portant
  chacune une intensité non nulle pour la même entrée s'attirent ou se
  repoussent, par PAIRES (une seule application par paire).
- **Fonctions** : `avancer(monde, delta, catalogue={}, materiaux={})` → ids
  déplacés ; `force_paire(...)` — lecture seule, MÊME calcul interne, pour
  l'observabilité d'un banc.
- **MUTATION EN PLACE** : le déplacement est SUBI, jamais décidé — à
  l'opposé d'un mouvement d'agent, qui REND une position à un appelant.
- **DEUX RÔLES DISTINCTS, jamais confondus** : la QUANTITÉ DE MATIÈRE attire
  (EXTENSIVE, somme pondérée par volume — un objet deux fois plus gros
  contient deux fois plus de matière et subit deux fois la force) ; la MASSE
  résiste (accélération inversement proportionnelle). La densité effective
  reste une MOYENNE parce qu'elle est INTENSIVE.
- **LOI** : produit des deux quantités (forme mutuelle standard) — si l'un
  des deux est nul, la paire l'est aussi, ce qui rend « objet sans la
  propriété, ni source ni cible » vrai sans code spécial. Distance bornée par
  un plancher, force nulle au-delà de la portée, déplacement borné par un
  plafond FLAT (jamais mis à l'échelle du delta : un grand delta atteint ce
  plafond plus tôt et AFFAIBLIT donc la traction relative).
- **Entrée de catalogue STRUCTURELLE** : un champ requis absent → alarme,
  entrée entière ignorée ce tick, jamais un défaut inventé qui simulerait une
  loi physique. Toute clé commençant par `_` est ignorée à l'itération.
- **Frontière avec `fuite.gd`** : celui-ci ne décide rien et rend une
  DIRECTION consommée par un mouvement d'agent ; `champ.gd` déplace lui-même.

### `scripts/velocite.gd` — dérivation passive d'une vélocité
La différence entre deux positions devient une vélocité lisible, une fois par
tick. `avancer(monde, delta)`. Contrat, pièges et frontières : en-tête du
fichier. Test : `test_velocite.gd`.

### `scripts/quantite_matiere.gd` — quantité sommée sur une composition
Une composition rend le total d'une propriété matériau, pondéré par volume.
`quantite(proprietes, propriete_materiau, materiaux)`. Contrat, pièges et
frontières : en-tête du fichier. Test : `test_quantite_matiere.gd`.

### `scripts/combustible.gd` — lecture du rendement d'une réserve
Une réserve nommée rend ce qui lui reste, en absolu et en proportion de sa
capacité. `restant(chose, nom_reserve)`. Contrat, pièges et frontières :
en-tête du fichier. Test : `test_combustible.gd`.

### `scripts/monde.gd` — requête spatiale
Le contenant réellement utilisé en jeu : il rend les choses dans un rayon, et
une chose par son id. `ajouter`, `par_id`, `choses_dans_rayon`. Contrat,
pièges et frontières : en-tête du fichier. Test : `test_monde.gd`.

### `scripts/etat_effectif.gd` — un état écrase ou module une propriété
Les états actifs d'une chose écrasent ou multiplient la valeur de base d'une
propriété. `valeur(...)`, `resoudre(...)`. Contrat, pièges et frontières :
en-tête du fichier. Test : `test_etat_effectif.gd`.

### `scripts/etat_duree.gd` — un état a une intensité qui décroît
Un état porte une intensité qui s'épuise, et se retire lui-même à zéro.
`poser`, `avancer`, `etats_ponderes`. Contrat, pièges et frontières : en-tête
du fichier. Test : `test_etat_duree.gd`.

### `scripts/vent.gd` — direction et force du vent
Le vent souffle à une position et à un instant, et allonge ou réduit une
portée selon l'angle. `vecteur(...)`, `facteur_directionnel(...)`. Contrat,
pièges et frontières : en-tête du fichier. Test : `test_vent.gd`.

### `scripts/temperature.gd` — température tirée vers une température locale
Des sources font une température locale, et chaque chose la rejoint d'autant
plus lentement qu'elle emmagasine — en se dilatant. `locale(...)`,
`avancer(...)`. Contrat, pièges et frontières : en-tête du fichier. Test :
`test_temperature.gd`.

### `scripts/seuil_etat.gd` — seuil d'état réversible sur une propriété
Une propriété continue franchit un seuil et pose — ou retire — un nom d'état.
`avancer(monde, catalogue)`. Contrat, pièges et frontières : en-tête du
fichier. Test : `test_seuil_etat.gd`.

### `scripts/soudure.gd` — fusion irréversible de deux objets
Deux objets physiques n'en font plus qu'un, composition concaténée et
propriétés immuables refabriquées. `fabriquer_composite(...)`, `souder(...)`.
Contrat, pièges et frontières : en-tête du fichier. Test : `test_soudure.gd`.

### `scripts/frappe.gd` — événement ponctuel par sélection
Un événement choisit une cible par score composite, puis lui retire une
quantité d'une réserve. `selectionner(...)`, `frapper(...)`. Contrat, pièges
et frontières : en-tête du fichier. Test : `test_frappe.gd`.

### `scripts/bifurcation.gd` — sélection d'une sortie parmi N
Un biais individuel et une grandeur de situation élisent une sortie parmi
celles déclarées en donnée. `selectionner(...)`, `resoudre(...)`. Contrat,
pièges et frontières : en-tête du fichier. Test : `test_bifurcation.gd`.

### `scripts/lumiere.gd` — lumière ambiante à deux composantes
Des sources dispersées et un soleil font, en un point, une intensité et une
température de couleur. `locale(...)`, `avancer(...)`, `soleil(...)`.
Contrat, pièges et frontières : en-tête du fichier. Test :
`test_lumiere.gd`.

### `scripts/ecoulement.gd` — transfert conservé pair-à-pair
Deux voisins comparent leur hauteur, et le plus haut vide une réserve dans le
plus bas. `avancer(cases, rayon_voisinage, nom_reserve, nom_altitude, taux,
delta)`. Contrat, pièges et frontières : en-tête du fichier. Test :
`test_ecoulement.gd`.

### `scripts/sandpile.gd` — transfert DISCRET conditionné par pente critique
Deux voisins comparent leur hauteur ; si l'écart dépasse strictement un seuil,
UN grain entier passe du haut vers le bas. Sous le seuil, rien. Neuvième
nature de mécanisme (taxonomie de `ecoulement.gd`) : granularité entière +
seuil, là où `ecoulement.gd` est fluide continu sans seuil. Modèle
Bak-Tang-Wiesenfeld, angle de repos naturel. `avancer(cases, rayon_voisinage,
nom_reserve, nom_altitude, seuil_pente)`. Chaque paire non ordonnée évaluée
UNE fois par tick (jamais `(j, i)` après `(i, j)` — sinon oscillation).
Contrat, pièges et frontières : en-tête du fichier. Test : `test_sandpile.gd`.
ÉCART FRAMEWORK : présent dans le dépôt orion, ABSENT de la copie locale
`scripts/` de ce dépôt.

### `scripts/occlusion.gd` — géométrie d'occlusion partagée
Ce qui se dresse entre deux points atténue ce qui les relie, et une force
décroît en puissance inverse de la distance. `facteur(...)`,
`attenuer_par_distance(...)`. Contrat, pièges et frontières : en-tête du
fichier. Test : `test_occlusion.gd`.

### `scripts/champ_occulte.gd` — champ atténué par distance ET obstacles
Des sources dispersées font une intensité en un point, réduite par ce qui se
dresse entre elles et lui. `intensite_locale(...)`. Contrat, pièges et
frontières : en-tête du fichier. Test : `test_champ_occulte.gd`.

### `scripts/conditions.gd` — évaluateur multi-conditions REJOUABLE
N conditions en ET sur N propriétés posent — et retirent — un Dictionary de
propriétés, à chaque tick. `remplies(...)`, `evaluer(proprietes, catalogue,
retirer_si_faux=false)`. Contrat, pièges et frontières : en-tête du fichier.
Test : `test_conditions.gd`.

### `scripts/horloge.gd` — heure du jour et saison
Un temps écoulé rend l'heure du jour et le nom de la saison courante.
`heure(...)`, `saison(...)`. Contrat, pièges et frontières : en-tête du
fichier. Test : `test_horloge.gd`.

### `scripts/memoire_spatiale.gd` — souvenir de POSITION, décroissant
Un percevant retient où il a vu une chose, et relit ce souvenir dévié plutôt
que le réel. `memoriser`, `avancer`, `position_memorisee`. Contrat, pièges et
frontières : en-tête du fichier. Test : `test_memoire_spatiale.gd`.

### `scripts/tick.gd` — framework de tick modulable
Décide QUAND avancer une entité et AVEC QUEL profil, puis délègue le pas à
`mouvement_kinematic.gd`. Offre plusieurs politiques (`politique_intrinseque`
pour un monde émergent à temps uniforme ; `politique_distance` pour un jeu
action centré sur un point chaud ; `politique_groupe` pour tests/debug/cinématiques)
et laisse l'appelant choisir. Une politique est un `Callable` déjà lié par
l'appelant, jamais recalculé ici (patron `boucle.gd`). Contrat, pièges et
frontières : en-tête du fichier. ÉCART FRAMEWORK : présent dans cette copie
locale de `scripts/`, ABSENT du dépôt orion.

### `scripts/mouvement_kinematic.gd` — mouvement kinématique en donnée pure
UNE implémentation partagée de la gravité, du blocage terrain, du snap au sol
et de la collision inter-entités pour tout mobile du monde (joueur, cubes,
producteurs...). Agnostique du type : ne connaît ni « joueur », ni « cube »,
ni « mur » — ne lit que des propriétés. Le profil (`complet`/`simple`/`minimal`)
choisit la RICHESSE de la simulation, jamais l'identité du mobile.
`pas(entite, delta, monde, carte, profil)` avance UNE entité en donnée pure ;
l'appelant POSE l'intention (velocité horizontale désirée, saut demandé) dans
l'entité avant l'appel. Aucun `Input` lu ici. Contrat, contrat d'entité, pièges
et frontières : en-tête du fichier. ÉCART FRAMEWORK : présent dans cette copie
locale de `scripts/`, ABSENT du dépôt orion.

### `scripts/mesh_catalogue.gd` — résolveur de meshes déclarés en donnée
Lit `data/mesh.json` et rend un `Mesh` Godot depuis une fiche { `type`, +
champs de la famille }. Ne parle que de FAMILLES GÉOMÉTRIQUES (`boite`
aujourd'hui), aucun nom de contenu. Une famille de plus = un `case` de plus
dans `fabriquer_mesh`, zéro ligne à toucher chez les consommateurs
(`peuplement.gd` et autres). `charger()`, `fabriquer_mesh(fiche)`. Aucun cache
interne, aucune allocation de MultiMesh, aucune instance
`RenderingServer`. Contrat, pièges et frontières : en-tête du fichier. ÉCART
FRAMEWORK : présent dans cette copie locale de `scripts/` + `data/`, ABSENT du
dépôt orion.

### `scripts/peuplement.gd` — rendu MultiMesh + tick partagé pour population homogène
Fondation des populations mobiles massives (canevas CLAUDE.md « POPULATIONS
MASSIVES »). UN Node qui tient un `Array` d'individus itéré en UNE boucle
`_physics_process`, UN MultiMesh + UNE instance `RenderingServer` directe qui
rend en UN draw call. Aucun Node ni Timer par individu. UN peuplement = UN
type = UN MultiMesh (`type_id` figé à la première fabrication) ; un banc qui
veut plusieurs meshes instancie plusieurs peuplements. Pool de slots fixe, LIFO,
slots inactifs à échelle NULLE (jamais `Transform3D()` identité qui rendrait
un mesh à l'origine). Ne connaît aucun nom de contenu — `type_id` et `mesh_ref`
opaques, résolus via `objet.gd:fabriquer` et `mesh_catalogue.gd`. Contrat,
pièges et frontières : en-tête du fichier. ÉCART FRAMEWORK : présent dans cette
copie locale de `scripts/`, ABSENT du dépôt orion. `set_cast_shadow(pool, actif)`
bascule les ombres du MultiMesh entier en un seul appel `RenderingServer.instance_geometry_set_cast_shadows_setting` — outil DIAGNOSTIC pour
mesurer le poids du rendu shadow sur le plafond FPS à N élevé, pas une
proposition d'optimisation. Profil scaling du pipeline
(phases A/B/C par individu à N ∈ {100, 500, 1000, 2000, 5000}) :
`scripts/test_profil_peuplement.gd`. Micro-profil de la Phase B décomposée
en B1 (dispatch Tick), B2 (`Mouvement._pas_simple`), B3 (`monde.deplacer`),
à N ∈ {1000, 5000} : `scripts/test_profil_phase_b.gd`. Sous-profil de B2
décomposé en B2.1 (gravité + composition), B2.2 (les 2 `sommet_sous` de S.6),
B2.3 (comparaison de blocage), B2.4 (application + snap sol + écriture),
à N ∈ {1000, 5000} : `scripts/test_profil_pas_simple.gd`.

### `jeu/Proto/collision.gd` — système de collision généraliste, donnée pure (prototype)
Tout statique, aucun état interne. Aucune physique Godot
(`PhysicsServer3D`/`StaticBody3D`/`CollisionShape3D`) : une forme est un
`Dictionary`, une entité est un `Dictionary`, la collision se calcule sur ces
données, hors rendu comme dans le rendu. Système complet : SUPPORT unifié, AABB
par forme, GJK, EPA, `tick` (broadphase `monde.gd` + narrowphase + swept),
`resoudre` (séparation en donnée pure). Quatre types de forme : `sphere`,
`boite`, `capsule` (axe Y), `hull`. Le dispatch par type vit UNIQUEMENT dans
`_support_local` — cinquième type = un `case` de plus, rien d'autre ailleurs.
`transform_monde` reçu par `support`/`aabb_forme` est COMPLET (l'appelant
compose déjà `Transform3D(orientation, position) * transform_locale`). Contrat
de forme et pièges : en-tête du fichier. VIT DANS `jeu/`, pas dans `scripts/` :
c'est un proto jeu candidat à devenir un mécanisme framework.

---

## 3. Les câblages de banc

### `scripts/banc_p1.gd`

Scène principale du projet (`Scene/banc_p1.tscn`, `data/banc_p1.json`). Un
`Node2D` qui CÂBLE les couches et traduit la décision en image.

**TOUS LES BANCS SONT JETABLES PAR DÉFINITION** — aucune règle de jeu ne doit
y vivre. Conventions valables pour les 105 suivants, et non répétées à chaque
section : chacun est une scène SÉPARÉE qui coexiste avec les autres, la scène
principale restant `banc_p1.tscn` ; chacun charge son propre
`data/banc_*.json` dans son `_ready` ; chacun peut NOMMER une catégorie pour
poser une scène d'observation (exception de `CLAUDE.md`, ce nommage ne
survit jamais dans le moteur permanent) ; la logique enfermée dans `_process`
ou `_unhandled_input` en sort en fonction statique testable, le clic ou la
boucle ne faisant que déclencher.

**CLAUDE N'A NI ÉCRAN NI SOURIS** : aucun rendu d'aucun banc n'est vérifié
visuellement, et aucun clic n'est jamais exercé en headless — ce qui dépend
d'une bascule au clic n'est prouvé que par son test. Ce qui doit être
confirmé à l'œil vit dans `docs/prototypes.md`, jamais ici.

**Montre** : le pipeline complet à QUATRE couches sur des colons réels, plus
la propagation du feu, l'extinction par le travail, et l'occupation d'un
chantier. Clic gauche allume un feu ; la touche `M` pose un bloc cassable.

**Deux moitiés** :
- **Node (impur)** : `_ready` charge les données et fabrique le monde,
  `_unhandled_input` allume, `_process` fait avancer propagation et
  extinction puis chaque colon, gère le rendu et la console. Le monde est une
  instance de `Monde` : une seule écriture, et les mécanismes qui attendent un
  Array nu le reçoivent aplati, mêmes références — aucune copie.
- **Fonctions statiques (pures, testables headless)** : `decider` (les quatre
  étapes, jamais de jugement) ; `decider_et_memoriser` (enveloppe qui écrit
  `action_en_cours` — sans cet appel, `gain_inertie` reste sans effet malgré
  des données non nulles) ; `agir_et_deplacer` (LE GESTE COMPLET
  décision → mouvement, branche fuite comprise, appelé aussi par la boucle de
  test : un seul chemin de code pour le jeu et pour un test dynamique) ;
  `cible_pour_decision`/`feu_le_plus_proche` (retrouvent OÙ aller, puisque la
  couche attache ne rend qu'un nombre) ; `mettre_a_jour_occupation`.
- **OCCUPATION, DÉTECTION PAR POSITION et jamais par `action_en_cours`** —
  essayé puis corrigé : une chose gelée n'étant plus saillante pour son
  occupant non plus, sa décision devient `null`, ce qui viderait son
  `action_en_cours` au tick suivant et ferait CLIGNOTER l'occupation à chaque
  tick. Une chose occupée reçoit un marqueur et PERD son profil de saillance
  (gelé sous une autre clé, jamais perdu) : plus aucun colon ne la vise, sans
  qu'une ligne du cœur ne le sache. Restauré à l'identique dès qu'aucun agent
  n'est à portée — SAUF si le chantier s'est achevé entre-temps : la chose
  reste alors inerte pour de bon, comme une cendre, jamais ressuscitée.
- **ENGAGEMENT** : posé dès que le colon est physiquement à portée de travail
  d'un chantier, retiré si la décision change de cible. Ferme le bug
  d'oscillation sur un chantier lent, verrouillé par un test intégrateur sur
  un colon PLACIDE (inertie nulle : la personnalité ne peut pas expliquer le
  résultat).

**Testé par** : `scripts/test_banc_p1.gd`.

---

### `scripts/banc_animal.gd`

**Montre** : `flux.gd` et `depense.gd` jouant ensemble sur un animal
photosynthétique qui se déplace vers ce dont il manque.

**Compose** : `flux.gd`, `depense.gd`, `couplage.gd` — tous inchangés.

**Fonction propre** : `cible_besoin` — retrouve OÙ aller en pilotant
l'engagement générique au passage. L'HYSTÉRÉSIS est propre à ce banc, jamais
un mécanisme de `couplage.gd` : elle compare la pire réserve courante au
canal engagé et relâche si l'écart dépasse un seuil. Générique à N réserves :
ni le mécanisme ni le banc ne nomment jamais une réserve en dur.

**Testé par** : `scripts/test_banc_animal.gd`.

---

### `scripts/banc_feu.gd`

**Montre** : la BASCULE INDIVIDUELLE. Deux colons, mêmes couches, seul leur
`gain_jugement` diffère — à mesure que le nombre de feux monte, le peureux
quitte l'extinction pour l'abri pendant que le prudent éteint encore.

**PREMIER câblage réel à faire entrer `jugement.gd` dans un `decider()`** :
cinq étapes au lieu de quatre. Le jugement lit la couche 2 AVANT lui-même, et
son résultat la rejoint ENSUITE, avant dominance.

**Compose** : les quatre couches plus `jugement.gd`, `extinction.gd` —
inchangés. Pas de propagation : rien d'inflammable ici en dehors du feu.

**Décisions** : aucun colon ne porte d'attache, donc la chose ciblée porte
TOUJOURS une identité et le ciblage par menace est inutile — non dupliqué.
Le profil de saillance est retiré localement sur chaque colon : le sujet est
la bascule individuelle sous exposition identique, une convergence
colon-vers-colon serait du bruit.

**Testé par** : `scripts/test_banc_feu.gd`.

---

### `scripts/banc_commun.gd`

**Pas un banc** : ni scène, ni `_ready`, ni `_process`. Câblage PARTAGÉ et
éprouvé, jamais un mécanisme du cœur — elle ne porte pas COMMENT un mécanisme
fonctionne, mais comment un banc l'invoque en pratique. Elle ne s'ajoute pas
à la liste des mécanismes de §2.

**EXCEPTION assumée** : `propagation.gd` (mécanisme du cœur) la précharge et
appelle son geste de pose de chantier. Il portait auparavant sa PROPRE copie
du même geste, avec le même bug d'aliasing ; plutôt que corriger deux fois,
il appelle l'unique version.

**Les dix outils** : construire un Monde depuis les listes que le câblage
tient déjà (`monde_depuis` — SEULE façon pour un banc d'en obtenir un) ;
aplatir un monde en Array nu (mêmes références) ; poser
sur une chose les clés d'un patron qu'elle n'a pas déjà, AU GRAIN DE LA
SOUS-CLÉ (deux Dictionary se traversent : un conteneur déjà présent reçoit la
sous-clé qui lui manque, il n'est jamais sauté en bloc) ; dériver les agents
d'extinction ; marquer les choses éteintes ; fabriquer un colon ; déplacer
VERS une cible ou SELON une direction ; filtrer ce qu'il faut fuir (en
résolvant le verbe pour CETTE SEULE entrée) ; résoudre le verbe affiché
depuis le chantier de la chose ciblée, jamais un rayon en dur.

**Le CRITÈRE D'ENTRÉE et le REGISTRE vivent dans l'en-tête du fichier**, pas
ici : statique (aucun état retenu), autonome (précharge des mécanismes du
cœur, jamais un banc ni un autre outil), paramétré par donnée. La NOTICE
D'EXTENSION y fixe quatre pas obligatoires pour qui ajoute un outil.

**PIÈGE, à connaître de tout câblage** : `agents_rythme` lit le rythme BRUT.
Un état qui prétendrait le moduler serait vrai en donnée et sans le moindre
effet, EN SILENCE — un banc qui veut un rythme effectif doit composer
`etat_effectif.gd` lui-même.

**Testé par** : `scripts/test_banc_commun.gd` (les dix outils isolément, plus
un VERROU NÉGATIF : hors de cette boîte, plus aucun `banc_*.gd` n'a le droit
d'instancier `Monde` ailleurs qu'en déclaration de champ) et
`scripts/test_registre_banc_commun.gd` (le registre ne dérive pas du code).

---

### `scripts/banc_charge.gd`

**Montre** : PREMIER câblage réel de `charge.gd`. Deux colons, seul le SEUIL
de leur canal de peur diffère : un état interne monte tant qu'un feu est à
portée, franchit, pose un marqueur, redescend et le retire en son absence.

**Le problème résolu par ce câblage** : la pression du jugement se somme sur
les choses PERÇUES portant le déclencheur — or ici le déclencheur est porté
par le colon LUI-MÊME. Il faudrait qu'il se perçoive, ce que l'auto-exclusion
interdit en permanence au niveau du cœur, et un colon saillant à ses propres
yeux serait candidat de sa propre décision sans propriété actionnable : il se
figerait. La solution est un array SÉPARÉ passé au seul jugement, jamais
mélangé à ce qui va vers dominance. `jugement.gd` n'est pas touché.

**Compose** : les cinq couches (jugement inclus) plus `charge.gd`.

**Décision** : le canal complet vit sur le type partagé ; seul le seuil est
surchargé par colon, canal par canal, sans jamais écraser le reste hérité ni
partager le même Dictionary entre deux colons.

**Testé par** : `scripts/test_banc_charge.gd`.

---

### `scripts/banc_deformation.gd`

**Montre** : PREMIÈRE SOURCE RÉELLE de `deformation.gd`. Deux colons
identiques à la naissance, seule leur POSITION diffère : l'un reste à portée
de vue d'un feu stationnaire, l'autre non — leurs registres divergent.

**Compose** : `perception.gd`, `deformation.gd`. La pose vient d'une
perception RÉELLE, jamais d'une distance recalculée en dur.

**PORTÉE VOLONTAIREMENT LIMITÉE** : ce banc ne route RIEN par les couches de
saillance ni par la décision — il n'a ni `decider` ni déplacement. La lecture
du biais par une couche est démontrée ailleurs, par un test dédié.

**Testé par** : `scripts/test_banc_deformation.gd`.

---

### `scripts/banc_lien_personnel.gd`

**Montre** : la chaîne complète du lien personnel — un acte répété crée un
lien vers une chose précise, ce lien rend saillant ce qui s'en approche, et
au bout de plusieurs choses vécues il CRISTALLISE en attache générale sur le
trait. Trois pompiers aux seuils différents cristallisent à des rythmes
différents sous exposition identique ; un spectateur hors de portée n'en
développe aucun.

**Compose** : les quatre couches, plus `lien_personnel.gd`, son bonus de
saillance, son attraction, `attache_par_trait.gd`, `couplage.gd`,
`propagation.gd`, `extinction.gd`, `depense.gd` — tous inchangés. C'est le
passage par `agir.gd` qui est le point : le lien ne peut recevoir son
événement que par l'effet de bord ACTES LIANTS.

**PIÈGE MESURÉ, fermé** : le bonus de lien déjà accumulé sur une défense rend
celle-ci de plus en plus saillante et VERROUILLE le colon dessus pour
toujours — aucune nouvelle défense, même perçue, ne peut plus la détrôner. Le
test relocalise donc chaque défense hors de portée une fois sa phase finie.

**Décisions** : chaque feu allumé au clic porte le trait d'ouvrage et devient
candidat à son PROPRE lien, par le même mécanisme générique — plusieurs liens
simultanés sans qu'une ligne du banc ne le sache. La bâtisse ne porte PAS de
vulnérabilité : elle démarre en feu et doit RESTER éteinte une fois sauvée,
sinon un feu voisin la rallume cycliquement jusqu'à consumption.

**Testé par** : `scripts/test_banc_lien_personnel.gd`.

---

### `scripts/banc_comptage.gd`

**Montre** : PREMIER câblage réel de `comptage.gd`. Six lucioles dont l'état
bascule au hasard SEEDÉ ; le compte et sa moyenne glissante sont recalculés
à chaque tick, jamais stockés sur un objet-nuée.

**HORS DOMAINE STRICT** : ne touche ni aux colons ni à aucun contenu du jeu.
Il ne prouve PAS la croyance collective, seulement le câblage de la brique.

**Décision, tension trouvée au premier lancement** : le mode de présence
teste `.has()`, jamais la valeur — une luciole qui porterait un booléen
TOUJOURS présent aurait figé le compte au maximum en toute circonstance. Une
luciole éteinte porte donc des propriétés VIDES, même convention que
« extinction = retrait de propriété, jamais mutation de type ».

**La moyenne glissante est une composition du BANC**, jamais du mécanisme.

**Testé par** : `scripts/test_banc_comptage.gd`.

---

### `scripts/banc_convergence_attache.gd`

**Montre** : `comptage.gd` sur des colons réels — plusieurs colons forment
INDIVIDUELLEMENT une attache au même trait, et le compte rend à la demande un
FAIT COLLECTIF, jamais porté par un objet-groupe.

**CÂBLAGE DIRECT, sans pipeline de décision** : le lien est posé dès qu'un
colon perçoit une chose portant le trait, jamais via l'effet de bord de
`agir.gd` (qui exigerait une décision résolue en verbe, inutile ici).

**RÉGRESSION TROUVÉE ET CORRIGÉE avant ce banc** : une règle de généralisation
ajoutée au catalogue PARTAGÉ sur un trait très répandu s'est déclenchée sur
les objets d'un AUTRE banc qui portaient aussi ce trait, faussant son rythme.
Les règles propres à un banc restent dans son fichier.

**Portée limitée** : le fait collectif est PRODUIT, jamais CONSOMMÉ par une
décision.

**Testé par** : `scripts/test_banc_convergence_attache.gd`.

---

### `scripts/banc_contagion.gd`

**Montre** : PREMIÈRE fermeture de la boucle lecteur agrégé → décision. Un
fait collectif (des voisins portent une attache) alimente un canal de charge
sur le corps interne d'un colon, franchit un seuil et pose une propriété
interne.

**COMPTAGE IMPLICITE, sans appeler `comptage.gd`** : `charge.gd` boucle déjà
sur les causes, teste la portée et SOMME les poids. Construire une cause par
voisin porteur revient à compter — le compte émerge de la somme.

**Fonction propre** : construit les causes en filtrant sur une attache (qui
vit dans un Array), là où le banc de peur filtrait une propriété plate.
L'auto-exclusion vit dans CE câblage : `charge.gd` ne sait pas qui pose la
question.

**Testé par** : `scripts/test_banc_contagion.gd`.

---

### `scripts/banc_vecu_inter_colon.gd`

**Montre** : la CONTAGION CULTURELLE. Deux colons qui se perçoivent
mutuellement cristallisent chacun une attache au trait que l'autre porte ; un
troisième, d'identité opposée, arrive plus tard et se laisse absorber SANS
jamais perdre son identité d'origine — les attaches se cumulent, ne
s'effacent jamais.

**Compose** : `perception.gd`, `lien_personnel.gd`, sa croissance,
`attache_par_trait.gd`. Aucune décision.

**Décisions** : la portée d'écoute est une surcharge d'UNE SEULE sous-clé du
Dictionary de canaux — jamais un remplacement du tout, qui effacerait
silencieusement les cinq autres canaux. Le point d'arrêt du troisième colon
est PRÉCALCULÉ en donnée pour respecter à la fois la distance
d'anti-chevauchement et la portée d'écoute : aucun calcul de ralentissement à
l'exécution.

**Testé par** : `scripts/test_banc_vecu_inter_colon.gd`.

---

### `scripts/banc_genetique.gd`

**Montre** : PREMIER câblage réel d'`expression.gd` — la fondation génétique
produit un TRADE-OFF observable, pas un classement. Trois colons, mêmes
attaches et même forme : seule la génétique diverge.

**Un seul gène, TROIS cibles à la fois** : portée de vue et vitesse (positifs)
et le COÛT de la réserve d'énergie (positif AUSSI — cibler le stock n'aurait
baissé la réserve qu'UNE FOIS, à la fabrication ; c'est le TAUX lu chaque
tick qui doit monter pour produire « consomme plus vite »).

**CONSTAT GÉOMÉTRIQUE, à ne pas reperdre** : l'ordre de PERCEPTION n'est PAS
mécaniquement démontrable avec un feu et des colons statiques — pour que le
colon à la portée la plus courte perçoive un jour, le feu doit être à une
distance que les trois couvrent, donc les trois perçoivent au même tick.
Seuls l'ARRIVÉE et l'ÉPUISEMENT sont réellement ordonnés.

**RISQUE DORMANT, non corrigé** : les colons héritent un profil de saillance
et ne s'empilent pas au repos par ACCIDENT DE POSITION, pas par garde. À
corriger si les positions se rapprochent.

**Testé par** : `scripts/test_banc_genetique.gd`.

---

### `scripts/banc_reproduction.gd`

**Montre** : PREMIÈRE FERMETURE DU CYCLE COMPLET — stade, accouplement,
gestation, hérédité et fabrication tournent ENSEMBLE pour la première fois,
et un enfant est réellement fabriqué.

**Compose** : les cinq mécanismes du cycle, inchangés. Aucune décision, aucun
déplacement : deux colons immobiles qui se perçoivent.

**AUCUN PORTEUR N'EST DÉSIGNÉ ICI** : `avancer_cycle` boucle sur tous les
colons sans en distinguer aucun, la donnée ayant déjà tranché en amont.

**CLÔTURER, JAMAIS SEULEMENT EFFACER LA GESTATION** (`cloturer_gestation`) :
l'accumulateur d'accouplement ne décroît jamais, donc rester plein chez le
partenaire suffit à faire pondre le couple en rafale, sans trace.

**Décision** : les deux parents sont HOMOZYGOTES opposés, donc le tirage rend
toujours le même couple d'allèles avant mutation : l'enfant naît exactement
entre ses deux parents, sauf l'effet rare d'une mutation.

**Testé par** : `scripts/test_banc_reproduction.gd`.

---

### `scripts/banc_controle.gd`

**Montre** : PREMIÈRE FONDATION DU CONTRÔLE DIRECT DU JOUEUR. Un golem qui
OBÉIT et un colon qui DÉCIDE SEUL, dans la même scène. La différence vit
ENTIÈREMENT en donnée : ce fichier est le seul à lire la clé de contrôlabilité.

**AUCUN mécanisme du cœur nouveau ni touché** : trois clés neutres sur le
paquet dynamique et un patron de câblage.

**Poser un ordre est un geste SÉPARÉ d'obéir** : l'ordre s'écrit SANS jamais
vérifier la contrôlabilité — c'est à la LECTURE que la garde tranche. C'est
ce découplage qui rend testable « un ordre posé sur un colon ne produit
jamais de mouvement ».

**Le golem ne compose ni perception ni décision** : il ne réagit jamais au
feu, structurellement — `perception.gd` n'a rien à lui offrir.

**Coût énergétique** : surcoût STATIQUE, appliqué tout le temps qu'une entité
EST contrôlable, ponctionné par `depense.gd` sans aucun câblage neuf.

**Testé par** : `scripts/test_banc_controle.gd`.

---

### `scripts/banc_champ.gd`

**Montre** : PREMIER câblage réel de `champ.gd`. Un golem contrôlable au clic
approche d'un aimant fixe ; près du point de bascule, la traction l'emporte
sur le pas volontaire.

**RÉUTILISATION, PAS RECRÉATION** : le contrôle est repris TEL QUEL du banc
précédent, jamais réécrit. Ce fichier n'ajoute qu'une étape après le pas
volontaire.

**LA DOMINATION ÉMERGE D'UNE SUCCESSION, jamais d'une fusion de contrat** :
pas volontaire PUIS déviation subie, dans le même tick — aucune branche « si
dominé » nulle part. Les fonctions de déplacement restent inchangées.

**COLLISION FERMÉE AVEC LE LINTER** : une table de matériaux LOCALE a été
essayée puis refusée — le linter valide tout champ `materiau` de n'importe
quel `data/*.json` contre le catalogue partagé, sans notion de table locale.
Les deux matériaux ont donc rejoint le catalogue partagé, en restant dans
l'échelle documentée.

**CALIBRATION À REFAIRE SI LA LOI CHANGE** : quand la force est devenue
proportionnelle au VOLUME et plus au seul degré, les volumes ont dû être
recalculés — le volume comptant désormais deux fois (masse ET force). La loi
et le linter n'ont pas bougé, seule la donnée.

**Testé par** : `scripts/test_banc_champ.gd`.

---

### `scripts/banc_etat_effectif.gd`

**Montre** : PREMIER et SEUL câblage réel d'`etat_effectif.gd`. Quatre objets
côte à côte, une seule propriété, aucun pipeline : un témoin, un écrasé, un
modulé, et un qui porte LES DEUX — ce dernier rend la même valeur que
l'écrasé seul, preuve à l'écran que l'écraseur gagne toujours.

**Une MINUTERIE, pas le clavier** : les états sont posés puis retirés en
boucle, la valeur s'éloigne de sa base puis y revient — jamais figée au
démarrage.

**La console montre POURQUOI, l'écran montre QUE** : la trace lit le détail
de résolution rendu par le mécanisme, jamais une réimplémentation de la loi.

**Testé par** : `scripts/test_banc_etat_effectif.gd`.

---

### `scripts/banc_inflammabilite.gd`

**Montre** : l'inflammabilité EFFECTIVE. Quatre objets, MÊME délai de base et
MÊME portée — seule la matière et l'état expliquent l'écart : un bois pur
s'enflamme vite, un mélange lentement, un fer est sous le seuil, un bois
mouillé est écrasé à zéro. Deux couleurs DIFFÉRENTES pour deux raisons
différentes de blocage.

**Compose** : `objet.gd` (fusion des propriétés immuables) et
`propagation.gd` (délai d'ignition), sans réimplémenter leur loi.

**DÉFAUT RÉEL TROUVÉ EN OBSERVANT L'ÉCRAN, fermé** : le diagnostic rendait la
même sentinelle pour « ne s'enflamme jamais » et « vient de s'enflammer », et
lisait l'exposition VIVE, déjà remise à zéro par le mécanisme au tick de
l'allumage. Les deux sens ont été séparés et le temps réellement mis est
capturé au tick même de l'allumage. Trou de test fermé au passage : la
fonction qui produit le texte affiché n'était appelée par AUCUN test — d'où
la discipline, depuis, de vérifier CE QUI S'AFFICHE et pas seulement le
statut.

**Testé par** : `scripts/test_banc_inflammabilite.gd`.

---

### `scripts/banc_etat_duree.gd`

**Montre** : un état porte une INTENSITÉ qui décroît, pas une simple
présence. Un objet dont l'état expire voit sa barre se vider pendant que sa
valeur effective remonte AU MÊME RYTHME, puis l'état se retire de lui-même ;
un objet dont l'état n'a aucune durée déclarée ne bouge jamais — contraste
épuisable / permanent.

**Compose** : `etat_duree.gd` et `etat_effectif.gd`, ce dernier recevant le
catalogue AJUSTÉ plutôt que le brut : la loi de résolution tourne sans une
ligne changée, sur des nombres déjà pondérés.

**Testé par** : `scripts/test_banc_etat_duree.gd`.

---

### `scripts/banc_combustible.gd`

**Montre** : la réserve de combustible SUIT LA MATIÈRE. Sept objets déjà en
feu, dont l'ordre d'extinction est une conséquence pure de la capacité et du
coût effectif calculés à la fabrication — jamais une durée écrite à la main.
Trois volumes du même bois isolent le VOLUME ; un fer au volume identique
isole le MATÉRIAU ; une paire dense/poreux à CAPACITÉ STRICTEMENT ÉGALE
isole la VITESSE seule — la preuve la plus lisible du chantier.

**Compose** : `objet.gd` (capacité et coût effectif), `combustible.gd`
(lecture), `depense.gd` (consommation) — inchangés, ce dernier consommant la
réserve exactement comme il consommait un forfait avant.

**Décision corrigée** : la capacité venait d'abord de l'inflammabilité —
confusion de grandeurs. Elle vient d'une propriété DÉDIÉE : l'une mesure la
facilité à s'enflammer, l'autre la quantité à brûler, et une paille plus
inflammable que le bois a un pouvoir calorifique bien plus bas.

**Testé par** : `scripts/test_banc_combustible.gd`.

---

### `scripts/banc_emission.gd`

**Montre** : ce qu'une source ÉMET et ce qu'une cible ACCEPTE sont deux
grandeurs distinctes. Deux feux de volumes différents, quatre cibles à
distance IDENTIQUE : une seule s'enflamme. Les autres prouvent séparément que
la PORTÉE manque (même matière, même distance, source trop petite) et que la
MATIÈRE bloque (aucun des deux feux ne les expose jamais). Aucune distance
n'est écrite en dur — elle résulte de la loi.

**Compose** : `propagation.gd` (émission reçue et seuil d'exposition, en
lecture pure), `objet.gd` — inchangés.

**Testé par** : `scripts/test_banc_emission.gd`.

---

### `scripts/banc_vent.gd`

**Montre** : le vent module la PORTÉE de l'odorat. Un nez immobile au centre,
huit sources en cercle à distance ÉGALE : l'ensemble des sources captées
PIVOTE au fil du temps avec la direction du vent, visible sans lire la
console.

**Compose** : `vent.gd` et `perception.gd` (géométrie directionnelle SEULE)
— inchangés. Le catalogue de vent partagé est chargé RÉEL, jamais surchargé.

**Portée limitée** : aucune source locale de perturbation n'est démontrée ici
(la porte d'entrée existe, aucune source n'est posée) ; la généralisation du
vent aux autres canaux reste un chantier non commencé.

**Testé par** : `scripts/test_banc_vent.gd`.

---

### `scripts/banc_temperature.gd`

**Montre** : la loi de Newton devient observable en approchant un objet
d'une source à la main. Un feu fixe, une source MOBILE qui traverse la scène
(fonction pure du temps, aucun hasard), et un objet déplacé au clavier.

**Compose** : `temperature.gd` — inchangé. C'est CE BANC qui écrit la
position de l'objet chaque tick ; le mécanisme n'avance aucune position.

**Décision** : la conductivité est posée en donnée LOCALE, jamais dérivée
d'une fiche matériau — ce banc n'a aucune composition à résoudre.

**Testé par** : `scripts/test_banc_temperature.gd`.

---

### `scripts/banc_point_ignition.gd`

**Montre** : le gate de température, ISOLÉ du proxy d'intensité. Deux objets
de MÊME matière, MÊME distance de leur propre foyer, MÊME délai — seule la
température locale diverge : l'un s'enflamme exactement au délai de base,
l'autre N'ACCUMULE JAMAIS D'EXPOSITION.

**Compose** : `propagation.gd` et `temperature.gd` (température locale
seule) — inchangés. Le proxy d'intensité n'est volontairement pas fourni,
pour que le blocage observé ne puisse venir que du nouveau gate.

**Testé par** : `scripts/test_banc_point_ignition.gd`.

---

### `scripts/banc_transformation_produit.gd`

**Montre** : une transformation produit un objet NEUF, en CHAÎNE — bois →
charbon → cendre, deux maillons d'affilée, masses exactes aux rendements.

**Compose** : `produit.gd` et `extinction.gd` — inchangés.

**Décision** : l'agent qui mange le chantier n'est PAS un colon —
`extinction.gd` exige des agents à portée, jamais l'auto-consommation. Ce
banc fournit un point collé à l'objet, représentant la combustion se mangeant
elle-même ; sa position ne bouge jamais puisque le produit hérite toujours la
position de l'ancien.

**Testé par** : `scripts/test_banc_transformation_produit.gd`.

---

### `scripts/banc_humidite.gd`

**Montre** : la pose AUTOMATIQUE d'un état par accumulation. Une source
d'humidité togglable expose cinq objets aux mêmes seuils : trois isolent
l'absorption du matériau (le bois mouille vite, la pierre lentement, le fer
quasiment jamais), deux isolent la POROSITÉ à absorption STRICTEMENT ÉGALE
(composition mixte dosée pour ça). Couper la source fait redescendre la
charge vite, mais un objet déjà mouillé sèche PROGRESSIVEMENT.

**Compose** : `charge.gd`, `etat_duree.gd`, `etat_effectif.gd`, `objet.gd` —
tous inchangés.

**UN APPEL À `charge.gd` PAR OBJET CIBLE**, jamais un seul pour tout le monde :
le mécanisme n'a aucun coefficient par receveur, le poids de la cause est donc
pré-multiplié côté câblage par l'absorption de CET objet.

**Le marqueur posé n'est pas l'état** : le canal pose un simple booléen
d'exposition, et c'est le câblage qui repose l'état à chaque tick tant qu'il
reste vrai (remise à un, jamais un cumul). Sans ce détour, le séchage serait
le retrait symétrique INSTANTANÉ du canal au lieu du retrait progressif.

**Testé par** : `scripts/test_banc_humidite.gd`.

---

### `scripts/banc_changement_etat.gd`

**Montre** : un fer FABRIQUÉ PAR COMPOSITION traverse réellement chaud →
liquide → gaz sous une rampe de chaleur, puis repasse dans l'ordre inverse
une fois la source coupée. Sa malléabilité effective monte tant qu'il est
chaud ; sa fluidité ne se lit QUE liquide.

**Compose** : `temperature.gd`, `seuil_etat.gd`, `etat_effectif.gd` — tous
inchangés.

**DEUX DETTES DE DONNÉES FERMÉES EN COURS DE CHANTIER**, sans quoi le
chantier serait invisible sur un objet réellement fabriqué : deux points de
transition et une propriété modulée n'étaient JAMAIS fusionnés à la
fabrication — la base valait donc zéro, et un facteur appliqué à zéro reste
zéro.

**Décision** : la garde « lisible seulement si liquide » vit au CÂBLAGE. Le
mécanisme d'état n'offre qu'écraser (qui perdrait la distinction entre
matériaux) et moduler (qui ne tombe jamais à zéro) : aucun des deux n'exprime
seul cette condition.

**Testé par** : `scripts/test_banc_changement_etat.gd`.

---

### `scripts/banc_soudure.gd`

**Montre** : deux blocs de fer chauffés AU CLIC fusionnent en un seul
composite, masse combinée exacte ; l'objet absorbé devient un fantôme. Un
bois placé à la MÊME distance de contact ne se soude jamais — seule la
matière l'exclut, jamais la mise en scène.

**Compose** : `soudure.gd`, `temperature.gd`, `seuil_etat.gd`, `charge.gd` —
tous inchangés.

**DEUX ÉTAGES, jamais confondus** : DÉTECTION réversible (un canal de charge
monte tant qu'un voisin soudable et chaud est à portée, jusqu'à poser un
marqueur) puis DÉCLENCHEMENT one-shot (la soudure s'exécute une fois que deux
objets portent le marqueur en contact). Souder est IRRÉVERSIBLE : refroidir
retire le marqueur, jamais ne défait un composite.

**QUATRE DÉFAUTS TROUVÉS EN JOUANT, chacun avec sa leçon** :
- Le composite est fabriqué SANS paquets hérités : il perdait sa température,
  et le mécanisme thermique — pour qui cette clé est STRUCTURELLE — alarmait
  à chaque tick, indéfiniment. Corrigé au CÂBLAGE : la température est
  capturée avant la soudure et réappliquée après.
- La charge d'un objet montait dès qu'un VOISIN était chaud, sans vérifier
  qu'il l'était LUI-MÊME. Sous un curseur forcément asymétrique, celui déjà
  chaud voyait sa propre charge gelée pendant que l'autre accumulait grâce à
  lui. Corrigé par une garde : un objet qui n'est pas lui-même chaud ne
  produit aucune cause.
- Une fois fusionné, un objet n'a structurellement plus aucun voisin
  soudable : sa charge retombe à zéro et y reste. Ce n'était pas un bug mais
  un AFFICHAGE trompeur — la ligne de charge disparaît désormais dès que
  l'objet est soudé.
- Trois labels flottants se chevauchaient et les objets ne pouvaient pas être
  éloignés sans casser la démonstration : remplacés par un label unique fixe
  à l'écran.

**Testé par** : `scripts/test_banc_soudure.gd`.

---

### `scripts/banc_dilatation.gd`

**Montre** : deux objets en MIROIR — l'un part froid près d'une source et
GROSSIT, l'autre part chaud hors de portée et RÉTRÉCIT. Même coefficient,
même conductivité, même masse : seule la température diverge. La masse ne
change jamais, la densité reste exactement masse/volume.

**Compose** : `temperature.gd` — inchangé.

**COEFFICIENT DE DÉMONSTRATION, pas la valeur réelle** : la formule est
littérale, sans mise à l'échelle ; les valeurs réelles rendraient le volume
démesuré sur l'écart de température voulu ici. CONSÉQUENCE SIGNALÉE : les
bancs qui chauffent du fer réel sur de larges plages voient désormais leur
volume et leur densité bouger fortement en tâche de fond — non corrigé, hors
périmètre.

**Testé par** : `scripts/test_banc_dilatation.gd`.

---

### `scripts/banc_pourriture.gd`

**Montre** : PREMIÈRE fermeture du patron ACCUMULATION → ÉTAT → DÉGRADATION →
TRANSFORMATION. Un bois exposé à l'humidité pourrit, ses propriétés se
dégradent, puis sa réserve d'intégrité s'épuise et il devient du compost. Une
pierre à sensibilité nulle ne bouge JAMAIS. Couper la source avant le terme
le sauve.

**Compose** : `charge.gd`, `etat_duree.gd`, `etat_effectif.gd`, `depense.gd`,
`produit.gd` — tous inchangés, les deux derniers JAMAIS COMBINÉS avant ce
chantier.

**`depense.gd` n'a pas de branche « produire »** : il ne fait que DÉTECTER le
seuil terminal en posant un marqueur, et c'est CE FICHIER qui appelle la
transformation — exactement le geste que `extinction.gd` fait déjà en
interne, rejoué au niveau du câblage.

**Le coût est GELÉ tant que l'état est absent** : idiome inverse du gel par
sauvetage. La réserve est calibrée avec marge au-dessus du coût sur la durée
de l'état, pour qu'une coupure PRÉCOCE sauve réellement l'objet.

**Correction en cours d'écriture** : le nom du marqueur terminal était codé
en dur, ce qui empêchait un domaine inventé de poser SON PROPRE marqueur — il
vient de la donnée.

**Testé par** : `scripts/test_banc_pourriture.gd`.

---

### `scripts/banc_corrosion.gd`

**Montre** : SECONDE fermeture du même patron, sur un domaine sans rapport —
preuve qu'il généralise. Quatre objets, TROIS destins : le fer rouille et
finit TRANSFORMÉ ; cuivre et bronze verdissent et RESTENT VERTS pour
toujours ; l'argent ternit. La patine est une couche PROTECTRICE, elle ne
ronge pas le métal.

**CORRECTION DE DOMAINE, vérifiée** : la première version opposait fer et
BOIS — le bois ne rouille pas, il se dégrade par un tout autre processus déjà
modélisé séparément.

**GÉNÉRALISATION QUE CE BANC AJOUTE** : chaque objet porte SON PROPRE état
cible et SA PROPRE propriété visée, là où le banc précédent en avait un seul
pour toute la scène — l'oxydation produit des effets chimiquement différents
selon le métal.

**Ce qui sépare les trois destins est une SEULE clé de données** : seul le
fer porte une réserve d'intégrité. Les autres sont ignorés NATURELLEMENT par
la phase de transformation, sans aucune garde écrite.

**Testé par** : `scripts/test_banc_corrosion.gd`.

---

### `scripts/banc_porosite.gd`

**Montre** : UNE SEULE propriété matériau traverse DEUX mécanismes
indépendants EN MÊME TEMPS. Deux objets identiques SAUF la porosité (densité
comprise), déjà en feu ET exposés à la même source d'eau : le plus poreux
mouille avant l'autre ET épuise son combustible avant l'autre. La combustion
n'est jamais liée à l'eau — couper la source ne ralentit pas le feu.

**Compose** : `depense.gd`, `charge.gd`, `etat_duree.gd`, `temperature.gd`,
`objet.gd` — tous inchangés. Les fonctions dont il a besoin sont RECOPIÉES
depuis les deux bancs d'origine, jamais appelées : deux bancs jetables ne se
référencent jamais entre eux.

**Testé par** : `scripts/test_banc_porosite.gd`.

---

### `scripts/banc_permeabilite.gd`

**Montre** : la RÉTENTION, jamais l'absorption — distinction volontaire avec
le banc d'humidité. Deux objets montent STRICTEMENT à la même vitesse sous la
même source (preuve qu'une seule variable est isolée) ; une fois la source
coupée, l'un sèche en quelques secondes et l'autre reste saturé bien plus
longtemps.

**Compose** : `charge.gd`, `objet.gd` — inchangés. UN SEUL appel pour tous
les objets, contrairement au banc d'humidité : le taux de décroissance est
une grandeur PROPRE À CHAQUE CANAL que le mécanisme lit nativement, rien à
contourner.

**Décision** : le taux est `plancher + facteur × permeabilite`. Un taux
purement proportionnel tomberait à zéro exact pour un objet imperméable, qui
retiendrait l'eau POUR TOUJOURS — rejeté ; le plancher garantit que tout
objet finit par sécher.

**Testé par** : `scripts/test_banc_permeabilite.gd`.

---

### `scripts/banc_solubilite.gd`

**Montre** : un objet soluble exposé à l'humidité perd de la masse jusqu'à
disparaître — le sel fond dans l'eau, la pierre non.

**Compose** : les deux patrons déjà fermés (accumulation → mouillé, puis
réserve → transformation), recopiés localement.

**UNE DIFFÉRENCE ASSUMÉE** : le coût de la réserve n'est pas une constante,
il vaut `facteur × solubilite` — proportionnel, gelé tant que l'objet n'est
pas mouillé.

**Testé par** : `scripts/test_banc_solubilite.gd`.

---

### `scripts/banc_conduction.gd`

**Montre** : le courant se propage de proche en proche entre conducteurs en
contact, et un agent au contact d'un objet sous tension prend des dégâts
continus. Trois rangées isolent trois choses : le blocage NET à un isolant, la
traversée d'une chaîne, et l'effet ×10 de l'humidité sur la conductivité à
matériau égal — PREMIÈRE consommation réelle de cette fondation dormante.

**Compose** : `flux.gd` (un appel PAR OBJET avec un émetteur SYNTHÉTIQUE dont
le taux est proportionnel à la conductivité de CET objet — le mécanisme ne
connaît qu'un taux par source) puis le patron accumulation → état → dégât.

**QUI CONDUIT ET QUI EST SOUS TENSION est propre à ce fichier** : `flux.gd`
ne sait pas propager de proche en proche (une réceptrice ne devient jamais
source). Un parcours en largeur depuis chaque générateur, à travers les seuls
conducteurs en contact, recalculé CHAQUE TICK — un fait géométrique
instantané, pas une accumulation. Un objet non conducteur n'entre jamais dans
la frontière : blocage NET, pas une atténuation, aucune branche « si bois ».

**Testé par** : `scripts/test_banc_conduction.gd`.

---

### `scripts/banc_foudre.gd`

**Montre** : PREMIÈRE démonstration réelle de `frappe.gd`. Un clic déclenche
UN SEUL éclair qui choisit sa cible par score composite ; le carré frappé
encaisse le dégât et sa température bondit puis redescend. Un second clic
frappe la cible restante.

**Compose** : `frappe.gd`, `quantite_matiere.gd`, `temperature.gd`,
`portee.gd`, `objet.gd` — inchangés.

**CORRECTION FACTUELLE** : le critère était d'abord le magnétisme — FAUX
physiquement, la foudre est guidée par la conductivité électrique.

**CRITÈRES CALIBRÉS pour que la hauteur ne gagne JAMAIS seule** : la
contribution maximale de la hauteur reste sous celle de la conductivité à
hauteur nulle — la hauteur ne fait que DÉPARTAGER entre deux conducteurs.

**QUI EST FRAPPABLE est propre à ce fichier** : `frappe.gd` n'a aucune notion
de cible déjà détruite. La source de chaleur de l'impact n'existe qu'UN SEUL
tick — cas particulier de la même mécanique qu'une source mobile, jamais un
geste nouveau côté mécanisme.

**Testé par** : `scripts/test_banc_foudre.gd`.

---

### `scripts/banc_fracture.gd`

**Montre** : la FRAGILITÉ tranche entre déformation et destruction. La
pierre fracture au premier choc et se transforme en éclats ; le fer encaisse
deux coups, fracture au troisième et reste du fer — jamais transformé.

**Compose** : `frappe.gd`, `seuil_etat.gd`, `produit.gd` — inchangés.

**CUMUL DE DÉGÂT, geste que `frappe.gd` ne fait jamais** (il ne fait que
décrémenter une réserve) : le câblage écrit lui-même la grandeur cumulée que
le seuil compare. Elle ne redescend jamais : la fracture est donc
irréversible EN PRATIQUE, alors que le mécanisme reste générique et
réversible.

**LA VISÉE EST LE PETIT RAYON, pas le score** : contrairement à la foudre qui
choisit seule sur toute la scène, la position de frappe est le CLIC, et un
rayon petit devant l'espacement des objets fait office de visée.

**FRAGILITÉ lue SEULE par ce fichier** : aucun mécanisme du cœur ne la
connaît.

**Testé par** : `scripts/test_banc_fracture.gd`.

---

### `scripts/banc_chaleur_emise.gd`

**Montre** : un objet qui brûle émet de la chaleur en continu, force
proportionnelle à sa matière. Deux foyers, deux voisins froids à distance
IDENTIQUE : celui du foyer le plus émissif se réchauffe STRICTEMENT plus
vite. Chaque foyer s'éteint quand sa réserve est épuisée et sa source
disparaît au tick suivant.

**Compose** : `objet.gd`, `temperature.gd`, `depense.gd` — inchangés.

**Une source PAR OBJET qui brûle, reconstruite du néant à chaque appel** :
aucune mémoire propre n'est nécessaire, le câblage scanne le seul état
courant. L'extinction est détectée par `depense.gd`, jamais par ce fichier.

**Manque pour observer** : aucune barre de réserve — l'extinction ne se lit
qu'au changement de couleur et à la console.

**Testé par** : `scripts/test_banc_chaleur_emise.gd`.

---

### `scripts/banc_lumiere.gd`

**Montre** : cinq choses à la fois, un lecteur par phénomène — le cycle
jour/nuit pur (loin de toute source), une torche fixe qui domine la nuit et
se fond dans le jour, une lanterne MOBILE suivie par deux lecteurs (l'un
collé à elle, l'autre fixe sur sa trajectoire qui capte le passage puis le
perd), et une zone de RECOUVREMENT de deux sources de couleurs opposées qui
affiche une couleur STRICTEMENT ENTRE les deux.

**Compose** : `lumiere.gd` — inchangé.

**Décision de trace** : le log suit les changements de ZONE discrète, jamais
l'épsilon fin du retour du mécanisme — l'ambiante dérivant en continu, un log
sur ce retour imprimerait à presque chaque frame.

**LA COULEUR À L'ÉCRAN VIT ENTIÈREMENT DANS CE FICHIER** : le mécanisme ne
connaît qu'un scalaire de température de couleur, jamais un RGB.

**Manque pour observer** : aucune interaction, et aucune démonstration
d'occlusion (la propriété d'opacité est fusionnée mais lue par personne).

**Testé par** : `scripts/test_banc_lumiere.gd`.

---

### `scripts/banc_reflectivite.gd`

**Montre** : PREMIER usage de la lumière comme SOURCE SECONDAIRE — un objet
réfléchissant devient lui-même une source posée à sa position. Trois objets à
ÉGALE distance d'une lampe : l'argent renvoie le plus et chauffe le moins, le
bois l'inverse, le cuivre PATINÉ voit sa réflectivité strictement réduite.

**Compose** : `lumiere.gd`, `temperature.gd`, `etat_effectif.gd`, `objet.gd`
— inchangés.

**DÉRIVE SIGNALÉE ET TRANCHÉE AVANT ÉCRITURE** : la consigne demandait un fer
terni — impossible, cet état n'existe que sur l'argent dans tout le dépôt et
le fer suit un autre état, qui module une autre propriété. Remplacé par du
cuivre patiné, même famille de modulation ; aucune règle de contenu déjà
tranchée n'est rouverte.

**Décision** : conductivité et chaleur spécifique sont des constantes LOCALES
partagées par les trois objets — les fusionner aurait fait venir l'écart de
température d'une donnée manquante plutôt que de la réflectivité, confondant
la variable observée.

**Testé par** : `scripts/test_banc_reflectivite.gd`.

---

### `scripts/banc_photodegradation.gd`

**Montre** : le soleil dégrade la matière organique morte, et rien d'autre.
Trois objets : l'un se dégrade au soleil, un deuxième est épargné parce qu'il
est HORS DE PORTÉE, un troisième parce que sa biodégradabilité est NULLE
malgré une exposition réelle — deux raisons différentes, jamais confondues.

**Compose** : `lumiere.gd` et `depense.gd` — inchangés. Le coût effectif est
réécrit CHAQUE TICK (`biodegradabilite × facteur × lumière locale`) :
`depense.gd` n'a lui-même aucun coefficient de lumière.

**DOCTRINE TRANCHÉE** : un banc concurrent câblait l'UV comme un RALENTISSEUR
de la pourriture — physique fausse, la stérilisation ne domine pas la
décomposition en milieu naturel. Tranché en faveur de l'accélération seule ;
le banc concurrent et tous ses fichiers ont été retirés du dépôt.

**Soleil coupé** : la lumière locale retombe à l'ambiante, donc le coût à
zéro, donc plus aucune réserve ne bouge — sans branche spéciale.

**Manque pour observer** : la SYNERGIE entre photodégradation et
biodégradation microbienne reste NON EXPLORÉE.

**Testé par** : `scripts/test_banc_photodegradation.gd`.

---

### `scripts/banc_son.gd`

**Montre** : deux filtres INDÉPENDANTS sur l'ouïe — l'INTENSITÉ atténuée par
la distance comparée à un seuil, et la FRÉQUENCE comparée à une plage. Deux
sources partagent le MÊME degré d'émission et ne diffèrent que par la
fréquence : un colon à plage humaine n'entend jamais l'ultrason, un colon à
plage élargie l'entend.

**SEUL chantier de banc à ce jour qui touche un mécanisme du CŒUR au-delà de
son fichier** : la géométrie de propagation active le champ de seuil, jusque
là stocké sans jamais être lu. Aucun autre fichier du cœur touché.

**Le second filtre est PROPRE À CE BANC**, jamais dans `perception.gd` —
limite stricte du chantier.

**Manque pour observer** : aucun obstacle réel entre source et colon ; et
l'affichage ne distingue pas LEQUEL des deux filtres a retiré une source.

**Testé par** : `scripts/test_banc_son.gd`.

---

### `scripts/banc_fracture_sonore.gd`

**Montre** : un son intense casse un objet fragile. Même patron que la
fracture mécanique, même état, même doctrine de fragilité — mais un
DÉCLENCHEUR différent : une accumulation CONTINUE tant qu'une source sonore
reste active, jamais un événement ponctuel visé au clic.

**Compose** : `seuil_etat.gd`, `produit.gd`, `portee.gd` — inchangés.
`frappe.gd` n'est PAS utilisé.

**PREMIÈRE PREUVE RÉELLE de la coexistence de deux entrées visant le même
nom d'état** : la mémoire PAR ENTRÉE du mécanisme de seuil, documentée mais
jamais encore vue jouer deux fois. Les deux grandeurs comparées ne sont
jamais présentes sur le même objet, chaque banc fabriquant les siens.

**ACCUMULATION AVEC DELTA, décision assumée** : contrairement aux mécanismes
qui posent un montant FIXE par événement discret, la grandeur monte
proportionnellement au delta. SÛR ici, contrairement au bug historique de la
croissance de lien : elle ne redescend JAMAIS, aucune décroissance ne peut
l'effacer — le delta ne rend l'accumulation qu'INDÉPENDANTE DU FRAMERATE.

**DÉFAUT DE DONNÉE TROUVÉ EN ÉCRIVANT LE TEST, fermé avant commit** : le
matériau de démonstration ne déclarait aucun point de transition, et le
défaut nul de la fusion générique est FRANCHI par la température ambiante —
il posait donc un état de fusion À TORT dès sa fabrication, sans aucune
exposition. Corrigé en donnée seule.

**Testé par** : `scripts/test_banc_fracture_sonore.gd`.

---

### `scripts/banc_croissance.gd`

**Montre** : une plante pousse sous la lumière ET l'eau — l'une sans l'autre
ne pousse pas. Trois plantes de même vitesse maximale, seule leur POSITION
relative aux deux sources diffère : l'une reçoit les deux et pousse, les deux
autres stagnent. Deux sources togglables SÉPARÉMENT (gauche pour la lumière,
droite pour l'eau).

**Compose** : `lumiere.gd` (lue directement), `charge.gd` (un canal
d'humidité par plante), `flux.gd` (fait monter une réserve de maturité) —
tous inchangés.

**Le taux appliqué est un PRODUIT de trois facteurs bornés**, dont la charge
NORMALISÉE par son seuil — jamais la charge brute, que le mécanisme ne borne
qu'en bas. `flux.gd` ne connaissant qu'un taux par source, le câblage
construit un émetteur SYNTHÉTIQUE par plante et par tick ; et comme il ne
borne jamais rien, la maturité est plafonnée PAR CE FICHIER — jamais
redescendue, une plante adulte ne redevient pas graine.

**Testé par** : `scripts/test_banc_croissance.gd`.

---

### `scripts/banc_resonance.gd`

**Montre** : un matériau résonnant RÉÉMET le son qu'il reçoit. Trois objets à
ÉGALE distance d'une source, dont deux SYMÉTRIQUES par rapport à l'axe
source-colon (mêmes distances des deux côtés) : seule leur résonance les
sépare. Le son total perçu par le colon est STRICTEMENT plus fort avec eux
que sans.

**Compose** : `perception.gd` — inchangé.

**Une source PAR OBJET, reconstruite du néant à chaque appel** : un objet
dont le son réémis n'est pas strictement positif ne produit JAMAIS de source
secondaire, jamais une source posée à force nulle.

**Le monde perçu est JETABLE, reconstruit chaque tick** : il ne contient que
les sources actives du moment — les objets résonnants eux-mêmes n'y entrent
jamais (ce sont des réémetteurs, pas des choses perçues par ce canal).

**Testé par** : `scripts/test_banc_resonance.gd`.

---

### `scripts/banc_occlusion.gd`

**Montre** : un mur entre une source et un colon atténue le son au point de
le faire passer sous le seuil ; le même mur retiré, le son redevient perçu.
Une paire TÉMOIN sans mur, à la même géométrie, ne varie jamais.

**Compose** : `perception.gd` (troisième filtre) — inchangé.

**Marge volontairement FINE** : le mur réel n'absorbe que 5 %, et cela suffit
à faire basculer — jamais un mur artificiellement fort.

**Le monde est RECONSTRUIT CHAQUE TICK** : faire « disparaître » le mur exige
de ne jamais l'ajouter au monde de ce tick, jamais une mutation en place d'un
objet déjà enregistré — `monde.gd` n'a aucune fonction de retrait.

**Testé par** : `scripts/test_banc_occlusion.gd`.

---

### `scripts/banc_absorption_sonore.gd`

**Montre** : un POURCENTAGE de réduction, jamais une coupure — seuil
volontairement NUL, à l'inverse du banc précédent : le colon entend TOUJOURS
la source, quel que soit le mur. Le mur cycle au clic à travers quatre états
et l'atténuation suit la valeur RÉELLE du matériau : le bois absorbe le plus
(panneau acoustique), la pierre peu, le fer presque rien (le métal résonne).

**Ne code rien de neuf** : prouve seulement que le filtre déjà livré réduit
selon la matière, avec des matériaux DIFFÉRENTS.

**Jamais deux murs simultanés dans la scène** : le cumul multiplicatif de
deux obstacles réels est vérifié séparément par le test.

**Testé par** : `scripts/test_banc_absorption_sonore.gd`.

---

### `scripts/banc_friction.gd`

**Montre** : trois objets poussés par la même force glissent à des distances
différentes selon leur friction ; un clic les mouille TOUS LES TROIS et les
trois glissent plus loin, l'ordre restant net.

**Ce chantier rend enfin ACTIVE une fondation dormante** : l'état d'humidité
modulait déjà la friction, mais aucun objet fabriqué par composition ne
portait jamais cette propriété — la modulation était vraie en donnée et
inerte en jeu.

**Trois objets FABRIQUÉS par composition**, justement parce que le chantier
démontre que la propriété est désormais fusionnée.

**Testé par** : `scripts/test_banc_friction.gd`.

---

### `scripts/banc_restitution.gd`

**Montre** : trois objets lâchés au clic rebondissent de moins en moins haut,
chacun selon sa restitution — le fer rebondit le plus longtemps, le bois
s'arrête le premier. Un second clic les RÉINITIALISE en l'air.

**MÉCANIQUE, aucune physique Godot, aucun corps rigide** : un calcul de
position par tick, câblé à la main. Deux fonctions triviales (hauteur après
rebond, vitesse nécessaire pour culminer à une hauteur) composées par une
intégration simple.

**`position.z` porte la HAUTEUR**, rendue à l'écran par une projection — même
convention que le critère de hauteur de `frappe.gd`.

**Le compteur de rebonds n'est incrémenté que sur un rebond RÉEL**, jamais au
dernier contact qui arrête l'objet : une restitution nulle rend donc
exactement zéro rebond.

**Testé par** : `scripts/test_banc_restitution.gd`.

---

### `scripts/banc_rigidite.gd`

**Montre** : trois poutres soutenues à leurs deux bouts fléchissent sous une
charge identique — le bois beaucoup, le fer à peine. Au-delà d'un seuil, la
poutre CASSE et le reste même après retrait de la charge.

**Compose** : `seuil_etat.gd`, `etat_effectif.gd` — inchangés.

**CATALOGUE DE SEUIL LOCAL**, jamais ajouté au partagé : la grandeur comparée
est propre à ce mécanisme, sans rapport avec les grandeurs cumulées des
autres bancs.

**La flèche affichée est la MAXIMALE ATTEINTE, jamais l'instantanée** : un
accumulateur qui ne redescend jamais — une poutre déjà fléchie reste
visuellement déformée, et c'est ce qui rend la fracture irréversible en
pratique sans règle spéciale dans le mécanisme.

**Testé par** : `scripts/test_banc_rigidite.gd`.

---

### `scripts/banc_elasticite.gd`

**Montre** : ce que la force LAISSE une fois retirée. Sous compression, les
trois objets s'écrasent selon leur rigidité ; force retirée, chacun remonte
de la FRACTION que son élasticité récupère — le reste est permanent. Un
troisième clic réapplique la force et la déformation maximale continue
d'accumuler, rien ne redémarre à zéro.

**RÉUTILISE la rigidité** pour la déformation sous force — même formule que
le banc précédent, jamais réimplémentée différemment. Ce que ce banc ajoute
est le RETOUR.

**PIÈGE DE CALIBRATION, non trivial et signalé** : sur les valeurs réelles,
le rapport élasticité/rigidité de deux matériaux COÏNCIDE — la quantité
récupérée EN ABSOLU est donc identique pour les deux. Seule la FRACTION
récupérée les ordonne sans ambiguïté ; le test compare les deux axes
séparément et isole l'élasticité comme seule variable sur des objets
synthétiques à rigidité égale.

**Testé par** : `scripts/test_banc_elasticite.gd`.

---

### `scripts/banc_coupe.gd`

**Montre** : couper dépend de l'OUTIL autant que de la CIBLE. Un clic près
d'une cible la coupe ; le bois cède facilement, la pierre résiste, le fer
beaucoup. Chaque coupe ÉMOUSSE l'outil, d'autant plus vite que la cible est
dure — un outil en bois s'émousse avant d'entamer la pierre. Un clic droit
fait cycler l'outil et lui rend un tranchant frais.

**Compose** : `frappe.gd` (qui est frappé et quel dégât) et `produit.gd`
(débris à réserve épuisée) — inchangés. `seuil_etat.gd` n'est PAS utilisé :
différence assumée avec la fracture, qui compare deux grandeurs via un seuil.
Ici on épuise une réserve puis on transforme — le patron déjà établi par les
trois bancs de dégradation.

**L'outil porte SA PROPRE grandeur, propre à ce banc**, jamais dans le
catalogue matériau. Un tranchant nul ne coupe plus PAR LA SEULE ARITHMÉTIQUE,
jamais par une branche « l'outil ne coupe plus ».

**IDEMPOTENCE SANS MARQUEUR** : une cible transformée ne porte plus sa
référence de transformation, ce qui arrête tout par construction — aucun
compteur ni drapeau supplémentaire.

**Testé par** : `scripts/test_banc_coupe.gd`.

---

### `scripts/banc_usinabilite.gd`

**Montre** : le temps de fabrication dépend du matériau. Trois objets à même
travail initial : le bois finit le premier, la pierre le dernier. Rien ne
descend avant le premier clic — contraste volontaire avec les bancs qui
démarrent seuls.

**Compose** : `depense.gd`, `etat_effectif.gd` — inchangés. Un colon simulant
un geste de fabrication est une réserve nommée ordinaire.

**FORMULE TRANCHÉE EN CONVERSATION AVANT D'ÉCRIRE** : l'énoncé initial
(`cout / usinabilite`) produisait l'ORDRE INVERSE de ce qu'il décrivait —
`depense.gd` retirant `cout × delta`, diviser par une usinabilité HAUTE donne
un coût PLUS PETIT, donc la pierre aurait fini avant le bois. La formule
retenue est un PRODUIT : un matériau facile à usiner consomme sa réserve plus
vite et finit plus tôt.

**Testé par** : `scripts/test_banc_usinabilite.gd`.

---

### `scripts/banc_traction.gd`

**Montre** : trois objets suspendus sous une traction identique rompent à des
instants différents selon leur résistance ; l'objet rompu se détache et TOMBE
sans jamais rebondir.

**Compose** : `seuil_etat.gd` — inchangé.

**L'état de rupture ÉCRASE la résistance à zéro** : la propriété visée est
directement le SEUIL qui vient d'être franchi, un écrasement est la seule
valeur cohérente (là où une fracture MODULE par un facteur).

**L'état LUI-MÊME est le déclencheur de la chute**, aucun drapeau séparé.
Même convention de hauteur que le banc de rebond, mais sans rebond : un lien
rompu tombe et y reste.

**Testé par** : `scripts/test_banc_traction.gd`.

---

### `scripts/banc_velocite.gd`

**Montre** : PREMIER câblage réel de `velocite.gd`. Quatre objets — un colon
à mouvement VOLONTAIRE seul, un golem et un aimant REPRIS TELS QUELS d'un
autre banc (aucune donnée dupliquée), et un repère qui ne bouge jamais. La
vélocité est le DERNIER appel du tick, après tous les mécanismes qui mutent
une position.

**Un seul clic, deux ordres** : le même point-cible est posé sur le colon ET
sur le golem — aucune ambiguïté d'entrée.

**Le repère est la démonstration** : jamais touché par aucun mécanisme, il
affiche une vélocité exactement nulle — aucune propriété « immobile »
n'existe, le zéro EST le résultat du calcul sur une position qui ne change
pas.

**Testé par** : `scripts/test_banc_velocite.gd`.

---

### `scripts/banc_acide.gd`

**Montre** : trois objets exposés à la même source d'acide corrodent à des
instants différents selon leur résistance ; l'état est IRRÉVERSIBLE, la
grandeur cumulée ne redescendant jamais. Aucun mouvement, aucune
transformation : la corrosion ne fait que changer une couleur et moduler deux
propriétés.

**Compose** : `seuil_etat.gd`, `etat_effectif.gd` — inchangés.

**Même idiome d'accumulation** que la fracture sonore et la traction : une
grandeur qui n'existe QUE parce que ce câblage l'écrit, sous gate strict sur
l'activité de la source — source coupée, elle ne bouge jamais.

**Testé par** : `scripts/test_banc_acide.gd`.

---

### `scripts/banc_toxicite.gd`

**Montre** : un agent au contact d'un objet toxique prend des dégâts
continus. Trois objets de toxicités différentes ; le colon se déplace de
l'un à l'autre au clic (index circulaire sur trois positions fixes). Près du
plus toxique il s'empoisonne vite, près du fer nettement plus lentement, près
de la pierre jamais — sa charge redescend au lieu de monter. S'éloigner
laisse l'état s'estomper progressivement.

**Compose** : le patron accumulation → état → dégât, pour la cinquième fois,
SANS le volet propagation (aucun réseau, un seul objet compte à la fois).

**Fonction propre** : une cause par objet à toxicité EFFECTIVE strictement
positive — le filtrage par PORTÉE reste entièrement délégué à `charge.gd`.

**Testé par** : `scripts/test_banc_toxicite.gd`.

---

### `scripts/banc_mana_conduction.gd`

**Montre** : la MÊME propriété matériau sert un SECOND domaine. Deux rangées :
l'une bloquée net par un isolant, l'autre traversée de bout en bout.

**Compose** : `flux.gd` — inchangé. Le patron du banc de conduction
électrique est RECOPIÉ localement, jamais appelé : deux bancs jetables ne se
référencent jamais entre eux.

**Le seuil de conduction est VOLONTAIREMENT DIFFÉRENT** de l'électrique :
même propriété, deux domaines, deux seuils. Verrouillé par un test qui isole
une conductivité intermédiaire, conduisant l'un et pas l'autre.

**Décision** : ce chantier ne demande PAS de dégâts à un agent — seule la
canalisation est montrée. Un pas de décroissance est ajouté par le câblage :
`flux.gd` n'a lui-même aucun geste pour faire redescendre une réserve.

**Testé par** : `scripts/test_banc_mana_conduction.gd`.

---

### `scripts/banc_choc_magique.gd`

**Montre** : un TROISIÈME chemin vers le même état de fracture. Un sort
togglable frappe automatiquement à cadence fixe ; le verre casse et se
transforme, le bois puis le fer fracturent sans jamais se transformer.

**Compose** : `frappe.gd`, `seuil_etat.gd`, `produit.gd` — inchangés.

**DEUX DÉCISIONS TRANCHÉES EN CONVERSATION avant d'écrire** :
- CRITÈRE : la sensibilité magique SEULE. La distance ne joue AUCUN rôle dans
  le score — elle reste le filtre de portée déjà existant du mécanisme, jamais
  une seconde source ajoutée (ce qui aurait exigé de toucher le cœur).
- CADENCE : le sort est togglable et frappe à intervalle fixe, JAMAIS à chaque
  frame — le mécanisme applique une quantité PONCTUELLE, jamais un taux. Un
  accumulateur de temps comparé à un seuil garde la cadence indépendante du
  framerate sans faire du dégât un taux.

**UN CASTER PAR CIBLE, jamais un caster global** : chaque appel part de la
position de la cible elle-même avec un rayon petit devant leur espacement, si
bien que chaque appel ne voit qu'un seul candidat. Nécessaire pour que les
trois cibles progressent EN PARALLÈLE plutôt qu'un seul vainqueur au score
monopolise toutes les frappes.

**Testé par** : `scripts/test_banc_choc_magique.gd`.

---

### `scripts/banc_reactivite.gd`

**Montre** : PREMIER banc où DEUX objets réels réagissent l'un avec l'autre,
chacun contribuant sa propre réactivité au score — plutôt qu'un objet face à
une cause ambiante passive. Un acide rapproché au clic transforme trois
cibles à des vitesses différentes, puis se vide lui-même et devient un résidu.

**Compose** : `charge.gd`, `depense.gd`, `produit.gd`, `portee.gd` —
inchangés.

**DÉCISION DE DESIGN TRANCHÉE AVANT D'ÉCRIRE** : `produit.gd` ne prend qu'UN
objet ancien, `monde.gd` n'a aucune fonction de retrait, et le seul précédent
« deux objets réels → un » FUSIONNE au lieu de produire un type choisi. Les
deux réactifs sont donc transformés SÉPARÉMENT, par deux appels distincts :
la cible quand SON canal franchit, l'acide quand SA réserve atteint zéro.

**FERMETURE EXPLICITE, pas une simple décroissance** : la consommation de
l'acide est proportionnelle aux cibles ENCORE réactives à portée. Sans règle
supplémentaire, elle se figerait à une valeur résiduelle dès la dernière
cible transformée et l'acide ne deviendrait JAMAIS un résidu — la réserve est
donc FORCÉE à zéro dès qu'aucune cible ne porte plus d'entrée de catalogue.
Calibrée pour que la décroissance organique ne touche jamais zéro avant que
la cible la plus lente ait fini.

**Testé par** : `scripts/test_banc_reactivite.gd`.

---

### `scripts/banc_radiation.gd`

**Montre** : l'irradiation et le BLINDAGE. Trois objets à ÉGALE distance
d'une source, disposés PERPENDICULAIREMENT pour qu'aucun ne tombe sur le
segment du mur : seule leur sensibilité explique l'écart. Un mur togglable,
exactement au milieu d'un segment, fait cesser la perception d'une SEULE
cible dont la charge redescend alors.

**Compose** : `perception.gd` (canal dédié, occlusion par densité),
`charge.gd`, `etat_duree.gd`, `etat_effectif.gd`, `depense.gd` — inchangés.

**BLOQUÉ UNE SESSION ENTIÈRE** : la géométrie lisait le nom de la propriété
d'émission EN DUR, jamais paramétré par canal. L'audit affirmait « pur ajout
de donnée » — inexact sans cette généralisation. Décision : SIGNALER ET
REPORTER plutôt que toucher le cœur dans ce chantier. Une fois le chantier
séparé livré par une autre session, aucun mécanisme n'a eu à être touché ici.

**Testé par** : `scripts/test_banc_radiation.gd`.

---

### `scripts/banc_manger.gd`

**Montre** : PREMIÈRE démonstration réelle de `consommer.gd` et du verbe
manger. Un colon converge sur la seule chose saillante, l'atteint, mange :
son énergie monte EXACTEMENT de ce que la nourriture perd, jusqu'à épuisement
puis transformation en reste. Deux autres objets ne portent NI comestibilité
NI profil de saillance — structurellement non saillants, jamais candidats de
décision : le colon les ignore entièrement, pas seulement « ne les mange
pas ».

**Compose** : perception, proximité, dominance, agir, `consommer.gd`,
`produit.gd`, `etat_effectif.gd` — inchangés. Pipeline à TROIS couches, sans
attaches ni jugement : la seule source de saillance est la proximité.

**L'EXÉCUTION N'EST JAMAIS DANS `agir.gd`** : le verbe résolu est une
donnée pure, zéro ligne dans le mécanisme. C'est le câblage qui vérifie la
portée physique, compose le taux depuis deux propriétés effectives, et
appelle le transfert. Une ration pourrie a une comestibilité effective nulle,
donc un taux nul, donc le transfert ne fait déjà rien — AUCUN cas particulier
codé pour « pourri ».

**COLLISION FERMÉE AVEC LE LINTER** : profil de saillance et type produit
sont vérifiés contre les catalogues PARTAGÉS quel que soit le fichier source
— une table locale n'aurait jamais été validée.

**Testé par** : `scripts/test_banc_manger.gd`.

---

### `scripts/banc_magie_perception.gd`

**Montre** : un canal de perception magique, exactement sur le patron de
l'ouïe. Deux colons aux seuils différents, entourés chacun de sources
d'intensités variées : le mage perçoit les quatre de son cluster, le guerrier
seulement deux. Une source sans force d'émission n'est JAMAIS perçue (jamais
sous un seuil strictement positif) ; une source hors de portée non plus, mais
pour une raison géométrique DISTINCTE.

**BLOQUÉ EN DÉBUT DE SESSION, décision prise en conversation avant tout
code** : reproduire le patron de l'ouïe était IMPOSSIBLE sans toucher le cœur
tant que le nom de la propriété d'émission restait figé.

**SECONDE DÉCISION, contre le prompt d'origine** : celui-ci traitait la
sensibilité magique comme une intensité portée par la SOURCE — contredit par
la matrice des éléments, qui la décrit comme un stat du RÉCEPTEUR. Tranché
pour le sens RÉCEPTEUR : cette propriété reste DORMANTE, jamais fusionnée, et
le seuil réel vit sur le colon. La SOURCE porte une propriété SÉPARÉE, rôle
émetteur, indépendante — même discipline que les deux grandeurs du feu,
jamais dérivées l'une de l'autre.

**Testé par** : `scripts/test_banc_magie_perception.gd`.

---

### `scripts/banc_produit_nucleaire.gd`

**Montre** : TROIS effets d'une même source radioactive, en parallèle —
contamination de zone (la source s'épuise, devient un résidu qui irradie plus
faiblement), MUTATION génétique (une marque épigénétique s'accumule chez le
colon), et MALADIE (nausée réversible, puis deux seuils IRRÉVERSIBLES :
syndrome puis mort).

**Compose** : dix mécanismes déjà fermés, dont quatre jamais composés
ensemble avant — tous inchangés.

**FINDING absent de l'audit** : la source construite à la main doit porter
une MASSE posée à la main, sinon la transformation calcule un résidu de
volume nul et la fabrication est REFUSÉE.

**MORT = FIGÉ, PAS RETIRÉ** (décision Yael, trois options proposées) : une
fois l'état de mort actif, plus rien ne touche le colon — dose, marque,
états, vitesse, tout gelé exactement dans l'état où la mort l'a laissé. Il
reste visible comme un corps. Aucun retrait réel : `monde.gd` n'a aucune
fonction de retrait, et ouvrir ce chantier a été écarté explicitement.

**TROIS NOMS D'ÉTAT DISJOINTS, chacun gouverné par UN SEUL mécanisme** — la
collision que l'audit redoutait entre deux mécanismes sur le même nom n'est
jamais rencontrée ici. L'écraseur de mort rend les deux modulateurs sans
effet dès qu'il est actif, par l'ordre de résolution déjà prouvé.

**Testé par** : `scripts/test_banc_produit_nucleaire.gd`.

---

### `scripts/banc_sorts.gd`

**Montre** : la TUYAUTERIE des sorts, pas les sorts eux-mêmes. Un dispatcher
unique lit une entrée de catalogue, vérifie et ponctionne le mana, multiplie
par l'affinité du lanceur, puis route vers UN SEUL mécanisme déjà fermé.
Quatre effets, quatre patrons déjà écrits. AUCUN NOM DE SORT en dur au-delà
du routage par type d'effet.

**Compose** : `frappe.gd`, `flux.gd`, `etat_duree.gd`, `portee.gd` —
inchangés.

**UN SORT EST UN ÉVÉNEMENT PONCTUEL** : les effets continus sont appelés avec
un delta unitaire, la grandeur servant directement de quantité appliquée UNE
FOIS. Le mana est soustrait DIRECTEMENT, jamais via `depense.gd`
(structurellement continu) ; il remonte en parallèle par une source ambiante
— les deux mécanismes ne se connaissent pas.

**LA DURÉE RÉELLE VIENT DU CATALOGUE D'ÉTATS**, jamais du catalogue de sorts :
le mécanisme ne reçoit aucune durée en paramètre. Le champ du sort ne
documente que l'INTENTION.

**VOLATILITÉ POSÉE À LA MAIN, décision Yael** : les valeurs dormantes du
catalogue matériau sont hors d'échelle avec des dégâts de sort (un seul coup
les dépasserait toutes) ET dans un ORDRE qui contredirait la démonstration.
Le catalogue partagé n'est pas modifié.

**Testé par** : `scripts/test_banc_sorts.gd`.

---

### `scripts/banc_activation_neutronique.gd`

**Montre** : LA CHAÎNE — une source primaire irradie trois objets, chacun
accumule sa dose, et au seuil devient lui-même SOURCE SECONDAIRE. Le colon ne
perçoit JAMAIS la source primaire : il n'est irradié que par les objets
activés, y compris quand la primaire est coupée.

**Protection PAR CONSTRUCTION, jamais un filtre ajouté** : aucun appel de
perception ne l'interroge sur la primaire. Il perçoit uniquement les objets,
et le seuil du canal filtre lui-même ceux qui ne sont pas encore actifs
(force nulle).

**DÉCISION YAEL, question posée avant d'écrire** : la dose accumulée n'est
PAS un miroir de la charge (réversible par construction, elle redescend quand
la cause disparaît) mais le MAXIMUM jamais atteint — un miroir direct aurait
rendu l'état RÉVERSIBLE, contredisant le rôle de cicatrice permanente voulu.

**La force secondaire suit la réserve acquise et retombe exactement à zéro à
épuisement** — l'état, lui, reste : la cicatrice.

**Testé par** : `scripts/test_banc_activation_neutronique.gd`.

---

### `scripts/banc_emergences.gd`

**Montre** : une capacité qui n'appartient à AUCUN de ses composants apparaît
à la fabrication. Bistable AVANT/APRÈS au clic : un composite gagne une
capacité que ni l'un ni l'autre de ses matériaux ne remplit seul ; un
matériau léger et résistant en gagne une autre sans aucune composition ; un
fer seul ne gagne rien — ET logique réel.

**SEUL chantier de cette section qui MODIFIE un mécanisme du cœur**
(l'évaluation à la fabrication) — tous les autres composent sans y toucher.

**Aucun tick requis** : l'émergence se décide entièrement à la fabrication,
seul l'INSTANT de fabrication est rejouable.

**Le verdict vient TOUJOURS de la propriété posée par le mécanisme**, jamais
recalculé : le diagnostic par condition n'est qu'un AFFICHAGE de nombres déjà
connus, pas une seconde loi.

**Décision** : ce banc étend une liste LOCALE de propriétés immuables plutôt
que de toucher le catalogue partagé — préserver une dormance actée par un
autre chantier.

**Testé par** : `scripts/test_banc_emergences.gd`.

---

### `scripts/banc_chaine_reactions.gd`

**Montre** : PREMIÈRE démonstration de `reaction.gd`. Un clic rapproche trois
objets : le premier réagit avec le second et le transforme ; AU TICK SUIVANT,
le produit se trouve à portée du troisième et réagit à son tour — cascade en
deux étages, jamais dans le même appel. Les catalyseurs ne sont JAMAIS
transformés. Un second clic éloigne : plus rien n'accumule.

**Ce banc ne fait plus qu'UN SEUL appel par tick**, là où le banc de
réactivité portait encore les quatre phases dans son propre câblage. La
détection de paires, extraite vers le cœur, bénéficie désormais à tout banc
futur sans recâblage.

**DETTE ASSUMÉE** : un test existant a dû être ASSOUPLI — il verrouillait le
catalogue de réactions à exactement trois entrées, toutes du même catalyseur.
Désormais partagé par deux consommateurs, il vérifie seulement que les
entrées nécessaires à SON banc y figurent.

**Testé par** : `scripts/test_banc_chaine_reactions.gd`.

---

### `scripts/banc_maladie.gd`

**Montre** : contagion, incubation, mort. Neuf colons marchant au hasard
SEEDÉ ; un patient zéro contamine par proximité, le contaminé devient
contagieux IMMÉDIATEMENT (avant tout symptôme), puis les symptômes
apparaissent, puis la mort.

**Compose** : `charge.gd`, `etat_duree.gd`, `etat_effectif.gd`,
`seuil_etat.gd` — inchangés.

**AUCUNE COMPARAISON AVANT/APRÈS côté câblage** : seuls les colons PAS ENCORE
infectés portent le canal receveur, et le câblage le RETIRE au contaminé —
qui sort pour toujours du pool. Chaque bascule rendue est donc TOUJOURS une
contamination fraîche.

**CALIBRATION ASSUMÉE** : le seuil de mort est délibérément SOUS la durée de
la maladie — un malade meurt AVANT de guérir, cohérent avec l'absence de tout
traitement dans ce banc. La guérison n'est donc JAMAIS observée en direct,
seulement prouvée par le test.

**Testé par** : `scripts/test_banc_maladie.gd`.

---

### `scripts/banc_ecoulement.gd`

**Montre** : PREMIÈRE démonstration de `ecoulement.gd`. Une grille en pente ;
l'eau posée sur la colonne haute descend, s'accumule, et le compteur total
baisse par absorption et évaporation — jamais par l'écoulement, qui ne fait
que déplacer.

**TERRAIN MODÉLISÉ EN OBJETS ORDINAIRES** — tranche une question ouverte du
design : une grille de cases-objets `{ id, position, proprietes }`, AUCUNE
structure de terrain séparée.

**MODÈLE DE POSITION, décision Yael, contradiction trouvée AVANT d'écrire** :
`position` reste un FAIT SPATIAL PUR en unités de grille, `z` toujours nul.
Si l'altitude vivait dans `position.z`, l'écart entre deux cases adjacentes
dépasserait à lui seul le rayon de voisinage et casserait TOUT voisinage —
vérifié par le calcul, pas après coup.

**Absorption ET évaporation sans code neuf** : les deux vivent sur le même
canal (`cout_base` dérivé de la perméabilité du sol, surcoût constant), un
seul appel les décrémente ensemble. Le diagnostic qui les sépare à l'écran
rejoue le même calcul EN LECTURE SEULE, jamais une seconde source de vérité.

**Testé par** : `scripts/test_banc_ecoulement.gd`.

---

### `scripts/banc_sandpile.gd`

**Montre** : démonstration visuelle de `sandpile.gd`. Grille plate, clic
gauche ajoute `AJOUT_CLIC` grains sur la case sous le curseur. Chaque
`INTERVALLE_TICK` secondes, `Sandpile.avancer` roule les grains empilés au-delà
de `SEUIL_PENTE` vers les voisines cardinales — un cône au repos se forme.

**MODÈLE DE POSITION identique à `banc_ecoulement.gd`** : `case.position` est
un fait spatial pur en unités de GRILLE (`z = 0.0` toujours), l'altitude vit
dans `proprietes.altitude_sol`, découplée. `rayon_voisinage = 1.0` couvre les 4
voisins cardinaux sans être pollué par l'écart d'altitude.

**CASES CONSTRUITES À LA MAIN** : aucun `Objet.fabriquer`, même statut que
`banc_ecoulement` — une case du banc n'a ni composition ni densité.

**NOMS DE PROPRIÉTÉS** : lus depuis `data/banc_sandpile.json`, JAMAIS écrits en
dur. Aucun mot de « grain » dans le code du mécanisme.

**Testé par** : `scripts/test_sandpile.gd` (test hors domaine du mécanisme).

**ÉCART FRAMEWORK** : présent dans le dépôt orion, ABSENT de la copie locale
`scripts/` + `Scene/` + `data/` de ce dépôt.

---

### `scripts/banc_succession.gd`

**Montre** : succession écologique — nu → prairie → taillis → forêt. Un clic
BRÛLE une case et ses voisines, qui repartent du premier stade et rejouent la
succession entière. Une colonne stérile ne progresse JAMAIS, à côté de cinq
qui avancent.

**Compose** : `senescence.gd` puis `stade.gd`, deux appels par case et par
tick — inchangés.

**STADES EXCLUSIFS PAR CONSTRUCTION** : le stade est UNE String, jamais un
ensemble de marqueurs cumulés. C'est exactement ce qui distingue ce mécanisme
du seuil d'état (où plusieurs états restent actifs ensemble), et la raison
pour laquelle une succession ne s'écrit PAS en escalier de seuils.

**VIEILLISSEMENT CONDITIONNEL, sans une ligne de mécanisme** : le facteur
d'échelle rendu vaut zéro quand la case ne remplit pas la condition — l'âge
ne bouge plus, donc le stade non plus. Aucun cas particulier : c'est la
doctrine même du mécanisme, qui laisse le CÂBLAGE choisir la vitesse.

**LE FEU EXIGE LES DEUX ÉCRITURES** (âge ET stade) : le mécanisme refuse tout
retour en arrière en comparant des INDEX, donc remettre l'âge seul laisserait
le stade figé et bloquerait la remontée pour toujours.

**Testé par** : `scripts/test_banc_succession.gd`.

---

### `scripts/banc_cratere.gd`

**Montre** : une trace d'impact qui s'efface. Un clic creuse une case ; l'eau
s'y accumule au-dessus du niveau des voisines ; le compte à rebours défile,
puis le cratère disparaît d'un coup et l'eau repart.

**Compose** : `frappe.gd`, `depense.gd`, `ecoulement.gd` — inchangés.

**TROIS PROPRIÉTÉS D'ALTITUDE, TROIS CONTRATS DISJOINTS — le cœur du banc** :
l'altitude de BASE n'est JAMAIS réécrite par personne (un cratère ne l'écrase
pas, elle n'est donc jamais à restaurer) ; le CREUSEMENT est écrit à
l'impact et remis à zéro par le seuil ; l'altitude EFFECTIVE est DÉRIVÉE
chaque tick et c'est ELLE SEULE qui est passée à l'écoulement — le mécanisme
ne connaît pas le creusement et n'a pas à le connaître.

**Pourquoi restaurer un CREUSEMENT plutôt qu'une altitude** : un seuil
n'écrit qu'une CONSTANTE, la même pour toutes les cases — impossible de
restaurer l'altitude d'une case en pente, alors qu'un creusement vaut
toujours zéro.

**DÉCISION DE CÂBLAGE ASSUMÉE, absente de la consigne** : le même geste
RÉARME l'intégrité du sol — elle mesure la résistance à UN impact, jamais une
usure cumulée. Sans ce réarmement, une case ne serait creusable qu'une seule
fois de toute la vie du banc.

**PIÈGE** : recharger la réserve exige de VIDER les seuils franchis, sinon le
cratère suivant ne s'effacerait plus jamais.

**Testé par** : `scripts/test_banc_cratere.gd`.

---

### `scripts/banc_simulation_acceleree.gd`

**Montre** : accélérer le temps se fait par un FACTEUR D'ÉCHELLE et la
RÉPÉTITION d'un petit pas FIXE, JAMAIS par un grand delta. Bascule au clic
entre accéléré et temps réel — UN SEUL chemin de code, jamais deux branches
de simulation.

**LES DEUX VOIES DONNENT LE MÊME ÂGE SIMULÉ, PAS LE MÊME MONDE** : à grand
delta la température DIVERGE (intégration explicite) et l'écoulement devient
non physique (une case se vide vers son premier voisin dans l'ordre
d'itération). Le facteur d'échelle, lui, est DOCTRINAL.

**DEUX HORLOGES DÉCOUPLÉES, conséquence nommée** : la sénescence est le SEUL
mécanisme en ANNÉES, tout le reste travaille en SECONDES DE SIMULATION. Un
tick accéléré avance de plusieurs dizaines d'années de succession mais d'une
fraction de seconde d'hydrologie — « des milliers d'années simulées » ne se
lit JAMAIS « des milliers d'années de pluie ».

**TEMPÉRATURE VOLONTAIREMENT ABSENTE**, choix doctrinal : c'est le seul
mécanisme qui diverge numériquement, et le rendre inoffensif demanderait de
le sous-échantillonner EN INTERNE, donc de toucher le cœur. Verrouillé
POSITIVEMENT par test : aucune case ne porte cette propriété, la divergence
est impossible PAR CONSTRUCTION.

**LE NOMBRE D'ITÉRATIONS EST FIXÉ SUR MESURE, pas sur intuition** : le débit
en années ne dépend PAS de lui (doubler les itérations divise les ticks par
deux, le produit est constant) mais SEULEMENT du facteur d'échelle. Les
itérations ne règlent que la finesse du pas physique et la fluidité. Une
première calibration promettait « des milliers d'années en quelques
secondes » — mesurée FAUSSE, corrigée.

**Testé par** : `scripts/test_banc_simulation_acceleree.gd`.

---

### `scripts/banc_fertilite.gd`

**Montre** : le sol s'épuise et se refait. Quatre zones : la récolte fait
descendre la fertilité, la jachère la fait remonter TOUTE SEULE, une
légumineuse en fixe à distance, un cadavre se décompose dans la case sous lui
puis devient de l'humus.

**Compose** : `depense.gd`, `flux.gd`, `consommer.gd`, `produit.gd` —
inchangés, chacun sur le geste pour lequel il est fait.

**NEUTRALITÉ DE `depense.gd` EXPLOITÉE, jamais contournée** : un coût NÉGATIF
fait REMONTER la réserve — c'est ainsi que la jachère se refait, sans une
ligne de code neuve.

**TROIS TRANSFERTS, TROIS MÉCANISMES DIFFÉRENTS, et c'est le sujet** : la
légumineuse utilise `flux.gd`, qui ne déplète JAMAIS sa source — physiquement
correct, elle fixe l'azote de l'AIR. Le cadavre utilise `consommer.gd`,
CONSERVÉ : ce qu'il perd, le sol le gagne exactement. Et il perd une RÉSERVE
NOMMÉE, jamais sa masse (sortie dérivée de la composition, interdite en
écriture).

**LE PLAFOND EST DU CÂBLAGE** : la capacité est posée sur le canal mais
n'est JAMAIS lue par le mécanisme — rien dans le cœur ne borne le haut d'une
réserve. Le surplus est PERDU, et c'est visible.

**Testé par** : `scripts/test_banc_fertilite.gd`.

---

### `scripts/banc_erosion.gd`

**Montre** : le sol PART et se DÉPOSE — il ne disparaît jamais. Le compteur
de sol total est la preuve VISIBLE de la conservation. Deux érosions
distinctes : par l'eau (entraînement) et par le vent (orienté).

**Compose** : `ecoulement.gd`, `consommer.gd`, `vent.gd`, `etat_effectif.gd`
— tous inchangés.

**L'ÉROSION PAR L'EAU REJOUE LES TRANSFERTS DÉJÀ CALCULÉS**, dans le même
sens, sur une autre réserve. Un second appel à l'écoulement avec la réserve
de sol aurait COMPILÉ mais appliqué une loi FAUSSE : la hauteur effective
inclut la réserve, donc le sol coulerait de sa propre gravité — de la boue,
pas de l'érosion.

**L'ÉROSION PAR LE VENT APPARIE DEUX VOISINS PAR UN VECTEUR**, ce qu'AUCUN
mécanisme du dépôt ne sait faire (l'écoulement n'apparie que par comparaison
d'altitude). SI CE GESTE DOIT DURER, c'est un mécanisme du cœur neuf — à
trancher par Yael, pas ici.

**GATE « SOUS LE VENT », décision Yael** : le facteur directionnel ne rend
JAMAIS une valeur nulle ni négative, donc un test sur le signe serait TOUJOURS
vrai et le sol partirait aussi CONTRE le vent — une diffusion isotrope, pas
une érosion orientée. Le test porte donc sur le point neutre, strictement
équivalent à « dans le sens du vent ET vent non nul » par construction de la
formule.

**Testé par** : `scripts/test_banc_erosion.gd`.

---

### `scripts/banc_ombre_pluvio.gd`

**Montre** : il pleut moins derrière la montagne. Devant le relief l'humidité
décroît avec la distance ; derrière, elle est GRADUÉE — la case sur l'axe du
sommet est la plus sèche, celles d'à côté le sont moins, celles qui sortent
du cône ne le sont pas du tout. GRADUÉ, JAMAIS UNE COUPURE : la case la plus
à l'ombre garde une humidité strictement positive.

**PREMIÈRE ET SEULE démonstration de `champ_occulte.gd`** (et par lui de
`occlusion.gd`), tous deux nés de ce chantier.

**Les cases ne sont enregistrées dans AUCUN monde** : un simple Array passé
directement au mécanisme — c'est ce qui évite le coût cubique par tick que
l'audit chiffrait si chaque case avait dû devenir un percepteur.

**NORMALISATION EN DONNÉE** : le facteur d'occlusion est borné, donc une
altitude brute clamperait au maximum — BLOCAGE TOTAL, aucune gradation.
Chaque case porte donc, à côté de son altitude réelle, sa normalisation.

**PROFIL DE MONTAGNE, JAMAIS UN MUR** (décision de ce chantier, absente de la
consigne — sans elle l'ombre est plate) : un sommet encadré de deux épaules.
C'est cet écart qui gradue l'ombre ligne par ligne.

**LE VENT EST UN DÉCOR, et rien d'autre** — dit plutôt que masqué : la flèche
est lue en donnée, ce banc n'appelle JAMAIS `vent.gd` et le vent n'entre dans
AUCUN calcul. Une humidité portée par le vent serait un autre chantier.

**Testé par** : `scripts/test_banc_ombre_pluvio.gd`.

---

### `scripts/banc_biomes.gd`

**Montre** : la RÉVERSIBILITÉ — ce que le banc d'émergences ne pouvait pas
montrer, son évaluation n'ayant lieu qu'à la fabrication. Une grille à deux
axes croisés (humidité en colonnes, température en lignes) fait apparaître
les cinq rendus dès le démarrage ; refroidir puis rendre le climat ramène une
case EXACTEMENT à son biome d'origine.

**Compose** : `conditions.gd` REJOUÉ À CHAQUE TICK avec retrait — inchangé.

**LE CLIMAT NE DÉRIVE JAMAIS** : chaque case garde ses valeurs de BASE,
jamais mutées ; l'effective est recalculée chaque tick comme base + décalage
global — jamais un incrément accumulé sur la case, qui aurait fait diverger
les cases entre elles au moindre tick manqué.

**Le CHANGEMENT est lu AVANT/APRÈS sur la case**, jamais déduit de la trace
du mécanisme : celle-ci dit ce qui a été POSÉ, pas si la VALEUR a changé
(reposer le même biome y figure et n'est pourtant pas un changement). Sans
ça, la console imprimerait une ligne par case et par frame.

**CALIBRATION ASSUMÉE, verrouillée par test** : la moitié des cases n'a AUCUN
biome au repos — pas un mauvais réglage, mais la lecture directe des
conditions, qui ne pavent pas tout l'espace climatique. L'absence est rendue
VISIBLE plutôt que comblée par un biome par défaut inventé.

**Testé par** : `scripts/test_banc_biomes.gd`.

---

### `scripts/banc_fatigue_circadien.gd`

**Montre** : la fatigue descend en continu, plus vite si le colon marche ; une
zone circadienne dit quand il DEVRAIT dormir ; dormir la fait remonter ; ne
pas dormir accumule une DETTE. Un colon blessé récupère sa santé sans que sa
fatigue en profite.

**Compose** : `depense.gd`, `velocite.gd`, `seuil_etat.gd`, `conditions.gd`,
`charge.gd`, `etat_duree.gd`, `etat_effectif.gd` — tous inchangés.

**LA FATIGUE EST UNE RÉSERVE, PAS UNE CHARGE** — tranché par la doctrine : le
sommeil est l'un des canaux physiologiques du paquet dynamique. Le sommeil
pose un coût NÉGATIF sur le même canal : la réserve remonte, neutralité du
mécanisme exploitée.

**UN SEUL ÉCRIVAIN pour les deux canaux** (sommeil et santé), et c'est la
réponse au piège nommé par l'audit : un canal n'a qu'UN emplacement de
surcoût, deux morceaux de câblage qui y écrivent se détruisent EN SILENCE.

**LA ZONE ENJAMBE MINUIT, donc ce n'est PAS un seuil** : « après 16 h OU
avant 8 h » s'écrit en DEUX entrées de conditions posant TOUTES DEUX la même
clé, jouées avec retrait — exactement ce que les DEUX PASSES DISJOINTES du
mécanisme rendent sûr. Premier cas réel où deux entrées vraie/fausse se
croisent sur la même clé au même tick.

**LA DETTE EST UNE CHARGE À CAUSE SYNTHÉTISÉE** : la cause est le colon
LUI-MÊME, à portée nulle — elle ne peut donc alimenter QUE lui. LIMITE DITE :
deux colons SUPERPOSÉS se chargeraient mutuellement ; les positions déclarées
sont distinctes.

**BLESSÉ ≠ REPOS, ET C'EST STRUCTUREL** : santé et sommeil sont deux canaux
du MÊME Dictionary, avancés par la même boucle sans qu'aucun ne connaisse
l'autre. Le gate de blessure n'écrit QUE dans la santé : la fatigue est
intouchée par construction, pas par précaution.

**Testé par** : `scripts/test_banc_fatigue_circadien.gd`.

---

### `scripts/banc_faim_thermo.gd`

**Montre** : un colon qui marche sans rien à manger. Son énergie part en
métabolisme de base, en effort de marche (proportionnel à sa vélocité réelle)
et en lutte thermique (proportionnelle à l'écart au confort). Zone froide,
zone chaude, neutre entre les deux.

**UNE SEULE ÉCRITURE DE SURCOÛT PAR TICK — la raison d'être du banc** : trois
choses veulent y écrire, et il n'y a QU'UN emplacement par canal. Trois
morceaux séparés se détruiraient EN SILENCE — aucun test ne rougirait, la
dépense serait seulement fausse. Une seule fonction somme puis écrit une
fois, et rend la DÉCOMPOSITION que l'affichage relit sans rien recalculer.

**TROIS MIROIRS PLATS, et pourquoi ils sont obligatoires** : le seuil ne lit
qu'une clé PLATE et ne compare que vers le HAUT — « l'énergie descend sous un
seuil » n'est pas exprimable. Le câblage écrit donc chaque tick le manque et
les deux écarts ressentis.

**CES TROIS MIROIRS SONT RÉVERSIBLES**, contrairement à toutes les grandeurs
cumulées du dépôt : recalculés à neuf chaque tick, jamais accumulés. C'est ce
qui rend les quatre états réversibles sans une ligne de plus, et ce qui donne
le PREMIER escalier à deux étages sur une grandeur qui REDESCEND — les deux
états se posent dans un ordre et se retirent dans l'ordre INVERSE.

**JAMAIS UN `abs()` UNIQUE** (question laissée ouverte par l'audit, tranchée
ici) : le froid bascule sous une cible, le chaud au-dessus d'un AUTRE seuil —
deux nombres, deux coûts par degré. Tant que le second reste au-dessus du
premier, les deux miroirs ne sont jamais non nuls ensemble.

**LA TEMPÉRATURE DE CONFORT N'EST PAS CELLE D'UN CORPS** (écart assumé à
l'audit) : prendre une température corporelle aurait rendu le colon
hypothermique PARTOUT, y compris au cœur de la zone chaude, et le banc
n'aurait plus rien montré.

**L'ARRÊT FINAL EST UN GATE DE CÂBLAGE, PAS UN ÉTAT** : réserve à zéro →
vitesse effective nulle. Aucun état n'a été ajouté au catalogue partagé — un
état de plus se paie pour tout le dépôt.

**Testé par** : `scripts/test_banc_faim_thermo.gd`.

---

### `scripts/banc_hygiene_apparence.gd`

**Montre** : la perception SOCIALE. Une réserve d'hygiène descend ; sous un
seuil le colon devient sale ; les autres le FUIENT — mais seulement à partir
d'une distance qui n'est pas celle où ils le PERÇOIVENT. Un clic le lave, et
l'état se retire au tick suivant.

**Compose** : `depense.gd`, `seuil_etat.gd`, `perception.gd`, `proximite.gd`,
`dominance.gd`, `fuite.gd` — tous inchangés.

**LE MIROIR PLAT DES ÉTATS EST OBLIGATOIRE, pas un confort** : `agir.gd`
scanne les clés du catalogue d'actions contre les propriétés PLATES de la
chose, JAMAIS contre les états actifs où le seuil écrit. Sans le miroir,
l'état ne résoudrait aucun verbe et personne ne fuirait.

**DEUX CANAUX NEUFS EN DONNÉE PURE** : une odeur (qui CONTOURNE un mur) et
une apparence (qu'un mur BLOQUE totalement). L'odorat n'a PAS été touché : sa
géométrie porte SEULE la modulation par le vent et ne lit ni propriété
d'émission ni seuil — la basculer aurait retiré le vent à l'odorat en
silence, dans un catalogue partagé.

**LES COLONS NE PORTENT QUE CES DEUX CANAUX** : la liste héritée est
REMPLACÉE. Raison mesurable : la vue a une portée immense et aucun filtre
d'intensité — laissée en place, tout colon capterait tout colon à toute
distance et ni l'odeur ni le seuil ne prouveraient plus rien.

**CONSTAT MESURÉ — CE QUI BORNE RÉELLEMENT LA FUITE** : une entrée ne peut
être fuie que si elle SURVIT à la couche de proximité, qui l'exclut dès que
sa saillance tombe à zéro. Le colon attentif PERÇOIT donc le colon sale bien
au-delà de la distance à laquelle il le FUIT — c'est la portée de saillance
qui borne, jamais la perception.

**LE COLON BLESSÉ N'EST JAMAIS FUI** : son état n'a AUCUNE entrée dans le
catalogue d'actions, donc aucun verbe ne s'y résout. Il reste parfaitement
perçu. La différence entre « remarqué » et « fui » tient à UNE ligne de
donnée.

**Testé par** : `scripts/test_banc_hygiene_apparence.gd`.

---

### `scripts/banc_nutrition.gd`

**Montre** : TROIS RÉSERVES DE NUTRIMENT EN PARALLÈLE, chacune à sa vitesse —
le gras cale longtemps, le sucre redescend vite. Sous une somme critique, le
colon devient malnutri et sa vitesse chute ; le nourrir le répare.

**Rien de neuf n'a été écrit pour les trois réserves** : `depense.gd` boucle
déjà sur TOUTES les réserves d'une chose et avance chaque canal avec son
propre coût. Trois nombres en donnée suffisent.

**UNE CAUSE SYNTHÉTISÉE, À DISTANCE ZÉRO** : `charge.gd` ne lit jamais une
réserve et ne scanne jamais le monde. Le câblage met le colon lui-même comme
cause dès que la somme passe sous le seuil : son état interne devient sa
propre cause. PREMIÈRE cause du dépôt qui ne vient pas d'une AUTRE chose —
le chemin `distance <= 0.0` était signalé par l'audit comme jamais exercé.

**LE CÂBLAGE RETIRE L'ÉTAT LUI-MÊME** : l'état de malnutrition n'a PAS de
durée (elle s'arrête quand on remange, jamais après N secondes), donc il
n'entre jamais dans le suivi d'intensité et `etat_duree.gd` ne le retirera
JAMAIS. Le seul retrait possible est le MIROIR EXACT du marqueur que
`charge.gd` retire au franchissement descendant.

**C'EST LE MATÉRIAU QUI NOMME LA RÉSERVE RÉCEPTRICE, jamais le code** : le
type de nutriment est une String, donc jamais fusionnable (la fusion est une
moyenne pondérée). Un type qui ne désigne aucune réserve du colon est une
anomalie STRUCTURELLE — laisser faire aurait fait créer silencieusement une
quatrième réserve sans coût, qui ne redescendrait jamais.

**Testé par** : `scripts/test_banc_nutrition.gd`.

---

### `scripts/banc_elimination_salete.gd`

**Montre** : un besoin qui MONTE, des déchets qui s'accumulent au sol, et la
maladie qui en découle. Le colon qui mange le plus élimine deux fois plus
souvent. Un clic nettoie.

**Compose** : `depense.gd`, `seuil_etat.gd`, `objet.gd`, `monde.gd`,
`charge.gd`, `etat_duree.gd`, `etat_effectif.gd` — tous inchangés.

**LES DÉCHETS SONT DE VRAIS OBJETS FABRIQUÉS EN COURS DE PARTIE** : c'est la
seule façon d'obtenir leur propriété depuis le catalogue matériau sans
recopier le nombre dans le câblage.

**LE BESOIN MONTE PAR UN COÛT NÉGATIF**, base et surcoût, ce dernier réécrit
chaque tick depuis le taux de repas — un seul écrivain pour les deux champs.

**MIROIR NON INVERSÉ ici**, contrairement aux autres bancs : la réserve MONTE
déjà et le seuil compare vers le HAUT.

**DIFFÉRENCE VOULUE AVEC LE BANC DE MALADIE, et sa conséquence** : là-bas le
canal receveur est retiré au contaminé pour toujours. Ici il RESTE à vie —
sans lui, la charge ne pourrait plus jamais redescendre et « nettoyer fait
redescendre la saleté » serait infaisable. Conséquence assumée, c'est même le
sujet : un colon guéri qui repasse dans un tas retombe malade. La garde
contre une double incubation n'est donc pas le retrait du canal mais un gate
de câblage.

**DEUX RÉSULTATS NÉGATIFS MESURÉS, à ne pas refaire** : (1) la calibration
d'origine exposait le premier colon à ses DEUX PROPRES déchets avant qu'un
tas soit visible, et tuait les trois avant que le nettoyage ait servi ; (2) un
colon MORT continuait d'éliminer — INVISIBLE au test, trouvé en lançant,
fermé par un gate sur les deux coûts.

**Testé par** : `scripts/test_banc_elimination_salete.gd`.

---

### `scripts/banc_graisse_accoutumance.gd`

**Montre** : le surplus d'énergie se stocke en graisse, la famine la brûle,
et l'exposition répétée au froid rend le colon MOINS sensible au froid.

**Compose** : `consommer.gd`, `depense.gd`, `seuil_etat.gd`,
`etat_effectif.gd`, `epigenetique.gd` — tous inchangés.

**CE QUE CE BANC PROUVE ET QUE RIEN D'AUTRE NE PROUVAIT** : `consommer.gd`
appelé avec LA MÊME ENTITÉ comme source ET comme receveur, deux réserves du
même colon. Aucun appelant ne le faisait. Il fonctionne parce que les deux
opèrent sur des CLÉS DIFFÉRENTES du même Dictionary : aucun aliasing.

**PAS DE PRÉ-BORNAGE DANS LE SENS FAMINE, et c'est la CONTRE-ÉPREUVE** de la
correction du mécanisme : trois appelants avaient dû se pré-borner pour se
protéger d'un défaut depuis fermé. Ici le taux est demandé NU et le mécanisme
borne — le test vérifie que la somme des deux réserves est invariante quand
la demande dépasse la graisse.

**PLAFOND SUR LE MODULATEUR, CONDITION DE CORRECTION** : `epigenetique.gd`
n'a AUCUNE borne haute ; au-delà de l'unité, le facteur devient négatif et le
froid RECHARGERAIT le colon.

**CONTRAINTE DE CADENCE, RÉSULTAT NÉGATIF À NE PAS REFAIRE** : une marque
fraîche tombe sous son plancher de suppression en une fraction de seconde. Un
câblage qui pose à un intervalle supérieur n'accumule donc JAMAIS rien, et
rien ne rougit. L'inégalité ET sa contre-épreuve sont verrouillées contre les
nombres réels du disque. Poser à CHAQUE IMAGE échappe à la contrainte mais
rend la montée dépendante de la machine et sature en une seconde.

**LA MORT EST RÉVERSIBLE PAR CONSTRUCTION ICI, et c'est dit** : son miroir
est sous gate, donc recalculé — contrairement aux morts assises sur des
grandeurs monotones. Elle n'est définitive que parce que rien ne ressuscite
ni ne nourrit un mort.

**Testé par** : `scripts/test_banc_graisse_accoutumance.gd`.

---

### `scripts/banc_bonheur.gd`

**Montre** : quatre colons, MÊMES sources posées aux MÊMES niveaux au même
instant — rien dans le monde ne les distingue, et ils ont pourtant quatre
bonheurs et jusqu'à trois états différents. Couper une source n'affecte que
ceux qui la valorisent.

**LE BONHEUR EST UN CHAMP DÉRIVÉ, PAS UNE RÉSERVE** : il ne vit dans aucun
canal. Le câblage le RECALCULE À NEUF chaque tick et l'écrit par-dessus,
JAMAIS par incrément. Ce n'est pas un détail de style : c'est la seule chose
qui empêche un champ dérivé de DÉRIVER — le résultat négatif est déjà mesuré
deux fois ailleurs.

**UN SEUL ÉCRIVAIN** pour le champ ET son miroir, dans le MÊME geste, depuis
le MÊME nombre : deux morceaux séparés se seraient désynchronisés EN SILENCE,
et le seuil aurait comparé deux grandeurs qui ne se répondent plus.

**PREMIÈRE GRANDEUR DU DÉPÔT QUI MONTE QUAND LA SITUATION S'AMÉLIORE** :
toutes les autres montent quand elle empire, d'où leurs miroirs INVERSÉS.
L'état haut compare donc la valeur DIRECTEMENT ; le miroir ne sert ici qu'à
retourner le SENS pour les deux états bas, jamais à atteindre une réserve
enfouie — la valeur est déjà une clé plate.

**LES TEMPÉRAMENTS SONT DES POIDS, JAMAIS DES CATÉGORIES** : le fichier ne
connaît aucun nom de tempérament, il boucle sur un Dictionary porté par
chaque colon. Un cinquième tempérament est une entrée de donnée, zéro ligne.

**CE DICTIONNAIRE EST SÉPARÉ DE `poids_verbes`, délibérément** : l'unique
lecteur de `poids_verbes` arbitre des VERBES ; y glisser un poids de bonheur
lui donnerait deux lecteurs sur une clé STRUCTURELLE et ferait entrer une
source de bonheur dans l'arbitrage des verbes — faux positif silencieux le
jour où un verbe porterait le même nom.

**PREMIER ÉTAT DU DÉPÔT QUI ACCÉLÈRE** (facteur au-dessus de l'unité) — tous
les précédents ne savaient que ralentir ou écraser à zéro. LIMITE DITE : la
modulation du rythme n'a d'effet que dans un câblage qui compose lui-même la
valeur effective, ce qu'aucun autre banc ne fait. Dette du câblage existant,
signalée, pas de ce chantier.

**CONTRAINTE DE CALIBRATION verrouillée par test** : capacité moins seuil
haut doit rester sous le seuil bas, sinon un colon serait heureux ET
malheureux en même temps.

**Testé par** : `scripts/test_banc_bonheur.gd`.

---

### `scripts/banc_psycho_social.gd`

**Montre** : quatre lignes qui INTERAGISSENT — l'hésitation entre deux cibles
proches coûte de l'énergie, un besoin critique finit par écraser tout le
reste, une directive du joueur peut être suivie OU désobéie, et le combat
répété rend un colon plus ardent. Livrées ensemble parce que séparées elles
ne rendraient que quatre mécanismes déjà écrits.

**LE CONSTAT QUI DÉCIDE TROIS DES QUATRE LIGNES** : `agir.gd` choisit la
CIBLE au score PUIS le verbe — `poids_verbes` ne pèse donc JAMAIS entre deux
cibles, et un colon mourrait de faim devant un repas. Les deux seules voies
qui pèsent sont `deformation.gd` et une ENTRÉE DE SAILLANCE SYNTHÉTIQUE
ajoutée avant `dominance.gd` ; les deux sont utilisées ici.

**L'ÉCART SE MESURE SUR LA COUCHE 2, JAMAIS SUR CE QUI SURVIT À DOMINANCE** :
celle-ci a DÉJÀ retiré tout ce qui dépasse l'écart d'écrasement, un écart
supérieur n'y serait donc jamais mesurable. DÉDUPLICATION PAR CIBLE, décision
de ce chantier : deux entrées peuvent porter LA MÊME chose (sa saillance
naturelle et l'entrée synthétique de la directive) — sans elle, un colon
« hésiterait entre le feu et le feu ».

**LA DIRECTIVE EST UNE SAILLANCE CONCURRENTE, PAS UN BONUS ADDITIF** :
`agir.gd` retient le MEILLEUR score, il n'additionne pas — la directive doit
DÉPASSER le sommet naturel pour être suivie. **La désobéissance est donc
prouvée DEUX FOIS, par deux chemins indépendants** : par le POIDS (l'entrée
est ajoutée mais la faim pèse plus) et par un GATE PAR ÉTAT (l'entrée n'est
même pas construite).

**LA SIGMOÏDE EST DE L'ARITHMÉTIQUE DE CÂBLAGE**, zéro mécanisme neuf — elle
pilote la magnitude posée, MULTIPLIÉE PAR LE DELTA (le mécanisme n'a aucun
paramètre de temps, un montant fixe par image dépendrait de la machine) et
BORNÉE par un plafond de câblage, sans quoi le registre monterait
LINÉAIREMENT ET SANS BORNE.

**UN SEUL ÉCRIVAIN DE SURCOÛT, et sa CONTRE-ÉPREUVE VIVANTE** : quand le
combat a dû coûter de l'énergie, il a été AJOUTÉ à cette fonction (un
paramètre de plus) plutôt que de recevoir son propre point d'écriture —
exactement le geste que le patron impose, et le refaire l'a validé.

**DÉFAUT RÉEL TROUVÉ EN LANÇANT, invisible au test** : le miroir d'ardeur,
écrit inconditionnellement, mettait le vétéran en colère dès le premier
dixième de seconde SANS AUCUN ADVERSAIRE, et comme le combat lit cet état il
accumulait de l'expérience en permanence sans jamais se rouiller. Gaté sur la
décision de combat.

**SECOND DÉFAUT, mesuré en observant la scène** : sans effet derrière le
verbe, le colon arrivait sur l'allié et y restait PLANTÉ ; et l'adversaire,
trop saillant, faisait mourir de faim les deux colons collés à lui. Ce trou
était invisible au test, qui mesurait tout au point de départ, STATIQUEMENT,
sans jamais faire avancer le colon dans le temps. Soigner et combattre ont
donc un effet — et leurs mécanismes DIFFÈRENT délibérément : soigner
TRANSFÈRE (conservatif), combattre DÉTRUIT (la vigueur ne va nulle part) —
un transfert aurait signifié « combattre nourrit le vainqueur ».

**DEUX RETRAITS POUR SORTIR DE LA DÉCISION, et il faut les deux** : la
propriété sort des propriétés (sinon le verbe se résout encore sur un allié
guéri) ET le profil de saillance est GELÉ (sinon il reste saillant et le
colon reste planté sur quelqu'un qu'il ne peut plus aider).

**LIMITE QUI RESTE** : un verbe n'a toujours aucun effet, et les colons
campent près de la nourriture — le motif « planté » n'a pas disparu, il s'est
déplacé sur une cible qui, elle, a un effet.

**Testé par** : `scripts/test_banc_psycho_social.gd`.

---

### `scripts/banc_menace_combat.gd`

**Montre** : une menace produit peur OU colère selon le TEMPÉRAMENT. Trois
colons, MÊME code, MÊMES ennemis : seul leur biais les sépare. Le lâche a
peur dès un rapport de forces faible, l'agressif seulement très au-delà,
l'équilibré bascule EXACTEMENT à l'égalité.

**PREMIER APPELANT RÉEL de `bifurcation.gd`**, livré sans appelant par un
chantier précédent.

**LE SCORE DE MENACE multiplie trois grandeurs qui ne se ressemblent pas** :
géométrie (distance), rapport d'effectifs (deux comptages et une division),
et VISIBILITÉ (occlusion continue). SOMMÉ sur tous les ennemis perçus —
décision de ce banc, absente de la consigne : quatre ennemis doivent stresser
plus que deux, un maximum ne le rendrait jamais.

**LE BIAIS PASSÉ EST COMPOSÉ, pas brut** — sans quoi « l'équilibré dépend du
rapport de forces » serait infaisable : la grandeur du mécanisme est un
SCALAIRE COMMUN, elle ne peut JAMAIS départager deux biais. Le câblage
compose donc lui-même.

**IL FAUT LES DEUX GESTES, et c'est le constat central** : une saillance
amplifiée ne fait JAMAIS gagner un verbe, et un poids de verbe ne fait JAMAIS
gagner une cible. La déformation seule aurait produit un colon qui fonce sur
ce qu'il craint ; le poids seul, un colon qui fuit un ennemi qu'il ne regarde
même pas.

**LE PALIER DE DÉPART N'EST JAMAIS À L'ÉGALITÉ EXACTE** : à ce point précis,
l'équilibré tomberait sur une ÉGALITÉ STRICTE de produits, que le mécanisme
refuse de trancher — et alarmerait à chaque tick.

**UN SEUL ÉCRIVAIN DE `poids_verbes`**, réécrit EN ENTIER chaque tick depuis
la donnée, jamais par incrément.

**LA PROBABILITÉ DE FUITE EST LUE, JAMAIS TIRÉE AU SORT** : l'état de colère
l'ÉCRASE à zéro, et le câblage n'entre dans sa branche de fuite que si elle
est strictement positive — gate DÉTERMINISTE, aucun RNG. Sans cette lecture
explicite, déclarer l'effet dans le catalogue n'aurait STRICTEMENT rien
produit.

**Testé par** : `scripts/test_banc_menace_combat.gd`.

---

### `scripts/banc_grief.gd`

**Montre** : un grief qui monte sous l'injustice et redescend sous
l'amélioration ; au seuil, trois colons de MÊME grief et MÊME seuil partent
dans trois directions différentes — seul leur biais les sépare.

**PREMIER CUMUL DU DÉPÔT QUI REDESCEND** : les grandeurs comparées par le
seuil étaient jusqu'ici soit accumulées et monotones, soit recalculées à neuf.
Celle-ci est les deux — elle accumule ET redescend, bornée à zéro par le
câblage. Rien dans le mécanisme ne s'y oppose : il ne fait que comparer.

**DEUX ÉTATS DISTINCTS, jamais confondus** : une entrée de seuil pose UN nom
et ne sait pas choisir entre trois sorties. D'où un MARQUEUR PUR qui ne fait
qu'OUVRIR LA PORTE, puis la bifurcation qui pose la sortie retenue.

**TROIS ÉCARTS À LA CONSIGNE, constatés sur le disque AVANT d'écrire** :
(a) « ne pas utiliser le champ d'état » n'est PAS exprimable — le mécanisme
l'EXIGE ; traduit par le marqueur pur. (b) Le sens de déformation demandé
N'EXISTE PAS, et n'aurait rien pu faire : une entrée de directive est
SYNTHÉTIQUE, construite par le câblage — elle ne traverse JAMAIS la couche de
proximité, donc aucune déformation ne peut la moduler. Retenu à la place : le
GATE PAR ÉTAT, patron déjà écrit. (c) L'état de départ écrase la vitesse à
zéro — un colon censé partir en serait CLOUÉ AU SOL : le mouvement de sortie
passe par une propriété SÉPARÉE.

**PIÈGE TENU PAR UNE CHAÎNE ENTIÈRE** : déclarer que l'état module le rythme
ne suffit JAMAIS — le rythme est lu BRUT par les agents de chantier. Le
câblage compose lui-même la valeur effective avant de s'en servir, sinon la
modulation serait vraie dans le catalogue et sans le moindre effet, EN
SILENCE.

**ORDRE DU TICK NON INTERCHANGEABLE** : le grief bouge, PUIS le seuil
tranche, PUIS la bifurcation pose, PUIS les effets agissent. Inverser deux
étapes ferait bifurquer sur le marqueur du tick PRÉCÉDENT. La bifurcation ne
se rejoue pas tant que le seuil reste franchi : sans cette garde, les états
s'empileraient à chaque image.

**Testé par** : `scripts/test_banc_grief.gd`.

---

### `scripts/banc_croyance.gd`

**Montre** : les quatre couches décident sur une COPIE, plus sur le monde. Un
colon agit sur une information FAUSSE sans aucune branche spéciale : le fruit
devient toxique, il continue de le manger parce que sa croyance dit
« comestible ». Un dogmatique refuse toute correction — et ce qui le sépare
des trois autres est UN NOMBRE, jamais un état posé en dur.

**PREMIER APPELANT RÉEL de `croyance.gd`** ; la chaîne réelle tourne, et les
quatre dernières couches ne voient JAMAIS l'objet réel.

**DEUX REFUS DISTINCTS, jamais confondus** : sous un seuil de crédibilité, le
CÂBLAGE renonce et n'appelle même pas la correction (« je ne t'écoute pas ») ;
au-delà, il appelle et c'est le MÉCANISME qui refuse si la certitude a franchi
la résistance (« je t'écoute, mais je sais mieux »). Les deux sont détectés
par DIFFÉRENCE D'ÉTAT, jamais en recopiant un seuil.

**LA CRÉDIBILITÉ EST CÂBLÉE, JAMAIS INVENTÉE** : c'est la force du lien
personnel vers l'émetteur — un autre colon EST une chose, le registre porte
déjà cette force.

**DEUX CADENCES PAR COLON, cœur de la calibration** : le mécanisme n'a aucune
notion de temps propre, donc observer à chaque image porterait la certitude
au plafond en quelques images et rendrait tout le monde dogmatique avant la
première seconde.

**LE FRUIT TOXIQUE PERD LA CLÉ, il ne la met pas à faux** — structurel :
l'observation n'itère que les propriétés PRÉSENTES, une clé retirée n'est
donc jamais réobservée et la croyance périmée SURVIT. Symétriquement, la
toxicité n'est pas observable : on ne VOIT pas qu'un fruit est toxique, on
l'apprend en y goûtant.

**Ce que le banc NE fait pas, dit plutôt que masqué** : les colons ne bougent
pas — les faire marcher vers le fruit les mettrait tous au contact, donc tous
corrigés par l'expérience directe, et il n'y aurait plus rien à transmettre.

**Testé par** : `scripts/test_banc_croyance.gd`.

---

### `scripts/banc_memoire_navigation.gd`

**Montre** : le carré de la position RÉELLE et celui de la position MÉMORISÉE
se SÉPARENT dès que la cible sort de portée de vue, et le colon marche vers
le SOUVENIR. C'est exactement ce que le dépôt ne savait pas faire :
l'attraction rendait déjà une cible hors perception, mais à sa position
réelle relue vivante — donc suivie par télépathie.

**Compose** : `memoire_spatiale.gd` (neuf), `perception.gd`, `horloge.gd`,
`lumiere.gd`, `monde.gd` — les quatre derniers inchangés.

**PREMIER BANC APPELANT `horloge.gd`** — celui qui a fait franchir le seuil
qu'un autre avait nommé sans le franchir. La durée du jour vaut ZÉRO : point
LÉGITIME et documenté du mécanisme (le temps du monde est arrêté). Ce n'est
PAS un contournement — l'erreur a DEUX causes, mémoire faible et obscurité,
et le banc existe pour les SÉPARER : une heure qui dérive ferait varier la
luminosité sous chaque mesure.

**LE PLAFOND DE FORCE EST DU CÂBLAGE, et son ORDRE compte** : mémoriser est
appelé CHAQUE TICK tant que la cible est vue — il le faut pour que la
POSITION reste fraîche — donc la force monterait sans fin. Écrêter la FORCE
plutôt que sauter l'appel est le seul ordre correct : gater l'appel figerait
aussi la position, et une cible qui bouge sous les yeux du colon ne serait
plus jamais mise à jour, EN SILENCE.

**SEULE L'HORLOGE DE L'OUBLI ACCÉLÈRE** : le delta multiplié n'est passé
qu'au mécanisme de mémoire, jamais au déplacement ni à la perception — sinon
le colon traverserait l'écran et la dérive ne se verrait plus.

**Souvenir retiré sous le plancher : le colon S'ARRÊTE**, il ne fonce jamais
sur l'origine — ne pas savoir n'est pas savoir mal.

**LIMITE DITE** : aucune couche de saillance n'est montée. Brancher le
souvenir sur la couche 2 (un candidat à position MÉMORISÉE là où l'attraction
en rend un à position RÉELLE) est le chantier SUIVANT — il touchera le cœur,
il ne se bricole pas ici au passage.

**Testé par** : `scripts/test_banc_memoire_navigation.gd`.

---

### `scripts/banc_stress_thermo_vivant.gd`

**Montre** : quatre vivants, quatre sources de stress indépendantes (froid,
chaud, sécheresse, excès d'eau). Une plante stressée pousse RÉELLEMENT deux
fois moins vite ; au-delà d'un seuil elle meurt et ne pousse plus du tout.

**LE PATRON DU BONHEUR REJOUÉ, ET EN PLUS SIMPLE** : même boucle sur un
Dictionary de poids porté par chaque entité, sans connaître un seul nom de
source. Mais là où le bonheur MONTE quand la situation s'améliore — d'où son
miroir inversé —, le stress MONTE quand elle empire : **la comparaison vers
le HAUT tombe juste SANS AUCUN MIROIR.** Première grandeur du dépôt dans ce
sens.

**QUATRE SOURCES, PAS TROIS, et c'est un écart à la consigne** : la
quatrième est ajoutée par ce chantier — sans elle « l'arctique meurt de
chaud » est infaisable. Elle coûte ZÉRO ligne de code : la liste des sources
est de la donnée pure.

**JAMAIS UN `abs()`, ET DEUX FOIS PLUTÔT QU'UNE** : la décision déjà prise
pour la température est ÉTENDUE ici à l'humidité — quatre bascules, quatre
nombres par vivant, quatre poids indépendants.

**LA MORT EST DÉFINITIVE PAR UN GATE DE CÂBLAGE, JAMAIS PAR UN MÉCANISME** :
le stress étant recalculé à neuf, l'état serait RÉVERSIBLE — réchauffer
ferait redescendre le stress et le seuil retirerait la mort. Le calcul cesse
donc dès que l'état est actif, et les coûts sont mis à zéro : un mort ne
dépense plus.

**LE CONSTAT « UN EFFET DÉCLARÉ NE FAIT RIEN » TENU PAR UNE CHAÎNE ENTIÈRE** :
le câblage compose lui-même la valeur effective avant de la passer comme taux
de croissance. Sans cette chaîne, la modulation serait vraie dans le
catalogue et sans le moindre effet.

**AUCUNE CATÉGORIE DANS LE FICHIER** : il ne connaît ni « plante » ni
« animal ». Ce qui sépare les quatre vivants n'est qu'un jeu de propriétés —
qui porte un poids a un stress, qui porte un canal reçoit de l'eau, qui porte
une croissance pousse. Un premier jet nommait les cinq seuils en dur, corrigé
avant d'être laissé en l'état.

**Testé par** : `scripts/test_banc_stress_thermo_vivant.gd`.

---

### `scripts/banc_oubli_consolidation.gd`

**Montre** : **l'oubli est une EXPONENTIELLE, et aucun mécanisme ne le sait.**
Les deux registres de mémoire décroissent par SOUSTRACTION FIXE et lisent
leur taux au catalogue. Le câblage écrit chaque tick, ET PAR SOUVENIR, un
taux proportionnel à la valeur courante : la soustraction fixe devient une
décroissance exponentielle par intégration. Zéro ligne de mécanisme.

**LE POINT TECHNIQUE, qui ne vit nulle part ailleurs — un taux PAR SOUVENIR
sans toucher le cœur**, en deux gestes dont aucun ne recopie une loi : une
VUE par souvenir (le mécanisme est appelé sur un Dictionary jetable ne
portant qu'une entrée, mais cette entrée est LA RÉFÉRENCE réelle du champ,
si bien que la décroissance atteint le vrai registre) ; puis un BALAYAGE À
DELTA NUL sur l'entité réelle, qui ne change aucune valeur mais laisse le
mécanisme appliquer SON PROPRE plancher et SES retraits. Aucun seuil de
suppression n'est donc écrit dans le banc.

**L'ÉMOTION S'ATTACHE AU SOUVENIR, PAS AU COLON** : les états modulent une
charge sur le colon entier, or la ligne demande que la mémoire d'UN objet
décroisse plus lentement, pas toutes. Le câblage FIGE donc la charge
effective au moment de l'observation, dans un registre local, et SEULEMENT
pour les choses portant la propriété visée. Un souvenir reste chargé après
que la peur est retombée : c'est le sujet.

**L'EFFET D'ESPACEMENT est la seule chose que ce banc ajoute à la loi** :
chaque observation monte la certitude ET étire la constante de temps — pas
seulement « j'en suis plus sûr », mais « je l'oublierai moins vite ». Plafond
au câblage, sans quoi le souvenir deviendrait éternel.

**DÉFAUT RÉEL TROUVÉ EN LANÇANT, invisible au test** : la consolidation
itérait le registre SPATIAL, si bien qu'une chose dont la CROYANCE était
tombée sous le plancher voyait quand même sa POSITION reconsolidée chaque
nuit — elle remontait plus qu'elle n'avait décru le jour et devenait un
souvenir IMMORTEL dont le colon ne savait plus rien. Le sommeil ne rejoue
désormais que ce qui est encore CRU.

**L'OUBLI EST EN DERNIER dans l'ordre du pas** : une observation faite ce pas
ne doit pas perdre sa certitude avant d'avoir compté une fois.

**Testé par** : `scripts/test_banc_oubli_consolidation.gd`.

---

### `scripts/banc_ecosysteme_terrain.gd`

**Montre** : un refuge cache UNE proie et pas toutes ; une population se
régule par la capacité de charge de son biome ; un prédateur adapte son
territoire à la densité de proies.

**LE REFUGE : la voie retenue et les DEUX voies FAUSSES** — (a) moduler la
PORTÉE du prédateur le rendrait aveugle à TOUT, y compris à découvert, car la
portée est lue sur le PERCEVANT jamais sur la chose perçue ; (b) un état qui
modulerait la saillance serait vrai dans le catalogue et sans le moindre
effet, la couche de proximité lisant ce nombre dans le CATALOGUE et
n'appelant jamais `etat_effectif.gd`. La voie tenue est un ÉCRIVAIN UNIQUE de
la clé plate de profil, qui bascule entre deux profils déclarés.

**CE QUI EXCLUT RÉELLEMENT LA PROIE CACHÉE n'est PAS la couche de proximité**
(elle n'exclut qu'une saillance nulle ou une portée dépassée) **mais le SEUIL
DE DÉCISION du prédateur, au câblage** : une proie cachée plafonne sous ce
seuil À TOUTE DISTANCE, y compris collée au prédateur.

**PREMIER ÉCRIVAIN DYNAMIQUE de la config de canaux du dépôt** : rien dans le
cœur ne s'y oppose, mais aucun banc ne le faisait. LE PIÈGE, nommé par
l'audit et fermé : « rayon = base / densité » où la densité serait mesurée
DANS CE MÊME rayon est une BOUCLE. Deux gardes STRUCTURELLES : le rayon
d'échantillonnage est FIXE, et le territoire est recalculé À NEUF depuis sa
base — jamais depuis la portée courante.

**LES COLLECTIFS N'EXISTENT PAS, littéralement** : aucune case ne porte de
réserve de population. Chaque animal a SA réserve, meurt SEUL, et la
population est un comptage refait à neuf chaque tick.

**RÉSULTAT NÉGATIF TROUVÉ EN LANÇANT, invisible au test** : la chasse passait
AVANT la dépense. La proie était vidée puis son coût NÉGATIF la remplissait
dans le MÊME tick ; elle se stabilisait et NE MOURAIT JAMAIS, pendant que le
prédateur perdait de l'énergie EN CHASSANT une proie qu'il ne pouvait pas
achever. Rien ne rougissait : les deux mécanismes faisaient exactement ce
qu'ils promettent, c'est leur ORDRE qui était faux.

**ORDRE DU TICK NON INTERCHANGEABLE**, quinze étapes, dont trois inversions
seraient fausses (surpeuplement avant surcoût, territoires avant perception,
dépense avant chasse).

**Testé par** : `scripts/test_banc_ecosysteme_terrain.gd`.

---

### `scripts/banc_parasites_reproduction.gd`

**Montre** : PREMIER banc à faire tourner DEUX CYCLES DE VIE COMPLETS en même
temps, sur deux espèces à modes de reproduction DIFFÉRENTS. La population
naît, vieillit, se réinfeste et meurt en continu.

**DEUX ESPÈCES, UN SEUL CODE, ZÉRO BRANCHE** : ce qui les sépare tient à DEUX
ABSENCES de propriété, jamais à un test de type — l'une ne porte pas le canal
d'infestation (le mécanisme la saute, et l'entrée de seuil est pour elle un
chemin mort), l'autre ne porte pas de seuil de longévité (l'entrée replie sur
l'infini et ne se déclenche jamais). Les deux entrées coexistent dans le même
catalogue sans jamais se croiser, par la seule arithmétique.

**CE QUE LE CÂBLAGE VIDE EN PLUS, et qui n'était dit nulle part** :
l'accumulateur d'accouplement des deux parents. Le mécanisme n'a AUCUNE
décroissance — son accumulation est irréversible par construction. Sans ce
vidage, une gestation retirée est REPOSÉE au tick suivant, le couple pond en
rafale, et le couplage que le banc existe pour montrer serait faux, tous
tests verts.

**CINQ DÉFAUTS TROUVÉS EN LANÇANT, aucun visible à l'écriture** :
- CAPACITÉ DE CHARGE ABSENTE : un gate sur un nombre ABSOLU ne freine rien —
  chaque parasite pond indépendamment, les deux populations croissent
  exponentiellement, et la suite de tests a réellement PENDU dessus. Remplacé
  par un RATIO côté parasite et un plafond de voisinage côté hôte : freiner
  les seuls parasites aurait déplacé l'explosion sur l'autre espèce.
- UN PORTEUR S'INFESTAIT LUI-MÊME : devenu contagieux, il est une cause à
  distance ZÉRO de lui-même, et le mécanisme somme toutes les causes à portée
  sans savoir laquelle est la chose qu'il traite. Sa charge ne redescendait
  jamais.
- COLLISION D'ID entre les petits et les individus de départ : le monde
  refuse un id déjà présent et la chose n'était PAS enregistrée, en silence.
- UN CADAVRE PONDAIT : la liste des vivants est figée en tête de tick, les
  morts posés en cours de tick y figurent encore.
- TEST TROP FAIBLE, corrigé plutôt que masqué : « au moins une mort » était
  VERT alors que les seules morts observées étaient de VIEILLESSE.

**Testé par** : `scripts/test_banc_parasites_reproduction.gd`.

---

### `scripts/banc_predation.gd`

**Montre** : L'ORCHESTRATEUR, et c'est tout ce qu'il est. Les mécanismes
existent tous ; ce qui n'existait pas, c'est l'ORDRE FIXE qui les fait tenir
ensemble tick après tick, plus la naissance et le retrait. Une POPULATION qui
naît et meurt EN CONTINU — tous les bancs antérieurs ont un casting fixe.

**Dix-sept appels dans un ordre écrit**, dont TROIS INVERSIONS seraient
fausses : la mort avant le reste (on ne produit pas la carcasse d'un vivant),
la bifurcation avant la déformation (elle vise la cible de la sortie
GAGNANTE), la déformation avant la décision (sinon la saillance amplifiée
n'agit qu'au tick suivant).

**LA HIÉRARCHIE : les deux voies proposées étaient fausses.** `dominance.gd`
n'élit personne — il ÉCRASE et rend une liste ; le gagnant est choisi par une
fonction privée où le câblage ne peut rien ajouter sans modifier le cœur. Et
la sélection de `frappe.gd` ne connaît que deux sources de critère, aucune
« propriété plate ». La hiérarchie est donc une SOMME PONDÉRÉE recalculée à
neuf : le premier mange, les autres attendent, égalité stricte alarmée. **Et
comme la force est la cible d'un gène, LA HIÉRARCHIE EST HÉRÉDITAIRE sans une
ligne de code pour le dire.**

**L'AGRESSION exige LES DEUX voies** : `charge.gd` SOMME les contributions
(« attaque-t-il ? ») mais la somme efface l'origine ; `bifurcation.gd` prend
l'argmax des MÊMES contributions (« pourquoi ? »). Elles sont calculées UNE
fois et servies aux deux — impossible qu'elles divergent.

**DEUX RÉSULTATS NÉGATIFS MESURÉS, écrits pour ne pas être repayés** :
(1) UN PROFIL DE SAILLANCE NE PEUT PAS SERVIR LES DEUX SENS — une chose n'a
qu'UNE saillance, la même pour tous. Il faut pourtant que le prédateur voie
la proie plus fort que ses congénères ET l'inverse. Première calibration : les
prédateurs se rejoignaient avant d'avoir accumulé assez de charge et ne
chassaient JAMAIS — zéro repas en soixante secondes, tous les cas isolés
restant verts. Fermé en INVERSANT les profils et en ajoutant une déformation
de vigilance, posée INCONDITIONNELLEMENT : la déformation étant PAR
PERCEVANT, c'est la seule voie qui laisse deux espèces lire le même monde
différemment. (2) CE SONT LES DÉLAIS, PAS LES TAUX, QUI FONT LE CYCLE : il
faut que « repas → naissance » tienne DANS l'autonomie sans manger.

**GATE DE MOUVEMENT** : deux propriétés proposent les MÊMES verbes et un
animal n'a qu'un jeu de poids — une proie résoudrait donc la fuite aussi sur
une congénère, et le troupeau se disperserait sans jamais s'accoupler.

**Testé par** : `scripts/test_banc_predation.gd`.

---

### `scripts/banc_temps_anticipation.gd`

**Montre** : deux choses distinctes. Le colon lit le temps dans la FORCE de
ses souvenirs, sans aucune horloge interne — deux repères, l'un resté à
portée reste « récent » pour toujours, l'autre traverse les paliers à mesure
que sa force décroît. **Que le TEMPS ÉCOULÉ soit le même pour les deux est
précisément ce qui prouve que ce n'est pas lui qui est lu.** Et vivre des
saisons rend prévoyant : seul un prévoyant fait monter la saillance du
grenier avant l'hiver.

**DEUX OUTILS ÉCARTÉS, à ne pas reproposer** : `epigenetique.gd` (un appel
par cycle est un intervalle énorme — avec un taux non nul la marque est
effacée entre deux poses et n'accumule JAMAIS rien ; il faudrait un taux nul,
soit l'outil le plus lourd du dépôt pour un simple incrément) et `stade.gd`
(structurellement : il porte la garde « JAMAIS un retour en arrière », or une
saison est CYCLIQUE — ce n'est pas un outil à adapter, c'est un NON-OUTIL).

**LE GATE EST UN ÉTAT, L'AMPLITUDE EST UN COMPTE** : l'état dit SI le colon
anticipe, le compteur dit COMBIEN via le débit posé. Un état ne porte qu'un
nom — il ne sait pas dire « beaucoup plus ».

**POURQUOI LA SAILLANCE PASSE PAR UNE DÉFORMATION et non par un effet d'état**
(écarté, avec sa raison) : la couche de proximité lit la saillance dans le
CATALOGUE, jamais sur l'objet, et n'appelle JAMAIS `etat_effectif.gd` — un
effet déclaré serait vrai dans le fichier et sans le moindre effet dans le
jeu. Et un effet d'état modifie une propriété DU PORTEUR, alors que la
saillance à monter est celle d'une AUTRE chose.

**CONSÉQUENCE À LIRE** : tant que le gate est fermé, le biais du jeune est
EXACTEMENT nul — sa valeur de départ ne lui donne pas un petit biais, elle le
place plus haut sur la MÊME échelle, donc plus près du seuil.

**Testé par** : `scripts/test_banc_temps_anticipation.gd`.

---

### `scripts/banc_temps_vieillissement.gd`

**Montre** : trois choses sur une horloge commune. Une décision prise au
premier tick reste sans aucun signe visible pendant 730 jours simulés, puis
vide six fois plus vite la réserve de celui qui l'a prise. Quatre âges côte à
côte divergent sur DEUX courbes opposées — la force passe par un sommet puis
redescend, le savoir ne redescend jamais. Et deux couples engendrent, chaque
enfant recevant un allèle de chaque parent, une fraction de la marque
maternelle et la moitié du patrimoine.

**LE DÉLAI EST UN ACCUMULATEUR, JAMAIS UN MINUTEUR EMPRUNTÉ. Trois outils
ÉCARTÉS, à ne pas reproposer** : `etat_duree.gd` (son intensité part à 1.0 et
descend — l'inverse exact d'un effet qui attend), `charge.gd` (il ne monte que
tant qu'une cause reste à portée, or le déclenchement doit survenir quoi qu'il
advienne), `gestation.gd` (c'est bien le seul compteur inconditionnel du cœur,
mais tout son vocabulaire désigne la reproduction — l'emprunter nommerait un
concept absent).

**LA COURBE D'ÂGE NE PASSE PAS PAR `expression.gd`** : `exprimer` relit au
chemin ce qu'il vient d'écrire, donc rappelé en boucle il part sans borne.
La force effective est donc réécrite à neuf par-dessus elle-même, depuis
l'âge et une base que plus rien ne retouche. `expression.gd` n'intervient
qu'à la fabrication, pour traduire les allèles. **Verrou NÉGATIF** : le test
relit `avancer_tick` sur le disque et refuse tout appel de ce mécanisme.

**LA MOITIÉ PAR PARENT N'EST PAS RÉGLABLE** — `heredite.gd` tire exactement un
allèle chez chacun, quelle que soit la taille des tableaux parents. Le banc la
rend visible plutôt que déclarée : parents homozygotes de signes opposés,
l'enfant tombe au milieu. Une part différente serait une mécanique neuve du
cœur, pas une ligne de donnée.

**LES DEUX VOIES DE TRANSMISSION DES LIENS TOURNENT ENSEMBLE, la décision
reste ouverte** : une lignée pose sur l'enfant une marque par cible héritée,
sous un gate lu sur le parent ; l'autre ne pose rien. Ce que la première coûte
est dit : un registre de lien tire sa légitimité d'un événement vécu, et un
nouveau-né n'a rien vécu.

**TROIS GARDES VIENNENT DE LA DONNÉE** : un témoin sans espèce déclarée est
écarté du cycle par la garde du mécanisme lui-même ; deux espèces distinctes
suffisent à empêcher les couples de se mélanger ; un enfant naît sans espèce,
donc stérile dans cette scène. Aucun filtre de câblage.

**Testé par** : `scripts/test_banc_temps_vieillissement.gd`.

---

### `scripts/banc_marche_competence.gd`

**Montre** : le prix vit PAR COLON, jamais dans un objet-marché. L'offre est
une somme sur ce que CE colon PERÇOIT, la demande un comptage sur les colons
— deux questions, deux briques de la couche lecteur. Le novice au comptoir
voit tous les tas et trouve le lingot bon marché ; les forgerons, à portée
courte, n'en voient qu'un et le trouvent cher. **Retirer un tas qu'un
forgeron ne voyait pas ne bouge pas son prix d'une décimale.**

**PREMIER APPELANT RÉEL de `somme.gd`**, livré sans appelant « pour que le
cinquième consommateur n'écrive pas une cinquième copie ». C'est ce banc, et
il n'en a écrit aucune.

**LA SPÉCIALISATION PASSE PAR LA DÉFORMATION, jamais par `poids_verbes`** :
deux sources sur la MÊME cible, composées MULTIPLICATIVEMENT par la couche de
proximité.

**LE PLANCHER DE COMPÉTENCE EST UNE DONNÉE PAR COLON, jamais une constante** :
écrit comme constante, il s'appliquerait AUSSI au novice (marque absente,
modulateur nul) et « la forge n'est pas plus attractive pour lui » serait
FAUX, tous tests verts.

**LES PLAFONDS PORTENT DEUX FOIS, et le gate n'est pas un doublon** —
CONDITION D'OBSERVABILITÉ trouvée en lançant, pas au test : sans gate de
pose, les modulateurs bruts montaient à plusieurs fois leur plafond ; rien
n'était faux (la lecture restait clampée) mais la barre saturait en quelques
secondes et la décroissance qui porte le sujet demandait sept fois plus de
temps. Le clamp reste : lui seul protège des valeurs posées à la main.

**Testé par** : `scripts/test_banc_marche_competence.gd`.

---

### `scripts/banc_infrastructure.gd`

**Montre** : stockage, dégradation, coordination et usure de route. Un
grenier qui REFUSE quand il est plein, des lots qui se dégradent plus vite
dehors qu'à l'abri, une file qui use la route qu'elle emprunte.

**LE PLAFOND EST UN REFUS, PAS UN ÉCRÊTAGE** : rien dans le cœur ne borne le
haut d'une réserve, et DEUX comportements existaient — écrêter (surplus
PERDU) et refuser (le porteur GARDE sa charge). Le grenier plein demande le
second : écrêter ferait disparaître EN SILENCE ce qu'un colon a porté à
travers la carte. Un PRÉDICAT UNIQUE, lu par les deux endroits qui en
dépendent, aucun ne le recalcule.

**L'ÉTAT D'ENCOMBREMENT N'EST PAS POSÉ PAR LE SEUIL, et c'est une décision** :
le seuil compare STRICTEMENT au-dessus, alors que le refus est « au moins
égal » — réserve pile à la capacité, le refus serait vrai et l'état absent.
Deux vérités qui divergent EXACTEMENT au bord, c'est-à-dire la
désynchronisation silencieuse que la règle de l'écrivain unique existe pour
empêcher.

**« SUIS-JE À L'ABRI » EST UNE COMPARAISON DE POSITIONS** — aucun toit, aucun
mur, aucun drapeau posé à la main. Les deux taux sont DÉRIVÉS des durées de
vie déclarées : la base porte la dégradation d'abri, le surcoût l'EXCÉDENT du
dehors — la somme donne le taux extérieur, sans un `if`.

**L'USURE PASSE PAR LE SURCOÛT, et c'est un écart à la consigne** : la base
est un coût par SECONDE, jamais par événement — « coût par passage » n'est
pas exprimable. C'est exactement la frontière du mécanisme : la base est ce
que la route EST, le surcoût ce qui la foule cet instant.

**DÉFAUT TROUVÉ EN LANÇANT, pas au test** : les colons s'immobilisent à
portée de travail, donc encore dans le rayon de la dernière case — une file
ARRÊTÉE devant un grenier plein usait la route à plein régime. Le trafic
filtre désormais sur le transit : un colon qui charge ou décharge n'est pas
un passage.

**Testé par** : `scripts/test_banc_infrastructure.gd`.

---

### `scripts/banc_economie.gd`

**Montre** : un colon ramasse du minerai, le porte à la forge en marchant
visiblement plus lentement parce qu'il est CHARGÉ, le fond en un lingot ET un
tas de scories, porte le lingot au grenier, recommence — pendant qu'un seul
nombre en haut de l'écran ne bouge JAMAIS : la masse totale du monde.

**LA FUITE DE MASSE DE `produit.gd` EST FERMÉE ICI** : son en-tête assume que
la masse perdue « n'est nulle part ». Le câblage appelle DEUX FOIS la
transformation sur le MÊME objet ancien, avant tout écrasement — deux
rendements qui somment exactement à un. Passer par `extinction.gd` est FERMÉ
et ce n'est pas un oubli : sa branche ne lit qu'UN produit et REMPLACE les
propriétés sur la MÊME instance, il n'y a nulle part où mettre le second.

**PREMIER RETRAIT D'UNE ENTRÉE DE SAILLANCE DU DÉPÔT** : tous les autres
bancs AJOUTENT, aucun ne RETIRE. Le filtre écarte ce dont le score net du
trajet tombe sous un seuil, AVANT dominance — qui est RELATIVE par
construction et ne peut donc pas porter un seuil ABSOLU. **La saillance qui
entre dans dominance EST le score net du trajet**, jamais la valeur nue :
filtrer et pondérer sont ici le même geste. Les deux arbitrages coexistent.

**AMBIGUÏTÉ DE LA CONSIGNE, TRANCHÉE ET SIGNALÉE** : elle demandait à la fois
qu'une ressource lointaine soit retirée et qu'elle passe le filtre quand les
proches disparaissent — sous un seuil ABSOLU les deux ne tiennent pas
ensemble. Lecture retenue : DEUX choses lointaines, un gisement au-dessus du
seuil (écrasé tant que les proches existent) et une miette en dessous
(retirée pour toujours). Les deux phrases deviennent vraies sans inventer
aucune mécanique.

**LE PORTAGE EST UNE RÉSERVE** : charger et décharger sont le MÊME appel,
source et receveur inversés. Ce que le minerai perd est une RÉSERVE NOMMÉE,
jamais sa masse — sortie dérivée de la composition, interdite en écriture.

**UNE ÉMERGENCE NON PRÉVUE, mesurée et gardée** : les scores du minerai
proche et du gisement lointain S'INVERSENT selon l'endroit d'où le colon
décide. Il exploite donc le lointain avant d'avoir fini le proche, ce
qu'aucune ligne ne lui dit de faire — un coût de trajet se mesure depuis là
où l'on est, pas depuis une origine fixe.

**DÉFAUT TROUVÉ PAR YAEL À L'ÉCRAN, et sa leçon** : le clic de retrait était
à SENS UNIQUE, au motif qu'« un retrait n'a rien vers quoi rebasculer ». Ce
motif vaut pour un NETTOYAGE, où la chose est DÉTRUITE — pas ici, où la
matière sortie existe toujours. Et le colon épuisait les ressources en moins
de sept secondes, si bien que le clic ne trouvait ensuite plus rien à faire
et l'écrivait en console, où personne ne regarde pendant qu'une scène tourne.
Fermé sur trois plans : la bascule, la calibration, et un COMPTEUR DE CLICS
affiché — qui sépare deux pannes que rien ne distinguait : « le clic n'arrive
pas » et « le clic arrive et ne trouve rien à faire ».

**Testé par** : `scripts/test_banc_economie.gd`.

---

### `scripts/banc_affordances_travail.gd`

**Montre** : trois colons, trois outils. Le bûcheron abat les arbres ;
l'apprenti RENONCE faute d'autonomie, va dormir, revient ; le manœuvre marche
jusqu'à l'arbre et n'y fait strictement rien. Un chantier lâché en route
laisse une entaille qui se dégrade — si personne ne revient, tout le travail
fourni est perdu. Chaque arbre abattu donne un produit différent selon la
qualité de la coupe.

**QUATRE VOIES ÉCARTÉES — résultats négatifs, interdits à refaire** :
(1) `reaction.gd` pour le gate de coupe, alors que sa forme est exactement la
bonne : sa paire est appariée par MATÉRIAU et le nom de la propriété scorée
est FIGÉ — le rendre paramétrable toucherait le cœur.
(2) `seuil_etat.gd` pour l'ARRÊT du sommeil : il ne compare que vers le haut,
et redire le miroir pour la SORTIE créerait deux vérités divergeant au bord —
le sens de satisfaction de `couplage.gd` le dit déjà, une fois.
(3) La branche « produire » d'`extinction.gd` pour l'issue : elle ne lit
qu'UN produit figé à l'avance, or l'issue n'est connue qu'à l'INSTANT où le
chantier s'achève.
(4) `conditions.gd` pour la sensibilité : il fait N conditions en ET et pose
un Dictionary, IL NE MULTIPLIE RIEN.

**LE RYTHME N'EST JAMAIS LU BRUT, et c'est le piège que ce banc ferme** : la
fonction partagée le lit tel quel, donc un état qui prétendrait le moduler
serait vrai en donnée et sans effet EN SILENCE. Composer soi-même permet en
plus de FILTRER les agents, impossible autrement.

**LE TRAVAIL EXIGE LA DÉCISION, pas seulement la présence** — deux défauts
mesurés avant fermeture : sans cette condition, un colon qui a REFUSÉ le
chantier le travaillerait quand même du seul fait d'être à portée, et un
colon en route travaillerait tout chantier qu'il frôle. `extinction.gd` ne
peut pas le savoir : il ne reçoit que des positions et des rythmes.

**L'ABANDON SPONTANÉ EST STRUCTURELLEMENT IMPOSSIBLE** : une fois le chantier
entamé, le travail restant baisse plus vite que l'autonomie — la marge ne
peut que S'AMÉLIORER. L'entaille n'existe donc que pour ce que la marge NE
COUVRE PAS, et il faut un geste extérieur pour la provoquer. Verrouillé comme
une PROPRIÉTÉ, pas constaté comme un manque.

**LA MASSE N'EST PAS CONSERVÉE, ET C'EST LE SUJET** : les trois issues ne
somment PAS à un — rater DÉTRUIT vraiment de la matière. L'invariant vérifié
est « monde + perdu == référence ».

**CALIBRATION MESURÉE, deux nombres corrigés après lancement**, dont une
sortie déclarée qui était INATTEIGNABLE — morte en donnée sans qu'aucun test
ne rougisse, désormais verrouillée à l'envers.

**Testé par** : `scripts/test_banc_affordances_travail.gd`.

---

### `scripts/banc_affordances_portage.gd`

**Montre** : trois chantiers qui refusent pour trois raisons différentes. Un
TRONC demande de la FORCE (un colosse seul suffit, un faible non, deux
faibles oui) ; une ÉCHELLE demande DEUX MAINS (le colosse a deux fois la
force exigée et reste bloqué, parce qu'une échelle a deux bouts) ; une ENCLUME
demande d'être TENUE (un porteur seul est refusé, il passe avec un second ou
à côté d'un étau).

**PREMIER APPELANT de la lecture PLATE de `somme.gd`** — les deux appelants
existants n'utilisaient que la lecture profonde. Contrainte qui en découle :
les propriétés sommées doivent être des floats PLATS, jamais un Dictionary ni
une entrée de réserve.

**DEUX GATES SÉPARÉS SUR LA MÊME LISTE** : sa SOMME et sa TAILLE. C'est ce
qui rend l'échelle possible — un gate composite unique (une force divisée par
un nombre) n'aurait JAMAIS pu produire ce refus-là. `comptage.gd` ne peut PAS
rendre la seconde : sa valeur de référence vit dans le catalogue, donc
statique — compter autour de CETTE cible demanderait une entrée par cible.

**UN OBJET FOURNIT UNE GRANDEUR D'AIDE EXACTEMENT COMME UN AGENT** : l'étau
et le colon portent la MÊME propriété, et le gate ne demande jamais si un
contributeur est vivant — il somme. L'étau ne porte ni rythme ni force : il
n'est donc ni agent ni porteur, seulement stabilisateur. **Les trois rôles
sont distingués par ce que la chose PORTE, jamais par ce qu'elle EST.**

**LE GATE NE MET AUCUNE BRANCHE DANS LE CŒUR** : quand une condition manque,
le câblage ne construit simplement pas la liste d'agents. Conséquence mesurée
et verrouillée : sous le seuil le travail ne COMMENCE pas, il ne ralentit pas.

**LA RÉFÉRENCE DE CHANTIER NE S'APPELLE PAS `transformation`** : le linter
vérifie tout champ portant exactement ce nom contre le catalogue PARTAGÉ, une
référence locale y rougirait. La recopie sous la clé attendue se fait EN
CODE, une fois, à la fabrication.

**Direction des comparaisons : « au moins égal »** — une exigence exactement
atteinte est atteinte. Volontairement PAS la convention stricte des seuils
qui comparent une grandeur qui MONTE en continu, où l'égalité est un instant
sans durée : ici on compare deux valeurs POSÉES en donnée, où l'égalité est
un cas nominal qu'un auteur de contenu écrira exprès.

**Testé par** : `scripts/test_banc_affordances_portage.gd`.

---

### `scripts/banc_affordances_connaissance.gd`

**Montre** : seul celui qui s'en sert SAIT. L'apprenti est hors de portée
d'usage : il ne sait rien par lui-même, tout ce qu'il finit par savoir vient
d'un autre — d'une parole, ou d'un LIVRE. Un fruit devenu toxique reste
« comestible » dans sa croyance, il le mange et s'empoisonne. Le verbe
d'expérimentation n'est choisissable que si trois conditions sont réunies.

**LA PROBABILITÉ DE L'AUDIT EST DEVENUE UNE CADENCE** : aucun RNG n'existe
dans le dépôt, et `croyance.gd` n'a aucune notion de temps propre — la
cadence DOIT vivre au câblage.

**LA FIDÉLITÉ DÉGRADE LA CERTITUDE, JAMAIS LA VALEUR** : la correction
recopie la valeur telle quelle. Une transmission qui DÉFORMERAIT ce qui est
dit n'existe pas et serait un mécanisme neuf.

**NE PASSE PAS PAR `charge.gd`** : la contagion de maladie monte un canal par
présence, le savoir passe par la correction, directement — émetteur nommé,
destinataire nommé, crédibilité propre au couple.

**LE GATE DU VERBE EST ARITHMÉTIQUE** : le poids tombe à zéro dès qu'une des
trois conditions manque, et `agir.gd` exige un poids strictement positif — le
verbe devient inchoisissable sans qu'aucune branche n'existe. `conditions.gd`
ÉCARTÉ : il n'aurait rien épargné (mêmes miroirs plats requis, plus une
entrée de catalogue) et poserait un Dictionary qu'aucun mécanisme ne lirait.

**LE LIVRE EST UN VRAI OBJET fabriqué en cours de partie**, dont le contenu
est une COPIE PROFONDE des croyances de l'auteur — jamais du texte. Sa
lisibilité se dégrade jusqu'à un marqueur.

**DEUX CONSÉQUENCES MESURÉES, à attendre et non des bugs** : (a) le dogme
porte PAR PROPRIÉTÉ, jamais par chose — le novice dogmatique sur une
propriété acquiert l'autre du livre, et croit donc en même temps que le fruit
est comestible ET toxique, continuant de le manger parce que c'est la
première qui porte le verbe ; (b) **le dogme CÈDE À L'OUBLI** : la clé
retirée n'est plus rafraîchie, la certitude retombe sous la résistance, et
l'usage suivant corrige. Un dogme ne dure que tant qu'on le nourrit.

**Testé par** : `scripts/test_banc_affordances_connaissance.gd`.

---

### `scripts/banc_affordances_choix.gd`

**Montre** : un colon au centre, trois cibles. Rassasié, il ramasse le bois
parce qu'il est PRÈS. Le bois s'éloigne : il se tourne vers la forge, par
HABITUDE. Il a faim : le repas — la cible la plus lointaine et la moins
saillante en soi — écrase tout. Entre deux re-scorings, RIEN ne change.

**LES TROIS POIDS DE LA CONSIGNE NE SONT PAS UNE TABLE**, et c'est toute la
correction de voie : aucun des éléments décrits n'existe sous cette forme, et
aucun n'a été créé.
- Le poids d'urgence EST une entrée de `deformation.gd` — la seule voie qui
  fasse GAGNER une cible par un état interne, parce qu'elle indexe PAR
  PERCEVANT.
- **Le poids de distance N'EXISTE PAS COMME POIDS** : la couche de proximité
  applique une atténuation LINÉAIRE FIXE, sans exposant ni coefficient. Le
  seul réglage est la PORTÉE par profil — peser la distance plus fort, c'est
  RACCOURCIR la portée.
- Le poids d'habitude est le même outil, deuxième entrée, sur une autre
  cible ; les deux se composent EN SÉQUENCE.
- **La division par un coût n'existe nulle part** : rien ne divise une
  saillance dans ce dépôt.

**LE RE-SCORING A UN PRIX, et il est dit** : entre deux échéances le colon
est AVEUGLE — on peut tout changer autour de lui, il ne s'en aperçoit qu'à
l'échéance. Verrouillé dans les deux sens.

**QUATRE MÉCANISMES DE STABILITÉ, pas un** : ne pas re-scorer ; l'inertie
(préférence de PERSONNALITÉ) ; l'engagement (FAIT PHYSIQUE posé par
présence) ; et la pondération par avancement, PRÉSENTE et MESURABLEMENT
NEUTRE ici — chaque cible porte un travail intact, donc le facteur vaut
exactement un, verrouillé par test plutôt que supposé. L'engagement RALENTIT,
il ne verrouille pas.

**LA FILE DE PLAN EST ABANDONNÉE, décision doctrinale et non oubli** : elle
tombe sous deux des quatre griefs qui ont fait rejeter BDI. À chaque
re-scoring les quatre couches repartent de zéro. **Verrouillé NÉGATIVEMENT,
et le verrou cherche une FORME DE CODE, pas un mot** — les deux noms sont
NOMMÉS en prose dans l'en-tête du banc, c'est même là que leur abandon est
justifié, et un verrou sur le mot interdirait d'expliquer pourquoi on ne l'a
pas écrit.

**DEUX DÉFAUTS TROUVÉS EN LANÇANT** : le score affiché au TOUT PREMIER
re-scoring divergeait de celui que `agir.gd` avait comparé — l'inertie
s'appliquait rétroactivement à une tâche qui venait de naître ; et la liste
de ce que dominance avait laissé passer n'était rendue que les ticks de
re-scoring, donc le grisé d'une cible écrasée aurait battu au rythme de la
cadence.

**Testé par** : `scripts/test_banc_affordances_choix.gd`.

---

### `scripts/banc_social_information.gd`

**Montre** : ce qui CIRCULE d'un colon à un autre quand ils se voient. Un
témoin voit un vol, sa certitude monte, il la verse à qui est à portée — et
**jamais à sa propre hauteur : la parole affaiblit ce qu'elle porte**, sans
qu'une ligne le demande. En parallèle, un novice imite un maître et sa
compétence s'arrête net au produit de la fidélité et de celle du maître.

**LES DEUX LIGNES SONT LA MÊME QUESTION**, d'où un seul banc : l'une fait
circuler un FAIT (valeur + certitude), l'autre un SAVOIR-FAIRE (une marque).
Deux mécanismes, deux temporalités, UN seul geste de câblage : percevoir
quelqu'un à portée, puis écrire chez lui.

**TROIS CORRECTIONS DE VOIE, toutes tenues** :
- La réputation ne passe PAS par une contagion à canal accumulé : celle-ci ne
  porte NI valeur NI certitude et ignore de QUI vient l'information. Ici c'est
  PAR PAIRE.
- **`epigenetique.gd` N'A AUCUNE FONCTION DE LECTURE** : lire un modulateur
  est donc un geste de câblage.
- **Une cadence « par heure » n'est pas une cadence** : un seul facteur de
  conversion, et les quatre cadences en dérivent. Verrouillé, y compris « le
  nombre par heure n'est jamais consommé tel quel ».

**LE SENS DU LIEN DE CRÉDIBILITÉ EST INVERSÉ par rapport au prompt** : c'est
« à quel point JE TE crois » (receveur → émetteur). Une crédibilité portée
par l'émetteur ferait dépendre ma confiance de ce que l'AUTRE ressent pour
moi.

**UNE SEULE PORTÉE DE VUE EST LONGUE, et c'est STRUCTUREL** : sans cela, les
receveurs formeraient la croyance par observation DIRECTE et il n'y aurait
plus rien à propager — même piège que le banc de croyance évite en ne faisant
marcher personne.

**LE MAÎTRE NE PERD RIEN, et ce n'est pas un cas particulier** : la
décroissance touche TOUTES les marques de tous les colons, chaque tick,
inconditionnellement — un maître inerte perdrait sa compétence en quelques
secondes. Il l'ENTRETIENT : il exerce son métier, voilà tout.

**LE MODÈLE N'EST PAS NOMMÉ** : le câblage prend, parmi les colons perçus,
celui dont le modulateur est le plus haut. Un troisième forgeron plus
compétent volerait le rôle sans une ligne de code, et le maître n'imite
jamais le novice parce que son écart est négatif — pas parce qu'un cas
particulier l'exclut.

**Testé par** : `scripts/test_banc_social_information.gd`.

---

### `scripts/banc_social_rupture.gd`

**Montre** : deux colonies, cinq colons. Le nord est injuste : le chef se
soumet, le cupide conteste puis — second palier franchi — TRAHIT, et la
réserve commune se vide dans sa poche. Un clic tue un compagnon : celui qui
l'aimait entre en DEUIL, son rythme tombe, et son grief monte pour cette
raison-là aussi. Un colon à loyauté basse MIGRE vers l'autre colonie ; son
voisin lit EXACTEMENT la même attractivité et ne bouge pas.

**LE QUATRIÈME PALIER EST CE QUE CE BANC AJOUTE** : là où un seul seuil
ouvrait trois sorties départagées au biais, un SECOND palier sur le même
grief en ouvre une QUATRIÈME. `bifurcation.gd` ne connaît ni seuil ni palier
— « la trahison demande plus de grief que la révolte » ne peut s'écrire QUE
comme un ensemble de sorties qui GRANDIT. Conséquence : la bifurcation doit
être REJOUÉE quand cet ensemble change, sinon la quatrième sortie serait
inatteignable ; et jamais à chaque tick, l'ensemble du dernier arbitrage
étant mémorisé sur le colon.

**LA MORT N'EST PAS UN ÉVÉNEMENT, C'EST UNE ABSENCE** : rien ne s'appelle
« mourir ». Le câblage retire le compagnon du monde, et constate qu'un lien
personnel vise une chose qui n'y est PLUS. Tuer n'importe quoi vers quoi un
colon porte un lien assez fort produit le même deuil, sans cas particulier —
et le seuil est une FORCE DE LIEN, jamais une appartenance : le chef
connaissait le compagnon et ne porte pas son deuil.

**LE DEUIL S'ESTOMPE, IL NE S'ARRÊTE PAS D'UN COUP** : le câblage passe par
la pondération d'intensité AVANT la valeur effective — sans ce passage,
l'effet serait PLEIN puis nul d'un coup. Son intégrale est SOUS le palier de
trahison : **un deuil seul ne fait jamais un traître**, verrouillé par test.

**LE GRIEF PASSE PAR `charge.gd` alors qu'un autre banc l'avait ÉCARTÉ** — ce
n'est pas un revirement : ici c'est le comportement VOULU, une cause encore
active bloque toute décrue et l'amélioration ne défait que ce qui n'a plus de
cause.

**L'ATTRACTIVITÉ EST UN RÉSUMÉ LU, jamais une colonie perçue** : aucune
entité collective n'existe. En multijoueur ce nombre serait posé par la
couche serveur et lu ici sans une ligne de changée.

**Testé par** : `scripts/test_banc_social_rupture.gd`.

---

### `scripts/banc_social_foule.gd`

**Montre** : vingt colons, quatre gestes. Mettre des colons en colère (sous
une fraction critique rien ne bouge, au-delà la foule bascule quelques
secondes plus tard) ; tuer le chef (la cohésion s'effondre, le groupe se
disloque, le rendre la fait remonter) ; entasser la foule ; faire tourner le
bruit.

**DEUX RÉSULTATS NÉGATIFS, mesurés en écrivant, à ne jamais repayer** :
1. **`charge.gd` : UN SEUL CANAL PAR OBJET dès qu'il y a plusieurs causes.**
   Il applique LA MÊME liste de causes à TOUS les canaux de chaque chose, et
   les causes ne portent aucun type — seules la POSITION et la portée les
   sélectionnent, et aucune portée ne les sépare puisqu'une portée large
   contient toujours la petite. **Deux canaux sur le même objet ne peuvent
   donc pas être alimentés par deux causes différentes.** Aucun banc antérieur
   ne l'avait rencontré, chacun n'ayant qu'un canal. Ce banc en veut trois,
   d'où trois familles d'objets DISJOINTES et trois appels. Si ce partage ne
   suffit plus un jour, la voie est des causes NOMMÉES dans le mécanisme —
   chantier de framework, pas un bricolage au passage.
2. **`charge.gd` et `seuil_etat.gd` ne se branchent PAS directement** : le
   premier EFFACE ses clés au franchissement descendant, le second SORT quand
   la propriété comparée est absente. Branchés directement, l'état serait posé
   à la montée et **jamais retiré à la descente**, sa mémoire restant bloquée
   — irréversible EN SILENCE, sans qu'aucun test du cœur ne rougisse. Le
   câblage écrit donc un MIROIR PLAT binaire qui existe toujours, et le seuil
   n'est plus qu'un gate sur ce zéro-ou-un : toute la calibration reste dans
   le canal.

**LA FENÊTRE TEMPORELLE EST `charge.gd`, JAMAIS `etat_duree.gd`** — écarté
doctrinal : celui-ci fait DÉCROÎTRE une intensité et retire à zéro ; il ne
monte jamais, il ne sait donc pas dire « la fraction est restée au-dessus
pendant N secondes ». `charge.gd` est le seul mécanisme qui monte tant qu'une
cause dure, franchit, puis redescend seul — c'est aussi ce qui rend l'émeute
réversible sans une ligne de plus.

**`bifurcation.gd` ÉCARTÉ, décision prise avant écriture** : il exige de
NOMMER les sorties — du contenu de jeu, hors de ce chantier. La dislocation
reste un seul nom d'état ; les ajouter plus tard ne demandera aucune ligne de
mécanisme.

**LES CINQ ÉTATS SONT DES MARQUEURS PURS, et c'est un choix** : ce banc ne
compose la valeur effective nulle part, il n'a donc rien à moduler —
déclarer un effet serait vrai en donnée et inerte dans le jeu, en silence.

**Testé par** : `scripts/test_banc_social_foule.gd`.

---

### `scripts/banc_social_paire.gd`

**Montre** : quatre colons — un chef, un soldat loyal, un ami proche, un
ennemi. La confiance monte par temps partagé et débloque deux actions à deux
paliers : le soldat franchit les deux, l'ami PLAFONNE entre eux, l'ennemi ne
franchit rien. Le chef ordonne de tuer l'ami : le soldat CÈDE mais refuse,
l'ordre forcé passe outre et lui coûte du grief.

**LA PIÈCE QUI REND LA PAIRE POSSIBLE** : le registre de marques est un
Dictionary PLAT et le mécanisme alarme sur un nom absent du catalogue — une
grandeur PAR PAIRE ne peut donc s'obtenir qu'avec un nom COMPOSÉ et un
catalogue ÉTENDU par paire. Ce catalogue est **dérivé d'UNE seule entrée
partagée** et reçu en paramètre : la loi vit une fois en donnée, jamais N
fois.

**UNE GRANDEUR SIGNÉE SORT DE DEUX REGISTRES QUI RESTENT POSITIFS** : le
score net est une LECTURE refaite à neuf, jamais une valeur stockée. C'est la
seule route qui n'ouvre pas le chantier « registre de liens signé », qui
toucherait cinq fichiers du cœur.

**LA DETTE SE LIT SUR DEUX ENTITÉS** : un seul registre positif, posé sur
celui qui REND, et la dette est la différence des deux sens. Aucun mécanisme
du cœur ne compare une propriété de A à une propriété de B — cette
soustraction est du câblage.

**UN SEUL ÉCRIVAIN pour les deux miroirs**, dans le même geste. Première
entrée du dépôt qui paie les DEUX raisons de miroir à la fois : atteindre une
valeur enfouie ET retourner le sens de la comparaison.

**DÉFAUT RÉEL TROUVÉ EN LANÇANT LE TEST, pas raisonné à l'avance** : le
mécanisme de marque ajoute SANS BORNE HAUTE, donc un modulateur laissé libre
monte au-delà du plafond et le clamp à la LECTURE MASQUE la décroissance —
mesuré, « hors de portée, la confiance descend » affichait deux fois la même
valeur. Une hystérésis PAR ACCIDENT, proportionnelle au temps passé ensemble.
Fermé en ne posant plus au-delà du plafond.

**LA BIFURCATION SERT DE GATE** : sa grandeur est un scalaire COMMUN qui ne
peut jamais départager deux sorties — la comparaison vit donc entièrement
dans le BIAIS, et la grandeur vaut un s'il y a un ordre, zéro sinon : aucune
bifurcation sans ordre PAR LA SEULE ARITHMÉTIQUE.

**LE LECTEUR DU LIEN EST `lien_personnel.gd`, JAMAIS `attaches.gd`** —
correction de voie de l'audit : une attache lie à un TRAIT, jamais à un
individu.

**Testé par** : `scripts/test_banc_social_paire.gd`.

---

### `scripts/banc_temps_saisons.gd`

**Montre** quatre choses tenues ensemble par un seul monde. Une réserve
végétale gagne à chaque image et perd d'un coup au passage de saison. Une
année sur trois, le froid ne vient pas. Un colon dont la sérénité tombe
entraîne l'humeur de ses voisins immédiats, jamais celle du colon posé au
large. Des chroniques s'écrivent, se lisent, se dégradent et peuvent brûler.

**LES DEUX DÉBITS NE SE CONFONDENT PAS** : deux lignes de table visent la même
réserve, mais chacune a son émetteur, donc son taux et sa portée. Les fondre
en une seule ligne aurait donné un agrégat où plus rien ne se lit.

**LA PERTURBATION N'A PAS DE BRANCHE** (le point à retenir) : `conditions.gd`
ne sait comparer que des nombres, le nom d'une saison y vaudrait zéro. Le
câblage écrit donc des miroirs numériques, et sauter le froid consiste
uniquement à ne pas écrire le sien. La ligne lente ne trouve alors plus de
receveur — rien n'a été désactivé, une donnée manque.

**LA MARGE DU SEUIL DE PANIQUE EST LA MÉCANIQUE**, pas un réglage : sans elle,
un voisin contaminé franchirait à son tour, les deux se maintiendraient
mutuellement et la contagion ne se déferait jamais.

**LA FIERTÉ EST UN PRODUIT DE DEUX PARTS** — ce qu'un colon a lu, ce qui reste
lisible dans le monde. Perdre des rayonnages la fait tomber sans qu'aucune
ligne ne la retranche ; ce qui a déjà été appris, lui, demeure sur les
lecteurs.

**Testé par** : `scripts/test_banc_temps_saisons.gd`.

---

### `scripts/banc_llm_connexion.gd`

Sonde vers un modèle local : elle envoie un résumé d'état et vérifie que la
réponse est membre d'une liste close. À PART DE TOUS LES AUTRES BANCS — ni
scène, ni `_process`, ni `data/`, ni mécanisme du cœur, aucun test ne la
verrouille, `lanceur.gd` ne la ramasse pas (nom hors motif `test_*.gd`).
Elle se lance seule : `--headless --script scripts/banc_llm_connexion.gd`.
Contrat, pièges et limites : en-tête du fichier.

---

## 4. Les données (`data/`) — qui lit quoi

Le contenu vit ici. Ajouter un contenu = une ligne de données, zéro ligne de
code.

INDEX, pas une source de vérité : la forme exacte, les valeurs et les défauts
se lisent dans le fichier `.json` lui-même. Cette table dit ce que le JSON ne
dit pas — le rôle, les pièges, les statuts dormants, les écartés.

| Fichier | Contenu | Lu par |
|---|---|---|
| `types.json` | Table de fabrication. Quatre PAQUETS fondateurs composables à plat via `herite` (jamais récursif) : `objet_physique` (masse/volume/densite/temperature, `masse == densite * volume` par convention), `dynamique` (état interne qui évolue : `engagement`, `reserves` 5 canaux physiologiques, `liens_personnels`, `deformation_sources`/`deformation_etat`, `etats`, `marques_epigenetiques`, `age`, `stade`/`stades_config`, les cinq clés de reproduction), `percevant` (`canaux`, `canaux_config`, `orientation`), `agent` (`attaches`). Types nommés d'Orion : `colon` (compose les quatre), `arbre`, `bloc`, `batisse`, `feu`, plus les matériaux terminaux produits par transformation (`charbon`, `cendre`, `compost`, `rouille`, `residu_dissous`, `eclats_pierre`, `eclats_verre`, `copeaux_bois`, `limaille_fer`, `sel_metallique`, `residu_calcaire`, `residu_organique`, `residu_acide`, `residu_radioactif`, `humus`, `lingot_fer`, `scories`, `sel_dissous`, `buche`, `reste_nourriture`). PIÈGE : le merge de `objet.gd:fabriquer` est SUPERFICIEL — une clé présente dans un paquet ET dans le type REMPLACE la valeur du paquet en bloc, jamais une fusion clé par clé. `colon` doit donc redéclarer `canaux_config` EN ENTIER (six canaux) sous peine d'effacer silencieusement les cinq autres hérités de `percevant` ; même piège latent sur `deformation_etat`. Un `type_produit` de transformation DOIT vivre ici : `produit.gd` le résout contre cette table et `test_lint_donnees.gd` vérifie ce champ dans tout `data/*.json`. | `objet.gd:fabriquer` (via le catalogue de types du banc), `depense.gd` (canaux `reserves`), `charge.gd` (canal `etats.peur`) |
| `canaux.json` | Catalogue des canaux perceptifs : `nom_canal -> { geometrie, proprietes_captees, propriete_obstacle?, largeur_obstacle?, propriete_emission? }`. Quatre géométries : `cone_oriente` (vue), `propagation_obstacles` (ouïe, radiation, magie, odeur_corporelle, apparence), `sphere_directionnelle` (odorat), `contact` (toucher/goût/nociception). Portée/angle/sensibilité/seuil vivent SUR L'ENTITÉ (`canaux_config`), jamais ici, et ce catalogue ne porte aucun défaut de repli pour elles — un canal listé sans `canaux_config` reste MUET, jamais une alarme. `proprietes_captees` est une MÉTADONNÉE, jamais un filtre de détection. `propriete_obstacle`/`largeur_obstacle`/`propriete_emission` vivent sur le CANAL (un obstacle est une notion de canal, pas un réglage individuel) ; `propriete_obstacle` absente ou vide court-circuite l'occlusion à 1.0. ÉCARTÉ, à ne pas reproposer : `odorat` n'est jamais basculé en `propagation_obstacles` — il est SEUL porteur de la modulation par le vent et ne lit ni `propriete_emission` ni `seuil` ; le basculer retirerait le vent à l'odorat en silence. `odeur_corporelle`/`apparence` sont ses substituts sociaux, leurs propriétés d'émission étant écrites PLATES par le câblage, jamais fusionnées depuis une fiche matériau. | `perception.gd`, `test_lint_donnees.gd` (chaque nom de `canaux`), banc (chargement) |
| `profils_saillance.json` | Référence → `{ saillance_intrinseque, portee_saillance }`. Une chose saillante porte `profil_saillance` (String), jamais les deux nombres en valeur. Entrées réelles du jeu et de démonstration : `feu`, `bloc`, `menace_1/2/3`, `colon`, `nourriture`, `allie_blesse`, `adversaire`, `proie_exposee`/`proie_cachee`, `grenier_stockage`, `forge_atelier`, `repas_choix`/`bois_choix`/`forge_choix`. CONSÉQUENCE PORTANTE : `proximite.gd` applique une atténuation LINÉAIRE FIXE `clamp(1 - distance/portee)` — pas d'exposant, pas de coefficient. Le SEUL réglage de la distance est `portee_saillance` PAR PROFIL : peser la distance plus fort, c'est RACCOURCIR la portée. Deux profils au nom proche (`forge_atelier`/`forge_choix`) sont distincts exprès — deux bancs, deux géométries ; réutiliser une entrée couple deux bancs par une valeur que ni l'un ni l'autre ne peut plus régler seul. `proie_exposee`/`proie_cachee` sont une PAIRE : le câblage réécrit la clé plate `profil_saillance` en cours de partie, seul cas du dépôt où un profil est choisi plutôt que posé une fois. | `proximite.gd` (résolution + pondération par `travail_restant`/`travail_initial`), banc (chargement) |
| `menaces.json` | Couples `vulnérabilité: menace`, ex. `{ "inflammable": "brule" }`. | `attaches.gd`, `propagation.gd`, `ciblage.gd` (branche déclencheur), banc |
| `jugements.json` | Couples `propriete_jugee: propriete_declencheur`, même forme que `menaces.json`. `banc_p1.gd` charge la table sans jamais l'utiliser dans `decider` ; seul `banc_feu.gd` l'exerce. | `jugement.gd`, `ciblage.gd` (branche jugée), banc |
| `orientations.json` | `{ verbe: "jugee" \| "fuite" }` — PAR VERBE. Un verbe absent vise le déclencheur par défaut, jamais une alarme. | `ciblage.gd`, banc (branche fuite) |
| `transformations.json` | Deux rôles dans un même fichier. (1) `patron`/`patron_bloc` : gabarits posés à l'allumage (`travail_restant`, `travail_initial`, `profil_saillance`, `transformation`, et pour `patron` le `seuils_ref` du canal combustible). (2) Entrées nommées résolues par la référence `transformation` : `portee_travail` + `a_zero` (`retirer`/`poser`, ou `produire` = `{ type_produit, rendement, patron_produit? }`). DEUX FAMILLES D'ENTRÉES, à ne pas confondre : celles réellement lues par `extinction.gd` (`defaut`, `bloc_defaut`, `combustion_bois`, `combustion_charbon`, `chantier_coupe_arbre`) et celles que RIEN ne résout par `transformation` — lues DIRECTEMENT par le câblage d'un banc, qui appelle lui-même `produit.gd` parce que son déclencheur n'est pas `extinction.gd` (`pourriture_bois`, `corrosion_fer`, `dissolution_sel_demo`, `fracture_pierre`, `fracture_verre`, `coupe_bois`/`coupe_pierre`/`coupe_fer`, `reactivite_acide_epuise`, `epuisement_source_radiation`, `decomposition_cadavre_demo`, `fonte_metal`/`fonte_scories`). PIÈGE : une entrée portant `travail_restant` dont la `transformation` résolue n'a pas de `portee_travail` fait alarmer `extinction.gd` sans rien accomplir. `fonte_metal`+`fonte_scories` sont la SEULE PAIRE dont les rendements somment à 1.0 : partout ailleurs le complément du rendement est de la masse perdue sans destination. | `propagation.gd` (patron), `extinction.gd` (via `produit.gd`), `proximite.gd` (pondération), banc |
| `seuils_combustible.json` | MALGRÉ SON NOM, catalogue PARTAGÉ de TOUTE référence `seuils_ref` du dépôt pour `depense.gd`, quel que soit le canal : `test_lint_donnees.gd` vérifie chaque `seuils_ref` de `data/*.json` contre CE SEUL fichier, aucun second catalogue de seuils n'existe et un catalogue local à un banc y échoue. Forme : `ref -> Array de { seuil, retirer?, poser? }` en escalier. La plupart des entrées posent un simple MARQUEUR booléen et `depense.gd` n'agit qu'en DÉTECTEUR — c'est le câblage qui produit ensuite (`epuisement_pourriture`, `epuisement_corrosion`, `epuisement_solubilite`, `epuisement_reactivite_acide`, `epuisement_radioactivite`, `epuisement_lisibilite`). Deux exceptions où `poser` écrit une valeur NUMÉRIQUE et où `depense.gd` agit donc lui-même : `effacement_trace` (`creusement: 0.0`) et `usure_route` (`facteur_vitesse: 1.0`) — légitimes parce que la valeur restaurée est un neutre identique pour tout objet. `epuisement` reste l'entrée du feu (retire d'un coup `inflammable`/`brule`/`profil_saillance`/`travail_restant`/`transformation`). PIÈGE : `depense.gd` n'applique jamais deux fois le même seuil — un câblage qui recharge une réserve doit vider `seuils_franchis`, sinon le seuil ne se redéclenche plus jamais. | `depense.gd` (via `seuils_ref` posé par l'appelant), bancs (chargement) |
| `reactions.json` | `reactions` → Array de `{ materiau_a, materiau_b, seuil_reactivite, type_produit, rendement, portee_reaction? }`. Modèle ASYMÉTRIQUE : `materiau_a` est source/catalyseur, JAMAIS transformé ; `materiau_b` est la cible. `seuil_reactivite` initialise le seuil d'un canal `charge.gd` dédié, pondéré par le produit des deux `reactivite`. `materiau_a`/`materiau_b` ne sont PAS vérifiés par le linter (seul un champ nommé exactement `materiau` l'est) ; `type_produit` l'est. Une entrée dont le `materiau_b` est le PRODUIT d'une autre entrée est ce qui rend le chaînage possible. | `reaction.gd` (cœur), `banc_chaine_reactions.gd` (par le cœur), `banc_reactivite.gd` (lecture directe, sans passer par le cœur) |
| `emergences.json` | `emergences` → Array de `{ id?, conditions: Array de { propriete, operateur, seuil }, resultat }`. ET logique, opérateurs `>=`/`<=`/`>`/`<`/`==`, une propriété absente fait ÉCHOUER sa condition (jamais un défaut permissif). NE DÉPEND PAS de `composition` : s'applique à tout objet fabriqué. Évalué SANS retrait à la fabrication — une capacité issue de la matière ne peut pas disparaître. UNITÉS : `densite` y est en kg/m³ (SI), pas en g/cm³ comme `materiaux.json`. | `objet.gd:fabriquer` (délègue à `conditions.gd`), `banc_emergences.gd` |
| `types_attaches.json` | Vide (`{}`). Le verbe `defendre` qu'il portait était mort et créait une collision réelle avec `brule` sur une chose défendue en feu ; vider l'entrée en gardant la clé n'aurait pas suffi — une clé de catalogue compte pour le `break` du scan de `agir.gd`, son contenu non. | banc (fusionné dans son catalogue d'actions, sans effet) |
| `types_choses.json` | Par PROPRIÉTÉ (`brule`, `hostile`, `comestible`, `sale`, `experimentable`…), jamais par nom de type : `propriete -> { verbes: [clé, ...] }`, arbitrés par `poids_verbes` du colon. Résolu contre une propriété PLATE de `chose.proprietes` : `agir.gd` ne lit JAMAIS `etats_actifs`, d'où les miroirs plats que les câblages écrivent. Une propriété portant DEUX verbes permet à la même chose de commander deux gestes opposés selon l'état interne du percevant. ABSENCES DÉLIBÉRÉES : `blesse` (remarqué, jamais fui), `occupe` (une chose occupée reste actionnable — c'est `proximite.gd`, saillance gelée, qui l'exclut). | `agir.gd` (`_action`/`_verbe_par_poids`), banc |
| `deformations.json` | Catalogue par SOURCE : `source -> { sens, taux_decroissance_rapide, taux_decroissance_lent, w_rapide, w_lent }`. `cible` est DOCUMENTAIRE et n'est jamais lue — `deformation.gd` reçoit la cible en paramètre. Sources : `habituation` (`baisse`), `faim_critique`, `peur`, `colere`, `competence_forge`, `habitude_forge`, `urgence_repas`, `habitude_atelier`, `vigilance_proie`, `agression_territoire`, `agression_petits`, `anticipation`, plus `gravitique` (hors domaine). RÉSULTAT NÉGATIF MESURÉ DEUX FOIS, interdit de le repayer : `avancer` décroît par SOUSTRACTION FIXE, jamais par une fraction — il n'existe AUCUNE asymptote, un débit de pose égal au taux laisse le registre PLAT et le registre monte SANS BORNE sinon. Le plafond vit donc au CÂBLAGE, jamais espéré du mécanisme. Deux sources sur la même cible se composent MULTIPLICATIVEMENT dans `proximite.gd`. C'est la seule voie du dépôt qui fasse gagner une CIBLE par un état interne, parce qu'elle indexe PAR PERCEVANT. | `deformation.gd`, `proximite.gd` (`sens`), `test_lint_donnees.gd` (chaque nom de `deformation_sources`), bancs |
| `liens_personnels.json` | Une entrée `"defaut"` → `{ taux_decroissance, plancher_suppression, portee_menace, portee_attraction }`. Décroissance volontairement très lente. | `lien_personnel.gd`, `lien_personnel_saillance.gd`, `lien_personnel_attraction.gd`, bancs |
| `lien_personnel_croissance.json` | `ref -> { traits_recherches, montant_par_pose, intervalle_pose, plafond }`. Le montant est FIXE par événement de pose, jamais mis à l'échelle du delta — voir le résultat négatif en §2. `lien_personnel_croissance_ref` est vérifié ici par le linter. | `lien_personnel_croissance.gd`, `test_lint_donnees.gd`, `banc_vecu_inter_colon.gd` |
| `actes_liants.json` | `regle_id -> { verbe, propriete_cible, magnitude }`. Extensible sans code : un autre verbe ou une autre propriété est une entrée de plus. | `agir.gd` (`_appliquer_actes_liants`), `banc_lien_personnel.gd` |
| `attaches_par_trait.json` | `regle_id -> { propriete, seuil_nombre, seuil_force, force_attache }`. `propriete` nomme EXPLICITEMENT le trait vérifié et posé — jamais deviné en décodant `regle_id`. Chaque seuil est surchargeable PAR COLON via `proprietes.sensibilite_generalisation`. PIÈGE MESURÉ : une règle ajoutée ici est GLOBALE — une règle sur `brule` a cassé un banc dont les objets `notre_ouvrage` portaient aussi `brule`. Les règles propres à un banc restent dans son fichier. | `attache_par_trait.gd`, `agir.gd` (appel conditionnel), bancs |
| `materiaux.json` | Référence → paquet de ~46 propriétés physiques. Une chose physique porte `materiau` (String) dans sa `composition`, jamais les propriétés en valeur. Le linter valide tout champ `materiau` de N'IMPORTE QUEL `data/*.json` contre ce fichier — aucune notion de table locale, ce qui force tout matériau de démonstration à rejoindre ce catalogue partagé. TROIS STATUTS, à lire avant d'ajouter : (a) FUSIONNÉE à la fabrication si listée dans `proprietes_immuables_composition.json` ; (b) lue À LA DEMANDE par un mécanisme ou un câblage, jamais fusionnée (`permeabilite`, `porosite` pour l'humidité, `type_nutriment`) ; (c) DORMANTE — présente sur les fiches, lue par personne (`opacite`, `absorption_sombre`, `sensibilite_magique`, `couleur_physique`). UNITÉ : `densite` en g/cm³, convertie une seule fois en kg/m³ par `objet.gd`. `type_nutriment` est la seule propriété NON NUMÉRIQUE : elle ne peut jamais être fusionnée (la fusion est une moyenne pondérée), elle se lit directement sur la fiche. Deux grandeurs voisines ne se dérivent JAMAIS l'une de l'autre : `inflammabilite` (facilité à s'enflammer) vs `pouvoir_calorifique` (quantité à brûler) ; `sensibilite_radiation` (subir) vs `force_radiation` (émettre). Les matériaux terminaux (`rouille`, `compost`, `cendre`, `eclats_*`, `residu_*`, `scories`, `humus`) ne déclarent que `densite` : tout le reste retombe à `0.0` par le défaut facultatif de la fusion, et c'est EXACTEMENT la dégradation recherchée. | `objet.gd` (`densite` toujours, plus toute propriété listée dans `proprietes_immuables_composition.json`), `quantite_matiere.gd`, `champ.gd`, `temperature.gd`, `seuil_etat.gd`, `etat_effectif.gd`, et les bancs qui lisent à la demande |
| `champs.json` | `nom_champ -> { propriete_source, signe, exposant, portee, plancher_distance, plafond_deplacement, duree? }`. Une entrée, `magnetisme`. `duree` est PORTÉE PAR LE SCHÉMA, LUE PAR AUCUN CODE : une source éphémère exigerait de retirer un objet du monde, capacité absente de `monde.gd`. Toute clé commençant par `_` est ignorée à l'itération. | `champ.gd`, `banc_champ.gd`, `banc_velocite.gd` |
| `comptages.json` | `regle_id -> { propriete, mode, valeur_reference?, champ_element? }`, `mode` ∈ `presente`/`egale`/`superieur_a`/`contient_element_avec_champ`. `comptage.gd` n'a AUCUNE notion d'espace : c'est toujours l'appelant qui construit la liste, ce qui permet à une seule règle de servir deux questions différentes (population d'un biome, densité autour d'un point). `comptage_ref` est vérifié ici par le linter. | `comptage.gd`, `test_lint_donnees.gd`, bancs |
| `genes.json` | Référence → `{ cibles: Array de { chemin, poids }, mode_expression }`, `mode_expression` ∈ `dominant`/`recessif`/`additif`/`incomplet`/`codominant`. `chemin` est un chemin en points. `codominant` n'est PAS implémenté (non traduisible en une valeur scalaire) : il alarme et contribue `0.0`. Résolu par `proprietes.genes_actifs`. DORMANT EN PRATIQUE : `expression.gd` sait le lire, aucun câblage réel ne le lui passe — les deux bancs génétiques utilisent un catalogue LOCAL. | Personne en pratique |
| `epigenetique.json` | `nom_marque -> { cible, modulateur_pose, taux_decroissance, plancher_suppression, taux_transmission_enfant, source_environnementale }` — PAR MARQUE, jamais un `defaut` partagé. `cible` est lue par `expression.gd` seul, jamais par `epigenetique.gd`. `taux_decroissance` est un montant ABSOLU par seconde. CONTRAINTE DE CADENCE, résultat négatif mesuré deux fois : `plancher_suppression` doit rester nettement sous `modulateur_pose`, et un câblage qui pose à un intervalle supérieur à `(modulateur_pose - plancher_suppression) / taux_decroissance` n'accumule JAMAIS rien — la marque est effacée entre deux poses, et rien ne rougit. | `epigenetique.gd`, `expression.gd` (`cible`), `heredite.gd` (`taux_transmission_enfant`), bancs |
| `senescence.json` | Référence → `{ cible, age_debut, modulateur_par_annee, mode }`, `mode` ∈ `lineaire`/`exponentiel`/`plafonne`. Seul `lineaire` est implémenté : les deux autres exigent un champ absent du catalogue, alarment et contribuent `0.0`. Aucune liste « senescence_actifs » — chaque courbe s'applique dès que `age` franchit son `age_debut`. Modulateurs calculés à la volée, jamais stockés. DORMANT EN PRATIQUE : aucun câblage ne passe ce fichier à `expression.gd`. | Personne en pratique |
| `heredite.json` | Une entrée `"defaut"` → `{ taux_mutation_base, taux_mutation_asexuee, ecart_type_mutation, modulateurs_environnementaux, modulateurs_age_parent }`. Les deux `modulateurs_*` sont DORMANTS : aucun paramètre d'environnement ni d'âge n'est reçu, aucun des deux concepts n'est cadré. | `heredite.gd:fabriquer_genes_enfant` |
| `reproduction.json` | `reproduction_ref -> { seuil_accouplement, taux_montee, duree_gestation }`. `mode_reproduction`/`espece_reproduction`/`stades_fertiles`/`role_gestation` vivent SUR LE TYPE, jamais ici — `role_gestation` (`porteur`/`non_porteur`/`les_deux`, défaut vide) décide seul qui reçoit l'état de gestation. Sur une entrée en mode `"asexuee"`, `seuil_accouplement`/`taux_montee` sont INERTES — `accouplement.gd` ne s'exécute que pour `"sexuee"`, seul `duree_gestation` y est lu. `reproduction_ref` est vérifié ici par le linter — et le paquet `dynamique` ne la porte donc plus : une référence de catalogue VIDE n'existe pas, seule l'absence de clé dit « aucune référence ». | `accouplement.gd`, `gestation.gd` |
| `usure_attaches.json` | Une entrée `"defaut"` → `{ taux_usure_passive, taux_usure_contradiction, force_plancher }`. L'usure est UNIVERSELLE, jamais une règle choisie par trait. `force_plancher` est STRICTEMENT POSITIF et l'entrée n'est JAMAIS retirée de `proprietes.attaches` — patron inverse de tout autre plancher du dépôt, qui supprime l'entrée. FICHIER MORT EN PRATIQUE : `usure_attache.gd` reçoit son catalogue EN PARAMÈTRE et aucun appelant ne lui passe celui-ci — ni banc, ni test (son test fabrique le sien). Aucun `res://data/usure_attaches.json` n'existe dans `scripts/`. | personne |
| `contradictions_attaches.json` | `regle_id -> { trait, trait_contradictoire }` ; le fichier est ITÉRÉ EN ENTIER, aucune référence choisie par l'entité. Catalogue VIDE = point neutre légitime, jamais une alarme. FONDATION DORMANTE : une seule entrée hors domaine. FICHIER MORT EN PRATIQUE, même raison que `usure_attaches.json` ci-dessous : aucun appelant ne le charge. | personne |
| `etats.json` | `nom_etat -> { duree?, effets: Array de { propriete, mode: "ecraser" \| "moduler", valeur \| facteur } }`. `duree` est lue par `etat_duree.gd` SEUL, jamais par `etat_effectif.gd`. ÉCRASER gagne toujours sur MODULER ; deux écraseurs sur la même propriété sont départagés par TRI ALPHABÉTIQUE du nom d'état — reproductible, mais c'est un arbitrage par orthographe : à éviter en donnée. QUATRE FAMILLES DE RÉVERSIBILITÉ, à choisir explicitement : par le TEMPS (`duree`, ex. `mouille`) ; JAMAIS (sans `duree`, sur une grandeur monotone, ex. `fracture`, `rompu`) ; par FRANCHISSEMENT DESCENDANT d'un miroir plat qui redescend (`seuil_etat.gd`, ex. `epuise`, `sale`) ; par le CÂBLAGE qui pose ET retire lui-même (marqueur de `charge.gd` relayé, ex. `malnutri`). `effets: []` est légitime et fréquent : un MARQUEUR PUR, dont seule la PRÉSENCE est lue pour gater un câblage. PIÈGE STRUCTUREL : déclarer un effet ne produit RIEN si personne ne compose `etat_effectif.gd` — `depense.gd` ne le consulte jamais et `banc_commun.gd:agents_rythme` lit `rythme` BRUTE. SECOND PIÈGE : `etat_effectif.gd` rend `base × facteur`, donc un objet sans la propriété EN BASE donne `0.0` — mortel pour une propriété utilisée comme DIVISEUR. TROISIÈME PIÈGE, payé deux fois : deux chantiers parallèles ajoutant la même clé produisent une COLLISION JSON silencieuse, `parse_string` ne gardant que la dernière. `etats_actifs` est vérifié ici par le linter. | `etat_effectif.gd` (`effets`), `etat_duree.gd` (`duree`), `test_lint_donnees.gd`, bancs |
| `proprietes_immuables_composition.json` | `proprietes` : Array de String — les propriétés de `materiaux.json` fusionnées UNE FOIS à la fabrication par la même moyenne pondérée des volumes que `densite`, mais FACULTATIVE par fiche (absente → `0.0`, aucune alarme). C'est ce fichier, et lui seul, qui fait passer une propriété matériau du statut DORMANT au statut lisible sur un objet fabriqué. RISQUE ACCEPTÉ, documenté et non corrigé : le défaut `0.0` fausse une composition MIXTE mêlant un matériau qui déclare la propriété et un qui ne la déclare pas. Toléré tant que la valeur `0.0` reste un seuil BAS inoffensif ; corrigé PAR LA DONNÉE quand ce n'est pas le cas — `seuil_sublimation` est déclaré explicitement à une valeur jamais atteinte sur chaque fiche, parce qu'un `0.0` y serait une température banale franchie dès l'ambiante (défaut réel constaté : un `verre_demo` incomplet posait `liquide` dès sa fabrication). Une propriété n'est fusionnée que si un mécanisme ou un état a besoin d'une BASE non nulle à moduler. Une liste LOCALE peut être passée par un banc pour étendre la fusion sans toucher ce catalogue partagé — c'est ce qui préserve la dormance actée ailleurs. | `objet.gd:fabriquer` (paramètre `proprietes_immuables`), et les lecteurs de chaque propriété fusionnée |
| `seuils_etat.json` | `ref -> { propriete_continue, seuil_propriete? (LU PAR OBJET), seuil? (universel), etat }` — UN SEUL état par entrée, posé au-dessus, retiré en dessous. Deux entrées peuvent viser le MÊME nom d'état sans collision : `seuil_etat.gd` tient sa mémoire PAR ENTRÉE. `seuil_propriete` absent sur un objet replie sur `INF` — un objet sans `point_fusion` ne fond jamais. La `propriete_continue` est presque toujours une grandeur qui N'EXISTE QUE parce qu'un câblage l'écrit lui-même (`degats_impact_cumules`, `intensite_sonore_cumulee`, `force_traction_cumulee`, `exposition_acide_cumulee`, `dose_radiation_cumulee`, `manque_*`, `froid_ressenti`…). CONTRAINTE STRUCTURELLE : `seuil_etat.gd` ne lit qu'une clé PLATE et ne compare que vers le HAUT — une réserve vivant sous `proprietes.reserves.<nom>.reserve` lui est inatteignable, et « descendre sous un seuil » n'est pas exprimable. D'où les MIROIRS PLATS, parfois INVERSÉS (`capacite - reserve`), écrits par le câblage. Aucune entrée `solide` : « solide » est l'absence de `liquide` et de `gaz`. `"_note"` est ignorée à l'itération. | `seuil_etat.gd` (reçu en paramètre), bancs (catalogue partagé passé TEL QUEL, les entrées non concernées étant des chemins morts silencieux) |
| `flux.json` | Table de règles `{ source, receptrice, cible }` par ligne, analogue à `menaces.json`. `portee_flux`/`taux_flux` sont posés sur la SOURCE à la fabrication, jamais dans la table. Un `taux_flux` négatif VIDE la réserve — le mécanisme est neutre, ce n'est pas « le gain ». | `flux.gd`, `banc_animal.gd` |
| `intensite_propagation.json` | Configuration de `propagation.gd:delai_ignition` : `propriete_intensite`, `seuil_ignition`, `propriete_point_ignition`. FACULTATIF par construction — absent, l'allumage reste au `delai_propagation` fixe. Les deux gates (proxy d'intensité, point d'ignition) COEXISTENT : aucun ne remplace l'autre. | `propagation.gd`, `banc_inflammabilite.gd`, `banc_emission.gd` |
| `emission_propagation.json` | Configuration de `propagation.gd:recu`/`seuil_exposition` : `portee_emission_base`, `portee_emission_par_capacite`, `nom_reserve`, `seuil_base`. FACULTATIF — absent, l'exposition retombe sur le test `portee_propagation` d'origine. Sépare deux grandeurs que `portee_propagation` confondait : ce qu'une source ÉMET et ce qu'une cible ACCEPTE. | `propagation.gd`, `banc_emission.gd` |
| `reserve_combustible_composition.json` | `{ nom_reserve, propriete_materiau, propriete_porosite, cout_base, facteur_densite, facteur_porosite, surcout_action, seuils_ref }` — les huit champs sont REQUIS (l'un manque : alarme, rien n'est écrit). Pilote le canal de combustible calculé UNE FOIS à la fabrication : `capacite` (somme pondérée par volume, EXTENSIVE) et `cout_base` EFFECTIF (dense ralentit, poreux accélère). `capacite` n'est plus jamais réécrite ensuite ; `reserve` est le seul champ que `depense.gd` décrémente. | `objet.gd:fabriquer`, bancs |
| `vent.json` | Une entrée `defaut`. Trois couches ADDITIVES, chacune désactivable en donnée sans casser les deux autres (`fond`, `variation_lente`, `rafales`), plus `attenuation_source.exposant` et `directionnel` (`reference_force`, `facteur_max_sous_vent`, `facteur_min_contre_vent`). Une amplitude ou une période nulle retombe sur « cette couche ne contribue rien », jamais une alarme. Perpendiculaire au vent vaut TOUJOURS exactement `1.0` — propriété de l'interpolation en deux morceaux, jamais une valeur de donnée. | `vent.gd`, `perception.gd` (odorat, facultatif), `banc_vent.gd` |
| `temperature.json` | Une entrée `defaut` : `ambiante` et `attenuation.exposant`. Catalogue absent : repli sur `0.0`, PAS sur l'ambiante — un repli plausible maquillerait une erreur de câblage en lecture normale. | `temperature.gd`, bancs thermiques |
| `lumiere.json` | Une entrée `defaut` : `ambiante` (`{ intensite, couleur }`), `attenuation.exposant`, `cycle` (`heures_par_jour`, `heure_midi`), `courbe_couleur` (Array `{ heure, couleur }` TRIÉE, premier et dernier point identiques pour boucler sans code spécial), `latitude_demonstration`. `ambiante` est une valeur de REPLI : l'appelant est censé y écrire le résultat de `lumiere.gd:soleil` à chaque tick — sa valeur de nuit garantit qu'un appelant qui l'oublie retombe sur l'obscurité plutôt que d'inventer de la lumière. La couleur est une TEMPÉRATURE DE COULEUR scalaire, jamais un RGB. | `lumiere.gd`, bancs |
| `soudure.json` | Une entrée `defaut` : `portee_contact`, `seuil_charge`, `taux_decroissance`, `nom_marqueur`, plus le gabarit de la source interactive (`rayon`, `temperature`, `force`). `soudure.gd` ne charge JAMAIS ce fichier — il ne connaît ni portée ni seuil, seulement des compositions : détection et déclenchement vivent entièrement au câblage. | `banc_soudure.gd` |
| `croyances.json` | `{ proprietes_observables, proprietes_conservees, certitude_initiale, gain_par_verification, plafond_certitude, taux_decroissance, plancher_suppression, gain_par_echec, resistance_par_certitude, seuil_bornes_transmission }`. `proprietes_conservees` est structurel au sens fort : sans elle, `croyance.gd:filtrer` rendrait des perceptions privées de leurs pointeurs de catalogue et TROIS fichiers de la chaîne deviendraient muets sans que rien ne rougisse. `seuil_bornes_transmission` n'est JAMAIS lu par le mécanisme : c'est au câblage de renoncer à transmettre en dessous. Une propriété absente de `proprietes_observables` ne s'apprend que par contact ou par autrui. | `croyance.gd` (reçu en paramètre), bancs |
| `memoire_spatiale.json` | Une entrée `"defaut"` → `{ force_initiale, taux_decroissance, plancher_suppression, coef_memoire_faible, coef_nuit }`. L'erreur du souvenir est DÉTERMINISTE : aucun RNG. Elle a deux moitiés — COMBIEN (ces deux coefficients) et VERS OÙ (une direction dérivée du hash de l'id, donc stable dans le temps : le souvenir dérive toujours du même côté, il ne tremble jamais). | `memoire_spatiale.gd`, `banc_memoire_navigation.gd`, `banc_oubli_consolidation.gd`, `banc_temps_anticipation.gd` |
| `sorts.json` | `nom_sort -> { effet, grandeur, cible, portee, cout_mana }`. `effet` est dispatché vers un mécanisme du cœur, jamais un mécanisme référencé par nom de sort. `grandeur` porte les paramètres DÉJÀ à la forme attendue par ce mécanisme. `cible` (`"objet"`/`"soi"`/`"zone"`) est lue par le seul câblage. Un sort est un ÉVÉNEMENT PONCTUEL : les effets continus sont appelés avec `delta = 1.0`, la grandeur servant de quantité appliquée une fois. | `banc_sorts.gd` |
| `biomes.json` | MÊME FORME EXACTE que `emergences.json` et LU PAR LE MÊME MÉCANISME (`conditions.gd`) — seul le point d'appel diffère : `emergences.json` une fois à la fabrication et sans retrait, celui-ci à CHAQUE TICK avec `retirer_si_faux` (un biome est réversible). Quatre entrées posant TOUTES la clé `biome`. ORDRE PORTANT : deux entrées peuvent être vraies ensemble, et c'est la DERNIÈRE déclarée qui gagne. Les conditions NE PAVENT PAS tout l'espace climatique : une case qui ne remplit rien ne porte AUCUNE clé `biome`, et cette absence est voulue plutôt qu'un biome par défaut inventé. UNITÉS : humidité en ratio [0,1], température en °C. | `conditions.gd` (reçu en paramètre), `banc_biomes.gd`, `banc_ecosysteme_terrain.gd` |
| `textes.json` | Textes affichés, par clé. Seul fichier de chaînes visibles : le code manipule des CLÉS, jamais une chaîne composée par concaténation (`CLAUDE.md`, internationalisation). | bancs (affichage) |
| `attaches_exemple.json`, `proximite_exemple.json` | Scènes d'exemple pour les tests : ne portent que `attaches`/`forme`, le test enveloppe dans `{ proprietes: ... }` au chargement. | tests correspondants |

### Données de banc (jetables, une par banc)

Chaque `banc_*.json` est chargé par le `_ready` de son banc et par lui seul.
Convention générale, valable pour tous et non répétée ligne à ligne : ils
portent positions, couleurs, calibrations et NOMS DE CHAMP passés en
paramètre (aucun nom de contenu en dur dans le `.gd`), plus des types LOCAUX
quand le banc a besoin d'une déclaration que `data/types.json` n'a pas à
porter. Seul ce qui NE SE DÉDUIT PAS de cette convention est noté ci-dessous.

| Fichier | À savoir |
|---|---|
| `banc_p1.json` | Données PROPRES à chaque colon seulement (`position`, `attaches`, `forme`, `poids_verbes`) — `rythme`/`canaux`/`vitesse`/`reserves`, communs à tout colon, vivent dans `types.json`. |
| `banc_feu.json` | `catalogue_local` est la SEULE table à définir la propriété `abrite`, absente de tout `data/` partagé. Les deux colons ne diffèrent que par `forme.gain_jugement`. |
| `banc_animal.json` | `comportement.surcout_mouvement` seul subsiste — les seuils d'engagement ont migré vers `engagements.json`. |
| `banc_deformation.json` | — |
| `banc_lien_personnel.json` | `catalogue_local` fait résoudre `eteindre` pour `brule` ; le `types_choses.json` partagé garde `approcher`. Le type local `feu_ouvrage` porte `notre_ouvrage` : chaque feu cliqué devient candidat à son propre acte liant. |
| `banc_champ.json` | AUCUNE table `materiaux` locale : le linter valide tout champ `materiau` contre le catalogue partagé, ce qui a forcé les deux matériaux de ce banc à y entrer. |
| `banc_charge.json` | `catalogue_local` porte la SEULE définition de `refuge`, absente de tout `data/` partagé. Les deux colons ne diffèrent que par le seuil de leur canal de charge. |
| `banc_comptage.json` | HORS DOMAINE strict : six lucioles, aucun contenu Orion. `comptage_ref` vise `poissons_luisants`, l'entrée hors domaine déjà présente dans le catalogue partagé — ce banc n'y ajoute rien. `seed` fixe, aucune bascule non seedée. |
| `banc_contagion.json` | Colons construits À LA MAIN, jamais `Objet.fabriquer` : le canal de charge est déclaré ENTIER ici, `charge.gd` recevant toujours son catalogue en paramètre. |
| `banc_controle.json` | `golem` et `feu` restent LOCAUX pendant que `colon` est lu du catalogue partagé, INCHANGÉ. C'est cette asymétrie qui prouve que la différence « obéit » / « décide seul » vit entièrement en donnée. SEUL CAS DU DÉPÔT qui illustre la doctrine des compartiments : le golem redéclare les cinq réserves de `dynamique`, quatre d'entre elles ÉTEINTES (pleines, sans coût). |
| `banc_convergence_attache.json` | AUCUN seed, aucun RNG : contrairement à `banc_comptage.json`, l'écart entre les trois colons vient de seuils individuels, jamais du hasard. |
| `banc_croissance.json` | Les cinq noms de propriété que lit le câblage sont en donnée (`propriete_source_croissance`, `nom_reserve_maturite`…) : le `.gd` n'en nomme aucun. |
| `banc_fracture_sonore.json` | `seuil_fragilite_eclats` est LOCAL : il décide si un objet fracturé se transforme en éclats ou reste déformé. Jamais monté au partagé — deux bancs le calibrent différemment. |
| `banc_genetique.json` | `catalogue_genes` LOCAL, jamais `data/genes.json` (resté dormant) : une règle de banc de démonstration ne rejoint le catalogue partagé que si un second banc en a besoin. |
| `banc_permeabilite.json` | `taux_decroissance_plancher` STRICTEMENT positif : c'est lui qui garantit qu'un objet imperméable finit par sécher, au lieu de rester saturé à vie. |
| `banc_reproduction.json` | `catalogue_genes` LOCAL (même discipline que `banc_genetique.json`), un seul gène à UNE seule cible, et les deux parents HOMOZYGOTES aux extrêmes — l'enfant naît donc à la vitesse de base sauf mutation, et l'écart EST la preuve de l'héritage. `seed` fixe. |
| `banc_vecu_inter_colon.json` | `position_apparition_troisieme` est calculée hors de TOUTE portée de perception des deux premiers (marge déterministe au-delà du plus grand rayon réel), jamais un grand nombre choisi à vue. |
| `engagements.json` | Catalogue PARTAGÉ de `couplage.gd` : `poids`, `seuil_satisfait`/`seuil_bascule`, `sens_satisfaction`, `satisfait_par`, `arrache_par`. Un banc dont les saillances sont à une autre échelle passe un catalogue LOCAL au même format plutôt que d'ajouter une entrée ici. |
| `proximite_exemple.json` | Scène d'exemple pour les tests de `proximite.gd` : ne porte que `profils_saillance` et des colons `attaches`/`forme`, le test enveloppant lui-même dans un monde. Aucun contenu de jeu. |
| `banc_etat_effectif.json` | Quatre rôles (`sans_etat`/`ecrase`/`module`/`ecrase_et_module`) : le dernier rend la même valeur que `ecrase` seul, preuve à l'écran que l'écraseur gagne toujours. |
| `banc_inflammabilite.json` | Même `delai_propagation` et même portée pour les quatre objets : seule l'inflammabilité effective explique l'écart observé. |
| `banc_etat_duree.json` | Un état AVEC `duree` face à un état SANS : contraste épuisable/permanent. |
| `banc_combustible.json` | Sept objets calibrés pour isoler trois variables séparément : le volume (trois bois), le matériau à volume égal (fer vs bois), et la densité/porosité à CAPACITÉ ÉGALE (la paire `dense_vs_poreux_*`). |
| `banc_emission.json` | Deux feux de volumes différents, quatre cibles à distance IDENTIQUE : seule la capacité de la source et la matière de la cible expliquent qui s'enflamme. |
| `banc_vent.json` | `portee_odorat` surchargée plus court que le défaut, pour que le cercle de sources ne soit jamais capté sans effet réel du vent. Ne déclare AUCUN vent : charge `vent.json` partagé. |
| `banc_temperature.json` | `objet_test` porte `conductivite_thermique` posée en donnée LOCALE, jamais dérivée de `materiaux.json` (aucune composition dans ce banc). |
| `banc_point_ignition.json` | Deux cibles de MÊME matière, MÊME distance, MÊME délai — seule la température locale diverge. |
| `banc_transformation_produit.json` | L'agent qui mange le chantier est un point `{position, rythme}` collé à l'objet, pas un colon : `extinction.gd` exige des agents à portée. |
| `banc_humidite.json` | Cinq objets : trois isolent `absorption_humidite`, deux isolent la POROSITÉ à absorption strictement égale (composition mixte dosée pour ça). |
| `banc_changement_etat.json` | Source à distance NULLE de l'objet (atténuation toujours pleine) ; au-delà de `duree_chauffe` elle disparaît et l'objet retombe vers l'ambiante par la même loi de Newton. |
| `banc_soudure.json` | Le bois est à la MÊME distance de contact que les deux fers : seule la matière l'exclut de la soudure, jamais la mise en scène. |
| `banc_dilatation.json` | `dilatation_thermique` est une valeur DE DÉMONSTRATION locale, jamais celle de `materiaux.json` : la formule littérale rendrait le volume d'un objet réel démesuré sur l'écart de température voulu ici. |
| `banc_pourriture.json` | `reserve_integrite_defaut.seuils_ref` pointe vers le catalogue PARTAGÉ, jamais une table locale (contrainte du linter). Réserve calibrée avec marge au-dessus de `cout × duree` pour qu'une coupure précoce de la source sauve réellement l'objet. |
| `banc_corrosion.json` | Quatre objets, TROIS destins : un seul porte une réserve d'intégrité et suit la phase de transformation ; les trois autres sont COSMÉTIQUES (patine, ternissure) — la différence tient à la seule présence de la clé `reserves`, jamais à un test de type. L'état cible et la propriété visée vivent SUR CHAQUE OBJET, pas dans la config commune : l'oxydation produit des effets chimiquement différents selon le métal. |
| `banc_stress_thermo_vivant.json` | Quatre bascules indépendantes (froid sous une cible, chaud au-dessus d'un autre seuil, sécheresse sous un seuil, excès d'eau au-dessus d'un autre) : jamais un `abs()` unique, quatre nombres par vivant et quatre poids indépendants. Catalogue de seuils LOCAL, seuils lus PAR OBJET. |
| `banc_porosite.json` | Deux matériaux de démonstration identiques SAUF la porosité (densité comprise) : la même propriété traverse humidité et combustion en parallèle. Source d'eau et combustion sont indépendantes — couper l'eau n'arrête pas le feu. |
| `banc_solubilite.json` | Le `cout_base` de la réserve n'est pas constant : il vaut `facteur_dissolution × solubilite`, gelé tant que `mouille` est absent. |
| `banc_conduction.json` | Trois rangées isolent trois choses : le blocage par un isolant, la traversée d'une chaîne, et l'effet ×10 de `mouille` sur la conductivité à matériau égal. |
| `banc_foudre.json` | `criteres` calibrés pour que la hauteur seule ne batte JAMAIS un objet conducteur : elle ne fait que départager entre deux conducteurs. `degats` égale la réserve entière — une frappe détruit sa cible d'un coup. |
| `banc_fracture.json` | `rayon_frappe` petit devant l'espacement des objets : c'est LUI qui fait office de visée au clic, pas `criteres` (quasi neutre). `transformation_fracture` est vide pour le fer — il se déforme sans jamais se transformer. |
| `banc_chaleur_emise.json` | Les deux objets froids sont à distance IDENTIQUE de leur propre foyer, et les deux foyers au-delà du double de leur rayon d'émission : aucune contamination croisée. Volumes calibrés pour que les deux brûlent une durée comparable. |
| `banc_lumiere.json` | Cinq lecteurs, un par phénomène à montrer (cycle pur, torche fixe, recouvrement de deux couleurs, source mobile suivie, source mobile de passage). `cycle_reel` mappe des secondes réelles sur les heures du catalogue partagé, jamais `24.0` en dur. |
| `banc_photodegradation.json` | `reserve_integrite_defaut` ne porte PAS `seuils_ref` (clé absente, jamais une chaîne vide) : ce banc observe une décroissance, il ne configure aucune transformation terminale. Deux objets ne se dégradent jamais, pour DEUX raisons différentes (position hors portée / biodégradabilité nulle). |
| `banc_reflectivite.json` | Conductivité et chaleur spécifique sont des constantes LOCALES partagées par les trois objets : les fusionner aurait fait venir l'écart de température d'une donnée manquante plutôt que de la réflectivité. |
| `banc_son.json` | `frequence` est posée EN DUR par déclaration de type, jamais une propriété matériau. Deux sources partagent le MÊME `son_emis` et ne diffèrent que par la fréquence : preuve que les deux filtres sont indépendants. |
| `banc_resonance.json` | La source est un point d'émission abstrait, jamais un objet fabriqué — rien à fusionner sur un point. Deux objets sont SYMÉTRIQUES par rapport à l'axe source-colon : seule la résonance diverge. |
| `banc_occlusion.json` | Marge volontairement fine entre l'intensité sans mur et le seuil : le mur réel (5 % d'absorption) suffit à faire basculer, jamais un mur artificiellement fort. |
| `banc_absorption_sonore.json` | Seuil VOLONTAIREMENT NUL, à l'inverse du banc précédent : ce banc montre un POURCENTAGE de réduction, jamais une coupure. |
| `banc_friction.json` | Trois objets FABRIQUÉS par composition, justement parce que ce chantier démontre que `friction` est désormais fusionnée. |
| `banc_restitution.json` | `position.z` porte la hauteur, rendue par `Vector2(x, y - z)`. Aucune physique Godot : un calcul de position par tick. |
| `banc_rigidite.json` | Catalogue de seuil LOCAL, jamais ajouté au partagé : la grandeur comparée est propre à ce mécanisme. La flèche MAXIMALE ATTEINTE ne redescend jamais — une poutre reste visuellement déformée après retrait de la charge. |
| `banc_elasticite.json` | PIÈGE de calibration : sur les valeurs réelles, le rapport `elasticite/rigidite` de deux matériaux coïncide, donc la quantité récupérée EN ABSOLU est identique — seule la FRACTION récupérée les ordonne. |
| `banc_coupe.json` | L'outil porte `tranchant_effectif`, grandeur PROPRE À CE BANC, jamais dans `materiaux.json` : elle s'émousse à chaque coupe selon la dureté de la cible. Un tranchant nul ne coupe plus PAR LA SEULE ARITHMÉTIQUE. |
| `banc_usinabilite.json` | Rien ne descend avant le premier clic (contraste volontaire avec les bancs qui démarrent seuls). |
| `banc_traction.json` | `position.z` porte la hauteur, comme `banc_restitution.json` — mais un objet rompu tombe SANS jamais rebondir. |
| `banc_velocite.json` | Types locaux ; reprend le golem/aimant de `banc_champ.json` sans dupliquer aucune donnée. Un repère jamais touché par aucun mécanisme prouve que la vélocité nulle est un RÉSULTAT, pas une propriété. |
| `banc_acide.json` | Trois objets, aucun mouvement : la corrosion ne fait que changer une couleur et moduler deux propriétés. |
| `banc_toxicite.json` | Le colon se déplace par index circulaire sur trois positions fixes, jamais une position calculée ailleurs. |
| `banc_mana_conduction.json` | `seuil_conduction_mana` est VOLONTAIREMENT différent du seuil électrique : même propriété matériau, deux domaines, deux seuils. |
| `banc_choc_magique.json` | `sensibilite_magique` est le SEUL critère de sélection ; la distance reste le filtre de portée de `frappe.gd`, jamais une seconde source de score. Un caster PAR CIBLE (rayon petit) pour que les trois progressent en parallèle plutôt qu'un seul vainqueur monopolise les frappes. |
| `banc_reactivite.json` | La constante de consommation est calibrée pour que la décroissance organique de l'acide ne touche JAMAIS zéro avant que la cible la plus lente ait fini de réagir. |
| `banc_radiation.json` | Trois objets à ÉGALE distance, disposés PERPENDICULAIREMENT au segment source→mur : aucun ne tombe sur ce segment, seule la sensibilité explique l'écart. |
| `banc_manger.json` | `profil_saillance` et `type_produit` sont vérifiés par le linter contre les catalogues PARTAGÉS quel que soit le fichier source : une table locale n'aurait jamais été validée. Deux objets ne portent NI `comestible` NI `profil_saillance` — structurellement non saillants, jamais candidats. |
| `banc_magie_perception.json` | `magie_config` POSE tout `canaux_config.magie` : le type partagé `colon` ne porte pas ce canal, contrairement à l'ouïe qui n'est que surchargée. |
| `banc_produit_nucleaire.json` | La source hand-built porte une `masse` posée à la main : sans elle, `produit.gd` calcule un résidu de volume nul et la fabrication est refusée. |
| `banc_sorts.json` | `volatilite_magique` est posée À LA MAIN sur les cibles, jamais les valeurs de `materiaux.json` : celles-ci sont hors d'échelle avec des dégâts de sort ET dans un ordre qui contredirait la démonstration. |
| `banc_activation_neutronique.json` | La source primaire n'a AUCUNE réserve (toggle tout-ou-rien). Les canaux du colon sont recopiés d'un autre banc, jamais référencés. |
| `banc_emergences.json` | Bistable AVANT/APRÈS : aucun tick requis, l'émergence se décide entièrement à la fabrication. Étend une liste LOCALE de propriétés immuables pour ne pas rompre une dormance actée ailleurs. |
| `banc_chaine_reactions.json` | Trois objets dont un fixe au centre : le produit de la première réaction devient réactif de la seconde AU TICK SUIVANT, jamais dans le même appel. |
| `banc_maladie.json` | Incubation, durée et seuil de mort sont DUPLIQUÉS ici et dans les catalogues partagés : `etat_duree.gd`/`seuil_etat.gd` sont génériques et ne lisent jamais un fichier de banc. Le seuil de mort est délibérément SOUS la durée de maladie — un malade meurt avant de guérir. |
| `banc_ecoulement.json` | `position` en unités de GRILLE, `z` toujours nul : l'altitude vit dans une propriété nommée. Si elle vivait dans `position.z`, l'écart entre deux cases adjacentes dépasserait à lui seul le rayon de voisinage et casserait tout voisinage — vérifié par le calcul avant d'écrire. |
| `banc_succession.json` | Les quatre noms de stade n'existent QUE dans ce fichier : `stade.gd` n'en connaît aucun. `colonne_sterile` porte la condition de croissance à `false` : horloge à zéro, elle ne progresse jamais. |
| `banc_cratere.json` | TROIS propriétés d'altitude aux contrats disjoints : la base (jamais réécrite), le creusement (écrit à l'impact, effacé par `depense.gd`) et l'effective (dérivée chaque tick, seule passée à `ecoulement.gd`). Aucune absorption ni évaporation : la variable observée est le cratère, pas la perte d'eau. |
| `banc_simulation_acceleree.json` | Trois champs portants : le nombre d'itérations par tick, le delta FIXE et PETIT, et le facteur d'échelle en années. Le débit en années ne dépend QUE du facteur d'échelle — le nombre d'itérations ne règle que la finesse du pas physique. Absorption et évaporation volontairement bien plus basses qu'au banc d'origine : à cette vitesse, ses valeurs videraient la grille avant qu'aucune succession ne soit observable. |
| `banc_fertilite.json` | `capacite` est posée sur le canal mais n'est JAMAIS lue par `depense.gd` : c'est le câblage qui écrête. Un `cout_base` NÉGATIF fait REMONTER la réserve — neutralité du mécanisme exploitée, jamais contournée. |
| `banc_erosion.json` | Catalogue de vent PROPRE au banc (vent constant) : le `vent.json` partagé tourne et rend une érosion orientée illisible. `sources_vent` est DÉCLARÉE ET VIDE — porte d'entrée, aucune source posée. |
| `banc_ombre_pluvio.json` | `relief_bloquant` est une NORMALISATION [0,1] de l'altitude : l'altitude brute clamperait à 1.0 dans `occlusion.gd` et bloquerait TOTALEMENT au lieu de graduer. Profil de montagne (sommet + deux épaules), jamais un mur : c'est cet écart qui gradue l'ombre. |
| `banc_biomes.json` | Deux axes croisés (humidité en colonnes, température en lignes) : les cinq rendus possibles sont présents dès le démarrage sans aucun clic. La palette est le SEUL endroit du chantier où un nom de biome rencontre une couleur. |
| `banc_fatigue_circadien.json` | La zone circadienne ENJAMBE MINUIT : elle s'écrit en DEUX entrées de `conditions.gd` posant la même clé, ce que les deux passes disjointes du mécanisme rendent sûr. |
| `banc_faim_thermo.json` | Deux miroirs thermiques distincts (froid sous une cible, chaud au-dessus d'un autre seuil), jamais un `abs()` unique : deux seuils, deux coûts par degré. La température de CONFORT n'est pas celle d'un corps — la prendre à 37° rendrait le colon hypothermique partout, y compris en zone chaude. |
| `banc_hygiene_apparence.json` | Le seuil de perception est INDIVIDUEL, sur chaque colon. La liste `canaux` héritée est REMPLACÉE, pas étendue : la vue, à longue portée et sans filtre d'intensité, ferait capter tout colon à toute distance et ni l'odeur ni le seuil ne prouveraient plus rien. |
| `banc_nutrition.json` | Trois réserves aux `cout_base` en rapport 1:3:10. `contenu` volontairement énorme : ce banc observe le CORPS, jamais l'épuisement du plat. Le seuil de qualité est la SOMME des trois réserves sous laquelle le câblage synthétise une cause à distance nulle. |
| `banc_elimination_salete.json` | Catalogue de seuils LOCAL au format du partagé, passé tel quel. DEUX RÉSULTATS NÉGATIFS chiffrés dans le `_note` du fichier : une calibration qui exposait le premier colon à ses PROPRES déchets avant qu'un tas soit visible, et un colon MORT qui continuait d'éliminer (invisible au test, trouvé en lançant). |
| `banc_graisse_accoutumance.json` | Le plafond d'accoutumance est une CONDITION DE CORRECTION, pas de confort : au-delà de 1.0, le facteur devient négatif et le froid RECHARGERAIT le colon. Cadence de pose sous la contrainte d'`epigenetique.json`, sans quoi la marque n'accumule jamais rien. |
| `banc_bonheur.json` | Les CINQ mêmes sources sont posées sur les QUATRE colons aux MÊMES niveaux : rien dans le monde ne les distingue, seuls leurs poids diffèrent. Contrainte de calibration : `capacite - seuil_haut` doit rester sous le seuil bas, sinon un colon serait heureux ET malheureux en même temps. |
| `banc_psycho_social.json` | Catalogue de seuils LOCAL. Le palier de départ n'est JAMAIS à ratio 1.0 : à l'égalité stricte, la bifurcation refuse de trancher et alarme à chaque tick. |
| `banc_menace_combat.json` | Colons construits à la main exprès : `types.json:colon` porte déjà un canal `peur` qui capterait la cause synthétisée de ce banc et ferait monter une seconde peur parasite. `opacite` du mur posée à la main — la valeur réelle (1.0) bloquerait totalement et l'occlusion ne serait jamais observable en dégradé. |
| `banc_grief.json` | Le seuil de rupture est lu PAR COLON. La vitesse de sortie est une propriété SÉPARÉE de `vitesse` : l'état de départ écrase `vitesse` à zéro, un colon censé partir en serait cloué au sol. |
| `banc_croyance.json` | Deux cadences par colon (revenir regarder, revenir toucher) : `croyance.gd` n'a AUCUNE notion de temps propre, appelée à chaque image elle rendrait tout le monde dogmatique en une seconde. Ce qui sépare le dogmatique des autres est UN NOMBRE, jamais un état posé. |
| `banc_memoire_navigation.json` | Durée du jour à ZÉRO : point légitime et documenté d'`horloge.gd` (le temps du monde est arrêté). L'erreur a deux causes — mémoire faible et obscurité — et le banc existe pour les séparer : une heure qui dérive ferait varier la luminosité sous chaque mesure. |
| `banc_oubli_consolidation.json` | L'oubli exponentiel n'est PAS un mécanisme : le câblage réécrit chaque tick un taux valant `valeur/(S × charge)`, ce qui transforme la soustraction fixe du cœur en décroissance exponentielle. |
| `banc_ecosysteme_terrain.json` | Catalogue de seuils LOCAL, seuils lus PAR CASE. Le rayon d'échantillonnage de densité est FIXE et jamais la portée courante : mesurer la densité dans le rayon qu'on calcule serait une boucle. Les proies de renfort ont des énergies ÉTAGÉES — à énergies égales elles mourraient toutes au même instant et la population s'effondrerait d'un coup au lieu de se réguler. |
| `banc_parasites_reproduction.json` | Deux espèces, un seul code, zéro branche : ce qui les sépare tient à DEUX ABSENCES de propriété, jamais à un test de type. Capacité de charge par RATIO côté parasite et par plafond de voisinage côté hôte — un gate sur un nombre absolu ne freine rien et fait croître les deux populations sans borne. |
| `banc_predation.json` | Profils de saillance INVERSÉS par rapport à l'intuition (la proie plus saillante que le prédateur) : un profil ne peut pas servir les deux sens, et c'est la déformation PAR PERCEVANT qui fait lire le même monde différemment aux deux espèces. Le plafond de population est un plafond d'OBSERVABILITÉ, pas une capacité de charge. |
| `banc_temps_anticipation.json` | Le compteur de cycles vécus est une propriété PLATE. Deux outils ÉCARTÉS, à ne pas reproposer : `epigenetique.gd` (un appel par cycle est un intervalle énorme, la marque serait effacée entre deux poses) et `stade.gd` (il interdit tout retour en arrière, or une saison est CYCLIQUE — ce n'est pas un outil à adapter, c'est un non-outil). |
| `banc_temps_vieillissement.json` | Trois unités de temps qui ne se convertissent jamais l'une dans l'autre : l'horloge d'âge, l'unité de l'accumulateur (des jours, pour que le 730 du catalogue partagé se lise), et les secondes brutes. Catalogue de seuils LOCAL pour le pic de force : `age` est portée par tout vivant du dépôt, une entrée partagée attraperait les autres bancs. Catalogue de reproduction LOCAL aussi — la calibration partagée demanderait presque une minute avant la première naissance, et la baisser la baisserait pour l'autre banc qui la lit. |
| `banc_temps_saisons.json` | Deux émetteurs de flux séparés plutôt qu'un seul aux taux additionnés : c'est ce qui garde les deux échelles de temps lisibles. Trois miroirs numériques par plante, tous présents dès la construction — une propriété absente ferait ÉCHOUER sa condition, jamais réussir. Catalogue de seuils LOCAL pour les deux cadences : les états qu'il pose sont portés par une entité calendrier, une entrée partagée n'aurait visé personne d'autre. Le patron d'incendie référence `defaut`, entrée PARTAGÉE, dont la portée de travail de 25.0 décide seule qui peut éteindre quoi — le gardien ne sauve que le rayonnage qu'il touche. |
| `banc_marche_competence.json` | Le plancher de compétence est une donnée PAR COLON, jamais une constante : écrit comme constante, il s'appliquerait aussi au novice et « la forge n'est pas plus attractive pour lui » serait faux, tous tests verts. Les plafonds portent DEUX FOIS (gate de pose et clamp à la lecture) — sans le gate, l'observabilité disparaît. |
| `banc_infrastructure.json` | Catalogue de seuils LOCAL pour le surpeuplement ; l'usure de route et le comptage passent en revanche par les catalogues PARTAGÉS, non évitable (contrainte du linter). Le plafond du grenier est un REFUS, jamais un écrêtage : écrêter ferait disparaître en silence ce qu'un colon a porté à travers la carte. |
| `banc_economie.json` | La référence de transformation N'EST PAS nommée `transformation` : le linter vérifie tout champ portant exactement ce nom contre le catalogue partagé, une référence locale y rougirait. Deux ressources lointaines distinctes (un gisement au-dessus du seuil, une miette en dessous) — sous un seuil ABSOLU, une seule ne peut pas être à la fois retirée et récupérable. |
| `banc_affordances_travail.json` | La masse n'est PAS conservée, et c'est le sujet : les trois issues ne somment pas à 1.0, rater DÉTRUIT de la matière. L'invariant vérifié est `monde + perdu == référence`. Deux nombres corrigés APRÈS lancement, dont une sortie déclarée qui n'était jamais atteignable — morte en donnée sans qu'aucun test ne rougisse. |
| `banc_affordances_portage.json` | La référence de chantier se nomme `chantier_ref` et non `transformation`, même raison de linter que ci-dessus, recopiée en code sous la clé attendue à la fabrication. La grandeur d'aide est portée aussi bien par un objet que par un colon : le gate somme sans jamais demander si un contributeur est vivant. |
| `banc_affordances_choix.json` | Catalogue d'engagement LOCAL : le poids du catalogue partagé, calibré pour un autre banc, rendrait l'engagement indélogeable et l'urgence inobservable. |
| `banc_affordances_connaissance.json` | La probabilité de l'audit est devenue une CADENCE : aucun RNG n'existe dans le dépôt et `croyance.gd` n'a aucune notion de temps propre. Le contenu d'un livre est une copie profonde de croyances, jamais du texte. |
| `banc_social_information.json` | Le sens du lien de crédibilité est « à quel point JE TE crois » (receveur → émetteur) : l'inverse ferait dépendre ma confiance de ce que l'autre ressent pour moi. Une seule portée de vue est longue, et c'est structurel : sans ça les receveurs formeraient la croyance par observation directe et il n'y aurait plus rien à propager. |
| `banc_social_rupture.json` | Un SECOND palier sur le même grief ouvre une QUATRIÈME sortie : `bifurcation.gd` ne connaît ni seuil ni palier, « la trahison demande plus de grief que la révolte » ne peut s'écrire QUE comme un ensemble de sorties qui grandit. La bifurcation est donc rejouée quand cet ensemble change, jamais à chaque tick. |
| `banc_social_foule.json` | Trois canaux de charge exigent TROIS FAMILLES D'OBJETS DISJOINTES : `charge.gd` applique la même liste de causes à TOUS les canaux d'une chose, et aucune portée ne les sépare. Voir aussi le second résultat négatif : `charge.gd` et `seuil_etat.gd` ne se branchent pas directement. |
| `banc_social_paire.json` | Catalogue de marques DÉRIVÉ d'une seule entrée partagée et étendu par paire : une grandeur par paire exige un nom COMPOSÉ, `marques_epigenetiques` étant un Dictionary plat. Le plafond de confiance est PAR COLON — c'est lui, et lui seul, qui empêche un colon de franchir le second palier. |

Note d'état — `depense.gd` n'a volontairement AUCUNE ligne dans ce tableau :
il ne lit aucun `data/*.json` lui-même, ses canaux
(`proprietes.reserves.<nom>`) sont posés sur l'objet par l'appelant, depuis
`types.json` ou depuis un fichier de banc.

---

## 5. Outils de test (pas des couches du moteur)

- **`scripts/lanceur.gd`** — découvre automatiquement tout `scripts/test_*.gd`
  (aucune liste en dur), lance chacun en sous-processus (`OS.create_process`
  sur `cmd.exe`, sortie redirigée vers un fichier temporaire hors dépôt) et
  juge trois états : **VERT** (exit 0 ET sortie contenant `OK:`, ou exit
  différent de 0 pour un test marqué `# LANCEUR: echec-attendu`, voir
  `test_pv0b.gd`), **ROUGE** (le sous-processus s'est terminé, verdict
  ci-dessus faux), **DEPASSE** (le sous-processus n'a pas rendu la main
  avant 30s — `taskkill /F /T /PID` force alors l'arrêt de tout l'arbre de
  processus). État DEPASSE et mécanisme de sous-processus ajoutés après
  constat empirique : `OS.execute` bloquant (ancienne forme) n'a pas de
  délai, et un `assert()` natif de GDScript qui échoue en
  `--headless --script` ne rend jamais la main — un seul cas aurait gelé
  le lanceur entier. `OS.execute_with_pipe` essayé puis abandonné :
  `is_process_running` ne détecte jamais la fin du sous-processus avec
  cette API sur cette plateforme (vérifié empiriquement).
  Commande exacte : voir `CLAUDE.md`, « Travailler sur le projet ». Pas
  testé par un test dédié — son contrat (juger échec-attendu) est exercé
  par `test_pv0b.gd` à chaque exécution du lanceur lui-même.
- **`scripts/verif.gd`** — classe d'assertions partagée (`v(condition, message)`,
  `echecs()`), via `push_error` — jamais bloquant, contrairement à
  `assert()` natif de GDScript. Utilisée désormais par TOUS les
  `test_*.gd` (`assert()` natif abandonné partout, chantier « réparer les
  tests » — un `assert()` qui échoue peut faire pendre le processus,
  incompatible avec le lanceur). Nommée hors motif `test_*` exprès pour ne
  pas être ramassée. Pas de test dédié — exercée indirectement par tous
  les tests qui l'utilisent.
- **`scripts/boucle.gd`** — brique de boucle pour les tests DYNAMIQUES
  (multi-ticks) : `tracer(colon, ticks, geste)` appelle `ticks` fois un
  Callable `geste` DÉJÀ LIÉ par l'appelant à `agir_et_deplacer` d'un banc
  (`banc_p1.gd:agir_et_deplacer` / `banc_feu.gd:agir_et_deplacer`) — LE
  GESTE COMPLET décision→mouvement de ce banc (`decider_et_memoriser` +
  branche fuite/non-fuite + déplacement), le même que `_faire_agir_colon`
  appelle en jeu réel. `tracer()` mute `colon` en place et rend l'Array
  des décisions, une par tick. **Dette FERMÉE** (ancienne 3e copie de
  l'agencement décision→mouvement, dupliqué tel quel dans
  `banc_p1.gd:_faire_agir_colon` et `banc_feu.gd:_faire_agir_colon`) :
  `tracer()` ne connaît plus ni la branche fuite, ni `Ciblage.viser`, ni
  `bouger_vers`/`bouger_selon` — cet agencement vit désormais UNE SEULE
  FOIS par banc, dans sa fonction `agir_et_deplacer`, que `tracer()` et le
  Node du banc appellent tous deux. Nommé hors motif `test_*.gd` exprès
  (comme `verif.gd`) pour ne pas être ramassé par `lanceur.gd`. Testé
  indirectement par `test_banc_p1.gd`/`test_banc_feu.gd`, seuls appelants.
- **`scripts/test_docs.gd`** — audite l'alignement documents/code : extrait
  par RegEx toute adresse `fichier:fonction` citée dans les documents
  PERMANENTS (liste et raison : en-tête du fichier), et vérifie que la
  fonction existe
  réellement dans le fichier cité. Vérifie aussi chaque renvoi de section
  (`§N`, `§Nter`, ``banc_champ``...) cité dans ces documents : seul
  `CARTE.md` numérote ses sections (`## <id>. Titre`), tout `§<id>` cité,
  où que ce soit dans les trois documents, doit donc désigner une section
  réellement présente dans `CARTE.md`. Ne répare rien, signale seulement.
  C'est un test comme un autre pour `lanceur.gd` (motif `test_*.gd`), pas
  un outil à part.
- **`scripts/repetitions.gd`** — sonde OPT-IN, hors simulation. API :
  `repetitions.gd:tour`, `repetitions.gd:noter`, `repetitions.gd:rapport`,
  `repetitions.gd:resume`. Verdicts : REFAIT, INSTABLE. Aucune mesure de
  temps ; ce rôle revient au profileur. Mode d'emploi : en-tête du fichier.

Ce que chaque test verrouille. **HD** = porte un cas HORS DOMAINE (un cas
inventé, sans rapport avec le feu ni le colon, qui traverse le même code sans
une ligne ajoutée) — c'est la preuve de généricité du mécanisme, la seule
chose de ce tableau qui ne se lise pas dans le test lui-même. **CR** = chemin
réel, catalogues relus sur le disque plutôt qu'une fixture locale. Le détail
des cas vit dans le test ; il n'est pas paraphrasé ici.

Liste exhaustive : tout `scripts/test_*.gd` du dépôt y figure.

| Test | Verrouille | |
|---|---|---|
| `test_repetitions.gd` | Les deux verdicts ne se confondent jamais ; le tour cloisonne ; Vector3 et Dictionary comparables ; rapport resumable en JSON. | HD |
| `test_objet.gd` | Fabrication résout les propriétés, composition de paquets `herite` à plat, `duplicate(true)` ne contamine jamais la table partagée. | |
| `test_densite_effective.gd` | Densité effective par moyenne pondérée des volumes, conversion d'unité comprise ; échec FORT (aucun objet produit) sur matériau absent ou volume nul. | HD |
| `test_perception.gd` | Une géométrie par canal, pas de doublon multi-canal, auto-exclusion du percevant, gardes structurelles ; filtres d'occlusion et de vent. | HD |
| `test_occlusion.gd` | Géométrie d'occlusion : cumul MULTIPLICATIF de plusieurs obstacles, rien hors du segment ni hors largeur latérale. | HD |
| `test_champ_occulte.gd` | Champ atténué par distance ET obstacles : un obstacle RÉDUIT sans jamais couper — une ombre, pas une frontière. | HD |
| `test_banc_ombre_pluvio.gd` | Câblage : normalisation du relief bornée, cône d'ombre gradué, une case ne s'occulte jamais elle-même. | CR |
| `test_vent.gd` | Trois couches additives indépendamment désactivables ; perpendiculaire au vent toujours exactement `1.0` ; vent nul toujours neutre. | HD, CR |
| `test_banc_vent.gd` | Câblage : l'ensemble des sources captées PIVOTE au fil du temps, sans supposer le sens de rotation. | CR |
| `test_temperature.gd` | Loi de Newton (vite d'abord puis lentement, par la formule), superposition additive des sources, inertie par chaleur spécifique, dilatation. | HD, CR |
| `test_banc_temperature.gd` | Câblage : diagonale clavier NORMALISÉE, source mobile fonction pure du temps. | CR |
| `test_attaches.gd` | Menace par PROPRIÉTÉS reliées entre deux choses ; l'attache intacte reste saillante (familiarité), jamais absente. | HD |
| `test_proximite.gd` | Saillance intrinsèque par référence de catalogue ; hors portée ou sans profil, jamais saillante. | HD |
| `test_banc_deformation.gd` | Deux colons identiques à la naissance divergent par la seule exposition, via une perception RÉELLE. | CR |
| `test_attaches_deformation.gd` | La déformation module aussi la saillance d'ATTACHE, la cible étant directement la propriété défendue (une attache n'a pas d'identité de chose). | CR |
| `test_proximite_deformation.gd` | La déformation module la saillance : formule exacte, colon sans déformation inchangé. | CR |
| `test_antiempilement.gd` | Pondération par avancement du chantier ; `travail_initial` absent ou nul retombe au neutre, jamais une division par zéro. | HD |
| `test_jugement.gd` | Pression nulle ne produit RIEN (jamais une entrée à zéro) ; CAS DU COUPLE : un gain sans plafond alarme au lieu de rendre une saillance non bornée. | HD |
| `test_jugement_deformation.gd` | Le biais s'applique à la pression DÉJÀ SOMMÉE, jamais à chaque saillance avant sommation. | CR |
| `test_dominance.gd` | Écrase par le seul NOMBRE, jamais par le domaine d'origine d'une saillance. | HD |
| `test_agir.gd` | Inertie ; `etat_courant` n'invente jamais de position ; ENGAGEMENT (bonus additif, réinjection d'une cible gelée, arrachement par saillance non empêché). | |
| `test_agir_proximite.gd` | Résolution par PROPRIÉTÉ et non par type ; chose sans propriété actionnable = action vide légitime ; poids opposés → verbes différents. | HD |
| `test_ciblage.gd` | Dispatch PAR VERBE ; verbe orienté jugée sans propriété jugée connue rend `null` plutôt que de deviner. | HD |
| `test_fuite.gd` | Deux répulsions se composent vectoriellement ; annulation exacte → `Vector3.ZERO`, jamais un vecteur au hasard. | HD |
| `test_propagation.gd` | Propagation par propriété-menace ; `delai_propagation` absent alarme au lieu d'un allumage instantané ; les trois gates (intensité, émission, point d'ignition) coexistent. | HD |
| `test_fin_chantier.gd` | Le chantier posé par `propagation.gd` passe par le MÊME geste partagé que le banc — verrou du bug d'aliasing qui venait de deux copies du même geste. | |
| `test_propagation_chantier.gd` | L'allumage pose le chantier depuis le patron et remet l'exposition à zéro. | |
| `test_extinction.gd` | Chantier générique mangé par des agents à portée ; `a_zero` applique retirer/poser ou produit un objet neuf. | HD |
| `test_produit.gd` | Masse dérivée du rendement, jamais posée à la main ; rendement nul ne produit rien SANS alarme ; config incomplète alarme. | HD |
| `test_depense.gd` | Réserves indépendantes sur un même objet ; chaque seuil en escalier s'applique UNE seule fois ; référence de seuils absente alarme. | HD |
| `test_charge.gd` | Seuil RÉVERSIBLE : pose en montant, retire en descendant ; plancher à zéro ; hors portée ne contribue pas. | HD |
| `test_bifurcation.gd` | Le produit le plus haut gagne ; rien ne bifurque par défaut (seuil strictement positif) ; égalité stricte alarme sans trancher. | HD |
| `test_flux.gd` | Transfert au taux de la source ; un taux NÉGATIF vide la réserve par le même code — ce n'est pas « le gain ». | HD |
| `test_comptage.gd` | Les quatre modes rendent le compte exact ; règle absente alarme et rend `0` ; entité malformée ignorée sans planter. | HD |
| `test_somme.gd` | Somme exacte en lecture plate et profonde ; grandeur absente contribue `0.0` sans alarme ; valeur non numérique alarme sans arrêter la somme ; ne mute jamais. | HD |
| `test_banc_comptage.gd` | Câblage : deux RNG seedés identiquement produisent la même séquence ; la moyenne glissante est une composition du BANC, jamais du mécanisme. | CR |
| `test_banc_convergence_attache.gd` | Câblage : cristallisation échelonnée par seuil individuel sous exposition identique ; le comptage réel suit. | CR |
| `test_banc_contagion.gd` | Câblage : un colon ne se compte jamais lui-même ; la réversibilité de la charge retire la propriété posée. | CR |
| `test_banc_vecu_inter_colon.gd` | Câblage : cristallisation mutuelle, puis absorption d'un tiers SANS perte de son identité d'origine. | CR |
| `test_banc_genetique.gd` | Câblage : formule d'expression exacte, allèles neutres laissant EXACTEMENT le défaut du type, ordre d'arrivée et d'épuisement strict. | CR |
| `test_lien_personnel.gd` | `poser` accumule sans remplacer ; sous le plancher l'entrée est RETIRÉE ; alarme sur catalogue sans `defaut`. | HD |
| `test_lien_personnel_saillance.gd` | Rend saillant ce qui S'APPROCHE de la chose aimée, jamais la chose aimée elle-même ; chose liée détruite ignorée sans crash. | HD |
| `test_lien_personnel_attraction.gd` | Génère un candidat de saillance à distance AU COLON, même hors de toute perception ; jamais d'entrée à saillance nulle. | HD, CR |
| `test_lien_personnel_croissance.gd` | Pose un montant FIXE par événement, jamais mis à l'échelle du delta — le cas qui aurait attrapé le bug de cadence. | HD |
| `test_deformation.gd` | Deux registres à taux différents ; source non déclarée alarme et n'écrit rien ; résumabilité JSON stricte. | HD |
| `test_attache_par_trait.gd` | Seuil COMPOSITE (nombre ET force) ; idempotent ; surcharge par colon, partielle ou totale. | HD, CR |
| `test_usure_attache.gd` | Usure passive vs contradiction (jamais additionnées) ; le gel par renouvellement prime ; le plancher n'est jamais franchi et l'entrée jamais retirée. | HD |
| `test_expression.gd` | Les quatre modes d'expression ; composition ADDITIVE des trois couches ; mode non reconnu alarme et contribue `0.0`. | HD |
| `test_epigenetique.gd` | `poser` accumule au montant du catalogue ; décroissance par soustraction FIXE ; retrait sous plancher. | HD |
| `test_senescence.gd` | L'âge avance au facteur d'échelle reçu ; l'horloge du monde écrit ses deux clés ou aucune, et l'âge avance même horloge cassée. | HD |
| `test_stade.gd` | Le stade NE RECULE JAMAIS, garanti par comparaison d'INDEX et non par une hypothèse sur le sens de l'âge. | HD |
| `test_accouplement.gd` | Accumulation IRRÉVERSIBLE jusqu'au seuil ; `gestation` posée avec copie PROFONDE des gènes du partenaire, et sur les seuls porteurs déclarés — quel que soit lequel des deux est l'entité avancée. | HD |
| `test_gestation.gd` | Compteur initialisé puis accumulé ; flag posé exactement au seuil ; idempotent ensuite. | HD |
| `test_heredite.gd` | Un allèle de chaque parent en sexuée, copie en asexuée, réarrangement en parthénogenèse ; mutation rejouée au même seed. | HD |
| `test_banc_reproduction.gd` | Câblage : cycle complet, un SEUL des deux parents gestate (la donnée l'exclut, pas un appel sélectif), allèles de l'enfant rejoués au même seed, et aucune gestation ne revient après la naissance. | CR |
| `test_horloge.gd` | Heure et saison à toute longueur de jour ; la formule des deux bancs est RECOPIÉE dans le test comme contre-épreuve, jamais appelée sur eux. | HD |
| `test_memoire_spatiale.gd` | La position est RÉÉCRITE à chaque observation, la force ACCUMULE ; erreur DÉTERMINISTE (même appel, même résultat sur cent essais). | HD |
| `test_banc_memoire_navigation.gd` | Câblage : le colon marche vers le SOUVENIR, pas vers la position réelle ; souvenir perdu → il s'arrête au lieu de foncer sur l'origine. | CR |
| `test_croyance.gd` | Les couches décident sur une COPIE ; la certitude est ÉCRASÉE par correction, jamais incrémentée — le dogme ne naît que de l'accumulation d'observations. | HD |
| `test_banc_croyance.gd` | Câblage : un colon agit sur une information fausse sans aucune branche spéciale ; deux refus distincts (crédibilité trop basse / dogme). | CR |
| `test_champ.gd` | Déplacement inversement proportionnel à la MASSE, force proportionnelle à la QUANTITÉ DE MATIÈRE : deux rôles distincts, jamais confondus. | HD |
| `test_quantite_matiere.gd` | SOMME pondérée par volume (extensive), jamais une moyenne ; matériau absent alarme sans bloquer les autres éléments. | HD |
| `test_velocite.gd` | Dérivation PASSIVE : deux mutations de position dans le même tick donnent une vélocité NETTE ; delta nul ne rend jamais l'infini. | HD |
| `test_combustible.gd` | Capacité immuable vs réserve qui décroît sur le même canal ; capacité nulle ne divise jamais par zéro. | HD |
| `test_consommer.gd` | Transfert DESTRUCTIF conservatif : le receveur est crédité de ce qui a été RÉELLEMENT retiré, jamais de ce qui était demandé. | HD |
| `test_reaction.gd` | Détection de paires réactives, chaînage sur DEUX TICS distincts (jamais dans le même appel), trois régimes de profondeur maximale. | HD |
| `test_ecoulement.gd` | L'eau ne remonte JAMAIS ; conservation de la somme sur plusieurs cases et ticks. | HD |
| `test_sandpile.gd` | UN grain entier par paire déclenchante, JAMAIS en sens inverse ; écart strict > seuil requis ; source à réserve fractionnaire ne transfère rien ; somme totale conservée ; rayon négatif rend `[]` sans alarme. Domaine inventé (`unites_deplacables`/`attirance_site`) — verrouille le mécanisme, jamais le sable. Framework orion, ABSENT de la copie locale. | HD |
| `test_monde_subdivision.gd` | Subdivision adaptative de `monde.gd` : SPLIT au-delà de `SEUIL_SPLIT`, récursif jusqu'à `PROFONDEUR_MAX`, MERGE sous `SEUIL_MERGE`, hystérésis contre l'oscillation, frontière stricte entre octants, migration intra- et inter-globale dans le même `deplacer`, résultat de `choses_dans_rayon` identique à l'exhaustif. Écart local (voir en-tête `monde.gd`). | HD |
| `test_etat_effectif.gd` | ÉCRASER gagne sur MODULER ; plusieurs modulateurs se composent multiplicativement ; conflit d'écraseurs tranché par ordre alphabétique déterministe. | HD, CR |
| `test_etat_duree.gd` | Intensité décroissante ; REMISE à `1.0` (jamais un cumul) ; les deux gestes ont des IDENTITÉS différentes à intensité nulle (la base / `1.0`). | HD, CR |
| `test_seuil_etat.gd` | UNE ENTRÉE, UN SEUL ÉTAT ; mémoire PAR ENTRÉE (deux entrées visant le même nom ne se marchent pas dessus) ; sans seuil résoluble, jamais de bascule. | HD, CR |
| `test_soudure.gd` | Masse du composite = somme exacte des deux ; même id refusé sans rien muter. | HD |
| `test_frappe.gd` | Score composite, hors portée jamais candidat, égalité stricte alarme sans trancher ; dégât ponctuel borné à zéro. | HD |
| `test_lumiere.gd` | Intensité ADDITIVE bornée, couleur en MOYENNE PONDÉRÉE (jamais additive) ; nuit sans source reste bleue plutôt qu'indéfinie. | HD, CR |
| `test_emergences.gd` | Émergences à la fabrication : ET logique réel, deux émergences indépendantes coexistent, une propriété absente fait échouer sa condition (jamais un défaut permissif). | HD |
| `test_conditions.gd` | ET logique, réversibilité, DEUX PASSES : une entrée vraie gagne toujours sur une entrée fausse, quel que soit l'ordre. | HD |
| `test_portee.gd` | Frontière INCLUSE (`<=`), portée négative toujours hors portée, symétrie des deux positions. | HD |
| `test_couplage.gd` | Pose/garde/satisfait/arrache ; jetons de contexte substitués ; sens de satisfaction inversable. | HD |
| `test_monde.gd` | Une chose déplacée après son ajout est retrouvée à sa position VIVANTE — plus de copie figée. | |
| `test_banc_p1.gd` | Câblage principal : décision, mémorisation d'`action_en_cours` sur deux ticks, occupation, engagement qui ferme l'oscillation sur un chantier lent. | CR |
| `test_banc_animal.gd` | Câblage : hystérésis dans les deux sens, engagement jusqu'à satisfaction, générique à N réserves. | CR |
| `test_banc_feu.gd` | Câblage à CINQ étapes (premier `decider()` réel incluant le jugement) : deux colons basculent à des nombres de feux différents. | HD, CR |
| `test_banc_charge.gd` | Câblage : deux colons au seuil différent basculent à des expositions différentes ; sans cause, la charge redescend et retire l'état. | HD, CR |
| `test_banc_commun.gd` | Les dix outils partagés, isolément ; et le verrou négatif sur l'instanciation de `Monde` hors déclaration de champ. | HD |
| `test_registre_banc_commun.gd` | Chaque `static func` publique de `banc_commun.gd` a sa ligne de registre, et réciproquement — empêche le registre de dériver du code. | |
| `test_banc_lien_personnel.gd` | Câblage : le lien se forme sur la DÉCISION résolue, les trois pompiers cristallisent à leur rythme propre. | CR |
| `test_banc_controle.gd` | Câblage : un ordre posé sur une entité non contrôlable ne produit JAMAIS de mouvement — la garde est à la LECTURE, jamais à l'écriture. | CR |
| `test_banc_champ.gd` | Câblage : loin le pas volontaire l'emporte, près le champ domine — sans aucune branche « si dominé ». | CR |
| `test_banc_etat_effectif.gd` | Câblage : deux états dont un écraseur rendent la MÊME valeur que l'écraseur seul. | CR |
| `test_banc_inflammabilite.gd` | Câblage : deux raisons de blocage distinctes (sous le seuil / état qui écrase) ; le label dit la vérité une fois l'objet en feu. | CR |
| `test_banc_etat_duree.gd` | Câblage : barre et valeur effective bougent ENSEMBLE à mi-durée ; l'état expire et disparaît de l'affichage. | CR |
| `test_banc_combustible.gd` | Câblage : ordre d'extinction des sept objets, conséquence pure de la capacité et du coût effectif — jamais écrit à la main. | CR |
| `test_banc_emission.gd` | Câblage : seule la cible à la fois assez proche ET assez inflammable s'enflamme, sur 100 s simulées. | CR |
| `test_banc_point_ignition.gd` | Câblage : la cible froide n'accumule JAMAIS d'exposition, même inflammabilité et exposition identiques. | CR |
| `test_banc_transformation_produit.gd` | Câblage : chaîne bois → charbon → cendre, masses exactes aux rendements. | CR |
| `test_banc_humidite.gd` | Câblage : séchage STRICTEMENT progressif après coupure ; à absorption égale, le plus poreux monte plus vite. | HD, CR |
| `test_banc_changement_etat.gd` | Câblage : le fer traverse réellement chaud → liquide → gaz, puis resolidifie ; fluidité nulle tant qu'il n'est pas liquide. | CR |
| `test_banc_soudure.gd` | Câblage : deux fers froids ne soudent jamais ; chauffés ils fusionnent, masse combinée exacte, le bois jamais. | CR |
| `test_banc_dilatation.gd` | Câblage : volumes en miroir (l'un grossit, l'autre rétrécit), masse inchangée, densité exactement `masse/volume`. | CR |
| `test_banc_pourriture.gd` | Câblage : les trois phases jusqu'à la transformation ; un objet sauvé avant terme voit sa réserve FIGÉE. | HD, CR |
| `test_banc_corrosion.gd` | Câblage : le fer se transforme, cuivre/bronze/argent restent COSMÉTIQUES sur la même fenêtre. | HD, CR |
| `test_banc_porosite.gd` | Câblage : à porosité ÉGALE les deux objets évoluent identiquement tick par tick — preuve que seule la porosité explique tout écart mesuré ensuite. | HD, CR |
| `test_banc_permeabilite.gd` | Câblage : montée identique sous exposition, séchage divergent après coupure ; le plancher garantit qu'aucun objet ne reste mouillé à vie. | HD, CR |
| `test_banc_solubilite.gd` | Câblage : vitesse de dissolution proportionnelle à la solubilité ; solubilité nulle ne dissout JAMAIS. | HD, CR |
| `test_banc_conduction.gd` | Câblage : blocage NET à un isolant ; un objet mouillé accumule exactement dix fois plus vite qu'un sec. | CR |
| `test_banc_foudre.gd` | Câblage : la hauteur seule ne bat jamais un conducteur ; un objet détruit n'est plus jamais candidat. | CR |
| `test_banc_fracture.gd` | Câblage : la fragilité tranche entre éclats et déformation ; le fer fracture sans jamais se transformer. | CR |
| `test_banc_fracture_sonore.gd` | Câblage : sans source rien ne casse ; le verre casse strictement avant le fer. | CR |
| `test_banc_chaleur_emise.gd` | Câblage : à distance égale, le voisin du foyer le plus émissif se réchauffe strictement plus ; l'extinction supprime la source au tick suivant. | CR |
| `test_banc_lumiere.gd` | Câblage : cycle jour/nuit exact aux points nommés, recouvrement de deux sources strictement entre les deux couleurs. | CR |
| `test_banc_reflectivite.gd` | Câblage : l'argent réfléchit plus et chauffe moins que le bois à éclairement identique ; la patine réduit strictement la réflectivité. | CR |
| `test_banc_photodegradation.gd` | Câblage : `cout_base` effectif exactement `biodegradabilite × facteur × lumière` ; deux objets épargnés pour DEUX raisons différentes. | HD, CR |
| `test_banc_son.gd` | Câblage : deux filtres INDÉPENDANTS (seuil d'intensité, plage de fréquence) ; l'ultrason n'est entendu que par qui a la plage. | CR |
| `test_banc_resonance.gd` | Câblage : le son total perçu est STRICTEMENT plus fort avec les objets résonnants ; à distances égales, la résonance seule ordonne. | HD, CR |
| `test_banc_occlusion.gd` | Câblage : un mur réel (5 % d'absorption) suffit à faire passer sous le seuil ; le témoin sans mur n'est jamais affecté. | CR |
| `test_banc_absorption_sonore.gd` | Câblage : réduction exacte par matériau ; DEUX murs empilés cumulent MULTIPLICATIVEMENT. | CR |
| `test_banc_friction.gd` | Câblage : ordre de glisse pierre < fer < bois, conservé mouillé ; friction `1.0` ne bouge jamais. | CR |
| `test_banc_restitution.gd` | Câblage : restitution `0.0` ne rebondit JAMAIS, `1.0` rebondit indéfiniment à la même hauteur. | CR |
| `test_banc_rigidite.gd` | Câblage : la flèche maximale ne redescend JAMAIS, la fracture reste posée après retrait de la charge. | CR |
| `test_banc_elasticite.gd` | Câblage : `elasticite` isolée comme seule variable (rigidité égale) pour lever l'ambiguïté du ratio réel. | CR |
| `test_banc_coupe.gd` | Câblage : l'outil s'émousse d'autant plus que la cible est dure ; un outil émoussé ne coupe plus par la seule arithmétique. | CR |
| `test_banc_usinabilite.gd` | Câblage : ordre de fabrication bois < fer < pierre ; inactif, rien ne bouge jamais. | CR |
| `test_banc_traction.gd` | Câblage : sans force rien ne rompt ; un objet rompu tombe réellement, sans jamais rebondir. | CR |
| `test_banc_velocite.gd` | Câblage : vélocité exactement nulle pour un repère jamais touché ; le golem accélère en s'approchant de l'aimant. | CR |
| `test_banc_acide.gd` | Câblage : sans source rien ne corrode ; ordre fer < pierre < bois. | CR |
| `test_banc_toxicite.gd` | Câblage : rapport des charges = rapport des toxicités ; près d'un objet non toxique, jamais d'empoisonnement. | CR |
| `test_banc_mana_conduction.gd` | Câblage : seuil de mana DISTINCT du seuil électrique, vérifié par une conductivité intermédiaire qui conduit l'un et pas l'autre. | CR |
| `test_banc_choc_magique.gd` | Câblage : chaque caster ne frappe que sa propre cible ; ordre verre < bois < fer. | CR |
| `test_banc_reactivite.gd` | Câblage : l'acide se vide proportionnellement aux cibles ACTIVES ; sans cible reconnue il est immédiatement épuisé. | HD, CR |
| `test_banc_radiation.gd` | Câblage : le mur bloque une seule cible sans jamais affecter les deux autres ; sensibilité nulle ne charge jamais. | CR |
| `test_banc_manger.gd` | Câblage : la perte de contenu égale EXACTEMENT le gain d'énergie ; un objet pourri n'est jamais mangé. | CR |
| `test_banc_magie_perception.gd` | Câblage : un seuil strictement positif ne capte jamais une source sans force d'émission ; un mur opaque bloque totalement. | CR |
| `test_banc_produit_nucleaire.gd` | Câblage : nausée réversible, syndrome permanent, mort qui FIGE le colon ; un mur bloque simultanément deux cibles alignées. | CR |
| `test_banc_sorts.gd` | Câblage : mana insuffisant n'agit ni ne ponctionne ; l'affinité multiplie exactement le dégât ; explosion à portée et RIEN au-delà. | HD, CR |
| `test_banc_activation_neutronique.gd` | Câblage : un objet exposé devient source SECONDAIRE et irradie même source primaire absente ; l'état reste après épuisement. | CR |
| `test_banc_emergences.gd` | Câblage : ET logique réel (un seul critère rempli ne donne rien) ; le diagnostic par condition reste cohérent avec le verdict posé. | HD, CR |
| `test_banc_chaine_reactions.gd` | Câblage : cascade en deux étages sur deux ticks distincts ; les catalyseurs ne sont JAMAIS transformés. | CR |
| `test_banc_maladie.gd` | Câblage : un porteur encore en incubation contamine déjà ; un mort cesse d'être contagieux. | CR |
| `test_banc_ecoulement.gd` | Câblage : altitude décroissante, terre absorbe plus vite que roche, diagnostic égal au décrément réel. | CR |
| `test_banc_succession.gd` | Câblage : traversée des stades dans l'ordre sans saut ; le feu rejoue la succession entière ; la colonne stérile ne bouge jamais. | CR |
| `test_banc_cratere.gd` | Câblage : l'altitude de base n'est JAMAIS écrasée ; une case effacée est recreusable (seuils vidés). | CR |
| `test_banc_simulation_acceleree.gd` | Câblage : le MÊME âge atteint par N petits pas et par un pas géant donne deux ÉTATS D'EAU différents — la raison d'être du banc. | CR |
| `test_banc_fertilite.gd` | Câblage : transfert cadavre → sol conservé au flottant près ; la jachère remonte exactement du coût négatif. | CR |
| `test_banc_erosion.gd` | Câblage : conservation du sol sur 40 pas ; le sol ne part JAMAIS vers un voisin qui n'est pas sous le vent. | CR |
| `test_banc_croissance.gd` | Câblage : lumière ET eau font pousser, l'un sans l'autre stagne ; la maturité ne dépasse jamais son plafond. | HD, CR |
| `test_banc_biomes.gd` | Câblage : réversibilité réelle (forêt → toundra → forêt à l'identique) ; deux applications du même climat donnent le même état. | CR |
| `test_banc_fatigue_circadien.gd` | Câblage : la zone circadienne enjambe minuit sans que la seconde entrée efface la première ; deux veilleurs n'accumulent jamais l'un pour l'autre. | CR |
| `test_banc_faim_thermo.gd` | Câblage : effort, froid et chaud se SOMMENT exactement dans un seul `surcout_action` ; les quatre états se posent et se retirent au seuil. | HD, CR |
| `test_banc_hygiene_apparence.gd` | Câblage : franchissement STRICT vérifié aux deux bornes ; un mur bloque l'apparence et jamais l'odeur. | CR |
| `test_banc_nutrition.gd` | Câblage : chaque repas ne remplit QUE sa réserve ; une somme exactement égale au seuil ne synthétise aucune cause. | CR |
| `test_banc_elimination_salete.gd` | Câblage : un colon mort n'élimine plus ; un colon guéri qui repasse dans un tas retombe malade. | CR |
| `test_banc_graisse_accoutumance.gd` | Câblage : `energie + graisse` invariante quand la demande dépasse la graisse — contre-épreuve de la correction de `consommer.gd`. | CR |
| `test_banc_bonheur.gd` | Câblage : cent passages sur un monde immobile rendent EXACTEMENT le même nombre (un champ dérivé ne dérive pas) ; un poids sur une source absente rend `0.0` sans alarme. | HD, CR |
| `test_banc_psycho_social.gd` | Câblage : la désobéissance est prouvée par DEUX chemins indépendants (le poids, et le gate par état). | CR |
| `test_banc_menace_combat.gd` | Câblage : l'équilibré bascule EXACTEMENT à ratio 1.0 ; le tempérament tient à tous les paliers. | CR |
| `test_banc_grief.gd` | Câblage : même seuil et même grief pour les trois colons — seul le biais les sépare. | CR |
| `test_banc_stress_thermo_vivant.gd` | Câblage : quatre bascules indépendantes ; une plante stressée pousse RÉELLEMENT deux fois moins vite. | CR |
| `test_banc_oubli_consolidation.gd` | Câblage : l'oubli est exponentiel sans qu'aucun mécanisme ne le sache ; le sommeil ne reconsolide que ce qui est encore CRU. | HD, CR |
| `test_banc_ecosysteme_terrain.gd` | Câblage : une proie cachée reste sous le seuil À TOUTE DISTANCE ; l'ordre du tick (chasse en dernier) est verrouillé. | CR |
| `test_banc_parasites_reproduction.gd` | Câblage : deux cycles de vie complets, deux modes de reproduction, mort par parasitose ET réinfestation. | CR |
| `test_banc_predation.gd` | Câblage : population qui naît et meurt en continu ; hiérarchie héréditaire sans une ligne pour le dire. | CR |
| `test_banc_temps_anticipation.gd` | Câblage : le temps est lu dans la FORCE des souvenirs — le temps écoulé identique pour deux repères prouve que ce n'est pas lui qui est lu. | CR |
| `test_banc_temps_vieillissement.gd` | Câblage : rien ne bouge avant le 730ᵉ jour puis le coût sextuple ; deux courbes opposées sur le même âge ; la moitié par parent tient même avec cinq allèles d'un côté et un seul de l'autre. Verrou NÉGATIF : `avancer_tick` relu sur le disque ne doit appeler aucune expression génétique. | CR |
| `test_banc_marche_competence.gd` | Câblage : retirer un tas qu'un colon ne voyait pas ne bouge pas son prix d'une décimale. | HD, CR |
| `test_banc_infrastructure.gd` | Câblage : la matière se conserve sur 60 s ; le grenier plein REFUSE sans qu'un gramme disparaisse. | HD, CR |
| `test_banc_economie.gd` | Câblage : masse totale invariante sur 600 ticks ; les deux produits d'une fonte somment exactement à la masse fondue. | HD, CR |
| `test_banc_affordances_travail.gd` | Câblage : `monde + perdu == référence` (la masse n'est PAS conservée, et c'est le sujet) ; une issue déclarée mais inatteignable est verrouillée à l'envers. | HD, CR |
| `test_banc_affordances_portage.gd` | Câblage : sous le seuil le travail ne COMMENCE pas (il ne ralentit pas) ; deux gates séparés sur la même liste (somme et taille). | HD, CR |
| `test_banc_affordances_connaissance.gd` | Câblage : le dogme porte PAR PROPRIÉTÉ et cède à l'oubli ; le savoir circule sans que la valeur transmise soit jamais déformée. | CR |
| `test_banc_affordances_choix.gd` | Câblage : entre deux échéances le colon est AVEUGLE ; le score affiché a le même argmax que la décision réelle. | HD, CR |
| `test_banc_social_information.gd` | Câblage : la parole affaiblit ce qu'elle porte (aucun receveur n'atteint la certitude du témoin) ; verrou NÉGATIF qu'aucun mécanisme du cœur ne nomme ce contenu. | HD, CR |
| `test_banc_social_rupture.gd` | Câblage : un deuil seul ne fait JAMAIS un traître ; contre-épreuve de cupidité ; `banc_grief` vérifié intact. | HD, CR |
| `test_banc_social_foule.gd` | Câblage : accord entre les noms que le banc ÉCRIT et les propriétés que les entrées partagées COMPARENT ; deux verrous de réversibilité. | HD, CR |
| `test_banc_social_paire.gd` | Câblage : une grandeur par PAIRE via un nom composé ; le plafond par colon empêche seul de franchir le second palier. | HD, CR |
| `test_banc_temps_saisons.gd` | Câblage : deux débits sur la même réserve sans jamais se confondre ; une saison sautée ne déclenche rien ; une chronique brûlée perd ses propriétés sans effacer ce que son lecteur en a tiré. Dernier cas : la configuration du disque rejouée en entier à travers plusieurs saisons. | CR |
| `test_fondations_humidite.gd` | Les deux propriétés modulées par `mouille` portent bien les valeurs réelles du catalogue matériau. | |
| `test_lint_donnees.gd` | Trois scans indépendants : aucune référence de catalogue de `data/*.json` ne pointe dans le vide (forme scalaire et forme liste) ; toute propriété de `types.json` est enregistrée dans un des trois registres ; aucun type n'efface en silence une sous-clé d'un conteneur hérité (registre des effacements voulus). | |
| `test_docs.gd` | Chaque adresse `fichier:fonction` et chaque renvoi `§N` cités dans les documents permanents désignent une fonction ou une section réelle ; aucun d'eux ne renvoie vers un rapport `audit_*.md` (jetable et gitignoré). | |
| `test_volume_docs.gd` | Taille maximale de chaque document, et de leur somme. Voir son en-tête pour la règle et les seuils. | |
| `test_couverture_index.gd` | Rien du disque n'échappe à l'index : chaque script et chaque catalogue y a sa place. | |
| `test_recit_dans_le_code.gd` | Quantité de récit tolérée dans les commentaires `.gd`, par fichier. Voir son en-tête. | |
| `test_doublon_code_doc.gd` | Texte recopié entre la prose du dépôt et les documents. Voir son en-tête. | |
| `test_volume_entetes.gd` | Poids de prose toléré par fichier `.gd` et `.json`. Voir son en-tête. | |
| `test_encodage.gd` | Séquences de double encodage UTF-8 dans `.gd` et `.json`. Voir son en-tête. | |
| `test_pv0b.gd` | Échec volontaire : prouve que l'alarme des tests sonne bien en headless. | |

---

## 6. État, dettes et questions ouvertes (pointeurs)

Ce fichier décrit un ÉTAT, pas une histoire. Le détail vivant est ailleurs —
mettre CES fichiers à jour, pas celui-ci, sauf si la structure change :

**Ce qui s'écrit ici, et ce qui ne s'y écrit pas** : voir `CLAUDE.md`, « La
doc ne croît pas plus vite que le code ».

**`scripts/test_docs.gd` — DEUX TROUS CONNUS, hors de sa portée** : une
adresse `data/<x>.json:<entrée>` n'est vérifiée par rien, et un `.gd`
cité sans `:fonction` non plus. Quels documents il couvre, et pourquoi
les journaux en sont exclus : en-tête du fichier.

**ÉCARTÉ, à ne pas reproposer** : numéroter les sections de banc en
ordinaux latins. Un ordinal se décale à la prochaine insertion, deux
sections ont déjà porté le même identifiant, et tout renvoi vers l'une
devenait ambigu. L'adressage par NOM de banc n'a aucun de ces défauts.

**`scripts/lanceur.gd` — RÉSULTAT MESURÉ, à ne pas rediagnostiquer** : la
sortie de chaque test va dans `%TEMP%/orion_lanceur_<pid>_<nom>.tmp`. Le
PID est ce qui sépare deux lanceurs tournant en même temps sur le même
dépôt ; sans lui, ils écrasent et suppriment mutuellement ces fichiers,
le verdict `code == 0 and texte.find("OK:")` devient faux au hasard, et le
tableau sort une vingtaine de ROUGE **différents à chaque passage**. Signe
distinctif si le symptôme revient : un ROUGE dont la sortie affichée
CONTIENT « OK: », ou deux passages consécutifs qui rougissent deux
ensembles disjoints — dans ce cas la cause n'est plus le nom du fichier.

**`objet.gd:fabriquer` — le type écrase ce qu'il redéclare, et c'est le
CONTRAT, jamais un défaut** : une clé présente à la fois dans un paquet
hérité et dans le type remplace la valeur du paquet en bloc, jamais une
fusion clé par clé. C'est la seule voie par laquelle un type peut REFUSER
ce qu'un paquet lui donne — un golem sans corps physiologique n'en a pas
d'autre. Un type qui veut au contraire AJOUTER redéclare le conteneur EN
ENTIER, ce que `data/types.json:colon` fait déjà pour `canaux_config`
(six canaux, pas seulement `vue`).

Ce qui manquait n'était donc pas une fusion récursive, mais de VOIR
l'effacement quand il n'est pas voulu — une note en donnée en tenait
lieu, c'est-à-dire une discipline humaine. **FERMÉ** : le troisième scan
de `scripts/test_lint_donnees.gd` refuse toute surcharge partielle d'un
conteneur hérité, sur TOUS les `data/*.json` — les trois clés concernées
(`canaux_config`, `deformation_etat`, `reserves`) tombent sous la même
règle, y compris celles que personne n'a encore heurtées. Pourquoi son
registre d'exceptions doit rester vide : `docs/design.md`, « Doctrine des
compartiments ». ÉCARTÉ, à ne pas reproposer : rendre le merge récursif —
ça retirerait la seule façon d'exprimer le refus, pour fermer un trou
qui se ferme en donnée.

**`CARTE.md` §4, ligne `types.json` — verbeuse, condensation identifiée
mais différée** (audit documentation 2026-08-06, arbitrage Yael) : cette
ligne de tableau réexplique en entier, au même niveau de détail que les
sections §2 dédiées et que `docs/design.md` § « Les cinq composants du
corps interne », le pourquoi de chaque paquet et de chaque propriété —
alors que §4 devrait rester un index de données (clés/valeurs/défauts).
Condensation à faire en chantier séparé, avec vérification dédiée :
extraire d'abord chaque valeur numérique, puis retirer la prose — dans
cet ordre, jamais l'inverse. Pas commencé.

**`scripts/monde.gd` — aucune fonction de retrait d'objet** (confirmé en
écrivant `scripts/soudure.gd`/
`banc_soudure.gd`) : aucun mécanisme du dépôt ne supprime jamais une entrée
de `monde` — même un objet entièrement consumé (`extinction.gd`) ou
entièrement absorbé par une soudure (`soudure.gd:souder`) reste pour
toujours dans le conteneur, `proprietes` vidée (`{}`) plutôt que retirée.
Inoffensif tant que chaque mécanisme lit ses propriétés via `.get(cle,
defaut)` (c'est le cas partout aujourd'hui), mais STRUCTURELLEMENT
dangereux dès qu'un mécanisme traite une propriété comme STRUCTURELLE sur
CHAQUE chose de `monde` sans filtrage préalable — `temperature.gd:avancer`
en est la première preuve concrète : `proprietes.temperature` y est
structurelle, un fantôme non filtré y `push_error` INDÉFINIMENT à chaque
tick. `banc_soudure.gd` contourne ceci AU CÂBLAGE (`_monde_vivant()`,
filtre les fantômes avant `Temperature.avancer`/`SeuilEtat.avancer`),
jamais dans `temperature.gd` lui-même. **FERMÉ SANS AJOUTER DE RETRAIT** :
le geste, recopié dans vingt-sept endroits, vit désormais une seule fois —
`banc_commun.gd:monde_depuis`, qui porte le contrat et sa raison d'être ;
`test_banc_commun.gd` empêche qu'une copie réapparaisse. ÉCARTÉ, à
ne pas reproposer : un `retirer()` sur `monde.gd` — il rouvrirait la question
des index pour un geste que la liste d'appel exprime déjà.

**Convention de survie d'une fusion à deux objets — NON TRANCHÉE**
(`scripts/soudure.gd:souder`, chantier « soudabilite ») : `chose_a` garde
toujours son id et sa position, `chose_b` est toujours l'objet absorbé —
un choix d'API (le premier argument gagne), jamais une règle de jeu
(lequel des deux DEVRAIT survivre — le plus gros ? le plus vieux ? une
position moyenne ?). `banc_soudure.gd` ne tranche pas la question, il
suit juste la convention d'API. Même famille de question que « lequel des
deux gestate », dont la voie de sortie est connue : une PROPRIÉTÉ portée
par la chose (`role_gestation`, lue par `accouplement.gd`), jamais une
convention d'appelant. À trancher le jour où un contenu réel (pas une
démonstration) a besoin de choisir.

**ÉCARTÉ — pré-borner la demande avant `Consommer.transferer`** :
`consommer.gd` est conservatif par construction et rend la quantité
RÉELLEMENT retirée (§2). Borner côté appelant serait un second bornage
pour une invariante déjà garantie, et ferait dire à toute trace ce qu'on
a DEMANDÉ plutôt que ce qui s'est passé. Les appelants passent donc la
demande nue avec `delta=1.0` (les taux passés sont des quantités déjà
résolues, pas des débits) et lisent le retour :
`ecoulement.gd:avancer`, `banc_fertilite.gd:avancer_cadavres`,
`banc_erosion.gd` (`eroder_par_eau`/`eroder_par_vent`). Un court-circuit
sur réserve vide n'est pas un bornage et reste légitime.

**TROIS CONTRATS DE `somme.gd` TRANCHÉS SANS CONSIGNE** (même chantier) —
la consigne nommait six cas de test, aucun ne couvrait ces chemins ; ils
ont été tranchés par alignement sur `comptage.gd`, pas par décision de
Yael. MISE À JOUR (chantier « portage + force + stabilisation ») : ils ne
sont plus RÉOUVRABLES à peu de frais. Les deux premiers sont désormais
traversés par un appelant réel — `banc_affordances_portage.gd`
(`banc_affordances_portage`) mêle dans la même scène des choses qui portent la grandeur
et des choses qui ne la portent pas, et `test_banc_affordances_portage.gd`
verrouille explicitement que l'absence contribue `0.0` sans alarme et que
`somme.gd` ne crée jamais la clé qu'on lui demande. Les changer casserait ce
banc. Chacun reste verrouillé par `test_somme.gd` :
1. **Élément mal formé** (pas un Dictionary, `proprietes` absente ou d'un
   autre type) : ignoré SILENCIEUSEMENT — même garde que
   `comptage.gd:compter` (Array sale légitime, l'appelant filtre s'il
   veut).
2. **Valeur présente mais NON NUMÉRIQUE** : `push_error` nommant
   l'entité, elle contribue `0.0`, la somme continue — contrat de
   `comptage.gd:_satisfait` mode `superieur_a`.
3. **Aucune mutation des entités**, y compris interrogé sur une grandeur
   absente (aucune clé créée par un `.get()` à défaut) — `somme.gd` est
   un lecteur, au même titre que `comptage.gd`.

**Doctrine — poser une valeur de catalogue, c'est la COPIER** : un
Dictionary ou un Array assigné tel quel depuis une entrée de catalogue
partage sa référence avec toutes les choses qui résolvent cette même
entrée ; le mécanisme qui mute ensuite cette sous-structure en place écrit
sur toutes à la fois. Mesuré : un jeton de franchissement posé par la
première chose a empêché toutes les suivantes de se consumer.
`duplicate(true)` avant assignation est donc STRUCTUREL, jamais une
précaution — `banc_commun.gd:resoudre_chantier`,
`depense.gd:_appliquer_seuil`, `charge.gd:avancer`,
`extinction.gd:_appliquer_a_zero`. Vaut pour tout mécanisme futur qui pose
depuis un catalogue.

**Doctrine — propriété du monde vs champ de configuration technique** :
`docs/design.md` § « Propriété du monde vs champ de configuration
technique » distingue les champs perceptibles/manipulables
(`brule`, `cassable`, `rythme`...) des pointeurs vers catalogue
(`profil_saillance`, `seuils_ref`, `herite`) — ces derniers
n'ont rien à faire dans les listes `proprietes_captees` des catalogues
de canaux/menaces/jugements/engagements.

**Doctrine — les collectifs n'existent pas** : `docs/design.md` §
« Les collectifs n'existent pas — un résumé lu, pas un objet posé »
tranche qu'aucun objet-groupe (faction, cité, zone, sédimentation) n'a
sa place dans le moteur — un mot collectif est un résumé lu à la
demande sur N colons, jamais un état détaché posé quelque part.
Contraint tout futur mécanisme de zone, de faction lointaine ou de
sédimentation psychique.

### Séparation framework / jeu (dette explicite, à ouvrir plus tard)

Aujourd'hui, data/ mélange les catalogues du framework et les
données du jeu Orion. Le chantier de séparation proprement dite
est reporté (voir CLAUDE.md, « Frontière framework / jeu »).

Ce que le chantier fera, quand il sera ouvert :

* Déplacer les catalogues du framework dans data/framework/ :
  canaux.json, deformations.json, materiaux.json, comptages.json,
  profils_saillance.json, transformations.json,
  seuils_combustible.json.
* Déplacer les catalogues et fichiers du jeu dans data/jeu/ :
  menaces.json, jugements.json, orientations.json, flux.json,
  engagements.json, actes_liants.json, liens_personnels.json,
  attaches_par_trait.json, types_choses.json, types_attaches.json,
  banc_*.json, _exemple.json.
* Couper data/types.json en deux :
  - data/framework/paquets.json porte les quatre paquets
    fondateurs (objet_physique, dynamique, percevant, agent).
  - data/jeu/types.json porte les types nommés d'Orion (colon,
    arbre, feu, bloc, batisse).
  - L'appelant (banc, ou point d'entrée du jeu) fusionne les
    deux tables avant de les passer à Objet.fabriquer, qui reçoit
    une seule table depuis toujours et n'a pas à changer.
* Mettre à jour les _ready des bancs qui chargent des catalogues
  (chemins).
* Mettre à jour CARTE.md §4 (chemins des catalogues) et §5
  (`test_lint_donnees.gd` vérifie les nouveaux chemins).

Ce que le chantier NE FERA PAS :
* Toucher un seul mécanisme du cœur (scripts/*.gd hors bancs).
* Toucher un seul test hors domaine (chacun charge ses propres
  fixtures ou reçoit son catalogue en paramètre).
* Changer un comportement observable.

Le coût du chantier grandit avec le nombre de fichiers dans
data/ et avec le nombre de bancs qui chargent des catalogues.
Aujourd'hui : chantier léger. Le jour où data/ portera cinquante
fichiers de contenu Orion : chantier moyen. Le faire tôt reste
moins cher que le faire tard, mais ne le faire QUE quand une des
trois conditions ci-dessus est réunie — sinon c'est de la
friction gratuite.

### L'entité comme agent complet — chantier unifié

Les tâches suivantes, historiquement listées séparément, sont regroupées comme faces d'un même chantier :
- Formation d'attaches en jeu
- Lien personnel
- La déformation individuelle (vecteur)
- en_detresse / appeler à l'aide

Vues par lots dans `docs/design.md` § "L'entité comme agent complet". Suivi dans `docs/suivi_corps_interne_entite.md`.

- **Ce qui reste à construire** : `docs/design.md`, « État des couches → PAS
  FAIT » — liste à jour, non recopiée ici. CORRIGÉ : l'énumération qui vivait
  ici avant citait encore « formation d'attaches en jeu » (FERMÉE depuis
  PHASE 5) et « second canal de perception » comme simplement absent (il
  existe depuis PHASE 3.5, seulement inactif géométriquement dans les bancs
  actuels — nuance perdue par la recopie). Recopier cette liste ici l'expose
  à périmer une deuxième fois ; seul `docs/design.md` la tient à jour.
- **`competence` (source de déformation individuelle) — IDENTIFIÉE, JAMAIS
  COMMENCÉE** (retrouvée pendant l'audit documentation 2026-08-06, en
  condensant `docs/cadrage_corps_interne_colon.md`) : la déformation
  individuelle prévoit trois sources depuis PHASE 0 (`docs/design.md` §
  « Le chantier » — habituation, trauma, compétence), mais `deformation.gd`
  et `data/deformations.json` n'implémentent à ce jour QUE `habituation` —
  aucun mécanisme, aucune entrée de catalogue, aucun test ne portent
  `trauma` ni `compétence`. VÉRIFIÉ (cette entrée) : `compétence` n'a été
  abandonnée par AUCUNE décision — elle a simplement été formulée à PHASE 0
  et jamais reprise depuis, exactement comme `trauma`. Ce qu'elle voulait
  dire : une déformation qui vient de la répétition RÉUSSIE d'un geste —
  contrairement à `habituation` (répétition d'une EXPOSITION, subie) et
  `trauma` (un CHOC, subi), c'est la seule des sources envisagées dont
  l'origine est ce que l'entité a FAIT, pas ce qu'elle a subi. Sort de la
  quatrième source citée à PHASE 0, `attachement_positif` (absente des
  trois sources citées par `docs/design.md` aujourd'hui) : même statut
  qu'`competence` (jamais câblée, jamais abandonnée par décision), avec un
  degré d'oubli supplémentaire — son nom même avait disparu de
  `docs/design.md` avant cette session, il ne survivait que dans la
  version PHASE 0 de `docs/cadrage_corps_interne_colon.md` (désormais
  signalé dans ce fichier, section « Structure — les cinq composants »).
  Inscrit ici plutôt que dans `docs/ETAT.md` : ce fichier héberge déjà le
  patron d'un chantier identifié-mais-non-commencé (voir « Séparation
  framework / jeu » ci-dessous), et `docs/ETAT.md` était en cours
  d'écriture active par une autre session au moment de cet audit — un
  second écrivain simultané y aurait risqué la collision que `CLAUDE.md`
  nomme explicitement (Discipline de travail, point 9).
- **`fuir` — FERMÉ** : le JUGEMENT (troisième source de saillance) est
  fourni par `jugement.gd`/`data/jugements.json` ; le verbe est résolu par
  `agir.gd` (`decl.verbes`, arbitré par `poids_verbes`) ; le mouvement
  sans cible par `fuite.gd`/`bouger_selon`, câblé via
  `choses_a_fuir`/`data/orientations.json` (`banc_p1.gd`/`banc_feu.gd`).
  `banc_feu.gd:decider` est le premier pipeline réel à inclure le
  jugement — voir §2 (`jugement.gd`, `ciblage.gd`, `fuite.gd`), `banc_feu`.
  Dans `banc_p1.gd`, la branche fuite existe et est testée
  (`choses_a_fuir`) mais N'EST EXERCÉE PAR AUCUNE DONNÉE RÉELLE
  aujourd'hui : aucune entrée de `data/types_choses.json`/
  `data/types_attaches.json` (les catalogues que charge ce banc) ne
  propose le verbe `s_eloigner`, donc aucune décision de `banc_p1.gd` ne
  peut résoudre vers lui — chemin mort par absence de donnée, pas par
  code manquant.
- **Questions ouvertes non tranchées** (calque vs mutation de forme, déclencheur
  lien personnel → attache, ordre dans `menaces.json` quand plusieurs menaces
  s'appliquent, forme gagnante du placide) : `docs/design.md`, « Questions
  ouvertes ».
- **Le monde comme instance** : `docs/monde.md` (géographie, factions, cosmologie
  — encore largement à remplir).

