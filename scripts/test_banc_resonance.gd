extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_resonance.gd
#
# Verrouille le cablage de banc_resonance.gd -- chantier « resonance -- un
# materiau resonnant amplifie le son » :
# 1. son_recu (RECOPIEE de banc_fracture_sonore.gd:intensite_recue) -- nulle
#    hors du rayon d'emission, attenuee lineairement dans le rayon ;
# 2. diagnostic_objet/sources_resonantes -- source coupee ou resonance
#    absente/nulle : AUCUNE source secondaire, jamais une force nulle posee ;
#    resonance haute produit un son reemis strictement plus fort que
#    resonance basse, a son_recu egal ;
# 3. sources_actives -- source coupee : rien, ni originale ni secondaire ;
# 4. le colon (Perception.percevoir, INCHANGE) percoit la source originale
#    ET les sources secondaires, jamais l'une sans l'autre ;
# 5. chemin reel (data/banc_resonance.json + materiaux.json +
#    proprietes_immuables_composition.json + types.json) : le son total
#    percu par le colon est strictement plus fort avec les objets
#    resonnants qu'avec la seule source, fer/pierre (memes distances a la
#    source ET au colon, seule resonance diverge) isolent resonance comme
#    seule variable.
#
# AUCUN MECANISME DU COEUR TOUCHE par ce chantier : perception.gd/
# etat_effectif.gd/charge.gd/lumiere.gd/temperature.gd/frappe.gd/
# seuil_etat.gd/banc_son.gd restent exactement ceux deja verrouilles par
# leurs propres tests -- ce fichier verrouille uniquement banc_resonance.gd.

const BancResonance = preload("res://scripts/banc_resonance.gd")
const Monde = preload("res://scripts/monde.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

func _init() -> void:
	_son_recu_nulle_hors_de_portee()
	_son_recu_attenuee_lineairement()
	_son_recu_zero_si_rayon_emission_nul()

	_diagnostic_source_coupee_donne_zero()
	_diagnostic_resonance_absente_donne_zero_reemis()

	_sources_resonantes_ignore_resonance_nulle()
	_sources_resonantes_ignore_hors_de_portee()
	_sources_resonantes_force_proportionnelle_a_resonance()

	_sources_actives_source_coupee_rend_vide()
	_sources_actives_contient_originale_et_secondaires()

	_intensite_attenuee_hors_portee_nulle()
	_son_total_percu_ne_somme_que_les_entendus()

	_hors_domaine_un_recepteur_sans_rapport_avec_le_son()

	_chemin_reel_fabrication_fusionne_resonance()
	_chemin_reel_sans_source_aucune_resonance()
	_chemin_reel_objet_resonance_nulle_n_amplifie_rien()
	_chemin_reel_colon_percoit_source_et_secondaires()
	_chemin_reel_colon_percoit_plus_fort_avec_objets_resonnants()
	_chemin_reel_resonance_haute_amplifie_plus_que_basse()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: banc_resonance.gd -- un objet resonnant reemet le son recu de la source " +
		"proportionnellement a sa resonance, aucune source secondaire sans son recu ni sans " +
		"resonance, source coupee = aucune resonance, le colon percoit la source originale ET " +
		"les sources secondaires, chemin reel (data/banc_resonance.json + materiaux.json + " +
		"proprietes_immuables_composition.json) : le son total percu est strictement plus fort " +
		"avec des objets resonnants qu'avec la seule source, une resonance haute amplifie plus " +
		"qu'une resonance basse a distance egale")
	quit(0)

# ---- Fixtures : chargement disque ----

func _charger(chemin: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))

func _config() -> Dictionary:
	return _charger("res://data/banc_resonance.json")

func _materiaux() -> Dictionary:
	return _charger("res://data/materiaux.json")

func _proprietes_immuables() -> Array:
	return _charger("res://data/proprietes_immuables_composition.json").get("proprietes", [])

func _objet_physique() -> Dictionary:
	return _charger("res://data/types.json").get("objet_physique", {})

func _catalogue_types() -> Dictionary:
	return _charger("res://data/types.json")

func _catalogue_canaux() -> Dictionary:
	return _charger("res://data/canaux.json")

func _objets_reels() -> Array:
	var config := _config()
	return BancResonance.fabriquer_objets_resonnants(config.objets, _objet_physique(), _materiaux(), _proprietes_immuables())

func _colon_reel() -> Dictionary:
	var BancCommun = preload("res://scripts/banc_commun.gd")
	var config := _config()
	return BancCommun.fabriquer_colon("colon", "colon", config.colon, _catalogue_types())

func _par_id(objets: Array, id: String) -> Dictionary:
	for objet in objets:
		if objet.id == id:
			return objet
	return {}

# Meme geste que _process/_rafraichir_tout : construit un Monde jetable
# avec les sources du tick, rend { ids_entendus (tries), total } -- fonction
# de test seule, PAS une copie de banc_resonance.gd (elle appelle les
# fonctions statiques du banc, jamais ne reimplemente leur logique).
func _percevoir(colon: Dictionary, sources: Array, catalogue_canaux: Dictionary) -> Dictionary:
	var monde := Monde.new()
	for source in sources:
		monde.ajouter(source, "source_sonore", source.position)
	var entendus := BancResonance.captures_ouie(colon, monde, catalogue_canaux)
	var ids := BancResonance.ids_de(entendus)
	ids.sort()
	var total := BancResonance.son_total_percu(colon, sources, ids)
	return {"ids": ids, "total": total}

# ---- son_recu, pure ----

func _son_recu_nulle_hors_de_portee() -> void:
	var recu := BancResonance.son_recu(Vector3(1000.0, 0.0, 0.0), Vector3.ZERO, 1.0, 500.0)
	verif.v(recu == 0.0, "hors du rayon d'emission (1000 > 500) : son_recu doit etre nul")

func _son_recu_attenuee_lineairement() -> void:
	var recu := BancResonance.son_recu(Vector3(50.0, 0.0, 0.0), Vector3.ZERO, 1.0, 100.0)
	verif.v(is_equal_approx(recu, 0.5), "a mi-portee (50/100), son_recu doit valoir exactement son_emis_source * 0.5")

func _son_recu_zero_si_rayon_emission_nul() -> void:
	var recu := BancResonance.son_recu(Vector3.ZERO, Vector3.ZERO, 1.0, 0.0)
	verif.v(recu == 0.0, "rayon_emission nul : son_recu doit etre nul, jamais une division par zero")

# ---- diagnostic_objet, pure ----

func _diagnostic_source_coupee_donne_zero() -> void:
	var objet := {"id": "a", "position": Vector3(50.0, 0.0, 0.0), "proprietes": {"resonance": 0.9}}
	var diag := BancResonance.diagnostic_objet(objet, false, Vector3.ZERO, 1.0, 100.0)
	verif.v(diag.son_recu == 0.0, "source coupee : son_recu doit etre nul meme a portee")
	verif.v(diag.son_reemis == 0.0, "source coupee : son_reemis doit etre nul, resonance haute ou non")
	verif.v(is_equal_approx(diag.resonance, 0.9), "diagnostic_objet doit quand meme rapporter la resonance de l'objet")

func _diagnostic_resonance_absente_donne_zero_reemis() -> void:
	var objet := {"id": "a", "position": Vector3(50.0, 0.0, 0.0), "proprietes": {}}
	var diag := BancResonance.diagnostic_objet(objet, true, Vector3.ZERO, 1.0, 100.0)
	verif.v(diag.son_recu > 0.0, "l'objet est a portee et recoit du son de la source")
	verif.v(diag.son_reemis == 0.0, "'resonance' absente (defaut 0.0) : son_reemis doit rester nul malgre un son_recu positif")

# ---- sources_resonantes, pure ----

func _sources_resonantes_ignore_resonance_nulle() -> void:
	var objets := [{"id": "verre", "position": Vector3(50.0, 0.0, 0.0), "proprietes": {"resonance": 0.0}}]
	var sources := BancResonance.sources_resonantes(objets, true, Vector3.ZERO, 1.0, 100.0)
	verif.v(sources.is_empty(), "un objet a resonance 0.0 ne doit jamais produire de source secondaire")

func _sources_resonantes_ignore_hors_de_portee() -> void:
	var objets := [{"id": "loin", "position": Vector3(500.0, 0.0, 0.0), "proprietes": {"resonance": 0.9}}]
	var sources := BancResonance.sources_resonantes(objets, true, Vector3.ZERO, 1.0, 100.0)
	verif.v(sources.is_empty(), "un objet hors du rayon d'emission ne doit jamais produire de source secondaire, meme a resonance haute")

func _sources_resonantes_force_proportionnelle_a_resonance() -> void:
	var objets := [
		{"id": "haute", "position": Vector3(50.0, 0.0, 0.0), "proprietes": {"resonance": 0.7}},
		{"id": "basse", "position": Vector3(50.0, 0.0, 0.0), "proprietes": {"resonance": 0.2}},
	]
	var sources := BancResonance.sources_resonantes(objets, true, Vector3.ZERO, 1.0, 100.0)
	verif.v(sources.size() == 2, "les deux objets, meme distance de la source, doivent produire chacun une source secondaire")
	var par_id: Dictionary = {}
	for source in sources:
		par_id[source.id] = source
	var force_haute: float = par_id["haute_reso"].proprietes.son_emis
	var force_basse: float = par_id["basse_reso"].proprietes.son_emis
	verif.v(force_haute > force_basse, "a son_recu egal (meme distance), une resonance plus haute doit produire une source secondaire plus forte")
	verif.v(is_equal_approx(force_haute / force_basse, 0.7 / 0.2), "le rapport des forces doit egaler exactement le rapport des resonances (0.7/0.2), a son_recu egal")

# ---- sources_actives ----

func _sources_actives_source_coupee_rend_vide() -> void:
	var objets := [{"id": "a", "position": Vector3(50.0, 0.0, 0.0), "proprietes": {"resonance": 0.9}}]
	var sources := BancResonance.sources_actives(false, "source", Vector3.ZERO, 1.0, 100.0, objets)
	verif.v(sources.is_empty(), "source coupee : sources_actives doit rendre un Array vide, ni originale ni secondaire")

func _sources_actives_contient_originale_et_secondaires() -> void:
	var objets := [{"id": "a", "position": Vector3(50.0, 0.0, 0.0), "proprietes": {"resonance": 0.9}}]
	var sources := BancResonance.sources_actives(true, "source", Vector3.ZERO, 1.0, 100.0, objets)
	verif.v(sources.size() == 2, "source active avec un objet resonnant a portee : doit rendre la source originale PLUS une secondaire")
	var ids: Array = []
	for source in sources:
		ids.append(source.id)
	verif.v(ids.has("source"), "la source originale doit garder son propre id")
	verif.v(ids.has("a_reso"), "la source secondaire doit exister sous un id derive de l'objet resonnant")

# ---- intensite_attenuee / son_total_percu, pures ----

func _intensite_attenuee_hors_portee_nulle() -> void:
	verif.v(BancResonance.intensite_attenuee(1.0, 10.0, 0.0) == 0.0, "portee nulle : intensite_attenuee doit rendre 0.0, jamais une division par zero")

func _son_total_percu_ne_somme_que_les_entendus() -> void:
	var colon := {"position": Vector3.ZERO, "proprietes": {"canaux_config": {"ouie": {"portee": 100.0, "sensibilite": 1.0}}}}
	var sources := [
		{"id": "entendue", "position": Vector3(10.0, 0.0, 0.0), "proprietes": {"son_emis": 1.0}},
		{"id": "ignoree", "position": Vector3(90.0, 0.0, 0.0), "proprietes": {"son_emis": 1.0}},
	]
	var total_une_seule := BancResonance.son_total_percu(colon, sources, ["entendue"])
	var total_les_deux := BancResonance.son_total_percu(colon, sources, ["entendue", "ignoree"])
	verif.v(total_les_deux > total_une_seule, "une source supplementaire dans ids_entendus doit augmenter le total")
	verif.v(is_equal_approx(total_une_seule, 1.0 * (1.0 - 10.0 / 100.0)), "le total sur une seule source entendue doit egaler exactement son intensite attenuee")

# ---- Hors domaine : un recepteur/une source sans rapport avec le son ----

func _hors_domaine_un_recepteur_sans_rapport_avec_le_son() -> void:
	# "vibration_sismique"/"amplification_sismique" -- meme mecanique
	# (son_recu/sources_resonantes ignorent totalement le nom du domaine),
	# preuve que ce fichier ne connait ni le son ni la resonance acoustique.
	var recepteurs := [{"id": "capteur_sismique", "position": Vector3(30.0, 0.0, 0.0), "proprietes": {"resonance": 0.5}}]
	var sources := BancResonance.sources_resonantes(recepteurs, true, Vector3.ZERO, 2.0, 100.0)
	verif.v(sources.size() == 1, "le mecanisme doit traiter un recepteur sismique exactement comme un objet resonnant sonore")
	verif.v(sources[0].proprietes.son_emis > 0.0, "un recepteur sismique a portee, avec resonance positive, doit produire une source secondaire non nulle")

# ---- Chemin REEL ----

func _chemin_reel_fabrication_fusionne_resonance() -> void:
	var objets := _objets_reels()
	var fer := _par_id(objets, "fer_resonant")
	var bois := _par_id(objets, "bois_resonant")
	var pierre := _par_id(objets, "pierre_resonant")
	verif.v(not fer.is_empty() and not bois.is_empty() and not pierre.is_empty(), "chemin reel : les trois objets resonnants doivent exister")
	verif.v(is_equal_approx(fer.proprietes.resonance, 0.6), "chemin reel : fer_resonant doit fusionner resonance=0.6 depuis materiaux.json")
	verif.v(is_equal_approx(bois.proprietes.resonance, 0.7), "chemin reel : bois_resonant doit fusionner resonance=0.7 depuis materiaux.json")
	verif.v(is_equal_approx(pierre.proprietes.resonance, 0.2), "chemin reel : pierre_resonant doit fusionner resonance=0.2 depuis materiaux.json")

func _chemin_reel_sans_source_aucune_resonance() -> void:
	var config := _config()
	var objets := _objets_reels()
	var pos_source: Array = config.source.position
	var position_source := Vector3(pos_source[0], pos_source[1], pos_source[2])
	var sources := BancResonance.sources_actives(false, config.source.id, position_source, config.source.son_emis, config.source.rayon_emission, objets)
	verif.v(sources.is_empty(), "chemin reel, source coupee : aucune source active, ni originale ni resonnante")

func _chemin_reel_objet_resonance_nulle_n_amplifie_rien() -> void:
	var config := _config()
	var objets := _objets_reels()
	var pierre := _par_id(objets, "pierre_resonant")
	pierre.proprietes.resonance = 0.0
	var pos_source: Array = config.source.position
	var position_source := Vector3(pos_source[0], pos_source[1], pos_source[2])
	var sources := BancResonance.sources_resonantes([pierre], true, position_source, config.source.son_emis, config.source.rayon_emission)
	verif.v(sources.is_empty(), "chemin reel : un objet reel force a resonance 0.0 ne doit produire aucune source secondaire")

func _chemin_reel_colon_percoit_source_et_secondaires() -> void:
	var config := _config()
	var objets := _objets_reels()
	var colon := _colon_reel()
	var pos_source: Array = config.source.position
	var position_source := Vector3(pos_source[0], pos_source[1], pos_source[2])
	var sources := BancResonance.sources_actives(true, config.source.id, position_source, config.source.son_emis, config.source.rayon_emission, objets)
	var resultat := _percevoir(colon, sources, _catalogue_canaux())
	verif.v(resultat.ids.has(config.source.id), "chemin reel : le colon doit percevoir la source originale")
	verif.v(resultat.ids.has("fer_resonant_reso"), "chemin reel : le colon doit percevoir la source secondaire du fer")
	verif.v(resultat.ids.has("bois_resonant_reso"), "chemin reel : le colon doit percevoir la source secondaire du bois")
	verif.v(resultat.ids.has("pierre_resonant_reso"), "chemin reel : le colon doit percevoir la source secondaire de la pierre")

func _chemin_reel_colon_percoit_plus_fort_avec_objets_resonnants() -> void:
	var config := _config()
	var objets := _objets_reels()
	var colon := _colon_reel()
	var pos_source: Array = config.source.position
	var position_source := Vector3(pos_source[0], pos_source[1], pos_source[2])
	var catalogue_canaux := _catalogue_canaux()

	var sources_sans := BancResonance.sources_actives(true, config.source.id, position_source, config.source.son_emis, config.source.rayon_emission, [])
	var total_sans: float = _percevoir(colon, sources_sans, catalogue_canaux).total

	var sources_avec := BancResonance.sources_actives(true, config.source.id, position_source, config.source.son_emis, config.source.rayon_emission, objets)
	var total_avec: float = _percevoir(colon, sources_avec, catalogue_canaux).total

	verif.v(total_avec > total_sans, "chemin reel : le son total percu par le colon doit etre strictement plus fort avec les objets resonnants entre la source et lui qu'avec la source seule")

func _chemin_reel_resonance_haute_amplifie_plus_que_basse() -> void:
	# fer_resonant (resonance 0.6) et pierre_resonant (resonance 0.2) sont
	# geometriquement SYMETRIQUES dans data/banc_resonance.json -- MEME
	# distance a la source ET au colon -- resonance est donc la SEULE
	# variable qui peut expliquer un ecart de contribution au son total.
	var config := _config()
	var objets := _objets_reels()
	var colon := _colon_reel()
	var pos_source: Array = config.source.position
	var position_source := Vector3(pos_source[0], pos_source[1], pos_source[2])
	var fer := _par_id(objets, "fer_resonant")
	var pierre := _par_id(objets, "pierre_resonant")
	verif.v(is_equal_approx(fer.position.distance_to(position_source), pierre.position.distance_to(position_source)),
		"chemin reel : fer_resonant et pierre_resonant doivent etre a la MEME distance de la source (isolation de la variable resonance)")
	verif.v(is_equal_approx(fer.position.distance_to(colon.position), pierre.position.distance_to(colon.position)),
		"chemin reel : fer_resonant et pierre_resonant doivent etre a la MEME distance du colon (isolation de la variable resonance)")

	var sources_fer := BancResonance.sources_actives(true, config.source.id, position_source, config.source.son_emis, config.source.rayon_emission, [fer])
	var sources_pierre := BancResonance.sources_actives(true, config.source.id, position_source, config.source.son_emis, config.source.rayon_emission, [pierre])
	var resultat_fer := _percevoir(colon, sources_fer, _catalogue_canaux())
	var resultat_pierre := _percevoir(colon, sources_pierre, _catalogue_canaux())
	verif.v(resultat_fer.total > resultat_pierre.total,
		"chemin reel : a distances identiques, le fer (resonance 0.6) doit produire un son total percu strictement plus fort que la pierre (resonance 0.2)")
