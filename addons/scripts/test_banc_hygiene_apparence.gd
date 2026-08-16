extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_hygiene_apparence.gd
#
# Verrouille le chantier « hygiene + apparence -- perception sociale »
# (audit_mecaniques_corps_prealable.md, lignes 9 et 13), scripts/
# banc_hygiene_apparence.gd. AUCUN MECANISME DU COEUR N'A ETE TOUCHE NI CREE
# par ce chantier -- perception.gd/agir.gd/fuite.gd/depense.gd/seuil_etat.gd/
# proximite.gd/dominance.gd/banc_commun.gd restent verrouilles par leurs
# propres tests, inchanges. Ce fichier verrouille DEUX choses :
#
# 1. LES DEUX CANAUX NEUFS de data/canaux.json ("odeur_corporelle" /
#    "apparence"), sur des fixtures construites a la main mais avec le
#    catalogue REEL lu sur le disque -- meme patron que
#    test_banc_magie_perception.gd : le seuil individuel filtre, l'occlusion
#    par "opacite" bloque l'apparence, et NE bloque PAS l'odeur (son
#    propriete_obstacle est vide).
# 2. LA CHAINE REELLE du banc, rejouee sur data/banc_hygiene_apparence.json
#    + data/types.json + data/seuils_etat.json + data/types_choses.json +
#    data/orientations.json + data/profils_saillance.json lus sur le disque :
#    l'hygiene descend, "sale" est pose au franchissement exact, le colon
#    sale emet, les autres le fuient, le lavage retire l'etat et eteint
#    l'odeur, le colon blesse est percu sans jamais etre fui.
#
# LES POSITIONS SONT IMPOSEES PAR LE TEST (jamais celles de la donnee, qui ne
# servent qu'a placer la scene observable) : la fuite et la perception se
# mesurent a des distances CHOISIES, sinon rien n'est reproductible. Le
# deplacement (errance seedee) n'est jamais joue ici -- il est verrouille
# separement, sur sa fonction pure.

const Banc = preload("res://scripts/banc_hygiene_apparence.gd")
const Monde = preload("res://scripts/monde.gd")
const Perception = preload("res://scripts/perception.gd")
const Depense = preload("res://scripts/depense.gd")
const SeuilEtat = preload("res://scripts/seuil_etat.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

func _init() -> void:
	_mecanisme_apparence_percue_au_dessus_du_seuil_ignoree_en_dessous()
	_mecanisme_mur_opaque_bloque_le_canal_apparence()
	_mecanisme_mur_opaque_ne_bloque_jamais_l_odeur()
	_donnee_canaux_declarent_bien_leurs_emissions_et_obstacles()
	_donnee_sale_resout_un_verbe_oriente_fuite()

	_hygiene_descend_avec_le_temps()
	_sale_pose_exactement_au_franchissement_du_seuil()
	_colon_sale_emet_sur_le_canal_odeur_corporelle()
	_les_autres_colons_fuient_le_colon_sale()
	_le_colon_sale_ne_fuit_personne_et_le_blesse_n_est_jamais_fui()
	_lavage_retire_sale_et_eteint_l_odeur()
	_colon_blesse_percu_par_le_canal_apparence()
	_attentif_percoit_de_loin_distrait_seulement_de_pres()

	_errance_est_seedee_et_garde_sa_direction_le_temps_voulu()
	_borner_garde_le_colon_dans_le_cadre_et_a_plat()
	_compteurs_et_couleur_lisent_la_donnee()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: banc_hygiene_apparence.gd -- les deux canaux neufs (odeur_corporelle sans occlusion, " +
		"apparence occluse par opacite) filtrent par seuil individuel ; chemin reel : l'hygiene descend, " +
		"'sale' est pose exactement au franchissement de manque_hygiene > 60, le colon sale emet sur " +
		"odeur_corporelle et est fui par les trois autres, le lavage retire 'sale' et eteint l'odeur, " +
		"le colon blesse est percu par apparence (de loin par l'attentif, seulement de pres par le " +
		"distrait) sans jamais etre fui")
	quit(0)

# ---------- Fixtures ----------

static func _chose(id: String, position: Vector3, proprietes: Dictionary) -> Dictionary:
	return { "id": id, "position": position, "proprietes": proprietes }

static func _charger(chemin: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))

# Monte la scene REELLE (donnee du disque), sans obstacle : quatre colons
# fabriques par le cablage lui-meme, un Monde qui les porte. Les positions
# sont ecrasees par chaque cas de test.
func _monter() -> Dictionary:
	var config: Dictionary = _charger("res://data/banc_hygiene_apparence.json")
	var types_partages: Dictionary = _charger("res://data/types.json")
	var catalogue_types: Dictionary = config.get("types", {}).duplicate(true)
	for nom_paquet in ["objet_physique", "dynamique", "percevant", "agent", "colon"]:
		catalogue_types[nom_paquet] = types_partages.get(nom_paquet, {})
	var colons: Array = Banc.fabriquer_colons(config.get("colons", {}), catalogue_types, config)
	var monde := Monde.new()
	var par_id: Dictionary = {}
	for colon in colons:
		monde.ajouter(colon, "colon", colon.position)
		par_id[colon.id] = colon
	return {
		"config": config,
		"colons": colons,
		"monde": monde,
		"par_id": par_id,
		"canaux": _charger("res://data/canaux.json"),
		"seuils": _charger("res://data/seuils_etat.json"),
		"actions": _charger("res://data/types_choses.json"),
		"orientations": _charger("res://data/orientations.json"),
		"profils": _charger("res://data/profils_saillance.json"),
	}

# Les QUATRE premiers maillons du _process du banc, dans le meme ordre et
# par les MEMES appels -- jamais une logique recopiee. Le cinquieme
# (perception/fuite/deplacement) est joue a part par chaque cas.
func _tick(scene: Dictionary, delta: float) -> void:
	var config: Dictionary = scene.config
	Depense.avancer(scene.colons, delta)
	Banc.ecrire_manque(scene.colons, config.nom_reserve_hygiene, config.propriete_manque)
	SeuilEtat.avancer(scene.colons, scene.seuils)
	Banc.appliquer_marqueurs(
		scene.colons, config.emission_odeur, config.emission_apparence,
		config.propriete_odeur, config.propriete_apparence,
	)

func _placer(scene: Dictionary, id: String, position: Vector3) -> void:
	scene.par_id[id].position = position

# ---------- Mecanisme : les deux canaux neufs, catalogue REEL ----------

func _percepteur(canal: String, seuil: float, portee: float, position: Vector3) -> Dictionary:
	return _chose("percepteur", position, {
		"canaux": [canal],
		"canaux_config": { canal: { "portee": portee, "sensibilite": 1.0, "seuil": seuil } },
	})

func _percoit(percepteur: Dictionary, monde, canaux: Dictionary, id_cherche: String) -> bool:
	for entree in Perception.percevoir(percepteur, monde, canaux):
		if entree.chose.id == id_cherche:
			return true
	return false

# Meme mecanique exacte que ouie/son_emis et magie/force_magique : l'intensite
# ATTENUEE PAR LA DISTANCE est comparee au seuil INDIVIDUEL du percepteur.
# 0.6 a 700 sur une portee 900 vaut 0.1333 -- au-dessus de 0.05, sous 0.40.
func _mecanisme_apparence_percue_au_dessus_du_seuil_ignoree_en_dessous() -> void:
	var canaux: Dictionary = _charger("res://data/canaux.json")
	var monde := Monde.new()
	var cible := _chose("cible", Vector3(700.0, 0.0, 0.0), { "visibilite_etat": 0.6 })
	monde.ajouter(cible, "colon", cible.position)
	verif.v(_percoit(_percepteur("apparence", 0.05, 900.0, Vector3.ZERO), monde, canaux, "cible"),
		"apparence : un seuil bas (0.05) doit percevoir une visibilite_etat 0.6 attenuee a 0.1333")
	verif.v(not _percoit(_percepteur("apparence", 0.40, 900.0, Vector3.ZERO), monde, canaux, "cible"),
		"apparence : un seuil haut (0.40) ne doit PAS percevoir la meme cible attenuee a 0.1333")

# propriete_obstacle "opacite", valant 1.0 sur pierre/bois/fer : blocage
# TOTAL, jamais partiel -- meme consequence assumee que le canal magie.
func _mecanisme_mur_opaque_bloque_le_canal_apparence() -> void:
	var canaux: Dictionary = _charger("res://data/canaux.json")
	var monde := Monde.new()
	var cible := _chose("cible", Vector3(400.0, 0.0, 0.0), { "visibilite_etat": 0.6 })
	monde.ajouter(cible, "colon", cible.position)
	var percepteur := _percepteur("apparence", 0.05, 900.0, Vector3.ZERO)
	verif.v(_percoit(percepteur, monde, canaux, "cible"),
		"apparence : sans mur, la cible doit etre percue (0.6 attenue a 0.3333 > 0.05)")
	var mur := _chose("mur", Vector3(200.0, 0.0, 0.0), { "opacite": 1.0 })
	monde.ajouter(mur, "mur", mur.position)
	verif.v(not _percoit(percepteur, monde, canaux, "cible"),
		"apparence : un mur opaque (opacite 1.0) sur le segment doit bloquer totalement la perception")

# Le meme mur, sur le meme segment, ne bloque JAMAIS odeur_corporelle : son
# propriete_obstacle est vide, occlusion.gd court-circuite a 1.0.
func _mecanisme_mur_opaque_ne_bloque_jamais_l_odeur() -> void:
	var canaux: Dictionary = _charger("res://data/canaux.json")
	var monde := Monde.new()
	var cible := _chose("cible", Vector3(150.0, 0.0, 0.0), { "odeur_emise": 1.0 })
	monde.ajouter(cible, "colon", cible.position)
	var mur := _chose("mur", Vector3(75.0, 0.0, 0.0), { "opacite": 1.0 })
	monde.ajouter(mur, "mur", mur.position)
	verif.v(_percoit(_percepteur("odeur_corporelle", 0.05, 300.0, Vector3.ZERO), monde, canaux, "cible"),
		"odeur_corporelle : un mur opaque ne doit JAMAIS bloquer l'odeur (propriete_obstacle vide)")

func _donnee_canaux_declarent_bien_leurs_emissions_et_obstacles() -> void:
	var canaux: Dictionary = _charger("res://data/canaux.json")
	verif.v(canaux.has("odeur_corporelle") and canaux.has("apparence"),
		"data/canaux.json doit porter les deux canaux neufs")
	var odeur: Dictionary = canaux.get("odeur_corporelle", {})
	verif.v(odeur.get("geometrie", "") == "propagation_obstacles",
		"odeur_corporelle doit avoir la geometrie propagation_obstacles (la seule qui lise propriete_emission/seuil)")
	verif.v(odeur.get("propriete_emission", "") == "odeur_emise",
		"odeur_corporelle doit emettre sur 'odeur_emise'")
	verif.v(odeur.get("propriete_obstacle", "?") == "",
		"odeur_corporelle ne doit declarer AUCUN obstacle")
	var apparence: Dictionary = canaux.get("apparence", {})
	verif.v(apparence.get("geometrie", "") == "propagation_obstacles",
		"apparence doit avoir la geometrie propagation_obstacles")
	verif.v(apparence.get("propriete_emission", "") == "visibilite_etat",
		"apparence doit emettre sur 'visibilite_etat'")
	verif.v(apparence.get("propriete_obstacle", "") == "opacite",
		"apparence doit etre occluse par 'opacite'")
	verif.v(canaux.get("odorat", {}).get("geometrie", "") == "sphere_directionnelle",
		"le canal 'odorat' existant ne doit PAS avoir change de geometrie (il porte seul le vent)")

func _donnee_sale_resout_un_verbe_oriente_fuite() -> void:
	var actions: Dictionary = _charger("res://data/types_choses.json")
	var orientations: Dictionary = _charger("res://data/orientations.json")
	var verbes: Array = actions.get("sale", {}).get("verbes", [])
	verif.v(verbes.size() == 1, "data/types_choses.json:sale doit porter exactement un verbe")
	verif.v(orientations.get(verbes[0] if not verbes.is_empty() else "", "") == "fuite",
		"le verbe de 'sale' doit etre oriente 'fuite' dans data/orientations.json")
	verif.v(not actions.has("blesse"),
		"'blesse' ne doit avoir AUCUNE entree dans types_choses.json : un blesse est remarque, jamais fui")

# ---------- Chemin reel ----------

func _hygiene_descend_avec_le_temps() -> void:
	var scene := _monter()
	var config: Dictionary = scene.config
	var sale: Dictionary = scene.par_id["colon_sale"]
	var propre: Dictionary = scene.par_id["colon_attentif"]
	var avant_sale: float = sale.proprietes.reserves[config.nom_reserve_hygiene].reserve
	var avant_propre: float = propre.proprietes.reserves[config.nom_reserve_hygiene].reserve
	for i in range(4):
		_tick(scene, 0.5)
	var apres_sale: float = sale.proprietes.reserves[config.nom_reserve_hygiene].reserve
	var apres_propre: float = propre.proprietes.reserves[config.nom_reserve_hygiene].reserve
	verif.v(apres_sale < avant_sale, "l'hygiene du colon sale doit descendre avec le temps")
	verif.v(apres_propre < avant_propre, "l'hygiene des autres colons descend aussi, seulement bien plus lentement")
	verif.v(apres_sale < apres_propre - 10.0,
		"le colon qui ne se lave jamais doit descendre nettement plus vite (cout_base 8.0 contre 0.4)")
	verif.v(is_equal_approx(sale.proprietes[config.propriete_manque],
			float(sale.proprietes.reserves[config.nom_reserve_hygiene].capacite) - apres_sale),
		"le miroir plat manque_hygiene doit valoir exactement capacite - reserve")

# Franchissement EXACT : seuil_etat.gd compare strictement `valeur > seuil`.
# cout_base 8.0, capacite 100.0, seuil 60.0 -> a 7.5 s le manque vaut
# exactement 60.0 (pas encore sale), a 8.0 s il vaut 64.0 (sale).
func _sale_pose_exactement_au_franchissement_du_seuil() -> void:
	var scene := _monter()
	var sale: Dictionary = scene.par_id["colon_sale"]
	for i in range(15):
		_tick(scene, 0.5)
	verif.v(not sale.proprietes.etats_actifs.has("sale"),
		"a t=7.5 s le manque vaut exactement 60.0 : la comparaison est STRICTE, 'sale' ne doit pas encore etre pose")
	_tick(scene, 0.5)
	verif.v(sale.proprietes.etats_actifs.has("sale"),
		"a t=8.0 s le manque vaut 64.0 > 60.0 : 'sale' doit etre pose")
	verif.v(sale.proprietes.get("sale", false) == true,
		"le cablage doit miroiter 'sale' en propriete PLATE -- sans quoi agir.gd ne resout aucun verbe")
	for id in ["colon_blesse", "colon_attentif", "colon_distrait"]:
		verif.v(not scene.par_id[id].proprietes.etats_actifs.has("sale"),
			"%s ne doit pas devenir sale en 8 s (cout_base 0.4)" % id)

func _colon_sale_emet_sur_le_canal_odeur_corporelle() -> void:
	var scene := _monter()
	var config: Dictionary = scene.config
	var sale: Dictionary = scene.par_id["colon_sale"]
	verif.v(sale.proprietes[config.propriete_odeur] == 0.0,
		"un colon propre n'emet aucune odeur au depart")
	for i in range(20):
		_tick(scene, 0.5)
	verif.v(sale.proprietes[config.propriete_odeur] > 0.0,
		"une fois 'sale' pose, le cablage doit ecrire odeur_emise sur le colon")

	# Le distrait (seuil apparence 0.40) ne peut PAS voir un sale (0.15) :
	# ce qu'il capte ne peut venir que du canal de l'odeur.
	_placer(scene, "colon_sale", Vector3.ZERO)
	_placer(scene, "colon_distrait", Vector3(200.0, 0.0, 0.0))
	_placer(scene, "colon_blesse", Vector3(9000.0, 9000.0, 0.0))
	_placer(scene, "colon_attentif", Vector3(200.0, 0.0, 0.0))
	var canaux_captants: Array = []
	for entree in Banc.perceptions_de(scene.par_id["colon_distrait"], scene.monde, scene.canaux):
		if entree.chose.id == "colon_sale":
			canaux_captants = entree.canaux
	verif.v(canaux_captants == ["odeur_corporelle"],
		"le distrait ne doit capter le colon sale QUE par odeur_corporelle (trouve : %s)" % str(canaux_captants))

	var canaux_attentif: Array = []
	for entree in Banc.perceptions_de(scene.par_id["colon_attentif"], scene.monde, scene.canaux):
		if entree.chose.id == "colon_sale":
			canaux_attentif = entree.canaux
	verif.v(canaux_attentif.has("odeur_corporelle") and canaux_attentif.has("apparence"),
		"l'attentif (seuil apparence 0.05) doit capter le colon sale par LES DEUX canaux (trouve : %s)" % str(canaux_attentif))

func _les_autres_colons_fuient_le_colon_sale() -> void:
	var scene := _monter()
	for i in range(20):
		_tick(scene, 0.5)
	_placer(scene, "colon_sale", Vector3.ZERO)
	_placer(scene, "colon_blesse", Vector3(200.0, 0.0, 0.0))
	_placer(scene, "colon_attentif", Vector3(0.0, 200.0, 0.0))
	_placer(scene, "colon_distrait", Vector3(-200.0, 0.0, 0.0))
	for id in ["colon_blesse", "colon_attentif", "colon_distrait"]:
		var colon: Dictionary = scene.par_id[id]
		var perceptions := Banc.perceptions_de(colon, scene.monde, scene.canaux)
		var visibles := Banc.visibles_de(perceptions, colon, scene.profils)
		var f := Banc.fuite_de(visibles, colon, scene.actions, scene.orientations, scene.monde)
		verif.v(f.ids == ["colon_sale"], "%s doit fuir le colon sale, et lui seul (trouve : %s)" % [id, str(f.ids)])
		var attendu: Vector3 = (colon.position - Vector3.ZERO).normalized()
		verif.v(f.direction.distance_to(attendu) < 0.001,
			"%s doit s'eloigner exactement a l'oppose du colon sale" % id)

	# Hors de portee de l'odeur (285 unites) et hors de la portee de
	# saillance (350) : plus rien a fuir, sans cas particulier.
	_placer(scene, "colon_distrait", Vector3(-600.0, 0.0, 0.0))
	var loin: Dictionary = scene.par_id["colon_distrait"]
	var f_loin := Banc.fuite_de(
		Banc.visibles_de(Banc.perceptions_de(loin, scene.monde, scene.canaux), loin, scene.profils),
		loin, scene.actions, scene.orientations, scene.monde,
	)
	verif.v(f_loin.ids.is_empty() and f_loin.direction == Vector3.ZERO,
		"a 600 unites le distrait ne sent plus rien : aucune fuite, direction nulle")

func _le_colon_sale_ne_fuit_personne_et_le_blesse_n_est_jamais_fui() -> void:
	var scene := _monter()
	for i in range(20):
		_tick(scene, 0.5)
	_placer(scene, "colon_sale", Vector3.ZERO)
	_placer(scene, "colon_blesse", Vector3(150.0, 0.0, 0.0))
	_placer(scene, "colon_attentif", Vector3(9000.0, 9000.0, 0.0))
	_placer(scene, "colon_distrait", Vector3(9000.0, 9500.0, 0.0))
	var sale: Dictionary = scene.par_id["colon_sale"]
	var perceptions := Banc.perceptions_de(sale, scene.monde, scene.canaux)
	var ids := Banc.ids_de(perceptions)
	verif.v(ids == ["colon_blesse"],
		"le colon sale doit bien PERCEVOIR le blesse (visibilite 0.60 a 150 unites) -- trouve : %s" % str(ids))
	var f := Banc.fuite_de(
		Banc.visibles_de(perceptions, sale, scene.profils), sale, scene.actions, scene.orientations, scene.monde,
	)
	verif.v(f.ids.is_empty() and f.direction == Vector3.ZERO,
		"un colon blesse est remarque mais JAMAIS fui : aucun verbe ne se resout sur 'blesse'")

func _lavage_retire_sale_et_eteint_l_odeur() -> void:
	var scene := _monter()
	var config: Dictionary = scene.config
	var sale: Dictionary = scene.par_id["colon_sale"]
	for i in range(20):
		_tick(scene, 0.5)
	verif.v(sale.proprietes.etats_actifs.has("sale") and sale.proprietes[config.propriete_odeur] > 0.0,
		"pre-condition : le colon doit etre sale et emettre avant le lavage")

	Banc.laver(sale, config.nom_reserve_hygiene)
	verif.v(is_equal_approx(sale.proprietes.reserves[config.nom_reserve_hygiene].reserve,
			float(sale.proprietes.reserves[config.nom_reserve_hygiene].capacite)),
		"le lavage doit remettre la reserve a sa capacite")
	verif.v(sale.proprietes.etats_actifs.has("sale"),
		"le lavage ne touche NI etats_actifs NI l'odeur : c'est seuil_etat.gd qui retire, au tick suivant")

	_tick(scene, 0.5)
	verif.v(not sale.proprietes.etats_actifs.has("sale"),
		"au tick suivant, le franchissement DESCENDANT doit retirer 'sale'")
	verif.v(not sale.proprietes.has("sale"),
		"le miroir plat doit etre efface avec l'etat")
	verif.v(sale.proprietes[config.propriete_odeur] == 0.0,
		"l'odeur doit cesser des que 'sale' n'est plus actif")
	verif.v(sale.proprietes[config.propriete_apparence] == 0.0,
		"la visibilite d'etat doit retomber a 0.0 elle aussi")

	# Il se resalit, et peut etre relave : le cycle n'est pas a sens unique.
	for i in range(20):
		_tick(scene, 0.5)
	verif.v(sale.proprietes.etats_actifs.has("sale"),
		"apres lavage le colon doit pouvoir redevenir sale -- le seuil est REVERSIBLE, jamais consomme")

func _colon_blesse_percu_par_le_canal_apparence() -> void:
	var scene := _monter()
	var config: Dictionary = scene.config
	var blesse: Dictionary = scene.par_id["colon_blesse"]
	verif.v(blesse.proprietes.etats_actifs.has("blesse"),
		"colon_blesse doit porter 'blesse' des la fabrication (etats_actifs de la donnee)")
	_tick(scene, 0.1)
	verif.v(blesse.proprietes[config.propriete_apparence] > 0.0,
		"le cablage doit ecrire visibilite_etat sur le colon blesse")
	verif.v(blesse.proprietes[config.propriete_odeur] == 0.0,
		"'blesse' ne figure pas dans emission_odeur : un blesse ne sent pas mauvais")

	_placer(scene, "colon_blesse", Vector3.ZERO)
	_placer(scene, "colon_attentif", Vector3(300.0, 0.0, 0.0))
	_placer(scene, "colon_sale", Vector3(9000.0, 9000.0, 0.0))
	_placer(scene, "colon_distrait", Vector3(9000.0, 9500.0, 0.0))
	var canaux_captants: Array = []
	for entree in Banc.perceptions_de(scene.par_id["colon_attentif"], scene.monde, scene.canaux):
		if entree.chose.id == "colon_blesse":
			canaux_captants = entree.canaux
	verif.v(canaux_captants == ["apparence"],
		"le blesse ne doit etre capte QUE par le canal apparence (trouve : %s)" % str(canaux_captants))

# Le point fort de la ligne 13 : le seuil vit sur le PERCEPTEUR
# (canaux_config.apparence.seuil), pas dans le catalogue. 0.60 attenue vaut
# 0.1333 a 700 unites et 0.4667 a 200.
func _attentif_percoit_de_loin_distrait_seulement_de_pres() -> void:
	var scene := _monter()
	_tick(scene, 0.1)
	_placer(scene, "colon_blesse", Vector3.ZERO)
	_placer(scene, "colon_sale", Vector3(9000.0, 9000.0, 0.0))
	_placer(scene, "colon_attentif", Vector3(700.0, 0.0, 0.0))
	_placer(scene, "colon_distrait", Vector3(-700.0, 0.0, 0.0))
	verif.v(Banc.ids_de(Banc.perceptions_de(scene.par_id["colon_attentif"], scene.monde, scene.canaux)).has("colon_blesse"),
		"l'attentif (seuil 0.05) doit remarquer le blesse a 700 unites")
	verif.v(not Banc.ids_de(Banc.perceptions_de(scene.par_id["colon_distrait"], scene.monde, scene.canaux)).has("colon_blesse"),
		"le distrait (seuil 0.40) ne doit PAS remarquer le blesse a 700 unites")

	_placer(scene, "colon_distrait", Vector3(-200.0, 0.0, 0.0))
	verif.v(Banc.ids_de(Banc.perceptions_de(scene.par_id["colon_distrait"], scene.monde, scene.canaux)).has("colon_blesse"),
		"le meme distrait doit remarquer le blesse a 200 unites : le seuil filtre la DISTANCE, jamais la chose")

# ---------- Fonctions pures de deplacement et d'affichage ----------

func _errance_est_seedee_et_garde_sa_direction_le_temps_voulu() -> void:
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 1234
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 1234
	var etat_a: Dictionary = {}
	var etat_b: Dictionary = {}
	var d1 := Banc.avancer_errance(etat_a, 0.1, rng_a, 2.0)
	verif.v(d1.length() > 0.99 and d1.length() < 1.01, "l'errance doit rendre une direction normalisee")
	verif.v(d1.z == 0.0, "l'errance reste a plat (z = 0.0)")
	var d2 := Banc.avancer_errance(etat_a, 0.1, rng_a, 2.0)
	verif.v(d1 == d2, "la direction doit tenir tant que la duree n'est pas ecoulee")
	Banc.avancer_errance(etat_b, 0.1, rng_b, 2.0)
	Banc.avancer_errance(etat_b, 0.1, rng_b, 2.0)
	verif.v(etat_a.direction == etat_b.direction, "meme graine, meme suite de directions : aucun hasard non seede")
	var d3 := Banc.avancer_errance(etat_a, 5.0, rng_a, 2.0)
	verif.v(d3 != d2, "une fois la duree epuisee, une direction neuve doit etre tiree")

func _borner_garde_le_colon_dans_le_cadre_et_a_plat() -> void:
	var bornes := { "x_min": 100.0, "x_max": 1000.0, "y_min": 100.0, "y_max": 500.0 }
	verif.v(Banc.borner(Vector3(50.0, 50.0, 7.0), bornes) == Vector3(100.0, 100.0, 0.0),
		"borner doit ramener dans le cadre et remettre z a 0.0")
	verif.v(Banc.borner(Vector3(2000.0, 900.0, 0.0), bornes) == Vector3(1000.0, 500.0, 0.0),
		"borner doit couper aussi vers le haut")
	verif.v(Banc.borner(Vector3(500.0, 300.0, 0.0), bornes) == Vector3(500.0, 300.0, 0.0),
		"une position deja dans le cadre ne bouge pas")
	verif.v(Banc.borner(Vector3(5.0, 5.0, 0.0), {}) == Vector3(5.0, 5.0, 0.0),
		"bornes absentes : position rendue telle quelle, jamais une alarme")

func _compteurs_et_couleur_lisent_la_donnee() -> void:
	var scene := _monter()
	var config: Dictionary = scene.config
	verif.v(Banc.compter_etat(scene.colons, config.etat_compte) == 0, "aucun colon sale au depart")
	verif.v(Banc.compter_etat(scene.colons, "blesse") == 1, "exactement un colon blesse au depart")
	for i in range(20):
		_tick(scene, 0.5)
	verif.v(Banc.compter_etat(scene.colons, config.etat_compte) == 1, "exactement un colon sale apres 10 s")
	verif.v(Banc.texte_compteurs(1, 3) == "colons sales : 1    colons qui fuient : 3",
		"le compteur doit afficher les deux nombres demandes")
	verif.v(Banc.etat_dominant(scene.par_id["colon_blesse"], config.priorite_couleur) == "blesse",
		"la couleur d'un colon blesse doit venir de 'blesse'")
	verif.v(Banc.etat_dominant(scene.par_id["colon_sale"], config.priorite_couleur) == "sale",
		"la couleur d'un colon sale doit venir de 'sale'")
	verif.v(Banc.etat_dominant(scene.par_id["colon_attentif"], config.priorite_couleur) == "",
		"un colon sans etat visible n'a pas de couleur d'etat")
	var texte: String = Banc.texte_colon(
		scene.par_id["colon_sale"], config.nom_reserve_hygiene,
		config.propriete_odeur, config.propriete_apparence, ["colon_blesse"],
	)
	verif.v(texte.contains("colon_sale") and texte.contains("hygiene") and texte.contains("colon_blesse"),
		"le label doit porter l'id, l'hygiene et ce que le colon percoit")
	verif.v(Banc.ligne_log(1.0, "colon_attentif", [], []).contains("(personne)"),
		"la trace console doit dire explicitement quand un colon ne fuit personne")
