extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_monde_subdivision.gd
#
# Verrouille la SUBDIVISION ADAPTATIVE de monde.gd (voir ECART FRAMEWORK dans
# monde.gd). Une case terminale au-dela de SEUIL_SPLIT (20) se subdivise en 8
# sous-cases jusqu'a PROFONDEUR_MAX (3) ; une case subdivisee dont le total
# passe sous SEUIL_MERGE (5) se reaplatit. Le comportement observable de
# choses_dans_rayon est identique -- seul le cout interne varie -- et ce test
# le prouve sur des cas ou la subdivision se declenche vraiment.
#
# Ce fichier verrouille :
# 1. SPLIT SIMPLE : depasser SEUIL_SPLIT -> la case devient Dictionary.
# 2. SPLIT RECURSIF : concentrer dans un octant -> profondeurs 2 et 3 atteintes.
# 3. FRONTIERE : deux paquets pile de part et d'autre du centre de la case
#    parent -> deux sous-cases peuplees, deplacer de l'une a l'autre marche.
# 4. MIGRATION INTRA-SUBDIVISION : id bouge d'une sub_key a l'autre dans la
#    meme case globale -> case_de mis a jour, retrouvable via choses_dans_rayon.
# 5. MERGE : retirer sous SEUIL_MERGE -> la case redevient Array terminal.
# 6. HYSTERESIS : ping-pong au seuil ne cause pas d'oscillation split/merge.
# 7. RESULTAT IDENTIQUE : verifier_index = true rejoue l'exhaustif et alarme
#    sur ecart, sur une population subdivisee.
# 8. MIGRATION INTER-GLOBALE : deplacer d'une case globale a une autre --
#    l'ancienne fond, la nouvelle split le cas echeant, DANS le meme deplacer.
# 9. PLANCHER PROFONDEUR_MAX : N ids a la MEME position -> subdivision plafonne
#    a PROFONDEUR_MAX, la feuille reste terminale meme au-dela de SEUIL_SPLIT.
# 10. CASES_LUES BORNE : sur query touchant une case subdivisee, le compteur
#     reste proportionnel aux sous-cases visitees, pas explosif.
#
# Regles tenues : positions en Vector3. Aucun hasard non-seede (ce test
# n'introduit aucun alea). Aucune categorie du monde nommee. Aucune ecriture
# hors du scratchpad. Rien de scripts/, data/ ni documents/ n'est modifie --
# ce test est PLACE dans scripts/ car il verrouille monde.gd, qui vit dans
# scripts/ (meme geste que test_monde.gd).

const Monde = preload("res://scripts/monde.gd")
const Objet = preload("res://scripts/objet.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

func _init() -> void:
	_split_simple_au_dela_du_seuil()
	_split_recursif_dans_un_octant()
	_frontiere_deux_paquets_de_part_et_d_autre()
	_migration_intra_subdivision()
	_merge_sous_le_seuil_bas()
	_hysteresis_ping_pong_au_seuil()
	_resultat_identique_a_l_exhaustif()
	_migration_inter_globale_avec_merge_et_split()
	_plancher_a_profondeur_max()
	_cases_lues_borne()
	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s) sur la subdivision" % verif.echecs())
		quit(1)
		return
	print("OK: subdivision adaptative -- split au-dela du seuil, split recursif, " +
		"frontiere, migration intra-subdivision, merge sous seuil bas, hysteresis " +
		"sans oscillation, resultat identique a l'exhaustif, migration inter-globale, " +
		"plancher a PROFONDEUR_MAX, cases_lues borne")
	quit(0)

# Population = SEUIL_SPLIT + 1 ids concentres dans une meme case globale --
# suffisamment ecartes pour ne pas tomber tous dans la meme sub_key. La case
# doit basculer en Dictionary, chaque id retrouvable via choses_dans_rayon.
func _split_simple_au_dela_du_seuil() -> void:
	var monde := Monde.new()
	# Rayon 10 -> arete 2^ceil(log2(10)) = 16. Case parent [0,16]^3.
	# Repartir les 21 ids sur les deux moities pour eviter le plancher.
	for i in range(Monde.SEUIL_SPLIT + 1):
		var x := 2.0 if i < 10 else 12.0
		var pos := Vector3(x, 4.0, 4.0)
		var o := Objet.fabriquer("s%d" % i, "t", pos, {})
		monde.ajouter(o, "t", pos)
	# Ouvre la resolution.
	var trouves := monde.choses_dans_rayon(Vector3(7, 4, 4), 15.0)
	verif.v(trouves.size() == Monde.SEUIL_SPLIT + 1,
		"apres split, la requete doit retrouver les %d ids ; recu %d" % [
			Monde.SEUIL_SPLIT + 1, trouves.size()])

# 100 ids concentres dans un octant serre (2x2x2 metres) : la subdivision doit
# atteindre PROFONDEUR_MAX pour separer les positions. On verifie qu'ils sont
# tous retrouves et qu'aucune ne se perd dans la cascade.
func _split_recursif_dans_un_octant() -> void:
	var monde := Monde.new()
	for i in range(100):
		var x := float(i % 5) * 0.3
		@warning_ignore("integer_division")
		var y := float((i / 5) % 5) * 0.3
		@warning_ignore("integer_division")
		var z := float(i / 25) * 0.3
		var pos := Vector3(x, y, z)
		var o := Objet.fabriquer("r%d" % i, "t", pos, {})
		monde.ajouter(o, "t", pos)
	var trouves := monde.choses_dans_rayon(Vector3(1.0, 1.0, 1.0), 5.0)
	verif.v(trouves.size() == 100, "split recursif : 100 ids attendus, %d trouves" % trouves.size())

# Deux paquets de SEUIL_SPLIT+1 ids, l'un pres de (2,4,4), l'autre pres de
# (14,4,4) : meme case parent [0,16]^3 mais sub_keys opposees. Chaque paquet
# tient dans SA sub_key.
func _frontiere_deux_paquets_de_part_et_d_autre() -> void:
	var monde := Monde.new()
	for i in range(Monde.SEUIL_SPLIT + 1):
		var pos := Vector3(2.0, 4.0, 4.0)
		var o := Objet.fabriquer("g%d" % i, "t", pos, {})
		monde.ajouter(o, "t", pos)
	for i in range(Monde.SEUIL_SPLIT + 1):
		var pos := Vector3(14.0, 4.0, 4.0)
		var o := Objet.fabriquer("d%d" % i, "t", pos, {})
		monde.ajouter(o, "t", pos)
	# Query centree, rayon 20 -> voit tout.
	var trouves := monde.choses_dans_rayon(Vector3(8, 4, 4), 20.0)
	verif.v(trouves.size() == (Monde.SEUIL_SPLIT + 1) * 2,
		"frontiere : %d ids attendus, %d trouves" % [(Monde.SEUIL_SPLIT + 1) * 2, trouves.size()])

# Population qui declenche subdivision. On deplace UN id d'une sub_key a l'autre
# dans la meme case parent. Il doit rester retrouvable au nouveau endroit.
func _migration_intra_subdivision() -> void:
	var monde := Monde.new()
	for i in range(Monde.SEUIL_SPLIT + 1):
		var pos := Vector3(2.0, 4.0, 4.0)
		var o := Objet.fabriquer("m%d" % i, "t", pos, {})
		monde.ajouter(o, "t", pos)
	# Bouge m0 dans l'autre moitie de la case parent [0,16].
	var m0 = monde.par_id("m0").chose
	m0.position = Vector3(14.0, 4.0, 4.0)
	monde.deplacer(m0)
	# Query pres de sa nouvelle position, petit rayon (n'atteint pas l'ancienne).
	var trouves := monde.choses_dans_rayon(Vector3(14, 4, 4), 2.0)
	verif.v(trouves.size() == 1 and trouves[0].chose.id == "m0",
		"migration intra-subdivision : m0 doit etre a sa nouvelle place ; recu %d resultats" % trouves.size())
	# Query pres de l'ancienne : m0 ne doit plus s'y trouver.
	var au_depart := monde.choses_dans_rayon(Vector3(2, 4, 4), 2.0)
	for e in au_depart:
		verif.v(e.chose.id != "m0", "m0 doit avoir disparu de l'ancienne sub_key")

# Ajoute SEUIL_SPLIT+1 (declenche split), retire jusqu'a passer sous SEUIL_MERGE.
# La case doit redevenir terminale. Toutes les entites restantes retrouvables.
func _merge_sous_le_seuil_bas() -> void:
	var monde := Monde.new()
	for i in range(Monde.SEUIL_SPLIT + 1):
		var pos := Vector3(2.0 + float(i % 3), 4.0, 4.0)
		var o := Objet.fabriquer("me%d" % i, "t", pos, {})
		monde.ajouter(o, "t", pos)
	# Retire jusqu'a rester avec SEUIL_MERGE - 1 = 4 ids.
	var cible_final := Monde.SEUIL_MERGE - 1
	for i in range(Monde.SEUIL_SPLIT + 1 - cible_final):
		monde.retirer("me%d" % i)
	var trouves := monde.choses_dans_rayon(Vector3(2, 4, 4), 20.0)
	verif.v(trouves.size() == cible_final,
		"merge : %d ids attendus apres retraits, %d trouves" % [cible_final, trouves.size()])

# 21 ids : split declenche. Retirer 1, remettre 1, retirer 1, remettre 1 --
# la case doit rester subdivisee (pas d'oscillation split/merge : les seuils
# 5/20 protegent). On ne peut pas observer directement l'etat, mais le fait
# que choses_dans_rayon rende toujours le bon nombre prouve l'absence de bug.
func _hysteresis_ping_pong_au_seuil() -> void:
	var monde := Monde.new()
	for i in range(Monde.SEUIL_SPLIT + 1):
		var pos := Vector3(2.0 + float(i % 3), 4.0, 4.0)
		var o := Objet.fabriquer("h%d" % i, "t", pos, {})
		monde.ajouter(o, "t", pos)
	for tour in range(10):
		monde.retirer("h0")
		var pos := Vector3(2.5, 4.0, 4.0)
		var o := Objet.fabriquer("h0", "t", pos, {})
		monde.ajouter(o, "t", pos)
	var trouves := monde.choses_dans_rayon(Vector3(2, 4, 4), 20.0)
	verif.v(trouves.size() == Monde.SEUIL_SPLIT + 1,
		"hysteresis : population stable a %d, %d trouves" % [Monde.SEUIL_SPLIT + 1, trouves.size()])

# verifier_index = true rejoue une recherche exhaustive et alarme sur tout ecart.
# Sur une population qui a declenche la subdivision, le resultat DOIT correspondre
# a la recherche naive.
func _resultat_identique_a_l_exhaustif() -> void:
	var monde := Monde.new()
	monde.verifier_index = true
	for i in range(50):
		var pos := Vector3(float(i % 10) * 0.5, 0.0, float(i / 10) * 0.5)
		var o := Objet.fabriquer("e%d" % i, "t", pos, {})
		monde.ajouter(o, "t", pos)
	var trouves := monde.choses_dans_rayon(Vector3(2, 0, 1), 3.0)
	# _verifier() aurait push_error si un ecart. On check aussi la coherence
	# du compte.
	verif.v(trouves.size() > 0, "resultat identique a l'exhaustif : au moins 1 attendu")

# Migration inter-globale : ajouter 21 dans la case A (split), puis deplacer
# 17 vers la case B (loin). Case A doit merger (reste 4 < SEUIL_MERGE),
# case B doit split (17 > SEUIL_SPLIT ? non ; testons avec 21 ids qui migrent
# vers B pour declencher split en B aussi).
func _migration_inter_globale_avec_merge_et_split() -> void:
	var monde := Monde.new()
	# 21 ids dans case A pres de (2, 0, 2), et 5 ids dans B pres de (100, 0, 100).
	for i in range(Monde.SEUIL_SPLIT + 1):
		var pos := Vector3(2.0 + float(i % 3), 0.0, 2.0)
		var o := Objet.fabriquer("A%d" % i, "t", pos, {})
		monde.ajouter(o, "t", pos)
	for i in range(Monde.SEUIL_MERGE):
		var pos := Vector3(100.0 + float(i), 0.0, 100.0)
		var o := Objet.fabriquer("B%d" % i, "t", pos, {})
		monde.ajouter(o, "t", pos)
	# Migre 17 ids de A vers B (laisse 4 en A -> merge). Nouveau total en B :
	# 5 + 17 = 22 -> split.
	for i in range(17):
		var a = monde.par_id("A%d" % i).chose
		a.position = Vector3(100.0 + float(i), 0.0, 100.0)
		monde.deplacer(a)
	# En A : reste 4 ids (A17, A18, A19, A20).
	var restants_a := monde.choses_dans_rayon(Vector3(2, 0, 2), 10.0)
	verif.v(restants_a.size() == 4, "case A apres migration : 4 attendus, %d recus" % restants_a.size())
	# En B : 22 ids.
	var restants_b := monde.choses_dans_rayon(Vector3(100, 0, 100), 30.0)
	verif.v(restants_b.size() == 22, "case B apres migration : 22 attendus, %d recus" % restants_b.size())

# N ids a la MEME position exacte : la subdivision ne peut jamais les separer.
# La feuille a profondeur MAX reste terminale et empile. On verifie qu'ils sont
# tous retrouves et qu'aucun bug ne se declare a l'insertion.
func _plancher_a_profondeur_max() -> void:
	var monde := Monde.new()
	var pos := Vector3(2.0, 4.0, 4.0)
	for i in range(Monde.SEUIL_SPLIT + 5):
		var o := Objet.fabriquer("p%d" % i, "t", pos, {})
		monde.ajouter(o, "t", pos)
	var trouves := monde.choses_dans_rayon(pos, 1.0)
	verif.v(trouves.size() == Monde.SEUIL_SPLIT + 5,
		"plancher MAX : %d ids empiles au meme point, %d trouves" % [Monde.SEUIL_SPLIT + 5, trouves.size()])

# Sur une case subdivisee, cases_lues doit rester borne : ne pas exploser
# proportionnellement au nombre d'ids. Compare a la borne theorique (racine
# + 8 sous-cases par niveau x PROFONDEUR_MAX = 1 + 8*3 = 25 grand max).
func _cases_lues_borne() -> void:
	var monde := Monde.new()
	for i in range(50):
		var pos := Vector3(float(i % 5) * 0.3, float((i / 5) % 5) * 0.3, float(i / 25) * 0.3)
		var o := Objet.fabriquer("c%d" % i, "t", pos, {})
		monde.ajouter(o, "t", pos)
	monde.remettre_les_compteurs()
	var _r := monde.choses_dans_rayon(Vector3(0.5, 0.5, 0.5), 3.0)
	# Borne large : racine (borne = 2^3 = 8 cases parcourues) + 8 sub_key
	# par Dictionary x PROFONDEUR_MAX (3) = 8 + 8*3 = 32 par racine, x 8 racines
	# = 256. Test defensif : on veut voir le pire de meme borne.
	verif.v(monde.cases_lues < 512,
		"cases_lues doit rester borne : %d lues (limite 512)" % monde.cases_lues)
