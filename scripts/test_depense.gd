extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_depense.gd
#
# Verrouille scripts/depense.gd comme MODELE GENERIQUE DE DEPENSE, pas comme
# un code de faim ou de fatigue. Une chose porte un ENSEMBLE NOMME de
# reserves (energie, matiere...), chacune ponctionnee independamment par un
# cout_base (son etat) et un surcout_action (son action en cours), deja
# resolus en nombres -- le script ne lit aucun nom d'action, d'etat ni de
# reserve. Un canal ne porte plus ses seuils EN VALEUR : "seuils_ref"
# reference une entree du catalogue (parametre, meme modele que
# "transformation" dans extinction.gd) ; l'instance garde seulement l'ETAT
# ("seuils_franchis", des indices) -- le catalogue n'est jamais mute.
#
# Fonction pure : aucune couche, aucun noeud, aucun rendu.

const Depense = preload("res://scripts/depense.gd")
const Verif = preload("res://scripts/verif.gd")

func _init() -> void:
	var v := Verif.new()
	_sans_reserves_rien_ne_bouge(v)
	_cout_base_seul_fait_decroitre(v)
	_surcout_s_additionne_au_cout_base(v)
	_seuil_s_applique_une_seule_fois(v)
	_seuils_en_escalier_independants(v)
	_delta_large_franchit_deux_seuils_dans_l_ordre(v)
	_reference_de_seuils_absente_du_catalogue_alarme(v)
	_le_modele_ignore_le_domaine(v)
	_reserve_bornee_a_zero_jamais_negative(v)
	_valeur_posee_par_un_seuil_est_une_copie_jamais_une_reference(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: une chose porte un ensemble nomme de reserves, cout_base + surcout_action " +
			"ponctionnent chacune independamment, chaque seuil franchi applique sa transformation " +
			"une fois sur proprietes, en donnee, depuis une reference de catalogue jamais mutee")
		quit(0)

func _canal(reserve: float, cout_base: float, surcout: float, seuils_ref: String = "") -> Dictionary:
	return {
		"reserve": reserve,
		"cout_base": cout_base,
		"surcout_action": surcout,
		"seuils_ref": seuils_ref,
	}

func _chose(id: String, canaux: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var proprietes := {"reserves": canaux}
	for cle in extra:
		proprietes[cle] = extra[cle]
	return {"id": id, "position": Vector3.ZERO, "proprietes": proprietes}

func _sans_reserves_rien_ne_bouge(v) -> void:
	var monde := [{"id": "x", "position": Vector3.ZERO, "proprietes": {}}]
	var f := Depense.avancer(monde, 1.0)
	v.v(f.is_empty(), "sans reserves, rien ne doit etre rendu comme franchi")
	v.v(not monde[0].proprietes.has("reserves"), "sans reserves, aucune cle ne doit apparaitre")

func _cout_base_seul_fait_decroitre(v) -> void:
	var monde := [_chose("a", {"energie": _canal(10.0, 2.0, 0.0)})]
	Depense.avancer(monde, 1.0)
	v.v(monde[0].proprietes.reserves.energie.reserve == 8.0,
		"cout_base seul doit ponctionner la reserve de cout_base * delta")

func _surcout_s_additionne_au_cout_base(v) -> void:
	var sans_surcout := [_chose("a", {"energie": _canal(10.0, 1.0, 0.0)})]
	var avec_surcout := [_chose("b", {"energie": _canal(10.0, 1.0, 2.0)})]
	Depense.avancer(sans_surcout, 1.0)
	Depense.avancer(avec_surcout, 1.0)
	v.v(avec_surcout[0].proprietes.reserves.energie.reserve < sans_surcout[0].proprietes.reserves.energie.reserve,
		"surcout_action doit s'additionner au cout_base, pas le remplacer")

func _seuil_s_applique_une_seule_fois(v) -> void:
	var catalogue := {
		"vif_faible": [{"seuil": 0.0, "retirer": ["vif"], "poser": {"faible": true}}],
	}
	var monde := [_chose("a", {"energie": _canal(5.0, 10.0, 0.0, "vif_faible")}, {"vif": true})]
	var f1 := Depense.avancer(monde, 1.0, catalogue)
	var p: Dictionary = monde[0].proprietes
	v.v(f1.has("a"), "franchir un seuil doit rendre l'id de la chose")
	v.v(not p.has("vif"), "le seuil franchi doit retirer vif sur proprietes")
	v.v(p.get("faible", false), "le seuil franchi doit poser faible sur proprietes")
	var f2 := Depense.avancer(monde, 1.0, catalogue)
	v.v(not f2.has("a"), "un seuil deja applique ne doit pas se redeclencher")
	v.v(catalogue.vif_faible.size() == 1,
		"le catalogue n'est jamais mute : la definition reste presente apres application")

# HORS DOMAINE. Ce que pose un seuil est une COPIE, jamais la reference du
# catalogue : deux choses qui franchissent le MEME seuil ne partagent aucune
# sous-structure, et le catalogue reste intact. Ce fichier mutant ses canaux
# en place, une reference partagee ferait ecrire sur toutes a la fois.
func _valeur_posee_par_un_seuil_est_une_copie_jamais_une_reference(v) -> void:
	var catalogue := {
		"zorg": [{"seuil": 0.0, "poser": {"bac": {"niveau": 1.0}, "paliers": ["a"]}}],
	}
	var monde := [
		_chose("a", {"plif": _canal(1.0, 10.0, 0.0, "zorg")}),
		_chose("b", {"plif": _canal(1.0, 10.0, 0.0, "zorg")}),
	]
	Depense.avancer(monde, 1.0, catalogue)
	var pa: Dictionary = monde[0].proprietes
	var pb: Dictionary = monde[1].proprietes
	v.v(pa.has("bac") and pb.has("bac"), "les deux choses doivent avoir franchi le seuil")
	pa.bac.niveau = 99.0
	pa.paliers.append("z")
	v.v(pb.bac.niveau == 1.0,
		"deux choses ne doivent jamais partager le Dictionary pose par un seuil")
	v.v(pb.paliers.size() == 1,
		"deux choses ne doivent jamais partager l'Array pose par un seuil")
	v.v(catalogue.zorg[0].poser.bac.niveau == 1.0,
		"le catalogue ne doit jamais etre mute par une pose")

func _seuils_en_escalier_independants(v) -> void:
	var catalogue := {
		"alerte_critique": [
			{"seuil": 10.0, "retirer": [], "poser": {"alerte": true}},
			{"seuil": 0.0, "retirer": [], "poser": {"critique": true}},
		],
	}
	var monde := [_chose("a", {"energie": _canal(20.0, 10.0, 0.0, "alerte_critique")})]
	Depense.avancer(monde, 1.0, catalogue)
	var p: Dictionary = monde[0].proprietes
	v.v(p.get("alerte", false), "le premier seuil franchi doit poser alerte")
	v.v(not p.has("critique"), "le second seuil ne doit pas s'appliquer avant d'etre franchi")
	v.v(p.reserves.energie.seuils_franchis.size() == 1, "seul le seuil franchi doit rejoindre l'etat de l'instance")
	Depense.avancer(monde, 1.0, catalogue)
	v.v(p.get("critique", false), "le second seuil doit s'appliquer quand la reserve le franchit a son tour")
	v.v(catalogue.alerte_critique.size() == 2, "le catalogue garde ses deux definitions, jamais purgees")

func _delta_large_franchit_deux_seuils_dans_l_ordre(v) -> void:
	var catalogue := {
		"haut_bas": [
			{"seuil": 10.0, "retirer": [], "poser": {"ordre": "haut", "trace_haut": true}},
			{"seuil": 0.0, "retirer": [], "poser": {"ordre": "bas", "trace_bas": true}},
		],
	}
	var monde := [_chose("a", {"energie": _canal(20.0, 10.0, 0.0, "haut_bas")})]
	var f := Depense.avancer(monde, 3.0, catalogue)
	var p: Dictionary = monde[0].proprietes
	v.v(f.has("a"), "un delta qui franchit deux seuils d'un coup doit rendre l'id de la chose")
	v.v(p.get("trace_haut", false), "le seuil du haut doit s'appliquer")
	v.v(p.get("trace_bas", false), "le seuil du bas doit s'appliquer dans le meme pas")
	v.v(p.get("ordre") == "bas",
		"le seuil du bas, applique en dernier, doit ecraser la trace du seuil du haut : preuve de l'ordre haut -> bas")
	v.v(p.reserves.energie.seuils_franchis.size() == 2, "les deux seuils franchis doivent rejoindre l'etat de l'instance")

# STRUCTUREL, meme forme que "transformation" dans extinction.gd : un canal
# qui reference un seuils_ref absent du catalogue alarme et n'applique rien,
# jamais un 0.0 silencieux qui se confondrait avec "aucun seuil a surveiller".
func _reference_de_seuils_absente_du_catalogue_alarme(v) -> void:
	var monde := [_chose("a", {"energie": _canal(0.0, 0.0, 0.0, "reference_inconnue")})]
	var f := Depense.avancer(monde, 1.0, {})
	v.v(f.is_empty(), "une reference de seuils absente du catalogue ne doit rien franchir")

# LA serrure generaliste : une chose sans rapport avec faim/fatigue s'accomplit
# par le MEME code, ET deux reserves independantes sur le meme objet (un
# animal a besoin d'energie ET de matiere) ne se marchent jamais dessus. Si ce
# test passe, depense.gd ne connait ni domaine ni nombre de reserves par objet.
func _le_modele_ignore_le_domaine(v) -> void:
	var catalogue := {
		"energie_seuils": [{"seuil": 0.0, "retirer": ["operationnel"], "poser": {"hors_service": true}}],
		"lubrifiant_seuils": [{"seuil": 10.0, "retirer": [], "poser": {"grippe": true}}],
	}
	var canaux := {
		"energie": _canal(3.0, 5.0, 0.0, "energie_seuils"),
		"lubrifiant": _canal(20.0, 1.0, 0.0, "lubrifiant_seuils"),
	}
	var monde := [_chose("gadget_1", canaux, {"operationnel": true})]
	var f := Depense.avancer(monde, 1.0, catalogue)
	var p: Dictionary = monde[0].proprietes
	v.v(f.has("gadget_1"), "un objet hors de tout domaine connu doit franchir un seuil par le meme code")
	v.v(not p.has("operationnel"), "le seuil d'energie doit retirer operationnel sur proprietes")
	v.v(p.get("hors_service", false), "le seuil d'energie doit poser hors_service sur proprietes")
	v.v(not p.has("grippe"), "le seuil de lubrifiant (10.0) n'est pas encore franchi : 20.0 - 1.0*1.0 = 19.0")
	v.v(p.reserves.lubrifiant.reserve == 19.0,
		"lubrifiant se ponctionne independamment d'energie, sur le meme objet")

# BORNE BASSE (bug ferme 2026-08-07) : un delta assez grand pour ponctionner
# bien au-dela de la reserve disponible doit s'arreter EXACTEMENT a 0.0,
# jamais descendre en negatif -- verifie sur un seul pas (delta large) ET
# sur plusieurs pas successifs une fois deja a zero (une reserve epuisee
# reste epuisee, elle ne redescend jamais).
func _reserve_bornee_a_zero_jamais_negative(v) -> void:
	var monde := [_chose("a", {"energie": _canal(5.0, 10.0, 0.0)})]
	Depense.avancer(monde, 3.0)
	v.v(monde[0].proprietes.reserves.energie.reserve == 0.0,
		"un delta qui ponctionnerait bien au-dela de la reserve disponible (5.0 - 30.0) doit la borner a 0.0, jamais negative")
	Depense.avancer(monde, 5.0)
	v.v(monde[0].proprietes.reserves.energie.reserve == 0.0,
		"une reserve deja a 0.0 doit y rester sur les pas suivants, jamais redescendre en negatif")
