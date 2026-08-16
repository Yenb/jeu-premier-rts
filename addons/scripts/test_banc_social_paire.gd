extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_social_paire.gd
#
# Verrouille scripts/banc_social_paire.gd (chantier « relation par paire »,
# audit_social_relations_prealable.md lignes 1, 2, 3, 11 et 14). Les
# MECANISMES eux-memes sont verrouilles hors domaine ailleurs
# (test_lien_personnel.gd, test_epigenetique.gd, test_seuil_etat.gd,
# test_bifurcation.gd, test_charge.gd, test_dominance.gd, test_agir.gd) --
# ce fichier-ci ne teste que le CABLAGE.
#
# Couvre les treize issues demandees :
#   la confiance monte par temps partage ; 'confiant_combattre' pose au
#   premier seuil ; 'confiant_obeir' pose au second ; le lien_negatif monte
#   par agression ; le score_net vaut positif - negatif ; la dette monte au
#   service et decroit dans le temps ; 'rancunier' pose sous seuil_rancune ;
#   le colon refuse de tuer un proche ; le refus force accumule du grief ;
#   le colon cede au chef fort et aime ; il resiste au chef faible ET au chef
#   hai ; lien_personnel.gd reste POSITIF SEULEMENT ; aucun mecanisme du coeur
#   n'est modifie.
#
# Plus huit verrous que la consigne ne demandait pas et que le banc exige :
#   l'ami PLAFONNE entre les deux seuils et n'obeit JAMAIS (sans quoi
#   l'escalier serait une affaire de temps, pas de personne) ; l'ennemi, que
#   personne ne frequente, n'accumule RIEN ; « a portee » est REEL (un colon
#   eloigne cesse d'accumuler, sa confiance redescend et ses etats se
#   retirent) ; la CADENCE de pose reste sous la borne des trois planchers de
#   suppression, mesuree contre les nombres REELS de data/epigenetique.json
#   (resultat negatif deja paye TROIS fois dans le depot -- une marque effacee
#   entre deux poses n'accumule JAMAIS rien) ; le catalogue PARTAGE de seuils
#   ne pose AUCUN etat parasite sur ces colons ; la bifurcation ne rend AUCUNE
#   sortie sans ordre (le gate par la grandeur, pas par un `if`) ; le refus
#   NON force ne coute AUCUN grief ; et le REJEU COMPLET de
#   data/banc_social_paire.json franchit vraiment ses seuils -- lecon de
#   banc_maladie, dont le seuil d'origine ne franchissait jamais rien pendant
#   que son test restait VERT.
#
# Le dernier cas fait traverser le MEME code par un domaine ENTIEREMENT
# INVENTE (suffixe "_vroque", aucun nom du jeu, ni « confiance » ni « chef »
# ni « tuer ») : c'est ce qui prouve qu'aucun nom de propriete, d'etat ou de
# verbe n'est ecrit en dur dans le .gd.

const Banc = preload("res://scripts/banc_social_paire.gd")
const Monde = preload("res://scripts/monde.gd")
const Epigenetique = preload("res://scripts/epigenetique.gd")
const LienPersonnel = preload("res://scripts/lien_personnel.gd")
const Verif = preload("res://scripts/verif.gd")

const DELTA := 0.05

# Les quatorze fichiers du coeur que ce chantier s'interdit de toucher.
const COEUR_INTOUCHE := [
	"lien_personnel", "epigenetique", "seuil_etat", "etat_effectif",
	"depense", "charge", "bifurcation", "attaches", "dominance", "agir",
	"couplage", "perception", "portee", "comptage",
]

# Le vocabulaire NEUF de ce chantier. Aucun de ces mots ne doit apparaitre
# dans un fichier du coeur -- c'est la doctrine « le moteur ne connait que des
# verbes » rendue opposable, pas une precaution de style.
const VOCABULAIRE_DU_BANC := [
	"confiance", "lien_negatif", "service_rendu", "cession",
	"transgress", "rancun", "social_paire",
]

func _init() -> void:
	var v := Verif.new()
	_la_confiance_monte_par_temps_partage(v)
	_le_premier_seuil_pose_confiant_combattre(v)
	_le_second_seuil_pose_confiant_obeir(v)
	_l_ami_plafonne_entre_les_deux_seuils(v)
	_l_ennemi_n_accumule_aucune_confiance(v)
	_hors_de_portee_la_confiance_cesse_et_les_etats_se_retirent(v)
	_le_lien_negatif_monte_par_agression(v)
	_le_score_net_vaut_positif_moins_negatif(v)
	_la_dette_monte_au_service_et_decroit_dans_le_temps(v)
	_rancunier_pose_sous_le_seuil_puis_se_retire(v)
	_le_colon_refuse_de_tuer_un_proche(v)
	_le_refus_non_force_ne_coute_aucun_grief(v)
	_le_refus_force_accumule_du_grief(v)
	_aucune_cession_sans_ordre(v)
	_le_colon_cede_au_chef_fort_et_aime(v)
	_le_colon_resiste_au_chef_faible(v)
	_le_colon_resiste_au_chef_hai(v)
	_lien_personnel_reste_positif_seulement(v)
	_la_cadence_reste_sous_la_borne_des_planchers(v)
	_aucun_etat_parasite_du_catalogue_partage(v)
	_aucun_mecanisme_du_coeur_n_est_modifie(v)
	_aucun_nom_en_dur(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: banc_social_paire -- confiance par paire (marque epigenetique a nom compose, " +
			"catalogue LOCAL derive d'UNE entree partagee), escalier a deux paliers combattre/obeir " +
			"avec plafond PAR COLON, portee reelle et reversible, haine en SECOND REGISTRE POSITIF " +
			"(score net = positif - negatif, lien_personnel.gd inchange et positif seulement), " +
			"dette = difference lue sur deux entites, rancune par miroir plat inverse, " +
			"refus de tuer un proche par RETRAIT d'entree avant dominance.gd, ordre force -> " +
			"transgression -> grief par charge.gd, cession tranchee par bifurcation.gd (gate par la " +
			"grandeur, comparaison dans le biais), cadence sous la borne des trois planchers, " +
			"aucun etat parasite, aucun mecanisme du coeur modifie, aucun nom en dur")
		quit(0)

# ---------------------------------------------------------------------------
# Outils
# ---------------------------------------------------------------------------

func _config() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_social_paire.json"))

func _seuils() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/seuils_etat.json"))

func _liens() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/liens_personnels.json"))

func _epigenetique() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/epigenetique.json"))

# Monte la scene entiere depuis la donnee, exactement comme _ready le fait.
func _scene(config: Dictionary) -> Dictionary:
	var colons := Banc.construire_colons(config)
	var menace := Banc.construire_menace(config)
	var ouvrages := Banc.construire_ouvrages(config)
	return {
		"colons": colons,
		"menace": menace,
		"ouvrages": ouvrages,
		"paires": Banc.catalogue_paires(config, colons, _epigenetique()),
		"monde": Banc.construire_monde(colons, menace, ouvrages.values(), Monde),
	}

func _tourner(scene: Dictionary, mode: String, ordre: int, secondes: float, config: Dictionary) -> Dictionary:
	var bilan: Dictionary = {}
	var restant := secondes
	while restant > 0.0:
		bilan = Banc.avancer(scene.colons, scene.menace, scene.ouvrages, mode, ordre,
			config, _seuils(), _liens(), scene.paires, scene.monde, DELTA)
		restant -= DELTA
	return bilan

func _colon(scene: Dictionary, id: String) -> Dictionary:
	return Banc.colon_par_id(scene.colons, id)

func _etat_de(bilan: Dictionary, id: String) -> Dictionary:
	for etat_colon in bilan.get("colons", []):
		if String(etat_colon.id) == id:
			return etat_colon
	return {}

func _actifs(colon: Dictionary) -> Array:
	return colon.proprietes.get("etats_actifs", [])

# ---------------------------------------------------------------------------
# Ligne 1 -- la confiance monte par temps partage, et debloque par paliers
# ---------------------------------------------------------------------------

func _la_confiance_monte_par_temps_partage(v) -> void:
	var config := _config()
	var scene := _scene(config)
	var soldat := _colon(scene, "soldat")
	v.v(Banc.confiance(soldat, "chef", config) == 0.0,
		"pre-condition : la confiance doit partir de zero, jamais posee en dur")
	_tourner(scene, Banc.MODE_SERVICE, Banc.ORDRE_AUCUN, 1.0, config)
	var apres := Banc.confiance(soldat, "chef", config)
	v.v(apres > 0.0, "la confiance doit MONTER par temps partage (obtenu %.3f)" % apres)
	# La montee NETTE exacte, jamais un « ca monte » approximatif :
	# modulateur_pose / intervalle - taux_decroissance, tous lus sur le disque.
	var regle: Dictionary = _epigenetique()["confiance"]
	var net: float = float(regle.modulateur_pose) / float(config.intervalle_interaction_s) \
		- float(regle.taux_decroissance)
	v.v(abs(apres - net * 1.0) < 0.03,
		"la montee doit valoir (modulateur_pose / intervalle - taux) x duree, soit %.3f/s (obtenu %.3f)"
			% [net, apres])

func _le_premier_seuil_pose_confiant_combattre(v) -> void:
	var config := _config()
	var scene := _scene(config)
	var soldat := _colon(scene, "soldat")
	var etat := String(config.etat_confiant_combattre)
	v.v(not _actifs(soldat).has(etat), "pre-condition : aucun etat au depart")
	# Assez pour franchir 0.20 a 0.18/s (t = 1.1 s), pas assez pour 0.70.
	_tourner(scene, Banc.MODE_SERVICE, Banc.ORDRE_AUCUN, 2.0, config)
	v.v(_actifs(soldat).has(etat),
		"'%s' doit etre pose au premier palier (confiance %.3f)" % [etat, Banc.confiance(soldat, "chef", config)])
	v.v(not _actifs(soldat).has(String(config.etat_confiant_obeir)),
		"le SECOND palier ne doit PAS encore etre franchi a 2 s -- sinon l'escalier n'en est pas un")
	# Le gate REEL, pas seulement l'etat : sans lui l'entree de menace tombe.
	var scene_nue := _scene(config)
	var soldat_nu := _colon(scene_nue, "soldat")
	var bruts := Banc.resultats_bruts(soldat_nu, scene_nue.menace, scene_nue.ouvrages["soldat"],
		{}, config, Banc.ORDRE_AUCUN)
	var filtre := Banc.filtrer_resultats(soldat_nu, bruts, {}, config, _liens(), Banc.ORDRE_AUCUN)
	var motifs: Array = []
	for retire in filtre.retires:
		motifs.append(String(retire.motif))
	v.v(motifs.has(Banc.MOTIF_SANS_CONFIANCE_COMBATTRE),
		"sans '%s', l'entree de menace doit etre RETIREE de resultats (motifs obtenus : %s)" % [etat, motifs])

func _le_second_seuil_pose_confiant_obeir(v) -> void:
	var config := _config()
	var scene := _scene(config)
	var soldat := _colon(scene, "soldat")
	_tourner(scene, Banc.MODE_SERVICE, Banc.ORDRE_AUCUN, 6.0, config)
	v.v(_actifs(soldat).has(String(config.etat_confiant_obeir)),
		"'%s' doit etre pose au second palier (confiance %.3f)"
			% [String(config.etat_confiant_obeir), Banc.confiance(soldat, "chef", config)])
	# L'ESCALIER : les DEUX restent actifs ensemble, aucune entree n'en retire
	# une autre (memoire PAR ENTREE de seuil_etat.gd).
	v.v(_actifs(soldat).has(String(config.etat_confiant_combattre)),
		"le premier palier doit rester actif SOUS le second -- c'est un escalier, pas une bascule")

func _l_ami_plafonne_entre_les_deux_seuils(v) -> void:
	var config := _config()
	var scene := _scene(config)
	var ami := _colon(scene, "ami")
	# Trois fois le temps qu'il faudrait au soldat : si l'ami franchissait le
	# second palier un jour, ce serait ici.
	_tourner(scene, Banc.MODE_SERVICE, Banc.ORDRE_AUCUN, 18.0, config)
	var c := Banc.confiance(ami, "chef", config)
	var plafond: float = float(ami.proprietes[String(config.nom_plafond_confiance)])
	# Une decroissance d'intervalle de marge sous le plafond : la pose est
	# BORNEE (banc_social_paire.gd:_poser_borne), donc le modulateur oscille
	# entre « juste sous » et « juste au-dessus » -- lu clampe, il vaut le
	# plafond ou une decroissance en dessous, jamais davantage.
	var regle: Dictionary = _epigenetique()["confiance"]
	var marge: float = float(regle.taux_decroissance) * float(config.intervalle_interaction_s) + 0.001
	v.v(c <= plafond and c >= plafond - marge,
		"l'ami doit se tenir a son plafond individuel %.2f (a %.4f pres, obtenu %.4f) -- " % [plafond, marge, c] +
		"borne A LA POSE, jamais laisse deriver au-dessus")
	v.v(_actifs(ami).has(String(config.etat_confiant_combattre)),
		"l'ami doit franchir le premier palier")
	v.v(not _actifs(ami).has(String(config.etat_confiant_obeir)),
		"l'ami ne doit JAMAIS franchir le second : son plafond (%.2f) est sous le seuil (%.2f) -- " % [
			plafond, Banc.seuil_de(_seuils(), String(config.ref_seuil_obeir))] +
		"c'est un POIDS individuel qui le decide, jamais un seuil different")

func _l_ennemi_n_accumule_aucune_confiance(v) -> void:
	var config := _config()
	var scene := _scene(config)
	var ennemi := _colon(scene, "ennemi")
	_tourner(scene, Banc.MODE_SERVICE, Banc.ORDRE_AUCUN, 18.0, config)
	v.v(Banc.confiance(ennemi, "chef", config) == 0.0,
		"l'ennemi, avec qui personne ne partage de temps, doit rester a EXACTEMENT 0.0 -- " +
		"son plafond est pourtant le plus haut (%.2f) : c'est l'absence d'interaction qui decide"
			% float(ennemi.proprietes[String(config.nom_plafond_confiance)]))
	v.v(_actifs(ennemi).is_empty() or not _actifs(ennemi).has(String(config.etat_confiant_combattre)),
		"l'ennemi ne doit franchir aucun palier de confiance")

# « A PORTEE » EST REEL : c'est le seul cas qui le prouve, la scene par defaut
# ayant tout le monde a portee. Prouve AUSSI la reversibilite complete.
func _hors_de_portee_la_confiance_cesse_et_les_etats_se_retirent(v) -> void:
	var config := _config()
	var scene := _scene(config)
	var soldat := _colon(scene, "soldat")
	_tourner(scene, Banc.MODE_SERVICE, Banc.ORDRE_AUCUN, 6.0, config)
	var haut := Banc.confiance(soldat, "chef", config)
	v.v(_actifs(soldat).has(String(config.etat_confiant_obeir)), "pre-condition : les deux paliers franchis")

	# On l'eloigne au-dela de portee_interaction. Rien d'autre ne change.
	soldat.position = Vector3(99999.0, 0.0, 0.0)
	_tourner(scene, Banc.MODE_SERVICE, Banc.ORDRE_AUCUN, 2.0, config)
	var apres := Banc.confiance(soldat, "chef", config)
	v.v(apres < haut,
		"hors de portee, la confiance doit DESCENDRE (%.3f -> %.3f)" % [haut, apres])

	# Assez longtemps pour repasser sous les deux seuils : la decroissance est
	# lente devant la montee (0.02/s contre 0.18/s), et c'est voulu.
	_tourner(scene, Banc.MODE_SERVICE, Banc.ORDRE_AUCUN, 60.0, config)
	v.v(not _actifs(soldat).has(String(config.etat_confiant_obeir)),
		"le second palier doit se RETIRER au franchissement descendant (confiance %.3f)"
			% Banc.confiance(soldat, "chef", config))
	v.v(not _actifs(soldat).has(String(config.etat_confiant_combattre)),
		"le premier palier aussi -- reversibilite complete, sans une ligne de plus")

# ---------------------------------------------------------------------------
# Ligne 2 -- deux registres positifs, un score net signe
# ---------------------------------------------------------------------------

func _le_lien_negatif_monte_par_agression(v) -> void:
	var config := _config()
	var scene := _scene(config)
	var soldat := _colon(scene, "soldat")
	v.v(Banc.lien_negatif(soldat, "ennemi", config) == 0.0, "pre-condition : aucune haine au depart")
	_tourner(scene, Banc.MODE_AGRESSION, Banc.ORDRE_AUCUN, 2.0, config)
	var haine := Banc.lien_negatif(soldat, "ennemi", config)
	v.v(haine > 0.0, "le lien_negatif de la VICTIME envers l'agresseur doit monter (obtenu %.3f)" % haine)
	# La marque est posee sur la VICTIME, jamais sur l'agresseur.
	var ennemi := _colon(scene, "ennemi")
	v.v(Banc.lien_negatif(ennemi, "soldat", config) == 0.0,
		"l'AGRESSEUR ne doit rien accumuler : c'est la victime qui hait, jamais l'inverse")
	# En mode service, aucune agression n'est declaree : rien ne monte.
	var scene_paisible := _scene(config)
	_tourner(scene_paisible, Banc.MODE_SERVICE, Banc.ORDRE_AUCUN, 2.0, config)
	v.v(Banc.lien_negatif(_colon(scene_paisible, "soldat"), "ennemi", config) == 0.0,
		"sans agression declaree, aucun lien_negatif ne doit apparaitre")

func _le_score_net_vaut_positif_moins_negatif(v) -> void:
	var config := _config()
	var scene := _scene(config)
	var soldat := _colon(scene, "soldat")
	_tourner(scene, Banc.MODE_AGRESSION, Banc.ORDRE_AUCUN, 3.0, config)
	var positif := Banc.lien_positif(soldat, "ennemi", _liens())
	var negatif := Banc.lien_negatif(soldat, "ennemi", config)
	var net := Banc.score_net(soldat, "ennemi", config, _liens())
	v.v(abs(net - (positif - negatif)) < 0.0001,
		"le score net doit valoir EXACTEMENT positif - negatif (%.4f - %.4f attendu, %.4f obtenu)"
			% [positif, negatif, net])
	v.v(net < 0.0,
		"apres agression, le net du soldat envers l'ennemi doit etre NEGATIF (obtenu %.3f) -- " % net +
		"une valeur signee obtenue de deux registres qui, eux, restent positifs")
	v.v(positif >= 0.0 and negatif >= 0.0,
		"les DEUX registres pris separement doivent rester positifs (%.3f et %.3f)" % [positif, negatif])
	# Et le lien positif vers l'ami, lui, n'a pas bouge : deux paires, deux
	# registres, aucune contamination.
	v.v(Banc.score_net(soldat, "ami", config, _liens()) > 0.0,
		"le net envers l'ami doit rester positif -- une haine ailleurs n'entame pas un attachement ici")

# ---------------------------------------------------------------------------
# Ligne 3 -- la dette, et la rancune
# ---------------------------------------------------------------------------

func _la_dette_monte_au_service_et_decroit_dans_le_temps(v) -> void:
	var config := _config()
	var scene := _scene(config)
	var chef := _colon(scene, "chef")
	var ennemi := _colon(scene, "ennemi")
	v.v(Banc.dette_sociale(ennemi, chef, config) == 0.0, "pre-condition : aucune dette au depart")

	_tourner(scene, Banc.MODE_SERVICE, Banc.ORDRE_AUCUN, 3.0, config)
	var rendu := Banc.service_rendu(chef, "ennemi", config)
	v.v(rendu > 0.0, "le service RENDU doit monter chez celui qui rend (obtenu %.3f)" % rendu)
	v.v(Banc.service_rendu(ennemi, "chef", config) == 0.0,
		"le beneficiaire n'ecrit RIEN -- sa dette est la lecture du registre de l'autre")
	var dette_ennemi := Banc.dette_sociale(ennemi, chef, config)
	var dette_chef := Banc.dette_sociale(chef, ennemi, config)
	v.v(abs(dette_ennemi + rendu) < 0.0001,
		"la dette du beneficiaire doit valoir EXACTEMENT -service_rendu (%.4f attendu, %.4f obtenu)"
			% [-rendu, dette_ennemi])
	v.v(abs(dette_chef - rendu) < 0.0001,
		"et celle du bienfaiteur exactement +service_rendu -- la dette est ANTISYMETRIQUE (%.4f obtenu)"
			% dette_chef)

	# LA DECROISSANCE : on coupe le service (mode agression n'en declare
	# aucun) et la dette remonte vers zero d'elle-meme, par epigenetique.gd:
	# avancer et rien d'autre.
	_tourner(scene, Banc.MODE_AGRESSION, Banc.ORDRE_AUCUN, 2.0, config)
	var apres := Banc.service_rendu(chef, "ennemi", config)
	v.v(apres < rendu, "la dette doit DECROITRE quand le service cesse (%.3f -> %.3f)" % [rendu, apres])
	var regle: Dictionary = _epigenetique()["service_rendu"]
	var attendu: float = rendu - float(regle.taux_decroissance) * 2.0
	v.v(abs(apres - attendu) < 0.01,
		"la descente doit valoir exactement taux_decroissance x duree (%.3f attendu, %.3f obtenu)"
			% [attendu, apres])

func _rancunier_pose_sous_le_seuil_puis_se_retire(v) -> void:
	var config := _config()
	var scene := _scene(config)
	var ennemi := _colon(scene, "ennemi")
	var etat := String(config.etat_rancunier)
	var seuil := Banc.seuil_de(_seuils(), String(config.ref_seuil_rancune))

	_tourner(scene, Banc.MODE_SERVICE, Banc.ORDRE_AUCUN, 8.0, config)
	var dette := Banc.dette_sociale(ennemi, _colon(scene, "chef"), config)
	v.v(dette < -seuil,
		"la dette de l'ennemi doit passer sous -%.2f (obtenu %.3f)" % [seuil, dette])
	v.v(_actifs(ennemi).has(etat),
		"'%s' doit etre pose quand le score net (rendus - recus) passe sous le seuil" % etat)
	# Le miroir INVERSE, verifie explicitement : c'est la seule forme que
	# seuil_etat.gd sache comparer.
	v.v(abs(float(ennemi.proprietes[String(config.nom_dette_negative)]) + dette) < 0.0001,
		"'%s' doit valoir EXACTEMENT -dette (%.4f attendu, %.4f obtenu)" % [
			String(config.nom_dette_negative), -dette,
			float(ennemi.proprietes[String(config.nom_dette_negative)])])
	# C'est le DEBITEUR qui est rancunier, jamais le bienfaiteur.
	v.v(not _actifs(_colon(scene, "chef")).has(etat),
		"le chef, dont la dette est POSITIVE, ne doit jamais devenir rancunier")

	# REVERSIBLE : le service cesse, la dette remonte, l'etat se retire.
	_tourner(scene, Banc.MODE_AGRESSION, Banc.ORDRE_AUCUN, 200.0, config)
	v.v(not _actifs(ennemi).has(etat),
		"'%s' doit se RETIRER quand la dette remonte (dette %.3f)" % [
			etat, Banc.dette_sociale(ennemi, _colon(scene, "chef"), config)])

# ---------------------------------------------------------------------------
# Ligne 11 -- le refus de tuer un proche
# ---------------------------------------------------------------------------

# Amene le soldat au second palier de confiance : etat de depart de tous les
# cas d'ordre ci-dessous (sans 'confiant_obeir', c'est un AUTRE gate qui
# tomberait et le refus ne serait jamais atteint).
func _scene_soldat_confiant(config: Dictionary) -> Dictionary:
	var scene := _scene(config)
	_tourner(scene, Banc.MODE_SERVICE, Banc.ORDRE_AUCUN, 6.0, config)
	return scene

func _le_colon_refuse_de_tuer_un_proche(v) -> void:
	var config := _config()
	var scene := _scene_soldat_confiant(config)
	var soldat := _colon(scene, "soldat")
	v.v(_actifs(soldat).has(String(config.etat_confiant_obeir)),
		"pre-condition : le soldat doit avoir assez confiance pour obeir")
	var lien := Banc.lien_positif(soldat, String(config.cible_ordre_id), _liens())
	v.v(lien > float(config.seuil_attache),
		"pre-condition : le lien du soldat vers '%s' (%.2f) doit depasser le seuil d'attache (%.2f)"
			% [String(config.cible_ordre_id), lien, float(config.seuil_attache)])

	var bilan := _tourner(scene, Banc.MODE_SERVICE, Banc.ORDRE_DONNE, 0.5, config)
	var etat := _etat_de(bilan, "soldat")
	v.v(String(etat.cession.get("sortie", "")) == "ceder",
		"pre-condition : il doit d'abord CEDER au chef -- sans quoi c'est la resistance " +
		"qui retirerait l'entree, pas le lien")
	var motifs: Array = []
	for retire in etat.retires:
		motifs.append(String(retire.motif))
	v.v(motifs.has(Banc.MOTIF_REFUS_LIEN),
		"l'entree de l'ordre doit etre RETIREE de resultats pour cause de lien (motifs : %s)" % [motifs])
	v.v(String(etat.verbe) != "tuer",
		"le soldat ne doit PAS tuer (verbe obtenu : '%s')" % String(etat.verbe))
	v.v(String(etat.verbe) != "",
		"et il doit faire AUTRE CHOSE, jamais rien : un refus n'est pas une scene vide (verbe '%s' sur '%s')"
			% [String(etat.verbe), String(etat.cible)])

	# L'ENNEMI, lui, n'a aucun lien vers la cible : son entree passe le gate du
	# lien sans probleme -- et tombe sur un AUTRE gate. Deux refus, deux
	# raisons, jamais confondues.
	var etat_ennemi := _etat_de(bilan, "ennemi")
	var motifs_ennemi: Array = []
	for retire in etat_ennemi.retires:
		motifs_ennemi.append(String(retire.motif))
	v.v(not motifs_ennemi.has(Banc.MOTIF_REFUS_LIEN),
		"l'ennemi, sans lien vers la cible, ne doit pas refuser POUR CETTE RAISON (motifs : %s)" % [motifs_ennemi])
	v.v(String(etat_ennemi.verbe) != "tuer",
		"mais il ne doit pas tuer non plus -- il resiste au chef (verbe '%s')" % String(etat_ennemi.verbe))

func _le_refus_non_force_ne_coute_aucun_grief(v) -> void:
	var config := _config()
	var scene := _scene_soldat_confiant(config)
	var soldat := _colon(scene, "soldat")
	_tourner(scene, Banc.MODE_SERVICE, Banc.ORDRE_DONNE, 3.0, config)
	v.v(Banc.charge_transgression(soldat, config) == 0.0,
		"refuser ne coute RIEN : le grief ne monte que si l'ordre est FORCE (charge %.3f)"
			% Banc.charge_transgression(soldat, config))
	v.v(not Banc.est_transgresseur(soldat, config),
		"et le marqueur de transgression ne doit pas etre pose")

func _le_refus_force_accumule_du_grief(v) -> void:
	var config := _config()
	var scene := _scene_soldat_confiant(config)
	var soldat := _colon(scene, "soldat")

	var bilan := _tourner(scene, Banc.MODE_SERVICE, Banc.ORDRE_FORCE, 0.5, config)
	var etat := _etat_de(bilan, "soldat")
	v.v(String(etat.verbe) == "tuer",
		"sous l'ordre FORCE, l'entree survit au gate du lien et le colon tue (verbe '%s')" % String(etat.verbe))
	v.v(bool(etat.transgresse), "et la decision doit etre marquee TRANSGRESSION")
	v.v(Banc.charge_transgression(soldat, config) > 0.0,
		"le grief de transgression doit MONTER (charge %.3f)" % Banc.charge_transgression(soldat, config))

	# Assez pour franchir le seuil du canal et poser le marqueur.
	_tourner(scene, Banc.MODE_SERVICE, Banc.ORDRE_FORCE, 2.0, config)
	v.v(Banc.est_transgresseur(soldat, config),
		"au-dela du seuil du canal, charge.gd doit poser '%s' (charge %.3f, seuil %.2f)" % [
			String(config.nom_marqueur_transgression), Banc.charge_transgression(soldat, config),
			float(config.canal_transgression.seuil)])

	# REVERSIBLE : l'ordre retombe, la cause disparait, la charge redescend et
	# charge.gd retire le marqueur de lui-meme.
	_tourner(scene, Banc.MODE_SERVICE, Banc.ORDRE_AUCUN, 20.0, config)
	v.v(not Banc.est_transgresseur(soldat, config),
		"l'ordre leve, charge.gd doit RETIRER le marqueur au franchissement descendant (charge %.3f)"
			% Banc.charge_transgression(soldat, config))

	# LE CANAL N'EST PAS PARTAGE entre colons : un canal recopie par reference
	# aurait fait basculer les quatre ensemble (bug reel ferme par
	# banc_commun.gd:resoudre_chantier).
	for autre in ["chef", "ami", "ennemi"]:
		v.v(Banc.charge_transgression(_colon(scene, autre), config) == 0.0,
			"le canal de '%s' doit rester intact -- il est DUPLIQUE par colon, jamais partage" % autre)

# ---------------------------------------------------------------------------
# Ligne 14 -- ceder ou resister
# ---------------------------------------------------------------------------

# LE GATE PAR LA GRANDEUR, et pas par un `if` : sans ordre, bifurcation.gd ne
# rend AUCUNE sortie parce que la grandeur vaut 0.0, donc aucun score n'est
# strictement positif. C'est l'idiome que le mecanisme annonce lui-meme.
func _aucune_cession_sans_ordre(v) -> void:
	var config := _config()
	var scene := _scene(config)
	var bilan := _tourner(scene, Banc.MODE_SERVICE, Banc.ORDRE_AUCUN, 6.0, config)
	for id in ["chef", "soldat", "ami", "ennemi"]:
		v.v(String(_etat_de(bilan, id).cession.get("sortie", "")) == "",
			"sans ordre, aucune sortie de bifurcation ne doit etre rendue pour '%s'" % id)
	# La cible de l'ordre n'en est jamais destinataire, meme ordre donne.
	var bilan_ordre := _tourner(scene, Banc.MODE_SERVICE, Banc.ORDRE_DONNE, 0.5, config)
	v.v(String(_etat_de(bilan_ordre, String(config.cible_ordre_id)).cession.get("sortie", "")) == "",
		"la cible de l'ordre n'en est pas destinataire : aucune cession pour elle")
	v.v(String(_etat_de(bilan_ordre, String(config.chef_id)).cession.get("sortie", "")) == "",
		"l'emetteur non plus : on ne cede pas a soi-meme")

func _le_colon_cede_au_chef_fort_et_aime(v) -> void:
	var config := _config()
	var scene := _scene_soldat_confiant(config)
	var soldat := _colon(scene, "soldat")
	var chef := _colon(scene, "chef")
	var cession := Banc.resoudre_cession(soldat, chef, config, _liens(), Banc.ORDRE_DONNE)
	v.v(String(cession.sortie) == "ceder",
		"un chef fort et aime obtient la cession (ceder %.3f contre resister %.3f)" % [
			float(cession.scores.ceder), float(cession.scores.resister)])
	# Le score, terme a terme, jamais un « ca passe » : c'est la formule de la
	# consigne, verifiee contre les nombres du disque.
	var attendu: float = float(config.poids_lien_cession) * Banc.score_net(soldat, "chef", config, _liens()) \
		+ float(config.poids_hierarchie_cession) * Banc.score_hierarchie(chef, config)
	v.v(abs(float(cession.scores.ceder) - attendu) < 0.0001,
		"le score de cession doit valoir poids_lien x net + poids_hierarchie x hierarchie(chef) " +
		"(%.4f attendu, %.4f obtenu)" % [attendu, float(cession.scores.ceder)])
	# Et le score de hierarchie lui-meme, terme a terme.
	var h: float = float(config.hierarchie.poids_masse) * float(chef.proprietes[String(config.nom_masse)]) \
		+ float(config.hierarchie.poids_force) * float(chef.proprietes[String(config.nom_force)])
	v.v(abs(Banc.score_hierarchie(chef, config) - h) < 0.0001,
		"le score de hierarchie doit valoir exactement poids_masse x masse + poids_force x force")

func _le_colon_resiste_au_chef_faible(v) -> void:
	var config := _config()
	var scene := _scene_soldat_confiant(config)
	var soldat := _colon(scene, "soldat")
	var chef := _colon(scene, "chef")
	# On affaiblit le chef, et RIEN d'autre : meme lien, meme confiance, meme
	# cout de conflit.
	chef.proprietes[String(config.nom_masse)] = 0.0
	chef.proprietes[String(config.nom_force)] = 0.0
	var cession := Banc.resoudre_cession(soldat, chef, config, _liens(), Banc.ORDRE_DONNE)
	v.v(String(cession.sortie) == "resister",
		"un chef FAIBLE se fait resister par le meme colon (ceder %.3f contre resister %.3f)" % [
			float(cession.scores.ceder), float(cession.scores.resister)])
	# Et la consequence sur la decision : l'entree de l'ordre est retiree pour
	# RESISTANCE, un motif different du refus par lien.
	var bruts := Banc.resultats_bruts(soldat, scene.menace, scene.ouvrages["soldat"],
		_colon(scene, String(config.cible_ordre_id)), config, Banc.ORDRE_DONNE)
	var filtre := Banc.filtrer_resultats(soldat, bruts, cession, config, _liens(), Banc.ORDRE_DONNE)
	var motifs: Array = []
	for retire in filtre.retires:
		motifs.append(String(retire.motif))
	v.v(motifs.has(Banc.MOTIF_RESISTE),
		"la resistance doit retirer l'entree de l'ordre, avec SON motif (motifs : %s)" % [motifs])

func _le_colon_resiste_au_chef_hai(v) -> void:
	var config := _config()
	var scene := _scene_soldat_confiant(config)
	var soldat := _colon(scene, "soldat")
	var chef := _colon(scene, "chef")
	v.v(String(Banc.resoudre_cession(soldat, chef, config, _liens(), Banc.ORDRE_DONNE).sortie) == "ceder",
		"pre-condition : il cede avant d'etre monte contre son chef")

	# On fait monter la HAINE du soldat envers son chef, et rien d'autre --
	# le chef garde sa masse, sa force, et le lien positif est intact. C'est le
	# SCORE NET qui bascule, et c'est tout le sujet de la ligne 2 : sans lui,
	# « un chef HAI se fait resister » ne serait observable nulle part.
	var marque := Banc.marque_paire(String(config.marques.lien_negatif), "chef")
	for i in range(200):
		Epigenetique.poser(soldat, marque, scene.paires)
	var cession := Banc.resoudre_cession(soldat, chef, config, _liens(), Banc.ORDRE_DONNE)
	v.v(String(cession.sortie) == "resister",
		"un chef HAI se fait resister (haine %.2f, ceder %.3f contre resister %.3f)" % [
			Banc.lien_negatif(soldat, "chef", config),
			float(cession.scores.ceder), float(cession.scores.resister)])
	v.v(Banc.lien_positif(soldat, "chef", _liens()) > 0.0,
		"et le lien POSITIF est reste intact : ce sont bien DEUX registres, pas un signe")

# ---------------------------------------------------------------------------
# Les verrous de doctrine
# ---------------------------------------------------------------------------

# lien_personnel.gd est POSITIF SEULEMENT, et ce chantier ne l'a pas change.
# Verrouille par le COMPORTEMENT (une magnitude negative ne survit pas un
# tick) plutot que par la lecture d'une ligne de source : c'est le fait qui
# compte, pas son orthographe.
func _lien_personnel_reste_positif_seulement(v) -> void:
	var colon: Dictionary = {"id": "sujet", "position": Vector3.ZERO, "proprietes": {"liens_personnels": {}}}
	LienPersonnel.poser(colon, "cible", -5.0)
	v.v(LienPersonnel.force(colon, "cible", _liens()) < 0.0,
		"pre-condition : poser() accepte une magnitude negative sans alarme")
	LienPersonnel.avancer(colon, 0.1, _liens())
	v.v(LienPersonnel.force(colon, "cible", _liens()) >= 0.0,
		"avancer() doit ramener toute valeur negative a 0.0 -- lien_personnel.gd est POSITIF " +
		"SEULEMENT, et c'est POUR CA que la haine vit dans un second registre")

# LA CADENCE, mesuree contre les nombres REELS de data/epigenetique.json et
# jamais recopies ici : resultat negatif deja paye TROIS fois dans le depot
# (accoutumance_froid, experience_combat, competence_forge) -- au-dela de
# cette borne, la marque est effacee entre deux poses et n'accumule JAMAIS
# rien, en silence, sans qu'aucun autre test ne rougisse.
func _la_cadence_reste_sous_la_borne_des_planchers(v) -> void:
	var config := _config()
	var catalogue := _epigenetique()
	var intervalle: float = float(config.intervalle_interaction_s)
	for role in config.marques:
		var base := String(config.marques[role])
		v.v(catalogue.has(base), "la marque '%s' doit exister dans data/epigenetique.json" % base)
		if not catalogue.has(base):
			continue
		var regle: Dictionary = catalogue[base]
		var taux: float = float(regle.taux_decroissance)
		v.v(taux > 0.0, "la marque '%s' doit DECROITRE (sinon ce n'est qu'un compteur monotone)" % base)
		if taux <= 0.0:
			continue
		var borne: float = (float(regle.modulateur_pose) - float(regle.plancher_suppression)) / taux
		v.v(intervalle < borne,
			"l'intervalle de pose (%.3f s) doit rester SOUS (modulateur_pose - plancher_suppression) / " % intervalle +
			"taux_decroissance = %.3f s pour '%s', sinon la marque n'accumule jamais rien" % [borne, base])
		v.v(float(regle.plancher_suppression) < float(regle.modulateur_pose),
			"le plancher de '%s' doit rester sous modulateur_pose" % base)

# Le catalogue PARTAGE de seuils est passe EN ENTIER : ses ~30 autres entrees
# doivent etre des chemins morts silencieux pour ces colons. Verrou POSITIF --
# le chantier « rupture + migration » ecrit en parallele dans le meme fichier,
# et rien ne doit deborder.
func _aucun_etat_parasite_du_catalogue_partage(v) -> void:
	var config := _config()
	var scene := _scene(config)
	_tourner(scene, Banc.MODE_SERVICE, Banc.ORDRE_AUCUN, 10.0, config)
	_tourner(scene, Banc.MODE_AGRESSION, Banc.ORDRE_FORCE, 10.0, config)
	var attendus := Banc.noms_etats(config)
	for colon in scene.colons:
		for etat in _actifs(colon):
			v.v(attendus.has(String(etat)),
				"aucun etat parasite ne doit se poser : '%s' trouve sur '%s' (attendus : %s)"
					% [String(etat), String(colon.id), attendus])

# Aucun nom de ce chantier ne doit avoir fui dans un fichier du coeur. C'est
# « le moteur ne connait que des verbes » (CLAUDE.md) rendu opposable, et
# c'est aussi la preuve la plus directe qu'aucun des quatorze fichiers cites
# par la consigne n'a ete touche pour faire marcher ce banc.
func _aucun_mecanisme_du_coeur_n_est_modifie(v) -> void:
	for nom in COEUR_INTOUCHE:
		var chemin := "res://scripts/%s.gd" % nom
		var source := FileAccess.get_file_as_string(chemin)
		v.v(source != "", "le fichier du coeur '%s' doit exister et etre lisible" % chemin)
		var minuscule := source.to_lower()
		for mot in VOCABULAIRE_DU_BANC:
			v.v(not minuscule.contains(mot),
				"'%s' contient '%s' -- un nom de ce chantier a fui dans le coeur" % [chemin, mot])

# ---------------------------------------------------------------------------
# Hors domaine -- le meme code, un vocabulaire entierement invente
# ---------------------------------------------------------------------------

# Aucun mot du jeu : ni colon, ni chef, ni confiance, ni tuer. Trois
# « thrums » qui se « murmurent », un qui « ecaille » les autres, et un
# « glyphe » a « dissoudre » sur consigne. Si une seule chaine etait ecrite en
# dur dans banc_social_paire.gd, ce cas ne pourrait pas passer.
func _config_hors_domaine() -> Dictionary:
	return {
		"chef_id": "thrum_vroque",
		"cible_ordre_id": "glyphe_vroque",
		"nom_confiance": "accord_vroque",
		"nom_dette_negative": "creance_vroque",
		"nom_masse": "densite_vroque",
		"nom_force": "tension_vroque",
		"nom_plafond_confiance": "plafond_vroque",
		"nom_cout_conflit": "friction_vroque",
		"nom_reference": "pivot_vroque",
		"nom_marqueur_transgression": "fele_vroque",
		"nom_canal_transgression": "ecaille_vroque",
		"etat_confiant_combattre": "accorde_vroque",
		"etat_confiant_obeir": "soude_vroque",
		"etat_rancunier": "creancier_vroque",
		"ref_seuil_combattre": "seuil_accord_vroque",
		"ref_seuil_obeir": "seuil_soudure_vroque",
		"ref_seuil_rancune": "seuil_creance_vroque",
		"marques": {
			"confiance": "murmure_vroque",
			"lien_negatif": "ecaillage_vroque",
			"service": "offrande_vroque",
		},
		"plafond_lien_negatif": 2.0,
		"plafond_service": 3.0,
		"portee_interaction": 500.0,
		"intervalle_interaction_s": 0.25,
		"seuil_attache": 1.0,
		"poids_lien_cession": 1.0,
		"poids_hierarchie_cession": 1.0,
		"hierarchie": {"poids_masse": 0.01, "poids_force": 0.2},
		"sorties_cession": ["ceder", "resister"],
		"saillance_menace": 2.0,
		"saillance_ouvrage": 1.0,
		"bonus_ordre": 4.0,
		"propriete_menace": "grince_vroque",
		"propriete_cible_ordre": "marque_vroque",
		"propriete_ouvrage": "chantier_vroque",
		"catalogue_local": {
			"grince_vroque": {"verbes": ["amortir_vroque"]},
			"marque_vroque": {"verbes": ["dissoudre_vroque"]},
			"chantier_vroque": {"verbes": ["tisser_vroque"]},
		},
		"poids_verbes_colon": {"amortir_vroque": 1.0, "dissoudre_vroque": 1.0, "tisser_vroque": 1.0},
		"forme_colon": {"seuil_ecrasement": 3.5, "gain_inertie": 0.1, "rayon_liaison": 0.0},
		"canal_transgression": {
			"charge": 0.0, "seuil": 1.0, "portee_charge": 0.0,
			"taux_decroissance": 0.5, "poser": {"fele_vroque": true},
		},
		"cout_transgression": 1.0,
		"menace": {"id": "grincement_vroque", "position": [0.0, 0.0, 0.0]},
		"colons": [
			{
				"id": "thrum_vroque", "position": [100.0, 0.0, 0.0], "ouvrage": [100.0, 60.0, 0.0],
				"masse": 85.0, "force": 9.0, "plafond_confiance": 0.9, "cout_conflit": 9.9,
				"reference_confiance": "echo_vroque", "liens_initiaux": {"echo_vroque": 0.8},
			},
			{
				"id": "echo_vroque", "position": [200.0, 0.0, 0.0], "ouvrage": [200.0, 60.0, 0.0],
				"masse": 78.0, "force": 7.0, "plafond_confiance": 1.0, "cout_conflit": 2.0,
				"reference_confiance": "thrum_vroque",
				"liens_initiaux": {"thrum_vroque": 0.9, "glyphe_vroque": 1.4},
			},
			{
				"id": "glyphe_vroque", "position": [300.0, 0.0, 0.0], "ouvrage": [300.0, 60.0, 0.0],
				"masse": 70.0, "force": 5.0, "plafond_confiance": 0.5, "cout_conflit": 4.0,
				"reference_confiance": "thrum_vroque", "liens_initiaux": {"echo_vroque": 1.4},
			},
		],
		"interactions": {
			"service": [
				{"source": "echo_vroque", "cible": "thrum_vroque", "genre": "temps_partage"},
				{"source": "thrum_vroque", "cible": "echo_vroque", "genre": "temps_partage"},
				{"source": "glyphe_vroque", "cible": "thrum_vroque", "genre": "temps_partage"},
				{"source": "thrum_vroque", "cible": "glyphe_vroque", "genre": "service"},
			],
			"agression": [
				{"source": "glyphe_vroque", "cible": "echo_vroque", "genre": "agression"},
			],
		},
	}

# Le catalogue de seuils est LOCAL ici -- au format EXACT du partage, passe
# tel quel a seuil_etat.gd (patron data/banc_psycho_social.json:seuils_locaux).
# Il ne touche pas data/seuils_etat.json : un domaine invente n'a rien a y
# faire.
func _seuils_hors_domaine() -> Dictionary:
	return {
		"seuil_accord_vroque": {"propriete_continue": "accord_vroque", "seuil": 0.20, "etat": "accorde_vroque"},
		"seuil_soudure_vroque": {"propriete_continue": "accord_vroque", "seuil": 0.70, "etat": "soude_vroque"},
		"seuil_creance_vroque": {"propriete_continue": "creance_vroque", "seuil": 1.0, "etat": "creancier_vroque"},
	}

# Le catalogue de marques est LOCAL lui aussi -- au format EXACT de
# data/epigenetique.json, dont catalogue_paires() derivera les entrees par
# paire. Un domaine invente n'a rien a faire dans le catalogue partage, et le
# fait que ce chemin marche prouve d'un coup DEUX choses : que le banc
# n'ecrit aucun nom de marque en dur, et que catalogue_paires() ne lit jamais
# le disque -- il ne fait que deriver ce qu'on lui donne.
func _epigenetique_hors_domaine() -> Dictionary:
	return {
		"murmure_vroque": {
			"cible": "accord_vroque", "modulateur_pose": 0.05,
			"taux_decroissance": 0.02, "plancher_suppression": 0.03,
		},
		"ecaillage_vroque": {
			"cible": "ecaille_vroque", "modulateur_pose": 0.08,
			"taux_decroissance": 0.03, "plancher_suppression": 0.04,
		},
		"offrande_vroque": {
			"cible": "creance_vroque", "modulateur_pose": 0.06,
			"taux_decroissance": 0.02, "plancher_suppression": 0.03,
		},
	}

func _aucun_nom_en_dur(v) -> void:
	var config := _config_hors_domaine()
	var seuils := _seuils_hors_domaine()
	var liens := _liens()
	var colons := Banc.construire_colons(config)
	var menace := Banc.construire_menace(config)
	var ouvrages := Banc.construire_ouvrages(config)
	var paires := Banc.catalogue_paires(config, colons, _epigenetique_hors_domaine())
	var monde = Banc.construire_monde(colons, menace, ouvrages.values(), Monde)

	var bilan: Dictionary = {}
	var restant := 8.0
	while restant > 0.0:
		bilan = Banc.avancer(colons, menace, ouvrages, "service", Banc.ORDRE_AUCUN,
			config, seuils, liens, paires, monde, DELTA)
		restant -= DELTA

	var echo := Banc.colon_par_id(colons, "echo_vroque")
	var glyphe := Banc.colon_par_id(colons, "glyphe_vroque")
	var thrum := Banc.colon_par_id(colons, "thrum_vroque")

	v.v(echo.proprietes.get("etats_actifs", []).has("soude_vroque"),
		"hors domaine : le second palier doit se poser sur un vocabulaire entierement invente")
	v.v(glyphe.proprietes.get("etats_actifs", []).has("accorde_vroque")
		and not glyphe.proprietes.get("etats_actifs", []).has("soude_vroque"),
		"hors domaine : l'escalier doit tenir -- premier palier oui, second non (plafond 0.5)")
	v.v(glyphe.proprietes.get("etats_actifs", []).has("creancier_vroque"),
		"hors domaine : la rancune doit se poser sur le beneficiaire (dette %.3f)"
			% Banc.dette_sociale(glyphe, thrum, config))

	# L'ordre, le refus par lien, puis la transgression forcee -- tout le
	# chemin de la ligne 11, sans un mot du jeu.
	restant = 0.5
	while restant > 0.0:
		bilan = Banc.avancer(colons, menace, ouvrages, "service", Banc.ORDRE_DONNE,
			config, seuils, liens, paires, monde, DELTA)
		restant -= DELTA
	var etat_echo := _etat_de(bilan, "echo_vroque")
	var motifs: Array = []
	for retire in etat_echo.retires:
		motifs.append(String(retire.motif))
	v.v(motifs.has(Banc.MOTIF_REFUS_LIEN),
		"hors domaine : le refus par lien doit retirer l'entree (motifs : %s)" % [motifs])
	v.v(String(etat_echo.verbe) == "amortir_vroque",
		"hors domaine : il doit se rabattre sur un verbe invente resolu par le catalogue local " +
		"(verbe obtenu '%s')" % String(etat_echo.verbe))

	restant = 2.0
	while restant > 0.0:
		bilan = Banc.avancer(colons, menace, ouvrages, "service", Banc.ORDRE_FORCE,
			config, seuils, liens, paires, monde, DELTA)
		restant -= DELTA
	v.v(String(_etat_de(bilan, "echo_vroque").verbe) == "dissoudre_vroque",
		"hors domaine : l'ordre force doit passer outre le lien (verbe '%s')"
			% String(_etat_de(bilan, "echo_vroque").verbe))
	v.v(bool(echo.proprietes.get("fele_vroque", false)),
		"hors domaine : charge.gd doit poser le marqueur de transgression invente (charge %.3f)"
			% Banc.charge_transgression(echo, config))
