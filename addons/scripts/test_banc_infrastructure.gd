extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_infrastructure.gd
#
# Verrouille le CABLAGE de scripts/banc_infrastructure.gd -- jamais
# scripts/depense.gd, scripts/consommer.gd, scripts/comptage.gd,
# scripts/seuil_etat.gd, scripts/etat_effectif.gd ni scripts/portee.gd
# eux-memes, deja verrouilles par leurs propres tests.
#
# LES QUATRE CATALOGUES SONT LUS SUR LE DISQUE (data/banc_infrastructure.json,
# data/comptages.json, data/seuils_combustible.json, data/etats.json) : le
# seuil qui repose facteur_vitesse a 1.0 est applique par depense.gd A PARTIR
# de data/seuils_combustible.json:usure_route, et la regle de comptage vit dans
# data/comptages.json -- les verifier depuis une fixture locale ne prouverait
# rien du chemin reel (patron test_banc_cratere.gd).
#
# DERNIER CAS, HORS DOMAINE : la meme classe traverse une ruche (silo a pollen,
# butineuses, sentier de vol) sans qu'une ligne de banc_infrastructure.gd ne
# change -- et l'etat de foule y MODULE reellement la cadence via
# etat_effectif.gd, ce qu'aucun nom de la config reelle ne fait. C'est ce cas,
# et lui seul, qui prouve que le piege de la ligne 7 est paye : sans l'appel a
# EtatEffectif.valeur dans poser_rythme_effectif, le facteur declare dans le
# catalogue d'etats serait inerte, en silence.

const Banc = preload("res://scripts/banc_infrastructure.gd")
const Depense = preload("res://scripts/depense.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

var _config: Dictionary = {}
var _comptages: Dictionary = {}
var _seuils: Dictionary = {}
var _etats: Dictionary = {}

func _init() -> void:
	_config = _charger("res://data/banc_infrastructure.json")
	_comptages = _charger("res://data/comptages.json")
	_seuils = _charger("res://data/seuils_combustible.json")
	_etats = _charger("res://data/etats.json")

	_les_trois_catalogues_du_disque_portent_les_ajouts()
	_le_grenier_plein_refuse_le_depot()
	_agrandir_le_grenier_leve_le_refus_sans_le_remplir()
	_l_objet_dehors_se_degrade_plus_vite_que_dedans()
	_le_comptage_ne_compte_que_les_colons_actifs()
	_la_coordination_baisse_le_rythme_au_dela_du_seuil()
	_la_route_accelere_le_colon()
	_la_route_usee_ne_donne_plus_de_bonus()
	_la_reparation_restaure_le_bonus_et_reste_reusable()
	_un_seul_ecrivain_pour_surcout_action_et_pour_rythme()
	_la_navette_conserve_la_matiere_sur_la_config_reelle()
	_le_meme_code_traverse_une_ruche()

	if verif.echecs() > 0:
		quit(1)
	else:
		print("OK: banc_infrastructure.gd refuse le depot dans un grenier plein sans faire " +
			"disparaitre la charge du porteur, degrade sept fois plus vite un lot laisse dehors " +
			"qu'un lot a l'abri, fait baisser le rythme effectif au-dela du seuil de coordination, " +
			"double la vitesse sur une route neuve, la perd quand depense.gd epuise la route, " +
			"la rend a la reparation, n'a qu'un ecrivain par canal de surcout_action et un seul " +
			"pour le rythme, conserve la matiere de bout en bout, et traverse un domaine invente " +
			"sans une ligne de code changee")
		quit(0)

# ---- Outils locaux ----

func _charger(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))

func _monde() -> Dictionary:
	return Banc.construire_monde(_config)

func _avancer_n(etat: Dictionary, pas: int, delta: float) -> Dictionary:
	var bilan: Dictionary = {}
	for i in range(pas):
		bilan = Banc.avancer(etat, _config, _comptages, _seuils, _etats, delta)
	return bilan

func _lot(etat: Dictionary, id: String) -> Dictionary:
	for lot in etat.lots:
		if lot.id == id:
			return lot
	return {}

func _poser_charge(colon: Dictionary, quantite: float, config: Dictionary) -> void:
	colon.proprietes.reserves[String(config.nom_reserve_charge)]["reserve"] = quantite

func _rythme_de(colon: Dictionary, config: Dictionary) -> float:
	return float(colon.proprietes.get(String(config.nom_rythme_effectif), 0.0))

# Total de matiere en circulation : tas + grenier + tout ce que les colons
# portent. consommer.gd etant conservatif par construction et aucun cout_base
# ne ponctionnant ces trois canaux, ce total doit rester INVARIANT.
func _matiere_totale(etat: Dictionary, config: Dictionary) -> float:
	var total := float(Banc.canal_stockage(etat.tas, config).get("reserve", 0.0))
	total += Banc.stock_grenier(etat.grenier, config)
	for colon in etat.colons:
		total += Banc.charge_de(colon, config)
	return total

# ---- Cas ----

func _les_trois_catalogues_du_disque_portent_les_ajouts() -> void:
	verif.v(_etats.has("encombre"),
		"data/etats.json doit porter 'encombre' (marqueur pose par le cablage sur un contenant plein)")
	verif.v(_etats.get("encombre", {}).get("effets", [1]).is_empty(),
		"'encombre' doit etre un MARQUEUR PUR (effets vides) -- un effet declare la serait inerte, aucun mecanisme ne lit cet etat")
	verif.v(_etats.has("surpeuplement"),
		"data/etats.json doit porter 'surpeuplement' (reutilise tel quel, pose ici par seuil_etat.gd)")
	verif.v(_etats.get("surpeuplement", {}).get("effets", [1]).is_empty(),
		"'surpeuplement' doit rester un MARQUEUR PUR : y declarer une modulation de 'rythme' ne produirait RIEN " +
		"(banc_commun.gd:agents_rythme lit rythme BRUTE) -- c'est le cablage qui compose")

	verif.v(_seuils.has("usure_route"),
		"data/seuils_combustible.json doit porter 'usure_route' -- test_lint_donnees.gd verifie CHAQUE seuils_ref contre ce SEUL fichier")
	var entree: Array = _seuils.get("usure_route", [])
	verif.v(entree.size() == 1, "'usure_route' doit porter exactement un seuil, recu %d" % entree.size())
	verif.v(entree.size() > 0 and is_equal_approx(float(entree[0].get("seuil", -1.0)), 0.0),
		"le seuil d'usure doit se declencher a reserve 0.0")
	verif.v(entree.size() > 0 and entree[0].get("poser", {}).has(String(_config.nom_facteur_vitesse)),
		"'usure_route' doit POSER '%s' -- c'est depense.gd qui retire le bonus, jamais le cablage" % String(_config.nom_facteur_vitesse))
	verif.v(entree.size() > 0 and is_equal_approx(float(entree[0].get("poser", {}).get(String(_config.nom_facteur_vitesse), -1.0)),
			float(_config.route.facteur_vitesse_use)),
		"la valeur reposee doit etre le NEUTRE de la multiplication (%.1f)" % float(_config.route.facteur_vitesse_use))

	verif.v(_comptages.has(String(_config.comptage_ref)),
		"data/comptages.json doit porter '%s' (referencee par comptage_ref)" % String(_config.comptage_ref))
	verif.v(_comptages.get(String(_config.comptage_ref), {}).get("mode", "") == "presente",
		"la regle doit etre en mode 'presente' -- le cablage RETIRE la cle sur un colon inactif, jamais un 'false' laisse en place")

func _le_grenier_plein_refuse_le_depot() -> void:
	var etat := _monde()
	var grenier: Dictionary = etat.grenier
	var canal := Banc.canal_stockage(grenier, _config)
	canal["reserve"] = Banc.capacite_grenier(grenier, _config)

	verif.v(Banc.est_plein(grenier, _config),
		"reserve EXACTEMENT egale a la capacite : le grenier doit etre plein (comparaison >=, jamais >)")
	verif.v(not Banc.peut_deposer(grenier, _config),
		"un grenier plein doit refuser le depot")
	verif.v(Banc.poser_encombrement(grenier, _config) and Banc.est_encombre(grenier, _config),
		"l'etat 'encombre' doit etre pose depuis LE MEME predicat que le refus -- jamais un seuil qui diverge au bord")

	var colon: Dictionary = etat.colons[0]
	colon.proprietes[String(_config.nom_mode)] = String(_config.mode_depot)
	colon.position = Banc.cible_de(colon, grenier.position)
	colon.proprietes[String(_config.nom_rythme_effectif)] = 1.0
	_poser_charge(colon, 25.0, _config)

	var stock_avant := Banc.stock_grenier(grenier, _config)
	var bilan := Banc.avancer_colons(etat.colons, etat.tas, grenier, etat.route, _config, _etats, 0.5)

	verif.v(int(bilan.refus) >= 1, "le depot doit etre compte comme REFUSE, recu %d" % int(bilan.refus))
	verif.v(is_equal_approx(Banc.charge_de(colon, _config), 25.0),
		"LE PORTEUR GARDE SA CHARGE -- refuser n'est pas ecreter (recu %.3f, attendu 25.000)" % Banc.charge_de(colon, _config))
	verif.v(is_equal_approx(Banc.stock_grenier(grenier, _config), stock_avant),
		"le grenier ne doit pas gagner un gramme (%.3f -> %.3f)" % [stock_avant, Banc.stock_grenier(grenier, _config)])
	verif.v(colon.proprietes[String(_config.nom_mode)] == String(_config.mode_depot),
		"le colon reste devant le grenier, en attente -- il ne repart pas a vide")

	# et rien, jamais, ne fait passer la reserve au-dessus de la capacite
	verif.v(Banc.stock_grenier(grenier, _config) <= Banc.capacite_grenier(grenier, _config),
		"la reserve ne doit jamais depasser sa capacite")

func _agrandir_le_grenier_leve_le_refus_sans_le_remplir() -> void:
	var etat := _monde()
	var grenier: Dictionary = etat.grenier
	var canal := Banc.canal_stockage(grenier, _config)
	canal["reserve"] = Banc.capacite_grenier(grenier, _config)
	var stock_avant := Banc.stock_grenier(grenier, _config)
	var capacite_avant := Banc.capacite_grenier(grenier, _config)

	var nouvelle := Banc.agrandir_grenier(grenier, _config)
	verif.v(is_equal_approx(nouvelle, capacite_avant + float(_config.grenier.agrandissement)),
		"agrandir doit ajouter exactement %.0f de capacite (%.1f -> %.1f)" % [
			float(_config.grenier.agrandissement), capacite_avant, nouvelle])
	verif.v(is_equal_approx(Banc.stock_grenier(grenier, _config), stock_avant),
		"agrandir un grenier ne le REMPLIT pas -- la reserve ne bouge pas")
	verif.v(Banc.peut_deposer(grenier, _config), "le depot doit redevenir possible")
	verif.v(not Banc.poser_encombrement(grenier, _config) and not Banc.est_encombre(grenier, _config),
		"'encombre' doit etre RETIRE par le meme unique ecrivain -- l'etat est reversible")

	# et le depot reprend reellement
	var colon: Dictionary = etat.colons[0]
	colon.proprietes[String(_config.nom_mode)] = String(_config.mode_depot)
	colon.position = Banc.cible_de(colon, grenier.position)
	colon.proprietes[String(_config.nom_rythme_effectif)] = 1.0
	_poser_charge(colon, 25.0, _config)
	Banc.avancer_colons(etat.colons, etat.tas, grenier, etat.route, _config, _etats, 0.5)
	verif.v(Banc.charge_de(colon, _config) < 25.0,
		"la file repart : le colon doit enfin poser une partie de sa charge (%.3f restant)" % Banc.charge_de(colon, _config))

	# le plafond de capacite lui-meme est borne
	for i in range(50):
		Banc.agrandir_grenier(grenier, _config)
	verif.v(is_equal_approx(Banc.capacite_grenier(grenier, _config), float(_config.grenier.capacite_max)),
		"la capacite ne doit jamais depasser capacite_max (%.1f obtenu)" % Banc.capacite_grenier(grenier, _config))

func _l_objet_dehors_se_degrade_plus_vite_que_dedans() -> void:
	var etat := _monde()

	# Les deux taux, derives des durees de vie declarees, jamais poses en dur.
	var abri := Banc.cout_abri(_config)
	var dehors := Banc.cout_exterieur(_config)
	verif.v(dehors > abri, "le cout du dehors (%.3f) doit depasser celui de l'abri (%.3f)" % [dehors, abri])

	var rapport := Banc.poser_surcout_degradation(etat.lots, etat.grenier, _config)
	var nb_abrites := 0
	for id in rapport:
		var r: Dictionary = rapport[id]
		if bool(r.abrite):
			nb_abrites += 1
			verif.v(is_equal_approx(float(r.surcout), 0.0),
				"un lot A L'ABRI ne porte AUCUN surcout (%s : %.3f)" % [id, float(r.surcout)])
			verif.v(is_equal_approx(float(r.total), abri),
				"il se degrade au seul cout d'abri (%s : %.3f attendu %.3f)" % [id, float(r.total), abri])
		else:
			verif.v(is_equal_approx(float(r.total), dehors),
				"un lot DEHORS se degrade a cout_exterieur exactement, cout_base + surcout (%s : %.3f attendu %.3f)"
					% [id, float(r.total), dehors])
	verif.v(nb_abrites > 0 and nb_abrites < rapport.size(),
		"le banc doit poser des lots des DEUX cotes de l'abri (%d abrites sur %d)" % [nb_abrites, rapport.size()])

	# Et le mecanisme confirme la lecture : au bout de la duree de vie du
	# dehors, les lots exterieurs sont ruines et les autres a peine entames.
	var duree := float(_config.degradation.duree_j_exterieur) / float(_config.jours_par_seconde)
	_avancer_n(etat, int(duree * 10.0) + 2, 0.1)

	for lot in etat.lots:
		var sous_abri: bool = bool(lot.proprietes.get(String(_config.nom_abrite), false))
		var reste := Banc.integrite(lot, _config)
		if sous_abri:
			verif.v(reste > float(_config.degradation.integrite_lot) * 0.7,
				"apres %.0f s, un lot a l'abri doit avoir garde l'essentiel de son integrite (%s : %.2f)" % [duree, lot.id, reste])
		else:
			verif.v(is_equal_approx(reste, 0.0),
				"apres sa duree de vie, un lot dehors doit etre a zero, borne par depense.gd (%s : %.2f)" % [lot.id, reste])

	# « suis-je a l'abri » est une COMPARAISON DE POSITIONS, pas un drapeau
	# pose a la main : deplacer un lot sous le grenier suffit a le sauver.
	var rescape: Dictionary = _lot(etat, "lot_d")
	verif.v(not rescape.is_empty(), "le lot 'lot_d' doit exister dans la config reelle")
	rescape.position = etat.grenier.position
	Banc.poser_surcout_degradation(etat.lots, etat.grenier, _config)
	verif.v(bool(rescape.proprietes[String(_config.nom_abrite)]),
		"un lot deplace SOUS le grenier doit devenir abrite -- Portee.en_portee, jamais un drapeau")
	verif.v(is_equal_approx(float(rescape.proprietes.reserves[String(_config.nom_reserve_integrite)].surcout_action), 0.0),
		"et son surcout doit retomber a exactement 0.0 -- ecriture COMPLETE, jamais un residu")

func _le_comptage_ne_compte_que_les_colons_actifs() -> void:
	var etat := _monde()
	verif.v(Banc.compter_actifs(etat.colons, _comptages, _config) == int(_config.colons.actifs_initial),
		"au depart, exactement actifs_initial colons doivent etre comptes")

	Banc.regler_actifs(etat.colons, 7, _config)
	verif.v(Banc.compter_actifs(etat.colons, _comptages, _config) == 7,
		"regler_actifs(7) doit donner un comptage de 7, recu %d" % Banc.compter_actifs(etat.colons, _comptages, _config))
	verif.v(not etat.colons[7].proprietes.has(String(_config.nom_actif)),
		"un colon inactif doit voir la cle RETIREE, jamais posee a false -- le mode 'presente' compterait un false")

	Banc.regler_actifs(etat.colons, 0, _config)
	verif.v(Banc.compter_actifs(etat.colons, _comptages, _config) == 0,
		"zero actif doit compter zero, jamais une alarme")

	verif.v(Banc.actifs_apres(int(_config.colons.population_max), int(_config.colons.pas_toggle), _config)
			== int(_config.colons.population_max),
		"le toggle est borne en haut par population_max")
	verif.v(Banc.actifs_apres(0, -int(_config.colons.pas_toggle), _config) == 0,
		"et en bas par zero -- jamais un nombre negatif de colons")

func _la_coordination_baisse_le_rythme_au_dela_du_seuil() -> void:
	var seuil := int(_config.colons.seuil_agents)

	# SOUS le seuil : exactement 1.0, jamais un « presque ».
	var etat_calme := _monde()
	Banc.regler_actifs(etat_calme.colons, seuil, _config)
	var bilan_calme := _avancer_n(etat_calme, 2, 0.1)
	verif.v(int(bilan_calme.population) == seuil,
		"la population comptee doit valoir %d, recu %d" % [seuil, int(bilan_calme.population)])
	verif.v(not etat_calme.colons[0].proprietes.get("etats_actifs", []).has(String(_config.etat_surpeuplement)),
		"a la population EGALE au seuil, aucun surpeuplement (seuil_etat.gd compare strictement >)")
	verif.v(is_equal_approx(_rythme_de(etat_calme.colons[0], _config), float(_config.colons.rythme_base)),
		"et le rythme effectif vaut exactement le rythme de base (%.3f)" % _rythme_de(etat_calme.colons[0], _config))

	# AU-DELA : l'etat est pose et le rythme baisse de la formule exacte.
	var etat_foule := _monde()
	var population := int(_config.colons.population_max)
	Banc.regler_actifs(etat_foule.colons, population, _config)
	var bilan_foule := _avancer_n(etat_foule, 2, 0.1)
	verif.v(int(bilan_foule.population) == population,
		"la population comptee doit valoir %d, recu %d" % [population, int(bilan_foule.population)])
	verif.v(etat_foule.colons[0].proprietes.get("etats_actifs", []).has(String(_config.etat_surpeuplement)),
		"au-dela du seuil, seuil_etat.gd doit poser 'surpeuplement' sur les colons")

	var attendu: float = float(_config.colons.rythme_base) * (
		1.0 - float(_config.colons.perte_efficacite) * float(population - seuil))
	verif.v(is_equal_approx(_rythme_de(etat_foule.colons[0], _config), attendu),
		"rythme effectif = rythme x (1 - perte x (population - seuil)) : %.4f attendu, %.4f obtenu"
			% [attendu, _rythme_de(etat_foule.colons[0], _config)])
	verif.v(_rythme_de(etat_foule.colons[0], _config) < _rythme_de(etat_calme.colons[0], _config),
		"et il doit etre STRICTEMENT plus bas que sous le seuil")

	# le rythme de BASE n'a jamais ete touche
	verif.v(is_equal_approx(float(etat_foule.colons[0].proprietes[String(_config.nom_rythme)]), float(_config.colons.rythme_base)),
		"le rythme de BASE ne doit jamais etre reecrit -- seul le champ derive change")

	# REVERSIBLE : on redescend sous le seuil, l'etat se retire et le rythme
	# revient exactement a sa base.
	Banc.regler_actifs(etat_foule.colons, seuil, _config)
	_avancer_n(etat_foule, 2, 0.1)
	verif.v(not etat_foule.colons[0].proprietes.get("etats_actifs", []).has(String(_config.etat_surpeuplement)),
		"redescendu sous le seuil, 'surpeuplement' doit etre retire par le franchissement descendant")
	verif.v(is_equal_approx(_rythme_de(etat_foule.colons[0], _config), float(_config.colons.rythme_base)),
		"et le rythme revient exactement a sa base (%.4f)" % _rythme_de(etat_foule.colons[0], _config))

func _la_route_accelere_le_colon() -> void:
	var etat := _monde()
	var colon: Dictionary = etat.colons[0]
	var facteur := float(_config.route.facteur_vitesse)

	colon.position = Vector3(0.0, -9999.0, 0.0)
	var hors_route := Banc.vitesse_effective(colon, etat.route, _config, _etats)
	verif.v(Banc.case_sous(colon, etat.route, float(_config.route.rayon_case)) == null,
		"loin de tout, aucune case ne doit etre sous le colon")
	verif.v(is_equal_approx(hors_route, float(_config.colons.vitesse_base)),
		"hors route, la vitesse effective vaut exactement la vitesse de base (%.2f)" % hors_route)

	colon.position = etat.route[1].position
	var sur_route := Banc.vitesse_effective(colon, etat.route, _config, _etats)
	verif.v(Banc.case_sous(colon, etat.route, float(_config.route.rayon_case)) != null,
		"sur une case de route, case_sous doit la retrouver (patron banc_fertilite.gd:case_sous)")
	verif.v(is_equal_approx(sur_route, float(_config.colons.vitesse_base) * facteur),
		"sur route neuve, la vitesse vaut base x %.2f (%.2f attendu, %.2f obtenu)"
			% [facteur, float(_config.colons.vitesse_base) * facteur, sur_route])
	verif.v(sur_route > hors_route, "et elle doit etre STRICTEMENT plus grande que hors route")

	# le trajet est reellement plus court : meme temps, plus de distance
	var sur: Dictionary = etat.colons[1]
	var hors: Dictionary = etat.colons[2]
	sur.position = etat.route[0].position
	hors.position = etat.route[0].position + Vector3(0.0, -9999.0, 0.0)
	var cible_sur: Vector3 = sur.position + Vector3(400.0, 0.0, 0.0)
	var cible_hors: Vector3 = hors.position + Vector3(400.0, 0.0, 0.0)
	var depart_sur: Vector3 = sur.position
	var depart_hors: Vector3 = hors.position
	Banc.deplacer_vers(sur, cible_sur, etat.route, _config, _etats, 0.5)
	Banc.deplacer_vers(hors, cible_hors, etat.route, _config, _etats, 0.5)
	verif.v(sur.position.distance_to(depart_sur) > hors.position.distance_to(depart_hors),
		"en un meme pas de temps, le colon sur la route doit avoir parcouru plus de chemin (%.2f contre %.2f)"
			% [sur.position.distance_to(depart_sur), hors.position.distance_to(depart_hors)])

func _la_route_usee_ne_donne_plus_de_bonus() -> void:
	var etat := _monde()
	var case: Dictionary = etat.route[0]
	var colon: Dictionary = etat.colons[0]
	colon.position = case.position

	verif.v(Banc.usure_route(case, _config) > 0.0, "la route part chargee")
	# UN SEUL colon sur la case : le surcout est exactement cout_par_passage.
	Banc.regler_actifs(etat.colons, 1, _config)
	var poses := Banc.poser_usure_routes(etat.route, etat.colons, _config)
	verif.v(is_equal_approx(float(poses[case.id]), float(_config.route.cout_par_passage)),
		"un colon sur la case doit poser exactement cout_par_passage en surcout (%.3f)" % float(poses[case.id]))

	# on la fait mourir
	for i in range(400):
		Banc.poser_usure_routes(etat.route, etat.colons, _config)
		Depense.avancer(etat.route, 0.5, _seuils)
		if is_equal_approx(Banc.usure_route(case, _config), 0.0):
			break

	verif.v(is_equal_approx(Banc.usure_route(case, _config), 0.0),
		"la reserve de route doit atteindre exactement 0.0 (borne basse de depense.gd), recu %.3f" % Banc.usure_route(case, _config))
	verif.v(is_equal_approx(float(case.proprietes[String(_config.nom_facteur_vitesse)]), float(_config.route.facteur_vitesse_use)),
		"a zero, c'est DEPENSE.GD qui repose %s a %.1f -- jamais le cablage"
			% [String(_config.nom_facteur_vitesse), float(_config.route.facteur_vitesse_use)])
	verif.v(is_equal_approx(Banc.facteur_vitesse_sous(colon, etat.route, _config), 1.0),
		"une case usee ne donne plus aucun bonus")
	verif.v(is_equal_approx(Banc.vitesse_effective(colon, etat.route, _config, _etats), float(_config.colons.vitesse_base)),
		"le colon dessus retombe a sa vitesse de base (%.2f)" % Banc.vitesse_effective(colon, etat.route, _config, _etats))

	# UNE FILE ARRETEE N'USE RIEN. Defaut trouve en lancant la scene : les
	# colons stoppes devant un grenier plein restent dans le rayon de la
	# derniere case et l'usaient a plein regime -- une route usee par des gens
	# qui attendent. Le filtre `en_transit` le ferme.
	var etat_file := _monde()
	Banc.regler_actifs(etat_file.colons, 3, _config)
	for i in range(3):
		etat_file.colons[i].position = etat_file.route[0].position
		etat_file.colons[i].proprietes[String(_config.nom_mode)] = String(_config.mode_depot)
	var poses_file := Banc.poser_usure_routes(etat_file.route, etat_file.colons, _config)
	verif.v(is_equal_approx(float(poses_file[etat_file.route[0].id]), 0.0),
		"trois colons ARRETES sur une case ne posent aucun surcout de trafic (%.3f)"
			% float(poses_file[etat_file.route[0].id]))
	for i in range(3):
		etat_file.colons[i].proprietes[String(_config.nom_mode)] = String(_config.mode_vers_grenier)
	poses_file = Banc.poser_usure_routes(etat_file.route, etat_file.colons, _config)
	verif.v(is_equal_approx(float(poses_file[etat_file.route[0].id]), 3.0 * float(_config.route.cout_par_passage)),
		"les MEMES trois colons, en transit, posent bien trois passages (%.3f)"
			% float(poses_file[etat_file.route[0].id]))

	# une case OU PERSONNE NE PASSE s'use bien plus lentement : c'est le
	# trafic, pas le seul temps, qui fait l'usure.
	var etat_b := _monde()
	Banc.regler_actifs(etat_b.colons, 3, _config)
	for i in range(3):
		etat_b.colons[i].position = etat_b.route[0].position
	for i in range(20):
		Banc.poser_usure_routes(etat_b.route, etat_b.colons, _config)
		Depense.avancer(etat_b.route, 0.1, _seuils)
	verif.v(Banc.usure_route(etat_b.route[0], _config) < Banc.usure_route(etat_b.route[3], _config),
		"la case foulee doit s'user plus vite que celle que personne n'emprunte (%.2f contre %.2f)"
			% [Banc.usure_route(etat_b.route[0], _config), Banc.usure_route(etat_b.route[3], _config)])

func _la_reparation_restaure_le_bonus_et_reste_reusable() -> void:
	var etat := _monde()
	var case: Dictionary = etat.route[0]
	Banc.regler_actifs(etat.colons, 1, _config)
	etat.colons[0].position = case.position

	for i in range(400):
		Banc.poser_usure_routes(etat.route, etat.colons, _config)
		Depense.avancer(etat.route, 0.5, _seuils)
		if is_equal_approx(Banc.usure_route(case, _config), 0.0):
			break
	verif.v(is_equal_approx(float(case.proprietes[String(_config.nom_facteur_vitesse)]), 1.0),
		"la route doit etre usee avant de tester la reparation")

	var reparees := Banc.reparer_route(etat.route, _config)
	verif.v(reparees == etat.route.size(), "toutes les cases doivent etre reparees, %d sur %d" % [reparees, etat.route.size()])
	verif.v(is_equal_approx(Banc.usure_route(case, _config), float(_config.route.duree_route)),
		"la reserve doit etre rechargee a duree_route (%.1f obtenu)" % Banc.usure_route(case, _config))
	verif.v(is_equal_approx(float(case.proprietes[String(_config.nom_facteur_vitesse)]), float(_config.route.facteur_vitesse)),
		"et le facteur de vitesse doit etre rendu (x%.2f obtenu)" % float(case.proprietes[String(_config.nom_facteur_vitesse)]))
	verif.v(case.proprietes.reserves[String(_config.nom_reserve_route)].seuils_franchis.is_empty(),
		"la reparation doit VIDER seuils_franchis, sinon depense.gd n'userait plus JAMAIS cette route")

	# et elle s'use A NOUVEAU : c'est ce que le vidage prouve.
	for i in range(400):
		Banc.poser_usure_routes(etat.route, etat.colons, _config)
		Depense.avancer(etat.route, 0.5, _seuils)
		if is_equal_approx(Banc.usure_route(case, _config), 0.0):
			break
	verif.v(is_equal_approx(float(case.proprietes[String(_config.nom_facteur_vitesse)]), 1.0),
		"une route reparee doit pouvoir s'user une SECONDE fois (facteur x%.2f obtenu)"
			% float(case.proprietes[String(_config.nom_facteur_vitesse)]))

func _un_seul_ecrivain_pour_surcout_action_et_pour_rythme() -> void:
	var etat := _monde()

	# ---- surcout_action, canal des LOTS ----
	var lot: Dictionary = etat.lots[0]
	var canal_lot: Dictionary = lot.proprietes.reserves[String(_config.nom_reserve_integrite)]
	canal_lot["surcout_action"] = 999.0
	canal_lot["cout_base"] = 999.0
	var rapport := Banc.poser_surcout_degradation(etat.lots, etat.grenier, _config)
	verif.v(is_equal_approx(float(canal_lot.surcout_action) + float(canal_lot.cout_base), float(rapport[lot.id].total)),
		"le canal doit porter EXACTEMENT ce que la decomposition rendue annonce (%.3f contre %.3f)"
			% [float(canal_lot.surcout_action) + float(canal_lot.cout_base), float(rapport[lot.id].total)])
	verif.v(float(canal_lot.surcout_action) < 999.0 and float(canal_lot.cout_base) < 999.0,
		"une valeur polluee a la main doit etre REECRITE EN ENTIER, jamais incrementee")

	# le meme lot, deplace dehors puis ramene : aucun residu ni dans un sens
	# ni dans l'autre.
	var position_abri: Vector3 = lot.position
	lot.position = Vector3(-9999.0, 0.0, 0.0)
	Banc.poser_surcout_degradation(etat.lots, etat.grenier, _config)
	var dehors := float(canal_lot.surcout_action)
	lot.position = position_abri
	Banc.poser_surcout_degradation(etat.lots, etat.grenier, _config)
	verif.v(dehors > 0.0 and is_equal_approx(float(canal_lot.surcout_action), 0.0),
		"dehors le surcout monte (%.3f), rentre il retombe a EXACTEMENT zero (%.3f)" % [dehors, float(canal_lot.surcout_action)])

	# ---- surcout_action, canal des CASES DE ROUTE (famille disjointe) ----
	var case: Dictionary = etat.route[0]
	var canal_route: Dictionary = case.proprietes.reserves[String(_config.nom_reserve_route)]
	var cout_base_avant := float(canal_route.cout_base)
	Banc.regler_actifs(etat.colons, 2, _config)
	etat.colons[0].position = case.position
	etat.colons[1].position = case.position
	Banc.poser_usure_routes(etat.route, etat.colons, _config)
	verif.v(is_equal_approx(float(canal_route.surcout_action), 2.0 * float(_config.route.cout_par_passage)),
		"deux colons sur la case : le surcout est la SOMME, jamais l'un qui ecrase l'autre (%.3f)" % float(canal_route.surcout_action))
	verif.v(is_equal_approx(float(canal_route.cout_base), cout_base_avant),
		"poser_usure_routes ne touche JAMAIS cout_base -- l'usure du temps et celle du trafic ne se melangent pas")
	etat.colons[0].position = Vector3(-9999.0, 0.0, 0.0)
	etat.colons[1].position = Vector3(-9999.0, 0.0, 0.0)
	Banc.poser_usure_routes(etat.route, etat.colons, _config)
	verif.v(is_equal_approx(float(canal_route.surcout_action), 0.0),
		"plus personne dessus : le surcout retombe a EXACTEMENT zero, jamais un residu (%.3f)" % float(canal_route.surcout_action))

	# les deux familles de canaux restent disjointes : ecrire l'une n'a rien
	# ecrit sur l'autre.
	verif.v(is_equal_approx(float(canal_lot.surcout_action), 0.0),
		"le canal des lots doit etre reste intact pendant qu'on ecrivait sur celui des routes")

	# ---- rythme ----
	var colon: Dictionary = etat.colons[0]
	colon.proprietes[String(_config.nom_rythme_effectif)] = 999.0
	Banc.poser_rythme_effectif(etat.colons, 1, _config, _etats)
	verif.v(is_equal_approx(Banc.rythme_effectif(colon, _config), float(_config.colons.rythme_base)),
		"le rythme effectif est REECRIT A NEUF chaque tick, jamais un '+=' (999.0 -> %.3f)" % Banc.rythme_effectif(colon, _config))
	verif.v(is_equal_approx(float(colon.proprietes[String(_config.nom_rythme)]), float(_config.colons.rythme_base)),
		"et le rythme de BASE n'a pas bouge d'un chiffre")

func _la_navette_conserve_la_matiere_sur_la_config_reelle() -> void:
	var etat := _monde()
	var total_depart := _matiere_totale(etat, _config)
	var integrite_depart := Banc.integrite(_lot(etat, "lot_a"), _config)

	var bilan := _avancer_n(etat, 600, 0.1)

	verif.v(is_equal_approx(_matiere_totale(etat, _config), total_depart),
		"LA MATIERE SE CONSERVE de bout en bout (tas + colons + grenier) : %.4f au depart, %.4f apres 60 s"
			% [total_depart, _matiere_totale(etat, _config)])
	verif.v(Banc.stock_grenier(etat.grenier, _config) > float(_config.grenier.stockage_initial),
		"le grenier doit s'etre rempli (%.2f, parti de %.2f)"
			% [Banc.stock_grenier(etat.grenier, _config), float(_config.grenier.stockage_initial)])
	verif.v(Banc.stock_grenier(etat.grenier, _config) <= Banc.capacite_grenier(etat.grenier, _config),
		"et n'avoir JAMAIS depasse sa capacite (%.2f / %.2f)"
			% [Banc.stock_grenier(etat.grenier, _config), Banc.capacite_grenier(etat.grenier, _config)])
	verif.v(is_equal_approx(Banc.integrite(_lot(etat, "lot_d"), _config), 0.0),
		"apres 60 s, les lots restes dehors sont ruines (%.2f)" % Banc.integrite(_lot(etat, "lot_d"), _config))
	verif.v(Banc.integrite(_lot(etat, "lot_a"), _config) > integrite_depart * 0.2,
		"ceux de l'abri tiennent encore largement (%.2f, partis de %.2f)"
			% [Banc.integrite(_lot(etat, "lot_a"), _config), integrite_depart])
	verif.v(float(bilan.travail.depose) >= 0.0 and int(bilan.population) == int(_config.colons.actifs_initial),
		"le bilan rendu doit rester coherent avec la population reelle (%d)" % int(bilan.population))

	# la route a servi : au moins une case s'est usee sous la navette.
	var usee := false
	for case in etat.route:
		if Banc.usure_route(case, _config) < float(_config.route.duree_route):
			usee = true
	verif.v(usee, "la navette doit avoir use la route -- sinon aucun colon n'a jamais pris le chemin")

func _le_meme_code_traverse_une_ruche() -> void:
	var config := _config_ruche()
	var comptages := {
		"butineuses_en_service": { "propriete": "en_service", "mode": "presente" },
	}
	var seuils := {
		"fatigue_sentier": [ { "seuil": 0.0, "poser": { "gain_allure": 1.0 } } ],
	}
	# Catalogue d'etats LOCAL : 'essaim_dense' MODULE reellement la cadence.
	# C'est ce cas qui prouve que poser_rythme_effectif compose bien
	# EtatEffectif.valeur -- sans cet appel, ce facteur serait inerte.
	var etats := {
		"essaim_dense": { "effets": [ { "propriete": "cadence", "mode": "moduler", "facteur": 0.5 } ] },
		"panier_plein": { "effets": [] },
	}

	var etat := Banc.construire_monde(config)
	verif.v(etat.colons.size() == int(config.colons.population_max),
		"le domaine invente doit construire ses butineuses comme les autres")

	# stockage : le silo plein refuse le depot, la butineuse garde son pollen
	var silo: Dictionary = etat.grenier
	Banc.canal_stockage(silo, config)["reserve"] = Banc.capacite_grenier(silo, config)
	verif.v(not Banc.peut_deposer(silo, config), "un silo a pollen plein refuse comme un grenier")
	Banc.poser_encombrement(silo, config)
	verif.v(silo.proprietes.etats_actifs.has("panier_plein"),
		"et c'est le NOM DECLARE EN DONNEE qui est pose, jamais 'encombre' en dur")

	# degradation : le pollen laisse dehors se perd plus vite
	var rapport := Banc.poser_surcout_degradation(etat.lots, silo, config)
	verif.v(rapport.has("grappe_abri") and rapport.has("grappe_dehors"),
		"les deux grappes doivent etre rapportees")
	verif.v(is_equal_approx(float(rapport["grappe_abri"].surcout), 0.0)
			and float(rapport["grappe_dehors"].surcout) > 0.0,
		"la grappe dehors porte un surcout, celle de l'abri aucun")

	# coordination : au-dela du seuil, l'etat d'essaim MODULE la cadence ET la
	# formule de coordination s'y ajoute. Le produit des deux, exactement.
	Banc.regler_actifs(etat.colons, int(config.colons.population_max), config)
	var population := Banc.compter_actifs(etat.colons, comptages, config)
	verif.v(population == int(config.colons.population_max),
		"le comptage doit trouver toutes les butineuses en service, recu %d" % population)
	Banc.poser_population(etat.colons, population, config)
	var SeuilEtat = load("res://scripts/seuil_etat.gd")
	SeuilEtat.avancer(etat.colons, config.seuils_locaux)
	verif.v(etat.colons[0].proprietes.etats_actifs.has("essaim_dense"),
		"l'etat d'essaim doit etre pose au-dela du seuil de la ruche")

	Banc.poser_rythme_effectif(etat.colons, population, config, etats)
	var attendu: float = float(config.colons.rythme_base) * 0.5 * (
		1.0 - float(config.colons.perte_efficacite) * float(population - int(config.colons.seuil_agents)))
	verif.v(is_equal_approx(Banc.rythme_effectif(etat.colons[0], config), attendu),
		"la cadence effective doit etre le PRODUIT du facteur d'etat (x0.5, via etat_effectif.gd) et " +
		"du facteur de coordination : %.4f attendu, %.4f obtenu" % [attendu, Banc.rythme_effectif(etat.colons[0], config)])

	# routes : le sentier de vol accelere, s'use, et se repare
	var butineuse: Dictionary = etat.colons[0]
	butineuse.position = etat.route[0].position
	verif.v(is_equal_approx(Banc.facteur_vitesse_sous(butineuse, etat.route, config), float(config.route.facteur_vitesse)),
		"le sentier de vol doit accelerer la butineuse")
	Banc.regler_actifs(etat.colons, 1, config)
	for i in range(400):
		Banc.poser_usure_routes(etat.route, etat.colons, config)
		Depense.avancer(etat.route, 0.5, seuils)
		if is_equal_approx(Banc.usure_route(etat.route[0], config), 0.0):
			break
	verif.v(is_equal_approx(Banc.facteur_vitesse_sous(butineuse, etat.route, config), 1.0),
		"use, il ne donne plus rien -- et le nom de la propriete posee par le seuil vient de la donnee")
	Banc.reparer_route(etat.route, config)
	verif.v(is_equal_approx(Banc.facteur_vitesse_sous(butineuse, etat.route, config), float(config.route.facteur_vitesse)),
		"repare, il redonne son gain")

	# le pas complet tourne, et conserve le pollen
	var total_depart := _matiere_totale(etat, config)
	Banc.regler_actifs(etat.colons, int(config.colons.actifs_initial), config)
	for i in range(200):
		Banc.avancer(etat, config, comptages, seuils, etats, 0.1)
	verif.v(is_equal_approx(_matiere_totale(etat, config), total_depart),
		"et le pollen se conserve exactement comme la marchandise (%.4f -> %.4f)"
			% [total_depart, _matiere_totale(etat, config)])

# Un domaine SANS AUCUN rapport avec un chantier de colonie : une ruche. Aucun
# nom n'est partage avec data/banc_infrastructure.json -- ni les reserves, ni
# les etats, ni les modes, ni les proprietes.
func _config_ruche() -> Dictionary:
	return {
		"jours_par_seconde": 2.0,
		"periode_trace_s": 1.0,

		"nom_reserve_stockage": "pollen",
		"nom_capacite_stockage": "volume_alveoles",
		"nom_reserve_charge": "panier_pollen",
		"nom_capacite_charge": "volume_panier",
		"nom_reserve_integrite": "fraicheur",
		"nom_reserve_route": "nettete_sentier",

		"nom_vitesse": "allure_vol",
		"nom_rythme": "cadence",
		"nom_rythme_effectif": "cadence_effective",
		"nom_population_active": "essaim_present",
		"nom_seuil_agents": "seuil_essaim",
		"nom_facteur_vitesse": "gain_allure",
		"nom_actif": "en_service",
		"nom_mode": "phase_vol",
		"nom_abrite": "sous_toit",

		"etat_encombre": "panier_plein",
		"etat_surpeuplement": "essaim_dense",

		"mode_vers_tas": "vers_fleurs",
		"mode_charge": "butine",
		"mode_vers_grenier": "vers_ruche",
		"mode_depot": "decharge",

		"comptage_ref": "butineuses_en_service",
		"seuils_locaux": {
			"essaim_ruche": {
				"propriete_continue": "essaim_present",
				"seuil_propriete": "seuil_essaim",
				"etat": "essaim_dense",
			},
		},

		"grenier": {
			"id": "silo_pollen",
			"position": [400.0, 0.0, 0.0],
			"stockage_initial": 10.0,
			"capacite_initiale": 60.0,
			"agrandissement": 20.0,
			"capacite_max": 100.0,
			"cout_base": 0.0,
		},
		"tas": {
			"id": "prairie",
			"position": [0.0, 0.0, 0.0],
			"stock_initial": 500.0,
		},
		"degradation": {
			"rayon_abri": 50.0,
			"integrite_lot": 20.0,
			"duree_j_abri": 40.0,
			"duree_j_exterieur": 5.0,
			"lots": [
				{ "id": "grappe_abri", "position": [410.0, 10.0, 0.0] },
				{ "id": "grappe_dehors", "position": [20.0, 10.0, 0.0] },
			],
		},
		"route": {
			"cases": [ [130.0, 0.0, 0.0], [270.0, 0.0, 0.0] ],
			"rayon_case": 80.0,
			"facteur_vitesse": 2.5,
			"facteur_vitesse_use": 1.0,
			"duree_route": 25.0,
			"cout_base_route": 0.1,
			"cout_par_passage": 2.0,
			"seuils_ref": "fatigue_sentier",
		},
		"colons": {
			"population_max": 12,
			"actifs_initial": 3,
			"pas_toggle": 3,
			"vitesse_base": 40.0,
			"rythme_base": 1.0,
			"capacite_charge": 6.0,
			"taux_charge": 4.0,
			"taux_depot": 3.0,
			"portee_travail": 30.0,
			"seuil_agents": 6.0,
			"perte_efficacite": 0.05,
			"facteur_min_coordination": 0.1,
			"depart": [0.0, 60.0, 0.0],
			"colonnes_depart": 4,
			"espacement_depart": 12.0,
		},
		"couleurs": {
			"lot_abrite": [0.9, 0.8, 0.2],
			"lot_dehors": [0.6, 0.3, 0.1],
			"lot_ruine": [0.1, 0.1, 0.1],
			"route_neuve": [1.0, 1.0, 0.5],
			"route_usee": [0.4, 0.4, 0.4],
			"colon_vide": [0.5, 0.5, 0.9],
			"colon_charge": [0.9, 0.9, 0.3],
			"colon_inactif": [0.2, 0.2, 0.2],
			"grenier": [0.7, 0.6, 0.2],
			"grenier_plein": [0.9, 0.2, 0.2],
			"tas": [0.3, 0.5, 0.3],
			"barre_fond": [0.1, 0.1, 0.1],
			"barre_remplie": [0.4, 0.8, 0.4],
			"fond": [0.1, 0.1, 0.1],
		},
	}
