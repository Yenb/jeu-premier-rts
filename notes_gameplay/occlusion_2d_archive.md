# Archive — occlusion 2D CPU-side (Intel MOC-style)

Archive au 2026-09-19. L'occlusion 2D est DÉSACTIVÉE dans `dans_cercle`
(`extension_terrain/src/simulation_arbre.cpp`). Le code est conservé dans
`simulation_arbre.cpp` (`passe_occlusion`, `ecrire_volume`,
`test_volume_occulte`, `world_to_pixel`, le buffer 2D et le refill des
bloqueurs) pour réactivation future si besoin — il suffit de décommenter
la ligne `if (passe_occlusion(i)) { dump_raison[i] = 2; return false; }`.

## Concept

Occlusion masquée par un buffer de profondeur 2D en espace écran, calculé
CPU-side (pattern Intel Masked Occlusion Culling). À chaque frame :

1. Sélection des BLOQUEURS candidats depuis la caméra (arbres proches et
   assez hauts, dans le rayon de rendu).
2. Projection de chaque bloqueur dans un buffer 2D (`BUFFER_2D_LARGEUR` ×
   `BUFFER_2D_HAUTEUR`) via `world_to_pixel` ; on écrit la profondeur du
   volume du bloqueur (`ecrire_volume`) — le plus proche gagne par pixel.
3. Test de chaque arbre CANDIDAT (`test_volume_occulte`) : s'il est
   entièrement couvert par des pixels strictement plus proches, il est
   déclaré occulté et retiré du buffer de rendu.

La décision est binaire par slot, stabilisée par une hystérésis temporelle
(persistance N frames avant bascule).

## Paramètres clés

- `seuil_couverture` (0..1) : fraction minimale de pixels de l'empreinte
  d'un candidat qui doivent être strictement plus proches pour l'occulter.
  1.0 = 100 % requis (quasi rien occulté) ; 0.5 = la moitié suffit.
- `marge_profondeur_m` (m) : marge absorbée sur la profondeur ; un pixel
  n'est couvrant que si son buffer est `< depth_min_candidat - marge`.
- `hysteresis_frames` (frames) : nombre de frames consécutives où le verdict
  brut doit tenir avant que l'état affiché ne bascule. Classique : 60.

## Problèmes identifiés cette session

- PROJECTION ANGULAIRE : `world_to_pixel` mappait par `atan2` (angle) au
  lieu de la projection perspective standard tan-based
  (`ndc = view_xy / (view_z · tan(fov/2))`). Corrigé en tan-based ; les deux
  divergent surtout en périphérie de l'image. La correction reste dans le
  code.
- OCCULTEUR INSCRIT AU LIEU DE CIRCONSCRIT : `ecrire_volume` posait le carré
  INSCRIT (`largeur · 0.5 · INV_SQRT2`), sous-couvrant l'AABB du bloqueur →
  pixels manquants au bord → faux « visible ». Corrigé : l'occulteur écrit le
  carré CIRCONSCRIT (`largeur · 0.5`), le candidat (`test_volume_occulte`)
  garde l'inscrit (`INV_SQRT2_TEST`) pour rester conservatif dans l'autre
  sens.
- POP BINAIRE NON LISSÉ : la décision 0/1 par slot produit une
  apparition/disparition franche (« pop ») quand un arbre bascule, visible et
  gênante.
- COUPLAGE OCCLUSION + RENDU : le verdict d'occlusion pilotait directement
  l'inclusion dans le buffer MultiMesh ; difficile de tester l'occlusion en
  isolation du rendu sans découpler les deux (d'où les bancs de test 2 et 3,
  désormais supprimés).

## Tentatives d'amélioration (essayées cette session)

- FONDU SYMÉTRIQUE (`fade_frames`) : rampe continue d'un scalaire par slot
  (0→1) pour lisser le pop. Deux implémentations : d'abord par l'ÉCHELLE de
  l'instance (l'arbre rétrécissait — rejeté, il changeait de taille), puis par
  l'ALPHA de la couleur d'instance + matériau `TRANSPARENCY_ALPHA_HASH`
  (dithered discard, écran de porte moustiquaire) — taille/position/couleur
  intactes, seule la densité de pixels rendus glisse.
- HYSTÉRÉSIS ADAPTATIVE À LA VITESSE CAMÉRA : N descendait de sa valeur de
  repos vers un plancher (`hysteresis_min`) selon la vitesse linéaire/angulaire
  de la caméra (`vitesse_seuil_lin`, `vitesse_seuil_ang`) — filtre réactif en
  mouvement, stable au repos. Retiré au nettoyage (retour à N fixe).
- ANTICIPATION CAMÉRA : projeter la transform caméra en avant pour pré-tester
  l'occlusion sur la position future et masquer le retard en translation.
- ShaderMaterial DITHER : dissolution custom en shader (écarté au profit du
  `TRANSPARENCY_ALPHA_HASH` standard, plus simple, sans shader à maintenir).
- GUARD BAND / marge de garde écran : élargir la zone d'inclusion au-delà du
  cadre pour éviter qu'un arbre juste hors champ soit coupé trop tôt.
- MARGE FRUSTUM (`marge_frustum`) : facteur multiplicatif sur les
  demi-ouvertures du cône radar pour ne pas couper les arbres en bord de champ.
  Distinct de l'occlusion, conservé dans le pipeline distance + frustum actif.

## État final

Pipeline actif : SIM → distance + frustum → MultiMesh. L'occlusion 2D est
coupée. Les @export `seuil_couverture`, `marge_profondeur_m`,
`hysteresis_frames` restent poussés au sim (surcharges JSON préservées) mais
sans effet visible tant que l'occlusion reste désactivée.
