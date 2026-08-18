extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_senescence.gd
#
# Verrouille scripts/senescence.gd comme mecanisme GENERIQUE d'horloge
# d'age -- pas un code de colon. Domaine hors Orion : entite nommee
# "cristal_gravitique_1", meme famille de vocabulaire que
# test_lien_personnel.gd/test_deformation.gd, sans rapport avec le feu ni
# la genetique du colon.
#
# Fonction pure : aucune couche, aucun noeud, aucun rendu, aucun disque
# (pas de catalogue -- ce mecanisme n'en recoit aucun, contrairement a
# deformation.gd/lien_personnel.gd/epigenetique.gd).
#
# SECONDE MOITIE DU FICHIER (chantier « horloge du monde ») : le parametre
# FACULTATIF `horloge`. La LOI de calcul n'est pas verrouillee ici -- elle
# vit dans horloge.gd et est prouvee hors domaine par test_horloge.gd ; ce
# qui se verrouille ici est le CONTRAT D'ECRITURE de senescence.gd : quand
# les deux cles sont posees, quand elles ne le sont pas, et le fait que l'age
# avance TOUJOURS, horloge cassee ou non. Cycle de test hors domaine :
# "mue_prax"/"mue_velm"/"mue_tuor"/"mue_mibb", meme vocabulaire que
# test_horloge.gd, aucune saison d'Orion.

const Senescence = preload("res://scripts/senescence.gd")
const Horloge = preload("res://scripts/horloge.gd")
const Verif = preload("res://scripts/verif.gd")

const MUES := ["mue_prax", "mue_velm", "mue_tuor", "mue_mibb"]

func _init() -> void:
	var v := Verif.new()
	_avancer_incremente_age_selon_delta_et_facteur(v)
	_avancer_accumule_sur_plusieurs_appels(v)
	_facteur_nul_laisse_age_inchange(v)
	_avancer_alarme_sur_propriete_structurelle_absente(v)
	_resumabilite_json_stricte(v)

	_sans_horloge_rien_n_est_ecrit(v)
	_horloge_fournie_pose_les_deux_cles(v)
	_horloge_sans_saisons_ne_pose_que_l_heure(v)
	_horloge_incomplete_alarme_sans_rien_poser_mais_l_age_avance(v)
	_saisons_sans_jours_par_saison_alarme_apres_avoir_pose_l_heure(v)
	_l_horloge_est_mondiale_l_age_est_individuel(v)
	_resumabilite_json_stricte_avec_horloge(v)

	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: senescence.gd incremente l'age d'une entite selon un facteur d'echelle " +
			"et pose le temps du monde quand une horloge lui est fournie, " +
			"generique a tout domaine invente")
		quit(0)

func _entite(id: String, proprietes: Dictionary) -> Dictionary:
	return {"id": id, "position": Vector3.ZERO, "proprietes": proprietes}

func _avancer_incremente_age_selon_delta_et_facteur(v) -> void:
	var e := _entite("cristal_gravitique_1", {"age": 10.0})
	Senescence.avancer(e, 2.0, 0.5)
	v.v(is_equal_approx(e.proprietes.age, 11.0),
		"age doit s'incrementer exactement de delta * annees_par_seconde (2.0 * 0.5)")

func _avancer_accumule_sur_plusieurs_appels(v) -> void:
	var e := _entite("cristal_gravitique_2", {"age": 0.0})
	Senescence.avancer(e, 1.0, 1.0)
	Senescence.avancer(e, 1.0, 1.0)
	v.v(is_equal_approx(e.proprietes.age, 2.0),
		"plusieurs appels doivent accumuler l'age, jamais le remplacer")

func _facteur_nul_laisse_age_inchange(v) -> void:
	var e := _entite("cristal_gravitique_3", {"age": 5.0})
	Senescence.avancer(e, 100.0, 0.0)
	v.v(e.proprietes.age == 5.0,
		"un annees_par_seconde nul ne doit jamais faire vieillir, meme sur un grand delta")

func _avancer_alarme_sur_propriete_structurelle_absente(v) -> void:
	var e := _entite("cristal_gravitique_4", {})
	Senescence.avancer(e, 1.0, 1.0)
	v.v(not e.proprietes.has("age"),
		"proprietes sans la cle structurelle 'age' ne doit rien ecrire (alarme, pas defaut silencieux)")

func _resumabilite_json_stricte(v) -> void:
	var e := {
		"id": "cristal_gravitique_5",
		"position": {"x": 1.0, "y": 0.0, "z": 2.0},
		"proprietes": {"age": 0.0},
	}
	Senescence.avancer(e, 10.0, 0.1)
	var texte := JSON.stringify(e)
	var relu: Variant = JSON.parse_string(texte)
	v.v(relu != null, "JSON.stringify puis parse_string doit reussir sans erreur")
	v.v(is_equal_approx(relu.proprietes.age, e.proprietes.age),
		"age doit survivre identique a l'aller-retour JSON")

# ---------------------------------------------------------------------------
# Le temps du monde (parametre FACULTATIF `horloge`, chantier « horloge du
# monde »). `duree_jour_secondes` est pose EGAL a `heures_par_jour` partout
# ci-dessous : une heure du monde dure alors une seconde reelle, et
# temps_ecoule se lit directement en HEURES.
# ---------------------------------------------------------------------------

func _horloge(temps_ecoule: float) -> Dictionary:
	return {
		"temps_ecoule": temps_ecoule,
		"duree_jour_secondes": 24.0,
		"heures_par_jour": 24.0,
		"heure_depart": 0.0,
		"jours_par_saison": 5.0,
		"saisons": MUES,
	}

func _sans_horloge_rien_n_est_ecrit(v) -> void:
	# NON-REGRESSION : c'est exactement le chemin des trois appelants
	# existants (banc_reproduction.gd, banc_succession.gd,
	# banc_simulation_acceleree.gd), qui ne passent pas le parametre.
	var e := _entite("cristal_gravitique_6", {"age": 1.0})
	Senescence.avancer(e, 2.0, 3.0)
	v.v(is_equal_approx(e.proprietes.age, 7.0),
		"sans horloge, l'age doit avancer exactement comme avant ce chantier")
	v.v(not e.proprietes.has("heure_courante"),
		"sans horloge, heure_courante ne doit JAMAIS etre posee")
	v.v(not e.proprietes.has("saison"),
		"sans horloge, saison ne doit JAMAIS etre posee")
	# Un Dictionary vide passe explicitement doit valoir exactement l'absence.
	var e2 := _entite("cristal_gravitique_7", {"age": 1.0})
	Senescence.avancer(e2, 2.0, 3.0, {})
	v.v(e2.proprietes.size() == 1 and is_equal_approx(e2.proprietes.age, 7.0),
		"une horloge VIDE doit valoir exactement l'absence d'horloge, aucune cle de plus")

func _horloge_fournie_pose_les_deux_cles(v) -> void:
	var e := _entite("cristal_gravitique_8", {"age": 0.0})
	var h := _horloge(31.0)  # 31 h ecoulees = 1,29 jour -> 7 h du matin
	Senescence.avancer(e, 1.0, 1.0, h)
	v.v(is_equal_approx(e.proprietes.age, 1.0),
		"l'age doit avancer normalement quand une horloge est fournie")
	v.v(is_equal_approx(e.proprietes.heure_courante, Horloge.heure(31.0, 24.0, 24.0, 0.0)),
		"heure_courante doit valoir exactement ce que rend Horloge.heure, jamais un second calcul")
	v.v(is_equal_approx(e.proprietes.heure_courante, 7.0),
		"31 h ecoulees sur des jours de 24 h doivent poser heure_courante = 7.0")
	v.v(e.proprietes.saison == Horloge.saison(31.0, 24.0, 5.0, MUES),
		"saison doit valoir exactement ce que rend Horloge.saison, jamais un second calcul")
	v.v(e.proprietes.saison == MUES[0],
		"31 h = 1,29 jour, sous les 5 jours par saison : encore la premiere saison declaree")
	# La saison bascule bien, elle, une fois les 5 jours passes.
	var e_tard := _entite("cristal_gravitique_8b", {"age": 0.0})
	Senescence.avancer(e_tard, 1.0, 1.0, _horloge(24.0 * 7.0))
	v.v(e_tard.proprietes.saison == MUES[1],
		"apres 7 jours (jours_par_saison = 5), la saison doit avoir bascule sur la deuxieme")

func _horloge_sans_saisons_ne_pose_que_l_heure(v) -> void:
	var e := _entite("cristal_gravitique_9", {"age": 0.0})
	var h := _horloge(10.0)
	h.erase("saisons")
	h.erase("jours_par_saison")
	Senescence.avancer(e, 1.0, 1.0, h)
	v.v(e.proprietes.has("heure_courante"),
		"une horloge sans saisons doit tout de meme poser l'heure")
	v.v(not e.proprietes.has("saison"),
		"un monde sans saison declaree ne doit JAMAIS porter la cle saison (absence legitime)")
	# Un Array de saisons VIDE doit valoir exactement l'absence de la cle.
	var e2 := _entite("cristal_gravitique_10", {"age": 0.0})
	var h2 := _horloge(10.0)
	h2["saisons"] = []
	Senescence.avancer(e2, 1.0, 1.0, h2)
	v.v(e2.proprietes.has("heure_courante") and not e2.proprietes.has("saison"),
		"un Array de saisons VIDE doit valoir exactement l'absence de la cle, sans alarme")

func _horloge_incomplete_alarme_sans_rien_poser_mais_l_age_avance(v) -> void:
	for cle in ["temps_ecoule", "duree_jour_secondes", "heures_par_jour"]:
		var e := _entite("cristal_gravitique_11", {"age": 2.0})
		var h := _horloge(10.0)
		h.erase(cle)
		Senescence.avancer(e, 1.0, 1.0, h)
		v.v(is_equal_approx(e.proprietes.age, 3.0),
			"une horloge cassee (cle '%s' absente) ne doit JAMAIS priver l'entite de son vieillissement" % cle)
		v.v(not e.proprietes.has("heure_courante") and not e.proprietes.has("saison"),
			"cle structurelle '%s' absente : alarme, et AUCUNE des deux cles d'horloge posee" % cle)

func _saisons_sans_jours_par_saison_alarme_apres_avoir_pose_l_heure(v) -> void:
	var e := _entite("cristal_gravitique_12", {"age": 0.0})
	var h := _horloge(10.0)
	h.erase("jours_par_saison")
	Senescence.avancer(e, 1.0, 1.0, h)
	v.v(e.proprietes.has("heure_courante"),
		"le couple saisons/jours_par_saison ne doit pas empecher l'heure, deja posee")
	v.v(not e.proprietes.has("saison"),
		"saisons peuplee SANS jours_par_saison : alarme (le cas du couple), saison jamais posee")

func _l_horloge_est_mondiale_l_age_est_individuel(v) -> void:
	# Deux entites d'ages differents recoivent LA MEME horloge (ce que fait un
	# cablage : une seule construction par tick, passee a chaque appel).
	var jeune := _entite("cristal_gravitique_13", {"age": 0.0})
	var vieux := _entite("cristal_gravitique_14", {"age": 400.0})
	var h := _horloge(77.0)
	Senescence.avancer(jeune, 1.0, 1.0, h)
	Senescence.avancer(vieux, 1.0, 1.0, h)
	v.v(is_equal_approx(jeune.proprietes.heure_courante, vieux.proprietes.heure_courante)
			and jeune.proprietes.saison == vieux.proprietes.saison,
		"le temps du monde doit etre IDENTIQUE pour toutes les entites du meme tick")
	v.v(not is_equal_approx(jeune.proprietes.age, vieux.proprietes.age),
		"l'age doit rester INDIVIDUEL : deux horloges disjointes, jamais reliees")

func _resumabilite_json_stricte_avec_horloge(v) -> void:
	var e := {
		"id": "cristal_gravitique_15",
		"position": {"x": 0.0, "y": 0.0, "z": 0.0},
		"proprietes": {"age": 0.0},
	}
	Senescence.avancer(e, 10.0, 0.1, _horloge(37.5))
	var relu: Variant = JSON.parse_string(JSON.stringify(e))
	v.v(relu != null, "une entite portant le temps du monde doit survivre a l'aller-retour JSON")
	v.v(is_equal_approx(relu.proprietes.heure_courante, e.proprietes.heure_courante),
		"heure_courante est un float nu, il doit survivre identique a l'aller-retour JSON")
	v.v(relu.proprietes.saison == e.proprietes.saison,
		"saison est une String nue, elle doit survivre identique a l'aller-retour JSON")
