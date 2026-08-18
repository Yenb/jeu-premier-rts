extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_affordances_portage.gd
#
# Verrouille le cablage de banc_affordances_portage.gd : le gate de FORCE
# (somme.gd:propriete comparee a une exigence de la cible), le gate de NOMBRE
# (len de la MEME liste, compare a points_de_prise) et le gate de
# STABILISATION (la meme somme, sur une autre propriete, sans jamais demander
# si le contributeur est vivant). Les mecanismes du coeur restent INCHANGES --
# ce fichier ne verrouille que du cablage. somme.gd, portee.gd, extinction.gd,
# objet.gd et monde.gd ne sont ni modifies ni reimplementes ici.
#
# LES DEUX GATES DE PORTAGE SONT SEPARES, ET C'EST LE CAS CENTRAL : l'echelle
# le prouve mieux que le tronc. Le colosse a DEUX FOIS la force demandee par
# l'echelle et reste refuse, parce qu'un seul porteur ne tient pas deux bouts.
# Un gate composite unique (une force divisee par un nombre, par exemple)
# n'aurait pas pu produire ce refus -- d'ou deux comparaisons, jamais une.
#
# TROIS FAMILLES DE CAS, a ne pas confondre :
# - les cas de MECANIQUE isolent evaluer_gates sur des positions choisies, sur
#   la scene REELLE du disque ;
# - les cas de CHEMIN REEL rejouent avancer() avec les vrais catalogues, et
#   verifient que travail_restant descend EXACTEMENT du rythme des porteurs
#   quand les trois gates passent, et pas d'un chiffre quand un seul manque --
#   sans eux, tout ce fichier resterait VERT alors que la scene lancee a
#   l'ecran ne montrerait rien (c'est le trou qui avait laisse passer la
#   calibration morte de banc_maladie, voir docs/ETAT.md) ;
# - un cas HORS DOMAINE integral (des pousseurs de monolithe sur une planete
#   inventee) : catalogue de materiaux, table de types, catalogue de chantiers
#   et TOUS les noms de propriete sont fabriques dans ce fichier, aucun
#   n'existe ailleurs dans le depot. C'est lui qui prouve que le cablage ne
#   connait ni tronc, ni echelle, ni etau.

const Banc = preload("res://scripts/banc_affordances_portage.gd")
const Somme = preload("res://scripts/somme.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

const DELTA := 0.1
# Tolerance : les forces traversent une somme de flottants, l'egalite BINAIRE
# n'est pas garantie sur 0.9 + 0.9 ; 1e-9 l'est largement sur ces ordres de
# grandeur.
const EPS := 1e-9

# Loin de tout : aucune cible du banc n'est a moins de 90 (la plus grande
# portee du fichier de donnees) de ce point.
const AILLEURS := Vector3(100.0, 1200.0, 0.0)

var _config: Dictionary
var _types: Dictionary
var _materiaux: Dictionary

func _init() -> void:
	_config = JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_affordances_portage.json"))
	_types = JSON.parse_string(FileAccess.get_file_as_string("res://data/types.json"))
	_materiaux = JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))

	_le_colosse_porte_le_tronc_seul()
	_deux_faibles_portent_le_tronc_ensemble()
	_un_faible_seul_ne_porte_pas_le_tronc()
	_l_echelle_requiert_deux_porteurs_meme_si_un_est_fort()
	_l_etau_fournit_de_la_stabilisation()
	_un_colon_fournit_aussi_de_la_stabilisation()
	_sans_stabilisation_le_travail_est_refuse()
	_somme_gd_est_l_additionneur_reel()
	_le_travail_avance_exactement_du_rythme_des_porteurs()
	_le_travail_n_avance_pas_d_un_chiffre_sous_le_seuil()
	_l_etau_ne_travaille_jamais()
	_hors_domaine_des_pousseurs_de_monolithe()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: banc_affordances_portage.gd -- gate de FORCE (somme.gd:propriete, " +
		"premier appelant reel de cette fonction), gate de NOMBRE separe sur la " +
		"MEME liste de porteurs (l'echelle refuse un colosse deux fois trop fort " +
		"mais seul), et gate de STABILISATION ou un etau et un colon sont " +
		"interchangeables sur la meme propriete -- sans qu'aucun mecanisme du " +
		"coeur ne soit touche")
	quit(0)

# ---- Fixtures ---------------------------------------------------------------

# Monte la scene REELLE du disque, puis pousse TOUS les colons hors de portee
# de tout : chaque cas rapproche ensuite exactement ceux qu'il veut. Sans ce
# nettoyage, un cas dependrait des positions de depart du fichier de donnees et
# se casserait au premier ajustement de calibration.
func _scene_reelle() -> Dictionary:
	return _scene_depuis(_config, _types, _materiaux)

func _scene_depuis(config: Dictionary, types: Dictionary, materiaux: Dictionary) -> Dictionary:
	var colons := Banc.construire_colons(config, types)
	var cibles := Banc.construire_objets_locaux(config.get("cibles", []), materiaux, config)
	var objets := Banc.construire_objets_locaux(config.get("objets", []), materiaux, config)
	for colon in colons:
		colon.position = AILLEURS
	return {
		"colons": colons, "cibles": cibles, "objets": objets,
		"choses": colons + cibles + objets,
	}

func _par_id(objets: Array, id: String) -> Dictionary:
	for objet in objets:
		if String(objet.id) == id:
			return objet
	return {}

# Colle une chose sur une cible (meme position) : a portee de tout, quelle que
# soit la portee declaree.
func _coller(chose: Dictionary, cible: Dictionary) -> void:
	chose.position = cible.position

func _gates(scene: Dictionary, id_cible: String, config: Dictionary) -> Dictionary:
	var cible := _par_id(scene.cibles, id_cible)
	var ref := String(cible.proprietes.get(String(config.propriete_chantier_ref), ""))
	var portee: float = float(config.chantiers.get(ref, {}).get("portee_travail", 0.0))
	return Banc.evaluer_gates(cible, scene.choses, config, portee)

func _restant(chose: Dictionary) -> float:
	return float(chose.proprietes.get("travail_restant", 0.0))

# ---- Cas : le gate de FORCE -------------------------------------------------

# « Un colosse seul suffit » -- une somme sur une liste d'UN element, aucun
# minimum d'agents impose (le tronc demande points_de_prise 1).
func _le_colosse_porte_le_tronc_seul() -> void:
	var scene := _scene_reelle()
	var tronc := _par_id(scene.cibles, "tronc")
	_coller(_par_id(scene.colons, "colosse"), tronc)

	var g := _gates(scene, "tronc", _config)
	verif.v(int(g.nombre) == 1, "un seul porteur a portee du tronc (%d)" % int(g.nombre))
	verif.v(bool(g.force_ok), "le colosse seul doit passer le seuil de force (%.2f pour %.2f)" % [float(g.force_totale), float(g.force_requise)])
	verif.v(bool(g.prise_ok), "un point de prise suffit pour le tronc")
	verif.v(bool(g.satisfait), "le colosse seul porte le tronc")

# « Deux faibles ensemble aussi » -- 0.9 + 0.9 = 1.8, la MEME somme que le
# colosse seul. C'est litteralement la semantique de la ligne 7 de l'audit :
# rien dans le calcul ne distingue un agent a 1.8 de deux agents a 0.9.
func _deux_faibles_portent_le_tronc_ensemble() -> void:
	var scene := _scene_reelle()
	var tronc := _par_id(scene.cibles, "tronc")
	_coller(_par_id(scene.colons, "faible_a"), tronc)
	_coller(_par_id(scene.colons, "faible_b"), tronc)

	var g := _gates(scene, "tronc", _config)
	verif.v(int(g.nombre) == 2, "deux porteurs a portee du tronc (%d)" % int(g.nombre))
	verif.v(bool(g.satisfait), "deux faibles ensemble portent le tronc (%.2f pour %.2f)" % [float(g.force_totale), float(g.force_requise)])

	# Et leur total est EXACTEMENT celui du colosse seul : la force est un
	# nombre, pas une identite.
	var solo := _scene_reelle()
	_coller(_par_id(solo.colons, "colosse"), _par_id(solo.cibles, "tronc"))
	var g_solo := _gates(solo, "tronc", _config)
	verif.v(absf(float(g.force_totale) - float(g_solo.force_totale)) < EPS,
		"deux faibles pesent EXACTEMENT ce que pese le colosse (%.6f vs %.6f)" % [float(g.force_totale), float(g_solo.force_totale)])

# Le refus, et il ne vient QUE de la force : le nombre de porteurs, lui, est
# suffisant.
func _un_faible_seul_ne_porte_pas_le_tronc() -> void:
	var scene := _scene_reelle()
	_coller(_par_id(scene.colons, "faible_a"), _par_id(scene.cibles, "tronc"))

	var g := _gates(scene, "tronc", _config)
	verif.v(not bool(g.force_ok), "un faible seul est sous le seuil de force (%.2f pour %.2f)" % [float(g.force_totale), float(g.force_requise)])
	verif.v(bool(g.prise_ok), "et ce n'est PAS le nombre de porteurs qui le bloque")
	verif.v(not bool(g.satisfait), "un faible seul ne porte pas le tronc")

# ---- Cas : le gate de NOMBRE, separe du precedent ---------------------------

# LE CAS CENTRAL. Le colosse a 1.8 pour 0.9 demandes -- deux fois trop fort --
# et reste refuse : une echelle a deux bouts. Le refus vient du SEUL gate de
# nombre, verifie explicitement, sans quoi ce cas ne prouverait pas que les
# deux gates sont separes.
func _l_echelle_requiert_deux_porteurs_meme_si_un_est_fort() -> void:
	var scene := _scene_reelle()
	var echelle := _par_id(scene.cibles, "echelle")
	_coller(_par_id(scene.colons, "colosse"), echelle)

	var g := _gates(scene, "echelle", _config)
	verif.v(bool(g.force_ok), "le colosse est largement assez fort pour l'echelle (%.2f pour %.2f)" % [float(g.force_totale), float(g.force_requise)])
	verif.v(float(g.force_totale) > float(g.force_requise), "et strictement au-dessus, pas de justesse")
	verif.v(not bool(g.prise_ok), "mais un seul porteur pour %d points de prise" % int(g.points_de_prise))
	verif.v(not bool(g.satisfait), "l'echelle reste refusee a un colosse seul")

	# N'IMPORTE QUEL second porteur debloque, meme le plus faible : c'est un
	# gate de NOMBRE, il ne regarde aucune force.
	_coller(_par_id(scene.colons, "faible_a"), echelle)
	var g2 := _gates(scene, "echelle", _config)
	verif.v(int(g2.nombre) == 2, "deux porteurs a portee de l'echelle (%d)" % int(g2.nombre))
	verif.v(bool(g2.satisfait), "un second porteur, meme faible, debloque l'echelle")

	# ET DANS L'AUTRE SENS : deux faibles, dont aucun n'atteindrait le seuil du
	# tronc, portent l'echelle sans peine -- les deux gates ne se recouvrent pas.
	var faibles := _scene_reelle()
	var echelle2 := _par_id(faibles.cibles, "echelle")
	_coller(_par_id(faibles.colons, "faible_a"), echelle2)
	_coller(_par_id(faibles.colons, "faible_b"), echelle2)
	verif.v(bool(_gates(faibles, "echelle", _config).satisfait), "deux faibles portent l'echelle")

# ---- Cas : le gate de STABILISATION ----------------------------------------

# L'etau est un OBJET : il ne porte ni force ni rythme. Il n'entre donc dans
# aucune des deux listes de portage, et il contribue quand meme -- c'est toute
# la ligne 9 de l'audit.
func _l_etau_fournit_de_la_stabilisation() -> void:
	var scene := _scene_reelle()
	var enclume := _par_id(scene.cibles, "enclume")
	var etau := _par_id(scene.objets, "etau")
	_coller(_par_id(scene.colons, "faible_a"), enclume)

	verif.v(not etau.proprietes.has(String(_config.propriete_force)),
		"l'etau ne porte AUCUNE force : ce n'est pas un porteur")
	verif.v(not etau.proprietes.has("rythme"),
		"ni aucun rythme : ce n'est pas un agent de chantier")

	var g := _gates(scene, "enclume", _config)
	verif.v(int(g.nombre) == 1, "un seul porteur sur l'enclume -- l'etau n'en est pas un (%d)" % int(g.nombre))
	verif.v(bool(g.satisfait), "avec l'etau a portee, l'enclume est tenue (%.2f pour %.2f)" % [float(g.stabilisation_totale), float(g.stabilisation_requise)])

	# Et sa contribution est bien la sienne : l'eloigner suffit a tout casser,
	# sans qu'aucun colon n'ait bouge.
	etau.position = AILLEURS
	verif.v(not bool(_gates(scene, "enclume", _config).stabilisation_ok),
		"l'etau eloigne, la stabilisation retombe sous l'exigence")

# La contrepartie exacte : un colon remplace l'etau, sur la MEME propriete.
# Aucune ligne du gate ne demande si un contributeur est vivant.
func _un_colon_fournit_aussi_de_la_stabilisation() -> void:
	var scene := _scene_reelle()
	var enclume := _par_id(scene.cibles, "enclume")
	_par_id(scene.objets, "etau").position = AILLEURS
	_coller(_par_id(scene.colons, "faible_a"), enclume)
	_coller(_par_id(scene.colons, "faible_b"), enclume)

	var g := _gates(scene, "enclume", _config)
	verif.v(bool(g.stabilisation_ok),
		"deux colons, sans etau, tiennent l'enclume (%.2f pour %.2f)" % [float(g.stabilisation_totale), float(g.stabilisation_requise)])
	verif.v(bool(g.satisfait), "et le chantier est pret")
	verif.v(g.stabilisateurs.size() == 2, "les deux contributeurs sont les deux colons (%d)" % g.stabilisateurs.size())

# Sans stabilisation suffisante, le travail ne commence pas -- et c'est bien
# CE gate-la qui refuse, les deux autres passant.
func _sans_stabilisation_le_travail_est_refuse() -> void:
	var scene := _scene_reelle()
	_par_id(scene.objets, "etau").position = AILLEURS
	_coller(_par_id(scene.colons, "faible_a"), _par_id(scene.cibles, "enclume"))

	var g := _gates(scene, "enclume", _config)
	verif.v(bool(g.force_ok), "l'enclume ne demande aucune force particuliere")
	verif.v(bool(g.prise_ok), "et un porteur suffit en nombre")
	verif.v(not bool(g.stabilisation_ok),
		"mais un porteur seul ne tient pas assez (%.2f pour %.2f)" % [float(g.stabilisation_totale), float(g.stabilisation_requise)])
	verif.v(not bool(g.satisfait), "le travail est refuse")

# ---- Cas : somme.gd est bien l'additionneur --------------------------------

# PREMIER APPELANT REEL de somme.gd:propriete dans le depot (ses deux autres
# appelants n'utilisent que somme.gd:reserves, la lecture PROFONDE). Ce cas
# verifie que le total du gate EST celui que rend somme.gd sur la meme liste,
# et que les trois contrats de son en-tete traversent bien le cablage --
# aucun ne serait vrai d'une boucle `float(valeur)` recodee a la main.
func _somme_gd_est_l_additionneur_reel() -> void:
	var scene := _scene_reelle()
	var tronc := _par_id(scene.cibles, "tronc")
	_coller(_par_id(scene.colons, "colosse"), tronc)
	_coller(_par_id(scene.colons, "faible_a"), tronc)
	var nom_force := String(_config.propriete_force)

	var g := _gates(scene, "tronc", _config)
	verif.v(absf(float(g.force_totale) - Somme.propriete(g.porteurs, nom_force)) < EPS,
		"le total du gate EST somme.gd:propriete sur la liste des porteurs")

	# Contrat 1 -- Array vide : 0.0, jamais une absence de reponse.
	var vide := _scene_reelle()
	verif.v(_gates(vide, "tronc", _config).force_totale == 0.0,
		"personne a portee : total 0.0, jamais autre chose")

	# Contrat 2 -- une entite qui ne porte pas la grandeur contribue 0.0 sans
	# alarme et sans casser le total. L'etau colle au tronc : il n'a pas de
	# force, il est ecarte de la liste et ne fausse rien.
	var mixte := _scene_reelle()
	var tronc2 := _par_id(mixte.cibles, "tronc")
	_coller(_par_id(mixte.colons, "colosse"), tronc2)
	_coller(_par_id(mixte.objets, "etau"), tronc2)
	var g2 := _gates(mixte, "tronc", _config)
	verif.v(int(g2.nombre) == 1, "l'etau n'entre pas dans les porteurs (%d)" % int(g2.nombre))
	verif.v(absf(float(g2.force_totale) - 1.8) < EPS,
		"et ne change pas le total d'un chiffre (%.6f)" % float(g2.force_totale))

	# Contrat 3 -- somme.gd est un LECTEUR : il ne mute aucune entite, et
	# n'invente aucune cle sur celle qui ne porte pas la grandeur interrogee.
	var etau := _par_id(mixte.objets, "etau")
	Somme.propriete([etau], nom_force)
	verif.v(not etau.proprietes.has(nom_force),
		"interroger somme.gd sur une grandeur absente ne cree jamais la cle")

# ---- Cas : chemin REEL, avancer() ------------------------------------------

# extinction.gd mange le chantier, et il le mange au rythme des SEULS porteurs
# retenus par le gate -- verifie au chiffre exact contre data/types.json:colon.
func _le_travail_avance_exactement_du_rythme_des_porteurs() -> void:
	var scene := _scene_reelle()
	var tronc := _par_id(scene.cibles, "tronc")
	_coller(_par_id(scene.colons, "colosse"), tronc)

	var avant := _restant(tronc)
	verif.v(avant > 0.0, "le tronc porte un chantier au depart")
	Banc.avancer(scene.cibles, scene.choses, DELTA, _config, _config.chantiers)
	var rythme: float = float(_par_id(scene.colons, "colosse").proprietes.rythme)
	verif.v(absf((avant - _restant(tronc)) - rythme * DELTA) < 1e-6,
		"le chantier descend EXACTEMENT du rythme du porteur (%.6f attendu %.6f)" % [avant - _restant(tronc), rythme * DELTA])

	# Et il finit par s'accomplir : extinction.gd retire lui-meme
	# travail_restant, ce cablage n'y touche jamais.
	var accomplis: Array = []
	for i in range(400):
		for id in Banc.avancer(scene.cibles, scene.choses, DELTA, _config, _config.chantiers).accomplis:
			accomplis.append(String(id))
	verif.v(accomplis.has("tronc"), "le tronc finit par etre porte")
	verif.v(not tronc.proprietes.has("travail_restant"),
		"et extinction.gd a retire travail_restant de lui-meme")

# Le refus n'est pas un ralentissement : sous le seuil, le chantier ne bouge
# pas d'un chiffre, meme au bout de mille ticks.
func _le_travail_n_avance_pas_d_un_chiffre_sous_le_seuil() -> void:
	var scene := _scene_reelle()
	var tronc := _par_id(scene.cibles, "tronc")
	_coller(_par_id(scene.colons, "faible_a"), tronc)

	var avant := _restant(tronc)
	for i in range(1000):
		Banc.avancer(scene.cibles, scene.choses, DELTA, _config, _config.chantiers)
	verif.v(_restant(tronc) == avant,
		"sous le seuil de force, le travail ne COMMENCE pas -- il ne ralentit pas (%.6f vs %.6f)" % [_restant(tronc), avant])

	# Meme mesure sur l'echelle, ou c'est le NOMBRE qui refuse : un colosse
	# largement assez fort n'entame rien.
	var ech := _scene_reelle()
	var echelle := _par_id(ech.cibles, "echelle")
	_coller(_par_id(ech.colons, "colosse"), echelle)
	var avant_ech := _restant(echelle)
	for i in range(1000):
		Banc.avancer(ech.cibles, ech.choses, DELTA, _config, _config.chantiers)
	verif.v(_restant(echelle) == avant_ech,
		"un colosse seul n'entame pas l'echelle d'un chiffre (%.6f vs %.6f)" % [_restant(echelle), avant_ech])

# L'etau stabilise et NE TRAVAILLE PAS : sans un colon pour tenir le marteau,
# le chantier de l'enclume ne bouge pas -- banc_commun.gd:agents_rythme ne
# ramasse que ce qui porte « rythme ».
func _l_etau_ne_travaille_jamais() -> void:
	var scene := _scene_reelle()
	var enclume := _par_id(scene.cibles, "enclume")
	var avant := _restant(enclume)
	for i in range(200):
		Banc.avancer(scene.cibles, scene.choses, DELTA, _config, _config.chantiers)
	verif.v(_restant(enclume) == avant,
		"l'etau seul a portee ne fait avancer aucun chantier (%.6f vs %.6f)" % [_restant(enclume), avant])

# ---- HORS DOMAINE -----------------------------------------------------------

# Des pousseurs de monolithe sur une planete inventee : catalogue de materiaux,
# table de types, catalogue de chantiers ET tous les noms de propriete sont
# fabriques ici, aucun n'existe ailleurs dans le depot. Pas un tronc, pas une
# echelle, pas un etau -- et le meme code traverse les trois gates : la poussee
# qui se somme, les points d'appui qui se comptent, et le calage fourni
# indifferemment par un vivant ou par une cale de pierre.
func _hors_domaine_des_pousseurs_de_monolithe() -> void:
	var materiaux := {
		"granit_zorg": {"densite": 2.7},
		"basalte_zorg": {"densite": 3.0},
	}
	var types := {
		"zorgien": {"rythme": 2.0, "poussee_zorg": 1.0, "calage_zorg": 0.4},
	}
	var config := {
		"type_colon": "zorgien",
		"propriete_force": "poussee_zorg",
		"propriete_stabilisation": "calage_zorg",
		"propriete_force_requise": "poussee_exigee",
		"propriete_points_de_prise": "appuis_exiges",
		"propriete_stabilisation_requise": "calage_exige",
		"propriete_chantier_ref": "manoeuvre_ref",
		"portee_stabilisation": 50.0,
		"chantiers": {
			"pousser_monolithe": {"portee_travail": 50.0, "a_zero": {"poser": {"monolithe_dresse": true}}},
			"caler_stele": {"portee_travail": 50.0, "a_zero": {"poser": {"stele_calee": true}}},
		},
		"colons": [
			{"id": "hercule_zorg", "position": [0.0, 0.0, 0.0], "poussee_zorg": 3.0},
			{"id": "menu_zorg", "position": [0.0, 0.0, 0.0], "poussee_zorg": 1.1},
		],
		"cibles": [
			{
				"id": "monolithe", "position": [1000.0, 0.0, 0.0],
				"composition": [{"materiau": "granit_zorg", "volume": 8.0}],
				"poussee_exigee": 2.0, "appuis_exiges": 2, "calage_exige": 0.0,
				"manoeuvre_ref": "pousser_monolithe", "travail_restant": 5.0,
			},
			{
				"id": "stele", "position": [2000.0, 0.0, 0.0],
				"composition": [{"materiau": "basalte_zorg", "volume": 1.0}],
				"poussee_exigee": 0.0, "appuis_exiges": 1, "calage_exige": 0.8,
				"manoeuvre_ref": "caler_stele", "travail_restant": 5.0,
			},
		],
		"objets": [
			{
				"id": "cale_pierre", "position": [2000.0, 0.0, 0.0],
				"composition": [{"materiau": "granit_zorg", "volume": 0.3}],
				"calage_zorg": 1.0,
			},
		],
	}

	var scene := _scene_depuis(config, types, materiaux)
	verif.v(scene.colons.size() == 2 and scene.cibles.size() == 2 and scene.objets.size() == 1,
		"la scene inventee se fabrique entierement sur des catalogues inventes")

	# Le gate de NOMBRE, sur un domaine ou rien ne s'appelle « echelle » : le
	# costaud a une fois et demie la poussee exigee et reste refuse, seul.
	var monolithe := _par_id(scene.cibles, "monolithe")
	_coller(_par_id(scene.colons, "hercule_zorg"), monolithe)
	var g := _gates(scene, "monolithe", config)
	verif.v(bool(g.force_ok) and not bool(g.prise_ok) and not bool(g.satisfait),
		"assez fort, pas assez nombreux -- meme code, autre planete")
	_coller(_par_id(scene.colons, "menu_zorg"), monolithe)
	verif.v(bool(_gates(scene, "monolithe", config).satisfait), "a deux, le monolithe se leve")

	# Le gate de STABILISATION : la cale de pierre remplace un vivant, et
	# l'inverse -- exactement comme l'etau et le colon du domaine reel.
	var stele := _par_id(scene.cibles, "stele")
	var cale := _par_id(scene.objets, "cale_pierre")
	_coller(_par_id(scene.colons, "menu_zorg"), stele)
	verif.v(bool(_gates(scene, "stele", config).satisfait), "un pousseur plus la cale suffisent (1.4 pour 0.8)")
	cale.position = AILLEURS
	verif.v(not bool(_gates(scene, "stele", config).stabilisation_ok), "la cale retiree, le calage manque (0.4 pour 0.8)")
	_coller(_par_id(scene.colons, "hercule_zorg"), stele)
	verif.v(bool(_gates(scene, "stele", config).satisfait), "deux vivants remplacent la cale (0.8 pour 0.8)")

	# Et le chantier avance reellement, au rythme invente de ce type.
	var avant := _restant(stele)
	Banc.avancer(scene.cibles, scene.choses, DELTA, config, config.chantiers)
	verif.v(absf((avant - _restant(stele)) - 2.0 * 2.0 * DELTA) < 1e-6,
		"deux zorgiens a rythme 2.0 mangent 0.4 par tick (%.6f)" % (avant - _restant(stele)))
