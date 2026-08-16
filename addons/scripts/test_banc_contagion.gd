extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_contagion.gd
#
# Verrouille le cablage de banc_contagion.gd : PREMIERE FERMETURE de la
# boucle lecteur agrege -> decision. causes_de_attache (calque sur
# banc_charge.gd:causes_de) selectionne les voisins porteurs d'une attache,
# scripts/charge.gd (inchange) absorbe ces causes et pose une propriete
# interne au franchissement du seuil.
#
# Fonction pure pour causes_de_attache : aucun noeud, aucun rendu. Les cas
# de pipeline (4/5/6) lisent data/banc_contagion.json REEL sur disque
# (canal/propriete_visee), comme le fait ce banc -- chemin reel, pas une
# fixture locale pour les poids/seuils.

const BancContagion = preload("res://scripts/banc_contagion.gd")
const Charge = preload("res://scripts/charge.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

const DELTA_TICK := 0.1

func _init() -> void:
	_causes_de_attache_construit_les_causes_attendues()
	_causes_de_attache_exclut_le_recepteur()
	_causes_de_attache_ignore_attache_sans_propriete_visee()
	_pipeline_charge_franchit_seuil()
	_pipeline_charge_redescend_si_causes_disparaissent()
	_resumabilite_des_colons()
	_porte_attache_et_couleur_de_distinguent_porteur_et_non_porteur()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: banc_contagion.gd ferme la boucle lecteur agrege -> decision -- " +
		"causes_de_attache selectionne les voisins porteurs, charge.gd (inchange) " +
		"absorbe la contagion et pose une propriete interne au seuil, reversible")
	quit(0)

func _colon(id: String, position: Vector3, attaches: Array, etats: Dictionary = {}) -> Dictionary:
	var proprietes: Dictionary = {"attaches": attaches}
	if not etats.is_empty():
		proprietes["etats"] = etats
	return {"id": id, "position": position, "proprietes": proprietes}

func _donnees_banc_reelles() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_contagion.json"))

func _causes_de_attache_construit_les_causes_attendues() -> void:
	var porteur_1 := _colon("porteur_1", Vector3(10.0, 0.0, 0.0), [{"propriete": "guerrier", "force": 1.0}])
	var porteur_2 := _colon("porteur_2", Vector3(-10.0, 0.0, 0.0), [{"propriete": "guerrier", "force": 1.0}])
	var non_porteur := _colon("non_porteur", Vector3(0.0, 10.0, 0.0), [])
	var colons := [porteur_1, porteur_2, non_porteur]

	var causes := BancContagion.causes_de_attache(colons, "guerrier", "non_porteur")
	verif.v(causes.size() == 2, "deux colons portent l'attache visee, deux causes attendues")
	verif.v(causes[0].position == porteur_1.position, "la premiere cause doit porter la position exacte de porteur_1")
	verif.v(causes[1].position == porteur_2.position, "la seconde cause doit porter la position exacte de porteur_2")
	verif.v(not causes[0].has("poids") and not causes[1].has("poids"),
		"aucun poids explicite : le defaut 1.0 de charge.gd doit suffire")

func _causes_de_attache_exclut_le_recepteur() -> void:
	var porteur_solo := _colon("porteur_solo", Vector3.ZERO, [{"propriete": "guerrier", "force": 1.0}])
	var causes := BancContagion.causes_de_attache([porteur_solo], "guerrier", "porteur_solo")
	verif.v(causes.is_empty(), "un colon qui s'interroge lui-meme ne doit jamais se compter comme sa propre cause")

func _causes_de_attache_ignore_attache_sans_propriete_visee() -> void:
	var colon_eau := _colon("colon_eau", Vector3(5.0, 0.0, 0.0), [{"propriete": "eau", "force": 1.0}])
	var causes := BancContagion.causes_de_attache([colon_eau], "guerrier", "un_autre_id")
	verif.v(causes.is_empty(), "une attache qui ne porte pas la propriete visee ne doit jamais produire de cause")

func _fixture_pipeline() -> Dictionary:
	var donnees := _donnees_banc_reelles()
	var propriete_visee: String = donnees.get("propriete_visee", "")
	var canal: Dictionary = donnees.get("canal", {}).duplicate(true)
	var porteur_1 := _colon("porteur_1", Vector3(50.0, 0.0, 0.0), [{"propriete": propriete_visee, "force": 1.0}])
	var porteur_2 := _colon("porteur_2", Vector3(-50.0, 0.0, 0.0), [{"propriete": propriete_visee, "force": 1.0}])
	var recepteur := _colon("recepteur_test", Vector3.ZERO, [], {"pression_guerrier": canal})
	return {"colons": [porteur_1, porteur_2, recepteur], "propriete_visee": propriete_visee}

func _pipeline_charge_franchit_seuil() -> void:
	var fixture := _fixture_pipeline()
	var colons: Array = fixture.colons
	var propriete_visee: String = fixture.propriete_visee
	var recepteur: Dictionary = colons[2]

	for i in 5:
		var causes := BancContagion.causes_de_attache(colons, propriete_visee, recepteur.id)
		Charge.avancer(colons, causes, DELTA_TICK)
	verif.v(not recepteur.proprietes.has("sous_pression_guerrier"),
		"apres seulement 5 ticks, la charge ne doit pas encore avoir franchi le seuil reel")

	for i in 10:
		var causes := BancContagion.causes_de_attache(colons, propriete_visee, recepteur.id)
		Charge.avancer(colons, causes, DELTA_TICK)
	verif.v(recepteur.proprietes.get("sous_pression_guerrier", false) == true,
		"apres 15 ticks au total, deux voisins porteurs dans la portee reelle doivent avoir fait franchir le seuil")

func _pipeline_charge_redescend_si_causes_disparaissent() -> void:
	var fixture := _fixture_pipeline()
	var colons: Array = fixture.colons
	var propriete_visee: String = fixture.propriete_visee
	var recepteur: Dictionary = colons[2]

	for i in 15:
		var causes := BancContagion.causes_de_attache(colons, propriete_visee, recepteur.id)
		Charge.avancer(colons, causes, DELTA_TICK)
	verif.v(recepteur.proprietes.get("sous_pression_guerrier", false) == true,
		"precondition : le seuil doit avoir ete franchi avant de tester la redescente")

	for i in 30:
		Charge.avancer(colons, [], DELTA_TICK)
	verif.v(not recepteur.proprietes.has("sous_pression_guerrier"),
		"une fois les causes disparues (plus aucun voisin porteur), la charge doit redescendre sous le seuil et retirer la propriete -- reversibilite de charge.gd")

func _resumabilite_des_colons() -> void:
	var fixture := _fixture_pipeline()
	var colons: Array = fixture.colons
	var propriete_visee: String = fixture.propriete_visee
	var recepteur: Dictionary = colons[2]

	for i in 15:
		var causes := BancContagion.causes_de_attache(colons, propriete_visee, recepteur.id)
		Charge.avancer(colons, causes, DELTA_TICK)

	var texte := JSON.stringify(colons)
	var relus: Variant = JSON.parse_string(texte)
	verif.v(relus != null, "JSON.stringify puis parse_string doit reussir sans erreur sur la liste de colons")

	var causes_originales := BancContagion.causes_de_attache(colons, propriete_visee, recepteur.id)
	var causes_relues := BancContagion.causes_de_attache(relus, propriete_visee, recepteur.id)
	verif.v(causes_relues.size() == causes_originales.size(),
		"causes_de_attache doit rendre le meme nombre de causes avant et apres un aller-retour JSON")

	var recepteur_relu: Dictionary = relus[2]
	verif.v(recepteur_relu.proprietes.get("sous_pression_guerrier", false) == recepteur.proprietes.get("sous_pression_guerrier", false),
		"l'etat sous_pression_guerrier doit survivre identique a l'aller-retour JSON")
	verif.v(is_equal_approx(
		recepteur_relu.proprietes.etats.pression_guerrier.charge,
		recepteur.proprietes.etats.pression_guerrier.charge,
	), "la charge exacte doit survivre identique a l'aller-retour JSON")

# Audit couverture 2026-08-06 : _porte_attache/_couleur_de sont des
# fonctions INSTANCE, aucune appelee par un test avant cette session.
# Meme patron que les autres bancs : BancContagion.new() nu, jamais
# ajoute a l'arbre. _couleur_de(colon) delegue entierement a
# _porte_attache -- teste ensemble, la couleur EST la traduction visuelle
# directe du booleen.
func _porte_attache_et_couleur_de_distinguent_porteur_et_non_porteur() -> void:
	var b := BancContagion.new()
	b._propriete_visee = "guerrier"
	b._couleur_porteur = Color(0.9, 0.1, 0.1)
	b._couleur_non_porteur = Color(0.2, 0.2, 0.2)

	var porteur := {"proprietes": {"attaches": [{"propriete": "guerrier", "force": 1.0}]}}
	var non_porteur := {"proprietes": {"attaches": [{"propriete": "autre_chose", "force": 1.0}]}}
	var sans_attache := {"proprietes": {"attaches": []}}

	verif.v(b._porte_attache(porteur), "un colon avec l'attache visee doit etre detecte comme porteur")
	verif.v(not b._porte_attache(non_porteur), "un colon avec une AUTRE attache ne doit jamais compter comme porteur")
	verif.v(not b._porte_attache(sans_attache), "un colon sans attache ne doit jamais compter comme porteur")

	verif.v(b._couleur_de(porteur) == Color(0.9, 0.1, 0.1), "un porteur doit rendre la couleur porteur, pas le defaut")
	verif.v(b._couleur_de(non_porteur) == Color(0.2, 0.2, 0.2), "un non-porteur doit rendre la couleur non-porteur")
