extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_stade.gd
#
# Verrouille scripts/stade.gd comme mecanisme GENERIQUE d'avancement de
# stade de vie -- pas un code de colon/papillon/arbre. Domaine hors Orion :
# entite "cristal_N", stades inventes (cristal_dormant/cristal_actif/
# cristal_instable), meme famille de vocabulaire que test_senescence.gd/
# test_deformation.gd, sans rapport avec le feu ni la genetique du colon.
#
# Fonction pure : aucune couche, aucun noeud, aucun rendu, aucun disque
# (pas de catalogue -- ce mecanisme n'en recoit aucun, la table des stades
# vit deja sur l'entite, voir l'en-tete de stade.gd).

const Stade = preload("res://scripts/stade.gd")
const Verif = preload("res://scripts/verif.gd")

func _init() -> void:
	var v := Verif.new()
	_avance_au_premier_seuil_franchi_des_la_naissance(v)
	_avance_au_stade_suivant_quand_age_depasse_son_seuil(v)
	_reste_inchange_sous_le_premier_seuil(v)
	_ne_recule_jamais_meme_si_lage_resoudrait_un_stade_anterieur(v)
	_stades_config_vide_ne_change_rien(v)
	_alarme_sur_age_absent(v)
	_alarme_sur_stades_config_absent(v)
	_resumabilite_json_stricte(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: stade.gd avance le stade de vie d'une entite selon son age, " +
			"generique a tout domaine invente")
		quit(0)

func _stades_config_invente() -> Array:
	return [
		{ "nom": "cristal_dormant", "age_seuil": 0.0 },
		{ "nom": "cristal_actif", "age_seuil": 10.0 },
		{ "nom": "cristal_instable", "age_seuil": 25.0 },
	]

func _entite(id: String, age: float, stade: String, stades_config: Array) -> Dictionary:
	return {
		"id": id,
		"position": Vector3.ZERO,
		"proprietes": { "age": age, "stade": stade, "stades_config": stades_config },
	}

func _avance_au_premier_seuil_franchi_des_la_naissance(v) -> void:
	var e := _entite("cristal_1", 0.0, "", _stades_config_invente())
	Stade.avancer(e)
	v.v(e.proprietes.stade == "cristal_dormant",
		"a age_seuil 0.0 franchi des la naissance, le stade doit devenir cristal_dormant")

func _avance_au_stade_suivant_quand_age_depasse_son_seuil(v) -> void:
	var e := _entite("cristal_2", 12.0, "cristal_dormant", _stades_config_invente())
	Stade.avancer(e)
	v.v(e.proprietes.stade == "cristal_actif",
		"un age de 12.0 doit faire avancer le stade jusqu'a cristal_actif (seuil 10.0)")

func _reste_inchange_sous_le_premier_seuil(v) -> void:
	var config := [
		{ "nom": "cristal_dormant", "age_seuil": 5.0 },
		{ "nom": "cristal_actif", "age_seuil": 10.0 },
	]
	var e := _entite("cristal_3", 2.0, "", config)
	Stade.avancer(e)
	v.v(e.proprietes.stade == "",
		"sous le premier seuil, le stade doit rester inchange (aucun index trouve)")

func _ne_recule_jamais_meme_si_lage_resoudrait_un_stade_anterieur(v) -> void:
	var e := _entite("cristal_4", 2.0, "cristal_instable", _stades_config_invente())
	Stade.avancer(e)
	v.v(e.proprietes.stade == "cristal_instable",
		"un age qui resoudrait un index anterieur au stade deja atteint ne doit jamais le faire reculer")

func _stades_config_vide_ne_change_rien(v) -> void:
	var e := _entite("cristal_5", 50.0, "", [])
	Stade.avancer(e)
	v.v(e.proprietes.stade == "",
		"stades_config vide est un point neutre legitime : aucune ecriture, aucune alarme")

func _alarme_sur_age_absent(v) -> void:
	var e := {
		"id": "cristal_6",
		"position": Vector3.ZERO,
		"proprietes": { "stade": "", "stades_config": _stades_config_invente() },
	}
	Stade.avancer(e)
	v.v(not e.proprietes.has("age"),
		"proprietes sans la cle structurelle 'age' ne doit rien ecrire (alarme, pas defaut silencieux)")

func _alarme_sur_stades_config_absent(v) -> void:
	var e := {
		"id": "cristal_7",
		"position": Vector3.ZERO,
		"proprietes": { "age": 30.0, "stade": "" },
	}
	Stade.avancer(e)
	v.v(not e.proprietes.has("stades_config"),
		"proprietes sans la cle structurelle 'stades_config' ne doit rien ecrire (alarme, pas defaut silencieux)")
	v.v(e.proprietes.stade == "",
		"sans stades_config, stade ne doit jamais etre invente")

func _resumabilite_json_stricte(v) -> void:
	var e := {
		"id": "cristal_8",
		"position": { "x": 1.0, "y": 0.0, "z": 2.0 },
		"proprietes": { "age": 15.0, "stade": "", "stades_config": _stades_config_invente() },
	}
	Stade.avancer(e)
	var texte := JSON.stringify(e)
	var relu: Variant = JSON.parse_string(texte)
	v.v(relu != null, "JSON.stringify puis parse_string doit reussir sans erreur")
	v.v(relu.proprietes.stade == e.proprietes.stade,
		"stade doit survivre identique a l'aller-retour JSON")
