extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_photodegradation.gd
#
# Verrouille le cablage de banc_photodegradation.gd -- le soleil (scripts/
# lumiere.gd, NON TOUCHE) module cout_base EFFECTIF sur la reserve
# 'integrite' (scripts/depense.gd, NON TOUCHE) proportionnellement a
# biodegradabilite. AUCUN MECANISME DU COEUR TOUCHE par ce chantier :
# lumiere.gd/depense.gd/objet.gd restent exactement ceux deja verrouilles
# par leurs propres tests -- ce fichier verrouille uniquement
# banc_photodegradation.gd.

const BancPhoto = preload("res://scripts/banc_photodegradation.gd")
const Lumiere = preload("res://scripts/lumiere.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

const CONFIG := {
	"propriete_biodegradabilite": "biodegradabilite",
	"nom_reserve_integrite": "integrite",
	"facteur_uv_degradation": 1.0,
	"reserve_integrite_defaut": {"reserve": 20.0, "cout_base": 0.0, "surcout_action": 0.0},
}

const CATALOGUE_LUMIERE := {
	"defaut": {"ambiante": {"intensite": 0.0, "couleur": 0.9}, "attenuation": {"exposant": 1.0}},
}

const SOLEIL := {"position": Vector3(0, 0, 0), "rayon": 200.0, "intensite": 1.0, "temperature_couleur": 0.2, "force": 1.0}

func _init() -> void:
	_basculer_soleil_pur()
	_bois_au_soleil_se_degrade()
	_bois_dans_le_noir_ne_perd_rien()
	_pierre_au_soleil_ne_perd_rien()
	_vitesse_proportionnelle_a_biodegradabilite_x_lumiere()
	_lumiere_coupee_arrete_la_degradation()
	_biodegradabilite_nulle_ne_se_degrade_jamais_meme_en_plein_soleil()
	_hors_domaine_avancer_ignore_le_domaine()
	_fabrication_reelle_fusionne_biodegradabilite_depuis_materiaux_json()
	_donnees_reelles_banc_photodegradation_json()
	_chemin_reel_complet_trois_objets()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: bascule du soleil pure, le bois au soleil se degrade, le bois dans le noir ne perd rien, " +
		"la pierre au soleil ne perd rien, la vitesse de degradation est exactement proportionnelle a " +
		"biodegradabilite x lumiere_locale, couper la lumiere arrete la degradation, biodegradabilite 0.0 " +
		"ne se degrade jamais meme en plein soleil, avancer() ignore le domaine, la fabrication reelle " +
		"fusionne biodegradabilite depuis materiaux.json, data/banc_photodegradation.json charge " +
		"correctement, et le chemin reel complet (trois objets, donnees sur disque) se comporte comme attendu")
	quit(0)

func _objet(id: String, position: Vector3, biodegradabilite: float, reserve: Variant) -> Dictionary:
	var proprietes: Dictionary = {"biodegradabilite": biodegradabilite}
	if reserve != null:
		proprietes["reserves"] = {"integrite": (reserve as Dictionary).duplicate(true)}
	return {"id": id, "position": position, "proprietes": proprietes}

func _reserve() -> Dictionary:
	return CONFIG.reserve_integrite_defaut.duplicate(true)

func _basculer_soleil_pur() -> void:
	verif.v(not BancPhoto.basculer_soleil(true), "un soleil actif bascule vers coupe")
	verif.v(BancPhoto.basculer_soleil(false), "un soleil coupe bascule vers actif")

func _bois_au_soleil_se_degrade() -> void:
	var objet := _objet("bois_soleil", Vector3(100, 0, 0), 0.9, _reserve())
	var temps := 0.0
	var delta := 1.0
	for i in 20:
		BancPhoto.avancer([objet], [SOLEIL], delta, CONFIG, CATALOGUE_LUMIERE)
		temps += delta
	verif.v(objet.proprietes.reserves.integrite.reserve < 20.0, "au soleil, avec une biodegradabilite non nulle, la reserve d'integrite doit avoir strictement decru")
	verif.v(objet.proprietes.reserves.integrite.reserve >= 0.0, "la reserve d'integrite reste bornee a 0.0 (depense.gd, non touche)")

func _bois_dans_le_noir_ne_perd_rien() -> void:
	var objet := _objet("bois_noir", Vector3(2000, 0, 0), 0.9, _reserve())
	var temps := 0.0
	var delta := 1.0
	for i in 30:
		BancPhoto.avancer([objet], [SOLEIL], delta, CONFIG, CATALOGUE_LUMIERE)
		temps += delta
	verif.v(objet.proprietes.reserves.integrite.reserve == 20.0, "hors du rayon du soleil, lumiere_locale=0.0 -- la reserve d'integrite ne doit jamais decroitre, quelle que soit la biodegradabilite")

func _pierre_au_soleil_ne_perd_rien() -> void:
	var objet := _objet("pierre_soleil", Vector3(100, 0, 0), 0.0, _reserve())
	var temps := 0.0
	var delta := 1.0
	for i in 30:
		BancPhoto.avancer([objet], [SOLEIL], delta, CONFIG, CATALOGUE_LUMIERE)
		temps += delta
	verif.v(objet.proprietes.reserves.integrite.reserve == 20.0, "biodegradabilite 0.0, meme en plein soleil, la reserve d'integrite ne doit jamais decroitre")

# Verrouille la LOI exacte, pas seulement un ordre relatif : deux objets a
# la MEME position (meme lumiere_locale), biodegradabilite dans un rapport
# de 2 -- le cout_base_eff ecrit doit suivre exactement ce rapport, et
# valoir exactement biodegradabilite * facteur_uv_degradation *
# lumiere_locale (lumiere_locale recalculee independamment via
# Lumiere.locale, jamais supposee).
func _vitesse_proportionnelle_a_biodegradabilite_x_lumiere() -> void:
	var position := Vector3(100, 0, 0)
	var objet_fort := _objet("fort", position, 0.9, _reserve())
	var objet_faible := _objet("faible", position, 0.45, _reserve())
	BancPhoto.avancer([objet_fort, objet_faible], [SOLEIL], 1.0, CONFIG, CATALOGUE_LUMIERE)

	var cout_fort: float = objet_fort.proprietes.reserves.integrite.cout_base
	var cout_faible: float = objet_faible.proprietes.reserves.integrite.cout_base
	verif.v(abs(cout_fort - 2.0 * cout_faible) < 0.0001, "cout_base_eff doit etre proportionnel a biodegradabilite : le double de biodegradabilite doit produire exactement le double de cout_base_eff a lumiere egale")

	var lumiere_attendue: float = Lumiere.locale(position, [SOLEIL], CATALOGUE_LUMIERE).intensite
	verif.v(abs(cout_fort - 0.9 * float(CONFIG.facteur_uv_degradation) * lumiere_attendue) < 0.0001, "cout_base_eff doit valoir exactement biodegradabilite * facteur_uv_degradation * lumiere_locale")
	verif.v(lumiere_attendue > 0.0, "cette assertion suppose l'objet reellement eclaire, sinon les deux verifications precedentes seraient triviales")

func _lumiere_coupee_arrete_la_degradation() -> void:
	var objet := _objet("bois_coupe", Vector3(100, 0, 0), 0.9, _reserve())
	var delta := 1.0
	for i in 10:
		BancPhoto.avancer([objet], [SOLEIL], delta, CONFIG, CATALOGUE_LUMIERE)
	var reserve_apres_exposition: float = objet.proprietes.reserves.integrite.reserve
	verif.v(reserve_apres_exposition < 20.0, "avant coupure, la reserve doit avoir decru (sinon la suite du test serait triviale)")

	for i in 10:
		BancPhoto.avancer([objet], [], delta, CONFIG, CATALOGUE_LUMIERE)
	verif.v(objet.proprietes.reserves.integrite.reserve == reserve_apres_exposition, "soleil coupe (liste de sources vide) -- la reserve ne doit plus bouger du tout, meme apres plusieurs pas")

func _biodegradabilite_nulle_ne_se_degrade_jamais_meme_en_plein_soleil() -> void:
	var objet := _objet("temoin_biodeg_nulle", Vector3(0, 0, 0), 0.0, _reserve())
	var delta := 1.0
	for i in 50:
		BancPhoto.avancer([objet], [SOLEIL], delta, CONFIG, CATALOGUE_LUMIERE)
	verif.v(objet.proprietes.reserves.integrite.reserve == 20.0, "biodegradabilite 0.0, y compris a la position exacte du soleil (lumiere_locale maximale), la reserve d'integrite ne doit jamais decroitre")

# Un canal/reserve/propriete invente, sans aucun rapport avec le soleil ou
# l'organique, doit traverser exactement le meme code -- meme serrure que
# test_banc_uv_degradation.gd:_hors_domaine_avancer_ignore_le_domaine.
func _hors_domaine_avancer_ignore_le_domaine() -> void:
	var config_invente := {
		"propriete_biodegradabilite": "friabilite_zorg",
		"nom_reserve_integrite": "coeur_zorg",
		"facteur_uv_degradation": 0.5,
		"reserve_integrite_defaut": {"reserve": 10.0, "cout_base": 0.0, "surcout_action": 0.0},
	}
	var source_invente := {"position": Vector3(0, 0, 0), "rayon": 100.0, "intensite": 1.0, "temperature_couleur": 0.5, "force": 1.0}
	var cobaye := {
		"id": "cobaye",
		"position": Vector3(20, 0, 0),
		"proprietes": {
			"friabilite_zorg": 1.0,
			"reserves": {"coeur_zorg": {"reserve": 10.0, "cout_base": 0.0, "surcout_action": 0.0}},
		},
	}

	var delta := 0.5
	for i in 20:
		BancPhoto.avancer([cobaye], [source_invente], delta, config_invente, CATALOGUE_LUMIERE)
	verif.v(cobaye.proprietes.reserves.coeur_zorg.reserve < 10.0, "un domaine invente doit voir sa reserve decroitre exactement comme le bois")

# Chemin REEL : materiaux.json/proprietes_immuables_composition.json lus
# sur disque, comme test_banc_uv_degradation.gd le fait -- verrouille que
# biodegradabilite (DEJA fusionnee par le chantier concurrent « UV et
# biodegradation ») est bien lue par fabriquer_objets(), independamment de
# tout cablage de scene.
func _fabrication_reelle_fusionne_biodegradabilite_depuis_materiaux_json() -> void:
	var materiaux: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))
	var proprietes_immuables: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/proprietes_immuables_composition.json")).get("proprietes", [])
	verif.v(proprietes_immuables.has("biodegradabilite"), "data/proprietes_immuables_composition.json doit lister biodegradabilite")

	var declarations := [
		{"id": "bois", "position": [0.0, 0.0, 0.0], "composition": [{"materiau": "bois", "volume": 3.0}]},
		{"id": "pierre", "position": [10.0, 0.0, 0.0], "composition": [{"materiau": "pierre", "volume": 3.0}]},
	]
	var objets := BancPhoto.fabriquer_objets(declarations, materiaux, proprietes_immuables, CONFIG)
	var bois: Dictionary = objets[0]
	var pierre: Dictionary = objets[1]
	verif.v(abs(bois.proprietes.biodegradabilite - 0.9) < 0.0001, "bois reel doit fusionner biodegradabilite=0.9 depuis materiaux.json")
	verif.v(abs(pierre.proprietes.biodegradabilite - 0.0) < 0.0001, "pierre reelle doit fusionner biodegradabilite=0.0 depuis materiaux.json")
	verif.v(not is_same(bois.proprietes.reserves.integrite, pierre.proprietes.reserves.integrite), "chaque objet fabrique doit avoir sa propre reserve, jamais un Dictionary partage")

func _donnees_reelles_banc_photodegradation_json() -> void:
	var donnees: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_photodegradation.json"))
	verif.v(donnees.propriete_biodegradabilite == "biodegradabilite", "data/banc_photodegradation.json doit declarer propriete_biodegradabilite")
	verif.v(donnees.nom_reserve_integrite == "integrite", "data/banc_photodegradation.json doit declarer nom_reserve_integrite")
	verif.v(donnees.objets.size() == 3, "data/banc_photodegradation.json doit declarer trois objets")
	var ids: Array = []
	for objet in donnees.objets:
		ids.append(objet.id)
	for id_attendu in ["bois_soleil", "bois_noir", "pierre_soleil"]:
		verif.v(ids.has(id_attendu), "data/banc_photodegradation.json doit declarer l'objet '%s'" % id_attendu)
	verif.v(not donnees.reserve_integrite_defaut.has("seuils_ref"), "ce banc ne configure aucun seuils_ref (cle absente, jamais une chaine vide -- voir depense.gd, facultative par defaut) -- juste une decroissance observee, jamais une transformation")

# Chemin REEL complet : data/banc_photodegradation.json/data/lumiere.json/
# data/materiaux.json/data/proprietes_immuables_composition.json lus sur
# disque, comme banc_photodegradation.gd les charge lui-meme a _ready() --
# reproduit sa boucle de simulation pour les trois objets reels, soleil
# actif puis coupe.
func _chemin_reel_complet_trois_objets() -> void:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_photodegradation.json"))
	var catalogue_lumiere: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/lumiere.json"))
	var materiaux: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))
	var proprietes_immuables: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/proprietes_immuables_composition.json")).get("proprietes", [])

	var objets := BancPhoto.fabriquer_objets(config.get("objets", []), materiaux, proprietes_immuables, config)
	var par_id: Dictionary = {}
	for objet in objets:
		par_id[objet.id] = objet

	var pos_soleil: Array = config.soleil.position
	var soleil := {
		"position": Vector3(pos_soleil[0], pos_soleil[1], pos_soleil[2]),
		"rayon": config.soleil.rayon, "intensite": config.soleil.intensite,
		"temperature_couleur": config.soleil.get("temperature_couleur", 0.0), "force": config.soleil.force,
	}

	var lumiere_bois_soleil := 0.0
	var lumiere_bois_noir := 0.0
	var delta := 0.5
	for i in 200:
		var resultat := BancPhoto.avancer(objets, [soleil], delta, config, catalogue_lumiere)
		lumiere_bois_soleil = max(lumiere_bois_soleil, float(resultat.lumieres.get("bois_soleil", 0.0)))
		lumiere_bois_noir = max(lumiere_bois_noir, float(resultat.lumieres.get("bois_noir", 0.0)))

	verif.v(lumiere_bois_soleil > 0.0, "chemin reel : bois_soleil doit reellement recevoir de la lumiere du soleil pendant la simulation")
	verif.v(lumiere_bois_noir == 0.0, "chemin reel : bois_noir doit rester a lumiere_locale=0.0 en permanence (hors de portee)")

	var reserve_bois_soleil: float = par_id.bois_soleil.proprietes.reserves.integrite.reserve
	var reserve_bois_noir: float = par_id.bois_noir.proprietes.reserves.integrite.reserve
	var reserve_pierre_soleil: float = par_id.pierre_soleil.proprietes.reserves.integrite.reserve
	var capacite: float = float(config.reserve_integrite_defaut.reserve)

	verif.v(reserve_bois_soleil < capacite, "chemin reel : bois_soleil doit avoir une reserve d'integrite strictement entamee apres 100s au soleil")
	verif.v(reserve_bois_noir == capacite, "chemin reel : bois_noir ne doit jamais perdre d'integrite, jamais eclaire")
	verif.v(reserve_pierre_soleil == capacite, "chemin reel : pierre_soleil, biodegradabilite 0.0, ne doit jamais perdre d'integrite malgre la meme exposition que bois_soleil")

	# Soleil coupe : la reserve deja entamee de bois_soleil ne doit plus bouger.
	var reserve_avant_coupure: float = reserve_bois_soleil
	for i in 50:
		BancPhoto.avancer(objets, [], delta, config, catalogue_lumiere)
	verif.v(par_id.bois_soleil.proprietes.reserves.integrite.reserve == reserve_avant_coupure, "chemin reel : soleil coupe, la reserve de bois_soleil ne doit plus decroitre du tout")
