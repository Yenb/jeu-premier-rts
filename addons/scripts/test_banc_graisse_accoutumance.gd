extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_graisse_accoutumance.gd
#
# Verrouille le CABLAGE de scripts/banc_graisse_accoutumance.gd (transfert
# reserve -> reserve SUR LA MEME ENTITE dans les deux sens, plafond de graisse,
# escalier famine -> mort_famine, accoutumance qui monte, decroit et allege le
# surcout thermique) -- jamais scripts/consommer.gd, scripts/depense.gd,
# scripts/seuil_etat.gd, scripts/etat_effectif.gd ni scripts/epigenetique.gd
# eux-memes, deja verrouilles par leurs propres tests.
#
# LES TROIS CATALOGUES SONT LUS SUR LE DISQUE (data/seuils_etat.json,
# data/etats.json, data/epigenetique.json) et la config du banc AUSSI
# (data/banc_graisse_accoutumance.json) : la calibration de ce chantier est
# precisement ce qui peut se casser en silence -- la lecon de banc_maladie, dont
# le canal ne contaminait JAMAIS personne pendant que son test restait vert
# faute de rejouer le JSON reel. Une fixture locale ne prouverait rien du chemin
# reel. Les seules fixtures de ce fichier sont celles du cas HORS DOMAINE, dont
# c'est tout l'objet.
#
# LE TICK N'EST JAMAIS RECONSTITUE ICI : ce fichier appelle
# BancGraisse.avancer_colon, la MEME fonction statique que _process appelle.
# Rejouer l'ordre a la main aurait laisse la scene et le test deriver l'un de
# l'autre sans qu'aucun ne rougisse.

const BancGraisse = preload("res://scripts/banc_graisse_accoutumance.gd")
const Temperature = preload("res://scripts/temperature.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")
const Epigenetique = preload("res://scripts/epigenetique.gd")
const Verif = preload("res://scripts/verif.gd")

const DELTA := 0.1
const TICKS_MAX := 4000

func _json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))

func _config() -> Dictionary:
	return _json("res://data/banc_graisse_accoutumance.json")

func _seuils() -> Dictionary:
	return _json("res://data/seuils_etat.json")

func _etats() -> Dictionary:
	return _json("res://data/etats.json")

func _epigenetique() -> Dictionary:
	return _json("res://data/epigenetique.json")

func _init() -> void:
	var v := Verif.new()
	_le_surplus_d_energie_va_dans_la_graisse(v)
	_sous_le_seuil_de_surplus_rien_ne_part_en_graisse(v)
	_la_graisse_ne_depasse_jamais_sa_capacite(v)
	_en_famine_la_graisse_est_consommee_et_l_energie_tenue(v)
	_le_transfert_sur_soi_meme_est_conserve_meme_en_demandant_trop(v)
	_mort_famine_est_posee_quand_la_graisse_est_epuisee(v)
	_mort_famine_n_est_jamais_posee_au_premier_tick(v)
	_un_mort_ne_brule_ni_ne_transfere_plus_rien(v)
	_l_accoutumance_reduit_le_surcout_thermique(v)
	_l_accoutumance_monte_sous_exposition_et_decroit_quand_elle_cesse(v)
	_l_intervalle_de_pose_du_disque_laisse_la_marque_survivre(v)
	_le_plafond_empeche_le_surcout_de_devenir_negatif(v)
	_sans_accoutumance_le_colon_meurt_plus_vite(v)
	_la_zone_froide_du_disque_mord_bien_au_centre(v)
	_les_miroirs_du_banc_correspondent_aux_entrees_du_disque(v)
	_les_seuils_du_disque_disent_bien_reserve_vide(v)
	_hors_domaine_le_meme_code_traverse_un_vocabulaire_invente(v)

	if v.echecs() > 0:
		print("ECHEC: %d verification(s) en echec" % v.echecs())
		quit(1)
	else:
		print("OK: banc_graisse_accoutumance -- graisse (surplus, plafond, famine, conservation, mort) et accoutumance (montee, decroissance, allegement du surcout, plafond)")
		quit(0)

# ---- Outils de scenario -------------------------------------------------

# Temperature locale au coeur de la zone froide, calculee par le mecanisme du
# coeur depuis les nombres REELS du disque -- jamais une constante recopiee ici.
func _temp_froide(config: Dictionary) -> float:
	var zone: Dictionary = config.zone_froide
	var p: Array = zone.position
	return Temperature.locale(
		Vector3(float(p[0]), float(p[1]), float(p[2])),
		BancGraisse.sources_temperature(config, true),
		_json("res://data/temperature.json"))

func _reserve(colon: Dictionary, nom: String) -> float:
	return float(colon.proprietes.reserves[nom].reserve)

func _poser_reserve(colon: Dictionary, nom: String, valeur: float) -> void:
	colon.proprietes.reserves[nom]["reserve"] = valeur

func _modulateur(colon: Dictionary, config: Dictionary) -> float:
	var marques: Dictionary = colon.proprietes.get("marques_epigenetiques", {})
	return float(marques.get(String(config.nom_marque_accoutumance), {}).get("modulateur", 0.0))

# Rejoue N ticks du BANC REEL (avancer_colon, la fonction que _process appelle).
# Rend { ticks, horloge } ; s'arrete des que "jusqu_a_mort" est demande et que la
# mort est la.
func _simuler(colon: Dictionary, nourriture: Dictionary, config: Dictionary, seuils: Dictionary, epi: Dictionary, temp_locale: float, nourriture_active: bool, ticks: int, jusqu_a_mort: bool) -> Dictionary:
	var monde: Array = [colon, nourriture]
	var horloge: float = 0.0
	var faits: int = 0
	for i in range(ticks):
		if jusqu_a_mort and BancGraisse.est_mort(colon, config):
			break
		var resultat: Dictionary = BancGraisse.avancer_colon(
			colon, nourriture, monde, DELTA, temp_locale,
			nourriture_active, horloge, config, seuils, epi)
		horloge = float(resultat.horloge)
		faits += 1
	return {"ticks": faits, "horloge": horloge}

# ---- Cas ---------------------------------------------------------------

func _le_surplus_d_energie_va_dans_la_graisse(v) -> void:
	var config := _config()
	var colon := BancGraisse.construire_colon(config)
	var nourriture := BancGraisse.construire_nourriture(config)
	var graisse_avant := _reserve(colon, String(config.nom_reserve_graisse))
	v.v(graisse_avant == 0.0, "le colon doit naitre sans graisse, recu %f" % graisse_avant)

	# Sans froid (temperature locale = confort) : seul le metabolisme brule, la
	# demonstration du surplus n'est pas polluee par le thermique.
	_simuler(colon, nourriture, config, _seuils(), _epigenetique(), float(config.temp_cible), true, 20, false)

	var graisse := _reserve(colon, String(config.nom_reserve_graisse))
	var energie := _reserve(colon, String(config.nom_reserve_energie))
	v.v(graisse > 0.0, "manger au-dessus du seuil de surplus doit remplir la graisse, recu %f" % graisse)
	v.v(energie > float(config.seuil_surplus),
		"l'energie doit rester au-dessus du seuil de surplus tant que la nourriture coule, recu %f" % energie)
	# Le transfert est borne par taux_surplus_max : jamais plus que ce que le
	# catalogue de banc autorise par seconde.
	var maximum: float = float(config.taux_surplus_max) * DELTA * 20.0
	v.v(graisse <= maximum + 0.0001,
		"la graisse gagnee ne doit jamais depasser taux_surplus_max x duree (%f), recu %f" % [maximum, graisse])

func _sous_le_seuil_de_surplus_rien_ne_part_en_graisse(v) -> void:
	var config := _config()
	var colon := BancGraisse.construire_colon(config)
	_poser_reserve(colon, String(config.nom_reserve_energie), float(config.seuil_surplus))
	var quantite: float = BancGraisse.transferer_surplus(colon, config, DELTA)
	v.v(quantite == 0.0,
		"a l'exact seuil de surplus, rien ne doit partir en graisse, recu %f" % quantite)
	_poser_reserve(colon, String(config.nom_reserve_energie), float(config.seuil_surplus) - 10.0)
	v.v(BancGraisse.transferer_surplus(colon, config, DELTA) == 0.0,
		"sous le seuil de surplus, rien ne doit jamais partir en graisse")
	v.v(_reserve(colon, String(config.nom_reserve_graisse)) == 0.0,
		"la graisse doit etre restee intacte")

func _la_graisse_ne_depasse_jamais_sa_capacite(v) -> void:
	var config := _config()
	var colon := BancGraisse.construire_colon(config)
	var nourriture := BancGraisse.construire_nourriture(config)
	var capacite := float(config.capacite_graisse)

	_simuler(colon, nourriture, config, _seuils(), _epigenetique(), float(config.temp_cible), true, 600, false)
	var graisse := _reserve(colon, String(config.nom_reserve_graisse))
	v.v(graisse <= capacite + 0.0001,
		"la graisse ne doit JAMAIS depasser sa capacite %f, recu %f" % [capacite, graisse])
	v.v(is_equal_approx(graisse, capacite),
		"apres une longue phase d'abondance la graisse doit etre PLEINE (%f), recu %f" % [capacite, graisse])
	# Contre-epreuve directe : une graisse deja pleine ne prend plus rien, meme
	# avec un surplus d'energie enorme.
	_poser_reserve(colon, String(config.nom_reserve_energie), 1000.0)
	v.v(BancGraisse.transferer_surplus(colon, config, DELTA) == 0.0,
		"graisse pleine : plus aucun transfert, quel que soit le surplus d'energie")

func _en_famine_la_graisse_est_consommee_et_l_energie_tenue(v) -> void:
	var config := _config()
	var colon := BancGraisse.construire_colon(config)
	var nourriture := BancGraisse.construire_nourriture(config)
	_poser_reserve(colon, String(config.nom_reserve_energie), 0.0)
	_poser_reserve(colon, String(config.nom_reserve_graisse), 20.0)

	# Premier tick : les miroirs et seuil_etat.gd posent 'famine'.
	_simuler(colon, nourriture, config, _seuils(), _epigenetique(), _temp_froide(config), false, 1, false)
	v.v(BancGraisse.est_famine(colon, config),
		"energie a zero : 'famine' doit etre posee par seuil_etat.gd des le premier tick, etats %s"
			% str(colon.proprietes.etats_actifs))

	_simuler(colon, nourriture, config, _seuils(), _epigenetique(), _temp_froide(config), false, 30, false)
	var graisse := _reserve(colon, String(config.nom_reserve_graisse))
	v.v(graisse < 20.0 and graisse > 0.0,
		"en famine la graisse doit descendre (et pas d'un coup), recu %f" % graisse)
	# L'energie ne remonte jamais au-dessus de rien : la graisse ne fait que
	# remplacer ce qui brule (taux_famine_effectif = cout courant).
	var energie := _reserve(colon, String(config.nom_reserve_energie))
	v.v(energie < 1.0,
		"la graisse remplace la combustion, elle ne recharge jamais le colon, recu %f d'energie" % energie)
	v.v(BancGraisse.est_famine(colon, config),
		"'famine' ne doit pas clignoter tant que la graisse alimente juste la combustion")

func _le_transfert_sur_soi_meme_est_conserve_meme_en_demandant_trop(v) -> void:
	# LE cas que ce chantier existe pour prouver : consommer.gd appele avec la
	# MEME entite comme source ET comme receveur, SANS pre-bornage, avec une
	# demande qui depasse largement la reserve. Contre-epreuve de la correction
	# de consommer.gd (credit borne a la quantite reellement retiree).
	var config := _config()
	var colon := BancGraisse.construire_colon(config)
	_poser_reserve(colon, String(config.nom_reserve_energie), 0.0)
	_poser_reserve(colon, String(config.nom_reserve_graisse), 0.5)
	colon.proprietes.etats_actifs = [String(config.nom_etat_famine)]
	# Le surcout doit etre pose pour que taux_famine_effectif ait un cout a lire.
	BancGraisse.poser_surcout_action(colon, -50.0, config)

	var total_avant: float = _reserve(colon, String(config.nom_reserve_energie)) + _reserve(colon, String(config.nom_reserve_graisse))
	var demande: float = BancGraisse.taux_famine_effectif(colon, config) * 5.0
	v.v(demande > 0.5,
		"le scenario n'a de sens que si la demande (%f) depasse la graisse (0.5)" % demande)

	var quantite: float = BancGraisse.transferer_famine(colon, config, 5.0)
	var total_apres: float = _reserve(colon, String(config.nom_reserve_energie)) + _reserve(colon, String(config.nom_reserve_graisse))
	v.v(is_equal_approx(total_avant, total_apres),
		"energie + graisse doit etre invariante (avant %f, apres %f) -- demander plus que la graisse ne possede ne doit creer AUCUNE energie" % [total_avant, total_apres])
	v.v(is_equal_approx(quantite, 0.5),
		"la quantite transferee doit valoir la graisse reellement disponible (0.5), recu %f" % quantite)
	v.v(_reserve(colon, String(config.nom_reserve_graisse)) == 0.0,
		"la graisse doit etre exactement vide, jamais negative")

	# Meme invariance dans l'autre sens (energie -> graisse), avec un surplus
	# plus petit que ce que le taux demanderait.
	var autre := BancGraisse.construire_colon(config)
	_poser_reserve(autre, String(config.nom_reserve_energie), float(config.seuil_surplus) + 0.2)
	var avant2: float = _reserve(autre, String(config.nom_reserve_energie)) + _reserve(autre, String(config.nom_reserve_graisse))
	BancGraisse.transferer_surplus(autre, config, 5.0)
	var apres2: float = _reserve(autre, String(config.nom_reserve_energie)) + _reserve(autre, String(config.nom_reserve_graisse))
	v.v(is_equal_approx(avant2, apres2),
		"sens energie -> graisse : la somme doit rester invariante (avant %f, apres %f)" % [avant2, apres2])
	v.v(is_equal_approx(_reserve(autre, String(config.nom_reserve_graisse)), 0.2),
		"seul le surplus REEL (0.2) doit partir, recu %f" % _reserve(autre, String(config.nom_reserve_graisse)))

func _mort_famine_est_posee_quand_la_graisse_est_epuisee(v) -> void:
	var config := _config()
	var colon := BancGraisse.construire_colon(config)
	var nourriture := BancGraisse.construire_nourriture(config)
	_poser_reserve(colon, String(config.nom_reserve_energie), 0.0)
	_poser_reserve(colon, String(config.nom_reserve_graisse), 3.0)

	var resultat := _simuler(colon, nourriture, config, _seuils(), _epigenetique(), _temp_froide(config), false, TICKS_MAX, true)
	v.v(BancGraisse.est_mort(colon, config),
		"la graisse epuisee en famine doit poser 'mort_famine', etats %s apres %d ticks"
			% [str(colon.proprietes.etats_actifs), int(resultat.ticks)])
	v.v(_reserve(colon, String(config.nom_reserve_graisse)) < 1.0,
		"a la mort, la graisse doit etre a peu pres vide, recu %f" % _reserve(colon, String(config.nom_reserve_graisse)))
	# L'ECRASEMENT gagne sur tout modulateur (etat_effectif.gd) : c'est la preuve
	# visible que 'mort_famine' est bien une fin d'escalier, pas un marqueur.
	var vitesse: float = BancGraisse.vitesse_effective(colon, config, _etats())
	v.v(vitesse == 0.0,
		"'mort_famine' doit ECRASER la vitesse a 0.0 quels que soient les autres etats, recu %f" % vitesse)

func _mort_famine_n_est_jamais_posee_au_premier_tick(v) -> void:
	# Le colon nait SANS graisse : sans le gate 'famine' sur le miroir
	# manque_graisse, il serait declare mort de faim avant d'avoir vecu.
	var config := _config()
	var colon := BancGraisse.construire_colon(config)
	var nourriture := BancGraisse.construire_nourriture(config)
	_simuler(colon, nourriture, config, _seuils(), _epigenetique(), _temp_froide(config), true, 1, false)
	v.v(not BancGraisse.est_mort(colon, config),
		"un colon neuf, sans graisse mais plein d'energie, ne doit JAMAIS naitre mort, etats %s"
			% str(colon.proprietes.etats_actifs))
	v.v(float(colon.proprietes[String(config.nom_manque_graisse)]) == 0.0,
		"hors famine, le miroir de graisse doit rester a 0.0, recu %f"
			% float(colon.proprietes[String(config.nom_manque_graisse)]))
	# Et le gate s'ouvre bien quand la famine arrive.
	_poser_reserve(colon, String(config.nom_reserve_energie), 0.0)
	_simuler(colon, nourriture, config, _seuils(), _epigenetique(), _temp_froide(config), false, 2, false)
	v.v(float(colon.proprietes[String(config.nom_manque_graisse)]) > 0.0,
		"en famine, le miroir de graisse doit enfin porter le manque reel")

func _un_mort_ne_brule_ni_ne_transfere_plus_rien(v) -> void:
	# LA MORT DOIT VENIR DE LA CHAINE, jamais d'un etat pose a la main : un
	# 'mort_famine' ecrit directement dans etats_actifs est RETIRE par
	# seuil_etat.gd au premier passage (son miroir vaut 0.0 hors famine, donc le
	# franchissement s'inverse) -- comportement correct du mecanisme, constate en
	# ecrivant ce test, et qui dit exactement pourquoi la mort de ce banc est
	# tenue par la CONJONCTION des deux entrees et non par une ecriture directe.
	var config := _config()
	var colon := BancGraisse.construire_colon(config)
	var nourriture := BancGraisse.construire_nourriture(config)
	_poser_reserve(colon, String(config.nom_reserve_energie), 0.0)
	_poser_reserve(colon, String(config.nom_reserve_graisse), 2.0)
	_simuler(colon, nourriture, config, _seuils(), _epigenetique(), _temp_froide(config), false, TICKS_MAX, true)
	v.v(BancGraisse.est_mort(colon, config),
		"le scenario n'a de sens que si le colon est reellement mort, etats %s" % str(colon.proprietes.etats_actifs))

	var energie_mort := _reserve(colon, String(config.nom_reserve_energie))
	var graisse_mort := _reserve(colon, String(config.nom_reserve_graisse))
	# Nourriture REMISE : un mort ne mange pas non plus.
	_simuler(colon, nourriture, config, _seuils(), _epigenetique(), _temp_froide(config), true, 50, false)
	v.v(_reserve(colon, String(config.nom_reserve_energie)) == energie_mort,
		"un mort ne brule ni ne mange plus rien, energie %f puis %f" % [energie_mort, _reserve(colon, String(config.nom_reserve_energie))])
	v.v(_reserve(colon, String(config.nom_reserve_graisse)) == graisse_mort,
		"un mort ne transfere plus rien, graisse %f puis %f" % [graisse_mort, _reserve(colon, String(config.nom_reserve_graisse))])
	v.v(BancGraisse.est_mort(colon, config),
		"la mort ne doit pas se retirer toute seule : le miroir reste ouvert tant que la famine dure")

func _l_accoutumance_reduit_le_surcout_thermique(v) -> void:
	var config := _config()
	var froid := 30.0
	var nu: float = BancGraisse.surcout_thermo(froid, 0.0, config)
	var accoutume: float = BancGraisse.surcout_thermo(froid, 0.5, config)
	v.v(accoutume < nu,
		"une accoutumance non nulle doit REDUIRE le surcout thermique (%f vs %f)" % [accoutume, nu])
	v.v(is_equal_approx(accoutume, nu * 0.5),
		"le modulateur doit s'appliquer en (1 - modulateur), attendu %f, recu %f" % [nu * 0.5, accoutume])

	# Et le meme effet a travers le canal reel, pas seulement l'arithmetique.
	var config_temoin := _config()
	var expose := BancGraisse.construire_colon(config)
	var temoin := BancGraisse.construire_colon(config_temoin)
	expose.proprietes.marques_epigenetiques[String(config.nom_marque_accoutumance)] = {"modulateur": 0.4, "age_marque": 0.0}
	var temp := _temp_froide(config)
	var d_expose: Dictionary = BancGraisse.poser_surcout_action(expose, temp, config)
	var d_temoin: Dictionary = BancGraisse.poser_surcout_action(temoin, temp, config_temoin)
	v.v(float(d_expose.thermo) < float(d_temoin.thermo),
		"le colon accoutume doit ecrire un surcout_action plus faible (%f vs %f)" % [float(d_expose.thermo), float(d_temoin.thermo)])
	v.v(float(expose.proprietes.reserves[String(config.nom_reserve_energie)].surcout_action) == float(d_expose.thermo),
		"poser_surcout_action doit ecrire dans le canal exactement ce qu'il rend")

func _l_accoutumance_monte_sous_exposition_et_decroit_quand_elle_cesse(v) -> void:
	var config := _config()
	var colon := BancGraisse.construire_colon(config)
	var nourriture := BancGraisse.construire_nourriture(config)
	var froid := _temp_froide(config)

	_simuler(colon, nourriture, config, _seuils(), _epigenetique(), froid, true, 100, false)
	var apres_10s := _modulateur(colon, config)
	v.v(apres_10s > 0.0,
		"10 s de froid doivent avoir depose une marque, recu %f" % apres_10s)

	_simuler(colon, nourriture, config, _seuils(), _epigenetique(), froid, true, 100, false)
	var apres_20s := _modulateur(colon, config)
	v.v(apres_20s > apres_10s,
		"la marque doit CONTINUER de monter tant que l'exposition dure (%f puis %f)" % [apres_10s, apres_20s])

	# Exposition coupee : temperature locale = confort, froid_ressenti nul.
	_simuler(colon, nourriture, config, _seuils(), _epigenetique(), float(config.temp_cible), true, 100, false)
	var apres_coupure := _modulateur(colon, config)
	v.v(apres_coupure < apres_20s,
		"la marque doit DECROITRE quand l'exposition cesse (%f puis %f)" % [apres_20s, apres_coupure])
	v.v(apres_coupure > 0.0,
		"la decroissance est lente : 10 s sans froid ne doivent pas effacer une marque bien installee, recu %f" % apres_coupure)

func _l_intervalle_de_pose_du_disque_laisse_la_marque_survivre(v) -> void:
	# CONTRAINTE DE CADENCE trouvee en ecrivant ce chantier : une marque qui
	# vient d'etre posee vaut modulateur_pose et est RETIREE par epigenetique.gd
	# des qu'elle passe sous plancher_suppression. Un intervalle de pose trop
	# long efface donc la marque entre deux poses -- elle n'accumule jamais rien,
	# et rien d'autre ne rougit.
	var config := _config()
	var epi := _epigenetique()
	var regle: Dictionary = epi[String(config.nom_marque_accoutumance)]
	var marge: float = float(regle.modulateur_pose) - float(regle.plancher_suppression)
	var survie: float = marge / float(regle.taux_decroissance)
	var intervalle: float = float(config.intervalle_pose_accoutumance_s)
	v.v(marge > 0.0,
		"plancher_suppression (%f) doit rester SOUS modulateur_pose (%f)" % [float(regle.plancher_suppression), float(regle.modulateur_pose)])
	v.v(intervalle < survie,
		"l'intervalle de pose (%f s) doit rester sous la duree de survie d'une marque fraiche (%f s), sinon elle est effacee entre deux poses" % [intervalle, survie])

	# Preuve par le comportement, pas seulement par l'inegalite : 30 s de froid
	# doivent laisser une marque nettement au-dessus d'une seule pose.
	var colon := BancGraisse.construire_colon(config)
	var nourriture := BancGraisse.construire_nourriture(config)
	_simuler(colon, nourriture, config, _seuils(), epi, _temp_froide(config), true, 300, false)
	v.v(_modulateur(colon, config) > float(regle.modulateur_pose) * 5.0,
		"30 s d'exposition doivent ACCUMULER, pas se reduire a la derniere pose, recu %f" % _modulateur(colon, config))

	# CONTRE-EPREUVE : le meme code avec un intervalle trop long n'accumule
	# jamais rien. C'est le resultat negatif que la calibration evite.
	var config_lent := _config()
	config_lent["intervalle_pose_accoutumance_s"] = survie + 1.0
	var colon_lent := BancGraisse.construire_colon(config_lent)
	var nourriture_lent := BancGraisse.construire_nourriture(config_lent)
	_simuler(colon_lent, nourriture_lent, config_lent, _seuils(), epi, _temp_froide(config_lent), true, 300, false)
	v.v(_modulateur(colon_lent, config_lent) <= float(regle.modulateur_pose) + 0.0001,
		"contre-epreuve : un intervalle superieur a la survie de la marque ne doit JAMAIS accumuler, recu %f" % _modulateur(colon_lent, config_lent))

func _le_plafond_empeche_le_surcout_de_devenir_negatif(v) -> void:
	# epigenetique.gd n'a AUCUNE borne haute. Sans le plafond du cablage, un
	# modulateur au-dela de 1.0 rendrait (1 - modulateur) negatif : le froid
	# RECHARGERAIT le colon.
	var config := _config()
	var colon := BancGraisse.construire_colon(config)
	colon.proprietes.marques_epigenetiques[String(config.nom_marque_accoutumance)] = {"modulateur": 5.0, "age_marque": 0.0}
	var module: float = BancGraisse.modulateur_accoutumance(colon, config)
	v.v(module == float(config.plafond_accoutumance),
		"un modulateur emballe doit etre borne au plafond %f, recu %f" % [float(config.plafond_accoutumance), module])

	var decomposition: Dictionary = BancGraisse.poser_surcout_action(colon, _temp_froide(config), config)
	v.v(float(decomposition.thermo) > 0.0,
		"le surcout thermique ne doit JAMAIS devenir negatif (le froid ne recharge personne), recu %f" % float(decomposition.thermo))
	v.v(float(decomposition.thermo) < float(decomposition.brut),
		"il doit rester strictement plus faible que le surcout brut")
	v.v(float(config.plafond_accoutumance) < 1.0,
		"le plafond doit rester sous 1.0 : a 1.0 le froid deviendrait gratuit, au-dela il rechargerait")

func _sans_accoutumance_le_colon_meurt_plus_vite(v) -> void:
	var config := _config()
	# Temoin : MEME code, MEME catalogue, plafond d'accoutumance a zero -- la
	# marque est toujours posee et decrue par epigenetique.gd, elle ne module
	# simplement plus rien. Isole l'effet sans toucher au catalogue partage.
	var config_temoin := _config()
	config_temoin["plafond_accoutumance"] = 0.0

	var seuils := _seuils()
	var epi := _epigenetique()
	var froid := _temp_froide(config)

	var endurci := BancGraisse.construire_colon(config)
	var nourriture_a := BancGraisse.construire_nourriture(config)
	_poser_reserve(endurci, String(config.nom_reserve_graisse), float(config.capacite_graisse))
	var temoin := BancGraisse.construire_colon(config_temoin)
	var nourriture_b := BancGraisse.construire_nourriture(config_temoin)
	_poser_reserve(temoin, String(config_temoin.nom_reserve_graisse), float(config_temoin.capacite_graisse))

	var vie_endurci: int = int(_simuler(endurci, nourriture_a, config, seuils, epi, froid, false, TICKS_MAX, true).ticks)
	var vie_temoin: int = int(_simuler(temoin, nourriture_b, config_temoin, seuils, epi, froid, false, TICKS_MAX, true).ticks)

	v.v(BancGraisse.est_mort(endurci, config) and BancGraisse.est_mort(temoin, config_temoin),
		"les deux colons doivent finir par mourir de faim (endurci %d ticks, temoin %d ticks)" % [vie_endurci, vie_temoin])
	v.v(vie_temoin < vie_endurci,
		"sans accoutumance, le colon doit mourir STRICTEMENT plus vite (temoin %d ticks, endurci %d ticks)" % [vie_temoin, vie_endurci])
	v.v(_modulateur(endurci, config) > 0.0,
		"le colon endurci doit finir sa vie avec une marque installee, recu %f" % _modulateur(endurci, config))

func _la_zone_froide_du_disque_mord_bien_au_centre(v) -> void:
	# La calibration du banc repose entierement sur ce nombre. Le verifier par le
	# MECANISME (temperature.gd) et non par une constante recopiee.
	var config := _config()
	var froid_local := _temp_froide(config)
	var ressenti := BancGraisse.froid_ressenti(froid_local, float(config.temp_cible))
	v.v(ressenti > 0.0,
		"la zone froide du disque doit reellement mordre au centre, froid ressenti %f" % ressenti)
	var p: Array = config.position_colon
	var q: Array = config.zone_froide.position
	v.v(is_equal_approx(float(p[0]), float(q[0])) and is_equal_approx(float(p[1]), float(q[1])),
		"le colon doit etre pose au centre exact de la zone, sinon la calibration ecrite en donnee ne vaut plus rien")
	# Source coupee : aucun froid du tout, sinon le clic droit ne couperait rien.
	var ambiante := Temperature.locale(
		Vector3(float(p[0]), float(p[1]), 0.0),
		BancGraisse.sources_temperature(config, false),
		_json("res://data/temperature.json"))
	v.v(BancGraisse.froid_ressenti(ambiante, float(config.temp_cible)) == 0.0,
		"source coupee : le froid ressenti doit tomber a zero, recu %f" % BancGraisse.froid_ressenti(ambiante, float(config.temp_cible)))

func _les_miroirs_du_banc_correspondent_aux_entrees_du_disque(v) -> void:
	var config := _config()
	var seuils := _seuils()
	var etats := _etats()

	var ref_famine := String(config.ref_seuil_famine)
	var ref_mort := String(config.ref_seuil_mort_famine)
	v.v(seuils.has(ref_famine) and seuils.has(ref_mort),
		"data/seuils_etat.json doit porter les entrees '%s' et '%s'" % [ref_famine, ref_mort])
	if not (seuils.has(ref_famine) and seuils.has(ref_mort)):
		return
	v.v(String(seuils[ref_famine].propriete_continue) == String(config.nom_manque_energie),
		"le miroir du banc et la propriete comparee par '%s' doivent etre le MEME nom" % ref_famine)
	v.v(String(seuils[ref_mort].propriete_continue) == String(config.nom_manque_graisse),
		"le miroir du banc et la propriete comparee par '%s' doivent etre le MEME nom" % ref_mort)
	v.v(String(seuils[ref_famine].etat) == String(config.nom_etat_famine),
		"l'etat pose par '%s' et celui que le banc lit doivent etre le MEME nom" % ref_famine)
	v.v(String(seuils[ref_mort].etat) == String(config.nom_etat_mort_famine),
		"l'etat pose par '%s' et celui que le banc lit doivent etre le MEME nom" % ref_mort)

	v.v(etats.has(String(config.nom_etat_famine)) and etats.has(String(config.nom_etat_mort_famine)),
		"data/etats.json doit porter les deux etats de ce chantier")
	if etats.has(String(config.nom_etat_famine)):
		v.v(etats[String(config.nom_etat_famine)].effets.is_empty(),
			"'famine' est un MARQUEUR de gate : sa liste d'effets doit rester vide")
	if etats.has(String(config.nom_etat_mort_famine)):
		var effets: Array = etats[String(config.nom_etat_mort_famine)].effets
		v.v(effets.size() == 1 and String(effets[0].mode) == "ecraser" and float(effets[0].valeur) == 0.0,
			"'mort_famine' doit ECRASER (et non moduler) sa propriete a 0.0")

	v.v(_epigenetique().has(String(config.nom_marque_accoutumance)),
		"data/epigenetique.json doit porter la marque '%s'" % String(config.nom_marque_accoutumance))

func _les_seuils_du_disque_disent_bien_reserve_vide(v) -> void:
	var config := _config()
	var seuils := _seuils()
	var seuil_famine := BancGraisse.seuil_de(seuils, String(config.ref_seuil_famine))
	var seuil_mort := BancGraisse.seuil_de(seuils, String(config.ref_seuil_mort_famine))
	var reste_energie := float(config.capacite_energie) - seuil_famine
	var reste_graisse := float(config.capacite_graisse) - seuil_mort
	v.v(reste_energie > 0.0 and reste_energie <= 2.0,
		"le seuil de famine doit dire « reserve vide » : capacite %f - seuil %f = %f, attendu dans ]0, 2]"
			% [float(config.capacite_energie), seuil_famine, reste_energie])
	v.v(reste_graisse > 0.0 and reste_graisse <= 2.0,
		"le seuil de mort doit dire « graisse vide » : capacite %f - seuil %f = %f, attendu dans ]0, 2]"
			% [float(config.capacite_graisse), seuil_mort, reste_graisse])
	v.v(float(config.seuil_surplus) < float(config.capacite_energie),
		"le seuil de surplus doit rester sous la capacite, sinon rien ne part jamais en graisse")

func _hors_domaine_le_meme_code_traverse_un_vocabulaire_invente(v) -> void:
	# PREUVE que le cablage ne porte aucun nom en dur : meme code, vocabulaire
	# entierement invente, catalogues locaux. Rien de ce qui suit n'existe dans
	# le depot.
	var config := _config()
	config["nom_reserve_energie"] = "flux_vital"
	config["nom_reserve_graisse"] = "depot_lipide"
	config["nom_reserve_nourriture"] = "substrat"
	config["nom_vitesse"] = "cadence"
	config["nom_manque_energie"] = "deficit_vital"
	config["nom_manque_graisse"] = "deficit_depot"
	config["nom_froid_ressenti"] = "morsure_gel"
	config["nom_marque_accoutumance"] = "endurcissement_gel"
	config["nom_etat_famine"] = "carence"
	config["nom_etat_mort_famine"] = "extinction_carence"

	var seuils := {
		"carence": {"propriete_continue": "deficit_vital", "seuil": 99.0, "etat": "carence"},
		"extinction_carence": {"propriete_continue": "deficit_depot", "seuil": 39.0, "etat": "extinction_carence"},
	}
	var etats := {
		"carence": {"effets": []},
		"extinction_carence": {"effets": [{"propriete": "cadence", "mode": "ecraser", "valeur": 0.0}]},
	}
	var epi := {
		"endurcissement_gel": {
			"cible": "cout_par_degre_froid",
			"modulateur_pose": 0.01,
			"taux_decroissance": 0.005,
			"plancher_suppression": 0.008,
		},
	}

	var colon := BancGraisse.construire_colon(config)
	var nourriture := BancGraisse.construire_nourriture(config)
	v.v(colon.proprietes.reserves.has("flux_vital") and colon.proprietes.reserves.has("depot_lipide"),
		"les reserves doivent porter les noms inventes, recu %s" % str(colon.proprietes.reserves.keys()))

	# Abondance : le depot se remplit.
	_simuler(colon, nourriture, config, seuils, epi, _temp_froide(config), true, 400, false)
	v.v(_reserve(colon, "depot_lipide") > 0.0,
		"le surplus doit remplir le depot invente, recu %f" % _reserve(colon, "depot_lipide"))
	v.v(float(colon.proprietes.get("endurcissement_gel_absent", 0.0)) == 0.0,
		"garde-fou : aucune cle parasite ne doit apparaitre")
	v.v(colon.proprietes.marques_epigenetiques.has("endurcissement_gel"),
		"la marque inventee doit avoir ete posee, recu %s" % str(colon.proprietes.marques_epigenetiques.keys()))

	# Disette : la carence puis l'extinction.
	var resultat := _simuler(colon, nourriture, config, seuils, epi, _temp_froide(config), false, TICKS_MAX, true)
	v.v(colon.proprietes.etats_actifs.has("carence"),
		"l'etat invente 'carence' doit avoir ete pose, etats %s" % str(colon.proprietes.etats_actifs))
	v.v(colon.proprietes.etats_actifs.has("extinction_carence"),
		"l'etat invente 'extinction_carence' doit avoir ete pose apres %d ticks, etats %s"
			% [int(resultat.ticks), str(colon.proprietes.etats_actifs)])
	v.v(EtatEffectif.valeur(colon, "cadence", etats) == 0.0,
		"l'ecrasement invente doit ramener la propriete inventee a 0.0")
