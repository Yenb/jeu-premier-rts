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
	_retirer_sort_une_chose_de_partout()
	_choses_dans_couloir_ne_lit_que_les_cases_traversees()
	_choses_dans_rayons_equivaut_a_la_boucle_ponctuelle()
	_ajouter_lot_equivaut_a_la_boucle_unitaire()
	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: position vivante suivie apres deplacement, filtre de distance nominal, " +
		"ajouter() refuse sans position comme sur un id deja pris sans jamais ecraser, " +
		"retirer() ne laisse aucun fantome derriere lui, et choses_dans_couloir suit " +
		"la longueur du segment (candidats_mesures borne, jamais N)")
	quit(0)

# REQUETE GROUPEE : choses_dans_rayons(positions, rayon) doit rendre pour
# chaque point la meme chose que choses_dans_rayon(pos, rayon), meme
# resultat (memes ids, meme ordre car aucun trier_par_insertion). Prouve
# aussi que la longueur de la sortie egale la longueur de l'entree.
func _choses_dans_rayons_equivaut_a_la_boucle_ponctuelle() -> void:
	var monde := Monde.new()
	for i in range(50):
		var pos := Vector3(float(i) * 2.0, 0.0, float((i * 7) % 20))
		var c := Objet.fabriquer("chose_%d" % i, "type", pos, {})
		monde.ajouter(c, "type", c.position)
	var points: Array = [
		Vector3(0.0, 0.0, 0.0),
		Vector3(20.0, 0.0, 10.0),
		Vector3(80.0, 0.0, 5.0),
		Vector3(1000.0, 0.0, 0.0),
	]
	var rayon: float = 5.0
	var groupe := monde.choses_dans_rayons(points, rayon)
	verif.v(groupe.size() == points.size(),
		"choses_dans_rayons doit rendre autant d'entrees que de points (%d vs %d)" % [groupe.size(), points.size()])
	var i: int = 0
	while i < points.size():
		var ponctuel := monde.choses_dans_rayon(points[i], rayon)
		var batch: Array = groupe[i]
		verif.v(ponctuel.size() == batch.size(),
			"point %d : taille batch %d != ponctuel %d" % [i, batch.size(), ponctuel.size()])
		var j: int = 0
		while j < ponctuel.size() and j < batch.size():
			verif.v(ponctuel[j].chose == batch[j].chose,
				"point %d j=%d : chose differente entre batch et ponctuel" % [i, j])
			j += 1
		i += 1

# COUT DE LA REQUETE COULOIR : N=2000 choses eparpillees en anneau tres loin
# du segment (y=100+/-50), trois choses PILE sur le segment. Le compteur
# candidats_mesures doit rester borne par la petite bande transverse, jamais
# suivre N -- c'est ce qui prouve l'absence de balayage cache (un test de
# correction seul ne verrait pas un O(n) qui donne encore la bonne reponse).
func _choses_dans_couloir_ne_lit_que_les_cases_traversees() -> void:
	var monde := Monde.new()
	# 2000 choses HORS du couloir : anneau autour de (50,100,0), tous les y
	# entre ~50 et ~150. Le couloir demande [y=-0.5, y=+0.5] -- aucune de ces
	# choses n'est dans une case y visitee par la requete.
	for i in range(2000):
		var angle: float = float(i) * TAU / 2000.0
		var pos := Vector3(50.0 + cos(angle) * 50.0, 100.0 + sin(angle) * 50.0, 0.0)
		var hors := Objet.fabriquer("hors_%d" % i, "hors", pos, {})
		monde.ajouter(hors, "hors", hors.position)
	# TROIS choses PILE dans le couloir, cases x distinctes.
	for k in range(3):
		var pos_dedans := Vector3(25.0 * float(k + 1), 0.0, 0.0)
		var dedans := Objet.fabriquer("dedans_%d" % k, "dedans", pos_dedans, {})
		monde.ajouter(dedans, "dedans", dedans.position)

	monde.remettre_les_compteurs()
	var trouves := monde.choses_dans_couloir(Vector3.ZERO, Vector3(100.0, 0.0, 0.0), 0.5)
	verif.v(trouves.size() == 3,
		"les trois choses PILE dans le couloir doivent etre trouvees (recu %d)" % trouves.size())
	verif.v(monde.candidats_mesures < 50,
		"candidats_mesures doit suivre la longueur du segment, pas N=2000 (recu %d)" % monde.candidats_mesures)

# UNE CHOSE RETIREE NE COMPTE PLUS NULLE PART -- ni dans une requete de
# rayon, ni dans un par_id() qui suit. Deux niveaux ouverts avant le
# retrait (un petit rayon puis un grand), pour prouver que retirer() les
# parcourt TOUS, pas seulement celui de la derniere requete.
func _retirer_sort_une_chose_de_partout() -> void:
	var monde := Monde.new()
	var cible := Objet.fabriquer("cible", "type_cible", Vector3(10, 0, 0), {})
	var temoin := Objet.fabriquer("temoin", "type_temoin", Vector3(10, 0, 0), {})
	monde.ajouter(cible, "type_cible", cible.position)
	monde.ajouter(temoin, "type_temoin", temoin.position)

	# OUVRE DEUX NIVEAUX DE RESOLUTION DIFFERENTS avant le retrait.
	verif.v(monde.choses_dans_rayon(Vector3(10, 0, 0), 1.0).size() == 2,
		"les deux choses doivent etre trouvees a courte portee avant le retrait")
	verif.v(monde.choses_dans_rayon(Vector3(10, 0, 0), 500.0).size() == 2,
		"les deux choses doivent etre trouvees a longue portee avant le retrait")

	monde.retirer("cible")

	verif.v(monde.par_id("cible") == null, "une chose retiree ne doit plus repondre a par_id()")
	var courte := monde.choses_dans_rayon(Vector3(10, 0, 0), 1.0)
	verif.v(courte.size() == 1 and courte[0].chose.id == "temoin",
		"a courte portee, seul le temoin doit rester apres le retrait de la cible")
	var longue := monde.choses_dans_rayon(Vector3(10, 0, 0), 500.0)
	verif.v(longue.size() == 1 and longue[0].chose.id == "temoin",
		"a longue portee aussi, la cible retiree ne doit plus etre trouvee")

	# UN ID ABSENT ALARME ET NE FAIT RIEN -- jamais un second retrait muet.
	monde.retirer("cible")
	verif.v(monde.choses_dans_rayon(Vector3(10, 0, 0), 1.0).size() == 1,
		"retirer() sur un id deja absent ne doit rien changer d'autre")

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

# LOT : ajouter_lot(entries) doit rendre le meme etat qu'une boucle
# unitaire d'ajouter, memes ids, meme voisinage.
func _ajouter_lot_equivaut_a_la_boucle_unitaire() -> void:
	# Oracle : ajouter un a un.
	var oracle := Monde.new()
	for i in range(20):
		var pos := Vector3(float(i), 0.0, 0.0)
		var c := Objet.fabriquer("chose_%d" % i, "type", pos, {})
		oracle.ajouter(c, "type", c.position)
	# Essai : ajouter_lot avec entries.
	var essai := Monde.new()
	var entries: Array = []
	for i in range(20):
		var pos := Vector3(float(i), 0.0, 0.0)
		var c := Objet.fabriquer("chose_%d" % i, "type", pos, {})
		entries.append({"chose": c, "type": "type"})
	essai.ajouter_lot(entries)
	# Verifie que chaque id est retrouvable et que le voisinage est identique.
	for i in range(20):
		var id: String = "chose_%d" % i
		verif.v(oracle.par_id(id) != null, "oracle : id %s doit etre present" % id)
		verif.v(essai.par_id(id) != null, "essai : id %s doit etre present" % id)
	var voisins_oracle := oracle.choses_dans_rayon(Vector3(10.0, 0.0, 0.0), 5.0)
	var voisins_essai := essai.choses_dans_rayon(Vector3(10.0, 0.0, 0.0), 5.0)
	verif.v(voisins_oracle.size() == voisins_essai.size(),
		"voisinage : oracle %d essai %d" % [voisins_oracle.size(), voisins_essai.size()])
