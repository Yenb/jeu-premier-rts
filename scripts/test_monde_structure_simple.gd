extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_monde_structure_simple.gd
#
# Verrouille le mode `structure_simple` de monde.gd (voir ECART FRAMEWORK dans
# monde.gd). Sous ce mode, la subdivision adaptative est court-circuitee :
# chaque case reste un Array<id> a plat, deplacer devient un swap-remove +
# append. Le COMPORTEMENT OBSERVABLE des requetes (choses_dans_rayon /
# _couloir) doit rester IDENTIQUE au mode par defaut -- seul le cout interne
# change. Ce test le prouve.
#
# Trois cas :
# 1. PARITE AJOUT + RAYON : mille objets ajoutes, meme resultat de rayon dans
#    les deux modes (memes ids, meme compte).
# 2. PARITE DEPLACER : chaque objet bouge une fois, retrouve a la nouvelle
#    position dans les deux modes, absent de l'ancienne.
# 3. PARITE RETIRER : retirer un lot, le reste est identique dans les deux
#    modes.
#
# La subdivision existante reste verrouillee par scripts/test_monde_subdivision.gd
# (mode par defaut, structure_simple=false).

const Monde = preload("res://scripts/monde.gd")
const Objet = preload("res://scripts/objet.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

func _init() -> void:
	_parite_ajout_et_rayon()
	_parite_deplacer()
	_parite_retirer()
	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: structure_simple rend les MEMES ids sur choses_dans_rayon " +
		"apres ajout / deplacement / retrait qu'en mode subdivision")
	quit(0)

func _peupler(monde: Object, n: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260908
	for i in range(n):
		var pos := Vector3(rng.randf_range(-50.0, 50.0), 0.0, rng.randf_range(-50.0, 50.0))
		var o := Objet.fabriquer("p%d" % i, "t", pos, {})
		monde.ajouter(o, "t", pos)

func _ids_tries(monde: Object, centre: Vector3, rayon: float) -> Array:
	var trouves: Array = monde.choses_dans_rayon(centre, rayon)
	var ids: Array = []
	for e in trouves:
		ids.append(e.chose.id)
	ids.sort()
	return ids

func _parite_ajout_et_rayon() -> void:
	var m_defaut := Monde.new()
	var m_simple := Monde.new()
	m_simple.structure_simple = true
	_peupler(m_defaut, 1000)
	_peupler(m_simple, 1000)
	var ids_defaut := _ids_tries(m_defaut, Vector3(10, 0, 10), 15.0)
	var ids_simple := _ids_tries(m_simple, Vector3(10, 0, 10), 15.0)
	verif.v(ids_defaut == ids_simple,
		"parite ajout+rayon : structure_simple doit rendre les MEMES ids (defaut=%d, simple=%d)" % [ids_defaut.size(), ids_simple.size()])

func _parite_deplacer() -> void:
	var m_defaut := Monde.new()
	var m_simple := Monde.new()
	m_simple.structure_simple = true
	_peupler(m_defaut, 500)
	_peupler(m_simple, 500)
	# Deplace TOUS les objets d'un decalage constant. Les positions restent en
	# phase entre les deux mondes (memes ids, meme nouvelles positions).
	var decalage := Vector3(20.0, 0.0, -20.0)
	for i in range(500):
		var id: String = "p%d" % i
		var e_d = m_defaut.par_id(id)
		var e_s = m_simple.par_id(id)
		e_d.chose.position += decalage
		e_s.chose.position += decalage
		m_defaut.deplacer(e_d.chose)
		m_simple.deplacer(e_s.chose)
	var ancien_defaut := _ids_tries(m_defaut, Vector3(10, 0, 10), 5.0)
	var ancien_simple := _ids_tries(m_simple, Vector3(10, 0, 10), 5.0)
	verif.v(ancien_defaut == ancien_simple,
		"parite deplacer (ancienne position) : recu defaut=%d simple=%d" % [ancien_defaut.size(), ancien_simple.size()])
	var nouveau_defaut := _ids_tries(m_defaut, Vector3(30, 0, -10), 15.0)
	var nouveau_simple := _ids_tries(m_simple, Vector3(30, 0, -10), 15.0)
	verif.v(nouveau_defaut == nouveau_simple,
		"parite deplacer (nouvelle position) : defaut=%d simple=%d, ids diverges" % [nouveau_defaut.size(), nouveau_simple.size()])

func _parite_retirer() -> void:
	var m_defaut := Monde.new()
	var m_simple := Monde.new()
	m_simple.structure_simple = true
	_peupler(m_defaut, 300)
	_peupler(m_simple, 300)
	for i in range(0, 300, 2):
		var id: String = "p%d" % i
		m_defaut.retirer(id)
		m_simple.retirer(id)
	var reste_defaut := _ids_tries(m_defaut, Vector3.ZERO, 200.0)
	var reste_simple := _ids_tries(m_simple, Vector3.ZERO, 200.0)
	verif.v(reste_defaut == reste_simple,
		"parite retirer : le reste doit etre identique (defaut=%d simple=%d)" % [reste_defaut.size(), reste_simple.size()])
	verif.v(reste_defaut.size() == 150,
		"parite retirer : 150 ids attendus apres retrait d'1/2, %d recu (mode defaut)" % reste_defaut.size())
