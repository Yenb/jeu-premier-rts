extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_feu.gd
#
# Verrouille le cablage de banc_feu.gd, en particulier decider() : PREMIER
# pipeline reel a inclure jugement.gd (perception -> attaches + proximite
# -> jugement -> dominance -> agir). La logique reelle est testee via cette
# fonction STATIQUE (jamais via _process/_unhandled_input -- CLAUDE.md,
# Regle d'etat : "le clic ou la boucle ne fait que declencher, jamais
# calculer").
#
# Deux colons, memes couches, seul gain_jugement differe (0.2 vs 0.8) :
# - a UN feu (pression = 3.0, feu.saillance_intrinseque), l'abri
#   (jugement) reste sous le feu (proximite, ~3.0) pour les DEUX colons --
#   les deux retiennent encore "approcher".
# - a TROIS feux (pression = 9.0), le gain-haut (0.8 * 9.0 = 7.2 > 3.0)
#   bascule : l'abri domine, poids_verbes favorise s_eloigner chez lui --
#   "s_eloigner". Le gain-bas (0.2 * 9.0 = 1.8 < 3.0) reste sous le feu :
#   "approcher" encore.
#
# _hors_domaine_decider_ignore_le_domaine() verrouille que decider()
# (le cablage neuf de ce banc) ne code aucun nom en dur : un couple
# jugee/declencheur invente (eclair/paratonnerre), sans aucun rapport avec
# le feu ni l'abri, traverse le meme cablage.
#
# _bascule_peureux_par_mouvement_reel() est le premier test DYNAMIQUE
# (chantier "test dynamique", scripts/boucle.gd) : le colon avance
# reellement, tick apres tick, par decider_et_memoriser + bouger_vers/
# bouger_selon reels (jamais une saillance truquee a la main comme dans
# _inertie_tient_sur_deux_ticks_via_decider_et_memoriser ci-dessous). La
# bascule approcher -> s_eloigner nait du mouvement lui-meme (la pression
# de jugement croit a mesure que le colon approche du foyer de feux), et
# reste verrouillee (jamais un flottement) par gain_inertie -- calibre
# empiriquement, voir le commentaire de la fonction.
#
# _mesure_reel_bascule_vers_se_proteger_a_cinq_feux() ferme le point 1 de
# docs/ETAT.md, §OUVERT : troisieme colon, "mesure" (gain_jugement 0.24,
# poids_verbes se_proteger 1.0 / s_eloigner 0.5), qui pese LES DEUX verbes
# que propose "abrite" au lieu d'un seul -- se_proteger l'emporte des que
# l'abri domine, jamais atteint par prudent (gain trop bas) ni peureux
# (poids nul sur se_proteger). CHEMIN REEL : le colon "mesure" est
# fabrique via BancCommun.fabriquer_colon contre data/banc_feu.json lu sur
# disque (JSON.parse_string(FileAccess.get_file_as_string(...)), meme
# idiome que test_banc_charge.gd:_catalogue_types_reel) -- jamais une
# fixture locale qui recopierait a la main gain_jugement/poids_verbes,
# sinon rien ne verrouille que LA DONNEE REELLE produit la bascule.
# Calibre a distance nulle (comme _monde_avec_feux) : pression = n * 3.0
# (feu.saillance_intrinseque) ; a 4 feux, 4*3.0*0.24=2.88 < 3.0 (encore
# sous le feu, approcher) ; a 5 feux, 5*3.0*0.24=3.6 > 3.0 (l'abri domine,
# se_proteger).

const BancFeu = preload("res://scripts/banc_feu.gd")
const Boucle = preload("res://scripts/boucle.gd")
const Monde = preload("res://scripts/monde.gd")
const Objet = preload("res://scripts/objet.gd")
const Verif = preload("res://scripts/verif.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")

var verif := Verif.new()

const TYPES := {
	"feu": { "profil_saillance": "feu", "brule": true },
	"abri": { "abrite": true },
}
# Catalogue de profils de saillance (equivalent local a
# data/profils_saillance.json), resolu par "feu": { "profil_saillance": "feu" }
# ci-dessus -- voir scripts/proximite.gd. "feu_intense" sert uniquement a
# _inertie_tient_sur_deux_ticks_via_decider_et_memoriser, ou feu_b doit
# devenir plus saillant que feu_a SANS muter le profil partage.
const PROFILS_SAILLANCE := {
	"feu": { "saillance_intrinseque": 3.0, "portee_saillance": 900.0 },
	"feu_intense": { "saillance_intrinseque": 3.5, "portee_saillance": 900.0 },
}
const JUGEMENTS := { "abrite": "brule" }
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
	"abrite": { "verbes": ["se_proteger", "s_eloigner"] },
}
# data/orientations.json, recopiee ici comme TYPES/JUGEMENTS/CATALOGUE
# ci-dessus (ce test ne charge aucun JSON, il mirrorre les tables reelles).
const ORIENTATIONS := { "se_proteger": "jugee", "s_eloigner": "fuite" }

func _init() -> void:
	_faible_pression_les_deux_eteignent()
	_forte_pression_gain_haut_bascule_gain_bas_reste()
	_hors_domaine_decider_ignore_le_domaine()
	_inertie_tient_sur_deux_ticks_via_decider_et_memoriser()
	_bascule_peureux_par_mouvement_reel()
	_mesure_reel_bascule_vers_se_proteger_a_cinq_feux()
	_couleur_de_lit_le_type_pose_jamais_le_defaut()
	_etiquette_decision_cas()
	_faire_agir_colon_sans_feu_rend_rien_et_ne_bouge_pas()
	_faire_agir_colon_avec_feu_deplace_le_colon_et_redessine_le_noeud()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: a 1 feu les deux eteignent, a 3 feux le gain-haut fuit tandis que " +
		"le gain-bas eteint encore, domaine invente traverse le meme cablage, " +
		"l'inertie tient sur deux ticks via decider_et_memoriser, " +
		"la bascule tient sur 20 ticks de mouvement reel via boucle.gd, " +
		"et le mesure (chemin reel) se protege vers l'abri a partir de 5 feux")
	quit(0)

func _colon(gain_jugement: float, poids_verbes: Dictionary) -> Dictionary:
	return {
		"position": Vector3.ZERO,
		"proprietes": {
			"canaux": ["vue"], "canaux_config": {"vue": {"portee": 1600.0}},
			"attaches": [],
			"forme": { "gain_jugement": gain_jugement, "plafond_jugement": 20.0 },
			"poids_verbes": poids_verbes,
		},
		"action_en_cours": {},
	}

func _prudent() -> Dictionary:
	return _colon(0.2, { "approcher": 1.0, "se_proteger": 1.0, "s_eloigner": 0.0 })

func _peureux() -> Dictionary:
	return _colon(0.8, { "approcher": 1.0, "se_proteger": 0.0, "s_eloigner": 1.0 })

# N feux, tous a distance nulle du colon (facteur = 1.0, saillance exacte
# = saillance_intrinseque = 3.0 chacun -- deterministe, sans arrondi de
# distance) + un abri a portee.
func _monde_avec_feux(n: int) -> Monde:
	var monde := Monde.new()
	for i in n:
		var feu := Objet.fabriquer("feu_%d" % i, "feu", Vector3.ZERO, TYPES)
		monde.ajouter(feu, "feu", Vector3.ZERO)
	var abri := Objet.fabriquer("abri", "abri", Vector3(50, 0, 0), TYPES)
	monde.ajouter(abri, "abri", abri.position)
	return monde

func _faible_pression_les_deux_eteignent() -> void:
	var monde := _monde_avec_feux(1)
	var r_prudent := BancFeu.decider(_prudent(), monde, CATALOGUE_CANAUX, {}, PROFILS_SAILLANCE, CATALOGUE_DEFORMATIONS, JUGEMENTS, CATALOGUE)
	var r_peureux := BancFeu.decider(_peureux(), monde, CATALOGUE_CANAUX, {}, PROFILS_SAILLANCE, CATALOGUE_DEFORMATIONS, JUGEMENTS, CATALOGUE)

	verif.v(r_prudent.decision != null and r_prudent.decision.action == "approcher",
		"a 1 feu, le prudent (gain 0.2) doit encore eteindre")
	verif.v(r_peureux.decision != null and r_peureux.decision.action == "approcher",
		"a 1 feu, le peureux (gain 0.8) doit ENCORE eteindre -- son gain haut ne suffit pas seul")

func _forte_pression_gain_haut_bascule_gain_bas_reste() -> void:
	var monde := _monde_avec_feux(3)
	var r_prudent := BancFeu.decider(_prudent(), monde, CATALOGUE_CANAUX, {}, PROFILS_SAILLANCE, CATALOGUE_DEFORMATIONS, JUGEMENTS, CATALOGUE)
	var r_peureux := BancFeu.decider(_peureux(), monde, CATALOGUE_CANAUX, {}, PROFILS_SAILLANCE, CATALOGUE_DEFORMATIONS, JUGEMENTS, CATALOGUE)

	verif.v(r_prudent.decision != null and r_prudent.decision.action == "approcher",
		"a 3 feux, le gain-bas doit ENCORE eteindre -- 0.2 * 9.0 = 1.8, sous le feu (3.0)")
	verif.v(r_peureux.decision != null and r_peureux.decision.action == "s_eloigner",
		"a 3 feux, le gain-haut doit basculer -- 0.8 * 9.0 = 7.2, au-dessus du feu (3.0), " +
		"et son poids favorise s_eloigner sur l'abri")

# LA serrure hors domaine : "eclair"/"charge"/"paratonnerre"/"protege"
# n'ont aucun rapport avec le feu ni l'abri, et ne sont vus nulle part
# ailleurs dans le depot. Si ce test passe, decider() (le cablage propre a
# ce banc) ne code aucun nom en dur.
func _hors_domaine_decider_ignore_le_domaine() -> void:
	var types_inventes := {
		"eclair": { "profil_saillance": "eclair", "charge": true },
		"paratonnerre": { "protege": true },
	}
	var profils_saillance_invente := {
		"eclair": { "saillance_intrinseque": 3.0, "portee_saillance": 900.0 },
	}
	var jugements_inventes := { "protege": "charge" }
	var catalogue_invente := {
		"charge": { "verbes": ["approcher"] },
		"protege": { "verbes": ["se_proteger", "s_eloigner"] },
	}
	var monde := Monde.new()
	for i in 3:
		var eclair := Objet.fabriquer("eclair_%d" % i, "eclair", Vector3.ZERO, types_inventes)
		monde.ajouter(eclair, "eclair", Vector3.ZERO)
	var paratonnerre := Objet.fabriquer("paratonnerre", "paratonnerre", Vector3(50, 0, 0), types_inventes)
	monde.ajouter(paratonnerre, "paratonnerre", paratonnerre.position)

	var r := BancFeu.decider(_peureux(), monde, CATALOGUE_CANAUX, {}, profils_saillance_invente, {}, jugements_inventes, catalogue_invente)
	verif.v(r.decision != null and r.decision.action == "s_eloigner",
		"un domaine invente (eclair/paratonnerre) doit traverser le meme cablage sans ligne ajoutee")

# Verrou du fil decider_et_memoriser LUI-MEME, pas de decider()/etat_courant()
# rejoues a la main depuis le test -- le test appelle la fonction que
# _faire_agir_colon appelle, jamais une reimplementation du geste (sinon rien
# ne prouve que le cablage reel memorise). Deux feux a distance nulle du
# colon (facteur = 1.0, comme _monde_avec_feux) : egalite stricte au tick 1,
# choisir() retient feu_a (premier element, comparaison stricte ">"). Entre
# les deux ticks, feu_b monte a 3.5 (delta 0.5), sous gain_inertie (1.0,
# valeur reelle de data/banc_feu.json) : sans memorisation feu_b l'emporterait
# au tick 2 (3.5 > 3.0) -- avec, feu_a tient (3.0 + 1.0 = 4.0 > 3.5). Retirer
# la ligne d'ecriture DANS decider_et_memoriser fait tomber ce test au rouge.
func _inertie_tient_sur_deux_ticks_via_decider_et_memoriser() -> void:
	var colon := {
		"position": Vector3.ZERO,
		"proprietes": {
			"canaux": ["vue"], "canaux_config": {"vue": {"portee": 1600.0}},
			"attaches": [],
			"forme": { "gain_inertie": 1.0 },
			"poids_verbes": { "approcher": 1.0 },
		},
		"action_en_cours": {},
	}
	var monde := Monde.new()
	var feu_a := Objet.fabriquer("feu_a", "feu", Vector3.ZERO, TYPES)
	var feu_b := Objet.fabriquer("feu_b", "feu", Vector3.ZERO, TYPES)
	monde.ajouter(feu_a, "feu", Vector3.ZERO)
	monde.ajouter(feu_b, "feu", Vector3.ZERO)

	var r1 := BancFeu.decider_et_memoriser(colon, monde, CATALOGUE_CANAUX, {}, PROFILS_SAILLANCE, CATALOGUE_DEFORMATIONS, JUGEMENTS, CATALOGUE)
	verif.v(r1.decision != null and r1.decision.chose.id == "feu_a",
		"tick 1, egalite stricte (3.0 == 3.0) : le premier feu (feu_a) doit etre retenu")

	# Une reference de catalogue ne se surcharge pas par instance : pour
	# faire monter la saillance de feu_b SEUL, on le fait pointer vers un
	# profil distinct ("feu_intense", voir PROFILS_SAILLANCE) plutot que
	# muter saillance_intrinseque sur l'instance, qui n'existe plus.
	feu_b.proprietes.profil_saillance = "feu_intense"

	var r2 := BancFeu.decider_et_memoriser(colon, monde, CATALOGUE_CANAUX, {}, PROFILS_SAILLANCE, CATALOGUE_DEFORMATIONS, JUGEMENTS, CATALOGUE)
	verif.v(r2.decision != null and r2.decision.chose.id == "feu_a",
		"tick 2, feu_b monte a 3.5 (delta 0.5 < gain_inertie 1.0) : l'inertie doit garder feu_a")

# Geometrie choisie pour que le MOUVEMENT REEL (jamais une saillance posee a
# la main) produise la bascule : feu_a et feu_b sont alignes sur l'axe X,
# le colon avance vers feu_a (le plus proche, retenu des le premier tick) ;
# feu_b, plus lointain au depart, entre progressivement dans
# portee_saillance (900) a mesure que le colon approche de feu_a. Sa
# saillance s'ajoute a la PRESSION de jugement (jugement.gd:_pression) sans
# jamais entrer dans le calcul de la saillance de feu_a lui-meme -- la
# pression (feu_a + feu_b) croit donc plus vite que la seule saillance de
# feu_a, jusqu'a ce que l'abri (pression * gain_jugement) la depasse.
# Calibre empiriquement (harnais jetable, non conserve) : bascule au
# tick 13/20, jamais de retour a "approcher" ensuite dans la fenetre testee.
const FEU_A := Vector3(400.0, 0.0, 0.0)
const FEU_B := Vector3(600.0, 0.0, 0.0)
const ABRI := Vector3(400.0, 300.0, 0.0)
const DEPART := Vector3(-300.0, 0.0, 0.0)

func _monde_convergence() -> Monde:
	var monde := Monde.new()
	var feu_a := Objet.fabriquer("feu_a", "feu", FEU_A, TYPES)
	var feu_b := Objet.fabriquer("feu_b", "feu", FEU_B, TYPES)
	var abri := Objet.fabriquer("abri", "abri", ABRI, TYPES)
	monde.ajouter(feu_a, "feu", FEU_A)
	monde.ajouter(feu_b, "feu", FEU_B)
	monde.ajouter(abri, "abri", ABRI)
	return monde

# Meme peureux que _peureux() (gain_jugement 0.8), avec en plus une
# position de depart, proprietes.vitesse et forme.gain_inertie --
# STRUCTURELLES/lues par scripts/boucle.gd et agir.gd, absentes de
# _peureux() qui ne sert qu'a des decider() statiques sur UN seul tick,
# jamais a un deplacement reel ni a une inertie exercee sur plusieurs
# tours (gain_inertie a 0.0, valeur facultative par defaut, y serait
# invisible). vitesse=150.0 et gain_inertie=1.0 : valeurs REELLES de
# data/banc_feu.json (type "colon" ; colon "peureux").
func _peureux_mobile() -> Dictionary:
	var colon := _peureux()
	colon.position = DEPART
	colon.proprietes["vitesse"] = 150.0
	colon.proprietes.forme["gain_inertie"] = 1.0
	return colon

static func _cle_action(decision) -> String:
	if decision == null:
		return "<rien>"
	return String(decision.get("action", ""))

# Verrou du canal REEL de l'oscillation (chantier "test dynamique") : le
# peureux commence par APPROCHER (feu_a domine), puis BASCULE vers
# s_eloigner une fois la pression des deux feux au-dessus de l'abri --
# jamais l'inverse ensuite, gain_inertie (1.0, valeur reelle de
# data/banc_feu.json) verrouillant la nouvelle tache exactement comme
# l'ancienne. Aucune position ni saillance n'est posee a la main : tout
# vient de decider_et_memoriser + bouger_vers/bouger_selon reels, drives
# par Boucle.tracer (scripts/boucle.gd).
func _bascule_peureux_par_mouvement_reel() -> void:
	var monde := _monde_convergence()
	var colon := _peureux_mobile()
	var geste := Callable(BancFeu, "agir_et_deplacer").bind(monde, CATALOGUE_CANAUX, {}, PROFILS_SAILLANCE, CATALOGUE_DEFORMATIONS, JUGEMENTS, CATALOGUE, ORIENTATIONS, 0.3)
	var trace := Boucle.tracer(colon, 20, geste)

	verif.v(trace[0] != null and trace[0].action == "approcher",
		"au premier tick, feu_a domine seul encore : le peureux doit eteindre")
	verif.v(trace[-1] != null and trace[-1].action == "s_eloigner",
		"apres 20 ticks de vraie approche, la pression des deux feux doit avoir fait basculer l'abri au-dessus de feu_a")

	var changements := 0
	for i in range(1, trace.size()):
		if _cle_action(trace[i]) != _cle_action(trace[i - 1]):
			changements += 1
	verif.v(changements == 1,
		("l'inertie (gain_inertie=1.0, valeur reelle) doit verrouiller une seule bascule sur toute la " +
			"trace, jamais un flottement approcher/s_eloigner -- %d changement(s) observes") % changements)

# Fabrique le colon "mesure" via le CHEMIN REEL de _ready() (BancCommun.
# fabriquer_colon contre data/banc_feu.json lu sur disque), jamais une
# fixture locale -- voir le commentaire au-dessus de
# _mesure_reel_bascule_vers_se_proteger_a_cinq_feux.
func _mesure_reel() -> Dictionary:
	var donnees: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_feu.json"))
	var catalogue_types: Dictionary = donnees.get("types", {})
	var decl: Dictionary = donnees.get("colons", {}).get("mesure", {})
	var mesure := BancCommun.fabriquer_colon("mesure", "colon", decl, catalogue_types)
	mesure.position = Vector3.ZERO
	return mesure

# Meme geometrie que _monde_avec_feux (n feux a distance nulle du colon,
# saillance exacte = saillance_intrinseque = 3.0 chacun) + un abri "eau"
# a portee -- fabrique depuis le meme catalogue reel que le colon, pour
# que toute la scene (colon compris) vienne de data/banc_feu.json.
func _monde_reel_avec_feux(catalogue_types: Dictionary, n: int) -> Monde:
	var monde := Monde.new()
	for i in n:
		var feu := Objet.fabriquer("feu_%d" % i, "feu", Vector3.ZERO, catalogue_types)
		monde.ajouter(feu, "feu", Vector3.ZERO)
	var eau := Objet.fabriquer("eau_0", "eau", Vector3(50, 0, 0), catalogue_types)
	monde.ajouter(eau, "eau", eau.position)
	return monde

func _mesure_reel_bascule_vers_se_proteger_a_cinq_feux() -> void:
	var donnees: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_feu.json"))
	var catalogue_types: Dictionary = donnees.get("types", {})

	var monde_4 := _monde_reel_avec_feux(catalogue_types, 4)
	var r4 := BancFeu.decider(_mesure_reel(), monde_4, CATALOGUE_CANAUX, {}, PROFILS_SAILLANCE, CATALOGUE_DEFORMATIONS, JUGEMENTS, CATALOGUE)
	verif.v(r4.decision != null and r4.decision.action == "approcher",
		"le mesure (chemin reel) doit encore eteindre a 4 feux -- 4*3.0*0.24=2.88, sous le feu (3.0)")

	var monde_5 := _monde_reel_avec_feux(catalogue_types, 5)
	var r5 := BancFeu.decider(_mesure_reel(), monde_5, CATALOGUE_CANAUX, {}, PROFILS_SAILLANCE, CATALOGUE_DEFORMATIONS, JUGEMENTS, CATALOGUE)
	verif.v(r5.decision != null and r5.decision.action == "se_proteger",
		"le mesure (chemin reel) doit basculer vers se_proteger a 5 feux -- 5*3.0*0.24=3.6, au-dessus du feu (3.0)")
	var cible = r5.decision.get("chose", null)
	verif.v(cible != null and cible.proprietes.get("abrite", false),
		"a 5 feux, la cible du mesure doit etre une chose 'abrite' (l'eau ici), jamais le feu")

# Audit couverture 2026-08-06 : _couleur_de/_etiquette_decision/
# _faire_agir_colon sont des fonctions INSTANCE, aucune appelee par un
# test avant cette session. Meme patron que test_banc_p1.gd/
# test_banc_charge.gd : BancFeu.new() nu, jamais ajoute a l'arbre, champs
# prives poses a la main pour chaque scenario.

func _couleur_de_lit_le_type_pose_jamais_le_defaut() -> void:
	var b := BancFeu.new()
	b._couleurs_types = {"feu": [0.9, 0.2, 0.1], "abri": [0.1, 0.6, 0.9]}
	verif.v(b._couleur_de("feu") == Color(0.9, 0.2, 0.1), "doit rendre la couleur posee pour 'feu', pas le defaut blanc")
	verif.v(b._couleur_de("abri") == Color(0.1, 0.6, 0.9), "doit distinguer deux types poses")
	verif.v(b._couleur_de("inconnu") == Color(1.0, 1.0, 1.0), "un type absent doit rendre le blanc par defaut, jamais alarmer")

# Meme comportement que banc_charge.gd (chose non-Dictionary retombe sur
# decision.type) -- different de banc_p1.gd. Verrouille CE fichier
# precisement, pas une supposition de coherence entre bancs.
func _etiquette_decision_cas() -> void:
	var b := BancFeu.new()
	verif.v(b._etiquette_decision({"type": "abrite", "chose": {"id": "abri_1"}}) == "abri_1",
		"chose Dictionary avec id : doit rendre l'id de la chose")
	verif.v(b._etiquette_decision({"type": "abrite", "chose": {}}) == "abrite",
		"chose Dictionary sans id : doit retomber sur decision.type")
	verif.v(b._etiquette_decision({"type": "brule", "chose": "feu_2"}) == "brule",
		"chose non-Dictionary : retombe sur decision.type")
	verif.v(b._etiquette_decision({"type": "brule", "chose": null}) == "brule",
		"chose absente (null) : doit retomber sur decision.type")

func _faire_agir_colon_sans_feu_rend_rien_et_ne_bouge_pas() -> void:
	var b := BancFeu.new()
	b._monde = Monde.new()
	b._catalogue_canaux = CATALOGUE_CANAUX
	b._menaces = {}
	b._profils_saillance = PROFILS_SAILLANCE
	b._catalogue_deformations = CATALOGUE_DEFORMATIONS
	b._jugements = JUGEMENTS
	b._catalogue_actions = CATALOGUE
	b._orientations = ORIENTATIONS
	var colon := _peureux()
	colon["id"] = "colon_test"
	colon.proprietes["vitesse"] = 150.0
	colon["action_precedente"] = ""
	b._faire_agir_colon(colon, 0.1)
	verif.v(colon.action_precedente == "RIEN", "sans feu, l'etiquette doit etre RIEN")
	verif.v(colon.position == Vector3.ZERO, "sans feu, le colon ne doit pas bouger")

func _faire_agir_colon_avec_feu_deplace_le_colon_et_redessine_le_noeud() -> void:
	var b := BancFeu.new()
	b._monde = _monde_avec_feux(1)
	b._catalogue_canaux = CATALOGUE_CANAUX
	b._menaces = {}
	b._profils_saillance = PROFILS_SAILLANCE
	b._catalogue_deformations = CATALOGUE_DEFORMATIONS
	b._jugements = JUGEMENTS
	b._catalogue_actions = CATALOGUE
	b._orientations = ORIENTATIONS
	var colon := _peureux()
	colon["id"] = "colon_test"
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
