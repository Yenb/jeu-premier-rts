extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_volume_entetes.gd
#
# PLAFOND DE LISIBILITE PAR FICHIER, sur la PROSE de scripts/*.gd et de
# data/*.json. Troisieme garde, et le seul qui porte le critere reel : un
# commentaire existe pour rendre le fichier COMPREHENSIBLE. Un preambule de
# deux cents lignes echoue a ca meme quand chacune de ses phrases est vraie --
# on ne le lit plus, on saute au code. Le recit
# (scripts/test_recit_dans_le_code.gd) et la recopie
# (scripts/test_doublon_code_doc.gd) sont des INDICES de ce defaut ; le volume
# en est la mesure directe.
#
# CE QUI EST MESURE, en OCTETS et jamais en lignes : pour un .gd, le PREAMBULE
# -- tout commentaire situe AVANT la premiere func, c'est-a-dire le mode
# d'emploi au sens de CLAUDE.md, « Doctrine d'en-tete ». Pour un .json, la
# somme des lignes portant une cle de note. Les lignes valent d'etre comptees
# en octets : une seule ligne de note a deja pese 31 000 caracteres dans ce
# depot, un plafond en lignes ne l'aurait jamais vu.
#
# CE QUE CE TEST N'EST PAS : un jugement sur une phrase. Il ne sait pas lire.
# Il compare un poids a un plafond, fichier par fichier.
#
# DEUX REPONSES A UN ROUGE, aucune autre :
#   - poids AU-DESSUS : le preambule a grossi. Le degraisser, ou monter le
#     plafond ICI dans le MEME commit -- ce qui rend la croissance visible dans
#     le diff au lieu de la laisser passer en silence.
#   - poids EN DESSOUS : le preambule a maigri. Baisser le plafond ICI dans le
#     MEME commit. Le cliquet se resserre d'un cran, definitivement.
# Un fichier absent du registre doit tenir sous PLAFOND_PAR_DEFAUT.
#
# POURQUOI UN PLAFOND PAR FICHIER ET NON UN RATIO : un ratio commentaire/code
# recompense l'ajout de code et punit le fichier court. portee.gd fait une
# comparaison et n'a besoin que de quelques lignes de mode d'emploi ; sa
# fraction de commentaire sera toujours haute et ce n'est pas un defaut. Ce
# qu'un repreneur ne peut pas absorber, c'est un VOLUME, pas une fraction.
#
# Entree : aucune -- lit scripts/*.gd et data/*.json sur le disque. Sortie :
# "OK:" / exit 0 si chaque fichier est EXACTEMENT a son plafond ou sous le
# defaut ; "ECHEC:" / exit 1 en nommant chaque ecart et la ligne a coller.

const Verif = preload("res://scripts/verif.gd")

const DOSSIER_CODE := "res://scripts"
const DOSSIER_DONNEES := "res://data"

# Meme convention que les deux autres gardes : une ligne de .json est de la
# prose si elle porte une cle de note.
const MOTIF_CLE_NOTE := "\"[a-z_]*(note|commentaire|pourquoi|description|remarque)[a-z_]*\"[ \\t]*:"

# Ce qu'un fichier neuf a le droit de porter sans etre inscrit nulle part.
# Calibre sur ce qu'un repreneur lit d'une traite : de l'ordre de soixante
# lignes de commentaire. Au-dela, le fichier se declare.
const PLAFOND_PAR_DEFAUT := 4000

# Chemin -> plafond en octets. Ce registre ne s'ajoute pas : il se vide, et
# chaque entree qui disparait est un fichier revenu sous le defaut.
const PLAFONDS := {
	"res://scripts/monde.gd": 5776,
	"res://data/banc_affordances_choix.json": 8615,
	"res://data/banc_affordances_connaissance.json": 7433,
	"res://data/banc_affordances_portage.json": 5548,
	"res://data/banc_affordances_travail.json": 10718,
	"res://data/banc_bonheur.json": 5273,
	"res://data/banc_croyance.json": 4312,
	"res://data/banc_ecosysteme_terrain.json": 7213,
	"res://data/banc_elimination_salete.json": 5062,
	"res://data/banc_graisse_accoutumance.json": 5220,
	"res://data/banc_grief.json": 4400,
	"res://data/banc_lien_personnel.json": 4860,
	"res://data/banc_marche_competence.json": 7292,
	"res://data/banc_menace_combat.json": 5765,
	"res://data/banc_oubli_consolidation.json": 5528,
	"res://data/banc_parasites_reproduction.json": 5916,
	"res://data/banc_predation.json": 18524,
	"res://data/banc_psycho_social.json": 11298,
	"res://data/banc_social_foule.json": 6445,
	"res://data/banc_social_information.json": 9214,
	"res://data/banc_social_paire.json": 7445,
	"res://data/banc_social_rupture.json": 6413,
	"res://data/banc_stress_thermo_vivant.json": 8125,
	"res://data/banc_temps_anticipation.json": 6244,
	"res://data/banc_temps_saisons.json": 6419,
	"res://data/biomes.json": 4504,
	"res://data/canaux.json": 7310,
	"res://data/comptages.json": 5634,
	"res://data/croyances.json": 4981,
	"res://data/deformations.json": 24341,
	"res://data/epigenetique.json": 23099,
	"res://data/etats.json": 94118,
	"res://data/materiaux.json": 43711,
	"res://data/profils_saillance.json": 13802,
	"res://data/reproduction.json": 6177,
	"res://data/seuils_combustible.json": 4032,
	"res://data/seuils_etat.json": 46825,
	"res://data/transformations.json": 19166,
	"res://data/types.json": 16269,
	"res://scripts/accouplement.gd": 6802,
	"res://scripts/agir.gd": 11067,
	"res://scripts/attache_par_trait.gd": 4513,
	"res://scripts/attaches.gd": 4922,
	"res://scripts/banc_activation_neutronique.gd": 4665,
	"res://scripts/banc_affordances_choix.gd": 10518,
	"res://scripts/banc_affordances_connaissance.gd": 10276,
	"res://scripts/banc_affordances_portage.gd": 7103,
	"res://scripts/banc_affordances_travail.gd": 10154,
	"res://scripts/banc_animal.gd": 4068,
	"res://scripts/banc_bonheur.gd": 9225,
	"res://scripts/banc_changement_etat.gd": 4952,
	"res://scripts/banc_charge.gd": 6845,
	"res://scripts/banc_choc_magique.gd": 6254,
	"res://scripts/banc_commun.gd": 4952,
	"res://scripts/banc_conduction.gd": 8890,
	"res://scripts/banc_controle.gd": 5202,
	"res://scripts/banc_convergence_attache.gd": 4886,
	"res://scripts/banc_corrosion.gd": 7162,
	"res://scripts/banc_coupe.gd": 5015,
	"res://scripts/banc_cratere.gd": 4826,
	"res://scripts/banc_croissance.gd": 5429,
	"res://scripts/banc_croyance.gd": 4675,
	"res://scripts/banc_economie.gd": 10853,
	"res://scripts/banc_ecosysteme_terrain.gd": 11686,
	"res://scripts/banc_elasticite.gd": 4952,
	"res://scripts/banc_elimination_salete.gd": 7504,
	"res://scripts/banc_emergences.gd": 4115,
	"res://scripts/banc_erosion.gd": 5394,
	"res://scripts/banc_faim_thermo.gd": 7513,
	"res://scripts/banc_fatigue_circadien.gd": 6682,
	"res://scripts/banc_fertilite.gd": 5362,
	"res://scripts/banc_feu.gd": 7458,
	"res://scripts/banc_foudre.gd": 4479,
	"res://scripts/banc_fracture.gd": 6644,
	"res://scripts/banc_fracture_sonore.gd": 4133,
	"res://scripts/banc_genetique.gd": 10013,
	"res://scripts/banc_graisse_accoutumance.gd": 9635,
	"res://scripts/banc_grief.gd": 7245,
	"res://scripts/banc_humidite.gd": 7013,
	"res://scripts/banc_hygiene_apparence.gd": 8011,
	"res://scripts/banc_inflammabilite.gd": 4312,
	"res://scripts/banc_infrastructure.gd": 7840,
	"res://scripts/banc_lien_personnel.gd": 4411,
	"res://scripts/banc_lumiere.gd": 5013,
	"res://scripts/banc_magie_perception.gd": 8293,
	"res://scripts/banc_maladie.gd": 4921,
	"res://scripts/banc_mana_conduction.gd": 5414,
	"res://scripts/banc_manger.gd": 4494,
	"res://scripts/banc_marche_competence.gd": 12009,
	"res://scripts/banc_memoire_navigation.gd": 5873,
	"res://scripts/banc_menace_combat.gd": 7028,
	"res://scripts/banc_nutrition.gd": 5973,
	"res://scripts/banc_occlusion.gd": 4593,
	"res://scripts/banc_oubli_consolidation.gd": 7707,
	"res://scripts/banc_p1.gd": 8320,
	"res://scripts/banc_parasites_reproduction.gd": 9841,
	"res://scripts/banc_permeabilite.gd": 4777,
	"res://scripts/banc_pourriture.gd": 6082,
	"res://scripts/banc_predation.gd": 10028,
	"res://scripts/banc_produit_nucleaire.gd": 6241,
	"res://scripts/banc_psycho_social.gd": 8498,
	"res://scripts/banc_radiation.gd": 5409,
	"res://scripts/banc_reactivite.gd": 7519,
	"res://scripts/banc_reflectivite.gd": 6771,
	"res://scripts/banc_reproduction.gd": 5677,
	"res://scripts/banc_resonance.gd": 5101,
	"res://scripts/banc_rigidite.gd": 4161,
	"res://scripts/banc_simulation_acceleree.gd": 8550,
	"res://scripts/banc_social_foule.gd": 9474,
	"res://scripts/banc_social_information.gd": 8927,
	"res://scripts/banc_social_paire.gd": 12309,
	"res://scripts/banc_social_rupture.gd": 8637,
	"res://scripts/banc_solubilite.gd": 5576,
	"res://scripts/banc_son.gd": 4258,
	"res://scripts/banc_sorts.gd": 6261,
	"res://scripts/banc_soudure.gd": 6507,
	"res://scripts/banc_stress_thermo_vivant.gd": 11116,
	"res://scripts/banc_succession.gd": 4625,
	"res://scripts/banc_temps_anticipation.gd": 6743,
	"res://scripts/banc_temps_saisons.gd": 4488,
	"res://scripts/banc_toxicite.gd": 5368,
	"res://scripts/banc_traction.gd": 4568,
	"res://scripts/banc_vecu_inter_colon.gd": 9657,
	"res://scripts/bifurcation.gd": 6774,
	"res://scripts/champ.gd": 7309,
	"res://scripts/champ_occulte.gd": 5060,
	"res://scripts/comptage.gd": 4500,
	"res://scripts/conditions.gd": 6657,
	"res://scripts/couplage.gd": 8484,
	"res://scripts/croyance.gd": 9653,
	"res://scripts/deformation.gd": 4929,
	"res://scripts/depense.gd": 4467,
	"res://scripts/ecoulement.gd": 4122,
	"res://scripts/epigenetique.gd": 5656,
	"res://scripts/etat_duree.gd": 7779,
	"res://scripts/etat_effectif.gd": 6047,
	"res://scripts/expression.gd": 7908,
	"res://scripts/extinction.gd": 4592,
	"res://scripts/frappe.gd": 4018,
	"res://scripts/gestation.gd": 6465,
	"res://scripts/heredite.gd": 9849,
	"res://scripts/horloge.gd": 5789,
	"res://scripts/jugement.gd": 4854,
	"res://scripts/lien_personnel_attraction.gd": 4710,
	"res://scripts/lien_personnel_croissance.gd": 7563,
	"res://scripts/lumiere.gd": 8181,
	"res://scripts/memoire_spatiale.gd": 8598,
	"res://scripts/objet.gd": 15037,
	"res://scripts/occlusion.gd": 5552,
	"res://scripts/perception.gd": 6958,
	"res://scripts/propagation.gd": 7856,
	"res://scripts/proximite.gd": 4918,
	"res://scripts/reaction.gd": 4595,
	"res://scripts/senescence.gd": 7293,
	"res://scripts/seuil_etat.gd": 10113,
	"res://scripts/temperature.gd": 7453,
	"res://scripts/test_banc_p1.gd": 6658,
	"res://scripts/test_doublon_code_doc.gd": 4213,
	"res://scripts/test_lint_donnees.gd": 9907,
	"res://scripts/usure_attache.gd": 6888,
	"res://scripts/velocite.gd": 5721,
	"res://scripts/vent.gd": 10422,
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

	var a_coller: Array = []
	var total := 0
	var au_defaut := 0

	for chemin in chemins:
		var poids := _poids_prose(chemin)
		total += poids
		var inscrit: bool = PLAFONDS.has(chemin)
		var plafond: int = PLAFONDS.get(chemin, PLAFOND_PAR_DEFAUT)
		if not inscrit:
			if poids <= plafond:
				au_defaut += 1
				continue
			verif.v(false, "%s porte %d octets de prose pour un defaut de %d -- degraisser, ou inscrire le fichier au registre dans le MEME commit" % [chemin, poids, plafond])
		elif poids > plafond:
			verif.v(false, "%s porte %d octets de prose pour un plafond de %d (%d de trop) -- degraisser, ou monter le plafond dans le MEME commit" % [chemin, poids, plafond, poids - plafond])
		elif poids < plafond:
			verif.v(false, "%s porte %d octets de prose pour un plafond de %d -- baisser le plafond a %d dans le MEME commit, le cliquet se resserre" % [chemin, poids, plafond, poids])
		else:
			continue
		a_coller.append("\t\"%s\": %d," % [chemin, poids])

	if verif.echecs() > 0:
		print("--- registre a coller dans PLAFONDS (%d entree(s)) ---" % a_coller.size())
		for ligne in a_coller:
			print(ligne)
		print("ECHEC: %d fichier(s) hors de leur plafond de prose" % verif.echecs())
		quit(1)
		return

	print("OK: les %d fichiers de scripts/ et data/ tiennent leur plafond de prose (%d sous le defaut de %d octets, %d octets de prose au total, un poids qui ne peut que descendre)" % [chemins.size(), au_defaut, PLAFOND_PAR_DEFAUT, total])
	quit(0)

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

# Poids de la prose, en octets. Pour un .gd, seul compte ce qui precede la
# premiere func : un commentaire pose AU-DESSUS d'une fonction precise est du
# mode d'emploi local, il vit au plus pres de ce qu'il explique et n'entre pas
# dans ce plafond. Pour un .json, toute ligne portant une cle de note.
func _poids_prose(chemin: String) -> int:
	var texte := FileAccess.get_file_as_string(chemin)
	if texte.is_empty():
		push_error("test_volume_entetes.gd : %s illisible ou vide" % chemin)
		return 0
	var est_code := chemin.ends_with(".gd")
	var avant_premiere_func := true
	var poids := 0
	for ligne in texte.split("\n"):
		if est_code:
			if ligne.strip_edges().begins_with("func ") or ligne.strip_edges().begins_with("static func "):
				avant_premiere_func = false
			if avant_premiere_func and ligne.strip_edges().begins_with("#"):
				poids += ligne.length() + 1
		elif _cle_note.search(ligne) != null:
			poids += ligne.length() + 1
	return poids
