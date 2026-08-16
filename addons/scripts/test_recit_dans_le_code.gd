extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_recit_dans_le_code.gd
#
# CLIQUET SUR LE RECIT, dans les COMMENTAIRES de scripts/*.gd et dans les CLES
# DE NOTE de data/*.json. Fait respecter, pour le CODE ET LES DONNEES, la
# premiere des cinq questions de CLAUDE.md (« La doc ne croit pas plus vite que
# le code ») : un commentaire dit ce qui EST, jamais ce qui S'EST PASSE. Cette
# question ne visait jusqu'ici que les .md ; rien ne la tenait dans un .gd ni
# dans un .json, et le compte total de ce fichier mesure exactement ce que
# cette absence a laisse passer.
#
# POURQUOI LES DEUX DANS UN SEUL TEST : c'est UNE question, celle du recit.
# Deux fichiers auraient porte deux registres, deux calibrations et deux
# occasions de diverger.
#
# CE QUE CE TEST N'EST PAS : un interdit d'ecrire. Il ne juge aucune phrase et
# ne sait pas lire. Il COMPTE des marqueurs et compare au compte enregistre
# ci-dessous, fichier par fichier. Le compte ne peut que DESCENDRE : c'est tout
# le mecanisme.
#
# TROIS REPONSES A UN ROUGE, aucune autre :
#   - compte REEL SUPERIEUR : du recit vient d'etre ajoute. Le retirer, ou
#     monter le compte ICI dans le MEME commit -- ce qui rend l'ajout visible
#     dans le diff au lieu de le laisser passer en silence.
#   - compte REEL INFERIEUR : du recit vient d'etre retire. Baisser le compte
#     ICI dans le MEME commit. Le cliquet se resserre d'un cran, definitivement.
#   - fichier ABSENT du registre et porteur d'au moins un marqueur : un fichier
#     neuf naît a zero. Le mettre a zero est la seule reponse ; l'inscrire au
#     registre est une derogation, elle se demande.
#
# CE QUI EST COMPTE : la liste vit dans MOTIFS (plus bas) et nulle part
# ailleurs -- la recopier ici la ferait diverger, et surtout la ferait compter
# elle-meme. Elle n'est lue que dans la PROSE : les lignes de commentaire d'un
# .gd (^ #), les lignes portant une cle de note d'un .json (MOTIF_CLE_NOTE).
# Jamais dans le code ni dans une valeur de donnee, ou un nom de champ peut
# legitimement porter le meme mot.
#
# CE QUI N'EST PAS COMPTE, et c'est deliberé : un RESULTAT NEGATIF (essaye,
# echoue, pourquoi) et un ECARTE DOCTRINAL (rejete, pourquoi). CLAUDE.md les
# garde explicitement -- ce sont les deux seules formes de passe qui changent
# une decision future.
#
# Entree : aucune -- lit scripts/*.gd et data/*.json sur le disque. Sortie :
# "OK:" / exit 0 si chaque fichier porte EXACTEMENT son compte ; "ECHEC:" /
# exit 1 en nommant chaque ecart, son sens, et la ligne de registre a coller,
# sinon.

const Verif = preload("res://scripts/verif.gd")

const DOSSIER_CODE := "res://scripts"
const DOSSIER_DONNEES := "res://data"

# Une ligne de .json compte comme prose si elle porte une cle de note. Le motif
# tolere les prefixes et suffixes (`_note`, `_note_experimentable`) : c'est la
# convention reelle du depot, pas une forme imposee.
const MOTIF_CLE_NOTE := "\"[a-z_]*(note|commentaire|pourquoi|description|remarque)[a-z_]*\"[ \\t]*:"

# Motifs de recit, en minuscules (le texte est abaisse avant comparaison).
# Les deux formes -- accentuee et non accentuee -- sont listees : les .gd du
# depot commentent sans accent par convention, les .md avec.
const MOTIFS := [
	# "chantier" a DEUX sens dans ce depot et un seul est du recit : le LOT DE
	# TRAVAIL qu'on nomme (chantier "feu -- inflammabilite effective", "ce
	# chantier") d'un cote, la CHOSE DU MONDE qu'on travaille de l'autre (une
	# chose qui porte un chantier, travail_restant, colon_chantier). Mesure
	# faite avant de retenir ces deux motifs : sur 1453 occurrences dans la
	# prose du depot, 625 sont le sens DOMAINE. Compter le mot nu poussait a
	# supprimer du vocabulaire legitime pour faire baisser un compte.
	"chantier [\"«]",
	"ce chantier",
	"session ulterieure",
	"session ultérieure",
	"avant ce ",
	"apres ce ",
	"après ce ",
	"aucune regression",
	"aucune régression",
	"non-regression",
	"bug ferme",
	"bug fermé",
	"defaut ferme",
	"défaut fermé",
	"dette fermee",
	"dette fermée",
	# Le PARTICIPE seul est du recit (« corrige », « corrigee ») ; l'INFINITIF
	# ne l'est pas -- « signaler, pas corriger » est une regle, pas une
	# histoire. La sentinelle exclut donc toute lettre qui suivrait.
	"corrig[eé]e?s?(?![a-z])",
	"audit_",
	"[0-9]{4}-[0-9]{2}-[0-9]{2}",
	"phase [0-9]",
	"trouve en lancant",
	"trouvé en lançant",
	"trouve en ecrivant",
	"trouvé en écrivant",
]

# Chemin -> nombre de marqueurs tolerés. Un fichier absent d'ici doit en porter
# ZERO. Ce registre ne s'ajoute pas : il se vide.
const COMPTES := {
	"res://data/banc_activation_neutronique.json": 1,
	"res://data/banc_affordances_choix.json": 3,
	"res://data/banc_affordances_connaissance.json": 5,
	"res://data/banc_affordances_portage.json": 2,
	"res://data/banc_affordances_travail.json": 2,
	"res://data/banc_bonheur.json": 2,
	"res://data/banc_chaine_reactions.json": 1,
	"res://data/banc_champ.json": 1,
	"res://data/banc_changement_etat.json": 1,
	"res://data/banc_charge.json": 1,
	"res://data/banc_choc_magique.json": 1,
	"res://data/banc_combustible.json": 2,
	"res://data/banc_corrosion.json": 2,
	"res://data/banc_cratere.json": 1,
	"res://data/banc_croissance.json": 1,
	"res://data/banc_croyance.json": 3,
	"res://data/banc_deformation.json": 1,
	"res://data/banc_dilatation.json": 1,
	"res://data/banc_economie.json": 2,
	"res://data/banc_ecosysteme_terrain.json": 3,
	"res://data/banc_elimination_salete.json": 5,
	"res://data/banc_faim_thermo.json": 4,
	"res://data/banc_fatigue_circadien.json": 3,
	"res://data/banc_foudre.json": 1,
	"res://data/banc_friction.json": 1,
	"res://data/banc_graisse_accoutumance.json": 5,
	"res://data/banc_grief.json": 4,
	"res://data/banc_hygiene_apparence.json": 2,
	"res://data/banc_infrastructure.json": 2,
	"res://data/banc_lien_personnel.json": 8,
	"res://data/banc_maladie.json": 2,
	"res://data/banc_marche_competence.json": 2,
	"res://data/banc_memoire_navigation.json": 2,
	"res://data/banc_menace_combat.json": 4,
	"res://data/banc_nutrition.json": 2,
	"res://data/banc_ombre_pluvio.json": 1,
	"res://data/banc_oubli_consolidation.json": 2,
	"res://data/banc_parasites_reproduction.json": 3,
	"res://data/banc_permeabilite.json": 2,
	"res://data/banc_porosite.json": 1,
	"res://data/banc_predation.json": 3,
	"res://data/banc_produit_nucleaire.json": 2,
	"res://data/banc_psycho_social.json": 3,
	"res://data/banc_radiation.json": 2,
	"res://data/banc_reactivite.json": 1,
	"res://data/banc_reflectivite.json": 2,
	"res://data/banc_simulation_acceleree.json": 1,
	"res://data/banc_social_foule.json": 2,
	"res://data/banc_social_information.json": 1,
	"res://data/banc_social_paire.json": 3,
	"res://data/banc_social_rupture.json": 3,
	"res://data/banc_solubilite.json": 2,
	"res://data/banc_son.json": 1,
	"res://data/banc_sorts.json": 2,
	"res://data/banc_soudure.json": 1,
	"res://data/banc_stress_thermo_vivant.json": 4,
	"res://data/banc_temps_anticipation.json": 2,
	"res://data/banc_transformation_produit.json": 1,
	"res://data/banc_vecu_inter_colon.json": 1,
	"res://data/banc_velocite.json": 0,
	"res://data/biomes.json": 3,
	"res://data/canaux.json": 7,
	"res://data/comptages.json": 1,
	"res://data/croyances.json": 2,
	"res://data/deformations.json": 5,
	"res://data/epigenetique.json": 7,
	"res://data/etats.json": 27,
	"res://data/heredite.json": 3,
	"res://data/intensite_propagation.json": 4,
	"res://data/materiaux.json": 53,
	"res://data/memoire_spatiale.json": 2,
	"res://data/proprietes_immuables_composition.json": 1,
	"res://data/reactions.json": 2,
	"res://data/reproduction.json": 1,
	"res://data/senescence.json": 1,
	"res://data/seuils_combustible.json": 6,
	"res://data/seuils_etat.json": 8,
	"res://data/sorts.json": 2,
	"res://data/soudure.json": 2,
	"res://data/textes.json": 4,
	"res://data/transformations.json": 18,
	"res://data/types.json": 16,
	"res://scripts/agir.gd": 10,
	"res://scripts/attache_par_trait.gd": 4,
	"res://scripts/attaches.gd": 1,
	"res://scripts/banc_absorption_sonore.gd": 1,
	"res://scripts/banc_acide.gd": 2,
	"res://scripts/banc_activation_neutronique.gd": 1,
	"res://scripts/banc_affordances_choix.gd": 1,
	"res://scripts/banc_affordances_connaissance.gd": 8,
	"res://scripts/banc_affordances_portage.gd": 2,
	"res://scripts/banc_affordances_travail.gd": 3,
	"res://scripts/banc_animal.gd": 3,
	"res://scripts/banc_biomes.gd": 1,
	"res://scripts/banc_bonheur.gd": 6,
	"res://scripts/banc_chaine_reactions.gd": 1,
	"res://scripts/banc_chaleur_emise.gd": 3,
	"res://scripts/banc_changement_etat.gd": 4,
	"res://scripts/banc_charge.gd": 9,
	"res://scripts/banc_choc_magique.gd": 4,
	"res://scripts/banc_combustible.gd": 3,
	"res://scripts/banc_commun.gd": 5,
	"res://scripts/banc_conduction.gd": 10,
	"res://scripts/banc_contagion.gd": 1,
	"res://scripts/banc_controle.gd": 1,
	"res://scripts/banc_convergence_attache.gd": 3,
	"res://scripts/banc_corrosion.gd": 13,
	"res://scripts/banc_coupe.gd": 8,
	"res://scripts/banc_cratere.gd": 2,
	"res://scripts/banc_croissance.gd": 3,
	"res://scripts/banc_croyance.gd": 3,
	"res://scripts/banc_deformation.gd": 4,
	"res://scripts/banc_dilatation.gd": 3,
	"res://scripts/banc_economie.gd": 5,
	"res://scripts/banc_ecosysteme_terrain.gd": 2,
	"res://scripts/banc_ecoulement.gd": 2,
	"res://scripts/banc_elasticite.gd": 4,
	"res://scripts/banc_elimination_salete.gd": 4,
	"res://scripts/banc_emergences.gd": 1,
	"res://scripts/banc_emission.gd": 1,
	"res://scripts/banc_erosion.gd": 3,
	"res://scripts/banc_etat_duree.gd": 2,
	"res://scripts/banc_faim_thermo.gd": 4,
	"res://scripts/banc_fatigue_circadien.gd": 4,
	"res://scripts/banc_fertilite.gd": 5,
	"res://scripts/banc_feu.gd": 12,
	"res://scripts/banc_foudre.gd": 5,
	"res://scripts/banc_fracture.gd": 8,
	"res://scripts/banc_fracture_sonore.gd": 2,
	"res://scripts/banc_friction.gd": 3,
	"res://scripts/banc_genetique.gd": 8,
	"res://scripts/banc_graisse_accoutumance.gd": 5,
	"res://scripts/banc_grief.gd": 2,
	"res://scripts/banc_humidite.gd": 9,
	"res://scripts/banc_hygiene_apparence.gd": 3,
	"res://scripts/banc_inflammabilite.gd": 2,
	"res://scripts/banc_infrastructure.gd": 4,
	"res://scripts/banc_lien_personnel.gd": 4,
	"res://scripts/banc_magie_perception.gd": 5,
	"res://scripts/banc_maladie.gd": 2,
	"res://scripts/banc_mana_conduction.gd": 3,
	"res://scripts/banc_manger.gd": 5,
	"res://scripts/banc_marche_competence.gd": 4,
	"res://scripts/banc_memoire_navigation.gd": 4,
	"res://scripts/banc_menace_combat.gd": 5,
	"res://scripts/banc_nutrition.gd": 3,
	"res://scripts/banc_occlusion.gd": 2,
	"res://scripts/banc_ombre_pluvio.gd": 3,
	"res://scripts/banc_oubli_consolidation.gd": 4,
	"res://scripts/banc_p1.gd": 18,
	"res://scripts/banc_parasites_reproduction.gd": 6,
	"res://scripts/banc_permeabilite.gd": 5,
	"res://scripts/banc_photodegradation.gd": 1,
	"res://scripts/banc_point_ignition.gd": 4,
	"res://scripts/banc_porosite.gd": 2,
	"res://scripts/banc_pourriture.gd": 7,
	"res://scripts/banc_predation.gd": 1,
	"res://scripts/banc_produit_nucleaire.gd": 3,
	"res://scripts/banc_psycho_social.gd": 1,
	"res://scripts/banc_radiation.gd": 4,
	"res://scripts/banc_reactivite.gd": 13,
	"res://scripts/banc_reflectivite.gd": 3,
	"res://scripts/banc_reproduction.gd": 1,
	"res://scripts/banc_resonance.gd": 2,
	"res://scripts/banc_restitution.gd": 4,
	"res://scripts/banc_rigidite.gd": 3,
	"res://scripts/banc_simulation_acceleree.gd": 4,
	"res://scripts/banc_social_foule.gd": 0,
	"res://scripts/banc_social_information.gd": 1,
	"res://scripts/banc_social_paire.gd": 8,
	"res://scripts/banc_social_rupture.gd": 3,
	"res://scripts/banc_solubilite.gd": 5,
	"res://scripts/banc_son.gd": 4,
	"res://scripts/banc_sorts.gd": 2,
	"res://scripts/banc_soudure.gd": 7,
	"res://scripts/banc_stress_thermo_vivant.gd": 4,
	"res://scripts/banc_succession.gd": 1,
	"res://scripts/banc_temperature.gd": 1,
	"res://scripts/banc_temps_anticipation.gd": 5,
	"res://scripts/banc_toxicite.gd": 5,
	"res://scripts/banc_traction.gd": 2,
	"res://scripts/banc_transformation_produit.gd": 2,
	"res://scripts/banc_usinabilite.gd": 4,
	"res://scripts/banc_vecu_inter_colon.gd": 7,
	"res://scripts/banc_vent.gd": 1,
	"res://scripts/bifurcation.gd": 1,
	"res://scripts/boucle.gd": 1,
	"res://scripts/champ.gd": 2,
	"res://scripts/champ_occulte.gd": 2,
	"res://scripts/charge.gd": 1,
	"res://scripts/combustible.gd": 1,
	"res://scripts/conditions.gd": 2,
	"res://scripts/consommer.gd": 5,
	"res://scripts/couplage.gd": 2,
	"res://scripts/croyance.gd": 3,
	"res://scripts/deformation.gd": 7,
	"res://scripts/depense.gd": 0,
	"res://scripts/ecoulement.gd": 3,
	"res://scripts/epigenetique.gd": 2,
	"res://scripts/etat_duree.gd": 4,
	"res://scripts/expression.gd": 5,
	"res://scripts/extinction.gd": 3,
	"res://scripts/frappe.gd": 2,
	"res://scripts/gestation.gd": 1,
	"res://scripts/heredite.gd": 2,
	"res://scripts/jugement.gd": 2,
	"res://scripts/lanceur.gd": 1,
	"res://scripts/lien_personnel.gd": 4,
	"res://scripts/lien_personnel_croissance.gd": 4,
	"res://scripts/lien_personnel_saillance.gd": 2,
	"res://scripts/lumiere.gd": 3,
	"res://scripts/memoire_spatiale.gd": 1,
	"res://scripts/monde.gd": 1,
	"res://scripts/objet.gd": 16,
	"res://scripts/occlusion.gd": 1,
	"res://scripts/portee.gd": 0,
	"res://scripts/produit.gd": 1,
	"res://scripts/propagation.gd": 2,
	"res://scripts/proximite.gd": 2,
	"res://scripts/quantite_matiere.gd": 4,
	"res://scripts/reaction.gd": 2,
	"res://scripts/senescence.gd": 6,
	"res://scripts/seuil_etat.gd": 6,
	"res://scripts/somme.gd": 0,
	"res://scripts/soudure.gd": 4,
	"res://scripts/temperature.gd": 7,
	"res://scripts/test_agir.gd": 1,
	"res://scripts/test_agir_proximite.gd": 1,
	"res://scripts/test_attache_par_trait.gd": 3,
	"res://scripts/test_attaches_deformation.gd": 1,
	"res://scripts/test_banc_acide.gd": 1,
	"res://scripts/test_banc_activation_neutronique.gd": 1,
	"res://scripts/test_banc_affordances_choix.gd": 2,
	"res://scripts/test_banc_affordances_connaissance.gd": 6,
	"res://scripts/test_banc_affordances_travail.gd": 1,
	"res://scripts/test_banc_animal.gd": 3,
	"res://scripts/test_banc_biomes.gd": 1,
	"res://scripts/test_banc_bonheur.gd": 3,
	"res://scripts/test_banc_chaleur_emise.gd": 2,
	"res://scripts/test_banc_champ.gd": 1,
	"res://scripts/test_banc_charge.gd": 8,
	"res://scripts/test_banc_choc_magique.gd": 2,
	"res://scripts/test_banc_combustible.gd": 4,
	"res://scripts/test_banc_commun.gd": 2,
	"res://scripts/test_banc_conduction.gd": 2,
	"res://scripts/test_banc_contagion.gd": 1,
	"res://scripts/test_banc_controle.gd": 3,
	"res://scripts/test_banc_corrosion.gd": 3,
	"res://scripts/test_banc_coupe.gd": 2,
	"res://scripts/test_banc_croissance.gd": 2,
	"res://scripts/test_banc_croyance.gd": 3,
	"res://scripts/test_banc_deformation.gd": 4,
	"res://scripts/test_banc_dilatation.gd": 1,
	"res://scripts/test_banc_ecosysteme_terrain.gd": 3,
	"res://scripts/test_banc_elasticite.gd": 1,
	"res://scripts/test_banc_elimination_salete.gd": 1,
	"res://scripts/test_banc_emergences.gd": 1,
	"res://scripts/test_banc_emission.gd": 1,
	"res://scripts/test_banc_erosion.gd": 1,
	"res://scripts/test_banc_etat_duree.gd": 1,
	"res://scripts/test_banc_etat_effectif.gd": 1,
	"res://scripts/test_banc_faim_thermo.gd": 2,
	"res://scripts/test_banc_fatigue_circadien.gd": 2,
	"res://scripts/test_banc_feu.gd": 5,
	"res://scripts/test_banc_foudre.gd": 3,
	"res://scripts/test_banc_fracture.gd": 1,
	"res://scripts/test_banc_fracture_sonore.gd": 2,
	"res://scripts/test_banc_friction.gd": 1,
	"res://scripts/test_banc_genetique.gd": 2,
	"res://scripts/test_banc_graisse_accoutumance.gd": 3,
	"res://scripts/test_banc_grief.gd": 2,
	"res://scripts/test_banc_humidite.gd": 3,
	"res://scripts/test_banc_hygiene_apparence.gd": 3,
	"res://scripts/test_banc_inflammabilite.gd": 1,
	"res://scripts/test_banc_infrastructure.gd": 1,
	"res://scripts/test_banc_lien_personnel.gd": 5,
	"res://scripts/test_banc_lumiere.gd": 1,
	"res://scripts/test_banc_magie_perception.gd": 9,
	"res://scripts/test_banc_mana_conduction.gd": 2,
	"res://scripts/test_banc_manger.gd": 2,
	"res://scripts/test_banc_marche_competence.gd": 2,
	"res://scripts/test_banc_occlusion.gd": 1,
	"res://scripts/test_banc_oubli_consolidation.gd": 3,
	"res://scripts/test_banc_p1.gd": 23,
	"res://scripts/test_banc_parasites_reproduction.gd": 2,
	"res://scripts/test_banc_permeabilite.gd": 2,
	"res://scripts/test_banc_photodegradation.gd": 1,
	"res://scripts/test_banc_porosite.gd": 5,
	"res://scripts/test_banc_pourriture.gd": 1,
	"res://scripts/test_banc_predation.gd": 1,
	"res://scripts/test_banc_produit_nucleaire.gd": 2,
	"res://scripts/test_banc_psycho_social.gd": 6,
	"res://scripts/test_banc_radiation.gd": 2,
	"res://scripts/test_banc_reactivite.gd": 2,
	"res://scripts/test_banc_reproduction.gd": 1,
	"res://scripts/test_banc_resonance.gd": 2,
	"res://scripts/test_banc_restitution.gd": 1,
	"res://scripts/test_banc_rigidite.gd": 1,
	"res://scripts/test_banc_simulation_acceleree.gd": 3,
	"res://scripts/test_banc_social_foule.gd": 2,
	"res://scripts/test_banc_social_information.gd": 3,
	"res://scripts/test_banc_social_paire.gd": 7,
	"res://scripts/test_banc_social_rupture.gd": 3,
	"res://scripts/test_banc_solubilite.gd": 1,
	"res://scripts/test_banc_son.gd": 5,
	"res://scripts/test_banc_sorts.gd": 3,
	"res://scripts/test_banc_soudure.gd": 4,
	"res://scripts/test_banc_stress_thermo_vivant.gd": 4,
	"res://scripts/test_banc_temps_anticipation.gd": 2,
	"res://scripts/test_banc_toxicite.gd": 2,
	"res://scripts/test_banc_transformation_produit.gd": 1,
	"res://scripts/test_banc_usinabilite.gd": 1,
	"res://scripts/test_banc_vecu_inter_colon.gd": 2,
	"res://scripts/test_banc_vent.gd": 1,
	"res://scripts/test_bifurcation.gd": 2,
	"res://scripts/test_champ.gd": 1,
	"res://scripts/test_champ_occulte.gd": 1,
	"res://scripts/test_ciblage.gd": 2,
	"res://scripts/test_conditions.gd": 1,
	"res://scripts/test_consommer.gd": 1,
	"res://scripts/test_deformation.gd": 2,
	"res://scripts/test_densite_effective.gd": 7,
	"res://scripts/test_depense.gd": 2,
	"res://scripts/test_docs.gd": 1,
	"res://scripts/test_emergences.gd": 1,
	"res://scripts/test_expression.gd": 1,
	"res://scripts/test_extinction.gd": 2,
	"res://scripts/test_fin_chantier.gd": 5,
	"res://scripts/test_fondations_humidite.gd": 1,
	"res://scripts/test_frappe.gd": 2,
	"res://scripts/test_horloge.gd": 1,
	"res://scripts/test_jugement_deformation.gd": 5,
	"res://scripts/test_lien_personnel_croissance.gd": 2,
	"res://scripts/test_lint_donnees.gd": 1,
	"res://scripts/test_lumiere.gd": 1,
	"res://scripts/test_monde.gd": 1,
	"res://scripts/test_objet.gd": 2,
	"res://scripts/test_occlusion.gd": 1,
	"res://scripts/test_perception.gd": 15,
	"res://scripts/test_portee.gd": 1,
	"res://scripts/test_propagation.gd": 7,
	"res://scripts/test_proximite.gd": 1,
	"res://scripts/test_proximite_deformation.gd": 6,
	"res://scripts/test_recit_dans_le_code.gd": 3,
	"res://scripts/test_registre_banc_commun.gd": 1,
	"res://scripts/test_senescence.gd": 3,
	"res://scripts/test_seuil_etat.gd": 3,
	"res://scripts/test_soudure.gd": 2,
	"res://scripts/test_temperature.gd": 6,
	"res://scripts/test_vent.gd": 1,
	"res://scripts/usure_attache.gd": 1,
	"res://scripts/velocite.gd": 3,
	"res://scripts/vent.gd": 2,
	"res://scripts/verif.gd": 1,
}

var verif := Verif.new()
var _cle_note := RegEx.new()

func _init() -> void:
	if _cle_note.compile(MOTIF_CLE_NOTE) != OK:
		print("ECHEC: motif de cle de note illisible")
		quit(1)
		return

	var chemins := _lister_cibles()
	if chemins.is_empty():
		print("ECHEC: aucun scripts/*.gd ni data/*.json trouve -- le test ne mesure rien")
		quit(1)
		return

	var motifs := _compiler_motifs()
	var a_coller: Array = []
	var total_reel := 0

	for chemin in chemins:
		var reel := _compter_marqueurs(chemin, motifs)
		total_reel += reel
		var attendu: int = COMPTES.get(chemin, 0)
		if reel == attendu:
			continue
		if not COMPTES.has(chemin):
			verif.v(false, "%s porte %d marqueur(s) de recit et n'est pas au registre -- un fichier neuf naît a zero" % [chemin, reel])
		elif reel > attendu:
			verif.v(false, "%s porte %d marqueur(s) pour %d enregistre(s) -- retirer le recit ajoute, ou monter le compte dans le MEME commit" % [chemin, reel, attendu])
		else:
			verif.v(false, "%s porte %d marqueur(s) pour %d enregistre(s) -- baisser le compte a %d dans le MEME commit, le cliquet se resserre" % [chemin, reel, attendu, reel])
		a_coller.append("\t\"%s\": %d," % [chemin, reel])

	if verif.echecs() > 0:
		print("--- registre a coller dans COMPTES (%d entree(s)) ---" % a_coller.size())
		for ligne in a_coller:
			print(ligne)
		print("ECHEC: %d fichier(s) hors de leur compte de recit" % verif.echecs())
		quit(1)
		return

	print("OK: les %d fichiers de scripts/ et data/ portent exactement leur compte de recit enregistre (%d marqueur(s) au total, un compte qui ne peut que descendre)" % [chemins.size(), total_reel])
	quit(0)

# Rend les chemins res:// de tous les .gd et de tous les .json, tries --
# l'ordre du systeme de fichiers ne doit jamais changer la sortie du test.
func _lister_cibles() -> Array:
	var chemins: Array = []
	for nom in DirAccess.get_files_at(DOSSIER_CODE):
		if nom.ends_with(".gd"):
			chemins.append("%s/%s" % [DOSSIER_CODE, nom])
	for nom in DirAccess.get_files_at(DOSSIER_DONNEES):
		if nom.ends_with(".json"):
			chemins.append("%s/%s" % [DOSSIER_DONNEES, nom])
	chemins.sort()
	return chemins

# Vrai si la ligne est de la PROSE : un commentaire de .gd, ou une ligne de
# .json portant une cle de note. Le contrat est le meme des deux cotes -- ce
# que le fichier raconte, jamais ce qu'il fait.
func _est_prose(ligne: String, chemin: String) -> bool:
	if chemin.ends_with(".gd"):
		return ligne.strip_edges().begins_with("#")
	return _cle_note.search(ligne) != null

func _compiler_motifs() -> Array:
	var compiles: Array = []
	for motif in MOTIFS:
		var re := RegEx.new()
		if re.compile(motif) != OK:
			push_error("test_recit_dans_le_code.gd : motif illisible '%s'" % motif)
			continue
		compiles.append(re)
	return compiles

# Compte les occurrences de motifs dans les seules lignes de PROSE.
# Un fichier illisible compte zero et alarme : mieux vaut un trou signale
# qu'un vert obtenu par une lecture ratee.
func _compter_marqueurs(chemin: String, motifs: Array) -> int:
	var texte := FileAccess.get_file_as_string(chemin)
	if texte.is_empty():
		push_error("test_recit_dans_le_code.gd : %s illisible ou vide" % chemin)
		return 0
	var total := 0
	for ligne in texte.split("\n"):
		if _est_prose(ligne, chemin):
			var bas := ligne.to_lower()
			for re in motifs:
				total += re.search_all(bas).size()
	return total
