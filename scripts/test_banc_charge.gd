extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_charge.gd
#
# Verrouille le cablage de banc_charge.gd, en particulier decider() et le
# mecanisme charge.gd (le "canal de charge") joue en jeu pour la
# PREMIERE fois (voir CARTE.md §2, charge.gd "Non cable a ce jour").
#
# Deux colons, memes couches, seul le SEUIL de charge differe (peureux 3.0,
# prudent 8.0) -- gain_jugement differe aussi (2.0/1.0, comme banc_feu.gd),
# mais ce n'est PAS ce qui declenche la bascule ici : les deux colons
# recoivent la MEME exposition (1 feu, meme portee), seul le nombre de
# ticks avant que CHAQUE seuil soit franchi diverge.
#
# - a peu de ticks (charge sous les deux seuils), les deux colons resolvent
#   encore "approcher" -- rien n'a change par rapport a un banc sans
#   charge.
# - apres exposition prolongee (4 ticks, charge 4.0), le peureux (seuil
#   3.0) a bascule : proprietes.effraye est pose, decider() resout
#   "s_eloigner" (poids_verbes le favorise). Le prudent (seuil 8.0) n'a
#   pas encore bascule : "approcher" encore.
# - a plus d'exposition (9 ticks, charge 9.0), le prudent bascule aussi :
#   "se_proteger" (poids_verbes le favorise chez lui).
# - sans plus aucune cause, la charge redescend (taux_decroissance) et
#   retire "effraye" -- le colon revient resoudre "approcher" des qu'un
#   feu est de nouveau perçu.
#
# _hors_domaine_decider_ignore_le_domaine() verrouille que decider() (le
# cablage propre a ce banc) ne code aucun nom en dur : un canal de charge
# et un couple jugee/declencheur inventes (rayonnement/contamine/bunker),
# sans aucun rapport avec le feu, traversent le meme cablage.
#
# PHASE 3 piece 2 (chantier "L'entite comme agent complet") : etats.peur a
# migre de data/banc_charge.json vers data/types.json:colon (herite_entite),
# seul son seuil reste surcharge par colon (prudent 8.0, peureux 3.0). Les
# trois derniers tests verrouillent ce chemin REEL (data/types.json et
# data/banc_charge.json lus sur disque, pas une fixture locale) : un colon
# fabrique directement herite bien portee_charge/taux_decroissance/poser/
# charge de data/types.json:colon.etats.peur ; le chemin complet de
# banc_charge.gd (_fabriquer_colon_charge) donne a prudent et peureux le
# meme canal herite mais chacun son propre seuil, sans jamais partager le
# meme Dictionary entre les deux colons ; et les colons REELS ainsi
# fabriques basculent bien effraye a des expositions differentes selon leur
# seuil surcharge -- meme comportement qu'avant le renommage/l'extraction,
# prouve de bout en bout plutot que par fixture locale.

const BancCharge = preload("res://scripts/banc_charge.gd")
const Charge = preload("res://scripts/charge.gd")
const Monde = preload("res://scripts/monde.gd")
const Objet = preload("res://scripts/objet.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

const TYPES := {
	"feu": { "profil_saillance": "feu", "brule": true },
	"abri": { "refuge": true },
}
const PROFILS_SAILLANCE := {
	"feu": { "saillance_intrinseque": 3.0, "portee_saillance": 900.0 },
}
const JUGEMENTS := { "refuge": "effraye" }
# PHASE 4 piece 3 (chantier "L'entite comme agent complet") : vide partout
# ici -- voir test_proximite_deformation.gd pour la deformation elle-meme,
# ce fichier verrouille seulement que le cablage la propage.
const CATALOGUE_DEFORMATIONS := {}
# Catalogue de canaux local (equivalent a data/canaux.json) : les deux
# colons ne portent que "vue" (aucun "angle" -- degenere en sphere, meme
# comportement que l'ancienne portee unique du colon).
const CATALOGUE_CANAUX := {
	"vue": { "geometrie": "cone_oriente" },
}
const CATALOGUE := {
	"brule": { "verbes": ["approcher"] },
	"refuge": { "verbes": ["se_proteger", "s_eloigner"] },
}
const ORIENTATIONS := { "se_proteger": "jugee", "s_eloigner": "fuite" }
const DECLENCHEUR_CHARGE := "brule"
const DECLENCHEUR_INTERNE := "effraye"
const INTENSITE_INTERNE := 4.0

func _init() -> void:
	_peu_de_feux_les_deux_eteignent()
	_exposition_prolongee_bascule_le_peureux_avant_le_prudent()
	_sans_cause_la_charge_redescend_et_effraye_se_retire()
	_hors_domaine_decider_ignore_le_domaine()
	_colon_reel_herite_de_etats_peur_de_colon()
	_colons_reels_surchargent_le_seuil_sans_partager_reference()
	_colon_reel_avec_surcharge_de_seuil_bascule_effraye_selon_seuil()
	_couleur_de_lit_le_type_pose_jamais_le_defaut()
	_etiquette_decision_cas()
	_faire_agir_colon_sans_feu_rend_rien_et_ne_bouge_pas()
	_faire_agir_colon_avec_feu_deplace_le_colon_et_redessine_le_noeud()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: a peu d'exposition les deux eteignent, exposition prolongee bascule le " +
		"peureux avant le prudent (meme seuil individuel, meme code), sans cause la charge " +
		"redescend et effraye se retire, un canal/declencheur invente traverse le meme cablage, " +
		"le colon reel herite etats.peur de data/types.json, chaque colon reel du banc surcharge " +
		"son propre seuil sans jamais partager de reference, et les colons reels basculent effraye " +
		"a des expositions differentes selon leur seuil surcharge")
	quit(0)

func _colon_charge(gain_jugement: float, seuil: float, poids_verbes: Dictionary) -> Dictionary:
	return {
		"id": "colon_test",
		"position": Vector3.ZERO,
		"proprietes": {
			"canaux": ["vue"], "canaux_config": {"vue": {"portee": 1600.0}},
			"attaches": [],
			"forme": { "gain_jugement": gain_jugement, "plafond_jugement": 10.0 },
			"poids_verbes": poids_verbes,
			"etats": {
				"peur": {
					"charge": 0.0, "seuil": seuil, "portee_charge": 900.0,
					"taux_decroissance": 1.0, "poser": { "effraye": true },
				},
			},
		},
		"action_en_cours": {},
	}

func _prudent() -> Dictionary:
	return _colon_charge(1.0, 8.0, { "approcher": 1.0, "se_proteger": 1.0, "s_eloigner": 0.0 })

func _peureux() -> Dictionary:
	return _colon_charge(2.0, 3.0, { "approcher": 1.0, "se_proteger": 0.0, "s_eloigner": 1.0 })

# 1 feu a distance nulle (saillance exacte = saillance_intrinseque = 3.0)
# + 1 abri a portee -- meme geometrie que test_banc_feu.gd:_monde_avec_feux.
func _monde_avec_feu_et_abri() -> Monde:
	var monde := Monde.new()
	var feu := Objet.fabriquer("feu_0", "feu", Vector3.ZERO, TYPES)
	monde.ajouter(feu, "feu", Vector3.ZERO)
	var abri := Objet.fabriquer("abri", "abri", Vector3(50, 0, 0), TYPES)
	monde.ajouter(abri, "abri", abri.position)
	return monde

func _peu_de_feux_les_deux_eteignent() -> void:
	var monde := _monde_avec_feu_et_abri()
	var r_prudent := BancCharge.decider(_prudent(), monde, CATALOGUE_CANAUX, {}, PROFILS_SAILLANCE, CATALOGUE_DEFORMATIONS, JUGEMENTS, CATALOGUE, DECLENCHEUR_INTERNE, INTENSITE_INTERNE)
	var r_peureux := BancCharge.decider(_peureux(), monde, CATALOGUE_CANAUX, {}, PROFILS_SAILLANCE, CATALOGUE_DEFORMATIONS, JUGEMENTS, CATALOGUE, DECLENCHEUR_INTERNE, INTENSITE_INTERNE)

	verif.v(r_prudent.decision != null and r_prudent.decision.action == "approcher",
		"avant toute bascule (effraye absent), le prudent doit eteindre")
	verif.v(r_peureux.decision != null and r_peureux.decision.action == "approcher",
		"avant toute bascule (effraye absent), le peureux doit ENCORE eteindre -- son seuil bas ne suffit pas seul, sans exposition")

func _exposition_prolongee_bascule_le_peureux_avant_le_prudent() -> void:
	var peureux := _peureux()
	var prudent := _prudent()
	var feu := Objet.fabriquer("feu_expo", "feu", Vector3.ZERO, TYPES)
	var causes := [{"position": Vector3.ZERO}]
	var monde_accum := [peureux, prudent, feu]

	for i in 4:
		Charge.avancer(monde_accum, causes, 1.0)
	verif.v(peureux.proprietes.get("effraye", false),
		"apres 4 ticks d'exposition (charge 4.0 > seuil 3.0), le peureux doit avoir bascule")
	verif.v(not prudent.proprietes.get("effraye", false),
		"apres 4 ticks d'exposition (charge 4.0 < seuil 8.0), le prudent ne doit pas encore avoir bascule")

	var monde_decider := _monde_avec_feu_et_abri()
	var r_peureux := BancCharge.decider(peureux, monde_decider, CATALOGUE_CANAUX, {}, PROFILS_SAILLANCE, CATALOGUE_DEFORMATIONS, JUGEMENTS, CATALOGUE, DECLENCHEUR_INTERNE, INTENSITE_INTERNE)
	var r_prudent := BancCharge.decider(prudent, monde_decider, CATALOGUE_CANAUX, {}, PROFILS_SAILLANCE, CATALOGUE_DEFORMATIONS, JUGEMENTS, CATALOGUE, DECLENCHEUR_INTERNE, INTENSITE_INTERNE)
	verif.v(r_peureux.decision != null and r_peureux.decision.action == "s_eloigner",
		"effraye pose, le peureux doit fuir (poids_verbes favorise s_eloigner chez lui)")
	verif.v(r_prudent.decision != null and r_prudent.decision.action == "approcher",
		"pas encore effraye, le prudent doit encore eteindre")

	for i in 5:
		Charge.avancer(monde_accum, causes, 1.0)
	verif.v(prudent.proprietes.get("effraye", false),
		"apres 9 ticks d'exposition (charge 9.0 > seuil 8.0), le prudent doit avoir bascule a son tour")
	var r_prudent2 := BancCharge.decider(prudent, monde_decider, CATALOGUE_CANAUX, {}, PROFILS_SAILLANCE, CATALOGUE_DEFORMATIONS, JUGEMENTS, CATALOGUE, DECLENCHEUR_INTERNE, INTENSITE_INTERNE)
	verif.v(r_prudent2.decision != null and r_prudent2.decision.action == "se_proteger",
		"effraye pose chez le prudent, il doit se proteger (poids_verbes favorise se_proteger chez lui, pas s_eloigner)")

func _sans_cause_la_charge_redescend_et_effraye_se_retire() -> void:
	var peureux := _peureux()
	var causes := [{"position": Vector3.ZERO}]
	var monde_accum := [peureux]

	for i in 4:
		Charge.avancer(monde_accum, causes, 1.0)
	verif.v(peureux.proprietes.get("effraye", false),
		"le peureux doit d'abord basculer sous exposition, avant de pouvoir en descendre")

	for i in 4:
		Charge.avancer(monde_accum, [], 1.0)
	verif.v(not peureux.proprietes.get("effraye", false),
		"sans plus aucune cause a portee, la charge doit redescendre sous le seuil et retirer effraye")

	var monde_nouveau_feu := _monde_avec_feu_et_abri()
	var r := BancCharge.decider(peureux, monde_nouveau_feu, CATALOGUE_CANAUX, {}, PROFILS_SAILLANCE, CATALOGUE_DEFORMATIONS, JUGEMENTS, CATALOGUE, DECLENCHEUR_INTERNE, INTENSITE_INTERNE)
	verif.v(r.decision != null and r.decision.action == "approcher",
		"effraye retire, le peureux doit revenir eteindre un nouveau feu percu")

# LA serrure hors domaine : "rayonnement"/"contamine"/"bunker" n'ont aucun
# rapport avec le feu ni la peur, et ne sont vus nulle part ailleurs dans
# le depot. "contamine" est pose directement sur le colon (simule une
# charge deja basculee, sans repasser par charge.gd -- deja verrouille
# par test_charge.gd) pour isoler ce que CE fichier doit prouver :
# decider() ne lit ni "brule", ni "effraye", ni "refuge" en dur.
func _hors_domaine_decider_ignore_le_domaine() -> void:
	var types_invente := {
		"rayonnement": { "profil_saillance": "rayonnement", "irradie": true },
		"bunker": { "refuge_invente": true },
	}
	var profils_invente := {
		"rayonnement": { "saillance_intrinseque": 3.0, "portee_saillance": 900.0 },
	}
	var jugements_invente := { "refuge_invente": "contamine" }
	var catalogue_invente := {
		"irradie": { "verbes": ["approcher"] },
		"refuge_invente": { "verbes": ["se_proteger", "s_eloigner"] },
	}
	var colon := _colon_charge(2.0, 3.0, { "approcher": 1.0, "se_proteger": 0.0, "s_eloigner": 1.0 })
	colon.proprietes["contamine"] = true

	var monde := Monde.new()
	var source := Objet.fabriquer("source", "rayonnement", Vector3.ZERO, types_invente)
	monde.ajouter(source, "rayonnement", Vector3.ZERO)
	var bunker := Objet.fabriquer("bunker", "bunker", Vector3(50, 0, 0), types_invente)
	monde.ajouter(bunker, "bunker", bunker.position)

	var r := BancCharge.decider(colon, monde, CATALOGUE_CANAUX, {}, profils_invente, {}, jugements_invente, catalogue_invente, "contamine", 4.0)
	verif.v(r.decision != null and r.decision.action == "s_eloigner",
		"un canal/declencheur invente (rayonnement/contamine/bunker) doit traverser le meme cablage sans ligne ajoutee")

# Meme geste que banc_charge.gd:_ready pour construire _catalogue_types :
# catalogue local (eau/pierre/feu) + dynamique/percevant/agent/colon
# fusionnes depuis data/types.json par-dessus (refonte "eclatement du
# corps interne", plus un paquet unique "entite"). Duplique volontairement
# ces quelques lignes de _ready plutot que d'instancier la scene entiere --
# meme choix que test_banc_p1.gd:_catalogue_types_reel pour les reserves
# (PHASE 2).
func _catalogue_types_reel() -> Dictionary:
	var banc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_charge.json"))
	var types: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/types.json"))
	var catalogue: Dictionary = banc.get("types", {}).duplicate(true)
	catalogue["dynamique"] = types.get("dynamique", {})
	catalogue["percevant"] = types.get("percevant", {})
	catalogue["agent"] = types.get("agent", {})
	catalogue["colon"] = types.get("colon", {})
	return catalogue

# PHASE 3 piece 2 : Objet.fabriquer directement contre data/types.json lu
# sur disque -- verrouille que "colon" y porte bien etats.peur au complet
# (herite_entite), independamment de tout cablage de banc.
func _colon_reel_herite_de_etats_peur_de_colon() -> void:
	var types: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/types.json"))
	var colon := Objet.fabriquer("c1", "colon", Vector3.ZERO, types)
	var peur: Dictionary = colon.proprietes.get("etats", {}).get("peur", {})
	verif.v(peur.get("portee_charge", -1.0) == 900.0,
		"colon reel doit heriter portee_charge 900.0 de data/types.json:colon.etats.peur")
	verif.v(peur.get("taux_decroissance", -1.0) == 1.0,
		"colon reel doit heriter taux_decroissance 1.0 de data/types.json:colon.etats.peur")
	verif.v(peur.get("poser", {}) == {"effraye": true},
		"colon reel doit heriter poser {effraye: true} de data/types.json:colon.etats.peur")
	verif.v(peur.get("charge", -1.0) == 0.0,
		"colon reel doit demarrer a charge 0.0 (valeur de type, data/types.json)")

# Chemin reel COMPLET de banc_charge.gd (_fabriquer_colon_charge) sur les
# donnees telles qu'elles vivent sur le disque : prudent et peureux doivent
# recevoir le MEME canal herite (portee_charge/taux_decroissance/poser)
# mais chacun son propre seuil (surcharge, data/banc_charge.json), sans
# jamais partager le meme Dictionary etats.peur entre les deux colons --
# sinon muter l'un via decider()/Charge.avancer muterait l'autre en silence.
func _colons_reels_surchargent_le_seuil_sans_partager_reference() -> void:
	var catalogue := _catalogue_types_reel()
	var banc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_charge.json"))
	var decl_prudent: Dictionary = banc.colons.prudent
	var decl_peureux: Dictionary = banc.colons.peureux
	var prudent := BancCharge._fabriquer_colon_charge("prudent", "colon", decl_prudent, catalogue)
	var peureux := BancCharge._fabriquer_colon_charge("peureux", "colon", decl_peureux, catalogue)

	verif.v(prudent.proprietes.etats.peur.seuil == 8.0,
		"prudent reel doit surcharger seuil a 8.0 (data/banc_charge.json)")
	verif.v(peureux.proprietes.etats.peur.seuil == 3.0,
		"peureux reel doit surcharger seuil a 3.0 (data/banc_charge.json)")
	verif.v(prudent.proprietes.etats.peur.portee_charge == 900.0 and peureux.proprietes.etats.peur.portee_charge == 900.0,
		"les deux colons reels doivent heriter le meme portee_charge, jamais duplique dans data/banc_charge.json")
	verif.v(not is_same(prudent.proprietes.etats.peur, peureux.proprietes.etats.peur),
		"prudent et peureux ne doivent jamais partager le meme Dictionary etats.peur")
	prudent.proprietes.etats.peur.seuil = 999.0
	verif.v(peureux.proprietes.etats.peur.seuil == 3.0,
		"muter le seuil surcharge de prudent ne doit jamais affecter peureux (pas de reference partagee)")

# Chemin reel COMPLET, bout en bout : deux colons FABRIQUES via
# _fabriquer_colon_charge (donc avec leur seuil surcharge depuis
# data/banc_charge.json, pas une fixture locale comme _colon_charge())
# exposes au meme feu par Charge.avancer -- doivent basculer effraye a des
# expositions DIFFERENTES selon leur propre seuil, exactement comme avant
# PHASE 3 (meme scenario/memes seuils/memes ticks que
# _exposition_prolongee_bascule_le_peureux_avant_le_prudent, mais sur les
# colons REELLEMENT fabriques plutot que sur la fixture locale -- preuve
# que le renommage + l'extraction vers types.json n'a rien change au
# comportement observable du banc).
func _colon_reel_avec_surcharge_de_seuil_bascule_effraye_selon_seuil() -> void:
	var catalogue := _catalogue_types_reel()
	var banc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_charge.json"))
	var decl_prudent: Dictionary = banc.colons.prudent
	var decl_peureux: Dictionary = banc.colons.peureux
	var prudent := BancCharge._fabriquer_colon_charge("prudent", "colon", decl_prudent, catalogue)
	var peureux := BancCharge._fabriquer_colon_charge("peureux", "colon", decl_peureux, catalogue)

	var feu := Objet.fabriquer("feu_expo", "feu", Vector3.ZERO, TYPES)
	var causes := [{"position": Vector3.ZERO}]
	var monde := [prudent, peureux, feu]

	for i in 4:
		Charge.avancer(monde, causes, 1.0)
	verif.v(peureux.proprietes.get("effraye", false),
		"le colon reel peureux (seuil 3.0 surcharge) doit avoir bascule apres 4 ticks d'exposition")
	verif.v(not prudent.proprietes.get("effraye", false),
		"le colon reel prudent (seuil 8.0 surcharge) ne doit pas encore avoir bascule apres 4 ticks")

	for i in 5:
		Charge.avancer(monde, causes, 1.0)
	verif.v(prudent.proprietes.get("effraye", false),
		"le colon reel prudent doit basculer a son tour apres 9 ticks d'exposition (charge 9.0 > seuil 8.0)")

# Audit couverture 2026-08-06 : _couleur_de/_etiquette_decision/
# _faire_agir_colon sont des fonctions INSTANCE, aucune appelee par un
# test avant cette session. Meme patron que test_banc_p1.gd :
# BancCharge.new() nu, jamais ajoute a l'arbre, champs prives poses a la
# main pour chaque scenario.

func _couleur_de_lit_le_type_pose_jamais_le_defaut() -> void:
	var b := BancCharge.new()
	b._couleurs_types = {"feu": [0.9, 0.2, 0.1], "abri": [0.1, 0.6, 0.9]}
	verif.v(b._couleur_de("feu") == Color(0.9, 0.2, 0.1), "doit rendre la couleur posee pour 'feu', pas le defaut blanc")
	verif.v(b._couleur_de("abri") == Color(0.1, 0.6, 0.9), "doit distinguer deux types poses")
	verif.v(b._couleur_de("inconnu") == Color(1.0, 1.0, 1.0), "un type absent doit rendre le blanc par defaut, jamais alarmer")

# Difference avec banc_p1.gd:_etiquette_decision (audit croise, meme
# session) : ICI, une "chose" non-Dictionary retombe sur decision.type --
# banc_p1.gd, lui, rend la chose telle quelle. Verrouille CE comportement
# precis, propre a ce fichier -- une fusion future des deux ne doit pas
# passer inapercue sans faire tomber ce test.
func _etiquette_decision_cas() -> void:
	var b := BancCharge.new()
	verif.v(b._etiquette_decision({"type": "refuge", "chose": {"id": "abri_1"}}) == "abri_1",
		"chose Dictionary avec id : doit rendre l'id de la chose")
	verif.v(b._etiquette_decision({"type": "refuge", "chose": {}}) == "refuge",
		"chose Dictionary sans id : doit retomber sur decision.type")
	verif.v(b._etiquette_decision({"type": "brule", "chose": "feu_2"}) == "brule",
		"chose non-Dictionary : ici, retombe sur decision.type (different de banc_p1.gd)")
	verif.v(b._etiquette_decision({"type": "brule", "chose": null}) == "brule",
		"chose absente (null) : doit retomber sur decision.type")

func _faire_agir_colon_sans_feu_rend_rien_et_ne_bouge_pas() -> void:
	var b := BancCharge.new()
	b._monde = Monde.new()
	b._catalogue_canaux = CATALOGUE_CANAUX
	b._menaces = {}
	b._profils_saillance = PROFILS_SAILLANCE
	b._catalogue_deformations = CATALOGUE_DEFORMATIONS
	b._jugements = JUGEMENTS
	b._catalogue_actions = CATALOGUE
	b._orientations = ORIENTATIONS
	b._declencheur_interne = DECLENCHEUR_INTERNE
	b._intensite_interne = INTENSITE_INTERNE
	var colon := _peureux()
	colon.proprietes["vitesse"] = 150.0
	colon["action_precedente"] = ""
	b._faire_agir_colon(colon, 0.1)
	verif.v(colon.action_precedente == "RIEN", "sans feu, l'etiquette doit etre RIEN")
	verif.v(colon.position == Vector3.ZERO, "sans feu, le colon ne doit pas bouger")

func _faire_agir_colon_avec_feu_deplace_le_colon_et_redessine_le_noeud() -> void:
	var b := BancCharge.new()
	b._monde = _monde_avec_feu_et_abri()
	b._catalogue_canaux = CATALOGUE_CANAUX
	b._menaces = {}
	b._profils_saillance = PROFILS_SAILLANCE
	b._catalogue_deformations = CATALOGUE_DEFORMATIONS
	b._jugements = JUGEMENTS
	b._catalogue_actions = CATALOGUE
	b._orientations = ORIENTATIONS
	b._declencheur_interne = DECLENCHEUR_INTERNE
	b._intensite_interne = INTENSITE_INTERNE
	var colon := _peureux()
	colon.proprietes["vitesse"] = 150.0
	colon["position"] = Vector3(500, 0, 0)
	colon["action_precedente"] = ""
	var noeud := ColorRect.new()
	noeud.size = Vector2(24.0, 24.0)
	b._noeuds["colon_test"] = noeud

	b._faire_agir_colon(colon, 0.1)

	verif.v(colon.action_precedente != "RIEN", "avec un feu a portee, l'etiquette ne doit pas rester RIEN")
	verif.v(colon.position != Vector3(500, 0, 0), "avec un feu a portee, le colon doit s'etre deplace")
	var attendu := Vector2(colon.position.x, colon.position.y) - noeud.size / 2.0
	verif.v(noeud.position.distance_to(attendu) < 0.001,
		"le noeud de rendu doit suivre la nouvelle position du colon")
