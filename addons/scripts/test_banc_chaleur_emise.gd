extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_chaleur_emise.gd
#
# Verrouille le cablage de banc_chaleur_emise.gd -- chantier « chaleur_emise
# -- un feu emet de la chaleur » :
# 1. sources_chaleur (PROPRE a ce banc) construit une source PAR OBJET qui
#    porte "brule" CE TICK, force PROPORTIONNELLE a "chaleur_emise" ;
# 2. un objet qui ne brule pas (jamais allume, ou eteint) n'apparait jamais
#    dans les sources ;
# 3. Temperature.avancer (INCHANGE) applique ces sources -- un voisin se
#    rechauffe d'autant plus vite que la source a une chaleur_emise haute,
#    chaleur_emise 0.0 n'emet rien ;
# 4. Depense.avancer (INCHANGE) detecte l'epuisement de la reserve
#    "combustible" et retire "brule" -- la source disparait au tick suivant,
#    jamais reconstruite.
#
# AUCUN MECANISME DU COEUR TOUCHE par ce chantier : temperature.gd/
# depense.gd/combustible.gd/objet.gd restent exactement ceux deja
# verrouilles par leurs propres tests -- ce fichier verrouille uniquement
# banc_chaleur_emise.gd.

const BancChaleurEmise = preload("res://scripts/banc_chaleur_emise.gd")
const Temperature = preload("res://scripts/temperature.gd")
const Depense = preload("res://scripts/depense.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

func _init() -> void:
	_source_construite_pour_un_objet_qui_brule()
	_aucune_source_pour_un_objet_qui_ne_brule_pas()
	_force_proportionnelle_a_chaleur_emise()
	_chaleur_emise_zero_n_emet_rien()
	_objet_eteint_cesse_d_emettre()
	_chemin_reel_objet_qui_brule_rechauffe_voisin()
	_chemin_reel_chaleur_emise_haute_rechauffe_plus_vite_que_basse()
	_chemin_reel_extinction_retire_brule_et_supprime_la_source()
	_donnees_reelles_banc_chaleur_emise_json()
	_chemin_reel_fabrication_fusionne_chaleur_emise()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: banc_chaleur_emise.gd -- une source de chaleur est construite par tick pour chaque objet " +
		"qui brule, force proportionnelle a chaleur_emise, un objet qui ne brule pas n'emet jamais, " +
		"chaleur_emise 0.0 n'emet rien, l'extinction (depense.gd) supprime la source au tick suivant, " +
		"chemin reel (data/banc_chaleur_emise.json + materiaux.json + types.json) : le bois qui brule " +
		"rechauffe un voisin a distance egale plus vite que le fer")
	quit(0)

# ---- Fixtures : chargement disque ----

func _charger(chemin: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))

func _config() -> Dictionary:
	return _charger("res://data/banc_chaleur_emise.json")

func _materiaux() -> Dictionary:
	return _charger("res://data/materiaux.json")

func _proprietes_immuables() -> Array:
	return _charger("res://data/proprietes_immuables_composition.json").get("proprietes", [])

func _objet_physique() -> Dictionary:
	return _charger("res://data/types.json").get("objet_physique", {})

func _catalogue_temperature() -> Dictionary:
	return _charger("res://data/temperature.json")

func _seuils_combustible() -> Dictionary:
	return _charger("res://data/seuils_combustible.json")

func _reserve_combustible() -> Dictionary:
	return _charger("res://data/reserve_combustible_composition.json")

func _objets_reels() -> Array:
	var config := _config()
	return BancChaleurEmise.fabriquer_objets(config.objets, _objet_physique(), _materiaux(), _proprietes_immuables(), _reserve_combustible())

func _par_id(objets: Array, id: String) -> Dictionary:
	for objet in objets:
		if objet.id == id:
			return objet
	return {}

# ---- sources_chaleur, pure ----

func _source_construite_pour_un_objet_qui_brule() -> void:
	var objets := [{"id": "a", "position": Vector3(10.0, 0.0, 0.0), "proprietes": {"brule": true, "chaleur_emise": 0.5}}]
	var sources := BancChaleurEmise.sources_chaleur(objets, 300.0, 800.0)
	verif.v(sources.size() == 1, "un objet qui brule doit produire exactement une source")
	verif.v(sources[0].position == Vector3(10.0, 0.0, 0.0), "la source doit etre construite a la position de l'objet")
	verif.v(is_equal_approx(sources[0].rayon, 300.0), "la source doit reprendre le rayon_emission recu")
	verif.v(is_equal_approx(sources[0].temperature, 800.0), "la source doit reprendre la temperature_source recue")
	verif.v(is_equal_approx(sources[0].force, 0.5), "la force de la source doit egaler chaleur_emise")

func _aucune_source_pour_un_objet_qui_ne_brule_pas() -> void:
	var objets := [
		{"id": "eteint", "position": Vector3.ZERO, "proprietes": {"brule": false, "chaleur_emise": 0.9}},
		{"id": "jamais_allume", "position": Vector3.ZERO, "proprietes": {"chaleur_emise": 0.9}},
	]
	var sources := BancChaleurEmise.sources_chaleur(objets, 300.0, 800.0)
	verif.v(sources.is_empty(), "un objet qui ne porte pas 'brule' a true ne doit jamais produire de source, meme avec chaleur_emise haute")

func _force_proportionnelle_a_chaleur_emise() -> void:
	var haute := [{"id": "haute", "position": Vector3.ZERO, "proprietes": {"brule": true, "chaleur_emise": 0.8}}]
	var basse := [{"id": "basse", "position": Vector3.ZERO, "proprietes": {"brule": true, "chaleur_emise": 0.3}}]
	var source_haute: Dictionary = BancChaleurEmise.sources_chaleur(haute, 300.0, 800.0)[0]
	var source_basse: Dictionary = BancChaleurEmise.sources_chaleur(basse, 300.0, 800.0)[0]
	verif.v(source_haute.force > source_basse.force, "une chaleur_emise plus haute doit produire une force de source plus haute")
	verif.v(is_equal_approx(source_haute.force / source_basse.force, 0.8 / 0.3), "la force doit rester exactement proportionnelle a chaleur_emise (rapport 0.8/0.3)")

# ---- chaleur_emise 0.0 : aucune emission ----

func _chaleur_emise_zero_n_emet_rien() -> void:
	var catalogue := _catalogue_temperature()
	var foyer := [{"id": "foyer_froid", "position": Vector3.ZERO, "proprietes": {"brule": true, "chaleur_emise": 0.0}}]
	var voisin := {"id": "voisin", "position": Vector3(100.0, 0.0, 0.0), "proprietes": {"temperature": 20.0, "conductivite_thermique": 2.5, "chaleur_specifique": 790.0}}
	var monde := [voisin]
	var sources := BancChaleurEmise.sources_chaleur(foyer, 300.0, 800.0)
	verif.v(sources.size() == 1, "un objet 'brule' avec chaleur_emise 0.0 doit quand meme produire une source (force nulle, pas une absence)")
	for i in 20:
		Temperature.avancer(monde, sources, 0.5, catalogue)
	verif.v(is_equal_approx(voisin.proprietes.temperature, 20.0), "chaleur_emise 0.0 : le voisin deja a l'ambiante ne doit jamais se rechauffer, meme apres plusieurs pas")

# ---- Extinction : la source disparait au tick suivant ----

func _objet_eteint_cesse_d_emettre() -> void:
	var objets := [{"id": "a", "position": Vector3.ZERO, "proprietes": {"brule": true, "chaleur_emise": 0.8}}]
	verif.v(BancChaleurEmise.sources_chaleur(objets, 300.0, 800.0).size() == 1, "avant extinction : une source doit exister")
	objets[0].proprietes.brule = false
	verif.v(BancChaleurEmise.sources_chaleur(objets, 300.0, 800.0).is_empty(), "apres extinction (brule=false) : sources_chaleur ne doit plus jamais reconstruire de source pour cet objet")

# ---- Chemin REEL : le bois qui brule rechauffe un voisin ----

func _chemin_reel_objet_qui_brule_rechauffe_voisin() -> void:
	var config := _config()
	var objets := _objets_reels()
	var bois_brule := _par_id(objets, "bois_brule")
	var froid_pres_bois := _par_id(objets, "froid_pres_bois")
	verif.v(not bois_brule.is_empty() and not froid_pres_bois.is_empty(), "chemin reel : bois_brule et froid_pres_bois doivent exister")

	var monde := [bois_brule, froid_pres_bois]
	var temperature_avant: float = froid_pres_bois.proprietes.temperature
	var catalogue := _catalogue_temperature()
	for i in 20:
		var sources := BancChaleurEmise.sources_chaleur(monde, config.rayon_emission, config.temperature_source)
		Temperature.avancer(monde, sources, 0.5, catalogue)
	verif.v(froid_pres_bois.proprietes.temperature > temperature_avant, "chemin reel : froid_pres_bois doit se rechauffer tant que bois_brule brule a portee")

# ---- Chemin REEL : chaleur_emise haute (bois) rechauffe plus vite que basse (fer) ----

func _chemin_reel_chaleur_emise_haute_rechauffe_plus_vite_que_basse() -> void:
	var config := _config()
	var objets := _objets_reels()
	var bois_brule := _par_id(objets, "bois_brule")
	var fer_brule := _par_id(objets, "fer_brule")
	var froid_pres_bois := _par_id(objets, "froid_pres_bois")
	var froid_pres_fer := _par_id(objets, "froid_pres_fer")
	verif.v(bois_brule.proprietes.chaleur_emise > fer_brule.proprietes.chaleur_emise,
		"chemin reel : chaleur_emise du bois doit etre strictement superieure a celle du fer (donnee du chantier)")

	var monde := [bois_brule, fer_brule, froid_pres_bois, froid_pres_fer]
	var catalogue := _catalogue_temperature()
	# fenetre courte (10s simules), largement a l'interieur de la duree de
	# combustion des deux foyers (~20-23s, voir data/banc_chaleur_emise.json._note)
	for i in 20:
		var sources := BancChaleurEmise.sources_chaleur(monde, config.rayon_emission, config.temperature_source)
		Temperature.avancer(monde, sources, 0.5, catalogue)
	var hausse_bois: float = froid_pres_bois.proprietes.temperature - 20.0
	var hausse_fer: float = froid_pres_fer.proprietes.temperature - 20.0
	verif.v(hausse_bois > 0.0 and hausse_fer > 0.0, "chemin reel : les deux voisins doivent se rechauffer (les deux foyers brulent encore a 10s)")
	verif.v(hausse_bois > hausse_fer, "chemin reel : a distance egale, le voisin du bois (chaleur_emise plus haute) doit se rechauffer plus que le voisin du fer")

# ---- Chemin REEL : l'extinction retire 'brule' et supprime la source ----

func _chemin_reel_extinction_retire_brule_et_supprime_la_source() -> void:
	var objets := _objets_reels()
	var bois_brule := _par_id(objets, "bois_brule")
	verif.v(bois_brule.proprietes.get("brule", false), "avant extinction : bois_brule doit porter 'brule'")

	# force une reserve presque epuisee (chemin reel de depense.gd/
	# seuils_combustible.json, jamais un retrait direct de 'brule' par ce
	# test -- verrouille le VRAI detecteur d'extinction)
	bois_brule.proprietes.reserves.combustible.reserve = 0.001
	var seuils := _seuils_combustible()
	var franchis: Array = Depense.avancer([bois_brule], 1.0, seuils)
	verif.v(franchis.has("bois_brule"), "depense.gd doit signaler que bois_brule a franchi le seuil d'epuisement")
	verif.v(not bois_brule.proprietes.get("brule", false), "apres epuisement : depense.gd doit avoir retire 'brule' (seuils_combustible.json:epuisement)")

	var sources := BancChaleurEmise.sources_chaleur([bois_brule], 300.0, 800.0)
	verif.v(sources.is_empty(), "apres extinction reelle : sources_chaleur ne doit plus jamais produire de source pour bois_brule")

# ---- Chemin REEL : data/banc_chaleur_emise.json ----

func _donnees_reelles_banc_chaleur_emise_json() -> void:
	var config := _config()
	verif.v(config.objets.size() == 4, "data/banc_chaleur_emise.json doit declarer quatre objets")
	var par_id: Dictionary = {}
	for decl in config.objets:
		par_id[decl.id] = decl
	verif.v(par_id.bois_brule.composition[0].materiau == "bois", "bois_brule doit etre compose de bois")
	verif.v(par_id.fer_brule.composition[0].materiau == "fer", "fer_brule doit etre compose de fer")
	verif.v(par_id.bois_brule.brule_initial == true, "bois_brule doit demarrer allume")
	verif.v(par_id.froid_pres_bois.get("brule_initial", false) == false, "froid_pres_bois ne doit jamais demarrer allume")

	var pos_bois: Array = par_id.bois_brule.position
	var pos_froid_bois: Array = par_id.froid_pres_bois.position
	var pos_fer: Array = par_id.fer_brule.position
	var pos_froid_fer: Array = par_id.froid_pres_fer.position
	var distance_bois: float = Vector3(pos_bois[0], pos_bois[1], pos_bois[2]).distance_to(Vector3(pos_froid_bois[0], pos_froid_bois[1], pos_froid_bois[2]))
	var distance_fer: float = Vector3(pos_fer[0], pos_fer[1], pos_fer[2]).distance_to(Vector3(pos_froid_fer[0], pos_froid_fer[1], pos_froid_fer[2]))
	verif.v(is_equal_approx(distance_bois, distance_fer), "froid_pres_bois et froid_pres_fer doivent etre a la MEME distance de leur propre foyer, pour une comparaison propre")

# ---- Chemin REEL : la fabrication fusionne chaleur_emise ----

func _chemin_reel_fabrication_fusionne_chaleur_emise() -> void:
	var objets := _objets_reels()
	var bois_brule := _par_id(objets, "bois_brule")
	var fer_brule := _par_id(objets, "fer_brule")
	var froid_pres_bois := _par_id(objets, "froid_pres_bois")

	verif.v(bois_brule.proprietes.has("temperature"), "chemin reel : bois_brule doit porter 'temperature' (paquet objet_physique fusionne)")
	verif.v(is_equal_approx(bois_brule.proprietes.chaleur_emise, 0.8), "chemin reel : bois_brule doit fusionner chaleur_emise=0.8 depuis materiaux.json")
	verif.v(is_equal_approx(fer_brule.proprietes.chaleur_emise, 0.3), "chemin reel : fer_brule doit fusionner chaleur_emise=0.3 depuis materiaux.json")
	verif.v(is_equal_approx(froid_pres_bois.proprietes.chaleur_emise, 0.0), "chemin reel : froid_pres_bois (pierre) doit fusionner chaleur_emise=0.0")
	verif.v(bois_brule.proprietes.has("reserves") and bois_brule.proprietes.reserves.has("combustible"), "chemin reel : bois_brule doit porter une reserve 'combustible' reelle")
	verif.v(not froid_pres_bois.proprietes.has("reserves"), "chemin reel : froid_pres_bois ne doit jamais recevoir de reserve 'combustible' (brule_initial false)")
