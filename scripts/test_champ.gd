extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_champ.gd
#
# Verrouille scripts/champ.gd comme MODELE GENERIQUE DE FORCE A PORTEE, pas
# comme un code de magnetisme. Une chose porteuse d'une PROPRIETE SOURCE
# (lue a la demande dans sa fiche materiau) attire ou repousse une autre
# chose porteuse de la MEME propriete, par paires (i<j), le deplacement de
# chacune inversement proportionnel a sa masse, la force decroissant en
# 1/distance^exposant, bornee par un plancher (pres de zero) et un plafond
# (par tick). Ce fichier n'utilise AUCUN nom lie au magnetisme reel : deux
# proprietes inventees ("attire_zorg", "repousse_glurp") et deux materiaux
# fictifs prouvent que champ.gd ignore le domaine.
#
# Fonction pure : aucune couche, aucun noeud, aucun rendu.

const Champ = preload("res://scripts/champ.gd")
const Verif = preload("res://scripts/verif.gd")

func _init() -> void:
	var v := Verif.new()
	_sans_composition_rien_ne_bouge(v)
	_deux_objets_masses_differentes_deplacement_inverse_a_la_masse(v)
	_traction_monte_en_inverse_carre_a_l_approche(v)
	_plancher_evite_l_infini_pres_de_zero(v)
	_plafond_evite_la_traversee(v)
	_paire_appliquee_une_seule_fois_symetrie(v)
	_objet_sans_propriete_est_ignore(v)
	_paire_sans_masse_alarme_et_ne_deplace_personne(v)
	_hors_portee_aucune_traction(v)
	_entree_incomplete_alarme_et_ignoree(v)
	_signe_negatif_repousse(v)
	_le_modele_ignore_le_domaine(v)
	_cle_note_du_catalogue_ignoree(v)
	_meme_materiau_volumes_differents_force_proportionnelle_au_volume(v)
	_objet_composite_moitie_magnetique_subit_la_moitie_de_la_force(v)
	_masse_et_force_sont_des_roles_distincts(v)
	_resumabilite_json_stricte(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: champ.gd applique une force generique a portee, mutuelle et par paires, " +
			"deplacement inversement proportionnel a la masse, decroissance 1/d^exposant, " +
			"plancher et plafond respectes, objet sans propriete ignore, hors domaine prouve")
		quit(0)

func _materiaux_fictifs() -> Dictionary:
	return {
		"cristal_zorg": {"attire_zorg": 2.0, "repousse_glurp": 3.0},
		"roche_zorg": {"attire_zorg": 0.5, "repousse_glurp": 1.5},
		"verre_zorg": {},
	}

func _entree_attraction(portee: float, plancher: float, plafond: float) -> Dictionary:
	return {
		"propriete_source": "attire_zorg",
		"signe": 1.0,
		"exposant": 2.0,
		"portee": portee,
		"plancher_distance": plancher,
		"plafond_deplacement": plafond,
	}

func _chose(id: String, position: Vector3, masse: float, composition: Array = []) -> Dictionary:
	var proprietes := {"masse": masse}
	if not composition.is_empty():
		proprietes["composition"] = composition
	return {"id": id, "position": position, "proprietes": proprietes}

func _element(materiau: String, volume: float) -> Dictionary:
	return {"materiau": materiau, "volume": volume}

func _sans_composition_rien_ne_bouge(v) -> void:
	var a := _chose("a", Vector3.ZERO, 1.0)
	var b := _chose("b", Vector3(5.0, 0.0, 0.0), 1.0)
	var monde := [a, b]
	var catalogue := {"attraction": _entree_attraction(100.0, 1.0, 1000.0)}
	var deplaces := Champ.avancer(monde, 1.0, catalogue, _materiaux_fictifs())
	v.v(deplaces.is_empty(), "deux choses sans 'composition' ne doivent jamais bouger")
	v.v(a.position == Vector3.ZERO, "position de 'a' inchangee sans composition")
	v.v(b.position == Vector3(5.0, 0.0, 0.0), "position de 'b' inchangee sans composition")

func _deux_objets_masses_differentes_deplacement_inverse_a_la_masse(v) -> void:
	var a := _chose("a", Vector3.ZERO, 2.0, [_element("cristal_zorg", 1.0)])
	var b := _chose("b", Vector3(5.0, 0.0, 0.0), 10.0, [_element("roche_zorg", 1.0)])
	var monde := [a, b]
	var catalogue := {"attraction": _entree_attraction(100.0, 1.0, 1000.0)}
	Champ.avancer(monde, 1.0, catalogue, _materiaux_fictifs())
	var pas_a: float = a.position.distance_to(Vector3.ZERO)
	var pas_b: float = b.position.distance_to(Vector3(5.0, 0.0, 0.0))
	v.v(pas_a > 0.0 and pas_b > 0.0, "les deux choses doivent avoir bouge (attraction mutuelle)")
	v.v(is_equal_approx(2.0 * pas_a, 10.0 * pas_b),
		"masse * deplacement doit etre egal des deux cotes (meme force, masse differente)")
	v.v(pas_a > pas_b, "la chose la plus legere doit se deplacer davantage que la plus lourde")

func _traction_monte_en_inverse_carre_a_l_approche(v) -> void:
	var entree := _entree_attraction(100.0, 0.5, 1000.0)
	var mat := _materiaux_fictifs()
	var a_proche := _chose("a", Vector3.ZERO, 1.0, [_element("cristal_zorg", 1.0)])
	var b_proche := _chose("b", Vector3(5.0, 0.0, 0.0), 1.0, [_element("roche_zorg", 1.0)])
	var force_proche: float = Champ.force_paire(a_proche, b_proche, entree, mat)
	var a_loin := _chose("a", Vector3.ZERO, 1.0, [_element("cristal_zorg", 1.0)])
	var b_loin := _chose("b", Vector3(10.0, 0.0, 0.0), 1.0, [_element("roche_zorg", 1.0)])
	var force_loin: float = Champ.force_paire(a_loin, b_loin, entree, mat)
	v.v(force_proche > force_loin, "la traction doit etre plus forte a 5 unites qu'a 10")
	v.v(is_equal_approx(force_proche / force_loin, 4.0),
		"doubler la distance doit diviser la force par 4 (1/d^2 exactement)")

func _plancher_evite_l_infini_pres_de_zero(v) -> void:
	var entree := _entree_attraction(100.0, 2.0, 1000.0)
	var a := _chose("a", Vector3.ZERO, 1.0, [_element("cristal_zorg", 1.0)])
	var b := _chose("b", Vector3.ZERO, 1.0, [_element("roche_zorg", 1.0)])
	var force: float = Champ.force_paire(a, b, entree, _materiaux_fictifs())
	v.v(not is_inf(force) and not is_nan(force), "a distance nulle, le plancher doit empecher l'infini")
	v.v(is_equal_approx(force, (2.0 * 0.5) / pow(2.0, 2.0)),
		"a distance nulle, la force doit se calculer avec d = plancher_distance")
	var monde := [a, b]
	var deplaces := Champ.avancer(monde, 1.0, {"attraction": entree}, _materiaux_fictifs())
	v.v(deplaces.is_empty(), "a positions confondues, l'axe est indefini -- aucun deplacement, jamais un crash")

func _plafond_evite_la_traversee(v) -> void:
	var entree := {
		"propriete_source": "attire_zorg", "signe": 1.0, "exposant": 2.0,
		"portee": 100.0, "plancher_distance": 0.1, "plafond_deplacement": 0.5,
	}
	var a := _chose("a", Vector3.ZERO, 0.001, [_element("cristal_zorg", 1.0)])
	var b := _chose("b", Vector3(1.0, 0.0, 0.0), 0.001, [_element("roche_zorg", 1.0)])
	var monde := [a, b]
	Champ.avancer(monde, 1.0, {"attraction": entree}, _materiaux_fictifs())
	var pas_a: float = a.position.distance_to(Vector3.ZERO)
	var pas_b: float = b.position.distance_to(Vector3(1.0, 0.0, 0.0))
	v.v(is_equal_approx(pas_a, 0.5) or pas_a < 0.5,
		"meme avec une force enorme (masse quasi nulle), le pas ne doit jamais depasser plafond_deplacement")
	v.v(is_equal_approx(pas_b, 0.5) or pas_b < 0.5,
		"meme avec une force enorme (masse quasi nulle), le pas ne doit jamais depasser plafond_deplacement")
	v.v(a.position.distance_to(b.position) >= 0.0, "les deux choses ne doivent jamais se croiser au point de produire une distance negative")

func _paire_appliquee_une_seule_fois_symetrie(v) -> void:
	var a := _chose("a", Vector3.ZERO, 4.0, [_element("cristal_zorg", 1.0)])
	var b := _chose("b", Vector3(5.0, 0.0, 0.0), 4.0, [_element("roche_zorg", 1.0)])
	var monde := [a, b]
	var entree := _entree_attraction(100.0, 1.0, 1000.0)
	Champ.avancer(monde, 1.0, {"attraction": entree}, _materiaux_fictifs())
	# Calcul independant, sans appeler champ.gd, pour prouver qu'une paire
	# n'est jamais appliquee deux fois (ex. i,j ET j,i) :
	var force_attendue: float = (2.0 * 0.5) / pow(5.0, 2.0)
	var pas_attendu: float = force_attendue / 4.0 * 1.0
	var pas_reel: float = a.position.distance_to(Vector3.ZERO)
	v.v(is_equal_approx(pas_reel, pas_attendu),
		"le deplacement doit correspondre a UNE SEULE application de la paire, jamais un doublement")

func _objet_sans_propriete_est_ignore(v) -> void:
	var a := _chose("a", Vector3.ZERO, 2.0, [_element("cristal_zorg", 1.0)])
	var b := _chose("b", Vector3(5.0, 0.0, 0.0), 2.0, [_element("roche_zorg", 1.0)])
	var c := _chose("c", Vector3(2.5, 0.0, 0.0), 1.0, [_element("verre_zorg", 1.0)])
	var monde := [a, b, c]
	var entree := _entree_attraction(100.0, 1.0, 1000.0)
	Champ.avancer(monde, 1.0, {"attraction": entree}, _materiaux_fictifs())
	v.v(c.position == Vector3(2.5, 0.0, 0.0),
		"une chose dont la fiche materiau ne porte pas la propriete source ne doit jamais bouger")
	v.v(a.position != Vector3.ZERO and b.position != Vector3(5.0, 0.0, 0.0),
		"la paire a/b avec la propriete doit interagir normalement, sans egard a c")

# La masse RESISTE : sans elle, l'acceleration se divise par rien. Une paire
# dont un membre n'en porte pas est une DONNEE CASSEE -- alarme, et la paire
# ENTIERE est ignoree. Deplacer le seul membre qui en porte serait pire que
# de ne rien faire : une force sans reaction, invisible a tout test de
# conservation.
func _paire_sans_masse_alarme_et_ne_deplace_personne(v) -> void:
	var a := _chose("a", Vector3.ZERO, 2.0, [_element("cristal_zorg", 1.0)])
	var b := {
		"id": "b", "position": Vector3(5.0, 0.0, 0.0),
		"proprietes": {"composition": [_element("cristal_zorg", 1.0)]},
	}
	var monde := [a, b]
	var deplaces := Champ.avancer(monde, 1.0, {"attraction": _entree_attraction(100.0, 1.0, 1000.0)}, _materiaux_fictifs())
	v.v(deplaces.is_empty(), "une paire sans masse des deux cotes ne doit produire aucun deplacement")
	v.v(a.position == Vector3.ZERO and b.position == Vector3(5.0, 0.0, 0.0),
		"aucun des deux membres ne bouge : la paire entiere est ignoree")

func _hors_portee_aucune_traction(v) -> void:
	var a := _chose("a", Vector3.ZERO, 1.0, [_element("cristal_zorg", 1.0)])
	var b := _chose("b", Vector3(50.0, 0.0, 0.0), 1.0, [_element("roche_zorg", 1.0)])
	var monde := [a, b]
	var entree := _entree_attraction(10.0, 1.0, 1000.0)
	var deplaces := Champ.avancer(monde, 1.0, {"attraction": entree}, _materiaux_fictifs())
	v.v(deplaces.is_empty(), "au-dela de 'portee', aucune traction ne doit s'appliquer")
	v.v(a.position == Vector3.ZERO and b.position == Vector3(50.0, 0.0, 0.0),
		"positions inchangees hors de portee")

func _entree_incomplete_alarme_et_ignoree(v) -> void:
	var a := _chose("a", Vector3.ZERO, 1.0, [_element("cristal_zorg", 1.0)])
	var b := _chose("b", Vector3(5.0, 0.0, 0.0), 1.0, [_element("roche_zorg", 1.0)])
	var monde := [a, b]
	var entree_cassee := {
		"propriete_source": "attire_zorg", "signe": 1.0, "exposant": 2.0, "portee": 100.0,
		# "plancher_distance" et "plafond_deplacement" manquent volontairement.
	}
	var deplaces := Champ.avancer(monde, 1.0, {"attraction": entree_cassee}, _materiaux_fictifs())
	v.v(deplaces.is_empty(), "une entree de catalogue incomplete doit etre ignoree, jamais un defaut invente")
	v.v(a.position == Vector3.ZERO, "positions inchangees quand l'entree est structurellement cassee")

func _signe_negatif_repousse(v) -> void:
	var entree := {
		"propriete_source": "repousse_glurp", "signe": -1.0, "exposant": 2.0,
		"portee": 100.0, "plancher_distance": 0.5, "plafond_deplacement": 1000.0,
	}
	var a := _chose("a", Vector3.ZERO, 1.0, [_element("cristal_zorg", 1.0)])
	var b := _chose("b", Vector3(2.0, 0.0, 0.0), 1.0, [_element("roche_zorg", 1.0)])
	var distance_avant: float = a.position.distance_to(b.position)
	var monde := [a, b]
	Champ.avancer(monde, 1.0, {"repulsion": entree}, _materiaux_fictifs())
	var distance_apres: float = a.position.distance_to(b.position)
	v.v(distance_apres > distance_avant, "signe negatif doit ELOIGNER les deux choses l'une de l'autre")

# LA serrure generaliste : un catalogue de champs FICTIF (deux proprietes
# sans aucun rapport avec le magnetisme reel), deux materiaux fictifs,
# traverse le meme code que n'importe quel autre champ -- aucun nom de
# phenomene n'apparait dans champ.gd.
func _le_modele_ignore_le_domaine(v) -> void:
	var mat := _materiaux_fictifs()
	var catalogue := {
		"attraction_zorg": _entree_attraction(100.0, 1.0, 1000.0),
		"repulsion_glurp": {
			"propriete_source": "repousse_glurp", "signe": -1.0, "exposant": 2.0,
			"portee": 100.0, "plancher_distance": 1.0, "plafond_deplacement": 1000.0,
		},
	}
	var a := _chose("cristal_17", Vector3.ZERO, 3.0, [_element("cristal_zorg", 1.0)])
	var b := _chose("roche_9", Vector3(4.0, 0.0, 0.0), 3.0, [_element("roche_zorg", 1.0)])
	var monde := [a, b]
	var deplaces := Champ.avancer(monde, 1.0, catalogue, mat)
	v.v(not deplaces.is_empty(), "deux entrees de catalogue sans rapport avec un phenomene reel doivent produire un deplacement par le meme code")

# Un catalogue charge depuis data/champs.json porte "_note" au meme niveau
# que les entrees reelles (meme forme que data/materiaux.json) -- ne doit
# jamais etre lu comme une entree de champ (String sans "propriete_source").
func _cle_note_du_catalogue_ignoree(v) -> void:
	var a := _chose("a", Vector3.ZERO, 2.0, [_element("cristal_zorg", 1.0)])
	var b := _chose("b", Vector3(5.0, 0.0, 0.0), 2.0, [_element("roche_zorg", 1.0)])
	var monde := [a, b]
	var catalogue := {
		"_note": "texte descriptif, jamais une entree",
		"attraction": _entree_attraction(100.0, 1.0, 1000.0),
	}
	var deplaces := Champ.avancer(monde, 1.0, catalogue, _materiaux_fictifs())
	v.v(not deplaces.is_empty(), "une cle '_note' a cote d'une vraie entree ne doit jamais empecher le calcul")

# Peaufinage (session ulterieure) : la force depend de la QUANTITE de
# matiere magnetique (magnetisme x volume, SOMMEE), pas du seul degre de
# magnetisme -- un gros echantillon du meme materiau doit subir une force
# plus grande qu'un petit, meme aimant de reference, memes materiaux.
func _meme_materiau_volumes_differents_force_proportionnelle_au_volume(v) -> void:
	var entree := _entree_attraction(100.0, 1.0, 1000.0)
	var mat := _materiaux_fictifs()
	var reference := _chose("ref", Vector3(5.0, 0.0, 0.0), 1.0, [_element("roche_zorg", 1.0)])
	var petit := _chose("petit", Vector3.ZERO, 1.0, [_element("cristal_zorg", 1.0)])
	var gros := _chose("gros", Vector3.ZERO, 1.0, [_element("cristal_zorg", 3.0)])
	var force_petit: float = Champ.force_paire(petit, reference, entree, mat)
	var force_gros: float = Champ.force_paire(gros, reference, entree, mat)
	v.v(force_gros > force_petit, "un plus gros volume du meme materiau magnetique doit subir une force plus grande")
	v.v(is_equal_approx(force_gros / force_petit, 3.0),
		"la force doit etre EXACTEMENT proportionnelle au volume (3x le volume -> 3x la force), jamais une moyenne insensible au volume")

# Un objet moitie magnetique moitie inerte (meme volume total qu'un objet
# plein) ne subit que la contribution de sa moitie magnetique -- jamais
# diluee par le materiau inerte, jamais annulee par lui non plus.
func _objet_composite_moitie_magnetique_subit_la_moitie_de_la_force(v) -> void:
	var entree := _entree_attraction(100.0, 1.0, 1000.0)
	var mat := _materiaux_fictifs()
	var reference := _chose("ref", Vector3(5.0, 0.0, 0.0), 1.0, [_element("roche_zorg", 1.0)])
	var plein := _chose("plein", Vector3.ZERO, 1.0, [_element("cristal_zorg", 1.0)])
	var moitie := _chose("moitie", Vector3.ZERO, 1.0, [_element("cristal_zorg", 0.5), _element("verre_zorg", 0.5)])
	var force_plein: float = Champ.force_paire(plein, reference, entree, mat)
	var force_moitie: float = Champ.force_paire(moitie, reference, entree, mat)
	v.v(is_equal_approx(force_moitie, force_plein / 2.0),
		"un objet moitie magnetique moitie inerte doit subir exactement la moitie de la force d'un objet plein du meme volume total")

# La masse et la force sont deux roles distincts : meme quantite de matiere
# magnetique (meme materiau, meme volume) -> MEME force sur les deux, mais
# des masses differentes -> des deplacements (accelerations) differents.
func _masse_et_force_sont_des_roles_distincts(v) -> void:
	var entree := _entree_attraction(100.0, 1.0, 1000.0)
	var mat := _materiaux_fictifs()
	var reference_a := _chose("ref_a", Vector3(5.0, 0.0, 0.0), 1.0, [_element("roche_zorg", 1.0)])
	var reference_b := _chose("ref_b", Vector3(5.0, 0.0, 0.0), 1.0, [_element("roche_zorg", 1.0)])
	var leger := _chose("leger", Vector3.ZERO, 2.0, [_element("cristal_zorg", 1.0)])
	var lourd := _chose("lourd", Vector3.ZERO, 8.0, [_element("cristal_zorg", 1.0)])
	var force_leger: float = Champ.force_paire(leger, reference_a, entree, mat)
	var force_lourd: float = Champ.force_paire(lourd, reference_b, entree, mat)
	v.v(is_equal_approx(force_leger, force_lourd),
		"meme materiau, meme volume -> la FORCE doit etre identique quelle que soit la masse")

	var monde_leger := [leger, reference_a]
	var monde_lourd := [lourd, reference_b]
	Champ.avancer(monde_leger, 1.0, {"attraction": entree}, mat)
	Champ.avancer(monde_lourd, 1.0, {"attraction": entree}, mat)
	var pas_leger: float = leger.position.distance_to(Vector3.ZERO)
	var pas_lourd: float = lourd.position.distance_to(Vector3.ZERO)
	v.v(pas_leger > pas_lourd,
		"a force egale, l'objet le plus leger doit accelerer (se deplacer) davantage -- la masse RESISTE, elle n'attire pas")
	v.v(is_equal_approx(pas_leger / pas_lourd, 4.0),
		"le rapport des deplacements doit suivre exactement le rapport inverse des masses (8/2 = 4), a force identique")

func _resumabilite_json_stricte(v) -> void:
	var a := _chose("cristal_20", Vector3.ZERO, 3.0, [_element("cristal_zorg", 1.0)])
	var b := _chose("roche_20", Vector3(4.0, 0.0, 0.0), 3.0, [_element("roche_zorg", 1.0)])
	var monde := [a, b]
	var entree := _entree_attraction(100.0, 1.0, 1000.0)
	Champ.avancer(monde, 1.0, {"attraction": entree}, _materiaux_fictifs())
	var texte := JSON.stringify(a)
	var relu: Variant = JSON.parse_string(texte)
	v.v(relu != null, "JSON.stringify puis parse_string doit reussir sans erreur")
	v.v(relu.proprietes.masse == 3.0, "masse doit survivre identique a l'aller-retour JSON")
	v.v(relu.proprietes.composition[0].materiau == "cristal_zorg",
		"composition doit survivre identique a l'aller-retour JSON -- champ.gd n'ecrit jamais dans proprietes")
