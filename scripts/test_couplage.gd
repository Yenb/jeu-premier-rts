extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_couplage.gd
#
# Verrouille scripts/couplage.gd comme mecanisme GENERIQUE de couplage
# physique entre ticks -- pas un code de colon ni d'animal. Aucune chose
# du dépot (colon, feu, bloc, animal, reserve) n'apparait ici : une
# entite et une cible inventees, une regle inventee, un catalogue
# inventé. Ce test prouve que poser/avancer/retirer traversent le meme
# code quel que soit le domaine.
#
# Fonction pure : aucune couche, aucun noeud, aucun rendu, aucun disque
# (le catalogue est un Dictionary construit ici, jamais data/engagements.json).

const Couplage = preload("res://scripts/couplage.gd")
const Verif = preload("res://scripts/verif.gd")

func _init() -> void:
	var v := Verif.new()
	_poser_ecrit_l_engagement_depuis_la_regle(v)
	_avancer_vide_si_aucun_engagement(v)
	_avancer_garde_tant_que_la_valeur_reste_au_dessus_du_seuil(v)
	_avancer_satisfait_et_retire_quand_la_valeur_passe_sous_le_seuil(v)
	_avancer_arrache_et_retire_quand_la_cible_disparait(v)
	_retirer_remet_a_null_quelle_que_soit_la_raison(v)
	_regle_absente_du_catalogue_alarme(v)
	_propriete_structurelle_absente_alarme(v)
	_contexte_parametre_le_chemin_de_satisfaction_par_canal(v)
	_valeur_cherchee_sur_l_entite_si_absente_de_la_cible(v)
	_sens_satisfaction_sur_seuil_inverse_la_comparaison(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: couplage.gd pose/avance/retire un couplage physique entite-cible par " +
			"regle de catalogue, generique a tout domaine invente")
		quit(0)

func _entite(id: String, proprietes: Dictionary) -> Dictionary:
	return {"id": id, "position": Vector3.ZERO, "proprietes": proprietes}

func _catalogue() -> Dictionary:
	return {
		"veille_cristal": {
			"poids": 6.0,
			"seuil_satisfait": 2.0,
			"seuil_bascule": 1.0,
			"satisfait_par": "energie_cristal",
			"arrache_par": "saillance_superieure_seuil",
		},
		"jauge_par_canal": {
			"poids": 3.0,
			"seuil_satisfait": 5.0,
			"seuil_bascule": 0.5,
			"satisfait_par": "jauges.{canal}.valeur",
			"arrache_par": "saillance_superieure_seuil",
		},
		"jauge_qui_recharge": {
			"poids": 4.0,
			"seuil_satisfait": 8.0,
			"seuil_bascule": 1.0,
			"sens_satisfaction": "sur_seuil",
			"satisfait_par": "energie_cristal",
			"arrache_par": "saillance_superieure_seuil",
		},
	}

func _poser_ecrit_l_engagement_depuis_la_regle(v) -> void:
	var sentinelle := _entite("sentinelle_1", {"engagement": null})
	var cristal := _entite("cristal_1", {"energie_cristal": 9.0})
	Couplage.poser(sentinelle, cristal, "veille_cristal", _catalogue())
	var e: Dictionary = sentinelle.proprietes.engagement
	v.v(e.cible_id == "cristal_1", "poser doit ecrire l'id de la cible")
	v.v(e.regle_id == "veille_cristal", "poser doit ecrire le regle_id")
	v.v(e.poids == 6.0, "poser doit copier le poids depuis la regle")
	v.v(e.seuil_satisfait == 2.0, "poser doit copier seuil_satisfait depuis la regle")
	v.v(e.duree == 0.0, "poser doit initialiser duree a 0.0")

func _avancer_vide_si_aucun_engagement(v) -> void:
	var sentinelle := _entite("sentinelle_2", {"engagement": null})
	var resultat := Couplage.avancer(sentinelle, null, 1.0, _catalogue())
	v.v(resultat == "vide", "avancer sans engagement en cours doit rendre 'vide'")

func _avancer_garde_tant_que_la_valeur_reste_au_dessus_du_seuil(v) -> void:
	var sentinelle := _entite("sentinelle_3", {"engagement": null})
	var cristal := _entite("cristal_3", {"energie_cristal": 9.0})
	Couplage.poser(sentinelle, cristal, "veille_cristal", _catalogue())
	var resultat := Couplage.avancer(sentinelle, cristal, 0.5, _catalogue())
	v.v(resultat == "garde", "valeur au-dessus du seuil doit garder l'engagement")
	v.v(sentinelle.proprietes.engagement != null, "garder ne doit pas retirer l'engagement")
	v.v(sentinelle.proprietes.engagement.duree == 0.5, "garder doit accumuler duree de delta")

func _avancer_satisfait_et_retire_quand_la_valeur_passe_sous_le_seuil(v) -> void:
	var sentinelle := _entite("sentinelle_4", {"engagement": null})
	var cristal := _entite("cristal_4", {"energie_cristal": 9.0})
	Couplage.poser(sentinelle, cristal, "veille_cristal", _catalogue())
	cristal.proprietes.energie_cristal = 1.0
	var resultat := Couplage.avancer(sentinelle, cristal, 1.0, _catalogue())
	v.v(resultat == "satisfait", "valeur sous le seuil doit rendre 'satisfait'")
	v.v(sentinelle.proprietes.engagement == null, "satisfait doit retirer l'engagement")

func _avancer_arrache_et_retire_quand_la_cible_disparait(v) -> void:
	var sentinelle := _entite("sentinelle_5", {"engagement": null})
	var cristal := _entite("cristal_5", {"energie_cristal": 9.0})
	Couplage.poser(sentinelle, cristal, "veille_cristal", _catalogue())
	var resultat := Couplage.avancer(sentinelle, null, 1.0, _catalogue())
	v.v(resultat == "arrache", "cible absente (null) doit rendre 'arrache'")
	v.v(sentinelle.proprietes.engagement == null, "arrache doit retirer l'engagement")

func _retirer_remet_a_null_quelle_que_soit_la_raison(v) -> void:
	var sentinelle := _entite("sentinelle_6", {"engagement": null})
	var cristal := _entite("cristal_6", {"energie_cristal": 9.0})
	Couplage.poser(sentinelle, cristal, "veille_cristal", _catalogue())
	Couplage.retirer(sentinelle, "raison_quelconque_jamais_lue")
	v.v(sentinelle.proprietes.engagement == null, "retirer doit toujours remettre l'engagement a null")

func _regle_absente_du_catalogue_alarme(v) -> void:
	var sentinelle := _entite("sentinelle_7", {"engagement": null})
	var cristal := _entite("cristal_7", {"energie_cristal": 9.0})
	Couplage.poser(sentinelle, cristal, "regle_inexistante", _catalogue())
	v.v(sentinelle.proprietes.engagement == null,
		"poser avec un regle_id absent du catalogue doit alarmer et ne rien ecrire")

	# avancer() a sa PROPRE garde sur la meme absence, et c'est le chemin
	# dangereux : un engagement deja pose dont la regle disparait du catalogue
	# ne peut plus jamais etre satisfait. Il doit alarmer PUIS arracher --
	# jamais garder l'entite couplee a une cible qu'aucune regle ne juge.
	var veilleur := _entite("veilleur_7", {"engagement": {"regle_id": "regle_disparue", "cible_id": "cristal_7"}})
	v.v(Couplage.avancer(veilleur, cristal, 1.0, _catalogue()) == "arrache",
		"avancer sur une regle absente du catalogue doit alarmer et arracher")
	v.v(veilleur.proprietes.engagement == null,
		"l'engagement orphelin doit etre retire, jamais laisse en place")

func _propriete_structurelle_absente_alarme(v) -> void:
	var sentinelle := _entite("sentinelle_8", {})
	var cristal := _entite("cristal_8", {"energie_cristal": 9.0})
	Couplage.poser(sentinelle, cristal, "veille_cristal", _catalogue())
	v.v(not sentinelle.proprietes.has("engagement"),
		"proprietes sans la cle structurelle 'engagement' ne doit rien ecrire (alarme, pas defaut silencieux)")
	var resultat := Couplage.avancer(sentinelle, cristal, 1.0, _catalogue())
	v.v(resultat == "vide", "avancer sur une entite sans cle 'engagement' doit alarmer et rendre 'vide'")

# Un meme regle_id sert plusieurs canaux distincts sans dupliquer l'entree
# de catalogue -- le jeton {canal} est substitue depuis le contexte pose,
# jamais lu en dur dans couplage.gd.
func _contexte_parametre_le_chemin_de_satisfaction_par_canal(v) -> void:
	var horloge := _entite("horloge_1", {"engagement": null})
	var source := _entite("source_1", {})
	Couplage.poser(horloge, source, "jauge_par_canal", _catalogue(), {"canal": "mana"})
	v.v(horloge.proprietes.engagement.canal == "mana", "contexte doit se fusionner dans l'engagement pose")
	source.proprietes["jauges"] = {"mana": {"valeur": 8.0}}
	var garde := Couplage.avancer(horloge, source, 1.0, _catalogue())
	v.v(garde == "garde", "jauges.mana.valeur (8.0) au-dessus du seuil (5.0) doit garder")
	source.proprietes.jauges.mana.valeur = 2.0
	var satisfait := Couplage.avancer(horloge, source, 1.0, _catalogue())
	v.v(satisfait == "satisfait", "jauges.mana.valeur (2.0) sous le seuil (5.0) doit satisfaire")

# La cible peut ne rien porter de pertinent (un simple repere spatial) --
# la valeur a comparer vit alors sur l'ENTITE elle-meme (ex. une reserve
# interne), jamais sur la cible. couplage.gd cherche l'un puis l'autre,
# sans jamais nommer "reserve" ni "chantier".
func _valeur_cherchee_sur_l_entite_si_absente_de_la_cible(v) -> void:
	var horloge := _entite("horloge_2", {
		"engagement": null,
		"jauges": {"mana": {"valeur": 7.0}},
	})
	var repere := _entite("repere_1", {})
	Couplage.poser(horloge, repere, "jauge_par_canal", _catalogue(), {"canal": "mana"})
	var garde := Couplage.avancer(horloge, repere, 1.0, _catalogue())
	v.v(garde == "garde",
		"absente de la cible, la valeur doit se lire sur l'entite (7.0, au-dessus du seuil 5.0)")
	horloge.proprietes.jauges.mana.valeur = 1.0
	var satisfait := Couplage.avancer(horloge, repere, 1.0, _catalogue())
	v.v(satisfait == "satisfait", "meme lecture cote entite, sous le seuil doit satisfaire")

# sens_satisfaction "sur_seuil" : une jauge qui RECHARGE se satisfait en
# MONTANT, jamais en descendant -- sans ce champ, la comparaison par
# defaut ("<=") satisferait des la premiere baisse, l'exact inverse du
# comportement voulu pour une reserve qui se recharge (voir couplage.gd,
# section 4 de l'en-tete).
func _sens_satisfaction_sur_seuil_inverse_la_comparaison(v) -> void:
	var sentinelle := _entite("sentinelle_9", {"engagement": null})
	var cristal := _entite("cristal_9", {"energie_cristal": 3.0})
	Couplage.poser(sentinelle, cristal, "jauge_qui_recharge", _catalogue())
	v.v(sentinelle.proprietes.engagement.sens_satisfaction == "sur_seuil",
		"poser doit copier sens_satisfaction depuis la regle")

	var sous_le_seuil := Couplage.avancer(sentinelle, cristal, 1.0, _catalogue())
	v.v(sous_le_seuil == "garde",
		"sur_seuil : valeur (3.0) sous le seuil (8.0) doit garder, PAS satisfaire (inverse de sous_seuil)")

	cristal.proprietes.energie_cristal = 9.0
	var au_dessus_du_seuil := Couplage.avancer(sentinelle, cristal, 1.0, _catalogue())
	v.v(au_dessus_du_seuil == "satisfait",
		"sur_seuil : valeur (9.0) au-dessus du seuil (8.0) doit satisfaire")
	v.v(sentinelle.proprietes.engagement == null, "satisfait doit retirer l'engagement, meme en sens sur_seuil")
