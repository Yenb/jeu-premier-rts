extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_soudure.gd
#
# Verrouille le cablage de banc_soudure.gd (chantier "soudabilite", voir
# audit_soudabilite.md) : fonctions statiques pures (est_soudable/
# causes_de_soudure/paires_pretes/sources_du_tick/statut_pour_objet/
# couleur_pour_objet/texte_label/poser_etat_initial/ligne_*) plus un
# CHEMIN REEL combinant Temperature.avancer/SeuilEtat.avancer/
# Charge.avancer/Soudure.souder sur des objets FABRIQUES PAR COMPOSITION
# (data/materiaux.json/data/proprietes_immuables_composition.json/
# data/temperature.json/data/seuils_etat.json/data/soudure.json lus sur
# disque) -- deux fers "chauffes" (source constante, meme forme que le
# clic maintenu du banc reel) au contact doivent reellement fusionner
# pendant qu'un bois identique ne se soude jamais, et "relacher" (source
# vide) apres coup ne doit jamais defaire le composite ni faire reapparaitre
# l'alarme "sans propriete temperature" corrigee par poser_etat_initial.

const Objet = preload("res://scripts/objet.gd")
const Temperature = preload("res://scripts/temperature.gd")
const SeuilEtat = preload("res://scripts/seuil_etat.gd")
const Charge = preload("res://scripts/charge.gd")
const Soudure = preload("res://scripts/soudure.gd")
const BancSoudure = preload("res://scripts/banc_soudure.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

func _init() -> void:
	_est_soudable_lit_la_propriete_fusionnee()
	_causes_de_soudure_filtre_soudable_et_chaud_et_s_exclut_soi_meme()
	_causes_de_soudure_ignore_les_fantomes()
	_causes_de_soudure_cible_froide_ne_produit_jamais_de_cause()
	_paires_pretes_exige_les_deux_marqueurs_et_le_contact()
	_sources_du_tick_vide_si_pas_chauffe()
	_sources_du_tick_porte_la_position_du_curseur_si_chauffe()
	_statut_pour_objet_les_quatre_cas()
	_poser_etat_initial_pose_temperature_etats_et_canal()
	_couleur_pour_objet_distingue_fer_et_bois()
	_texte_label_porte_le_statut_et_les_nombres()
	_texte_label_soude_masque_la_charge_de_soudure()
	_texte_label_fantome_n_affiche_aucun_zero_trompeur()
	_ligne_soudure_porte_les_ids_et_les_masses()
	_ligne_fantome_porte_l_id()

	_chemin_reel_deux_fers_froids_ne_se_soudent_pas()
	_chemin_reel_deux_fers_chauds_se_soudent_et_le_bois_jamais()
	_chemin_reel_relacher_apres_soudure_ne_defait_rien_et_ne_ralarme_pas()
	_chemin_reel_curseur_asymetrique_ne_desynchronise_pas_les_deux_charges()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: cablage banc_soudure -- causes/paires/sources/statuts/couleurs/" +
		"textes corrects, chemin reel (materiaux.json/proprietes_immuables_" +
		"composition.json/temperature.json/seuils_etat.json/soudure.json) : " +
		"deux fers froids ne se soudent jamais, deux fers chauffes au contact " +
		"fusionnent en un composite de masse exacte pendant qu'un bois identique " +
		"reste intact, relacher apres soudure ne defait jamais le composite et " +
		"ne fait jamais reapparaitre l'alarme 'sans propriete temperature'")
	quit(0)

# ---- fixtures locales (pas de disque) ----

func _chose(id: String, position: Vector3, proprietes: Dictionary) -> Dictionary:
	return {"id": id, "position": position, "proprietes": proprietes}

# ---- est_soudable ----

func _est_soudable_lit_la_propriete_fusionnee() -> void:
	verif.v(BancSoudure.est_soudable({"soudabilite": 0.8}) == true, "une soudabilite strictement positive doit rendre soudable")
	verif.v(BancSoudure.est_soudable({"soudabilite": 0.0}) == false, "une soudabilite nulle ne doit jamais rendre soudable")
	verif.v(BancSoudure.est_soudable({}) == false, "une propriete soudabilite absente doit rendre non soudable, jamais une alarme")

# ---- causes_de_soudure ----

func _causes_de_soudure_filtre_soudable_et_chaud_et_s_exclut_soi_meme() -> void:
	# "cible" doit ELLE-MEME etre chaude pour que la garde (voir en-tete de
	# causes_de_soudure) laisse passer quoi que ce soit -- fixture corrigee
	# apres le bug "la charge du deuxieme fer s'arrete" (voir ci-dessous).
	var cible := _chose("cible", Vector3.ZERO, {"soudabilite": 0.8, "etats_actifs": ["chaud"]})
	var voisin_valide := _chose("voisin_valide", Vector3(10, 0, 0), {"soudabilite": 0.8, "etats_actifs": ["chaud"]})
	var voisin_froid := _chose("voisin_froid", Vector3(10, 0, 0), {"soudabilite": 0.8, "etats_actifs": []})
	var voisin_non_soudable := _chose("voisin_non_soudable", Vector3(10, 0, 0), {"soudabilite": 0.0, "etats_actifs": ["chaud"]})
	var monde := [cible, voisin_valide, voisin_froid, voisin_non_soudable]

	var causes := BancSoudure.causes_de_soudure(cible, monde)
	verif.v(causes.size() == 1, "une seule cause valide (soudable ET chaud) doit ressortir, recu %d" % causes.size())
	verif.v(causes[0].position == voisin_valide.position, "la cause retenue doit etre le voisin valide")

	var causes_cible_elle_meme := BancSoudure.causes_de_soudure(voisin_valide, [voisin_valide])
	verif.v(causes_cible_elle_meme.is_empty(), "un objet ne doit jamais devenir sa propre cause")

func _causes_de_soudure_ignore_les_fantomes() -> void:
	var cible := _chose("cible", Vector3.ZERO, {"soudabilite": 0.8, "etats_actifs": ["chaud"]})
	var fantome := _chose("fantome", Vector3(10, 0, 0), {})
	var causes := BancSoudure.causes_de_soudure(cible, [cible, fantome])
	verif.v(causes.is_empty(), "un fantome (proprietes vide) ne doit jamais devenir une cause")

# Verrou DIRECT du bug "la charge du deuxieme fer s'arrete" (trouve a
# l'ecran) : une cible FROIDE ne doit JAMAIS accumuler de charge, meme si
# un voisin soudable est deja chaud -- sans cette garde, la charge d'un
# objet montait des qu'un voisin etait chaud, independamment de sa PROPRE
# temperature, ce qui geleait la charge de l'autre cote (celui deja
# chaud) tant que le voisin n'avait pas lui-meme franchi le seuil.
func _causes_de_soudure_cible_froide_ne_produit_jamais_de_cause() -> void:
	var cible_froide := _chose("cible_froide", Vector3.ZERO, {"soudabilite": 0.8, "etats_actifs": []})
	var voisin_chaud := _chose("voisin_chaud", Vector3(10, 0, 0), {"soudabilite": 0.8, "etats_actifs": ["chaud"]})
	var causes := BancSoudure.causes_de_soudure(cible_froide, [cible_froide, voisin_chaud])
	verif.v(causes.is_empty(), "une cible qui n'est pas ELLE-MEME chaude ne doit jamais recevoir de cause, meme si un voisin soudable est chaud")

# ---- paires_pretes ----

func _paires_pretes_exige_les_deux_marqueurs_et_le_contact() -> void:
	var proche_marque_a := _chose("a", Vector3(0, 0, 0), {"pret_a_souder": true})
	var proche_marque_b := _chose("b", Vector3(10, 0, 0), {"pret_a_souder": true})
	var proche_pas_marque := _chose("c", Vector3(15, 0, 0), {"pret_a_souder": false})
	var loin_marque := _chose("d", Vector3(1000, 0, 0), {"pret_a_souder": true})
	var fantome := _chose("e", Vector3(5, 0, 0), {})

	var paires := BancSoudure.paires_pretes([proche_marque_a, proche_marque_b, proche_pas_marque, loin_marque, fantome], "pret_a_souder", 50.0)
	verif.v(paires.size() == 1, "une seule paire doit ressortir (les deux marques ET en contact), recu %d" % paires.size())
	verif.v((paires[0].a.id == "a" and paires[0].b.id == "b") or (paires[0].a.id == "b" and paires[0].b.id == "a"), "la paire doit etre exactement (a, b)")

	var sans_marque := BancSoudure.paires_pretes([proche_marque_a, proche_pas_marque], "pret_a_souder", 50.0)
	verif.v(sans_marque.is_empty(), "sans les deux marqueurs, aucune paire ne doit ressortir")

	var trop_loin := BancSoudure.paires_pretes([proche_marque_a, loin_marque], "pret_a_souder", 50.0)
	verif.v(trop_loin.is_empty(), "hors de portee de contact, aucune paire ne doit ressortir meme si les deux portent le marqueur")

# ---- sources_du_tick (interactivite) ----

func _sources_du_tick_vide_si_pas_chauffe() -> void:
	var sources := BancSoudure.sources_du_tick(false, Vector3(10, 20, 0), 100.0, 900.0, 1.0)
	verif.v(sources.is_empty(), "relache (chauffe=false), aucune source ne doit exister -- meme contrat que sources_du_tick au-dela de duree_chauffe avant cette refonte")

func _sources_du_tick_porte_la_position_du_curseur_si_chauffe() -> void:
	var position := Vector3(37.0, -12.0, 0.0)
	var sources := BancSoudure.sources_du_tick(true, position, 100.0, 900.0, 1.0)
	verif.v(sources.size() == 1, "clic maintenu, exactement une source doit exister")
	verif.v(sources[0].position == position, "la source doit suivre EXACTEMENT la position du curseur, jamais une position fixe")
	verif.v(is_equal_approx(sources[0].temperature, 900.0), "la source doit porter la temperature configuree")
	verif.v(is_equal_approx(sources[0].rayon, 100.0), "la source doit porter le rayon configure")

# ---- statut_pour_objet ----

func _statut_pour_objet_les_quatre_cas() -> void:
	verif.v(BancSoudure.statut_pour_objet({}, "pret_a_souder") == "fantome", "des proprietes vides doivent rendre 'fantome'")
	verif.v(BancSoudure.statut_pour_objet({"composition": [{"materiau": "fer", "volume": 1.0}], "pret_a_souder": false}, "pret_a_souder") == "intact", "une composition a un seul element sans marqueur doit rendre 'intact'")
	verif.v(BancSoudure.statut_pour_objet({"composition": [{"materiau": "fer", "volume": 1.0}], "pret_a_souder": true}, "pret_a_souder") == "pret_a_souder", "le marqueur pose doit rendre 'pret_a_souder'")
	verif.v(BancSoudure.statut_pour_objet({"composition": [{"materiau": "fer", "volume": 1.0}, {"materiau": "fer", "volume": 1.5}], "pret_a_souder": false}, "pret_a_souder") == "soude", "une composition a PLUSIEURS elements doit rendre 'soude', meme sans le marqueur (une fusion a deja eu lieu)")

# ---- poser_etat_initial ----

func _poser_etat_initial_pose_temperature_etats_et_canal() -> void:
	var objet := {"id": "x", "position": Vector3.ZERO, "proprietes": {"composition": [{"materiau": "fer", "volume": 1.0}]}}
	BancSoudure.poser_etat_initial(objet, 456.0, "pret_a_souder", 2.0, 60.0, 1.0)
	verif.v(is_equal_approx(float(objet.proprietes.temperature), 456.0), "poser_etat_initial doit poser EXACTEMENT la temperature recue, jamais une constante")
	verif.v(objet.proprietes.etats_actifs == [], "poser_etat_initial doit repartir d'une liste d'etats actifs vide")
	var canal: Dictionary = objet.proprietes.etats.soudure
	verif.v(is_equal_approx(float(canal.charge), 0.0), "le canal de soudure doit repartir a charge zero")
	verif.v(is_equal_approx(float(canal.seuil), 2.0) and is_equal_approx(float(canal.portee_charge), 60.0) and is_equal_approx(float(canal.taux_decroissance), 1.0), "le canal de soudure doit porter EXACTEMENT les quatre reglages recus")
	verif.v(canal.poser.get("pret_a_souder", false) == true, "le canal doit poser le marqueur nomme, jamais un nom en dur")

# ---- rendu / textes ----

func _couleur_pour_objet_distingue_fer_et_bois() -> void:
	var couleur_fer := Color(0.5, 0.5, 0.5)
	var couleur_bois := Color(0.3, 0.2, 0.1)
	var tint_chaud := Color(1.0, 0.0, 0.0)
	var tint_pret := Color(0.0, 1.0, 0.0)

	var fer_intact := {"composition": [{"materiau": "fer", "volume": 1.0}], "etats_actifs": []}
	verif.v(BancSoudure.couleur_pour_objet(fer_intact, couleur_fer, couleur_bois, tint_chaud, tint_pret) == couleur_fer, "un fer intact doit rendre exactement couleur_fer")

	var bois_intact := {"composition": [{"materiau": "bois", "volume": 1.0}], "etats_actifs": []}
	verif.v(BancSoudure.couleur_pour_objet(bois_intact, couleur_fer, couleur_bois, tint_chaud, tint_pret) == couleur_bois, "un bois intact doit rendre exactement couleur_bois, jamais couleur_fer")

	var fer_chaud := {"composition": [{"materiau": "fer", "volume": 1.0}], "etats_actifs": ["chaud"]}
	verif.v(BancSoudure.couleur_pour_objet(fer_chaud, couleur_fer, couleur_bois, tint_chaud, tint_pret) != couleur_fer, "un fer chaud doit se teinter, jamais rester couleur_fer pure")

	var fer_pret := {"composition": [{"materiau": "fer", "volume": 1.0}], "etats_actifs": [], "pret_a_souder": true}
	verif.v(BancSoudure.couleur_pour_objet(fer_pret, couleur_fer, couleur_bois, tint_chaud, tint_pret) != couleur_fer, "un fer 'pret_a_souder' doit se teinter, jamais rester couleur_fer pure")

func _texte_label_porte_le_statut_et_les_nombres() -> void:
	var proprietes := {
		"composition": [{"materiau": "fer", "volume": 1.0}],
		"temperature": 123.4,
		"masse": 987.6,
		"etats_actifs": ["chaud"],
		"etats": {"soudure": {"charge": 1.5}},
		"pret_a_souder": true,
	}
	var texte := BancSoudure.texte_label("fer_test", proprietes, "pret_a_souder")
	verif.v(texte.find("fer_test") != -1, "le texte doit porter l'id")
	verif.v(texte.find("pret_a_souder") != -1, "le texte doit porter le statut")
	verif.v(texte.find("123.4") != -1, "le texte doit porter la temperature")
	verif.v(texte.find("987.6") != -1, "le texte doit porter la masse")
	verif.v(texte.find("1.50") != -1, "le texte doit porter la charge de soudure")
	verif.v(texte.find("chaud") != -1, "le texte doit porter les etats actifs")

# Verrou DIRECT du bug "la charge de fer_0 disparait et n'augmente plus
# quand fer_1 statut=fantome" (trouve a l'ecran) : une fois fusionne,
# l'objet n'a structurellement plus de voisin soudable, sa charge retombe
# donc a zero et y reste (comportement CORRECT du mecanisme, rien a
# fusionner avec) -- mais l'afficher a cote de "statut = soude" se lisait
# comme un recul. Decision Yael : masquer la ligne charge_soudure des que
# statut == "soude".
func _texte_label_soude_masque_la_charge_de_soudure() -> void:
	var proprietes := {
		"composition": [{"materiau": "fer", "volume": 1.0}, {"materiau": "fer", "volume": 1.5}],
		"temperature": 338.0,
		"masse": 19675.0,
		"etats_actifs": ["chaud"],
		"etats": {"soudure": {"charge": 0.0}},
		"pret_a_souder": false,
	}
	var texte := BancSoudure.texte_label("fer_0", proprietes, "pret_a_souder")
	verif.v(texte.find("statut = soude") != -1, "le texte doit porter le statut 'soude'")
	verif.v(texte.find("charge_soudure") == -1, "une fois soude, la ligne charge_soudure ne doit JAMAIS s'afficher -- plus rien qui puisse se lire comme un recul sur un objet deja fusionne")
	verif.v(texte.find("338.0") != -1 and texte.find("19675.0") != -1, "temperature et masse doivent rester affichees meme une fois soude")

func _texte_label_fantome_n_affiche_aucun_zero_trompeur() -> void:
	var texte := BancSoudure.texte_label("fer_1", {}, "pret_a_souder")
	verif.v(texte.find("fer_1") != -1, "le texte d'un fantome doit quand meme porter son id")
	verif.v(texte.find("fantome") != -1, "le texte d'un fantome doit porter le statut 'fantome' explicitement")
	verif.v(texte.find("0.0") == -1, "le texte d'un fantome ne doit JAMAIS afficher un zero de temperature/masse trompeur -- rien a lire, pas un objet froid et sans masse")

func _ligne_soudure_porte_les_ids_et_les_masses() -> void:
	var ligne := BancSoudure.ligne_soudure(12.5, "fer_0", "fer_1", 100.0, 200.0, 300.0)
	verif.v(ligne.find("fer_0") != -1 and ligne.find("fer_1") != -1, "la ligne doit porter les deux ids")
	verif.v(ligne.find("100.0") != -1 and ligne.find("200.0") != -1 and ligne.find("300.0") != -1, "la ligne doit porter les trois masses (avant/avant/apres)")

func _ligne_fantome_porte_l_id() -> void:
	var ligne := BancSoudure.ligne_fantome(8.0, "fer_1")
	verif.v(ligne.find("fer_1") != -1, "la ligne doit porter l'id de l'objet devenu fantome")
	verif.v(ligne.find("fantome") != -1, "la ligne doit nommer l'evenement 'fantome'")

# ---- Chemin reel ----

func _catalogues_reels() -> Dictionary:
	return {
		"materiaux": JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json")),
		"proprietes_immuables": JSON.parse_string(FileAccess.get_file_as_string("res://data/proprietes_immuables_composition.json")).get("proprietes", []),
		"temperature": JSON.parse_string(FileAccess.get_file_as_string("res://data/temperature.json")),
		"seuils": JSON.parse_string(FileAccess.get_file_as_string("res://data/seuils_etat.json")),
		"soudure": JSON.parse_string(FileAccess.get_file_as_string("res://data/soudure.json")),
	}

func _fabriquer_objet(id: String, materiau: String, volume: float, position: Vector3, cat: Dictionary) -> Dictionary:
	var table := {id: {"composition": [{"materiau": materiau, "volume": volume}]}}
	var objet := Objet.fabriquer(id, id, position, table, cat.materiaux, cat.proprietes_immuables)
	var config: Dictionary = cat.soudure.defaut
	BancSoudure.poser_etat_initial(objet, 20.0, config.nom_marqueur, config.seuil_charge, config.portee_contact, config.taux_decroissance)
	return objet

# Reproduit EXACTEMENT la partie logique de banc_soudure.gd:_process (pas
# le rendu) -- meme ordre d'appel (temperature -> seuil d'etat -> charge
# par objet soudable -> declenchement one-shot -> reinitialisation du
# survivant), sur les VRAIS mecanismes, jamais reimplementes. "sources"
# joue le role de l'etat du clic a ce tick : un Array non vide = maintenu
# (meme forme que BancSoudure.sources_du_tick(true, ...)), vide = relache.
func _avancer_tick(monde: Array, sources: Array, delta: float, cat: Dictionary) -> void:
	var vivant: Array = monde.filter(func(o): return not o.proprietes.is_empty())
	Temperature.avancer(vivant, sources, delta, cat.temperature)
	SeuilEtat.avancer(vivant, cat.seuils)
	var config: Dictionary = cat.soudure.defaut
	for objet in monde:
		if objet.proprietes.is_empty():
			continue
		if not BancSoudure.est_soudable(objet.proprietes):
			continue
		var causes := BancSoudure.causes_de_soudure(objet, monde)
		Charge.avancer([objet], causes, delta)
	for paire in BancSoudure.paires_pretes(monde, config.nom_marqueur, config.portee_contact):
		var a: Dictionary = paire.a
		var b: Dictionary = paire.b
		if a.proprietes.is_empty() or b.proprietes.is_empty():
			continue
		var temperature_avant: float = a.proprietes.get("temperature", 20.0)
		if Soudure.souder(a, b, cat.materiaux, cat.proprietes_immuables):
			BancSoudure.poser_etat_initial(a, temperature_avant, config.nom_marqueur, config.seuil_charge, config.portee_contact, config.taux_decroissance)

func _chemin_reel_deux_fers_froids_ne_se_soudent_pas() -> void:
	var cat := _catalogues_reels()
	var fer_0 := _fabriquer_objet("fer_0", "fer", 1.0, Vector3(0.0, 0.0, 0.0), cat)
	var fer_1 := _fabriquer_objet("fer_1", "fer", 1.5, Vector3(45.0, 0.0, 0.0), cat)
	var monde := [fer_0, fer_1]

	var t := 0.0
	var delta := 0.5
	while t < 60.0:
		_avancer_tick(monde, [], delta, cat) # clic jamais maintenu -- jamais "chaud"
		t += delta

	var nom_marqueur: String = cat.soudure.defaut.nom_marqueur
	verif.v(not fer_0.proprietes.is_empty(), "chemin reel : sans chaleur, fer_0 ne doit jamais se souder")
	verif.v(not fer_1.proprietes.is_empty(), "chemin reel : sans chaleur, fer_1 ne doit jamais se souder")
	verif.v(not fer_0.proprietes.get(nom_marqueur, false), "chemin reel : sans etat 'chaud', le marqueur ne doit jamais se poser")

func _chemin_reel_deux_fers_chauds_se_soudent_et_le_bois_jamais() -> void:
	var cat := _catalogues_reels()
	var fer_0 := _fabriquer_objet("fer_0", "fer", 1.0, Vector3(0.0, 0.0, 0.0), cat)
	var fer_1 := _fabriquer_objet("fer_1", "fer", 1.5, Vector3(45.0, 0.0, 0.0), cat)
	var bois_0 := _fabriquer_objet("bois_0", "bois", 1.0, Vector3(-45.0, 0.0, 0.0), cat)
	var masse_fer_0: float = fer_0.proprietes.masse
	var masse_fer_1: float = fer_1.proprietes.masse
	var monde := [bois_0, fer_0, fer_1]

	# Clic maintenu : source CONSTANTE centree sur le trio, rayon large --
	# equivalent de sources_du_tick(true, ...) tenu par le joueur sur toute
	# la duree, jamais une rampe automatique (celle-ci a disparu de la
	# refonte interactive).
	var sources := [{"position": Vector3(0.0, 0.0, 0.0), "rayon": 250.0, "temperature": 900.0, "force": 1.0}]
	var t := 0.0
	var delta := 0.5
	var fusionne := false
	while t < 60.0 and not fusionne:
		_avancer_tick(monde, sources, delta, cat)
		if fer_0.proprietes.is_empty() or fer_1.proprietes.is_empty():
			fusionne = true
		t += delta

	verif.v(fusionne, "chemin reel : deux fers chauffes au contact (clic maintenu) doivent finir par fusionner avant t=60s")

	var survivant: Dictionary = fer_0 if not fer_0.proprietes.is_empty() else fer_1
	var absorbe: Dictionary = fer_1 if survivant == fer_0 else fer_0
	verif.v(absorbe.proprietes.is_empty(), "chemin reel : l'objet absorbe doit avoir des proprietes entierement vides")
	verif.v(is_equal_approx(float(survivant.proprietes.masse), masse_fer_0 + masse_fer_1), "chemin reel : la masse du composite doit etre EXACTEMENT la somme des deux masses d'origine (%f), recu %f" % [masse_fer_0 + masse_fer_1, survivant.proprietes.masse])
	verif.v(survivant.proprietes.has("temperature"), "chemin reel : le composite survivant doit porter 'temperature' DES LE TICK DE LA SOUDURE -- verrou direct du bug 'sans propriete temperature' corrige par poser_etat_initial")

	var nom_marqueur: String = cat.soudure.defaut.nom_marqueur
	verif.v(not bois_0.proprietes.is_empty(), "chemin reel : le bois ne doit JAMAIS se souder, meme chauffe et au contact d'un fer")
	verif.v(not bois_0.proprietes.get(nom_marqueur, false), "chemin reel : le bois ne doit jamais porter le marqueur de soudure")

# Verrou DIRECT du bug "la charge du deuxieme fer s'arrete", au niveau du
# CHEMIN REEL (pas seulement causes_de_soudure en isolation) : un curseur
# tenu PILE SUR fer_0 -- le cas le plus asymetrique qu'un joueur produise
# presque toujours, jamais le milieu exact -- ne doit JAMAIS faire prendre
# de l'avance a une charge sur l'autre. Avant le correctif, fer_1 (encore
# froid) accumulait deja de la charge des que fer_0 devenait chaud, pendant
# que la charge de fer_0 (deja chaud) restait gelee a zero tant que fer_1
# n'avait pas lui-meme franchi le seuil -- desynchronisation visible a
# l'ecran, lue par Yael comme "la charge du deuxieme fer s'arrete".
func _chemin_reel_curseur_asymetrique_ne_desynchronise_pas_les_deux_charges() -> void:
	var cat := _catalogues_reels()
	var fer_0 := _fabriquer_objet("fer_0", "fer", 1.0, Vector3(0.0, 0.0, 0.0), cat)
	var fer_1 := _fabriquer_objet("fer_1", "fer", 1.5, Vector3(45.0, 0.0, 0.0), cat)
	var monde := [fer_0, fer_1]

	var sources := [{"position": Vector3(0.0, 0.0, 0.0), "rayon": 100.0, "temperature": 900.0, "force": 1.0}]
	var t := 0.0
	var delta := 0.1
	var ticks_verifies := 0
	while t < 20.0:
		if fer_0.proprietes.is_empty() or fer_1.proprietes.is_empty():
			break
		_avancer_tick(monde, sources, delta, cat)
		if fer_0.proprietes.is_empty() or fer_1.proprietes.is_empty():
			break # soudure survenue ce tick -- rien de plus a comparer
		var charge_0: float = fer_0.proprietes.etats.soudure.charge
		var charge_1: float = fer_1.proprietes.etats.soudure.charge
		verif.v(is_equal_approx(charge_0, charge_1), "chemin reel : meme sous chauffe asymetrique (curseur pile sur fer_0), les deux charges doivent rester EXACTEMENT synchronisees a chaque tick (t=%.1f, fer_0=%.3f, fer_1=%.3f) -- aucun des deux ne doit prendre l'avance sur l'autre" % [t, charge_0, charge_1])
		ticks_verifies += 1
		t += delta

	verif.v(ticks_verifies > 10, "chemin reel : le test doit avoir reellement observe plusieurs ticks de charge en cours avant fusion ou expiration (recu %d), sinon la verification ci-dessus ne prouve rien" % ticks_verifies)

func _chemin_reel_relacher_apres_soudure_ne_defait_rien_et_ne_ralarme_pas() -> void:
	var cat := _catalogues_reels()
	var fer_0 := _fabriquer_objet("fer_0", "fer", 1.0, Vector3(0.0, 0.0, 0.0), cat)
	var fer_1 := _fabriquer_objet("fer_1", "fer", 1.5, Vector3(45.0, 0.0, 0.0), cat)
	var monde := [fer_0, fer_1]

	var sources := [{"position": Vector3(0.0, 0.0, 0.0), "rayon": 250.0, "temperature": 900.0, "force": 1.0}]
	var t := 0.0
	var delta := 0.5
	while t < 60.0 and not (fer_0.proprietes.is_empty() or fer_1.proprietes.is_empty()):
		_avancer_tick(monde, sources, delta, cat)
		t += delta

	verif.v(fer_0.proprietes.is_empty() or fer_1.proprietes.is_empty(), "chemin reel (relachement) : la soudure prealable doit avoir eu lieu avant de tester le refroidissement")
	var survivant: Dictionary = fer_0 if not fer_0.proprietes.is_empty() else fer_1
	var masse_composite: float = survivant.proprietes.masse

	# Relachement : clic non maintenu (sources vides) sur une longue duree --
	# l'objet redescend vers l'ambiante par la meme loi de Newton ;
	# "chaud"/le marqueur doivent redescendre (reversibles), le composite
	# lui NE DOIT JAMAIS se defaire, et Temperature.avancer NE DOIT JAMAIS
	# alarmer (verrou direct du bug trouve a l'ecran : le composite gardait
	# des proprietes non vides mais SANS 'temperature', donc jamais filtre
	# par le tri "vivant", et alarmait a chaque tick).
	var t_relache := 0.0
	while t_relache < 200.0:
		verif.v(survivant.proprietes.has("temperature"), "chemin reel : 'temperature' doit rester presente sur le composite a CHAQUE tick de relachement, jamais seulement au moment de la soudure")
		_avancer_tick(monde, [], delta, cat)
		t_relache += delta

	verif.v(not survivant.proprietes.is_empty(), "chemin reel : le composite ne doit jamais disparaitre en refroidissant")
	verif.v(is_equal_approx(float(survivant.proprietes.masse), masse_composite), "chemin reel : la masse du composite ne doit jamais changer en refroidissant, attendu %f, recu %f" % [masse_composite, survivant.proprietes.masse])
	verif.v(not survivant.proprietes.get("etats_actifs", []).has("chaud"), "chemin reel : 'chaud' doit redescendre normalement (reversible) meme sur un composite deja soude")
	verif.v(survivant.proprietes.composition.size() == 2, "chemin reel : le composite doit toujours porter DEUX elements de composition apres refroidissement -- jamais redecoupe en deux objets")
	verif.v(BancSoudure.statut_pour_objet(survivant.proprietes, cat.soudure.defaut.nom_marqueur) == "soude", "chemin reel : le statut affiche doit rester 'soude' apres refroidissement, jamais 'intact' ni 'fantome'")
