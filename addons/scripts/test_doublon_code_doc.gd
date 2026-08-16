extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_doublon_code_doc.gd
#
# CLIQUET SUR LE DOUBLON ENTRE LA PROSE DU DEPOT ET SES DOCUMENTS -- les
# commentaires de scripts/*.gd et les cles de note de data/*.json d'un cote,
# les .md de l'autre. Fait respecter, entre le CODE, LES DONNEES et les .md, la
# deuxieme des cinq questions de CLAUDE.md (« ce fait est-il deja ecrit
# ailleurs, meme autrement dit ? »). Cette question ne visait jusqu'ici que les
# .md ENTRE EUX ; rien ne la tenait entre un .md et un .gd ni un .json, et
# c'est par la que le contrat d'un mecanisme a fini ecrit deux fois, celui d'un
# banc trois fois.
#
# COMMENT LE DOUBLON EST MESURE, sans jamais lire ni juger une phrase : une
# SUITE de TAILLE_SUITE mots consecutifs partagee entre un commentaire et un
# document n'est pas une coincidence, c'est une recopie. Le test compte, par
# fichier, combien de ses suites se retrouvent telles quelles dans les
# documents. Deux textes qui disent la meme chose AUTREMENT ne sont donc PAS
# comptes -- c'est une limite assumee, dite plutot que masquee : ce test
# attrape la recopie, jamais la paraphrase.
#
# NORMALISATION avant comparaison : minuscules, accents retires, toute
# ponctuation ramenee a une espace. Sans le retrait des accents, rien ne
# matcherait jamais -- les .gd du depot commentent sans accent, les .md avec.
#
# CE QUE CE TEST N'EST PAS : un interdit d'ecrire, et surtout pas un ordre de
# vider les en-tetes. Il ne dit pas OU un fait doit vivre, il dit qu'il ne peut
# pas vivre a deux endroits. Le choix de qui garde se tranche ailleurs.
#
# TROIS REPONSES A UN ROUGE, aucune autre :
#   - compte REEL SUPERIEUR : une recopie vient d'etre faite. La retirer d'un
#     des deux cotes, ou monter le compte ICI dans le MEME commit -- ce qui
#     rend la recopie visible dans le diff au lieu de la laisser passer.
#   - compte REEL INFERIEUR : une recopie vient d'etre retiree. Baisser le
#     compte ICI dans le MEME commit. Le cliquet se resserre d'un cran.
#   - fichier ABSENT du registre et porteur d'au moins une suite partagee : un
#     fichier neuf naît a zero.
#
# LE COMPTE BOUGE QUAND UN DOCUMENT BOUGE, et c'est voulu : retirer de la prose
# d'un .md fait tomber les suites partagees, donc rougir ce test, donc baisser
# le compte. Une purge de document se paie d'une ligne ici -- c'est le prix a
# payer pour que le solde soit visible, jamais un defaut.
#
# SECONDE MESURE, MEME QUESTION : LE DOUBLON D'UN FICHIER DU COEUR A L'AUTRE.
# Celle ci-dessus ne mord que sur la recopie code <-> document ; un fait
# ecrit quatre fois dans quatre mecanismes ne la declenche jamais.
# COMPTES_COEUR porte ce second cliquet, meme regle et meme trois reponses.
#
# PORTEE, MESUREE AVANT D'ETRE CHOISIE -- les .gd qui ne sont ni banc ni
# test. Les bancs en sont exclus : leur recopie mutuelle est doctrinale, et
# la mesure le confirme (2794 suites entre bancs contre 195 dans le coeur),
# un cliquet la punirait. Les tests aussi : deux verrous du meme contrat le
# decrivent legitimement pareil.
#
# Entree : aucune -- lit scripts/*.gd, data/*.json et DOCUMENTS sur le disque.
# Sortie : "OK:" / exit 0 si chaque fichier porte EXACTEMENT ses deux comptes ;
# "ECHEC:" / exit 1 en nommant chaque ecart et la ligne de registre a coller,
# sinon.

const Verif = preload("res://scripts/verif.gd")

const DOSSIER_CODE := "res://scripts"
const DOSSIER_DONNEES := "res://data"

# Meme convention que test_recit_dans_le_code.gd : une ligne de .json est de la
# prose si elle porte une cle de note.
const MOTIF_CLE_NOTE := "\"[a-z_]*(note|commentaire|pourquoi|description|remarque)[a-z_]*\"[ \\t]*:"

# Les documents ou un contrat peut se retrouver recopie. docs/ETAT.md n'y est
# pas : il ne porte qu'une ligne par lot de travail, jamais un contrat.
# CLAUDE.md non plus : il porte des regles de travail, jamais le contrat d'un
# fichier precis.
const DOCUMENTS := [
	"res://CARTE.md",
	"res://docs/prototypes.md",
	"res://docs/design.md",
]

# Longueur d'une suite de mots. A huit mots consecutifs, une collision
# fortuite entre deux textes francais n'arrive pas ; a trois ou quatre, elle
# arriverait a chaque phrase et le test ne mesurerait plus rien.
const TAILLE_SUITE := 8

const ACCENTS := {
	"à": "a", "â": "a", "ä": "a",
	"é": "e", "è": "e", "ê": "e", "ë": "e",
	"î": "i", "ï": "i",
	"ô": "o", "ö": "o",
	"ù": "u", "û": "u", "ü": "u",
	"ç": "c", "œ": "oe", "æ": "ae",
}

# Chemin -> suites recopiees d'un fichier du COEUR a l'autre (seconde mesure,
# voir en-tete). Meme cliquet, meme regle : un fichier absent d'ici doit en
# porter ZERO, et ce registre ne s'ajoute pas.
const COMPTES_COEUR := {
	"res://scripts/accouplement.gd": 48,
	"res://scripts/agir.gd": 20,
	"res://scripts/attache_par_trait.gd": 100,
	"res://scripts/attaches.gd": 78,
	"res://scripts/bifurcation.gd": 14,
	"res://scripts/champ.gd": 11,
	"res://scripts/champ_occulte.gd": 17,
	"res://scripts/charge.gd": 40,
	"res://scripts/ciblage.gd": 12,
	"res://scripts/combustible.gd": 6,
	"res://scripts/comptage.gd": 34,
	"res://scripts/conditions.gd": 6,
	"res://scripts/consommer.gd": 12,
	"res://scripts/couplage.gd": 29,
	"res://scripts/croyance.gd": 28,
	"res://scripts/deformation.gd": 58,
	"res://scripts/depense.gd": 30,
	"res://scripts/dominance.gd": 6,
	"res://scripts/ecoulement.gd": 4,
	"res://scripts/epigenetique.gd": 79,
	"res://scripts/etat_duree.gd": 1,
	"res://scripts/etat_effectif.gd": 13,
	"res://scripts/expression.gd": 25,
	"res://scripts/extinction.gd": 51,
	"res://scripts/flux.gd": 36,
	"res://scripts/frappe.gd": 14,
	"res://scripts/gestation.gd": 74,
	"res://scripts/heredite.gd": 55,
	"res://scripts/horloge.gd": 14,
	"res://scripts/jugement.gd": 82,
	"res://scripts/lien_personnel.gd": 73,
	"res://scripts/lien_personnel_attraction.gd": 60,
	"res://scripts/lien_personnel_croissance.gd": 43,
	"res://scripts/lien_personnel_saillance.gd": 82,
	"res://scripts/lumiere.gd": 53,
	"res://scripts/memoire_spatiale.gd": 29,
	"res://scripts/monde.gd": 6,
	"res://scripts/objet.gd": 14,
	"res://scripts/occlusion.gd": 22,
	"res://scripts/perception.gd": 1,
	"res://scripts/portee.gd": 10,
	"res://scripts/produit.gd": 25,
	"res://scripts/propagation.gd": 23,
	"res://scripts/proximite.gd": 84,
	"res://scripts/quantite_matiere.gd": 3,
	"res://scripts/reaction.gd": 5,
	"res://scripts/senescence.gd": 63,
	"res://scripts/seuil_etat.gd": 13,
	"res://scripts/somme.gd": 35,
	"res://scripts/soudure.gd": 27,
	"res://scripts/stade.gd": 27,
	"res://scripts/temperature.gd": 83,
	"res://scripts/usure_attache.gd": 53,
	"res://scripts/velocite.gd": 4,
	"res://scripts/vent.gd": 42,
}

# Chemin -> nombre de suites partagees tolerées. Un fichier absent d'ici doit
# en porter ZERO. Ce registre ne s'ajoute pas : il se vide.
const COMPTES := {
	"res://data/banc_absorption_sonore.json": 4,
	"res://data/banc_acide.json": 13,
	"res://data/banc_activation_neutronique.json": 4,
	"res://data/banc_affordances_choix.json": 78,
	"res://data/banc_affordances_connaissance.json": 75,
	"res://data/banc_affordances_portage.json": 13,
	"res://data/banc_affordances_travail.json": 14,
	"res://data/banc_biomes.json": 27,
	"res://data/banc_bonheur.json": 55,
	"res://data/banc_chaine_reactions.json": 1,
	"res://data/banc_chaleur_emise.json": 2,
	"res://data/banc_changement_etat.json": 5,
	"res://data/banc_choc_magique.json": 7,
	"res://data/banc_combustible.json": 3,
	"res://data/banc_conduction.json": 12,
	"res://data/banc_convergence_attache.json": 1,
	"res://data/banc_corrosion.json": 7,
	"res://data/banc_coupe.json": 8,
	"res://data/banc_cratere.json": 16,
	"res://data/banc_croissance.json": 2,
	"res://data/banc_croyance.json": 87,
	"res://data/banc_deformation.json": 1,
	"res://data/banc_dilatation.json": 39,
	"res://data/banc_economie.json": 10,
	"res://data/banc_ecosysteme_terrain.json": 38,
	"res://data/banc_ecoulement.json": 8,
	"res://data/banc_elimination_salete.json": 19,
	"res://data/banc_emergences.json": 17,
	"res://data/banc_emission.json": 14,
	"res://data/banc_erosion.json": 5,
	"res://data/banc_etat_duree.json": 5,
	"res://data/banc_etat_effectif.json": 16,
	"res://data/banc_faim_thermo.json": 12,
	"res://data/banc_fatigue_circadien.json": 6,
	"res://data/banc_fertilite.json": 15,
	"res://data/banc_foudre.json": 32,
	"res://data/banc_fracture.json": 8,
	"res://data/banc_fracture_sonore.json": 2,
	"res://data/banc_friction.json": 2,
	"res://data/banc_genetique.json": 12,
	"res://data/banc_grief.json": 22,
	"res://data/banc_humidite.json": 15,
	"res://data/banc_hygiene_apparence.json": 11,
	"res://data/banc_inflammabilite.json": 21,
	"res://data/banc_infrastructure.json": 1,
	"res://data/banc_lumiere.json": 1,
	"res://data/banc_magie_perception.json": 3,
	"res://data/banc_maladie.json": 26,
	"res://data/banc_mana_conduction.json": 4,
	"res://data/banc_manger.json": 3,
	"res://data/banc_marche_competence.json": 13,
	"res://data/banc_memoire_navigation.json": 21,
	"res://data/banc_menace_combat.json": 22,
	"res://data/banc_nutrition.json": 26,
	"res://data/banc_occlusion.json": 1,
	"res://data/banc_ombre_pluvio.json": 25,
	"res://data/banc_oubli_consolidation.json": 20,
	"res://data/banc_parasites_reproduction.json": 33,
	"res://data/banc_photodegradation.json": 17,
	"res://data/banc_point_ignition.json": 2,
	"res://data/banc_porosite.json": 25,
	"res://data/banc_predation.json": 77,
	"res://data/banc_psycho_social.json": 79,
	"res://data/banc_reactivite.json": 1,
	"res://data/banc_reflectivite.json": 11,
	"res://data/banc_reproduction.json": 16,
	"res://data/banc_resonance.json": 4,
	"res://data/banc_rigidite.json": 9,
	"res://data/banc_simulation_acceleree.json": 30,
	"res://data/banc_social_foule.json": 15,
	"res://data/banc_social_information.json": 43,
	"res://data/banc_social_paire.json": 35,
	"res://data/banc_social_rupture.json": 56,
	"res://data/banc_son.json": 4,
	"res://data/banc_sorts.json": 62,
	"res://data/banc_stress_thermo_vivant.json": 41,
	"res://data/banc_succession.json": 5,
	"res://data/banc_temps_anticipation.json": 2,
	"res://data/banc_temps_saisons.json": 19,
	"res://data/banc_temps_vieillissement.json": 8,
	"res://data/banc_traction.json": 17,
	"res://data/banc_transformation_produit.json": 25,
	"res://data/banc_vecu_inter_colon.json": 2,
	"res://data/banc_vent.json": 1,
	"res://data/biomes.json": 8,
	"res://data/canaux.json": 22,
	"res://data/champs.json": 3,
	"res://data/comptages.json": 15,
	"res://data/croyances.json": 23,
	"res://data/deformations.json": 59,
	"res://data/emergences.json": 1,
	"res://data/engagements.json": 8,
	"res://data/epigenetique.json": 51,
	"res://data/etats.json": 203,
	"res://data/genes.json": 1,
	"res://data/heredite.json": 1,
	"res://data/intensite_propagation.json": 2,
	"res://data/lien_personnel_croissance.json": 6,
	"res://data/lumiere.json": 2,
	"res://data/materiaux.json": 72,
	"res://data/profils_saillance.json": 40,
	"res://data/proprietes_immuables_composition.json": 14,
	"res://data/reactions.json": 10,
	"res://data/reproduction.json": 8,
	"res://data/reserve_combustible_composition.json": 8,
	"res://data/senescence.json": 9,
	"res://data/seuils_combustible.json": 18,
	"res://data/seuils_etat.json": 153,
	"res://data/sorts.json": 36,
	"res://data/soudure.json": 9,
	"res://data/textes.json": 45,
	"res://data/transformations.json": 29,
	"res://data/types.json": 52,
	"res://data/usure_attaches.json": 4,
	"res://scripts/accouplement.gd": 34,
	"res://scripts/agir.gd": 27,
	"res://scripts/attache_par_trait.gd": 9,
	"res://scripts/attaches.gd": 29,
	"res://scripts/banc_absorption_sonore.gd": 15,
	"res://scripts/banc_acide.gd": 50,
	"res://scripts/banc_activation_neutronique.gd": 57,
	"res://scripts/banc_affordances_choix.gd": 183,
	"res://scripts/banc_affordances_connaissance.gd": 163,
	"res://scripts/banc_affordances_portage.gd": 104,
	"res://scripts/banc_affordances_travail.gd": 63,
	"res://scripts/banc_animal.gd": 6,
	"res://scripts/banc_biomes.gd": 41,
	"res://scripts/banc_bonheur.gd": 189,
	"res://scripts/banc_chaine_reactions.gd": 13,
	"res://scripts/banc_chaleur_emise.gd": 25,
	"res://scripts/banc_champ.gd": 11,
	"res://scripts/banc_changement_etat.gd": 72,
	"res://scripts/banc_charge.gd": 6,
	"res://scripts/banc_choc_magique.gd": 51,
	"res://scripts/banc_combustible.gd": 17,
	"res://scripts/banc_commun.gd": 2,
	"res://scripts/banc_comptage.gd": 25,
	"res://scripts/banc_conduction.gd": 106,
	"res://scripts/banc_contagion.gd": 37,
	"res://scripts/banc_controle.gd": 27,
	"res://scripts/banc_convergence_attache.gd": 60,
	"res://scripts/banc_corrosion.gd": 89,
	"res://scripts/banc_coupe.gd": 62,
	"res://scripts/banc_cratere.gd": 60,
	"res://scripts/banc_croissance.gd": 17,
	"res://scripts/banc_croyance.gd": 202,
	"res://scripts/banc_deformation.gd": 14,
	"res://scripts/banc_dilatation.gd": 107,
	"res://scripts/banc_economie.gd": 171,
	"res://scripts/banc_ecosysteme_terrain.gd": 239,
	"res://scripts/banc_ecoulement.gd": 12,
	"res://scripts/banc_elasticite.gd": 92,
	"res://scripts/banc_elimination_salete.gd": 41,
	"res://scripts/banc_emergences.gd": 22,
	"res://scripts/banc_emission.gd": 33,
	"res://scripts/banc_erosion.gd": 81,
	"res://scripts/banc_etat_duree.gd": 48,
	"res://scripts/banc_etat_effectif.gd": 34,
	"res://scripts/banc_faim_thermo.gd": 42,
	"res://scripts/banc_fatigue_circadien.gd": 54,
	"res://scripts/banc_fertilite.gd": 99,
	"res://scripts/banc_feu.gd": 12,
	"res://scripts/banc_foudre.gd": 29,
	"res://scripts/banc_fracture.gd": 77,
	"res://scripts/banc_fracture_sonore.gd": 21,
	"res://scripts/banc_friction.gd": 14,
	"res://scripts/banc_genetique.gd": 65,
	"res://scripts/banc_graisse_accoutumance.gd": 70,
	"res://scripts/banc_grief.gd": 143,
	"res://scripts/banc_humidite.gd": 38,
	"res://scripts/banc_hygiene_apparence.gd": 87,
	"res://scripts/banc_inflammabilite.gd": 20,
	"res://scripts/banc_infrastructure.gd": 166,
	"res://scripts/banc_lien_personnel.gd": 75,
	"res://scripts/banc_lumiere.gd": 46,
	"res://scripts/banc_magie_perception.gd": 26,
	"res://scripts/banc_maladie.gd": 4,
	"res://scripts/banc_mana_conduction.gd": 54,
	"res://scripts/banc_manger.gd": 37,
	"res://scripts/banc_marche_competence.gd": 223,
	"res://scripts/banc_memoire_navigation.gd": 84,
	"res://scripts/banc_menace_combat.gd": 160,
	"res://scripts/banc_nutrition.gd": 103,
	"res://scripts/banc_occlusion.gd": 37,
	"res://scripts/banc_ombre_pluvio.gd": 62,
	"res://scripts/banc_oubli_consolidation.gd": 96,
	"res://scripts/banc_p1.gd": 13,
	"res://scripts/banc_parasites_reproduction.gd": 68,
	"res://scripts/banc_permeabilite.gd": 11,
	"res://scripts/banc_photodegradation.gd": 22,
	"res://scripts/banc_point_ignition.gd": 76,
	"res://scripts/banc_porosite.gd": 78,
	"res://scripts/banc_pourriture.gd": 31,
	"res://scripts/banc_predation.gd": 146,
	"res://scripts/banc_produit_nucleaire.gd": 41,
	"res://scripts/banc_psycho_social.gd": 207,
	"res://scripts/banc_radiation.gd": 80,
	"res://scripts/banc_reactivite.gd": 105,
	"res://scripts/banc_reflectivite.gd": 103,
	"res://scripts/banc_reproduction.gd": 29,
	"res://scripts/banc_resonance.gd": 24,
	"res://scripts/banc_restitution.gd": 31,
	"res://scripts/banc_rigidite.gd": 62,
	"res://scripts/banc_simulation_acceleree.gd": 184,
	"res://scripts/banc_social_foule.gd": 167,
	"res://scripts/banc_social_information.gd": 125,
	"res://scripts/banc_social_paire.gd": 388,
	"res://scripts/banc_social_rupture.gd": 154,
	"res://scripts/banc_solubilite.gd": 76,
	"res://scripts/banc_son.gd": 11,
	"res://scripts/banc_sorts.gd": 209,
	"res://scripts/banc_soudure.gd": 24,
	"res://scripts/banc_stress_thermo_vivant.gd": 64,
	"res://scripts/banc_succession.gd": 80,
	"res://scripts/banc_temperature.gd": 61,
	"res://scripts/banc_temps_anticipation.gd": 63,
	"res://scripts/banc_temps_saisons.gd": 13,
	"res://scripts/banc_temps_vieillissement.gd": 18,
	"res://scripts/banc_toxicite.gd": 70,
	"res://scripts/banc_traction.gd": 36,
	"res://scripts/banc_transformation_produit.gd": 64,
	"res://scripts/banc_usinabilite.gd": 15,
	"res://scripts/banc_vecu_inter_colon.gd": 31,
	"res://scripts/banc_velocite.gd": 33,
	"res://scripts/banc_vent.gd": 76,
	"res://scripts/bifurcation.gd": 2,
	"res://scripts/boucle.gd": 15,
	"res://scripts/champ.gd": 14,
	"res://scripts/champ_occulte.gd": 5,
	"res://scripts/charge.gd": 19,
	"res://scripts/ciblage.gd": 4,
	"res://scripts/combustible.gd": 1,
	"res://scripts/comptage.gd": 29,
	"res://scripts/conditions.gd": 11,
	"res://scripts/consommer.gd": 41,
	"res://scripts/couplage.gd": 21,
	"res://scripts/croyance.gd": 153,
	"res://scripts/deformation.gd": 25,
	"res://scripts/depense.gd": 40,
	"res://scripts/ecoulement.gd": 35,
	"res://scripts/epigenetique.gd": 21,
	"res://scripts/etat_duree.gd": 6,
	"res://scripts/etat_effectif.gd": 7,
	"res://scripts/expression.gd": 30,
	"res://scripts/extinction.gd": 22,
	"res://scripts/flux.gd": 7,
	"res://scripts/frappe.gd": 8,
	"res://scripts/fuite.gd": 65,
	"res://scripts/gestation.gd": 11,
	"res://scripts/heredite.gd": 46,
	"res://scripts/horloge.gd": 16,
	"res://scripts/jugement.gd": 28,
	"res://scripts/lanceur.gd": 4,
	"res://scripts/lien_personnel.gd": 8,
	"res://scripts/lien_personnel_attraction.gd": 23,
	"res://scripts/lien_personnel_croissance.gd": 25,
	"res://scripts/lien_personnel_saillance.gd": 8,
	"res://scripts/lumiere.gd": 15,
	"res://scripts/memoire_spatiale.gd": 27,
	"res://scripts/monde.gd": 13,
	"res://scripts/objet.gd": 88,
	"res://scripts/occlusion.gd": 0,
	"res://scripts/perception.gd": 70,
	"res://scripts/portee.gd": 9,
	"res://scripts/produit.gd": 4,
	"res://scripts/propagation.gd": 64,
	"res://scripts/proximite.gd": 15,
	"res://scripts/reaction.gd": 52,
	"res://scripts/senescence.gd": 29,
	"res://scripts/seuil_etat.gd": 2,
	"res://scripts/somme.gd": 28,
	"res://scripts/soudure.gd": 2,
	"res://scripts/stade.gd": 3,
	"res://scripts/temperature.gd": 8,
	"res://scripts/test_agir.gd": 1,
	"res://scripts/test_agir_proximite.gd": 2,
	"res://scripts/test_antiempilement.gd": 4,
	"res://scripts/test_attache_par_trait.gd": 1,
	"res://scripts/test_attaches.gd": 1,
	"res://scripts/test_attaches_deformation.gd": 2,
	"res://scripts/test_banc_absorption_sonore.gd": 7,
	"res://scripts/test_banc_activation_neutronique.gd": 17,
	"res://scripts/test_banc_affordances_choix.gd": 67,
	"res://scripts/test_banc_affordances_connaissance.gd": 6,
	"res://scripts/test_banc_affordances_portage.gd": 17,
	"res://scripts/test_banc_affordances_travail.gd": 10,
	"res://scripts/test_banc_chaine_reactions.gd": 7,
	"res://scripts/test_banc_chaleur_emise.gd": 12,
	"res://scripts/test_banc_charge.gd": 1,
	"res://scripts/test_banc_commun.gd": 1,
	"res://scripts/test_banc_comptage.gd": 1,
	"res://scripts/test_banc_conduction.gd": 10,
	"res://scripts/test_banc_contagion.gd": 1,
	"res://scripts/test_banc_convergence_attache.gd": 3,
	"res://scripts/test_banc_corrosion.gd": 12,
	"res://scripts/test_banc_coupe.gd": 2,
	"res://scripts/test_banc_croissance.gd": 12,
	"res://scripts/test_banc_croyance.gd": 8,
	"res://scripts/test_banc_deformation.gd": 3,
	"res://scripts/test_banc_dilatation.gd": 14,
	"res://scripts/test_banc_economie.gd": 0,
	"res://scripts/test_banc_ecosysteme_terrain.gd": 10,
	"res://scripts/test_banc_faim_thermo.gd": 5,
	"res://scripts/test_banc_fatigue_circadien.gd": 13,
	"res://scripts/test_banc_foudre.gd": 5,
	"res://scripts/test_banc_graisse_accoutumance.gd": 15,
	"res://scripts/test_banc_grief.gd": 8,
	"res://scripts/test_banc_humidite.gd": 8,
	"res://scripts/test_banc_infrastructure.gd": 13,
	"res://scripts/test_banc_lien_personnel.gd": 7,
	"res://scripts/test_banc_lumiere.gd": 2,
	"res://scripts/test_banc_magie_perception.gd": 11,
	"res://scripts/test_banc_mana_conduction.gd": 11,
	"res://scripts/test_banc_manger.gd": 17,
	"res://scripts/test_banc_marche_competence.gd": 17,
	"res://scripts/test_banc_memoire_navigation.gd": 2,
	"res://scripts/test_banc_nutrition.gd": 4,
	"res://scripts/test_banc_occlusion.gd": 11,
	"res://scripts/test_banc_p1.gd": 8,
	"res://scripts/test_banc_parasites_reproduction.gd": 14,
	"res://scripts/test_banc_permeabilite.gd": 5,
	"res://scripts/test_banc_photodegradation.gd": 5,
	"res://scripts/test_banc_porosite.gd": 6,
	"res://scripts/test_banc_pourriture.gd": 12,
	"res://scripts/test_banc_produit_nucleaire.gd": 29,
	"res://scripts/test_banc_psycho_social.gd": 31,
	"res://scripts/test_banc_radiation.gd": 12,
	"res://scripts/test_banc_reactivite.gd": 8,
	"res://scripts/test_banc_reproduction.gd": 6,
	"res://scripts/test_banc_resonance.gd": 9,
	"res://scripts/test_banc_rigidite.gd": 3,
	"res://scripts/test_banc_simulation_acceleree.gd": 4,
	"res://scripts/test_banc_social_foule.gd": 19,
	"res://scripts/test_banc_social_information.gd": 33,
	"res://scripts/test_banc_social_paire.gd": 10,
	"res://scripts/test_banc_social_rupture.gd": 8,
	"res://scripts/test_banc_solubilite.gd": 19,
	"res://scripts/test_banc_son.gd": 3,
	"res://scripts/test_banc_sorts.gd": 20,
	"res://scripts/test_banc_soudure.gd": 7,
	"res://scripts/test_banc_stress_thermo_vivant.gd": 5,
	"res://scripts/test_banc_temps_anticipation.gd": 14,
	"res://scripts/test_banc_temps_vieillissement.gd": 2,
	"res://scripts/test_banc_toxicite.gd": 7,
	"res://scripts/test_banc_transformation_produit.gd": 3,
	"res://scripts/test_champ_occulte.gd": 2,
	"res://scripts/test_charge.gd": 9,
	"res://scripts/test_comptage.gd": 1,
	"res://scripts/test_conditions.gd": 1,
	"res://scripts/test_consommer.gd": 2,
	"res://scripts/test_couverture_index.gd": 3,
	"res://scripts/test_deformation.gd": 2,
	"res://scripts/test_densite_effective.gd": 1,
	"res://scripts/test_depense.gd": 1,
	"res://scripts/test_docs.gd": 1,
	"res://scripts/test_doublon_code_doc.gd": 0,
	"res://scripts/test_emergences.gd": 4,
	"res://scripts/test_flux.gd": 4,
	"res://scripts/test_fondations_humidite.gd": 2,
	"res://scripts/test_fuite.gd": 4,
	"res://scripts/test_gestation.gd": 1,
	"res://scripts/test_horloge.gd": 0,
	"res://scripts/test_jugement.gd": 12,
	"res://scripts/test_jugement_deformation.gd": 4,
	"res://scripts/test_lint_donnees.gd": 8,
	"res://scripts/test_lumiere.gd": 4,
	"res://scripts/test_objet.gd": 10,
	"res://scripts/test_perception.gd": 1,
	"res://scripts/test_portee.gd": 3,
	"res://scripts/test_proximite_deformation.gd": 2,
	"res://scripts/test_pv0b.gd": 2,
	"res://scripts/test_recit_dans_le_code.gd": 5,
	"res://scripts/test_senescence.gd": 1,
	"res://scripts/test_seuil_etat.gd": 1,
	"res://scripts/test_soudure.gd": 0,
	"res://scripts/test_temperature.gd": 12,
	"res://scripts/test_volume_docs.gd": 5,
	"res://scripts/usure_attache.gd": 16,
	"res://scripts/velocite.gd": 12,
	"res://scripts/vent.gd": 3,
	"res://scripts/verif.gd": 13,
}

var verif := Verif.new()
var _nettoyeur := RegEx.new()
var _cle_note := RegEx.new()

func _init() -> void:
	if _nettoyeur.compile("[^a-z0-9]+") != OK or _cle_note.compile(MOTIF_CLE_NOTE) != OK:
		print("ECHEC: motif illisible")
		quit(1)
		return

	var corpus := _suites_des_documents()
	if corpus.is_empty():
		print("ECHEC: aucun document lisible -- le test ne mesure rien")
		quit(1)
		return

	var chemins := _lister_cibles()
	var a_coller: Array = []
	var total_reel := 0

	for chemin in chemins:
		var reel := _compter_suites_partagees(chemin, corpus)
		total_reel += reel
		var attendu: int = COMPTES.get(chemin, 0)
		if reel == attendu:
			continue
		if not COMPTES.has(chemin):
			verif.v(false, "%s partage %d suite(s) de %d mots avec un document et n'est pas au registre -- un fichier neuf naît a zero" % [chemin, reel, TAILLE_SUITE])
		elif reel > attendu:
			verif.v(false, "%s partage %d suite(s) pour %d enregistree(s) -- retirer la recopie d'un des deux cotes, ou monter le compte dans le MEME commit" % [chemin, reel, attendu])
		else:
			verif.v(false, "%s partage %d suite(s) pour %d enregistree(s) -- baisser le compte a %d dans le MEME commit, le cliquet se resserre" % [chemin, reel, attendu, reel])
		a_coller.append("\t\"%s\": %d," % [chemin, reel])

	var coeur := _lister_coeur()
	var index := _index_du_coeur(coeur)
	var a_coller_coeur: Array = []
	var total_coeur := 0

	for chemin in coeur:
		var reel := _compter_suites_du_coeur(chemin, index)
		total_coeur += reel
		var attendu: int = COMPTES_COEUR.get(chemin, 0)
		if reel == attendu:
			continue
		if not COMPTES_COEUR.has(chemin):
			verif.v(false, "%s partage %d suite(s) de %d mots avec un AUTRE fichier du coeur et n'est pas au registre -- un fichier neuf naît a zero" % [chemin, reel, TAILLE_SUITE])
		elif reel > attendu:
			verif.v(false, "%s partage %d suite(s) avec le coeur pour %d enregistree(s) -- mettre le fait a UN endroit et y renvoyer, ou monter le compte dans le MEME commit" % [chemin, reel, attendu])
		else:
			verif.v(false, "%s partage %d suite(s) avec le coeur pour %d enregistree(s) -- baisser le compte a %d dans le MEME commit, le cliquet se resserre" % [chemin, reel, attendu, reel])
		a_coller_coeur.append("\t\"%s\": %d," % [chemin, reel])

	if verif.echecs() > 0:
		if not a_coller.is_empty():
			print("--- registre a coller dans COMPTES (%d entree(s)) ---" % a_coller.size())
			for ligne in a_coller:
				print(ligne)
		if not a_coller_coeur.is_empty():
			print("--- registre a coller dans COMPTES_COEUR (%d entree(s)) ---" % a_coller_coeur.size())
			for ligne in a_coller_coeur:
				print(ligne)
		print("ECHEC: %d fichier(s) hors de leur compte de doublon" % verif.echecs())
		quit(1)
		return

	print("OK: les %d fichiers de scripts/ et data/ portent exactement leur compte de suites recopiees depuis %d document(s) (%d suite(s) de %d mots au total), et les %d fichiers du coeur leur compte de suites recopiees d'un fichier du coeur a l'autre (%d) -- deux comptes qui ne peuvent que descendre" % [chemins.size(), DOCUMENTS.size(), total_reel, TAILLE_SUITE, coeur.size(), total_coeur])
	quit(0)

# Le COEUR : tout .gd de scripts/ qui n'est ni un banc ni un test. Aucune
# liste en dur -- le disque et deux prefixes suffisent, un mecanisme neuf y
# entre sans qu'on ait rien a inscrire.
func _lister_coeur() -> Array:
	var chemins: Array = []
	for nom in DirAccess.get_files_at(DOSSIER_CODE):
		if nom.ends_with(".gd") and not nom.begins_with("banc_") and not nom.begins_with("test_"):
			chemins.append("%s/%s" % [DOSSIER_CODE, nom])
	chemins.sort()
	return chemins

# suite -> nombre de FICHIERS distincts du coeur qui la portent. Une suite
# repetee dans un seul fichier n'est pas un doublon entre fichiers : elle ne
# compte qu'une fois par fichier ici.
func _index_du_coeur(coeur: Array) -> Dictionary:
	var index := {}
	for chemin in coeur:
		var vues := {}
		for suite in _suites(_normaliser(_prose_de(chemin))):
			vues[suite] = true
		for suite in vues:
			index[suite] = index.get(suite, 0) + 1
	return index

func _compter_suites_du_coeur(chemin: String, index: Dictionary) -> int:
	var partagees := 0
	for suite in _suites(_normaliser(_prose_de(chemin))):
		if index.get(suite, 0) >= 2:
			partagees += 1
	return partagees

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

func _est_prose(ligne: String, chemin: String) -> bool:
	if chemin.ends_with(".gd"):
		return ligne.strip_edges().begins_with("#")
	return _cle_note.search(ligne) != null

# Toutes les suites de TAILLE_SUITE mots des documents, en cles d'un
# Dictionary -- la recherche par fichier doit rester en temps constant, un
# balayage lineaire par suite coûterait le carre du corpus.
func _suites_des_documents() -> Dictionary:
	var corpus := {}
	for chemin in DOCUMENTS:
		var texte := FileAccess.get_file_as_string(chemin)
		if texte.is_empty():
			push_error("test_doublon_code_doc.gd : %s illisible ou vide" % chemin)
			continue
		for suite in _suites(_normaliser(texte)):
			corpus[suite] = true
	return corpus

# Compte les suites de la PROSE d'un fichier qui se retrouvent dans le corpus.
# Le code et les valeurs de donnee ne sont jamais compares : un nom de fonction
# ou de cle cite dans un document est un INDEX, pas un doublon -- c'est meme
# exactement ce qu'un index doit faire.
func _compter_suites_partagees(chemin: String, corpus: Dictionary) -> int:
	var partagees := 0
	for suite in _suites(_normaliser(_prose_de(chemin))):
		if corpus.has(suite):
			partagees += 1
	return partagees

func _prose_de(chemin: String) -> String:
	var texte := FileAccess.get_file_as_string(chemin)
	if texte.is_empty():
		push_error("test_doublon_code_doc.gd : %s illisible ou vide" % chemin)
		return ""
	var prose := ""
	for ligne in texte.split("\n"):
		if _est_prose(ligne, chemin):
			prose += " " + ligne.strip_edges().trim_prefix("#")
	return prose

func _normaliser(texte: String) -> String:
	var bas := texte.to_lower()
	for accent in ACCENTS:
		bas = bas.replace(accent, ACCENTS[accent])
	return _nettoyeur.sub(bas, " ", true)

func _suites(texte_normalise: String) -> Array:
	var mots := texte_normalise.split(" ", false)
	var suites: Array = []
	if mots.size() < TAILLE_SUITE:
		return suites
	for i in range(mots.size() - TAILLE_SUITE + 1):
		var morceaux: Array = []
		for j in range(TAILLE_SUITE):
			morceaux.append(mots[i + j])
		suites.append(" ".join(morceaux))
	return suites
