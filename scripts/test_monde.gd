extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_monde.gd
#
# Verrouille monde.gd : choses_dans_rayon() lit la position VIVANTE
# de la chose (chose.position) a chaque appel, jamais une copie figee au
# moment de l'ajout -- une chose deplacee apres son ajout (colon.position
# reassigne a chaque tick, voir banc_p1.gd:_faire_agir_colon) doit rester
# trouvable a sa position actuelle, absente de l'ancienne. Verrouille
# aussi le filtre de distance nominal (deja couvert indirectement par
# test_perception.gd, verrouille ici directement sur monde.gd).
#
# Ce fichier teste _monde reellement, pas un echafaudage a part : depuis
# le chantier "_monde porte la requete spatiale" (CARTE.md §6), _monde
# (banc_p1.gd) EST une instance de Monde. Ce verrou couvre donc un
# mecanisme dont le banc reel depend, pas juste une fixture de test.

const Monde = preload("res://scripts/monde.gd")
const Objet = preload("res://scripts/objet.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

func _init() -> void:
	_chose_deplacee_suit_sa_position_vivante()
	_resynchroniser_rattrape_un_deplacement_en_lot()
	_filtre_de_distance_nominal()
	_ajouter_refuse_sans_position_et_refuse_un_id_deja_pris()
	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: position vivante suivie apres deplacement, filtre de distance nominal, " +
		"et ajouter() refuse sans position comme sur un id deja pris, sans jamais ecraser")
	quit(0)

# LES DEUX REFUS D'ajouter(), exerces ici et nulle part ailleurs. Le second
# est le plus couteux : un id deja pris fait SORTIR sans enregistrer, et une
# chose absente du Monde reste parfaitement vivante dans la liste de son
# appelant -- elle bouge, elle est lue, mais aucune requete spatiale ne la
# trouvera. Le symptome a deja ete paye en jeu (des petits nommes comme des
# individus de depart), jamais verrouille.
func _ajouter_refuse_sans_position_et_refuse_un_id_deja_pris() -> void:
	var monde := Monde.new()

	monde.ajouter({"id": "sans_position"}, "type", Vector3.ZERO)
	verif.v(monde.par_id("sans_position") == null,
		"une chose sans champ 'position' ne doit JAMAIS etre enregistree")

	var premier := Objet.fabriquer("meme_id", "type_a", Vector3.ZERO, {})
	var second := Objet.fabriquer("meme_id", "type_b", Vector3(50, 0, 0), {})
	monde.ajouter(premier, "type_a", premier.position)
	monde.ajouter(second, "type_b", second.position)
	var enregistre = monde.par_id("meme_id")
	verif.v(enregistre != null and enregistre.type == "type_a",
		"un id deja pris ne doit JAMAIS ecraser l'entree en place")
	verif.v(monde.choses_dans_rayon(Vector3(50, 0, 0), 5.0).is_empty(),
		"la chose refusee reste introuvable : aucune requete spatiale ne la voit")

func _chose_deplacee_suit_sa_position_vivante() -> void:
	var monde := Monde.new()
	var mobile := Objet.fabriquer("mobile", "type_mobile", Vector3(10, 0, 0), {})
	monde.ajouter(mobile, "type_mobile", mobile.position)

	var ici := monde.choses_dans_rayon(Vector3(10, 0, 0), 5.0)
	verif.v(ici.size() == 1, "la chose doit etre trouvee a sa position d'origine")

	mobile.position = Vector3(200, 0, 0)
	# LE DEPLACEMENT SE DECLARE. La requete de rayon ne visite que les cases
	# proches : une chose qui bouge sans le dire reste rangee a son ancienne
	# case et devient introuvable la ou elle est. C'est le prix d'une requete
	# qui ne balaie plus le monde entier, et il se paie ici, en une ligne.
	monde.deplacer(mobile)

	var ancienne := monde.choses_dans_rayon(Vector3(10, 0, 0), 5.0)
	verif.v(ancienne.size() == 0,
		"une chose deplacee ne doit plus etre trouvee a son ancienne position")

	var nouvelle := monde.choses_dans_rayon(Vector3(200, 0, 0), 5.0)
	verif.v(nouvelle.size() == 1,
		"une chose deplacee doit etre trouvee a sa NOUVELLE position")
	if nouvelle.size() == 1:
		verif.v(nouvelle[0].position == Vector3(200, 0, 0),
			"la position rendue doit etre la position vivante, pas la copie figee a l'ajout")

func _resynchroniser_rattrape_un_deplacement_en_lot() -> void:
	var monde := Monde.new()
	var choses: Array = []
	for i in range(3):
		var chose := Objet.fabriquer("lot%d" % i, "type_lot", Vector3(float(i), 0, 0), {})
		choses.append(chose)
		monde.ajouter(chose, "type_lot", chose.position)

	# TROIS CHOSES DEPLACEES D'UN COUP, sans que personne ne le declare : c'est
	# ce que fait une bascule de scene. resynchroniser() est la reponse -- une
	# seule passe pour tout le monde, au lieu d'un deplacer() par chose.
	for chose in choses:
		chose.position = Vector3(300.0 + chose.position.x, 0, 0)
	monde.resynchroniser()

	verif.v(monde.choses_dans_rayon(Vector3(1, 0, 0), 5.0).is_empty(),
		"apres resynchronisation, plus rien ne doit etre trouve a l'ancienne place")
	verif.v(monde.choses_dans_rayon(Vector3(301, 0, 0), 5.0).size() == 3,
		"apres resynchronisation, les trois choses doivent etre trouvees a la nouvelle place")

func _filtre_de_distance_nominal() -> void:
	var monde := Monde.new()
	var dedans := Objet.fabriquer("dedans", "type_dedans", Vector3(10, 0, 0), {})
	var dehors := Objet.fabriquer("dehors", "type_dehors", Vector3(500, 0, 0), {})
	monde.ajouter(dedans, "type_dedans", dedans.position)
	monde.ajouter(dehors, "type_dehors", dehors.position)

	var resultat := monde.choses_dans_rayon(Vector3.ZERO, 50.0)
	verif.v(resultat.size() == 1, "attendu 1 chose dans le rayon, recu %d" % resultat.size())
	if resultat.size() == 1:
		verif.v(resultat[0].chose.id == "dedans", "la chose dans le rayon doit etre 'dedans'")
