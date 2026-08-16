extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_attache_par_trait.gd
#
# Verrouille scripts/attache_par_trait.gd comme mecanisme GENERIQUE de
# passage lien personnel -> attache par trait (L'ELARGISSEMENT, PHASE 5
# etape 4/4 piece 1/3, chantier "L'entite comme agent complet"). Domaine
# invente (trait "massif", jamais vu ailleurs dans le depot -- catalogue
# hors domaine "gravitique_massif") : ce test prouve qu'avancer() traverse
# le meme code quel que soit le trait vise.
#
# Chemin reel : l'entite est fabriquee via Objet.fabriquer contre
# data/types.json lu sur disque ; le catalogue est
# data/attaches_par_trait.json lu sur disque, jamais une fixture locale
# pour les seuils. Les liens personnels sont poses via LienPersonnel.poser
# (chemin reel, scripts/lien_personnel.gd).
#
# Depuis la refonte "eclatement du corps interne", le type "entite" n'existe
# plus dans data/types.json -- liens_personnels vit desormais dans le paquet
# dynamique, attaches dans le paquet agent (voir docs/design.md, "L'entite
# comme agent complet"). AttacheParTrait.avancer exige les DEUX (structurel,
# voir attache_par_trait.gd) ; aucun type reel de data/types.json ne compose
# exactement dynamique+agent sans bagage supplementaire ("colon" ajoute
# rythme/vitesse/canaux elargis/etats.peur/deformation.habituation.brule,
# jamais voulu ici). _entite_reelle fabrique donc contre un TYPE-WRAPPER
# synthetique local, minimal (herite: ["dynamique", "agent"], aucune
# propriete propre), injecte dans une copie de la table reelle -- les DEUX
# paquets qu'il compose restent lus sur data/types.json, le chemin reste
# reel pour tout ce que ce test verrouille (liens_personnels/attaches),
# seul le nom du type composeur est local.

const AttacheParTrait = preload("res://scripts/attache_par_trait.gd")
const Objet = preload("res://scripts/objet.gd")
const LienPersonnel = preload("res://scripts/lien_personnel.gd")
const Monde = preload("res://scripts/monde.gd")
const Verif = preload("res://scripts/verif.gd")

func _init() -> void:
	var v := Verif.new()
	_deux_choses_liees_nombre_insuffisant_ne_forme_pas(v)
	_trois_choses_liees_force_insuffisante_ne_forme_pas(v)
	_trois_choses_liees_force_suffisante_forme_lattache(v)
	_second_appel_idempotent_ne_reforme_pas(v)
	_une_chose_sans_le_trait_ne_forme_pas(v)
	_chose_liee_absente_du_monde_ignoree_silencieusement(v)
	_propriete_structurelle_absente_alarme(v)
	_resumabilite_json_stricte(v)
	_surcharge_colon_complete_remplace_le_catalogue(v)
	_surcharge_colon_partielle_se_mele_au_catalogue(v)
	_absence_de_surcharge_retombe_sur_le_catalogue(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: attache_par_trait.gd forme une attache par trait quand assez " +
			"de liens personnels, assez forts, portent le meme trait -- " +
			"generique a tout trait invente")
		quit(0)

func _types_reels() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/types.json"))

func _catalogue_reel() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/attaches_par_trait.json"))

# Entite REELLE, fabriquee contre data/types.json par un type-wrapper
# synthetique local qui compose dynamique+agent (voir commentaire d'en-tete
# du fichier). Herite liens_personnels: {} (paquet dynamique) et attaches: []
# (paquet agent), tous deux vides a la naissance -- meme forme qu'avant la
# refonte.
func _entite_reelle(id: String) -> Dictionary:
	var table := _types_reels().duplicate(true)
	table["entite_test"] = {"herite": ["dynamique", "agent"]}
	return Objet.fabriquer(id, "entite_test", Vector3.ZERO, table)

func _chose_massif(id: String, massif: bool) -> Dictionary:
	var proprietes := {}
	if massif:
		proprietes["massif"] = true
	return {"id": id, "position": Vector3.ZERO, "proprietes": proprietes}

func _monde_avec(choses: Array) -> Monde:
	var monde := Monde.new()
	for c in choses:
		monde.ajouter(c, "roc", c.position)
	return monde

func _deux_choses_liees_nombre_insuffisant_ne_forme_pas(v) -> void:
	var gardien := _entite_reelle("gardien_1")
	var monde := _monde_avec([_chose_massif("caillou_1", true), _chose_massif("caillou_2", true)])
	LienPersonnel.poser(gardien, "caillou_1", 0.7)
	LienPersonnel.poser(gardien, "caillou_2", 0.7)
	var nouveaux := AttacheParTrait.avancer(gardien, monde, _catalogue_reel())
	v.v(nouveaux.is_empty(), "seulement deux choses liees (seuil_nombre 3) ne doit jamais former l'attache")
	v.v(gardien.proprietes.attaches.is_empty(), "attaches doit rester vide, nombre insuffisant")

func _trois_choses_liees_force_insuffisante_ne_forme_pas(v) -> void:
	var gardien := _entite_reelle("gardien_2")
	var monde := _monde_avec([
		_chose_massif("caillou_1", true),
		_chose_massif("caillou_2", true),
		_chose_massif("caillou_3", true),
	])
	LienPersonnel.poser(gardien, "caillou_1", 0.3)
	LienPersonnel.poser(gardien, "caillou_2", 0.3)
	LienPersonnel.poser(gardien, "caillou_3", 0.3)
	var nouveaux := AttacheParTrait.avancer(gardien, monde, _catalogue_reel())
	v.v(nouveaux.is_empty(), "force 0.3 sous seuil_force 0.5 ne doit jamais compter, meme a trois choses liees")
	v.v(gardien.proprietes.attaches.is_empty(), "attaches doit rester vide, force insuffisante par lien")

func _trois_choses_liees_force_suffisante_forme_lattache(v) -> void:
	var gardien := _entite_reelle("gardien_3")
	var monde := _monde_avec([
		_chose_massif("caillou_1", true),
		_chose_massif("caillou_2", true),
		_chose_massif("caillou_3", true),
	])
	LienPersonnel.poser(gardien, "caillou_1", 0.6)
	LienPersonnel.poser(gardien, "caillou_2", 0.6)
	LienPersonnel.poser(gardien, "caillou_3", 0.6)
	var nouveaux := AttacheParTrait.avancer(gardien, monde, _catalogue_reel())
	v.v(nouveaux.size() == 1 and nouveaux[0] == "massif",
		"trois choses liees, massif, force suffisante doit former l'attache et nommer le trait dans le retour")
	v.v(gardien.proprietes.attaches.size() == 1, "attaches doit gagner exactement une entree")
	if gardien.proprietes.attaches.size() == 1:
		var attache: Dictionary = gardien.proprietes.attaches[0]
		v.v(attache.propriete == "massif", "l'attache formee doit porter la propriete 'massif'")
		v.v(attache.force == 1.0, "l'attache formee doit porter force_attache du catalogue (1.0)")

func _second_appel_idempotent_ne_reforme_pas(v) -> void:
	var gardien := _entite_reelle("gardien_4")
	var monde := _monde_avec([
		_chose_massif("caillou_1", true),
		_chose_massif("caillou_2", true),
		_chose_massif("caillou_3", true),
	])
	LienPersonnel.poser(gardien, "caillou_1", 0.6)
	LienPersonnel.poser(gardien, "caillou_2", 0.6)
	LienPersonnel.poser(gardien, "caillou_3", 0.6)
	AttacheParTrait.avancer(gardien, monde, _catalogue_reel())
	var nouveaux := AttacheParTrait.avancer(gardien, monde, _catalogue_reel())
	v.v(nouveaux.is_empty(), "un second appel dans les memes conditions ne doit rien former de neuf")
	v.v(gardien.proprietes.attaches.size() == 1, "l'attache ne doit jamais etre dupliquee (idempotence)")

func _une_chose_sans_le_trait_ne_forme_pas(v) -> void:
	var gardien := _entite_reelle("gardien_5")
	var monde := _monde_avec([
		_chose_massif("caillou_1", true),
		_chose_massif("caillou_2", true),
		_chose_massif("caillou_3", false),
	])
	LienPersonnel.poser(gardien, "caillou_1", 0.6)
	LienPersonnel.poser(gardien, "caillou_2", 0.6)
	LienPersonnel.poser(gardien, "caillou_3", 0.6)
	var nouveaux := AttacheParTrait.avancer(gardien, monde, _catalogue_reel())
	v.v(nouveaux.is_empty(), "seulement deux choses liees portent reellement 'massif' -- nombre insuffisant malgre trois liens")
	v.v(gardien.proprietes.attaches.is_empty(), "attaches doit rester vide")

func _chose_liee_absente_du_monde_ignoree_silencieusement(v) -> void:
	var gardien := _entite_reelle("gardien_6")
	var monde := _monde_avec([
		_chose_massif("caillou_1", true),
		_chose_massif("caillou_2", true),
		_chose_massif("caillou_3", true),
	])
	LienPersonnel.poser(gardien, "caillou_1", 0.6)
	LienPersonnel.poser(gardien, "caillou_2", 0.6)
	LienPersonnel.poser(gardien, "caillou_3", 0.6)
	LienPersonnel.poser(gardien, "caillou_fantome", 0.6)
	var nouveaux := AttacheParTrait.avancer(gardien, monde, _catalogue_reel())
	v.v(nouveaux.size() == 1 and nouveaux[0] == "massif",
		"un chose_id absent du monde doit etre ignore silencieusement, sans empecher les liens reels de compter ni planter")

func _propriete_structurelle_absente_alarme(v) -> void:
	var gardien := {"id": "gardien_7", "position": Vector3.ZERO, "proprietes": {}}
	var monde := _monde_avec([])
	var nouveaux := AttacheParTrait.avancer(gardien, monde, _catalogue_reel())
	v.v(nouveaux.is_empty(), "une entite sans 'liens_personnels' ni 'attaches' doit alarmer et rendre un Array vide, jamais un crash")

	# L'entite VIDE ci-dessus sort sur la PREMIERE garde ; la seconde n'est
	# atteinte que par une entite a qui il manque exactement 'attaches'.
	var sans_attaches := {"id": "gardien_8", "position": Vector3.ZERO, "proprietes": {"liens_personnels": {}}}
	v.v(AttacheParTrait.avancer(sans_attaches, monde, _catalogue_reel()).is_empty(),
		"'attaches' absente alors que 'liens_personnels' est la : alarme, aucune cristallisation")
	v.v(not sans_attaches.proprietes.has("attaches"),
		"la cle absente n'est jamais creee au passage")

func _resumabilite_json_stricte(v) -> void:
	var gardien := _entite_reelle("gardien_8")
	var monde := _monde_avec([
		_chose_massif("caillou_1", true),
		_chose_massif("caillou_2", true),
		_chose_massif("caillou_3", true),
	])
	LienPersonnel.poser(gardien, "caillou_1", 0.6)
	LienPersonnel.poser(gardien, "caillou_2", 0.6)
	LienPersonnel.poser(gardien, "caillou_3", 0.6)
	AttacheParTrait.avancer(gardien, monde, _catalogue_reel())
	var texte := JSON.stringify(gardien)
	var relu: Variant = JSON.parse_string(texte)
	v.v(relu != null, "JSON.stringify puis parse_string doit reussir sans erreur")
	v.v(relu.proprietes.attaches.size() == 1 and relu.proprietes.attaches[0].propriete == "massif",
		"l'attache par trait formee doit survivre identique a l'aller-retour JSON")

# PHASE 5 etape 4/4 piece 2/3 -- SURCHARGE PAR COLON (voir attache_par_trait.gd,
# "SURCHARGE PAR COLON"). Les trois cas suivants exercent
# proprietes.sensibilite_generalisation, absente des fixtures ci-dessus
# (piece 1) : surcharge complete, surcharge partielle (melange colon +
# catalogue), et absence explicite (repli total sur le catalogue).

func _surcharge_colon_complete_remplace_le_catalogue(v) -> void:
	var gardien := _entite_reelle("gardien_9")
	gardien.proprietes["sensibilite_generalisation"] = {
		"massif": {"seuil_nombre": 2, "seuil_force": 0.2, "force_attache": 5.0},
	}
	var monde := _monde_avec([_chose_massif("caillou_1", true), _chose_massif("caillou_2", true)])
	LienPersonnel.poser(gardien, "caillou_1", 0.3)
	LienPersonnel.poser(gardien, "caillou_2", 0.3)
	var nouveaux := AttacheParTrait.avancer(gardien, monde, _catalogue_reel())
	v.v(nouveaux.size() == 1 and nouveaux[0] == "massif",
		"surcharge complete (seuil_nombre 2, seuil_force 0.2) doit former l'attache a deux choses liees a force 0.3, sous le seuil_force du catalogue (0.5)")
	v.v(gardien.proprietes.attaches.size() == 1 and gardien.proprietes.attaches[0].force == 5.0,
		"l'attache formee doit porter force_attache DU COLON (5.0), jamais celle du catalogue (1.0)")

func _surcharge_colon_partielle_se_mele_au_catalogue(v) -> void:
	var gardien := _entite_reelle("gardien_10")
	gardien.proprietes["sensibilite_generalisation"] = {"massif": {"seuil_nombre": 2}}
	var monde := _monde_avec([_chose_massif("caillou_1", true), _chose_massif("caillou_2", true)])
	LienPersonnel.poser(gardien, "caillou_1", 0.6)
	LienPersonnel.poser(gardien, "caillou_2", 0.6)
	var nouveaux := AttacheParTrait.avancer(gardien, monde, _catalogue_reel())
	v.v(nouveaux.size() == 1 and nouveaux[0] == "massif",
		"surcharge partielle (seuil_nombre 2 seul) doit former l'attache a deux choses liees, force 0.6 au-dessus du seuil_force DU CATALOGUE (0.5, non surcharge)")
	v.v(gardien.proprietes.attaches.size() == 1 and gardien.proprietes.attaches[0].force == 1.0,
		"force_attache non surchargee doit venir du catalogue (1.0)")

	var gardien_insuffisant := _entite_reelle("gardien_11")
	gardien_insuffisant.proprietes["sensibilite_generalisation"] = {"massif": {"seuil_nombre": 2}}
	var monde2 := _monde_avec([_chose_massif("caillou_1", true), _chose_massif("caillou_2", true)])
	LienPersonnel.poser(gardien_insuffisant, "caillou_1", 0.3)
	LienPersonnel.poser(gardien_insuffisant, "caillou_2", 0.3)
	var nouveaux2 := AttacheParTrait.avancer(gardien_insuffisant, monde2, _catalogue_reel())
	v.v(nouveaux2.is_empty(),
		"seuil_force NON surcharge (0.5, catalogue) doit toujours s'appliquer malgre seuil_nombre surcharge -- force 0.3 insuffisante")

func _absence_de_surcharge_retombe_sur_le_catalogue(v) -> void:
	var gardien := _entite_reelle("gardien_12")
	gardien.proprietes["sensibilite_generalisation"] = {}
	var monde := _monde_avec([
		_chose_massif("caillou_1", true), _chose_massif("caillou_2", true), _chose_massif("caillou_3", true),
	])
	LienPersonnel.poser(gardien, "caillou_1", 0.6)
	LienPersonnel.poser(gardien, "caillou_2", 0.6)
	var nouveaux_insuffisant := AttacheParTrait.avancer(gardien, monde, _catalogue_reel())
	v.v(nouveaux_insuffisant.is_empty(),
		"sensibilite_generalisation vide doit retomber entierement sur le catalogue -- deux choses liees, sous seuil_nombre 3")
	LienPersonnel.poser(gardien, "caillou_3", 0.6)
	var nouveaux := AttacheParTrait.avancer(gardien, monde, _catalogue_reel())
	v.v(nouveaux.size() == 1 and nouveaux[0] == "massif" and gardien.proprietes.attaches[0].force == 1.0,
		"trois choses liees, force du catalogue, doit former l'attache avec force_attache du catalogue -- comportement piece 1 preserve")
