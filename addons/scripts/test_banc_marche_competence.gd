extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_marche_competence.gd
#
# Verrouille le CABLAGE de scripts/banc_marche_competence.gd (prix comme champ
# derive par colon, offre percue, demande comptee, competence qui monte par usage
# et se rouille sans, plancher a la lecture, habitude qui accelere la forge et se
# perd, specialisation qui monte la saillance du forgeable pour un seul colon) --
# jamais scripts/somme.gd, scripts/comptage.gd, scripts/epigenetique.gd,
# scripts/deformation.gd, scripts/perception.gd, scripts/proximite.gd,
# scripts/depense.gd ni scripts/consommer.gd eux-memes, deja verrouilles par
# leurs propres tests.
#
# LES CINQ CATALOGUES SONT LUS SUR LE DISQUE (data/canaux.json,
# data/profils_saillance.json, data/deformations.json, data/epigenetique.json,
# data/comptages.json) et la config du banc AUSSI
# (data/banc_marche_competence.json) : la calibration de ce chantier est
# precisement ce qui peut se casser en silence -- la lecon de banc_maladie, dont
# le canal ne contaminait JAMAIS personne pendant que son test restait vert faute
# de rejouer le JSON reel. Une fixture locale ne prouverait rien du chemin reel.
# Les seules fixtures de ce fichier sont celles du cas HORS DOMAINE, dont c'est
# tout l'objet.
#
# LE TICK N'EST JAMAIS RECONSTITUE ICI : ce fichier appelle Banc.avancer_tick, la
# MEME fonction statique que _process appelle. Rejouer l'ordre a la main aurait
# laisse la scene et le test deriver l'un de l'autre sans qu'aucun ne rougisse.

const Banc = preload("res://scripts/banc_marche_competence.gd")
const Monde = preload("res://scripts/monde.gd")
const Verif = preload("res://scripts/verif.gd")

const DELTA := 0.1

func _json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))

func _config() -> Dictionary:
	return _json("res://data/banc_marche_competence.json")

func _canaux() -> Dictionary:
	return _json("res://data/canaux.json")

func _profils() -> Dictionary:
	return _json("res://data/profils_saillance.json")

func _deformations() -> Dictionary:
	return _json("res://data/deformations.json")

func _epigenetique() -> Dictionary:
	return _json("res://data/epigenetique.json")

func _comptages() -> Dictionary:
	return _json("res://data/comptages.json")

func _init() -> void:
	var v := Verif.new()
	_le_prix_monte_quand_l_offre_baisse(v)
	_le_prix_est_recalcule_a_neuf_jamais_accumule(v)
	_deux_colons_estiment_deux_prix_parce_qu_ils_ne_voient_pas_le_meme_stock(v)
	_la_demande_est_un_compte_d_entites_lu_par_comptage(v)
	_la_competence_monte_par_usage(v)
	_la_competence_decroit_sans_usage(v)
	_le_plancher_empeche_la_competence_de_tomber_a_zero(v)
	_le_novice_n_a_pas_de_plancher_donc_pas_de_competence(v)
	_l_habitude_accelere_la_vitesse_de_forge(v)
	_l_habitude_decroit_sans_repetition(v)
	_la_specialisation_monte_la_saillance_du_forgeable(v)
	_le_novice_n_a_aucune_deformation(v)
	_le_gate_de_portee_ferme_la_forge_au_colon_eloigne(v)
	_les_trois_plafonds_du_cablage_tiennent(v)
	_l_intervalle_de_pose_du_disque_laisse_les_deux_marques_survivre(v)
	_les_distances_du_disque_tiennent_la_demonstration(v)
	_forger_produit_reellement_de_la_matiere_et_la_conserve(v)
	_expression_gd_n_est_jamais_preload_par_ce_banc(v)
	_hors_domaine_le_meme_code_traverse_un_vocabulaire_invente(v)

	if v.echecs() > 0:
		print("ECHEC: %d verification(s) en echec" % v.echecs())
		quit(1)
	else:
		print("OK: banc_marche_competence -- prix (offre percue, demande comptee, recalcul a neuf, divergence par perception), competence (usage, rouille, plancher a la lecture), habitude (vitesse de forge, perte du rythme) et specialisation (saillance deformee par percevant)")
		quit(0)

# ---- Outils de scenario -------------------------------------------------

# Construit la scene EXACTEMENT comme _ready la construit : memes fonctions
# statiques, aucune fixture parallele.
func _scene(config: Dictionary) -> Dictionary:
	var forge: Dictionary = Banc.construire_forge(config)
	var tas: Dictionary = {}
	var actifs: Dictionary = {}
	for decl in config.get("tas", []):
		var t: Dictionary = Banc.construire_tas(decl, config)
		tas[t.id] = t
		actifs[t.id] = true
	var colons: Array = []
	var veut: Dictionary = {}
	var horloges: Dictionary = {}
	for decl in config.get("colons", []):
		var colon: Dictionary = Banc.construire_colon(decl, config)
		colons.append(colon)
		veut[colon.id] = bool(decl.get("forge_au_depart", false))
		horloges[colon.id] = 0.0
	var scene: Dictionary = {
		"colons": colons, "forge": forge, "tas": tas, "actifs": actifs,
		"veut": veut, "horloges": horloges, "demande": 0, "infos": {},
	}
	_reconstruire(scene)
	return scene

func _reconstruire(scene: Dictionary) -> void:
	var monde = Monde.new()
	for colon in scene.colons:
		monde.ajouter(colon, "colon", colon.position)
	monde.ajouter(scene.forge, "forge", scene.forge.position)
	for id in scene.tas:
		if bool(scene.actifs.get(id, false)):
			monde.ajouter(scene.tas[id], "tas", scene.tas[id].position)
	scene["monde"] = monde

func _retirer(scene: Dictionary, id: String) -> void:
	scene.actifs[id] = false
	_reconstruire(scene)

func _production(scene: Dictionary, config: Dictionary):
	var id := String(config.tas_production)
	if not scene.tas.has(id) or not bool(scene.actifs.get(id, false)):
		return null
	return scene.tas[id]

func _colon(scene: Dictionary, id: String) -> Dictionary:
	for colon in scene.colons:
		if String(colon.id) == id:
			return colon
	return {}

func _simuler(scene: Dictionary, config: Dictionary, ticks: int) -> void:
	for i in range(ticks):
		var resultat: Dictionary = Banc.avancer_tick(
			scene.colons, scene.monde, scene.forge, _production(scene, config),
			scene.veut, scene.horloges, DELTA, config,
			_canaux(), _profils(), _deformations(), _epigenetique(), _comptages())
		scene["infos"] = resultat.infos
		scene["horloges"] = resultat.horloges
		scene["demande"] = int(resultat.demande)

func _infos(scene: Dictionary, id: String) -> Dictionary:
	return scene.infos.get(id, {})

func _masse(scene: Dictionary, config: Dictionary, id: String) -> float:
	return float(scene.tas[id].proprietes.reserves[String(config.nom_reserve_masse)].reserve)

func _marchandise(config: Dictionary, nom: String) -> Dictionary:
	return Banc.marchandise_par_nom(config, nom)

func _premiere_marchandise(config: Dictionary) -> Dictionary:
	return config.marchandises[0]

# ---- Cas ---------------------------------------------------------------

func _le_prix_monte_quand_l_offre_baisse(v) -> void:
	var config := _config()
	var marchandise := _premiere_marchandise(config)

	# D'abord la formule, nue : c'est elle qui porte la ligne.
	var cher: float = Banc.calculer_prix(10.0, 2, marchandise)
	var abondant: float = Banc.calculer_prix(100.0, 2, marchandise)
	v.v(cher > abondant,
		"a demande egale, une offre plus faible doit donner un prix PLUS HAUT (%f contre %f)" % [cher, abondant])
	v.v(Banc.calculer_prix(0.0, 2, marchandise) > cher,
		"une offre nulle doit donner le prix le plus haut que la formule sait produire, jamais une division par zero")

	# Puis le chemin REEL, en retirant un tas de la scene du disque.
	var scene := _scene(config)
	scene.veut["forgeron"] = false
	scene.veut["apprenti"] = false
	_simuler(scene, config, 1)
	var avant: float = float(_infos(scene, "novice").prix[String(marchandise.nom)])
	var offre_avant: float = float(_infos(scene, "novice").offres[String(marchandise.nom)])

	_retirer(scene, "lingot_comptoir_a")
	_simuler(scene, config, 1)
	var apres: float = float(_infos(scene, "novice").prix[String(marchandise.nom)])
	var offre_apres: float = float(_infos(scene, "novice").offres[String(marchandise.nom)])

	v.v(offre_apres < offre_avant,
		"retirer un tas doit faire BAISSER l'offre percue (%f puis %f)" % [offre_avant, offre_apres])
	v.v(apres > avant,
		"l'offre qui baisse doit faire MONTER le prix (%f puis %f)" % [avant, apres])

func _le_prix_est_recalcule_a_neuf_jamais_accumule(v) -> void:
	# LE piege que ce banc existe aussi pour eviter : un champ derive ecrit par
	# '+=' DERIVE sans borne (resultat negatif mesure quatre fois dans le depot).
	var config := _config()
	var scene := _scene(config)
	var colon := _colon(scene, "novice")
	var marchandise := _premiere_marchandise(config)
	var nom_prix := String(marchandise.nom_prix)

	var offres: Dictionary = {}
	for m in config.marchandises:
		offres[String(m.nom)] = 50.0

	var premier: float = float(Banc.poser_prix(colon, offres, 2, config)[String(marchandise.nom)])
	var deuxieme: float = float(Banc.poser_prix(colon, offres, 2, config)[String(marchandise.nom)])
	var troisieme: float = float(Banc.poser_prix(colon, offres, 2, config)[String(marchandise.nom)])
	v.v(is_equal_approx(premier, deuxieme) and is_equal_approx(deuxieme, troisieme),
		"trois poses de suite sur les MEMES entrees doivent rendre le MEME prix (%f, %f, %f) -- un '+=' l'aurait triple" % [premier, deuxieme, troisieme])
	v.v(is_equal_approx(float(colon.proprietes[nom_prix]), premier),
		"poser_prix doit ecrire dans la propriete exactement ce qu'il rend")

	# Contre-epreuve : une valeur absurde ecrite a la main est ECRASEE, jamais
	# ajoutee.
	colon.proprietes[nom_prix] = 9999.0
	Banc.poser_prix(colon, offres, 2, config)
	v.v(is_equal_approx(float(colon.proprietes[nom_prix]), premier),
		"le prix doit etre ECRIT PAR-DESSUS la valeur du tick precedent, recu %f au lieu de %f" % [float(colon.proprietes[nom_prix]), premier])

func _deux_colons_estiment_deux_prix_parce_qu_ils_ne_voient_pas_le_meme_stock(v) -> void:
	# LA LIGNE 9 DANS SA FORME LA PLUS NETTE : rien ne distingue les deux colons
	# que leur PERCEPTION, et pourtant leurs prix n'ont rien a voir.
	var config := _config()
	var scene := _scene(config)
	scene.veut["forgeron"] = false
	scene.veut["apprenti"] = false
	_simuler(scene, config, 1)
	var marchandise := _premiere_marchandise(config)
	var nom := String(marchandise.nom)

	var offre_forgeron: float = float(_infos(scene, "forgeron").offres[nom])
	var offre_novice: float = float(_infos(scene, "novice").offres[nom])
	v.v(offre_novice > offre_forgeron,
		"le colon poste au comptoir doit voir PLUS de stock que celui de l'atelier (%f contre %f)" % [offre_novice, offre_forgeron])

	var prix_forgeron: float = float(_infos(scene, "forgeron").prix[nom])
	var prix_novice: float = float(_infos(scene, "novice").prix[nom])
	v.v(prix_forgeron > prix_novice,
		"celui qui voit moins de stock doit estimer un prix PLUS HAUT (%f contre %f)" % [prix_forgeron, prix_novice])
	v.v(float(_colon(scene, "forgeron").proprietes[String(marchandise.nom_prix)]) == prix_forgeron
			and float(_colon(scene, "novice").proprietes[String(marchandise.nom_prix)]) == prix_novice,
		"le prix doit vivre SUR CHAQUE COLON, jamais dans un objet-marche partage")

	# ET le retrait d'un tas que le forgeron NE VOIT PAS ne bouge pas son prix
	# d'une decimale -- c'est la preuve que l'offre est bien PERCUE.
	_retirer(scene, "lingot_comptoir_b")
	_simuler(scene, config, 1)
	v.v(is_equal_approx(float(_infos(scene, "forgeron").prix[nom]), prix_forgeron),
		"retirer un tas hors de sa vue ne doit RIEN changer au prix du forgeron (%f puis %f)" % [prix_forgeron, float(_infos(scene, "forgeron").prix[nom])])
	v.v(float(_infos(scene, "novice").prix[nom]) > prix_novice,
		"le meme retrait doit faire monter le prix de celui qui voyait le tas")

func _la_demande_est_un_compte_d_entites_lu_par_comptage(v) -> void:
	var config := _config()
	var scene := _scene(config)
	_simuler(scene, config, 1)
	v.v(scene.demande == 2,
		"deux colons naissent sous le seuil de faim du catalogue partage, la demande doit valoir 2 au premier tick, recu %d" % scene.demande)

	var regle: Dictionary = _comptages()[String(config.comptage_ref)]
	v.v(String(regle.propriete) == String(config.nom_manque_energie),
		"le miroir ecrit par le banc et la propriete comptee par '%s' doivent etre le MEME nom" % String(config.comptage_ref))
	v.v(String(regle.mode) == "superieur_a",
		"la demande se lit sur un manque qui MONTE, donc en mode superieur_a")

	# Vider l'energie du troisieme colon le fait entrer dans la demande, sans
	# qu'aucune ligne du banc ne le nomme.
	_colon(scene, "novice").proprietes.reserves[String(config.nom_reserve_energie)]["reserve"] = 0.0
	_simuler(scene, config, 1)
	v.v(scene.demande == 3,
		"un troisieme colon affame doit faire monter la demande a 3, recu %d" % scene.demande)

func _la_competence_monte_par_usage(v) -> void:
	var config := _config()
	var scene := _scene(config)
	var apprenti := _colon(scene, "apprenti")
	v.v(Banc.modulateur_competence(apprenti, config) == 0.0,
		"l'apprenti doit naitre SANS aucune competence, recu %f" % Banc.modulateur_competence(apprenti, config))

	_simuler(scene, config, 50)
	var apres_5s: float = Banc.modulateur_competence(apprenti, config)
	v.v(apres_5s > 0.0,
		"5 s de forge doivent avoir depose une competence, recu %f" % apres_5s)
	_simuler(scene, config, 50)
	var apres_10s: float = Banc.modulateur_competence(apprenti, config)
	v.v(apres_10s > apres_5s,
		"la competence doit CONTINUER de monter tant que l'usage dure (%f puis %f)" % [apres_5s, apres_10s])

	# Le novice, dans la MEME scene et au MEME instant, n'a rien accumule.
	v.v(Banc.modulateur_competence(_colon(scene, "novice"), config) == 0.0,
		"le colon qui ne forge pas ne doit rien accumuler du tout")

func _la_competence_decroit_sans_usage(v) -> void:
	var config := _config()
	var scene := _scene(config)
	scene.veut["forgeron"] = false
	var forgeron := _colon(scene, "forgeron")
	var depart: float = Banc.modulateur_competence(forgeron, config)
	v.v(depart > 0.0,
		"le forgeron doit naitre avec une competence installee, recu %f" % depart)

	_simuler(scene, config, 50)
	var apres: float = Banc.modulateur_competence(forgeron, config)
	v.v(apres < depart,
		"la competence doit DECROITRE sans usage (%f puis %f)" % [depart, apres])
	v.v(apres > 0.0,
		"5 s d'arret ne doivent pas effacer une competence bien installee, recu %f" % apres)

	# Et elle remonte des qu'il s'y remet : la decroissance n'est pas un
	# aller simple.
	scene.veut["forgeron"] = true
	_simuler(scene, config, 50)
	v.v(Banc.modulateur_competence(forgeron, config) > apres,
		"reprendre la forge doit refaire monter la competence (%f puis %f)" % [apres, Banc.modulateur_competence(forgeron, config)])

func _le_plancher_empeche_la_competence_de_tomber_a_zero(v) -> void:
	# LA LIGNE 12. plancher_suppression du catalogue SUPPRIME l'entree, il ne
	# borne rien : sans le clamp a la lecture du cablage, le veteran redeviendrait
	# un novice d'un coup.
	var config := _config()
	var scene := _scene(config)
	scene.veut["forgeron"] = false
	var forgeron := _colon(scene, "forgeron")
	var plancher: float = Banc.plancher_competence(forgeron, config)
	v.v(plancher > 0.0,
		"le forgeron veteran doit porter un plancher strictement positif, recu %f" % plancher)

	# Assez longtemps pour que epigenetique.gd retire l'entree sous son
	# plancher_suppression.
	_simuler(scene, config, 400)
	v.v(not forgeron.proprietes.marques_epigenetiques.has(String(config.nom_marque_competence)),
		"apres un long arret, epigenetique.gd doit avoir RETIRE l'entree (marques restantes : %s)"
			% str(forgeron.proprietes.marques_epigenetiques.keys()))
	v.v(Banc.modulateur_competence(forgeron, config) == 0.0,
		"marque retiree : le modulateur BRUT doit valoir exactement 0.0, recu %f" % Banc.modulateur_competence(forgeron, config))
	v.v(is_equal_approx(Banc.competence_effective(forgeron, config), plancher),
		"la competence EFFECTIVE ne doit jamais descendre sous le plancher %f, recu %f" % [plancher, Banc.competence_effective(forgeron, config)])

	# Et le plancher ne PLAFONNE jamais : au-dessus de lui, c'est le modulateur
	# qui commande.
	forgeron.proprietes.marques_epigenetiques[String(config.nom_marque_competence)] = {"modulateur": 0.8, "age_marque": 0.0}
	v.v(is_equal_approx(Banc.competence_effective(forgeron, config), 0.8),
		"au-dessus du plancher, la competence effective doit valoir le modulateur, recu %f" % Banc.competence_effective(forgeron, config))

func _le_novice_n_a_pas_de_plancher_donc_pas_de_competence(v) -> void:
	# LE CAS QUI INTERDIT D'ECRIRE LE PLANCHER COMME UNE CONSTANTE DU CABLAGE :
	# max(0.3, modulateur) applique a tout le monde donnerait 0.3 au novice, et
	# « la forge n'est pas plus attractive pour lui » serait faux tous tests verts.
	var config := _config()
	var scene := _scene(config)
	var novice := _colon(scene, "novice")
	v.v(Banc.plancher_competence(novice, config) == 0.0,
		"le novice doit porter un plancher NUL, recu %f" % Banc.plancher_competence(novice, config))
	v.v(Banc.competence_effective(novice, config) == 0.0,
		"un plancher nul et aucune marque doivent donner une competence effective exactement nulle, recu %f" % Banc.competence_effective(novice, config))
	_simuler(scene, config, 200)
	v.v(Banc.competence_effective(novice, config) == 0.0,
		"20 s plus tard, le novice ne doit toujours avoir aucune competence, recu %f" % Banc.competence_effective(novice, config))

func _l_habitude_accelere_la_vitesse_de_forge(v) -> void:
	var config := _config()
	var scene := _scene(config)
	var apprenti := _colon(scene, "apprenti")
	var nu: float = Banc.vitesse_forge_effective(apprenti, config)
	v.v(is_equal_approx(nu, float(config.vitesse_forge_base)),
		"sans habitude, la vitesse de forge doit valoir exactement la base %f, recu %f" % [float(config.vitesse_forge_base), nu])

	_simuler(scene, config, 100)
	var rodee: float = Banc.vitesse_forge_effective(apprenti, config)
	v.v(rodee > nu,
		"10 s de forge doivent ACCELERER la forge (%f puis %f)" % [nu, rodee])
	v.v(is_equal_approx(rodee, float(config.vitesse_forge_base) * (1.0 + Banc.habitude_clampee(apprenti, config))),
		"la vitesse doit valoir exactement base x (1 + habitude clampee), recu %f" % rodee)

	# Et l'acceleration se voit dans la MATIERE produite, pas seulement dans le
	# nombre affiche : meme delta, plus de masse.
	var lent := _scene(_config())
	var produit_lent: float = Banc.forger(
		_colon(lent, "apprenti"), lent.forge, lent.tas[String(config.tas_production)], true, DELTA, config)
	var produit_rapide: float = Banc.forger(
		apprenti, scene.forge, scene.tas[String(config.tas_production)], true, DELTA, config)
	v.v(produit_rapide > produit_lent,
		"a delta egal, un colon rode doit produire PLUS de matiere (%f contre %f)" % [produit_rapide, produit_lent])

func _l_habitude_decroit_sans_repetition(v) -> void:
	var config := _config()
	var scene := _scene(config)
	var apprenti := _colon(scene, "apprenti")
	_simuler(scene, config, 100)
	var installee: float = Banc.modulateur_habitude(apprenti, config)
	v.v(installee > 0.0,
		"10 s de forge doivent avoir installe une habitude, recu %f" % installee)

	scene.veut["apprenti"] = false
	_simuler(scene, config, 30)
	var perdue: float = Banc.modulateur_habitude(apprenti, config)
	v.v(perdue < installee,
		"l'habitude doit DECROITRE des que la repetition cesse (%f puis %f)" % [installee, perdue])

	# LE GATE DE POSE BORNE LE MODULATEUR BRUT, et c'est une CONDITION
	# D'OBSERVABILITE, pas un confort (defaut trouve en lancant la scene) :
	# epigenetique.gd n'a aucune borne haute, et sans ce gate le modulateur
	# montait a 7.6 pour un plafond de lecture de 0.5 -- la vitesse restait bien
	# bornee, mais la marque mettait ensuite 95 s a se vider au lieu de 6, et
	# « il perd son rythme » devenait inobservable.
	v.v(installee <= float(config.plafond_habitude) + float(_epigenetique()[String(config.nom_marque_habitude)].modulateur_pose),
		"le modulateur BRUT ne doit jamais depasser son plafond de plus d'une pose (%f contre %f)"
			% [installee, float(config.plafond_habitude)])

	_simuler(scene, config, 100)
	v.v(Banc.modulateur_habitude(apprenti, config) == 0.0,
		"apres un long arret, epigenetique.gd doit avoir RETIRE la marque d'habitude, recu %f" % Banc.modulateur_habitude(apprenti, config))
	v.v(is_equal_approx(Banc.vitesse_forge_effective(apprenti, config), float(config.vitesse_forge_base)),
		"la vitesse de forge doit etre revenue exactement a sa base %f, recu %f"
			% [float(config.vitesse_forge_base), Banc.vitesse_forge_effective(apprenti, config)])

	# L'HABITUDE SE PERD PLUS VITE QUE LA COMPETENCE, c'est le contraste que le
	# chantier existe pour montrer -- verifie sur les taux REELS du disque.
	var epi := _epigenetique()
	v.v(float(epi[String(config.nom_marque_habitude)].taux_decroissance)
			> float(epi[String(config.nom_marque_competence)].taux_decroissance),
		"le rythme (habitude) doit se perdre PLUS VITE que le savoir (competence)")

func _la_specialisation_monte_la_saillance_du_forgeable(v) -> void:
	# LA LIGNE 10. La saillance d'une chose est UNE, lue dans
	# data/profils_saillance.json ; seule la deformation, indexee PAR PERCEVANT,
	# permet a deux entites de lire la meme forge differemment.
	var config := _config()
	var scene := _scene(config)
	_simuler(scene, config, 100)
	var infos := _infos(scene, "forgeron")

	v.v(float(infos.saillance_nue_forge) > 0.0,
		"la forge doit etre saillante en soi pour un lecteur sans deformation, recu %f" % float(infos.saillance_nue_forge))
	v.v(float(infos.saillance_forge) > float(infos.saillance_nue_forge),
		"la specialisation doit MONTER la saillance du forgeable (%f contre %f nue)"
			% [float(infos.saillance_forge), float(infos.saillance_nue_forge)])

	# Le facteur est exactement la composition EN SEQUENCE des deux sources
	# (proximite.gd, multiplicative) -- jamais une addition.
	var attendu: float = float(infos.saillance_nue_forge) \
		* (1.0 + float(infos.biais_competence)) * (1.0 + float(infos.biais_habitude))
	v.v(is_equal_approx(float(infos.saillance_forge), attendu),
		"les deux sources doivent se composer MULTIPLICATIVEMENT : attendu %f, recu %f" % [attendu, float(infos.saillance_forge)])

	var etat: Dictionary = _colon(scene, "forgeron").proprietes.deformation_etat
	v.v(etat.has(String(config.source_deformation_competence)) and etat.has(String(config.source_deformation_habitude)),
		"les DEUX sources doivent tenir chacune leur registre, recu %s" % str(etat.keys()))

func _le_novice_n_a_aucune_deformation(v) -> void:
	var config := _config()
	var scene := _scene(config)
	_simuler(scene, config, 200)
	var novice := _colon(scene, "novice")
	var infos := _infos(scene, "novice")

	v.v(novice.proprietes.deformation_etat.is_empty(),
		"le novice ne doit porter AUCUN registre de deformation, recu %s" % str(novice.proprietes.deformation_etat.keys()))
	v.v(float(infos.biais_competence) == 0.0 and float(infos.biais_habitude) == 0.0,
		"ses deux biais doivent valoir exactement 0.0, recus %f et %f" % [float(infos.biais_competence), float(infos.biais_habitude)])
	v.v(float(infos.saillance_forge) > 0.0,
		"il doit tout de meme PERCEVOIR la forge -- ce n'est pas la perception qui le distingue, recu %f" % float(infos.saillance_forge))
	v.v(is_equal_approx(float(infos.saillance_forge), float(infos.saillance_nue_forge)),
		"la forge doit lui arriver a sa saillance NUE, sans un poil de modulation (%f contre %f)"
			% [float(infos.saillance_forge), float(infos.saillance_nue_forge)])

func _le_gate_de_portee_ferme_la_forge_au_colon_eloigne(v) -> void:
	var config := _config()
	var scene := _scene(config)
	v.v(Banc.a_portee_forge(_colon(scene, "forgeron"), scene.forge, config),
		"le forgeron doit etre a portee de la forge dans la scene du disque")
	v.v(not Banc.a_portee_forge(_colon(scene, "novice"), scene.forge, config),
		"le colon poste au comptoir ne doit PAS etre a portee de la forge")

	# Meme force a forger, il ne forge pas et n'accumule rien : c'est la PORTEE
	# qui ferme, pas le toggle.
	scene.veut["novice"] = true
	_simuler(scene, config, 100)
	v.v(not bool(_infos(scene, "novice").en_forge),
		"un colon hors de portee ne doit jamais forger, meme toggle actif")
	v.v(Banc.modulateur_habitude(_colon(scene, "novice"), config) == 0.0,
		"et il ne doit accumuler aucune habitude, recu %f" % Banc.modulateur_habitude(_colon(scene, "novice"), config))
	v.v(float(_infos(scene, "novice").surcout.total) == 0.0,
		"ni payer le surcout d'une forge qu'il n'atteint pas")

func _les_trois_plafonds_du_cablage_tiennent(v) -> void:
	# Ni epigenetique.gd ni deformation.gd n'ont de borne haute, et deformation.gd
	# decroit par SOUSTRACTION FIXE : il n'existe AUCUN equilibre naturel. Sans
	# ces trois plafonds, la forge finirait par tout ecraser.
	var config := _config()
	var scene := _scene(config)
	_simuler(scene, config, 600)

	var forgeron := _colon(scene, "forgeron")
	# LE GATE DE POSE : les modulateurs BRUTS eux-memes restent bornes, a une pose
	# pres. Sans lui, 60 s de forge les portaient au-dela de 7 -- rien de faux, la
	# lecture restait clampee, mais la decroissance qui porte les lignes 11 et 12
	# devenait dix fois plus longue que ce que la calibration annonce.
	var epi := _epigenetique()
	v.v(Banc.modulateur_competence(forgeron, config)
			<= float(config.plafond_competence) + float(epi[String(config.nom_marque_competence)].modulateur_pose),
		"le modulateur BRUT de competence doit rester borne par le gate de pose, recu %f pour un plafond de %f"
			% [Banc.modulateur_competence(forgeron, config), float(config.plafond_competence)])
	v.v(Banc.modulateur_habitude(forgeron, config)
			<= float(config.plafond_habitude) + float(epi[String(config.nom_marque_habitude)].modulateur_pose),
		"le modulateur BRUT d'habitude doit rester borne par le gate de pose, recu %f pour un plafond de %f"
			% [Banc.modulateur_habitude(forgeron, config), float(config.plafond_habitude)])
	v.v(Banc.habitude_clampee(forgeron, config) <= float(config.plafond_habitude) + 0.0001,
		"l'habitude lue doit rester sous son plafond %f, recu %f" % [float(config.plafond_habitude), Banc.habitude_clampee(forgeron, config)])
	v.v(Banc.vitesse_forge_effective(forgeron, config)
			<= float(config.vitesse_forge_base) * (1.0 + float(config.plafond_habitude)) + 0.0001,
		"la vitesse de forge doit rester bornee, recu %f" % Banc.vitesse_forge_effective(forgeron, config))

	var infos := _infos(scene, "forgeron")
	v.v(float(infos.biais_competence) <= float(config.plafond_biais_competence) + 0.5,
		"le biais de competence doit rester au voisinage de son plafond %f, recu %f"
			% [float(config.plafond_biais_competence), float(infos.biais_competence)])
	v.v(float(infos.biais_habitude) <= float(config.plafond_biais_habitude) + 0.5,
		"le biais d'habitude doit rester au voisinage de son plafond %f, recu %f"
			% [float(config.plafond_biais_habitude), float(infos.biais_habitude)])

	# Contre-epreuve du clamp : un modulateur emballe ne fait pas exploser la
	# vitesse.
	forgeron.proprietes.marques_epigenetiques[String(config.nom_marque_habitude)] = {"modulateur": 50.0, "age_marque": 0.0}
	v.v(Banc.habitude_clampee(forgeron, config) == float(config.plafond_habitude),
		"un modulateur emballe doit etre borne au plafond, recu %f" % Banc.habitude_clampee(forgeron, config))

func _l_intervalle_de_pose_du_disque_laisse_les_deux_marques_survivre(v) -> void:
	# CONTRAINTE DE CADENCE, deja payee deux fois dans le depot : une marque qui
	# vient d'etre posee vaut modulateur_pose et est RETIREE des qu'elle passe
	# sous plancher_suppression. Un intervalle trop long l'efface entre deux
	# poses -- elle n'accumule JAMAIS rien, et rien d'autre ne rougit.
	var config := _config()
	var epi := _epigenetique()
	var intervalle: float = float(config.intervalle_pose_marque_s)
	for cle in [String(config.nom_marque_competence), String(config.nom_marque_habitude)]:
		var regle: Dictionary = epi[cle]
		var marge: float = float(regle.modulateur_pose) - float(regle.plancher_suppression)
		v.v(marge > 0.0,
			"plancher_suppression (%f) doit rester SOUS modulateur_pose (%f) pour '%s'"
				% [float(regle.plancher_suppression), float(regle.modulateur_pose), cle])
		var survie: float = marge / float(regle.taux_decroissance)
		v.v(intervalle < survie,
			"l'intervalle de pose (%f s) doit rester sous la duree de survie d'une marque fraiche de '%s' (%f s)"
				% [intervalle, cle, survie])

	# Preuve par le COMPORTEMENT, pas seulement par l'inegalite.
	var scene := _scene(config)
	_simuler(scene, config, 300)
	var apprenti := _colon(scene, "apprenti")
	v.v(Banc.modulateur_competence(apprenti, config) > float(epi[String(config.nom_marque_competence)].modulateur_pose) * 3.0,
		"30 s de forge doivent ACCUMULER, pas se reduire a la derniere pose, recu %f" % Banc.modulateur_competence(apprenti, config))

	# CONTRE-EPREUVE : le meme code avec un intervalle trop long n'accumule
	# jamais rien.
	var config_lent := _config()
	config_lent["intervalle_pose_marque_s"] = 5.0
	var scene_lente := _scene(config_lent)
	_simuler(scene_lente, config_lent, 300)
	v.v(Banc.modulateur_competence(_colon(scene_lente, "apprenti"), config_lent)
			<= float(epi[String(config.nom_marque_competence)].modulateur_pose) + 0.0001,
		"contre-epreuve : un intervalle superieur a la survie de la marque ne doit JAMAIS accumuler, recu %f"
			% Banc.modulateur_competence(_colon(scene_lente, "apprenti"), config_lent))

func _les_distances_du_disque_tiennent_la_demonstration(v) -> void:
	# TOUTE la demonstration de la ligne 9 repose sur ces distances. Les verifier
	# par le MECANISME (les portees reelles), jamais par des constantes recopiees.
	var config := _config()
	var scene := _scene(config)
	_simuler(scene, config, 1)

	var perceptions_forgeron: Array = _infos(scene, "forgeron").perceptions
	var perceptions_novice: Array = _infos(scene, "novice").perceptions
	var vus_forgeron: Array = []
	for entree in perceptions_forgeron:
		vus_forgeron.append(String(entree.chose.id))
	var vus_novice: Array = []
	for entree in perceptions_novice:
		vus_novice.append(String(entree.chose.id))

	v.v(vus_forgeron.has(String(config.tas_production)),
		"le forgeron doit voir le tas de l'atelier, recu %s" % str(vus_forgeron))
	v.v(not vus_forgeron.has("lingot_comptoir_a") and not vus_forgeron.has("lingot_comptoir_b"),
		"il ne doit voir AUCUN tas du comptoir, recu %s" % str(vus_forgeron))
	for decl in config.get("tas", []):
		v.v(vus_novice.has(String(decl.id)),
			"le colon du comptoir doit voir TOUS les tas, '%s' manque dans %s" % [String(decl.id), str(vus_novice)])
	v.v(vus_novice.has(String(config.forge.id)),
		"il doit voir la forge sans etre a sa portee de travail : voir n'est pas atteindre")

func _forger_produit_reellement_de_la_matiere_et_la_conserve(v) -> void:
	# consommer.gd est CONSERVATIF PAR CONSTRUCTION : ce qui sort du minerai entre
	# exactement dans le tas. Le verifier ici, c'est verifier que le cablage ne
	# fabrique rien a cote.
	var config := _config()
	var scene := _scene(config)
	var minerai_avant: float = float(scene.forge.proprietes.reserves[String(config.nom_reserve_minerai)].reserve)
	var tas_avant: float = _masse(scene, config, String(config.tas_production))
	_simuler(scene, config, 100)
	var minerai_apres: float = float(scene.forge.proprietes.reserves[String(config.nom_reserve_minerai)].reserve)
	var tas_apres: float = _masse(scene, config, String(config.tas_production))

	v.v(tas_apres > tas_avant,
		"forger doit faire GROSSIR le tas de l'atelier (%f puis %f)" % [tas_avant, tas_apres])
	v.v(is_equal_approx(minerai_avant - minerai_apres, tas_apres - tas_avant),
		"la matiere doit etre CONSERVEE : minerai perdu %f, masse gagnee %f"
			% [minerai_avant - minerai_apres, tas_apres - tas_avant])

	# Tas de production retire : la forge tourne a vide, rien n'apparait.
	var scene2 := _scene(_config())
	_retirer(scene2, String(config.tas_production))
	var minerai2: float = float(scene2.forge.proprietes.reserves[String(config.nom_reserve_minerai)].reserve)
	_simuler(scene2, config, 20)
	v.v(is_equal_approx(float(scene2.forge.proprietes.reserves[String(config.nom_reserve_minerai)].reserve), minerai2),
		"sans tas ou verser, la forge ne doit consommer AUCUN minerai")

func _expression_gd_n_est_jamais_preload_par_ce_banc(v) -> void:
	# CONTOURNEMENT INTENTIONNEL, verrouille NEGATIVEMENT : le mecanisme dormant
	# fait DIVERGER SANS BORNE la propriete visee quand il est rappele chaque tick
	# (resultat negatif mesure quatre fois, voir data/epigenetique.json). Le
	# chemin est compose morceau par morceau ici, pour que ni ce test ni l'en-tete
	# du banc ne se fassent rougir par leur propre verrou.
	var chemin_interdit := "res://scripts/" + "expression" + ".gd"
	var source := FileAccess.get_file_as_string("res://scripts/banc_marche_competence.gd")
	v.v(source != "",
		"le fichier du banc doit etre lisible sur le disque pour que ce verrou ait un sens")
	v.v(not source.contains(chemin_interdit),
		"le banc ne doit JAMAIS preload le mecanisme dormant -- il compose les modulateurs lui-meme")
	v.v(source.contains("epigenetique.gd") and source.contains("deformation.gd"),
		"garde-fou de ce verrou : il doit bien lire le fichier attendu (les deux mecanismes reellement cables y sont)")

func _hors_domaine_le_meme_code_traverse_un_vocabulaire_invente(v) -> void:
	# PREUVE que le cablage ne porte aucun nom en dur : meme code, vocabulaire
	# entierement invente, catalogues locaux. Rien de ce qui suit n'existe dans le
	# depot.
	var config := _config()
	config["canaux"] = ["capteur_flux"]
	config["deformation_sources"] = ["maitrise_tissage", "cadence_tissage"]
	config["comptage_ref"] = "tisserands_en_manque"
	config["nom_reserve_energie"] = "souffle"
	config["nom_reserve_masse"] = "volume_range"
	config["nom_reserve_minerai"] = "fil_brut"
	config["nom_manque_energie"] = "deficit_souffle"
	config["nom_plancher_competence"] = "socle_maitrise"
	config["nom_marque_competence"] = "maitrise_tissage"
	config["nom_marque_habitude"] = "cadence_tissage"
	config["source_deformation_competence"] = "maitrise_tissage"
	config["source_deformation_habitude"] = "cadence_tissage"
	config["cible_deformation"] = "tissable"
	config["marchandises"] = [{
		"nom": "etoffe", "propriete": "etoffe", "nom_prix": "cours_etoffe",
		"poids_offre_demande": 300.0, "elasticite": 1.0, "couleur": [1.0, 1.0, 1.0],
	}]
	for decl in config.tas:
		decl["marchandise"] = "etoffe"
	config.forge["proprietes"] = {
		"tissable": true,
		"profil_saillance": "metier_a_tisser",
		"reserves": {"fil_brut": {"reserve": 500.0, "cout_base": 0.0, "surcout_action": 0.0}},
	}

	var canaux := {"capteur_flux": {"geometrie": "contact", "proprietes_captees": []}}
	var profils := {"metier_a_tisser": {"saillance_intrinseque": 2.0, "portee_saillance": 600.0}}
	var deformations := {
		"maitrise_tissage": {"sens": "monte", "taux_decroissance_rapide": 0.8, "taux_decroissance_lent": 0.5, "w_rapide": 0.8, "w_lent": 0.2},
		"cadence_tissage": {"sens": "monte", "taux_decroissance_rapide": 0.4, "taux_decroissance_lent": 0.2, "w_rapide": 0.6, "w_lent": 0.4},
	}
	var epi := {
		"maitrise_tissage": {"modulateur_pose": 0.04, "taux_decroissance": 0.05, "plancher_suppression": 0.02},
		"cadence_tissage": {"modulateur_pose": 0.05, "taux_decroissance": 0.08, "plancher_suppression": 0.02},
	}
	var comptages := {"tisserands_en_manque": {"propriete": "deficit_souffle", "mode": "superieur_a", "valeur_reference": 20.0}}

	var forge: Dictionary = Banc.construire_forge(config)
	var tas: Dictionary = {}
	var colons: Array = []
	var veut: Dictionary = {}
	var horloges: Dictionary = {}
	var monde = Monde.new()
	for decl in config.get("colons", []):
		var colon: Dictionary = Banc.construire_colon(decl, config)
		colons.append(colon)
		veut[colon.id] = bool(decl.get("forge_au_depart", false))
		horloges[colon.id] = 0.0
		monde.ajouter(colon, "tisserand", colon.position)
	monde.ajouter(forge, "metier", forge.position)
	for decl in config.get("tas", []):
		var t: Dictionary = Banc.construire_tas(decl, config)
		tas[t.id] = t
		monde.ajouter(t, "ballot", t.position)

	v.v(colons[0].proprietes.reserves.has("souffle"),
		"la reserve doit porter le nom invente, recu %s" % str(colons[0].proprietes.reserves.keys()))
	v.v(colons[0].proprietes.has("socle_maitrise"),
		"le plancher doit porter le nom invente")

	var infos: Dictionary = {}
	for i in range(200):
		var resultat: Dictionary = Banc.avancer_tick(
			colons, monde, forge, tas[String(config.tas_production)], veut, horloges, DELTA,
			config, canaux, profils, deformations, epi, comptages)
		infos = resultat.infos
		horloges = resultat.horloges

	var maitre: Dictionary = colons[0]
	v.v(maitre.proprietes.marques_epigenetiques.has("cadence_tissage"),
		"la marque inventee doit avoir ete posee, recu %s" % str(maitre.proprietes.marques_epigenetiques.keys()))
	v.v(maitre.proprietes.deformation_etat.has("maitrise_tissage"),
		"la source de deformation inventee doit tenir son registre, recu %s" % str(maitre.proprietes.deformation_etat.keys()))
	v.v(maitre.proprietes.has("cours_etoffe"),
		"le prix invente doit avoir ete ecrit sur le colon, proprietes %s" % str(maitre.proprietes.keys()))
	v.v(float(infos[maitre.id].saillance_forge) > float(infos[maitre.id].saillance_nue_forge),
		"la specialisation inventee doit monter la saillance de la chose inventee (%f contre %f)"
			% [float(infos[maitre.id].saillance_forge), float(infos[maitre.id].saillance_nue_forge)])
	v.v(colons[2].proprietes.deformation_etat.is_empty(),
		"le colon sans socle ni usage ne doit porter aucune deformation, meme en vocabulaire invente")
