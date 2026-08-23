# SESSION SUIVANTE

Document de passation, NON permanent. À lire une fois au début de la
prochaine session Claude, puis à mettre à jour ou supprimer.

## État à la fin de la session 2026-08-22

### Ce qui tourne dans `test_ennemi2 Mother box.tscn`

- **Géniteur v2** (`geniteur_v2.gd/.tscn`) : copie du géniteur sans
  la gestation mother cube. Deux stocks : `capacite_privee` (violet,
  150) et `capacite_public` (bleu, 150). Extraction 50/50. Se déplace
  au sol vers case marron quand ses 9 cases sont vides.
- **Gestation générateur** sur stock PUBLIC (`gestation_generateur_public.gd`) :
  seuil 15 (10 %), coût 15, max 8 vivants, durée 60 s, rayon 6-8 m.
- **Gestation stockeur** sur stock PRIVÉ (`gestation_stockeur.gd`) :
  seuil 30 (20 %), coût 30, max 4 vivants, durée 60 s, rayon 6-8 m.
- **Générateur d'énergie** (`generateur_energie.gd`) : puise sur toute
  source qui expose `stock_puisable > 0` (géniteur, cadavres, plus tard
  protogéniteur). Pond un carré rouge derrière lui après cumul 10 stock
  + 60 s d'attente. Mort naturelle 5 min → cadavre 5 min (`vie_cadavre =
  7`, `stock_cadavre_initial = 10`, `duree_decomposition_cadavre = 300`).
  Cadavre pourrit auto si non consommé. Fix 2026-08-22 : source morte
  après cout_paye → transition ETAT_POND au lieu d'ETAT_ATTENTE (évite
  la boucle silencieuse « géniteur touche, repart, revient »).
- **Carré rouge** (`carre_rouge.gd`) : nourriture 5, vie 5, pourrit après
  `duree_pourriture = 600` s (10 min).
- **Stockeur** (`stockeur.gd/.tscn`) : cube orange, vie 3, vie 20 min,
  capacité 100. Chasse carrés rouges dans 30 m via perception. Absorbe
  au contact (frappe one-shot). Patrouille vers géniteur si carré rouge
  hors perception (rayon 50 m). Une fois plein → suit géniteur à 10 m.
  Exceptions collision avec géniteur, générateurs, cadavres, autres
  stockeurs, protogéniteurs.
- **Accélérateur** (`controle_vitesse.gd`) : touches `+`/`-` × 2, `0`
  reset, plafond ×10.

### Ce qui est écrit mais NON branché dans la scène

- **Protogéniteur** (`protogeniteur.gd/.tscn`) : cube bleu 3×3×3
  (moitié du géniteur), RigidBody3D masse 15, vie 5, 20 min de vie,
  capacité `_stock_public` 100, auto-production 2/s. Suit géniteur à
  60 m. Expose `stock_public_courant()` + `preleve_stock_public()`.
- **Gestation protogéniteur** (`gestation_protogeniteur.gd`) : seuil 120
  (80 % privé), coût 120, max 3, durée 240 s (4 min), rayon 8-12 m.
- Le nœud `GestationProtogeniteur` n'est PAS instancié dans
  `geniteur_v2.tscn`. Pour activer : ajouter les 2 lignes ext_resource
  + child node dans le tscn (patron déjà appliqué pour `GestationStockeur`,
  copier).

### V1 en stock

- `geniteur.gd`, `geniteur.tscn`, `gestation_mother_cube.gd`,
  `mother_cube.gd`, `mother_cube.tscn` : intacts sur disque, réutilisables
  quand la mother cube redeviendra un chantier.

### Où on s'est arrêté

Yael sent qu'il y a un « truc » avec la boucle actuelle (extraction →
générateurs → carrés rouges → stockeurs qui collectent + cadavres qui
pourrissent). Décision partagée : ne pas ajouter le protogéniteur tout
de suite, laisser tourner l'existant en accéléré ×10 pour voir ce qui
émerge, et éventuellement ajouter d'abord un CONSOMMATEUR FINAL du
stockeur (Yael a mentionné un **guerrier** qui puiserait dans le stockeur
pour aller attaquer le joueur — donne du sens au flux).

### La prochaine étape voulue par Yael

Deux options selon envie :
1. **Combiner avec l'existant** : lancer 15-20 min, observer, laisser
   émerger, décider ensuite.
2. **Ajouter le guerrier** : fermer la boucle (stockeur → guerrier →
   joueur), permet de VRAIMENT playtester le rythme collecte/consommation
   avant d'empiler d'autres tiers.

Le protogéniteur peut attendre le guerrier — sans consommateur final,
empiler des producteurs supplémentaires ne révèle rien.

## Pièges déjà payés cette session

- Le générateur pousse le géniteur au contact (RigidBody masse 30, non
  freeze, contact_seuil 4 m avec collider 3 m). Fix : exception collision
  au `_ready` du générateur. Patron identique dans le stockeur pour tous
  les copains.
- Le générateur qui mange un cadavre (stock 10 = cout 10) meurt de faim
  au tour suivant si on ne bascule pas en POND anticipée (matiere_cumulee
  reste à 10 sans reset, prochaine puisée demande reste=0 → boucle
  silencieuse). Fix dans `_faire_colle`.
- Le stockeur reste planté après avoir mangé loin du géniteur si aucun
  carré rouge dans son rayon de perception. Fix : `_appliquer_patrouille`
  qui le fait revenir vers géniteur (rayon_patrouille 50 m).
- Hook `require_test.ps1` bloque toute écriture .gd/.tscn tant que
  `test_ecosysteme.gd` headless n'a pas tourné VERT dans les 600 s.
  Relancer avant chaque nouvelle vague d'edits.
- Godot fullscreen borderless ignore `ShowWindow SW_MINIMIZE` — la
  capture d'écran fonctionne quand même en mode « minimisé ».

## Capacité de Claude confirmée cette session

Claude PEUT voir la fenêtre Godot en la capturant en PNG via PowerShell
(`System.Drawing.Bitmap` + `CopyFromScreen`) puis en lisant le PNG avec
l'outil `Read` (multimodal). Les sessions précédentes ont dit à tort
« impossible ». Voir mémoire perso `reference_capture_ecran_godot`.

## Comportement attendu de Claude, prochaine session

Voir mémoire perso `feedback_interdit_preambule_editorial` + les autres
feedbacks Premier Rts. En particulier : couper tout jugement de design,
tout préambule éditorial, toute méta-explication de mes propres défauts.
Rester dans le rôle d'observateur technique (bug, patron, fix, outil).
