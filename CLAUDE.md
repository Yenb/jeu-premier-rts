# CLAUDE.md — LE JEU

Ce fichier donne à Claude Code le contexte nécessaire pour travailler sur le
JEU. Le framework Orion a son propre `CLAUDE.md`, dans son propre dépôt : ce
fichier ne le remplace pas, il en reprend les règles qui valent aussi ici.

Journal de bord de la programmation du jeu : `SUIVI.md`, à la racine. C'est le
SEUL document que Claude modifie au fil des sessions.

Game design du jeu : `jeu/GAME_DESIGN.md`.

## Aperçu

Premier jeu RTS bâti sur le framework Orion.

Le framework est une COPIE en LECTURE SEULE, répartie entre `scripts/`, `data/`
et `documents/`. Le contenu du jeu vit dans `jeu/`. Toute écriture se fait dans
`jeu/`, ou dans les documents du jeu à la racine (`CLAUDE.md`, `SUIVI.md`) —
JAMAIS dans `scripts/`, `data/` ni `documents/`.

## Arborescence

- `scripts/` — le cœur du framework, à la racine (lecture seule).
- `data/` — les catalogues du framework, à la racine (lecture seule).
- `documents/CARTE.md` — l'index du moteur, fichier par fichier (lecture seule).
- `documents/` — la doc du framework : `design.md` (le design et le
  pourquoi), `prototypes.md` (l'état des bancs). Lecture seule.
- `jeu/` — tout le contenu propre au jeu.

## Frontière

Le jeu ne touche JAMAIS `scripts/`, `data/` ni `documents/`. Que le cœur et les
catalogues du framework soient posés À LA RACINE ne les rend pas écrivables :
la racine n'est ouverte que pour les documents du jeu. S'il manque une
mécanique, ce n'est pas un
chantier de jeu : c'est un chantier FRAMEWORK, et il se fait dans l'autre
dépôt. Claude s'arrête et le DIT — il ne bricole pas la mécanique manquante au
passage.

## Connexion LLM

Le classifieur stratégique parle à un modèle local par HTTP POST vers
`127.0.0.1:11434/api/generate` (Ollama). Modèle : `llama3.2-32k` — ou
`llama3.2:3b` tant que la variante 32k n'est pas créée. La sortie est forcée
par une grammaire GBNF ; le prompt seul ne suffit pas.

LA SORTIE DU MODÈLE NE RENTRE JAMAIS DANS L'ÉTAT DE LA SIMULATION. Le modèle
lit un résumé d'état et rend une CLÉ ; le moteur reste la seule autorité sur ce
qui est vrai. Le modèle n'a AUCUNE mémoire d'un appel à l'autre. Les agents
mémoire sont côté CODE, dans le moteur du jeu — jamais dans le modèle.

Agents : chaque agent est un Modelfile Ollama séparé (un system prompt plus des
paramètres). Dix agents = dix Modelfiles, un seul modèle de base. Le modèle
suit les consignes à la lettre — la qualité du system prompt et du résumé
d'état décide de tout.

---

# LES RÈGLES DU FRAMEWORK

Ce qui suit est RECOPIÉ TEL QUEL du `CLAUDE.md` du framework, sans résumé et
sans reformulation. Les règles valent identiquement ici.

Correspondance des chemins, à lire une fois et à appliquer partout dans ce
bloc : `scripts/` et `data/` désignent `scripts/` et `data/` À LA RACINE
(lecture seule) ; `CARTE.md`, `docs/design.md` et `docs/prototypes.md`
désignent `documents/CARTE.md`, `documents/design.md` et
`documents/prototypes.md` ; `docs/ETAT.md` désigne, pour le jeu,
`SUIVI.md` à la racine. Le code neuf du jeu s'écrit dans `jeu/`.

## Ne code pas ce que tu n'as pas compris
Si une consigne est ambiguë, si tu dois deviner une intention, si tu hésites
entre deux lectures : ARRÊTE-TOI et demande. N'écris pas de code.

Une hypothèse silencieuse coûte plus cher qu'une question.

N'affirme jamais que quelque chose marche si tu ne l'as pas lancé. Ce qui
reste à vérifier à l'écran se dit EN UNE LIGNE, une seule fois, en fin de
récapitulatif. Yael sait que Claude n'a ni écran ni souris : le redire, le
justifier, s'en excuser ou conseiller comment regarder est du bruit — « le
rendu est à vérifier à l'écran » suffit, et le paragraphe qui l'explique ne
s'écrit pas. Tu proposes, je vérifie.

Ne bricole pas un contournement pour masquer ce que tu ne peux pas faire.
Dis que tu ne peux pas.

Avant tout morceau de code : constat écrit du périmètre (quels fichiers
touchés, quels champs lus, quoi casse si ça change). Le constat précède le
code, toujours.

## ADN : le moteur ne connaît que des verbes

Un seul moule : l'objet, un sac de propriétés cumulables (position,
opaque, solide, mouvant, inflammable, attaches...). Aucune catégorie de
type dans le code moteur — pas de « colon », « mur », « feu » comme
boîtes ; aucun trait, seuil, événement, faction ou effet n'apparaît en dur.
Tout le contenu vit en données, dans `data/`. Ajouter un contenu = une
ligne de données, zéro ligne de code — validé par Dwarf Fortress et
RimWorld (inflammabilité, types de menace : des données, pas du code). Il
doit marcher avec 3 traits comme avec 300, sans recompilation. Détail et
justification : docs/design.md, section "Tout est objet".

Test permanent, à faire tourner sur tout code moteur écrit ou relu : si
le code mentionne le nom d'une chose du monde (`"mur"`, `"colon"`,
`"feu"`, `type == "..."`) — c'est une catégorie qui s'est glissée. STOP,
remplacer par une propriété.

Exception, une seule : un banc jetable peut nommer une catégorie pour
poser une scène d'observation ("mur ici, colon là"). Ce nommage ne
survit jamais dans le moteur permanent.

Si une tâche exige de modifier le moteur pour ajouter du contenu : signal
d'alarme, s'arrêter et le dire — ne pas coder d'abord.

L'image qui porte le pourquoi, et pas seulement la règle : le moteur est
un GÉNOME, le contenu est ce qui s'exprime. Toutes les cellules d'un
corps portent le MÊME ADN — un neurone et une cellule de foie ne
diffèrent pas par le code, mais par ce qui s'exprime. Faire pousser un
organe ne demande jamais de rouvrir le génome. Et le rouvrir pour un
seul organe n'est pas une retouche locale : ça touche l'organisme
entier et toute sa descendance — un mécanisme du cœur modifié pour un
contenu change TOUS les contenus qui s'en servent, ceux déjà écrits
comme ceux à venir, et le dégât n'apparaît pas là où on a écrit.

## Autres règles non négociables

- INTERNATIONALISATION (couvre aussi la traduction) : aucune chaîne de
  texte visible par le joueur n'apparaît en dur dans le code, ni composée
  par concaténation — le code manipule des CLÉS, les textes (avec leurs
  trous nommés) vivent en données. Ajouter une langue = un fichier, zéro
  ligne de code. Vaut dès la première ligne d'interface, ne se
  rétrofitte pas.
- VERTICALITÉ : toutes les positions sont des Vector3, jamais des
  Vector2, même si Z reste à zéro aujourd'hui. Ne se greffe pas après
  coup.
- Aucun hasard non-seedé : tout aléa passe par un RNG seedé et
  reproductible.
- La simulation ne dépend JAMAIS de l'affichage : le moteur doit pouvoir
  tourner sans rendu.
- Raison des deux règles ci-dessus : garder la porte du multijoueur
  ouverte sans coût aujourd'hui. Ne rien coder pour le multijoueur
  maintenant.
- LLM-ANCRÉ : tout état du monde reste lisible en données ET résumable —
  c'est la condition de l'ancrage LLM, pas seulement de l'ajout de contenu.
  Le jeu nourrit l'LLM par tranche résumée, jamais le firehose ; l'LLM lit
  l'état, il ne l'invente jamais. Voir design.md, « L'LLM : lecteur ancré,
  jamais auteur ».

## Godot : jamais de class_name

Un class_name n'est enregistré qu'au scan de l'éditeur. Les tests tournent en
--headless --script, sans éditeur : l'appel par nom échoue et il faut forcer
un rescan à chaque fois.

Donc : PAS de class_name. Toujours preload.
  const MaClasse = preload("res://scripts/ma_classe.gd")

Si tu vois un rescan devenir nécessaire, c'est qu'un class_name a été
réintroduit. Corrige-le, ne contourne pas.

## Doctrine d'en-tête

Tout fichier de code commence par un bloc de commentaire qui dit :
- ce que fait le fichier (son rôle dans le moteur, sa couche)
- ce qu'il reçoit en entrée et ce qu'il rend en sortie
- les règles à respecter (ex. "lit proprietes, jamais le type")
Un fichier sans en-tête est incomplet. L'en-tête est le mode d'emploi de
l'outil : un repreneur (humain ou agent) doit comprendre le fichier sans
lire son code. Modèle déjà en place : proximite.gd, attaches.gd.

UN EN-TÊTE N'A AUCUNE DIMENSION TEMPORELLE — ni nom de chantier, ni date,
ni « avant/après », ni « corrigé depuis », ni « aucune régression ». Le fil
entre deux sessions vit dans `docs/ETAT.md` et dans le message de commit,
JAMAIS dans un `.gd` ni dans une `_note` de `data/*.json` : polluer le code
avec de la mémoire de session, c'est écrire dans le fichier qui n'est
relu par personne ce que porte déjà celui qui est relu en premier.

Un résultat négatif ne s'y RACONTE pas, il s'y CONJUGUE AU PRÉSENT. Pas
« plafonner chaque registre a été essayé puis écarté, le biais retombait » —
mais « plafonner chaque registre est ÉCARTÉ : le biais retombe alors que la
cause est encore là ». Même fait, même interdit, zéro histoire.

Opposable : `scripts/test_recit_dans_le_code.gd` compte les marqueurs de
récit par fichier et rougit dès qu'un compte monte ;
`scripts/test_doublon_code_doc.gd` fait de même pour une phrase recopiée
entre un fichier et un document.

## La doc ne croît pas plus vite que le code

Vaut pour TOUT `.md` du dépôt, celui-ci compris. Avant d'écrire une
phrase, lui poser les cinq questions. UN SEUL « oui » suffit à ne pas
l'écrire.

1. RÉCIT — dit-elle ce qui S'EST PASSÉ au lieu de ce qui EST ?
   (« CORRIGÉ », « avant ce chantier », « défaut fermé », une date, un
   diagnostic raconté) → git les tient (git log, message de commit).
   Seule survit la LEÇON du défaut, une ligne, là où vivent les dettes.
2. DOUBLON — ce fait est-il déjà écrit ailleurs, même autrement dit ?
   Le redire ne prouve pas qu'on a travaillé : ça crée deux vérités qui
   divergeront. → « voir `<fichier>` § `<titre>` », vers un fichier SUIVI
   PAR GIT. Vrai pour TOUTES les entrées d'une section : ça s'écrit une
   fois en tête, jamais dans chacune.
3. COMPTE EN DUR — un nombre qui bouge quand le dépôt bouge ? (« 56
   mécanismes », « 175 tests VERT », un chrono relevé au lancement, un
   ordinal de section qui se décale à la prochaine insertion) → adresser
   par NOM ; nommer l'endroit qui porte le compte, pas le compte. Un
   compte recopié périme en silence, sans casser aucun test.
4. VERBIAGE — coupée de moitié, perd-elle une information ? Si non,
   couper : justification déjà donnée, « autrement dit », deuxième
   exemple qui montre la même chose, paraphrase d'un test ou d'une
   donnée — la source de vérité est le fichier, la paraphraser garantit
   qu'elle divergera.
5. INUTILE — ne change-t-elle AUCUNE décision future ? Trois cas gardent,
   aucun autre : l'INDEX (ce qui existe, ce que fait un fichier, adresse
   `fichier:fonction`) ; un RÉSULTAT NÉGATIF (essayé, échoué, POURQUOI —
   interdit de le refaire) ; un ÉCARTÉ DOCTRINAL (rejeté, pourquoi —
   interdit de le reproposer). Tout le reste ne s'écrit pas.

Puis, sur le FICHIER, avant de rendre la main — réponse dans le
récapitulatif de fin de tâche, jamais dans le `.md` :

- SOLDE — mesurer en OCTETS, jamais en lignes : une seule ligne de
  tableau peut peser 18 000 caractères sans que rien ne le signale. Le
  fichier a-t-il grossi ? Si oui, nommer ce qui sort en échange. Zéro
  retrait = l'ajout n'est pas fini ; « rien n'était redondant » ne se dit
  qu'après avoir relu la section entière, et se dit explicitement.

CE SOLDE N'EST PLUS UNE AUTO-DISCIPLINE : `scripts/test_volume_docs.gd`
porte un plafond en octets par document et rougit dès qu'un document
enfle. Trois purifications successives de la doc n'ont pas tenu, et
toujours pour la même raison — retirer du texte ne change rien à ce qui
le produit. Deux réponses légitimes à un plafond dépassé : retirer autant
qu'on ajoute, ou remonter le plafond DANS LE MÊME COMMIT, ce qui rend la
croissance visible dans le diff au lieu de la laisser passer en silence.

Fermeture de chantier : UNE ligne dans ETAT.md (`hash — quoi`), le reste
dans le message de commit — jamais un compte rendu dans un `.md`.

Une doc qui ne peut PAS rétrécir est une doc qu'on a cessé de relire.

## Discipline de travail (imposée par Yael, à faire respecter par Claude)

Yael pense en transversal : il change de sujet, saute d'un système à l'autre, mélange
une idée de design avec une question technique. C'est sa méthode et elle est productive.
Le rôle de Claude n'est PAS de la corriger. C'est de la TENIR.

Concrètement, Claude doit :

1. UNE CHOSE À LA FOIS. Si Yael demande trois choses dans un prompt, Claude les sépare,
   les nomme, et demande par laquelle commencer. Il ne les fait pas toutes.

2. REFORMULER AVANT D'AGIR sur toute demande ambiguë ou brouillonne.
   "Je comprends : X, Y, Z. Je commence par X ?" Puis attendre.
   Ne jamais deviner et coder dans le vide.

3. NOMMER LA DÉRIVE. Si Yael introduit une idée qui contredit le design.md, Claude le dit
   AVANT de coder. Pas pour refuser — pour que la contradiction soit consciente.

4. SIGNALER QUAND ÇA DEVRAIT ÊTRE UNE DONNÉE. Si une demande implique de toucher au code
   du moteur, Claude pose la question : "pourquoi ça ne tient pas dans data/ ?"
   Il ne code pas d'abord.

5. TENIR LA CARTE. À la fin de chaque système ajouté, Claude dit en une ligne
   OÙ vit la décision qu'il vient d'écrire. Yael doit toujours pouvoir répondre à
   "où se prend la décision du colon ?".

6. PAS D'ARROGANCE, PAS DE COMPLAISANCE. Claude ne flatte pas, ne s'excuse pas,
   n'édulcore pas. Il dit ce qui est. Yael préfère être contredit tôt que tard.

7. DIRE OÙ LE CONTENU A ATTERRI. À la fin de chaque tâche, Claude dit
   explicitement s'il a dû toucher un script du cœur pour ajouter du
   contenu, et pourquoi. S'il n'a touché que des données, il le dit
   aussi — jamais un silence à la place de cette phrase.

8. UN SEUL MORCEAU VÉRIFIABLE À LA FOIS. Prolonge le point 1 à l'intérieur
   même d'une tâche déjà acceptée : Claude s'arrête après un morceau
   vérifiable, lance, regarde, et attend le feu vert avant de continuer —
   jamais deux morceaux d'affilée. Même principe que prototypes.md
   applique aux bancs.

9. UN FICHIER, UN ÉCRIVAIN. Sur des chantiers parallèles (plusieurs
   instances actives sur le même dépôt), un fichier n'a jamais deux
   écrivains en même temps. Deux écrasements se sont produits faute de
   ça : un commit sans pathspec qui aspire le working tree d'un fichier
   partagé, un `git apply --cached` isolé qui a fini par tout réindexer.

## Quand Yael dit que ça ne marche pas

Le code peut être juste et le problème entier : ce qui manque alors n'est
pas la qualité du travail, c'est le RAPPORT au problème.

- QUAND YAEL POSE UNE QUESTION OU SIGNALE QUELQUE CHOSE, CE N'EST PAS UNE
  CRITIQUE DU TRAVAIL : il veut COMPRENDRE. Répondre à ce qu'il demande,
  jamais défendre ce qui a été fait. Une réponse qui explique pourquoi le
  code est bon ne répond à personne.
- PREMIÈRE RÉPONSE : UNE QUESTION, JAMAIS UNE EXPLICATION. « Qu'est-ce que
  tu attendais qu'il se passe ? » avant tout diagnostic. Un écart entre « ça
  marche » et « ça ne marche pas » est le plus souvent un écart d'OBJECTIF,
  pas de code.
- LE SYMPTÔME OBSERVÉ GAGNE TOUJOURS SUR LE TEST VERT. Un test qui ne voit
  pas le symptôme est un test incomplet, jamais une preuve que le symptôme
  n'existe pas. Ce que les tests ne peuvent PAS voir se dit AVANT de les
  montrer — un test headless ne voit rien de l'éditeur.
- AVANT DE CODER, DÉCRIRE CE QUI SE VERRA À L'ÉCRAN, jamais ce qui va être
  construit. Une phrase, validée ou corrigée en trente secondes. Décrire le
  mécanisme ne révèle aucun malentendu : les deux descriptions peuvent être
  vraies et parler de deux choses différentes.
- UN NOM PAR CHOSE, tenu du code jusqu'à la conversation. Trois noms pour un
  même objet coûtent plusieurs échanges à chercher le mauvais nœud.
- NOMMER TOUT CHOIX STRUCTURANT AU MOMENT OÙ IL EST PRIS, surtout celui qui
  épargne du travail à Claude. Un choix qui n'est pas dit ne peut pas être
  contesté.

## Méthode

- Répondre en français, toujours, sans exception, dans toutes les réponses
  — y compris commentaires de code, messages de commit, et récapitulatifs.
- Pas de préambule, pas d'éditorialisation.
- Pas de "oui mais" non demandé, pas de prudence automatique.
- Ne jamais supposer ce que Yael pense (voir Discipline de travail, point 2).
- Chercher avant d'affirmer.
- Réponse nette à question nette, puis s'arrêter.
- Yael fait le design et teste. Claude écrit tout le code.

## Règle d'état

- Ne jamais déclarer un fichier fait sans avoir vérifié qu'il existe sur
  le disque et que son test passe. "En cours" n'est pas "fait".
- Ne jamais se fier à une lecture antérieure d'un fichier, à un souvenir de
  session, ni à un résumé de compaction : relire sur le disque avant
  d'affirmer quoi que ce soit sur son contenu — la vérité est sur le
  disque, pas dans le contexte.
- Tout comportement du banc (`banc_p1.gd`) qui a marché une fois est
  verrouillé par un test headless (`scripts/test_banc_p1.gd`). Un
  comportement sans test régresse en silence. Si la logique à verrouiller
  est enfermée dans `_process` ou `_unhandled_input`, elle en sort en
  fonction statique testable — le clic ou la boucle ne fait que déclencher,
  jamais calculer.

## Forme des prompts de tâche

Les prompts de Yael ne répètent plus le contexte projet (il est ici). Ils
portent seulement : le constat préalable propre à la tâche, le périmètre
(fichiers touchés / interdits), et les issues vérifiables (vert/rouge).
Ne réclame pas le pavé de contexte : va le lire toi-même sur le disque.

Cas particulier, les prompts de GAMEPLAY. La règle qui suit ne vaut QUE
pour le gameplay : elle ne s'applique PAS à l'écriture du framework.
Trancher lequel des deux, avant toute chose :

- FRAMEWORK — le prompt demande un MÉCANISME, nommé par ce qu'il fait
  et jamais par ce qu'il représente. Exemple : « un scalaire qui
  diffuse de voisin en voisin en s'atténuant avec la distance ». Ça
  ne se recopie pas d'un patron : ça s'écrit neuf dans `scripts/`, et
  ça se prouve générique par un test hors domaine. La règle ci-dessous
  ne s'applique pas.
- GAMEPLAY — le prompt demande une CHOSE DU MONDE, nommée. Exemple :
  « un sort de peste qui se transmet de colon en colon ». Ça ne
  s'invente pas : ça se recopie d'un patron existant et ça vit dans
  `data/`. La règle ci-dessous s'applique.

Même diffusion de voisin en voisin dans les deux exemples : c'est le
NOM qui tranche, pas le sujet. Un mécanisme se nomme par son verbe,
un contenu par la chose qu'il désigne.

La règle, donc, pour le gameplay seul : le prompt NOMME les bancs
existants qui servent de PATRON de câblage, et IMPOSE leur lecture
avant toute écriture. Un prompt de gameplay qui ne nomme aucun banc est
incomplet — mais la protection ne repose JAMAIS sur la mémoire de Yael.
Si le prompt n'en nomme aucun, Claude ne renvoie pas la question : il
va CHERCHER les patrons lui-même (`scripts/banc_*.gd`,
`docs/prototypes.md`), les propose nommément, et attend validation. Il
n'écrit rien tant qu'il ne les a pas lus. Raison : le câblage n'est pas à TROUVER, il est déjà résolu
dans le banc. Sans le banc sous les yeux, Claude refait une réflexion
qui a déjà eu lieu — travail jeté, et ce qui en sort ne recolle jamais
tout à fait à ce qui existe. Avec le banc, il n'y a plus rien à
concevoir : on recopie et on change les noms. Le nom d'un banc ne dit
pas ce qu'il fait — deux bancs au nom proche peuvent porter deux
mécaniques sans rapport. Choisir son patron au nom, sans l'ouvrir, mène
droit au travail jeté que cette règle existe pour éviter.

UN GAMEPLAY EST UNE COMPOSITION, JAMAIS UNE PIÈCE. Il n'invente aucune
mécanique : il en assemble plusieurs déjà écrites. Un gameplay tient
donc PLUSIEURS bancs par définition, pas par accident — « un barbare à
forte appétence de combat traverse une forêt à pousse rapide, avec des
alliés, contre des porteurs de maladie » n'est pas cinq tâches, c'est
UN gameplay à cinq bancs. Ne jamais le découper en morceaux livrés
séparément : ce qui FAIT le gameplay est le câblage ENTRE les bancs, et
cinq morceaux séparés ne rendent que cinq bancs qui existaient déjà. Le
« une chose à la fois » de la Discipline de travail vaut pour le
framework, où chaque mécanisme est neuf et se prouve seul ; en gameplay
rien n'est neuf, il n'y a rien à isoler.

Conséquence : en gameplay, Claude n'écrit AUCUNE mécanique, et ne
touche ni un script du cœur ni un banc existant. Tout ce dont il a
besoin est déjà là ; son travail est de faire tenir les bancs ensemble.
S'il se surprend à écrire un mécanisme, il s'est trompé de mode —
signal d'alarme, voir « ADN ».

S'IL MANQUE VRAIMENT UNE MÉCANIQUE — le gameplay demande une chose
qu'aucun banc ne sait faire : ce n'est plus du gameplay, c'est un
chantier de framework. Il ne se bricole pas au passage, dans le même
prompt, sous prétexte qu'il bloque. Claude s'arrête et le DIT. Avant
toute ligne, trois choses, dans l'ordre : (1) l'analyse du code
existant qui PROUVE que la mécanique manque — qu'elle n'est pas déjà
écrite ailleurs sous un autre nom ; (2) le constat écrit du périmètre
(voir « Ne code pas ce que tu n'as pas compris ») ; (3) la définition
du mécanisme par son VERBE, hors de tout contenu, prouvable par test
hors domaine. Le gameplay attend que ce chantier soit fermé — il ne
part pas avec une mécanique à moitié définie.

---

# TRAVAILLER SUR LE PROJET

## Les deux dépôts

- JEU (ce dossier) : `https://github.com/Yenb/jeu-premier-rts` — c'est ici que
  vont les commits et les push.
- FRAMEWORK : `https://github.com/Yenb/orion`. Ses fichiers sont présents ici en
  COPIE (`scripts/`, `data/`, `documents/`) et n'y sont jamais écrits — les
  corriger se fait dans son dépôt, et rien ne se pousse d'ici vers lui.

C'est un projet Godot, pas un projet CLI/npm/etc. — pas de gestionnaire de paquets, pas de lint. Le développement passe par l'éditeur Godot ou l'exécutable `godot`.

Yael travaille depuis deux machines ; le chemin de l'exécutable Godot
diffère sur chacune, et `godot` n'est PAS dans le PATH. Avant toute
commande, vérifier lequel des deux chemins existe sur la machine
courante — ne jamais supposer :

- Machine « yaeln » : `C:\Users\yaeln\Desktop\Dev\Godot\Godot_v4.7.1-stable_win64_console.exe`
- Machine « Asus » : `C:\Users\Asus\Documents\Jeu\Godot_v4.7-stable_win64.exe`

Si aucun des deux n'existe, chercher (`find`/`Get-ChildItem`) plutôt que
deviner, ou demander.

Toute commande de lancement s'écrit avec l'opérateur d'appel PowerShell
et le CHEMIN COMPLET trouvé ci-dessus — jamais `godot` seul (pas dans le
PATH), jamais `&&` pour chaîner (n'existe pas en PowerShell 5.1 ; utiliser
`;`). Forme exacte, à reproduire telle quelle :

    & "<chemin trouvé ci-dessus>" --headless --script jeu/test_xxx.gd

- Ouvrir l'éditeur : `& "<chemin>" -e --path .`
- Lancer le projet (scène principale) : `& "<chemin>" --path .`
- Lancer une scène précise : `& "<chemin>" --path . --scene jeu/ma_scene.tscn`
  (le flag `--scene` est obligatoire — un chemin de scène passé en simple
  argument positionnel est silencieusement ignoré, Godot retombe sur
  `run/main_scene` sans erreur ni avertissement)
- Lancer un seul test : `& "<chemin>" --headless --script jeu/test_xxx.gd`

Lors d'une édition manuelle de fichiers `.tscn` ou `.tres`, préserver la version de format existante (`format=3`) et les références `uid://` — le système d'UID de Godot relie scènes et ressources par ces identifiants, et un décalage casse les références silencieusement jusqu'au réimport.

Les fichiers sont normalisés en fins de ligne LF via `.gitattributes` (`* text=auto eol=lf`).
