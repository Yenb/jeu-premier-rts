extends SceneTree

# Test headless du chantier "fatigue en cadence lente sur charge/seuil"
# (2026-09-08). Verrouille le cablage POUR UNE UNITE :
#
#   Depense.avancer(sommeil, delta)  --  decrement reserve
#   miroir plat : proprietes.manque_sommeil = capacite - reserves.sommeil.reserve
#   SeuilEtat.avancer(catalogue seuils_etat.json)  --  pose/retire 'epuise'
#
# CE QU'ON PROUVE ici :
# - Au demarrage (reserve=100), 'epuise' n'est PAS pose (manque=0 < seuil=70).
# - Apres N decrements, manque_sommeil franchit 70 -- 'epuise' est pose UNE fois.
# - Entre deux appels sans mutation du miroir, SeuilEtat.avancer NE MUTE RIEN (rend
#   un Array vide, l'etat reste actif -- memoire par entree, jamais un recalcul).
# - Rechargement de la reserve -> franchissement descendant -> 'epuise' est RETIRE.
# - Le seuil vient bien de data/seuils_etat.json (entree "epuisement"), aucun
#   nombre en dur dans ce test qui reference le mecanisme.
#
# Utilise scripts/verif.gd -- assert() natif INTERDIT.
# Lancement : godot --headless --script scripts/test_fatigue_seuil.gd

const Verif = preload("res://scripts/verif.gd")
const Objet = preload("res://scripts/objet.gd")
const Depense = preload("res://scripts/depense.gd")
const SeuilEtat = preload("res://scripts/seuil_etat.gd")

var _v := Verif.new()

func _init() -> void:
	_executer()
	if _v.echecs() == 0:
		print("OK: fatigue/seuil -- 5 cas passes (aucun etat avant seuil, epuise pose au franchissement, pas de recalcul entre deux, retire au franchissement inverse, seuil vient des donnees)")
		quit(0)
	else:
		printerr("ECHEC: %d assertion(s) fausse(s)" % _v.echecs())
		quit(1)

func _executer() -> void:
	var table: Dictionary = _charger_types()
	_v.v(table.has("mobile_test"), "prealable : types.json sans mobile_test")
	var catalogue_seuils: Dictionary = _charger_seuils()
	_v.v(catalogue_seuils.has("epuisement"), "prealable : seuils_etat.json sans entree 'epuisement'")

	# ---- CAS 5 (verifie D'ABORD, prealable a tout le reste) : le seuil vient des donnees.
	# Aucun nombre litteral n'est cite dans les CAS 1..4 -- ils lisent tout depuis
	# le catalogue.
	var entree_epuisement: Dictionary = catalogue_seuils.epuisement
	_v.v(entree_epuisement.has("seuil"), "cas 5 : 'seuil' absent de l'entree 'epuisement'")
	_v.v(entree_epuisement.has("propriete_continue"), "cas 5 : 'propriete_continue' absent")
	_v.v(entree_epuisement.has("etat"), "cas 5 : 'etat' absent")
	var seuil_data: float = float(entree_epuisement.seuil)
	var propriete_miroir: String = String(entree_epuisement.propriete_continue)
	var etat_nom: String = String(entree_epuisement.etat)

	# Objet.fabriquer avec paquets_partages=false : deep-copy propre, mutations
	# librement isolees pour ce test.
	Objet.vider_cache_paquets_partages()
	var individu: Dictionary = Objet.fabriquer("t1", "mobile_test", Vector3.ZERO, table, {}, [], {}, [], false)
	_v.v(not individu.is_empty(), "prealable : Objet.fabriquer a rendu {}")
	var p: Dictionary = individu.proprietes
	_v.v(p.has("reserves") and p.reserves.has("sommeil"), "prealable : canal sommeil absent (herite de dynamique)")

	# Accelerer le cout_base pour que le seuil se franchisse en un nombre modeste
	# de ticks -- cablage local au test, pas un choix moteur.
	p.reserves.sommeil.cout_base = 10.0
	var capacite_sommeil: float = float(p.reserves.sommeil.reserve)  # 100.0 par defaut de dynamique

	var monde: Array = [individu]

	# ---- CAS 1 : reserve pleine, aucun etat 'epuise' ----
	_poser_miroir(p, propriete_miroir, capacite_sommeil)
	_v.v(float(p[propriete_miroir]) < seuil_data, "cas 1 : miroir deja au-dessus du seuil au demarrage")
	SeuilEtat.avancer(monde, catalogue_seuils)
	var actifs_1: Array = p.get("etats_actifs", [])
	_v.v(not actifs_1.has(etat_nom),
		"cas 1 : etat '%s' pose alors que sommeil est plein (%.1f/%.1f)" % [etat_nom, float(p.reserves.sommeil.reserve), capacite_sommeil])

	# ---- CAS 2 : decrement + miroir + SeuilEtat -> 'epuise' pose UNE fois ----
	for _i in range(10):
		Depense.avancer(monde, 1.0)
	_poser_miroir(p, propriete_miroir, capacite_sommeil)
	_v.v(float(p[propriete_miroir]) > seuil_data,
		"cas 2 : miroir (%.1f) pas au-dessus du seuil (%.1f) apres decrement" % [float(p[propriete_miroir]), seuil_data])
	var bascules_2: Array = SeuilEtat.avancer(monde, catalogue_seuils)
	_v.v(bascules_2.has("t1"), "cas 2 : bascule montante non rendue apres franchissement")
	var actifs_2: Array = p.get("etats_actifs", [])
	_v.v(actifs_2.has(etat_nom), "cas 2 : etat '%s' pas pose apres franchissement" % etat_nom)

	# ---- CAS 3 : entre deux franchissements, SeuilEtat.avancer NE MUTE RIEN ----
	# Le miroir n'est PAS repose ; la memoire par entree conserve la derniere valeur ;
	# aucun cote observe ne change ; l'Array rendu est VIDE.
	var bascules_3: Array = SeuilEtat.avancer(monde, catalogue_seuils)
	_v.v(bascules_3.is_empty(),
		"cas 3 : SeuilEtat.avancer rend %d bascule(s) sans changement du miroir -- recalcul errone" % bascules_3.size())
	var actifs_3: Array = p.get("etats_actifs", [])
	_v.v(actifs_3.has(etat_nom), "cas 3 : etat '%s' retire hors franchissement" % etat_nom)

	# ---- CAS 4 : recharge -> franchissement descendant -> retire 'epuise' ----
	p.reserves.sommeil.reserve = capacite_sommeil
	_poser_miroir(p, propriete_miroir, capacite_sommeil)
	_v.v(float(p[propriete_miroir]) < seuil_data, "cas 4 : miroir toujours au-dessus du seuil apres recharge")
	var bascules_4: Array = SeuilEtat.avancer(monde, catalogue_seuils)
	_v.v(bascules_4.has("t1"), "cas 4 : bascule descendante non rendue apres recharge")
	var actifs_4: Array = p.get("etats_actifs", [])
	_v.v(not actifs_4.has(etat_nom), "cas 4 : etat '%s' encore actif apres franchissement descendant" % etat_nom)

func _poser_miroir(proprietes: Dictionary, nom_miroir: String, capacite: float) -> void:
	var reserve_actuelle: float = float(proprietes.reserves.sommeil.reserve)
	proprietes[nom_miroir] = capacite - reserve_actuelle

func _charger_types() -> Dictionary:
	var texte := FileAccess.get_file_as_string("res://data/types.json")
	var donnees = JSON.parse_string(texte)
	if donnees is Dictionary:
		return donnees
	return {}

func _charger_seuils() -> Dictionary:
	var texte := FileAccess.get_file_as_string("res://data/seuils_etat.json")
	var donnees = JSON.parse_string(texte)
	if donnees is Dictionary:
		return donnees
	return {}
