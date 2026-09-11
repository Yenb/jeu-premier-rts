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
	_avancer_lot_equivaut_a_la_boucle_unitaire(v)
	_avancer_lot_saute_les_libres_et_ne_recule_pas(v)
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

# LOT : avancer_lot(ages, libres, stades_actuels_index, stades_config)
# doit rendre le meme index par entite que la boucle unitaire de
# `avancer` sur des entites paralleles. Domaine "cristal" pour la
# genericite.
func _avancer_lot_equivaut_a_la_boucle_unitaire(v) -> void:
	var stades_config: Array = _stades_config_invente()
	var noms: Array = ["", "cristal_dormant", "cristal_actif", "cristal_instable"]
	# 4 ages : 0.0 (au seuil 0), 5.0 (dormant), 15.0 (actif), 30.0 (instable).
	var ages_arr: Array = [0.0, 5.0, 15.0, 30.0]
	# Etat initial : tous au stade -1 (aucun stade encore atteint).
	var entites: Array = []
	for i in range(ages_arr.size()):
		entites.append(_entite("cristal_%d" % i, ages_arr[i], "", stades_config))
	for i in range(entites.size()):
		Stade.avancer(entites[i])
	# Essai lot : colonnes paralleles.
	var ages: PackedFloat32Array = PackedFloat32Array(ages_arr)
	var libres: PackedByteArray = PackedByteArray()
	libres.resize(ages.size())
	for i in range(libres.size()):
		libres[i] = 0
	var index_courant: PackedInt32Array = PackedInt32Array()
	index_courant.resize(ages.size())
	for i in range(ages.size()):
		index_courant[i] = -1
	Stade.avancer_lot(ages, libres, index_courant, stades_config)
	for i in range(ages.size()):
		var nom_oracle: String = entites[i].proprietes.get("stade", "")
		var index_oracle: int = noms.find(nom_oracle) - 1  # noms[0] = "" -> -1
		v.v(index_courant[i] == index_oracle,
			"avancer_lot doit donner le meme index que la boucle unitaire (i=%d : lot=%d oracle=%d nom_oracle=%s)" % [i, index_courant[i], index_oracle, nom_oracle])

# Slots libres : index_courant inchange. Pas de recul (si age chute, on ne
# revient jamais en arriere -- meme regle que le port unitaire).
func _avancer_lot_saute_les_libres_et_ne_recule_pas(v) -> void:
	var stades_config: Array = _stades_config_invente()
	var ages: PackedFloat32Array = PackedFloat32Array([5.0, 30.0, 0.0])
	var libres: PackedByteArray = PackedByteArray([0, 1, 0])
	# Entite 2 : deja au stade 2 (instable), age 0 -> ne doit PAS reculer.
	var index_courant: PackedInt32Array = PackedInt32Array([-1, 0, 2])
	Stade.avancer_lot(ages, libres, index_courant, stades_config)
	v.v(index_courant[0] == 0, "vivant 0 doit avancer au stade 0 (age 5 sous 10)")
	v.v(index_courant[1] == 0, "libre 1 ne doit PAS bouger (recu %d)" % index_courant[1])
	v.v(index_courant[2] == 2, "vivant 2 doit rester au stade 2 (jamais reculer, recu %d)" % index_courant[2])
